import SwiftUI
import ImageIO

/// Pokémon you've caught by clicking them in the notch. Saved between launches.
@MainActor
final class PokedexStore: ObservableObject {
    struct Entry: Codable {
        var count: Int
        var shinyCount: Int
        var firstCaught: Date
    }

    static let shared = PokedexStore()
    @Published private(set) var caught: [String: Entry] = [:]  // roster id → entry
    private let key = "pokedexCaught"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([String: Entry].self, from: data) {
            caught = saved
        }
    }

    var totalCaught: Int { caught.values.reduce(0) { $0 + $1.count } }
    var shinyCaught: Int { caught.values.reduce(0) { $0 + $1.shinyCount } }

    func record(id: String, shiny: Bool) {
        var entry = caught[id] ?? Entry(count: 0, shinyCount: 0, firstCaught: Date())
        entry.count += 1
        if shiny { entry.shinyCount += 1 }
        caught[id] = entry
        if let data = try? JSONEncoder().encode(caught) { UserDefaults.standard.set(data, forKey: key) }
    }

    func reset() {
        caught = [:]
        UserDefaults.standard.removeObject(forKey: key)
    }
}

extension PokeBrawlSprites {
    private static var icons: [String: CGImage] = [:]

    /// First idle frame (facing down), trimmed — a small icon for the Pokédex grid.
    static func icon(for entry: RosterEntry, shiny: Bool) -> CGImage? {
        let key = entry.id + (shiny ? "/s" : "")
        if let cached = icons[key] { return cached }
        let anims = (shiny ? entry.shiny : nil) ?? entry.anims
        guard let anim = anims["idle"] ?? anims["walk"],
              let base = bundleURL?.appendingPathComponent(entry.id),
              let source = CGImageSourceCreateWithURL((shiny ? base.appendingPathComponent("s") : base)
                .appendingPathComponent("\(anim.file).png") as CFURL, nil),
              let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let sprite = SpriteAnim(sheet: sheet, anim: RosterEntry.Anim(w: anim.w, h: anim.h, d: [anim.d.first ?? 1],
                                                                            file: anim.file, hit: nil)),
              let frame = sprite.left.first else { return nil }
        icons[key] = frame
        return frame
    }
}

struct PokedexTab: View {
    @ObservedObject private var dex = PokedexStore.shared

    private var entries: [(RosterEntry, PokedexStore.Entry)] {
        PokeBrawlSprites.roster.compactMap { e in dex.caught[e.id].map { (e, $0) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Label("\(dex.caught.count) / \(PokeBrawlSprites.roster.count) caught", systemImage: "circle.circle")
                    .font(.caption.bold())
                if dex.shinyCaught > 0 {
                    Text("✨ \(dex.shinyCaught) shiny").font(.caption).foregroundStyle(.yellow)
                }
                Spacer()
                Text("Click a Pokémon in the notch to throw a Poké Ball").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            if entries.isEmpty {
                StatusMessage(icon: "circle.circle", text: "No Pokémon caught yet")
            } else {
                ScrollView(.vertical) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 46), spacing: 6)], spacing: 6) {
                        ForEach(entries, id: \.0.id) { entry, info in
                            DexCell(entry: entry, info: info)
                        }
                    }
                    .padding(.trailing, 6)
                }
            }
        }
    }
}

private struct DexCell: View {
    let entry: RosterEntry
    let info: PokedexStore.Entry

    var body: some View {
        let shiny = info.shinyCount > 0 && entry.shiny != nil
        VStack(spacing: 2) {
            if let icon = PokeBrawlSprites.icon(for: entry, shiny: shiny) {
                Image(decorative: icon, scale: 1).interpolation(.none)
                    .resizable().aspectRatio(contentMode: .fit)
                    .frame(width: 34, height: 30)
            }
            Text("#\(entry.dex)").font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
        }
        .frame(width: 46, height: 46)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
        .overlay(alignment: .topTrailing) {
            if info.count > 1 {
                Text("×\(info.count)").font(.system(size: 8, weight: .bold)).padding(2)
            }
        }
        .overlay(alignment: .topLeading) {
            if shiny { Text("✨").font(.system(size: 8)).padding(1) }
        }
        .help("\(entry.name) · caught \(info.count)×" + (info.shinyCount > 0 ? " (\(info.shinyCount) shiny)" : ""))
    }
}

/// A tiny Poké Ball drawn with shapes.
struct PokeBallView: View {
    var body: some View {
        ZStack {
            Circle().fill(.white)
            Circle().trim(from: 0.5, to: 1).fill(Color.red)
            Rectangle().fill(.black).frame(height: 1.5)
            Circle().fill(.white).frame(width: 4.5, height: 4.5).overlay(Circle().stroke(.black, lineWidth: 1))
            Circle().stroke(.black, lineWidth: 1)
        }
    }
}
