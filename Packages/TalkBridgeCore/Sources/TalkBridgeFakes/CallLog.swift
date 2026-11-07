import Synchronization

/// 測試用的呼叫紀錄。只記錄呼叫代碼（例如 "recognition.start(en-US)"），絕不記錄說話內容。
/// 同步記錄，確保順序與實際呼叫順序一致。
public final class CallLog: Sendable {
    private let storage = Mutex<[String]>([])

    public init() {}

    public func record(_ entry: String) {
        storage.withLock { $0.append(entry) }
    }

    public var entries: [String] {
        storage.withLock { $0 }
    }

    public func count(of entry: String) -> Int {
        entries.filter { $0 == entry }.count
    }
}
