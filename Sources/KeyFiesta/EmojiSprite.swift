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
