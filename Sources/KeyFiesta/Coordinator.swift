import AppKit
import ApplicationServices

/// 把各组件接线：按键 → 节流 → 定位 → 粒子 + 音效。负责辅助功能授权状态。
final class Coordinator {
    let settings: Settings
    private let keyMonitor = KeyMonitor()
    private let caretLocator = CaretLocator()
    private let imeLocator = IMECandidateLocator()
    private let overlay = FXOverlay()
    private let sound: SoundEngine
    private let throttler = BurstThrottler()
    private var trustTimer: Timer?

    /// AX 查询走后台串行队列（IPC 可能慢/超时，不能卡主线程）。
    private let axQueue = DispatchQueue(label: "fun.keyfiesta.ax", qos: .userInteractive)
    /// 仅主线程访问：有查询在途时新按键直接用上次成功点/鼠标位置，避免排队堆积。
    private var axInFlight = false
    private var axInFlightSince: TimeInterval = 0
    private var lastCaretPoint: CGPoint?

    /// 以下状态仅在 axQueue 上访问：中文组合期借输入法候选窗定位，候选条 x 锚定
    /// 拼音段起点不动，按 ~9pt/键 估算当前输入位置的偏移。
    private var compositionKeyCount = 0
    private var lastPanelX: CGFloat?
    /// axQueue：最近一次见到候选窗的时间，用于判断是否处于中文组合期。
    private var lastPanelTime: TimeInterval = -.infinity
    private var activationObserver: NSObjectProtocol?

    private(set) var isTrusted = false
    var onTrustChange: (() -> Void)?

    init(settings: Settings = Settings()) {
        self.settings = settings
        let soundsURL = Bundle.main.resourceURL?.appendingPathComponent("Sounds")
            ?? URL(fileURLWithPath: "Resources/Sounds")
        sound = SoundEngine(soundsDirectory: soundsURL)
        sound.volume = settings.volume.gain
        keyMonitor.onKey = { [weak self] isBackspace in self?.handleKey(isBackspace: isBackspace) }

        // app 激活时预注入辅助功能开关：Electron 注入后有 2s 防抖才提供字符级几何，
        // 激活时注入可让防抖期在用户开始打字前耗完。
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            let pid = app.processIdentifier
            self.axQueue.async { self.caretLocator.preInject(pid: pid) }
        }
        if let front = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            axQueue.async { [weak self] in self?.caretLocator.preInject(pid: front) }
        }
    }

    deinit {
        if let o = activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(o) }
    }

    func start() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        isTrusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        if isTrusted {
            applyEffectsState()
            onTrustChange?()
        } else {
            trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                guard AXIsProcessTrusted() else { return }
                self.isTrusted = true
                self.trustTimer?.invalidate()
                self.trustTimer = nil
                // 关键：进程在授权前启动，AX 客户端 API 仍是 disabled(-25211)，
                // 须重启进程才真正启用。固定签名下重启会自动保留授权，因此首次
                // 授权后自动重启自己，用户无需手动操作、光标定位立刻可用。
                self.relaunchSelf()
            }
        }
    }

    private func relaunchSelf() {
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.4; open \"\(path)\""]
        try? p.run()
        NSApp.terminate(nil)
    }

    /// 菜单打开时调用：感知运行期间被撤销/恢复的辅助功能权限。
    func refreshTrust() {
        let trusted = AXIsProcessTrusted()
        guard trusted != isTrusted else { return }
        isTrusted = trusted
        applyEffectsState()
    }

    func setEffectsEnabled(_ on: Bool) {
        settings.effectsEnabled = on
        applyEffectsState()
    }

    func setSoundEnabled(_ on: Bool) {
        settings.soundEnabled = on
        if !on { sound.pauseNow() }
    }

    func setVolume(_ level: VolumeLevel) {
        settings.volume = level
        sound.volume = level.gain
    }

    private func applyEffectsState() {
        if settings.effectsEnabled && isTrusted {
            keyMonitor.start()
        } else {
            keyMonitor.stop()
        }
    }

    /// 排除名单：这些 app 自绘 UI 对系统零暴露，光标无法精确定位（详见调研），
    /// 与其喷错位置不如完全不喷。微信即此类。
    private static let excludedBundleIDs: Set<String> = ["com.tencent.xinWeChat"]

    private func handleKey(isBackspace: Bool) {
        // 前台是排除名单里的 app（如微信）→ 完全跳过，不喷粒子不响音效
        if let bid = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           Self.excludedBundleIDs.contains(bid) {
            return
        }
        guard let strength = throttler.register(now: ProcessInfo.processInfo.systemUptime) else { return }
        if settings.soundEnabled {
            sound.play()    // 音效不依赖位置，立即响
        }
        // AppKit 状态在主线程捕获，再交给后台队列做 AX IPC
        let mouseFallback = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let frontPid = NSWorkspace.shared.frontmostApplication?.processIdentifier

        // axInFlight 自愈：若上一次查询异常未回（超 1s），强制放行，避免永久
        // 卡在"复用上次点/鼠标"的应急路径。
        let now = ProcessInfo.processInfo.systemUptime
        if axInFlight && now - axInFlightSince < 1.0 {
            overlay.burst(at: lastCaretPoint ?? mouseFallback, strength: strength)
            return
        }
        axInFlight = true
        axInFlightSince = now
        axQueue.async { [weak self] in
            guard let self else { return }
            let located = self.resolvePoint(primaryHeight: primaryHeight, frontPid: frontPid,
                                            isBackspace: isBackspace)
            DispatchQueue.main.async {
                self.axInFlight = false
                self.lastCaretPoint = located
                self.overlay.burst(at: located ?? mouseFallback, strength: strength)
            }
        }
    }

    /// axQueue 上执行。优先级：AX 精确光标（原生 + Electron TextMarker）
    /// → 输入法候选窗锚点 + 组合内按键计数偏移（中文组合期）
    /// → nil（调用方降级鼠标）。
    private func resolvePoint(primaryHeight: CGFloat, frontPid: pid_t?, isBackspace: Bool) -> CGPoint? {
        if let p = caretLocator.locateAX(primaryHeight: primaryHeight, frontPid: frontPid) {
            compositionKeyCount = 0
            lastPanelX = nil
            return p
        }
        // 仅在组合活跃（最近 1s 见过候选窗）时才做短重扫，避免无候选窗时每键白等。
        let now = ProcessInfo.processInfo.systemUptime
        var panel = imeLocator.panel(primaryHeight: primaryHeight)
        if panel == nil && now - lastPanelTime < 1.0 {
            usleep(60_000)
            panel = imeLocator.panel(primaryHeight: primaryHeight)
        }
        if let panel {
            lastPanelTime = now
            if let last = lastPanelX, abs(panel.panelX - last) > 2 {
                compositionKeyCount = 0     // 锚点跳变 = 新一段组合开始
            }
            lastPanelX = panel.panelX
            compositionKeyCount = max(0, compositionKeyCount + (isBackspace ? -1 : 1))
            // 候选条 x 固定在拼音段起点；按 ~9pt/键 估算当前输入位置
            let offset = min(CGFloat(max(compositionKeyCount - 1, 0)) * 9.0, 360)
            return CGPoint(x: panel.anchorPoint.x + offset, y: panel.anchorPoint.y)
        }
        compositionKeyCount = 0
        lastPanelX = nil
        return nil
    }
}
