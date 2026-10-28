import Foundation

enum Condition: String, CaseIterable {
    case clear, partlyCloudy, overcast, fog, drizzle, rain, heavyRain, thunderstorm

    var title: String {
        switch self {
        case .clear: return "Clear"
        case .partlyCloudy: return "Partly cloudy"
        case .overcast: return "Overcast"
        case .fog: return "Fog / mist"
        case .drizzle: return "Drizzle"
        case .rain: return "Rain"
        case .heavyRain: return "Heavy rain"
        case .thunderstorm: return "Thunderstorm"
        }
    }

    func symbol(isDay: Bool) -> String {
        switch self {
        case .clear: return isDay ? "sun.max" : "moon.stars"
        case .partlyCloudy: return isDay ? "cloud.sun" : "cloud.moon"
        case .overcast: return "cloud"
        case .fog: return "cloud.fog"
        case .drizzle: return "cloud.drizzle"
        case .rain: return "cloud.rain"
        case .heavyRain: return "cloud.heavyrain"
        case .thunderstorm: return "cloud.bolt.rain"
        }
    }

    init(wmo: Int) {
        switch wmo {
        case 0: self = .clear
        case 1, 2: self = .partlyCloudy
        case 3: self = .overcast
        case 45, 48: self = .fog
        case 51...57: self = .drizzle
        case 61, 63, 66, 80, 81: self = .rain
        case 65, 67, 82: self = .heavyRain
        case 95...99: self = .thunderstorm
        default: self = .overcast
        }
    }
}

struct WeatherSnapshot {
    var condition: Condition
    var cloudCover: Double  // 0...1
    var precipitation: Double  // mm in last interval
    var windKmh: Double
    var windFromDeg: Double
    var temperature: Double?
    var pm25: Double?
    var aqi: Int?
    var fetchedAt: Date?

    static func preset(_ c: Condition) -> WeatherSnapshot {
        let cover: Double = [.clear: 0.05, .partlyCloudy: 0.45, .overcast: 0.95, .fog: 0.7, .drizzle: 0.9,
                             .rain: 1, .heavyRain: 1, .thunderstorm: 1][c] ?? 0.5
        let precip: Double = [.drizzle: 0.4, .rain: 2.5, .heavyRain: 8, .thunderstorm: 6][c] ?? 0
        let wind: Double = [.thunderstorm: 28, .heavyRain: 18, .rain: 12][c] ?? 8
        return WeatherSnapshot(condition: c, cloudCover: cover, precipitation: precip, windKmh: wind,
                               windFromDeg: 200, temperature: nil, pm25: 25, aqi: nil, fetchedAt: nil)
    }

    /// Target scene parameters, all 0...1 except wind (screen px/s, signed: + moves right).
    var params: WeatherParams {
        var p = WeatherParams()
        let baseRain: Double
        switch condition {
        case .drizzle: baseRain = 0.22
        case .rain: baseRain = 0.55
        case .heavyRain: baseRain = 0.95
        case .thunderstorm: baseRain = 0.85
        default: baseRain = 0
        }
        p.rain = baseRain > 0 ? max(baseRain, min(1, precipitation / 8)) : 0
        p.storm = condition == .thunderstorm ? 1 : 0
        p.cloud = cloudCover
        if p.rain > 0 { p.cloud = max(p.cloud, 0.9) }
        if condition == .overcast { p.cloud = max(p.cloud, 0.85) }
        p.fog = condition == .fog ? 0.85 : 0
        if let pm = pm25 { p.haze = clamp01((pm - 15) / 140) * 0.9 }
        // Viewer looks south across the lake: east is screen-left, west is screen-right.
        let towards = (windFromDeg + 180) * .pi / 180
        let eastward = sin(towards)
        p.wind = -eastward * max(3, windKmh) * 1.6
        return p
    }
}

struct WeatherParams {
    var cloud = 0.1, rain = 0.0, storm = 0.0, fog = 0.0, haze = 0.15, wind = -8.0

    mutating func approach(_ t: WeatherParams, _ k: Double) {
        cloud += (t.cloud - cloud) * k
        rain += (t.rain - rain) * k
        storm += (t.storm - storm) * k
        fog += (t.fog - fog) * k
        haze += (t.haze - haze) * k
        wind += (t.wind - wind) * k
    }
}

/// Polls Open-Meteo (no API key needed) for Dhaka's current weather and air quality.
final class WeatherService {
    private(set) var latest: WeatherSnapshot?
    private(set) var lastError: String?
    var onUpdate: ((WeatherSnapshot) -> Void)?
    private var timer: Timer?

    func stop() { timer?.invalidate(); timer = nil }

    func start(interval: TimeInterval = 15 * 60) {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        let lat = Solar.latitude, lon = Solar.longitude
        let wx = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)"
            + "&current=temperature_2m,weather_code,cloud_cover,precipitation,wind_speed_10m,wind_direction_10m"
            + "&timezone=Asia%2FDhaka")!
        let aq = URL(string: "https://air-quality-api.open-meteo.com/v1/air-quality?latitude=\(lat)&longitude=\(lon)"
            + "&current=pm2_5,us_aqi")!

        let group = DispatchGroup()
        var wxJSON: [String: Any]?, aqJSON: [String: Any]?
        var err: String?
        for (url, isWx) in [(wx, true), (aq, false)] {
            group.enter()
            var req = URLRequest(url: url)
            req.timeoutInterval = 20
            URLSession.shared.dataTask(with: req) { data, _, error in
                defer { group.leave() }
                if let error { err = error.localizedDescription; return }
                let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                if isWx { wxJSON = json } else { aqJSON = json }
            }.resume()
        }
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            guard let cur = wxJSON?["current"] as? [String: Any] else {
                self.lastError = err ?? "Weather unavailable"
                return
            }
            func num(_ d: [String: Any]?, _ k: String) -> Double? { (d?[k] as? NSNumber)?.doubleValue }
            let aqCur = aqJSON?["current"] as? [String: Any]
            let snap = WeatherSnapshot(
                condition: Condition(wmo: Int(num(cur, "weather_code") ?? 0)),
                cloudCover: (num(cur, "cloud_cover") ?? 20) / 100,
                precipitation: num(cur, "precipitation") ?? 0,
                windKmh: num(cur, "wind_speed_10m") ?? 5,
                windFromDeg: num(cur, "wind_direction_10m") ?? 180,
                temperature: num(cur, "temperature_2m"),
                pm25: num(aqCur, "pm2_5"),
                aqi: num(aqCur, "us_aqi").map { Int($0) },
                fetchedAt: Date())
            self.latest = snap
            self.lastError = nil
            self.onUpdate?(snap)
        }
    }
}
