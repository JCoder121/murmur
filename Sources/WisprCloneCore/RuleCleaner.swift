import Foundation

public struct RuleCleaner: Cleaner {
    public init() {}

    public func clean(_ transcript: String) async -> String {
        var s = transcript
        // Standalone fillers, optionally followed by a comma/period.
        s = s.replacingOccurrences(
            of: #"(?i)(?<![\p{L}])(um+|uh+|uhm+|er+m?|ah|hm+m?|mm+)(?![\p{L}])[,.]?\s*"#,
            with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip a leading orphaned comma left by a removed filler ("um, so" -> ", so").
        s = s.replacingOccurrences(of: #"^[,.;:]\s*"#, with: "", options: .regularExpression)
        if let first = s.first, first.isLowercase {
            s = first.uppercased() + s.dropFirst()
        }
        return s
    }
}
