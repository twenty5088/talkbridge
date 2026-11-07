import AVFoundation
import TalkBridgeCore

/// AVSpeechSynthesizer 的正式實作。speak 播完才回來；stop 或 Task 取消時丟出 CancellationError。
///
/// 每一句用 ObjectIdentifier 對應自己的 continuation，避免「上一句被停止的回呼」晚到時誤結束新的一句。
@MainActor
final class AppleSpeechSynthesisService: NSObject, SpeechSynthesisService, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var current: (id: ObjectIdentifier, continuation: CheckedContinuation<Void, Error>)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func voiceMatch(forLanguageID languageID: String) -> VoiceMatch {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        if voices.contains(where: { $0.language == languageID }) {
            return .exact
        }
        if let fallback = Self.closestVoice(to: languageID, in: voices) {
            return .fallback(actualLanguageID: fallback.language)
        }
        return .none
    }

    func speak(_ text: String, languageID: String) async throws {
        try Task.checkCancellation()
        finishCurrent(with: .failure(CancellationError()))
        let utterance = AVSpeechUtterance(string: text)
        let voices = AVSpeechSynthesisVoice.speechVoices()
        utterance.voice = voices.first(where: { $0.language == languageID }) ?? Self.closestVoice(to: languageID, in: voices)
        let id = ObjectIdentifier(utterance)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                current = (id, continuation)
                synthesizer.speak(utterance)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.stop() }
        }
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        finishCurrent(with: .failure(CancellationError()))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finish(id: id, with: .success(())) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finish(id: id, with: .failure(CancellationError())) }
    }

    private func finish(id: ObjectIdentifier, with result: Result<Void, Error>) {
        guard let current, current.id == id else { return }
        finishCurrent(with: result)
    }

    private func finishCurrent(with result: Result<Void, Error>) {
        guard let current else { return }
        self.current = nil
        current.continuation.resume(with: result)
    }

    /// 同語言（例如 en-US 找不到時用 en-GB）中第一個可用的語音。
    private static func closestVoice(to languageID: String, in voices: [AVSpeechSynthesisVoice]) -> AVSpeechSynthesisVoice? {
        guard let language = languageID.split(separator: "-").first.map(String.init) else { return nil }
        return voices.first { $0.language == language || $0.language.hasPrefix(language + "-") }
    }
}
