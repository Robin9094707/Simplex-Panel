import XCTest

final class CommunityUITests: XCTestCase {
    func testWelcomeLanguagesAndDemo() {
        let app = XCUIApplication()
        app.launchArguments = ["--reset-setup"]
        app.launch()
        XCTAssertTrue(app.buttons["language-en"].waitForExistence(timeout: 15))
        app.buttons["language-en"].tap()
        screenshot("Welcome-English")
        app.buttons["language-de"].tap()
        screenshot("Welcome-Deutsch")
        app.buttons["setupNext"].tap()
        XCTAssertTrue(app.buttons["setupDemo"].waitForExistence(timeout: 5))
        app.buttons["setupDemo"].tap()
        XCTAssertTrue(app.navigationBars["Simplex Wing"].waitForExistence(timeout: 10))
        screenshot("Workspace-Deutsch")
    }
    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
