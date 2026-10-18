import Foundation

/// Presentation of one backend recovery result. Copy that used to name specific monitors
/// now comes from the live analysis, and the countdown is the primary safety net: the
/// backend reverts a timed-out override by itself, so the user never has to click.
struct RecoveryPresentation {
    let title: String
    let detail: String
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
        orderLabel = analysis["orderLabel"] as? String ?? object["orderLabel"] as? String ?? ""
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
        switch state {
        case "already-healthy":
            title = displays.isEmpty ? "无需恢复" : displays + " · 无需恢复"
            detail = ""
        case "ready":
            title = orderVerified ? "发现可恢复的连接故障" : "发现可恢复的连接故障 · 未验证的接入顺序"
            detail = (summary.isEmpty ? "" : summary + "\n")
                + (orderLabel.isEmpty ? "" : "接入顺序：\(orderLabel)。\n")
                + (requiresNoInternalFallback ? "内屏未在线：写入需要在详细信息中主动选择“允许无内屏回退写入”。\n" : "")
                + "倒计时到点未取得稳定证据时会自动撤销临时覆盖。"
        case "refused":
            title = "已识别故障 · 当前拒绝写入"
            detail = error.isEmpty ? "请展开详细信息，查看具体拒绝原因。" : error
        case "dry-run":
            title = "方案已检查 · 未写入显示"
            detail = "已按本次实时身份保存备份与候选；真正恢复时会重新检查。"
        case "applying":
            title = "正在应用临时候选…"
            detail = (targetName.isEmpty ? "正在写入本次选中的单一外接服务。" : "正在写入本次选中的单一外接服务：\(targetName)（\(targetPort)）。")
                + "请勿拔线、合盖或退出。"
        case "polling":
            title = Presentation.countdown(remaining: object["remainingSeconds"] as? Int,
                                           total: object["countdownSeconds"] as? Int ?? countdownSeconds)
            detail = "到点未取得稳定双屏证据会自动撤销临时覆盖并核验原件，不需要你点击。请勿拔线、合盖或退出。"
        case "auto-reverting":
            title = "倒计时结束 · 正在自动撤销临时覆盖…"
            detail = "正在按本次运行记录核验原件字节；请勿操作。目标消失或身份变化时会保留未结束事务并停止写入。"
        case "auto-reverted-verified":
            title = "已自动撤销临时覆盖 · 原件已核验"
            detail = "系统读数已回到双屏且原件字节一致；请检查实体画面与 OSD。"
        case "auto-reverted-cg-not-restored":
            title = "已自动撤销临时覆盖 · 双屏未恢复"
            detail = error.isEmpty ? "原件字节已核验；系统仍未给出稳定双屏证据。可再次尝试或查看记录。" : error
        case "resetting":
            title = "双屏已上线 · 正在撤销覆盖…"
            detail = "正在核验原始数据，请稍候。"
        case "cg-restored-reset-verified":
            title = "系统双屏已恢复 · 覆盖已撤销"
            detail = "请检查实体画面及 OSD；可在详细信息中记录确认。"
        case "physical-accepted":
            title = "已记录实体双屏确认"
            detail = ""
        case "undo-verified":
            title = "覆盖已撤销 · 原件已核验"
            detail = "请检查画面；撤销不代表连接故障已解决。"
        case "recovery-needed":
            title = "需要处理 · 有未结束覆盖"
            detail = "自动撤销未能核验完成，未结束事务已保留。请保持机盖开启，使用“撤销本次覆盖”。" + (error.isEmpty ? "" : "\n" + error)
        case "unsupported":
            title = "当前连接不支持自动恢复"
            detail = error.isEmpty ? "请展开详细信息，查看支持范围。" : error
        case "reset-verified-cg-not-restored":
            title = "覆盖已撤销 · 双屏未保持"
            detail = "已停止自动操作，请查看记录。"
        default:
            title = "无法完成检查或操作"
            detail = error.isEmpty ? "请查看详细信息和记录，暂勿重复恢复。" : error
        }
    }
}
