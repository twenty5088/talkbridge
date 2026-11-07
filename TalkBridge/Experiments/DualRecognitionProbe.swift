import AVFoundation
import Observation
import Speech
import TalkBridgeCore

/// 【拋棄式實驗】v2 設計 §3.5：確認兩個 SFSpeechRecognizer 能否同時聽同一個麥克風，並收集真實分數。
/// 完整功能開發時整個 Experiments 資料夾移除。不寫任何辨識文字到 log，結果只在記憶體。
@MainActor
@Observable
final class DualRecognitionProbe {
    struct Side: Sendable {
        var localeID: String
        var onDevice = false
        var text = ""
        var isFinal = false
        var confidence: Double?
        var error: String?
        var finalAfter: Double?
    }

    struct Trial: Identifiable {
        let id = UUID()
        let spokeChinese: Bool
        let partnerLanguage: PartnerLanguage
        let chinese: Side
        let partner: Side
    }

    enum Phase { case idle, listening, finishing }

    var partnerLanguage: PartnerLanguage = .english
    var spokeChinese = true
    private(set) var phase: Phase = .idle
    private(set) var sides: [Side] = []
    private(set) var trials: [Trial] = []
    private(set) var status = ""

    @ObservationIgnored private var session: ProbeSession?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var endedAt: Date?

    func start() async {
        guard phase == .idle else { return }
        status = ""
        let permissions = ApplePermissionService()
        var snapshot = await permissions.current()
        if snapshot.microphone == .notDetermined || snapshot.speech == .notDetermined {
            snapshot = await permissions.request()
        }
        guard snapshot.microphone == .granted, snapshot.speech == .granted else {
            status = "沒有麥克風或語音辨識權限"
            return
        }
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord, mode: .default, options: [.allowBluetoothA2DP, .defaultToSpeaker])
            try audio.setActive(true)
        } catch {
            status = "音訊無法啟動：\((error as NSError).code)"
            return
        }
        generation += 1
        let localeIDs = [ChineseLocale.speechLocaleID,
                         LocaleMapping.speechLocaleID(for: .partnerToChinese(partnerLanguage))]
        sides = localeIDs.map { Side(localeID: $0) }
        endedAt = nil
        do {
            let (session, onDevice, errors) = try Self.begin(localeIDs: localeIDs, generation: generation, probe: self)
            self.session = session
            for index in sides.indices {
                sides[index].onDevice = onDevice[index]
                sides[index].error = errors[index]
            }
            phase = .listening
        } catch {
            status = "麥克風無法啟動"
        }
    }

    /// 說完了：停麥克風、送出結束，最多等 3 秒最終結果，然後記一筆。
    func finish() async {
        guard phase == .listening, let session else { return }
        phase = .finishing
        endedAt = Date()
        session.endAudio()
        let myGeneration = generation
        for _ in 0..<30 {
            if sides.allSatisfy({ $0.isFinal || $0.error != nil }) { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard generation == myGeneration, sides.count == 2 else { return }
        trials.insert(Trial(spokeChinese: spokeChinese, partnerLanguage: partnerLanguage,
                            chinese: sides[0], partner: sides[1]), at: 0)
        session.cancel()
        self.session = nil
        phase = .idle
    }

    func clear() { trials.removeAll() }

    /// 給 Kevin 貼回來的純文字結果。
    var report: String {
        trials.reversed().enumerated().map { number, trial in
            let spoken = trial.spokeChinese ? "中文" : trial.partnerLanguage.displayName
            return "#\(number + 1) 實際說：\(spoken)\n" + [trial.chinese, trial.partner].map(Self.describe).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    static func describe(_ side: Side) -> String {
        let confidence = side.confidence.map { String(format: "%.2f", $0) } ?? "-"
        let ratio = String(format: "%.2f", ScriptScore.ratio(side.text, localeID: side.localeID))
        let after = side.finalAfter.map { String(format: "%.1fs", $0) } ?? "-"
        let place = side.onDevice ? "手機" : "伺服器"
        let error = side.error.map { " 錯誤:\($0)" } ?? ""
        return "[\(side.localeID) \(place)] 信心 \(confidence) 文字比例 \(ratio) 最終 \(after)\(error)\n  「\(side.text)」"
    }

    // MARK: 來自辨識回呼（已切回主執行緒）

    fileprivate func receive(index: Int, generation: Int, text: String, isFinal: Bool, confidence: Double?) {
        guard generation == self.generation, sides.indices.contains(index) else { return }
        sides[index].text = text
        if isFinal {
            sides[index].isFinal = true
            sides[index].confidence = confidence
            sides[index].finalAfter = endedAt.map { Date().timeIntervalSince($0) }
        }
    }

    fileprivate func receiveError(index: Int, generation: Int, description: String) {
        guard generation == self.generation, sides.indices.contains(index), !sides[index].isFinal else { return }
        sides[index].error = description
    }

    /// 在非主執行緒的函式裡建立回呼，避免回呼被當成主執行緒專用而在背景執行緒當掉。
    nonisolated private static func begin(localeIDs: [String], generation: Int,
                                          probe: DualRecognitionProbe) throws -> (ProbeSession, [Bool], [String?]) {
        var recognizers: [SFSpeechRecognizer] = []
        var requests: [SFSpeechAudioBufferRecognitionRequest] = []
        var tasks: [SFSpeechRecognitionTask] = []
        var onDevice: [Bool] = []
        var errors: [String?] = []
        for (index, localeID) in localeIDs.enumerated() {
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)), recognizer.isAvailable else {
                onDevice.append(false)
                errors.append("此語言辨識器不可用")
                continue
            }
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
            onDevice.append(recognizer.supportsOnDeviceRecognition)
            errors.append(nil)
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let result {
                    let text = result.bestTranscription.formattedString
                    let segments = result.bestTranscription.segments
                    let isFinal = result.isFinal
                    let confidence: Double? = isFinal && !segments.isEmpty
                        ? segments.reduce(0) { $0 + Double($1.confidence) } / Double(segments.count) : nil
                    Task { @MainActor in
                        probe.receive(index: index, generation: generation, text: text, isFinal: isFinal,
                                      confidence: confidence)
                    }
                } else if let error {
                    let nsError = error as NSError
                    let description = "\(nsError.domain) \(nsError.code)"
                    Task { @MainActor in
                        probe.receiveError(index: index, generation: generation, description: description)
                    }
                }
            }
            recognizers.append(recognizer)
            requests.append(request)
            tasks.append(task)
        }

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            tasks.forEach { $0.cancel() }
            throw AppError.audioSessionFailed
        }
        let box = ProbeSession.RequestsBox(requests)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            for request in box.requests { request.append(buffer) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            tasks.forEach { $0.cancel() }
            throw AppError.audioSessionFailed
        }
        return (ProbeSession(engine: engine, recognizers: recognizers, requests: requests, tasks: tasks), onDevice, errors)
    }
}

/// 一次實驗的錄音引擎與兩個辨識工作。
final class ProbeSession {
    final class RequestsBox: @unchecked Sendable {
        let requests: [SFSpeechAudioBufferRecognitionRequest]
        init(_ requests: [SFSpeechAudioBufferRecognitionRequest]) { self.requests = requests }
    }

    private let engine: AVAudioEngine
    private let recognizers: [SFSpeechRecognizer]   // 辨識期間保持存活
    private let requests: [SFSpeechAudioBufferRecognitionRequest]
    private let tasks: [SFSpeechRecognitionTask]
    private var audioStopped = false

    init(engine: AVAudioEngine, recognizers: [SFSpeechRecognizer],
         requests: [SFSpeechAudioBufferRecognitionRequest], tasks: [SFSpeechRecognitionTask]) {
        self.engine = engine
        self.recognizers = recognizers
        self.requests = requests
        self.tasks = tasks
    }

    func endAudio() {
        stopEngine()
        requests.forEach { $0.endAudio() }
    }

    func cancel() {
        stopEngine()
        tasks.forEach { $0.cancel() }
    }

    private func stopEngine() {
        guard !audioStopped else { return }
        audioStopped = true
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}

/// 辨識文字裡「屬於該語言文字系統」的字母比例（0～1）。完整功能的判斷規則會從這裡出發。
enum ScriptScore {
    static func ratio(_ text: String, localeID: String) -> Double {
        var letters = 0
        var matching = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            letters += 1
            if matches(scalar.value, localeID: localeID) { matching += 1 }
        }
        return letters == 0 ? 0 : Double(matching) / Double(letters)
    }

    private static func matches(_ v: UInt32, localeID: String) -> Bool {
        let han = (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v)
        let kana = (0x3040...0x30FF).contains(v)
        let latin = (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v) || (0xC0...0x24F).contains(v)
        let thai = (0x0E00...0x0E7F).contains(v)
        let hangul = (0xAC00...0xD7AF).contains(v) || (0x1100...0x11FF).contains(v) || (0x3130...0x318F).contains(v)
        switch localeID.prefix(2) {
        case "zh": return han
        case "ja": return han || kana
        case "th": return thai
        case "ko": return hangul
        default: return latin
        }
    }
}
