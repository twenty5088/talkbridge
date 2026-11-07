import XCTest
@testable import TalkBridgeCore
import TalkBridgeFakes

/// v2 設計 §3：使用情境總檢查找到的問題（P3–P11）。
@MainActor
final class ScenarioFixTests: XCTestCase {
    private let chinese: [RecognitionUpdate] = [.partial("請問車站"), .final("請問車站在哪裡？")]

    private func settings(_ mode: ConversationMode) -> AppSettings {
        var settings = AppSettings()
        settings.mode = mode
        return settings
    }

    /// 對方說一句並播完中文（自動輪流會接著聽太太）。
    private func finishPartnerTurn(_ h: Harness) async {
        h.vm.partnerButtonTapped()
        await waitUntil("listening partner") { h.vm.state == .listeningToPartner && !h.vm.partialTranscript.isEmpty }
        h.vm.partnerButtonTapped()
        await waitUntil("speaking chinese") { h.vm.state == .speakingChinese && h.synthesis.isSpeaking }
        h.synthesis.completeCurrent()
        await waitUntil("idle") { h.vm.state == .idle }
    }

    /// 聽到部分結果後停頓 2 秒（預設停頓），讓這句結束。
    private func endUtteranceBySilence(_ h: Harness, partial: String) async {
        await waitUntil("partial \(partial)") { h.vm.state.isMicrophoneActive && h.vm.partialTranscript == partial }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .seconds(2))
    }

    private func passMicGuard(_ h: Harness) async {
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .milliseconds(300))
    }

    /// 太太說中文 → 倒數 → 播外語 → 播完。
    private func finishUserTurn(_ h: Harness) async {
        h.vm.userButtonTapped()
        await waitUntil("listening user") { h.vm.state == .listeningToUser && !h.vm.partialTranscript.isEmpty }
        h.vm.userButtonTapped()
        await waitUntil("countdown") { h.vm.state == .readyToPlayForPartner(countdown: 2) }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .seconds(1))
        await waitUntil("countdown 1") { h.vm.state == .readyToPlayForPartner(countdown: 1) }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .seconds(1))
        await waitUntil("speaking") { h.vm.state == .speakingPartnerLanguage && h.synthesis.isSpeaking }
        h.synthesis.completeCurrent()
        await waitUntil("idle") { h.vm.state == .idle }
    }

    // MARK: P4 自動輪流忽略空白結果

    func testAutoModeIgnoresEmptyTranscriptAndKeepsListening() async {
        let h = Harness(scriptsByLocale: ["en-US": [.partial("。"), .final("。")]], settings: settings(.autoAlternate))
        h.vm.partnerButtonTapped()
        await endUtteranceBySilence(h, partial: "。")
        await waitUntil("first listen done") { h.log.count(of: "recognition.start(en-US)") == 1 && h.vm.state == .idle }
        XCTAssertNil(h.vm.notice, "自動輪流不顯示「沒有聽到內容」")
        XCTAssertEqual(h.vm.currentTurn, .partner, "自動輪流沒有停")
        await passMicGuard(h)
        await waitUntil("listening again") { h.log.count(of: "recognition.start(en-US)") == 2 }
        XCTAssertEqual(h.log.count(of: "translation.translate(en->zh-Hant-TW)"), 0)
    }

    func testManualModeEmptyTranscriptStillShowsNotice() async {
        let h = Harness(scriptsByLocale: ["en-US": [.partial("。"), .final("。")]])
        h.vm.partnerButtonTapped()
        await endUtteranceBySilence(h, partial: "。")
        await waitUntil("idle with notice") { h.vm.state == .idle && h.vm.notice != nil }
        XCTAssertEqual(h.vm.notice, "沒有聽到內容，請再說一次。")
        h.sleeper.advance(by: .seconds(1))
        for _ in 0..<500 { await Task.yield() }
        XCTAssertEqual(h.log.count(of: "recognition.start(en-US)"), 1)
    }

    // MARK: P6 自動輪流 60 秒沒聲音才暫停

    func testAutoModeNoSpeechPausesAfter60Seconds() async {
        XCTAssertEqual(ConversationConfiguration.standard.autoModeNoSpeechTimeout, .seconds(60))
        let h = Harness(script: [], settings: settings(.autoAlternate))
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .seconds(59))
        for _ in 0..<1000 { await Task.yield() }
        XCTAssertEqual(h.vm.state, .listeningToPartner, "59 秒還要繼續聽")
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .seconds(1))
        await waitUntil("paused") { h.vm.state == .idle }
        XCTAssertEqual(h.vm.notice, "太久沒有聲音，已暫停自動輪流。")
        XCTAssertNil(h.vm.currentTurn)
    }

    func testManualModeNoSpeechStill15Seconds() async {
        let h = Harness(script: [])
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .seconds(15))
        await waitUntil("idle") { h.vm.state == .idle }
        XCTAssertEqual(h.vm.notice, AppError.noSpeechDetected.userMessage)
    }

    // MARK: P5 聆聽中重播

    func testReplayWhileListeningStopsMicPlaysThenResumesSameSpeaker() async {
        let h = Harness(scriptsByLocale: ["zh-TW": chinese], settings: settings(.autoAlternate))
        await finishPartnerTurn(h)
        await passMicGuard(h)
        await waitUntil("listening user") { h.vm.state == .listeningToUser }
        let entryID = h.vm.entries[0].id
        h.vm.replay(entryID)
        await waitUntil("replaying") { h.vm.state == .speakingChinese && h.synthesis.isSpeaking }
        XCTAssertFalse(h.recognition.isListening, "重播前要先關麥克風")
        let entries = h.log.entries
        let cancelIndex = entries.lastIndex(of: "recognition.cancel")
        let speakIndex = entries.lastIndex(of: "synthesis.speak(zh-TW)")
        XCTAssertNotNil(cancelIndex)
        if let cancelIndex, let speakIndex { XCTAssertLessThan(cancelIndex, speakIndex) }
        h.synthesis.completeCurrent()
        await waitUntil("idle") { h.vm.state == .idle }
        await passMicGuard(h)
        await waitUntil("listening user again") { h.vm.state == .listeningToUser }
        XCTAssertEqual(h.log.count(of: "recognition.start(zh-TW)"), 2)
        XCTAssertEqual(h.vm.currentTurn, .user)
    }

    func testReplayWhenIdleDoesNotStartListening() async {
        let h = Harness()
        await finishPartnerTurn(h)
        h.vm.replay(h.vm.entries[0].id)
        await waitUntil("replaying") { h.vm.state == .speakingChinese && h.synthesis.isSpeaking }
        h.synthesis.completeCurrent()
        await waitUntil("idle") { h.vm.state == .idle }
        h.sleeper.advance(by: .seconds(1))
        for _ in 0..<500 { await Task.yield() }
        XCTAssertEqual(h.log.count(of: "recognition.start(en-US)"), 1)
    }

    // MARK: P7 再試一次用同一句

    func testRetryAfterTranslationFailureRetranslatesSameText() async {
        let h = Harness(translateError: AppError.translationFailed)
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner && !h.vm.partialTranscript.isEmpty }
        h.vm.partnerButtonTapped()
        await waitUntil("error") { h.vm.state == .error(.translationFailed) }
        h.translation.setTranslateError(nil)
        h.vm.recover()
        await waitUntil("speaking chinese") { h.vm.state == .speakingChinese && h.synthesis.isSpeaking }
        XCTAssertEqual(h.log.count(of: "recognition.start(en-US)"), 1, "不用重講")
        XCTAssertEqual(h.log.count(of: "translation.translate(en->zh-Hant-TW)"), 2)
        XCTAssertEqual(h.vm.entries.last?.original, "Where is the station?")
        XCTAssertEqual(h.vm.entries.last?.translation, "[zh-Hant-TW] Where is the station?")
        XCTAssertNil(h.vm.lastError)
    }

    func testRetryForChineseGoesToCountdownAgain() async {
        let h = Harness(scriptsByLocale: ["zh-TW": chinese], translateError: AppError.translationFailed)
        h.vm.userButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToUser && !h.vm.partialTranscript.isEmpty }
        h.vm.userButtonTapped()
        await waitUntil("error") { h.vm.state == .error(.translationFailed) }
        h.translation.setTranslateError(nil)
        h.vm.recover()
        await waitUntil("countdown") { h.vm.state == .readyToPlayForPartner(countdown: 2) }
        XCTAssertEqual(h.vm.editableTranslation, "[en] 請問車站在哪裡？")
        XCTAssertEqual(h.log.count(of: "recognition.start(zh-TW)"), 1)
    }

    // MARK: P8 殘響過濾

    func testEchoOfJustPlayedTranslationIsDiscarded() async {
        let echo = "[en] 請問車站在哪裡？"
        let h = Harness(scriptsByLocale: ["zh-TW": chinese, "en-US": [.partial(echo), .final(echo)]],
                        settings: settings(.autoAlternate))
        await finishUserTurn(h)
        await passMicGuard(h)
        await endUtteranceBySilence(h, partial: echo)
        await waitUntil("first partner listen done") {
            h.log.count(of: "recognition.start(en-US)") == 1 && h.vm.state == .idle
        }
        XCTAssertEqual(h.log.count(of: "translation.translate(en->zh-Hant-TW)"), 0, "殘響不翻譯")
        XCTAssertEqual(h.vm.currentTurn, .partner)
        // 只檢查播放後的第一句：之後同樣的話照常翻譯。
        await passMicGuard(h)
        await endUtteranceBySilence(h, partial: echo)
        await waitUntil("second listen translated") { h.log.count(of: "translation.translate(en->zh-Hant-TW)") == 1 }
    }

    func testDifferentSentenceAfterPlaybackIsNotDiscarded() async {
        let h = Harness(scriptsByLocale: ["zh-TW": chinese, "en-US": [.partial("It is over there"), .final("It is over there.")]],
                        settings: settings(.autoAlternate))
        await finishUserTurn(h)
        await passMicGuard(h)
        await endUtteranceBySilence(h, partial: "It is over there")
        await waitUntil("translated") { h.log.count(of: "translation.translate(en->zh-Hant-TW)") == 1 }
    }

    // MARK: P3、P10 畫面提示

    func testKeepsScreenAwakeDuringConversation() async {
        let h = Harness(scriptsByLocale: ["zh-TW": chinese], settings: settings(.autoAlternate))
        XCTAssertFalse(h.vm.keepsScreenAwake)
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner }
        XCTAssertTrue(h.vm.keepsScreenAwake)
        h.vm.partnerButtonTapped()
        await waitUntil("speaking") { h.vm.state == .speakingChinese && h.synthesis.isSpeaking }
        h.synthesis.completeCurrent()
        await waitUntil("idle between turns") { h.vm.state == .idle }
        XCTAssertTrue(h.vm.keepsScreenAwake, "自動輪流換人之間也不能鎖螢幕")
        h.vm.stopAll()
        XCTAssertFalse(h.vm.keepsScreenAwake)
    }

    func testMicrophoneHints() async {
        let h = Harness(scriptsByLocale: ["zh-TW": chinese], holdTranslations: true)
        XCTAssertNil(h.vm.microphoneHint)
        h.vm.partnerButtonTapped()
        await waitUntil("listening partner") { h.vm.state == .listeningToPartner }
        XCTAssertEqual(h.vm.microphoneHint, "現在可以說話：English")
        h.vm.partnerButtonTapped()
        await waitUntil("translating") { h.vm.state == .translatingToChinese }
        XCTAssertEqual(h.vm.microphoneHint, "請稍等，麥克風已關閉")
        h.vm.stopAll()
        h.vm.userButtonTapped()
        await waitUntil("listening user") { h.vm.state == .listeningToUser }
        XCTAssertEqual(h.vm.microphoneHint, "現在可以說話：中文")
        h.vm.stopAll()
        XCTAssertNil(h.vm.microphoneHint)
    }

    func testQueuedHint() async {
        let h = Harness(holdTranslations: true)
        XCTAssertNil(h.vm.queuedHint)
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner && !h.vm.partialTranscript.isEmpty }
        h.vm.partnerButtonTapped()
        await waitUntil("translating") { h.vm.state == .translatingToChinese }
        h.vm.userButtonTapped()
        XCTAssertEqual(h.vm.queuedHint, "下一句：我說中文")
        h.vm.partnerButtonTapped()
        XCTAssertEqual(h.vm.queuedHint, "下一句：對方說話")
        h.vm.stopAll()
        XCTAssertNil(h.vm.queuedHint)
    }
}

final class EchoFilterTests: XCTestCase {
    func testIdenticalTextIsEcho() {
        XCTAssertTrue(EchoFilter.isLikelyEcho(heard: "Where is the station?", played: "Where is the station?", threshold: 0.8))
    }

    func testCaseAndPunctuationAreIgnored() {
        XCTAssertTrue(EchoFilter.isLikelyEcho(heard: "where is the station", played: "Where is the station?", threshold: 0.8))
    }

    func testMostlyMatchingTailIsEcho() {
        XCTAssertTrue(EchoFilter.isLikelyEcho(heard: "is the station", played: "Where is the station?", threshold: 0.6))
    }

    func testDifferentTextIsNotEcho() {
        XCTAssertFalse(EchoFilter.isLikelyEcho(heard: "It is over there.", played: "Where is the station?", threshold: 0.8))
    }

    func testEmptyIsNotEcho() {
        XCTAssertFalse(EchoFilter.isLikelyEcho(heard: "", played: "Where is the station?", threshold: 0.8))
        XCTAssertFalse(EchoFilter.isLikelyEcho(heard: "Hello", played: "", threshold: 0.8))
    }

    func testChineseEcho() {
        XCTAssertTrue(EchoFilter.isLikelyEcho(heard: "請問車站在哪裡", played: "請問車站在哪裡？", threshold: 0.8))
        XCTAssertFalse(EchoFilter.isLikelyEcho(heard: "我要去機場", played: "請問車站在哪裡？", threshold: 0.8))
    }

    func testDefaultThreshold() {
        XCTAssertEqual(ConversationConfiguration.standard.echoSimilarityThreshold, 0.8)
    }
}
