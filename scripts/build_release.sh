#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# FindUX – Release-APK bauen
# ─────────────────────────────────────────────────────────────────────────────
# Schutzmassnahmen (laut SICHERHEITSKONZEPT):
#
#   --obfuscate          Dart-Klassennamen unkenntlich machen
#                        (aus QueryBuilder wird z.B. "a1")
#   --split-debug-info   Debug-Symbole LOKAL speichern (debug_info/)
#                        → Abstuerze symbolisieren ohne Quellcode-Leak
#
# ProGuard/R8 ist bereits in android/app/build.gradle aktiviert:
#   minifyEnabled true   → Kotlin/Java-Code verschleiern + optimieren
#   shrinkResources true → Ungenutzte Ressourcen entfernen
#
# WICHTIG:
#   • Den debug_info/-Ordner NIEMALS weitergeben oder ins Repo pushen!
#   • .gitignore schliesst debug_info/ bereits aus.
#   • Keystore-Daten in android/key.properties (ebenfalls in .gitignore).
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DEBUG_INFO_DIR="$PROJECT_ROOT/debug_info"

echo "╔══════════════════════════════════════════════════════════╗"
echo "║  FindUX Release-APK Builder                              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Projekt:     $PROJECT_ROOT"
echo "  Debug-Info:  $DEBUG_INFO_DIR"
echo ""

# Flutter-Version prüfen (Minimum: 3.41.8 für intl 0.20.2)
FLUTTER_VERSION=$(flutter --version --machine 2>/dev/null | grep -o '"frameworkVersion":"[^"]*"' | cut -d'"' -f4 || echo "unbekannt")
echo "  Flutter:     $FLUTTER_VERSION"
echo ""

# Debug-Info-Verzeichnis anlegen (falls nicht vorhanden)
mkdir -p "$DEBUG_INFO_DIR"

# Sauber bauen
echo "▶ flutter clean ..."
cd "$PROJECT_ROOT"
flutter clean

echo ""
echo "▶ flutter pub get ..."
flutter pub get

echo ""
echo "▶ flutter build apk --release --obfuscate ..."
flutter build apk \
  --release \
  --obfuscate \
  --split-debug-info="$DEBUG_INFO_DIR" \
  --target-platform android-arm,android-arm64,android-x64

APK_PATH="$PROJECT_ROOT/build/app/outputs/flutter-apk/app-release.apk"

echo ""
if [ -f "$APK_PATH" ]; then
  APK_SIZE=$(du -sh "$APK_PATH" | cut -f1)
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║  ✅  Build erfolgreich                                   ║"
  echo "╠══════════════════════════════════════════════════════════╣"
  echo "║  APK:  $APK_PATH"
  echo "║  Größe: $APK_SIZE"
  echo "║"
  echo "║  ⚠️  debug_info/ NICHT weitergeben (für Symbolisierung)  ║"
  echo "╚══════════════════════════════════════════════════════════╝"
else
  echo "❌ APK nicht gefunden — Build fehlgeschlagen."
  exit 1
fi
