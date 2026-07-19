import AppKit

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController!

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        controller = AppController()
        controller.start()
    }

    public func applicationWillTerminate(_ notification: Notification) {
        controller.stopWhisper()
    }
}
