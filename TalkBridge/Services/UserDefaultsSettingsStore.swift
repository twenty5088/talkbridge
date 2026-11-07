import Foundation
import TalkBridgeCore

/// 設定存在 UserDefaults（只有偏好，沒有任何對話內容）。
@MainActor
final class UserDefaultsSettingsStore: SettingsStore {
    private let defaults: UserDefaults
    private let key = "settings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }
}
