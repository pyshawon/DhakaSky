import AppKit
import SpriteKit
import Vision

struct LandmarkArt {
    var base: SKTexture
    var lights: SKTexture?
    var size: CGSize
}

/// Hand-built vector drawings of Dhaka landmarks, in full colour (lit at runtime by multiplying the ambient light).
enum ArtLandmarks {
    static func make(_ id: String, height h: CGFloat, screenWidth W: CGFloat) -> LandmarkArt? {
        if id.hasPrefix("custom:") { return custom(file: String(id.dropFirst(7)), height: h, maxWidth: W * 0.6) }
        switch Landmark(rawValue: id) ?? .parliament {
        case .parliament: return parliament(h: h)
        case .shaheedMinar: return shaheedMinar(h: h * 1.08)
        case .ahsanManzil: return ahsanManzil(h: h * 0.95)
        case .satGambuj: return satGambuj(h: h * 0.95)
        case .hatirjheel: return hatirjheel(h: h * 0.9, w: W * 0.82)
        case .lalbagh: return lalbagh(h: h * 0.95)
        case .padma: return padma(h: h * 0.62, w: W * 1.02)
        case .none: return nil
        }
    }

    /// Two passes into separate contexts: daylight art and night lights.
    private static func draw(_ size: CGSize, _ body: (CGContext, CGContext) -> Void) -> LandmarkArt {
        let ctx = Painter.context(size), lit = Painter.context(size)
        body(ctx, lit)
        return LandmarkArt(base: Painter.texture(ctx.makeImage()!), lights: Painter.texture(lit.makeImage()!), size: size)
    }

    private static func pointedArch(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let spring = y + h - w * 0.62
        p.move(to: P(x, y))
        p.addLine(to: P(x, spring))
        p.addQuadCurve(to: P(x + w / 2, y + h), control: P(x, y + h - w * 0.08))
        p.addQuadCurve(to: P(x + w, spring), control: P(x + w, y + h - w * 0.08))
        p.addLine(to: P(x + w, y))
        p.closeSubpath()
        return p
    }

    private static func roundArch(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let r = w / 2
        p.move(to: P(x, y))
        p.addLine(to: P(x, y + h - r))
        p.addArc(center: P(x + r, y + h - r), radius: r, startAngle: .pi, endAngle: 0, clockwise: true)
        p.addLine(to: P(x + w, y))
        p.closeSubpath()
        return p
    }

    private static func onionDome(cx: CGFloat, base y: CGFloat, r: CGFloat, height: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: P(cx - r * 0.92, y))
        p.addCurve(to: P(cx, y + height), control1: P(cx - r * 1.32, y + height * 0.55), control2: P(cx - r * 0.12, y + height * 0.62))
        p.addCurve(to: P(cx + r * 0.92, y), control1: P(cx + r * 0.12, y + height * 0.62), control2: P(cx + r * 1.32, y + height * 0.55))
        p.closeSubpath()
        return p
    }

    // MARK: - Jatiya Sangsad Bhaban (Louis Kahn): concrete masses, giant geometric voids, marble inlay bands.

    static func parliament(h: CGFloat) -> LandmarkArt {
        let w = h * 1.8
        let concrete = RGB(0xB9AFA3), side = RGB(0x958C81), void = RGB(0x4A4541), deep = RGB(0x2D2A28)
        let marble = RGB(0xE8E2D7), back = RGB(0xA89F94)
        let warm = RGB(0xFFC77A)
        let plinth = h * 0.06

        return draw(CGSize(width: w, height: h)) { ctx, lit in
            func bands(_ x0: CGFloat, _ x1: CGFloat, _ top: CGFloat) {
                var y = plinth + h * 0.07
                while y < top - h * 0.02 {
                    ctx.fill(marble, 0.9, R(x0, y, x1 - x0, max(1, h * 0.006)))
                    y += h * 0.085
                }
            }
            func punch(_ path: CGPath, through: CGPath? = nil, depthShift: CGFloat = 0) {
                ctx.fillPath(void, 1, path)
                let bb = path.boundingBoxOfPath
                ctx.saveGState(); ctx.addPath(path); ctx.clip()
                ctx.fillPath(deep, 1, CGPath(ellipseIn: bb.offsetBy(dx: bb.width * 0.18 + depthShift, dy: -bb.height * 0.12), transform: nil))
                ctx.restoreGState()
                if let through {
                    ctx.saveGState(); ctx.setBlendMode(.clear); ctx.addPath(through); ctx.fillPath(); ctx.restoreGState()
                }
                lit.fillPath(warm, 0.55, path)
            }

            // Back row: taller towers glimpsed behind, with voids open to the sky.
            for (x0, x1, top) in [(0.05, 0.2, 0.8), (0.29, 0.4, 0.9), (0.6, 0.71, 0.9), (0.8, 0.95, 0.8)] as [(CGFloat, CGFloat, CGFloat)] {
                let r = R(w * x0, plinth, w * (x1 - x0), h * top - plinth)
                ctx.fill(back, 1, r)
                ctx.saveGState(); ctx.setBlendMode(.clear)
                let cr = r.width * 0.22
                ctx.fillEllipse(in: R(r.midX - cr, r.maxY - cr * 3.2, cr * 2, cr * 2))
                ctx.fill(R(r.minX + r.width * 0.15, r.maxY - h * 0.33, r.width * 0.08, h * 0.16))
                ctx.restoreGState()
                lit.fill(warm, 0.25, R(r.minX, r.maxY - h * 0.05, r.width, h * 0.02))
            }

            // Front masses: (x0, x1, top, kind)
            let blocks: [(CGFloat, CGFloat, CGFloat, Int)] = [
                (0.0, 0.13, 0.5, 0), (0.13, 0.24, 0.66, 1), (0.24, 0.38, 0.58, 2), (0.38, 0.62, 1.0, 3),
                (0.62, 0.76, 0.58, 0), (0.76, 0.87, 0.66, 1), (0.87, 1.0, 0.5, 2),
            ]
            for (fx0, fx1, ft, kind) in blocks {
                let x0 = w * fx0, x1 = w * fx1, top = h * ft, bw = x1 - x0, cx = (x0 + x1) / 2
                ctx.fill(concrete, 1, R(x0, plinth, bw, top - plinth))
                ctx.fill(side, 1, R(x0, plinth, bw * 0.07, top - plinth))
                if kind == 3 {  // octagonal assembly hall: angled side faces
                    ctx.fill(side, 1, R(x0, plinth, bw * 0.17, top - plinth))
                    ctx.fill(side.darker(0.08), 1, R(x1 - bw * 0.17, plinth, bw * 0.17, top - plinth))
                }
                bands(x0, x1, top)
                ctx.fill(marble, 0.7, R(x0, top - 2, bw, 2))
                lit.fill(RGB(0xFFE2B0), 0.1, R(x0, plinth, bw, (top - plinth) * 0.6))

                switch kind {
                case 0:
                    let r = bw * 0.33, cy = plinth + (top - plinth) * 0.56
                    let c = CGPath(ellipseIn: R(cx - r, cy - r, r * 2, r * 2), transform: nil)
                    punch(c, through: CGPath(ellipseIn: R(cx - r * 0.42 - r * 0.15, cy - r * 0.42 + r * 0.1, r * 0.84, r * 0.84), transform: nil))
                case 1:
                    for i in 0..<3 {
                        let sx = x0 + bw * (0.2 + CGFloat(i) * 0.25)
                        punch(CGPath(rect: R(sx, plinth + (top - plinth) * 0.22, bw * 0.11, (top - plinth) * 0.56), transform: nil))
                    }
                case 2:
                    let tri = CGPath.poly([P(x0 + bw * 0.14, top - h * 0.08), P(x1 - bw * 0.14, top - h * 0.08), P(cx, plinth + (top - plinth) * 0.3)])
                    punch(tri, through: CGPath.poly([P(cx - bw * 0.12, top - h * 0.12), P(cx + bw * 0.12, top - h * 0.12), P(cx, top - h * 0.24)]))
                    punch(CGPath(rect: R(cx - bw * 0.08, plinth + h * 0.03, bw * 0.16, h * 0.06), transform: nil))
                default:
                    let ar = bw * 0.24
                    let arch = CGMutablePath()
                    arch.addArc(center: P(cx, plinth), radius: ar, startAngle: 0, endAngle: .pi, clockwise: false)
                    arch.closeSubpath()
                    punch(arch)
                    punch(CGPath(rect: R(cx - bw * 0.05, plinth + ar + h * 0.06, bw * 0.1, h * 0.3), transform: nil))
                    for i in -1...1 {
                        let r = bw * 0.06
                        let ccx = cx + CGFloat(i) * bw * 0.22, ccy = top - h * 0.12
                        punch(CGPath(ellipseIn: R(ccx - r, ccy - r, r * 2, r * 2), transform: nil),
                              through: CGPath(ellipseIn: R(ccx - r * 0.5, ccy - r * 0.5, r, r), transform: nil))
                    }
                    for i in [-1, 1] {
                        let tri = CGPath.poly([P(cx + CGFloat(i) * bw * 0.26 - bw * 0.07, top - h * 0.3), P(cx + CGFloat(i) * bw * 0.26 + bw * 0.07, top - h * 0.3),
                                               P(cx + CGFloat(i) * bw * 0.26, top - h * 0.45)])
                        punch(tri)
                    }
                }
            }
            ctx.fill(RGB(0xA0978C), 1, R(0, 0, w, plinth))
            ctx.fill(marble, 0.9, R(0, plinth - 1.5, w, 1.5))
            lit.fill(warm, 0.35, R(0, plinth - 2, w, 2))
        }
    }

    // MARK: - Central Shaheed Minar: the mother and her martyred sons before a red sun.

    static func shaheedMinar(h: CGFloat) -> LandmarkArt {
        let w = h * 1.35
        let marble = RGB(0xEFECE6), marbleShade = RGB(0xC9C4BB), bar = RGB(0x3A3A40), stone = RGB(0xD3CCC1)
        let base = h * 0.1
        return draw(CGSize(width: w, height: h)) { ctx, lit in
            // Steps.
            for i in 0..<4 {
                let sw = w * (1 - CGFloat(i) * 0.07), y = CGFloat(i) * h * 0.025
                ctx.fill(stone.darker(CGFloat(3 - i) * 0.03), 1, R((w - sw) / 2, y, sw, h * 0.025))
                ctx.fill(marble, 0.8, R((w - sw) / 2, y + h * 0.025 - 1, sw, 1))
            }
            // The red sun.
            let sr = h * 0.21, sc = P(w * 0.5, h * 0.58)
            ctx.fillEllipse(RGB(0xB3352E), 1, R(sc.x - sr, sc.y - sr, sr * 2, sr * 2))
            lit.fillEllipse(RGB(0xFF5544), 0.55, R(sc.x - sr, sc.y - sr, sr * 2, sr * 2))
            lit.fillEllipse(RGB(0xFF6A50), 0.12, R(sc.x - sr * 1.5, sc.y - sr * 1.5, sr * 3, sr * 3))

            func frame(cx: CGFloat, fw: CGFloat, fh: CGFloat, bent: Bool) {
                let pw = fw * 0.13
                let top = base + fh
                // Iron bars inside.
                var bx = cx - fw / 2 + pw * 1.8
                while bx < cx + fw / 2 - pw * 1.5 { ctx.fill(bar, 0.85, R(bx, base, max(1, fw * 0.02), fh)); bx += fw * 0.13 }
                for sx in [cx - fw / 2, cx + fw / 2 - pw] {
                    ctx.fill(marble, 1, R(sx, base, pw, fh))
                    ctx.fill(marbleShade, 1, R(sx + pw * 0.62, base, pw * 0.38, fh))
                    lit.fill(.white, 0.22, R(sx, base, pw, fh))
                }
                ctx.fill(marble, 1, R(cx - fw / 2, top - pw, fw, pw))
                if bent {
                    // The bowed head, foreshortened toward the viewer.
                    let bh = fh * 0.2, flare = fw * 0.14
                    let l = CGPath.poly([P(cx - fw / 2, top), P(cx - fw / 2 + pw, top), P(cx - fw / 2 - flare + pw, top + bh), P(cx - fw / 2 - flare, top + bh)])
                    let r = CGPath.poly([P(cx + fw / 2 - pw, top), P(cx + fw / 2, top), P(cx + fw / 2 + flare, top + bh), P(cx + fw / 2 + flare - pw, top + bh)])
                    var bx2 = cx - fw / 2 - flare + pw * 2
                    while bx2 < cx + fw / 2 + flare - pw * 1.5 {
                        let t = (bx2 - (cx - fw / 2 - flare)) / (fw + flare * 2)
                        let bottomX = cx - fw / 2 + t * fw
                        ctx.strokeLine(bar, 0.85, width: max(1, fw * 0.02), [P(bottomX, top), P(bx2, top + bh)])
                        bx2 += fw * 0.15
                    }
                    ctx.fillPath(marble, 1, l); ctx.fillPath(marbleShade, 1, r)
                    ctx.fill(marble, 1, R(cx - fw / 2 - flare, top + bh - pw, fw + flare * 2, pw))
                    lit.fillPath(.white, 0.2, l); lit.fillPath(.white, 0.2, r)
                }
            }
            frame(cx: w * 0.14, fw: w * 0.1, fh: h * 0.34, bent: false)
            frame(cx: w * 0.86, fw: w * 0.1, fh: h * 0.34, bent: false)
            frame(cx: w * 0.3, fw: w * 0.12, fh: h * 0.48, bent: false)
            frame(cx: w * 0.7, fw: w * 0.12, fh: h * 0.48, bent: false)
            frame(cx: w * 0.5, fw: w * 0.2, fh: h * 0.66, bent: true)
            // Flowers laid at the base.
            var rng = SeededRNG(seed: 21)
            for _ in 0..<70 {
                let fx = rng.cg(w * 0.25, w * 0.75), fy = rng.cg(base - h * 0.012, base + h * 0.01)
                ctx.fillEllipse(rng.pick([RGB(0xC8423A), RGB(0xE7A13A), RGB(0xEEE6D8), RGB(0x6E8B4A)]), 0.95, R(fx, fy, h * 0.012, h * 0.01))
            }
        }
    }

    // MARK: - Ahsan Manzil: the pink palace on the Buriganga.

    static func ahsanManzil(h: CGFloat) -> LandmarkArt {
        let w = h * 1.75
        let pink = RGB(0xCF8C9C), pinkLight = RGB(0xDA9CAB), pinkShade = RGB(0xB07285)
        let trim = RGB(0xF2E8E3), dark = RGB(0x5A3E4A), stone = RGB(0xE3DAD2), dome = RGB(0xC98196)
        let warm = RGB(0xFFC48A)
        return draw(CGSize(width: w, height: h)) { ctx, lit in
            let pl = h * 0.06
            ctx.fill(stone, 1, R(0, 0, w, pl))
            ctx.fill(pink, 1, R(w * 0.02, pl, w * 0.96, h * 0.4))
            // End pavilions.
            for x in [w * 0.02, w * 0.89] { ctx.fill(pinkLight, 1, R(x, pl, w * 0.09, h * 0.42)) }
            lit.fill(RGB(0xFFB8C8), 0.12, R(w * 0.02, pl, w * 0.96, h * 0.4))

            // Two-storey arcades.
            for (y0, ah) in [(pl + h * 0.02, h * 0.15), (h * 0.27, h * 0.15)] {
                let bays = 18
                let bw = w * 0.96 / CGFloat(bays)
                for i in 0..<bays {
                    let x = w * 0.02 + CGFloat(i) * bw
                    if x > w * 0.38 && x < w * 0.6 { continue }
                    let a = roundArch(x + bw * 0.2, y0, bw * 0.6, ah)
                    ctx.fillPath(dark, 1, a)
                    ctx.setStrokeColor(trim.cg(0.9)); ctx.setLineWidth(max(0.8, h * 0.004)); ctx.addPath(a); ctx.strokePath()
                    lit.fillPath(warm, 0.5, a)
                }
            }
            ctx.fill(trim, 1, R(w * 0.02, h * 0.248, w * 0.96, h * 0.012))
            ctx.fill(trim, 1, R(w * 0.01, h * 0.455, w * 0.98, h * 0.016))
            // Balustrade.
            var bx = w * 0.015
            while bx < w * 0.985 { ctx.fill(trim, 0.95, R(bx, h * 0.471, w * 0.004, h * 0.03)); bx += w * 0.012 }
            ctx.fill(trim, 1, R(w * 0.01, h * 0.5, w * 0.98, h * 0.008))

            // Central portico.
            ctx.fill(pinkLight, 1, R(w * 0.39, pl, w * 0.22, h * 0.48))
            ctx.fill(pinkShade, 1, R(w * 0.59, pl, w * 0.02, h * 0.48))
            for i in 0..<3 {
                let a = roundArch(w * (0.405 + CGFloat(i) * 0.067), h * 0.27, w * 0.05, h * 0.17)
                ctx.fillPath(dark, 1, a); lit.fillPath(warm, 0.55, a)
            }
            let ped = CGPath.poly([P(w * 0.385, h * 0.535), P(w * 0.615, h * 0.535), P(w * 0.5, h * 0.6)])
            ctx.fillPath(trim, 1, ped)
            ctx.fill(trim, 1, R(w * 0.385, h * 0.52, w * 0.23, h * 0.016))
            // Grand staircase.
            let stairs = CGPath.poly([P(w * 0.33, 0), P(w * 0.67, 0), P(w * 0.575, h * 0.26), P(w * 0.425, h * 0.26)])
            ctx.fillPath(stone, 1, stairs)
            ctx.saveGState(); ctx.addPath(stairs); ctx.clip()
            var sy: CGFloat = 0
            while sy < h * 0.26 { ctx.fill(RGB(0xBFB4AA), 1, R(0, sy, w, max(0.7, h * 0.003))); sy += h * 0.013 }
            ctx.restoreGState()

            // Drum and onion dome.
            let cx = w * 0.5
            ctx.fill(pink, 1, R(cx - w * 0.055, h * 0.6, w * 0.11, h * 0.1))
            ctx.fill(pinkShade, 1, R(cx + w * 0.03, h * 0.6, w * 0.025, h * 0.1))
            for i in -1...1 {
                let a = roundArch(cx + CGFloat(i) * w * 0.03 - w * 0.008, h * 0.615, w * 0.016, h * 0.055)
                ctx.fillPath(dark, 1, a); lit.fillPath(warm, 0.6, a)
            }
            ctx.fill(trim, 1, R(cx - w * 0.06, h * 0.7, w * 0.12, h * 0.012))
            let d = onionDome(cx: cx, base: h * 0.712, r: w * 0.062, height: h * 0.25)
            ctx.fillPath(dome, 1, d)
            ctx.saveGState(); ctx.addPath(d); ctx.clip()
            ctx.fill(pinkShade, 0.6, R(cx + w * 0.012, h * 0.7, w * 0.08, h * 0.3))
            for i in -2...2 {
                let rib = CGMutablePath()
                rib.move(to: P(cx + CGFloat(i) * w * 0.022, h * 0.712))
                rib.addQuadCurve(to: P(cx, h * 0.96), control: P(cx + CGFloat(i) * w * 0.034, h * 0.86))
                ctx.setStrokeColor(trim.cg(0.45)); ctx.setLineWidth(max(0.7, h * 0.003)); ctx.addPath(rib); ctx.strokePath()
            }
            ctx.restoreGState()
            lit.fillPath(RGB(0xFFC0D0), 0.22, d)
            ctx.fill(RGB(0xC9A45C), 1, R(cx - 0.6, h * 0.95, 1.2, h * 0.05))
            ctx.fillEllipse(RGB(0xC9A45C), 1, R(cx - h * 0.008, h * 0.965, h * 0.016, h * 0.016))
            // Kiosks on the portico corners.
            for kx in [w * 0.395, w * 0.605] {
                ctx.fill(trim, 1, R(kx - w * 0.012, h * 0.54, w * 0.024, h * 0.04))
                ctx.fillPath(dome, 1, onionDome(cx: kx, base: h * 0.58, r: w * 0.014, height: h * 0.05))
            }
        }
    }

    // MARK: - Sat Gambuj Mosque: three domes, four domed corner towers.

    static func satGambuj(h: CGFloat) -> LandmarkArt {
        let w = h * 1.45
        let cream = RGB(0xE8DEC8), shade = RGB(0xC6BAA1), dark = RGB(0x4C4136), domeC = RGB(0xEEE6D6), gold = RGB(0xC6A35A)
        let warm = RGB(0xFFCF8A)
        return draw(CGSize(width: w, height: h)) { ctx, lit in
            let pl = h * 0.07
            func tower(_ cx: CGFloat, _ tw: CGFloat, _ th: CGFloat, _ tone: Double) {
                let c = cream.darker(tone), s = shade.darker(tone)
                ctx.fill(s, 1, R(cx - tw / 2, pl, tw, th - pl))
                ctx.fill(c, 1, R(cx - tw * 0.28, pl, tw * 0.56, th - pl))
                var y = pl + h * 0.1
                while y < th - h * 0.04 { ctx.fill(s.darker(0.1), 1, R(cx - tw / 2, y, tw, max(1, h * 0.008))); y += h * 0.1 }
                // Open kiosk on top.
                let ky = th
                ctx.fill(c, 1, R(cx - tw * 0.6, ky, tw * 1.2, h * 0.012))
                for px in [cx - tw * 0.45, cx + tw * 0.3] { ctx.fill(c, 1, R(px, ky + h * 0.012, tw * 0.15, h * 0.05)) }
                lit.fill(warm, 0.35, R(cx - tw * 0.3, ky + h * 0.012, tw * 0.6, h * 0.05))
                ctx.fill(c, 1, R(cx - tw * 0.6, ky + h * 0.062, tw * 1.2, h * 0.01))
                ctx.fillPath(domeC.darker(tone), 1, onionDome(cx: cx, base: ky + h * 0.072, r: tw * 0.55, height: h * 0.08))
                ctx.fill(gold, 1, R(cx - 0.5, ky + h * 0.15, 1, h * 0.03))
            }
            // Back towers, then hall, then front towers.
            tower(w * 0.2, w * 0.045, h * 0.5, 0.08)
            tower(w * 0.8, w * 0.045, h * 0.5, 0.08)
            // Platform with a row of blind arches.
            ctx.fill(RGB(0xD8CDB5), 1, R(0, 0, w, pl))
            var ax = w * 0.02
            while ax < w * 0.97 { ctx.fillPath(RGB(0xA89A80), 1, pointedArch(ax, h * 0.012, w * 0.022, pl * 0.7)); ax += w * 0.04 }
            // Prayer hall.
            ctx.fill(cream, 1, R(w * 0.17, pl, w * 0.66, h * 0.3))
            ctx.fill(cream.lighter(0.25), 1, R(w * 0.415, pl, w * 0.17, h * 0.32))
            ctx.fill(shade, 1, R(w * 0.575, pl, w * 0.01, h * 0.32))
            let mainArch = pointedArch(w * 0.45, pl, w * 0.1, h * 0.22)
            ctx.fillPath(dark, 1, mainArch); lit.fillPath(warm, 0.6, mainArch)
            for x in [w * 0.245, w * 0.675] {
                ctx.fill(cream.lighter(0.12), 1, R(x - w * 0.01, pl, w * 0.1, h * 0.25))
                let a = pointedArch(x + w * 0.012, pl, w * 0.056, h * 0.16)
                ctx.fillPath(dark, 1, a); lit.fillPath(warm, 0.55, a)
            }
            // Merlons.
            var mx = w * 0.17
            while mx < w * 0.83 { ctx.fill(cream, 1, R(mx, pl + h * 0.3, w * 0.011, h * 0.02)); mx += w * 0.022 }
            // Three domes.
            for (cx, r) in [(w * 0.32, w * 0.07), (w * 0.68, w * 0.07), (w * 0.5, w * 0.092)] {
                let dy = pl + h * 0.3
                ctx.fill(cream, 1, R(cx - r * 0.95, dy, r * 1.9, h * 0.035))
                let d = onionDome(cx: cx, base: dy + h * 0.035, r: r, height: r * 1.75)
                ctx.fillPath(domeC, 1, d)
                ctx.saveGState(); ctx.addPath(d); ctx.clip()
                ctx.fillEllipse(shade, 0.45, R(cx + r * 0.1, dy, r * 1.4, r * 2.2))
                ctx.restoreGState()
                lit.fillPath(RGB(0xFFE7B0), 0.16, d)
                let ft = dy + h * 0.035 + r * 1.75
                ctx.fill(gold, 1, R(cx - 0.6, ft - 1, 1.2, r * 0.5))
                ctx.fillEllipse(gold, 1, R(cx - r * 0.07, ft + r * 0.1, r * 0.14, r * 0.14))
                ctx.fillEllipse(gold, 1, R(cx - r * 0.05, ft + r * 0.28, r * 0.1, r * 0.1))
            }
            tower(w * 0.135, w * 0.06, h * 0.6, 0)
            tower(w * 0.865, w * 0.06, h * 0.6, 0)
        }
    }

    // MARK: - Hatirjheel: sweeping white arches over the lake, glass towers behind.

    static func hatirjheel(h: CGFloat, w: CGFloat) -> LandmarkArt {
        let white = RGB(0xEDEDF0), under = RGB(0xA9AEB8), glass = RGB(0x9FB2C6)
        var rng = SeededRNG(seed: 99)
        return draw(CGSize(width: w, height: h)) { ctx, lit in
            // Towers.
            for (fx, fw, fh) in [(0.06, 0.06, 0.72), (0.16, 0.05, 0.92), (0.66, 0.07, 1.0), (0.8, 0.05, 0.8), (0.9, 0.06, 0.62)] as [(CGFloat, CGFloat, CGFloat)] {
                let r = R(w * fx, 0, w * fw, h * fh)
                ctx.fill(glass, 1, r)
                ctx.fill(glass.darker(0.18), 1, R(r.maxX - r.width * 0.3, 0, r.width * 0.3, r.height))
                var y: CGFloat = 4
                while y < r.height - 3 {
                    ctx.fill(glass.lighter(0.25), 0.6, R(r.minX, y, r.width, 0.7))
                    var x = r.minX + 2
                    while x < r.maxX - 2.5 {
                        if rng.chance(0.45) { lit.fill(rng.pick(ArtCity.windowColors), 0.85, R(x, y + 1, 2, 2.2)) }
                        x += 3.5
                    }
                    y += 4.2
                }
                ctx.fill(glass.lighter(0.4), 1, R(r.minX, r.maxY - 2, r.width, 2))
            }
            let deckY = h * 0.2, deckH = h * 0.035
            // Under-deck arches.
            let piers: [CGFloat] = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]
            for i in 0..<(piers.count - 1) {
                let x0 = w * piers[i], x1 = w * piers[i + 1]
                let arch = CGMutablePath()
                arch.addEllipse(in: R(x0, -deckY * 0.95, x1 - x0, deckY * 1.9))
                ctx.saveGState(); ctx.clip(to: R(0, 0, w, deckY))
                ctx.setStrokeColor(white.cg()); ctx.setLineWidth(max(2, h * 0.016)); ctx.addPath(arch); ctx.strokePath()
                lit.saveGState(); lit.clip(to: R(0, 0, w, deckY))
                lit.setStrokeColor(RGB(0x8A7CFF).cg(0.55)); lit.setLineWidth(max(2, h * 0.02)); lit.addPath(arch); lit.strokePath()
                lit.restoreGState()
                ctx.restoreGState()
                var sx = x0 + (x1 - x0) * 0.12
                while sx < x1 - (x1 - x0) * 0.1 { ctx.fill(white, 0.9, R(sx, deckY * 0.55, 1, deckY * 0.45)); sx += (x1 - x0) * 0.08 }
            }
            // Deck.
            ctx.fill(under, 1, R(0, deckY, w, deckH * 0.45))
            ctx.fill(white, 1, R(0, deckY + deckH * 0.45, w, deckH * 0.55))
            ctx.fill(white, 1, R(0, deckY + deckH + h * 0.025, w, 1))
            var px: CGFloat = 0
            while px < w { ctx.fill(white, 1, R(px, deckY + deckH, 0.8, h * 0.025)); px += w * 0.012 }
            // Colour-changing deck lights.
            let ledColors = [RGB(0x4FA8FF), RGB(0xD25AD8), RGB(0x3FD6C8), RGB(0xFFB45A)]
            var lx: CGFloat = 0, li = 0
            while lx < w {
                lit.fill(ledColors[(li / 6) % ledColors.count], 0.9, R(lx, deckY + 0.5, w * 0.008, deckH * 0.35))
                lx += w * 0.0095; li += 1
            }
            // Signature bow arch over the central span.
            let bow = CGMutablePath()
            bow.addEllipse(in: R(w * 0.34, deckY + deckH - h * 0.5, w * 0.32, h * 1.0))
            ctx.saveGState(); ctx.clip(to: R(0, deckY + deckH, w, h))
            ctx.setStrokeColor(white.cg()); ctx.setLineWidth(max(2.5, h * 0.022)); ctx.addPath(bow); ctx.strokePath()
            lit.saveGState(); lit.clip(to: R(0, deckY + deckH, w, h))
            lit.setStrokeColor(RGB(0x9F8CFF).cg(0.5)); lit.setLineWidth(max(2.5, h * 0.03)); lit.addPath(bow); lit.strokePath()
            lit.restoreGState()
            ctx.restoreGState()
            for i in 1..<12 {
                let t = CGFloat(i) / 12
                let x = w * 0.34 + w * 0.32 * t
                let yTop = deckY + deckH + h * 0.5 * sqrt(max(0, 1 - pow(2 * t - 1, 2)))
                ctx.fill(white, 0.85, R(x, deckY + deckH, 0.7, yTop - deckY - deckH))
            }
            // Lamp posts.
            var lpx = w * 0.03
            while lpx < w {
                ctx.fill(RGB(0x5C6170), 1, R(lpx, deckY + deckH, 0.9, h * 0.08))
                ctx.fill(RGB(0x5C6170), 1, R(lpx - 2, deckY + deckH + h * 0.08, 4.9, 1.2))
                lit.fillEllipse(RGB(0xFFE0A8), 1, R(lpx - 2.5, deckY + deckH + h * 0.072, 6, 3.4))
                lpx += w * 0.06
            }
        }
    }

    // MARK: - Lalbagh Fort: terracotta ramparts, the South Gate, Pari Bibi's tomb, the three-domed mosque.

    static func lalbagh(h: CGFloat) -> LandmarkArt {
        let w = h * 2.0
        let brick = RGB(0xB0654A), brickShade = RGB(0x8C4E3A), sand = RGB(0xD9C7A6), sandShade = RGB(0xB9A684)
        let brass = RGB(0xB8935C), cream = RGB(0xEAE1CE), dark = RGB(0x3E2E26), warm = RGB(0xFFC98A)
        return draw(CGSize(width: w, height: h)) { ctx, lit in
            let wallH = h * 0.18
            func merlons(_ x0: CGFloat, _ x1: CGFloat, _ y: CGFloat, _ c: RGB) {
                var x = x0
                while x < x1 - w * 0.008 { ctx.fill(c, 1, R(x, y, w * 0.008, h * 0.022)); x += w * 0.015 }
            }
            func turret(_ cx: CGFloat, _ tw: CGFloat, _ top: CGFloat, _ c: RGB, _ s: RGB) {
                ctx.fill(s, 1, R(cx - tw / 2, 0, tw, top))
                ctx.fill(c, 1, R(cx - tw * 0.28, 0, tw * 0.56, top))
                var y = h * 0.1
                while y < top - h * 0.03 { ctx.fill(s.darker(0.12), 1, R(cx - tw / 2, y, tw, max(1, h * 0.007))); y += h * 0.09 }
                ctx.fill(c, 1, R(cx - tw * 0.62, top, tw * 1.24, h * 0.012))
                for px in [cx - tw * 0.5, cx + tw * 0.32] { ctx.fill(c, 1, R(px, top + h * 0.012, tw * 0.16, h * 0.045)) }
                lit.fill(warm, 0.4, R(cx - tw * 0.3, top + h * 0.012, tw * 0.6, h * 0.045))
                ctx.fill(c, 1, R(cx - tw * 0.62, top + h * 0.057, tw * 1.24, h * 0.01))
                ctx.fillPath(c.lighter(0.1), 1, onionDome(cx: cx, base: top + h * 0.067, r: tw * 0.55, height: h * 0.075))
                ctx.fill(brass, 1, R(cx - 0.5, top + h * 0.14, 1, h * 0.03))
            }
            // Rampart with blind arches and merlons.
            ctx.fill(brick, 1, R(0, 0, w, wallH))
            ctx.fill(brickShade, 1, R(0, 0, w, h * 0.025))
            var ax = w * 0.01
            while ax < w * 0.99 { ctx.fillPath(brickShade, 1, pointedArch(ax, h * 0.04, w * 0.018, wallH * 0.6)); ax += w * 0.03 }
            merlons(0, w, wallH, brick)
            lit.fill(warm, 0.14, R(0, 0, w, wallH))

            // South Gate (left).
            turret(w * 0.07, w * 0.04, h * 0.66, brick.lighter(0.05), brickShade)
            turret(w * 0.25, w * 0.04, h * 0.66, brick.lighter(0.05), brickShade)
            ctx.fill(brick.lighter(0.08), 1, R(w * 0.09, 0, w * 0.14, h * 0.56))
            ctx.fill(brickShade, 1, R(w * 0.21, 0, w * 0.02, h * 0.56))
            ctx.fill(brick.lighter(0.2), 1, R(w * 0.115, h * 0.06, w * 0.09, h * 0.4))
            let gate = pointedArch(w * 0.13, 0, w * 0.06, h * 0.34)
            ctx.fillPath(dark, 1, gate); lit.fillPath(warm, 0.55, gate)
            for gx in [w * 0.1, w * 0.2] {
                let a = pointedArch(gx, h * 0.38, w * 0.018, h * 0.1)
                ctx.fillPath(dark, 1, a); lit.fillPath(warm, 0.5, a)
            }
            merlons(w * 0.09, w * 0.23, h * 0.56, brick.lighter(0.08))

            // Pari Bibi's tomb (centre).
            let tc = w * 0.52
            ctx.fill(sandShade, 1, R(tc - w * 0.14, wallH, w * 0.28, h * 0.05))
            ctx.fill(sand, 1, R(tc - w * 0.11, wallH + h * 0.05, w * 0.22, h * 0.26))
            ctx.fill(sandShade, 1, R(tc + w * 0.08, wallH + h * 0.05, w * 0.03, h * 0.26))
            for i in -1...1 {
                let aw = i == 0 ? w * 0.05 : w * 0.032
                let ah = i == 0 ? h * 0.2 : h * 0.15
                let a = pointedArch(tc + CGFloat(i) * w * 0.065 - aw / 2, wallH + h * 0.06, aw, ah)
                ctx.fillPath(dark, 1, a); lit.fillPath(warm, 0.6, a)
            }
            ctx.fill(sand.lighter(0.15), 1, R(tc - w * 0.115, wallH + h * 0.31, w * 0.23, h * 0.014))
            for tx in [tc - w * 0.11, tc + w * 0.11] { turret(tx, w * 0.026, wallH + h * 0.36, sand, sandShade) }
            ctx.fill(sand, 1, R(tc - w * 0.045, wallH + h * 0.32, w * 0.09, h * 0.08))
            ctx.fill(sandShade, 1, R(tc + w * 0.025, wallH + h * 0.32, w * 0.02, h * 0.08))
            let dome = onionDome(cx: tc, base: wallH + h * 0.4, r: w * 0.05, height: h * 0.2)
            ctx.fillPath(brass, 1, dome)
            ctx.saveGState(); ctx.addPath(dome); ctx.clip()
            ctx.fill(brass.darker(0.2), 1, R(tc + w * 0.012, wallH + h * 0.4, w * 0.06, h * 0.25))
            ctx.restoreGState()
            lit.fillPath(RGB(0xFFD9A0), 0.25, dome)
            ctx.fill(brass, 1, R(tc - 0.6, wallH + h * 0.59, 1.2, h * 0.05))
            ctx.fillEllipse(brass, 1, R(tc - h * 0.008, wallH + h * 0.61, h * 0.016, h * 0.016))

            // Three-domed mosque (right).
            let mx0 = w * 0.74, mw = w * 0.2
            ctx.fill(cream, 1, R(mx0, wallH, mw, h * 0.17))
            for i in 0..<3 {
                let a = pointedArch(mx0 + mw * (0.12 + CGFloat(i) * 0.3), wallH + h * 0.015, mw * 0.16, h * 0.12)
                ctx.fillPath(dark, 1, a); lit.fillPath(warm, 0.55, a)
            }
            for (fx, r) in [(0.22, 0.09), (0.5, 0.12), (0.78, 0.09)] as [(CGFloat, CGFloat)] {
                let cx = mx0 + mw * fx
                ctx.fill(cream, 1, R(cx - mw * r * 0.9, wallH + h * 0.17, mw * r * 1.8, h * 0.02))
                ctx.fillPath(cream.lighter(0.15), 1, onionDome(cx: cx, base: wallH + h * 0.19, r: mw * r, height: mw * r * 1.6))
                ctx.fill(brass, 1, R(cx - 0.5, wallH + h * 0.19 + mw * r * 1.55, 1, h * 0.03))
            }
            for tx in [mx0, mx0 + mw] { turret(tx, w * 0.014, wallH + h * 0.24, cream, cream.darker(0.12)) }
        }
    }

    // MARK: - Padma Bridge: a double-deck steel truss marching across a wide river.

    static func padma(h: CGFloat, w: CGFloat) -> LandmarkArt {
        let steel = RGB(0xC9CDD4), steelShade = RGB(0x8E949E), concrete = RGB(0xB5AEA4)
        return draw(CGSize(width: w, height: h)) { ctx, lit in
            let bottom = h * 0.36, top = h * 0.62
            let span = w / 15
            // Piers: twin raked legs on a pile cap.
            var px = span * 0.5
            while px < w {
                ctx.fill(concrete.darker(0.15), 1, R(px - span * 0.11, 0, span * 0.22, h * 0.05))
                ctx.fillPath(concrete, 1, CGPath.poly([P(px - span * 0.08, h * 0.05), P(px - span * 0.03, h * 0.05), P(px - span * 0.05, bottom), P(px - span * 0.12, bottom)]))
                ctx.fillPath(concrete.darker(0.08), 1, CGPath.poly([P(px + span * 0.03, h * 0.05), P(px + span * 0.08, h * 0.05), P(px + span * 0.12, bottom), P(px + span * 0.05, bottom)]))
                ctx.fill(concrete, 1, R(px - span * 0.14, bottom - h * 0.025, span * 0.28, h * 0.025))
                px += span
            }
            // Warren truss.
            ctx.fill(steelShade, 1, R(0, bottom, w, h * 0.035))
            ctx.fill(steel, 1, R(0, top - h * 0.03, w, h * 0.03))
            ctx.setStrokeColor(steel.cg()); ctx.setLineWidth(max(1.2, h * 0.018)); ctx.setLineCap(.butt)
            let panel = span / 4
            var x: CGFloat = 0, up = true
            while x < w {
                ctx.move(to: P(x, up ? bottom + h * 0.03 : top - h * 0.03))
                ctx.addLine(to: P(x + panel, up ? top - h * 0.03 : bottom + h * 0.03))
                x += panel; up.toggle()
            }
            ctx.strokePath()
            // Rail deck glimpsed inside, road deck on top with lamps.
            ctx.fill(RGB(0x5A5F68), 0.8, R(0, bottom + h * 0.08, w, h * 0.02))
            ctx.fill(steel.lighter(0.2), 1, R(0, top, w, h * 0.035))
            var lx = panel
            while lx < w {
                ctx.fill(steelShade, 1, R(lx, top + h * 0.035, 0.9, h * 0.12))
                ctx.fill(steelShade, 1, R(lx - 2, top + h * 0.15, 4.5, 1.2))
                lit.fillEllipse(RGB(0xFFE0A8), 1, R(lx - 2.6, top + h * 0.135, 6.2, 3.4))
                lx += panel * 2
            }
            lit.fill(RGB(0xA9C4FF), 0.2, R(0, bottom, w, top - bottom))
            lit.fill(RGB(0xFFD9A0), 0.35, R(0, top, w, h * 0.035))
        }
    }

    // MARK: - Pari Bibi's tomb (Lalbagh), front elevation for the garden view.

    struct Elevation { var base: CGImage; var lights: CGImage; var size: CGSize }

    static func pariBibi(height h: CGFloat) -> Elevation {
        let w = h * 1.3
        let size = CGSize(width: w, height: h)
        let salmon = RGB(0xE6AC91), salmonShade = RGB(0xC98D74), trim = RGB(0xF3CDB8), dark = RGB(0x3A2A26)
        let slate = RGB(0x3E4B5E), stone = RGB(0xD9CBB6), warm = RGB(0xFFC98A)
        let ctx = Painter.context(size, scale: 1), lit = Painter.context(size, scale: 1)
        let outline = { (path: CGPath) in
            ctx.setStrokeColor(RGB(0x7A4E40).cg(0.55)); ctx.setLineWidth(h * 0.004); ctx.addPath(path); ctx.strokePath()
        }
        func box(_ r: CGRect, _ c: RGB) { ctx.fill(c, 1, r); outline(CGPath(rect: r, transform: nil)) }
        func turret(_ cx: CGFloat) {
            let tw = w * 0.085
            box(R(cx - tw / 2, 0, tw, h * 0.66), salmonShade)
            box(R(cx - tw * 0.28, 0, tw * 0.56, h * 0.66), salmon)
            for y in stride(from: h * 0.12, to: h * 0.62, by: h * 0.12) { ctx.fill(trim, 1, R(cx - tw / 2, y, tw, h * 0.008)) }
            box(R(cx - tw * 0.62, h * 0.66, tw * 1.24, h * 0.02), trim)
            for px in [cx - tw * 0.5, cx + tw * 0.34] { box(R(px, h * 0.68, tw * 0.16, h * 0.07), salmon) }
            lit.fill(warm, 0.45, R(cx - tw * 0.3, h * 0.68, tw * 0.6, h * 0.07))
            box(R(cx - tw * 0.62, h * 0.75, tw * 1.24, h * 0.016), trim)
            let d = onionDome(cx: cx, base: h * 0.766, r: tw * 0.6, height: h * 0.11)
            ctx.fillPath(salmon.lighter(0.08), 1, d); outline(d)
            ctx.fill(RGB(0xC6A35A), 1, R(cx - h * 0.003, h * 0.87, h * 0.006, h * 0.04))
        }
        // Body.
        box(R(w * 0.1, 0, w * 0.8, h * 0.58), salmon)
        box(R(w * 0.33, 0, w * 0.34, h * 0.62), salmon.lighter(0.08))   // central pishtaq
        let main = pointedArch(w * 0.41, h * 0.03, w * 0.18, h * 0.45)
        ctx.fillPath(trim, 1, pointedArch(w * 0.395, h * 0.02, w * 0.21, h * 0.48))
        ctx.fillPath(dark, 1, main); outline(main)
        lit.fillPath(warm, 0.65, main)
        for x in [w * 0.17, w * 0.71] {
            ctx.fillPath(trim, 1, pointedArch(x - w * 0.01, h * 0.02, w * 0.14, h * 0.33))
            let a = pointedArch(x, h * 0.03, w * 0.12, h * 0.3)
            ctx.fillPath(dark, 1, a); outline(a)
            ctx.saveGState(); ctx.addPath(a); ctx.clip()   // jaali lattice
            var gx = x
            while gx < x + w * 0.12 { ctx.fill(RGB(0x8A6A5A), 0.8, R(gx, 0, h * 0.004, h * 0.4)); gx += w * 0.015 }
            ctx.restoreGState()
            lit.fillPath(warm, 0.5, a)
            let up = pointedArch(x + w * 0.035, h * 0.4, w * 0.05, h * 0.12)
            ctx.fillPath(dark, 1, up); lit.fillPath(warm, 0.5, up)
        }
        box(R(w * 0.09, h * 0.58, w * 0.82, h * 0.025), trim)
        var mx = w * 0.1
        while mx < w * 0.9 { ctx.fill(salmon, 1, R(mx, h * 0.605, w * 0.012, h * 0.025)); mx += w * 0.024 }
        // Drum and slate dome.
        box(R(w * 0.42, h * 0.6, w * 0.16, h * 0.09), salmon)
        box(R(w * 0.41, h * 0.69, w * 0.18, h * 0.015), trim)
        let dome = onionDome(cx: w * 0.5, base: h * 0.705, r: w * 0.095, height: h * 0.24)
        ctx.fillPath(slate, 1, dome)
        ctx.saveGState(); ctx.addPath(dome); ctx.clip()
        ctx.fill(slate.lighter(0.18), 1, R(w * 0.43, h * 0.7, w * 0.04, h * 0.3))
        ctx.fill(slate.darker(0.2), 1, R(w * 0.52, h * 0.7, w * 0.08, h * 0.3))
        ctx.restoreGState(); outline(dome)
        ctx.fill(RGB(0xC6A35A), 1, R(w * 0.5 - h * 0.004, h * 0.935, h * 0.008, h * 0.06))
        lit.fillPath(RGB(0xBFD0FF), 0.2, dome)
        for x in [w * 0.1, w * 0.9] { turret(x) }
        for x in [w * 0.36, w * 0.64] { turret(x) }   // small corner kiosks on the pishtaq
        lit.fill(RGB(0xFFD9A0), 0.16, R(w * 0.1, 0, w * 0.8, h * 0.58))
        // Steps.
        ctx.fill(stone, 1, R(w * 0.36, -h * 0.01, w * 0.28, h * 0.03))
        return Elevation(base: ctx.makeImage()!, lights: lit.makeImage()!, size: size)
    }

    // MARK: - Your own image.

    static func custom(file: String, height h: CGFloat, maxWidth: CGFloat) -> LandmarkArt? {
        let url = Settings.customDir.appendingPathComponent(file)
        guard let ns = NSImage(contentsOf: url), let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let aspect = CGFloat(cg.width) / CGFloat(cg.height)
        var size = CGSize(width: h * aspect, height: h)
        if size.width > maxWidth { size = CGSize(width: maxWidth, height: maxWidth / aspect) }
        let lights = Painter.texture(size) { ctx in
            // Warm glow in the landmark's shape: paint the gradient, then keep it only where the image is opaque.
            ctx.saveGState()
            Painter.linearGradient(ctx, [(0, RGB(0xFFD9A0).cg(0.32)), (1, RGB(0xFFD9A0).cg(0))], from: P(0, 0), to: P(0, size.height))
            ctx.setBlendMode(.destinationIn)
            ctx.draw(cg, in: R(0, 0, size.width, size.height))
            ctx.restoreGState()
        }
        return LandmarkArt(base: Painter.texture(cg), lights: lights, size: size)
    }

    /// Lifts the subject out of a photo with Apple Vision. Returns nil if no foreground was found.
    static func cutOut(_ cg: CGImage) -> CGImage? {
        let req = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cg)
        guard (try? handler.perform([req])) != nil, let obs = req.results?.first,
              let buf = try? obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler, croppedToInstancesExtent: true)
        else { return nil }
        let ci = CIImage(cvPixelBuffer: buf)
        return CIContext().createCGImage(ci, from: ci.extent)  // only when importing a photo; freed afterwards
    }
}
