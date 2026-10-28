import AppKit
import SpriteKit

// MARK: - A tiny perspective camera (metres in, points out)

/// Camera at (0, height, 0) looking down +Z, pitched down by `pitch`. Screen y grows upward.
struct Cam {
    var height: CGFloat, pitch: CGFloat, f: CGFloat, cx: CGFloat, cy: CGFloat

    func depth(_ y: CGFloat, _ z: CGFloat) -> CGFloat { max(0.5, z * cos(pitch) - (y - height) * sin(pitch)) }
    func p(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGPoint {
        let yp = (y - height) * cos(pitch) + z * sin(pitch)
        let d = depth(y, z)
        return CGPoint(x: cx + f * x / d, y: cy + f * yp / d)
    }
    /// Points per metre at that spot.
    func scale(_ y: CGFloat, _ z: CGFloat) -> CGFloat { f / depth(y, z) }
    var horizon: CGFloat { cy + f * tan(pitch) }
    /// The ground distance that lands on screen height `y`.
    func groundZ(atScreenY y: CGFloat) -> CGFloat {
        let k = (y - cy) / f, s = sin(pitch), c = cos(pitch)
        return height * (c + k * s) / (s - k * c)
    }
    /// Half the visible ground width (metres) at distance z, with a margin.
    func halfWidth(_ z: CGFloat, W: CGFloat) -> CGFloat { (max(cx, W - cx) + 60) / scale(0, z) }

    static func make(W: CGFloat, H: CGFloat, height: CGFloat, pitchDeg: CGFloat, horizon: CGFloat, cx: CGFloat, cy: CGFloat) -> Cam {
        let pitch = pitchDeg * .pi / 180
        return Cam(height: height, pitch: pitch, f: (horizon - cy) * H / tan(pitch), cx: cx * W, cy: cy * H)
    }
}

/// Where things move in a view: a parametric path in world metres.
struct Lane {
    enum Kind { case car, boat, walker, rowboat }
    var kind: Kind
    var length: CGFloat
    var point: (CGFloat) -> (x: CGFloat, y: CGFloat, z: CGFloat)
    var toward: Bool = false            // travelling toward the camera (headlights show)
    var fadeIn: CGFloat = 0, fadeOut: CGFloat = 0   // metres of alpha fade at the ends
    var count: Int                      // how many movers it holds at full density
    var speed: ClosedRange<CGFloat>     // m/s
}

extension Lane {
    /// A car route through world points (metres), walked at constant speed by arc length.
    static func path(_ pts: [(CGFloat, CGFloat, CGFloat)], toward: Bool = false, fadeIn: CGFloat = 0, fadeOut: CGFloat = 0,
                     count: Int, speed: ClosedRange<CGFloat>) -> Lane {
        var cum: [CGFloat] = [0]
        for i in 1..<pts.count {
            let a = pts[i - 1], b = pts[i]
            cum.append(cum[i - 1] + sqrt((b.0 - a.0) * (b.0 - a.0) + (b.1 - a.1) * (b.1 - a.1) + (b.2 - a.2) * (b.2 - a.2)))
        }
        let total = cum[cum.count - 1]
        return Lane(kind: .car, length: total, point: { s in
            let s = min(max(0, s), total)
            var i = 1
            while i < cum.count - 1 && cum[i] < s { i += 1 }
            let seg = max(1e-6, cum[i] - cum[i - 1]), t = (s - cum[i - 1]) / seg
            let a = pts[i - 1], b = pts[i]
            return (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
        }, toward: toward, fadeIn: fadeIn, fadeOut: fadeOut, count: count, speed: speed)
    }
}

struct ViewArt {
    var base: CGImage
    var lights: CGImage
    var cam: Cam
    var hasWater: Bool
    var waterTint: RGB?                 // e.g. Hatirjheel's green water
    var lanes: [Lane] = []
    var fountains: [(CGPoint, CGFloat)] = []   // screen point, points-per-metre there
    var rippleRect: CGRect?
    var planes = false
    var skyline: CGFloat = 0.05         // far skyline height (fraction of H)
    var groundTop: CGFloat = 0          // screen y where the drawn ground ends; sky shows above it
    var hazeDepth: CGFloat = 0.3        // how far below groundTop the atmospheric haze reaches (fraction of H)
    var dino: DinoExtras?               // Dinosaur World's moving parts
    var front: (base: CGImage, lights: CGImage)?   // buildings that traffic can pass behind, drawn over it
}

// MARK: - Painter

/// Draws cartoon boxes, trees and ground in perspective, far to near, into a colour pass and a night-lights pass.
final class PerspectivePainter {
    let cam: Cam, W: CGFloat, H: CGFloat
    let ctx: CGContext, lit: CGContext
    var rng: SeededRNG
    var haze = RGB(0xC6CDD3)
    var hazeRange: ClosedRange<CGFloat> = 400...2600
    private var items: [(key: CGFloat, draw: () -> Void)] = []

    static let walls = [RGB(0xF2EEE6), RGB(0xEADFCB), RGB(0xDCC8AC), RGB(0xC8D5DE), RGB(0xE6C5B8), RGB(0xE3D9A4),
                        RGB(0xC08D72), RGB(0xB5CDB0), RGB(0xF4F1EA), RGB(0xD9D3CB)]
    static let greens = (dark: RGB(0x3B6A3E), mid: RGB(0x5C8E4B), light: RGB(0x89B565))

    init(cam: Cam, W: CGFloat, H: CGFloat, seed: UInt64) {
        self.cam = cam; self.W = W; self.H = H
        ctx = Painter.context(CGSize(width: W, height: H))
        lit = Painter.context(CGSize(width: W, height: H))
        rng = SeededRNG(seed: seed)
        for c in [ctx, lit] { c.setLineJoin(.round); c.setLineCap(.round) }
    }

    func hz(_ z: CGFloat) -> Double { Double(smoothstep(Double(hazeRange.lowerBound), Double(hazeRange.upperBound), Double(z))) * 0.8 }
    func tone(_ c: RGB, _ z: CGFloat) -> RGB { .mix(c, haze, hz(z)) }
    func add(_ key: CGFloat, _ f: @escaping () -> Void) { items.append((key, f)) }
    func flush() {
        items.sort { $0.key > $1.key }
        items.forEach { $0.draw() }
        items.removeAll()
    }
    func finish() -> (CGImage, CGImage) { (ctx.makeImage()!, lit.makeImage()!) }

    /// Screen outline of a box (rooftop clutter included), for hiding traffic that passes behind it.
    func silhouette(_ b: Box) -> CGPath {
        var pts: [CGPoint] = []
        for x in [b.x0, b.x1] { for y in [b.y0, b.h] { for z in [b.z0, b.z1] { pts.append(cam.p(x, y, z)) } } }
        pts.sort { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        func cross(_ o: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat { (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x) }
        var lower: [CGPoint] = [], upper: [CGPoint] = []
        for p in pts { while lower.count >= 2 && cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 { lower.removeLast() }; lower.append(p) }
        for p in pts.reversed() { while upper.count >= 2 && cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 { upper.removeLast() }; upper.append(p) }
        return CGPath.poly(Array(lower.dropLast() + upper.dropLast()))
    }

    /// The parts of the finished painting inside `outlines`, to lay over the traffic.
    static func cutout(_ img: CGImage, _ outlines: [CGPath], W: CGFloat, H: CGFloat) -> CGImage {
        let c = Painter.context(CGSize(width: W, height: H))
        for o in outlines { c.addPath(o) }
        c.clip()
        c.draw(img, in: R(0, 0, W, H))
        return c.makeImage()!
    }

    func poly(_ pts: [CGPoint], _ c: RGB, _ a: Double = 1, in g: CGContext? = nil) {
        guard pts.count > 2 else { return }
        let path = CGPath.poly(pts)
        (g ?? ctx).fillPath(c, a, path)
        if g == nil && a >= 0.9 { occlude(path) }
    }

    /// Anything solid hides the night lights behind it (they live in a separate pass).
    func occlude(_ path: CGPath) {
        lit.saveGState(); lit.setBlendMode(.clear); lit.addPath(path); lit.fillPath(); lit.restoreGState()
    }
    func outline(_ pts: [CGPoint], _ c: RGB, _ a: Double, width: CGFloat) {
        guard pts.count > 1 else { return }
        ctx.setStrokeColor(c.cg(a)); ctx.setLineWidth(width)
        ctx.addPath(CGPath.poly(pts)); ctx.strokePath()
    }

    /// Ground fill from the bottom of the screen up to `top` (the farthest drawn ground), fading into haze.
    /// Above `top` stays clear so the real sky shows behind the distant city.
    @discardableResult
    func groundGradient(_ near: RGB, farZ: CGFloat, hazeMix: Double = 1) -> CGFloat {
        let top = cam.p(0, 0, farZ).y
        let far = RGB.mix(near, haze, hazeMix)
        Painter.linearGradient(ctx, [(0, near.cg()), (0.7, RGB.mix(near, far, 0.5).cg()), (1, far.cg())],
                               from: P(0, 0), to: P(0, top))
        ctx.saveGState(); ctx.setBlendMode(.clear); ctx.fill(R(0, top, W, H)); ctx.restoreGState()
        return top
    }

    /// A ground band between two edges that vary with distance. `clear` punches a hole (for water).
    func strip(_ z0: CGFloat, _ z1: CGFloat, left: (CGFloat) -> CGFloat, right: (CGFloat) -> CGFloat,
               _ c: RGB, clear: Bool = false, steps: Int = 60, y: CGFloat = 0) {
        var l: [CGPoint] = [], r: [CGPoint] = []
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let z = z0 * pow(z1 / z0, t)  // denser samples up close
            l.append(cam.p(left(z), y, z)); r.append(cam.p(right(z), y, z))
        }
        let pts = l + r.reversed()
        if clear {
            ctx.saveGState(); ctx.setBlendMode(.clear); ctx.addPath(CGPath.poly(pts)); ctx.fillPath(); ctx.restoreGState()
            occlude(CGPath.poly(pts))
        } else {
            poly(pts, y > 0 ? c : tone(c, (z0 + z1) / 2 * 0.3))
        }
    }

    func line3D(_ a: (CGFloat, CGFloat, CGFloat), _ b: (CGFloat, CGFloat, CGFloat), _ c: RGB, widthM: CGFloat, minW: CGFloat = 0.6, in g: CGContext? = nil, alpha: Double = 1) {
        let w = max(minW, widthM * cam.scale(a.1, a.2))
        (g ?? ctx).strokeLine(c, alpha, width: w, [cam.p(a.0, a.1, a.2), cam.p(b.0, b.1, b.2)])
    }

    // MARK: Buildings

    struct Box {
        var x0: CGFloat, x1: CGFloat, z0: CGFloat, z1: CGFloat, h: CGFloat
        var wall: RGB, roof: RGB
        var y0: CGFloat = 0
        var glass = false
        var details = true
        var litChance = 0.32
    }

    func randomBox(x0: CGFloat, x1: CGFloat, z0: CGFloat, z1: CGFloat, h: CGFloat, glass: Bool = false) -> Box {
        let wall = glass ? rng.pick([RGB(0x9DB4CA), RGB(0xB8C8D6), RGB(0xE8ECEF), RGB(0x8FA9BF)]) : rng.pick(Self.walls)
        let roof = glass ? wall.lighter(0.2) : (rng.chance(0.6) ? RGB(0xCBC7BE) : wall.lighter(0.12))
        return Box(x0: x0, x1: x1, z0: z0, z1: z1, h: h, wall: wall, roof: roof, glass: glass)
    }

    func addBox(_ b: Box) { add(b.z0) { [unowned self] in self.drawBox(b) } }

    func drawBox(_ b: Box) {
        let p = cam.p
        let fl = p(b.x0, b.y0, b.z0), fr = p(b.x1, b.y0, b.z0), flt = p(b.x0, b.h, b.z0), frt = p(b.x1, b.h, b.z0)
        let blt = p(b.x0, b.h, b.z1), brt = p(b.x1, b.h, b.z1), bl = p(b.x0, b.y0, b.z1), br = p(b.x1, b.y0, b.z1)
        let s = cam.scale(0, b.z0)
        let wall = tone(b.wall, b.z0), front = wall.scaled(0.94), side = wall.scaled(0.76), roof = tone(b.roof, b.z0).lighter(0.05)
        let edge = wall.scaled(0.45)
        let ow = min(1.1, max(0.35, s * 0.1))
        var sideFace: [CGPoint]? = nil
        if b.x1 < 0 { sideFace = [fr, br, brt, frt] } else if b.x0 > 0 { sideFace = [fl, bl, blt, flt] }
        if let sf = sideFace { poly(sf, side); outline(sf, edge, 0.35, width: ow) }
        let ff = [fl, fr, frt, flt]
        poly(ff, front)
        let rf = [flt, frt, brt, blt]
        poly(rf, roof)

        // Windows / floors.
        let floorH: CGFloat = b.glass ? 3.6 : 3.2
        if s > 1.1 {
            var y: CGFloat = b.y0 + 1.8
            while y < b.h - 1.2 {
                if b.glass {
                    poly([p(b.x0, y, b.z0), p(b.x1, y, b.z0), p(b.x1, y + 1.2, b.z0), p(b.x0, y + 1.2, b.z0)], front.lighter(0.25), 0.7)
                }
                var x = b.x0 + 1.2
                while x < b.x1 - 1.6 {
                    let a = p(x, y, b.z0), c = p(x + 1.3, y + 1.5, b.z0)
                    let r = CGRect(x: a.x, y: a.y, width: c.x - a.x, height: c.y - a.y)
                    if !b.glass { ctx.fill(RGB.mix(front, RGB(0x34404C), 0.55), 1, r) }
                    if rng.chance(b.litChance) { lit.fill(rng.pick(ArtCity.windowColors), rng.d(0.6, 1), r) }
                    x += 3.0
                }
                if let sf = sideFace, s > 1.6 {
                    let sx = sf[0] == fr ? b.x1 : b.x0
                    ctx.strokeLine(side.scaled(0.85), 0.8, width: max(0.4, s * 0.12), [p(sx, y - 0.4, b.z0), p(sx, y - 0.4, b.z1)])
                }
                y += floorH
            }
        } else {
            // Too small for window detail: scatter a few lit dots for the night.
            let n = Int((b.x1 - b.x0) * b.h / 24 * CGFloat(b.litChance))
            let d = max(0.7, s * 1.3)
            for _ in 0..<n {
                let q = p(rng.cg(b.x0 + 1, b.x1 - 1), rng.cg(1.5, max(2, b.h - 1)), b.z0)
                lit.fill(rng.pick(ArtCity.windowColors), rng.d(0.5, 1), R(q.x, q.y, d, d * 0.9))
            }
        }
        outline(ff, edge, 0.35, width: ow)
        outline(rf, edge, 0.3, width: ow)

        // Rooftop clutter: stair room, water tanks, tin sheds.
        guard b.details, s > 0.45, !b.glass else { return }
        let rw = b.x1 - b.x0, rd = b.z1 - b.z0
        if rng.chance(0.5) {
            let x = b.x0 + rw * rng.cg(0.1, 0.55), z = b.z0 + rd * rng.cg(0.3, 0.6)
            drawBox(Box(x0: x, x1: x + min(4, rw * 0.35), z0: z, z1: z + 3.5, h: b.h + 2.6, wall: b.wall, roof: b.roof, y0: b.h, details: false, litChance: 0))
        }
        if rng.chance(0.35) {
            let x = b.x0 + rw * rng.cg(0.05, 0.4), z = b.z0 + rd * rng.cg(0.1, 0.4)
            let c = rng.pick([RGB(0x5B7FB0), RGB(0x9A5B44), RGB(0x7C8A96)])
            poly([p(x, b.h + 0.05, z), p(x + rw * 0.45, b.h + 0.05, z), p(x + rw * 0.45, b.h + 0.05, z + rd * 0.45), p(x, b.h + 0.05, z + rd * 0.45)], tone(c, b.z0))
        }
        for _ in 0..<(rng.chance(0.65) ? rng.pick([1, 1, 2]) : 0) {
            let x = b.x0 + rw * rng.cg(0.15, 0.8), z = b.z0 + rd * rng.cg(0.2, 0.7)
            let c = rng.pick([RGB(0x2E3238), RGB(0x2E3238), RGB(0x3E6FA8), RGB(0xE8E8E8)])
            drawBox(Box(x0: x, x1: x + 1.7, z0: z, z1: z + 1.7, h: b.h + 1.6, wall: c, roof: c.lighter(0.25), y0: b.h, details: false, litChance: 0))
        }
    }

    // MARK: Trees

    func addTree(_ x: CGFloat, _ z: CGFloat, r: CGFloat, flowering: RGB? = nil) {
        add(z) { [unowned self] in self.drawTree(x, z, r: r, flowering: flowering) }
    }

    func drawTree(_ x: CGFloat, _ z: CGFloat, r: CGFloat, flowering: RGB? = nil) {
        let s = cam.scale(r, z)
        let rad = r * s
        guard rad > 0.5 else { return }
        let c = cam.p(x, r * 1.25, z)
        let g = Self.greens
        let dark = tone(g.dark, z), mid = tone(flowering ?? g.mid, z), light = tone(flowering?.lighter(0.25) ?? g.light, z)
        if rad > 4 {
            let base = cam.p(x, 0, z)
            ctx.strokeLine(tone(RGB(0x5A4636), z), 1, width: max(1, rad * 0.16), [base, P(c.x, c.y - rad * 0.3)])
        }
        let lobes: [(CGFloat, CGFloat, CGFloat)] = [(-0.42, -0.08, 0.68), (0.42, -0.08, 0.68), (0, 0.28, 0.74)]
        let shape = CGMutablePath()
        for (dx, dy, k) in lobes { shape.addEllipse(in: R(c.x + dx * rad - k * rad, c.y + dy * rad - k * rad, 2 * k * rad, 2 * k * rad)) }
        ctx.fillPath(dark, 1, shape)
        occlude(shape)
        ctx.saveGState(); ctx.addPath(shape); ctx.clip()
        for (dx, dy, k) in lobes {
            ctx.fillEllipse(mid, 1, R(c.x + (dx - 0.12) * rad - k * 0.75 * rad, c.y + (dy + 0.14) * rad - k * 0.75 * rad, 1.5 * k * rad, 1.5 * k * rad))
            ctx.fillEllipse(light, 0.9, R(c.x + (dx - 0.22) * rad - k * 0.38 * rad, c.y + (dy + 0.3) * rad - k * 0.38 * rad, 0.76 * k * rad, 0.76 * k * rad))
        }
        ctx.restoreGState()
        ctx.setStrokeColor(dark.scaled(0.6).cg(0.5)); ctx.setLineWidth(min(1, max(0.3, rad * 0.04)))
        ctx.addPath(shape); ctx.strokePath()
    }

    /// A round clipped shrub sitting on the ground (topiary).
    func addBush(_ x: CGFloat, _ z: CGFloat, r: CGFloat, tall: Bool = false) {
        add(z) { [unowned self] in
            let s = self.cam.scale(r, z), rad = r * s
            let c = self.cam.p(x, tall ? r * 1.6 : r, z)
            let g = Self.greens
            self.ctx.fillEllipse(self.tone(RGB(0x2C3A26), z), 0.25, R(c.x - rad * 1.1, self.cam.p(x, 0, z).y - rad * 0.25, rad * 2.2, rad * 0.5))
            let rect = tall ? R(c.x - rad * 0.8, c.y - rad * 1.6, rad * 1.6, rad * 3.2) : R(c.x - rad, c.y - rad, 2 * rad, 2 * rad)
            self.ctx.fillEllipse(self.tone(g.dark, z), 1, rect)
            self.occlude(CGPath(ellipseIn: rect, transform: nil))
            self.ctx.fillEllipse(self.tone(g.mid, z), 1, rect.insetBy(dx: rad * 0.12, dy: rad * 0.12).offsetBy(dx: -rad * 0.1, dy: rad * 0.12))
            self.ctx.fillEllipse(self.tone(g.light, z), 0.9, R(rect.minX + rad * 0.35, rect.maxY - rad * 0.85, rad * 0.6, rad * 0.5))
        }
    }

    /// White arch bridge: a deck across X at depth z, with bow arches drawn as thick 3D curves.
    func addArchBridge(z: CGFloat, x0: CGFloat, x1: CGFloat, deckY: CGFloat, arches: [(CGFloat, CGFloat, CGFloat)], width: CGFloat = 14) {
        add(z + width) { [unowned self] in
            let p = self.cam.p
            let white = self.tone(RGB(0xEFEFF2), z), shade = self.tone(RGB(0xB9BEC6), z), rail = self.tone(RGB(0xC2483E), z)
            // Piers.
            for t in stride(from: 0.12, through: 0.88, by: 0.19) {
                let x = x0 + (x1 - x0) * CGFloat(t)
                self.poly([p(x - 1.2, 0, z + 1), p(x + 1.2, 0, z + 1), p(x + 1.2, deckY, z + 1), p(x - 1.2, deckY, z + 1)], shade)
            }
            // Deck: top surface, then the fascia facing us, then a red railing line.
            self.poly([p(x0, deckY + 1.2, z), p(x1, deckY + 1.2, z), p(x1, deckY + 1.2, z + width), p(x0, deckY + 1.2, z + width)], self.tone(RGB(0x8E9097), z))
            self.poly([p(x0, deckY, z), p(x1, deckY, z), p(x1, deckY + 1.2, z), p(x0, deckY + 1.2, z)], white)
            self.line3D((x0, deckY + 2.2, z), (x1, deckY + 2.2, z), rail, widthM: 0.25)
            var x = x0
            while x < x1 { self.line3D((x, deckY + 1.2, z), (x, deckY + 2.2, z), rail, widthM: 0.12); x += 3 }
            // Arches on both edges of the deck (far one first).
            for dz in [width, 0] as [CGFloat] {
                for (a, b, peak) in arches {
                    var pts: [CGPoint] = []
                    for i in 0...40 {
                        let t = CGFloat(i) / 40
                        pts.append(p(a + (b - a) * t, deckY + 1.2 + peak * sin(.pi * t), z + dz))
                    }
                    let w = max(1.5, 1.4 * self.cam.scale(deckY, z + dz))
                    self.ctx.strokeLine(dz > 0 ? shade : white, 1, width: w, pts)
                    self.lit.strokeLine(RGB(0x8C7CFF), 0.5, width: w * 1.2, pts)
                    var t: CGFloat = 0.1
                    while t < 0.95 {  // hangers
                        let hx = a + (b - a) * t
                        self.line3D((hx, deckY + 1.2, z + dz), (hx, deckY + 1.2 + peak * sin(.pi * t), z + dz), shade, widthM: 0.12, minW: 0.4)
                        t += 0.09
                    }
                }
            }
            // Deck LED strip for the night.
            var lx = x0
            let leds = [RGB(0x4FA8FF), RGB(0xD25AD8), RGB(0x3FD6C8), RGB(0xFFB45A)]
            var i = 0
            while lx < x1 {
                let q = p(lx, deckY + 0.5, z)
                let d = max(1.2, self.cam.scale(deckY, z) * 0.6)
                self.lit.fillEllipse(leds[(i / 5) % 4], 0.9, R(q.x - d / 2, q.y - d / 2, d, d))
                lx += 2.2; i += 1
            }
        }
    }

    /// Electricity pylon standing in the water: tapered lattice with cross-arms.
    func addPylon(x: CGFloat, z: CGFloat, h: CGFloat) {
        add(z) { [unowned self] in
            let steel = self.tone(RGB(0x5A6068), z)
            let base: CGFloat = 5, top: CGFloat = 1.2
            func leg(_ sx: CGFloat, _ sz: CGFloat, _ y: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
                let k = base + (top - base) * (y / h)
                return (x + sx * k, y, z + sz * k)
            }
            let corners: [(CGFloat, CGFloat)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
            for (sx, sz) in corners { self.line3D(leg(sx, sz, 0), leg(sx, sz, h), steel, widthM: 0.35, minW: 0.7) }
            var y: CGFloat = 0
            let step = h / 9
            while y < h - 0.1 {
                for (sx, _) in [(-1, -1), (1, -1)] as [(CGFloat, CGFloat)] {
                    self.line3D(leg(sx, -1, y), leg(-sx, -1, y + step), steel, widthM: 0.15, minW: 0.4)
                }
                self.line3D(leg(-1, -1, y), leg(1, -1, y), steel, widthM: 0.15, minW: 0.4)
                y += step
            }
            for (ay, aw) in [(h * 0.78, 11.0), (h * 0.9, 8.0)] as [(CGFloat, CGFloat)] {
                self.line3D((x - aw, ay, z), (x + aw, ay, z), steel, widthM: 0.5, minW: 0.8)
                self.line3D((x - aw, ay, z), (x, ay + 3, z), steel, widthM: 0.2, minW: 0.4)
                self.line3D((x + aw, ay, z), (x, ay + 3, z), steel, widthM: 0.2, minW: 0.4)
            }
            let tip = self.cam.p(x, h + 1, z)
            self.lit.fillEllipse(RGB(0xFF3B30), 0.9, R(tip.x - 1.5, tip.y - 1.5, 3, 3))
        }
    }

    /// Street lamps along a path on the ground (night-lights pass only).
    func lamps(along f: (CGFloat) -> CGFloat, z0: CGFloat, z1: CGFloat, every: CGFloat, height: CGFloat = 7) {
        var z = z0
        while z < z1 {
            let q = cam.p(f(z), height, z)
            let s = cam.scale(height, z)
            let d = max(1.1, s * 0.7)
            lit.fillEllipse(RGB(0xFFD9A0), 0.18, R(q.x - d * 3, q.y - d * 3, d * 6, d * 6))
            lit.fillEllipse(RGB(0xFFE2B0), 1, R(q.x - d / 2, q.y - d / 2, d, d))
            z += every
        }
    }
}

// MARK: - The views

enum ArtViews {
    // MARK: Hatirjheel from above: a canal between two cartoon cities, arch bridge and pylons.

    static func hatirjheel(W: CGFloat, H: CGFloat, seed: UInt64) -> ViewArt {
        let cam = Cam.make(W: W, H: H, height: 140, pitchDeg: 22, horizon: 0.8, cx: 0.47, cy: 0.45)
        let pp = PerspectivePainter(cam: cam, W: W, H: H, seed: seed)
        pp.hazeRange = 500...2600
        let zNear = cam.groundZ(atScreenY: -H * 0.03), zFar: CGFloat = 2600
        func centre(_ z: CGFloat) -> CGFloat { z > 900 ? -pow(z - 900, 1.15) * 0.22 : 0 }
        func half(_ z: CGFloat) -> CGFloat {
            55 + 115 * CGFloat(smoothstep(850, 1050, Double(z)) * (1 - smoothstep(1450, 1750, Double(z))))
        }
        let L = { (z: CGFloat) in centre(z) - half(z) }, Rt = { (z: CGFloat) in centre(z) + half(z) }

        let top = pp.groundGradient(RGB(0xC2B79F), farZ: zFar)
        pp.strip(zNear, zFar, left: L, right: Rt, .black, clear: true)
        for side in [-1.0, 1.0] as [CGFloat] {
            let edge = { (z: CGFloat, d: CGFloat) -> CGFloat in side < 0 ? L(z) - d : Rt(z) + d }
            pp.strip(zNear, zFar, left: { edge($0, side < 0 ? 10 : 0) }, right: { edge($0, side < 0 ? 0 : 10) }, RGB(0x7FA562))
            pp.strip(zNear, zFar, left: { edge($0, side < 0 ? 26 : 10) }, right: { edge($0, side < 0 ? 10 : 26) }, RGB(0x6E7177))
            pp.strip(zNear, zFar, left: { edge($0, side < 0 ? 28.5 : 26) }, right: { edge($0, side < 0 ? 26 : 28.5) }, RGB(0xD3CCBC))
            var z = zNear
            while z < 1800 {  // lane dashes
                pp.line3D((edge(z, 18), 0.05, z), (edge(z + 6, 18), 0.05, z + 6), RGB(0xE6E2D6), widthM: 0.25, minW: 0.4)
                z += 14
            }
            // Bank trees.
            z = zNear + 4
            while z < zFar {
                pp.addTree(edge(z, 5) + pp.rng.cg(-2, 2), z, r: pp.rng.cg(3.2, 4.6), flowering: pp.rng.chance(0.08) ? RGB(0xD9603E) : nil)
                z += pp.rng.cg(7, 12) * (z > 900 ? 1.8 : 1)
            }
            pp.lamps(along: { edge($0, 27) }, z0: zNear, z1: 2000, every: 26)
            // City blocks.
            z = zNear - 10
            while z < zFar {
                let far = z > 900
                let dz = far ? pp.rng.cg(22, 34) : pp.rng.cg(14, 22)
                let mid = z + dz / 2
                var off: CGFloat = 31
                let maxOff = cam.halfWidth(mid, W: W) + abs(centre(mid)) + 40
                while off < maxOff {
                    let bw = far ? pp.rng.cg(16, 32) : pp.rng.cg(9, 20)
                    let x0 = side < 0 ? L(mid) - off - bw : Rt(mid) + off
                    if pp.rng.chance(0.14) {
                        for _ in 0..<(far ? 1 : 2) { pp.addTree(x0 + pp.rng.cg(0, bw), z + pp.rng.cg(0, dz), r: pp.rng.cg(4, 6)) }
                    } else {
                        var h = pp.rng.cg(9, 26)
                        var glass = false
                        if pp.rng.chance(0.05) { h = pp.rng.cg(36, 55) }
                        if z > 1500 && x0 < -200 && x0 > -1100 && pp.rng.chance(0.12) { h = pp.rng.cg(70, 120); glass = true }
                        pp.addBox(pp.randomBox(x0: x0, x1: x0 + bw, z0: max(z, zNear - 30), z1: z + dz, h: h, glass: glass))
                    }
                    off += bw + (pp.rng.chance(0.15) ? pp.rng.cg(6, 9) : pp.rng.cg(1.5, 4))
                }
                z += dz + (pp.rng.chance(0.3) ? pp.rng.cg(6, 10) : pp.rng.cg(1.5, 3))
            }
        }
        // Footbridge, pylons, and the wave arch bridge on the lake.
        pp.addArchBridge(z: 430, x0: L(430) - 14, x1: Rt(430) + 14, deckY: 7, arches: [], width: 5)
        pp.addPylon(x: 4, z: 300, h: 55)
        pp.addPylon(x: -6, z: 680, h: 55)
        let bz: CGFloat = 1180, bx0 = L(bz) - 10, bx1 = Rt(bz) + 10, span = (bx1 - bx0) / 3
        pp.addArchBridge(z: bz, x0: bx0, x1: bx1, deckY: 6,
                         arches: [(bx0 + span * 0.1, bx0 + span * 1.05, 16), (bx0 + span * 0.95, bx0 + span * 2.05, 22), (bx0 + span * 1.95, bx0 + span * 2.9, 16)])
        pp.flush()

        let (base, lights) = pp.finish()
        var art = ViewArt(base: base, lights: lights, cam: cam, hasWater: true, waterTint: RGB(0x2F8F72))
        // Two-way traffic on each bank road, boats on the canal below the footbridge.
        for side in [-1.0, 1.0] as [CGFloat] {
            for (lane, toward) in [(15.0, false), (21.0, true)] as [(CGFloat, Bool)] {
                let len: CGFloat = 1800 - zNear
                art.lanes.append(Lane(kind: .car, length: len, point: { s in
                    let z = toward ? 1800 - s : zNear + s
                    return (side < 0 ? L(z) - lane : Rt(z) + lane, 0, z)
                }, toward: toward, fadeIn: toward ? 300 : 0, fadeOut: toward ? 0 : 300, count: 9, speed: 9...14))
            }
        }
        for (dx, toward) in [(-18.0, true), (20.0, false)] as [(CGFloat, Bool)] {
            art.lanes.append(Lane(kind: .boat, length: 420 - zNear, point: { s in
                let z = toward ? 420 - s : zNear + s
                return (dx, 0, z)
            }, toward: toward, fadeIn: toward ? 30 : 0, fadeOut: toward ? 0 : 30, count: 1, speed: 3...5))
        }
        let a = cam.p(-55, 0, zNear), b = cam.p(55, 0, 900)
        art.rippleRect = CGRect(x: a.x, y: 0, width: (cam.p(55, 0, zNear).x - a.x), height: b.y)
        art.planes = true
        art.skyline = 0
        art.groundTop = top
        return art
    }

    // MARK: Gulshan Lake: white double-arch bridge over a green lake, park trees, towers beyond.

    static func gulshanLake(W: CGFloat, H: CGFloat, seed: UInt64) -> ViewArt {
        let cam = Cam.make(W: W, H: H, height: 70, pitchDeg: 26, horizon: 0.8, cx: 0.5, cy: 0.42)
        let pp = PerspectivePainter(cam: cam, W: W, H: H, seed: seed)
        pp.hazeRange = 300...1600
        let zNear = cam.groundZ(atScreenY: -H * 0.03), zFar: CGFloat = 1700
        // The lake runs from the bottom-left corner away to the right.
        func lc(_ z: CGFloat) -> CGFloat { -95 + (z - zNear) * 0.42 }
        func lh(_ z: CGFloat) -> CGFloat { 40 + (z - zNear) * 0.03 }
        let L = { (z: CGFloat) in lc(z) - lh(z) }, Rt = { (z: CGFloat) in lc(z) + lh(z) }

        let top = pp.groundGradient(RGB(0x6F9A55), farZ: zFar)
        pp.strip(zNear, zFar, left: L, right: Rt, .black, clear: true)
        // Bank roads: one along the right shore, one crossing on the bridge.
        pp.strip(zNear, zFar, left: { Rt($0) + 6 }, right: { Rt($0) + 18 }, RGB(0x707379))
        pp.strip(zNear, zFar, left: { Rt($0) + 18 }, right: { Rt($0) + 20 }, RGB(0xD3CCBC))
        // Left: a deep park of trees. Right: the city.
        var z = zNear - 10
        while z < zFar {
            var x = L(z) - 4
            let minX = -cam.halfWidth(z, W: W)
            while x > minX {
                pp.addTree(x, z + pp.rng.cg(-3, 3), r: pp.rng.cg(4.5, 7.5) * (z > 700 ? 1.4 : 1),
                           flowering: pp.rng.chance(0.07) ? pp.rng.pick([RGB(0xD9603E), RGB(0xE69A3C)]) : nil)
                x -= pp.rng.cg(7, 11) * (z > 700 ? 1.6 : 1)
            }
            z += pp.rng.cg(7, 11) * (z > 700 ? 1.6 : 1)
        }
        z = zNear
        let bridgeZ = zNear + 40
        while z < zFar {
            // Leave the shore in front of the bridge open, so no tree stands between us and its traffic.
            if z < bridgeZ - 34 || z > bridgeZ + 14 {
                pp.addTree(Rt(z) + 3, z, r: pp.rng.cg(3.5, 5), flowering: pp.rng.chance(0.12) ? RGB(0xD9603E) : nil)
            }
            z += pp.rng.cg(8, 13)
        }
        z = zNear - 10
        var tallDone = false
        var roadside: [CGPath] = []   // blocks beside the shore road; cars pass behind them
        while z < zFar {
            let dz = pp.rng.cg(16, 26) * (z > 700 ? 1.5 : 1)
            var x = Rt(z + dz / 2) + 24
            let maxX = cam.halfWidth(z, W: W)
            while x < maxX {
                let bw = pp.rng.cg(12, 24) * (z > 700 ? 1.4 : 1)
                var h = pp.rng.cg(14, 36)
                var glass = false
                if !tallDone && z > 260 && x < Rt(z) + 60 { h = 78; tallDone = true }  // the landmark tower by the bridge
                if z > 900 && pp.rng.chance(0.2) { h = pp.rng.cg(60, 120); glass = pp.rng.chance(0.6) }
                // Seen from above, a tall block left of the camera leans out over the shore road, and cars on
                // the road would then be drawn across its roof. Keep each roof's lean clear of the road.
                if x < 0 {
                    while h > 4 {
                        let k = cam.height / (cam.height - h)
                        if x * k >= Rt((z + dz) * k) + 22 { break }
                        h -= 1
                    }
                }
                if h <= 6 || pp.rng.chance(0.1) { pp.addTree(x + bw / 2, z + dz / 2, r: pp.rng.cg(4, 6)) } else {
                    let b = pp.randomBox(x0: x, x1: x + bw, z0: z, z1: z + dz, h: h, glass: glass)
                    pp.addBox(b)
                    if x < Rt(z) + 120 { roadside.append(pp.silhouette(b)) }
                }
                x += bw + pp.rng.cg(2, 6)
            }
            z += dz + pp.rng.cg(2, 7)
        }
        // Far shore city across the lake.
        z = 1000
        while z < 1700 {
            var x = -cam.halfWidth(z, W: W)
            while x < L(z) - 20 {
                let bw = pp.rng.cg(20, 40)
                pp.addBox(pp.randomBox(x0: x, x1: x + bw, z0: z, z1: z + 30, h: pp.rng.cg(20, 70), glass: pp.rng.chance(0.3)))
                x += bw + pp.rng.cg(3, 10)
            }
            z += pp.rng.cg(35, 60)
        }
        // The bridge crosses the lake close to us.
        let bz = bridgeZ
        // The deck spans the water; a ramp then flares down onto the shore road like a real junction.
        let bx0 = L(bz) - 60, bx1 = Rt(bz), deckTop: CGFloat = 5.2
        pp.strip(bz, bz + 12, left: { _ in bx0 - 200 }, right: { _ in bx0 }, RGB(0x707379))
        pp.addArchBridge(z: bz, x0: bx0, x1: bx1, deckY: 4, arches: [(bx0 + 8, bx0 + (bx1 - bx0) * 0.55, 20), (bx0 + (bx1 - bx0) * 0.45, bx1 - 4, 17)], width: 12)
        let rampNear = (z: bz - 5, x: Rt(bz - 5) + 6), rampFar = (z: bz + 17, x: Rt(bz + 17) + 6)
        pp.add(bz + 11.9) { [unowned pp] in
            let p = pp.cam.p
            // Each edge eases from the deck down to the road edge, flaring outwards near the bottom.
            func edge(_ zd: CGFloat, _ end: (z: CGFloat, x: CGFloat)) -> [(CGFloat, CGFloat, CGFloat)] {
                (0...16).map { i in
                    let t = CGFloat(i) / 16, e = t * t * (3 - 2 * t)
                    let flare = pow(t, 2.2)
                    return (bx1 + (end.x - bx1) * t, deckTop * (1 - e), zd + (end.z - zd) * flare)
                }
            }
            let near = edge(bz, rampNear), far = edge(bz + 12, rampFar)
            // Surface in slices, shading from the deck's grey into the road's asphalt.
            for i in 0..<16 {
                let c = RGB.mix(RGB(0x8E9097), RGB(0x707379), Double(i) / 15)
                let q = [near[i], near[i + 1], far[i + 1], far[i]].map { p($0.0, $0.1, $0.2) }
                pp.poly(q, pp.tone(c, bz))
                pp.ctx.addPath(CGPath.poly(q)); pp.ctx.setStrokeColor(pp.tone(c, bz).cg()); pp.ctx.setLineWidth(1); pp.ctx.strokePath()
            }
            // The embankment wall facing us, then the railing following the slope.
            let wall = near.map { p($0.0, $0.1, $0.2) } + [p(rampNear.x, 0, rampNear.z), p(bx1, 0, bz)]
            pp.poly(wall, pp.tone(RGB(0xE4E4E8), bz))
            pp.ctx.strokeLine(pp.tone(RGB(0xC2483E), bz), 1, width: max(1, 0.25 * pp.cam.scale(4, bz)),
                              near.prefix(12).map { p($0.0, $0.1 + 1.0, $0.2) })
        }
        pp.lamps(along: { Rt($0) + 19 }, z0: zNear, z1: 1200, every: 22)
        pp.flush()

        let (base, lights) = pp.finish()
        var art = ViewArt(base: base, lights: lights, cam: cam, hasWater: true, waterTint: RGB(0x2E8A5E))
        art.front = (PerspectivePainter.cutout(base, roadside, W: W, H: H), PerspectivePainter.cutout(lights, roadside, W: W, H: H))
        // Bridge traffic: off the bridge, down the ramp and a smooth left or right turn into the shore road,
        // and the other way round. Road lanes: Rt+10 heads away (+z), Rt+15 comes toward us (-z).
        typealias W3 = (CGFloat, CGFloat, CGFloat)
        func ramp(_ zl: CGFloat, down: Bool) -> [W3] {
            let pts: [W3] = (0...10).map { i in
                let t = CGFloat(i) / 10, e = t * t * (3 - 2 * t)
                let zt = zl + (zl < bz + 6 ? -1 : 1) * 2 * t
                return (bx1 + (Rt(zt) + 6 - bx1) * t, deckTop * (1 - e), zt)
            }
            return down ? pts : pts.reversed()
        }
        /// A curve from `a` (moving along x) into the road lane `off` at depth `zt`, following the road's slope.
        func turn(from a: W3, lane off: CGFloat, to zt: CGFloat) -> [W3] {
            let b: W3 = (Rt(zt) + off, 0, zt)
            let c: W3 = (b.0 + (a.2 - zt) * 0.45, 0, a.2)  // where the two headings meet
            return (1...12).map { i in
                let t = CGFloat(i) / 12, u = 1 - t
                return (u * u * a.0 + 2 * u * t * c.0 + t * t * b.0, 0, u * u * a.2 + 2 * u * t * c.2 + t * t * b.2)
            }
        }
        func road(_ off: CGFloat, _ z0: CGFloat, _ z1: CGFloat) -> [W3] {
            (0...8).map { i in let z = z0 + (z1 - z0) * CGFloat(i) / 8; return (Rt(z) + off, 0, z) }
        }
        let east = bz + 3, west = bz + 8
        let deckE: [W3] = [(bx0 - 100, deckTop, east), (bx1, deckTop, east)]
        let downE = ramp(east, down: true)
        art.lanes.append(Lane.path(deckE + downE + turn(from: downE.last!, lane: 10, to: east + 18) + road(10, east + 18, bz + 420),
                                   fadeOut: 160, count: 2, speed: 6...9))
        art.lanes.append(Lane.path(deckE + downE + turn(from: downE.last!, lane: 15, to: east - 16) + road(15, east - 16, zNear - 30),
                                   toward: true, count: 2, speed: 6...9))
        let upW = ramp(west, down: false)
        let deckW: [W3] = [(bx1, deckTop, west), (bx0 - 100, deckTop, west)]
        func into(_ off: CGFloat, from zFrom: CGFloat) -> [W3] { Array(turn(from: upW[0], lane: off, to: zFrom).reversed()) }
        art.lanes.append(Lane.path(road(15, bz + 420, west + 22) + into(15, from: west + 22) + [upW[0]] + upW + deckW,
                                   toward: true, fadeIn: 160, count: 2, speed: 6...9))
        art.lanes.append(Lane.path(road(10, zNear - 30, west - 14) + into(10, from: west - 14) + [upW[0]] + upW + deckW,
                                   count: 2, speed: 6...9))
        for (lane, toward) in [(10.0, false), (15.0, true)] as [(CGFloat, Bool)] {
            art.lanes.append(Lane(kind: .car, length: 1100, point: { s in
                let z = toward ? zNear + 1100 - s : zNear + s
                return (Rt(z) + lane, 0, z)
            }, toward: toward, fadeIn: toward ? 200 : 0, fadeOut: toward ? 0 : 200, count: 5, speed: 8...12))
        }
        art.lanes.append(Lane(kind: .boat, length: 700, point: { s in
            let z = zNear + 60 + s
            return (lc(z) + 5, 0, z)
        }, fadeIn: 20, fadeOut: 60, count: 1, speed: 2...3.5))
        let a = cam.p(L(zNear), 0, zNear), b = cam.p(Rt(900), 0, 900)
        art.rippleRect = CGRect(x: max(0, a.x), y: 0, width: b.x - max(0, a.x), height: b.y)
        art.skyline = 0.03
        art.groundTop = top
        return art
    }

    // MARK: Lalbagh Fort gardens: Pari Bibi's tomb at the end of a brick walk with fountain pools.

    static func lalbagh(W: CGFloat, H: CGFloat, seed: UInt64) -> ViewArt {
        let cam = Cam.make(W: W, H: H, height: 9, pitchDeg: 8, horizon: 0.6, cx: 0.5, cy: 0.42)
        let pp = PerspectivePainter(cam: cam, W: W, H: H, seed: seed)
        pp.hazeRange = 200...900
        let zNear = cam.groundZ(atScreenY: -H * 0.03), zFar: CGFloat = 1000
        let brick = RGB(0xC98B78), joint = RGB(0xAF7360), stone = RGB(0xE0D6C6)

        let top = pp.groundGradient(RGB(0x7FAA5C), farZ: zFar, hazeMix: 0.35)
        // Mowing stripes on the lawns.
        for side in [-1.0, 1.0] as [CGFloat] {
            var x: CGFloat = 9
            while x < 90 {
                pp.strip(zNear, 104, left: { _ in side < 0 ? -x - 4 : x }, right: { _ in side < 0 ? -x : x + 4 }, RGB(0x8DB866), steps: 8)
                x += 8
            }
        }
        // Paths: main walk, cross walk, two side walks, the platform.
        pp.strip(zNear, 116, left: { _ in -7 }, right: { _ in 7 }, brick, steps: 10)
        pp.strip(104, 116, left: { _ in -120 }, right: { _ in 120 }, brick, steps: 4)
        for x in [-38.0, 34.0] as [CGFloat] { pp.strip(zNear, 104, left: { _ in x }, right: { _ in x + 4 }, brick, steps: 8) }
        var z = zNear
        while z < 116 {  // paving joints
            pp.line3D((-7, 0.02, z), (7, 0.02, z), joint, widthM: 0.06, minW: 0.4)
            z += 1.6
        }
        for x in stride(from: -7.0, through: 7.0, by: 1.75) {
            pp.line3D((CGFloat(x), 0.02, zNear), (CGFloat(x), 0.02, 116), joint, widthM: 0.05, minW: 0.4)
        }
        for edge in [-7.2, 7.2] as [CGFloat] {
            pp.strip(zNear, 116, left: { _ in edge - 0.3 }, right: { _ in edge + 0.3 }, stone, steps: 6)
        }
        // Fountain pools with stone borders and nozzles.
        var fountains: [(CGFloat, CGFloat)] = []
        for (z0, z1) in [(22.0, 46.0), (54.0, 76.0), (84.0, 98.0)] as [(CGFloat, CGFloat)] {
            pp.strip(z0 - 0.6, z1 + 0.6, left: { _ in -2.9 }, right: { _ in 2.9 }, stone, steps: 4)
            pp.strip(z0, z1, left: { _ in -2.3 }, right: { _ in 2.3 }, .black, clear: true, steps: 4)
            var nz = z0 + 3
            while nz < z1 - 2 { fountains.append((0, nz)); nz += 6 }
        }
        // Hedges along the walk, topiary rows, cone trees, lamp posts.
        for side in [-1.0, 1.0] as [CGFloat] {
            var hz = zNear
            while hz < 100 {
                let len = min(18, 100 - hz)
                let x0 = side < 0 ? -9.2 : 8.2
                pp.addBox(PerspectivePainter.Box(x0: x0, x1: x0 + 1, z0: hz, z1: hz + len, h: 0.8, wall: RGB(0x3F6E3A), roof: RGB(0x5C8E4B), details: false, litChance: 0))
                hz += len + 3
            }
            for rowX in [12.5, 25.0, 46.0] as [CGFloat] {
                var bz = zNear + 4
                while bz < 100 {
                    pp.addBush(side * rowX, bz, r: pp.rng.cg(1.1, 1.5), tall: rowX == 25 && pp.rng.chance(0.3))
                    bz += 9
                }
            }
            var lz = zNear + 8
            while lz < 104 {
                let lx = side * 8.8
                pp.add(lz) { [unowned pp] in
                    pp.line3D((lx, 0, lz), (lx, 3.6, lz), RGB(0x2E2E33), widthM: 0.12, minW: 0.7)
                    let q = pp.cam.p(lx, 3.8, lz), d = max(2, pp.cam.scale(3.8, lz) * 0.45)
                    pp.ctx.fillEllipse(RGB(0xE8E1CC), 1, R(q.x - d / 2, q.y - d / 2, d, d * 1.2))
                    pp.lit.fillEllipse(RGB(0xFFD9A0), 1, R(q.x - d / 2, q.y - d / 2, d, d * 1.2))
                    pp.lit.fillEllipse(RGB(0xFFD9A0), 0.15, R(q.x - d * 3, q.y - d * 3, d * 6, d * 6))
                }
                lz += 18
            }
        }
        // Platform and tomb.
        pp.addBox(PerspectivePainter.Box(x0: -34, x1: 34, z0: 116, z1: 150, h: 1.1, wall: RGB(0xD5C6B0), roof: RGB(0xD9CFC0), details: false, litChance: 0))
        let tomb = ArtLandmarks.pariBibi(height: 600)  // drawn at 1x, scaled into place
        pp.add(128) { [unowned pp] in
            let s = pp.cam.scale(1.1, 128)
            let w: CGFloat = 30 * s, h = w * tomb.size.height / tomb.size.width
            let b = pp.cam.p(0, 1.1, 128)
            pp.ctx.draw(tomb.base, in: R(b.x - w / 2, b.y, w, h))
            pp.lit.saveGState(); pp.lit.clip(to: R(b.x - w / 2, b.y, w, h), mask: tomb.base)
            pp.lit.setBlendMode(.clear); pp.lit.fill(R(b.x - w / 2, b.y, w, h)); pp.lit.restoreGState()
            pp.lit.draw(tomb.lights, in: R(b.x - w / 2, b.y, w, h))
        }
        // Fort wall, trees, then the city beyond.
        pp.addBox(PerspectivePainter.Box(x0: -260, x1: 260, z0: 240, z1: 244, h: 7, wall: RGB(0xB76C52), roof: RGB(0xC27A5E), details: false, litChance: 0))
        pp.add(239) { [unowned pp] in
            var x: CGFloat = -260
            while x < 260 {
                let a = pp.cam.p(x, 7, 240), b = pp.cam.p(x + 1.2, 7.9, 240)
                pp.ctx.fill(pp.tone(RGB(0xB76C52), 240), 1, R(a.x, a.y, b.x - a.x, b.y - a.y))
                x += 2.4
            }
        }
        for _ in 0..<60 {
            let x = pp.rng.cg(-220, 220)
            if abs(x) < 40 { continue }
            pp.addTree(x, pp.rng.cg(150, 235), r: pp.rng.cg(3.5, 6))
        }
        for x in [-70.0, -52.0, 52.0, 70.0] as [CGFloat] { pp.addTree(x, pp.rng.cg(125, 140), r: pp.rng.cg(3, 4)) }
        z = 260
        while z < zFar {
            var x = -cam.halfWidth(z, W: W)
            while x < cam.halfWidth(z, W: W) {
                let bw = pp.rng.cg(14, 30)
                pp.addBox(pp.randomBox(x0: x, x1: x + bw, z0: z, z1: z + 20, h: pp.rng.cg(12, 38)))
                x += bw + pp.rng.cg(1, 5)
            }
            z += pp.rng.cg(28, 50)
        }
        pp.flush()

        let (base, lights) = pp.finish()
        var art = ViewArt(base: base, lights: lights, cam: cam, hasWater: true, waterTint: RGB(0x4FA3A6))
        art.fountains = fountains.map { (cam.p($0.0, 0.2, $0.1), cam.scale(0.2, $0.1)) }
        // Visitors strolling: along the cross walk, the side walks and the main walk.
        for dir in [1.0, -1.0] as [CGFloat] {
            art.lanes.append(Lane(kind: .walker, length: 200, point: { s in (dir > 0 ? -100 + s : 100 - s, 0, dir > 0 ? 107 : 112) },
                                  fadeIn: 10, fadeOut: 10, count: 3, speed: 1.0...1.4))
        }
        for (x, toward) in [(-36.0, true), (36.0, false), (-5.0, false), (5.0, true)] as [(CGFloat, Bool)] {
            art.lanes.append(Lane(kind: .walker, length: 104 - zNear, point: { s in (x, 0, toward ? 104 - s : zNear + s) },
                                  toward: toward, fadeIn: 4, fadeOut: 4, count: 2, speed: 0.9...1.3))
        }
        let a = cam.p(-2.3, 0, zNear + 2), b = cam.p(2.3, 0, 98)
        art.rippleRect = CGRect(x: a.x - 40, y: cam.p(0, 0, 22).y, width: (b.x - a.x) + 80, height: b.y - cam.p(0, 0, 22).y)
        art.skyline = 0.04
        art.groundTop = top
        art.hazeDepth = 0.08
        return art
    }

    // MARK: City panorama: rooftops and greenery to the horizon, a tower cluster, a river.

    static func panorama(W: CGFloat, H: CGFloat, seed: UInt64) -> ViewArt {
        let cam = Cam.make(W: W, H: H, height: 170, pitchDeg: 9, horizon: 0.55, cx: 0.5, cy: 0.36)
        let pp = PerspectivePainter(cam: cam, W: W, H: H, seed: seed)
        pp.hazeRange = 700...4200
        let zNear = cam.groundZ(atScreenY: -H * 0.03), zFar: CGFloat = 4300
        func riverEdge(_ z: CGFloat) -> CGFloat { -420 - (z - 1300) * 0.95 }
        let avenue: ClosedRange<CGFloat> = 60...82

        let top = pp.groundGradient(RGB(0xB9AF9A), farZ: zFar)
        pp.strip(1300, zFar * 1.6, left: { _ in -9000 }, right: riverEdge, .black, clear: true)
        pp.strip(1300, zFar, left: riverEdge, right: { riverEdge($0) + 25 }, RGB(0x7FA562))
        pp.strip(zNear, zFar, left: { _ in avenue.lowerBound }, right: { _ in avenue.upperBound }, RGB(0x6E7177))
        pp.strip(880, 905, left: { _ in -2500 }, right: { _ in 2500 }, RGB(0x6E7177), steps: 4)
        pp.lamps(along: { _ in avenue.lowerBound - 1 }, z0: zNear, z1: 3000, every: 35, height: 9)
        pp.lamps(along: { _ in avenue.upperBound + 1 }, z0: zNear, z1: 3000, every: 35, height: 9)

        var z = zNear - 30
        while z < zFar {
            let far = z > 1600
            let dz = far ? pp.rng.cg(45, 80) : pp.rng.cg(18, 30)
            let hw = cam.halfWidth(z, W: W)
            var x = -hw
            while x < hw {
                let bw = far ? pp.rng.cg(30, 60) : pp.rng.cg(10, 22)
                defer { x += bw + pp.rng.cg(2, far ? 10 : 5) }
                if x + bw > avenue.lowerBound - 4 && x < avenue.upperBound + 4 { continue }
                if z > 1300 && x < riverEdge(z) + 30 { continue }
                if z > 880 && z < 905 { continue }
                // Lots of green, like the real city from above.
                if pp.rng.chance(far ? 0.15 : 0.3) {
                    for _ in 0..<(far ? 1 : 3) {
                        pp.addTree(x + pp.rng.cg(0, bw), z + pp.rng.cg(0, dz), r: pp.rng.cg(4, 7) * (far ? 2 : 1),
                                   flowering: pp.rng.chance(0.05) ? RGB(0xD9603E) : nil)
                    }
                    continue
                }
                var h = pp.rng.cg(10, 30)
                var glass = false
                let inCluster = z > 1700 && z < 3000 && x > -700 && x < 500
                if inCluster && pp.rng.chance(0.4) { h = pp.rng.cg(80, 190); glass = pp.rng.chance(0.7) }
                else if z > 900 && pp.rng.chance(0.08) { h = pp.rng.cg(40, 70) }
                pp.addBox(pp.randomBox(x0: x, x1: x + bw, z0: z, z1: z + dz * 0.8, h: h, glass: glass))
            }
            z += dz
        }
        var tz = zNear
        while tz < 2500 {
            for x in [avenue.lowerBound - 4, avenue.upperBound + 4] { pp.addTree(x, tz, r: 4) }
            tz += pp.rng.cg(16, 24)
        }
        pp.flush()

        let (base, lights) = pp.finish()
        var art = ViewArt(base: base, lights: lights, cam: cam, hasWater: true, waterTint: RGB(0x4E86A6))
        for (lane, toward) in [(66.0, false), (76.0, true)] as [(CGFloat, Bool)] {
            art.lanes.append(Lane(kind: .car, length: 2600, point: { s in (lane, 0, toward ? zNear + 2600 - s : zNear + s) },
                                  toward: toward, fadeIn: toward ? 600 : 0, fadeOut: toward ? 0 : 600, count: 12, speed: 10...15))
        }
        art.planes = true
        art.skyline = 0.02
        art.groundTop = top
        art.hazeDepth = 0.2
        return art
    }
}
