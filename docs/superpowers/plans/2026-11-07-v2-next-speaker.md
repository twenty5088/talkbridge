# TalkBridge v2 Implementation Plan：按鈕指定下一句＋使用情境修正

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans（Native，Kevin 2026-11-07 說「請幫我開始修改」）。

**Goal:** 按鈕在翻譯／倒數／播放中改為「記住下一句換誰說」而不中斷，並修正設計 §3 的 P3–P11。
**Spec:** `docs/superpowers/specs/2026-11-07-auto-language-design.md`（v2，按鈕版）
**開發迴圈：** `bash scripts/ci.sh core`（Linux 單元測試）、`bash scripts/ci.sh ios`（模擬器＋UI＋警告＋ipa）。

## Global Constraints
- 沿用 v1 計畫 Global Constraints（Swift 6 strict concurrency、iOS 18、無第三方、不記錄說話內容、0 警告、測試不用固定 sleep）。
- 停頓預設 2 秒（v37 已做）；麥克風保護間隔 0.3 秒；自動輪流沒聲音暫停 60 秒、手動 15 秒。
- 行為改變而修改的舊測試，要在 progress.md 記 `Ruling:` 說明原因。

## Review Focus
1. 記住的下一句在「全部停止／錯誤／換語言／背景／來電／耳機斷線」後一定清掉，之後不會突然開麥克風。
2. 播放中按按鈕不可中斷播放（舊行為是停止）；倒數中按「我說中文」不可丟掉待播句。
3. 殘響過濾不可把對方真正說的不同內容丟掉（只比對播放後的第一句、門檻集中設定）。
4. 自動輪流忽略空白結果時不可形成無限快速迴圈（每輪仍受沒聲音 60 秒限制）。
5. 聆聽中按重播：要確實關麥克風再播放，播完回到原本那一方。

---

### Task 1: 下一句佇列（ViewModel）
**Files:** Modify `ViewModels/ConversationViewModel.swift`；Test `Tests/.../NextSpeakerQueueTests.swift`；修改受影響的舊測試。
**Produces:** `public private(set) var queuedSpeaker: Speaker?`；`buttonTapped` 依設計 §2.1 表格；`scheduleNextTurn` 優先用 `queuedSpeaker`（兩種模式都適用）；`stopAll`、`fail`、`stopPlayback` 清空。
**Tests（先寫、先看失敗）:**
- testUserTapDuringPartnerLanguagePlaybackQueuesChineseAndDoesNotStop：播放外語中按「我說中文」→ state 仍 speakingPartnerLanguage、synthesis 沒被 stop；播完經 0.3 秒 → listeningToUser（自動與手動模式各一）。
- testUserTapDuringCountdownKeepsPendingAndPlaysThenListensChinese：倒數中按 → 倒數照走、播放、之後聽中文；entries 有這一句。
- testPartnerTapDuringTranslatingToChineseQueuesPartner：翻譯中按「對方說話」→ 播完中文後聽對方（自動輪流原本會換太太）。
- testLastTapWins：先按對方再按我 → 播完聽中文。
- testStopAllClearsQueue、testStopPlaybackClearsQueue、testErrorClearsQueue、testLanguageChangeClearsQueue。
- testTapOtherSideWhileListeningStillSwitchesImmediately（照舊）。

### Task 2: 自動輪流穩定性（P4、P6、P11）
**Files:** `ConversationViewModel.swift`、`ConversationConfiguration.swift`（`autoModeNoSpeechTimeout = .seconds(60)`）、`UtteranceEndDetector.swift`（init 加 `noSpeechTimeout: Duration?`）。
**Tests:** testAutoModeIgnoresEmptyTranscriptAndKeepsListening（不出現 idle、currentTurn 不變、再開一次同語言辨識）；testAutoModeNoSpeechPausesAfter60Seconds（59 秒仍聽、60 秒暫停）；testManualModeNoSpeechStill15Seconds；testBackgroundAndHeadsetDisconnectClearQueue。

### Task 3: 聆聽中重播（P5）、再試用同一句（P7）
**Tests:** testReplayWhileListeningStopsMicPlaysThenResumesSameSpeaker（recognition.cancel 在 synthesis.speak 之前；播完 → 再聽原本那一方）；testRetryAfterTranslationFailureRetranslatesSameText（不再呼叫 recognition.start；翻譯第二次成功後照常播放／倒數）。
**Produces:** `lastFailedUtterance` 內部狀態；`recover()` 在 `.retry` 且有失敗句時重翻；把 runTurn 的「翻譯→送出」抽成 `deliver(text:direction:)`。

### Task 4: 殘響過濾（P8）
**Files:** Create `Utilities/EchoFilter.swift`：`public enum EchoFilter { static func isLikelyEcho(heard: String, played: String, threshold: Double) -> Bool }`（只比字母數字、忽略大小寫與標點；相似度＝最長共同子序列長度／較長者長度）；`ConversationConfiguration.echoSimilarityThreshold = 0.8`。
**Tests:** EchoFilterTests（相同、標點大小寫不同、部分殘響、完全不同、空字串）；testEchoOfJustPlayedTranslationIsDiscarded（播完英文後聽對方，辨識到同一句英文 → 丟掉、繼續聽、沒有翻譯）；testDifferentSentenceAfterPlaybackIsNotDiscarded；testOnlyFirstUtteranceAfterPlaybackIsChecked。

### Task 5: 畫面提示用的計算屬性（P3、P10）
**Produces:** `public var keepsScreenAwake: Bool`（state.isBusy || currentTurn != nil || queuedSpeaker != nil）；`public var microphoneHint: String?`（聆聽中「現在可以說話：中文」或「現在可以說話：\(partnerLanguage.displayName)」；其他忙碌狀態「請稍等，麥克風已關閉」；待機 nil）；`public var queuedHint: String?`（「下一句：我說中文／對方說話」）。
**Tests:** 各狀態的三個屬性值。

### Task 6: 畫面（P3、P9、P10）＋UI 測試
**Files:** `ContentView.swift`（`UIApplication.shared.isIdleTimerDisabled = conversation.keepsScreenAwake`，onChange 與消失時恢復）；`StatusView`（顯示 microphoneHint、queuedHint，identifier `microphoneHint`、`queuedHint`）；`ConversationView`（ScrollViewReader，entries.count 改變時捲到最後一張）；AccessibilityID 新增兩個 identifier。
**UI tests:** testQueuedHintShownAndPlaybackNotStopped（倒數中按「我說中文」→ 出現「下一句：我說中文」且接著出現「正在播放」）；testMicrophoneHintWhileListening；testNewestCardScrolledIntoView（連續 4 輪後最後一張卡片 isHittable）。

### Task 7: 文件、整體審查、交付
README（按鈕規則、提示、螢幕不鎖定）、PhysicalDeviceTestPlan（設計 §5 三項）、final-report 增補；用最強模型子代理唯讀整體審查 → Critical/Important 先寫失敗測試再修；`ci.sh ios` 全綠；下載 ipa、更新 progress.md 為 DONE。
