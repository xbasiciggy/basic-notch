import SwiftUI
import AppKit

/// A live, drawn sky for the weather tab that matches the current conditions and where the sun
/// actually is: bright blue with the sun high on a clear day, warm and low in the hour around
/// sunset, blue hour just after, stars and the moon at night. Clouds drift; rain, snow and fog move.
struct WeatherScene: View {
    let code: Int
    let isDay: Bool
    let sunrise: Date?
    let sunset: Date?
    /// 0 = still air, 1 = windy, up to 1.5 = very windy. Speeds up clouds, tilts rain, sways trees.
    var wind: Double = 0.3
    /// Draw only the moving weather (rain, snow, lightning, fog, shooting stars) to lay over a photo.
    var overlayOnly = false

    private var sky: SkyKind { SkyKind(code: code) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            Canvas { ctx, size in
                let phase = DayPhase(now: context.date, isDay: isDay, sunrise: sunrise, sunset: sunset)
                let t = context.date.timeIntervalSinceReferenceDate
                if overlayOnly {
                    drawWeatherOverlay(ctx, size, phase, t)
                    return
                }
                drawSky(ctx, size, phase)
                if phase == .night && sky.showsStars {
                    drawStars(ctx, size, t)
                    drawShootingStar(ctx, size, t)
                }
                drawSunOrMoon(ctx, size, phase, now: context.date, t: t)
                drawClouds(ctx, size, phase, t, far: true)
                if sky.showsStars && (phase == .day || phase == .golden) { drawBirds(ctx, size, phase, t) }
                drawClouds(ctx, size, phase, t, far: false)
                drawHills(ctx, size, phase)
                drawTrees(ctx, size, phase, t)
                if sky == .fog { drawFog(ctx, size, phase, t) }
                switch sky {
                case .rain: drawRain(ctx, size, t, heavy: false)
                case .storm: drawRain(ctx, size, t, heavy: true); drawLightning(ctx, size, t)
                case .snow: drawSnow(ctx, size, t)
                default: break
                }
            }
        }
    }

    private func drawWeatherOverlay(_ ctx: GraphicsContext, _ size: CGSize, _ phase: DayPhase, _ t: Double) {
        if phase == .night && sky.showsStars { drawShootingStar(ctx, size, t) }
        switch sky {
        case .fog: drawFog(ctx, size, phase, t)
        case .rain: drawRain(ctx, size, t, heavy: false)
        case .storm: drawRain(ctx, size, t, heavy: true); drawLightning(ctx, size, t)
        case .snow: drawSnow(ctx, size, t)
        default: break
        }
    }

    // MARK: Sky

    private func drawSky(_ ctx: GraphicsContext, _ size: CGSize, _ phase: DayPhase) {
        let base = phase.skyStops
        let (target, amount) = sky.mute(for: phase)
        let colors = base.map { mix($0, target, amount).color }
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: colors), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height * 0.75)))
    }

    private func drawStars(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double) {
        var rng = Seeded(7)
        for _ in 0..<70 {
            let x = rng.unit() * size.width, y = rng.unit() * size.height * 0.6
            let r = 0.5 + rng.unit() * 1.1
            let twinkle = 0.35 + 0.65 * abs(sin(t * (0.6 + rng.unit() * 1.4) + rng.unit() * 6))
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                     with: .color(.white.opacity(twinkle * 0.9)))
        }
    }

    /// A streak across the sky every ~11 seconds, somewhere new each time.
    private func drawShootingStar(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double) {
        let period = 11.0, duration = 0.9
        let cycle = t.truncatingRemainder(dividingBy: period)
        guard cycle < duration else { return }
        var rng = Seeded(UInt64(t / period))
        let start = CGPoint(x: size.width * (0.35 + rng.unit() * 0.6), y: size.height * (0.05 + rng.unit() * 0.2))
        let p = cycle / duration
        let travel = 160.0
        let head = CGPoint(x: start.x - travel * p, y: start.y + travel * 0.45 * p)
        let tail = CGPoint(x: head.x + 60, y: head.y - 27)
        var path = Path()
        path.move(to: tail)
        path.addLine(to: head)
        let fade = sin(p * .pi)
        ctx.stroke(path, with: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.9 * fade)]), startPoint: tail, endPoint: head),
                   style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
    }

    // MARK: Sun and moon

    private func drawSunOrMoon(_ ctx: GraphicsContext, _ size: CGSize, _ phase: DayPhase, now: Date, t: Double) {
        let w = size.width, h = size.height
        let visible = sky.sunVisibility  // 1 = clear, 0 = fully hidden by clouds
        let breathe = 1 + 0.06 * sin(t * 0.8)

        if phase == .night {
            guard visible > 0.2 else { return }
            let c = CGPoint(x: w * 0.8, y: h * 0.2), r = 14.0
            glow(ctx, at: c, radius: 70 * breathe, color: Color(white: 0.9).opacity(0.2 * visible))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                     with: .color(Color(red: 0.95, green: 0.94, blue: 0.86).opacity(visible)))
            for (dx, dy, cr) in [(-4.0, -3.0, 3.0), (5.0, 4.0, 2.2), (-2.0, 6.0, 1.6)] {
                ctx.fill(Path(ellipseIn: CGRect(x: c.x + dx - cr, y: c.y + dy - cr, width: cr * 2, height: cr * 2)),
                         with: .color(Color(red: 0.8, green: 0.79, blue: 0.72).opacity(0.6 * visible)))
            }
            return
        }

        // Follow the real arc: rises on the left at sunrise, highest at midday, sets on the right.
        let progress: Double
        if let sunrise, let sunset, sunset > sunrise {
            progress = now.timeIntervalSince(sunrise) / sunset.timeIntervalSince(sunrise)
        } else {
            progress = 0.5
        }
        let p = min(max(progress, -0.08), 1.08)
        let horizon = h * 0.7
        let c = CGPoint(x: w * (0.12 + 0.76 * p), y: horizon - sin(min(max(p, 0), 1) * .pi) * h * 0.55 + (p < 0 || p > 1 ? 14 : 0))
        let low = phase == .golden || phase == .blueHour
        let core = low ? Color(red: 1, green: 0.72, blue: 0.38) : Color(red: 1, green: 0.97, blue: 0.84)
        let halo = low ? Color(red: 1, green: 0.5, blue: 0.25) : Color(red: 1, green: 0.92, blue: 0.6)

        glow(ctx, at: c, radius: (low ? 170 : 130) * breathe, color: halo.opacity((low ? 0.55 : 0.45) * max(visible, 0.25)))
        guard visible > 0.15, phase != .blueHour else { return }

        // Slowly turning rays.
        ctx.drawLayer { layer in
            layer.translateBy(x: c.x, y: c.y)
            layer.rotate(by: .radians(t * 0.05))
            layer.addFilter(.blur(radius: 3))
            let rays = 12, length = (low ? 150.0 : 120.0) * breathe
            for i in 0..<rays {
                let a = Double(i) / Double(rays) * 2 * .pi
                let spread = 0.07 + 0.03 * sin(t * 0.6 + Double(i))
                var ray = Path()
                ray.move(to: .zero)
                ray.addLine(to: CGPoint(x: cos(a - spread) * length, y: sin(a - spread) * length))
                ray.addLine(to: CGPoint(x: cos(a + spread) * length, y: sin(a + spread) * length))
                ray.closeSubpath()
                layer.fill(ray, with: .radialGradient(Gradient(colors: [halo.opacity(0.28 * visible), .clear]),
                                                      center: .zero, startRadius: 10, endRadius: length))
            }
        }

        let r = (low ? 20.0 : 16.0) * (1 + 0.02 * sin(t * 1.3))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                 with: .color(core.opacity(visible)))

        // Lens flare: a few faint rings along the line from the sun through the middle.
        guard sky == .clear else { return }
        let mid = CGPoint(x: w / 2, y: h / 2)
        for (k, (along, fr, alpha)) in [(0.6, 8.0, 0.12), (1.1, 14.0, 0.08), (1.45, 5.0, 0.14), (1.8, 22.0, 0.06)].enumerated() {
            let shimmer = 1 + 0.15 * sin(t * 0.7 + Double(k))
            let fc = CGPoint(x: c.x + (mid.x - c.x) * along, y: c.y + (mid.y - c.y) * along)
            ctx.fill(Path(ellipseIn: CGRect(x: fc.x - fr, y: fc.y - fr, width: fr * 2, height: fr * 2)),
                     with: .color(halo.opacity(alpha * shimmer)))
        }
    }

    private func glow(_ ctx: GraphicsContext, at c: CGPoint, radius: CGFloat, color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)),
                 with: .radialGradient(Gradient(colors: [color, .clear]), center: c, startRadius: 0, endRadius: radius))
    }

    // MARK: Clouds, fog and birds

    /// Two depths: small, faint, slow clouds far away and bigger, faster ones up close.
    private func drawClouds(_ ctx: GraphicsContext, _ size: CGSize, _ phase: DayPhase, _ t: Double, far: Bool) {
        let total = sky.cloudCount
        let count = far ? total / 2 : total - total / 2
        guard count > 0 else { return }
        let w = size.width, h = size.height
        let tint = sky.cloudColor(for: phase)
        let depth = far ? 0.55 : 1.0
        let windSpeed = 0.5 + wind
        var rng = Seeded(far ? 91 : 42)
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: far ? 9 : 6))
            layer.opacity = far ? 0.7 : 1
            for i in 0..<count {
                let scale = (0.7 + rng.unit() * 0.7) * depth
                let cw = w * 0.24 * scale, ch = cw * 0.38
                let speed = (5 + rng.unit() * 7) * depth * windSpeed
                let span = w + cw * 2
                let x = (rng.unit() * span + t * speed).truncatingRemainder(dividingBy: span) - cw
                let y = h * (sky.cloudTop + rng.unit() * sky.cloudSpread) + (far ? 0 : 10) + sin(t * 0.2 + Double(i)) * 2
                let puffs: [(Double, Double, Double)] = [(0, 0.35, 0.6), (0.22, 0.05, 0.75), (0.5, 0.15, 0.7), (0.72, 0.4, 0.55)]
                for (k, (px, py, ps)) in puffs.enumerated() {
                    // Each puff slowly swells and shrinks, so clouds change shape as they drift.
                    let billow = 1 + 0.07 * sin(t * 0.35 + Double(i * 4 + k))
                    let pw = cw * ps * billow, ph = ch * ps * 1.6 * billow
                    layer.fill(Path(ellipseIn: CGRect(x: x + cw * px, y: y + ch * py - ph / 2, width: pw, height: ph)),
                               with: .color(tint))
                }
            }
        }
    }

    private func drawFog(_ ctx: GraphicsContext, _ size: CGSize, _ phase: DayPhase, _ t: Double) {
        let w = size.width, h = size.height
        let color = phase == .night ? Color(white: 0.5) : Color(white: 0.95)
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: 14))
            for i in 0..<5 {
                let y = h * (0.3 + Double(i) * 0.11) + sin(t * 0.15 + Double(i)) * 4
                let x = sin(t * 0.08 + Double(i) * 1.7) * w * 0.12 - w * 0.12
                layer.fill(Path(roundedRect: CGRect(x: x, y: y, width: w * 1.25, height: h * 0.12), cornerRadius: 24),
                           with: .color(color.opacity(0.5 + 0.12 * sin(t * 0.3 + Double(i)))))
            }
        }
    }

    /// A small flock that flaps across the sky every ~26 seconds.
    private func drawBirds(_ ctx: GraphicsContext, _ size: CGSize, _ phase: DayPhase, _ t: Double) {
        let period = 26.0, flight = 13.0
        let cycle = t.truncatingRemainder(dividingBy: period)
        guard cycle < flight else { return }
        let p = cycle / flight
        let w = size.width, h = size.height
        var rng = Seeded(UInt64(t / period) &+ 17)
        let leftToRight = rng.unit() > 0.5
        let lead = CGPoint(x: leftToRight ? -40 + (w + 80) * p : w + 40 - (w + 80) * p,
                           y: h * (0.18 + rng.unit() * 0.15) + sin(p * .pi * 3) * 8)
        let color = phase == .golden ? Color(red: 0.2, green: 0.12, blue: 0.1) : Color(red: 0.12, green: 0.16, blue: 0.24)
        let offsets: [(Double, Double)] = [(0, 0), (-14, 7), (-14, -7), (-27, 13), (-25, -12)]
        var path = Path()
        for (k, (dx, dy)) in offsets.enumerated() {
            let c = CGPoint(x: lead.x + (leftToRight ? dx : -dx), y: lead.y + dy)
            let flap = sin(t * 9 + Double(k) * 1.3) * 3
            let span = 5.0
            path.move(to: CGPoint(x: c.x - span, y: c.y - flap))
            path.addQuadCurve(to: c, control: CGPoint(x: c.x - span / 2, y: c.y - flap - 2))
            path.addQuadCurve(to: CGPoint(x: c.x + span, y: c.y - flap), control: CGPoint(x: c.x + span / 2, y: c.y - flap - 2))
        }
        ctx.stroke(path, with: .color(color.opacity(0.75)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
    }

    // MARK: Ground

    private static let hillLayers: [(base: Double, amp: Double, phase: Double)] = [(0.6, 0.07, 0.3), (0.7, 0.06, 1.4), (0.8, 0.05, 2.2)]

    private func hillY(_ x: Double, _ size: CGSize, layer i: Int) -> Double {
        let l = Self.hillLayers[i], w = size.width
        return size.height * (l.base + l.amp * sin(x / w * .pi * 2.2 + l.phase) + l.amp * 0.4 * sin(x / w * .pi * 5 + l.phase * 2))
    }

    private func hillColor(_ i: Int, _ phase: DayPhase) -> RGB {
        let color = phase.hillColors[i]
        let night = phase == .night
        switch sky {
        case .snow: return mix(color, RGB(0.9, 0.92, 0.95), night ? 0.35 : 0.75)
        case .fog: return mix(color, night ? RGB(0.2, 0.21, 0.23) : RGB(0.72, 0.75, 0.76), 0.35 + Double(2 - i) * 0.15)
        case .overcast, .rain: return mix(color, RGB(0.18, 0.22, 0.22), 0.4)
        case .storm: return mix(color, RGB(0.1, 0.12, 0.13), 0.55)
        default: return color
        }
    }

    private func drawHills(_ ctx: GraphicsContext, _ size: CGSize, _ phase: DayPhase) {
        for i in Self.hillLayers.indices {
            let path = Path { p in
                p.move(to: CGPoint(x: 0, y: size.height))
                for x in stride(from: 0.0, through: size.width, by: 6) {
                    p.addLine(to: CGPoint(x: x, y: hillY(x, size, layer: i)))
                }
                p.addLine(to: CGPoint(x: size.width, y: size.height))
                p.closeSubpath()
            }
            ctx.fill(path, with: .color(hillColor(i, phase).color))
        }
    }

    /// Pines on the middle and front hills, swaying with the wind.
    private func drawTrees(_ ctx: GraphicsContext, _ size: CGSize, _ phase: DayPhase, _ t: Double) {
        var rng = Seeded(23)
        for layerIndex in [1, 2] {
            let base = hillColor(layerIndex, phase)
            let color = mix(base, RGB(0, 0.05, 0.02), phase == .night ? 0.3 : 0.35).color
            let treeScale = layerIndex == 1 ? 0.7 : 1.0
            for _ in 0..<(layerIndex == 1 ? 6 : 5) {
                let x = rng.unit() * size.width
                let y = hillY(x, size, layer: layerIndex) + 2
                let height = (16 + rng.unit() * 14) * treeScale
                let sway = sin(t * (1.1 + rng.unit() * 0.5) + x * 0.05) * 0.05 * (0.3 + wind)
                var tree = ctx
                tree.translateBy(x: x, y: y)
                tree.rotate(by: .radians(sway))
                var path = Path()
                for tier in 0..<3 {
                    let top = -height * (1 - Double(tier) * 0.28)
                    let bottom = -height * (0.45 - Double(tier) * 0.18)
                    let half = height * (0.18 + Double(tier) * 0.08)
                    path.move(to: CGPoint(x: 0, y: top))
                    path.addLine(to: CGPoint(x: -half, y: bottom))
                    path.addLine(to: CGPoint(x: half, y: bottom))
                    path.closeSubpath()
                }
                path.addRect(CGRect(x: -1.2, y: -height * 0.1, width: 2.4, height: height * 0.12))
                tree.fill(path, with: .color(color))
            }
        }
    }

    // MARK: Precipitation

    private func drawRain(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double, heavy: Bool) {
        let w = size.width, h = size.height
        let slant = 0.15 + wind * 0.35  // sideways drift per unit of fall
        var rng = Seeded(3)
        var path = Path()
        let length = heavy ? 16.0 : 12.0
        for _ in 0..<(heavy ? 140 : 80) {
            let speed = 280 + rng.unit() * 140
            let x0 = rng.unit() * (w + h * slant)
            let y = (rng.unit() * h + t * speed).truncatingRemainder(dividingBy: h + 20) - 20
            let x = x0 - y * slant
            path.move(to: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x - length * slant, y: y + length))
        }
        ctx.stroke(path, with: .color(.white.opacity(heavy ? 0.42 : 0.34)), lineWidth: 1)
        guard !overlayOnly else { return }  // the photo has its own ground

        // Splashes on the front hill.
        var splash = Seeded(31)
        for _ in 0..<(heavy ? 30 : 18) {
            let x = splash.unit() * w
            let p = (t * (1.6 + splash.unit()) + splash.unit()).truncatingRemainder(dividingBy: 1)
            let y = hillY(x, size, layer: 2) + 2
            let r = 1 + p * 4
            ctx.stroke(Path(ellipseIn: CGRect(x: x - r, y: y - r * 0.35, width: r * 2, height: r * 0.7)),
                       with: .color(.white.opacity((1 - p) * 0.45)), lineWidth: 0.8)
        }
    }

    private func drawSnow(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double) {
        let w = size.width, h = size.height
        var rng = Seeded(5)
        for _ in 0..<90 {
            let r = 1 + rng.unit() * 1.8
            let speed = 18 + rng.unit() * 22
            let y = (rng.unit() * h + t * speed).truncatingRemainder(dividingBy: h + 10) - 5
            let drift = (t * 12 * wind).truncatingRemainder(dividingBy: w)
            let x = (rng.unit() * w + drift + sin(t * 0.8 + rng.unit() * 6) * 8).truncatingRemainder(dividingBy: w)
            ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.85)))
        }
    }

    private func drawLightning(_ ctx: GraphicsContext, _ size: CGSize, _ t: Double) {
        // A double flash roughly every 9 seconds, with a jagged bolt on the first.
        let period = 9.0
        let cycle = t.truncatingRemainder(dividingBy: period)
        let flash = cycle < 0.08 ? 0.35 : (cycle > 0.16 && cycle < 0.22 ? 0.2 : 0)
        guard flash > 0 else { return }
        ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(flash)))
        guard cycle < 0.08 else { return }
        var rng = Seeded(UInt64(t / period) &+ 5)
        var bolt = Path()
        var point = CGPoint(x: size.width * (0.3 + rng.unit() * 0.5), y: size.height * 0.12)
        bolt.move(to: point)
        while point.y < size.height * 0.62 {
            point = CGPoint(x: point.x + (rng.unit() - 0.5) * 26, y: point.y + 10 + rng.unit() * 14)
            bolt.addLine(to: point)
        }
        ctx.stroke(bolt, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
    }
}

// MARK: - Photo backdrop

/// One of the bundled weather photos, picked for the current conditions and the sun's real position,
/// softened with a 25% blur, slowly drifting (Ken Burns), with rain, snow and lightning animated on top.
struct WeatherPhotoBackdrop: View {
    let code: Int
    let isDay: Bool
    let sunrise: Date?
    let sunset: Date?
    var wind: Double = 0.3
    @State private var drift = false

    var body: some View {
        // Re-check every 30 seconds so the photo changes at golden hour, sunset and dark.
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let phase = DayPhase(now: context.date, isDay: isDay, sunrise: sunrise, sunset: sunset)
            let choice = WeatherPhoto(sky: SkyKind(code: code), phase: phase)
            GeometryReader { geo in
                ZStack {
                    if let image = choice.image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .scaleEffect(drift ? 1.14 : 1.06, anchor: drift ? .topTrailing : .bottomLeading)
                            .blur(radius: WeatherPhoto.blurRadius, opaque: true)
                            .brightness(choice.dim)
                            .clipped()
                            .id(choice.name)
                            .transition(.opacity)
                    }
                    WeatherScene(code: code, isDay: isDay, sunrise: sunrise, sunset: sunset, wind: wind, overlayOnly: true)
                }
                .animation(.easeInOut(duration: 1.5), value: choice.name)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 45).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

struct WeatherPhoto {
    /// 25% of a heavy 20 pt blur.
    static let blurRadius: CGFloat = 5

    let name: String
    /// Darkens a daytime photo when it stands in at night (e.g. rain after dark).
    let dim: Double

    init(sky: SkyKind, phase: DayPhase) {
        switch (sky, phase) {
        case (.rain, _), (.storm, _): name = "rain"
        case (.snow, _): name = "snow"
        case (_, .night): name = "night"
        case (_, .blueHour): name = "twilight"
        case (.fog, _): name = "fog"
        case (_, .golden): name = "sunset"
        case (.clear, _): name = "clear"
        default: name = "cloudy"  // partly cloudy and overcast
        }
        let photoIsDaytime = ["rain", "snow"].contains(name)
        dim = photoIsDaytime ? (phase == .night ? -0.3 : phase == .blueHour ? -0.15 : 0) : 0
    }

    private static var cache: [String: NSImage] = [:]

    var image: NSImage? {
        if let cached = Self.cache[name] { return cached }
        guard let url = Bundle.main.url(forResource: "weather-\(name)", withExtension: "jpg"),
              let image = NSImage(contentsOf: url) else { return nil }
        Self.cache[name] = image
        return image
    }
}

// MARK: - Model

/// Where the sun is, from today's real sunrise and sunset times.
enum DayPhase {
    case night, blueHour, golden, day

    init(now: Date, isDay: Bool, sunrise: Date?, sunset: Date?) {
        guard let sunrise, let sunset else { self = isDay ? .day : .night; return }
        let blue: TimeInterval = 40 * 60, golden: TimeInterval = 60 * 60
        if now < sunrise.addingTimeInterval(-blue) || now > sunset.addingTimeInterval(blue) {
            self = .night
        } else if now < sunrise || now > sunset {
            self = .blueHour
        } else if now < sunrise.addingTimeInterval(golden) || now > sunset.addingTimeInterval(-golden) {
            self = .golden
        } else {
            self = .day
        }
    }

    /// Sky colors from top to horizon.
    var skyStops: [RGB] {
        switch self {
        case .day: [RGB(0.09, 0.40, 0.86), RGB(0.27, 0.60, 0.95), RGB(0.62, 0.82, 0.98)]
        case .golden: [RGB(0.22, 0.35, 0.64), RGB(0.86, 0.56, 0.47), RGB(1.0, 0.73, 0.40)]
        case .blueHour: [RGB(0.06, 0.09, 0.26), RGB(0.32, 0.28, 0.55), RGB(0.90, 0.50, 0.42)]
        case .night: [RGB(0.01, 0.02, 0.07), RGB(0.04, 0.07, 0.16), RGB(0.09, 0.13, 0.26)]
        }
    }

    /// Back, middle and front hill colors.
    var hillColors: [RGB] {
        switch self {
        case .day: [RGB(0.24, 0.45, 0.32), RGB(0.30, 0.55, 0.24), RGB(0.40, 0.64, 0.22)]
        case .golden: [RGB(0.36, 0.32, 0.30), RGB(0.32, 0.34, 0.20), RGB(0.30, 0.34, 0.16)]
        case .blueHour: [RGB(0.16, 0.15, 0.25), RGB(0.11, 0.12, 0.18), RGB(0.08, 0.09, 0.13)]
        case .night: [RGB(0.06, 0.08, 0.12), RGB(0.04, 0.06, 0.09), RGB(0.03, 0.04, 0.06)]
        }
    }
}

/// The weather, grouped from Open-Meteo's WMO codes into how the sky should look.
enum SkyKind {
    case clear, partly, overcast, fog, rain, snow, storm

    init(code: Int) {
        switch code {
        case 0, 1: self = .clear
        case 2: self = .partly
        case 3: self = .overcast
        case 45, 48: self = .fog
        case 51...67, 80...82: self = .rain
        case 71...77, 85, 86: self = .snow
        case 95...99: self = .storm
        default: self = .partly
        }
    }

    var showsStars: Bool { self == .clear || self == .partly }

    var cloudCount: Int {
        switch self {
        case .clear: 0
        case .partly: 4
        case .fog: 2
        case .snow: 7
        case .overcast, .rain, .storm: 10
        }
    }

    var cloudTop: Double { self == .partly ? 0.1 : 0.0 }
    var cloudSpread: Double { self == .partly ? 0.3 : 0.4 }

    /// How much of the sun or moon shows through.
    var sunVisibility: Double {
        switch self {
        case .clear: 1
        case .partly: 0.9
        case .fog, .snow: 0.3
        case .overcast: 0.15
        case .rain, .storm: 0
        }
    }

    /// Pulls the sky toward gray for cloudy, rainy and stormy weather.
    func mute(for phase: DayPhase) -> (RGB, Double) {
        let night = phase == .night
        switch self {
        case .clear: return (RGB(0, 0, 0), 0)
        case .partly: return (RGB(0.6, 0.65, 0.7), 0.12)
        case .fog: return (night ? RGB(0.12, 0.13, 0.15) : RGB(0.8, 0.82, 0.84), 0.75)
        case .overcast: return (night ? RGB(0.08, 0.09, 0.11) : RGB(0.55, 0.59, 0.64), 0.65)
        case .rain: return (night ? RGB(0.06, 0.07, 0.09) : RGB(0.36, 0.4, 0.45), 0.8)
        case .snow: return (night ? RGB(0.14, 0.16, 0.2) : RGB(0.82, 0.85, 0.9), 0.6)
        case .storm: return (RGB(0.16, 0.17, 0.22), 0.85)
        }
    }

    func cloudColor(for phase: DayPhase) -> Color {
        let dark: Double = switch self {
        case .storm: 0.55
        case .rain: 0.4
        case .overcast: 0.25
        default: 0
        }
        let base: RGB = switch phase {
        case .day: RGB(0.98, 0.98, 1)
        case .golden: RGB(1, 0.8, 0.68)
        case .blueHour: RGB(0.58, 0.46, 0.62)
        case .night: RGB(0.2, 0.22, 0.3)
        }
        return mix(base, RGB(0.25, 0.27, 0.32), dark).color.opacity(self == .partly ? 0.85 : 0.92)
    }
}

struct RGB {
    var r, g, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    var color: Color { Color(red: r, green: g, blue: b) }
}

private func mix(_ a: RGB, _ b: RGB, _ amount: Double) -> RGB {
    RGB(a.r + (b.r - a.r) * amount, a.g + (b.g - a.g) * amount, a.b + (b.b - a.b) * amount)
}

/// Same sequence every frame, so stars, clouds and raindrops keep their places.
private struct Seeded {
    var state: UInt64
    init(_ seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 &+ 1 }
    mutating func unit() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}
