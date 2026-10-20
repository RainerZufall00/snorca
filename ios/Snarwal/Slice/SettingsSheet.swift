import SnarwalCore
import SwiftUI

struct SettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("Qualität") {
                    Picker("Schichthöhe", selection: $model.settings.quality) {
                        Text("Fein · 0,12 mm").tag(Quality.fine)
                        Text("Normal · 0,20 mm").tag(Quality.normal)
                        Text("Schnell · 0,28 mm").tag(Quality.fast)
                    }
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Infill")
                            Spacer()
                            Text("\(model.settings.infill) %").monospacedDigit().bold()
                        }
                        Slider(value: Binding(
                            get: { Double(model.settings.infill) },
                            set: { model.settings.infill = Int($0) }),
                               in: 0...100, step: 5) {
                            Text("Infill")
                        }
                    }
                    Toggle("Stützen", isOn: $model.settings.supports)
                        .accessibilityIdentifier("supportsToggle")
                    Toggle("Brim", isOn: $model.settings.brim)
                }

                if model.printer.status?.filaments.contains(where: \.loaded) == true {
                    Section {
                        ForEach(model.heads) { head in
                            HStack(spacing: 12) {
                                FilamentDot(color: head.color)
                                VStack(alignment: .leading) {
                                    Text(head.title)
                                    if let vendor = head.vendor {
                                        Text(vendor).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(head.loaded ? Format.temperature(Double(head.nozzleTemp)) : String(localized: "leer"))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Filament im Drucker")
                    } footer: {
                        Text("Vom U1 gelesen (RFID oder Touchscreen). Temperaturen kommen aus den Snarwal-Standardwerten des Materials.")
                    }
                } else {
                    Section {
                        ForEach($model.manualHeads) { $head in
                            ManualHeadRow(head: $head)
                        }
                    } header: {
                        Text("Filament pro Kopf")
                    } footer: {
                        Text("Sobald ein Drucker verbunden ist, liest Snarwal das geladene Filament automatisch aus.")
                    }
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ManualHeadRow: View {
    @Binding var head: HeadFilament

    var body: some View {
        HStack(spacing: 12) {
            ColorPicker(selection: Binding(
                get: { head.color },
                set: { head.colorHex = $0.hexString }),
                        supportsOpacity: false) {
                Text(head.label).bold()
            }
            .fixedSize()
            Spacer()
            Picker("Material", selection: Binding(
                get: { head.material },
                set: { material in
                    head.material = material
                    head.nozzleTemp = material.defaults.nozzleTemp
                    head.bedTemp = material.defaults.bedTemp
                })) {
                ForEach(Material.allCases) { material in
                    Text(material.rawValue).tag(material)
                }
            }
            .labelsHidden()
            Stepper(value: $head.nozzleTemp, in: 170...300, step: 5) {
                Text(Format.temperature(Double(head.nozzleTemp))).monospacedDigit()
            }
            .fixedSize()
        }
    }
}
