import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: pixels, height: pixels))
        image.lockFocus()
        let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
        let side = CGFloat(pixels)
        let shape = NSBezierPath(roundedRect: rect.insetBy(dx: side * 0.045, dy: side * 0.045), xRadius: side * 0.22, yRadius: side * 0.22)
        NSGradient(starting: NSColor(calibratedRed: 0.10, green: 0.23, blue: 0.28, alpha: 1), ending: NSColor(calibratedRed: 0.04, green: 0.10, blue: 0.14, alpha: 1))!.draw(in: shape, angle: -60)
        let config = NSImage.SymbolConfiguration(pointSize: side * 0.53, weight: .medium)
            .applying(.init(paletteColors: [NSColor(calibratedRed: 0.22, green: 0.88, blue: 0.74, alpha: 1)]))
        if let symbol = NSImage(systemSymbolName: "sparkles.rectangle.stack.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let ratio = min(side * 0.64 / symbol.size.width, side * 0.64 / symbol.size.height)
            let symbolSize = NSSize(width: symbol.size.width * ratio, height: symbol.size.height * ratio)
            symbol.draw(in: NSRect(x: (side - symbolSize.width) / 2, y: (side - symbolSize.height) / 2, width: symbolSize.width, height: symbolSize.height))
        }
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(filename))
    }
}
