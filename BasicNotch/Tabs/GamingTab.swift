import SwiftUI

struct GamingTab: View {
    @ObservedObject var psn: PSNService

    var body: some View {
        if !psn.isSignedIn {
            VStack(spacing: 10) {
                Image(systemName: "playstation.logo").font(.system(size: 32))
                Text("See what your PlayStation friends are playing").font(.headline)
                Button {
                    psn.showLogin()
                } label: {
                    if psn.isLoading {
                        ProgressView().controlSize(.mini)
                    } else {
                        Label("Sign in with PlayStation", systemImage: "person.crop.circle")
                    }
                }
                .buttonStyle(PillButtonStyle())
                if let error = psn.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                } else {
                    Text("You sign in on Sony's own page. Your password never touches BasicNotch.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "playstation.logo")
                    Text("Friends").font(.caption.bold())
                    Text("· \(psn.onlineCount) online").font(.caption).foregroundStyle(.green)
                    Spacer()
                    if let error = psn.error { Text(error).font(.caption2).foregroundStyle(.red).lineLimit(1) }
                    Button { Task { await psn.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Refresh")
                }

                if onlineFriends.isEmpty {
                    if psn.isLoading {
                        ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        StatusMessage(icon: "person.2", text: "None of your friends are online")
                    }
                } else {
                    HScroll {
                        HStack(spacing: 10) {
                            ForEach(onlineFriends) { FriendCard(friend: $0) }
                        }
                    }
                }
            }
            .contextMenu {
                Button("Sign out of PlayStation") { psn.signOut() }
            }
        }
    }
}

private extension GamingTab {
    /// Only friends who are online right now; anyone in a game comes first (the service sorts them).
    var onlineFriends: [PSNService.Friend] { psn.friends.filter(\.online) }
}

struct FriendCard: View {
    let friend: PSNService.Friend

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AvatarImage(url: friend.avatar, name: friend.onlineID, size: 34)
                .overlay(alignment: .bottomTrailing) {
                    Circle()
                        .fill(friend.online ? Color.green : Color.gray)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.black, lineWidth: 2))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(friend.onlineID).font(.caption.bold()).lineLimit(1)
                    Text(statusText).font(.system(size: 10)).foregroundStyle(friend.online ? Color.green : Color.secondary).lineLimit(1)
                }
            }

            if friend.online, let game = friend.game {
                HStack(spacing: 6) {
                    GameIconImage(url: friend.gameIcon, size: 30)
                    Text(game).font(.system(size: 10, weight: .medium)).lineLimit(2)
                }
            } else {
                Text(friend.online ? "Not in a game" : " ")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .frame(height: 30, alignment: .center)
            }
        }
        .padding(10)
        .frame(width: 160, alignment: .leading)
        .card(highlighted: friend.online && friend.game != nil)
    }

    private var statusText: String {
        if friend.online { return "Online" + (friend.platform.map { " · \($0)" } ?? "") }
        guard let last = friend.lastOnline else { return "Offline" }
        return "Last seen " + last.formatted(.relative(presentation: .named))
    }
}
