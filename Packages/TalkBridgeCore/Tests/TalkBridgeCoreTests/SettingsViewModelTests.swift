import XCTest
@testable import TalkBridgeCore

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testSettingsPersistThroughStore() {
        let store = InMemorySettingsStore()
        let first = SettingsViewModel(store: store)
        XCTAssertEqual(first.settings, AppSettings())
        first.settings.confirmBeforePlay = true
        first.settings.outputPreference = .alwaysSpeaker
        first.settings.fontScale = 1.5
        XCTAssertEqual(store.saveCount, 3)

        let second = SettingsViewModel(store: store)
        XCTAssertTrue(second.settings.confirmBeforePlay)
        XCTAssertEqual(second.settings.outputPreference, .alwaysSpeaker)
        XCTAssertEqual(second.settings.fontScale, 1.5)
    }

    func testFontScaleOptions() {
        XCTAssertEqual(SettingsViewModel.fontScaleOptions, [0.85, 1.0, 1.2, 1.5])
    }

    func testSettingsRoundTripThroughJSON() throws {
        var settings = AppSettings()
        settings.mode = .autoAlternate
        settings.continueListeningAfterPartner = true
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data), settings)
    }
}
