#!/usr/bin/env bash
# Extrae la receta del kernel 6.6 desde un release de RubyxLabs.
#
#   ./scripts/extract-release.sh [tag] [directorio_salida]
#
# Requiere: curl o gh, aria2c (opcional), jq, unzip, payload-dumper-go,
# unpack_bootimg, extract-dtb, dtc, erofs-utils, kmod, python3,
# extract-ikconfig y (opcional) kallsyms-finder.
set -euo pipefail

TAG="${1:-rubyx-20261015}"
OUT="${2:-work/blueprint}"
REPO="RubyxLabs/releases"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/ruby-extract.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$OUT"/{boot,config,dts,dtbo_dts,modules,symbols}
log() { printf '[extract] %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- descarga
log "release $REPO@$TAG"
if have gh && gh auth status >/dev/null 2>&1; then
  gh api "repos/$REPO/releases/tags/$TAG" --jq '.assets[] | [.name,.browser_download_url] | @tsv' \
    > "$WORK/assets.tsv"
else
  curl -fsSL "https://api.github.com/repos/$REPO/releases/tags/$TAG" \
    | jq -r '.assets[] | [.name,.browser_download_url] | @tsv' > "$WORK/assets.tsv"
fi
[ -s "$WORK/assets.tsv" ] || { log "release sin assets"; exit 1; }

mkdir -p "$WORK/assets"
while IFS=$'\t' read -r name url; do
  [ -n "$name" ] || continue
  case "$name" in
    boot.img|dtbo.img|vendor_boot.img|vendor_dlkm.img|*.zip) ;;
    *) continue ;;
  esac
  log "descargando $name"
  if have aria2c; then
    aria2c -q -x16 -s16 -k1M -c -d "$WORK/assets" -o "$name" "$url"
  else
    curl -fL --retry 5 -C - -o "$WORK/assets/$name" "$url"
  fi
done < "$WORK/assets.tsv"

# ------------------------------------------------------- payload / particiones
PAYLOAD=""
for z in "$WORK"/assets/*.zip; do
  [ -f "$z" ] || continue
  if unzip -l "$z" 2>/dev/null | grep -q 'payload.bin'; then
    log "extrayendo payload.bin de $(basename "$z")"
    unzip -oq "$z" payload.bin -d "$WORK"
    PAYLOAD="$WORK/payload.bin"
    break
  fi
done

if [ -n "$PAYLOAD" ] && have payload-dumper-go; then
  mapfile -t PARTS < <(payload-dumper-go -l "$PAYLOAD" | tr '\n' ' ' \
    | sed 's/.*Found partitions:[[:space:]]*//' | tr ',' '\n' \
    | sed -E 's/^ *([a-z0-9_]+).*/\1/' | grep -v '^$')
  log "particiones: ${PARTS[*]:-?}"
  SELECT=""
  for p in boot dtbo vendor vendor_boot vendor_dlkm system_dlkm; do
    printf '%s\n' "${PARTS[@]}" | grep -qx "$p" && SELECT="${SELECT:+$SELECT,}$p"
  done
  [ -n "$SELECT" ] || { log "no hay particiones conocidas en el payload"; exit 1; }
  payload-dumper-go -p "$SELECT" -o "$WORK/parts" "$PAYLOAD" >/dev/null
elif [ -n "$PAYLOAD" ]; then
  log "FALTA payload-dumper-go"; exit 1
fi

for name in boot dtbo vendor vendor_boot vendor_dlkm; do
  [ -f "$WORK/assets/$name.img" ] && cp "$WORK/assets/$name.img" "$WORK/parts/$name.img" 2>/dev/null || true
done
if [ "${KEEP_IMAGES:-0}" = 1 ]; then
  for name in boot dtbo vendor_boot vendor_dlkm; do
    [ -f "$WORK/parts/$name.img" ] && cp "$WORK/parts/$name.img" "$OUT/" || true
  done
fi

# ----------------------------------------------------------------- boot.img
if [ -f "$WORK/parts/boot.img" ] && have unpack_bootimg; then
  unpack_bootimg --boot_img "$WORK/parts/boot.img" --out "$WORK/boot" \
    > "$OUT/boot/header.txt"
  cp -a "$WORK/boot" "$OUT/boot/unpacked"
  log "boot: $(ls "$WORK/boot")"
else
  log "sin boot.img o sin unpack_bootimg; se omite kernel/config"
fi

KERNEL_RAW=""
if [ -f "$WORK/boot/kernel" ]; then
  case "$(file -b "$WORK/boot/kernel")" in
    *gzip*)   gzip -dc "$WORK/boot/kernel" > "$WORK/kernel.raw" ;;
    *LZ4*)    lz4  -dc "$WORK/boot/kernel" > "$WORK/kernel.raw" ;;
    *Zstandard*) zstd -dc "$WORK/boot/kernel" > "$WORK/kernel.raw" ;;
    *)        cp "$WORK/boot/kernel" "$WORK/kernel.raw" ;;
  esac
  KERNEL_RAW="$WORK/kernel.raw"
  cp "$KERNEL_RAW" "$OUT/boot/Image.raw"

  strings -a "$KERNEL_RAW" | grep -m1 -E '^Linux version [0-9]' \
    > "$OUT/config/kernel-version.txt" || true

  if [ ! -x "$WORK/extract-ikconfig" ]; then
    curl -fsSL https://raw.githubusercontent.com/torvalds/linux/master/scripts/extract-ikconfig \
      -o "$WORK/extract-ikconfig"; chmod +x "$WORK/extract-ikconfig"
  fi
  "$WORK/extract-ikconfig" "$KERNEL_RAW" > "$OUT/config/ruby_defconfig" 2>/dev/null || true
  [ -s "$OUT/config/ruby_defconfig" ] || log "AVISO: el kernel no expone IKCONFIG"

  if have kallsyms-finder; then
    kallsyms-finder "$KERNEL_RAW" > "$OUT/symbols/kallsyms.txt" 2>/dev/null || true
    gzip -9 -f "$OUT/symbols/kallsyms.txt" 2>/dev/null || true
  fi
fi

# ------------------------------------------------------------------- DTB/DTBO
if [ -f "$WORK/boot/dtb" ] && have extract-dtb; then
  extract-dtb "$WORK/boot/dtb" -o "$WORK/dtb" >/dev/null 2>&1 || true
  for f in "$WORK"/dtb/*.dtb; do
    [ -f "$f" ] || continue
    dtc -I dtb -O dts -o "$OUT/dts/$(basename "$f" .dtb).dts" "$f" 2>/dev/null || true
  done
fi

if [ -f "$WORK/parts/dtbo.img" ]; then
  python3 - "$WORK/parts/dtbo.img" "$OUT/dtbo_dts" <<'PY'
import struct, sys, os, subprocess
img, out = sys.argv[1], sys.argv[2]
d = open(img, 'rb').read()
if struct.unpack('>I', d[:4])[0] != 0xd7b7ab1e:
    sys.exit('dtbo: magic desconocido')
magic, total, hsize, esize, count, eoff, page, ver = struct.unpack('>8I', d[:32])
for i in range(count):
    e = eoff + i * esize
    sz, off = struct.unpack('>II', d[e:e+8])
    name = d[e+8:e+32].split(b'\0')[0].decode(errors='replace') or f'entry{i}'
    base = f'{i:02d}_{name}'
    dtb = f'{out}/{base}.dtb'
    open(dtb, 'wb').write(d[off:off+sz])
    subprocess.run(['dtc', '-I', 'dtb', '-O', 'dts', '-o', f'{out}/{base}.dts', dtb],
                   stderr=subprocess.DEVNULL, check=False)
    print(f'{base}: {sz} B')
PY
fi

# ------------------------------------------------------------------- módulos
MODDIR=""
if [ -d "$WORK/parts" ] && [ -f "$WORK/parts/vendor_dlkm.img" ] && have fsck.erofs; then
  mkdir -p "$WORK/vendor_dlkm"
  fsck.erofs --extract="$WORK/vendor_dlkm" "$WORK/parts/vendor_dlkm.img" >/dev/null 2>&1 || true
  MODDIR="$WORK/vendor_dlkm"
elif [ -f "$WORK/parts/vendor.img" ] && have fsck.erofs; then
  mkdir -p "$WORK/vendor"
  fsck.erofs --extract="$WORK/vendor" "$WORK/parts/vendor.img" >/dev/null 2>&1 || true
  MODDIR="$WORK/vendor"
fi

if [ -n "$MODDIR" ]; then
  find "$MODDIR" -name '*.ko' | sort > "$OUT/modules/ko_list.txt"
  : > "$OUT/modules/ko_details.txt"
  while read -r ko; do
    { echo "=== ${ko#"$MODDIR"/} ==="
      modinfo "$ko" 2>&1 | grep -E '^(filename|license|description|srcversion|depends|vermagic|name|alias):'
    } >> "$OUT/modules/ko_details.txt"
  done < "$OUT/modules/ko_list.txt"
  for f in modules.dep modules.softdep modules.alias modules.load; do
    find "$MODDIR" -name "$f" -exec cp {} "$OUT/modules/" \; 2>/dev/null || true
  done
  log "módulos: $(wc -l < "$OUT/modules/ko_list.txt")"
fi

# ------------------------------------------------------------------- resumen
{
  echo "tag: $TAG"
  echo "fecha: $(date -u +%FT%TZ)"
  if [ -s "$OUT/config/kernel-version.txt" ]; then
    cat "$OUT/config/kernel-version.txt"
  fi
  echo "defconfig: $(wc -l < "$OUT/config/ruby_defconfig" 2>/dev/null || echo 0) líneas"
  echo "ko: $(wc -l < "$OUT/modules/ko_list.txt" 2>/dev/null || echo 0)"
} > "$OUT/summary.txt"

log "listo: $OUT"
