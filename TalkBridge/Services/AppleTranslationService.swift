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
    struct Pair: Equatable, Sendable {
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
        try await enqueue(.translate(text), pair: Pair(source: source, target: target))
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
