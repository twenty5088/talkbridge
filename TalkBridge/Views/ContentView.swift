import SwiftUI
import TalkBridgeCore

/// 根畫面：主對話畫面＋設定＋「給對方看」，並掛上唯一的翻譯宿主與音訊事件監聽。
struct ContentView: View {
    let environment: AppEnvironment
    @State private var showSettings = false
    @State private var showPartnerDisplay = false

    private var conversation: ConversationViewModel { environment.conversation }

    var body: some View {
        NavigationStack {
            ConversationView(conversation: conversation, mode: modeBinding)
                .navigationTitle("TalkBridge")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showPartnerDisplay = true
                        } label: {
                            Label("給對方看", systemImage: "rectangle.portrait.rotate")
                        }
                        .accessibilityIdentifier(AccessibilityID.partnerDisplayButton)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Label("設定", systemImage: "gearshape")
                        }
                        .accessibilityIdentifier(AccessibilityID.settingsButton)
                    }
                }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: environment.settings)
        }
        .fullScreenCover(isPresented: $showPartnerDisplay) {
            PartnerDisplayView(text: latestForeignText) { showPartnerDisplay = false }
        }
        .background {
            if let translationService = environment.translationService {
                TranslationHostView(service: translationService)
            }
        }
        .modifier(FontScaleModifier(scale: environment.settings.settings.fontScale))
        .task {
            await conversation.startObservingAudioEvents()
        }
        .onAppear {
            conversation.settings = environment.settings.settings
        }
        .onChange(of: environment.settings.settings) { _, newValue in
            conversation.settings = newValue
        }
        // 對話進行中不讓螢幕自動鎖定；鎖定會讓 App 進背景而中斷對話（v2 設計 P3）。
        .onChange(of: conversation.keepsScreenAwake, initial: true) { _, keepAwake in
            UIApplication.shared.isIdleTimerDisabled = keepAwake
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private var modeBinding: Binding<ConversationMode> {
        Binding(get: { environment.settings.settings.mode },
                set: { environment.settings.settings.mode = $0 })
    }

    /// 「給對方看」顯示最新一句外語：待播譯文優先，其次是最後一句給對方的翻譯。
    private var latestForeignText: String {
        if case .readyToPlayForPartner = conversation.state, !conversation.editableTranslation.isEmpty {
            return conversation.editableTranslation
        }
        return conversation.entries.last(where: { $0.speaker == .user })?.translation ?? ""
    }
}

/// 設定裡的字體大小：標準（1.0）時完全跟隨系統的 Dynamic Type；其他選項才覆寫。
private struct FontScaleModifier: ViewModifier {
    let scale: Double

    func body(content: Content) -> some View {
        switch scale {
        case ..<0.9: content.dynamicTypeSize(.small)
        case 1.1..<1.3: content.dynamicTypeSize(.xLarge)
        case 1.3...: content.dynamicTypeSize(.xxxLarge)
        default: content
        }
    }
}
