import SwiftUI

/// Now and then two wandering Pokémon walk up to each other and battle with their
/// attack, hurt and faint animations. Type matchups matter; the loser faints and returns to its
/// Poké Ball, and a new Pokémon comes along to take its place.
struct Battle {
    enum Phase { case approach, pause, attacking, finished }

    let left: UUID  // stands on the left, facing right
    let right: UUID
    let meetX: CGFloat
    var phase: Phase = .approach
    var timer: Double = 0
    var attackerIsLeft = Bool.random()
    var hitDone = false
    var hp: [UUID: Int]
    let maxHP: [UUID: Int]

    /// Half the distance between the fighters — leaves room for the health bars between them.
    static let gap: CGFloat = 36

    func fraction(_ id: UUID) -> Double {
        Double(max(hp[id] ?? 0, 0)) / Double(max(maxHP[id] ?? 1, 1))
    }
}

extension PokemonParty {
    /// Attacking type → types it's super effective against.
    private static let superEffective: [String: Set<String>] = [
        "fire": ["grass", "ice", "bug", "steel"],
        "water": ["fire", "ground", "rock"],
        "grass": ["water", "ground", "rock"],
        "electric": ["water", "flying"],
        "ice": ["grass", "ground", "flying", "dragon"],
        "fighting": ["normal", "ice", "rock", "dark", "steel"],
        "poison": ["grass", "fairy"],
        "ground": ["fire", "electric", "poison", "rock", "steel"],
        "flying": ["grass", "fighting", "bug"],
        "psychic": ["fighting", "poison"],
        "bug": ["grass", "psychic", "dark"],
        "rock": ["fire", "ice", "flying", "bug"],
        "ghost": ["psychic", "ghost"],
        "dragon": ["dragon"],
        "dark": ["psychic", "ghost"],
        "steel": ["ice", "rock", "fairy"],
        "fairy": ["fighting", "dragon", "dark"],
    ]

    func updateBattle(_ dt: Double) {
        battleClock -= dt
        guard var b = battle else {
            if battleClock <= 0 {
                battleClock = .random(in: 25...60)
                if UserDefaults.standard.bool(forKey: "pokemonBattles") { startBattle() }
            }
            return
        }
        guard let li = members.firstIndex(where: { $0.id == b.left }),
              let ri = members.firstIndex(where: { $0.id == b.right }) else {
            endBattle()
            return
        }
        let ai = b.attackerIsLeft ? li : ri
        let di = b.attackerIsLeft ? ri : li

        switch b.phase {
        case .approach:
            // Walk to either side of the meeting point.
            let gap = Battle.gap
            var arrived = true
            for (i, target) in [(li, b.meetX - gap), (ri, b.meetX + gap)] {
                let dx = target - members[i].x
                if abs(dx) > 1 {
                    members[i].direction = dx > 0 ? 1 : -1
                    members[i].mood = .walking
                    members[i].x += members[i].direction * min(abs(dx), 42 * dt)
                    arrived = false
                } else {
                    members[i].mood = .idle
                }
            }
            b.timer += dt
            if arrived || b.timer > 12 {
                members[li].direction = 1
                members[ri].direction = -1
                members[li].mood = .idle
                members[ri].mood = .idle
                b.phase = .pause
                b.timer = 0.9
            }

        case .pause:
            b.timer -= dt
            if b.timer <= 0 {
                members[ai].action = .attack
                members[ai].actionTime = 0
                b.hitDone = false
                b.phase = .attacking
            }

        case .attacking:
            let anim = members[ai].sprites.attack ?? members[ai].sprites.walk
            if !b.hitDone && members[ai].actionTime >= anim.hitTime {
                b.hitDone = true
                // No text during fights — the attack animations and health bars tell the story.
                var damage = 1
                if Self.superEffective[members[ai].type]?.contains(members[di].type) == true {
                    damage += 1
                } else if Double.random(in: 0...1) < 0.15 {
                    damage += 1  // critical hit
                }
                let hp = (b.hp[members[di].id] ?? 1) - damage
                b.hp[members[di].id] = hp
                members[di].x += members[ai].direction * 3  // knockback
                members[di].actionTime = 0
                members[di].action = hp <= 0 ? .faint : .hurt
            }
            if members[ai].actionTime >= anim.total {
                members[ai].action = nil
                if members[di].action == .faint {
                    members[ai].vy = 160  // victory hop
                    b.phase = .finished
                    b.timer = (members[di].sprites.faint?.total ?? 0.6) + 1.2
                } else {
                    b.attackerIsLeft.toggle()
                    b.phase = .pause
                    b.timer = 0.45
                }
            }

        case .finished:
            b.timer -= dt
            if b.timer <= 0 {
                members[di].fainted = true
                members[di].inBattle = false
                members[ai].inBattle = false
                members[ai].moodTimer = 1
                battle = nil
                return
            }
        }

        // Let hurt animations finish, then go back to standing.
        for i in [li, ri] where members[i].action == .hurt {
            if members[i].actionTime >= (members[i].sprites.hurt?.total ?? 0.35) { members[i].action = nil }
        }
        battle = b
    }

    private func startBattle() {
        let ready = members.filter { !$0.leaving && !$0.fainted && !$0.inBattle && $0.catchPhase == nil && $0.scale >= 1 }
        guard ready.count >= 2 else { return }
        let pair = Array(ready.shuffled().prefix(2))
        let (l, r) = pair[0].x <= pair[1].x ? (pair[0], pair[1]) : (pair[1], pair[0])

        // Meet somewhere visible: not hidden behind the camera housing when the notch is closed.
        let edge = max(halfWidth - edgeInset, 20)
        var meet = (l.x + r.x) / 2
        let wingInner = notchHalfWidth + Battle.gap + 16
        if !isOpen && abs(meet) < wingInner {
            let side: CGFloat = meet == 0 ? (Bool.random() ? 1 : -1) : (meet > 0 ? 1 : -1)
            meet = side * wingInner
        }
        meet = min(max(meet, -(edge - Battle.gap - 4)), edge - Battle.gap - 4)

        for id in [l.id, r.id] {
            guard let i = members.firstIndex(where: { $0.id == id }) else { continue }
            members[i].inBattle = true
            members[i].vy = 120
            members[i].bubble = nil
        }
        let hp = [l.id: Int.random(in: 3...5), r.id: Int.random(in: 3...5)]
        battle = Battle(left: l.id, right: r.id, meetX: meet, hp: hp, maxHP: hp)
    }

    func endBattle() {
        for i in members.indices where members[i].inBattle {
            members[i].inBattle = false
            if members[i].action != .faint { members[i].action = nil }
        }
        battle = nil
    }
}
