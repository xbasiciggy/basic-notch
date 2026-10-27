import Foundation

@main
struct BuddyCareChecks {
    @MainActor static func main() throws {
        let oldMax = BuddyLayout(size: 3), newMax = BuddyLayout(size: BuddyLayout.maximumSize)
        precondition(newMax.spriteHeight == oldMax.spriteHeight * 3.5)
        precondition(newMax.height - newMax.spriteHeight == oldMax.height - oldMax.spriteHeight)
        precondition(newMax.width >= newMax.spriteWidth)
        precondition(BuddyLayout(size: .infinity).expansion == 1)
        precondition(BuddyLayout(size: 99).expansion == 3.5)
        let suite = "BasicNotch.BuddyCareTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("keep-me", forKey: "unrelatedSetting")
        let care = BuddyCareStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var checks = 5
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); checks += 1
        }
        care.select("0025")
        check(care.profile.level == 1 && care.profile.levelProgress == 0, "new buddy starts at level 1")
        care.rename("  Sparky  ")
        check(care.profile.nickname == "Sparky", "nickname trimming")
        care.perform(.berry, now: now)
        check(care.profile.xp == 10 && care.action == .berry, "food grants XP and animation")
        care.perform(.tennis, now: now.addingTimeInterval(2))
        check(care.profile.xp == 10 && care.action == .tennis, "cooldown across actions still permits play")
        care.perform(.tennis, now: now.addingTimeInterval(10))
        check(care.profile.xp == 25, "cooldown expires")
        care.tick(now: now.addingTimeInterval(20))
        check(care.action == nil && care.speech == nil, "actions and speech expire")
        care.sleep(now: now.addingTimeInterval(30))
        check(care.sleeping && care.blocksMovement, "sleep pauses roaming")
        care.perform(.shock, now: now.addingTimeInterval(40))
        check(care.action == nil && care.profile.xp == 25, "sleep does not allow shock or XP")
        let restored = BuddyCareStore(defaults: defaults)
        restored.select("0025")
        check(restored.sleeping && restored.profile.nickname == "Sparky" && restored.profile.xp == 25, "restart preserves care state")
        restored.wake(now: now.addingTimeInterval(91))
        check(!restored.sleeping && restored.profile.xp == 30, "long nap grants small reward")
        restored.wake(now: now.addingTimeInterval(200))
        check(restored.profile.xp == 30, "no repeated wake reward")
        restored.select("0700")
        check(restored.profile.xp == 0 && restored.profile.nickname.isEmpty, "per-species progression")
        restored.select("0025")
        check(restored.profile.xp == 30, "switching back retains progress")
        for i in 1...8 { restored.perform(.berry, now: now.addingTimeInterval(100 + Double(i)*10)) }
        check(restored.profile.level == 2 && abs(restored.profile.levelProgress - 0.1) < 0.001, "level rollover")
        restored.rename(String(repeating: "x", count: 90))
        check(restored.profile.nickname.count == 24, "bounded nickname")
        check(defaults.string(forKey: "unrelatedSetting") == "keep-me", "other settings untouched")
        restored.menuOpen = true
        check(restored.blocksMovement, "care menu pauses roaming")
        restored.select("0700")
        check(!restored.menuOpen && restored.action == nil, "selection closes transient interactions")
        var capped = BuddyProfile(); capped.xp = 9900
        check(capped.level == 100 && capped.levelProgress == 1, "level cap")
        print("Passed \(checks) buddy care checks")
    }
}
