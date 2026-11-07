import XCTest
@testable import TalkBridgeCore

final class LocaleMappingTests: XCTestCase {
    func testPartnerLocaleMapping() {
        let expected: [PartnerLanguage: (speech: String, translation: String, voice: String)] = [
            .english: ("en-US", "en", "en-US"),
            .indonesian: ("id-ID", "id", "id-ID"),
            .thai: ("th-TH", "th", "th-TH"),
            .japanese: ("ja-JP", "ja", "ja-JP"),
            .korean: ("ko-KR", "ko", "ko-KR"),
        ]
        XCTAssertEqual(expected.count, PartnerLanguage.allCases.count)
        for (lang, e) in expected {
            let d = TranslationDirection.partnerToChinese(lang)
            XCTAssertEqual(LocaleMapping.speechLocaleID(for: d), e.speech, "\(lang)")
            XCTAssertEqual(LocaleMapping.translationPair(for: d).source, e.translation, "\(lang)")
            XCTAssertEqual(LocaleMapping.translationPair(for: d).target, "zh-Hant-TW", "\(lang)")
            XCTAssertEqual(LocaleMapping.voiceLanguageID(for: d), "zh-TW", "\(lang)")

            let r = d.reversed
            XCTAssertEqual(LocaleMapping.speechLocaleID(for: r), "zh-TW", "\(lang)")
            XCTAssertEqual(LocaleMapping.translationPair(for: r).source, "zh-Hant-TW", "\(lang)")
            XCTAssertEqual(LocaleMapping.translationPair(for: r).target, e.translation, "\(lang)")
            XCTAssertEqual(LocaleMapping.voiceLanguageID(for: r), e.voice, "\(lang)")
        }
    }

    func testChineseLocaleConstants() {
        XCTAssertEqual(ChineseLocale.speechLocaleID, "zh-TW")
        XCTAssertEqual(ChineseLocale.translationLanguageID, "zh-Hant-TW")
        XCTAssertEqual(ChineseLocale.voiceLanguageID, "zh-TW")
    }

    func testDisplayNames() {
        // Kevin 2026-11-08：選單改用中文顯示（太太操作）。
        XCTAssertEqual(PartnerLanguage.english.displayName, "英文")
        XCTAssertEqual(PartnerLanguage.indonesian.displayName, "印尼文")
        XCTAssertEqual(PartnerLanguage.thai.displayName, "泰文")
        XCTAssertEqual(PartnerLanguage.japanese.displayName, "日文")
        XCTAssertEqual(PartnerLanguage.korean.displayName, "韓文")
    }
}
