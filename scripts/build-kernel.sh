#!/usr/bin/env bash
# Compila el kernel 6.6 con soporte Droidspaces.
#
#   ./scripts/build-kernel.sh --source <url> --ref <rama>   # árbol MTK real
#   ./scripts/build-kernel.sh --ack                          # GKI puro (no bootea ruby)
#
# Opciones:
#   --config <file>        defconfig base (def: configs/ruby_defconfig)
#   --fragment <file>      fragmento extra (def: configs/droidspaces.fragment)
#   --patch <file>         parche kABI (def: variante 6_7_8)
#   --boot-unpacked <dir>  si se indica, reempaqueta boot.img al terminar
#   --out <dir>            salida (def: out)
#   --jobs <n>             paralelismo (def: nproc)
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$PWD

SRC=""; REF=""; ACK=0
CONFIG="$ROOT/configs/ruby_defconfig"
FRAGMENT="$ROOT/configs/droidspaces.fragment"
PATCH="$ROOT/droidspaces/patches/001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch"
OUT="$ROOT/out"; JOBS="$(nproc)"; BOOT_UNPACKED=""

while [ $# -gt 0 ]; do
  case "$1" in
    --source) SRC="$2"; shift 2 ;;
    --ref) REF="$2"; shift 2 ;;
    --ack) ACK=1; shift ;;
    --config) CONFIG="$2"; shift 2 ;;
    --fragment) FRAGMENT="$2"; shift 2 ;;
    --patch) PATCH="$2"; shift 2 ;;
    --boot-unpacked) BOOT_UNPACKED="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "opción desconocida: $1" >&2; exit 2 ;;
  esac
done

log() { printf '[build] %s\n' "$*" >&2; }
mkdir -p "$OUT"

if [ "$ACK" = 1 ]; then
  SRC="${SRC:-https://android.googlesource.com/kernel/common}"
  REF="${REF:-android15-6.6-2026-04_r31}"
fi
[ -n "$SRC" ] || { echo "falta --source o --ack" >&2; exit 2; }

TREE="$OUT/linux"
if [ ! -d "$TREE/.git" ]; then
  log "clonando $SRC ($REF)"
  git clone --depth 1 --branch "$REF" "$SRC" "$TREE"
else
  log "usando árbol existente $TREE"
fi

cd "$TREE"
if [ -f "$PATCH" ]; then
  log "aplicando $(basename "$PATCH")"
  patch -p1 --forward < "$PATCH" >/dev/null || log "el parche ya estaba aplicado"
fi

if [ "$ACK" = 1 ]; then
  CONFIG="$TREE/arch/arm64/configs/gki_defconfig"
fi
cp "$CONFIG" arch/arm64/configs/ruby-gki_defconfig

if [ -f "$FRAGMENT" ]; then
  log "fusionando $(basename "$FRAGMENT")"
  scripts/kconfig/merge_config.sh -m arch/arm64/configs/ruby-gki_defconfig "$FRAGMENT" >/dev/null
fi

make ARCH=arm64 LLVM=1 ruby-gki_defconfig >/dev/null
make ARCH=arm64 LLVM=1 olddefconfig >/dev/null

# Guardas: no permitir opciones que rompen el kABI
for bad in CFS_BANDWIDTH CGROUP_PIDS; do
  if grep -q "^CONFIG_${bad}=y" .config; then
    log "ERROR: CONFIG_${bad}=y rompe el kABI; desactívalo"
    exit 3
  fi
done

log "compilando con $(clang --version | head -1)"
make -j"$JOBS" ARCH=arm64 LLVM=1 Image.gz

cp arch/arm64/boot/Image.gz "$OUT/Image.gz"
cp .config "$OUT/config.final"
{
  echo "source: $SRC"
  echo "ref: $REF"
  echo "fecha: $(date -u +%FT%TZ)"
  echo "clang: $(clang --version | head -1)"
  echo "patch: $(basename "$PATCH")"
  grep -E '^CONFIG_(SYSVIPC|POSIX_MQUEUE|PID_NS|IPC_NS|USER_NS|LOCALVERSION)=' .config || true
} > "$OUT/build-info.txt"

if [ -n "$BOOT_UNPACKED" ]; then
  log "reempaquetando boot.img"
  "$ROOT/scripts/repack-boot.sh" "$BOOT_UNPACKED" "$OUT/boot-droidspaces.img" "$OUT/Image.gz"
fi

log "listo: $OUT/Image.gz"
