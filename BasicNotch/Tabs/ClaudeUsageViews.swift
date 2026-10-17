import SwiftUI

/// Header chip: Claude Code usage in the current 5-hour window, with details on click.
struct ClaudeUsageChip: View {
    @ObservedObject var usage: ClaudeUsageService
    @State private var showDetails = false

    private var tint: Color {
        switch usage.fraction {
        case ..<0.6: Color(red: 0.85, green: 0.47, blue: 0.34)  // Claude orange
        case ..<0.85: .yellow
        default: .red
        }
    }

    var body: some View {
        if usage.available {
            Button { showDetails.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle").font(.system(size: 10, weight: .bold)).foregroundStyle(tint)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule().fill(tint).frame(width: 46 * (usage.isActive ? usage.fraction : 0))
                    }
                    .frame(width: 46, height: 5)
                    Text(usage.isActive ? "\(Int(usage.fraction * 100))%" : "idle")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Claude Code usage")
            .popover(isPresented: $showDetails, arrowEdge: .bottom) {
                ClaudeUsageDetails(usage: usage, tint: tint)
            }
        }
    }
}

struct ClaudeUsageDetails: View {
    @ObservedObject var usage: ClaudeUsageService
    let tint: Color

    var body: some View {
        let s = usage.snapshot
        VStack(alignment: .leading, spacing: 10) {
            Label("Claude Code usage", systemImage: "sparkle").font(.headline).foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Current 5-hour window")
                    Spacer()
                    Text(ClaudeUsageService.tokens(s.blockTokens) + " tokens").monospacedDigit()
                }
                ProgressView(value: usage.isActive ? usage.fraction : 0).tint(tint)
                if let end = s.blockEnd, usage.isActive {
                    Text("Resets \(end.formatted(date: .omitted, time: .shortened)) · \(Self.remaining(until: end)) left")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("No active window — it starts with your next message").font(.caption).foregroundStyle(.secondary)
                }
            }

            Divider()
            row("Today", ClaudeUsageService.tokens(s.todayTokens))
            row("Last 7 days", ClaudeUsageService.tokens(s.weekTokens))
            row("Messages (7 days)", "\(s.weekMessages)")
            if !s.topModel.isEmpty { row("Most used model", s.topModel) }

            Text(UserDefaults.standard.integer(forKey: "claudeBlockLimit") > 0
                 ? "Bar is measured against your limit in Settings."
                 : "Bar is measured against your busiest window this week. Set a token limit in Settings for your plan.")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
        .padding(16)
        .frame(width: 290)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
    }

    private static func remaining(until end: Date) -> String {
        let minutes = max(0, Int(end.timeIntervalSinceNow / 60))
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}
