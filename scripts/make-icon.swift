import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let card = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 208, yRadius: 208)
        NSColor(calibratedRed: 0.12, green: 0.27, blue: 0.62, alpha: 1).setFill(); card.fill()
        card.addClip()
        let gradient = NSGradient(starting: NSColor(calibratedRed: 0.28, green: 0.65, blue: 1, alpha: 1),
                                  ending: NSColor(calibratedRed: 0.43, green: 0.24, blue: 0.84, alpha: 1))!
        gradient.draw(in: card, angle: -50)
        NSColor.white.withAlphaComponent(0.96).setFill()
        for (x, height) in [(284, 204), (460, 354), (636, 504)] {
            NSBezierPath(roundedRect: NSRect(x: x, y: 260, width: 104, height: height), xRadius: 52, yRadius: 52).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(filename))
    }
}
