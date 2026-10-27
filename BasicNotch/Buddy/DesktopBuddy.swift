import AppKit
import SwiftUI

extension Notification.Name {
    static let openDesktopBuddyCare = Notification.Name("BasicNotch.openDesktopBuddyCare")
    static let resetDesktopBuddy = Notification.Name("BasicNotch.resetDesktopBuddy")
}

private final class BuddyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class BuddyMotionState: ObservableObject {
    @Published var zoom = 1.0
    @Published var walking = false
    @Published var direction = 0
    @Published var pickedUp = false
    @Published var playfulUntil = Date.distantPast
}

/// One independent desktop panel, sharing the app's existing activity services.
@MainActor
final class DesktopBuddyController {
    private var panel: NSPanel?
    private var observers: [NSObjectProtocol] = []
    private let vm: NotchViewModel
    private var dragOrigin: NSPoint?
    private var dragMouseOrigin: NSPoint?
    private let motion = BuddyMotionState()
    private let care = BuddyCareStore()
    private var nextComment = Date().addingTimeInterval(60)
    private var roamTimer: Timer?
    private var destination: CGPoint?
    private var lastTick = Date()
    private var restUntil = Date()


    init(vm: NotchViewModel) {
        self.vm = vm
        UserDefaults.standard.register(defaults: ["desktopBuddyRoaming": true, "desktopBuddySpeed": 45.0])
        let center = NotificationCenter.default
        for name in [UserDefaults.didChangeNotification, NSApplication.didChangeScreenParametersNotification,
                     .resetDesktopBuddy, .openDesktopBuddyCare] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if note.name == .openDesktopBuddyCare {
                        UserDefaults.standard.set(true, forKey: "desktopBuddyEnabled")
                        self.refresh()
                        self.panel?.makeKeyAndOrderFront(nil)
                        self.care.menuOpen = true
                    }
                    else if note.name == .resetDesktopBuddy { self.resetPosition() }
                    else if note.name == NSApplication.didChangeScreenParametersNotification { self.keepOnScreen() }
                    else { self.refresh() }
                }
            })
        }
        refresh()
    }

    func stop() {
        keepOnScreen()
        roamTimer?.invalidate()
        roamTimer = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        panel?.close()
        panel = nil
    }

    private func refresh() {
        let id = UserDefaults.standard.string(forKey: "desktopBuddySpecies") ?? "0700"
        care.select(DesktopBuddyArtwork.entry(for: id)?.id ?? "0700")
        guard UserDefaults.standard.bool(forKey: "desktopBuddyEnabled") else {
            let previous = panel
            panel = nil
            if let previous {
                UserDefaults.standard.set(previous.frame.minX, forKey: "desktopBuddyX")
                UserDefaults.standard.set(previous.frame.minY, forKey: "desktopBuddyY")
                previous.close()
            }
            roamTimer?.invalidate()
            roamTimer = nil
            motion.walking = false
            care.menuOpen = false
            panel?.close()
            panel = nil
            dragOrigin = nil
            motion.pickedUp = false
            return
        }
        if panel != nil { updateSize(); return }
        let window = BuddyPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 310),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "BasicNotch Desktop Buddy"
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.hidesOnDeactivate = false
        window.becomesKeyOnlyIfNeeded = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = NotchHostingView(rootView: DesktopBuddyView(exports: vm.exports, cards: vm.cards, motion: motion, care: care,
            weatherComment: { [weak self] in self?.speakWeather() },
            drag: { [weak self] translation, ended in self?.drag(translation, ended: ended) },
            settings: { [weak self] in
                UserDefaults.standard.set("buddy", forKey: "settingsTab")
                self?.vm.openSettings()
            }))
        panel = window
        updateSize()
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "desktopBuddyX") != nil {
            let x = defaults.double(forKey: "desktopBuddyX"), y = defaults.double(forKey: "desktopBuddyY")
            if x.isFinite && y.isFinite { window.setFrameOrigin(NSPoint(x: x, y: y)) }
            else { resetPosition() }
        } else { resetPosition() }
        keepOnScreen()
        window.orderFrontRegardless()
        lastTick = Date()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.roam() }
        }
        timer.tolerance = 0.008
        RunLoop.main.add(timer, forMode: .common)
        roamTimer = timer
    }

    private func roam() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastTick)
        lastTick = now
        let defaults = UserDefaults.standard
        care.tick(now: now)
        if !defaults.bool(forKey: "desktopBuddyComments") && defaults.object(forKey: "desktopBuddyComments") != nil {
            care.quiet()
        } else if now >= nextComment && !care.blocksMovement && !motion.pickedUp && !defaults.bool(forKey: "desktopBuddyPaused") {
            nextComment = now.addingTimeInterval(Double.random(in: 90...150))
            if Bool.random() { speakWeather() }
            else { care.say(["One step at a time!", "I'm here to keep you company.", "A little stretch sounds nice.", "We make a pretty good team!"].randomElement()!) }
        }
        guard !care.blocksMovement, let panel, defaults.bool(forKey: "desktopBuddyRoaming"),
              !defaults.bool(forKey: "desktopBuddyPaused"),
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              dragOrigin == nil, !panel.frame.contains(NSEvent.mouseLocation),
              NSEvent.pressedMouseButtons == 0, now >= restUntil else {
            motion.walking = false
            return
        }
        guard let screen = panel.screen ?? NSScreen.main else { return }
        if destination == nil {
            let bounds = screen.visibleFrame
            destination = CGPoint(x: CGFloat.random(in: bounds.minX...max(bounds.minX, bounds.maxX - panel.frame.width)),
                                  y: CGFloat.random(in: bounds.minY...max(bounds.minY, bounds.maxY - panel.frame.height)))
        }
        guard let target = destination else { return }
        let origin = panel.frame.origin
        let next = BuddyMotion.step(from: origin, to: target,
            speed: min(120, max(15, defaults.double(forKey: "desktopBuddySpeed"))), elapsed: elapsed)
        motion.direction = BuddyMotion.direction(dx: target.x - origin.x, dy: target.y - origin.y)
        motion.walking = next != origin
        panel.setFrameOrigin(next)
        if hypot(next.x - target.x, next.y - target.y) < 1 {
            destination = nil
            restUntil = now.addingTimeInterval(Double.random(in: 2...4))
            if Bool.random() { motion.playfulUntil = now.addingTimeInterval(1.5) }
            motion.walking = false
            keepOnScreen()
        }
    }

    private func speakWeather() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "desktopBuddyComments") == nil || defaults.bool(forKey: "desktopBuddyComments") else { return }
        if !vm.weather.failed, let weather = vm.weather.now {
            let unit = defaults.bool(forKey: "useFahrenheit") ? "°F" : "°C"
            care.say("\(vm.weather.place): \(Int(weather.temperature.rounded()))\(unit), \(WeatherCode.description(weather.code).lowercased()).")
        } else { care.say("No weather report yet. I'll keep you company meanwhile!") }
    }

    private func updateSize() {
        guard let panel else { return }
        let requested = max(1, min(3, UserDefaults.standard.object(forKey: "desktopBuddyMagnification") as? Double ?? 1))
        let layout = BuddyLayout(size: UserDefaults.standard.object(forKey: "desktopBuddyScale") as? Double ?? 2)
        let screen = panel.screen ?? NSScreen.main
        let maxZoom = screen.map { min($0.visibleFrame.width / layout.width, $0.visibleFrame.height / layout.height) } ?? requested
        motion.zoom = min(requested, maxZoom)
        let size = NSSize(width: layout.width * motion.zoom, height: layout.height * motion.zoom)
        if panel.frame.size != size {
            panel.setContentSize(size)
            panel.setFrame(BuddyPlacement.fit(panel.frame, screens: NSScreen.screens.map(\.visibleFrame)), display: true)
        }
    }

    private func drag(_ translation: CGSize, ended: Bool) {
        guard let panel else { return }
        if dragOrigin == nil {
            destination = nil
            motion.walking = false
            motion.pickedUp = true
            motion.direction = 0
            dragOrigin = panel.frame.origin
            dragMouseOrigin = NSEvent.mouseLocation
        }
        guard let origin = dragOrigin, let mouseOrigin = dragMouseOrigin else { return }
        let mouse = NSEvent.mouseLocation
        panel.setFrameOrigin(NSPoint(x: origin.x + mouse.x - mouseOrigin.x, y: origin.y + mouse.y - mouseOrigin.y))
        if ended { motion.pickedUp = false; dragOrigin = nil; dragMouseOrigin = nil; restUntil = Date().addingTimeInterval(2); keepOnScreen() }
    }

    private func keepOnScreen() {
        updateSize()
        destination = nil
        guard let panel else { return }
        panel.setFrame(BuddyPlacement.fit(panel.frame, screens: NSScreen.screens.map(\.visibleFrame)), display: true)
        UserDefaults.standard.set(panel.frame.minX, forKey: "desktopBuddyX")
        UserDefaults.standard.set(panel.frame.minY, forKey: "desktopBuddyY")
    }

    private func resetPosition() {
        guard let panel, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - panel.frame.width - 24,
                                     y: screen.visibleFrame.minY + 24))
        keepOnScreen()
    }
}

private struct DesktopBuddyView: View {
    @ObservedObject var exports: LightroomExportService
    @ObservedObject var cards: CardIngestService
    @ObservedObject var motion: BuddyMotionState
    @ObservedObject var care: BuddyCareStore
    var weatherComment: () -> Void
    var drag: (CGSize, Bool) -> Void
    var settings: () -> Void
    @AppStorage("desktopBuddyComments") private var comments = true
    @AppStorage("desktopBuddySpecies") private var species = "0700"
    @AppStorage("desktopBuddyShiny") private var shiny = false
    @AppStorage("desktopBuddyRoaming") private var roaming = true
    @AppStorage("desktopBuddyPaused") private var paused = false
    @AppStorage("desktopBuddyAnimation") private var animation = "auto"
    @AppStorage("desktopBuddyMagnification") private var magnification = 1.0
    @AppStorage("desktopBuddyScale") private var scale = 2.0
    @AppStorage("desktopBuddyActivities") private var activities = true
    @AppStorage("liveLightroomExports") private var liveExports = true
    @AppStorage("liveCardIngest") private var liveCards = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var layout: BuddyLayout { BuddyLayout(size: scale) }

    private var busy: Bool {
        activities && ((liveExports && !exports.active.isEmpty) || (liveCards && cards.progress != nil))
    }

    var body: some View {
        VStack(spacing: 6) {
            if comments, let speech = care.speech {
                Text(speech).font(.caption).multilineTextAlignment(.center)
                    .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .frame(height: 48)
            } else { Color.clear.frame(height: 48) }
            VStack(spacing: 3) {
                if activities && liveExports, !exports.active.isEmpty {
                    Text("Lightroom · \(exports.countLabel)").font(.caption.bold())
                    ProgressView(value: exports.progress).tint(.mint)
                }
                if activities && liveCards {
                    if let progress = cards.progress {
                        Text("Card import · \(Int(progress * 100))%").font(.caption.bold())
                        ProgressView(value: progress).tint(.cyan)
                    } else if let card = cards.card {
                        Text(card.isScanning ? "Scanning camera card…" : "\(card.name) · \(card.newFiles.count) new files")
                            .font(.caption).lineLimit(1)
                    }
                    if cards.error != nil { Text("Card import needs attention — open Notch").font(.caption2).foregroundStyle(.orange) }
                }
            }
            .padding(8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .opacity(hasActivity ? 1 : 0)
            .frame(height: 64)
            Button { care.menuOpen = true } label: {
                VStack(spacing: 3) {
                    HStack {
                        Text(care.profile.nickname.isEmpty ? (DesktopBuddyArtwork.entry(for: species)?.name ?? "Buddy") : care.profile.nickname)
                            .lineLimit(1)
                        Text("Lv. \(care.profile.level)").foregroundStyle(.secondary)
                    }.font(.caption.bold())
                    ProgressView(value: care.profile.levelProgress).tint(.mint).frame(width: 130)
                }.padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
            }.buttonStyle(.plain).help("Open food, play and sleep menu")
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused || reduceMotion)) { context in
                if let entry = DesktopBuddyArtwork.entry(for: species) {
                    let animations = DesktopBuddyArtwork.animations(for: entry, shiny: shiny)
                    let now = context.date
                    let chosen = care.sleeping ? "sleep" : motion.pickedUp ? "hurt" :
                        care.action?.animation ?? (motion.walking ? "walk" :
                            animation != "auto" ? animation : busy ? "walk" : now < motion.playfulUntil ? "attack" : "idle")
                    if let anim = animations[chosen] ?? animations["idle"] ?? animations["walk"] {
                        let maxHeight = animations.values.map(\.size.height).max() ?? 100
                        let maxWidth = animations.values.map(\.size.width).max() ?? 220
                        let multiplier = min(max(scale, 1), min(3, min(100 / maxHeight, 220 / maxWidth))) * layout.expansion
                        let time = care.action != nil ? now.timeIntervalSince(care.actionStarted) : now.timeIntervalSinceReferenceDate
                        Image(decorative: anim.frame(at: paused || reduceMotion ? 0 : time,
                                                     direction: motion.pickedUp || care.action != nil ? 0 : motion.direction), scale: 1)
                            .interpolation(.none).resizable()
                            .frame(width: anim.size.width * multiplier, height: anim.size.height * multiplier)
                            .overlay(alignment: .topTrailing) {
                                if care.sleeping { Text("Zzz").font(.caption.bold()).foregroundStyle(.cyan).offset(x: 20, y: -10) }
                                if let action = care.action {
                                    let t = paused || reduceMotion ? 0 : max(0, now.timeIntervalSince(care.actionStarted))
                                    Text(action.icon).font(.system(size: 22))
                                        .offset(x: action == .tennis || action == .beach ? CGFloat(sin(t * 4) * 45) : 12,
                                                y: action == .tennis || action == .beach ? CGFloat(-abs(sin(t * 5)) * 30) : -12)
                                }
                            }
                    } else {
                        Label("Buddy artwork unavailable", systemImage: "pawprint").font(.caption)
                    }
                }
            }
            .frame(width: layout.spriteWidth, height: layout.spriteHeight)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { if !care.menuOpen { drag($0.translation, false) } }
                .onEnded { drag($0.translation, true) })
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.55, maximumDistance: 8).onEnded { _ in
                drag(.zero, true)
                care.menuOpen = true
            })
            .popover(isPresented: $care.menuOpen, arrowEdge: .bottom) {
                BuddyCareMenu(care: care, speciesName: DesktopBuddyArtwork.entry(for: species)?.name ?? "Buddy",
                    supportsShock: species == "0025", onWeather: weatherComment)
            }
            .accessibilityLabel("\(DesktopBuddyArtwork.entry(for: species)?.name ?? "Pokémon") desktop buddy")
            .accessibilityHint("Drag to move, hold to open care, or click the name tag.")
        }
        .padding(.horizontal, 10)
        .frame(width: layout.width, height: layout.height)
        .scaleEffect(motion.zoom)
        .frame(width: layout.width * motion.zoom, height: layout.height * motion.zoom)
        .contextMenu {
            Button("Food, play & sleep…") { care.menuOpen = true }
            Button(paused ? "Resume buddy" : "Pause buddy") { paused.toggle() }
            Button(roaming ? "Stop roaming" : "Roam freely") { roaming.toggle() }
            Button("Play animation") { motion.playfulUntil = Date().addingTimeInterval(2) }
            Button("Choose Pokémon…", action: settings)
            Button("Buddy settings…", action: settings)
            Button("Reset position") { NotificationCenter.default.post(name: .resetDesktopBuddy, object: nil) }
            Divider()
            Button("Hide buddy") { UserDefaults.standard.set(false, forKey: "desktopBuddyEnabled") }
        }
    }

    private var hasActivity: Bool {
        activities && ((liveExports && !exports.active.isEmpty) || (liveCards && (cards.card != nil || cards.progress != nil || cards.error != nil)))
    }
}

struct DesktopBuddySettings: View {
    @State private var search = ""
    @AppStorage("desktopBuddySpeed") private var speed = 45.0
    private var choices: [RosterEntry] {
        DesktopBuddyArtwork.roster.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.id == species }
    }
    @AppStorage("desktopBuddyEnabled") private var enabled = false
    @AppStorage("desktopBuddyComments") private var comments = true
    @AppStorage("desktopBuddySpecies") private var species = "0700"
    @AppStorage("desktopBuddyShiny") private var shiny = false
    @AppStorage("desktopBuddyRoaming") private var roaming = true
    @AppStorage("desktopBuddyPaused") private var paused = false
    @AppStorage("desktopBuddyAnimation") private var animation = "auto"
    @AppStorage("desktopBuddyMagnification") private var magnification = 1.0
    @AppStorage("desktopBuddyScale") private var scale = 2.0
    @AppStorage("desktopBuddyActivities") private var activities = true

    var body: some View {
        Form {
            Section("Desktop buddy") {
                Toggle("Show buddy on the desktop", isOn: $enabled)
                Button("Open food, play & sleep menu") {
                    NotificationCenter.default.post(name: .openDesktopBuddyCare, object: nil)
                }
                TextField("Search Pokémon", text: $search)
                Picker("Pokémon", selection: $species) {
                    ForEach(choices, id: \.id) { entry in
                        Text(entry.name).tag(entry.id)
                    }
                }
                Toggle("Shiny", isOn: $shiny).disabled(!DesktopBuddyArtwork.hasShiny(species))
                Toggle("Roam freely around the screen", isOn: $roaming)
                Slider(value: $speed, in: 15...120, step: 5) { Text("Walking speed") }
                    .disabled(!roaming)
                Text("Roaming pauses when you point at the buddy, drag it, or enable Reduce Motion. Drag it to another display to explore there.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Drag your buddy anywhere on a display. Right-click for quick controls. Its position is saved between launches.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Pause buddy", isOn: $paused)
                Picker("Animation", selection: $animation) {
                    Text("React to activity").tag("auto")
                    Text("Idle").tag("idle")
                    Text("Walk in place").tag("walk")
                    Text("Play / attack").tag("attack")
                    Text("Hurt / surprised").tag("hurt")
                    if species == "0025" { Text("Shock ⚡️").tag("shock") }
                    if let entry = DesktopBuddyArtwork.entry(for: species),
                       DesktopBuddyArtwork.animations(for: entry, shiny: shiny)["faint"] != nil {
                        Text("Lie down / faint").tag("faint")
                    }
                }
                Text("Walks in eight directions. Picking up uses the front-facing hurt pose; automatic mode sometimes plays an attack animation while resting. Missing poses fall back to idle.")
                    .font(.caption).foregroundStyle(.secondary)
                Slider(value: $scale, in: 1...BuddyLayout.maximumSize, step: 0.5) { Text("Size") }
                Slider(value: $magnification, in: 1...3, step: 0.25) { Text("Magnification · \(Int(magnification * 100))%") }
                Toggle("Occasional comments and weather chat", isOn: $comments)
                Toggle("Show live activity above buddy", isOn: $activities)
                Button("Reset position to main display") {
                    NotificationCenter.default.post(name: .resetDesktopBuddy, object: nil)
                }.disabled(!enabled)
            }
            Section("Connected activities") {
                Text("Lightroom Classic exports use the existing BasicNotch export plug-in. Camera cards use the existing DCIM detection and BasicNotch import progress. General → Live activities controls also apply here.")
                Text("Tethered camera capture and transfers performed by other apps are planned; they are not monitored in this build.")
                    .foregroundStyle(.secondary)
            }.font(.caption)
            Section("Artwork & credits") {
                Text("Artwork comes from the bundled SpriteCollab collection. Custom artwork is noncommercial with attribution (CC BY-NC 4.0); original game artwork retains its underlying rights. Sylveon is by baronessfaron. See the bundled credits for every artist. No endorsement is implied.")
                    .font(.caption)
                Link("Source artwork", destination: URL(string: "https://github.com/PMDCollab/SpriteCollab/tree/f663e2331a5f83504d1e7a01573dc53a6708f4c7/sprite/0700")!)
                Link("License terms", destination: URL(string: "https://creativecommons.org/licenses/by-nc/4.0/")!)
                Button("Full bundled sprite credits") {
                    if let url = DesktopBuddyArtwork.bundleURL?.appendingPathComponent("CREDITS.md") { NSWorkspace.shared.open(url) }
                }
            }
        }.formStyle(.grouped)
    }
}
