import Foundation
import Combine

struct BuddyProfile: Codable, Equatable {
    var nickname = ""
    var xp = 0
    var sleepingSince: Date?
    var lastReward: Date?
    var level: Int { min(100, max(0, xp) / 100 + 1) }
    var levelProgress: Double { level == 100 ? 1 : Double(max(0, xp) % 100) / 100 }
}

enum BuddyCareAction: String {
    case berry, apple, tennis, beach, pet, shock
    var xp: Int {
        switch self { case .berry, .apple: 10; case .tennis, .beach: 15; case .pet, .shock: 5 }
    }
    var animation: String {
        switch self { case .berry, .apple: "eat"; case .tennis, .beach, .pet: "attack"; case .shock: "shock" }
    }
    var icon: String {
        switch self { case .berry: "🫐"; case .apple: "🍎"; case .tennis: "🎾"; case .beach: "🏐"; case .pet: "♥"; case .shock: "⚡️" }
    }
    var comment: String {
        switch self {
        case .berry: "Mmm, berries! Thank you!"
        case .apple: "Crunch! That hit the spot."
        case .tennis: "Your serve! Let's play!"
        case .beach: "Boing! One more bounce!"
        case .pet: "Happy to be your buddy."
        case .shock: "Pika pika! ⚡️"
        }
    }
}

/// Separate, versioned preferences. Never modifies the notch party, Pokédex, or account data.
@MainActor
final class BuddyCareStore: ObservableObject {
    @Published private(set) var profiles: [String: BuddyProfile]
    @Published private(set) var selectedID = "0700"
    @Published var menuOpen = false
    @Published private(set) var action: BuddyCareAction?
    @Published private(set) var actionStarted = Date.distantPast
    @Published private(set) var speech: String?
    private var actionUntil = Date.distantPast
    private var speechUntil = Date.distantPast
    private let defaults: UserDefaults
    static let storageKey = "desktopBuddyCare.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([String: BuddyProfile].self, from: data) {
            profiles = saved.mapValues { p in
                var p = p; p.xp = min(9900, max(0, p.xp)); p.nickname = String(p.nickname.prefix(24)); return p
            }
        } else { profiles = [:] }
    }

    var profile: BuddyProfile { profiles[selectedID] ?? BuddyProfile() }
    var sleeping: Bool { profile.sleepingSince != nil }
    var blocksMovement: Bool { sleeping || menuOpen || action != nil }

    func select(_ id: String) {
        guard id != selectedID else { return }
        selectedID = id
        action = nil; speech = nil; menuOpen = false
    }

    func rename(_ name: String) {
        var p = profile
        p.nickname = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        save(p)
    }

    func perform(_ selectedAction: BuddyCareAction, now: Date = Date()) {
        guard !sleeping else { say("Zzz… wake me up first.", now: now); return }
        action = selectedAction; actionStarted = now; actionUntil = now.addingTimeInterval(5)
        let oldLevel = profile.level
        reward(selectedAction.xp, now: now)
        say(profile.level > oldLevel ? "Level \(profile.level)! We make a great team!" : selectedAction.comment, now: now)
        menuOpen = false
    }

    func sleep(now: Date = Date()) {
        guard !sleeping else { return }
        var p = profile; p.sleepingSince = now; save(p)
        action = nil; menuOpen = false
        say("Time for a little nap. Zzz…", now: now)
    }

    func wake(now: Date = Date()) {
        guard let since = profile.sleepingSince else { return }
        var p = profile; p.sleepingSince = nil; save(p)
        if now.timeIntervalSince(since) >= 60 { reward(5, now: now) }
        menuOpen = false
        say("All rested! Ready when you are.", now: now)
    }

    func say(_ message: String, now: Date = Date()) {
        speech = message; speechUntil = now.addingTimeInterval(8)
    }

    func tick(now: Date = Date()) {
        if action != nil && now >= actionUntil { action = nil }
        if speech != nil && now >= speechUntil { speech = nil }
    }

    func quiet() { if speech != nil { speech = nil } }

    private func reward(_ amount: Int, now: Date) {
        var p = profile
        // Care always works; XP is awarded at most once every 10 seconds, across actions.
        if let last = p.lastReward, now.timeIntervalSince(last) < 10 { return }
        p.xp = min(9900, max(0, p.xp) + amount); p.lastReward = now; save(p)
    }

    private func save(_ profile: BuddyProfile) {
        profiles[selectedID] = profile
        if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: Self.storageKey) }
    }
}
