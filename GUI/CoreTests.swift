import Foundation

@main struct CoreTests {
    static func main() throws {
        let tree: [[String: Any]] = [["IORegistryEntryChildren": [["ConnectionMapping": [["ProductName": "QSN-CAB", "role": "DCPEXT1", "PipeIDs": [1, 0], "MaxPipes": 2]]]]]]
        let data = try PropertyListSerialization.data(fromPropertyList: tree, format: .xml, options: 0)
        let rows = try DiagnosticCore.mappings(data)
        guard rows.count == 1, rows.first?.pipeIDs == [1,0], rows.first?.maxPipes == 2, rows.first?.name == "QSN-CAB" else {
            print("FAIL: nested ConnectionMapping must preserve actual PipeIDs separately from MaxPipes")
            exit(1)
        }
        print("PASS: nested ConnectionMapping preserves PipeIDs and MaxPipes")
        guard DiagnosticCore.status(rows) == "检测到多 Pipe 分配；恢复尚未验证", DiagnosticCore.status([]) == "未读取到 Pipe 映射；不能判断链路", DiagnosticCore.status([PipeMapping(name: "x", role: "r", pipeIDs: [1], maxPipes: 2)]) == "已读取 Pipe 分配；不代表实际输入或恢复成功" else {
            print("FAIL: status must warn for multi-pipe and never infer recovery from capability or missing data")
            exit(1)
        }
        print("PASS: conservative status for multi-pipe, single-pipe and missing data")
        let text = "SERVICE id=42 location=External\nCOPY result=0x00000000\nEDID bytes=384 checksumAndLengthValid=true vendor=0x22f6 model=0x6346\nSERVICE id=43 location=External\nEDID bytes=128 checksumAndLengthValid=false vendor=0x3103 model=0x907d\n"
        let readings = DiagnosticCore.edids(text)
        guard readings.count == 2, readings.first?.serviceID == "42", readings.first?.byteCount == 384, readings.first?.valid == true, readings.last?.valid == false, DiagnosticCore.edids("COPY result=0xdeadbeef").isEmpty else {
            print("FAIL: EDID parser must retain service identity and invalid checksum, reject missing records")
            exit(1)
        }
        print("PASS: EDID records preserve identity, length, validity; missing data is not success")
        let unnamed = try DiagnosticCore.mappings(PropertyListSerialization.data(fromPropertyList: [["ConnectionMapping": [["ProductName": "  ", "role": "DCPEXT0", "PipeIDs": []]]]], format: .xml, options: 0))
        guard unnamed.first?.name == "未命名连接（DCPEXT0）" else {
            print("FAIL: empty mapping name must use a readable role-based fallback"); exit(1)
        }
        print("PASS: empty mapping name uses readable role-based fallback")
        let one = DisplayReading(id: 1, name: "QSN-CAB", builtin: false, vendor: 0x22f6, model: 0x6346, logicalWidth: nil, logicalHeight: nil, renderWidth: nil, renderHeight: nil, reportedRefreshHz: nil)
        let partial = Snapshot(refreshedAt: "2026-10-18T00:00:00Z", displays: [one], mappings: rows, edids: readings, errors: [])
        guard partial.targetCards.count == 2, partial.targetCards[0].state == .online, partial.targetCards[1].state == .missing, partial.hardwareSummary.contains("1 / 2"), partial.collectionSummary.contains("采集完成"), !partial.status.contains("双屏在线") else {
            print("FAIL: successful collection must still warn about missing target display"); exit(1)
        }
        print("PASS: collection success is separate from missing target hardware")
        guard Presentation.dimensions(nil, nil) == "未知", Presentation.refreshRate(nil) == "未知", Presentation.refreshRate(0).contains("未知"), Presentation.beijingTime("2026-10-18T00:00:00Z").contains("08:00:00") else {
            print("FAIL: missing mode must remain unknown and timestamps must be Beijing"); exit(1)
        }
        print("PASS: unknown mode data and explicit Beijing timestamp")
        let unknown = Snapshot(refreshedAt: "x", displays: [], mappings: [], edids: readings, errors: ["CoreGraphics 枚举失败：1"])
        guard unknown.targetCards.allSatisfy({ $0.state == .unknown }), unknown.hardwareSummary.contains("无法确认"), unknown.collectionSummary.contains("不完整") else {
            print("FAIL: enumeration failure and EDID presence must not imply online or absent"); exit(1)
        }
        print("PASS: enumeration failure produces unknown hardware, EDID is not online proof")
        let duplicate = Snapshot(refreshedAt: "x", displays: [one, one], mappings: [], edids: [], errors: [])
        guard duplicate.targetCards[0].state == .ambiguous else { print("FAIL: duplicate target identity must be ambiguous"); exit(1) }
        print("PASS: duplicate target identity is ambiguous")
        guard partial.pipeDetails.contains("MaxPipes"), partial.edidDetails.contains("service=42"), partial.targetDetails(partial.targetCards[1]).contains("EDID 可读不等于系统在线"), partial.targetDetails(partial.targetCards[0]).contains("逻辑 未知"), Snapshot.recoveryNotice.contains("不可用") else {
            print("FAIL: GUI sections must expose independent evidence and unavailable recovery"); exit(1)
        }
        print("PASS: GUI sections preserve separate Pipe, EDID, mode and recovery evidence")
        let exported = try JSONSerialization.jsonObject(with: partial.json()) as! [String: Any]
        guard exported["targetCards"] is [[String: Any]], exported["collectionSummary"] as? String == partial.collectionSummary, exported["hardwareSummary"] as? String == partial.hardwareSummary else {
            print("FAIL: smoke JSON must expose hardware and collection layers independently"); exit(1)
        }
        print("PASS: smoke JSON exposes target states and independent collection status")
        do { _ = try DiagnosticCore.mappings(Data("not plist".utf8)); print("FAIL: malformed plist accepted"); exit(1) } catch { print("PASS: malformed plist throws") }
    }
}
