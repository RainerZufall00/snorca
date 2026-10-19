import SnarwalCore
import SwiftUI

/// "Jetzt drucken?" – compares the plan with what is loaded in the printer.
struct SendSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var sending = false
    @State private var uploaded = false

    var body: some View {
        NavigationStack {
            Group {
                if let result = model.result {
                    content(result)
                }
            }
            .navigationTitle("Jetzt drucken?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .alert("Senden fehlgeschlagen", isPresented: Binding(
            get: { model.printer.lastError != nil },
            set: { if !$0 { model.printer.lastError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.printer.lastError ?? "")
        }
    }

    private func content(_ result: AppModel.SliceResult) -> some View {
        let printer = model.printer
        let checks = headChecks(result)
        let busy = printer.status?.state.isActive == true
        return Form {
            Section {
                if let summary = result.summary {
                    LabeledContent("Druckzeit", value: Format.duration(summary.printTime))
                    LabeledContent("Filament", value: Format.grams(summary.totalGrams))
                }
                LabeledContent("Datei", value: result.filename)
            }
            Section("Köpfe") {
                ForEach(checks, id: \.tool) { check in
                    HStack(spacing: 10) {
                        FilamentDot(color: check.planned.color, size: 20)
                        Text(check.planned.title)
                        Spacer()
                        switch check.state {
                        case .ok:
                            Label("geladen", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                        case .unknown:
                            Label("unbekannt", systemImage: "questionmark.circle").foregroundStyle(.secondary)
                        case .empty:
                            Label("leer", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        case .different(let loaded):
                            Label("im Drucker: \(loaded)", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                    }
                    .font(.subheadline)
                }
            }
            Section {
                if printer.host.isEmpty {
                    Text("Noch kein Drucker eingerichtet.")
                        .foregroundStyle(.secondary)
                    Button {
                        dismiss()
                        model.showPreview = false
                        model.tab = .printer
                    } label: {
                        Label("Drucker verbinden", systemImage: "printer")
                    }
                } else if printer.link != .online {
                    Text("Der U1 ist gerade nicht erreichbar. Ist er eingeschaltet und im selben WLAN?")
                        .foregroundStyle(.secondary)
                } else if busy {
                    Text("Der U1 druckt gerade. Du kannst die Datei hochladen und später starten.")
                        .foregroundStyle(.secondary)
                }
                if uploaded {
                    Label("Auf den U1 hochgeladen", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Button {
                    send(result, start: true)
                } label: {
                    HStack {
                        if sending { ProgressView() }
                        Text("Drucken").bold()
                    }
                    .frame(maxWidth: .infinity)
                }
                .disabled(printer.link != .online || busy || sending)
                .accessibilityIdentifier("printButton")
                Button("Nur hochladen") {
                    send(result, start: false)
                }
                .frame(maxWidth: .infinity)
                .disabled(printer.link != .online || sending)
            }
        }
    }

    private func send(_ result: AppModel.SliceResult, start: Bool) {
        sending = true
        Task {
            let ok = await model.printer.upload(gcode: result.gcode, filename: result.filename, start: start)
            sending = false
            guard ok else { return }
            if start {
                dismiss()
                model.showPreview = false
                model.tab = .printer
            } else {
                uploaded = true
            }
        }
    }

    struct HeadCheck {
        enum Status { case ok, unknown, empty, different(String) }
        var tool: Int
        var planned: HeadFilament
        var state: Status
    }

    private func headChecks(_ result: AppModel.SliceResult) -> [HeadCheck] {
        let used = result.summary.map { summary in
            summary.gramsPerTool.enumerated().filter { $0.element > 0 }.map(\.offset)
        } ?? model.plate.usedTools
        let loaded = model.printer.status?.filaments
        return used.map { tool in
            let planned = model.heads.first { $0.tool == tool } ?? HeadFilament(tool: tool)
            guard let head = loaded?.first(where: { $0.tool == tool }) else {
                return HeadCheck(tool: tool, planned: planned, state: .unknown)
            }
            if !head.loaded { return HeadCheck(tool: tool, planned: planned, state: .empty) }
            if head.material != planned.material {
                return HeadCheck(tool: tool, planned: planned, state: .different(head.material.rawValue))
            }
            return HeadCheck(tool: tool, planned: planned, state: .ok)
        }
    }
}
