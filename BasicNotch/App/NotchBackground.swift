import SwiftUI
import AppKit

/// Cursor position inside the open notch, in the notch's own coordinates (origin top-left).
/// Kept separate from the view model so only the glow redraws as the mouse moves.
@MainActor
final class CursorTracker: ObservableObject {
    @Published private(set) var point: CGPoint?

    func update(_ newPoint: CGPoint?) {
        switch (point, newPoint) {
        case (nil, nil): return
        case let (old?, new?) where abs(old.x - new.x) < 0.5 && abs(old.y - new.y) < 0.5: return
        default: point = newPoint
        }
    }
}

/// How the open notch is filled. Every theme stays solid black at the top so the camera housing disappears.
enum NotchTheme: String, CaseIterable, Identifiable {
    case glass, black

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass: "Liquid Glass"
        case .black: "Solid black"
        }
    }

    var subtitle: String {
        switch self {
        case .glass: "Black fading into frosted glass"
        case .black: "Plain black, like the hardware notch"
        }
    }

    static let glassFadeStops: [Gradient.Stop] = [
        .init(color: .black, location: 0),
        .init(color: .black, location: 0.22),
        .init(color: .black.opacity(0.6), location: 0.6),
        .init(color: .black.opacity(0.18), location: 1),
    ]

    /// A small preview of the theme for the Settings picker.
    @ViewBuilder
    var swatch: some View {
        switch self {
        case .glass:
            LinearGradient(stops: Self.glassFadeStops, startPoint: .top, endPoint: .bottom)
                .background(Color(white: 0.55))
        case .black:
            Color.black
        }
    }
}

/// The notch fill: plain black when closed; when open, black at the top (so the camera housing
/// still disappears) fading into the chosen theme, with a neon glow that follows the cursor.
struct NotchBackground: View {
    let isOpen: Bool
    let shape: NotchShape
    @ObservedObject var cursor: CursorTracker
    /// Album colors to glow with (music tab); empty for no glow.
    var albumColors: [Color] = []
    /// Drift and pulse the album glow (while music is playing).
    var albumGlowAnimated = false
    @AppStorage("notchTheme") private var theme: NotchTheme = .glass
    @AppStorage("neonGlow") private var neon = true
    @AppStorage("neonColor") private var neonHex = "#33E6FF"
    @AppStorage("neonIntensity") private var intensity = 0.45

    private var glowColor: Color { Color(hex: neonHex) ?? .cyan }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if isOpen && theme == .glass {
                    glassLayer
                    LinearGradient(stops: NotchTheme.glassFadeStops, startPoint: .top, endPoint: .bottom)
                } else {
                    Color.black
                }

                if isOpen && !albumColors.isEmpty {
                    AlbumGlow(colors: albumColors, size: geo.size, animated: albumGlowAnimated)
                        .transition(.opacity)
                }

                if isOpen && neon, let p = cursor.point {
                    NeonGlow(point: p, size: geo.size, color: glowColor, intensity: intensity)
                        .transition(.opacity)
                }
            }
            .clipShape(shape)
            .overlay {
                if isOpen && neon, let p = cursor.point {
                    // The notch's edge lights up near the cursor.
                    shape.stroke(
                        RadialGradient(colors: [glowColor.opacity(0.9 * intensity), glowColor.opacity(0.3 * intensity), .clear],
                                       center: UnitPoint(x: p.x / max(geo.size.width, 1), y: p.y / max(geo.size.height, 1)),
                                       startRadius: 0, endRadius: 130),
                        lineWidth: 1)
                    .blendMode(.plusLighter)
                }
            }
            .animation(.easeOut(duration: 0.12), value: cursor.point?.x)
            .animation(.easeOut(duration: 0.12), value: cursor.point?.y)
            .animation(.easeInOut(duration: 0.3), value: isOpen)
            .animation(.easeInOut(duration: 0.3), value: theme)
            .animation(.easeInOut(duration: 0.8), value: albumColors)
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var glassLayer: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            BehindWindowBlur()
        }
    }
}

/// Soft blooms of the album's colors rising from the bottom of the notch, like Apple Music's ambient
/// background. Masked so the top stays black over the camera housing.
/// Soft blobs of the album's colors rising from the bottom. While music plays they drift around
/// like a lava lamp and gently breathe; when paused they hold still.
private struct AlbumGlow: View {
    let colors: [Color]
    let size: CGSize
    var animated = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: !animated)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(Array(colors.prefix(3).enumerated()), id: \.offset) { i, color in
                    let phase = Double(i) * 2.1
                    let speed = 0.22 + 0.06 * Double(i)
                    let dx = sin(t * speed + phase) * 0.17                 // slow side-to-side drift
                    let dy = cos(t * speed * 0.8 + phase) * 0.1            // and a little bob
                    let breathe = 1 + 0.09 * sin(t * 1.4 + phase)          // gentle swell
                    Ellipse()
                        .fill(color.opacity(0.62 + 0.13 * sin(t * 0.9 + phase)))
                        .frame(width: size.width * 0.55 * breathe, height: size.height * 0.9 * breathe)
                        .position(x: size.width * ([0.2, 0.8, 0.5][i] + dx),
                                  y: size.height * ([0.95, 0.9, 1.1][i] + dy))
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .blur(radius: 60)
        .mask(LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .clear, location: 0.2),
            .init(color: .white.opacity(0.7), location: 0.65),
            .init(color: .white, location: 1),
        ], startPoint: .top, endPoint: .bottom))
    }
}

/// Picks a few vivid, distinct colors from artwork by sampling a tiny thumbnail.
enum ArtworkPalette {
    static func colors(from image: NSImage) -> [Color] {
        let side = 12
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return [] }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        let px = data.bindMemory(to: UInt8.self, capacity: side * side * 4)

        var samples: [(h: CGFloat, s: CGFloat, b: CGFloat)] = []
        for i in 0..<(side * side) {
            let c = NSColor(srgbRed: CGFloat(px[i * 4]) / 255, green: CGFloat(px[i * 4 + 1]) / 255,
                            blue: CGFloat(px[i * 4 + 2]) / 255, alpha: 1)
            var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
            c.getHue(&h, saturation: &s, brightness: &b, alpha: nil)
            samples.append((h, s, b))
        }

        // Most vivid first; skip near-duplicate hues so the glow has some variety.
        var picked: [(h: CGFloat, s: CGFloat, b: CGFloat)] = []
        for c in samples.sorted(by: { $0.s * $0.b > $1.s * $1.b }) where c.s > 0.2 && c.b > 0.2 {
            let distinct = picked.allSatisfy { p in
                let d = abs(p.h - c.h)
                return min(d, 1 - d) > 0.07
            }
            if distinct { picked.append(c) }
            if picked.count == 3 { break }
        }

        // Grayscale artwork: fall back to its average tone so the glow still matches.
        if picked.isEmpty {
            let avg = samples.map(\.b).reduce(0, +) / CGFloat(samples.count)
            return [Color(white: max(0.35, avg))]
        }
        // Lift dark colors so they read as light rather than mud.
        return picked.map { Color(hue: $0.h, saturation: min(1, $0.s * 1.1), brightness: max(0.6, $0.b)) }
    }
}

/// A soft neon glow that trails the cursor, in the color chosen in Settings.
private struct NeonGlow: View {
    let point: CGPoint
    let size: CGSize
    let color: Color
    let intensity: Double

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(0.32 * intensity), color.opacity(0.08 * intensity), .clear],
                                 center: .center, startRadius: 0, endRadius: 110))
            .frame(width: 220, height: 220)
            .position(point)
            .frame(width: size.width, height: size.height)
            .blendMode(.plusLighter)
    }
}

extension Color {
    init?(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

/// Fallback frosted glass for macOS versions before Liquid Glass.
private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active  // stay frosted even though the panel never becomes the active window
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
