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
  LectorMD/HTMLSafety.swift
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

# ── Quick Look Preview Extension (.appex) ────────────────────────────────────
log "Compilando Quick Look Extension..."
swiftc \
  -sdk "$SDK" \
  -target "$TARGET" \
  -parse-as-library \
  -module-name "$QL_NAME" \
  -framework Cocoa \
  -framework QuickLookUI \
  -framework WebKit \
  -application-extension \
  -Xlinker -e -Xlinker _NSExtensionMain \
  QuickLookMD/PreviewViewController.swift \
  LectorMD/MarkdownRenderer.swift \
  LectorMD/HTMLTemplate.swift \
  LectorMD/HTMLSafety.swift \
  -o "$QL_MACOS/$QL_NAME"

cp LectorMD/Resources/highlight.min.js "$QL_RESOURCES/"
cp LectorMD/Resources/mermaid.min.js   "$QL_RESOURCES/"

# Info.plist del .appex: una sola fuente (también la usa el proyecto Xcode)
cp QuickLookMD/ExtInfo.plist "$QL_BUNDLE/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$QL_BUNDLE/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$VERSION" "$QL_BUNDLE/Contents/Info.plist"
plutil -replace LSMinimumSystemVersion -string "$MACOS_MIN" "$QL_BUNDLE/Contents/Info.plist"

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
    <key>LSMultipleInstancesProhibited</key> <true/>

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

# ── 4. firma, de adentro hacia afuera (sin --deep) ───────────────────────────
# Identidad: SIGN_IDENTITY del entorno; si no, el certificado "Apple Development"
# del llavero (el gratuito de cualquier Apple ID); si no hay, ad-hoc.
SIGN_AUTO=0
if [ -z "${SIGN_IDENTITY:-}" ]; then
    SIGN_AUTO=1
    # Sin "exit" en awk: con pipefail, un SIGPIPE en security abortaría el script
    SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | awk '/"Apple Development: / && !found { print $2; found = 1 }') || true
    if [ -z "$SIGN_IDENTITY" ]; then
        SIGN_IDENTITY="-"
        warn "No hay certificado \"Apple Development\" en el llavero."
        warn "Para crearlo (gratis, con cualquier Apple ID): Xcode → Settings → Accounts →"
        warn "(tu Apple ID) → Manage Certificates → + → Apple Development."
    fi
fi
if [ "$SIGN_IDENTITY" = "-" ]; then
    warn "Firmando ad-hoc (sin TeamIdentifier). Si más adelante firmás con un certificado,"
    warn "macOS va a pedir una vez que confirmes el cambio de firma de la extensión."
else
    log "Identidad de firma: $(security find-identity -v -p codesigning 2>/dev/null | grep -F "$SIGN_IDENTITY" | sed -E 's/.*"(.*)"/\1/' | head -1 || true)"
fi

# Primero la extensión de Vista Rápida, con App Sandbox (sin sandbox PlugInKit la
# rechaza: "plug-ins must be sandbox"); después la app principal, sin sandbox.
sign_bundle() {
    log "Firmando extensión Quick Look (con sandbox)..."
    codesign --force --timestamp=none --sign "$1" \
        --entitlements QuickLookMD/LectorMDQL.entitlements "$QL_BUNDLE" || return 1
    log "Firmando app (sin sandbox)..."
    codesign --force --timestamp=none --sign "$1" "$APP" || return 1
}

if ! sign_bundle "$SIGN_IDENTITY"; then
    # p. ej. llavero bloqueado en una sesión SSH: el certificado aparece pero no se puede usar
    [ "$SIGN_AUTO" = 1 ] && [ "$SIGN_IDENTITY" != "-" ] || die "No se pudo firmar con \"$SIGN_IDENTITY\""
    warn "No se pudo firmar con el certificado (¿llavero bloqueado?). Firmando ad-hoc."
    SIGN_IDENTITY="-"
    sign_bundle - || die "No se pudo firmar ad-hoc"
fi

codesign --verify --strict --deep "$APP" || die "La firma no verifica"

# ── 5. quitar cuarentena (permite ejecutar sin aviso de Gatekeeper) ───────────
xattr -rd com.apple.quarantine "$APP" 2>/dev/null || true

# Si está instalada en ~/Applications, actualizar (rm primero para no anidar)
# y usar esa copia; si no, usar la de .build
LS_REGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
INSTALLED="$HOME/Applications/$APP_NAME.app"
RUN_APP="$(pwd)/$APP"
if [ -d "$INSTALLED" ]; then
    rm -rf "$INSTALLED"
    cp -R "$APP" "$INSTALLED"
    xattr -rd com.apple.quarantine "$INSTALLED" 2>/dev/null || true
    RUN_APP="$INSTALLED"
    # Una sola copia registrada: con dos .appex del mismo bundle id,
    # PlugInKit puede quedarse con la de .build
    pluginkit -r "$(pwd)/$QL_BUNDLE" 2>/dev/null || true
    "$LS_REGISTER" -u "$(pwd)/$APP" 2>/dev/null || true
fi

# ── 6. registrar app + extensión y reiniciar Vista Rápida ────────────────────
log "Registrando con Launch Services y PlugInKit..."
"$LS_REGISTER" -f "$RUN_APP" 2>/dev/null || warn "lsregister falló (el doble click puede requerir reinstalación manual)"
pluginkit -a "$RUN_APP/Contents/PlugIns/$QL_NAME.appex" 2>/dev/null || warn "pluginkit -a falló"

qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true

# "+" = activada, "-" = desactivada por el usuario, " " = default (activada)
QL_STATUS=$(pluginkit -m -p com.apple.quicklook.preview -i "$QL_BUNDLE_ID" 2>/dev/null || true)
if [ -z "$QL_STATUS" ]; then
    warn "La extensión de Vista Rápida no aparece en PlugInKit (ver README → Vista Rápida)"
elif [ "${QL_STATUS:0:1}" = "-" ]; then
    warn "La extensión de Vista Rápida está desactivada. Activala en Ajustes del Sistema →"
    warn "General → Ítems de inicio y extensiones → Vista rápida, o con:"
    warn "  pluginkit -e use -i $QL_BUNDLE_ID"
else
    log "Vista Rápida registrada: $(echo "$QL_STATUS" | xargs)"
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

## Diagrama

```mermaid
graph LR
    A[archivo.md] --> B(MarkdownRenderer)
    B --> C{HTMLTemplate}
    C --> D[LectorMD.app]
    C --> E[Vista Rápida]
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
echo ""
echo -e "${GRN}✓ Build exitoso:${NC} $RUN_APP"
echo ""

# Abrir el archivo de prueba directamente
log "Abriendo archivo de prueba..."
open -a "$RUN_APP" "$TEST_MD"

echo ""
echo "  Abrir cualquier archivo:  open -a \"$RUN_APP\" archivo.md"
echo "  Vista Rápida:             qlmanage -p $TEST_MD  (o barra espaciadora en Finder)"
echo ""
echo "  Para doble-click en Finder:"
echo "  1. Copiá la app a ~/Applications/"
echo "  2. Click derecho en un .md → 'Abrir con' → LectorMD"
