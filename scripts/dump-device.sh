#!/usr/bin/env bash
# Extrae datos del ruby en marcha (Android 17, kernel 6.6) vía Termux + su.
#
#   ./scripts/dump-device.sh [host_ssh] [directorio]
#   ./scripts/dump-device.sh termux extracted/device
#
# Requiere: ssh sin password al host, `su` (APatch/Magisk) y que el kernel
# tenga cargado kheaders.ko (CONFIG_IKHEADERS=m) para /sys/kernel/kheaders.tar.xz.
# Todo es lectura; no escribe en el dispositivo.
set -euo pipefail

HOST="${1:-termux}"
OUT="${2:-extracted/device}"
mkdir -p "$OUT"

log() { printf '[device] %s\n' "$*" >&2; }
root() { ssh -o BatchMode=yes "$HOST" "su -c '$1'"; }

log "identidad"
{
  echo "# Datos del dispositivo ($HOST)"
  echo
  ssh -o BatchMode=yes "$HOST" 'getprop ro.product.device; getprop ro.build.version.release;
    getprop ro.build.version.sdk; getprop ro.boot.slot_suffix' 2>/dev/null
  echo
  root 'cat /proc/version'
  echo
  root 'cat /proc/cmdline'
} > "$OUT/device-info.txt"

log "FDT vivo"
root 'cat /sys/firmware/fdt' > "$OUT/fdt-live.dtb"
dtc -I dtb -O dts -o "$OUT/fdt-live.dts" "$OUT/fdt-live.dtb" 2>/dev/null
./scripts/relabel-dts.py "$OUT/fdt-live.dts" "$OUT/fdt-live-labeled.dts" || true

log "headers del kernel"
if root 'test -r /sys/kernel/kheaders.tar.xz'; then
  root 'cat /sys/kernel/kheaders.tar.xz' > "$OUT/kheaders.tar.xz"
  tar -tJf "$OUT/kheaders.tar.xz" | wc -l | sed 's/^/  entradas: /' >&2
else
  log "kheaders no disponible; ejecuta: su -c 'insmod /vendor/lib/modules/kheaders.ko'"
fi

log "kallsyms (direcciones ocultas si kptr_restrict=2)"
root 'cat /proc/kallsyms' | gzip -9 > "$OUT/kallsyms-live.txt.gz"
root 'cat /sys/kernel/notes' > "$OUT/kernel-notes.bin" 2>/dev/null || true
root 'cat /proc/modules' > "$OUT/proc-modules.txt" 2>/dev/null || true

if [ "${DUMP_PARTITIONS:-0}" = 1 ]; then
  log "particiones boot_a / dtbo_a (solo lectura)"
  root 'cat /dev/block/by-name/boot_a' > "$OUT/boot_a.img"
  root 'cat /dev/block/by-name/dtbo_a' > "$OUT/dtbo_a.img"
  sha256sum "$OUT"/boot_a.img "$OUT"/dtbo_a.img >> "$OUT/device-info.txt"
fi

log "listo: $OUT"
