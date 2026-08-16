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
}
