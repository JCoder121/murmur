import Foundation

/// Whisper transcription language. `.auto` supports EN+ZH but costs an extra
/// detection pass (~2x latency); `.en` skips it.
public enum Language: String {
    case auto, en
}

// Mode (rules vs smart) is no longer a setting — it's chosen per dictation by
// the hotkey: Right-Cmd alone = rules, Right-Cmd + Right-Opt = smart.
public enum Settings {
    public static var language: Language {
        get { UserDefaults.standard.string(forKey: "language").flatMap(Language.init) ?? .auto }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "language") }
    }
}
