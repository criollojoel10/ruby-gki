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

## Cómo desbloquear

1. Pedir a quien mantiene el build de `lineage-24.0` acceso al árbol
   `kernel/xiaomi/mt6877` (o su tarball), aunque sea sin historial.
2. Verificar que su `Makefile` declara 6.6.127 y que incluye `arch/arm64/configs/ruby_defconfig`.
3. Compilar con `scripts/build-kernel.sh --source ... --ref ...`.
4. Comparar `vermagic` y `srcversion` de los 78 módulos antes de flashear.

Mientras tanto, `ruri` + Arch Linux ARM sigue siendo la alternativa funcional
en el kernel stock (ver el repositorio `stack-ruby`).
