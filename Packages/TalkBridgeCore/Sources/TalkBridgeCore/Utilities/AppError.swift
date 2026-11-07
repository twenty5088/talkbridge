/// 使用者可能遇到的錯誤。錯誤本身不攜帶任何使用者說話內容，訊息只用一般人看得懂的繁體中文。
public enum AppError: Error, Equatable, Sendable {
    case microphoneDenied
    case speechRecognitionDenied
    case recognizerUnavailable(localeID: String)
    case languageUnsupported
    case translationModelNotInstalled
    case modelDownloadCancelled
    case noSpeechDetected
    case emptyTranscript
    case translationFailed
    case synthesisInterrupted
    case audioSessionFailed
    case headsetDisconnected
    case appBackgrounded
    case audioInterrupted
    case maxDurationReached
    case missingDeviceLanguageResources

    public var userMessage: String {
        switch self {
        case .microphoneDenied:
            "沒有麥克風權限，請到「設定」開啟 TalkBridge 的麥克風。"
        case .speechRecognitionDenied:
            "沒有語音辨識權限，請到「設定」開啟 TalkBridge 的語音辨識。"
        case .recognizerUnavailable(let localeID):
            "目前無法辨識這個語言（\(localeID)）。請確認網路連線，或稍後再試。"
        case .languageUnsupported:
            "這台 iPhone 不支援這個語言的翻譯，請換一種語言。"
        case .translationModelNotInstalled:
            "這個語言的翻譯資料還沒下載。按「下載語言」後依畫面指示下載。"
        case .modelDownloadCancelled:
            "翻譯資料沒有下載完成。需要翻譯時，請再按「下載語言」。"
        case .noSpeechDetected:
            "沒有聽到說話聲，請靠近手機再說一次。"
        case .emptyTranscript:
            "沒有辨識出內容，請再說一次。"
        case .translationFailed:
            "翻譯沒有成功，請再試一次。"
        case .synthesisInterrupted:
            "語音播放被中斷了。可以按「重播」再聽一次。"
        case .audioSessionFailed:
            "無法使用麥克風或喇叭，可能有其他 App 正在使用。請關閉其他 App 後再試。"
        case .headsetDisconnected:
            "耳機已斷線，已停止播放。重新連接耳機或改用手機喇叭後再試。"
        case .appBackgrounded:
            "App 切到背景，已停止聆聽與播放。"
        case .audioInterrupted:
            "被來電或其他 App 的聲音打斷，已停止。結束後再按一次開始。"
        case .maxDurationReached:
            "這句話太長了，已先翻譯前面的部分。"
        case .missingDeviceLanguageResources:
            "這台 iPhone 缺少這個語言需要的語音資料。請到「設定」下載後再試。"
        }
    }

    public var recovery: RecoveryAction {
        switch self {
        case .microphoneDenied, .speechRecognitionDenied, .missingDeviceLanguageResources: .openSettings
        case .languageUnsupported: .chooseAnotherLanguage
        case .translationModelNotInstalled, .modelDownloadCancelled: .prepareLanguage
        case .recognizerUnavailable, .noSpeechDetected, .emptyTranscript, .translationFailed,
             .synthesisInterrupted, .audioSessionFailed, .headsetDisconnected, .audioInterrupted:
            .retry
        case .appBackgrounded, .maxDurationReached: .dismiss
        }
    }

    /// 開發用分類，只用於 log 與除錯，不顯示給使用者。
    public var category: String {
        switch self {
        case .microphoneDenied: "permission.microphone"
        case .speechRecognitionDenied: "permission.speech"
        case .recognizerUnavailable: "recognition.unavailable"
        case .languageUnsupported: "translation.unsupported"
        case .translationModelNotInstalled: "translation.notInstalled"
        case .modelDownloadCancelled: "translation.downloadCancelled"
        case .noSpeechDetected: "recognition.noSpeech"
        case .emptyTranscript: "recognition.empty"
        case .translationFailed: "translation.failed"
        case .synthesisInterrupted: "synthesis.interrupted"
        case .audioSessionFailed: "audio.sessionFailed"
        case .headsetDisconnected: "audio.headsetDisconnected"
        case .appBackgrounded: "lifecycle.background"
        case .audioInterrupted: "audio.interrupted"
        case .maxDurationReached: "recognition.maxDuration"
        case .missingDeviceLanguageResources: "device.missingLanguageResources"
        }
    }
}

/// 錯誤畫面上的復原按鈕。
public enum RecoveryAction: Equatable, Sendable {
    case openSettings, retry, prepareLanguage, chooseAnotherLanguage, dismiss

    public var buttonTitle: String {
        switch self {
        case .openSettings: "前往設定"
        case .retry: "再試一次"
        case .prepareLanguage: "下載語言"
        case .chooseAnotherLanguage: "換一種語言"
        case .dismiss: "知道了"
        }
    }
}
