import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: Coordinator!
    private var statusBarMenu: StatusBarMenu!

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = Coordinator()
        statusBarMenu = StatusBarMenu(coordinator: coordinator)
        coordinator.start()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
