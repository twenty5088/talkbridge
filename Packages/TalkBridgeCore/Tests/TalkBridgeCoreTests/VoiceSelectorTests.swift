import XCTest
@testable import TalkBridgeCore

/// Kevin 2026-11-08：下載了「加強版／高品質」聲音後，App 要真的用到它。
final class VoiceSelectorTests: XCTestCase {
    func testPrefersHighestQualityForExactLanguage() {
        let voices = [
            VoiceCandidate(language: "en-US", quality: .standard),
            VoiceCandidate(language: "en-US", quality: .premium),
            VoiceCandidate(language: "en-US", quality: .enhanced),
        ]
        XCTAssertEqual(VoiceSelector.bestIndex(for: "en-US", in: voices), 1)
    }

    func testSkipsNoveltyVoices() {
        let voices = [
            VoiceCandidate(language: "en-US", quality: .standard, isNovelty: true),
            VoiceCandidate(language: "en-US", quality: .standard),
        ]
        XCTAssertEqual(VoiceSelector.bestIndex(for: "en-US", in: voices), 1)
    }

    func testExactLanguageBeatsBetterFallbackRegion() {
        let voices = [
            VoiceCandidate(language: "en-GB", quality: .premium),
            VoiceCandidate(language: "en-US", quality: .standard),
        ]
        XCTAssertEqual(VoiceSelector.bestIndex(for: "en-US", in: voices), 1)
    }

    func testFallbackRegionPicksHighestQuality() {
        let voices = [
            VoiceCandidate(language: "zh-CN", quality: .standard),
            VoiceCandidate(language: "zh-HK", quality: .enhanced),
            VoiceCandidate(language: "ja-JP", quality: .premium),
        ]
        XCTAssertEqual(VoiceSelector.bestIndex(for: "zh-TW", in: voices), 1)
    }

    func testOnlyNoveltyStillUsedRatherThanSilence() {
        let voices = [VoiceCandidate(language: "en-US", quality: .standard, isNovelty: true)]
        XCTAssertEqual(VoiceSelector.bestIndex(for: "en-US", in: voices), 0)
    }

    func testNoMatchingLanguageReturnsNil() {
        let voices = [VoiceCandidate(language: "ja-JP", quality: .premium)]
        XCTAssertNil(VoiceSelector.bestIndex(for: "th-TH", in: voices))
    }
}
