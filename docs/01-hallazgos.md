# 01 — Hallazgos de la extracción

Todo lo de este documento se obtuvo del release `rubyx-20261015`, sin acceso al
dispositivo ni al árbol fuente.

## Identidad del kernel

```
Linux version 6.6.127-android15-8-4k-gf18ad88fac49-dirty
  (nobody@android-build)
  (Android (15071444, +pgo, +bolt, +lto, +mlgo, based on r596125)
   clang version 22.0.2, LLD 22.0.2)
  #5 SMP PREEMPT Wed Oct 14 19:20:13 UTC 2026 aarch64
```

- Rama GKI: `android15-6.6`, KMI generación 8, páginas 4K.
- `CONFIG_LOCALVERSION="-android15-8-4k"` + `CONFIG_LOCALVERSION_AUTO=y`
  (de ahí `-gf18ad88fac49-dirty`).
- `CONFIG_MODVERSIONS=y`, `CONFIG_MODULE_SIG=y`,
  `CONFIG_MODULE_SIG_PROTECT=y`, `CONFIG_MODULE_SIG_ALL=y`.
- El tag de ACK con el mismo SUBLEVEL es `android15-6.6-2026-04_r31`
  (6.6.127), fijado como submódulo en `kernel/common`.

## Particiones del payload

25 particiones, ninguna `vendor_boot`, `init_boot`, `vendor_dlkm`,
`system_dlkm` ni `odm`:

```
audio_dsp boot cam_vpu1 cam_vpu2 cam_vpu3 dpm dtbo gz lk logo mcupm md1img
pi_img preloader_raw product scp spmfw sspm system system_ext tee vbmeta
vbmeta_system vbmeta_vendor vendor
```

## boot.img

```
header version  2
kernel          21 082 776 B  (gzip; 55 564 296 B descomprimido)
ramdisk         20 651 368 B  (lz4)
dtb                179 139 B
cmdline         bootopt=64S3,32N2,64N2 androidboot.tee_type=2
os version      17.0.0 / 2026-10
base            0x40078000  kernel 0x40080000
ramdisk         0x51100000  tags/dtb 0x47c80000
page size       2048
```

El DTB contiene dos fragmentos; el útil es `01_dtbdump_MT6877.dtb`
(`compatible = "mediatek,mt6877","mediatek,MT6877"`).

El `boot.img` suelto del release y el `boot` del payload tienen el **mismo
kernel y el mismo DTB** (SHA-256 idénticos), pero **ramdisk distinto**: el
release va reempaquetado (probablemente con el `overlay.d` de KernelSU o un
ramdisk de recovery). Para el análisis de kernel es indiferente.

## dtbo.img

Cabecera `d7b7ab1e`, 1 entrada de 76 799 B llamada `RUBY`; el resto del archivo
de 32 MB es padding. El overlay define paneles, táctil y periféricos de ruby.

## Módulos

78 `.ko` en `/vendor/lib/modules` (erofs), todos genéricos:

```
6lowpan 8021q 9pnet 9pnet_fd aqc111 asix ax88179_178a bpf_preload btbcm
btqca btsdio can* cdc-acm cdc_eem cdc_ether ... kunit ... virtio ... gzvm
```

- `vermagic` idéntico en todos:
  `6.6.127-android15-8-4k-gf18ad88fac49-dirty SMP preempt mod_unload modversions aarch64`
- `modules.load` está vacío; `modules.dep` y `modules.alias` sí tienen contenido.
- **0 módulos MTK** → pantalla, táctil, PMIC, cámara, wifi y almacenamiento van
  built-in en el `Image`.

## Config

8626 líneas. 205 opciones `CONFIG_MTK_*`, entre ellas:

```
CONFIG_MTK_PLATFORM="mt6877"
CONFIG_MACH_MT6877=y
CONFIG_MTK_LPM_MT6877=y
CONFIG_MTK_APUSYS_SUPPORT=y
```

Ausencias que bloquean Droidspaces:

```
# CONFIG_SYSVIPC is not set
# CONFIG_POSIX_MQUEUE is not set
# CONFIG_PID_NS is not set
# CONFIG_USER_NS is not set
# CONFIG_CGROUP_PIDS is not set
# CONFIG_CFS_BANDWIDTH is not set
# CONFIG_CGROUP_DEVICE is not set
# CONFIG_NETFILTER_XT_MATCH_ADDRTYPE is not set
```

`CONFIG_IPC_NS` no aparece ni como `is not set`: no está definida.

## Símbolos

`kallsyms` reconstruido: 184 347 símbolos, base `ffffffc080000000`.
Confirma que los subsistemas ausentes no existen en el binario (0 símbolos
`sysvipc`, `pid_namespace` o `ipc_namespace`) y que los drivers MTK sí están
integrados (`mt6877_pinctrl_probe`, `clk_mt6877_*`, `mt6877_devapc_probe`…).

## Conclusión técnica

Es un kernel **GKI 6.6 moderno con el BSP MTK enlazado estáticamente**. No es
un GKI puro con módulos de vendor: es un árbol MTK privado. Por eso el
`boot.img` no se puede reconstruir solo con ACK + los `.ko` del release.

Los datos del dispositivo en marcha (FDT final, kheaders, `sched.h`) están en
[`05-dispositivo.md`](05-dispositivo.md).
