import SwiftUI
import AppKit

@main
struct LectorMDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { file in
            ContentView(document: file.document)
        }
    }
}

// Cuando la app arranca sin archivo abre el panel de selección automáticamente
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if NSDocumentController.shared.documents.isEmpty {
                NSApp.sendAction(#selector(NSDocumentController.openDocument(_:)), to: nil, from: nil)
            }
        }
    }

    // No crear documento en blanco al relanzar la app
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
}
