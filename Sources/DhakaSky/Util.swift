import AppKit
import CoreImage
import SpriteKit

// MARK: - Math

@inline(__always) func clamp01(_ x: Double) -> Double { min(1, max(0, x)) }
@inline(__always) func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }
@inline(__always) func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
    let t = clamp01((x - e0) / (e1 - e0))
    return t * t * (3 - 2 * t)
}

// MARK: - Color

struct RGB {
    var r: Double, g: Double, b: Double

    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    static let white = RGB(1, 1, 1)
    static let black = RGB(0, 0, 0)

    static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        RGB(lerp(a.r, b.r, t), lerp(a.g, b.g, t), lerp(a.b, b.b, t))
    }
    func scaled(_ k: Double) -> RGB { RGB(r * k, g * k, b * k) }
    func lighter(_ t: Double) -> RGB { RGB.mix(self, .white, t) }
    func darker(_ t: Double) -> RGB { RGB.mix(self, .black, t) }
    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
    func desaturated(_ t: Double) -> RGB { let l = luminance; return RGB.mix(self, RGB(l, l, l), t) }

    var sk: SKColor { SKColor(srgbRed: r, green: g, blue: b, alpha: 1) }
    func cg(_ a: Double = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    func v4(_ a: Double = 1) -> SIMD4<Float> { SIMD4(Float(r), Float(g), Float(b), Float(a)) }
}

// MARK: - Deterministic randomness (stable city layout between launches)

struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func d(_ a: Double, _ b: Double) -> Double { Double.random(in: a...b, using: &self) }
    mutating func cg(_ a: CGFloat, _ b: CGFloat) -> CGFloat { CGFloat.random(in: a...b, using: &self) }
    mutating func chance(_ p: Double) -> Bool { Double.random(in: 0..<1, using: &self) < p }
    mutating func pick<T>(_ a: [T]) -> T { a[Int.random(in: 0..<a.count, using: &self)] }
}

// MARK: - Painting helpers

enum Painter {
    /// Backing scale used for generated art (2 on Retina).
    static var scale: CGFloat = 2
    static let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    static let space = CGColorSpace(name: CGColorSpace.sRGB)!

    static func image(_ size: CGSize, scale s: CGFloat = Painter.scale, _ draw: (CGContext) -> Void) -> CGImage {
        let w = max(1, Int((size.width * s).rounded(.up)))
        let h = max(1, Int((size.height * s).rounded(.up)))
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: s, y: s)
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high
        draw(ctx)
        return ctx.makeImage()!
    }

    /// A blank drawing context in points (bottom-left origin), for art that needs several passes.
    static func context(_ size: CGSize, scale s: CGFloat = Painter.scale) -> CGContext {
        let w = max(1, Int((size.width * s).rounded(.up)))
        let h = max(1, Int((size.height * s).rounded(.up)))
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: s, y: s)
        return ctx
    }

    static func texture(_ size: CGSize, scale s: CGFloat = Painter.scale, _ draw: (CGContext) -> Void) -> SKTexture {
        texture(image(size, scale: s, draw))
    }

    static func texture(_ img: CGImage) -> SKTexture {
        let t = SKTexture(cgImage: img)
        t.filteringMode = .linear
        return t
    }

    static func blurred(_ img: CGImage, radius: CGFloat) -> CGImage {
        let input = CIImage(cgImage: img)
        let f = CIFilter(name: "CIGaussianBlur")!
        f.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
        f.setValue(radius, forKey: kCIInputRadiusKey)
        guard let out = f.outputImage?.cropped(to: input.extent),
              let cg = ciContext.createCGImage(out, from: input.extent) else { return img }
        return cg
    }

    /// Soft radial glow (white centre fading to transparent).
    static func glow(_ d: CGFloat, falloff: CGFloat = 1.6) -> SKTexture {
        let px = Int(d * scale)
        let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let stops = 24
        var colors: [CGColor] = []
        var locs: [CGFloat] = []
        for i in 0...stops {
            let t = CGFloat(i) / CGFloat(stops)
            colors.append(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: pow(1 - t, falloff * 1.6)))
            locs.append(t)
        }
        let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locs)!
        let c = CGPoint(x: CGFloat(px) / 2, y: CGFloat(px) / 2)
        ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(px) / 2, options: [])
        return texture(ctx.makeImage()!)
    }

    static func linearGradient(_ ctx: CGContext, _ stops: [(CGFloat, CGColor)], from: CGPoint, to: CGPoint) {
        let g = CGGradient(colorsSpace: space, colors: stops.map { $0.1 } as CFArray, locations: stops.map { $0.0 })!
        ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
}

extension CGContext {
    func fill(_ c: RGB, _ a: Double = 1, _ r: CGRect) { setFillColor(c.cg(a)); fill(r) }
    func fillGray(_ g: Double, _ a: Double = 1, _ r: CGRect) { setFillColor(gray: g, alpha: a); fill(r) }
    func fillEllipse(_ c: RGB, _ a: Double = 1, _ r: CGRect) { setFillColor(c.cg(a)); fillEllipse(in: r) }
    func fillPath(_ c: RGB, _ a: Double = 1, _ p: CGPath) { setFillColor(c.cg(a)); addPath(p); fillPath() }
    func strokeLine(_ c: RGB, _ a: Double = 1, width: CGFloat, _ pts: [CGPoint]) {
        setStrokeColor(c.cg(a)); setLineWidth(width); setLineCap(.round)
        addLines(between: pts); strokePath()
    }
}

extension CGPath {
    static func poly(_ pts: [CGPoint]) -> CGPath {
        let p = CGMutablePath(); p.addLines(between: pts); p.closeSubpath(); return p
    }
}

func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
