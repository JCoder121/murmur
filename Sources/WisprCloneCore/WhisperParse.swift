import Foundation

public enum WhisperParse {
    public static func text(from data: Data) throws -> String {
        struct Response: Decodable { let text: String }
        return try JSONDecoder().decode(Response.self, from: data)
            .text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whisper emits bracketed pseudo-events for non-speech: [BLANK_AUDIO], (music)...
    public static func isNoise(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        return t.range(of: #"^[\[(][^\])]*[\])]$"#, options: .regularExpression) != nil
    }
}
