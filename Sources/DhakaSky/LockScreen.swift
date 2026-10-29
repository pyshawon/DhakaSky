import AppKit
import SpriteKit

/// macOS draws the lock screen from the desktop picture, so while this is on each screen's desktop picture
/// (hidden behind the live wallpaper) is a still of Dhaka Sky. Turning it off puts the user's own pictures back.
///
/// Every new desktop picture makes macOS keep a full-size uncompressed copy (tens of MB) in its wallpaper cache,
/// a folder apps can't clean up. So stills are never re-rendered on a timer. There is one fixed file per
/// look (the settings that change the picture, plus day / golden hour / night and dry / wet), written once and
/// reused: switching back to a look points at the same, unchanged file, which macOS already has cached.
/// New cache entries only appear when the user changes how the scene looks, and the files kept here are capped.
enum LockScreen {
    private static let originalsKey = "lockScreenOriginals"
    private static let usedKey = "lockScreenStillsUsed"
    private static let maxStills = 24
    private static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("DhakaSky/LockScreen", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// True while some screen's desktop picture is a Dhaka Sky still (also after a crash, until restored).
    static var hasOriginals: Bool { UserDefaults.standard.dictionary(forKey: originalsKey)?.isEmpty == false }

    static func displayID(_ screen: NSScreen) -> String {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? "main"
    }

    /// Show the still for the current look, rendering it only if this look has never been saved.
    /// `look` is `Settings.pictureSignature`: the settings that change the picture.
    static func update(_ windows: [WallpaperWindow], look: String) {
        let ws = NSWorkspace.shared, fm = FileManager.default, folder = dir
        var originals = UserDefaults.standard.dictionary(forKey: originalsKey) as? [String: String] ?? [:]
        var used = UserDefaults.standard.dictionary(forKey: usedKey) as? [String: Double] ?? [:]
        var changed = false
        for w in windows {
            let screen = w.targetScreen, id = displayID(screen)
            let m = moment(w.cityScene)
            let size = "\(Int(w.frame.width))x\(Int(w.frame.height))"
            let name = "lock-\(id)-\(stableHash("\(look)|\(size)|\(m.key)")).jpg"
            let url = folder.appendingPathComponent(name)
            let current = ws.desktopImageURL(for: screen)
            if current?.standardizedFileURL == url.standardizedFileURL, fm.fileExists(atPath: url.path) { continue }  // already showing
            // Remember the user's own picture once, so it can be restored.
            if originals[id] == nil, let cur = current, !cur.path.hasPrefix(folder.path) {
                originals[id] = cur.absoluteString
            }
            if !fm.fileExists(atPath: url.path) {
                guard let img = w.cityScene.renderStill(in: w.skView, at: m.date, weather: m.weather),
                      let data = NSBitmapImageRep(cgImage: img).representation(using: .jpeg, properties: [.compressionFactor: 0.85]),
                      (try? data.write(to: url)) != nil else { continue }
            }
            guard (try? ws.setDesktopImageURL(url, for: screen, options: [
                .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true,
            ])) != nil else { continue }
            used[name] = Date().timeIntervalSince1970
            changed = true
        }
        // Defaults are only written when a picture actually changed (writing them wakes the whole settings chain).
        guard changed else { return }
        prune(&used)
        UserDefaults.standard.set(originals, forKey: originalsKey)
        UserDefaults.standard.set(used, forKey: usedKey)
    }

    /// Keep the most recently used stills (about 1 MB each), never one that a screen is showing, and always the
    /// latest one of every display, so a monitor that is unplugged for a while still has its picture when it returns.
    private static func prune(_ used: inout [String: Double]) {
        let fm = FileManager.default
        let showing = Set(NSScreen.screens.compactMap { NSWorkspace.shared.desktopImageURL(for: $0)?.lastPathComponent })
        var keep = Set(used.sorted { $0.value > $1.value }.prefix(maxStills).map(\.key)).union(showing)
        var latest: [String: (String, Double)] = [:]
        for (name, t) in used {
            let id = name.split(separator: "-").dropFirst().first.map(String.init) ?? ""
            if t > latest[id]?.1 ?? 0 { latest[id] = (name, t) }
        }
        keep.formUnion(latest.values.map(\.0))
        used = used.filter { keep.contains($0.key) }
        for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] where !keep.contains(f.lastPathComponent) {
            try? fm.removeItem(at: f)
        }
    }

    /// The still for a moment depends only on the light (day, golden hour, night) and whether it is raining. Each is
    /// drawn at a fixed time and in fixed weather, so the saved picture is the same whenever it is first made.
    private static func moment(_ scene: CityScene) -> (key: String, date: Date, weather: WeatherParams) {
        let now = scene.clock()
        let sun = Solar.sun(at: now).elevation
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = Solar.dhaka
        let start = cal.startOfDay(for: now)
        let (light, date): (String, Date) =
            sun > 8 ? ("day", start.addingTimeInterval(11 * 3600)) :
            sun > -6 ? ("golden", Solar.time(forElevation: 2, morning: false, on: now)) :
            ("night", start.addingTimeInterval(21.5 * 3600))
        let w = scene.weatherTarget
        let wet = w.rain > 0.15 || w.storm > 0.2
        return ("\(light)-\(wet ? "wet" : "dry")", date, WeatherSnapshot.preset(wet ? .rain : .partlyCloudy).params)
    }

    /// FNV-1a: stable across launches (Swift's Hasher is not), so the same look always maps to the same file.
    private static func stableHash(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return String(h, radix: 16)
    }

    /// Put back the pictures the user had before.
    /// `deleteStills` when the feature is turned off: the saved stills go too. On quit they stay, so the next launch
    /// reuses them (setting an unchanged file again costs nothing).
    static func restore(deleteStills: Bool = false) {
        defer {
            if deleteStills, !hasOriginals {
                try? FileManager.default.removeItem(at: dir)
                UserDefaults.standard.removeObject(forKey: usedKey)
            }
        }
        guard var originals = UserDefaults.standard.dictionary(forKey: originalsKey) as? [String: String] else { return }
        for screen in NSScreen.screens {
            let id = displayID(screen)
            guard let s = originals[id], let url = URL(string: s), FileManager.default.fileExists(atPath: url.path),
                  (try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])) != nil else { continue }
            originals[id] = nil
        }
        if originals.isEmpty { UserDefaults.standard.removeObject(forKey: originalsKey) }
        else { UserDefaults.standard.set(originals, forKey: originalsKey) }
    }
}

/// Keeps the Dhaka Sky screen saver (which macOS can run over the lock screen) in step with the app.
/// The saver runs sandboxed, so it can't read the app's settings; they are copied into its sandbox instead.
enum SaverSync {
    static let saverURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Screen Savers/Dhaka Sky.saver")
    static var installed: Bool { FileManager.default.fileExists(atPath: saverURL.path) }

    /// The app carries a copy of the saver (Contents/Resources/Dhaka Sky.saver), so a downloaded app works on its own.
    /// Install it, or replace an installed copy from a different build.
    static func installBundled() {
        guard let bundled = Bundle.main.url(forResource: "Dhaka Sky", withExtension: "saver") else { return }
        let fm = FileManager.default
        func version(_ url: URL) -> String? { Bundle(url: url)?.infoDictionary?["CFBundleVersion"] as? String }
        func binaryDate(_ url: URL) -> Date? {
            (try? fm.attributesOfItem(atPath: url.appendingPathComponent("Contents/MacOS/DhakaSky").path))?[.modificationDate] as? Date
        }
        if installed, version(saverURL) == version(bundled), binaryDate(saverURL) == binaryDate(bundled) { return }
        do {
            try fm.createDirectory(at: saverURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if installed { try fm.removeItem(at: saverURL) }
            try fm.copyItem(at: bundled, to: saverURL)
            // A downloaded app's files carry the quarantine flag, which would stop the screen saver host loading this copy.
            let xattr = Process()
            xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            xattr.arguments = ["-dr", "com.apple.quarantine", saverURL.path]
            try? xattr.run()
            xattr.waitUntilExit()
            log("installed the screen saver from the app bundle")
        } catch {
            log("couldn't install the screen saver: \(error.localizedDescription)")
        }
    }
    private static let sandboxDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Application Support/DhakaSky", isDirectory: true)
    private static let keys = ["view", "landmark", "weatherOverride", "timeOverride", "showTraffic", "showPeople", "showBoats",
                               "showBirds", "showTrees", "showPlanes", "dim", "showGrain", "fps"]

    static func sync() {
        guard installed else { return }
        let fm = FileManager.default, d = UserDefaults.standard
        do {
            try fm.createDirectory(at: sandboxDir.appendingPathComponent("Custom"), withIntermediateDirectories: true)
            var dict: [String: Any] = [:]
            for k in keys { if let v = d.object(forKey: k) { dict[k] = v } }
            (dict as NSDictionary).write(to: sandboxDir.appendingPathComponent("settings.plist"), atomically: true)
            // Mirror the user's photos and landmark images.
            let src = Settings.customDir, dst = sandboxDir.appendingPathComponent("Custom")
            let want = Set((try? fm.contentsOfDirectory(atPath: src.path)) ?? [])
            let have = Set((try? fm.contentsOfDirectory(atPath: dst.path)) ?? [])
            for f in have.subtracting(want) { try? fm.removeItem(at: dst.appendingPathComponent(f)) }
            func modified(_ u: URL) -> Date? { (try? fm.attributesOfItem(atPath: u.path))?[.modificationDate] as? Date }
            for f in want {
                let from = src.appendingPathComponent(f), to = dst.appendingPathComponent(f)
                // Copy new photos, and ones re-imported under the same name.
                if have.contains(f), let a = modified(from), let b = modified(to), a <= b { continue }
                try? fm.removeItem(at: to)
                try? fm.copyItem(at: from, to: to)
            }
        } catch {
            NSLog("DhakaSky: couldn't update the screen saver's settings: \(error.localizedDescription)")
        }
    }

    /// Whether Dhaka Sky is the screen saver chosen in System Settings (macOS keeps that choice in the wallpaper store).
    static var isSelected: Bool {
        let store = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        guard let data = try? Data(contentsOf: store) else { return false }
        return data.range(of: Data("Dhaka Sky.saver".utf8)) != nil || data.range(of: Data("Dhaka%20Sky.saver".utf8)) != nil
    }

    /// Make Dhaka Sky the screen saver, the same choice System Settings > Screen Saver makes. macOS keeps it in the
    /// wallpaper store: every "Idle" entry holds a list of choices, and a legacy .saver is a "screen-saver" choice whose
    /// configuration is a small plist pointing at the bundle. The previous store is kept as Index.plist.dhakasky-backup.
    @discardableResult
    static func select() -> Bool {
        guard installed else { return false }
        let store = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        guard let data = try? Data(contentsOf: store),
              var root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let config = try? PropertyListSerialization.data(fromPropertyList: ["module": ["relative": saverURL.absoluteString]],
                                                               format: .binary, options: 0)
        else { log("couldn't read the wallpaper store"); return false }
        let choice: [String: Any] = ["Provider": "com.apple.wallpaper.choice.screen-saver", "Configuration": config, "Files": [Any]()]
        func patch(_ any: Any) -> Any {
            guard var dict = any as? [String: Any] else { return any }
            for (k, v) in dict {
                if k == "Idle", var idle = v as? [String: Any], var content = idle["Content"] as? [String: Any] {
                    content["Choices"] = [choice]
                    idle["Content"] = content
                    idle["LastSet"] = Date()
                    dict[k] = idle
                } else {
                    dict[k] = patch(v)
                }
            }
            return dict
        }
        root = patch(root) as? [String: Any] ?? root
        guard let out = try? PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0) else { return false }
        let backup = store.appendingPathExtension("dhakasky-backup")
        if !FileManager.default.fileExists(atPath: backup.path) { try? FileManager.default.copyItem(at: store, to: backup) }
        do { try out.write(to: store, options: .atomic) } catch { log("couldn't write the wallpaper store: \(error.localizedDescription)"); return false }
        // WallpaperAgent caches the store; restarting it (launchd brings it straight back) makes the choice take effect.
        let kill = Process()
        kill.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        kill.arguments = ["WallpaperAgent"]
        try? kill.run()
        kill.waitUntilExit()
        log("selected Dhaka Sky as the screen saver")
        return true
    }

    /// Start the screen saver now (used the moment the screen locks).
    static func start() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app"),
                                           configuration: NSWorkspace.OpenConfiguration()) { app, error in
            log(error.map { "screen saver failed to start: \($0.localizedDescription)" } ?? "screen saver started (pid \(app?.processIdentifier ?? 0))")
        }
    }

    /// A short diagnostic trail in ~/Library/Logs/DhakaSky.log.
    static func log(_ msg: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DhakaSky.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(msg)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }

    static func openScreenSaverSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension") { NSWorkspace.shared.open(url) }
    }
}
