import SwiftUI
import Combine

enum NotchTab: String, CaseIterable, Identifiable {
    case music, sports, gaming, crypto, weather, files, pokedex, focus, system

    var id: Self { self }

    var title: String {
        switch self {
        case .music: "Now Playing"
        case .sports: "Sports"
        case .gaming: "Gaming"
        case .crypto: "Crypto"
        case .weather: "Weather"
        case .files: "Shelf"
        case .pokedex: "Pokédex"
        case .focus: "Focus"
        case .system: "System"
        }
    }

    var icon: String {
        switch self {
        case .music: "music.note"
        case .sports: "sportscourt.fill"
        case .gaming: "gamecontroller.fill"
        case .crypto: "bitcoinsign.circle.fill"
        case .weather: "cloud.sun.fill"
        case .pokedex: "circle.circle"
        case .focus: "timer"
        case .system: "cpu"
        case .files: "tray.full.fill"
        }
    }
}

extension NotchTab {
    /// Tabs switched off in Settings are stored as a comma-separated list under "hiddenTabs".
    static func visible(hidden: String) -> [NotchTab] {
        let off = Set(hidden.split(separator: ",").map(String.init))
        return allCases.filter { !off.contains($0.rawValue) }
    }

    static func setHidden(_ tab: NotchTab, _ isHidden: Bool, in hidden: String) -> String {
        var off = Set(hidden.split(separator: ",").map(String.init))
        if isHidden { off.insert(tab.rawValue) } else { off.remove(tab.rawValue) }
        return allCases.map(\.rawValue).filter(off.contains).joined(separator: ",")
    }
}

enum AppSettings {
    static let defaults: [String: Any] = [
        "wingWidth": 110.0,
        "hiddenTabs": "",
        "notchDisplayID": 0,
        "showPokemon": true,
        "pokemonCount": 3,
        "shinyOdds": 64,
        "pokemonBattles": true,
        "pokemonCatching": true,
        "weatherPokemon": true,
        "notchAlerts": true,
        "tumblrClientID": "",
        "tumblrBlog": "",
        "alertScores": true,
        "alertFriends": true,
        "alertCoinMoves": true,
        "alertPrices": true,
        "alertCalendar": true,
        "alertAirPods": true,
        "pokemonMaxDex": 0,
        "musicLiveActivity": true,
        "hapticsEnabled": true,
        "glassBackground": true,
        "notchTheme": NotchTheme.glass.rawValue,
        "albumGlow": true,
        "showLyrics": true,
        "liveDownloads": true,
        "liveRecording": true,
        "liveCardIngest": true,
        "liveGoldenHour": true,
        "alertSunset": true,
        "alertSunsetGoodOnly": true,
        "alertCard": true,
        "alertDownloads": true,
        "neonGlow": true,
        "weatherCity": "New York",
        "weatherUseCurrentLocation": false,
        "useFahrenheit": true,
        "weatherPortfolioBackdrop": false,
        "cryptoCoins": "bitcoin,ethereum,solana,dogecoin",
        "favoriteTeams": "",
        "league": "nfl",
        "claudeBlockLimit": 0,
    ]

    static func register() {
        let store = UserDefaults.standard
        // Carry over the old "Liquid Glass fade" toggle: turning it off meant a plain black notch.
        if store.object(forKey: "notchTheme") == nil, store.object(forKey: "glassBackground") as? Bool == false {
            store.set(NotchTheme.black.rawValue, forKey: "notchTheme")
        }
        store.register(defaults: defaults)
    }
}

@MainActor
final class NotchViewModel: ObservableObject {
    @Published var isOpen = false
    @Published var isPinned = false
    @Published var tab: NotchTab = .music
    @Published var notchSize = CGSize(width: 190, height: 32)
    @Published var hasNotch = true
    @Published var isDropTargeted = false
    @Published var showMirror = false
    @Published var banner: NotchBanner?
    var bannerQueue: [NotchBanner] = []

    let expandedSize = CGSize(width: 780, height: 290)

    let music = NowPlayingService()
    let sports = SportsService()
    let psn = PSNService()
    let crypto = CryptoService()
    let weather = WeatherService()
    let files = FileTrayService()
    let calendar = CalendarService()
    let battery = BatteryService()
    let party = PokemonParty()
    let cursor = CursorTracker()
    let clipboard = ClipboardService()
    let tumblr = TumblrService()
    let portfolio = GalleryManagerInbox()
    let volume = SystemVolume()
    let focus = FocusTimer()
    let system = SystemStatsService()
    let airpods = AirPodsService()
    let claude = ClaudeUsageService()
    let lyrics = LyricsService()
    let cards = CardIngestService()
    let downloads = DownloadMonitor()
    let recording = ScreenRecordingMonitor()
    let goldenHour = GoldenHourClock()

    var openSettings: () -> Void = {}
    var bag = Set<AnyCancellable>()

    init() {
        AppSettings.register()
    }

    func start() {
        music.$isPlaying.sink { [weak self] in self?.party.musicPlaying = $0 }.store(in: &bag)
        $isOpen.sink { [weak self] in self?.party.isOpen = $0 }.store(in: &bag)
        $notchSize.sink { [weak self] in self?.party.notchHalfWidth = $0.width / 2 }.store(in: &bag)
        // Forward nested changes that affect the closed-notch layout.
        music.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        battery.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        focus.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        cards.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        downloads.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        recording.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)
        goldenHour.objectWillChange.sink { [weak self] in self?.objectWillChange.send() }.store(in: &bag)

        // Look up lyrics whenever the song changes — once its own length is known, so LRCLIB returns
        // the version that matches (remasters and edits have different timings).
        music.$durationReadyKey
            .removeDuplicates()
            .sink { [weak self] _ in
                guard let self, !self.music.title.isEmpty else { return }
                self.lyrics.load(title: self.music.title, artist: self.music.artist,
                                 album: self.music.album, duration: self.music.duration)
            }
            .store(in: &bag)
        // Fallback if the length never arrives (e.g. Automation permission denied): look up without it.
        music.$title.combineLatest(music.$artist, music.$album)
            .debounce(for: .seconds(3), scheduler: RunLoop.main)
            .sink { [weak self] title, artist, album in
                self?.lyrics.load(title: title, artist: artist, album: album, duration: 0)
            }
            .store(in: &bag)
        music.$title.sink { [weak self] title in
            if title.isEmpty { self?.lyrics.load(title: "", artist: "", album: "", duration: 0) }
        }.store(in: &bag)

        party.start()
        sports.start()
        psn.start()
        crypto.start()
        weather.start()
        calendar.start()
        battery.start()
        claude.start()
        clipboard.start()
        system.start()
        airpods.start()
        cards.start()
        downloads.start()
        recording.start()
        goldenHour.start { [weak self] in self?.weather.days.first?.sunset }
        weather.$days.sink { [weak self] _ in
            DispatchQueue.main.async { self?.goldenHour.check() }
        }.store(in: &bag)
        startAlerts()
    }

    /// Pinned, or the user is typing (coin search, Tumblr post).
    var keepsOpen: Bool { isPinned || crypto.isSearching || tumblr.isComposing || portfolio.isComposing }

    /// Live activities beyond music, in priority order: the first one active shows in the closed notch.
    enum LiveActivity: Equatable {
        case cardImport, download, recording, card, goldenHour
    }

    var liveActivity: LiveActivity? {
        let on = { (key: String) in UserDefaults.standard.bool(forKey: key) }
        if cards.progress != nil && on("liveCardIngest") { return .cardImport }
        if !downloads.items.isEmpty && on("liveDownloads") { return .download }
        if recording.isRecording && on("liveRecording") { return .recording }
        if let card = cards.card, !card.newFiles.isEmpty, on("liveCardIngest") { return .card }
        if goldenHour.isActive && on("liveGoldenHour") { return .goldenHour }
        return nil
    }

    /// Size of the closed notch: wings appear for Pokémon or any live activity (music, charging, timer, alert).
    func closedSize(wingWidth: Double, showPokemon: Bool, musicLiveActivity: Bool) -> CGSize {
        let live = (musicLiveActivity && music.isPlaying) || battery.flash || focus.isActive || banner != nil
            || liveActivity != nil
        let wing = banner != nil ? max(wingWidth, 150) : wingWidth
        return CGSize(width: notchSize.width + ((showPokemon || live) ? wing * 2 : 0), height: notchSize.height)
    }

    func open() {
        guard !isOpen else { return }
        isOpen = true
        if UserDefaults.standard.bool(forKey: "hapticsEnabled") {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    func close() {
        guard isOpen, !keepsOpen else { return }
        isOpen = false
        showMirror = false
    }
}
