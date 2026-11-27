import AppKit

// The Triad mark for the menu bar. A template image, so macOS tints it for
// light and dark bars and the highlighted state.
enum StatusIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            func polygon(_ points: [(CGFloat, CGFloat)]) -> NSBezierPath {
                let path = NSBezierPath()
                path.move(to: NSPoint(x: points[0].0, y: points[0].1))
                for p in points.dropFirst() { path.line(to: NSPoint(x: p.0, y: p.1)) }
                path.close()
                path.lineJoinStyle = .miter
                return path
            }
            NSColor.black.setFill()
            polygon([(3, 1.8), (9, 1.8), (9, 9.6), (7.8, 10.8), (1.8, 10.8), (1.8, 3)]).fill()

            let framed = polygon([(11.8, 2.5), (15.5, 2.5), (15.5, 9.1), (14.4, 10.1), (10.6, 10.1), (10.6, 3.6)])
            framed.lineWidth = 1.3
            NSColor.black.setStroke()
            framed.stroke()

            NSColor.black.withAlphaComponent(0.55).setFill()
            polygon([(3, 12.2), (16.2, 12.2), (16.2, 15), (15, 16.2), (1.8, 16.2), (1.8, 13.4)]).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Tessera"
        return image
    }
}
