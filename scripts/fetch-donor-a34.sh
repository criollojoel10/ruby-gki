#!/usr/bin/env bash
# Clona en modo sparse el BSP MT6877 6.6 del Galaxy A34 y mide su cobertura
# frente a las opciones =y que le faltan a ruby.
#
#   ./scripts/fetch-donor-a34.sh [destino]
#
# No compila nada; solo descarga el árbol de drivers y calcula el gap.
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="${1:-work/a34-bsp}"
REPO=https://github.com/Fede2782/android_kernel_samsung_a34x
REF='sep-17.0/stock'

if [ ! -d "$DEST/.git" ]; then
  log() { printf '[donor] %s\n' "$*" >&2; }
  log "clonando $REPO ($REF), sparse"
  git clone --depth 1 --filter=blob:none --sparse -b "$REF" "$REPO" "$DEST"
  ( cd "$DEST" && git sparse-checkout set \
      kernel/kernel_device_modules-6.6 kernel-6.6/build.config.mtk.aarch64 )
fi

if [ -f "$DEST/kernel-6.6/Makefile" ]; then
  printf 'ACK del BSP: '; sed -n '1,4p' "$DEST/kernel-6.6/Makefile" | tr '\n' ' '; echo
fi

[ -d work/gap_analysis ] || ./scripts/gap-analysis.sh

BSP="$DEST/kernel/kernel_device_modules-6.6"
[ -d "$BSP" ] || { echo "no se descargó $BSP" >&2; exit 1; }

find "$BSP" -name 'Kconfig*' -type f -print0 \
  | xargs -0 grep -hE '^[[:space:]]*(menu)?config[[:space:]]+[A-Za-z0-9_]+' \
  | awk '{print $NF}' | sort -u > work/gap_analysis/a34_kconfig_symbols.txt

total=$(wc -l < work/gap_analysis/missing_builtin.txt)
cubiertos=$(comm -12 work/gap_analysis/missing_builtin.txt \
  work/gap_analysis/a34_kconfig_symbols.txt | wc -l)

echo "opciones =y que le faltan a ACK: $total"
echo "de esas, declaradas en el BSP A34: $cubiertos"
comm -23 work/gap_analysis/missing_builtin.txt \
  work/gap_analysis/a34_kconfig_symbols.txt \
  > work/gap_analysis/still_missing.txt
echo "sin cubrir: $(wc -l < work/gap_analysis/still_missing.txt) (ver still_missing.txt)"

echo
echo "Drivers MT6877 presentes:"
for d in drivers/clk/mediatek drivers/pinctrl/mediatek sound/soc/codecs \
         drivers/gpu/drm/mediatek drivers/input/touchscreen; do
  [ -d "$BSP/$d" ] && echo "  $d: $(find "$BSP/$d" -type f | wc -l) archivos"
done
