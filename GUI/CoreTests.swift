import Foundation

@main struct CoreTests {
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        guard value() else { print("FAIL: " + message); exit(1) }
        print("PASS: " + message)
    }
    static func online(id: UInt32, name: String, vendor: UInt32, model: UInt32, hz: Double?) -> DisplayReading {
        DisplayReading(id: id, name: name, builtin: false, vendor: vendor, model: model,
                       logicalWidth: 1920, logicalHeight: 1080, renderWidth: 3840, renderHeight: 2160, reportedRefreshHz: hz)
    }
    static func reading(_ service: String, vendor: String, model: String, name: String?, named: Bool,
                        valid: Bool = true, bytes: Int = 384) -> EDIDReading {
        EDIDReading(serviceID: service, byteCount: bytes, valid: valid, vendor: vendor, model: model, name: name, named: named)
    }
    static func main() throws {
        // ---- registry and probe parsing ----
        let tree: [[String: Any]] = [["IORegistryEntryChildren": [["ConnectionMapping": [["ProductName": "PANEL-A", "role": "DCPEXT1", "PipeIDs": [1, 0], "MaxPipes": 2]]]]]]
        let data = try PropertyListSerialization.data(fromPropertyList: tree, format: .xml, options: 0)
        let rows = try DiagnosticCore.mappings(data)
        check(rows.count == 1 && rows.first?.pipeIDs == [1, 0] && rows.first?.maxPipes == 2 && rows.first?.name == "PANEL-A",
              "nested ConnectionMapping preserves PipeIDs separately from MaxPipes")
        check(DiagnosticCore.status(rows) == "检测到多 Pipe 分配；可能是可恢复的连接故障"
              && DiagnosticCore.status([]) == "未读取到 Pipe 映射；不能判断链路"
              && DiagnosticCore.status([PipeMapping(name: "x", role: "r", pipeIDs: [1], maxPipes: 2)]) == "已读取 Pipe 分配；不代表实际输入或恢复成功",
              "status warns for multi-pipe and never infers recovery from capability or missing data")
        let probe = "SERVICE id=42 location=External\nCOPY result=0x00000000\nEDID bytes=384 checksumAndLengthValid=true vendor=0x1a2b model=0x3001 name=PANEL%20A named=true\nSERVICE id=43 location=External\nEDID bytes=128 checksumAndLengthValid=false vendor=0x2b3c model=0x4002 name= named=false\n"
        let readings = DiagnosticCore.edids(probe)
        check(readings.count == 2 && readings[0].serviceID == "42" && readings[0].byteCount == 384 && readings[0].valid
              && readings[0].name == "PANEL A" && readings[0].named && readings[1].name == nil && !readings[1].named && !readings[1].valid,
              "probe records preserve service identity, the decoded 0xFC name and an honest unreadable name")
        check(DiagnosticCore.edids("COPY result=0xdeadbeef").isEmpty, "EDID parser rejects records without a monitor service")
        let unnamed = try DiagnosticCore.mappings(PropertyListSerialization.data(fromPropertyList: [["ConnectionMapping": [["ProductName": "  ", "role": "DCPEXT0", "PipeIDs": []]]]], format: .xml, options: 0))
        check(unnamed.first?.name == "未命名连接（DCPEXT0）", "empty mapping name uses a readable role-based fallback")

        // ---- dynamic rows: every name comes from the displays themselves ----
        let a = online(id: 3, name: "", vendor: 0x1a2b, model: 0x3001, hz: 120)
        let b = online(id: 4, name: "PANEL B", vendor: 0x2b3c, model: 0x4002, hz: 60)
        let mappings = [PipeMapping(name: "PANEL A", role: "DCPEXT1", pipeIDs: [1], maxPipes: 1),
                        PipeMapping(name: "PANEL B", role: "DCPEXT0", pipeIDs: [0], maxPipes: 1)]
        let snapshot = Snapshot(refreshedAt: "2026-10-18T00:00:00Z", displays: [a, b], mappings: mappings,
                                edids: [reading("42", vendor: "0x1a2b", model: "0x3001", name: "PANEL A", named: true),
                                        reading("43", vendor: "0x2b3c", model: "0x4002", name: nil, named: false)],
                                errors: [])
        let cards = snapshot.externalCards
        check(cards.count == 2, "one row per online external display, no fixed two-row assumption")
        check(cards[0].name == "PANEL A" && cards[0].nameSource == "edid" && cards[0].stateText == "在线 · 120 Hz" && cards[0].port == "DCPEXT1",
              "EDID 0xFC name is preferred and the row reports online state, reported Hz and port")
        check(cards[1].name == "PANEL B" && cards[1].nameSource == "coregraphics" && cards[1].stateText == "在线 · 60 Hz",
              "without a 0xFC name the CoreGraphics name is used honestly")
        check(snapshot.hardwareSummary.contains("外接显示器 2 台") && snapshot.hardwareSummary.contains("内屏：未在线")
              && snapshot.collectionSummary.contains("采集完成"),
              "hardware summary is dynamic and reports the internal display state")

        let anonymous = Snapshot(refreshedAt: "x", displays: [online(id: 5, name: "未知显示器（CG 5）", vendor: 0x1111, model: 0x2222, hz: nil)],
                                 mappings: [], edids: [], errors: [])
        check(anonymous.externalCards.first?.nameSource == "vendor-model"
              && anonymous.externalCards.first?.name == "0x1111:0x2222"
              && anonymous.externalCards.first?.stateText.contains("刷新率未知") == true,
              "a display without any readable name falls back to vendor:model and says the rate is unknown")

        let unreadable = Snapshot(refreshedAt: "x", displays: [online(id: 6, name: "", vendor: 0x3333, model: 0x4444, hz: 120)],
                                  mappings: [], edids: [reading("77", vendor: "0x3333", model: "0x4444", name: nil, named: false, valid: false, bytes: 0)],
                                  errors: [])
        check(unreadable.externalCards.count == 1 && unreadable.externalCards[0].edidValid == false
              && unreadable.externalCards[0].detail.contains("不通过"),
              "an online display with an invalid EDID stays online but its EDID is reported as failing")

        let offline = Snapshot(refreshedAt: "x", displays: [online(id: 7, name: "PANEL C", vendor: 0x5555, model: 0x6666, hz: 120)],
                               mappings: [], edids: [reading("88", vendor: "0x9999", model: "0xaaaa", name: nil, named: false)],
                               errors: [])
        check(offline.externalCards.count == 2, "a connected-but-offline external service still gets a row")
        check(offline.externalCards[1].online == false && offline.externalCards[1].stateText.contains("系统未上线"),
              "the extra row says the display is connected but not online")

        let one = Snapshot(refreshedAt: "x", displays: [a], mappings: [], edids: [], errors: [])
        check(one.externalCards.count == 1, "one external is one row")
        let three = Snapshot(refreshedAt: "x", displays: [a, b, online(id: 8, name: "PANEL C", vendor: 0x5555, model: 0x6666, hz: 144)],
                             mappings: [], edids: [], errors: [])
        check(three.externalCards.count == 3 && three.externalCards[2].stateText.contains("144"),
              "three externals are all shown with their own reported Hz")
        let none = Snapshot(refreshedAt: "x", displays: [DisplayReading(id: 1, name: "内屏", builtin: true, vendor: 1, model: 2, logicalWidth: 3456, logicalHeight: 2234, renderWidth: 3456, renderHeight: 2234, reportedRefreshHz: 120)],
                            mappings: [], edids: [], errors: [])
        check(none.externalCards.isEmpty && none.hardwareSummary.contains("未检测到外接显示器"),
              "zero externals are reported honestly instead of showing fixed rows")

        let ambiguous = Snapshot(refreshedAt: "x", displays: [a], mappings: [],
                                 edids: [reading("1", vendor: "0x1a2b", model: "0x3001", name: "PANEL A", named: true),
                                         reading("2", vendor: "0x1a2b", model: "0x3001", name: "PANEL B", named: true)], errors: [])
        check(ambiguous.externalCards.count == 1 && ambiguous.externalCards[0].state == .ambiguous
              && ambiguous.externalCards[0].stateText.contains("无法确认"),
              "two different names for one identity are reported as unconfirmable, not guessed")

        let enumFailed = Snapshot(refreshedAt: "x", displays: [a], mappings: [], edids: [], errors: ["CoreGraphics 枚举失败：1"])
        check(enumFailed.externalCards.allSatisfy { $0.state == .unknown } && enumFailed.hardwareSummary.contains("无法确认")
              && enumFailed.collectionSummary.contains("不完整"),
              "enumeration failure is unknown and never inferred as online or missing")

        check(snapshot.portDetails.contains("MaxPipes") && snapshot.edidDetails.contains("service=42")
              && snapshot.edidDetails.contains("不可读") && snapshot.displayDetails.contains("名称来源")
              && Snapshot.recoveryNotice.contains("健康状态不写入"),
              "GUI sections expose independent Pipe, EDID, naming and recovery evidence")
        check(Presentation.dimensions(nil, nil) == "未知" && Presentation.refreshRate(nil) == "未知"
              && Presentation.refreshRate(0).contains("未知") && Presentation.beijingTime("2026-10-18T00:00:00Z").contains("08:00:00"),
              "unknown mode data stays unknown and timestamps render in Beijing time")
        check(Presentation.countdown(remaining: 18, total: 20).contains("18") && Presentation.countdown(remaining: 18, total: 20).contains("自动撤销"),
              "countdown copy states the remaining seconds and the automatic revert")

        let exported = try JSONSerialization.jsonObject(with: snapshot.json()) as! [String: Any]
        check(exported["externalCards"] is [[String: Any]] && exported["hardwareSummary"] as? String == snapshot.hardwareSummary
              && exported["collectionSummary"] as? String == snapshot.collectionSummary,
              "smoke JSON exposes the dynamic display cards and independent collection status")
        do { _ = try DiagnosticCore.mappings(Data("not plist".utf8)); print("FAIL: malformed plist accepted"); exit(1) }
        catch { print("PASS: malformed plist throws") }
        print("PASS: dynamic identification checks complete")
    }
}
