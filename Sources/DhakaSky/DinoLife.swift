import SpriteKit

/// Everything that moves in Dinosaur World: walkers in three bands, Pteranodons, a Plesiosaur and the volcano.
final class DinoLife: SKNode {
    private let ex: DinoExtras
    private let W: CGFloat, H: CGFloat
    private var arts: [Dino: DinoArt] = [:]
    private let ptero: DinoArt, plesioArt: DinoArt
    private let shadowTex: SKTexture, glowTex = Painter.glow(64), puffTex = Painter.texture(Painter.blurred(Painter.image(CGSize(width: 64, height: 64)) { ctx in
        ctx.fillEllipse(RGB(0xD9D4D0), 1, R(6, 6, 52, 52))
        ctx.fillEllipse(.white, 1, R(14, 26, 30, 26))
    }, radius: 3))

    private final class Walker {
        let node = SKNode()
        var sprites: [SKSpriteNode] = []
        var back: CGFloat = 0, front: CGFloat = 0   // extent behind / ahead of the node, in points
    }
    private struct Band {
        var y: CGFloat, scale: CGFloat, dir: CGFloat, speed: CGFloat, max: Int, z: CGFloat
        var walkers: [Walker] = []
        var gap: CGFloat = 0
        var recent: [Dino] = []
    }
    private var bands: [Band] = []
    private var flyers: [(SKNode, CGFloat)] = []
    private var nextFlyer = 6.0
    private let plesio: SKSpriteNode
    private var plesioDir: CGFloat = 1
    private let smoke = SKEmitterNode(), lava = SKEmitterNode()
    private let craterGlow: SKSpriteNode
    private var nextEruption = Double.random(in: 25...60), erupting = 0.0
    private var clock = 0.0
    private var ambient = RGB.white, night = 0.0, haze = RGB.white

    init(_ ex: DinoExtras, size: CGSize) {
        self.ex = ex
        W = size.width; H = size.height
        for d in Dino.allCases { arts[d] = ArtDinos.art(d, ppm: ex.ppm) }
        ptero = ArtDinos.pteranodon(ppm: ex.ppm)
        plesioArt = ArtDinos.plesiosaur(ppm: ex.ppm)
        shadowTex = Painter.texture(CGSize(width: 64, height: 16), scale: 1) { ctx in
            ctx.fillEllipse(.black, 1, R(0, 0, 64, 16))
        }
        plesio = SKSpriteNode(texture: plesioArt.frames[0], size: plesioArt.size)
        craterGlow = SKSpriteNode(texture: glowTex, size: CGSize(width: ex.craterHW * 7, height: ex.craterHW * 4))
        super.init()

        let speeds: [CGFloat] = [1.1, 1.3, 1.5]
        let counts = [4, 3, 3]
        for (i, b) in ex.bands.enumerated() {
            bands.append(Band(y: b.y, scale: b.scale, dir: i == 1 ? -1 : 1, speed: speeds[i], max: counts[i], z: 2 + CGFloat(i) * 0.3))
        }

        let fg = SKSpriteNode(texture: Painter.texture(ex.foreground), size: size)
        fg.anchorPoint = .zero; fg.zPosition = 3.5; fg.colorBlendFactor = 1; fg.name = "fg"
        addChild(fg)

        // Plesiosaur in the lake.
        plesio.anchorPoint = plesioArt.anchor
        let k: CGFloat = 0.85
        plesio.size = CGSize(width: plesioArt.size.width * k, height: plesioArt.size.height * k)
        plesio.position = P(ex.lake.midX, ex.lake.midY + ex.lake.height * 0.05)
        plesio.zPosition = 1.6; plesio.colorBlendFactor = 1
        plesio.run(.repeatForever(.animate(with: plesioArt.frames, timePerFrame: 0.45)))
        addChild(plesio)

        // Volcano: steady smoke, a warm crater glow and the occasional (friendly) eruption.
        smoke.particleTexture = puffTex
        smoke.particleBirthRate = 0.45
        smoke.particleLifetime = 7; smoke.particleLifetimeRange = 1.5
        smoke.position = P(ex.crater.x, ex.crater.y + H * 0.01)
        smoke.particlePositionRange = CGVector(dx: ex.craterHW * 1.2, dy: 0)
        smoke.emissionAngle = .pi / 2; smoke.emissionAngleRange = 0.12
        smoke.particleSpeed = H * 0.028; smoke.particleSpeedRange = H * 0.006
        smoke.particleScale = ex.craterHW * 0.65 / 64; smoke.particleScaleRange = ex.craterHW * 0.2 / 64
        smoke.particleScaleSpeed = ex.craterHW * 0.06 / 64
        smoke.particleAlpha = 0.75; smoke.particleAlphaSpeed = -0.1
        smoke.particleRotationRange = .pi * 2
        smoke.particleColorBlendFactor = 1; smoke.particleColor = RGB(0x9A9490).sk
        smoke.zPosition = 1.25
        addChild(smoke)
        smoke.advanceSimulationTime(7)

        craterGlow.position = P(ex.crater.x, ex.crater.y)
        craterGlow.blendMode = .add; craterGlow.colorBlendFactor = 1; craterGlow.color = RGB(0xFF7A2A).sk
        craterGlow.zPosition = 1.2
        addChild(craterGlow)

        lava.particleTexture = Painter.glow(24)
        lava.particleBirthRate = 0
        lava.particleLifetime = 2.4; lava.particleLifetimeRange = 0.6
        lava.position = P(ex.crater.x, ex.crater.y)
        lava.particlePositionRange = CGVector(dx: ex.craterHW, dy: 0)
        lava.emissionAngle = .pi / 2; lava.emissionAngleRange = 0.55
        lava.particleSpeed = H * 0.16; lava.particleSpeedRange = H * 0.05
        lava.yAcceleration = -H * 0.15
        lava.particleScale = H * 0.012 / 24; lava.particleScaleRange = H * 0.005 / 24
        lava.particleAlphaSpeed = -0.25
        lava.particleColorBlendFactor = 1
        lava.particleColorSequence = SKKeyframeSequence(keyframeValues: [RGB(0xFFE07A).sk, RGB(0xFF8A2A).sk, RGB(0xC8401E).sk], times: [0, 0.5, 1])
        lava.particleBlendMode = .add
        lava.zPosition = 1.22
        addChild(lava)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Look

    func applyLook(ambient: RGB, night: Double, haze: RGB, wind: Double) {
        self.ambient = ambient; self.night = night; self.haze = haze
        (childNode(withName: "fg") as? SKSpriteNode)?.color = ambient.sk
        plesio.color = ambient.sk
        smoke.particleColor = RGB.mix(ambient, .white, 0.45).scaled(0.5 + 0.5 * ambient.luminance).sk
        smoke.xAcceleration = CGFloat(wind) * 0.25
        for b in bands { for w in b.walkers { tint(w, band: b) } }
        for (f, _) in flyers { (f.children.first as? SKSpriteNode)?.color = ambient.sk }
    }

    private func tint(_ w: Walker, band: Band) {
        let c = RGB.mix(ambient, haze, Double(1 - band.scale) * 0.25).sk
        for s in w.sprites { s.color = c }
    }

    // MARK: Motion

    func settle() {
        for i in bands.indices {
            var x = CGFloat.random(in: W * 0.02...W * 0.15)
            while x < W * 0.95 && bands[i].walkers.count < bands[i].max {
                let w = spawn(band: i)
                w.node.position.x = bands[i].dir > 0 ? x + w.back : W - x - w.back
                x += w.back + w.front + CGFloat.random(in: W * 0.08...W * 0.2)
            }
        }
        spawnFlyer(x: W * CGFloat.random(in: 0.2...0.6))
    }

    func update(_ dt: Double) {
        clock += dt
        let fdt = CGFloat(dt)
        for i in bands.indices {
            let b = bands[i]
            let v = b.speed * ex.ppm * b.scale * b.dir
            for w in b.walkers { w.node.position.x += v * fdt }
            bands[i].walkers.removeAll { w in
                let gone = b.dir > 0 ? w.node.position.x - w.back > W + 20 : w.node.position.x + w.back < -20
                if gone { w.node.removeFromParent() }
                return gone
            }
            // A newcomer enters once the last one has walked far enough in.
            let clear = bands[i].walkers.allSatisfy { w in
                b.dir > 0 ? w.node.position.x - w.back > bands[i].gap : w.node.position.x + w.back < W - bands[i].gap
            }
            if clear && bands[i].walkers.count < b.max {
                let w = spawn(band: i)
                w.node.position.x = b.dir > 0 ? -w.front - 10 : W + w.front + 10
            }
        }

        // Plesiosaur glides across the lake and back.
        let lake = ex.lake
        plesio.position.x += plesioDir * fdt * ex.ppm * 0.35
        let margin = lake.width * 0.22
        if plesio.position.x > lake.maxX - margin { plesioDir = -1 } else if plesio.position.x < lake.minX + margin { plesioDir = 1 }
        plesio.xScale = abs(plesio.xScale) * plesioDir
        plesio.position.y = lake.midY + lake.height * 0.05 + sin(CGFloat(clock) * 0.8) * 1.5

        // Pteranodons.
        nextFlyer -= dt
        if nextFlyer <= 0 { spawnFlyer(x: nil); nextFlyer = Double.random(in: 14...32) }
        for (f, v) in flyers {
            f.position.x += v * fdt
            f.position.y += sin(CGFloat(clock) * 0.9 + f.position.x * 0.01) * 0.25
        }
        flyers.removeAll { f, _ in
            let gone = f.position.x < -150 || f.position.x > W + 150
            if gone { f.removeFromParent() }
            return gone
        }

        // Volcano.
        let pulse = 0.5 + 0.5 * sin(clock * 0.7)
        craterGlow.alpha = CGFloat(0.25 + night * 0.45 + pulse * 0.1 + min(1, erupting) * 0.4)
        nextEruption -= dt
        if nextEruption <= 0 {
            erupting = 3
            nextEruption = Double.random(in: 50...120)
        }
        if erupting > 0 {
            erupting -= dt
            lava.particleBirthRate = erupting > 0.8 ? 70 : 0
            smoke.particleBirthRate = 1.2
        } else {
            lava.particleBirthRate = 0
            smoke.particleBirthRate = 0.45
        }
    }

    // MARK: Spawning

    private func spawn(band i: Int) -> Walker {
        let b = bands[i]
        // Pick a kind that hasn't walked by in this band lately, so all of them take turns.
        let pool = Dino.allCases.filter { !b.recent.contains($0) }
        let d = pool.randomElement() ?? .trex
        bands[i].recent.append(d)
        if bands[i].recent.count > 7 { bands[i].recent.removeFirst() }

        let w = Walker()
        let art = arts[d]!
        func add(_ k: CGFloat, offset: CGFloat) {
            let s = SKSpriteNode(texture: art.frames[0], size: CGSize(width: art.size.width * k, height: art.size.height * k))
            s.anchorPoint = art.anchor
            s.position = P(offset, 0)
            s.colorBlendFactor = 1
            let metresPerSec = b.speed
            let cycleMetres = art.cycle * k
            let tpf = Double(max(0.06, min(0.35, cycleMetres / metresPerSec / 8)))
            s.run(.repeatForever(.animate(with: art.frames, timePerFrame: tpf)), withKey: "walk")
            let sh = SKSpriteNode(texture: shadowTex, size: CGSize(width: s.size.width * 0.7, height: s.size.height * 0.08 + 4))
            sh.position = P(offset, 0); sh.alpha = 0.18; sh.zPosition = -0.01
            w.node.addChild(sh)
            w.node.addChild(s)
            w.sprites.append(s)
        }
        add(b.scale, offset: 0)
        let half = art.size.width * b.scale / 2
        w.front = half; w.back = half
        if d.hasBabies && Bool.random() {
            let k = b.scale * 0.42
            let off = -(half + art.size.width * k * 0.5 + ex.ppm * b.scale * 0.4)
            add(k, offset: off)
            w.back = -off + art.size.width * k / 2
        }
        w.node.xScale = b.dir
        w.node.position.y = b.y
        w.node.zPosition = b.z + CGFloat(Int.random(in: 0..<50)) * 0.001
        addChild(w.node)
        bands[i].walkers.append(w)
        bands[i].gap = CGFloat.random(in: W * 0.06...W * 0.22)
        tint(w, band: bands[i])
        return w
    }

    private func spawnFlyer(x: CGFloat?) {
        let n = Int.random(in: 1...3)
        let dir: CGFloat = Bool.random() ? 1 : -1
        let y0 = H * CGFloat.random(in: 0.68...0.88)
        let v = dir * CGFloat.random(in: 45...75)
        for k in 0..<n {
            let node = SKNode()
            let s = SKSpriteNode(texture: ptero.frames[0], size: ptero.size)
            let scale = CGFloat.random(in: 1.0...1.3) * (k == 0 ? 1 : 0.8)
            s.size = CGSize(width: ptero.size.width * scale, height: ptero.size.height * scale)
            s.colorBlendFactor = 1; s.color = ambient.sk
            s.run(.repeatForever(.animate(with: ptero.frames, timePerFrame: Double.random(in: 0.09...0.12))))
            node.addChild(s)
            node.xScale = dir
            let startX = x ?? (dir > 0 ? -60 : W + 60)
            node.position = P(startX - dir * CGFloat(k) * ptero.size.width * 1.1, y0 + CGFloat(k) * H * 0.03 * (k % 2 == 0 ? 1 : -1))
            node.zPosition = 1.3
            addChild(node)
            flyers.append((node, v))
        }
    }
}
