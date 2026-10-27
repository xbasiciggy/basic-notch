import Foundation
import ImageIO

@MainActor
enum DesktopBuddyArtwork {
    static let bundleURL = Bundle.main.url(forResource: "Mons", withExtension: "bundle")

    static let roster = PokeBrawlSprites.roster.sorted {
        $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }

    static func entry(for id: String) -> RosterEntry? {
        roster.first { $0.id == id } ?? roster.first { $0.id == "0700" } ?? roster.first
    }

    static func hasShiny(_ id: String) -> Bool {
        PokeBrawlSprites.roster.first { $0.id == id }?.shiny != nil
    }

    private static var cache: [String: [String: SpriteAnim]] = [:]

    /// Only the buddy requests eight rows; notch companions retain their two-row renderer.
    static func animations(for entry: RosterEntry, shiny: Bool) -> [String: SpriteAnim] {
        let useShiny = shiny && hasShiny(entry.id)
        let key = entry.id + (useShiny ? "/s" : "")
        if let cached = cache[key] { return cached }
        let sourceEntry = entry
        guard let base = bundleURL?.appendingPathComponent(entry.id) else { return [:] }
        let folder = useShiny ? base.appendingPathComponent("s") : base
        let metadata = (useShiny ? sourceEntry.shiny : nil) ?? sourceEntry.anims
        var result: [String: SpriteAnim] = [:]
        for (name, anim) in metadata {
            guard let source = CGImageSourceCreateWithURL(folder.appendingPathComponent(anim.file + ".png") as CFURL, nil),
                  let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let decoded = SpriteAnim(sheet: sheet, anim: anim, allDirections: true) else { continue }
            result[name] = decoded
        }
        // Keep selection browsing from retaining every species' eight-direction frames.
        if cache.count >= 12 { cache.removeAll() }
        cache[key] = result
        return result
    }
}
