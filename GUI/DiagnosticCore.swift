import Foundation

struct PipeMapping: Codable {
    let name: String
    let role: String
    let pipeIDs: [Int]
    let maxPipes: Int?
}
struct EDIDReading: Codable {
    let serviceID: String
    let byteCount: Int
    let valid: Bool
    let vendor: String
    let model: String
    // Descriptor 0xFC monitor name, when the read-only probe could expose it.
    let name: String?
    let named: Bool
    var vendorNumber: UInt32? { DiagnosticCore.number(vendor) }
    var modelNumber: UInt32? { DiagnosticCore.number(model) }
}
enum DiagnosticCore {
    static func mappings(_ data: Data) throws -> [PipeMapping] {
        let tree = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        var result: [PipeMapping] = []
        func walk(_ value: Any) {
            if let dict = value as? [String: Any] {
                if let entries = dict["ConnectionMapping"] as? [[String: Any]] {
                    for row in entries {
                        let role = (row["role"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        let name = (row["ProductName"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        result.append(PipeMapping(name: name.isEmpty ? "未命名连接（\(role.isEmpty ? "未知角色" : role)）" : name, role: role.isEmpty ? "未知角色" : role, pipeIDs: row["PipeIDs"] as? [Int] ?? [], maxPipes: row["MaxPipes"] as? Int))
                    }
                }
                for (key, item) in dict where key != "ConnectionMapping" { walk(item) }
            } else if let array = value as? [Any] { array.forEach(walk) }
        }
        walk(tree)
        return result.sorted { ($0.role, $0.name) < ($1.role, $1.name) }
    }
    static func number(_ text: String) -> UInt32? {
        var value = text.lowercased()
        if value.hasPrefix("0x") { value = String(value.dropFirst(2)) }
        return UInt32(value, radix: 16)
    }
    /// The probe percent-encodes the 0xFC name so the line stays space-separated key=value.
    static func decodedName(_ text: String?) -> String? {
        guard let text = text, !text.isEmpty else { return nil }
        var bytes = [UInt8](); var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "%", let end = text.index(index, offsetBy: 2, limitedBy: text.endIndex) {
                let hex = String(text[text.index(after: index)...end])
                if let value = UInt8(hex, radix: 16) { bytes.append(value); index = text.index(after: end); continue }
            }
            bytes.append(contentsOf: Array(String(text[index]).utf8)); index = text.index(after: index)
        }
        let name = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : String(name.prefix(24))
    }
    static func edids(_ text: String) -> [EDIDReading] {
        var service = ""
        var result: [EDIDReading] = []
        for line in text.split(separator: "\n") {
            let fields = Dictionary(line.split(separator: " ").compactMap { token -> (String, String)? in
                let pair = token.split(separator: "=", maxSplits: 1)
                return pair.count == 2 ? (String(pair[0]), String(pair[1])) : nil
            }, uniquingKeysWith: { _, last in last })
            if line.hasPrefix("SERVICE ") { service = fields["id"] ?? "" }
            if line.hasPrefix("EDID "), !service.isEmpty, let bytes = fields["bytes"].flatMap(Int.init), let valid = fields["checksumAndLengthValid"], ["true", "false"].contains(valid), let vendor = fields["vendor"], let model = fields["model"] {
                let named = fields["named"] == "true"
                result.append(EDIDReading(serviceID: service, byteCount: bytes, valid: valid == "true", vendor: vendor,
                                          model: model, name: named ? decodedName(fields["name"]) : nil, named: named))
            }
        }
        return result
    }
    static func status(_ mappings: [PipeMapping]) -> String {
        if mappings.isEmpty { return "未读取到 Pipe 映射；不能判断链路" }
        if mappings.contains(where: { $0.pipeIDs.count > 1 }) { return "检测到多 Pipe 分配；可能是可恢复的连接故障" }
        return "已读取 Pipe 分配；不代表实际输入或恢复成功"
    }
}

struct DisplayReading: Codable {
    let id: UInt32
    let name: String
    let builtin: Bool
    let vendor: UInt32
    let model: UInt32
    let logicalWidth: Int?
    let logicalHeight: Int?
    let renderWidth: Int?
    let renderHeight: Int?
    let reportedRefreshHz: Double?
}
struct Snapshot: Encodable {
    let version = "0.2"
    let readOnly = true
    let recoveryValidated = false
    let refreshedAt: String
    let displays: [DisplayReading]
    let mappings: [PipeMapping]
    let edids: [EDIDReading]
    let errors: [String]
    var status: String { hardwareSummary + "；" + DiagnosticCore.status(mappings) }
    func json() throws -> Data {
        // Include computed status explicitly in the smoke output.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var object = try JSONSerialization.jsonObject(with: encoder.encode(self)) as! [String: Any]
        object["status"] = status
        object["hardwareSummary"] = hardwareSummary
        object["collectionSummary"] = collectionSummary
        object["externalCards"] = try JSONSerialization.jsonObject(with: encoder.encode(externalCards))
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    }
}
