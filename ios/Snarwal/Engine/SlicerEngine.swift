import Foundation
import Observation
import SnarwalCore
import WebKit

/// Hosts the Kiri:Moto engine (ios/EngineBundle) in a hidden WKWebView.
///
/// The bundle is served over http://127.0.0.1 by LocalEngineServer rather
/// than file:// or a custom scheme, because Kiri needs module workers and
/// WASM fetches from a regular origin.
@MainActor
@Observable
final class SlicerEngine {
    enum State: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private(set) var state: State = .loading
    /// 0...1 while slicing.
    private(set) var progress: Double = 0

    let webView: WKWebView
    @ObservationIgnored private var readyWaiters: [CheckedContinuation<Void, Error>] = []

    @ObservationIgnored private var server: LocalEngineServer?

    init() {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()
        config.userContentController = controller
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        controller.add(MessageProxy(self), name: "snarwal")
        #if DEBUG
        webView.isInspectable = true
        #endif
        Task { [weak self] in
            await self?.start()
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(30))
            self?.failIfStillLoading()
        }
    }

    private func start() async {
        guard let root = Bundle.main.url(forResource: "EngineBundle", withExtension: nil) else {
            fail("Das Engine-Paket fehlt in der App (ios/EngineBundle).")
            return
        }
        let server = LocalEngineServer(root: root)
        self.server = server
        do {
            let port = try await server.start()
            webView.load(URLRequest(url: URL(string: "http://127.0.0.1:\(port)/index.html")!))
        } catch {
            fail("Die Slicing-Engine konnte nicht gestartet werden: \(error.localizedDescription)")
        }
    }

    private func fail(_ message: String) {
        state = .failed(message)
        readyWaiters.forEach { $0.resume(throwing: EngineError.engine(message)) }
        readyWaiters.removeAll()
    }

    private func failIfStillLoading() {
        guard state == .loading else { return }
        fail("Die Slicing-Engine konnte nicht gestartet werden.")
    }

    fileprivate func receive(_ body: Any) {
        guard let message = body as? [String: Any] else { return }
        if message["ready"] != nil {
            state = .ready
            readyWaiters.forEach { $0.resume() }
            readyWaiters.removeAll()
        }
        if let value = message["progress"] as? Double {
            progress = value
        }
    }

    private func waitUntilReady() async throws {
        switch state {
        case .ready: return
        case .failed(let message): throw EngineError.engine(message)
        case .loading:
            try await withCheckedThrowingContinuation { readyWaiters.append($0) }
        }
    }

    private func call(_ body: String, arguments: [String: Any]) async throws -> Any? {
        try await waitUntilReady()
        do {
            let result: Any? = try await webView.callAsyncJavaScript(body, arguments: arguments, in: nil, in: .page)
            return result
        } catch {
            // JS exceptions arrive as WKError with the message in userInfo
            let message = (error as NSError).userInfo["WKJavaScriptExceptionMessage"] as? String
            throw EngineError.engine(message ?? error.localizedDescription)
        }
    }

    struct LoadedObject {
        var name: String
        var tool: Int?
        var painted: Bool
        var mesh: Mesh
    }

    /// Reads an STL or 3MF file into meshes (3MF keeps plate positions and heads).
    func loadModel(name: String, data: Data) async throws -> [LoadedObject] {
        let result = try await call("return await snarwal.loadModel({ name, data })",
                                    arguments: ["name": name, "data": data.base64EncodedString()])
        guard let dict = result as? [String: Any], let objects = dict["objects"] as? [[String: Any]] else {
            throw EngineError.unexpectedResult
        }
        return try objects.map { object in
            guard let base64 = object["vertices"] as? String, let mesh = Mesh(base64: base64) else {
                throw EngineError.unexpectedResult
            }
            return LoadedObject(name: object["name"] as? String ?? name,
                                tool: (object["tool"] as? NSNumber)?.intValue,
                                painted: object["painted"] as? Bool ?? false,
                                mesh: mesh)
        }
    }

    struct Output {
        var gcode: String
    }

    func slice(plate: Plate, process: [String: KiriValue], heads: [HeadFilament]) async throws -> Output {
        progress = 0
        let thumbnails: [[String: Any]] = PlateThumbnail.render(plate: plate, heads: heads).map {
            ["width": $0.width, "height": $0.height, "png": $0.png.base64EncodedString()]
        }
        let objects: [[String: Any]] = plate.objects.map {
            ["vertices": $0.placedMesh().base64(), "tool": $0.tool]
        }
        let filaments: [[String: Any]] = heads.map {
            ["type": $0.material.rawValue, "color": $0.colorHex, "density": $0.material.defaults.density]
        }
        let result = try await call("return await snarwal.slice({ objects, process, filaments, thumbnails })", arguments: [
            "objects": objects,
            "process": process.mapValues(\.foundationValue),
            "filaments": filaments,
            "thumbnails": thumbnails,
        ])
        guard let dict = result as? [String: Any], let gcode = dict["gcode"] as? String else {
            throw EngineError.unexpectedResult
        }
        return Output(gcode: gcode)
    }
}

enum EngineError: LocalizedError {
    case engine(String)
    case unexpectedResult

    var errorDescription: String? {
        switch self {
        case .engine(let message): message
        case .unexpectedResult: "Die Slicing-Engine hat eine unerwartete Antwort geliefert."
        }
    }
}

/// WKUserContentController retains its handlers; this breaks the cycle.
private final class MessageProxy: NSObject, WKScriptMessageHandler {
    weak var engine: SlicerEngine?

    init(_ engine: SlicerEngine) {
        self.engine = engine
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body
        MainActor.assumeIsolated {
            engine?.receive(body)
        }
    }
}
