#!/usr/bin/env bash
# strip-nfsu2.sh - shrink a stock NFS Underground 2 install so it compresses
# under ~120 MB, while keeping the game playable.
#
#   ./strip-nfsu2.sh [/path/to/install]      (default: script's directory)
#
# Method: assets are EMPTIED to 0 bytes, not deleted, wherever the engine
# might still look them up. Files are only deleted when SPEED2.EXE contains
# no reference to them at all. Run once on a stock install; it is idempotent.
set -euo pipefail
GAME="${1:-$(dirname "$(readlink -f "$0")")}"
cd "$GAME"
[ -f SPEED2.EXE ] || { echo "not an NFSU2 install: $GAME" >&2; exit 1; }

# --- configuration -----------------------------------------------------------
# Playable cars to KEEP. Everything else is emptied. 350Z is Rachel's car.
KEEP_CARS="350Z 240SX CELICA CIVIC COROLLA CORSA FOCUS IS300 MIATA PEUGOT PEUGOT106 SENTRA SUPRA TIBURON"
KEEP_REGION="A"          # world region to keep (A = City Core, where you start)
# -----------------------------------------------------------------------------

ALL_CARS="PEUGOT FOCUS COROLLA 240SX MIATA CIVIC PEUGOT106 CORSA HUMMER NAVIGATOR
ESCALADE TIBURON SENTRA CELICA IS300 SUPRA GOLF A3 RSX ECLIPSE TT RX8 350Z G35
3000GT GTO MUSTANGGT SKYLINE LANCEREVO8 RX7 IMPREZAWRX"
BODY_PARTS="SPOILER SPOILER_SUV SPOILER_HATCH ROOF MIRRORS_BODY MIRRORS_SUV MIRRORS_HUMMER MIRRORS_POST"
ALL_REGIONS="A B C D F G H R"

empty() { if [ -f "$1" ] && [ -s "$1" ]; then : > "$1"; fi; }
say()   { printf '  %-46s %s\n' "$1" "$2"; }
before=$(du -sb --exclude=.git . | cut -f1)

echo "== 1. pre-rendered videos =="
# EA ships blank.vp6, a valid 1s VP6 stream. Reuse it so the decoder never
# sees an empty file and every filename still resolves.
if [ -f MOVIES/blank.vp6 ]; then
  n=0; for f in MOVIES/*.vp6; do
    [ "$(basename "$f")" = blank.vp6 ] && continue
    cmp -s MOVIES/blank.vp6 "$f" || { cp -f MOVIES/blank.vp6 "$f"; n=$((n+1)); }
  done; say "MOVIES/*.vp6 -> blank.vp6" "$n files"
fi

echo "== 2. text assets =="
# CREDITS is read as UTF-16LE via the literal path CREDITS\<LANG>.TXT.
if [ -d CREDITS ]; then
  { printf '\xff\xfe'; printf 'Need for Speed Underground 2\r\n\r\nElectronic Arts - Black Box\r\n' | iconv -f UTF-8 -t UTF-16LE; } > /tmp/.credstub.$$
  n=0; for f in CREDITS/*.TXT; do cmp -s /tmp/.credstub.$$ "$f" || { cp -f /tmp/.credstub.$$ "$f"; n=$((n+1)); }; done
  rm -f /tmp/.credstub.$$; say "CREDITS/*.TXT -> minimal UTF-16LE" "$n files"
fi
# SUBTITLES: Scene20 ships as an 8-byte empty table (ffff terminator).
if [ -f SUBTITLES/Scene20 ]; then
  cp SUBTITLES/Scene20 /tmp/.substub.$$
  n=0; for f in SUBTITLES/*; do cmp -s /tmp/.substub.$$ "$f" || { cp -f /tmp/.substub.$$ "$f"; n=$((n+1)); }; done
  rm -f /tmp/.substub.$$; say "SUBTITLES/* -> empty table" "$n files"
fi

echo "== 3. unreferenced files (safe to delete) =="
for f in unins000.exe unins000.dat elamigos.jpg; do
  [ -e "$f" ] && { rm -f "$f"; say "deleted $f" ""; }
done
[ -d Support ] && { rm -rf Support; say "deleted Support/" "EA help, registration, uninstaller"; }

echo "== 4. music and speech (sdat.viv) =="
# Rebuild as a structurally valid BIG4 archive with the bulk audio payloads
# emptied. All 10 entries keep their names, order and descriptor content.
if [ -f SDATA/sdat.viv ] && [ "$(stat -c%s SDATA/sdat.viv)" -gt 1000000 ]; then
python3 - <<'PY'
import struct
p='SDATA/sdat.viv'; d=open(p,'rb').read()
total,n,hdr=struct.unpack_from('>III',d,4); off=16; ent=[]
for _ in range(n):
    o,s=struct.unpack_from('>II',d,off); off+=8
    e=d.index(b'\0',off); ent.append((d[off:e].decode(),o,s)); off=e+1
STRIP={'pfdata/MusicSFx.mus','speech/UG2_Speech_GR.big','speech/nisaudio.big'}
new=[(nm, b'' if nm in STRIP else d[o:o+s]) for nm,o,s in ent]
hs=16+sum(8+len(nm)+1 for nm,_ in new); hs=(hs+15)//16*16
body=bytearray(); offs=[]; cur=hs
for nm,data in new:
    offs.append(cur if data else 0); body+=data; cur+=len(data)
    while cur%16: body+=b'\0'; cur+=1
out=bytearray(b'BIG4'); out+=struct.pack('>III',hs+len(body),len(new),hs)
for (nm,data),o in zip(new,offs): out+=struct.pack('>II',o,len(data))+nm.encode()+b'\0'
out+=b'\0'*(hs-len(out)); out+=body
open(p,'wb').write(out)
PY
  say "SDATA/sdat.viv rebuilt" "$(stat -c%s SDATA/sdat.viv) bytes"
fi

echo "== 5. cars =="
n=0; for f in CARS/*/VINYLS.BIN; do [ -s "$f" ] && { : > "$f"; n=$((n+1)); }; done
say "VINYLS.BIN emptied" "$n files"
n=0; for c in $ALL_CARS; do
  case " $KEEP_CARS " in *" $c "*) continue;; esac
  for f in GEOMETRY.BIN TEXTURES.BIN; do
    if [ -s "CARS/$c/$f" ]; then : > "CARS/$c/$f"; n=$((n+1)); fi
  done
done
say "unused player cars emptied" "$n files"
n=0; for d in $BODY_PARTS; do [ -s "CARS/$d/GEOMETRY.BIN" ] && { : > "CARS/$d/GEOMETRY.BIN"; n=$((n+1)); }; done
say "body parts emptied" "$n (spoilers, roofs, mirrors)"

echo "== 6. world =="
n=0; for r in $ALL_REGIONS; do
  [ "$r" = "$KEEP_REGION" ] && continue
  empty "TRACKS/STREAML4R$r.BUN"
  for f in TRACKS/ROUTESL4R$r/*; do empty "$f"; done
  n=$((n+1))
done
say "regions emptied" "$n of 8 (kept L4R$KEEP_REGION)"
n=0; for f in TRACKS/TRACKMAP*.BIN; do [ -s "$f" ] && { : > "$f"; n=$((n+1)); }; done
say "TRACKMAP minimaps emptied" "$n files"

echo "== 7. cutscenes =="
n=0; for f in NIS/Scene_IntroNis*_BundleB.bun NIS/Scene_EndingNis*_BundleB.bun; do
  [ -s "$f" ] && { : > "$f"; n=$((n+1)); }
done
say "story bundles emptied" "$n (shop/dyno/showcase kept)"

after=$(du -sb --exclude=.git . | cut -f1)
printf '\ndone: %.1f MiB -> %.1f MiB\n' \
  "$(echo "$before"|awk '{print $1/1048576}')" "$(echo "$after"|awk '{print $1/1048576}')"
echo "next: ./build-archive.sh   then   ./play-nfsu2.sh"
