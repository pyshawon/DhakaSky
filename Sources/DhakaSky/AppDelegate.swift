import AppKit
import IOKit.ps
import ServiceManagement
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var windows: [WallpaperWindow] = []
    private let weather = WeatherService()
    private var statusItem: NSStatusItem!
    private var virtualTime: Date?          // cached time-of-day override
    private var minuteTimer: Timer?
    private var onBattery = false
    private let settings = Settings.shared
    private let sound = SoundScape()
    private var soundTimer: Timer?
    private var asleep = false
    private var lockTimer: Timer?
    private var lockSignature = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusIcon()

        buildWindows()
        weather.onUpdate = { [weak self] _ in self?.pushWeather(); self?.updateStatusIcon() }
        weather.start()

        let nc = NotificationCenter.default, ws = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(settingsChanged(_:)), name: Settings.changed, object: nil)
        nc.addObserver(self, selector: #selector(defaultsChanged), name: UserDefaults.didChangeNotification, object: nil)
        nc.addObserver(forName: CustomImages.changed, object: nil, queue: .main) { [weak self] _ in
            self?.windows.forEach { $0.cityScene.reloadCustomArt() }
            SaverSync.sync()
        }
        nc.addObserver(self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        ws.addObserver(self, selector: #selector(sleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(refreshLockScreen), name: NSWorkspace.willSleepNotification, object: nil)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(screenLocked),
                                                            name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        ws.addObserver(self, selector: #selector(sleep), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        ws.addObserver(self, selector: #selector(wake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(wake), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        ws.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)

        soundTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.updateSound() }
        refreshVirtualTime()
        minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.tick() }
        tick()
        applyLockScreen()
        // Animating the lock screen needs Dhaka Sky to be the screen saver; choose it once on the user's behalf.
        let d = UserDefaults.standard
        if settings.lockAnimation, SaverSync.installed, !SaverSync.isSelected, !d.bool(forKey: "saverAutoSelected") {
            d.set(SaverSync.select(), forKey: "saverAutoSelected")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if LockScreen.hasOriginals { LockScreen.restore() }
    }

    // MARK: Lock screen

    /// Start or stop keeping the lock screen (desktop picture) in sync with the live wallpaper.
    private func applyLockScreen() {
        // Only react to changes that alter the picture (saving the still itself writes defaults too).
        let d = UserDefaults.standard
        let sig = ["lockScreen", "lockAnimation", "lockRefresh", "showTraffic", "showPeople", "showBoats", "showBirds", "showPlanes", "showGrain", "fps", "view", "landmark", "weatherOverride", "timeOverride", "dim", "showTrees"]
            .map { "\(d.object(forKey: $0) ?? "-")" }.joined(separator: "|")
        guard sig != lockSignature else { return }
        lockSignature = sig
        SaverSync.sync()
        if settings.lockScreen {
            lockTimer?.invalidate()
            let every = TimeInterval(max(1, settings.lockRefresh) * 60)
            lockTimer = Timer.scheduledTimer(withTimeInterval: every, repeats: true) { [weak self] _ in self?.refreshLockScreen() }
            // Let a new view or weather settle in before taking the still.
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(refreshLockScreen), object: nil)
            perform(#selector(refreshLockScreen), with: nil, afterDelay: 3)
        } else {
            lockTimer?.invalidate(); lockTimer = nil
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(refreshLockScreen), object: nil)
            if LockScreen.hasOriginals { LockScreen.restore() }
        }
    }

    @objc private func screenLocked() {
        refreshLockScreen()
        SaverSync.log("screen locked; animate=\(settings.lockAnimation) installed=\(SaverSync.installed) selected=\(SaverSync.isSelected)")
        // Only when Dhaka Sky is the chosen saver: otherwise this would start someone else's saver on every lock.
        if settings.lockAnimation && SaverSync.installed && SaverSync.isSelected { SaverSync.start() }
    }

    @objc private func refreshLockScreen() {
        // No point rendering stills while the displays sleep; sleep() takes one on the way down.
        guard settings.lockScreen, !asleep, !windows.isEmpty else { return }
        LockScreen.update(windows)
    }

    // MARK: Windows

    private func buildWindows() {
        windows.forEach { $0.orderOut(nil) }
        windows = NSScreen.screens.map { WallpaperWindow(screen: $0) }
        windows.first?.cityScene.onLightning = { [weak self] close in
            guard let self, self.settings.soundEnabled, self.settings.soundThunder else { return }
            self.sound.thunder(close: close)
        }
        for w in windows {
            w.cityScene.clock = { [weak self] in self?.virtualTime ?? Date() }
            NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged(_:)),
                                                   name: NSWindow.didChangeOcclusionStateNotification, object: w)
            w.orderFrontRegardless()
        }
        pushWeather()
        applyFrameRate()
    }

    @objc private func screensChanged() {
        // Debounce: displays often report several changes in a row.
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(rebuildNow), object: nil)
        perform(#selector(rebuildNow), with: nil, afterDelay: 1.0)
    }

    @objc private func rebuildNow() { buildWindows() }

    @objc private func occlusionChanged(_ n: Notification) {
        guard let w = n.object as? WallpaperWindow else { return }
        w.skView.isPaused = !w.occlusionState.contains(.visible)
    }

    @objc private func sleep() { refreshLockScreen(); asleep = true; windows.forEach { $0.skView.isPaused = true }; updateSound() }
    @objc private func wake() { asleep = false; windows.forEach { $0.skView.isPaused = !$0.occlusionState.contains(.visible) }; updateSound() }

    private func updateSound() {
        guard settings.soundEnabled, !asleep, let scene = windows.first?.cityScene else { sound.stop(); return }
        sound.start()
        sound.volume = Float(settings.soundVolume)
        sound.rain = settings.soundRain ? Float(scene.weather.rain) : 0
        sound.bells = settings.soundBells
        let hour = Solar.localHour(virtualTime ?? Date())
        let busy: Float = hour >= 7 && hour < 22 ? 1 : (hour >= 5 ? 0.5 : 0.15)
        sound.street = (settings.soundStreet || settings.soundBells) && settings.showTraffic ? busy * Float(1 - scene.weather.rain * 0.6) : 0
        sound.humLevel = settings.soundStreet ? 1 : 0
    }

    // MARK: State → scenes

    private func currentParams() -> WeatherParams {
        if settings.weatherOverride != "live", let c = Condition(rawValue: settings.weatherOverride) {
            var snap = WeatherSnapshot.preset(c)
            snap.pm25 = weather.latest?.pm25 ?? 25
            return snap.params
        }
        var p = (weather.latest ?? WeatherSnapshot.preset(.clear)).params
        // Dhaka winter mornings are misty even when the station doesn't report fog.
        let now = virtualTime ?? Date()
        let month = Solar.month(now), hour = Solar.localHour(now)
        if [12, 1, 2].contains(month) && hour >= 5 && hour < 9.5 { p.fog = max(p.fog, 0.35) }
        return p
    }

    private func pushWeather() {
        let p = currentParams()
        windows.forEach { $0.cityScene.weatherTarget = p }
    }

    private func refreshVirtualTime() {
        let t = settings.timeOverride
        virtualTime = t == .live ? nil : t.date()
    }

    private func tick() {
        refreshVirtualTime()
        let battery = Self.isOnBattery()
        if battery != onBattery { onBattery = battery; applyFrameRate() }
        windows.forEach { $0.cityScene.applySettings() }  // picks up daily landmark rotation & seasonal blossoms
        pushWeather()
        updateStatusIcon()
    }

    private func applyFrameRate() {
        let fps = onBattery && settings.batterySaver ? min(20, settings.fps) : settings.fps
        windows.forEach { $0.skView.preferredFramesPerSecond = fps }
    }

    @objc private func defaultsChanged() {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(applyDefaults), object: nil)
        perform(#selector(applyDefaults), with: nil, afterDelay: 0.05)
    }

    @objc private func applyDefaults() { settingsChanged(Notification(name: Settings.changed)) }

    @objc private func settingsChanged(_ n: Notification) {
        updateSound()
        refreshVirtualTime()
        windows.forEach { $0.cityScene.applySettings() }
        pushWeather()
        applyFrameRate()
        updateStatusIcon()
        applyLockScreen()
    }

    static func isOnBattery() -> Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return false }
        return type == kIOPMBatteryPowerKey
    }

    // MARK: Menu bar

    private func displayedCondition() -> (Condition, Bool) {
        let isDay = Solar.sun(at: virtualTime ?? Date()).elevation > -2
        if let c = Condition(rawValue: settings.weatherOverride) { return (c, isDay) }
        return (weather.latest?.condition ?? .clear, isDay)
    }

    private func updateStatusIcon() {
        let (c, day) = displayedCondition()
        let img = NSImage(systemSymbolName: c.symbol(isDay: day), accessibilityDescription: "Dhaka Sky")
        img?.isTemplate = true
        statusItem.button?.image = img
        if let t = weather.latest?.temperature { statusItem.button?.title = " \(Int(t.rounded()))°" }
        statusItem.button?.imagePosition = .imageLeading
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let w = weather.latest {
            var line = "Dhaka · \(w.condition.title)"
            if let t = w.temperature { line += " · \(Int(t.rounded()))°C" }
            if let a = w.aqi { line += " · AQI \(a)" }
            menu.addItem(disabled(line))
            if let at = w.fetchedAt {
                let f = RelativeDateTimeFormatter()
                menu.addItem(disabled("Updated \(f.localizedString(for: at, relativeTo: Date()))"))
            }
        } else {
            menu.addItem(disabled(weather.lastError.map { "Weather: \($0)" } ?? "Fetching Dhaka weather…"))
        }
        menu.addItem(item("Refresh Weather", #selector(refreshWeather)))
        menu.addItem(.separator())

        // View
        let vw = NSMenu()
        for v in ViewKind.allCases { vw.addItem(choice(v.title, settings.view == v.rawValue, #selector(pickView(_:)), v.rawValue)) }
        let photos = Settings.customFiles(prefix: "scene-")
        if !photos.isEmpty {
            vw.addItem(.separator())
            for f in photos { vw.addItem(choice("Photo: \(prettyName(f))", settings.view == "custom:\(f)", #selector(pickView(_:)), "custom:\(f)")) }
        }
        vw.addItem(.separator())
        vw.addItem(choice("Rotate Daily", settings.view == "rotate", #selector(pickView(_:)), "rotate"))
        vw.addItem(.separator())
        vw.addItem(item("Add Your Own Photo…", #selector(addScene)))
        vw.addItem(item("Open Custom Images Folder", #selector(openCustomFolder)))
        menu.addItem(submenu("View", vw))

        // Landmark
        let lm = NSMenu()
        lm.addItem(choice("Rotate Daily", settings.landmark == "rotate", #selector(pickLandmark(_:)), "rotate"))
        lm.addItem(.separator())
        for l in Landmark.allCases { lm.addItem(choice(l.title, settings.landmark == l.rawValue, #selector(pickLandmark(_:)), l.rawValue)) }
        let customs = Settings.customFiles(prefix: "landmark-")
        if !customs.isEmpty {
            lm.addItem(.separator())
            for f in customs { lm.addItem(choice(prettyName(f), settings.landmark == "custom:\(f)", #selector(pickLandmark(_:)), "custom:\(f)")) }
        }
        lm.addItem(.separator())
        lm.addItem(item("Add Your Own Landmark Image…", #selector(addLandmark)))
        menu.addItem(submenu("Landmark", lm))

        // Elements
        let el = NSMenu()
        el.addItem(toggle("Rickshaws & Traffic", settings.showTraffic, "showTraffic"))
        el.addItem(toggle("People on the Footpath", settings.showPeople, "showPeople"))
        el.addItem(toggle("Boats on the Lake", settings.showBoats, "showBoats"))
        el.addItem(toggle("Birds", settings.showBirds, "showBirds"))
        el.addItem(toggle("Aeroplanes", settings.showPlanes, "showPlanes"))
        el.addItem(toggle("Krishnachura & Palm Trees", settings.showTrees, "showTrees"))
        menu.addItem(submenu("Elements", el))
        menu.addItem(.separator())

        // Weather / time preview
        let wx = NSMenu()
        wx.addItem(choice("Live (Dhaka)", settings.weatherOverride == "live", #selector(pickWeather(_:)), "live"))
        wx.addItem(.separator())
        for c in Condition.allCases { wx.addItem(choice(c.title, settings.weatherOverride == c.rawValue, #selector(pickWeather(_:)), c.rawValue)) }
        menu.addItem(submenu("Weather", wx))
        let tm = NSMenu()
        for t in TimeOverride.allCases {
            tm.addItem(choice(t.title, settings.timeOverride == t, #selector(pickTime(_:)), t.rawValue))
            if t == .live { tm.addItem(.separator()) }
        }
        menu.addItem(submenu("Time of Day", tm))

        // Sound
        let sd = NSMenu()
        sd.addItem(toggle("Sound On", settings.soundEnabled, "soundEnabled"))
        sd.addItem(.separator())
        sd.addItem(toggle("Rain", settings.soundRain, "soundRain"))
        sd.addItem(toggle("Thunder", settings.soundThunder, "soundThunder"))
        sd.addItem(toggle("Distant City Hum", settings.soundStreet, "soundStreet"))
        sd.addItem(toggle("Rickshaw Bells", settings.soundBells, "soundBells"))
        menu.addItem(submenu("Sound", sd))

        // Comfort
        let cm = NSMenu()
        for (label, v) in [("No Dimming", 0.0), ("Dim 10%", 0.1), ("Dim 20%", 0.2), ("Dim 35%", 0.35)] {
            cm.addItem(choice(label, abs(settings.dim - v) < 0.01, #selector(pickDim(_:)), String(v)))
        }
        cm.addItem(.separator())
        for f in [20, 30, 60] { cm.addItem(choice("\(f) fps", settings.fps == f, #selector(pickFPS(_:)), String(f))) }
        cm.addItem(toggle("Battery Saver (20 fps on battery)", settings.batterySaver, "batterySaver"))
        cm.addItem(.separator())
        cm.addItem(toggle("Show on Lock Screen", settings.lockScreen, "lockScreen"))
        cm.addItem(toggle("Animate Lock Screen (Screen Saver)", settings.lockAnimation, "lockAnimation"))
        let lr = NSMenu()
        for m in [1, 2, 5, 10, 15] { lr.addItem(choice("Every \(m) min", settings.lockRefresh == m, #selector(pickLockRefresh(_:)), String(m))) }
        cm.addItem(submenu("Lock Screen Refresh", lr))
        menu.addItem(submenu("Comfort & Performance", cm))
        menu.addItem(.separator())

        let prefs = item("Settings…", #selector(openSettings))
        prefs.keyEquivalent = ","
        menu.addItem(prefs)
        let login = item("Launch at Login", #selector(toggleLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item("Quit Dhaka Sky", #selector(quit)))
    }

    private func disabled(_ t: String) -> NSMenuItem { let i = NSMenuItem(title: t, action: nil, keyEquivalent: ""); i.isEnabled = false; return i }
    private func item(_ t: String, _ sel: Selector) -> NSMenuItem { let i = NSMenuItem(title: t, action: sel, keyEquivalent: ""); i.target = self; return i }
    private func submenu(_ t: String, _ m: NSMenu) -> NSMenuItem { let i = NSMenuItem(title: t, action: nil, keyEquivalent: ""); i.submenu = m; return i }
    private func choice(_ t: String, _ on: Bool, _ sel: Selector, _ value: String) -> NSMenuItem {
        let i = item(t, sel); i.state = on ? .on : .off; i.representedObject = value; return i
    }
    private func toggle(_ t: String, _ on: Bool, _ key: String) -> NSMenuItem { choice(t, on, #selector(flip(_:)), key) }
    private func prettyName(_ f: String) -> String {
        let base = (f as NSString).deletingPathExtension
        return base.split(separator: "-", maxSplits: 1).last.map(String.init)?.replacingOccurrences(of: "_", with: " ") ?? base
    }

    @objc private func refreshWeather() { weather.refresh() }
    @objc private func pickLockRefresh(_ s: NSMenuItem) { settings.lockRefresh = Int(s.representedObject as! String) ?? 5 }
    @objc private func pickView(_ s: NSMenuItem) { settings.view = s.representedObject as! String }
    @objc private func pickLandmark(_ s: NSMenuItem) { settings.landmark = s.representedObject as! String }
    @objc private func pickWeather(_ s: NSMenuItem) { settings.weatherOverride = s.representedObject as! String }
    @objc private func pickTime(_ s: NSMenuItem) { settings.timeOverride = TimeOverride(rawValue: s.representedObject as! String) ?? .live }
    @objc private func pickDim(_ s: NSMenuItem) { settings.dim = Double(s.representedObject as! String) ?? 0 }
    @objc private func pickFPS(_ s: NSMenuItem) { settings.fps = Int(s.representedObject as! String) ?? 30 }
    @objc private func flip(_ s: NSMenuItem) {
        let key = s.representedObject as! String
        let d = UserDefaults.standard
        let current = d.object(forKey: key) as? Bool ?? Settings.defaultBool(key)
        d.set(!current, forKey: key)
        NotificationCenter.default.post(name: Settings.changed, object: key)
    }
    @objc private func openSettings() { SettingsWindow.show(weather: weather) }
    @objc private func openCustomFolder() { NSWorkspace.shared.open(Settings.customDir) }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            alert("Couldn't change Launch at Login", error.localizedDescription)
        }
    }

    // MARK: Custom images

    @objc private func addLandmark() { CustomImages.pickAndImport(kind: .landmark) }
    @objc private func addScene() { CustomImages.pickAndImport(kind: .scene) }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}
