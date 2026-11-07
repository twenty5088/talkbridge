import Synchronization
import TalkBridgeCore

/// 決定性的假翻譯：結果固定為 "[<target>] <原文>"。
public final class FakeTranslationService: TranslationService, Sendable {
    private struct State {
        var readiness: TranslationReadiness
        var prepareError: (any Error & Sendable)?
        var translateError: (any Error & Sendable)?
    }

    private let log: CallLog
    private let state: Mutex<State>

    public init(log: CallLog, readiness: TranslationReadiness = .installed,
                prepareError: (any Error & Sendable)? = nil, translateError: (any Error & Sendable)? = nil) {
        self.log = log
        self.state = Mutex(State(readiness: readiness, prepareError: prepareError, translateError: translateError))
    }

    public func setTranslateError(_ error: (any Error & Sendable)?) { state.withLock { $0.translateError = error } }
    public func setReadiness(_ readiness: TranslationReadiness) { state.withLock { $0.readiness = readiness } }

    public func readiness(source: String, target: String) async -> TranslationReadiness {
        state.withLock { $0.readiness }
    }

    public func prepare(source: String, target: String) async throws {
        log.record("translation.prepare")
        let error = state.withLock { s -> (any Error & Sendable)? in
            if s.prepareError == nil { s.readiness = .installed }
            return s.prepareError
        }
        if let error { throw error }
    }

    public func translate(_ text: String, source: String, target: String) async throws -> String {
        log.record("translation.translate(\(source)->\(target))")
        if let error = state.withLock({ $0.translateError }) { throw error }
        return "[\(target)] \(text)"
    }
}
