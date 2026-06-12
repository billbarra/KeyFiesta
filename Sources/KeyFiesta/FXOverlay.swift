import AppKit
import QuartzCore

/// 每个屏幕一个透明、点穿、置顶的窗口，承载 CAEmitterLayer 粒子 burst。
final class FXOverlay {
    enum Style: CaseIterable {
        case confetti, fireworks

        var emojis: [String] {
            switch self {
            case .confetti: return ["🎉", "🎊", "🎀", "✨", "🎈"]
            case .fireworks: return ["🎆", "🎇", "💥", "⭐️", "🌟"]
            }
        }
    }

    private static let rareEmojis = ["🥳", "😂"]
    private static let maxLiveEmitters = 12
    private var entries: [(frame: CGRect, window: NSWindow)] = []
    private var liveEmitters = 0
    private var screenObserver: NSObjectProtocol?

    init() {
        rebuildWindows()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.rebuildWindows() }
    }

    deinit {
        if let o = screenObserver { NotificationCenter.default.removeObserver(o) }
    }

    private func rebuildWindows() {
        for e in entries { e.window.orderOut(nil) }
        entries = NSScreen.screens.map { screen in
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.ignoresMouseEvents = true
            w.hasShadow = false
            w.isReleasedWhenClosed = false
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            let v = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            v.wantsLayer = true
            w.contentView = v
            w.orderFrontRegardless()
            return (screen.frame, w)
        }
    }

    /// 在全局 AppKit 坐标 point 处喷一次粒子。strength ∈ 1...4 放大粒子量。
    func burst(at point: CGPoint, strength: Int) {
        guard liveEmitters < Self.maxLiveEmitters else { return }
        let frames = entries.map { $0.frame }
        guard let idx = frameIndexContaining(point, frames: frames) ?? nearestFrameIndex(point, frames: frames),
              let layer = entries[idx].window.contentView?.layer else { return }
        let frame = entries[idx].frame
        let local = clampPoint(CGPoint(x: point.x - frame.minX, y: point.y - frame.minY),
                               to: CGRect(origin: .zero, size: frame.size), inset: 8)

        let style = Style.allCases.randomElement()!
        var pool = style.emojis
        if Int.random(in: 0..<10) == 0 { pool.append(Self.rareEmojis.randomElement()!) }

        let emitter = CAEmitterLayer()
        emitter.emitterPosition = local
        emitter.emitterShape = .point
        emitter.birthRate = 1
        emitter.beginTime = CACurrentMediaTime()
        emitter.emitterCells = pool.compactMap { makeCell(emoji: $0, style: style, strength: strength) }
        layer.addSublayer(emitter)
        liveEmitters += 1

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            emitter.birthRate = 0
            CATransaction.commit()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            emitter.removeFromSuperlayer()
            self?.liveEmitters -= 1
        }
    }

    private func makeCell(emoji: String, style: Style, strength: Int) -> CAEmitterCell? {
        guard let img = EmojiSprite.image(for: emoji) else { return nil }
        let cell = CAEmitterCell()
        cell.contents = img
        let k = Float(min(max(strength, 1), 4))
        switch style {
        case .confetti:
            cell.birthRate = 60 * k
            cell.velocity = 380
            cell.velocityRange = 140
            cell.emissionLongitude = .pi / 2   // macOS layer y 轴向上
            cell.emissionRange = 0.55
            cell.yAcceleration = -420          // 重力向下
            cell.spin = 3
            cell.spinRange = 4
            cell.lifetime = 1.5
            cell.lifetimeRange = 0.3
            cell.alphaSpeed = -0.55
        case .fireworks:
            cell.birthRate = 80 * k
            cell.velocity = 320
            cell.velocityRange = 160
            cell.emissionRange = .pi           // 全向爆开
            cell.yAcceleration = -100
            cell.spin = 1
            cell.spinRange = 2
            cell.lifetime = 1.2
            cell.lifetimeRange = 0.25
            cell.alphaSpeed = -0.8
        }
        cell.scale = 0.5
        cell.scaleRange = 0.2
        cell.scaleSpeed = -0.1
        return cell
    }
}
