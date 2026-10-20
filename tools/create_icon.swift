import AppKit
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = root.appendingPathComponent(".build/AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
func draw(_ pixels: Int) throws -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)!
    let scale = CGFloat(pixels) / 1024
    NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)
    let rect = NSRect(x: 60, y: 60, width: 904, height: 904)
    let shape = NSBezierPath(roundedRect: rect, xRadius: 200, yRadius: 200)
    NSGradient(starting: NSColor(red: 0.12, green: 0.11, blue: 0.26, alpha: 1), ending: NSColor(red: 0.31, green: 0.22, blue: 0.65, alpha: 1))!.draw(in: shape, angle: 45)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: NSRect(x: 235, y: 585, width: 554, height: 190), xRadius: 70, yRadius: 70).fill()
    NSColor(calibratedWhite: 0.18, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 483, y: 695, width: 58, height: 25)).fill()
    func sparkle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat, _ color: NSColor) {
        let p = NSBezierPath(); p.move(to: NSPoint(x: x, y: y + radius))
        p.curve(to: NSPoint(x: x + radius, y: y), controlPoint1: NSPoint(x: x + radius * 0.2, y: y + radius * 0.2), controlPoint2: NSPoint(x: x + radius * 0.2, y: y + radius * 0.2))
        p.curve(to: NSPoint(x: x, y: y - radius), controlPoint1: NSPoint(x: x + radius * 0.2, y: y - radius * 0.2), controlPoint2: NSPoint(x: x + radius * 0.2, y: y - radius * 0.2))
        p.curve(to: NSPoint(x: x - radius, y: y), controlPoint1: NSPoint(x: x - radius * 0.2, y: y - radius * 0.2), controlPoint2: NSPoint(x: x - radius * 0.2, y: y - radius * 0.2))
        p.curve(to: NSPoint(x: x, y: y + radius), controlPoint1: NSPoint(x: x - radius * 0.2, y: y + radius * 0.2), controlPoint2: NSPoint(x: x - radius * 0.2, y: y + radius * 0.2))
        p.close(); color.setFill(); p.fill()
    }
    sparkle(480, 370, 155, .white)
    sparkle(700, 470, 65, NSColor(red: 0.4, green: 0.9, blue: 1, alpha: 1))
    sparkle(300, 310, 43, NSColor(red: 0.9, green: 0.7, blue: 1, alpha: 1))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}
for size in [16, 32, 128, 256, 512] {
    try draw(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try draw(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
