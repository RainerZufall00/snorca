import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let http = response as? HTTPURLResponse {
                    continuation.resume(returning: (data ?? Data(), http))
                } else {
                    continuation.resume(throwing: MoonrakerError.invalidResponse)
                }
            }.resume()
        }
    }
}

public enum MoonrakerError: Error, Equatable, LocalizedError {
    case invalidHost(String)
    case invalidResponse
    case http(status: Int, message: String)
    case printer(String)

    public var errorDescription: String? {
        switch self {
        case .invalidHost(let host): "Ungültige Adresse: \(host)"
        case .invalidResponse: "Unerwartete Antwort vom Drucker"
        case .http(let status, let message): "Drucker meldet Fehler \(status): \(message)"
        case .printer(let message): message
        }
    }
}

public struct Webcam: Equatable, Sendable {
    public var name: String
    public var service: String
    public var streamURL: URL?
    public var snapshotURL: URL?
}

public enum CameraSource: Equatable, Sendable {
    /// Extended firmware: HTML player that negotiates WebRTC itself.
    case webrtcPage(URL)
    /// A JPEG that is fresh on every request.
    case snapshot(URL)
    /// Stock firmware: JPEG that only updates after `camera.start_monitor`.
    case stockMonitor(URL)
}

/// Talks to Moonraker on the U1. The stock nginx on port 80 proxies the
/// Moonraker API; the LAN needs no authentication.
public struct MoonrakerClient: Sendable {
    public let baseURL: URL
    let transport: HTTPTransport

    /// `host`: "192.168.1.20", "U1.local", "u1.tailnet.ts.net:7125" or a full URL.
    public init(host: String, transport: HTTPTransport = URLSessionTransport()) throws {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard !trimmed.isEmpty, let url = URL(string: text), url.host != nil else {
            throw MoonrakerError.invalidHost(host)
        }
        self.baseURL = url
        self.transport = transport
    }

    func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        components.queryItems = query.isEmpty ? nil : query
        return components.url!
    }

    func json(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await transport.send(request)
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(response.statusCode) else {
            let error = object?["error"] as? [String: Any]
            throw MoonrakerError.http(status: response.statusCode, message: error?["message"] as? String ?? "")
        }
        guard let object else { throw MoonrakerError.invalidResponse }
        // the U1 answers some failures with HTTP 200 and a state field
        let result = object["result"] as? [String: Any]
        if (object["state"] as? String) == "error" || (result?["state"] as? String) == "error" {
            let message = (object["message"] as? String) ?? (result?["message"] as? String) ?? "Der Drucker hat den Auftrag abgelehnt"
            throw MoonrakerError.printer(message)
        }
        return object
    }

    func post(_ path: String, query: [URLQueryItem] = []) async throws {
        var request = URLRequest(url: url(path, query: query))
        request.httpMethod = "POST"
        _ = try await json(request)
    }

    // MARK: status

    public func status() async throws -> PrinterStatus {
        var request = URLRequest(url: url("/printer/objects/query",
                                          query: PrinterStatus.queryObjects.map { URLQueryItem(name: $0, value: nil) }))
        request.timeoutInterval = 5
        let object = try await json(request)
        guard let result = object["result"] as? [String: Any], let status = result["status"] as? [String: Any] else {
            throw MoonrakerError.invalidResponse
        }
        return PrinterStatus(objects: status)
    }

    /// Slicer estimate for a file on the printer, in seconds.
    public func estimatedTime(filename: String) async throws -> TimeInterval? {
        let object = try await json(URLRequest(url: url("/server/files/metadata", query: [URLQueryItem(name: "filename", value: filename)])))
        let result = object["result"] as? [String: Any]
        return (result?["estimated_time"] as? NSNumber)?.doubleValue
    }

    // MARK: jobs

    /// Uploads G-code to the `gcodes` root; with `start` the printer begins right away.
    public func upload(gcode: Data, filename: String, start: Bool) async throws {
        var form = MultipartForm()
        form.addField(name: "root", value: "gcodes")
        form.addField(name: "print", value: start ? "true" : "false")
        form.addFile(name: "file", filename: filename, contentType: "application/octet-stream", data: gcode)
        var request = URLRequest(url: url("/server/files/upload"))
        request.httpMethod = "POST"
        request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finalizedBody
        request.timeoutInterval = 300
        _ = try await json(request)
    }

    public func startPrint(filename: String) async throws {
        try await post("/printer/print/start", query: [URLQueryItem(name: "filename", value: filename)])
    }

    public func pause() async throws { try await post("/printer/print/pause") }
    public func resume() async throws { try await post("/printer/print/resume") }
    public func cancel() async throws { try await post("/printer/print/cancel") }

    public func run(gcode script: String) async throws {
        try await post("/printer/gcode/script", query: [URLQueryItem(name: "script", value: script)])
    }

    public func setLight(on: Bool) async throws {
        try await run(gcode: "SET_LED LED=cavity_led WHITE=\(on ? 1 : 0)")
    }

    /// 0...1
    public func setPartFan(_ speed: Double) async throws {
        try await run(gcode: "M106 S\(Int((min(max(speed, 0), 1) * 255).rounded()))")
    }

    // MARK: camera

    public func webcams() async throws -> [Webcam] {
        let object = try await json(URLRequest(url: url("/server/webcams/list")))
        let list = (object["result"] as? [String: Any])?["webcams"] as? [[String: Any]] ?? []
        return list.map { cam in
            Webcam(name: cam["name"] as? String ?? "",
                   service: cam["service"] as? String ?? "",
                   streamURL: resolve(cam["stream_url"] as? String),
                   snapshotURL: resolve(cam["snapshot_url"] as? String))
        }
    }

    func resolve(_ path: String?) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    /// Best available camera: WebRTC player, then fresh snapshots, then the
    /// stock monitor image.
    public static func cameraSource(webcams: [Webcam], baseURL: URL) -> CameraSource {
        if let cam = webcams.first(where: { $0.service.contains("webrtc") }), let stream = cam.streamURL {
            return .webrtcPage(stream)
        }
        if let snapshot = webcams.compactMap(\.snapshotURL).first {
            return .snapshot(snapshot)
        }
        return .stockMonitor(URL(string: "/server/files/camera/monitor.jpg", relativeTo: baseURL)!.absoluteURL)
    }

    /// Moonraker JSON-RPC websocket, used for `camera.start_monitor` on stock firmware.
    public var websocketURL: URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        components.path = "/websocket"
        return components.url!
    }
}

/// multipart/form-data body builder.
public struct MultipartForm {
    public let boundary: String
    public private(set) var body = Data()

    public init(boundary: String = "snarwal-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    public var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    public mutating func addField(name: String, value: String) {
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
    }

    public mutating func addFile(name: String, filename: String, contentType: String, data: Data) {
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(contentType)\r\n\r\n")
        body.append(data)
        append("\r\n")
    }

    /// Closing boundary is added lazily so fields can be appended in any order.
    public var finalizedBody: Data {
        var data = body
        data.append(Data("--\(boundary)--\r\n".utf8))
        return data
    }

    private mutating func append(_ text: String) {
        body.append(Data(text.utf8))
    }
}
