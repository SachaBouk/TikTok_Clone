#!/usr/bin/env bash
# Tests de l'app iOS dans le simulateur, en local comme en CI (.github/workflows/ios.yml, ADR-033).
# Projet généré au préalable : `xcodegen generate`.
#
# xcodebuild reste parfois bloqué après une passe de tests terminée (piège rencontré en local). Le résultat
# est donc lu sur sa ligne de fin (« ** TEST SUCCEEDED ** » ou « ** TEST FAILED ** ») ; une fois cette ligne
# écrite, xcodebuild a GRACE_SECONDS pour se terminer, puis il est arrêté.
#
# Variables facultatives :
#   IOS_DESTINATION     simulateur (défaut : iPhone 18 Pro)
#   DERIVED_DATA_PATH   dossier de build (défaut : build/DerivedData)
#   SPM_DIR             dossier des paquets Swift clonés (défaut : celui de DERIVED_DATA_PATH), à mettre en cache
#   RESULT_BUNDLE_PATH  résultats détaillés .xcresult (défaut : build/TikTokClone.xcresult)
#   TEST_LOG            journal complet de xcodebuild (défaut : build/xcodebuild-test.log)
#   TEST_GRACE_SECONDS  délai laissé à xcodebuild après sa ligne de fin (défaut : 60)
set -euo pipefail

cd "$(dirname "$0")/.."
DESTINATION="${IOS_DESTINATION:-platform=iOS Simulator,name=iPhone 18 Pro}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-build/DerivedData}"
RESULT_BUNDLE_PATH="${RESULT_BUNDLE_PATH:-build/TikTokClone.xcresult}"
TEST_LOG="${TEST_LOG:-build/xcodebuild-test.log}"
GRACE_SECONDS="${TEST_GRACE_SECONDS:-60}"
DONE_PATTERN='\*\* TEST (SUCCEEDED|FAILED) \*\*'

if [ ! -d TikTokClone.xcodeproj ]; then
  echo "TikTokClone.xcodeproj absent : lancer « xcodegen generate » dans apps/ios." >&2
  exit 1
fi

mkdir -p "$(dirname "$TEST_LOG")"
rm -rf "$RESULT_BUNDLE_PATH"
: > "$TEST_LOG"

args=(-project TikTokClone.xcodeproj -scheme TikTokClone -destination "$DESTINATION"
  -skipPackagePluginValidation -derivedDataPath "$DERIVED_DATA_PATH" -resultBundlePath "$RESULT_BUNDLE_PATH")
if [ -n "${SPM_DIR:-}" ]; then args+=(-clonedSourcePackagesDirPath "$SPM_DIR"); fi

xcodebuild "${args[@]}" test >> "$TEST_LOG" 2>&1 &
build_pid=$!

# Arrête xcodebuild et ses processus enfants.
stop_build() {
  pkill -TERM -P "$build_pid" 2>/dev/null || true
  kill "$build_pid" 2>/dev/null || true
}

# Affiche l'essentiel au fil de l'eau (erreurs, tests en échec, résumé) ; le journal complet reste dans TEST_LOG.
# `$!` désigne ici `tail` lui-même : l'arrêter ferme aussi le filtre. Aucun processus ne doit survivre au script,
# sinon l'étape de CI attendrait la fermeture de sa sortie.
tail -n +1 -f "$TEST_LOG" > >(grep --line-buffered -E "error:|✘|Test run with|\*\* (TEST|BUILD) ") &
tail_pid=$!
disown "$tail_pid"
trap 'kill "$tail_pid" 2>/dev/null || true; stop_build' EXIT

finished_at=""
while kill -0 "$build_pid" 2>/dev/null; do
  if [ -z "$finished_at" ] && grep -qE "$DONE_PATTERN" "$TEST_LOG"; then finished_at=$SECONDS; fi
  if [ -n "$finished_at" ] && [ $((SECONDS - finished_at)) -ge "$GRACE_SECONDS" ]; then
    echo "xcodebuild ne s'est pas terminé $GRACE_SECONDS s après la fin des tests : arrêté."
    stop_build
    break
  fi
  sleep 2
done
wait "$build_pid" 2>/dev/null && status=0 || status=$?
sleep 1
kill "$tail_pid" 2>/dev/null || true

if grep -q '\*\* TEST SUCCEEDED \*\*' "$TEST_LOG"; then
  echo "Tests iOS : succès."
  exit 0
fi
echo "Tests iOS : échec (code $status). Dernières lignes du journal ($TEST_LOG) :" >&2
tail -n 80 "$TEST_LOG" >&2
exit 1
