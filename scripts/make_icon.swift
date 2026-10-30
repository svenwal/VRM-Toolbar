// Draws the app icon (lightning bolt on an electric squircle) and writes Resources/AppIcon.icns.
// Usage: swift scripts/make_icon.swift
import AppKit

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let S = CGFloat(size)
    let box = CGRect(x: S * 0.098, y: S * 0.098, width: S * 0.804, height: S * 0.804)
    let squircle = NSBezierPath(roundedRect: box, xRadius: box.width * 0.225, yRadius: box.width * 0.225)

    // Drop shadow + body gradient
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -S * 0.012), blur: S * 0.03, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    NSColor.black.setFill(); squircle.fill()
    ctx.restoreGState()
    ctx.saveGState()
    squircle.addClip()
    let space = CGColorSpaceCreateDeviceRGB()
    let body = CGGradient(colorsSpace: space, colors: [
        NSColor(red: 0.30, green: 0.25, blue: 0.95, alpha: 1).cgColor,
        NSColor(red: 0.05, green: 0.10, blue: 0.40, alpha: 1).cgColor,
        NSColor(red: 0.01, green: 0.03, blue: 0.14, alpha: 1).cgColor] as CFArray, locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(body, start: CGPoint(x: box.maxX, y: box.maxY), end: CGPoint(x: box.minX, y: box.minY), options: [])
    // Electric glow behind the bolt
    let glow = CGGradient(colorsSpace: space, colors: [
        NSColor(red: 0.2, green: 0.8, blue: 1, alpha: 0.55).cgColor, NSColor(red: 0.2, green: 0.8, blue: 1, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: S * 0.52, y: S * 0.5), startRadius: 0,
                           endCenter: CGPoint(x: S * 0.52, y: S * 0.5), endRadius: S * 0.42, options: [])

    // Bolt
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: box.minX + box.width * x, y: box.minY + box.height * y) }
    let bolt = NSBezierPath()
    bolt.move(to: p(0.62, 0.93)); bolt.line(to: p(0.27, 0.46)); bolt.line(to: p(0.47, 0.46))
    bolt.line(to: p(0.38, 0.07)); bolt.line(to: p(0.75, 0.57)); bolt.line(to: p(0.54, 0.57)); bolt.close()
    bolt.lineJoinStyle = .round; bolt.lineWidth = S * 0.018
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: S * 0.07, color: NSColor(red: 1, green: 0.8, blue: 0.2, alpha: 0.9).cgColor)
    NSColor(red: 1, green: 0.85, blue: 0.3, alpha: 1).setFill(); bolt.fill()
    ctx.restoreGState()
    ctx.saveGState()
    bolt.addClip()
    let fill = CGGradient(colorsSpace: space, colors: [
        NSColor(red: 1, green: 1, blue: 0.85, alpha: 1).cgColor,
        NSColor(red: 1, green: 0.82, blue: 0.2, alpha: 1).cgColor,
        NSColor(red: 1, green: 0.5, blue: 0.1, alpha: 1).cgColor] as CFArray, locations: [0, 0.5, 1])!
    ctx.drawLinearGradient(fill, start: p(0.5, 0.95), end: p(0.5, 0.05), options: [])
    ctx.restoreGState()
    NSColor.white.withAlphaComponent(0.7).setStroke(); bolt.stroke()

    // Glass sheen on the top half
    let sheen = CGGradient(colorsSpace: space, colors: [
        NSColor.white.withAlphaComponent(0.28).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: S / 2, y: box.maxY), end: CGPoint(x: S / 2, y: box.midY), options: [])
    ctx.restoreGState()
    // Rim light
    NSColor.white.withAlphaComponent(0.25).setStroke()
    squircle.lineWidth = S * 0.004; squircle.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let fm = FileManager.default
let iconset = NSTemporaryDirectory() + "AppIcon-\(UUID().uuidString).iconset"
try fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: URL(fileURLWithPath: "\(iconset)/icon_\(base)x\(base)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset, "-o", "Resources/AppIcon.icns"]
try task.run(); task.waitUntilExit()
try? fm.removeItem(atPath: iconset)
print(task.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
