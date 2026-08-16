# MarkdownView

Ultra-lightweight native macOS markdown **editor** with live preview.

Built with **SwiftUI + AppKit**, zero third-party dependencies. A hand-rolled markdown parser renders to `NSAttributedString` in a split-pane layout: editable source on the left, live preview on the right.

## Features

- **Split-pane editor** — left: plain monospaced markdown source; right: live rendered preview
- **Live preview** updates as you type
- **Save** with Cmd+S (atomic write); **Save As…** via Cmd+Shift+S; dirty indicator (`•`) in the window title
- **Open** files via Cmd+O, drag & drop, or CLI path argument
- **Live reload** when the file changes on disk (does not clobber unsaved edits)
- **Font size** increase/decrease (Cmd+ / Cmd-) applies to both panes
- **Print** (Cmd+P) and **manual reload** (Cmd+R)
- **Selection format toolbar** — popover above the source selection with bold, italic, underline (`<u>`), strikethrough, inline code, link, heading, quote, bullet list, and code block (toggles unwrap when already wrapped; dismisses on scroll / empty selection)
- Text selection, copy, and Cmd+F find (native NSTextView)
- Dark mode via semantic system colors

### Markdown support

| Blocks | Inlines |
|--------|---------|
| ATX headings `#` … `######` | `**bold**` |
| Blockquotes `>` | `*italic*` |
| Fenced code ` ``` ` | `` `inline code` `` |
| Unordered lists `-` / `*` | `[link](url)` |
| Ordered lists `1.` | `~~strikethrough~~` |
| Thematic breaks `---` | `<u>underline</u>` |
| Paragraphs | |

## Requirements

- macOS 14.0+
- Swift 6.0+ (Xcode 16+)

## Build

```bash
./scripts/build-app.sh
```

This runs `swift build -c release`, assembles `dist/MarkdownView.app`, ad-hoc codesigns it, and prints the bundle size (target ≤ 20 MB).

Or build the binary only:

```bash
swift build -c release
```

## Run

```bash
# App bundle
open dist/MarkdownView.app

# Binary with a file
.build/release/MarkdownView path/to/file.md

# Or the bundled binary
dist/MarkdownView.app/Contents/MacOS/MarkdownView path/to/file.md
```

## Test

```bash
swift test
```

## Size

The release `.app` bundle is intentionally tiny — a single native executable plus `Info.plist`, typically well under 5 MB and always **≤ 20 MB**.

## License

MIT
