import SwiftUI

enum ChartRange: String, CaseIterable, Identifiable {
    case h1 = "1H", d1 = "1D", d7 = "7D", m1 = "1M", m3 = "3M", m6 = "6M", all = "ALL"

    var id: Self { self }

    /// CoinGecko `days` parameter.
    var days: String {
        switch self {
        case .h1, .d1: "1"
        case .d7: "7"
        case .m1: "30"
        case .m3: "90"
        case .m6: "180"
        case .all: "max"
        }
    }

    var label: String { self == .all ? "all time" : rawValue.lowercased() }
}

struct ChartPoint: Identifiable {
    let date: Date
    let value: Double
    var id: Date { date }
}

struct Candle: Identifiable {
    let date: Date
    let open: Double
    let high: Double
    let low: Double
    let close: Double
    var id: Date { date }
    var isUp: Bool { close >= open }
}

private struct MarketChartResponse: Decodable {
    let prices: [[Double]]
    let market_caps: [[Double]]
}

@MainActor
final class CoinDetailModel: ObservableObject {
    let coinID: String

    @Published private(set) var coin: Coin?
    @Published var range: ChartRange = .d1 {
        didSet { Task { await loadChart() } }
    }
    @Published var showMarketCap = false
    @Published var candles = false {
        didSet { if candles { Task { await loadCandles() } } }
    }
    @Published var expanded = false
    @Published var hover: ChartPoint?
    @Published private(set) var prices: [ChartPoint] = []
    @Published private(set) var caps: [ChartPoint] = []
    @Published private(set) var ohlc: [Candle] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    private var chartCache: [String: (fetched: Date, prices: [ChartPoint], caps: [ChartPoint])] = [:]
    private var loop: Task<Void, Never>?

    init(coinID: String) {
        self.coinID = coinID
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.loadInfo()
                await self?.loadChart()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stop() { loop?.cancel() }

    // MARK: Derived values

    var series: [ChartPoint] { showMarketCap ? caps : prices }

    var currentValue: Double {
        if showMarketCap { return coin?.market_cap ?? caps.last?.value ?? 0 }
        return coin?.current_price ?? prices.last?.value ?? 0
    }

    var alternateValue: Double {
        showMarketCap ? (coin?.current_price ?? prices.last?.value ?? 0) : (coin?.market_cap ?? caps.last?.value ?? 0)
    }

    /// Change across the selected range (or up to the hovered point).
    var change: (amount: Double, percent: Double) {
        guard let first = series.first?.value, first != 0 else { return (0, 0) }
        let end = hover?.value ?? series.last?.value ?? first
        return (end - first, (end - first) / first * 100)
    }

    var isUp: Bool { change.amount >= 0 }

    func format(_ value: Double) -> String {
        showMarketCap ? CryptoFormat.compact(value) : CryptoFormat.price(value)
    }

    func nearestPoint(to date: Date) -> ChartPoint? {
        let s = series
        guard !s.isEmpty else { return nil }
        // Binary search: series is sorted by date.
        var lo = 0, hi = s.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if s[mid].date < date { lo = mid + 1 } else { hi = mid }
        }
        if lo > 0, abs(s[lo - 1].date.timeIntervalSince(date)) < abs(s[lo].date.timeIntervalSince(date)) {
            return s[lo - 1]
        }
        return s[lo]
    }

    // MARK: Loading

    func loadInfo() async {
        guard let url = URL(string: "https://api.coingecko.com/api/v3/coins/markets?vs_currency=usd&ids=\(coinID)"),
              let result = try? await Net.get([Coin].self, from: url),
              let first = result.first else { return }
        coin = first
    }

    func loadChart() async {
        let range = self.range
        let key = range.days
        if let cached = chartCache[key], Date().timeIntervalSince(cached.fetched) < 60 {
            apply(cached.prices, cached.caps, for: range)
            return
        }
        guard let url = URL(string: "https://api.coingecko.com/api/v3/coins/\(coinID)/market_chart?vs_currency=usd&days=\(key)") else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await Net.get(MarketChartResponse.self, from: url)
            let toPoints: ([[Double]]) -> [ChartPoint] = { rows in
                rows.compactMap { row in
                    row.count >= 2 ? ChartPoint(date: Date(timeIntervalSince1970: row[0] / 1000), value: row[1]) : nil
                }
            }
            let p = toPoints(response.prices), c = toPoints(response.market_caps)
            chartCache[key] = (Date(), p, c)
            guard self.range.days == key else { return }
            apply(p, c, for: self.range)
            error = nil
        } catch {
            self.error = "CoinGecko is rate limiting — try again in a minute"
        }
        if candles { await loadCandles() }
    }

    func loadCandles() async {
        let range = self.range
        guard let url = URL(string: "https://api.coingecko.com/api/v3/coins/\(coinID)/ohlc?vs_currency=usd&days=\(range.days)"),
              let rows = try? await Net.get([[Double]].self, from: url) else { return }
        var result = rows.compactMap { r in
            r.count >= 5 ? Candle(date: Date(timeIntervalSince1970: r[0] / 1000), open: r[1], high: r[2], low: r[3], close: r[4]) : nil
        }
        if range == .h1 { result = result.filter { $0.date > Date().addingTimeInterval(-3600) } }
        guard self.range == range else { return }
        ohlc = result
    }

    private func apply(_ p: [ChartPoint], _ c: [ChartPoint], for range: ChartRange) {
        if range == .h1 {
            let cutoff = Date().addingTimeInterval(-3600)
            prices = p.filter { $0.date > cutoff }
            caps = c.filter { $0.date > cutoff }
        } else {
            prices = p
            caps = c
        }
        hover = nil
    }
}
