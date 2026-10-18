import AppKit

final class MemoryPreferences: UserDefaults {
    var values: [String: Any] = [:]
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    override func set(_ value: Bool, forKey key: String) { values[key] = value }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
}
@main struct LocalizationTests {
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ reason: String) {
        guard condition() else { fatalError(reason) }; count += 1; print("PASS: " + reason)
    }
    static func main() {
        _ = NSApplication.shared
        let prefs = MemoryPreferences()
        L10n.preferences = prefs
        L10n.systemLanguages = { ["fr-FR"] }
        check(L10n.language == .english, "other system languages fall back to English")
        for language in ["zh", "zh-Hans", "zh-Hans-CN", "zh-Hant-TW", "zh-CN", "zh-SG"] {
            L10n.systemLanguages = { [language] }
            check(L10n.language == .simplifiedChinese, "system \(language) selects Simplified Chinese")
        }
        L10n.systemLanguages = { [] }
        check(L10n.language == .english, "empty system languages fall back to English")
        prefs.values[L10n.preferenceKey] = "unrecognized"
        check(L10n.choice == .system, "unknown saved preference uses system")
        check(L10n.text("Uncatalogued English fallback") == "Uncatalogued English fallback", "missing translation has English fallback")
        check(L10n.text("External displays: {0}", "{1} 内屏 /Users/raw") == "External displays: {1} 内屏 /Users/raw", "dynamic arguments are never translated or recursively interpolated")
        for (english, chinese) in L10n.catalog {
            let pattern = try! NSRegularExpression(pattern: #"\{[0-9]+\}"#)
            func tokens(_ text: String) -> [String] { pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).map { (text as NSString).substring(with: $0.range) }.sorted() }
            check(tokens(english) == tokens(chinese), "catalog interpolation parity: \(english)")
        }
        let delegate = AppDelegate(collect: { _ in fatalError("language switching must not collect") }, run: { _, _ in fatalError("language switching must not run any backend command or setter") }, preferences: prefs)
        delegate.buildWindow()
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        func visible(_ view: NSView) -> Bool { !view.isHidden && (view.superview.map(visible) ?? true) }
        func texts() -> String { all(delegate.window.contentView!).filter(visible).compactMap { ($0 as? NSTextField)?.stringValue }.joined(separator: "\n") }
        func buttons() -> [NSButton] { all(delegate.window.contentView!).compactMap { $0 as? NSButton } }
        let names = ["内屏 PANEL internal display", "机盖 lid PANEL", "English 中文 /DCPEXT0", "未知显示器 — raw {1}"]
        let snapshot = Snapshot(refreshedAt: "2026-10-18T00:00:00Z", displays: names.enumerated().map { index, name in
            DisplayReading(id: UInt32(index + 1), name: name, builtin: false, vendor: UInt32(index + 1), model: 9, logicalWidth: 1920, logicalHeight: 1080, renderWidth: 3840, renderHeight: 2160, reportedRefreshHz: 120)
        }, mappings: [], edids: [], errors: [])
        delegate.present(snapshot)
        let unsafe = "内屏 internal display; 机盖 open lid closed lid; EDID missing-data /Users/demo/DCPEXT1"
        let states = ["already-healthy", "ready", "refused", "dry-run", "applying", "polling", "auto-reverting", "auto-reverted-verified", "auto-reverted-cg-not-restored", "resetting", "cg-restored-reset-verified", "physical-accepted", "undo-verified", "recovery-needed", "unsupported", "reset-verified-cg-not-restored", "failure", "unknown-future-state"]
        for choice in [LanguageChoice.english, .simplifiedChinese] {
            delegate.selectLanguage(choice)
            let missing = RecoveryClient.missingInterpreter(ordered: ["/unchanged/路径/python3"], overridden: true).localizedDescription
            check(missing.contains("/unchanged/路径/python3") && missing.contains("DISPLAYPIPE_PYTHON") && missing.contains(choice == .english ? "No display writes occurred" : "未写入显示"), "dependency errors are localized and preserve paths")
            for state in states {
                let object: [String: Any] = ["state": state, "summary": unsafe, "error": unsafe, "pending": [["error": unsafe]], "remainingSeconds": 17, "analysis": ["requiresNoInternalFallback": true, "target": ["name": names[0], "port": "DCPEXT1"]]]
                let presentation = RecoveryPresentation(object, displays: unsafe)
                check(!["内屏", "机盖", "internal", "lid"].contains { (presentation.title + presentation.detail).lowercased().contains($0) }, "\(choice)/\(state) uses structured lid-free home copy")
                check(presentation.technicalDetail.contains(unsafe) && presentation.requiresNoInternalFallback, "\(choice)/\(state) keeps full diagnostic and unchanged gate")
                if choice == .english { check(presentation.title.unicodeScalars.allSatisfy { !(0x4e00...0x9fff).contains($0.value) }, "English state title has no untranslated UI prose: \(presentation.title), language \(L10n.language)") }
                delegate.presentRecovery(object)
                let content = delegate.window.contentView!
                content.layoutSubtreeIfNeeded()
                let frames = all(content).filter { visible($0) && ($0 is NSTextField || $0 is NSButton) }.map { $0.convert($0.bounds, to: content) }
                check(frames.allSatisfy { content.bounds.insetBy(dx: -1, dy: -1).contains($0) }, "\(choice)/\(state) home controls fit native content bounds")
                check(names.allSatisfy { texts().contains($0) }, "\(choice)/\(state) preserves all dynamic names verbatim")
            }
            let detailTitle = L10n.text("Details")
            buttons().first { $0.title == detailTitle }!.performClick(nil)
            check(texts().contains(unsafe) && texts().contains(L10n.text("Raw technical diagnostics (original language)")), "Details labels full raw untranslated diagnostics honestly")
            let checkbox = buttons().first { $0.title == L10n.text("Allow writes without internal fallback (remembered)") }!
            check(checkbox.state == .off, "no-fallback remains default-off")
            checkbox.performClick(nil)
            let selector = all(delegate.window.contentView!).compactMap { $0 as? NSPopUpButton }.first!
            check(selector.numberOfItems == 3, "Details offers System/English/简体中文")
            selector.selectItem(at: LanguageChoice.allCases.firstIndex(of: choice == .english ? .simplifiedChinese : .english)!)
            NSApp.sendAction(selector.action!, to: selector.target, from: selector)
            check(buttons().contains { $0.title == L10n.text("Refresh") }, "native selector immediately relocalizes controls")
            check(checkbox.state == .on, "language change preserves remembered permission")
            checkbox.performClick(nil)
            buttons().first { $0.title == L10n.text("Details") }!.performClick(nil)
            check(!texts().contains(unsafe), "collapsing Details keeps diagnostic off home")
        }
        for choice in [LanguageChoice.english, .simplifiedChinese] {
            delegate.selectLanguage(choice)
            for number in 1...4 {
                delegate.present(Snapshot(refreshedAt: "x", displays: Array(snapshot.displays.prefix(number)), mappings: [], edids: [], errors: [unsafe]))
                check(names.prefix(number).allSatisfy { texts().contains($0) }, "dynamic 1..N display names survive relocalization")
                check(!texts().contains(unsafe), "collection error is not exposed on home")
            }
        }
        delegate.selectLanguage(.english)
        check(Set(prefs.values.keys) == [L10n.preferenceKey, AppDelegate.noFallbackPreferenceKey], "only language and explicit opt-in preferences are persisted")
        check(L10n.text("Refresh") == "Refresh", "switching immediately updates English UI")
        check(L10n.catalog.values.allSatisfy { !$0.isEmpty } && L10n.catalog.count > 40, "central bilingual catalog has nonempty translations")
        print("PASS: \(count) localization checks; no collector, backend or setter executed")
    }
}
