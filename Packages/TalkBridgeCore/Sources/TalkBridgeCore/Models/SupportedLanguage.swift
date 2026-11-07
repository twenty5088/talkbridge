/// 對方可選的語言。rawValue 只當穩定識別碼用（UI 測試的 accessibility identifier 也用它）。
public enum PartnerLanguage: String, CaseIterable, Sendable, Identifiable {
    case english, indonesian, thai, japanese, korean

    public var id: String { rawValue }

    /// 中文名稱（Kevin 2026-11-08 決定：App 由太太操作，選單用中文顯示）。
    public var displayName: String {
        switch self {
        case .english: "英文"
        case .indonesian: "印尼文"
        case .thai: "泰文"
        case .japanese: "日文"
        case .korean: "韓文"
        }
    }

    /// 語音辨識用的 locale（SFSpeechRecognizer）。
    var speechLocaleID: String {
        switch self {
        case .english: "en-US"
        case .indonesian: "id-ID"
        case .thai: "th-TH"
        case .japanese: "ja-JP"
        case .korean: "ko-KR"
        }
    }

    /// Translation framework 用的語言代碼。
    var translationLanguageID: String {
        switch self {
        case .english: "en"
        case .indonesian: "id"
        case .thai: "th"
        case .japanese: "ja"
        case .korean: "ko"
        }
    }

    /// 語音合成用的語言（AVSpeechSynthesisVoice）。
    var voiceLanguageID: String { speechLocaleID }

    /// 設定頁試聽聲音時唸的句子。
    var voiceSampleText: String {
        switch self {
        case .english: "Hello, nice to meet you."
        case .indonesian: "Halo, senang bertemu dengan Anda."
        case .thai: "สวัสดี ยินดีที่ได้รู้จัก"
        case .japanese: "こんにちは、はじめまして。"
        case .korean: "안녕하세요, 만나서 반갑습니다."
        }
    }
}

/// 使用者這一側固定是繁體中文（台灣）。
/// 若某個 Apple API 不支援這些代碼，App 端要偵測並在設定頁顯示實際使用的代碼。
public enum ChineseLocale {
    public static let speechLocaleID = "zh-TW"
    public static let translationLanguageID = "zh-Hant-TW"
    public static let voiceLanguageID = "zh-TW"
}
