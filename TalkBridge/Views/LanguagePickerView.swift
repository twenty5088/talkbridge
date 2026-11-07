import SwiftUI
import TalkBridgeCore

/// 對方語言選擇。用 Menu＋每個選項各自的 identifier，讓 UI 測試能逐一選取。
struct LanguagePickerView: View {
    @Binding var selection: PartnerLanguage

    var body: some View {
        HStack {
            Text("對方語言")
                .font(.headline)
            Spacer()
            Menu {
                ForEach(PartnerLanguage.allCases) { language in
                    Button {
                        selection = language
                    } label: {
                        if language == selection {
                            Label(language.displayName, systemImage: "checkmark")
                        } else {
                            Text(language.displayName)
                        }
                    }
                    .accessibilityIdentifier(AccessibilityID.language(language))
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selection.displayName)
                    Image(systemName: "chevron.up.chevron.down")
                        .accessibilityHidden(true)
                }
            }
            .accessibilityIdentifier(AccessibilityID.languagePicker)
            .accessibilityLabel("對方語言")
            .accessibilityValue(selection.displayName)
        }
    }
}
