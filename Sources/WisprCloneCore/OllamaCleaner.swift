import Foundation

public final class OllamaCleaner: Cleaner {
    static let systemPrompt = """
    You clean up dictated speech. Rules:
    1. Remove filler words (um, uh, like, you know) and false starts.
    2. Fix punctuation, casing, and obvious grammar slips without changing meaning or tone.
    3. Translate any Chinese into natural English. The output must be entirely English.
    4. If the speech contains a meta-instruction such as "give me the following in English:", \
    apply the instruction to the content that follows instead of writing out the instruction.
    5. Output ONLY the final cleaned text. No quotes, no commentary, no explanations.
    """

    private let endpoint: URL
    private let model: String
    private let timeout: TimeInterval
    private let fallback: Cleaner
    private let onFallback: (() -> Void)?

    public init(endpoint: URL = URL(string: "http://127.0.0.1:11434/api/chat")!,
                model: String = "qwen2.5:3b",
                timeout: TimeInterval = 10,
                fallback: Cleaner,
                onFallback: (() -> Void)? = nil) {
        self.endpoint = endpoint
        self.model = model
        self.timeout = timeout
        self.fallback = fallback
        self.onFallback = onFallback
    }

    static func buildBody(model: String, transcript: String) -> Data {
        let payload: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": transcript],
            ],
        ]
        return try! JSONSerialization.data(withJSONObject: payload)
    }

    static func parse(_ data: Data) throws -> String {
        struct Response: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        return try JSONDecoder().decode(Response.self, from: data)
            .message.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func clean(_ transcript: String) async -> String {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.buildBody(model: model, transcript: transcript)
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let out = try Self.parse(data)
            guard !out.isEmpty else { throw URLError(.zeroByteResource) }
            return out
        } catch {
            onFallback?()
            return await fallback.clean(transcript)
        }
    }
}
