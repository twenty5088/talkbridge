import AVFoundation
import Speech
import TalkBridgeCore

/// SFSpeechRecognizer＋AVAudioEngine 的正式實作。
///
/// - 該語言支援裝置端辨識時一律 requiresOnDeviceRecognition；不支援時由 Apple 伺服器辨識（畫面會標示）。
/// - finishAudio：移除音訊 tap、停引擎、endAudio，等最終結果。
/// - cancel：同上並取消辨識工作，不送最終結果。
/// - 不記錄任何辨識文字。
///
/// 可變狀態都由 lock 保護，因此標成 @unchecked Sendable。
final class AppleSpeechRecognitionService: SpeechRecognitionService, @unchecked Sendable {
    private typealias Continuation = AsyncThrowingStream<RecognitionUpdate, Error>.Continuation

    /// SFSpeechAudioBufferRecognitionRequest.append 可以從音訊執行緒呼叫；用盒子包起來傳進 tap。
    private final class RequestBox: @unchecked Sendable {
        let request: SFSpeechAudioBufferRecognitionRequest
        init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }
    }

    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var continuation: Continuation?

    func mode(forLocaleID localeID: String) async -> RecognitionMode {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)), recognizer.isAvailable else {
            return .unavailable
        }
        return recognizer.supportsOnDeviceRecognition ? .onDevice : .server
    }

    func start(localeID: String) throws -> AsyncThrowingStream<RecognitionUpdate, Error> {
        cancel()   // 保險：絕不同時開兩個錄音引擎
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)), recognizer.isAvailable else {
            throw AppError.recognizerUnavailable(localeID: localeID)
        }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AppError.audioSessionFailed
        }
        let box = RequestBox(request)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            box.request.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw AppError.audioSessionFailed
        }

        let (stream, continuation) = AsyncThrowingStream<RecognitionUpdate, Error>.makeStream()
        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    continuation.yield(.final(text))
                    continuation.finish()
                    self?.stopAudio()
                } else {
                    continuation.yield(.partial(text))
                }
            } else if let error {
                continuation.finish(throwing: Self.map(error, localeID: localeID))
                self?.stopAudio()
            }
        }

        lock.withLock {
            self.engine = engine
            self.request = request
            self.task = task
            self.continuation = continuation
        }
        return stream
    }

    func finishAudio() {
        stopAudio()
        let request = lock.withLock { self.request }
        request?.endAudio()
    }

    func cancel() {
        stopAudio()
        let (task, continuation) = lock.withLock { () -> (SFSpeechRecognitionTask?, Continuation?) in
            let result = (self.task, self.continuation)
            self.task = nil
            self.request = nil
            self.continuation = nil
            return result
        }
        task?.cancel()
        continuation?.finish()
    }

    /// 移除 tap、停止引擎（麥克風關閉）。可重複呼叫。
    private func stopAudio() {
        let engine = lock.withLock { () -> AVAudioEngine? in
            let engine = self.engine
            self.engine = nil
            return engine
        }
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private static func map(_ error: Error, localeID: String) -> Error {
        let nsError = error as NSError
        // kAFAssistantErrorDomain 1110：沒有偵測到語音。
        if nsError.domain == "kAFAssistantErrorDomain", nsError.code == 1110 {
            return AppError.noSpeechDetected
        }
        return AppError.recognizerUnavailable(localeID: localeID)
    }
}
