import AppKit
import Foundation
let before=URL(fileURLWithPath: CommandLine.arguments[1]); let after=URL(fileURLWithPath: CommandLine.arguments[2])
let files=try FileManager.default.contentsOfDirectory(at: before, includingPropertiesForKeys: nil).filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
let afterFiles=try FileManager.default.contentsOfDirectory(at: after, includingPropertiesForKeys: nil).filter { $0.pathExtension == "png" }
precondition(Set(files.map(\.lastPathComponent)) == Set(afterFiles.map(\.lastPathComponent)), "all icon representations must remain")
for file in files {
 let a=NSBitmapImageRep(data: try Data(contentsOf: file))!
 let b=NSBitmapImageRep(data: try Data(contentsOf: after.appendingPathComponent(file.lastPathComponent)))!
 precondition(a.pixelsWide == b.pixelsWide && a.pixelsHigh == b.pixelsHigh && a.samplesPerPixel == b.samplesPerPixel && a.bitsPerSample == b.bitsPerSample, "icon pixel layout changed")
 let stride=a.samplesPerPixel
 var xPixel=[Int](repeating: 0, count: stride); var yPixel=xPixel
 for y in 0..<a.pixelsHigh { for x in 0..<a.pixelsWide {
  a.getPixel(&xPixel, atX: x, y: y); b.getPixel(&yPixel, atX: x, y: y)
  precondition(xPixel == yPixel, "icon pixel changed: \(file.lastPathComponent) at \(x),\(y)")
 } }
 print("PASS: AppKit decoded identical pixels", file.lastPathComponent, a.pixelsWide, a.pixelsHigh)
}
print("PASS: all \(files.count) icon representations retained pixel-exact")
