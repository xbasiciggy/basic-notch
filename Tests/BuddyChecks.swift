import Foundation
import ImageIO

@main
struct BuddyChecks {
    static func main() throws {
        var checks = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }
        let primary = CGRect(x: 0, y: 25, width: 1440, height: 850)
        let left = CGRect(x: -1920, y: -500, width: 1920, height: 1080)
        let frame = CGRect(x: -1500, y: -200, width: 260, height: 190)
        check(BuddyPlacement.fit(frame, screens: [primary, left]) == frame, "retain negative-coordinate display position")
        check(primary.contains(BuddyPlacement.fit(frame, screens: [primary])), "recover disconnected display")
        check(BuddyPlacement.fit(frame, screens: []) == frame, "no-screen transition")
        for x in stride(from: -2500, through: 2500, by: 100) {
            for y in stride(from: -1200, through: 1600, by: 100) {
                let fitted = BuddyPlacement.fit(CGRect(x: x, y: y, width: 260, height: 190), screens: [primary, left])
                check(primary.contains(fitted) || left.contains(fitted), "entire buddy fits one visible display")
            }
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let roster = try JSONDecoder().decode([RosterEntry].self, from: Data(contentsOf: root.appendingPathComponent("roster.json")))
        let sylveon = try XCTUnwrap(roster.first { $0.id == "0700" })
        for key in ["idle", "walk"] {
            let metadata = try XCTUnwrap(sylveon.anims[key])
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(root.appendingPathComponent("0700/\(metadata.file).png") as CFURL, nil))
            let sheet = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let animation = try XCTUnwrap(SpriteAnim(sheet: sheet, anim: metadata))
            check(animation.total > 0, "positive animation duration")
            check(animation.left.count == metadata.d.count, "all frames decode")
            for t in [0.0, 0.1, 100.0] { check(animation.frame(at: t, facingRight: false).height > 0, "valid frame") }
        }
        let credits = try String(contentsOf: root.appendingPathComponent("0700/credits.txt"), encoding: .utf8)
        check(credits.contains("CC_BY-NC_4") && credits.contains("544245909639397378"), "explicit Sylveon license and artist retained")
        print("Passed \(checks) desktop buddy checks")
    }
    static func XCTUnwrap<T>(_ value: T?) throws -> T {
        guard let value else { throw NSError(domain: "BuddyChecks", code: 1) }; return value
    }
}
