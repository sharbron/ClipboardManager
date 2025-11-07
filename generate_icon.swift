#!/usr/bin/env swift

import Foundation
import AppKit
import CoreGraphics

// Generate app icon with clipboard design
func generateIcon(size: CGFloat) -> NSImage {
    // Create bitmap with proper pixel dimensions
    guard let bitmapRep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return NSImage(size: NSSize(width: size, height: size))
    }

    // Set the bitmap's size to match pixel dimensions (72 DPI)
    bitmapRep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmapRep)

    guard let context = NSGraphicsContext.current?.cgContext else {
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: size, height: size))
        image.addRepresentation(bitmapRep)
        return image
    }

    // Add proper inset margins (96px on 1024px canvas = 9.375% margin)
    // This prevents the icon from appearing too large compared to other macOS apps
    let inset = size * 0.09375
    let usableSize = size - (inset * 2)

    // Solid background with rounded corners (like WindowSwitcher)
    let backgroundRect = CGRect(x: inset, y: inset, width: usableSize, height: usableSize)
    let cornerRadius = usableSize * 0.22

    // Create gradient background (blue gradient)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let gradientColors = [
        NSColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1.0).cgColor,
        NSColor(red: 0.1, green: 0.3, blue: 0.7, alpha: 1.0).cgColor
    ] as CFArray
    let gradient = CGGradient(colorsSpace: colorSpace, colors: gradientColors, locations: [0.0, 1.0])!

    context.saveGState()
    let backgroundPath = NSBezierPath(roundedRect: backgroundRect, xRadius: cornerRadius, yRadius: cornerRadius)
    backgroundPath.addClip()
    context.drawLinearGradient(gradient,
                              start: CGPoint(x: inset, y: inset + usableSize),
                              end: CGPoint(x: inset + usableSize, y: inset),
                              options: [])
    context.restoreGState()

    // Calculate clipboard dimensions within usable area
    let clipboardWidth = usableSize * 0.65
    let clipboardHeight = usableSize * 0.78
    let clipboardX = inset + (usableSize - clipboardWidth) / 2
    let clipboardY = inset + (usableSize - clipboardHeight) / 2
    let clipboardCornerRadius = usableSize * 0.10

    // Shadow for depth
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: size * 0.02), blur: size * 0.04, color: NSColor.black.withAlphaComponent(0.25).cgColor)

    // Clipboard body - white/light gray with border
    let clipboardRect = CGRect(x: clipboardX, y: clipboardY, width: clipboardWidth, height: clipboardHeight)
    let clipboardPath = NSBezierPath(roundedRect: clipboardRect, xRadius: clipboardCornerRadius, yRadius: clipboardCornerRadius)
    NSColor(white: 0.95, alpha: 1.0).setFill()
    clipboardPath.fill()

    // Border
    NSColor(red: 0.25, green: 0.35, blue: 0.45, alpha: 1.0).setStroke()
    clipboardPath.lineWidth = size * 0.008
    clipboardPath.stroke()

    context.restoreGState()

    // Clipboard clip at the top
    let clipWidth = clipboardWidth * 0.5
    let clipHeight = usableSize * 0.10
    let clipX = clipboardX + (clipboardWidth - clipWidth) / 2
    let clipY = clipboardY + clipboardHeight - clipHeight / 2
    let clipRadius = clipHeight * 0.3

    // Clip body (dark blue/gray)
    let clipPath = NSBezierPath(roundedRect: CGRect(x: clipX, y: clipY, width: clipWidth, height: clipHeight),
                                xRadius: clipRadius, yRadius: clipRadius)
    NSColor(red: 0.25, green: 0.35, blue: 0.45, alpha: 1.0).setFill()
    clipPath.fill()

    // Clip metal piece (lighter gray)
    let metalWidth = clipWidth * 0.85
    let metalHeight = clipHeight * 0.35
    let metalX = clipX + (clipWidth - metalWidth) / 2
    let metalY = clipY + clipHeight * 0.25
    let metalPath = NSBezierPath(roundedRect: CGRect(x: metalX, y: metalY, width: metalWidth, height: metalHeight),
                                 xRadius: metalHeight * 0.4, yRadius: metalHeight * 0.4)
    NSColor(red: 0.55, green: 0.60, blue: 0.63, alpha: 1.0).setFill()
    metalPath.fill()

    // Text lines on clipboard (blue lines representing clipboard items)
    let lineColor = NSColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1.0)
    let lineHeight = usableSize * 0.025
    let lineSpacing = usableSize * 0.08
    let lineStartX = clipboardX + clipboardWidth * 0.15
    let lineWidth = clipboardWidth * 0.7
    let firstLineY = clipboardY + clipboardHeight * 0.25

    for i in 0..<5 {
        let y = firstLineY + CGFloat(i) * lineSpacing
        let currentLineWidth = (i == 5) ? lineWidth * 0.6 : lineWidth // Last line shorter

        let linePath = NSBezierPath(roundedRect: CGRect(x: lineStartX, y: y, width: currentLineWidth, height: lineHeight),
                                   xRadius: lineHeight / 2, yRadius: lineHeight / 2)
        lineColor.setFill()
        linePath.fill()
    }

    NSGraphicsContext.restoreGraphicsState()

    // Create final NSImage and add the bitmap representation
    let image = NSImage(size: NSSize(width: size, height: size))
    image.addRepresentation(bitmapRep)
    return image
}

// Save image as PNG at specific size
func saveIconImage(_ image: NSImage, size: Int, filename: String) -> Bool {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData) else {
        print("Failed to create PNG data for \(filename)")
        return false
    }

    // Explicitly set DPI to 72 (standard for macOS icons)
    bitmap.size = NSSize(width: size, height: size)

    // Create PNG with explicit DPI metadata
    let pngProperties: [NSBitmapImageRep.PropertyKey: Any] = [
        .compressionFactor: 1.0
    ]

    guard let pngData = bitmap.representation(using: .png, properties: pngProperties) else {
        print("Failed to create PNG data for \(filename)")
        return false
    }

    let url = URL(fileURLWithPath: filename)
    do {
        try pngData.write(to: url)
        print("✓ Generated \(filename)")
        return true
    } catch {
        print("Failed to write \(filename): \(error)")
        return false
    }
}

// Main execution
print("Generating ClipboardManager app icon...")

let iconsDir = "AppIcon.iconset"
let fileManager = FileManager.default

// Create iconset directory
if fileManager.fileExists(atPath: iconsDir) {
    try? fileManager.removeItem(atPath: iconsDir)
}

do {
    try fileManager.createDirectory(atPath: iconsDir, withIntermediateDirectories: true)
} catch {
    print("Failed to create directory: \(error)")
    exit(1)
}

// Generate all required icon sizes for macOS
let sizes = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

var allSuccessful = true
for (size, filename) in sizes {
    let image = generateIcon(size: CGFloat(size))
    let path = "\(iconsDir)/\(filename)"
    if !saveIconImage(image, size: size, filename: path) {
        allSuccessful = false
    }
}

if !allSuccessful {
    print("\n⚠️  Some icons failed to generate")
    exit(1)
}

// Convert iconset to icns using iconutil
print("\nConverting to .icns format...")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsDir, "-o", "AppIcon.icns"]

do {
    try process.run()
    process.waitUntilExit()

    if process.terminationStatus == 0 {
        print("✓ Generated AppIcon.icns")

        // Clean up iconset directory
        try? fileManager.removeItem(atPath: iconsDir)

        // Set DPI to 72 for the .icns file to match other macOS app icons
        let sipsProcess = Process()
        sipsProcess.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        sipsProcess.arguments = ["-s", "dpiWidth", "72", "-s", "dpiHeight", "72", "AppIcon.icns"]
        sipsProcess.standardOutput = FileHandle.nullDevice
        sipsProcess.standardError = FileHandle.nullDevice
        try? sipsProcess.run()
        sipsProcess.waitUntilExit()

        print("\n✅ Icon generation complete!")
        print("📁 AppIcon.icns has been created")
        print("\nTo use this icon:")
        print("1. Add AppIcon.icns to your Xcode project")
        print("2. Update Info.plist with: <key>CFBundleIconFile</key><string>AppIcon</string>")
        print("3. Rebuild your app")
    } else {
        print("❌ iconutil failed with status: \(process.terminationStatus)")
        exit(1)
    }
} catch {
    print("❌ Failed to run iconutil: \(error)")
    exit(1)
}
