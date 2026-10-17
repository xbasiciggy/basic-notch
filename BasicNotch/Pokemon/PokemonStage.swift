import SwiftUI

struct PokemonStage: View {
    @ObservedObject var party: PokemonParty
    let width: CGFloat
    let height: CGFloat
    let edgeInset: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
            ForEach(party.members) { p in
                PokemonSpriteView(pokemon: p, maxHeight: height - 3)
                    .offset(x: p.x, y: -p.y - 1)
                    .onTapGesture { party.tap(p.id) }
                    .contextMenu {
                        Text(p.shiny ? "✨ Shiny \(p.name) · #\(p.dex)" : "\(p.name) · #\(p.dex)")
                        Button("Throw a Poké Ball") { party.tap(p.id) }
                        Button("Say hi") { party.poke(p.id) }
                        Button("Open Pokédex entry") {
                            if let url = URL(string: "https://www.pokemon.com/us/pokedex/\(p.dex)") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        Divider()
                        Button("Release") { party.release(p.id) }
                    }
            }
        }
        .overlay {
            // Health bars between the two fighters once they've squared off.
            if let b = party.battle, b.phase != .approach {
                BattleHUD(left: b.fraction(b.left), right: b.fraction(b.right))
                    .offset(x: b.meetX)
                    .transition(.opacity.combined(with: .scale(scale: 0.6)))
            }
        }
        .animation(.easeOut(duration: 0.25), value: party.battle?.phase == .approach)
        .frame(width: max(width, 0), height: height)
        .onAppear { sync() }
        .onChange(of: width) { _, _ in sync() }
        .onChange(of: edgeInset) { _, _ in sync() }
    }

    private func sync() {
        party.halfWidth = width / 2
        party.edgeInset = edgeInset
    }
}

struct PokemonSpriteView: View {
    let pokemon: Pokemon
    let maxHeight: CGFloat

    var body: some View {
        let sprites = pokemon.sprites
        let scale = sprites.displayScale(maxHeight: maxHeight)
        let facingRight = pokemon.direction > 0
        // Battle animations first; otherwise walk while moving or hopping, idle when standing still.
        let standing = pokemon.mood == .idle && pokemon.y == 0 && !pokemon.leaving
        let anim: SpriteAnim = switch pokemon.action {
        case .attack: sprites.attack ?? sprites.walk
        case .hurt: sprites.hurt ?? sprites.idle ?? sprites.walk
        case .faint: sprites.faint ?? sprites.idle ?? sprites.walk
        case nil: standing ? (sprites.idle ?? sprites.walk) : sprites.walk
        }
        let time = pokemon.action == nil ? pokemon.animTime : pokemon.actionTime

        Image(decorative: anim.frame(at: time, facingRight: facingRight, loop: pokemon.action == nil), scale: 1)
            .resizable()
            .interpolation(scale < 0.8 ? .medium : .none)
            .frame(width: anim.size.width * scale, height: anim.size.height * scale)
            .offset(x: anim.centerOffset * scale)
            .overlay(alignment: facingRight ? .trailing : .leading) {
                if let text = pokemon.bubble {
                    if facingRight {
                        SpeechBubble(text: text).alignmentGuide(HorizontalAlignment.trailing) { d in d[.leading] - 2 }
                    } else {
                        SpeechBubble(text: text).alignmentGuide(HorizontalAlignment.leading) { d in d[.trailing] + 2 }
                    }
                }
            }
            .shadow(color: pokemon.shiny ? .yellow.opacity(0.7) : .clear, radius: 3)
            .scaleEffect(max(pokemon.scale, 0.01), anchor: .bottom)
            .overlay(alignment: .bottom) {
                if let phase = pokemon.catchPhase, phase != .escaped || pokemon.catchTime < 0.15 {
                    CatchBall(phase: phase, time: pokemon.catchTime)
                }
            }
            .contentShape(Rectangle())
    }
}

struct SpeechBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(.black)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(.white.opacity(0.65)))
            .transition(.scale.combined(with: .opacity))
    }
}

/// The Poké Ball during a catch: drops in, wobbles three times, then sparkles (caught) or pops open.
private struct CatchBall: View {
    let phase: Pokemon.CatchPhase
    let time: Double

    var body: some View {
        let drop: CGFloat = phase == .throwing ? CGFloat(max(0, 1 - time / 0.3)) * -24 : 0
        let wobble: Double = phase == .wobbling ? sin(time * .pi / 0.6 * 2) * (time.truncatingRemainder(dividingBy: 0.6) < 0.4 ? 18 : 0) : 0
        PokeBallView()
            .frame(width: 11, height: 11)
            .rotationEffect(.degrees(wobble), anchor: .bottom)
            .offset(y: drop - 1)
            .overlay {
                if phase == .caught {
                    Text("✨").font(.system(size: 9)).offset(y: -9)
                }
            }
            .opacity(phase == .caught ? max(0, 1 - (time - 1.4) / 0.8) : 1)
            .scaleEffect(phase == .escaped ? 1.4 : 1)
    }
}

/// Tiny "▮▮ VS ▮▮" health display that sits between two battling Pokémon.
private struct BattleHUD: View {
    let left: Double
    let right: Double

    var body: some View {
        HStack(spacing: 2) {
            HPBar(fraction: left, drainsTowardLeft: false)
            Text("VS")
                .font(.system(size: 6.5, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
            HPBar(fraction: right, drainsTowardLeft: true)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.black.opacity(0.75)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
    }
}

private struct HPBar: View {
    let fraction: Double
    /// The right fighter's bar empties toward the middle, mirroring the left one.
    let drainsTowardLeft: Bool

    private var color: Color {
        switch fraction {
        case ..<0.25: .red
        case ..<0.55: .yellow
        default: .green
        }
    }

    var body: some View {
        ZStack(alignment: drainsTowardLeft ? .trailing : .leading) {
            Capsule().fill(Color.white.opacity(0.18))
            Capsule().fill(color).frame(width: 14 * max(fraction, 0))
        }
        .frame(width: 14, height: 3.5)
        .animation(.easeOut(duration: 0.35), value: fraction)
    }
}
