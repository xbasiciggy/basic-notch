import SwiftUI

struct MusicTab: View {
    @ObservedObject var music: NowPlayingService
    @ObservedObject var volume: SystemVolume
    @ObservedObject var lyrics: LyricsService
    @AppStorage("showLyrics") private var showLyrics = true

    private var lyricsVisible: Bool { showLyrics && (lyrics.state == .synced || lyrics.state == .plainOnly) }

    var body: some View {
        if music.title.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "music.note.list").font(.system(size: 30)).foregroundStyle(.secondary)
                Text("Nothing playing").font(.headline)
                HStack {
                    Button("Open Music") { music.launch(.music) }
                    Button("Open Spotify") { music.launch(.spotify) }
                }
                .buttonStyle(PillButtonStyle())
                VolumeSlider(volume: volume, music: music).frame(width: 180).padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 18) {
                AlbumArt(image: music.artwork, cornerRadius: 14)
                    .frame(width: 140, height: 140)
                    .shadow(color: .black.opacity(0.6), radius: 8, y: 4)
                    .onTapGesture { music.bringPlayerToFront() }
                    .scaleEffect(music.isPlaying ? 1 : 0.92)
                    .animation(.spring, value: music.isPlaying)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: music.player == .spotify ? "dot.radiowaves.left.and.right" : "music.note")
                        Text(music.player?.rawValue ?? "")
                        Spacer()
                        SmallControl(icon: "quote.bubble", help: showLyrics ? "Hide lyrics" : "Show lyrics",
                                     tint: showLyrics && lyrics.state == .synced ? .white : nil) {
                            withAnimation(.snappy) { showLyrics.toggle() }
                        }
                        .opacity(lyrics.state == .notFound || lyrics.state == .instrumental ? 0.35 : 1)
                        SmallControl(icon: "gobackward.15", help: "Back 15 seconds") { music.skip(by: -15) }
                        SmallControl(icon: "goforward.15", help: "Forward 15 seconds") { music.skip(by: 15) }
                        if music.player == .music {
                            SmallControl(icon: music.isFavorite ? "star.fill" : "star",
                                         help: music.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                                         tint: music.isFavorite ? .pink : nil) { music.toggleFavorite() }
                        } else if music.trackLink != nil {
                            CopyLinkControl { music.copyTrackLink() }
                        }
                        AudioVisualizer(active: music.isPlaying, barCount: 5)
                            .frame(width: 26, height: 16)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                    if lyricsVisible {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(music.title).font(.headline).lineLimit(1)
                            Text(music.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .padding(.bottom, 6)
                        // Lyrics sit in their own soft panel, edged in the album's color.
                        LyricsView(lyrics: lyrics, music: music)
                            .padding(.vertical, 6)
                            .padding(.leading, 12)
                            .padding(.trailing, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06)))
                            .overlay(alignment: .leading) {
                                Capsule().fill(music.artworkColors.first ?? accent)
                                    .frame(width: 3)
                                    .padding(.vertical, 7)
                                    .padding(.leading, 4)
                            }
                            .transition(.opacity)
                    } else {
                        Text(music.title).font(.title3.bold()).lineLimit(1)
                        Text(music.artist).foregroundStyle(.secondary).lineLimit(1)
                        Text(music.album).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                    }

                    Spacer(minLength: 4)
                    ProgressScrubber(music: music)
                    // Room for the controls, which are centered on the whole notch below.
                    Color.clear.frame(height: 44)
                }
            }
            .padding(.horizontal, 4)
            .overlay(alignment: .bottom) {
                // Centered under the tab bar, independent of the album art on the left.
                HStack(spacing: 14) {
                    ControlButton(icon: "shuffle", size: 13, isOn: music.shuffling, accent: accent) { music.toggleShuffle() }
                        .help(music.shuffling ? "Shuffle on" : "Shuffle off")
                    ControlButton(icon: "backward.fill", size: 18) { music.previous() }
                    ControlButton(icon: music.isPlaying ? "pause.fill" : "play.fill", size: 26) { music.playPause() }
                    ControlButton(icon: "forward.fill", size: 18) { music.next() }
                    ControlButton(icon: "repeat", size: 13, isOn: music.repeating, accent: accent) { music.toggleRepeat() }
                        .help(music.repeating ? "Repeat on" : "Repeat off")
                }
                .frame(height: 44)
            }
            .overlay(alignment: .bottomTrailing) {
                VolumeSlider(volume: volume, music: music)
                    .frame(width: 130, height: 44)
                    .padding(.trailing, 4)
            }
        }
    }
}

private extension MusicTab {
    /// Spotify green or Apple Music pink for toggles that are on.
    var accent: Color {
        music.player == .spotify ? Color(red: 0.12, green: 0.84, blue: 0.38) : Color(red: 0.98, green: 0.24, blue: 0.36)
    }
}

/// A small icon button for the header row (skip 15 seconds, favorite).
struct SmallControl: View {
    let icon: String
    let help: String
    var tint: Color? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint ?? (hovering ? .primary : .secondary))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.12 : 0)))
                .contentShape(Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Copies the Spotify song link and briefly shows a checkmark.
struct CopyLinkControl: View {
    let action: () -> Void
    @State private var copied = false

    var body: some View {
        SmallControl(icon: copied ? "checkmark" : "link", help: copied ? "Link copied" : "Copy song link",
                     tint: copied ? .green : nil) {
            action()
            copied = true
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                copied = false
            }
        }
    }
}

/// Karaoke-style synced lyrics: the line being sung, bright and large, between the last and next lines.
struct LyricsView: View {
    @ObservedObject var lyrics: LyricsService
    @ObservedObject var music: NowPlayingService
    @State private var hovering = false

    var body: some View {
        if lyrics.state == .synced {
            TimelineView(.periodic(from: .now, by: 0.1)) { context in
                let index = lyrics.index(at: music.livePosition(at: context.date))
                VStack(alignment: .leading, spacing: 2) {
                    line(index.map { $0 - 1 }, current: false)
                    line(index ?? -1, current: true)
                    line((index ?? -1) + 1, current: false)
                }
                .animation(.snappy(duration: 0.35), value: index)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                // Timing fixes: shown on hover, or always while a fix is active.
                if hovering || lyrics.offset != 0 || lyrics.versionIndex != 0 {
                    SyncControls(lyrics: lyrics, expanded: hovering)
                        .transition(.opacity)
                }
            }
            .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hovering = h } }
        } else {
            // Unsynced lyrics: just the first lines, small.
            Text(lyrics.lines.prefix(3).map(\.text).joined(separator: "\n"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }

    @ViewBuilder
    private func line(_ i: Int?, current: Bool) -> some View {
        let text = i.flatMap { lyrics.lines.indices.contains($0) ? lyrics.lines[$0].text : nil } ?? (current ? "♪" : " ")
        Text(text)
            .font(.system(size: current ? 15 : 11, weight: current ? .bold : .medium))
            .foregroundStyle(current ? Color.white : Color.white.opacity(0.4))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .id(text + (current ? "-now" : ""))
            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
    }
}

struct ProgressScrubber: View {
    @ObservedObject var music: NowPlayingService
    @State private var dragValue: Double?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let duration = max(music.duration, 1)
            let position = dragValue ?? music.livePosition(at: context.date)
            VStack(spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule().fill(Color.white)
                            .frame(width: geo.size.width * min(max(position / duration, 0), 1))
                    }
                    .frame(height: dragValue == nil ? 5 : 8)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            dragValue = min(max(value.location.x / geo.size.width, 0), 1) * duration
                        }
                        .onEnded { _ in
                            if let target = dragValue { music.seek(to: target) }
                            dragValue = nil
                        })
                }
                .frame(height: 12)
                .animation(.snappy, value: dragValue == nil)

                HStack {
                    Text(timeString(position))
                    Spacer()
                    Text("-" + timeString(max(duration - position, 0)))
                }
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
            }
            .opacity(music.duration > 0 ? 1 : 0.3)
        }
    }

    private func timeString(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct ControlButton: View {
    let icon: String
    let size: CGFloat
    /// For toggles like shuffle and repeat: nil for a plain button.
    var isOn: Bool? = nil
    var accent: Color = .green
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: isOn == nil ? .regular : .bold))
                .foregroundStyle(isOn == true ? accent : isOn == false ? Color.secondary : Color.primary)
                .frame(width: size + 18, height: size + 18)
                .overlay(alignment: .bottom) {
                    if isOn == true {
                        Circle().fill(accent).frame(width: 3, height: 3).offset(y: -2)
                    }
                }
                .background(Circle().fill(Color.white.opacity(hovering ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct AlbumArt: View {
    let image: NSImage?
    let cornerRadius: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [.purple, .pink, .orange], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Image(systemName: "music.note").font(.system(size: 18, weight: .bold)).foregroundStyle(.white.opacity(0.8)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Animated spectrum bars, like boring.notch's closed-notch visualizer.
struct AudioVisualizer: View {
    let active: Bool
    let barCount: Int

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !active)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                HStack(alignment: .center, spacing: geo.size.width * 0.12) {
                    ForEach(0..<barCount, id: \.self) { i in
                        let phase = Double(i) * 1.7
                        let wave = (sin(t * (5 + Double(i)) + phase) + sin(t * 3.1 + phase * 2)) / 4 + 0.5
                        Capsule()
                            .fill(Color.white)
                            .frame(height: geo.size.height * (active ? max(0.2, wave) : 0.2))
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}

/// Volume: controls the playing app's own volume (Spotify or Music). With nothing playing,
/// it falls back to the Mac's output volume when that output supports it.
struct VolumeSlider: View {
    @ObservedObject var volume: SystemVolume
    @ObservedObject var music: NowPlayingService
    @State private var dragging = false

    private var usePlayer: Bool { music.player != nil }
    private var enabled: Bool { volume.isAdjustable || usePlayer }
    private var level: Double {
        usePlayer ? music.playerVolume / 100 : (volume.muted ? 0 : Double(volume.volume))
    }

    private var icon: String {
        if (!usePlayer && volume.muted) || level == 0 { return "speaker.slash.fill" }
        switch level {
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                if usePlayer { music.setPlayerVolume(level > 0 ? 0 : 50) } else { volume.toggleMute() }
            } label: {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 20, alignment: .leading)
                    .foregroundStyle(.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help("Mute")

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.15))
                    Capsule().fill(Color.white.opacity(!usePlayer && volume.muted ? 0.3 : 1))
                        .frame(width: max(0, geo.size.width * level))
                }
                .frame(height: dragging ? 8 : 5)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragging = true
                        let fraction = min(max(value.location.x / geo.size.width, 0), 1)
                        if usePlayer { music.setPlayerVolume(fraction * 100) } else { volume.set(Float(fraction)) }
                    }
                    .onEnded { _ in dragging = false })
                .animation(.snappy(duration: 0.15), value: dragging)
            }
            .frame(height: 14)
            .disabled(!enabled)
            .opacity(enabled ? 1 : 0.4)
            .help(usePlayer ? "\(music.player?.rawValue ?? "Player") volume \(Int(level * 100))%"
                  : enabled ? "Mac volume \(Int(level * 100))%" : "Start Spotify or Music to control its volume")
        }
    }
}

/// Small controls for lyrics that are out of sync: earlier / later in half-second steps,
/// and flipping to another volunteer's timing from LRCLIB. Both are remembered per song.
private struct SyncControls: View {
    @ObservedObject var lyrics: LyricsService
    let expanded: Bool

    var body: some View {
        HStack(spacing: 3) {
            if expanded {
                pill(icon: "minus", help: "Lyrics later (−0.5 s)") { lyrics.nudge(by: -0.5) }
            }
            if lyrics.offset != 0 || expanded {
                Button { lyrics.resetTiming() } label: {
                    Text(lyrics.offset == 0 ? "sync" : String(format: "%+.1fs", lyrics.offset))
                        .font(.system(size: 9, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 5)
                        .frame(height: 18)
                }
                .buttonStyle(.plain)
                .help(lyrics.offset == 0 ? "Use − / + to nudge the lyrics" : "Reset timing")
            }
            if expanded {
                pill(icon: "plus", help: "Lyrics sooner (+0.5 s)") { lyrics.nudge(by: 0.5) }
            }
            if lyrics.versions.count > 1 && (expanded || lyrics.versionIndex != 0) {
                Button { lyrics.nextVersion() } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 8, weight: .bold))
                        Text("\(lyrics.versionIndex + 1)/\(lyrics.versions.count)")
                            .font(.system(size: 9, weight: .semibold).monospacedDigit())
                    }
                    .padding(.horizontal, 5)
                    .frame(height: 18)
                }
                .buttonStyle(.plain)
                .help("Try another synced version from LRCLIB")
            }
        }
        .foregroundStyle(.white.opacity(0.85))
        .background(Capsule().fill(Color.black.opacity(0.45)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
    }

    private func pill(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 8, weight: .bold)).frame(width: 18, height: 18).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
