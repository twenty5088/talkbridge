import TalkBridgeCore

/// 假語音合成：speak 會一直等，直到測試呼叫 completeCurrent()／failCurrent()，或 stop()。
/// UI 測試模式可設定 autoCompleteAfter，讓播放在一段時間後自動結束。
@MainActor
public final class FakeSpeechSynthesisService: SpeechSynthesisService {
    private let log: CallLog
    private let autoCompleteAfter: Duration?
    private let sleeper: any Sleeper
    private var current: CheckedContinuation<Void, Error>?
    private var generation = 0

    public var match: VoiceMatch
    /// 被要求先載入的聲音語言（不寫進 CallLog）。
    public private(set) var warmedLanguages: [String] = []
    /// 有一個 speak 正在等待結束。用 continuation 判斷，避免被停止的上一句晚收尾時誤清旗標。
    public var isSpeaking: Bool { current != nil }

    public init(log: CallLog, match: VoiceMatch = .exact, autoCompleteAfter: Duration? = nil,
                sleeper: any Sleeper = TaskSleeper()) {
        self.log = log
        self.match = match
        self.autoCompleteAfter = autoCompleteAfter
        self.sleeper = sleeper
    }

    public func voiceMatch(forLanguageID languageID: String) -> VoiceMatch { match }

    public func speak(_ text: String, languageID: String) async throws {
        log.record("synthesis.speak(\(languageID))")
        try Task.checkCancellation()
        generation += 1
        let myGeneration = generation
        if let autoCompleteAfter {
            let sleeper = self.sleeper
            Task { @MainActor [weak self] in
                try? await sleeper.sleep(for: autoCompleteAfter)
                guard let self, self.generation == myGeneration else { return }
                self.resume(with: .success(()))
            }
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                current = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.resume(with: .failure(CancellationError())) }
        }
    }

    public func warmUp(languageID: String) {
        warmedLanguages.append(languageID)
    }

    public func stop() {
        log.record("synthesis.stop")
        resume(with: .failure(CancellationError()))
    }

    public func completeCurrent() {
        resume(with: .success(()))
    }

    public func failCurrent(_ error: Error) {
        resume(with: .failure(error))
    }

    private func resume(with result: Result<Void, Error>) {
        guard let continuation = current else { return }
        current = nil
        continuation.resume(with: result)
    }
}
