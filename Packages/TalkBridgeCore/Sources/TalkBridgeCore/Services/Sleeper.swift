/// 可注入的時間來源與等待。正式用 ContinuousClock／Task.sleep；
/// 測試用 ManualSleeper 精準控制虛擬時間，不靠真實等待。
public protocol Sleeper: Sendable {
    /// 單調遞增的目前時間（只拿來算間隔）。
    var now: Duration { get }
    func sleep(for duration: Duration) async throws
}

public struct TaskSleeper: Sleeper {
    private let origin = ContinuousClock.now

    public init() {}

    public var now: Duration { ContinuousClock.now - origin }

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
