import AppKit
import SpriteKit

/// A depth layer: grayscale body (tinted by the palette) + coloured window lights (added at night).
struct LayerArt {
    var base: SKTexture
    var lights: SKTexture
    var lightsImage: CGImage?        // kept only until the glow is made from it (see CityScene.addBloom)
    var size: CGSize
    var beacons: [CGPoint] = []      // red aviation lights, layer-local points
    var greenLights: [CGPoint] = []  // mosque minaret lights
}

enum ArtCity {
    static let windowColors: [RGB] = [RGB(0xFFD38A), RGB(0xFFE7BF), RGB(0xFFC872), RGB(0xE4F1FF), RGB(0xD2E8FF), RGB(0xFFF4DE)]

    // MARK: Far skyline: dense towers, minarets, a crane.

    static func farSkyline(width W: CGFloat, height H: CGFloat, seed: UInt64) -> LayerArt {
        var rng = SeededRNG(seed: seed)
        let size = CGSize(width: W, height: H * 1.2)
        let ctx = Painter.context(size), lit = Painter.context(size)
        var art = LayerArt(base: SKTexture(), lights: SKTexture(), size: size)
        let ph1 = rng.d(0, 6), ph2 = rng.d(0, 6)

        var x: CGFloat = -8
        while x < W + 8 {
            let t = Double(x / W)
            if rng.chance(0.06) {
                minaret(ctx, lit, x: x + 4, h: H * rng.cg(0.45, 0.8), w: max(3, W * 0.0045), art: &art)
                x += W * 0.012
                continue
            }
            let w = rng.cg(W * 0.012, W * 0.042)
            let env = 0.5 + 0.5 * sin(t * 2 * .pi * 1.3 + ph1)
            let env2 = 0.5 + 0.5 * sin(t * 2 * .pi * 3.4 + ph2)
            let hf = 0.16 + 0.84 * pow(env * 0.65 + env2 * 0.35, 1.4) * rng.d(0.55, 1.0)
            let h = H * CGFloat(hf)
            let g = rng.d(0.9, 1.0)
            ctx.fillGray(g, 1, R(x, 0, w, h))
            ctx.fillGray(g * 0.9, 1, R(x + w * 0.78, 0, w * 0.22, h))
            rooftop(ctx, x: x, w: w, h: h, g: g, scale: 0.8, rng: &rng)
            if hf > 0.82 && rng.chance(0.8) {
                let top = h + (rng.chance(0.5) ? H * 0.06 : 0)
                if top > h { ctx.fillGray(g, 1, R(x + w * 0.48, h, 0.9, top - h)) }
                art.beacons.append(P(x + w * 0.5, top + 1))
            }
            // Windows: tiny lit dots.
            var wy: CGFloat = 4
            while wy < h - 4 {
                var wx = x + 2
                while wx < x + w - 2.5 {
                    if rng.chance(0.2) {
                        lit.fill(rng.pick(windowColors), rng.d(0.55, 1), R(wx, wy, 1.6, 1.5))
                    }
                    wx += 3.6
                }
                wy += 4.6
            }
            x += w + (rng.chance(0.25) ? rng.cg(1, W * 0.01) : 0)
        }
        crane(ctx, x: W * rng.cg(0.18, 0.3), h: H * 1.05, art: &art)
        art.base = Painter.texture(ctx.makeImage()!)
        let litImage = lit.makeImage()!
        art.lights = Painter.texture(litImage)
        art.lightsImage = litImage
        return art
    }

    // MARK: Near skyline: chunky residential blocks with balconies and rooftop tanks, plus the far bank.

    static func nearSkyline(width W: CGFloat, height H: CGFloat, gap: ClosedRange<CGFloat>, seed: UInt64) -> LayerArt {
        var rng = SeededRNG(seed: seed)
        let size = CGSize(width: W, height: H * 1.15)
        let ctx = Painter.context(size), lit = Painter.context(size)
        var art = LayerArt(base: SKTexture(), lights: SKTexture(), size: size)
        let bank: CGFloat = max(3, H * 0.035)

        var x: CGFloat = -10
        while x < W + 10 {
            let w = rng.cg(W * 0.028, W * 0.07)
            let mid = x + w / 2
            if gap.contains(mid) || gap.contains(x) || gap.contains(x + w) { x += w * 0.5; continue }
            // Lower near the gap so the landmark breathes.
            let distToGap = min(abs(mid - gap.lowerBound), abs(mid - gap.upperBound)) / W
            let cap = 0.35 + 0.65 * smoothstep(0, 0.18, Double(distToGap))
            let h = H * CGFloat(rng.d(0.35, 1.0) * cap)
            let g = rng.d(0.86, 1.0)
            let floorH = max(6, H * 0.075)
            ctx.fillGray(g, 1, R(x, bank, w, h))
            ctx.fillGray(g * 0.86, 1, R(x + w * 0.82, bank, w * 0.18, h))
            // Floors: balcony ledges + window bays.
            var fy = bank + floorH * 0.6
            var floor = 0
            while fy < bank + h - floorH * 0.5 {
                ctx.fillGray(g * 1.04, 1, R(x, fy - 1.2, w * 0.82, 1.1))
                var wx = x + 3
                while wx < x + w * 0.8 - 4 {
                    ctx.fillGray(g * 0.78, 1, R(wx, fy + 1.5, 3.2, floorH * 0.48))
                    if rng.chance(0.36) {
                        let c = rng.pick(windowColors)
                        lit.fill(c, rng.d(0.6, 1), R(wx, fy + 1.5, 3.2, floorH * 0.48))
                    }
                    wx += 6.2
                }
                fy += floorH
                floor += 1
            }
            rooftop(ctx, x: x, w: w * 0.82, h: bank + h, g: g, scale: 1.2, rng: &rng)
            x += w + rng.cg(0, W * 0.006)
        }

        // Far bank: embankment, a row of trees, and the lakeside lamp string.
        ctx.fillGray(0.72, 1, R(0, 0, W, bank))
        var tx: CGFloat = 0
        while tx < W {
            let r = rng.cg(H * 0.04, H * 0.09)
            if !gap.contains(tx) {
                ctx.setFillColor(gray: CGFloat(rng.d(0.6, 0.7)), alpha: 1)
                ctx.fillEllipse(in: R(tx - r, bank - r * 0.3, r * 2, r * 1.6))
            }
            tx += r * 1.1
        }
        var lx: CGFloat = 6
        while lx < W {
            lit.fillEllipse(RGB(0xFFC27A), 0.95, R(lx - 1.1, bank + 1, 2.2, 2.2))
            lx += 22
        }
        art.base = Painter.texture(ctx.makeImage()!)
        let litImage = lit.makeImage()!
        art.lights = Painter.texture(litImage)
        art.lightsImage = litImage
        return art
    }

    private static func rooftop(_ ctx: CGContext, x: CGFloat, w: CGFloat, h: CGFloat, g: Double, scale s: CGFloat, rng: inout SeededRNG) {
        if rng.chance(0.4) {  // stair room / stepped top
            let rw = w * rng.cg(0.3, 0.55)
            ctx.fillGray(g, 1, R(x + rng.cg(0, w - rw), h, rw, 4 * s))
        }
        if rng.chance(0.55) {  // the classic Dhaka rooftop water tank
            let tw = 4 * s, th = 3.6 * s
            let tx = x + rng.cg(1, max(1.5, w - tw - 1))
            ctx.fillGray(g * 0.95, 1, R(tx + 0.5, h, 0.7, 1.4 * s))
            ctx.fillGray(g * 0.95, 1, R(tx + tw - 1.2, h, 0.7, 1.4 * s))
            ctx.setFillColor(gray: CGFloat(g * 0.95), alpha: 1)
            ctx.addPath(CGPath(roundedRect: R(tx, h + 1.4 * s, tw, th), cornerWidth: 1.2 * s, cornerHeight: 1.2 * s, transform: nil))
            ctx.fillPath()
        }
        if rng.chance(0.3) {  // exposed rebar, waiting for the next floor
            var rx = x + 1
            while rx < x + w - 1 { ctx.fillGray(g, 1, R(rx, h, 0.5, 3 * s)); rx += 2.5 * s }
        }
        if rng.chance(0.12) {  // dish / antenna
            ctx.fillGray(g, 1, R(x + w * 0.3, h, 0.7, 9 * s))
        }
    }

    private static func minaret(_ ctx: CGContext, _ lit: CGContext, x: CGFloat, h: CGFloat, w: CGFloat, art: inout LayerArt) {
        ctx.fillGray(0.97, 1, R(x - w / 2, 0, w, h))
        for f in [0.45, 0.7, 0.9] { ctx.fillGray(0.97, 1, R(x - w * 0.9, h * CGFloat(f), w * 1.8, 1.4)) }
        // Small onion dome + finial.
        let d = CGMutablePath()
        d.move(to: P(x - w * 0.75, h))
        d.addCurve(to: P(x, h + w * 2.1), control1: P(x - w * 1.1, h + w * 1.0), control2: P(x - w * 0.2, h + w * 1.4))
        d.addCurve(to: P(x + w * 0.75, h), control1: P(x + w * 0.2, h + w * 1.4), control2: P(x + w * 1.1, h + w * 1.0))
        d.closeSubpath()
        ctx.setFillColor(gray: 0.97, alpha: 1); ctx.addPath(d); ctx.fillPath()
        ctx.fillGray(0.97, 1, R(x - 0.35, h + w * 2.1, 0.7, w * 0.9))
        art.greenLights.append(P(x, h + w * 0.9))
        lit.fill(RGB(0x7DFFB0), 0.8, R(x - w * 0.9, h * 0.9, w * 1.8, 1.4))
    }

    private static func crane(_ ctx: CGContext, x: CGFloat, h: CGFloat, art: inout LayerArt) {
        ctx.setStrokeColor(gray: 0.95, alpha: 1)
        ctx.setLineWidth(0.8)
        let mw: CGFloat = 4
        ctx.stroke(R(x, 0, mw, h))
        var y: CGFloat = 0
        while y < h { ctx.move(to: P(x, y)); ctx.addLine(to: P(x + mw, y + mw)); y += mw }
        ctx.strokePath()
        let jib = h * 0.75
        ctx.fillGray(0.95, 1, R(x - h * 0.25, h, h * 0.25 + mw + jib, 2))
        ctx.fillGray(0.95, 1, R(x - h * 0.22, h - 5, 6, 5))  // counterweight
        ctx.strokeLine(.white, 0.95, width: 0.5, [P(x + mw / 2, h + 9), P(x + mw + jib, h + 2)])
        ctx.strokeLine(.white, 0.95, width: 0.5, [P(x + mw / 2, h + 9), P(x - h * 0.24, h + 2)])
        ctx.fillGray(0.95, 1, R(x + 1, h, 2, 9))
        ctx.strokeLine(.white, 0.9, width: 0.4, [P(x + jib * 0.6, h), P(x + jib * 0.6, h * 0.55)])
        art.beacons.append(P(x + mw / 2, h + 10))
        art.beacons.append(P(x + mw + jib, h + 3))
    }
}
