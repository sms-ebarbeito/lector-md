# Documentación del renderizador Markdown — LectorMD

## Visión general

El sistema convierte Markdown → HTML en dos etapas:

1. **`MarkdownRenderer`** — parser propio (sin librerías externas) que produce un fragmento HTML.
2. **`HTMLTemplate.build(body:)`** — envuelve ese fragmento en un documento HTML completo con CSS, Highlight.js y Mermaid.js.

---

## Etapa 1: `MarkdownRenderer` — Markdown → HTML

### Normalización previa

Antes de parsear, se normalizan saltos de línea:
- `\r\n` → `\n`
- `\r` → `\n`

---

### Renderizado de bloques (`renderBlocks`)

Se procesa línea por línea con un índice `i`. Cada tipo de bloque consume una o más líneas y avanza `i`. El orden de detección importa (mayor precedencia primero):

#### 1. Bloque de código cercado (fenced code)

```
Detector: línea empieza con ``` o ~~~
```

- Se extrae la **fence** (los 3 primeros chars) y el **lang**: como en CommonMark, la primera palabra del resto del primer renglón.
- Se acumulan líneas hasta encontrar otra que empiece con la misma fence → fin del bloque.
- **Si `lang` es `mermaid`** (sin importar mayúsculas): el contenido se escapa como texto (`HTMLSafety.escapeText`: `&`, `<`, `>`); Mermaid lee el `textContent`, que queda igual al original. Se emite:
  ```html
  <div class="mermaid">...contenido...</div>
  ```
- **Cualquier otro lang**: el contenido se escapa como texto y el lang como atributo (`HTMLSafety.escapeAttribute`), y se emite:
  ```html
  <pre><code class="language-LANG">...contenido...</code></pre>
  ```
  Si no hay lang: `<code>` sin clase.

#### 2. Heading ATX

```
Detector: línea empieza con 1–6 `#` seguidos de espacio (o fin de línea)
```

- Se cuenta la cantidad de `#` → nivel (1–6).
- El texto es el resto, trimmeado. Se eliminan `#` al final (trailing `#`).
- Se genera un `id` con `slugify(texto)` (y se escapa como atributo, aunque `slugify` ya solo deja letras, números, `-` y `_`).
- El texto pasa por `renderInline()`.
- Emite: `<hN id="SLUG">TEXTO</hN>`

#### 3. Heading Setext

```
Detector: línea actual no vacía + línea siguiente es solo `=` o solo `-` (≥2 chars)
```

- `====...` → `<h1>`, `----...` → `<h2>`.
- Se excluye el caso donde la línea con `-` es una regla horizontal (`isHRule`).
- Mismo tratamiento de id y renderInline que ATX.

#### 4. Regla horizontal (`<hr>`)

```
Detector: 3+ caracteres, todos iguales: solo `-`, solo `*`, o solo `_` (ignorando espacios)
```

Emite: `<hr>`

#### 5. Blockquote

```
Detector: línea empieza con `>`
```

- Se acumulan líneas mientras:
  - Empiecen con `>` (se quita el `>` y un espacio, si hay: `> texto` y `>texto` valen igual)
  - Estén vacías y la siguiente empiece con `>`
- El contenido acumulado se renderiza **recursivamente** con `renderBlocks()`.
- Emite: `<blockquote>CONTENIDO</blockquote>`

#### 6. Lista desordenada (`<ul>`)

```
Detector: línea empieza con `- `, `* `, o `+ ` (prefijo de 2 chars)
```

- Se acumulan ítems consecutivos del mismo tipo.
- Cada ítem pasa por `renderTaskOrInline()` (para soportar task lists).
- Emite: `<ul><li>...</li>...</ul>`

**Task list** (dentro de ítems):
- `[ ] texto` → `<input type="checkbox" disabled> texto`
- `[x] texto` o `[X] texto` → `<input type="checkbox" checked disabled> texto`

#### 7. Lista ordenada (`<ol>`)

```
Detector: línea empieza con dígitos seguidos de `. ` (e.g., `1. `, `42. `)
```

- Se acumulan ítems consecutivos.
- El prefijo numérico se elimina, el resto pasa por `renderInline()`.
- Emite: `<ol><li>...</li>...</ol>`
- **Nota**: el número real del ítem se ignora; el orden lo da el HTML.

#### 8. Tabla GFM

```
Detector: línea siguiente a la actual es un separador de tabla (solo `|`, `-`, `:`, espacios)
         Y la línea actual contiene `|`
```

El separador puede ser como: `|---|---|`, `|:---:|---:|`, etc.

- Se acumula la cabecera + filas mientras las líneas contengan `|`.
- Cada celda se parsea con `splitTableRow()`:
  - Se quitan `|` al inicio y fin.
  - Se divide por `|`, cada celda se trimmea.
- Emite:
  ```html
  <table>
    <thead><tr><th>...</th>...</tr></thead>
    <tbody><tr><td>...</td>...</tr>...</tbody>
  </table>
  ```
- El separador (segunda línea) se salta automáticamente.

#### 9. Párrafo (fallback)

Se acumulan líneas consecutivas no vacías que no disparan ningún otro bloque. Las líneas con **dos espacios al final** generan un `<br>` (hard break).

Emite: `<p>LÍNEA1\nLÍNEA2...</p>`

---

### Renderizado inline (`renderInline`)

Transforma el texto dentro de bloques. Usa **5 pasadas** para evitar bugs de índices. Lo ya armado se guarda aparte y en el texto queda un **sentinel** `\u{E000}N\u{E001}` (N es el índice): así las pasadas siguientes no lo tocan. Si el `.md` trae esos caracteres del área de uso privado, se reemplazan antes por `U+FFFD`.

#### Pasada 1 — Extraer código inline

Se buscan pares de backticks `` ` `` manualmente (no con regex). El contenido se escapa como texto y queda como sentinel de `<code>CONTENIDO</code>`.

#### Pasada 2 — Imágenes y links

Sobre el texto **sin escapar**, así cada valor se escapa una sola vez, al armar el atributo con `HTMLSafety.escapeAttribute` (`&`, `<`, `>`, `"`, `'`).

| Patrón | Salida |
|--------|--------|
| `![alt](url "title")` | `<img src="url" alt="alt" title="title">` (sentinel) |
| `[texto](url 'title')` | `<a href="url" title="title">` + texto + `</a>` (las etiquetas como sentinels; el texto sigue en el flujo y le aplican los énfasis) |

- El destino son palabras separadas por espacios, sin `)`. Después de un espacio, una palabra que empieza con `"` o `'` es el title, y las demás no llevan `[`. Las regex son posesivas: lineales aunque la línea sea enorme.
- `href` y `src` pasan por `HTMLSafety.isSafeURL`: si el esquema es `javascript:`, `vbscript:` o `data:` (salvo `data:image/…` en una imagen), el Markdown queda como texto.
- El `alt` y el `title` usan el texto plano de un código inline que tengan adentro.

#### Pasada 3 — Escape del texto restante

`HTMLSafety.escapeText`: `&` → `&amp;`, `<` → `&lt;`, `>` → `&gt;`. Los sentinels son solo dígitos, así que no cambian. Así el **HTML crudo del `.md` siempre sale como texto**.

#### Pasada 4 — Énfasis (regex rebuild-based)

Función `sub(input, pattern, replace)`: itera los matches, reconstruye el string concatenando partes no-match y reemplazos → sin aritmética de offsets, sin bugs.

| Patrón | Salida |
|--------|--------|
| `***texto***` | `<strong><em>texto</em></strong>` |
| `___texto___` | `<strong><em>texto</em></strong>` |
| `**texto**` | `<strong>texto</strong>` |
| `__texto__` | `<strong>texto</strong>` |
| `*texto*` (no `**`) | `<em>texto</em>` |
| `_texto_` (no `__`) | `<em>texto</em>` |
| `~~texto~~` | `<del>texto</del>` |

Los patrones `*` y `_` usan lookahead/lookbehind para no capturar `**` o `__`.

#### Pasada 5 — Restaurar

Se sustituyen los sentinels por su HTML, en una sola pasada (lo restaurado no se vuelve a mirar).

---

### `slugify(text)` — generación de IDs para headings

```
texto → minúsculas → espacios por guiones → filtrar solo [a-z, 0-9, -, _]
      → quitar guiones al inicio/fin → "heading" si vacío
```

**Importante**: La búsqueda de headings en el cliente usa esta misma función para generar los IDs y navegar a ellos, por lo que debe ser idéntica.

---

### `HTMLSafety` — escape y validaciones

- `escapeText(text)`: `&` → `&amp;`, `<` → `&lt;`, `>` → `&gt;`. Para texto entre etiquetas.
- `escapeAttribute(value)`: además `"` → `&quot;` y `'` → `&#39;`. Para todo valor de atributo (siempre entre comillas dobles).
- Los dos recorren unicode scalars, no `Character`: una `"` seguida de un acento combinante es un solo `Character`, pero para el parser de HTML sigue siendo una comilla.
- `isSafeURL(url, allowDataImage:)`: `false` para `javascript:`, `vbscript:` y `data:` (salvo `data:image/…` si `allowDataImage`). Ignora mayúsculas, espacios y controles, como el navegador.
- `isSafeDiagramSVG(svg)`: valida el SVG que llega por el puente `diagramClick` (ver `CLAUDE.md`, *Seguridad*).

---

## Etapa 2: `HTMLTemplate.build()` — documento HTML completo

El fragmento HTML del renderer se inserta en:

```html
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="utf-8">
  <!-- head: la Content-Security-Policy (HTMLTemplate.appHead en la app, la suya en la Vista Rápida) -->
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>/* CSS completo embebido */</style>
</head>
<body>
  <article class="markdown-body">
    <!-- FRAGMENTO DEL RENDERER -->
  </article>
  <script src="highlight.min.js"></script>
  <script>hljs.highlightAll();</script>
  <script src="mermaid.min.js"></script>
  <script>/* init mermaid + handler de clic para abrir en ventana */</script>
  <script>/* lectorNorm, lectorSearch, lectorSearchNext, lectorSearchPrev */</script>
</body>
</html>
```

---

## CSS — sistema de colores

Variables CSS en `:root` para tema claro, sobreescritas en `@media (prefers-color-scheme: dark)`:

| Variable | Claro | Oscuro |
|---|---|---|
| `--bg` | `#ffffff` | `#0d1117` |
| `--surface` | `#f6f8fa` | `#161b22` |
| `--border` | `#d0d7de` | `#30363d` |
| `--text` | `#1f2328` | `#e6edf3` |
| `--text-muted` | `#656d76` | `#7d8590` |
| `--heading` | `#1f2328` | `#e6edf3` |
| `--link` | `#0969da` | `#58a6ff` |
| `--code-fg` | `#cf222e` | `#ff7b72` |
| `--blockquote-border` | `#0969da` | `#388bfd` |

Fuentes: `--font-body` = sistema (-apple-system…), `--font-mono` = SFMono, Menlo, Consolas…

Layout principal: `.markdown-body { max-width: 800px; margin: 0 auto; padding: 40px 32px 96px; }`

---

## Highlight.js

Se incluye `highlight.min.js` como archivo local. Se inicializa con `hljs.highlightAll()` después de cargar el DOM. Los temas GitHub Light / GitHub Dark están embebidos como CSS inline (no como archivo separado), activados con `@media (prefers-color-scheme: dark)`.

El bloque `<pre>` da el fondo y padding; se anula el fondo que hljs pondría en `pre code.hljs` con `background: transparent; padding: 0`.

---

## Mermaid.js

Se incluye `mermaid.min.js` como archivo local. Configuración:

```js
mermaid.initialize({
  startOnLoad: true,
  securityLevel: 'strict',  // el default de Mermaid: sanea el SVG y los links, y apaga `click … call`
  theme: 'default'  // o 'dark'
});
```

El tema se pasa en el momento de build del HTML (no cambia dinámicamente con el sistema operativo). Un `MutationObserver` detecta cuando Mermaid renderiza el SVG y añade un `click` handler al `<div class="mermaid">` para exponer el SVG al sistema nativo (en web esto puede adaptarse a abrir en modal/nueva pestaña).

---

## Sistema de búsqueda en JS

Tres funciones globales: `lectorSearch(q)`, `lectorSearchNext()`, `lectorSearchPrev()`.

### `lectorNorm(str)` — normalización diacrática

```js
function lectorNorm(str) {
  var r = '';
  for (var i = 0; i < str.length; i++) {
    r += str[i].normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
  }
  return r;
}
```

**Por qué char a char**: al normalizar de a 1 carácter, el largo del resultado == largo del input. Esto garantiza que los índices en el string normalizado coinciden exactamente con el string original, permitiendo extraer el substring con su ortografía real (con tildes) para mostrarlo en el `<mark>`.

### `lectorSearch(q)`

1. Elimina todos los `<mark class="lector-hit">` previos (reemplazándolos por nodos de texto) y llama `normalize()` para fundir text nodes adyacentes.
2. Crea un `TreeWalker` de nodos de texto dentro de `.markdown-body`.
3. Para cada nodo: normaliza su contenido con `lectorNorm()`, busca la query normalizada con `indexOf`.
4. Para cada match: crea un `<mark class="lector-hit">` con el texto **original** (no normalizado) usando los mismos índices (que coinciden por la propiedad del paso char-a-char).
5. El primer hit recibe además `lector-hit-current` y hace scroll a él.
6. Retorna el conteo total de hits.

### `lectorSearchNext()` / `lectorSearchPrev()`

- Leen todos los `mark.lector-hit` actuales.
- Quitan `lector-hit-current` del hit actual, avanzan/retroceden el índice con módulo, añaden la clase al nuevo hit y hacen scroll.
- Retornan `[posición_actual, total]` (1-based).

### Clases CSS de búsqueda

```css
mark.lector-hit         { background-color: #ffeb3b; color: inherit; border-radius: 2px; padding: 0 1px; }
mark.lector-hit-current { background-color: #ff9800; color: #000; }

/* Dark mode */
mark.lector-hit         { background-color: #5c4a00; color: #ffd54f; }
mark.lector-hit-current { background-color: #a06000; color: #ffe082; }
```

---

## Adaptación para web

Para implementar en una página web, los cambios respecto a la app macOS son:

1. **El renderer** puede reescribirse en JavaScript siguiendo exactamente la misma lógica (o portarse a TypeScript). La lógica de bloques e inline es pura manipulación de strings.
2. **Highlight.js y Mermaid.js**: usar desde CDN o npm en lugar de archivos locales.
3. **Tema Mermaid**: leer `window.matchMedia('(prefers-color-scheme: dark)').matches` en tiempo de render para pasar `'dark'` o `'default'`.
4. **Click handler de Mermaid**: el `window.webkit.messageHandlers.diagramClick.postMessage(...)` es específico de WKWebView — reemplazarlo por un modal o `window.open` con el SVG.
5. **Búsqueda**: las funciones JS son reutilizables tal cual — no dependen de nada nativo.
