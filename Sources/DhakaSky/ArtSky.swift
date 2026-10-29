import AppKit
import SpriteKit

/// Procedural sky / weather art. Grayscale textures are tinted at runtime (sprite colour multiplies).
enum ArtSky {
    static func stars(size: CGSize, seed: UInt64) -> SKTexture {
        var rng = SeededRNG(seed: seed)
        // Drawn at 1x: stars are soft dots anyway, and this layer covers most of the screen (saves ~75% of its memory).
        return Painter.texture(size, scale: 1) { ctx in
            let count = Int(size.width * size.height / 2600)
            for _ in 0..<count {
                let x = rng.cg(0, size.width), y = rng.cg(0, size.height)
                // Fewer stars near the (light-polluted) horizon.
                let fade = Double(y / size.height)
                guard rng.chance(0.25 + 0.75 * fade) else { continue }
                let r = rng.chance(0.06) ? rng.cg(0.9, 1.4) : rng.cg(0.35, 0.8)
                let tint = rng.pick([RGB(0xFFFFFF), RGB(0xFFF1DC), RGB(0xDCE8FF)])
                ctx.fillEllipse(tint, rng.d(0.35, 0.95) * (0.4 + 0.6 * fade), R(x - r, y - r, r * 2, r * 2))
            }
        }
    }

    static func sunDisc(_ d: CGFloat) -> SKTexture {
        Painter.texture(CGSize(width: d, height: d)) { ctx in
            ctx.fillEllipse(RGB(0xFFFBF2), 1, R(0, 0, d, d))
        }
    }

    /// Per-pixel lit sphere so the phase terminator looks right. Waxing = lit from the right.
    static func moon(_ d: CGFloat, phase: Double) -> SKTexture {
        let px = Int(d * Painter.scale)
        var rng = SeededRNG(seed: 7)
        // A few soft maria for texture.
        let maria: [(Double, Double, Double)] = (0..<9).map { _ in (rng.d(-0.55, 0.45), rng.d(-0.4, 0.5), rng.d(0.12, 0.3)) }
        let phi = phase * 2 * .pi
        let lx = sin(phi), lz = -cos(phi)
        var buf = [UInt8](repeating: 0, count: px * px * 4)
        let r = Double(px) / 2
        for j in 0..<px {
            for i in 0..<px {
                let x = (Double(i) + 0.5 - r) / r, y = (Double(j) + 0.5 - r) / r
                let rr = x * x + y * y
                guard rr <= 1 else { continue }
                let z = sqrt(1 - rr)
                let lit = smoothstep(-0.06, 0.12, x * lx + z * lz)
                var shade = 0.93
                for m in maria {
                    let dd = ((x - m.0) * (x - m.0) + (y - m.1) * (y - m.1)) / (m.2 * m.2)
                    shade -= 0.09 * exp(-dd * 1.5)
                }
                let edge = smoothstep(1.0, 0.94, sqrt(rr))
                let earthshine = 0.07
                let v = (earthshine + (shade - earthshine) * lit)
                let a = edge * (0.18 + 0.82 * lit)
                let idx = ((px - 1 - j) * px + i) * 4
                buf[idx] = UInt8(min(255, v * 255 * a))
                buf[idx + 1] = UInt8(min(255, v * 0.98 * 255 * a))
                buf[idx + 2] = UInt8(min(255, v * 0.94 * 255 * a))
                buf[idx + 3] = UInt8(min(255, a * 255))
            }
        }
        let ctx = CGContext(data: &buf, width: px, height: px, bitsPerComponent: 8, bytesPerRow: px * 4,
                            space: Painter.space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return Painter.texture(ctx.makeImage()!)
    }

    /// Soft painterly cumulus: white tops, cooler grey undersides.
    static func cloud(width w: CGFloat, seed: UInt64, flat: Bool = false) -> (SKTexture, CGSize) {
        var rng = SeededRNG(seed: seed)
        let h = w * (flat ? 0.34 : 0.62)
        let size = CGSize(width: w, height: h)
        let pad = w * 0.06
        let img = Painter.image(size, scale: 1) { ctx in
            let base = h * 0.22
            var puffs: [CGRect] = []
            let n = flat ? 16 : 11
            for i in 0..<n {
                let t = CGFloat(i) / CGFloat(n - 1)
                let cx = pad + (w - 2 * pad) * (0.08 + 0.84 * t) + rng.cg(-w * 0.03, w * 0.03)
                let bell = sin(t * .pi)
                let r = (flat ? h * 0.12 : h * 0.1) + (flat ? h * 0.12 : h * 0.17) * bell * rng.cg(0.7, 1.15)
                puffs.append(R(cx - r, base + rng.cg(0, h * 0.05) * bell, r * 2, r * 1.5))
            }
            // Shadowed underside first, then lit tops shifted up.
            for p in puffs { ctx.setFillColor(gray: 0.78, alpha: 1); ctx.fillEllipse(in: p) }
            for p in puffs {
                ctx.setFillColor(gray: 1, alpha: 1)
                ctx.fillEllipse(in: p.offsetBy(dx: -p.width * 0.04, dy: p.height * 0.12).insetBy(dx: p.width * 0.06, dy: p.height * 0.08))
            }
            // Flatten the base.
            ctx.setBlendMode(.clear)
            ctx.fill(R(0, 0, w, base + h * 0.02))
        }
        let soft = Painter.blurred(img, radius: w * 0.018)
        return (Painter.texture(soft), size)
    }

    /// Wide, flat overcast sheet for heavy cloud cover.
    static func stratus(size: CGSize, seed: UInt64) -> SKTexture {
        var rng = SeededRNG(seed: seed)
        let small = CGSize(width: size.width / 4, height: size.height / 4)
        let img = Painter.image(small, scale: 1) { ctx in
            for _ in 0..<70 {
                let w = rng.cg(small.width * 0.15, small.width * 0.45)
                let hh = w * rng.cg(0.18, 0.32)
                let x = rng.cg(-w * 0.3, small.width - w * 0.7)
                let y = rng.cg(small.height * 0.15, small.height * 1.0)
                ctx.setFillColor(gray: CGFloat(rng.d(0.7, 1.0)), alpha: CGFloat(rng.d(0.35, 0.7)))
                ctx.fillEllipse(in: R(x, y, w, hh))
            }
            ctx.setFillColor(gray: 0.85, alpha: 0.9)
            ctx.fill(R(0, small.height * 0.62, small.width, small.height * 0.38))
        }
        return Painter.texture(Painter.blurred(img, radius: small.height * 0.05))
    }

    static func fogBand(width w: CGFloat, seed: UInt64) -> SKTexture {
        var rng = SeededRNG(seed: seed)
        let size = CGSize(width: w / 3, height: w / 3 * 0.18)
        let img = Painter.image(size, scale: 1) { ctx in
            for _ in 0..<26 {
                let ww = rng.cg(size.width * 0.12, size.width * 0.35)
                let hh = ww * rng.cg(0.15, 0.3)
                ctx.setFillColor(gray: 1, alpha: CGFloat(rng.d(0.25, 0.55)))
                ctx.fillEllipse(in: R(rng.cg(0, size.width - ww), rng.cg(size.height * 0.2, size.height * 0.6), ww, hh))
            }
        }
        return Painter.texture(Painter.blurred(img, radius: size.height * 0.12))
    }

    /// Paper-grain overlay, subtle, keeps the illustration feeling hand-made.
    static func grain(size: CGSize, seed: UInt64) -> SKTexture {
        let w = Int(size.width / 1.5), h = Int(size.height / 1.5)
        var rng = SeededRNG(seed: seed)
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            let v = rng.d(0, 1)
            let a = UInt8(v * 15)
            let g = UInt8(v > 0.5 ? 255 : 0)
            let pg = UInt8(Double(g) * Double(a) / 255)
            buf[i * 4] = pg; buf[i * 4 + 1] = pg; buf[i * 4 + 2] = pg; buf[i * 4 + 3] = a
        }
        let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: Painter.space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return Painter.texture(ctx.makeImage()!)
    }

    static func vignette(size: CGSize) -> SKTexture {
        let small = CGSize(width: 320, height: 320 * size.height / size.width)
        return Painter.texture(small, scale: 1) { ctx in
            let c = P(small.width / 2, small.height * 0.55)
            let g = CGGradient(colorsSpace: Painter.space,
                               colors: [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.55)] as CFArray,
                               locations: [0, 0.55, 1])!
            ctx.drawRadialGradient(g, startCenter: c, startRadius: 0, endCenter: c,
                                   endRadius: hypot(small.width, small.height) * 0.62, options: [.drawsAfterEndLocation])
        }
    }

    /// Vertical alpha ramp (opaque bottom → clear top), used for haze planes and glows.
    static func verticalRamp(power: Double = 1.0) -> SKTexture {
        Painter.texture(CGSize(width: 4, height: 256), scale: 1) { ctx in
            for y in 0..<256 {
                let a = pow(1 - Double(y) / 255, power)
                ctx.fillGray(1, a, R(0, CGFloat(y), 4, 1))
            }
        }
    }

    static func rainStreak() -> SKTexture {
        Painter.texture(CGSize(width: 2, height: 44), scale: 1) { ctx in
            Painter.linearGradient(ctx, [(0, CGColor(gray: 1, alpha: 0)), (0.7, CGColor(gray: 1, alpha: 0.9)), (1, CGColor(gray: 1, alpha: 0.2))],
                                   from: P(0, 0), to: P(0, 44))
        }
    }

    static func ripple() -> SKTexture {
        Painter.texture(CGSize(width: 40, height: 10), scale: 1) { ctx in
            ctx.setStrokeColor(gray: 1, alpha: 0.9)
            ctx.setLineWidth(1.2)
            ctx.strokeEllipse(in: R(1, 1, 38, 8))
        }
    }

    static func lightningBolt(seed: UInt64, height h: CGFloat) -> SKTexture {
        var rng = SeededRNG(seed: seed)
        let w = h * 0.45
        let img = Painter.image(CGSize(width: w, height: h)) { ctx in
            func branch(_ start: CGPoint, _ len: CGFloat, _ width: CGFloat, _ depth: Int) {
                var pts = [start]
                var p = start
                let steps = 14
                for _ in 0..<steps {
                    p = P(p.x + rng.cg(-len * 0.09, len * 0.09), p.y - len / CGFloat(steps))
                    pts.append(p)
                    if depth < 2, rng.chance(0.12) { branch(p, len * 0.4, width * 0.55, depth + 1) }
                }
                ctx.setLineJoin(.round)
                ctx.strokeLine(RGB(0xBFD4FF), 0.35, width: width * 4, pts)
                ctx.strokeLine(.white, 1, width: width, pts)
            }
            branch(P(w / 2, h), h * 0.95, 2.2, 0)
        }
        return Painter.texture(Painter.blurred(img, radius: 0.6))
    }

    /// Crow / egret silhouettes, three wing frames.
    static func birdFrames(size s: CGFloat) -> [SKTexture] {
        [0.55, 0.0, -0.45].map { lift in
            Painter.texture(CGSize(width: s, height: s * 0.6)) { ctx in
                let cy = s * 0.28
                let tip = cy + s * 0.28 * CGFloat(lift)
                let p = CGMutablePath()
                p.move(to: P(0, tip))
                p.addQuadCurve(to: P(s * 0.5, cy), control: P(s * 0.26, cy + s * 0.12 * CGFloat(lift) + s * 0.04))
                p.addQuadCurve(to: P(s, tip), control: P(s * 0.74, cy + s * 0.12 * CGFloat(lift) + s * 0.04))
                p.addQuadCurve(to: P(s * 0.5, cy - s * 0.05), control: P(s * 0.74, cy + s * 0.02))
                p.addQuadCurve(to: P(0, tip), control: P(s * 0.26, cy + s * 0.02))
                ctx.fillPath(RGB(0x26262E), 1, p)
                ctx.fillEllipse(RGB(0x26262E), 1, R(s * 0.44, cy - s * 0.06, s * 0.12, s * 0.09))
            }
        }
    }
}
