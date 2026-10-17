import AppKit
import WebKit
import ImageIO
import UniformTypeIdentifiers

/// Posts images from the Shelf to Tumblr using Tumblr's official API (OAuth 2 + Neue Post Format).
/// You register a free app at tumblr.com/oauth/apps and paste its keys into Settings once.
@MainActor
final class TumblrService: ObservableObject {
    struct Blog: Identifiable, Hashable {
        var id: String { name }
        let name: String
        let title: String
        let primary: Bool
    }

    enum PostState: String, CaseIterable, Identifiable {
        case published, queue, draft
        var id: Self { self }
        var title: String {
            switch self {
            case .published: "Post now"
            case .queue: "Add to queue"
            case .draft: "Save draft"
            }
        }
    }

    static let redirectURI = "https://localhost/basicnotch-tumblr"
    static let secretAccount = "tumblr-client-secret"
    static let refreshAccount = "tumblr-refresh-token"

    @Published private(set) var isSignedIn = Keychain.get(TumblrService.refreshAccount) != nil
    @Published private(set) var blogs: [Blog] = []
    @Published private(set) var isPosting = false
    @Published private(set) var status: String?
    @Published private(set) var lastPostURL: URL?
    @Published var error: String?
    /// While the compose panel is open, the notch stays open so you can type.
    @Published var isComposing = false

    private var accessToken: String?
    private var accessExpiry = Date.distantPast
    private var loginWindow: TumblrLoginWindow?

    private var clientID: String { (UserDefaults.standard.string(forKey: "tumblrClientID") ?? "").trimmingCharacters(in: .whitespaces) }
    private var clientSecret: String { Keychain.get(Self.secretAccount) ?? "" }
    var hasKeys: Bool { !clientID.isEmpty && !clientSecret.isEmpty }

    var selectedBlog: String {
        let saved = UserDefaults.standard.string(forKey: "tumblrBlog") ?? ""
        if blogs.contains(where: { $0.name == saved }) { return saved }
        return blogs.first(where: \.primary)?.name ?? blogs.first?.name ?? saved
    }

    // MARK: Sign in

    func signIn() {
        guard hasKeys else {
            error = "Add your Tumblr app's keys in Settings first"
            return
        }
        let state = UUID().uuidString
        var components = URLComponents(string: "https://www.tumblr.com/oauth2/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "basic write offline_access"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
        ]
        loginWindow = TumblrLoginWindow(url: components.url!, redirect: Self.redirectURI) { [weak self] callback in
            guard let self else { return }
            self.loginWindow = nil
            guard let callback,
                  let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems,
                  items.first(where: { $0.name == "state" })?.value == state,
                  let code = items.first(where: { $0.name == "code" })?.value else {
                return
            }
            Task { await self.finishSignIn(code: code) }
        }
        NSApp.activate(ignoringOtherApps: true)
        loginWindow?.makeKeyAndOrderFront(nil)
    }

    private func finishSignIn(code: String) async {
        do {
            try await requestTokens(["grant_type": "authorization_code", "code": code,
                                     "client_id": clientID, "client_secret": clientSecret,
                                     "redirect_uri": Self.redirectURI])
            isSignedIn = true
            error = nil
            await loadBlogs()
        } catch {
            self.error = "Tumblr sign-in failed: \(error.localizedDescription)"
        }
    }

    func signOut() {
        Keychain.set("", for: Self.refreshAccount)
        accessToken = nil
        accessExpiry = .distantPast
        blogs = []
        isSignedIn = false
    }

    func loadBlogs() async {
        guard isSignedIn else { return }
        do {
            var request = URLRequest(url: URL(string: "https://api.tumblr.com/v2/user/info")!)
            request.setValue("Bearer \(try await validToken())", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            try Self.check(response, data)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let user = (json?["response"] as? [String: Any])?["user"] as? [String: Any]
            blogs = (user?["blogs"] as? [[String: Any]] ?? []).compactMap { b in
                guard let name = b["name"] as? String else { return nil }
                return Blog(name: name, title: b["title"] as? String ?? name, primary: b["primary"] as? Bool ?? false)
            }
        } catch {
            self.error = "Couldn't load your Tumblr blogs"
        }
    }

    // MARK: Posting

    func post(images: [URL], caption: String, tags: String, state: PostState) async {
        guard !images.isEmpty, !isPosting else { return }
        let blog = selectedBlog
        guard !blog.isEmpty else {
            error = "Pick a blog in Settings"
            return
        }
        isPosting = true
        error = nil
        lastPostURL = nil
        status = "Uploading \(images.count) image\(images.count == 1 ? "" : "s")…"
        defer { isPosting = false }

        do {
            var content: [[String: Any]] = []
            var files: [(field: String, name: String, mime: String, data: Data)] = []
            for (i, url) in images.enumerated() {
                let prepared = try Self.prepare(url)
                let field = "file\(i)"
                content.append(["type": "image", "media": [["type": prepared.mime, "identifier": field]]])
                files.append((field, prepared.name, prepared.mime, prepared.data))
            }
            let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { content.append(["type": "text", "text": text]) }
            var payload: [String: Any] = ["content": content, "state": state.rawValue]
            let tagList = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if !tagList.isEmpty { payload["tags"] = tagList.joined(separator: ",") }

            let boundary = "BasicNotch-\(UUID().uuidString)"
            var body = Data()
            func append(_ string: String) { body.append(Data(string.utf8)) }
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"json\"\r\nContent-Type: application/json\r\n\r\n")
            body.append(try JSONSerialization.data(withJSONObject: payload))
            append("\r\n")
            for f in files {
                append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(f.field)\"; filename=\"\(f.name)\"\r\nContent-Type: \(f.mime)\r\n\r\n")
                body.append(f.data)
                append("\r\n")
            }
            append("--\(boundary)--\r\n")

            var request = URLRequest(url: URL(string: "https://api.tumblr.com/v2/blog/\(blog)/posts")!)
            request.httpMethod = "POST"
            request.timeoutInterval = 180
            request.setValue("Bearer \(try await validToken())", forHTTPHeaderField: "Authorization")
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            let (data, response) = try await URLSession.shared.upload(for: request, from: body)
            try Self.check(response, data)

            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let id = ((json?["response"] as? [String: Any])?["id"]).map { "\($0)" }
            lastPostURL = id.flatMap { URL(string: "https://www.tumblr.com/\(blog)/\($0)") }
            status = state == .published ? "Posted to \(blog)! 🎉" : state == .queue ? "Added to \(blog)'s queue" : "Saved as a draft on \(blog)"
        } catch {
            status = nil
            self.error = error.localizedDescription
        }
    }

    /// Tumblr caps image uploads at about 10 MB; big photos are re-encoded as high-quality JPEG.
    private static func prepare(_ url: URL) throws -> (name: String, mime: String, data: Data) {
        let data = try Data(contentsOf: url)
        let type = UTType(filenameExtension: url.pathExtension.lowercased())
        let mime = type?.preferredMIMEType ?? "image/jpeg"
        let passThrough: Set<String> = ["image/jpeg", "image/png", "image/gif", "image/webp"]
        if passThrough.contains(mime) && data.count < 9_500_000 {
            return (url.lastPathComponent, mime, data)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 4096,
              ] as CFDictionary) else {
            throw NSError(domain: "Tumblr", code: 0, userInfo: [NSLocalizedDescriptionKey: "\(url.lastPathComponent) isn't an image Tumblr accepts"])
        }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw NSError(domain: "Tumblr", code: 0, userInfo: [NSLocalizedDescriptionKey: "Couldn't prepare \(url.lastPathComponent)"])
        }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
        CGImageDestinationFinalize(dest)
        return (url.deletingPathExtension().lastPathComponent + ".jpg", "image/jpeg", out as Data)
    }

    // MARK: Tokens

    private func validToken() async throws -> String {
        if let token = accessToken, accessExpiry > Date().addingTimeInterval(60) { return token }
        guard let refresh = Keychain.get(Self.refreshAccount) else { throw Self.failure("Sign in to Tumblr first") }
        do {
            try await requestTokens(["grant_type": "refresh_token", "refresh_token": refresh,
                                     "client_id": clientID, "client_secret": clientSecret])
        } catch {
            signOut()
            throw Self.failure("Your Tumblr sign-in expired — sign in again")
        }
        guard let token = accessToken else { throw Self.failure("Sign in to Tumblr first") }
        return token
    }

    private func requestTokens(_ form: [String: String]) async throws {
        var request = URLRequest(url: URL(string: "https://api.tumblr.com/v2/oauth2/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = body.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String else { throw Self.failure("Tumblr didn't return a token") }
        accessToken = access
        accessExpiry = Date().addingTimeInterval(TimeInterval(json["expires_in"] as? Int ?? 2400))
        if let refresh = json["refresh_token"] as? String { Keychain.set(refresh, for: Self.refreshAccount) }
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let detail = (json?["errors"] as? [[String: Any]])?.first?["detail"] as? String
            ?? json?["error_description"] as? String
            ?? (json?["meta"] as? [String: Any])?["msg"] as? String
        throw failure(detail ?? "Tumblr error \(http.statusCode)")
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "Tumblr", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

/// Tumblr's own sign-in page in a private, non-persistent browser window.
/// When Tumblr redirects back with the authorization code, the window catches it and closes.
final class TumblrLoginWindow: NSWindow, WKNavigationDelegate {
    private let webView: WKWebView
    private let redirect: String
    private let onFinish: @MainActor (URL?) -> Void
    private var finished = false

    @MainActor
    init(url: URL, redirect: String, onFinish: @escaping @MainActor (URL?) -> Void) {
        self.redirect = redirect
        self.onFinish = onFinish
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init(contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
                   styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        title = "Sign in to Tumblr"
        isReleasedWhenClosed = false
        contentView = webView
        center()
        webView.navigationDelegate = self
        webView.load(URLRequest(url: url))
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url, url.absoluteString.hasPrefix(redirect) {
            decisionHandler(.cancel)
            MainActor.assumeIsolated { finish(url) }
            return
        }
        decisionHandler(.allow)
    }

    @MainActor
    private func finish(_ url: URL?) {
        guard !finished else { return }
        finished = true
        onFinish(url)
        close()
    }

    override func close() {
        super.close()
        MainActor.assumeIsolated {
            if !finished {
                finished = true
                onFinish(nil)
            }
        }
    }
}
