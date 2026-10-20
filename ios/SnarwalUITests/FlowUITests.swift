import XCTest

/// Uses the app like a person would. CI runs a mock Moonraker
/// (ci/mock_moonraker.py) on 127.0.0.1:7125 and puts test models into
/// /tmp/snarwal-uitest (an Orca 3MF with head assignments and 3DBenchy).
final class FlowUITests: XCTestCase {
    static let models = "/tmp/snarwal-uitest"

    override func setUp() {
        continueAfterFailure = false
    }

    // MARK: helpers

    private func launch(_ arguments: [String], language: String = "de") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + ["-AppleLanguages", "(\(language))",
                                           "-AppleLocale", language == "de" ? "de_DE" : "en_US"]
        app.launch()
        return app
    }

    private func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval) {
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: element)
        wait(for: [enabled], timeout: timeout)
    }

    /// Scrolls the controls under the 3D view until `element` can be tapped.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let controls = app.scrollViews["controls"]
        var tries = 0
        while !element.isHittable && controls.exists && tries < 5 {
            controls.swipeUp()
            tries += 1
        }
    }

    /// Waits until some element with `identifier` shows one of `labels`;
    /// reports what it saw instead otherwise.
    private func waitForLabel(_ identifier: String, in app: XCUIApplication, oneOf labels: [String], timeout: TimeInterval) {
        let query = app.descendants(matching: .any).matching(identifier: identifier)
        let deadline = Date().addingTimeInterval(timeout)
        var seen: [String] = []
        while Date() < deadline {
            seen = query.allElementsBoundByIndex.map { $0.label }
            if seen.contains(where: { label in labels.contains { label.contains($0) } }) { return }
            Thread.sleep(forTimeInterval: 1)
        }
        XCTFail("\(identifier) shows \(seen), expected one of \(labels)")
    }

    private func chip(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    private func snapshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: tests (run in alphabetical order)

    /// English UI: the main labels are translated.
    func testA_EnglishInterface() throws {
        let app = launch(["-SnarwalDemo", "-SnarwalResetPrinter"], language: "en")
        let slice = app.buttons["sliceButton"]
        XCTAssertTrue(slice.waitForExistence(timeout: 60))
        waitForLabel("sliceButton", in: app, oneOf: ["Slice"], timeout: 120)
        XCTAssertTrue(app.staticTexts["Print head"].exists)
        XCTAssertTrue(app.buttons["Printer"].firstMatch.exists)
        snapshot("English", app)
    }

    /// Orca 3MF: object names and head assignments survive the import.
    func testB_ImportOrca3MFKeepsHeads() throws {
        let app = launch(["-SnarwalResetPrinter", "-SnarwalResetPlate", "-SnarwalImport", "\(Self.models)/Kopftest.3mf"])
        let sockel = chip("Sockel", in: app)
        XCTAssertTrue(sockel.waitForExistence(timeout: 120), "imported object 'Sockel'")
        XCTAssertTrue(sockel.label.contains("T1"), sockel.label)
        let turm = chip("Turm", in: app)
        XCTAssertTrue(turm.exists)
        XCTAssertTrue(turm.label.contains("T3"), turm.label)
        turm.tap()
        let t3 = app.buttons["head-T3"]
        reveal(t3, in: app)
        XCTAssertTrue(t3.isSelected, "Turm is printed by T3")
        snapshot("3MF-Import", app)
    }

    /// A real model (3DBenchy, 225k triangles) imports and slices in the app.
    func testC_ImportAndSliceBenchy() throws {
        let app = launch(["-SnarwalResetPrinter", "-SnarwalResetPlate", "-SnarwalImport", "\(Self.models)/3DBenchy.3mf"])
        XCTAssertTrue(chip("3DBenchy", in: app).waitForExistence(timeout: 180), "3DBenchy on the plate")
        let slice = app.buttons["sliceButton"]
        waitUntilEnabled(slice, timeout: 120)
        slice.tap()
        XCTAssertTrue(app.buttons["sendButton"].waitForExistence(timeout: 600), "preview of the Benchy")
        XCTAssertTrue(app.staticTexts["Druckzeit"].exists)
        snapshot("Benchy-Vorschau", app)
    }

    /// Mixed materials block slicing with an explanation; same material unblocks.
    func testD_MixedMaterialsAreBlocked() throws {
        let app = launch(["-SnarwalDemo", "-SnarwalResetPrinter"])
        let slice = app.buttons["sliceButton"]
        XCTAssertTrue(slice.waitForExistence(timeout: 60))
        waitUntilEnabled(slice, timeout: 180)
        // the demo heads hold PLA on T1–T3 and PETG on T4
        let t4 = app.buttons["head-T4"]
        reveal(t4, in: app)
        t4.tap()
        let warning = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Gemischte Materialien'")).firstMatch
        reveal(warning, in: app)
        XCTAssertTrue(warning.waitForExistence(timeout: 10), "mixed material warning")
        XCTAssertFalse(slice.isEnabled, "slicing is blocked")
        XCTAssertTrue(app.staticTexts["Bitte zuerst die Hinweise oben beheben."].exists)
        snapshot("Gemischte Materialien", app)
        let t1 = app.buttons["head-T1"]
        reveal(t1, in: app)
        t1.tap()
        waitUntilEnabled(slice, timeout: 10)
    }

    /// Printer tab shows the live status of a connected (mock) U1.
    func testE_PrinterTabShowsLiveStatus() throws {
        let app = launch(["-SnarwalPrinterHost", "127.0.0.1:7125"])
        let tab = app.buttons["Drucker"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 60))
        tab.tap()
        snapshot("Drucker-Tab", app)
        waitForLabel("statusChip", in: app, oneOf: ["Bereit"], timeout: 60)
        let temps = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'temperaturen'")).firstMatch
        XCTAssertTrue(temps.waitForExistence(timeout: 30))
    }

    /// Settings sheet: toggling supports shows up in the summary.
    func testF_SettingsChangeSummary() throws {
        let app = launch(["-SnarwalDemo", "-SnarwalResetPrinter"])
        let settings = app.buttons["settingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 60))
        reveal(settings, in: app)
        settings.tap()
        let supports = app.switches["supportsToggle"]
        XCTAssertTrue(supports.waitForExistence(timeout: 10))
        let before = supports.value as? String
        supports.tap()
        if supports.value as? String == before {
            // some iOS versions only react to taps on the switch itself
            supports.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        }
        XCTAssertNotEqual(supports.value as? String, before, "toggle changed")
        snapshot("Einstellungen", app)
        app.buttons["Fertig"].tap()
        let expected = before == "1" ? "Stützen aus" : "Stützen an"
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", expected)).firstMatch.waitForExistence(timeout: 10),
                      "summary shows \(expected)")
    }

    /// The whole job: assign a head, slice, send, print, pause, resume, light, cancel.
    func testG_SliceSendPrintAndControl() throws {
        let app = launch(["-SnarwalDemo", "-SnarwalPrinterHost", "127.0.0.1:7125"])

        let t2 = app.buttons["head-T2"]
        XCTAssertTrue(t2.waitForExistence(timeout: 60), "head picker for the selected object")
        reveal(t2, in: app)
        t2.tap()
        XCTAssertTrue(t2.isSelected, "T2 marked as chosen")
        snapshot("Platte", app)

        let slice = app.buttons["sliceButton"]
        reveal(slice, in: app)
        waitUntilEnabled(slice, timeout: 180)
        slice.tap()

        let send = app.buttons["sendButton"]
        XCTAssertTrue(send.waitForExistence(timeout: 300), "preview after slicing")
        XCTAssertTrue(app.staticTexts["Druckzeit"].exists)
        snapshot("Vorschau", app)
        send.tap()

        let print = app.buttons["printButton"]
        XCTAssertTrue(print.waitForExistence(timeout: 30))
        waitUntilEnabled(print, timeout: 60)
        snapshot("Jetzt drucken", app)
        print.tap()

        waitForLabel("statusChip", in: app, oneOf: ["Druckt"], timeout: 60)
        snapshot("Drucker", app)

        // pause and resume
        let pause = app.buttons["pauseButton"]
        XCTAssertTrue(pause.waitForExistence(timeout: 20))
        pause.tap()
        waitForLabel("statusChip", in: app, oneOf: ["Pausiert"], timeout: 30)
        app.buttons["resumeButton"].tap()
        waitForLabel("statusChip", in: app, oneOf: ["Druckt"], timeout: 30)

        // light: the mock starts with the light on
        app.buttons["lightButton"].tap()
        waitForLabel("lightButton", in: app, oneOf: ["Licht aus"], timeout: 30)

        // cancel asks first, then stops the print
        app.buttons["cancelPrintButton"].tap()
        let confirm = app.buttons["Druck abbrechen"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "cancel asks for confirmation")
        confirm.tap()
        waitForLabel("statusChip", in: app, oneOf: ["Bereit"], timeout: 30)
        XCTAssertTrue(app.staticTexts["Kein aktiver Druck"].waitForExistence(timeout: 10))
        snapshot("Abgebrochen", app)
    }

    /// Tools change the selected object; the plate survives an app restart.
    func testH_ToolsAndPlateSurvivesRestart() throws {
        var app = launch(["-SnarwalDemo", "-SnarwalResetPrinter"])
        let size = app.staticTexts["selectionSize"]
        XCTAssertTrue(size.waitForExistence(timeout: 60))
        XCTAssertEqual(size.label, "60 × 40 × 48 mm")

        app.buttons["tool-rotate"].tap()
        XCTAssertEqual(size.label, "40 × 60 × 48 mm", "rotated by 90°")

        app.buttons["tool-scale"].tap()
        app.buttons["150 %"].tap()
        XCTAssertEqual(size.label, "60 × 90 × 72 mm", "scaled to 150 %")

        app.buttons["tool-object"].tap()
        app.buttons["Duplizieren"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Halterung'")).count, 2, "duplicated")
        snapshot("Werkzeuge", app)

        // give the debounced save time, then relaunch without demo data
        Thread.sleep(forTimeInterval: 2)
        app.terminate()
        app = launch(["-SnarwalResetPrinter"])
        XCTAssertTrue(chip("Halterung", in: app).waitForExistence(timeout: 60), "plate restored")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Halterung'")).count, 2)
        XCTAssertTrue(chip("Deckel", in: app).exists)
        // filament chosen per head (demo: PETG on T4) is kept as well
        chip("Halterung", in: app).tap()
        let t4 = app.buttons["head-T4"]
        reveal(t4, in: app)
        XCTAssertTrue(t4.label.contains("PETG"), t4.label)
        snapshot("Nach Neustart", app)
    }
}
