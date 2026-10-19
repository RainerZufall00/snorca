import Foundation

/// Saves the plate to a folder: one binary file per mesh (written once)
/// and a small JSON index with names, heads and transforms (written on
/// every change). iOS may end the app in the background at any time.
public struct PlateStore: Sendable {
    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    struct Record: Codable {
        var id: UUID
        var name: String
        var tool: Int
        var rotation: [Double]
        var scale: Double
        var x: Double
        var y: Double
    }

    struct Index: Codable {
        var projectName: String
        var objects: [Record]
    }

    private var indexURL: URL { folder.appendingPathComponent("plate.json") }

    private func meshURL(_ id: UUID) -> URL { folder.appendingPathComponent("mesh-\(id.uuidString).bin") }

    public func save(plate: Plate, projectName: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for object in plate.objects where !FileManager.default.fileExists(atPath: meshURL(object.id).path) {
            let data = object.mesh.vertices.withUnsafeBufferPointer { Data(buffer: $0) }
            try data.write(to: meshURL(object.id), options: .atomic)
        }
        let index = Index(projectName: projectName, objects: plate.objects.map {
            Record(id: $0.id, name: $0.name, tool: $0.tool, rotation: $0.rotation.m, scale: $0.scale,
                   x: $0.position.x, y: $0.position.y)
        })
        try JSONEncoder().encode(index).write(to: indexURL, options: .atomic)
        // drop meshes of removed objects
        let keep = Set(plate.objects.map { meshURL($0.id).lastPathComponent })
        for file in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        where file.hasPrefix("mesh-") && !keep.contains(file) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(file))
        }
    }

    public func load() -> (plate: Plate, projectName: String)? {
        guard let data = try? Data(contentsOf: indexURL),
              let index = try? JSONDecoder().decode(Index.self, from: data) else { return nil }
        let objects: [PlateObject] = index.objects.compactMap { record in
            guard record.rotation.count == 9,
                  let raw = try? Data(contentsOf: meshURL(record.id)), raw.count % 36 == 0, !raw.isEmpty else { return nil }
            let vertices = raw.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            return PlateObject(id: record.id, name: record.name, mesh: Mesh(vertices: vertices), tool: record.tool,
                               rotation: Mat3(record.rotation), scale: record.scale, position: (record.x, record.y))
        }
        return (Plate(objects: objects), index.projectName)
    }

    public func clear() {
        try? FileManager.default.removeItem(at: folder)
    }
}
