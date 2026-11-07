import Foundation
import Observation

/// 對話流程的總指揮：權限 → 語言準備 → 聆聽 → 辨識 → 翻譯 → 播放。
///
/// 規則：
/// - 同一時間只有一個工作（`activeTask`）；開始新工作前先取消舊的。
/// - 麥克風只在 listening 狀態開著；播放前一定已經停止收音（避免把自己的播放聲音再辨識）。
/// - 所有狀態變化都經過 `ConversationStateMachine`。
/// - 不記錄任何說話內容到 log。
@MainActor
@Observable
public final class ConversationViewModel {
    // MARK: 給畫面讀的狀態

    public private(set) var state: ConversationState = .idle
    public private(set) var entries: [ConversationEntry] = []
    public private(set) var partialTranscript = ""
    /// 非錯誤的提示（伺服器辨識、語音替代、喇叭切換失敗…）。
    public private(set) var notice: String?
    public private(set) var route: AudioRouteInfo
    /// 自動輪流時現在輪到誰。
    public private(set) var currentTurn: Speaker?
    /// 翻譯、倒數或播放中按了按鈕：這句播完後換這一方說（v2 設計 §2）。
    public private(set) var queuedSpeaker: Speaker?
    public private(set) var lastError: AppError?
    /// 換語言時若正在進行中，先全部停止，避免用舊語言翻譯或播放；
    /// 也清掉「舊語言」的下載與錯誤，回到待機。
    public var partnerLanguage: PartnerLanguage = .english {
        didSet {
            guard oldValue != partnerLanguage else { return }
            pendingPreparePair = nil
            queuedSpeaker = nil
            if state.isBusy {
                stopAll()
            } else if state == .languageNotReady || state == .error(.languageUnsupported) {
                lastError = nil
                move(to: .idle)
            }
        }
    }
    public var settings: AppSettings
    /// 模式 B 倒數剩餘秒數；nil 表示沒有在倒數。
    public private(set) var countdownRemaining: Int?
    /// 模式 B 待播的譯文，使用者可以編輯。
    public var editableTranslation = ""
    public private(set) var isEditing = false

    // MARK: 依賴

    @ObservationIgnored private let recognition: any SpeechRecognitionService
    @ObservationIgnored private let translation: any TranslationService
    @ObservationIgnored private let synthesis: any SpeechSynthesisService
    @ObservationIgnored private let audio: any AudioSessionService
    @ObservationIgnored private let permissions: any PermissionService
    @ObservationIgnored private let sleeper: any Sleeper
    @ObservationIgnored private let configuration: ConversationConfiguration
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let logger: @Sendable (String) -> Void

    // MARK: 內部狀態

    @ObservationIgnored private var machine = ConversationStateMachine()
    @ObservationIgnored private var activeTask: Task<Void, Never>?
    /// 正在進行的「聆聽→翻譯」流程屬於誰；用來判斷再按一次同一個按鈕＝說完了。
    @ObservationIgnored private var activeTurn: Speaker?
    @ObservationIgnored private var recognitionActive = false
    @ObservationIgnored private var listening: ListeningContext?
    @ObservationIgnored private var listenCounter = 0
    /// 目前用來等待的 sleep；有新的辨識結果或要求結束時取消它，讓監看迴圈立刻重新判斷。
    @ObservationIgnored private var wakeTask: Task<Void, Error>?
    @ObservationIgnored private var pendingPreparePair: (source: String, target: String)?
    /// 模式 B 待播的這一句（原文與方向）；第一次播放時才加入對話紀錄。
    @ObservationIgnored private var pendingUtterance: (original: String, direction: TranslationDirection)?
    @ObservationIgnored private var pendingEntryID: UUID?
    /// 外語播放時暫時切到手機喇叭，播完要切回來。
    @ObservationIgnored private var outputOverridden = false
    /// 剛播出的譯文與語言；播放後的第一句若幾乎一樣就當成喇叭殘響（v2 設計 P8）。
    @ObservationIgnored private var lastPlayed: (text: String, languageID: String)?
    /// 翻譯失敗的那一句；「再試一次」用它重新翻譯，不用重講（v2 設計 P7）。
    @ObservationIgnored private var lastFailedUtterance: (text: String, direction: TranslationDirection)?

    private struct ListeningContext {
        let id: Int
        let start: Duration
        var lastChange: Duration?
        var lastPartial = ""
        var finalText: String?
        var streamEnded = false
        var streamError: Error?
        var endRequested = false
    }

    static let serverRecognitionNotice = "此語言的語音辨識需要網路（由 Apple 處理）"
    static let emptyTranscriptNotice = "沒有聽到內容，請再說一次。"
    static let speakerOverrideFailureNotice = "外語仍從耳機播出，請改用「給對方看」或在設定改成一律用手機喇叭。"

    public init(recognition: any SpeechRecognitionService, translation: any TranslationService,
                synthesis: any SpeechSynthesisService, audio: any AudioSessionService,
                permissions: any PermissionService, sleeper: any Sleeper,
                configuration: ConversationConfiguration = .standard, settings: AppSettings = AppSettings(),
                now: @escaping @MainActor () -> Date = { Date() },
                logger: @escaping @Sendable (String) -> Void = { _ in }) {
        self.recognition = recognition
        self.translation = translation
        self.synthesis = synthesis
        self.audio = audio
        self.permissions = permissions
        self.sleeper = sleeper
        self.configuration = configuration
        self.settings = settings
        self.now = now
        self.logger = logger
        self.route = audio.currentRoute
    }

    // MARK: 使用者操作

    public func partnerButtonTapped() { buttonTapped(.partner) }

    public func userButtonTapped() { buttonTapped(.user) }

    /// 緊急停止：取消所有工作、關麥克風、停播放，回到待機。
    public func stopAll() {
        cancelCurrentWork()
        clearPending()
        lastPlayed = nil
        lastFailedUtterance = nil
        currentTurn = nil
        queuedSpeaker = nil
        partialTranscript = ""
        if state != .idle { move(to: .idle) }
    }

    public func clearHistory() {
        entries.removeAll()
    }

    /// 重播某一句的翻譯。聆聽中按：先關麥克風、播放，播完再聽原本那一方（v2 設計 P5）。
    public func replay(_ entryID: UUID) {
        guard let entry = entries.first(where: { $0.id == entryID }) else { return }
        var resumeSpeaker: Speaker?
        if state.isMicrophoneActive {
            resumeSpeaker = activeTurn
            cancelCurrentWork()
            partialTranscript = ""
        } else if state.isBusy {
            return
        }
        if state != .idle { move(to: .idle) }
        lastError = nil
        let speakingState: ConversationState = entry.direction.speaker == .partner ? .speakingChinese : .speakingPartnerLanguage
        activeTask = Task { [weak self] in
            await self?.speak(entry.translation, direction: entry.direction, as: speakingState,
                              continuesConversation: false, resumeSpeaker: resumeSpeaker)
        }
    }

    /// 對話進行中不讓螢幕自動鎖定（鎖定會讓 App 進背景而中斷對話；v2 設計 P3）。
    public var keepsScreenAwake: Bool {
        state.isBusy || currentTurn != nil || queuedSpeaker != nil
    }

    /// 麥克風狀態提示（v2 設計 P10）。待機時沒有。
    public var microphoneHint: String? {
        switch state {
        case .listeningToUser: "現在可以說話：中文"
        case .listeningToPartner: "現在可以說話：\(partnerLanguage.displayName)"
        default: state.isBusy ? "請稍等，麥克風已關閉" : nil
        }
    }

    /// 記住的下一句（v2 設計 §2）。
    public var queuedHint: String? {
        switch queuedSpeaker {
        case .user: "下一句：我說中文"
        case .partner: "下一句：對方說話"
        case nil: nil
        }
    }

    // MARK: 系統事件

    /// 持續接收音訊事件（耳機插拔、來電中斷…）。畫面在 .task 裡呼叫。
    public func startObservingAudioEvents() async {
        for await event in audio.events {
            handleAudioEvent(event)
        }
    }

    public func handleAudioEvent(_ event: AudioSessionEvent) {
        switch event {
        case .routeChanged(let newRoute, let oldDeviceUnavailable):
            route = newRoute
            // 耳機斷線時，若接下來（或正在）要把中文播給太太聽，立刻停，避免中文突然從手機喇叭大聲播出。
            // 聆聽中不用停：收音一律用 iPhone 內建麥克風，不受耳機影響。
            if oldDeviceUnavailable, Self.chinesePlaybackPending(in: state) {
                stopWithError(.headsetDisconnected)
            }
        case .interruptionBegan:
            if state.isBusy { stopWithError(.audioInterrupted) }
        case .interruptionEnded:
            break   // 不自動恢復；使用者再按一次開始。
        case .mediaServicesReset:
            if state.isBusy { stopWithError(.audioSessionFailed) } else { stopAll() }
        }
    }

    private static func chinesePlaybackPending(in state: ConversationState) -> Bool {
        switch state {
        case .transcribingPartner, .translatingToChinese, .speakingChinese: true
        default: false
        }
    }

    /// App 進入背景：安全停止所有工作（不在背景錄音）。
    public func appDidEnterBackground() {
        if state.isBusy {
            stopWithError(.appBackgrounded)
        }
    }

    private func stopWithError(_ error: AppError) {
        stopAll()
        logger("stopped: \(error.category)")
        lastError = error
        move(to: .error(error))
    }

    // MARK: 模式 B 待播操作

    /// 立即播放待播譯文給對方（倒數中按下也可以）。
    public func playForPartner() {
        guard case .readyToPlayForPartner = state, pendingUtterance != nil else { return }
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            await self?.playPending()
        }
    }

    /// 停止倒數，等使用者自己按播放。
    public func cancelCountdown() {
        guard case .readyToPlayForPartner(let countdown) = state, countdown != nil else { return }
        activeTask?.cancel()
        activeTask = nil
        countdownRemaining = nil
        move(to: .readyToPlayForPartner(countdown: nil))
    }

    public func beginEditing() {
        guard case .readyToPlayForPartner = state else { return }
        cancelCountdown()
        isEditing = true
    }

    /// 停止正在播放的外語；有待播的一句時回到待播，可以重播。
    public func stopPlayback() {
        guard state.isSpeaking else { return }
        activeTask?.cancel()
        activeTask = nil
        queuedSpeaker = nil
        synthesis.stop()
        restoreOutput()
        if state == .speakingPartnerLanguage, pendingUtterance != nil {
            move(to: .readyToPlayForPartner(countdown: nil))
        } else {
            move(to: .idle)
        }
    }

    public func replayLastForPartner() {
        if case .readyToPlayForPartner = state {
            playForPartner()
            return
        }
        guard !state.isBusy, let last = entries.last(where: { $0.speaker == .user }) else { return }
        replay(last.id)
    }

    /// 丟掉這句待播翻譯，重新聽太太說。
    public func rerecord() {
        guard case .readyToPlayForPartner = state else { return }
        startTurn(.user)
    }

    /// 錯誤畫面的復原按鈕。
    public func recover() {
        guard let error = lastError else {
            if state != .idle { move(to: .idle) }
            return
        }
        switch error.recovery {
        case .prepareLanguage:
            prepareLanguage()
        case .openSettings:
            break   // 由畫面開啟 iOS 設定；回來後再按一次開始即可重新檢查。
        case .retry:
            lastError = nil
            move(to: .idle)
            if error == .translationFailed, let failed = lastFailedUtterance {
                lastFailedUtterance = nil
                activeTurn = failed.direction.speaker
                activeTask = Task { [weak self] in
                    await self?.deliver(failed.text, direction: failed.direction)
                }
            }
        case .chooseAnotherLanguage, .dismiss:
            lastError = nil
            move(to: .idle)
        }
    }

    // MARK: 流程

    /// v2 設計 §2.1：聆聽中按同一方＝說完了、按另一方＝改聽另一方；
    /// 辨識、翻譯、倒數或播放中按＝記住下一句換誰說，不中斷目前這句（以最後按的為準）。
    private func buttonTapped(_ speaker: Speaker) {
        if state.isMicrophoneActive {
            if activeTurn == speaker { requestEndOfUtterance() } else { startTurn(speaker) }
            return
        }
        if Self.queuesNextSpeaker(in: state) {
            queuedSpeaker = speaker
            return
        }
        if activeTurn == speaker { return }   // 正在準備（權限、語言檢查）：忽略重複點擊
        startTurn(speaker)
    }

    private static func queuesNextSpeaker(in state: ConversationState) -> Bool {
        switch state {
        case .transcribingPartner, .translatingToChinese, .speakingChinese,
             .transcribingChinese, .translatingToPartnerLanguage, .speakingPartnerLanguage:
            true
        case .readyToPlayForPartner(let countdown):
            countdown != nil   // 倒數中記住；等使用者自己按播放時（沒有倒數）按＝重新開始，避免卡住
        default:
            false
        }
    }

    private func startTurn(_ speaker: Speaker) {
        cancelCurrentWork()
        clearPending()
        notice = nil
        lastError = nil
        partialTranscript = ""
        if state != .idle { move(to: .idle) }
        activeTurn = speaker
        queuedSpeaker = nil
        lastFailedUtterance = nil
        currentTurn = settings.mode == .autoAlternate ? speaker : nil
        let direction = TranslationDirection.from(speaker: speaker, partner: partnerLanguage)
        activeTask = Task { [weak self] in
            await self?.runTurn(direction)
        }
    }

    private func runTurn(_ direction: TranslationDirection) async {
        let speaker = direction.speaker
        let localeID = LocaleMapping.speechLocaleID(for: direction)
        let pair = LocaleMapping.translationPair(for: direction)

        guard await ensurePermissions(), !Task.isCancelled else { return }

        switch await translation.readiness(source: pair.source, target: pair.target) {
        case .installed:
            break
        case .unsupported:
            if !Task.isCancelled { fail(.languageUnsupported) }
            return
        case .needsDownload:
            guard !Task.isCancelled else { return }
            pendingPreparePair = pair
            lastError = .translationModelNotInstalled
            move(to: .languageNotReady)
            finishTurn()
            return
        }
        guard !Task.isCancelled else { return }

        switch await recognition.mode(forLocaleID: localeID) {
        case .unavailable:
            if !Task.isCancelled { fail(.recognizerUnavailable(localeID: localeID)) }
            return
        case .server:
            notice = Self.serverRecognitionNotice
        case .onDevice:
            break
        }
        guard !Task.isCancelled else { return }

        do {
            try audio.activate()
        } catch {
            fail(.audioSessionFailed)
            return
        }
        let stream: AsyncThrowingStream<RecognitionUpdate, Error>
        do {
            stream = try recognition.start(localeID: localeID)
        } catch {
            fail(Self.recognitionError(error, localeID: localeID))
            return
        }
        recognitionActive = true
        move(to: speaker == .partner ? .listeningToPartner : .listeningToUser)
        logger("listening started")

        guard let text = await listen(to: stream, localeID: localeID, speaker: speaker) else { return }

        // 播放後的第一句：和剛播出的同語言譯文幾乎一樣，就是喇叭殘響。
        let echoReference = lastPlayed
        lastPlayed = nil
        let isEcho = echoReference.map {
            Self.sameLanguage($0.languageID, localeID)
                && EchoFilter.isLikelyEcho(heard: text, played: $0.text, threshold: configuration.echoSimilarityThreshold)
        } ?? false
        let isMeaningful = UtteranceEndDetector.isMeaningful(text, configuration: configuration)
        guard isMeaningful, !isEcho else {
            partialTranscript = ""
            move(to: .idle)
            finishTurn()
            if isEcho || settings.mode == .autoAlternate {
                logger(isEcho ? "echo discarded" : "empty transcript ignored")
                scheduleTurn(speaker)   // 繼續聽同一方（間隔 postPlaybackMicGuard，不會快速空轉）
            } else {
                notice = Self.emptyTranscriptNotice
            }
            return
        }

        await deliver(text, direction: direction)
    }

    /// 翻譯並送出：對方的話翻成中文播放；太太的話翻成外語後倒數播放。
    private func deliver(_ text: String, direction: TranslationDirection) async {
        let speaker = direction.speaker
        let pair = LocaleMapping.translationPair(for: direction)
        move(to: speaker == .partner ? .translatingToChinese : .translatingToPartnerLanguage)
        let translated: String
        do {
            translated = try await translateWithTimeout(text, source: pair.source, target: pair.target)
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled {
                let appError = (error as? AppError) ?? .translationFailed
                fail(appError)
                if appError == .translationFailed { lastFailedUtterance = (text: text, direction: direction) }
            }
            return
        }
        guard !Task.isCancelled else { return }
        partialTranscript = ""

        switch direction {
        case .partnerToChinese:
            let entry = ConversationEntry(speaker: .partner, direction: direction, original: text,
                                          translation: translated, timestamp: now())
            entries.append(entry)
            await speak(translated, direction: direction, as: .speakingChinese)
        case .chineseToPartner:
            pendingUtterance = (original: text, direction: direction)
            pendingEntryID = nil
            editableTranslation = translated
            isEditing = false
            finishTurn()   // 待播時再按「我說中文」＝重新錄一句
            await countdownThenPlay()
        }
    }

    /// 聆聽直到一句話結束，回傳辨識文字；被取消或失敗時回傳 nil（狀態已處理）。
    private func listen(to stream: AsyncThrowingStream<RecognitionUpdate, Error>,
                        localeID: String, speaker: Speaker) async -> String? {
        listenCounter += 1
        let listenID = listenCounter
        listening = ListeningContext(id: listenID, start: sleeper.now)
        let consumer = Task { [weak self] in
            do {
                for try await update in stream {
                    self?.handle(update, listenID: listenID)
                }
                self?.handleStreamEnd(error: nil, listenID: listenID)
            } catch {
                self?.handleStreamEnd(error: error, listenID: listenID)
            }
        }
        defer { consumer.cancel() }

        // 監看迴圈：停頓、最長時間、完全沒聲音、使用者再按一次。
        let detector = UtteranceEndDetector(
            configuration: configuration, userPause: settings.pauseDuration,
            noSpeechTimeout: settings.mode == .autoAlternate ? configuration.autoModeNoSpeechTimeout : nil)
        var reachedMaxDuration = false
        monitor: while true {
            if Task.isCancelled { return nil }
            guard let context = listening, context.id == listenID else { return nil }
            if let error = context.streamError {
                fail(Self.recognitionError(error, localeID: localeID))
                return nil
            }
            if context.endRequested || context.streamEnded || context.finalText != nil { break monitor }
            let current = sleeper.now
            switch detector.evaluate(elapsed: current - context.start,
                                     sinceLastPartial: context.lastChange.map { current - $0 }) {
            case .keepListening:
                break
            case .endBySilence:
                break monitor
            case .endByMaxDuration:
                reachedMaxDuration = true
                break monitor
            case .endByNoSpeech:
                stopRecognition()
                listening = nil
                if settings.mode == .autoAlternate {
                    notice = "太久沒有聲音，已暫停自動輪流。"
                    currentTurn = nil
                } else {
                    notice = AppError.noSpeechDetected.userMessage
                }
                move(to: .idle)
                finishTurn()
                return nil
            }
            await sleepUnlessWoken(for: nextDeadline(for: context, detector: detector) - current)
        }

        if reachedMaxDuration {
            notice = "已達單句最長 \(configuration.maxUtteranceDuration.components.seconds) 秒，先翻譯這一段。"
        }
        if let context = listening, !context.streamEnded, context.finalText == nil {
            recognition.finishAudio()
        }
        move(to: speaker == .partner ? .transcribingPartner : .transcribingChinese)

        // 等最終結果，最多 finalResultTimeout；逾時用最後一次部分結果。
        let deadline = sleeper.now + configuration.finalResultTimeout
        while let context = listening, context.id == listenID, context.finalText == nil, !context.streamEnded {
            if Task.isCancelled { return nil }
            let remaining = deadline - sleeper.now
            if remaining <= .zero { break }
            await sleepUnlessWoken(for: remaining)
        }
        if Task.isCancelled { return nil }
        guard let context = listening, context.id == listenID else { return nil }
        if context.finalText == nil && !context.streamEnded {
            recognition.cancel()   // 逾時：強制關掉麥克風
        }
        recognitionActive = false
        listening = nil
        if let finalText = context.finalText { return finalText }
        if let error = context.streamError, context.lastPartial.isEmpty {
            fail(Self.recognitionError(error, localeID: localeID))
            return nil
        }
        return context.lastPartial
    }

    private func nextDeadline(for context: ListeningContext, detector: UtteranceEndDetector) -> Duration {
        let maxDeadline = context.start + configuration.maxUtteranceDuration
        if let lastChange = context.lastChange {
            return min(maxDeadline, lastChange + detector.silenceTimeout)
        }
        return min(maxDeadline, context.start + detector.noSpeechTimeout)
    }

    private func handle(_ update: RecognitionUpdate, listenID: Int) {
        guard var context = listening, context.id == listenID else { return }
        switch update {
        case .partial(let text):
            guard text != context.lastPartial else { return }
            context.lastPartial = text
            context.lastChange = sleeper.now
            partialTranscript = text
        case .final(let text):
            context.finalText = text
            partialTranscript = text
        }
        listening = context
        wake()
    }

    private func handleStreamEnd(error: Error?, listenID: Int) {
        guard var context = listening, context.id == listenID else { return }
        context.streamEnded = true
        if let error, !(error is CancellationError) { context.streamError = error }
        listening = context
        wake()
    }

    private func requestEndOfUtterance() {
        guard var context = listening else { return }
        context.endRequested = true
        listening = context
        wake()
    }

    /// 翻譯加上逾時：翻譯、逾時、被取消三者誰先到就用誰；其餘的工作一併取消。
    private func translateWithTimeout(_ text: String, source: String, target: String) async throws -> String {
        let translation = self.translation
        let sleeper = self.sleeper
        let timeout = configuration.translationTimeout
        let gate = ResumeGate<String>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                gate.attach(continuation)
                let work = Task {
                    do {
                        let result = try await translation.translate(text, source: source, target: target)
                        gate.resume(with: .success(result))
                    } catch {
                        gate.resume(with: .failure(error))
                    }
                }
                let timer = Task {
                    do {
                        try await sleeper.sleep(for: timeout)
                        gate.resume(with: .failure(AppError.translationFailed))
                    } catch {
                        // 被取消：翻譯已經先完成或整個流程被停止。
                    }
                }
                gate.onFinish {
                    work.cancel()
                    timer.cancel()
                }
            }
        } onCancel: {
            gate.resume(with: .failure(CancellationError()))
        }
    }

    /// 倒數後自動播放；設定「先確認再播」時直接等使用者按播放。
    private func countdownThenPlay() async {
        guard !settings.confirmBeforePlay else {
            countdownRemaining = nil
            move(to: .readyToPlayForPartner(countdown: nil))
            return
        }
        var remaining = configuration.playbackCountdown
        while remaining > 0 {
            countdownRemaining = remaining
            move(to: .readyToPlayForPartner(countdown: remaining))
            do {
                try await sleeper.sleep(for: .seconds(1))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            remaining -= 1
        }
        countdownRemaining = nil
        await playPending()
    }

    private func playPending() async {
        guard let pending = pendingUtterance else { return }
        isEditing = false
        countdownRemaining = nil
        let text = editableTranslation
        if let id = pendingEntryID, let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].translation = text
        } else {
            let entry = ConversationEntry(speaker: .user, direction: pending.direction, original: pending.original,
                                          translation: text, timestamp: now())
            entries.append(entry)
            pendingEntryID = entry.id
        }
        await speak(text, direction: pending.direction, as: .speakingPartnerLanguage)
    }

    /// - Parameters:
    ///   - continuesConversation: 播完後是否依設定自動換下一個人說（重播時為 false）。
    ///   - resumeSpeaker: 重播前正在聽誰；播完繼續聽這一方。
    private func speak(_ text: String, direction: TranslationDirection, as speakingState: ConversationState,
                       continuesConversation: Bool = true, resumeSpeaker: Speaker? = nil) async {
        let languageID = LocaleMapping.voiceLanguageID(for: direction)
        switch synthesis.voiceMatch(forLanguageID: languageID) {
        case .exact:
            break
        case .fallback(let actual):
            notice = "找不到 \(languageID) 的標準語音，改用 \(actual)。"
        case .none:
            notice = direction.speaker == .user
                ? "這台 iPhone 沒有 \(languageID) 的語音，請讓對方看畫面上的文字。"
                : "這台 iPhone 沒有 \(languageID) 的語音，請看畫面上的翻譯文字。"
            if case .readyToPlayForPartner = state {
                move(to: .readyToPlayForPartner(countdown: nil))
            } else if state != .idle {
                move(to: .idle)
            }
            finishTurn()
            return
        }
        let overridden = overrideOutputIfNeeded(for: direction)
        defer { if overridden { restoreOutput() } }
        move(to: speakingState)
        do {
            try await synthesis.speak(text, languageID: languageID)
        } catch is CancellationError {
            // 被停止或取消：下面依是否被取消決定要不要收尾。
        } catch {
            if !Task.isCancelled { fail(.synthesisInterrupted) }
            return
        }
        guard !Task.isCancelled else { return }
        lastPlayed = (text: text, languageID: languageID)
        if state == speakingState { move(to: .idle) }
        finishTurn()
        if continuesConversation {
            scheduleNextTurn(after: direction)
        } else if let next = queuedSpeaker ?? resumeSpeaker {
            scheduleTurn(next)
        }
    }

    /// 自動輪流：換另一方。手動模式且開了「對方說完繼續聆聽」：再聽對方。
    /// 一律先等 postPlaybackMicGuard，避免把喇叭殘響收進麥克風。
    private func scheduleNextTurn(after direction: TranslationDirection) {
        let next: Speaker
        if let queued = queuedSpeaker {
            next = queued   // 使用者按了按鈕指定下一句（兩種模式都適用）
        } else {
            switch settings.mode {
            case .autoAlternate:
                next = direction.speaker.other
            case .manual:
                guard settings.continueListeningAfterPartner, direction.speaker == .partner else { return }
                next = .partner
            }
        }
        if settings.mode == .autoAlternate { currentTurn = next }
        scheduleTurn(next)
    }

    /// 等 postPlaybackMicGuard 後開始聽指定的一方（仍在待機才開始）。
    private func scheduleTurn(_ next: Speaker) {
        let sleeper = self.sleeper
        let micGuard = configuration.postPlaybackMicGuard
        activeTask = Task { [weak self] in
            do {
                try await sleeper.sleep(for: micGuard)
            } catch {
                return
            }
            guard !Task.isCancelled, let self, self.state == .idle else { return }
            self.startTurn(next)
        }
    }

    /// 外語要給對方聽：有耳機時暫時切到手機喇叭；「一律用手機喇叭」時兩個方向都切。
    /// 回傳是否有要求切換（之後要切回來）。
    private func overrideOutputIfNeeded(for direction: TranslationDirection) -> Bool {
        let current = audio.currentRoute
        route = current
        guard current.kind != .speaker else { return false }
        let wantsSpeaker: Bool
        switch settings.outputPreference {
        case .alwaysSpeaker: wantsSpeaker = true
        case .automatic: wantsSpeaker = direction.speaker == .user && current.kind.isHeadset
        }
        guard wantsSpeaker else { return false }
        do {
            let actual = try audio.setOutput(.speaker)
            route = actual
            outputOverridden = true
            if actual.kind != .speaker { notice = Self.speakerOverrideFailureNotice }
            return true
        } catch {
            notice = Self.speakerOverrideFailureNotice
            return false
        }
    }

    private func restoreOutput() {
        guard outputOverridden else { return }
        outputOverridden = false
        route = (try? audio.setOutput(.systemDefault)) ?? audio.currentRoute
    }

    private func clearPending() {
        pendingUtterance = nil
        pendingEntryID = nil
        editableTranslation = ""
        isEditing = false
        countdownRemaining = nil
    }

    private func ensurePermissions() async -> Bool {
        var snapshot = await permissions.current()
        if snapshot.microphone == .notDetermined || snapshot.speech == .notDetermined {
            snapshot = await permissions.request()
        }
        guard !Task.isCancelled else { return false }
        if snapshot.microphone != .granted {
            denyPermission(.microphoneDenied)
            return false
        }
        if snapshot.speech != .granted {
            denyPermission(.speechRecognitionDenied)
            return false
        }
        return true
    }

    private func denyPermission(_ error: AppError) {
        lastError = error
        move(to: .needsPermission)
        finishTurn()
    }

    private func prepareLanguage() {
        guard let pair = pendingPreparePair else {
            lastError = nil
            move(to: .idle)
            return
        }
        activeTask?.cancel()
        activeTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.translation.prepare(source: pair.source, target: pair.target)
                guard !Task.isCancelled else { return }
                self.pendingPreparePair = nil
                self.lastError = nil
                self.move(to: .idle)
            } catch {
                guard !Task.isCancelled else { return }
                self.lastError = (error as? AppError) ?? .modelDownloadCancelled
                self.move(to: .languageNotReady)
            }
        }
    }

    // MARK: 收尾與取消

    private func fail(_ error: AppError) {
        logger("error \(error.category)")
        queuedSpeaker = nil
        stopRecognition()
        listening = nil
        partialTranscript = ""
        lastError = error
        move(to: .error(error))
        finishTurn()
    }

    private func finishTurn() {
        activeTurn = nil
    }

    private func stopRecognition() {
        if recognitionActive {
            recognition.cancel()
            recognitionActive = false
        }
    }

    private func cancelCurrentWork() {
        activeTask?.cancel()
        activeTask = nil
        wake()
        stopRecognition()
        listening = nil
        if state.isSpeaking { synthesis.stop() }
        restoreOutput()
        countdownRemaining = nil
        activeTurn = nil
    }

    private func sleepUnlessWoken(for duration: Duration) async {
        let sleeper = self.sleeper
        let task = Task { try await sleeper.sleep(for: duration) }
        wakeTask = task
        _ = await task.result
        if wakeTask == task { wakeTask = nil }
    }

    private func wake() {
        wakeTask?.cancel()
        wakeTask = nil
    }

    private func move(to next: ConversationState) {
        do {
            try machine.transition(to: next)
            state = next
        } catch {
            logger("invalid transition")
            assertionFailure("不允許的狀態轉換：\(error.from) → \(error.to)")
        }
    }

    /// "en-US" 與 "en-US"、"zh-TW" 與 "zh-TW"：比較語言部分。
    private static func sameLanguage(_ a: String, _ b: String) -> Bool {
        a.split(separator: "-").first == b.split(separator: "-").first
    }

    private static func recognitionError(_ error: Error, localeID: String) -> AppError {
        (error as? AppError) ?? .recognizerUnavailable(localeID: localeID)
    }
}
