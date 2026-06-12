import AppKit
import ApplicationServices

/// AX 定位发射点（返回 AppKit 全局坐标），设计为在后台串行队列调用：
/// 1. AX 焦点元素插入点精确 bounds → 2. 焦点元素 frame 中心 → 失败返回 nil，
/// 由 Coordinator 降级到鼠标位置。
final class CaretLocator {
    /// 复用 system-wide 元素，AX IPC 超时 0.5s（在 system-wide 元素上设置即
    /// 全局生效）。本类跑在后台队列，超时只延迟粒子、不卡主线程。
    private let systemWide: AXUIElement = {
        let el = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(el, 0.5)
        return el
    }()

    /// 已注入"开启辅助功能树"标志的 app。Chromium/Electron 系默认不渲染
    /// AX 树（查不到光标），注入 AXManualAccessibility/AXEnhancedUserInterface
    /// 后才会暴露；注入一次即可，按 pid 记录。
    private var axEnabledPids = Set<pid_t>()

    /// 按 pid 缓存 app 元素（已设超时）。
    private var appElements: [pid_t: AXUIElement] = [:]

    /// 最近一次有效的 marker 光标点 + 时间。Chromium 选区 marker 在光标刚移动/
    /// 刚聚焦的瞬间有竞态，会偶发返回 nil；此时光标几乎没动，复用最近有效点
    /// 比降级到 frame 中心（固定错位）平滑得多。
    private var lastMarkerPoint: CGPoint?
    private var lastMarkerTime: TimeInterval = -.infinity

    private func appElement(for pid: pid_t) -> AXUIElement {
        if let cached = appElements[pid] { return cached }
        let el = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(el, 0.5)
        appElements[pid] = el
        return el
    }

    /// 对 Electron/Chromium 注入"开启辅助功能树"标志。注入后 Electron 有 2 秒
    /// 防抖才进入 kAXModeComplete（含字符级几何），因此在 app 激活时预注入，
    /// 让防抖期在用户打字前耗完。幂等，按 pid 只注入一次。
    func preInject(pid: pid_t) {
        guard !axEnabledPids.contains(pid) else { return }
        axEnabledPids.insert(pid)
        let appEl = appElement(for: pid)
        // Claude 桌面版对 AXEnhancedUserInterface 返回 NotImplemented，
        // AXManualAccessibility 才是 Electron 的有效开关；两个都设，错误忽略。
        AXUIElementSetAttributeValue(appEl, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(appEl, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    /// 纯 AX 查询；frontPid 为前台 app 进程号（由主线程捕获后传入）。
    func locateAX(primaryHeight: CGFloat, frontPid: pid_t?) -> CGPoint? {
        if let pid = frontPid { preInject(pid: pid) }
        return axPoint(primaryHeight: primaryHeight)
    }

    /// Electron/Chromium 常以 err=0 返回零尺寸垃圾矩形（如 (0, 屏高, 0, 0)）。
    /// 用"像光标/文本行"的尺寸约束过滤。
    private func isPlausibleCaretRect(_ r: CGRect) -> Bool {
        r.minX.isFinite && r.minY.isFinite
            && r.height >= 4 && r.height <= 300
            && r.width >= 0 && r.width <= 300
    }

    // MARK: - TextMarker 管线（Chromium/Electron/WebKit）

    /// 字符级矩形校验：行高 2–160（SuperCmd 阈值），过滤容器巨矩形与全零矩形。
    private func isPlausibleCharRect(_ r: CGRect) -> Bool {
        r.minX.isFinite && r.minY.isFinite
            && r.height > 2 && r.height < 160
            && r.width >= 0 && r.width < 300
            && !(abs(r.minX) < 0.5 && abs(r.minY) < 0.5 && r.width == 0 && r.height == 0)
    }

    private func copyMarker(_ element: AXUIElement, _ attribute: String, _ marker: AXTextMarker) -> AXTextMarker? {
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, attribute as CFString, marker, &out) == .success,
              let ref = out, CFGetTypeID(ref) == AXTextMarkerGetTypeID() else { return nil }
        return (ref as! AXTextMarker)
    }

    private func boundsForMarkerRange(_ element: AXUIElement, _ range: AXTextMarkerRange) -> CGRect? {
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, "AXBoundsForTextMarkerRange" as CFString, range, &out) == .success,
              let ref = out, CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(ref as! AXValue, .cgRect, &rect), isPlausibleCharRect(rect) else { return nil }
        return rect
    }

    /// VoiceOver 同款 TextMarker 通道，Chromium 对任意 AX 客户端开放（AXTextMarker
    /// C API 自 macOS 12 起公开）。直接用选区 marker range 查 bounds 会拿到容器
    /// 巨矩形或被丢弃的零宽矩形（Chromium 不下沉锚点 + Union 丢零宽 rect），必须
    /// "洗锚点"：用 Previous/Next 把光标 marker 下沉到叶子文本节点并扩成 1 字符 range。
    private func markerCaretRect(_ element: AXUIElement) -> CGRect? {
        var rangeObj: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXSelectedTextMarkerRange" as CFString, &rangeObj) == .success,
              let rangeRef = rangeObj, CFGetTypeID(rangeRef) == AXTextMarkerRangeGetTypeID() else { return nil }
        let caretEnd = AXTextMarkerRangeCopyEndMarker(rangeRef as! AXTextMarkerRange)

        // 向后洗：[prev(end), next(prev)] = 光标前一字符的叶子级 range，右缘即光标
        if let prev = copyMarker(element, "AXPreviousTextMarkerForTextMarker", caretEnd),
           let back = copyMarker(element, "AXNextTextMarkerForTextMarker", prev) {
            let charRange = AXTextMarkerRangeCreate(kCFAllocatorDefault, prev, back)
            if let rect = boundsForMarkerRange(element, charRange) {
                return CGRect(x: rect.maxX - 1, y: rect.minY, width: 2, height: rect.height)
            }
        }
        // 行首/空文档：向前洗，[prev(next(end)), next(end)] = 光标后一字符，左缘即光标
        if let next = copyMarker(element, "AXNextTextMarkerForTextMarker", caretEnd),
           let fwd = copyMarker(element, "AXPreviousTextMarkerForTextMarker", next) {
            let charRange = AXTextMarkerRangeCreate(kCFAllocatorDefault, fwd, next)
            if let rect = boundsForMarkerRange(element, charRange) {
                return CGRect(x: rect.minX - 1, y: rect.minY, width: 2, height: rect.height)
            }
        }
        // 兜底：取光标所在词的矩形，用右缘近似（前两种洗法在节点边界偶发失败时补救）
        var wordObj: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(
            element, "AXLeftWordTextMarkerRangeForTextMarker" as CFString, caretEnd, &wordObj) == .success,
           let wordRef = wordObj, CFGetTypeID(wordRef) == AXTextMarkerRangeGetTypeID(),
           let rect = boundsForMarkerRange(element, wordRef as! AXTextMarkerRange) {
            return CGRect(x: rect.maxX - 1, y: rect.minY, width: 2, height: rect.height)
        }
        return nil
    }

    // MARK: - 经典 range 通道（原生 app）

    private func boundsForRange(_ element: AXUIElement, _ rangeValue: AXValue) -> CGRect? {
        var boundsObj: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &boundsObj) == .success,
              let boundsRef = boundsObj, CFGetTypeID(boundsRef) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect), isPlausibleCaretRect(rect) else { return nil }
        return rect
    }

    private func axPoint(primaryHeight: CGFloat) -> CGPoint? {
        var focusedObj: CFTypeRef?
        let focusErr = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedObj)
        guard focusErr == .success, focusedObj != nil,
              let focusedRef = focusedObj, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return nil }
        let element = focusedRef as! AXUIElement
        // 焦点元素不一定继承 systemWide 的超时；显式设置，确保 marker/word 等
        // 参数化属性调用卡死时最多 0.4s 返回，不会永久阻塞后台队列。
        AXUIElementSetMessagingTimeout(element, 0.4)

        // 1. 插入点精确位置（带垃圾矩形过滤）
        var rangeObj: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeObj) == .success,
           let rangeRef = rangeObj, CFGetTypeID(rangeRef) == AXValueGetTypeID() {
            let rangeValue = rangeRef as! AXValue
            if let rect = boundsForRange(element, rangeValue) {
                return emissionPoint(forAXRect: rect, primaryScreenHeight: primaryHeight)
            }
            // 1b. 空选区 bounds 失败时查"前一个字符"的 bounds（Electron 系常见可行路径），
            //     用其右缘作为光标位置。
            var range = CFRange(location: 0, length: 0)
            if AXValueGetValue(rangeValue, .cfRange, &range), range.location > 0 {
                var prev = CFRange(location: range.location - 1, length: 1)
                if let prevValue = AXValueCreate(.cfRange, &prev),
                   let rect = boundsForRange(element, prevValue) {
                    let caret = CGRect(x: rect.maxX - 1, y: rect.minY, width: 2, height: rect.height)
                    return emissionPoint(forAXRect: caret, primaryScreenHeight: primaryHeight)
                }
            }
        }

        // 2. TextMarker 管线（Chromium/Electron/WebKit 的 web 内容，VoiceOver 同款通道）
        let now = ProcessInfo.processInfo.systemUptime
        if let rect = markerCaretRect(element) {
            let point = emissionPoint(forAXRect: rect, primaryScreenHeight: primaryHeight)
            lastMarkerPoint = point
            lastMarkerTime = now
            return point
        }
        // 2b. marker 偶发竞态 miss：若刚才（<1.2s）拿到过有效点，光标几乎没动，复用之，
        //     避免降级到固定的 frame 位置造成"突然蹦一下"。
        if let cached = lastMarkerPoint, now - lastMarkerTime < 1.2 {
            return cached
        }

        // 3. 焦点元素 frame 左缘（无 marker 历史时的兜底：文本输入首字符靠左，
        //    比 frame 中心准）
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
                let leftRect = CGRect(x: pos.x + 8, y: pos.y + size.height / 2, width: 2, height: 2)
                return emissionPoint(forAXRect: leftRect, primaryScreenHeight: primaryHeight)
            }
        }
        return nil
    }
}
