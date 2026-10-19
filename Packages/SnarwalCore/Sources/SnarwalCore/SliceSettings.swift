import Foundation

public enum Quality: String, CaseIterable, Codable, Sendable, Identifiable {
    case fine, normal, fast

    public var id: String { rawValue }

    public var layerHeight: Double {
        switch self {
        case .fine: 0.12
        case .normal: 0.2
        case .fast: 0.28
        }
    }

    /// Print speed for infill and inner walls (mm/s).
    var feedrate: Double {
        switch self {
        case .fine: 100
        case .normal: 120
        case .fast: 150
        }
    }
}

/// The handful of settings v1 exposes; everything else comes from the
/// engine's U1 base process.
public struct SliceSettings: Equatable, Codable, Sendable {
    public var quality: Quality = .normal
    /// 0...100 %
    public var infill: Int = 15
    public var supports: Bool = false
    public var brim: Bool = false

    public init(quality: Quality = .normal, infill: Int = 15, supports: Bool = false, brim: Bool = false) {
        self.quality = quality
        self.infill = infill
        self.supports = supports
        self.brim = brim
    }

    /// Kiri:Moto process overrides for `snarwal.slice({ process })`.
    /// Temperatures come from the head printing the first layer; v1 only
    /// allows one material per plate, so they match for all heads.
    public func kiriProcess(firstHead head: HeadFilament) -> [String: KiriValue] {
        let m = head.material.defaults
        let lh = quality.layerHeight
        // keep volumetric flow within the material's limit at 0.45 mm line width
        let maxSpeed = m.maxVolumetricFlow / (lh * 0.45)
        let feed = min(quality.feedrate, maxSpeed.rounded(.down))
        return [
            "sliceHeight": .number(lh),
            "firstSliceHeight": .number(0.2),
            "sliceFillSparse": .number(Double(min(max(infill, 0), 100)) / 100),
            "sliceSupportType": .string(supports ? "automatic" : "disabled"),
            "outputBrimCount": .number(brim ? 5 : 0),
            "outputTemp": .number(Double(head.nozzleTemp)),
            "firstLayerNozzleTemp": .number(Double(head.nozzleTemp + m.firstLayerNozzleTemp - m.nozzleTemp)),
            "outputBedTemp": .number(Double(head.bedTemp)),
            "firstLayerBedTemp": .number(Double(head.bedTemp)),
            "outputFanSpeed": .number(Double(m.fanSpeed)),
            "outputFeedrate": .number(feed),
            "outputFinishrate": .number(min(feed, 80)),
            "outputRetractDist": .number(m.retract),
            "outputMaxFlowrate": .number(m.maxVolumetricFlow),
        ]
    }
}

/// JSON value passed into the slicing engine.
public enum KiriValue: Equatable, Sendable, Encodable {
    case number(Double)
    case string(String)
    case bool(Bool)

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        }
    }

    /// Plain Foundation value, for WKWebView `callAsyncJavaScript` arguments.
    public var foundationValue: Any {
        switch self {
        case .number(let v): v
        case .string(let v): v
        case .bool(let v): v
        }
    }
}
