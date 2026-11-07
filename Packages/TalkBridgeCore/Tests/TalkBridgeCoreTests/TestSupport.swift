import Foundation
import XCTest
@testable import TalkBridgeCore
import TalkBridgeFakes

/// 讓出主執行緒直到條件成立（不用固定 sleep）。超過上限就判失敗。
@MainActor
func waitUntil(_ description: String = "condition", file: StaticString = #filePath, line: UInt = #line,
               _ condition: @MainActor () -> Bool) async {
    for _ in 0..<200_000 {
        if condition() { return }
        await Task.yield()
    }
    XCTFail("等不到：\(description)", file: file, line: line)
}

/// 每個測試自己建立一組全新的假服務，測試之間互不依賴。
@MainActor
struct Harness {
    let log: CallLog
    let recognition: FakeSpeechRecognitionService
    let translation: FakeTranslationService
    let synthesis: FakeSpeechSynthesisService
    let audio: FakeAudioSessionService
    let permissions: FakePermissionService
    let sleeper: ManualSleeper
    let vm: ConversationViewModel

    init(script: [RecognitionUpdate] = [.partial("Where"), .partial("Where is the station"), .final("Where is the station?")],
         scriptsByLocale: [String: [RecognitionUpdate]] = [:],
         recognitionMode: RecognitionMode = .onDevice,
         recognitionError: (any Error & Sendable)? = nil,
         sendsFinal: Bool = true,
         readiness: TranslationReadiness = .installed,
         prepareError: (any Error & Sendable)? = nil,
         translateError: (any Error & Sendable)? = nil,
         holdTranslations: Bool = false,
         voiceMatch: VoiceMatch = .exact,
         route: AudioRouteInfo = AudioRouteInfo(kind: .speaker, portName: "Speaker"),
         speakerOverrideResult: AudioRouteInfo? = nil,
         permissionSnapshot: PermissionSnapshot = .allGranted,
         afterRequest: PermissionSnapshot? = nil,
         settings: AppSettings = AppSettings(),
         configuration: ConversationConfiguration = .standard) {
        let log = CallLog()
        self.log = log
        recognition = FakeSpeechRecognitionService(log: log, mode: recognitionMode, script: script,
                                                   scriptsByLocale: scriptsByLocale, error: recognitionError,
                                                   sendsFinal: sendsFinal)
        translation = FakeTranslationService(log: log, readiness: readiness, prepareError: prepareError,
                                             translateError: translateError, holdTranslations: holdTranslations)
        synthesis = FakeSpeechSynthesisService(log: log, match: voiceMatch)
        audio = FakeAudioSessionService(log: log, route: route, speakerOverrideResult: speakerOverrideResult)
        permissions = FakePermissionService(log: log, snapshot: permissionSnapshot, afterRequest: afterRequest)
        sleeper = ManualSleeper()
        var tick: TimeInterval = 0
        vm = ConversationViewModel(recognition: recognition, translation: translation, synthesis: synthesis,
                                   audio: audio, permissions: permissions, sleeper: sleeper,
                                   configuration: configuration, settings: settings,
                                   now: { tick += 1; return Date(timeIntervalSince1970: tick) })
    }

    /// 對方說一句並播完中文（模式 A 完整一輪）。
    func runPartnerTurn() async {
        vm.partnerButtonTapped()
        await waitUntil("listening") { vm.state == .listeningToPartner && !vm.partialTranscript.isEmpty }
        vm.partnerButtonTapped()   // 再按一次＝說完了
        await waitUntil("speaking") { vm.state == .speakingChinese && synthesis.isSpeaking }
        synthesis.completeCurrent()
        await waitUntil("idle") { vm.state == .idle }
    }
}
