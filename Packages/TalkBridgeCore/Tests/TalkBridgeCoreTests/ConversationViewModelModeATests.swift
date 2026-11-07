import XCTest
@testable import TalkBridgeCore
import TalkBridgeFakes

@MainActor
final class ConversationViewModelModeATests: XCTestCase {
    func testModeAHappyPathCallOrder() async {
        let h = Harness()
        h.vm.partnerButtonTapped()
        await waitUntil("partial") { h.vm.state == .listeningToPartner && h.vm.partialTranscript == "Where is the station" }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .milliseconds(1200))
        await waitUntil("speaking") { h.vm.state == .speakingChinese && h.synthesis.isSpeaking }
        h.synthesis.completeCurrent()
        await waitUntil("idle") { h.vm.state == .idle }

        XCTAssertEqual(h.log.entries, [
            "audio.activate", "recognition.start(en-US)", "recognition.finishAudio",
            "translation.translate(en->zh-Hant-TW)", "synthesis.speak(zh-TW)",
        ])
        XCTAssertEqual(h.vm.entries.count, 1)
        XCTAssertEqual(h.vm.entries[0].speaker, .partner)
        XCTAssertEqual(h.vm.entries[0].direction, .partnerToChinese(.english))
        XCTAssertEqual(h.vm.entries[0].original, "Where is the station?")
        XCTAssertEqual(h.vm.entries[0].translation, "[zh-Hant-TW] Where is the station?")
    }

    func testSilenceShorterThanTimeoutKeepsListening() async {
        let h = Harness()
        h.vm.partnerButtonTapped()
        await waitUntil("partial") { h.vm.partialTranscript == "Where is the station" }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .milliseconds(1100))
        for _ in 0..<1000 { await Task.yield() }
        XCTAssertEqual(h.vm.state, .listeningToPartner)
        XCTAssertEqual(h.log.count(of: "recognition.finishAudio"), 0)
    }

    func testNewPartialResetsSilenceTimer() async {
        let h = Harness()
        h.vm.partnerButtonTapped()
        await waitUntil("partial") { h.vm.partialTranscript == "Where is the station" }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .milliseconds(1000))
        h.recognition.emit(.partial("Where is the station please"))
        await waitUntil("new partial") { h.vm.partialTranscript == "Where is the station please" }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .milliseconds(1000))   // 距最新結果只有 1.0 秒
        for _ in 0..<1000 { await Task.yield() }
        XCTAssertEqual(h.vm.state, .listeningToPartner)
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .milliseconds(200))
        await waitUntil("transcribing or later") { h.vm.state != .listeningToPartner }
        XCTAssertEqual(h.log.count(of: "recognition.finishAudio"), 1)
    }

    func testPartialTranscriptIsPublished() async {
        let h = Harness()
        h.vm.partnerButtonTapped()
        await waitUntil("partial") { h.vm.partialTranscript == "Where is the station" }
        XCTAssertEqual(h.vm.state, .listeningToPartner)
        XCTAssertTrue(h.vm.state.isMicrophoneActive)
    }

    func testEmptyTranscriptSkipsTranslation() async {
        let h = Harness(script: [.final("  ")])
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner }
        h.vm.partnerButtonTapped()
        await waitUntil("idle") { h.vm.state == .idle }
        XCTAssertFalse(h.log.entries.contains { $0.hasPrefix("translation.") })
        XCTAssertEqual(h.vm.notice, "沒有聽到內容，請再說一次。")
        XCTAssertTrue(h.vm.entries.isEmpty)
    }

    func testRecognitionFailureShowsError() async {
        let h = Harness(recognitionError: AppError.recognizerUnavailable(localeID: "en-US"))
        h.vm.partnerButtonTapped()
        await waitUntil("error") { h.vm.state == .error(.recognizerUnavailable(localeID: "en-US")) }
        XCTAssertFalse(h.log.entries.contains { $0.hasPrefix("translation.") })
        XCTAssertEqual(h.vm.lastError, .recognizerUnavailable(localeID: "en-US"))
        XCTAssertFalse(h.recognition.isListening)
    }

    func testTranslationFailureShowsRetry() async {
        let h = Harness(translateError: AppError.translationFailed)
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner && !h.vm.partialTranscript.isEmpty }
        h.vm.partnerButtonTapped()
        await waitUntil("error") { h.vm.state == .error(.translationFailed) }
        XCTAssertEqual(h.vm.lastError?.recovery, .retry)
        XCTAssertFalse(h.log.entries.contains { $0.hasPrefix("synthesis.") })
        h.vm.recover()
        XCTAssertEqual(h.vm.state, .idle)
        XCTAssertNil(h.vm.lastError)
    }

    func testSynthesisCancelledReturnsToIdle() async {
        let h = Harness()
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner && !h.vm.partialTranscript.isEmpty }
        h.vm.partnerButtonTapped()
        await waitUntil("speaking") { h.vm.state == .speakingChinese && h.synthesis.isSpeaking }
        h.synthesis.failCurrent(CancellationError())
        await waitUntil("idle") { h.vm.state == .idle }
        XCTAssertEqual(h.vm.entries.count, 1, "播放被取消，對話紀錄仍保留")
    }

    func testSynthesisFailureShowsError() async {
        struct SynthesisBroke: Error {}
        let h = Harness()
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner && !h.vm.partialTranscript.isEmpty }
        h.vm.partnerButtonTapped()
        await waitUntil("speaking") { h.vm.state == .speakingChinese && h.synthesis.isSpeaking }
        h.synthesis.failCurrent(SynthesisBroke())
        await waitUntil("error") { h.vm.state == .error(.synthesisInterrupted) }
    }

    func testSecondTapEndsUtteranceEarly() async {
        let h = Harness()
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner && !h.vm.partialTranscript.isEmpty }
        h.vm.partnerButtonTapped()
        await waitUntil("speaking") { h.vm.state == .speakingChinese }
        XCTAssertEqual(h.log.count(of: "recognition.finishAudio"), 1)
        XCTAssertEqual(h.log.count(of: "recognition.start(en-US)"), 1)
    }

    func testMicrophoneStoppedBeforeSpeaking() async {
        let h = Harness()
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner && !h.vm.partialTranscript.isEmpty }
        h.vm.partnerButtonTapped()
        await waitUntil("speaking") { h.vm.state == .speakingChinese && h.synthesis.isSpeaking }
        XCTAssertFalse(h.recognition.isListening)
        XCTAssertFalse(h.vm.state.isMicrophoneActive)
        let entries = h.log.entries
        let stopIndex = entries.firstIndex { $0 == "recognition.finishAudio" || $0 == "recognition.cancel" }
        let speakIndex = entries.firstIndex { $0.hasPrefix("synthesis.speak") }
        XCTAssertNotNil(stopIndex)
        XCTAssertNotNil(speakIndex)
        if let stopIndex, let speakIndex { XCTAssertLessThan(stopIndex, speakIndex) }
    }

    func testMissingFinalResultFallsBackToLastPartial() async {
        let h = Harness(sendsFinal: false)
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner && h.vm.partialTranscript == "Where is the station" }
        h.vm.partnerButtonTapped()
        await waitUntil("transcribing") { h.vm.state == .transcribingPartner }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .seconds(2))
        await waitUntil("speaking") { h.vm.state == .speakingChinese }
        XCTAssertEqual(h.vm.entries.last?.original, "Where is the station")
        XCTAssertFalse(h.recognition.isListening, "逾時後要關掉麥克風")
    }

    func testServerRecognitionShowsNotice() async {
        let h = Harness(recognitionMode: .server)
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner }
        XCTAssertEqual(h.vm.notice, "此語言的語音辨識需要網路（由 Apple 處理）")
    }

    func testUnavailableRecognizerShowsError() async {
        let h = Harness(recognitionMode: .unavailable)
        h.vm.partnerButtonTapped()
        await waitUntil("error") { h.vm.state == .error(.recognizerUnavailable(localeID: "en-US")) }
        XCTAssertEqual(h.log.count(of: "recognition.start(en-US)"), 0)
    }

    func testUsesSelectedPartnerLanguage() async {
        let h = Harness()
        h.vm.partnerLanguage = .japanese
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner }
        XCTAssertTrue(h.log.entries.contains("recognition.start(ja-JP)"))
    }

    func testClearHistoryEmptiesEntriesInOrder() async {
        let h = Harness()
        await h.runPartnerTurn()
        await h.runPartnerTurn()
        XCTAssertEqual(h.vm.entries.count, 2)
        XCTAssertLessThan(h.vm.entries[0].timestamp, h.vm.entries[1].timestamp)
        h.vm.clearHistory()
        XCTAssertTrue(h.vm.entries.isEmpty)
    }

    func testReplayPartnerEntrySpeaksChineseAgain() async {
        let h = Harness()
        await h.runPartnerTurn()
        let id = h.vm.entries[0].id
        h.vm.replay(id)
        await waitUntil("speaking") { h.vm.state == .speakingChinese && h.synthesis.isSpeaking }
        h.synthesis.completeCurrent()
        await waitUntil("idle") { h.vm.state == .idle }
        XCTAssertEqual(h.log.count(of: "synthesis.speak(zh-TW)"), 2)
        XCTAssertEqual(h.log.count(of: "recognition.start(en-US)"), 1, "重播不會開麥克風")
    }
}
