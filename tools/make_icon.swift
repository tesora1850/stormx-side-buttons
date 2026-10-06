// 앱 아이콘 만들기: swift tools/make_icon.swift → AppIcon.icns
import AppKit

func render(_ size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = size * 0.1
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.225, yRadius: rect.width * 0.225)
    NSGradient(colors: [NSColor(red: 0.20, green: 0.45, blue: 1.0, alpha: 1), NSColor(red: 0.42, green: 0.25, blue: 0.95, alpha: 1)])!
        .draw(in: path, angle: -60)
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.42, weight: .semibold)
        .applying(.init(paletteColors: [.white]))
    if let sym = NSImage(systemSymbolName: "computermouse.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let s = sym.size
        sym.draw(in: NSRect(x: (size - s.width) / 2 - size * 0.06, y: (size - s.height) / 2, width: s.width, height: s.height))
    }
    // 옆 버튼 표시
    NSColor.white.withAlphaComponent(0.9).setFill()
    for dy in [0.08, -0.04] {
        NSBezierPath(roundedRect: NSRect(x: size * 0.66, y: size * (0.5 + dy), width: size * 0.07, height: size * 0.09),
                     xRadius: size * 0.02, yRadius: size * 0.02).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let dir = URL(fileURLWithPath: "build/AppIcon.iconset")
try? FileManager.default.removeItem(at: dir)
try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! render(CGFloat(base * scale)).representation(using: .png, properties: [:])!.write(to: dir.appendingPathComponent(name))
    }
}
