import Foundation

/// AppKit screen coordinates; handles displays left of or below the primary display.
enum BuddyPlacement {
    static func fit(_ frame: CGRect, screens: [CGRect]) -> CGRect {
        guard let screen = screens.max(by: { overlap(frame, $0) < overlap(frame, $1) }) else { return frame }
        let target = screens.contains(where: { overlap(frame, $0) > 0 }) ? screen : screens[0]
        return CGRect(x: min(max(frame.minX, target.minX), max(target.minX, target.maxX - frame.width)),
                      y: min(max(frame.minY, target.minY), max(target.minY, target.maxY - frame.height)),
                      width: frame.width, height: frame.height)
    }

    private static func overlap(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}
