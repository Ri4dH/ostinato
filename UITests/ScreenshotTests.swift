import XCTest

/// App Store screenshots. Skipped unless SCREENSHOT_DIR is set; run through
/// `scripts/screenshots.sh`, which passes it as TEST_RUNNER_SCREENSHOT_DIR.
@MainActor
final class ScreenshotTests: XCTestCase {
    private var outputDirectory: URL!

    override func setUp() async throws {
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("Set SCREENSHOT_DIR to capture screenshots")
        }
        outputDirectory = URL(filePath: dir, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        continueAfterFailure = false
    }

    private func launch(_ args: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-demoData"] + args
        app.launch()
        return app
    }

    private func capture(_ name: String, after element: XCUIElement) throws {
        XCTAssertTrue(element.waitForExistence(timeout: 60), "\(name): \(element) never appeared")
        sleep(2)   // let animations and charts settle
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try png.write(to: outputDirectory.appending(path: "\(name).png"))
    }

    func test1Session() throws {
        let app = launch(["-demoSession"])
        try capture("1-session", after: app.staticTexts["sessionTimer"])
    }

    func test2Finish() throws {
        let app = launch(["-demoSession", "-demoFinish"])
        try capture("2-finish", after: app.buttons["saveSession"])
    }

    func test3Stats() throws {
        let app = launch(["-tab", "stats"])
        try capture("3-stats", after: app.staticTexts["Minutes per day"])
    }

    func test4Item() throws {
        let app = launch(["-tab", "repertoire", "-demoItem"])
        try capture("4-item", after: app.buttons["Practice This"])
    }

    func test5Home() throws {
        let app = launch([])
        XCTAssertTrue(app.staticTexts["Continue with"].waitForExistence(timeout: 60))
        try capture("5-home", after: app.buttons["startPractice"])
    }

    func test6Metronome() throws {
        let app = launch(["-demoTool", "metronome"])
        try capture("6-metronome", after: app.staticTexts["BPM"])
    }
}
