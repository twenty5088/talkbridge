import SwiftUI
import TalkBridgeCore

struct SettingsView: View {
    @Bindable var settings: SettingsViewModel
    var canPreviewVoice = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("輸出方式", selection: $settings.settings.outputPreference) {
                        Text("自動（有耳機時外語改用手機喇叭）").tag(OutputPreference.automatic)
                        Text("一律用手機喇叭").tag(OutputPreference.alwaysSpeaker)
                    }
                } header: {
                    Text("聲音")
                } footer: {
                    Text("有藍牙耳機時，中文從耳機播給你聽；外語會暫時改從手機喇叭播給對方。若耳機切不過去，畫面會提示，可改用「給對方看」。收音一律使用 iPhone 的麥克風。")
                }

                Section {
                    ForEach(VoiceLanguage.all, id: \.languageID) { language in
                        NavigationLink {
                            VoicePickerView(language: language, settings: settings, canPreview: canPreviewVoice)
                        } label: {
                            LabeledContent(language.title,
                                           value: VoicePickerView.chosenName(for: language, in: settings.settings))
                        }
                        .accessibilityIdentifier(AccessibilityID.voiceRow(language.languageID))
                    }
                } header: {
                    Text("翻譯時用的聲音")
                } footer: {
                    Text("想要更自然的聲音：到 iPhone「設定 → 輔助使用 → 閱讀與朗讀 → 聲音」下載名字標「加強版」或「高品質」的聲音，再回來這裡選。")
                }

                Section {
                    Picker("說完停頓多久才翻譯", selection: $settings.settings.pauseSeconds) {
                        ForEach(SettingsViewModel.pauseOptions, id: \.self) { seconds in
                            Text(Self.pauseText(seconds)).tag(seconds)
                        }
                    }
                    .accessibilityIdentifier(AccessibilityID.pausePicker)
                } header: {
                    Text("聆聽")
                } footer: {
                    Text("說話停頓超過這個時間，就當作一句話說完、開始翻譯。常被切斷就調長一點；想馬上翻譯，可以再按一次按鈕。")
                }

                Section("播放給對方") {
                    Toggle("先確認再播放（不倒數）", isOn: $settings.settings.confirmBeforePlay)
                    Toggle("對方說完後繼續聆聽對方", isOn: $settings.settings.continueListeningAfterPartner)
                }

                Section("字體大小") {
                    Picker("字體大小", selection: $settings.settings.fontScale) {
                        Text("小").tag(SettingsViewModel.fontScaleOptions[0])
                        Text("標準（跟隨系統）").tag(SettingsViewModel.fontScaleOptions[1])
                        Text("大").tag(SettingsViewModel.fontScaleOptions[2])
                        Text("特大").tag(SettingsViewModel.fontScaleOptions[3])
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    LabeledContent("中文語音辨識", value: ChineseLocale.speechLocaleID)
                    LabeledContent("中文翻譯", value: ChineseLocale.translationLanguageID)
                    LabeledContent("中文語音", value: ChineseLocale.voiceLanguageID)
                } header: {
                    Text("實際使用的中文代碼")
                }

                Section("離線與隱私") {
                    Text("語音辨識、翻譯與語音合成都由 Apple 系統功能處理，不使用第三方雲端服務。能不能離線，取決於語言資料是否已下載，以及 Apple 對該語言是否支援在手機上辨識；不支援的語言會改由 Apple 伺服器辨識，畫面會標示。")
                    Text("錄音不會被儲存；對話紀錄只在記憶體中，關閉 App 就消失。")
                }

                Section {
                    LabeledContent("版本", value: Self.versionText)
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier(AccessibilityID.settingsDoneButton)
                }
            }
        }
    }

    private static func pauseText(_ seconds: Double) -> String {
        let text = seconds == seconds.rounded() ? String(Int(seconds)) : String(seconds)
        return seconds == AppSettings().pauseSeconds ? "\(text) 秒（預設）" : "\(text) 秒"
    }

    private static var versionText: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "第 \(build) 版"
    }
}
