# TalkBridge

雙向、輪流說話的即時語音翻譯 iPhone App。對方說外語時，太太從耳機（或手機喇叭）聽到繁體中文；太太說中文時，外語從手機喇叭播給對方聽，螢幕同時顯示大字。

> 文件：設計 `docs/superpowers/specs/2026-11-07-talkbridge-design.md`（v2 變更：`2026-11-07-auto-language-design.md`）、計畫 `docs/superpowers/plans/2026-11-07-talkbridge.md`（v2：`2026-11-07-v2-next-speaker.md`）、原始需求 `docs/original-requirements.md`、實機測試 `docs/PhysicalDeviceTestPlan.md`。

## 1. App 目標

- 對方說英文、印尼文、泰文、日文或韓文 → 辨識 → 翻成繁體中文 → 用中文語音念出。
- 太太說中文 → 辨識 → 翻成對方語言 → 倒數 2 秒後用該語言語音播出（可取消、編輯、重播、重新錄音）。
- 一人說完、另一人再說的半雙工流程；不宣稱同步口譯或零延遲。
- **連續說好幾句**：翻譯、倒數或播放中按「我說中文」或「對方說話」，不會打斷這一句，App 會記住「下一句換誰說」（畫面顯示「下一句：…」），這句播完再聽指定的人。
- 狀態區顯示麥克風狀態：「現在可以說話：中文／英文…」或「請稍等，麥克風已關閉」。
- 對話進行中螢幕不會自動鎖定（回到待機後恢復）。
- 自動輪流：聽到雜音或喇叭殘響會自動忽略、繼續聽；60 秒沒人說話才暫停；聆聽中也能按卡片重播。
- 翻譯失敗按「再試一次」會用同一句文字重新翻譯，不用重講。
- 所有處理都用 Apple 系統框架，不用第三方雲端服務，沒有 API Key。

## 2. 系統需求

- iPhone，iOS 18.0 以上（實際測試裝置：iPhone 17 系列、iOS 26.6.2）。
- 直向介面。
- 一般藍牙耳機或手機喇叭（AirPods 也可以，但不是必要）。

## 3. Xcode 版本

開發者的電腦是 Windows、沒有 Mac，所以**所有建置與測試都在 GitHub Actions 的雲端 Mac 上執行**：

- Runner：`macos-15`，自動選用最新的正式版 Xcode（實際：**Xcode 26.3**、**Swift 6.2.4**，iOS 26.2 模擬器）。
- 專案檔由 XcodeGen 從 `project.yml` 產生（`.xcodeproj` 不進 git）。
- 核心邏輯另外在 Linux（`swift:6.2` 容器）跑單元測試，作為快速的 TDD 迴圈。

## 4. iOS 最低版本

iOS 18.0。iOS 26 才有的 API 都以 `#available` 判斷；目前沒有用到只限 iOS 26 的 API。

## 5. 使用的 Apple frameworks

| 框架 | 用途 |
|---|---|
| Speech（`SFSpeechRecognizer`） | 語音辨識。該語言支援裝置端辨識時強制在手機上辨識；不支援時由 Apple 伺服器辨識，畫面會標示「需要網路」。 |
| Translation（`LanguageAvailability`、`.translationTask`、`TranslationSession`） | 翻譯與語言資料下載。 |
| AVFoundation（`AVAudioEngine`、`AVAudioSession`、`AVSpeechSynthesizer`） | 收音、音訊路由、語音合成。 |
| SwiftUI＋Observation | 畫面與狀態。 |
| XCTest、XCUITest | 單元測試與 UI 測試。 |

沒有任何第三方套件、分析或廣告 SDK。

## 6. 架構

```
Packages/TalkBridgeCore/           本機 Swift 套件（不 import 任何 iOS 專屬框架，可在 Linux 測試）
  Sources/TalkBridgeCore/
    Models/          語言、翻譯方向、對話紀錄、狀態、音訊路由、accessibility ID
    Configuration/   ConversationConfiguration（所有時間數值）、AppSettings
    Utilities/       AppError（繁中訊息＋復原動作＋開發分類）、LocaleMapping
    Services/        五個 service protocol、Sleeper（可注入的時間）
    StateMachine/    ConversationStateMachine、UtteranceEndDetector
    ViewModels/      ConversationViewModel（總指揮）、SettingsViewModel
  Sources/TalkBridgeFakes/         測試與 UI 測試模式專用的假服務（與正式實作分開）
  Tests/TalkBridgeCoreTests/       單元測試
TalkBridge/                        App target（iOS 專屬）
  App/        TalkBridgeApp、AppEnvironment（組裝正式或假服務）
  Services/   Apple*Service（Speech / Translation / AVFoundation 的正式實作）、TranslationHostView
  Views/      SwiftUI 畫面
TalkBridgeUITests/                 XCUITest
```

重點決策：

- **Protocol＋依賴注入**：ViewModel 只認得 `SpeechRecognitionService`、`TranslationService`、`SpeechSynthesisService`、`AudioSessionService`、`PermissionService`。
- **明確的狀態機**：所有狀態變化都經過 `ConversationStateMachine`；硬規則是「播放中不能直接進入聆聽」，播放結束、再等 0.3 秒保護間隔才會重新開麥克風，避免把自己的聲音再辨識一次。
- **同一時間只有一個工作**：開始新工作前一定先取消舊工作；連續按鈕不會重複開錄音引擎；停止後回來的翻譯結果會丟棄。
- **翻譯集中整合**：Translation framework 只能透過 SwiftUI 的 `.translationTask` 取得 session，整個 App 只有 `TranslationHostView` 一處使用它，由 `AppleTranslationService` 的工作佇列驅動。
- **可測試的時間**：停頓秒數（預設 2 秒，設定可調 1.2–4 秒）、最長 30 秒、倒數 2 秒等都透過注入的 `Sleeper` 計時，測試用 `ManualSleeper` 精準推進虛擬時間，不用固定 sleep。

## 7. 如何建置

雲端（主要方式）：推送到 `main` 會自動觸發；也可以在 GitHub Actions 頁面手動執行 `ios` workflow。

在 Mac 上自行建置（如果日後有 Mac）：

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project TalkBridge.xcodeproj -scheme TalkBridge -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=<實際存在的 iPhone 模擬器>" -derivedDataPath ./DerivedData build
```

## 8. 如何執行測試

```bash
# 核心單元測試（Linux 或 Mac 都可以）
swift test --package-path Packages/TalkBridgeCore

# 核心單元測試（iOS 模擬器）
cd Packages/TalkBridgeCore && xcodebuild test -scheme TalkBridgeCore-Package -destination "$DEST"

# App 建置＋UI 測試
xcodebuild test -project TalkBridge.xcodeproj -scheme TalkBridge -destination "$DEST" -derivedDataPath DerivedData
```

`$DEST` 由 `scripts/pick_simulator.sh` 從實際存在的模擬器挑選。開發時用 `scripts/ci.sh core|ios` 推送並等待雲端結果。

UI 測試用 launch argument 切換假服務情境（只在 Debug 版有效）：`-fakeScenario happyPath | permissionDenied | translationFailure | languageNotReady | speakerOverrideFails`，`-resetSettings` 清除設定。

## 9. Apple Developer Team 設定

**不需要付費的 Apple Developer 帳號，也不用在 Xcode 設定 Team。** 雲端產生的是**未簽章**的 ipa，由 Sideloadly 用免費 Apple ID 簽章。限制：

- 免費 Apple ID 簽的 App **7 天後到期**，要重新簽（Sideloadly 的 AutoRefresh 可以自動續簽，電腦要開著、和 iPhone 在同一個網路或有連線）。
- 一支 iPhone 最多 3 個用免費帳號自行安裝的 App（含天氣日誌）。

## 10. 如何安裝到實體 iPhone

1. 到 GitHub Actions 的 `ios` workflow 最新成功執行，下載 artifact `TalkBridge-vN-ipa`（裡面是 `TalkBridge-vN.ipa`）。
2. Windows 電腦用官網版 iTunes（不是 Microsoft Store 版）＋ Sideloadly。
3. iPhone 用傳輸線接電腦，按「信任這部電腦」。
4. Sideloadly：選 ipa、填 Apple ID、按 Start。
5. iPhone：設定 → 一般 → VPN 與裝置管理 → 信任該開發者。
6. 若要求開發者模式：設定 → 隱私權與安全性 → 開發者模式 → 開啟並重開機。

## 11. 如何準備語言及翻譯資料

- 翻譯資料：iPhone 設定 → 一般 → 語言與地區，往下捲到最底的「翻譯語言」（iOS 18 以後也可走 設定 → App → 翻譯 → 已下載的語言；找不到就略過），下載英文、印尼文、泰文、日文、韓文與中文（繁體）。也可以在 App 裡遇到「語言模型尚未準備」時按「下載語言」，由系統視窗下載。
- 語音：設定 → 輔助使用 → 閱讀與朗讀（舊版叫「朗讀內容」）→ 聲音 → 選語言 → 選地區，下載名字標「增強音質」或「高品質」的聲音；App 預設自動用品質最好的那個（不用趣味語音），也可以在 App 的「設定 → 翻譯時用的聲音」替每個語言自己挑、按 ▶ 試聽（對話進行中不能試聽）。挑的聲音之後被刪掉會自動退回「自動」。**Siri 聲音（Siri 聲音 1／2）Apple 不開放給第三方 App**，不會出現在清單。找不到某語言的精確語音時，App 會改用同語言最接近的語音並提示。
- App 會在開始前用 `LanguageAvailability` 檢查語言組合；不支援時顯示「換一種語言」，不會假裝可以用。

## 12. 藍牙耳機、AirPods 與音訊路由限制

- AVAudioSession：`.playAndRecord`＋`.allowBluetoothA2DP`＋`.defaultToSpeaker`，**刻意不開 HFP**。所以：
  - 收音一律用 **iPhone 內建麥克風**（太太說中文時對著手機說）。
  - 有藍牙耳機時，播放走耳機（高音質）；沒有耳機時走手機喇叭。
  - 只支援 HFP 的耳機不會被使用，聲音會從手機喇叭出來。
- iPhone **不能**同時把兩個不同的聲音分別送到耳機和喇叭。所以有耳機時：
  - 中文（給太太）從耳機播。
  - 外語（給對方）播放時用公開 API `overrideOutputAudioPort(.speaker)` **暫時**切到手機喇叭，播完切回。
  - 一般藍牙耳機能不能切過去**要實機驗證**。App 會讀回實際路由；如果仍在耳機上，畫面顯示「外語仍從耳機播出，請改用「給對方看」或在設定改成一律用手機喇叭。」
- 設定可選「一律用手機喇叭」：兩個方向都從喇叭出來。
- 耳機在播放或聆聽中斷線：立即停止（避免中文突然從喇叭大聲播出），顯示錯誤與「再試一次」。

## 13. 模擬器不能驗證的功能

- 真實麥克風收音與語音辨識、各語言是否支援裝置端辨識。
- Apple Translation 的實際翻譯與語言資料下載（模擬器不支援）。
- 藍牙耳機路由、切換到喇叭是否成功。
- 實際語音合成的聲音與可用語音。
- 來電中斷、耗電與發熱。

這些都列在 `docs/PhysicalDeviceTestPlan.md`，在 iPhone 上逐項驗證。

## 14. 隱私設計

- 錄音只在記憶體裡串流給辨識，**不存檔**。
- 對話紀錄只在記憶體，**關閉 App 就消失**；設定只存偏好（UserDefaults），不含任何對話。
- log 只記狀態名稱與錯誤分類，**不記錄任何說話內容**。
- 權限在第一次使用功能時才請求，拒絕時提供「前往設定」。
- 辨識、翻譯、語音合成都由 Apple 系統框架完成：
  - 語音辨識：支援裝置端的語言在手機上完成；不支援的語言由 Apple 伺服器處理（畫面標示）。
  - 翻譯：Apple Translation，語言資料下載後在手機上翻譯。
  - 語音合成：AVSpeechSynthesizer，在手機上完成。
- 沒有分析、廣告或第三方追蹤。

## 15. 已知限制

- **不宣稱完全離線**：能不能離線取決於語言資料是否已下載，以及 Apple 對該語言是否支援裝置端辨識。
- 一般藍牙耳機下「外語暫時改從喇叭播」尚未實機驗證。
- 不會自動判斷誰在說話（Kevin 2026-11-07 決定改由按鈕指定下一句）；吵雜環境下停頓判斷可能較慢（開始說話後最長 30 秒一定結束，也可隨時按鈕結束）。
- 播放時麥克風關著，這段時間說的話不會被收到（畫面會提示）。
- `TranslationSession` 不是 Sendable，App 以單一 Task 依序使用並用 `@unchecked Sendable` 的盒子傳遞（理由見程式註解）。
- 免費 Apple ID 簽章 7 天到期。

## 16. 下一版建議

- 實機驗證後，依結果決定耳機模式的預設輸出方式。
- 評估 iOS 26 的 `SpeechAnalyzer`／`SpeechTranscriber`（新的裝置端辨識 API），比較五種語言的離線支援度。
- 實機確認喇叭殘響過濾的門檻（`echoSimilarityThreshold` 0.8）。
- 可選的對話匯出（目前刻意不保存）。

## 17. 實際執行過的 build／test 命令

以下由 GitHub Actions 的實際 log 抄錄（每次都是全新的雲端環境，等同乾淨建置）。

Linux（`core.yml`，容器 `swift:6.2`，Swift 6.2.4）：

```bash
swift --version
swift test --package-path Packages/TalkBridgeCore
```

macOS（`ios.yml`，`macos-15`，Xcode 26.3 build 17C529，Swift 6.2.4，模擬器 iPhone 17 Pro／iOS 26.2）：

```bash
sudo xcode-select -s /Applications/Xcode_26.3.0.app/Contents/Developer
xcodebuild -version && swift --version && xcodebuild -showsdks && xcrun simctl list devices available
brew install xcodegen && xcodegen generate
DEST=$(bash scripts/pick_simulator.sh)      # → platform=iOS Simulator,id=<iPhone 17 Pro 的 UDID>
cd Packages/TalkBridgeCore && xcodebuild test -scheme TalkBridgeCore-Package -destination "$DEST" \
  -derivedDataPath ../../DerivedData-core -resultBundlePath ../../CoreTests.xcresult
xcodebuild test -project TalkBridge.xcodeproj -scheme TalkBridge -destination "$DEST" \
  -derivedDataPath DerivedData -resultBundlePath UITests.xcresult
xcrun xcresulttool get test-results summary --path UITests.xcresult --format json
xcodebuild -project TalkBridge.xcodeproj -scheme TalkBridge -configuration Release -sdk iphoneos \
  -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
```

## 18. 最終測試結果摘要

最終驗證的程式版本：commit `5abbb3f`（2026-11-07，加入可調停頓秒數）。

| 項目 | 結果 |
|---|---|
| Linux 單元測試（core-tests，commit 5abbb3f） | 119 個，通過 119、失敗 0、略過 0 |
| iOS 模擬器單元測試（ios #37） | 119 個，通過 119、失敗 0、略過 0 |
| iOS UI 測試（ios #37） | 14 個，通過 14、失敗 0、略過 0 |
| 本專案程式的編譯警告 | 0 |
| App 建置（Debug 模擬器、Release iphoneos 未簽章） | 成功，產生 `TalkBridge-v37.ipa` |
| 實機測試 | **尚未執行**，見 `docs/PhysicalDeviceTestPlan.md` |

整體審查（另一個模型唯讀審查全部程式）：沒有 Critical；6 個 Important 已修正（能自動測的 3 項都先寫了會失敗的測試）；6 個 Minor 留到下一版，清單在 `docs/superpowers/progress.md`。
