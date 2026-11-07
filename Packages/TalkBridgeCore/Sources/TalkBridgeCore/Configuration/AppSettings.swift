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

    public init() {}
}
