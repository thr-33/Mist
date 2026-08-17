import AppKit
import Foundation

/// Renders parsed markdown blocks into an `NSAttributedString` using semantic colors.
public enum MarkdownRenderer {

    public struct Style {
        public var baseFontSize: CGFloat
        public var bodyFont: NSFont
        public var monoFont: NSFont
        public var textColor: NSColor
        public var secondaryColor: NSColor
        public var codeBackground: NSColor
        public var linkColor: NSColor

        public init(baseFontSize: CGFloat = 14) {
            self.baseFontSize = baseFontSize
            self.bodyFont = NSFont.systemFont(ofSize: baseFontSize)
            self.monoFont = NSFont.monospacedSystemFont(ofSize: baseFontSize * 0.92, weight: .regular)
            self.textColor = .labelColor
            self.secondaryColor = .secondaryLabelColor
            self.codeBackground = NSColor.textBackgroundColor.blended(withFraction: 0.08, of: .labelColor)
                ?? NSColor.controlBackgroundColor
            self.linkColor = .linkColor
        }

        public func withFontSize(_ size: CGFloat) -> Style {
            Style(baseFontSize: size)
        }
    }

    public static func render(_ markdown: String, style: Style = Style()) -> NSAttributedString {
        let blocks = MarkdownParser.parse(markdown)
        return render(blocks: blocks, style: style)
    }

    public static func render(blocks: [BlockNode], style: Style = Style()) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, block) in blocks.enumerated() {
            let piece = renderBlock(block, style: style)
            result.append(piece)
            if index < blocks.count - 1 {
                result.append(NSAttributedString(string: "\n\n", attributes: baseAttrs(style)))
            }
        }
        return result
    }

    // MARK: - Blocks

    private static func renderBlock(_ block: BlockNode, style: Style) -> NSAttributedString {
        switch block {
        case .heading(let level, let text):
            let size: CGFloat = {
                switch level {
                case 1: return style.baseFontSize * 2.0
                case 2: return style.baseFontSize * 1.6
                case 3: return style.baseFontSize * 1.35
                case 4: return style.baseFontSize * 1.15
                case 5: return style.baseFontSize * 1.05
                default: return style.baseFontSize
                }
            }()
            let font = NSFont.systemFont(ofSize: size, weight: .bold)
            return renderInlines(text, font: font, color: style.textColor, style: style)

        case .paragraph(let text):
            return renderInlines(text, font: style.bodyFont, color: style.textColor, style: style)

        case .blockquote(let children):
            let inner = NSMutableAttributedString()
            for (i, child) in children.enumerated() {
                inner.append(renderBlock(child, style: style))
                if i < children.count - 1 {
                    inner.append(NSAttributedString(string: "\n", attributes: baseAttrs(style)))
                }
            }
            let range = NSRange(location: 0, length: inner.length)
            inner.addAttribute(.foregroundColor, value: style.secondaryColor, range: range)
            let para = NSMutableParagraphStyle()
            para.firstLineHeadIndent = 12
            para.headIndent = 12
            inner.addAttribute(.paragraphStyle, value: para, range: range)
            return inner

        case .codeBlock(_, let code):
            let para = NSMutableParagraphStyle()
            para.lineHeightMultiple = 1.15
            let attrs: [NSAttributedString.Key: Any] = [
                .font: style.monoFont,
                .foregroundColor: style.textColor,
                .backgroundColor: style.codeBackground,
                .paragraphStyle: para,
            ]
            let display = code.isEmpty ? " " : code
            return NSAttributedString(string: display, attributes: attrs)

        case .unorderedList(let items):
            let result = NSMutableAttributedString()
            for (i, item) in items.enumerated() {
                let bullet = NSAttributedString(string: "• ", attributes: baseAttrs(style))
                result.append(bullet)
                result.append(renderInlines(item, font: style.bodyFont, color: style.textColor, style: style))
                if i < items.count - 1 {
                    result.append(NSAttributedString(string: "\n", attributes: baseAttrs(style)))
                }
            }
            return result

        case .orderedList(let items):
            let result = NSMutableAttributedString()
            for (i, item) in items.enumerated() {
                let prefix = NSAttributedString(string: "\(i + 1). ", attributes: baseAttrs(style))
                result.append(prefix)
                result.append(renderInlines(item, font: style.bodyFont, color: style.textColor, style: style))
                if i < items.count - 1 {
                    result.append(NSAttributedString(string: "\n", attributes: baseAttrs(style)))
                }
            }
            return result

        case .thematicBreak:
            let attrs: [NSAttributedString.Key: Any] = [
                .font: style.bodyFont,
                .foregroundColor: style.secondaryColor,
            ]
            return NSAttributedString(string: "────────────", attributes: attrs)

        case .table(let columns, let rows):
            return renderTable(columns: columns, rows: rows, style: style)
        }
    }

    // MARK: - Tables

    private static func renderTable(
        columns: [TableColumn],
        rows: [[String]],
        style: Style
    ) -> NSAttributedString {
        let colCount = max(columns.count, 1)
        let table = NSTextTable()
        table.numberOfColumns = colCount
        table.collapsesBorders = true
        table.setBorderColor(NSColor.separatorColor)
        // Border width applied per cell block below
        table.layoutAlgorithm = .automaticLayoutAlgorithm

        let result = NSMutableAttributedString()
        let boldHeaderFont = NSFontManager.shared.convert(style.bodyFont, toHaveTrait: .boldFontMask)

        // Header row
        if columns.isEmpty {
            appendTableCell(
                to: result,
                text: "",
                table: table,
                row: 0,
                column: 0,
                columnCount: 1,
                alignment: .left,
                font: boldHeaderFont,
                style: style
            )
        } else {
            for (col, column) in columns.enumerated() {
                appendTableCell(
                    to: result,
                    text: column.header,
                    table: table,
                    row: 0,
                    column: col,
                    columnCount: colCount,
                    alignment: column.alignment,
                    font: boldHeaderFont,
                    style: style
                )
            }
        }

        // Body rows
        for (r, row) in rows.enumerated() {
            for c in 0..<colCount {
                let cellText = c < row.count ? row[c] : ""
                let align = c < columns.count ? columns[c].alignment : TableAlignment.left
                appendTableCell(
                    to: result,
                    text: cellText,
                    table: table,
                    row: r + 1,
                    column: c,
                    columnCount: colCount,
                    alignment: align,
                    font: style.bodyFont,
                    style: style
                )
            }
        }

        // Trailing newline so following blocks don't merge into the table's last cell
        result.append(NSAttributedString(string: "\n", attributes: baseAttrs(style)))
        return result
    }

    private static func appendTableCell(
        to result: NSMutableAttributedString,
        text: String,
        table: NSTextTable,
        row: Int,
        column: Int,
        columnCount: Int,
        alignment: TableAlignment,
        font: NSFont,
        style: Style
    ) {
        let block = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
        block.setBorderColor(NSColor.separatorColor)
        block.setWidth(0.5, type: .absoluteValueType, for: .border)
        block.setWidth(6, type: .absoluteValueType, for: .padding)
        // Equal percentage widths keep columns aligned
        let pct = 100.0 / CGFloat(max(columnCount, 1))
        block.setValue(pct, type: .percentageValueType, for: .width)

        let para = NSMutableParagraphStyle()
        para.textBlocks = [block]
        switch alignment {
        case .left: para.alignment = .left
        case .center: para.alignment = .center
        case .right: para.alignment = .right
        }

        // NBSP keeps empty cells from collapsing during layout
        let display = text.isEmpty ? "\u{00A0}" : text
        let cellContent = renderInlines(display, font: font, color: style.textColor, style: style)
        let mutable = NSMutableAttributedString(attributedString: cellContent)
        if mutable.length == 0 {
            mutable.append(NSAttributedString(string: "\u{00A0}", attributes: [
                .font: font,
                .foregroundColor: style.textColor,
            ]))
        }
        // Terminate cell paragraph with \n so NSTextView assembles contiguous table cells
        mutable.append(NSAttributedString(string: "\n", attributes: [
            .font: font,
            .foregroundColor: style.textColor,
        ]))
        let range = NSRange(location: 0, length: mutable.length)
        mutable.addAttribute(.paragraphStyle, value: para, range: range)

        result.append(mutable)
    }

    // MARK: - Inlines

    private static func renderInlines(
        _ text: String,
        font: NSFont,
        color: NSColor,
        style: Style
    ) -> NSAttributedString {
        let nodes = MarkdownParser.parseInlines(text)
        let result = NSMutableAttributedString()
        for node in nodes {
            result.append(renderInline(node, font: font, color: color, style: style))
        }
        return result
    }

    private static func renderInline(
        _ node: InlineNode,
        font: NSFont,
        color: NSColor,
        style: Style
    ) -> NSAttributedString {
        switch node {
        case .text(let s):
            return NSAttributedString(string: s, attributes: [
                .font: font,
                .foregroundColor: color,
            ])

        case .bold(let s):
            let bold = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
            return NSAttributedString(string: s, attributes: [
                .font: bold,
                .foregroundColor: color,
            ])

        case .italic(let s):
            let italic = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
            return NSAttributedString(string: s, attributes: [
                .font: italic,
                .foregroundColor: color,
            ])

        case .code(let s):
            return NSAttributedString(string: s, attributes: [
                .font: style.monoFont,
                .foregroundColor: color,
                .backgroundColor: style.codeBackground,
            ])

        case .link(let text, let url):
            return NSAttributedString(string: text, attributes: [
                .font: font,
                .foregroundColor: style.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .toolTip: url,
                .link: url,
            ])

        case .strikethrough(let s):
            return NSAttributedString(string: s, attributes: [
                .font: font,
                .foregroundColor: color,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            ])

        case .underline(let s):
            return NSAttributedString(string: s, attributes: [
                .font: font,
                .foregroundColor: color,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
            ])
        }
    }

    private static func baseAttrs(_ style: Style) -> [NSAttributedString.Key: Any] {
        [
            .font: style.bodyFont,
            .foregroundColor: style.textColor,
        ]
    }
}
