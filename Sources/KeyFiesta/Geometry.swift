import CoreGraphics
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

/// 屏外点 fallback：返回中心距该点最近的 frame 下标，空数组为 nil。
func nearestFrameIndex(_ p: CGPoint, frames: [CGRect]) -> Int? {
    frames.indices.min { a, b in
        let da = pow(frames[a].midX - p.x, 2) + pow(frames[a].midY - p.y, 2)
        let db = pow(frames[b].midX - p.x, 2) + pow(frames[b].midY - p.y, 2)
        return da < db
    }
}

/// 把点钳制到矩形内（留 inset 边距），保证发射点不出屏。
func clampPoint(_ p: CGPoint, to rect: CGRect, inset: CGFloat = 4) -> CGPoint {
    CGPoint(x: min(max(p.x, rect.minX + inset), rect.maxX - inset),
            y: min(max(p.y, rect.minY + inset), rect.maxY - inset))
}
