import Foundation

/// The Snapmaker U1 build volume.
public enum PrinterSpec {
    public static let bedWidth = 270.0
    public static let bedDepth = 270.0
    public static let maxHeight = 270.0
    public static let toolCount = 4
}

/// One model on the build plate. The source mesh stays untouched; rotation,
/// scale and position are applied when the plate is sent to the slicer.
public struct PlateObject: Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var mesh: Mesh
    public var tool: Int
    public var rotation: Mat3
    public var scale: Double
    /// Bed position of the bounding box centre, millimetres from the front-left corner.
    public var position: (x: Double, y: Double)

    public init(id: UUID = UUID(), name: String, mesh: Mesh, tool: Int = 0,
                rotation: Mat3 = .identity, scale: Double = 1, position: (x: Double, y: Double)? = nil) {
        self.id = id
        self.name = name
        self.mesh = mesh
        self.tool = tool
        self.rotation = rotation
        self.scale = scale
        let c = mesh.bounds.center
        self.position = position ?? (c.x, c.y)
    }

    public var matrix: Mat3 {
        Mat3([scale, 0, 0, 0, scale, 0, 0, 0, scale]) * rotation
    }

    /// Mesh in bed coordinates, resting on the plate.
    public func placedMesh() -> Mesh {
        mesh.placed(matrix: matrix, center: position)
    }

    /// Size of the placed object (width, depth, height).
    public var size: Vec3 {
        mesh.bounds(applying: matrix).size
    }

    /// Translation that, after `matrix`, centres the object on `position`
    /// and rests it on the bed. Used by the 3D view as the node transform.
    public var translation: Vec3 {
        let b = mesh.bounds(applying: matrix)
        return Vec3(position.x - b.center.x, position.y - b.center.y, -b.min.z)
    }

    public mutating func rotateZ(degrees: Double) {
        rotation = Mat3.rotationZ(degrees: degrees) * rotation
    }

    public mutating func layFlat() {
        rotation = mesh.layFlatRotation(applying: rotation)
    }
}

public enum PlateIssue: Equatable, Sendable {
    case outsideBed(name: String)
    case tooTall(name: String)
    case mixedMaterials([Material])
    case paintedModel(name: String)
}

public struct Plate: Sendable {
    public var objects: [PlateObject] = []

    public init(objects: [PlateObject] = []) {
        self.objects = objects
    }

    /// Footprint of every object fits on the bed and below the gantry.
    public func boundsIssues() -> [PlateIssue] {
        var issues: [PlateIssue] = []
        for object in objects {
            let b = object.placedMesh().bounds
            if b.min.x < 0 || b.min.y < 0 || b.max.x > PrinterSpec.bedWidth || b.max.y > PrinterSpec.bedDepth {
                issues.append(.outsideBed(name: object.name))
            }
            if b.max.z > PrinterSpec.maxHeight {
                issues.append(.tooTall(name: object.name))
            }
        }
        return issues
    }

    public var usedTools: [Int] {
        Array(Set(objects.map(\.tool))).sorted()
    }

    /// Arranges all objects in rows across the bed (shelf packing), keeping
    /// `spacing` millimetres between footprints, and centres the result.
    /// Returns false if they do not fit; positions stay unchanged then.
    @discardableResult
    public mutating func arrange(spacing: Double = 8) -> Bool {
        let sizes = objects.map(\.size)
        let order = objects.indices.sorted { sizes[$0].y > sizes[$1].y }
        var placements: [Int: (x: Double, y: Double)] = [:]
        var cursorX = 0.0, cursorY = 0.0, rowDepth = 0.0, usedWidth = 0.0
        for index in order {
            let s = sizes[index]
            if cursorX > 0 && cursorX + s.x > PrinterSpec.bedWidth {
                cursorX = 0
                cursorY += rowDepth + spacing
                rowDepth = 0
            }
            if s.x > PrinterSpec.bedWidth || cursorY + s.y > PrinterSpec.bedDepth { return false }
            placements[index] = (cursorX + s.x / 2, cursorY + s.y / 2)
            cursorX += s.x + spacing
            usedWidth = max(usedWidth, cursorX - spacing)
            rowDepth = max(rowDepth, s.y)
        }
        let usedDepth = cursorY + rowDepth
        let offsetX = (PrinterSpec.bedWidth - usedWidth) / 2
        let offsetY = (PrinterSpec.bedDepth - usedDepth) / 2
        for (index, p) in placements {
            objects[index].position = (p.x + offsetX, p.y + offsetY)
        }
        return true
    }
}
