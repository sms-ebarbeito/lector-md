# CLAUDE.md — LectorMD

Contexto de arquitectura y decisiones técnicas para Claude Code.

## Cómo compilar y probar

```bash
bash build.sh          # compila, firma, abre prueba.md
```

Para instalar/actualizar en `~/Applications` después del build:
```bash
cp -R .build/LectorMD.app ~/Applications/
xattr -rd com.apple.quarantine ~/Applications/LectorMD.app
```

Tests de seguridad (#5): escape del renderer, CSP y puente `diagramClick`, con WebKit de verdad:
```bash
bash test.sh           # compila Tests/SecurityTests.swift con las fuentes y lo corre
```

Verificar tipos sin compilar el bundle completo (más rápido):
```bash
swiftc -typecheck LectorMD/*.swift \
  -sdk $(xcrun --show-sdk-path --sdk macosx) \
  -target arm64-apple-macosx13.0 \
  -framework SwiftUI -framework AppKit -framework WebKit
```

## Arquitectura

La app es un `DocumentGroup` (SwiftUI) que abre archivos `.md` como `FileDocument`. Cada documento se renderiza en un `WKWebView` embebido en un `NSViewRepresentable`.

```
MarkdownDocument (FileDocument)
    └── ContentView (SwiftUI)
            ├── MarkdownWebView (NSViewRepresentable → WKWebView)
            │       └── Coordinator (WKScriptMessageHandler)
            │               └── openDiagramViewer() → NSWindow separada
            ├── SearchPanel (SwiftUI overlay, top-trailing)
            └── FrameSetterView (NSView subclass, maneja tamaño inicial)
```

## Renderizado

`MarkdownRenderer` es un parser propio sin dependencias externas. Convierte Markdown → HTML mediante walks de líneas. Todo lo que viene del `.md` pasa por `HTMLSafety`: `escapeText` para texto y `escapeAttribute` para valores de atributo (ver *Seguridad*). El HTML resultante se pasa a `HTMLTemplate.build()` que agrega:
- CSS completo (variables de color con `prefers-color-scheme`)
- Highlight.js (resaltado de código, temas GitHub claro/oscuro)
- Mermaid.js (diagramas)
- `lectorSearch()`, `lectorSearchNext()`, `lectorSearchPrev()` (búsqueda JS)
- en `head`, la Content-Security-Policy: `HTMLTemplate.appHead()` en la app, la suya en la Vista Rápida

Los headings reciben `id` generados con `MarkdownRenderer.slugify()` — la misma función usa `SearchModel.loadHeadings()` para que los IDs coincidan al navegar.

## Búsqueda (Cmd+F)

- **`SearchModel`** (ObservableObject): mantiene query, matchCount, currentMatch, lista de headings y una referencia `weak` al `WKWebView`.
- **`SearchPanel`**: overlay SwiftUI top-trailing, ancho 272px, aparece/desaparece con animación `.move(edge: .trailing)`.
- **Flujo**: query ≥ 3 chars → `performSearch()` automático; Enter con resultados → `next()`; Enter sin resultados → `performSearch()`.
- **JS `lectorNorm()`**: normaliza diacríticos carácter a carácter (NFD + strip combining marks U+0300–U+036F). Al procesar de a 1 char, el largo del string resultante == largo del original, así los índices son directamente aplicables al texto original para extraer el match con su ortografía real.
- **`lector-hit`** (amarillo): todos los matches. **`lector-hit-current`** (naranja): match activo. `lectorCurrentHit` es un var global en el HTML que trackea la posición.

## Ventana Mermaid

`Coordinator.openDiagramViewer()` abre un `NSWindow` con un `WKWebView` separado. El HTML sale de `HTMLTemplate.diagramPage(svg:)`: el SVG más una barra de búsqueda HTML/CSS/JS con `window.find()` (apropiado para SVG), con su propia CSP (el script de búsqueda por hash, sin handlers inline). El SVG llega por el puente `diagramClick` y solo se acepta si pasa `Coordinator.diagramSVG(from:)` (ver *Seguridad*). `isReleasedWhenClosed = false` es necesario para evitar un crash por operaciones async pendientes en WKWebView.

## Tamaño de ventana

`FrameSetterView` (NSView subclass usada como `.background()` en ContentView) sobreescribe `viewDidMoveToWindow()` — el único punto donde `self.window` está garantizado no-nil. Aplica el frame dos veces:
1. Sincrónico en `viewDidMoveToWindow()` (antes de que la ventana sea visible)
2. En `didBecomeKeyNotification` (después de que SwiftUI termina su layout inicial)

Esto cubre el caso donde SwiftUI sobreescribe el frame con sus propios valores de layout.

Tamaño default: ancho 860px, alto = 90% del alto total de pantalla (`frame.height`, no `visibleFrame`).

## Vista Rápida (`QuickLookMD/`)

`LectorMDQL.appex` es una Quick Look Preview Extension (`com.apple.quicklook.preview`, `QLIsDataBasedPreview = false`): `PreviewViewController` (`QLPreviewingController`) renderiza con el mismo `MarkdownRenderer` + `HTMLTemplate` en un `WKWebView`, con `baseURL` = Resources del `.appex` (ahí van `highlight.min.js` y `mermaid.min.js`). Llama al `completionHandler` en `didFinish` (llega en unos 300 ms) o a los 2 s, lo que pase primero; los 2 s son un watchdog por si WebKit no avisa nunca (p. ej. un script colgado sin que muera WebContent). Si falla la carga o muere el WebContent, lo llama con error y Quick Look cae al preview de texto de Apple. Los links que salen del documento se cancelan; las anclas `#titulo` funcionan.

- **Sin red:** la vista previa no carga nada remoto. Una `WKContentRuleList` bloquea toda carga `http(s)`/`ws(s)` del WKWebView, de cualquier tipo de recurso. Además, la extensión pasa en `HTMLTemplate.build(head:)` la misma CSP que la app (`HTMLTemplate.contentSecurityPolicy`), pero con imágenes y fuentes solo de `file:`/`data:`. La CSP bloquea aunque la lista no compile. Un script reemplaza cada `<img>` remota por un recuadro con su `alt` o su dominio, y agrega un aviso arriba. `allowsLinkPreview = false`.
- Las imágenes locales no se ven en la vista previa: las relativas se resuelven contra el `baseURL` (Resources del `.appex`) y las absolutas las bloquea el sandbox. Las `data:` sí se ven.
- `ExtInfo.plist` es el Info.plist del `.appex` tanto para `build.sh` como para el proyecto Xcode.
- La extensión **tiene que** tener App Sandbox (`LectorMDQL.entitlements`). Dentro del sandbox, WKWebView necesita `com.apple.security.network.client`: sin eso WebContent/GPU/Networking abortan con "Application does not have permission to communicate with network resources".
- Firma de adentro hacia afuera, sin `--deep`: primero el `.appex` con sus entitlements, después la app. Identidad: `SIGN_IDENTITY` o el primer "Apple Development" del llavero; si no hay, ad-hoc. Al cambiar de identidad (p. ej. ad-hoc → Apple Development), macOS pregunta una vez "differs from previously opened versions" por el contenedor del sandbox de la extensión.
- `build.sh` registra solo una copia (la de `~/Applications` si existe) para que PlugInKit no elija la de `.build`.

## Seguridad (#5)

Un `.md` es contenido que no controlamos: nada de lo que trae puede ejecutar JS. Las capas son independientes: el escape del renderer y la CSP alcanzan cada una por sí sola para que el `.md` no ejecute nada.

- **Renderer.** `HTMLSafety.escapeText` (`& < >`) para texto y `escapeAttribute` (`& < > " '`) para todo valor de atributo, siempre entre comillas dobles. Recorren unicode scalars, no `Character`: una `"` seguida de un acento combinante es un solo `Character` y no se escaparía. Imágenes y links se arman sobre el texto sin escapar (cada valor se escapa una sola vez) y quedan como sentinels, así los énfasis no tocan sus atributos. `href` y `src` pasan por `isSafeURL`: se rechazan `javascript:`, `vbscript:` y `data:` (salvo `data:image/…` en imágenes), ignorando mayúsculas, espacios y controles; un link o imagen rechazado queda como texto Markdown. El `title` de links e imágenes se soporta, entre `"` o `'`. El lenguaje de un bloque de código es su primera palabra. Los sentinels (U+E000/U+E001) que traiga el `.md` se reemplazan por U+FFFD.
- **HTML crudo: siempre texto.** No hay bloques HTML ni HTML inline: todo `<…>` del `.md` se escapa (párrafos, títulos, listas, citas, tablas, texto de links), así que se ve como texto y no se interpreta. Decisión del #5: no se sanitiza ni se permite un subconjunto.
- **CSP** (`HTMLTemplate.contentSecurityPolicy`, en `head`, antes que cualquier contenido): `default-src 'none'`; `script-src file:` más los `<script>` inline del template **solo por hash** (se calculan del template con el body vacío, así nada del `.md` queda permitido); sin `'unsafe-inline'` ni `'unsafe-eval'` (Mermaid y highlight.js no los necesitan); `style-src 'unsafe-inline'` (Mermaid mete estilos); `object-src`, `base-uri` y `form-action` en `'none'`. La app permite `img-src https: http: data: file:`; la Vista Rápida, solo `file: data:`. `evaluateJavaScript` (búsqueda, títulos) no pasa por la CSP. Si agregás o cambiás un `<script>` inline en `HTMLTemplate`, el hash se recalcula solo; un `<script>` con atributos (salvo `src`) no se detecta, así que no se ejecutaría.
- **Mermaid con `securityLevel: 'strict'`** (el default de Mermaid). Con `'loose'`, `click A call f(…)` llamaba a cualquier función global desde el `.md` (p. ej. `webkit.messageHandlers.diagramClick.postMessage`), los links de los diagramas no se saneaban y el SVG no pasaba por DOMPurify. Los directivos `%%{init}%%` no pueden cambiar `securityLevel`.
- **Puente `diagramClick`.** `Coordinator.diagramSVG(from:)` acepta solo mensajes del marco principal con origen `file:` (nuestro documento: si el WKWebView navega a otra página por un link, esa página también ve `window.webkit.messageHandlers`) y solo un SVG que pase `HTMLSafety.isSafeDiagramSVG`: hasta 5 MB, empieza con `<svg` y termina con `</svg>`, sin `<script>`, `<iframe>`, `<meta>`, `<!…>` y parecidos, sin atributos `on*` y con `href`/`src` seguros. No es un parser de HTML: lo que garantiza que nada se ejecute en la ventana del diagrama es su CSP.

`bash test.sh` prueba cada capa: salidas exactas del renderer, y con WKWebView fuera de pantalla que `Tests/ataque.md` no ejecuta nada con la CSP de la app (un servidor propio en 127.0.0.1 no recibe ningún `/xss-…`), que `Tests/normal.md` anda igual (Mermaid, resaltado, búsqueda, anclas, imágenes remotas, clic en el diagrama, sin violaciones de CSP) y controles sin CSP que sí ejecutan. En un binario de línea de comandos WebKit no da permiso de lectura al `baseURL` de `loadHTMLString`; el test lo consigue con un `loadFileURL(…, allowingReadAccessTo:)` previo.

## Convenciones

- `build.sh` firma la app principal sin sandbox. La extensión de Vista Rápida sí va con sandbox (obligatorio). Con sandbox, WKWebView necesita `com.apple.security.network.client` (verificado en la extensión). Ojo: el target de la app en el proyecto Xcode todavía usa `LectorMD/LectorMD.entitlements` (sandbox sin `network.client`), pero ese no es el build oficial
- `WeakScriptHandler` wrappea el Coordinator para evitar retain cycle con `WKUserContentController`
- `diagramWindows: [NSWindow]` en el Coordinator mantiene referencias fuertes a las ventanas de diagrama para que no se liberen prematuramente
- No usar `setFrameAutosaveName` — interfiere con el sizing manual y restaura frames pequeños de sesiones anteriores
