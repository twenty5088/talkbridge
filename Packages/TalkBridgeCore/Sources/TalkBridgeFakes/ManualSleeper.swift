import Synchronization
import TalkBridgeCore

/// 測試用時鐘：sleep 會掛起，直到測試呼叫 advance(by:) 讓虛擬時間超過期限。
public final class ManualSleeper: Sleeper, Sendable {
    private struct Waiter: Sendable {
        let id: UInt64
        let deadline: Duration
        let continuation: CheckedContinuation<Void, Error>
    }

    private struct State {
        var now: Duration = .zero
        var nextID: UInt64 = 0
        var waiters: [Waiter] = []
        var cancelledBeforeRegistering: Set<UInt64> = []
    }

    private enum Outcome { case wait, resumeNow, cancelNow }

    private let state = Mutex(State())

    public init() {}

    public var pendingCount: Int { state.withLock { $0.waiters.count } }
    public var now: Duration { state.withLock { $0.now } }

    public func sleep(for duration: Duration) async throws {
        let id = state.withLock { s -> UInt64 in
            s.nextID += 1
            return s.nextID
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let outcome = state.withLock { s -> Outcome in
                    if s.cancelledBeforeRegistering.remove(id) != nil { return .cancelNow }
                    if duration <= .zero { return .resumeNow }
                    s.waiters.append(Waiter(id: id, deadline: s.now + duration, continuation: continuation))
                    return .wait
                }
                switch outcome {
                case .wait: break
                case .resumeNow: continuation.resume()
                case .cancelNow: continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            let waiter = state.withLock { s -> Waiter? in
                if let index = s.waiters.firstIndex(where: { $0.id == id }) {
                    return s.waiters.remove(at: index)
                }
                s.cancelledBeforeRegistering.insert(id)
                return nil
            }
            waiter?.continuation.resume(throwing: CancellationError())
        }
    }

    public func advance(by duration: Duration) {
        let due = state.withLock { s -> [Waiter] in
            s.now += duration
            let deadline = s.now
            let ready = s.waiters.filter { $0.deadline <= deadline }
            s.waiters.removeAll { $0.deadline <= deadline }
            return ready
        }
        for waiter in due { waiter.continuation.resume() }
    }

    /// 等到至少有 count 個 sleep 在等待（讓測試知道被測程式已經走到等待點）。
    /// 有上限：等不到就回傳 false，讓測試接著在後面的檢查失敗，而不是永遠卡住。
    @discardableResult
    public func waitForPendingCount(_ count: Int, maxYields: Int = 200_000) async -> Bool {
        for _ in 0..<maxYields {
            if pendingCount >= count { return true }
            await Task.yield()
        }
        return pendingCount >= count
    }
}
