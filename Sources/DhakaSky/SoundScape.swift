import AVFoundation

/// Procedural ambience: rain (hiss + droplets), thunder that follows the lightning, distant street hum and
/// the odd rickshaw bell. Parameters are plain floats written on the main thread and read by the audio thread.
final class SoundScape {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode!
    private let sr: Float = 44100
    private var bellTimer: Timer?

    // Main-thread inputs.
    var rain: Float = 0
    var street: Float = 0
    var bells = true
    var humLevel: Float = 0
    var volume: Float = 0.6
    private var thunderSeq = 0, thunderAmp: Float = 0
    fileprivate(set) var thunderDelay = 0
    private var thunderClose = false
    private var bellSeq = 0, bellPan: Float = 0

    // Audio-thread state.
    private var seed: UInt32 = 0x1234567
    private var gRain: Float = 0, gStreet: Float = 0, gVol: Float = 0
    private var lpL: Float = 0, lpR: Float = 0, lp2L: Float = 0, lp2R: Float = 0, brown: Float = 0, brownLP: Float = 0
    private var drops: [(env: Float, decay: Float, phase: Float, inc: Float, pan: Float)] = Array(repeating: (0, 0, 0, 0, 0), count: 12)
    private var seenThunder = 0, tWait = 0, tEnv: Float = 0, tPeak: Float = 0, tRise = true, tCrack: Float = 0, tFlutter: Float = 0, tFlutterLP: Float = 0
    private var seenBell = 0, bellT = 0, bellHits = 3, bP1: Float = 0, bP2: Float = 0, bEnv: Float = 0, bPanA: Float = 0
    private(set) var running = false

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: Double(sr), channels: 2)!
        source = AVAudioSourceNode(format: format) { [unowned self] _, _, frames, abl -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(abl)
            guard buffers.count >= 2, let l = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            self.render(l, r, Int(frames))
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        // macOS stops the engine when the output device changes (headphones, AirPlay); the next start() restarts it.
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.running = false
        }
    }

    func start() {
        guard !running else { return }
        do { try engine.start(); running = true } catch { NSLog("DhakaSky audio: \(error)"); return }
        bellTimer?.invalidate()
        bellTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, self.bells, self.street > 0.2, Float.random(in: 0...1) < 0.12 * self.street else { return }
            self.bellPan = Float.random(in: -0.7...0.7)
            self.bellSeq += 1
        }
    }

    func stop() {
        guard running else { return }
        engine.pause()
        bellTimer?.invalidate(); bellTimer = nil
        running = false
    }

    /// `close` strikes crack before they rumble; distant ones arrive later and softer.
    func thunder(close: Bool) {
        thunderClose = close
        thunderAmp = close ? Float.random(in: 0.7...1) : Float.random(in: 0.3...0.6)
        thunderDelay = Int(Float.random(in: close ? 0.15...0.6 : 1.2...3.5) * sr)
        thunderSeq += 1
    }

    /// Renders a few seconds offline (no speakers) and reports RMS levels, used by `--sound-test`.
    static func selfTest() -> String {
        func rms(_ setup: (SoundScape) -> Void, seconds: Float = 3) -> (Float, Float) {
            let s = SoundScape()
            s.volume = 0.6
            setup(s)
            let n = Int(s.sr * seconds)
            let l = UnsafeMutablePointer<Float>.allocate(capacity: n), r = UnsafeMutablePointer<Float>.allocate(capacity: n)
            defer { l.deallocate(); r.deallocate() }
            s.render(l, r, n)
            var sum: Float = 0, peak: Float = 0
            for i in (n / 2)..<n { sum += l[i] * l[i]; peak = max(peak, abs(l[i])); if l[i].isNaN { return (.nan, .nan) } }
            return ((sum / Float(n / 2)).squareRoot(), peak)
        }
        var out: [String] = []
        for (name, setup) in [
            ("silent (no rain, no street)", { (_: SoundScape) in }),
            ("drizzle", { $0.rain = 0.25 }),
            ("heavy rain", { $0.rain = 1 }),
            ("street hum", { $0.street = 1; $0.humLevel = 1 }),
            ("close thunder", { $0.thunder(close: true); $0.thunderDelay = 0 }),
        ] as [(String, (SoundScape) -> Void)] {
            let (r, p) = rms(setup)
            out.append(String(format: "%-28@ rms %.4f  peak %.3f", name as NSString, r, p))
        }
        return out.joined(separator: "\n")
    }

    @inline(__always) private func rnd(_ a: Float, _ b: Float) -> Float { a + (b - a) * (noise() * 0.5 + 0.5) }

    @inline(__always) private func noise() -> Float {
        seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5
        return Float(seed) / Float(UInt32.max) * 2 - 1
    }

    private func render(_ L: UnsafeMutablePointer<Float>, _ R: UnsafeMutablePointer<Float>, _ n: Int) {
        if thunderSeq != seenThunder {
            seenThunder = thunderSeq; tWait = thunderDelay; tPeak = thunderAmp; tEnv = 0; tRise = true
            tCrack = thunderClose ? 1 : 0
        }
        if bellSeq != seenBell { seenBell = bellSeq; bellT = 0; bellHits = 0; bPanA = bellPan }
        let k: Float = 1 - exp(-1 / (sr * 0.8))
        let dropRate = (15 + rain * 420) / sr
        for i in 0..<n {
            gRain += (rain - gRain) * k; gStreet += (street - gStreet) * k; gVol += (volume - gVol) * k
            let nl = noise(), nr = noise()
            // Rain: high hiss (white minus low-pass) plus a soft low wash.
            lpL += (nl - lpL) * 0.06; lpR += (nr - lpR) * 0.06
            lp2L += (nl - lp2L) * 0.012; lp2R += (nr - lp2R) * 0.012
            let rainAmp = gRain * 0.1 + gRain * gRain * 0.12
            var outL = ((nl - lpL) * 0.5 + lp2L * 1.6) * rainAmp
            var outR = ((nr - lpR) * 0.5 + lp2R * 1.6) * rainAmp

            // Droplets on leaves and tin roofs.
            if gRain > 0.02, rnd(0, 1) < dropRate {
                if let idx = drops.firstIndex(where: { $0.env < 0.01 }) {
                    let f = rnd(1200, 4200)
                    drops[idx] = (rnd(0.05, 0.25) * gRain, exp(-1 / (sr * rnd(0.004, 0.015))), 0, f / sr * 2 * .pi, rnd(-1, 1))
                }
            }
            for d in 0..<drops.count where drops[d].env > 0.001 {
                let s = sin(drops[d].phase) * drops[d].env
                drops[d].phase += drops[d].inc
                drops[d].inc *= 0.9997
                drops[d].env *= drops[d].decay
                outL += s * (1 - drops[d].pan) * 0.5; outR += s * (1 + drops[d].pan) * 0.5
            }

            // Brown noise feeds both thunder and the distant city hum.
            brown = (brown + nl * 0.02) * 0.998
            brownLP += (brown - brownLP) * 0.02
            let hum = brownLP * gStreet * 0.35 * humLevel
            outL += hum; outR += hum

            if tWait > 0 { tWait -= 1 } else if tPeak > 0 {
                if tRise { tEnv += tPeak / (sr * 0.12); if tEnv >= tPeak { tRise = false } } else { tEnv *= exp(-1 / (sr * 1.6)) }
                tFlutterLP += (abs(noise()) - tFlutterLP) * 0.0004
                let rumble = brownLP * 5 * tEnv * (0.5 + tFlutterLP * 2)
                var crack: Float = 0
                if tCrack > 0.001 { crack = (nl - lpL) * tCrack * 0.5; tCrack *= exp(-1 / (sr * 0.09)) }
                outL += rumble + crack; outR += rumble * 0.9 + crack * 0.8
                if !tRise && tEnv < 0.0005 { tPeak = 0 }
            }

            // Rickshaw bell: three quick strikes, two inharmonic partials.
            if bellHits < 3 {
                if bellT % Int(sr * 0.085) == 0 { bEnv = 1; bellHits += 1 }
                bellT += 1
            }
            if bEnv > 0.0005 {
                bP1 += 2 * .pi * 2350 / sr; bP2 += 2 * .pi * 3480 / sr
                if bP1 > 2 * .pi { bP1 -= 2 * .pi }
                if bP2 > 2 * .pi { bP2 -= 2 * .pi }
                let b = (sin(bP1) + sin(bP2) * 0.6) * bEnv * 0.05
                bEnv *= exp(-1 / (sr * 0.12))
                outL += b * (1 - bPanA) * 0.5; outR += b * (1 + bPanA) * 0.5
            }

            L[i] = tanh(outL * gVol)
            R[i] = tanh(outR * gVol)
        }
    }
}
