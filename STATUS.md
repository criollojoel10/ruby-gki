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
fuente con el que se compiló, y ese árbol exacto no es público:

| Fuente pública | Versión | ¿Sirve? |
|---|---|---|
| `MiCode/Xiaomi_Kernel_OpenSource` rama `ruby-s-oss` | 4.19.191 | No |
| `RubyxLabs/kernel_xiaomi_mt6877` (`lineage-23.2`) | 4.19 | No |
| `DXRN-MoonWake/aeron_kernel_xiaomi_ruby` | 4.19.325 | No |
| AOSP `kernel/common` `android15-6.6-2026-04_r31` | 6.6.127 | Solo el núcleo GKI; sin drivers MTK |
| **`HelloVolla/android_kernel_volla_mt6877`** + **`..._device_modules_volla_mt6877`** | **6.6.89 (MTK 6.6 de MT6877)** | **Sí: misma plataforma, drivers MTK de 6.6** |

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

### Estado real a 2026-10-22 (ver `rubyx-kernel66-lab/docs/91-*`)

El bloqueo se ha reencuadrado gracias a dos hallazgos:

1. **El árbol MTK 6.6 de MT6877 sí es público** (el de Volla): GKI 6.6.89 +
   device modules de MTK para MT6877 con TEEI 400/510/515, `mediatek_v2`,
   focaltech por SPI, carga de MTK y el DTS `mt6877.dts`. Y el árbol que ya
   usa el laboratorio (`UN1CA/kernel_samsung_a34x`) **es** la plataforma
   MTK 6.6 de MT6877: el A34 5G es un Exynos 1380 = MT6877V, y su
   `kernel_device_modules-6.6` es el árbol de device modules de MTK (TEEI,
   mediatek_v2, mt6359p, carga MTK, focaltech, goodix, GT9xx).
2. **El Device Tree no hay que portarlo**: el DTB 6.6 de ruby ya está
   extraído (`work/dtb_boot/01_dtbdump_MT6877.dtb`) y el overlay sigue en la
   partición `dtbo`.

Lo que falta, por tanto, son los drivers **propios del board de ruby**:

| Driver | Origen del port |
|---|---|
| panel `m16_36_02_0b` (DSC VDO 1080x2400) | 4.19 de ruby + plantilla `panel-n11a-42-02-0a-dsc-vdo.c` |
| Focaltech FT3680 por SPI3 | 4.19 de ruby + `focaltech_spi_v2.c` del árbol MTK |
| cargadores `mp2762`, `ln8410`, `sc8561`, `bq25980`, `xmusb350`, `bq28z610`, `max77932` | 4.19 de ruby |
| huella Goodix por SPI | 4.19 de ruby |
| GNSS/consys | `vendor/mediatek/kernel_modules/connectivity/gps/*` (por localizar) |

El panel ya está portado y compilándose en CI
(`rubyx-kernel66-lab/port/display/`), y el TEEI 400 también.

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
