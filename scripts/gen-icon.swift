#!/usr/bin/env swift
// Generates macdoon.icns — a document-style icon with the markdown mark.

import Cocoa

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let s = size
    let pad = s * 0.08

    // -- Document shape with folded corner --
    let bodyRect = CGRect(x: pad, y: pad, width: s - pad * 2, height: s - pad * 2)
    let foldSize = s * 0.18
    let cornerRadius = s * 0.06

    let doc = CGMutablePath()
    let left = bodyRect.minX
    let right = bodyRect.maxX
    let top = bodyRect.maxY
    let bottom = bodyRect.minY
    let foldX = right - foldSize
    let foldY = top - foldSize

    // Start bottom-left, go clockwise
    doc.move(to: CGPoint(x: left + cornerRadius, y: bottom))
    doc.addLine(to: CGPoint(x: right - cornerRadius, y: bottom))
    doc.addArc(tangent1End: CGPoint(x: right, y: bottom),
               tangent2End: CGPoint(x: right, y: bottom + cornerRadius),
               radius: cornerRadius)
    doc.addLine(to: CGPoint(x: right, y: foldY))
    // Fold
    doc.addLine(to: CGPoint(x: foldX, y: top))
    doc.addLine(to: CGPoint(x: left + cornerRadius, y: top))
    doc.addArc(tangent1End: CGPoint(x: left, y: top),
               tangent2End: CGPoint(x: left, y: top - cornerRadius),
               radius: cornerRadius)
    doc.addLine(to: CGPoint(x: left, y: bottom + cornerRadius))
    doc.addArc(tangent1End: CGPoint(x: left, y: bottom),
               tangent2End: CGPoint(x: left + cornerRadius, y: bottom),
               radius: cornerRadius)
    doc.closeSubpath()

    // Shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.015), blur: s * 0.04,
                  color: CGColor(gray: 0, alpha: 0.35))
    ctx.setFillColor(CGColor.white)
    ctx.addPath(doc)
    ctx.fillPath()
    ctx.restoreGState()

    // Document fill — white
    ctx.setFillColor(CGColor.white)
    ctx.addPath(doc)
    ctx.fillPath()

    // Fold triangle (darker shade)
    let fold = CGMutablePath()
    fold.move(to: CGPoint(x: foldX, y: top))
    fold.addLine(to: CGPoint(x: right, y: foldY))
    fold.addLine(to: CGPoint(x: foldX, y: foldY))
    fold.closeSubpath()

    ctx.setFillColor(CGColor(gray: 0.85, alpha: 1.0))
    ctx.addPath(fold)
    ctx.fillPath()

    // -- Markdown "M" mark --
    // Centered in the document body, below the fold
    let markAreaTop = foldY - s * 0.06
    let markAreaBottom = bottom + s * 0.15
    let markAreaLeft = left + s * 0.14
    let markAreaRight = right - s * 0.14
    let markH = markAreaTop - markAreaBottom
    let markW = markAreaRight - markAreaLeft

    // Background rounded rect for the mark
    let markBg = CGRect(x: markAreaLeft - s * 0.03, y: markAreaBottom - s * 0.03,
                        width: markW + s * 0.06, height: markH + s * 0.06)
    let markBgPath = CGPath(roundedRect: markBg, cornerWidth: s * 0.04, cornerHeight: s * 0.04, transform: nil)
    ctx.setFillColor(CGColor(red: 0.15, green: 0.16, blue: 0.18, alpha: 1.0))
    ctx.addPath(markBgPath)
    ctx.fillPath()

    // Helper to snap to nearest half-pixel for crispness
    func snap(_ v: CGFloat) -> CGFloat { return (v * 2).rounded() / 2 }

    // Draw M in white — shifted left to make room for arrow
    let lineW = s * 0.055  // thicker strokes for crispness
    ctx.setStrokeColor(CGColor.white)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(lineW)

    let mLeft = snap(markAreaLeft + markW * 0.10)
    let mRight = snap(markAreaLeft + markW * 0.62)  // M takes ~52% of width, leaving room
    let mTop = snap(markAreaTop - s * 0.04)
    let mBottom = snap(markAreaBottom + s * 0.04)
    let mMid = snap((mLeft + mRight) / 2)

    // Left stroke of M (bottom to top)
    ctx.move(to: CGPoint(x: mLeft, y: mBottom))
    ctx.addLine(to: CGPoint(x: mLeft, y: mTop))
    // Diagonal down to center
    ctx.addLine(to: CGPoint(x: mMid, y: (mTop + mBottom) / 2))
    // Diagonal up to right top
    ctx.addLine(to: CGPoint(x: mRight, y: mTop))
    // Right stroke down
    ctx.addLine(to: CGPoint(x: mRight, y: mBottom))
    ctx.strokePath()

    // Down arrow (↓) — well separated from M, centered in remaining space
    let arrowRegionLeft = mRight + markW * 0.08  // clear gap after M
    let arrowRegionRight = markAreaRight - markW * 0.04
    let arrowX = snap((arrowRegionLeft + arrowRegionRight) / 2)
    let arrowTop = snap(markAreaTop - s * 0.05)
    let arrowBottom = snap(markAreaBottom + s * 0.05)
    let arrowW = s * 0.055
    let arrowLineW = s * 0.045  // match M stroke weight

    ctx.setLineWidth(arrowLineW)
    // Vertical line
    ctx.move(to: CGPoint(x: arrowX, y: arrowTop))
    ctx.addLine(to: CGPoint(x: arrowX, y: arrowBottom))
    ctx.strokePath()
    // Arrowhead
    ctx.move(to: CGPoint(x: snap(arrowX - arrowW), y: snap(arrowBottom + arrowW)))
    ctx.addLine(to: CGPoint(x: arrowX, y: arrowBottom))
    ctx.addLine(to: CGPoint(x: snap(arrowX + arrowW), y: snap(arrowBottom + arrowW)))
    ctx.strokePath()

    // Document outline
    ctx.setStrokeColor(CGColor(gray: 0.75, alpha: 1.0))
    ctx.setLineWidth(s * 0.01)
    ctx.addPath(doc)
    ctx.strokePath()

    image.unlockFocus()
    return image
}

// Generate all required sizes for .icns
let sizes: [(CGFloat, String)] = [
    (16, "16x16"),
    (32, "16x16@2x"),
    (32, "32x32"),
    (64, "32x32@2x"),
    (128, "128x128"),
    (256, "128x128@2x"),
    (256, "256x256"),
    (512, "256x256@2x"),
    (512, "512x512"),
    (1024, "512x512@2x"),
]

// Create iconset directory
let iconsetPath = "build/macdoon.iconset"
let fm = FileManager.default
try? fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

for (size, name) in sizes {
    let image = drawIcon(size: size)
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("Failed to generate \(name)")
        continue
    }
    let filename = "icon_\(name).png"
    let path = "\(iconsetPath)/\(filename)"
    try png.write(to: URL(fileURLWithPath: path))
    print("Generated \(filename) (\(Int(size))x\(Int(size)))")
}

print("Converting to icns...")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetPath, "-o", "resources/macdoon.icns"]
try process.run()
process.waitUntilExit()

if process.terminationStatus == 0 {
    print("Created resources/macdoon.icns")
} else {
    print("iconutil failed with status \(process.terminationStatus)")
    exit(1)
}
