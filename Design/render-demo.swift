// Renders the README demo: a drawn menu bar where the cursor clicks LightSpot's magnifying
// glass and the Spotlight search bar opens. Writes PNG frames; gifski turns them into the GIF.
//
// Usage (from the repo root):
//   swift Design/render-demo.swift build/demo-frames
//   gifski --fps 30 --width 1312 --quality 90 -o Design/demo.gif build/demo-frames/*.png
import AppKit

let size = CGSize(width: 820, height: 340) // points; rendered at 2x
let scale: CGFloat = 2
let fps = 30.0
let duration = 6.0
let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/demo-frames", isDirectory: true)
try? FileManager.default.removeItem(at: outDir)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let indigo = NSColor(srgbRed: 0.298, green: 0.361, blue: 0.941, alpha: 1)
let navy = NSColor(srgbRed: 0.110, green: 0.102, blue: 0.412, alpha: 1)
let query = "Calendar"

// MARK: Timeline (seconds)

func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
func progress(_ t: Double, _ start: Double, _ end: Double) -> Double { clamp((t - start) / (end - start)) }
func easeInOut(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
func mix(_ a: CGFloat, _ b: CGFloat, _ x: Double) -> CGFloat { a + (b - a) * CGFloat(x) }

let barHeight: CGFloat = 30
let cursorRest = CGPoint(x: 560, y: 285)
let typeStart = 2.25, typeStep = 0.13
let closeStart = 4.9

// MARK: Drawing helpers

func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight = .medium, color: NSColor) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        .applying(.init(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
}

func drawCentered(_ image: NSImage, at center: CGPoint) {
    image.draw(in: CGRect(x: center.x - image.size.width / 2, y: center.y - image.size.height / 2,
                          width: image.size.width, height: image.size.height),
               from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
}

func text(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) -> NSAttributedString {
    NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
}

/// The standard arrow pointer, tip at `tip`.
func drawCursor(at tip: CGPoint, pressed: Bool) {
    let s: CGFloat = pressed ? 1.12 : 1.2
    let points: [CGPoint] = [(0, 0), (0, 17), (4.2, 13.2), (7, 19.6), (9.6, 18.5), (6.9, 12.2), (12.4, 12.2)]
        .map { CGPoint(x: tip.x + $0.0 * s, y: tip.y + $0.1 * s) }
    let path = NSBezierPath()
    path.move(to: points[0])
    points.dropFirst().forEach { path.line(to: $0) }
    path.close()
    path.lineJoinStyle = .round
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 3
    shadow.shadowOffset = CGSize(width: 0, height: -1.5)
    shadow.set()
    NSColor.white.setFill()
    let outline = path.copy() as! NSBezierPath
    outline.lineWidth = 3
    NSColor.white.setStroke()
    outline.stroke()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.black.setFill()
    path.fill()
}

// The magnifying glass's place in the menu bar, worked out once from the right-hand items.
let clock = text("Mon 9:41", size: 13.5, weight: .medium, color: NSColor.white.withAlphaComponent(0.95))
let battery = symbol("battery.75percent", pointSize: 15, color: NSColor.white.withAlphaComponent(0.9))
let wifi = symbol("wifi", pointSize: 14, color: NSColor.white.withAlphaComponent(0.9))
let glass = symbol("magnifyingglass", pointSize: 14, weight: .semibold, color: .white)
let clockX = size.width - 16 - clock.size().width
let batteryCenter = CGPoint(x: clockX - 18 - battery.size.width / 2, y: barHeight / 2)
let wifiCenter = CGPoint(x: batteryCenter.x - battery.size.width / 2 - 18 - wifi.size.width / 2, y: barHeight / 2)
let glassCenter = CGPoint(x: wifiCenter.x - wifi.size.width / 2 - 22 - glass.size.width / 2, y: barHeight / 2)
let cursorTarget = CGPoint(x: glassCenter.x + 3, y: glassCenter.y + 4) // lower right, so the glass stays visible

func drawFrame(at t: Double, in rect: CGRect) {
    // Desktop.
    NSGradient(colors: [indigo, navy])!.draw(in: rect, angle: -70)
    let glowCenter = CGPoint(x: 540, y: 90)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.16), NSColor.white.withAlphaComponent(0)])!
        .draw(fromCenter: glowCenter, radius: 0, toCenter: glowCenter, radius: 360, options: [])

    // Menu bar.
    NSColor.white.withAlphaComponent(0.13).setFill()
    CGRect(x: 0, y: 0, width: rect.width, height: barHeight).fill()

    var x: CGFloat = 18
    let apple = symbol("apple.logo", pointSize: 14, color: .white)
    drawCentered(apple, at: CGPoint(x: x + apple.size.width / 2, y: barHeight / 2 - 0.5))
    x += apple.size.width + 20
    for (i, item) in ["Finder", "File", "Edit", "View", "Go", "Window", "Help"].enumerated() {
        let label = text(item, size: 13.5, weight: i == 0 ? .bold : .regular, color: NSColor.white.withAlphaComponent(0.95))
        label.draw(at: CGPoint(x: x, y: (barHeight - label.size().height) / 2))
        x += label.size().width + 19
    }
    clock.draw(at: CGPoint(x: clockX, y: (barHeight - clock.size().height) / 2))
    drawCentered(battery, at: batteryCenter)
    drawCentered(wifi, at: wifiCenter)

    // Cursor path: rest → glass, hold while the search bar is open, then back to rest.
    let toGlass = easeInOut(progress(t, 0.35, 1.45))
    let back = easeInOut(progress(t, closeStart + 0.35, duration - 0.15))
    let cursor = CGPoint(x: mix(mix(cursorRest.x, cursorTarget.x, toGlass), cursorRest.x, back),
                         y: mix(mix(cursorRest.y, cursorTarget.y, toGlass), cursorRest.y, back))
    let pressed = t >= 1.55 && t < 1.68
    let menuOpen = t >= 1.6 && t < closeStart

    // The highlight behind the glass: on while the pointer is over it, solid while search is open.
    let hover = t >= 1.35 && t < closeStart + 0.35
    if hover || menuOpen {
        let pill = CGRect(x: glassCenter.x - 17, y: 4, width: 34, height: barHeight - 8)
        NSColor.white.withAlphaComponent(menuOpen ? 0.32 : 0.2).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
    }
    drawCentered(glass, at: glassCenter)

    // Spotlight search bar.
    let appear = easeOut(progress(t, 1.62, 1.9))
    let disappear = progress(t, closeStart, closeStart + 0.22)
    let opacity = CGFloat(appear * (1 - disappear))
    if opacity > 0 {
        let s = mix(0.94, 1, appear) * mix(1, 0.97, disappear)
        let barSize = CGSize(width: 520 * s, height: 56 * s)
        let bar = CGRect(x: (rect.width - barSize.width) / 2, y: 170 - barSize.height / 2, width: barSize.width, height: barSize.height)

        NSGraphicsContext.current!.cgContext.setAlpha(opacity)
        NSGraphicsContext.current!.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(srgbRed: 0.03, green: 0.02, blue: 0.16, alpha: 0.55)
        shadow.shadowBlurRadius = 40
        shadow.shadowOffset = CGSize(width: 0, height: -16)
        shadow.set()
        NSColor(srgbRed: 0.965, green: 0.968, blue: 1, alpha: 0.94).setFill()
        let shape = NSBezierPath(roundedRect: bar, xRadius: bar.height / 2, yRadius: bar.height / 2)
        shape.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.white.withAlphaComponent(0.8).setStroke()
        shape.lineWidth = 1
        shape.stroke()

        let ink = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.17, alpha: 1)
        let lens = symbol("magnifyingglass", pointSize: 21 * s, weight: .medium, color: ink.withAlphaComponent(0.5))
        drawCentered(lens, at: CGPoint(x: bar.minX + 34 * s, y: bar.midY))

        let typed = min(query.count, max(0, Int(((t - typeStart) / typeStep).rounded(.down)) + 1))
        let textX = bar.minX + 58 * s
        let fontSize = 23 * s
        let typedText = text(String(query.prefix(typed)), size: fontSize, color: ink)
        if typed == 0 {
            let placeholder = text("Spotlight Search", size: fontSize, color: ink.withAlphaComponent(0.38))
            placeholder.draw(at: CGPoint(x: textX + 3, y: bar.midY - placeholder.size().height / 2))
        } else {
            typedText.draw(at: CGPoint(x: textX, y: bar.midY - typedText.size().height / 2))
        }
        // Caret: solid while typing, blinking otherwise.
        let typing = t >= typeStart && t < typeStart + Double(query.count) * typeStep + 0.3
        if typing || Int((t - 1.6) / 0.53) % 2 == 0 {
            indigo.setFill()
            let caretX = textX + (typed == 0 ? 0 : typedText.size().width + 1.5)
            CGRect(x: caretX, y: bar.midY - 13 * s, width: 2.2, height: 26 * s).fill()
        }
        NSGraphicsContext.current!.cgContext.endTransparencyLayer()
        NSGraphicsContext.current!.cgContext.setAlpha(1)
    }

    drawCursor(at: cursor, pressed: pressed)
}

let frameCount = Int(duration * fps)
for i in 0..<frameCount {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    // Flipped context so layout reads top-down, as in the other render scripts.
    let cg = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    cg.translateBy(x: 0, y: size.height)
    cg.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    drawFrame(at: Double(i) / fps, in: CGRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    let name = String(format: "frame-%03d.png", i)
    try rep.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent(name))
}
print("wrote \(frameCount) frames to \(outDir.relativePath)")
