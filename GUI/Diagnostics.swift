import Foundation
import AppKit
import CoreGraphics

enum Diagnostics {
    // Query only the mapping owner, not the machine-wide registry (tens of MB).
    // Missing mappings remain an explicit diagnostic failure, never inferred healthy.
    static let registryArguments = ["-a", "-l", "-w0", "-r", "-c", "AppleDisplayConnectionManager"]
    static func screenNames() -> [UInt32: String] {
        var names: [UInt32: String] = [:]
        for screen in NSScreen.screens {
            if let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 { names[id] = screen.localizedName }
        }
        return names
    }
    static func run(_ executable: String, _ arguments: [String] = []) throws -> Data {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Drain before wait to prevent a full ioreg pipe from deadlocking.
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        guard process.terminationStatus == 0 else { throw NSError(domain: "DisplayPipe", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "\(URL(fileURLWithPath: executable).lastPathComponent) 失败或超时，退出码 \(process.terminationStatus)"]) }
        return data
    }
    static func collect(names: [UInt32: String]) -> Snapshot {
        var errors: [String] = []
        var displays: [DisplayReading] = []
        var count: UInt32 = 0
        var result = CGGetOnlineDisplayList(0, nil, &count)
        if result == .success {
            var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
            result = CGGetOnlineDisplayList(count, &ids, &count)
            if result == .success {
                for id in ids.prefix(Int(count)) {
                    let mode = CGDisplayCopyDisplayMode(id)
                    displays.append(DisplayReading(id: id, name: names[id] ?? "未知显示器（CG \(id)）", builtin: CGDisplayIsBuiltin(id) != 0, vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id), logicalWidth: mode?.width, logicalHeight: mode?.height, renderWidth: mode?.pixelWidth, renderHeight: mode?.pixelHeight, reportedRefreshHz: mode?.refreshRate))
                }
            }
        }
        if result != .success { errors.append("CoreGraphics 枚举失败：\(result.rawValue)") }
        var mappings: [PipeMapping] = []
        do {
            mappings = try DiagnosticCore.mappings(run("/usr/sbin/ioreg", registryArguments))
            if mappings.isEmpty { errors.append("IORegistry 未提供 ConnectionMapping") }
        } catch { errors.append("Pipe：\(error.localizedDescription)") }
        var edids: [EDIDReading] = []
        do {
            let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/EDIDProbe").path
            edids = DiagnosticCore.edids(String(decoding: try run(helper), as: UTF8.self))
            if edids.isEmpty { errors.append("EDID：未读取到外接记录") }
        } catch { errors.append("EDID：\(error.localizedDescription)") }
        return Snapshot(refreshedAt: ISO8601DateFormatter().string(from: Date()), displays: displays, mappings: mappings, edids: edids, errors: errors)
    }
}
