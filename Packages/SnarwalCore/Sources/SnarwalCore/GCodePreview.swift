import Foundation

/// Extrusion paths per layer, for the layer preview.
public struct GCodePreview: Sendable {
    public struct Layer: Sendable {
        public var z: Double
        /// Per tool: flat list of line segments x0, y0, x1, y1 (bed millimetres).
        public var segments: [Int: [Float]]
    }

    public var layers: [Layer]
    /// Extent of all extrusions (minX, minY, maxX, maxY), nil without any.
    public var bounds: (minX: Float, minY: Float, maxX: Float, maxY: Float)?

    /// Parses G-code written by the Snarwal U1 profile: absolute XY,
    /// relative extrusion, and `;BEFORE_LAYER_CHANGE` / `;<z>` markers.
    public init(gcode: String) {
        var layers: [Layer] = []
        var current: Layer?
        var tool = 0
        var x = 0.0, y = 0.0
        var expectZ = false
        var printing = false

        gcode.enumerateLines { line, _ in
            if line.hasPrefix(";BEFORE_LAYER_CHANGE") {
                printing = true
                if let layer = current, !layer.segments.isEmpty { layers.append(layer) }
                current = Layer(z: 0, segments: [:])
                expectZ = true
                return
            }
            if expectZ {
                expectZ = false
                if line.hasPrefix(";"), let z = Double(line.dropFirst()) {
                    current?.z = z
                    return
                }
            }
            if line.hasPrefix("T"), let t = Int(line.dropFirst().prefix { $0.isNumber }) {
                tool = t
                return
            }
            guard line.hasPrefix("G1 ") || line.hasPrefix("G0 ") else { return }
            let code = line.split(separator: ";", maxSplits: 1).first ?? ""
            var nx = x, ny = y, e = 0.0
            for word in code.split(separator: " ").dropFirst() {
                guard let axis = word.first, let value = Double(word.dropFirst()) else { continue }
                switch axis {
                case "X": nx = value
                case "Y": ny = value
                case "E": e = value
                default: break
                }
            }
            // positions are tracked from the start; paths only once layers begin
            if printing && e > 0 && (nx != x || ny != y) {
                current?.segments[tool, default: []].append(contentsOf: [Float(x), Float(y), Float(nx), Float(ny)])
            }
            x = nx
            y = ny
        }
        if let layer = current, !layer.segments.isEmpty { layers.append(layer) }
        self.layers = layers
        var minX = Float.infinity, minY = Float.infinity, maxX = -Float.infinity, maxY = -Float.infinity
        for layer in layers {
            for segments in layer.segments.values {
                var i = 0
                while i + 1 < segments.count {
                    minX = min(minX, segments[i]); maxX = max(maxX, segments[i])
                    minY = min(minY, segments[i + 1]); maxY = max(maxY, segments[i + 1])
                    i += 2
                }
            }
        }
        bounds = minX <= maxX ? (minX, minY, maxX, maxY) : nil
    }
}

/// Totals from the Orca-style footer the engine appends.
public struct GCodeSummary: Equatable, Sendable {
    public var printTime: TimeInterval
    public var layers: Int
    public var gramsPerTool: [Double]

    public var totalGrams: Double { gramsPerTool.reduce(0, +) }

    public init?(gcode: String) {
        let tail = gcode.suffix(8192)
        var time: TimeInterval?
        var layers: Int?
        var grams: [Double]?
        for line in tail.split(separator: "\n") {
            if line.hasPrefix("; estimated printing time (normal mode) = ") {
                time = Self.parseDuration(String(line.split(separator: "=").last ?? ""))
            } else if line.hasPrefix("; total layers count = ") {
                layers = Int(line.split(separator: "=").last?.trimmingCharacters(in: .whitespaces) ?? "")
            } else if line.hasPrefix("; filament used [g] = ") {
                grams = line.split(separator: "=").last?.split(separator: ",")
                    .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            }
        }
        guard let time, let layers, let grams else { return nil }
        self.printTime = time
        self.layers = layers
        self.gramsPerTool = grams
    }

    /// "1d 2h 3m 4s" → seconds
    static func parseDuration(_ text: String) -> TimeInterval {
        var total = 0.0
        for part in text.split(separator: " ") {
            guard let unit = part.last, let value = Double(part.dropLast()) else { continue }
            switch unit {
            case "d": total += value * 86400
            case "h": total += value * 3600
            case "m": total += value * 60
            case "s": total += value
            default: break
            }
        }
        return total
    }
}
