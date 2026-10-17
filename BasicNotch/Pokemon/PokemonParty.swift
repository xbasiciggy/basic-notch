import SwiftUI
import QuartzCore

struct Pokemon: Identifiable {
    enum Mood { case walking, idle }
    enum Action { case attack, hurt, faint }
    enum CatchPhase { case throwing, wobbling, caught, escaped }

    let id = UUID()
    let rosterID: String
    let dex: Int
    let shiny: Bool
    let name: String
    let type: String
    let sprites: MonSprites
    var x: CGFloat
    var y: CGFloat = 0
    var vy: CGFloat = 0
    var direction: CGFloat
    var speed: CGFloat
    var mood: Mood = .walking
    var moodTimer: Double
    var animTime: Double = 0
    var bubble: String?
    var bubbleTimer: Double = 0
    var scale: Double = 0
    var leaving = false
    /// One-shot battle animation playing right now (attack, hurt or faint).
    var action: Action?
    var actionTime: Double = 0
    var inBattle = false
    var fainted = false
    var catchPhase: CatchPhase?
    var catchTime: Double = 0
    var catchWillSucceed = false
}

/// Stream Avatars–style wandering party: Pokémon spawn, walk, idle, hop, chatter, dance to music,
/// react to clicks, and every few minutes one wanders off and a new one arrives.
/// Now and then two of them meet up and battle (see PokemonBattle.swift).
@MainActor
final class PokemonParty: ObservableObject {
    @Published var members: [Pokemon] = []

    var musicPlaying = false
    var isOpen = false
    var halfWidth: CGFloat = 200
    var edgeInset: CGFloat = 12
    var notchHalfWidth: CGFloat = 95
    /// Current weather (Open-Meteo code + day/night) so the right types show up.
    var weather: (code: Int, isDay: Bool)?
    /// While a focus timer runs, the party cheers you on.
    var focusMode = false

    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    private var spawnCooldown = 0.0
    private var rotationClock = Double.random(in: 90...180)
    var battle: Battle?
    var battleClock = Double.random(in: 10...20)

    private var targetCount: Int {
        let d = UserDefaults.standard
        return d.bool(forKey: "showPokemon") ? min(max(d.integer(forKey: "pokemonCount"), 0), 6) : 0
    }

    func start() {
        guard timer == nil else { return }
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func respawnAll() {
        battle = nil
        members.removeAll()
        spawnCooldown = 0
    }

    /// Click: throw a Poké Ball (or, with catching off, say hi).
    func tap(_ id: UUID) {
        guard let i = members.firstIndex(where: { $0.id == id }) else { return }
        guard UserDefaults.standard.bool(forKey: "pokemonCatching"),
              !members[i].inBattle, !members[i].leaving, !members[i].fainted, members[i].catchPhase == nil else {
            poke(id)
            return
        }
        let legendary: Set<Int> = [144, 145, 146, 150, 151, 243, 244, 245, 249, 250, 251, 377, 378, 379, 380, 381, 382, 383,
                                   384, 385, 386, 480, 481, 482, 483, 484, 485, 486, 487, 488, 491, 492, 493, 494, 638, 639,
                                   640, 641, 642, 643, 644, 645, 646, 647, 648, 649, 716, 717, 718, 785, 786, 787, 788, 789,
                                   790, 791, 792, 800, 888, 889, 890, 1007, 1008]
        var chance = 0.65
        if members[i].shiny { chance = 0.4 }
        if legendary.contains(members[i].dex) { chance = 0.3 }
        members[i].catchWillSucceed = Double.random(in: 0...1) < chance
        members[i].catchPhase = .throwing
        members[i].catchTime = 0
        members[i].bubble = nil
    }

    /// Make everyone react to something (a goal, a price jump, a finished timer…).
    func react(_ text: String, happy: Bool) {
        for i in members.indices where !members[i].inBattle && !members[i].fainted && members[i].catchPhase == nil {
            if happy && members[i].y == 0 { members[i].vy = .random(in: 130...190) }
            say(&members[i], i == 0 ? text : (happy ? ["🎉", "✨", "❗", "🙌"] : ["😢", "💧", "…"]).randomElement()!)
            members[i].bubbleTimer = 3.5
        }
    }

    func poke(_ id: UUID) {
        guard let i = members.firstIndex(where: { $0.id == id }) else { return }
        if members[i].inBattle { return }  // no bubbles mid-fight
        if members[i].y == 0 { members[i].vy = 170 }
        let reactions = ["\(members[i].name)!", "❤️", "❗", "😆"]
        say(&members[i], members[i].dex == 25 ? "Pika pika!" : reactions.randomElement()!)
    }

    func release(_ id: UUID) {
        if members.first(where: { $0.id == id })?.inBattle == true { endBattle() }
        guard let i = members.firstIndex(where: { $0.id == id }) else { return }
        members[i].leaving = true
        members[i].mood = .walking
        members[i].direction = members[i].x >= 0 ? 1 : -1
        members[i].speed *= 1.8
        say(&members[i], "👋")
    }

    // MARK: - Simulation

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.1)
        lastTick = now

        // Keep the party at the target size.
        spawnCooldown -= dt
        let staying = members.filter { !$0.leaving && !$0.fainted }
        if staying.count < targetCount, spawnCooldown <= 0 {
            spawnOne()
        } else if staying.count > targetCount, let extra = staying.first {
            release(extra.id)
        }

        // Every so often someone wanders off and a new Pokémon shows up.
        rotationClock -= dt
        if rotationClock <= 0 {
            rotationClock = .random(in: 90...180)
            if let leaver = staying.filter({ !$0.inBattle && $0.catchPhase == nil }).randomElement() { release(leaver.id) }
        }

        updateBattle(dt)

        guard !members.isEmpty else { return }
        let edge = max(halfWidth - edgeInset, 20)

        for i in members.indices {
            var p = members[i]
            p.animTime += dt
            p.actionTime += dt
            if p.catchPhase != nil {
                updateCatch(&p, dt)
                members[i] = p
                continue
            }

            if p.bubbleTimer > 0 {
                p.bubbleTimer -= dt
                if p.bubbleTimer <= 0 { p.bubble = nil }
            }

            // Hop physics.
            if p.y > 0 || p.vy > 0 {
                p.vy -= 650 * dt
                p.y = max(0, p.y + p.vy * dt)
                if p.y == 0 { p.vy = 0 }
            }

            if !p.leaving && !p.inBattle && !p.fainted {
                if musicPlaying && p.y == 0 && Double.random(in: 0...1) < 0.05 { p.vy = 95 }  // dance!

                p.moodTimer -= dt
                if p.moodTimer <= 0 {
                    // Never stop to idle while hidden behind the camera housing.
                    let hidden = !isOpen && abs(p.x) < notchHalfWidth
                    if hidden || Double.random(in: 0...1) < 0.65 {
                        p.mood = .walking
                        if Double.random(in: 0...1) < 0.4 { p.direction *= -1 }
                    } else {
                        p.mood = .idle
                    }
                    p.moodTimer = .random(in: 1.5...5)
                }
                if p.y == 0 && Double.random(in: 0...1) < 0.002 { p.vy = 150 }
                if p.bubble == nil && Double.random(in: 0...1) < 0.0012 { chatter(&p) }
            }

            // Battlers are moved by the battle itself.
            if (p.mood == .walking && !p.inBattle && !p.fainted) || p.leaving {
                p.x += p.direction * p.speed * dt
            }

            if abs(p.x) >= edge {
                p.x = edge * (p.x > 0 ? 1 : -1)
                if !p.leaving { p.direction = p.x > 0 ? -1 : 1 }
            }

            // Grow in on spawn; shrink away at the edge when leaving.
            if p.fainted {
                p.scale -= dt * 1.5  // back into its Poké Ball
            } else if p.leaving && abs(p.x) >= edge {
                p.scale -= dt * 4
            } else {
                p.scale = min(1, p.scale + dt * 2.5)
            }

            members[i] = p
        }
        members.removeAll { ($0.leaving || $0.fainted) && $0.scale <= 0 }
        members.removeAll { $0.catchPhase == .caught && $0.catchTime > 2.2 }
    }

    private func chatter(_ p: inout Pokemon) {
        var options = ["\(p.name)!", "❤️", "💤", "❗", "✨", "…", "?"]
        if musicPlaying { options += ["♪", "♫", "♪♫"] }
        if focusMode { options = ["📚", "You got this!", "Focus!", "💪", "Keep going!", "🧠"] }
        say(&p, options.randomElement()!)
    }

    func say(_ p: inout Pokemon, _ text: String) {
        p.bubble = text
        p.bubbleTimer = 2.5
    }

    // MARK: - Spawning

    private func spawnOne() {
        spawnCooldown = 0.6
        let d = UserDefaults.standard
        let maxDex = d.integer(forKey: "pokemonMaxDex")
        let pool = PokeBrawlSprites.roster.filter { maxDex <= 0 || $0.dex <= maxDex }
        // Half the time, pick a Pokémon that suits the weather outside.
        let favored = favoredTypes()
        let weatherPool = pool.filter { favored.contains($0.type) }
        let source = (!weatherPool.isEmpty && Bool.random()) ? weatherPool : pool
        guard let entry = source.randomElement() else {
            spawnCooldown = 10
            return
        }
        // Shiny (or Galar form, which the sprite data keeps in the shiny slot) when the odds hit.
        let shiny = entry.shiny != nil && Int.random(in: 1...max(d.integer(forKey: "shinyOdds"), 1)) == 1
        guard let sprites = PokeBrawlSprites.sprites(for: entry, shiny: shiny) else {
            spawnCooldown = 1
            return
        }
        let edge = max(halfWidth - edgeInset, 20)
        let side: CGFloat = Bool.random() ? 1 : -1
        let inner = min(notchHalfWidth + 10, edge)
        var p = Pokemon(rosterID: entry.id, dex: entry.dex, shiny: shiny, name: entry.name, type: entry.type, sprites: sprites,
                        x: side * CGFloat.random(in: inner...edge),
                        direction: Bool.random() ? 1 : -1,
                        speed: .random(in: 14...28),
                        moodTimer: .random(in: 1...3))
        say(&p, shiny ? "✨" : "\(entry.name)!")
        members.append(p)
    }

    private func favoredTypes() -> Set<String> {
        guard UserDefaults.standard.bool(forKey: "weatherPokemon"), let w = weather else { return [] }
        switch w.code {
        case 95...99: return ["electric", "dragon"]
        case 71...77, 85, 86: return ["ice"]
        case 51...67, 80...82: return ["water", "electric"]
        case 45, 48: return ["ghost", "psychic"]
        default: break
        }
        if !w.isDay { return ["ghost", "dark", "psychic"] }
        return w.code == 3 ? ["normal", "flying", "rock"] : ["fire", "grass", "bug", "flying"]
    }

    // MARK: - Catching

    private func updateCatch(_ p: inout Pokemon, _ dt: Double) {
        p.catchTime += dt
        switch p.catchPhase {
        case .throwing:
            p.scale = max(0, 1 - p.catchTime / 0.35)  // pulled into the ball
            if p.catchTime >= 0.45 { p.catchPhase = .wobbling; p.catchTime = 0 }
        case .wobbling:
            p.scale = 0
            if p.catchTime >= 1.8 {
                p.catchTime = 0
                if p.catchWillSucceed {
                    p.catchPhase = .caught
                    PokedexStore.shared.record(id: p.rosterID, shiny: p.shiny)
                    say(&p, "Gotcha! \(p.name) was caught!")
                    p.bubbleTimer = 2.2
                } else {
                    p.catchPhase = .escaped
                    say(&p, "💢 Broke free!")
                }
            }
        case .caught:
            break
        case .escaped:
            p.scale = min(1, p.catchTime / 0.25)
            if p.catchTime >= 0.3 {
                p.catchPhase = nil
                p.mood = .walking
                p.speed = min(p.speed * 1.6, 45)
                p.direction = Bool.random() ? 1 : -1
                p.vy = 150
            }
        case nil:
            break
        }
        if p.bubbleTimer > 0 {
            p.bubbleTimer -= dt
            if p.bubbleTimer <= 0 { p.bubble = nil }
        }
    }
}
