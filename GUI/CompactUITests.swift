import AppKit

@main struct CompactUITests {
    static func main() throws {
        L10n.preferences = TestLanguagePreferences()

        _ = NSApplication.shared
        let delegate = AppDelegate(collect: { _ in fatalError("layout tests must not collect live displays") })
        delegate.buildWindow()
        let window = delegate.window!
        let content = window.contentView!
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        func visible(_ view: NSView) -> Bool { !view.isHidden && (view.superview.map(visible) ?? true) }
        func buttons() -> [NSButton] { all(content).compactMap { $0 as? NSButton } }
        func button(_ title: String) -> NSButton { buttons().first { $0.title == title }! }
        func texts() -> [String] { all(content).compactMap { $0 as? NSTextField }.filter(visible).map(\.stringValue) }
        func check(_ value: @autoclosure () -> Bool, _ message: String) { guard value() else { fatalError(message) }; print("PASS: " + message) }
        func size() -> NSSize { window.contentRect(forFrameRect: window.frame).size }
        func display(_ id: UInt32, _ name: String, _ vendor: UInt32, _ model: UInt32, hz: Double?) -> DisplayReading {
            DisplayReading(id: id, name: name, builtin: false, vendor: vendor, model: model, logicalWidth: 1920,
                           logicalHeight: 1080, renderWidth: 3840, renderHeight: 2160, reportedRefreshHz: hz)
        }
        check(size() == NSSize(width: 520, height: 420), "native default content is 520x420")
        check(buttons().filter(visible).map(\.title).sorted() == ["刷新", "恢复双屏", "详细信息"].sorted(), "default has one main action and two small controls")
        check(!all(content).contains { $0 is NSScrollView }, "default diagnostics are not allocated")
        check(!texts().joined().contains("PipeIDs") && !texts().joined().contains("EDID"), "default has no raw diagnostic or instructional labels")

        // Two discovered externals: rows are built from the enumeration, not from fixed names.
        delegate.present(Snapshot(refreshedAt: "2026-10-18T00:00:00Z", displays: [
            display(1, "PANEL A", 0x1a2b, 0x3001, hz: 120), display(2, "PANEL B", 0x2b3c, 0x4002, hz: 120)], mappings: [], edids: [], errors: []))
        delegate.presentRecovery(["state": "already-healthy"])
        check(texts().filter { $0 == "在线 · 120 Hz" }.count == 2, "one concise online/Hz row per discovered external")
        check(texts().contains("PANEL A") && texts().contains("PANEL B"), "rows show the real display names")
        check(texts().joined().contains("外接显示器 2 台") && !texts().joined().contains("内屏"), "compact view reports only external count")
        check(texts().joined().contains("无需恢复"), "healthy state stays one calm line")
        check(button("撤销本次覆盖").isHidden && button("恢复双屏").isEnabled, "healthy state hides undo and keeps the guarded no-op action")

        // One external, then three: the layout follows the live count.
        delegate.present(Snapshot(refreshedAt: "x", displays: [display(1, "PANEL A", 0x1a2b, 0x3001, hz: 120)], mappings: [], edids: [], errors: []))
        check(texts().filter { $0 == "在线 · 120 Hz" }.count == 1 && size().height == 420, "one external renders one row at the compact height")
        delegate.present(Snapshot(refreshedAt: "x", displays: [
            display(1, "PANEL A", 0x1a2b, 0x3001, hz: 120), display(2, "PANEL B", 0x2b3c, 0x4002, hz: 120),
            display(3, "PANEL C", 0x5555, 0x6666, hz: 144)], mappings: [], edids: [], errors: []))
        check(texts().filter { $0.contains("在线 ·") }.count == 3 && size().height == 464, "three externals grow the window instead of hiding a row")
        delegate.present(Snapshot(refreshedAt: "x", displays: [], mappings: [], edids: [], errors: []))
        check(texts().contains("未检测到外接显示器") && size().height == 420, "zero externals are stated honestly")

        delegate.present(Snapshot(refreshedAt: "x", displays: [display(1, "PANEL A", 0x1a2b, 0x3001, hz: 120), display(2, "PANEL B", 0x2b3c, 0x4002, hz: 120)], mappings: [], edids: [], errors: []))
        button("详细信息").performClick(nil)
        check(size().height == 680 && texts().joined().contains("EDID") && buttons().contains { $0.title == "打开记录" }, "details disclosure creates scrollable diagnostics and records/help")
        check(button("确认实体双屏与 OSD").isHidden, "physical acceptance is hidden when not applicable")
        let optIn = buttons().first { $0.title.contains("允许无内屏回退写入") }
        check(optIn != nil && optIn!.state == .off, "the no-internal-fallback opt-in exists and is never pre-ticked")
        check(optIn!.title.contains("不保存"), "the opt-in says it is not persisted")
        button("详细信息").performClick(nil)
        check(size().height == 420 && !all(content).contains { $0 is NSScrollView }, "collapsing details releases views and restores compact geometry")

        // Countdown and automatic revert copy is what the user sees while writing.
        delegate.presentRecovery(["progress": "polling", "remainingSeconds": 17, "countdownSeconds": 20, "stableSamples": 1])
        check(texts().joined().contains("17") && texts().joined().contains("自动撤销") && !button("恢复双屏").isEnabled, "countdown is shown prominently and blocks a second action")
        delegate.presentRecovery(["state": "auto-reverted-verified"])
        check(texts().joined().contains("已自动撤销临时覆盖") && button("恢复双屏").isEnabled && button("撤销本次覆盖").isHidden, "an automatic revert is reported as a finished no-override state")

        delegate.presentRecovery(["state": "ready", "summary": "外接端口 2 个 · 目标：PANEL A（端口 DCPEXT1，双 Pipe）；缺失/无 Pipe 的对端端口：DCPEXT0",
                                  "analysis": ["orderVerified": false, "orderLabel": "首次使用该组合",
                                               "combinationDescription": "目标：PANEL A（端口 DCPEXT1，双 Pipe）",
                                               "countdownSeconds": 20, "internalOnline": false, "requiresNoInternalFallback": true,
                                               "target": ["name": "PANEL A", "port": "DCPEXT1"]]])
        check(texts().joined().contains("首次使用该组合"), "a first-use cable order carries the neutral label without blocking recovery")
        check(button("恢复双屏").isEnabled, "a first-use cable order stays recoverable with the normal confirmation")
        check(!texts().joined().contains("未验证") && !texts().joined().contains("实验性"), "no unverified or experimental wording reaches the interface")
        delegate.presentRecovery(["state": "ready", "summary": "外接端口 2 个 · 目标：PANEL B（端口 DCPEXT1，双 Pipe）",
                                  "analysis": ["orderVerified": true, "orderLabel": "接入顺序（本机已验证）",
                                               "countdownSeconds": 20, "internalOnline": true,
                                               "target": ["name": "PANEL B", "port": "DCPEXT1"]]])
        check(texts().joined().contains("接入顺序（本机已验证）"), "a recorded verified order shows the plain calm label")
        check(!texts().joined().contains("首次使用该组合"), "a recorded verified order is not labelled as a first use")
        delegate.presentRecovery(["state": "refused", "error": "占用双 Pipe 的目标 EDID 当前不可读（missing-data）：拒绝写入。"])
        check(!button("恢复双屏").isEnabled && texts().joined().contains("详细信息"), "a refusal directs to Details and blocks recovery")
        delegate.presentRecovery(["state": "recovery-needed", "error": "目标身份变化，已停止写入。"])
        check(!button("撤销本次覆盖").isHidden && button("撤销本次覆盖").isEnabled && !button("恢复双屏").isEnabled, "pending overlay prominently exposes only owned undo; recovery blocked")
        check(!texts().joined().contains("机盖") && texts().joined().contains("详细信息"), "pending state keeps lid-free action and directs to Details")
        delegate.presentRecovery(["state": "unsupported", "error": "未找到另一台外接显示器缺失/无 Pipe 的证据"])
        check(!button("恢复双屏").isEnabled && button("撤销本次覆盖").isHidden && texts().joined().contains("详细信息"), "unsupported state directs to the full fail-closed reason in Details")
        delegate.presentRecovery(["state": "cg-restored-reset-verified"])
        button("详细信息").performClick(nil)
        check(!button("确认实体双屏与 OSD").isHidden && button("确认实体双屏与 OSD").isEnabled, "physical confirmation remains available inside details after system recovery")
        button("详细信息").performClick(nil)
        content.layoutSubtreeIfNeeded()
        let visibleFrames = all(content).filter { visible($0) && ($0 is NSTextField || $0 is NSButton) }.map { $0.convert($0.bounds, to: content) }
        check(visibleFrames.allSatisfy { content.bounds.insetBy(dx: -1, dy: -1).contains($0) }, "compact recovered state controls stay inside content bounds")
        check(!all(content).compactMap { $0 as? NSTextField }.contains { $0.textColor == .systemOrange }, "no orange text in constructed interface")
        check(!texts().joined().contains("P275") && !texts().joined().contains("华为") && !texts().joined().contains("QSN"), "no hardcoded monitor names anywhere in the interface")
        print("UI_INTROSPECTION", String(data: try JSONSerialization.data(withJSONObject: ["contentWidth": size().width, "contentHeight": size().height, "visibleButtons": buttons().filter(visible).map(\.title), "visibleLabels": texts(), "testOnly": true], options: [.sortedKeys]), encoding: .utf8)!)
        print("PASS: 32 AppKit hierarchy checks (not screenshot or live GUI interaction acceptance)")
    }
}

private final class TestLanguagePreferences: UserDefaults {
    override func string(forKey key: String) -> String? { key == L10n.preferenceKey ? LanguageChoice.simplifiedChinese.rawValue : nil }
}
