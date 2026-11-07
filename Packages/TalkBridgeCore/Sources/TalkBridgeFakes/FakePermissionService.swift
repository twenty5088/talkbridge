import Synchronization
import TalkBridgeCore

public final class FakePermissionService: PermissionService, Sendable {
    private let log: CallLog
    private let afterRequest: PermissionSnapshot?
    private let snapshot: Mutex<PermissionSnapshot>

    public init(log: CallLog, snapshot: PermissionSnapshot = .allGranted, afterRequest: PermissionSnapshot? = nil) {
        self.log = log
        self.snapshot = Mutex(snapshot)
        self.afterRequest = afterRequest
    }

    public func current() async -> PermissionSnapshot {
        snapshot.withLock { $0 }
    }

    public func request() async -> PermissionSnapshot {
        log.record("permission.request")
        let afterRequest = self.afterRequest
        return snapshot.withLock { s in
            if let afterRequest { s = afterRequest }
            return s
        }
    }
}
