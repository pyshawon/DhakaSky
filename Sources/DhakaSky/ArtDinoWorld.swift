import AppKit
import SpriteKit

// MARK: - The Dinosaur World landscape (a side-on storybook painting)

extension ArtDinos {
    /// Screen heights (fractions of H) where the three walking bands put their feet, far → near.
    static let bandY: [CGFloat] = [0.462, 0.268, 0.082]
    static let bandScale: [CGFloat] = [0.36, 0.62, 1.0]

    static func world(W: CGFloat, H: CGFloat, seed: UInt64) -> ViewArt {
        var rng = SeededRNG(seed: seed + 17)
        let size = CGSize(width: W, height: H)
        let gT = H * 0.5
        let cam = Cam.make(W: W, H: H, height: 8, pitchDeg: 6, horizon: 0.5, cx: 0.5, cy: 0.3)
        let ctx = Painter.context(size), lit = Painter.context(size)
        for c in [ctx, lit] { c.setLineCap(.round); c.setLineJoin(.round) }

        // Far mountain ranges.
        func range(base: CGFloat, step: CGFloat, hMin: CGFloat, hMax: CGFloat, color: RGB) {
            var x: CGFloat = -step * rng.cg(0.2, 0.8)
            var pts: [CGPoint] = [P(-10, base)]
            while x < W + step {
                pts.append(P(x, base + H * rng.cg(hMin, hMax)))
                x += step * rng.cg(0.5, 0.75)
                pts.append(P(x, base + H * rng.cg(hMin * 0.3, hMin * 0.8)))
                x += step * rng.cg(0.4, 0.6)
            }
            let p = CGMutablePath()
            p.move(to: P(-10, base - H * 0.1))
            p.addLine(to: pts[0])
            for i in 1..<pts.count {
                let m = P((pts[i - 1].x + pts[i].x) / 2, (pts[i - 1].y + pts[i].y) / 2)
                p.addQuadCurve(to: m, control: pts[i - 1])
            }
            p.addLine(to: P(W + 10, base)); p.addLine(to: P(W + 10, base - H * 0.1)); p.closeSubpath()
            ctx.fillPath(color, 1, p)
        }
        range(base: gT - H * 0.02, step: W * 0.16, hMin: 0.09, hMax: 0.17, color: RGB(0xB3BEDC))
        range(base: gT - H * 0.03, step: W * 0.12, hMin: 0.06, hMax: 0.11, color: RGB(0x98ABCF))

        // The volcano: a concave cone with lava rivers and a glowing crater.
        let cx = W * 0.68, peak = H * 0.8, vBase = H * 0.45
        let baseHW = min(W * 0.34, H * 0.48), craterHW = H * 0.055
        func hw(_ y: CGFloat) -> CGFloat {
            let t = (peak - y) / (peak - vBase)
            return craterHW + (baseHW - craterHW) * pow(max(0, t), 1.7)
        }
        let cone = CGMutablePath()
        cone.move(to: P(cx - baseHW, vBase))
        for i in 1...30 {
            let y = vBase + (peak - vBase) * CGFloat(i) / 30
            cone.addLine(to: P(cx - hw(y), y))
        }
        cone.addQuadCurve(to: P(cx + craterHW, peak), control: P(cx, peak - H * 0.022))
        for i in (0..<30).reversed() {
            let y = vBase + (peak - vBase) * CGFloat(i) / 30
            cone.addLine(to: P(cx + hw(y), y))
        }
        cone.closeSubpath()
        // Lava pool peeking over the rim, then the cone over it.
        ctx.fillEllipse(RGB(0xFF7A22), 1, R(cx - craterHW * 0.85, peak - H * 0.012, craterHW * 1.7, H * 0.016))
        ctx.fillEllipse(RGB(0xFFC94A), 1, R(cx - craterHW * 0.5, peak - H * 0.008, craterHW, H * 0.009))
        ctx.fillPath(RGB(0x6E4C44), 1, cone)
        ctx.saveGState()
        ctx.addPath(cone); ctx.clip()
        let litSide = CGMutablePath()
        litSide.move(to: P(cx - baseHW - 5, vBase - 5))
        litSide.addLine(to: P(cx - craterHW * 0.4, peak + 5))
        litSide.addLine(to: P(cx - baseHW * 0.12, vBase - 5))
        litSide.closeSubpath()
        ctx.fillPath(RGB(0x8E6656), 1, litSide)
        ctx.fill(RGB(0x553833), 0.8, R(cx - baseHW, peak - H * 0.035, baseHW * 2, H * 0.04))
        for k in 0..<7 {  // gullies
            let f = CGFloat(k) / 6 * 1.6 - 0.8
            let g = CGMutablePath()
            g.move(to: P(cx + f * craterHW, peak - H * 0.02))
            g.addQuadCurve(to: P(cx + f * baseHW * 0.85, vBase), control: P(cx + f * baseHW * 0.25, vBase + (peak - vBase) * 0.4))
            ctx.addPath(g); ctx.setStrokeColor(RGB(0x4A302B).cg(0.35)); ctx.setLineWidth(H * 0.004); ctx.strokePath()
        }
        ctx.restoreGState()
        // Lava rivers, drawn in colour and again as night glow.
        for (k, len, wig) in [(-0.55, 0.42, 1.0), (0.15, 0.34, -1.0), (0.62, 0.45, 1.0)] as [(CGFloat, CGFloat, CGFloat)] {
            var pts: [CGPoint] = [], ws: [CGFloat] = []
            for i in 0...10 {
                let t = CGFloat(i) / 10 * len
                let y = peak - H * 0.008 - t * (peak - vBase)
                pts.append(P(cx + k * hw(y) * 0.92 + wig * sin(t * 14) * H * 0.008, y))
                ws.append(H * (0.016 - 0.01 * t / len))
            }
            let outer = ArtDinos.tube(pts, ws), inner = ArtDinos.tube(pts, ws.map { $0 * 0.45 })
            ctx.fillPath(RGB(0xF0601E), 1, outer); ctx.fillPath(RGB(0xFFC23A), 1, inner)
            lit.fillPath(RGB(0xFF8A30), 1, outer); lit.fillPath(RGB(0xFFD870), 1, inner)
        }
        lit.fillEllipse(RGB(0xFFB040), 1, R(cx - craterHW * 0.9, peak - H * 0.014, craterHW * 1.8, H * 0.02))

        // Rolling foothills.
        func hills(_ y0: CGFloat, _ amp: CGFloat, _ color: RGB, _ f: CGFloat) {
            let r1 = rng.cg(0, 6), r2 = rng.cg(0, 6)
            let p = CGMutablePath()
            p.move(to: P(0, gT - H * 0.06))
            var x: CGFloat = 0
            while x <= W + 8 {
                let u = x / W
                p.addLine(to: P(x, y0 + amp * (0.5 + 0.35 * sin(u * f + r1) + 0.2 * sin(u * f * 2.3 + r2))))
                x += 8
            }
            p.addLine(to: P(W + 8, gT - H * 0.06)); p.closeSubpath()
            ctx.fillPath(color, 1, p)
        }
        hills(gT - H * 0.005, H * 0.05, RGB(0x8DBB78), 7)
        hills(gT - H * 0.02, H * 0.035, RGB(0x76AC5C), 11)

        // The plain.
        ctx.saveGState()
        ctx.clip(to: R(0, 0, W, gT))
        Painter.linearGradient(ctx, [(0, RGB(0x76AF52).cg()), (1, RGB(0x9CCA6C).cg())], from: P(0, 0), to: P(0, gT))
        for _ in 0..<40 {  // soft grass patches
            let x = rng.cg(0, W), y = rng.cg(0, gT), w = rng.cg(W * 0.05, W * 0.14)
            ctx.fillEllipse(rng.chance(0.5) ? RGB(0x5E9A44) : RGB(0xB2D67E), 0.14, R(x - w / 2, y - w * 0.06, w, w * 0.12))
        }
        ctx.restoreGState()

        // Sandy footpaths under each walking band.
        for (i, by) in bandY.enumerated() {
            let y = H * by, th = H * [0.012, 0.024, 0.04][i]
            let p = CGMutablePath()
            p.move(to: P(-10, y - th * 0.55))
            var x: CGFloat = -10
            let ph = rng.cg(0, 6)
            while x <= W + 10 { p.addLine(to: P(x, y - th * 0.55 + sin(x / W * 9 + ph) * th * 0.18)); x += 10 }
            x = W + 10
            while x >= -10 { p.addLine(to: P(x, y + th * 0.45 + sin(x / W * 7 + ph) * th * 0.18)); x -= 10 }
            p.closeSubpath()
            ctx.fillPath(RGB(0xE2CB8E), 0.55, p)
            for _ in 0..<Int(W / 30) {
                let px = rng.cg(0, W), py = y + rng.cg(-th * 0.4, th * 0.3), r = th * rng.cg(0.06, 0.12)
                ctx.fillEllipse(RGB(0xBFA77A), 0.6, R(px, py, r * 1.4, r))
            }
        }

        // The lake (a hole in the painting; the water shader shows through).
        let lake = R(W * 0.035, H * 0.312, W * 0.4, H * 0.128)
        let lp = CGMutablePath()
        let lr1 = rng.cg(0, 6)
        for i in 0...72 {
            let a = CGFloat(i) / 72 * .pi * 2
            let wob = 1 + 0.05 * sin(a * 3 + lr1) + 0.03 * sin(a * 7)
            let q = P(lake.midX + cos(a) * lake.width / 2 * wob, lake.midY + sin(a) * lake.height / 2 * wob)
            if i == 0 { lp.move(to: q) } else { lp.addLine(to: q) }
        }
        lp.closeSubpath()
        ctx.addPath(lp); ctx.setStrokeColor(RGB(0xE6D3A0).cg()); ctx.setLineWidth(H * 0.012); ctx.strokePath()
        ctx.saveGState(); ctx.setBlendMode(.clear); ctx.addPath(lp); ctx.fillPath(); ctx.restoreGState()
        lit.saveGState(); lit.setBlendMode(.clear); lit.addPath(lp); lit.fillPath(); lit.restoreGState()
        // Lily pads and a few flowers on the water.
        for _ in 0..<7 {
            let a = rng.cg(0, .pi * 2), d = rng.cg(0.45, 0.85)
            let q = P(lake.midX + cos(a) * lake.width / 2 * d, lake.midY + sin(a) * lake.height / 2 * d * 0.8)
            let r = H * rng.cg(0.007, 0.011)
            let pad = CGMutablePath()
            pad.move(to: q)
            pad.addArc(center: q, radius: r, startAngle: 0.35, endAngle: .pi * 2 - 0.1, clockwise: false)
            pad.closeSubpath()
            var t = CGAffineTransform(translationX: q.x, y: q.y).scaledBy(x: 1, y: 0.42).translatedBy(x: -q.x, y: -q.y)
            if let squashed = pad.copy(using: &t) { ctx.fillPath(RGB(0x4E9A4A), 1, squashed) }
            if rng.chance(0.4) { ctx.fillEllipse(RGB(0xF6A8C8), 1, R(q.x - r * 0.3, q.y, r * 0.6, r * 0.4)) }
        }
        // Reeds and cattails at both ends of the lake.
        for side in [lake.minX + lake.width * 0.04, lake.maxX - lake.width * 0.06] {
            for _ in 0..<9 {
                let x = side + rng.cg(-lake.width * 0.05, lake.width * 0.05)
                let y = lake.midY + rng.cg(-lake.height * 0.3, lake.height * 0.1)
                let h = H * rng.cg(0.025, 0.045)
                let lean = rng.cg(-h * 0.15, h * 0.15)
                ctx.strokeLine(RGB(0x3F7A3A), 1, width: H * 0.0025, [P(x, y), P(x + lean, y + h)])
                if rng.chance(0.6) { ctx.fillEllipse(RGB(0x7A4A2A), 1, R(x + lean * 0.85 - H * 0.002, y + h * 0.72, H * 0.004, h * 0.22)) }
            }
        }

        // The jungle edge along the far plain.
        func palm(_ x: CGFloat, _ y: CGFloat, _ h: CGFloat, _ green: RGB) {
            let lean = h * rng.cg(-0.2, 0.2)
            let top = P(x + lean, y + h)
            ctx.addPath(ArtDinos.tube([P(x, y), P(x + lean * 0.4, y + h * 0.55), top], [h * 0.07, h * 0.055, h * 0.045]))
            ctx.setFillColor(RGB(0x8A6A48).cg()); ctx.fillPath()
            for k in 0..<7 {
                let a = CGFloat(k) / 6 * 2.6 + 0.27
                let end = P(top.x + cos(a) * h * 0.45, top.y + sin(a) * h * 0.12 - h * 0.18)
                let mid = P(top.x + cos(a) * h * 0.25, top.y + h * 0.08)
                ctx.addPath(ArtDinos.tube([top, mid, end], [h * 0.09, h * 0.08, h * 0.01]))
                ctx.setFillColor((k % 2 == 0 ? green : green.lighter(0.12)).cg()); ctx.fillPath()
            }
        }
        func araucaria(_ x: CGFloat, _ y: CGFloat, _ h: CGFloat, _ green: RGB) {
            ctx.strokeLine(RGB(0x7A5A3F), 1, width: h * 0.05, [P(x, y), P(x, y + h * 0.95)])
            for k in 0..<4 {
                let ty = y + h * (0.55 + CGFloat(k) * 0.13), w = h * (0.55 - CGFloat(k) * 0.1)
                ctx.fillEllipse(k % 2 == 0 ? green : green.lighter(0.1), 1, R(x - w / 2, ty, w, h * 0.12))
            }
        }
        func bush(_ x: CGFloat, _ y: CGFloat, _ h: CGFloat, _ green: RGB) {
            for k in 0..<4 {
                let r = h * rng.cg(0.4, 0.6)
                ctx.fillEllipse(k % 2 == 0 ? green : green.lighter(0.1), 1, R(x + CGFloat(k - 2) * h * 0.35 - r, y - r * 0.2, r * 2, r * 1.5))
            }
        }
        var x: CGFloat = rng.cg(0, 20)
        let greens = [RGB(0x3E7B4A), RGB(0x4C8C4E), RGB(0x2F6B45), RGB(0x568F3E)]
        while x < W {
            let y = gT - H * rng.cg(0.004, 0.012)
            let h = H * rng.cg(0.05, 0.11)
            let g = rng.pick(greens)
            switch rng.d(0, 1) {
            case ..<0.4: palm(x, y, h, g)
            case ..<0.62: araucaria(x, y, h * 1.15, g)
            default: bush(x, y, h * 0.3, g)
            }
            x += rng.cg(W * 0.015, W * 0.05)
        }

        // Between the bands: flowers, grass tufts, rocks and a nest of eggs (low enough not to cross the next band).
        func flower(_ q: CGPoint, _ r: CGFloat) {
            let col = rng.pick([RGB(0xF6A8C8), RGB(0xFFE066), RGB(0xFFFFFF), RGB(0xC9A8F2), RGB(0xFF9A6A)])
            ctx.strokeLine(RGB(0x4E8A3A), 1, width: r * 0.3, [P(q.x, q.y - r * 2.2), q])
            for k in 0..<5 {
                let a = CGFloat(k) / 5 * .pi * 2
                ctx.fillEllipse(col, 1, R(q.x + cos(a) * r * 0.7 - r * 0.45, q.y + sin(a) * r * 0.7 - r * 0.45, r * 0.9, r * 0.9))
            }
            ctx.fillEllipse(RGB(0xF2B13A), 1, R(q.x - r * 0.35, q.y - r * 0.35, r * 0.7, r * 0.7))
        }
        func tuft(_ q: CGPoint, _ h: CGFloat) {
            for k in -2...2 {
                ctx.strokeLine(RGB(0x4E8E3E), 1, width: h * 0.12, [P(q.x + CGFloat(k) * h * 0.12, q.y), P(q.x + CGFloat(k) * h * 0.3, q.y + h * (1 - abs(CGFloat(k)) * 0.2))])
            }
        }
        func rock(_ q: CGPoint, _ r: CGFloat) {
            ctx.fillEllipse(RGB(0x3A3A3A), 0.15, R(q.x - r * 1.1, q.y - r * 0.15, r * 2.2, r * 0.4))
            ctx.fillPath(RGB(0x9C968E), 1, CGPath(roundedRect: R(q.x - r, q.y, r * 2, r * 1.2), cornerWidth: r * 0.6, cornerHeight: r * 0.55, transform: nil))
            ctx.fillEllipse(RGB(0xBDB8B0), 1, R(q.x - r * 0.6, q.y + r * 0.6, r * 0.8, r * 0.4))
        }
        for _ in 0..<Int(W / 16) {
            let y = H * rng.cg(0.105, 0.24)
            let room = H * 0.262 - y
            let q = P(rng.cg(0, W), y)
            switch rng.d(0, 1) {
            case ..<0.45: flower(q, min(room * 0.3, H * 0.006))
            case ..<0.85: tuft(q, min(room * 0.7, H * 0.014))
            default: rock(q, min(room * 0.45, H * 0.012))
            }
        }
        for _ in 0..<Int(W / 30) {  // between the middle band and the lake
            let q = P(rng.cg(0, W), H * rng.cg(0.285, 0.31))
            if lake.insetBy(dx: -10, dy: -10).contains(q) { continue }
            rng.chance(0.5) ? flower(q, H * 0.004) : tuft(q, H * 0.008)
        }
        // A nest with eggs (one hatching).
        let nest = P(W * 0.86, H * 0.165), nr = H * 0.03
        ctx.fillEllipse(RGB(0x3A3A3A), 0.15, R(nest.x - nr * 1.2, nest.y - nr * 0.25, nr * 2.4, nr * 0.5))
        for (i, ex) in [-0.45, 0.0, 0.45].enumerated() {
            let e = P(nest.x + CGFloat(ex) * nr, nest.y + nr * 0.2 + (i == 1 ? nr * 0.12 : 0))
            let er = nr * 0.32
            ctx.fillEllipse(RGB(0xF6F0DC), 1, R(e.x - er, e.y - er * 0.4, er * 2, er * 2.7))
            for _ in 0..<3 { ctx.fillEllipse(RGB(0x8BC48A), 1, R(e.x + rng.cg(-er * 0.6, er * 0.4), e.y + rng.cg(0, er * 1.6), er * 0.35, er * 0.3)) }
            if i == 1 {  // a baby peeking out
                ctx.fillEllipse(RGB(0x8FCB6A), 1, R(e.x - er * 0.75, e.y + er * 1.6, er * 1.5, er * 1.15))
                ctx.fillEllipse(.white, 1, R(e.x - er * 0.05, e.y + er * 2.05, er * 0.45, er * 0.5))
                ctx.fillEllipse(RGB(0x1E1A1A), 1, R(e.x + er * 0.06, e.y + er * 2.1, er * 0.28, er * 0.34))
                ctx.fillPath(RGB(0xF6F0DC), 1, CGPath.poly([P(e.x - er, e.y + er * 1.75), P(e.x - er * 0.6, e.y + er * 2.05), P(e.x - er * 0.3, e.y + er * 1.7),
                                                            P(e.x + er * 0.2, e.y + er * 1.95), P(e.x + er * 0.5, e.y + er * 1.65), P(e.x + er, e.y + er * 1.8),
                                                            P(e.x + er, e.y + er * 1.4), P(e.x - er, e.y + er * 1.4)]))
            }
        }
        let twig = CGMutablePath()
        twig.addEllipse(in: R(nest.x - nr * 1.05, nest.y - nr * 0.2, nr * 2.1, nr * 0.75))
        ctx.fillPath(RGB(0xA77B4E), 1, twig)
        for k in 0..<10 {
            let a = CGFloat(k) / 10 * .pi
            ctx.strokeLine(RGB(0x7E5A36), 1, width: H * 0.0018, [P(nest.x - cos(a) * nr, nest.y + nr * 0.1 + sin(a) * nr * 0.18), P(nest.x - cos(a + 0.6) * nr * 0.7, nest.y - nr * 0.1)])
        }

        // Night glow from the lava, softened.
        var lights = lit.makeImage()!
        lights = Painter.blurred(lights, radius: H * 0.004 * Painter.scale)

        // Foreground: ferns and rocks along the bottom edge, in front of the nearest band.
        let fg = Painter.context(size)
        fg.setLineCap(.round)
        func fern(_ q: CGPoint, _ h: CGFloat, _ green: RGB) {
            for k in 0..<7 {
                let a = CGFloat(k) / 6 * 2.2 + 0.47
                let tip = P(q.x + cos(a) * h * 0.9, q.y + sin(a) * h)
                let mid = P(q.x + cos(a) * h * 0.45, q.y + sin(a) * h * 0.75)
                fg.addPath(ArtDinos.tube([q, mid, tip], [h * 0.05, h * 0.04, h * 0.01]))
                fg.setFillColor(green.darker(0.2).cg()); fg.fillPath()
                for j in 1..<9 {  // leaflets
                    let t = CGFloat(j) / 9
                    let s = P(q.x + (tip.x - q.x) * t, q.y + (mid.y - q.y) * min(1, t * 1.6) + (tip.y - mid.y) * max(0, t * 1.6 - 0.6))
                    let len = h * 0.16 * (1 - t * 0.7)
                    for side in [-1.0, 1.0] as [CGFloat] {
                        let la = a + side * 1.1
                        fg.addPath(ArtDinos.tube([s, P(s.x + cos(la) * len, s.y + sin(la) * len)], [len * 0.35, len * 0.08]))
                        fg.setFillColor((j % 2 == 0 ? green : green.lighter(0.08)).cg()); fg.fillPath()
                    }
                }
            }
        }
        func fgRock(_ q: CGPoint, _ r: CGFloat) {
            fg.fillPath(RGB(0x8E887F), 1, CGPath(roundedRect: R(q.x - r, q.y - r * 0.3, r * 2, r * 1.3), cornerWidth: r * 0.6, cornerHeight: r * 0.6, transform: nil))
            fg.fillEllipse(RGB(0xB0AAA2), 1, R(q.x - r * 0.65, q.y + r * 0.45, r * 0.9, r * 0.4))
            fg.fillEllipse(RGB(0x6DA64F), 1, R(q.x - r * 0.9, q.y + r * 0.75, r * 0.8, r * 0.25))
        }
        fern(P(W * 0.02, -H * 0.01), H * 0.17, RGB(0x4E9446))
        fern(P(W * 0.07, -H * 0.03), H * 0.12, RGB(0x5BA04E))
        fgRock(P(W * 0.13, H * 0.005), H * 0.03)
        fern(P(W * 0.985, -H * 0.01), H * 0.16, RGB(0x4E9446))
        fern(P(W * 0.93, -H * 0.03), H * 0.11, RGB(0x5BA04E))
        fgRock(P(W * 0.885, 0), H * 0.022)
        var fx: CGFloat = W * 0.16
        while fx < W * 0.86 {  // a low fringe of grass and flowers along the very bottom
            let h = H * rng.cg(0.012, 0.022)
            for k in -2...2 {
                fg.strokeLine(RGB(0x4E8E3E), 1, width: h * 0.13, [P(fx + CGFloat(k) * h * 0.12, -2), P(fx + CGFloat(k) * h * 0.32, h * (1 - abs(CGFloat(k)) * 0.2))])
            }
            if rng.chance(0.35) {
                let r = H * 0.005, q = P(fx + h * 0.5, h * 0.8)
                let col = rng.pick([RGB(0xF6A8C8), RGB(0xFFE066), RGB(0xFFFFFF), RGB(0xFF9A6A)])
                for k in 0..<5 {
                    let a = CGFloat(k) / 5 * .pi * 2
                    fg.fillEllipse(col, 1, R(q.x + cos(a) * r * 0.7 - r * 0.45, q.y + sin(a) * r * 0.7 - r * 0.45, r * 0.9, r * 0.9))
                }
                fg.fillEllipse(RGB(0xF2B13A), 1, R(q.x - r * 0.35, q.y - r * 0.35, r * 0.7, r * 0.7))
            }
            fx += rng.cg(W * 0.02, W * 0.06)
        }

        var art = ViewArt(base: ctx.makeImage()!, lights: lights, cam: cam, hasWater: true)
        art.waterTint = RGB(0x3FA7A0)
        art.rippleRect = lake.insetBy(dx: lake.width * 0.12, dy: lake.height * 0.2)
        art.skyline = 0
        art.groundTop = gT
        art.hazeDepth = 0
        art.dino = DinoExtras(foreground: fg.makeImage()!, crater: P(cx, peak), craterHW: craterHW, lake: lake,
                              bands: zip(bandY, bandScale).map { (H * $0, $1) }, ppm: H * 0.032)
        return art
    }
}
