import Foundation

/// Every colour the scene needs for one moment, derived from sun elevation + weather.
struct Look {
    var top, mid, hor: RGB          // sky gradient
    var glow: RGB                   // sun glow tint
    var glowStrength: Double
    var ambient: RGB                // multiplies foreground colour art
    var far: RGB                    // distant skyline tint
    var midB: RGB                   // near skyline tint
    var cloud: RGB
    // derived
    var waterFar = RGB.black, waterNear = RGB.black
    var night = 0.0                 // 0 day … 1 night (window lights)
    var starAlpha = 0.0, sunAlpha = 1.0, moonAlpha = 0.0
    var hazeAlpha = 0.0, fogAlpha = 0.0
    var cityGlow = 0.0              // orange light-pollution on the horizon / cloud bases

    static func mix(_ a: Look, _ b: Look, _ t: Double) -> Look {
        var o = a
        o.top = .mix(a.top, b.top, t); o.mid = .mix(a.mid, b.mid, t); o.hor = .mix(a.hor, b.hor, t)
        o.glow = .mix(a.glow, b.glow, t); o.glowStrength = lerp(a.glowStrength, b.glowStrength, t)
        o.ambient = .mix(a.ambient, b.ambient, t); o.far = .mix(a.far, b.far, t)
        o.midB = .mix(a.midB, b.midB, t); o.cloud = .mix(a.cloud, b.cloud, t)
        return o
    }

    private static func key(_ top: UInt32, _ mid: UInt32, _ hor: UInt32, _ glow: UInt32, _ gs: Double,
                            _ amb: UInt32, _ far: UInt32, _ midB: UInt32, _ cloud: UInt32) -> Look {
        Look(top: RGB(top), mid: RGB(mid), hor: RGB(hor), glow: RGB(glow), glowStrength: gs,
             ambient: RGB(amb), far: RGB(far), midB: RGB(midB), cloud: RGB(cloud))
    }

    // Clear-sky keyframes by solar elevation (degrees). Muted on purpose, easy on the eyes.
    private static let clearKeys: [(Double, Look)] = [
        (-90, key(0x070C22, 0x14204A, 0x2E3B6E, 0x000000, 0.0, 0x46557F, 0x26305A, 0x1A2244, 0x242E55)),
        (-16, key(0x091029, 0x18244F, 0x34406F, 0x2B2F5A, 0.0, 0x485782, 0x28325C, 0x1C2446, 0x29335C)),
        (-9, key(0x121B44, 0x2A3470, 0x5A4E7E, 0x7A4F80, 0.25, 0x535A82, 0x383F68, 0x282E52, 0x5C5880)),
        (-4, key(0x1F2D66, 0x56528E, 0xC48A90, 0xE39A84, 0.55, 0x8C7590, 0x5C5583, 0x3C3962, 0xB08499)),
        (0.5, key(0x324E8A, 0x9E7DA6, 0xF0AC80, 0xFFB27A, 1.0, 0xD4A08E, 0x8A7896, 0x5D5275, 0xF2B48F)),
        (6, key(0x4A76B2, 0xA4B8D6, 0xF2D4AC, 0xFFD9A0, 0.8, 0xEEDAC2, 0xA2A5BD, 0x787899, 0xFFE6CC)),
        (18, key(0x4A86C2, 0x8CB9DC, 0xD4E3EC, 0xFFF1D6, 0.5, 0xF2EEE6, 0xA6B7CA, 0x7F8FA8, 0xFDFCFA)),
        (50, key(0x4583BE, 0x86B5DA, 0xCBDEEA, 0xFFF6E6, 0.42, 0xF6F4EE, 0xAABBCD, 0x8494AB, 0xFFFFFF)),
        (91, key(0x4583BE, 0x86B5DA, 0xCBDEEA, 0xFFF6E6, 0.42, 0xF6F4EE, 0xAABBCD, 0x8494AB, 0xFFFFFF)),
    ]

    private static let overcastDay = key(0x7E8999, 0x99A4B2, 0xB9C1CA, 0xFFFFFF, 0.08, 0xCDD0D5, 0x9DA5B0, 0x7E8694, 0xD0D4DA)
    private static let rainyDay = key(0x56616F, 0x6C7785, 0x8B94A0, 0xFFFFFF, 0.0, 0x9CA2AC, 0x7D8592, 0x626A78, 0x8D94A0)
    private static let stormyDay = key(0x2C3343, 0x41485A, 0x646879, 0xFFFFFF, 0.0, 0x737889, 0x585E6E, 0x434A5A, 0x5C6273)
    private static let overcastNight = key(0x12162A, 0x1E2336, 0x3A3746, 0x000000, 0.0, 0x393E54, 0x282D40, 0x1D2232, 0x2F2F40)

    static func interpolateClear(_ e: Double) -> Look {
        for i in 1..<clearKeys.count where e <= clearKeys[i].0 {
            let (e0, a) = clearKeys[i - 1], (e1, b) = clearKeys[i]
            return mix(a, b, smoothstep(0, 1, (e - e0) / (e1 - e0)))
        }
        return clearKeys.last!.1
    }

    /// - Parameters:
    ///   - sun: solar elevation in degrees. `moonUp`: moon elevation in degrees. `phase`: lunar phase 0…1.
    static func compute(sun e: Double, moon moonEl: Double, phase: Double, w: WeatherParams) -> Look {
        let clear = interpolateClear(e)
        let light = smoothstep(-9, 9, e)

        // Grey-out amount from cloud cover and rain.
        let grey = clamp01(max(pow(clamp01((w.cloud - 0.35) / 0.6), 1.3) * 0.9, w.rain > 0.02 ? 0.75 + w.rain * 0.25 : 0))
        var dayGrey = mix(overcastDay, rainyDay, clamp01(w.rain * 1.3))
        dayGrey = mix(dayGrey, stormyDay, clamp01(w.storm))
        var greyLook = mix(overcastNight, dayGrey, light)
        // Keep a little warmth at golden hour even through clouds.
        let golden = smoothstep(-6, -1, e) * (1 - smoothstep(4, 12, e))
        greyLook.hor = .mix(greyLook.hor, clear.hor, golden * 0.3)
        greyLook.cloud = .mix(greyLook.cloud, clear.cloud, golden * 0.35)

        var o = mix(clear, greyLook, grey)
        o.glowStrength = clear.glowStrength * (1 - grey * 0.9)

        // Smog / dust haze, Dhaka's winter signature.
        if w.haze > 0 {
            let hazeCol = RGB.mix(RGB(0x3A3A4A), RGB(0xD8CBB4), light)
            o.hor = .mix(o.hor, hazeCol, w.haze * 0.45)
            o.mid = .mix(o.mid, hazeCol, w.haze * 0.18)
            o.far = .mix(o.far, o.hor, w.haze * 0.55)
            o.midB = .mix(o.midB, o.hor, w.haze * 0.25)
        }
        // Fog washes everything toward a pale grey.
        if w.fog > 0 {
            let fogCol = RGB.mix(RGB(0x363B4C), RGB(0xD9DDE0), light)
            o.hor = .mix(o.hor, fogCol, w.fog * 0.8)
            o.mid = .mix(o.mid, fogCol, w.fog * 0.6)
            o.top = .mix(o.top, fogCol, w.fog * 0.35)
            o.far = .mix(o.far, fogCol, w.fog * 0.85)
            o.midB = .mix(o.midB, fogCol, w.fog * 0.55)
            o.cloud = .mix(o.cloud, fogCol, w.fog * 0.6)
            o.ambient = .mix(o.ambient, fogCol, w.fog * 0.2)
        }

        o.night = 1 - smoothstep(-7, 3, e)
        let daylightGloom = (1 - o.night) * grey * 0.25  // a few lights stay on during gloomy days
        o.night = max(o.night, daylightGloom)
        o.sunAlpha = (1 - grey) * (1 - w.fog * 0.7) * smoothstep(-3, 0.5, e)
        let moonVisible = smoothstep(-2, 4, moonEl) * (1 - smoothstep(-2, 8, e) * 0.75)
        o.moonAlpha = moonVisible * (1 - grey * 0.92) * (1 - w.fog * 0.8) * (0.35 + 0.65 * sin(.pi * phase))
        o.starAlpha = (1 - smoothstep(-14, -4, e)) * (1 - grey) * (1 - w.haze * 0.6) * (1 - w.fog)
        o.hazeAlpha = 0.18 + w.haze * 0.35 + w.fog * 0.4
        o.fogAlpha = w.fog
        o.cityGlow = (1 - light) * (0.35 + grey * 0.5)

        // Moonlight: a bright moon lifts the night foreground toward a cool silver-blue.
        o.ambient = .mix(o.ambient, RGB(0x8E9CC8), o.moonAlpha * o.night * 0.22)

        o.waterFar = RGB.mix(o.hor, o.mid, 0.35).scaled(0.8)
        o.waterNear = RGB.mix(o.mid, o.top, 0.55).scaled(0.6)
        return o
    }
}
