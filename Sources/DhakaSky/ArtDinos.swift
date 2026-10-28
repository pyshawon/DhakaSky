import AppKit
import SpriteKit

// MARK: - Dinosaur World: friendly cartoon dinosaurs, a volcano and a lake

enum Dino: String, CaseIterable {
    case trex, triceratops, stegosaurus, brachiosaurus, diplodocus, ankylosaurus,
         parasaurolophus, spinosaurus, velociraptor, pachycephalosaurus, dilophosaurus, gallimimus

    /// Kinds that sometimes walk with a little one in tow.
    var hasBabies: Bool { [.triceratops, .stegosaurus, .brachiosaurus, .diplodocus, .ankylosaurus, .parasaurolophus].contains(self) }
}

/// A walk cycle: frames drawn in metres at `ppm`, feet on `anchor`.
struct DinoArt {
    var frames: [SKTexture]
    var size: CGSize          // points, at the ppm it was drawn
    var anchor: CGPoint
    var cycle: CGFloat        // metres travelled per walk cycle (keeps feet from sliding)
}

/// What the dinosaur view needs beyond the static painting.
struct DinoExtras {
    var foreground: CGImage
    var crater: CGPoint
    var craterHW: CGFloat
    var lake: CGRect
    var bands: [(y: CGFloat, scale: CGFloat)]   // far → near
    var ppm: CGFloat
}

/// Where the walking pose is in its cycle, shared by every part of one frame.
private struct Pose {
    var ph: CGFloat
    var bob: CGFloat
    var nod: CGFloat
    var tail: [CGPoint]
}

private struct Plan {
    var size: CGSize
    var biped = false
    var color: RGB, belly: RGB, spot: RGB
    var body: CGRect
    var tail: [CGPoint], tailW: [CGFloat]
    var neck: [CGPoint], neckW: [CGFloat]
    var head: CGRect, headCorner: CGFloat
    var eye: CGPoint, eyeR: CGFloat
    var smile: (CGPoint, CGPoint)
    var hip: CGPoint, legW: CGFloat
    var shoulder: CGPoint? = nil, frontW: CGFloat = 0
    var arm: CGPoint? = nil, armLen: CGFloat = 0
    var stride: CGFloat = 0.32
    var bob: CGFloat = 0.06
    var headExtras: [CGPath] = []                          // same colour as the head (bumps)
    var bodyBehind: ((CGContext, Pose) -> Void)? = nil     // plates, sails, back spikes
    var headBehind: ((CGContext, Pose) -> Void)? = nil     // frills, crests (head coordinates)
    var bodyFront: ((CGContext, Pose) -> Void)? = nil      // armour, tail club, feathers
    var headFront: ((CGContext, Pose) -> Void)? = nil      // horns, teeth, domes
}

enum ArtDinos {
    static let ground: CGFloat = 0.08   // metres of canvas below the feet

    // MARK: Drawing helpers

    private static func catmull(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
        let t2 = t * t, t3 = t2 * t
        func c(_ a: CGFloat, _ b: CGFloat, _ cc: CGFloat, _ d: CGFloat) -> CGFloat {
            let k1: CGFloat = 2 * b
            let k2: CGFloat = (cc - a) * t
            let k3: CGFloat = (2 * a - 5 * b + 4 * cc - d) * t2
            let k4: CGFloat = (3 * b - a - 3 * cc + d) * t3
            return 0.5 * (k1 + k2 + k3 + k4)
        }
        return P(c(p0.x, p1.x, p2.x, p3.x), c(p0.y, p1.y, p2.y, p3.y))
    }

    /// A smooth tapered tube through `pts` with round ends.
    static func tube(_ pts: [CGPoint], _ ws: [CGFloat], samples: Int = 10) -> CGPath {
        var c: [CGPoint] = [], w: [CGFloat] = []
        let n = pts.count
        for i in 0..<(n - 1) {
            let p0 = pts[max(0, i - 1)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(n - 1, i + 2)]
            for k in 0..<samples {
                let t = CGFloat(k) / CGFloat(samples)
                c.append(catmull(p0, p1, p2, p3, t))
                w.append(ws[i] + (ws[i + 1] - ws[i]) * t)
            }
        }
        c.append(pts[n - 1]); w.append(ws[n - 1])
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in 0..<c.count {
            let a = c[max(0, i - 1)], b = c[min(c.count - 1, i + 1)]
            let l = max(1e-6, hypot(b.x - a.x, b.y - a.y))
            let nx = -(b.y - a.y) / l, ny = (b.x - a.x) / l
            left.append(P(c[i].x + nx * w[i] / 2, c[i].y + ny * w[i] / 2))
            right.append(P(c[i].x - nx * w[i] / 2, c[i].y - ny * w[i] / 2))
        }
        let p = CGMutablePath()
        p.move(to: left[0])
        for q in left.dropFirst() { p.addLine(to: q) }
        let e = c[c.count - 1], er = max(0.001, w[w.count - 1] / 2)
        let a1 = atan2(left[left.count - 1].y - e.y, left[left.count - 1].x - e.x)
        p.addArc(center: e, radius: er, startAngle: a1, endAngle: a1 - .pi, clockwise: true)
        for q in right.reversed() { p.addLine(to: q) }
        let s = c[0], sr = max(0.001, w[0] / 2)
        let a2 = atan2(right[0].y - s.y, right[0].x - s.x)
        p.addArc(center: s, radius: sr, startAngle: a2, endAngle: a2 - .pi, clockwise: true)
        p.closeSubpath()
        return p
    }

    static func ellipse(_ r: CGRect) -> CGPath { CGPath(ellipseIn: r, transform: nil) }
    static func ellipse(_ c: CGPoint, _ rx: CGFloat, _ ry: CGFloat) -> CGPath { ellipse(R(c.x - rx, c.y - ry, rx * 2, ry * 2)) }

    /// Parts filled in one colour with a single outline around the whole group (joins stay clean).
    static func outlined(_ ctx: CGContext, _ parts: [CGPath], _ fill: RGB, _ line: RGB, _ ow: CGFloat = 0.05) {
        ctx.setLineJoin(.round)
        for p in parts { ctx.addPath(p); ctx.setStrokeColor(line.cg()); ctx.setLineWidth(ow * 2); ctx.strokePath() }
        for p in parts { ctx.fillPath(fill, 1, p) }
    }

    private static func lerpP(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint { P(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t) }

    // MARK: Walk cycles

    static func art(_ d: Dino, ppm: CGFloat) -> DinoArt {
        let plan = self.plan(d)
        let frames = (0..<8).map { i -> SKTexture in
            let ph = CGFloat(i) / 8 * .pi * 2
            let img = Painter.image(CGSize(width: plan.size.width * ppm, height: plan.size.height * ppm)) { ctx in
                ctx.scaleBy(x: ppm, y: ppm)
                ctx.setLineCap(.round); ctx.setLineJoin(.round)
                draw(plan, ph: ph, ctx: ctx, seed: UInt64(d.rawValue.count * 31 + 7))
            }
            return Painter.texture(img)
        }
        let L = plan.hip.y - ground
        return DinoArt(frames: frames, size: CGSize(width: plan.size.width * ppm, height: plan.size.height * ppm),
                       anchor: P(0.5, ground / plan.size.height), cycle: 4 * L * sin(plan.stride))
    }

    private static func leg(_ ctx: CGContext, hip: CGPoint, phase: CGFloat, w: CGFloat, plan: Plan, far: Bool) {
        let L = hip.y - ground - w * 0.3
        let a = sin(phase) * plan.stride
        let lift = max(0, cos(phase)) * L * (plan.biped ? 0.16 : 0.1)
        let foot = P(hip.x + sin(a) * L, ground + w * 0.3 + lift)
        let knee = P((hip.x + foot.x) / 2 + (plan.biped ? L * 0.14 : lift * 0.4), (hip.y + foot.y) / 2)
        let col = far ? plan.color.darker(0.18) : plan.color
        var parts = [tube([hip, knee, foot], [w * 1.3, w, w * 0.9]),
                     ellipse(R(foot.x - w * 0.6, foot.y - w * 0.3, w * 1.5, w * 0.6))]
        if plan.biped { parts.append(ellipse(R(hip.x - w * 1.05, hip.y - w * 1.25, w * 2.1, w * 2.3))) }
        outlined(ctx, parts, col, plan.color.darker(0.5))
        for k in 0..<3 {  // toenails
            let x = foot.x + w * 0.5 - CGFloat(k) * w * 0.3
            ctx.fillEllipse(RGB(0xF6EEDC), far ? 0.6 : 1, R(x, foot.y - w * 0.28, w * 0.24, w * 0.18))
        }
    }

    private static func draw(_ plan: Plan, ph: CGFloat, ctx: CGContext, seed: UInt64) {
        let bob = cos(ph * 2) * plan.bob * 0.5
        let nod = sin(ph * 2 + 0.6) * plan.bob * 0.6
        var tail = plan.tail
        for i in 1..<tail.count { tail[i].y += sin(ph) * 0.08 * CGFloat(i) }
        let pose = Pose(ph: ph, bob: bob, nod: nod, tail: tail)
        let outline = plan.color.darker(0.5)

        // Far legs.
        let hip = P(plan.hip.x, plan.hip.y + bob)
        leg(ctx, hip: P(hip.x - 0.12, hip.y), phase: ph + .pi, w: plan.legW, plan: plan, far: true)
        if let s = plan.shoulder {
            leg(ctx, hip: P(s.x - 0.12, s.y + bob), phase: ph, w: plan.frontW, plan: plan, far: true)
        }
        if let a = plan.arm {
            let ang = sin(ph) * 0.3
            ctx.saveGState(); ctx.translateBy(x: -0.1, y: bob)
            outlined(ctx, [tube([a, P(a.x + plan.armLen * 0.55, a.y - plan.armLen * 0.4 + ang * 0.2), P(a.x + plan.armLen * 0.9, a.y - plan.armLen * 0.8)],
                                [plan.armLen * 0.32, plan.armLen * 0.24, plan.armLen * 0.16])], plan.color.darker(0.18), outline)
            ctx.restoreGState()
        }

        ctx.saveGState()
        ctx.translateBy(x: 0, y: bob)
        plan.bodyBehind?(ctx, pose)
        ctx.saveGState(); ctx.translateBy(x: 0, y: nod)
        plan.headBehind?(ctx, pose)
        ctx.restoreGState()

        // Body, tail, neck and head as one outlined shape.
        var neck = plan.neck
        neck[neck.count - 1].y += nod
        if neck.count > 2 { neck[neck.count - 2].y += nod * 0.5 }
        let head = plan.head.offsetBy(dx: 0, dy: nod)
        var parts = [tube(tail, plan.tailW), ellipse(plan.body), tube(neck, plan.neckW),
                     CGPath(roundedRect: head, cornerWidth: plan.headCorner, cornerHeight: plan.headCorner, transform: nil)]
        var t = CGAffineTransform(translationX: 0, y: nod)
        parts += plan.headExtras.compactMap { $0.copy(using: &t) }
        outlined(ctx, parts, plan.color, outline)

        // Belly and spots, kept inside the body.
        ctx.saveGState()
        ctx.addPath(ellipse(plan.body)); ctx.clip()
        let b = plan.body
        ctx.fillEllipse(plan.belly, 1, R(b.minX + b.width * 0.12, b.minY - b.height * 0.55, b.width * 0.8, b.height * 0.95))
        var rng = SeededRNG(seed: seed)
        for _ in 0..<7 {
            let x = rng.cg(b.minX + b.width * 0.15, b.maxX - b.width * 0.2)
            let y = rng.cg(b.midY + b.height * 0.05, b.maxY - b.height * 0.12)
            let r = rng.cg(0.1, 0.22) * min(1, b.height / 1.6)
            ctx.fillEllipse(plan.spot, 0.8, R(x - r, y - r * 0.8, r * 2, r * 1.6))
        }
        ctx.restoreGState()
        plan.bodyFront?(ctx, pose)
        ctx.restoreGState()

        // Near arm and legs.
        if let a = plan.arm {
            let ang = sin(ph + .pi) * 0.3
            ctx.saveGState(); ctx.translateBy(x: 0, y: bob)
            outlined(ctx, [tube([a, P(a.x + plan.armLen * 0.55, a.y - plan.armLen * 0.4 + ang * 0.2), P(a.x + plan.armLen * 0.9, a.y - plan.armLen * 0.8)],
                                [plan.armLen * 0.34, plan.armLen * 0.26, plan.armLen * 0.17])], plan.color, outline)
            ctx.restoreGState()
        }
        leg(ctx, hip: hip, phase: ph, w: plan.legW, plan: plan, far: false)
        if let s = plan.shoulder { leg(ctx, hip: P(s.x, s.y + bob), phase: ph + .pi, w: plan.frontW, plan: plan, far: false) }

        // Face.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: bob + nod)
        plan.headFront?(ctx, pose)
        let e = plan.eye, r = plan.eyeR
        ctx.fillEllipse(RGB(0xF08A8A), 0.35, R(e.x + r * 0.2, e.y - r * 2.3, r * 1.6, r * 0.9))   // rosy cheek
        outlined(ctx, [ellipse(e, r, r * 1.12)], .white, outline, 0.03)
        ctx.fillEllipse(RGB(0x1E1A1A), 1, R(e.x - r * 0.35, e.y - r * 0.62, r * 1.15, r * 1.25))
        ctx.fillEllipse(.white, 1, R(e.x + r * 0.08, e.y + r * 0.12, r * 0.42, r * 0.42))
        ctx.fillEllipse(.white, 0.8, R(e.x - r * 0.2, e.y - r * 0.4, r * 0.2, r * 0.2))
        let (s0, s1) = plan.smile
        let sm = CGMutablePath()
        sm.move(to: s0)
        sm.addQuadCurve(to: s1, control: P((s0.x + s1.x) / 2, min(s0.y, s1.y) - 0.12))
        ctx.addPath(sm); ctx.setStrokeColor(outline.cg()); ctx.setLineWidth(0.06); ctx.strokePath()
        let h = plan.head
        ctx.fillEllipse(outline, 0.8, R(h.maxX - h.height * 0.22, h.maxY - h.height * 0.3, h.height * 0.1, h.height * 0.07))
        ctx.restoreGState()
    }

    // MARK: Species

    private static func teeth(_ ctx: CGContext, from x0: CGFloat, to x1: CGFloat, y: CGFloat, size: CGFloat) {
        var x = x0
        while x < x1 {
            ctx.fillPath(RGB(0xFFFDF5), 1, CGPath.poly([P(x, y), P(x + size, y), P(x + size / 2, y - size * 1.1)]))
            x += size * 1.7
        }
    }

    private static func plan(_ d: Dino) -> Plan {
        switch d {
        case .trex:
            let c = RGB(0x6DBA5E)
            return Plan(size: CGSize(width: 7.6, height: 5.0), biped: true, color: c, belly: RGB(0xF0E6A8), spot: RGB(0x529C47),
                        body: R(1.75, 1.75, 3.1, 2.05), tail: [P(2.1, 2.9), P(1.1, 2.9), P(0.25, 2.6)], tailW: [1.3, 0.7, 0.16],
                        neck: [P(4.3, 3.1), P(4.9, 3.55)], neckW: [1.25, 1.05],
                        head: R(4.55, 3.15, 2.55, 1.4), headCorner: 0.6, eye: P(5.45, 4.12), eyeR: 0.25,
                        smile: (P(5.95, 3.5), P(7.0, 3.62)), hip: P(3.0, 2.25), legW: 0.55,
                        arm: P(4.4, 2.55), armLen: 0.55, stride: 0.42, bob: 0.12,
                        headFront: { ctx, _ in teeth(ctx, from: 6.1, to: 6.95, y: 3.5, size: 0.13) })
        case .triceratops:
            let c = RGB(0xEE9A4E), frill = RGB(0x5DB8A8), horn = RGB(0xF6EBD0)
            return Plan(size: CGSize(width: 7.1, height: 3.9), color: c, belly: RGB(0xF8DDB0), spot: RGB(0xD27C34),
                        body: R(1.3, 1.0, 3.9, 2.1), tail: [P(1.6, 2.0), P(0.8, 1.85), P(0.15, 1.5)], tailW: [1.0, 0.5, 0.12],
                        neck: [P(4.7, 2.15), P(5.25, 2.1)], neckW: [1.35, 1.2],
                        head: R(5.0, 1.35, 1.7, 1.25), headCorner: 0.5, eye: P(5.72, 2.2), eyeR: 0.21,
                        smile: (P(6.0, 1.75), P(6.6, 1.82)), hip: P(2.0, 1.5), legW: 0.6, shoulder: P(4.4, 1.45), frontW: 0.58,
                        stride: 0.33, bob: 0.05,
                        headBehind: { ctx, _ in
                            var parts = [ellipse(P(5.1, 2.4), 1.0, 1.05)]
                            for k in 0..<9 {
                                let a = CGFloat(k) / 8 * 3.3 + 0.1
                                parts.append(ellipse(P(5.1 + cos(a) * 1.0, 2.4 + sin(a) * 1.05), 0.2, 0.2))
                            }
                            outlined(ctx, parts, frill, frill.darker(0.5))
                            for k in 0..<6 {
                                let a = CGFloat(k) / 5 * 2.6 + 0.3
                                ctx.fillEllipse(frill.lighter(0.4), 1, R(5.1 + cos(a) * 0.7 - 0.1, 2.4 + sin(a) * 0.72 - 0.1, 0.2, 0.2))
                            }
                            outlined(ctx, [tube([P(5.8, 2.45), P(6.2, 2.85), P(6.75, 3.0)], [0.24, 0.15, 0.04])], horn.darker(0.12), c.darker(0.5))
                        },
                        headFront: { ctx, _ in
                            outlined(ctx, [tube([P(5.55, 2.5), P(5.95, 2.95), P(6.5, 3.2)], [0.27, 0.16, 0.04])], horn, c.darker(0.5))
                            outlined(ctx, [tube([P(6.4, 2.35), P(6.55, 2.6), P(6.6, 2.85)], [0.22, 0.12, 0.03])], horn, c.darker(0.5))
                            ctx.fillPath(c.darker(0.3), 1, CGPath.poly([P(6.45, 1.42), P(6.98, 1.62), P(6.55, 1.98)]))
                        })
        case .stegosaurus:
            let c = RGB(0xA9C25C), p1 = RGB(0xF08A4B), p2 = RGB(0xF4B64A)
            let body = R(1.6, 1.1, 3.8, 2.2)
            return Plan(size: CGSize(width: 7.3, height: 4.6), color: c, belly: RGB(0xEEF2BE), spot: RGB(0x8AA545),
                        body: body, tail: [P(1.9, 2.1), P(0.9, 2.05), P(0.2, 2.25)], tailW: [1.0, 0.5, 0.18],
                        neck: [P(5.0, 1.95), P(5.7, 1.65)], neckW: [0.95, 0.65],
                        head: R(5.45, 1.25, 1.2, 0.75), headCorner: 0.33, eye: P(6.0, 1.75), eyeR: 0.16,
                        smile: (P(6.2, 1.45), P(6.62, 1.5)), hip: P(2.4, 1.45), legW: 0.55, shoulder: P(4.6, 1.3), frontW: 0.48,
                        stride: 0.3, bob: 0.05,
                        bodyBehind: { ctx, pose in
                            func plate(_ x: CGFloat, _ h: CGFloat, _ col: RGB, _ dx: CGFloat) {
                                let rx = body.width / 2, cx = body.midX
                                let u = (x - cx) / rx
                                let top = body.midY + body.height / 2 * sqrt(max(0, 1 - u * u))
                                let path = CGMutablePath()
                                path.move(to: P(x - h * 0.42 + dx, top - 0.3))
                                path.addQuadCurve(to: P(x + dx, top + h), control: P(x - h * 0.5 + dx, top + h * 0.55))
                                path.addQuadCurve(to: P(x + h * 0.42 + dx, top - 0.3), control: P(x + h * 0.5 + dx, top + h * 0.55))
                                path.closeSubpath()
                                outlined(ctx, [path], col, col.darker(0.5))
                            }
                            for k in 0..<7 { plate(1.9 + CGFloat(k) * 0.52, 0.55 + 0.5 * sin(CGFloat(k) / 6 * .pi), (k % 2 == 0 ? p2 : p1).darker(0.15), 0.26) }
                            for k in 0..<7 { plate(1.75 + CGFloat(k) * 0.52, 0.6 + 0.55 * sin(CGFloat(k) / 6 * .pi), k % 2 == 0 ? p1 : p2, 0) }
                            let t = pose.tail
                            let a = lerpP(t[1], t[2], 0.45), b = lerpP(t[1], t[2], 0.85)
                            for (q, s) in [(a, 1.0), (b, 0.85)] as [(CGPoint, CGFloat)] {
                                outlined(ctx, [tube([q, P(q.x - 0.25 * s, q.y + 0.55 * s)], [0.16, 0.03])], RGB(0xF6EBD0), c.darker(0.5))
                                outlined(ctx, [tube([q, P(q.x - 0.45 * s, q.y + 0.3 * s)], [0.16, 0.03])], RGB(0xF6EBD0), c.darker(0.5))
                            }
                        })
        case .brachiosaurus:
            let c = RGB(0x6FA8DC)
            return Plan(size: CGSize(width: 7.8, height: 9.6), color: c, belly: RGB(0xD7E9F7), spot: RGB(0x5590C8),
                        body: R(1.8, 2.45, 3.8, 2.3), tail: [P(2.0, 3.4), P(1.0, 3.0), P(0.2, 2.3)], tailW: [1.0, 0.55, 0.15],
                        neck: [P(5.0, 4.2), P(5.75, 6.3), P(6.15, 8.3)], neckW: [1.3, 0.85, 0.66],
                        head: R(5.8, 8.05, 1.55, 0.85), headCorner: 0.4, eye: P(6.55, 8.6), eyeR: 0.18,
                        smile: (P(6.85, 8.3), P(7.3, 8.35)), hip: P(2.6, 2.95), legW: 0.7, shoulder: P(4.8, 3.15), frontW: 0.66,
                        stride: 0.22, bob: 0.06,
                        headExtras: [ellipse(P(6.25, 8.85), 0.38, 0.32)])
        case .diplodocus:
            let c = RGB(0xB58ACF)
            return Plan(size: CGSize(width: 10.0, height: 4.7), color: c, belly: RGB(0xEEDFF5), spot: RGB(0x9A6DB8),
                        body: R(3.0, 1.6, 3.6, 2.1), tail: [P(3.3, 2.7), P(1.9, 2.65), P(0.7, 2.25), P(0.12, 1.9)], tailW: [1.0, 0.6, 0.25, 0.08],
                        neck: [P(6.3, 3.0), P(7.5, 3.6), P(8.6, 3.9)], neckW: [1.15, 0.66, 0.5],
                        head: R(8.4, 3.55, 1.35, 0.72), headCorner: 0.34, eye: P(9.05, 4.05), eyeR: 0.16,
                        smile: (P(9.3, 3.78), P(9.72, 3.82)), hip: P(4.0, 2.05), legW: 0.6, shoulder: P(5.8, 2.0), frontW: 0.56,
                        stride: 0.26, bob: 0.05,
                        bodyBehind: { ctx, _ in
                            for k in 0..<9 {  // little back spines
                                let x = 3.4 + CGFloat(k) * 0.36
                                let u = (x - 4.8) / 1.8
                                let top = 2.65 + 1.05 * sqrt(max(0, 1 - u * u))
                                ctx.fillPath(c.darker(0.25), 1, CGPath.poly([P(x - 0.13, top - 0.1), P(x, top + 0.22), P(x + 0.13, top - 0.1)]))
                            }
                        })
        case .ankylosaurus:
            let c = RGB(0xC9A46A), armour = RGB(0x9C7A48)
            let body = R(1.4, 0.8, 3.6, 1.6)
            return Plan(size: CGSize(width: 6.4, height: 2.8), color: c, belly: RGB(0xF0E2C0), spot: RGB(0xB08C55),
                        body: body, tail: [P(1.6, 1.4), P(0.85, 1.28), P(0.45, 1.18)], tailW: [0.7, 0.35, 0.22],
                        neck: [P(4.8, 1.4), P(5.15, 1.35)], neckW: [0.85, 0.75],
                        head: R(4.9, 0.95, 1.2, 0.85), headCorner: 0.36, eye: P(5.5, 1.5), eyeR: 0.15,
                        smile: (P(5.72, 1.18), P(6.05, 1.24)), hip: P(2.2, 1.05), legW: 0.48, shoulder: P(4.3, 1.0), frontW: 0.45,
                        stride: 0.3, bob: 0.035,
                        bodyBehind: { ctx, _ in
                            for k in 0..<9 {
                                let x = body.minX + 0.35 + CGFloat(k) * 0.37
                                let u = (x - body.midX) / (body.width / 2)
                                let top = body.midY + body.height / 2 * sqrt(max(0, 1 - u * u))
                                outlined(ctx, [CGPath.poly([P(x - 0.15, top - 0.15), P(x, top + 0.22), P(x + 0.15, top - 0.15)])], RGB(0xF2E6CC), c.darker(0.5), 0.03)
                            }
                        },
                        bodyFront: { ctx, pose in
                            ctx.saveGState()
                            ctx.addPath(ellipse(body)); ctx.clip()
                            for row in 0..<3 {
                                for k in 0..<8 {
                                    let x = body.minX + 0.4 + CGFloat(k) * 0.42 + CGFloat(row % 2) * 0.2
                                    let y = body.maxY - 0.3 - CGFloat(row) * 0.33
                                    ctx.fillEllipse(armour, 1, R(x - 0.14, y - 0.11, 0.28, 0.22))
                                    ctx.fillEllipse(armour.lighter(0.35), 1, R(x - 0.06, y, 0.1, 0.07))
                                }
                            }
                            ctx.restoreGState()
                            let tip = pose.tail[pose.tail.count - 1]
                            outlined(ctx, [ellipse(P(tip.x - 0.05, tip.y), 0.42, 0.3)], armour, c.darker(0.5))
                            ctx.fillEllipse(armour.lighter(0.3), 1, R(tip.x - 0.25, tip.y + 0.05, 0.2, 0.12))
                        })
        case .parasaurolophus:
            let c = RGB(0xE6788F), crest = RGB(0xF2C14E)
            return Plan(size: CGSize(width: 6.6, height: 5.0), biped: true, color: c, belly: RGB(0xF9DCE2), spot: RGB(0xCC5D75),
                        body: R(2.0, 1.85, 2.8, 1.7), tail: [P(2.2, 2.75), P(1.2, 2.65), P(0.2, 2.35)], tailW: [1.0, 0.55, 0.12],
                        neck: [P(4.4, 3.0), P(4.95, 3.7)], neckW: [0.9, 0.66],
                        head: R(4.7, 3.45, 1.4, 0.72), headCorner: 0.33, eye: P(5.2, 3.9), eyeR: 0.17,
                        smile: (P(5.55, 3.62), P(6.05, 3.68)), hip: P(3.1, 2.1), legW: 0.48,
                        arm: P(4.25, 2.6), armLen: 0.6, stride: 0.4, bob: 0.1,
                        headBehind: { ctx, _ in
                            outlined(ctx, [tube([P(5.0, 3.95), P(4.45, 4.4), P(3.75, 4.55)], [0.38, 0.32, 0.26])], crest, c.darker(0.5))
                        })
        case .spinosaurus:
            let c = RGB(0x4FA3A5), sail = RGB(0xE96A4F)
            return Plan(size: CGSize(width: 8.6, height: 5.4), biped: true, color: c, belly: RGB(0xD8EFE6), spot: RGB(0x3E8B8D),
                        body: R(2.4, 2.0, 3.2, 1.8), tail: [P(2.6, 2.9), P(1.4, 2.8), P(0.2, 2.5)], tailW: [1.1, 0.6, 0.14],
                        neck: [P(5.3, 3.2), P(5.9, 3.55)], neckW: [0.95, 0.8],
                        head: R(5.6, 3.25, 2.7, 0.82), headCorner: 0.38, eye: P(6.1, 3.82), eyeR: 0.18,
                        smile: (P(6.6, 3.45), P(8.25, 3.5)), hip: P(3.6, 2.25), legW: 0.55,
                        arm: P(5.0, 2.6), armLen: 0.65, stride: 0.4, bob: 0.1,
                        bodyBehind: { ctx, _ in
                            let s = CGMutablePath()
                            s.move(to: P(2.5, 3.3))
                            s.addCurve(to: P(4.0, 5.15), control1: P(2.7, 4.6), control2: P(3.3, 5.1))
                            s.addCurve(to: P(5.5, 3.4), control1: P(4.8, 5.2), control2: P(5.4, 4.5))
                            s.closeSubpath()
                            outlined(ctx, [s], sail, sail.darker(0.5))
                            for k in 0..<6 {
                                let x = 2.85 + CGFloat(k) * 0.45
                                ctx.strokeLine(sail.darker(0.25), 1, width: 0.07, [P(x, 3.5), P(x + 0.1, 4.2 + 0.6 * sin(CGFloat(k) / 5 * .pi))])
                            }
                        },
                        headFront: { ctx, _ in teeth(ctx, from: 6.9, to: 8.2, y: 3.47, size: 0.11) })
        case .velociraptor:
            let c = RGB(0x8F79D9), feather = RGB(0xF2A33A)
            return Plan(size: CGSize(width: 3.5, height: 2.2), biped: true, color: c, belly: RGB(0xE6E0F8), spot: RGB(0x7562C2),
                        body: R(1.2, 0.98, 1.25, 0.75), tail: [P(1.3, 1.38), P(0.75, 1.48), P(0.18, 1.58)], tailW: [0.45, 0.25, 0.12],
                        neck: [P(2.25, 1.52), P(2.55, 1.78)], neckW: [0.4, 0.3],
                        head: R(2.35, 1.62, 0.9, 0.44), headCorner: 0.2, eye: P(2.68, 1.92), eyeR: 0.11,
                        smile: (P(2.85, 1.72), P(3.2, 1.76)), hip: P(1.65, 1.1), legW: 0.22,
                        arm: P(2.15, 1.3), armLen: 0.38, stride: 0.55, bob: 0.07,
                        bodyBehind: { ctx, pose in
                            let tip = pose.tail[pose.tail.count - 1]
                            for (k, a) in [(-0.35), 0, 0.35].enumerated() {
                                let path = tube([tip, P(tip.x - 0.4 * cos(a), tip.y + 0.4 * sin(a))], [0.2, 0.06])
                                outlined(ctx, [path], k == 1 ? feather : feather.darker(0.15), c.darker(0.5), 0.03)
                            }
                        },
                        headBehind: { ctx, _ in
                            for k in 0..<3 {
                                let x = 2.45 + CGFloat(k) * 0.12
                                outlined(ctx, [tube([P(x, 1.98), P(x - 0.22, 2.2 - CGFloat(k) * 0.05)], [0.09, 0.03])], feather, c.darker(0.5), 0.025)
                            }
                        })
        case .pachycephalosaurus:
            let c = RGB(0xF2CF55), dome = RGB(0xC98B4D)
            return Plan(size: CGSize(width: 4.6, height: 3.6), biped: true, color: c, belly: RGB(0xFBF1C6), spot: RGB(0xDDB43A),
                        body: R(1.4, 1.3, 1.9, 1.25), tail: [P(1.55, 1.98), P(0.8, 1.98), P(0.15, 1.78)], tailW: [0.75, 0.4, 0.1],
                        neck: [P(3.0, 2.28), P(3.3, 2.58)], neckW: [0.62, 0.5],
                        head: R(3.05, 2.28, 0.98, 0.62), headCorner: 0.26, eye: P(3.55, 2.65), eyeR: 0.13,
                        smile: (P(3.7, 2.45), P(4.0, 2.5)), hip: P(2.1, 1.45), legW: 0.36,
                        arm: P(2.85, 1.85), armLen: 0.4, stride: 0.45, bob: 0.08,
                        headFront: { ctx, _ in
                            outlined(ctx, [ellipse(P(3.42, 2.95), 0.5, 0.4)], dome, c.darker(0.5), 0.04)
                            ctx.fillEllipse(dome.lighter(0.35), 1, R(3.25, 3.1, 0.25, 0.13))
                            for k in 0..<4 {
                                let a = 2.4 + CGFloat(k) * 0.35
                                ctx.fillEllipse(dome.darker(0.2), 1, R(3.42 + cos(a) * 0.5 - 0.06, 2.95 + sin(a) * 0.4 - 0.06, 0.12, 0.12))
                            }
                        })
        case .dilophosaurus:
            let c = RGB(0xE05A4C), crest = RGB(0xF6C445)
            return Plan(size: CGSize(width: 5.6, height: 3.8), biped: true, color: c, belly: RGB(0xF8DACB), spot: RGB(0xC2443A),
                        body: R(1.7, 1.55, 2.0, 1.15), tail: [P(1.8, 2.2), P(1.0, 2.15), P(0.15, 1.9)], tailW: [0.75, 0.4, 0.1],
                        neck: [P(3.5, 2.4), P(3.9, 2.88)], neckW: [0.62, 0.46],
                        head: R(3.7, 2.68, 1.25, 0.56), headCorner: 0.25, eye: P(4.15, 3.02), eyeR: 0.13,
                        smile: (P(4.4, 2.82), P(4.9, 2.86)), hip: P(2.5, 1.65), legW: 0.38,
                        arm: P(3.35, 2.05), armLen: 0.45, stride: 0.45, bob: 0.09,
                        headBehind: { ctx, _ in
                            for (cx, rx) in [(4.05, 0.42), (4.45, 0.34)] as [(CGFloat, CGFloat)] {
                                let path = CGMutablePath()
                                path.addArc(center: P(cx, 3.12), radius: rx, startAngle: 0.15, endAngle: .pi - 0.15, clockwise: false)
                                path.closeSubpath()
                                outlined(ctx, [path], crest, c.darker(0.5), 0.035)
                                ctx.strokeLine(crest.darker(0.2), 1, width: 0.04, [P(cx - rx * 0.5, 3.2), P(cx - rx * 0.3, 3.12 + rx * 0.7)])
                                ctx.strokeLine(crest.darker(0.2), 1, width: 0.04, [P(cx + rx * 0.1, 3.2), P(cx + rx * 0.2, 3.12 + rx * 0.75)])
                            }
                        })
        case .gallimimus:
            let c = RGB(0xB07A52)
            return Plan(size: CGSize(width: 4.4, height: 3.8), biped: true, color: c, belly: RGB(0xF4E4CC), spot: RGB(0x946140),
                        body: R(1.2, 2.0, 1.55, 0.95), tail: [P(1.3, 2.55), P(0.7, 2.62), P(0.1, 2.52)], tailW: [0.6, 0.3, 0.08],
                        neck: [P(2.55, 2.75), P(2.95, 3.32)], neckW: [0.4, 0.28],
                        head: R(2.8, 3.2, 0.78, 0.4), headCorner: 0.19, eye: P(3.08, 3.46), eyeR: 0.1,
                        smile: (P(3.25, 3.28), P(3.55, 3.32)), hip: P(1.9, 2.2), legW: 0.28,
                        arm: P(2.45, 2.4), armLen: 0.42, stride: 0.5, bob: 0.08,
                        bodyFront: { ctx, _ in
                            ctx.saveGState()
                            ctx.addPath(ellipse(R(1.2, 2.0, 1.55, 0.95))); ctx.clip()
                            for k in 0..<4 {
                                let x = 1.45 + CGFloat(k) * 0.32
                                ctx.strokeLine(RGB(0xF4E4CC), 0.7, width: 0.08, [P(x, 2.95), P(x - 0.1, 2.55)])
                            }
                            ctx.restoreGState()
                        })
        }
    }

    // MARK: Flying and swimming

    /// Pteranodon flap cycle (side view, facing right), anchor at the middle.
    static func pteranodon(ppm: CGFloat) -> DinoArt {
        let size = CGSize(width: 3.8, height: 3.2)
        let c = RGB(0xE59A5A), wing = RGB(0xF2B97A), line = RGB(0xE59A5A).darker(0.5)
        let frames = (0..<6).map { i -> SKTexture in
            let ph = CGFloat(i) / 6 * .pi * 2
            let up = sin(ph)
            return Painter.texture(CGSize(width: size.width * ppm, height: size.height * ppm)) { ctx in
                ctx.scaleBy(x: ppm, y: ppm)
                ctx.setLineCap(.round); ctx.setLineJoin(.round)
                func wingPath(_ k: CGFloat, _ dx: CGFloat) -> CGPath {
                    let tip = P(1.55 + dx, 1.6 + 1.35 * k)
                    let p = CGMutablePath()
                    p.move(to: P(1.4 + dx, 1.62))
                    p.addQuadCurve(to: tip, control: P(1.2 + dx, 1.6 + 0.9 * k))
                    p.addQuadCurve(to: P(2.25 + dx, 1.6), control: P(2.1 + dx, 1.6 + 0.5 * k))
                    p.closeSubpath()
                    return p
                }
                outlined(ctx, [wingPath(up * 0.9, 0.2)], wing.darker(0.15), line)
                outlined(ctx, [ellipse(P(1.85, 1.6), 0.7, 0.24), tube([P(0.9, 1.62), P(1.3, 1.6)], [0.08, 0.18]),
                               tube([P(2.4, 1.68), P(2.75, 1.78)], [0.3, 0.26]),
                               CGPath.poly([P(2.7, 1.88), P(3.75, 1.66), P(2.72, 1.64)]),
                               tube([P(2.85, 1.9), P(2.35, 2.12)], [0.16, 0.05])], c, line)
                outlined(ctx, [wingPath(up, 0)], wing, line)
                ctx.fillEllipse(.white, 1, R(2.82, 1.76, 0.13, 0.14))
                ctx.fillEllipse(RGB(0x1E1A1A), 1, R(2.86, 1.77, 0.08, 0.1))
            }
        }
        return DinoArt(frames: frames, size: CGSize(width: size.width * ppm, height: size.height * ppm), anchor: P(0.5, 0.5), cycle: 0)
    }

    /// A plesiosaur swimming with its head up; anchor on the waterline.
    static func plesiosaur(ppm: CGFloat) -> DinoArt {
        let size = CGSize(width: 5.0, height: 3.1), water: CGFloat = 0.6
        let c = RGB(0x7A86D8), line = c.darker(0.5)
        let frames = (0..<4).map { i -> SKTexture in
            let sway = sin(CGFloat(i) / 4 * .pi * 2) * 0.1
            return Painter.texture(CGSize(width: size.width * ppm, height: size.height * ppm)) { ctx in
                ctx.scaleBy(x: ppm, y: ppm)
                ctx.setLineCap(.round); ctx.setLineJoin(.round)
                ctx.saveGState()
                ctx.clip(to: R(0, water, size.width, size.height))
                outlined(ctx, [ellipse(P(1.9, water), 1.3, 0.42), tube([P(0.7, water + 0.05), P(0.1, water)], [0.3, 0.05]),
                               tube([P(2.6, water + 0.15), P(3.45 + sway, 1.6), P(3.75 + sway, 2.45)], [0.62, 0.42, 0.36]),
                               CGPath(roundedRect: R(3.55 + sway, 2.3, 0.95, 0.5), cornerWidth: 0.24, cornerHeight: 0.24, transform: nil)], c, line)
                for k in 0..<4 { ctx.fillEllipse(c.darker(0.15), 1, R(1.2 + CGFloat(k) * 0.4, water + 0.12, 0.2, 0.14)) }
                ctx.fillEllipse(RGB(0xF08A8A), 0.35, R(3.95 + sway, 2.35, 0.25, 0.13))
                outlined(ctx, [ellipse(P(3.92 + sway, 2.62), 0.12, 0.13)], .white, line, 0.025)
                ctx.fillEllipse(RGB(0x1E1A1A), 1, R(3.89 + sway, 2.56, 0.13, 0.15))
                ctx.fillEllipse(.white, 1, R(3.93 + sway, 2.64, 0.05, 0.05))
                let sm = CGMutablePath(); sm.move(to: P(4.1 + sway, 2.45)); sm.addQuadCurve(to: P(4.42 + sway, 2.48), control: P(4.26 + sway, 2.38))
                ctx.addPath(sm); ctx.setStrokeColor(line.cg()); ctx.setLineWidth(0.05); ctx.strokePath()
                ctx.restoreGState()
                for k in 0..<3 {  // ripples where the body meets the water
                    let w = 1.1 + CGFloat(k) * 0.6
                    ctx.strokeLine(.white, 0.55 - Double(k) * 0.15, width: 0.06, [P(1.9 - w, water - 0.02 - CGFloat(k) * 0.05), P(1.9 - w * 0.6, water - 0.02 - CGFloat(k) * 0.05)])
                    ctx.strokeLine(.white, 0.55 - Double(k) * 0.15, width: 0.06, [P(2.2 + w * 0.6, water - 0.02 - CGFloat(k) * 0.05), P(2.2 + w, water - 0.02 - CGFloat(k) * 0.05)])
                }
            }
        }
        return DinoArt(frames: frames, size: CGSize(width: size.width * ppm, height: size.height * ppm), anchor: P(0.5, water / size.height), cycle: 0)
    }
}
