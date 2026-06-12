import AppKit

/// 全局 keyDown 监听（被动，不拦截）。只把"按键发生"信号交给回调，
/// 不读取、不存储按键字符。⌘/⌃ 组合键（快捷键操作）不触发。
final class KeyMonitor {
    private var monitor: Any?
    /// 参数：是否为退格键（仅用于中文组合宽度估算的增减，不涉及按键内容）。
    var onKey: ((Bool) -> Void)?

    /// 非打字键不庆祝：Esc、方向键、F1-F12、Home/End/PgUp/PgDn、Help。
    private static let nonTypingKeyCodes: Set<UInt16> = [
        53,                                          // Esc
        123, 124, 125, 126,                          // 方向键
        122, 120, 99, 118, 96, 97, 98, 100,          // F1-F8
        101, 109, 103, 111,                          // F9-F12
        115, 116, 119, 121, 114,                     // Home/PgUp/End/PgDn/Help
    ]

    var isRunning: Bool { monitor != nil }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection([.command, .control]).isEmpty,
                  !Self.nonTypingKeyCodes.contains(event.keyCode) else { return }
            self?.onKey?(event.keyCode == 51)   // 51 = delete(退格)
        }
    }

    func stop() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }
}
