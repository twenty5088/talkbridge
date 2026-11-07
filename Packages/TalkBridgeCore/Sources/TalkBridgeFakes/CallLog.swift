/// 測試用的呼叫紀錄。只記錄呼叫代碼（例如 "recognition.start(en-US)"），絕不記錄說話內容。
public actor CallLog {
    public private(set) var entries: [String] = []

    public init() {}

    public func record(_ entry: String) {
        entries.append(entry)
    }
}
