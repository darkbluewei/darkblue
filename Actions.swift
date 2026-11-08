import Cocoa

private let fm = FileManager.default
private let cutKey = "cutPaths"

// MARK: - 入口

func runAction(_ payload: RCPayload) {
    guard let action = RCAction(rawValue: payload.a) else { return }
    let urls = payload.p.map { URL(fileURLWithPath: $0) }
    let target = payload.t.map { URL(fileURLWithPath: $0, isDirectory: true) }
    // 选中了文件 -> 取它所在的文件夹；没选中 -> 当前文件夹
    let base = urls.first?.deletingLastPathComponent() ?? target

    switch action {
    case .cut:
        doCut(urls)
    case .paste:
        doPaste(urls: urls, base: base)
    case .openTerminal:
        doOpenTerminal(urls: urls, base: base)
    case .screenshot:
        doScreenshot()
    case .newTxt, .newMd, .newDocx, .newXlsx, .newPptx, .newPy, .newHtml, .newJson:
        doNewFile(action, in: creationDir(urls: urls, target: target))
    case .deleteForever:
        doDeleteForever(urls)
    case .copyPath:
        var list = urls
        if list.isEmpty, let t = target { list = [t] }
        setClipboard(list.map { $0.path }.joined(separator: "\n"))
    case .copyName:
        setClipboard(urls.map { $0.lastPathComponent }.joined(separator: "\n"))
    case .copyDirPath:
        if let b = base { setClipboard(b.path) }
    case .moveTo:
        doTransfer(urls, move: true, startDir: base)
    case .copyTo:
        doTransfer(urls, move: false, startDir: base)
    case .batchRename:
        doBatchRename(urls)
    case .zip:
        doZip(urls, base: base)
    case .toggleHidden:
        doToggleHidden()
    }
}

// MARK: - 通用工具

func showAlert(_ title: String, _ message: String) {
    NSApp.activate(ignoringOtherApps: true)
    let a = NSAlert()
    a.messageText = title
    a.informativeText = message
    a.alertStyle = .warning
    a.addButton(withTitle: "好")
    a.runModal()
}

@discardableResult
func shell(_ path: String, _ args: [String], cwd: URL? = nil) -> (status: Int32, output: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    if let cwd = cwd { p.currentDirectoryURL = cwd }
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return (-1, error.localizedDescription) }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
}

private func isDirectory(_ url: URL) -> Bool {
    var d: ObjCBool = false
    return fm.fileExists(atPath: url.path, isDirectory: &d) && d.boolValue
}

private func setClipboard(_ s: String) {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(s, forType: .string)
}

/// 重名时自动加后缀：tag 为空 -> "名称 2.ext"；tag="副本" -> "名称 副本.ext"、"名称 副本 2.ext"
private func uniqueURL(in dir: URL, name: String, tag: String) -> URL {
    var candidate = dir.appendingPathComponent(name)
    if !fm.fileExists(atPath: candidate.path) { return candidate }
    let ns = name as NSString
    let ext = ns.pathExtension
    let stem = ns.deletingPathExtension
    var n = 1
    while true {
        var newStem = stem
        if tag.isEmpty {
            newStem += " \(n + 1)"
        } else {
            newStem += " " + tag
            if n > 1 { newStem += " \(n)" }
        }
        let newName = ext.isEmpty ? newStem : newStem + "." + ext
        candidate = dir.appendingPathComponent(newName)
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        n += 1
    }
}

// MARK: - 剪切 / 粘贴

private func doCut(_ urls: [URL]) {
    guard !urls.isEmpty else { return }
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.writeObjects(urls as [NSURL])
    UserDefaults.standard.set(urls.map { $0.path }, forKey: cutKey)
}

private func doPaste(urls: [URL], base: URL?) {
    let dest: URL?
    if urls.count == 1, isDirectory(urls[0]) { dest = urls[0] } else { dest = base }
    guard let destination = dest else { return }

    let pb = NSPasteboard.general
    guard let items = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingFileURLsOnly: true]) as? [URL],
          !items.isEmpty else {
        showAlert("无法粘贴", "剪贴板里没有文件。请先对文件使用「剪切」，或在 Finder 里按 ⌘C 复制。")
        return
    }
    // 剪贴板内容正好是刚才「剪切」的那批文件 -> 移动；否则当作复制
    let cutList = Set(UserDefaults.standard.stringArray(forKey: cutKey) ?? [])
    let isCut = !cutList.isEmpty && cutList == Set(items.map { $0.path })

    transferItems(items, to: destination, move: isCut) { success in
        if isCut && success {
            UserDefaults.standard.removeObject(forKey: cutKey)
            NSPasteboard.general.clearContents()
        }
    }
}

/// 移动/复制一批文件到目标文件夹（后台执行）
private func transferItems(_ items: [URL], to dest: URL, move: Bool, completion: ((Bool) -> Void)? = nil) {
    DispatchQueue.global(qos: .userInitiated).async {
        let destPath = dest.standardizedFileURL.path
        var errors: [String] = []
        var results: [URL] = []
        for src in items {
            let srcPath = src.standardizedFileURL.path
            if destPath == srcPath || destPath.hasPrefix(srcPath + "/") {
                errors.append("\(src.lastPathComponent)：不能放进它自己里面")
                continue
            }
            if move && src.deletingLastPathComponent().standardizedFileURL.path == destPath {
                continue   // 剪切后粘贴回原文件夹：什么都不用做
            }
            do {
                if move {
                    let to = uniqueURL(in: dest, name: src.lastPathComponent, tag: "")
                    try fm.moveItem(at: src, to: to)
                    results.append(to)
                } else {
                    let to = uniqueURL(in: dest, name: src.lastPathComponent, tag: "副本")
                    try fm.copyItem(at: src, to: to)
                    results.append(to)
                }
            } catch {
                errors.append("\(src.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        DispatchQueue.main.async {
            completion?(errors.isEmpty)
            if !errors.isEmpty { showAlert("部分文件处理失败", errors.joined(separator: "\n")) }
            if !results.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(results) }
        }
    }
}

private func doTransfer(_ urls: [URL], move: Bool, startDir: URL?) {
    guard !urls.isEmpty else { return }
    NSApp.activate(ignoringOtherApps: true)
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = move ? "移动到此处" : "复制到此处"
    panel.message = move ? "选择要移动到的文件夹" : "选择要复制到的文件夹"
    panel.directoryURL = startDir
    guard panel.runModal() == .OK, let dest = panel.url else { return }
    transferItems(urls, to: dest, move: move)
}

// MARK: - 终端 / 截屏

private func doOpenTerminal(urls: [URL], base: URL?) {
    let dir: URL? = (urls.count == 1 && isDirectory(urls[0])) ? urls[0] : base
    guard let d = dir else { return }
    NSWorkspace.shared.open([d],
                            withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                            configuration: NSWorkspace.OpenConfiguration(),
                            completionHandler: nil)
}

private func doScreenshot() {
    NSWorkspace.shared.openApplication(
        at: URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app"),
        configuration: NSWorkspace.OpenConfiguration(),
        completionHandler: nil)
}

// MARK: - 新建文件

/// 新建位置：只选中了一个文件夹 -> 建在它里面；否则建在当前窗口所在文件夹
private func creationDir(urls: [URL], target: URL?) -> URL? {
    if urls.count == 1, isDirectory(urls[0]) { return urls[0] }
    if let t = target, isDirectory(t) { return t }
    return urls.first?.deletingLastPathComponent() ?? target
}

private func ensureWritable(_ dir: URL) -> Bool {
    if fm.isWritableFile(atPath: dir.path) { return true }
    showAlert("无法在这里创建", "没有写入权限：\(dir.path)\n\n请进入具体的文件夹（如桌面、文稿、下载）后再新建。")
    return false
}

private func newFileSpec(_ a: RCAction) -> (label: String, ext: String, name: String) {
    switch a {
    case .newTxt:  return ("文本文档", "txt", "未命名文本")
    case .newMd:   return ("Markdown 文件", "md", "未命名")
    case .newDocx: return ("Word 文档", "docx", "未命名文档")
    case .newXlsx: return ("Excel 表格", "xlsx", "未命名表格")
    case .newPptx: return ("PowerPoint", "pptx", "未命名演示文稿")
    case .newPy:   return ("Python 脚本", "py", "script")
    case .newHtml: return ("HTML 网页", "html", "index")
    default:       return ("JSON 文件", "json", "data")
    }
}

private func textContent(_ a: RCAction) -> String {
    switch a {
    case .newPy:
        return "#!/usr/bin/env python3\n# -*- coding: utf-8 -*-\n\n"
    case .newHtml:
        return "<!DOCTYPE html>\n<html lang=\"zh-CN\">\n<head>\n  <meta charset=\"UTF-8\">\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">\n  <title>无标题</title>\n</head>\n<body>\n\n</body>\n</html>\n"
    case .newJson:
        return "{}\n"
    default:
        return ""
    }
}

private func doNewFile(_ action: RCAction, in dir: URL?) {
    guard let dir = dir, ensureWritable(dir) else { return }
    let spec = newFileSpec(action)
    // 不弹窗：直接用默认名字创建，重名自动加序号，然后在 Finder 里选中
    let dest = uniqueURL(in: dir, name: spec.name + "." + spec.ext, tag: "")
    do {
        switch action {
        case .newDocx, .newXlsx, .newPptx:
            guard let tpl = Bundle.main.url(forResource: "blank", withExtension: spec.ext) else {
                throw NSError(domain: "SuperRightClick", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "找不到内置的空白模板"])
            }
            try fm.copyItem(at: tpl, to: dest)
        default:
            try textContent(action).write(to: dest, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.activateFileViewerSelecting([dest])
    } catch {
        showAlert("创建失败", error.localizedDescription)
    }
}

// MARK: - 彻底删除

private func isProtectedPath(_ url: URL) -> Bool {
    let path = url.standardizedFileURL.path
    if path == "/" || path == NSHomeDirectory() { return true }
    return ["/", "/Users", "/Volumes"].contains(url.standardizedFileURL.deletingLastPathComponent().path)
}

private func doDeleteForever(_ urls: [URL]) {
    guard !urls.isEmpty else { return }
    let protected = urls.filter { isProtectedPath($0) }
    let targets = urls.filter { !isProtectedPath($0) }
    if !protected.isEmpty {
        showAlert("受保护的位置", "出于安全，不能彻底删除这些：\n" + protected.map { $0.path }.joined(separator: "\n"))
    }
    guard !targets.isEmpty else { return }

    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .critical
    alert.messageText = targets.count == 1
        ? "彻底删除“\(targets[0].lastPathComponent)”？"
        : "彻底删除这 \(targets.count) 个项目？"
    alert.informativeText = "不会放进废纸篓，删除后无法恢复。"
    alert.addButton(withTitle: "取消")        // 默认按钮（回车）是取消，防止误删
    alert.addButton(withTitle: "彻底删除")
    alert.buttons[1].hasDestructiveAction = true
    guard alert.runModal() == .alertSecondButtonReturn else { return }

    DispatchQueue.global(qos: .userInitiated).async {
        var errors: [String] = []
        for u in targets {
            do { try fm.removeItem(at: u) }
            catch { errors.append("\(u.lastPathComponent)：\(error.localizedDescription)") }
        }
        DispatchQueue.main.async {
            if !errors.isEmpty { showAlert("部分项目删除失败", errors.joined(separator: "\n")) }
        }
    }
}

// MARK: - 批量重命名

private func doBatchRename(_ urls: [URL]) {
    guard !urls.isEmpty else { return }
    NSApp.activate(ignoringOtherApps: true)

    let alert = NSAlert()
    alert.messageText = "批量重命名（\(urls.count) 个项目）"
    alert.informativeText = "新名称 = 前缀 + 原名称 + 后缀（+ 序号），扩展名保持不变。"
    alert.addButton(withTitle: "重命名")
    alert.addButton(withTitle: "取消")

    let prefix = NSTextField(frame: .zero)
    prefix.placeholderString = "前缀（可留空）"
    let suffix = NSTextField(frame: .zero)
    suffix.placeholderString = "后缀（可留空）"
    let numbering = NSButton(checkboxWithTitle: "在末尾添加序号（_001、_002…）", target: nil, action: nil)

    let stack = NSStackView(views: [prefix, suffix, numbering])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 8
    NSLayoutConstraint.activate([
        prefix.widthAnchor.constraint(equalToConstant: 300),
        suffix.widthAnchor.constraint(equalToConstant: 300)
    ])
    stack.frame = NSRect(origin: .zero, size: stack.fittingSize)
    alert.accessoryView = stack
    alert.window.initialFirstResponder = prefix

    guard alert.runModal() == .alertFirstButtonReturn else { return }
    let pre = prefix.stringValue.replacingOccurrences(of: "/", with: "-")
    let suf = suffix.stringValue.replacingOccurrences(of: "/", with: "-")
    let useNum = (numbering.state == .on)
    if pre.isEmpty && suf.isEmpty && !useNum { return }

    let sorted = urls.sorted {
        $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
    }
    var errors: [String] = []
    var results: [URL] = []
    for (i, u) in sorted.enumerated() {
        let ns = u.lastPathComponent as NSString
        let ext = ns.pathExtension
        var stem = pre + ns.deletingPathExtension + suf
        if useNum { stem += String(format: "_%03d", i + 1) }
        let newName = ext.isEmpty ? stem : stem + "." + ext
        let dest = u.deletingLastPathComponent().appendingPathComponent(newName)
        if dest.path == u.path { continue }
        if fm.fileExists(atPath: dest.path) {
            errors.append("\(newName) 已存在，已跳过")
            continue
        }
        do {
            try fm.moveItem(at: u, to: dest)
            results.append(dest)
        } catch {
            errors.append("\(u.lastPathComponent)：\(error.localizedDescription)")
        }
    }
    if !errors.isEmpty { showAlert("部分项目未能重命名", errors.joined(separator: "\n")) }
    if !results.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(results) }
}

// MARK: - 压缩 / 隐藏文件

private func doZip(_ urls: [URL], base: URL?) {
    guard let dir = base, !urls.isEmpty else { return }
    let zipName = urls.count == 1 ? urls[0].lastPathComponent + ".zip" : "归档.zip"
    let out = uniqueURL(in: dir, name: zipName, tag: "")
    let names = urls.map { "./" + $0.lastPathComponent }
    DispatchQueue.global(qos: .userInitiated).async {
        let r = shell("/usr/bin/zip",
                      ["-r", "-q", "-y", out.lastPathComponent] + names + ["-x", "*.DS_Store"],
                      cwd: dir)
        DispatchQueue.main.async {
            if r.status == 0 {
                NSWorkspace.shared.activateFileViewerSelecting([out])
            } else {
                showAlert("压缩失败", r.output)
            }
        }
    }
}

private func doToggleHidden() {
    let r = shell("/usr/bin/defaults", ["read", "com.apple.finder", "AppleShowAllFiles"])
    let value = r.output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    let showing = ["1", "true", "yes"].contains(value)
    shell("/usr/bin/defaults", ["write", "com.apple.finder", "AppleShowAllFiles", "-bool", showing ? "false" : "true"])
    shell("/usr/bin/killall", ["Finder"])
}
