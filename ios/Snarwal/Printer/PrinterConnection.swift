import Foundation
import Observation
import SnarwalCore

/// Connection to the one U1: address, live status (polled) and commands.
@MainActor
@Observable
final class PrinterConnection {
    enum Link: Equatable {
        case notConfigured
        case connecting
        case online
        case offline(String)
    }

    private(set) var host: String
    private(set) var link: Link = .notConfigured
    private(set) var status: PrinterStatus?
    private(set) var estimatedTotal: TimeInterval?
    private(set) var camera: CameraSource?
    var lastError: String?

    @ObservationIgnored private var client: MoonrakerClient?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var estimateFile = ""
    @ObservationIgnored private var isDemo = false

    init() {
        host = UserDefaults.standard.string(forKey: "printerHost") ?? ""
        if !host.isEmpty {
            configure(host: host)
        }
    }

    var baseURL: URL? { client?.baseURL }

    func configure(host newHost: String) {
        let trimmed = newHost.trimmingCharacters(in: .whitespacesAndNewlines)
        host = trimmed
        UserDefaults.standard.set(trimmed, forKey: "printerHost")
        status = nil
        camera = nil
        estimateFile = ""
        estimatedTotal = nil
        guard let client = try? MoonrakerClient(host: trimmed) else {
            self.client = nil
            link = .notConfigured
            return
        }
        self.client = client
        link = .connecting
        startPolling()
    }

    func forget() {
        stopPolling()
        client = nil
        host = ""
        UserDefaults.standard.removeObject(forKey: "printerHost")
        link = .notConfigured
        status = nil
        camera = nil
    }

    // MARK: polling

    func startPolling() {
        guard client != nil, pollTask == nil, !isDemo else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        guard let client else { return }
        do {
            let status = try await client.status()
            self.status = status
            link = .online
            if camera == nil {
                let cams = (try? await client.webcams()) ?? []
                camera = MoonrakerClient.cameraSource(webcams: cams, baseURL: client.baseURL)
            }
            if status.state.isActive, status.filename != estimateFile {
                estimateFile = status.filename
                estimatedTotal = try? await client.estimatedTime(filename: status.filename)
            }
        } catch {
            link = .offline(error.localizedDescription)
        }
    }

    var remaining: TimeInterval? {
        status?.remaining(estimatedTotal: estimatedTotal)
    }

    #if DEBUG
    /// Fake printing state for screenshots (no network).
    func loadDemo() {
        stopPolling()
        isDemo = true
        client = try? MoonrakerClient(host: "U1.local")
        host = "U1.local"
        link = .online
        var status = PrinterStatus()
        status.state = .printing
        status.filename = "Werkstatt-Set.gcode"
        status.progress = 0.37
        status.printDuration = 2400
        status.currentLayer = 84
        status.totalLayers = 240
        status.activeTool = 1
        status.nozzles = [HeaterState(temperature: 151, target: 150), HeaterState(temperature: 219.6, target: 220),
                          HeaterState(temperature: 22, target: 0), HeaterState(temperature: 22, target: 0)]
        status.bed = HeaterState(temperature: 60.1, target: 60)
        status.partFan = 0.8
        status.lightOn = true
        status.filaments = [
            HeadFilament(tool: 0, material: .pla, colorHex: "#EDEDE8", vendor: "Snapmaker", fromPrinter: true),
            HeadFilament(tool: 1, material: .pla, colorHex: "#2A2A2A", vendor: "Snapmaker", fromPrinter: true),
            HeadFilament(tool: 2, material: .pla, colorHex: "#E8792B", vendor: "Snapmaker", fromPrinter: true),
            HeadFilament(tool: 3, material: .petg, colorHex: "#2F6FD6", fromPrinter: true, loaded: false),
        ]
        self.status = status
        estimatedTotal = 6400
    }
    #endif

    // MARK: commands

    @discardableResult
    private func perform(_ action: @escaping (MoonrakerClient) async throws -> Void) async -> Bool {
        guard let client else {
            lastError = "Kein Drucker verbunden."
            return false
        }
        do {
            try await action(client)
            await refresh()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func upload(gcode: String, filename: String, start: Bool) async -> Bool {
        await perform { try await $0.upload(gcode: Data(gcode.utf8), filename: filename, start: start) }
    }

    func pause() async { await perform { try await $0.pause() } }
    func resume() async { await perform { try await $0.resume() } }
    func cancel() async { await perform { try await $0.cancel() } }
    func setLight(_ on: Bool) async { await perform { try await $0.setLight(on: on) } }
    func setPartFan(_ speed: Double) async { await perform { try await $0.setPartFan(speed) } }
}
