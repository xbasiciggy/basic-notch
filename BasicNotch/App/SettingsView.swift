import SwiftUI
import ServiceManagement

struct SettingsView: View {
    var onRespawn: () -> Void
    @ObservedObject var tumblr: TumblrService

    @AppStorage("showPokemon") private var showPokemon = true
    @AppStorage("pokemonCount") private var pokemonCount = 3
    @AppStorage("pokemonMaxDex") private var maxDex = 0
    @AppStorage("shinyOdds") private var shinyOdds = 64
    @AppStorage("wingWidth") private var wingWidth = 110.0
    @AppStorage("musicLiveActivity") private var musicLiveActivity = true
    @AppStorage("hapticsEnabled") private var haptics = true
    @AppStorage("weatherCity") private var city = "New York"
    @AppStorage("weatherUseCurrentLocation") private var useCurrentLocation = false
    @AppStorage("useFahrenheit") private var fahrenheit = true
    @AppStorage("cryptoCoins") private var coins = "bitcoin,ethereum,solana,dogecoin"
    @AppStorage("favoriteTeams") private var favoriteTeams = ""
    @AppStorage("claudeBlockLimit") private var claudeLimit = 0
    @AppStorage("notchAllDisplays") private var allDisplays = false
    @AppStorage("liveLightroomExports") private var liveLightroomExports = true
    @AppStorage("alertLightroomExports") private var alertLightroomExports = true
    @AppStorage("notchDisplayID") private var displayID = 0
    @AppStorage("hiddenTabs") private var hiddenTabs = ""
    @AppStorage("notchTheme") private var theme: NotchTheme = .glass
    @AppStorage("albumGlow") private var albumGlow = true
    @AppStorage("showLyrics") private var showLyrics = true
    @AppStorage("liveDownloads") private var liveDownloads = true
    @AppStorage("liveRecording") private var liveRecording = true
    @AppStorage("liveCardIngest") private var liveCardIngest = true
    @AppStorage("liveGoldenHour") private var liveGoldenHour = true
    @AppStorage("alertSunset") private var alertSunset = true
    @AppStorage("alertSunsetGoodOnly") private var alertSunsetGoodOnly = true
    @AppStorage("alertCard") private var alertCard = true
    @AppStorage("alertDownloads") private var alertDownloads = true
    @AppStorage("settingsTab") private var selectedTab = "general"
    @AppStorage("neonGlow") private var neonGlow = true
    @AppStorage("pokemonBattles") private var battles = true
    @AppStorage("neonColor") private var neonHex = "#33E6FF"
    @AppStorage("neonIntensity") private var neonIntensity = 0.45
    @AppStorage("pokemonCatching") private var catching = true
    @AppStorage("weatherPokemon") private var weatherPokemon = true
    @AppStorage("notchAlerts") private var notchAlerts = true
    @AppStorage("alertScores") private var alertScores = true
    @AppStorage("alertFriends") private var alertFriends = true
    @AppStorage("alertCoinMoves") private var alertCoinMoves = true
    @AppStorage("alertPrices") private var alertPrices = true
    @AppStorage("alertCalendar") private var alertCalendar = true
    @AppStorage("alertAirPods") private var alertAirPods = true
    @AppStorage("tumblrClientID") private var tumblrClientID = ""
    @AppStorage("tumblrBlog") private var tumblrBlog = ""
    @State private var tumblrSecret = Keychain.get(TumblrService.secretAccount) ?? ""
    @State private var loginError: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag("general")
            appearanceTab
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
                .tag("appearance")
            pokemonTab
                .tabItem { Label("Pokémon", systemImage: "pawprint") }
                .tag("pokemon")
            alertsTab
                .tabItem { Label("Alerts", systemImage: "bell.badge") }
                .tag("alerts")
            widgetsTab
                .tabItem { Label("Widgets", systemImage: "square.grid.2x2") }
                .tag("widgets")
            accountsTab
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }
                .tag("accounts")
        }
        .frame(width: 540, height: 600)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            Section {
                ForEach(NotchTab.allCases) { tab in
                    Toggle(isOn: tabBinding(tab)) {
                        Label(tab.title, systemImage: tab.icon)
                    }
                }
            } header: {
                Text("Notch tabs")
            } footer: {
                Text("Choose which tabs appear when the notch opens.")
            }

            Section {
                Toggle("Lightroom Classic export progress", isOn: $liveLightroomExports)
                Toggle(isOn: $liveDownloads) { Label("Downloads and AirDrop progress", systemImage: "arrow.down.circle") }
                Toggle(isOn: $liveCardIngest) { Label("Camera card import", systemImage: "sdcard") }
                Toggle(isOn: $liveRecording) { Label("Screen recording timer", systemImage: "record.circle") }
                Toggle(isOn: $liveGoldenHour) { Label("Golden hour countdown to sunset", systemImage: "sun.horizon") }
            } header: {
                Text("Live activities")
            } footer: {
                Text("Shown in the closed notch while they're happening. Screen recording is detected from macOS's own recorder (Screenshot toolbar or QuickTime).")
            }

            Section("Behavior") {
                Toggle("Show notch on all connected displays", isOn: $allDisplays)
                Picker("Screen", selection: $displayID) {
                    Text("Automatic (built-in display)").tag(0)
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        Text(NotchScreen.name(of: screen)).tag(NotchScreen.id(of: screen))
                    }
                }
                .disabled(allDisplays)
                Toggle("Show album art & visualizer when music plays", isOn: $musicLiveActivity)
                Toggle("Haptic feedback when the notch opens", isOn: $haptics)
                if let loginError { Text(loginError).font(.caption).foregroundStyle(.red) }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }
            Section {
                HStack {
                    Text("BasicNotch").fontWeight(.medium)
                    Spacer()
                    Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") · Build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—")")
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .font(.caption)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Appearance

    private var appearanceTab: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    ForEach(NotchTheme.allCases) { option in
                        themeCard(option)
                    }
                }
                .padding(.vertical, 4)
                Text(theme.subtitle).font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Theme")
            } footer: {
                Text("The top of the notch always stays solid black so the camera disappears.")
            }

            Section {
                Toggle("Glow with album colors on the Music tab", isOn: $albumGlow)
                Toggle("Show synced lyrics when available", isOn: $showLyrics)
            } header: {
                Text("Music")
            } footer: {
                Text("The bottom of the notch picks up colors from the current song's artwork.")
            }

            Section("Size") {
                VStack(alignment: .leading) {
                    Text("Wing width: \(Int(wingWidth)) pt")
                    Slider(value: $wingWidth, in: 60...220, step: 10)
                }
            }

            Section("Neon glow") {
                Toggle("Neon glow follows the cursor", isOn: $neonGlow)
                if neonGlow {
                    DisclosureGroup("Color and strength") {
                        HStack {
                            Text("Glow color")
                            Spacer()
                            ForEach(["#33E6FF", "#FF3DD8", "#8A5CFF", "#3DFF8A", "#FFB23D", "#FFFFFF"], id: \.self) { hex in
                                Button { neonHex = hex } label: {
                                    Circle().fill(Color(hex: hex) ?? .white)
                                        .frame(width: 18, height: 18)
                                        .overlay(Circle().stroke(Color.primary, lineWidth: neonHex == hex ? 2 : 0).padding(-3))
                                }
                                .buttonStyle(.plain)
                            }
                            ColorPicker("", selection: Binding(get: { Color(hex: neonHex) ?? .cyan },
                                                               set: { neonHex = $0.hexString }), supportsOpacity: false)
                                .labelsHidden()
                        }
                        VStack(alignment: .leading) {
                            Text("Glow strength: \(Int(neonIntensity * 100))%")
                            Slider(value: $neonIntensity, in: 0.1...1)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func themeCard(_ option: NotchTheme) -> some View {
        Button { theme = option } label: {
            VStack(spacing: 6) {
                option.swatch
                    .frame(height: 54)
                    .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14))
                    .overlay(UnevenRoundedRectangle(bottomLeadingRadius: 14, bottomTrailingRadius: 14)
                        .stroke(theme == option ? Color.accentColor : Color.secondary.opacity(0.3),
                                lineWidth: theme == option ? 2 : 0.5))
                Text(option.title)
                    .font(.caption)
                    .foregroundStyle(theme == option ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(theme == option ? .isSelected : [])
    }

    // MARK: - Pokémon

    private var pokemonTab: some View {
        Form {
            Section {
                if PokeBrawlSprites.roster.isEmpty {
                    Text("Sprite artwork is not included in this build. Pokémon features need a separately supplied Mons.bundle. See the User Guide in the menu bar.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Show Pokémon walking on the notch", isOn: $showPokemon)
                Stepper("Party size: \(pokemonCount)", value: $pokemonCount, in: 1...6)
                Button("Respawn party", action: onRespawn)
            } header: {
                Text("Party")
            }

            Section("Behavior") {
                Toggle("Pokémon battle each other sometimes", isOn: $battles)
                Toggle("Click a Pokémon to throw a Poké Ball", isOn: $catching)
                Toggle("Weather decides which types appear", isOn: $weatherPokemon)
            }

            Section("Pokédex") {
                Picker("Pokédex", selection: $maxDex) {
                    Text("Full roster").tag(0)
                    Text("Gen 1 · Kanto").tag(151)
                    Text("Up to Gen 2 · Johto").tag(251)
                    Text("Up to Gen 3 · Hoenn").tag(386)
                    Text("Up to Gen 4 · Sinnoh").tag(493)
                    Text("Up to Gen 5 · Unova").tag(649)
                    Text("Up to Gen 7 · Alola").tag(809)
                }
                Picker("Shiny odds", selection: $shinyOdds) {
                    Text("1 in 8 (lucky)").tag(8)
                    Text("1 in 64").tag(64)
                    Text("1 in 512").tag(512)
                    Text("1 in 4096 (official)").tag(4096)
                }
                DisclosureGroup("Reset") {
                    Button("Reset Pokédex", role: .destructive) { PokedexStore.shared.reset() }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Alerts

    private var alertsTab: some View {
        Form {
            Section {
                Toggle("Show alerts in the closed notch", isOn: $notchAlerts)
                if notchAlerts {
                    DisclosureGroup("Sports and gaming") {
                        Toggle("Favorite team scores & finals", isOn: $alertScores)
                        Toggle("PS5 friend starts a game", isOn: $alertFriends)
                    }
                    DisclosureGroup("Crypto") {
                        Toggle("Coin moves 5% in a day", isOn: $alertCoinMoves)
                        Toggle("Price alerts (set with 🔔 on a coin chart)", isOn: $alertPrices)
                    }
                    DisclosureGroup("Photography") {
                        Toggle("Sunset forecast, 45 min before golden hour", isOn: $alertSunset)
                        if alertSunset {
                            Toggle("Only when the color looks good (55+)", isOn: $alertSunsetGoodOnly)
                        }
                        Toggle("Lightroom export finished or failed", isOn: $alertLightroomExports)
                        Toggle("Camera card inserted and imported", isOn: $alertCard)
                    }
                    DisclosureGroup("System") {
                        Toggle("Download or AirDrop finished", isOn: $alertDownloads)
                        Toggle("Calendar event in 5 minutes", isOn: $alertCalendar)
                        Toggle("AirPods connect", isOn: $alertAirPods)
                    }
                }
            } header: {
                Text("Alerts")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Widgets

    private var widgetsTab: some View {
        Form {
            Section("Weather") {
                Toggle("Use my current location", isOn: $useCurrentLocation)
                TextField("City", text: $city)
                    .disabled(useCurrentLocation)
                Toggle("Fahrenheit", isOn: $fahrenheit)
            }

            Section {
                TextField("Coins", text: $coins)
            } header: {
                Text("Crypto")
            } footer: {
                Text("CoinGecko IDs, comma separated — e.g. bitcoin, ethereum, solana, cardano, pepe")
            }

            Section {
                TextField("Favorite teams", text: $favoriteTeams)
            } header: {
                Text("Sports")
            } footer: {
                Text("Team abbreviations, comma separated — e.g. LAL, DAL, NYY. Favorites are pinned first and highlighted.")
            }

            Section {
                TextField("Tokens per 5-hour window", value: $claudeLimit, format: .number)
            } header: {
                Text("Claude usage bar")
            } footer: {
                Text("Reads Claude Code's logs on this Mac. Leave at 0 to measure against your busiest window this week, or enter a token budget for your plan.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Accounts

    private var accountsTab: some View {
        Form {
            Section {
                if tumblr.isSignedIn {
                    Picker("Blog", selection: Binding(get: { tumblr.selectedBlog }, set: { tumblrBlog = $0 })) {
                        ForEach(tumblr.blogs) { Text($0.title == $0.name ? $0.name : "\($0.title) (\($0.name))").tag($0.name) }
                    }
                    Button("Sign out of Tumblr", role: .destructive) { tumblr.signOut() }
                } else {
                    Button("Sign in to Tumblr") { tumblr.signIn() }
                        .disabled(tumblrClientID.isEmpty || tumblrSecret.isEmpty)
                }
                DisclosureGroup("App keys") {
                    TextField("OAuth consumer key", text: $tumblrClientID)
                    SecureField("OAuth consumer secret", text: $tumblrSecret)
                        .onChange(of: tumblrSecret) { _, value in
                            Keychain.set(value.trimmingCharacters(in: .whitespacesAndNewlines), for: TumblrService.secretAccount)
                        }
                    HStack {
                        Text("Redirect URL").foregroundStyle(.secondary)
                        Spacer()
                        Text(TumblrService.redirectURI).font(.caption.monospaced()).textSelection(.enabled)
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(TumblrService.redirectURI, forType: .string)
                        }
                    }
                }
                if let error = tumblr.error { Text(error).font(.caption).foregroundStyle(.red) }
            } header: {
                Text("Tumblr")
            } footer: {
                Text("Register a free app at tumblr.com/oauth/apps, set its OAuth2 redirect URL to the one under App keys, then paste its consumer key and secret there. The secret and your sign-in are stored in the Keychain.")
            }
            .task { if tumblr.isSignedIn && tumblr.blogs.isEmpty { await tumblr.loadBlogs() } }
        }
        .formStyle(.grouped)
    }

    private func tabBinding(_ tab: NotchTab) -> Binding<Bool> {
        Binding(
            get: { NotchTab.visible(hidden: hiddenTabs).contains(tab) },
            set: { hiddenTabs = NotchTab.setHidden(tab, !$0, in: hiddenTabs) })
    }
}
