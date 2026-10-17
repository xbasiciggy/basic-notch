import SwiftUI
import ImageIO

/// Weather, styled after the Cultiveq smart-farming concept: a misty landscape backdrop fading into
/// deep forest green, frosted green glass cards, an ultra-thin oversized temperature, glass pill chips
/// and a "Today's suggestions" list. The backdrop is a softly blurred photo that matches the weather and
/// the sun's real position, with rain and snow animated on top (see WeatherPhotoBackdrop), or optionally
/// one of your own landscape photos from Gallery Manager's Adventures albums, changing daily.
struct WeatherTab: View {
    @ObservedObject var weather: WeatherService
    @AppStorage("weatherCity") private var city = "New York"
    @AppStorage("useFahrenheit") private var fahrenheit = true
    @AppStorage("weatherPortfolioBackdrop") private var usePortfolioBackdrop = false
    @AppStorage("weatherUseCurrentLocation") private var useCurrentLocation = false
    @State private var backdrop: NSImage?

    private var today: WeatherDay? { weather.days.first }

    private var statusText: String {
        if !weather.failed { return useCurrentLocation ? "Finding your location…" : "Loading weather…" }
        if let reason = weather.failureReason { return reason }
        return useCurrentLocation ? "Couldn't get the weather for your location" : "Couldn't find \"\(city)\" — change the city in Settings"
    }

    var body: some View {
        ZStack {
            if let now = weather.now {
                HStack(alignment: .top, spacing: 12) {
                    hero(now)
                    conditionsCard(now)
                    VStack(spacing: 8) {
                        forecastStrip
                        suggestionsCard(now)
                    }
                }
                .padding(14)
            } else {
                VStack(spacing: 10) {
                    StatusMessage(icon: useCurrentLocation ? "location" : "cloud.sun", text: statusText)
                    if weather.failed && useCurrentLocation {
                        HStack {
                            Button("Location settings…") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
                            }
                            Button("Use \(city) instead") { useCurrentLocation = false }
                        }
                        .buttonStyle(PillButtonStyle())
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Purely decorative: the photo is drawn cropped, but its full size would otherwise
        // swallow clicks meant for the tab bar above it.
        .background { background.allowsHitTesting(false) }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.1)))
        .task(id: "\(city)|\(fahrenheit)|\(useCurrentLocation)") {
            try? await Task.sleep(for: .milliseconds(500))  // debounce typing in Settings
            if !Task.isCancelled { await weather.refresh() }
        }
        .task(id: "\(usePortfolioBackdrop)|\(Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0)") {
            backdrop = usePortfolioBackdrop ? await WeatherBackdrop.todaysPhoto() : nil
        }
    }

    // MARK: Background

    private var background: some View {
        ZStack {
            if let backdrop {
                GeometryReader { geo in
                    Image(nsImage: backdrop).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                }
                // Fade into forest green at the bottom and darken the left for the big temperature.
                LinearGradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: Forest.deep.opacity(0.55), location: 0.55),
                    .init(color: Forest.deep.opacity(0.95), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [Forest.deep.opacity(0.55), .clear], startPoint: .leading, endPoint: .center)
            } else {
                WeatherPhotoBackdrop(code: weather.now?.code ?? 0, isDay: weather.now?.isDay ?? true,
                                     sunrise: today?.sunrise, sunset: today?.sunset,
                                     wind: min((weather.now?.wind ?? 0) / (fahrenheit ? 20 : 32), 1.5))
                // Light shading, so a bright sky still reads as bright.
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.45),
                    .init(color: Forest.deep.opacity(0.6), location: 1),
                ], startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [.black.opacity(0.3), .clear], startPoint: .leading, endPoint: .center)
            }
        }
    }

    // MARK: Hero

    private func hero(_ now: WeatherNow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Label(weather.place.isEmpty ? city : weather.place,
                      systemImage: useCurrentLocation ? "location.fill" : "mappin.and.ellipse")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                LocationButton(isOn: useCurrentLocation, city: city) { useCurrentLocation.toggle() }
            }
            Spacer(minLength: 6)
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.abbreviated).year()))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(Int(now.temperature.rounded()))°")
                    .font(.system(size: 77, weight: .ultraLight))
                    .tracking(-2)
                Text(fahrenheit ? "F" : "C")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.vertical, -6)
            Text(WeatherCode.description(now.code))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(width: 190, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .leading)
    }

    // MARK: Conditions

    private func conditionsCard(_ now: WeatherNow) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: WeatherCode.symbol(now.code, isDay: now.isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 20))
                Text("\(WeatherCode.description(now.code)) · \(today?.rainChance ?? 0)% rain")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                HStack(spacing: 5) {
                    GlassPill(icon: "arrow.up", text: "\(Int((today?.high ?? now.temperature).rounded()))°")
                    GlassPill(icon: "arrow.down", text: "\(Int((today?.low ?? now.temperature).rounded()))°")
                }
                HStack(spacing: 5) {
                    GlassPill(icon: "humidity.fill", text: "\(Int(now.humidity))%")
                    GlassPill(icon: "wind", text: "\(Int(now.wind.rounded()))")
                }
                Spacer(minLength: 0)
                if let rise = today?.sunrise, let set = today?.sunset {
                    HStack(spacing: 8) {
                        Label(rise.formatted(date: .omitted, time: .shortened), systemImage: "sunrise.fill")
                        Label(set.formatted(date: .omitted, time: .shortened), systemImage: "sunset.fill")
                    }
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .labelStyle(TightLabel())
                }
            }
        }
        .frame(width: 168)
    }

    // MARK: Forecast

    private var forecastStrip: some View {
        HStack(spacing: 6) {
            ForEach(weather.days) { day in
                VStack(spacing: 3) {
                    Text(day.weekday).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                    Image(systemName: WeatherCode.symbol(day.code))
                        .symbolRenderingMode(.multicolor)
                        .font(.system(size: 14))
                        .frame(height: 16)
                    Text("\(Int(day.high.rounded()))° \(Int(day.low.rounded()))°")
                        .font(.system(size: 9, weight: .medium).monospacedDigit())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(GlassBackground(cornerRadius: 12))
            }
        }
    }

    // MARK: Suggestions

    private func suggestionsCard(_ now: WeatherNow) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Today's suggestions").font(.system(size: 11, weight: .semibold))
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Forest.lime)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                }
                ForEach(suggestions(now).prefix(2), id: \.title) { s in
                    SuggestionRow(icon: s.icon, title: s.title, detail: s.detail)
                }
            }
        }
    }

    private struct Suggestion {
        let icon: String
        let title: String
        let detail: String
    }

    /// Practical tips for the day — tuned for someone who shoots outdoors.
    private func suggestions(_ now: WeatherNow) -> [Suggestion] {
        var list: [Suggestion] = []
        let time = { (d: Date) in d.formatted(date: .omitted, time: .shortened) }
        // How colorful the next sunset or sunrise should be, from the cloud forecast.
        if let show = [weather.sunsetShow, weather.sunriseShow].compactMap({ $0 }).min(by: { $0.time < $1.time }) {
            let golden = show.isSunrise ? show.time : show.time.addingTimeInterval(-3600)
            let when = show.isSunrise ? "Sunrise \(time(show.time))" : (golden > Date() ? "Golden hour \(time(golden))" : "Golden hour now")
            list.append(Suggestion(icon: show.isSunrise ? "sunrise.fill" : "sun.horizon.fill",
                                   title: "\(show.isSunrise ? "Sunrise" : "Sunset") \(show.score) · \(show.label)",
                                   detail: "\(show.reason) · \(when)"))
        } else if let sunset = today?.sunset, sunset > Date() {
            let golden = sunset.addingTimeInterval(-3600)
            list.append(golden > Date()
                ? Suggestion(icon: "camera.aperture", title: "Golden hour \(time(golden))", detail: "Best light for shooting today")
                : Suggestion(icon: "camera.aperture", title: "Golden hour now", detail: "Sunset at \(time(sunset)) — get outside"))
        } else if let sunrise = weather.days.dropFirst().first?.sunrise {
            list.append(Suggestion(icon: "sunrise", title: "Sunrise \(time(sunrise))", detail: "Blue hour starts ~30 min before"))
        }
        let rain = today?.rainChance ?? 0
        if rain >= 50 {
            list.append(Suggestion(icon: "umbrella.fill", title: "Rain likely · \(rain)%", detail: "Pack a rain cover for the camera"))
        }
        if (today?.uvMax ?? 0) >= 6 {
            list.append(Suggestion(icon: "sun.max.fill", title: "High UV · \(Int(today?.uvMax ?? 0))", detail: "Sunscreen and a hat"))
        }
        let cold = fahrenheit ? now.feelsLike < 52 : now.feelsLike < 11
        if cold {
            list.append(Suggestion(icon: "thermometer.snowflake", title: "Feels like \(Int(now.feelsLike.rounded()))°", detail: "Grab a jacket"))
        }
        let windy = fahrenheit ? now.wind >= 18 : now.wind >= 29
        if windy {
            list.append(Suggestion(icon: "wind", title: "Windy · \(Int(now.wind.rounded())) \(fahrenheit ? "mph" : "km/h")", detail: "Weigh down the tripod"))
        }
        if list.count < 2 {
            list.append(rain < 20
                ? Suggestion(icon: "leaf.fill", title: "Clear skies ahead", detail: "Great day to be outside")
                : Suggestion(icon: "cloud.fill", title: "Soft, cloudy light", detail: "Nice for portraits"))
        }
        return list
    }
}

// MARK: - Style pieces

private enum Forest {
    static let deep = Color(red: 0.04, green: 0.14, blue: 0.08)
    static let glass = Color(red: 0.16, green: 0.34, blue: 0.2)
    static let lime = Color(red: 0.83, green: 0.95, blue: 0.4)
}

private struct GlassBackground: View {
    var cornerRadius: CGFloat = 16

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Forest.glass.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.28), .white.opacity(0.06)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1))
            .environment(\.colorScheme, .dark)
    }
}

private struct GlassCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(GlassBackground())
    }
}

private struct GlassPill: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 8, weight: .bold))
            Text(text).font(.system(size: 10, weight: .semibold).monospacedDigit())
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.12)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
    }
}

private struct SuggestionRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.14)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Text(detail).font(.system(size: 9)).foregroundStyle(.white.opacity(0.65)).lineLimit(1)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.system(size: 7, weight: .bold))
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.white.opacity(0.12)))
        }
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

private struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) { configuration.icon; configuration.title }
    }
}

/// Picks one of your landscape photos from Gallery Manager's Adventures albums (a new one each day).
enum WeatherBackdrop {
    private static var cache: (day: Int, image: NSImage)?

    @MainActor
    static func todaysPhoto() async -> NSImage? {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: Date()) ?? 0
        if let cache, cache.day == day { return cache.image }
        let image = await Task.detached(priority: .utility) { pick(day: day) }.value
        if let image { cache = (day, image) }
        return image
    }

    private static func pick(day: Int) -> NSImage? {
        struct Library: Decodable {
            struct G: Decodable { let title: String; let navigationItemID: UUID?; let photoPaths: [String]? }
            let galleries: [G]
        }
        let adventures = UUID(uuidString: "A11E0000-0000-4000-8000-000000000001")
        let skip = ["hospital", "abandoned", "map"]  // not landscape-y
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GalleryManager/library.json")
        guard let data = try? Data(contentsOf: url),
              let library = try? JSONDecoder().decode(Library.self, from: data) else { return nil }
        let photos = library.galleries
            .filter { g in g.navigationItemID == adventures && !skip.contains { g.title.lowercased().contains($0) } }
            .flatMap { $0.photoPaths ?? [] }
        guard !photos.isEmpty else { return nil }

        // Walk from today's pick until a wide photo with open sky at the top turns up.
        var generator = SeededGenerator(seed: UInt64(day))
        var fallback: CGImage?
        for _ in 0..<40 {
            let path = photos[Int(generator.next() % UInt64(photos.count))]
            guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 1600,
                  ] as CFDictionary),
                  Double(cg.width) > Double(cg.height) * 1.2 else { continue }
            if fallback == nil { fallback = cg }
            if looksLikeLandscape(cg) { return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)) }
        }
        return fallback.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
    }

    /// Bright, sky-like top third and a darker, more colorful bottom — a rough "outdoor landscape" test.
    private static func looksLikeLandscape(_ image: CGImage) -> Bool {
        let w = 24, h = 16
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        func stats(rows: Range<Int>) -> (luma: Double, sat: Double) {
            var luma = 0.0, sat = 0.0, n = 0.0
            for y in rows { for x in 0..<w {
                let i = (y * w + x) * 4
                let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
                let mx = max(r, g, b), mn = min(r, g, b)
                luma += 0.299 * r + 0.587 * g + 0.114 * b
                sat += mx > 0 ? (mx - mn) / mx : 0
                n += 1
            } }
            return (luma / n, sat / n)
        }
        // Memory row 0 is the top of the image.
        let top = stats(rows: 0..<(h / 3)), bottom = stats(rows: (h / 2)..<h)
        return top.luma > 0.5 && top.luma > bottom.luma + 0.08 && bottom.sat > 0.15
    }

    private struct SeededGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state >> 17
        }
    }
}

/// Small glass button beside the place name: switch between your current location and the saved city.
private struct LocationButton: View {
    let isOn: Bool
    let city: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isOn ? "location.fill" : "location")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isOn ? Color(red: 0.83, green: 0.95, blue: 0.4) : .white.opacity(0.85))
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.white.opacity(hovering || isOn ? 0.2 : 0.1)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(isOn ? "Using your current location — click to use \(city)" : "Use my current location")
    }
}
