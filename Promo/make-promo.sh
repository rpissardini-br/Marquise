#!/bin/bash
# Gera o vídeo de divulgação da Marquise em cada idioma, na horizontal (1920×1080) e na
# vertical (1080×1920, para Reels, TikTok e Shorts). 30 qps, sem áudio.
# Uso: Promo/make-promo.sh [idiomas…]   (padrão: pt-BR en-US es)
# Os vídeos vão para dist/promo/. A compilação com -DPROMO fica em .build-promo e não vai no app.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release -Xswiftc -DPROMO --build-path .build-promo
BIN=.build-promo/release/Marquise
mkdir -p dist/promo

LANGS=("$@")
[ ${#LANGS[@]} -eq 0 ] && LANGS=(pt-BR en-US es)
for LANG_CODE in "${LANGS[@]}"; do
    "$BIN" --promo "dist/promo/Marquise-promo-$LANG_CODE.mp4" "$LANG_CODE"
    "$BIN" --promo "dist/promo/Marquise-promo-vertical-$LANG_CODE.mp4" "$LANG_CODE" --vertical
done
