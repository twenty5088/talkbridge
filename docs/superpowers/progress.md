# TalkBridge 開發進度（斷點檔）

只有正在做事的那個 Claude session 可以改這個檔案。每做完一個步驟就更新，並且 commit。

- status: DONE
  （IN_PROGRESS＝進行中／BLOCKED＝卡住等 Kevin／DONE＝全部完成）
- execution: Native（依 superpowers:executing-plans 在同一個 session 依序做；最後一位審查員做整體審查）
- last_active: 2026-11-08T09:10:41+08:00
  （正在工作的 session 每完成一步就更新成現在時間；排程每半小時檢查，看到 25 分鐘內有更新就不插手）
- current: 中文語言名稱＋自動挑最好的聲音＋自己挑聲音完成（ipa 在 dist/）
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
- [x] Task 12: SwiftUI 介面
- [x] Task 13: UI 測試
- [x] Task 14: 文件、最終乾淨建置、下載 ipa
- [x] 整體審查（superpowers:requesting-code-review），修完再跑一次 CI 全綠

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
- Task 12/13 第二輪：UI 11/13。修正：提示 Label 合併成單一無障礙元素；UI 測試假語音播放改 4 秒（1.5 秒來不及按停止）。
- Task 12/13 第三輪：UI 12/13，只剩編輯測試假設游標在結尾；改成清空後輸入整句並比對完全相同（更嚴格）。
- 整體審查（opus）：Critical 0、Important 4（辨識舊回呼關掉新麥克風、翻譯可能永遠等待、翻譯 session 用錯語言對、SFSpeechRecognizer 只是區域變數）、Minor 8。
- Final: Ruling: 審查 #5（翻譯途中耳機斷線中文改從喇叭播出）、#6（換語言後下載舊語言）由 Minor 升為 Important — 使用者會直接遇到 — 若錯：多兩個小修正。
- Final: fixed #5 耳機斷線（翻成中文途中也停、聆聽中不停）— testHeadsetDisconnectWhileTranslatingToChineseStops / testHeadsetDisconnectWhileListeningKeepsListening RED→GREEN，suite 110/110
- Final: fixed #6 換語言清掉舊下載 — testChangingLanguageClearsPendingDownload RED→GREEN，suite 110/110
- Final: fixed #2（ViewModel 端）翻譯 20 秒逾時＋取消即放棄 — testTranslationTimeoutShowsRetry RED→GREEN，suite 110/110
- Final: Ruling: #1 辨識回呼換代、#3 translation session 只處理自己語言對的工作、#4 保留 SFSpeechRecognizer、#2（翻譯服務端）取消時移除佇列工作 — 都在 Apple 框架實作裡，模擬器無法執行真實 Speech/Translation，寫不出會失敗的自動測試；以 macOS 編譯＋0 警告驗證，並列入實機測試計畫（第 10、12 項）— 若錯：實機測試時才會發現。
- Final: minor (deferred): #7 新一句開始時沒先 stopSpeaking；#8 utterance 用 ObjectIdentifier 比對可能撞位址（改用 ===）；#9 譯文清空時播放鈕仍可按；#10 回到待機沒有 deactivate 音訊（太太的音樂不會自動恢復）；#11 TalkBridgeFakes 也連結進 Release；#12 伺服器辨識的網路錯誤被顯示成「無法辨識這個語言」
- Task 12/13/14 + 審查修正：ios #35（commit e3fa11d）Core 110/110、UI 13/13、warnings 0、ipa v35；core-tests #35 110/110。
- 2026-11-07 完成：ipa v35 下載到 dist/；final-report.md 已寫；自動續做排程停用。
- 2026-11-07 變更（Kevin 要求）：停頓預設 1.2→2 秒並可在設定調整（1.2/1.5/2/2.5/3/4 秒）。RED：PauseSettingTests 9 項＋改 ModeA/Detector/Configuration 測試，因缺 pauseSeconds/userPause 編譯失敗；GREEN：core 119/119。
- Ruling: ConversationConfiguration.silenceTimeout 改為 Duration?，nil＝依使用者設定；只有 UI 測試假情境固定 0.3 秒 — 讓 UI 測試維持快速 — 若錯：假情境不反映使用者設定，只影響測試。
- Ruling: AppSettings 自訂 init(from:) 用 decodeIfPresent — 舊版存下的設定少了新欄位時不會整份被重置 — 若錯：升級後設定被重置。
- 停頓設定驗證：ios #37（commit 5abbb3f）Core 119/119、UI 14/14（新增 testPauseSettingDefaultsToTwoSecondsAndCanChange）、warnings 0、ipa v37 下載到 dist/。
- 2026-11-07 v2 改方向（Kevin）：不做自動判斷，改按鈕指定下一句；實驗畫面已 revert（e881b22）。計畫 plans/2026-11-07-v2-next-speaker.md 共 7 個 Task。
- Ruling: v2 設計改版後未再跑 builder check — Kevin 已在對話中逐條確認按鈕行為並說開始修改 — 若錯：實作中才發現缺漏，照計畫 Ruling 處理。
- Task 1: Ruling: 改寫 testNoMicWhileSpeakingPartnerLanguage（播放中按鈕原本＝停止，v2 改為記住下一句；仍驗證播放中不開麥克風）與 testSecondTranslationCancelsFirst→testTapOtherSideWhileTranslatingFinishesFirstThenSwitches（翻譯中按另一方原本＝取消，v2 改為翻完播完再換）— 設計 §2.1 表格 — 若錯：Kevin 想要的是立即中斷。
- Task 1: Ruling: 待播且沒有倒數（先確認再播／取消倒數／停止播放／沒有語音）時按按鈕＝照舊立刻開始新的一輪，不記住 — 否則沒有語音時會卡在待播、按什麼都只是記住 — 若錯：先確認再播模式下按我說中文會丟掉待播句（原本就是這樣）。
- Task 2: Ruling: testAutoIdleTimeoutStops 改推進 60 秒 — 設計 P6 自動輪流沒聲音暫停改 60 秒 — 若錯：Kevin 想維持 15 秒。
- Task 2: Ruling: 單句最長 30 秒改成從第一次聽到文字起算、且沒人說話時不適用 — 否則自動輪流安靜等待會在 30 秒被誤判成「已達單句最長」— 若錯：對方講超過 30 秒時切段時機略晚。（測試 testMaxDurationOnlyCountsAfterSpeechStarts）
- Task 6: Ruling: P9 自動捲動不做 — 對話紀錄本來就是最新一張在最上面、緊接在狀態區下方 — 若錯：Kevin 實機覺得還要捲。
- Task 6: Ruling: 卡片重播鈕在聆聽中改為可按（ConversationView canReplay），配合 P5。
- Task 1–6: complete（commits 6238762..0ee6205）。
- Task 7: README／PhysicalDeviceTestPlan（25–28）更新；v2 整體審查找到 R1–R8（記住的下一句殘留、保護間隔內中斷仍開麥克風、準備中重播、殘響過濾誤丟、雜音無限重聽、換語言用舊語言重試、錯誤沒結束自動輪流、待按播放沒提示），RED 測試寫在 ReviewFixV2Tests.swift。
- Final(v2): RED core #51：ReviewFixV2Tests 14 項失敗（R3 重播競態直接當掉：speakingChinese→listeningToPartner 不允許）。
- Final(v2): fixed R1–R8 — ReviewFixV2Tests RED→GREEN，core #52 166/166（commit 71726d6）。
- Final(v2): Ruling: 殘響門檻 0.8→0.9、只比對播完 1.5 秒內開始的話、少於 4 個字母／數字不比對；舊測試 testDefaultThreshold 改成 0.9 — 審查 R4：寧可漏丟殘響也不可丟對方真的回答 — 若錯：喇叭殘響偶爾被翻回中文（實機測試 28 項會看到）。
- Final(v2): Ruling: 沒有語音時（voiceMatch none）照樣接下一句；但待播句（外語沒語音）停在待播並清掉記住的下一句 — 待播句要留給對方看畫面 — 若錯：按了下一句卻要再按一次。
- Final(v2): Ruling: 待機時（準備中或保護間隔內）進背景／來電／換語言改為 stopAll（不顯示錯誤畫面）— 沒有正在進行的一句，不需要錯誤畫面 — 若錯：無。
- Final(v2): ios #53：Core 166/166、UI 14/15、warnings 0。失敗 testErrorStateHasRecoveryButton：根因是 P7 之後「再試一次」會用同一句重翻，而假情境 translationFailure 每次都失敗→又回到「發生錯誤」。
- Final(v2): Ruling: 假翻譯加 translateErrorOnce，translationFailure 情境只失敗第一次；UI 測試改成驗證重試後「正在播放」→「等待中」（比原本只看等待中更嚴格）— 行為改變是 P7 本意 — 若錯：無。
- Final(v2): ios #49（commit b0fca46）Core 167/167、UI 15/15、warnings 0；ipa v49 下載到 dist/；final-report 更新；status DONE，自動續做排程停用。
- 2026-11-08: 對方語言名稱改中文（英文／印尼文／泰文／日文／韓文）— Kevin 要求；RED 6 失敗→GREEN；ios #52 Core 167/167、UI 15/15、warnings 0。
- 2026-11-08: 自動挑最好的聲音（高品質＞加強版＞一般，略過趣味語音，本地區優先）— VoiceSelectorTests RED 3 失敗→GREEN。
- 2026-11-08: 自己挑聲音（Kevin 核准設計）— VoiceChoiceTests RED 10 失敗→GREEN，core 184/184。
- 2026-11-08: Ruling: 設定存「語音語言代碼→聲音 identifier」，挑的聲音被刪或語言不符就退回自動 — 不會沒聲音 — 若錯：使用者以為選了卻用自動，設定頁那列會顯示「自動」可看出。
- 2026-11-08: Ruling: 對話進行中不能試聽（▶ 變灰）— 麥克風可能開著，試聽聲會被當成有人說話 — 若錯：要先按全部停止才能試聽。
- 2026-11-08: Ruling: 試聽沿用對話的音訊設定（抽出 AppleAudioSessionService.configureCategory），只在離開選聲音畫面時關掉自己開的工作階段 — 靜音開關下也聽得到、不干擾對話 — 若錯：試聽後別的 App 音樂要手動再播。
- 2026-11-08: Ruling: 選聲音畫面的 UI 測試與畫面同一次提交（非先 RED）— 核心規則已 TDD，畫面只是接線；UI 測試只驗預設「自動」與畫面可進入 — 若錯：畫面細節靠實機測試第 29 項。
- 2026-11-08: 品質標籤「加強版」改「增強音質」（與 iOS 聲音設定用詞一致，Kevin 實機看到）；設定頁與 README 註明 Siri 聲音不開放給第三方 App — RED 1 失敗→GREEN。
