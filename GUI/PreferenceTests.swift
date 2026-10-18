import AppKit

@main struct PreferenceTests {
    static let key = "DisplayPipe.allowWritesWithoutInternalFallback"
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        guard value() else { fatalError(message) }; count += 1; print("PASS: " + message)
    }
    static func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
    static func buttons(_ delegate: AppDelegate) -> [NSButton] { all(delegate.window.contentView!).compactMap { $0 as? NSButton } }
    static func details(_ delegate: AppDelegate) { buttons(delegate).first { $0.title == L10n.text("Details") }!.performClick(nil) }
    static func checkbox(_ delegate: AppDelegate) -> NSButton {
        buttons(delegate).first { $0.title.hasPrefix("Allow writes without internal fallback") || $0.title.hasPrefix("允许无内屏回退写入") }!
    }
    static func main() {
        _ = NSApplication.shared
        let suite = "DisplayPipe.PreferenceTests." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        L10n.preferences = preferences
        L10n.select(.english)
        preferences.set(true, forKey: key)
        check(preferences.bool(forKey: key), "isolated app preferences contain stored true")
        let delegate = AppDelegate(collect: { _ in fatalError("preference load must not collect") }, run: { _, _ in fatalError("preference load must not run backend/setter") }, preferences: preferences)
        delegate.buildWindow(); details(delegate)
        check(checkbox(delegate).state == .on, "new delegate loads saved true into the actual checkbox")
        func fresh() -> AppDelegate {
            let result = AppDelegate(collect: { _ in fatalError("preferences must not collect") }, run: { _, _ in fatalError("preferences must not run backend/setter") }, preferences: preferences)
            result.buildWindow(); return result
        }
        preferences.removeObject(forKey: key)
        let defaultOff = fresh()
        check(!buttons(defaultOff).contains { $0.title.hasPrefix("Allow writes without internal fallback") }, "permission stays out of the home page")
        details(defaultOff)
        check(checkbox(defaultOff).state == .off && preferences.object(forKey: key) == nil, "absent key defaults false without saving consent")
        checkbox(defaultOff).performClick(nil)
        check(preferences.bool(forKey: key), "checking saves true in the dedicated preference")
        let restarted = fresh(); details(restarted)
        check(checkbox(restarted).state == .on, "another delegate restores the checked state after restart")
        checkbox(restarted).performClick(nil)
        check(preferences.object(forKey: key) as? Bool == false, "unchecking explicitly persists false")
        let disabled = fresh(); details(disabled)
        check(checkbox(disabled).state == .off, "another delegate restores unchecked false")
        for language in [LanguageChoice.english, .simplifiedChinese] {
            disabled.selectLanguage(language)
            let control = checkbox(disabled)
            check(control.title == (language == .english ? "Allow writes without internal fallback (remembered)" : "允许无内屏回退写入（记住此选择）"), "\(language) plainly says permission is remembered")
            control.performClick(nil)
            disabled.selectLanguage(language == .english ? .simplifiedChinese : .english)
            check(control.state == .on && preferences.bool(forKey: key), "language change preserves saved true without collecting or running backend")
            details(disabled); details(disabled)
            check(checkbox(disabled).state == .on, "collapsing and reopening Details preserves checked permission")
            disabled.present(Snapshot(refreshedAt: "refresh", displays: [], mappings: [], edids: [], errors: []))
            disabled.presentRecovery(["state": "ready", "analysis": ["requiresNoInternalFallback": true, "countdownSeconds": 20]])
            check(checkbox(disabled).state == .on && preferences.bool(forKey: key), "refresh/status presentation preserves permission and countdown state")
            checkbox(disabled).performClick(nil)
        }
        let needsPermission: [String: Any] = ["state": "ready", "analysis": ["requiresNoInternalFallback": true, "countdownSeconds": 20]]
        disabled.presentRecovery(needsPermission)
        check(disabled.recoveryCommand() == nil, "saved false refuses the no-fallback explicit action")
        checkbox(disabled).performClick(nil)
        check(disabled.recoveryCommand() == ["recover", "--execute", "--confirm-private-api-risk", "--ack-no-internal-fallback"], "saved true adds only the explicit action flag, preserving risk confirmation")
        details(disabled)
        check(disabled.recoveryCommand()?.contains("--ack-no-internal-fallback") == true, "saved true remains effective with Details collapsed")
        disabled.presentRecovery(["state": "ready", "analysis": ["requiresNoInternalFallback": false]])
        check(disabled.recoveryCommand() == ["recover", "--execute", "--confirm-private-api-risk"], "an online internal fallback needs no opt-in command flag")
        check(Set(preferences.persistentDomain(forName: suite)!.keys) == [key, L10n.preferenceKey], "only opt-in and language persist, never target, EDID or pending authorization")
        print("PASS: \(count) preference checks; no collector, backend or setter executed")
    }
}
