# TalkBridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 做出可在 iPhone（iOS 26.6.2）上用 Sideloadly 安裝的雙向輪流語音翻譯 App「TalkBridge」，含完整單元測試、UI 測試、雲端 CI、README 與實機測試計畫。

**Architecture:** 所有可測試的邏輯（模型、狀態機、停頓偵測、錯誤對照、ViewModel）放在本機 Swift 套件 `TalkBridgeCore`，不 import 任何 iOS 專屬框架，所以能在 Linux CI 上幾分鐘內跑完單元測試（TDD 主迴圈）。Apple 框架（Speech、Translation、AVFoundation）只出現在 App target 的 `Apple*Service` 實作裡，透過 protocol 注入 ViewModel。測試用假服務放在獨立模組 `TalkBridgeFakes`。完整 iOS 建置、模擬器單元測試、UI 測試、警告檢查與未簽章 ipa 在 GitHub Actions macOS runner 上跑。

**Tech Stack:** Swift 6、SwiftUI、Observation（`@Observable`）、async/await、Speech（`SFSpeechRecognizer`）、Translation（`.translationTask` 宿主 view）、AVFoundation（`AVAudioEngine`、`AVAudioSession`、`AVSpeechSynthesizer`）、XCTest、XCUITest、XcodeGen、GitHub Actions（ubuntu + macOS）、Sideloadly。

**Spec:** `docs/superpowers/specs/2026-11-07-talkbridge-design.md`（設計，優先）＋ `docs/original-requirements.md`（原需求，章節以「原需求 §X」引用）。

## Global Constraints

- 部署目標 iOS 18.0；實機 iOS 26.6.2（iPhone 17 系列）。iOS 26 專屬 API 一律 `if #available(iOS 26, *)`。
- 需要 Xcode 26 SDK；CI 上用 `xcode-select` 明確選定，版本印進 log。
- 不用任何第三方套件、雲端翻譯 API、API Key、分析／廣告 SDK。
- 不使用私有 API。不使用 force unwrap、`try!`。
- repo 是**公開**的：不得提交密碼、金鑰、Apple ID、個資、真實對話；測試句子一律人工示例。
- 對話只存在記憶體；不保存錄音；console／log 不印說話內容（`Logger` 只記狀態與錯誤分類，privacy `.private` 也不放內容）。
- 所有給使用者看的文字用繁體中文（台灣用語）。
- 狀態不能只靠顏色表示：每個狀態都有文字＋SF Symbol。
- AVAudioSession：category `.playAndRecord`、mode `.default`、options `[.allowBluetoothA2DP, .defaultToSpeaker]`；**不得**加入 HFP 選項（`.allowBluetooth` / `.allowBluetoothHFP`）。
- 預設值（全部放 `ConversationConfiguration`）：停頓 1.2 秒、單句最長 30 秒、倒數 2 秒、播放後麥克風保護 0.3 秒、自動輪流等待上限 15 秒、等最終辨識結果上限 2 秒。
- 版本號＝GitHub Actions `run_number`；ipa 檔名 `TalkBridge-vN.ipa`。
- Bundle ID `com.twenty5088.talkbridge`；顯示名稱「TalkBridge」。
- 測試不得用固定 sleep；用 async test、`XCTestExpectation` 或可控的假 `Sleeper`。不得刪測試、放寬 assertion 或跳過測試來變綠。
- 每個 commit 訊息結尾加 `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`。

## Review Focus

1. **耳機模式下切喇叭失敗**：`setOutput(.speaker)` 回傳的實際路由仍是藍牙 → 外語不能假裝從喇叭播出，畫面要顯示「外語仍從耳機播出」提示並提供「給對方看」。→ Task 8 測試 `testSpeakerOverrideFailureShowsNotice`。
2. **辨識只有部分結果、遲遲沒有最終結果**（`endAudio()` 後 SFSpeech 不回 final）→ 等 2 秒後用最後一次部分結果繼續，不可卡在「正在辨識」。→ Task 7 測試 `testMissingFinalResultFallsBackToLastPartial`。
3. **說話途中換對方語言** → 取消目前工作、不得用舊語言翻譯或播放，回到待機。→ Task 9 測試 `testChangingLanguageMidUtteranceCancelsWork`。
4. **語言模型下載視窗被關掉或拒絕** → 狀態變成「語言模型尚未準備」並提供重試，不可卡住等待。→ Task 9 測試 `testDeclinedModelDownloadShowsNotReady`。
5. **播放中耳機被拔掉／斷線** → 立即停止播放（避免中文突然從手機喇叭大聲播出），顯示耳機已斷線。→ Task 9 測試 `testHeadsetDisconnectDuringPlaybackStopsSpeaking`。

---

## 檔案結構

```
talkbridge/
  project.yml                                  XcodeGen 專案定義
  .github/workflows/core.yml                   Linux：swift test（每次 push）
  .github/workflows/ios.yml                    macOS：環境資訊、build、模擬器測試、UI 測試、警告檢查、ipa
  scripts/ci.sh                                推送後等 CI 結果並印出失敗摘要（Claude 開發用）
  scripts/pick_simulator.sh                    在 runner 上挑實際存在的 iPhone 模擬器
  Packages/TalkBridgeCore/
    Package.swift                              products: TalkBridgeCore, TalkBridgeFakes
    Sources/TalkBridgeCore/
      Models/SupportedLanguage.swift           PartnerLanguage, ChineseLocale
      Models/Speaker.swift                     Speaker
      Models/TranslationDirection.swift
      Models/ConversationEntry.swift
      Models/ConversationState.swift
      Models/AudioRouteInfo.swift              AudioOutputKind + 由 port type 對照
      Models/AccessibilityID.swift             App 與 UI 測試共用的識別字串
      Configuration/ConversationConfiguration.swift
      Configuration/AppSettings.swift          OutputPreference、confirmBeforePlay 等（UserDefaults 持久化介面）
      Utilities/AppError.swift                 錯誤 → 繁中訊息、復原動作、開發分類
      Utilities/LocaleMapping.swift
      Services/ServiceProtocols.swift          五個 service protocol 與其值型別
      Services/Sleeper.swift                   可注入的等待（正式用 Task.sleep）
      StateMachine/ConversationStateMachine.swift
      StateMachine/UtteranceEndDetector.swift
      ViewModels/ConversationViewModel.swift
      ViewModels/SettingsViewModel.swift
    Sources/TalkBridgeFakes/                   只給測試與 UI 測試模式用
      CallLog.swift
      FakeSpeechRecognitionService.swift
      FakeTranslationService.swift
      FakeSpeechSynthesisService.swift
      FakeAudioSessionService.swift
      FakePermissionService.swift
      ManualSleeper.swift
      FakeScenario.swift                       UI 測試情境（happyPath / permissionDenied / translationFailure / ...）
    Tests/TalkBridgeCoreTests/                 每個 Task 的測試檔
  TalkBridge/                                  App target（iOS 專屬）
    App/TalkBridgeApp.swift
    App/AppEnvironment.swift                   組裝正式或假服務（依 launch arguments）
    Services/AppleAudioSessionService.swift
    Services/ApplePermissionService.swift
    Services/AppleSpeechRecognitionService.swift
    Services/AppleSpeechSynthesisService.swift
    Services/AppleTranslationService.swift
    Services/TranslationHostView.swift         唯一持有 .translationTask 的地方
    Views/ContentView.swift
    Views/ConversationView.swift
    Views/ConversationCardView.swift
    Views/StatusView.swift
    Views/LanguagePickerView.swift
    Views/PlaybackControlsView.swift
    Views/PartnerDisplayView.swift             「給對方看」大字、可翻轉 180°
    Views/PermissionView.swift
    Views/SettingsView.swift
    Views/AudioRouteView.swift
    Resources/Localizable.xcstrings            來源語言 zh-Hant
    Resources/Info.plist
  TalkBridgeUITests/TalkBridgeUITests.swift
  README.md
  docs/PhysicalDeviceTestPlan.md
```

## 開發迴圈（所有 Task 共用）

本機是 Windows、沒有 Swift。所有「Run」步驟都是：

```bash
git add -A && git commit -m "<msg>" && scripts/ci.sh core      # Linux 單元測試，約 2–4 分鐘
scripts/ci.sh ios                                                # macOS 完整流程，約 10–15 分鐘（只在標明時跑）
```

`scripts/ci.sh <core|ios>` 會 push、找到 HEAD commit 對應的 workflow run、等它結束，印出 `conclusion` 和失敗步驟最後 80 行 log；失敗時 exit 1。「預期 FAIL」的步驟，失敗原因必須是預期的那個（例如 `cannot find 'X' in scope`），不是別的錯。

---

### Task 1: Repo、CI 骨架與最小可編譯 App

**Files:**
- Create: `.gitignore`（`*.xcodeproj`、`DerivedData/`、`.build/`、`build/`、`*.ipa`、`Payload/`）
- Create: `Packages/TalkBridgeCore/Package.swift`
- Create: `Packages/TalkBridgeCore/Sources/TalkBridgeCore/Models/Speaker.swift`
- Create: `Packages/TalkBridgeCore/Sources/TalkBridgeFakes/CallLog.swift`
- Create: `Packages/TalkBridgeCore/Tests/TalkBridgeCoreTests/SpeakerTests.swift`
- Create: `project.yml`、`TalkBridge/App/TalkBridgeApp.swift`、`TalkBridge/Views/ContentView.swift`、`TalkBridge/Resources/Info.plist`、`TalkBridge/Resources/Localizable.xcstrings`、`TalkBridgeUITests/TalkBridgeUITests.swift`
- Create: `.github/workflows/core.yml`、`.github/workflows/ios.yml`、`scripts/ci.sh`、`scripts/pick_simulator.sh`

**Interfaces:**
- Produces: `public enum Speaker: String, Sendable, CaseIterable { case partner, user }`；`public actor CallLog { public func record(_ entry: String); public var entries: [String] { get } }`
- Produces: 套件 products `TalkBridgeCore`、`TalkBridgeFakes`（Fakes 依賴 Core）；test target `TalkBridgeCoreTests` 依賴兩者。Package `platforms: [.iOS(.v18), .macOS(.v15)]`，`swiftLanguageModes: [.v6]`。

- [ ] **Step 1: 取得 GitHub token 並建立公開 repo**

用 `printf 'protocol=https\nhost=github.com\n\n' | git credential fill` 取 token（只存在 shell 變數，不寫檔、不印出）。`POST https://api.github.com/user/repos` 建 `talkbridge`（`"private": false`）。若 token 取不到或權限不足：停下來，請 Kevin 在 github.com 手動建立公開 repo `talkbridge`，並比照 voicejournal 加部署金鑰（`~/.ssh/talkbridge_deploy`，repo `core.sshCommand` 指向它）。設定 `origin`。

- [ ] **Step 2: 寫會失敗的測試**

```swift
final class SpeakerTests: XCTestCase {
    func testSpeakerOtherSide() {
        XCTAssertEqual(Speaker.partner.other, .user)
        XCTAssertEqual(Speaker.user.other, .partner)
    }
}
```

- [ ] **Step 3: 寫 `core.yml` 與 `scripts/ci.sh`，推送，確認失敗**

`core.yml`：`on: push`；`runs-on: ubuntu-latest`；`container: swift:6.2`（若該 tag 不存在改用最新 6.x 正式版，寫進 README）；步驟 `swift --version`、`swift test --package-path Packages/TalkBridgeCore`。
Run: `scripts/ci.sh core`　Expected: FAIL，`value of type 'Speaker' has no member 'other'`

- [ ] **Step 4: 實作 `Speaker.other`，推送確認通過**

Run: `scripts/ci.sh core`　Expected: PASS，`Executed 1 test, with 0 failures`

- [ ] **Step 5: 最小 App、XcodeGen 與 `ios.yml`**

`project.yml`：local package `Packages/TalkBridgeCore`；target `TalkBridge`（application，iOS 18.0，`INFOPLIST_FILE`，`SWIFT_VERSION: 6.0`，`SWIFT_STRICT_CONCURRENCY: complete`，`TARGETED_DEVICE_FAMILY: 1`，`PRODUCT_BUNDLE_IDENTIFIER: com.twenty5088.talkbridge`，依賴 `TalkBridgeCore`、`TalkBridgeFakes`）；target `TalkBridgeUITests`（bundle.ui-testing，依賴 `TalkBridgeCore`，用 `AccessibilityID`）；scheme `TalkBridge`（test targets：UI tests）。
`Info.plist`：`NSMicrophoneUsageDescription`＝「TalkBridge 需要使用麥克風聽取對話內容，才能進行即時翻譯。錄音不會被儲存。」；`NSSpeechRecognitionUsageDescription`＝「TalkBridge 需要語音辨識，把說話內容轉成文字後再翻譯。部分語言的辨識由 Apple 伺服器處理。」；`UISupportedInterfaceOrientations` 只有 portrait；`CFBundleDisplayName` TalkBridge；`CFBundleDevelopmentRegion` zh-Hant。
`ContentView` 先顯示「TalkBridge」文字。UI 測試 `testAppLaunches`：啟動後 `app.staticTexts["TalkBridge"].exists`。
`ios.yml`（`on: push` 只在 `TalkBridge/**`、`TalkBridgeUITests/**`、`Packages/**`、`project.yml`、`.github/workflows/ios.yml` 變動，加 `workflow_dispatch`）：`runs-on: macos-26`（若映像檔不存在改 `macos-15` 並 `sudo xcode-select -s` 到 `/Applications/Xcode_26*.app`），依序：
1. `xcodebuild -version`、`swift --version`、`xcodebuild -showsdks`、`xcrun simctl list devices available`
2. `brew install xcodegen && xcodegen generate`
3. `DEST=$(scripts/pick_simulator.sh)`（挑最新 iOS runtime 中第一台 iPhone，輸出 `platform=iOS Simulator,id=<UDID>`）
4. `xcodebuild test -scheme TalkBridgeCore -destination "$DEST" -derivedDataPath DerivedData`（套件單元測試在 iOS 模擬器上再跑一次）
5. `xcodebuild test -project TalkBridge.xcodeproj -scheme TalkBridge -destination "$DEST" -derivedDataPath DerivedData -resultBundlePath UITests.xcresult 2>&1 | tee build.log`
6. 警告檢查：`grep -E "^/.*(TalkBridge|Packages)/.*warning:" build.log | sort -u > warnings.txt`；數量寫進 `$GITHUB_STEP_SUMMARY`；>0 則失敗
7. `xcrun xcresulttool get test-results summary --path UITests.xcresult > test-summary.json`（印出 passed/failed/skipped）
8. 比照 voicejournal 的 Release 未簽章 build → `Payload/` → `TalkBridge-v${run_number}.ipa`；`CURRENT_PROJECT_VERSION=${run_number}`、`MARKETING_VERSION=1.${run_number}`
9. 上傳 artifacts：`TalkBridge-v${run_number}-ipa`、`test-results`（xcresult、summary、warnings、build.log）

- [ ] **Step 6: 推送並確認 iOS 流程全綠**

Run: `scripts/ci.sh ios`　Expected: 所有步驟 success；log 中有 Xcode 26.x 版本；summary 顯示 UI 測試 1 passed、warnings 0；artifact 有 ipa。

- [ ] **Step 7: Commit**（已在每次 ci.sh 前 commit；此步確認 `git status` 乾淨）

---

### Task 2: 語言、方向、對照與設定值

**Files:**
- Create: `Models/SupportedLanguage.swift`、`Models/TranslationDirection.swift`、`Utilities/LocaleMapping.swift`、`Configuration/ConversationConfiguration.swift`
- Test: `Tests/TalkBridgeCoreTests/LocaleMappingTests.swift`、`TranslationDirectionTests.swift`、`ConversationConfigurationTests.swift`

**Interfaces:**
- Produces:
  - `public enum PartnerLanguage: String, CaseIterable, Sendable, Identifiable { case english, indonesian, thai, japanese, korean }`，`displayName`（English / Bahasa Indonesia / ไทย / 日本語 / 한국어）
  - `public enum ChineseLocale { public static let speechLocaleID = "zh-TW"; public static let translationLanguageID = "zh-Hant-TW"; public static let voiceLanguageID = "zh-TW" }`
  - `public enum TranslationDirection: Hashable, Sendable { case partnerToChinese(PartnerLanguage), chineseToPartner(PartnerLanguage) }`，`var speaker: Speaker`、`var partnerLanguage: PartnerLanguage`、`var reversed: TranslationDirection`、`static func from(speaker: Speaker, partner: PartnerLanguage) -> TranslationDirection`
  - `public enum LocaleMapping { static func speechLocaleID(for: TranslationDirection) -> String; static func translationPair(for: TranslationDirection) -> (source: String, target: String); static func voiceLanguageID(for: TranslationDirection) -> String }`
  - `public struct ConversationConfiguration: Sendable, Equatable { silenceTimeout: Duration = .milliseconds(1200); maxUtteranceDuration: Duration = .seconds(30); playbackCountdown: Int = 2 /*秒*/; postPlaybackMicGuard: Duration = .milliseconds(300); autoTurnIdleTimeout: Duration = .seconds(15); finalResultTimeout: Duration = .seconds(2); minimumMeaningfulCharacters: Int = 1; static let standard }`

- [ ] **Step 1: 寫失敗測試**

```swift
func testPartnerLocaleMapping() {
    let expected: [PartnerLanguage: (speech: String, translation: String, voice: String)] = [
        .english: ("en-US", "en", "en-US"), .indonesian: ("id-ID", "id", "id-ID"),
        .thai: ("th-TH", "th", "th-TH"), .japanese: ("ja-JP", "ja", "ja-JP"), .korean: ("ko-KR", "ko", "ko-KR")]
    for (lang, e) in expected {
        let d = TranslationDirection.partnerToChinese(lang)
        XCTAssertEqual(LocaleMapping.speechLocaleID(for: d), e.speech)
        XCTAssertEqual(LocaleMapping.translationPair(for: d).source, e.translation)
        XCTAssertEqual(LocaleMapping.translationPair(for: d).target, "zh-Hant-TW")
        XCTAssertEqual(LocaleMapping.voiceLanguageID(for: d), "zh-TW")
        let r = d.reversed
        XCTAssertEqual(LocaleMapping.speechLocaleID(for: r), "zh-TW")
        XCTAssertEqual(LocaleMapping.translationPair(for: r).target, e.translation)
        XCTAssertEqual(LocaleMapping.voiceLanguageID(for: r), e.voice)
    }
}
func testDirectionReversedTwiceIsIdentity()   // 每種語言 d.reversed.reversed == d
func testDirectionFromSpeaker()               // .partner → .partnerToChinese, .user → .chineseToPartner
func testDisplayNames()                       // 五個 displayName 與上列完全相同
func testDefaultConfiguration()               // 六個預設值與 Global Constraints 相同
```

- [ ] **Step 2:** `scripts/ci.sh core` → FAIL（`cannot find 'LocaleMapping' in scope`）
- [ ] **Step 3:** 實作上列型別
- [ ] **Step 4:** `scripts/ci.sh core` → PASS
- [ ] **Step 5:** Commit `feat(core): languages, directions, locale mapping, configuration`

---

### Task 3: 錯誤對照與音訊路由對照

**Files:**
- Create: `Utilities/AppError.swift`、`Models/AudioRouteInfo.swift`
- Test: `AppErrorTests.swift`、`AudioRouteInfoTests.swift`

**Interfaces:**
- Produces:
  - `public enum AppError: Error, Equatable, Sendable`，cases：`microphoneDenied, speechRecognitionDenied, recognizerUnavailable(localeID: String), languageUnsupported, translationModelNotInstalled, modelDownloadCancelled, noSpeechDetected, emptyTranscript, translationFailed, synthesisInterrupted, audioSessionFailed, headsetDisconnected, appBackgrounded, audioInterrupted, maxDurationReached, missingDeviceLanguageResources`（共 16 個）
  - `var userMessage: String`（繁中，不含任何使用者說話內容）、`var recovery: RecoveryAction`、`var category: String`（開發分類，如 `"permission.microphone"`）
  - `public enum RecoveryAction: Equatable, Sendable { case openSettings, retry, prepareLanguage, chooseAnotherLanguage, dismiss }`，`var buttonTitle: String`（前往設定／再試一次／下載語言／換一種語言／知道了）
  - `public enum AudioOutputKind: Equatable, Sendable { case airPods, bluetooth, speaker, receiver, headphones, unknown }`，`var displayName`（AirPods／藍牙耳機／手機喇叭／聽筒／有線耳機／未知）、`var symbolName`（SF Symbol）
  - `public struct AudioRouteInfo: Equatable, Sendable { kind: AudioOutputKind; portName: String?; static func from(portType: String, portName: String) -> AudioRouteInfo }`：對照 AVAudioSession.Port raw value `"BluetoothA2DPOutput"`/`"BluetoothHFP"`/`"BluetoothLE"` → bluetooth（portName 含 "AirPods" → airPods）、`"Speaker"` → speaker、`"Receiver"` → receiver、`"Headphones"`/`"USBAudio"` → headphones、其他 → unknown

- [ ] **Step 1: 寫失敗測試**

```swift
func testEveryErrorHasChineseMessageAndRecovery() {
    for error in allErrors {                       // 測試檔內的 private let allErrors: [AppError]，列出全部 16 個 case
        XCTAssertFalse(error.userMessage.isEmpty)
        XCTAssertFalse(error.category.isEmpty)
    }
}
func testSpecificMappings() {
    XCTAssertEqual(AppError.microphoneDenied.recovery, .openSettings)
    XCTAssertEqual(AppError.speechRecognitionDenied.recovery, .openSettings)
    XCTAssertEqual(AppError.translationModelNotInstalled.recovery, .prepareLanguage)
    XCTAssertEqual(AppError.languageUnsupported.recovery, .chooseAnotherLanguage)
    XCTAssertEqual(AppError.translationFailed.recovery, .retry)
    XCTAssertEqual(AppError.microphoneDenied.userMessage, "沒有麥克風權限，請到「設定」開啟 TalkBridge 的麥克風。")
}
func testRouteMapping() {
    XCTAssertEqual(AudioRouteInfo.from(portType: "BluetoothA2DPOutput", portName: "Kevin's AirPods Pro").kind, .airPods)
    XCTAssertEqual(AudioRouteInfo.from(portType: "BluetoothA2DPOutput", portName: "JBL Tune").kind, .bluetooth)
    XCTAssertEqual(AudioRouteInfo.from(portType: "Speaker", portName: "Speaker").kind, .speaker)
    XCTAssertEqual(AudioRouteInfo.from(portType: "Receiver", portName: "Receiver").kind, .receiver)
    XCTAssertEqual(AudioRouteInfo.from(portType: "Weird", portName: "X").kind, .unknown)
    XCTAssertEqual(AudioOutputKind.speaker.displayName, "手機喇叭")
}
```

- [ ] **Step 2:** `scripts/ci.sh core` → FAIL（`cannot find 'AppError'`）
- [ ] **Step 3:** 實作；其餘 15 個訊息自擬，一般使用者看得懂、說明下一步
- [ ] **Step 4:** `scripts/ci.sh core` → PASS
- [ ] **Step 5:** Commit `feat(core): user-facing errors and audio route mapping`

---

### Task 4: Service protocols、Sleeper 與假服務

**Files:**
- Create: `Services/ServiceProtocols.swift`、`Services/Sleeper.swift`
- Create: `TalkBridgeFakes/*.swift`（除 CallLog 已存在）
- Test: `FakesTests.swift`

**Interfaces:**
- Produces（Core）：

```swift
public enum RecognitionMode: Sendable, Equatable { case onDevice, server, unavailable }
public enum RecognitionUpdate: Sendable, Equatable { case partial(String), final(String) }
public protocol SpeechRecognitionService: AnyObject, Sendable {
    func mode(forLocaleID: String) async -> RecognitionMode
    /// 開麥克風開始辨識。串流在 finishAudio() 後送出 final 並結束；cancel() 立即結束且不送 final。
    func start(localeID: String) throws -> AsyncThrowingStream<RecognitionUpdate, Error>
    func finishAudio()
    func cancel()
}
public enum TranslationReadiness: Sendable, Equatable { case installed, needsDownload, unsupported }
public protocol TranslationService: AnyObject, Sendable {
    func readiness(source: String, target: String) async -> TranslationReadiness
    func prepare(source: String, target: String) async throws        // 使用者拒絕 → throw AppError.modelDownloadCancelled
    func translate(_ text: String, source: String, target: String) async throws -> String
}
public enum VoiceMatch: Sendable, Equatable { case exact, fallback(actualLanguageID: String), none }
@MainActor public protocol SpeechSynthesisService: AnyObject {
    func voiceMatch(forLanguageID: String) -> VoiceMatch
    /// 播完才 return；stop() 或 Task 取消時 throw CancellationError。
    func speak(_ text: String, languageID: String) async throws
    func stop()
}
public enum OutputTarget: Sendable { case systemDefault, speaker }
public enum AudioSessionEvent: Sendable, Equatable {
    case routeChanged(AudioRouteInfo, oldDeviceUnavailable: Bool)
    case interruptionBegan, interruptionEnded, mediaServicesReset
}
@MainActor public protocol AudioSessionService: AnyObject {
    var currentRoute: AudioRouteInfo { get }
    var events: AsyncStream<AudioSessionEvent> { get }
    func activate() throws
    /// 回傳切換後的「實際」路由
    func setOutput(_ target: OutputTarget) throws -> AudioRouteInfo
    func deactivate()
}
public enum PermissionState: Sendable, Equatable { case granted, denied, notDetermined }
public struct PermissionSnapshot: Sendable, Equatable { public var microphone: PermissionState; public var speech: PermissionState }
public protocol PermissionService: AnyObject, Sendable {
    func current() async -> PermissionSnapshot
    func request() async -> PermissionSnapshot
}
public protocol Sleeper: Sendable { func sleep(for: Duration) async throws }
public struct TaskSleeper: Sleeper { public init() }   // 正式：Task.sleep(for:)
```

- Produces（Fakes）：每個 Fake 都接受腳本並把呼叫寫進共用 `CallLog`（字串格式固定：`"recognition.start(<localeID>)"`、`"recognition.finishAudio"`、`"recognition.cancel"`、`"translation.translate(<source>-><target>)"`、`"translation.prepare"`、`"synthesis.speak(<languageID>)"`、`"synthesis.stop"`、`"audio.setOutput(speaker|systemDefault)"`、`"audio.activate"`）。**CallLog 只記代碼，不記句子內容**。
  - `FakeSpeechRecognitionService(log:, mode: RecognitionMode = .onDevice, script: [RecognitionUpdate], error: Error? = nil, sendsFinal: Bool = true)`：`start` 依序送出 script 的 partial，等 `finishAudio()` 後送 final（`sendsFinal == false` 時 `finishAudio()` 後既不送 final 也不結束串流——用來測 Review Focus 2）
  - `FakeTranslationService(log:, readiness: TranslationReadiness = .installed, prepareError: Error? = nil, translateError: Error? = nil)`：翻譯結果固定為 `"[\(target)] \(text)"`
  - `FakeSpeechSynthesisService(log:, match: VoiceMatch = .exact)`：`speak` 等到測試呼叫 `completeCurrent()` 或 `failCurrent(_:)` 才 return；`isSpeaking` 屬性
  - `FakeAudioSessionService(log:, route: AudioRouteInfo, speakerOverrideResult: AudioRouteInfo? = nil)`：`send(_ event:)` 推事件
  - `FakePermissionService(snapshot:, afterRequest:)`
  - `ManualSleeper`：`sleep` 掛起直到測試呼叫 `advance(by:)` 累積超過；`pendingCount`
  - `FakeScenario: String { case happyPath, permissionDenied, translationFailure, languageNotReady, speakerOverrideFails }` 與 `static func makeServices(_:) -> FakeServiceBundle`（UI 測試用；happyPath 的辨識腳本用人工示例句，如 `"Where is the train station?"` / `"請問車站在哪裡？"`）

- [ ] **Step 1: 寫失敗測試**（`FakesTests`）：`testFakeRecognitionEmitsPartialsThenFinal`、`testFakeTranslationIsDeterministic`（`"[zh-Hant-TW] Hello"`）、`testCallLogRecordsCodesNotContent`（翻譯 `"secret sentence"` 後 log 中沒有該字串）、`testManualSleeperResumesAfterAdvance`
- [ ] **Step 2:** `scripts/ci.sh core` → FAIL
- [ ] **Step 3:** 實作 protocols 與 fakes
- [ ] **Step 4:** `scripts/ci.sh core` → PASS
- [ ] **Step 5:** Commit `feat(core): service protocols and deterministic fakes`

---

### Task 5: 狀態機

**Files:**
- Create: `Models/ConversationState.swift`、`StateMachine/ConversationStateMachine.swift`
- Test: `ConversationStateMachineTests.swift`

**Interfaces:**
- Produces:

```swift
public enum ConversationState: Equatable, Sendable {
    case idle
    case listeningToPartner, transcribingPartner, translatingToChinese, speakingChinese
    case listeningToUser, transcribingChinese, translatingToPartnerLanguage
    case readyToPlayForPartner(countdown: Int?)      // nil = 等使用者按播放（確認模式或已按編輯）
    case speakingPartnerLanguage
    case needsPermission, languageNotReady, error(AppError)
    public var statusText: String     // 等待中／正在聆聽／正在辨識／正在翻譯／正在播放／準備播放給對方／需要權限／語言模型尚未準備／發生錯誤
    public var symbolName: String
    public var isMicrophoneActive: Bool   // 只有兩個 listening 狀態為 true
    public var isSpeaking: Bool
}
public struct InvalidTransition: Error, Equatable { public let from: ConversationState; public let to: ConversationState }
public struct ConversationStateMachine: Sendable {
    public private(set) var state: ConversationState = .idle
    public static func isAllowed(from: ConversationState, to: ConversationState) -> Bool
    public mutating func transition(to: ConversationState) throws(InvalidTransition)
}
```

允許的轉換（其他一律拒絕）：
- 主流程 A：idle→listeningToPartner→transcribingPartner→translatingToChinese→speakingChinese→idle
- 主流程 B：idle→listeningToUser→transcribingChinese→translatingToPartnerLanguage→readyToPlayForPartner→speakingPartnerLanguage→idle；readyToPlayForPartner→readyToPlayForPartner（倒數變化、按編輯）；speakingPartnerLanguage→readyToPlayForPartner(nil)（停止後可重播）
- 自動輪流：speakingChinese→listeningToUser、speakingPartnerLanguage→listeningToPartner **不允許**（必須先回 idle，由 ViewModel 在保護間隔後再開麥克風）——這是「播放中不開麥克風」的硬規則
- 任何狀態→idle（停止）、→error、→needsPermission、→languageNotReady；error/needsPermission/languageNotReady→idle
- listening→idle（沒說話）；transcribing→idle（空白結果）

- [ ] **Step 1: 寫失敗測試**：`testHappyPathA`、`testHappyPathB`（逐步 transition 不 throw）、`testRejectsDoubleStartListening`（listeningToPartner→listeningToPartner throws）、`testRejectsListeningWhileSpeaking`（speakingChinese→listeningToUser、speakingPartnerLanguage→listeningToPartner、speakingChinese→listeningToPartner 都 throws）、`testRejectsSkippingTranslation`（transcribingPartner→speakingChinese throws）、`testAnyStateCanStop`（窮舉所有狀態→idle 允許）、`testMicrophoneActiveOnlyWhileListening`、`testStatusTextsAreChinese`（每個狀態 statusText 與上列相同）
- [ ] **Step 2:** FAIL　**Step 3:** 實作（用 switch 窮舉，不用字串表）　**Step 4:** PASS
- [ ] **Step 5:** Commit `feat(core): explicit conversation state machine`

---

### Task 6: 一句話結束偵測

**Files:**
- Create: `StateMachine/UtteranceEndDetector.swift`
- Test: `UtteranceEndDetectorTests.swift`

**Interfaces:**
- Produces:

```swift
public struct UtteranceEndDetector: Sendable {
    public enum Decision: Equatable, Sendable { case keepListening, endBySilence, endByMaxDuration, endByNoSpeech }
    public init(configuration: ConversationConfiguration)
    /// elapsed：從開始聆聽算起；sinceLastPartial：距最後一次「文字有變」的部分結果，沒有任何結果時為 nil
    public func evaluate(elapsed: Duration, sinceLastPartial: Duration?) -> Decision
    public static func isMeaningful(_ transcript: String, configuration: ConversationConfiguration) -> Bool
}
```

規則：elapsed ≥ maxUtteranceDuration → endByMaxDuration；有部分結果且 sinceLastPartial ≥ silenceTimeout → endBySilence；沒有任何結果且 elapsed ≥ autoTurnIdleTimeout → endByNoSpeech；否則 keepListening。`isMeaningful`：去掉空白與標點後字元數 ≥ minimumMeaningfulCharacters。

- [ ] **Step 1: 寫失敗測試**：`testSilenceAfterSpeechEnds`（1.19s keep、1.2s endBySilence）、`testMaxDuration`（30s 時即使仍有新結果也 end）、`testNoSpeechTimeout`（nil、15s）、`testWhitespaceAndPunctuationAreNotMeaningful`（`""`、`"   "`、`"。，?"` false；`"好"`、`"OK"` true）、`testCustomConfigurationIsRespected`（silence 0.5s 時 0.5s end）
- [ ] **Step 2:** FAIL　**Step 3:** 實作　**Step 4:** PASS
- [ ] **Step 5:** Commit `feat(core): utterance end detection`

---

### Task 7: ConversationViewModel——模式 A（對方說 → 中文）

**Files:**
- Create: `Models/ConversationEntry.swift`、`ViewModels/ConversationViewModel.swift`、`Configuration/AppSettings.swift`
- Test: `ConversationViewModelModeATests.swift`

**Interfaces:**
- Consumes: Task 2–6 全部型別與 protocols。
- Produces:

```swift
public struct ConversationEntry: Identifiable, Equatable, Sendable {
    public let id: UUID; public let speaker: Speaker; public let direction: TranslationDirection
    public let original: String; public var translation: String; public let timestamp: Date
}
public enum OutputPreference: String, Sendable, CaseIterable { case automatic, alwaysSpeaker }
public enum ConversationMode: String, Sendable, CaseIterable { case manual, autoAlternate }
public struct AppSettings: Equatable, Sendable {
    public var outputPreference: OutputPreference = .automatic
    public var confirmBeforePlay = false
    public var continueListeningAfterPartner = false     // 原需求 §五 A-8
    public var fontScale: Double = 1.0                  // 0.85 / 1.0 / 1.2 / 1.5
    public var mode: ConversationMode = .manual
}
@MainActor @Observable public final class ConversationViewModel {
    public init(recognition: any SpeechRecognitionService, translation: any TranslationService,
                synthesis: any SpeechSynthesisService, audio: any AudioSessionService,
                permissions: any PermissionService, sleeper: any Sleeper,
                configuration: ConversationConfiguration = .standard, settings: AppSettings = .init(),
                now: @escaping @Sendable () -> Date = Date.init)
    public private(set) var state: ConversationState
    public private(set) var entries: [ConversationEntry]          // 舊到新
    public private(set) var partialTranscript: String
    public private(set) var notice: String?                       // 非錯誤的提示（伺服器辨識、語音替代、喇叭切換失敗…）
    public private(set) var route: AudioRouteInfo
    public private(set) var currentTurn: Speaker?                 // 自動輪流用
    public var partnerLanguage: PartnerLanguage                   // didSet → Task 9 規則
    public var settings: AppSettings
    public var editableTranslation: String                        // 模式 B 編輯用
    public var lastError: AppError? { get }                       // state 為 .error 時
    public func partnerButtonTapped()
    public func userButtonTapped()
    public func stopAll()
    public func clearHistory()
    public func replay(_ entryID: UUID)
    public func recover()                                         // 依 lastError.recovery：retry→回 idle；prepareLanguage→呼叫 translation.prepare
}
```

行為（模式 A）：`partnerButtonTapped()` 在 idle 時：檢查權限（Task 9）→ 檢查翻譯 readiness（Task 9）→ `audio.activate()` → `recognition.start(localeID:)` → state listeningToPartner；部分結果更新 `partialTranscript`；用 `UtteranceEndDetector` 每 100ms（透過 `sleeper`）評估；結束時 `finishAudio()` → transcribingPartner → 等 final（最多 `finalResultTimeout`，逾時用最後一次部分結果）→ 若 `!isMeaningful` → idle 並 notice「沒有聽到內容，請再說一次。」不呼叫翻譯 → translatingToChinese → `translate` → 新增 entry → 確定麥克風已停（`recognition.cancel()` 已呼叫或串流已結束）→ speakingChinese → `speak(languageID: "zh-TW")` → idle。辨識模式為 `.server` 時 notice「此語言的語音辨識需要網路（由 Apple 處理）」。
**同一個大按鈕在 listening 時再按一次＝提早結束這一句**（Kevin 決定）。

- [ ] **Step 1: 寫失敗測試**（每個測試自己建立全新 fakes，互不依賴）

```swift
func testModeAHappyPathCallOrder() async {
    // script: partial "Where", partial "Where is the station", final "Where is the station?"
    // 驅動：tap partner → 等 state == .listeningToPartner → sleeper.advance(1.2s) → 等 speaking → synthesis.completeCurrent() → 等 idle
    XCTAssertEqual(await log.entries, [
        "audio.activate", "recognition.start(en-US)", "recognition.finishAudio",
        "translation.translate(en->zh-Hant-TW)", "synthesis.speak(zh-TW)"])
    XCTAssertEqual(vm.entries.count, 1)
    XCTAssertEqual(vm.entries[0].translation, "[zh-Hant-TW] Where is the station?")
    XCTAssertEqual(vm.state, .idle)
}
func testPartialTranscriptIsPublished()                 // listening 中 partialTranscript == "Where is the station"
func testEmptyTranscriptSkipsTranslation()              // final "  " → log 無 translation.*、state idle、notice 非 nil
func testRecognitionFailureShowsError()                 // fake error → state .error(.recognizerUnavailable…) 或對應 case；無 translation 呼叫
func testTranslationFailureShowsRetry()                 // translateError → .error(.translationFailed)、recovery .retry、無 synthesis 呼叫
func testSynthesisCancelledReturnsToIdle()              // speaking 時 failCurrent(CancellationError()) → idle、entry 仍保留
func testSecondTapEndsUtteranceEarly()                  // listening 時再 tap partner → finishAudio 被呼叫一次、不需等 1.2s
func testMicrophoneStoppedBeforeSpeaking()              // log 中 "synthesis.speak" 之前必有 finishAudio 或 cancel，且 speaking 時 state.isMicrophoneActive == false
func testMissingFinalResultFallsBackToLastPartial()     // sendsFinal false → advance 2s → 用 "Where is the station" 翻譯（Review Focus 2）
func testServerRecognitionShowsNotice()                 // mode .server → notice == "此語言的語音辨識需要網路（由 Apple 處理）"
func testClearHistoryEmptiesEntriesInOrder()            // 兩輪後 entries 依時間排序；clearHistory 後為空
```

- [ ] **Step 2:** FAIL　**Step 3:** 實作（單一 `private var activeTask: Task<Void, Never>?`；所有 fake/服務回呼都在 MainActor 上更新狀態；Core 不 import `os`（Linux 沒有），記錄改用注入的 `log: @Sendable (String) -> Void`，預設不做事，App 端接 `Logger` 且只傳狀態名稱與錯誤分類）　**Step 4:** PASS
- [ ] **Step 5:** Commit `feat(core): mode A partner-to-Chinese flow`

---

### Task 8: ViewModel——模式 B（我說中文 → 外語）

**Files:**
- Modify: `ViewModels/ConversationViewModel.swift`
- Test: `ConversationViewModelModeBTests.swift`

**Interfaces:**
- Produces（新增到 ConversationViewModel）：

```swift
public func playForPartner()          // readyToPlay → 播放
public func cancelCountdown()         // 停在 readyToPlay(countdown: nil)
public func beginEditing()            // 同上，editableTranslation 可改
public func stopPlayback()            // speakingPartnerLanguage → readyToPlay(nil)
public func replayLastForPartner()
public func rerecord()                // 丟掉這句待播翻譯（不加入 entries）→ 重新開始聆聽太太
public private(set) var countdownRemaining: Int?
```

行為：翻譯完成 → `editableTranslation = 譯文` → `settings.confirmBeforePlay` 為 false 時 readyToPlay(countdown: 2) 每秒（sleeper）遞減，到 0 自動 `playForPartner()`；為 true 時 readyToPlay(nil)。entry 在**播放時**加入 entries，translation 用 `editableTranslation`（編輯後內容）。播放：若 `settings.outputPreference == .automatic` 且目前路由是藍牙／AirPods／有線耳機 → `audio.setOutput(.speaker)`；回傳路由不是 `.speaker` → notice「外語仍從耳機播出，請改用『給對方看』或在設定改成一律用手機喇叭。」仍照樣播放；播完（或停止）→ `setOutput(.systemDefault)`。找不到精確語音 → notice「找不到 <語言> 的標準語音，改用 <actual>。」；`.none` → notice 並只顯示文字不播。

- [ ] **Step 1: 寫失敗測試**

```swift
func testModeBCountdownAutoPlays()            // final "請問車站在哪裡？" → readyToPlay(2) → advance 1s → (1) → advance 1s → speakingPartnerLanguage；log 含 "synthesis.speak(en-US)"
func testCancelCountdownWaitsForTap()         // readyToPlay(2) → cancelCountdown → advance 5s 後仍 readyToPlay(nil)、無 speak；playForPartner 後才 speak
func testConfirmBeforePlaySetting()           // confirmBeforePlay true → 直接 readyToPlay(nil)
func testEditedTranslationIsSpokenAndStored() // beginEditing → editableTranslation = "Where is the station, please?" → play → entries.last.translation 相同
func testStopAndReplay()                      // speaking 時 stopPlayback → readyToPlay(nil)、log "synthesis.stop"；replayLastForPartner → 再次 speak
func testRerecordDiscardsPending()            // readyToPlay 時 rerecord → entries 數不變、state listeningToUser、log 第二次 "recognition.start(zh-TW)"
func testSpeakerOverrideWithHeadset()         // route bluetooth → play 前 "audio.setOutput(speaker)"、播完 "audio.setOutput(systemDefault)"
func testSpeakerOverrideFailureShowsNotice()  // speakerOverrideResult = bluetooth → notice 為上列文字（Review Focus 1）
func testAlwaysSpeakerPreferenceSkipsOverrideWhenAlreadySpeaker()  // route speaker → 不呼叫 setOutput
func testVoiceFallbackNotice()                // match .fallback("en-GB") → notice 含 "en-GB"
func testNoMicWhileSpeakingPartnerLanguage()  // speaking 時 userButtonTapped / partnerButtonTapped → 不新增 recognition.start（先停止播放、回 idle，不自動開麥）
```

- [ ] **Step 2:** FAIL　**Step 3:** 實作　**Step 4:** PASS
- [ ] **Step 5:** Commit `feat(core): mode B Chinese-to-partner with countdown`

---

### Task 9: ViewModel——並發、權限、語言準備、中斷

**Files:**
- Modify: `ViewModels/ConversationViewModel.swift`
- Create: `ViewModels/SettingsViewModel.swift`
- Test: `ConversationViewModelRobustnessTests.swift`、`SettingsViewModelTests.swift`

**Interfaces:**
- Produces（ConversationViewModel 新增）：

```swift
public func handleAudioEvent(_ event: AudioSessionEvent)
public func appDidEnterBackground()
public func startObservingAudioEvents()     // 迴圈讀 audio.events，View 在 .task 呼叫
```
- Produces：`@MainActor @Observable public final class SettingsViewModel { public init(store: any SettingsStore); public var settings: AppSettings; public static let fontScaleOptions: [Double] = [0.85, 1.0, 1.2, 1.5] }`；`public protocol SettingsStore: AnyObject { func load() -> AppSettings; func save(_: AppSettings) }`；`public final class InMemorySettingsStore: SettingsStore`（Core，測試用；App 另寫 UserDefaults 版）。設定只存偏好，不存對話。

行為：
- 開始前權限：`permissions.current()`；`notDetermined` → `request()`；任一 denied → state `.needsPermission`，`lastError` 對應 `.microphoneDenied` 或 `.speechRecognitionDenied`。
- 開始前翻譯：readiness `.unsupported` → `.error(.languageUnsupported)`；`.needsDownload` → `.languageNotReady`（`recover()` 呼叫 `prepare`，成功回 idle，throw `modelDownloadCancelled` → 仍 `.languageNotReady`）。
- 辨識 mode `.unavailable` → `.error(.recognizerUnavailable(localeID:))`。
- 任何時候 `stopAll()`：取消 activeTask、`recognition.cancel()`、`synthesis.stop()`、`audio.setOutput(.systemDefault)`、state idle、countdown nil。
- 開始新工作前一律先取消舊工作；**同時最多一個翻譯呼叫**（第二個請求在第一個完成前到來時，先取消第一個）。
- 改 `partnerLanguage`：非 idle 時等同 `stopAll()`。
- 音訊事件：`routeChanged(oldDeviceUnavailable: true)` → 若正在播放或聆聽 → stopAll 並 `.error(.headsetDisconnected)`；永遠更新 `route`。`interruptionBegan` → stopAll + `.error(.audioInterrupted)`；`mediaServicesReset` → stopAll + `.error(.audioSessionFailed)`。`appDidEnterBackground` → stopAll（若非 idle 則 `.error(.appBackgrounded)`）。
- 單句超過 30 秒 → 照常結束這一句並翻譯，notice「已達單句最長 30 秒，先翻譯這一段。」（不是錯誤）。

- [ ] **Step 1: 寫失敗測試**

```swift
func testRapidTapsStartRecognitionOnce()          // idle 時連續 tap partner 3 次（同一 run loop）→ "recognition.start" 只出現 1 次（第 2 次為提早結束、第 3 次被忽略或為新的一輪，但同時間只會有一個錄音）
func testStartingNewTaskCancelsOld()              // listening partner 時 tap user → log 有 "recognition.cancel" 再 "recognition.start(zh-TW)"
func testStopAllCancelsEverything()               // 在 translating 時 stopAll → idle；translate 回來的結果不會新增 entry；log 有 cancel 與 synthesis.stop
func testMicrophoneDeniedShowsPermissionState()   // denied → .needsPermission、lastError .microphoneDenied、recovery .openSettings、無 recognition.start
func testSpeechDeniedShowsPermissionState()
func testUnsupportedLanguage()                    // .unsupported → .error(.languageUnsupported)
func testDeclinedModelDownloadShowsNotReady()     // needsDownload → languageNotReady → recover() 且 prepare throws cancelled → 仍 languageNotReady（Review Focus 4）
func testChangingLanguageMidUtteranceCancelsWork()// listening 時 partnerLanguage = .thai → idle、無 translation 呼叫（Review Focus 3）
func testHeadsetDisconnectDuringPlaybackStopsSpeaking() // speakingChinese 時送 routeChanged(speaker, true) → synthesis.stop、.error(.headsetDisconnected)（Review Focus 5）
func testInterruptionStopsWork()
func testBackgroundStopsWork()
func testMaxDurationTranslatesSegment()           // 持續送新 partial、advance 30s → finishAudio、notice 為上列文字、有翻譯
func testSettingsPersistThroughStore()            // SettingsViewModel 改 confirmBeforePlay → store.save 被呼叫；新 VM load 回相同值
```

- [ ] **Step 2:** FAIL　**Step 3:** 實作　**Step 4:** PASS
- [ ] **Step 5:** Commit `feat(core): concurrency, permissions, language readiness, interruptions`

---

### Task 10: 自動輪流（模式 C，固定交替）

**Files:**
- Modify: `ViewModels/ConversationViewModel.swift`
- Test: `ConversationViewModelAutoTests.swift`

**Interfaces:**
- Produces：`currentTurn` 在 autoAlternate 模式下有值；第一句由按下的按鈕決定。

行為：`settings.mode == .autoAlternate` 時，一輪結束（A 播完、或 B 播完）→ idle → 等 `postPlaybackMicGuard` → 換另一方開始聆聽。B 在 `confirmBeforePlay` 開啟時停在 readyToPlay(nil) 等按播放，這段等待不計 15 秒。聆聽 15 秒沒有任何辨識結果（`endByNoSpeech`）→ idle、`currentTurn = nil`、notice「太久沒有聲音，已暫停自動輪流。」。任一時候按另一個大按鈕＝搶回順序（stop 目前、改由該方開始）。手動模式下 `continueListeningAfterPartner == true` 時，A 播完同樣等保護間隔後再聽對方（同一套機制）。

- [ ] **Step 1: 寫失敗測試**：`testAutoAlternatesPartnerThenUser`（A 播完 → 未 advance 0.3s 前 state idle 且無第二次 start → advance 0.3s → listeningToUser、currentTurn .user）、`testAutoAlternatesUserThenPartner`、`testAutoIdleTimeoutStops`（無結果 advance 15s → idle、currentTurn nil、notice）、`testConfirmModeWaitsInAuto`（readyToPlay(nil) 時 advance 60s 仍等待）、`testOtherButtonTakesTurn`、`testManualModeDoesNotAutoListen`、`testContinueListeningAfterPartnerSetting`
- [ ] **Step 2:** FAIL　**Step 3:** 實作　**Step 4:** PASS
- [ ] **Step 5:** Commit `feat(core): auto alternate mode`

---

### Task 11: Apple 框架實作（App target）

**Files:**
- Create: `TalkBridge/Services/Apple*.swift`（5 個）、`TalkBridge/Services/TranslationHostView.swift`、`TalkBridge/App/AppEnvironment.swift`、`TalkBridge/Services/UserDefaultsSettingsStore.swift`
- Modify: `TalkBridge/App/TalkBridgeApp.swift`

**Interfaces:**
- Consumes: Task 4 protocols；Task 9 `SettingsStore`。
- Produces: `@MainActor final class AppEnvironment { let conversation: ConversationViewModel; let settings: SettingsViewModel; let translationService: AppleTranslationService?; static func make(arguments: [String]) -> AppEnvironment }`。launch argument `-fakeScenario <FakeScenario.rawValue>` → 用 Fakes（只在 `#if DEBUG` 內解析；Release 一律正式服務）；`-resetSettings` → 清設定。

實作要點（無法單元測試，靠 CI 編譯＋實機測試計畫驗證）：
- **AppleAudioSessionService**：Global Constraints 的 category/mode/options；`setOutput(.speaker)` → `overrideOutputAudioPort(.speaker)`、`.systemDefault` → `.none`，回傳 `AudioRouteInfo.from(currentRoute.outputs.first)`；監聽 `routeChangeNotification`（reason `.oldDeviceUnavailable` → `oldDeviceUnavailable: true`）、`interruptionNotification`、`mediaServicesWereResetNotification`，轉成 `AsyncStream`，在 MainActor 上 yield。
- **AppleSpeechRecognitionService**：`SFSpeechRecognizer(locale:)`；`mode`：nil 或 `!isAvailable` → unavailable，`supportsOnDeviceRecognition` → onDevice，否則 server；`start`：`AVAudioEngine` input node `installTap`（buffer 1024，用 input format），`SFSpeechAudioBufferRecognitionRequest`（`shouldReportPartialResults = true`、onDevice 時 `requiresOnDeviceRecognition = true`、`addsPunctuation = true`）；`finishAudio`：`removeTap`、`engine.stop()`、`request.endAudio()`；`cancel`：同上加 `task.cancel()`。重入保護：已在錄時 `start` 先 `cancel`。錯誤對照到 `AppError`；不印辨識文字。
- **AppleTranslationService＋TranslationHostView**：服務持有 `@Observable` 的 `configuration: TranslationSession.Configuration?` 與待處理請求佇列（`CheckedContinuation`）；`TranslationHostView` 是根畫面上的透明 `Color.clear`，`.translationTask(service.configuration) { session in await service.run(session) }`；`readiness` 用 `LanguageAvailability().status(from:to:)`（`.installed/.supported/.unsupported` → installed/needsDownload/unsupported）；`prepare` 走 `session.prepareTranslation()`（使用者拒絕的錯誤 → `modelDownloadCancelled`）；`translate` 走 `session.translate(_:)`；語言對變更時換新 configuration，同語言對再次請求用 `configuration.invalidate()`。**整個 App 只有這一處 `.translationTask`。**
- **AppleSpeechSynthesisService**：`AVSpeechSynthesizer` + delegate 轉 continuation；`voiceMatch`：`AVSpeechSynthesisVoice(language:)` 精確 → exact；否則找 `speechVoices()` 中語言前綴相同者 → fallback(actual)；都沒有 → none。`stop` → `stopSpeaking(at: .immediate)` 並以 CancellationError 結束 continuation。
- **ApplePermissionService**：`AVAudioApplication.requestRecordPermission()`、`SFSpeechRecognizer.requestAuthorization`（包成 async）。
- `TalkBridgeApp`：`scenePhase == .background` → `conversation.appDidEnterBackground()`。

- [ ] **Step 1:** 實作上列檔案（ContentView 暫時只掛 `TranslationHostView` 與兩個按鈕，讓編譯能跑）
- [ ] **Step 2:** `scripts/ci.sh ios` → Expected: build success、warnings 0、既有測試 PASS。編譯錯誤依 runner 上 SDK 實際 API 修正（例如 iOS 26 改名的列舉），修正內容記到 README「API 版本差異」。
- [ ] **Step 3:** Commit `feat(app): Apple framework services and composition root`

---

### Task 12: SwiftUI 介面

**Files:**
- Create: `TalkBridge/Views/*.swift`（檔案結構所列）、`Models/AccessibilityID.swift`（Core）
- Modify: `Resources/Localizable.xcstrings`

**Interfaces:**
- Produces: `public enum AccessibilityID { static let partnerButton = "partnerButton", userButton = "userButton", stopAllButton = "stopAllButton", clearHistoryButton = "clearHistoryButton", languagePicker = "languagePicker", modePicker = "modePicker", statusView = "statusView", routeView = "routeView", noticeView = "noticeView", playButton = "playButton", stopPlaybackButton = "stopPlaybackButton", replayButton = "replayButton", rerecordButton = "rerecordButton", editTranslationButton = "editTranslationButton", cancelCountdownButton = "cancelCountdownButton", translationEditor = "translationEditor", partnerDisplayButton = "partnerDisplayButton", partnerDisplayView = "partnerDisplayView", flipButton = "flipButton", closePartnerDisplayButton = "closePartnerDisplayButton", settingsButton = "settingsButton", permissionView = "permissionView", openSettingsButton = "openSettingsButton", recoveryButton = "recoveryButton"; static func card(_ index: Int) -> String /* "card.\(index)" */; static func language(_ l: PartnerLanguage) -> String /* "language.\(l.rawValue)" */ }`

畫面（直向）：上方語言選擇（五個 `displayName`）＋模式選擇（手動輪流／自動輪流 Beta）＋設定鈕；中央 `StatusView`（SF Symbol＋`statusText`＋partialTranscript＋notice；自動輪流顯示「現在輪到：對方／我」）；`AudioRouteView`（symbol＋displayName）；對話卡片列表（說話者、原文、翻譯、時間、重播鈕）；模式 B 待播時 `PlaybackControlsView`（倒數秒數、播放、停止、重播、重新錄音、編輯、取消倒數）；底部兩個大按鈕「對方說話」「我說中文」（listening 時文字變「說完了」）、緊急停止（紅色＋文字「全部停止」＋symbol）、「給對方看」、清除紀錄。`PermissionView`：說明為何需要＋`openSettingsButton`（`UIApplication.openSettingsURLString`）。錯誤狀態顯示 `userMessage`＋`recoveryButton`（`recovery.buttonTitle`）。`PartnerDisplayView`：全螢幕最新外語譯文，字級最大、`rotationEffect(.degrees(flipped ? 180 : 0))`。`SettingsView`：輸出方式、先確認再播、對方說完繼續聆聽、字體大小、顯示實際使用的中文代碼（zh-TW / zh-Hant-TW）、離線說明文字。所有文字支援 Dynamic Type（不用固定字級；`fontScale` 以 `.dynamicTypeSize` 或乘數套用）、深色模式用系統語意色。

- [ ] **Step 1:** 實作畫面
- [ ] **Step 2:** `scripts/ci.sh ios` → build success、warnings 0、既有 UI 測試 PASS（`testAppLaunches` 改成檢查 `partnerButton` 存在）
- [ ] **Step 3:** Commit `feat(app): main conversation UI, settings, partner display`

---

### Task 13: UI 測試

**Files:**
- Modify: `TalkBridgeUITests/TalkBridgeUITests.swift`

**Interfaces:**
- Consumes: `AccessibilityID`、`FakeScenario` raw values、launch arguments `-fakeScenario`、`-resetSettings`。

每個測試 `app.launchArguments = ["-fakeScenario", scenario, "-resetSettings"]`，用 `waitForExistence(timeout:)`，不用 sleep。fake 在 UI 測試模式下用真實時間的短設定（`ConversationConfiguration` 的 silence 0.3s、countdown 1s，由 `AppEnvironment` 在 fake 模式套用）讓流程自動跑完。

- [ ] **Step 1: 寫測試**：
  1. `testAppLaunches`
  2. `testLanguagePickerSelectsAllFive`（逐一選五個 `language.*`，選後 picker 顯示該 displayName）
  3. `testMainButtonsExistAndAreHittable`
  4. `testPermissionDeniedShowsPermissionView`（`permissionDenied`：tap partner → `permissionView` 與 `openSettingsButton` 出現）
  5. `testFakeModeShowsOriginalAndTranslation`（happyPath：tap partner → `card.0` 內含 "Where is the train station?" 與其譯文）
  6. `testPlaybackControls`（happyPath：tap user → 待播時 `cancelCountdownButton` → `editTranslationButton`、`playButton`、`stopPlaybackButton`、`replayButton`、`rerecordButton` 都可按且狀態文字隨之改變）
  7. `testClearHistory`（一輪後 clear → `card.0` 不存在）
  8. `testLargestDynamicTypeKeepsControlsVisible`（`-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL`；兩個大按鈕、stopAll 的 `frame` 完全在 `app.windows.firstMatch.frame` 內且 `isHittable`；按鈕 label 等於完整文字）
  9. `testAccessibilityIdentifiersExist`（主畫面所有 ID 存在）
  10. `testErrorStateHasRecoveryButton`（`translationFailure`：一輪後 `recoveryButton` 出現，按下回到「等待中」）
  11. `testPartnerDisplayOpensFlipsAndCloses`
  12. `testSpeakerOverrideFailureNoticeShown`（`speakerOverrideFails`：tap user 一輪 → `noticeView` 含「外語仍從耳機播出」）
- [ ] **Step 2:** `scripts/ci.sh ios` → 先看失敗原因，修 UI／accessibility（不是改測試）直到 PASS；summary 12 passed、0 failed、0 skipped
- [ ] **Step 3:** Commit `test(ui): XCUITest coverage with fake scenarios`

---

### Task 14: 文件、最終乾淨建置、下載 ipa

**Files:**
- Create: `README.md`、`docs/PhysicalDeviceTestPlan.md`

- [ ] **Step 1: README.md**，涵蓋原需求 §十三 18 項，並改寫：第 9–10 項＝Sideloadly＋免費 Apple ID 安裝流程（含 7 天到期、AutoRefresh、一支手機 3 個自裝 app 上限、設定→一般→VPN 與裝置管理 信任開發者、iOS 開發者模式）；第 11 項＝設定→一般→語言與地區→翻譯語言下載、App 內「下載語言」；第 12 項＝改寫成「藍牙耳機與手機喇叭」（§4 決定、無 HFP、切喇叭需實機驗證）；第 17–18 項＝從 Task 14 Step 3 的 CI log 與 summary 實際抄錄的命令與數字（不可憑記憶寫）。另含「為什麼用雲端 Mac」「API 版本差異」「哪些處理由 Apple 系統框架完成」「離線取決於模型下載」。
- [ ] **Step 2: PhysicalDeviceTestPlan.md**：原需求 §十二 20 項，每項都有「前置條件／步驟／預期結果／實際結果：＿＿／Pass/Fail：＿＿」表格；第 1 項改 Sideloadly；第 6 項改藍牙耳機；另加 21「耳機模式下外語是否真的從手機喇叭播出」、22「倒數 2 秒取消與編輯」、23「自動輪流固定交替與 15 秒暫停」、24「給對方看翻轉」。五種語言測試句用人工示例。
- [ ] **Step 3: 最終乾淨建置**：`workflow_dispatch` 觸發 `ios.yml`（runner 本來就是全新環境＋`-derivedDataPath DerivedData`），`scripts/ci.sh core` 與 `scripts/ci.sh ios` 皆 PASS；記下：Xcode/Swift 版本、模擬器、單元測試 passed/failed/skipped（Linux 與 iOS 模擬器兩份）、UI 測試數字、warnings 數。把數字寫進 README 第 18 項後再推一次。
- [ ] **Step 4: 下載 ipa** 到 `dist/TalkBridge-vN.ipa`（比照 voicejournal：API 取 artifact，302 那一跳不帶 Authorization）。`dist/` 在 `.gitignore`。
- [ ] **Step 5:** Commit `docs: README and physical device test plan`；最終回報照原需求 §十六 14 項（第 11–12 項改 Sideloadly），所有數字來自 CI 實際輸出。
