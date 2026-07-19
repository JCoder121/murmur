import Foundation

public enum Mode: String {
    case smart, rules
}

public enum Settings {
    public static var mode: Mode {
        get { UserDefaults.standard.string(forKey: "mode").flatMap(Mode.init) ?? .smart }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "mode") }
    }
}
