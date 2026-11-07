import Synchronization
import TalkBridgeCore

/// 依腳本送出辨識結果：start 時立刻送出所有 partial，finishAudio 後送出 final 並結束串流。
public final class FakeSpeechRecognitionService: SpeechRecognitionService, Sendable {
    private typealias Continuation = AsyncThrowingStream<RecognitionUpdate, Error>.Continuation

    private struct State {
        var continuation: Continuation?
        var pendingFinals: [RecognitionUpdate] = []
        var mode: RecognitionMode
        var error: (any Error & Sendable)?
    }

    private let log: CallLog
    private let defaultScript: [RecognitionUpdate]
    private let scriptsByLocale: [String: [RecognitionUpdate]]
    private let sendsFinal: Bool
    private let state: Mutex<State>

    public init(log: CallLog, mode: RecognitionMode = .onDevice, script: [RecognitionUpdate] = [],
                scriptsByLocale: [String: [RecognitionUpdate]] = [:],
                error: (any Error & Sendable)? = nil, sendsFinal: Bool = true) {
        self.log = log
        self.defaultScript = script
        self.scriptsByLocale = scriptsByLocale
        self.sendsFinal = sendsFinal
        self.state = Mutex(State(mode: mode, error: error))
    }

    public func setMode(_ mode: RecognitionMode) { state.withLock { $0.mode = mode } }
    public func setError(_ error: (any Error & Sendable)?) { state.withLock { $0.error = error } }

    /// 目前有沒有開著的辨識串流（＝麥克風開著）。
    public var isListening: Bool { state.withLock { $0.continuation != nil } }

    /// 測試用：在聆聽中途再送一個部分結果。
    public func emit(_ update: RecognitionUpdate) {
        let continuation = state.withLock { $0.continuation }
        continuation?.yield(update)
    }

    public func mode(forLocaleID localeID: String) async -> RecognitionMode {
        state.withLock { $0.mode }
    }

    public func start(localeID: String) throws -> AsyncThrowingStream<RecognitionUpdate, Error> {
        log.record("recognition.start(\(localeID))")
        let (stream, continuation) = AsyncThrowingStream<RecognitionUpdate, Error>.makeStream()
        let script = scriptsByLocale[localeID] ?? defaultScript
        if let error = state.withLock({ $0.error }) {
            continuation.finish(throwing: error)
            return stream
        }
        var finals: [RecognitionUpdate] = []
        for update in script {
            switch update {
            case .partial: continuation.yield(update)
            case .final: finals.append(update)
            }
        }
        state.withLock {
            $0.continuation = continuation
            $0.pendingFinals = finals
        }
        return stream
    }

    public func finishAudio() {
        log.record("recognition.finishAudio")
        guard sendsFinal else { return }
        let taken = state.withLock { s -> (Continuation?, [RecognitionUpdate]) in
            let result = (s.continuation, s.pendingFinals)
            s.continuation = nil
            s.pendingFinals = []
            return result
        }
        guard let continuation = taken.0 else { return }
        for update in taken.1 { continuation.yield(update) }
        continuation.finish()
    }

    public func cancel() {
        log.record("recognition.cancel")
        let continuation = state.withLock { s -> Continuation? in
            let c = s.continuation
            s.continuation = nil
            return c
        }
        continuation?.finish()
    }
}
