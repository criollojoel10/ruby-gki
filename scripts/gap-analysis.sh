#!/usr/bin/env bash
# Cruza configs/ruby_defconfig contra ACK 6.6.127 y kheaders del dispositivo.
#
#   ./scripts/gap-analysis.sh [arbol_kernel] [salida]
#
# Responde: ¿cuántas opciones =y del kernel de ruby no existen en ACK y
# cuántos headers del build real faltan en ACK?
set -euo pipefail

TREE="${1:-kernel/common}"
OUT="${2:-work/gap_analysis}"
mkdir -p "$OUT"

[ -d "$TREE" ] || { echo "falta $TREE (git submodule update --init)" >&2; exit 1; }

# Símbolos declarados en cualquier Kconfig del árbol
find "$TREE" -name 'Kconfig*' -type f -print0 \
  | xargs -0 grep -hE '^[[:space:]]*(menu)?config[[:space:]]+[A-Za-z0-9_]+' \
  | awk '{print $NF}' | sort -u > "$OUT/ack_kconfig_symbols.txt"

grep -E '=y$' configs/ruby_defconfig | sed -E 's/^CONFIG_//; s/=y$//' | sort -u \
  > "$OUT/ruby_builtin.txt"
grep -E '=m$' configs/ruby_defconfig | sed -E 's/^CONFIG_//; s/=m$//' | sort -u \
  > "$OUT/ruby_modules.txt"

comm -23 "$OUT/ruby_builtin.txt" "$OUT/ack_kconfig_symbols.txt" \
  > "$OUT/missing_builtin.txt"
comm -23 "$OUT/ruby_modules.txt" "$OUT/ack_kconfig_symbols.txt" \
  > "$OUT/missing_modules.txt"

# Headers del build real que no están en ACK
if [ -f extracted/device/kheaders.tar.xz ]; then
  rm -rf "$OUT/kheaders"; mkdir -p "$OUT/kheaders"
  tar -xJf extracted/device/kheaders.tar.xz -C "$OUT/kheaders"
  (cd "$OUT/kheaders" && find . -type f) | sort > "$OUT/kheaders_files.txt"
  (cd "$TREE" && find . -name '*.h' -type f) | sort > "$OUT/ack_headers.txt"
  comm -23 "$OUT/kheaders_files.txt" "$OUT/ack_headers.txt" \
    > "$OUT/missing_headers.txt"
fi

echo "== ruby =="
echo "  =y: $(wc -l < "$OUT/ruby_builtin.txt")"
echo "  =m: $(wc -l < "$OUT/ruby_modules.txt")"
echo "== ACK $TREE =="
echo "  símbolos Kconfig: $(wc -l < "$OUT/ack_kconfig_symbols.txt")"
echo "  =y que no existen en ACK: $(wc -l < "$OUT/missing_builtin.txt")"
echo "  =m que no existen en ACK: $(wc -l < "$OUT/missing_modules.txt")"
[ -f "$OUT/missing_headers.txt" ] && \
  echo "  headers del build real ausentes en ACK: $(wc -l < "$OUT/missing_headers.txt")"

echo
echo "-- primeras 40 opciones =y ausentes --"
head -40 "$OUT/missing_builtin.txt"
echo
echo "Resultados en $OUT/"
