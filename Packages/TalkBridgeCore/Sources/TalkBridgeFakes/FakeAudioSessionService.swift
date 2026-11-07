import TalkBridgeCore

@MainActor
public final class FakeAudioSessionService: AudioSessionService {
    private let log: CallLog
    private var baseRoute: AudioRouteInfo
    private let speakerOverrideResult: AudioRouteInfo?
    private let continuation: AsyncStream<AudioSessionEvent>.Continuation

    public private(set) var currentRoute: AudioRouteInfo
    public let events: AsyncStream<AudioSessionEvent>
    public var activateError: AppError?

    public init(log: CallLog, route: AudioRouteInfo = AudioRouteInfo(kind: .speaker, portName: "Speaker"),
                speakerOverrideResult: AudioRouteInfo? = nil) {
        self.log = log
        self.baseRoute = route
        self.currentRoute = route
        self.speakerOverrideResult = speakerOverrideResult
        (events, continuation) = AsyncStream<AudioSessionEvent>.makeStream()
    }

    public func activate() throws {
        log.record("audio.activate")
        if let activateError { throw activateError }
    }

    public func setOutput(_ target: OutputTarget) throws -> AudioRouteInfo {
        switch target {
        case .speaker:
            log.record("audio.setOutput(speaker)")
            currentRoute = speakerOverrideResult ?? AudioRouteInfo(kind: .speaker, portName: "Speaker")
        case .systemDefault:
            log.record("audio.setOutput(systemDefault)")
            currentRoute = baseRoute
        }
        return currentRoute
    }

    public func deactivate() {
        log.record("audio.deactivate")
    }

    /// 模擬系統送來的音訊事件（耳機拔除、來電中斷…）。
    public func send(_ event: AudioSessionEvent) {
        if case .routeChanged(let route, _) = event {
            baseRoute = route
            currentRoute = route
        }
        continuation.yield(event)
    }
}
