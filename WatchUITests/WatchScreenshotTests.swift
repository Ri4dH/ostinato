import XCTest

/// Apple Watch App Store screenshots. Skipped unless SCREENSHOT_DIR is set.
@MainActor
final class WatchScreenshotTests: XCTestCase {
    private var outputDirectory: URL!

    override func setUp() async throws {
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("Set SCREENSHOT_DIR to capture screenshots")
        }
        outputDirectory = URL(filePath: dir, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    private func capture(_ name: String, args: [String], waitFor label: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-demoData"] + args
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)[label].firstMatch.waitForExistence(timeout: 60), "\(label) never appeared")
        sleep(2)
        try XCUIScreen.main.screenshot().pngRepresentation.write(to: outputDirectory.appending(path: "\(name).png"))
    }

    func test1Active() throws { try capture("1-active", args: ["-demoSession"], waitFor: "Next Item") }
    func test2Home() throws { try capture("2-home", args: [], waitFor: "Start") }
}
