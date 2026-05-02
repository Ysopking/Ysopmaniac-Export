#!/usr/bin/env bash
# FindUX — Crash-Symbolisierung
# Wandelt obfuszierten Flutter-Stacktrace in lesbare Namen um.
# Benoetigt: debug_info/ aus --split-debug-info=./debug_info
#
# Verwendung: bash scripts/symbolize_crash.sh <crash_stacktrace.txt>
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
DEBUG_INFO_DIR="$PROJECT_ROOT/debug_info"
CRASH_FILE="${1:-}"

echo "══════════════════════════════════════════════"
echo "  FindUX Crash Symbolizer"
echo "══════════════════════════════════════════════"

if [ -z "$CRASH_FILE" ]; then
  echo "Verwendung: bash scripts/symbolize_crash.sh <crash.txt>"
  exit 1
fi
if [ ! -f "$CRASH_FILE" ]; then
  echo "Datei nicht gefunden: $CRASH_FILE"; exit 1
fi
if [ ! -d "$DEBUG_INFO_DIR" ]; then
  echo "debug_info/ fehlt: $DEBUG_INFO_DIR"
  echo "Bitte mit --split-debug-info=./debug_info bauen."
  exit 1
fi

echo "  Crash:      $CRASH_FILE"
echo "  Debug-Info: $DEBUG_INFO_DIR"
echo ""
flutter symbolize --debug-info "$DEBUG_INFO_DIR" --input "$CRASH_FILE"
