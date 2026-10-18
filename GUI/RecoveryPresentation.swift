import Foundation
struct RecoveryPresentation {
 let title: String
 let detail: String
 let canRecover: Bool
 let canUndo: Bool
 let canAcceptPhysical: Bool
 let physicalAccepted: Bool
 init(_ object: [String: Any]) {
  let state = object["state"] as? String ?? object["progress"] as? String ?? "failure"
  canRecover = ["already-healthy", "ready", "dry-run", "undo-verified", "cg-restored-reset-verified", "physical-accepted", "reset-verified-cg-not-restored"].contains(state)
  canUndo = state == "recovery-needed"
  canAcceptPhysical = state == "cg-restored-reset-verified"
  physicalAccepted = state == "physical-accepted" && object["physicalInputConfirmed"] as? Bool == true
  let pending = object["pending"] as? [[String: Any]] ?? []
  let error = (object["error"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? pending.first?["error"] as? String ?? ""
  switch state {
  case "already-healthy": title = "双屏在线 · 无需恢复"; detail = ""
  case "ready": title = "发现可恢复的连接故障"; detail = "P275 在线，华为未上线。可尝试恢复双屏。"
  case "dry-run": title = "方案已检查 · 未写入显示"; detail = "已保存备份；恢复时会重新检查目标。"
  case "applying": title = "正在尝试恢复…"; detail = "正在应用临时120Hz候选。请勿拔线或合盖。"
  case "polling": title = "等待双屏上线 · \(object["remainingSeconds"] ?? 20) 秒"; detail = "正在核对系统读数（\(object["stableSamples"] ?? 0) / 3）。请勿拔线或合盖。"
  case "resetting": title = "双屏已上线 · 正在撤销覆盖…"; detail = "正在核验原始数据，请稍候。"
  case "cg-restored-reset-verified": title = "系统双屏已恢复 · 覆盖已撤销"; detail = "请检查实体画面及 OSD；可在详细信息中记录确认。"
  case "physical-accepted": title = "已记录实体双屏确认"; detail = ""
  case "undo-verified": title = "覆盖已撤销 · 原件已核验"; detail = "请检查画面；撤销不代表连接故障已解决。"
  case "recovery-needed": title = "需要处理 · 有未结束覆盖"; detail = "请保持机盖开启，使用“撤销本次覆盖”。" + (error.isEmpty ? "" : "\n" + error)
  case "unsupported": title = "当前连接不支持自动恢复"; detail = error.isEmpty ? "请展开详细信息，查看支持范围。" : error
  case "reset-verified-cg-not-restored": title = "覆盖已撤销 · 双屏未保持"; detail = "已停止自动操作，请查看记录。"
  default: title = "无法完成检查或操作"; detail = error.isEmpty ? "请查看详细信息和记录，暂勿重复恢复。" : error
  }
 }
}
