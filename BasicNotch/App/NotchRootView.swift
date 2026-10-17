import SwiftUI

struct NotchRootView: View {
    @ObservedObject var vm: NotchViewModel
    @AppStorage("wingWidth") private var wingWidth = 110.0
    @AppStorage("showPokemon") private var showPokemon = true
    @AppStorage("musicLiveActivity") private var musicLiveActivity = true
    @AppStorage("albumGlow") private var albumGlow = true

    private var liveMusic: Bool { musicLiveActivity && vm.music.isPlaying }
    /// Something is using the closed notch's wings (alert, timer, charging, music).
    private var liveActivity: Bool {
        vm.banner != nil || vm.focus.isActive || vm.battery.flash || liveMusic || vm.liveActivity != nil
    }
    private var closedSize: CGSize {
        vm.closedSize(wingWidth: wingWidth, showPokemon: showPokemon, musicLiveActivity: musicLiveActivity)
    }
    private var size: CGSize { vm.isOpen ? vm.expandedSize : closedSize }
    private var topRadius: CGFloat { vm.isOpen ? 14 : 6 }
    private var bottomRadius: CGFloat { vm.isOpen ? 30 : 12 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchBackground(isOpen: vm.isOpen,
                                shape: NotchShape(topRadius: topRadius, bottomRadius: bottomRadius),
                                cursor: vm.cursor,
                                albumColors: albumGlow && vm.tab == .music ? vm.music.artworkColors : [],
                                albumGlowAnimated: vm.music.isPlaying)

                VStack(spacing: 0) {
                    topRow
                        .frame(height: vm.notchSize.height)
                    if vm.isOpen {
                        ExpandedContent(vm: vm)
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    }
                }
                .padding(.horizontal, topRadius)
            }
            .frame(width: size.width, height: size.height)
            .shadow(color: .black.opacity(vm.isOpen ? 0.5 : 0), radius: 10, y: 4)
            .animation(.spring(response: 0.42, dampingFraction: 0.8), value: vm.isOpen)
            .animation(.spring(response: 0.42, dampingFraction: 0.8), value: closedSize.width)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
    }

    /// The strip at the height of the menu bar: Pokémon walk here, plus boring.notch-style live activities.
    private var topRow: some View {
        ZStack {
            if showPokemon {
                PokemonStage(party: vm.party,
                             width: size.width - topRadius * 2,
                             height: vm.notchSize.height,
                             edgeInset: (!vm.isOpen && liveActivity) ? 34 : 12)
                    .opacity(!vm.isOpen && vm.banner != nil ? 0 : 1)
            }
            if !vm.isOpen {
                if let banner = vm.banner {
                    BannerRow(banner: banner, notchWidth: vm.notchSize.width)
                        .transition(.opacity)
                } else {
                    HStack(spacing: 0) {
                        leftActivity
                        Spacer(minLength: 0)
                        rightActivity
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
    }

    @ViewBuilder
    private var leftActivity: some View {
        if let activity = vm.liveActivity {
            LiveActivityIcon(vm: vm, activity: activity)
                .transition(.scale.combined(with: .opacity))
        } else if vm.focus.isActive {
            ZStack {
                Circle().stroke(Color.white.opacity(0.2), lineWidth: 2.5)
                Circle().trim(from: 0, to: vm.focus.progress)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 16, height: 16)
            .transition(.scale.combined(with: .opacity))
        } else if liveMusic {
            AlbumArt(image: vm.music.artwork, cornerRadius: 5)
                .frame(width: 22, height: 22)
                .transition(.scale.combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var rightActivity: some View {
        if vm.battery.flash {
            BatteryBadge(level: vm.battery.level, charging: vm.battery.isCharging, compact: true)
                .transition(.scale.combined(with: .opacity))
        } else if let activity = vm.liveActivity {
            LiveActivityDetail(vm: vm, activity: activity)
                .transition(.scale.combined(with: .opacity))
        } else if vm.focus.isActive {
            Text(vm.focus.label)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(vm.focus.isRunning ? Color.orange : Color.secondary)
                .transition(.scale.combined(with: .opacity))
        } else if liveMusic {
            AudioVisualizer(active: vm.music.isPlaying, barCount: 4)
                .frame(width: 20, height: 14)
                .transition(.scale.combined(with: .opacity))
        }
    }
}

/// Left wing of a live activity: a progress ring or a symbol.
struct LiveActivityIcon: View {
    @ObservedObject var vm: NotchViewModel
    let activity: NotchViewModel.LiveActivity

    var body: some View {
        switch activity {
        case .cardImport:
            ProgressRing(fraction: vm.cards.progress ?? 0, color: .orange, symbol: "sdcard.fill")
        case .download:
            let item = vm.downloads.current
            ProgressRing(fraction: vm.downloads.overallFraction, color: .blue,
                         symbol: item?.isAirDrop == true ? "airplayaudio" : "arrow.down")
        case .recording:
            TimelineView(.animation(minimumInterval: 0.5)) { context in
                let on = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
                Circle().fill(Color.red).frame(width: 9, height: 9).opacity(on ? 1 : 0.35)
                    .frame(width: 18, height: 18)
            }
        case .card:
            Image(systemName: "sdcard.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(.orange)
                .frame(width: 18, height: 18)
        case .goldenHour:
            Image(systemName: "sun.horizon.fill").font(.system(size: 12)).symbolRenderingMode(.multicolor)
                .frame(width: 18, height: 18)
        }
    }
}

/// Right wing of a live activity: percent, a timer or a count.
struct LiveActivityDetail: View {
    @ObservedObject var vm: NotchViewModel
    let activity: NotchViewModel.LiveActivity

    var body: some View {
        Group {
            switch activity {
            case .cardImport:
                Text("\(vm.cards.copiedCount)/\(vm.cards.card?.newFiles.count ?? 0)").foregroundStyle(.orange)
            case .download:
                Text("\(Int((vm.downloads.overallFraction * 100).rounded()))%").foregroundStyle(.blue)
            case .recording:
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let s = Int(context.date.timeIntervalSince(vm.recording.startedAt ?? context.date))
                    Text(String(format: "%d:%02d", s / 60, s % 60)).foregroundStyle(.red)
                }
            case .card:
                Text("\(vm.cards.card?.newFiles.count ?? 0) new").foregroundStyle(.orange)
            case .goldenHour:
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    let minutes = max(0, Int(((vm.goldenHour.sunset ?? context.date).timeIntervalSince(context.date) / 60).rounded()))
                    Text("\(minutes)m").foregroundStyle(Color(red: 1, green: 0.62, blue: 0.3))
                }
            }
        }
        .font(.system(size: 12, weight: .semibold).monospacedDigit())
        .lineLimit(1)
    }
}

/// A small circular progress ring with a symbol in the middle.
struct ProgressRing: View {
    let fraction: Double
    let color: Color
    let symbol: String

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.2), lineWidth: 2.2)
            Circle().trim(from: 0, to: max(0.02, fraction))
                .stroke(color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.3), value: fraction)
            Image(systemName: symbol).font(.system(size: 7, weight: .bold)).foregroundStyle(color)
        }
        .frame(width: 18, height: 18)
    }
}

/// An alert in the closed notch: icon + title on the left wing, detail on the right wing.
struct BannerRow: View {
    let banner: NotchBanner
    let notchWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                if banner.image != nil {
                    AvatarImage(url: banner.image, name: banner.title, size: 18)
                } else if banner.iconIsEmoji {
                    Text(banner.icon).font(.system(size: 13))
                } else {
                    Image(systemName: banner.icon).font(.system(size: 12, weight: .bold)).foregroundStyle(banner.tint)
                }
                Text(banner.title).font(.system(size: 11, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: notchWidth)
            HStack(spacing: 5) {
                Text(banner.detail)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if banner.detailImage != nil {
                    GameIconImage(url: banner.detailImage, size: 18)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 10)
    }
}

/// The notch outline: flared top corners that blend into the screen edge, rounded bottom corners.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = topRadius
        let b = min(bottomRadius, max(rect.height - t, 0))
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t),
                       control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
                       control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
                       control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

struct ExpandedContent: View {
    @ObservedObject var vm: NotchViewModel
    @AppStorage("hiddenTabs") private var hiddenTabs = ""

    private var tabs: [NotchTab] { NotchTab.visible(hidden: hiddenTabs) }

    var body: some View {
        VStack(spacing: 10) {
            header
            HStack(spacing: 12) {
                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if vm.showMirror {
                    CameraMirror()
                        .frame(width: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 16)
        .overlay {
            if vm.isDropTargeted {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .padding(8)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $vm.isDropTargeted) { providers in
            vm.tab = .files
            return vm.files.add(providers)
        }
    }

    private var header: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                Button {
                    withAnimation(.snappy) { vm.tab = tab }
                } label: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 26)
                        .background(Capsule().fill(vm.tab == tab ? Color.white.opacity(0.18) : .clear))
                        .foregroundStyle(vm.tab == tab ? Color.white : Color.secondary)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }

            Spacer(minLength: 8)

            NextEventChip(calendar: vm.calendar)

            Spacer(minLength: 8)

            ClaudeUsageChip(usage: vm.claude)

            BatteryBadge(level: vm.battery.level, charging: vm.battery.isCharging, compact: false)
                .opacity(vm.battery.hasBattery ? 1 : 0)

            HeaderIconButton(icon: "web.camera", active: vm.showMirror, help: "Mirror") {
                withAnimation(.snappy) { vm.showMirror.toggle() }
            }
            HeaderIconButton(icon: vm.isPinned ? "pin.fill" : "pin", active: vm.isPinned, help: "Keep open") {
                vm.isPinned.toggle()
            }
            HeaderIconButton(icon: "gearshape.fill", active: false, help: "Settings") {
                vm.openSettings()
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        if tabs.isEmpty {
            StatusMessage(icon: "square.grid.2x2", text: "All tabs are turned off — turn some on in Settings")
        } else {
            selectedTab
                .onAppear(perform: fixSelection)
                .onChange(of: hiddenTabs) { _, _ in fixSelection() }
        }
    }

    /// If the selected tab was switched off, move to the first one that's still on.
    private func fixSelection() {
        if !tabs.contains(vm.tab), let first = tabs.first { vm.tab = first }
    }

    @ViewBuilder
    private var selectedTab: some View {
        switch vm.tab {
        case .music: MusicTab(music: vm.music, volume: vm.volume, lyrics: vm.lyrics)
        case .sports: SportsTab(sports: vm.sports)
        case .gaming: GamingTab(psn: vm.psn)
        case .crypto: CryptoTab(crypto: vm.crypto)
        case .weather: WeatherTab(weather: vm.weather)
        case .files: ShelfTab(tray: vm.files, clipboard: vm.clipboard, tumblr: vm.tumblr, portfolio: vm.portfolio,
                                       cards: vm.cards, openSettings: vm.openSettings)
        case .pokedex: PokedexTab()
        case .focus: FocusTab(focus: vm.focus)
        case .system: SystemTab(stats: vm.system, battery: vm.battery, airpods: vm.airpods)
        }
    }
}

// MARK: - Shared bits

struct HeaderIconButton: View {
    let icon: String
    let active: Bool
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(active ? 0.22 : hovering ? 0.12 : 0.06)))
                .foregroundStyle(active ? Color.white : Color.secondary)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.25 : 0.12)))
            .contentShape(Capsule())
    }
}

struct Chip: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(selected ? Color.white : Color.white.opacity(0.1)))
                .foregroundStyle(selected ? Color.black : Color.white)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct CardBackground: ViewModifier {
    var highlighted = false
    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(highlighted ? Color.yellow.opacity(0.8) : Color.white.opacity(0.06), lineWidth: 1))
    }
}

extension View {
    func card(highlighted: Bool = false) -> some View { modifier(CardBackground(highlighted: highlighted)) }
}

struct StatusMessage: View {
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 26)).foregroundStyle(.secondary)
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
