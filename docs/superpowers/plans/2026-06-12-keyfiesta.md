# KeyFiesta 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建 KeyFiesta —— macOS 菜单栏打字特效工具：每次按键在文字光标处喷出 emoji 烟花/彩带粒子并播放随机搞笑音效，兼容所有输入法，打包为可分享的 .app。

**Architecture:** 原生 AppKit 菜单栏 app。全局 keyDown 监听（辅助功能权限）→ AX API 三级 fallback 定位光标 → 每屏一个透明点穿置顶窗承载 CAEmitterLayer 粒子 burst + AVAudioEngine 8 路音效池。纯逻辑（节流、选音、几何换算）独立成文件做 TDD；系统集成部分靠编译检查 + 手动验收清单。

**Tech Stack:** Swift 6.3（`-swift-version 5` 模式）、AppKit、AVFoundation、ApplicationServices、ServiceManagement；swiftc 直接编译（无 Xcode/SPM 依赖）；Python 3 stdlib + afconvert 合成音效。

**构建注意：** ad-hoc 签名每次重编译后 CDHash 变化，系统会要求重新授予辅助功能权限（系统设置里把 KeyFiesta 开关关掉再打开）。

**风险与备用方案：** 若 macOS 26 上 `NSEvent.addGlobalMonitorForEvents(.keyDown)` 在已授权辅助功能后仍收不到事件（新系统可能要求"输入监控"权限），将 KeyMonitor 替换为 listen-only `CGEventTap`（`CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly, eventsOfInterest: 1 << CGEventType.keyDown.rawValue, ...)`），并在 README 中把权限说明改为"输入监控 + 辅助功能"。验收清单第 1 项失败时启用此方案。

---

### Task 1: 纯逻辑模块（TDD）—— BurstThrottler / SoundPicker / Geometry

**Files:**
- Create: `Tests/run_tests.swift`
- Create: `Sources/KeyFiesta/BurstThrottle.swift`
- Create: `Sources/KeyFiesta/SoundPicker.swift`
- Create: `Sources/KeyFiesta/Geometry.swift`

- [x] **Step 1: 写失败测试**

`Tests/run_tests.swift`（注意：swiftc 多文件编译时顶层语句只允许在 main.swift，因此测试入口用 `@main` 包装，编译加 `-parse-as-library`）：

```swift
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
}

if failures == 0 { print("ALL TESTS PASSED") } else { print("\(failures) FAILURES"); exit(1) }
}
}
```

- [x] **Step 2: 运行验证失败**

Run: `cd "<repo-root>" && swiftc -swift-version 5 -parse-as-library Tests/run_tests.swift -o /tmp/kf_tests 2>&1 | head -5`
Expected: 编译错误 `cannot find 'BurstThrottler' in scope`（实现不存在）

- [x] **Step 3: 实现三个模块**

`Sources/KeyFiesta/BurstThrottle.swift`：

```swift
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
```

`Sources/KeyFiesta/SoundPicker.swift`：

```swift
import Foundation

/// 随机挑音效索引，保证不与上一条重复。
struct SoundPicker {
    private var last = -1
    let count: Int

    init(count: Int) { self.count = count }

    mutating func next<R: RandomNumberGenerator>(using rng: inout R) -> Int {
        guard count > 1 else { return 0 }
        var i: Int
        repeat { i = Int.random(in: 0..<count, using: &rng) } while i == last
        last = i
        return i
    }
}
```

`Sources/KeyFiesta/Geometry.swift`：

```swift
import Foundation

/// AX API 返回顶左原点（y 向下）的屏幕坐标；AppKit 用底左原点（y 向上）。
/// 取 AX rect 的顶部中点作为粒子发射点，换算到 AppKit 坐标系。
func emissionPoint(forAXRect r: CGRect, primaryScreenHeight h: CGFloat) -> CGPoint {
    CGPoint(x: r.midX, y: h - r.minY)
}

/// 返回包含该点的 frame 下标（AppKit 坐标），都不包含则 nil。
func frameIndexContaining(_ p: CGPoint, frames: [CGRect]) -> Int? {
    frames.firstIndex { $0.contains(p) }
}

/// 把点钳制到矩形内（留 inset 边距），保证发射点不出屏。
func clampPoint(_ p: CGPoint, to rect: CGRect, inset: CGFloat = 4) -> CGPoint {
    CGPoint(x: min(max(p.x, rect.minX + inset), rect.maxX - inset),
            y: min(max(p.y, rect.minY + inset), rect.maxY - inset))
}
```

- [x] **Step 4: 运行验证通过**

Run: `cd "<repo-root>" && swiftc -swift-version 5 -parse-as-library Sources/KeyFiesta/BurstThrottle.swift Sources/KeyFiesta/SoundPicker.swift Sources/KeyFiesta/Geometry.swift Tests/run_tests.swift -o /tmp/kf_tests && /tmp/kf_tests`
Expected: `ALL TESTS PASSED`

- [x] **Step 5: Commit**

```bash
git add Sources Tests && git commit -m "feat: 纯逻辑模块（节流/选音/几何换算）+ 测试"
```

---

### Task 2: Settings（UserDefaults 持久化，TDD）

**Files:**
- Create: `Sources/KeyFiesta/Settings.swift`
- Modify: `Tests/run_tests.swift`（追加测试）

- [x] **Step 1: 追加失败测试**

在 `Tests/run_tests.swift` 的 `if failures == 0` 行**之前**（即 `TestMain.main()` 内部末尾）插入：

```swift
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
```

- [x] **Step 2: 运行验证失败**

Run: `cd "<repo-root>" && swiftc -swift-version 5 -parse-as-library Sources/KeyFiesta/{BurstThrottle,SoundPicker,Geometry}.swift Tests/run_tests.swift -o /tmp/kf_tests 2>&1 | head -3`
Expected: `cannot find 'Settings' in scope`

- [x] **Step 3: 实现 Settings**

`Sources/KeyFiesta/Settings.swift`：

```swift
import Foundation

enum VolumeLevel: String, CaseIterable {
    case low, medium, high

    var gain: Float {
        switch self {
        case .low: return 0.3
        case .medium: return 0.6
        case .high: return 1.0
        }
    }

    var label: String {
        switch self {
        case .low: return "小"
        case .medium: return "中"
        case .high: return "大"
        }
    }
}

final class Settings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "effectsEnabled": true,
            "soundEnabled": true,
            "volume": VolumeLevel.medium.rawValue,
        ])
    }

    var effectsEnabled: Bool {
        get { defaults.bool(forKey: "effectsEnabled") }
        set { defaults.set(newValue, forKey: "effectsEnabled") }
    }

    var soundEnabled: Bool {
        get { defaults.bool(forKey: "soundEnabled") }
        set { defaults.set(newValue, forKey: "soundEnabled") }
    }

    var volume: VolumeLevel {
        get { VolumeLevel(rawValue: defaults.string(forKey: "volume") ?? "") ?? .medium }
        set { defaults.set(newValue.rawValue, forKey: "volume") }
    }
}
```

- [x] **Step 4: 运行验证通过**

Run: `cd "<repo-root>" && swiftc -swift-version 5 -parse-as-library Sources/KeyFiesta/{BurstThrottle,SoundPicker,Geometry,Settings}.swift Tests/run_tests.swift -o /tmp/kf_tests && /tmp/kf_tests`
Expected: `ALL TESTS PASSED`

- [x] **Step 5: Commit**

```bash
git add Sources Tests && git commit -m "feat: Settings 持久化 + 测试"
```

---

### Task 3: 音效合成脚本 → 12 条卡通音效 .caf

**Files:**
- Create: `scripts/make_sounds.py`
- Create: `Resources/Sounds/*.caf`（生成产物，入库）

- [x] **Step 1: 写合成脚本**

`scripts/make_sounds.py`（纯 stdlib + macOS 自带 afconvert）：

```python
#!/usr/bin/env python3
"""合成 12 条卡通搞笑短音效（44.1kHz mono 16-bit caf），全部自有版权。"""
import math
import os
import struct
import subprocess
import tempfile
import wave

SR = 44100
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Resources", "Sounds")
TWO_PI = 2 * math.pi


def envelope(i, n, attack=0.005, release=0.05):
    t, total = i / SR, n / SR
    a = min(1.0, t / attack) if attack > 0 else 1.0
    r = max(0.0, min(1.0, (total - t) / release)) if release > 0 else 1.0
    return min(a, r)


def sweep(f0, f1, dur, shape=lambda x: x, harmonics=((1, 1.0),), wobble=(0, 0)):
    """正弦扫频：f0→f1，可加谐波与颤音 (rate, depth)。"""
    n = int(SR * dur)
    out, phase = [], 0.0
    rate, depth = wobble
    for i in range(n):
        t = i / n
        f = f0 + (f1 - f0) * shape(t)
        if rate:
            f *= 1 + depth * math.sin(TWO_PI * rate * i / SR)
        phase += TWO_PI * f / SR
        s = sum(amp * math.sin(k * phase) for k, amp in harmonics)
        out.append(s * envelope(i, n))
    return out


def noise(dur, lp=0.0):
    """白噪声，lp∈[0,1) 为一阶低通系数。"""
    import random
    random.seed(7)
    n = int(SR * dur)
    out, prev = [], 0.0
    for i in range(n):
        s = random.uniform(-1, 1)
        prev = lp * prev + (1 - lp) * s
        out.append(prev * envelope(i, n))
    return out


def mul_decay(samples, power=1.5):
    n = len(samples)
    return [s * (1 - i / n) ** power for i, s in enumerate(samples)]


def concat(*parts, gap=0.04):
    silence = [0.0] * int(SR * gap)
    out = []
    for j, p in enumerate(parts):
        out += p
        if j < len(parts) - 1:
            out += silence
    return out


def boing():
    return mul_decay(sweep(380, 130, 0.5, harmonics=((1, 1.0), (2, 0.35)), wobble=(28, 0.22)))


def pop():
    body = sweep(900, 350, 0.07, harmonics=((1, 1.0),))
    click = mul_decay(noise(0.02, lp=0.3), power=3)
    return [a + 0.4 * (click[i] if i < len(click) else 0) for i, a in enumerate(body)]


def slide_up():
    return sweep(350, 1250, 0.42, shape=lambda x: x ** 0.8, harmonics=((1, 1.0), (3, 0.12)), wobble=(6, 0.02))


def slide_down():
    return sweep(1250, 350, 0.42, shape=lambda x: x ** 1.2, harmonics=((1, 1.0), (3, 0.12)), wobble=(6, 0.02))


def quack():
    one = mul_decay(sweep(260, 200, 0.16, harmonics=((1, 1.0), (2, 0.6), (3, 0.4), (5, 0.2)), wobble=(85, 0.35)), 1.0)
    return concat(one, one, gap=0.05)


def honk():
    n = int(SR * 0.32)
    out = []
    for i in range(n):
        s = math.sin(TWO_PI * 220 * i / SR) + 0.8 * math.sin(TWO_PI * 330 * i / SR)
        s += 0.3 * (1 if math.sin(TWO_PI * 220 * i / SR) > 0 else -1)
        out.append(s * envelope(i, n, attack=0.02, release=0.08))
    return out


def toot():
    base = noise(0.36, lp=0.92)
    out = []
    for i, s in enumerate(base):
        flutter = 0.5 + 0.5 * math.sin(TWO_PI * (70 + 25 * math.sin(TWO_PI * 7 * i / SR)) * i / SR)
        out.append(s * flutter)
    return mul_decay(out, 1.2)


def squeak():
    return mul_decay(sweep(1400, 1850, 0.16, shape=lambda x: math.sin(x * math.pi), harmonics=((1, 1.0), (2, 0.2))))


def bubble():
    blips = [mul_decay(sweep(400 + 180 * k, 850 + 180 * k, 0.07), 1.0) for k in range(3)]
    return concat(*blips, gap=0.03)


def ding():
    n = int(SR * 0.5)
    return [(math.sin(TWO_PI * 1318 * i / SR) + 0.4 * math.sin(TWO_PI * 1318 * 2.76 * i / SR))
            * math.exp(-5.5 * i / n) for i in range(n)]


def whee():
    return sweep(500, 1500, 0.45, shape=lambda x: math.sin(x * math.pi * 0.5), harmonics=((1, 1.0), (2, 0.15)), wobble=(9, 0.05))


def drum():
    kick = mul_decay(sweep(150, 48, 0.16, harmonics=((1, 1.0),)), 2.0)
    snare = mul_decay(noise(0.09, lp=0.4), 2.5)
    return concat(kick, snare, gap=0.02)


SOUNDS = {
    "01_boing": boing, "02_pop": pop, "03_slide_up": slide_up, "04_slide_down": slide_down,
    "05_quack": quack, "06_honk": honk, "07_toot": toot, "08_squeak": squeak,
    "09_bubble": bubble, "10_ding": ding, "11_whee": whee, "12_drum": drum,
}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, fn in SOUNDS.items():
        samples = fn()
        peak = max(1e-9, max(abs(s) for s in samples))
        norm = [s / peak * 0.7 for s in samples]
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
            wav_path = tmp.name
        with wave.open(wav_path, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(b"".join(struct.pack("<h", int(s * 32767)) for s in norm))
        out = os.path.join(OUT_DIR, f"{name}.caf")
        subprocess.run(["afconvert", "-f", "caff", "-d", "LEI16@44100", "-c", "1", wav_path, out], check=True)
        os.unlink(wav_path)
        print(f"OK {out} ({len(samples) / SR:.2f}s)")


if __name__ == "__main__":
    main()
```

- [x] **Step 2: 运行生成并验证**

Run: `cd "<repo-root>" && python3 scripts/make_sounds.py && ls Resources/Sounds/ | wc -l && afinfo Resources/Sounds/01_boing.caf | grep -E "data format|estimated duration"`
Expected: 12 行 `OK ...`；文件数 `12`；afinfo 显示 `44100 Hz, Int16, mono` 与时长 ~0.5s

- [x] **Step 3: 试听抽查（人耳验证可跳过自动化）**

Run: `cd "<repo-root>" && for f in Resources/Sounds/0{1,5,7}*.caf; do afplay "$f"; done`
Expected: 听到弹簧 boing、鸭叫、噗声（无报错即可）

- [x] **Step 4: Commit**

```bash
git add scripts Resources/Sounds && git commit -m "feat: 合成 12 条卡通音效（自有版权，44.1kHz mono caf）"
```

---

### Task 4: SoundEngine（8 路播放池）+ 加载冒烟测试

**Files:**
- Create: `Sources/KeyFiesta/SoundEngine.swift`
- Create: `Tests/sound_smoke.swift`

- [x] **Step 1: 实现 SoundEngine**

`Sources/KeyFiesta/SoundEngine.swift`：

```swift
import AVFoundation

/// 预载全部音效到内存，8 路 AVAudioPlayerNode 轮询池，零延迟随机播放。
/// 全部素材由资产管线统一为 44.1kHz mono，因此 processingFormat 一致。
final class SoundEngine {
    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [AVAudioPCMBuffer] = []
    private var nextPlayer = 0
    private var picker: SoundPicker
    private var rng = SystemRandomNumberGenerator()

    var volume: Float {
        get { engine.mainMixerNode.outputVolume }
        set { engine.mainMixerNode.outputVolume = newValue }
    }

    var loadedCount: Int { buffers.count }

    init(soundsDirectory: URL, voices: Int = 8) {
        let urls = ((try? FileManager.default.contentsOfDirectory(at: soundsDirectory, includingPropertiesForKeys: nil)) ?? [])
            .filter { ["caf", "wav", "m4a", "mp3"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in urls {
            guard let file = try? AVAudioFile(forReading: url),
                  let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                             frameCapacity: AVAudioFrameCount(file.length)),
                  (try? file.read(into: buf)) != nil else { continue }
            if let first = buffers.first, first.format != buf.format { continue }
            buffers.append(buf)
        }
        picker = SoundPicker(count: buffers.count)
        let format = buffers.first?.format
        for _ in 0..<voices {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        startEngine()
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in self?.startEngine() }
    }

    private func startEngine() {
        guard !buffers.isEmpty else { return }
        engine.prepare()
        try? engine.start()
    }

    func play() {
        guard !buffers.isEmpty else { return }
        if !engine.isRunning { startEngine() }
        guard engine.isRunning else { return }
        let buf = buffers[picker.next(using: &rng)]
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.stop()
        player.scheduleBuffer(buf, completionHandler: nil)
        player.play()
    }
}
```

- [x] **Step 2: 写冒烟测试（验证加载数量 + 实际出声）**

`Tests/sound_smoke.swift`：

```swift
import AVFoundation
import Foundation

@main
struct SoundSmoke {
    static func main() {
        let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/Sounds")
        let engine = SoundEngine(soundsDirectory: dir)
        print("loaded: \(engine.loadedCount)")
        guard engine.loadedCount == 12 else { print("SMOKE FAIL"); exit(1) }
        engine.volume = 0.5
        for _ in 0..<3 {
            engine.play()
            Thread.sleep(forTimeInterval: 0.4)
        }
        Thread.sleep(forTimeInterval: 0.8)
        print("SMOKE OK")
    }
}
```

- [x] **Step 3: 运行冒烟测试**

Run: `cd "<repo-root>" && swiftc -swift-version 5 -parse-as-library Sources/KeyFiesta/{SoundEngine,SoundPicker}.swift Tests/sound_smoke.swift -o /tmp/kf_sound && /tmp/kf_sound`
Expected: `loaded: 12` + 听到 3 条随机音效 + `SMOKE OK`

- [x] **Step 4: 回归纯逻辑测试**

Run: `cd "<repo-root>" && swiftc -swift-version 5 -parse-as-library Sources/KeyFiesta/{BurstThrottle,SoundPicker,Geometry,Settings}.swift Tests/run_tests.swift -o /tmp/kf_tests && /tmp/kf_tests`
Expected: `ALL TESTS PASSED`

- [x] **Step 5: Commit**

```bash
git add Sources Tests && git commit -m "feat: SoundEngine 8 路播放池 + 冒烟测试"
```

---

### Task 5: EmojiSprite + FXOverlay（透明置顶粒子层）+ 视觉冒烟测试

**Files:**
- Create: `Sources/KeyFiesta/EmojiSprite.swift`
- Create: `Sources/KeyFiesta/FXOverlay.swift`
- Create: `Tests/fx_smoke.swift`

- [x] **Step 1: 实现 EmojiSprite**

`Sources/KeyFiesta/EmojiSprite.swift`：

```swift
import AppKit

/// 把 emoji 字符渲染成 CGImage 并缓存（粒子贴图）。
enum EmojiSprite {
    private static var cache: [String: CGImage] = [:]

    static func image(for emoji: String, pointSize: CGFloat = 30) -> CGImage? {
        if let hit = cache[emoji] { return hit }
        let str = NSAttributedString(string: emoji, attributes: [.font: NSFont.systemFont(ofSize: pointSize)])
        let size = str.size()
        guard size.width > 0, size.height > 0 else { return nil }
        let img = NSImage(size: size, flipped: false) { _ in
            str.draw(at: .zero)
            return true
        }
        var rect = CGRect(origin: .zero, size: size)
        guard let cg = img.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        cache[emoji] = cg
        return cg
    }
}
```

- [x] **Step 2: 实现 FXOverlay**

`Sources/KeyFiesta/FXOverlay.swift`：

```swift
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
    private var entries: [(frame: CGRect, window: NSWindow)] = []

    init() {
        rebuildWindows()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.rebuildWindows() }
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
        let frames = entries.map { $0.frame }
        let idx = frameIndexContaining(point, frames: frames) ?? 0
        guard idx < entries.count, let layer = entries[idx].window.contentView?.layer else { return }
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { emitter.birthRate = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { emitter.removeFromSuperlayer() }
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
```

- [x] **Step 3: 写视觉冒烟测试（屏幕中央连喷 4 次）**

`Tests/fx_smoke.swift`：

```swift
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
```

- [x] **Step 4: 运行视觉冒烟测试**

Run: `cd "<repo-root>" && swiftc -swift-version 5 -parse-as-library Sources/KeyFiesta/{EmojiSprite,FXOverlay,Geometry}.swift Tests/fx_smoke.swift -o /tmp/kf_fx && /tmp/kf_fx`
Expected: 屏幕中央肉眼可见 4 次 emoji 烟花/彩带 burst，4 秒后打印 `FX SMOKE DONE` 正常退出（可同时用截图工具确认）

- [x] **Step 5: Commit**

```bash
git add Sources Tests && git commit -m "feat: EmojiSprite + FXOverlay 粒子特效层 + 视觉冒烟测试"
```

---

### Task 6: KeyMonitor + CaretLocator + Coordinator

**Files:**
- Create: `Sources/KeyFiesta/KeyMonitor.swift`
- Create: `Sources/KeyFiesta/CaretLocator.swift`
- Create: `Sources/KeyFiesta/Coordinator.swift`

- [x] **Step 1: 实现 KeyMonitor**

`Sources/KeyFiesta/KeyMonitor.swift`：

```swift
import AppKit

/// 全局 keyDown 监听（被动，不拦截）。只把"按键发生"信号交给回调，
/// 不读取、不存储按键字符。⌘/⌃ 组合键（快捷键操作）不触发。
final class KeyMonitor {
    private var monitor: Any?
    var onKey: (() -> Void)?

    var isRunning: Bool { monitor != nil }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.modifierFlags.intersection([.command, .control]).isEmpty else { return }
            self?.onKey?()
        }
    }

    func stop() {
        if let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }
}
```

- [x] **Step 2: 实现 CaretLocator**

`Sources/KeyFiesta/CaretLocator.swift`：

```swift
import AppKit
import ApplicationServices

/// 三级 fallback 定位发射点（返回 AppKit 全局坐标）：
/// 1. AX 焦点元素插入点精确 bounds → 2. 焦点元素 frame 中心 → 3. 鼠标位置。
final class CaretLocator {
    func locate() -> CGPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        if let p = axPoint(primaryHeight: primaryHeight) { return p }
        return NSEvent.mouseLocation
    }

    private func axPoint(primaryHeight: CGFloat) -> CGPoint? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedObj: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedObj) == .success,
              let focusedRef = focusedObj, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return nil }
        let element = focusedRef as! AXUIElement

        // 1. 插入点精确位置
        var rangeObj: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeObj) == .success,
           let rangeRef = rangeObj, CFGetTypeID(rangeRef) == AXValueGetTypeID() {
            var boundsObj: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(
                element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeRef, &boundsObj) == .success,
               let boundsRef = boundsObj, CFGetTypeID(boundsRef) == AXValueGetTypeID() {
                var rect = CGRect.zero
                if AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect),
                   rect.width.isFinite, rect.height.isFinite, rect != .zero {
                    return emissionPoint(forAXRect: rect, primaryScreenHeight: primaryHeight)
                }
            }
        }

        // 2. 焦点元素 frame 中心
        var posObj: CFTypeRef?
        var sizeObj: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posObj) == .success,
           AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeObj) == .success,
           let posRef = posObj, let sizeRef = sizeObj,
           CFGetTypeID(posRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID() {
            var pos = CGPoint.zero
            var size = CGSize.zero
            if AXValueGetValue(posRef as! AXValue, .cgPoint, &pos),
               AXValueGetValue(sizeRef as! AXValue, .cgSize, &size),
               size.width > 0, size.height > 0 {
                let centerRect = CGRect(x: pos.x + size.width / 2 - 1, y: pos.y + size.height / 2,
                                        width: 2, height: 2)
                return emissionPoint(forAXRect: centerRect, primaryScreenHeight: primaryHeight)
            }
        }
        return nil
    }
}
```

- [x] **Step 3: 实现 Coordinator**

`Sources/KeyFiesta/Coordinator.swift`：

```swift
import AppKit
import ApplicationServices

/// 把各组件接线：按键 → 节流 → 定位 → 粒子 + 音效。负责辅助功能授权状态。
final class Coordinator {
    let settings: Settings
    private let keyMonitor = KeyMonitor()
    private let caretLocator = CaretLocator()
    private let overlay = FXOverlay()
    private let sound: SoundEngine
    private let throttler = BurstThrottler()
    private var trustTimer: Timer?

    private(set) var isTrusted = false
    var onTrustChange: (() -> Void)?

    init(settings: Settings = Settings()) {
        self.settings = settings
        let soundsURL = Bundle.main.resourceURL?.appendingPathComponent("Sounds")
            ?? URL(fileURLWithPath: "Resources/Sounds")
        sound = SoundEngine(soundsDirectory: soundsURL)
        sound.volume = settings.volume.gain
        keyMonitor.onKey = { [weak self] in self?.handleKey() }
    }

    func start() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        isTrusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        if isTrusted {
            applyEffectsState()
        } else {
            trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                guard let self, AXIsProcessTrusted() else { return }
                self.isTrusted = true
                self.trustTimer?.invalidate()
                self.trustTimer = nil
                self.applyEffectsState()
                self.onTrustChange?()
            }
        }
    }

    func setEffectsEnabled(_ on: Bool) {
        settings.effectsEnabled = on
        applyEffectsState()
    }

    func setSoundEnabled(_ on: Bool) {
        settings.soundEnabled = on
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

    private func handleKey() {
        guard let strength = throttler.register(now: ProcessInfo.processInfo.systemUptime) else { return }
        let point = caretLocator.locate()
        overlay.burst(at: point, strength: strength)
        if settings.soundEnabled {
            sound.play()
        }
    }
}
```

- [x] **Step 4: 编译检查（无可执行入口，typecheck 即可）**

Run: `cd "<repo-root>" && swiftc -swift-version 5 -typecheck Sources/KeyFiesta/*.swift && echo TYPECHECK-OK`
Expected: `TYPECHECK-OK`

- [x] **Step 5: Commit**

```bash
git add Sources && git commit -m "feat: KeyMonitor/CaretLocator/Coordinator 接线"
```

---

### Task 7: StatusBarMenu + main.swift + Info.plist + build.sh → 可运行 .app

**Files:**
- Create: `Sources/KeyFiesta/StatusBarMenu.swift`
- Create: `Sources/KeyFiesta/main.swift`
- Create: `Resources/Info.plist`
- Create: `scripts/build.sh`

- [x] **Step 1: 实现 StatusBarMenu**

`Sources/KeyFiesta/StatusBarMenu.swift`：

```swift
import AppKit
import ServiceManagement

/// 菜单栏 🎉 图标与控制菜单。未授权辅助功能时显示 ⚠️ 并提供设置入口。
final class StatusBarMenu: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let coordinator: Coordinator

    private let effectsItem = NSMenuItem(title: "打字特效", action: #selector(toggleEffects), keyEquivalent: "")
    private let soundItem = NSMenuItem(title: "搞笑音效", action: #selector(toggleSound), keyEquivalent: "")
    private let permissionItem = NSMenuItem(title: "⚠️ 打开「辅助功能」设置…", action: #selector(openAccessibility), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "开机自启", action: #selector(toggleLogin), keyEquivalent: "")
    private var volumeItems: [VolumeLevel: NSMenuItem] = [:]

    init(coordinator: Coordinator) {
        self.coordinator = coordinator
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        for item in [effectsItem, soundItem] {
            item.target = self
            menu.addItem(item)
        }

        let volumeMenu = NSMenu()
        for level in VolumeLevel.allCases {
            let item = NSMenuItem(title: level.label, action: #selector(pickVolume(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = level.rawValue
            volumeItems[level] = item
            volumeMenu.addItem(item)
        }
        let volumeRoot = NSMenuItem(title: "音量", action: nil, keyEquivalent: "")
        volumeRoot.submenu = volumeMenu
        menu.addItem(volumeRoot)

        menu.addItem(.separator())
        permissionItem.target = self
        menu.addItem(permissionItem)
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())

        let aboutItem = NSMenuItem(title: "关于 KeyFiesta", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        coordinator.onTrustChange = { [weak self] in self?.refresh() }
        refresh()
    }

    func menuNeedsUpdate(_ menu: NSMenu) { refresh() }

    private func refresh() {
        statusItem.button?.title = coordinator.isTrusted ? "🎉" : "⚠️"
        effectsItem.state = coordinator.settings.effectsEnabled ? .on : .off
        soundItem.state = coordinator.settings.soundEnabled ? .on : .off
        permissionItem.isHidden = coordinator.isTrusted
        for (level, item) in volumeItems {
            item.state = coordinator.settings.volume == level ? .on : .off
        }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func toggleEffects() {
        coordinator.setEffectsEnabled(!coordinator.settings.effectsEnabled)
    }

    @objc private func toggleSound() {
        coordinator.setSoundEnabled(!coordinator.settings.soundEnabled)
    }

    @objc private func pickVolume(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let level = VolumeLevel(rawValue: raw) else { return }
        coordinator.setVolume(level)
    }

    @objc private func openAccessibility() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
        }
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "KeyFiesta 键盘庆典 1.0"
        alert.informativeText = """
        打字时喷 emoji 烟花彩带 + 随机搞笑音效。

        隐私：本应用不读取、不记录、不传输任何按键内容，\
        只把"有键按下"当作放烟花的信号；无网络访问。\
        辅助功能权限仅用于感知按键和定位文字光标。
        """
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
```

- [x] **Step 2: 实现 main.swift**

`Sources/KeyFiesta/main.swift`：

```swift
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
```

- [x] **Step 3: Info.plist**

`Resources/Info.plist`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>KeyFiesta</string>
    <key>CFBundleIdentifier</key>
    <string>fun.keyfiesta.app</string>
    <key>CFBundleName</key>
    <string>KeyFiesta</string>
    <key>CFBundleDisplayName</key>
    <string>键盘庆典</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>仅供朋友间娱乐使用。不读取、不记录任何按键内容。</string>
</dict>
</plist>
```

- [x] **Step 4: build.sh**

`scripts/build.sh`：

```bash
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP=dist/KeyFiesta.app
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Sounds"

swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
  Sources/KeyFiesta/*.swift \
  -o "$APP/Contents/MacOS/KeyFiesta"

cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Sounds/*.caf "$APP/Contents/Resources/Sounds/"

codesign --force -s - "$APP"
ditto -c -k --keepParent "$APP" dist/KeyFiesta.zip

echo "BUILD OK: $APP"
```

- [x] **Step 5: 构建**

Run: `cd "<repo-root>" && chmod +x scripts/build.sh && ./scripts/build.sh && codesign -dv dist/KeyFiesta.app 2>&1 | grep -E "Signature|Identifier"`
Expected: `BUILD OK: dist/KeyFiesta.app`；codesign 显示 `Signature=adhoc`、`Identifier=fun.keyfiesta.app`

- [x] **Step 6: 启动冒烟（进程存活 + 菜单栏图标）**

Run: `cd "<repo-root>" && open dist/KeyFiesta.app && sleep 3 && pgrep -x KeyFiesta && echo RUNNING`
Expected: 输出 pid + `RUNNING`；系统会弹出辅助功能授权引导（首次）；菜单栏出现 ⚠️（未授权）或 🎉（已授权）

- [x] **Step 7: 把 dist/ 加入 .gitignore 并 Commit**

```bash
printf "dist/\n.DS_Store\n" > .gitignore
git add -A && git commit -m "feat: 菜单栏 UI + app 入口 + 构建脚本，可产出 KeyFiesta.app"
```

---

### Task 8: README + 最终验收

**Files:**
- Create: `README.md`

- [x] **Step 1: 写 README**

`README.md`：

````markdown
# 🎉 KeyFiesta 键盘庆典

macOS 菜单栏小工具：打字时在文字光标处喷出 emoji 烟花/彩带，并播放随机搞笑音效。
对所有输入法生效（苹果拼音、微信输入法、五笔……都行，因为它监听的是按键而不是输入法）。

## 安装（朋友看这里）

1. 解压 `KeyFiesta.zip`，把 `KeyFiesta.app` 拖到「应用程序」文件夹（或任意位置）。
2. **右键点击** `KeyFiesta.app` → 选「打开」→ 再点「打开」。
   （直接双击会被 Gatekeeper 拦住，因为这是朋友自编译的 app，没花 99 美元买苹果签名 😄）
3. 首次启动会弹出「辅助功能」授权引导：
   系统设置 → 隐私与安全性 → 辅助功能 → 打开 KeyFiesta 的开关。
4. 菜单栏出现 🎉 就绪。随便打几个字试试！

## 使用

- 菜单栏 🎉 图标：开关特效 / 开关音效 / 音量三档 / 开机自启 / 退出。
- 在密码框打字**不会**有任何特效（macOS 安全输入机制，系统层面保证）。
- ⌘C / ⌘V 等快捷键不触发特效，专心打字才庆祝。

## 隐私

- **不读取、不记录、不传输任何按键内容**。代码只把"有键按下"当作放烟花的信号。
- 无网络访问。辅助功能权限仅用于感知按键事件和定位文字光标。
- 不放心可以审计源码：`Sources/KeyFiesta/`，总共几百行。

## 自己编译

需要 macOS 13+，Xcode Command Line Tools（`xcode-select --install`）：

```bash
python3 scripts/make_sounds.py   # 生成音效（已入库，可跳过）
./scripts/build.sh               # 产出 dist/KeyFiesta.app 和 dist/KeyFiesta.zip
```

注：重新编译后 ad-hoc 签名变化，需在系统设置里把辅助功能开关关掉再打开一次。

## 音效版权

全部 12 条音效由 `scripts/make_sounds.py` 程序合成，自有版权，随意分发。
````

- [ ] **Step 2: 手动验收清单（来自设计文档）**

逐项执行并记录（需要辅助功能授权后进行）：

1. 备忘录 + 苹果拼音：光标处喷粒子 + 音效
2. Safari 网页文本框 + 地址栏
3. 微信聊天框 + 微信输入法（本机未装微信输入法则注明）
4. 终端打字
5. Safari 登录页密码框：完全静默
6. ⌘C/⌘V 等快捷键：不触发
7. 长按字母连发 10s：流畅，`top -pid $(pgrep -x KeyFiesta)` CPU < 20%
8. 菜单全部项生效；退出后 `pgrep -x KeyFiesta` 无输出
9. 全屏 app 中特效可见
10. `dist/KeyFiesta.zip` 解压后右键打开可运行

- [x] **Step 3: Commit + 交付**

```bash
git add README.md && git commit -m "docs: README（安装/隐私/编译说明）"
```

把 `dist/KeyFiesta.zip` 发给用户（SendUserFile），附验收结果。
