import Foundation

/// Time-synced lyrics from LRCLIB (lrclib.net), a free, open lyrics database. No account needed.
///
/// LRCLIB often has several synced versions of a song, timed by different volunteers, and their
/// accuracy varies. We keep them all, start with the most finely timed one, and let you flip to
/// another version or nudge the timing — both remembered per song.
@MainActor
final class LyricsService: ObservableObject {
    struct Line: Equatable {
        let time: Double  // seconds into the song
        let text: String
    }

    enum State: Equatable {
        case idle, loading, synced, plainOnly, instrumental, notFound
    }

    @Published private(set) var lines: [Line] = []
    @Published private(set) var state: State = .idle
    /// Every distinct synced version found for this song, best first.
    @Published private(set) var versions: [[Line]] = []
    @Published private(set) var versionIndex = 0
    /// Seconds added to the playback position (positive = lyrics come sooner).
    @Published private(set) var offset: Double = 0

    private var key = ""
    /// Whether the current lyrics were matched using the song's length.
    private var matchedWithDuration = false
    private var cache: [String: Result] = [:]
    private var task: Task<Void, Never>?

    private struct Result {
        let state: State
        let versions: [[Line]]
        let plain: [Line]
    }

    /// Index of the line being sung at `position`, or nil before the first line.
    func index(at position: Double) -> Int? {
        guard state == .synced else { return nil }
        // Show each line a beat early so it's on screen as it starts.
        let t = position + offset + 0.2
        return lines.lastIndex { $0.time <= t }
    }

    // MARK: Fixing timing (remembered per song)

    func nudge(by seconds: Double) {
        offset = ((offset + seconds) * 10).rounded() / 10
        Self.store(offset == 0 ? nil : offset, in: "lyricsOffsets", key: key)
    }

    func resetTiming() {
        offset = 0
        Self.store(nil, in: "lyricsOffsets", key: key)
    }

    func nextVersion() {
        guard versions.count > 1 else { return }
        versionIndex = (versionIndex + 1) % versions.count
        lines = versions[versionIndex]
        Self.store(versionIndex == 0 ? nil : Double(versionIndex), in: "lyricsVersions", key: key)
    }

    private static func store(_ value: Double?, in defaultsKey: String, key: String) {
        var map = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Double] ?? [:]
        map[key] = value
        UserDefaults.standard.set(map, forKey: defaultsKey)
    }

    private static func stored(_ defaultsKey: String, key: String) -> Double? {
        (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Double])?[key]
    }

    // MARK: Loading

    func load(title: String, artist: String, album: String, duration: Double) {
        let newKey = "\(artist)|\(title)"
        // Same song: only look again if we now know its length and didn't before.
        guard newKey != key || (duration > 0 && !matchedWithDuration) else { return }
        let cacheKey = newKey + (duration > 0 ? "|\(Int(duration.rounded()))" : "")
        key = newKey
        matchedWithDuration = duration > 0
        offset = Self.stored("lyricsOffsets", key: newKey) ?? 0
        task?.cancel()
        guard !title.isEmpty else { apply(Result(state: .idle, versions: [], plain: [])); return }
        if let cached = cache[cacheKey] { apply(cached); return }
        lines = []
        versions = []
        state = .loading
        task = Task { [weak self] in
            let result = await Self.fetch(title: title, artist: artist, album: album, duration: duration)
            guard let self, !Task.isCancelled, self.key == newKey else { return }
            self.cache[cacheKey] = result
            self.apply(result)
        }
    }

    private func apply(_ result: Result) {
        state = result.state
        versions = result.versions
        let saved = Int(Self.stored("lyricsVersions", key: key) ?? 0)
        versionIndex = versions.indices.contains(saved) ? saved : 0
        lines = result.state == .synced ? versions[versionIndex] : result.plain
    }

    // MARK: Fetching

    private struct Record: Decodable {
        let instrumental: Bool?
        let syncedLyrics: String?
        let plainLyrics: String?
        let duration: Double?
    }

    private static func fetch(title: String, artist: String, album: String, duration: Double) async -> Result {
        // Exact match (artist + title + album + length) plus a search, which finds the other synced versions.
        var exact = URLComponents(string: "https://lrclib.net/api/get")!
        exact.queryItems = [URLQueryItem(name: "artist_name", value: artist), URLQueryItem(name: "track_name", value: title)]
        if !album.isEmpty { exact.queryItems?.append(URLQueryItem(name: "album_name", value: album)) }
        if duration > 0 { exact.queryItems?.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        var search = URLComponents(string: "https://lrclib.net/api/search")!
        search.queryItems = [URLQueryItem(name: "artist_name", value: artist), URLQueryItem(name: "track_name", value: cleaned(title))]

        async let exactRecord: Record? = get(exact.url!)
        async let found: [Record]? = get(search.url!)
        var records: [Record] = []
        if let record = await exactRecord { records.append(record) }
        // Only versions about the same length as what's playing — other cuts have different timings.
        records += (await found ?? []).filter { duration <= 0 || abs(($0.duration ?? duration) - duration) < 3 }

        if records.first?.instrumental == true { return Result(state: .instrumental, versions: [], plain: []) }

        // Distinct synced versions, best timed first.
        var seen = Set<String>()
        let versions = records.compactMap(\.syncedLyrics)
            .map(parse)
            .filter { !$0.isEmpty && seen.insert($0.map { "\($0.time)" }.joined(separator: ",")).inserted }
            .sorted { score($0) > score($1) }
        if !versions.isEmpty { return Result(state: .synced, versions: versions, plain: []) }

        if let plain = records.lazy.compactMap(\.plainLyrics).first, !plain.isEmpty {
            return Result(state: .plainOnly, versions: [], plain: plain.split(separator: "\n").map { Line(time: 0, text: String($0)) })
        }
        return Result(state: .notFound, versions: [], plain: [])
    }

    /// Finer timing usually means more careful syncing: count sung lines, and penalize long lines
    /// (several phrases lumped under one timestamp start well before most of their words).
    static func score(_ lines: [Line]) -> Double {
        let sung = lines.filter { $0.text != "♪" }
        guard !sung.isEmpty else { return 0 }
        let averageLength = Double(sung.map(\.text.count).reduce(0, +)) / Double(sung.count)
        // Shorter lines break ties: they mean each timestamp sits closer to its words.
        return Double(sung.count) - max(0, averageLength - 40) * 0.5 - averageLength * 0.05
    }

    private static func get<T: Decodable>(_ url: URL) async -> T? {
        var request = URLRequest(url: url)
        request.setValue("BasicNotch (https://github.com)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// "Song - Remastered 2011" / "Song (feat. X)" → "Song"
    private static func cleaned(_ title: String) -> String {
        var t = title
        for marker in [" - ", " (feat", " [feat", " (with"] {
            if let r = t.range(of: marker, options: .caseInsensitive) { t = String(t[..<r.lowerBound]) }
        }
        return t
    }

    /// Parses LRC lines like "[01:23.45] words". Lines can carry several timestamps.
    static func parse(_ lrc: String) -> [Line] {
        var result: [Line] = []
        for raw in lrc.split(separator: "\n") {
            var rest = Substring(raw)
            var times: [Double] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let stamp = rest[rest.index(after: rest.startIndex)..<close]
                let parts = stamp.split(separator: ":")
                if parts.count == 2, let m = Double(parts[0]), let s = Double(parts[1]) { times.append(m * 60 + s) }
                rest = rest[rest.index(after: close)...]
            }
            let text = rest.trimmingCharacters(in: .whitespaces)
            for time in times { result.append(Line(time: time, text: text.isEmpty ? "♪" : text)) }
        }
        return result.sorted { $0.time < $1.time }
    }
}
