import Foundation

/// Small value types for mesh math. `simd` is not available on Linux,
/// where the package's tests also run.
public struct Vec3: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(_ x: Double, _ y: Double, _ z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vec3(0, 0, 0)

    public static func + (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x + b.x, a.y + b.y, a.z + b.z) }
    public static func - (a: Vec3, b: Vec3) -> Vec3 { Vec3(a.x - b.x, a.y - b.y, a.z - b.z) }
    public static func * (a: Vec3, s: Double) -> Vec3 { Vec3(a.x * s, a.y * s, a.z * s) }

    public func dot(_ b: Vec3) -> Double { x * b.x + y * b.y + z * b.z }
    public func cross(_ b: Vec3) -> Vec3 { Vec3(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x) }
    public var length: Double { dot(self).squareRoot() }
    public var normalized: Vec3 { length > 0 ? self * (1 / length) : self }
}

/// 3×3 rotation/scale matrix, row-major.
public struct Mat3: Equatable, Sendable {
    public var m: [Double]

    public init(_ m: [Double]) {
        precondition(m.count == 9)
        self.m = m
    }

    public static let identity = Mat3([1, 0, 0, 0, 1, 0, 0, 0, 1])

    public static func rotationZ(degrees: Double) -> Mat3 {
        let r = degrees * .pi / 180
        let c = cos(r), s = sin(r)
        return Mat3([c, -s, 0, s, c, 0, 0, 0, 1])
    }

    /// Rotation around an arbitrary unit axis (Rodrigues).
    public static func rotation(axis: Vec3, radians: Double) -> Mat3 {
        let a = axis.normalized
        let c = cos(radians), s = sin(radians), t = 1 - c
        return Mat3([
            t * a.x * a.x + c, t * a.x * a.y - s * a.z, t * a.x * a.z + s * a.y,
            t * a.x * a.y + s * a.z, t * a.y * a.y + c, t * a.y * a.z - s * a.x,
            t * a.x * a.z - s * a.y, t * a.y * a.z + s * a.x, t * a.z * a.z + c,
        ])
    }

    /// Rotation that turns unit vector `from` onto unit vector `to`.
    public static func rotation(from: Vec3, to: Vec3) -> Mat3 {
        let f = from.normalized, t = to.normalized
        let d = f.dot(t)
        if d > 0.999999 { return .identity }
        if d < -0.999999 {
            // opposite: rotate 180° around any perpendicular axis
            let axis = abs(f.x) < 0.9 ? f.cross(Vec3(1, 0, 0)) : f.cross(Vec3(0, 1, 0))
            return rotation(axis: axis, radians: .pi)
        }
        return rotation(axis: f.cross(t), radians: acos(d))
    }

    public static func * (a: Mat3, b: Mat3) -> Mat3 {
        var r = [Double](repeating: 0, count: 9)
        for i in 0..<3 {
            for j in 0..<3 {
                r[i * 3 + j] = a.m[i * 3] * b.m[j] + a.m[i * 3 + 1] * b.m[3 + j] + a.m[i * 3 + 2] * b.m[6 + j]
            }
        }
        return Mat3(r)
    }

    public static func * (a: Mat3, v: Vec3) -> Vec3 {
        Vec3(a.m[0] * v.x + a.m[1] * v.y + a.m[2] * v.z,
             a.m[3] * v.x + a.m[4] * v.y + a.m[5] * v.z,
             a.m[6] * v.x + a.m[7] * v.y + a.m[8] * v.z)
    }
}

public struct Box3: Equatable, Sendable {
    public var min: Vec3
    public var max: Vec3

    public var size: Vec3 { max - min }
    public var center: Vec3 { (min + max) * 0.5 }
}

/// Triangle soup: 9 floats (3 vertices) per triangle, millimetres.
public struct Mesh: Sendable {
    public var vertices: [Float]

    public init(vertices: [Float]) {
        self.vertices = vertices
    }

    /// Decodes the base64 Float32 buffers the slicing engine returns.
    public init?(base64: String) {
        guard let data = Data(base64Encoded: base64), data.count % 36 == 0, !data.isEmpty else { return nil }
        let floats = data.withUnsafeBytes { raw in Array(raw.bindMemory(to: Float.self)) }
        self.init(vertices: floats)
    }

    public var triangleCount: Int { vertices.count / 9 }

    /// Box with its min corner at the origin (demo plates and tests).
    public static func box(_ x: Float, _ y: Float, _ z: Float) -> Mesh {
        let v: [[Float]] = [[0, 0, 0], [x, 0, 0], [x, y, 0], [0, y, 0], [0, 0, z], [x, 0, z], [x, y, z], [0, y, z]]
        let faces = [[0, 2, 1], [0, 3, 2], [4, 5, 6], [4, 6, 7], [0, 1, 5], [0, 5, 4],
                     [1, 2, 6], [1, 6, 5], [2, 3, 7], [2, 7, 6], [3, 0, 4], [3, 4, 7]]
        return Mesh(vertices: faces.flatMap { $0.flatMap { v[$0] } })
    }

    public func base64() -> String {
        vertices.withUnsafeBufferPointer { Data(buffer: $0) }.base64EncodedString()
    }

    public var bounds: Box3 {
        var lo = Vec3(.infinity, .infinity, .infinity), hi = Vec3(-.infinity, -.infinity, -.infinity)
        var i = 0
        while i < vertices.count {
            let x = Double(vertices[i]), y = Double(vertices[i + 1]), z = Double(vertices[i + 2])
            lo = Vec3(Swift.min(lo.x, x), Swift.min(lo.y, y), Swift.min(lo.z, z))
            hi = Vec3(Swift.max(hi.x, x), Swift.max(hi.y, y), Swift.max(hi.z, z))
            i += 3
        }
        return Box3(min: lo, max: hi)
    }

    /// Bounds after applying `matrix`, without building a new mesh.
    public func bounds(applying matrix: Mat3) -> Box3 {
        var lo = Vec3(.infinity, .infinity, .infinity), hi = Vec3(-.infinity, -.infinity, -.infinity)
        var i = 0
        while i < vertices.count {
            let v = matrix * Vec3(Double(vertices[i]), Double(vertices[i + 1]), Double(vertices[i + 2]))
            lo = Vec3(Swift.min(lo.x, v.x), Swift.min(lo.y, v.y), Swift.min(lo.z, v.z))
            hi = Vec3(Swift.max(hi.x, v.x), Swift.max(hi.y, v.y), Swift.max(hi.z, v.z))
            i += 3
        }
        return Box3(min: lo, max: hi)
    }

    /// Applies `matrix` around the origin, then moves the result so its
    /// bounding box is centred on (center.x, center.y) and rests on Z = 0.
    public func placed(matrix: Mat3, center: (x: Double, y: Double)) -> Mesh {
        var out = [Float](repeating: 0, count: vertices.count)
        var i = 0
        while i < vertices.count {
            let v = matrix * Vec3(Double(vertices[i]), Double(vertices[i + 1]), Double(vertices[i + 2]))
            out[i] = Float(v.x)
            out[i + 1] = Float(v.y)
            out[i + 2] = Float(v.z)
            i += 3
        }
        var mesh = Mesh(vertices: out)
        let b = mesh.bounds
        let dx = Float(center.x - b.center.x), dy = Float(center.y - b.center.y), dz = Float(-b.min.z)
        i = 0
        while i < mesh.vertices.count {
            mesh.vertices[i] += dx
            mesh.vertices[i + 1] += dy
            mesh.vertices[i + 2] += dz
            i += 3
        }
        return mesh
    }

    /// Rotation that puts the largest flat area of the mesh face down.
    /// Faces are grouped by (rounded) normal and their areas summed.
    public func layFlatRotation(applying current: Mat3 = .identity) -> Mat3 {
        var areas: [String: (normal: Vec3, area: Double)] = [:]
        var i = 0
        while i + 8 < vertices.count {
            let a = current * Vec3(Double(vertices[i]), Double(vertices[i + 1]), Double(vertices[i + 2]))
            let b = current * Vec3(Double(vertices[i + 3]), Double(vertices[i + 4]), Double(vertices[i + 5]))
            let c = current * Vec3(Double(vertices[i + 6]), Double(vertices[i + 7]), Double(vertices[i + 8]))
            i += 9
            let n = (b - a).cross(c - a)
            let area = n.length / 2
            guard area > 1e-9 else { continue }
            let u = n.normalized
            let key = String(format: "%.2f,%.2f,%.2f", u.x, u.y, u.z)
            let entry = areas[key] ?? (u, 0)
            areas[key] = (entry.normal, entry.area + area)
        }
        guard let best = areas.values.max(by: { $0.area < $1.area }) else { return current }
        return Mat3.rotation(from: best.normal, to: Vec3(0, 0, -1)) * current
    }
}
