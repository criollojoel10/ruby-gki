# 07 — Por qué SysV IPC/PID ns no pueden ser un módulo

Resumen: Droidspaces exige **PID namespace** e **IPC namespace** reales. No
son drivers que se puedan cargar: son infraestructura del núcleo que en este
kernel **no está compilada**. Un `.ko` o un KPM no puede añadirla sin cambiar
el núcleo.

## Evidencia en el kernel vivo

De `/proc/config.gz` (y de `configs/ruby_defconfig`):

```
# CONFIG_USER_NS is not set
# CONFIG_PID_NS is not set
# CONFIG_SYSVIPC is not set
# CONFIG_POSIX_MQUEUE is not set
# CONFIG_IPC_NS no aparece: no está definida
```

En `kallsyms` del `Image` original (184 347 símbolos) hay **0** símbolos
`exit_sem`, `shm_exit`, `create_ipc_ns`, `copy_ipcs` o `pid_namespace`.

## Evidencia en el código (ACK 6.6.127)

`kernel/Makefile`:

```make
obj-$(CONFIG_PID_NS) += pid_namespace.o
```

`ipc/Makefile`:

```make
obj-$(CONFIG_SYSVIPC) += util.o msgutil.o msg.o sem.o shm.o syscall.o
obj-$(CONFIG_POSIX_MQUEUE) += mqueue.o msgutil.o
obj-$(CONFIG_IPC_NS) += namespace.o
```

Son `bool`. No existe `obj-m` para `ipc/` ni para `pid_namespace.o`. Compilar
esos directorios como módulo no está soportado por Kbuild.

## Qué pasa exactamente con `clone(CLONE_NEWPID)` / `unshare(CLONE_NEWIPC)`

`kernel/nsproxy.c` acepta los flags, pero las funciones que crean los
namespaces son stubs cuando la opción está apagada. En
`include/linux/pid_namespace.h`:

```c
#ifdef CONFIG_PID_NS
extern struct pid_namespace *copy_pid_ns(...);
#else
static inline struct pid_namespace *copy_pid_ns(...)
{
	return get_pid_ns(ns);   /* devuelve el namespace actual */
}
#endif
```

Resultado: el proceso “clona” pero sigue en el mismo PID namespace. No hay
PID 1 propio, no hay `/proc/<pid>` aislado y no aparece
`/proc/self/ns/pid`.

Para IPC, con `CONFIG_IPC_NS=n` no se compila `ipc/namespace.o`; no hay
`create_ipc_ns`, no hay `unshare(CLONE_NEWIPC)` efectivo y no existe
`/proc/self/ns/ipc`.

## Por qué un KPM no lo arregla

Un KPM puede enganchar syscalls (`fp_hook_syscalln`) y añadir llamadas nuevas,
pero Droidspaces no solo necesita `msgget`/`semget`: necesita **aislamiento**.
Para eso haría falta:

1. añadir estado por namespace a `task_struct`/`nsproxy`;
2. integrarlo en `copy_process`, `unshare`, `setns`, `exit_task_namespaces`;
3. crear `/proc/self/ns/pid` e `/proc/self/ns/ipc`;
4. hacer que `getpid()` devuelva el PID del namespace y que el hijo sea PID 1;
5. limpiar semáforos y shm al salir de cada proceso.

Los puntos 1-3 son código del núcleo, no de un módulo. El kABI solo reserva
**punteros** en `task_struct`; no añade campos a `nsproxy`, ni las tablas de
PID, ni los ganchos de `do_exit`. Un KPM que emule SysV IPC por su cuenta
seguiría sin superar el `droidspaces check` de PID/IPC namespace.

## Sobre el bypass de CRC

`kernel/module/version.c` en 6.6.127 sí tiene la firma que citas:

```c
int check_version(const struct load_info *info, const char *symname,
                  struct module *mod, const s32 *crc)
```

Pero no hace falta tocarla. El parche kABI mueve `sysv_sem`/`sysv_shm` a los
slots 6-8, así que el layout de `task_struct` no cambia y los CRC de los
símbolos exportados deberían coincidir. Si no coinciden, el bypass solo
esconde una diferencia real de tipos o configuración, y puede provocar
corrupción de memoria.

Además, `check_version` también valida `module_layout`; devolver 1 siempre
desactiva esa comprobación. Si hay que depurar, comparar `modinfo` y
`__versions` antes de parchear.

## El `.ko` de `ipc/` en concreto: por qué no puede funcionar

La propuesta de compilar `ipc/*.c` como `droidspaces_ipc.ko` y enganchar
`do_exit`/`sys_call_table` falla en varios puntos independientes:

1. **Los símbolos del núcleo no existen.** `kallsyms` del `Image` original:

   ```
   exit_sem          AUSENTE
   shm_exit          AUSENTE
   ipc_init          AUSENTE
   ipc_ns_init       AUSENTE
   init_ipc_ns       AUSENTE
   ```

   El módulo los declara `extern`; modpost los marca `undefined!` y `insmod`
   falla con `Unknown symbol`. No se pueden enlazar funciones que el kernel no
   compiló.

2. **Las syscalls son stubs, no implementaciones.** `kernel/sys_ni.c`:

   ```c
   COND_SYSCALL(msgget);
   ```

   Eso genera `__arm64_sys_msgget` como alias **weak** de `sys_ni_syscall`
   (comprobado: `W __arm64_sys_msgget` apunta a `T sys_ni_syscall`). Enganchar
   la tabla a esas direcciones solo devuelve `-ENOSYS`.

3. **`task_struct` del kernel vivo no tiene `sysvsem`.** Compilar el módulo con
   `-DCONFIG_SYSVIPC=1` cambia la definición de `struct task_struct` **solo
   para el módulo**; el kernel en ejecución se compiló sin esos campos. El
   módulo leería offsets que en el kernel son otra cosa. Aplicar el parche
   kABI a los headers no cambia el binario que está corriendo.

4. **El parche kABI no aplica con `git apply`.** En ACK
   `android15-6.6-2026-04_r31` falla:

   ```
   error: patch failed: include/linux/sched.h:1513
   error: include/linux/sched.h: patch does not apply
   ```

   `git apply` es estricto con el fuzz; `patch -p1` sí aplica. El script
   propuesto usa `git apply ... || echo "ya aplicado"`, así que **continuaría
   sin parche** y sin avisar.

5. **`ipc_init`/`ipc_ns_init` son `__init`.** Aunque se compilaran, su memoria
   se libera al terminar el arranque; llamarlas desde un módulo es
   use-after-free.

6. **`Module.symvers` reconstruido no es un Module.symvers.** `__versions`
   solo tiene los símbolos que cada `.ko` importa: 1439 únicos, 4124
   referencias, 0 conflictos de CRC en los 78 módulos. Un Module.symvers real
   contiene todos los exports y lo genera genksyms al compilar el kernel; no
   se puede fabricar desde los `.ko`. Sirve para auditar, no para enlazar.

7. **Aunque todo lo anterior funcionara, falta PID namespace.** En el kernel
   vivo:

   ```
   $ ls /proc/self/ns/
   cgroup mnt net time uts          # no hay pid, ipc ni user
   $ unshare -i true                # Invalid argument
   $ unshare -p -f true             # Invalid argument
   $ unshare -U true                # Invalid argument
   ```

   Droidspaces exige PID e IPC namespace como *must-have*. Sin recompilar el
   núcleo, el `check` seguirá fallando aunque exista `/proc/sysvipc`.

## Auditoría correcta (lo que sí se puede hacer)

`scripts/audit-modversions.py` extrae `vermagic` y los CRC de `__versions` de
los 78 `.ko` (auditoría de ABI, detección de conflictos), sin presentarlo como
un Module.symvers utilizable para enlazar. Resultado actual:

```
módulos: 78
símbolos importados únicos: 1439
referencias totales: 4124
conflictos de CRC: 0
vermagic: 6.6.127-android15-8-4k-gf18ad88fac49-dirty SMP preempt mod_unload modversions aarch64
```

## Lo que sí es cierto de tu análisis

- Los 78 `.ko` no van en `Image` (en ruby están en `vendor.img`, no en
  `vendor_boot`/`vendor_dlkm`, que no existen).
- Solo faltan los `.c` compilados `=y` fuera de ACK: **302** opciones.
- El BSP del A34 cubre al menos **181** de esas 302.
- El DTS vivo con `__symbols__` y `kheaders` ahorran buena parte del trabajo
  de portar estructuras y bindings.

Ver [`06-bsp-a34.md`](06-bsp-a34.md) para el plan de build.
