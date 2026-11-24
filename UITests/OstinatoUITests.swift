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
