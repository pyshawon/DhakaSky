import AppKit
import UniformTypeIdentifiers

/// Importing, listing and removing the user's own landmark and scene images.
enum CustomImages {
    enum Kind: String { case landmark, scene }

    struct Item: Identifiable, Hashable {
        let file: String
        var id: String { file }
        var name: String {
            let base = (file as NSString).deletingPathExtension
            return base.split(separator: "-", maxSplits: 1).last.map(String.init)?.replacingOccurrences(of: "_", with: " ") ?? base
        }
        var url: URL { Settings.customDir.appendingPathComponent(file) }
        var settingValue: String { "custom:\(file)" }
    }

    static func list(_ kind: Kind) -> [Item] { Settings.customFiles(prefix: kind.rawValue + "-").map(Item.init) }

    /// Copies an image into the custom folder (cutting the subject out of opaque landmark photos) and selects it.
    @discardableResult
    static func importImage(from url: URL, kind: Kind, select: Bool = true) throws -> String {
        guard let img = NSImage(contentsOf: url), var cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: "DhakaSky", code: 1, userInfo: [NSLocalizedDescriptionKey: "That file isn't an image macOS can read."])
        }
        if kind == .landmark {
            let opaque = [.none, .noneSkipLast, .noneSkipFirst].contains(cg.alphaInfo)
            if opaque, let cut = ArtLandmarks.cutOut(cg) { cg = cut }
        }
        // Keep files a sensible size: scenes up to 4K wide, landmarks up to 2000 px tall.
        cg = downscale(cg, maxW: kind == .scene ? 3840 : 4000, maxH: kind == .scene ? 2400 : 2000)
        let name = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "/", with: "_")
        let file = "\(kind.rawValue)-\(name).png"
        guard let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            throw NSError(domain: "DhakaSky", code: 2, userInfo: [NSLocalizedDescriptionKey: "Couldn't encode the image."])
        }
        try data.write(to: Settings.customDir.appendingPathComponent(file))
        if select {
            if kind == .landmark { Settings.shared.landmark = "custom:\(file)" } else { Settings.shared.view = "custom:\(file)" }
        }
        NotificationCenter.default.post(name: CustomImages.changed, object: nil)
        return file
    }

    static func remove(_ item: Item) {
        try? FileManager.default.removeItem(at: item.url)
        let s = Settings.shared
        if s.landmark == item.settingValue { s.landmark = "rotate" }
        if s.view == item.settingValue { s.view = "lakeside" }
        NotificationCenter.default.post(name: CustomImages.changed, object: nil)
    }

    static let changed = Notification.Name("DhakaSkyCustomImagesChanged")

    static func pickAndImport(kind: Kind) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.message = kind == .landmark
            ? "Choose a landmark image. A PNG with a transparent background works best; photos get their subject cut out automatically."
            : "Choose a photo to use as a view. Weather and time-of-day lighting are layered on top."
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try importImage(from: url, kind: kind) } catch {
            let a = NSAlert(); a.messageText = "Couldn't add image"; a.informativeText = error.localizedDescription; a.runModal()
        }
    }

    private static func downscale(_ cg: CGImage, maxW: Int, maxH: Int) -> CGImage {
        let k = min(1, min(Double(maxW) / Double(cg.width), Double(maxH) / Double(cg.height)))
        guard k < 1 else { return cg }
        let w = Int(Double(cg.width) * k), h = Int(Double(cg.height) * k)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: Painter.space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? cg
    }
}
