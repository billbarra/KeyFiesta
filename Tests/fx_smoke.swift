import AppKit

final class SmokeDelegate: NSObject, NSApplicationDelegate {
    var overlay: FXOverlay!

    func applicationDidFinishLaunching(_ notification: Notification) {
        overlay = FXOverlay()
        guard let screen = NSScreen.main else { exit(1) }
        let center = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
        for i in 0..<4 {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.7) {
                self.overlay.burst(at: center, strength: i % 4 + 1)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            print("FX SMOKE DONE")
            exit(0)
        }
    }
}

@main
struct FXSmoke {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = SmokeDelegate()
        app.delegate = delegate
        app.run()
    }
}
