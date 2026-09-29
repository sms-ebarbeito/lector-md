import Foundation

enum HTMLTemplate {

    // `head` va al principio del <head>, antes que cualquier contenido: ahí la
    // Vista Rápida pone su Content-Security-Policy. La app no lo usa.
    static func build(body: String, isDark: Bool = false, head: String = "") -> String {
        """
        <!DOCTYPE html>
        <html lang="es">
        <head>
        <meta charset="utf-8">\(head)
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        \(css)
        </style>
        </head>
        <body>
        <article class="markdown-body">
        \(body)
        </article>
        <script src="highlight.min.js"></script>
        <script>hljs.highlightAll();</script>
        <script src="mermaid.min.js"></script>
        <script>
        mermaid.initialize({
            startOnLoad: true,
            securityLevel: 'loose',
            theme: '\(isDark ? "dark" : "default")'
        });
        (function() {
            function attachClickHandler(container) {
                if (container.dataset.clickReady) return;
                container.dataset.clickReady = '1';
                container.addEventListener('click', function() {
                    var svg = container.querySelector('svg');
                    if (!svg) return;
                    window.webkit.messageHandlers.diagramClick.postMessage(svg.outerHTML);
                });
            }
            var obs = new MutationObserver(function(mutations) {
                for (var i = 0; i < mutations.length; i++) {
                    var added = mutations[i].addedNodes;
                    for (var j = 0; j < added.length; j++) {
                        var n = added[j];
                        if (n.nodeType !== 1) continue;
                        if (n.tagName === 'svg' && n.parentElement && n.parentElement.classList.contains('mermaid')) {
                            attachClickHandler(n.parentElement);
                        }
                    }
                }
            });
            obs.observe(document.documentElement, { childList: true, subtree: true });
        })();
        </script>
        <script>
        var lectorCurrentHit = 0;

        // Normaliza diacríticos carácter a carácter (NFD + quita combining marks).
        // Al procesar de a 1 char, el largo del resultado == largo del input,
        // entonces los índices en el string normalizado coinciden con el original.
        function lectorNorm(str) {
            var r = '';
            for (var i = 0; i < str.length; i++) {
                r += str[i].normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
            }
            return r;
        }

        function lectorSearch(q) {
            document.querySelectorAll('mark.lector-hit').forEach(function(m) {
                m.parentNode.replaceChild(document.createTextNode(m.textContent), m);
            });
            var body = document.querySelector('.markdown-body');
            if (body) body.normalize();
            if (!q) return 0;

            var nq = lectorNorm(q);
            var walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT, null);
            var nodes = [];
            var n;
            while ((n = walker.nextNode())) nodes.push(n);

            var count = 0;
            for (var i = 0; i < nodes.length; i++) {
                var node = nodes[i];
                var text = node.textContent;
                var nt = lectorNorm(text);
                var idx = nt.indexOf(nq);
                if (idx === -1) continue;
                var frag = document.createDocumentFragment();
                var last = 0;
                while (idx !== -1) {
                    if (idx > last) frag.appendChild(document.createTextNode(text.slice(last, idx)));
                    var mark = document.createElement('mark');
                    mark.className = 'lector-hit';
                    mark.textContent = text.slice(idx, idx + nq.length);
                    frag.appendChild(mark);
                    count++;
                    last = idx + nq.length;
                    idx = nt.indexOf(nq, last);
                }
                if (last < text.length) frag.appendChild(document.createTextNode(text.slice(last)));
                node.parentNode.replaceChild(frag, node);
            }
            lectorCurrentHit = 0;
            var hits = document.querySelectorAll('mark.lector-hit');
            if (hits.length > 0) {
                hits[0].classList.add('lector-hit-current');
                hits[0].scrollIntoView({ behavior: 'smooth', block: 'center' });
            }
            return count;
        }

        function lectorSearchNext() {
            var hits = document.querySelectorAll('mark.lector-hit');
            if (hits.length === 0) return [0, 0];
            hits[lectorCurrentHit].classList.remove('lector-hit-current');
            lectorCurrentHit = (lectorCurrentHit + 1) % hits.length;
            hits[lectorCurrentHit].classList.add('lector-hit-current');
            hits[lectorCurrentHit].scrollIntoView({ behavior: 'smooth', block: 'center' });
            return [lectorCurrentHit + 1, hits.length];
        }

        function lectorSearchPrev() {
            var hits = document.querySelectorAll('mark.lector-hit');
            if (hits.length === 0) return [0, 0];
            hits[lectorCurrentHit].classList.remove('lector-hit-current');
            lectorCurrentHit = (lectorCurrentHit - 1 + hits.length) % hits.length;
            hits[lectorCurrentHit].classList.add('lector-hit-current');
            hits[lectorCurrentHit].scrollIntoView({ behavior: 'smooth', block: 'center' });
            return [lectorCurrentHit + 1, hits.length];
        }
        </script>
        </body>
        </html>
        """
    }

    // Uses @media (prefers-color-scheme) so WKWebView adapts to system appearance automatically
    private static let css = """
    :root {
        --font-body: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif;
        --font-mono: "SFMono-Regular", "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;

        /* Light */
        --bg: #ffffff;
        --surface: #f6f8fa;
        --border: #d0d7de;
        --text: #1f2328;
        --text-muted: #656d76;
        --heading: #1f2328;
        --link: #0969da;
        --link-hover: #0550ae;
        --code-fg: #cf222e;
        --blockquote-border: #0969da;
        --blockquote-fg: #656d76;
        --hr: #d0d7de;
        --table-header-bg: #f6f8fa;
        --table-stripe: #f6f8fa;
    }

    @media (prefers-color-scheme: dark) {
        :root {
            --bg: #0d1117;
            --surface: #161b22;
            --border: #30363d;
            --text: #e6edf3;
            --text-muted: #7d8590;
            --heading: #e6edf3;
            --link: #58a6ff;
            --link-hover: #79c0ff;
            --code-fg: #ff7b72;
            --blockquote-border: #388bfd;
            --blockquote-fg: #7d8590;
            --hr: #30363d;
            --table-header-bg: #161b22;
            --table-stripe: #161b22;
        }
    }

    *, *::before, *::after { box-sizing: border-box; }

    html { font-size: 16px; }

    body {
        font-family: var(--font-body);
        line-height: 1.7;
        color: var(--text);
        background: var(--bg);
        margin: 0;
        padding: 0;
        -webkit-font-smoothing: antialiased;
    }

    .markdown-body {
        max-width: 800px;
        margin: 0 auto;
        padding: 40px 32px 96px;
    }

    /* Headings */
    h1, h2, h3, h4, h5, h6 {
        color: var(--heading);
        font-weight: 600;
        line-height: 1.3;
        margin: 1.5em 0 0.5em;
    }
    h1:first-child, h2:first-child { margin-top: 0; }
    h1 { font-size: 2em;    padding-bottom: 0.3em;  border-bottom: 1px solid var(--border); }
    h2 { font-size: 1.5em;  padding-bottom: 0.25em; border-bottom: 1px solid var(--border); }
    h3 { font-size: 1.25em; }
    h4 { font-size: 1em; }
    h5 { font-size: 0.875em; }
    h6 { font-size: 0.85em; color: var(--text-muted); }

    /* Prose */
    p { margin: 0 0 1em; }
    strong { font-weight: 600; }
    em { font-style: italic; }
    del { color: var(--text-muted); text-decoration: line-through; }

    /* Links */
    a { color: var(--link); text-decoration: none; }
    a:hover { color: var(--link-hover); text-decoration: underline; }

    /* Inline code */
    code {
        font-family: var(--font-mono);
        font-size: 0.875em;
        color: var(--code-fg);
        background: var(--surface);
        border: 1px solid var(--border);
        border-radius: 4px;
        padding: 0.15em 0.4em;
    }

    /* Code blocks */
    pre {
        background: var(--surface);
        border: 1px solid var(--border);
        border-radius: 8px;
        padding: 18px 20px;
        overflow-x: auto;
        margin: 0 0 1.2em;
        line-height: 1.55;
    }
    pre code {
        font-size: 0.875em;
        color: var(--text);
        background: none;
        border: none;
        padding: 0;
        border-radius: 0;
        white-space: pre;
    }

    /* Blockquote */
    blockquote {
        margin: 0 0 1.2em;
        padding: 6px 16px;
        border-left: 4px solid var(--blockquote-border);
        color: var(--blockquote-fg);
        background: var(--surface);
        border-radius: 0 6px 6px 0;
    }
    blockquote p { margin-bottom: 0.5em; }
    blockquote p:last-child { margin-bottom: 0; }

    /* Lists */
    ul, ol { padding-left: 1.8em; margin: 0 0 1.2em; }
    li { margin: 0.3em 0; }
    li > ul, li > ol { margin-top: 0.2em; margin-bottom: 0.2em; }

    /* Task list */
    li:has(> input[type="checkbox"]) { list-style: none; margin-left: -1.6em; }
    input[type="checkbox"] {
        margin-right: 0.4em;
        vertical-align: middle;
        accent-color: var(--link);
    }

    /* Horizontal rule */
    hr { border: none; border-top: 2px solid var(--hr); margin: 2em 0; }

    /* Images */
    img { max-width: 100%; height: auto; border-radius: 6px; display: block; margin: 0.5em 0; }

    /* Tables */
    table {
        border-collapse: collapse;
        width: 100%;
        margin: 0 0 1.2em;
        border: 1px solid var(--border);
        border-radius: 6px;
        overflow: hidden;
        display: block;
        overflow-x: auto;
    }
    thead { background: var(--table-header-bg); }
    th, td { border: 1px solid var(--border); padding: 8px 14px; text-align: left; vertical-align: top; }
    th { font-weight: 600; }
    tbody tr:nth-child(even) { background: var(--table-stripe); }

    /* Mermaid — clic para ampliar */
    .mermaid { cursor: zoom-in; transition: opacity 0.15s ease; border-radius: 8px; }
    .mermaid:hover { opacity: 0.75; }

    /* Scrollbars */
    ::-webkit-scrollbar { width: 8px; height: 8px; }
    ::-webkit-scrollbar-track { background: transparent; }
    ::-webkit-scrollbar-thumb { background: var(--border); border-radius: 4px; }
    ::-webkit-scrollbar-thumb:hover { background: var(--text-muted); }

    /* ── Highlight.js — GitHub Light ──────────────────────────────────────── */
    pre code.hljs{display:block;overflow-x:auto;padding:1em}code.hljs{padding:3px 5px}.hljs{color:#24292e;background:#fff}.hljs-doctag,.hljs-keyword,.hljs-meta .hljs-keyword,.hljs-template-tag,.hljs-template-variable,.hljs-type,.hljs-variable.language_{color:#d73a49}.hljs-title,.hljs-title.class_,.hljs-title.class_.inherited__,.hljs-title.function_{color:#6f42c1}.hljs-attr,.hljs-attribute,.hljs-literal,.hljs-meta,.hljs-number,.hljs-operator,.hljs-selector-attr,.hljs-selector-class,.hljs-selector-id,.hljs-variable{color:#005cc5}.hljs-meta .hljs-string,.hljs-regexp,.hljs-string{color:#032f62}.hljs-built_in,.hljs-symbol{color:#e36209}.hljs-code,.hljs-comment,.hljs-formula{color:#6a737d}.hljs-name,.hljs-quote,.hljs-selector-pseudo,.hljs-selector-tag{color:#22863a}.hljs-subst{color:#24292e}.hljs-section{color:#005cc5;font-weight:700}.hljs-bullet{color:#735c0f}.hljs-emphasis{color:#24292e;font-style:italic}.hljs-strong{color:#24292e;font-weight:700}.hljs-addition{color:#22863a;background-color:#f0fff4}.hljs-deletion{color:#b31d28;background-color:#ffeef0}

    @media (prefers-color-scheme: dark) {
    /* ── Highlight.js — GitHub Dark ───────────────────────────────────────── */
    .hljs{color:#c9d1d9;background:#0d1117}.hljs-doctag,.hljs-keyword,.hljs-meta .hljs-keyword,.hljs-template-tag,.hljs-template-variable,.hljs-type,.hljs-variable.language_{color:#ff7b72}.hljs-title,.hljs-title.class_,.hljs-title.class_.inherited__,.hljs-title.function_{color:#d2a8ff}.hljs-attr,.hljs-attribute,.hljs-literal,.hljs-meta,.hljs-number,.hljs-operator,.hljs-selector-attr,.hljs-selector-class,.hljs-selector-id,.hljs-variable{color:#79c0ff}.hljs-meta .hljs-string,.hljs-regexp,.hljs-string{color:#a5d6ff}.hljs-built_in,.hljs-symbol{color:#ffa657}.hljs-code,.hljs-comment,.hljs-formula{color:#8b949e}.hljs-name,.hljs-quote,.hljs-selector-pseudo,.hljs-selector-tag{color:#7ee787}.hljs-subst{color:#c9d1d9}.hljs-section{color:#1f6feb;font-weight:700}.hljs-bullet{color:#f2cc60}.hljs-emphasis{color:#c9d1d9;font-style:italic}.hljs-strong{color:#c9d1d9;font-weight:700}.hljs-addition{color:#aff5b4;background-color:#033a16}.hljs-deletion{color:#ffdcd7;background-color:#67060c}
    }

    /* El fondo y padding del bloque los maneja nuestro <pre>, no hljs */
    pre code.hljs { background: transparent; padding: 0; }

    /* Search highlights */
    mark.lector-hit {
        background-color: #ffeb3b;
        color: inherit;
        border-radius: 2px;
        padding: 0 1px;
    }
    mark.lector-hit-current {
        background-color: #ff9800;
        color: #000;
    }
    @media (prefers-color-scheme: dark) {
        mark.lector-hit         { background-color: #5c4a00; color: #ffd54f; }
        mark.lector-hit-current { background-color: #a06000; color: #ffe082; }
    }

    /* ── Print styles ────────────────────────────────────────────────────── */
    @media print {
        :root {
            --bg: #ffffff !important;
            --surface: #f6f8fa !important;
            --border: #d0d7de !important;
            --text: #1f2328 !important;
            --text-muted: #656d76 !important;
            --heading: #1f2328 !important;
            --link: #0969da !important;
            --code-fg: #cf222e !important;
            --blockquote-border: #0969da !important;
            --blockquote-fg: #656d76 !important;
            --hr: #d0d7de !important;
        }
        body {
            background: white !important;
            color: black !important;
            -webkit-print-color-adjust: exact;
            print-color-adjust: exact;
        }
        .markdown-body {
            max-width: none !important;
            padding: 0 !important;
            margin: 0 !important;
        }
        pre, blockquote, table, img {
            page-break-inside: avoid;
        }
        h1, h2, h3 {
            page-break-after: avoid;
        }
        ::-webkit-scrollbar { display: none; }
    }
    """
}
