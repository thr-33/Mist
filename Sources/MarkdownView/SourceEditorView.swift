import AppKit
import SwiftUI

/// Editable plain-text NSTextView for markdown source.
struct SourceEditorView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    var onTextChange: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextChange: onTextChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 16, height: 16)
        // Soft-wrap markdown prose to the pane width.
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 5
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.textColor = .labelColor
        textView.string = text
        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.onTextChange = onTextChange
        context.coordinator.isUpdating = true
        defer { context.coordinator.isUpdating = false }

        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if textView.font != font {
            textView.font = font
        }

        // Avoid clobbering in-progress typing / selection when text matches.
        if textView.string != text {
            let selected = textView.selectedRanges
            textView.string = text
            if let ranges = selected as? [NSRange],
               let first = ranges.first,
               first.location + first.length <= textView.string.utf16.count {
                textView.selectedRanges = selected
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onTextChange: (String) -> Void
        weak var textView: NSTextView?
        var isUpdating = false

        init(onTextChange: @escaping (String) -> Void) {
            self.onTextChange = onTextChange
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            onTextChange(textView.string)
        }
    }
}
