public protocol Cleaner {
    func clean(_ transcript: String) async -> String
}
