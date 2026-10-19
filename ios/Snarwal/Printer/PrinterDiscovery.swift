import Foundation
import Network
import Observation

/// Finds U1 printers on the local network. The firmware advertises
/// `_snapmaker._tcp` (port 1884, MQTT) with the printer's IP in the TXT record.
@MainActor
@Observable
final class PrinterDiscovery {
    struct Found: Identifiable, Hashable {
        var id: String { name }
        var name: String
        var host: String
        var model: String?
    }

    private(set) var printers: [Found] = []
    private(set) var isSearching = false

    @ObservationIgnored private var browser: NWBrowser?

    func start() {
        guard browser == nil else { return }
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_snapmaker._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let found = results.compactMap(Self.found)
            Task { @MainActor in
                self?.printers = found.sorted { $0.name < $1.name }
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready: self?.isSearching = true
                case .failed, .cancelled: self?.isSearching = false
                default: break
                }
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        isSearching = false
    }

    nonisolated private static func found(_ result: NWBrowser.Result) -> Found? {
        guard case let .service(name, _, _, _) = result.endpoint else { return nil }
        var ip: String?
        var model: String?
        var deviceName: String?
        if case let .bonjour(record) = result.metadata {
            ip = record["ip"]
            model = record["machine_type"]
            deviceName = record["device_name"]
        }
        // without an IP in the TXT record fall back to the mDNS host name
        let host = ip.flatMap { $0.isEmpty ? nil : $0 } ?? "\(name).local"
        return Found(name: deviceName.flatMap { $0.isEmpty ? nil : $0 } ?? name, host: host, model: model)
    }
}
