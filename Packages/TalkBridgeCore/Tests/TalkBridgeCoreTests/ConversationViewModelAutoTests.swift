import XCTest
@testable import TalkBridgeCore
import TalkBridgeFakes

@MainActor
final class ConversationViewModelAutoTests: XCTestCase {
    private let scripts: [String: [RecognitionUpdate]] = [
        "en-US": [.partial("Where is it"), .final("Where is it?")],
        "zh-TW": [.partial("在那邊"), .final("在那邊。")],
    ]

    private func makeHarness(mode: ConversationMode = .autoAlternate, confirmBeforePlay: Bool = false,
                             continueListeningAfterPartner: Bool = false,
                             script: [RecognitionUpdate]? = nil) -> Harness {
        var settings = AppSettings()
        settings.mode = mode
        settings.confirmBeforePlay = confirmBeforePlay
        settings.continueListeningAfterPartner = continueListeningAfterPartner
        if let script {
            return Harness(script: script, settings: settings)
        }
        return Harness(scriptsByLocale: scripts, settings: settings)
    }

    /// 對方那一輪：聽 → 說完 → 播完中文。
    private func finishPartnerTurn(_ h: Harness, alreadyListening: Bool = false) async {
        if !alreadyListening { h.vm.partnerButtonTapped() }
        await waitUntil("listening partner") { h.vm.state == .listeningToPartner && !h.vm.partialTranscript.isEmpty }
        h.vm.partnerButtonTapped()
        await waitUntil("speaking chinese") { h.vm.state == .speakingChinese && h.synthesis.isSpeaking }
        h.synthesis.completeCurrent()
        await waitUntil("idle") { h.vm.state == .idle }
    }

    func testAutoAlternatesPartnerThenUser() async {
        let h = makeHarness()
        await finishPartnerTurn(h)
        for _ in 0..<500 { await Task.yield() }
        XCTAssertEqual(h.log.count(of: "recognition.start(zh-TW)"), 0, "保護間隔過之前不開麥克風")
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .milliseconds(300))
        await waitUntil("listening user") { h.vm.state == .listeningToUser }
        XCTAssertEqual(h.vm.currentTurn, .user)
    }

    func testAutoAlternatesUserThenPartner() async {
        let h = makeHarness()
        h.vm.userButtonTapped()
        XCTAssertEqual(h.vm.currentTurn, .user)
        await waitUntil("listening user") { h.vm.state == .listeningToUser && !h.vm.partialTranscript.isEmpty }
        h.vm.userButtonTapped()
        await waitUntil("ready") { h.vm.state == .readyToPlayForPartner(countdown: 2) }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .seconds(1))
        await waitUntil("countdown 1") { h.vm.state == .readyToPlayForPartner(countdown: 1) }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .seconds(1))
        await waitUntil("speaking") { h.vm.state == .speakingPartnerLanguage && h.synthesis.isSpeaking }
        h.synthesis.completeCurrent()
        await waitUntil("idle") { h.vm.state == .idle }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .milliseconds(300))
        await waitUntil("listening partner") { h.vm.state == .listeningToPartner }
        XCTAssertEqual(h.vm.currentTurn, .partner)
    }

    func testAutoIdleTimeoutStops() async {
        let h = makeHarness(script: [])
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .seconds(15))
        await waitUntil("idle") { h.vm.state == .idle }
        XCTAssertNil(h.vm.currentTurn)
        XCTAssertEqual(h.vm.notice, "太久沒有聲音，已暫停自動輪流。")
        XCTAssertFalse(h.recognition.isListening)
    }

    func testConfirmModeWaitsInAuto() async {
        let h = makeHarness(confirmBeforePlay: true)
        h.vm.userButtonTapped()
        await waitUntil("listening user") { h.vm.state == .listeningToUser && !h.vm.partialTranscript.isEmpty }
        h.vm.userButtonTapped()
        await waitUntil("ready") { h.vm.state == .readyToPlayForPartner(countdown: nil) }
        h.sleeper.advance(by: .seconds(60))
        for _ in 0..<1000 { await Task.yield() }
        XCTAssertEqual(h.vm.state, .readyToPlayForPartner(countdown: nil), "等待確認不計入 15 秒上限")
        XCTAssertEqual(h.log.count(of: "recognition.start(en-US)"), 0)
        h.vm.playForPartner()
        await waitUntil("speaking") { h.vm.state == .speakingPartnerLanguage && h.synthesis.isSpeaking }
        h.synthesis.completeCurrent()
        await waitUntil("idle") { h.vm.state == .idle }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .milliseconds(300))
        await waitUntil("listening partner") { h.vm.state == .listeningToPartner }
    }

    func testOtherButtonTakesTurn() async {
        let h = makeHarness()
        h.vm.partnerButtonTapped()
        await waitUntil("listening partner") { h.vm.state == .listeningToPartner }
        h.vm.userButtonTapped()
        await waitUntil("listening user") { h.vm.state == .listeningToUser }
        XCTAssertEqual(h.vm.currentTurn, .user)
    }

    func testStopAllEndsAutoAlternation() async {
        let h = makeHarness()
        await finishPartnerTurn(h)
        h.vm.stopAll()
        XCTAssertNil(h.vm.currentTurn)
        h.sleeper.advance(by: .seconds(1))
        for _ in 0..<1000 { await Task.yield() }
        XCTAssertEqual(h.vm.state, .idle)
        XCTAssertEqual(h.log.count(of: "recognition.start(zh-TW)"), 0)
    }

    func testManualModeDoesNotAutoListen() async {
        let h = makeHarness(mode: .manual)
        await finishPartnerTurn(h)
        h.sleeper.advance(by: .seconds(1))
        for _ in 0..<1000 { await Task.yield() }
        XCTAssertEqual(h.vm.state, .idle)
        XCTAssertNil(h.vm.currentTurn)
        XCTAssertEqual(h.log.count(of: "recognition.start(en-US)"), 1)
    }

    func testContinueListeningAfterPartnerSetting() async {
        let h = makeHarness(mode: .manual, continueListeningAfterPartner: true)
        await finishPartnerTurn(h)
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .milliseconds(300))
        await waitUntil("listening partner again") { h.vm.state == .listeningToPartner }
        XCTAssertEqual(h.log.count(of: "recognition.start(en-US)"), 2)
    }

    func testReplayDoesNotTriggerNextTurn() async {
        let h = makeHarness()
        await finishPartnerTurn(h)
        h.vm.stopAll()
        h.vm.replay(h.vm.entries[0].id)
        await waitUntil("speaking") { h.vm.state == .speakingChinese && h.synthesis.isSpeaking }
        h.synthesis.completeCurrent()
        await waitUntil("idle") { h.vm.state == .idle }
        h.sleeper.advance(by: .seconds(1))
        for _ in 0..<1000 { await Task.yield() }
        XCTAssertEqual(h.log.count(of: "recognition.start(zh-TW)"), 0)
    }
}
