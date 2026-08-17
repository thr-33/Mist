# Mist

Ultra-lightweight native macOS markdown **viewer and editor** with live preview.

Built with **SwiftUI + AppKit**, zero third-party dependencies. A hand-rolled markdown parser renders to `NSAttributedString`. Default layout is a single-pane full-window preview; toggle to a split-pane layout with editable source on the left and live preview on the right.

## Features

- **Default single-pane preview**; toolbar button or **Cmd+Shift+E** toggles split-pane edit + live preview (mode remembered)
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
- **GFM tables** (pipe tables with alignment) render as native `NSTextTable` in the preview
- **Elegant section separation** — hairline kick-lines under H1/H2, breathing heading spacing, and light thematic dividers

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
| GFM tables (pipe tables with alignment) | |

## Requirements

- macOS 14.0+
- Swift 6.0+ (Xcode 16+)

## Build

```bash
./scripts/build-app.sh
```

This runs `swift build -c release`, assembles `dist/Mist.app`, ad-hoc codesigns it, and prints the bundle size (target ≤ 20 MB).

Or build the binary only:

```bash
swift build -c release
```

## Run

```bash
# App bundle
open dist/Mist.app

# Binary with a file
.build/release/Mist path/to/file.md

# Or the bundled binary
dist/Mist.app/Contents/MacOS/Mist path/to/file.md
```

## Test

```bash
swift test
```

## Icon

The app icon is generated with a zero-dependency AppKit script:

```bash
swift scripts/generate-icon.swift
```

This draws a Big Sur–style squircle (indigo→blue gradient + white **M↓** markdown mark), writes the full `.iconset`, builds `scripts/AppIcon.icns` via `iconutil`, and saves `icon-preview.png` at the project root for a quick look without building. `./scripts/build-app.sh` embeds the icns into the bundle automatically.

## Size

The release `.app` bundle is intentionally tiny — a single native executable plus `Info.plist` and app icon, typically well under 5 MB and always **≤ 20 MB**.

## License

MIT
