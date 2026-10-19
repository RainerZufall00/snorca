import SnarwalCore
import SwiftUI

struct PreviewScreen: View {
    @Environment(AppModel.self) private var model
    @State private var layer: Double = 0
    @State private var showSend = false

    var body: some View {
        if let result = model.result {
            content(result)
        } else {
            ContentUnavailableView("Keine Vorschau", systemImage: "square.stack.3d.up.slash",
                                   description: Text("Slice zuerst die Druckplatte."))
        }
    }

    private func content(_ result: AppModel.SliceResult) -> some View {
        let layers = result.preview.layers
        let index = min(max(Int(layer.rounded()), 0), max(layers.count - 1, 0))
        return ScrollView {
            VStack(spacing: 16) {
                LayerCanvas(preview: result.preview, index: index, heads: model.heads)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 520)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                if layers.count > 1 {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Schicht \(index + 1) / \(layers.count)").bold()
                            Spacer()
                            Text("Z \(layers[index].z.formatted(.number.precision(.fractionLength(2)))) mm")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $layer, in: 0...Double(layers.count - 1), step: 1) {
                            Text("Schicht")
                        }
                    }
                    .frame(maxWidth: 520)
                }
                stats(result)
                    .frame(maxWidth: 520)
                VStack(spacing: 10) {
                    Button {
                        showSend = true
                    } label: {
                        Text("An U1 senden").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    if let url = result.fileURL {
                        ShareLink(item: url) {
                            Label("G-Code teilen", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                .frame(maxWidth: 520)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Vorschau")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if layer == 0 { layer = Double(max(layers.count / 2, 0)) }
        }
        .sheet(isPresented: $showSend) {
            SendSheet()
        }
    }

    @ViewBuilder
    private func stats(_ result: AppModel.SliceResult) -> some View {
        if let summary = result.summary {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    StatTile(title: "Druckzeit", value: Format.duration(summary.printTime))
                    StatTile(title: "Filament", value: Format.grams(summary.totalGrams))
                }
                VStack(spacing: 0) {
                    ForEach(Array(summary.gramsPerTool.enumerated()), id: \.offset) { tool, grams in
                        if grams > 0 {
                            let head = model.heads.first { $0.tool == tool } ?? HeadFilament(tool: tool)
                            HStack {
                                FilamentDot(color: head.color, size: 18)
                                Text(head.title)
                                Spacer()
                                Text(Format.grams(grams)).monospacedDigit().bold()
                            }
                            .padding(.vertical, 10)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .background(.background, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}

struct StatTile: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            Text(value).font(.title3.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Top view of one layer; the layer below is drawn faintly for context.
private struct LayerCanvas: View {
    let preview: GCodePreview
    let index: Int
    let heads: [HeadFilament]

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.snarwalViewport))
            guard preview.layers.indices.contains(index) else { return }
            let scale = size.width / PrinterSpec.bedWidth
            if index > 0 {
                draw(preview.layers[index - 1], in: &context, scale: scale, height: size.height, opacity: 0.18, width: 1)
            }
            draw(preview.layers[index], in: &context, scale: scale, height: size.height, opacity: 1, width: max(1, 0.45 * scale))
        }
        .accessibilityLabel("Schichtansicht von oben")
    }

    static func luminance(_ hex: String) -> Double {
        let value = UInt32(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).prefix(6), radix: 16) ?? 0xFFFFFF
        let r = Double((value >> 16) & 0xFF), g = Double((value >> 8) & 0xFF), b = Double(value & 0xFF)
        return (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255
    }

    private func draw(_ layer: GCodePreview.Layer, in context: inout GraphicsContext, scale: CGFloat, height: CGFloat,
                      opacity: Double, width: CGFloat) {
        for (tool, segments) in layer.segments {
            var path = Path()
            var i = 0
            while i + 3 < segments.count {
                // bed Y grows away from the viewer; screen Y grows down
                path.move(to: CGPoint(x: CGFloat(segments[i]) * scale, y: height - CGFloat(segments[i + 1]) * scale))
                path.addLine(to: CGPoint(x: CGFloat(segments[i + 2]) * scale, y: height - CGFloat(segments[i + 3]) * scale))
                i += 4
            }
            let hex = heads.first { $0.tool == tool }?.colorHex ?? "#E8792B"
            // very dark filament would vanish on the dark background
            let color = Self.luminance(hex) < 0.2 ? Color.gray : Color(hex: hex)
            context.stroke(path, with: .color(color.opacity(opacity)), lineWidth: width)
        }
    }
}
