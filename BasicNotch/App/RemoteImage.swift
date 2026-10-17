import SwiftUI
import AppKit
import os

let imageLog = Logger(subsystem: "com.local.BasicNotch", category: "images")

/// Loads an image from the web once and keeps it in memory, so pictures don't blink or
/// re-download every time a list refreshes (AsyncImage starts over on each new view).
@MainActor
final class RemoteImageCache {
    static let shared = RemoteImageCache()

    private let cache = NSCache<NSURL, NSImage>()
    private var inFlight: [URL: Task<NSImage?, Never>] = [:]

    func cached(_ url: URL) -> NSImage? { cache.object(forKey: Self.secure(url) as NSURL) }

    static func secure(_ url: URL) -> URL {
        guard url.scheme == "http", var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        parts.scheme = "https"
        return parts.url ?? url
    }

    func load(_ original: URL) async -> NSImage? {
        // macOS blocks plain-http downloads; PlayStation hands out http:// avatar links that also work over https.
        let url = Self.secure(original)
        if let image = cached(url) { return image }
        if let task = inFlight[url] { return await task.value }
        let task = Task<NSImage?, Never> {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                let image = NSImage(data: data)
                return status == 200 ? image : nil
            } catch {
                imageLog.error("image failed \(error.localizedDescription, privacy: .public) \(url.absoluteString, privacy: .public)")
                return nil
            }
        }
        inFlight[url] = task
        let image = await task.value
        inFlight[url] = nil
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }
}

/// A cached web image with a placeholder while it loads (or if it fails).
struct RemoteImage<Placeholder: View>: View {
    let url: URL?
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image = image ?? url.flatMap(RemoteImageCache.shared.cached) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            image = nil
            if let url { image = await RemoteImageCache.shared.load(url) }
        }
    }
}

/// A PlayStation-style round profile picture with initials while it loads.
struct AvatarImage: View {
    let url: URL?
    let name: String
    var size: CGFloat = 34

    var body: some View {
        RemoteImage(url: url) {
            ZStack {
                Circle().fill(Color.white.opacity(0.12))
                Text(name.prefix(1).uppercased())
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// A game's square icon with a controller symbol while it loads.
struct GameIconImage: View {
    let url: URL?
    var size: CGFloat = 30

    var body: some View {
        RemoteImage(url: url) {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.2).fill(Color.white.opacity(0.1))
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
    }
}
