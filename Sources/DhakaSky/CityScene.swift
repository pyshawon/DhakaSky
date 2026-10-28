import SpriteKit

// MARK: - Shaders

enum Shaders {
    static let sky = """
    void main() {
        vec2 uv = v_tex_coord;
        float t = uv.y;
        vec3 c = mix(u_hor.rgb, u_mid.rgb, smoothstep(0.0, 0.5, t));
        c = mix(c, u_top.rgb, smoothstep(0.35, 1.0, t));
        vec2 p = vec2(uv.x * u_aspect, uv.y);
        vec2 s = vec2(u_sun.x * u_aspect, u_sun.y);
        float d = distance(p, s);
        c += u_glow.rgb * u_glow.a * (exp(-d * 3.2) * 0.45 + exp(-d * 12.0) * 0.5);
        c += u_glow.rgb * u_glow.a * 0.35 * exp(-t * 5.0) * exp(-abs(uv.x - u_sun.x) * 1.4);
        c += u_city.rgb * u_city.a * exp(-t * 6.0);
        float r = fract(sin(dot(uv * 1000.0, vec2(12.9898, 78.233))) * 43758.5453);
        c += (r - 0.5) / 255.0;
        gl_FragColor = vec4(c, 1.0);
    }
    """

    static let water = """
    void main() {
        vec2 uv = v_tex_coord;
        float t = uv.y;
        vec3 c = mix(u_near.rgb, u_far.rgb, pow(t, 0.7));
        float depth = 1.0 / (1.06 - t);
        float n = sin(uv.x * 23.0 + depth * 2.0 + u_time * 0.35) * 0.5 + sin(uv.x * 61.0 - depth * 3.1 + u_time * 0.6) * 0.5;
        float band = sin(depth * 9.0 + n * (1.3 + u_rough * 2.5) - u_time * 0.9);
        float hi = smoothstep(0.55, 1.0, band);
        c = mix(c, u_far.rgb * 1.25 + 0.02, hi * (0.10 + 0.08 * u_rough) * (0.4 + 0.6 * t));
        c *= 1.0 - smoothstep(-0.55, -1.0, band) * 0.06;
        float glit = smoothstep(0.3, 1.0, band) * 0.8 + 0.2;
        float dx = abs(uv.x - u_sun.x) * u_aspect;
        float w = 0.012 + (1.0 - t) * 0.08;
        c += u_glow.rgb * u_glow.a * exp(-(dx * dx) / (w * w)) * glit * (0.3 + 0.7 * t) * u_sun.y;
        float mdx = abs(uv.x - u_moon.x) * u_aspect;
        float mw = 0.008 + (1.0 - t) * 0.04;
        c += vec3(0.85, 0.88, 0.95) * u_moon.y * exp(-(mdx * mdx) / (mw * mw)) * glit * 0.5;
        float r = fract(sin(dot(uv * 1000.0, vec2(12.9898, 78.233))) * 43758.5453);
        c += (r - 0.5) / 255.0;
        gl_FragColor = vec4(c, 1.0);
    }
    """

    /// Mirror images on the lake: wobble, horizontal break-up, and fade with distance from the bank.
    static let reflection = """
    void main() {
        vec2 uv = v_tex_coord;
        float k = uv.y;
        uv.x += sin(uv.y * u_freq + u_time * 1.8) * u_amp * (0.3 + k * 1.6);
        vec4 c = texture2D(u_texture, uv);
        float stripes = 0.7 + 0.3 * sin(uv.y * u_freq * 2.7 - u_time * 2.2 + sin(uv.x * 30.0) * 1.2);
        float fade = 1.0 - smoothstep(0.0, 0.9, k);
        gl_FragColor = vec4(c.rgb * u_tint.rgb, c.a) * u_tint.a * stripes * (0.2 + 0.8 * fade);
    }
    """
}

private final class Reflection {
    let node: SKSpriteNode
    let tint = SKUniform(name: "u_tint", vectorFloat4: SIMD4(1, 1, 1, 0.4))
    init(texture: SKTexture, size: CGSize, amp: CGFloat, additive: Bool) {
        node = SKSpriteNode(texture: texture, size: size)
        node.anchorPoint = P(0.5, 0)
        node.yScale = -1
        if additive { node.blendMode = .add }
        let freq = Float(size.height / 3.2)
        node.shader = SKShader(source: Shaders.reflection, uniforms: [
            tint, SKUniform(name: "u_amp", float: Float(amp / size.width)), SKUniform(name: "u_freq", float: freq),
        ])
    }
}

// MARK: - Moving things

private final class Vehicle {
    let root = SKNode()
    let body: SKSpriteNode
    var wheels: [(SKSpriteNode, CGFloat)] = []
    var nightNodes: [(SKSpriteNode, CGFloat)] = []   // node, max alpha
    var wetNodes: [SKSpriteNode] = []
    var rider: SKSpriteNode?
    var riderFrames: [SKTexture] = []
    var riderPhase: CGFloat = 0
    var riderIndex = -1
    let lane: Int
    var x: CGFloat
    let desired: CGFloat
    var v: CGFloat
    let halfW: CGFloat
    init(body: SKSpriteNode, lane: Int, x: CGFloat, speed: CGFloat, halfW: CGFloat) {
        self.body = body; self.lane = lane; self.x = x; desired = speed; v = speed; self.halfW = halfW
    }
}

private final class Walker {
    let node: SKSpriteNode
    var x: CGFloat
    let v: CGFloat
    init(node: SKSpriteNode, x: CGFloat, v: CGFloat) { self.node = node; self.x = x; self.v = v }
}

private final class Boat {
    let root = SKNode()
    let body: SKSpriteNode
    let refl: SKSpriteNode
    let lantern: SKSpriteNode
    var x: CGFloat
    let y: CGFloat, v: CGFloat, depth: CGFloat, phase: Double, halfW: CGFloat
    init(body: SKSpriteNode, refl: SKSpriteNode, lantern: SKSpriteNode, x: CGFloat, y: CGFloat, v: CGFloat, depth: CGFloat, halfW: CGFloat) {
        self.body = body; self.refl = refl; self.lantern = lantern
        self.x = x; self.y = y; self.v = v; self.depth = depth; self.halfW = halfW
        phase = Double.random(in: 0...6)
    }
}

private final class Cloud {
    let node: SKSpriteNode
    let rank: Double, speed: CGFloat, baseAlpha: CGFloat
    var frac: CGFloat = 0.5   // height within the sky band
    init(node: SKSpriteNode, rank: Double, speed: CGFloat, baseAlpha: CGFloat) {
        self.node = node; self.rank = rank; self.speed = speed; self.baseAlpha = baseAlpha
    }
}

// MARK: - Scene

final class CityScene: SKScene {
    var clock: () -> Date = { Date() }
    /// Fired on each lightning strike; `true` when a bolt is visible (a close strike).
    var onLightning: ((Bool) -> Void)?
    var weatherTarget = WeatherParams()
    private(set) var weather = WeatherParams()
    private var wet = 0.0
    private var sunEl = 30.0, sunAz = 180.0, moonEl = -30.0, moonAz = 180.0, phase = 0.5
    private var moonPhaseDrawn = -1.0
    private var look = Look.interpolateClear(30)
    private var lastUpdate: TimeInterval = 0
    private var time: Double = 0
    private var landmarkID = ""
    private var riverView = false   // Padma: the city recedes to a faint far shore

    let W: CGFloat, H: CGFloat
    var yShore: CGFloat { H * 0.36 }
    var yWater: CGFloat { H * 0.15 }
    var ppm: CGFloat { H * 0.0185 }
    private let calm: CGFloat = 0.55  // slows traffic to a relaxed pace
    private var seed: UInt64 { UInt64(W) &* 31 &+ UInt64(H) }

    // Layers
    private let cityRoot = SKNode()     // the lakeside view
    private let skyRoot = SKNode()      // sky shared by every view
    private var scenic: ScenicView?
    private var viewID: ViewKind?
    private var horizon: CGFloat = 0
    private let uSkyAspect = SKUniform(name: "u_aspect", float: 1)
    private let sky = SKSpriteNode()
    private let uTop = SKUniform(name: "u_top", vectorFloat4: .zero), uMid = SKUniform(name: "u_mid", vectorFloat4: .zero)
    private let uHor = SKUniform(name: "u_hor", vectorFloat4: .zero), uGlow = SKUniform(name: "u_glow", vectorFloat4: .zero)
    private let uSun = SKUniform(name: "u_sun", vectorFloat2: .zero), uCity = SKUniform(name: "u_city", vectorFloat4: .zero)
    private let water = SKSpriteNode()
    private let wFar = SKUniform(name: "u_far", vectorFloat4: .zero), wNear = SKUniform(name: "u_near", vectorFloat4: .zero)
    private let wGlow = SKUniform(name: "u_glow", vectorFloat4: .zero), wSun = SKUniform(name: "u_sun", vectorFloat2: .zero)
    private let wMoon = SKUniform(name: "u_moon", vectorFloat2: .zero), wRough = SKUniform(name: "u_rough", float: 0)

    private var stars = SKSpriteNode(), sun = SKSpriteNode(), sunHalo = SKSpriteNode()
    private var moon = SKSpriteNode(), moonHalo = SKSpriteNode()
    private var stratus = SKSpriteNode()
    private var clouds: [Cloud] = []
    private var bolt = SKSpriteNode()
    private var boltTextures: [SKTexture] = []
    private var cityGlow = SKSpriteNode()
    private var far = SKSpriteNode(), farLights = SKSpriteNode()
    private var near = SKSpriteNode(), nearLights = SKSpriteNode()
    private var landmark: SKSpriteNode?, landmarkLights: SKSpriteNode?
    private var beacons: [(SKSpriteNode, Double)] = []
    private var greenLights: [SKSpriteNode] = []
    private var hazeA = SKSpriteNode(), hazeB = SKSpriteNode()
    private var reflections: [(Reflection, Int)] = []  // kind: 0 far, 1 near, 2 landmark, 3 lights
    private var nearReflections: [(Reflection, Int)] = []
    private var landmarkReflections: [(Reflection, Int)] = []
    private var road = SKSpriteNode(), roadWet = SKSpriteNode()
    private var lamps: [SKSpriteNode] = []
    private var lampGlows: [(SKSpriteNode, CGFloat)] = []
    private var lampWet: [SKSpriteNode] = []
    private var tree: SKSpriteNode?, palm: SKSpriteNode?
    private var treeBloom = -1.0
    private let rainFar = SKEmitterNode(), rainNear = SKEmitterNode()
    private let ripples = SKEmitterNode(), roadRipples = SKEmitterNode()
    private var fogBands: [SKSpriteNode] = []
    private let flash = SKSpriteNode(), grain = SKSpriteNode(), vignette = SKSpriteNode(), dimmer = SKSpriteNode()
    private var backdrop: SKSpriteNode?

    private var vehiclePool: [VehicleArt.Kind: [VehicleArt]] = [:]
    private var vehicles: [Vehicle] = []
    private var nextSpawn: [Double] = [0, 0]
    private var boatArt: [(PropArt, CGPoint)] = []
    private var boats: [Boat] = []
    private var nextBoat = 0.0
    private var walkerArt: [([SKTexture], CGSize)] = []
    private var umbrellaArt: [([SKTexture], CGSize)] = []
    private var walkers: [Walker] = []
    private var nextWalker = 0.0
    private var birdFrames: [SKTexture] = []
    private var flocks: [(SKNode, CGFloat)] = []
    private var nextFlock = 20.0
    private var nextLightning = 4.0
    private var glowTex = Painter.glow(64)

    /// Pixels per point of this scene's screen. `Painter.scale` is shared by every scene, so each scene sets it
    /// back to its own value before drawing new art (screens can differ, e.g. a Retina laptop and a 1x display).
    private let pixelScale: CGFloat

    init(size: CGSize, scale: CGFloat) {
        W = size.width; H = size.height
        pixelScale = scale
        Painter.scale = scale
        super.init(size: size)
        anchorPoint = .zero
        scaleMode = .resizeFill
        backgroundColor = .black
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Build

    private func sprite(_ tex: SKTexture?, _ size: CGSize, z: CGFloat, anchor: CGPoint = .zero, at p: CGPoint = .zero, parent: SKNode? = nil) -> SKSpriteNode {
        let s = SKSpriteNode(texture: tex, size: size)
        s.anchorPoint = anchor; s.position = p; s.zPosition = z
        s.colorBlendFactor = 1; s.color = .white
        (parent ?? cityRoot).addChild(s)
        return s
    }

    private func build() {
        addChild(cityRoot)
        let white = Painter.texture(CGSize(width: 2, height: 2), scale: 1) { $0.fillGray(1, 1, R(0, 0, 2, 2)) }
        let skyH = H - yShore + 4

        // Sky.
        sky.texture = white; sky.size = CGSize(width: W, height: skyH)
        sky.anchorPoint = .zero; sky.position = P(0, yShore - 4); sky.zPosition = 0
        sky.shader = SKShader(source: Shaders.sky, uniforms: [uTop, uMid, uHor, uGlow, uSun, uCity, uSkyAspect])
        cityRoot.addChild(sky)

        stars = sprite(ArtSky.stars(size: CGSize(width: W, height: H - yShore - H * 0.05), seed: seed), CGSize(width: W, height: H - yShore - H * 0.05), z: 1, at: P(0, yShore + H * 0.05))
        stars.blendMode = .add
        sunHalo = sprite(glowTex, CGSize(width: H * 0.5, height: H * 0.5), z: 2, anchor: P(0.5, 0.5)); sunHalo.blendMode = .add
        sun = sprite(ArtSky.sunDisc(H * 0.05), CGSize(width: H * 0.05, height: H * 0.05), z: 2.1, anchor: P(0.5, 0.5))
        moonHalo = sprite(glowTex, CGSize(width: H * 0.22, height: H * 0.22), z: 2, anchor: P(0.5, 0.5)); moonHalo.blendMode = .add
        moon = sprite(nil, CGSize(width: H * 0.04, height: H * 0.04), z: 2.1, anchor: P(0.5, 0.5))

        stratus = sprite(ArtSky.stratus(size: CGSize(width: W * 1.3, height: skyH * 0.75), seed: seed + 3),
                         CGSize(width: W * 1.3, height: skyH * 0.75), z: 3, anchor: P(0.5, 0), at: P(W / 2, H - skyH * 0.75 + 2))
        buildClouds()
        boltTextures = (0..<3).map { ArtSky.lightningBolt(seed: UInt64($0) + 40, height: H * 0.45) }
        bolt = sprite(boltTextures[0], CGSize(width: H * 0.45 * 0.45, height: H * 0.45), z: 3.5, anchor: P(0.5, 0)); bolt.blendMode = .add; bolt.alpha = 0

        let ramp = ArtSky.verticalRamp(power: 1.6)
        cityGlow = sprite(ramp, CGSize(width: W, height: H * 0.22), z: 5, at: P(0, yShore)); cityGlow.blendMode = .add
        cityGlow.color = RGB(0xFF9A5A).sk

        // Far skyline.
        let farArt = ArtCity.farSkyline(width: W, height: H * 0.2, seed: seed + 11)
        far = sprite(farArt.base, farArt.size, z: 6, at: P(0, yShore + H * 0.012))
        farLights = sprite(farArt.lights, farArt.size, z: 6.1, at: far.position); farLights.blendMode = .add
        for b in farArt.beacons {
            let g = sprite(glowTex, CGSize(width: 9, height: 9), z: 6.2, anchor: P(0.5, 0.5), at: P(b.x, far.position.y + b.y))
            g.blendMode = .add; g.color = RGB(0xFF3B30).sk
            beacons.append((g, Double.random(in: 0...6)))
        }
        for gp in farArt.greenLights {
            let g = sprite(glowTex, CGSize(width: 7, height: 7), z: 6.2, anchor: P(0.5, 0.5), at: P(gp.x, far.position.y + gp.y))
            g.blendMode = .add; g.color = RGB(0x5CFF9A).sk
            greenLights.append(g)
        }
        hazeA = sprite(ramp, CGSize(width: W, height: H * 0.24), z: 7, at: P(0, yShore))
        hazeB = sprite(ramp, CGSize(width: W, height: H * 0.1), z: 9.5, at: P(0, yShore))

        // Lake.
        water.texture = white; water.size = CGSize(width: W, height: yShore - yWater + 2)
        water.anchorPoint = .zero; water.position = P(0, yWater); water.zPosition = 10
        water.shader = SKShader(source: Shaders.water, uniforms: [wFar, wNear, wGlow, wSun, wMoon, wRough,
                                                                  SKUniform(name: "u_aspect", float: Float(W / (yShore - yWater)))])
        cityRoot.addChild(water)
        addReflection(farArt.base, farArt.size, x: W / 2, kind: 0, list: &reflections, yOffset: H * 0.012)
        addReflection(farArt.lights, farArt.size, x: W / 2, kind: 3, list: &reflections, yOffset: H * 0.012)

        // Near bank: road, lamps, trees.
        let roadArt = ArtProps.road(width: W, H: H, seed: seed + 5)
        road = sprite(roadArt.texture, roadArt.size, z: 18)
        roadWet = sprite(ArtSky.verticalRamp(power: 0.6), CGSize(width: W, height: H * 0.085), z: 18.1, at: P(0, H * 0.06))
        roadWet.yScale = -1; roadWet.position.y = H * 0.145
        let lampArt = ArtProps.lampPost(height: H * 0.2)
        for fx in [0.27, 0.5, 0.72, 0.88] as [CGFloat] {
            let x = W * fx
            let l = sprite(lampArt.texture, lampArt.size, z: 19, anchor: P(0.5, 0), at: P(x, H * 0.152))
            lamps.append(l)
            for p in lampArt.points {
                let hp = P(x - lampArt.size.width / 2 + p.x, H * 0.152 + p.y)
                let core = sprite(glowTex, CGSize(width: H * 0.035, height: H * 0.035), z: 22, anchor: P(0.5, 0.5), at: hp)
                let halo = sprite(glowTex, CGSize(width: H * 0.16, height: H * 0.16), z: 22, anchor: P(0.5, 0.5), at: hp)
                let pool = sprite(glowTex, CGSize(width: H * 0.2, height: H * 0.045), z: 18.2, anchor: P(0.5, 0.5), at: P(hp.x, H * 0.11))
                for (n, a) in [(core, 1.0), (halo, 0.35), (pool, 0.22)] as [(SKSpriteNode, CGFloat)] {
                    n.blendMode = .add; n.color = RGB(0xFFD9A0).sk; lampGlows.append((n, a))
                }
                let streak = sprite(glowTex, CGSize(width: H * 0.02, height: H * 0.09), z: 18.2, anchor: P(0.5, 1), at: P(hp.x, H * 0.145))
                streak.blendMode = .add; streak.color = RGB(0xFFD9A0).sk
                lampWet.append(streak)
            }
        }

        buildWeatherFX()

        grain.texture = ArtSky.grain(size: size, seed: seed); grain.size = size; grain.anchorPoint = .zero; grain.zPosition = 40
        vignette.texture = ArtSky.vignette(size: size); vignette.size = size; vignette.anchorPoint = .zero; vignette.zPosition = 41
        vignette.alpha = 0.45
        dimmer.color = .black; dimmer.size = size; dimmer.anchorPoint = .zero; dimmer.zPosition = 42
        flash.color = RGB(0xDDE6FF).sk; flash.size = size; flash.anchorPoint = .zero; flash.zPosition = 30; flash.alpha = 0; flash.blendMode = .add
        for n in [grain, vignette, dimmer, flash] { addChild(n) }

        // Vehicle art pool.
        var rng = SeededRNG(seed: seed + 77)
        let counts: [VehicleArt.Kind: Int] = [.rickshaw: 5, .cng: 2, .car: 4, .bus: 1, .localBus: 2]
        for (k, n) in counts { vehiclePool[k] = (0..<n).map { _ in ArtProps.vehicle(k, ppm: ppm, rng: &rng) } }
        boatArt = (0..<3).map { _ in ArtProps.boat(ppm: ppm, rng: &rng) }
        walkerArt = (0..<8).map { _ in ArtProps.walker(ppm: ppm, rng: &rng, umbrella: false) }
        umbrellaArt = (0..<6).map { _ in ArtProps.walker(ppm: ppm, rng: &rng, umbrella: true) }
        birdFrames = ArtSky.birdFrames(size: max(12, H * 0.014))

        addChild(skyRoot)
        for n in [sky, stars, sunHalo, sun, moonHalo, moon, stratus, bolt, cityGlow] + clouds.map(\.node) { n.move(toParent: skyRoot) }
        horizon = yShore
        applySettings()
    }

    // MARK: Views

    private func setView(_ v: ViewKind) {
        viewID = v
        scenic?.removeFromParent(); scenic = nil
        if v != .lakeside {
            let sv = ScenicView(kind: v, size: size, seed: seed + 400)
            sv.zPosition = 6
            addChild(sv)
            scenic = sv
            let st = Settings.shared
            sv.settle(density: trafficDensity(), showTraffic: st.showTraffic, showPeople: st.showPeople, showBoats: st.showBoats)
            horizon = sv.horizon
        } else {
            horizon = yShore
        }
        layoutSky()
        updateVisibility()
    }

    private func updateVisibility() {
        let custom = backdrop != nil
        skyRoot.isHidden = custom
        cityRoot.isHidden = custom || scenic != nil
        scenic?.isHidden = custom
    }

    /// Fit the shared sky to the current view's horizon.
    private func layoutSky() {
        let bottom = (scenic?.skyBottom ?? horizon) - 4
        let skyH = H - bottom
        sky.position = P(0, bottom); sky.size = CGSize(width: W, height: skyH)
        uSkyAspect.floatValue = Float(W / skyH)
        stars.position.y = horizon + H * 0.05
        cityGlow.position.y = horizon
        for c in clouds { c.node.position.y = horizon + (H - horizon) * c.frac }
        let bh = min(H * 0.45, (H - horizon) * 0.95)
        bolt.size = CGSize(width: bh * 0.45, height: bh)
        for (i, f) in fogBands.enumerated() {
            f.position.y = [horizon - H * 0.03, horizon + H * 0.03, max(H * 0.18, horizon - H * 0.16)][i]
        }
    }

    private func addReflection(_ tex: SKTexture, _ size: CGSize, x: CGFloat, kind: Int, list: inout [(Reflection, Int)], yOffset: CGFloat = 0) {
        let r = Reflection(texture: tex, size: size, amp: 1.6, additive: kind == 3)
        r.node.position = P(x, yShore - yOffset * 0.5)
        r.node.zPosition = kind == 3 ? 11.5 : 11
        cityRoot.addChild(r.node)
        list.append((r, kind))
    }

    private func buildClouds() {
        var rng = SeededRNG(seed: seed + 9)
        let variants = (0..<6).map { i in ArtSky.cloud(width: 420, seed: seed + UInt64(i) * 13, flat: i >= 4) }
        let count = 16
        for i in 0..<count {
            let (tex, sz) = variants[i % variants.count]
            let y = yShore + (H - yShore) * rng.cg(0.25, 0.92)
            let nearness = (y - yShore) / (H - yShore)
            let w = W * rng.cg(0.14, 0.26) * (0.6 + nearness * 0.7)
            let n = sprite(tex, CGSize(width: w, height: w * sz.height / sz.width), z: 4 + CGFloat(i) * 0.01, anchor: P(0.5, 0.3), at: P(rng.cg(0, W), y))
            let cl = Cloud(node: n, rank: Double(i) / Double(count) + rng.d(-0.03, 0.03), speed: 0.4 + nearness * 0.8, baseAlpha: rng.cg(0.85, 1))
            cl.frac = nearness
            clouds.append(cl)
        }
    }

    private func buildWeatherFX() {
        let streak = ArtSky.rainStreak()
        for (e, z, scale, speed, alpha) in [(rainFar, 17.0, 0.45, 820.0, 0.3), (rainNear, 26.0, 1.0, 1350.0, 0.42)] as [(SKEmitterNode, CGFloat, CGFloat, CGFloat, CGFloat)] {
            e.particleTexture = streak
            e.particleBirthRate = 0
            e.particleLifetime = (H + 200) / speed * 1.15
            e.particlePositionRange = CGVector(dx: W * 1.6, dy: 0)
            e.position = P(W / 2, H + 40)
            e.particleSpeed = speed; e.particleSpeedRange = speed * 0.2
            e.emissionAngle = -.pi / 2
            e.particleAlpha = alpha; e.particleAlphaRange = alpha * 0.4
            e.particleScale = scale; e.particleScaleRange = scale * 0.3
            e.particleColorBlendFactor = 1; e.particleColor = .white
            e.zPosition = z
            addChild(e)
        }
        let ring = ArtSky.ripple()
        for (e, rect, rate) in [(ripples, R(0, yWater, W, yShore - yWater), 1.0), (roadRipples, R(0, H * 0.06, W, H * 0.085), 0.5)] as [(SKEmitterNode, CGRect, CGFloat)] {
            e.particleTexture = ring
            e.particleBirthRate = 0
            e.userData = ["rate": rate]
            e.particleLifetime = 0.7
            e.position = P(rect.midX, rect.midY)
            e.particlePositionRange = CGVector(dx: rect.width, dy: rect.height)
            e.particleSpeed = 0
            e.particleAlpha = 0.55; e.particleAlphaSpeed = -0.8
            e.particleScale = 0.12; e.particleScaleRange = 0.08; e.particleScaleSpeed = 0.9
            e.particleColorBlendFactor = 1; e.particleColor = .white
            e.zPosition = e === ripples ? 13 : 18.3
            cityRoot.addChild(e)
        }
        for i in 0..<3 {
            let tex = ArtSky.fogBand(width: W * 1.6, seed: seed + 60 + UInt64(i))
            let y = [yShore - H * 0.03, yShore + H * 0.03, yWater + H * 0.05][i]
            let n = sprite(tex, CGSize(width: W * 1.6, height: W * 1.6 * 0.18), z: 16.5, anchor: P(0.5, 0.5), at: P(W * CGFloat(i) * 0.3, y), parent: self)
            fogBands.append(n)
        }
    }

    // MARK: Settings-driven pieces

    /// Forget cached custom art so a re-imported image with the same name is picked up.
    func reloadCustomArt() { landmarkID = ""; backdropID = "" ; applySettings() }

    func applySettings() {
        Painter.scale = pixelScale
        let s = Settings.shared
        let id = s.effectiveLandmark
        if id != landmarkID { setLandmark(id) }
        if s.effectiveView != viewID { setView(s.effectiveView) }
        updateTrees(show: s.showTrees)
        if !s.showTraffic { vehicles.forEach { $0.root.removeFromParent() }; vehicles.removeAll() }
        if !s.showPeople { walkers.forEach { $0.node.removeFromParent() }; walkers.removeAll() }
        if !s.showBoats { boats.forEach { $0.root.removeFromParent() }; boats.removeAll() }
        if !s.showBirds { flocks.forEach { $0.0.removeFromParent() }; flocks.removeAll() }
        applyBackdrop(s.effectivePhoto ?? "city")
        grain.isHidden = !s.showGrain
    }

    private func setLandmark(_ id: String) {
        landmarkID = id
        landmark?.removeFromParent(); landmarkLights?.removeFromParent()
        landmark = nil; landmarkLights = nil
        for (r, _) in landmarkReflections + nearReflections { r.node.removeFromParent() }
        landmarkReflections.removeAll(); nearReflections.removeAll()
        near.removeFromParent(); nearLights.removeFromParent()

        let art = ArtLandmarks.make(id, height: H * 0.25, screenWidth: W)
        let wide = id == Landmark.hatirjheel.rawValue || id == Landmark.padma.rawValue
        let cx = wide ? W * 0.5 : W * 0.6
        riverView = id == Landmark.padma.rawValue
        var gap: ClosedRange<CGFloat> = (W * 0.6 - 2)...(W * 0.6 + 2)
        if let art {
            let base = yShore - H * 0.004
            let l = sprite(art.base, art.size, z: 8, anchor: P(0.5, 0), at: P(cx, base))
            landmark = l
            if let lt = art.lights {
                landmarkLights = sprite(lt, art.size, z: 8.1, anchor: P(0.5, 0), at: l.position)
                landmarkLights?.blendMode = .add
            }
            gap = (cx - art.size.width / 2 - W * 0.015)...(cx + art.size.width / 2 + W * 0.015)
            if riverView { gap = (-W)...(W * 2) }  // open river: no near-bank city
            addReflection(art.base, art.size, x: cx, kind: 2, list: &landmarkReflections, yOffset: H * 0.008)
            if let lt = art.lights { addReflection(lt, art.size, x: cx, kind: 3, list: &landmarkReflections, yOffset: H * 0.008) }
        }
        let nearArt = ArtCity.nearSkyline(width: W, height: H * 0.13, gap: gap, seed: seed + 23)
        near = sprite(nearArt.base, nearArt.size, z: 9, at: P(0, yShore - H * 0.006))
        nearLights = sprite(nearArt.lights, nearArt.size, z: 9.1, at: near.position); nearLights.blendMode = .add
        addReflection(nearArt.base, nearArt.size, x: W / 2, kind: 1, list: &nearReflections)
        addReflection(nearArt.lights, nearArt.size, x: W / 2, kind: 3, list: &nearReflections)
    }

    private func updateTrees(show: Bool) {
        let month = Solar.month(clock())
        let bloom: Double = [4: 1.0, 5: 1.0, 6: 0.8, 3: 0.3, 7: 0.35][month] ?? 0
        if !show { tree?.removeFromParent(); palm?.removeFromParent(); tree = nil; palm = nil; treeBloom = -1; return }
        guard tree == nil || bloom != treeBloom else { return }
        tree?.removeFromParent(); palm?.removeFromParent()
        treeBloom = bloom
        let t = ArtProps.krishnachura(width: W * 0.38, height: H * 0.56, bloom: bloom, seed: seed + 31)
        tree = sprite(t.texture, t.size, z: 24, anchor: t.anchor, at: P(W * 0.075, H * 0.02))
        let p = ArtProps.palm(width: W * 0.2, height: H * 0.5, seed: seed + 37)
        palm = sprite(p.texture, p.size, z: 24, anchor: p.anchor, at: P(W * 0.955, H * 0.02))
    }

    private var backdropID = "city"

    private func applyBackdrop(_ scene: String) {
        guard scene != backdropID else { return }
        backdropID = scene
        backdrop?.removeFromParent(); backdrop = nil
        defer { updateVisibility() }
        guard scene.hasPrefix("custom:") else { return }
        let url = Settings.customDir.appendingPathComponent(String(scene.dropFirst(7)))
        guard let img = NSImage(contentsOf: url), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let aspect = CGFloat(cg.width) / CGFloat(cg.height)
        let sz = aspect > W / H ? CGSize(width: H * aspect, height: H) : CGSize(width: W, height: W / aspect)
        let b = SKSpriteNode(texture: Painter.texture(cg), size: sz)
        b.position = P(W / 2, H / 2); b.zPosition = 0.5; b.colorBlendFactor = 1
        addChild(b)
        backdrop = b
    }

    // MARK: Snapshot helpers

    /// Bring sky, light and weather up to date without easing, for a still taken while the view may have been paused.
    func catchUp() {
        weather = weatherTarget
        wet = max(wet, weather.rain)
        computeCelestial(snap: true)
        look = Look.compute(sun: sunEl, moon: moonEl, phase: phase, w: weather)
        applyLook(0)
    }

    /// Jump straight to the target state (no easing) and fill the scene with traffic and rain.
    func settle() {
        weather = weatherTarget
        wet = weather.rain
        computeCelestial(snap: true)
        if scenic == nil, Settings.shared.showTraffic {
            for lane in 0..<2 {
                var x = CGFloat.random(in: 0...80)
                while x < W + 100 { spawnVehicle(lane: lane, at: x); x += CGFloat.random(in: 140...300) }
            }
        }
        if scenic == nil, Settings.shared.showBoats { for _ in 0..<2 { spawnBoat(anywhere: true) } }
        if scenic == nil, Settings.shared.showPeople { for _ in 0..<Int(4 + 4 * trafficDensity()) { spawnWalker(at: CGFloat.random(in: 0...W)) } }
        update(lastUpdate + 1.0 / 30)
        for e in [rainFar, rainNear, ripples, roadRipples] { e.advanceSimulationTime(3) }
    }

    // MARK: Update

    private func computeCelestial(snap: Bool) {
        let now = clock()
        let s = Solar.sun(at: now), m = Solar.moon(at: now)
        phase = Solar.moonPhase(at: now)
        let k = snap ? 1.0 : 0.04
        sunEl += (s.elevation - sunEl) * k
        sunAz += (s.azimuth - sunAz) * k
        moonEl += (m.elevation - moonEl) * k
        moonAz += (m.azimuth - moonAz) * k
        if abs(phase - moonPhaseDrawn) > 0.01 {
            moonPhaseDrawn = phase
            moon.texture = ArtSky.moon(H * 0.04, phase: phase)
        }
    }

    private func skyPoint(el: Double, az: Double) -> CGPoint {
        let x = W * CGFloat(0.5 + (az - 180) / 180 * 0.95)
        let y = horizon + (H - horizon) * CGFloat(el / 62) * 0.95
        return P(x, y)
    }

    override func update(_ currentTime: TimeInterval) {
        let dt = lastUpdate == 0 ? 1.0 / 30 : min(0.25, currentTime - lastUpdate)
        lastUpdate = currentTime
        Painter.scale = pixelScale
        time += dt
        computeCelestial(snap: false)
        weather.approach(weatherTarget, 1 - exp(-dt / 5))
        wet += (weather.rain - wet) * (weather.rain > wet ? 1 - exp(-dt / 8) : 1 - exp(-dt / 900))

        look = Look.compute(sun: sunEl, moon: moonEl, phase: phase, w: weather)
        applyLook(dt)
        updateClouds(dt)
        updateRain()
        if let sv = scenic {
            let st = Settings.shared
            sv.update(dt: dt, density: trafficDensity(), showTraffic: st.showTraffic, showPeople: st.showPeople, showBoats: st.showBoats)
        } else {
            updateTraffic(dt)
            updateBoats(dt)
            updateWalkers(dt)
        }
        updateBirds(dt)
        updateLightning(dt)

        let sway = 0.004 + min(0.012, abs(weather.wind) / 120 * 0.01) + weather.storm * 0.012
        tree?.zRotation = CGFloat(sin(time * 0.45) * sway + sin(time * 1.3) * sway * 0.25)
        palm?.zRotation = CGFloat(sin(time * 0.55 + 1) * sway * 1.4)

        let dim = Settings.shared.dim + look.night * 0.06
        dimmer.alpha = CGFloat(dim)
        dimmer.isHidden = dim < 0.005
    }

    private func applyLook(_ dt: Double) {
        let L = look
        uTop.vectorFloat4Value = L.top.v4(); uMid.vectorFloat4Value = L.mid.v4(); uHor.vectorFloat4Value = L.hor.v4()
        uGlow.vectorFloat4Value = L.glow.v4(L.glowStrength * smoothstep(-8, 0, sunEl))
        uCity.vectorFloat4Value = RGB(0xFF9A5A).v4(L.cityGlow * 0.16)

        let sp = skyPoint(el: sunEl, az: sunAz)
        uSun.vectorFloat2Value = SIMD2(Float(sp.x / W), Float((sp.y - sky.position.y) / sky.size.height))
        sun.position = sp; sunHalo.position = sp
        sun.alpha = CGFloat(L.sunAlpha); sun.isHidden = L.sunAlpha < 0.01
        sun.color = RGB.mix(RGB(0xFFF4E0), RGB(0xFFB070), 1 - smoothstep(0, 12, sunEl)).sk
        sunHalo.alpha = CGFloat(L.sunAlpha * 0.55); sunHalo.color = L.glow.sk; sunHalo.isHidden = sun.isHidden

        let mp = skyPoint(el: moonEl, az: moonAz)
        moon.position = mp; moonHalo.position = mp
        moon.alpha = CGFloat(L.moonAlpha); moon.isHidden = L.moonAlpha < 0.01
        moonHalo.alpha = CGFloat(L.moonAlpha * 0.25); moonHalo.color = RGB(0xC8D4F0).sk; moonHalo.isHidden = moon.isHidden
        stars.alpha = CGFloat(L.starAlpha * (0.85 + 0.15 * sin(time * 0.7))); stars.isHidden = L.starAlpha < 0.01

        cityGlow.alpha = CGFloat(L.cityGlow * 0.22)
        far.color = L.far.sk
        far.alpha = riverView ? 0.3 : 1
        near.color = L.midB.sk
        landmark?.color = RGB.mix(L.ambient, L.midB.lighter(0.3), 0.15).sk
        let lit = CGFloat(L.night)
        farLights.alpha = lit * 0.85 * CGFloat(1 - weather.fog * 0.6) * (riverView ? 0.35 : 1)
        nearLights.alpha = lit
        landmarkLights?.alpha = lit
        for (b, ph) in beacons {
            let pulse = pow(max(0, sin(time * 1.6 + ph)), 6)
            b.alpha = lit * CGFloat(0.25 + 0.75 * pulse)
        }
        for g in greenLights { g.alpha = lit * 0.8 }
        hazeA.color = L.hor.sk; hazeA.alpha = CGFloat(min(0.85, L.hazeAlpha))
        hazeB.color = L.hor.sk; hazeB.alpha = CGFloat(min(0.6, L.hazeAlpha * 0.45))

        wFar.vectorFloat4Value = L.waterFar.v4(); wNear.vectorFloat4Value = L.waterNear.v4()
        wGlow.vectorFloat4Value = L.glow.v4(L.glowStrength * 0.9)
        wSun.vectorFloat2Value = SIMD2(Float(sp.x / W), Float(L.sunAlpha))
        wMoon.vectorFloat2Value = SIMD2(Float(mp.x / W), Float(L.moonAlpha))
        scenic?.applyLook(L, weather: weather, wet: wet, sunX: sp.x / W, moonX: mp.x / W, time: time)
        wRough.floatValue = Float(min(1, weather.rain + abs(weather.wind) / 60))

        let reflAlpha = 0.42 * (1 - weather.rain * 0.5) * (1 - weather.fog * 0.6)
        for (r, kind) in reflections + nearReflections + landmarkReflections {
            switch kind {
            case 0: r.tint.vectorFloat4Value = RGB.mix(L.far, L.waterFar, 0.3).v4(reflAlpha * 0.8 * (riverView ? 0.3 : 1))
            case 1: r.tint.vectorFloat4Value = RGB.mix(L.midB, L.waterFar, 0.2).v4(reflAlpha)
            case 2: r.tint.vectorFloat4Value = RGB.mix(L.ambient, L.waterFar, 0.25).scaled(0.85).v4(reflAlpha)
            default: r.tint.vectorFloat4Value = RGB.white.v4(L.night * 0.55 * (1 - weather.fog * 0.5))
            }
        }

        let amb = L.ambient.sk
        road.color = amb; lamps.forEach { $0.color = amb }
        tree?.color = amb; palm?.color = amb
        roadWet.color = L.hor.lighter(0.2).sk
        roadWet.alpha = CGFloat(wet * 0.28); roadWet.isHidden = wet < 0.01
        let fogBloom = 1 + weather.fog * 0.6 + weather.rain * 0.3
        for (n, a) in lampGlows { n.alpha = lit * a * CGFloat(fogBloom) }
        for s in lampWet { s.alpha = lit * CGFloat(wet) * 0.6; s.isHidden = s.alpha < 0.01 }

        for (i, f) in fogBands.enumerated() {
            f.alpha = CGFloat(L.fogAlpha * 0.75 + weather.haze * 0.12)
            f.color = L.hor.lighter(0.15).sk
            f.position.x += CGFloat(dt) * (6 + CGFloat(i) * 3) * (weather.wind < 0 ? -1 : 1)
            if f.position.x > W * 1.3 { f.position.x = -W * 0.3 } else if f.position.x < -W * 0.3 { f.position.x = W * 1.3 }
            f.isHidden = f.alpha < 0.01
        }
        backdrop?.color = RGB.mix(.white, L.ambient, 0.85).sk
        let rainCol = RGB.mix(L.hor, .white, 0.35).sk
        rainFar.particleColor = rainCol; rainNear.particleColor = rainCol
        ripples.particleColor = RGB.mix(L.waterFar, .white, 0.5).sk
        roadRipples.particleColor = RGB.mix(L.hor, .white, 0.3).sk
    }

    private func updateClouds(_ dt: Double) {
        let amount = weather.cloud
        let st = smoothstep(0.55, 1.0, amount)
        // Under a full overcast, individual cumulus melt into the grey sheet.
        let melt = 1 - st * 0.75 - weather.rain * 0.2
        let col = RGB.mix(look.cloud, look.cloud.scaled(0.9), st).sk
        for c in clouds {
            let vis = smoothstep(c.rank, c.rank + 0.12, amount + 0.08)
            c.node.alpha = CGFloat(vis * max(0.12, melt)) * c.baseAlpha * CGFloat(1 - weather.fog * 0.5)
            c.node.isHidden = vis < 0.01
            c.node.color = col
            c.node.position.x += CGFloat(weather.wind * dt) * c.speed * 0.5
            let hw = c.node.size.width / 2
            if c.node.position.x > W + hw { c.node.position.x = -hw } else if c.node.position.x < -hw { c.node.position.x = W + hw }
        }
        stratus.alpha = CGFloat(st * 0.95)
        stratus.isHidden = st < 0.01
        stratus.color = look.cloud.scaled(0.95).sk
        stratus.position.x += CGFloat(weather.wind * dt) * 0.15
        if abs(stratus.position.x - W / 2) > W * 0.15 { stratus.position.x = W / 2 - (stratus.position.x - W / 2) * 0.98 }
    }

    private func updateRain() {
        let r = CGFloat(weather.rain)
        let tilt = max(-0.35, min(0.35, CGFloat(weather.wind) / 110))
        for (e, rate) in [(rainFar, 1500.0), (rainNear, 420.0)] as [(SKEmitterNode, CGFloat)] {
            e.particleBirthRate = r < 0.02 ? 0 : rate * r * (W / 1512)
            e.emissionAngle = -.pi / 2 + tilt
            e.particleRotation = tilt
            e.position.x = W / 2 - tilt * H * 0.6
        }
        for e in [ripples, roadRipples] {
            let rate = (e.userData?["rate"] as? CGFloat) ?? 1
            e.particleBirthRate = r < 0.02 ? 0 : 160 * r * rate * (W / 1512)
        }
    }

    private func updateLightning(_ dt: Double) {
        guard weather.storm > 0.5 else { return }
        nextLightning -= dt
        guard nextLightning <= 0 else { return }
        nextLightning = Double.random(in: 5...16)
        let peak = CGFloat.random(in: 0.25...0.5)
        flash.run(.sequence([
            .fadeAlpha(to: peak, duration: 0.05), .fadeAlpha(to: 0.05, duration: 0.08),
            .fadeAlpha(to: peak * 0.7, duration: 0.05), .fadeAlpha(to: 0, duration: 0.6),
        ]))
        let close = Bool.random()
        onLightning?(close)
        if close {
            bolt.texture = boltTextures.randomElement()
            bolt.position = P(W * CGFloat.random(in: 0.15...0.85), horizon + (scenic == nil ? H * 0.12 : -H * 0.01))
            bolt.xScale = Bool.random() ? 1 : -1
            bolt.run(.sequence([.fadeAlpha(to: 0.95, duration: 0.03), .wait(forDuration: 0.12), .fadeAlpha(to: 0.3, duration: 0.05),
                                .fadeAlpha(to: 0.85, duration: 0.04), .fadeAlpha(to: 0, duration: 0.25)]))
        }
    }

    // MARK: Traffic

    private let laneY: [CGFloat] = [0.066, 0.106]
    private let laneScale: [CGFloat] = [1.0, 0.88]
    private let laneDir: [CGFloat] = [1, -1]

    private func trafficDensity() -> Double {
        let h = Solar.localHour(clock())
        var d: Double
        switch h {
        case 7..<22: d = 1.0
        case 22..<24, 5..<7: d = 0.5
        default: d = 0.18
        }
        return d * (1 - weather.rain * 0.4) * (1 - weather.storm * 0.3)
    }

    private func updateTraffic(_ dt: Double) {
        let density = trafficDensity()
        if Settings.shared.showTraffic && backdrop == nil {
            for lane in 0..<2 {
                nextSpawn[lane] -= dt
                if nextSpawn[lane] <= 0 {
                    let entry: CGFloat = laneDir[lane] > 0 ? -60 : W + 60
                    let clear = vehicles.filter { $0.lane == lane }.allSatisfy { abs($0.x - entry) > $0.halfW + 120 }
                    if clear { spawnVehicle(lane: lane, at: nil) }
                    nextSpawn[lane] = Double.random(in: 2.5...9) / max(0.15, density)
                }
            }
        }
        let amb = look.ambient.sk
        let lit = CGFloat(look.night)
        for lane in 0..<2 {
            let dir = laneDir[lane]
            let list = vehicles.filter { $0.lane == lane }.sorted { $0.x * dir > $1.x * dir }  // front-most first
            for (i, v) in list.enumerated() {
                var speed = v.desired
                if i > 0 {
                    let lead = list[i - 1]
                    let gap = abs(lead.x - v.x) - lead.halfW - v.halfW
                    if gap < 50 { speed = min(speed, lead.v * max(0, gap - 12) / 38) }
                }
                v.v += (speed - v.v) * CGFloat(min(1, dt * 2))
                v.x += dir * v.v * CGFloat(dt)
                v.root.position.x = v.x
                for (w, r) in v.wheels { w.zRotation -= v.v * CGFloat(dt) / (r * laneScale[lane]) }
                v.body.color = amb
                if let r = v.rider {
                    v.riderPhase += v.v * CGFloat(dt) / (1.9 * ppm * laneScale[lane]) * CGFloat(v.riderFrames.count)
                    let idx = Int(v.riderPhase) % v.riderFrames.count
                    if idx != v.riderIndex { v.riderIndex = idx; r.texture = v.riderFrames[idx] }
                    r.color = amb
                }
                for (w, _) in v.wheels { w.color = amb }
                for (n, a) in v.nightNodes { n.alpha = lit * a; n.isHidden = lit < 0.01 }
                for n in v.wetNodes { n.alpha = lit * CGFloat(wet) * 0.5; n.isHidden = n.alpha < 0.01 }
            }
        }
        vehicles.removeAll { v in
            let out = v.x < -v.halfW - 200 || v.x > W + v.halfW + 200
            if out { v.root.removeFromParent() }
            return out
        }
    }

    private func pickKind() -> VehicleArt.Kind {
        let night = look.night > 0.5
        let weights: [(VehicleArt.Kind, Double)] = [(.rickshaw, night ? 0.25 : 0.42 + weather.rain * 0.2), (.cng, 0.24), (.car, 0.2), (.bus, 0.07), (.localBus, 0.09)]
        var r = Double.random(in: 0..<weights.reduce(0) { $0 + $1.1 })
        for (k, w) in weights { r -= w; if r <= 0 { return k } }
        return .rickshaw
    }

    private func spawnVehicle(lane: Int, at x0: CGFloat?) {
        guard let art = vehiclePool[pickKind()]?.randomElement() else { return }
        let s = laneScale[lane], dir = laneDir[lane]
        let body = SKSpriteNode(texture: art.body, size: art.size)
        body.anchorPoint = .zero; body.position = P(-art.size.width / 2, 0)
        body.colorBlendFactor = 1
        let speed = CGFloat.random(in: art.speed) * ppm * s * calm
        let halfW = art.size.width * s / 2
        let x = x0 ?? (dir > 0 ? -halfW - 40 : W + halfW + 40)
        let v = Vehicle(body: body, lane: lane, x: x, speed: speed, halfW: halfW)
        v.root.addChild(body)
        if !art.rider.isEmpty {
            let r = SKSpriteNode(texture: art.rider[0], size: art.size)
            r.anchorPoint = .zero; r.position = body.position; r.zPosition = 0.15; r.colorBlendFactor = 1
            v.root.addChild(r)
            v.rider = r; v.riderFrames = art.rider
        }
        v.root.position = P(x, H * laneY[lane])
        v.root.xScale = dir * s; v.root.yScale = s
        v.root.zPosition = lane == 0 ? 21 : 20
        for (i, (c, r)) in art.wheels.enumerated() {
            let tex = (i == 1 ? art.wheelBack : nil) ?? art.wheel
            let w = SKSpriteNode(texture: tex, size: CGSize(width: r * 2, height: r * 2))
            w.position = P(-art.size.width / 2 + c.x, c.y); w.zPosition = 0.1; w.colorBlendFactor = 1
            w.zRotation = .random(in: 0...6)
            v.root.addChild(w); v.wheels.append((w, r))
        }
        func glow(_ p: CGPoint, _ size: CGSize, _ color: RGB, _ a: CGFloat, anchor: CGPoint = P(0.5, 0.5)) -> SKSpriteNode {
            let g = SKSpriteNode(texture: glowTex, size: size)
            g.anchorPoint = anchor; g.position = P(-art.size.width / 2 + p.x, p.y)
            g.blendMode = .add; g.colorBlendFactor = 1; g.color = color.sk; g.zPosition = 0.2
            v.root.addChild(g); v.nightNodes.append((g, a))
            return g
        }
        let isRickshaw = art.kind == .rickshaw
        let headCol = isRickshaw ? RGB(0xFFC46A) : RGB(0xFFF1D0)
        _ = glow(art.head, CGSize(width: ppm * (isRickshaw ? 0.6 : 0.9), height: ppm * (isRickshaw ? 0.6 : 0.9)), headCol, 1)
        if !isRickshaw {
            _ = glow(P(art.head.x - ppm * 0.4, art.head.y - ppm * 0.15), CGSize(width: ppm * 6, height: ppm * 1.0), RGB(0xFFF1D0), 0.22, anchor: P(0, 0.5))
            _ = glow(art.tail, CGSize(width: ppm * 0.7, height: ppm * 0.7), RGB(0xFF3A2E), 0.9)
        }
        if let lt = art.lights {
            let l = SKSpriteNode(texture: lt, size: art.size)
            l.anchorPoint = .zero; l.position = body.position; l.blendMode = .add; l.zPosition = 0.05
            v.root.addChild(l); v.nightNodes.append((l, 0.9))
        }
        let refl = SKSpriteNode(texture: glowTex, size: CGSize(width: ppm * 0.7, height: ppm * 3.2))
        refl.anchorPoint = P(0.5, 1); refl.position = P(-art.size.width / 2 + art.head.x, 0)
        refl.blendMode = .add; refl.colorBlendFactor = 1; refl.color = headCol.sk; refl.zPosition = -0.1
        v.root.addChild(refl); v.wetNodes.append(refl)
        cityRoot.addChild(v.root)
        vehicles.append(v)
    }

    // MARK: Pedestrians

    private func updateWalkers(_ dt: Double) {
        if Settings.shared.showPeople && backdrop == nil {
            nextWalker -= dt
            if nextWalker <= 0 {
                let busy = trafficDensity() * (1 - weather.storm * 0.8)
                if walkers.count < Int(3 + 8 * busy) { spawnWalker(at: nil) }
                nextWalker = Double.random(in: 3...10) / max(0.2, busy)
            }
        }
        let amb = look.ambient.sk
        for w in walkers {
            w.x += w.v * CGFloat(dt)
            w.node.position.x = w.x
            w.node.color = amb
        }
        walkers.removeAll { w in
            let out = w.x < -60 || w.x > W + 60
            if out { w.node.removeFromParent() }
            return out
        }
    }

    private func spawnWalker(at x0: CGFloat?) {
        let rainy = weather.rain > 0.15
        guard let (frames, size) = (rainy ? umbrellaArt : walkerArt).randomElement() else { return }
        let s: CGFloat = 0.8
        let dir: CGFloat = Bool.random() ? 1 : -1
        let mps = CGFloat.random(in: 1.0...1.4) * (rainy ? 1.15 : 1)
        let n = SKSpriteNode(texture: frames[0], size: CGSize(width: size.width * s, height: size.height * s))
        n.anchorPoint = P(0.5, 0.01); n.colorBlendFactor = 1
        n.xScale = dir
        let x = x0 ?? (dir > 0 ? -40 : W + 40)
        n.position = P(x, H * 0.151)
        n.zPosition = 19.5 + CGFloat.random(in: 0...0.2)
        let stride: CGFloat = 1.5  // metres per walk cycle
        n.run(.repeatForever(.animate(with: frames, timePerFrame: Double(stride / mps) / Double(frames.count))))
        cityRoot.addChild(n)
        walkers.append(Walker(node: n, x: x, v: dir * mps * ppm * s * 0.8))
    }

    // MARK: Boats

    private func updateBoats(_ dt: Double) {
        if Settings.shared.showBoats && backdrop == nil && weather.storm < 0.5 {
            nextBoat -= dt
            if nextBoat <= 0 {
                if boats.count < 3 { spawnBoat(anywhere: false) }
                nextBoat = Double.random(in: 25...70)
            }
        }
        let amb = look.ambient
        for b in boats {
            b.x += b.v * CGFloat(dt)
            let bob = CGFloat(sin(time * 1.2 + b.phase)) * 1.2 * b.depth
            b.root.position = P(b.x, b.y + bob)
            b.root.zRotation = CGFloat(sin(time * 0.8 + b.phase) * 0.015)
            let c = RGB.mix(amb, look.waterFar, Double(1 - b.depth) * 0.45)
            b.body.color = c.sk
            b.refl.color = c.scaled(0.8).sk
            b.lantern.alpha = CGFloat(look.night)
            b.lantern.isHidden = look.night < 0.02
        }
        boats.removeAll { b in
            let out = b.x < -b.halfW - 60 || b.x > W + b.halfW + 60
            if out { b.root.removeFromParent() }
            return out
        }
    }

    private func spawnBoat(anywhere: Bool) {
        guard let (art, lanternPt) = boatArt.randomElement() else { return }
        let f = CGFloat.random(in: 0.08...0.85)
        let y = yWater + (yShore - yWater) * f
        let depth = 1 - f * 0.75  // 1 = close
        let s = 0.35 + depth * 0.55
        let dir: CGFloat = Bool.random() ? 1 : -1
        let size = CGSize(width: art.size.width * s, height: art.size.height * s)
        let x = anywhere ? CGFloat.random(in: W * 0.1...W * 0.9) : (dir > 0 ? -size.width : W + size.width)
        let body = SKSpriteNode(texture: art.texture, size: size)
        body.anchorPoint = P(0.5, 0.05); body.colorBlendFactor = 1
        let refl = SKSpriteNode(texture: art.texture, size: size)
        refl.anchorPoint = P(0.5, 0.05); refl.yScale = -0.8; refl.alpha = 0.3; refl.colorBlendFactor = 1
        let lantern = SKSpriteNode(texture: glowTex, size: CGSize(width: 14 * s + 6, height: 14 * s + 6))
        lantern.position = P(-size.width / 2 + lanternPt.x * s, lanternPt.y * s - size.height * 0.05)
        lantern.blendMode = .add; lantern.colorBlendFactor = 1; lantern.color = RGB(0xFFB45A).sk
        let b = Boat(body: body, refl: refl, lantern: lantern, x: x, y: y, v: dir * CGFloat.random(in: 5...10) * s * 1.4, depth: depth, halfW: size.width / 2)
        b.root.addChild(refl); b.root.addChild(body); b.root.addChild(lantern)
        b.root.xScale = dir
        b.root.zPosition = 12 + depth
        cityRoot.addChild(b.root)
        boats.append(b)
    }

    // MARK: Birds

    private func updateBirds(_ dt: Double) {
        for (f, v) in flocks { f.position.x += v * CGFloat(dt); f.position.y += sin(CGFloat(time) * 0.4) * 0.08 }
        flocks.removeAll { f in
            let out = f.0.position.x < -300 || f.0.position.x > W + 300
            if out { f.0.removeFromParent() }
            return out
        }
        guard Settings.shared.showBirds, backdrop == nil, scenic?.kind != .dinos, weather.rain < 0.3, sunEl > -4 else { return }
        nextFlock -= dt
        guard nextFlock <= 0 else { return }
        nextFlock = Double.random(in: 40...140)
        let root = SKNode()
        let dir: CGFloat = Bool.random() ? 1 : -1
        root.position = P(dir > 0 ? -150 : W + 150, horizon + (H - horizon) * CGFloat.random(in: 0.3...0.75))
        root.zPosition = 4.5
        let n = Int.random(in: 4...11)
        let sc = CGFloat.random(in: 0.7...1.2)
        for i in 0..<n {
            let b = SKSpriteNode(texture: birdFrames[0], size: CGSize(width: max(12, H * 0.014) * sc, height: max(12, H * 0.014) * 0.6 * sc))
            let row = CGFloat((i + 1) / 2), side: CGFloat = i % 2 == 0 ? 1 : -1
            b.position = P(-dir * row * 16 * sc + .random(in: -5...5), side * row * 9 * sc + .random(in: -4...4))
            b.alpha = 0.85
            b.run(.repeatForever(.animate(with: birdFrames + [birdFrames[1]], timePerFrame: .random(in: 0.09...0.14))))
            root.addChild(b)
        }
        skyRoot.addChild(root)
        flocks.append((root, dir * CGFloat.random(in: 30...50)))
    }
}
