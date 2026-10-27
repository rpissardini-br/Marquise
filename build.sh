#!/bin/bash
# Compila a Marquise e monta build/Marquise.app (assinatura ad-hoc).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Marquise"

APP=build/Marquise.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Marquise"
cp Info.plist "$APP/Contents/Info.plist"
cp -R Resources/*.lproj Resources/AppIcon.icns "$APP/Contents/Resources/"
# Com um certificado local do Porta-chaves (LOCAL_CERT, padrão "Ilha Local") a assinatura é a mesma a cada compilação,
# então o macOS lembra das permissões (microfone, Automação…). Sem ele, assina ad-hoc.
LOCAL_CERT="${LOCAL_CERT:-Ilha Local}"
IDENTITY="$(security find-certificate -c "$LOCAL_CERT" -Z 2>/dev/null | awk '/SHA-1 hash:/ {print $3; exit}')"
# --options runtime = "hardened runtime" (proteção contra injeção de código), com só as
# permissões declaradas em Marquise.entitlements.
SIGN_FLAGS=(--force --options runtime --entitlements Marquise.entitlements)
if [ -n "$IDENTITY" ]; then
    codesign "${SIGN_FLAGS[@]}" --sign "$IDENTITY" "$APP"
    echo "Assinado com o certificado $LOCAL_CERT (hardened runtime)"
else
    codesign "${SIGN_FLAGS[@]}" --sign - "$APP"
    echo "Assinado ad-hoc (certificado $LOCAL_CERT não encontrado; hardened runtime)"
fi

echo "Pronto: $(pwd)/$APP"
