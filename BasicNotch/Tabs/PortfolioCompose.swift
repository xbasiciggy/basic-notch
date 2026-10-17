import SwiftUI

/// Send the Shelf's selected images (or all of them) to a portfolio album via Gallery Manager.
struct PortfolioCompose: View {
    @ObservedObject var inbox: GalleryManagerInbox
    @ObservedObject var tray: FileTrayService

    @State private var sectionID: UUID?
    @State private var albumID: UUID?
    @State private var creatingNew = false
    @State private var newTitle = ""
    @FocusState private var titleFocused: Bool

    private var section: GalleryManagerInbox.Section? { inbox.sections.first { $0.id == sectionID } }
    private var album: GalleryManagerInbox.Album? { inbox.albums.first { $0.id == albumID } }
    private var canSend: Bool {
        !tray.imagesToPost.isEmpty && (creatingNew ? !newTitle.trimmingCharacters(in: .whitespaces).isEmpty : album != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "photo.stack.fill").foregroundStyle(.orange)
                Text("Add \(tray.imagesToPost.count) photo\(tray.imagesToPost.count == 1 ? "" : "s") to portfolio").font(.caption.bold())
                Spacer()
                Button(inbox.status != nil ? "Done" : "Cancel") { close() }.buttonStyle(PillButtonStyle())
            }

            // Sections (Adventures, Lifestyle, …)
            HStack(spacing: 6) {
                ForEach(inbox.sections) { s in
                    Chip(title: s.title, selected: sectionID == s.id) {
                        sectionID = s.id
                        albumID = nil
                    }
                }
            }

            // Albums in that section, plus "New album"
            HScroll {
                HStack(spacing: 6) {
                    Button { creatingNew = true; albumID = nil; titleFocused = true } label: {
                        Label("New album", systemImage: "plus")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().strokeBorder(Color.white.opacity(creatingNew ? 0.9 : 0.3), style: StrokeStyle(lineWidth: 1, dash: [4])))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    ForEach(inbox.albums(in: sectionID)) { a in
                        Chip(title: "\(a.title) · \(a.photoCount)", selected: albumID == a.id && !creatingNew) {
                            albumID = a.id
                            creatingNew = false
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                if creatingNew {
                    TextField("New album name, e.g. Oahu 2026", text: $newTitle)
                        .textFieldStyle(.plain)
                        .focused($titleFocused)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
                        .onSubmit(send)
                } else {
                    Text(album.map { "→ \(section?.title ?? "") › \($0.title)" } ?? "Pick an album")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                Button(action: send) { Label("Send", systemImage: "paperplane.fill") }
                    .buttonStyle(PillButtonStyle())
                    .disabled(!canSend)
            }

            if let error = inbox.error {
                Text(error).font(.caption2).foregroundStyle(.red).lineLimit(2)
            } else if let status = inbox.status {
                Text(status).font(.caption2).foregroundStyle(.green).lineLimit(2)
            } else {
                Text("Gallery Manager adds them as draft changes, then you publish as usual.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .onAppear {
            NSApp.windows.first { $0 is NotchPanel }?.makeKey()
            inbox.loadLibrary()
            if sectionID == nil { sectionID = inbox.sections.first(where: { $0.title == "Adventures" })?.id ?? inbox.sections.first?.id }
        }
    }

    private func send() {
        guard canSend else { return }
        inbox.send(tray.imagesToPost, toAlbum: creatingNew ? nil : album,
                   newAlbumTitle: creatingNew ? newTitle : nil, section: section)
        if inbox.error == nil {
            tray.selected.removeAll()
            newTitle = ""
        }
    }

    private func close() {
        inbox.isComposing = false
        inbox.error = nil
    }
}
