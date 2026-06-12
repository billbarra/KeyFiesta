import Foundation

/// 按键 burst 节流：每个 interval 窗口内最多触发一次；
/// 窗口内被吞掉的按键累计到下一次触发的强度上（封顶 4）。
final class BurstThrottler {
    private let interval: TimeInterval
    private var lastFire: TimeInterval = -.infinity
    private var pendingExtra = 0

    init(interval: TimeInterval = 0.08) { self.interval = interval }

    /// 返回 burst 强度（>=1）表示应当触发；返回 nil 表示本次吞掉。
    func register(now: TimeInterval) -> Int? {
        if now - lastFire >= interval {
            let strength = min(1 + pendingExtra, 4)
            pendingExtra = 0
            lastFire = now
            return strength
        }
        pendingExtra += 1
        return nil
    }
}
