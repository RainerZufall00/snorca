import SnarwalCore
import SwiftUI

struct PlateScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showSettings = false

    var body: some View {
        Group {
            if sizeClass == .regular {
                HStack(spacing: 0) {
                    viewport
                    Divider()
                    ScrollView {
                        controls.padding()
                    }
                    .frame(width: 360)
                    .background(Color(.systemGroupedBackground))
                }
            } else {
                VStack(spacing: 0) {
                    viewport
                        .frame(maxHeight: 360)
                    ScrollView {
                        controls.padding()
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
        }
        .navigationTitle(model.projectName.isEmpty ? "Druckplatte" : model.projectName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ImportButton {
                    Label("Objekt hinzufügen", systemImage: "plus")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("Platte leeren", systemImage: "trash", role: .destructive) {
                        model.clearPlate()
                    }
                } label: {
                    Label("Mehr", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
        }
    }

    private var viewport: some View {
        VStack(spacing: 0) {
            PlateSceneView(objects: model.plate.objects, heads: model.heads, selectedID: model.selectedID) { id in
                model.selectedID = id
            }
            ObjectToolbar()
        }
        .background(Color.snarwalViewport)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            ObjectStrip()
            ForEach(Array(model.issues.enumerated()), id: \.offset) { _, issue in
                WarningBanner(text: issue.message)
            }
            ForEach(model.importNotes, id: \.self) { note in
                WarningBanner(text: note)
            }
            QualityPicker()
            Button {
                showSettings = true
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Einstellungen").font(.headline)
                        Text(settingsSummary).font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                }
                .padding(14)
                .background(.background, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            SliceButton()
        }
    }

    private var settingsSummary: String {
        let s = model.settings
        let supports = s.supports ? String(localized: "an") : String(localized: "aus")
        let brim = s.brim ? String(localized: "an") : String(localized: "aus")
        return String(localized: "Infill \(s.infill) % · Stützen \(supports) · Brim \(brim)")
    }
}

struct WarningBanner: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(.subheadline)
            .foregroundStyle(Color(red: 0.42, green: 0.25, blue: 0))
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 1, green: 0.96, blue: 0.88), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Edit tools for the selected object.
private struct ObjectToolbar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let hasSelection = model.selectedIndex != nil
        HStack {
            tool("Drehen", "arrow.clockwise") { model.rotateSelected() }
                .disabled(!hasSelection)
            Menu {
                ForEach([0.5, 0.8, 1.0, 1.2, 1.5, 2.0], id: \.self) { factor in
                    Button("\(Int(factor * 100)) %") { model.setScaleSelected(factor) }
                }
            } label: {
                toolLabel("Skalieren", "arrow.up.left.and.arrow.down.right")
            }
            .disabled(!hasSelection)
            tool("Flachlegen", "square.bottomhalf.filled") { model.layFlatSelected() }
                .disabled(!hasSelection)
            tool("Anordnen", "square.grid.2x2") { model.arrange() }
            Menu {
                Button("Duplizieren", systemImage: "plus.square.on.square") { model.duplicateSelected() }
                Button("Entfernen", systemImage: "trash", role: .destructive) { model.removeSelected() }
            } label: {
                toolLabel("Objekt", "ellipsis")
            }
            .disabled(!hasSelection)
        }
        .foregroundStyle(Color(white: 0.82))
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    private func tool(_ title: LocalizedStringKey, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { toolLabel(title, icon) }
    }

    private func toolLabel(_ title: LocalizedStringKey, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title3)
            Text(title).font(.caption2)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .contentShape(Rectangle())
    }
}

/// Objects on the plate; the dot picks the head.
private struct ObjectStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.plate.objects) { object in
                    chip(object)
                }
            }
        }
    }

    private func chip(_ object: PlateObject) -> some View {
        let head = model.heads.first { $0.tool == object.tool } ?? HeadFilament(tool: object.tool)
        let selected = object.id == model.selectedID
        return HStack(spacing: 8) {
            Menu {
                ForEach(model.heads) { h in
                    Button {
                        model.setTool(h.tool, for: object.id)
                    } label: {
                        Label(h.title, systemImage: h.tool == object.tool ? "checkmark" : "circle.fill")
                    }
                }
            } label: {
                FilamentDot(color: head.color, size: 26)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("\(object.name): Kopf wählen")
            Button {
                model.selectedID = object.id
            } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(object.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(head.title + (object.scale != 1 ? " · \(Int(object.scale * 100)) %" : ""))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.trailing, 12)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .background(.background, in: Capsule())
        .overlay(Capsule().strokeBorder(selected ? Color.accentColor : Color(.separator), lineWidth: selected ? 2 : 1))
    }
}

private struct QualityPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Picker("Qualität", selection: $model.settings.quality) {
            Text("Fein · 0,12").tag(Quality.fine)
            Text("Normal · 0,20").tag(Quality.normal)
            Text("Schnell · 0,28").tag(Quality.fast)
        }
        .pickerStyle(.segmented)
    }
}

private struct SliceButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            if case .failed(let message) = model.sliceState {
                WarningBanner(text: "Slicen fehlgeschlagen: \(message)")
            }
            Button {
                Task { await model.slice() }
            } label: {
                Group {
                    if case .slicing = model.sliceState {
                        HStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("Wird geslict … \(Int(model.engine.progress * 100)) %")
                        }
                    } else {
                        Text("Slicen")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canSlice || isSlicing)
            if model.result != nil, !isSlicing {
                Button("Letzte Vorschau öffnen") { model.showPreview = true }
                    .font(.subheadline)
            }
        }
    }

    private var isSlicing: Bool {
        if case .slicing = model.sliceState { return true }
        return false
    }
}
