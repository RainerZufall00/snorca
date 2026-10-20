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
                        VStack(spacing: 14) {
                            controls
                            SliceButton()
                        }
                        .padding()
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
                    .accessibilityIdentifier("controls")
                    // the main action stays visible however long the list gets
                    .safeAreaInset(edge: .bottom) {
                        SliceButton()
                            .padding(.horizontal)
                            .padding(.vertical, 10)
                            .background(.bar)
                    }
                }
            }
        }
        .navigationTitle(model.projectName.isEmpty ? String(localized: "Druckplatte") : model.projectName)
        .navigationBarTitleDisplayMode(.inline)
        // the bar sits on the dark 3D viewport
        .toolbarBackground(Color.snarwalViewport, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
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
            PlateSceneView(objects: model.plate.objects, heads: model.heads, selectedID: model.selectedID,
                           onSelect: { id in model.selectedID = id },
                           onMove: { id, x, y in model.move(id, to: (x, y)) },
                           onMoveEnded: { model.finishMove() })
            ObjectToolbar()
        }
        .background(Color.snarwalViewport)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            ObjectStrip()
            SelectionPanel()
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
            .accessibilityIdentifier("settingsButton")
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
                .accessibilityIdentifier("tool-rotate")
            Menu {
                ForEach([0.5, 0.8, 1.0, 1.2, 1.5, 2.0], id: \.self) { factor in
                    Button("\(Int(factor * 100)) %") { model.setScaleSelected(factor) }
                }
            } label: {
                toolLabel("Skalieren", "arrow.up.left.and.arrow.down.right")
            }
            .disabled(!hasSelection)
            .accessibilityIdentifier("tool-scale")
            tool("Flachlegen", "square.bottomhalf.filled") { model.layFlatSelected() }
                .disabled(!hasSelection)
                .accessibilityIdentifier("tool-layflat")
            tool("Anordnen", "square.grid.2x2") { model.arrange() }
                .accessibilityIdentifier("tool-arrange")
            Menu {
                Button("Duplizieren", systemImage: "plus.square.on.square") { model.duplicateSelected() }
                Button("Entfernen", systemImage: "trash", role: .destructive) { model.removeSelected() }
            } label: {
                toolLabel("Objekt", "ellipsis")
            }
            .disabled(!hasSelection)
            .accessibilityIdentifier("tool-object")
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

/// Objects on the plate; tapping one selects it.
private struct ObjectStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.plate.objects) { object in
                    chip(object)
                }
                ImportButton {
                    Label("Hinzufügen", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .frame(minHeight: 44)
                        .background(.background, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color(.separator), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 2)
        }
    }

    private func chip(_ object: PlateObject) -> some View {
        let head = model.heads.first { $0.tool == object.tool } ?? HeadFilament(tool: object.tool)
        let selected = object.id == model.selectedID
        return Button {
            // always select; deselecting happens by tapping empty space in the 3D view
            model.selectedID = object.id
        } label: {
            HStack(spacing: 8) {
                FilamentDot(color: head.color, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(object.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(head.label).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .frame(minHeight: 44)
            .background(.background, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Color.accentColor : Color(.separator), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Details of the selected object: size and which head prints it.
private struct SelectionPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let index = model.selectedIndex {
            let object = model.plate.objects[index]
            let size = object.size
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(object.name).font(.headline).lineLimit(1)
                    Spacer()
                    Text(verbatim: "\(Self.mm(size.x)) × \(Self.mm(size.y)) × \(Self.mm(size.z)) mm")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("selectionSize")
                }
                Text("Druckkopf").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    ForEach(model.heads) { head in
                        headButton(head, selected: head.tool == object.tool, objectID: object.id)
                    }
                }
            }
            .padding(14)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
        } else if !model.plate.objects.isEmpty {
            Label("Tippe ein Objekt an, um es zu bearbeiten und einem Druckkopf zuzuordnen. Ziehen verschiebt es auf der Platte.",
                  systemImage: "hand.tap")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func headButton(_ head: HeadFilament, selected: Bool, objectID: UUID) -> some View {
        Button {
            model.setTool(head.tool, for: objectID)
        } label: {
            VStack(spacing: 4) {
                FilamentDot(color: head.color, size: 26)
                Text(head.label).font(.caption.weight(.bold))
                Text(head.loaded || !head.fromPrinter ? head.material.rawValue : String(localized: "leer"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(selected ? Color.accentColor.opacity(0.14) : Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(head.label), \(head.material.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("head-\(head.label)")
    }

    static func mm(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)))
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
                            Text("Wird geslict …") + Text(verbatim: " \(Int(model.engine.progress * 100)) %")
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
            .accessibilityIdentifier("sliceButton")
            .sensoryFeedback(.success, trigger: model.sliceCount)
            if let reason = disabledReason {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
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

    /// Why "Slicen" is greyed out, so nobody is left guessing.
    private var disabledReason: LocalizedStringKey? {
        guard !isSlicing, !model.canSlice else { return nil }
        switch model.engine.state {
        case .loading: return "Die Slicing-Engine startet noch …"
        case .failed: return "Die Slicing-Engine ist nicht verfügbar. Starte die App neu."
        case .ready: return model.issues.isEmpty ? nil : "Bitte zuerst die Hinweise oben beheben."
        }
    }
}
