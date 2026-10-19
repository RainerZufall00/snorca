import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import SnarwalCore

/// Talks over real HTTP to ci/mock_moonraker.py. Runs only when
/// SNARWAL_MOCK_PRINTER is set, e.g. "127.0.0.1:7125".
final class MockPrinterTests: XCTestCase {
    func testUploadStartPauseAndLight() async throws {
        guard let host = ProcessInfo.processInfo.environment["SNARWAL_MOCK_PRINTER"] else {
            throw XCTSkip("SNARWAL_MOCK_PRINTER not set")
        }
        let client = try MoonrakerClient(host: host)
        let before = try await client.status()
        XCTAssertEqual(before.state, .standby)
        XCTAssertEqual(before.filaments.map(\.loaded), [true, true, true, true])
        XCTAssertEqual(before.filaments[2].colorHex, "#E8792B")

        try await client.upload(gcode: Data("PRINT_START\nG1 X1 E1\nPRINT_END\n".utf8), filename: "Mock Test.gcode", start: true)
        let printing = try await client.status()
        XCTAssertEqual(printing.state, .printing)
        XCTAssertEqual(printing.filename, "Mock Test.gcode")

        try await client.setLight(on: false)
        try await client.pause()
        let paused = try await client.status()
        XCTAssertEqual(paused.state, .paused)
        XCTAssertFalse(paused.lightOn)
        try await client.resume()
        try await client.cancel()
        let estimated = try await client.estimatedTime(filename: "Mock Test.gcode")
        XCTAssertEqual(estimated, 2400)
        let cancelled = try await client.status()
        XCTAssertEqual(cancelled.state, .cancelled)
    }
}
