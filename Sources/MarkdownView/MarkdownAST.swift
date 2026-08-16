import Foundation

/// Block-level markdown nodes produced by the parser.
public enum BlockNode: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case blockquote([BlockNode])
    case codeBlock(language: String?, code: String)
    case unorderedList([String])
    case orderedList([String])
    case thematicBreak
}

/// Inline markdown spans within a text run.
public enum InlineNode: Equatable, Sendable {
    case text(String)
    case bold(String)
    case italic(String)
    case code(String)
    case link(text: String, url: String)
    case strikethrough(String)
}
