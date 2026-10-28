import AppKit
import SpriteKit

struct VehicleArt {
    enum Kind: CaseIterable { case rickshaw, cng, car, bus, localBus }
    var kind: Kind
    var body: SKTexture
    var lights: SKTexture?
    var size: CGSize                         // points
    var wheels: [(CGPoint, CGFloat)]         // centre, radius (points)
    var wheel: SKTexture
    var wheelBack: SKTexture?                // rickshaws have a second, offset wheel
    var head: CGPoint, tail: CGPoint
    var speed: ClosedRange<CGFloat>          // metres / second
    var rider: [SKTexture] = []              // pedalling-leg frames, overlaid on the body
}

struct PropArt {
    var texture: SKTexture
    var size: CGSize
    var anchor: CGPoint = P(0.5, 0)
    var points: [CGPoint] = []               // lamp heads etc.
}

/// Foreground props drawn in colour, in metres scaled by `ppm` (points per metre).
enum ArtProps {
    static let skin = [RGB(0x8A5A3C), RGB(0x6E4630), RGB(0x9C6A48)]
    static let shirts = [RGB(0xE9E4DA), RGB(0x8FB3D1), RGB(0xD38B4A), RGB(0x6F8F6A), RGB(0xC9C1A8), RGB(0xB85A5A)]
    static let lungis = [RGB(0x2F4F7A), RGB(0x3D6B4A), RGB(0x6B4A3A), RGB(0x4A3F6B), RGB(0x7A3A3A)]

    private static func metres(_ size: CGSize, _ ppm: CGFloat, _ draw: (CGContext) -> Void) -> CGImage {
        Painter.image(CGSize(width: size.width * ppm, height: size.height * ppm)) { ctx in
            ctx.scaleBy(x: ppm, y: ppm)
            ctx.setLineJoin(.round); ctx.setLineCap(.round)
            draw(ctx)
        }
    }

    static func wheel(radius r: CGFloat, ppm: CGFloat, spokes: Int, rim: RGB = RGB(0xB7B9BE)) -> SKTexture {
        let d = r * 2
        return Painter.texture(metres(CGSize(width: d, height: d), ppm) { ctx in
            let c = P(r, r)
            ctx.fillEllipse(RGB(0x1D1D21), 1, R(0, 0, d, d))
            if spokes > 8 {
                ctx.fillEllipse(RGB(0x2A2A2F), 1, R(r * 0.14, r * 0.14, d - r * 0.28, d - r * 0.28))
                ctx.setStrokeColor(rim.cg(0.85)); ctx.setLineWidth(0.012)
                for i in 0..<spokes {
                    let a = CGFloat(i) / CGFloat(spokes) * .pi * 2
                    ctx.move(to: c); ctx.addLine(to: P(c.x + cos(a) * r * 0.86, c.y + sin(a) * r * 0.86))
                }
                ctx.strokePath()
                ctx.setStrokeColor(rim.cg()); ctx.setLineWidth(0.03); ctx.strokeEllipse(in: R(r * 0.14, r * 0.14, d - r * 0.28, d - r * 0.28))
            } else {
                ctx.fillEllipse(rim, 1, R(r * 0.42, r * 0.42, r * 1.16, r * 1.16))
                for i in 0..<spokes {
                    let a = CGFloat(i) / CGFloat(spokes) * .pi * 2
                    ctx.fillEllipse(RGB(0x4A4C52), 1, R(c.x + cos(a) * r * 0.36 - r * 0.08, c.y + sin(a) * r * 0.36 - r * 0.08, r * 0.16, r * 0.16))
                }
            }
            ctx.fillEllipse(RGB(0x55575D), 1, R(r * 0.86, r * 0.86, r * 0.28, r * 0.28))
        })
    }

    static func vehicle(_ kind: VehicleArt.Kind, ppm: CGFloat, rng: inout SeededRNG) -> VehicleArt {
        switch kind {
        case .rickshaw: return rickshaw(ppm: ppm, rng: &rng)
        case .cng: return cng(ppm: ppm, rng: &rng)
        case .car: return car(ppm: ppm, rng: &rng)
        case .bus: return bus(ppm: ppm, rng: &rng, doubleDecker: true)
        case .localBus: return bus(ppm: ppm, rng: &rng, doubleDecker: false)
        }
    }

    // MARK: Rickshaw: the soul of Dhaka's streets.

    static func rickshaw(ppm: CGFloat, rng: inout SeededRNG) -> VehicleArt {
        let size = CGSize(width: 2.45, height: 2.05)
        let hoodC = rng.pick([RGB(0xC23B3B), RGB(0x2E6FA8), RGB(0x2F8A5A), RGB(0xD06A2C), RGB(0x8A3A8F), RGB(0x1F4E79)])
        let boxC = rng.pick([RGB(0x2F5D8C), RGB(0xB8322E), RGB(0x2E7D4F), RGB(0x6C3483), RGB(0x1E8A8A)])
        let trimC = rng.pick([RGB(0xE8C547), RGB(0xF2F2F2), RGB(0xE7A13A)])
        let skinC = rng.pick(skin), shirt = rng.pick(shirts), lungi = rng.pick(lungis)
        let passenger = rng.chance(0.6)
        let pShirt = rng.pick(shirts + [RGB(0xC8426B), RGB(0x7B4BA0), RGB(0xE07A3A)])
        let metal = RGB(0x2E2E33)

        let img = metres(size, ppm) { ctx in
            // Frame.
            ctx.strokeLine(metal, 1, width: 0.05, [P(0.62, 0.34), P(1.48, 0.45), P(1.95, 0.98), P(2.05, 0.3)])
            ctx.strokeLine(metal, 1, width: 0.05, [P(1.48, 0.45), P(1.36, 1.0)])
            ctx.strokeLine(metal, 1, width: 0.045, [P(1.36, 0.98), P(1.95, 0.98)])
            ctx.strokeLine(metal, 1, width: 0.04, [P(1.95, 0.98), P(1.9, 1.14), P(1.76, 1.14)])
            ctx.fillEllipse(metal, 1, R(1.25, 0.95, 0.24, 0.09))  // saddle
            // Passenger box with painted panel.
            ctx.addPath(CGPath(roundedRect: R(0.18, 0.52, 0.9, 0.4), cornerWidth: 0.06, cornerHeight: 0.06, transform: nil))
            ctx.setFillColor(boxC.cg()); ctx.fillPath()
            ctx.fill(trimC, 1, R(0.18, 0.68, 0.9, 0.05))
            for i in 0..<6 { ctx.fillEllipse(trimC.lighter(0.3), 1, R(0.24 + CGFloat(i) * 0.14, 0.57, 0.07, 0.07)) }
            ctx.fill(RGB(0x8B2F3A), 1, R(0.22, 0.92, 0.8, 0.1))  // cushion
            ctx.strokeLine(metal, 1, width: 0.035, [P(1.0, 0.55), P(1.3, 0.55)])  // footboard
            // Rear mudguard.
            let mg = CGMutablePath()
            mg.addArc(center: P(0.62, 0.34), radius: 0.41, startAngle: .pi * 0.12, endAngle: .pi * 0.92, clockwise: false)
            ctx.setStrokeColor(hoodC.cg()); ctx.setLineWidth(0.07); ctx.addPath(mg); ctx.strokePath()

            if passenger {
                ctx.fill(pShirt, 1, R(0.42, 1.0, 0.38, 0.36))
                ctx.fillEllipse(rng.pick(skin), 1, R(0.5, 1.33, 0.22, 0.24))
                ctx.fillEllipse(RGB(0x1C1A1A), 1, R(0.48, 1.45, 0.24, 0.14))
                ctx.fill(pShirt.darker(0.15), 1, R(0.68, 0.86, 0.34, 0.16))  // knees
            }
            // Folding hood with folds and a bright trim.
            let hood = CGMutablePath()
            hood.move(to: P(0.12, 1.0))
            hood.addQuadCurve(to: P(0.42, 1.98), control: P(0.02, 1.86))
            hood.addQuadCurve(to: P(1.12, 1.6), control: P(0.95, 2.04))
            hood.addLine(to: P(1.0, 1.52))
            hood.addQuadCurve(to: P(0.42, 1.82), control: P(0.86, 1.88))
            hood.addQuadCurve(to: P(0.3, 1.0), control: P(0.18, 1.6))
            hood.closeSubpath()
            ctx.fillPath(hoodC, 1, hood)
            ctx.saveGState(); ctx.addPath(hood); ctx.clip()
            for i in 1...3 {
                let f = CGMutablePath()
                let k = CGFloat(i) * 0.12
                f.move(to: P(0.12 + k, 1.0)); f.addQuadCurve(to: P(0.42 + k * 0.6, 1.98 - k * 0.3), control: P(0.02 + k, 1.86 - k * 0.2))
                ctx.setStrokeColor(hoodC.darker(0.3).cg()); ctx.setLineWidth(0.03); ctx.addPath(f); ctx.strokePath()
            }
            ctx.restoreGState()
            ctx.strokeLine(trimC, 1, width: 0.05, [P(1.0, 1.52), P(1.12, 1.6)])
            ctx.fill(trimC, 1, R(0.12, 0.98, 0.2, 0.05))

            // Rickshawala.
            ctx.fillPath(shirt, 1, CGPath.poly([P(1.28, 1.02), P(1.48, 1.06), P(1.68, 1.5), P(1.5, 1.58), P(1.32, 1.3)]))
            ctx.strokeLine(skinC, 1, width: 0.06, [P(1.62, 1.44), P(1.74, 1.24), P(1.84, 1.14)])
            ctx.fillEllipse(skinC, 1, R(1.58, 1.56, 0.2, 0.22))
            ctx.fillEllipse(rng.pick([RGB(0xE9E4DA), RGB(0xB8322E), RGB(0x2F5D8C)]), 1, R(1.57, 1.69, 0.22, 0.08))  // gamchha
            ctx.fillEllipse(metal, 1, R(1.42, 0.39, 0.12, 0.12))  // chainring
        }
        let frames = (0..<8).map { i in
            Painter.texture(metres(size, ppm) { ctx in pedalLegs(ctx, angle: CGFloat(i) / 8 * .pi * 2, skin: skinC, lungi: lungi) })
        }
        let k = ppm
        return VehicleArt(kind: .rickshaw, body: Painter.texture(img), lights: nil,
                          size: CGSize(width: size.width * k, height: size.height * k),
                          wheels: [(P(0.62 * k, 0.34 * k), 0.34 * k), (P(2.05 * k, 0.3 * k), 0.3 * k)],
                          wheel: wheel(radius: 0.34, ppm: ppm, spokes: 20), wheelBack: wheel(radius: 0.3, ppm: ppm, spokes: 18),
                          head: P(1.96 * k, 1.0 * k), tail: P(0.18 * k, 0.75 * k), speed: 2.2...3.4, rider: frames)
    }

    /// Two legs on a crank, solved with simple two-bone IK; the far leg is half a turn behind and in shadow.
    private static func pedalLegs(_ ctx: CGContext, angle a: CGFloat, skin: RGB, lungi: RGB) {
        let hip = P(1.38, 1.0), crank = P(1.48, 0.45), r: CGFloat = 0.16
        let thigh: CGFloat = 0.5, shin: CGFloat = 0.5
        func leg(_ ang: CGFloat, shade: CGFloat) {
            let foot = P(crank.x + cos(ang) * r, crank.y + sin(ang) * r)
            let dx = foot.x - hip.x, dy = foot.y - hip.y
            let d = min(thigh + shin - 0.01, hypot(dx, dy))
            let base = atan2(dy, dx)
            let bend = acos(max(-1, min(1, (thigh * thigh + d * d - shin * shin) / (2 * thigh * d))))
            let knee = P(hip.x + cos(base + bend) * thigh, hip.y + sin(base + bend) * thigh)  // knee forward
            ctx.strokeLine(metal(shade), 1, width: 0.03, [crank, foot])
            ctx.strokeLine(skin.darker(shade), 1, width: 0.065, [knee, foot])
            ctx.fillEllipse(RGB(0x2A2420).darker(shade), 1, R(foot.x - 0.06, foot.y - 0.03, 0.14, 0.06))
            ctx.strokeLine(lungi.darker(shade), 1, width: 0.2, [P(hip.x - 0.04, hip.y + 0.02), knee])
            ctx.fillEllipse(lungi.darker(shade), 1, R(knee.x - 0.1, knee.y - 0.1, 0.2, 0.18))
        }
        func metal(_ shade: CGFloat) -> RGB { RGB(0x2E2E33).darker(shade) }
        leg(a + .pi, shade: 0.3)
        leg(a, shade: 0)
    }

    // MARK: Pedestrians: walk cycle, with umbrellas when it rains.

    static func walker(ppm: CGFloat, rng: inout SeededRNG, umbrella: Bool) -> ([SKTexture], CGSize) {
        let size = CGSize(width: 1.1, height: umbrella ? 2.3 : 1.85)
        let woman = rng.chance(0.45)
        let skinC = rng.pick(skin)
        let top = woman ? rng.pick([RGB(0xC8426B), RGB(0x7B4BA0), RGB(0xE07A3A), RGB(0x2E8A7A), RGB(0xD9B23A)]) : rng.pick(shirts)
        let bottom = woman ? top.darker(0.15) : rng.pick(lungis + [RGB(0x3A3F4A), RGB(0x5A4A3A)])
        let scarf = woman ? rng.pick([RGB(0xF2E6D8), RGB(0xE7A13A), RGB(0x2F5D8C), RGB(0xB8322E)]) : nil
        let umb = rng.pick([RGB(0x1E1E24), RGB(0x1E1E24), RGB(0x2F5D8C), RGB(0xB8322E), RGB(0x2E7D4F), RGB(0x6C3483)])
        let longSkirt = woman || rng.chance(0.4)  // saree / lungi
        let frames = (0..<8).map { i -> SKTexture in
            let ph = CGFloat(i) / 8 * .pi * 2
            return Painter.texture(metres(size, ppm) { ctx in
                let cx: CGFloat = 0.5, hip = P(cx, 0.88)
                let swing = sin(ph) * 0.4
                let bob = abs(cos(ph)) * 0.02
                func legFoot(_ s: CGFloat) -> CGPoint { P(hip.x + sin(s) * 0.86, max(0.02, hip.y - cos(s) * 0.86)) }
                for (s, shade) in [(-swing, 0.25), (swing, 0.0)] as [(CGFloat, CGFloat)] {
                    let f = legFoot(s)
                    ctx.strokeLine((longSkirt ? skinC : bottom).darker(shade), 1, width: longSkirt ? 0.07 : 0.13, [P(hip.x, hip.y + bob), f])
                    ctx.fillEllipse(RGB(0x2A2420).darker(shade), 1, R(f.x - 0.05, f.y - 0.03, 0.15, 0.06))
                }
                if longSkirt {
                    let spread = abs(sin(ph)) * 0.12
                    ctx.fillPath(bottom, 1, CGPath.poly([P(cx - 0.17, hip.y + 0.05 + bob), P(cx + 0.17, hip.y + 0.05 + bob),
                                                         P(cx + 0.2 + spread, 0.16), P(cx - 0.2 - spread, 0.16)]))
                }
                // Torso, far arm, head.
                let sh = P(cx + 0.03, 1.42 + bob)
                ctx.strokeLine(top.darker(0.25), 1, width: 0.08, [P(sh.x, sh.y - 0.05), P(sh.x + sin(swing) * 0.3, sh.y - 0.5)])
                ctx.addPath(CGPath(roundedRect: R(cx - 0.15, hip.y - 0.02 + bob, 0.32, 0.58), cornerWidth: 0.1, cornerHeight: 0.1, transform: nil))
                ctx.setFillColor(top.cg()); ctx.fillPath()
                let head = P(cx + 0.05, 1.56 + bob)
                ctx.fillEllipse(skinC, 1, R(head.x - 0.1, head.y - 0.1, 0.21, 0.24))
                ctx.fillEllipse(RGB(0x1C1A1A), 1, R(head.x - 0.12, head.y + 0.03, 0.22, 0.13))
                if let scarf {
                    ctx.fillPath(scarf, 1, CGPath.poly([P(cx - 0.17, 1.4 + bob), P(cx + 0.18, 1.44 + bob), P(cx + 0.02, 1.0 + bob), P(cx - 0.2, 1.05 + bob)]))
                }
                if umbrella {
                    let hand = P(cx + 0.12, 1.42 + bob)
                    ctx.strokeLine(top, 1, width: 0.08, [P(sh.x, sh.y - 0.05), P(cx + 0.2, 1.2 + bob), hand])
                    ctx.strokeLine(RGB(0x2A2A2A), 1, width: 0.025, [P(hand.x, hand.y - 0.05), P(hand.x - 0.02, 2.08 + bob)])
                    let canopy = CGMutablePath()
                    let c = P(hand.x - 0.02, 1.9 + bob)
                    canopy.move(to: P(c.x - 0.52, c.y))
                    canopy.addQuadCurve(to: P(c.x + 0.52, c.y), control: P(c.x, c.y + 0.5))
                    for k in 0..<4 {  // scalloped rim
                        let x0 = c.x + 0.52 - CGFloat(k) * 0.26
                        canopy.addQuadCurve(to: P(x0 - 0.26, c.y), control: P(x0 - 0.13, c.y + 0.07))
                    }
                    ctx.fillPath(umb, 1, canopy)
                    ctx.strokeLine(umb.lighter(0.25), 0.6, width: 0.015, [P(c.x, c.y + 0.25), P(c.x - 0.2, c.y + 0.02)])
                    ctx.strokeLine(umb.lighter(0.25), 0.6, width: 0.015, [P(c.x, c.y + 0.25), P(c.x + 0.2, c.y + 0.02)])
                } else {
                    ctx.strokeLine(top, 1, width: 0.08, [P(sh.x, sh.y - 0.05), P(sh.x - sin(swing) * 0.3, sh.y - 0.5)])
                    ctx.fillEllipse(skinC, 1, R(sh.x - sin(swing) * 0.3 - 0.04, sh.y - 0.56, 0.08, 0.08))
                }
            })
        }
        return (frames, CGSize(width: size.width * ppm, height: size.height * ppm))
    }

    // MARK: CNG auto-rickshaw.

    static func cng(ppm: CGFloat, rng: inout SeededRNG) -> VehicleArt {
        let size = CGSize(width: 2.65, height: 1.78)
        let green = rng.chance(0.85) ? RGB(0x3E8B57) : RGB(0x4A4F57)
        let img = metres(size, ppm) { ctx in
            let lower = CGMutablePath()
            lower.move(to: P(0.08, 0.3)); lower.addLine(to: P(2.45, 0.3))
            lower.addQuadCurve(to: P(2.6, 0.95), control: P(2.66, 0.5))
            lower.addLine(to: P(0.12, 0.95)); lower.closeSubpath()
            ctx.fillPath(green, 1, lower)
            let cabin = CGMutablePath()
            cabin.move(to: P(0.14, 0.92))
            cabin.addLine(to: P(0.2, 1.48))
            cabin.addQuadCurve(to: P(0.62, 1.74), control: P(0.24, 1.72))
            cabin.addLine(to: P(1.95, 1.74))
            cabin.addQuadCurve(to: P(2.4, 1.5), control: P(2.32, 1.72))
            cabin.addLine(to: P(2.56, 0.95))
            cabin.closeSubpath()
            ctx.fillPath(green.lighter(0.06), 1, cabin)
            ctx.fill(RGB(0x24563A), 1, R(0.3, 1.58, 1.8, 0.16))
            // Caged passenger window, open driver bay, windscreen.
            ctx.addPath(CGPath(roundedRect: R(0.36, 0.98, 1.2, 0.54), cornerWidth: 0.08, cornerHeight: 0.08, transform: nil))
            ctx.setFillColor(RGB(0x16211B).cg(0.92)); ctx.fillPath()
            var gx: CGFloat = 0.42
            while gx < 1.52 { ctx.fill(green.lighter(0.15), 1, R(gx, 0.98, 0.025, 0.54)); gx += 0.085 }
            ctx.addPath(CGPath(roundedRect: R(1.66, 0.98, 0.56, 0.54), cornerWidth: 0.08, cornerHeight: 0.08, transform: nil))
            ctx.setFillColor(RGB(0x16211B).cg(0.92)); ctx.fillPath()
            ctx.fillEllipse(rng.pick(skin), 1, R(1.86, 1.2, 0.2, 0.22))
            ctx.fillPath(RGB(0xA9CBDD), 0.7, CGPath.poly([P(2.3, 1.0), P(2.48, 1.0), P(2.36, 1.48), P(2.26, 1.48)]))
            ctx.fill(RGB(0xF2F0E6), 0.9, R(0.12, 0.9, 2.44, 0.035))
            ctx.fill(RGB(0xE9E2C8), 1, R(2.15, 0.42, 0.28, 0.14))  // plate
            ctx.fillEllipse(RGB(0xF3EFD9), 1, R(2.5, 0.66, 0.1, 0.12))
        }
        let k = ppm
        return VehicleArt(kind: .cng, body: Painter.texture(img), lights: nil,
                          size: CGSize(width: size.width * k, height: size.height * k),
                          wheels: [(P(0.6 * k, 0.26 * k), 0.26 * k), (P(2.25 * k, 0.24 * k), 0.24 * k)],
                          wheel: wheel(radius: 0.26, ppm: ppm, spokes: 5), wheelBack: nil,
                          head: P(2.6 * k, 0.72 * k), tail: P(0.1 * k, 0.62 * k), speed: 4.5...6.5)
    }

    // MARK: Car.

    static func car(ppm: CGFloat, rng: inout SeededRNG) -> VehicleArt {
        let size = CGSize(width: 4.4, height: 1.45)
        let paint = rng.pick([RGB(0xE8E8E6), RGB(0xB9BDC2), RGB(0x3A3F48), RGB(0x8E2A2A), RGB(0x2C4A6E), RGB(0xE8E8E6)])
        let img = metres(size, ppm) { ctx in
            for wx in [0.95, 3.45] as [CGFloat] { ctx.fillEllipse(RGB(0x18181B), 1, R(wx - 0.4, -0.05, 0.8, 0.8)) }
            let b = CGMutablePath()
            b.move(to: P(0.1, 0.32)); b.addLine(to: P(0.06, 0.74))
            b.addQuadCurve(to: P(0.7, 0.86), control: P(0.2, 0.86))
            b.addQuadCurve(to: P(1.45, 1.36), control: P(1.1, 1.3))
            b.addLine(to: P(2.85, 1.4))
            b.addQuadCurve(to: P(3.6, 0.92), control: P(3.3, 1.34))
            b.addQuadCurve(to: P(4.36, 0.78), control: P(4.25, 0.9))
            b.addLine(to: P(4.38, 0.36)); b.closeSubpath()
            ctx.fillPath(paint, 1, b)
            ctx.saveGState(); ctx.addPath(b); ctx.clip()
            ctx.fill(paint.darker(0.18), 1, R(0, 0.3, 4.4, 0.18))
            ctx.fill(paint.lighter(0.25), 0.8, R(0, 0.8, 4.4, 0.04))
            for wx in [0.95, 3.45] as [CGFloat] { ctx.fillEllipse(RGB(0x18181B), 1, R(wx - 0.4, -0.08, 0.8, 0.8)) }
            ctx.restoreGState()
            let win = CGPath.poly([P(1.42, 0.9), P(1.58, 1.3), P(2.82, 1.33), P(3.36, 0.9)])
            ctx.fillPath(RGB(0x2D3A4A), 1, win)
            ctx.fill(paint, 1, R(2.3, 0.9, 0.07, 0.44))
            ctx.fillPath(RGB(0x9FB4C8), 0.25, CGPath.poly([P(1.7, 0.95), P(1.85, 1.28), P(2.0, 1.28), P(1.85, 0.95)]))
            ctx.fillEllipse(RGB(0xF4F1E2), 1, R(4.22, 0.62, 0.14, 0.12))
            ctx.fill(RGB(0xB3302C), 1, R(0.06, 0.62, 0.1, 0.12))
        }
        let k = ppm
        return VehicleArt(kind: .car, body: Painter.texture(img), lights: nil,
                          size: CGSize(width: size.width * k, height: size.height * k),
                          wheels: [(P(0.95 * k, 0.33 * k), 0.33 * k), (P(3.45 * k, 0.33 * k), 0.33 * k)],
                          wheel: wheel(radius: 0.33, ppm: ppm, spokes: 5), wheelBack: nil,
                          head: P(4.36 * k, 0.68 * k), tail: P(0.06 * k, 0.68 * k), speed: 5.5...8)
    }

    // MARK: Buses: red BRTC double-decker, or a colourful local bus.

    static func bus(ppm: CGFloat, rng: inout SeededRNG, doubleDecker dd: Bool) -> VehicleArt {
        let size = CGSize(width: dd ? 10.5 : 9.2, height: dd ? 4.3 : 3.15)
        let paint = dd ? RGB(0xB03A35) : rng.pick([RGB(0x2D6FA3), RGB(0x2E7D4F), RGB(0xE6E2D8), RGB(0x6A3E8E)])
        let stripe = dd ? RGB(0xE9DFC8) : rng.pick([RGB(0xD94A3A), RGB(0xF0B53A), RGB(0x3AA0D9)])
        let glassC = RGB(0x2B3540)
        let L = size.width
        let lights = Painter.context(CGSize(width: size.width * ppm, height: size.height * ppm))
        lights.scaleBy(x: ppm, y: ppm)
        var rng2 = rng
        let img = metres(size, ppm) { ctx in
            for wx in [2.0, L - 2.1] { ctx.fillEllipse(RGB(0x18181B), 1, R(wx - 0.6, -0.1, 1.2, 1.2)) }
            let body = CGPath(roundedRect: R(0.08, 0.32, L - 0.16, size.height - 0.36), cornerWidth: 0.35, cornerHeight: 0.35, transform: nil)
            ctx.fillPath(paint, 1, body)
            ctx.saveGState(); ctx.addPath(body); ctx.clip()
            for wx in [2.0, L - 2.1] { ctx.fillEllipse(RGB(0x18181B), 1, R(wx - 0.62, -0.14, 1.24, 1.24)) }
            ctx.fill(paint.darker(0.2), 1, R(0, 0.32, L, 0.3))
            ctx.restoreGState()
            let decks: [(CGFloat, CGFloat)] = dd ? [(1.15, 0.8), (2.5, 1.25)] : [(1.4, 1.0)]
            ctx.fill(stripe, 1, R(0.08, dd ? 2.05 : 1.1, L - 0.16, 0.22))
            if !dd { ctx.fill(stripe.darker(0.1), 1, R(0.08, 0.75, L - 0.16, 0.12)) }
            for (wy, wh) in decks {
                var wx: CGFloat = 0.55
                while wx < L - 1.6 {
                    if !(wx > L - 2.0 && wy < 2) {
                        ctx.addPath(CGPath(roundedRect: R(wx, wy, 0.92, wh), cornerWidth: 0.1, cornerHeight: 0.1, transform: nil))
                        ctx.setFillColor(glassC.cg()); ctx.fillPath()
                        if rng2.chance(0.6) {
                            ctx.fillEllipse(RGB(0x151A20), 1, R(wx + 0.3, wy + wh * 0.3, 0.3, 0.34))
                            ctx.fill(RGB(0x151A20), 1, R(wx + 0.22, wy, 0.46, wh * 0.38))
                        }
                        lights.fill(RGB(0xEAF4FF), 0.55, R(wx, wy, 0.92, wh))
                    }
                    wx += 1.05
                }
                ctx.fill(glassC, 1, R(L - 0.75, wy - 0.05, 0.62, wh + 0.1))
                ctx.fill(RGB(0x9FB4C8), 0.3, R(L - 0.6, wy + wh * 0.4, 0.2, wh * 0.5))
            }
            // Door.
            ctx.fill(RGB(0x1E242B), 1, R(L - 1.55, 0.45, 0.6, dd ? 1.55 : 1.95))
            // Destination sign.
            let signY = size.height - (dd ? 0.38 : 0.42)
            ctx.fill(RGB(0x2A1C10), 1, R(L - 1.6, signY, 1.4, 0.24))
            ctx.fill(RGB(0xFFB347), 0.9, R(L - 1.5, signY + 0.06, 1.2, 0.12))
            lights.fill(RGB(0xFFB347), 0.9, R(L - 1.5, signY + 0.06, 1.2, 0.12))
            ctx.fillEllipse(RGB(0xF4F1E2), 1, R(L - 0.2, 0.7, 0.14, 0.2))
            ctx.fill(RGB(0xB3302C), 1, R(0.08, 0.8, 0.12, 0.3))
        }
        rng = rng2
        let k = ppm
        return VehicleArt(kind: dd ? .bus : .localBus, body: Painter.texture(img), lights: Painter.texture(lights.makeImage()!),
                          size: CGSize(width: size.width * k, height: size.height * k),
                          wheels: [(P(2.0 * k, 0.5 * k), 0.5 * k), (P((L - 2.1) * k, 0.5 * k), 0.5 * k)],
                          wheel: wheel(radius: 0.5, ppm: ppm, spokes: 6), wheelBack: nil,
                          head: P((L - 0.12) * k, 0.8 * k), tail: P(0.1 * k, 0.95 * k), speed: 4...6)
    }

    // MARK: Nouka: wooden country boat with a bamboo canopy.

    static func boat(ppm: CGFloat, rng: inout SeededRNG) -> (PropArt, CGPoint) {
        let size = CGSize(width: 7.6, height: 2.8)
        let wood = rng.pick([RGB(0x4A3628), RGB(0x5A4030), RGB(0x3E2E24)])
        let img = metres(size, ppm) { ctx in
            ctx.strokeLine(RGB(0x3B3028), 1, width: 0.05, [P(0.5, 0.0), P(1.75, 2.75)])  // bamboo pole
            let hull = CGMutablePath()
            hull.move(to: P(0.0, 1.1))
            hull.addQuadCurve(to: P(1.2, 0.12), control: P(0.3, 0.2))
            hull.addLine(to: P(6.2, 0.12))
            hull.addQuadCurve(to: P(7.55, 1.2), control: P(7.25, 0.2))
            hull.addQuadCurve(to: P(6.4, 0.58), control: P(7.0, 0.62))
            hull.addLine(to: P(1.2, 0.58))
            hull.addQuadCurve(to: P(0.0, 1.1), control: P(0.4, 0.62))
            hull.closeSubpath()
            ctx.fillPath(wood, 1, hull)
            ctx.saveGState(); ctx.addPath(hull); ctx.clip()
            ctx.fill(wood.lighter(0.2), 1, R(0, 0.46, 7.6, 0.1))
            ctx.fill(wood.darker(0.25), 1, R(0, 0.1, 7.6, 0.14))
            ctx.restoreGState()
            // Chhoi canopy.
            let canopy = CGMutablePath()
            canopy.addArc(center: P(3.7, 0.56), radius: 1.0, startAngle: 0, endAngle: .pi, clockwise: false)
            canopy.closeSubpath()
            ctx.saveGState(); ctx.scaleBy(x: 1.15, y: 1.0); ctx.translateBy(x: -0.48, y: 0)
            ctx.fillPath(RGB(0x9A8458), 1, canopy)
            ctx.addPath(canopy); ctx.clip()
            var y: CGFloat = 0.62
            while y < 1.6 { ctx.fill(RGB(0x7A6640), 1, R(2.6, y, 2.2, 0.03)); y += 0.12 }
            ctx.restoreGState()
            ctx.fillEllipse(RGB(0x2A2218), 1, R(4.55, 0.6, 0.35, 0.75))
            // Boatman.
            let s = rng.pick(skin)
            ctx.fillPath(rng.pick(lungis), 1, CGPath.poly([P(1.0, 0.58), P(1.42, 0.58), P(1.36, 1.25), P(1.06, 1.25)]))
            ctx.fillPath(rng.pick(shirts), 1, CGPath.poly([P(1.04, 1.22), P(1.4, 1.22), P(1.36, 1.78), P(1.08, 1.78)]))
            ctx.strokeLine(s, 1, width: 0.07, [P(1.32, 1.7), P(1.52, 1.5), P(1.6, 1.92)])
            ctx.fillEllipse(s, 1, R(1.1, 1.78, 0.24, 0.26))
            ctx.fillEllipse(RGB(0xC9A35A), 1, R(1.02, 1.94, 0.4, 0.1))  // straw hat brim
        }
        return (PropArt(texture: Painter.texture(img), size: CGSize(width: size.width * ppm, height: size.height * ppm)),
                P(4.9 * ppm, 1.2 * ppm))
    }

    // MARK: Krishnachura (flame tree): umbrella canopy, red blossoms in summer.

    static func krishnachura(width w: CGFloat, height h: CGFloat, bloom: Double, seed: UInt64) -> PropArt {
        var rng = SeededRNG(seed: seed)
        let trunkX = w * 0.24
        let bark = RGB(0x4A3B32), barkLight = RGB(0x6B5646), barkDark = RGB(0x33281F)
        // Muted foliage tones, shadow → highlight, so the tree sits in the same palette as the city.
        let tones = [RGB(0x2D4232), RGB(0x3D5940), RGB(0x55744D), RGB(0x76935F), RGB(0x9DB27A)]
        let reds = [RGB(0xC9483A), RGB(0xD9603E), RGB(0xB83A30), RGB(0xE5844A)]

        struct Lobe { var dx: CGFloat; var dy: CGFloat; var r: CGFloat }
        struct Clump { var c: CGPoint; var rx: CGFloat; var ry: CGFloat; var lobes: [Lobe] }

        // Crown plan: an irregular umbrella of clumps, plus a few higher ones over the middle.
        var clumps: [Clump] = []
        func addClump(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat) {
            let ry = rx * rng.cg(0.5, 0.62)
            let cx = min(max(x, rx * 1.2), w - rx * 1.2)
            let cy = min(y, h - ry * 1.45)
            var lobes = [Lobe(dx: 0, dy: 0.05, r: 0.62)]
            for k in 0..<9 {
                let a = CGFloat(k) / 9 * .pi * 2 + rng.cg(-0.25, 0.25)
                let squash: CGFloat = sin(a) < 0 ? 0.55 : 1  // flatter undersides
                lobes.append(Lobe(dx: cos(a) * rng.cg(0.48, 0.62), dy: sin(a) * rng.cg(0.4, 0.55) * squash, r: rng.cg(0.36, 0.5)))
            }
            clumps.append(Clump(c: P(cx, cy), rx: rx, ry: ry, lobes: lobes))
        }
        // Three overlapping tiers make one continuous umbrella; the rim droops at the ends.
        let tiers: [(count: Int, span: ClosedRange<CGFloat>, y: CGFloat, rise: CGFloat, r: CGFloat)] = [
            (5, 0.3...0.72, 0.84, 0.04, 0.1),
            (8, 0.12...0.9, 0.75, 0.08, 0.1),
            (10, 0.06...0.95, 0.66, 0.07, 0.085),
        ]
        for tier in tiers {
            for i in 0..<tier.count {
                let t = CGFloat(i) / CGFloat(tier.count - 1)
                let dome = sin(t * .pi)
                addClump(w * (tier.span.lowerBound + (tier.span.upperBound - tier.span.lowerBound) * t) + rng.cg(-w * 0.015, w * 0.015),
                         h * (tier.y + tier.rise * dome) - h * 0.03 * pow(abs(t - 0.5) * 2, 3) + rng.cg(-h * 0.012, h * 0.012),
                         w * tier.r * (0.85 + 0.3 * dome) * rng.cg(0.9, 1.1))
            }
        }
        // Back (higher) clumps first, the lower front ones overlap them.
        clumps.sort { $0.c.y > $1.c.y }

        let img = Painter.image(CGSize(width: w, height: h)) { ctx in
            // Tapered limb as a filled shape along a quadratic curve, with a lit edge.
            func limb(_ a: CGPoint, _ b: CGPoint, _ ctrl: CGPoint, _ w0: CGFloat, _ w1: CGFloat) {
                let steps = 18
                var left: [CGPoint] = [], right: [CGPoint] = [], mid: [CGPoint] = []
                for i in 0...steps {
                    let t = CGFloat(i) / CGFloat(steps)
                    let p = P(pow(1 - t, 2) * a.x + 2 * (1 - t) * t * ctrl.x + t * t * b.x,
                              pow(1 - t, 2) * a.y + 2 * (1 - t) * t * ctrl.y + t * t * b.y)
                    let d = P(2 * (1 - t) * (ctrl.x - a.x) + 2 * t * (b.x - ctrl.x), 2 * (1 - t) * (ctrl.y - a.y) + 2 * t * (b.y - ctrl.y))
                    let len = max(0.001, hypot(d.x, d.y))
                    let nrm = P(-d.y / len, d.x / len)
                    let half = (w0 + (w1 - w0) * t) / 2
                    left.append(P(p.x + nrm.x * half, p.y + nrm.y * half))
                    right.append(P(p.x - nrm.x * half, p.y - nrm.y * half))
                    mid.append(P(p.x + nrm.x * half * 0.45, p.y + nrm.y * half * 0.45))
                }
                ctx.fillPath(bark, 1, CGPath.poly(left + right.reversed()))
                ctx.strokeLine(barkLight, 0.7, width: max(0.8, w0 * 0.18), Array(mid.prefix(steps - 3)))
                ctx.strokeLine(barkDark, 0.6, width: max(0.6, w0 * 0.12), Array(right.prefix(steps - 3)))
            }

            // Trunk with a root flare, forking into limbs that end inside the clumps.
            let fork = P(trunkX + w * 0.03, h * 0.5)
            ctx.fillPath(bark, 1, CGPath.poly([P(trunkX - w * 0.06, 0), P(trunkX + w * 0.065, 0), P(trunkX + w * 0.03, h * 0.05), P(trunkX - w * 0.025, h * 0.05)]))
            limb(P(trunkX, 0), fork, P(trunkX - w * 0.025, h * 0.26), w * 0.06, w * 0.042)
            // A few main limbs: rise steeply, then spread out under the canopy (rain-tree habit).
            for fx in [0.05, 0.3, 0.6, 0.88] as [CGFloat] {
                let end = P(w * fx, h * 0.68 + rng.cg(0, h * 0.04))
                let dx = end.x - fork.x, dy = end.y - fork.y
                let ctrl = P(fork.x + dx * 0.2, fork.y + dy * 0.95)
                limb(fork, end, ctrl, w * 0.032, w * 0.01)
                // Secondary branches fanning from partway along, up into the crown.
                for _ in 0..<1 {
                    let t = rng.cg(0.4, 0.6)
                    let start = P(pow(1 - t, 2) * fork.x + 2 * (1 - t) * t * ctrl.x + t * t * end.x,
                                  pow(1 - t, 2) * fork.y + 2 * (1 - t) * t * ctrl.y + t * t * end.y)
                    let side: CGFloat = fx < 0.3 ? -1 : 1
                    let tip = P(start.x + side * w * rng.cg(0.08, 0.14), h * rng.cg(0.7, 0.76))
                    limb(start, tip, P(start.x + (tip.x - start.x) * 0.6, start.y + (tip.y - start.y) * 0.8), w * 0.012, w * 0.004)
                }
            }

            // Foliage: each clump is shaded in layers that step up and toward the light.
            func lobePath(_ cl: Clump, scale s: CGFloat, shift: CGPoint, filter: (Lobe) -> Bool = { _ in true }) -> CGPath {
                let p = CGMutablePath()
                for l in cl.lobes where filter(l) {
                    let r = l.r * cl.ry * s * 1.15
                    let x = cl.c.x + l.dx * cl.rx * s + shift.x * cl.rx
                    let y = cl.c.y + l.dy * cl.ry * 1.6 * s + shift.y * cl.ry
                    p.addEllipse(in: R(x - r * 1.25, y - r, r * 2.5, r * 2))
                    // Leafy scallops along each lobe's rim.
                    for k in 0..<7 {
                        let a = CGFloat(k) / 7 * .pi * 2 + l.dx
                        let sr = r * 0.32
                        p.addEllipse(in: R(x + cos(a) * r * 1.15 - sr, y + sin(a) * r * 0.92 - sr * 0.8, sr * 2, sr * 1.6))
                    }
                }
                return p
            }
            let ys = clumps.map(\.c.y)
            let minY = ys.min() ?? 0, maxY = ys.max() ?? 1
            for cl in clumps {
                // Upper crown catches the sun; lower clumps sit in the canopy's own shade.
                let sun = Double((cl.c.y - minY) / max(1, maxY - minY))
                let lit = sun * rng.d(0.75, 1.0)
                let silhouette = lobePath(cl, scale: 1, shift: .zero)
                ctx.fillPath(tones[0], 1, silhouette)
                ctx.saveGState()
                ctx.addPath(silhouette); ctx.clip()
                ctx.fillPath(tones[1], 1, lobePath(cl, scale: 0.92, shift: P(-0.04, 0.1)))
                ctx.fillPath(tones[2], 0.55 + 0.45 * lit, lobePath(cl, scale: 0.78, shift: P(-0.08, 0.24)) { $0.dy > -0.25 })
                ctx.fillPath(tones[3], 0.15 + 0.85 * lit, lobePath(cl, scale: 0.58, shift: P(-0.13, 0.36)) { $0.dy > 0.05 })
                if lit > 0.45 {
                    ctx.fillPath(tones[4], 0.8 * (lit - 0.45) / 0.55, lobePath(cl, scale: 0.32, shift: P(-0.2, 0.5)) { $0.dx < 0.1 && $0.dy > 0.15 })
                }
                // A little leaf texture: short darker strokes in the mid tones.
                for _ in 0..<40 {
                    let x = cl.c.x + rng.cg(-cl.rx, cl.rx), y = cl.c.y + rng.cg(-cl.ry * 0.6, cl.ry * 1.2)
                    let len = cl.rx * rng.cg(0.04, 0.08)
                    ctx.strokeLine(tones[1], 0.35, width: max(0.7, cl.rx * 0.012), [P(x, y), P(x + len, y + len * 0.3)])
                }
                if bloom > 0 {
                    for _ in 0..<Int(14 * bloom) {
                        let bx = cl.c.x + rng.cg(-cl.rx * 0.8, cl.rx * 0.6), by = cl.c.y + rng.cg(0, cl.ry * 1.1)
                        for _ in 0..<5 {
                            let fr = cl.rx * rng.cg(0.025, 0.045)
                            ctx.fillEllipse(rng.pick(reds), 0.95, R(bx + rng.cg(-fr * 2, fr * 2), by + rng.cg(-fr, fr * 1.5), fr * 2, fr * 1.7))
                        }
                    }
                }
                ctx.restoreGState()
            }
        }
        return PropArt(texture: Painter.texture(img), size: CGSize(width: w, height: h), anchor: P(trunkX / w, 0))
    }

    // MARK: Coconut palm.

    static func palm(width w: CGFloat, height h: CGFloat, seed: UInt64) -> PropArt {
        var rng = SeededRNG(seed: seed)
        let img = Painter.image(CGSize(width: w, height: h)) { ctx in
            let base = P(w * 0.62, 0), crown = P(w * 0.45, h * 0.8)
            let trunk = CGMutablePath()
            trunk.move(to: P(base.x - w * 0.04, 0))
            trunk.addQuadCurve(to: P(crown.x - w * 0.018, crown.y), control: P(w * 0.62, h * 0.45))
            trunk.addLine(to: P(crown.x + w * 0.018, crown.y))
            trunk.addQuadCurve(to: P(base.x + w * 0.04, 0), control: P(w * 0.7, h * 0.45))
            trunk.closeSubpath()
            ctx.fillPath(RGB(0x7A6A58), 1, trunk)
            ctx.saveGState(); ctx.addPath(trunk); ctx.clip()
            var y: CGFloat = 4
            while y < crown.y { ctx.fill(RGB(0x5E5144), 1, R(0, y, w, 1.2)); y += 6 }
            ctx.restoreGState()
            for i in 0..<11 {
                let ang = -0.25 + CGFloat(i) / 10 * (.pi + 0.5) + rng.cg(-0.1, 0.1)
                let len = w * rng.cg(0.38, 0.5)
                let tip = P(crown.x + cos(ang) * len, crown.y + sin(ang) * len * 0.55 - len * 0.35)
                let ctrl = P(crown.x + cos(ang) * len * 0.55, crown.y + max(0, sin(ang)) * len * 0.5 + len * 0.15)
                let col = rng.pick([RGB(0x3E6833), RGB(0x4C7A3E), RGB(0x34592C)])
                for j in 0..<22 {
                    let t = CGFloat(j) / 22
                    let pt = P(pow(1 - t, 2) * crown.x + 2 * (1 - t) * t * ctrl.x + t * t * tip.x,
                               pow(1 - t, 2) * crown.y + 2 * (1 - t) * t * ctrl.y + t * t * tip.y)
                    let ll = len * 0.22 * (1 - t * 0.7)
                    ctx.strokeLine(col, 1, width: 1.3, [pt, P(pt.x + ll * 0.35, pt.y - ll)])
                    ctx.strokeLine(col, 1, width: 1.3, [pt, P(pt.x - ll * 0.35, pt.y - ll)])
                }
                let spine = CGMutablePath(); spine.move(to: crown); spine.addQuadCurve(to: tip, control: ctrl)
                ctx.setStrokeColor(col.darker(0.2).cg()); ctx.setLineWidth(1.6); ctx.addPath(spine); ctx.strokePath()
            }
            for _ in 0..<5 { ctx.fillEllipse(RGB(0x5A4A2E), 1, R(crown.x + rng.cg(-8, 4), crown.y - rng.cg(4, 10), 6, 6)) }
        }
        return PropArt(texture: Painter.texture(img), size: CGSize(width: w, height: h), anchor: P(0.62, 0))
    }

    // MARK: Lamp post (twin arms).

    static func lampPost(height h: CGFloat) -> PropArt {
        let w = h * 0.5
        let metal = RGB(0x3A3D45)
        let img = Painter.image(CGSize(width: w, height: h)) { ctx in
            let cx = w / 2
            ctx.fill(metal, 1, R(cx - h * 0.012, 0, h * 0.024, h * 0.93))
            ctx.fill(metal, 1, R(cx - h * 0.025, 0, h * 0.05, h * 0.06))
            for s in [-1.0, 1.0] as [CGFloat] {
                let arm = CGMutablePath()
                arm.move(to: P(cx, h * 0.9))
                arm.addQuadCurve(to: P(cx + s * w * 0.4, h * 0.94), control: P(cx + s * w * 0.15, h * 1.0))
                ctx.setStrokeColor(metal.cg()); ctx.setLineWidth(h * 0.012); ctx.addPath(arm); ctx.strokePath()
                ctx.fillEllipse(RGB(0xDCD6C8), 1, R(cx + s * w * 0.4 - h * 0.04, h * 0.9, h * 0.08, h * 0.04))
            }
        }
        return PropArt(texture: Painter.texture(img), size: CGSize(width: w, height: h),
                       points: [P(w * 0.1, h * 0.91), P(w * 0.9, h * 0.91)])
    }

    // MARK: Near bank: footpaths, road, railing, hedge.

    static func road(width W: CGFloat, H: CGFloat, seed: UInt64) -> PropArt {
        var rng = SeededRNG(seed: seed)
        let h = H * 0.185
        let img = Painter.image(CGSize(width: W, height: h)) { ctx in
            let asphalt = RGB(0x5B5D63)
            ctx.fill(RGB(0xA6A198), 1, R(0, H * 0.04, W, H * 0.022))
            ctx.fill(asphalt, 1, R(0, H * 0.06, W, H * 0.087))
            for _ in 0..<Int(W * 1.5) {
                ctx.fill(rng.chance(0.5) ? asphalt.lighter(0.12) : asphalt.darker(0.15), 0.5,
                         R(rng.cg(0, W), rng.cg(H * 0.06, H * 0.147), 1.2, 1))
            }
            ctx.fill(asphalt.darker(0.12), 0.5, R(0, H * 0.078, W, H * 0.008))
            ctx.fill(asphalt.darker(0.12), 0.5, R(0, H * 0.118, W, H * 0.006))
            var dx: CGFloat = 0
            while dx < W { ctx.fill(RGB(0xD9D6CC), 0.85, R(dx, H * 0.103, H * 0.05, max(1.2, H * 0.0025))); dx += H * 0.1 }
            ctx.fill(RGB(0x8E8A82), 1, R(0, H * 0.145, W, H * 0.004))
            ctx.fill(RGB(0xA49F96), 1, R(0, H * 0.149, W, H * 0.011))
            var tx: CGFloat = 0
            while tx < W { ctx.fill(RGB(0x8E8A82), 0.6, R(tx, H * 0.149, 0.8, H * 0.011)); tx += H * 0.03 }
            // Railing at the water's edge.
            let rail = RGB(0x8C9098)
            ctx.fill(rail, 1, R(0, H * 0.178, W, max(1.5, H * 0.0035)))
            ctx.fill(rail, 1, R(0, H * 0.168, W, max(1, H * 0.002)))
            var px: CGFloat = 0
            while px < W { ctx.fill(rail.darker(0.1), 1, R(px, H * 0.16, max(1.5, H * 0.003), H * 0.021)); px += H * 0.045 }
            // Hedge along the bottom.
            ctx.fill(RGB(0x22402A), 1, R(0, 0, W, H * 0.042))
            for _ in 0..<Int(W / 1.6) {
                let r = rng.cg(H * 0.006, H * 0.016)
                ctx.fillEllipse(rng.pick([RGB(0x2F5531), RGB(0x3B6236), RGB(0x2A4A2C), RGB(0x4A7340)]), 1,
                                R(rng.cg(-r, W), rng.cg(-r * 0.6, H * 0.036), r * 2, r * 1.3))
            }
        }
        return PropArt(texture: Painter.texture(img), size: CGSize(width: W, height: h), anchor: .zero)
    }
}
