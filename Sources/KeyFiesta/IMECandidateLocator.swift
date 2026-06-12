import AppKit
import CoreGraphics

/// 通过输入法候选词窗口定位光标：候选窗由系统输入法框架保证贴着光标弹出，
/// 对所有 app（含微信、Electron 系）一致精确；仅在拼音等组合输入进行中存在，
/// 无候选窗（如英文直输）时返回 nil 由调用方走 AX 链。
/// 实测特征（微信输入法候选条）：极高 window layer、宽 30–900、高 15–400，
/// 紧贴光标行下方。CGWindowList 的 bounds/owner/pid/layer 不需要屏幕录制权限。
final class IMECandidateLocator {
    private var imePids: Set<pid_t> = []
    private var lastScan: TimeInterval = 0

    private func refreshIMEPids(now: TimeInterval) {
        guard now - lastScan > 5 || imePids.isEmpty else { return }
        lastScan = now
        imePids = Set(NSWorkspace.shared.runningApplications.compactMap { app in
            let bundleID = app.bundleIdentifier?.lowercased() ?? ""
            let name = app.localizedName ?? ""
            let isIME = bundleID.contains("inputmethod")
                || name.contains("输入法")
                || name.localizedCaseInsensitiveContains("input method")
            return isIME ? app.processIdentifier : nil
        })
    }

    struct Panel {
        /// 候选条左缘锚点的发射点（AppKit 坐标）。候选条 x 锚定在**整段拼音的起点**
        /// （系统行为：输入法用 forCharacterIndex:0 定位），不随当前输入位置移动，
        /// 调用方需按组合内按键数估算 x 偏移。
        let anchorPoint: CGPoint
        /// 候选条原始左缘 x（顶左坐标系），用于识别"新一段组合开始"（锚点跳变）。
        let panelX: CGFloat
    }

    /// 返回当前候选窗信息；无候选窗（非组合输入中）时 nil。
    func panel(primaryHeight: CGFloat) -> Panel? {
        refreshIMEPids(now: ProcessInfo.processInfo.systemUptime)
        guard !imePids.isEmpty,
              let list = CGWindowListCopyWindowInfo(
                  [.optionOnScreenOnly, .excludeDesktopElements], CGWindowID(0)) as? [[String: Any]]
        else { return nil }

        for window in list {
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, imePids.contains(pid),
                  let layer = window[kCGWindowLayer as String] as? Int, layer >= 1000,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"],
                  width >= 30, width <= 900, height >= 15, height <= 400
            else { continue }
            // 候选条贴在光标行正下方：取其左上角上方一点作为发射点（顶左坐标系）
            let anchor = CGRect(x: x + 10, y: y - 8, width: 2, height: 2)
            return Panel(anchorPoint: emissionPoint(forAXRect: anchor, primaryScreenHeight: primaryHeight),
                         panelX: x)
        }
        return nil
    }
}
