import Foundation

enum Landmark: String, CaseIterable {
    case parliament, shaheedMinar, ahsanManzil, satGambuj, hatirjheel, lalbagh, padma, none

    var title: String {
        switch self {
        case .parliament: return "Jatiya Sangsad Bhaban (Parliament)"
        case .shaheedMinar: return "Central Shaheed Minar"
        case .ahsanManzil: return "Ahsan Manzil (Pink Palace)"
        case .satGambuj: return "Sat Gambuj Mosque"
        case .hatirjheel: return "Hatirjheel Bridges"
        case .lalbagh: return "Lalbagh Fort"
        case .padma: return "Padma Bridge (river view)"
        case .none: return "Skyline only"
        }
    }
    static let rotating: [Landmark] = [.parliament, .shaheedMinar, .ahsanManzil, .satGambuj, .hatirjheel, .lalbagh, .padma]
}

enum ViewKind: String, CaseIterable {
    case lakeside, hatirjheel, gulshan, dhanmondi, lalbagh, panorama, cefalo, dinos

    var title: String {
        switch self {
        case .lakeside: return "Lakeside skyline"
        case .hatirjheel: return "Hatirjheel from above"
        case .gulshan: return "Gulshan Lake bridge"
        case .dhanmondi: return "Dhanmondi Lake"
        case .cefalo: return "Cefalo rooftop"
        case .lalbagh: return "Lalbagh Fort gardens"
        case .panorama: return "City panorama"
        case .dinos: return "Dinosaur World"
        }
    }
    var subtitle: String {
        switch self {
        case .lakeside: return "Across the lake, with your choice of landmark"
        case .hatirjheel: return "Aerial view down the canal, arch bridge and pylons"
        case .gulshan: return "Arch bridge over the green lake, park and towers"
        case .dhanmondi: return "Lakeside promenade, footbridge, Rabindra Sarobar, rowing boats"
        case .cefalo: return "The green wall and deck, with Dhaka's rooftops beyond the railing"
        case .lalbagh: return "Pari Bibi's tomb, fountains and topiary gardens"
        case .panorama: return "Rooftops, greenery and towers to the horizon"
        case .dinos: return "Friendly dinosaurs, a smoking volcano and a lake, for little ones"
        }
    }
}

enum TimeOverride: String, CaseIterable {
    case live, dawn, morning, noon, afternoon, sunset, dusk, night

    var title: String {
        switch self {
        case .live: return "Live (Dhaka time)"
        case .dawn: return "Dawn"
        case .morning: return "Morning"
        case .noon: return "Noon"
        case .afternoon: return "Afternoon"
        case .sunset: return "Golden hour / sunset"
        case .dusk: return "Dusk"
        case .night: return "Night"
        }
    }

    /// The virtual clock time this override represents (today, Dhaka).
    func date(now: Date = Date()) -> Date {
        switch self {
        case .live: return now
        case .dawn: return Solar.time(forElevation: -4, morning: true, on: now)
        case .morning: return Solar.time(forElevation: 22, morning: true, on: now)
        case .noon: return Solar.time(forElevation: 90, morning: true, on: now)
        case .afternoon: return Solar.time(forElevation: 28, morning: false, on: now)
        case .sunset: return Solar.time(forElevation: 2, morning: false, on: now)
        case .dusk: return Solar.time(forElevation: -5, morning: false, on: now)
        case .night: return Solar.time(forElevation: -40, morning: false, on: now).addingTimeInterval(1800)
        }
    }
}

/// One persisted value per key; every change posts `Settings.changed`.
final class Settings {
    static let shared = Settings()
    static let changed = Notification.Name("DhakaSkySettingsChanged")
    private let d = UserDefaults.standard

    private init() {
        // v2 kept the user's photo in a separate "scene" setting that overrode the view; it's now just another view.
        if let old = d.string(forKey: "scene") {
            if old.hasPrefix("custom:") { d.set(old, forKey: "view") }
            d.removeObject(forKey: "scene")
        }
    }

    private func get<T>(_ k: String, _ def: T) -> T { d.object(forKey: k) as? T ?? def }
    private func set(_ k: String, _ v: Any?) {
        d.set(v, forKey: k)
        NotificationCenter.default.post(name: Settings.changed, object: k)
    }

    /// A `Landmark` raw value, "rotate", or "custom:<filename>".
    var landmark: String { get { get("landmark", "rotate") } set { set("landmark", newValue) } }
    /// A `ViewKind` raw value, "rotate", or "custom:<filename>" for one of the user's photos.
    var view: String { get { get("view", "lakeside") } set { set("view", newValue) } }
    /// Show the current frame on the lock screen (by keeping the system desktop picture in sync).
    var lockScreen: Bool { get { get("lockScreen", true) } set { set("lockScreen", newValue) } }
    /// Start the Dhaka Sky screen saver as soon as the screen locks, so the lock screen is animated.
    var lockAnimation: Bool { get { get("lockAnimation", true) } set { set("lockAnimation", newValue) } }
    /// How often the lock-screen still is refreshed, in minutes.
    var lockRefresh: Int { get { get("lockRefresh", 5) } set { set("lockRefresh", newValue) } }
    /// "live" or a `Condition` raw value.
    var weatherOverride: String { get { get("weatherOverride", "live") } set { set("weatherOverride", newValue) } }
    var timeOverride: TimeOverride {
        get { TimeOverride(rawValue: get("timeOverride", "live")) ?? .live }
        set { set("timeOverride", newValue.rawValue) }
    }
    var showTraffic: Bool { get { get("showTraffic", true) } set { set("showTraffic", newValue) } }
    var showPeople: Bool { get { get("showPeople", true) } set { set("showPeople", newValue) } }
    var showBoats: Bool { get { get("showBoats", true) } set { set("showBoats", newValue) } }
    var showBirds: Bool { get { get("showBirds", true) } set { set("showBirds", newValue) } }
    var showTrees: Bool { get { get("showTrees", true) } set { set("showTrees", newValue) } }
    var showPlanes: Bool { get { get("showPlanes", true) } set { set("showPlanes", newValue) } }
    /// Extra darkening for eye comfort, 0...0.4.
    var dim: Double { get { get("dim", 0.0) } set { set("dim", newValue) } }
    var soundEnabled: Bool { get { get("soundEnabled", false) } set { set("soundEnabled", newValue) } }
    var soundRain: Bool { get { get("soundRain", true) } set { set("soundRain", newValue) } }
    var soundThunder: Bool { get { get("soundThunder", true) } set { set("soundThunder", newValue) } }
    var soundStreet: Bool { get { get("soundStreet", false) } set { set("soundStreet", newValue) } }
    var soundBells: Bool { get { get("soundBells", true) } set { set("soundBells", newValue) } }
    var soundVolume: Double { get { get("soundVolume", 0.5) } set { set("soundVolume", newValue) } }
    var showGrain: Bool { get { get("showGrain", true) } set { set("showGrain", newValue) } }
    var fps: Int { get { get("fps", 30) } set { set("fps", newValue) } }
    var batterySaver: Bool { get { get("batterySaver", true) } set { set("batterySaver", newValue) } }

    static func defaultBool(_ key: String) -> Bool {
        ["soundEnabled": false, "soundStreet": false][key] ?? true
    }

    /// Today's view as a `ViewKind` raw value or "custom:<filename>"; "rotate" cycles through views and photos.
    var effectiveChoice: String {
        guard view == "rotate" else { return view }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Solar.dhaka
        let day = cal.ordinality(of: .day, in: .era, for: Date()) ?? 0
        let all = ViewKind.allCases.map(\.rawValue) + Settings.customFiles(prefix: "scene-").map { "custom:\($0)" }
        return all[day % all.count]
    }

    var effectiveView: ViewKind { ViewKind(rawValue: effectiveChoice) ?? .lakeside }

    /// "custom:<filename>" while one of the user's photos is showing.
    var effectivePhoto: String? { effectiveChoice.hasPrefix("custom:") ? effectiveChoice : nil }

    var effectiveLandmark: String {
        guard landmark == "rotate" else { return landmark }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Solar.dhaka
        let day = cal.ordinality(of: .day, in: .era, for: Date()) ?? 0
        return Landmark.rotating[day % Landmark.rotating.count].rawValue
    }

    static var customDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("DhakaSky/Custom", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func customFiles(prefix: String) -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: customDir.path)) ?? []
        return files.filter { $0.hasPrefix(prefix) }.sorted()
    }
}
