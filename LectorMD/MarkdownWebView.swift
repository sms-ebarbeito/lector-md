import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let markdownText: String
    let searchModel: SearchModel
    let appearanceMode: String

    final class Coordinator: NSObject, WKScriptMessageHandler {
        var renderedText: String = ""
        var lastAppearanceMode: String = ""
        private var diagramWindows: [NSWindow] = []

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let svg = Self.diagramSVG(from: message) else {
                NSLog("LectorMD: diagramClick rechazado")
                return
            }
            DispatchQueue.main.async { self.openDiagramViewer(svg: svg) }
        }

        // El puente solo acepta mensajes de nuestro documento (el marco principal, cargado
        // con un baseURL file:) y solo un <svg> razonable (#5). Si el WKWebView navega a otra
        // página (p. ej. un link del .md), esa página también ve window.webkit.messageHandlers.
        static func diagramSVG(from message: WKScriptMessage) -> String? {
            guard message.name == "diagramClick",
                  message.frameInfo.isMainFrame,
                  message.frameInfo.securityOrigin.protocol == "file",
                  let svg = message.body as? String,
                  HTMLSafety.isSafeDiagramSVG(svg)
            else { return nil }
            return svg
        }

        private func openDiagramViewer(svg: String) {
            let html = HTMLTemplate.diagramPage(svg: svg)
            let webView = WKWebView()
            webView.allowsMagnification = true
            webView.underPageBackgroundColor = .textBackgroundColor
            webView.loadHTMLString(html, baseURL: nil)

            let frame = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
            let window = NSWindow(
                contentRect: frame,
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.contentView = webView
            window.title = "Diagrama"
            // Evita que NSWindow libere la memoria al cerrarse mientras WKWebView
            // aún tiene operaciones async pendientes (causa crash + cierre del documento)
            window.isReleasedWhenClosed = false
            window.makeKeyAndOrderFront(nil)

            diagramWindows.append(window)
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] note in
                guard let w = note.object as? NSWindow else { return }
                self?.diagramWindows.removeAll { $0 === w }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(
            WeakScriptHandler(context.coordinator),
            name: "diagramClick"
        )
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsMagnification = true
        webView.underPageBackgroundColor = NSColor.textBackgroundColor
        searchModel.webView = webView
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let modeChanged = appearanceMode != context.coordinator.lastAppearanceMode
        guard markdownText != context.coordinator.renderedText || modeChanged else { return }
        context.coordinator.renderedText = markdownText
        context.coordinator.lastAppearanceMode = appearanceMode
        let isDark: Bool
        switch appearanceMode {
        case "dark":  isDark = true
        case "light": isDark = false
        default:      isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
        // Sync bounce-scroll background with the HTML --bg variable
        webView.underPageBackgroundColor = isDark
            ? NSColor(red: 0.051, green: 0.067, blue: 0.090, alpha: 1)  // #0d1117
            : .white
        let html = HTMLTemplate.build(body: MarkdownRenderer().render(markdownText), isDark: isDark,
                                      head: HTMLTemplate.appHead(isDark: isDark))
        webView.loadHTMLString(html, baseURL: Bundle.main.resourceURL)
    }
}

// Wrapper para evitar el ciclo de retención fuerte que introduce WKUserContentController
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: MarkdownWebView.Coordinator?
    init(_ target: MarkdownWebView.Coordinator) { self.target = target }
    func userContentController(_ ucc: WKUserContentController, didReceive msg: WKScriptMessage) {
        target?.userContentController(ucc, didReceive: msg)
    }
}
