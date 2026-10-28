import AppKit
import SpriteKit

extension ArtViews {
    // MARK: Dhanmondi Lake: lakeside promenade, winding lake, footbridge, Rabindra Sarobar, trees and apartments.

    static func dhanmondi(W: CGFloat, H: CGFloat, seed: UInt64) -> ViewArt {
        let cam = Cam.make(W: W, H: H, height: 10, pitchDeg: 12, horizon: 0.6, cx: 0.5, cy: 0.4)
        let pp = PerspectivePainter(cam: cam, W: W, H: H, seed: seed)
        pp.hazeRange = 150...1100
        let zNear = cam.groundZ(atScreenY: -H * 0.03), zFar: CGFloat = 1100
        let nearEdge: CGFloat = 31
        // The far bank: close on the left (a narrow arm), sweeping away to the right.
        func bank(_ x: CGFloat) -> CGFloat { min(1500, x < -30 ? 120 : (x < 60 ? 120 + (x + 30) * 1.0 : 210 + (x - 60) * 2.4)) }
        let hwFar = cam.halfWidth(1500, W: W)

        let top = pp.groundGradient(RGB(0x6E9A52), farZ: zFar, hazeMix: 0.6)
        // Water: near edge, then back along the far bank.
        var water: [CGPoint] = [cam.p(-hwFar, 0, nearEdge), cam.p(hwFar, 0, nearEdge)]
        var x = hwFar
        while x > -hwFar { water.append(cam.p(x, 0, bank(x))); x -= max(2, abs(x) * 0.02) }
        let waterPath = CGPath.poly(water)
        pp.ctx.saveGState(); pp.ctx.setBlendMode(.clear); pp.ctx.addPath(waterPath); pp.ctx.fillPath(); pp.ctx.restoreGState()

        // Far bank: footpath, rows of big trees, the amphitheatre, then apartments.
        let amph: ClosedRange<CGFloat> = -78...(-50)
        var trees: [(CGFloat, CGFloat, CGFloat, RGB?)] = []
        for row in 0..<3 {
            var tx = -cam.halfWidth(200, W: W)
            while tx < hwFar {
                let bz = bank(tx)
                if bz > 600 { break }
                if !(amph.contains(tx) && row == 0) {
                    let flower: RGB? = pp.rng.chance(0.1) ? RGB(0xD9483A) : (pp.rng.chance(0.06) ? RGB(0xE8B83A) : nil)
                    trees.append((tx + pp.rng.cg(-2, 2), bz + 4 + CGFloat(row) * 9 + pp.rng.cg(0, 4), pp.rng.cg(4, 6) * (1 + bz / 900), flower))
                }
                tx += pp.rng.cg(7, 11) * (1 + bz / 400)
            }
        }
        var boxes: [PerspectivePainter.Box] = []
        var bz: CGFloat = 145
        while bz < zFar {
            let dz = pp.rng.cg(16, 26) * (1 + bz / 500)
            var bx = -cam.halfWidth(bz, W: W)
            while bx < cam.halfWidth(bz, W: W) {
                let bw = pp.rng.cg(14, 26) * (1 + bz / 600)
                if bz > max(bank(bx), bank(bx + bw)) + 22 {
                    var h = pp.rng.cg(18, 42)
                    if pp.rng.chance(0.1) { h = pp.rng.cg(50, 75) }
                    boxes.append(pp.randomBox(x0: bx, x1: bx + bw, z0: bz, z1: bz + dz * 0.8, h: h))
                }
                bx += bw + pp.rng.cg(3, 9)
            }
            bz += dz
        }
        // Reflections of the far bank in the lake (water plane mirror: y → −y), clipped to the water.
        pp.ctx.saveGState(); pp.ctx.addPath(waterPath); pp.ctx.clip()
        for b in boxes where b.z0 < 400 {
            let pts = [cam.p(b.x0, 0, b.z0), cam.p(b.x1, 0, b.z0), cam.p(b.x1, -b.h, b.z0), cam.p(b.x0, -b.h, b.z0)]
            pp.poly(pts, pp.tone(b.wall, b.z0).scaled(0.7), 0.16)
        }
        for (tx, tz, r, f) in trees where tz < 300 {
            let c = cam.p(tx, -r * 1.25, tz), rad = r * cam.scale(0, tz)
            pp.ctx.fillEllipse(pp.tone(f ?? PerspectivePainter.greens.dark, tz).scaled(0.8), 0.2, R(c.x - rad * 1.1, c.y - rad * 0.9, rad * 2.2, rad * 1.8))
        }
        pp.ctx.restoreGState()
        // Far-bank walkway as a thin band along the shore.
        var walk: [CGPoint] = []
        x = -cam.halfWidth(200, W: W)
        var back: [CGPoint] = []
        while x < 260 { walk.append(cam.p(x, 0, bank(x) + 0.5)); back.append(cam.p(x, 0, bank(x) + 3)); x += 3 }
        pp.poly(walk + back.reversed(), pp.tone(RGB(0xCFC6B4), 100))

        for b in boxes { pp.addBox(b) }
        for (tx, tz, r, f) in trees { pp.addTree(tx, tz, r: r, flowering: f) }
        // Rabindra Sarobar: stone steps down to the water and a white-roofed stage.
        for i in 0..<6 {
            let z0 = 120.5 + CGFloat(i) * 2.2
            pp.addBox(PerspectivePainter.Box(x0: amph.lowerBound, x1: amph.upperBound, z0: z0, z1: z0 + 2.2, h: 0.4 + CGFloat(i) * 0.55,
                                             wall: RGB(0xD9CFC0), roof: RGB(0xE6DED2), details: false, litChance: 0))
        }
        pp.add(137) { [unowned pp] in
            let z: CGFloat = 137
            for px in [amph.lowerBound + 3, amph.lowerBound + 10, amph.upperBound - 10, amph.upperBound - 3] {
                pp.line3D((px, 3.5, z), (px, 9, z), RGB(0xEDEDED), widthM: 0.4)
            }
            let roof = CGMutablePath()
            for i in 0...30 {
                let t = CGFloat(i) / 30
                let q = cam.p(amph.lowerBound + 1 + (amph.upperBound - amph.lowerBound - 2) * t, 9 + 2.2 * sin(.pi * t), z)
                if i == 0 { roof.move(to: q) } else { roof.addLine(to: q) }
            }
            pp.ctx.setStrokeColor(RGB(0xF4F4F4).cg()); pp.ctx.setLineWidth(max(2, 0.8 * cam.scale(9, z))); pp.ctx.addPath(roof); pp.ctx.strokePath()
            pp.lit.setStrokeColor(RGB(0xFFD9A0).cg(0.5)); pp.lit.setLineWidth(max(2, 0.8 * cam.scale(9, z))); pp.lit.addPath(roof); pp.lit.strokePath()
        }
        // White arched footbridge across the narrow arm.
        pp.add(75) { [unowned pp] in
            let x0: CGFloat = -24, x1: CGFloat = -20
            var topL: [CGPoint] = [], topR: [CGPoint] = [], under: [CGPoint] = []
            for i in 0...30 {
                let t = CGFloat(i) / 30
                let z = nearEdge - 1 + (120 + 2 - nearEdge + 1) * t
                let y = 1.0 + 3.5 * sin(.pi * t)
                topL.append(cam.p(x0, y, z)); topR.append(cam.p(x1, y, z)); under.append(cam.p(x1, y - 0.7, z))
            }
            pp.poly(topL + topR.reversed(), RGB(0xBFB6A8))
            pp.poly(topR + under.reversed(), RGB(0xF2F0EC))
            for (i, q) in topR.enumerated() where i % 2 == 0 {
                pp.ctx.strokeLine(RGB(0x3E5A3E), 1, width: max(0.6, cam.scale(1, 50) * 0.08), [q, P(q.x, q.y + cam.scale(1, 50) * 1.0)])
            }
            pp.ctx.strokeLine(RGB(0x3E5A3E), 1, width: max(0.8, cam.scale(1, 50) * 0.1), topR.map { P($0.x, $0.y + cam.scale(1, 50) * 1.0) })
            for (i, q) in topR.enumerated() where i % 5 == 0 { pp.lit.fillEllipse(RGB(0xFFE0A8), 0.9, R(q.x - 2, q.y + cam.scale(1, 50) * 1.1, 4, 4)) }
        }
        pp.flush()

        // Near bank: grass with flower beds, the promenade, lamps, benches and a railing.
        let hwNear = cam.halfWidth(nearEdge, W: W)
        pp.strip(zNear, nearEdge, left: { _ in -hwNear }, right: { _ in hwNear }, RGB(0x6E9A52), steps: 4)
        for _ in 0..<160 {
            let fx = pp.rng.cg(-hwNear, hwNear), fz = pp.rng.cg(zNear, 22)
            let q = cam.p(fx, 0, fz), d = cam.scale(0, fz) * 0.18
            pp.ctx.fillEllipse(pp.rng.pick([RGB(0xE8B83A), RGB(0xD9483A), RGB(0xF2E6D8), RGB(0xC94B8A)]), 0.95, R(q.x, q.y, d, d * 0.8))
        }
        pp.strip(23, 29, left: { _ in -hwNear }, right: { _ in hwNear }, RGB(0xCFC6B4), steps: 4)
        var jz: CGFloat = 23
        while jz < 29 { pp.line3D((-hwNear, 0.01, jz), (hwNear, 0.01, jz), RGB(0xB8AE9C), widthM: 0.04, minW: 0.4); jz += 1.2 }
        pp.strip(29, nearEdge, left: { _ in -hwNear }, right: { _ in hwNear }, RGB(0x8E9A7C), steps: 2)
        var px = -hwNear
        while px < hwNear {  // railing
            pp.line3D((px, 0, 30.3), (px, 1.0, 30.3), RGB(0x2F4A3A), widthM: 0.06)
            px += 2
        }
        for y in [0.5, 1.0] as [CGFloat] { pp.line3D((-hwNear, y, 30.3), (hwNear, y, 30.3), RGB(0x2F4A3A), widthM: 0.05) }
        for bx in [-19.0, 6.0, 21.0] as [CGFloat] {  // benches
            pp.drawBox(PerspectivePainter.Box(x0: bx, x1: bx + 1.8, z0: 28.4, z1: 28.9, h: 0.45, wall: RGB(0x6B4A32), roof: RGB(0x8A6444), details: false, litChance: 0))
            pp.drawBox(PerspectivePainter.Box(x0: bx, x1: bx + 1.8, z0: 28.9, z1: 29.0, h: 0.95, wall: RGB(0x6B4A32), roof: RGB(0x8A6444), details: false, litChance: 0))
        }
        var lx = -hwNear + 4
        while lx < hwNear {
            pp.line3D((lx, 0, 29.4), (lx, 4, 29.4), RGB(0x2E2E33), widthM: 0.1, minW: 0.8)
            let q = cam.p(lx, 4.1, 29.4), d = max(3, cam.scale(4, 29.4) * 0.4)
            pp.ctx.fillEllipse(RGB(0xEDE6D2), 1, R(q.x - d / 2, q.y - d / 2, d, d))
            pp.lit.fillEllipse(RGB(0xFFD9A0), 1, R(q.x - d / 2, q.y - d / 2, d, d))
            pp.lit.fillEllipse(RGB(0xFFD9A0), 0.15, R(q.x - d * 3, q.y - d * 3, d * 6, d * 6))
            lx += 13
        }

        let (base, lights) = pp.finish()
        var art = ViewArt(base: base, lights: lights, cam: cam, hasWater: true, waterTint: RGB(0x3E7F68))
        for (z, dir) in [(25.0, 1.0), (27.0, -1.0)] as [(CGFloat, CGFloat)] {
            art.lanes.append(Lane(kind: .walker, length: hwNear * 2 + 6, point: { s in (dir > 0 ? -hwNear - 3 + s : hwNear + 3 - s, 0, z) },
                                  count: 3, speed: 1.0...1.9))
        }
        art.lanes.append(Lane(kind: .rowboat, length: 90, point: { s in (-16 + s, 0, 60) }, fadeIn: 8, fadeOut: 8, count: 1, speed: 0.8...1.2))
        art.lanes.append(Lane(kind: .rowboat, length: 160, point: { s in (170 - s, 0, 170 + s * 0.2) }, fadeIn: 8, fadeOut: 8, count: 1, speed: 0.8...1.2))
        let a = cam.p(0, 0, nearEdge), b = cam.p(0, 0, 200)
        art.rippleRect = CGRect(x: 0, y: a.y, width: W, height: b.y - a.y)
        art.skyline = 0.02
        art.groundTop = top
        art.hazeDepth = 0.06
        return art
    }

    // MARK: Cefalo rooftop: the living green wall under a pergola, teak deck, and the city beyond the glass railing.

    static func cefalo(W: CGFloat, H: CGFloat, seed: UInt64) -> ViewArt {
        let roofY: CGFloat = 40
        let cam = Cam.make(W: W, H: H, height: roofY + 1.6, pitchDeg: 10, horizon: 0.6, cx: 0.5, cy: 0.42)
        let pp = PerspectivePainter(cam: cam, W: W, H: H, seed: seed)
        pp.hazeRange = 300...2600
        let zFar: CGFloat = 2600
        let top = pp.groundGradient(RGB(0xB9AF9A), farZ: zFar)
        let p = cam.p

        // The city below and beyond.
        var z: CGFloat = 40
        while z < zFar {
            let dz = pp.rng.cg(18, 30) * (1 + z / 700)
            let hw = cam.halfWidth(z, W: W)
            var x = -hw
            while x < hw {
                let bw = pp.rng.cg(12, 24) * (1 + z / 900)
                if pp.rng.chance(0.22) {
                    pp.addTree(x + bw / 2, z + dz / 2, r: pp.rng.cg(4, 7) * (1 + z / 800), flowering: pp.rng.chance(0.05) ? RGB(0xD9603E) : nil)
                } else {
                    var h = pp.rng.cg(12, 36)
                    var glass = false
                    if z > 500 && pp.rng.chance(0.12) { h = pp.rng.cg(60, 150); glass = pp.rng.chance(0.6) }
                    pp.addBox(pp.randomBox(x0: x, x1: x + bw, z0: z, z1: z + dz * 0.8, h: h, glass: glass))
                }
                x += bw + pp.rng.cg(2, 7)
            }
            z += dz
        }
        pp.flush()

        // Layout of the terrace (metres; camera stands at x = 0).
        let wallX: CGFloat = -2.4, wallZ0: CGFloat = 1.5, wallZ1: CGFloat = 15, wallH: CGFloat = 3.0
        let railZ: CGFloat = 15.5, railX: CGFloat = 6.2
        let deckL = wallX, deckR = railX

        // Deck: planks running away from us, each a slightly different tone.
        let wood = [RGB(0xB58858), RGB(0xB08454), RGB(0xBA8D5E), RGB(0xB3865A)]
        var px = deckL
        var i = 0
        while px < deckR {
            let x0 = px, x1 = min(deckR, px + 0.15)
            pp.strip(1, railZ, left: { _ in x0 }, right: { _ in x1 }, wood[(i * 7 + i / 3) % wood.count], steps: 2, y: roofY)
            pp.line3D((x0, roofY + 0.005, 1), (x0, roofY + 0.005, railZ), RGB(0x8E6440), widthM: 0.006, minW: 0.3)
            px += 0.15; i += 1
        }
        // Soft shadow of the pergola on the deck.
        pp.poly([p(wallX, roofY, wallZ0), p(1.1, roofY, wallZ0), p(1.1, roofY, wallZ1), p(wallX, roofY, wallZ1)], RGB(0x3A2A1E), 0.12)

        // Glass railings: far edge and right side, with the city behind.
        let glass = RGB(0xC9DDE8)
        pp.poly([p(deckL, roofY, railZ), p(deckR, roofY, railZ), p(deckR, roofY + 1.1, railZ), p(deckL, roofY + 1.1, railZ)], glass, 0.14)
        pp.poly([p(railX, roofY, 1), p(railX, roofY, railZ), p(railX, roofY + 1.1, railZ), p(railX, roofY + 1.1, 1)], glass, 0.14)
        var rx = deckL
        while rx <= deckR { pp.line3D((rx, roofY, railZ), (rx, roofY + 1.1, railZ), RGB(0x8E949C), widthM: 0.04, minW: 0.6); rx += 1.5 }
        var rz: CGFloat = 1
        while rz <= railZ { pp.line3D((railX, roofY, rz), (railX, roofY + 1.1, rz), RGB(0x8E949C), widthM: 0.04, minW: 0.6); rz += 1.5 }
        pp.line3D((deckL, roofY + 1.1, railZ), (deckR, roofY + 1.1, railZ), RGB(0xA4AAB2), widthM: 0.05, minW: 0.8)
        pp.line3D((railX, roofY + 1.1, 1), (railX, roofY + 1.1, railZ), RGB(0xA4AAB2), widthM: 0.05, minW: 0.8)

        // Long concrete planter of ornamental grasses along the right railing.
        let plX0 = railX - 0.7, plX1 = railX - 0.1
        pp.drawBox(PerspectivePainter.Box(x0: plX0, x1: plX1, z0: 3, z1: railZ - 0.2, h: roofY + 0.55, wall: RGB(0x8C8C88), roof: RGB(0x5A4632), y0: roofY, details: false, litChance: 0))
        let grass = [RGB(0x6E8F4A), RGB(0x8DA85A), RGB(0xB5C27A), RGB(0x5C7A3E), RGB(0xC9B97A)]
        var gz = railZ - 0.3
        while gz > 3.1 {
            for _ in 0..<5 {
                let gx = pp.rng.cg(plX0 + 0.05, plX1 - 0.05)
                let base = p(gx, roofY + 0.55, gz), s = cam.scale(roofY + 0.55, gz)
                let h = pp.rng.cg(0.45, 0.9) * s
                for _ in 0..<4 {
                    let lean = pp.rng.cg(-0.35, 0.35) * h
                    let blade = CGMutablePath()
                    blade.move(to: base)
                    blade.addQuadCurve(to: P(base.x + lean, base.y + h), control: P(base.x + lean * 0.2, base.y + h * 0.7))
                    pp.ctx.setStrokeColor(pp.rng.pick(grass).cg()); pp.ctx.setLineWidth(max(0.5, s * 0.012)); pp.ctx.addPath(blade); pp.ctx.strokePath()
                }
            }
            gz -= 0.12
        }
        // Planter uplights.
        var uz: CGFloat = 4
        while uz < railZ { let q = p(plX0, roofY + 0.3, uz); pp.lit.fillEllipse(RGB(0xFFE2B0), 0.9, R(q.x - 1.5, q.y - 1.5, 3, 3)); uz += 2 }

        // The living wall, receding along the left, drawn flat, then mapped onto the wall in vertical slices.
        let ppmW: CGFloat = 110
        let wallLen = wallZ1 - wallZ0
        let flatSize = CGSize(width: wallLen * ppmW, height: wallH * ppmW)
        let flat = Painter.context(flatSize, scale: 1), flatLit = Painter.context(flatSize, scale: 1)
        flat.fill(RGB(0x1B2E1E), 1, R(0, 0, flatSize.width, flatSize.height))
        let leafGreens = [RGB(0x2F5530), RGB(0x3E6B38), RGB(0x4F7F40), RGB(0x2A4628), RGB(0x5C8A45)]
        let lime = [RGB(0xA9C04E), RGB(0xC4D46A), RGB(0x8DB04A)]
        for _ in 0..<Int(flatSize.width * flatSize.height / 10) {
            let lx = pp.rng.cg(0, flatSize.width), ly = pp.rng.cg(0, flatSize.height)
            let band = ly / (ppmW * 0.55)
            let inBand = abs(band - band.rounded()) < 0.16
            let c = inBand && pp.rng.chance(0.6) ? pp.rng.pick(lime) : pp.rng.pick(leafGreens)
            let l = ppmW * pp.rng.cg(0.05, 0.09)
            flat.saveGState(); flat.translateBy(x: lx, y: ly); flat.rotate(by: pp.rng.cg(-0.9, 0.9) + (pp.rng.chance(0.5) ? .pi : 0))
            flat.fillEllipse(c, 0.95, R(0, -l * 0.3, l * 2, l * 0.6))
            flat.restoreGState()
        }
        // ⋮CEFALO, white, around 5 to 9 m along the wall.
        let logoH = ppmW * 0.5
        let font = NSFont.systemFont(ofSize: logoH, weight: .regular).fontDescriptor.withDesign(.rounded)
            .flatMap { NSFont(descriptor: $0, size: logoH) } ?? NSFont.systemFont(ofSize: logoH)
        let text = NSAttributedString(string: "CEFALO", attributes: [.font: font, .foregroundColor: NSColor.white, .kern: logoH * 0.1])
        let tw = text.size().width
        let lx0 = ppmW * 2.6, ly = flatSize.height * 0.52
        for (g, a) in [(flat, 1.0), (flatLit, 1.0)] as [(CGContext, Double)] {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: g, flipped: false)
            text.draw(at: P(lx0 + logoH * 0.5, ly - logoH * 0.62))
            NSGraphicsContext.restoreGraphicsState()
            for k in 0..<3 {
                let d = logoH * 0.27
                g.fillEllipse(.white, a, R(lx0, ly - logoH * 0.48 + CGFloat(k) * logoH * 0.36, d, d))
            }
        }
        _ = tw
        let flatImg = flat.makeImage()!, flatLitImg = flatLit.makeImage()!
        // Slices are thinner up close (geometric spacing) and clipped to their exact quad, so edges stay smooth.
        let slices = 700
        for k in 0..<slices {
            let za = wallZ0 * pow(wallZ1 / wallZ0, CGFloat(k) / CGFloat(slices))
            let zb = wallZ0 * pow(wallZ1 / wallZ0, CGFloat(k + 1) / CGFloat(slices))
            let t0 = (za - wallZ0) / wallLen, t1 = (zb - wallZ0) / wallLen
            let a0 = p(wallX, roofY, za), a1 = p(wallX, roofY + wallH, za), b0 = p(wallX, roofY, zb), b1 = p(wallX, roofY + wallH, zb)
            let quad = CGPath.poly([a0, b0, b1, a1])
            let bb = quad.boundingBoxOfPath.insetBy(dx: -0.5, dy: 0)
            let src = CGRect(x: flatSize.width * t0, y: 0, width: max(1, flatSize.width * (t1 - t0)), height: flatSize.height)
            let grow = CGPath.poly([P(a0.x - 0.6, a0.y), b0, b1, P(a1.x - 0.6, a1.y)])
            for (g, img) in [(pp.ctx, flatImg), (pp.lit, flatLitImg)] as [(CGContext, CGImage)] {
                g.saveGState(); g.addPath(grow); g.clip()
                if g === pp.lit { g.setBlendMode(.clear); g.fill(bb); g.setBlendMode(.normal) }
                if let piece = img.cropping(to: src) { g.draw(piece, in: bb) }
                g.restoreGState()
            }
        }
        // Pebble bed along the wall's foot.
        pp.strip(wallZ0, wallZ1, left: { _ in wallX }, right: { _ in wallX + 0.45 }, RGB(0x9C9A94), steps: 2, y: roofY + 0.01)
        for _ in 0..<900 {
            let pz = pp.rng.cg(wallZ0, wallZ1)
            let q = p(pp.rng.cg(wallX, wallX + 0.45), roofY + 0.02, pz), d = cam.scale(roofY, pz) * pp.rng.cg(0.035, 0.06)
            pp.ctx.fillEllipse(pp.rng.pick([RGB(0xDAD7D0), RGB(0xBAB7B0), RGB(0xEEEBE5), RGB(0x8F8D87)]), 1, R(q.x, q.y, d, d * 0.65))
        }
        // Night wash from the spotlights onto the wall.
        var wz = wallZ0 + 0.6
        while wz < wallZ1 {
            let c = p(wallX, roofY + wallH * 0.62, wz), s = cam.scale(roofY + 2, wz)
            pp.lit.fillEllipse(RGB(0xFFE8B8), 0.045, R(c.x - s * 0.25, c.y - s * 1.3, s * 0.5, s * 2.2))
            wz += 1.2
        }

        // Teak loungers with cream cushions, and a round side table.
        func lounger(_ x: CGFloat, _ z: CGFloat) {
            let teak = RGB(0x8A5A36), cushion = RGB(0xE9E1D2)
            pp.drawBox(PerspectivePainter.Box(x0: x, x1: x + 0.7, z0: z, z1: z + 1.9, h: roofY + 0.32, wall: teak, roof: teak, y0: roofY + 0.12, details: false, litChance: 0))
            for lz in [z + 0.05, z + 1.75] { for lx in [x + 0.05, x + 0.6] {
                pp.drawBox(PerspectivePainter.Box(x0: lx, x1: lx + 0.06, z0: lz, z1: lz + 0.06, h: roofY + 0.12, wall: teak.darker(0.2), roof: teak, y0: roofY, details: false, litChance: 0))
            } }
            pp.drawBox(PerspectivePainter.Box(x0: x + 0.03, x1: x + 0.67, z0: z + 0.05, z1: z + 1.4, h: roofY + 0.42, wall: cushion.darker(0.08), roof: cushion, y0: roofY + 0.32, details: false, litChance: 0))
            // Raised backrest at the far end.
            let b = [p(x + 0.03, roofY + 0.32, z + 1.4), p(x + 0.67, roofY + 0.32, z + 1.4), p(x + 0.67, roofY + 0.95, z + 1.85), p(x + 0.03, roofY + 0.95, z + 1.85)]
            pp.poly(b, cushion)
            pp.outline(b, cushion.scaled(0.6), 0.4, width: 0.8)
        }
        // Far things first: the string-light posts and the side table sit behind/between the loungers.
        for zPost in [6.0, 12.0] as [CGFloat] { pp.line3D((railX, roofY, zPost), (railX, roofY + 2.7, zPost), RGB(0x2E2E33), widthM: 0.05, minW: 0.8) }
        let tc = p(2.8, roofY + 0.5, 6.4), ts = cam.scale(roofY + 0.5, 6.4)
        pp.line3D((2.8, roofY, 6.4), (2.8, roofY + 0.5, 6.4), RGB(0x2E2E33), widthM: 0.05)
        pp.ctx.fillEllipse(RGB(0x6B4A32), 1, R(tc.x - ts * 0.22, tc.y - ts * 0.05, ts * 0.44, ts * 0.1))
        pp.occlude(CGPath(ellipseIn: R(tc.x - ts * 0.22, tc.y - ts * 0.05, ts * 0.44, ts * 0.1), transform: nil))
        lounger(3.3, 5.2)
        lounger(1.6, 5.2)

        // Pergola: posts, a fascia beam, and slats overhead with recessed spotlights.
        let beamY: CGFloat = roofY + wallH + 0.25, fasciaX: CGFloat = 1.1
        let darkWood = RGB(0x6E4A2E), slat = RGB(0xA8774A)
        for pz in stride(from: 6.0, through: wallZ1, by: 4.0) {
            pp.drawBox(PerspectivePainter.Box(x0: fasciaX - 0.07, x1: fasciaX + 0.07, z0: pz, z1: pz + 0.14, h: beamY, wall: darkWood, roof: darkWood, y0: roofY, details: false, litChance: 0))
        }
        var sz = wallZ1
        while sz >= wallZ0 {
            // Slat underside (we look up at it), then its front edge.
            let under = [p(wallX, beamY, sz), p(fasciaX + 0.25, beamY, sz), p(fasciaX + 0.25, beamY, sz + 0.12), p(wallX, beamY, sz + 0.12)]
            pp.poly(under, slat.darker(0.15))
            let front = [p(wallX, beamY, sz), p(fasciaX + 0.25, beamY, sz), p(fasciaX + 0.25, beamY + 0.18, sz), p(wallX, beamY + 0.18, sz)]
            pp.poly(front, slat)
            sz -= 0.55
        }
        let fascia = [p(fasciaX, beamY - 0.2, wallZ0), p(fasciaX, beamY - 0.2, wallZ1), p(fasciaX, beamY, wallZ1), p(fasciaX, beamY, wallZ0)]
        pp.poly(fascia, darkWood)
        var lz = wallZ0 + 0.5
        while lz < wallZ1 {
            let q = p(wallX + 0.35, beamY - 0.01, lz), s = cam.scale(beamY, lz)
            let d = max(2, s * 0.1)
            pp.ctx.fillEllipse(RGB(0x1E1E1E), 1, R(q.x - d, q.y - d * 0.4, d * 2, d * 0.8))
            pp.ctx.fillEllipse(RGB(0xFFF4DC), 1, R(q.x - d * 0.5, q.y - d * 0.2, d, d * 0.4))
            pp.lit.fillEllipse(RGB(0xFFE8B8), 1, R(q.x - d * 0.6, q.y - d * 0.25, d * 1.2, d * 0.5))
            lz += 1.2
        }

        // String lights zig-zagging from the pergola to the railing posts.
        let anchors: [(CGFloat, CGFloat, CGFloat)] = [(fasciaX, beamY - 0.1, 3), (railX, roofY + 2.6, 6), (fasciaX, beamY - 0.1, 9),
                                                      (railX, roofY + 2.6, 12), (fasciaX, beamY - 0.1, 15)]
        for k in 0..<(anchors.count - 1) {
            let a = anchors[k], b = anchors[k + 1]
            var prev = p(a.0, a.1, a.2)
            for j in 1...24 {
                let t = CGFloat(j) / 24
                let q = p(a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t - 0.45 * sin(.pi * t), a.2 + (b.2 - a.2) * t)
                pp.ctx.strokeLine(RGB(0x2A2A2E), 1, width: 0.7, [prev, q])
                if j % 2 == 0 {
                    let d = max(2, cam.scale(roofY + 2, a.2 + (b.2 - a.2) * t) * 0.07)
                    pp.ctx.fillEllipse(RGB(0xF4EBD0), 1, R(q.x - d / 2, q.y - d * 1.1, d, d * 1.3))
                    pp.lit.fillEllipse(RGB(0xFFD38A), 1, R(q.x - d / 2, q.y - d * 1.1, d, d * 1.3))
                    pp.lit.fillEllipse(RGB(0xFFD38A), 0.08, R(q.x - d * 1.4, q.y - d * 1.8, d * 2.8, d * 2.8))
                }
                prev = q
            }
        }

        let (base, lights) = pp.finish()
        var art = ViewArt(base: base, lights: lights, cam: cam, hasWater: false, waterTint: nil)
        art.planes = true
        art.skyline = 0.02
        art.groundTop = top
        art.hazeDepth = 0   // the city is already hazed in its colours; a haze sheet would wash over the terrace
        return art
    }
}
