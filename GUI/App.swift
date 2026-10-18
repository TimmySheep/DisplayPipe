import AppKit

// Manual recovery delegates to the unchanged guarded transaction engine.
private final class DiagnosticDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    typealias Collector = ([UInt32: String]) -> Snapshot
    private let collect: Collector
    init(collect: @escaping Collector = Diagnostics.collect) { self.collect = collect; super.init() }
    private(set) var window: NSWindow!
    private var root: NSStackView!
    private var refreshButton: NSButton!
    private var detailsButton: NSButton!
    private var stateLabel: NSTextField!
    private var stateDetail: NSTextField!
    private var targetLabels: [NSTextField] = []
    private var detailsScroll: NSScrollView?
    private var diagnosticsLabel: NSTextField?
    private var acceptButton: NSButton?
    private var planButton: NSButton?
    private var snapshot: Snapshot?
    private var recoveryObject: [String: Any] = [:]
    private var refreshing = false
    private var operationActive = false
    private var recoverButton: NSButton!
    private var undoButton: NSButton!
    private var activity: NSProgressIndicator!
    private var recoveryState = RecoveryPresentation(["state": "failure", "error": "正在检查连接…"])

    private func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.isSelectable = true
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        return field
    }
    private func displayRow(_ name: String) -> NSView {
        let box = NSBox(); box.boxType = .custom; box.borderWidth = 0
        box.fillColor = .controlBackgroundColor; box.cornerRadius = 10
        let title = label(name, weight: .medium)
        let status = label("检查中", size: 12); status.textColor = .secondaryLabelColor
        targetLabels.append(status)
        let row = NSStackView(views: [title, NSView(), status]); row.alignment = .centerY; row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false; box.contentView!.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: box.contentView!.leadingAnchor, constant: 14),
            row.trailingAnchor.constraint(equalTo: box.contentView!.trailingAnchor, constant: -14),
            row.topAnchor.constraint(equalTo: box.contentView!.topAnchor, constant: 16),
            row.bottomAnchor.constraint(equalTo: box.contentView!.bottomAnchor, constant: -16)
        ])
        return box
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu(); let item = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 DisplayPipe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu; menu.addItem(item); NSApp.mainMenu = menu
        buildWindow()
        window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); refresh()
    }
    // Constructing the native interface does not enumerate or write displays.
    func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 420), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.delegate = self; window.title = "DisplayPipe"
        root = NSStackView(); root.orientation = .vertical; root.alignment = .leading; root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!; content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            root.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20)
        ])
        func add(_ view: NSView) { root.addArrangedSubview(view); view.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true }
        refreshButton = NSButton(title: "刷新", target: self, action: #selector(refresh)); refreshButton.controlSize = .small; refreshButton.bezelStyle = .rounded; refreshButton.keyEquivalent = "r"
        let heading = NSStackView(views: [label("DisplayPipe", size: 23, weight: .semibold), NSView(), refreshButton!]); heading.alignment = .centerY
        add(heading)
        stateLabel = label("正在检查连接…", size: 15, weight: .medium)
        stateDetail = label("", size: 12); stateDetail.textColor = .secondaryLabelColor; stateDetail.maximumNumberOfLines = 3
        let state = NSStackView(views: [stateLabel!, stateDetail!]); state.orientation = .vertical; state.alignment = .leading; state.spacing = 5
        stateDetail.isHidden = true; add(state)
        for name in ["HWV QSN-CAB", "P275MV PLUS"] { add(displayRow(name)) }
        recoverButton = NSButton(title: "恢复双屏", target: self, action: #selector(recover)); recoverButton.bezelStyle = .rounded; recoverButton.controlSize = .large; recoverButton.keyEquivalent = "\r"
        undoButton = NSButton(title: "撤销本次覆盖", target: self, action: #selector(undo)); undoButton.bezelStyle = .rounded; undoButton.isHidden = true
        activity = NSProgressIndicator(); activity.style = .spinning; activity.controlSize = .small; activity.isDisplayedWhenStopped = false
        let actions = NSStackView(views: [recoverButton!, undoButton!, activity!]); actions.spacing = 10; actions.alignment = .centerY
        add(actions)
        detailsButton = NSButton(title: "详细信息", target: self, action: #selector(toggleDetails)); detailsButton.bezelStyle = .inline; detailsButton.controlSize = .small
        detailsButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil); detailsButton.imagePosition = .imageLeading
        root.addArrangedSubview(detailsButton)
        controls()
    }
    @objc private func toggleDetails() {
        if let scroll = detailsScroll {
            root.removeArrangedSubview(scroll); scroll.removeFromSuperview()
            detailsScroll = nil; diagnosticsLabel = nil; planButton = nil; acceptButton = nil
        } else {
            let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
            let document = DiagnosticDocumentView(); document.translatesAutoresizingMaskIntoConstraints = false
            let sections = NSStackView(); sections.orientation = .vertical; sections.alignment = .leading; sections.spacing = 12; sections.translatesAutoresizingMaskIntoConstraints = false
            diagnosticsLabel = label("", size: 11); diagnosticsLabel!.textColor = .secondaryLabelColor
            let links = NSStackView(views: [NSButton(title: "使用说明", target: self, action: #selector(openGuide)), NSButton(title: "打开记录", target: self, action: #selector(openProject))]); links.spacing = 8
            planButton = NSButton(title: "检查方案（不写入）", target: self, action: #selector(plan))
            acceptButton = NSButton(title: "确认实体双屏与 OSD", target: self, action: #selector(acceptPhysical))
            sections.addArrangedSubview(links); sections.addArrangedSubview(planButton!); sections.addArrangedSubview(acceptButton!); sections.addArrangedSubview(diagnosticsLabel!)
            document.addSubview(sections); scroll.documentView = document
            NSLayoutConstraint.activate([
                document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
                sections.leadingAnchor.constraint(equalTo: document.leadingAnchor), sections.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -8),
                sections.topAnchor.constraint(equalTo: document.topAnchor, constant: 4), sections.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -8),
                diagnosticsLabel!.widthAnchor.constraint(equalTo: sections.widthAnchor)
            ])
            root.addArrangedSubview(scroll); scroll.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
            scroll.heightAnchor.constraint(equalToConstant: 240).isActive = true
            detailsScroll = scroll; updateDetails(); controls()
        }
        detailsButton.image = NSImage(systemSymbolName: detailsScroll == nil ? "chevron.right" : "chevron.down", accessibilityDescription: nil)
        var frame = window.frame; let height: CGFloat = detailsScroll == nil ? 420 : 680
        let contentHeight = window.contentRect(forFrameRect: frame).height
        frame.origin.y -= height - contentHeight; frame.size.height += height - contentHeight
        window.setFrame(frame, display: true, animate: false)
    }
    private func updateDetails() {
        guard let field = diagnosticsLabel else { return }
        var parts = [recoveryState.title, recoveryState.detail]
        if let path = recoveryObject["runDirectory"] as? String { parts.append("本次记录：" + path) }
        if let value = snapshot {
            parts += ["采集：" + Presentation.beijingTime(value.refreshedAt), value.collectionSummary]
            parts += value.targetCards.map { value.targetDetails($0) }
            parts += [value.pipeDetails, value.edidDetails]
        }
        parts.append("系统读数不是实体输入测量；请查看显示器 OSD。支持范围、私有接口风险及停止条件见使用说明。")
        field.stringValue = parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
    @objc private func openProject() {
        try? FileManager.default.createDirectory(at: RecoveryClient.stateURL, withIntermediateDirectories: true)
        NSWorkspace.shared.open(RecoveryClient.stateURL)
    }
    @objc private func openGuide() {
        if let resources = Bundle.main.resourceURL { NSWorkspace.shared.open(resources.appendingPathComponent("docs/USER_GUIDE.md")) }
    }
    private func controls() {
        let busy = refreshing || operationActive
        refreshButton.isEnabled = !busy; recoverButton.isEnabled = !busy && recoveryState.canRecover
        planButton?.isEnabled = !busy && recoveryState.canRecover
        undoButton.isHidden = !recoveryState.canUndo; undoButton.isEnabled = !busy && recoveryState.canUndo
        acceptButton?.isHidden = !recoveryState.canAcceptPhysical
        acceptButton?.isEnabled = !busy && recoveryState.canAcceptPhysical
        if busy { activity.startAnimation(nil) } else { activity.stopAnimation(nil) }
    }
    func presentRecovery(_ object: [String: Any]) {
        recoveryObject = object; recoveryState = RecoveryPresentation(object)
        stateLabel.stringValue = recoveryState.title
        stateDetail.stringValue = String(recoveryState.detail.prefix(180))
        stateDetail.isHidden = recoveryState.detail.isEmpty
        updateDetails(); controls()
    }
    private func confirm(_ title: String, _ text: String, action: String) -> Bool {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = text
        alert.alertStyle = .warning; alert.addButton(withTitle: action); alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }
    @objc private func recover() {
        guard !refreshing && !operationActive else { return }
        guard confirm("恢复双屏？", "仅支持 P275 先接且双Pipe、华为缺失，内屏必须在线。会备份本次目标、临时应用120Hz EDID、观察最多20秒，并在系统证据稳定后核验撤销。私有接口可能闪屏或失败；身份/回读不确定时会保留未结束事务，需手动处理。已有双屏在线时不会写入。请勿拔线、合盖或退出。", action: "确认并恢复") else { return }
        perform(["recover", "--execute", "--confirm-private-api-risk"])
    }
    @objc private func plan() { perform(["recover"]) }
    @objc private func undo() {
        guard confirm("撤销本程序本次覆盖？", "只处理唯一未结束事务的同一注册表ID与完整路径。原件/候选或当前回读不一致时拒绝写入，不自动改选设备。", action: "确认撤销") else { return }
        perform(["undo", "--execute", "--confirm-private-api-risk"])
    }
    @objc private func acceptPhysical() {
        guard confirm("两个实体屏幕已确认？", "请亲自确认华为与 P275 均点亮，并查看显示器 OSD 实际输入。此按钮只记录你的确认，不测量线缆时序、不写显示。", action: "两屏已确认") else { return }
        perform(["accept", "--confirm-physical"])
    }
    private func perform(_ command: [String]) {
        guard !refreshing && !operationActive else { return }
        operationActive = true; controls()
        stateLabel.stringValue = "正在检查身份与备份…"; stateDetail.isHidden = true
        let names = Diagnostics.screenNames()
        DispatchQueue.global(qos: .userInitiated).async { autoreleasepool {
            let result: [String: Any]
            do { result = try RecoveryClient.run(command) { value in DispatchQueue.main.async { self.presentRecovery(value) } } }
            catch { result = ["state": "failure", "error": error.localizedDescription] }
            let snapshot = self.collect(names)
            DispatchQueue.main.async { self.operationActive = false; self.present(snapshot); self.presentRecovery(result) }
        } }
    }
    @objc private func refresh() {
        guard !refreshing && !operationActive else { return }
        refreshing = true; controls(); stateLabel.stringValue = "正在检查连接…"; stateDetail.isHidden = true
        let names = Diagnostics.screenNames()
        DispatchQueue.global(qos: .userInitiated).async { autoreleasepool {
            let snapshot = self.collect(names)
            let status: [String: Any]
            do { status = try RecoveryClient.run(["status"]) }
            catch { status = ["state": "failure", "error": error.localizedDescription] }
            DispatchQueue.main.async { self.present(snapshot); self.presentRecovery(status) }
        } }
    }
    func present(_ value: Snapshot) {
        snapshot = value
        for (index, card) in value.targetCards.enumerated() {
            let hz = card.display?.reportedRefreshHz
            let rate = hz.map { $0.isFinite && $0 > 0 ? String(format: " · %.0f Hz", $0) : " · 刷新率未知" } ?? ""
            targetLabels[index].stringValue = card.state == .online ? "在线" + rate : card.stateText
        }
        refreshing = false; updateDetails(); controls()
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if operationActive {
            let alert = NSAlert(); alert.messageText = "恢复事务正在进行，请等待完成。"; alert.informativeText = "强制退出可能留下未结束覆盖；再次打开App会显示手动撤销。"; alert.runModal()
            return .terminateCancel
        }
        return .terminateNow
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { if operationActive { NSSound.beep(); return false }; return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
#if !UI_TESTING
@main struct DisplayPipeApp {
    static func main() {
        if CommandLine.arguments.contains("--smoke-json") {
            let snapshot = Diagnostics.collect(names: Diagnostics.screenNames())
            do { FileHandle.standardOutput.write(try snapshot.json()); FileHandle.standardOutput.write(Data("\n".utf8)); exit(snapshot.errors.isEmpty ? 0 : 1) }
            catch { fputs("\(error)\n", stderr); exit(2) }
        }
        if CommandLine.arguments.contains("--recovery-smoke-json") {
            do {
                let result = try RecoveryClient.run(["recover"])
                let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data("\n".utf8)); exit(result["state"] as? String == "already-healthy" || result["state"] as? String == "dry-run" ? 0 : 1)
            } catch { fputs("\(error.localizedDescription)\n", stderr); exit(2) }
        }
        let app = NSApplication.shared; let delegate = AppDelegate(); app.setActivationPolicy(.regular); app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
#endif
