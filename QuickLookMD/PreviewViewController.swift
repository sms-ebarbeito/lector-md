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
        // Force click en un link no abre la página en un popover
        webView.allowsLinkPreview = false
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
        let html = HTMLTemplate.build(body: MarkdownRenderer().render(text), isDark: isDark,
                                      head: Self.head(isDark: isDark))
        // Resources del .appex: ahí están highlight.min.js y mermaid.min.js
        let base = Bundle(for: PreviewViewController.self).resourceURL

        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "LectorMDQL.sinRed", encodedContentRuleList: Self.networkRules
        ) { [weak self] rules, error in
            guard let self else { return }
            if let rules {
                self.webView.configuration.userContentController.add(rules)
            } else {
                // Sigue valiendo la CSP del HTML, que también bloquea las cargas remotas
                NSLog("LectorMDQL: no se pudo compilar el bloqueo de red: %@", error.map { "\($0)" } ?? "?")
            }
            self.webView.loadHTMLString(html, baseURL: base)
        }

        // didFinish llega en unos 300 ms; esto es por si WebKit no avisa nunca (p. ej.
        // un script colgado sin que muera WebContent): no dejar a Quick Look con el spinner
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

    // MARK: - Sin red (#3)

    // La vista previa no pide nada a internet: con solo seleccionar un .md y apretar
    // espacio, cada imagen remota le diría a su servidor la IP, la hora y qué archivo
    // se miró. Dos capas:
    // 1. WKContentRuleList: WebKit bloquea toda carga http(s) y ws(s) de este WKWebView,
    //    de cualquier tipo (img, srcset, CSS, fuentes, fetch), venga del HTML o de lo
    //    que agregue Mermaid después. No depende del HTML.
    // 2. CSP en el HTML: default-src 'none' (imágenes y fuentes solo de file: y data:),
    //    y scripts inline solo por hash, sin 'unsafe-inline'. Vale aunque la lista no
    //    compile, y evita que un atributo que venga del .md ejecute JS: desde JS hay
    //    caminos de red que la lista no cubre.
    private static let networkRules = """
        [{"trigger": {"url-filter": "^https?:"}, "action": {"type": "block"}},
         {"trigger": {"url-filter": "^wss?:"}, "action": {"type": "block"}}]
        """

    // La misma CSP que la app (hashes del template con el body vacío, así nada del .md queda
    // permitido), pero con imágenes solo de file: y data:
    private static func head(isDark: Bool) -> String {
        HTMLTemplate.contentSecurityPolicy(isDark: isDark, imgSrc: "file: data:", extraHead: remoteImagesHead)
    }

    // El JS solo cambia cómo se ve: cada <img> remota (ya bloqueada) pasa a ser un
    // recuadro con su alt o su dominio, y arriba aparece un aviso. Escucha los errores
    // de carga desde el <head>, así también agarra las <img> que agrega Mermaid.
    private static let remoteImagesHead = #"""

        <style>
        .lector-aviso-remoto {
            font-size: 12px; color: var(--text-muted); background: var(--surface);
            border: 1px solid var(--border); border-radius: 6px;
            padding: 6px 10px; margin-bottom: 16px;
        }
        .lector-img-bloqueada {
            display: inline-block; max-width: 100%; box-sizing: border-box;
            padding: 6px 10px; margin: 0.5em 0; overflow-wrap: anywhere;
            font-size: 0.85em; color: var(--text-muted); background: var(--surface);
            border: 1px dashed var(--border); border-radius: 6px;
        }
        </style>
        <script>
        (function () {
            function bloquear(img) {
                var url = img.currentSrc || img.src;
                if (!/^https?:/i.test(url) || !img.parentNode) return;
                var host = '';
                try { host = new URL(url).hostname; } catch (e) {}
                var box = document.createElement('span');
                box.className = 'lector-img-bloqueada';
                box.textContent = img.alt || host || 'Imagen remota';
                box.title = url;
                img.replaceWith(box);

                var body = document.querySelector('.markdown-body');
                if (!body || body.querySelector('.lector-aviso-remoto')) return;
                var aviso = document.createElement('div');
                aviso.className = 'lector-aviso-remoto';
                aviso.textContent = 'Imágenes remotas bloqueadas · abrí el archivo en LectorMD para verlas';
                body.insertBefore(aviso, body.firstChild);
            }
            document.addEventListener('error', function (e) {
                if (e.target instanceof HTMLImageElement) bloquear(e.target);
            }, true);
            document.addEventListener('DOMContentLoaded', function () {
                document.querySelectorAll('img').forEach(bloquear);
            });
        })();
        </script>
        """#

    private func finish(_ error: Error?) {
        let completion = pendingCompletion
        pendingCompletion = nil
        completion?(error)
    }
}
