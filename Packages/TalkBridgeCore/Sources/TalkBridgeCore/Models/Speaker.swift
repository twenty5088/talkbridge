/// 誰在說話：對方（外語）或使用者（中文）。
public enum Speaker: String, Sendable, CaseIterable {
    case partner
    case user

    /// 輪流對話中的另一方。
    public var other: Speaker {
        switch self {
        case .partner: .user
        case .user: .partner
        }
    }
}
