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
