import Observation

/// 設定的讀寫介面。App 用 UserDefaults 版本；測試用 InMemorySettingsStore。
@MainActor
public protocol SettingsStore: AnyObject {
    func load() -> AppSettings
    func save(_ settings: AppSettings)
}

@MainActor
public final class InMemorySettingsStore: SettingsStore {
    private var stored: AppSettings?
    public private(set) var saveCount = 0

    public init() {}

    public func load() -> AppSettings { stored ?? AppSettings() }

    public func save(_ settings: AppSettings) {
        stored = settings
        saveCount += 1
    }
}

@MainActor
@Observable
public final class SettingsViewModel {
    public static let fontScaleOptions: [Double] = [0.85, 1.0, 1.2, 1.5]
    /// 「說完停頓多久才翻譯」的選項（秒）。
    public static let pauseOptions: [Double] = [1.2, 1.5, 2.0, 2.5, 3.0, 4.0]

    @ObservationIgnored private let store: any SettingsStore

    /// 每次修改都立即保存（只存偏好，不存對話）。
    public var settings: AppSettings {
        didSet { store.save(settings) }
    }

    public init(store: any SettingsStore) {
        self.store = store
        self.settings = store.load()
    }
}
