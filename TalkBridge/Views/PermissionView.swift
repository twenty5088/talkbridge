import SwiftUI
import TalkBridgeCore

/// 權限不足：說明為什麼需要，並提供前往 iOS 設定的按鈕。
struct PermissionView: View {
    let error: AppError?
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("需要權限", systemImage: "lock.shield")
                .font(.headline)
            Text(error?.userMessage ?? "TalkBridge 需要麥克風與語音辨識權限。")
            Text("TalkBridge 用麥克風聽取對話、用語音辨識把說話轉成文字再翻譯。錄音不會被儲存，對話紀錄關閉 App 後就消失。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("前往設定", action: onOpenSettings)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AccessibilityID.openSettingsButton)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.permissionView)
    }
}
