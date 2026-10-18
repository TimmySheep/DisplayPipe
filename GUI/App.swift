import AppKit

// Manual recovery delegates to the guarded transaction engine. Rows and all copy about
// displays come from the live enumeration: nothing here names a specific monitor, and the
// countdown that the backend enforces is shown prominently while it runs.
private final class DiagnosticDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    typealias Collector = ([UInt32: String]) -> Snapshot
    typealias Runner = ([String], @escaping ([String: Any]) -> Void) throws -> [String: Any]
    private let collect: Collector
    private let run: Runner
    init(collect: @escaping Collector = Diagnostics.collect,
         run: @escaping Runner = { try RecoveryClient.run($0, progress: $1) }) {
        self.collect = collect; self.run = run; super.init()
    }
    private(set) var window: NSWindow!
    private var root: NSStackView!
    private var displayRowsStack: NSStackView!
    private var refreshButton: NSButton!
    private var detailsButton: NSButton!
    private var stateLabel: NSTextField!
    private var stateDetail: NSTextField!
    private var hardwareLine: NSTextField!
    private var statusLabels: [NSTextField] = []
    private var detailsScroll: NSScrollView?
    private var diagnosticsLabel: NSTextField?
    private var acceptButton: NSButton?
    private var planButton: NSButton?
    private var noFallbackCheckbox: NSButton?
    private var languageSelector: NSPopUpButton?
    private var languageLabel: NSTextField?
    private var guideButton: NSButton?
    private var recordsButton: NSButton?
    private var fallbackRiskLabel: NSTextField?
    private var fallbackHeading: NSTextField?
    private var quitMenuItem: NSMenuItem?
    private let fallbackRiskKey = "Without an online internal display, the selected external display may be the only lit screen. It may go dark while reinitializing, hiding progress and undo. The countdown attempts an automatic revert; a missing service or changed identity prevents verified undo and retains a pending transaction. Opening the lid may change service identities. Manual handling may be needed."
    private var snapshot: Snapshot?
    private var recoveryObject: [String: Any] = [:]
    private var refreshing = false
    private var operationActive = false
    private var recoverButton: NSButton!
    private var undoButton: NSButton!
    private var activity: NSProgressIndicator!
    private var rowCount = 1
    private var recoveryState = RecoveryPresentation(["state": "failure", "error": L10n.text("Checking connections…")])

    private var compactHeight: CGFloat { 420 + 44 * CGFloat(max(0, rowCount - 2)) }
    private var detailsHeight: CGFloat { compactHeight + 260 }

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
        let status = label(L10n.text("Checking"), size: 12); status.textColor = .secondaryLabelColor
        statusLabels.append(status)
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
    /// One row per discovered external display; the row count follows the live enumeration.
    private func rebuildDisplayRows(_ rows: [(name: String, status: String)]) {
        for view in displayRowsStack.arrangedSubviews {
            displayRowsStack.removeArrangedSubview(view); view.removeFromSuperview()
        }
        statusLabels = []; rowCount = max(1, rows.count)
        for entry in rows {
            let box = displayRow(entry.name)
            displayRowsStack.addArrangedSubview(box)
            box.widthAnchor.constraint(equalTo: displayRowsStack.widthAnchor).isActive = true
            statusLabels.last?.stringValue = entry.status
        }
        resizeForRows()
    }
    private func resizeForRows() {
        guard window != nil, root != nil else { return }
        let height = detailsScroll == nil ? compactHeight : detailsHeight
        var frame = window.frame
        let contentHeight = window.contentRect(forFrameRect: frame).height
        guard abs(contentHeight - height) > 0.5 else { return }
        frame.origin.y -= height - contentHeight; frame.size.height += height - contentHeight
        window.setFrame(frame, display: true, animate: false)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu(); let item = NSMenuItem(); let appMenu = NSMenu()
        quitMenuItem = appMenu.addItem(withTitle: L10n.text("Quit DisplayPipe"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        refreshButton = NSButton(title: L10n.text("Refresh"), target: self, action: #selector(refresh)); refreshButton.controlSize = .small; refreshButton.bezelStyle = .rounded; refreshButton.keyEquivalent = "r"
        let heading = NSStackView(views: [label("DisplayPipe", size: 23, weight: .semibold), NSView(), refreshButton!]); heading.alignment = .centerY
        add(heading)
        stateLabel = label(L10n.text("Checking connections…"), size: 15, weight: .medium)
        stateDetail = label("", size: 12); stateDetail.textColor = .secondaryLabelColor; stateDetail.maximumNumberOfLines = 4
        let state = NSStackView(views: [stateLabel!, stateDetail!]); state.orientation = .vertical; state.alignment = .leading; state.spacing = 5
        stateDetail.isHidden = true; add(state)
        displayRowsStack = NSStackView(); displayRowsStack.orientation = .vertical; displayRowsStack.spacing = 10
        add(displayRowsStack)
        rebuildDisplayRows([(name: L10n.text("External display"), status: L10n.text("Checking"))])
        hardwareLine = label(L10n.text("Checking connections…"), size: 12); hardwareLine.textColor = .secondaryLabelColor
        add(hardwareLine)
        recoverButton = NSButton(title: L10n.text("Recover Displays"), target: self, action: #selector(recover)); recoverButton.bezelStyle = .rounded; recoverButton.controlSize = .large; recoverButton.keyEquivalent = "\r"
        undoButton = NSButton(title: L10n.text("Undo This Override"), target: self, action: #selector(undo)); undoButton.bezelStyle = .rounded; undoButton.isHidden = true
        activity = NSProgressIndicator(); activity.style = .spinning; activity.controlSize = .small; activity.isDisplayedWhenStopped = false
        let actions = NSStackView(views: [recoverButton!, undoButton!, activity!]); actions.spacing = 10; actions.alignment = .centerY
        add(actions)
        detailsButton = NSButton(title: L10n.text("Details"), target: self, action: #selector(toggleDetails)); detailsButton.bezelStyle = .inline; detailsButton.controlSize = .small
        detailsButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil); detailsButton.imagePosition = .imageLeading
        root.addArrangedSubview(detailsButton)
        controls()
    }
    @objc private func toggleDetails() {
        if let scroll = detailsScroll {
            root.removeArrangedSubview(scroll); scroll.removeFromSuperview()
            detailsScroll = nil; diagnosticsLabel = nil; planButton = nil; acceptButton = nil; noFallbackCheckbox = nil
            languageSelector = nil; languageLabel = nil; guideButton = nil; recordsButton = nil; fallbackRiskLabel = nil; fallbackHeading = nil
        } else {
            let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
            let document = DiagnosticDocumentView(); document.translatesAutoresizingMaskIntoConstraints = false
            let sections = NSStackView(); sections.orientation = .vertical; sections.alignment = .leading; sections.spacing = 12; sections.translatesAutoresizingMaskIntoConstraints = false
            diagnosticsLabel = label("", size: 11); diagnosticsLabel!.textColor = .secondaryLabelColor
            guideButton = NSButton(title: L10n.text("User Guide"), target: self, action: #selector(openGuide))
            recordsButton = NSButton(title: L10n.text("Open Records"), target: self, action: #selector(openProject))
            let links = NSStackView(views: [guideButton!, recordsButton!]); links.spacing = 8
            languageLabel = label(L10n.text("Language"), size: 12)
            languageSelector = NSPopUpButton(frame: .zero, pullsDown: false)
            languageSelector!.target = self; languageSelector!.action = #selector(languageChanged)
            updateLanguageSelector()
            let languageRow = NSStackView(views: [languageLabel!, languageSelector!]); languageRow.spacing = 8
            sections.addArrangedSubview(languageRow)
            planButton = NSButton(title: L10n.text("Check Plan (No Writes)"), target: self, action: #selector(plan))
            acceptButton = NSButton(title: L10n.text("Confirm Physical Displays & OSD"), target: self, action: #selector(acceptPhysical))
            // Advanced, per-run opt-in: never pre-ticked, never persisted, never needed while the
            // internal display is online. Selecting it acknowledges the countdown-revert limits.
            noFallbackCheckbox = NSButton(checkboxWithTitle: L10n.text("Allow writes without internal fallback (this session only; not saved)"), target: self, action: nil)
            noFallbackCheckbox!.state = .off
            noFallbackCheckbox!.toolTip = L10n.text(fallbackRiskKey)
            noFallbackCheckbox!.cell?.wraps = true
            fallbackHeading = label(L10n.text("No-Internal-Fallback Authorization"), size: 12, weight: .medium)
            fallbackRiskLabel = label(L10n.text(fallbackRiskKey), size: 11)
            sections.addArrangedSubview(fallbackHeading!)
            sections.addArrangedSubview(fallbackRiskLabel!)
            sections.addArrangedSubview(links); sections.addArrangedSubview(planButton!)
            sections.addArrangedSubview(noFallbackCheckbox!)
            sections.addArrangedSubview(acceptButton!); sections.addArrangedSubview(diagnosticsLabel!)
            document.addSubview(sections); scroll.documentView = document
            NSLayoutConstraint.activate([
                document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
                sections.leadingAnchor.constraint(equalTo: document.leadingAnchor), sections.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -8),
                sections.topAnchor.constraint(equalTo: document.topAnchor, constant: 4), sections.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -8),
                diagnosticsLabel!.widthAnchor.constraint(equalTo: sections.widthAnchor),
                noFallbackCheckbox!.widthAnchor.constraint(equalTo: sections.widthAnchor),
                fallbackRiskLabel!.widthAnchor.constraint(equalTo: sections.widthAnchor)
            ])
            root.addArrangedSubview(scroll); scroll.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
            scroll.heightAnchor.constraint(equalToConstant: 240).isActive = true
            detailsScroll = scroll; updateDetails(); controls()
        }
        detailsButton.image = NSImage(systemSymbolName: detailsScroll == nil ? "chevron.right" : "chevron.down", accessibilityDescription: nil)
        resizeForRows()
    }
    private func updateLanguageSelector() {
        guard let selector = languageSelector else { return }
        selector.removeAllItems()
        selector.addItems(withTitles: [L10n.text("System"), "English", "简体中文"])
        selector.selectItem(at: LanguageChoice.allCases.firstIndex(of: L10n.choice) ?? 0)
    }
    @objc private func languageChanged() {
        guard let selector = languageSelector, LanguageChoice.allCases.indices.contains(selector.indexOfSelectedItem) else { return }
        selectLanguage(LanguageChoice.allCases[selector.indexOfSelectedItem])
    }
    /// Presentation-only: redraw cached state, never enumerate, run a command or change consent.
    func selectLanguage(_ choice: LanguageChoice) {
        L10n.select(choice)
        refreshButton.title = L10n.text("Refresh"); recoverButton.title = L10n.text("Recover Displays")
        undoButton.title = L10n.text("Undo This Override"); detailsButton.title = L10n.text("Details")
        guideButton?.title = L10n.text("User Guide"); recordsButton?.title = L10n.text("Open Records")
        planButton?.title = L10n.text("Check Plan (No Writes)"); acceptButton?.title = L10n.text("Confirm Physical Displays & OSD")
        noFallbackCheckbox?.title = L10n.text("Allow writes without internal fallback (this session only; not saved)")
        noFallbackCheckbox?.toolTip = L10n.text(fallbackRiskKey)
        fallbackHeading?.stringValue = L10n.text("No-Internal-Fallback Authorization")
        fallbackRiskLabel?.stringValue = L10n.text(fallbackRiskKey)
        languageLabel?.stringValue = L10n.text("Language"); updateLanguageSelector()
        quitMenuItem?.title = L10n.text("Quit DisplayPipe")
        if let value = snapshot { renderSnapshot(value) }
        else { rebuildDisplayRows([(name: L10n.text("External display"), status: L10n.text("Checking"))]); hardwareLine.stringValue = L10n.text("Checking connections…") }
        if refreshing { stateLabel.stringValue = L10n.text("Checking connections…") }
        else if operationActive && recoveryObject.isEmpty { stateLabel.stringValue = L10n.text("Checking identity and backup…") }
        else if recoveryObject.isEmpty { stateLabel.stringValue = L10n.text("Checking connections…") }
        else { presentRecovery(recoveryObject) }
        updateDetails(); controls()
    }
    private func updateDetails() {
        guard let field = diagnosticsLabel else { return }
        var parts = [recoveryState.title, recoveryState.detail,
                     L10n.text("Raw technical diagnostics (original language)"),
                     L10n.text("The diagnostics below retain their original backend language (Chinese or English), device names and paths. UI language does not rewrite them."),
                     recoveryState.technicalDetail]
        if JSONSerialization.isValidJSONObject(recoveryObject),
           let data = try? JSONSerialization.data(withJSONObject: recoveryObject, options: [.prettyPrinted, .sortedKeys]),
           let raw = String(data: data, encoding: .utf8) { parts.append(raw) }
        if !recoveryState.combinationDescription.isEmpty { parts.append(L10n.text("Combination: ") + recoveryState.combinationDescription) }
        if let path = recoveryObject["runDirectory"] as? String { parts.append(L10n.text("Run records: ") + path) }
        if let value = snapshot {
            parts += [L10n.text("Collected: ") + Presentation.beijingTime(value.refreshedAt), value.collectionSummary]
            parts += [value.displayDetails, value.portDetails, value.edidDetails]
        }
        parts.append(L10n.text("System readings do not measure physical input; check the display OSD. The countdown attempts verified automatic undo. A missing registry service can require manual handling. See the guide for scope, private API risks and stop conditions."))
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
        noFallbackCheckbox?.isEnabled = !busy
        if busy { activity.startAnimation(nil) } else { activity.stopAnimation(nil) }
    }
    func presentRecovery(_ object: [String: Any]) {
        recoveryObject = object
        let displays = ""
        recoveryState = RecoveryPresentation(object, displays: displays)
        stateLabel.stringValue = recoveryState.title
        stateDetail.stringValue = recoveryState.detail
        stateDetail.isHidden = recoveryState.detail.isEmpty
        updateDetails(); controls()
    }
    private func confirm(_ title: String, _ text: String, action: String) -> Bool {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = text
        alert.alertStyle = .warning; alert.addButton(withTitle: action); alert.addButton(withTitle: L10n.text("Cancel"))
        return alert.runModal() == .alertFirstButtonReturn
    }
    private func recoverConfirmation() -> String {
        var parts = [L10n.text("Select the external display holding two Pipes by its current identity, back up its EDID, apply a conservative temporary candidate, and observe for up to {0} seconds. ", String(recoveryState.countdownSeconds))
                     + L10n.text("Without stable evidence, automatically undo and verify the original bytes at the deadline; no click is needed. Private APIs may flicker or fail. Uncertain identity/readback retains a pending transaction for manual handling. Healthy displays are not written. Do not unplug or quit.")]
        if !recoveryState.targetName.isEmpty { parts.append(L10n.text("Target: ") + recoveryState.targetName + " · " + recoveryState.targetPort) }
        if !recoveryState.orderLabel.isEmpty { parts.append(L10n.text("Connection order: ") + recoveryState.orderLabel) }
        return parts.joined(separator: "\n\n")
    }
    @objc private func recover() {
        guard !refreshing && !operationActive else { return }
        var command = ["recover", "--execute", "--confirm-private-api-risk"]
        if recoveryState.requiresNoInternalFallback {
            guard noFallbackCheckbox?.state == .on else {
                let alert = NSAlert(); alert.messageText = L10n.text("Additional Authorization Required"); alert.alertStyle = .warning
                alert.informativeText = L10n.text("Read the technical risks in Details and explicitly authorize this session. No display write occurred.")
                alert.addButton(withTitle: L10n.text("OK")); alert.runModal(); return
            }
            command.append("--ack-no-internal-fallback")
        }
        guard confirm(L10n.text("Recover Displays?"), recoverConfirmation(), action: L10n.text("Confirm and Recover")) else { return }
        perform(command)
    }
    @objc private func plan() { perform(["recover"]) }
    @objc private func undo() {
        guard confirm(L10n.text("Undo This App’s Override?"), L10n.text("Only the one owned pending transaction with the same registry ID and full path is eligible. Mismatched original/candidate bytes or readback refuse writes; never retarget another device."), action: L10n.text("Confirm Undo")) else { return }
        perform(["undo", "--execute", "--confirm-private-api-risk"])
    }
    @objc private func acceptPhysical() {
        let names = (snapshot?.externalDisplays ?? []).map { $0.name }.filter { !$0.isEmpty }
        let subject = names.isEmpty ? L10n.text("the external displays") : names.joined(separator: L10n.text(" and "))
        guard confirm(L10n.text("Physical Displays Confirmed?"), L10n.text("Personally confirm that {0} are lit and check the actual OSD input. This records your confirmation only; it does not measure wire timing or write to displays.", String(subject)), action: L10n.text("Confirmed")) else { return }
        perform(["accept", "--confirm-physical"])
    }
    private func perform(_ command: [String]) {
        guard !refreshing && !operationActive else { return }
        operationActive = true; controls()
        stateLabel.stringValue = L10n.text("Checking identity and backup…"); stateDetail.isHidden = true
        let names = Diagnostics.screenNames()
        DispatchQueue.global(qos: .userInitiated).async { autoreleasepool {
            let result: [String: Any]
            do { result = try self.run(command) { value in DispatchQueue.main.async { self.presentRecovery(value) } } }
            catch { result = ["state": "failure", "error": error.localizedDescription] }
            let snapshot = self.collect(names)
            DispatchQueue.main.async { self.operationActive = false; self.present(snapshot); self.presentRecovery(result) }
        } }
    }
    @objc private func refresh() {
        guard !refreshing && !operationActive else { return }
        refreshing = true; controls(); stateLabel.stringValue = L10n.text("Checking connections…"); stateDetail.isHidden = true
        let names = Diagnostics.screenNames()
        DispatchQueue.global(qos: .userInitiated).async { autoreleasepool {
            let snapshot = self.collect(names)
            let status: [String: Any]
            do { status = try self.run(["status"], { _ in }) }
            catch { status = ["state": "failure", "error": error.localizedDescription] }
            DispatchQueue.main.async { self.present(snapshot); self.presentRecovery(status) }
        } }
    }
    func present(_ value: Snapshot) {
        snapshot = value
        renderSnapshot(value)
        refreshing = false; updateDetails(); controls()
    }
    private func renderSnapshot(_ value: Snapshot) {
        let cards = value.externalCards
        let rows = cards.isEmpty
            ? [(name: value.coreGraphicsFailed ? L10n.text("External displays: enumeration failed") : L10n.text("No external displays detected"), status: value.coreGraphicsFailed ? L10n.text("Unknown (enumeration failed)") : L10n.text("Check connections"))]
            : cards.map { (name: $0.name, status: $0.stateText) }
        rebuildDisplayRows(rows)
        hardwareLine.stringValue = value.coreGraphicsFailed ? L10n.text("Incomplete readings · See Details") : L10n.text("External displays: {0}", String(value.externalDisplays.count)) + (value.errors.isEmpty ? "" : L10n.text(" · Incomplete readings · See Details"))
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if operationActive {
            let alert = NSAlert(); alert.messageText = L10n.text("Recovery is in progress. Please wait."); alert.informativeText = L10n.text("Force quitting may leave a pending override. Reopening the app exposes manual undo."); alert.runModal()
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
