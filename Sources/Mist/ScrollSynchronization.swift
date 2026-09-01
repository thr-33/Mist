import AppKit
import Foundation

/// Identifies which split pane originated a user-driven scroll.
enum ScrollSyncPane: Equatable, Sendable {
    case source
    case preview
}

/// Pure normalized vertical scroll mapping (progress in 0...1).
///
/// Progress is relative to each pane's independently scrollable range so source
/// and preview stay aligned even when document heights differ.
enum VerticalScrollMapping {
    static let defaultEpsilon: Double = 0.000_5

    static func clampProgress(_ progress: Double) -> Double {
        if progress.isNaN || progress.isInfinite { return 0 }
        return min(max(progress, 0), 1)
    }

    /// Scrollable range in points. Zero when content fits in the viewport.
    static func scrollableRange(contentHeight: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        let content = max(contentHeight, 0)
        let viewport = max(viewportHeight, 0)
        return max(0, content - viewport)
    }

    static func progress(
        contentOffsetY: CGFloat,
        contentHeight: CGFloat,
        viewportHeight: CGFloat
    ) -> Double {
        let range = scrollableRange(contentHeight: contentHeight, viewportHeight: viewportHeight)
        guard range > 0 else { return 0 }
        return clampProgress(Double(contentOffsetY / range))
    }

    static func contentOffsetY(
        progress: Double,
        contentHeight: CGFloat,
        viewportHeight: CGFloat
    ) -> CGFloat {
        let range = scrollableRange(contentHeight: contentHeight, viewportHeight: viewportHeight)
        return CGFloat(clampProgress(progress)) * range
    }

    static func isNearlyEqual(
        _ a: Double,
        _ b: Double,
        epsilon: Double = defaultEpsilon
    ) -> Bool {
        abs(a - b) <= epsilon
    }

    @MainActor
    static func progress(from scrollView: NSScrollView) -> Double {
        let metrics = metrics(from: scrollView)
        return progress(
            contentOffsetY: metrics.offsetY,
            contentHeight: metrics.contentHeight,
            viewportHeight: metrics.viewportHeight
        )
    }

    @MainActor
    static func metrics(from scrollView: NSScrollView) -> (
        offsetY: CGFloat,
        contentHeight: CGFloat,
        viewportHeight: CGFloat
    ) {
        let clip = scrollView.contentView
        let offsetY = clip.bounds.origin.y
        let viewportHeight = clip.bounds.height
        let contentHeight = scrollView.documentView?.frame.height ?? 0
        return (offsetY, contentHeight, viewportHeight)
    }
}

/// Origin of a scroll notification reported by a pane.
enum ScrollSyncScrollKind: Equatable, Sendable {
    /// Trackpad/mouse live gesture (`didLiveScrollNotification`). Sticky until end.
    case live
    /// Bounds-only change (keyboard, caret, layout, non-live programmatic). Not sticky.
    case nonLive
}

/// Pure rules for accepting a user scroll and whether the follower needs an apply.
enum ScrollSyncPolicy {
    /// Reject echo from the pane currently receiving a programmatic apply, and reject
    /// the opposite pane while a live gesture owns `activeDriver`.
    ///
    /// Programmatic suppression is pane-scoped so the driving pane can keep reporting
    /// rapid consecutive events while the follower is being updated.
    static func shouldAcceptUserScroll(
        programmaticTarget: ScrollSyncPane?,
        activeDriver: ScrollSyncPane?,
        reportingPane: ScrollSyncPane
    ) -> Bool {
        if programmaticTarget == reportingPane { return false }
        if let activeDriver, activeDriver != reportingPane { return false }
        return true
    }

    /// Live gestures sticky-lock the driver until `endDriver`. Non-live events never
    /// establish a sticky lock (they may keep an existing same-pane live lock).
    static func driverAfterAccepting(
        activeDriver: ScrollSyncPane?,
        reportingPane: ScrollSyncPane,
        kind: ScrollSyncScrollKind
    ) -> ScrollSyncPane? {
        switch kind {
        case .live:
            return reportingPane
        case .nonLive:
            return activeDriver == reportingPane ? reportingPane : nil
        }
    }

    /// Whether progress changed enough to push to the opposite pane.
    static func shouldPropagate(from current: Double, to next: Double) -> Bool {
        !VerticalScrollMapping.isNearlyEqual(
            VerticalScrollMapping.clampProgress(current),
            VerticalScrollMapping.clampProgress(next)
        )
    }

    static func endDriver(
        activeDriver: ScrollSyncPane?,
        endingPane: ScrollSyncPane
    ) -> ScrollSyncPane? {
        activeDriver == endingPane ? nil : activeDriver
    }
}

/// Coordinates bidirectional normalized scroll sync between two `NSScrollView`s.
///
/// Held as a `@StateObject` without publishing progress so live scrolling does not
/// rebuild SwiftUI; apply calls mutate AppKit clip bounds directly.
@MainActor
final class ScrollSyncCoordinator: ObservableObject {
    private(set) var progress: Double = 0
    private(set) var activeDriver: ScrollSyncPane?

    /// Pane currently receiving a programmatic clip scroll; echo from that pane only.
    private var programmaticTarget: ScrollSyncPane?

    weak var sourceScrollView: NSScrollView?
    weak var previewScrollView: NSScrollView?

    var isApplyingProgrammatic: Bool { programmaticTarget != nil }

    func register(_ pane: ScrollSyncPane, scrollView: NSScrollView) {
        switch pane {
        case .source:
            sourceScrollView = scrollView
        case .preview:
            previewScrollView = scrollView
        }
    }

    func unregister(_ pane: ScrollSyncPane, scrollView: NSScrollView) {
        switch pane {
        case .source:
            if sourceScrollView === scrollView { sourceScrollView = nil }
        case .preview:
            if previewScrollView === scrollView { previewScrollView = nil }
        }
    }

    /// Report a scroll from `pane`. Use `.live` for live gestures and `.nonLive` for
    /// bounds-only / keyboard / caret / layout notifications.
    func userScrolled(_ pane: ScrollSyncPane, kind: ScrollSyncScrollKind) {
        guard ScrollSyncPolicy.shouldAcceptUserScroll(
            programmaticTarget: programmaticTarget,
            activeDriver: activeDriver,
            reportingPane: pane
        ) else { return }

        guard let scrollView = scrollView(for: pane) else { return }
        let next = VerticalScrollMapping.progress(from: scrollView)
        activeDriver = ScrollSyncPolicy.driverAfterAccepting(
            activeDriver: activeDriver,
            reportingPane: pane,
            kind: kind
        )

        guard ScrollSyncPolicy.shouldPropagate(from: progress, to: next) else { return }
        progress = next
        apply(progress, to: opposite(of: pane))
    }

    func endUserScroll(_ pane: ScrollSyncPane) {
        activeDriver = ScrollSyncPolicy.endDriver(activeDriver: activeDriver, endingPane: pane)
    }

    /// Re-apply the current progress to a pane (e.g. after content/layout change).
    func reapply(to pane: ScrollSyncPane) {
        apply(progress, to: pane)
    }

    private func opposite(of pane: ScrollSyncPane) -> ScrollSyncPane {
        switch pane {
        case .source: return .preview
        case .preview: return .source
        }
    }

    private func scrollView(for pane: ScrollSyncPane) -> NSScrollView? {
        switch pane {
        case .source: return sourceScrollView
        case .preview: return previewScrollView
        }
    }

    private func apply(_ progress: Double, to pane: ScrollSyncPane) {
        guard let scrollView = scrollView(for: pane) else { return }
        let metrics = VerticalScrollMapping.metrics(from: scrollView)
        let current = VerticalScrollMapping.progress(
            contentOffsetY: metrics.offsetY,
            contentHeight: metrics.contentHeight,
            viewportHeight: metrics.viewportHeight
        )
        if VerticalScrollMapping.isNearlyEqual(current, progress) {
            return
        }

        let targetY = VerticalScrollMapping.contentOffsetY(
            progress: progress,
            contentHeight: metrics.contentHeight,
            viewportHeight: metrics.viewportHeight
        )
        // Skip no-op moves (also covers zero-range → always 0).
        if abs(targetY - metrics.offsetY) < 0.5 {
            return
        }

        // Suppress only the follower's echo. Clear synchronously: AppKit posts
        // bounds changes during `scroll(to:)`, and an async clear would reject the
        // driver's next rapid event still pending on the main queue.
        programmaticTarget = pane
        let clip = scrollView.contentView
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: targetY))
        scrollView.reflectScrolledClipView(clip)
        programmaticTarget = nil
    }
}
