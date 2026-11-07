# TalkBridge 開發進度（斷點檔）

只有正在做事的那個 Claude session 可以改這個檔案。每做完一個步驟就更新，並且 commit。

- status: IN_PROGRESS
  （IN_PROGRESS＝進行中／BLOCKED＝卡住等 Kevin／DONE＝全部完成）
- execution: Native（依 superpowers:executing-plans 在同一個 session 依序做；最後一位審查員做整體審查）
- last_active: 2026-11-07T10:27:56+08:00
  （正在工作的 session 每完成一步就更新成現在時間；排程每半小時檢查，看到 25 分鐘內有更新就不插手）
- current: Task 12/13（畫面＋UI 測試，一起推送）
- blocked_reason: （無）

## 任務清單

- [x] Task 1: Repo、CI 骨架與最小可編譯 App
- [x] Task 2: 語言、方向、對照與設定值
- [x] Task 3: 錯誤對照與音訊路由對照
- [x] Task 4: Service protocols、Sleeper 與假服務
- [x] Task 5: 狀態機
- [x] Task 6: 一句話結束偵測
- [x] Task 7: ViewModel 模式 A
- [x] Task 8: ViewModel 模式 B
- [x] Task 9: 並發、權限、語言準備、中斷
- [x] Task 10: 自動輪流
- [x] Task 11: Apple 框架實作
- [ ] Task 12: SwiftUI 介面
- [ ] Task 13: UI 測試
- [ ] Task 14: 文件、最終乾淨建置、下載 ipa
- [ ] 整體審查（superpowers:requesting-code-review），修完再跑一次 CI 全綠

## 紀錄（新的在下面）

- 2026-11-07 計畫核准，開始執行。
- Ruling: 直接在 main 開發，不開 worktree — 新 repo、只有 Claude 在寫，排程續做也要找得到同一份工作 — 若錯：之後要 PR 流程再開分支即可。
- Ruling: 斷點／ledger 用 docs/superpowers/progress.md，不用 .superpowers/sdd/ — 排程 session 要讀得到、而且要進 git — 若錯：無。
- Ruling: iOS runner 用 macos-15 + 自動選最新 Xcode（實測 Xcode 26.3、Swift 6.2.4、模擬器 iOS 26.2）— macos-26 標籤不確定存在 — 若錯：改 runs-on 一行。
- Ruling: Task 3 的 AudioOutputKind 多加 isHeadset（airPods/bluetooth/headphones）— Task 8「目前路由是耳機才切喇叭」需要 — 若錯：多一個屬性。
- Task 1: complete（commits 0b45add..4d97abd；core-tests #3 1/1 pass；ios #2：Core 1/1、UI 1/1 pass、warnings 0、ipa 產出）
- Task 2: complete（commits 6ca3b47..c3ea250；core-tests #5 9/9 pass）
- Task 3: complete（commits 3c1…；core-tests 17/17 pass）。Core 不 import Foundation：Linux 上字串方法要用純 Swift。
- Ruling: CallLog 由 actor 改成 Mutex 保護的 final class、同步 record — actor 的非同步記錄會讓呼叫順序不確定，測不了「服務呼叫順序」— 若錯：無。
- Task 4: complete（commit 0ddb9ad；core-tests #10 24/24 pass）。Fakes 加了 emit()/setMode()/setReadiness() 等測試輔助。
- Ruling: 狀態機允許 readyToPlayForPartner → listeningToUser — Task 8「重新錄音」需要從待播直接重錄 — 若錯：多一條轉換。
- Task 5: complete（commit 9f452ab；core-tests #12 34/34 pass）
- Task 6: complete（commit 6ad241d；core-tests #14 39/39 pass）
- Ruling: Sleeper 協定加 `var now: Duration`（TaskSleeper 用 ContinuousClock、ManualSleeper 用虛擬時間）— 停頓判斷要量「距上次結果多久」，測試要能精準控制 — 若錯：多一個屬性。
- Ruling: ViewModel 的 now 參數改成 `@MainActor () -> Date`（不是 @Sendable）— 測試要用遞增時間 — 若錯：無。
- Ruling: 狀態機加 idle→speakingChinese、idle→speakingPartnerLanguage（重播）— 重播只播放不開麥克風 — 若錯：多兩條轉換。
- Ruling: ios.yml 加 concurrency cancel-in-progress — 每次推送都觸發 macOS，排隊會拖慢驗證 — 若錯：中間版本不會有 iOS 結果（Linux 仍每版都有）。
- Task 7: complete（commit 73cf31b；core-tests #16 57/57 pass）。模式 B 在 Task 7 先停在 readyToPlay(nil)，Task 8 補完。
- Task 7 iOS 驗證：ios #16 Core 57/57、UI 1/1、warnings 0
- Task 8: 假語音服務的 isSpeaking 改由 continuation 判斷（被停止的上一句晚收尾會誤清旗標）；正式版 AppleSpeechSynthesisService 也要注意同樣的競態。
- Task 8: complete（commits cf67b7d..89af8f8；core-tests #20 71/71 pass）
- Ruling: Task 9 的「stopAll 時 log 有 cancel 與 synthesis.stop」拆成三個測試（聆聽中→cancel、翻譯中→結果丟棄、播放中→synthesis.stop）— 翻譯中本來就沒有麥克風與播放可停 — 若錯：無。
- Ruling: FakeTranslationService 加 holdTranslations/releaseTranslations — 要測翻譯途中被停止 — 若錯：無。
- 注意：Linux XCTest 不支援「@MainActor 類別裡的同步測試方法」（會 signal 6 當掉），這種類別的測試一律寫成 async。
- Task 9: complete（commits 7c092da..c49b610；core-tests #23 96/96 pass）
- Ruling: ManualSleeper.waitForPendingCount 加上限、core.yml 加 timeout-minutes 15 — RED 測試曾因無上限等待卡住 CI 超過 10 分鐘 — 若錯：無。
- Task 10: complete（commits eb126a9..229b948；core-tests #26 105/105 pass）
- Task 11: complete（commits 9f0af08..0c13e93；ios #27 build 成功、Core 105/105、UI 1/1、warnings 0、ipa 產出）
- Ruling: TranslationSession 用 @unchecked Sendable 的 TranslationSessionBox 帶進 nonisolated 的 process()——它不是 Sendable，Swift 6 不讓它跨到主執行緒；整個 App 只在同一個 translationTask 裡依序使用，不會並行 — 若錯：理論上的資料競爭，實機測試要留意翻譯是否偶發失敗。
- Ruling: 設計文件 §5.1 提到 iOS 26 可直接建立 session；改成 iOS 18/26 都走同一個 translationTask 宿主 — 少維護一條路 — 若錯：iOS 26 少用一個較新的 API，功能相同。
- Ruling: Task 12 與 Task 13 分兩個 commit、一次推送跑 macOS — 每輪 macOS 約 10–15 分鐘 — 若錯：失敗時要自己分辨是畫面還是測試的問題。
- Ruling: UI 測試假模式的倒數設成 5 秒（正式版仍是 2 秒）— 讓 UI 測試來得及按「取消倒數」— 若錯：無。
- Task 12/13 第一輪：UI 10/13。修正：待播按鈕改 LazyVGrid 並移到狀態正下方（ViewThatFits 可能讓按鈕在結構裡出現兩份／被底部列擋住）、給對方看畫面外框加 .contain（識別名稱會蓋掉子按鈕）、編輯框改單行並以「完成」收鍵盤。
