import AppKit
import XCTest
@testable import MarkdownView

final class MarkdownParserTests: XCTestCase {

    // MARK: - Block: Headings

    func testATXHeadings() {
        let md = """
        # H1
        ## H2
        ### H3
        #### H4
        ##### H5
        ###### H6
        """
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks.count, 6)
        XCTAssertEqual(blocks[0], .heading(level: 1, text: "H1"))
        XCTAssertEqual(blocks[1], .heading(level: 2, text: "H2"))
        XCTAssertEqual(blocks[2], .heading(level: 3, text: "H3"))
        XCTAssertEqual(blocks[3], .heading(level: 4, text: "H4"))
        XCTAssertEqual(blocks[4], .heading(level: 5, text: "H5"))
        XCTAssertEqual(blocks[5], .heading(level: 6, text: "H6"))
    }

    func testHeadingRequiresSpace() {
        let blocks = MarkdownParser.parse("#NoSpace")
        // Not a heading — treated as paragraph
        guard case .paragraph(let t) = blocks[0] else {
            return XCTFail("expected paragraph")
        }
        XCTAssertTrue(t.contains("#NoSpace"))
    }

    // MARK: - Block: Code fence

    func testFencedCodeBlock() {
        let md = """
        ```swift
        let x = 1
        print(x)
        ```
        """
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks.count, 1)
        guard case .codeBlock(let lang, let code) = blocks[0] else {
            return XCTFail("expected codeBlock, got \(blocks[0])")
        }
        XCTAssertEqual(lang, "swift")
        XCTAssertTrue(code.contains("let x = 1"))
        XCTAssertTrue(code.contains("print(x)"))
    }

    func testFencedCodeBlockNoLanguage() {
        let md = """
        ```
        plain
        ```
        """
        let blocks = MarkdownParser.parse(md)
        guard case .codeBlock(let lang, let code) = blocks[0] else {
            return XCTFail("expected codeBlock")
        }
        XCTAssertNil(lang)
        XCTAssertEqual(code, "plain")
    }

    // MARK: - Block: Lists

    func testUnorderedList() {
        let md = """
        - alpha
        - beta
        * gamma
        """
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks.count, 1)
        guard case .unorderedList(let items) = blocks[0] else {
            return XCTFail("expected unorderedList, got \(blocks[0])")
        }
        XCTAssertEqual(items, ["alpha", "beta", "gamma"])
    }

    func testOrderedList() {
        let md = """
        1. first
        2. second
        3. third
        """
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks.count, 1)
        guard case .orderedList(let items) = blocks[0] else {
            return XCTFail("expected orderedList, got \(blocks[0])")
        }
        XCTAssertEqual(items, ["first", "second", "third"])
    }

    // MARK: - Block: Blockquote, HR, Paragraph

    func testBlockquote() {
        let md = "> quoted line"
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks.count, 1)
        guard case .blockquote(let inner) = blocks[0] else {
            return XCTFail("expected blockquote")
        }
        XCTAssertFalse(inner.isEmpty)
    }

    func testThematicBreak() {
        let md = """
        before

        ---

        after
        """
        let blocks = MarkdownParser.parse(md)
        XCTAssertTrue(blocks.contains(.thematicBreak))
        XCTAssertEqual(blocks.count, 3)
    }

    func testParagraph() {
        let md = "Hello world.\nStill same paragraph."
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks.count, 1)
        guard case .paragraph(let t) = blocks[0] else {
            return XCTFail("expected paragraph")
        }
        XCTAssertTrue(t.contains("Hello world."))
        XCTAssertTrue(t.contains("Still same paragraph."))
    }

    // MARK: - Inline

    func testBold() {
        let nodes = MarkdownParser.parseInlines("a **bold** b")
        XCTAssertEqual(nodes, [.text("a "), .bold("bold"), .text(" b")])
    }

    func testItalic() {
        let nodes = MarkdownParser.parseInlines("a *italic* b")
        XCTAssertEqual(nodes, [.text("a "), .italic("italic"), .text(" b")])
    }

    func testInlineCode() {
        let nodes = MarkdownParser.parseInlines("use `code` here")
        XCTAssertEqual(nodes, [.text("use "), .code("code"), .text(" here")])
    }

    func testLink() {
        let nodes = MarkdownParser.parseInlines("see [docs](https://example.com) now")
        XCTAssertEqual(nodes, [
            .text("see "),
            .link(text: "docs", url: "https://example.com"),
            .text(" now"),
        ])
    }

    func testStrikethrough() {
        let nodes = MarkdownParser.parseInlines("~~gone~~")
        XCTAssertEqual(nodes, [.strikethrough("gone")])
    }

    func testUnderline() {
        let nodes = MarkdownParser.parseInlines("<u>hi</u>")
        XCTAssertEqual(nodes, [.underline("hi")])
    }

    func testUnderlineRenderAppliesUnderlineStyle() {
        let attr = MarkdownRenderer.render("<u>hi</u>")
        XCTAssertGreaterThan(attr.length, 0)
        let plain = attr.string as NSString
        let range = plain.range(of: "hi")
        XCTAssertNotEqual(range.location, NSNotFound)
        var effective = NSRange()
        let value = attr.attribute(.underlineStyle, at: range.location, effectiveRange: &effective)
        XCTAssertEqual(value as? Int, NSUnderlineStyle.single.rawValue)
    }

    func testMixedInlines() {
        let nodes = MarkdownParser.parseInlines("**bold** and *em* and `c`")
        XCTAssertEqual(nodes, [
            .bold("bold"),
            .text(" and "),
            .italic("em"),
            .text(" and "),
            .code("c"),
        ])
    }

    // MARK: - Renderer smoke

    func testRendererProducesNonEmptyString() {
        let md = """
        # Title

        A **bold** paragraph with `code` and [link](https://x.test).

        - item

        ```
        code
        ```

        ---

        ~~strike~~
        """
        let attr = MarkdownRenderer.render(md)
        XCTAssertGreaterThan(attr.length, 0)
        let plain = attr.string
        XCTAssertTrue(plain.contains("Title"))
        XCTAssertTrue(plain.contains("bold"))
        XCTAssertTrue(plain.contains("code"))
        XCTAssertTrue(plain.contains("link"))
        XCTAssertTrue(plain.contains("item"))
        XCTAssertTrue(plain.contains("strike"))
    }

    // MARK: - GFM tables

    func testTableParseStructureAndAlignment() {
        let md = """
        | Left | Center | Right |
        | :--- | :---: | ---: |
        | a | b | c |
        | d | e | f |
        """
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks.count, 1)
        guard case .table(let columns, let rows) = blocks[0] else {
            return XCTFail("expected table, got \(blocks[0])")
        }
        XCTAssertEqual(columns.count, 3)
        XCTAssertEqual(columns[0].header, "Left")
        XCTAssertEqual(columns[0].alignment, .left)
        XCTAssertEqual(columns[1].header, "Center")
        XCTAssertEqual(columns[1].alignment, .center)
        XCTAssertEqual(columns[2].header, "Right")
        XCTAssertEqual(columns[2].alignment, .right)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0], ["a", "b", "c"])
        XCTAssertEqual(rows[1], ["d", "e", "f"])
    }

    func testTableRowPaddingTruncationAndEscapes() {
        // Build with explicit newlines so \| is a real backslash-pipe in source
        let md = [
            "| A | B | C |",
            "| --- | --- | --- |",
            "| only |",
            "| 1 | 2 | 3 | 4 | extra |",
            "| pipe " + "\\" + "| here | `a|b` | end |",
        ].joined(separator: "\n")
        let blocks = MarkdownParser.parse(md)
        guard case .table(let columns, let rows) = blocks[0] else {
            return XCTFail("expected table, got \(blocks)")
        }
        XCTAssertEqual(columns.count, 3)
        XCTAssertEqual(rows.count, 3)
        // short row padded
        XCTAssertEqual(rows[0], ["only", "", ""])
        // long row truncated
        XCTAssertEqual(rows[1], ["1", "2", "3"])
        // escaped pipe + pipe inside code span
        XCTAssertEqual(rows[2][0], "pipe | here")
        XCTAssertEqual(rows[2][1], "`a|b`")
        XCTAssertEqual(rows[2][2], "end")
    }

    func testNonTablePipeLineStaysParagraph() {
        let md = "a | b"
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks.count, 1)
        guard case .paragraph(let t) = blocks[0] else {
            return XCTFail("expected paragraph, got \(blocks[0])")
        }
        XCTAssertEqual(t, "a | b")
    }

    @MainActor
    func testTableRenderLayoutSmoke() {
        let md = """
        | Name | Align |
        | --- | :---: |
        | **bold** | center |
        | `code` | x |
        """
        let attr = MarkdownRenderer.render(md)
        XCTAssertGreaterThan(attr.length, 0)
        let plain = attr.string
        XCTAssertTrue(plain.contains("Name"))
        XCTAssertTrue(plain.contains("Align"))
        XCTAssertTrue(plain.contains("bold"))
        XCTAssertTrue(plain.contains("center"))
        XCTAssertTrue(plain.contains("code"))

        // Offscreen NSTextView layout — must not crash
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        tv.textStorage?.setAttributedString(attr)
        if let lm = tv.layoutManager, let container = tv.textContainer {
            lm.ensureLayout(for: container)
            let glyphRange = lm.glyphRange(for: container)
            XCTAssertGreaterThanOrEqual(glyphRange.length, 0)
        }

        // Header cell "Name" should be bold
        let ns = plain as NSString
        let nameRange = ns.range(of: "Name")
        XCTAssertNotEqual(nameRange.location, NSNotFound)
        var effective = NSRange()
        if let font = attr.attribute(.font, at: nameRange.location, effectiveRange: &effective) as? NSFont {
            let traits = NSFontManager.shared.traits(of: font)
            XCTAssertTrue(traits.contains(.boldFontMask), "header font should be bold")
        } else {
            XCTFail("expected font on header cell")
        }

        // Center column alignment on header "Align"
        let alignRange = ns.range(of: "Align")
        XCTAssertNotEqual(alignRange.location, NSNotFound)
        if let para = attr.attribute(.paragraphStyle, at: alignRange.location, effectiveRange: &effective) as? NSParagraphStyle {
            XCTAssertEqual(para.alignment, .center)
            XCTAssertFalse(para.textBlocks.isEmpty, "table cell should have textBlocks")
        } else {
            XCTFail("expected paragraphStyle on center header")
        }
    }

    @MainActor
    func testReadmeSupportTableRenders() {
        // Exact structure from README "### Markdown support" table
        let md = """
        | Blocks | Inlines |
        |--------|---------|
        | ATX headings `#` … `######` | `**bold**` |
        | Blockquotes `>` | `*italic*` |
        | Fenced code | `` `inline code` `` |
        | Unordered lists `-` / `*` | `[link](url)` |
        | Ordered lists `1.` | `~~strikethrough~~` |
        | Thematic breaks `---` | `<u>underline</u>` |
        | Paragraphs | |
        | GFM tables | |
        """
        let blocks = MarkdownParser.parse(md)
        XCTAssertEqual(blocks.count, 1)
        guard case .table(let columns, let rows) = blocks[0] else {
            return XCTFail("README support table must parse as table, got \(blocks)")
        }
        XCTAssertEqual(columns.count, 2)
        XCTAssertEqual(columns[0].header, "Blocks")
        XCTAssertEqual(columns[1].header, "Inlines")
        XCTAssertGreaterThanOrEqual(rows.count, 7)

        let attr = MarkdownRenderer.render(md)
        let plain = attr.string
        XCTAssertTrue(plain.contains("Blocks"))
        XCTAssertTrue(plain.contains("Inlines"))
        XCTAssertTrue(plain.contains("ATX headings"))
        XCTAssertTrue(plain.contains("GFM tables"))

        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        tv.textStorage?.setAttributedString(attr)
        tv.layoutManager?.ensureLayout(for: tv.textContainer!)
    }
}
