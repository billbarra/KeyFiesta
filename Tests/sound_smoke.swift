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
