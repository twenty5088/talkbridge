import AVFoundation
import SwiftUI
import TalkBridgeCore

/// 設定 → 翻譯時用的聲音 → 某個語言：選「自動（品質最好）」或手機上已下載的某個聲音，並可試聽。
struct VoicePickerView: View {
    let language: VoiceLanguage
    @Bindable var settings: SettingsViewModel
    /// 對話進行中不能試聽（麥克風可能開著）。
    let canPreview: Bool
    @State private var previewer = VoicePreviewer()
    @State private var voices: [AVSpeechSynthesisVoice] = []

    var body: some View {
        List {
            Section {
                row(title: "自動（品質最好）", detail: automaticDetail, selected: chosenVoice == nil, identifier: nil)
                    .accessibilityIdentifier(AccessibilityID.voiceAutomatic)
            } footer: {
                Text("自動會用這個語言目前品質最好的聲音；下載了更好的聲音會自動換用。")
            }

            Section {
                if options.isEmpty {
                    Text("這支手機還沒有\(language.title)的聲音。請到 iPhone「設定 → 輔助使用 → 閱讀與朗讀 → 聲音」下載。")
                        .foregroundStyle(.secondary)
                }
                ForEach(options, id: \.identifier) { voice in
                    row(title: voice.name,
                        detail: [Self.regionName(voice.language), voice.candidate.quality.label]
                            .filter { !$0.isEmpty }.joined(separator: " · "),
                        selected: chosenVoice?.identifier == voice.identifier,
                        identifier: voice.identifier)
                }
            } header: {
                Text("手機上已下載的聲音")
            } footer: {
                if !canPreview {
                    Text("對話進行中不能試聽，先按「全部停止」再來試聽。")
                }
            }
        }
        .navigationTitle("\(language.title)的聲音")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { voices = AVSpeechSynthesisVoice.speechVoices() }
        .onDisappear { previewer.stop() }
    }

    // MARK: 一列：左邊點了就選，右邊按鈕試聽

    private func row(title: String, detail: String, selected: Bool, identifier: String?) -> some View {
        HStack {
            Button {
                settings.settings.voiceIdentifiers[language.languageID] = identifier
            } label: {
                HStack {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    VStack(alignment: .leading) {
                        Text(title)
                        if !detail.isEmpty {
                            Text(detail).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(selected ? .isSelected : [])

            Button {
                previewer.play(language.sampleText, voice: voice(for: identifier))
            } label: {
                Image(systemName: "play.circle").font(.title2)
            }
            .buttonStyle(.borderless)
            .disabled(!canPreview)
            .accessibilityLabel("試聽\(title)")
        }
    }

    // MARK: 資料

    private var candidates: [VoiceCandidate] { voices.map(\.candidate) }

    private var options: [AVSpeechSynthesisVoice] {
        VoiceSelector.optionIndices(for: language.languageID, in: candidates).map { voices[$0] }
    }

    /// 使用者挑的聲音（還在手機上才算）；nil＝自動。
    private var chosenVoice: AVSpeechSynthesisVoice? {
        guard let id = settings.settings.voiceIdentifiers[language.languageID] else { return nil }
        return options.first { $0.identifier == id }
    }

    private var automaticVoice: AVSpeechSynthesisVoice? {
        VoiceSelector.bestIndex(for: language.languageID, in: candidates).map { voices[$0] }
    }

    private var automaticDetail: String {
        guard let voice = automaticVoice else { return "" }
        return "目前是 \(voice.name)（\(voice.candidate.quality.label)）"
    }

    private func voice(for identifier: String?) -> AVSpeechSynthesisVoice? {
        guard let identifier else { return automaticVoice }
        return options.first { $0.identifier == identifier }
    }

    /// 設定頁那一列右邊顯示的名稱。
    static func chosenName(for language: VoiceLanguage, in settings: AppSettings) -> String {
        guard let id = settings.voiceIdentifiers[language.languageID],
              let voice = AVSpeechSynthesisVoice(identifier: id) else { return "自動" }
        return voice.name
    }

    private static func regionName(_ languageID: String) -> String {
        let parts = languageID.split(separator: "-")
        guard parts.count > 1, let region = parts.last else { return "" }
        return Locale(identifier: "zh-Hant-TW").localizedString(forRegionCode: String(region)) ?? ""
    }
}

/// 設定頁試聽用的獨立播放器。用和對話相同的音訊設定（靜音開關不會讓它沒聲音）。
@MainActor
final class VoicePreviewer {
    private let synthesizer = AVSpeechSynthesizer()
    private var activatedSession = false

    func play(_ text: String, voice: AVSpeechSynthesisVoice?) {
        synthesizer.stopSpeaking(at: .immediate)
        let session = AVAudioSession.sharedInstance()
        try? AppleAudioSessionService.configureCategory(session)
        if (try? session.setActive(true)) != nil { activatedSession = true }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        synthesizer.speak(utterance)
    }

    /// 離開選聲音畫面時停止；只有自己開過的音訊工作階段才關掉（不干擾對話）。
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        if activatedSession {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            activatedSession = false
        }
    }
}
