import AppKit
import CoreGraphics

func createIconImage(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        img.unlockFocus()
        return img
    }

    ctx.saveGState()

    // Base Dimensions relative to 1024
    let scale = size / 1024.0

    // Standard macOS squircle bounds (inset 80px on 1024 canvas for shadow and border)
    let squircleInset: CGFloat = 80.0 * scale
    let squircleRect = CGRect(x: squircleInset, y: squircleInset, width: size - (squircleInset * 2), height: size - (squircleInset * 2))
    let cornerRadius: CGFloat = 190.0 * scale
    let squirclePath = CGPath(roundedRect: squircleRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

    // Outer subtle drop shadow
    ctx.setShadow(offset: CGSize(width: 0, height: -12.0 * scale), blur: 24.0 * scale, color: NSColor.black.withAlphaComponent(0.45).cgColor)

    // Clip to squircle for background gradient
    ctx.addPath(squirclePath)
    ctx.fillPath()

    ctx.restoreGState()
    ctx.saveGState()

    ctx.addPath(squirclePath)
    ctx.clip()

    // 1. Background Gradient: Deep rich indigo / midnight slate
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(red: 0.08, green: 0.10, blue: 0.18, alpha: 1.0).cgColor, // Deep Slate
        NSColor(red: 0.11, green: 0.13, blue: 0.28, alpha: 1.0).cgColor, // Midnight Indigo
        NSColor(red: 0.20, green: 0.16, blue: 0.42, alpha: 1.0).cgColor  // Violet / Purple
    ] as CFArray
    let bgLocations: [CGFloat] = [0.0, 0.55, 1.0]
    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: bgLocations) {
        ctx.drawLinearGradient(bgGradient, start: CGPoint(x: size / 2, y: size - squircleInset), end: CGPoint(x: size / 2, y: squircleInset), options: [])
    }

    // 2. Subtle central radial glow
    let glowColors = [
        NSColor(red: 0.35, green: 0.30, blue: 0.75, alpha: 0.35).cgColor,
        NSColor(red: 0.15, green: 0.20, blue: 0.50, alpha: 0.0).cgColor
    ] as CFArray
    if let glowGradient = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
        let center = CGPoint(x: size / 2, y: size / 2)
        ctx.drawRadialGradient(glowGradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: 360.0 * scale, options: [])
    }

    // 3. Central Soundwave Ring Container
    let ringRadius: CGFloat = 260.0 * scale
    let ringCenter = CGPoint(x: size / 2, y: (size / 2) + (10.0 * scale))
    let ringRect = CGRect(x: ringCenter.x - ringRadius, y: ringCenter.y - ringRadius, width: ringRadius * 2, height: ringRadius * 2)

    // Dark circular backdrop for waveform
    ctx.setFillColor(NSColor(red: 0.05, green: 0.06, blue: 0.12, alpha: 0.75).cgColor)
    ctx.fillEllipse(in: ringRect)

    // Outer ring border with glowing cyan/violet gradient
    let ringPath = CGPath(ellipseIn: ringRect, transform: nil)
    ctx.setLineWidth(5.0 * scale)
    ctx.setStrokeColor(NSColor(red: 0.40, green: 0.55, blue: 0.95, alpha: 0.45).cgColor)
    ctx.addPath(ringPath)
    ctx.strokePath()

    // 4. Equalizer / Soundwave Bars
    // 9 symmetrical vertical soundwave bars
    let barHeights: [CGFloat] = [70, 120, 190, 280, 360, 280, 190, 120, 70].map { $0 * scale }
    let barWidth: CGFloat = 22.0 * scale
    let barSpacing: CGFloat = 16.0 * scale
    let totalWaveformWidth = (CGFloat(barHeights.count) * barWidth) + (CGFloat(barHeights.count - 1) * barSpacing)
    let waveStartX = ringCenter.x - (totalWaveformWidth / 2)

    let waveColors = [
        NSColor(red: 0.18, green: 0.82, blue: 0.95, alpha: 1.0).cgColor, // Cyan top
        NSColor(red: 0.55, green: 0.38, blue: 0.95, alpha: 1.0).cgColor, // Purple mid
        NSColor(red: 0.96, green: 0.30, blue: 0.45, alpha: 1.0).cgColor  // Coral bottom
    ] as CFArray
    let waveGradient = CGGradient(colorsSpace: colorSpace, colors: waveColors, locations: [0.0, 0.5, 1.0])

    for (i, h) in barHeights.enumerated() {
        let x = waveStartX + (CGFloat(i) * (barWidth + barSpacing))
        let y = ringCenter.y - (h / 2)
        let barRect = CGRect(x: x, y: y, width: barWidth, height: h)
        let barPath = CGPath(roundedRect: barRect, cornerWidth: barWidth / 2, cornerHeight: barWidth / 2, transform: nil)

        ctx.saveGState()
        ctx.addPath(barPath)
        ctx.clip()
        if let wg = waveGradient {
            ctx.drawLinearGradient(wg, start: CGPoint(x: x, y: y + h), end: CGPoint(x: x, y: y), options: [])
        }
        ctx.restoreGState()
    }

    // 5. Glowing Red "REC" Indicator Dot
    let recDotRadius: CGFloat = 26.0 * scale
    let recDotCenter = CGPoint(x: ringCenter.x + (ringRadius * 0.65), y: ringCenter.y + (ringRadius * 0.65))
    let recDotRect = CGRect(x: recDotCenter.x - recDotRadius, y: recDotCenter.y - recDotRadius, width: recDotRadius * 2, height: recDotRadius * 2)

    // Outer Red Glow
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 20.0 * scale, color: NSColor(red: 0.95, green: 0.20, blue: 0.25, alpha: 0.95).cgColor)
    ctx.setFillColor(NSColor(red: 0.98, green: 0.25, blue: 0.30, alpha: 1.0).cgColor)
    ctx.fillEllipse(in: recDotRect)
    ctx.restoreGState()

    // Inner bright specular highlight on dot
    let dotHighlightRadius = recDotRadius * 0.45
    let dotHighlightRect = CGRect(x: recDotCenter.x - (dotHighlightRadius * 0.8), y: recDotCenter.y + (dotHighlightRadius * 0.2), width: dotHighlightRadius * 2, height: dotHighlightRadius)
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.45).cgColor)
    ctx.fillEllipse(in: dotHighlightRect)

    // 6. Subtle inner rim highlight on the squircle
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(squirclePath)
    ctx.setLineWidth(2.0 * scale)
    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.20).cgColor)
    ctx.strokePath()
    ctx.restoreGState()

    img.unlockFocus()
    return img
}

func savePNG(image: NSImage, to url: URL) {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("Failed to convert image to PNG")
    }
    try! pngData.write(to: url)
}

// Generate iconset
let iconsetDir = URL(fileURLWithPath: "Resources/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconsetDir)
try! FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (filename, px) in sizes {
    let img = createIconImage(size: px)
    let dest = iconsetDir.appendingPathComponent(filename)
    savePNG(image: img, to: dest)
    print("Generated \(filename) (\(Int(px))x\(Int(px)))")
}

print("AppIcon.iconset successfully generated.")
