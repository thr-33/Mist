import AppKit
import SwiftUI

/// Handles Finder double-click / "Open With" via Apple Event `kAEOpenDocuments`.
/// Uses a static pending queue so cold-launch openFiles (before DocumentModel exists)
/// never drops the target URL.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let pendingOpen = DispatchQueue(label: "mist.pendingOpen")
    /// Protected by `pendingOpen`; marked unsafe for Swift 6 static mutable state checks.
    nonisolated(unsafe) static var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure any late-created windows beyond the first are closed (single-window policy).
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                Self.enforceSingleWindow()
            }
        }

        // Drain anything that arrived before the model / first view appeared.
        DispatchQueue.main.async {
            DocumentModel.current?.flushPendingOpen()
            Self.enforceSingleWindow()
        }
    }

    /// Modern AppKit entry (preferred when implemented).
    func application(_ application: NSApplication, open urls: [URL]) {
        Self.enqueueOpenURLs(urls)
    }

    /// Legacy path-string entry (still used by Launch Services on many macOS versions).
    func application(_ application: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.compactMap { s -> URL? in
            guard !s.hasPrefix("-") else { return nil }
            return URL(fileURLWithPath: s)
        }
        guard !urls.isEmpty else {
            application.reply(toOpenOrPrint: .failure)
            return
        }
        Self.enqueueOpenURLs(urls)
        application.reply(toOpenOrPrint: .success)
    }

    /// Shared enqueue used by openFiles / open urls.
    static func enqueueOpenURLs(_ urls: [URL]) {
        let fileURLs = urls.filter { $0.isFileURL || $0.path.hasPrefix("/") }
            .map { $0.isFileURL ? $0 : URL(fileURLWithPath: $0.path) }
        guard !fileURLs.isEmpty else { return }
        pendingOpen.sync { pendingURLs.append(contentsOf: fileURLs) }
        Task { @MainActor in
            DocumentModel.current?.flushPendingOpen()
            Self.enforceSingleWindow()
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// Suppress automatic untitled-file creation; we own loading (pending queue + model).
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // If a window exists, just activate it; do not spawn another.
        if flag {
            Self.enforceSingleWindow()
            NSApp.activate(ignoringOtherApps: true)
            return false
        }
        return true
    }

    /// Keep only the first/main app window; close extras spawned by open events.
    @MainActor
    static func enforceSingleWindow() {
        let appWindows = NSApp.windows.filter { window in
            // Skip panels, sheets, status, and other non-document chrome.
            window.isVisible
                && window.canBecomeMain
                && !(window is NSPanel)
                && window.frame.width > 200
                && window.frame.height > 200
        }
        guard appWindows.count > 1 else { return }
        // Prefer the key/main window as survivor; else the oldest.
        let survivor = NSApp.mainWindow
            ?? NSApp.keyWindow
            ?? appWindows.first
        for window in appWindows where window !== survivor {
            window.close()
        }
        survivor?.makeKeyAndOrderFront(nil)
    }
}

@main
struct MistApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    /// Created once at App scope so every scene shares a single DocumentModel.
    @StateObject private var model: DocumentModel

    init() {
        let args = CommandLine.arguments
        var path: String?
        // First non-flag argument after executable is a file path
        if args.count > 1 {
            for arg in args.dropFirst() {
                if arg.hasPrefix("-") { continue }
                path = arg
                break
            }
        }
        _model = StateObject(wrappedValue: DocumentModel(initialPath: path))
    }

    var body: some Scene {
        // Single-window scene (not WindowGroup) so open-file never spawns a second window.
        Window("Mist", id: "main") {
            ContentView(model: model)
                .environmentObject(model)
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                .onOpenURL { url in
                    model.handleOpenURL(url)
                    Task { @MainActor in
                        AppDelegate.enforceSingleWindow()
                    }
                }
        }
        .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
        .defaultSize(width: 1140, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    model.openPanel()
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    model.save()
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save As…") {
                    model.saveAs()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }

            CommandGroup(after: .newItem) {
                Button("Reload") {
                    model.reload()
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            CommandGroup(after: .textEditing) {
                Button("Increase Font Size") {
                    model.increaseFontSize()
                }
                .keyboardShortcut("+", modifiers: .command)

                Button("Decrease Font Size") {
                    model.decreaseFontSize()
                }
                .keyboardShortcut("-", modifiers: .command)
            }

            CommandGroup(replacing: .printItem) {
                Button("Print…") {
                    model.printDocument()
                }
                .keyboardShortcut("p", modifiers: .command)
            }

            // Cmd+Shift+E (not Cmd+E — that is NSTextView "Use Selection for Find").
            CommandGroup(after: .sidebar) {
                Button(model.viewMode == .preview ? "Edit" : "Preview") {
                    model.toggleViewMode()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }
}
