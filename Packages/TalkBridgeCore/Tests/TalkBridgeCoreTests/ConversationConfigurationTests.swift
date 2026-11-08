import XCTest
@testable import TalkBridgeCore

final class ConversationConfigurationTests: XCTestCase {
    func testDefaultConfiguration() {
        let c = ConversationConfiguration.standard
        XCTAssertNil(c.silenceTimeout, "nil＝依使用者設定的停頓秒數")
        XCTAssertEqual(c.maxUtteranceDuration, .seconds(30))
        XCTAssertNil(c.playbackCountdown, "nil＝依使用者設定的倒數秒數")
        XCTAssertEqual(c.postPlaybackMicGuard, .milliseconds(300))
        XCTAssertEqual(c.autoTurnIdleTimeout, .seconds(15))
        XCTAssertEqual(c.finalResultTimeout, .seconds(1), "說完後等最終辨識最多 1 秒（加快出聲）")
        XCTAssertEqual(c.minimumMeaningfulCharacters, 1)
    }

    func testConfigurationIsAdjustable() {
        var c = ConversationConfiguration.standard
        c.silenceTimeout = .milliseconds(500)
        XCTAssertNotEqual(c, .standard)
    }
}
