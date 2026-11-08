import Foundation
import Observation
import TalkBridgeCore
import Translation

/// TranslationSession 不是 Sendable。整個 App 只在 TranslationHostView 的 translationTask 裡
/// 用同一個 Task 依序使用它，從不並行，所以用這個盒子把它帶進非主執行緒的處理函式。
struct TranslationSessionBox: @unchecked Sendable {
    let session: TranslationSession
}

/// Apple Translation framework 的集中整合（原需求 §八-10）。
///
/// Translation framework 只能透過 SwiftUI 的 `.translationTask` 取得 TranslationSession，
/// 所以整個 App 只有 `TranslationHostView` 一處掛 `.translationTask`，由這個服務驅動：
/// 1. ViewModel 呼叫 translate／prepare → 工作排進佇列，設定（或 invalidate）configuration。
/// 2. SwiftUI 因 configuration 變化重新執行 translationTask，呼叫 `process(_:service:)`。
/// 3. `process` 記下這次 session 的語言對，只處理同一語言對的工作；其他語言對的工作留給下一次。
/// 4. 呼叫端取消（停止、逾時）時，還沒處理的工作會從佇列移除。
@MainActor
@Observable
final class AppleTranslationService: TranslationService {
    struct Pair: Hashable, Sendable {
        let source: String
        let target: String
    }

    struct Job: Sendable {
        enum Kind: Sendable {
            case translate(String)
            case prepare
        }
        let id: UUID
        let kind: Kind
        let pair: Pair
        let continuation: CheckedContinuation<String, Error>
    }

    /// TranslationHostView 觀察這個值。
    private(set) var configuration: TranslationSession.Configuration?

    @ObservationIgnored private var jobs: [Job] = []
    @ObservationIgnored private var configuredPair: Pair?
    /// iOS 26 起：每個已安裝的語言對各留一個一直開著的翻譯工作，不用每句重新載入模型（Kevin 2026-11-08）。
    @ObservationIgnored private var readySessions: [Pair: TranslationSessionBox] = [:]
    /// 正在預熱的語言對；真的翻譯前先等它做完，避免同一個翻譯工作同時被用兩次。
    @ObservationIgnored private var warmUps: [Pair: Task<Void, Never>] = [:]

    nonisolated func readiness(source: String, target: String) async -> TranslationReadiness {
        let status = await LanguageAvailability().status(from: Locale.Language(identifier: source),
                                                         to: Locale.Language(identifier: target))
        switch status {
        case .installed: return .installed
        case .supported: return .needsDownload
        case .unsupported: return .unsupported
        @unknown default: return .unsupported
        }
    }

    nonisolated func prepare(source: String, target: String) async throws {
        _ = try await enqueue(.prepare, pair: Pair(source: source, target: target))
    }

    nonisolated func translate(_ text: String, source: String, target: String) async throws -> String {
        let pair = Pair(source: source, target: target)
        if #available(iOS 26.0, *), let box = await readySession(for: pair) {
            do {
                return try await box.session.translate(text).targetText
            } catch {
                if error is CancellationError || Task.isCancelled { throw CancellationError() }
                await dropSession(for: pair)   // 下次重新建立；模型被刪掉時會改走下載流程
                throw AppError.translationFailed
            }
        }
        return try await enqueue(.translate(text), pair: pair)
    }

    /// 對話開始時呼叫：先翻一個短句，讓模型載入記憶體。沒安裝的語言對不做事。
    nonisolated func warmUp(source: String, target: String) async {
        guard #available(iOS 26.0, *) else { return }
        await startWarmUp(Pair(source: source, target: target))?.value
    }

    @available(iOS 26.0, *)
    private func startWarmUp(_ pair: Pair) async -> Task<Void, Never>? {
        if let running = warmUps[pair] { return running }
        guard let box = await session(for: pair) else { return nil }
        if let running = warmUps[pair] { return running }
        let text = Self.warmUpText(source: pair.source)
        let task = Task.detached { _ = try? await box.session.translate(text) }
        warmUps[pair] = task
        return task
    }

    @available(iOS 26.0, *)
    private func readySession(for pair: Pair) async -> TranslationSessionBox? {
        if let running = warmUps[pair] { await running.value }
        return await session(for: pair)
    }

    /// 已安裝的語言對才建立（不需要畫面的 iOS 26 寫法）；沒安裝的交給原本的 translationTask 流程處理下載。
    @available(iOS 26.0, *)
    private func session(for pair: Pair) async -> TranslationSessionBox? {
        if let box = readySessions[pair] { return box }
        guard await readiness(source: pair.source, target: pair.target) == .installed else { return nil }
        if let box = readySessions[pair] { return box }
        let box = TranslationSessionBox(session: TranslationSession(
            installedSource: Locale.Language(identifier: pair.source),
            target: Locale.Language(identifier: pair.target)))
        readySessions[pair] = box
        return box
    }

    private func dropSession(for pair: Pair) {
        readySessions[pair] = nil
        warmUps[pair] = nil
    }

    /// 用來源語言的一句問候語預熱（中文用中文、英文用英文…）。
    private nonisolated static func warmUpText(source: String) -> String {
        let base = source.split(separator: "-").first.map(String.init) ?? source
        return VoiceLanguage.all.first { $0.languageID.split(separator: "-").first.map(String.init) == base }?
            .sampleText ?? "Hello"
    }

    private func enqueue(_ kind: Job.Kind, pair: Pair) async throws -> String {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                jobs.append(Job(id: id, kind: kind, pair: pair, continuation: continuation))
                if configuredPair == pair, configuration != nil {
                    configuration?.invalidate()   // 同一語言對：讓 translationTask 再跑一次
                } else {
                    configuredPair = pair
                    configuration = TranslationSession.Configuration(source: Locale.Language(identifier: pair.source),
                                                                     target: Locale.Language(identifier: pair.target))
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.removeJob(id) }
        }
    }

    /// 呼叫端已取消：還沒被處理的工作直接移除，不再浪費時間翻譯。
    private func removeJob(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        let job = jobs.remove(at: index)
        job.continuation.resume(throwing: CancellationError())
    }

    /// translationTask 開始時記下的語言對（就是這次 session 的語言對）。
    func currentPair() -> Pair? { configuredPair }

    /// 取出下一個屬於指定語言對的工作；其他語言對的工作留在佇列等下一次 session。
    func nextJob(for pair: Pair) -> Job? {
        guard let index = jobs.firstIndex(where: { $0.pair == pair }) else { return nil }
        return jobs.remove(at: index)
    }

    /// 由 TranslationHostView 的 translationTask 呼叫。在同一個 Task 裡依序使用 session。
    nonisolated static func process(_ box: TranslationSessionBox, service: AppleTranslationService) async {
        guard let pair = await service.currentPair() else { return }
        while !Task.isCancelled, let job = await service.nextJob(for: pair) {
            switch job.kind {
            case .prepare:
                do {
                    try await box.session.prepareTranslation()
                    job.continuation.resume(returning: "")
                } catch {
                    job.continuation.resume(throwing: AppError.modelDownloadCancelled)
                }
            case .translate(let text):
                do {
                    let response = try await box.session.translate(text)
                    job.continuation.resume(returning: response.targetText)
                } catch {
                    job.continuation.resume(throwing: AppError.translationFailed)
                }
            }
        }
    }
}
