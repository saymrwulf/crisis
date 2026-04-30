#!/usr/bin/env swift
// Renders a CrisisViz app icon at every macOS-required size and writes them
// into ./AppIcon.iconset, ready for `iconutil -c icns AppIcon.iconset`.
//
// Run with:   swift Tools/MakeAppIcon.swift
// Or via the bundle.sh script (which then calls iconutil for you).

import Cocoa
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let outDir = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// (filename suffix, pixel size) — Apple's required iconset contents.
let entries: [(name: String, px: Int)] = [
    ("16x16", 16),
    ("16x16@2x", 32),
    ("32x32", 32),
    ("32x32@2x", 64),
    ("128x128", 128),
    ("128x128@2x", 256),
    ("256x256", 256),
    ("256x256@2x", 512),
    ("512x512", 512),
    ("512x512@2x", 1024),
]

// Palette — matches the live app's node colours.
let palette: [CGColor] = [
    CGColor(red: 0.30, green: 0.69, blue: 0.94, alpha: 1.0),  // cyan
    CGColor(red: 0.35, green: 0.85, blue: 0.55, alpha: 1.0),  // green
    CGColor(red: 0.95, green: 0.60, blue: 0.20, alpha: 1.0),  // orange
    CGColor(red: 0.80, green: 0.40, blue: 0.90, alpha: 1.0),  // purple
    CGColor(red: 0.95, green: 0.45, blue: 0.45, alpha: 1.0),  // pink
    CGColor(red: 0.90, green: 0.75, blue: 0.30, alpha: 1.0),  // gold
]

func renderIcon(px: Int) -> CGImage {
    let cs = CGColorSpaceCreateDeviceRGB()
    let info = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let ctx = CGContext(
        data: nil, width: px, height: px,
        bitsPerComponent: 8, bytesPerRow: px * 4,
        space: cs, bitmapInfo: info
    ) else { fatalError("CGContext failed") }

    let s = CGFloat(px)
    // macOS Big-Sur-and-later icon mask: rounded square, ~22.5% corner radius
    let inset = s * 0.10
    let body = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let radius: CGFloat = body.width * 0.225
    let mask = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(mask)
    ctx.clip()

    // Background — dark indigo gradient (top→bottom).
    let bgColors = [
        CGColor(red: 0.06, green: 0.08, blue: 0.16, alpha: 1.0),
        CGColor(red: 0.02, green: 0.03, blue: 0.08, alpha: 1.0),
    ]
    if let grad = CGGradient(
        colorsSpace: cs, colors: bgColors as CFArray,
        locations: [0, 1]
    ) {
        ctx.drawLinearGradient(
            grad,
            start: CGPoint(x: 0, y: body.maxY),
            end: CGPoint(x: 0, y: body.minY),
            options: []
        )
    }

    // Subtle round-separator lines (echo of the chapters' "round zones").
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.05))
    ctx.setLineWidth(max(0.5, s * 0.003))
    let sep = body.width / 4
    for i in 1..<4 {
        let x = body.minX + sep * CGFloat(i)
        ctx.move(to: CGPoint(x: x, y: body.minY + sep * 0.4))
        ctx.addLine(to: CGPoint(x: x, y: body.maxY - sep * 0.4))
    }
    ctx.strokePath()

    // Layout: a 3-round mini-DAG. Three columns of nodes with edges between them.
    let cx = body.midX
    let cy = body.midY
    let span = body.width * 0.62
    let colDx = span / 2
    let nodeR = max(s * 0.045, 2.0)
    let edgeWidth = max(s * 0.012, 1.0)

    struct Node {
        let pos: CGPoint
        let color: CGColor
        let radiusScale: CGFloat
    }

    // Three columns: left (round 0, 2 nodes), middle (round 1, 3 nodes), right (round 2, 2 nodes).
    let leftX = cx - colDx
    let midX = cx
    let rightX = cx + colDx
    let yStep = body.height * 0.18

    let nodes: [Node] = [
        Node(pos: CGPoint(x: leftX, y: cy + yStep * 0.7), color: palette[0], radiusScale: 1.0),
        Node(pos: CGPoint(x: leftX, y: cy - yStep * 0.7), color: palette[3], radiusScale: 1.0),

        Node(pos: CGPoint(x: midX, y: cy + yStep), color: palette[1], radiusScale: 1.05),
        Node(pos: CGPoint(x: midX, y: cy), color: palette[5], radiusScale: 1.4),    // emphasized centre
        Node(pos: CGPoint(x: midX, y: cy - yStep), color: palette[4], radiusScale: 1.05),

        Node(pos: CGPoint(x: rightX, y: cy + yStep * 0.7), color: palette[2], radiusScale: 1.0),
        Node(pos: CGPoint(x: rightX, y: cy - yStep * 0.7), color: palette[0], radiusScale: 1.0),
    ]

    // Edges (parent references): each later-column node points to a couple of earlier-column nodes.
    let edges: [(Int, Int)] = [
        (2, 0), (2, 1),
        (3, 0), (3, 1),
        (4, 0), (4, 1),
        (5, 2), (5, 3),
        (6, 3), (6, 4),
    ]

    ctx.setLineCap(.round)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.55))
    ctx.setLineWidth(edgeWidth)
    for (a, b) in edges {
        ctx.move(to: nodes[a].pos)
        ctx.addLine(to: nodes[b].pos)
    }
    ctx.strokePath()

    // Glow pass under each node.
    for n in nodes {
        let r = nodeR * n.radiusScale * 2.2
        let rect = CGRect(x: n.pos.x - r, y: n.pos.y - r, width: r * 2, height: r * 2)
        ctx.saveGState()
        ctx.setShadow(offset: .zero, blur: r * 1.4, color: n.color)
        ctx.setFillColor(n.color)
        ctx.setAlpha(0.28)
        ctx.fillEllipse(in: rect)
        ctx.restoreGState()
    }

    // Filled nodes.
    for n in nodes {
        let r = nodeR * n.radiusScale
        let rect = CGRect(x: n.pos.x - r, y: n.pos.y - r, width: r * 2, height: r * 2)
        ctx.setFillColor(n.color)
        ctx.fillEllipse(in: rect)
        // Inner highlight
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.45))
        let hr = r * 0.4
        let highlight = CGRect(x: n.pos.x - hr * 0.6, y: n.pos.y + r * 0.2 - hr * 0.6, width: hr, height: hr)
        ctx.fillEllipse(in: highlight)
    }

    // Centre vertex emphasis ring.
    let centre = nodes[3]
    let cr = nodeR * centre.radiusScale + s * 0.012
    let centerRect = CGRect(x: centre.pos.x - cr, y: centre.pos.y - cr, width: cr * 2, height: cr * 2)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.85))
    ctx.setLineWidth(max(s * 0.006, 0.8))
    ctx.strokeEllipse(in: centerRect)

    // Wordmark "C" only at large sizes (bottom-right corner).
    if px >= 128 {
        let label = "Δ"  // suggestive of consensus / change
        let fontSize = s * 0.16
        let font = NSFont(name: "Menlo-Bold", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize, weight: .heavy)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.55),
            .paragraphStyle: para,
        ]
        let str = NSAttributedString(string: label, attributes: attrs)
        let line = CTLineCreateWithAttributedString(str)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let dx = body.maxX - bounds.width - s * 0.06
        let dy = body.minY + s * 0.06
        ctx.textPosition = CGPoint(x: dx, y: dy)
        CTLineDraw(line, ctx)
    }

    ctx.restoreGState()

    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1, nil
    ) else {
        fputs("✘ Failed to create dest for \(path)\n", stderr); exit(1)
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

for entry in entries {
    let img = renderIcon(px: entry.px)
    let path = "\(outDir)/icon_\(entry.name).png"
    writePNG(img, to: path)
    print("✓ \(path)  (\(entry.px)×\(entry.px))")
}
print("Done. Now:  iconutil -c icns \(outDir) -o AppIcon.icns")
