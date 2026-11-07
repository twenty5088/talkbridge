import SwiftUI
import TalkBridgeCore

/// 主對話畫面：上方選語言與模式，中間是狀態、待播控制與對話紀錄，下方固定兩個大按鈕與全部停止。
struct ConversationView: View {
    @Bindable var conversation: ConversationViewModel
    /// 對話模式存在設定裡（會保存），由 ContentView 傳入。
    @Binding var mode: ConversationMode
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                LanguagePickerView(selection: $conversation.partnerLanguage)
                modePicker
                StatusView(conversation: conversation)
                problemSection
                // 待播控制放在狀態正下方，不會被底部的大按鈕列擋住。
                if showsPlaybackControls {
                    PlaybackControlsView(conversation: conversation)
                }
                AudioRouteView(route: conversation.route)
                historySection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .safeAreaInset(edge: .bottom) {
            mainButtons
        }
    }

    private var modePicker: some View {
        Picker("對話模式", selection: $mode) {
            Text("手動輪流").tag(ConversationMode.manual)
            Text("自動輪流 Beta").tag(ConversationMode.autoAlternate)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier(AccessibilityID.modePicker)
    }

    @ViewBuilder
    private var problemSection: some View {
        switch conversation.state {
        case .needsPermission:
            PermissionView(error: conversation.lastError) { openAppSettings() }
        case .error, .languageNotReady:
            if let error = conversation.lastError {
                ErrorCardView(error: error) {
                    if error.recovery == .openSettings {
                        openAppSettings()
                    } else {
                        conversation.recover()
                    }
                }
            }
        default:
            EmptyView()
        }
    }

    private var showsPlaybackControls: Bool {
        switch conversation.state {
        case .readyToPlayForPartner: true
        case .speakingPartnerLanguage: !conversation.editableTranslation.isEmpty
        default: false
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("對話紀錄")
                    .font(.headline)
                Spacer()
                if !conversation.entries.isEmpty {
                    Button(role: .destructive) {
                        conversation.clearHistory()
                    } label: {
                        Label("清除紀錄", systemImage: "trash")
                    }
                    .accessibilityIdentifier(AccessibilityID.clearHistoryButton)
                }
            }
            if conversation.entries.isEmpty {
                Text("還沒有對話。按下方按鈕開始。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            // 新的在上面。
            ForEach(Array(conversation.entries.enumerated().reversed()), id: \.element.id) { index, entry in
                ConversationCardView(entry: entry, index: index, canReplay: !conversation.state.isBusy) {
                    conversation.replay(entry.id)
                }
            }
        }
    }

    private var mainButtons: some View {
        VStack(spacing: 10) {
            AdaptiveStack {
                BigTalkButton(title: partnerButtonTitle, systemImage: "person.wave.2.fill", tint: .indigo,
                              identifier: AccessibilityID.partnerButton) {
                    conversation.partnerButtonTapped()
                }
                BigTalkButton(title: userButtonTitle, systemImage: "mic.fill", tint: .teal,
                              identifier: AccessibilityID.userButton) {
                    conversation.userButtonTapped()
                }
            }
            Button(role: .destructive) {
                conversation.stopAll()
            } label: {
                Label("全部停止", systemImage: "stop.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .accessibilityIdentifier(AccessibilityID.stopAllButton)
            .accessibilityHint("停止聆聽、翻譯與播放")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var partnerButtonTitle: String {
        conversation.state == .listeningToPartner ? "說完了" : "對方說話"
    }

    private var userButtonTitle: String {
        conversation.state == .listeningToUser ? "說完了" : "我說中文"
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            openURL(url)
        }
    }
}

/// 一般字級左右並排；大字（無障礙字級）時改上下排，避免文字被截斷。
private struct AdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder let content: Content

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) { content }
        } else {
            HStack(spacing: 12) { content }
        }
    }
}

private struct BigTalkButton: View {
    let title: String
    let systemImage: String
    let tint: Color
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 56)
                .multilineTextAlignment(.center)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
        .accessibilityIdentifier(identifier)
    }
}

/// 錯誤訊息＋復原按鈕。
private struct ErrorCardView: View {
    let error: AppError
    let onRecover: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(error.userMessage, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.primary)
            Button(error.recovery.buttonTitle, action: onRecover)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AccessibilityID.recoveryButton)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.errorView)
    }
}
