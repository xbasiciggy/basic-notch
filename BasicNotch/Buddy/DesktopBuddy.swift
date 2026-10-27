import AppKit
import SwiftUI

extension Notification.Name {
    static let resetDesktopBuddy = Notification.Name("BasicNotch.resetDesktopBuddy")
}

private final class BuddyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// One independent desktop panel, sharing the app's existing activity services.
@MainActor
final class DesktopBuddyController {
    private var panel: NSPanel?
    private var observers: [NSObjectProtocol] = []
    private let vm: NotchViewModel
    private var dragOrigin: NSPoint?
    private var dragMouseOrigin: NSPoint?

    init(vm: NotchViewModel) {
        self.vm = vm
        let center = NotificationCenter.default
        for name in [UserDefaults.didChangeNotification, NSApplication.didChangeScreenParametersNotification,
                     .resetDesktopBuddy] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if note.name == .resetDesktopBuddy { self.resetPosition() }
                    else if note.name == NSApplication.didChangeScreenParametersNotification { self.keepOnScreen() }
                    else { self.refresh() }
                }
            })
        }
        refresh()
    }

    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        panel?.close()
        panel = nil
    }

    private func refresh() {
        guard UserDefaults.standard.bool(forKey: "desktopBuddyEnabled") else {
            panel?.close()
            panel = nil
            dragOrigin = nil
            return
        }
        guard panel == nil else { return }
        let window = BuddyPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 190),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = NotchHostingView(rootView: DesktopBuddyView(exports: vm.exports, cards: vm.cards,
            drag: { [weak self] translation, ended in self?.drag(translation, ended: ended) },
            settings: { [weak self] in
                UserDefaults.standard.set("buddy", forKey: "settingsTab")
                self?.vm.openSettings()
            }))
        panel = window
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "desktopBuddyX") != nil {
            let x = defaults.double(forKey: "desktopBuddyX"), y = defaults.double(forKey: "desktopBuddyY")
            if x.isFinite && y.isFinite { window.setFrameOrigin(NSPoint(x: x, y: y)) }
            else { resetPosition() }
        } else { resetPosition() }
        keepOnScreen()
        window.orderFrontRegardless()
    }

    private func drag(_ translation: CGSize, ended: Bool) {
        guard let panel else { return }
        if dragOrigin == nil {
            dragOrigin = panel.frame.origin
            dragMouseOrigin = NSEvent.mouseLocation
        }
        guard let origin = dragOrigin, let mouseOrigin = dragMouseOrigin else { return }
        let mouse = NSEvent.mouseLocation
        panel.setFrameOrigin(NSPoint(x: origin.x + mouse.x - mouseOrigin.x, y: origin.y + mouse.y - mouseOrigin.y))
        if ended { dragOrigin = nil; dragMouseOrigin = nil; keepOnScreen() }
    }

    private func keepOnScreen() {
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
    var drag: (CGSize, Bool) -> Void
    var settings: () -> Void
    @AppStorage("desktopBuddyPaused") private var paused = false
    @AppStorage("desktopBuddyAnimation") private var animation = "auto"
    @AppStorage("desktopBuddyScale") private var scale = 2.0
    @AppStorage("desktopBuddyActivities") private var activities = true
    @AppStorage("liveLightroomExports") private var liveExports = true
    @AppStorage("liveCardIngest") private var liveCards = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var busy: Bool {
        activities && ((liveExports && !exports.active.isEmpty) || (liveCards && cards.progress != nil))
    }

    var body: some View {
        VStack(spacing: 6) {
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
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused || reduceMotion)) { context in
                if let entry = PokeBrawlSprites.roster.first(where: { $0.id == "0700" }),
                   let sprites = PokeBrawlSprites.sprites(for: entry, shiny: false) {
                    let anim = animation == "walk" || (animation == "auto" && busy) ? sprites.walk : (sprites.idle ?? sprites.walk)
                    let multiplier = min(max(scale, 1), min(3, 100 / anim.size.height))
                    Image(decorative: anim.frame(at: paused || reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate,
                                                 facingRight: false), scale: 1)
                        .interpolation(.none).resizable()
                        .frame(width: anim.size.width * multiplier, height: anim.size.height * multiplier)
                } else {
                    Label("Buddy artwork unavailable", systemImage: "pawprint").font(.caption)
                }
            }
            .frame(width: 240, height: 104)
            .contentShape(Rectangle())
            .gesture(DragGesture(coordinateSpace: .global)
                .onChanged { drag($0.translation, false) }.onEnded { drag($0.translation, true) })
            .accessibilityLabel("Sylveon desktop buddy")
            .accessibilityHint("Drag to move. Open the context menu for controls.")
        }
        .padding(.horizontal, 10)
        .frame(width: 260, height: 190)
        .contextMenu {
            Button(paused ? "Resume animation" : "Pause animation") { paused.toggle() }
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
    @AppStorage("desktopBuddyEnabled") private var enabled = false
    @AppStorage("desktopBuddyPaused") private var paused = false
    @AppStorage("desktopBuddyAnimation") private var animation = "auto"
    @AppStorage("desktopBuddyScale") private var scale = 2.0
    @AppStorage("desktopBuddyActivities") private var activities = true

    var body: some View {
        Form {
            Section("Desktop buddy") {
                Toggle("Show Sylveon on the desktop", isOn: $enabled)
                Text("Drag your buddy anywhere on a display. Right-click for quick controls. Its position is saved between launches.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Pause animation", isOn: $paused)
                Picker("Animation", selection: $animation) {
                    Text("React to activity").tag("auto")
                    Text("Idle").tag("idle")
                    Text("Walk in place").tag("walk")
                }
                Slider(value: $scale, in: 1...3, step: 0.5) { Text("Size") }
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
                Text("Sylveon by baronessfaron · PMD SpriteCollab · CC BY-NC 4.0. Noncommercial use with attribution. Original sheets are unchanged; frames are cropped for display. Pokémon rights remain with their owners; no endorsement is implied.")
                    .font(.caption)
                Link("Source artwork", destination: URL(string: "https://github.com/PMDCollab/SpriteCollab/tree/f663e2331a5f83504d1e7a01573dc53a6708f4c7/sprite/0700")!)
                Link("License terms", destination: URL(string: "https://creativecommons.org/licenses/by-nc/4.0/")!)
                Button("Full bundled sprite credits") {
                    if let url = PokeBrawlSprites.bundleURL?.appendingPathComponent("CREDITS.md") { NSWorkspace.shared.open(url) }
                }
            }
        }.formStyle(.grouped)
    }
}
