"""The debug symbol file of a build: every address that an emulator debug
run needs, so a run reads the state of the game from outside it.

The game itself holds no diagnostic state. Each line of the file is one of:
    host NAME ADDRESS    a 65816 label or equate of the game (ld65 debug file)
    boot NAME ADDRESS    a 65816 label or equate of the boot loader
    card NAME ADDRESS    a Second Sight Z180 symbol (secondsight.elf)
    area NAME START END  a 65816 code and data area of src/iigs.cfg, END exclusive
ADDRESS, START and END are hexadecimal. A scoped host name is SCOPE::NAME.
"""

import re

from iigs_payload import areas


def host_symbols(path):
    scopes, symbols = {}, {}
    rows = []
    for line in path.read_text().splitlines():
        kind, _, rest = line.partition("\t")
        fields = dict(re.findall(r'(\w+)=("[^"]*"|[^,]*)', rest))
        if kind == "scope":
            scopes[fields["id"]] = (fields["name"].strip('"'), fields.get("parent"))
        elif kind == "sym" and "val" in fields and fields.get("type") in ("lab", "equ"):
            rows.append(fields)

    def qualified(scope):
        name, parent = scopes.get(scope, ("", None))
        if not name:
            return ""
        outer = qualified(parent) if parent is not None else ""
        return f"{outer}{name}::"

    for fields in rows:
        name = fields["name"].strip('"')
        if name.startswith("@") or not name:
            continue
        symbols[qualified(fields.get("scope", "0")) + name] = int(fields["val"], 16)
    return symbols


def card_symbols(path):
    out = {}
    for line in path.read_text().splitlines():
        m = re.match(r"^secondsight_(\w+) = \$([0-9A-Fa-f]+)$", line)
        if m:
            out[m[1]] = int(m[2], 16)
    return out


def write(case, path):
    """Write the symbol file of the build in folder CASE (build/game) to PATH."""
    lines = ["; Debug symbols of this build (scripts/debug_symbols.py)."]
    lines += [f"area {n} {a:06x} {a + s:06x}" for n, (a, s) in sorted(areas(case / "host.lbl").items())]
    lines += [f"host {n} {v:06x}" for n, v in sorted(host_symbols(case / "host.dbg").items())]
    lines += [f"boot {n} {v:06x}" for n, v in sorted(host_symbols(path.parent / "boot.dbg").items())]
    lines += [f"card {n} {v:06x}" for n, v in sorted(card_symbols(case / "secondsight_symbols.inc").items())]
    path.write_text("\n".join(lines) + "\n")
