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
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 24, height: 20)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        textView.delegate = context.coordinator
        context.coordinator.textView = textView

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.onOpenFile = onOpenFile

        if textView.attributedString().isEqual(to: attributedText) {
            return
        }

        let selected = textView.selectedRanges
        textView.textStorage?.setAttributedString(attributedText)
        textView.backgroundColor = .textBackgroundColor
        if let ranges = selected as? [NSRange],
           let first = ranges.first,
           first.location + first.length <= textView.string.utf16.count {
            textView.selectedRanges = selected
        }
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
