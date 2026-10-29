import AppKit
import ServiceManagement
import SwiftUI

/// The Settings window. Every control writes straight to UserDefaults (via @AppStorage);
/// AppDelegate observes UserDefaults and applies changes live.
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(weather: WeatherService) {
        NSApp.activate(ignoringOtherApps: true)
        if let w = window { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
                         styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "Dhaka Sky Settings"
        w.contentViewController = NSHostingController(rootView: SettingsView(weather: weather))
        w.isReleasedWhenClosed = false
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
    }
}

struct SettingsView: View {
    let weather: WeatherService
    var body: some View {
        TabView {
            SceneTab().tabItem { Label("View", systemImage: "photo.on.rectangle") }
            ElementsTab().tabItem { Label("Elements", systemImage: "figure.walk") }
            WeatherTab(weather: weather).tabItem { Label("Weather & Time", systemImage: "cloud.sun") }
            SoundTab().tabItem { Label("Sound", systemImage: "speaker.wave.2") }
            DisplayTab().tabItem { Label("Display", systemImage: "display") }
        }
        .padding(16)
        .frame(width: 620, height: 560)
    }
}

// MARK: - View: illustrated views, your own photos, and the lakeside landmark

private struct SceneTab: View {
    @AppStorage("landmark") private var landmark = "rotate"
    @AppStorage("view") private var view = "lakeside"
    @State private var scenes = CustomImages.list(.scene)
    @State private var landmarks = CustomImages.list(.landmark)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GroupBox("View") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("", selection: $view) {
                            ForEach(ViewKind.allCases, id: \.rawValue) { v in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(v.title)
                                    Text(v.subtitle).font(.caption).foregroundStyle(.secondary)
                                }.tag(v.rawValue)
                            }
                            Text("Rotate daily through all views").tag("rotate")
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()

                        Divider().padding(.vertical, 4)
                        Text("Your photos").font(.headline)
                        if !scenes.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
                                ForEach(scenes) { item in
                                    Card(title: item.name, image: NSImage(contentsOf: item.url), symbol: nil, selected: view == item.settingValue,
                                         onRemove: { CustomImages.remove(item) }) { view = item.settingValue }
                                }
                            }
                        }
                        HStack {
                            Button("Add Photo…") { CustomImages.pickAndImport(kind: .scene) }
                            Spacer()
                            Button("Open Images Folder") { NSWorkspace.shared.open(Settings.customDir) }
                        }
                        Text("Every view follows Dhaka's live weather, sun, moon and time of day. On your photos, rain, fog, lightning and day/night lighting play on top. \"Rotate daily\" includes your photos.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }

                GroupBox("Landmark") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Featured landmark", selection: $landmark) {
                            Text("Rotate daily").tag("rotate")
                            Divider()
                            ForEach(Landmark.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                            if !landmarks.isEmpty {
                                Divider()
                                ForEach(landmarks) { Text("Your image: \($0.name)").tag($0.settingValue) }
                            }
                        }
                        if !landmarks.isEmpty {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                                ForEach(landmarks) { item in
                                    Card(title: item.name, image: NSImage(contentsOf: item.url), symbol: nil, selected: landmark == item.settingValue,
                                         fit: true, onRemove: { CustomImages.remove(item) }) { landmark = item.settingValue }
                                }
                            }
                        }
                        Button("Add Landmark Image…") { CustomImages.pickAndImport(kind: .landmark) }
                        Text("A PNG with a transparent background works best. For ordinary photos, the subject is cut out automatically.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
                }
                .disabled(view != "lakeside")
                .opacity(view != "lakeside" ? 0.5 : 1)
                if view != "lakeside" {
                    Text("The landmark applies to the Lakeside skyline view.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(4)
        }
        .onReceive(NotificationCenter.default.publisher(for: CustomImages.changed)) { _ in
            scenes = CustomImages.list(.scene); landmarks = CustomImages.list(.landmark)
        }
    }
}

private struct Card: View {
    let title: String
    let image: NSImage?
    let symbol: String?
    let selected: Bool
    var fit = false
    var onRemove: (() -> Void)?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let image {
                        Image(nsImage: image).resizable().aspectRatio(contentMode: fit ? .fit : .fill)
                    } else {
                        LinearGradient(colors: [Color(red: 0.29, green: 0.5, blue: 0.76), Color(red: 0.95, green: 0.7, blue: 0.55)],
                                       startPoint: .top, endPoint: .bottom)
                            .overlay(Image(systemName: symbol ?? "photo").font(.system(size: 28)).foregroundStyle(.white))
                    }
                }
                .frame(height: 74).frame(maxWidth: .infinity).clipped()
                .background(Color.black.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 3 : 1))
                if let onRemove {
                    Button(action: onRemove) { Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.white, .black.opacity(0.6)) }
                        .buttonStyle(.plain).padding(4).help("Remove this image")
                }
            }
            Text(title).font(.caption).lineLimit(1)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

// MARK: - Elements

private struct ElementsTab: View {
    @AppStorage("showTraffic") private var traffic = true
    @AppStorage("showPeople") private var people = true
    @AppStorage("showBoats") private var boats = true
    @AppStorage("showBirds") private var birds = true
    @AppStorage("showTrees") private var trees = true
    @AppStorage("showPlanes") private var planes = true

    var body: some View {
        Form {
            Section("Life in the scene") {
                Toggle("Rickshaws, CNGs, cars & buses", isOn: $traffic)
                Toggle("People walking (umbrellas when it rains)", isOn: $people)
                Toggle("Boats on the lake", isOn: $boats)
                Toggle("Birds", isOn: $birds)
                Toggle("Aeroplanes (aerial, panorama & rooftop views)", isOn: $planes)
                Toggle("Krishnachura & palm trees (blossoms April to June)", isOn: $trees)
            }
            Text("Traffic and crowds follow Dhaka's clock: busy by day, quiet late at night, thinner in heavy rain.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Weather & time

private struct WeatherTab: View {
    let weather: WeatherService
    @AppStorage("weatherOverride") private var weatherOverride = "live"
    @AppStorage("timeOverride") private var timeOverride = "live"
    @State private var summary = ""

    var body: some View {
        Form {
            Section("Live Dhaka weather") {
                Text(summary.isEmpty ? "Fetching…" : summary)
                Button("Refresh Now") {
                    weather.refresh()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { summary = describe() }
                }
            }
            Section("Weather") {
                Picker("Show", selection: $weatherOverride) {
                    Text("Live (follows real Dhaka weather)").tag("live")
                    Divider()
                    ForEach(Condition.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
            }
            Section("Time of day") {
                Picker("Show", selection: $timeOverride) {
                    ForEach(TimeOverride.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }
            }
            Text("Pick anything other than Live to preview a look, or to keep it fixed. Set both back to Live to follow the real sky.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .onAppear { summary = describe() }
    }

    private func describe() -> String {
        guard let w = weather.latest else { return weather.lastError.map { "Unavailable: \($0)" } ?? "" }
        var parts = [w.condition.title]
        if let t = w.temperature { parts.append("\(Int(t.rounded()))°C") }
        parts.append("clouds \(Int(w.cloudCover * 100))%")
        parts.append("wind \(Int(w.windKmh)) km/h")
        if let a = w.aqi { parts.append("AQI \(a)") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Sound

private struct SoundTab: View {
    @AppStorage("soundEnabled") private var enabled = false
    @AppStorage("soundVolume") private var volume = 0.5
    @AppStorage("soundRain") private var rain = true
    @AppStorage("soundThunder") private var thunder = true
    @AppStorage("soundStreet") private var street = false
    @AppStorage("soundBells") private var bells = true

    var body: some View {
        Form {
            Section {
                Toggle("Play ambient sound", isOn: $enabled)
                HStack {
                    Image(systemName: "speaker.fill")
                    Slider(value: $volume, in: 0.05...1)
                    Image(systemName: "speaker.wave.3.fill")
                }.disabled(!enabled)
            }
            Section("Sounds") {
                Toggle("Rain (only while it's raining)", isOn: $rain)
                Toggle("Thunder (follows each lightning flash)", isOn: $thunder)
                Toggle("Distant city hum", isOn: $street)
                Toggle("Rickshaw bells now and then", isOn: $bells)
            }
            .disabled(!enabled)
            Text("All sound is generated live. Nothing plays while the screen is asleep.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

// MARK: - Display & performance

private struct DisplayTab: View {
    @AppStorage("dim") private var dim = 0.0
    @AppStorage("fps") private var fps = 30
    @AppStorage("batterySaver") private var batterySaver = true
    @AppStorage("showGrain") private var grain = true
    @AppStorage("lockScreen") private var lockScreen = true
    @AppStorage("lockAnimation") private var lockAnimation = true
    @State private var saverSelected = SaverSync.isSelected
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Eye comfort") {
                HStack {
                    Text("Dim wallpaper")
                    Slider(value: $dim, in: 0...0.5)
                    Text("\(Int(dim * 100))%").monospacedDigit().frame(width: 40, alignment: .trailing)
                }
                Toggle("Paper grain texture", isOn: $grain)
            }
            Section("Lock screen") {
                Toggle("Show Dhaka Sky on the lock screen", isOn: $lockScreen)
                Text("Shows a still of the current view on the lock screen, with day, golden-hour and night versions. This works by setting your desktop picture (hidden behind the live wallpaper). Each still is saved once and reused, so it doesn't fill up your disk. Turning it off restores your original picture.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Animate the lock screen", isOn: $lockAnimation)
                HStack {
                    Text("macOS only allows animation over the lock screen through a screen saver. When you lock, Dhaka Sky starts its screen saver, which plays the same live view.")
                        .font(.caption).foregroundStyle(.secondary)
                    if saverSelected {
                        Button("Screen Saver Settings…") { SaverSync.openScreenSaverSettings() }
                    } else {
                        Button("Use Dhaka Sky as Screen Saver") { SaverSync.select(); saverSelected = SaverSync.isSelected }
                    }
                }
                Label(saverSelected ? "Dhaka Sky is your screen saver." : "Dhaka Sky is not your screen saver yet, so locking won't animate.",
                      systemImage: saverSelected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(saverSelected ? .green : .orange)
                    .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in saverSelected = SaverSync.isSelected }
            }
            Section("Performance") {
                Picker("Frame rate", selection: $fps) {
                    Text("20 fps").tag(20); Text("30 fps").tag(30); Text("60 fps").tag(60)
                }.pickerStyle(.segmented)
                Toggle("Battery saver (20 fps on battery)", isOn: $batterySaver)
                Text("Animation pauses automatically when the desktop is covered or the screen sleeps.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
            }
            Section {
                Button("Quit Dhaka Sky") { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
    }
}
