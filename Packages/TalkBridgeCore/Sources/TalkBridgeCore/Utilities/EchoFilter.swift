/// 判斷剛聽到的話是不是喇叭播出的譯文殘響（v2 設計 P8）。純函式。
public enum EchoFilter {
    /// 只比字母與數字（忽略大小寫、空白、標點）；相似度＝最長共同子序列長度／較長者長度。
    public static func isLikelyEcho(heard: String, played: String, threshold: Double) -> Bool {
        let a = normalized(heard)
        let b = normalized(played)
        // 太短的話（「謝謝」「OK」）對方很可能真的照說一次，不當成殘響。
        guard a.count >= minimumCharacters, b.count >= minimumCharacters else { return false }
        let lcs = longestCommonSubsequence(a, b)
        return Double(lcs) / Double(max(a.count, b.count)) >= threshold
    }

    /// 去掉標點後至少要幾個字母／數字才比對。
    public static let minimumCharacters = 4

    static func normalized(_ text: String) -> [Character] {
        text.lowercased().filter { $0.isLetter || $0.isNumber }.map { $0 }
    }

    private static func longestCommonSubsequence(_ a: [Character], _ b: [Character]) -> Int {
        var previous = [Int](repeating: 0, count: b.count + 1)
        for x in a {
            var current = [Int](repeating: 0, count: b.count + 1)
            for (j, y) in b.enumerated() {
                current[j + 1] = x == y ? previous[j] + 1 : max(previous[j + 1], current[j])
            }
            previous = current
        }
        return previous[b.count]
    }
}
