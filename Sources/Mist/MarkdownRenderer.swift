import AppKit
import Foundation

// MARK: - Kami warm paper palette

/// Kami (紙) warm parchment palette — programmatic NSColors, no asset catalog.
public enum Kami {
    // Light surfaces — original Kami palette (#F5F4ED / #FAF9F5)
    public static let parchment = NSColor(srgbRed: 0xF5 / 255, green: 0xF4 / 255, blue: 0xED / 255, alpha: 1)
    public static let ivory = NSColor(srgbRed: 0xFA / 255, green: 0xF9 / 255, blue: 0xF5 / 255, alpha: 1)
    // Text (warm olive undertones)
    public static let nearBlack = NSColor(srgbRed: 0x14 / 255, green: 0x14 / 255, blue: 0x13 / 255, alpha: 1)
    public static let darkWarm = NSColor(srgbRed: 0x3D / 255, green: 0x3D / 255, blue: 0x3A / 255, alpha: 1)
    public static let olive = NSColor(srgbRed: 0x50 / 255, green: 0x4E / 255, blue: 0x49 / 255, alpha: 1)
    public static let stone = NSColor(srgbRed: 0x6B / 255, green: 0x6A / 255, blue: 0x64 / 255, alpha: 1)
    // Accent — original Kami ink-blue
    public static let brand = NSColor(srgbRed: 0x1B / 255, green: 0x36 / 255, blue: 0x5D / 255, alpha: 1)
    public static let brandLight = NSColor(srgbRed: 0x2D / 255, green: 0x5A / 255, blue: 0x8A / 255, alpha: 1)
    // Borders
    public static let border = NSColor(srgbRed: 0xE8 / 255, green: 0xE6 / 255, blue: 0xDC / 255, alpha: 1)
    public static let borderSoft = NSColor(srgbRed: 0xE5 / 255, green: 0xE3 / 255, blue: 0xD8 / 255, alpha: 1)
    // Dark mode surfaces
    public static let darkSurface = NSColor(srgbRed: 0x30 / 255, green: 0x30 / 255, blue: 0x2E / 255, alpha: 1)
    public static let deepDark = NSColor(srgbRed: 0x14 / 255, green: 0x14 / 255, blue: 0x13 / 255, alpha: 1)
    public static let darkIvory = NSColor(srgbRed: 0x3A / 255, green: 0x3A / 255, blue: 0x37 / 255, alpha: 1)
    // Dark mode text
    public static let darkPrimary = NSColor(srgbRed: 0xF5 / 255, green: 0xF4 / 255, blue: 0xED / 255, alpha: 1)
    public static let darkSecondary = NSColor(srgbRed: 0xC8 / 255, green: 0xC6 / 255, blue: 0xB8 / 255, alpha: 1)
    public static let darkTertiary = NSColor(srgbRed: 0x9A / 255, green: 0x98 / 255, blue: 0x8C / 255, alpha: 1)

    /// True when the current drawing appearance is dark.
    /// Uses `NSAppearance.currentDrawing()` so callers need not be on the main actor
    /// (tests and background render paths stay nonisolated-safe).
    public static var isDark: Bool {
        let appearance = NSAppearance.currentDrawing()
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    /// Page / preview background (parchment ↔ warm charcoal).
    public static var pageBackground: NSColor {
        isDark ? darkSurface : parchment
    }

    /// Source editor background — ivory in light, slightly deeper charcoal in dark.
    public static var editorBackground: NSColor {
        isDark ? deepDark : ivory
    }

    /// Lifted card / code-block fill.
    public static var codeFill: NSColor {
        isDark ? darkIvory : ivory
    }

    /// Primary body text.
    public static var primaryText: NSColor {
        isDark ? darkPrimary : nearBlack
    }

    /// Secondary text (table headers, secondary labels).
    public static var secondaryText: NSColor {
        isDark ? darkSecondary : darkWarm
    }

    /// Subtext / blockquote body.
    public static var subtext: NSColor {
        isDark ? darkTertiary : olive
    }

    /// Metadata / tertiary.
    public static var tertiaryText: NSColor {
        isDark ? darkTertiary : stone
    }

    /// Ink-blue accent (links, markers, kick-lines). Brighter on dark surfaces.
    public static var accent: NSColor {
        isDark ? brandLight : brand
    }

    /// Dividers / table borders.
    public static var divider: NSColor {
        isDark ? NSColor(srgbRed: 0x4A / 255, green: 0x4A / 255, blue: 0x46 / 255, alpha: 1) : border
    }

    // MARK: Fonts

    /// Serif body/heading family: Charter → Palatino → Georgia → system.
    public static func serifFont(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        let candidates = ["Charter", "Palatino", "Georgia"]
        for name in candidates {
            if let base = NSFont(name: name, size: size) {
                let manager = NSFontManager.shared
                let traits: NSFontTraitMask = weight >= .semibold ? .boldFontMask : []
                if let converted = manager.font(
                    withFamily: base.familyName ?? name,
                    traits: traits,
                    weight: weightValue(weight),
                    size: size
                ) {
                    return converted
                }
                return base
            }
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    /// Monospace: JetBrains Mono → system monospaced.
    public static func monoFont(ofSize size: CGFloat) -> NSFont {
        if let font = NSFont(name: "JetBrains Mono", size: size)
            ?? NSFont(name: "JetBrainsMono-Regular", size: size) {
            return font
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// NSFontManager weight scale (0…15); 5 ≈ regular, 6 ≈ medium/semibold-ish.
    private static func weightValue(_ weight: NSFont.Weight) -> Int {
        switch weight {
        case .ultraLight: return 1
        case .thin: return 2
        case .light: return 3
        case .regular: return 5
        case .medium: return 6
        case .semibold: return 7
        case .bold: return 8
        case .heavy: return 9
        case .black: return 10
        default: return 5
        }
    }
}

/// Renders parsed markdown blocks into an `NSAttributedString` using Kami warm paper styling.
public enum MarkdownRenderer {

    public struct Style {
        public var baseFontSize: CGFloat
        public var bodyFont: NSFont
        public var monoFont: NSFont
        public var textColor: NSColor
        public var secondaryColor: NSColor
        public var codeBackground: NSColor
        public var linkColor: NSColor
        public var brandColor: NSColor
        public var oliveColor: NSColor
        public var stoneColor: NSColor
        public var borderColor: NSColor
        public var bodyLineHeight: CGFloat
        public var headingLineHeight: CGFloat

        public init(baseFontSize: CGFloat = 14) {
            self.baseFontSize = baseFontSize
            self.bodyFont = Kami.serifFont(ofSize: baseFontSize, weight: .regular)
            self.monoFont = Kami.monoFont(ofSize: baseFontSize * 0.92)
            self.textColor = Kami.primaryText
            self.secondaryColor = Kami.secondaryText
            self.codeBackground = Kami.codeFill
            self.linkColor = Kami.accent
            self.brandColor = Kami.accent
            self.oliveColor = Kami.subtext
            self.stoneColor = Kami.tertiaryText
            self.borderColor = Kami.divider
            self.bodyLineHeight = 1.55
            self.headingLineHeight = 1.15
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
            let isLast = index == blocks.count - 1
            let piece = renderBlock(block, style: style, isLast: isLast)
            result.append(piece)
            if !isLast {
                result.append(NSAttributedString(string: "\n\n", attributes: baseAttrs(style)))
            }
        }
        return result
    }

    // MARK: - Blocks

    private static func renderBlock(_ block: BlockNode, style: Style, isLast: Bool = false) -> NSAttributedString {
        switch block {
        case .heading(let level, let text):
            return renderHeading(level: level, text: text, style: style, isLast: isLast)

        case .paragraph(let text):
            let result = NSMutableAttributedString(
                attributedString: renderInlines(text, font: style.bodyFont, color: style.textColor, style: style)
            )
            applyBodyParagraphStyle(to: result, style: style)
            return result

        case .blockquote(let children):
            let inner = NSMutableAttributedString()
            for (i, child) in children.enumerated() {
                inner.append(renderBlock(child, style: style, isLast: false))
                if i < children.count - 1 {
                    inner.append(NSAttributedString(string: "\n", attributes: baseAttrs(style)))
                }
            }
            let range = NSRange(location: 0, length: inner.length)
            // Olive body text + brand-colored left bar via leading "│ " marker
            if inner.length > 0 {
                inner.addAttribute(.foregroundColor, value: style.oliveColor, range: range)
            }
            // DEBUG: thicker left bar (~4pt visual weight) + brighter brand
            let barFont = NSFont.systemFont(ofSize: style.baseFontSize * 1.15, weight: .bold)
            let barAttrs: [NSAttributedString.Key: Any] = [
                .font: barFont,
                .foregroundColor: style.brandColor,
            ]
            let withBar = NSMutableAttributedString(string: "▌ ", attributes: barAttrs)
            withBar.append(inner)
            let fullRange = NSRange(location: 0, length: withBar.length)
            let para = NSMutableParagraphStyle()
            para.firstLineHeadIndent = 4
            para.headIndent = 20
            para.lineHeightMultiple = style.bodyLineHeight
            withBar.addAttribute(.paragraphStyle, value: para, range: fullRange)
            return withBar

        case .codeBlock(_, let code):
            let para = NSMutableParagraphStyle()
            para.lineHeightMultiple = 1.15
            para.paragraphSpacingBefore = 4
            para.paragraphSpacing = 4
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
            // DEBUG: larger bullet markers so list styling is obvious
            let markerFont = Kami.serifFont(ofSize: style.baseFontSize * 1.25, weight: .semibold)
            let markerAttrs: [NSAttributedString.Key: Any] = [
                .font: markerFont,
                .foregroundColor: style.brandColor,
            ]
            let bodyPara = bodyParagraphStyle(style)
            bodyPara.headIndent = 16
            bodyPara.firstLineHeadIndent = 0
            for (i, item) in items.enumerated() {
                let bullet = NSAttributedString(string: "● ", attributes: markerAttrs)
                result.append(bullet)
                let body = renderInlines(item, font: style.bodyFont, color: style.textColor, style: style)
                result.append(body)
                if i < items.count - 1 {
                    result.append(NSAttributedString(string: "\n", attributes: baseAttrs(style)))
                }
            }
            if result.length > 0 {
                result.addAttribute(
                    .paragraphStyle,
                    value: bodyPara,
                    range: NSRange(location: 0, length: result.length)
                )
            }
            return result

        case .orderedList(let items):
            let result = NSMutableAttributedString()
            let markerFont = Kami.serifFont(ofSize: style.baseFontSize * 1.1, weight: .semibold)
            let markerAttrs: [NSAttributedString.Key: Any] = [
                .font: markerFont,
                .foregroundColor: style.brandColor,
            ]
            let bodyPara = bodyParagraphStyle(style)
            bodyPara.headIndent = 20
            bodyPara.firstLineHeadIndent = 0
            for (i, item) in items.enumerated() {
                let prefix = NSAttributedString(string: "\(i + 1). ", attributes: markerAttrs)
                result.append(prefix)
                result.append(renderInlines(item, font: style.bodyFont, color: style.textColor, style: style))
                if i < items.count - 1 {
                    result.append(NSAttributedString(string: "\n", attributes: baseAttrs(style)))
                }
            }
            if result.length > 0 {
                result.addAttribute(
                    .paragraphStyle,
                    value: bodyPara,
                    range: NSRange(location: 0, length: result.length)
                )
            }
            return result

        case .thematicBreak:
            // Warm stone hairline — not cool secondaryLabel gray
            let breakColor = style.stoneColor.withAlphaComponent(0.35)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: Kami.serifFont(ofSize: style.baseFontSize * 0.8, weight: .regular),
                .foregroundColor: breakColor,
            ]
            return NSAttributedString(string: "────────────", attributes: attrs)

        case .table(let columns, let rows):
            return renderTable(columns: columns, rows: rows, style: style)
        }
    }

    // MARK: - Headings

    private static func renderHeading(
        level: Int,
        text: String,
        style: Style,
        isLast: Bool
    ) -> NSAttributedString {
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
        // Weight 500 (semibold) serif — Kami locks serif headings at 500, not bold 700
        let font = Kami.serifFont(ofSize: size, weight: .semibold)

        let spacingBefore: CGFloat
        let spacingAfter: CGFloat
        switch level {
        case 1:
            spacingBefore = 20
            spacingAfter = 6
        case 2:
            spacingBefore = 16
            spacingAfter = 5
        default:
            spacingBefore = 10
            spacingAfter = 3
        }

        // When a kick-line follows, leave clear gap so rule reads as separator (not underline)
        let wantsRule = (level == 1 || level == 2) && !isLast
        let headingAfter: CGFloat = wantsRule ? 8 : spacingAfter

        let headingPara = NSMutableParagraphStyle()
        headingPara.paragraphSpacingBefore = spacingBefore
        headingPara.paragraphSpacing = headingAfter
        headingPara.lineHeightMultiple = style.headingLineHeight

        let heading = NSMutableAttributedString(
            attributedString: renderInlines(text, font: font, color: style.textColor, style: style)
        )
        if heading.length > 0 {
            heading.addAttribute(
                .paragraphStyle,
                value: headingPara,
                range: NSRange(location: 0, length: heading.length)
            )
        }

        guard wantsRule else { return heading }

        let result = NSMutableAttributedString(attributedString: heading)
        result.append(NSAttributedString(string: "\n", attributes: [
            .font: font,
            .foregroundColor: style.textColor,
            .paragraphStyle: headingPara,
        ]))

        // Full text-container width (matches MarkdownTextView maxMeasure = 680)
        let ruleLength: CGFloat = 680
        let ruleHeight: CGFloat = 0.3
        // Subtle warm gray section separator (Kami border-adjacent)
        let ruleColor = NSColor(srgbRed: 0xD8 / 255, green: 0xD4 / 255, blue: 0xCC / 255, alpha: 1)

        let rule = hairlineRule(
            length: ruleLength,
            height: ruleHeight,
            color: ruleColor,
            paragraphSpacingAfter: spacingAfter,
            style: style
        )
        result.append(rule)
        return result
    }

    /// Drawn hairline rule as an `NSTextAttachment` (not text dashes).
    private static func hairlineRule(
        length: CGFloat,
        height: CGFloat,
        color: NSColor,
        paragraphSpacingAfter: CGFloat,
        style: Style
    ) -> NSAttributedString {
        let image = drawHairlineImage(length: length, height: height, color: color)
        let attachment = NSTextAttachment()
        attachment.image = image
        // Bounds: origin y slightly below baseline so the line sits under the heading
        attachment.bounds = CGRect(x: 0, y: 0, width: length, height: height)

        let rulePara = NSMutableParagraphStyle()
        rulePara.alignment = .left
        rulePara.paragraphSpacingBefore = 0
        rulePara.paragraphSpacing = paragraphSpacingAfter

        let result = NSMutableAttributedString(attachment: attachment)
        let attrs: [NSAttributedString.Key: Any] = [
            .paragraphStyle: rulePara,
            .font: style.bodyFont,
            .foregroundColor: color,
        ]
        result.addAttributes(attrs, range: NSRange(location: 0, length: result.length))
        result.append(NSAttributedString(string: "\n", attributes: attrs))
        return result
    }

    /// 矢量式 hairline：按目标 backing scale 自动栅格化，Retina 上 0.5pt = 1 物理像素。
    private static func drawHairlineImage(length: CGFloat, height: CGFloat, color: NSColor) -> NSImage {
        let size = NSSize(width: length, height: height)
        return NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.setFillColor(color.cgColor)
            ctx.fill(rect)
            return true
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
        table.setBorderColor(style.borderColor)
        table.layoutAlgorithm = .automaticLayoutAlgorithm

        let result = NSMutableAttributedString()
        // Weight 500 serif for headers (not synthetic bold 700)
        let headerFont = Kami.serifFont(ofSize: style.baseFontSize, weight: .semibold)

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
                font: headerFont,
                color: style.secondaryColor,
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
                    font: headerFont,
                    color: style.secondaryColor,
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
                    color: style.textColor,
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
        color: NSColor,
        style: Style
    ) {
        let block = NSTextTableBlock(table: table, startingRow: row, rowSpan: 1, startingColumn: column, columnSpan: 1)
        block.setBorderColor(style.borderColor)
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
        let cellContent = renderInlines(display, font: font, color: color, style: style)
        let mutable = NSMutableAttributedString(attributedString: cellContent)
        if mutable.length == 0 {
            mutable.append(NSAttributedString(string: "\u{00A0}", attributes: [
                .font: font,
                .foregroundColor: color,
            ]))
        }
        // Terminate cell paragraph with \n so NSTextView assembles contiguous table cells
        mutable.append(NSAttributedString(string: "\n", attributes: [
            .font: font,
            .foregroundColor: color,
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
            // Kami locks strong at weight 500 (not synthetic 700)
            let bold = Kami.serifFont(ofSize: font.pointSize, weight: .semibold)
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

    // MARK: - Paragraph helpers

    private static func bodyParagraphStyle(_ style: Style) -> NSMutableParagraphStyle {
        let para = NSMutableParagraphStyle()
        para.lineHeightMultiple = style.bodyLineHeight
        return para
    }

    private static func applyBodyParagraphStyle(to result: NSMutableAttributedString, style: Style) {
        guard result.length > 0 else { return }
        result.addAttribute(
            .paragraphStyle,
            value: bodyParagraphStyle(style),
            range: NSRange(location: 0, length: result.length)
        )
    }

    private static func baseAttrs(_ style: Style) -> [NSAttributedString.Key: Any] {
        [
            .font: style.bodyFont,
            .foregroundColor: style.textColor,
        ]
    }
}
