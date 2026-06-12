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
    private var idleTimer: Timer?

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
        // 引擎懒启动：常驻运转会持有阻止系统休眠的电源断言。
        // 设备切换（配置变化）后引擎自动停止，下次 play() 懒启动即恢复。
    }

    deinit { idleTimer?.invalidate() }

    private func startEngine() {
        guard !buffers.isEmpty else { return }
        engine.prepare()
        try? engine.start()
    }

    /// 立即暂停音频 I/O（释放电源断言）；已解码 buffer 保留，重启零成本。
    func pauseNow() {
        idleTimer?.invalidate()
        idleTimer = nil
        engine.pause()
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
        scheduleIdlePause()
    }

    private func scheduleIdlePause() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            self?.engine.pause()
        }
    }
}
