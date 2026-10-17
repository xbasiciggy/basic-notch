import SwiftUI

/// Compose a Tumblr post from the Shelf's selected images (or all of them).
struct TumblrCompose: View {
    @ObservedObject var tumblr: TumblrService
    @ObservedObject var tray: FileTrayService
    let openSettings: () -> Void

    @State private var caption = ""
    @State private var tags = ""
    @State private var state: TumblrService.PostState = .published
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "paperplane.fill").foregroundStyle(Color(red: 0.0, green: 0.6, blue: 1.0))
                Text(tumblr.isSignedIn && !tumblr.selectedBlog.isEmpty ? "Post to \(tumblr.selectedBlog)" : "Post to Tumblr")
                    .font(.caption.bold())
                Spacer()
                Button(tumblr.lastPostURL != nil ? "Done" : "Cancel") { close() }.buttonStyle(PillButtonStyle())
            }

            if !tumblr.hasKeys {
                setupMessage("Add your Tumblr app keys in Settings → Tumblr to start posting.", button: "Open Settings", action: openSettings)
            } else if !tumblr.isSignedIn {
                setupMessage("Sign in once with your Tumblr account.", button: "Sign in to Tumblr") { tumblr.signIn() }
            } else {
                composer
            }
        }
        .onAppear {
            NSApp.windows.first { $0 is NotchPanel }?.makeKey()
            if tumblr.isSignedIn && tumblr.blogs.isEmpty { Task { await tumblr.loadBlogs() } }
        }
    }

    private var composer: some View {
        let images = tray.imagesToPost
        return HStack(alignment: .top, spacing: 12) {
            // Thumbnails of what's being posted.
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.fixed(44)), GridItem(.fixed(44))], spacing: 4) {
                    ForEach(images, id: \.self) { url in
                        Thumbnail(url: url).frame(width: 44, height: 44)
                    }
                }
            }
            .frame(width: 92)

            VStack(alignment: .leading, spacing: 6) {
                TextField("Caption (optional)", text: $caption, axis: .vertical)
                    .lineLimit(2...3)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .padding(7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                TextField("Tags, comma separated", text: $tags)
                    .textFieldStyle(.plain)
                    .padding(7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                HStack(spacing: 6) {
                    ForEach(TumblrService.PostState.allCases) { s in
                        Chip(title: s.title, selected: state == s) { state = s }
                    }
                    Spacer()
                    Button {
                        Task {
                            await tumblr.post(images: images, caption: caption, tags: tags, state: state)
                            if tumblr.error == nil {
                                caption = ""
                                tags = ""
                                tray.selected.removeAll()
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            if tumblr.isPosting { ProgressView().controlSize(.mini) } else { Image(systemName: "paperplane.fill") }
                            Text(tumblr.isPosting ? "Posting…" : "Post \(images.count)")
                        }
                    }
                    .buttonStyle(PillButtonStyle())
                    .disabled(tumblr.isPosting || images.isEmpty)
                }
                statusLine
            }
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if let error = tumblr.error {
            Text(error).font(.caption2).foregroundStyle(.red).lineLimit(2)
        } else if let status = tumblr.status {
            HStack(spacing: 8) {
                Text(status).font(.caption2).foregroundStyle(tumblr.isPosting ? Color.secondary : Color.green)
                if let url = tumblr.lastPostURL {
                    Button("View post") { NSWorkspace.shared.open(url) }.buttonStyle(.plain).font(.caption2.bold())
                    Button("Copy link") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    }
                    .buttonStyle(.plain).font(.caption2.bold())
                }
            }
        } else {
            Text(tray.selected.isEmpty ? "Posting every image on the shelf — click images first to pick just some."
                 : "Posting the \(tray.imagesToPost.count) selected image\(tray.imagesToPost.count == 1 ? "" : "s").")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func setupMessage(_ text: String, button: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Text(text).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(button, action: action).buttonStyle(PillButtonStyle())
            if let error = tumblr.error { Text(error).font(.caption2).foregroundStyle(.red) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func close() {
        tumblr.isComposing = false
        tumblr.error = nil
    }
}

private struct Thumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Color.white.opacity(0.08)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: url) {
            image = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                          kCGImageSourceCreateThumbnailFromImageAlways: true,
                          kCGImageSourceCreateThumbnailWithTransform: true,
                          kCGImageSourceThumbnailMaxPixelSize: 120,
                      ] as CFDictionary) else { return nil }
                return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            }.value
        }
    }
}
