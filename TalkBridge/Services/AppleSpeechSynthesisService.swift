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
        guard let voice = Self.bestVoice(for: languageID) else { return .none }
        return voice.language == languageID ? .exact : .fallback(actualLanguageID: voice.language)
    }

    func speak(_ text: String, languageID: String) async throws {
        try Task.checkCancellation()
        finishCurrent(with: .failure(CancellationError()))
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestVoice(for: languageID)
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

    /// 挑品質最好的語音：使用者在「設定 → 輔助使用 → 閱讀與朗讀 → 聲音」下載的高品質／加強版會優先使用；
    /// 找不到該地區時改用同語言其他地區（例如 en-US 找不到時用 en-GB）。規則在 TalkBridgeCore 的 VoiceSelector。
    private static func bestVoice(for languageID: String) -> AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let candidates = voices.map { voice -> VoiceCandidate in
            let quality: VoiceQuality = switch voice.quality {
            case .premium: .premium
            case .enhanced: .enhanced
            default: .standard
            }
            return VoiceCandidate(language: voice.language, quality: quality,
                                  isNovelty: voice.voiceTraits.contains(.isNoveltyVoice))
        }
        return VoiceSelector.bestIndex(for: languageID, in: candidates).map { voices[$0] }
    }
}
