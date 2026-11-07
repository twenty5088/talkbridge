// Apple 框架都包在這些 protocol 後面：正式實作在 App target（Apple*Service），
// 測試與 UI 測試模式用 TalkBridgeFakes。ViewModel 只認得 protocol。

public enum RecognitionMode: Sendable, Equatable {
    /// 在手機上辨識，不需網路。
    case onDevice
    /// 由 Apple 伺服器辨識，需要網路（畫面要標示）。
    case server
    case unavailable
}

public enum RecognitionUpdate: Sendable, Equatable {
    case partial(String)
    case final(String)
}

public protocol SpeechRecognitionService: AnyObject, Sendable {
    func mode(forLocaleID localeID: String) async -> RecognitionMode
    /// 開麥克風開始辨識。串流在 finishAudio() 後送出 final 並結束；cancel() 立即結束且不送 final。
    func start(localeID: String) throws -> AsyncThrowingStream<RecognitionUpdate, Error>
    /// 停止收音、要求最終結果。
    func finishAudio()
    /// 立即停止收音並丟棄結果。
    func cancel()
}

public enum TranslationReadiness: Sendable, Equatable {
    case installed
    case needsDownload
    case unsupported
}

public protocol TranslationService: AnyObject, Sendable {
    func readiness(source: String, target: String) async -> TranslationReadiness
    /// 請系統下載語言資料。使用者拒絕或取消時 throw AppError.modelDownloadCancelled。
    func prepare(source: String, target: String) async throws
    func translate(_ text: String, source: String, target: String) async throws -> String
}

public enum VoiceMatch: Sendable, Equatable {
    case exact
    /// 找不到精確 locale 的語音，改用同語言最接近的。
    case fallback(actualLanguageID: String)
    case none
}

@MainActor
public protocol SpeechSynthesisService: AnyObject {
    func voiceMatch(forLanguageID languageID: String) -> VoiceMatch
    /// 播完才 return；stop() 或 Task 取消時 throw CancellationError。
    func speak(_ text: String, languageID: String) async throws
    func stop()
}

public enum OutputTarget: Sendable {
    case systemDefault
    case speaker
}

public enum AudioSessionEvent: Sendable, Equatable {
    case routeChanged(AudioRouteInfo, oldDeviceUnavailable: Bool)
    case interruptionBegan
    case interruptionEnded
    case mediaServicesReset
}

@MainActor
public protocol AudioSessionService: AnyObject {
    var currentRoute: AudioRouteInfo { get }
    var events: AsyncStream<AudioSessionEvent> { get }
    func activate() throws
    /// 回傳切換後的「實際」路由（可能切不過去）。
    func setOutput(_ target: OutputTarget) throws -> AudioRouteInfo
    func deactivate()
}

public enum PermissionState: Sendable, Equatable {
    case granted, denied, notDetermined
}

public struct PermissionSnapshot: Sendable, Equatable {
    public var microphone: PermissionState
    public var speech: PermissionState

    public init(microphone: PermissionState, speech: PermissionState) {
        self.microphone = microphone
        self.speech = speech
    }

    public static let allGranted = PermissionSnapshot(microphone: .granted, speech: .granted)
}

public protocol PermissionService: AnyObject, Sendable {
    func current() async -> PermissionSnapshot
    func request() async -> PermissionSnapshot
}
