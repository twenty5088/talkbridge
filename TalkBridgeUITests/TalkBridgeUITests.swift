import XCTest

final class TalkBridgeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testAppLaunches() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["TalkBridge"].waitForExistence(timeout: 10))
    }
}
