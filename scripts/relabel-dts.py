#!/usr/bin/env python3
"""Reemplaza phandles numéricos por etiquetas usando el nodo __symbols__.

    ./scripts/relabel-dts.py entrada.dts salida.dts

dtc no conserva las etiquetas al decompilar, pero el FDT vivo de Android sí
trae __symbols__ (label -> ruta). Este script reconstruye la relación
phandle -> etiqueta y reescribe las referencias para que el DTS sea editable.
"""
import re
import sys


def parse(text):
    """Devuelve (path -> phandle, label -> path)."""
    path_phandle = {}
    symbols = {}
    stack = []
    in_symbols = False
    depth = 0

    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("//"):
            continue

        if in_symbols:
            m = re.match(r'([\w,.-]+)\s*=\s*"([^"]+)"\s*;', line)
            if m:
                symbols[m.group(1)] = m.group(2)
            depth += line.count("{") - line.count("}")
            if depth <= 0:
                in_symbols = False
            continue

        if line == "__symbols__ {":
            in_symbols = True
            depth = 1
            continue

        if line.endswith("{"):
            name = line[:-1].strip().split()[-1]
            stack.append(name)
            continue

        if line.startswith("}"):
            if stack:
                stack.pop()
            continue

        m = re.match(r'phandle\s*=\s*<(0x[0-9a-fA-F]+)>', line)
        if m and stack:
            path = re.sub(r'/+', '/', "/" + "/".join(stack))
            path_phandle[path] = int(m.group(1), 16)

    return path_phandle, symbols


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
    path_phandle, symbols = parse(text)

    phandle_label = {}
    for label, path in symbols.items():
        ph = path_phandle.get(path)
        if ph is not None and ph not in phandle_label:
            phandle_label[ph] = label

    if not phandle_label:
        sys.exit("no se pudo reconstruir ningún phandle")

    def repl(m):
        val = int(m.group(1), 16)
        label = phandle_label.get(val)
        return f"&{label}" if label else m.group(0)

    # Solo propiedades que son inequívocamente un phandle único. Reescribir
    # todas las celdas rompe valores como #address-cells o plat_dbg_info,size.
    single = re.compile(
        r'(interrupt-parent|memory-region|syscon|.*-supply|.*-gpios?|'
        r'.*-parent|.*-handle|.*-reset)$'
    )

    out = []
    for line in text.splitlines():
        m = re.match(r'^(\s*)([\w,.#+-]+)(\s*=\s*)<([^<>]*)>(\s*;.*)$', line)
        if m and single.match(m.group(2)):
            cells = m.group(4).strip().split()
            if len(cells) == 1:
                line = (m.group(1) + m.group(2) + m.group(3) + "<" +
                        re.sub(r'0x([0-9a-fA-F]+)', repl, cells[0]) + ">" +
                        m.group(5))
        out.append(line)

    open(sys.argv[2], "w", encoding="utf-8").write("\n".join(out) + "\n")
    print(f"{len(phandle_label)} etiquetas, {len(path_phandle)} nodos con phandle")


if __name__ == "__main__":
    main()
