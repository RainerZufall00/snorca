import Foundation

public enum PrintState: String, Sendable {
    case standby, printing, paused, complete, cancelled, error
    case unknown

    public var isActive: Bool { self == .printing || self == .paused }
}

public struct HeaterState: Equatable, Sendable {
    public var temperature: Double
    public var target: Double

    public init(temperature: Double = 0, target: Double = 0) {
        self.temperature = temperature
        self.target = target
    }
}

/// Snapshot of the printer, built from a Moonraker `printer/objects/query`.
public struct PrinterStatus: Equatable, Sendable {
    public var state: PrintState = .unknown
    public var message: String = ""
    public var filename: String = ""
    /// 0...1
    public var progress: Double = 0
    public var printDuration: TimeInterval = 0
    public var currentLayer: Int?
    public var totalLayers: Int?
    /// 0-based head index, from `toolhead.extruder` ("extruder2" → 2).
    public var activeTool: Int?
    public var nozzles: [HeaterState] = Array(repeating: HeaterState(), count: PrinterSpec.toolCount)
    public var bed = HeaterState()
    /// 0...1
    public var partFan: Double = 0
    public var lightOn = false
    public var filaments: [HeadFilament] = HeadFilament.defaults()

    public init() {}

    /// Objects to request; see `init(objects:)`.
    public static let queryObjects = [
        "print_stats", "virtual_sdcard", "toolhead", "extruder", "extruder1", "extruder2", "extruder3",
        "heater_bed", "fan", "led cavity_led", "print_task_config",
    ]

    static func extruderName(_ tool: Int) -> String { tool == 0 ? "extruder" : "extruder\(tool)" }

    /// `objects` is `result.status` of a `printer/objects/query` response.
    public init(objects: [String: Any]) {
        if let stats = objects["print_stats"] as? [String: Any] {
            state = PrintState(rawValue: stats["state"] as? String ?? "") ?? .unknown
            message = stats["message"] as? String ?? ""
            filename = stats["filename"] as? String ?? ""
            printDuration = (stats["print_duration"] as? NSNumber)?.doubleValue ?? 0
            if let info = stats["info"] as? [String: Any] {
                currentLayer = (info["current_layer"] as? NSNumber)?.intValue
                totalLayers = (info["total_layer"] as? NSNumber)?.intValue
            }
        }
        if let sd = objects["virtual_sdcard"] as? [String: Any] {
            progress = (sd["progress"] as? NSNumber)?.doubleValue ?? 0
        }
        if let toolhead = objects["toolhead"] as? [String: Any], let name = toolhead["extruder"] as? String {
            activeTool = name == "extruder" ? 0 : Int(name.dropFirst("extruder".count))
        }
        for tool in 0..<PrinterSpec.toolCount {
            if let heater = objects[Self.extruderName(tool)] as? [String: Any] {
                nozzles[tool] = Self.heater(heater)
            }
        }
        if let heater = objects["heater_bed"] as? [String: Any] {
            bed = Self.heater(heater)
        }
        if let fan = objects["fan"] as? [String: Any] {
            partFan = (fan["speed"] as? NSNumber)?.doubleValue ?? 0
        }
        if let led = objects["led cavity_led"] as? [String: Any],
           let data = led["color_data"] as? [[NSNumber]], let first = data.first, first.count >= 4 {
            lightOn = first[3].doubleValue > 0 || first[0].doubleValue > 0
        }
        if let config = objects["print_task_config"] as? [String: Any] {
            filaments = Self.filaments(config)
        }
    }

    static func heater(_ dict: [String: Any]) -> HeaterState {
        HeaterState(temperature: (dict["temperature"] as? NSNumber)?.doubleValue ?? 0,
                    target: (dict["target"] as? NSNumber)?.doubleValue ?? 0)
    }

    /// `print_task_config` holds per-head arrays filled from RFID tags or the touchscreen.
    static func filaments(_ config: [String: Any]) -> [HeadFilament] {
        let types = config["filament_type"] as? [String] ?? []
        let colors = config["filament_color_rgba"] as? [String] ?? []
        let exists = config["filament_exist"] as? [Bool] ?? []
        let vendors = config["filament_vendor"] as? [String] ?? []
        let subTypes = config["filament_sub_type"] as? [String] ?? []
        return (0..<PrinterSpec.toolCount).map { tool in
            let type = tool < types.count ? types[tool] : "NONE"
            let material = Material(printerType: type)
            let rgba = tool < colors.count ? colors[tool] : "FFFFFFFF"
            let vendor = tool < vendors.count ? vendors[tool] : "NONE"
            let subType = tool < subTypes.count ? subTypes[tool] : "NONE"
            return HeadFilament(
                tool: tool,
                material: material ?? .pla,
                colorHex: "#" + String(rgba.prefix(6)).uppercased(),
                vendor: vendor == "NONE" ? nil : vendor,
                subType: subType == "NONE" ? nil : subType,
                fromPrinter: true,
                loaded: (tool < exists.count ? exists[tool] : false) && material != nil)
        }
    }

    /// Remaining time from the slicer estimate when known, else extrapolated.
    public func remaining(estimatedTotal: TimeInterval?) -> TimeInterval? {
        if let estimatedTotal, estimatedTotal > 0 {
            return max(0, estimatedTotal - printDuration)
        }
        guard progress > 0.02 else { return nil }
        return printDuration / progress - printDuration
    }
}
