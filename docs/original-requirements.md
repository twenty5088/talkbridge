# TalkBridge 原始需求（Kevin 於 2026-11-07 提供，逐字保存）

> 本文件是 Kevin 提供的原始需求全文。與後續討論衝突之處，以
> `docs/superpowers/specs/2026-11-07-talkbridge-design.md` 的「決定與覆寫」為準。

你是一位資深 iOS 架構師、Swift 工程師、音訊工程師與測試工程師。請直接在目前目錄建立一個可編譯、可測試，並可安裝到實體 iPhone 的完整原生 iOS App 專案。

你必須實際建立和編輯程式碼、測試程式、專案設定與必要文件，不要只提供教學、虛擬碼或程式碼片段。請在每個階段執行建置與測試，遇到錯誤時自行分析、修改並重新測試，直到專案可以成功建置，或遇到只有使用者才能處理的簽章、實體裝置授權或系統資源限制。

# 一、產品目標

建立一個雙向即時語音翻譯 iPhone App，暫定名稱為「TalkBridge」。

主要使用情境：

1. 我的妻子使用 AirPods 或其他藍牙耳機。
2. 對方說話時：
   - iPhone 麥克風接收對方語音。
   - App 自動辨識對方語言或使用預先選定的語言。
   - 將語音轉成文字。
   - 將文字翻譯成繁體中文。
   - 使用中文語音合成，讓妻子透過耳機聽到翻譯。
3. 妻子說中文時：
   - App 辨識中文語音。
   - 將中文翻譯成對方所選語言。
   - 使用對方語言的語音合成播放翻譯，讓對方聽到。
4. App 必須同時顯示：
   - 原文
   - 翻譯文字
   - 目前說話方向
   - 麥克風、辨識、翻譯與播放狀態
5. 優先採用一人說完、另一人再說的輪流對話模式，而不是宣稱真正零延遲或完全同時雙工。
6. 所有語音及翻譯資料應盡可能留在裝置端，不使用第三方雲端翻譯 API，不加入 API Key。

# 二、技術限制

請使用：

- Swift
- SwiftUI
- async/await
- Observation 或 ObservableObject，依部署版本選擇最穩定方案
- Apple Speech framework
- Apple Translation framework
- AVFoundation
- AVAudioSession
- AVAudioEngine 或 Apple 官方目前最合適的即時音訊擷取 API
- AVSpeechSynthesizer
- XCTest
- XCUITest

部署目標：

- iOS 18.0 或更高版本
- Xcode 16 或目前環境可使用的更新版本
- 必須支援實體 iPhone
- 以直向介面為主
- 不使用任何第三方套件，除非 Apple 原生 API 無法達成，而且必須先停下來清楚說明原因，不可自行加入雲端服務

請先檢查本機安裝的 Xcode 與 Swift 版本，再根據實際 SDK 調整 API。不要假設不存在的 Apple API。若 Apple API 版本有差異，請以本機 SDK 中可以成功編譯的正式 API 為準。

# 三、語言需求

目標中文：

- 繁體中文，優先使用 zh-TW
- 若部分 Apple API 只支援其他中文 locale，必須偵測並清楚顯示實際使用的 locale

對方語言至少包含：

- 英文：en-US
- 印尼文：id-ID
- 泰文：th-TH
- 日文：ja-JP
- 韓文：ko-KR

翻譯方向：

- 英文 ↔ 繁體中文
- 印尼文 ↔ 繁體中文
- 泰文 ↔ 繁體中文
- 日文 ↔ 繁體中文
- 韓文 ↔ 繁體中文

啟動翻譯前，必須以 Apple 的 LanguageAvailability 或目前 SDK 對應 API 檢查該語言組合是否可用。

如果語言不支援、語言模型未下載或系統需要使用者同意下載，App 必須提供明確操作指引，不可以崩潰或假裝功能可用。

# 四、重要可行性原則

請務必誠實處理 Apple 平台限制：

1. 不要假設 iPhone 可以將兩個不同的音訊串流同時輸出到 AirPods 和手機喇叭。
2. 實作前先確認 AVAudioSession 在目前 iOS SDK 下的路由能力。
3. 如果系統無法同時做到：
   - 中文翻譯只進 AirPods
   - 對方語言翻譯只由手機喇叭播放
   請採用可靠的替代方案，不要使用私有 API。
4. 建議替代流程：
   - 「對方說話」模式：翻譯內容播放到目前耳機音訊路由。
   - 「我方說話」模式：完成中文辨識及翻譯後，畫面顯示大字翻譯，並提供明確的「播放給對方」按鈕。
   - 若必須切換到手機喇叭，只有在 Apple 公開 API 確實支援且不會破壞錄音流程時才執行。
5. 第一版以穩定的半雙工、輪流說話模式為主。
6. 不得在語音合成播放時繼續辨識相同輸出，避免 App 把自己的播放聲音再次辨識，形成回音循環。
7. 使用狀態機控制錄音、辨識、翻譯與播放，禁止重複啟動錄音引擎。
8. 不宣稱完全離線。請在 UI 及 README 說明，是否可以離線取決於語言模型與語音資源是否已下載，以及 Apple 對特定語言的支援狀態。

# 五、核心使用流程

## 模式 A：對方說話，翻譯成中文

流程：

idle
→ listeningToPartner
→ transcribingPartner
→ translatingToChinese
→ speakingChinese
→ idle

要求：

1. 使用選定語言進行語音辨識。
2. 畫面即時顯示 partial transcript。
3. 取得 final transcript 或偵測到停頓後再送翻譯。
4. 將文字翻譯成繁體中文。
5. 顯示原文與中文翻譯。
6. 使用適合 zh-TW 的 AVSpeechSynthesisVoice 播放。
7. 播放時暫停語音辨識。
8. 播放完成後回到待機或繼續聆聽，依設定決定。

## 模式 B：妻子說中文，翻譯給對方

流程：

idle
→ listeningToUser
→ transcribingChinese
→ translatingToPartnerLanguage
→ readyToPlayForPartner
→ speakingPartnerLanguage
→ idle

要求：

1. 使用 zh-TW 進行語音辨識。
2. 翻譯成目前選定的對方語言。
3. 顯示中文原文與翻譯結果。
4. 預設讓使用者確認後才播放，避免錯誤翻譯立即播出。
5. 提供：
   - 播放
   - 停止
   - 重播
   - 重新錄音
   - 編輯翻譯文字
6. 使用目標語言對應的 AVSpeechSynthesisVoice。
7. 如果找不到精確 locale 的語音，選擇同語言最接近的系統語音並顯示提示。

## 模式 C：自動輪流對話

第一版可以是實驗功能。

需求：

1. 使用語音活動或停頓判斷一句話結束。
2. 必須有合理的 debounce、silence timeout 及最大錄音時間。
3. 預設值可設為：
   - 停頓判定：1.2 秒
   - 最短有效語句：非空且至少包含一個可辨識字詞
   - 單次最長錄音：30 秒
4. 上述數值必須集中在設定結構中，方便調整。
5. 如果自動判斷不可靠，使用者可以切換至手動按鍵模式。

# 六、UI/UX 要求

主畫面包含：

1. 對方語言選擇器：
   - English
   - Bahasa Indonesia
   - ไทย
   - 日本語
   - 한국어
2. 對話模式選擇：
   - 手動輪流
   - 自動輪流 Beta
3. 兩個大型按鈕：
   - 「對方說話」
   - 「我說中文」
4. 中央狀態區：
   - 等待中
   - 正在聆聽
   - 正在辨識
   - 正在翻譯
   - 正在播放
   - 需要權限
   - 語言模型尚未準備
   - 發生錯誤
5. 對話卡片：
   - 說話者
   - 原文
   - 翻譯
   - 時間
   - 重播按鈕
6. 音訊輸出狀態：
   - AirPods
   - Bluetooth
   - iPhone Speaker
   - Receiver
   - Unknown
7. 清除對話紀錄按鈕。
8. 停止所有動作的緊急停止按鈕。
9. 字體大小設定。
10. 支援 Dynamic Type、VoiceOver、深色模式和足夠的顏色對比。
11. 所有錯誤訊息使用一般使用者能理解的繁體中文。
12. 不要只用顏色表示狀態。

# 七、權限與隱私

正確加入並使用：

- NSMicrophoneUsageDescription
- NSSpeechRecognitionUsageDescription

權限流程：

1. 首次使用功能時才請求權限。
2. 解釋為何需要麥克風與語音辨識權限。
3. 如果拒絕權限，顯示前往 iOS 設定的操作按鈕。
4. App 不得偷偷保存原始錄音。
5. 第一版預設只在記憶體中保留目前對話。
6. 關閉 App 後不保留對話內容。
7. 不加入分析 SDK、廣告 SDK或第三方追蹤。
8. README 必須說明哪些處理由 Apple 系統框架完成。
9. 不記錄使用者實際說話內容到 console。
10. 測試資料只能使用人工建立的示例句子，不可包含真實個資。

# 八、建議架構

請依職責拆分，避免把所有邏輯放在 ContentView。

建議結構：

```
TalkBridge/
  App/
    TalkBridgeApp.swift
  Models/
    SupportedLanguage.swift
    ConversationEntry.swift
    TranslationDirection.swift
    ConversationState.swift
    AudioRouteInfo.swift
  Services/
    SpeechRecognitionService.swift
    TranslationService.swift
    SpeechSynthesisService.swift
    AudioSessionService.swift
    PermissionService.swift
  ViewModels/
    ConversationViewModel.swift
    SettingsViewModel.swift
  Views/
    ContentView.swift
    ConversationView.swift
    ConversationCardView.swift
    LanguagePickerView.swift
    PermissionView.swift
    SettingsView.swift
    AudioRouteView.swift
  Configuration/
    ConversationConfiguration.swift
  Utilities/
    AppError.swift
    LocaleMapping.swift
  Resources/
    Localizable.xcstrings
  Tests/
  UITests/
```

架構要求：

1. 使用 protocol 抽象 SpeechRecognitionService、TranslationService 和 SpeechSynthesisService。
2. ViewModel 透過 dependency injection 接收服務。
3. 測試時使用 mock 或 fake services。
4. 所有 UI 狀態更新在 MainActor 執行。
5. 避免 retain cycle。
6. 正確取消 Task、語音辨識 request 和音訊 tap。
7. App 進入背景、電話插入、耳機斷線或音訊中斷時安全停止工作。
8. 處理 AVAudioSession interruption 與 route change notification。
9. 使用明確、可測試的狀態機。
10. 不要將 TranslationSession 直接散落在多個 View 中。請設計符合 Apple Translation framework 生命週期限制的集中整合方式。

# 九、錯誤處理

至少處理：

- 麥克風權限被拒絕
- 語音辨識權限被拒絕
- Speech recognizer 不可用
- 語言不支援
- Translation model 未下載
- 使用者取消模型下載
- 沒有辨識到語音
- 空白辨識結果
- 翻譯失敗
- 語音合成中斷
- AudioSession 啟動失敗
- AirPods 或藍牙耳機中途斷線
- App 進入背景
- 電話或其他 App 中斷音訊
- 使用者快速重複點擊按鈕
- 同一時間重複啟動兩個翻譯工作
- Task cancellation
- 超過單次錄音時間
- 實體裝置缺少必要語言資源

每個錯誤需要：

- 對使用者友善的繁體中文訊息
- 可行的復原操作
- 開發用錯誤分類
- 不得顯示敏感內容

# 十、自動測試要求

你必須自行建立測試，而且必須實際執行。

## 單元測試

至少測試：

1. 五種語言和繁體中文的 locale mapping。
2. TranslationDirection 的雙向切換。
3. 正常狀態流程。
4. 不允許的狀態轉換。
5. 空白辨識結果不進行翻譯。
6. 翻譯服務失敗。
7. 語音辨識失敗。
8. 語音播放失敗或取消。
9. 使用者連續點擊開始按鈕。
10. 新任務開始時取消舊任務。
11. 播放期間不啟動麥克風辨識。
12. 停止按鈕會取消所有工作。
13. 權限拒絕狀態。
14. 語言不支援狀態。
15. ViewModel 的 published 或 observable UI 狀態。
16. ConversationEntry 順序與清除。
17. AppError 到繁體中文訊息的 mapping。
18. Audio route 顯示 mapping。
19. silence timeout 與最長錄音時間設定。
20. 服務呼叫是否在正確順序發生。

## UI 測試

至少測試：

1. App 正常啟動。
2. 語言選擇器能選擇五種語言。
3. 兩個主要說話按鈕存在且可操作。
4. 權限不足時顯示適當畫面。
5. mock 模式下能顯示原文與翻譯。
6. 播放、停止、重播、重新錄音按鈕可操作。
7. 清除對話紀錄。
8. Dynamic Type 下主要控制項不被截斷。
9. VoiceOver accessibility identifier 存在。
10. 錯誤狀態有復原按鈕。

## 整合測試策略

Translation、Speech 和實際麥克風功能可能無法在模擬器完整測試，因此：

1. 將 Apple framework 包裝在 service protocol 後方。
2. 模擬器與 CI 使用 deterministic fake services。
3. 針對實體裝置另外提供手動整合測試清單。
4. 不要讓測試依賴真實網路、真實語音辨識結果或尚未下載的語言模型。
5. 不要用固定 sleep 等待非同步結果，使用 XCTestExpectation 或 async test。
6. 測試不得互相依賴。
7. 為 UI 測試加入 launch arguments，啟用 mock service、權限拒絕、翻譯失敗等情境。

# 十一、自動建置與修正流程

請依序執行：

1. 檢查：
   - xcodebuild -version
   - swift --version
   - 可用 SDK
   - 可用 simulator destination
2. 建立專案。
3. 建立最小可編譯版本。
4. 執行 build。
5. 修正所有 compile error。
6. 建立 service protocols 和 mock implementations。
7. 建立單元測試。
8. 執行單元測試。
9. 修正失敗測試。
10. 建立 UI 測試。
11. 執行 UI 測試。
12. 修正 UI 測試或 accessibility 問題。
13. 執行乾淨建置：
    - 清除 DerivedData 或使用乾淨的 derivedDataPath
    - 執行完整 build 與 test
14. 執行 Swift compiler warnings 檢查。
15. 不可用刪除測試、降低 assertion、跳過測試或把錯誤吞掉的方式讓測試通過。
16. 如果本機沒有可用 simulator，仍需完成專案與測試程式，並記錄未執行的精確原因及可執行命令。
17. 如果因 code signing 無法安裝實體 iPhone，不要停在模糊錯誤。請整理使用者必須在 Xcode 完成的 Signing & Capabilities 步驟。

如果環境支援，使用類似以下方式建置，請根據實際 scheme、project 或 workspace 名稱調整：

```
xcodebuild \
  -project TalkBridge.xcodeproj \
  -scheme TalkBridge \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=<實際存在的模擬器>' \
  -derivedDataPath ./DerivedData \
  build
```

執行測試時，使用實際存在的 simulator destination，不要硬編不存在的型號或 OS 版本。

# 十二、實體 iPhone 驗收功能

提供一份 PhysicalDeviceTestPlan.md，至少包含：

1. 安裝與簽章步驟。
2. 麥克風權限測試。
3. 語音辨識權限測試。
4. 五種語言分別測試。
5. 每種語言雙向翻譯測試。
6. AirPods 連接前、連接後和中途斷線測試。
7. 手機喇叭播放測試。
8. 靜音環境測試。
9. 吵雜環境測試。
10. 快速輪流說話測試。
11. 長句和短句測試。
12. 語言模型尚未下載的測試。
13. 飛航模式或無網路測試，用來確認哪些功能可離線。
14. App 進入背景和回到前景測試。
15. 電話或其他音訊中斷測試。
16. VoiceOver 測試。
17. 大字體測試。
18. 電量消耗和裝置發熱觀察。
19. 實際輸出路由是否符合 UI 顯示。
20. 確認 App 不會把自己播放的翻譯再次辨識。

每一項必須包含：

- 前置條件
- 測試步驟
- 預期結果
- 實際結果欄位
- Pass/Fail 欄位

# 十三、README 要求

建立完整 README.md，說明：

1. App 目標。
2. 系統需求。
3. Xcode 版本。
4. iOS 最低版本。
5. 使用的 Apple frameworks。
6. 架構。
7. 如何建置。
8. 如何執行測試。
9. 如何設定 Apple Developer Team。
10. 如何安裝到實體 iPhone。
11. 如何準備語言及翻譯模型。
12. AirPods 與音訊路由限制。
13. 模擬器不能驗證的功能。
14. 隱私設計。
15. 已知限制。
16. 下一版建議。
17. 實際執行過的 build/test 命令。
18. 最終測試結果摘要。

# 十四、程式品質要求

1. 所有程式碼必須可讀且符合 Swift 命名慣例。
2. 避免過度設計，但必須可測試。
3. 不使用 force unwrap，除非有不可避免且能證明安全的理由。
4. 不使用 try!。
5. 不忽略 cancellation。
6. 對 Apple framework 的 callback 正確切換到 MainActor。
7. 不在主執行緒進行長時間阻塞。
8. 為關鍵音訊和狀態機邏輯加入必要註解。
9. 不把權限、音訊、翻譯和 UI 邏輯混在同一個型別。
10. 不要建立假功能或只會顯示假結果的正式實作。
11. 測試用 mock 必須和 production implementation 明確分開。
12. 若使用尚未普及或有 availability 限制的 API，必須加入 @available 或替代處理。

# 十五、執行方式

開始時請先：

1. 檢查目前目錄內容，避免覆蓋既有重要檔案。
2. 顯示簡短實作計畫。
3. 檢查 Xcode、Swift 及 SDK 版本。
4. 確認 Apple Translation、Speech 與 AVFoundation 在目前 SDK 的實際 API。
5. 建立專案並開始實作，不要在每一個小步驟等待我確認。

只有以下情況才需要停下來詢問：

- 即將覆蓋既有非本專案檔案
- 需要我的 Apple Developer Team ID
- 需要我在實體 iPhone 上核准 Developer Mode 或信任憑證
- Apple 公開 API 無法實現核心需求，而且替代方案會明顯改變產品行為
- 需要付費服務或第三方套件

其他一般技術決策請自行選擇合理方案並記錄在 README。

# 十六、最終回報格式

完成後請提供：

1. 專案檔案結構。
2. 已完成功能。
3. 尚未完成或受 Apple 平台限制的功能。
4. 使用的框架及架構決策。
5. 實際執行的 build 命令。
6. 實際執行的 test 命令。
7. Build 結果。
8. 單元測試結果，包括通過、失敗與跳過數量。
9. UI 測試結果。
10. Compiler warnings。
11. 如何在 Xcode 選擇我的 Development Team。
12. 如何安裝到實體 iPhone。
13. 實體裝置仍需手動驗證的項目。
14. 已知的 AirPods 和音訊路由限制。

禁止只回覆「程式碼已完成」或「測試已通過」。所有成功聲明必須以實際執行結果為依據。

現在開始檢查環境、建立專案、實作、建置、測試並自行修正問題。
