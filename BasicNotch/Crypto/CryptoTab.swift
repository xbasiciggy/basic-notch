import SwiftUI

struct CryptoTab: View {
    @ObservedObject var crypto: CryptoService
    @AppStorage("cryptoCoins") private var coinIDs = "bitcoin,ethereum,solana,dogecoin"

    private var ids: [String] {
        coinIDs.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if crypto.isSearching {
                CoinSearchView(crypto: crypto, existing: Set(ids), onAdd: add)
            } else {
                HScroll {
                    HStack(spacing: 10) {
                        ForEach(crypto.coins) { coin in
                            CoinCard(coin: coin)
                                .onTapGesture { CoinWindowManager.shared.open(coinID: coin.id) }
                                .contextMenu {
                                    Button("Open Chart") { CoinWindowManager.shared.open(coinID: coin.id) }
                                    Divider()
                                    Button("Remove \(coin.symbol.uppercased())") { remove(coin.id) }
                                }
                        }
                        AddCoinCard { crypto.isSearching = true }
                    }
                }
                HStack {
                    if crypto.coins.isEmpty && !ids.isEmpty {
                        Text(crypto.failed ? "Couldn't reach CoinGecko (rate limited?)" : "Loading prices…")
                    } else if let updated = crypto.updated {
                        Text("Click a coin for its chart · CoinGecko · updated \(updated.formatted(date: .omitted, time: .shortened))")
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            }
        }
        .task(id: coinIDs) { await crypto.refresh() }
    }

    private func add(_ id: String) {
        guard !ids.contains(id) else { return }
        coinIDs = (ids + [id]).joined(separator: ",")
    }

    private func remove(_ id: String) {
        coinIDs = ids.filter { $0 != id }.joined(separator: ",")
    }
}

struct CoinCard: View {
    let coin: Coin
    @State private var hovering = false

    private var change: Double { coin.price_change_percentage_24h ?? 0 }
    private var tint: Color { change >= 0 ? .green : .red }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                CoinIcon(url: URL(string: coin.image), size: 20)
                Text(coin.symbol.uppercased()).font(.callout.bold())
                Spacer()
                Label(String(format: "%.1f%%", abs(change)), systemImage: change >= 0 ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint)
            }
            Text(CryptoFormat.price(coin.current_price ?? 0))
                .font(.title3.bold().monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let points = coin.sparkline_in_7d?.price, points.count > 1 {
                Sparkline(values: points)
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(height: 34)
            }
        }
        .padding(12)
        .frame(width: 150)
        .card(highlighted: hovering)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onHover { hovering = $0 }
    }
}

struct AddCoinCard: View {
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: "plus.circle.fill").font(.system(size: 24))
                Text("Add coin").font(.caption.bold())
            }
            .foregroundStyle(hovering ? Color.white : Color.secondary)
            .frame(width: 96, height: 110)
            .background(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(hovering ? 0.4 : 0.2), style: StrokeStyle(lineWidth: 1.5, dash: [5])))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct CoinSearchView: View {
    @ObservedObject var crypto: CryptoService
    let existing: Set<String>
    let onAdd: (String) -> Void
    @State private var query = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search coins — pepe, bonk, sui…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit {
                        if let first = crypto.searchResults.first { add(first.id) }
                    }
                Button("Done") { close() }.buttonStyle(PillButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.1)))

            if crypto.searchResults.isEmpty {
                Text(query.isEmpty ? "Type a name or ticker. Press Return to add the top result." : "Searching…")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HScroll {
                    HStack(spacing: 8) {
                        ForEach(crypto.searchResults) { result in
                            let added = existing.contains(result.id)
                            Button { add(result.id) } label: {
                                VStack(spacing: 6) {
                                    CoinIcon(url: result.thumb.flatMap(URL.init(string:)), size: 28)
                                    Text(result.symbol.uppercased()).font(.caption.bold()).lineLimit(1)
                                    Text(result.name).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                    Label(added ? "Added" : (result.market_cap_rank.map { "#\($0)" } ?? "Add"),
                                          systemImage: added ? "checkmark" : "plus")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(added ? Color.green : Color.secondary)
                                }
                                .padding(8)
                                .frame(width: 84)
                                .card(highlighted: added)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .onAppear {
            // The notch panel never activates the app, so explicitly make it key to receive typing.
            NSApp.windows.first { $0 is NotchPanel }?.makeKey()
            focused = true
        }
        .onExitCommand { close() }
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(350))
            if !Task.isCancelled { await crypto.search(query) }
        }
    }

    private func add(_ id: String) {
        onAdd(id)
        query = ""
        close()
    }

    private func close() {
        crypto.isSearching = false
    }
}

struct CoinIcon: View {
    let url: URL?
    let size: CGFloat

    var body: some View {
        AsyncImage(url: url) { $0.resizable().scaledToFit() } placeholder: {
            Circle().fill(Color.white.opacity(0.1))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

struct Sparkline: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        guard values.count > 1, let lo = values.min(), let hi = values.max() else { return Path() }
        let range = max(hi - lo, .ulpOfOne)
        var path = Path()
        for (i, v) in values.enumerated() {
            let point = CGPoint(x: rect.minX + rect.width * CGFloat(i) / CGFloat(values.count - 1),
                                y: rect.maxY - rect.height * CGFloat((v - lo) / range))
            i == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        return path
    }
}

enum CryptoFormat {
    private static let subscripts: [Character] = ["₀", "₁", "₂", "₃", "₄", "₅", "₆", "₇", "₈", "₉"]

    /// Prices like the screenshot: tiny values use subscript-zero notation, e.g. $0.0₅4207 = $0.000004207.
    static func price(_ value: Double) -> String {
        let v = abs(value)
        guard v > 0 else { return "$0.00" }
        if v >= 1 {
            return v.formatted(.currency(code: "USD").precision(.fractionLength(v >= 1000 ? 0...2 : 2...2)))
        }
        var zeros = Int(floor(-log10(v)))
        if zeros < 4 {
            return "$" + String(format: "%.\(zeros + 4)f", v)
        }
        var significant = Int((v * pow(10, Double(zeros + 4))).rounded())
        if significant >= 10000 {
            significant /= 10
            zeros -= 1
        }
        let sub = String(String(zeros).compactMap { $0.wholeNumberValue.map { subscripts[$0] } })
        return "$0.0\(sub)\(significant)"
    }

    /// $1.77B, $312.4M …
    static func compact(_ value: Double) -> String {
        let v = abs(value)
        let units: [(Double, String)] = [(1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")]
        for (size, suffix) in units where v >= size {
            return String(format: "$%.2f%@", v / size, suffix)
        }
        return String(format: "$%.2f", v)
    }
}
