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
        coordinator.refreshTrust()
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
