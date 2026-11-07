import XCTest
@testable import TalkBridgeCore
import TalkBridgeFakes

/// v2 設計 §2：翻譯、倒數或播放中按按鈕＝記住「下一句換誰說」，不中斷目前這句（Kevin 2026-11-07）。
@MainActor
final class NextSpeakerQueueTests: XCTestCase {
    private struct SampleError: Error {}

    private let scripts: [String: [RecognitionUpdate]] = [
        "en-US": [.partial("Where is it"), .final("Where is it?")],
        "zh-TW": [.partial("請問車站"), .final("請問車站在哪裡？")],
    ]

    private func makeHarness(mode: ConversationMode = .autoAlternate, holdTranslations: Bool = false) -> Harness {
        var settings = AppSettings()
        settings.mode = mode
        return Harness(scriptsByLocale: scripts, holdTranslations: holdTranslations, settings: settings)
    }

    /// 太太說一句中文，翻譯完進入倒數。
    private func speakChinese(_ h: Harness) async {
        h.vm.userButtonTapped()
        await waitUntil("listening user") { h.vm.state == .listeningToUser && h.vm.partialTranscript == "請問車站" }
        h.vm.userButtonTapped()
        await waitUntil("countdown 2") { h.vm.state == .readyToPlayForPartner(countdown: 2) }
    }

    /// 倒數 2 秒走完，開始播外語。
    private func runCountdown(_ h: Harness) async {
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .seconds(1))
        await waitUntil("countdown 1") { h.vm.state == .readyToPlayForPartner(countdown: 1) }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .seconds(1))
        await waitUntil("speaking partner language") { h.vm.state == .speakingPartnerLanguage && h.synthesis.isSpeaking }
    }

    /// 播完，過 0.3 秒麥克風保護間隔。
    private func finishPlaybackAndGuard(_ h: Harness) async {
        h.synthesis.completeCurrent()
        await waitUntil("idle after playback") { h.vm.state == .idle }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .milliseconds(300))
    }

    private func assertNoNewListening(_ h: Harness, zhStarts: Int, enStarts: Int,
                                      file: StaticString = #filePath, line: UInt = #line) async {
        h.sleeper.advance(by: .seconds(1))
        for _ in 0..<1000 { await Task.yield() }
        XCTAssertEqual(h.log.count(of: "recognition.start(zh-TW)"), zhStarts, file: file, line: line)
        XCTAssertEqual(h.log.count(of: "recognition.start(en-US)"), enStarts, file: file, line: line)
    }

    func testUserTapDuringPartnerLanguagePlaybackQueuesChineseAndDoesNotStop() async {
        let h = makeHarness()
        await speakChinese(h)
        await runCountdown(h)
        h.vm.userButtonTapped()
        XCTAssertEqual(h.vm.state, .speakingPartnerLanguage, "播放不可被中斷")
        XCTAssertTrue(h.synthesis.isSpeaking)
        XCTAssertEqual(h.log.count(of: "synthesis.stop"), 0)
        XCTAssertEqual(h.vm.queuedSpeaker, .user)
        await finishPlaybackAndGuard(h)
        await waitUntil("listening user again") { h.vm.state == .listeningToUser }
        XCTAssertEqual(h.log.count(of: "recognition.start(zh-TW)"), 2)
        XCTAssertEqual(h.log.count(of: "recognition.start(en-US)"), 0, "自動輪流原本會換對方，按了就聽中文")
        XCTAssertNil(h.vm.queuedSpeaker)
        XCTAssertEqual(h.vm.currentTurn, .user)
    }

    func testUserTapDuringPlaybackInManualModeAlsoListensChineseAfterward() async {
        let h = makeHarness(mode: .manual)
        await speakChinese(h)
        await runCountdown(h)
        h.vm.userButtonTapped()
        XCTAssertEqual(h.vm.state, .speakingPartnerLanguage)
        await finishPlaybackAndGuard(h)
        await waitUntil("listening user again") { h.vm.state == .listeningToUser }
        XCTAssertEqual(h.log.count(of: "recognition.start(zh-TW)"), 2)
    }

    func testUserTapDuringCountdownKeepsPendingAndPlaysThenListensChinese() async {
        let h = makeHarness()
        await speakChinese(h)
        h.vm.userButtonTapped()
        XCTAssertEqual(h.vm.state, .readyToPlayForPartner(countdown: 2), "倒數中按「我說中文」不可丟掉待播句")
        XCTAssertEqual(h.vm.queuedSpeaker, .user)
        await runCountdown(h)
        XCTAssertEqual(h.vm.entries.count, 1)
        XCTAssertEqual(h.vm.entries.first?.original, "請問車站在哪裡？")
        await finishPlaybackAndGuard(h)
        await waitUntil("listening user again") { h.vm.state == .listeningToUser }
        XCTAssertEqual(h.log.count(of: "recognition.start(zh-TW)"), 2)
    }

    func testPartnerTapDuringTranslatingToChineseQueuesPartner() async {
        let h = makeHarness(holdTranslations: true)
        h.vm.partnerButtonTapped()
        await waitUntil("listening partner") { h.vm.state == .listeningToPartner && !h.vm.partialTranscript.isEmpty }
        h.vm.partnerButtonTapped()
        await waitUntil("translating") { h.vm.state == .translatingToChinese }
        h.vm.partnerButtonTapped()
        XCTAssertEqual(h.vm.queuedSpeaker, .partner)
        XCTAssertEqual(h.vm.state, .translatingToChinese)
        h.translation.releaseTranslations()
        await waitUntil("speaking chinese") { h.vm.state == .speakingChinese && h.synthesis.isSpeaking }
        h.vm.partnerButtonTapped()
        XCTAssertEqual(h.vm.state, .speakingChinese, "播中文時按也不中斷")
        await finishPlaybackAndGuard(h)
        await waitUntil("listening partner again") { h.vm.state == .listeningToPartner }
        XCTAssertEqual(h.log.count(of: "recognition.start(en-US)"), 2)
        XCTAssertEqual(h.log.count(of: "recognition.start(zh-TW)"), 0, "自動輪流原本會換太太，按了就繼續聽對方")
        XCTAssertEqual(h.vm.currentTurn, .partner)
    }

    func testPartnerTapDuringChinesePlaybackInManualModeListensPartnerAgain() async {
        let h = makeHarness(mode: .manual)
        h.vm.partnerButtonTapped()
        await waitUntil("listening partner") { h.vm.state == .listeningToPartner && !h.vm.partialTranscript.isEmpty }
        h.vm.partnerButtonTapped()
        await waitUntil("speaking chinese") { h.vm.state == .speakingChinese && h.synthesis.isSpeaking }
        h.vm.partnerButtonTapped()
        XCTAssertEqual(h.vm.state, .speakingChinese)
        await finishPlaybackAndGuard(h)
        await waitUntil("listening partner again") { h.vm.state == .listeningToPartner }
    }

    func testLastTapWins() async {
        let h = makeHarness()
        await speakChinese(h)
        await runCountdown(h)
        h.vm.partnerButtonTapped()
        h.vm.userButtonTapped()
        XCTAssertEqual(h.vm.queuedSpeaker, .user)
        await finishPlaybackAndGuard(h)
        await waitUntil("listening user") { h.vm.state == .listeningToUser }
    }

    func testStopAllClearsQueue() async {
        let h = makeHarness()
        await speakChinese(h)
        h.vm.userButtonTapped()
        h.vm.stopAll()
        XCTAssertNil(h.vm.queuedSpeaker)
        XCTAssertEqual(h.vm.state, .idle)
        await assertNoNewListening(h, zhStarts: 1, enStarts: 0)
    }

    func testStopPlaybackClearsQueue() async {
        let h = makeHarness()
        await speakChinese(h)
        await runCountdown(h)
        h.vm.userButtonTapped()
        h.vm.stopPlayback()
        XCTAssertNil(h.vm.queuedSpeaker)
        XCTAssertEqual(h.vm.state, .readyToPlayForPartner(countdown: nil))
        await assertNoNewListening(h, zhStarts: 1, enStarts: 0)
    }

    func testPlaybackErrorClearsQueue() async {
        let h = makeHarness()
        await speakChinese(h)
        await runCountdown(h)
        h.vm.userButtonTapped()
        h.synthesis.failCurrent(SampleError())
        await waitUntil("error") { h.vm.lastError != nil }
        XCTAssertNil(h.vm.queuedSpeaker)
        await assertNoNewListening(h, zhStarts: 1, enStarts: 0)
    }

    func testLanguageChangeClearsQueue() async {
        let h = makeHarness()
        await speakChinese(h)
        await runCountdown(h)
        h.vm.userButtonTapped()
        h.vm.partnerLanguage = .japanese
        XCTAssertNil(h.vm.queuedSpeaker)
        XCTAssertEqual(h.vm.state, .idle)
        await assertNoNewListening(h, zhStarts: 1, enStarts: 0)
    }

    func testBackgroundClearsQueue() async {
        let h = makeHarness()
        await speakChinese(h)
        await runCountdown(h)
        h.vm.userButtonTapped()
        h.vm.appDidEnterBackground()
        XCTAssertNil(h.vm.queuedSpeaker)
        await assertNoNewListening(h, zhStarts: 1, enStarts: 0)
    }
}
