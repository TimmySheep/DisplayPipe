import AppKit

@main struct CompactUITests {
    static func main() throws {
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
        check(size() == NSSize(width: 520, height: 420), "native default content is 520x420")
        check(buttons().filter(visible).map(\.title).sorted() == ["刷新", "恢复双屏", "详细信息"].sorted(), "default has one main action and two small controls")
        check(!all(content).contains { $0 is NSScrollView }, "default diagnostics are not allocated")
        check(!texts().joined().contains("PipeIDs") && !texts().joined().contains("EDID"), "default has no raw diagnostic or instructional labels")
        let a = DisplayReading(id: 1, name: "QSN-CAB", builtin: false, vendor: 0x22f6, model: 0x6346, logicalWidth: 1920, logicalHeight: 1080, renderWidth: 3840, renderHeight: 2160, reportedRefreshHz: 120)
        let b = DisplayReading(id: 2, name: "P275MV PLUS", builtin: false, vendor: 0x3103, model: 0x907d, logicalWidth: 1920, logicalHeight: 1080, renderWidth: 3840, renderHeight: 2160, reportedRefreshHz: 120)
        delegate.present(Snapshot(refreshedAt: "2026-10-18T00:00:00Z", displays: [a,b], mappings: [], edids: [], errors: []))
        delegate.presentRecovery(["state": "already-healthy"])
        check(texts().filter { $0 == "在线 · 120 Hz" }.count == 2 && texts().contains("双屏在线 · 无需恢复"), "two concise online/Hz rows and one calm state line")
        check(button("撤销本次覆盖").isHidden && button("恢复双屏").isEnabled, "healthy state hides undo and keeps guarded no-op action")
        button("详细信息").performClick(nil)
        check(size().height == 680 && texts().joined().contains("EDID") && buttons().contains { $0.title == "打开记录" }, "details disclosure creates scrollable diagnostics and records/help")
        check(button("确认实体双屏与 OSD").isHidden, "physical acceptance is hidden when not applicable")
        button("详细信息").performClick(nil)
        check(size().height == 420 && !all(content).contains { $0 is NSScrollView }, "collapsing details releases views and restores compact geometry")
        delegate.presentRecovery(["state":"recovery-needed", "error":"目标身份变化，已停止写入。"])
        check(!button("撤销本次覆盖").isHidden && button("撤销本次覆盖").isEnabled && !button("恢复双屏").isEnabled, "pending overlay prominently exposes only owned undo; recovery blocked")
        check(texts().joined().contains("机盖") && texts().joined().contains("身份变化"), "pending state retains concise action and failure reason")
        delegate.presentRecovery(["state":"unsupported", "error":"华为先接尚未验证"])
        check(!button("恢复双屏").isEnabled && button("撤销本次覆盖").isHidden && texts().contains("华为先接尚未验证"), "unsupported state explains fail-closed without undo")
        delegate.presentRecovery(["state":"cg-restored-reset-verified"])
        button("详细信息").performClick(nil)
        check(!button("确认实体双屏与 OSD").isHidden && button("确认实体双屏与 OSD").isEnabled, "physical confirmation remains available inside details after system recovery")
        button("详细信息").performClick(nil)
        content.layoutSubtreeIfNeeded()
        let visibleFrames = all(content).filter { visible($0) && ($0 is NSTextField || $0 is NSButton) }.map { $0.convert($0.bounds, to: content) }
        check(visibleFrames.allSatisfy { content.bounds.insetBy(dx: -1, dy: -1).contains($0) }, "compact recovered state controls stay inside content bounds")
        check(!all(content).compactMap { $0 as? NSTextField }.contains { $0.textColor == .systemOrange }, "no orange text in constructed interface")
        print("UI_INTROSPECTION", String(data: try JSONSerialization.data(withJSONObject: ["contentWidth": size().width, "contentHeight": size().height, "visibleButtons": buttons().filter(visible).map(\.title), "visibleLabels": texts(), "testOnly": true], options: [.sortedKeys]), encoding: .utf8)!)
        print("PASS: 15 AppKit hierarchy checks (not screenshot or live GUI interaction acceptance)")
    }
}
