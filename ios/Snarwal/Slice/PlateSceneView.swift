import SceneKit
import SnarwalCore
import SwiftUI
import UIKit

/// 3D view of the U1 bed with the plate objects. Drag to orbit, pinch to
/// zoom, tap an object to select it.
struct PlateSceneView: UIViewRepresentable {
    let objects: [PlateObject]
    let heads: [HeadFilament]
    let selectedID: UUID?
    let onSelect: (UUID?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = FittingSCNView()
        view.scene = context.coordinator.scene
        view.backgroundColor = UIColor(Color.snarwalViewport)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.pointOfView = context.coordinator.cameraNode
        view.defaultCameraController.interactionMode = .orbitTurntable
        view.defaultCameraController.target = SCNVector3(x: 135, y: 135, z: 0)
        view.defaultCameraController.worldUp = SCNVector3(x: 0, y: 0, z: 1)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.update(objects: objects, heads: heads, selectedID: selectedID)
    }

    @MainActor
    final class Coordinator: NSObject {
        let scene = SCNScene()
        let cameraNode = SCNNode()
        var onSelect: (UUID?) -> Void
        private var nodes: [UUID: SCNNode] = [:]
        private let selectionNode = SCNNode()
        /// Geometry is built once per mesh; edits only change node transforms.
        private var geometryKeys: [UUID: Int] = [:]

        init(onSelect: @escaping (UUID?) -> Void) {
            self.onSelect = onSelect
            super.init()
            buildBed()
            let camera = SCNCamera()
            camera.zFar = 5000
            camera.fieldOfView = 40
            cameraNode.camera = camera
            cameraNode.position = SCNVector3(x: 135, y: -230, z: 300)
            cameraNode.look(at: SCNVector3(x: 135, y: 135, z: 0), up: SCNVector3(x: 0, y: 0, z: 1), localFront: SCNVector3(x: 0, y: 0, z: -1))
            scene.rootNode.addChildNode(cameraNode)

            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 350
            scene.rootNode.addChildNode(ambient)
            let sun = SCNNode()
            sun.light = SCNLight()
            sun.light?.type = .directional
            sun.light?.intensity = 750
            sun.eulerAngles = SCNVector3(x: -Float.pi / 3, y: Float.pi / 6, z: 0)
            scene.rootNode.addChildNode(sun)
            scene.rootNode.addChildNode(selectionNode)
        }

        private func buildBed() {
            let size = CGFloat(PrinterSpec.bedWidth)
            let bed = SCNBox(width: size, height: size, length: 2, chamferRadius: 2)
            bed.firstMaterial?.diffuse.contents = UIColor(red: 0.12, green: 0.18, blue: 0.23, alpha: 1)
            let bedNode = SCNNode(geometry: bed)
            bedNode.position = SCNVector3(size / 2, size / 2, -1.01)
            scene.rootNode.addChildNode(bedNode)

            // 30 mm grid
            var points: [SCNVector3] = []
            var step = 30.0
            while step < PrinterSpec.bedWidth {
                let s = Float(step), w = Float(size)
                points += [SCNVector3(s, 0, 0.05), SCNVector3(s, w, 0.05), SCNVector3(0, s, 0.05), SCNVector3(w, s, 0.05)]
                step += 30
            }
            let source = SCNGeometrySource(vertices: points)
            let element = SCNGeometryElement(indices: (0..<Int32(points.count)).map { $0 }, primitiveType: .line)
            let grid = SCNGeometry(sources: [source], elements: [element])
            grid.firstMaterial?.diffuse.contents = UIColor(red: 0.2, green: 0.29, blue: 0.36, alpha: 1)
            grid.firstMaterial?.lightingModel = .constant
            scene.rootNode.addChildNode(SCNNode(geometry: grid))
        }

        func update(objects: [PlateObject], heads: [HeadFilament], selectedID: UUID?) {
            let ids = Set(objects.map(\.id))
            for (id, node) in nodes where !ids.contains(id) {
                node.removeFromParentNode()
                nodes[id] = nil
                geometryKeys[id] = nil
            }
            for object in objects {
                let key = object.mesh.vertices.count
                let node: SCNNode
                if let existing = nodes[object.id], geometryKeys[object.id] == key {
                    node = existing
                } else {
                    nodes[object.id]?.removeFromParentNode()
                    node = SCNNode(geometry: Self.geometry(for: object.mesh))
                    node.name = object.id.uuidString
                    scene.rootNode.addChildNode(node)
                    nodes[object.id] = node
                    geometryKeys[object.id] = key
                }
                let m = object.matrix.m, t = object.translation
                // SceneKit uses row vectors (v * M): row i holds the image of axis i
                node.transform = SCNMatrix4(
                    m11: Float(m[0]), m12: Float(m[3]), m13: Float(m[6]), m14: 0,
                    m21: Float(m[1]), m22: Float(m[4]), m23: Float(m[7]), m24: 0,
                    m31: Float(m[2]), m32: Float(m[5]), m33: Float(m[8]), m34: 0,
                    m41: Float(t.x), m42: Float(t.y), m43: Float(t.z), m44: 1)
                let head = heads.first { $0.tool == object.tool }
                node.geometry?.firstMaterial?.diffuse.contents = UIColor(head?.color ?? .gray)
            }
            updateSelection(objects.first { $0.id == selectedID })
        }

        /// Outline of the selected object's bounding box; tinting the object
        /// itself would falsify its filament colour.
        private func updateSelection(_ object: PlateObject?) {
            selectionNode.geometry = nil
            guard let object else { return }
            let s = object.size
            let x0 = Float(object.position.x - s.x / 2), x1 = Float(object.position.x + s.x / 2)
            let y0 = Float(object.position.y - s.y / 2), y1 = Float(object.position.y + s.y / 2)
            let z0: Float = 0.1, z1 = Float(s.z) + 0.1
            let corners = [
                SCNVector3(x0, y0, z0), SCNVector3(x1, y0, z0), SCNVector3(x1, y1, z0), SCNVector3(x0, y1, z0),
                SCNVector3(x0, y0, z1), SCNVector3(x1, y0, z1), SCNVector3(x1, y1, z1), SCNVector3(x0, y1, z1),
            ]
            let edges: [Int32] = [0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7]
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: corners)],
                                       elements: [SCNGeometryElement(indices: edges, primitiveType: .line)])
            geometry.firstMaterial?.diffuse.contents = UIColor(red: 0.5, green: 0.83, blue: 0.92, alpha: 1)
            geometry.firstMaterial?.lightingModel = .constant
            selectionNode.geometry = geometry
        }

        /// Flat-shaded geometry from triangle soup.
        static func geometry(for mesh: Mesh) -> SCNGeometry {
            let v = mesh.vertices
            var positions: [SCNVector3] = []
            var normals: [SCNVector3] = []
            positions.reserveCapacity(v.count / 3)
            normals.reserveCapacity(v.count / 3)
            var i = 0
            while i + 8 < v.count {
                let a = SCNVector3(v[i], v[i + 1], v[i + 2])
                let b = SCNVector3(v[i + 3], v[i + 4], v[i + 5])
                let c = SCNVector3(v[i + 6], v[i + 7], v[i + 8])
                let ux = b.x - a.x, uy = b.y - a.y, uz = b.z - a.z
                let wx = c.x - a.x, wy = c.y - a.y, wz = c.z - a.z
                var n = SCNVector3(uy * wz - uz * wy, uz * wx - ux * wz, ux * wy - uy * wx)
                let len = (n.x * n.x + n.y * n.y + n.z * n.z).squareRoot()
                if len > 0 { n = SCNVector3(n.x / len, n.y / len, n.z / len) }
                positions += [a, b, c]
                normals += [n, n, n]
                i += 9
            }
            let element = SCNGeometryElement(indices: (0..<Int32(positions.count)).map { $0 }, primitiveType: .triangles)
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals)],
                                       elements: [element])
            let material = SCNMaterial()
            material.lightingModel = .blinn
            material.isDoubleSided = true
            geometry.materials = [material]
            return geometry
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let view = gesture.view as? SCNView else { return }
            let hits = view.hitTest(gesture.location(in: view), options: [.searchMode: SCNHitTestSearchMode.closest.rawValue])
            let id = hits.lazy.compactMap { $0.node.name.flatMap(UUID.init(uuidString:)) }.first
            onSelect(id)
        }
    }
}

/// Keeps the whole bed in view: the field of view applies to the narrower
/// side, so portrait iPhones and iPads do not crop the plate.
private final class FittingSCNView: SCNView {
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        pointOfView?.camera?.projectionDirection = bounds.width < bounds.height ? .horizontal : .vertical
    }
}
