import Foundation
import CoreGraphics

// Read-only independent probe: no BetterDisplay dependency, no mode changes.
var count: UInt32 = 0
let first = CGGetOnlineDisplayList(0, nil, &count)
guard first == .success else { fputs("display enumeration failed: \(first.rawValue)\n", stderr); exit(1) }
var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
let second = CGGetOnlineDisplayList(count, &ids, &count)
guard second == .success else { exit(2) }
var displays: [[String: Any]] = []
for id in ids.prefix(Int(count)) {
    let mode = CGDisplayCopyDisplayMode(id)
    displays.append([
        "id": id,
        "builtin": CGDisplayIsBuiltin(id) != 0,
        "online": CGDisplayIsOnline(id) != 0,
        "logicalWidth": mode?.width ?? 0,
        "logicalHeight": mode?.height ?? 0,
        "renderWidth": mode?.pixelWidth ?? 0,
        "renderHeight": mode?.pixelHeight ?? 0,
        "reportedRefreshHz": mode?.refreshRate ?? 0,
        "vendor": CGDisplayVendorNumber(id),
        "model": CGDisplayModelNumber(id)
    ])
}
let result: [String: Any] = ["readOnly": true, "backend": "CoreGraphics", "displays": displays]
let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: data, as: UTF8.self))
