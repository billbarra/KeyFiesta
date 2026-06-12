import Foundation

var failures = 0
func expect(_ cond: Bool, _ msg: String, line: Int = #line) {
    if !cond { failures += 1; print("FAIL [\(line)] \(msg)") }
}

// 可种子化 RNG，保证测试确定性
struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

@main
struct TestMain {
static func main() {
// ── BurstThrottler ──
do {
    let t = BurstThrottler(interval: 0.08)
    expect(t.register(now: 0.0) == 1, "首键立即触发，强度 1")
    expect(t.register(now: 0.02) == nil, "窗口内吞掉")
    expect(t.register(now: 0.04) == nil, "窗口内吞掉")
    expect(t.register(now: 0.10) == 3, "窗口后触发，带累计强度 1+2")
    expect(t.register(now: 0.30) == 1, "间隔够大，恢复强度 1")
}
do {
    let t = BurstThrottler(interval: 0.08)
    _ = t.register(now: 0.0)
    for i in 1...10 { _ = t.register(now: 0.0 + Double(i) * 0.005) }
    expect(t.register(now: 0.2) == 4, "累计强度封顶 4")
}

// ── SoundPicker ──
do {
    var rng = SplitMix64(seed: 42)
    var p = SoundPicker(count: 5)
    var prev = -1
    for _ in 0..<200 {
        let i = p.next(using: &rng)
        expect((0..<5).contains(i), "索引在范围内")
        expect(i != prev, "不与上一条重复")
        prev = i
    }
}
do {
    var rng = SplitMix64(seed: 1)
    var p = SoundPicker(count: 1)
    expect(p.next(using: &rng) == 0, "只有一条时恒为 0")
    expect(p.next(using: &rng) == 0, "只有一条时恒为 0（重复调用）")
}

// ── Geometry ──
do {
    // AX 顶左原点 → AppKit 底左原点；主屏高 1000
    let p = emissionPoint(forAXRect: CGRect(x: 100, y: 200, width: 2, height: 18), primaryScreenHeight: 1000)
    expect(p.x == 101 && p.y == 800, "AX rect 顶部中点换算，got \(p)")

    let frames = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 1512, y: 0, width: 1920, height: 1080)]
    expect(frameIndexContaining(CGPoint(x: 100, y: 100), frames: frames) == 0, "主屏命中")
    expect(frameIndexContaining(CGPoint(x: 1600, y: 500), frames: frames) == 1, "副屏命中")
    expect(frameIndexContaining(CGPoint(x: -50, y: 5000), frames: frames) == nil, "屏外为 nil")

    let c = clampPoint(CGPoint(x: -10, y: 2000), to: CGRect(x: 0, y: 0, width: 100, height: 100), inset: 4)
    expect(c.x == 4 && c.y == 96, "钳制到 inset 内，got \(c)")

    // 屏外点 fallback：选中心最近的屏
    expect(nearestFrameIndex(CGPoint(x: 1500, y: 1500), frames: frames) == 0, "屏外点靠近主屏")
    expect(nearestFrameIndex(CGPoint(x: 3500, y: 1200), frames: frames) == 1, "屏外点靠近副屏")
    expect(nearestFrameIndex(CGPoint(x: 0, y: 0), frames: []) == nil, "无屏时为 nil")
}

// ── Settings ──
do {
    let suite = "kf.test.\(UUID().uuidString)"
    let ud = UserDefaults(suiteName: suite)!
    let s = Settings(defaults: ud)
    expect(s.effectsEnabled == true, "默认特效开")
    expect(s.soundEnabled == true, "默认音效开")
    expect(s.volume == .medium, "默认中音量")
    s.effectsEnabled = false
    s.volume = .high
    let s2 = Settings(defaults: ud)
    expect(s2.effectsEnabled == false, "特效开关持久化")
    expect(s2.volume == .high, "音量持久化")
    expect(VolumeLevel.low.gain == 0.3 && VolumeLevel.medium.gain == 0.6 && VolumeLevel.high.gain == 1.0, "三档增益")
    ud.removePersistentDomain(forName: suite)
}

if failures == 0 { print("ALL TESTS PASSED") } else { print("\(failures) FAILURES"); exit(1) }
}
}
