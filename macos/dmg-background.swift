import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let width = 720
let height = 440
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
func ink(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}
func rect(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
    CGRect(x: x, y: CGFloat(height) - top - h, width: w, height: h)
}
func point(_ x: CGFloat, _ top: CGFloat) -> CGPoint {
    CGPoint(x: x, y: CGFloat(height) - top)
}
func text(_ value: String, _ x: CGFloat, _ top: CGFloat, _ size: CGFloat,
          _ color: UInt32, weight: NSFont.Weight = .regular, tracking: CGFloat = 0) {
    let line = NSAttributedString(string: value, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: ink(color), .kern: tracking,
    ])
    line.draw(at: point(x, top + ceil(line.size().height)))
}
func render(_ scale: Int) -> CGImage {
    let c = CGContext(data: nil, width: width * scale, height: height * scale,
                      bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
    defer { NSGraphicsContext.restoreGraphicsState() }

    c.setFillColor(ink(0xe9f4ef).cgColor)
    c.fill(rect(0, 0, 720, 440))
    let header = rect(0, 0, 720, 148)
    c.saveGState()
    c.clip(to: header)
    let colors = [ink(0x102e31).cgColor, ink(0x28635e).cgColor] as CFArray
    c.drawLinearGradient(CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0, 1])!,
                         start: point(180, 130), end: point(720, 12),
                         options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    c.setLineWidth(1)
    c.setStrokeColor(ink(0x86ddbb).withAlphaComponent(0.14).cgColor)
    for offset in stride(from: 0, through: 102, by: 17) {
        c.move(to: point(CGFloat(454 + offset), 148))
        c.addLine(to: point(CGFloat(604 + offset), 0))
    }
    c.strokePath()
    c.restoreGState()
    text("MACOS INSTALLER", 42, 21, 11, 0xafedca, weight: .semibold, tracking: 2.2)
    text("QuickLaunch", 40, 44, 40, 0xf2fffa, weight: .bold, tracking: -1.3)
    text("Drag QuickLaunch into Applications to install.", 43, 105, 15, 0xe0f6ec)

    // Finder overlays the actual app and Applications shortcut at these centers.
    for x in [CGFloat(200), CGFloat(520)] {
        let well = CGPath(roundedRect: rect(x - 74, 178, 148, 148),
                          cornerWidth: 27, cornerHeight: 27, transform: nil)
        c.addPath(well)
        c.setFillColor(ink(0xf6fcf8).cgColor)
        c.setStrokeColor(ink(0xc9e2d7).cgColor)
        c.setLineWidth(1.5)
        c.drawPath(using: .fillStroke)
    }
    c.setStrokeColor(ink(0x287060).cgColor)
    c.setLineCap(.round)
    c.setLineJoin(.round)
    c.setLineWidth(5)
    c.move(to: point(336, 252)); c.addLine(to: point(382, 252))
    c.move(to: point(368, 238)); c.addLine(to: point(382, 252)); c.addLine(to: point(368, 266))
    c.strokePath()

    c.setFillColor(ink(0xd6e9e0).cgColor)
    c.fill(rect(42, 379, 636, 1))
    text("AFTER INSTALL", 44, 402, 11, 0x305e53, weight: .semibold, tracking: 1.6)
    text("Set your targets, then press ⌘F12.", 163, 399, 14, 0x294842, weight: .medium)
    return c.makeImage()!
}

let base = URL(fileURLWithPath: CommandLine.arguments[1])
for scale in [1, 2] {
    let path = scale == 1 ? base : base.deletingLastPathComponent()
        .appendingPathComponent(base.deletingPathExtension().lastPathComponent + "@2x.png")
    let writer = CGImageDestinationCreateWithURL(path as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(writer, render(scale), nil)
    guard CGImageDestinationFinalize(writer) else { fatalError("Could not write \(path.path)") }
}
