import AppKit
import SpriteKit

/// macOS draws the lock screen from the desktop picture, and only the system can animate it.
/// So while this is on, the current frame of each screen is saved as that screen's desktop picture
/// (hidden behind the live wallpaper) every few minutes and just before the screen locks or sleeps.
/// Turning it off puts the user's original pictures back.
enum LockScreen {
    private static let originalsKey = "lockScreenOriginals"
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

    static func update(_ windows: [WallpaperWindow]) {
        let ws = NSWorkspace.shared
        var originals = UserDefaults.standard.dictionary(forKey: originalsKey) as? [String: String] ?? [:]
        let stamp = Int(Date().timeIntervalSince1970)
        for w in windows {
            let screen = w.targetScreen, id = displayID(screen)
            // Remember the user's own picture once, so it can be restored.
            if originals[id] == nil, let cur = ws.desktopImageURL(for: screen), !cur.path.hasPrefix(dir.path) {
                originals[id] = cur.absoluteString
            }
            w.cityScene.catchUp()
            guard let tex = w.skView.texture(from: w.cityScene) else { continue }
            let rep = NSBitmapImageRep(cgImage: tex.cgImage())
            guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else { continue }
            // A fresh file name each time: the system caches pictures by URL.
            let url = dir.appendingPathComponent("lock-\(id)-\(stamp).jpg")
            do {
                try data.write(to: url)
                try ws.setDesktopImageURL(url, for: screen, options: [
                    .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue, .allowClipping: true,
                ])
            } catch { continue }
            removeOld(id: id, keep: url)
        }
        UserDefaults.standard.set(originals, forKey: originalsKey)
    }

    /// Put back the pictures the user had before, and forget the saved frames.
    static func restore() {
        guard var originals = UserDefaults.standard.dictionary(forKey: originalsKey) as? [String: String] else { return }
        for screen in NSScreen.screens {
            let id = displayID(screen)
            guard let s = originals[id], let url = URL(string: s), FileManager.default.fileExists(atPath: url.path),
                  (try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])) != nil else { continue }
            originals[id] = nil
            // The screen shows the user's picture again, so its stills can go. Screens that couldn't be restored keep theirs.
            for f in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            where f.lastPathComponent.hasPrefix("lock-\(id)-") {
                try? FileManager.default.removeItem(at: f)
            }
        }
        if originals.isEmpty { UserDefaults.standard.removeObject(forKey: originalsKey) }
        else { UserDefaults.standard.set(originals, forKey: originalsKey) }
    }

    private static func removeOld(id: String, keep: URL) {
        for f in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        where f.lastPathComponent.hasPrefix("lock-\(id)-") && f != keep {
            try? FileManager.default.removeItem(at: f)
        }
    }
}

/// Keeps the Dhaka Sky screen saver (which macOS can run over the lock screen) in step with the app.
/// The saver runs sandboxed, so it can't read the app's settings; they are copied into its sandbox instead.
enum SaverSync {
    static let saverURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Screen Savers/Dhaka Sky.saver")
    static var installed: Bool { FileManager.default.fileExists(atPath: saverURL.path) }
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
