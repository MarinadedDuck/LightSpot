// Renders the DMG window background at 1x and 2x, then combines them into one HiDPI TIFF.
// Usage: swift Design/render-dmg-background.swift   (run from the repo root)
//
// Layout (points, origin top-left): window 660×400, app icon centred at (170, 190),
// Applications at (490, 190), icon size 128. Keep scripts/dmg-settings.py in sync.
import AppKit

let size = CGSize(width: 660, height: 400)
let outDir = URL(fileURLWithPath: "Design/dmg", isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let indigo = NSColor(srgbRed: 0.298, green: 0.361, blue: 0.941, alpha: 1)
let navy = NSColor(srgbRed: 0.110, green: 0.102, blue: 0.412, alpha: 1)
let ink = NSColor(srgbRed: 0.13, green: 0.14, blue: 0.24, alpha: 1)

func draw(in rect: CGRect) {
    // Base: soft cool white.
    NSGradient(colors: [
        NSColor(srgbRed: 0.975, green: 0.978, blue: 1.0, alpha: 1),
        NSColor(srgbRed: 0.925, green: 0.932, blue: 0.985, alpha: 1),
    ])!.draw(in: rect, angle: 90)

    // A "light spot" glow behind each icon.
    for (center, alpha) in [(CGPoint(x: 170, y: 190), 0.22), (CGPoint(x: 490, y: 190), 0.10)] {
        let glow = NSGradient(colors: [indigo.withAlphaComponent(alpha), indigo.withAlphaComponent(0)])!
        glow.draw(fromCenter: center, radius: 0, toCenter: center, radius: 150, options: [])
    }

    // Header.
    let title = NSAttributedString(string: "LightSpot", attributes: [
        .font: NSFont.systemFont(ofSize: 26, weight: .bold),
        .foregroundColor: ink,
    ])
    let subtitle = NSAttributedString(string: "Your Spotlight button, back in the menu bar.", attributes: [
        .font: NSFont.systemFont(ofSize: 13, weight: .regular),
        .foregroundColor: ink.withAlphaComponent(0.55),
    ])
    let tSize = title.size(), sSize = subtitle.size()
    title.draw(at: CGPoint(x: (rect.width - tSize.width) / 2, y: 34))
    subtitle.draw(at: CGPoint(x: (rect.width - sSize.width) / 2, y: 34 + tSize.height + 2))

    // Arrow between the icons.
    let start = CGPoint(x: 262, y: 190), end = CGPoint(x: 392, y: 190)
    let control1 = CGPoint(x: 300, y: 160), control2 = CGPoint(x: 354, y: 160)
    let arrow = NSBezierPath()
    arrow.move(to: start)
    arrow.curve(to: end, controlPoint1: control1, controlPoint2: control2)
    arrow.lineWidth = 5
    arrow.lineCapStyle = .round
    arrow.setLineDash([0.1, 13], count: 2, phase: 0)
    indigo.withAlphaComponent(0.85).setStroke()
    arrow.stroke()

    // The head points along the last stretch of dots (from 85% along the curve to its end),
    // which reads better than the exact tangent at the end point.
    func point(at t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(x: a * start.x + b * control1.x + c * control2.x + d * end.x,
                       y: a * start.y + b * control1.y + c * control2.y + d * end.y)
    }
    let from = point(at: 0.85)
    let angle = atan2(end.y - from.y, end.x - from.x)
    let tip = CGPoint(x: end.x + 8 * cos(angle), y: end.y + 8 * sin(angle))
    let armLength: CGFloat = 17, spread: CGFloat = .pi / 6 // 30° each side
    func arm(_ side: CGFloat) -> CGPoint {
        let a = angle + .pi + side * spread
        return CGPoint(x: tip.x + armLength * cos(a), y: tip.y + armLength * sin(a))
    }
    let head = NSBezierPath()
    head.move(to: arm(-1))
    head.line(to: tip)
    head.line(to: arm(1))
    head.lineWidth = 5
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    // Footer instruction.
    let hint = NSAttributedString(string: "Drag LightSpot onto Applications to install", attributes: [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: ink.withAlphaComponent(0.6),
    ])
    let hSize = hint.size()
    hint.draw(at: CGPoint(x: (rect.width - hSize.width) / 2, y: 330))

    // Hairline accent at the bottom, using the icon colours.
    NSGradient(colors: [indigo, navy])!.draw(in: CGRect(x: 0, y: rect.height - 4, width: rect.width, height: 4), angle: 0)
}

func render(scale: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                               pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size // points, so the 2x rep carries 144 dpi
    NSGraphicsContext.saveGraphicsState()
    // Use a flipped context so layout reads top-down and text still renders upright.
    let cg = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    cg.translateBy(x: 0, y: size.height) // the rep already maps points to pixels
    cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    draw(in: CGRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (scale, name) in [(1.0, "background.png"), (2.0, "background@2x.png")] {
    let data = render(scale: scale).representation(using: .png, properties: [:])!
    try data.write(to: outDir.appendingPathComponent(name))
    print("wrote Design/dmg/\(name)")
}
