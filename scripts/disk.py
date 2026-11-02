"""The disk step, after the links: the card load records from
build/secondsight/secondsight.elf, the boot volume (scripts/boot_disk.py)
and the debug symbol file.

The card load records hold every loaded byte of the Second Sight program:
the program image in SRAM bank 1, the pattern tables, and the tile art in
video RAM (src/secondsight/secondsight.ld). None of them touches what the
firmware uses while it loads them.
"""

import boot_disk
import debug_symbols
import elf32
from roms import ROOT

PART = 16384  # the most bytes of one card load record


def card_records(elf):
    """(load address, bytes) of the card load records."""
    sections = elf32.loads(elf)
    loads = []
    for _, load, data in sorted(sections.values(), key=lambda v: v[1]):
        if loads and loads[-1][0] + len(loads[-1][1]) > load:
            raise RuntimeError(f"card load records overlap at {load:06X}")
        if loads and loads[-1][0] + len(loads[-1][1]) == load:
            loads[-1] = (loads[-1][0], loads[-1][1] + data)
        else:
            loads.append((load, data))
    records = []
    for address, data in loads:
        for offset in range(0, len(data), PART):
            records.append((address + offset, bytes(data[offset : offset + PART])))
    return records


def main():
    game, disk = ROOT / "build/game", ROOT / "build/game-disk"
    records = card_records(ROOT / "build/secondsight/secondsight.elf")
    (game / "card-startup.bin").write_bytes(
        b"".join(a.to_bytes(3, "little") + len(d).to_bytes(3, "little") + d for a, d in records) + bytes(6)
    )
    boot_disk.build(game, disk)
    debug_symbols.write(game, disk / "debug.sym")


if __name__ == "__main__":
    main()
