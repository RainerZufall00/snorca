import XCTest
@testable import SnarwalCore

final class PlateStoreTests: XCTestCase {
    func testRoundTripAndCleanup() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("plate-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = PlateStore(folder: folder)
        XCTAssertNil(store.load())

        var a = PlateObject(name: "A", mesh: .box(10, 20, 30), tool: 2, position: (50, 60))
        a.rotateZ(degrees: 90)
        a.scale = 1.5
        let b = PlateObject(name: "B", mesh: .box(5, 5, 5), tool: 1, position: (150, 160))
        try store.save(plate: Plate(objects: [a, b]), projectName: "Set")

        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded.projectName, "Set")
        XCTAssertEqual(loaded.plate.objects.map(\.name), ["A", "B"])
        let first = loaded.plate.objects[0]
        XCTAssertEqual(first.id, a.id)
        XCTAssertEqual(first.tool, 2)
        XCTAssertEqual(first.scale, 1.5)
        XCTAssertEqual(first.rotation, a.rotation)
        XCTAssertEqual(first.position.x, 50)
        XCTAssertEqual(first.mesh.vertices, a.mesh.vertices)

        // removing B deletes its mesh file
        try store.save(plate: Plate(objects: [a]), projectName: "Set")
        let meshes = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("mesh-") }
        XCTAssertEqual(meshes, ["mesh-\(a.id.uuidString).bin"])
    }
}
