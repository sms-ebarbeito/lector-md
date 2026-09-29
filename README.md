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

Los builds siguientes actualizan `~/Applications` automáticamente si la app ya existe ahí,
y registran esa copia (y no la de `.build`) para Vista Rápida. Después de la primera
copia manual, corré `bash build.sh` una vez más.

## Vista Rápida (barra espaciadora en Finder)

La app trae una extensión de Vista Rápida (`LectorMDQL.appex`, extension point
`com.apple.quicklook.preview`) que muestra el `.md` renderizado igual que la app:
Mermaid, resaltado de código y modo oscuro.

`build.sh` la firma aparte, **antes** que la app y sin `--deep`:

- **La extensión** corre con App Sandbox (`QuickLookMD/LectorMDQL.entitlements`).
  Tiene también `com.apple.security.network.client`: sin eso, WKWebView no arranca
  dentro del sandbox, aunque todo el contenido sea local.
- **La app** sigue sin sandbox.
- **Identidad:** si en el llavero hay un certificado **"Apple Development"** (el
  gratuito de cualquier Apple ID, no hace falta la cuenta paga), lo usa. Si no hay,
  firma ad-hoc y avisa. Para forzar otra identidad: `SIGN_IDENTITY="..." bash build.sh`
  (`SIGN_IDENTITY=-` fuerza ad-hoc).

  En macOS 27 la vista previa también carga con ad-hoc; el certificado se usa
  cuando está porque da una identidad estable (TeamIdentifier) entre builds.

Después de firmar, el script registra la app (`lsregister -f`) y la extensión
(`pluginkit -a`), y reinicia Vista Rápida (`qlmanage -r`, `qlmanage -r cache`).

### Verificar

```bash
# ¿macOS la reconoce? Tiene que aparecer com.lectormd.app.qlextension
pluginkit -m -v -p com.apple.quicklook.preview | grep -i lector

# Vista previa directa, sin Finder
qlmanage -p .build/prueba.md
```

Si `pluginkit` la lista con un `-` adelante, está desactivada. Activala en
**Ajustes del Sistema → General → Ítems de inicio y extensiones → Vista rápida**
(activar LectorMD), o con:

```bash
pluginkit -e use -i com.lectormd.app.qlextension
```

Si macOS muestra *"LectorMD differs from previously opened versions"* después de
cambiar de firma (por ejemplo, de ad-hoc a "Apple Development"), elegí **Open Anyway**
una vez: así el contenedor del sandbox de la extensión pasa a la firma nueva.

Para ver por qué no carga:

```bash
/usr/bin/log stream --predicate 'process == "LectorMDQL" OR process BEGINSWITH "com.apple.WebKit" OR subsystem == "com.apple.PlugInKit"'
```

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
├── PreviewViewController.swift  # Extensión de Vista Rápida (QLPreviewingController + WKWebView)
├── ExtInfo.plist                # Info.plist del .appex (com.apple.quicklook.preview)
└── LectorMDQL.entitlements      # App Sandbox + network.client (necesario para WKWebView)
```
