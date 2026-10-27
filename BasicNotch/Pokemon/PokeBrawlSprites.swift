import Foundation
import CoreGraphics
import ImageIO

/// Sprites imported from a sprite project (PMD-style sheets) by tools/import_pokebrawl_sprites.py.
/// Each sheet is a grid: one column per frame, one row per facing direction
/// (0 down, 1 down-right, 2 right, 3 up-right, 4 up, 5 up-left, 6 left, 7 down-left).
struct RosterEntry: Decodable {
    struct Anim: Decodable {
        let w: Int
        let h: Int
        let d: [Int]  // frame durations in 1/60 s ticks
        let file: String
        let hit: Int?  // frame where an attack connects
    }

    let id: String
    let name: String
    let type: String
    let anims: [String: Anim]
    let shiny: [String: Anim]?

    /// National Pokédex number ("0006-MX" → 6).
    var dex: Int { Int(id.prefix(4)) ?? 0 }
}

struct SpriteAnim {
    let directions: [[CGImage]]
    let left: [CGImage]
    let right: [CGImage]
    let durations: [Double]
    let total: Double
    /// Size of the trimmed frames, in sprite pixels.
    let size: CGSize
    /// How far the trimmed box's center sits from the cell's center (keeps lunges anchored).
    let centerOffset: CGFloat
    /// Seconds into the animation when the attack lands.
    let hitTime: Double

    init?(sheet: CGImage, anim: RosterEntry.Anim, allDirections: Bool = false) {
        let w = anim.w, h = anim.h
        guard w > 0, h > 0, !anim.d.isEmpty else { return nil }
        let rows = max(1, Int((Double(sheet.height) / Double(h)).rounded()))
        let cols = min(anim.d.count, sheet.width / w)
        guard cols > 0 else { return nil }

        func cells(_ row: Int) -> [CGImage] {
            (0..<cols).compactMap { sheet.cropping(to: CGRect(x: $0 * w, y: row * h, width: w, height: h)) }
        }
        let rawLeft = cells(rows >= 8 ? 6 : 0)
        let rawRight = cells(rows >= 8 ? 2 : 0)

        // Trim the empty padding around the cells (same box for every frame, so feet stay planted).
        let rawDirections = allDirections ? (0..<8).map { cells(rows >= 8 ? $0 : 0) } : []
        let box = Self.opaqueBounds(allDirections ? rawDirections.flatMap { $0 } : rawLeft + rawRight, width: w, height: h)
        directions = allDirections ? rawDirections.map { frames in frames.compactMap { $0.cropping(to: box) } } : []
        left = rawLeft.compactMap { $0.cropping(to: box) }
        right = rawRight.compactMap { $0.cropping(to: box) }
        guard !left.isEmpty, !right.isEmpty else { return nil }
        durations = anim.d.prefix(cols).map { Double(max($0, 1)) / 60 }
        total = durations.reduce(0, +)
        size = box.size
        centerOffset = box.midX - CGFloat(w) / 2
        let hit = anim.hit ?? -1
        hitTime = hit >= 0 ? durations.prefix(hit).reduce(0, +) : total * 0.5
    }

    func frame(at time: Double, direction: Int, loop: Bool = true) -> CGImage {
        let frames = directions.isEmpty ? left : directions[min(7, max(0, direction))]
        return timedFrame(frames, time: time, loop: loop)
    }

    private func timedFrame(_ frames: [CGImage], time: Double, loop: Bool) -> CGImage {
        guard frames.count > 1 else { return frames[0] }
        if !loop && time >= total { return frames[frames.count - 1] }
        var t = max(0, time).truncatingRemainder(dividingBy: total)
        for (i, d) in durations.enumerated() where i < frames.count {
            if t < d { return frames[i] }
            t -= d
        }
        return frames[frames.count - 1]
    }

    func frame(at time: Double, facingRight: Bool, loop: Bool = true) -> CGImage {
        let frames = facingRight ? right : left
        guard frames.count > 1 else { return frames[0] }
        if !loop && time >= total { return frames[frames.count - 1] }
        var t = time.truncatingRemainder(dividingBy: total)
        for (i, d) in durations.enumerated() where i < frames.count {
            if t < d { return frames[i] }
            t -= d
        }
        return frames[frames.count - 1]
    }

    private static func opaqueBounds(_ images: [CGImage], width: Int, height: Int) -> CGRect {
        var minX = width, minY = height, maxX = -1, maxY = -1
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)
        for image in images {
            buffer.withUnsafeMutableBytes { ptr in
                guard let ctx = CGContext(data: ptr.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
                ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
                ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            // CGContext memory starts at the top row, matching CGImage cropping coordinates.
            for y in 0..<height {
                for x in 0..<width where buffer[y * bytesPerRow + x * 4 + 3] > 20 {
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        guard maxX >= minX else { return CGRect(x: 0, y: 0, width: width, height: height) }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}

struct MonSprites {
    let walk: SpriteAnim
    let idle: SpriteAnim?
    let attack: SpriteAnim?
    let hurt: SpriteAnim?
    let faint: SpriteAnim?

    /// Display size: one sprite pixel per point (chunky pixel art), shrunk if it won't fit the bar.
    func displayScale(maxHeight: CGFloat) -> CGFloat {
        let tallest = max(walk.size.height, idle?.size.height ?? 0)
        return tallest > maxHeight ? maxHeight / tallest : 1
    }
}

@MainActor
enum PokeBrawlSprites {
    static let bundleURL = Bundle.main.url(forResource: "Mons", withExtension: "bundle")

    static let roster: [RosterEntry] = {
        guard let url = bundleURL?.appendingPathComponent("roster.json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([RosterEntry].self, from: data) else { return [] }
        return entries
    }()

    private static var cache: [String: MonSprites] = [:]

    static func sprites(for entry: RosterEntry, shiny: Bool) -> MonSprites? {
        let key = entry.id + (shiny ? "/s" : "")
        if let cached = cache[key] { return cached }
        guard let base = bundleURL?.appendingPathComponent(entry.id) else { return nil }
        let folder = shiny ? base.appendingPathComponent("s") : base
        let anims = (shiny ? entry.shiny : nil) ?? entry.anims

        func load(_ key: String) -> SpriteAnim? {
            guard let anim = anims[key],
                  let source = CGImageSourceCreateWithURL(folder.appendingPathComponent("\(anim.file).png") as CFURL, nil),
                  let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            return SpriteAnim(sheet: sheet, anim: anim)
        }
        guard let walk = load("walk") else { return nil }
        let sprites = MonSprites(walk: walk, idle: load("idle"), attack: load("attack"),
                                 hurt: load("hurt"), faint: load("faint"))
        cache[key] = sprites
        return sprites
    }
}
