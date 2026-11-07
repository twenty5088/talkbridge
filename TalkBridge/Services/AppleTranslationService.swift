import Foundation
import Observation
import TalkBridgeCore
import Translation

/// Apple Translation framework 的集中整合（原需求 §八-10）。
///
/// Translation framework 只能透過 SwiftUI 的 `.translationTask` 取得 TranslationSession，
/// 所以整個 App 只有 `TranslationHostView` 一處掛 `.translationTask`，由這個服務驅動：
/// 1. ViewModel 呼叫 translate／prepare → 工作排進佇列，設定（或 invalidate）configuration。
/// 2. SwiftUI 因 configuration 變化重新執行 translationTask，把 session 交給 `run(_:)`。
/// 3. `run` 依序處理佇列裡同一語言對的工作，把結果交回各自的 continuation。
@MainActor
@Observable
final class AppleTranslationService: TranslationService {
    private struct Job {
        enum Kind {
            case translate(String)
            case prepare
        }
        let kind: Kind
        let source: String
        let target: String
        let continuation: CheckedContinuation<String, Error>
    }

    /// TranslationHostView 觀察這個值。
    private(set) var configuration: TranslationSession.Configuration?

    @ObservationIgnored private var jobs: [Job] = []
    @ObservationIgnored private var configuredPair: (source: String, target: String)?

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
        _ = try await enqueue(.prepare, source: source, target: target)
    }

    nonisolated func translate(_ text: String, source: String, target: String) async throws -> String {
        try await enqueue(.translate(text), source: source, target: target)
    }

    private func enqueue(_ kind: Job.Kind, source: String, target: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            jobs.append(Job(kind: kind, source: source, target: target, continuation: continuation))
            if let pair = configuredPair, pair.source == source, pair.target == target, configuration != nil {
                configuration?.invalidate()   // 同一語言對：讓 translationTask 再跑一次
            } else {
                configuredPair = (source, target)
                configuration = TranslationSession.Configuration(source: Locale.Language(identifier: source),
                                                                 target: Locale.Language(identifier: target))
            }
        }
    }

    /// 由 TranslationHostView 的 translationTask 呼叫。
    func run(_ session: TranslationSession) async {
        while !jobs.isEmpty {
            let job = jobs.removeFirst()
            guard let pair = configuredPair, pair.source == job.source, pair.target == job.target else {
                // 語言對已經換了（例如使用者換語言），這個工作作廢。
                job.continuation.resume(throwing: AppError.translationFailed)
                continue
            }
            switch job.kind {
            case .prepare:
                do {
                    try await session.prepareTranslation()
                    job.continuation.resume(returning: "")
                } catch {
                    job.continuation.resume(throwing: AppError.modelDownloadCancelled)
                }
            case .translate(let text):
                do {
                    let response = try await session.translate(text)
                    job.continuation.resume(returning: response.targetText)
                } catch {
                    job.continuation.resume(throwing: AppError.translationFailed)
                }
            }
        }
    }
}
