import Foundation

/// Size affects the sprite region; magnification scales the whole companion UI.
struct BuddyLayout {
    static let maximumSize = 10.5 // Previous maximum 3 + 250%.
    let expansion: CGFloat
    var spriteWidth: CGFloat { 240 * expansion }
    var spriteHeight: CGFloat { 104 * expansion }
    var width: CGFloat { max(280, spriteWidth + 20) }
    var height: CGFloat { 310 + spriteHeight - 104 }
    init(size: Double) {
        expansion = max(1, min(Self.maximumSize, size.isFinite ? size : 2) / 3)
    }
}
