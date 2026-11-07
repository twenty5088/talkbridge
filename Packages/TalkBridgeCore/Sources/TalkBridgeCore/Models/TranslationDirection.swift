/// 一句話的翻譯方向。
public enum TranslationDirection: Hashable, Sendable {
    /// 對方說外語 → 翻成中文給使用者聽。
    case partnerToChinese(PartnerLanguage)
    /// 使用者說中文 → 翻成外語給對方聽。
    case chineseToPartner(PartnerLanguage)

    public var speaker: Speaker {
        switch self {
        case .partnerToChinese: .partner
        case .chineseToPartner: .user
        }
    }

    public var partnerLanguage: PartnerLanguage {
        switch self {
        case .partnerToChinese(let language), .chineseToPartner(let language): language
        }
    }

    public var reversed: TranslationDirection {
        switch self {
        case .partnerToChinese(let language): .chineseToPartner(language)
        case .chineseToPartner(let language): .partnerToChinese(language)
        }
    }

    public static func from(speaker: Speaker, partner: PartnerLanguage) -> TranslationDirection {
        switch speaker {
        case .partner: .partnerToChinese(partner)
        case .user: .chineseToPartner(partner)
        }
    }
}
