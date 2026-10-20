#!/usr/bin/env bash
# Comprueba un .config (o /proc/config.gz del dispositivo) contra Droidspaces.
#
#   ./scripts/check-droidspaces.sh [config|-]
#   adb shell 'zcat /proc/config.gz' | ./scripts/check-droidspaces.sh -
set -euo pipefail

SRC="${1:-}"
if [ -z "$SRC" ]; then
  if [ -r /proc/config.gz ]; then SRC=/proc/config.gz
  elif [ -r /boot/config-$(uname -r) ]; then SRC=/boot/config-$(uname -r)
  else echo "uso: $0 <config|->" >&2; exit 2; fi
fi

CONF="$(mktemp)"
trap 'rm -f "$CONF"' EXIT
if [ "$SRC" = "-" ]; then cat > "$CONF"
elif [[ "$SRC" == *.gz ]]; then gzip -dc "$SRC" > "$CONF"
else cp "$SRC" "$CONF"; fi

val() { sed -n "s/^CONFIG_$1=//p" "$CONF" | head -1; }
is_y() { [ "$(val "$1")" = "y" ]; }

missing=0
row() { # row CONFIG etiqueta must(1/0)
  local c=$1 label=$2 must=$3
  if is_y "$c"; then printf '  [OK]      %-34s %s\n' "$c" "$label"
  else
    printf '  [FALTA]   %-34s %s\n' "$c" "$label"
    [ "$must" = 1 ] && missing=$((missing + 1)) || true
  fi
}

echo "== obligatorias =="
row SYSVIPC          "IPC SysV"                       1
row POSIX_MQUEUE     "colas POSIX"                    1
row PID_NS           "PID namespace"                  1
row IPC_NS           "IPC namespace"                  1
row NAMESPACES       "namespaces"                     1
row SECCOMP          "seccomp"                        1
row SECCOMP_FILTER   "seccomp filter"                 1
row CGROUPS          "cgroups"                        1
row DEVTMPFS         "devtmpfs"                       1

echo "== recomendadas =="
row USER_NS          "user namespace (sandbox/docker)" 0
row NET_NS           "net namespace"                   0
row VETH             "veth"                            0
row BRIDGE           "bridge"                          0
row NETFILTER        "netfilter"                       0
row OVERLAY_FS       "overlayfs"                       0
row FUSE_FS          "FUSE"                            0
row TUN              "TUN"                             0
row BLK_DEV_LOOP     "loop"                            0
row EXT4_FS          "ext4"                            0
row MACVLAN          "macvlan"                         0

echo
if [ "$missing" -eq 0 ]; then
  echo "Resultado: OK — no falta ninguna opción obligatoria."
else
  echo "Resultado: faltan $missing opciones obligatorias."
fi

if is_y SYSVIPC && ! is_y PID_NS; then
  echo "AVISO: SYSVIPC sin el parche kABI puede romper los módulos del vendor."
fi
exit $([ "$missing" -eq 0 ] && echo 0 || echo 1)
