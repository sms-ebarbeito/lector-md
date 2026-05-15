import Cocoa
import QuickLookUI
import WebKit

@objc(PreviewViewController)
class PreviewViewController: NSViewController, QLPreviewingController {
    private var webView: WKWebView!

    override func loadView() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        webView.underPageBackgroundColor = .textBackgroundColor
        view = webView
    }

    func preparePreviewOfFile(at url: URL, completionHandler: @escaping (Error?) -> Void) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            completionHandler(nil)
            return
        }
        let html = HTMLTemplate.build(body: MarkdownRenderer().render(text))
        let base = Bundle(for: PreviewViewController.self).resourceURL
        webView.loadHTMLString(html, baseURL: base)
        completionHandler(nil)
    }
}
