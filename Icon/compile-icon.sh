#!/bin/bash
# Compila Icon/Marquise.icon (claro, escuro, colorido e transparente) em Assets.car,
# o formato do macOS 26+. Precisa do Xcode; sem ele, o app fica só com o AppIcon.icns.
# Uso: Icon/compile-icon.sh <pasta Contents/Resources do app>
set -euo pipefail
cd "$(dirname "$0")/.."
RESOURCES="$1"

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
if ! xcrun --find actool >/dev/null 2>&1; then
    echo "Aviso: Xcode não encontrado; o ícone não vai trocar no modo escuro"
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
xcrun actool Icon/Marquise.icon --compile "$TMP" --platform macosx --minimum-deployment-target 14.0 \
    --app-icon Marquise --output-partial-info-plist "$TMP/partial.plist" \
    --output-format human-readable-text --errors >/dev/null
# Só o Assets.car: em macOS mais antigos vale o AppIcon.icns, desenhado para o formato antigo.
cp "$TMP/Assets.car" "$RESOURCES/Assets.car"
echo "Ícone claro/escuro compilado"
