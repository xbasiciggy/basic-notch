import SwiftUI

/// How colorful a sunset (or sunrise) is likely to be, from 0 to 100.
///
/// The best skies have high, thin clouds (and some mid-level ones) to catch the light after the sun
/// drops, with a clear horizon so the light can reach them. Low clouds block that light, rain dulls
/// everything, and a totally clear sky is pleasant but plain.
struct SkyShowScore: Equatable {
    let score: Int
    let time: Date
    let isSunrise: Bool
    let high: Int
    let mid: Int
    let low: Int

    init(time: Date, isSunrise: Bool, high: Int, mid: Int, low: Int, rainChance: Int) {
        self.time = time
        self.isSunrise = isSunrise
        self.high = high
        self.mid = mid
        self.low = low

        func bell(_ value: Int, peak: Double, width: Double) -> Double {
            max(0, 1 - abs(Double(value) - peak) / width)
        }
        var s = 30.0
        s += 38 * bell(high, peak: 50, width: 50)  // high cirrus: the canvas for color
        s += 24 * bell(mid, peak: 35, width: 40)   // some mid clouds add drama
        s -= 0.55 * Double(low)                    // low clouds block the light
        s -= 0.25 * Double(rainChance)
        if high + mid < 10 { s = min(s, 40) }      // clear sky: nice light, little color
        score = Int(min(max(s, 0), 100).rounded())
    }

    var label: String {
        switch score {
        case 75...: "Epic burn"
        case 55..<75: "Good color"
        case 30..<55: "Decent"
        default: "Dull"
        }
    }

    var color: Color {
        switch score {
        case 75...: Color(red: 1, green: 0.42, blue: 0.24)
        case 55..<75: Color(red: 1, green: 0.62, blue: 0.3)
        case 30..<55: Color(red: 0.95, green: 0.8, blue: 0.5)
        default: Color(white: 0.7)
        }
    }

    /// One short reason, e.g. "High clouds 55% · clear horizon".
    var reason: String {
        if low >= 60 { return "Low clouds \(low)% may block it" }
        if high + mid < 10 { return "Clear sky · soft, simple light" }
        let canvas = high >= mid ? "High clouds \(high)%" : "Mid clouds \(mid)%"
        return low < 25 ? "\(canvas) · clear horizon" : "\(canvas) · some low cloud"
    }

    /// Picks the cloud cover at the hour closest to `time` from Open-Meteo's hourly forecast.
    static func make(at time: Date?, isSunrise: Bool, hours: [Date], high: [Int?], mid: [Int?], low: [Int?], rain: [Int?]) -> SkyShowScore? {
        guard let time, !hours.isEmpty,
              let i = hours.indices.min(by: { abs(hours[$0].timeIntervalSince(time)) < abs(hours[$1].timeIntervalSince(time)) }),
              abs(hours[i].timeIntervalSince(time)) < 2 * 3600 else { return nil }
        func at(_ list: [Int?]) -> Int { i < list.count ? (list[i] ?? 0) : 0 }
        return SkyShowScore(time: time, isSunrise: isSunrise, high: at(high), mid: at(mid), low: at(low), rainChance: at(rain))
    }
}
