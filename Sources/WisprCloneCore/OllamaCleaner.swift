import Foundation

public final class OllamaCleaner: Cleaner {
    static let basePrompt = """
    You clean up dictated speech. Rules:
    1. Remove filler words (um, uh, like, you know) and false starts.
    2. Fix punctuation, casing, and obvious grammar slips without changing meaning or tone.
    3. Translate any Chinese into natural English. The output must be entirely English.
    4. If the speech contains a meta-instruction such as "give me the following in English:", \
    apply the instruction to the content that follows instead of writing out the instruction.
    5. Output ONLY the final cleaned text. No quotes, no commentary, no explanations.
    6. Convert spoken symbol names (slash, dash, comma, colon, dot) into characters when \
    context clearly calls for it (e.g. file paths, punctuation); otherwise leave them as words.
    """

    static func systemPrompt(context: AppContext?, dictionaryTerms: [String]) -> String {
        var parts = [basePrompt]
        if let context {
            let title = context.windowTitle.isEmpty ? "" : " (window: \"\(context.windowTitle)\")"
            switch context.bucket {
            case .chat:
                parts.append("The user is typing in a chat app (\(context.appName))\(title); keep it casual and light on punctuation.")
            case .code:
                parts.append("The user is typing in a terminal or code editor (\(context.appName))\(title); preserve technical terms, paths, and symbols exactly.")
            case .prose:
                parts.append("The user is writing prose in \(context.appName.isEmpty ? "an app" : context.appName)\(title); use proper punctuation and capitalization.")
            }
        }
        if !dictionaryTerms.isEmpty {
            parts.append("Preferred spellings: \(dictionaryTerms.joined(separator: ", ")).")
        }
        return parts.joined(separator: "\n")
    }

    private let endpoint: URL
    private let model: String
    private let timeout: TimeInterval
    private let fallback: Cleaner
    private let onFallback: (() -> Void)?
    private let contextProvider: (() -> (AppContext?, [String]))?

    public init(endpoint: URL = URL(string: "http://127.0.0.1:11434/api/chat")!,
                model: String = "qwen2.5:3b",
                timeout: TimeInterval = 10,
                fallback: Cleaner,
                onFallback: (() -> Void)? = nil,
                contextProvider: (() -> (AppContext?, [String]))? = nil) {
        self.endpoint = endpoint
        self.model = model
        self.timeout = timeout
        self.fallback = fallback
        self.onFallback = onFallback
        self.contextProvider = contextProvider
    }

    static func buildBody(model: String, transcript: String, systemPrompt: String) -> Data {
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

    /// Fire-and-forget 1-token generation to pull the model into memory.
    /// Called on chord-engage so the ~7.5s cold load overlaps speech + whisper.
    public static func warmUp(endpoint: URL = URL(string: "http://127.0.0.1:11434/api/chat")!,
                              model: String = "qwen2.5:3b") {
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": model, "stream": false,
            "messages": [["role": "user", "content": "hi"]],
            "options": ["num_predict": 1],
        ])
        URLSession.shared.dataTask(with: req).resume()
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
        let (context, terms) = contextProvider?() ?? (nil, [])
        req.httpBody = Self.buildBody(
            model: model, transcript: transcript,
            systemPrompt: Self.systemPrompt(context: context, dictionaryTerms: terms))
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
