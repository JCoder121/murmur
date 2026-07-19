import Foundation

/// User-editable list of proper nouns (one per line, # comments) fed to
/// whisper as initial_prompt and to the smart cleaner as preferred spellings.
public final class PersonalDictionary {
    public static let defaultFileURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Chirp/dictionary.txt")

    private let fileURL: URL
    private var cachedTerms: [String] = []
    private var cachedMTime: Date?

    public init(fileURL: URL = PersonalDictionary.defaultFileURL) {
        self.fileURL = fileURL
    }

    public var terms: [String] {
        let mtime = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate]) as? Date
        if mtime != cachedMTime {
            cachedMTime = mtime
            let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            cachedTerms = text.split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        }
        return cachedTerms
    }

    public var initialPrompt: String {
        var out = ""
        for term in terms {
            let next = out.isEmpty ? term : out + ", " + term
            if next.count > 600 { break }
            out = next
        }
        return out
    }
}
