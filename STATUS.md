# Estado y bloqueo principal

## Lo que sí está resuelto

1. **Defconfig exacto** del kernel que arranca Android 17 en ruby:
   `configs/ruby_defconfig` (8626 líneas, extraído del `Image` con
   `extract-ikconfig`; `CONFIG_IKCONFIG=y`).
2. **Device Tree 6.6** ya migrado: `extracted/dts/mt6877.dts` (SoC, 877 nodos)
   y `extracted/dts/ruby-dtbo.dts` (overlay de ruby, 517 nodos).
3. **Baseline de ABI**: 78 módulos con `vermagic`, `srcversion`, `depends` y
   `modules.dep` en `extracted/modules/`. Todos son genéricos de GKI; no hay
   ningún módulo MTK.
4. **Símbolos**: tabla `kallsyms` completa (184 347 símbolos) y lista filtrada
   de MTK/ruby en `extracted/symbols/`.
5. **Datos del dispositivo vivo** (root/APatch): FDT final con `__symbols__`,
   6509 headers del build exacto (`kheaders`), `sched.h` real que confirma los
   slots KABI 6/7/8 libres.
6. **Kit Droidspaces**: fragmento de config seguro para kABI y los tres parches
   oficiales de slots reservados.
7. **Pipeline reproducible**: `scripts/extract-release.sh`,
   `scripts/dump-device.sh` y `.github/workflows/extract.yml`.

## El bloqueo

`ruby` no usa el layout GKI "boot + vendor_boot + vendor_dlkm". Su `Image` de
53 MB lleva **todos los drivers MTK built-in**. El release no incluye el árbol
fuente con el que se compiló, y ese árbol no es público:

| Fuente pública | Versión | ¿Sirve? |
|---|---|---|
| `MiCode/Xiaomi_Kernel_OpenSource` rama `ruby-s-oss` | 4.19.191 | No |
| `RubyxLabs/kernel_xiaomi_mt6877` (`lineage-23.2`) | 4.19 | No |
| `DXRN-MoonWake/aeron_kernel_xiaomi_ruby` | 4.19.325 | No |
| AOSP `kernel/common` `android15-6.6-2026-04_r31` | 6.6.127 | Solo el núcleo GKI; sin drivers MTK |

El `BoardConfig.mk` del device lo confirma:

```make
TARGET_KERNEL_SOURCE := kernel/xiaomi/mt6877
TARGET_KERNEL_CONFIG := ruby_defconfig
TARGET_KERNEL_CLANG_VERSION := r563880c   # el build real usó r596125
```

Ese `kernel/xiaomi/mt6877` de la rama `lineage-24.0` no está publicado. Sin él:

- compilar ACK 6.6.127 con `ruby_defconfig` descarta las 205 opciones MTK y
  genera un kernel sin pantalla, sin almacenamiento, sin PMIC: **no arranca**;
- no se puede habilitar `PID_NS`/`IPC_NS` por módulo ni por KPM, porque el
  código no está en el binario;
- los 78 `.ko` del vendor no aportan ningún driver de plataforma.

## Caminos posibles

### A. Conseguir el árbol 6.6 (recomendado)

Pedir/extraer `kernel/xiaomi/mt6877` de la rama `lineage-24.0` a RubyxLabs o a
quien mantiene el build. Cuando exista:

```sh
./scripts/build-kernel.sh --source https://github.com/ORG/kernel_xiaomi_mt6877 \
                          --ref lineage-24.0
```

El script aplica el parche kABI, fusiona `configs/droidspaces.fragment`,
compila con el defconfig extraído y reempaqueta `boot.img` conservando ramdisk
y DTB originales.

### B. Portar MTK 4.19 → 6.6

Posible pero grande: 205 configs MTK, DRM/DSI, PMIC mt6359p, táctil, cámara,
conectividad. Semanas de trabajo y riesgo alto. El DTS de 6.6 ya extraído
ahorra la parte de Device Tree, no la de drivers.

### C. Kernel GKI genérico

Solo válido para emulador/QEMU o para validar los parches. No arranca ruby.
El workflow `build.yml` lo produce etiquetado como **NO FLASHEABLE**.

## Criterio de aceptación para dar Droidspaces por terminado

1. `droidspaces check` en el dispositivo: 0 features obligatorias ausentes.
2. `unshare -p -f --mount-proc` y `unshare -i` funcionan.
3. Los 78 `.ko` cargan sin `-f` (CRC y vermagic intactos).
4. `boot.img` con el mismo `vermagic` y mismo `srcversion` por módulo.
5. Arranque estable 72 h y `dmesg` sin `disagrees about version of symbol`.
