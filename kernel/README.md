# kernel/common — ACK 6.6.127

Submódulo que apunta al kernel común de AOSP, la base GKI exacta del kernel de
ruby:

```
url     https://android.googlesource.com/kernel/common
tag     android15-6.6-2026-04_r31
commit  9219fdbf541af7cadec566a17df0c3e6b1a0be52
versión 6.6.127
```

```sh
git submodule update --init --depth 1 kernel/common
```

## Qué incluye y qué no

Incluye el núcleo GKI (scheduler, MM, VFS, red, namespaces, cgroup, seccomp,
drivers genéricos). **No incluye** el BSP de MediaTek:

- `CONFIG_MTK_PLATFORM="mt6877"` y 205 `CONFIG_MTK_*`;
- DRM/DSI, PMIC mt6359p, táctil, cámara, conectividad, almacenamiento;
- el `mt6877.dts` y el overlay `ruby` del build real (están en
  `extracted/dts/`).

Por eso compilar este submódulo produce un GKI genérico, no un kernel para
ruby. El árbol que sí sirve es `kernel/xiaomi/mt6877` de la rama
`lineage-24.0`, que no está publicado (ver [`../STATUS.md`](../STATUS.md)).

## Por qué este tag

El kernel stock es `6.6.127-android15-8-4k`. El tag
`android15-6.6-2026-04_r31` es el último parche de la línea 6.6.127 en ACK
(`SUBLEVEL = 127`), aunque el build real sea de octubre. Coincide en versión,
KMI 8 y páginas de 4K.
