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

    // Quick Look lo llama una sola vez, en el main thread
    func preparePreviewOfFile(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            // Quick Look vuelve a la vista previa de texto plano del sistema
            completionHandler(error)
            return
        }
        pendingCompletion = completionHandler
        let isDark = view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let html = HTMLTemplate.build(body: MarkdownRenderer().render(text), isDark: isDark)
        // Resources del .appex: ahí están highlight.min.js y mermaid.min.js
        let base = Bundle(for: PreviewViewController.self).resourceURL
        webView.loadHTMLString(html, baseURL: base)

        // didFinish espera todas las imágenes (también las remotas): no dejar a
        // Quick Look con el spinner si alguna tarda; el contenido sigue cargando
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.finish(nil)
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

    // Links: solo anclas dentro del documento (#titulo). Cualquier otro link
    // reemplazaría la vista previa por otra página, sin forma de volver.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.navigationType == .linkActivated else {
            decisionHandler(.allow)
            return
        }
        let target = navigationAction.request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: true) }
        let current = webView.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: true) }
        var targetDoc = target, currentDoc = current
        targetDoc?.fragment = nil
        currentDoc?.fragment = nil
        let sameDocument = target?.fragment != nil && targetDoc != nil && targetDoc == currentDoc
        decisionHandler(sameDocument ? .allow : .cancel)
    }

    private func finish(_ error: Error?) {
        let completion = pendingCompletion
        pendingCompletion = nil
        completion?(error)
    }
}
