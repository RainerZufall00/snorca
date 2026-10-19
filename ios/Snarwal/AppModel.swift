import Foundation
import Observation
import SnarwalCore
import UniformTypeIdentifiers

/// App-wide state: the build plate, slicing and the current result.
@MainActor
@Observable
final class AppModel {
    enum Tab: Hashable {
        case slice, printer
    }

    enum SliceState {
        case idle
        case slicing
        case done(SliceResult)
        case failed(String)
    }

    struct SliceResult {
        var gcode: String
        var summary: GCodeSummary?
        var preview: GCodePreview
        var filename: String
        /// Temporary copy for the share sheet.
        var fileURL: URL?
    }

    var tab: Tab = .slice
    var plate = Plate()
    var projectName = ""
    var selectedID: UUID?
    var settings = SliceSettings() {
        didSet { saveSettings() }
    }
    /// Filament per head chosen in the app; replaced by the printer's RFID data when connected.
    var manualHeads = HeadFilament.defaults()
    var sliceState: SliceState = .idle
    var showPreview = false
    var importError: String?
    var isImporting = false
    /// Notes from the last import (painted models, positions reset, ...).
    var importNotes: [String] = []

    let engine = SlicerEngine()
    let printer = PrinterConnection()

    static let modelTypes: [UTType] = [
        UTType("public.standard-tesselated-geometry-format") ?? UTType(filenameExtension: "stl", conformingTo: .data) ?? .data,
        UTType(filenameExtension: "3mf", conformingTo: .data) ?? .data,
    ]

    init() {
        if let data = UserDefaults.standard.data(forKey: "sliceSettings"),
           let saved = try? JSONDecoder().decode(SliceSettings.self, from: data) {
            settings = saved
        }
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "sliceSettings")
        }
    }

    /// Heads used for slicing: live printer data when available.
    var heads: [HeadFilament] {
        if let status = printer.status, status.filaments.contains(where: \.loaded) {
            return status.filaments
        }
        return manualHeads
    }

    var selectedIndex: Int? {
        plate.objects.firstIndex { $0.id == selectedID }
    }

    var issues: [PlateIssue] {
        plate.boundsIssues() + MaterialCheck.issues(plate: plate, heads: heads)
    }

    var canSlice: Bool {
        !plate.objects.isEmpty && issues.isEmpty && engine.state == .ready
    }

    // MARK: import

    func importFile(at url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        isImporting = true
        defer { isImporting = false }
        do {
            let data = try Data(contentsOf: url)
            let loaded = try await engine.loadModel(name: url.lastPathComponent, data: data)
            var notes: [String] = []
            if loaded.contains(where: \.painted) {
                notes.append(String(localized: "Das Modell ist mehrfarbig bemalt. Bemalung wird noch nicht unterstützt – es wird einfarbig gedruckt."))
            }
            let added = loaded.map { item in
                PlateObject(name: item.name, mesh: item.mesh, tool: min(item.tool ?? 0, PrinterSpec.toolCount - 1))
            }
            // STL files carry no plate position; 3MF positions are kept if they fit
            let isSTL = url.pathExtension.lowercased() == "stl"
            if plate.objects.isEmpty {
                projectName = url.deletingPathExtension().lastPathComponent
            }
            plate.objects.append(contentsOf: added)
            if isSTL || !plate.boundsIssues().isEmpty {
                if !plate.arrange() {
                    notes.append(String(localized: "Nicht alle Objekte passen auf das Druckbett. Skaliere sie oder entferne welche."))
                } else if !isSTL {
                    notes.append(String(localized: "Die Objekte lagen außerhalb des U1-Betts und wurden neu angeordnet."))
                }
            }
            selectedID = plate.objects.last?.id
            importNotes = notes
            invalidateSlice()
        } catch {
            importError = error.localizedDescription
        }
    }

    // MARK: editing

    func updateSelected(_ change: (inout PlateObject) -> Void) {
        guard let index = selectedIndex else { return }
        change(&plate.objects[index])
        invalidateSlice()
    }

    func rotateSelected() {
        updateSelected { $0.rotateZ(degrees: 90) }
    }

    func layFlatSelected() {
        updateSelected { $0.layFlat() }
    }

    func setScaleSelected(_ scale: Double) {
        updateSelected { $0.scale = scale }
    }

    func setTool(_ tool: Int, for id: UUID) {
        guard let index = plate.objects.firstIndex(where: { $0.id == id }) else { return }
        plate.objects[index].tool = tool
        invalidateSlice()
    }

    func duplicateSelected() {
        guard let index = selectedIndex else { return }
        var copy = plate.objects[index]
        copy = PlateObject(name: copy.name, mesh: copy.mesh, tool: copy.tool, rotation: copy.rotation,
                           scale: copy.scale, position: (copy.position.x + 10, copy.position.y + 10))
        plate.objects.append(copy)
        selectedID = copy.id
        _ = plate.arrange()
        invalidateSlice()
    }

    func removeSelected() {
        guard let index = selectedIndex else { return }
        plate.objects.remove(at: index)
        selectedID = plate.objects.last?.id
        invalidateSlice()
    }

    @discardableResult
    func arrange() -> Bool {
        let ok = plate.arrange()
        invalidateSlice()
        return ok
    }

    func clearPlate() {
        plate = Plate()
        selectedID = nil
        projectName = ""
        importNotes = []
        invalidateSlice()
    }

    private func invalidateSlice() {
        if case .slicing = sliceState { return }
        sliceState = .idle
    }

    // MARK: slicing

    func slice() async {
        guard canSlice else { return }
        let firstTool = plate.usedTools.first ?? 0
        let head = heads.first { $0.tool == firstTool } ?? HeadFilament(tool: firstTool)
        let process = settings.kiriProcess(firstHead: head)
        let plate = self.plate
        let heads = self.heads
        sliceState = .slicing
        do {
            let output = try await engine.slice(plate: plate, process: process, heads: heads)
            let gcode = output.gcode
            let (summary, preview) = await Task.detached(priority: .userInitiated) {
                (GCodeSummary(gcode: gcode), GCodePreview(gcode: gcode))
            }.value
            let filename = gcodeFilename
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            let saved = (try? gcode.write(to: fileURL, atomically: true, encoding: .utf8)) != nil
            sliceState = .done(SliceResult(gcode: gcode, summary: summary, preview: preview, filename: filename,
                                           fileURL: saved ? fileURL : nil))
            showPreview = true
        } catch {
            sliceState = .failed(error.localizedDescription)
        }
    }

    var gcodeFilename: String {
        let base = projectName.isEmpty ? "Snarwal" : projectName
        let safe = base.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
        return String(safe) + ".gcode"
    }

    var result: SliceResult? {
        if case .done(let result) = sliceState { return result }
        return nil
    }
}
