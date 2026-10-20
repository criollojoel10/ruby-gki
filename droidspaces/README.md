# droidspaces

Kit para habilitar Droidspaces en el kernel 6.6 GKI de ruby.

## Contenido

| Archivo | Uso |
|---|---|
| `patches/001...6_7_8.patch` | Variante por defecto (slots ABI 6, 7, 8). |
| `patches/001...3_4_5.patch` | Alternativa si hay bootloop. |
| `patches/001...1_2_3.patch` | Segunda alternativa. |
| `../configs/droidspaces.fragment` | Opciones a fusionar en el defconfig. |

Los parches vienen de
[`ravindu644/Droidspaces-OSS`](https://github.com/ravindu644/Droidspaces-OSS),
`Documentation/resources/kernel-patches/GKI/below-kernel-6.12/`, GPL-2.0.

## Orden de aplicación

```sh
patch -p1 < droidspaces/patches/001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch
scripts/kconfig/merge_config.sh -m arch/arm64/configs/ruby_defconfig \
    configs/droidspaces.fragment
make ARCH=arm64 olddefconfig
```

El parche **debe** ir antes de activar `CONFIG_SYSVIPC`. Sin él, el layout de
`task_struct` cambia, los CRC de los símbolos exportados cambian y los 78 `.ko`
del vendor se niegan a cargar.

## Qué hace exactamente

`CONFIG_SYSVIPC` añade `sysv_sem` y `sysv_shm` a `task_struct`. El parche
comenta esos campos en su posición original y los coloca en los
`ANDROID_KABI_RESERVE(n)`, que ya forman parte del struct y no alteran
offsets. El resultado es el mismo layout binario con IPC habilitado.

`CONFIG_PID_NS`, `CONFIG_IPC_NS` y `CONFIG_POSIX_MQUEUE` no mueven
`task_struct`, así que no necesitan parche.

## Qué no activar

```
CONFIG_CFS_BANDWIDTH
CONFIG_CGROUP_PIDS
```

Redimensionan `task_struct`/`cgroup` y cambian miles de CRC. No hay padding que
lo cubra. Sin ellas Droidspaces pierde `--cpus` y `--pids-limit`, nada más.
`scripts/build-kernel.sh` aborta si las encuentra activas.

## Verificar

```sh
adb shell 'zcat /proc/config.gz' | ./scripts/check-droidspaces.sh -
adb shell droidspaces check
adb shell dmesg | grep -i 'disagrees about version'
```
