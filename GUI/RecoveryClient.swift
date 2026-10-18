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
        let tried = ordered.isEmpty ? L10n.text("(no candidate paths)") : ordered.joined(separator: ", ")
        let advice = overridden
            ? L10n.text("DISPLAYPIPE_PYTHON is not executable or is older than 3.9; correct or unset it. ")
            : L10n.text("Provide Python 3.9+ (for example /usr/bin/python3 from Xcode/command line tools, or an existing interpreter via DISPLAYPIPE_PYTHON). ")
        return failure(L10n.text("No usable existing Python 3.9+. Tried: {0}. This app installs no runtime and does not modify the system. {1}No display writes occurred.", String(tried), String(advice)))
    }

    static func recordedInterpreter(resources: URL) -> String? {
        guard let text = try? String(contentsOf: resources.appendingPathComponent("python-path.txt"), encoding: .utf8) else { return nil }
        let path = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    static func run(_ command: [String], progress: @escaping ([String: Any]) -> Void = { _ in }) throws -> [String: Any] {
        guard let resources = Bundle.main.resourceURL else { throw failure(L10n.text("Application resources are missing")) }
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
        guard let value = result else { throw failure(L10n.text("Backend interrupted or dependency unavailable (interpreter {0}, exit {1}). Preserve records and refresh to check for pending transactions.\n{2}", String(python), String(process.terminationStatus), String(diagnostics.prefix(1000)))) }
        return value
    }
    static func failure(_ message: String) -> NSError { NSError(domain: "DisplayPipe", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
