import Foundation

public enum Mode: String {
    case smart, rules
}

/// Whisper transcription language. `.auto` supports EN+ZH but costs an extra
/// detection pass (~2x latency); `.en` skips it.
public enum Language: String {
    case auto, en
}

public enum Settings {
    public static var mode: Mode {
        get { UserDefaults.standard.string(forKey: "mode").flatMap(Mode.init) ?? .smart }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "mode") }
    }

    public static var language: Language {
        get { UserDefaults.standard.string(forKey: "language").flatMap(Language.init) ?? .auto }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "language") }
    }
}
