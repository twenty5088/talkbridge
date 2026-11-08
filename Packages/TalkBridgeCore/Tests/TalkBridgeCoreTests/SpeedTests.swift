import Foundation
import XCTest
@testable import TalkBridgeCore
import TalkBridgeFakes

/// Kevin 2026-11-08：太太覺得說完到播出來太久 → 倒數可調、各階段計時、先暖好翻譯與聲音。
@MainActor
final class SpeedTests: XCTestCase {
    private let chineseScript: [String: [RecognitionUpdate]] = [
        "zh-TW": [.partial("請問車站"), .final("請問車站在哪裡？")],
    ]

    private func speakChinese(_ h: Harness) async {
        h.vm.userButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToUser && h.vm.partialTranscript == "請問車站" }
        h.vm.userButtonTapped()
    }

    // MARK: 倒數設定

    func testCountdownDefaultsToOneSecondWithZeroToTwoOptions() {
        XCTAssertEqual(AppSettings().playbackCountdownSeconds, 1)
        XCTAssertEqual(SettingsViewModel.countdownOptions, [0, 1, 2])
    }

    func testCountdownSettingSurvivesSaveAndOldSettingsStillLoad() throws {
        var settings = AppSettings()
        settings.playbackCountdownSeconds = 0
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data).playbackCountdownSeconds, 0)
        let old = #"{"pauseSeconds":3}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: old).playbackCountdownSeconds, 1)
    }

    func testCountdownFollowsUserSetting() async {
        let h = Harness(scriptsByLocale: chineseScript, countdownFromSettings: true)
        await speakChinese(h)
        await waitUntil("countdown 1") { h.vm.state == .readyToPlayForPartner(countdown: 1) }
        XCTAssertEqual(h.vm.countdownRemaining, 1)
    }

    func testZeroCountdownPlaysRightAfterTranslation() async {
        var settings = AppSettings()
        settings.playbackCountdownSeconds = 0
        let h = Harness(scriptsByLocale: chineseScript, settings: settings, countdownFromSettings: true)
        await speakChinese(h)
        await waitUntil("speaking") { h.vm.state == .speakingPartnerLanguage && h.synthesis.isSpeaking }
        XCTAssertNil(h.vm.countdownRemaining)
        XCTAssertEqual(h.vm.entries.last?.speaker, .user)
    }

    // MARK: 各階段計時（只記時間，不記內容）

    func testTimingsRecordEachStage() async {
        let h = Harness(scriptsByLocale: chineseScript, holdTranslations: true)
        await speakChinese(h)
        await waitUntil("translating") { h.vm.state == .translatingToPartnerLanguage }
        h.sleeper.advance(by: .milliseconds(1500))
        h.translation.releaseTranslations()
        await waitUntil("countdown 2") { h.vm.state == .readyToPlayForPartner(countdown: 2) }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .seconds(1))
        await waitUntil("countdown 1") { h.vm.state == .readyToPlayForPartner(countdown: 1) }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .seconds(1))
        await waitUntil("speaking") { h.vm.state == .speakingPartnerLanguage && h.synthesis.isSpeaking }
        XCTAssertEqual(h.vm.lastTimings, TurnTimings(finishing: .zero, translation: .milliseconds(1500),
                                                     countdown: .seconds(2), voiceStart: .zero))
    }

    func testPartnerTurnTimingsHaveNoCountdown() async {
        let h = Harness()
        await h.runPartnerTurn()
        XCTAssertEqual(h.vm.lastTimings, TurnTimings(finishing: .zero, translation: .zero,
                                                     countdown: nil, voiceStart: .zero))
    }

    func testTimingSummaryRoundsToTenthsAndSkipsMissingStages() {
        let timings = TurnTimings(finishing: .milliseconds(840), translation: .milliseconds(1250),
                                  countdown: nil, voiceStart: .milliseconds(300))
        XCTAssertEqual(timings.summary, "收尾 0.8 秒・翻譯 1.3 秒・出聲 0.3 秒")
        XCTAssertEqual(TurnTimings(finishing: .zero, translation: nil, countdown: .seconds(1), voiceStart: nil).summary,
                       "收尾 0.0 秒・倒數 1.0 秒")
    }

    // MARK: 先暖好翻譯與聲音

    func testConversationStartWarmsBothDirectionsAndVoices() async {
        let h = Harness()
        h.vm.partnerButtonTapped()
        await waitUntil("warmed") { h.translation.warmedPairs.count == 2 && h.synthesis.warmedLanguages.count == 2 }
        XCTAssertEqual(Set(h.translation.warmedPairs), ["en->zh-Hant-TW", "zh-Hant-TW->en"])
        XCTAssertEqual(Set(h.synthesis.warmedLanguages), ["zh-TW", "en-US"])
    }

    func testWarmUpOnlyOncePerPartnerLanguage() async {
        let h = Harness()
        await h.runPartnerTurn()
        await h.runPartnerTurn()
        XCTAssertEqual(h.translation.warmedPairs.count, 2)
        h.vm.partnerLanguage = .japanese
        h.vm.partnerButtonTapped()
        await waitUntil("warmed ja") { h.translation.warmedPairs.count == 4 }
        XCTAssertTrue(h.translation.warmedPairs.contains("ja->zh-Hant-TW"))
        XCTAssertTrue(h.synthesis.warmedLanguages.contains("ja-JP"))
    }
}
