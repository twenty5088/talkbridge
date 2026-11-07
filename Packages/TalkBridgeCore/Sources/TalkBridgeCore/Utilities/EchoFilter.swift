/// 判斷剛聽到的話是不是喇叭播出的譯文殘響（v2 設計 P8）。純函式。
public enum EchoFilter {
    /// 只比字母與數字（忽略大小寫、空白、標點）；相似度＝最長共同子序列長度／較長者長度。
    public static func isLikelyEcho(heard: String, played: String, threshold: Double) -> Bool {
        let a = normalized(heard)
        let b = normalized(played)
        guard !a.isEmpty, !b.isEmpty else { return false }
        let lcs = longestCommonSubsequence(a, b)
        return Double(lcs) / Double(max(a.count, b.count)) >= threshold
    }

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
