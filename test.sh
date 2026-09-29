#!/usr/bin/env bash
# test.sh — tests de seguridad (#5): escape del renderer, CSP y puente diagramClick.
# Compila Tests/SecurityTests.swift con las fuentes de la app y lo corre. Las pruebas de
# WebKit abren WKWebViews fuera de pantalla y un servidor propio en 127.0.0.1 (se apaga
# solo al terminar). También deja .build/ataque.md y .build/normal.md para probar a mano
# en la app y en la Vista Rápida (con un servidor en 127.0.0.1:8765, ver Tests/ataque.md).
set -euo pipefail

GRN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
die() { echo -e "${RED}✗  $1${NC}" >&2; exit 1; }

cd "$(dirname "$0")"
SDK=$(xcrun --show-sdk-path --sdk macosx 2>/dev/null) \
  || die "SDK de macOS no encontrado. Ejecutá: xcode-select --install"
TARGET="$(uname -m)-apple-macosx13.0"
OUT=".build/tests"
mkdir -p "$OUT"
cp Tests/ataque.md Tests/normal.md .build/

echo -e "${GRN}==> Compilando tests...${NC}"
swiftc \
  -sdk "$SDK" \
  -target "$TARGET" \
  -parse-as-library \
  -module-name LectorMDTests \
  -framework SwiftUI \
  -framework AppKit \
  -framework WebKit \
  -framework QuickLookUI \
  Tests/SecurityTests.swift \
  LectorMD/MarkdownDocument.swift \
  LectorMD/ContentView.swift \
  LectorMD/MarkdownWebView.swift \
  LectorMD/MarkdownRenderer.swift \
  LectorMD/HTMLTemplate.swift \
  LectorMD/HTMLSafety.swift \
  QuickLookMD/PreviewViewController.swift \
  -o "$OUT/LectorMDTests"

"$OUT/LectorMDTests" "$(pwd)"
