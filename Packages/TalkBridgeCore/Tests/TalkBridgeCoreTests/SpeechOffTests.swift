import Foundation
import XCTest
@testable import TalkBridgeCore
import TalkBridgeFakes

/// Kevin 2026-11-08：一個總開關把語音輸出關掉，只看文字；對話照常進行，手動播放／重播仍會唸。
@MainActor
final class SpeechOffTests: XCTestCase {
    private func mutedSettings(mode: ConversationMode = .manual) -> AppSettings {
        var settings = AppSettings()
        settings.speechOutputEnabled = false
        settings.mode = mode
        return settings
    }

    // MARK: 設定

    func testSpeechOutputIsOnByDefaultAndSurvivesSave() throws {
        XCTAssertTrue(AppSettings().speechOutputEnabled)
        let data = try JSONEncoder().encode(mutedSettings())
        XCTAssertFalse(try JSONDecoder().decode(AppSettings.self, from: data).speechOutputEnabled)
        let old = #"{"pauseSeconds":3}"#.data(using: .utf8)!
        XCTAssertTrue(try JSONDecoder().decode(AppSettings.self, from: old).speechOutputEnabled, "舊設定預設有聲音")
    }

    func testMutedHintShownOnlyWhenOff() {
        XCTAssertNil(Harness().vm.speechOffHint)
        XCTAssertEqual(Harness(settings: mutedSettings()).vm.speechOffHint, "目前只顯示文字，不唸出來")
    }

    // MARK: 關掉聲音時

    func testMutedPartnerTurnShowsChineseWithoutSpeaking() async {
        let h = Harness(settings: mutedSettings())
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner && !h.vm.partialTranscript.isEmpty }
        h.vm.partnerButtonTapped()
        await waitUntil("entry") { h.vm.entries.count == 1 && h.vm.state == .idle }
        XCTAssertEqual(h.vm.entries[0].translation, "[zh-Hant-TW] Where is the station?")
        XCTAssertFalse(h.log.entries.contains { $0.hasPrefix("synthesis.speak") })
    }

    func testMutedChineseTurnShowsTranslationWithoutCountdownOrSpeaking() async {
        let h = Harness(scriptsByLocale: ["zh-TW": [.partial("請問車站"), .final("請問車站在哪裡？")]],
                        settings: mutedSettings())
        h.vm.userButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToUser && h.vm.partialTranscript == "請問車站" }
        h.vm.userButtonTapped()
        await waitUntil("entry") { h.vm.entries.count == 1 && h.vm.state == .idle }
        XCTAssertEqual(h.vm.entries[0].speaker, .user)
        XCTAssertEqual(h.vm.entries[0].translation, "[en] 請問車站在哪裡？")
        XCTAssertNil(h.vm.countdownRemaining)
        XCTAssertFalse(h.log.entries.contains { $0.hasPrefix("synthesis.speak") })
        XCTAssertFalse(h.log.entries.contains { $0.hasPrefix("audio.setOutput") }, "不唸就不用切喇叭")
    }

    func testMutedAutoAlternateMovesToNextSpeakerRightAway() async {
        let h = Harness(settings: mutedSettings(mode: .autoAlternate))
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner && !h.vm.partialTranscript.isEmpty }
        h.vm.partnerButtonTapped()
        await waitUntil("entry") { h.vm.entries.count == 1 }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .milliseconds(300))
        await waitUntil("listening to user") { h.vm.state == .listeningToUser }
        XCTAssertTrue(h.log.entries.contains("recognition.start(zh-TW)"))
    }

    func testReplayStillSpeaksWhenMuted() async {
        let h = Harness(settings: mutedSettings())
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner && !h.vm.partialTranscript.isEmpty }
        h.vm.partnerButtonTapped()
        await waitUntil("entry") { h.vm.entries.count == 1 && h.vm.state == .idle }
        h.vm.replay(h.vm.entries[0].id)
        await waitUntil("speaking") { h.vm.state == .speakingChinese && h.synthesis.isSpeaking }
        XCTAssertTrue(h.log.entries.contains("synthesis.speak(zh-TW)"))
    }
}
