// Renders the 1024 px app icon: the station dial with the signal disc parked
// at twelve. Usage: swift scripts/make-icon.swift <out.png>
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
let enamel = NSColor(srgbRed: 0x0B / 255, green: 0x0D / 255, blue: 0x10 / 255, alpha: 1)
let face = NSColor(srgbRed: 0xF2 / 255, green: 0xF2 / 255, blue: 0xEE / 255, alpha: 1)
let graphite = NSColor(srgbRed: 0x8A / 255, green: 0x8F / 255, blue: 0x98 / 255, alpha: 1)
let signal = NSColor(srgbRed: 0xE1 / 255, green: 0x25 / 255, blue: 0x1B / 255, alpha: 1)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

ctx.setFillColor(enamel.cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

let c = CGPoint(x: size / 2, y: size / 2)
let r = size * 0.40

func point(_ fraction: CGFloat, _ radius: CGFloat) -> CGPoint {
    let a = .pi / 2 - fraction * 2 * .pi   // 0 at twelve, clockwise (y up)
    return CGPoint(x: c.x + cos(a) * radius, y: c.y + sin(a) * radius)
}

for i in 0..<60 {
    let major = i % 5 == 0
    ctx.setStrokeColor((major ? face : graphite).cgColor)
    ctx.setLineWidth(r * (major ? 0.06 : 0.022))
    ctx.move(to: point(CGFloat(i) / 60, r))
    ctx.addLine(to: point(CGFloat(i) / 60, r * (major ? 0.76 : 0.9)))
    ctx.strokePath()
}

// Signal hand: stem through the centre, disc near twelve.
ctx.setFillColor(signal.cgColor)
ctx.fill(CGRect(x: c.x - r * 0.018, y: c.y - r * 0.25, width: r * 0.036, height: r * 0.9))
let disc = r * 0.3
ctx.fillEllipse(in: CGRect(x: c.x - disc / 2, y: c.y + r * 0.58 - disc / 2, width: disc, height: disc))
ctx.fillEllipse(in: CGRect(x: c.x - r * 0.05, y: c.y - r * 0.05, width: r * 0.1, height: r * 0.1))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
