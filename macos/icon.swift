import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let space = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    let rgb = [16, 8, 0].map { CGFloat((hex >> $0) & 255) / 255 }
    return CGColor(colorSpace: space, components: rgb + [alpha])!
}
func tile(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}
func fill(_ context: CGContext, _ path: CGPath, _ tint: CGColor) {
    context.addPath(path)
    context.setFillColor(tint)
    context.fillPath()
}
func gradient(_ context: CGContext, _ path: CGPath, _ top: UInt32, _ bottom: UInt32,
              from: CGPoint, to: CGPoint) {
    context.saveGState()
    context.addPath(path)
    context.clip()
    let colors = [color(top), color(bottom)] as CFArray
    let paint = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
    context.drawLinearGradient(paint, start: from, end: to,
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()
}

func render(_ size: Int) -> CGImage {
    let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                      bytesPerRow: 0, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(size) / 1024
    c.scaleBy(x: scale, y: scale)
    c.setAllowsAntialiasing(true)
    let shell = tile(CGRect(x: 90, y: 94, width: 844, height: 844), 192)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -12), blur: 23, color: color(0x051b1d, 0.46))
    fill(c, shell, color(0x102f32))
    c.restoreGState()
    gradient(c, shell, 0x285e5d, 0x10282e, from: CGPoint(x: 230, y: 938), to: CGPoint(x: 760, y: 94))
    if size >= 64 {
        c.addPath(tile(CGRect(x: 97, y: 101, width: 830, height: 830), 186))
        c.setLineWidth(5)
        c.setStrokeColor(color(0xbbfff0, 0.26))
        c.strokePath()
    }
    let keyBase = tile(CGRect(x: 261, y: 260, width: 502, height: 475), 114)
    c.saveGState()
    if size >= 32 {
        c.setShadow(offset: CGSize(width: 0, height: -22), blur: 23, color: color(0x031f24, 0.63))
    }
    fill(c, keyBase, color(0x509f85))
    c.restoreGState()
    let keyTop = tile(CGRect(x: 261, y: 295, width: 502, height: 452), 112)
    gradient(c, keyTop, 0xe3ffcf, 0x8edbbb, from: CGPoint(x: 318, y: 760), to: CGPoint(x: 663, y: 295))

    // The diagonal stem and right-angle head stay clear at menu-sized scales.
    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: 407, y: 416))
    arrow.addLine(to: CGPoint(x: 609, y: 618))
    arrow.move(to: CGPoint(x: 461, y: 618))
    arrow.addLine(to: CGPoint(x: 609, y: 618))
    arrow.addLine(to: CGPoint(x: 609, y: 470))
    c.addPath(arrow)
    c.setStrokeColor(color(0x163c39))
    c.setLineWidth(60)
    c.setLineJoin(.round)
    c.setLineCap(.round)
    c.strokePath()
    return c.makeImage()!
}

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
var images: [Int: CGImage] = [:]
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let image = images[pixels] ?? render(pixels)
        images[pixels] = image
        let suffix = scale == 2 ? "@2x" : ""
        let url = folder.appendingPathComponent("icon_\(points)x\(points)\(suffix).png")
        let writer = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(writer, image, nil)
        guard CGImageDestinationFinalize(writer) else { fatalError("Could not write \(url.path)") }
    }
}
