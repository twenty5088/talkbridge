# TalkBridge 最終回報（2026-11-07）

依原始需求 §十六 的 14 項回報；所有數字都來自 GitHub Actions 的實際執行結果（commit `e3fa11d`，ios #35、core-tests #35）。

## 1. 專案檔案結構

```
talkbridge/
  project.yml                       XcodeGen 專案定義（.xcodeproj 不進 git）
  .github/workflows/core.yml        Linux 單元測試
  .github/workflows/ios.yml         macOS：模擬器單元測試、App 建置、UI 測試、警告檢查、未簽章 ipa
  scripts/ci.sh, ci.py              推送並等待雲端結果
  scripts/pick_simulator.sh         挑實際存在的 iPhone 模擬器
  scripts/download_ipa.py           下載 ipa 到 dist/
  Packages/TalkBridgeCore/          可測試的核心（Models、Configuration、Utilities、Services 介面、StateMachine、ViewModels）
    Sources/TalkBridgeFakes/        測試用假服務（與正式實作分開）
    Tests/TalkBridgeCoreTests/      110 個單元測試
  TalkBridge/                       App：App/、Services/（Apple 框架實作）、Views/、Resources/
  TalkBridgeUITests/                13 個 UI 測試
  README.md
  docs/PhysicalDeviceTestPlan.md    24 項實機測試
  docs/superpowers/                 設計、計畫、斷點紀錄、本報告
```

## 2. 已完成功能

- 模式 A：對方說五種語言之一 → 即時顯示辨識文字 → 停頓自動結束（預設 2 秒，2026-11-07 起可在設定調整 1.2–4 秒；或再按一次）→ 翻成繁體中文 → 中文語音播放。
- 模式 B：太太說中文 → 翻成對方語言 → 大字顯示 → 倒數 2 秒自動播放；可取消倒數、編輯、播放、停止、重播、重新錄音；設定可改成「先確認再播」。
- 模式 C：自動輪流（Beta），對方與太太固定交替，畫面顯示輪到誰；15 秒沒聲音自動暫停。
- 播放中絕不聆聽；播完 0.3 秒才重新開麥克風。
- 耳機模式：中文走藍牙耳機，外語暫時切到手機喇叭；切不過去會照實提示。設定可改「一律用手機喇叭」。
- 「給對方看」全螢幕大字，可翻轉 180°。
- 權限在第一次使用時才請求，拒絕時有說明與「前往設定」。
- 語言可用性檢查（LanguageAvailability）、語言資料下載引導、16 種錯誤都有繁中訊息與復原按鈕。
- 音訊中斷、耳機斷線、切到背景都會安全停止；換語言會取消進行中的工作。
- 翻譯 20 秒逾時；單句最長 30 秒。
- 字體大小設定、Dynamic Type、VoiceOver 標籤、深色模式（系統語意色）、狀態一律有文字＋圖示。

## 3. 尚未完成或受 Apple 平台限制的功能

- 一般藍牙耳機下「外語暫時改從手機喇叭播」：使用公開 API，能否成功取決於耳機，**尚未實機驗證**。
- 是否能離線：取決於語言資料是否下載、Apple 是否支援該語言的裝置端辨識；不支援的語言改用 Apple 伺服器辨識（畫面標示）。
- 真實的語音辨識、翻譯、語音合成、路由切換，模擬器都無法驗證；全部列在實機測試計畫。
- 自動輪流不會自動判斷說話語言（刻意設計為固定交替）。
- 延後到下一版的小問題：見 `progress.md` 的 `minor (deferred)`。

## 4. 使用的框架及架構決策

Speech、Translation、AVFoundation（AVAudioEngine／AVAudioSession／AVSpeechSynthesizer）、SwiftUI＋Observation、XCTest、XCUITest；無第三方套件。核心邏輯與 Apple 框架以 protocol 分離並注入；明確狀態機；同時只有一個工作；翻譯只在一個 `.translationTask` 宿主集中處理；時間透過可注入的 Sleeper，測試不用固定 sleep。所有偏離計畫的決定都記在 `progress.md` 的 `Ruling:`。

## 5. 實際執行的 build 命令

見 README §17（Xcode 26.3／Swift 6.2.4，模擬器 iPhone 17 Pro iOS 26.2；Release `-sdk iphoneos` 未簽章建置）。

## 6. 實際執行的 test 命令

見 README §17：`swift test --package-path Packages/TalkBridgeCore`（Linux）、`xcodebuild test -scheme TalkBridgeCore-Package`（模擬器）、`xcodebuild test -scheme TalkBridge`（App＋UI 測試）。

## 7. Build 結果

成功：Debug 模擬器建置、Release iphoneos 未簽章建置；產生 `TalkBridge-v35.ipa`（351,399 bytes，Bundle ID `com.twenty5088.talkbridge`，版本 1.35 (35)，最低 iOS 18.0）。

## 8. 單元測試結果

Linux：110 個，通過 110、失敗 0、略過 0。iOS 模擬器：110 個，通過 110、失敗 0、略過 0。

## 9. UI 測試結果

13 個，通過 13、失敗 0、略過 0。

## 10. Compiler warnings

本專案程式（TalkBridge、TalkBridgeUITests、TalkBridgeCore）的編譯警告：0（每次 CI 檢查，有警告就判失敗）。

## 11. 如何選擇 Development Team

不需要。沒有 Mac 也沒有付費開發者帳號，改用 Sideloadly＋免費 Apple ID 簽章（README §9）。

## 12. 如何安裝到實體 iPhone

README §10：下載 ipa → Sideloadly（官網版 iTunes）→ 填太太的 Apple ID → 信任開發者 → 必要時開開發者模式。免費簽章 7 天到期，開 AutoRefresh。

## 13. 實體裝置仍需手動驗證的項目

`docs/PhysicalDeviceTestPlan.md` 全部 24 項；最優先：第 21 項（耳機模式下外語能否切到喇叭）、第 4–5 項（五種語言雙向）、第 13 項（哪些語言可離線）、第 20 項（不會辨識自己的播放）、第 6 項（耳機中途斷線）。

## 14. 已知的耳機與音訊路由限制

iPhone 不能同時把兩種聲音分別送到耳機與喇叭；不開 HFP，收音一律用 iPhone 麥克風；只支援 HFP 的耳機不會被使用；外語播放時暫時覆寫到喇叭，切不過去就提示並建議「給對方看」或「一律用手機喇叭」；耳機在中文播放前或播放中斷線會立即停止。

## 整體審查

另一個模型（唯讀）審查全部程式：Critical 0；Important 4（＋2 項由 Minor 升級）全部修正；能自動測的 3 項先寫了會失敗的測試（RED→GREEN）；Apple 框架內的 3 項無法在模擬器測，以編譯＋0 警告驗證並列入實機測試。
