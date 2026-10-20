import SnarwalCore
import SwiftUI

struct SliceTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                if model.plate.objects.isEmpty {
                    StartView()
                } else {
                    PlateScreen()
                }
            }
            .navigationDestination(isPresented: $model.showPreview) {
                PreviewScreen()
            }
        }
        .alert("Import fehlgeschlagen", isPresented: Binding(
            get: { model.importError != nil },
            set: { if !$0 { model.importError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.importError ?? "")
        }
    }
}

/// Opens the file picker and imports the chosen models.
struct ImportButton<Content: View>: View {
    @Environment(AppModel.self) private var model
    @State private var showPicker = false
    let label: () -> Content

    init(@ViewBuilder label: @escaping () -> Content) {
        self.label = label
    }

    var body: some View {
        Button {
            showPicker = true
        } label: {
            label()
        }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: AppModel.modelTypes, allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            Task {
                for url in urls {
                    await model.importFile(at: url)
                }
            }
        }
    }
}

struct StartView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            NarwhalMark()
                .frame(width: 132, height: 86)
            VStack(spacing: 6) {
                Text("Was druckst du heute?")
                    .font(.title2.bold())
                Text("STL oder 3MF öffnen – oder über „Teilen“ aus Safari, Printables oder MakerWorld schicken.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            ImportButton {
                Label("Modell öffnen", systemImage: "folder")
                    .font(.headline)
                    .frame(maxWidth: 300, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isImporting || model.engine.state != .ready)
            EngineStatusLine()
            Spacer()
        }
        .padding()
        .navigationTitle("Snarwal")
    }
}

struct EngineStatusLine: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.engine.state {
        case .loading:
            Label("Slicing-Engine startet …", systemImage: "hourglass")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .failed(let message):
            VStack(spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                Button("Erneut versuchen", systemImage: "arrow.clockwise") {
                    model.engine.restart()
                }
                .font(.subheadline)
            }
        case .ready:
            if model.isImporting {
                ProgressView("Modell wird geladen …")
                    .font(.footnote)
            }
        }
    }
}

/// The app's narwhal logo, drawn in code.
struct NarwhalMark: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width / 132, size.height / 86)
            context.scaleBy(x: s, y: s)
            var body = Path()
            body.move(to: CGPoint(x: 14, y: 54))
            body.addCurve(to: CGPoint(x: 58, y: 24), control1: CGPoint(x: 14, y: 37), control2: CGPoint(x: 32, y: 24))
            body.addCurve(to: CGPoint(x: 104, y: 46), control1: CGPoint(x: 80, y: 24), control2: CGPoint(x: 96, y: 33))
            body.addLine(to: CGPoint(x: 108, y: 53))
            body.addCurve(to: CGPoint(x: 103, y: 61), control1: CGPoint(x: 110, y: 57), control2: CGPoint(x: 107, y: 61))
            body.addLine(to: CGPoint(x: 40, y: 61))
            body.addCurve(to: CGPoint(x: 14, y: 54), control1: CGPoint(x: 25, y: 61), control2: CGPoint(x: 14, y: 59))
            body.closeSubpath()
            var tail = Path()
            tail.move(to: CGPoint(x: 14, y: 54))
            tail.addCurve(to: CGPoint(x: 4, y: 39), control1: CGPoint(x: 9, y: 51), control2: CGPoint(x: 5, y: 45))
            tail.addCurve(to: CGPoint(x: 18, y: 47), control1: CGPoint(x: 10, y: 40), control2: CGPoint(x: 15, y: 43))
            context.fill(body, with: .color(.accentColor))
            context.fill(tail, with: .color(.accentColor))
            var tusk = Path()
            tusk.move(to: CGPoint(x: 100, y: 40))
            tusk.addLine(to: CGPoint(x: 128, y: 6))
            context.stroke(tusk, with: .color(.primary), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: 89, y: 39, width: 6, height: 6)), with: .color(.white))
        }
        .accessibilityHidden(true)
    }
}
