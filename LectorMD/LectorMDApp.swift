import SwiftUI
import AppKit

@main
struct LectorMDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("appearanceMode") private var appearanceMode: String = "system"

    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
                .onChange(of: appearanceMode) { newValue in
                    applyNSAppearance(newValue)
                }
        }
        .commands {
            ReloadCommands()
            PrintCommands()
            CommandGroup(after: .toolbar) {
                Divider()
                Picker("Apariencia", selection: $appearanceMode) {
                    Text("Sistema").tag("system")
                    Text("Claro").tag("light")
                    Text("Oscuro").tag("dark")
                }
                .pickerStyle(.inline)
            }
        }
    }
}

private func applyNSAppearance(_ mode: String) {
    switch mode {
    case "light": NSApp.appearance = NSAppearance(named: .aqua)
    case "dark":  NSApp.appearance = NSAppearance(named: .darkAqua)
    default:      NSApp.appearance = nil
    }
}

struct ReloadCommands: Commands {
    @FocusedValue(\.reloadAction) var reloadAction

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Recargar") { reloadAction?() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(reloadAction == nil)
        }
    }
}

struct PrintCommands: Commands {
    @FocusedValue(\.printAction) var printAction

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Imprimir…") { printAction?() }
                .keyboardShortcut("p", modifiers: .command)
                .disabled(printAction == nil)
        }
    }
}

// Cuando la app arranca sin archivo abre el panel de selección automáticamente
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let saved = UserDefaults.standard.string(forKey: "appearanceMode") ?? "system"
        applyNSAppearance(saved)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if NSDocumentController.shared.documents.isEmpty {
                NSApp.sendAction(#selector(NSDocumentController.openDocument(_:)), to: nil, from: nil)
            }
        }
    }

    // No crear documento en blanco al relanzar la app
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
}
