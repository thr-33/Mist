import Foundation

/// Column alignment for GFM pipe tables.
public enum TableAlignment: Equatable, Sendable {
    case left
    case center
    case right
}

/// One column in a GFM pipe table (header cell text + alignment).
public struct TableColumn: Equatable, Sendable {
    public let header: String
    public let alignment: TableAlignment

    public init(header: String, alignment: TableAlignment) {
        self.header = header
        self.alignment = alignment
    }
}

/// Block-level markdown nodes produced by the parser.
public enum BlockNode: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case blockquote([BlockNode])
    case codeBlock(language: String?, code: String)
    case unorderedList([String])
    case orderedList([String])
    case thematicBreak
    /// GFM pipe table: header columns (with alignment) + body rows of raw cell markdown.
    case table(columns: [TableColumn], rows: [[String]])
}

/// Inline markdown spans within a text run.
public enum InlineNode: Equatable, Sendable {
    case text(String)
    case bold(String)
    case italic(String)
    case code(String)
    case link(text: String, url: String)
    case strikethrough(String)
    case underline(String)
}
