import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: DocumentModel

    var body: some View {
        MarkdownTextView(
            attributedText: model.attributedText,
            onOpenFile: { url in
                model.open(url: url)
            }
        )
        .frame(minWidth: 480, minHeight: 320)
        .background(Color(nsColor: .textBackgroundColor))
        .navigationTitle(model.windowTitle)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .onAppear {
            model.loadInitialIfNeeded()
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let u = item as? URL {
                url = u
            } else if let s = item as? String {
                url = URL(fileURLWithPath: s)
            } else {
                url = nil
            }
            if let url {
                DispatchQueue.main.async {
                    model.open(url: url)
                }
            }
        }
        return true
    }
}

@MainActor
final class DocumentModel: ObservableObject {
    @Published private(set) var attributedText: NSAttributedString = NSAttributedString(string: "")
    @Published private(set) var fileURL: URL?
    @Published var fontSize: CGFloat = 14

    private let monitor = FileMonitor()
    private var rawMarkdown: String = ""
    private var didLoadInitial = false
    private var initialPath: String?

    var windowTitle: String {
        if let fileURL {
            return fileURL.lastPathComponent
        }
        return "MarkdownView"
    }

    init(initialPath: String? = nil) {
        self.initialPath = initialPath
        renderPlaceholder()
        monitor.onChange = { [weak self] in
            Task { @MainActor in
                self?.reloadFromDisk()
            }
        }
    }

    func loadInitialIfNeeded() {
        guard !didLoadInitial else { return }
        didLoadInitial = true
        if let path = initialPath, !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            open(url: url)
        }
    }

    func open(url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try String(contentsOf: url, encoding: .utf8)
            fileURL = url
            rawMarkdown = data
            recompute()
            monitor.watch(url: url)
        } catch {
            rawMarkdown = "Failed to open file:\n\n\(error.localizedDescription)"
            fileURL = url
            recompute()
        }
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText,
            .plainText,
        ]
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.open(url: url)
            }
        }
    }

    func reload() {
        reloadFromDisk()
    }

    func increaseFontSize() {
        fontSize = min(fontSize + 1, 48)
        recompute()
    }

    func decreaseFontSize() {
        fontSize = max(fontSize - 1, 8)
        recompute()
    }

    func printDocument() {
        let printInfo = NSPrintInfo.shared
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: printInfo.paperSize.width - 72, height: 10))
        textView.isEditable = false
        textView.textStorage?.setAttributedString(attributedText)
        textView.frame.size.height = textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 500

        let op = NSPrintOperation(view: textView, printInfo: printInfo)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        op.run()
    }

    private func reloadFromDisk() {
        guard let url = fileURL else { return }
        do {
            let data = try String(contentsOf: url, encoding: .utf8)
            if data != rawMarkdown {
                rawMarkdown = data
                recompute()
            }
        } catch {
            // Keep existing content if transient read failure (atomic save mid-write)
        }
    }

    private func recompute() {
        let style = MarkdownRenderer.Style(baseFontSize: fontSize)
        attributedText = MarkdownRenderer.render(rawMarkdown, style: style)
    }

    private func renderPlaceholder() {
        let welcome = """
        # MarkdownView

        Ultra-lightweight markdown reader for macOS.

        **Open a file** with `Cmd+O`, drag & drop onto the window, or pass a path on the command line.

        ## Features

        - Headings, blockquotes, lists, code fences
        - *Italic*, **bold**, `code`, ~~strikethrough~~, [links](https://example.com)
        - Live reload when the file changes
        - Font size (`Cmd+` / `Cmd-`), print (`Cmd+P`), reload (`Cmd+R`)
        """
        rawMarkdown = welcome
        recompute()
    }
}
