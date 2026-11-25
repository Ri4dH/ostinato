import XCTest

@MainActor
final class OstinatoUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func launch(skipOnboarding: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting"] + (skipOnboarding ? ["-skipOnboarding"] : [])
        app.launch()
        return app
    }

    func testOnboardingCanBeSkipped() {
        let app = launch(skipOnboarding: false)
        let skip = app.buttons["skipOnboarding"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        skip.tap()
        XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 5))
    }

    func testFullSessionFlow() {
        let app = launch()
        app.buttons["startPractice"].tap()

        XCTAssertTrue(app.staticTexts["sessionTimer"].waitForExistence(timeout: 5))
        // Switch to an item with one tap.
        app.buttons["Scales"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Scales"].waitForExistence(timeout: 2))

        app.buttons["pauseResume"].tap()
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 2))
        app.buttons["pauseResume"].tap()

        app.buttons["finishSession"].tap()
        let save = app.buttons["saveSession"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Scales"].exists, "Finish sheet lists the segment")
        save.tap()

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Scales'")).firstMatch
            .waitForExistence(timeout: 5))
    }

    func testManualLog() {
        let app = launch()
        app.buttons["Log Past Session"].firstMatch.tap()
        let save = app.navigationBars.buttons["Save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(app.staticTexts["General practice"].waitForExistence(timeout: 5))
    }

    func testEditSession() {
        let app = launch()
        app.buttons["Log Past Session"].firstMatch.tap()
        app.navigationBars.buttons["Save"].tap()
        app.tabBars.buttons["History"].tap()
        app.staticTexts["General practice"].firstMatch.tap()

        let notes = app.descendants(matching: .any).matching(identifier: "sessionNotes").firstMatch
        for _ in 0..<4 where !notes.isHittable { app.swipeUp() }
        XCTAssertTrue(notes.waitForExistence(timeout: 5))
        notes.tap()
        notes.typeText("Slow practice on bar 12")
        XCTAssertEqual(notes.value as? String, "Slow practice on bar 12")
    }

    func testExportCSV() {
        let app = launch()
        app.buttons["Log Past Session"].firstMatch.tap()
        app.navigationBars.buttons["Save"].tap()
        app.tabBars.buttons["Settings"].tap()
        let data = app.buttons["dataManagement"]
        for _ in 0..<6 where !data.isHittable { app.swipeUp() }
        data.tap()
        let create = app.buttons["Practice log (CSV)"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
        // After the file is created the row becomes a share link.
        XCTAssertTrue(app.buttons["Practice log (CSV)"].waitForExistence(timeout: 5))
    }
}

@MainActor
final class ToolsUITests: XCTestCase {
    /// Regressions: opening the Tuner crashed (recursive didSet), and running
    /// audio crashed (callbacks isolated to the main actor). Runs each tool.
    func testToolsRunWithoutCrashing() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding"]
        app.launch()
        addUIInterruptionMonitor(withDescription: "Microphone") { alert in
            let allow = alert.buttons["Allow"]
            if allow.exists { allow.tap() } else { alert.buttons.firstMatch.tap() }
            return true
        }
        XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 30))

        open("Metronome", in: app)
        app.buttons["Start"].firstMatch.tap()
        sleep(3)
        assertRunning(app, "metronome playing")
        app.buttons["Stop"].firstMatch.tap()
        close("Metronome", in: app)

        open("Drone", in: app)
        app.buttons["D"].firstMatch.tap()   // starts the drone on D
        sleep(3)
        assertRunning(app, "drone playing")
        app.buttons["Stop"].firstMatch.tap()
        close("Drone", in: app)

        open("Tuner", in: app)
        sleep(2)
        app.swipeUp()                        // lets the interruption monitor answer the mic prompt
        sleep(3)
        assertRunning(app, "tuner listening")
        close("Tuner", in: app)
    }

    private func open(_ tool: String, in app: XCUIApplication) {
        // A freshly booted simulator can drop taps while it draws its first
        // frames (shader compilation), so retry a few times.
        let button = app.buttons[tool].firstMatch
        let bar = app.navigationBars[tool]
        for _ in 0..<3 where !bar.exists {
            if button.isHittable { button.tap() }
            _ = bar.waitForExistence(timeout: 15)
        }
        XCTAssertTrue(bar.exists, "\(tool) didn't open")
    }

    private func close(_ tool: String, in app: XCUIApplication) {
        let bar = app.navigationBars[tool]
        bar.buttons["Done"].tap()
        // Wait for the sheet to finish dismissing before tapping the next tool.
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: bar)
        wait(for: [gone], timeout: 10)
        XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
    }

    private func assertRunning(_ app: XCUIApplication, _ what: String) {
        XCTAssertEqual(app.state, .runningForeground, "App stopped with \(what)")
    }
}
