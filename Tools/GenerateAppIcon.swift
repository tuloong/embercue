import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("usage: GenerateAppIcon.swift OUTPUT_DIRECTORY\n", stderr)
    exit(64)
}

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let sizes = [16, 32, 64, 128, 256, 512, 1024]
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

for size in sizes {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "EmbercueIcon", code: 1)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.black.setFill()
    NSBezierPath(roundedRect: rect, xRadius: CGFloat(size) * 0.18, yRadius: CGFloat(size) * 0.18).fill()

    let ember = NSBezierPath()
    ember.move(to: NSPoint(x: CGFloat(size) * 0.52, y: CGFloat(size) * 0.17))
    ember.line(to: NSPoint(x: CGFloat(size) * 0.31, y: CGFloat(size) * 0.49))
    ember.line(to: NSPoint(x: CGFloat(size) * 0.45, y: CGFloat(size) * 0.75))
    ember.line(to: NSPoint(x: CGFloat(size) * 0.54, y: CGFloat(size) * 0.60))
    ember.line(to: NSPoint(x: CGFloat(size) * 0.38, y: CGFloat(size) * 0.52))
    ember.line(to: NSPoint(x: CGFloat(size) * 0.59, y: CGFloat(size) * 0.32))
    ember.close()

    let lowerStroke = NSBezierPath()
    lowerStroke.move(to: NSPoint(x: CGFloat(size) * 0.65, y: CGFloat(size) * 0.45))
    lowerStroke.line(to: NSPoint(x: CGFloat(size) * 0.69, y: CGFloat(size) * 0.54))
    lowerStroke.line(to: NSPoint(x: CGFloat(size) * 0.46, y: CGFloat(size) * 0.78))
    lowerStroke.close()

    NSColor.white.setFill()
    ember.fill()
    lowerStroke.fill()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "EmbercueIcon", code: 1) }
    try png.write(to: directory.appendingPathComponent("\(size).png"))
}
