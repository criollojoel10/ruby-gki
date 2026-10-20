# 05 — Datos del dispositivo en marcha

Aprovechando root (APatch, `su` en dominio `u:r:magisk:s0`) y Termux se
extrajeron datos que **no están en el release**. Todo es lectura.

## Cómo se accede

```sh
ssh termux                 # shell Android (u0_a176)
su -c id                   # uid=0, contexto u:r:magisk:s0
ssh termux "su -c 'cat /sys/firmware/fdt'" > fdt-live.dtb
```

El chroot de Arch (`ruri`) no ve `/vendor` ni `/dev/block`, así que hay que
pasar por Termux. Reproducible con [`../scripts/dump-device.sh`](../scripts/dump-device.sh).

## Artefactos

| Archivo | Origen | Tamaño | Valor |
|---|---|---|---|
| `fdt-live.dtb` | `/sys/firmware/fdt` | 263 363 B | Device Tree **final** con boot + dtbo aplicados y `__symbols__`. |
| `fdt-live.dts` | `dtc -I dtb` | 314 KB | 1185 nodos, 576 phandles. |
| `fdt-live-labeled.dts` | `relabel-dts.py` | 314 KB | Referencias seguras convertidas a `&label` (69). |
| `kheaders.tar.xz` | `/sys/kernel/kheaders.tar.xz` | 4.3 MB | 6509 headers del build exacto, **0 archivos .c**. |
| `headers/` | extraídos del tar | — | `sched.h`, `ipc_namespace.h`, `pid_namespace.h`, `nsproxy.h`, `cgroup-defs.h`, exports GKI. |
| `kallsyms-live.txt.gz` | `/proc/kallsyms` | 1.1 MB | 184 442 símbolos; direcciones a cero por `kptr_restrict=2`. |
| `kernel-notes.bin` | `/sys/kernel/notes` | 84 B | Build ID. |
| `device-info.txt` | varios | — | Versión, cmdline, hashes, particiones. |

## Device Tree vivo

El FDT de 263 KB es la suma del DTB del boot (179 KB) y el overlay RUBY
(77 KB), ya resuelto por el bootloader. Incluye `__symbols__`, que dtc
descarta al decompilar; `scripts/relabel-dts.py` lo usa para mapear
phandle → etiqueta y reescribe solo propiedades inequívocas
(`interrupt-parent`, `*-supply`, `*-gpios`, `memory-region`…).

El resultado compila con `dtc` sin errores. Es la base editable para
`arch/arm64/boot/dts/mediatek/ruby.dts`.

## Headers del kernel

`CONFIG_IKHEADERS=m` permitió cargar `kheaders.ko` y obtener el tarball que el
kernel genera en build time. Contiene **todos los headers internos** de
`include/` y `arch/arm64/include/`, con la configuración real
(`include/generated/autoconf.h`, `utsrelease.h`) y las listas de exports
protegidos de GKI (517 + 8).

No contiene `.c`, así que no sustituye al árbol fuente: sirve para adaptar
parches, estructuras y firmas sin adivinar.

## Hallazgo para el parche Droidspaces

En el `sched.h` real (`extracted/headers/sched.h`, líneas 1221-1229):

```c
ANDROID_KABI_USE(1, struct task_dma_buf_info *dmabuf_info);

ANDROID_KABI_RESERVE(2);
ANDROID_KABI_RESERVE(3);
ANDROID_KABI_RESERVE(4);
ANDROID_KABI_RESERVE(5);
ANDROID_KABI_RESERVE(6);
ANDROID_KABI_RESERVE(7);
ANDROID_KABI_RESERVE(8);
```

Los slots **6, 7 y 8 están libres**, que es exactamente lo que usa la variante
por defecto `001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch`. No hace falta
probar las otras dos salvo que el árbol MTK cambie esos huecos.

## Estado de las particiones

```
boot_a -> /dev/block/sdc32   sha256 a6faa65f...  (kernel parcheado por APatch)
dtbo_a -> /dev/block/sdc35   sha256 73a09532...  (= dtbo del payload)
```

El kernel de `boot_a` **no** coincide con el del release porque APatch lo
parchea al instalar. El kernel original está en `boot.img` del payload/release
(SHA-256 `05a69ae4...`), que es el que se usa para el análisis.

## Lo que sigue sin poder extraerse

- Código `.c` de los drivers MTK: no está en el binario ni en kheaders.
- BTF (`/sys/kernel/btf/vmlinux` no existe: `CONFIG_DEBUG_INFO_BTF` off).
- `/proc/kcore`: no existe (`CONFIG_PROC_KCORE` off).
- FTrace de funciones: `CONFIG_FUNCTION_TRACER` off, no hay
  `available_filter_functions`.

Para “liberar los sources” de verdad hace falta el árbol
`kernel/xiaomi/mt6877` o una release GPL del OEM; estos artefactos reducen el
trabajo de portarlo, no lo eliminan.
