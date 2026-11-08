import Synchronization
import TalkBridgeCore

/// 決定性的假翻譯：結果固定為 "[<target>] <原文>"。
/// holdTranslations 為 true 時，translate 會等到測試呼叫 releaseTranslations() 才回來（用來測試翻譯途中被停止）。
public final class FakeTranslationService: TranslationService, Sendable {
    private struct State {
        var readiness: TranslationReadiness
        var prepareError: (any Error & Sendable)?
        var translateError: (any Error & Sendable)?
        var holdTranslations: Bool
        var translateErrorOnce: Bool
        var held: [CheckedContinuation<Void, Never>] = []
        var warmed: [String] = []
    }

    private let log: CallLog
    private let state: Mutex<State>

    public init(log: CallLog, readiness: TranslationReadiness = .installed,
                prepareError: (any Error & Sendable)? = nil, translateError: (any Error & Sendable)? = nil,
                holdTranslations: Bool = false, translateErrorOnce: Bool = false) {
        self.log = log
        self.state = Mutex(State(readiness: readiness, prepareError: prepareError,
                                 translateError: translateError, holdTranslations: holdTranslations,
                                 translateErrorOnce: translateErrorOnce))
    }

    public func setTranslateError(_ error: (any Error & Sendable)?) { state.withLock { $0.translateError = error } }
    public func setReadiness(_ readiness: TranslationReadiness) { state.withLock { $0.readiness = readiness } }

    /// 放行所有卡住的翻譯，之後的翻譯也不再卡住。
    public func releaseTranslations() {
        let held = state.withLock { s -> [CheckedContinuation<Void, Never>] in
            s.holdTranslations = false
            let held = s.held
            s.held = []
            return held
        }
        for continuation in held { continuation.resume() }
    }

    /// 被要求先暖好的語言對，例如 "en->zh-Hant-TW"（不寫進 CallLog，不影響既有的呼叫順序測試）。
    public var warmedPairs: [String] { state.withLock { $0.warmed } }

    public func warmUp(source: String, target: String) async {
        state.withLock { $0.warmed.append("\(source)->\(target)") }
    }

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
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeNow = state.withLock { s -> Bool in
                guard s.holdTranslations else { return true }
                s.held.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
        // translateErrorOnce：只有第一次失敗（UI 測試「再試一次」要能成功）。
        let error = state.withLock { s -> (any Error & Sendable)? in
            let error = s.translateError
            if s.translateErrorOnce { s.translateError = nil }
            return error
        }
        if let error { throw error }
        return "[\(target)] \(text)"
    }
}
