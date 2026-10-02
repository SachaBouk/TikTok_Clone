#!/usr/bin/env bash
# Lint du Swift de l'app (ADR-041) : swift-format, fourni avec Xcode, réglé par `.swift-format` (4 espaces, 150 colonnes).
# En local comme en CI (.github/workflows/ios.yml). `--fix` reformate les fichiers au lieu de signaler les écarts.
set -euo pipefail

cd "$(dirname "$0")/.."
SOURCES=(TikTokClone TikTokCloneTests)

if [[ "${1:-}" == "--fix" ]]; then
  swift format --in-place --recursive --parallel "${SOURCES[@]}"
fi
# --strict : un avertissement fait échouer le lint.
swift format lint --strict --recursive --parallel "${SOURCES[@]}"
echo "Lint Swift : aucun écart."
