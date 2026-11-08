import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var statusLabel = NSTextField(wrappingLabelWithString: "")
    private var handledURL = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 被右键菜单拉起时（收到 URL）不弹窗；用户自己双击打开才显示设置窗口
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self, !self.handledURL else { return }
            self.showWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let s = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: s),
              let payload = RCPayload(url: url) else { return }
        handledURL = true
        runAction(payload)
    }

    // MARK: 设置窗口

    private func showWindow() {
        NSApp.setActivationPolicy(.regular)
        if window == nil { buildWindow() }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    private func buildWindow() {
        let title = NSTextField(labelWithString: "超级右键")
        title.font = NSFont.boldSystemFont(ofSize: 20)

        let intro = NSTextField(wrappingLabelWithString:
            "Finder 右键增强工具。首次使用请按顺序操作：\n" +
            "1. 把本应用放进「应用程序」文件夹，再打开一次\n" +
            "2. 点下面的「启用 Finder 扩展」\n" +
            "3. 若右键菜单没有出现：系统设置 → 通用 → 登录项与扩展 → 扩展 → Finder，勾选「超级右键」\n" +
            "4. 第一次操作桌面、文稿等文件夹时，系统会询问访问权限，请点「允许」")
        intro.preferredMaxLayoutWidth = 420

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.preferredMaxLayoutWidth = 420

        let b1 = NSButton(title: "启用 Finder 扩展", target: self, action: #selector(enableExtension))
        let b2 = NSButton(title: "打开系统扩展设置", target: self, action: #selector(openSettings))
        let b3 = NSButton(title: "重启 Finder", target: self, action: #selector(restartFinder))
        let b4 = NSButton(title: "退出超级右键", target: self, action: #selector(quit))
        let row = NSStackView(views: [b1, b2, b3])
        row.orientation = .horizontal
        row.spacing = 8

        let stack = NSStackView(views: [title, intro, row, statusLabel, b4])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 300),
                         styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = "超级右键"
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = stack
        w.setContentSize(NSSize(width: 460, height: stack.fittingSize.height))
        window = w
    }

    @objc private func enableExtension() {
        guard let appex = Bundle.main.builtInPlugInsURL?.appendingPathComponent("FinderExtension.appex") else {
            statusLabel.stringValue = "找不到内置的扩展，请确认应用完整。"
            return
        }
        shell("/usr/bin/pluginkit", ["-a", appex.path])
        let r = shell("/usr/bin/pluginkit", ["-e", "use", "-i", RCConst.extensionID])
        shell("/usr/bin/killall", ["Finder"])
        statusLabel.stringValue = r.status == 0
            ? "已发送启用指令并重启 Finder。右键试试；若还没有菜单，请到系统设置里手动勾选。"
            : "自动启用失败（\(r.output.trimmingCharacters(in: .whitespacesAndNewlines))），请到系统设置里手动勾选。"
    }

    @objc private func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func restartFinder() {
        shell("/usr/bin/killall", ["Finder"])
        statusLabel.stringValue = "Finder 已重启。"
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
