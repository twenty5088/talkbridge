import SwiftUI
import TalkBridgeCore

/// 中央狀態區：圖示＋文字（不只靠顏色）、即時辨識文字、提示、自動輪流時輪到誰。
struct StatusView: View {
    let conversation: ConversationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: conversation.state.symbolName)
                    .font(.title2)
                    .accessibilityHidden(true)
                Text(conversation.state.statusText)
                    .font(.title3.weight(.semibold))
                    .accessibilityIdentifier(AccessibilityID.statusText)
                Spacer(minLength: 0)
            }
            if let hint = conversation.microphoneHint {
                Label(hint, systemImage: conversation.state.isMicrophoneActive ? "mic.circle.fill" : "mic.slash.circle")
                    .font(.headline)
                    .foregroundStyle(conversation.state.isMicrophoneActive ? Color.green : Color.secondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(AccessibilityID.microphoneHint)
            }
            if let queued = conversation.queuedHint {
                Label(queued, systemImage: "arrow.uturn.right.circle.fill")
                    .font(.headline)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier(AccessibilityID.queuedHint)
            }
            if let turn = conversation.currentTurn {
                Text("現在輪到：\(turn == .partner ? "對方" : "我")")
                    .font(.headline)
                    .accessibilityIdentifier(AccessibilityID.turnIndicator)
            }
            if !conversation.partialTranscript.isEmpty {
                Text(conversation.partialTranscript)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            if let notice = conversation.notice {
                Label(notice, systemImage: "info.circle")
                    .font(.callout)
                    .accessibilityElement(children: .combine)   // 圖示＋文字合成一個元素
                    .accessibilityIdentifier(AccessibilityID.noticeView)
            }
            if let timings = conversation.lastTimings, !conversation.state.isBusy {
                Text("上一句花的時間：\(timings.summary)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AccessibilityID.timingsText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.statusView)
    }
}
