import AppKit
import SwiftUI

/// `NSHostingView` configured to avoid driving window content-size extrema.
/// Do **not** override `updateConstraints` — skipping `super` leaves the dirty
/// flag set and AppKit aborts with:
/// "layout constraints still need update after calling -updateConstraints".
final class PassiveHostingView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = []
        translatesAutoresizingMaskIntoConstraints = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        let size = bounds.size
        if size.width < 1 || size.height < 1 {
            return NSSize(width: 1, height: 1)
        }
        return size
    }
}
