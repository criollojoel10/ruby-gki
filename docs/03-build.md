# 03 — Compilar y reempaquetar

## Requisitos

- Linux x86_64/arm64, ~60 GB libres, 16 GB RAM recomendados.
- `clang`/`lld` de Android **r596125** (el del build original) o el que declare
  `extracted/config/summary.txt`.
- `bc`, `bison`, `flex`, `cpio`, `dtc`, `lz4`, `zstd`, `mkbootimg`.
- Python 3 para `unpack_bootimg`.

Toolchain oficial:

```sh
# Android clang r596125 (la misma que el kernel stock)
wget https://android.googlesource.com/kernel/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/clang-r596125.tar.gz
mkdir -p toolchain/clang-r596125 && tar xzf clang-r596125.tar.gz -C toolchain/clang-r596125
export PATH=$PWD/toolchain/clang-r596125/bin:$PATH
```

No cambies de compilador si quieres conservar CRC: `genksyms` deriva los CRC
del tipo, no del codegen, pero el `vermagic` y el binario sí dependen de la
versión.

## Caso A — árbol MTK 6.6 disponible

Es el único camino que produce un `boot.img` que arranca en ruby.

```sh
./scripts/build-kernel.sh \
  --source https://github.com/ORG/kernel_xiaomi_mt6877 \
  --ref lineage-24.0 \
  --config configs/ruby_defconfig \
  --fragment configs/droidspaces.fragment \
  --out out
```

El script:

1. clona el árbol (shallow) y hace checkout del ref;
2. aplica el parche kABI SYSVIPC;
3. fusiona el fragmento Droidspaces;
4. compila `Image.gz` con `LLVM=1`;
5. reempaqueta `boot.img` con el ramdisk y DTB originales;
6. guarda `out/Image.gz`, `out/boot-droidspaces.img` y `out/build-info.txt`.

Antes de flashear, comparar:

```sh
strings out/Image | grep -m1 '^6\.6\.'
# debe coincidir con 6.6.127-android15-8-4k-... si el árbol es el mismo
```

Si el árbol añade commits, el `vermagic` cambiará (`-gXXXX`). Para conservarlo,
fijar `CONFIG_LOCALVERSION` y desactivar `CONFIG_LOCALVERSION_AUTO`, o
recompilar también los 78 módulos y flashearlos juntos.

## Caso B — solo ACK 6.6.127 (experimental, NO arranca ruby)

```sh
./scripts/build-kernel.sh --ack --out out-ack
```

Compila el GKI puro con el fragmento. Sirve para validar que el parche aplica y
que `droidspaces check` pasa en QEMU, pero **no incluye ningún driver MTK**.
No flashear en ruby.

## Reempaquetar sin compilar

Para probar el pipeline o cambiar solo la cmdline:

```sh
./scripts/repack-boot.sh work/boot_unpacked work/boot-new.img
```

Parámetros usados (de `BoardConfig.mk` y de la cabecera real):

```
--header_version 2 --pagesize 2048
--base 0x40078000 --kernel_offset 0x00008000
--ramdisk_offset 0x11088000
--tags_offset 0x07c08000 --dtb_offset 0x07c08000
--os_version 17.0.0 --os_patch_level 2026-10
--cmdline "bootopt=64S3,32N2,64N2 androidboot.tee_type=2"
```

El bootloader está desbloqueado y AVB tiene `hashtree_disabled`, así que un
`boot.img` reempaquetado se puede flashear sin re-firmar `vbmeta`:

```sh
fastboot flash boot boot-new.img
fastboot reboot
```

Guardar siempre el original (`dl/boot.img`) para volver.

## GitHub Actions

- `extract.yml`: reproduce toda la extracción y publica el blueprint.
- `build.yml`: build manual. Acepta `source_repo`/`source_ref`; por defecto usa
  ACK y marca el artefacto como no flasheable.

Los runners estándar tienen ~14 GB libres; el ZIP son 1.6 GB y el árbol de
kernel otros ~2 GB. `extract.yml` libera espacio antes de descargar.
