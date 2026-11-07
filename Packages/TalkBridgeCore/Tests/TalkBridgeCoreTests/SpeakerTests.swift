import XCTest
@testable import TalkBridgeCore

final class SpeakerTests: XCTestCase {
    func testSpeakerOtherSide() {
        XCTAssertEqual(Speaker.partner.other, .user)
        XCTAssertEqual(Speaker.user.other, .partner)
    }
}
