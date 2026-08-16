import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var model: DocumentModel

    var body: some View {
        HSplitView {
            SourceEditorView(
                text: Binding(
                    get: { model.rawMarkdown },
                    set: { model.updateMarkdown($0) }
                ),
                fontSize: model.fontSize,
                onTextChange: { model.updateMarkdown($0) }
            )
            .frame(minWidth: 200)
            .layoutPriority(0.4)

            MarkdownTextView(
                attributedText: model.attributedText,
                onOpenFile: { url in
                    model.open(url: url)
                }
            )
            .frame(minWidth: 240)
            .layoutPriority(0.6)
        }
        .frame(minWidth: 640, minHeight: 360)
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
    @Published private(set) var isDirty: Bool = false
    @Published private(set) var rawMarkdown: String = ""
    @Published var fontSize: CGFloat = 14
    @Published private(set) var statusMessage: String?

    private let monitor = FileMonitor()
    private var didLoadInitial = false
    private var initialPath: String?
    private var previewTask: Task<Void, Never>?

    var windowTitle: String {
        let name: String
        if let fileURL {
            name = fileURL.lastPathComponent
        } else {
            name = "Untitled"
        }
        if isDirty {
            return "• \(name)"
        }
        return name
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

    func updateMarkdown(_ text: String) {
        guard text != rawMarkdown else { return }
        rawMarkdown = text
        isDirty = true
        statusMessage = nil
        schedulePreviewUpdate()
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
            isDirty = false
            statusMessage = nil
            recompute()
            monitor.watch(url: url)
        } catch {
            rawMarkdown = "Failed to open file:\n\n\(error.localizedDescription)"
            fileURL = url
            isDirty = false
            statusMessage = error.localizedDescription
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
        // Explicit reload always reloads from disk (user intent).
        forceReloadFromDisk()
    }

    func save() {
        if let url = fileURL {
            writeAtomically(to: url)
        } else {
            saveAs()
        }
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText,
            .plainText,
        ]
        panel.nameFieldStringValue = fileURL?.lastPathComponent ?? "Untitled.md"
        if let fileURL {
            panel.directoryURL = fileURL.deletingLastPathComponent()
        }
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                self?.writeAtomically(to: url, updateFileURL: true)
            }
        }
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

    /// External change handler: skip when dirty so user edits are not clobbered.
    private func reloadFromDisk() {
        guard !isDirty else { return }
        forceReloadFromDisk()
    }

    private func forceReloadFromDisk() {
        guard let url = fileURL else { return }
        do {
            let data = try String(contentsOf: url, encoding: .utf8)
            if data != rawMarkdown {
                rawMarkdown = data
                isDirty = false
                statusMessage = nil
                recompute()
            } else {
                isDirty = false
            }
        } catch {
            statusMessage = "Reload failed: \(error.localizedDescription)"
            presentAlert(title: "Reload Failed", message: error.localizedDescription)
        }
    }

    private func writeAtomically(to url: URL, updateFileURL: Bool = false) {
        let directory = url.deletingLastPathComponent()
        let tempName = ".\(url.lastPathComponent).\(UUID().uuidString).tmp"
        let tempURL = directory.appendingPathComponent(tempName)
        do {
            try rawMarkdown.write(to: tempURL, atomically: true, encoding: .utf8)
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: url)
            }
            // Clean up temp if replace left it behind
            try? FileManager.default.removeItem(at: tempURL)

            if updateFileURL || fileURL == nil {
                fileURL = url
                monitor.watch(url: url)
            }
            isDirty = false
            statusMessage = nil
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            statusMessage = "Save failed: \(error.localizedDescription)"
            presentAlert(title: "Save Failed", message: error.localizedDescription)
        }
    }

    private func presentAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        // Non-blocking relative to the main run loop for the sheet-less case:
        // run as a regular alert window; do not crash.
        alert.runModal()
    }

    private func schedulePreviewUpdate() {
        previewTask?.cancel()
        previewTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 120_000_000) // ~120 ms debounce
            guard !Task.isCancelled else { return }
            recompute()
        }
    }

    private func recompute() {
        let style = MarkdownRenderer.Style(baseFontSize: fontSize)
        attributedText = MarkdownRenderer.render(rawMarkdown, style: style)
    }

    private func renderPlaceholder() {
        let welcome = """
        # MarkdownView

        Ultra-lightweight markdown editor for macOS.

        **Open a file** with `Cmd+O`, drag & drop onto the window, or pass a path on the command line.

        Edit on the left — live preview updates on the right. Save with `Cmd+S`.

        ## Features

        - Split-pane source + live preview
        - Headings, blockquotes, lists, code fences
        - *Italic*, **bold**, `code`, ~~strikethrough~~, [links](https://example.com)
        - Live reload when the file changes (skips while dirty)
        - Font size (`Cmd+` / `Cmd-`), print (`Cmd+P`), reload (`Cmd+R`)
        """
        rawMarkdown = welcome
        isDirty = false
        recompute()
    }
}
