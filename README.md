# Mist

> A tiny, native Markdown viewer and editor for macOS.

[![Tests](https://github.com/thr-33/Mist/actions/workflows/test.yml/badge.svg)](https://github.com/thr-33/Mist/actions/workflows/test.yml)
[![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-111827)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Mist is an intentionally small Markdown app for macOS. It opens quickly, keeps editing close to the source, and renders a calm, readable preview without a web view or third-party dependency.

**中文简介：** Mist 是一个使用 SwiftUI + AppKit 编写的轻量级 macOS Markdown 查看器和编辑器。它支持实时预览、双栏编辑、文件监听和原生打印，适合作为日常阅读 Markdown 以及学习 macOS 原生开发的开源项目。

## Why Mist?

Most Markdown tools try to become full writing suites. Mist takes the opposite approach: one focused window, a fast native renderer, and the controls needed to read or make a small edit. The default experience is a distraction-free preview; press **⌘⇧E** whenever you need the source.

## Features

- **Preview-first window** with a remembered single-pane or split-pane layout
- **Live editing** with the Markdown source on the left and rendered preview on the right
- **Native file workflows**: open, drag and drop, command-line paths, Save, Save As, and atomic writes
- **Live reload** when the current file changes on disk, without clobbering unsaved edits
- **Selection formatting toolbar** for bold, italic, underline, strikethrough, inline code, links, headings, quotes, lists, and fenced code
- **GFM-style tables** with left, center, and right alignment rendered as native `NSTextTable`
- **Native macOS behavior**: system dark mode, Cmd+F, copy/paste, printing, font-size controls, and Finder file associations
- **Zero third-party dependencies**: built with SwiftUI, AppKit, and Foundation

## Supported Markdown

Mist uses a small hand-rolled parser focused on everyday Markdown:

| Block syntax | Inline syntax |
| --- | --- |
| ATX headings `#` through `######` | **Bold** `**text**` |
| Paragraphs | *Italic* `*text*` |
| Blockquotes `>` | `Inline code` `` `code` `` |
| Fenced code blocks ```` ``` ```` | [Links](https://example.com) `[text](url)` |
| Unordered lists `-` / `*` | ~~Strikethrough~~ `~~text~~` |
| Ordered lists `1.` | <u>Underline</u> `<u>text</u>` |
| Thematic breaks `---` | GFM tables with alignment |

Mist is not intended to be a complete CommonMark implementation. If a document depends on advanced Markdown extensions, check the rendered result before sharing it.

## Requirements

- macOS 14.0 or later
- Swift 6.0 or Xcode 16 or later
- A Mac with Apple Silicon or Intel support for the installed Swift toolchain

## Build and run

Clone the repository, then build the app bundle:

```bash
git clone https://github.com/thr-33/Mist.git
cd Mist
./scripts/build-app.sh
open dist/Mist.app
```

The build script runs a release build, assembles `dist/Mist.app`, embeds the icon, and applies an ad-hoc signature for local use. The generated `dist/` directory is intentionally ignored by Git.

To build only the executable:

```bash
swift build -c release
.build/release/Mist path/to/document.md
```

To open a document with the app bundle:

```bash
dist/Mist.app/Contents/MacOS/Mist path/to/document.md
```

> Mist currently has no signed/notarized binary release. Building from source is the supported installation path for now.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘O` | Open a Markdown file |
| `⌘S` | Save |
| `⌘⇧S` | Save As… |
| `⌘⇧E` | Toggle preview / split editor |
| `⌘R` | Reload from disk |
| `⌘P` | Print |
| `⌘+` / `⌘-` | Increase / decrease font size |
| `⌘F` | Find in the source editor |

## Development

Run the test suite before opening a pull request:

```bash
swift test
```

Generate the icon assets when needed:

```bash
swift scripts/generate-icon.swift
```

The repository is intentionally a plain Swift Package so it can be opened in Xcode or built from the command line. The main pieces are:

```text
Sources/Mist/
├── MistApp.swift           # App lifecycle, commands, and file opening
├── ContentView.swift       # Main window and view-mode presentation
├── SourceEditorView.swift  # Editable NSTextView bridge
├── MarkdownParser.swift    # Markdown -> AST parsing
├── MarkdownAST.swift       # Block and inline model
├── MarkdownRenderer.swift  # AST -> NSAttributedString rendering
└── FileMonitor.swift       # On-disk change monitoring
Tests/MistTests/             # Parser, renderer, and view-mode tests
scripts/                    # App bundle and icon generation scripts
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow.

## Roadmap

Ideas for future versions include richer Markdown compatibility, syntax highlighting, and a signed release download. Contributions and thoughtful issue reports are welcome; the project will remain focused rather than trying to become a full IDE.

## License

Mist is available under the [MIT License](LICENSE).
