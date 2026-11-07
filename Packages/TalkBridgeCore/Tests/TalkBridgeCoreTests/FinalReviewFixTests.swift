import XCTest
@testable import TalkBridgeCore
import TalkBridgeFakes

/// 整體審查找到的問題：每一項先有會失敗的測試，再修。
@MainActor
final class FinalReviewFixTests: XCTestCase {
    /// 審查 #5：翻成中文途中耳機斷線，中文不能接著從手機喇叭大聲播出。
    func testHeadsetDisconnectWhileTranslatingToChineseStops() async {
        let bluetooth = AudioRouteInfo(kind: .bluetooth, portName: "Sample Buds")
        let h = Harness(holdTranslations: true, route: bluetooth)
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner && !h.vm.partialTranscript.isEmpty }
        h.vm.partnerButtonTapped()
        await waitUntil("translating") { h.vm.state == .translatingToChinese }
        h.vm.handleAudioEvent(.routeChanged(AudioRouteInfo(kind: .speaker, portName: "Speaker"), oldDeviceUnavailable: true))
        XCTAssertEqual(h.vm.state, .error(.headsetDisconnected))
        h.translation.releaseTranslations()
        for _ in 0..<1000 { await Task.yield() }
        XCTAssertFalse(h.log.entries.contains { $0.hasPrefix("synthesis.speak") })
    }

    /// 審查 #5：收音一律用 iPhone 麥克風，聆聽中耳機斷線不必丟掉對方正在說的話。
    func testHeadsetDisconnectWhileListeningKeepsListening() async {
        let bluetooth = AudioRouteInfo(kind: .bluetooth, portName: "Sample Buds")
        let h = Harness(route: bluetooth)
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner && !h.vm.partialTranscript.isEmpty }
        h.vm.handleAudioEvent(.routeChanged(AudioRouteInfo(kind: .speaker, portName: "Speaker"), oldDeviceUnavailable: true))
        XCTAssertEqual(h.vm.state, .listeningToPartner)
        XCTAssertEqual(h.vm.route.kind, .speaker)
        XCTAssertTrue(h.recognition.isListening)
    }

    /// 審查 #6：語言模型未準備時換語言，不能還記著舊語言去下載。
    func testChangingLanguageClearsPendingDownload() async {
        let h = Harness(readiness: .needsDownload)
        h.vm.partnerButtonTapped()
        await waitUntil("not ready") { h.vm.state == .languageNotReady }
        h.vm.partnerLanguage = .thai
        XCTAssertEqual(h.vm.state, .idle)
        XCTAssertNil(h.vm.lastError)
        h.vm.recover()
        for _ in 0..<500 { await Task.yield() }
        XCTAssertFalse(h.log.entries.contains("translation.prepare"))
    }

    /// 審查 #2：翻譯一直沒回來時，不能永遠停在「正在翻譯」。
    func testTranslationTimeoutShowsRetry() async {
        let h = Harness(holdTranslations: true)
        h.vm.partnerButtonTapped()
        await waitUntil("listening") { h.vm.state == .listeningToPartner && !h.vm.partialTranscript.isEmpty }
        h.vm.partnerButtonTapped()
        await waitUntil("translating") { h.vm.state == .translatingToChinese }
        await h.sleeper.waitForPendingCount(1)
        h.sleeper.advance(by: .seconds(20))
        await waitUntil("timeout error") { h.vm.state == .error(.translationFailed) }
        XCTAssertEqual(h.vm.lastError?.recovery, .retry)
        h.translation.releaseTranslations()
        for _ in 0..<1000 { await Task.yield() }
        XCTAssertTrue(h.vm.entries.isEmpty, "逾時後才回來的結果要丟掉")
    }

    func testTranslationTimeoutIsConfigurable() async {
        XCTAssertEqual(ConversationConfiguration.standard.translationTimeout, .seconds(20))
    }
}
