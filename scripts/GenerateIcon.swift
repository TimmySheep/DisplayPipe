import AppKit
import Foundation
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
 for scale in [1, 2] {
  let pixels = size * scale
  let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
  NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
  let factor = CGFloat(pixels) / 1024
  NSGraphicsContext.current!.cgContext.scaleBy(x: factor, y: factor)
  let background = NSBezierPath(roundedRect: NSRect(x: 28,y: 28,width: 968,height: 968), xRadius: 218,yRadius: 218)
  NSGradient(starting: NSColor(calibratedRed: 0.08,green: 0.15,blue: 0.30,alpha: 1),ending: NSColor(calibratedRed: 0.12,green: 0.07,blue: 0.24,alpha: 1))!.draw(in: background, angle: -45)
  func monitor(_ rect: NSRect, _ color: NSColor) {
   color.setFill(); NSBezierPath(roundedRect: rect,xRadius: 34,yRadius: 34).fill()
   NSColor(calibratedWhite: 0.06,alpha: 1).setFill()
   NSBezierPath(roundedRect: rect.insetBy(dx: 22,dy: 22),xRadius: 17,yRadius: 17).fill()
   color.withAlphaComponent(0.22).setFill()
   NSBezierPath(roundedRect: rect.insetBy(dx: 35,dy: 35),xRadius: 10,yRadius: 10).fill()
   color.setFill(); NSBezierPath(roundedRect: NSRect(x: rect.midX-15,y: rect.minY-55,width: 30,height: 55),xRadius: 5,yRadius: 5).fill()
   NSBezierPath(roundedRect: NSRect(x: rect.midX-65,y: rect.minY-70,width: 130,height: 18),xRadius: 9,yRadius: 9).fill()
  }
  monitor(NSRect(x: 115,y: 455,width: 430,height: 305),NSColor(calibratedRed: 0.30,green: 0.81,blue: 1,alpha: 1))
  monitor(NSRect(x: 555,y: 330,width: 335,height: 275),NSColor(calibratedRed: 0.72,green: 0.56,blue: 1,alpha: 1))
  let route=NSBezierPath(); route.move(to:NSPoint(x:330,y:340)); route.line(to:NSPoint(x:330,y:240)); route.curve(to:NSPoint(x:400,y:170),controlPoint1:NSPoint(x:330,y:190),controlPoint2:NSPoint(x:350,y:170)); route.line(to:NSPoint(x:650,y:170)); route.curve(to:NSPoint(x:722,y:240),controlPoint1:NSPoint(x:700,y:170),controlPoint2:NSPoint(x:722,y:190)); route.line(to:NSPoint(x:722,y:245)); route.lineWidth=30; route.lineCapStyle = .round
  NSColor(calibratedRed:0.26,green:0.94,blue:0.66,alpha:1).setStroke(); route.stroke()
  let check=NSBezierPath(); check.move(to:NSPoint(x:458,y:305)); check.line(to:NSPoint(x:500,y:263)); check.line(to:NSPoint(x:583,y:350)); check.lineWidth=30; check.lineCapStyle = .round; check.lineJoinStyle = .round; check.stroke()
  NSGraphicsContext.restoreGraphicsState()
  let name="icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
  try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name), options: .withoutOverwriting)
 }
}
print("Generated native icon set: \(output.path)")
