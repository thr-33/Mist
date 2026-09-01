import AppKit
import SwiftUI

/// Read-only NSTextView wrapper with selection, copy, and find.
struct MarkdownTextView: NSViewRepresentable {
    var attributedText: NSAttributedString
    var onOpenFile: ((URL) -> Void)?
    /// When non-nil (split mode), participates in bidirectional scroll sync.
    var scrollSync: ScrollSyncCoordinator? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenFile: onOpenFile, scrollSync: scrollSync)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.allowsUndo = false
        textView.drawsBackground = true
        // Kami page background (warm beige parchment in light mode)
        textView.backgroundColor = Kami.pageBackground
        textView.textContainerInset = NSSize(width: 24, height: 20)
        // Soft-wrap to pane; reading measure capped at ~680pt in updateNSView
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 5
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.linkTextAttributes = [
            .foregroundColor: Kami.accent,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        textView.delegate = context.coordinator
        context.coordinator.textView = textView
        context.coordinator.attachScrollObserver(to: scrollView)
        context.coordinator.scrollSync = scrollSync
        scrollSync?.register(.preview, scrollView: scrollView)

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Kami.pageBackground

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.onOpenFile = onOpenFile
        context.coordinator.scrollSync = scrollSync
        scrollSync?.register(.preview, scrollView: scrollView)

        // Keep parchment / charcoal in sync with appearance changes
        let page = Kami.pageBackground
        textView.backgroundColor = page
        scrollView.backgroundColor = page
        textView.linkTextAttributes = [
            .foregroundColor: Kami.accent,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        // Cap line length at ~680pt for comfortable reading measure
        applyReadingMeasure(to: textView, in: scrollView)

        var contentChanged = false
        if !textView.attributedString().isEqual(to: attributedText) {
            let selected = textView.selectedRanges
            textView.textStorage?.setAttributedString(attributedText)
            if let ranges = selected as? [NSRange],
               let first = ranges.first,
               first.location + first.length <= textView.string.utf16.count {
                textView.selectedRanges = selected
            }
            contentChanged = true
        }

        // Live preview / resize can change scrollable range — keep shared progress.
        if contentChanged {
            scrollSync?.reapply(to: .preview)
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.scrollSync?.unregister(.preview, scrollView: scrollView)
        coordinator.detachScrollObservers()
    }

    /// Cap container width at 680pt so long lines stay comfortable to read.
    private func applyReadingMeasure(to textView: NSTextView, in scrollView: NSScrollView) {
        guard let container = textView.textContainer else { return }
        let maxMeasure: CGFloat = 680
        let available = scrollView.contentView.bounds.width
            - textView.textContainerInset.width * 2
            - container.lineFragmentPadding * 2
        let target = min(max(available, 1), maxMeasure)
        if abs(container.containerSize.width - target) > 0.5 {
            container.containerSize = NSSize(width: target, height: CGFloat.greatestFiniteMagnitude)
        }
        // Track when narrower than the cap; freeze at 680 when the pane is wider
        container.widthTracksTextView = available <= maxMeasure
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var onOpenFile: ((URL) -> Void)?
        var scrollSync: ScrollSyncCoordinator?
        weak var textView: NSTextView?

        private var scrollObserver: NSObjectProtocol?
        private var boundsObserver: NSObjectProtocol?
        private var endLiveScrollObserver: NSObjectProtocol?

        init(onOpenFile: ((URL) -> Void)?, scrollSync: ScrollSyncCoordinator?) {
            self.onOpenFile = onOpenFile
            self.scrollSync = scrollSync
        }

        deinit {
            MainActor.assumeIsolated {
                detachScrollObservers()
            }
        }

        func detachScrollObservers() {
            let nc = NotificationCenter.default
            if let scrollObserver {
                nc.removeObserver(scrollObserver)
                self.scrollObserver = nil
            }
            if let boundsObserver {
                nc.removeObserver(boundsObserver)
                self.boundsObserver = nil
            }
            if let endLiveScrollObserver {
                nc.removeObserver(endLiveScrollObserver)
                self.endLiveScrollObserver = nil
            }
        }

        func attachScrollObserver(to scrollView: NSScrollView) {
            detachScrollObservers()
            let nc = NotificationCenter.default
            scrollObserver = nc.addObserver(
                forName: NSScrollView.didLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scrollSync?.userScrolled(.preview, kind: .live)
                }
            }
            endLiveScrollObserver = nc.addObserver(
                forName: NSScrollView.didEndLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.scrollSync?.endUserScroll(.preview)
                }
            }
            boundsObserver = nc.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    // Keyboard/caret/layout: propagate without sticky-locking.
                    self?.scrollSync?.userScrolled(.preview, kind: .nonLive)
                }
            }
            scrollView.contentView.postsBoundsChangedNotifications = true
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            // Consume click; links are visually distinct but navigation is optional
            return true
        }
    }
}
