import SwiftUI
import TalkBridgeCore

/// 「給對方看」：全螢幕大字顯示最新一句外語，可翻轉 180° 給坐在對面的人看。
struct PartnerDisplayView: View {
    let text: String
    let onClose: () -> Void
    @State private var flipped = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 0)
            Text(text.isEmpty ? "（還沒有要給對方看的翻譯）" : text)
                .font(.system(size: 44, weight: .bold))
                .minimumScaleFactor(0.3)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
                .rotationEffect(.degrees(flipped ? 180 : 0))
                .accessibilityIdentifier(AccessibilityID.partnerDisplayText)
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                Button {
                    flipped.toggle()
                } label: {
                    Label("翻轉", systemImage: "arrow.up.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(AccessibilityID.flipButton)
                .accessibilityValue(flipped ? "已翻轉" : "未翻轉")

                Button(action: onClose) {
                    Label("關閉", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AccessibilityID.closePartnerDisplayButton)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        // 外框只當容器；不加 .contain 的話，識別名稱會蓋掉裡面按鈕自己的名稱。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.partnerDisplayView)
    }
}
