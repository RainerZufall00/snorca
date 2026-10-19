import Metal
import SceneKit
import SnarwalCore
import UIKit

/// Renders the plate objects to PNG previews for the G-code header
/// (the U1 touchscreen and Moonraker show them; Orca uses 48 and 300 px).
@MainActor
enum PlateThumbnail {
    static let sizes = [48, 300]

    static func render(plate: Plate, heads: [HeadFilament]) -> [(width: Int, height: Int, png: Data)] {
        guard !plate.objects.isEmpty else { return [] }
        let scene = SCNScene()
        var lo = Vec3(.infinity, .infinity, .infinity), hi = Vec3(-.infinity, -.infinity, -.infinity)
        for object in plate.objects {
            let node = SCNNode(geometry: PlateSceneView.Coordinator.geometry(for: object.mesh))
            let m = object.matrix.m, t = object.translation
            node.transform = SCNMatrix4(
                m11: Float(m[0]), m12: Float(m[3]), m13: Float(m[6]), m14: 0,
                m21: Float(m[1]), m22: Float(m[4]), m23: Float(m[7]), m24: 0,
                m31: Float(m[2]), m32: Float(m[5]), m33: Float(m[8]), m34: 0,
                m41: Float(t.x), m42: Float(t.y), m43: Float(t.z), m44: 1)
            let head = heads.first { $0.tool == object.tool }
            node.geometry?.firstMaterial?.diffuse.contents = UIColor(head?.color ?? .gray)
            scene.rootNode.addChildNode(node)
            let size = object.size
            lo = Vec3(min(lo.x, object.position.x - size.x / 2), min(lo.y, object.position.y - size.y / 2), 0)
            hi = Vec3(max(hi.x, object.position.x + size.x / 2), max(hi.y, object.position.y + size.y / 2), max(hi.z, size.z))
        }
        let center = (lo + hi) * 0.5
        let extent = max(hi.x - lo.x, hi.y - lo.y, hi.z, 10)

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = extent * 0.75
        camera.zFar = 10_000
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(x: Float(center.x), y: Float(center.y - extent * 1.5), z: Float(center.z + extent * 1.2))
        cameraNode.look(at: SCNVector3(x: Float(center.x), y: Float(center.y), z: Float(center.z)),
                        up: SCNVector3(x: 0, y: 0, z: 1), localFront: SCNVector3(x: 0, y: 0, z: -1))
        scene.rootNode.addChildNode(cameraNode)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 500
        scene.rootNode.addChildNode(ambient)
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 900
        sun.eulerAngles = SCNVector3(x: -Float.pi / 3, y: Float.pi / 6, z: 0)
        scene.rootNode.addChildNode(sun)
        scene.background.contents = UIColor(red: 0.063, green: 0.110, blue: 0.149, alpha: 1)

        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = cameraNode
        return sizes.compactMap { px in
            let image = renderer.snapshot(atTime: 0, with: CGSize(width: px, height: px), antialiasingMode: .multisampling4X)
            guard let png = image.pngData() else { return nil }
            return (px, px, png)
        }
    }
}
