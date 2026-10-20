import SwiftUI

/// Shelf: dropped files on the left, recently copied text on the right.
struct ShelfTab: View {
    @ObservedObject var tray: FileTrayService
    @ObservedObject var clipboard: ClipboardService
    @ObservedObject var tumblr: TumblrService
    @ObservedObject var cards: CardIngestService
    let openSettings: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 8) {
                if cards.card != nil || cards.lastImport != nil {
                    CardIngestPanel(cards: cards, tray: tray)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                Group {
                if tumblr.isComposing {
                    TumblrCompose(tumblr: tumblr, tray: tray, openSettings: openSettings)
                } else {
                    FilesTab(tray: tray, tumblr: tumblr)
                }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.snappy, value: cards.card)
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
            ClipboardTab(clipboard: clipboard)
                .frame(width: 300)
        }
    }
}

/// A camera card is in: how many shots are new, one-click import with progress, then hand-off.
struct CardIngestPanel: View {
    @ObservedObject var cards: CardIngestService
    @ObservedObject var tray: FileTrayService

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sdcard.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Color.orange.opacity(0.15)))

            VStack(alignment: .leading, spacing: 3) {
                Text(cards.card?.name ?? "Card removed").font(.system(size: 12, weight: .bold)).lineLimit(1)
                if let progress = cards.progress {
                    ProgressView(value: progress).tint(.orange).frame(maxWidth: 220)
                    Text("Copying \(cards.copiedCount) of \(cards.card?.newFiles.count ?? 0)…")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                } else {
                    Text(status).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                if let error = cards.error { Text(error).font(.system(size: 10)).foregroundStyle(.red).lineLimit(1) }
            }

            Spacer(minLength: 6)

            if cards.progress != nil {
                Button("Stop") { cards.cancelImport() }
            } else {
                if let card = cards.card, !card.newFiles.isEmpty {
                    Button { cards.importNew() } label: { Label("Import \(card.newFiles.count)", systemImage: "square.and.arrow.down") }
                        .buttonStyle(PillButtonStyle())
                }
                if cards.lastImport != nil {
                    Button { cards.revealLastImport() } label: { Label("Show", systemImage: "folder") }
                }
                if cards.card != nil {
                    Button { cards.eject() } label: { Image(systemName: "eject.fill") }.help("Eject card")
                }
            }
        }
        .font(.system(size: 11))
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.orange.opacity(0.35), lineWidth: 1))
    }

    private var status: String {
        guard let card = cards.card else {
            return cards.lastImport.map { "Imported \($0.count) to Pictures › Card Imports" } ?? ""
        }
        if card.isScanning { return "Looking for photos…" }
        if let last = cards.lastImport, card.newFiles.isEmpty { return "Imported \(last.count) · all caught up" }
        if card.newFiles.isEmpty { return "\(card.total) photos and videos · all imported already" }
        return "\(card.total) photos and videos · \(card.newFiles.count) new"
    }
}

struct FilesTab: View {
    @ObservedObject var tray: FileTrayService
    @ObservedObject var tumblr: TumblrService

    var body: some View {
        if tray.files.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 30)).foregroundStyle(.secondary)
                Text("Drop files here").font(.headline)
                Text("Drag anything onto the notch to keep it handy, then drag it out wherever you need it.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, dash: [6])))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(tray.selected.isEmpty ? "\(tray.files.count) item\(tray.files.count == 1 ? "" : "s") · click to select"
                         : "\(tray.selected.count) selected")
                        .font(.caption.bold()).foregroundStyle(.secondary)
                    Spacer()
                    Button { tumblr.isComposing = true } label: { Label("Tumblr", systemImage: "paperplane.fill") }
                        .disabled(tray.images.isEmpty)
                        .help(tray.images.isEmpty ? "Add images to the shelf to post them" : "Post images to Tumblr")
                    Button { tray.airDrop(tray.files) } label: { Label("AirDrop", systemImage: "airplayaudio") }
                    Button { tray.clear() } label: { Label("Clear", systemImage: "trash") }
                }
                .buttonStyle(PillButtonStyle())

                HScroll {
                    HStack(spacing: 10) {
                        ForEach(tray.files, id: \.self) { FileTile(url: $0, tray: tray) }
                    }
                }
            }
        }
    }
}

struct FileTile: View {
    let url: URL
    @ObservedObject var tray: FileTrayService
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 48, height: 48)
            Text(url.lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.center)
        }
        .padding(8)
        .frame(width: 88)
        .card(highlighted: hovering)
        .overlay {
            if tray.selected.contains(url) {
                RoundedRectangle(cornerRadius: 14).strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .overlay(alignment: .topLeading) {
            if tray.selected.contains(url) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 14))
                    .foregroundStyle(.white, Color.accentColor).offset(x: -4, y: -4)
            }
        }
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { tray.remove(url) } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.white, .gray)
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }
        }
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { tray.open(url) }
        .onTapGesture { tray.toggleSelection(url) }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { tray.open(url) }
            Button("Show in Finder") { tray.reveal(url) }
            Button("AirDrop") { tray.airDrop([url]) }
            Divider()
            Button("Remove from Shelf") { tray.remove(url) }
        }
        .help(url.path)
    }
}

// MARK: - Header widgets

struct NextEventChip: View {
    @ObservedObject var calendar: CalendarService

    var body: some View {
        if let event = calendar.next {
            Button { calendar.openCalendarApp() } label: {
                HStack(spacing: 6) {
                    Capsule().fill(event.color).frame(width: 3, height: 14)
                    Text(event.title).lineLimit(1)
                    Text(timeText(event)).foregroundStyle(.secondary)
                }
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.08)))
                .frame(maxWidth: 150)
            }
            .buttonStyle(.plain)
            .help("Open Calendar")
        }
    }

    private func timeText(_ e: CalendarService.Event) -> String {
        let now = Date()
        if e.start <= now { return "now" }
        let minutes = Int(e.start.timeIntervalSince(now) / 60)
        if minutes < 60 { return "in \(minutes)m" }
        return e.start.formatted(date: .omitted, time: .shortened)
    }
}

struct BatteryBadge: View {
    let level: Int
    let charging: Bool
    let compact: Bool

    private var symbol: String {
        if charging { return "battery.100percent.bolt" }
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    private var tint: Color {
        if charging { return .green }
        return level <= 20 ? .red : .white
    }

    var body: some View {
        HStack(spacing: 3) {
            Text("\(level)%").font(.system(size: compact ? 10 : 11, weight: .semibold).monospacedDigit())
            Image(systemName: symbol)
                .symbolRenderingMode(.palette)
                .foregroundStyle(tint, Color.white.opacity(0.5))
                .font(.system(size: compact ? 12 : 14))
        }
        .padding(.horizontal, compact ? 0 : 4)
    }
}
