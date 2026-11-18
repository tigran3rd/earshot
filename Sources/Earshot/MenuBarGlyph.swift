import AppKit

/// The menu bar version of the logo: a tiny VU meter, drawn as a template image so it
/// follows the menu bar's light/dark appearance.
enum MenuBarGlyph {
    static let image: NSImage = {
        let size = NSSize(width: 20, height: 15)
        let img = NSImage(size: size, flipped: false) { rect in
            NSColor.black.set()
            // Case.
            let body = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: 3.5, yRadius: 3.5)
            body.lineWidth = 1.5
            body.stroke()
            // Scale arc.
            let pivot = NSPoint(x: rect.midX, y: 1.5)
            let arc = NSBezierPath()
            arc.appendArc(withCenter: pivot, radius: 10, startAngle: 145, endAngle: 35, clockwise: true)
            arc.lineWidth = 1.6
            arc.stroke()
            // Needle.
            let a = 62.0 * .pi / 180
            let needle = NSBezierPath()
            needle.move(to: pivot)
            needle.line(to: NSPoint(x: pivot.x + cos(a) * 11.5, y: pivot.y + sin(a) * 11.5))
            needle.lineWidth = 1.4
            needle.lineCapStyle = .round
            needle.stroke()
            return true
        }
        img.isTemplate = true
        return img
    }()
}
