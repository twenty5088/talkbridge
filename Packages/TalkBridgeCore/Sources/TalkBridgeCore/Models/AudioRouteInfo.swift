/// 聲音實際從哪裡出來（顯示給使用者看的是「實際」路由，不是期望路由）。
public enum AudioOutputKind: Equatable, Sendable {
    case airPods, bluetooth, speaker, receiver, headphones, unknown

    public var displayName: String {
        switch self {
        case .airPods: "AirPods"
        case .bluetooth: "藍牙耳機"
        case .speaker: "手機喇叭"
        case .receiver: "聽筒"
        case .headphones: "有線耳機"
        case .unknown: "未知"
        }
    }

    public var symbolName: String {
        switch self {
        case .airPods: "airpods"
        case .bluetooth: "headphones"
        case .speaker: "speaker.wave.2.fill"
        case .receiver: "iphone"
        case .headphones: "headphones"
        case .unknown: "questionmark.circle"
        }
    }

    /// 戴在使用者耳朵上的輸出（外語要給對方聽時需暫時改到手機喇叭）。
    public var isHeadset: Bool {
        switch self {
        case .airPods, .bluetooth, .headphones: true
        case .speaker, .receiver, .unknown: false
        }
    }
}

public struct AudioRouteInfo: Equatable, Sendable {
    public var kind: AudioOutputKind
    public var portName: String?

    public init(kind: AudioOutputKind, portName: String? = nil) {
        self.kind = kind
        self.portName = portName
    }

    /// 由 AVAudioSession.Port 的 rawValue 對照。放在 Core 是為了不依賴 AVFoundation 也能測試。
    public static func from(portType: String, portName: String) -> AudioRouteInfo {
        let kind: AudioOutputKind
        switch portType {
        case "BluetoothA2DPOutput", "BluetoothHFP", "BluetoothLE":
            kind = portName.localizedCaseInsensitiveContains("AirPods") ? .airPods : .bluetooth
        case "Speaker": kind = .speaker
        case "Receiver": kind = .receiver
        case "Headphones", "USBAudio": kind = .headphones
        default: kind = .unknown
        }
        return AudioRouteInfo(kind: kind, portName: portName)
    }

    public static let unknown = AudioRouteInfo(kind: .unknown)
}
