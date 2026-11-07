/// 外語要從哪裡播出。
public enum OutputPreference: String, Sendable, CaseIterable, Codable {
    /// 有耳機時：中文走耳機，外語暫時改從手機喇叭播出。
    case automatic
    /// 一律用手機喇叭。
    case alwaysSpeaker
}

public enum ConversationMode: String, Sendable, CaseIterable, Codable {
    /// 手動輪流：每句都按按鈕開始。
    case manual
    /// 自動輪流（Beta）：對方與使用者固定交替。
    case autoAlternate
}

/// 使用者偏好。只存偏好，不存任何對話內容。
public struct AppSettings: Equatable, Sendable, Codable {
    public var outputPreference: OutputPreference = .automatic
    /// 開啟時，模式 B 翻譯完不倒數，等使用者按「播放」。
    public var confirmBeforePlay = false
    /// 手動模式下，對方說完、中文播完後繼續聆聽對方（原需求 §五 A-8）。
    public var continueListeningAfterPartner = false
    public var fontScale: Double = 1.0
    public var mode: ConversationMode = .manual
    /// 說完停頓多久才開始翻譯（秒）。Kevin 2026-11-07：預設 2 秒，可在設定調整。
    public var pauseSeconds: Double = 2.0
    /// 使用者自己挑的聲音：語音語言代碼（例如 "en-US"）→ 聲音 identifier。沒有＝自動（品質最好）。
    public var voiceIdentifiers: [String: String] = [:]

    public init() {}

    public var pauseDuration: Duration {
        .milliseconds(Int((pauseSeconds * 1000).rounded()))
    }

    private enum CodingKeys: String, CodingKey {
        case outputPreference, confirmBeforePlay, continueListeningAfterPartner, fontScale, mode, pauseSeconds, voiceIdentifiers
    }

    /// 舊版存下的設定缺少新欄位時用預設值，不讓整份設定解碼失敗而被重置。
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        outputPreference = try c.decodeIfPresent(OutputPreference.self, forKey: .outputPreference) ?? d.outputPreference
        confirmBeforePlay = try c.decodeIfPresent(Bool.self, forKey: .confirmBeforePlay) ?? d.confirmBeforePlay
        continueListeningAfterPartner = try c.decodeIfPresent(Bool.self, forKey: .continueListeningAfterPartner)
            ?? d.continueListeningAfterPartner
        fontScale = try c.decodeIfPresent(Double.self, forKey: .fontScale) ?? d.fontScale
        mode = try c.decodeIfPresent(ConversationMode.self, forKey: .mode) ?? d.mode
        pauseSeconds = try c.decodeIfPresent(Double.self, forKey: .pauseSeconds) ?? d.pauseSeconds
        voiceIdentifiers = try c.decodeIfPresent([String: String].self, forKey: .voiceIdentifiers) ?? d.voiceIdentifiers
    }
}
