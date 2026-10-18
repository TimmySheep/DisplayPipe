import Foundation

enum RecoveryClient {
 static func arguments(resources: URL, command: [String]) -> [String] {
  ["-B", resources.appendingPathComponent("backend/recovery.py").path] + command
 }
 static var stateURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/DisplayPipe") }
 static func run(_ command: [String], progress: @escaping ([String: Any]) -> Void = { _ in }) throws -> [String: Any] {
  guard let resources = Bundle.main.resourceURL else { throw failure("应用资源路径缺失") }
  let python = try String(contentsOf: resources.appendingPathComponent("python-path.txt"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
  guard python.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: python) else {
   throw failure("缺少已验证的现有 Python 3.9+：\(python)。本App不安装运行时；请恢复该解释器后重试。未写入显示。")
  }
  let process = Process(); let pipe = Pipe()
  process.executableURL = URL(fileURLWithPath: python)
  process.arguments = arguments(resources: resources, command: command)
  var env = ProcessInfo.processInfo.environment
  env["PYTHONDONTWRITEBYTECODE"] = "1"; env["PYTHONUNBUFFERED"] = "1"
  // A copied bundle never needs a writable source tree or shell PATH.
  env["DISPLAYPIPE_STATE"] = stateURL.path
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
  guard let value = result else { throw failure("后端中断或依赖不可用（退出 \(process.terminationStatus)）。若曾开始恢复，请保留记录并刷新检查未结束事务。\n\(diagnostics.prefix(1000))") }
  return value
 }
 static func failure(_ message: String) -> NSError { NSError(domain: "DisplayPipe", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
