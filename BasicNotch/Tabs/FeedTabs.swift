import SwiftUI

// MARK: - Sports

struct SportsTab: View {
    @ObservedObject var sports: SportsService
    @AppStorage("league") private var league = "nfl"
    @AppStorage("favoriteTeams") private var favoriteTeams = ""

    private var favorites: Set<String> {
        Set(favoriteTeams.uppercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
    }

    private var sortedGames: [Game] {
        let rank = ["in": 0, "pre": 1, "post": 2]
        return sports.games.sorted { a, b in
            let fa = isFavorite(a), fb = isFavorite(b)
            if fa != fb { return fa }
            return (rank[a.state] ?? 3) < (rank[b.state] ?? 3)
        }
    }

    private func isFavorite(_ g: Game) -> Bool {
        favorites.contains(g.home.abbr.uppercased()) || favorites.contains(g.away.abbr.uppercased())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HScroll {
                HStack(spacing: 6) {
                    ForEach(League.allCases) { l in
                        Chip(title: l.title, selected: league == l.rawValue) { league = l.rawValue }
                    }
                }
            }

            if sports.games.isEmpty {
                if sports.isLoading {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    StatusMessage(icon: "sportscourt", text: sports.failed ? "Couldn't load scores" : "No games scheduled")
                }
            } else {
                HScroll {
                    HStack(spacing: 10) {
                        ForEach(sortedGames) { GameCard(game: $0, favorite: isFavorite($0)) }
                    }
                }
            }
        }
        .task(id: league) { await sports.refresh() }
    }
}

struct GameCard: View {
    let game: Game
    let favorite: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                if game.isLive {
                    Circle().fill(.red).frame(width: 6, height: 6)
                }
                Text(game.detail)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(game.isLive ? Color.red : Color.secondary)
                    .lineLimit(1)
            }
            row(game.away)
            row(game.home)
        }
        .padding(12)
        .frame(width: 150)
        .card(highlighted: favorite)
    }

    private func row(_ side: Game.Side) -> some View {
        HStack(spacing: 8) {
            AsyncImage(url: side.logo) { $0.resizable().scaledToFit() } placeholder: {
                Circle().fill(Color.white.opacity(0.1))
            }
            .frame(width: 22, height: 22)
            Text(side.abbr).font(.callout.bold())
            Spacer()
            if game.state != "pre" {
                Text(side.score).font(.title3.bold().monospacedDigit())
            }
        }
    }
}
