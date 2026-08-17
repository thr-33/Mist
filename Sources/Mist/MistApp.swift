import AppKit
import SwiftUI

@main
struct MistApp: App {
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
        WindowGroup {
            ContentView(model: model)
        }
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
