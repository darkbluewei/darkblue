import Cocoa
import FinderSync

class FinderSync: FIFinderSync {

    /// 最近一次弹出的是不是「空白处」菜单（是的话，忽略可能残留的选中项）
    private var lastWasContainer = false

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [
            URL(fileURLWithPath: "/"),
            URL(fileURLWithPath: "/Volumes")
        ]
    }

    // MARK: 工具栏按钮（可选，Finder 工具栏自定义里能拖出来）
    override var toolbarItemName: String { "超级右键" }
    override var toolbarItemToolTip: String { "超级右键菜单" }
    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "contextualmenu.and.cursorarrow", accessibilityDescription: nil)
            ?? NSImage(named: NSImage.actionTemplateName)
            ?? NSImage()
    }

    // MARK: 菜单
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let ctl = FIFinderSyncController.default()
        let hasSelection = !(ctl.selectedItemURLs() ?? []).isEmpty

        switch menuKind {
        case .contextualMenuForSidebar:
            return nil
        default:
            break
        }

        let showItems = (menuKind == .contextualMenuForContainer) ? false : hasSelection
        lastWasContainer = !showItems
        let menu = NSMenu(title: "")

        // ---- 一级菜单 ----
        if showItems { add(menu, "剪切", .cut, "scissors") }
        add(menu, "粘贴", .paste, "doc.on.clipboard")
        add(menu, "在此处打开终端", .openTerminal, "terminal")
        add(menu, "截屏工具", .screenshot, "camera.viewfinder")
        if showItems { add(menu, "彻底删除", .deleteForever, "trash") }
        menu.addItem(NSMenuItem.separator())

        // ---- 新建文件 ----
        let newSub = NSMenu(title: "新建文件")
        add(newSub, "文本文档 (.txt)", .newTxt)
        add(newSub, "Markdown (.md)", .newMd)
        add(newSub, "Word 文档 (.docx)", .newDocx)
        add(newSub, "Excel 表格 (.xlsx)", .newXlsx)
        add(newSub, "PowerPoint (.pptx)", .newPptx)
        add(newSub, "Python 脚本 (.py)", .newPy)
        add(newSub, "HTML 网页 (.html)", .newHtml)
        add(newSub, "JSON 文件 (.json)", .newJson)
        addSub(menu, "新建文件", "doc.badge.plus", newSub)

        // ---- 复制路径 ----
        let pathSub = NSMenu(title: "复制路径")
        if showItems {
            add(pathSub, "复制文件路径", .copyPath)
            add(pathSub, "复制文件名", .copyName)
        }
        add(pathSub, "复制文件夹路径", .copyDirPath)
        addSub(menu, "复制路径", "link", pathSub)

        // ---- 文件操作 ----
        let opSub = NSMenu(title: "文件操作")
        if showItems {
            add(opSub, "移动到…", .moveTo)
            add(opSub, "复制到…", .copyTo)
            add(opSub, "批量重命名…", .batchRename)
            add(opSub, "压缩为 zip", .zip)
            opSub.addItem(NSMenuItem.separator())
        }
        add(opSub, "显示/隐藏隐藏文件", .toggleHidden)
        addSub(menu, "文件操作", "ellipsis.circle", opSub)

        return menu
    }

    @discardableResult
    private func add(_ menu: NSMenu, _ title: String, _ action: RCAction, _ symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(handle(_:)), keyEquivalent: "")
        item.tag = action.rawValue
        if let s = symbol {
            item.image = NSImage(systemSymbolName: s, accessibilityDescription: nil)
        }
        menu.addItem(item)
        return item
    }

    private func addSub(_ menu: NSMenu, _ title: String, _ symbol: String, _ sub: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        item.submenu = sub
        menu.addItem(item)
    }

    // MARK: 点击后：把请求交给主程序（扩展在沙盒里，不能直接改文件）
    @objc func handle(_ sender: AnyObject?) {
        guard let item = sender as? NSMenuItem, let action = RCAction(rawValue: item.tag) else { return }
        let ctl = FIFinderSyncController.default()
        let selected = lastWasContainer ? [] : (ctl.selectedItemURLs() ?? []).map { $0.path }
        let target = ctl.targetedURL()?.path
        let payload = RCPayload(a: action.rawValue, p: selected, t: target)
        guard let url = payload.url() else { return }
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.activates = false
        NSWorkspace.shared.open(url, configuration: cfg, completionHandler: nil)
    }
}
