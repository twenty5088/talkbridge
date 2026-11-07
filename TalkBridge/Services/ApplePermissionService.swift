import AVFoundation
import Speech
import TalkBridgeCore

/// 麥克風與語音辨識權限。第一次使用功能時才請求（由 ViewModel 決定時機）。
final class ApplePermissionService: PermissionService {
    func current() async -> PermissionSnapshot {
        PermissionSnapshot(microphone: Self.microphoneState(), speech: Self.speechState())
    }

    func request() async -> PermissionSnapshot {
        if AVAudioApplication.shared.recordPermission == .undetermined {
            _ = await AVAudioApplication.requestRecordPermission()
        }
        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            _ = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        }
        return await current()
    }

    private static func microphoneState() -> PermissionState {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        case .undetermined: .notDetermined
        @unknown default: .denied
        }
    }

    private static func speechState() -> PermissionState {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .denied
        }
    }
}
