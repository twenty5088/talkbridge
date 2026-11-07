import XCTest
@testable import TalkBridgeCore
import TalkBridgeFakes

@MainActor
final class ConversationViewModelRobustnessTests: XCTestCase {
    private func startListeningToPartner(_ h: Harness) async {
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner && !h.vm.partialTranscript.isEmpty }
    }

    private func reachSpeakingChinese(_ h: Harness) async {
        await startListeningToPartner(h)
        h.vm.partnerButtonTapped()
        await waitUntil("speaking") { h.vm.state == .speakingChinese && h.synthesis.isSpeaking }
    }

    func testRapidTapsStartRecognitionOnce() async {
        let h = Harness()
        h.vm.partnerButtonTapped()
        h.vm.partnerButtonTapped()
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner }
        for _ in 0..<500 { await Task.yield() }
        XCTAssertEqual(h.log.count(of: "recognition.start(en-US)"), 1)
        XCTAssertEqual(h.log.count(of: "audio.activate"), 1)
    }

    func testStartingNewTaskCancelsOld() async {
        let h = Harness(scriptsByLocale: ["zh-TW": [.partial("你好"), .final("你好。")]])
        await startListeningToPartner(h)
        h.vm.userButtonTapped()
        await waitUntil("listening user") { h.vm.state == .listeningToUser }
        let entries = h.log.entries
        let cancelIndex = entries.firstIndex(of: "recognition.cancel")
        let startIndex = entries.firstIndex(of: "recognition.start(zh-TW)")
        XCTAssertNotNil(cancelIndex)
        XCTAssertNotNil(startIndex)
        if let cancelIndex, let startIndex { XCTAssertLessThan(cancelIndex, startIndex) }
    }

    func testStopAllWhileListeningClosesMicrophone() async {
        let h = Harness()
        await startListeningToPartner(h)
        h.vm.stopAll()
        XCTAssertEqual(h.vm.state, .idle)
        XCTAssertFalse(h.recognition.isListening)
        XCTAssertTrue(h.log.entries.contains("recognition.cancel"))
    }

    func testStopAllWhileTranslatingDiscardsResult() async {
        let h = Harness(holdTranslations: true)
        await startListeningToPartner(h)
        h.vm.partnerButtonTapped()
        await waitUntil("translating") { h.vm.state == .translatingToChinese }
        h.vm.stopAll()
        XCTAssertEqual(h.vm.state, .idle)
        h.translation.releaseTranslations()
        for _ in 0..<1000 { await Task.yield() }
        XCTAssertTrue(h.vm.entries.isEmpty, "停止後回來的翻譯結果不得加入紀錄")
        XCTAssertFalse(h.log.entries.contains { $0.hasPrefix("synthesis.speak") })
        XCTAssertEqual(h.vm.state, .idle)
    }

    func testStopAllWhileSpeakingStopsSynthesis() async {
        let h = Harness()
        await reachSpeakingChinese(h)
        h.vm.stopAll()
        XCTAssertEqual(h.vm.state, .idle)
        XCTAssertTrue(h.log.entries.contains("synthesis.stop"))
        XCTAssertFalse(h.synthesis.isSpeaking)
    }

    func testSecondTranslationCancelsFirst() async {
        let h = Harness(holdTranslations: true)
        await startListeningToPartner(h)
        h.vm.partnerButtonTapped()
        await waitUntil("translating") { h.vm.state == .translatingToChinese }
        h.vm.userButtonTapped()   // 換人說：取消第一個翻譯
        await waitUntil("listening user") { h.vm.state == .listeningToUser }
        h.translation.releaseTranslations()
        for _ in 0..<1000 { await Task.yield() }
        XCTAssertTrue(h.vm.entries.isEmpty)
        XCTAssertEqual(h.vm.state, .listeningToUser)
    }

    func testMicrophoneDeniedShowsPermissionState() async {
        let h = Harness(permissionSnapshot: PermissionSnapshot(microphone: .denied, speech: .granted))
        h.vm.partnerButtonTapped()
        await waitUntil("needs permission") { h.vm.state == .needsPermission }
        XCTAssertEqual(h.vm.lastError, .microphoneDenied)
        XCTAssertEqual(h.vm.lastError?.recovery, .openSettings)
        XCTAssertFalse(h.log.entries.contains { $0.hasPrefix("recognition.start") })
    }

    func testSpeechDeniedShowsPermissionState() async {
        let h = Harness(permissionSnapshot: PermissionSnapshot(microphone: .granted, speech: .denied))
        h.vm.partnerButtonTapped()
        await waitUntil("needs permission") { h.vm.state == .needsPermission }
        XCTAssertEqual(h.vm.lastError, .speechRecognitionDenied)
    }

    func testPermissionRequestedOnFirstUse() async {
        let h = Harness(permissionSnapshot: PermissionSnapshot(microphone: .notDetermined, speech: .notDetermined),
                        afterRequest: .allGranted)
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner }
        XCTAssertEqual(h.log.entries.first, "permission.request")
    }

    func testUnsupportedLanguage() async {
        let h = Harness(readiness: .unsupported)
        h.vm.partnerButtonTapped()
        await waitUntil("error") { h.vm.state == .error(.languageUnsupported) }
        XCTAssertEqual(h.vm.lastError?.recovery, .chooseAnotherLanguage)
        XCTAssertFalse(h.log.entries.contains { $0.hasPrefix("recognition.start") })
    }

    func testDeclinedModelDownloadShowsNotReady() async {
        let h = Harness(readiness: .needsDownload, prepareError: AppError.modelDownloadCancelled)
        h.vm.partnerButtonTapped()
        await waitUntil("not ready") { h.vm.state == .languageNotReady }
        XCTAssertEqual(h.vm.lastError, .translationModelNotInstalled)
        h.vm.recover()
        await waitUntil("prepare tried") { h.log.entries.contains("translation.prepare") && h.vm.lastError == .modelDownloadCancelled }
        XCTAssertEqual(h.vm.state, .languageNotReady)
    }

    func testAcceptedModelDownloadReturnsToIdle() async {
        let h = Harness(readiness: .needsDownload)
        h.vm.partnerButtonTapped()
        await waitUntil("not ready") { h.vm.state == .languageNotReady }
        h.vm.recover()
        await waitUntil("idle") { h.vm.state == .idle }
        XCTAssertNil(h.vm.lastError)
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner }
    }

    func testChangingLanguageMidUtteranceCancelsWork() async {
        let h = Harness()
        await startListeningToPartner(h)
        h.vm.partnerLanguage = .thai
        XCTAssertEqual(h.vm.state, .idle)
        for _ in 0..<1000 { await Task.yield() }
        XCTAssertFalse(h.log.entries.contains { $0.hasPrefix("translation.") })
        XCTAssertFalse(h.recognition.isListening)
    }

    func testHeadsetDisconnectDuringPlaybackStopsSpeaking() async {
        let bluetooth = AudioRouteInfo(kind: .bluetooth, portName: "Sample Buds")
        let h = Harness(route: bluetooth)
        Task { await h.vm.startObservingAudioEvents() }
        await reachSpeakingChinese(h)
        h.audio.send(.routeChanged(AudioRouteInfo(kind: .speaker, portName: "Speaker"), oldDeviceUnavailable: true))
        await waitUntil("error") { h.vm.state == .error(.headsetDisconnected) }
        XCTAssertTrue(h.log.entries.contains("synthesis.stop"))
        XCTAssertEqual(h.vm.route.kind, .speaker)
    }

    func testRouteChangeWhileIdleOnlyUpdatesRoute() async {
        let h = Harness()
        Task { await h.vm.startObservingAudioEvents() }
        let buds = AudioRouteInfo(kind: .bluetooth, portName: "Sample Buds")
        h.audio.send(.routeChanged(buds, oldDeviceUnavailable: false))
        await waitUntil("route") { h.vm.route == buds }
        XCTAssertEqual(h.vm.state, .idle)
    }

    func testInterruptionStopsWork() async {
        let h = Harness()
        Task { await h.vm.startObservingAudioEvents() }
        await startListeningToPartner(h)
        h.audio.send(.interruptionBegan)
        await waitUntil("error") { h.vm.state == .error(.audioInterrupted) }
        XCTAssertFalse(h.recognition.isListening)
    }

    func testMediaServicesResetStopsWork() async {
        let h = Harness()
        await startListeningToPartner(h)
        h.vm.handleAudioEvent(.mediaServicesReset)
        XCTAssertEqual(h.vm.state, .error(.audioSessionFailed))
        XCTAssertFalse(h.recognition.isListening)
    }

    func testBackgroundStopsWork() async {
        let h = Harness()
        await startListeningToPartner(h)
        h.vm.appDidEnterBackground()
        XCTAssertEqual(h.vm.state, .error(.appBackgrounded))
        XCTAssertFalse(h.recognition.isListening)
    }

    func testBackgroundWhileIdleStaysIdle() {
        let h = Harness()
        h.vm.appDidEnterBackground()
        XCTAssertEqual(h.vm.state, .idle)
    }

    func testAudioActivationFailure() async {
        let h = Harness()
        h.audio.activateError = .audioSessionFailed
        h.vm.partnerButtonTapped()
        await waitUntil("error") { h.vm.state == .error(.audioSessionFailed) }
        XCTAssertFalse(h.log.entries.contains { $0.hasPrefix("recognition.start") })
    }

    func testMaxDurationTranslatesSegment() async {
        var configuration = ConversationConfiguration.standard
        configuration.silenceTimeout = .seconds(60)   // 讓停頓不會先觸發
        let h = Harness(configuration: configuration)
        await startListeningToPartner(h)
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .seconds(30))
        await waitUntil("speaking") { h.vm.state == .speakingChinese }
        XCTAssertEqual(h.log.count(of: "recognition.finishAudio"), 1)
        XCTAssertEqual(h.vm.notice, "已達單句最長 30 秒，先翻譯這一段。")
        XCTAssertEqual(h.vm.entries.count, 1)
    }

    func testNoSpeechTimeoutReturnsToIdle() async {
        let h = Harness(script: [])
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .seconds(15))
        await waitUntil("idle") { h.vm.state == .idle }
        XCTAssertFalse(h.recognition.isListening)
        XCTAssertEqual(h.vm.notice, AppError.noSpeechDetected.userMessage)
    }
}
