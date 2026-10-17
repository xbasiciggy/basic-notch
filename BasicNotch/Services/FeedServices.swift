import Foundation
import SwiftUI

enum Net {
    static func get<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("BasicNotch/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Sports (ESPN public scoreboard)

enum League: String, CaseIterable, Identifiable {
    case nfl, nba, mlb, nhl, cfb, wnba, epl, mls

    var id: Self { self }
    var title: String {
        switch self {
        case .nfl: "NFL"
        case .nba: "NBA"
        case .mlb: "MLB"
        case .nhl: "NHL"
        case .cfb: "NCAAF"
        case .wnba: "WNBA"
        case .epl: "Premier League"
        case .mls: "MLS"
        }
    }
    var path: String {
        switch self {
        case .nfl: "football/nfl"
        case .nba: "basketball/nba"
        case .mlb: "baseball/mlb"
        case .nhl: "hockey/nhl"
        case .cfb: "football/college-football"
        case .wnba: "basketball/wnba"
        case .epl: "soccer/eng.1"
        case .mls: "soccer/usa.1"
        }
    }
}

struct Game: Identifiable {
    struct Side {
        let abbr: String
        let name: String
        let score: String
        let logo: URL?
    }

    let id: String
    let away: Side
    let home: Side
    let detail: String
    let state: String  // "pre", "in", "post"

    var isLive: Bool { state == "in" }
}

private struct ESPNScoreboard: Decodable {
    struct Event: Decodable {
        let id: String
        let competitions: [Competition]
        let status: Status?
    }
    struct Competition: Decodable {
        let competitors: [Competitor]
        let status: Status?
    }
    struct Competitor: Decodable {
        let homeAway: String
        let score: String?
        let team: Team
    }
    struct Team: Decodable {
        let abbreviation: String?
        let displayName: String?
        let shortDisplayName: String?
        let logo: String?
    }
    struct Status: Decodable {
        let type: StatusType
    }
    struct StatusType: Decodable {
        let state: String?
        let shortDetail: String?
    }

    let events: [Event]
}

@MainActor
final class SportsService: ObservableObject {
    @Published private(set) var games: [Game] = []
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false
    private var loop: Task<Void, Never>?

    func start() {
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func refresh() async {
        let league = League(rawValue: UserDefaults.standard.string(forKey: "league") ?? "") ?? .nfl
        guard let url = URL(string: "https://site.api.espn.com/apis/site/v2/sports/\(league.path)/scoreboard") else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let board = try await Net.get(ESPNScoreboard.self, from: url)
            guard UserDefaults.standard.string(forKey: "league") == league.rawValue else { return }
            games = board.events.compactMap { event in
                guard let comp = event.competitions.first,
                      let home = comp.competitors.first(where: { $0.homeAway == "home" }),
                      let away = comp.competitors.first(where: { $0.homeAway == "away" }) else { return nil }
                let status = comp.status ?? event.status
                func side(_ c: ESPNScoreboard.Competitor) -> Game.Side {
                    Game.Side(abbr: c.team.abbreviation ?? "—",
                              name: c.team.shortDisplayName ?? c.team.displayName ?? "",
                              score: c.score ?? "",
                              logo: c.team.logo.flatMap(URL.init(string:)))
                }
                return Game(id: event.id, away: side(away), home: side(home),
                            detail: status?.type.shortDetail ?? "",
                            state: status?.type.state ?? "pre")
            }
            failed = false
        } catch {
            failed = true
        }
    }
}

// MARK: - Crypto (CoinGecko)

struct Coin: Decodable, Identifiable {
    struct Sparkline: Decodable { let price: [Double] }

    let id: String
    let symbol: String
    let name: String
    let image: String
    let current_price: Double?
    let market_cap: Double?
    let price_change_percentage_24h: Double?
    let sparkline_in_7d: Sparkline?
}

struct CoinSearchResult: Decodable, Identifiable {
    let id: String
    let name: String
    let symbol: String
    let thumb: String?
    let market_cap_rank: Int?
}

private struct CoinSearchResponse: Decodable {
    let coins: [CoinSearchResult]
}

@MainActor
final class CryptoService: ObservableObject {
    @Published private(set) var coins: [Coin] = []
    @Published private(set) var updated: Date?
    @Published private(set) var failed = false
    /// While the coin search field is up, the notch stays open so you can type.
    @Published var isSearching = false
    @Published private(set) var searchResults: [CoinSearchResult] = []

    func search(_ query: String) async {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { searchResults = []; return }
        var components = URLComponents(string: "https://api.coingecko.com/api/v3/search")!
        components.queryItems = [URLQueryItem(name: "query", value: query)]
        guard let url = components.url,
              let response = try? await Net.get(CoinSearchResponse.self, from: url) else { return }
        searchResults = Array(response.coins.prefix(8))
    }
    private var loop: Task<Void, Never>?

    func start() {
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(90))
            }
        }
    }

    func refresh() async {
        let ids = (UserDefaults.standard.string(forKey: "cryptoCoins") ?? "")
            .lowercased()
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !ids.isEmpty else { coins = []; return }
        var components = URLComponents(string: "https://api.coingecko.com/api/v3/coins/markets")!
        components.queryItems = [
            URLQueryItem(name: "vs_currency", value: "usd"),
            URLQueryItem(name: "ids", value: ids.joined(separator: ",")),
            URLQueryItem(name: "sparkline", value: "true"),
        ]
        guard let url = components.url else { return }
        do {
            let result = try await Net.get([Coin].self, from: url)
            // Keep the user's order.
            coins = ids.compactMap { id in result.first { $0.id == id } }
            updated = Date()
            failed = false
        } catch {
            failed = true
        }
    }
}

// MARK: - Weather (Open-Meteo, no API key)

struct WeatherNow {
    let temperature: Double
    let feelsLike: Double
    let humidity: Double
    let wind: Double
    let code: Int
    let isDay: Bool
}

struct WeatherDay: Identifiable {
    let id: String
    let weekday: String
    let code: Int
    let high: Double
    let low: Double
    var rainChance: Int = 0
    var sunrise: Date?
    var sunset: Date?
    var uvMax: Double = 0
}

enum WeatherCode {
    static func symbol(_ code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61, 63, 66, 80, 81: "cloud.rain.fill"
        case 65, 67, 82: "cloud.heavyrain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    static func description(_ code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1: "Mostly clear"
        case 2: "Partly cloudy"
        case 3: "Overcast"
        case 45, 48: "Fog"
        case 51...57: "Drizzle"
        case 61...67: "Rain"
        case 71...77: "Snow"
        case 80...82: "Showers"
        case 85, 86: "Snow showers"
        case 95...99: "Thunderstorms"
        default: "—"
        }
    }
}

private struct GeocodeResponse: Decodable {
    struct Place: Decodable {
        let name: String
        let latitude: Double
        let longitude: Double
        let admin1: String?
        let country_code: String?
    }
    let results: [Place]?
}

private struct ForecastResponse: Decodable {
    struct Current: Decodable {
        let temperature_2m: Double
        let apparent_temperature: Double
        let relative_humidity_2m: Double
        let weather_code: Int
        let wind_speed_10m: Double
        let is_day: Int
    }
    struct Daily: Decodable {
        let time: [String]
        let weather_code: [Int]
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
        let precipitation_probability_max: [Int?]?
        let sunrise: [String]?
        let sunset: [String]?
        let uv_index_max: [Double?]?
    }
    struct Hourly: Decodable {
        let time: [String]
        let cloud_cover_low: [Int?]?
        let cloud_cover_mid: [Int?]?
        let cloud_cover_high: [Int?]?
        let precipitation_probability: [Int?]?
    }
    let utc_offset_seconds: Int?
    let current: Current
    let daily: Daily
    let hourly: Hourly?
}

@MainActor
final class WeatherService: ObservableObject {
    @Published private(set) var place = ""
    @Published private(set) var now: WeatherNow?
    @Published private(set) var days: [WeatherDay] = []
    @Published private(set) var failed = false
    /// Why the last refresh failed, when there's something useful to say (e.g. location denied).
    @Published private(set) var failureReason: String?
    /// How colorful the next sunset and sunrise should be.
    @Published private(set) var sunsetShow: SkyShowScore?
    @Published private(set) var sunriseShow: SkyShowScore?
    private var geocodeCache: [String: GeocodeResponse.Place] = [:]
    private var loop: Task<Void, Never>?

    func start() {
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(60 * 15))
            }
        }
    }

    func refresh() async {
        let city = (UserDefaults.standard.string(forKey: "weatherCity") ?? "").trimmingCharacters(in: .whitespaces)
        let fahrenheit = UserDefaults.standard.bool(forKey: "useFahrenheit")
        let useCurrentLocation = UserDefaults.standard.bool(forKey: "weatherUseCurrentLocation")
        guard useCurrentLocation || !city.isEmpty else { return }
        do {
            // Where: your Mac's current location, or the city from Settings.
            let latitude: Double, longitude: Double, placeName: String
            if useCurrentLocation {
                let fix = try await CurrentLocation.shared.fix()
                (latitude, longitude, placeName) = (fix.latitude, fix.longitude, fix.name)
            } else {
                let match: GeocodeResponse.Place
                if let cached = geocodeCache[city] {
                    match = cached
                } else {
                    var geo = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
                    geo.queryItems = [URLQueryItem(name: "name", value: city), URLQueryItem(name: "count", value: "1")]
                    guard let first = try await Net.get(GeocodeResponse.self, from: geo.url!).results?.first else {
                        failed = true
                        failureReason = nil
                        return
                    }
                    geocodeCache[city] = first
                    match = first
                }
                (latitude, longitude) = (match.latitude, match.longitude)
                placeName = [match.name, match.admin1].compactMap { $0 }.joined(separator: ", ")
            }

            var forecast = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            forecast.queryItems = [
                URLQueryItem(name: "latitude", value: String(latitude)),
                URLQueryItem(name: "longitude", value: String(longitude)),
                URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day"),
                URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset,uv_index_max"),
                URLQueryItem(name: "hourly", value: "cloud_cover_low,cloud_cover_mid,cloud_cover_high,precipitation_probability"),
                URLQueryItem(name: "temperature_unit", value: fahrenheit ? "fahrenheit" : "celsius"),
                URLQueryItem(name: "wind_speed_unit", value: fahrenheit ? "mph" : "kmh"),
                URLQueryItem(name: "timezone", value: "auto"),
                URLQueryItem(name: "forecast_days", value: "5"),
            ]
            let response = try await Net.get(ForecastResponse.self, from: forecast.url!)
            let c = response.current
            now = WeatherNow(temperature: c.temperature_2m, feelsLike: c.apparent_temperature,
                             humidity: c.relative_humidity_2m, wind: c.wind_speed_10m,
                             code: c.weather_code, isDay: c.is_day == 1)

            let parser = DateFormatter()
            parser.dateFormat = "yyyy-MM-dd"
            let dayName = DateFormatter()
            dayName.dateFormat = "EEE"
            let d = response.daily
            // Sunrise/sunset come back as local wall-clock times for the forecast location.
            let local = DateFormatter()
            local.dateFormat = "yyyy-MM-dd'T'HH:mm"
            local.timeZone = TimeZone(secondsFromGMT: response.utc_offset_seconds ?? 0)
            func at<T>(_ list: [T]?, _ i: Int) -> T? { list.flatMap { i < $0.count ? $0[i] : nil } }
            days = d.time.indices.map { i in
                let label = i == 0 ? "Today" : parser.date(from: d.time[i]).map(dayName.string(from:)) ?? d.time[i]
                return WeatherDay(id: d.time[i], weekday: label, code: d.weather_code[i],
                                  high: d.temperature_2m_max[i], low: d.temperature_2m_min[i],
                                  rainChance: (at(d.precipitation_probability_max, i) ?? nil) ?? 0,
                                  sunrise: at(d.sunrise, i).flatMap(local.date(from:)),
                                  sunset: at(d.sunset, i).flatMap(local.date(from:)),
                                  uvMax: (at(d.uv_index_max, i) ?? nil) ?? 0)
            }
            if let hourly = response.hourly {
                let hours = hourly.time.map { local.date(from: $0) ?? .distantPast }
                let now = Date()
                let nextSunset = days.compactMap(\.sunset).first { $0 > now.addingTimeInterval(-30 * 60) }
                let nextSunrise = days.compactMap(\.sunrise).first { $0 > now.addingTimeInterval(-30 * 60) }
                func show(_ time: Date?, sunrise: Bool) -> SkyShowScore? {
                    SkyShowScore.make(at: time, isSunrise: sunrise, hours: hours, high: hourly.cloud_cover_high ?? [],
                                      mid: hourly.cloud_cover_mid ?? [], low: hourly.cloud_cover_low ?? [],
                                      rain: hourly.precipitation_probability ?? [])
                }
                sunsetShow = show(nextSunset, sunrise: false)
                sunriseShow = show(nextSunrise, sunrise: true)
            }
            place = placeName
            failed = false
            failureReason = nil
        } catch {
            failed = true
            failureReason = (error as? CurrentLocation.Failure)?.errorDescription
        }
    }
}
