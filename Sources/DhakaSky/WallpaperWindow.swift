import AppKit
import SpriteKit

/// A borderless window pinned to the desktop layer (below Finder's icons) on one screen.
final class WallpaperWindow: NSWindow {
    let skView: SKView
    let cityScene: CityScene
    let targetScreen: NSScreen

    init(screen: NSScreen) {
        targetScreen = screen
        skView = SKView(frame: NSRect(origin: .zero, size: screen.frame.size))
        cityScene = CityScene(size: screen.frame.size, scale: screen.backingScaleFactor)
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        ignoresMouseEvents = true
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        isReleasedWhenClosed = false

        skView.ignoresSiblingOrder = true
        skView.shouldCullNonVisibleNodes = true
        skView.allowsTransparency = false
        skView.preferredFramesPerSecond = Settings.shared.fps
        skView.presentScene(cityScene)
        contentView = skView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
