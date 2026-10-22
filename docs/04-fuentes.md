# 04 — Fuentes públicas evaluadas

Búsqueda hecha el 2026-10-20. Ninguna fuente pública contiene el árbol MTK 6.6
con el que se compiló el kernel de ruby.

| Repositorio | Rama | Versión | Resultado |
|---|---|---|---|
| `MiCode/Xiaomi_Kernel_OpenSource` | `ruby-s-oss` | 4.19.191 | descartado |
| `RubyxLabs/kernel_xiaomi_mt6877` | `lineage-23.2` | 4.19 | descartado |
| `DXRN-MoonWake/aeron_kernel_xiaomi_ruby` | `ksu_susfs`, `lineage-23.0` | 4.19.325 | descartado |
| `xiaomi-mediatek-devs/android_kernel_xiaomi_mt6877` | `lineage-21` | 4.19 | descartado |
| `android.googlesource.com/kernel/common` | `android15-6.6-2026-04_r31` | 6.6.127 | solo GKI, sin MTK |

Comprobación de versión:

```sh
gh api repos/MiCode/Xiaomi_Kernel_OpenSource/contents/Makefile?ref=ruby-s-oss \
  --jq .content | base64 -d | head -4
# VERSION=4 PATCHLEVEL=19 SUBLEVEL=191
```

El `BoardConfig.mk` de `RubyxLabs/device_xiaomi_rubyx` (`lineage-24.0`) declara
el árbol que falta:

```make
TARGET_KERNEL_SOURCE := kernel/xiaomi/mt6877
TARGET_KERNEL_CONFIG := ruby_defconfig
TARGET_KERNEL_CLANG_VERSION := r563880c
```

Ese repositorio no aparece ni en la organización `RubyxLabs` ni en el usuario,
y la release no incluye fuente. Tampoco hay un `vendor_boot`/`vendor_dlkm` del
que rescatar módulos MTK: solo hay 78 `.ko` genéricos.

## Precedente útil

`blue-boy-questions/kernel_daria_zahedan` compila ACK 6.6 para otro MT6877
(Volla Quintus). Es una **receta**, no un BSP: usa el GKI y módulos de vendor.
En ruby los drivers MTK son built-in, así que ese enfoque no se traslada
directamente, pero sirve como plantilla de CI y de parches kABI.

## Actualización 2026-10-22: el árbol MTK 6.6 de MT6877 sí es público

Búsqueda nueva (la del 2026-10-20 se centró en repos de *ruby* y se pasó por
alto el árbol de otro OEM con el **mismo SoC**):

| Repositorio | Rama | Qué es |
|---|---|---|
| `HelloVolla/android_kernel_volla_mt6877` | `volla-16.0` | GKI **6.6.89** de MTK para MT6877 (`gki_defconfig`, `build.config.gki.aarch64`, `abi.bzl`) |
| `HelloVolla/android_kernel_device_modules_volla_mt6877` | `volla-16.0` | **device modules de MTK 6.6 para MT6877** |

Verificado por API en el árbol de device modules:

- `drivers/tee/teei/{400,510,515}` → Microtrust TEEI, el TEE real de ruby.
- `drivers/gpu/drm/mediatek/mediatek_v2/` → API de display (`mtk_panel_ctx`).
- `drivers/gpu/drm/panel/panel-n11a-42-02-0a-dsc-vdo.c` → panel Xiaomi DSC VDO
  (plantilla para el m16 de ruby).
- `drivers/input/touchscreen/focal_FT3519/focaltech_spi_v2.c` → transporte SPI
  de Focaltech en 6.6 (ruby usa FT3680 por SPI3).
- `drivers/power/supply/` → `mtk_charger`, `mtk_pe4/5`, `mtk_gauge`,
  `charger_class`, `sc8551-charger.c`, `ufcs`…
- `arch/arm64/boot/dts/mediatek/{mt6877.dts,k6877v1_64.dts}`.

Dos consecuencias:

1. **El laboratorio ya usa esa plataforma.** El árbol del A34
   (`UN1CA/kernel_samsung_a34x`) tiene como submodulo `kernel-6.6` el GKI de
   MTK 6.6.127 y como `kernel_device_modules-6.6` el árbol de device modules
   **de MTK para MT6877** (el A34 5G es un Exynos 1380 = MT6877V): trae
   `teei/{400,510,515}`, `mediatek_v2`, `mt6359p`, la carga de MTK, focaltech,
   goodix y GT9xx. Falta lo propio del board de ruby: panel `m16_36_02_0b`,
   Focaltech FT3680 por SPI, los cargadores de Xiaomi (mp2762, ln8410, sc8561,
   bq25980, xmusb350, bq28z610, max77932), la huella Goodix y el GNSS de MTK.
2. **El Device Tree no hay que portarlo**: el DTB 6.6 de ruby ya esta
   extraido en `work/dtb_boot/01_dtbdump_MT6877.dtb` y el overlay de ruby
   sigue en la partición `dtbo`.

Clonado en el laboratorio con `scripts/fetch-mtk-6.6-mt6877.sh`; el análisis
completo esta en `rubyx-kernel66-lab/docs/91-base-mtk-6.6-mt6877.md`.

## Cómo desbloquear

1. Pedir a quien mantiene el build de `lineage-24.0` acceso al árbol
   `kernel/xiaomi/mt6877` (o su tarball), aunque sea sin historial.
2. Verificar que su `Makefile` declara 6.6.127 y que incluye `arch/arm64/configs/ruby_defconfig`.
3. Compilar con `scripts/build-kernel.sh --source ... --ref ...`.
4. Comparar `vermagic` y `srcversion` de los 78 módulos antes de flashear.

Si (1) no llega, la alternativa es portar sobre el árbol MTK 6.6 de MT6877
público los drivers propios de ruby, usando el DTB ya extraído y los
parches kABI de Droidspaces (ver el laboratorio).

Mientras tanto, `ruri` + Arch Linux ARM sigue siendo la alternativa funcional
en el kernel stock (ver el repositorio `stack-ruby`).
