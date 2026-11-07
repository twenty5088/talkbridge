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
/// 3. `process` 依序取出同一語言對的工作，把結果交回各自的 continuation。
@MainActor
@Observable
final class AppleTranslationService: TranslationService {
    struct Job: Sendable {
        enum Kind: Sendable {
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

    /// 取出下一個屬於目前語言對的工作；語言對已經換掉的舊工作直接作廢。
    func nextJob() -> Job? {
        while !jobs.isEmpty {
            let job = jobs.removeFirst()
            if let pair = configuredPair, pair.source == job.source, pair.target == job.target {
                return job
            }
            job.continuation.resume(throwing: AppError.translationFailed)
        }
        return nil
    }

    /// 由 TranslationHostView 的 translationTask 呼叫。在同一個 Task 裡依序使用 session。
    nonisolated static func process(_ box: TranslationSessionBox, service: AppleTranslationService) async {
        while let job = await service.nextJob() {
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
