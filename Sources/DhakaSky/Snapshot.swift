import AppKit
import SpriteKit

/// `DhakaSky --snapshot out.png [--time dusk] [--weather rain] [--landmark parliament] [--size 1512x982] [--scale 2]`
final class SnapshotRunner: NSObject, NSApplicationDelegate {
    let output: String
    let args: [String]
    var window: NSWindow?

    init(output: String, args: [String]) { self.output = output; self.args = args }

    func value(_ flag: String) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        var size = CGSize(width: 1512, height: 982)
        if let s = value("--size")?.split(separator: "x"), s.count == 2, let w = Double(s[0]), let h = Double(s[1]) {
            size = CGSize(width: w, height: h)
        }
        let scale = CGFloat(Double(value("--scale") ?? "2") ?? 2)
        // View and landmark go in the argument domain: it overrides the saved settings for this process only,
        // so snapshots never touch the running app's settings and can run in parallel.
        let d = UserDefaults.standard
        var overrides = d.volatileDomain(forName: UserDefaults.argumentDomain)
        overrides["view"] = value("--scene").flatMap { $0 == "city" ? nil : $0 } ?? value("--view") ?? "lakeside"
        if let lm = value("--landmark") { overrides["landmark"] = lm }
        d.setVolatileDomain(overrides, forName: UserDefaults.argumentDomain)

        let start = Date()
        let scene = CityScene(size: size, scale: scale)
        let t = TimeOverride(rawValue: value("--time") ?? "live") ?? .live
        let clockTime = t.date()
        scene.clock = { clockTime }
        if let w = value("--weather"), let c = Condition(rawValue: w) {
            var p = WeatherSnapshot.preset(c)
            if let pm = value("--pm25").flatMap(Double.init) { p.pm25 = pm }
            scene.weatherTarget = p.params
        }
        FileHandle.standardError.write("build: \(String(format: "%.2f", Date().timeIntervalSince(start)))s\n".data(using: .utf8)!)

        let view = SKView(frame: NSRect(origin: .zero, size: size))
        view.ignoresSiblingOrder = true
        let win = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: size.width, height: size.height),
                           styleMask: .borderless, backing: .buffered, defer: false)
        win.contentView = view
        win.orderFrontRegardless()
        window = win
        view.presentScene(scene)
        scene.settle()

        // `--frames N [--fps F]` writes a numbered sequence (out-000.png, out-001.png, ...) for making animations.
        let frames = Int(value("--frames") ?? "1") ?? 1
        let interval = 1 / (Double(value("--fps") ?? "15") ?? 15)
        let wait = Double(value("--wait") ?? "2.5") ?? 2.5
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            if frames <= 1 { self.capture(view, scene, to: self.output); exit(0) }
            let base = (self.output as NSString).deletingPathExtension
            var n = 0
            Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { t in
                self.capture(view, scene, to: String(format: "%@-%03d.png", base, n))
                n += 1
                if n == frames { t.invalidate(); exit(0) }
            }
        }
    }

    private func capture(_ view: SKView, _ scene: SKScene, to path: String) {
        guard let tex = view.texture(from: scene), case let cg = tex.cgImage() else {
            FileHandle.standardError.write("snapshot failed\n".data(using: .utf8)!)
            exit(1)
        }
        let rep = NSBitmapImageRep(cgImage: cg)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("wrote \(path) \(cg.width)x\(cg.height)")
    }
}
