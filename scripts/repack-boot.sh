#!/usr/bin/env bash
# Reempaqueta boot.img conservando ramdisk + DTB originales.
#
#   ./scripts/repack-boot.sh <dir_desempaquetado> <salida.img> [kernel]
#
# <dir_desempaquetado> es la salida de:
#   unpack_bootimg --boot_img boot.img --out boot_unpacked
set -euo pipefail

UNPACKED="${1:?falta directorio desempaquetado}"
OUT="${2:?falta imagen de salida}"
KERNEL="${3:-$UNPACKED/kernel}"

[ -f "$KERNEL" ]          || { echo "falta kernel: $KERNEL" >&2; exit 1; }
[ -f "$UNPACKED/ramdisk" ] || { echo "falta ramdisk" >&2; exit 1; }
command -v mkbootimg >/dev/null || { echo "falta mkbootimg" >&2; exit 1; }

DTB=()
[ -f "$UNPACKED/dtb" ] && DTB=(--dtb "$UNPACKED/dtb")

mkbootimg \
  --kernel "$KERNEL" \
  --ramdisk "$UNPACKED/ramdisk" \
  "${DTB[@]}" \
  --header_version 2 \
  --pagesize 2048 \
  --base 0x40078000 \
  --kernel_offset 0x00008000 \
  --ramdisk_offset 0x11088000 \
  --tags_offset 0x07c08000 \
  --dtb_offset 0x07c08000 \
  --cmdline "bootopt=64S3,32N2,64N2 androidboot.tee_type=2" \
  --os_version 17.0.0 \
  --os_patch_level 2026-10 \
  --output "$OUT"

echo "boot.img: $OUT"
unpack_bootimg --boot_img "$OUT" --out "$(mktemp -d)" 2>/dev/null | head -20 || true
