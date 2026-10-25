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
        XCTAssertTrue(app.staticTexts["Deine Server.\nDein Wing."].waitForExistence(timeout: 10))
        screenshot("Welcome-Deutsch")
        app.buttons["setupNext"].tap()
        XCTAssertTrue(app.buttons["setupDemo"].waitForExistence(timeout: 5))
        app.buttons["setupDemo"].tap()
        XCTAssertTrue(app.navigationBars["Simplex Wing"].waitForExistence(timeout: 10))
        screenshot("Workspace-Deutsch")
    }
    func testDemoServerConsoleAndFiles() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "-wing.language", "en", "-wing.onboarded", "YES"]
        app.launch()
        let server = app.buttons["server-simplex1"]
        XCTAssertTrue(server.waitForExistence(timeout: 15))
        for _ in 0..<4 { if server.isHittable { break }; app.swipeUp() }
        server.tap()
        XCTAssertTrue(app.tabBars.buttons["Console"].waitForExistence(timeout: 10))
        screenshot("Server-English")
        app.tabBars.buttons["Console"].tap()
        XCTAssertTrue(app.textViews["consoleOutput"].waitForExistence(timeout: 10))
        screenshot("Console-English")
        app.tabBars.buttons["Files"].tap()
        XCTAssertTrue(app.staticTexts["server.properties"].waitForExistence(timeout: 10))
        screenshot("Files-English")
    }
    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
