import Foundation

/// Presentation of one backend recovery result. Copy that used to name specific monitors
/// now comes from the live analysis, and the countdown is the primary safety net: the
/// backend reverts a timed-out override by itself, so the user never has to click.
struct RecoveryPresentation {
    let title: String
    let detail: String
    let technicalDetail: String
    let canRecover: Bool
    let canUndo: Bool
    let canAcceptPhysical: Bool
    let physicalAccepted: Bool
    let orderVerified: Bool
    let orderLabel: String
    let combinationDescription: String
    let requiresNoInternalFallback: Bool
    let countdownSeconds: Int
    let targetName: String
    let targetPort: String

    init(_ object: [String: Any], displays: String = "") {
        let state = object["state"] as? String ?? object["progress"] as? String ?? "failure"
        let analysis = object["analysis"] as? [String: Any] ?? [:]
        let target = analysis["target"] as? [String: Any] ?? [:]
        orderVerified = (analysis["orderVerified"] as? Bool) ?? (object["orderVerified"] as? Bool) ?? false
        orderLabel = (analysis["orderLabel"] ?? object["orderLabel"]) == nil ? "" : (orderVerified ? L10n.text("Connection order (verified on this Mac)") : L10n.text("First use of this combination"))
        combinationDescription = analysis["combinationDescription"] as? String ?? object["combinationDescription"] as? String ?? ""
        requiresNoInternalFallback = (analysis["requiresNoInternalFallback"] as? Bool) ?? false
        countdownSeconds = (analysis["countdownSeconds"] as? Int) ?? (object["countdownSeconds"] as? Int) ?? 20
        targetName = target["name"] as? String ?? object["targetName"] as? String ?? ""
        targetPort = target["port"] as? String ?? object["targetPort"] as? String ?? ""
        canRecover = ["already-healthy", "ready", "dry-run", "undo-verified", "cg-restored-reset-verified",
                      "physical-accepted", "reset-verified-cg-not-restored", "auto-reverted-verified",
                      "auto-reverted-cg-not-restored"].contains(state)
        canUndo = state == "recovery-needed"
        canAcceptPhysical = state == "cg-restored-reset-verified"
        physicalAccepted = state == "physical-accepted" && object["physicalInputConfirmed"] as? Bool == true
        let pending = object["pending"] as? [[String: Any]] ?? []
        let summary = object["summary"] as? String ?? ""
        let error = (object["error"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (state == "ready" && !summary.isEmpty ? summary : nil)
            ?? pending.first?["error"] as? String ?? ""
        technicalDetail = [summary, error, requiresNoInternalFallback ? L10n.text("The internal display is offline: explicitly select the no-internal-fallback permission in Details. Opening the lid may change service identity. Unverifiable countdown undo retains a pending transaction.") : ""].filter { !$0.isEmpty }.joined(separator: "\n")
        switch state {
        case "already-healthy":
            title = L10n.text("No recovery needed"); detail = ""
        case "ready":
            title = L10n.text("Recoverable connection fault detected")
            detail = (orderLabel.isEmpty ? "" : orderLabel + "\n") + L10n.text("The countdown automatically attempts undo if no stable evidence arrives. Review Details before recovering.")
        case "refused":
            title = L10n.text("Fault detected · Write refused"); detail = L10n.text("See Details for the exact refusal reason.")
        case "dry-run":
            title = L10n.text("Plan checked · No display writes"); detail = L10n.text("Backup and candidate saved for the current identity. Recovery checks again before applying.")
        case "applying":
            title = L10n.text("Applying temporary candidate…"); detail = L10n.text("Do not unplug or quit.")
        case "polling":
            title = Presentation.countdown(remaining: object["remainingSeconds"] as? Int, total: object["countdownSeconds"] as? Int ?? countdownSeconds)
            detail = L10n.text("At the deadline, undo is attempted and original bytes verified automatically; no click is needed. Do not unplug or quit.")
        case "auto-reverting":
            title = L10n.text("Countdown ended · Automatically undoing…"); detail = L10n.text("Verifying original bytes. Uncertain identity or readback retains a pending transaction. Please wait.")
        case "auto-reverted-verified":
            title = L10n.text("Automatically undone · Original verified"); detail = L10n.text("System readings show both displays and original bytes match. Check the physical image and OSD.")
        case "auto-reverted-cg-not-restored":
            title = L10n.text("Automatically undone · Displays not restored"); detail = L10n.text("No stable dual-display evidence. See Details.")
        case "resetting":
            title = L10n.text("Both displays online · Undoing override…"); detail = L10n.text("Verifying original data. Please wait.")
        case "cg-restored-reset-verified":
            title = L10n.text("System displays restored · Override removed"); detail = L10n.text("Check the physical image and OSD; record confirmation in Details.")
        case "physical-accepted":
            title = L10n.text("Physical display confirmation recorded"); detail = ""
        case "undo-verified":
            title = L10n.text("Override removed · Original verified"); detail = L10n.text("Check the image. Undo does not mean the connection fault was fixed.")
        case "recovery-needed":
            title = L10n.text("Action required · Pending override"); detail = L10n.text("Automatic undo could not be verified. Use Undo This Override and see Details.")
        case "unsupported":
            title = L10n.text("Automatic recovery unavailable"); detail = L10n.text("See Details for the supported scope and exact reason.")
        case "reset-verified-cg-not-restored":
            title = L10n.text("Override removed · Displays did not stay online"); detail = L10n.text("Automatic operations stopped. See Details.")
        default:
            title = L10n.text("Unable to complete check or operation"); detail = L10n.text("See Details and records before retrying recovery.")
        }
    }
}
