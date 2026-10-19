import SnarwalCore
import SwiftUI
import UIKit
import WebKit

/// Live camera: WebRTC player page on the extended firmware, refreshed
/// JPEG snapshots otherwise.
struct CameraView: View {
    let source: CameraSource
    let websocketURL: URL?

    var body: some View {
        switch source {
        case .webrtcPage(let url):
            WebRTCPlayer(url: url)
        case .snapshot(let url):
            SnapshotView(url: url, monitorSocket: nil)
        case .stockMonitor(let url):
            SnapshotView(url: url, monitorSocket: websocketURL)
        }
    }
}

private struct WebRTCPlayer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        if view.url != url {
            view.load(URLRequest(url: url))
        }
    }
}

/// Reloads a JPEG every two seconds. On stock firmware the image only
/// updates while `camera.start_monitor` is active, which is requested over
/// Moonraker's websocket.
private struct SnapshotView: View {
    let url: URL
    let monitorSocket: URL?

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.black
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if failed {
                Label("Kein Kamerabild", systemImage: "video.slash")
                    .foregroundStyle(.white.opacity(0.8))
            } else {
                ProgressView().tint(.white)
            }
        }
        .task(id: url) {
            let monitor = monitorSocket.map { CameraMonitor(url: $0) }
            monitor?.start()
            defer { monitor?.stop() }
            while !Task.isCancelled {
                var request = URLRequest(url: url)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.timeoutInterval = 5
                let fetched = try? await URLSession.shared.data(for: request)
                if let data = fetched?.0, let next = UIImage(data: data) {
                    image = next
                    failed = false
                } else if image == nil {
                    failed = true
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

/// Keeps the stock firmware's camera monitor running via JSON-RPC.
private final class CameraMonitor {
    private let task: URLSessionWebSocketTask

    init(url: URL) {
        task = URLSession.shared.webSocketTask(with: url)
    }

    func start() {
        task.resume()
        send(method: "camera.start_monitor", params: ["domain": "lan", "interval": 1])
    }

    func stop() {
        send(method: "camera.stop_monitor", params: ["domain": "lan"])
        task.cancel(with: .normalClosure, reason: nil)
    }

    private func send(method: String, params: [String: Any]) {
        let payload: [String: Any] = ["jsonrpc": "2.0", "method": method, "params": params, "id": Int.random(in: 1...99_999)]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { _ in }
    }
}
