import Foundation
import XCTest
@testable import TalkBridgeCore

/// Kevin 2026-11-08：在設定裡自己挑每個語言的聲音；沒挑＝自動（品質最好）。
final class VoiceChoiceTests: XCTestCase {
    private let voices = [
        VoiceCandidate(identifier: "en.std", name: "Fred", language: "en-US", quality: .standard),
        VoiceCandidate(identifier: "en.prem", name: "Ava", language: "en-US", quality: .premium),
        VoiceCandidate(identifier: "gb.enh", name: "Daniel", language: "en-GB", quality: .enhanced),
        VoiceCandidate(identifier: "en.fun", name: "Bubbles", language: "en-US", quality: .standard, isNovelty: true),
        VoiceCandidate(identifier: "ja.std", name: "Kyoko", language: "ja-JP", quality: .standard),
    ]

    // MARK: 設定

    func testDefaultHasNoChosenVoices() {
        XCTAssertEqual(AppSettings().voiceIdentifiers, [:])
    }

    func testChosenVoicesSurviveSaveAndLoad() throws {
        var settings = AppSettings()
        settings.voiceIdentifiers["en-US"] = "en.std"
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data).voiceIdentifiers, ["en-US": "en.std"])
    }

    func testOldSavedSettingsWithoutVoicesStillLoad() throws {
        let old = #"{"pauseSeconds":3,"fontScale":1.2}"#.data(using: .utf8)!
        let settings = try JSONDecoder().decode(AppSettings.self, from: old)
        XCTAssertEqual(settings.pauseSeconds, 3)
        XCTAssertEqual(settings.voiceIdentifiers, [:])
    }

    // MARK: 挑選

    func testChosenVoiceWinsOverBetterQuality() {
        XCTAssertEqual(VoiceSelector.bestIndex(for: "en-US", in: voices, preferredIdentifier: "en.std"), 0)
    }

    func testChosenVoiceFromOtherRegionOfSameLanguageIsUsed() {
        XCTAssertEqual(VoiceSelector.bestIndex(for: "en-US", in: voices, preferredIdentifier: "gb.enh"), 2)
    }

    func testDeletedChosenVoiceFallsBackToAutomatic() {
        XCTAssertEqual(VoiceSelector.bestIndex(for: "en-US", in: voices, preferredIdentifier: "gone"), 1)
    }

    func testChosenVoiceOfAnotherLanguageIsIgnored() {
        // 不能讓日文聲音去唸英文。
        XCTAssertEqual(VoiceSelector.bestIndex(for: "en-US", in: voices, preferredIdentifier: "ja.std"), 1)
    }

    // MARK: 選單

    func testOptionsListSameLanguageOnlyBestFirstWithoutNovelty() {
        // 本地區優先，再依品質高到低；不列趣味語音、不列其他語言。
        XCTAssertEqual(VoiceSelector.optionIndices(for: "en-US", in: voices), [1, 0, 2])
    }

    func testOptionsEmptyWhenNoVoiceForLanguage() {
        XCTAssertEqual(VoiceSelector.optionIndices(for: "th-TH", in: voices), [])
    }

    func testQualityLabels() {
        XCTAssertEqual(VoiceQuality.premium.label, "高品質")
        XCTAssertEqual(VoiceQuality.enhanced.label, "加強版")
        XCTAssertEqual(VoiceQuality.standard.label, "一般")
    }

    func testVoiceLanguagesCoverChineseAndEveryPartnerLanguage() {
        let ids = VoiceLanguage.all.map(\.languageID)
        XCTAssertEqual(ids, ["zh-TW", "en-US", "id-ID", "th-TH", "ja-JP", "ko-KR"])
        XCTAssertEqual(VoiceLanguage.all.map(\.title), ["中文", "英文", "印尼文", "泰文", "日文", "韓文"])
        XCTAssertEqual(VoiceLanguage.all.first?.languageID, ChineseLocale.voiceLanguageID)
        for (language, voiceLanguage) in zip(PartnerLanguage.allCases, VoiceLanguage.all.dropFirst()) {
            XCTAssertEqual(voiceLanguage.languageID, language.voiceLanguageID)
        }
        XCTAssertTrue(VoiceLanguage.all.allSatisfy { !$0.sampleText.isEmpty }, "每個語言都要有試聽句")
    }
}
