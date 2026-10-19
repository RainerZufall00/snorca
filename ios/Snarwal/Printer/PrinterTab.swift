import SnarwalCore
import SwiftUI

struct PrinterTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            if model.printer.host.isEmpty {
                ConnectView()
            } else {
                PrinterScreen()
            }
        }
    }
}

/// Finds the U1 on the network or takes an address.
struct ConnectView: View {
    @Environment(AppModel.self) private var model
    @State private var discovery = PrinterDiscovery()
    @State private var address = ""
    @State private var searchedLong = false

    var body: some View {
        Form {
            Section {
                if discovery.printers.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Suche nach Snapmaker U1 im WLAN …").foregroundStyle(.secondary)
                    }
                    if searchedLong {
                        Text("Nichts gefunden? Prüfe, ob der U1 eingeschaltet und im selben WLAN ist und ob Snarwal in den iOS-Einstellungen unter Datenschutz → Lokales Netzwerk erlaubt ist. Du kannst die IP-Adresse auch unten eintragen.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(discovery.printers) { found in
                    Button {
                        model.printer.configure(host: found.host)
                    } label: {
                        HStack {
                            Image(systemName: "printer.fill")
                            VStack(alignment: .leading) {
                                Text(found.name).foregroundStyle(.primary)
                                Text(found.host).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Im Netzwerk gefunden")
            }
            Section {
                TextField("IP-Adresse oder Hostname", text: $address)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .onSubmit(connect)
                Button("Verbinden", action: connect)
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
            } header: {
                Text("Manuell")
            } footer: {
                Text("Die IP steht am Touchscreen des U1 unter Einstellungen → WLAN. Für unterwegs kannst du die Tailscale-Adresse eintragen.")
            }
        }
        .navigationTitle("Drucker verbinden")
        .onAppear { discovery.start() }
        .onDisappear { discovery.stop() }
        .task {
            try? await Task.sleep(for: .seconds(8))
            searchedLong = true
        }
    }

    private func connect() {
        model.printer.configure(host: address)
    }
}

struct PrinterScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmCancel = false
    @State private var fanDraft: Double?

    var body: some View {
        let printer = model.printer
        let status = printer.status
        ScrollView {
            VStack(spacing: 14) {
                if case .offline(let message) = printer.link {
                    WarningBanner(text: "Drucker nicht erreichbar: \(message)")
                }
                camera
                if let status, status.state.isActive {
                    progressCard(status)
                    controls(status)
                } else {
                    idleCard(status)
                }
                if let status {
                    temperatures(status)
                }
            }
            .padding()
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Snapmaker U1")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                statusChip(status)
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Text(printer.host)
                    Button("Anderen Drucker wählen", systemImage: "arrow.left.arrow.right") {
                        printer.forget()
                    }
                } label: {
                    Label("Drucker", systemImage: "gearshape")
                }
            }
        }
        .confirmationDialog("Druck wirklich abbrechen?", isPresented: $confirmCancel, titleVisibility: .visible) {
            Button("Druck abbrechen", role: .destructive) {
                Task { await printer.cancel() }
            }
            Button("Weiterdrucken", role: .cancel) {}
        } message: {
            Text("Der Druck kann danach nicht fortgesetzt werden.")
        }
        .alert("Aktion fehlgeschlagen", isPresented: Binding(
            get: { printer.lastError != nil },
            set: { if !$0 { printer.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(printer.lastError ?? "")
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { printer.startPolling() } else { printer.stopPolling() }
        }
    }

    @ViewBuilder
    private var camera: some View {
        ZStack {
            Color.snarwalViewport
            if let source = model.printer.camera {
                CameraView(source: source, websocketURL: model.printer.baseURL.flatMap { try? MoonrakerClient(host: $0.absoluteString).websocketURL })
            } else {
                ProgressView().tint(.white)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func statusChip(_ status: PrinterStatus?) -> some View {
        let (text, color): (LocalizedStringKey, Color) = switch (model.printer.link, status?.state) {
        case (.offline, _): ("Offline", .red)
        case (.connecting, _), (_, nil): ("Verbinde …", .secondary)
        case (_, .printing?): ("Druckt", .blue)
        case (_, .paused?): ("Pausiert", .orange)
        case (_, .error?): ("Fehler", .red)
        default: ("Bereit", .green)
        }
        return Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.14), in: Capsule())
            .accessibilityIdentifier("statusChip")
    }

    private func progressCard(_ status: PrinterStatus) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(status.filename).font(.headline).lineLimit(1)
                Spacer()
                Text("\(Int((status.progress * 100).rounded())) %")
                    .font(.title.bold())
                    .monospacedDigit()
            }
            ProgressView(value: status.progress)
            HStack {
                if let layer = status.currentLayer, let total = status.totalLayers, total > 0 {
                    Text("Schicht \(layer) / \(total)")
                }
                Spacer()
                if let remaining = model.printer.remaining {
                    Text("noch \(Format.duration(remaining))")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            if let tool = status.activeTool {
                let head = status.filaments.first { $0.tool == tool } ?? HeadFilament(tool: tool)
                HStack(spacing: 8) {
                    FilamentDot(color: head.color, size: 16)
                    Text("Aktiver Kopf: ") + Text(head.title).bold()
                }
                .font(.subheadline)
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func controls(_ status: PrinterStatus) -> some View {
        let printer = model.printer
        return HStack(spacing: 10) {
            if status.state == .paused {
                ControlButton(title: "Fortsetzen", icon: "play.fill") { Task { await printer.resume() } }
            } else {
                ControlButton(title: "Pause", icon: "pause.fill") { Task { await printer.pause() } }
            }
            ControlButton(title: "Abbrechen", icon: "stop.fill", tint: .red) { confirmCancel = true }
            ControlButton(title: status.lightOn ? "Licht an" : "Licht aus",
                          icon: status.lightOn ? "lightbulb.fill" : "lightbulb") {
                Task { await printer.setLight(!status.lightOn) }
            }
        }
    }

    private func idleCard(_ status: PrinterStatus?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(status?.state == .complete ? "Druck fertig" as LocalizedStringKey : "Kein aktiver Druck").font(.headline)
            Text("Slice ein Modell und schick es an den U1 – hier siehst du dann Fortschritt, Kamera und Steuerung.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let status {
                Button {
                    Task { await model.printer.setLight(!status.lightOn) }
                } label: {
                    Label(status.lightOn ? "Licht ausschalten" : "Licht einschalten",
                          systemImage: status.lightOn ? "lightbulb.fill" : "lightbulb")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func temperatures(_ status: PrinterStatus) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Temperaturen")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.vertical, 8)
            ForEach(0..<PrinterSpec.toolCount, id: \.self) { tool in
                let head = status.filaments.first { $0.tool == tool } ?? HeadFilament(tool: tool)
                heaterRow(dot: head.color, title: head.loaded ? head.title : String(localized: "\(head.label) · leer"), heater: status.nozzles[tool])
            }
            heaterRow(dot: .gray, title: String(localized: "Bett"), heater: status.bed)
            VStack(alignment: .leading) {
                HStack {
                    Text("Bauteillüfter")
                    Spacer()
                    Text("\(Int(((fanDraft ?? status.partFan) * 100).rounded())) %").monospacedDigit().bold()
                }
                Slider(value: Binding(get: { fanDraft ?? status.partFan }, set: { fanDraft = $0 }),
                       in: 0...1,
                       step: 0.05,
                       label: { Text("Bauteillüfter") },
                       onEditingChanged: { editing in
                           // send once when the finger lifts, not on every step
                           guard !editing, let value = fanDraft else { return }
                           Task {
                               await model.printer.setPartFan(value)
                               fanDraft = nil
                           }
                       })
            }
            .padding(.vertical, 10)
        }
        .padding(.horizontal, 14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func heaterRow(dot: Color, title: String, heater: HeaterState) -> some View {
        HStack {
            FilamentDot(color: dot, size: 16)
            Text(title).font(.subheadline)
            Spacer()
            Text(Format.temperature(heater.temperature)).bold().monospacedDigit()
            Text(verbatim: "/ " + (heater.target > 0 ? Format.temperature(heater.target) : String(localized: "aus")))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 9)
    }
}

private struct ControlButton: View {
    let title: LocalizedStringKey
    let icon: String
    var tint: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.title3)
                Text(title).font(.footnote.weight(.semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .foregroundStyle(tint)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
