import AppKit
import WebKit

/// PlayStation Network friends + presence.
/// Sony has no public API, so this uses the same endpoints as the PlayStation mobile app
/// (the approach documented by the open-source psn-api project): sign in on Sony's own page,
/// take the `npsso` session cookie, and exchange it for app tokens. Tokens live in the Keychain.
@MainActor
final class PSNService: ObservableObject {
    struct Friend: Identifiable {
        let id: String  // accountId
        var onlineID: String
        var avatar: URL?
        var online: Bool
        var platform: String?
        var game: String?
        var gameIcon: URL?
        var lastOnline: Date?
    }

    @Published private(set) var friends: [Friend] = []
    @Published private(set) var isSignedIn = Keychain.get(PSNService.refreshAccount) != nil
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?

    static let refreshAccount = "psn-refresh-token"
    private static let clientID = "09515159-7237-4370-9b40-3806e67c0891"
    private static let basicAuth = "Basic MDk1MTUxNTktNzIzNy00MzcwLTliNDAtMzgwNmU2N2MwODkxOnVjUGprYTV0bnRCMktxc1A="
    private static let redirectURI = "com.scee.psxandroid.scecompcall://redirect"
    private static let scope = "psn:mobile.v2.core psn:clientapp"
    private static let api = "https://m.np.playstation.com/api/userProfile/v1/internal/users"

    private var accessToken: String?
    private var accessExpiry = Date.distantPast
    /// Friends' names and avatars, saved between launches so a restart doesn't re-fetch all of them
    /// (looking up 150+ profiles at once trips PlayStation's rate limit).
    private var profiles: [String: (onlineID: String, avatar: URL?)] = PSNService.loadSavedProfiles()
    private static let profilesKey = "psnProfiles"
    /// Game art by title ID (e.g. "PPSA01234_00"), saved between launches — a game's art doesn't change.
    private var titleArt: [String: String] = UserDefaults.standard.dictionary(forKey: "psnTitleArt") as? [String: String] ?? [:]
    private var titleArtMisses: Set<String> = []
    /// New profiles looked up per refresh; the rest follow on later refreshes.
    private static let profileFetchesPerRefresh = 25
    private var loop: Task<Void, Never>?
    private var loginWindow: PSNLoginWindow?

    var onlineCount: Int { friends.filter(\.online).count }

    func start() {
        loop = Task { [weak self] in
            while !Task.isCancelled {
                if self?.isSignedIn == true { await self?.refresh() }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    // MARK: Sign in / out

    func showLogin() {
        if loginWindow == nil {
            loginWindow = PSNLoginWindow(
                validate: { [weak self] npsso in
                    await self?.signIn(npsso: npsso, reportErrors: false) ?? false
                },
                onClose: { [weak self] in self?.loginWindow = nil })
        }
        NSApp.activate(ignoringOtherApps: true)
        loginWindow?.makeKeyAndOrderFront(nil)
    }

    /// Returns true once the session cookie really signs in. While Sony is still asking for the
    /// 6-digit two-step code, this fails quietly and the login window keeps waiting.
    @discardableResult
    func signIn(npsso: String, reportErrors: Bool = true) async -> Bool {
        isLoading = true
        if reportErrors { error = nil }
        defer { isLoading = false }
        do {
            let code = try await authorizationCode(npsso: npsso.trimmingCharacters(in: .whitespacesAndNewlines))
            try await requestTokens(["code": code, "redirect_uri": Self.redirectURI,
                                     "grant_type": "authorization_code", "token_format": "jwt"])
            isSignedIn = true
            error = nil
            await refresh()
            return true
        } catch {
            if reportErrors { self.error = "PlayStation sign-in failed: \(error.localizedDescription)" }
            return false
        }
    }

    func signOut() {
        Keychain.set("", for: Self.refreshAccount)
        accessToken = nil
        accessExpiry = .distantPast
        friends = []
        profiles = [:]
        UserDefaults.standard.removeObject(forKey: Self.profilesKey)
        isSignedIn = false
    }

    private static func loadSavedProfiles() -> [String: (onlineID: String, avatar: URL?)] {
        let saved = UserDefaults.standard.dictionary(forKey: profilesKey) as? [String: [String]] ?? [:]
        return saved.compactMapValues { pair in
            guard let name = pair.first else { return nil }
            return (name, pair.count > 1 ? URL(string: pair[1]) : nil)
        }
    }

    private func saveProfiles() {
        let plain = profiles.mapValues { [$0.onlineID] + ($0.avatar.map { [$0.absoluteString] } ?? []) }
        UserDefaults.standard.set(plain, forKey: Self.profilesKey)
    }

    // MARK: Friends

    func refresh() async {
        isLoading = friends.isEmpty
        defer { isLoading = false }
        do {
            let list: FriendsResponse = try await get("\(Self.api)/me/friends?limit=200")
            let ids = list.friends
            let presences = try await presences(for: ids)

            var result: [Friend] = []
            var lookups = 0
            // Friends who are playing or online get their profiles looked up first.
            func rank(_ id: String) -> Int {
                guard let p = presences[id] else { return 2 }
                if !(p.gameTitleInfoList ?? []).isEmpty { return 0 }
                return p.primaryPlatformInfo?.onlineStatus == "online" ? 1 : 2
            }
            for id in ids.sorted(by: { rank($0) < rank($1) }) {
                // Use saved profiles; look up a limited number of new ones per refresh. A failed lookup
                // just leaves that friend out until a later refresh instead of failing the whole list.
                let profile: (onlineID: String, avatar: URL?)
                if let known = profiles[id] {
                    profile = known
                } else if lookups < Self.profileFetchesPerRefresh {
                    lookups += 1
                    do {
                        profile = try await self.profile(for: id)
                    } catch PSNError.signedOut {
                        throw PSNError.signedOut
                    } catch {
                        imageLog.error("psn profile \(id, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                        continue
                    }
                } else {
                    continue
                }
                let p = presences[id]
                let game = p?.gameTitleInfoList?.first
                var iconString = game?.conceptIconUrl ?? game?.npTitleIconUrl
                if iconString == nil, let titleID = game?.npTitleId {
                    iconString = await art(for: titleID, playedBy: id)
                }
                result.append(Friend(
                    id: id,
                    onlineID: profile.onlineID,
                    avatar: profile.avatar,
                    online: p?.primaryPlatformInfo?.onlineStatus == "online",
                    platform: p?.primaryPlatformInfo?.platform,
                    game: game?.titleName,
                    gameIcon: iconString.flatMap(URL.init(string:)),
                    lastOnline: p?.primaryPlatformInfo?.lastOnlineDate.flatMap { ISO8601DateFormatter().date(from: $0) }))
            }
            if lookups > 0 { saveProfiles() }
            // Warm the image cache so the Gaming tab shows pictures instantly.
            let pictures = result.flatMap { [$0.avatar, $0.gameIcon] }.compactMap { $0 }
            Task { for url in pictures { _ = await RemoteImageCache.shared.load(url) } }
            // Playing something first, then online, then most recently seen.
            friends = result.sorted { a, b in
                if (a.game != nil && a.online) != (b.game != nil && b.online) { return a.game != nil && a.online }
                if a.online != b.online { return a.online }
                return (a.lastOnline ?? .distantPast) > (b.lastOnline ?? .distantPast)
            }
            error = nil
        } catch PSNError.signedOut {
            imageLog.error("psn refresh: signed out")
            signOut()
            error = "Your PlayStation sign-in expired. Sign in again."
        } catch {
            imageLog.error("psn refresh failed: \(String(describing: error), privacy: .public)")
            self.error = "Couldn't load PlayStation friends"
        }
    }

    private func presences(for ids: [String]) async throws -> [String: Presence] {
        var map: [String: Presence] = [:]
        for start in stride(from: 0, to: ids.count, by: 50) {
            let batch = ids[start..<min(start + 50, ids.count)]
            if let response: PresencesResponse = try? await get("\(Self.api)/basicPresences?type=primary&accountIds=\(batch.joined(separator: ","))") {
                for p in response.basicPresences { map[p.accountId] = p }
            } else {
                // A friend's privacy settings can fail the whole batch; fall back to one at a time.
                for id in batch {
                    if let single: SinglePresenceResponse = try? await get("\(Self.api)/\(id)/basicPresences?type=primary") {
                        map[id] = single.basicPresence
                    }
                }
            }
        }
        return map
    }

    /// Friend status only carries a game's name and ID, so look its art up in that friend's
    /// recently played list (the documented game-list endpoint) and remember it.
    private func art(for titleID: String, playedBy accountID: String) async -> String? {
        if let known = titleArt[titleID] { return known }
        guard !titleArtMisses.contains(titleID + accountID) else { return nil }
        struct GameList: Decodable {
            struct Title: Decodable {
                let titleId: String
                let imageUrl: String?
                let localizedImageUrl: String?
            }
            let titles: [Title]
        }
        let url = "https://m.np.playstation.com/api/gamelist/v2/users/\(accountID)/titles?categories=ps4_game,ps5_native_game&limit=10&offset=0"
        guard let list: GameList = try? await get(url) else {
            titleArtMisses.insert(titleID + accountID)  // their game list is private — don't ask again
            return nil
        }
        for title in list.titles {
            if let image = title.imageUrl ?? title.localizedImageUrl, titleArt[title.titleId] == nil {
                titleArt[title.titleId] = image
            }
        }
        UserDefaults.standard.set(titleArt, forKey: "psnTitleArt")
        if titleArt[titleID] == nil { titleArtMisses.insert(titleID + accountID) }
        return titleArt[titleID]
    }

    private func profile(for id: String) async throws -> (onlineID: String, avatar: URL?) {
        if let cached = profiles[id] { return cached }
        let p: ProfileResponse = try await get("\(Self.api)/\(id)/profiles")
        // Largest first so pictures stay sharp on Retina screens.
        let avatar = ["l", "m", "xl", "s"].lazy.compactMap { size in p.avatars.first { $0.size == size } }.first
            .flatMap { URL(string: $0.url) } ?? p.avatars.first.flatMap { URL(string: $0.url) }
        profiles[id] = (p.onlineId, avatar)
        return (p.onlineId, avatar)
    }

    // MARK: Networking

    private enum PSNError: Error { case signedOut, noCode }

    private func get<T: Decodable>(_ urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await validAccessToken())", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status == 401 { throw PSNError.signedOut }
        guard status == 200 else {
            imageLog.error("psn HTTP \(status, privacy: .public) for \(url.path, privacy: .public)")
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func validAccessToken() async throws -> String {
        if let token = accessToken, accessExpiry > Date().addingTimeInterval(60) { return token }
        guard let refresh = Keychain.get(Self.refreshAccount) else { throw PSNError.signedOut }
        try await requestTokens(["refresh_token": refresh, "grant_type": "refresh_token",
                                 "scope": Self.scope, "token_format": "jwt"])
        guard let token = accessToken else { throw PSNError.signedOut }
        return token
    }

    private func authorizationCode(npsso: String) async throws -> String {
        var components = URLComponents(string: "https://ca.account.sony.com/api/authz/v3/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
        ]
        var request = URLRequest(url: components.url!)
        request.httpShouldHandleCookies = false
        request.setValue("npsso=\(npsso)", forHTTPHeaderField: "Cookie")
        // Sony answers with a redirect to the app's custom URL scheme carrying ?code=…; don't follow it.
        let (_, response) = try await URLSession.shared.data(for: request, delegate: NoRedirects())
        guard let location = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Location"),
              let code = URLComponents(string: location)?.queryItems?.first(where: { $0.name == "code" })?.value
        else { throw PSNError.noCode }
        return code
    }

    private func requestTokens(_ form: [String: String]) async throws {
        var request = URLRequest(url: URL(string: "https://ca.account.sony.com/api/authz/v3/oauth/token")!)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.setValue(Self.basicAuth, forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw PSNError.signedOut }
        let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)
        accessToken = tokens.access_token
        accessExpiry = Date().addingTimeInterval(TimeInterval(tokens.expires_in))
        if let refresh = tokens.refresh_token { Keychain.set(refresh, for: Self.refreshAccount) }
    }

    // MARK: Responses

    private struct TokenResponse: Decodable {
        let access_token: String
        let expires_in: Int
        let refresh_token: String?
    }

    private struct FriendsResponse: Decodable { let friends: [String] }

    private struct ProfileResponse: Decodable {
        struct Avatar: Decodable { let size: String; let url: String }
        let onlineId: String
        let avatars: [Avatar]
    }

    struct Presence: Decodable {
        struct Platform: Decodable {
            let onlineStatus: String?
            let platform: String?
            let lastOnlineDate: String?
        }
        struct Title: Decodable {
            let titleName: String?
            let npTitleId: String?
            let conceptIconUrl: String?
            let npTitleIconUrl: String?
        }
        let accountId: String
        let primaryPlatformInfo: Platform?
        let gameTitleInfoList: [Title]?
    }

    private struct PresencesResponse: Decodable { let basicPresences: [Presence] }

    private struct SinglePresenceResponse: Decodable {
        let basicPresence: Presence

        enum CodingKeys: String, CodingKey { case basicPresence }
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? { nil }
}

// MARK: - Sign-in window

/// Shows Sony's real sign-in page (including the 6-digit two-step verification step).
/// Each time Sony's `npsso` session cookie changes, it's tested; the window only closes once
/// that cookie actually completes sign-in. Uses a private, non-persistent browser session.
final class PSNLoginWindow: NSWindow, WKNavigationDelegate {
    private let webView: WKWebView
    private let validate: @MainActor (String) async -> Bool
    private let onClose: @MainActor () -> Void
    private var pollTimer: Timer?
    private var lastTried: String?
    private var lastTryDate = Date.distantPast
    private var checking = false
    private var done = false

    @MainActor
    init(validate: @escaping @MainActor (String) async -> Bool, onClose: @escaping @MainActor () -> Void) {
        self.validate = validate
        self.onClose = onClose
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 480, height: 720),
                   styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        title = "Sign in to PlayStation"
        isReleasedWhenClosed = false
        contentView = webView
        center()
        webView.navigationDelegate = self
        webView.load(URLRequest(url: URL(string: "https://my.playstation.com/")!))

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkCookie() }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { checkCookie() }
    }

    @MainActor
    private func checkCookie() {
        guard !done, !checking else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            MainActor.assumeIsolated {
                guard let self, !self.done, !self.checking,
                      let npsso = cookies.first(where: { $0.name == "npsso" && $0.domain.contains("sony.com") })?.value,
                      !npsso.isEmpty else { return }
                // Try each new cookie right away; retry an unchanged one every few seconds
                // (it starts working once the two-step code is accepted).
                guard npsso != self.lastTried || Date().timeIntervalSince(self.lastTryDate) > 4 else { return }
                self.lastTried = npsso
                self.lastTryDate = Date()
                self.checking = true
                Task { @MainActor in
                    let ok = await self.validate(npsso)
                    self.checking = false
                    if ok {
                        self.done = true
                        self.close()
                    }
                }
            }
        }
    }

    override func close() {
        pollTimer?.invalidate()
        pollTimer = nil
        super.close()
        MainActor.assumeIsolated { onClose() }
    }
}
