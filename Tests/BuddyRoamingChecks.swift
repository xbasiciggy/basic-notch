import Foundation
import ImageIO

@main
struct BuddyRoamingChecks {
    static func main() throws {
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); count += 1
        }
        let vectors: [(CGFloat, CGFloat)] = [(0,-1),(1,-1),(1,0),(1,1),(0,1),(-1,1),(-1,0),(-1,-1)]
        for (row, vector) in vectors.enumerated() {
            check(BuddyMotion.direction(dx: vector.0, dy: vector.1) == row, "correct PMD direction row")
        }
        // A synthetic sheet with a unique color in every row proves actual row selection.
        let pixels: [UInt8] = (0..<8).flatMap { [UInt8($0 * 30), UInt8(20), UInt8(50), UInt8(255)] }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let sheet = CGImage(width: 1, height: 8, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let metadata = RosterEntry.Anim(w: 1, h: 1, d: [6], file: "test", hit: nil)
        let directional = SpriteAnim(sheet: sheet, anim: metadata, allDirections: true)!
        for row in 0..<8 {
            var rgba = [UInt8](repeating: 0, count: 4)
            rgba.withUnsafeMutableBytes { buffer in
                let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                    bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(directional.frame(at: 0, direction: row), in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            check(rgba[0] == UInt8(row * 30), "frame comes from requested direction")
        }
        let start = CGPoint(x: -1400, y: -300), target = CGPoint(x: -100, y: 300)
        let first = BuddyMotion.step(from: start, to: target, speed: 45, elapsed: 1.0 / 30)
        check(abs(hypot(first.x-start.x, first.y-start.y)-1.5) < 0.00001, "speed in points per second")
        check(BuddyMotion.step(from: start, to: target, speed: 0, elapsed: 0.1) == start, "zero speed")
        check(BuddyMotion.step(from: start, to: start, speed: 45, elapsed: 0.1) == start, "stationary destination")
        check(BuddyMotion.step(from: start, to: target, speed: 45, elapsed: .infinity) == start, "invalid elapsed")
        let afterSleep = BuddyMotion.step(from: start, to: target, speed: 45, elapsed: 500)
        check(hypot(afterSleep.x-start.x, afterSleep.y-start.y) <= 4.501, "no jump after wake")
        let near = CGPoint(x: start.x + 0.1, y: start.y)
        check(BuddyMotion.step(from: start, to: near, speed: 120, elapsed: 0.1) == near, "no overshoot")
        var point = start
        for _ in 0..<2000 {
            point = BuddyMotion.step(from: point, to: target, speed: 120, elapsed: 1.0/30)
            check(point.x >= start.x && point.x <= target.x && point.y >= start.y && point.y <= target.y, "bounded diagonal movement")
        }
        check(point == target, "arrives exactly")
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let roster = try JSONDecoder().decode([RosterEntry].self, from: Data(contentsOf: root.appendingPathComponent("roster.json")))
        check(Set(roster.map(\.id)).count == roster.count, "unique selector IDs")
        for entry in roster {
            for shiny in [false, true] {
                guard let anims = shiny ? entry.shiny : entry.anims else { continue }
                for key in ["walk", "idle", "hurt", "attack", "faint", "shock", "sleep", "eat"] {
                    guard let anim = anims[key] else { continue }
                    let path = root.appendingPathComponent(entry.id).appendingPathComponent(shiny ? "s" : "").appendingPathComponent(anim.file + ".png")
                    guard let source = CGImageSourceCreateWithURL(path as CFURL, nil),
                          let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil),
                          let decoded = SpriteAnim(sheet: sheet, anim: anim, allDirections: true) else {
                        fatalError("Missing animation: \(entry.id) \(shiny) \(key)")
                    }
                    check(decoded.total > 0 && !decoded.left.isEmpty && !decoded.right.isEmpty, "selected sprite supports walking directions")
                    for direction in 0..<8 {
                        check(!decoded.directions[direction].isEmpty && decoded.frame(at: 0.2, direction: direction).width > 0, "all direction and reaction frames decode")
                    }
                }
            }
        }
        print("Passed \(count) roaming and selector checks across \(roster.count) Pokémon")
    }
}
