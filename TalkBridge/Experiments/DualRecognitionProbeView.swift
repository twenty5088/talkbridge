import SwiftUI
import TalkBridgeCore
import UIKit

/// 【拋棄式實驗】語言判斷測試畫面。v2 設計 §3.5；完整功能開發時移除。
struct DualRecognitionProbeView: View {
    @State private var probe = DualRecognitionProbe()
    @State private var copied = false

    var body: some View {
        Form {
            Section {
                Text("先選對方語言和「這句要說的語言」，按「開始聽」後說一句話，說完按「說完了」。每種語言中文、外語各說 3 句以上，最後按「複製全部結果」貼給 Claude。")
                    .font(.footnote)
                Picker("對方語言", selection: $probe.partnerLanguage) {
                    ForEach(PartnerLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .disabled(probe.phase != .idle)
                Picker("這句要說", selection: $probe.spokeChinese) {
                    Text("中文").tag(true)
                    Text(probe.partnerLanguage.displayName).tag(false)
                }
                .pickerStyle(.segmented)
                .disabled(probe.phase != .idle)
            }

            Section {
                switch probe.phase {
                case .idle:
                    Button("開始聽") { Task { await probe.start() } }
                        .font(.title2.bold())
                case .listening:
                    Button("說完了") { Task { await probe.finish() } }
                        .font(.title2.bold())
                        .tint(.red)
                case .finishing:
                    ProgressView("等待辨識結果…")
                }
                if !probe.status.isEmpty {
                    Text(probe.status).foregroundStyle(.red)
                }
                ForEach(Array(probe.sides.enumerated()), id: \.offset) { _, side in
                    Text(DualRecognitionProbe.describe(side))
                        .font(.footnote.monospaced())
                }
            } header: {
                Text("這一句")
            }

            Section {
                Button(copied ? "已複製" : "複製全部結果") {
                    UIPasteboard.general.string = probe.report
                    copied = true
                }
                .disabled(probe.trials.isEmpty)
                Button("清除結果", role: .destructive) { probe.clear() }
                    .disabled(probe.trials.isEmpty)
                ForEach(probe.trials) { trial in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("實際說：\(trial.spokeChinese ? "中文" : trial.partnerLanguage.displayName)")
                            .font(.headline)
                        Text(DualRecognitionProbe.describe(trial.chinese))
                        Text(DualRecognitionProbe.describe(trial.partner))
                    }
                    .font(.footnote.monospaced())
                }
            } header: {
                Text("結果（\(probe.trials.count) 句）")
            }
        }
        .navigationTitle("語言判斷測試")
        .navigationBarTitleDisplayMode(.inline)
    }
}
