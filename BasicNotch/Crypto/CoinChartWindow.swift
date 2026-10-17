import SwiftUI
import Charts
import AppKit

// MARK: - Window management

/// One floating chart window per coin. Windows start small and expand to the full chart view.
@MainActor
final class CoinWindowManager {
    static let shared = CoinWindowManager()
    private var windows: [String: CoinChartPanel] = [:]

    func open(coinID: String) {
        if let existing = windows[coinID] {
            existing.orderFrontRegardless()
            return
        }
        let panel = CoinChartPanel(model: CoinDetailModel(coinID: coinID)) { [weak self] in
            self?.windows[coinID] = nil
        }
        let screen = NotchScreen.selected
        if let visible = screen?.visibleFrame {
            let cascade = CGFloat(windows.count) * 28
            let size = CoinChartPanel.compactSize
            // Drop it just under the notch, a bit to the right, cascading additional windows.
            panel.setFrameOrigin(NSPoint(x: visible.midX + 200 + cascade,
                                         y: visible.maxY - size.height - 16 - cascade))
        }
        windows[coinID] = panel
        panel.orderFrontRegardless()
    }
}

final class CoinChartPanel: NSPanel {
    static let compactSize = CGSize(width: 300, height: 176)
    static let expandedSize = CGSize(width: 440, height: 540)

    private let model: CoinDetailModel
    private let onClose: () -> Void

    @MainActor
    init(model: CoinDetailModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        super.init(contentRect: NSRect(origin: .zero, size: Self.compactSize),
                   styleMask: [.borderless, .nonactivatingPanel, .resizable],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let root = CoinChartView(model: model,
                                 onToggleExpand: { [weak self] in self?.toggleExpanded() },
                                 onClose: { [weak self] in self?.close() })
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }

    override func close() {
        MainActor.assumeIsolated { model.stop() }
        super.close()
        onClose()
    }

    @MainActor
    private func toggleExpanded() {
        model.expanded.toggle()
        let size = model.expanded ? Self.expandedSize : Self.compactSize
        var newFrame = frame
        let top = newFrame.maxY
        newFrame.size = size
        newFrame.origin.y = top - size.height  // grow downward from the top edge
        if let visible = screen?.visibleFrame {
            newFrame.origin.x = min(max(newFrame.origin.x, visible.minX), visible.maxX - size.width)
            newFrame.origin.y = max(newFrame.origin.y, visible.minY)
        }
        setFrame(newFrame, display: true, animate: true)
        invalidateShadow()
    }
}

// MARK: - Views

private let upGreen = Color(red: 0.36, green: 0.85, blue: 0.40)
private let downRed = Color(red: 0.96, green: 0.33, blue: 0.33)

struct CoinChartView: View {
    @ObservedObject var model: CoinDetailModel
    let onToggleExpand: () -> Void
    let onClose: () -> Void

    private var tint: Color { model.isUp ? upGreen : downRed }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: model.expanded ? 26 : 20, style: .continuous)
                .fill(Color(red: 0.05, green: 0.05, blue: 0.08))
                .overlay(RoundedRectangle(cornerRadius: model.expanded ? 26 : 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08)))

            if model.expanded { expanded } else { compact }
        }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .animation(.snappy, value: model.expanded)
    }

    // MARK: Compact

    private var compact: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                CoinIcon(url: model.coin.flatMap { URL(string: $0.image) }, size: 22)
                Text(model.coin?.symbol.uppercased() ?? "…").font(.headline)
                Text(model.coin?.name ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                PriceAlertButton(model: model, size: 22)
                WindowButton(icon: "arrow.up.left.and.arrow.down.right", action: onToggleExpand)
                WindowButton(icon: "xmark", action: onClose)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(model.format(model.hover?.value ?? model.currentValue))
                    .font(.system(size: 22, weight: .bold).monospacedDigit())
                ChangeLabel(model: model, tint: tint, showAmount: false)
            }
            CoinChart(model: model, tint: tint, detailed: false)
        }
        .padding(14)
    }

    // MARK: Expanded (the full layout)

    private var expanded: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                CoinIcon(url: model.coin.flatMap { URL(string: $0.image) }, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.coin?.symbol.uppercased() ?? "…").font(.system(size: 26, weight: .bold))
                    HStack(spacing: 6) {
                        Text(model.coin?.name ?? "").font(.title3).foregroundStyle(.secondary)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(model.coinID, forType: .string)
                        } label: {
                            Image(systemName: "square.on.square").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy CoinGecko ID")
                    }
                }
                Spacer()
                PriceAlertButton(model: model, size: 30)
                WindowButton(icon: "square.and.arrow.up", size: 30) {
                    if let url = URL(string: "https://www.coingecko.com/en/coins/\(model.coinID)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .help("Open on CoinGecko")
                WindowButton(icon: "arrow.down.right.and.arrow.up.left", size: 30, action: onToggleExpand)
                WindowButton(icon: "xmark", size: 30, action: onClose)
            }
            .padding(.bottom, 22)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.format(model.hover?.value ?? model.currentValue))
                        .font(.system(size: 38, weight: .bold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    ChangeLabel(model: model, tint: tint, showAmount: true)
                }
                Spacer()
                Button {
                    model.showMarketCap.toggle()
                    model.hover = nil
                } label: {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                            Text(model.showMarketCap ? CryptoFormat.price(model.alternateValue) : CryptoFormat.compact(model.alternateValue))
                                .font(.title2.bold().monospacedDigit())
                        }
                        Text(model.showMarketCap ? "Price" : "Market cap").foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .help("Swap price and market cap chart")
            }

            CoinChart(model: model, tint: tint, detailed: true)
                .padding(.vertical, 18)

            HStack(spacing: 2) {
                ForEach(ChartRange.allCases) { r in
                    Button { model.range = r } label: {
                        Text(r.rawValue)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(model.range == r ? Color.white : Color.secondary)
                            .frame(width: 42, height: 32)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(model.range == r ? 0.12 : 0)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Divider().frame(height: 26).padding(.horizontal, 6)
                Button { model.candles.toggle() } label: {
                    Image(systemName: model.candles ? "chart.xyaxis.line" : "chart.bar.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(model.candles ? Color.white : upGreen)
                        .frame(width: 34, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.candles ? "Line chart" : "Candlesticks")
                .disabled(model.showMarketCap)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(22)
    }
}

struct ChangeLabel: View {
    @ObservedObject var model: CoinDetailModel
    let tint: Color
    let showAmount: Bool

    var body: some View {
        let change = model.change
        HStack(spacing: 6) {
            Image(systemName: change.amount >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                .font(.system(size: showAmount ? 11 : 9))
            if showAmount {
                Text("\(model.format(abs(change.amount))) (\(String(format: "%.2f", abs(change.percent)))%)")
            } else {
                Text(String(format: "%.2f%%", abs(change.percent)))
            }
            Text(model.hover.map { $0.date.formatted(date: .abbreviated, time: .shortened) } ?? model.range.label)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: showAmount ? 17 : 12, weight: .semibold).monospacedDigit())
        .foregroundStyle(tint)
    }
}

struct CoinChart: View {
    @ObservedObject var model: CoinDetailModel
    let tint: Color
    let detailed: Bool

    var body: some View {
        let showCandles = detailed && model.candles && !model.showMarketCap && !model.ohlc.isEmpty
        let values = showCandles ? model.ohlc.flatMap { [$0.low, $0.high] } : model.series.map(\.value)
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.08, hi * 0.0001)
        let domain = (lo - pad)...(hi + pad)

        ZStack {
            if detailed { DotGrid() }

            if model.series.isEmpty && !showCandles {
                if let error = model.error {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                } else {
                    ProgressView().controlSize(.small)
                }
            } else {
                Chart {
                    if showCandles {
                        ForEach(model.ohlc) { c in
                            RuleMark(x: .value("Time", c.date),
                                     yStart: .value("Low", c.low), yEnd: .value("High", c.high))
                                .lineStyle(StrokeStyle(lineWidth: 1))
                                .foregroundStyle(c.isUp ? upGreen : downRed)
                            RectangleMark(x: .value("Time", c.date),
                                          yStart: .value("Open", c.open), yEnd: .value("Close", c.close),
                                          width: .ratio(0.7))
                                .foregroundStyle(c.isUp ? upGreen : downRed)
                        }
                    } else {
                        ForEach(model.series) { p in
                            AreaMark(x: .value("Time", p.date),
                                     yStart: .value("Base", domain.lowerBound),
                                     yEnd: .value("Value", p.value))
                                .foregroundStyle(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0)],
                                                                startPoint: .top, endPoint: .bottom))
                            LineMark(x: .value("Time", p.date), y: .value("Value", p.value))
                                .foregroundStyle(tint)
                                .lineStyle(StrokeStyle(lineWidth: detailed ? 3 : 2, lineCap: .round, lineJoin: .round))
                        }
                        if let last = model.series.last {
                            RuleMark(y: .value("Now", last.value))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 5]))
                                .foregroundStyle(tint.opacity(0.5))
                            if detailed {
                                PointMark(x: .value("Time", last.date), y: .value("Value", last.value))
                                    .symbolSize(1100)
                                    .foregroundStyle(tint.opacity(0.12))
                            }
                            PointMark(x: .value("Time", last.date), y: .value("Value", last.value))
                                .symbolSize(detailed ? 260 : 60)
                                .foregroundStyle(tint)
                                .annotation(position: .trailing, spacing: 10,
                                            overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                    if detailed && model.hover == nil {
                                        Text(model.format(last.value))
                                            .font(.system(size: 13, weight: .bold).monospacedDigit())
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(RoundedRectangle(cornerRadius: 8).fill(tint))
                                    }
                                }
                        }
                    }
                    if let h = model.hover {
                        RuleMark(x: .value("Hover", h.date))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .foregroundStyle(Color.white.opacity(0.35))
                        PointMark(x: .value("Hover", h.date), y: .value("Value", h.value))
                            .symbolSize(detailed ? 120 : 40)
                            .foregroundStyle(.white)
                    }
                }
                .chartYScale(domain: domain)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartLegend(.hidden)
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    guard let plot = proxy.plotFrame else { return }
                                    let x = location.x - geo[plot].origin.x
                                    if let date: Date = proxy.value(atX: x) {
                                        model.hover = model.nearestPoint(to: date)
                                    }
                                case .ended:
                                    model.hover = nil
                                }
                            }
                    }
                }
                .padding(.trailing, detailed ? 6 : 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Subtle dotted backdrop like the screenshot.
struct DotGrid: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 18
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)),
                                 with: .color(.white.opacity(0.07)))
                    x += spacing
                }
                y += spacing
            }
        }
    }
}

struct WindowButton: View {
    let icon: String
    var size: CGFloat = 22
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.5, weight: .bold))
                .frame(width: size, height: size)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.18 : 0.08)))
                .foregroundStyle(hovering ? Color.white : Color.secondary)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Price alerts

struct PriceAlertButton: View {
    @ObservedObject var model: CoinDetailModel
    let size: CGFloat
    @ObservedObject private var store = PriceAlertStore.shared
    @State private var showing = false

    var body: some View {
        let count = store.alerts(for: model.coinID).count
        WindowButton(icon: count > 0 ? "bell.fill" : "bell", size: size) { showing.toggle() }
            .help("Price alerts")
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                PriceAlertEditor(model: model)
            }
    }
}

private struct PriceAlertEditor: View {
    @ObservedObject var model: CoinDetailModel
    @ObservedObject private var store = PriceAlertStore.shared
    @State private var priceText = ""
    @State private var above = true

    var body: some View {
        let symbol = model.coin?.symbol.uppercased() ?? model.coinID
        let price = model.coin?.current_price ?? 0
        VStack(alignment: .leading, spacing: 10) {
            Text("Alert me when \(symbol) goes…").font(.headline)
            Picker("", selection: $above) {
                Text("Above").tag(true)
                Text("Below").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            HStack {
                Text("$")
                TextField("Price", text: $priceText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(Double(priceText) == nil)
            }
            Text("Now \(CryptoFormat.price(price)). It shows in the notch when it hits (checked every 90 seconds).")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            let alerts = store.alerts(for: model.coinID)
            if !alerts.isEmpty {
                Divider()
                ForEach(alerts) { alert in
                    HStack {
                        Image(systemName: alert.above ? "arrow.up" : "arrow.down")
                        Text(CryptoFormat.price(alert.target)).monospacedDigit()
                        Spacer()
                        Button { store.remove(alert) } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 260)
        .onAppear {
            if price > 0 {
                above = true
                priceText = String(format: price >= 1 ? "%.2f" : "%.8f", price * 1.05)
            }
        }
    }

    private func add() {
        guard let target = Double(priceText.replacingOccurrences(of: ",", with: "")), target > 0 else { return }
        store.add(PriceAlert(coinID: model.coinID, symbol: model.coin?.symbol.uppercased() ?? model.coinID,
                             target: target, above: above))
        priceText = ""
    }
}
