import SnarwalCore
import XCTest
@testable import Snarwal

/// Runs the real Kiri:Moto bundle inside WebKit on the simulator: local
/// server, module workers, WASM and the Swift ↔ JS bridge.
@MainActor
final class EngineTests: XCTestCase {
    static let engine = SlicerEngine()

    func box(_ x: Float, _ y: Float, _ z: Float) -> Mesh {
        .box(x, y, z)
    }

    func testLoadsBinarySTL() async throws {
        let mesh = box(10, 20, 30)
        var data = Data(count: 80)
        var count = UInt32(mesh.triangleCount).littleEndian
        data.append(Data(bytes: &count, count: 4))
        for t in 0..<mesh.triangleCount {
            data.append(Data(count: 12)) // normal
            for i in 0..<9 {
                var value = mesh.vertices[t * 9 + i].bitPattern.littleEndian
                data.append(Data(bytes: &value, count: 4))
            }
            data.append(Data(count: 2))
        }
        let objects = try await Self.engine.loadModel(name: "Box.stl", data: data)
        XCTAssertEqual(objects.count, 1)
        XCTAssertEqual(objects.first?.name, "Box")
        XCTAssertEqual(objects.first?.mesh.triangleCount, 12)
        let size = try XCTUnwrap(objects.first?.mesh.bounds.size)
        XCTAssertEqual(size.z, 30, accuracy: 0.001)
    }

    func testSlicesTwoHeadsInWebKit() async throws {
        let plate = Plate(objects: [
            PlateObject(name: "A", mesh: box(20, 20, 10), tool: 0, position: (80, 135)),
            PlateObject(name: "B", mesh: box(20, 20, 10), tool: 1, position: (190, 135)),
        ])
        let heads = HeadFilament.defaults()
        let process = SliceSettings().kiriProcess(firstHead: heads[0])
        let output = try await Self.engine.slice(plate: plate, process: process, heads: heads)
        let gcode = output.gcode
        XCTAssertTrue(gcode.contains("PRINT_START"))
        XCTAssertTrue(gcode.contains("SM_PRINT_PREEXTRUDE_FILAMENT INDEX=1"))
        XCTAssertTrue(gcode.contains("; thumbnail begin 300x300"), "thumbnail from SceneKit renderer")

        let summary = try XCTUnwrap(GCodeSummary(gcode: gcode))
        XCTAssertEqual(summary.layers, 50)
        XCTAssertGreaterThan(summary.gramsPerTool[0], 0)
        XCTAssertGreaterThan(summary.gramsPerTool[1], 0)
        XCTAssertEqual(GCodePreview(gcode: gcode).layers.count, 50)
    }
}
