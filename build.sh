#!/usr/bin/env bash
# build.sh — compila LectorMD.app desde fuentes Swift (sin Xcode)
set -euo pipefail

# ── colores ──────────────────────────────────────────────────────────────────
GRN='\033[0;32m'; YEL='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
log()  { echo -e "${GRN}==> $1${NC}"; }
warn() { echo -e "${YEL}⚠  $1${NC}"; }
die()  { echo -e "${RED}✗  $1${NC}" >&2; exit 1; }

# ── configuración ─────────────────────────────────────────────────────────────
APP_NAME="LectorMD"
BUNDLE_ID="com.lectormd.app"
QL_NAME="LectorMDQL"
QL_BUNDLE_ID="com.lectormd.app.qlextension"
VERSION="1.0"
MACOS_MIN="13.0"
ARCH=$(uname -m)                            # arm64 o x86_64
TARGET="${ARCH}-apple-macosx${MACOS_MIN}"
SDK=$(xcrun --show-sdk-path --sdk macosx 2>/dev/null) \
  || die "SDK de macOS no encontrado. Ejecutá: xcode-select --install"

BUILD_DIR=".build"
APP="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS_BIN="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
QL_BUNDLE="$CONTENTS/PlugIns/$QL_NAME.appex"
QL_MACOS="$QL_BUNDLE/Contents/MacOS"
QL_RESOURCES="$QL_BUNDLE/Contents/Resources"

SOURCES=(
  LectorMD/LectorMDApp.swift
  LectorMD/MarkdownDocument.swift
  LectorMD/ContentView.swift
  LectorMD/MarkdownWebView.swift
  LectorMD/MarkdownRenderer.swift
  LectorMD/HTMLTemplate.swift
)

# ── 1. bundle skeleton ────────────────────────────────────────────────────────
log "Preparando bundle..."
rm -rf "$APP"
mkdir -p "$MACOS_BIN" "$RESOURCES" "$QL_MACOS" "$QL_RESOURCES"

# ── 2. ícono ─────────────────────────────────────────────────────────────────
CACHED_ICNS="$BUILD_DIR/AppIcon.icns"
ICON_BIN="$BUILD_DIR/make_icon_bin"

# Recompilar el generador solo si make_icon.swift cambió
if [ ! -f "$ICON_BIN" ] || [ "make_icon.swift" -nt "$ICON_BIN" ]; then
    log "Compilando generador de ícono..."
    swiftc -sdk "$SDK" -target "$TARGET" -framework Cocoa \
        make_icon.swift -o "$ICON_BIN"
fi

# Regenerar el .icns solo si no existe o si el script cambió
if [ ! -f "$CACHED_ICNS" ] || [ "make_icon.swift" -nt "$CACHED_ICNS" ]; then
    log "Generando ícono..."
    "$ICON_BIN" "$CACHED_ICNS"
fi

cp "$CACHED_ICNS" "$RESOURCES/AppIcon.icns"
cp LectorMD/Resources/mermaid.min.js "$RESOURCES/"
cp LectorMD/Resources/highlight.min.js "$RESOURCES/"

# ── Quick Look UI Extension (.appex) ─────────────────────────────────────────
log "Compilando Quick Look Extension..."
swiftc \
  -sdk "$SDK" \
  -target "$TARGET" \
  -parse-as-library \
  -module-name "$QL_NAME" \
  -framework Cocoa \
  -framework QuickLookUI \
  -framework WebKit \
  -Xlinker -e -Xlinker _NSExtensionMain \
  QuickLookMD/PreviewViewController.swift \
  LectorMD/MarkdownRenderer.swift \
  LectorMD/HTMLTemplate.swift \
  -o "$QL_MACOS/$QL_NAME"

cp LectorMD/Resources/highlight.min.js "$QL_RESOURCES/"
cp LectorMD/Resources/mermaid.min.js   "$QL_RESOURCES/"

cat > "$QL_BUNDLE/Contents/Info.plist" <<QLPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>  <string>en</string>
    <key>CFBundleExecutable</key>         <string>${QL_NAME}</string>
    <key>CFBundleIdentifier</key>         <string>${QL_BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
    <key>CFBundleName</key>               <string>${QL_NAME}</string>
    <key>CFBundlePackageType</key>        <string>XPC!</string>
    <key>CFBundleShortVersionString</key> <string>${VERSION}</string>
    <key>CFBundleVersion</key>            <string>1</string>
    <key>NSExtension</key>
    <dict>
        <key>NSExtensionPointIdentifier</key>
        <string>com.apple.quicklook-ui-extension</string>
        <key>NSExtensionPrincipalClass</key>
        <string>PreviewViewController</string>
        <key>NSExtensionAttributes</key>
        <dict>
            <key>QLSupportedContentTypes</key>
            <array>
                <string>net.daringfireball.markdown</string>
            </array>
            <key>QLSupportsSearchableItems</key>
            <false/>
        </dict>
    </dict>
</dict>
</plist>
QLPLIST

# ── 3. compilar Swift ─────────────────────────────────────────────────────────
log "Compilando (target: $TARGET)..."
swiftc \
  -sdk "$SDK" \
  -target "$TARGET" \
  -parse-as-library \
  -module-name "$APP_NAME" \
  -framework SwiftUI \
  -framework WebKit \
  -framework AppKit \
  -framework Foundation \
  -framework UniformTypeIdentifiers \
  "${SOURCES[@]}" \
  -o "$MACOS_BIN/$APP_NAME"

# ── 3. Info.plist (sin variables de Xcode) ───────────────────────────────────
log "Escribiendo Info.plist..."
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>      <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>      <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>            <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>     <string>LectorMD</string>
    <key>CFBundleVersion</key>         <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key> <string>${VERSION}</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key> <string>6.0</string>
    <key>CFBundleDevelopmentRegion</key> <string>en</string>
    <key>LSMinimumSystemVersion</key>  <string>${MACOS_MIN}</string>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>

    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key>   <string>Markdown Document</string>
            <key>CFBundleTypeRole</key>   <string>Viewer</string>
            <key>LSHandlerRank</key>      <string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>net.daringfireball.markdown</string>
            </array>
        </dict>
    </array>

    <key>UTImportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key>    <string>net.daringfireball.markdown</string>
            <key>UTTypeDescription</key>   <string>Markdown Document</string>
            <key>UTTypeConformsTo</key>
            <array>
                <string>public.text</string>
                <string>public.plain-text</string>
            </array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array>
                    <string>md</string>
                    <string>markdown</string>
                    <string>mdown</string>
                    <string>mkd</string>
                </array>
                <key>public.mime-type</key> <string>text/markdown</string>
            </dict>
        </dict>
    </array>
</dict>
</plist>
PLIST

# PkgInfo requerido por macOS
printf 'APPL????' > "$CONTENTS/PkgInfo"

# ── 4. firma ad-hoc (sin sandbox — WKWebView no arranca con sandbox + firma ad-hoc) ──
log "Firmando (ad-hoc, sin sandbox)..."
codesign --force --deep --sign - "$APP" 2>&1 | grep -v "^$" || true

# ── 5. registrar con Launch Services (app + QL generator) ────────────────────
log "Registrando con Launch Services..."
LS_REGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LS_REGISTER" -f "$APP" 2>/dev/null || warn "lsregister falló (el doble click puede requerir reinstalación manual)"

# Reiniciar el daemon de Quick Look para que detecte el nuevo plugin
qlmanage -r 2>/dev/null || true
qlmanage -r cache 2>/dev/null || true

# ── 6. quitar cuarentena (permite ejecutar sin aviso de Gatekeeper) ───────────
xattr -rd com.apple.quarantine "$APP" 2>/dev/null || true

# Si está instalada en ~/Applications, actualizar (rm primero para no anidar)
INSTALLED="$HOME/Applications/$APP_NAME.app"
if [ -d "$INSTALLED" ]; then
    rm -rf "$INSTALLED"
    cp -R "$APP" "$INSTALLED"
    xattr -rd com.apple.quarantine "$INSTALLED" 2>/dev/null || true
    "$LS_REGISTER" -f "$INSTALLED" 2>/dev/null || true
    qlmanage -r 2>/dev/null || true
fi

# ── 7. archivo de prueba ─────────────────────────────────────────────────────
TEST_MD="$BUILD_DIR/prueba.md"
cat > "$TEST_MD" <<'MDEOF'
# LectorMD

Visualizador nativo de Markdown para macOS.

## Texto

Párrafo con **negrita**, _cursiva_, ~~tachado~~ e `código inline`.

## Código

```swift
func saludo(_ nombre: String) -> String {
    return "Hola, \(nombre)!"
}
```

## Lista de tareas

- [x] Compilar sin Xcode
- [x] Modo oscuro automático
- [ ] Agregar ícono personalizado

## Tabla

| Elemento   | Soporte |
|------------|---------|
| Headings   | ✓       |
| Tablas     | ✓       |
| Task lists | ✓       |

> Una cita de bloque para ver el estilo.

---

[Más sobre Markdown](https://daringfireball.net/projects/markdown/)
MDEOF

# ── listo ─────────────────────────────────────────────────────────────────────
ABS_APP="$(pwd)/$APP"

echo ""
echo -e "${GRN}✓ Build exitoso:${NC} $ABS_APP"
echo ""

# Abrir el archivo de prueba directamente
log "Abriendo archivo de prueba..."
open -a "$ABS_APP" "$TEST_MD"

echo ""
echo "  Abrir cualquier archivo:  open -a \"$ABS_APP\" archivo.md"
echo ""
echo "  Para doble-click en Finder:"
echo "  1. Copiá la app a ~/Applications/"
echo "  2. Click derecho en un .md → 'Abrir con' → LectorMD"
