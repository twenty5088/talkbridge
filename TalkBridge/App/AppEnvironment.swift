import Foundation
import os
import TalkBridgeCore
#if DEBUG
import TalkBridgeFakes
#endif

/// 組裝正式服務或（只在 Debug、UI 測試用）假服務。
///
/// launch arguments：
/// - `-fakeScenario <FakeScenario>`：用假服務跑指定情境（只在 Debug 版有效；Release 一律正式服務）。
/// - `-resetSettings`：清除已儲存的設定。
@MainActor
final class AppEnvironment {
    let conversation: ConversationViewModel
    let settings: SettingsViewModel
    /// 正式版才有；TranslationHostView 需要它。
    let translationService: AppleTranslationService?

    private init(conversation: ConversationViewModel, settings: SettingsViewModel,
                 translationService: AppleTranslationService?) {
        self.conversation = conversation
        self.settings = settings
        self.translationService = translationService
    }

    static func make(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppEnvironment {
        #if DEBUG
        if let index = arguments.firstIndex(of: "-fakeScenario"), index + 1 < arguments.count,
           let scenario = FakeScenario(rawValue: arguments[index + 1]) {
            return makeFake(scenario)
        }
        #endif
        let store = UserDefaultsSettingsStore()
        if arguments.contains("-resetSettings") { store.reset() }
        let settings = SettingsViewModel(store: store)
        let translation = AppleTranslationService()
        let logger = Logger(subsystem: "com.twenty5088.talkbridge", category: "conversation")
        let synthesis = AppleSpeechSynthesisService()
        synthesis.preferredVoiceIdentifier = { [weak settings] languageID in
            settings?.settings.voiceIdentifiers[languageID]
        }
        let conversation = ConversationViewModel(
            recognition: AppleSpeechRecognitionService(),
            translation: translation,
            synthesis: synthesis,
            audio: AppleAudioSessionService(),
            permissions: ApplePermissionService(),
            sleeper: TaskSleeper(),
            settings: settings.settings,
            // 只記錄狀態與錯誤分類，絕不記錄說話內容。
            logger: { message in logger.info("\(message, privacy: .public)") })
        return AppEnvironment(conversation: conversation, settings: settings, translationService: translation)
    }

    #if DEBUG
    private static func makeFake(_ scenario: FakeScenario) -> AppEnvironment {
        let services = scenario.makeServices()
        // UI 測試用真實時間跑完流程，所以把等待縮短。
        var configuration = ConversationConfiguration.standard
        configuration.silenceTimeout = .milliseconds(300)
        configuration.playbackCountdown = 5   // 留時間給 UI 測試按「取消倒數」
        configuration.postPlaybackMicGuard = .milliseconds(100)
        let settings = SettingsViewModel(store: InMemorySettingsStore())
        let conversation = ConversationViewModel(
            recognition: services.recognition,
            translation: services.translation,
            synthesis: services.synthesis,
            audio: services.audio,
            permissions: services.permissions,
            sleeper: TaskSleeper(),
            configuration: configuration,
            settings: settings.settings)
        return AppEnvironment(conversation: conversation, settings: settings, translationService: nil)
    }
    #endif
}
