import SwiftUI
import TalkBridgeCore

/// 模式 B 待播：大字譯文、倒數、播放／停止／重播／重新錄音／編輯／取消倒數。
struct PlaybackControlsView: View {
    @Bindable var conversation: ConversationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("要說給對方聽的翻譯")
                .font(.headline)
            if conversation.isEditing {
                // 單行輸入：按「完成」就收起鍵盤，不會擋住下面的播放按鈕。
                TextField("翻譯文字", text: $conversation.editableTranslation)
                    .font(.title2)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .accessibilityIdentifier(AccessibilityID.translationEditor)
            } else {
                Text(conversation.editableTranslation)
                    .font(.title.weight(.semibold))
                    .textSelection(.enabled)
                    .accessibilityIdentifier(AccessibilityID.pendingTranslationText)
            }
            if let seconds = conversation.countdownRemaining {
                HStack {
                    Text("\(seconds) 秒後自動播放")
                        .font(.headline)
                        .accessibilityIdentifier(AccessibilityID.countdownText)
                    Spacer()
                    Button("取消倒數") { conversation.cancelCountdown() }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier(AccessibilityID.cancelCountdownButton)
                }
            }
            // 用格狀排列自動換行（大字時也不會截斷）；每個按鈕在畫面結構裡只出現一次。
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8)], alignment: .leading, spacing: 8) {
                buttons
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var buttons: some View {
        Button {
            conversation.playForPartner()
        } label: {
            Label("播放", systemImage: "play.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(conversation.state.isSpeaking)
        .accessibilityIdentifier(AccessibilityID.playButton)

        Button {
            conversation.stopPlayback()
        } label: {
            Label("停止", systemImage: "stop.fill")
        }
        .buttonStyle(.bordered)
        .disabled(!conversation.state.isSpeaking)
        .accessibilityIdentifier(AccessibilityID.stopPlaybackButton)

        Button {
            conversation.replayLastForPartner()
        } label: {
            Label("重播", systemImage: "arrow.counterclockwise")
        }
        .buttonStyle(.bordered)
        .disabled(conversation.state.isSpeaking)
        .accessibilityIdentifier(AccessibilityID.replayButton)

        Button {
            conversation.rerecord()
        } label: {
            Label("重新錄音", systemImage: "mic.badge.plus")
        }
        .buttonStyle(.bordered)
        .disabled(conversation.state.isSpeaking)
        .accessibilityIdentifier(AccessibilityID.rerecordButton)

        Button {
            conversation.beginEditing()
        } label: {
            Label("編輯", systemImage: "pencil")
        }
        .buttonStyle(.bordered)
        .disabled(conversation.state.isSpeaking || conversation.isEditing)
        .accessibilityIdentifier(AccessibilityID.editTranslationButton)
    }
}
