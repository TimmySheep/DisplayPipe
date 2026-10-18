import Foundation

enum TargetState: String, Codable { case online, missing, unknown, ambiguous }
struct TargetCard: Encodable {
    let name: String
    let vendor: UInt32
    let model: UInt32
    let state: TargetState
    let display: DisplayReading?
    var stateText: String {
        switch state {
        case .online: return "系统在线"
        case .missing: return "目标未上线"
        case .unknown: return "无法确认（枚举失败）"
        case .ambiguous: return "身份不唯一，不能确认"
        }
    }
}
extension Snapshot {
    static let recoveryNotice = "恢复与撤销：未验证，不可用。尚未接入已验收后端；无显示写入操作。"
    func targetDetails(_ card: TargetCard) -> String {
        var lines = [card.stateText, String(format: "vendor=0x%04x · model=0x%04x", card.vendor, card.model)]
        if let d = card.display {
            lines += ["CG ID \(d.id) · \(d.name)", "逻辑 \(Presentation.dimensions(d.logicalWidth, d.logicalHeight)) · 渲染 \(Presentation.dimensions(d.renderWidth, d.renderHeight))", "系统报告刷新率 \(Presentation.refreshRate(d.reportedRefreshHz))"]
        } else { lines.append("系统在线模式：未提供；不显示虚构的尺寸或刷新率") }
        lines.append("EDID 可读不等于系统在线；Pipe 与 CG 不强行配对。")
        return lines.joined(separator: "\n")
    }
    var pipeDetails: String {
        let rows = mappings.map { "\($0.name) / \($0.role)\nPipeIDs=\($0.pipeIDs) · MaxPipes=\($0.maxPipes.map(String.init) ?? "未知")（能力上限，非占用）" }
        return ([DiagnosticCore.status(mappings)] + rows + ["Pipe 映射不是链路在线证据；空 PipeIDs 表示该记录未列出分配，不据此推断端口状态。"]).joined(separator: "\n\n")
    }
    var edidDetails: String {
        let rows = edids.map { "service=\($0.serviceID) · vendor=\($0.vendor) model=\($0.model)\n\($0.byteCount) 字节 · 长度/校验：\($0.valid ? "通过" : "不通过")" }
        return ((rows.isEmpty ? ["未读取到 EDID 记录（未知，不视为校验通过）"] : rows) + ["校验仅检查长度与 checksum，不证明所有时序安全或当前实际输入。EDID service 与 CG/Pipe 未强行关联。"]).joined(separator: "\n\n")
    }
    var targetCards: [TargetCard] {
        let targets: [(String, UInt32, UInt32)] = [("HWV QSN-CAB", 0x22f6, 0x6346), ("P275MV PLUS", 0x3103, 0x907d)]
        return targets.map { name, vendor, model in
            let matches = displays.filter { !$0.builtin && $0.vendor == vendor && $0.model == model }
            let failed = errors.contains { $0.hasPrefix("CoreGraphics") }
            let state: TargetState = failed ? .unknown : matches.count > 1 ? .ambiguous : matches.isEmpty ? .missing : .online
            return TargetCard(name: name, vendor: vendor, model: model, state: state, display: matches.count == 1 ? matches[0] : nil)
        }
    }
    var hardwareSummary: String {
        let cards = targetCards
        if cards.contains(where: { $0.state == .unknown || $0.state == .ambiguous }) { return "目标硬件：无法确认；请检查采集与身份" }
        let count = cards.filter { $0.state == .online }.count
        return count == 2 ? "目标系统在线 2 / 2（不等于实际输入或恢复成功）" : "目标系统在线 \(count) / 2 · 有目标未上线"
    }
    var collectionSummary: String { errors.isEmpty ? "采集完成（不代表预期双屏在线）" : "采集不完整：\(errors.joined(separator: "；"))" }
}
enum Presentation {
    static func dimensions(_ width: Int?, _ height: Int?) -> String {
        guard let w = width, let h = height, w > 0, h > 0 else { return "未知" }
        return "\(w)×\(h)"
    }
    static func refreshRate(_ value: Double?) -> String {
        guard let value = value else { return "未知" }
        return value > 0 && value.isFinite ? String(format: "%.2f Hz", value) : "未知 / 可变（API 未给出固定值）"
    }
    static func beijingTime(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return "时间未知（\(value)）" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date) + " 北京时间 UTC+8"
    }
}
