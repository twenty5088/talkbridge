import TalkBridgeCore

/// UI 測試透過 launch argument `-fakeScenario <rawValue>` 選擇的情境。測試句子都是人工示例。
public enum FakeScenario: String, CaseIterable, Sendable {
    case happyPath
    case permissionDenied
    case translationFailure
    case languageNotReady
    case speakerOverrideFails

    public static let partnerSampleFinal = "Where is the train station?"
    public static let userSampleFinal = "請問車站在哪裡？"

    @MainActor
    public func makeServices(sleeper: any Sleeper = TaskSleeper()) -> FakeServiceBundle {
        let log = CallLog()
        let scripts: [String: [RecognitionUpdate]] = [
            "en-US": [.partial("Where is the"), .final(Self.partnerSampleFinal)],
            "zh-TW": [.partial("請問車站"), .final(Self.userSampleFinal)],
        ]
        let recognition = FakeSpeechRecognitionService(
            log: log, script: [.partial("Hello"), .final("Hello.")], scriptsByLocale: scripts)
        let translation = FakeTranslationService(
            log: log,
            readiness: self == .languageNotReady ? .needsDownload : .installed,
            translateError: self == .translationFailure ? AppError.translationFailed : nil,
            translateErrorOnce: true)   // 「再試一次」會用同一句重翻（v2 P7），第二次要成功
        let synthesis = FakeSpeechSynthesisService(log: log, autoCompleteAfter: .seconds(4), sleeper: sleeper)
        let bluetooth = AudioRouteInfo(kind: .bluetooth, portName: "Sample Buds")
        let audio = self == .speakerOverrideFails
            ? FakeAudioSessionService(log: log, route: bluetooth, speakerOverrideResult: bluetooth)
            : FakeAudioSessionService(log: log)
        let permissions = FakePermissionService(
            log: log,
            snapshot: self == .permissionDenied ? PermissionSnapshot(microphone: .denied, speech: .granted) : .allGranted)
        return FakeServiceBundle(log: log, recognition: recognition, translation: translation,
                                 synthesis: synthesis, audio: audio, permissions: permissions)
    }
}

@MainActor
public struct FakeServiceBundle {
    public let log: CallLog
    public let recognition: FakeSpeechRecognitionService
    public let translation: FakeTranslationService
    public let synthesis: FakeSpeechSynthesisService
    public let audio: FakeAudioSessionService
    public let permissions: FakePermissionService
}
