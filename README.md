# ruby-gki

Ingeniería inversa y receta de compilación del **kernel 6.6 GKI** del
**Xiaomi Redmi Note 12 Pro 5G** (`ruby` / `rubyx`, MediaTek **MT6877V**,
Dimensity 1080) con **LineageOS 24.0 (Android 17)**, release
[`rubyx-20261015`](https://github.com/RubyxLabs/releases/releases/tag/rubyx-20261015).

El objetivo final es un `boot.img` propio con **soporte Droidspaces**
(`CONFIG_PID_NS`, `CONFIG_IPC_NS`, `CONFIG_SYSVIPC`, `CONFIG_POSIX_MQUEUE`)
sin romper el ABI de los 78 módulos del vendor.

> **Estado corto:** la receta, el defconfig exacto, los Device Trees ya
> portados a 6.6, el baseline de ABI de los módulos y el kit Droidspaces están
> extraídos y versionados aquí. **Falta la pieza que no está en el release:**
> el árbol fuente MTK 6.6 (`kernel/xiaomi/mt6877`). Sin él se puede compilar el
> núcleo GKI genérico, pero no un kernel que arranque en ruby. Ver
> [`STATUS.md`](STATUS.md).

## Contenido

| Ruta | Qué es |
|---|---|
| `configs/ruby_defconfig` | `.config` exacto de 8626 líneas extraído del `Image` (IKCONFIG). |
| `configs/droidspaces.fragment` | Opciones Droidspaces seguras para kABI GKI 6.6. |
| `droidspaces/patches/` | Parches kABI SYSVIPC (3 variantes de slots reservados). |
| `extracted/dts/mt6877.dts` | DTB del SoC decompilado desde `boot.img`. |
| `extracted/dts/ruby-dtbo.dts` | Overlay de ruby decompilado desde `dtbo.img`. |
| `extracted/modules/` | 78 `.ko`, `modinfo`, `modules.dep`, `modules.alias`. |
| `extracted/symbols/` | `kallsyms` completo + símbolos MTK/ruby filtrados. |
| `extracted/config/` | Banner de versión, compilador y flags ausentes. |
| `scripts/` | Extracción, build y reempaquetado de `boot.img`. |
| `.github/workflows/` | Pipeline de extracción y build en Actions. |
| `kernel/common` | Submódulo: ACK `android15-6.6` **6.6.127** (`2026-04_r31`). |

## Datos verificados

```
kernel      6.6.127-android15-8-4k-gf18ad88fac49-dirty
            #5 SMP PREEMPT Wed Oct 14 19:20:13 UTC 2026 aarch64
compilador  Android clang 22.0.2 (r596125), LLD 22.0.2
config      Linux/arm64 6.6.127, GKI android15-8, 4K pages
vermagic    6.6.127-android15-8-4k-gf18ad88fac49-dirty SMP preempt mod_unload modversions aarch64
módulos     78 (.ko genéricos GKI; 0 drivers MTK)
DTB         179 139 B, 877 nodos
DTBO        76 799 B, 517 nodos
```

SHA-256 del release:

```
c9d6ad0d7e8921f708de65cbc71817d9bfb88f82c0768d87672f29a8000252aa  boot.img
7b96bf5d575f8ee38bb5f326d2de30887eba6b7a8fec78bac0e9e0c6188165a8  dtbo.img
8caef5f13ee19c9906a040032ba9f0a7846dc2044087a227a0d26f4d0059a2dc  lineage-24.0-20261014-UNOFFICIAL-rubyx.zip
```

## Layout real de la ROM

El release **no** usa `vendor_boot` ni `vendor_dlkm`. El payload tiene 25
particiones y el kernel va todo en `boot`:

```
boot.img (128 MB)  -> kernel 21 MB (gzip->53 MB) + ramdisk 20 MB + dtb 175 KB
dtbo.img (32 MB)   -> 1 overlay (RUBY)
vendor.img (501 MB, erofs) -> /lib/modules con 78 .ko genéricos
```

Consecuencia: los drivers MTK (pantalla, táctil, PMIC, cámara, wifi…) están
**built-in** en el `Image` (205 `CONFIG_MTK_*`), no en módulos. Cambiar el
kernel obliga a reconstruir esos drivers, no basta con reutilizar `.ko`.

## Uso rápido

```sh
git clone --recurse-submodules https://github.com/criollojoel10/ruby-gki
cd ruby-gki

# 1. Reproducir la extracción completa desde el release
./scripts/extract-release.sh rubyx-20261015

# 2. Reempaquetar el boot.img original (sin tocar kernel) como prueba
./scripts/repack-boot.sh work/boot_unpacked work/boot-new.img

# 3. Comprobar requisitos Droidspaces en el dispositivo
adb shell sh -c 'zcat /proc/config.gz' | ./scripts/check-droidspaces.sh -
```

## Droidspaces

El kernel stock no puede ejecutarlo: faltan `PID_NS`, `IPC_NS`, `SYSVIPC`,
`POSIX_MQUEUE` y `USER_NS`. No son módulos ni se pueden activar en runtime.
En GKI 6.6 hay que aplicar el parche kABI
`001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch` antes de activar las
opciones, o el teléfono entra en bootloop al rechazar los módulos del vendor
sus CRC. Detalle en [`docs/02-droidspaces.md`](docs/02-droidspaces.md).

## Aviso

Este repositorio no distribuye blobs propietarios ni el árbol MTK privado.
Solo contiene artefactos derivados del release público y parches GPL. Flashear
un `boot.img` incorrecto puede dejar el dispositivo sin arranque; mantén a mano
el `boot.img` original.
