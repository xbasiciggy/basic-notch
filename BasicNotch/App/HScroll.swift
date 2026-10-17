import SwiftUI
import AppKit

/// Horizontal scroller for the notch's card rows (coins, friends, games, files):
/// a thin always-visible scroll bar, and a normal mouse wheel / two-finger vertical swipe scrolls sideways.
struct HScroll<Content: View>: NSViewRepresentable {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    /// The rows live in their own hosting view, which doesn't inherit the notch's dark styling.
    private var themed: AnyView {
        AnyView(content.environment(\.colorScheme, .dark).foregroundStyle(.white))
    }

    func makeNSView(context: Context) -> HorizontalScrollView {
        let scrollView = HorizontalScrollView()
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = false
        scrollView.autohidesScrollers = false
        scrollView.horizontalScroller = ThinScroller()
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .allowed
        let host = NotchHostingView(rootView: themed)
        host.sizingOptions = [.intrinsicContentSize]  // needed so the row can measure its cards
        scrollView.documentView = host
        return scrollView
    }

    func updateNSView(_ scrollView: HorizontalScrollView, context: Context) {
        (scrollView.documentView as? NotchHostingView<AnyView>)?.rootView = themed
        scrollView.needsLayout = true
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HorizontalScrollView, context: Context) -> CGSize? {
        let fit = nsView.documentView?.fittingSize ?? .zero
        return CGSize(width: proposal.width ?? fit.width, height: fit.height + ThinScroller.thickness + 4)
    }
}

final class HorizontalScrollView: NSScrollView {
    /// Keep the always-visible style even if the system prefers auto-hiding overlay scroll bars.
    override var scrollerStyle: NSScroller.Style {
        get { .legacy }
        set {}
    }

    override func layout() {
        super.layout()
        guard let document = documentView else { return }
        let fit = document.fittingSize
        let size = NSSize(width: max(fit.width, contentSize.width), height: contentSize.height)
        if document.frame.size != size { document.setFrameSize(size) }
    }

    override func scrollWheel(with event: NSEvent) {
        // Mostly-vertical scrolling (mouse wheel or trackpad) moves the row sideways instead.
        guard abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX), let document = documentView else {
            super.scrollWheel(with: event)
            return
        }
        let step = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 12
        let maxX = max(0, document.frame.width - contentView.bounds.width)
        var origin = contentView.bounds.origin
        origin.x = min(max(origin.x - step, 0), maxX)
        contentView.scroll(to: origin)
        reflectScrolledClipView(contentView)
    }
}

/// Slim white scroll bar that suits the black notch.
final class ThinScroller: NSScroller {
    static let thickness: CGFloat = 8

    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat {
        thickness
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        NSColor.white.withAlphaComponent(0.06).setFill()
        NSBezierPath(roundedRect: slotRect.insetBy(dx: 2, dy: 2), xRadius: 2, yRadius: 2).fill()
    }

    override func drawKnob() {
        let knob = rect(for: .knob).insetBy(dx: 2, dy: 2)
        guard knob.width > 0 else { return }
        NSColor.white.withAlphaComponent(0.4).setFill()
        NSBezierPath(roundedRect: knob, xRadius: knob.height / 2, yRadius: knob.height / 2).fill()
    }
}
