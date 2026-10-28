import SpriteKit

/// One of the perspective views (aerial canal, Gulshan lake, Lalbagh gardens, panorama).
/// Shares the sky, weather and lighting of `CityScene`; owns its ground art and everything that moves on it.
final class ScenicView: SKNode {
    let kind: ViewKind
    let art: ViewArt
    var horizon: CGFloat { art.cam.horizon }
    /// Where the sky has to reach down to (the drawn ground stops here).
    var skyBottom: CGFloat { min(horizon, art.groundTop) }
    private let W: CGFloat, H: CGFloat

    private let water = SKSpriteNode()
    private let wFar = SKUniform(name: "u_far", vectorFloat4: .zero), wNear = SKUniform(name: "u_near", vectorFloat4: .zero)
    private let wGlow = SKUniform(name: "u_glow", vectorFloat4: .zero), wSun = SKUniform(name: "u_sun", vectorFloat2: .zero)
    private let wMoon = SKUniform(name: "u_moon", vectorFloat2: .zero), wRough = SKUniform(name: "u_rough", float: 0)
    private let ground: SKSpriteNode, lights: SKSpriteNode
    private let far: SKSpriteNode, farLights: SKSpriteNode
    private let haze = SKSpriteNode()
    private let ripples = SKEmitterNode()
    private var fountains: [SKEmitterNode] = []

    private final class Mover {
        let node = SKNode()
        let body: SKSpriteNode
        var s: CGFloat
        let v: CGFloat
        var glows: [(SKSpriteNode, CGFloat)] = []
        init(body: SKSpriteNode, s: CGFloat, v: CGFloat) { self.body = body; self.s = s; self.v = v }
    }
    private var movers: [[Mover]]
    private var spawnClock: [Double]
    private let glowTex = Painter.glow(32)
    private var carTex: [SKTexture] = []
    private var boatTex: SKTexture!, wakeTex: SKTexture!
    private var rowboats: [(PropArt, CGPoint)] = []
    private var walkers: [([SKTexture], CGSize)] = [], umbrellaWalkers: [([SKTexture], CGSize)] = []
    private var plane: SKNode?
    private var nextPlane = 25.0
    private var ambient = RGB.white, night = 0.0, hazeColor = RGB.white
    private var rainy = false
    private var dinos: DinoLife?

    init(kind: ViewKind, size: CGSize, seed: UInt64) {
        self.kind = kind
        W = size.width; H = size.height
        switch kind {
        case .hatirjheel: art = ArtViews.hatirjheel(W: W, H: H, seed: seed)
        case .gulshan: art = ArtViews.gulshanLake(W: W, H: H, seed: seed)
        case .lalbagh: art = ArtViews.lalbagh(W: W, H: H, seed: seed)
        case .dhanmondi: art = ArtViews.dhanmondi(W: W, H: H, seed: seed)
        case .cefalo: art = ArtViews.cefalo(W: W, H: H, seed: seed)
        case .dinos: art = ArtDinos.world(W: W, H: H, seed: seed)
        default: art = ArtViews.panorama(W: W, H: H, seed: seed)
        }
        ground = SKSpriteNode(texture: Painter.texture(art.base), size: size)
        lights = SKSpriteNode(texture: Painter.texture(art.lights), size: size)
        let farArt = ArtCity.farSkyline(width: W, height: H * max(0.01, art.skyline), seed: seed + 3)
        far = SKSpriteNode(texture: farArt.base, size: farArt.size)
        farLights = SKSpriteNode(texture: farArt.lights, size: farArt.size)
        movers = Array(repeating: [], count: art.lanes.count)
        spawnClock = Array(repeating: 0, count: art.lanes.count)
        super.init()
        build(seed: seed)
    }

    required init?(coder: NSCoder) { fatalError() }

    private func build(seed: UInt64) {
        let white = Painter.texture(CGSize(width: 2, height: 2), scale: 1) { $0.fillGray(1, 1, R(0, 0, 2, 2)) }
        if art.hasWater {
            water.texture = white
            water.size = CGSize(width: W, height: art.groundTop + 2)
            water.anchorPoint = .zero; water.zPosition = 0
            water.shader = SKShader(source: Shaders.water, uniforms: [wFar, wNear, wGlow, wSun, wMoon, wRough,
                                                                      SKUniform(name: "u_aspect", float: Float(W / art.groundTop))])
            addChild(water)
        }
        for (n, z) in [(far, 0.2), (farLights, 0.25)] as [(SKSpriteNode, CGFloat)] {
            n.anchorPoint = P(0, 0); n.position = P(0, art.groundTop - 3); n.zPosition = z; n.colorBlendFactor = 1
            if art.skyline > 0 { addChild(n) }
        }
        farLights.blendMode = .add
        for (n, z) in [(ground, 1.0), (lights, 1.1)] as [(SKSpriteNode, CGFloat)] {
            n.anchorPoint = .zero; n.zPosition = z; n.colorBlendFactor = 1
            addChild(n)
        }
        lights.blendMode = .add
        lights.color = .white; farLights.color = .white  // texture sprites default to a clear tint
        // Haze peaks at the far ground line and fades both down over the city and up over the tallest towers.
        let below = H * art.hazeDepth, above = H * 0.07
        let peak = Double(below / (below + above))
        haze.texture = Painter.texture(CGSize(width: 4, height: 256), scale: 1) { ctx in
            for y in 0..<256 {
                let t = Double(y) / 255
                let a = t < peak ? pow(t / peak, 1.5) : pow((1 - t) / (1 - peak), 1.3)
                ctx.fillGray(1, a, R(0, CGFloat(y), 4, 1))
            }
        }
        haze.size = CGSize(width: W, height: below + above)
        haze.anchorPoint = .zero; haze.position = P(0, art.groundTop - below); haze.zPosition = 3
        haze.colorBlendFactor = 1
        if art.hazeDepth > 0 { addChild(haze) }

        if let rr = art.rippleRect {
            ripples.particleTexture = ArtSky.ripple()
            ripples.particleBirthRate = 0
            ripples.particleLifetime = 0.7
            ripples.position = P(rr.midX, rr.midY)
            ripples.particlePositionRange = CGVector(dx: rr.width, dy: rr.height)
            ripples.particleAlpha = 0.5; ripples.particleAlphaSpeed = -0.7
            ripples.particleScale = 0.08; ripples.particleScaleRange = 0.05; ripples.particleScaleSpeed = 0.6
            ripples.particleColorBlendFactor = 1; ripples.particleColor = .white
            ripples.zPosition = 0.5
            addChild(ripples)
        }
        let drop = Painter.glow(16)
        for (pt, s) in art.fountains {
            let e = SKEmitterNode()
            e.particleTexture = drop
            e.particleBirthRate = 70
            e.particleLifetime = 0.8; e.particleLifetimeRange = 0.2
            e.position = pt
            e.emissionAngle = .pi / 2; e.emissionAngleRange = 0.18
            e.particleSpeed = 3.4 * s; e.particleSpeedRange = 0.6 * s
            e.yAcceleration = -9.8 * s
            e.particleScale = max(0.08, 0.16 * s / 16); e.particleScaleRange = 0.04
            e.particleAlpha = 0.75; e.particleAlphaSpeed = -0.6
            e.particleColorBlendFactor = 1; e.particleColor = RGB(0xE6F4FF).sk
            e.zPosition = 1.5
            addChild(e)
            fountains.append(e)
        }

        // Mover art.
        let carColors = [RGB(0xE8E8E6), RGB(0xB9BDC2), RGB(0x3A3F48), RGB(0xB23A35), RGB(0x2C5A8E), RGB(0x3E8B57), RGB(0xE0B23A)]
        carTex = carColors.map { c in
            Painter.texture(CGSize(width: 2.0, height: 1.8), scale: 24) { ctx in
                ctx.fillEllipse(RGB(0x1A1A1E), 1, R(0.15, 0, 0.4, 0.3)); ctx.fillEllipse(RGB(0x1A1A1E), 1, R(1.45, 0, 0.4, 0.3))
                ctx.addPath(CGPath(roundedRect: R(0.05, 0.15, 1.9, 0.85), cornerWidth: 0.2, cornerHeight: 0.2, transform: nil))
                ctx.setFillColor(c.cg()); ctx.fillPath()
                ctx.addPath(CGPath(roundedRect: R(0.3, 0.9, 1.4, 0.75), cornerWidth: 0.25, cornerHeight: 0.25, transform: nil))
                ctx.setFillColor(c.lighter(0.15).cg()); ctx.fillPath()
                ctx.fill(RGB(0x2D3A4A), 1, R(0.38, 0.95, 1.24, 0.3))
                ctx.fill(c.darker(0.25), 1, R(0.05, 0.15, 1.9, 0.12))
            }
        }
        boatTex = Painter.texture(CGSize(width: 2.8, height: 1.9), scale: 24) { ctx in
            ctx.fillPath(RGB(0x4A3628), 1, CGPath.poly([P(0, 0.55), P(2.8, 0.55), P(2.4, 0), P(0.4, 0)]))
            ctx.fill(RGB(0x7A5A40), 1, R(0.1, 0.45, 2.6, 0.12))
            let c = CGMutablePath(); c.addArc(center: P(1.4, 0.6), radius: 0.95, startAngle: 0, endAngle: .pi, clockwise: false); c.closeSubpath()
            ctx.fillPath(RGB(0x2F6FA8), 1, c)
            ctx.fillEllipse(RGB(0x1E2A35), 1, R(0.95, 0.6, 0.9, 0.6))
        }
        wakeTex = Painter.texture(CGSize(width: 10, height: 8), scale: 6) { ctx in
            ctx.strokeLine(.white, 0.5, width: 0.25, [P(4.6, 8), P(0.5, 0)])
            ctx.strokeLine(.white, 0.5, width: 0.25, [P(5.4, 8), P(9.5, 0)])
        }
        var rng = SeededRNG(seed: seed + 91)
        if art.lanes.contains(where: { $0.kind == .rowboat }) {
            rowboats = (0..<3).map { _ in ArtProps.boat(ppm: 24, rng: &rng) }
        }
        if art.lanes.contains(where: { $0.kind == .walker }) {
            walkers = (0..<8).map { _ in ArtProps.walker(ppm: 24, rng: &rng, umbrella: false) }
            umbrellaWalkers = (0..<6).map { _ in ArtProps.walker(ppm: 24, rng: &rng, umbrella: true) }
        }
        if let f = art.front {
            // Buildings that stand in front of the road, laid over the traffic so cars pass behind them.
            for (img, z, add) in [(f.base, 2.95, false), (f.lights, 2.96, true)] as [(CGImage, CGFloat, Bool)] {
                let n = SKSpriteNode(texture: Painter.texture(img), size: CGSize(width: W, height: H))
                n.anchorPoint = .zero; n.zPosition = z; n.colorBlendFactor = 1
                n.name = add ? "frontLights" : "front"
                if add { n.blendMode = .add; n.color = .white }
                addChild(n)
            }
        }
        if let ex = art.dino {
            let life = DinoLife(ex, size: CGSize(width: W, height: H))
            addChild(life)
            dinos = life
        }
    }

    // MARK: Look

    private func mul(_ a: RGB, _ b: RGB) -> RGB { RGB(a.r * b.r, a.g * b.g, a.b * b.b) }

    func applyLook(_ L: Look, weather: WeatherParams, wet: Double, sunX: CGFloat, moonX: CGFloat, time: Double) {
        ambient = L.ambient; night = L.night; hazeColor = L.hor
        rainy = weather.rain > 0.15
        ground.color = L.ambient.sk
        (childNode(withName: "front") as? SKSpriteNode)?.color = L.ambient.sk
        if let fl = childNode(withName: "frontLights") as? SKSpriteNode { fl.alpha = CGFloat(L.night); fl.isHidden = L.night < 0.01 }
        dinos?.applyLook(ambient: L.ambient, night: L.night, haze: L.hor, wind: weather.wind)
        lights.alpha = CGFloat(L.night); lights.isHidden = L.night < 0.01
        far.color = L.far.sk
        farLights.alpha = CGFloat(L.night * 0.8)
        haze.color = L.hor.sk
        haze.alpha = CGFloat(min(0.85, 0.25 + L.hazeAlpha * 0.6))
        if art.hasWater {
            let tint = mul(art.waterTint ?? L.waterFar, L.ambient)
            wFar.vectorFloat4Value = RGB.mix(L.waterFar, tint, 0.45).v4()
            wNear.vectorFloat4Value = RGB.mix(L.waterNear, tint.scaled(0.8), 0.6).v4()
            wGlow.vectorFloat4Value = L.glow.v4(L.glowStrength * 0.7)
            wSun.vectorFloat2Value = SIMD2(Float(sunX), Float(L.sunAlpha * 0.6))
            wMoon.vectorFloat2Value = SIMD2(Float(moonX), Float(L.moonAlpha * 0.6))
            wRough.floatValue = Float(min(1, weather.rain + abs(weather.wind) / 60))
        }
        ripples.particleBirthRate = weather.rain < 0.02 ? 0 : CGFloat(220 * weather.rain)
        ripples.particleColor = RGB.mix(L.waterFar, .white, 0.5).sk
        for f in fountains {
            f.particleColor = RGB.mix(L.ambient, .white, 0.4).sk
            f.particleBirthRate = weather.storm > 0.5 ? 0 : 70
        }
    }

    // MARK: Motion

    func update(dt: Double, density: Double, showTraffic: Bool, showPeople: Bool, showBoats: Bool) {
        for (i, lane) in art.lanes.enumerated() {
            let enabled: Bool
            switch lane.kind {
            case .car: enabled = showTraffic
            case .boat, .rowboat: enabled = showBoats
            case .walker: enabled = showPeople
            }
            if !enabled { movers[i].forEach { $0.node.removeFromParent() }; movers[i].removeAll(); continue }
            let target = max(1, Int((Double(lane.count) * density).rounded()))
            spawnClock[i] -= dt
            if spawnClock[i] <= 0 && movers[i].count < target {
                let gap = lane.length / CGFloat(lane.count) * 0.45
                if movers[i].allSatisfy({ $0.s > gap }) { spawn(lane: i, s: 0) }
                spawnClock[i] = Double.random(in: 1...4)
            }
            for m in movers[i] { m.s += m.v * CGFloat(dt); place(m, lane) }
            movers[i].removeAll { m in
                let done = m.s >= lane.length
                if done { m.node.removeFromParent() }
                return done
            }
        }
        updatePlane(dt)
        dinos?.update(dt)
    }

    func settle(density: Double, showTraffic: Bool, showPeople: Bool, showBoats: Bool) {
        dinos?.settle()
        for (i, lane) in art.lanes.enumerated() {
            let ok = lane.kind == .car ? showTraffic : (lane.kind == .boat || lane.kind == .rowboat) ? showBoats : showPeople
            guard ok else { continue }
            let n = max(1, Int((Double(lane.count) * density).rounded()))
            for k in 0..<n { spawn(lane: i, s: lane.length * (CGFloat(k) + CGFloat.random(in: 0.1...0.8)) / CGFloat(n)) }
        }
    }

    private func spawn(lane i: Int, s: CGFloat) {
        let lane = art.lanes[i]
        let body: SKSpriteNode
        let v = CGFloat.random(in: lane.speed)
        let m: Mover
        switch lane.kind {
        case .car:
            body = SKSpriteNode(texture: carTex.randomElement(), size: CGSize(width: 2.0, height: 1.8))
            body.anchorPoint = P(0.5, 0)
            m = Mover(body: body, s: s, v: v)
            for x in [-0.62, 0.62] as [CGFloat] {
                let g = SKSpriteNode(texture: glowTex, size: CGSize(width: 1.0, height: 1.0))
                g.position = P(x, 0.55); g.blendMode = .add; g.colorBlendFactor = 1
                g.color = lane.toward ? RGB(0xFFF1D0).sk : RGB(0xFF3A2E).sk
                g.zPosition = 0.1
                m.node.addChild(g); m.glows.append((g, 1))
            }
        case .boat:
            body = SKSpriteNode(texture: boatTex, size: CGSize(width: 2.8, height: 1.9))
            body.anchorPoint = P(0.5, 0.1)
            m = Mover(body: body, s: s, v: v)
            let wake = SKSpriteNode(texture: wakeTex, size: CGSize(width: 10, height: 8))
            wake.anchorPoint = P(0.5, 1); wake.position = P(0, 0.4); wake.zPosition = -0.1; wake.alpha = 0.7
            if lane.toward { wake.yScale = -1; wake.position = P(0, 0.6) }
            m.node.addChild(wake)
            let lantern = SKSpriteNode(texture: glowTex, size: CGSize(width: 1.6, height: 1.6))
            lantern.position = P(0, 1.2); lantern.blendMode = .add; lantern.colorBlendFactor = 1; lantern.color = RGB(0xFFB45A).sk
            m.node.addChild(lantern); m.glows.append((lantern, 1))
        case .rowboat:
            let (b, lanternPt) = rowboats.randomElement()!
            let k: CGFloat = 0.6 / 24  // a smaller lake boat
            body = SKSpriteNode(texture: b.texture, size: CGSize(width: b.size.width * k, height: b.size.height * k))
            body.anchorPoint = P(0.5, 0.05)
            m = Mover(body: body, s: s, v: v)
            let a = lane.point(0), e = lane.point(1)
            if art.cam.p(e.x, e.y, e.z).x < art.cam.p(a.x, a.y, a.z).x { m.node.xScale = -1 }
            let refl = SKSpriteNode(texture: b.texture, size: body.size)
            refl.anchorPoint = P(0.5, 0.05); refl.yScale = -0.7; refl.alpha = 0.25; refl.colorBlendFactor = 1; refl.color = .black
            m.node.addChild(refl)
            let lantern = SKSpriteNode(texture: glowTex, size: CGSize(width: 1.2, height: 1.2))
            lantern.position = P(-body.size.width / 2 + lanternPt.x * k, lanternPt.y * k)
            lantern.blendMode = .add; lantern.colorBlendFactor = 1; lantern.color = RGB(0xFFB45A).sk
            m.node.addChild(lantern); m.glows.append((lantern, 1))
        case .walker:
            let pool = rainy && !umbrellaWalkers.isEmpty ? umbrellaWalkers : walkers
            let (frames, sz) = pool.randomElement()!
            body = SKSpriteNode(texture: frames[0], size: CGSize(width: sz.width / 24, height: sz.height / 24))
            body.anchorPoint = P(0.5, 0.02)
            body.run(.repeatForever(.animate(with: frames, timePerFrame: Double(1.5 / v) / Double(frames.count))))
            m = Mover(body: body, s: s, v: v)
            let a = lane.point(0), b = lane.point(1)
            body.xScale = (art.cam.p(b.x, b.y, b.z).x - art.cam.p(a.x, a.y, a.z).x) >= 0 ? 1 : -1
        }
        body.colorBlendFactor = 1
        m.node.addChild(body)
        addChild(m.node)
        movers[i].append(m)
        place(m, lane)
    }

    private func place(_ m: Mover, _ lane: Lane) {
        let q = lane.point(m.s)
        let cam = art.cam
        m.node.position = cam.p(q.x, q.y, q.z)
        let k = cam.scale(q.y, q.z)
        m.node.xScale = m.node.xScale < 0 ? -k : k  // keep a boat's facing
        m.node.yScale = k
        m.node.zPosition = 2 + min(0.9, 30 / max(1, q.z))
        var a: CGFloat = 1
        if lane.fadeIn > 0 { a = min(a, m.s / lane.fadeIn) }
        if lane.fadeOut > 0 { a = min(a, (lane.length - m.s) / lane.fadeOut) }
        let hz = CGFloat(smoothstep(500, 2200, Double(q.z)))
        m.node.alpha = max(0, min(1, a)) * (1 - hz * 0.7)
        m.node.isHidden = k < 0.15 || m.node.alpha < 0.02
        m.body.color = RGB.mix(ambient, hazeColor, Double(hz) * 0.5).sk
        for (g, ga) in m.glows { g.alpha = CGFloat(night) * ga; g.isHidden = night < 0.02 }
    }

    // MARK: A plane crossing the sky now and then

    private func updatePlane(_ dt: Double) {
        guard art.planes, Settings.shared.showPlanes else {
            plane?.removeFromParent(); plane = nil
            return
        }
        if let p = plane {
            p.position.x -= CGFloat(dt) * 22
            if let blink = p.childNode(withName: "blink") { blink.alpha = CGFloat(night) * (sin(CGFloat(nextPlane) * 9) > 0.6 ? 1 : 0.15) }
            nextPlane += dt
            if p.position.x < -60 { p.removeFromParent(); plane = nil; nextPlane = Double.random(in: 60...180) }
            return
        }
        nextPlane -= dt
        guard nextPlane <= 0 else { return }
        let n = SKNode()
        let body = SKSpriteNode(texture: Painter.texture(CGSize(width: 34, height: 12)) { ctx in
            ctx.fill(RGB(0xF2F2F4), 1, R(2, 5, 30, 3))
            ctx.fillPath(RGB(0xF2F2F4), 1, CGPath.poly([P(14, 6), P(20, 6), P(12, 0), P(9, 0)]))
            ctx.fillPath(RGB(0xF2F2F4), 1, CGPath.poly([P(28, 6), P(32, 6), P(33, 12), P(30, 12)]))
        }, size: CGSize(width: 34, height: 12))
        body.colorBlendFactor = 1; body.color = RGB.mix(ambient, .white, 0.3).sk
        n.addChild(body)
        let blink = SKSpriteNode(texture: glowTex, size: CGSize(width: 10, height: 10))
        blink.name = "blink"; blink.blendMode = .add; blink.colorBlendFactor = 1; blink.color = RGB(0xFF4A3A).sk
        blink.position = P(-14, 0)
        n.addChild(blink)
        n.position = P(W + 40, horizon + (H - horizon) * CGFloat.random(in: 0.25...0.6))
        n.zPosition = 0.15
        addChild(n)
        plane = n
        nextPlane = 0
    }
}
