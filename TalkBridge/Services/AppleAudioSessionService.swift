import AVFoundation
import TalkBridgeCore

/// AVAudioSession 的正式實作。
///
/// 設定（見設計文件 §4.2）：.playAndRecord＋.allowBluetoothA2DP＋.defaultToSpeaker，**不加 HFP**。
/// 預期效果：有藍牙耳機時播放走耳機（高音質）、收音一律用 iPhone 內建麥克風；沒有耳機時走手機喇叭。
/// 實際路由一律從 currentRoute 讀出來顯示，不假設切換一定成功。
@MainActor
final class AppleAudioSessionService: AudioSessionService {
    private let session = AVAudioSession.sharedInstance()
    private let continuation: AsyncStream<AudioSessionEvent>.Continuation
    private var configured = false

    let events: AsyncStream<AudioSessionEvent>

    init() {
        let (stream, continuation) = AsyncStream<AudioSessionEvent>.makeStream()
        events = stream
        self.continuation = continuation
        observeNotifications()
    }

    var currentRoute: AudioRouteInfo {
        guard let output = session.currentRoute.outputs.first else { return .unknown }
        return AudioRouteInfo.from(portType: output.portType.rawValue, portName: output.portName)
    }

    func activate() throws {
        do {
            if !configured {
                try session.setCategory(.playAndRecord, mode: .default,
                                        options: [.allowBluetoothA2DP, .defaultToSpeaker])
                configured = true
            }
            try session.setActive(true)
        } catch {
            throw AppError.audioSessionFailed
        }
    }

    func setOutput(_ target: OutputTarget) throws -> AudioRouteInfo {
        do {
            switch target {
            case .speaker: try session.overrideOutputAudioPort(.speaker)
            case .systemDefault: try session.overrideOutputAudioPort(.none)
            }
        } catch {
            throw AppError.audioSessionFailed
        }
        return currentRoute
    }

    func deactivate() {
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: 系統通知 → AudioSessionEvent

    private func observeNotifications() {
        let center = NotificationCenter.default
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap(AVAudioSession.RouteChangeReason.init(rawValue:))
            let oldDeviceUnavailable = reason == .oldDeviceUnavailable
            MainActor.assumeIsolated {
                guard let self else { return }
                self.continuation.yield(.routeChanged(self.currentRoute, oldDeviceUnavailable: oldDeviceUnavailable))
            }
        }
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            MainActor.assumeIsolated {
                switch type {
                case .began: self?.continuation.yield(.interruptionBegan)
                case .ended: self?.continuation.yield(.interruptionEnded)
                default: break
                }
            }
        }
        center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // 媒體服務重置後所有音訊設定都失效，下次 activate 要重新設定。
                self?.configured = false
                self?.continuation.yield(.mediaServicesReset)
            }
        }
    }
}
