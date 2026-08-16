import Foundation

/// Hand-rolled CommonMark-ish markdown parser (blocks + inlines).
public enum MarkdownParser {

    // MARK: - Public API

    public static func parse(_ markdown: String) -> [BlockNode] {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        return parseBlocks(lines)
    }

    public static func parseInlines(_ text: String) -> [InlineNode] {
        var result: [InlineNode] = []
        var i = text.startIndex
        var plain = ""

        func flushPlain() {
            if !plain.isEmpty {
                result.append(.text(plain))
                plain = ""
            }
        }

        while i < text.endIndex {
            // Inline code `...`
            if text[i] == "`" {
                if let end = findClosing(text, from: text.index(after: i), delimiter: "`") {
                    flushPlain()
                    result.append(.code(String(text[text.index(after: i)..<end])))
                    i = text.index(after: end)
                    continue
                }
            }

            // Bold **...**
            if text[i...].hasPrefix("**"),
               let end = findClosingPair(text, from: text.index(i, offsetBy: 2), delimiter: "**") {
                flushPlain()
                result.append(.bold(String(text[text.index(i, offsetBy: 2)..<end])))
                i = text.index(end, offsetBy: 2)
                continue
            }

            // Strikethrough ~~...~~
            if text[i...].hasPrefix("~~"),
               let end = findClosingPair(text, from: text.index(i, offsetBy: 2), delimiter: "~~") {
                flushPlain()
                result.append(.strikethrough(String(text[text.index(i, offsetBy: 2)..<end])))
                i = text.index(end, offsetBy: 2)
                continue
            }

            // Italic *...* (single asterisk, not part of **)
            if text[i] == "*", !text[i...].hasPrefix("**"),
               let end = findClosing(text, from: text.index(after: i), delimiter: "*"),
               end > text.index(after: i) {
                flushPlain()
                result.append(.italic(String(text[text.index(after: i)..<end])))
                i = text.index(after: end)
                continue
            }

            // Underline <u>...</u> (HTML-ish; markdown has no native underline)
            if text[i] == "<", text[i...].hasPrefix("<u>") {
                let contentStart = text.index(i, offsetBy: 3)
                if let end = findClosingTag(text, from: contentStart, tag: "</u>") {
                    flushPlain()
                    result.append(.underline(String(text[contentStart..<end])))
                    i = text.index(end, offsetBy: 4) // past </u>
                    continue
                }
            }

            // Link [text](url)
            if text[i] == "[",
               let link = parseLink(text, from: i) {
                flushPlain()
                result.append(.link(text: link.text, url: link.url))
                i = link.end
                continue
            }

            plain.append(text[i])
            i = text.index(after: i)
        }

        flushPlain()
        return result
    }

    // MARK: - Block parsing

    private static func parseBlocks(_ lines: [String]) -> [BlockNode] {
        var blocks: [BlockNode] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Fenced code block
            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    let codeLine = lines[i]
                    if codeLine.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeLines.append(codeLine)
                    i += 1
                }
                let lang: String? = language.isEmpty ? nil : language
                blocks.append(.codeBlock(language: lang, code: codeLines.joined(separator: "\n")))
                continue
            }

            // ATX heading
            if let heading = parseHeading(trimmed) {
                blocks.append(heading)
                i += 1
                continue
            }

            // Thematic break
            if isThematicBreak(trimmed) {
                blocks.append(.thematicBreak)
                i += 1
                continue
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count {
                    let q = lines[i].trimmingCharacters(in: .whitespaces)
                    if q.hasPrefix(">") {
                        var content = String(q.dropFirst())
                        if content.hasPrefix(" ") { content = String(content.dropFirst()) }
                        quoteLines.append(content)
                        i += 1
                    } else if q.isEmpty {
                        break
                    } else {
                        break
                    }
                }
                let inner = parseBlocks(quoteLines)
                blocks.append(.blockquote(inner.isEmpty ? [.paragraph(quoteLines.joined(separator: " "))] : inner))
                continue
            }

            // Unordered list
            if isUnorderedListItem(trimmed) {
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if let item = unorderedListItemText(t) {
                        items.append(item)
                        i += 1
                    } else if t.isEmpty {
                        break
                    } else {
                        break
                    }
                }
                blocks.append(.unorderedList(items))
                continue
            }

            // Ordered list
            if isOrderedListItem(trimmed) {
                var items: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if let item = orderedListItemText(t) {
                        items.append(item)
                        i += 1
                    } else if t.isEmpty {
                        break
                    } else {
                        break
                    }
                }
                blocks.append(.orderedList(items))
                continue
            }

            // GFM pipe table (header + delimiter row required)
            if lineContainsUnescapedPipe(trimmed),
               i + 1 < lines.count,
               let alignments = parseDelimiterRow(lines[i + 1].trimmingCharacters(in: .whitespaces)) {
                let headerCells = splitTableCells(trimmed)
                let colCount = max(headerCells.count, alignments.count, 1)
                var columns: [TableColumn] = []
                columns.reserveCapacity(colCount)
                for c in 0..<colCount {
                    let header = c < headerCells.count ? headerCells[c] : ""
                    let align = c < alignments.count ? alignments[c] : TableAlignment.left
                    columns.append(TableColumn(header: header, alignment: align))
                }
                i += 2 // consume header + delimiter
                var rows: [[String]] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if t.isEmpty { break }
                    if !lineContainsUnescapedPipe(t) { break }
                    rows.append(normalizeRow(splitTableCells(t), columnCount: colCount))
                    i += 1
                }
                blocks.append(.table(columns: columns, rows: rows))
                continue
            }

            // Paragraph (collect until blank or block start)
            var paraLines: [String] = [trimmed]
            i += 1
            while i < lines.count {
                let t = lines[i].trimmingCharacters(in: .whitespaces)
                if t.isEmpty { break }
                if t.hasPrefix("```") { break }
                if parseHeading(t) != nil { break }
                if isThematicBreak(t) { break }
                if t.hasPrefix(">") { break }
                if isUnorderedListItem(t) { break }
                if isOrderedListItem(t) { break }
                // Don't swallow a table start into a paragraph
                if lineContainsUnescapedPipe(t),
                   i + 1 < lines.count,
                   parseDelimiterRow(lines[i + 1].trimmingCharacters(in: .whitespaces)) != nil {
                    break
                }
                paraLines.append(t)
                i += 1
            }
            blocks.append(.paragraph(paraLines.joined(separator: " ")))
        }

        return blocks
    }

    // MARK: - Helpers

    private static func parseHeading(_ line: String) -> BlockNode? {
        guard line.hasPrefix("#") else { return nil }
        var level = 0
        var idx = line.startIndex
        while idx < line.endIndex && line[idx] == "#" && level < 6 {
            level += 1
            idx = line.index(after: idx)
        }
        guard level > 0, level <= 6 else { return nil }
        guard idx == line.endIndex || line[idx] == " " else { return nil }
        let text = line[idx...].trimmingCharacters(in: .whitespaces)
        return .heading(level: level, text: String(text))
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3 else { return false }
        return stripped.allSatisfy({ $0 == "-" })
            || stripped.allSatisfy({ $0 == "*" })
            || stripped.allSatisfy({ $0 == "_" })
    }

    private static func isUnorderedListItem(_ line: String) -> Bool {
        unorderedListItemText(line) != nil
    }

    private static func unorderedListItemText(_ line: String) -> String? {
        guard line.count >= 2 else { return nil }
        let c = line[line.startIndex]
        guard c == "-" || c == "*" else { return nil }
        let rest = line.dropFirst()
        guard rest.first == " " else { return nil }
        return String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
    }

    private static func isOrderedListItem(_ line: String) -> Bool {
        orderedListItemText(line) != nil
    }

    private static func orderedListItemText(_ line: String) -> String? {
        var idx = line.startIndex
        var sawDigit = false
        while idx < line.endIndex && line[idx].isNumber {
            sawDigit = true
            idx = line.index(after: idx)
        }
        guard sawDigit, idx < line.endIndex, line[idx] == "." else { return nil }
        idx = line.index(after: idx)
        guard idx < line.endIndex, line[idx] == " " else { return nil }
        return String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
    }

    private static func findClosing(_ text: String, from start: String.Index, delimiter: Character) -> String.Index? {
        var i = start
        while i < text.endIndex {
            if text[i] == delimiter { return i }
            if text[i] == "\n" { return nil }
            i = text.index(after: i)
        }
        return nil
    }

    private static func findClosingPair(_ text: String, from start: String.Index, delimiter: String) -> String.Index? {
        var i = start
        while i < text.endIndex {
            if text[i...].hasPrefix(delimiter) { return i }
            if text[i] == "\n" { return nil }
            i = text.index(after: i)
        }
        return nil
    }

    /// Finds the start index of a closing HTML-ish tag (e.g. `</u>`), single-line only.
    private static func findClosingTag(_ text: String, from start: String.Index, tag: String) -> String.Index? {
        var i = start
        while i < text.endIndex {
            if text[i...].hasPrefix(tag) { return i }
            if text[i] == "\n" { return nil }
            i = text.index(after: i)
        }
        return nil
    }

    private static func parseLink(_ text: String, from start: String.Index) -> (text: String, url: String, end: String.Index)? {
        guard text[start] == "[" else { return nil }
        var i = text.index(after: start)
        var linkText = ""
        while i < text.endIndex {
            if text[i] == "]" { break }
            if text[i] == "\n" { return nil }
            linkText.append(text[i])
            i = text.index(after: i)
        }
        guard i < text.endIndex, text[i] == "]" else { return nil }
        i = text.index(after: i)
        guard i < text.endIndex, text[i] == "(" else { return nil }
        i = text.index(after: i)
        var url = ""
        while i < text.endIndex {
            if text[i] == ")" {
                return (linkText, url, text.index(after: i))
            }
            if text[i] == "\n" { return nil }
            url.append(text[i])
            i = text.index(after: i)
        }
        return nil
    }

    // MARK: - GFM tables

    /// True if `line` has a `|` that is not escaped and not inside inline code backticks.
    private static func lineContainsUnescapedPipe(_ line: String) -> Bool {
        var inCode = false
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if c == "`" {
                inCode.toggle()
            } else if c == "\\", !inCode {
                let next = line.index(after: i)
                if next < line.endIndex {
                    i = next // skip escaped char
                }
            } else if c == "|", !inCode {
                return true
            }
            i = line.index(after: i)
        }
        return false
    }

    /// Split a table row into cells. Leading/trailing pipes are separators.
    /// `\|` → literal `|`; pipes inside `` `...` `` are literal.
    private static func splitTableCells(_ line: String) -> [String] {
        var cells: [String] = []
        var current = ""
        var inCode = false
        var i = line.startIndex

        while i < line.endIndex {
            let c = line[i]
            if c == "`" {
                inCode.toggle()
                current.append(c)
                i = line.index(after: i)
                continue
            }
            if !inCode, c == "\\" {
                let next = line.index(after: i)
                if next < line.endIndex, line[next] == "|" {
                    current.append("|")
                    i = line.index(after: next)
                    continue
                }
                // Keep other backslash escapes as-is (backslash + char)
                current.append(c)
                if next < line.endIndex {
                    current.append(line[next])
                    i = line.index(after: next)
                } else {
                    i = next
                }
                continue
            }
            if !inCode, c == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                i = line.index(after: i)
                continue
            }
            current.append(c)
            i = line.index(after: i)
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))

        // GFM: leading/trailing empty cells from edge pipes are separators, not cells
        if cells.count >= 2, cells.first?.isEmpty == true {
            cells.removeFirst()
        }
        if cells.count >= 1, cells.last?.isEmpty == true, line.trimmingCharacters(in: .whitespaces).hasSuffix("|") {
            cells.removeLast()
        }
        return cells
    }

    /// Parse a delimiter row like `| :--- | ---: | :---: | --- |`.
    /// Returns alignments if every cell matches `:?-{1,}:?` and there is ≥1 column.
    private static func parseDelimiterRow(_ line: String) -> [TableAlignment]? {
        guard lineContainsUnescapedPipe(line) || line.contains("-") else { return nil }
        let cells = splitTableCells(line)
        guard !cells.isEmpty else { return nil }
        var alignments: [TableAlignment] = []
        alignments.reserveCapacity(cells.count)
        for cell in cells {
            guard let align = parseDelimiterCell(cell) else { return nil }
            alignments.append(align)
        }
        return alignments
    }

    private static func parseDelimiterCell(_ cell: String) -> TableAlignment? {
        let t = cell.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        var s = t
        var leftColon = false
        var rightColon = false
        if s.first == ":" {
            leftColon = true
            s = String(s.dropFirst())
        }
        if s.last == ":" {
            rightColon = true
            s = String(s.dropLast())
        }
        guard !s.isEmpty, s.allSatisfy({ $0 == "-" }) else { return nil }
        if leftColon && rightColon { return .center }
        if rightColon { return .right }
        return .left
    }

    private static func normalizeRow(_ cells: [String], columnCount: Int) -> [String] {
        if cells.count == columnCount { return cells }
        if cells.count > columnCount {
            return Array(cells.prefix(columnCount))
        }
        var padded = cells
        while padded.count < columnCount {
            padded.append("")
        }
        return padded
    }
}
