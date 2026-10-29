import XCTest

@MainActor final class CockpitSmokeTests: XCTestCase {
    func testTrainingArmStopAndDiagnostics() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
        addUIInterruptionMonitor(withDescription: "Bluetooth permission") { alert in
            for title in ["Erlauben", "Allow", "OK"] where alert.buttons[title].exists { alert.buttons[title].tap(); return true }
            return false
        }
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Hangar"].waitForExistence(timeout: 20))
        screenshot("01-Hangar")
        let training = app.buttons["Cockpit im Trainingsmodus ansehen"]
        for _ in 0..<5 { if training.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(training.isHittable); training.tap()
        XCTAssertTrue(app.staticTexts["TRAINING"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["GESPERRT"].exists)
        app.buttons["Freigeben"].tap()
        let checkbox = app.switches["Trainingsmodus verstanden"]
        XCTAssertTrue(checkbox.waitForExistence(timeout: 5))
        let start = app.buttons["Training starten"]
        XCTAssertFalse(start.isEnabled)
        checkbox.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertTrue(start.waitForEnabled(timeout: 5)); start.tap()
        XCTAssertTrue(app.staticTexts["FREI"].waitForExistence(timeout: 5))
        screenshot("02-Cockpit-Portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        screenshot("03-Cockpit-Landscape")
        app.buttons["STOP"].tap()
        XCTAssertTrue(app.staticTexts["GESPERRT"].exists)
        app.buttons["Cockpit schließen"].tap()
        XCUIDevice.shared.orientation = .portrait
        app.tabBars.buttons["Bluetooth-Labor"].tap()
        XCTAssertTrue(app.staticTexts["RX 0  •  TX 0"].waitForExistence(timeout: 5))
        screenshot("04-Bluetooth-Labor")
    }
    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

private extension XCUIElement {
    func waitForEnabled(timeout: TimeInterval) -> Bool {
        XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: self)], timeout: timeout) == .completed
    }
}
