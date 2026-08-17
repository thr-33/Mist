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
        context.coordinator.attachScrollObserver(to: scrollView)

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

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate, NSPopoverDelegate {
        var onTextChange: (String) -> Void
        weak var textView: NSTextView?
        var isUpdating = false

        private var formatPopover: NSPopover?
        private var scrollObserver: NSObjectProtocol?
        private var boundsObserver: NSObjectProtocol?
        /// Suppress re-entrant selection updates while we adjust selection after format.
        private var isApplyingFormat = false

        init(onTextChange: @escaping (String) -> Void) {
            self.onTextChange = onTextChange
        }

        deinit {
            // Coordinator is @MainActor; deinit is nonisolated. Observer tokens are
            // non-Sendable NSObjectProtocol — tear down under MainActor isolation.
            MainActor.assumeIsolated {
                if let scrollObserver {
                    NotificationCenter.default.removeObserver(scrollObserver)
                }
                if let boundsObserver {
                    NotificationCenter.default.removeObserver(boundsObserver)
                }
            }
        }

        func attachScrollObserver(to scrollView: NSScrollView) {
            if let scrollObserver {
                NotificationCenter.default.removeObserver(scrollObserver)
            }
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            let nc = NotificationCenter.default
            scrollObserver = nc.addObserver(
                forName: NSScrollView.didLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.hideFormatToolbar()
                }
            }
            boundsObserver = nc.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.hideFormatToolbar()
                }
            }
            scrollView.contentView.postsBoundsChangedNotifications = true
        }

        func textDidChange(_ notification: Notification) {
            guard !isUpdating, let textView = notification.object as? NSTextView else { return }
            onTextChange(textView.string)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdating, !isApplyingFormat else { return }
            guard let textView = notification.object as? NSTextView else { return }
            updateFormatToolbar(for: textView)
        }

        func textDidEndEditing(_ notification: Notification) {
            hideFormatToolbar()
        }

        // MARK: - Format toolbar

        private func updateFormatToolbar(for textView: NSTextView) {
            let range = textView.selectedRange()
            guard range.length > 0,
                  range.location != NSNotFound,
                  range.location + range.length <= (textView.string as NSString).length
            else {
                hideFormatToolbar()
                return
            }
            guard textView.window?.firstResponder === textView else {
                hideFormatToolbar()
                return
            }
            showFormatToolbar(for: textView, selection: range)
        }

        private func showFormatToolbar(for textView: NSTextView, selection: NSRange) {
            let nsString = textView.string as NSString
            let selectedText = nsString.substring(with: selection)
            let isMultiLine = selectedText.contains("\n")

            let toolbar = FormatToolbarViewController(
                isMultiLine: isMultiLine,
                onAction: { [weak self] action in
                    self?.handleToolbarAction(action, in: textView)
                }
            )

            let popover = formatPopover ?? NSPopover()
            popover.behavior = .transient
            popover.animates = false
            popover.contentViewController = toolbar
            popover.delegate = self
            popover.contentSize = toolbar.preferredContentSize
            formatPopover = popover

            guard let anchor = selectionAnchorRect(in: textView, range: selection) else {
                hideFormatToolbar()
                return
            }

            popover.show(relativeTo: anchor, of: textView, preferredEdge: .minY)

            // Restore first responder to the text view after popover presentation.
            DispatchQueue.main.async { [weak textView] in
                textView?.window?.makeFirstResponder(textView)
            }
        }

        private func selectionAnchorRect(in textView: NSTextView, range: NSRange) -> NSRect? {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer
            else { return nil }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            rect.origin.x += textView.textContainerOrigin.x
            rect.origin.y += textView.textContainerOrigin.y

            // Clamp to visible rect so the popover stays on-screen near selection.
            if let scrollView = textView.enclosingScrollView {
                let visible = textView.convert(scrollView.documentVisibleRect, from: scrollView.contentView)
                if rect.maxY < visible.minY || rect.minY > visible.maxY {
                    return nil
                }
                let clipped = rect.intersection(visible)
                if !clipped.isNull && !clipped.isEmpty {
                    rect = clipped
                }
            }

            // Prefer anchoring above the first line of the selection.
            if rect.height > 28 {
                rect.size.height = 18
            }
            if rect.width < 2 {
                rect.size.width = 2
            }
            return rect
        }

        func hideFormatToolbar() {
            guard let popover = formatPopover, popover.isShown else { return }
            popover.performClose(nil)
        }

        // MARK: - Apply formatting

        private enum FormatAction: Int {
            case bold
            case italic
            case underline
            case strikethrough
            case inlineCode
            case link
            case heading
            case quote
            case bulletList
            case codeBlock
        }

        private func handleToolbarAction(_ action: FormatAction, in textView: NSTextView) {
            let range = textView.selectedRange()
            guard range.length > 0 else { return }

            isApplyingFormat = true
            defer {
                isApplyingFormat = false
                DispatchQueue.main.async { [weak self, weak textView] in
                    guard let self, let textView else { return }
                    textView.window?.makeFirstResponder(textView)
                    self.updateFormatToolbar(for: textView)
                }
            }

            switch action {
            case .bold:
                toggleInlineWrap(textView, range: range, prefix: "**", suffix: "**")
            case .italic:
                toggleInlineWrap(textView, range: range, prefix: "*", suffix: "*")
            case .underline:
                toggleInlineWrap(textView, range: range, prefix: "<u>", suffix: "</u>")
            case .strikethrough:
                toggleInlineWrap(textView, range: range, prefix: "~~", suffix: "~~")
            case .inlineCode:
                toggleInlineWrap(textView, range: range, prefix: "`", suffix: "`")
            case .link:
                promptAndApplyLink(in: textView, range: range)
            case .heading:
                toggleLinePrefix(textView, range: range, prefix: "# ")
            case .quote:
                toggleLinePrefix(textView, range: range, prefix: "> ")
            case .bulletList:
                toggleLinePrefix(textView, range: range, prefix: "- ")
            case .codeBlock:
                toggleCodeBlock(textView, range: range)
            }
        }

        /// Replace text through the normal editing path so undo works.
        @discardableResult
        private func replaceText(in textView: NSTextView, range: NSRange, with replacement: String) -> Bool {
            guard textView.shouldChangeText(in: range, replacementString: replacement) else {
                return false
            }
            textView.textStorage?.beginEditing()
            textView.textStorage?.replaceCharacters(in: range, with: replacement)
            textView.textStorage?.endEditing()
            textView.didChangeText()
            onTextChange(textView.string)
            return true
        }

        private func toggleInlineWrap(
            _ textView: NSTextView,
            range: NSRange,
            prefix: String,
            suffix: String
        ) {
            let ns = textView.string as NSString
            let selected = ns.substring(with: range)
            let preLen = (prefix as NSString).length
            let sufLen = (suffix as NSString).length

            // Already wrapped by delimiters inside selection.
            if selected.hasPrefix(prefix),
               selected.hasSuffix(suffix),
               (selected as NSString).length >= preLen + sufLen {
                let innerStart = preLen
                let innerLen = (selected as NSString).length - preLen - sufLen
                let inner = (selected as NSString).substring(
                    with: NSRange(location: innerStart, length: max(0, innerLen))
                )
                guard replaceText(in: textView, range: range, with: inner) else { return }
                textView.setSelectedRange(NSRange(location: range.location, length: (inner as NSString).length))
                return
            }

            // Delimiters immediately outside selection.
            if range.location >= preLen {
                let outerLoc = range.location - preLen
                let outerLen = range.length + preLen + sufLen
                if outerLoc + outerLen <= ns.length {
                    let outer = ns.substring(with: NSRange(location: outerLoc, length: outerLen))
                    if outer.hasPrefix(prefix), outer.hasSuffix(suffix) {
                        guard replaceText(
                            in: textView,
                            range: NSRange(location: outerLoc, length: outerLen),
                            with: selected
                        ) else { return }
                        textView.setSelectedRange(NSRange(location: outerLoc, length: range.length))
                        return
                    }
                }
            }

            let wrapped = prefix + selected + suffix
            guard replaceText(in: textView, range: range, with: wrapped) else { return }
            // Select the content without delimiters so toolbar stays and toggle works.
            textView.setSelectedRange(NSRange(location: range.location + preLen, length: range.length))
        }

        private func promptAndApplyLink(in textView: NSTextView, range: NSRange) {
            let ns = textView.string as NSString
            let selected = ns.substring(with: range)

            // Toggle off if selection is a full `[text](url)` span.
            if selected.hasPrefix("["),
               let closeBracket = selected.range(of: "]("),
               selected.hasSuffix(")"),
               selected.distance(from: selected.startIndex, to: closeBracket.lowerBound) >= 1 {
                let textPart = String(
                    selected[selected.index(after: selected.startIndex)..<closeBracket.lowerBound]
                )
                guard replaceText(in: textView, range: range, with: textPart) else { return }
                textView.setSelectedRange(NSRange(location: range.location, length: (textPart as NSString).length))
                return
            }

            // Detect surrounding [selected](url) and unwrap.
            if range.location >= 1 {
                let checkStart = range.location - 1
                let afterSel = range.location + range.length
                if ns.substring(with: NSRange(location: checkStart, length: 1)) == "[",
                   afterSel + 2 <= ns.length,
                   ns.substring(with: NSRange(location: afterSel, length: 2)) == "](" {
                    var j = afterSel + 2
                    while j < ns.length {
                        let ch = ns.substring(with: NSRange(location: j, length: 1))
                        if ch == ")" {
                            let fullRange = NSRange(location: checkStart, length: j - checkStart + 1)
                            guard replaceText(in: textView, range: fullRange, with: selected) else { return }
                            textView.setSelectedRange(NSRange(location: checkStart, length: range.length))
                            return
                        }
                        if ch == "\n" { break }
                        j += 1
                    }
                }
            }

            let alert = NSAlert()
            alert.messageText = "Insert Link"
            alert.informativeText = "Enter the URL for the selected text."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Cancel")

            let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
            input.stringValue = "https://"
            input.placeholderString = "https://example.com"
            alert.accessoryView = input
            alert.window.initialFirstResponder = input

            hideFormatToolbar()

            let response = alert.runModal()
            textView.window?.makeFirstResponder(textView)
            guard response == .alertFirstButtonReturn else {
                textView.setSelectedRange(range)
                return
            }

            var url = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if url.isEmpty { url = "https://" }

            let wrapped = "[\(selected)](\(url))"
            guard replaceText(in: textView, range: range, with: wrapped) else { return }
            // Select the link text inside brackets.
            textView.setSelectedRange(NSRange(location: range.location + 1, length: range.length))
        }

        private func toggleLinePrefix(_ textView: NSTextView, range: NSRange, prefix: String) {
            let ns = textView.string as NSString
            let lineRange = ns.lineRange(for: range)
            let rawLines = ns.substring(with: lineRange)
            var lineParts: [String] = []
            rawLines.enumerateLines { line, _ in
                lineParts.append(line)
            }
            let endsWithNewline = rawLines.hasSuffix("\n")
            guard !lineParts.isEmpty else { return }

            let hasContent = lineParts.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            let allPrefixed = hasContent && lineParts.allSatisfy { line in
                line.hasPrefix(prefix) || line.trimmingCharacters(in: .whitespaces).isEmpty
            }

            let newLines: [String]
            if allPrefixed {
                newLines = lineParts.map { line in
                    if line.hasPrefix(prefix) {
                        return String(line.dropFirst(prefix.count))
                    }
                    return line
                }
            } else {
                newLines = lineParts.map { line in
                    if line.trimmingCharacters(in: .whitespaces).isEmpty { return line }
                    if line.hasPrefix(prefix) { return line }
                    return prefix + line
                }
            }

            var replacement = newLines.joined(separator: "\n")
            if endsWithNewline {
                replacement += "\n"
            }

            guard replaceText(in: textView, range: lineRange, with: replacement) else { return }
            let newLen = (replacement as NSString).length
            let selLen = endsWithNewline ? max(0, newLen - 1) : newLen
            textView.setSelectedRange(NSRange(location: lineRange.location, length: selLen))
        }

        private func toggleCodeBlock(_ textView: NSTextView, range: NSRange) {
            let ns = textView.string as NSString
            let selected = ns.substring(with: range)

            // If selection itself is a fenced block, unwrap.
            let trimmed = selected.trimmingCharacters(in: .newlines)
            if trimmed.hasPrefix("```"), trimmed.hasSuffix("```"), trimmed != "```" {
                var lines = selected.components(separatedBy: "\n")
                if lines.first?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true {
                    lines.removeFirst()
                }
                if lines.last?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true {
                    lines.removeLast()
                }
                let inner = lines.joined(separator: "\n")
                guard replaceText(in: textView, range: range, with: inner) else { return }
                textView.setSelectedRange(NSRange(location: range.location, length: (inner as NSString).length))
                return
            }

            // Expand to full lines for fencing.
            let lineRange = ns.lineRange(for: range)
            let block = ns.substring(with: lineRange)
            let endsWithNewline = block.hasSuffix("\n")
            var content = block
            if endsWithNewline {
                content = String(content.dropLast())
            }

            // Check surrounding fences outside selection.
            let before = lineRange.location
            let after = lineRange.location + lineRange.length
            var prevIsFence = false
            var nextIsFence = false
            var fenceStart = lineRange.location
            var fenceEnd = after

            if before > 0 {
                let prevLineRange = ns.lineRange(for: NSRange(location: before - 1, length: 0))
                let prevLine = ns.substring(with: prevLineRange)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if prevLine.hasPrefix("```") {
                    prevIsFence = true
                    fenceStart = prevLineRange.location
                }
            }
            if after < ns.length {
                let nextLineRange = ns.lineRange(for: NSRange(location: after, length: 0))
                let nextLine = ns.substring(with: nextLineRange)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if nextLine.hasPrefix("```") {
                    nextIsFence = true
                    fenceEnd = nextLineRange.location + nextLineRange.length
                }
            }

            if prevIsFence && nextIsFence {
                let fullRange = NSRange(location: fenceStart, length: fenceEnd - fenceStart)
                let full = ns.substring(with: fullRange)
                var lines = full.components(separatedBy: "\n")
                if let first = lines.first, first.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    lines.removeFirst()
                }
                if let last = lines.last, last.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    lines.removeLast()
                } else if lines.count >= 2,
                          lines[lines.count - 2].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    lines.remove(at: lines.count - 2)
                    if lines.last == "" { lines.removeLast() }
                }
                let inner = lines.joined(separator: "\n")
                guard replaceText(in: textView, range: fullRange, with: inner) else { return }
                textView.setSelectedRange(NSRange(location: fenceStart, length: (inner as NSString).length))
                return
            }

            // Wrap
            var wrapped = "```\n" + content + "\n```"
            if endsWithNewline {
                wrapped += "\n"
            }
            guard replaceText(in: textView, range: lineRange, with: wrapped) else { return }
            let innerStart = lineRange.location + 4 // ```\n
            let innerLen = (content as NSString).length
            textView.setSelectedRange(NSRange(location: innerStart, length: innerLen))
        }
    }
}

// MARK: - Format toolbar UI

@MainActor
private final class FormatToolbarViewController: NSViewController {
    private let isMultiLine: Bool
    private let onAction: (SourceEditorView.Coordinator.FormatActionTag) -> Void

    init(
        isMultiLine: Bool,
        onAction: @escaping (SourceEditorView.Coordinator.FormatActionTag) -> Void
    ) {
        self.isMultiLine = isMultiLine
        self.onAction = onAction
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        stack.alignment = .centerY

        let inline: [(String, String, SourceEditorView.Coordinator.FormatActionTag)] = [
            ("bold", "Bold", .bold),
            ("italic", "Italic", .italic),
            ("underline", "Underline", .underline),
            ("strikethrough", "Strikethrough", .strikethrough),
            ("chevron.left.forwardslash.chevron.right", "Inline Code", .inlineCode),
            ("link", "Link", .link),
        ]
        let block: [(String, String, SourceEditorView.Coordinator.FormatActionTag)] = [
            ("number", "Heading", .heading),
            ("text.quote", "Quote", .quote),
            ("list.bullet", "Bullet List", .bulletList),
            ("curlybraces", "Code Block", .codeBlock),
        ]

        for (symbol, tip, action) in inline {
            let btn = makeButton(symbol: symbol, tooltip: tip, action: action)
            btn.isEnabled = !isMultiLine
            stack.addArrangedSubview(btn)
        }

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: 18),
        ])
        stack.addArrangedSubview(divider)

        for (symbol, tip, action) in block {
            let btn = makeButton(symbol: symbol, tooltip: tip, action: action)
            stack.addArrangedSubview(btn)
        }

        let container = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        self.view = container
        preferredContentSize = NSSize(width: isMultiLine ? 160 : 320, height: 36)
    }

    private func makeButton(
        symbol: String,
        tooltip: String,
        action: SourceEditorView.Coordinator.FormatActionTag
    ) -> NSButton {
        let btn = NSButton(frame: .zero)
        btn.bezelStyle = .toolbar
        btn.isBordered = false
        btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        btn.imagePosition = .imageOnly
        btn.imageScaling = .scaleProportionallyDown
        btn.toolTip = tooltip
        btn.setButtonType(.momentaryChange)
        btn.target = self
        btn.action = #selector(buttonPressed(_:))
        btn.tag = action.rawValue
        btn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            btn.widthAnchor.constraint(equalToConstant: 28),
            btn.heightAnchor.constraint(equalToConstant: 28),
        ])
        btn.focusRingType = .none
        btn.refusesFirstResponder = true
        return btn
    }

    @objc private func buttonPressed(_ sender: NSButton) {
        guard let action = SourceEditorView.Coordinator.FormatActionTag(rawValue: sender.tag) else { return }
        onAction(action)
    }
}

extension SourceEditorView.Coordinator {
    /// Int-backed tags for toolbar buttons.
    enum FormatActionTag: Int {
        case bold
        case italic
        case underline
        case strikethrough
        case inlineCode
        case link
        case heading
        case quote
        case bulletList
        case codeBlock
    }

    fileprivate func handleToolbarAction(_ action: FormatActionTag, in textView: NSTextView) {
        guard let mapped = FormatAction(rawValue: action.rawValue) else { return }
        // Call private path via same raw values
        applyMapped(mapped, in: textView)
    }

    private func applyMapped(_ action: FormatAction, in textView: NSTextView) {
        // Re-route through handleToolbarAction's switch by inlining call:
        let range = textView.selectedRange()
        guard range.length > 0 else { return }

        isApplyingFormat = true
        defer {
            isApplyingFormat = false
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                textView.window?.makeFirstResponder(textView)
                self.updateFormatToolbar(for: textView)
            }
        }

        switch action {
        case .bold:
            toggleInlineWrap(textView, range: range, prefix: "**", suffix: "**")
        case .italic:
            toggleInlineWrap(textView, range: range, prefix: "*", suffix: "*")
        case .underline:
            toggleInlineWrap(textView, range: range, prefix: "<u>", suffix: "</u>")
        case .strikethrough:
            toggleInlineWrap(textView, range: range, prefix: "~~", suffix: "~~")
        case .inlineCode:
            toggleInlineWrap(textView, range: range, prefix: "`", suffix: "`")
        case .link:
            promptAndApplyLink(in: textView, range: range)
        case .heading:
            toggleLinePrefix(textView, range: range, prefix: "# ")
        case .quote:
            toggleLinePrefix(textView, range: range, prefix: "> ")
        case .bulletList:
            toggleLinePrefix(textView, range: range, prefix: "- ")
        case .codeBlock:
            toggleCodeBlock(textView, range: range)
        }
    }
}
