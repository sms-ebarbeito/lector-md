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
            guard message.name == "diagramClick", let svg = message.body as? String else { return }
            DispatchQueue.main.async { self.openDiagramViewer(svg: svg) }
        }

        private func openDiagramViewer(svg: String) {
            let html = """
            <!DOCTYPE html><html><head><meta charset="utf-8">
            <style>
            *{box-sizing:border-box;margin:0;padding:0}
            body{display:flex;align-items:center;justify-content:center;min-height:100vh;padding:32px;background:#ffffff}
            @media(prefers-color-scheme:dark){body{background:#0d1117}}
            svg{max-width:100%;height:auto}
            #lector-bar{display:none;position:fixed;top:12px;right:12px;z-index:9999;align-items:center;gap:6px;padding:8px 10px;border-radius:10px;background:rgba(255,255,255,0.88);backdrop-filter:blur(14px);-webkit-backdrop-filter:blur(14px);box-shadow:-2px 4px 14px rgba(0,0,0,0.22);font-family:-apple-system,sans-serif;font-size:14px}
            @media(prefers-color-scheme:dark){#lector-bar{background:rgba(28,28,28,0.90);color:#e0e0e0}}
            #lector-q{border:none;outline:none;background:transparent;font-size:14px;width:190px;color:inherit}
            #lector-q::placeholder{color:#999}
            .lector-btn{border:none;background:none;cursor:pointer;padding:0;font-size:16px;line-height:1;opacity:.65}
            .lector-btn:hover{opacity:1}
            #lector-info{font-size:11px;color:#999;min-width:16px;text-align:center}
            </style>
            </head><body>
            \(svg)
            <div id="lector-bar">
              <button class="lector-btn" onclick="lectorFind()" title="Buscar (Enter)">⌕</button>
              <input id="lector-q" type="text" placeholder="Buscar en el diagrama…"
                     onkeydown="if(event.key==='Enter')lectorFind()"
                     oninput="if(this.value.length>=3)lectorFind()">
              <span id="lector-info"></span>
              <button class="lector-btn" onclick="lectorClose()" title="Cerrar (Esc)">✕</button>
            </div>
            <script>
            document.addEventListener('keydown',function(e){
              if((e.metaKey||e.ctrlKey)&&e.key==='f'){e.preventDefault();lectorToggle();}
              if(e.key==='Escape'){lectorClose();}
            });
            function lectorToggle(){
              var bar=document.getElementById('lector-bar');
              var open=bar.style.display==='flex';
              bar.style.display=open?'none':'flex';
              if(!open){document.getElementById('lector-q').focus();}
              else{window.getSelection().removeAllRanges();}
            }
            function lectorFind(){
              var q=document.getElementById('lector-q').value;
              var info=document.getElementById('lector-info');
              if(!q){info.textContent='';return;}
              var found=window.find(q,false,false,true);
              info.textContent=found?'':'✕';
            }
            function lectorClose(){
              document.getElementById('lector-bar').style.display='none';
              document.getElementById('lector-info').textContent='';
              window.getSelection().removeAllRanges();
            }
            </script>
            </body></html>
            """
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
        let html = HTMLTemplate.build(body: MarkdownRenderer().render(markdownText), isDark: isDark)
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
