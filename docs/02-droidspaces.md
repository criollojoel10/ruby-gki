# 02 — Droidspaces en GKI 6.6

## Qué exige y qué hay

| Requisito | Kernel stock | Necesita rebuild |
|---|---|---|
| `CONFIG_PID_NS` | ❌ | sí |
| `CONFIG_IPC_NS` | ❌ (no definida) | sí |
| `CONFIG_SYSVIPC` | ❌ | sí |
| `CONFIG_POSIX_MQUEUE` | ❌ | sí |
| `CONFIG_USER_NS` | ❌ | sí (sandbox) |
| mount/UTS/net/cgroup ns | ✅ | no |
| seccomp + filter | ✅ | no |
| devtmpfs, cgroup v2, loop, ext4 | ✅ | no |
| overlayfs, FUSE, TUN, veth, bridge | ✅ | no |
| MACVLAN, NAT66, addrtype | ❌ | opcional |

Sin `PID_NS` e `IPC_NS` Droidspaces no arranca: su init debe ser PID 1 dentro
de un PID namespace. No hay modo degradado, ni se puede cargar como módulo
(son `bool` de compilación), ni APatch/KPM puede inyectar código que no existe.

## Por qué el parche kABI es obligatorio

En GKI, los módulos del vendor se validan por dos cosas:

1. `vermagic` (versión, KMI, `modversions`, `preempt`, `mod_unload`).
2. CRC por símbolo exportado (`CONFIG_MODVERSIONS`).
3. Firma (`CONFIG_MODULE_SIG_PROTECT`).

`CONFIG_SYSVIPC` añade `struct sysv_sem` y `struct sysv_shm` dentro de
`task_struct`. Eso desplaza todos los campos posteriores y cambia el CRC de
miles de funciones exportadas. Los 78 `.ko` del vendor dejarían de cargar y el
dispositivo entraría en bootloop.

El parche mueve esos campos a los huecos `ANDROID_KABI_RESERVE()` que el ABI ya
reserva, de modo que el layout no cambia. `CONFIG_PID_NS`, `CONFIG_IPC_NS` y
`CONFIG_POSIX_MQUEUE` no alteran `task_struct`; `CONFIG_USER_NS` tampoco mueve
el ABI en 6.6.

### Variantes del parche

Los números **no son versiones del kernel**, son slots de padding:

| Archivo | Slots usados |
|---|---|
| `001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch` | 6, 7, 8 (por defecto) |
| `001.GKI-below-6.12-fix_sysvipc_kabi_3_4_5.patch` | 3, 4, 5 |
| `001.GKI-below-6.12-fix_sysvipc_kabi_1_2_3.patch` | 1, 2, 3 |

Si el dispositivo bootloopea con la variante por defecto, probar las otras dos.
El kernel de ruby ya usa algunos slots para MTK, así que puede hacer falta una
variante distinta.

## Configuración

```sh
# 1. parche kABI
patch -p1 < droidspaces/patches/001.GKI-below-6.12-fix_sysvipc_kabi_6_7_8.patch

# 2. fusionar el fragmento sobre el defconfig del árbol
scripts/kconfig/merge_config.sh -m arch/arm64/configs/ruby_defconfig \
    configs/droidspaces.fragment
make ARCH=arm64 olddefconfig
```

No activar `CFS_BANDWIDTH` ni `CGROUP_PIDS`: sin parche posible, rompen el ABI.
Droidspaces seguirá funcionando; solo se pierden `--cpus` y `--pids-limit`
(la app los deshabilita con aviso). `CONFIG_MEMCG` ya está activo, así que los
límites de memoria sí funcionan.

## Verificación

En el dispositivo, con el kernel nuevo:

```sh
zcat /proc/config.gz | grep -E 'CONFIG_(SYSVIPC|POSIX_MQUEUE|PID_NS|IPC_NS|USER_NS)='
unshare -p -f --mount-proc echo ok     # PID ns
unshare -i echo ok                     # IPC ns
unshare -U echo ok                     # user ns
droidspaces check                      # 0 must-have ausentes
dmesg | grep -i 'disagrees about version'
```

Si aparece `disagrees about version of symbol`, el parche kABI elegido no es el
correcto o se activó algo que mueve el ABI. **No** desactivar
`CONFIG_MODVERSIONS` ni forzar módulos: enmascara el problema y puede corromper
memoria.

## Estado en ruby

Bloqueado por fuentes, no por configuración. Ver [`../STATUS.md`](../STATUS.md).
