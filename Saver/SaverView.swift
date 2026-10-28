import AppKit
import ScreenSaver
import SpriteKit

/// Dhaka Sky as a screen saver, so the animation also plays over the lock screen.
/// It runs inside macOS's sandboxed screen-saver host, so the app copies its settings
/// (and custom photos) into that sandbox; see `SaverSync` in the app.
@objc(DhakaSkySaverView)
final class DhakaSkySaverView: ScreenSaverView {
    private var skView: SKView?
    private var scene: CityScene?
    private let weather = WeatherService()
    private var minuteTimer: Timer?

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        Self.loadSettings()
        Self.log("start \(Int(frame.width))x\(Int(frame.height)) preview=\(isPreview) view=\(Settings.shared.view)")
        animationTimeInterval = 1.0 / 30
        let view = SKView(frame: bounds)
        view.autoresizingMask = [.width, .height]
        view.ignoresSiblingOrder = true
        view.shouldCullNonVisibleNodes = true
        view.preferredFramesPerSecond = isPreview ? 20 : Settings.shared.fps
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        Painter.scale = isPreview ? 1 : scale
        let s = CityScene(size: frame.size, scale: Painter.scale)
        s.clock = Self.virtualClock()
        view.presentScene(s)
        addSubview(view)
        skView = view; scene = s

        weather.onUpdate = { [weak self] snap in
            Self.log("weather: \(snap.condition.rawValue)")
            self?.scene?.weatherTarget = Self.params(live: snap)
        }
        scene?.weatherTarget = Self.params(live: nil)
        resume()
    }

    /// Weather polling, the settings timer and the "saver is stopping" observer; undone by `shutDown()`.
    private func resume() {
        guard minuteTimer == nil else { return }
        weather.start()
        minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.scene?.applySettings() }
        // The host sometimes keeps a saver alive after it is dismissed; stop drawing when that happens.
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(willStop),
                                                            name: Notification.Name("com.apple.screensaver.willstop"), object: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit { shutDown() }

    /// The host can keep old saver views alive, so stop timers, polling and observers as soon as one is finished with.
    private func shutDown() {
        minuteTimer?.invalidate(); minuteTimer = nil
        weather.stop()
        DistributedNotificationCenter.default().removeObserver(self)
        skView?.isPaused = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { shutDown() }
    }

    override func startAnimation() { super.startAnimation(); resume(); skView?.isPaused = false }
    override func stopAnimation() { super.stopAnimation(); skView?.isPaused = true }
    override func animateOneFrame() {}  // SpriteKit drives the frames
    override var hasConfigureSheet: Bool { false }

    @objc private func willStop() { shutDown() }

    // MARK: Settings handed over by the app

    static var sharedDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DhakaSky", isDirectory: true)
    }

    /// Written inside the saver's sandbox: ~/Library/Containers/com.apple.ScreenSaver.Engine.legacyScreenSaver/Data/Library/Logs.
    static func log(_ msg: String) {
        let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("DhakaSky-saver.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(msg)\n"
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() } else { try? Data(line.utf8).write(to: url) }
    }

    private static func loadSettings() {
        let url = sharedDir.appendingPathComponent("settings.plist")
        guard let dict = NSDictionary(contentsOf: url) as? [String: Any] else { return }
        UserDefaults.standard.register(defaults: dict)
    }

    private static func virtualClock() -> () -> Date {
        let t = Settings.shared.timeOverride
        if t == .live { return { Date() } }
        let fixed = t.date()
        return { fixed }
    }

    private static func params(live: WeatherSnapshot?) -> WeatherParams {
        let o = Settings.shared.weatherOverride
        if o != "live", let c = Condition(rawValue: o) { return WeatherSnapshot.preset(c).params }
        return (live ?? WeatherSnapshot.preset(.partlyCloudy)).params
    }
}
