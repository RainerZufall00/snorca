import XCTest

/// Uses the app like a person would: assign a head, slice, check the
/// preview, send to the printer and watch it start. CI runs a mock
/// Moonraker (ci/mock_moonraker.py) on 127.0.0.1:7125 for this.
final class FlowUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
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
            if seen.contains(where: labels.contains) { return }
            Thread.sleep(forTimeInterval: 1)
        }
        XCTFail("\(identifier) shows \(seen), expected one of \(labels)")
    }

    private func snapshot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSliceSendAndMonitor() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SnarwalDemo", "-SnarwalPrinterHost", "127.0.0.1:7125",
                               "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()

        // 1. assign print head T2 to the selected object
        let t2 = app.buttons["head-T2"]
        XCTAssertTrue(t2.waitForExistence(timeout: 60), "head picker for the selected object")
        reveal(t2, in: app)
        t2.tap()
        XCTAssertTrue(t2.isSelected, "T2 marked as chosen")
        snapshot("Platte", app)

        // 2. slice once the engine is ready
        let slice = app.buttons["sliceButton"]
        reveal(slice, in: app)
        waitUntilEnabled(slice, timeout: 180)
        slice.tap()

        // 3. preview appears with print time and the send button
        let send = app.buttons["sendButton"]
        XCTAssertTrue(send.waitForExistence(timeout: 300), "preview after slicing")
        XCTAssertTrue(app.staticTexts["Druckzeit"].exists)
        snapshot("Vorschau", app)
        send.tap()

        // 4. "Jetzt drucken?" – the mock printer reports PLA in all heads
        let print = app.buttons["printButton"]
        XCTAssertTrue(print.waitForExistence(timeout: 30))
        waitUntilEnabled(print, timeout: 60)
        snapshot("Jetzt drucken", app)
        print.tap()

        // 5. the app switches to the printer tab and shows the running print
        snapshot("Nach Drucken", app)
        waitForLabel("statusChip", in: app, oneOf: ["Druckt"], timeout: 60)
        snapshot("Drucker", app)
    }

    func testPrinterTabShowsLiveStatus() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-SnarwalPrinterHost", "127.0.0.1:7125",
                               "-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        app.launch()
        // printer tab with live status from the mock
        let tab = app.buttons["Drucker"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 60))
        tab.tap()
        snapshot("Drucker-Tab", app)
        waitForLabel("statusChip", in: app, oneOf: ["Bereit"], timeout: 60)
        let temps = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'temperaturen'")).firstMatch
        XCTAssertTrue(temps.waitForExistence(timeout: 30))
        snapshot("Drucker bereit", app)
    }
}
