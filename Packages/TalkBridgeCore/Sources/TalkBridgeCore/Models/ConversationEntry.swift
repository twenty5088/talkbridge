import Foundation

/// 一句對話紀錄。只存在記憶體，關閉 App 就消失。
public struct ConversationEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let speaker: Speaker
    public let direction: TranslationDirection
    public let original: String
    public var translation: String
    public let timestamp: Date

    public init(id: UUID = UUID(), speaker: Speaker, direction: TranslationDirection,
                original: String, translation: String, timestamp: Date) {
        self.id = id
        self.speaker = speaker
        self.direction = direction
        self.original = original
        self.translation = translation
        self.timestamp = timestamp
    }
}
