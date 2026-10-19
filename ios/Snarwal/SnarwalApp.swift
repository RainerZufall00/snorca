import SwiftUI

@main
struct SnarwalApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .onOpenURL { url in
                    // files shared from Safari, Files or other apps
                    model.tab = .slice
                    Task { await model.importFile(at: url) }
                }
        }
    }
}

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            Tab("Slicen", systemImage: "cube", value: AppModel.Tab.slice) {
                SliceTab()
            }
            Tab("Drucker", systemImage: "printer", value: AppModel.Tab.printer) {
                PrinterTab()
            }
        }
        .background {
            // the slicing engine's WebView must live in the window to run
            EngineHost(engine: model.engine)
                .frame(width: 1, height: 1)
                .opacity(0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct EngineHost: UIViewRepresentable {
    let engine: SlicerEngine

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        container.addSubview(engine.webView)
        return container
    }

    func updateUIView(_ view: UIView, context: Context) {}
}
