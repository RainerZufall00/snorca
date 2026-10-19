import SnarwalCore
import SwiftUI
import UIKit

extension Color {
    /// `#RRGGBB` → Color; invalid input gives gray.
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt32(digits.prefix(6), radix: 16) ?? 0x808080
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    /// Color → `#RRGGBB`
    var hexString: String {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    static let snarwalViewport = Color(red: 0.063, green: 0.110, blue: 0.149)
}

extension HeadFilament {
    var color: Color { Color(hex: colorHex) }

    /// "PLA Weiß"-style description, e.g. "T2 · PLA (Snapmaker)".
    var title: String {
        var text = "\(label) · \(material.rawValue)"
        if let subType, !subType.isEmpty { text += " \(subType)" }
        return text
    }
}

/// Round swatch for a head's filament color.
struct FilamentDot: View {
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        Circle()
            .fill(color)
            .overlay(Circle().strokeBorder(.primary.opacity(0.25), lineWidth: 1))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

enum Format {
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60
        return h > 0 ? "\(h) h \(m) min" : "\(max(m, 1)) min"
    }

    static func grams(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + " g"
    }

    static func temperature(_ value: Double) -> String {
        "\(Int(value.rounded())) °C"
    }
}

extension PlateIssue {
    var message: String {
        switch self {
        case .outsideBed(let name):
            "„\(name)“ liegt außerhalb des Druckbetts."
        case .tooTall(let name):
            "„\(name)“ ist höher als 270 mm."
        case .mixedMaterials(let materials):
            "Gemischte Materialien (\(materials.map(\.rawValue).joined(separator: " + "))) werden in Version 1 noch nicht unterstützt. Bitte nur Köpfe mit gleichem Material verwenden."
        case .paintedModel(let name):
            "„\(name)“ ist bemalt; die Bemalung wird ignoriert."
        }
    }
}
