#!/bin/bash
# Gera os instaladores da Marquise para distribuição: .dmg (arrastar para Aplicativos) e .pkg (instalador).
#
# MODO TESTE (sem conta de desenvolvedor da Apple):
#   ./release.sh
#   Assina com o certificado local LOCAL_CERT (padrão "Ilha Local"). Serve para testar o instalador NESTE Mac;
#   em outros Macs o Gatekeeper bloqueia o app.
#
# MODO DISTRIBUIÇÃO (Apple Developer Program):
#   DEVELOPER_ID_APP="Developer ID Application: Seu Nome (TEAMID)" \
#   DEVELOPER_ID_INSTALLER="Developer ID Installer: Seu Nome (TEAMID)" \
#   NOTARY_PROFILE="marquise-notary" \
#   ./release.sh
#   Assina com Developer ID, envia para a Apple notarizar e "grampeia" o resultado,
#   para o app abrir sem avisos em qualquer Mac.
set -euo pipefail
cd "$(dirname "$0")"
# Sem arquivos "._" (metadados do Finder) dentro dos pacotes: eles podem invalidar a assinatura.
export COPYFILE_DISABLE=1
copy_clean() { ditto --norsrc --noextattr --noqtn "$1" "$2"; }

plist() { /usr/libexec/PlistBuddy -c "Print :$1" Info.plist; }
NAME="$(plist CFBundleName)"
EXECUTABLE="$(plist CFBundleExecutable)"
BUNDLE_ID="$(plist CFBundleIdentifier)"
VERSION="$(plist CFBundleShortVersionString)"

DIST="dist"
STAGE="$DIST/.stage"
APP="$STAGE/app/$NAME.app"
DMG="$DIST/$NAME-$VERSION.dmg"
PKG="$DIST/$NAME-$VERSION.pkg"

step() { printf "\n▸ %s\n" "$1"; }

# --- Assinaturas -------------------------------------------------------------
if [ -n "${DEVELOPER_ID_APP:-}" ]; then
    MODE="distribuição"
    APP_IDENTITY="$DEVELOPER_ID_APP"
    TIMESTAMP="--timestamp"  # a notarização exige carimbo de tempo da Apple
else
    MODE="teste local"
    APP_IDENTITY="$(security find-certificate -c "${LOCAL_CERT:-Ilha Local}" -Z 2>/dev/null | awk '/SHA-1 hash:/ {print $3; exit}')"
    APP_IDENTITY="${APP_IDENTITY:--}"  # sem o certificado local: assinatura ad-hoc
    TIMESTAMP="--timestamp=none"
fi
echo "$NAME $VERSION · modo: $MODE"

# --- 1. Compilar (Apple Silicon + Intel), sem símbolos de depuração ------------
step "Compilando versão universal"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$EXECUTABLE"

rm -rf "$STAGE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$DIST"
cp "$BIN" "$APP/Contents/MacOS/$EXECUTABLE"
strip -S -x "$APP/Contents/MacOS/$EXECUTABLE"
cp Info.plist "$APP/Contents/Info.plist"
cp -R Resources/*.lproj Resources/AppIcon.icns "$APP/Contents/Resources/"
echo "Arquiteturas: $(lipo -archs "$APP/Contents/MacOS/$EXECUTABLE")"
xattr -cr "$APP"

# --- 2. Assinar o app (hardened runtime + só as permissões necessárias) --------
step "Assinando o app"
codesign --force --options runtime --entitlements Marquise.entitlements $TIMESTAMP \
    --sign "$APP_IDENTITY" "$APP"
codesign --verify --strict --deep "$APP"
codesign -d -r- "$APP" 2>&1 | tail -1

# --- 3. .dmg: janela com o app e um atalho para Aplicativos --------------------
step "Criando $DMG"
DMG_ROOT="$STAGE/dmg"
mkdir -p "$DMG_ROOT"
copy_clean "$APP" "$DMG_ROOT/$NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "$NAME" -srcfolder "$DMG_ROOT" -fs HFS+ -format UDZO -ov "$DMG"
codesign --force $TIMESTAMP --sign "$APP_IDENTITY" "$DMG"
hdiutil verify -quiet "$DMG" && echo "Imagem íntegra"

# --- 4. .pkg: instala em /Applications ------------------------------------------
step "Criando $PKG"
PKG_ROOT="$STAGE/pkg-root"
mkdir -p "$PKG_ROOT"
copy_clean "$APP" "$PKG_ROOT/$NAME.app"
pkgbuild --analyze --root "$PKG_ROOT" "$STAGE/component.plist" >/dev/null
# Sempre instala em /Applications, mesmo que exista outra cópia do app em outro lugar.
/usr/libexec/PlistBuddy -c "Delete :0:BundleIsRelocatable" "$STAGE/component.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :0:BundleIsRelocatable bool false" "$STAGE/component.plist"
pkgbuild --quiet --root "$PKG_ROOT" --component-plist "$STAGE/component.plist" \
    --identifier "$BUNDLE_ID.pkg" --version "$VERSION" --install-location /Applications \
    "$STAGE/component.pkg"
rm -f "$PKG"
if [ -n "${DEVELOPER_ID_INSTALLER:-}" ]; then
    productbuild --quiet --package "$STAGE/component.pkg" --sign "$DEVELOPER_ID_INSTALLER" --timestamp "$PKG"
else
    # Instaladores só podem ser assinados com um certificado "Developer ID Installer" da Apple.
    productbuild --quiet --package "$STAGE/component.pkg" "$PKG"
    echo "Aviso: .pkg sem assinatura (falta DEVELOPER_ID_INSTALLER)"
fi

# --- 5. Notarização (Apple) -----------------------------------------------------
if [ -n "${NOTARY_PROFILE:-}" ]; then
    for file in "$DMG" "$PKG"; do
        step "Notarizando $file (pode levar alguns minutos)"
        xcrun notarytool submit "$file" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$file"
    done
else
    step "Notarização pulada (sem NOTARY_PROFILE)"
fi

# --- 6. Conferência do Gatekeeper e checksums -----------------------------------
step "Avaliação do Gatekeeper (como um Mac que baixou o arquivo)"
spctl --assess --type open --context context:primary-signature -v "$DMG" 2>&1 || true
spctl --assess --type install -v "$PKG" 2>&1 || true

(cd "$DIST" && shasum -a 256 "$(basename "$DMG")" "$(basename "$PKG")" > SHA256SUMS.txt)
rm -rf "$STAGE"
step "Pronto"
ls -lh "$DMG" "$PKG" "$DIST/SHA256SUMS.txt"
