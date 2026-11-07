/// 把翻譯方向對應到各 Apple 框架要用的語言代碼。集中在這裡，避免各處各寫一份。
public enum LocaleMapping {
    /// 這句話要用哪個 locale 做語音辨識（說話者的語言）。
    public static func speechLocaleID(for direction: TranslationDirection) -> String {
        switch direction {
        case .partnerToChinese(let language): language.speechLocaleID
        case .chineseToPartner: ChineseLocale.speechLocaleID
        }
    }

    /// Translation framework 的來源與目標語言。
    public static func translationPair(for direction: TranslationDirection) -> (source: String, target: String) {
        switch direction {
        case .partnerToChinese(let language): (language.translationLanguageID, ChineseLocale.translationLanguageID)
        case .chineseToPartner(let language): (ChineseLocale.translationLanguageID, language.translationLanguageID)
        }
    }

    /// 譯文要用哪種語言的語音唸出來（聽者的語言）。
    public static func voiceLanguageID(for direction: TranslationDirection) -> String {
        switch direction {
        case .partnerToChinese: ChineseLocale.voiceLanguageID
        case .chineseToPartner(let language): language.voiceLanguageID
        }
    }
}
