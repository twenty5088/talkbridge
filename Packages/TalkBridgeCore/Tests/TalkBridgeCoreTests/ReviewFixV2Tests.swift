import XCTest
@testable import TalkBridgeCore
import TalkBridgeFakes

/// v2 整體審查找到的問題（R1–R8），每一項先寫會失敗的測試再修。
@MainActor
final class ReviewFixV2Tests: XCTestCase {
    private let chinese: [RecognitionUpdate] = [.partial("請問車站"), .final("請問車站在哪裡？")]

    private func settings(_ mode: ConversationMode) -> AppSettings {
        var settings = AppSettings()
        settings.mode = mode
        return settings
    }

    private func finishPartnerTurn(_ h: Harness) async {
        h.vm.partnerButtonTapped()
        await waitUntil("listening partner") { h.vm.state == .listeningToPartner && !h.vm.partialTranscript.isEmpty }
        h.vm.partnerButtonTapped()
        await waitUntil("speaking chinese") { h.vm.state == .speakingChinese && h.synthesis.isSpeaking }
        h.synthesis.completeCurrent()
        await waitUntil("idle") { h.vm.state == .idle }
    }

    private func finishUserTurn(_ h: Harness) async {
        h.vm.userButtonTapped()
        await waitUntil("listening user") { h.vm.state == .listeningToUser && !h.vm.partialTranscript.isEmpty }
        h.vm.userButtonTapped()
        await waitUntil("countdown") { h.vm.state == .readyToPlayForPartner(countdown: 2) }
        h.vm.playForPartner()
        await waitUntil("speaking") { h.vm.state == .speakingPartnerLanguage && h.synthesis.isSpeaking }
        h.synthesis.completeCurrent()
        await waitUntil("idle") { h.vm.state == .idle }
    }

    private func passMicGuard(_ h: Harness) async {
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .milliseconds(300))
    }

    private func settle(_ h: Harness) async {
        h.sleeper.advance(by: .seconds(1))
        for _ in 0..<1000 { await Task.yield() }
    }

    // MARK: R1 記住的下一句不可殘留

    func testQueuedSpeakerIsUsedWhenTranscriptTurnsOutEmpty() async {
        // 沒有最終結果：停在「正在辨識」等 2 秒，這時按「我說中文」。
        let h = Harness(scriptsByLocale: ["en-US": [.partial("。")], "zh-TW": chinese], sendsFinal: false)
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner && h.vm.partialTranscript == "。" }
        h.vm.partnerButtonTapped()
        await waitUntil("transcribing") { h.vm.state == .transcribingPartner }
        h.vm.userButtonTapped()
        XCTAssertEqual(h.vm.queuedSpeaker, .user)
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .seconds(2))   // 等不到最終結果 → 用部分結果「。」→ 空白
        await passMicGuard(h)
        await waitUntil("listening user") { h.vm.state == .listeningToUser }
        XCTAssertNil(h.vm.queuedSpeaker)
    }

    func testQueuedSpeakerIsUsedWhenChineseVoiceMissing() async {
        let h = Harness(scriptsByLocale: ["zh-TW": chinese], holdTranslations: true, voiceMatch: .none)
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner && !h.vm.partialTranscript.isEmpty }
        h.vm.partnerButtonTapped()
        await waitUntil("translating") { h.vm.state == .translatingToChinese }
        h.vm.userButtonTapped()
        h.translation.releaseTranslations()
        await waitUntil("idle without voice") { h.vm.state == .idle && h.vm.notice != nil }
        await passMicGuard(h)
        await waitUntil("listening user") { h.vm.state == .listeningToUser }
    }

    func testAutoModeContinuesWhenChineseVoiceMissing() async {
        let h = Harness(scriptsByLocale: ["zh-TW": chinese], voiceMatch: .none, settings: settings(.autoAlternate))
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner && !h.vm.partialTranscript.isEmpty }
        h.vm.partnerButtonTapped()
        await waitUntil("idle without voice") { h.vm.state == .idle && h.vm.notice != nil }
        await passMicGuard(h)
        await waitUntil("auto turn to user") { h.vm.state == .listeningToUser }
    }

    // MARK: R2 麥克風保護間隔內的中斷

    func testBackgroundDuringMicGuardDoesNotOpenMic() async {
        let h = Harness(scriptsByLocale: ["zh-TW": chinese], settings: settings(.autoAlternate))
        await finishPartnerTurn(h)
        h.vm.appDidEnterBackground()
        await settle(h)
        XCTAssertEqual(h.log.count(of: "recognition.start(zh-TW)"), 0)
        XCTAssertNil(h.vm.currentTurn)
        XCTAssertFalse(h.vm.keepsScreenAwake)
    }

    func testInterruptionDuringMicGuardDoesNotOpenMic() async {
        let h = Harness(scriptsByLocale: ["zh-TW": chinese], settings: settings(.autoAlternate))
        await finishPartnerTurn(h)
        h.vm.handleAudioEvent(.interruptionBegan)
        await settle(h)
        XCTAssertEqual(h.log.count(of: "recognition.start(zh-TW)"), 0)
        XCTAssertNil(h.vm.currentTurn)
    }

    func testLanguageChangeDuringMicGuardDoesNotOpenMic() async {
        let h = Harness(scriptsByLocale: ["zh-TW": chinese], settings: settings(.autoAlternate))
        await finishPartnerTurn(h)
        h.vm.partnerLanguage = .korean
        await settle(h)
        XCTAssertEqual(h.log.count(of: "recognition.start(zh-TW)"), 0)
        XCTAssertNil(h.vm.currentTurn)
    }

    // MARK: R3 準備中或保護間隔內按重播

    func testReplayDuringTurnPreparationCancelsItAndResumesAfterPlayback() async {
        let h = Harness()
        await finishPartnerTurn(h)
        h.vm.partnerButtonTapped()          // 開始準備（權限、語言檢查），狀態還是待機
        h.vm.replay(h.vm.entries[0].id)     // 立刻重播
        await waitUntil("replaying") { h.vm.state == .speakingChinese && h.synthesis.isSpeaking }
        for _ in 0..<1000 { await Task.yield() }
        XCTAssertEqual(h.log.count(of: "recognition.start(en-US)"), 1, "播放中不可開麥克風")
        h.synthesis.completeCurrent()
        await waitUntil("idle") { h.vm.state == .idle }
        await passMicGuard(h)
        await waitUntil("resumed partner") { h.vm.state == .listeningToPartner }
    }

    func testReplayDuringMicGuardResumesScheduledTurn() async {
        let h = Harness(scriptsByLocale: ["zh-TW": chinese], settings: settings(.autoAlternate))
        await finishPartnerTurn(h)          // 自動輪流：0.3 秒後要聽太太
        h.vm.replay(h.vm.entries[0].id)
        await waitUntil("replaying") { h.vm.state == .speakingChinese && h.synthesis.isSpeaking }
        h.synthesis.completeCurrent()
        await waitUntil("idle") { h.vm.state == .idle }
        await passMicGuard(h)
        await waitUntil("listening user") { h.vm.state == .listeningToUser }
        XCTAssertEqual(h.log.count(of: "recognition.start(zh-TW)"), 1)
    }

    // MARK: R4 殘響過濾不可誤丟真的回答

    func testEchoFilterIgnoresShortPhrasesAndExtraWords() {
        XCTAssertFalse(EchoFilter.isLikelyEcho(heard: "謝謝", played: "謝謝", threshold: 0.9))
        XCTAssertFalse(EchoFilter.isLikelyEcho(heard: "Nice to meet you too", played: "Nice to meet you", threshold: 0.9))
        XCTAssertEqual(ConversationConfiguration.standard.echoSimilarityThreshold, 0.9)
    }

    func testSameSentenceLongAfterPlaybackIsNotEcho() async {
        let echo = "[en] 請問車站在哪裡？"
        let h = Harness(scriptsByLocale: ["zh-TW": chinese, "en-US": [.partial(echo), .final(echo)]])
        await finishUserTurn(h)
        h.sleeper.advance(by: .seconds(10))   // 手動模式：10 秒後才按「對方說話」
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner && h.vm.partialTranscript == echo }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .seconds(2))
        await waitUntil("translated") { h.log.count(of: "translation.translate(en->zh-Hant-TW)") == 1 }
    }

    func testSpeechStartingLateAfterPlaybackIsNotEcho() async {
        let echo = "[en] 請問車站在哪裡？"
        let h = Harness(scriptsByLocale: ["zh-TW": chinese, "en-US": []], settings: settings(.autoAlternate))
        await finishUserTurn(h)
        await passMicGuard(h)
        await waitUntil("listening partner") { h.vm.state == .listeningToPartner }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .seconds(3))   // 3 秒後對方才開口
        h.recognition.emit(.partial(echo))
        await waitUntil("partial") { h.vm.partialTranscript == echo }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .seconds(2))
        await waitUntil("translated") { h.log.count(of: "translation.translate(en->zh-Hant-TW)") == 1 }
    }

    // MARK: R5 自動輪流在雜音中不可無限重聽

    func testAutoModeNoiseLoopPausesAfterTotalNoSpeechTimeout() async {
        var configuration = ConversationConfiguration.standard
        configuration.autoModeNoSpeechTimeout = .seconds(5)
        let h = Harness(scriptsByLocale: ["en-US": [.partial("。"), .final("。")]],
                        settings: settings(.autoAlternate), configuration: configuration)
        h.vm.partnerButtonTapped()
        for _ in 0..<6 {
            await waitUntil("noise partial") { h.vm.state == .listeningToPartner && h.vm.partialTranscript == "。" }
            await h.sleeper.waitForPendingCount(1)
            h.sleeper.advance(by: .seconds(2))
            await waitUntil("ignored") { h.vm.state == .idle }
            if h.vm.currentTurn == nil { break }
            await passMicGuard(h)
        }
        XCTAssertNil(h.vm.currentTurn, "累計超過沒聲音上限要暫停自動輪流")
        XCTAssertEqual(h.vm.notice, "太久沒有聲音，已暫停自動輪流。")
        XCTAssertLessThanOrEqual(h.log.count(of: "recognition.start(en-US)"), 3)
        await settle(h)
        XCTAssertLessThanOrEqual(h.log.count(of: "recognition.start(en-US)"), 3)
    }

    // MARK: R6 換語言後不可用舊語言重試

    func testLanguageChangeClearsFailedUtterance() async {
        let h = Harness(translateError: AppError.translationFailed)
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner && !h.vm.partialTranscript.isEmpty }
        h.vm.partnerButtonTapped()
        await waitUntil("error") { h.vm.state == .error(.translationFailed) }
        h.translation.setTranslateError(nil)
        h.vm.partnerLanguage = .japanese
        h.vm.recover()
        await settle(h)
        XCTAssertEqual(h.log.count(of: "translation.translate(en->zh-Hant-TW)"), 1, "不可用舊語言重翻")
        XCTAssertFalse(h.synthesis.isSpeaking)
    }

    // MARK: R7 發生錯誤要結束自動輪流

    func testErrorEndsAutoAlternation() async {
        let h = Harness(translateError: AppError.translationFailed, settings: settings(.autoAlternate))
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner && !h.vm.partialTranscript.isEmpty }
        h.vm.partnerButtonTapped()
        await waitUntil("error") { h.vm.state == .error(.translationFailed) }
        XCTAssertNil(h.vm.currentTurn)
        XCTAssertFalse(h.vm.keepsScreenAwake)
    }

    // MARK: UI 測試假情境：翻譯只失敗一次

    func testTranslationFailureScenarioRetrySucceeds() async {
        let services = FakeScenario.translationFailure.makeServices(sleeper: ManualSleeper())
        do {
            _ = try await services.translation.translate("Hi there", source: "en", target: "zh-Hant-TW")
            XCTFail("第一次要失敗")
        } catch {}
        let second = try? await services.translation.translate("Hi there", source: "en", target: "zh-Hant-TW")
        XCTAssertEqual(second, "[zh-Hant-TW] Hi there")
    }

    // MARK: R8 等使用者按播放時的提示

    func testHintWhileWaitingForUserToPlay() async {
        var s = AppSettings()
        s.confirmBeforePlay = true
        let h = Harness(scriptsByLocale: ["zh-TW": chinese], settings: s)
        h.vm.userButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToUser && !h.vm.partialTranscript.isEmpty }
        h.vm.userButtonTapped()
        await waitUntil("waiting") { h.vm.state == .readyToPlayForPartner(countdown: nil) }
        XCTAssertEqual(h.vm.microphoneHint, "按「播放」給對方聽，或按按鈕繼續說")
    }
}
