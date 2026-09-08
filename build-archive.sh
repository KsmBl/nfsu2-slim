#!/usr/bin/env bash
# Build the compressed archive that ships to the SD card.
#   ./build-archive.sh [output.tar.xz]
set -euo pipefail
OUT="${1:-nfsu2.tar.xz}"
cd "$(dirname "$(readlink -f "$0")")"
tar --exclude=.git --exclude="$OUT" --exclude=build-archive.sh -cf - . | xz -9e -T0 > "$OUT"
printf 'built %s: %s (from %s on disk)\n' "$OUT" "$(du -h "$OUT" | cut -f1)" "$(du -sh --exclude=.git . | cut -f1)"
