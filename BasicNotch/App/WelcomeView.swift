import SwiftUI

struct WelcomeView: View {
    let onGuide: () -> Void
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Welcome to BasicNotch", systemImage: "sparkles")
                .font(.largeTitle.bold())
            Text("Your music, files, weather and everyday tools — at the top of your Mac.")
                .font(.title3).foregroundStyle(.secondary)
            if Bundle.main.object(forInfoDictionaryKey: "BasicNotchLocalPreview") as? Bool != false {
                Label("Local preview: this build has not been notarized by Apple. macOS may show a security warning. Only install a copy from a source you trust.", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
            }
            Divider()
            Label("Hover at the top center of your screen to open the notch. Pin it to keep it open.", systemImage: "cursorarrow")
            Label("Use the sparkle menu in the menu bar for Settings, display selection, help and Quit.", systemImage: "menubar.rectangle")
            Label("Start with Focus or the Shelf. Set your weather city and favorite teams in Settings.", systemImage: "slider.horizontal.3")
            Label("Music controls, Calendar and the camera may ask for macOS permissions. You can decline and use other tools.", systemImage: "hand.raised")
            Text("The Shelf keeps file references; clipboard text stays in memory until you quit. Online widgets contact their data providers. PlayStation and Tumblr are optional account connections. Includes 18 Pokémon with SpriteCollab credits in the guide.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("User Guide & Features", action: onGuide)
                Spacer()
                Button("Open My Notch", action: onStart).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 530)
        .fixedSize(horizontal: false, vertical: true)
    }
}
