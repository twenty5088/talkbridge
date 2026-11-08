/// 一句話從「判定說完」到「開始出聲」各階段花的時間（只記時間，不記內容）。
/// Kevin 2026-11-08：用來在太太手機上看出是哪一段慢。
public struct TurnTimings: Equatable, Sendable {
    /// 判定說完 → 拿到最後辨識文字。
    public var finishing: Duration?
    public var translation: Duration?
    /// 只有中文翻外語、自動倒數時才有。
    public var countdown: Duration?
    /// 叫聲音播放 → 真的開始出聲。
    public var voiceStart: Duration?

    public init(finishing: Duration? = nil, translation: Duration? = nil,
                countdown: Duration? = nil, voiceStart: Duration? = nil) {
        self.finishing = finishing
        self.translation = translation
        self.countdown = countdown
        self.voiceStart = voiceStart
    }

    /// 例如「收尾 0.8 秒・翻譯 1.3 秒・倒數 1.0 秒・出聲 0.3 秒」；沒有的階段不列。
    public var summary: String {
        [("收尾", finishing), ("翻譯", translation), ("倒數", countdown), ("出聲", voiceStart)]
            .compactMap { label, duration in duration.map { "\(label) \(Self.seconds($0)) 秒" } }
            .joined(separator: "・")
    }

    /// 四捨五入到 0.1 秒（不用 String(format:)，Linux 測試也一樣）。
    private static func seconds(_ duration: Duration) -> String {
        let (s, attoseconds) = duration.components
        let milliseconds = s * 1000 + attoseconds / 1_000_000_000_000_000
        let tenths = (milliseconds + 50) / 100
        return "\(tenths / 10).\(tenths % 10)"
    }
}
