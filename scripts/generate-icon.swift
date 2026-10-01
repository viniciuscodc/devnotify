#!/usr/bin/env swift
import AppKit

NSApplication.shared.setActivationPolicy(.prohibited)

func renderIcon(pixels: Int) -> Data? {
    let s = CGFloat(pixels)
    let image = NSImage(size: NSSize(width: s, height: s), flipped: false) { bounds in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

        // Rounded rectangle clip (standard macOS app icon shape)
        let radius = s * 0.2237
        let path = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.addPath(path)
        ctx.clip()

        // Gradient background: deep navy → vivid indigo-blue
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let colors = [
            CGColor(red: 0.06, green: 0.08, blue: 0.22, alpha: 1), // top-left deep navy
            CGColor(red: 0.22, green: 0.10, blue: 0.52, alpha: 1), // mid indigo
            CGColor(red: 0.09, green: 0.38, blue: 0.86, alpha: 1), // bottom-right vivid blue
        ] as CFArray
        let locations: [CGFloat] = [0, 0.45, 1]
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) else { return false }
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: s),
            end: CGPoint(x: s, y: 0),
            options: []
        )

        // Soft glow circle behind symbol
        let glowRadius = s * 0.35
        let glowCenter = CGPoint(x: s * 0.5, y: s * 0.52)
        guard let radialGradient = CGGradient(
            colorsSpace: colorSpace,
            colors: [
                CGColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 0.28),
                CGColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 0),
            ] as CFArray,
            locations: [0, 1]
        ) else { return false }
        ctx.drawRadialGradient(radialGradient, startCenter: glowCenter, startRadius: 0, endCenter: glowCenter, endRadius: glowRadius, options: [])

        // Symbol: bell with badge
        let symbolSize = s * 0.56
        let config = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .medium)
        guard let symbol = NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return false }

        // Render symbol in white
        let symbolAreaSize = NSSize(width: symbolSize * 1.1, height: symbolSize * 1.1)
        let tinted = NSImage(size: symbolAreaSize, flipped: false) { r in
            symbol.draw(in: r)
            NSColor.white.setFill()
            r.fill(using: .sourceAtop)
            return true
        }

        let ox = (s - symbolAreaSize.width) / 2
        let oy = (s - symbolAreaSize.height) / 2 - s * 0.01
        tinted.draw(
            in: CGRect(x: ox, y: oy, width: symbolAreaSize.width, height: symbolAreaSize.height),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        return true
    }
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
}

let iconsetPath = "scripts/DevNotify.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let specs: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),   ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),   ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),("icon_512x512@2x.png", 1024),
]

for spec in specs {
    guard let png = renderIcon(pixels: spec.pixels) else { print("Failed: \(spec.name)"); continue }
    let url = URL(fileURLWithPath: "\(iconsetPath)/\(spec.name)")
    try? png.write(to: url)
    print("Generated \(spec.name) (\(spec.pixels)px)")
}
print("Done. Run: iconutil -c icns scripts/DevNotify.iconset -o scripts/DevNotify.icns")
