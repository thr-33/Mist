import AppKit
import SwiftUI

/// Read-only NSTextView wrapper with selection, copy, and find.
struct MarkdownTextView: NSViewRepresentable {
    var attributedText: NSAttributedString
    var onOpenFile: ((URL) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onOpenFile: onOpenFile)
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

        if textView.attributedString().isEqual(to: attributedText) {
            return
        }

        let selected = textView.selectedRanges
        textView.textStorage?.setAttributedString(attributedText)
        if let ranges = selected as? [NSRange],
           let first = ranges.first,
           first.location + first.length <= textView.string.utf16.count {
            textView.selectedRanges = selected
        }
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

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onOpenFile: ((URL) -> Void)?
        weak var textView: NSTextView?

        init(onOpenFile: ((URL) -> Void)?) {
            self.onOpenFile = onOpenFile
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            // Consume click; links are visually distinct but navigation is optional
            return true
        }
    }
}
