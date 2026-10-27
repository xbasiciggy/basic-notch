import SwiftUI

struct BuddyCareMenu: View {
    @ObservedObject var care: BuddyCareStore
    let speciesName: String
    let supportsShock: Bool
    var onWeather: () -> Void
    @State private var nickname = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(care.profile.nickname.isEmpty ? speciesName : care.profile.nickname).font(.headline)
                Spacer()
                Text("Level \(care.profile.level)").foregroundStyle(.secondary)
            }
            ProgressView(value: care.profile.levelProgress).tint(.mint)
            HStack {
                TextField("Nickname", text: $nickname).textFieldStyle(.roundedBorder)
                    .onSubmit { care.rename(nickname) }
                Button("Save") { care.rename(nickname) }
            }
            if care.sleeping {
                Label("Sleeping peacefully", systemImage: "moon.zzz.fill")
                Button("Wake up") { care.wake() }.buttonStyle(.borderedProminent)
            } else {
                Text("Food").font(.subheadline.bold())
                HStack {
                    Button("🫐 Berries") { care.perform(.berry) }
                    Button("🍎 Apple") { care.perform(.apple) }
                }
                Text("Play").font(.subheadline.bold())
                HStack {
                    Button("🎾 Tennis ball") { care.perform(.tennis) }
                    Button("🏐 Beach ball") { care.perform(.beach) }
                }
                HStack {
                    Button("♥ Pet") { care.perform(.pet) }
                    if supportsShock { Button("⚡️ Shock") { care.perform(.shock) } }
                }
                Divider()
                HStack {
                    Menu("Sleep") {
                        Button("Take a nap") { care.sleep() }
                        Text("Wake up from this menu whenever you're ready.")
                    }
                    Button("Weather chat", action: onWeather)
                }
            }
            Text("Care earns XP, with a 10-second reward cooldown. No lost progress or neglect penalties.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .buttonStyle(.bordered)
        .padding(16).frame(width: 300)
        .onAppear { nickname = care.profile.nickname }
    }
}
