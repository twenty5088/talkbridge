import XCTest
@testable import TalkBridgeCore
import TalkBridgeFakes

final class FakesTests: XCTestCase {
    func testFakeRecognitionEmitsPartialsThenFinal() async throws {
        let log = CallLog()
        let fake = FakeSpeechRecognitionService(log: log, script: [.partial("Where"), .partial("Where is"), .final("Where is it?")])
        let stream = try fake.start(localeID: "en-US")
        var received: [RecognitionUpdate] = []
        for try await update in stream {
            received.append(update)
            if received.count == 2 { fake.finishAudio() }
        }
        XCTAssertEqual(received, [.partial("Where"), .partial("Where is"), .final("Where is it?")])
        XCTAssertEqual(log.entries, ["recognition.start(en-US)", "recognition.finishAudio"])
    }

    func testFakeRecognitionWithoutFinalKeepsStreamOpen() async throws {
        let fake = FakeSpeechRecognitionService(log: CallLog(), script: [.partial("Hi"), .final("Hi.")], sendsFinal: false)
        let stream = try fake.start(localeID: "en-US")
        var iterator = stream.makeAsyncIterator()
        let first = try await iterator.next()
        XCTAssertEqual(first, .partial("Hi"))
        fake.finishAudio()
        fake.cancel()   // 只有 cancel 才結束串流
        let next = try await iterator.next()
        XCTAssertNil(next)
    }

    func testFakeTranslationIsDeterministic() async throws {
        let log = CallLog()
        let fake = FakeTranslationService(log: log)
        let result = try await fake.translate("Hello", source: "en", target: "zh-Hant-TW")
        XCTAssertEqual(result, "[zh-Hant-TW] Hello")
        XCTAssertEqual(log.entries, ["translation.translate(en->zh-Hant-TW)"])
    }

    func testCallLogRecordsCodesNotContent() async throws {
        let log = CallLog()
        let fake = FakeTranslationService(log: log)
        _ = try await fake.translate("secret sentence", source: "en", target: "zh-Hant-TW")
        XCTAssertFalse(log.entries.joined().contains("secret"))
    }

    func testManualSleeperResumesAfterAdvance() async throws {
        let sleeper = ManualSleeper()
        let done = expectation(description: "slept")
        Task {
            try await sleeper.sleep(for: .seconds(2))
            done.fulfill()
        }
        await sleeper.waitForPendingCount(1)
        sleeper.advance(by: .seconds(1))
        XCTAssertEqual(sleeper.pendingCount, 1)
        sleeper.advance(by: .seconds(1))
        await fulfillment(of: [done], timeout: 5)
        XCTAssertEqual(sleeper.pendingCount, 0)
    }

    @MainActor
    func testFakeSynthesisStopThrowsCancellation() async {
        let log = CallLog()
        let fake = FakeSpeechSynthesisService(log: log)
        let task = Task { @MainActor in
            do {
                try await fake.speak("Hello", languageID: "en-US")
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        while !fake.isSpeaking { await Task.yield() }
        fake.stop()
        let cancelled = await task.value
        XCTAssertTrue(cancelled)
        XCTAssertEqual(log.entries, ["synthesis.speak(en-US)", "synthesis.stop"])
    }

    @MainActor
    func testFakeAudioSpeakerOverrideResult() throws {
        let log = CallLog()
        let bluetooth = AudioRouteInfo(kind: .bluetooth, portName: "Buds")
        let fake = FakeAudioSessionService(log: log, route: bluetooth, speakerOverrideResult: bluetooth)
        XCTAssertEqual(try fake.setOutput(.speaker), bluetooth)
        let normal = FakeAudioSessionService(log: log, route: bluetooth)
        XCTAssertEqual(try normal.setOutput(.speaker).kind, .speaker)
        XCTAssertEqual(try normal.setOutput(.systemDefault), bluetooth)
    }
}
