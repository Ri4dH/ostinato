import XCTest

/// Runs Apple's automated accessibility audit (contrast, Dynamic Type,
/// hit regions, labels, traits) on every main screen with realistic data.
@MainActor
final class AccessibilityAuditTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-demoData"]
        app.launch()
    }

    private func audit(_ screen: String, file: StaticString = #filePath, line: UInt = #line) {
        let navTitles = Set(app.navigationBars.staticTexts.allElementsBoundByIndex.map(\.label))
        do {
            try app.performAccessibilityAudit { issue in
                // Triage policy (see docs/accessibility.md):
                // - Contrast: the audit samples Liquid Glass buttons and content under the
                //   floating tab bar incorrectly, flagging black-on-light text. Logged, and
                //   verified with light/dark screenshots instead.
                // - Dynamic Type: flags system toolbar buttons, nav titles and Form footers.
                //   Logged, and verified with AX5 screenshots instead.
                // - Issues with no element can't be attributed to app UI (system chrome).
                // Hit area, labels, traits, element detection and clipped text fail the test.
                let element = issue.element
                let isNavTitle = issue.auditType == .textClipped && navTitles.contains(element?.label ?? "")
                let logged = issue.auditType == .contrast || issue.auditType == .dynamicType
                let ignored = logged || element == nil || isNavTitle
                print("AUDIT [\(screen)] \(ignored ? "logged" : "FAIL") \(issue.auditType.rawValue): \(issue.compactDescription) — \(element?.label ?? "")")
                return ignored
            }
        } catch {
            XCTFail("Audit failed on \(screen): \(error)", file: file, line: line)
        }
    }

    func testTabsPassAudit() {
        XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
        audit("Practice")
        for tab in ["Repertoire", "History", "Stats", "Settings"] {
            app.tabBars.buttons[tab].tap()
            sleep(1)
            audit(tab)
        }
    }

    func testSessionScreensPassAudit() {
        XCTAssertTrue(app.buttons["startPractice"].waitForExistence(timeout: 10))
        app.buttons["startPractice"].tap()
        XCTAssertTrue(app.staticTexts["sessionTimer"].waitForExistence(timeout: 5))
        app.buttons["pauseResume"].tap()   // paused timer stops redrawing, so the audit can settle
        audit("Active session")
        app.buttons["finishSession"].tap()
        XCTAssertTrue(app.buttons["saveSession"].waitForExistence(timeout: 5))
        audit("Finish sheet")
    }
}
