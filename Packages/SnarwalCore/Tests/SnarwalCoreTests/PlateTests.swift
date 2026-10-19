import XCTest
@testable import SnarwalCore

/// Box with its min corner at the origin, as triangle soup.
func box(_ x: Float, _ y: Float, _ z: Float) -> Mesh {
    let v: [[Float]] = [[0,0,0],[x,0,0],[x,y,0],[0,y,0],[0,0,z],[x,0,z],[x,y,z],[0,y,z]]
    let faces = [[0,2,1],[0,3,2],[4,5,6],[4,6,7],[0,1,5],[0,5,4],[1,2,6],[1,6,5],[2,3,7],[2,7,6],[3,0,4],[3,4,7]]
    return Mesh(vertices: faces.flatMap { $0.flatMap { v[$0] } })
}

final class PlateTests: XCTestCase {
    func testBase64RoundTrip() throws {
        let mesh = box(10, 20, 30)
        let decoded = try XCTUnwrap(Mesh(base64: mesh.base64()))
        XCTAssertEqual(decoded.vertices, mesh.vertices)
        XCTAssertEqual(decoded.triangleCount, 12)
        XCTAssertNil(Mesh(base64: "not base64"))
    }

    func testPlacedMeshRestsOnBedAtPosition() {
        let object = PlateObject(name: "Box", mesh: box(10, 20, 30), position: (100, 50))
        let b = object.placedMesh().bounds
        XCTAssertEqual(b.min.z, 0, accuracy: 1e-4)
        XCTAssertEqual(b.center.x, 100, accuracy: 1e-4)
        XCTAssertEqual(b.center.y, 50, accuracy: 1e-4)
        XCTAssertEqual(b.size.z, 30, accuracy: 1e-4)
    }

    func testTranslationMatchesPlacedMesh() {
        var object = PlateObject(name: "Box", mesh: box(10, 20, 30), position: (80, 90))
        object.rotateZ(degrees: 30)
        object.scale = 1.5
        let placed = object.placedMesh().bounds
        let t = object.translation
        let b = object.mesh.bounds(applying: object.matrix)
        XCTAssertEqual(b.min.x + t.x, placed.min.x, accuracy: 1e-3)
        XCTAssertEqual(b.min.y + t.y, placed.min.y, accuracy: 1e-3)
        XCTAssertEqual(b.min.z + t.z, 0, accuracy: 1e-3)
    }

    func testRotateAndScale() {
        var object = PlateObject(name: "Box", mesh: box(10, 20, 30))
        object.rotateZ(degrees: 90)
        object.scale = 2
        let s = object.size
        XCTAssertEqual(s.x, 40, accuracy: 1e-3)
        XCTAssertEqual(s.y, 20, accuracy: 1e-3)
        XCTAssertEqual(s.z, 60, accuracy: 1e-3)
    }

    func testLayFlatPutsLargestFaceDown() {
        // a tall thin plate standing on its 2×30 edge should end up lying on its 30×40 face
        var object = PlateObject(name: "Plate", mesh: box(2, 30, 40))
        object.layFlat()
        let s = object.size
        XCTAssertEqual(s.z, 2, accuracy: 1e-3)
        XCTAssertEqual(max(s.x, s.y), 40, accuracy: 1e-3)
    }

    func testArrangeKeepsObjectsApartAndOnBed() {
        var plate = Plate(objects: (0..<6).map { PlateObject(name: "B\($0)", mesh: box(60, 40, 10), position: (0, 0)) })
        XCTAssertTrue(plate.arrange())
        XCTAssertTrue(plate.boundsIssues().isEmpty)
        let boxes = plate.objects.map { $0.placedMesh().bounds }
        for i in boxes.indices {
            for j in boxes.indices where j > i {
                let a = boxes[i], b = boxes[j]
                let overlap = a.min.x < b.max.x && b.min.x < a.max.x && a.min.y < b.max.y && b.min.y < a.max.y
                XCTAssertFalse(overlap, "\(i) overlaps \(j)")
            }
        }
    }

    func testArrangeFailsWhenTooLarge() {
        var plate = Plate(objects: [PlateObject(name: "Huge", mesh: box(300, 10, 10))])
        XCTAssertFalse(plate.arrange())
        XCTAssertEqual(plate.boundsIssues(), [.outsideBed(name: "Huge")])
    }

    func testMixedMaterialsAreReported() {
        var heads = HeadFilament.defaults()
        heads[3] = HeadFilament(tool: 3, material: .petg)
        var plate = Plate(objects: [PlateObject(name: "A", mesh: box(10, 10, 10), tool: 0)])
        XCTAssertTrue(MaterialCheck.issues(plate: plate, heads: heads).isEmpty)
        plate.objects.append(PlateObject(name: "B", mesh: box(10, 10, 10), tool: 3))
        XCTAssertEqual(MaterialCheck.issues(plate: plate, heads: heads), [.mixedMaterials([.petg, .pla])])
    }
}
