# TalkBridge 設計文件

日期：2026-11-07
狀態：待 Kevin 核准
完整原始需求：`docs/original-requirements.md`（以下稱「原需求」，章節編號沿用）。
本文件只寫**原需求之外的決定、覆寫與補充**；沒提到的部分一律照原需求做。

標記說明：
- 【Kevin 決定】＝Kevin 在對話中明確選擇的
- 【Claude 判斷】＝Claude 代為決定，Kevin 審核時可推翻

---

## 1. 目的與使用情境

Kevin 的太太在面對面場合（對方說英文、印尼文、泰文、日文或韓文）用 iPhone 當口譯：
- 對方說話 → 太太從耳機（或手機喇叭）聽到中文。
- 太太說中文 → 對方從手機喇叭聽到外語，螢幕也顯示大字。

成功的樣子：兩個人能用「一人說完、另一人再說」的節奏完成一段簡單對話，太太不需要看說明就會用，App 不會把自己播出的聲音當成新的一句。

失敗的樣子（反目標）：
- 宣稱可以離線或即時同步口譯，實際上做不到。
- 錯誤翻譯在太太來不及阻止時就播出去（所以有 2 秒倒數，見 §4.3）。
- 自己播的聲音被重新辨識，形成回音循環。
- 錄音被偷偷存檔，或對話內容寫進 log。

## 2. 開發環境與交付方式（覆寫原需求 §十一、§十二第 1 項、§十三第 9–10 項、§十六第 11–12 項）

**Kevin 只有 Windows 電腦，沒有 Mac、沒有本機 Xcode、沒有付費 Apple Developer 帳號。** 沿用錄音日誌（`C:\Users\Kevin\voicejournal`）已經跑通的做法：

| 項目 | 做法 |
|---|---|
| 專案位置 | `C:\Users\Kevin\talkbridge`（獨立資料夾，不動錄音日誌） |
| 原始碼管理 | git，新建 GitHub **私人** repo `twenty5088/talkbridge`；推送方式比照 voicejournal（部署金鑰或 `git credential fill` 取 token；🔴 GCM 在 Claude 環境跑不起來，別試） |
| 專案檔 | XcodeGen `project.yml` 產生 `.xcodeproj`（`.xcodeproj` 不進 git） |
| 編譯與測試 | GitHub Actions 雲端 Mac：產生專案 → 模擬器 build → 單元測試 → UI 測試 → 乾淨建置 → 未簽章 Release ipa，ipa 與 `.xcresult`／測試摘要都當 artifact 上傳 |
| 「實際執行過的命令」 | 原需求要求本機執行的 `xcodebuild -version`、`swift --version`、`xcrun simctl list` 等，全部改在 Actions 上執行並印進 log；Claude 透過 GitHub API 讀 log／artifact 判讀結果，失敗就修完重推 |
| 模擬器 | 用 Actions runner 上實際存在的模擬器；workflow 先列出可用 destination 再挑，不寫死型號 |
| 簽章與安裝 | **不用 Xcode Signing & Capabilities。** 用 Sideloadly（Windows）＋太太的免費 Apple ID 簽章安裝，7 天到期，開 AutoRefresh。README 與實機測試計畫寫 Sideloadly 步驟；免費帳號的限制（7 天、一支手機最多 3 個自裝 app）要寫清楚 |
| 版本號 | 比照 voicejournal：版本＝Actions 執行序號，設定頁顯示「第 N 版」，ipa 檔名 `TalkBridge-vN.ipa` |
| 下載 ipa | 比照 voicejournal 記錄的方法（API 取 artifact，302 轉址那一跳不能帶 Authorization） |

**Xcode／SDK 版本**：iOS 26 的 API（§5）需要 Xcode 26 SDK。實作第一步要在 runner 上確認有 Xcode 26（macos-15 映像檔是否內建，或改用 macos-26 映像檔），並用 `xcode-select` 明確選定版本。【Claude 判斷】

## 3. 目標裝置

- 【Kevin 決定】App 裝在**太太的 iPhone**，型號與 Kevin 相同，**iOS 26.6.2**。
- 部署目標維持原需求的 **iOS 18.0**；iOS 26 的新 API 以 `if #available(iOS 26, *)` 使用，iOS 18–25 走舊寫法。實機只會驗證到 iOS 26 那條路，iOS 18 路徑只保證能編譯並有單元測試。【Claude 判斷】

## 4. 音訊設計（覆寫原需求 §一第 1 項、§四、§六第 6 項、§十二第 6 項）

### 4.1 沒有 AirPods

【Kevin 決定】家裡沒有 AirPods，只有**一般藍牙耳機**，或**直接用手機喇叭**。兩種都要支援。UI 的路由顯示仍保留「AirPods」類別（若偵測到），但測試與文件以一般藍牙耳機和手機喇叭為主。原需求 §十二第 6 項的「AirPods 連接前/後/中途斷線」改成「藍牙耳機」。

### 4.2 麥克風：永遠用 iPhone 內建麥克風

【Kevin 決定】太太說中文時用**手機麥克風**（對著手機說），不用耳機麥克風。

因此 AVAudioSession 的設計【Claude 判斷，需實機驗證】：
- category `.playAndRecord`；options 含 `.allowBluetoothA2DP`、`.defaultToSpeaker`；**不加** `.allowBluetooth`（HFP），避免 iOS 把收音改到耳機麥克風、把耳機切成電話音質。
- 結果預期：有藍牙耳機時，播放走耳機（A2DP 高音質），收音走 iPhone 內建麥克風；沒有耳機時，播放走手機喇叭。
- 只支援 HFP 的耳機不會被使用，聲音會改由手機喇叭播出；UI 要照實顯示。

### 4.3 兩個方向各從哪裡播

| 輸出模式 | 對方說話 → 中文 | 太太說中文 → 外語 |
|---|---|---|
| **耳機模式**（偵測到藍牙耳機） | 中文從耳機播給太太 | 外語**暫時改從手機喇叭**播給對方（`overrideOutputAudioPort(.speaker)`），播完恢復走耳機 |
| **喇叭模式**（沒有耳機，或使用者選「一律用喇叭」） | 中文從手機喇叭播出（對方也聽得到） | 外語從手機喇叭播出 |

- 設定裡有「輸出方式」：自動（有耳機就用耳機模式）／一律用手機喇叭。【Claude 判斷】
- 耳機模式下「暫時切到喇叭」能不能在一般藍牙耳機上成功，**必須實機驗證**。實作要偵測切換後實際的 route；如果仍在耳機上，UI 明確提示「外語仍從耳機播出」，並引導改用「給對方看」大字畫面或切換成一律喇叭。不得使用私有 API。
- 音訊路由顯示（原需求 §六第 6 項）顯示「實際」路由，不是期望路由。

### 4.4 回音防護（補充原需求 §四第 6 項）

- 半雙工：語音合成播放期間，麥克風 tap 必須已移除、辨識 request 必須已結束；狀態機不允許從「播放中」直接轉到任何「聆聽中」狀態，必須先經過播放結束或被停止。
- 播放結束到重新開麥克風之間加一小段保護間隔（預設 0.3 秒，放在 `ConversationConfiguration`），避免喇叭殘響被收進去。【Claude 判斷】

## 5. Apple API 選擇（補充原需求 §二、§八第 10 項）

### 5.1 翻譯（Translation framework）
- 可用性用 `LanguageAvailability` 檢查；中文目標語言用繁體中文（`zh-Hant`，地區 TW），實際使用的語言代碼要顯示在 UI／設定頁（原需求 §三）。
- 集中整合：只有一個翻譯協調者（例如 `TranslationCoordinator`）持有 `TranslationSession`。下載語言模型（`prepareTranslation`）在 iOS 18 必須透過 SwiftUI `.translationTask` 取得 session，因此在 App 根畫面放一個隱藏的翻譯宿主 view，由協調者驅動；iOS 26 可直接建立已安裝語言的 session 做翻譯，但下載流程仍走宿主 view。具體寫法以 runner 上 SDK 實際能編譯的 API 為準。【Claude 判斷】
- Translation framework 在模擬器上不能真的翻譯，模擬器與 CI 一律用 fake service。

### 5.2 語音辨識
- 主要用 `SFSpeechRecognizer`（iOS 18 起可用，五種語言＋zh-TW 都有辨識器）。
- 偏好裝置端辨識：該語言 `supportsOnDeviceRecognition` 為真時設 `requiresOnDeviceRecognition = true`；為假時**允許 Apple 伺服器辨識**，但 UI 明確標示「此語言的語音辨識需要網路（由 Apple 處理）」。這不是第三方雲端服務，符合原需求「盡可能留在裝置端」。【Claude 判斷——Kevin 若要「只准裝置端、不支援就停用」可推翻】
- iOS 26 的新語音辨識 API（SpeechAnalyzer / SpeechTranscriber）第一版**不採用**，列入下一版建議；理由：多一條路徑要維護，且五種語言的支援度需另外查證。【Claude 判斷】

### 5.3 語音合成
- `AVSpeechSynthesizer`；每種語言挑精確 locale 的語音，沒有就挑同語言最接近的，並提示（原需求 §五 B-7）。

## 6. 對話流程的決定

### 6.1 模式 B 播放：倒數 2 秒自動播（覆寫原需求 §五 B-4）

【Kevin 決定】太太說完中文、翻譯完成後，**倒數 2 秒自動播放**給對方；倒數期間可以按「取消」或「編輯」（按編輯即停止倒數，改完手動按播放）。
- 狀態機在 `readyToPlayForPartner` 加倒數子狀態；倒數秒數放在 `ConversationConfiguration`。
- 原需求的「先確認再播」保留為設定選項（預設關閉）。【Claude 判斷】
- 播放、停止、重播、重新錄音、編輯翻譯文字（原需求 §五 B-5）照做。

### 6.2 模式 C 自動輪流：固定交替

【Kevin 決定】自動輪流時，**固定交替**：對方說完換太太、太太說完換對方，畫面大字顯示「現在輪到：對方／我」。不做自動判斷語言。
- 第一句由使用者按哪個大按鈕決定從誰開始。
- 停頓 1.2 秒、最長 30 秒照原需求；另加「輪到某人後若一直沒說話」的等待上限（預設 15 秒）後回到待機，避免麥克風無限開著。【Claude 判斷】
- 任何時候按另一個大按鈕都可以搶回順序；緊急停止回到 idle。

### 6.3 「給對方看」大字畫面（新增）

【Claude 判斷】加一個全螢幕大字畫面，顯示最新一句外語翻譯，可一鍵把畫面旋轉 180 度給坐在對面的人看。這也是 §4.3 喇叭切換失敗時的備案。UI 測試要涵蓋開啟與關閉。

## 7. 其他沿用原需求、但寫清楚的地方

- 隱私（原需求 §七）全照做；對話只在記憶體，關 App 即消失；console 不印說話內容。
- 錯誤處理（§九）、單元測試（§十，20 項）、UI 測試（10 項，另加 §6.3 大字畫面）全照做，模擬器與 CI 一律用 fake services；fake 放在測試／除錯目標，不進正式實作路徑。
- 實機測試計畫（§十二）20 項照做，改寫：AirPods → 藍牙耳機（§4.1）、加「耳機模式下外語是否真的從喇叭播出」、加「倒數 2 秒取消」、加「自動輪流固定交替」。
- README（§十三）18 項照做，第 9–10 項改寫成 Sideloadly 流程（§2）。

## 8. 留給實作者決定的事

- Observation（`@Observable`，iOS 17+）或 ObservableObject：部署 iOS 18，預期用 `@Observable`。
- 狀態機的具體型別設計、檔案切分細節（原需求 §八的結構當參考）。
- GitHub Actions workflow 細節（快取、模擬器挑選、測試結果摘要格式）。
- 字體大小設定的級距。

## 9. 不做的事（第一版）

- 真正同時雙工、零延遲口譯。
- 自動判斷說話語言。
- 對話紀錄存檔或匯出。
- 第三方套件、雲端翻譯 API、分析／廣告 SDK。
- iOS 26 新語音辨識 API（列下一版）。
- App Store 上架、付費開發者帳號簽章。
