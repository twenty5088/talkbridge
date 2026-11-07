/// App 畫面與 UI 測試共用的 accessibility identifier，避免兩邊各寫一份字串。
public enum AccessibilityID {
    public static let partnerButton = "partnerButton"
    public static let userButton = "userButton"
    public static let stopAllButton = "stopAllButton"
    public static let clearHistoryButton = "clearHistoryButton"
    public static let languagePicker = "languagePicker"
    public static let modePicker = "modePicker"
    public static let statusView = "statusView"
    public static let statusText = "statusText"
    public static let turnIndicator = "turnIndicator"
    public static let routeView = "routeView"
    public static let noticeView = "noticeView"
    public static let playButton = "playButton"
    public static let stopPlaybackButton = "stopPlaybackButton"
    public static let replayButton = "replayButton"
    public static let rerecordButton = "rerecordButton"
    public static let editTranslationButton = "editTranslationButton"
    public static let cancelCountdownButton = "cancelCountdownButton"
    public static let countdownText = "countdownText"
    public static let pendingTranslationText = "pendingTranslationText"
    public static let translationEditor = "translationEditor"
    public static let partnerDisplayButton = "partnerDisplayButton"
    public static let partnerDisplayView = "partnerDisplayView"
    public static let partnerDisplayText = "partnerDisplayText"
    public static let flipButton = "flipButton"
    public static let closePartnerDisplayButton = "closePartnerDisplayButton"
    public static let settingsButton = "settingsButton"
    public static let settingsDoneButton = "settingsDoneButton"
    public static let permissionView = "permissionView"
    public static let openSettingsButton = "openSettingsButton"
    public static let errorView = "errorView"
    public static let recoveryButton = "recoveryButton"

    public static func card(_ index: Int) -> String { "card.\(index)" }
    public static func cardOriginal(_ index: Int) -> String { "card.\(index).original" }
    public static func cardTranslation(_ index: Int) -> String { "card.\(index).translation" }
    public static func cardReplay(_ index: Int) -> String { "card.\(index).replay" }
    public static func language(_ language: PartnerLanguage) -> String { "language.\(language.rawValue)" }
}
