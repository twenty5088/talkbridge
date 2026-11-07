/// 判斷「一句話說完了沒」（原需求 §五 C）。純函式，時間由呼叫端提供，方便測試。
public struct UtteranceEndDetector: Sendable {
    public enum Decision: Equatable, Sendable {
        case keepListening
        /// 有說話後停頓超過 silenceTimeout。
        case endBySilence
        /// 超過單句最長時間，先翻譯這一段。
        case endByMaxDuration
        /// 開始聆聽後一直沒有任何辨識結果。
        case endByNoSpeech
    }

    private let configuration: ConversationConfiguration
    /// 實際使用的停頓秒數：設定檔有固定值就用它，否則用使用者設定。
    public let silenceTimeout: Duration
    /// 開始聆聽後一直沒有任何辨識結果的等待上限。
    public let noSpeechTimeout: Duration

    public init(configuration: ConversationConfiguration, userPause: Duration = AppSettings().pauseDuration,
                noSpeechTimeout: Duration? = nil) {
        self.configuration = configuration
        self.silenceTimeout = configuration.silenceTimeout ?? userPause
        self.noSpeechTimeout = noSpeechTimeout ?? configuration.autoTurnIdleTimeout
    }

    /// - Parameters:
    ///   - elapsed: 從開始聆聽算起的時間。
    ///   - sinceLastPartial: 距離最後一次「文字有變」的部分結果；還沒有任何結果時為 nil。
    public func evaluate(elapsed: Duration, sinceLastPartial: Duration?) -> Decision {
        if let sinceLastPartial {
            // 單句最長時間只在有人開始說話後才算（自動輪流可以安靜等 60 秒，不能先被 30 秒切掉）。
            if elapsed >= configuration.maxUtteranceDuration {
                return .endByMaxDuration
            }
            return sinceLastPartial >= silenceTimeout ? .endBySilence : .keepListening
        }
        return elapsed >= noSpeechTimeout ? .endByNoSpeech : .keepListening
    }

    /// 去掉空白與標點後，字母或數字至少要有 minimumMeaningfulCharacters 個。
    public static func isMeaningful(_ transcript: String, configuration: ConversationConfiguration) -> Bool {
        let count = transcript.reduce(into: 0) { count, character in
            if character.isLetter || character.isNumber { count += 1 }
        }
        return count >= max(1, configuration.minimumMeaningfulCharacters)
    }
}
