import AppKit
import SwiftUI

let app = NSApplication.shared
let args = CommandLine.arguments

if let i = args.firstIndex(of: "--settings-preview"), i + 1 < args.count {
    // Renders the Settings window offscreen to a PNG (for checking the layout).
    app.setActivationPolicy(.prohibited)
    let view = NSHostingView(rootView: SettingsView(weather: WeatherService()))
    view.frame = NSRect(x: 0, y: 0, width: 620, height: 560)
    let win = NSWindow(contentRect: NSRect(x: -30000, y: -30000, width: 620, height: 560), styleMask: .borderless, backing: .buffered, defer: false)
    win.contentView = view
    win.orderFrontRegardless()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
        exit(0)
    }
    app.run()
} else if args.contains("--select-saver") {
    // Make Dhaka Sky the screen saver (the Settings window button does the same).
    print(SaverSync.select() ? "selected" : "failed")
    exit(0)
} else if args.contains("--sound-test") {
    print(SoundScape.selfTest())
    exit(0)
} else if let i = args.firstIndex(of: "--import"), i + 2 < args.count, let kind = CustomImages.Kind(rawValue: args[i + 1]) {
    // `DhakaSky --import landmark|scene <image>`, same import path as the Settings window, without selecting it.
    do {
        let file = try CustomImages.importImage(from: URL(fileURLWithPath: args[i + 2]), kind: kind, select: false)
        print(Settings.customDir.appendingPathComponent(file).path)
        exit(0)
    } catch { FileHandle.standardError.write("\(error.localizedDescription)\n".data(using: .utf8)!); exit(1) }
} else if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
    // Render one frame to a PNG and exit, used for testing the art without touching the desktop.
    let runner = SnapshotRunner(output: args[i + 1], args: args)
    app.delegate = runner
    app.setActivationPolicy(.prohibited)
    app.run()
} else {
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
