import XCTest
@testable import TalkBridgeCore
import TalkBridgeFakes

@MainActor
final class ConversationViewModelModeBTests: XCTestCase {
    private let chineseScript: [String: [RecognitionUpdate]] = [
        "zh-TW": [.partial("請問車站"), .final("請問車站在哪裡？")],
    ]
    private let speakerOverrideFailureNotice = "外語仍從耳機播出，請改用「給對方看」或在設定改成一律用手機喇叭。"

    private func makeHarness(route: AudioRouteInfo = AudioRouteInfo(kind: .speaker, portName: "Speaker"),
                             speakerOverrideResult: AudioRouteInfo? = nil,
                             voiceMatch: VoiceMatch = .exact,
                             settings: AppSettings = AppSettings()) -> Harness {
        Harness(scriptsByLocale: chineseScript, voiceMatch: voiceMatch, route: route,
                speakerOverrideResult: speakerOverrideResult, settings: settings)
    }

    /// 太太說一句中文，等到翻譯完成、進入待播。
    private func speakChinese(_ h: Harness) async {
        h.vm.userButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToUser && h.vm.partialTranscript == "請問車站" }
        h.vm.userButtonTapped()
        await waitUntil("ready") {
            if case .readyToPlayForPartner = h.vm.state { return true }
            return false
        }
    }

    func testModeBCountdownAutoPlays() async {
        let h = makeHarness()
        await speakChinese(h)
        XCTAssertEqual(h.vm.state, .readyToPlayForPartner(countdown: 2))
        XCTAssertEqual(h.vm.countdownRemaining, 2)
        XCTAssertEqual(h.vm.editableTranslation, "[en] 請問車站在哪裡？")
        XCTAssertTrue(h.vm.entries.isEmpty, "還沒播放前不加入紀錄")
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .seconds(1))
        await waitUntil("countdown 1") { h.vm.state == .readyToPlayForPartner(countdown: 1) }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .seconds(1))
        await waitUntil("speaking") { h.vm.state == .speakingPartnerLanguage && h.synthesis.isSpeaking }
        XCTAssertTrue(h.log.entries.contains("synthesis.speak(en-US)"))
        XCTAssertEqual(h.vm.entries.last?.speaker, .user)
        XCTAssertEqual(h.vm.entries.last?.original, "請問車站在哪裡？")
        h.synthesis.completeCurrent()
        await waitUntil("idle") { h.vm.state == .idle }
        XCTAssertEqual(h.vm.entries.count, 1)
    }

    func testCancelCountdownWaitsForTap() async {
        let h = makeHarness()
        await speakChinese(h)
        h.vm.cancelCountdown()
        XCTAssertEqual(h.vm.state, .readyToPlayForPartner(countdown: nil))
        XCTAssertNil(h.vm.countdownRemaining)
        h.sleeper.advance(by: .seconds(5))
        for _ in 0..<1000 { await Task.yield() }
        XCTAssertEqual(h.vm.state, .readyToPlayForPartner(countdown: nil))
        XCTAssertFalse(h.log.entries.contains { $0.hasPrefix("synthesis.speak") })
        h.vm.playForPartner()
        await waitUntil("speaking") { h.vm.state == .speakingPartnerLanguage }
    }

    func testConfirmBeforePlaySetting() async {
        var settings = AppSettings()
        settings.confirmBeforePlay = true
        let h = makeHarness(settings: settings)
        await speakChinese(h)
        XCTAssertEqual(h.vm.state, .readyToPlayForPartner(countdown: nil))
        XCTAssertEqual(h.sleeper.pendingCount, 0)
    }

    func testEditedTranslationIsSpokenAndStored() async {
        let h = makeHarness()
        await speakChinese(h)
        h.vm.beginEditing()
        XCTAssertTrue(h.vm.isEditing)
        XCTAssertEqual(h.vm.state, .readyToPlayForPartner(countdown: nil))
        h.vm.editableTranslation = "Where is the station, please?"
        h.vm.playForPartner()
        await waitUntil("speaking") { h.vm.state == .speakingPartnerLanguage }
        XCTAssertFalse(h.vm.isEditing)
        XCTAssertEqual(h.vm.entries.last?.translation, "Where is the station, please?")
    }

    func testStopAndReplay() async {
        let h = makeHarness()
        await speakChinese(h)
        h.vm.playForPartner()
        await waitUntil("speaking") { h.vm.state == .speakingPartnerLanguage && h.synthesis.isSpeaking }
        h.vm.stopPlayback()
        XCTAssertEqual(h.vm.state, .readyToPlayForPartner(countdown: nil))
        XCTAssertTrue(h.log.entries.contains("synthesis.stop"))
        h.vm.replayLastForPartner()
        await waitUntil("speaking again") { h.vm.state == .speakingPartnerLanguage && h.synthesis.isSpeaking }
        XCTAssertEqual(h.log.count(of: "synthesis.speak(en-US)"), 2)
        XCTAssertEqual(h.vm.entries.count, 1, "重播不會重複新增紀錄")
    }

    func testRerecordDiscardsPending() async {
        let h = makeHarness()
        await speakChinese(h)
        h.vm.rerecord()
        await waitUntil("listening again") { h.vm.state == .listeningToUser }
        XCTAssertTrue(h.vm.entries.isEmpty)
        XCTAssertEqual(h.log.count(of: "recognition.start(zh-TW)"), 2)
    }

    func testSpeakerOverrideWithHeadset() async {
        let bluetooth = AudioRouteInfo(kind: .bluetooth, portName: "Sample Buds")
        let h = makeHarness(route: bluetooth)
        await speakChinese(h)
        h.vm.playForPartner()
        await waitUntil("speaking") { h.vm.state == .speakingPartnerLanguage && h.synthesis.isSpeaking }
        XCTAssertEqual(h.vm.route.kind, .speaker)
        h.synthesis.completeCurrent()
        await waitUntil("idle") { h.vm.state == .idle }
        let entries = h.log.entries
        let overrideIndex = entries.firstIndex(of: "audio.setOutput(speaker)")
        let speakIndex = entries.firstIndex(of: "synthesis.speak(en-US)")
        let restoreIndex = entries.firstIndex(of: "audio.setOutput(systemDefault)")
        XCTAssertNotNil(overrideIndex)
        XCTAssertNotNil(restoreIndex)
        if let overrideIndex, let speakIndex, let restoreIndex {
            XCTAssertLessThan(overrideIndex, speakIndex)
            XCTAssertLessThan(speakIndex, restoreIndex)
        }
        XCTAssertEqual(h.vm.route, bluetooth)
        XCTAssertNil(h.vm.notice)
    }

    func testSpeakerOverrideFailureShowsNotice() async {
        let bluetooth = AudioRouteInfo(kind: .bluetooth, portName: "Sample Buds")
        let h = makeHarness(route: bluetooth, speakerOverrideResult: bluetooth)
        await speakChinese(h)
        h.vm.playForPartner()
        await waitUntil("speaking") { h.vm.state == .speakingPartnerLanguage }
        XCTAssertEqual(h.vm.notice, speakerOverrideFailureNotice)
        XCTAssertEqual(h.vm.route.kind, .bluetooth, "畫面要顯示實際路由")
    }

    func testChinesePlaybackStaysOnHeadsetInAutomaticMode() async {
        let bluetooth = AudioRouteInfo(kind: .bluetooth, portName: "Sample Buds")
        let h = Harness(route: bluetooth)
        await h.runPartnerTurn()
        XCTAssertFalse(h.log.entries.contains { $0.hasPrefix("audio.setOutput") }, "中文給太太聽，維持耳機")
    }

    func testAlwaysSpeakerPreferenceOverridesChineseToo() async {
        var settings = AppSettings()
        settings.outputPreference = .alwaysSpeaker
        let bluetooth = AudioRouteInfo(kind: .bluetooth, portName: "Sample Buds")
        let h = Harness(route: bluetooth, settings: settings)
        await h.runPartnerTurn()
        XCTAssertTrue(h.log.entries.contains("audio.setOutput(speaker)"))
    }

    func testAlwaysSpeakerPreferenceSkipsOverrideWhenAlreadySpeaker() async {
        var settings = AppSettings()
        settings.outputPreference = .alwaysSpeaker
        let h = makeHarness(settings: settings)
        await speakChinese(h)
        h.vm.playForPartner()
        await waitUntil("speaking") { h.vm.state == .speakingPartnerLanguage }
        XCTAssertFalse(h.log.entries.contains { $0.hasPrefix("audio.setOutput") })
    }

    func testVoiceFallbackNotice() async {
        let h = makeHarness(voiceMatch: .fallback(actualLanguageID: "en-GB"))
        await speakChinese(h)
        h.vm.playForPartner()
        await waitUntil("speaking") { h.vm.state == .speakingPartnerLanguage }
        XCTAssertEqual(h.vm.notice, "找不到 en-US 的標準語音，改用 en-GB。")
    }

    func testMissingVoiceShowsTextOnly() async {
        let h = makeHarness(voiceMatch: .none)
        await speakChinese(h)
        h.vm.playForPartner()
        await waitUntil("back to ready") { h.vm.state == .readyToPlayForPartner(countdown: nil) && h.vm.notice != nil }
        XCTAssertEqual(h.vm.notice, "這台 iPhone 沒有 en-US 的語音，請讓對方看畫面上的文字。")
        XCTAssertFalse(h.log.entries.contains { $0.hasPrefix("synthesis.speak") })
    }

    func testNoMicWhileSpeakingPartnerLanguage() async {
        let h = makeHarness()
        await speakChinese(h)
        h.vm.playForPartner()
        await waitUntil("speaking") { h.vm.state == .speakingPartnerLanguage && h.synthesis.isSpeaking }
        // v2：播放中按按鈕不中斷播放，只記住下一句；播放中絕不開麥克風。
        h.vm.partnerButtonTapped()
        XCTAssertEqual(h.vm.state, .speakingPartnerLanguage)
        for _ in 0..<500 { await Task.yield() }
        XCTAssertEqual(h.log.count(of: "recognition.start(en-US)"), 0, "播放中不開麥克風")
        h.synthesis.completeCurrent()
        await waitUntil("idle") { h.vm.state == .idle }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .milliseconds(300))
        await waitUntil("listening partner") { h.vm.state == .listeningToPartner }
        XCTAssertEqual(h.log.count(of: "recognition.start(zh-TW)"), 1)
        XCTAssertEqual(h.log.count(of: "recognition.start(en-US)"), 1)
        let speakIndex = h.log.entries.firstIndex(of: "synthesis.speak(en-US)")
        let startIndex = h.log.entries.firstIndex(of: "recognition.start(en-US)")
        XCTAssertNotNil(speakIndex)
        if let speakIndex, let startIndex { XCTAssertLessThan(speakIndex, startIndex) }
    }
}
