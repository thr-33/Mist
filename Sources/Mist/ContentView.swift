import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Observes `NSApp.effectiveAppearance` and invokes `onChange` when light/dark flips.
private struct AppearanceObserver: NSViewRepresentable {
    var onChange: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = AppearanceView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? AppearanceView)?.onChange = onChange
    }

    private final class AppearanceView: NSView {
        var onChange: (() -> Void)?
        private var lastDark: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            checkAppearance()
        }

        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            checkAppearance()
        }

        private func checkAppearance() {
            let dark = Kami.isDark
            if lastDark != dark {
                lastDark = dark
                // Defer so we never publish @Published changes during a view update.
                let callback = onChange
                DispatchQueue.main.async {
                    callback?()
                }
            }
        }
    }
}

enum ViewMode: String, Equatable, Sendable {
    case preview
    case split

    static let defaultsKey = "viewMode"

    /// Resolve stored preference; missing or invalid → `.preview`.
    static func resolved(storedRaw: String?) -> ViewMode {
        guard let storedRaw, let mode = ViewMode(rawValue: storedRaw) else {
            return .preview
        }
        return mode
    }
}

struct ContentView: View {
    @ObservedObject var model: DocumentModel
    @AppStorage("splitFraction") private var splitFraction: Double = 0.5
    @State private var dragStartFraction: Double?

    private let dividerWidth: CGFloat = 6
    private let leftMinWidth: CGFloat = 340
    private let rightMinWidth: CGFloat = 310
    private let fractionMin: Double = 0.30
    private let fractionMax: Double = 0.70

    var body: some View {
        Group {
            switch model.viewMode {
            case .preview:
                MarkdownTextView(
                    attributedText: model.attributedText,
                    onOpenFile: { url in
                        model.open(url: url)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .split:
                splitPaneLayout
            }
        }
        .frame(minWidth: model.viewMode == .split ? 700 : 640, minHeight: 400)
        .background(Color(nsColor: Kami.pageBackground))
        .navigationTitle(model.windowTitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.toggleViewMode()
                } label: {
                    Image(systemName: model.viewMode == .preview ? "square.and.pencil" : "eye")
                }
                .help(model.viewMode == .preview ? "Edit" : "Preview")
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers)
        }
        .onAppear {
            model.loadInitialIfNeeded()
        }
        .background(AppearanceObserver { model.refreshStyleForAppearance() })
    }

    private var splitPaneLayout: some View {
        GeometryReader { geo in
            let totalWidth = max(geo.size.width, leftMinWidth + rightMinWidth + dividerWidth)
            let clamped = clampedFraction(for: totalWidth)
            let leftWidth = leftPaneWidth(totalWidth: totalWidth, fraction: clamped)

            HStack(spacing: 0) {
                SourceEditorView(
                    text: Binding(
                        get: { model.rawMarkdown },
                        set: { model.updateMarkdown($0) }
                    ),
                    fontSize: model.fontSize,
                    onTextChange: { model.updateMarkdown($0) }
                )
                .frame(width: leftWidth)
                .frame(maxHeight: .infinity)

                splitDivider(totalWidth: totalWidth)

                MarkdownTextView(
                    attributedText: model.attributedText,
                    onOpenFile: { url in
                        model.open(url: url)
                    }
                )
                .frame(minWidth: rightMinWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            .onAppear {
                // Normalize any out-of-range stored value once geometry is known.
                let normalized = clampedFraction(for: totalWidth)
                if abs(normalized - splitFraction) > 0.0001 {
                    splitFraction = normalized
                }
            }
        }
    }

    private func splitDivider(totalWidth: CGFloat) -> some View {
        ZStack {
            Rectangle()
                .fill(Color(nsColor: Kami.divider))
                .frame(width: 1)
            Color.clear
                .frame(width: dividerWidth)
                .contentShape(Rectangle())
        }
        .frame(width: dividerWidth)
        .frame(maxHeight: .infinity)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if dragStartFraction == nil {
                        dragStartFraction = splitFraction
                    }
                    let start = dragStartFraction ?? splitFraction
                    let startLeft = leftPaneWidth(totalWidth: totalWidth, fraction: start)
                    let proposedLeft = startLeft + value.translation.width
                    let usable = totalWidth - dividerWidth
                    guard usable > 0 else { return }
                    let raw = Double(proposedLeft / usable)
                    splitFraction = clampedFraction(for: totalWidth, proposed: raw)
                }
                .onEnded { _ in
                    dragStartFraction = nil
                }
        )
        .onHover { hovering in
            if hovering {
                NSCursor.resizeLeftRight.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    private func leftPaneWidth(totalWidth: CGFloat, fraction: Double) -> CGFloat {
        let usable = totalWidth - dividerWidth
        let ideal = CGFloat(fraction) * usable
        let maxLeft = usable - rightMinWidth
        return min(max(ideal, leftMinWidth), max(maxLeft, leftMinWidth))
    }

    private func clampedFraction(for totalWidth: CGFloat, proposed: Double? = nil) -> Double {
        let usable = totalWidth - dividerWidth
        guard usable > 0 else {
            return min(max(proposed ?? splitFraction, fractionMin), fractionMax)
        }
        let minF = max(fractionMin, Double(leftMinWidth / usable))
        let maxF = min(fractionMax, Double((usable - rightMinWidth) / usable))
        let lower = min(minF, maxF)
        let upper = max(minF, maxF)
        let value = proposed ?? splitFraction
        return min(max(value, lower), upper)
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
    @Published private(set) var viewMode: ViewMode

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
        // Load persisted mode before any @Published mutation observers attach.
        let stored = UserDefaults.standard.string(forKey: ViewMode.defaultsKey)
        self.viewMode = ViewMode.resolved(storedRaw: stored)
        self.initialPath = initialPath
        renderPlaceholder()
        monitor.onChange = { [weak self] in
            Task { @MainActor in
                self?.reloadFromDisk()
            }
        }
    }

    func setViewMode(_ mode: ViewMode) {
        guard mode != viewMode else { return }
        viewMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: ViewMode.defaultsKey)
    }

    func toggleViewMode() {
        setViewMode(viewMode == .preview ? .split : .preview)
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

    /// Re-render when light/dark appearance flips so Kami palette tokens refresh.
    func refreshStyleForAppearance() {
        recompute()
    }

    private func recompute() {
        let style = MarkdownRenderer.Style(baseFontSize: fontSize)
        attributedText = MarkdownRenderer.render(rawMarkdown, style: style)
    }

    private func renderPlaceholder() {
        let welcome = """
        # Mist

        Ultra-lightweight markdown viewer and editor for macOS.

        **Open a file** with `Cmd+O`, drag & drop onto the window, or pass a path on the command line.

        Starts in full-window preview. Press the toolbar button or `Cmd+Shift+E` to toggle split-pane edit + live preview. Save with `Cmd+S`.

        ## Features

        - Default single-pane preview; toggle split-pane source + live preview
        - Headings, blockquotes, lists, code fences
        - *Italic*, **bold**, `code`, ~~strikethrough~~, [links](https://example.com)
        - Live reload when the file changes (skips while dirty)
        - Font size (`Cmd+` / `Cmd-`), print (`Cmd+P`), reload (`Cmd+R`)

        > Tip: Drop a `.md` file onto the dock icon to open it instantly.

        ```
        mist README.md
        ```
        """
        rawMarkdown = welcome
        isDirty = false
        recompute()
    }
}
