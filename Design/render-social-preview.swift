// Renders the GitHub social preview (Settings → General → Social preview): 1280×640 PNG.
// Usage: swift Design/render-social-preview.swift   (run from the repo root)
//
// Uses Design/icon-1024.png, exported from the compiled AppIcon.icns.
import AppKit

let size = CGSize(width: 1280, height: 640)
let out = URL(fileURLWithPath: "Design/social-preview.png")
let icon = NSImage(contentsOfFile: "Design/icon-1024.png")!

let indigo = NSColor(srgbRed: 0.298, green: 0.361, blue: 0.941, alpha: 1)
let navy = NSColor(srgbRed: 0.110, green: 0.102, blue: 0.412, alpha: 1)
let gold = NSColor(srgbRed: 1.0, green: 0.78, blue: 0.30, alpha: 1)

func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight = .medium, color: NSColor) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        .applying(.init(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
}

func draw(in rect: CGRect) {
    // Background: the icon's indigo → navy, with a soft "light spot" behind the icon.
    NSGradient(colors: [indigo, navy])!.draw(in: rect, angle: -70)
    let glowCenter = CGPoint(x: 330, y: 350)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.20), NSColor.white.withAlphaComponent(0)])!
        .draw(fromCenter: glowCenter, radius: 0, toCenter: glowCenter, radius: 330, options: [])

    // A menu bar along the top, with the magnifying glass highlighted.
    let barHeight: CGFloat = 52
    NSColor.white.withAlphaComponent(0.10).setFill()
    CGRect(x: 0, y: 0, width: rect.width, height: barHeight).fill()

    var x = rect.width - 40
    let clock = NSAttributedString(string: "Mon 9:41", attributes: [
        .font: NSFont.systemFont(ofSize: 22, weight: .medium),
        .foregroundColor: NSColor.white.withAlphaComponent(0.9),
    ])
    x -= clock.size().width
    clock.draw(at: CGPoint(x: x, y: (barHeight - clock.size().height) / 2))
    for name in ["battery.75percent", "wifi"] {
        let image = symbol(name, pointSize: 22, color: NSColor.white.withAlphaComponent(0.85))
        x -= 28 + image.size.width
        image.draw(in: CGRect(x: x, y: (barHeight - image.size.height) / 2, width: image.size.width, height: image.size.height))
    }
    let glass = symbol("magnifyingglass", pointSize: 23, weight: .semibold, color: .white)
    x -= 36 + glass.size.width
    let pill = CGRect(x: x - 14, y: 7, width: glass.size.width + 28, height: barHeight - 14)
    NSColor.white.withAlphaComponent(0.28).setFill()
    NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
    glass.draw(in: CGRect(x: x, y: (barHeight - glass.size.height) / 2, width: glass.size.width, height: glass.size.height))

    // Icon, with a soft shadow.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 40
    shadow.shadowOffset = CGSize(width: 0, height: -14) // flipped context: positive y is down
    shadow.set()
    icon.draw(in: CGRect(x: 150, y: 190, width: 360, height: 360), from: .zero, operation: .sourceOver,
              fraction: 1, respectFlipped: true, hints: nil)
    NSGraphicsContext.restoreGraphicsState()

    // Text.
    let textX: CGFloat = 570, textWidth: CGFloat = 640
    let title = NSAttributedString(string: "LightSpot", attributes: [
        .font: NSFont.systemFont(ofSize: 96, weight: .bold),
        .foregroundColor: NSColor.white,
        .kern: -1.5,
    ])
    title.draw(at: CGPoint(x: textX, y: 214))

    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 4
    let tagline = NSAttributedString(string: "Returns the clickable Spotlight search button to the macOS 27 menu bar.", attributes: [
        .font: NSFont.systemFont(ofSize: 34, weight: .regular),
        .foregroundColor: NSColor.white.withAlphaComponent(0.85),
        .paragraphStyle: paragraph,
    ])
    tagline.draw(with: CGRect(x: textX, y: 340, width: textWidth, height: 120), options: [.usesLineFragmentOrigin])

    let footnote = NSMutableAttributedString(string: "✦  ", attributes: [
        .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
        .foregroundColor: gold,
    ])
    footnote.append(NSAttributedString(string: "Free and open source", attributes: [
        .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
        .foregroundColor: NSColor.white.withAlphaComponent(0.7),
    ]))
    footnote.draw(at: CGPoint(x: textX, y: 470))
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
// Flipped context so layout reads top-down, as in render-dmg-background.swift.
let cg = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
cg.translateBy(x: 0, y: size.height)
cg.scaleBy(x: 1, y: -1)
NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
draw(in: CGRect(origin: .zero, size: size))
NSGraphicsContext.restoreGraphicsState()

try rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote \(out.relativePath)")
