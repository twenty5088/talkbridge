/// 對話的所有狀態（原需求 §五 的流程）。畫面上的狀態文字與圖示都由這裡產生，不只靠顏色表示。
public enum ConversationState: Equatable, Sendable {
    case idle

    // 模式 A：對方說 → 中文
    case listeningToPartner
    case transcribingPartner
    case translatingToChinese
    case speakingChinese

    // 模式 B：使用者說中文 → 外語
    case listeningToUser
    case transcribingChinese
    case translatingToPartnerLanguage
    /// countdown 為剩餘秒數；nil 表示等使用者按「播放」（確認模式、按了取消倒數或編輯、播放被停止）。
    case readyToPlayForPartner(countdown: Int?)
    case speakingPartnerLanguage

    case needsPermission
    case languageNotReady
    case error(AppError)

    public var statusText: String {
        switch self {
        case .idle: "等待中"
        case .listeningToPartner, .listeningToUser: "正在聆聽"
        case .transcribingPartner, .transcribingChinese: "正在辨識"
        case .translatingToChinese, .translatingToPartnerLanguage: "正在翻譯"
        case .speakingChinese, .speakingPartnerLanguage: "正在播放"
        case .readyToPlayForPartner: "準備播放給對方"
        case .needsPermission: "需要權限"
        case .languageNotReady: "語言模型尚未準備"
        case .error: "發生錯誤"
        }
    }

    /// SF Symbol 名稱，與文字一起顯示。
    public var symbolName: String {
        switch self {
        case .idle: "pause.circle"
        case .listeningToPartner, .listeningToUser: "mic.fill"
        case .transcribingPartner, .transcribingChinese: "text.bubble"
        case .translatingToChinese, .translatingToPartnerLanguage: "character.bubble"
        case .speakingChinese, .speakingPartnerLanguage: "speaker.wave.3.fill"
        case .readyToPlayForPartner: "play.circle"
        case .needsPermission: "lock.shield"
        case .languageNotReady: "arrow.down.circle"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    /// 麥克風只在這兩個狀態開著。
    public var isMicrophoneActive: Bool {
        self == .listeningToPartner || self == .listeningToUser
    }

    public var isSpeaking: Bool {
        self == .speakingChinese || self == .speakingPartnerLanguage
    }

    public var isBusy: Bool {
        switch self {
        case .idle, .needsPermission, .languageNotReady, .error: false
        default: true
        }
    }
}

public struct InvalidTransition: Error, Equatable {
    public let from: ConversationState
    public let to: ConversationState
}

/// 明確的狀態機：所有狀態變化都要經過這裡，不允許的轉換一律拒絕。
///
/// 硬規則：「播放中」不能直接轉到任何「聆聽中」狀態——必須先回到 idle（或待播），
/// 由 ViewModel 在播放確實結束、保護間隔過後才重新開麥克風，避免把自己的播放聲音再辨識一次。
public struct ConversationStateMachine: Sendable {
    public private(set) var state: ConversationState = .idle

    public init() {}

    public static func isAllowed(from: ConversationState, to: ConversationState) -> Bool {
        // 停止、失敗、需要權限、語言未準備：任何狀態都可以進入。
        switch to {
        case .idle, .error, .needsPermission, .languageNotReady:
            return true
        default:
            break
        }

        switch (from, to) {
        // 模式 A
        case (.idle, .listeningToPartner),
             (.listeningToPartner, .transcribingPartner),
             (.transcribingPartner, .translatingToChinese),
             (.translatingToChinese, .speakingChinese):
            return true

        // 模式 B
        case (.idle, .listeningToUser),
             (.readyToPlayForPartner, .listeningToUser),          // 重新錄音
             (.listeningToUser, .transcribingChinese),
             (.transcribingChinese, .translatingToPartnerLanguage),
             (.translatingToPartnerLanguage, .readyToPlayForPartner),
             (.readyToPlayForPartner, .readyToPlayForPartner),    // 倒數變化、取消倒數、編輯
             (.readyToPlayForPartner, .speakingPartnerLanguage),
             (.speakingPartnerLanguage, .readyToPlayForPartner):  // 停止播放後可重播
            return true

        default:
            return false
        }
    }

    public mutating func transition(to next: ConversationState) throws(InvalidTransition) {
        guard Self.isAllowed(from: state, to: next) else {
            throw InvalidTransition(from: state, to: next)
        }
        state = next
    }
}
