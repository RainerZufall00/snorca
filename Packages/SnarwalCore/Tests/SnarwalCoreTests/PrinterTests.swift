import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import SnarwalCore

/// Records requests and answers with canned JSON.
final class MockTransport: HTTPTransport, @unchecked Sendable {
    var requests: [URLRequest] = []
    var responses: [(Int, String)]

    init(_ responses: [(Int, String)]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (status, body) = responses.isEmpty ? (200, "{\"result\":\"ok\"}") : responses.removeFirst()
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

let statusJSON = """
{"result": {"eventtime": 1, "status": {
  "print_stats": {"state": "printing", "filename": "Set.gcode", "print_duration": 600.5, "message": "",
                  "info": {"current_layer": 84, "total_layer": 240}},
  "virtual_sdcard": {"progress": 0.37},
  "toolhead": {"extruder": "extruder1"},
  "extruder": {"temperature": 151.2, "target": 150},
  "extruder1": {"temperature": 219.6, "target": 220},
  "extruder2": {"temperature": 22.0, "target": 0},
  "extruder3": {"temperature": 22.5, "target": 0},
  "heater_bed": {"temperature": 60.1, "target": 60},
  "fan": {"speed": 0.8},
  "led cavity_led": {"color_data": [[0, 0, 0, 1]]},
  "print_task_config": {
    "filament_type": ["PLA", "PLA", "PETG", "NONE"],
    "filament_sub_type": ["Basic", "Matte", "NONE", "NONE"],
    "filament_vendor": ["Snapmaker", "Snapmaker", "Generic", "NONE"],
    "filament_color_rgba": ["FFFFFFFF", "2A2A2AFF", "2F6FD6FF", "FFFFFFFF"],
    "filament_exist": [true, true, true, false]
  }
}}}
"""

final class PrinterTests: XCTestCase {
    func testHostParsing() throws {
        XCTAssertEqual(try MoonrakerClient(host: "192.168.1.20").baseURL.absoluteString, "http://192.168.1.20")
        XCTAssertEqual(try MoonrakerClient(host: " u1.tail.ts.net:7125 ").baseURL.absoluteString, "http://u1.tail.ts.net:7125")
        XCTAssertThrowsError(try MoonrakerClient(host: ""))
    }

    func testStatusDecoding() async throws {
        let transport = MockTransport([(200, statusJSON)])
        let status = try await MoonrakerClient(host: "u1.local", transport: transport).status()
        XCTAssertEqual(status.state, .printing)
        XCTAssertEqual(status.progress, 0.37, accuracy: 1e-9)
        XCTAssertEqual(status.currentLayer, 84)
        XCTAssertEqual(status.totalLayers, 240)
        XCTAssertEqual(status.activeTool, 1)
        XCTAssertEqual(status.nozzles[1], HeaterState(temperature: 219.6, target: 220))
        XCTAssertEqual(status.bed.target, 60)
        XCTAssertEqual(status.partFan, 0.8, accuracy: 1e-9)
        XCTAssertTrue(status.lightOn)
        XCTAssertEqual(status.filaments.map(\.material), [.pla, .pla, .petg, .pla])
        XCTAssertEqual(status.filaments.map(\.loaded), [true, true, true, false])
        XCTAssertEqual(status.filaments[1].colorHex, "#2A2A2A")
        XCTAssertEqual(status.filaments[2].vendor, "Generic")
        XCTAssertEqual(status.filaments[0].label, "T1")

        let query = try XCTUnwrap(transport.requests.first?.url?.absoluteString)
        XCTAssertTrue(query.hasPrefix("http://u1.local/printer/objects/query?print_stats&"), query)
        XCTAssertTrue(query.contains("led%20cavity_led"), query)
    }

    func testRemainingTime() {
        var status = PrinterStatus()
        status.printDuration = 600
        status.progress = 0.25
        XCTAssertEqual(status.remaining(estimatedTotal: 1000), 400)
        XCTAssertEqual(status.remaining(estimatedTotal: nil) ?? 0, 1800, accuracy: 1e-6)
        status.progress = 0.01
        XCTAssertNil(status.remaining(estimatedTotal: nil))
    }

    func testUploadIsMultipartWithPrintFlag() async throws {
        let transport = MockTransport([(201, "{\"result\": {\"item\": {\"path\": \"a.gcode\"}, \"print_started\": true}}")])
        let client = try MoonrakerClient(host: "u1.local", transport: transport)
        try await client.upload(gcode: Data("G28\n".utf8), filename: "a.gcode", start: true)
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/server/files/upload")
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"print\"\r\n\r\ntrue\r\n"))
        XCTAssertTrue(body.contains("name=\"root\"\r\n\r\ngcodes\r\n"))
        XCTAssertTrue(body.contains("filename=\"a.gcode\""))
        XCTAssertTrue(body.contains("G28\n"))
        XCTAssertTrue(body.hasSuffix("--\r\n"))
        let type = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(body.hasPrefix("--" + type.components(separatedBy: "boundary=")[1]))
    }

    func testPrinterRejectionWithHTTP200IsAnError() async throws {
        let transport = MockTransport([(200, "{\"state\": \"error\", \"message\": \"Printer busy\"}")])
        let client = try MoonrakerClient(host: "u1.local", transport: transport)
        do {
            try await client.startPrint(filename: "a.gcode")
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? MoonrakerError, .printer("Printer busy"))
        }
        XCTAssertEqual(transport.requests.first?.url?.absoluteString, "http://u1.local/printer/print/start?filename=a.gcode")
    }

    func testLightAndFanUseGCode() async throws {
        let transport = MockTransport([])
        let client = try MoonrakerClient(host: "u1.local", transport: transport)
        try await client.setLight(on: false)
        try await client.setPartFan(0.5)
        let scripts = transport.requests.compactMap { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value }
        XCTAssertEqual(scripts, ["SET_LED LED=cavity_led WHITE=0", "M106 S128"])
    }

    func testCameraSourcePrefersWebRTC() throws {
        let base = URL(string: "http://u1.local")!
        let webrtc = Webcam(name: "case", service: "webrtc-camerastreamer",
                            streamURL: URL(string: "http://u1.local/webcam/webrtc"),
                            snapshotURL: URL(string: "http://u1.local/webcam/snapshot.jpg"))
        XCTAssertEqual(MoonrakerClient.cameraSource(webcams: [webrtc], baseURL: base), .webrtcPage(URL(string: "http://u1.local/webcam/webrtc")!))
        XCTAssertEqual(MoonrakerClient.cameraSource(webcams: [], baseURL: base),
                       .stockMonitor(URL(string: "http://u1.local/server/files/camera/monitor.jpg")!))
        XCTAssertEqual(try MoonrakerClient(host: "u1.local").websocketURL.absoluteString, "ws://u1.local/websocket")
    }

    func testWebcamListResolvesRelativeURLs() async throws {
        let json = """
        {"result": {"webcams": [{"name": "case", "service": "webrtc-camerastreamer",
          "stream_url": "/webcam/webrtc", "snapshot_url": "/webcam/snapshot.jpg"}]}}
        """
        let client = try MoonrakerClient(host: "10.0.0.5", transport: MockTransport([(200, json)]))
        let cams = try await client.webcams()
        XCTAssertEqual(cams.first?.streamURL?.absoluteString, "http://10.0.0.5/webcam/webrtc")
        XCTAssertEqual(cams.first?.snapshotURL?.absoluteString, "http://10.0.0.5/webcam/snapshot.jpg")
    }
}
