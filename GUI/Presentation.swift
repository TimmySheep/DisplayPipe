import Foundation

enum DisplayState: String, Codable { case online, offline, unreadable, unknown, ambiguous }

/// One row per physical external display discovered at runtime. Names are resolved from the
/// display itself (EDID 0xFC name, then CoreGraphics localizedName, then vendor:model), and
/// anything unreadable is reported honestly instead of being hidden. Row count follows the
/// live enumeration, so one, two or more externals are all shown without a fixed layout.
struct DisplayCard: Encodable {
    let name: String
    let nameSource: String
    let online: Bool
    let builtin: Bool
    let vendor: UInt32?
    let model: UInt32?
    let reportedRefreshHz: Double?
    let logicalWidth: Int?
    let logicalHeight: Int?
    let renderWidth: Int?
    let renderHeight: Int?
    let port: String?
    let pipeIDs: [Int]
    let maxPipes: Int?
    let edidServiceID: String?
    let edidBytes: Int?
    let edidValid: Bool?
    let state: DisplayState
    let stateText: String
    let detail: String
}

extension Snapshot {
    static let recoveryNotice = "恢复与撤销由本机后端按实时身份执行；健康状态不写入。"
    var externalDisplays: [DisplayReading] { displays.filter { !$0.builtin } }
    var internalDisplays: [DisplayReading] { displays.filter { $0.builtin } }
    var coreGraphicsFailed: Bool { errors.contains { $0.hasPrefix("CoreGraphics") } }

    func readings(vendor: UInt32, model: UInt32) -> [EDIDReading] {
        edids.filter { $0.vendorNumber == vendor && $0.modelNumber == model }
    }
    /// Crossbar rows are joined to a display by its own name, never by row order.
    func mapping(named name: String?) -> PipeMapping? {
        guard let name = name, !name.isEmpty else { return nil }
        return mappings.first { $0.name == name }
    }
    static func vendorModel(_ vendor: UInt32?, _ model: UInt32?) -> String {
        guard let vendor = vendor, let model = model, vendor != 0 || model != 0 else { return L10n.text("Unknown identity") }
        return String(format: "0x%04x:0x%04x", vendor, model)
    }
    static func pipeText(_ pipeIDs: [Int], _ maxPipes: Int?) -> String {
        let capacity = maxPipes.map(String.init) ?? "未知"
        return pipeIDs.isEmpty ? "PipeIDs=[] · MaxPipes=\(capacity)（未列出分配）" : "PipeIDs=\(pipeIDs) · MaxPipes=\(capacity)（容量，非占用）"
    }

    var internalSummary: String {
        guard let display = internalDisplays.first else { return "内屏：未在线（无内屏回退）" }
        return "内屏：在线（\(Presentation.dimensions(display.logicalWidth, display.logicalHeight))）"
    }
    var hardwareSummary: String {
        if coreGraphicsFailed { return "外接显示器：无法确认（CoreGraphics 枚举失败）· " + internalSummary }
        if externalDisplays.isEmpty { return "未检测到外接显示器 · " + internalSummary }
        return "外接显示器 \(externalDisplays.count) 台 · 系统在线 \(externalDisplays.count) · " + internalSummary
    }
    var collectionSummary: String { errors.isEmpty ? "采集完成（不代表预期双屏在线）" : "采集不完整：\(errors.joined(separator: "；"))" }

    var externalCards: [DisplayCard] {
        var cards: [DisplayCard] = []
        var matched: Set<String> = []
        for display in externalDisplays {
            let displayReadings = readings(vendor: display.vendor, model: display.model)
            for reading in displayReadings { matched.insert("\(reading.serviceID)@\(display.vendor):\(display.model)") }
            cards.append(card(for: display, readings: displayReadings))
        }
        // External EDID services whose display is not currently online still get an honest row.
        for reading in edids {
            let key = "\(reading.serviceID)@\(reading.vendorNumber ?? 0):\(reading.modelNumber ?? 0)"
            if matched.contains(key) { continue }
            if reading.serviceID.isEmpty { continue }
            cards.append(serviceCard(for: reading))
        }
        return cards
    }

    private func card(for display: DisplayReading, readings displayReadings: [EDIDReading]) -> DisplayCard {
        let names = Set(displayReadings.compactMap { $0.name })
        let displayName = display.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var name = L10n.text("Unnamed external display")
        var source = "none"
        if let edidName = names.count == 1 ? names.first : nil, !edidName.isEmpty {
            name = edidName; source = "edid"
        } else if !displayName.isEmpty {
            name = displayName; source = "coregraphics"
        } else if display.vendor != 0 || display.model != 0 {
            name = Snapshot.vendorModel(display.vendor, display.model); source = "vendor-model"
        }
        let mapping = self.mapping(named: name) ?? self.mapping(named: displayName)
        if displayReadings.count > 1 { source = "coregraphics" }
        let ambiguous = displayReadings.count > 1 && names.count > 1
        let reported = displayReadings.first
        let state: DisplayState = coreGraphicsFailed ? .unknown : (ambiguous ? .ambiguous : .online)
        var stateText: String
        if coreGraphicsFailed {
            stateText = L10n.text("Unknown (enumeration failed)")
        } else if ambiguous {
            stateText = L10n.text("Ambiguous identity; name unconfirmed")
        } else {
            let rate = display.reportedRefreshHz.flatMap { $0.isFinite && $0 > 0 ? String(format: " · %.0f Hz", $0) : nil } ?? L10n.text(" · Refresh rate unknown")
            stateText = L10n.text("Online") + rate
        }
        let port = mapping?.role
        let title = state == .online ? name : name + (port.map { "（\($0)）" } ?? "")
        return DisplayCard(
            name: title, nameSource: source, online: state == .online, builtin: false,
            vendor: display.vendor, model: display.model, reportedRefreshHz: display.reportedRefreshHz,
            logicalWidth: display.logicalWidth, logicalHeight: display.logicalHeight,
            renderWidth: display.renderWidth, renderHeight: display.renderHeight,
            port: port, pipeIDs: mapping?.pipeIDs ?? [], maxPipes: mapping?.maxPipes,
            edidServiceID: reported?.serviceID, edidBytes: reported?.byteCount, edidValid: reported?.valid,
            state: state, stateText: stateText,
            detail: Snapshot.onlineDetail(display: display, mapping: mapping, readings: displayReadings, source: source))
    }

    private func serviceCard(for reading: EDIDReading) -> DisplayCard {
        let broken = !reading.valid || reading.byteCount < 128
        let name = reading.name ?? (broken ? L10n.text("Unnamed external service") : Snapshot.vendorModel(reading.vendorNumber, reading.modelNumber))
        let mapping = self.mapping(named: reading.name)
        let port = mapping?.role
        let state: DisplayState = coreGraphicsFailed ? .unknown : (broken ? .unreadable : .offline)
        let stateText: String
        if coreGraphicsFailed { stateText = L10n.text("Unknown (enumeration failed)") }
        else if broken { stateText = L10n.text("Connected · EDID unreadable (possibly no signal)") }
        else if reading.named { stateText = L10n.text("Connected · Offline (no signal / no Pipe)") }
        else { stateText = L10n.text("Connected · Offline (name unreadable)") }
        var lines = ["状态：\(stateText)"]
        if let mapping = mapping { lines.append("端口 \(mapping.role) · " + Snapshot.pipeText(mapping.pipeIDs, mapping.maxPipes)) }
        lines.append("EDID service=\(reading.serviceID) · \(reading.byteCount) 字节 · 长度/校验：\(reading.valid ? "通过" : "不通过")")
        lines.append("名称来源：\(reading.named ? "EDID 描述符 0xFC" : "无法读取（0xFC 缺失或不可解码）")")
        lines.append("EDID 可读不等于系统在线；Pipe 与 CG 不强行配对。")
        return DisplayCard(
            name: name + (port.map { "（\($0)）" } ?? ""), nameSource: reading.name == nil ? "vendor-model" : "edid",
            online: false, builtin: false, vendor: reading.vendorNumber, model: reading.modelNumber,
            reportedRefreshHz: nil, logicalWidth: nil, logicalHeight: nil, renderWidth: nil, renderHeight: nil,
            port: port, pipeIDs: mapping?.pipeIDs ?? [], maxPipes: mapping?.maxPipes,
            edidServiceID: reading.serviceID, edidBytes: reading.byteCount, edidValid: reading.valid,
            state: state, stateText: stateText, detail: lines.joined(separator: "\n"))
    }

    static func onlineDetail(display: DisplayReading, mapping: PipeMapping?, readings: [EDIDReading], source: String) -> String {
        var lines = ["状态：CoreGraphics 在线（不代表实体输入或恢复成功）",
                     "身份：\(vendorModel(display.vendor, display.model)) · CG ID \(display.id)",
                     "逻辑 \(Presentation.dimensions(display.logicalWidth, display.logicalHeight)) · 渲染 \(Presentation.dimensions(display.renderWidth, display.renderHeight))",
                     "系统报告刷新率 \(Presentation.refreshRate(display.reportedRefreshHz))",
                     "名称来源：\(source == "edid" ? "EDID 描述符 0xFC" : source == "coregraphics" ? "CoreGraphics 名称" : source == "vendor-model" ? "vendor:model 回退" : "无可用名称")"]
        if let mapping = mapping {
            lines.append("端口 \(mapping.role) · " + pipeText(mapping.pipeIDs, mapping.maxPipes))
        } else {
            lines.append("未匹配到 Pipe 映射记录；不以行序猜测端口")
        }
        if let reading = readings.first {
            lines.append("EDID service=\(reading.serviceID) · \(reading.byteCount) 字节 · 长度/校验：\(reading.valid ? "通过" : "不通过")")
        } else {
            lines.append("EDID：未读取到该身份记录（未知，不视为校验通过）")
        }
        lines.append("EDID 可读不等于系统在线；Pipe 与 CG 不强行配对。")
        return lines.joined(separator: "\n")
    }

    var portDetails: String {
        guard !mappings.isEmpty else { return "未读取到 Pipe 映射；不能判断链路" }
        let rows = mappings.map { "\($0.name) / \($0.role)\n" + Snapshot.pipeText($0.pipeIDs, $0.maxPipes) }
        return (["端口与 Pipe 分配（端口来自本机注册表枚举，不按产品名固定）"] + rows + [DiagnosticCore.status(mappings), "Pipe 映射不是链路在线证据；空 PipeIDs 表示该记录未列出分配，不据此推断端口状态。"]).joined(separator: "\n\n")
    }
    var edidDetails: String {
        let rows = edids.map { "service=\($0.serviceID) · vendor=\($0.vendor) model=\($0.model)\n\($0.byteCount) 字节 · 长度/校验：\($0.valid ? "通过" : "不通过") · 名称：\($0.name ?? "不可读")" }
        return ((rows.isEmpty ? ["未读取到 EDID 记录（未知，不视为校验通过）"] : rows) + ["校验仅检查长度与 checksum，不证明所有时序安全或当前实际输入。EDID service 与 CG/Pipe 未强行关联。"]).joined(separator: "\n\n")
    }
    var displayDetails: String {
        let cards = externalCards
        let rows = cards.map { "\($0.name) · \($0.stateText)\n" + $0.detail }
        return ((rows.isEmpty ? ["未检测到外接显示器；不显示虚构的屏幕行"] : rows) + [internalSummary]).joined(separator: "\n\n")
    }
}

enum Presentation {
    static func dimensions(_ width: Int?, _ height: Int?) -> String {
        guard let w = width, let h = height, w > 0, h > 0 else { return L10n.text("Unknown") }
        return "\(w)×\(h)"
    }
    static func refreshRate(_ value: Double?) -> String {
        guard let value = value else { return L10n.text("Unknown") }
        return value > 0 && value.isFinite ? String(format: "%.2f Hz", value) : L10n.text("Unknown / variable (no fixed API value)")
    }
    static func beijingTime(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else { return L10n.text("Unknown time ({0})", String(value)) }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = TimeZone(identifier: "Asia/Shanghai")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: date) + L10n.text(" Beijing time UTC+8")
    }
    static func countdown(remaining: Int?, total: Int?) -> String {
        let seconds = remaining.map(String.init) ?? "?"
        let limit = total.map(String.init) ?? "?"
        return L10n.text("Waiting for displays… {0}s remaining (of {1}s); automatic undo at deadline", String(seconds), String(limit))
    }
}
