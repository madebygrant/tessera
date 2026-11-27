// Renders the Triad app icon into an .iconset folder for iconutil:
//   swift Resources/make-icon.swift build/AppIcon.iconset
// Geometry is on a 1024 grid, y down, matching the design canvas.
import AppKit

let accent = CGColor(srgbRed: 0xE3 / 255, green: 0xA8 / 255, blue: 0x3B / 255, alpha: 1)
let ink = CGColor(srgbRed: 0x0B / 255, green: 0x0B / 255, blue: 0x0D / 255, alpha: 1)

func polygon(_ points: [(CGFloat, CGFloat)]) -> CGPath {
    let path = CGMutablePath()
    path.addLines(between: points.map { CGPoint(x: $0.0, y: $0.1) })
    path.closeSubpath()
    return path
}

let topLeft = polygon([(284, 236), (536, 236), (536, 548), (488, 596), (236, 596), (236, 284)])
let topRight = polygon([(608, 236), (788, 236), (788, 548), (740, 596), (560, 596), (560, 284)])
let bottom = polygon([(284, 620), (788, 620), (788, 740), (740, 788), (236, 788), (236, 668)])

// Hatching and corner brackets turn to noise below 128 px, so small sizes drop them.
func render(_ pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    let scale = CGFloat(pixels) / 1024
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: scale, y: -scale)
    let detailed = pixels >= 128

    ctx.addPath(CGPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), cornerWidth: 186, cornerHeight: 186, transform: nil))
    ctx.setFillColor(ink)
    ctx.fillPath()

    ctx.setLineJoin(.miter)
    if detailed {
        ctx.setStrokeColor(accent.copy(alpha: 0.6)!)
        ctx.setLineWidth(12)
        for corner in [[(172, 252), (172, 172), (252, 172)], [(772, 172), (852, 172), (852, 252)],
                       [(172, 772), (172, 852), (252, 852)], [(852, 772), (852, 852), (772, 852)]] {
            ctx.addLines(between: corner.map { CGPoint(x: $0.0, y: $0.1) })
        }
        ctx.strokePath()
    }

    ctx.addPath(topLeft)
    ctx.setFillColor(accent)
    ctx.fillPath()

    ctx.addPath(topRight)
    ctx.setStrokeColor(accent)
    ctx.setLineWidth(detailed ? 16 : 26)
    ctx.strokePath()

    if detailed {
        ctx.saveGState()
        ctx.addPath(bottom)
        ctx.clip()
        ctx.setStrokeColor(accent.copy(alpha: 0.45)!)
        ctx.setLineWidth(8)
        for x in stride(from: CGFloat(236), through: 1000, by: 36) {
            ctx.move(to: CGPoint(x: x, y: 620))
            ctx.addLine(to: CGPoint(x: x - 168, y: 788))
        }
        ctx.strokePath()
        ctx.restoreGState()
        ctx.addPath(bottom)
        ctx.setStrokeColor(accent.copy(alpha: 0.8)!)
        ctx.setLineWidth(10)
        ctx.strokePath()
    } else {
        ctx.addPath(bottom)
        ctx.setFillColor(accent.copy(alpha: 0.5)!)
        ctx.fillPath()
    }
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset")
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try render(points).write(to: out.appending(path: "icon_\(points)x\(points).png"))
    try render(points * 2).write(to: out.appending(path: "icon_\(points)x\(points)@2x.png"))
}
