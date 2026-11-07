/// 可注入的等待。正式用 Task.sleep；測試用 ManualSleeper 精準控制時間，不靠真實等待。
public protocol Sleeper: Sendable {
    func sleep(for duration: Duration) async throws
}

public struct TaskSleeper: Sleeper {
    public init() {}

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
