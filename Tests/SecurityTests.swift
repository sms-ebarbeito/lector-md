import AppKit
import Network
import WebKit

// Tests de seguridad del #5. Se corren con `bash test.sh`.
// 1. Escape: salidas exactas del renderer, esquemas de URL y el validador del puente.
// 2. WebKit de verdad: el .md de ataque con la CSP de la app no ejecuta nada (un servidor
//    propio en 127.0.0.1 anota cada pedido y no tiene que recibir ningún /xss-…), un
//    documento normal anda igual (Mermaid, resaltado, búsqueda, anclas, imágenes remotas,
//    clic en el diagrama) y la ventana del diagrama tampoco ejecuta nada. Cada prueba de
//    CSP tiene su control: el mismo HTML sin CSP sí dispara los pedidos.

var passed = 0
var failed = 0

func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
    if ok {
        passed += 1
        print("  ✓ \(name)")
    } else {
        failed += 1
        print("  ✗ \(name)")
        let d = detail()
        if !d.isEmpty { print("      \(d)") }
    }
}

@main
struct LectorMDTests {
    static func main() {
        let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)

        escapeTests()
        urlTests()
        rendererTests()
        diagramSVGTests()
        webKitTests(root: root)

        print(failed == 0 ? "\n✓ \(passed) pruebas OK" : "\n✗ \(failed) de \(passed + failed) pruebas fallaron")
        exit(failed == 0 ? 0 : 1)
    }
}

// MARK: - Escape

func escapeTests() {
    print("Escape")
    check(HTMLSafety.escapeText(#"a & b < c > d "e" 'f'"#) == #"a &amp; b &lt; c &gt; d "e" 'f'"#,
          "texto: & < >; las comillas quedan")
    check(HTMLSafety.escapeAttribute(#"& < > " '"#) == "&amp; &lt; &gt; &quot; &#39;",
          "atributo: & < > \" '")
    check(HTMLSafety.escapeAttribute("x\"\u{301} y") == "x&quot;\u{301} y",
          "atributo: comilla seguida de un acento combinante")
}

// MARK: - URLs

func urlTests() {
    print("URLs")
    for url in ["https://example.com/a?b=1&c=2", "http://x", "mailto:a@b.c", "#fin", "docs/a.md",
                "../otro archivo.md", "file:///tmp/x.png", "obsidian://open?vault=x"] {
        check(HTMLSafety.isSafeURL(url), "link permitido: \(url)")
    }
    for url in ["javascript:alert(1)", "JaVaScRiPt:alert(1)", " javascript:alert(1)", "\u{1}javascript:x",
                "java\tscript:x", "java\nscript:x", "vbscript:msgbox", "data:text/html,<script>x</script>",
                "data:image/png;base64,iVBO"] {
        check(!HTMLSafety.isSafeURL(url), "link rechazado: \(url.debugDescription)")
    }
    // El navegador toma "java script:" como relativa; acá se rechaza igual (más estricto, nunca menos)
    check(!HTMLSafety.isSafeURL("java script:x"), "link rechazado: \"java script:x\" (más estricto que el navegador)")
    check(HTMLSafety.isSafeURL("data:image/png;base64,iVBO", allowDataImage: true), "imagen permitida: data:image/png")
    check(HTMLSafety.isSafeURL("DATA:IMAGE/SVG+XML,<svg/>", allowDataImage: true), "imagen permitida: DATA:IMAGE/SVG+XML")
    for url in ["data:text/html,x", "javascript:x", "vbscript:x"] {
        check(!HTMLSafety.isSafeURL(url, allowDataImage: true), "imagen rechazada: \(url)")
    }
}

// MARK: - Renderer

func rendererTests() {
    print("Renderer")
    let r = MarkdownRenderer()
    func expect(_ md: String, _ html: String, _ name: String) {
        let out = r.render(md)
        check(out == html, name, "salió: \(out.debugDescription)")
    }
    func expectContains(_ md: String, _ fragment: String, _ name: String) {
        let out = r.render(md)
        check(out.contains(fragment), name, "salió: \(out.debugDescription)")
    }

    expect(#"![x" onerror="alert(1)](a.png)"#,
           "<p><img src=\"a.png\" alt=\"x&quot; onerror=&quot;alert(1)\"></p>\n",
           "alt con comillas dobles (onerror)")
    expect("![it's <b> & c](a.png)", "<p><img src=\"a.png\" alt=\"it&#39;s &lt;b&gt; &amp; c\"></p>\n",
           "alt con comilla simple, < y &")
    expect("![x\"\u{301} onerror=\"y](a.png)", "<p><img src=\"a.png\" alt=\"x&quot;\u{301} onerror=&quot;y\"></p>\n",
           "alt con comilla y acento combinante")
    expect("![a](b.png 'x\" onerror=\"y')", "<p><img src=\"b.png\" alt=\"a\" title=\"x&quot; onerror=&quot;y\"></p>\n",
           "title de imagen")
    expect("![a](javascript:alert(1))", "<p>![a](javascript:alert(1))</p>\n", "javascript: en src queda como texto")
    expect("![a](data:text/html,x)", "<p>![a](data:text/html,x)</p>\n", "data:text/html en src queda como texto")
    expect("![a](data:image/png;base64,iVBO)", "<p><img src=\"data:image/png;base64,iVBO\" alt=\"a\"></p>\n",
           "data:image en src se ve")

    expect(#"[a](https://x.com "t'q")"#, "<p><a href=\"https://x.com\" title=\"t&#39;q\">a</a></p>\n",
           "title de link entre comillas dobles")
    expect(#"[a](https://x.com 'x" onmouseover="y')"#,
           "<p><a href=\"https://x.com\" title=\"x&quot; onmouseover=&quot;y\">a</a></p>\n",
           "title de link entre comillas simples, con comillas dobles adentro")
    expect(#"[a](https://x.com "x" onmouseover="y")"#,
           "<p>[a](https://x.com \"x\" onmouseover=\"y\")</p>\n",
           "atributos después del title: no es un link, queda como texto")
    expect("[a](javascript:alert(1))", "<p>[a](javascript:alert(1))</p>\n", "javascript: en href queda como texto")
    expect("[a]( JaVaScRiPt:x)", "<p>[a]( JaVaScRiPt:x)</p>\n", "JaVaScRiPt: con espacio adelante")
    expect("[a](java\tscript:x)", "<p>[a](java\tscript:x)</p>\n", "javascript: con un tab en el medio")
    expect("[a](vbscript:x)", "<p>[a](vbscript:x)</p>\n", "vbscript:")
    expect("[a](data:text/html,x)", "<p>[a](data:text/html,x)</p>\n", "data: en href")
    expect("[a](https://x.com/?a=1&b=2)", "<p><a href=\"https://x.com/?a=1&amp;b=2\">a</a></p>\n",
           "& en la URL se escapa una sola vez")
    expect("[a](https://x.com/a_b_c)", "<p><a href=\"https://x.com/a_b_c\">a</a></p>\n",
           "_ en la URL no se vuelve <em>")
    expect("[a](https://x.com/it's)", "<p><a href=\"https://x.com/it&#39;s\">a</a></p>\n", "comilla simple en href")
    expect("[**a**](#fin)", "<p><a href=\"#fin\"><strong>a</strong></a></p>\n", "énfasis en el texto de un link")
    expect("[![CI](https://b.svg)](https://ci)", "<p><a href=\"https://ci\"><img src=\"https://b.svg\" alt=\"CI\"></a></p>\n",
           "imagen dentro de un link (badge)")
    expect("[<img src=x onerror=y>](https://x.com)",
           "<p><a href=\"https://x.com\">&lt;img src=x onerror=y&gt;</a></p>\n", "HTML en el texto de un link")
    expect("![`x\"y`](a.png)", "<p><img src=\"a.png\" alt=\"x&quot;y\"></p>\n", "código inline en el alt")

    let sentinel = r.render("`\"` ![\u{E000}0\u{E001}](c.png) [\u{E000}0\u{E001}](d)")
    check(!sentinel.contains("\u{E000}") && sentinel.contains("alt=\"\u{FFFD}0\u{FFFD}\""),
          "los sentinels del .md no restauran fragmentos", "salió: \(sentinel.debugDescription)")

    expect("```js\" onmouseover=\"x\ncode\n```", "<pre><code class=\"language-js&quot;\">code</code></pre>\n",
           "lenguaje del bloque con comillas dobles")
    expect("```js' x='y\ncode\n```", "<pre><code class=\"language-js&#39;\">code</code></pre>\n",
           "lenguaje del bloque con comillas simples")
    expect("```swift title=\"a\"\nlet a = \"<b>\"\n```",
           "<pre><code class=\"language-swift\">let a = \"&lt;b&gt;\"</code></pre>\n",
           "lenguaje: la primera palabra")
    expect("```mermaid\nA-->B<script>\n```", "<div class=\"mermaid\">A--&gt;B&lt;script&gt;</div>\n", "Mermaid: texto escapado")

    expect("<img src=x onerror=alert(1)>", "<p>&lt;img src=x onerror=alert(1)&gt;</p>\n", "HTML crudo: <img>")
    expect("<script>alert(1)</script>", "<p>&lt;script&gt;alert(1)&lt;/script&gt;</p>\n", "HTML crudo: <script>")
    expect("> <svg onload=x>", "<blockquote>\n<p>&lt;svg onload=x&gt;</p>\n</blockquote>\n", "HTML crudo en una cita")
    expect("- <iframe src=x>", "<ul>\n<li>&lt;iframe src=x&gt;</li>\n</ul>\n", "HTML crudo en una lista")
    expect(#"# Título" onmouseover="x"#, "<h1 id=\"título-onmouseoverx\">Título\" onmouseover=\"x</h1>\n",
           "título: id sin comillas, texto escapado")
    expectContains("| a |\n|---|\n| ![x\" onerror=\"y](z.png) |", "<td><img src=\"z.png\" alt=\"x&quot; onerror=&quot;y\"></td>",
                   "alt en una celda de tabla")
    expectContains("| a |\n|---|\n| <img src=x onerror=y> |", "<td>&lt;img src=x onerror=y&gt;</td>", "HTML crudo en una tabla")
}

// MARK: - Puente diagramClick

func diagramSVGTests() {
    print("SVG del puente diagramClick")
    let ok = [
        #"<svg xmlns="http://www.w3.org/2000/svg"><g><text>hola</text></g></svg>"#,
        #"<svg id="m"><style>#m .node&gt;rect{fill:red}</style><g><text>onclick=hola, onda = 3</text></g></svg>"#,
        #"<svg><a xlink:href="https://example.com/?a=1&amp;b=2"><text>x</text></a></svg>"#,
        #"<svg><foreignObject><div xmlns="http://www.w3.org/1999/xhtml"><span class="nodeLabel"><p>A<br>B</p></span></div></foreignObject></svg>"#,
        #"<svg><foreignObject><div><img src="https://example.com/a.png"></div></foreignObject></svg>"#,
    ]
    for svg in ok { check(HTMLSafety.isSafeDiagramSVG(svg), "acepta: \(svg.prefix(70))") }

    let bad = [
        #"<img src=x onerror="alert(1)">"#,
        #"<svgx></svgx>"#,
        #"<svg onload="alert(1)"></svg>"#,
        #"<svg/onload=alert(1)></svg>"#,
        #"<svg ONLOAD=alert(1)></svg>"#,
        #"<svg><g title="a>b" onclick="x"></g></svg>"#,
        #"<svg><script>alert(1)</script></svg>"#,
        #"<svg><SCRIPT>alert(1)</SCRIPT></svg>"#,
        #"<svg><a href="javascript:alert(1)"><text>x</text></a></svg>"#,
        #"<svg><a xlink:href=" JaVaScRiPt:alert(1)"><text>x</text></a></svg>"#,
        #"<svg><a href="&#106;avascript:alert(1)"><text>x</text></a></svg>"#,
        #"<svg><foreignObject><iframe src="https://x"></iframe></foreignObject></svg>"#,
        #"<svg><!-- x --></svg>"#,
        #"<svg></svg><meta http-equiv="refresh" content="0;url=https://x"><svg></svg>"#,
        #"<svg><set attributeName="href" to="javascript:alert(1)"/></svg>"#,
        #"<svg></ <x a="><img src=x onerror=alert(1)>"></svg>"#,
        #"<svg><foreignObject><style><x a="</style><img title=">" onerror=alert(1)>"></style></foreignObject></svg>"#,
        "<svg>" + String(repeating: "a", count: HTMLSafety.maxDiagramSVGBytes) + "</svg>",
    ]
    for svg in bad { check(!HTMLSafety.isSafeDiagramSVG(svg), "rechaza: \(svg.prefix(70))") }
}

// MARK: - WebKit

func webKitTests(root: URL) {
    print("WebKit")
    guard let server = try? ProbeServer(), spin(5, until: { server.port != 0 }) else {
        check(false, "servidor de prueba en 127.0.0.1")
        return
    }
    let port = server.port
    let resources = root.appendingPathComponent("LectorMD/Resources", isDirectory: true)
    func markdown(_ name: String) -> String {
        let text = (try? String(contentsOf: root.appendingPathComponent("Tests/\(name)"), encoding: .utf8)) ?? ""
        return text.replacingOccurrences(of: "127.0.0.1:8765", with: "127.0.0.1:\(port)")
    }
    // Igual que MarkdownWebView.updateNSView
    func appHTML(_ md: String) -> String {
        HTMLTemplate.build(body: MarkdownRenderer().render(md), isDark: false, head: HTMLTemplate.appHead(isDark: false))
    }
    func xss(since start: Int) -> [String] { server.paths.dropFirst(start).filter { $0.contains("/xss-") } }

    // CSP de la app
    let head = HTMLTemplate.appHead(isDark: false)
    check(head.contains("default-src 'none'") && head.contains("script-src file: 'sha256-")
          && head.contains("img-src https: http: data: file:") && head.contains("object-src 'none'")
          && head.contains("base-uri 'none'") && !head.contains("unsafe-eval")
          && !head.contains("script-src file: 'unsafe-inline'"),
          "CSP de la app: scripts por hash, imágenes remotas, object-src y base-uri 'none'", head)

    // Documento normal: todo anda con la CSP, y la CSP no bloquea nada
    var start = server.paths.count
    let normal = Page(html: appHTML(markdown("normal.md")), baseURL: resources, bridge: true)
    check(normal.waitFor("!!document.querySelector('.mermaid svg')"), "normal: Mermaid dibuja el diagrama")
    check(normal.evaluate("document.querySelectorAll('pre code.hljs .hljs-keyword').length") as? Int ?? 0 > 0,
          "normal: highlight.js resalta el código")
    check(normal.evaluate("lectorSearch('diagrama')") as? Int ?? 0 > 0, "normal: la búsqueda (Cmd+F) encuentra texto")
    check(normal.evaluate("document.querySelectorAll('table td').length") as? Int ?? 0 == 9, "normal: la tabla tiene sus celdas")
    _ = normal.evaluate("document.querySelector('a[href=\"#tabla\"]').click()")
    check(normal.waitFor("location.hash === '#tabla'"), "normal: el link interno #tabla navega")
    check(normal.evaluate("document.querySelector('a[title]').getAttribute('href')") as? String
          == "https://example.com/una_ruta_con_guiones_bajos", "normal: link con title y _ en la URL")
    spin(1)
    check(server.paths.dropFirst(start).contains("/legitima.png"), "normal: la imagen remota se pide (img-src http:)")
    _ = normal.evaluate("document.querySelector('.mermaid').click()")
    spin(2) { !normal.accepted.isEmpty }
    check(normal.accepted.count == 1 && normal.messages.count == 1,
          "normal: clic en el diagrama → el puente acepta el SVG de Mermaid",
          "mensajes: \(normal.messages.map { String($0.prefix(80)) })")
    check(normal.violations.isEmpty, "normal: ninguna violación de CSP", "\(normal.violations)")

    // Ventana del diagrama con ese SVG
    if let svg = normal.accepted.first {
        let diagram = Page(html: HTMLTemplate.diagramPage(svg: svg), baseURL: nil, bridge: false)
        check(diagram.evaluate("!!document.querySelector('body > svg')") as? Bool == true, "diagrama: el SVG se ve en su ventana")
        let found = diagram.evaluate("""
            document.getElementById('lector-q').value = 'Markdown';
            document.getElementById('lector-find').click();
            document.getElementById('lector-info').textContent
            """) as? String
        check(found == "", "diagrama: la búsqueda de la ventana anda con su CSP", "info: \(found ?? "nil")")
        check(diagram.violations.isEmpty, "diagrama: ninguna violación de CSP", "\(diagram.violations)")
    }

    // .md de ataque con la CSP de la app
    start = server.paths.count
    let attack = Page(html: appHTML(markdown("ataque.md")), baseURL: resources, bridge: true)
    check(attack.waitFor("!!document.querySelector('.mermaid svg')"), "ataque: Mermaid dibuja el diagrama")
    attack.provoke()
    spin(2)
    check(xss(since: start).isEmpty, "ataque: el servidor no recibe ningún /xss-…", "recibió: \(xss(since: start))")
    check(!attack.navigations.contains { $0.contains("xss") }, "ataque: ninguna navegación a /xss-…", "\(attack.navigations)")
    check(!attack.accepted.isEmpty && attack.accepted.count == attack.messages.count,
          "ataque: al puente solo llegan SVG de Mermaid, y los acepta (ningún click … call)",
          "mensajes: \(attack.messages.map { String($0.prefix(120)) })")
    check(server.paths.dropFirst(start).contains("/legitima.png"), "ataque: la imagen remota legítima se pide")

    // Control: HTML crudo metido en el body, salteando el renderer. Con la CSP no corre nada;
    // sin la CSP sí (así se ve que la prueba detecta la ejecución)
    let raw = """
        <img src="no-existe.png" onerror="i=new Image;i.src='http://127.0.0.1:\(port)/xss-csp-onerror'">
        <script>i=new Image;i.src='http://127.0.0.1:\(port)/xss-csp-script'</script>
        <svg onload="i=new Image;i.src='http://127.0.0.1:\(port)/xss-csp-svg'"></svg>
        <div onmouseover="i=new Image;i.src='http://127.0.0.1:\(port)/xss-csp-mouseover'">hover</div>
        <a href="javascript:i=new Image;i.src='http://127.0.0.1:\(port)/xss-csp-href';void 0">link</a>
        """
    start = server.paths.count
    let withCSP = Page(html: HTMLTemplate.build(body: raw, head: HTMLTemplate.appHead(isDark: false)), baseURL: resources, bridge: true)
    withCSP.provoke()
    spin(2)
    check(xss(since: start).isEmpty, "CSP de la app: el HTML inyectado no ejecuta nada", "recibió: \(xss(since: start))")
    start = server.paths.count
    let noCSP = Page(html: HTMLTemplate.build(body: raw), baseURL: resources, bridge: true)
    noCSP.provoke()
    spin(2)
    check(Set(xss(since: start)).count == 5, "control sin CSP: el mismo HTML sí ejecuta (5 pedidos)", "recibió: \(xss(since: start))")

    // Ventana del diagrama con un SVG malicioso (salteando la validación del puente)
    let evil = """
        <svg xmlns="http://www.w3.org/2000/svg" onload="i=new Image;i.src='http://127.0.0.1:\(port)/xss-diagram-onload'">\
        <foreignObject width="200" height="50"><img src="no-existe.png" onerror="i=new Image;i.src='http://127.0.0.1:\(port)/xss-diagram-onerror'">\
        <style><x a="</style><img src="no-existe.png" title=">" onerror="i=new Image;i.src='http://127.0.0.1:\(port)/xss-diagram-style'">"></style></foreignObject>\
        <script>i=new Image;i.src='http://127.0.0.1:\(port)/xss-diagram-script'</script></svg>
        """
    check(!HTMLSafety.isSafeDiagramSVG(evil), "diagrama: el puente rechaza el SVG malicioso")
    start = server.paths.count
    let evilPage = Page(html: HTMLTemplate.diagramPage(svg: evil), baseURL: nil, bridge: false)
    evilPage.provoke()
    spin(2)
    check(xss(since: start).isEmpty, "diagrama: aunque llegara, con su CSP no ejecuta nada", "recibió: \(xss(since: start))")
    start = server.paths.count
    let evilOld = Page(html: "<!DOCTYPE html><html><head><meta charset=\"utf-8\"></head><body>\(evil)</body></html>",
                       baseURL: nil, bridge: false)
    evilOld.provoke()
    spin(2)
    check(Set(xss(since: start)).count == 4, "control: en una página sin CSP (como antes) sí ejecuta", "recibió: \(xss(since: start))")
}

// MARK: - Helpers

@discardableResult
func spin(_ seconds: TimeInterval, until done: () -> Bool = { false }) -> Bool {
    let limit = Date().addingTimeInterval(seconds)
    while !done() && Date() < limit {
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
    return done()
}

// Un WKWebView fuera de pantalla que anota lo que manda la página al puente, las
// violaciones de CSP y las navegaciones que intenta
final class Page: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    let webView: WKWebView
    private(set) var loaded = false
    private(set) var messages: [String] = []
    private(set) var accepted: [String] = []   // lo que acepta Coordinator.diagramSVG(from:)
    private(set) var violations: [String] = []
    private(set) var navigations: [String] = []

    init(html: String, baseURL: URL?, bridge: Bool) {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 1400), configuration: config)
        super.init()
        let ucc = config.userContentController
        ucc.add(self, name: "violations")
        if bridge { ucc.add(self, name: "diagramClick") }
        // Los user scripts no pasan por la CSP de la página
        ucc.addUserScript(WKUserScript(source: """
            document.addEventListener('securitypolicyviolation', function (e) {
                window.webkit.messageHandlers.violations.postMessage(e.violatedDirective + ' ' + (e.blockedURI || ''));
            });
            """, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        webView.navigationDelegate = self
        if let baseURL, baseURL.isFileURL {
            // Un binario de línea de comandos no recibe permiso de lectura para el baseURL de
            // loadHTMLString (la app sí, para su bundle): se lo da una carga con loadFileURL
            webView.loadFileURL(baseURL.appendingPathComponent("highlight.min.js"), allowingReadAccessTo: baseURL)
            spin(10) { self.loaded }
            loaded = false
        }
        webView.loadHTMLString(html, baseURL: baseURL)
        spin(10) { self.loaded }
    }

    func evaluate(_ script: String) -> Any? {
        var result: Any?
        var finished = false
        webView.evaluateJavaScript(script) { value, _ in
            result = value
            finished = true
        }
        spin(10) { finished }
        return result
    }

    func waitFor(_ condition: String, seconds: TimeInterval = 8) -> Bool {
        spin(seconds) { self.evaluate(condition) as? Bool == true }
    }

    // Todo lo que un usuario podría hacer: pasar el mouse, hacer foco y clic en cada
    // elemento, y seguir cada link
    func provoke() {
        _ = evaluate("""
            (function () {
                var types = ['mouseover', 'mouseenter', 'mousemove', 'mousedown', 'mouseup', 'click',
                             'dblclick', 'focus', 'focusin', 'input', 'keydown', 'load', 'error'];
                var all = document.querySelectorAll('*');
                for (var i = 0; i < all.length; i++) {
                    for (var j = 0; j < types.length; j++) {
                        try { all[i].dispatchEvent(new MouseEvent(types[j], { bubbles: true, cancelable: true })); } catch (e) {}
                    }
                }
                document.querySelectorAll('a').forEach(function (a) { try { a.click(); } catch (e) {} });
                return all.length;
            })()
            """)
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "violations" {
            violations.append("\(message.body)")
            return
        }
        messages.append("\(message.body)")
        if let svg = MarkdownWebView.Coordinator.diagramSVG(from: message) { accepted.append(svg) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
    }

    // Como la app (que no tiene navigationDelegate): javascript: y los #anclas pasan, y
    // lo decide la CSP. Cualquier otra navegación se anota y se cancela, para no salir a internet.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard loaded, let url = action.request.url else { return decisionHandler(.allow) }
        var target = URLComponents(url: url, resolvingAgainstBaseURL: true)
        var current = webView.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: true) }
        target?.fragment = nil
        current?.fragment = nil
        if url.scheme == "javascript" || (url.fragment != nil && target == current) {
            return decisionHandler(.allow)
        }
        navigations.append(url.absoluteString)
        decisionHandler(.cancel)
    }
}

// Servidor HTTP mínimo en 127.0.0.1: anota la ruta de cada pedido y contesta 404
final class ProbeServer {
    private let listener: NWListener
    private(set) var paths: [String] = []
    var port: UInt16 { listener.port?.rawValue ?? 0 }

    init() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .main)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, _, _ in
                let line = data.flatMap { String(data: $0, encoding: .utf8) }?.components(separatedBy: "\r\n").first ?? ""
                let parts = line.split(separator: " ")
                if parts.count >= 2 { self?.paths.append(String(parts[1])) }
                let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: .main)
    }
}
