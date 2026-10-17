import AppKit
import SwiftUI

/// Tracks Apple Music and Spotify. Track changes arrive via their distributed notifications (no permission needed);
/// artwork, progress and playback controls use AppleScript (macOS asks for Automation permission once).
@MainActor
final class NowPlayingService: ObservableObject {
    enum Player: String {
        case music = "Music"
        case spotify = "Spotify"

        var bundleID: String { self == .music ? "com.apple.Music" : "com.spotify.client" }
        var notification: String { self == .music ? "com.apple.Music.playerInfo" : "com.spotify.client.PlaybackStateChanged" }
    }

    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var album = ""
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage? {
        didSet { artworkColors = artwork.map(ArtworkPalette.colors(from:)) ?? [] }
    }
    /// A few vivid colors from the current artwork, for the music tab's glow.
    @Published private(set) var artworkColors: [Color] = []
    @Published private(set) var player: Player?
    @Published private(set) var position: Double = 0
    @Published private(set) var positionDate = Date()
    @Published private(set) var duration: Double = 0
    @Published private(set) var shuffling = false
    @Published private(set) var repeating = false
    /// Apple Music only: the current song is in Favorites (Loved on older macOS).
    @Published private(set) var isFavorite = false
    /// Spotify only: an open.spotify.com link to the current track.
    @Published private(set) var trackLink: URL?
    private var togglesChangedAt = Date.distantPast
    /// The player app's own volume (0…100). Used when the Mac's output can't change volume (e.g. HDMI).
    @Published private(set) var playerVolume: Double = 50
    private var volumeChangedAt = Date.distantPast

    private var artworkKey = ""
    private let scriptQueue = DispatchQueue(label: "BasicNotch.applescript")
    private var progressLoop: Task<Void, Never>?

    init() {
        for p in [Player.music, .spotify] {
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(p.notification), object: nil, queue: .main
            ) { [weak self] note in
                let info = note.userInfo ?? [:]
                let title = info["Name"] as? String ?? ""
                let artist = info["Artist"] as? String ?? ""
                let album = info["Album"] as? String ?? ""
                let state = info["Player State"] as? String ?? ""
                MainActor.assumeIsolated {
                    self?.update(player: p, title: title, artist: artist, album: album, state: state)
                }
            }
        }
        refresh()
        progressLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, self.isPlaying else { continue }
                self.pollProgress()
            }
        }
    }

    /// Current playback position, extrapolated between polls so the progress bar moves smoothly.
    /// Set once the current song's own duration has been read, so lyrics can be matched to the right version.
    @Published private(set) var durationReadyKey = ""

    func livePosition(at date: Date) -> Double {
        guard isPlaying else { return position }
        return min(duration, position + date.timeIntervalSince(positionDate))
    }

    // MARK: Controls

    func playPause() { send("playpause") }
    func next() { send("next track") }
    func previous() { send("previous track") }

    /// Jump forward or back within the song, e.g. ±15 seconds.
    func skip(by seconds: Double) {
        seek(to: min(max(livePosition(at: Date()) + seconds, 0), max(duration - 1, 0)))
    }

    func toggleShuffle() {
        guard let p = player else { return }
        shuffling.toggle()
        togglesChangedAt = Date()
        run(p == .spotify
            ? "tell application \"Spotify\" to set shuffling to not shuffling"
            : "tell application \"Music\" to set shuffle enabled to not shuffle enabled")
    }

    func toggleRepeat() {
        guard let p = player else { return }
        repeating.toggle()
        togglesChangedAt = Date()
        run(p == .spotify
            ? "tell application \"Spotify\" to set repeating to not repeating"
            : """
            tell application "Music"
                if song repeat is off then
                    set song repeat to all
                else
                    set song repeat to off
                end if
            end tell
            """)
    }

    /// Apple Music: add or remove the current song from Favorites.
    func toggleFavorite() {
        guard player == .music else { return }
        isFavorite.toggle()
        togglesChangedAt = Date()
        let value = isFavorite ? "true" : "false"
        run("""
        tell application "Music"
            try
                set favorited of current track to \(value)
            on error
                set loved of current track to \(value)
            end try
        end tell
        """)
    }

    /// Spotify: copy a shareable link to the current song.
    func copyTrackLink() {
        guard let trackLink else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trackLink.absoluteString, forType: .string)
    }

    func seek(to seconds: Double) {
        guard let p = player else { return }
        position = seconds
        positionDate = Date()
        run("tell application \"\(p.rawValue)\" to set player position to \(seconds)")
    }

    func setPlayerVolume(_ value: Double) {
        guard let p = player else { return }
        let v = Int(min(max(value, 0), 100).rounded())
        playerVolume = Double(v)
        volumeChangedAt = Date()
        run("tell application \"\(p.rawValue)\" to set sound volume to \(v)")
    }

    func launch(_ p: Player) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: p.bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func bringPlayerToFront() {
        if let p = player { launch(p) }
    }

    // MARK: State

    func refresh() {
        for p in [Player.spotify, .music] where isRunning(p) {
            let source = """
            tell application "\(p.rawValue)"
                if player state is stopped then return ""
                set t to current track
                return (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & (player state as string)
            end tell
            """
            run(source) { [weak self] result in
                guard let parts = result?.stringValue?.components(separatedBy: "\n"), parts.count >= 4 else { return }
                self?.update(player: p, title: parts[0], artist: parts[1], album: parts[2], state: parts[3])
            }
        }
    }

    private func update(player p: Player, title: String, artist: String, album: String, state: String) {
        let state = state.lowercased()
        if state == "stopped" || title.isEmpty {
            if player == p || player == nil { clear() }
            return
        }
        // A paused player shouldn't steal the notch from one that's actively playing.
        if state != "playing", let current = player, current != p, isPlaying { return }

        player = p
        self.title = title
        self.artist = artist
        self.album = album
        isPlaying = state == "playing"

        let key = "\(p.rawValue)|\(title)|\(artist)"
        if key != artworkKey {
            artworkKey = key
            artwork = nil
            position = 0
            positionDate = Date()
            fetchArtwork(for: p, key: key)
        }
        pollProgress()
    }

    private func clear() {
        player = nil
        title = ""
        artist = ""
        album = ""
        isPlaying = false
        artwork = nil
        artworkKey = ""
        position = 0
        duration = 0
        shuffling = false
        repeating = false
        isFavorite = false
        trackLink = nil
    }

    private func pollProgress() {
        guard let p = player else { return }
        // Spotify reports duration in milliseconds, Music in seconds.
        let durationExpr = p == .spotify ? "((duration of current track) / 1000)" : "(duration of current track)"
        // Then shuffle, repeat, and the Spotify link or the Music favorite state.
        let extras = p == .spotify
            ? "(shuffling as string) & linefeed & (repeating as string) & linefeed & (spotify url of current track)"
            : "(shuffle enabled as string) & linefeed & (song repeat as string) & linefeed & fav"
        let favorite = p == .music ? """
                set fav to "false"
                try
                    set fav to (favorited of current track) as string
                on error
                    try
                        set fav to (loved of current track) as string
                    end try
                end try
        """ : ""
        let source = """
        tell application "\(p.rawValue)"
        \(favorite)
            return ((player position) as string) & linefeed & (\(durationExpr) as string) & linefeed & ((sound volume) as string) & linefeed & \(extras)
        end tell
        """
        let requested = Date()
        let trackKey = artworkKey
        run(source) { [weak self] result in
            guard let self,
                  let parts = result?.stringValue?.components(separatedBy: "\n"), parts.count >= 2,
                  let pos = Double(parts[0].replacingOccurrences(of: ",", with: ".")),
                  let dur = Double(parts[1].replacingOccurrences(of: ",", with: "."))
            else { return }
            // The script runs on a background queue; the position was read roughly halfway through
            // the round trip, not when the answer arrived. Stamp it then so lyrics don't lag.
            let readAt = requested.addingTimeInterval(Date().timeIntervalSince(requested) / 2)
            let predicted = self.livePosition(at: readAt)
            // Small differences are just polling jitter — keep the smooth clock instead of jumping back.
            if !self.isPlaying || abs(predicted - pos) > 0.25 || self.duration != dur {
                self.position = pos
                self.positionDate = readAt
            }
            self.duration = dur
            if trackKey == self.artworkKey, dur > 0 { self.durationReadyKey = trackKey }
            // Don't fight the slider while it's being dragged.
            if parts.count >= 3, let vol = Double(parts[2]), Date().timeIntervalSince(self.volumeChangedAt) > 2 {
                self.playerVolume = vol
            }
            // Skip right after a click, so a slow poll doesn't flip the button back.
            if parts.count >= 6, Date().timeIntervalSince(self.togglesChangedAt) > 2 {
                self.shuffling = parts[3] == "true"
                self.repeating = parts[4] != "false" && parts[4] != "off"
                if p == .spotify {
                    // spotify:track:ID → https://open.spotify.com/track/ID
                    let uri = parts[5].split(separator: ":")
                    self.trackLink = uri.count == 3 ? URL(string: "https://open.spotify.com/\(uri[1])/\(uri[2])") : nil
                    self.isFavorite = false
                } else {
                    self.isFavorite = parts[5] == "true"
                    self.trackLink = nil
                }
            }
        }
    }

    private func fetchArtwork(for p: Player, key: String) {
        switch p {
        case .music:
            run("tell application \"Music\" to get raw data of artwork 1 of current track") { [weak self] result in
                guard let self, self.artworkKey == key, let data = result?.data, let image = NSImage(data: data) else { return }
                self.artwork = image
            }
        case .spotify:
            run("tell application \"Spotify\" to get artwork url of current track") { [weak self] result in
                guard let string = result?.stringValue, let url = URL(string: string) else { return }
                Task { [weak self] in
                    guard let response = try? await URLSession.shared.data(from: url),
                          let self, self.artworkKey == key else { return }
                    self.artwork = NSImage(data: response.0)
                }
            }
        }
    }

    // MARK: Helpers

    private func send(_ command: String) {
        guard let p = player else { return }
        run("tell application \"\(p.rawValue)\" to \(command)") { [weak self] _ in self?.refresh() }
    }

    private func isRunning(_ p: Player) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: p.bundleID).isEmpty
    }

    private func run(_ source: String, completion: (@MainActor (NSAppleEventDescriptor?) -> Void)? = nil) {
        scriptQueue.async {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion?(result) }
            }
        }
    }
}
