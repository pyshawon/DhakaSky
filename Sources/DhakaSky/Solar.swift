import Foundation

/// Low-precision solar/lunar positions, plenty for a wallpaper.
enum Solar {
    static let latitude = 23.8103
    static let longitude = 90.4125
    static let dhaka = TimeZone(identifier: "Asia/Dhaka")!

    struct Position { var elevation: Double; var azimuth: Double }  // degrees; azimuth from north, clockwise

    private static func rad(_ d: Double) -> Double { d * .pi / 180 }
    private static func deg(_ r: Double) -> Double { r * 180 / .pi }

    static func sun(at date: Date) -> Position {
        let d = date.timeIntervalSince1970 / 86400 + 2440587.5 - 2451545.0
        let g = rad((357.529 + 0.98560028 * d).truncatingRemainder(dividingBy: 360))
        let q = (280.459 + 0.98564736 * d).truncatingRemainder(dividingBy: 360)
        let L = rad(q + 1.915 * sin(g) + 0.020 * sin(2 * g))
        let e = rad(23.439 - 0.00000036 * d)
        let ra = atan2(cos(e) * sin(L), cos(L))
        let dec = asin(sin(e) * sin(L))
        return position(d: d, ra: ra, dec: dec)
    }

    /// Moon approximated from phase: it sits where the sun was `phase` of a lunar day earlier
    /// (full moon at midnight ≈ the noon sun's position).
    static func moon(at date: Date) -> Position {
        sun(at: date.addingTimeInterval(-moonPhase(at: date) * 24.84 * 3600))
    }

    /// 0 = new, 0.25 = first quarter, 0.5 = full, 0.75 = last quarter.
    static func moonPhase(at date: Date) -> Double {
        let knownNew = 947182440.0  // 2000-01-06 18:14 UTC
        let synodic = 29.530588853 * 86400
        let p = (date.timeIntervalSince1970 - knownNew).truncatingRemainder(dividingBy: synodic) / synodic
        return p < 0 ? p + 1 : p
    }

    private static func position(d: Double, ra: Double, dec: Double) -> Position {
        let gmst = (18.697374558 + 24.06570982441908 * d).truncatingRemainder(dividingBy: 24)
        let lst = rad(gmst * 15 + longitude)
        let ha = lst - ra
        let lat = rad(latitude)
        let el = asin(sin(lat) * sin(dec) + cos(lat) * cos(dec) * cos(ha))
        var az = atan2(-sin(ha), tan(dec) * cos(lat) - sin(lat) * cos(ha))
        if az < 0 { az += 2 * .pi }
        return Position(elevation: deg(el), azimuth: deg(az))
    }

    /// Finds today's time (Dhaka) when the sun crosses `elevation`, on the morning or evening side.
    static func time(forElevation target: Double, morning: Bool, on day: Date = Date()) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = dhaka
        let start = cal.startOfDay(for: day)
        var best = start.addingTimeInterval(morning ? 6 * 3600 : 18 * 3600)
        var bestErr = Double.greatestFiniteMagnitude
        for minute in stride(from: 0, to: 1440, by: 2) {
            let t = start.addingTimeInterval(Double(minute) * 60)
            let p = sun(at: t)
            let isMorning = p.azimuth < 180
            if isMorning != morning { continue }
            let err = abs(p.elevation - target)
            if err < bestErr { bestErr = err; best = t }
        }
        return best
    }

    static func localHour(_ date: Date) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = dhaka
        let c = cal.dateComponents([.hour, .minute], from: date)
        return Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
    }

    static func month(_ date: Date) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = dhaka
        return cal.component(.month, from: date)
    }
}
