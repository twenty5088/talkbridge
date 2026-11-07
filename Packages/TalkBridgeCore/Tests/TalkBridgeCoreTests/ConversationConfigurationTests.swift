import XCTest
@testable import TalkBridgeCore

final class ConversationConfigurationTests: XCTestCase {
    func testDefaultConfiguration() {
        let c = ConversationConfiguration.standard
        XCTAssertEqual(c.silenceTimeout, .milliseconds(1200))
        XCTAssertEqual(c.maxUtteranceDuration, .seconds(30))
        XCTAssertEqual(c.playbackCountdown, 2)
        XCTAssertEqual(c.postPlaybackMicGuard, .milliseconds(300))
        XCTAssertEqual(c.autoTurnIdleTimeout, .seconds(15))
        XCTAssertEqual(c.finalResultTimeout, .seconds(2))
        XCTAssertEqual(c.minimumMeaningfulCharacters, 1)
    }

    func testConfigurationIsAdjustable() {
        var c = ConversationConfiguration.standard
        c.silenceTimeout = .milliseconds(500)
        XCTAssertNotEqual(c, .standard)
    }
}
