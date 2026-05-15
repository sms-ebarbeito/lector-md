# LectorMD

Visualizador nativo de Markdown para macOS. Renderiza `.md` directamente en una ventana limpia, con soporte para diagramas Mermaid, resaltado de sintaxis y búsqueda en el documento.

## Características

- **Renderizado completo de Markdown**: headings, negrita, cursiva, tablas, listas, task lists, blockquotes, links, imágenes
- **Resaltado de sintaxis** en bloques de código (via Highlight.js, tema GitHub claro/oscuro)
- **Diagramas Mermaid**: se renderizan inline; click en el diagrama lo abre en ventana separada para verlo en grande
- **Modo oscuro automático** siguiendo la preferencia del sistema
- **Búsqueda en el documento** (Cmd+F):
  - Búsqueda sin distinción de acentos ("parrafo" encuentra "Párrafo")
  - Resalta todas las ocurrencias; la actual en naranja, las demás en amarillo
  - Contador de posición (ej: `2 / 8`)
  - Enter navega a la siguiente ocurrencia; botones ↑ ↓ para avanzar/retroceder
  - Lista de títulos y subtítulos para navegación rápida
- **Vista previa Quick Look** al presionar espacio en Finder
- Ventana redimensionable; se abre al 90% del alto de pantalla por defecto

## Requisitos

- macOS 13 Ventura o superior
- Xcode Command Line Tools (`xcode-select --install`)

## Compilar

```bash
bash build.sh
```

La app queda en `.build/LectorMD.app` y se abre automáticamente con un archivo de prueba.

Para instalar en `~/Applications`:

```bash
cp -R .build/LectorMD.app ~/Applications/
```

Los builds siguientes actualizan `~/Applications` automáticamente si la app ya existe ahí.

## Estructura

```
LectorMD/
├── LectorMDApp.swift        # Entry point, AppDelegate
├── MarkdownDocument.swift   # Modelo de documento (FileDocument)
├── ContentView.swift        # Vista principal, SearchModel, SearchPanel, WindowFrameSaver
├── MarkdownWebView.swift    # WKWebView wrapper, visor de diagramas Mermaid
├── MarkdownRenderer.swift   # Parser/renderer Markdown → HTML (sin dependencias)
├── HTMLTemplate.swift       # Template HTML completo: CSS, highlight.js, mermaid, JS de búsqueda
QuickLookMD/
└── PreviewViewController.swift  # Extensión Quick Look
```
