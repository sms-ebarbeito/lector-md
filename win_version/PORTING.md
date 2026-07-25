# LectorMD — Port a Windows (.exe portable)

Este documento es el contexto y plan de trabajo para portar LectorMD (visualizador nativo de
Markdown, hoy solo macOS/SwiftUI) a una versión Windows distribuible como **.exe portable**,
sin instalador y sin requerir permisos de administrador ni conexión a internet en la máquina
destino.

Está pensado para que un agente (Claude Code u otro) corriendo en una máquina Windows lo lea
y ejecute la implementación directamente.

## Contexto y restricción clave

La máquina Windows destino es una **laptop laboral bloqueada**: no se puede instalar software
(sin permisos de admin, sin acceso a instaladores). Esto descarta cualquier solución que
dependa de un runtime que haya que instalar aparte (Node/Electron requeriría node_modules
pero el binario final de Electron sí es portable; .NET moderno —5/6/7/8— normalmente no viene
preinstalado). La solución debe poder copiarse como una carpeta y ejecutarse directo.

## Decisión: WPF sobre .NET Framework 4.8 + WebView2 (Fixed Version)

- **.NET Framework 4.8** ya viene preinstalado de fábrica en Windows 10/11 — no hay que
  instalar nada en la máquina destino para el runtime base.
- **WPF** como shell de UI (ventana, menú, apertura de archivos) — es el análogo directo del
  `NSWindow`/`SwiftUI` actual.
- **Microsoft.Web.WebView2** (paquete NuGet) como reemplazo de `WKWebView`. Es solo un wrapper:
  compila a DLLs que viajan junto al `.exe`, no requiere instalación.
- El motor real de WebView2 (basado en Edge Chromium) se distribuye en modalidad
  **Fixed Version** (no Evergreen): se empaqueta el runtime completo en una carpeta al lado
  del ejecutable. Sí, pesa ~150MB extra, pero garantiza que la app funcione sin depender de
  qué tenga instalado esa PC en particular. **No usar Evergreen** — asume que el runtime ya
  está en el sistema, y en una máquina corporativa bloqueada eso no se puede garantizar.

Resultado esperado: una carpeta (`LectorMD-win/`) con el `.exe`, las DLLs de WebView2 y la
carpeta del runtime Fixed Version, que se copia a la máquina destino y corre sin instalar
nada ni pedir privilegios elevados.

## Qué se reutiliza del código actual (macOS) vs. qué se reescribe

El renderizado de LectorMD ya es independiente de AppKit: `MarkdownRenderer.swift` es un
parser Markdown→HTML sin dependencias externas, y el HTML resultante se envuelve con
`HTMLTemplate.build()` (CSS + highlight.js + mermaid.js + JS de búsqueda). Esa capa es texto
puro (HTML/CSS/JS) y **se reutiliza tal cual**, sirviéndola al `WebView2` igual que hoy se
sirve a `WKWebView`.

Lo que **se reescribe** es exclusivamente el shell nativo (era AppKit, ahora será WPF/C#):

| Componente macOS (Swift/AppKit)              | Equivalente Windows (C#/WPF)                          |
|-----------------------------------------------|---------------------------------------------------------|
| `LectorMDApp.swift` (`DocumentGroup`)         | `App.xaml` + lógica de apertura de archivo (`OpenFileDialog` / asociación `.md`) |
| `MarkdownDocument.swift` (`FileDocument`)     | Clase simple de lectura de archivo (`File.ReadAllText`) |
| `ContentView.swift`                            | `MainWindow.xaml`                                       |
| `MarkdownWebView.swift` (`NSViewRepresentable` → `WKWebView`) | `Microsoft.Web.WebView2.Wpf.WebView2` control embebido |
| `Coordinator` (`WKScriptMessageHandler`, puente JS↔Swift) | `CoreWebView2.WebMessageReceived` / `ExecuteScriptAsync` (puente JS↔C#) |
| `Coordinator.openDiagramViewer()` (NSWindow separada para Mermaid) | Segunda `Window` WPF con su propio `WebView2` |
| `FrameSetterView` (tamaño inicial de ventana) | Seteo de `Width`/`Height` en el constructor de `MainWindow` (mucho más simple en WPF, no hace falta el workaround) |
| `SearchModel` / `SearchPanel` (Cmd+F)         | Reescribir el overlay de búsqueda en XAml; la lógica JS (`lectorSearch`, `lectorNorm`, etc.) se reutiliza sin cambios |
| `MarkdownRenderer.swift`, `HTMLTemplate.swift`, `Resources/highlight.min.js`, `Resources/mermaid.min.js` | **Se reutilizan tal cual** (portar el parser Markdown→HTML a C#, o cargarlo vía un motor JS si se prefiere no reescribirlo — a decidir, ver sección "Pendiente de decisión") |

## Atajos y comportamiento a preservar

- Cmd+F (macOS) → Ctrl+F (Windows) para el panel de búsqueda.
- Cmd+R (macOS) → Ctrl+R (Windows) para recarga de documento.
- Selector de apariencia Sistema / Claro / Oscuro (ya existe en macOS, ver commit
  `58a35ba`) — en WPF, escuchar `SystemParameters` / registro de tema de Windows para el modo
  "Sistema".
- Búsqueda: mismo comportamiento — query ≥ 3 caracteres dispara `performSearch()`
  automáticamente; Enter con resultados → `next()`; Enter sin resultados → `performSearch()`.
  Toda esta lógica vive en JS (`lectorSearch`, `lectorNorm`, `lector-hit` / `lector-hit-current`)
  y no cambia entre plataformas.

## Pendiente de decisión

1. **Parser Markdown→HTML**: portar `MarkdownRenderer.swift` línea por línea a C#, o
   ejecutar el JS/HTML resultante mediante alguna librería de Markdown ya existente en
   .NET (ej. Markdig) y ajustar el HTML generado para que coincida con las clases CSS del
   `HTMLTemplate` actual. Recomendado: portar el parser propio a C# para minimizar
   diferencias de comportamiento respecto a la versión macOS (slugify de headings, etc.),
   salvo que se prefiera mantenimiento único vía librería estándar.
2. **Asociación de archivo `.md`** en Windows (doble click abre LectorMD) — requiere modificar
   el registro (`HKEY_CURRENT_USER\Software\Classes`), que sí puede hacerse sin admin
   (alcance de usuario), a diferencia de `HKEY_LOCAL_MACHINE`.
3. **Firma del ejecutable**: sin certificado de code signing, Windows SmartScreen puede
   marcar el `.exe` como no confiable la primera vez que se ejecuta. Es aceptable para uso
   personal/laboral interno, pero conviene avisar al usuario.

## Pasos para el agente en Windows

1. Verificar que esté disponible `dotnet` (SDK, no solo runtime) o Visual Studio con carga de
   trabajo ".NET desktop development" en la máquina de **desarrollo** (no necesariamente la
   máquina laboral restringida — se compila en un lado y se copia el resultado al otro).
2. Crear proyecto WPF (.NET Framework 4.8): `LectorMD.Win.sln` / `LectorMD.Win.csproj`.
3. Agregar el paquete NuGet `Microsoft.Web.WebView2`.
4. Descargar el **Fixed Version Runtime** de WebView2 (desde el sitio oficial de Microsoft
   Edge Developer) y empaquetarlo junto al ejecutable en la carpeta de salida.
5. Portar `HTMLTemplate.swift` y los recursos (`highlight.min.js`, `mermaid.min.js`) tal cual,
   sirviéndolos vía `NavigateToString` o cargando un archivo HTML local con
   `CoreWebView2.Navigate("file://...")`.
6. Portar `MarkdownRenderer.swift` a C# (ver punto 1 de "Pendiente de decisión").
7. Reescribir el shell: `MainWindow.xaml.cs` (abrir archivo, host del WebView2, puente
   JS↔C# para atajos de teclado y el visor de diagramas Mermaid en ventana separada).
8. Publicar en modo **self-contained** (`dotnet publish -c Release -r win-x64
   --self-contained true -p:PublishSingleFile=true`) para minimizar dependencias externas
   más allá del propio WebView2 Runtime empaquetado.
9. Validar que la carpeta resultante corra en una máquina Windows limpia (sin VS, sin admin)
   copiándola y ejecutando el `.exe` directamente.

## Archivos de referencia en el repo macOS (para consulta, no para copiar directo)

- `LectorMD/MarkdownRenderer.swift` — parser Markdown→HTML.
- `LectorMD/HTMLTemplate.swift` — armado del HTML final (CSS, highlight.js, mermaid.js, JS de búsqueda).
- `LectorMD/MarkdownWebView.swift` — integración WKWebView + Coordinator (puente JS↔Swift).
- `LectorMD/ContentView.swift` — composición de la ventana principal, SearchPanel.
- `LectorMD/Resources/highlight.min.js`, `LectorMD/Resources/mermaid.min.js` — reutilizables tal cual.
- `CLAUDE.md` (raíz del repo) — contexto arquitectónico completo de la versión macOS.
