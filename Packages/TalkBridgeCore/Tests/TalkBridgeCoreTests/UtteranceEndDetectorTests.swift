import XCTest
@testable import TalkBridgeCore

final class UtteranceEndDetectorTests: XCTestCase {
    private let detector = UtteranceEndDetector(configuration: .standard)

    func testSilenceAfterSpeechEnds() {
        XCTAssertEqual(detector.evaluate(elapsed: .seconds(3), sinceLastPartial: .milliseconds(1990)), .keepListening)
        XCTAssertEqual(detector.evaluate(elapsed: .seconds(3), sinceLastPartial: .milliseconds(2000)), .endBySilence)
    }

    func testMaxDuration() {
        XCTAssertEqual(detector.evaluate(elapsed: .milliseconds(29_900), sinceLastPartial: .zero), .keepListening)
        XCTAssertEqual(detector.evaluate(elapsed: .seconds(30), sinceLastPartial: .zero), .endByMaxDuration)
    }

    func testMaxDurationOnlyCountsAfterSpeechStarts() {
        let detector = UtteranceEndDetector(configuration: .standard, noSpeechTimeout: .seconds(60))
        XCTAssertEqual(detector.evaluate(elapsed: .seconds(45), sinceLastPartial: nil), .keepListening)
        XCTAssertEqual(detector.evaluate(elapsed: .seconds(60), sinceLastPartial: nil), .endByNoSpeech)
    }

    func testNoSpeechTimeout() {
        XCTAssertEqual(detector.evaluate(elapsed: .seconds(14), sinceLastPartial: nil), .keepListening)
        XCTAssertEqual(detector.evaluate(elapsed: .seconds(15), sinceLastPartial: nil), .endByNoSpeech)
    }

    func testWhitespaceAndPunctuationAreNotMeaningful() {
        for text in ["", "   ", "。，?", " ! … "] {
            XCTAssertFalse(UtteranceEndDetector.isMeaningful(text, configuration: .standard), "\(text)")
        }
        for text in ["好", "OK", " 是。", "ครับ"] {
            XCTAssertTrue(UtteranceEndDetector.isMeaningful(text, configuration: .standard), "\(text)")
        }
    }

    func testCustomConfigurationIsRespected() {
        var configuration = ConversationConfiguration.standard
        configuration.silenceTimeout = .milliseconds(500)
        configuration.maxUtteranceDuration = .seconds(10)
        configuration.minimumMeaningfulCharacters = 2
        let custom = UtteranceEndDetector(configuration: configuration)
        XCTAssertEqual(custom.evaluate(elapsed: .seconds(2), sinceLastPartial: .milliseconds(500)), .endBySilence)
        XCTAssertEqual(custom.evaluate(elapsed: .seconds(10), sinceLastPartial: .zero), .endByMaxDuration)
        XCTAssertFalse(UtteranceEndDetector.isMeaningful("好", configuration: configuration))
        XCTAssertTrue(UtteranceEndDetector.isMeaningful("好的", configuration: configuration))
    }
}
