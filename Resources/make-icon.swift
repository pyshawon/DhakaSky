// swift Resources/make-icon.swift Resources/AppIcon.png
// Draws the app icon: a warm evening sky with the sun behind a rain cloud over a Dhaka skyline and its reflection.
import AppKit

let side = 1024, inset = 100
let body = CGFloat(side - inset * 2)
let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}
func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map { $0.1 } as CFArray, locations: stops.map { $0.0 })!
}

// Rounded-square body with the standard macOS drop shadow.
let rect = CGRect(x: CGFloat(inset), y: CGFloat(inset) + 10, width: body, height: body)
let shape = CGPath(roundedRect: rect, cornerWidth: body * 0.225, cornerHeight: body * 0.225, transform: nil)
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
ctx.addPath(shape); ctx.setFillColor(rgb(0x1E2450)); ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.addPath(shape); ctx.clip()

// Local coordinates: (0,0) bottom-left of the body, 1 = body width.
func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * body, y: rect.minY + y * body) }
let horizon: CGFloat = 0.30

// Sky.
ctx.drawLinearGradient(gradient([(0, rgb(0xFFB070)), (0.18, rgb(0xF58A7A)), (0.45, rgb(0x9A6FB0)), (0.75, rgb(0x4A4F98)), (1, rgb(0x242B66))]),
                       start: P(0, horizon), end: P(0, 1), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// Sun with a soft glow.
let sun = P(0.66, 0.60), sunR = body * 0.17
ctx.drawRadialGradient(gradient([(0, rgb(0xFFE6A0, 0.75)), (1, rgb(0xFFB070, 0))]), startCenter: sun, startRadius: sunR * 0.8,
                       endCenter: sun, endRadius: sunR * 2.6, options: [])
ctx.drawRadialGradient(gradient([(0, rgb(0xFFF6C8)), (0.7, rgb(0xFFD36A)), (1, rgb(0xFFB547))]), startCenter: CGPoint(x: sun.x - sunR * 0.3, y: sun.y + sunR * 0.3),
                       startRadius: 0, endCenter: sun, endRadius: sunR, options: [])

// Rain falling from the cloud.
ctx.setLineCap(.round)
ctx.setLineWidth(body * 0.022)
ctx.setStrokeColor(rgb(0xBFD9FF, 0.9))
for (x, y, l) in [(0.20, 0.50, 0.07), (0.29, 0.46, 0.08), (0.38, 0.51, 0.06), (0.47, 0.45, 0.07), (0.25, 0.39, 0.05), (0.42, 0.38, 0.05)] as [(CGFloat, CGFloat, CGFloat)] {
    ctx.move(to: P(x, y)); ctx.addLine(to: P(x - l * 0.3, y - l)); ctx.strokePath()
}

// Cloud: overlapping circles on a flat base, shaded from white to a cool grey underside.
let cloud = CGMutablePath()
for (x, y, r) in [(0.22, 0.60, 0.085), (0.33, 0.67, 0.12), (0.46, 0.64, 0.10), (0.55, 0.59, 0.07)] as [(CGFloat, CGFloat, CGFloat)] {
    cloud.addEllipse(in: CGRect(x: rect.minX + (x - r) * body, y: rect.minY + (y - r) * body, width: 2 * r * body, height: 2 * r * body))
}
cloud.addRoundedRect(in: CGRect(origin: P(0.14, 0.515), size: CGSize(width: body * 0.48, height: body * 0.09)),
                     cornerWidth: body * 0.04, cornerHeight: body * 0.04)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -body * 0.012), blur: body * 0.03, color: rgb(0x2A2360, 0.45))
ctx.addPath(cloud); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(cloud); ctx.clip()
ctx.drawLinearGradient(gradient([(0, rgb(0xC9CCE8)), (0.55, rgb(0xF4F2FA)), (1, rgb(0xFFFFFF))]), start: P(0, 0.515), end: P(0, 0.79), options: [])
ctx.restoreGState()

// Skyline: blocks and towers of Dhaka with a few lit windows, plus a minaret and a water tank.
let city = rgb(0x2C2558)
var rng: UInt64 = 7
func rand() -> CGFloat { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(rng >> 33) / CGFloat(1 << 31) }
let blocks: [(CGFloat, CGFloat, CGFloat)] = [
    (0.00, 0.08, 0.17), (0.08, 0.07, 0.25), (0.15, 0.06, 0.20), (0.21, 0.09, 0.31), (0.30, 0.05, 0.22),
    (0.35, 0.08, 0.27), (0.43, 0.06, 0.19), (0.49, 0.10, 0.35), (0.59, 0.07, 0.24), (0.66, 0.05, 0.20),
    (0.71, 0.09, 0.29), (0.80, 0.06, 0.21), (0.86, 0.08, 0.26), (0.94, 0.06, 0.18),
]
for (x, w, h) in blocks {
    let r = CGRect(origin: P(x, horizon), size: CGSize(width: w * body, height: (h - horizon + 0.12) * body))
    ctx.setFillColor(city); ctx.fill(r)
    // Windows.
    let cols = Int(w / 0.025), rows = Int((r.height / body) / 0.03)
    for c in 0..<cols { for j in 0..<rows where rand() < 0.28 {
        ctx.setFillColor(rgb(0xFFD58A, 0.55 + rand() * 0.4))
        ctx.fill(CGRect(x: r.minX + (CGFloat(c) + 0.35) * w * body / CGFloat(cols), y: r.minY + (CGFloat(j) + 0.4) * 0.03 * body,
                        width: body * 0.009, height: body * 0.012))
    } }
}
// Minaret with a small dome.
ctx.setFillColor(city)
ctx.fill(CGRect(origin: P(0.565, horizon), size: CGSize(width: body * 0.022, height: body * 0.18)))
ctx.fillEllipse(in: CGRect(origin: P(0.556, horizon + 0.165), size: CGSize(width: body * 0.04, height: body * 0.04)))
ctx.move(to: P(0.576, horizon + 0.23)); ctx.addLine(to: P(0.566, horizon + 0.195)); ctx.addLine(to: P(0.586, horizon + 0.195)); ctx.fillPath()

// Lake: darker water with the sky and city reflected as horizontal shimmer.
ctx.drawLinearGradient(gradient([(0, rgb(0x1C1E4A)), (1, rgb(0x5A4A8A))]), start: P(0, 0), end: P(0, horizon), options: [])
ctx.setLineWidth(body * 0.009)
for i in 0..<9 {
    let y = horizon - 0.02 - CGFloat(i) * 0.03
    let x0 = 0.05 + rand() * 0.55, len = 0.08 + rand() * 0.25
    ctx.setStrokeColor(rgb(i < 6 ? 0xFFB070 : 0x9A8FD0, 0.25 + rand() * 0.2))
    ctx.move(to: P(x0, y)); ctx.addLine(to: P(x0 + len, y)); ctx.strokePath()
}
// Sun's glitter path on the water.
for i in 0..<9 {
    let y = horizon - 0.025 - CGFloat(i) * 0.028, w = 0.10 - CGFloat(i) * 0.007
    ctx.setStrokeColor(rgb(0xFFE3A0, 0.85 - CGFloat(i) * 0.07))
    ctx.move(to: P(0.66 - w / 2, y)); ctx.addLine(to: P(0.66 + w / 2, y)); ctx.strokePath()
}
// Shore line.
ctx.setFillColor(rgb(0x221C48)); ctx.fill(CGRect(origin: P(0, horizon - 0.006), size: CGSize(width: body, height: body * 0.012)))

// Subtle top highlight for depth.
ctx.drawLinearGradient(gradient([(0, rgb(0xFFFFFF, 0)), (1, rgb(0xFFFFFF, 0.10))]), start: P(0, 0.7), end: P(0, 1), options: [])

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
