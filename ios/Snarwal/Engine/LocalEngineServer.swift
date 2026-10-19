import Foundation
import Network

/// Minimal static file server on the loopback interface for the engine
/// bundle. A plain http://127.0.0.1 origin is what WebKit's module
/// workers and WASM loading are known to accept; custom URL schemes are not
/// reliably allowed to start workers.
final class LocalEngineServer: @unchecked Sendable {
    private let root: URL
    private let queue = DispatchQueue(label: "snarwal.engine-server")
    private var listener: NWListener?

    init(root: URL) {
        self.root = root.standardizedFileURL
    }

    /// Starts listening on an ephemeral loopback port and returns it.
    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            self?.serve(connection)
        }
        return try await withCheckedThrowingContinuation { continuation in
            var resumed = false
            listener.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                case .failed(let error):
                    resumed = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private static let types = [
        "html": "text/html; charset=utf-8",
        "js": "text/javascript; charset=utf-8",
        "wasm": "application/wasm",
        "json": "application/json",
        "md": "text/plain; charset=utf-8",
    ]

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buffer[..<end.lowerBound], as: UTF8.self)
                self.respond(to: head, on: connection)
            } else if isComplete || buffer.count > 64 * 1024 {
                connection.cancel()
            } else {
                self.receiveRequest(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to head: String, on connection: NWConnection) {
        // "GET /kiri/worker.js HTTP/1.1"
        let parts = head.split(separator: "\r\n").first?.split(separator: " ") ?? []
        var status = "404 Not Found"
        var body = Data()
        var type = "text/plain"
        if parts.count >= 2, parts[0] == "GET" {
            let rawPath = String(parts[1].split(separator: "?").first ?? "")
            let path = (rawPath.removingPercentEncoding ?? rawPath).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let file = root.appendingPathComponent(path.isEmpty ? "index.html" : path).standardizedFileURL
            // never serve anything outside the bundle folder
            if file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file) {
                status = "200 OK"
                body = data
                type = Self.types[file.pathExtension] ?? "application/octet-stream"
            }
        }
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8) + body, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
