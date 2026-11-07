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
        // 基準（舊行為）：第一個完全相同語言的語音，否則同語系第一個。
        if let i = candidates.firstIndex(where: { $0.language == languageID }) { return i }
        guard let language = languageID.split(separator: "-").first.map(String.init) else { return nil }
        return candidates.firstIndex { $0.language == language || $0.language.hasPrefix(language + "-") }
    }
}
