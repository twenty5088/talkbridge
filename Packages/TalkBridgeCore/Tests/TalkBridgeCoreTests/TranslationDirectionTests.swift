import XCTest
@testable import TalkBridgeCore

final class TranslationDirectionTests: XCTestCase {
    func testDirectionReversedTwiceIsIdentity() {
        for lang in PartnerLanguage.allCases {
            let d = TranslationDirection.partnerToChinese(lang)
            XCTAssertEqual(d.reversed, .chineseToPartner(lang))
            XCTAssertEqual(d.reversed.reversed, d)
        }
    }

    func testDirectionFromSpeaker() {
        XCTAssertEqual(TranslationDirection.from(speaker: .partner, partner: .thai), .partnerToChinese(.thai))
        XCTAssertEqual(TranslationDirection.from(speaker: .user, partner: .thai), .chineseToPartner(.thai))
    }

    func testSpeakerAndPartnerLanguage() {
        XCTAssertEqual(TranslationDirection.partnerToChinese(.korean).speaker, .partner)
        XCTAssertEqual(TranslationDirection.chineseToPartner(.korean).speaker, .user)
        XCTAssertEqual(TranslationDirection.chineseToPartner(.korean).partnerLanguage, .korean)
    }
}
