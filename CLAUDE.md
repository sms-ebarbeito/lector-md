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

`MarkdownRenderer` es un parser propio sin dependencias externas. Convierte Markdown → HTML mediante walks de líneas. El HTML resultante se pasa a `HTMLTemplate.build()` que agrega:
- CSS completo (variables de color con `prefers-color-scheme`)
- Highlight.js (resaltado de código, temas GitHub claro/oscuro)
- Mermaid.js (diagramas)
- `lectorSearch()`, `lectorSearchNext()`, `lectorSearchPrev()` (búsqueda JS)

Los headings reciben `id` generados con `MarkdownRenderer.slugify()` — la misma función usa `SearchModel.loadHeadings()` para que los IDs coincidan al navegar.

## Búsqueda (Cmd+F)

- **`SearchModel`** (ObservableObject): mantiene query, matchCount, currentMatch, lista de headings y una referencia `weak` al `WKWebView`.
- **`SearchPanel`**: overlay SwiftUI top-trailing, ancho 272px, aparece/desaparece con animación `.move(edge: .trailing)`.
- **Flujo**: query ≥ 3 chars → `performSearch()` automático; Enter con resultados → `next()`; Enter sin resultados → `performSearch()`.
- **JS `lectorNorm()`**: normaliza diacríticos carácter a carácter (NFD + strip combining marks U+0300–U+036F). Al procesar de a 1 char, el largo del string resultante == largo del original, así los índices son directamente aplicables al texto original para extraer el match con su ortografía real.
- **`lector-hit`** (amarillo): todos los matches. **`lector-hit-current`** (naranja): match activo. `lectorCurrentHit` es un var global en el HTML que trackea la posición.

## Ventana Mermaid

`Coordinator.openDiagramViewer()` abre un `NSWindow` con un `WKWebView` separado. El HTML del diagrama incluye una barra de búsqueda HTML/CSS/JS con `window.find()` (apropiado para SVG). `isReleasedWhenClosed = false` es necesario para evitar un crash por operaciones async pendientes en WKWebView.

## Tamaño de ventana

`FrameSetterView` (NSView subclass usada como `.background()` en ContentView) sobreescribe `viewDidMoveToWindow()` — el único punto donde `self.window` está garantizado no-nil. Aplica el frame dos veces:
1. Sincrónico en `viewDidMoveToWindow()` (antes de que la ventana sea visible)
2. En `didBecomeKeyNotification` (después de que SwiftUI termina su layout inicial)

Esto cubre el caso donde SwiftUI sobreescribe el frame con sus propios valores de layout.

Tamaño default: ancho 860px, alto = 90% del alto total de pantalla (`frame.height`, no `visibleFrame`).

## Vista Rápida (`QuickLookMD/`)

`LectorMDQL.appex` es una Quick Look Preview Extension (`com.apple.quicklook.preview`, `QLIsDataBasedPreview = false`): `PreviewViewController` (`QLPreviewingController`) renderiza con el mismo `MarkdownRenderer` + `HTMLTemplate` en un `WKWebView`, con `baseURL` = Resources del `.appex` (ahí van `highlight.min.js` y `mermaid.min.js`). Llama al `completionHandler` recién en `didFinish` (o con error si falla la carga o muere el WebContent → Quick Look cae al preview de texto de Apple).

- `ExtInfo.plist` es el Info.plist del `.appex` tanto para `build.sh` como para el proyecto Xcode.
- La extensión **tiene que** tener App Sandbox (`LectorMDQL.entitlements`). Dentro del sandbox, WKWebView necesita `com.apple.security.network.client`: sin eso WebContent/GPU/Networking abortan con "Application does not have permission to communicate with network resources".
- Firma de adentro hacia afuera, sin `--deep`: primero el `.appex` con sus entitlements, después la app. Identidad: `SIGN_IDENTITY` o el primer "Apple Development" del llavero; si no hay, ad-hoc. Al cambiar de identidad (p. ej. ad-hoc → Apple Development), macOS pregunta una vez "differs from previously opened versions" por el contenedor del sandbox de la extensión.
- `build.sh` registra solo una copia (la de `~/Applications` si existe) para que PlugInKit no elija la de `.build`.

## Convenciones

- La app principal va sin sandbox (la firma ad-hoc + WKWebView no funciona bien con sandbox habilitado). La extensión de Vista Rápida sí va con sandbox (obligatorio)
- `WeakScriptHandler` wrappea el Coordinator para evitar retain cycle con `WKUserContentController`
- `diagramWindows: [NSWindow]` en el Coordinator mantiene referencias fuertes a las ventanas de diagrama para que no se liberen prematuramente
- No usar `setFrameAutosaveName` — interfiere con el sizing manual y restaura frames pequeños de sesiones anteriores
