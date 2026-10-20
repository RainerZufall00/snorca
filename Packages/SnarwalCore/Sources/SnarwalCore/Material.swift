import Foundation

/// Filament materials with Snarwal's own default values (MIT, not copied
/// from any slicer's profiles). Users can override temperatures per head.
public enum Material: String, CaseIterable, Codable, Sendable, Identifiable {
    case pla = "PLA"
    case petg = "PETG"
    case abs = "ABS"
    case asa = "ASA"
    case tpu = "TPU"
    case pva = "PVA"

    public var id: String { rawValue }

    public struct Defaults: Equatable, Sendable {
        public var nozzleTemp: Int
        public var firstLayerNozzleTemp: Int
        public var bedTemp: Int
        public var fanSpeed: Int          // 0...255
        public var density: Double        // g/cm³
        public var maxVolumetricFlow: Double // mm³/s
        public var retract: Double        // mm
    }

    public var defaults: Defaults {
        switch self {
        case .pla: Defaults(nozzleTemp: 220, firstLayerNozzleTemp: 220, bedTemp: 60, fanSpeed: 255, density: 1.24, maxVolumetricFlow: 21, retract: 0.8)
        case .petg: Defaults(nozzleTemp: 245, firstLayerNozzleTemp: 245, bedTemp: 75, fanSpeed: 140, density: 1.27, maxVolumetricFlow: 12, retract: 0.8)
        case .abs: Defaults(nozzleTemp: 255, firstLayerNozzleTemp: 255, bedTemp: 100, fanSpeed: 60, density: 1.04, maxVolumetricFlow: 16, retract: 0.8)
        case .asa: Defaults(nozzleTemp: 260, firstLayerNozzleTemp: 260, bedTemp: 100, fanSpeed: 60, density: 1.07, maxVolumetricFlow: 16, retract: 0.8)
        case .tpu: Defaults(nozzleTemp: 230, firstLayerNozzleTemp: 230, bedTemp: 50, fanSpeed: 255, density: 1.21, maxVolumetricFlow: 3.6, retract: 0.4)
        case .pva: Defaults(nozzleTemp: 215, firstLayerNozzleTemp: 215, bedTemp: 60, fanSpeed: 255, density: 1.23, maxVolumetricFlow: 8, retract: 0.8)
        }
    }

    /// Maps the printer's `filament_type` strings (RFID or manual entry).
    public init?(printerType: String) {
        let t = printerType.uppercased().trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t == "NONE" { return nil }
        if let exact = Material(rawValue: t) { self = exact; return }
        // sub types like "PLA-CF", "PETG HF", "PLA Matte"
        for material in Material.allCases where t.hasPrefix(material.rawValue) {
            self = material
            return
        }
        return nil
    }
}

/// What is loaded in one toolhead.
public struct HeadFilament: Equatable, Sendable, Identifiable, Codable {
    public var tool: Int
    public var material: Material
    /// `#RRGGBB`
    public var colorHex: String
    public var vendor: String?
    public var subType: String?
    /// Read from the printer (RFID / screen) rather than chosen in the app.
    public var fromPrinter: Bool
    public var loaded: Bool
    public var nozzleTemp: Int
    public var bedTemp: Int

    public var id: Int { tool }

    public init(tool: Int, material: Material = .pla, colorHex: String = "#FFFFFF", vendor: String? = nil,
                subType: String? = nil, fromPrinter: Bool = false, loaded: Bool = true,
                nozzleTemp: Int? = nil, bedTemp: Int? = nil) {
        self.tool = tool
        self.material = material
        self.colorHex = colorHex
        self.vendor = vendor
        self.subType = subType
        self.fromPrinter = fromPrinter
        self.loaded = loaded
        self.nozzleTemp = nozzleTemp ?? material.defaults.nozzleTemp
        self.bedTemp = bedTemp ?? material.defaults.bedTemp
    }

    /// "T1" … "T4" as printed on the U1.
    public var label: String { "T\(tool + 1)" }

    public static func defaults() -> [HeadFilament] {
        (0..<PrinterSpec.toolCount).map { HeadFilament(tool: $0, loaded: false) }
    }
}

public enum MaterialCheck {
    /// v1 slices with one nozzle temperature, so a plate may only use
    /// heads that hold the same material.
    public static func issues(plate: Plate, heads: [HeadFilament]) -> [PlateIssue] {
        let materials = Array(Set(plate.usedTools.compactMap { tool in heads.first { $0.tool == tool }?.material }))
            .sorted { $0.rawValue < $1.rawValue }
        return materials.count > 1 ? [.mixedMaterials(materials)] : []
    }
}
