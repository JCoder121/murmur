import Foundation

public final class WhisperServer {
    public static let modelPath = ("~/Library/Application Support/WisprClone/models/ggml-large-v3-turbo-q5_0.bin" as NSString).expandingTildeInPath
    private static let binaryCandidates = ["/opt/homebrew/bin/whisper-server", "/usr/local/bin/whisper-server"]
    private static let base = URL(string: "http://127.0.0.1:8642")!

    private var process: Process?
    private var startTask: Task<Void, Swift.Error>?

    public init() {}

    public var isModelInstalled: Bool {
        FileManager.default.fileExists(atPath: Self.modelPath)
    }

    public enum Error: Swift.Error, LocalizedError {
        case binaryMissing, modelMissing, startTimeout, badResponse
        public var errorDescription: String? {
            switch self {
            case .binaryMissing: "whisper-server not found — run scripts/setup.sh"
            case .modelMissing: "whisper model not found — run scripts/setup.sh"
            case .startTimeout: "whisper-server did not become ready"
            case .badResponse: "whisper-server returned an unexpected response"
            }
        }
    }

    @MainActor
    public func ensureRunning() async throws {
        if let t = startTask { return try await t.value }
        let t = Task<Void, Swift.Error> {
            if process?.isRunning == true, await healthy() { return }
            guard let bin = Self.binaryCandidates.first(where: { FileManager.default.fileExists(atPath: $0) })
            else { throw Error.binaryMissing }
            guard isModelInstalled else { throw Error.modelMissing }

            let p = Process()
            p.executableURL = URL(fileURLWithPath: bin)
            p.arguments = ["-m", Self.modelPath, "--host", "127.0.0.1", "--port", "8642", "--language", "auto"]
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try p.run()
            process = p

            for _ in 0..<60 {  // up to 30s for first model load
                try await Task.sleep(nanoseconds: 500_000_000)
                if await healthy() { return }
                if !p.isRunning { break }
            }
            stop()
            throw Error.startTimeout
        }
        startTask = t
        do {
            try await t.value
            startTask = nil
        } catch {
            startTask = nil
            throw error
        }
    }

    private func healthy() async -> Bool {
        var req = URLRequest(url: Self.base); req.timeoutInterval = 1
        guard let (_, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return false }
        return http.statusCode == 200
    }

    public func transcribe(wav: URL, language: Language = .auto) async throws -> String {
        let boundary = "wisprclone-\(UUID().uuidString)"
        var req = URLRequest(url: Self.base.appendingPathComponent("inference"))
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(try Data(contentsOf: wav))
        body.append(Data("\r\n".utf8))
        field("response_format", "json")
        field("language", language.rawValue)  // overrides the server's --language flag
        body.append(Data("--\(boundary)--\r\n".utf8))
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw Error.badResponse }
        let text = try WhisperParse.text(from: data)
        return WhisperParse.isNoise(text) ? "" : text
    }

    @MainActor
    public func stop() {
        let p = process
        p?.terminate()
        process = nil
        startTask = nil
        // Bounded wait off the main actor so the port frees before a restart,
        // without blocking synchronously for up to 2s.
        if let p {
            Task.detached {
                for _ in 0..<20 {
                    if !p.isRunning { return }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
        }
    }
}
