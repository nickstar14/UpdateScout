import AppKit
import CoreImage
// Update All, six ways of mixing the icon's six card colours. Each blob is
// (colour, x, y, size) in fractions of the button; sizes are in button heights.
let R = "ff453a", O = "ff9f0a", Y = "ffd60a", G = "30d158", B = "0a84ff", V = "bf5af2"
typealias Blob = (String, CGFloat, CGFloat, CGFloat)
let variants: [(String, String, [Blob])] = [
    ("A  Left to right", "today's mesh",
     [(R, 0.06, 0.35, 1.5), (O, 0.24, 0.80, 1.5), (Y, 0.42, 0.25, 1.5), (G, 0.60, 0.78, 1.5), (B, 0.78, 0.30, 1.5), (V, 0.96, 0.70, 1.5)]),
    ("B  Warm to cool diagonal", "like the icon's sheen, blurred",
     [(R, 0.0, 0.0, 1.6), (O, 0.22, 0.9, 1.4), (Y, 0.38, 0.1, 1.3), (G, 0.62, 0.9, 1.3), (B, 0.8, 0.15, 1.5), (V, 1.0, 1.0, 1.7)]),
    ("C  Glow from the centre", "warm core, cool edges",
     [(V, 0.02, 0.5, 1.8), (B, 0.98, 0.5, 1.8), (G, 0.25, 0.95, 1.3), (R, 0.75, 0.05, 1.3), (O, 0.38, 0.4, 1.4), (Y, 0.6, 0.6, 1.4)]),
    ("D  Scattered aurora", "colours placed out of order",
     [(B, 0.08, 0.2, 1.4), (Y, 0.3, 0.85, 1.3), (R, 0.5, 0.1, 1.2), (V, 0.68, 0.9, 1.4), (G, 0.85, 0.15, 1.3), (O, 0.98, 0.8, 1.3)]),
    ("E  Prism split", "white light in, spectrum out",
     [("ffffff", 0.1, 0.5, 2.2), (R, 0.55, 0.0, 1.0), (O, 0.65, 0.25, 1.0), (Y, 0.72, 0.5, 1.0), (G, 0.8, 0.75, 1.0), (B, 0.9, 0.95, 1.1), (V, 1.0, 0.5, 1.2)]),
    ("F  Pastel clouds", "big blobs, heavy overlap",
     [(R, 0.1, 0.7, 2.4), (Y, 0.35, 0.2, 2.4), (G, 0.55, 0.85, 2.2), (B, 0.75, 0.2, 2.4), (V, 0.95, 0.75, 2.4), (O, 0.2, 0.05, 1.8)]),
]
func hex(_ h: String) -> NSColor {
    let v = Int(h, radix: 16)!
    return NSColor(srgbRed: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}
func meshImage(_ blobs: [Blob], size: NSSize) -> NSImage {
    let pad = size.height
    let big = NSSize(width: size.width + pad * 2, height: size.height + pad * 2)
    let raw = NSImage(size: big, flipped: true) { _ in
        hex("c9b8f0").setFill(); NSRect(origin: .zero, size: big).fill()
        for (c, fx, fy, d0) in blobs {
            let d = size.height * d0
            hex(c).setFill()
            NSBezierPath(ovalIn: NSRect(x: pad + fx * size.width - d / 2, y: pad + fy * size.height - d / 2, width: d, height: d)).fill()
        }
        return true
    }
    let ci = CIImage(data: raw.tiffRepresentation!)!
    let blurred = ci.clampedToExtent().applyingGaussianBlur(sigma: Double(size.height * 0.45)).cropped(to: ci.extent)
    let out = NSImage(size: big); out.addRepresentation(NSCIImageRep(ciImage: blurred))
    return NSImage(size: size, flipped: false) { rect in
        out.draw(in: rect, from: NSRect(x: pad, y: pad, width: size.width, height: size.height), operation: .copy, fraction: 1); return true
    }
}
let s: CGFloat = 3
func pill(_ r: NSRect, _ blobs: [Blob], dark: Bool) {
    let path = NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2)
    NSGraphicsContext.saveGraphicsState(); path.addClip()
    meshImage(blobs, size: r.size).draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    (dark ? NSColor(srgbRed: 20/255, green: 26/255, blue: 46/255, alpha: 0.62) : NSColor(white: 1, alpha: 0.62)).setFill(); r.fill()
    NSGraphicsContext.restoreGraphicsState()
    (dark ? NSColor(white: 1, alpha: 0.18) : NSColor(white: 1, alpha: 0.8)).setStroke(); path.lineWidth = 0.5 * s; path.stroke()
    let ink = dark ? NSColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1) : NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13 * s, weight: .semibold), .foregroundColor: ink]
    let size = ("Update all" as NSString).size(withAttributes: attrs)
    ("Update all" as NSString).draw(at: NSPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2), withAttributes: attrs)
}
let rowH: CGFloat = 64 * s, W: CGFloat = 520 * s
let img = NSImage(size: NSSize(width: W, height: rowH * CGFloat(variants.count) + 30 * s), flipped: true) { _ in
    NSColor(srgbRed: 238/255, green: 241/255, blue: 248/255, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: W / 2 + 70 * s, height: 10_000).fill()
    NSColor(srgbRed: 20/255, green: 26/255, blue: 46/255, alpha: 1).setFill(); NSRect(x: W / 2 + 70 * s, y: 0, width: W, height: 10_000).fill()
    "Light".draw(at: NSPoint(x: 210 * s, y: 8 * s), withAttributes: [.font: NSFont.systemFont(ofSize: 11 * s, weight: .medium), .foregroundColor: NSColor.darkGray])
    "Dark".draw(at: NSPoint(x: 380 * s, y: 8 * s), withAttributes: [.font: NSFont.systemFont(ofSize: 11 * s, weight: .medium), .foregroundColor: NSColor.lightGray])
    for (i, v) in variants.enumerated() {
        let y = 30 * s + CGFloat(i) * rowH
        v.0.draw(at: NSPoint(x: 14 * s, y: y + 12 * s), withAttributes: [.font: NSFont.systemFont(ofSize: 12 * s, weight: .bold), .foregroundColor: NSColor.black])
        v.1.draw(at: NSPoint(x: 14 * s, y: y + 30 * s), withAttributes: [.font: NSFont.systemFont(ofSize: 10 * s), .foregroundColor: NSColor.darkGray])
        pill(NSRect(x: 196 * s, y: y + 14 * s, width: 110 * s, height: 30 * s), v.2, dark: false)
        pill(NSRect(x: 366 * s, y: y + 14 * s, width: 110 * s, height: 30 * s), v.2, dark: true)
    }
    return true
}
try! NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
