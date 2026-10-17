import SwiftUI

// MARK: - Clipboard

struct ClipboardTab: View {
    @ObservedObject var clipboard: ClipboardService
    @State private var copiedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recently copied").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Toggle("Pause", isOn: $clipboard.paused).toggleStyle(.switch).controlSize(.mini).font(.caption)
                Button { clipboard.clear() } label: { Label("Clear", systemImage: "trash") }
                    .buttonStyle(PillButtonStyle())
                    .disabled(clipboard.items.isEmpty)
            }
            if clipboard.items.isEmpty {
                StatusMessage(icon: "doc.on.clipboard",
                              text: clipboard.paused ? "Paused — not recording what you copy" : "Copy some text and it shows up here")
            } else {
                ScrollView(.vertical) {
                    VStack(spacing: 4) {
                        ForEach(clipboard.items) { item in
                            Button {
                                clipboard.copy(item)
                                copiedID = item.id
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Text(item.text.replacingOccurrences(of: "\n", with: " ⏎ "))
                                        .font(.system(size: 11))
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(copiedID == item.id ? "Copied!" : item.date.formatted(.relative(presentation: .named)))
                                        .font(.system(size: 9))
                                        .foregroundStyle(copiedID == item.id ? Color.green : Color.secondary)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Copy") { clipboard.copy(item) }
                                Button("Remove") { clipboard.remove(item) }
                            }
                        }
                    }
                    .padding(.trailing, 6)
                }
                Text("Click to copy again · kept in memory only, never saved to disk · password-manager copies are skipped")
                    .font(.system(size: 9)).foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Focus timer

struct FocusTab: View {
    @ObservedObject var focus: FocusTimer

    var body: some View {
        HStack(spacing: 26) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.12), lineWidth: 8)
                Circle().trim(from: 0, to: focus.progress)
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.25), value: focus.progress)
                VStack(spacing: 2) {
                    Text(focus.label).font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                    Text(focus.isRunning ? "Focusing" : focus.isActive ? "Paused" : "Ready")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 140, height: 140)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    ForEach([5, 15, 25, 45, 60], id: \.self) { m in
                        Chip(title: "\(m)m", selected: !focus.isActive && Int(focus.duration / 60) == m) { focus.set(minutes: m) }
                    }
                }
                HStack(spacing: 10) {
                    Button {
                        focus.isRunning ? focus.pause() : focus.start()
                    } label: {
                        Label(focus.isRunning ? "Pause" : focus.isActive ? "Resume" : "Start",
                              systemImage: focus.isRunning ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(PillButtonStyle())
                    Button { focus.reset() } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                        .buttonStyle(PillButtonStyle())
                        .disabled(!focus.isActive)
                }
                Text("The countdown shows in the closed notch while it runs, and your Pokémon cheer you on. A chime plays when it's done.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
    }
}

// MARK: - System

struct SystemTab: View {
    @ObservedObject var stats: SystemStatsService
    @ObservedObject var battery: BatteryService
    @ObservedObject var airpods: AirPodsService
    @State private var hoveringMemory = false
    @State private var hoveringList = false
    @State private var hideTask: Task<Void, Never>?

    private var showMemoryList: Bool { hoveringMemory || hoveringList }

    var body: some View {
        ZStack(alignment: .trailing) {
            cards
            if showMemoryList {
                MemoryBreakdown(top: stats.topMemory, total: stats.memoryTotal)
                    .onHover { hoveringList = $0; scheduleHide() }
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(.snappy(duration: 0.2), value: showMemoryList)
        .onChange(of: showMemoryList) { _, on in stats.watchTopMemory(on) }
        .onDisappear { stats.watchTopMemory(false) }
    }

    /// Small grace period so moving from the card to the list doesn't flicker it closed.
    private func scheduleHide() {
        hideTask?.cancel()
        guard !hoveringMemory && !hoveringList else { return }
        hideTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            if !Task.isCancelled && !hoveringMemory && !hoveringList { hoveringList = false }
        }
    }

    private var cards: some View {
        HScroll {
            HStack(spacing: 10) {
                StatCard(title: "CPU", icon: "cpu", value: "\(Int(stats.cpu * 100))%", tint: .orange) {
                    Sparkline(values: stats.cpuHistory.count > 1 ? stats.cpuHistory : [0, 0])
                        .stroke(Color.orange, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }
                StatCard(title: "Memory", icon: "memorychip",
                         value: SystemStatsService.bytes(Double(stats.memoryUsed)), tint: .purple) {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: Double(stats.memoryUsed), total: Double(max(stats.memoryTotal, 1))).tint(.purple)
                        Text("of \(SystemStatsService.bytes(Double(stats.memoryTotal))) · hover for details")
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                .onHover { hovering in
                    hoveringMemory = hovering
                    if hovering { hideTask?.cancel() } else { scheduleHide() }
                }
                StatCard(title: "Network", icon: "arrow.up.arrow.down",
                         value: "↓ \(SystemStatsService.bytes(stats.downRate))/s", tint: .cyan) {
                    VStack(alignment: .leading, spacing: 2) {
                        Sparkline(values: stats.downHistory.count > 1 ? stats.downHistory : [0, 0])
                            .stroke(Color.cyan, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                        Text("↑ \(SystemStatsService.bytes(stats.upRate))/s").font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                }
                if battery.hasBattery {
                    StatCard(title: "Battery", icon: battery.isCharging ? "battery.100percent.bolt" : "battery.75percent",
                             value: "\(battery.level)%", tint: battery.level <= 20 ? .red : .green) {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: Double(battery.level), total: 100).tint(battery.level <= 20 ? .red : .green)
                            Text(battery.isCharging ? "Charging" : battery.isPluggedIn ? "Plugged in" : "On battery")
                                .font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(airpods.devices) { device in
                    StatCard(title: device.name, icon: "airpodspro", value: device.lowest.map { "\($0)%" } ?? "—", tint: .white) {
                        Text(device.summary).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
        }
    }
}

private struct StatCard<Detail: View>: View {
    let title: String
    let icon: String
    let value: String
    let tint: Color
    @ViewBuilder let detail: Detail

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon).font(.caption.bold()).foregroundStyle(tint).lineLimit(1)
            Text(value).font(.title3.bold().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.6)
            detail.frame(height: 34)
        }
        .padding(12)
        .frame(width: 150, alignment: .leading)
        .card()
    }
}

/// Floating list of the biggest memory users (shown while hovering the Memory card).
private struct MemoryBreakdown: View {
    let top: [ProcessMemory]
    let total: UInt64

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Using the most memory", systemImage: "memorychip").font(.caption.bold()).foregroundStyle(.purple)
            if top.isEmpty {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 60)
            } else {
                let largest = Double(top.first?.bytes ?? 1)
                ForEach(top) { item in
                    HStack(spacing: 7) {
                        Group {
                            if let path = item.appPath {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable()
                            } else {
                                Image(systemName: "gearshape").resizable().foregroundStyle(.secondary).padding(1)
                            }
                        }
                        .frame(width: 14, height: 14)
                        Text(item.name + (item.processCount > 1 ? " (\(item.processCount))" : ""))
                            .font(.system(size: 10, weight: .medium)).lineLimit(1)
                            .frame(width: 130, alignment: .leading)
                        GeometryReader { geo in
                            Capsule().fill(Color.purple.opacity(0.7))
                                .frame(width: max(3, geo.size.width * Double(item.bytes) / largest))
                        }
                        .frame(height: 5)
                        Text(SystemStatsService.bytes(Double(item.bytes)))
                            .font(.system(size: 10).monospacedDigit()).foregroundStyle(.secondary)
                            .frame(width: 58, alignment: .trailing)
                    }
                }
            }
        }
        .padding(10)
        .frame(width: 330)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.09)))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.6), radius: 10)
    }
}
