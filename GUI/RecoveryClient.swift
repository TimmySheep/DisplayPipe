import Foundation

/// Runs the guarded backend with an interpreter that already exists on this Mac.
///
/// Resolution order (documented in the user guide, never an install and never a system write):
///   1. `DISPLAYPIPE_PYTHON` when set (explicit override; if it does not qualify, that is an error)
///   2. the path recorded next to the bundle in `python-path.txt`
///   3. `/usr/bin/python3` (Apple's command line tools stub is present on every supported Mac)
///   4. other standard locations (`/usr/local/bin/python3`, `/opt/homebrew/bin/python3`,
///      `/Library/Frameworks/Python.framework/Versions/*/bin/python3`)
///   5. `DISPLAYPIPE_PYTHON_CANDIDATES` when set (colon separated, for installs/tests)
/// Every candidate must be executable and report Python 3.9 or newer.
enum RecoveryClient {
    static let documentedFallbacks = ["/usr/bin/python3", "/usr/local/bin/python3", "/opt/homebrew/bin/python3"]
    static let frameworkGlob = "/Library/Frameworks/Python.framework/Versions/*/bin/python3"
    static let minimumVersion = "3.9"

    static func arguments(resources: URL, command: [String]) -> [String] {
        ["-B", resources.appendingPathComponent("backend/recovery.py").path] + command
    }
    static var stateURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/DisplayPipe") }

    static func splitCandidates(_ value: String?) -> [String] {
        guard let value = value else { return [] }
        return value.split(separator: ":").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    static func frameworkCandidates() -> [String] {
        let versions = "/Library/Frameworks/Python.framework/Versions"
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: versions) else { return [] }
        return entries.sorted().map { versions + "/" + $0 + "/bin/python3" }
    }
    /// Ordered, de-duplicated candidate list. The order is the contract this file documents.
    /// A non-empty `extra` list (DISPLAYPIPE_PYTHON_CANDIDATES) *replaces* the documented
    /// fallbacks for installations and tests; it never removes the recorded hint.
    static func candidates(recorded: String?, override: String? = nil, fallbacks: [String]? = nil,
                           extra: [String] = []) -> [String] {
        var ordered: [String] = []
        func add(_ path: String?) {
            guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines), !path.isEmpty else { return }
            if !ordered.contains(path) { ordered.append(path) }
        }
        add(override)
        add(recorded)
        for path in (extra.isEmpty ? (fallbacks ?? documentedFallbacks) : extra) { add(path) }
        for path in frameworkCandidates() { add(path) }
        return ordered
    }

    /// True when the candidate runs and reports Python 3.9+. Never installs anything.
    static func qualifies(_ path: String) -> Bool {
        guard path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) else { return false }
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["-B", "-c", "import sys; assert sys.version_info >= (3, 9); print(sys.executable)"]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 && !data.isEmpty
    }

    static func resolvedInterpreter(recorded: String?, override: String? = nil, fallbacks: [String]? = nil,
                                    extra: [String] = []) throws -> String {
        let ordered = candidates(recorded: recorded, override: override, fallbacks: fallbacks, extra: extra)
        // An explicit override is a decision, not a hint: honour it or fail, never silently ignore it.
        if let override = override?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            guard qualifies(override) else { throw missingInterpreter(ordered: [override], overridden: true) }
            return override
        }
        for candidate in ordered where qualifies(candidate) { return candidate }
        throw missingInterpreter(ordered: ordered, overridden: false)
    }

    static func missingInterpreter(ordered: [String], overridden: Bool) -> NSError {
        let tried = ordered.isEmpty ? "（无可尝试的路径）" : ordered.joined(separator: "、")
        let advice = overridden
            ? "DISPLAYPIPE_PYTHON 指向的解释器不可执行或低于 3.9；请修正该变量或取消它。"
            : "请安装或提供 Python 3.9+（例如 Xcode/命令行工具自带 /usr/bin/python3，或用 DISPLAYPIPE_PYTHON 指定已有解释器）。"
        return failure("缺少可用的现有 Python 3.9+。已尝试：\(tried)。本App不安装任何运行时、不修改系统；\(advice)未写入显示。")
    }

    static func recordedInterpreter(resources: URL) -> String? {
        guard let text = try? String(contentsOf: resources.appendingPathComponent("python-path.txt"), encoding: .utf8) else { return nil }
        let path = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    static func run(_ command: [String], progress: @escaping ([String: Any]) -> Void = { _ in }) throws -> [String: Any] {
        guard let resources = Bundle.main.resourceURL else { throw failure("应用资源路径缺失") }
        let environment = ProcessInfo.processInfo.environment
        let python = try resolvedInterpreter(recorded: recordedInterpreter(resources: resources),
                                            override: environment["DISPLAYPIPE_PYTHON"],
                                            extra: splitCandidates(environment["DISPLAYPIPE_PYTHON_CANDIDATES"]))
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = arguments(resources: resources, command: command)
        var env = environment
        env["PYTHONDONTWRITEBYTECODE"] = "1"; env["PYTHONUNBUFFERED"] = "1"
        // A copied bundle never needs a writable source tree or shell PATH.
        env["DISPLAYPIPE_STATE"] = stateURL.path
        env["DISPLAYPIPE_INTERPRETER"] = python
        process.environment = env; process.currentDirectoryURL = resources
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 100, execute: watchdog)
        var buffer = Data(); var result: [String: Any]?; var diagnostics = ""
        while true {
            let chunk = pipe.fileHandleForReading.availableData
            if chunk.isEmpty { break }; buffer.append(chunk)
            while let end = buffer.firstIndex(of: 10) {
                let line = buffer.prefix(upTo: end); buffer.removeSubrange(...end)
                if let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] {
                    if object["progress"] != nil { progress(object) } else { result = object }
                } else { diagnostics += String(decoding: line, as: UTF8.self) + "\n" }
            }
        }
        process.waitUntilExit(); watchdog.cancel()
        guard let value = result else { throw failure("后端中断或依赖不可用（解释器 \(python)，退出 \(process.terminationStatus)）。若曾开始恢复，请保留记录并刷新检查未结束事务。\n\(diagnostics.prefix(1000))") }
        return value
    }
    static func failure(_ message: String) -> NSError { NSError(domain: "DisplayPipe", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
