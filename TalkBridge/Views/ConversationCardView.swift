import SwiftUI
import TalkBridgeCore

/// 一句對話：說話者、原文、翻譯、時間、重播。
struct ConversationCardView: View {
    let entry: ConversationEntry
    let index: Int
    let canReplay: Bool
    let onReplay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(entry.speaker == .partner ? "對方" : "我",
                      systemImage: entry.speaker == .partner ? "person.wave.2" : "person.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(entry.timestamp, format: .dateTime.hour().minute().second())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(entry.original)
                .font(.body)
                .foregroundStyle(.secondary)
                .accessibilityLabel("原文：\(entry.original)")
                .accessibilityIdentifier(AccessibilityID.cardOriginal(index))
            Text(entry.translation)
                .font(.title3)
                .accessibilityLabel("翻譯：\(entry.translation)")
                .accessibilityIdentifier(AccessibilityID.cardTranslation(index))
            Button(action: onReplay) {
                Label("重播", systemImage: "speaker.wave.2")
            }
            .buttonStyle(.bordered)
            .disabled(!canReplay)
            .accessibilityIdentifier(AccessibilityID.cardReplay(index))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            entry.speaker == .partner ? Color.indigo.opacity(0.10) : Color.teal.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.card(index))
    }
}
