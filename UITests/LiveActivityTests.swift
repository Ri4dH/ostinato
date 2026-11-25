import XCTest

/// End to end: starting a session shows the Live Activity, and its Pause
/// button (an App Intent running in the app) pauses the session.
@MainActor
final class LiveActivityTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testLiveActivityAppearsAndPauses() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-skipOnboarding"]
        app.launch()
        app.buttons["startPractice"].tap()
        XCTAssertTrue(app.staticTexts["sessionTimer"].waitForExistence(timeout: 10))
        app.buttons["Scales"].firstMatch.tap()

        // Go home and pull down Notification Center, which lists Live Activities.
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let top = springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.005))
        top.press(forDuration: 0.1, thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.7)))

        let item = springboard.staticTexts["Scales"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 15), "Live Activity with the current item isn't visible")
        save(springboard, "live-activity")

        let pause = springboard.buttons["Pause"].firstMatch
        XCTAssertTrue(pause.waitForExistence(timeout: 5))
        pause.tap()
        XCTAssertTrue(springboard.buttons["Resume"].firstMatch.waitForExistence(timeout: 15),
                      "Pause intent didn't update the Live Activity")
        save(springboard, "live-activity-paused")

        // The app agrees: the session is paused. (Next UI-test launch starts clean.)
        app.activate()
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 10))
    }

    private func save(_ springboard: XCUIApplication, _ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] {
            try? shot.pngRepresentation.write(to: URL(filePath: dir).appending(path: "\(name).png"))
        }
    }
}
