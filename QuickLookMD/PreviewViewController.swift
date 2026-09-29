import Cocoa
import QuickLookUI
import WebKit

@objc(PreviewViewController)
class PreviewViewController: NSViewController, QLPreviewingController, WKNavigationDelegate {
    private var webView: WKWebView!
    private var pendingCompletion: ((Error?) -> Void)?

    override func loadView() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.underPageBackgroundColor = .textBackgroundColor
        view = webView
    }

    func preparePreviewOfFile(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            // Quick Look vuelve a la vista previa de texto plano del sistema
            completionHandler(error)
            return
        }
        DispatchQueue.main.async { [self] in
            finish(nil)
            pendingCompletion = completionHandler
            let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let html = HTMLTemplate.build(body: MarkdownRenderer().render(text), isDark: isDark)
            // Resources del .appex: ahí están highlight.min.js y mermaid.min.js
            let base = Bundle(for: PreviewViewController.self).resourceURL
            webView.loadHTMLString(html, baseURL: base)
        }
    }

    // Avisar a Quick Look recién cuando el HTML terminó de cargar, así no muestra la vista vacía
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(CocoaError(.fileReadUnknown))
    }

    private func finish(_ error: Error?) {
        pendingCompletion?(error)
        pendingCompletion = nil
    }
}
