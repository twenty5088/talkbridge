import Foundation
import XCTest
@testable import TalkBridgeCore
import TalkBridgeFakes

/// 「說完停頓多久才翻譯」可由使用者設定（Kevin 2026-11-07：預設 2 秒、可自行調整）。
@MainActor
final class PauseSettingTests: XCTestCase {
    func testDefaultPauseIsTwoSeconds() async {
        XCTAssertEqual(AppSettings().pauseSeconds, 2.0)
        XCTAssertEqual(AppSettings().pauseDuration, .milliseconds(2000))
    }

    func testPauseOptions() async {
        XCTAssertEqual(SettingsViewModel.pauseOptions, [1.2, 1.5, 2.0, 2.5, 3.0, 4.0])
        XCTAssertTrue(SettingsViewModel.pauseOptions.contains(AppSettings().pauseSeconds))
    }

    func testPauseSettingPersistsThroughStore() async {
        let store = InMemorySettingsStore()
        let first = SettingsViewModel(store: store)
        first.settings.pauseSeconds = 3.0
        XCTAssertEqual(SettingsViewModel(store: store).settings.pauseSeconds, 3.0)
    }

    /// 舊版存下的設定沒有 pauseSeconds：要保留其他設定，停頓用預設 2 秒（不能整份設定被重置）。
    func testSettingsSavedByOlderVersionStillDecode() async throws {
        let old = #"{"outputPreference":"alwaysSpeaker","confirmBeforePlay":true,"continueListeningAfterPartner":false,"fontScale":1.5,"mode":"autoAlternate"}"#
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        XCTAssertEqual(settings.outputPreference, .alwaysSpeaker)
        XCTAssertTrue(settings.confirmBeforePlay)
        XCTAssertEqual(settings.fontScale, 1.5)
        XCTAssertEqual(settings.mode, .autoAlternate)
        XCTAssertEqual(settings.pauseSeconds, 2.0)
    }

    func testPauseRoundTripsThroughJSON() async throws {
        var settings = AppSettings()
        settings.pauseSeconds = 4.0
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data), settings)
    }

    func testDetectorUsesUserPauseWhenConfigurationHasNoOverride() async {
        let detector = UtteranceEndDetector(configuration: .standard, userPause: .seconds(3))
        XCTAssertEqual(detector.evaluate(elapsed: .seconds(5), sinceLastPartial: .milliseconds(2990)), .keepListening)
        XCTAssertEqual(detector.evaluate(elapsed: .seconds(5), sinceLastPartial: .seconds(3)), .endBySilence)
    }

    func testConfigurationOverrideWinsOverUserPause() async {
        var configuration = ConversationConfiguration.standard
        configuration.silenceTimeout = .milliseconds(300)
        let detector = UtteranceEndDetector(configuration: configuration, userPause: .seconds(3))
        XCTAssertEqual(detector.evaluate(elapsed: .seconds(1), sinceLastPartial: .milliseconds(300)), .endBySilence)
    }

    func testViewModelWaitsForUserPauseBeforeTranslating() async {
        var settings = AppSettings()
        settings.pauseSeconds = 3.0
        let h = Harness(settings: settings)
        h.vm.partnerButtonTapped()
        await waitUntil("partial") { h.vm.partialTranscript == "Where is the station" }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .milliseconds(2900))
        for _ in 0..<1000 { await Task.yield() }
        XCTAssertEqual(h.vm.state, .listeningToPartner, "停頓 2.9 秒還沒到 3 秒，要繼續聽")
        XCTAssertEqual(h.log.count(of: "recognition.finishAudio"), 0)
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .milliseconds(100))
        await waitUntil("translating or later") { h.vm.state != .listeningToPartner }
        XCTAssertEqual(h.log.count(of: "recognition.finishAudio"), 1)
    }

    func testChangedPauseAppliesToNextUtterance() async {
        let h = Harness()
        var settings = h.vm.settings
        settings.pauseSeconds = 1.5
        h.vm.settings = settings
        h.vm.partnerButtonTapped()
        await waitUntil("partial") { h.vm.partialTranscript == "Where is the station" }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .milliseconds(1500))
        await waitUntil("translating or later") { h.vm.state != .listeningToPartner }
        XCTAssertEqual(h.log.count(of: "recognition.finishAudio"), 1)
    }
}
