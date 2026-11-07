import Synchronization

/// 只會 resume 一次的 continuation 閘門：讓「工作完成」「逾時」「被取消」三方競賽，誰先到就用誰的結果，
/// 其餘忽略；結束時執行登記的清理（取消另一個工作）。
final class ResumeGate<Value: Sendable>: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Value, Error>?
        var result: Result<Value, Error>?
        var cleanups: [@Sendable () -> Void] = []
    }

    private let state = Mutex(State())

    func attach(_ continuation: CheckedContinuation<Value, Error>) {
        let ready = state.withLock { s -> Result<Value, Error>? in
            if let result = s.result { return result }
            s.continuation = continuation
            return nil
        }
        if let ready { continuation.resume(with: ready) }
    }

    func onFinish(_ cleanup: @escaping @Sendable () -> Void) {
        let finished = state.withLock { s -> Bool in
            if s.result != nil { return true }
            s.cleanups.append(cleanup)
            return false
        }
        if finished { cleanup() }
    }

    func resume(with result: Result<Value, Error>) {
        let taken = state.withLock { s -> (CheckedContinuation<Value, Error>?, [@Sendable () -> Void])? in
            guard s.result == nil else { return nil }
            s.result = result
            let taken = (s.continuation, s.cleanups)
            s.continuation = nil
            s.cleanups = []
            return taken
        }
        guard let taken else { return }
        taken.0?.resume(with: result)
        for cleanup in taken.1 { cleanup() }
    }
}
