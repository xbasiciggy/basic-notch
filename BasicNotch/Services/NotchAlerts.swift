import SwiftUI
import Combine

/// A short live-activity banner shown in the closed notch: icon + title on the left wing, detail on the right.
struct NotchBanner: Identifiable, Equatable {
    let id = UUID()
    let icon: String  // SF Symbol or emoji
    let title: String
    let detail: String
    let tint: Color
    /// Optional web pictures: a round one replacing the icon, and a square one beside the detail.
    var image: URL? = nil
    var detailImage: URL? = nil

    var iconIsEmoji: Bool { icon.unicodeScalars.first.map { !$0.isASCII } ?? false }
}

// MARK: - Price alerts

struct PriceAlert: Codable, Identifiable, Equatable {
    var id = UUID()
    let coinID: String
    let symbol: String
    let target: Double
    let above: Bool
}

@MainActor
final class PriceAlertStore: ObservableObject {
    static let shared = PriceAlertStore()
    @Published private(set) var alerts: [PriceAlert] = []
    private let key = "priceAlerts"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([PriceAlert].self, from: data) { alerts = saved }
    }

    func add(_ alert: PriceAlert) { alerts.append(alert); save() }
    func remove(_ alert: PriceAlert) { alerts.removeAll { $0 == alert }; save() }
    func alerts(for coinID: String) -> [PriceAlert] { alerts.filter { $0.coinID == coinID } }

    private func save() {
        if let data = try? JSONEncoder().encode(alerts) { UserDefaults.standard.set(data, forKey: key) }
    }
}

// MARK: - Watching everything for alerts

extension NotchViewModel {
    func show(_ banner: NotchBanner) {
        bannerQueue.append(banner)
        if self.banner == nil { showNextBanner() }
    }

    private func showNextBanner() {
        guard !bannerQueue.isEmpty else { return }
        let next = bannerQueue.removeFirst()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { banner = next }
        if UserDefaults.standard.bool(forKey: "hapticsEnabled") {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { self.banner = nil }
            try? await Task.sleep(for: .milliseconds(500))
            self.showNextBanner()
        }
    }

    private func alertOn(_ key: String) -> Bool {
        UserDefaults.standard.bool(forKey: "notchAlerts") && UserDefaults.standard.bool(forKey: key)
    }

    func startAlerts() {
        watchScores()
        watchFriends()
        watchCoins()
        watchCalendar()
        watchSunset()

        cards.onInsert = { [weak self] card in
            guard let self else { return }
            self.tab = .files  // so opening the notch lands on the import panel
            guard self.alertOn("alertCard") else { return }
            let detail = card.newFiles.isEmpty ? "Nothing new to import" : "\(card.newFiles.count) new to import"
            self.show(NotchBanner(icon: "sdcard.fill", title: card.name, detail: detail, tint: .orange))
        }
        cards.onImported = { [weak self] result in
            guard let self, self.alertOn("alertCard") else { return }
            self.show(NotchBanner(icon: "checkmark.circle.fill", title: "Imported \(result.count)",
                                  detail: "Pictures › Card Imports", tint: .green))
            self.party.react("📸 Nice shots!", happy: true)
        }
        downloads.onFinish = { [weak self] name, isAirDrop in
            guard let self, self.alertOn("alertDownloads") else { return }
            self.show(NotchBanner(icon: isAirDrop ? "airplayaudio" : "arrow.down.circle.fill",
                                  title: isAirDrop ? "AirDrop received" : "Downloaded", detail: name, tint: .blue))
        }

        airpods.onConnect = { [weak self] device in
            guard let self, self.alertOn("alertAirPods") else { return }
            self.show(NotchBanner(icon: "airpodspro", title: device.name, detail: device.summary, tint: .white))
        }
        focus.onFinish = { [weak self] in
            guard let self else { return }
            self.show(NotchBanner(icon: "timer", title: "Focus done", detail: "Take a break 🎉", tint: .orange))
            self.party.react("⏰ Time's up!", happy: true)
        }
        focus.$isRunning.sink { [weak self] in self?.party.focusMode = $0 }.store(in: &bag)
        weather.$now.sink { [weak self] now in
            self?.party.weather = now.map { ($0.code, $0.isDay) }
        }.store(in: &bag)
    }

    /// Favorite teams scoring (and games going final).
    private func watchScores() {
        var last: [String: (away: String, home: String, state: String)] = [:]
        sports.$games.sink { [weak self] games in
            guard let self else { return }
            let favorites = Set((UserDefaults.standard.string(forKey: "favoriteTeams") ?? "")
                .uppercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            for g in games {
                defer { last[g.id] = (g.away.score, g.home.score, g.state) }
                guard let prev = last[g.id], self.alertOn("alertScores") else { continue }
                let awayFav = favorites.contains(g.away.abbr.uppercased())
                let homeFav = favorites.contains(g.home.abbr.uppercased())
                guard awayFav || homeFav else { continue }
                let line = "\(g.away.abbr) \(g.away.score) – \(g.home.score) \(g.home.abbr)"
                if g.state == "post" && prev.state != "post" {
                    self.show(NotchBanner(icon: "flag.checkered", title: "Final", detail: line, tint: .white))
                    continue
                }
                let awayUp = (Int(g.away.score) ?? 0) > (Int(prev.away) ?? 0)
                let homeUp = (Int(g.home.score) ?? 0) > (Int(prev.home) ?? 0)
                guard awayUp || homeUp else { continue }
                let scorer = awayUp ? g.away.abbr : g.home.abbr
                let favScored = (awayUp && awayFav) || (homeUp && homeFav)
                self.show(NotchBanner(icon: "sportscourt.fill", title: "\(scorer) scores!", detail: line,
                                      tint: favScored ? .green : .red))
                self.party.react(favScored ? "\(scorer)! 🎉" : "Nooo 😢", happy: favScored)
            }
        }.store(in: &bag)
    }

    /// PS5 friends starting a game.
    private func watchFriends() {
        var last: [String: String?] = [:]
        var primed = false
        psn.$friends.sink { [weak self] friends in
            guard let self else { return }
            defer {
                for f in friends { last[f.id] = f.online ? f.game : nil }
                if !friends.isEmpty { primed = true }
            }
            guard primed, self.alertOn("alertFriends") else { return }
            for f in friends where f.online {
                guard let game = f.game, (last[f.id] ?? nil) != game else { continue }
                self.show(NotchBanner(icon: "playstation.logo", title: f.onlineID, detail: "playing \(game)", tint: .blue,
                                      image: f.avatar, detailImage: f.gameIcon))
            }
        }.store(in: &bag)
    }

    /// Big 24h moves and your price alerts.
    private func watchCoins() {
        var lastChange: [String: Double] = [:]
        crypto.$coins.sink { [weak self] coins in
            guard let self else { return }
            for coin in coins {
                let change = coin.price_change_percentage_24h ?? 0
                defer { lastChange[coin.id] = change }
                let symbol = coin.symbol.uppercased()
                if let prev = lastChange[coin.id], abs(prev) < 5, abs(change) >= 5, self.alertOn("alertCoinMoves") {
                    let up = change > 0
                    self.show(NotchBanner(icon: up ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis",
                                          title: "\(symbol) \(up ? "+" : "")\(String(format: "%.1f", change))%",
                                          detail: CryptoFormat.price(coin.current_price ?? 0), tint: up ? .green : .red))
                    self.party.react(up ? "📈 \(symbol) to the moon!" : "📉 \(symbol)…", happy: up)
                }
                guard let price = coin.current_price else { continue }
                for alert in PriceAlertStore.shared.alerts(for: coin.id)
                where (alert.above && price >= alert.target) || (!alert.above && price <= alert.target) {
                    PriceAlertStore.shared.remove(alert)
                    guard self.alertOn("alertPrices") else { continue }
                    self.show(NotchBanner(icon: "bell.fill",
                                          title: "\(alert.symbol) \(alert.above ? "above" : "below") \(CryptoFormat.price(alert.target))",
                                          detail: "now \(CryptoFormat.price(price))", tint: .yellow))
                }
            }
        }.store(in: &bag)
    }

    /// "Epic sunset tonight" heads-up, 45 minutes before golden hour starts.
    private func watchSunset() {
        var alerted: Set<Date> = []
        Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let show = self.weather.sunsetShow, !alerted.contains(show.time) {
                    let goldenHour = show.time.addingTimeInterval(-3600)
                    let minutes = goldenHour.timeIntervalSinceNow / 60
                    let goodEnough = !UserDefaults.standard.bool(forKey: "alertSunsetGoodOnly") || show.score >= 55
                    if minutes > 0 && minutes <= 45 {
                        alerted.insert(show.time)
                        if goodEnough && self.alertOn("alertSunset") {
                            self.show(NotchBanner(icon: "sun.horizon.fill", title: "Sunset \(show.score) · \(show.label)",
                                                  detail: "Golden hour in \(Int(minutes.rounded()))m", tint: show.color))
                            if show.score >= 75 { self.party.react("🌅 Go shoot!", happy: true) }
                        }
                    }
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    /// "Meeting in 5 min" heads-up.
    private func watchCalendar() {
        var alerted: Set<String> = []
        Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if let event = self.calendar.next, !alerted.contains(event.id) {
                    let minutes = event.start.timeIntervalSinceNow / 60
                    if minutes > 0 && minutes <= 5 {
                        alerted.insert(event.id)
                        if self.alertOn("alertCalendar") {
                            self.show(NotchBanner(icon: "calendar", title: "In \(Int(minutes.rounded(.up))) min",
                                                  detail: event.title, tint: event.color))
                        }
                    }
                }
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }
}
