#!/usr/bin/env python3
"""Audita los CRC que los .ko del vendor exigen al kernel.

    ./scripts/audit-modversions.py [dir_de_ko] [salida]

No fabrica un Module.symvers completo: `__versions` solo contiene los símbolos
que cada módulo IMPORTA, con el CRC de su firma de tipos en el build original.
Sirve para auditar el ABI, detectar conflictos entre módulos y comparar contra
un kernel recién compilado. Un Module.symvers real lo genera el build del
kernel con genksyms; no se puede reconstruir desde los .ko.
"""
import subprocess
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODS = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "work/vendor_root/lib/modules"
OUT = Path(sys.argv[2]) if len(sys.argv) > 2 else ROOT / "work/blueprint_analysis"


def sh(*args):
    return subprocess.run(args, capture_output=True, text=True, check=False)


def main():
    if not MODS.is_dir():
        sys.exit(f"no existe {MODS} (extrae vendor.img primero)")
    OUT.mkdir(parents=True, exist_ok=True)

    kos = sorted(MODS.rglob("*.ko"))
    if not kos:
        sys.exit(f"no hay .ko en {MODS}")

    vermagic = None
    crcs = defaultdict(set)
    rows = []

    for ko in kos:
        if vermagic is None:
            r = sh("modinfo", "-F", "vermagic", str(ko))
            if r.stdout.strip():
                vermagic = r.stdout.strip()

        r = sh("modprobe", "--dump-modversions", str(ko))
        if r.returncode != 0:
            print(f"[!] {ko.name}: {r.stderr.strip()}", file=sys.stderr)
            continue
        for line in r.stdout.splitlines():
            parts = line.split()
            if len(parts) != 2:
                continue
            crc, sym = parts[0], parts[1]
            crcs[sym].add(crc)
            rows.append((sym, crc, ko.name))

    rows.sort()
    with (OUT / "module-crcs.tsv").open("w") as f:
        f.write("symbol\tcrc\tmodule\n")
        for sym, crc, mod in rows:
            f.write(f"{sym}\t{crc}\t{mod}\n")

    conflicts = {s: c for s, c in crcs.items() if len(c) > 1}
    with (OUT / "crc-conflicts.txt").open("w") as f:
        for sym, vals in sorted(conflicts.items()):
            f.write(f"{sym}\t{','.join(sorted(vals))}\n")

    if vermagic:
        (OUT / "vermagic.txt").write_text(vermagic + "\n")
        (OUT / "uts_release.txt").write_text(vermagic.split()[0] + "\n")

    report = [
        f"módulos: {len(kos)}",
        f"símbolos importados únicos: {len(crcs)}",
        f"referencias totales: {len(rows)}",
        f"conflictos de CRC: {len(conflicts)}",
        f"vermagic: {vermagic or '?'}",
    ]
    (OUT / "report.txt").write_text("\n".join(report) + "\n")
    print("\n".join(report))
    print(f"\nResultados en {OUT}")


if __name__ == "__main__":
    main()
