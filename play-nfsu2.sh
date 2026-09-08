#!/usr/bin/env bash
# Run NFS Underground 2 from a compressed archive, extracted into RAM.
#
#   ./play-nfsu2.sh [/path/to/nfsu2.tar.xz]
#
# Extracts to /dev/shm (tmpfs = RAM, no root needed), launches under Wine,
# and clears the RAM copy on exit.
set -euo pipefail

ARCHIVE="${1:-$(dirname "$(readlink -f "$0")")/nfsu2.tar.xz}"
RAMDIR="/dev/shm/nfsu2"

[ -f "$ARCHIVE" ] || { echo "archive not found: $ARCHIVE" >&2; exit 1; }

need=$(( $(stat -c%s "$ARCHIVE") / 1048576 * 4 + 128 ))   # ~4x archive + headroom
avail=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
if [ "$avail" -lt "$need" ]; then
  echo "not enough free RAM: need ~${need} MiB, have ${avail} MiB" >&2; exit 1
fi

cleanup() { rm -rf "$RAMDIR"; }
trap cleanup EXIT INT TERM

rm -rf "$RAMDIR"; mkdir -p "$RAMDIR"
echo "extracting $(du -h "$ARCHIVE" | cut -f1) into RAM..."
tar -xf "$ARCHIVE" -C "$RAMDIR"
echo "extracted $(du -sh "$RAMDIR" | cut -f1); starting..."

cd "$RAMDIR"
wine SPEED2.EXE "${@:2}"
