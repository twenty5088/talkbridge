/// 系統語音的品質等級（對應 AVSpeechSynthesisVoiceQuality；核心不 import AVFoundation）。
public enum VoiceQuality: Int, Comparable, Sendable {
    case standard = 1, enhanced = 2, premium = 3
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// 挑選語音時需要的資訊。
public struct VoiceCandidate: Equatable, Sendable {
    public var language: String
    public var quality: VoiceQuality
    public var isNovelty: Bool
    public init(language: String, quality: VoiceQuality, isNovelty: Bool = false) {
        self.language = language
        self.quality = quality
        self.isNovelty = isNovelty
    }
}

public enum VoiceSelector {
    /// 回傳要用的語音在 candidates 裡的位置；沒有可用的回傳 nil。
    public static func bestIndex(for languageID: String, in candidates: [VoiceCandidate]) -> Int? {
        // 優先順序：完全相同語言 > 同語系其他地區；非趣味語音 > 趣味語音；品質高 > 低。同分取前面的。
        guard let language = languageID.split(separator: "-").first.map(String.init) else { return nil }
        var best: (index: Int, key: (Int, Int, Int))?
        for (index, voice) in candidates.enumerated() {
            let exact = voice.language == languageID
            guard exact || voice.language == language || voice.language.hasPrefix(language + "-") else { continue }
            let key = (exact ? 1 : 0, voice.isNovelty ? 0 : 1, voice.quality.rawValue)
            if best == nil || key > best!.key { best = (index, key) }
        }
        return best?.index
    }
}
