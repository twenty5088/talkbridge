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
    public private(set) var lastError: AppError?
    public var partnerLanguage: PartnerLanguage = .english
    public var settings: AppSettings

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
        currentTurn = nil
        partialTranscript = ""
        if state != .idle { move(to: .idle) }
    }

    public func clearHistory() {
        entries.removeAll()
    }

    /// 重播某一句的翻譯。只播放，不開麥克風。
    public func replay(_ entryID: UUID) {
        guard !state.isBusy, let entry = entries.first(where: { $0.id == entryID }) else { return }
        if state != .idle { move(to: .idle) }
        lastError = nil
        let speakingState: ConversationState = entry.direction.speaker == .partner ? .speakingChinese : .speakingPartnerLanguage
        activeTask = Task { [weak self] in
            await self?.speak(entry.translation, direction: entry.direction, as: speakingState)
        }
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
        case .retry, .chooseAnotherLanguage, .dismiss:
            lastError = nil
            move(to: .idle)
        }
    }

    // MARK: 流程

    private func buttonTapped(_ speaker: Speaker) {
        if state.isSpeaking {
            stopAll()
            return
        }
        if activeTurn == speaker {
            if state.isMicrophoneActive { requestEndOfUtterance() }
            return   // 正在準備、辨識或翻譯：忽略重複點擊
        }
        startTurn(speaker)
    }

    private func startTurn(_ speaker: Speaker) {
        cancelCurrentWork()
        notice = nil
        lastError = nil
        partialTranscript = ""
        if state != .idle { move(to: .idle) }
        activeTurn = speaker
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

        guard UtteranceEndDetector.isMeaningful(text, configuration: configuration) else {
            notice = Self.emptyTranscriptNotice
            partialTranscript = ""
            move(to: .idle)
            finishTurn()
            return
        }

        move(to: speaker == .partner ? .translatingToChinese : .translatingToPartnerLanguage)
        let translated: String
        do {
            translated = try await translation.translate(text, source: pair.source, target: pair.target)
        } catch is CancellationError {
            return
        } catch {
            if !Task.isCancelled { fail((error as? AppError) ?? .translationFailed) }
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
            // 模式 B 的倒數與播放在 Task 8 實作。
            move(to: .readyToPlayForPartner(countdown: nil))
            finishTurn()
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
        let detector = UtteranceEndDetector(configuration: configuration)
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
                notice = AppError.noSpeechDetected.userMessage
                move(to: .idle)
                finishTurn()
                return nil
            }
            await sleepUnlessWoken(for: nextDeadline(for: context) - current)
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

    private func nextDeadline(for context: ListeningContext) -> Duration {
        let maxDeadline = context.start + configuration.maxUtteranceDuration
        if let lastChange = context.lastChange {
            return min(maxDeadline, lastChange + configuration.silenceTimeout)
        }
        return min(maxDeadline, context.start + configuration.autoTurnIdleTimeout)
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

    private func speak(_ text: String, direction: TranslationDirection, as speakingState: ConversationState) async {
        move(to: speakingState)
        do {
            try await synthesis.speak(text, languageID: LocaleMapping.voiceLanguageID(for: direction))
        } catch is CancellationError {
            // 被停止或取消：下面依是否被取消決定要不要收尾。
        } catch {
            if !Task.isCancelled { fail(.synthesisInterrupted) }
            return
        }
        guard !Task.isCancelled else { return }
        if state == speakingState { move(to: .idle) }
        finishTurn()
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

    private static func recognitionError(_ error: Error, localeID: String) -> AppError {
        (error as? AppError) ?? .recognizerUnavailable(localeID: localeID)
    }
}
