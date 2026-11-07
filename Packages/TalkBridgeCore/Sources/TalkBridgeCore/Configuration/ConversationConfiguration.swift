/// 對話流程的可調整數值，全部集中在這裡（原需求 §五 C-4）。
public struct ConversationConfiguration: Sendable, Equatable {
    /// 有說話後，停頓多久算一句話結束。
    public var silenceTimeout: Duration = .milliseconds(1200)
    /// 單句最長錄音時間，到了就先翻譯這一段。
    public var maxUtteranceDuration: Duration = .seconds(30)
    /// 模式 B 翻譯完成後自動播放前的倒數秒數。
    public var playbackCountdown: Int = 2
    /// 播放結束到重新開麥克風的保護間隔，避免收到喇叭殘響。
    public var postPlaybackMicGuard: Duration = .milliseconds(300)
    /// 開始聆聽後一直沒有任何辨識結果的等待上限（自動輪流用來暫停）。
    public var autoTurnIdleTimeout: Duration = .seconds(15)
    /// 送出結束後等待最終辨識結果的上限，逾時就用最後一次部分結果。
    public var finalResultTimeout: Duration = .seconds(2)
    /// 去掉空白與標點後至少要有幾個字才算有效語句。
    public var minimumMeaningfulCharacters: Int = 1
    /// 翻譯最長等待時間；逾時顯示「翻譯沒有成功」並可再試（避免永遠停在「正在翻譯」）。
    public var translationTimeout: Duration = .seconds(20)

    public init() {}

    public static let standard = ConversationConfiguration()
}
