"""The fitter of the Second Sight link: it puts the asset sections into the
free spaces of src/secondsight/secondsight.ld.

The Makefile links twice:
    secondsight_fit.py park PLACEMENTS OBJECT...
        writes PLACEMENTS, which parks the asset sections for the first link
        (each at 0, loading nothing).
    secondsight_fit.py place PLACEMENTS FIRST_LINK OBJECT...
        reads the free spaces of the first link (the fit_NAME__* symbols of
        secondsight.ld) and writes PLACEMENTS for the final link.

The allocator packs each asset section into the free space where its kind may
live, largest first into the tightest free space, and keeps the rules of the
kind (one 4 KB page, one video RAM window). It stops with a report when a
section has no place. A section's size does not change with its address, so
the first link gives the final free space.

Addresses are load addresses: 0x100000 + physical SRAM, or linear video RAM.
"""

import re
import sys
from pathlib import Path

import elf32

SRAM = 0x100000  # load address of SRAM byte 0 (secondsight.ld load_sram)
PAGE = 0x1000  # an MMU page

# The kinds of placeable sections, by name prefix (secondsight.ld FIT_KIND):
#   record:  banked data read through the bank area; stays in one 4 KB page.
#   common:  data that the CPU reads at its logical address.
#   vram:    linear video RAM; .vram.bN_aA_kK.NAME stays inside one window
#            of N groups (4 bytes each), aligned to A, out of the first K
#            groups of each 64K-group segment.
KINDS = (
    (".vram.", "vram"),
    (".common.", "common"),
    (".desc.", "record"),
)


class Space:
    """Free card memory: [start, end) load addresses, the kinds it takes, and
    the label of a record at its start."""

    def __init__(self, name, start, end, kinds, label):
        self.name = name
        self.free = [[start, end]]
        self.kinds = kinds
        self.run = label - start  # record label - load address

    def fits(self, size, align, kind, window=None, keep=0):
        """Free intervals and the first address in each that takes SIZE."""
        for interval in self.free:
            at = (interval[0] + align - 1) & -align
            # Keep out of the first KEEP groups of each 64K-group segment.
            if keep and (at >> 2) & 0xFFFF < keep:
                at = (((at >> 18) << 18) + keep * 4 + align - 1) & -align
            boundary = PAGE if kind == "record" else window
            if boundary and size <= boundary and (at & (boundary - 1)) + size > boundary:
                at = (at + boundary - 1) & -boundary
            if at + size <= interval[1]:
                yield interval, at

    def take(self, interval, at, size):
        self.free.remove(interval)
        self.free += [r for r in ([interval[0], at], [at + size, interval[1]]) if r[0] < r[1]]
        self.free.sort()

    def run_address(self, at, kind):
        if kind == "common":
            # The CPU address: the physical one, moved by the space's label
            # (fit_NAME__label = load_sram + the logical address of the start).
            return at + self.run - SRAM
        if kind == "vram":
            return at
        return at + self.run


def kind_of(name):
    return next((kind for prefix, kind in KINDS if name.startswith(prefix)), None)


def free_spaces(first_link):
    """The free spaces of the first link (fit_NAME__* symbols)."""
    symbols = elf32.global_symbols(Path(first_link))
    # The kinds that the memory map uses: FIT_KIND symbols (secondsight.ld).
    flags = {
        kind: symbols[f"FIT_{kind.upper()}"]
        for kind in ("record", "common", "vram")
        if f"FIT_{kind.upper()}" in symbols
    }
    spaces = []
    for name in sorted({m.group(1) for m in map(re.compile(r"fit_(\w+)__start$").match, symbols) if m}):
        value = {key: symbols.get(f"fit_{name}__{key}") for key in ("start", "end", "label", "kinds", "align")}
        align = value["align"] or 1
        start = (value["start"] + align - 1) & -align
        label = value["label"] + start - value["start"]
        kinds = {kind for kind, flag in flags.items() if value["kinds"] & flag}
        spaces.append(Space(name, start, value["end"], kinds, label))
    spaces.sort(key=lambda space: space.free[0][0])
    return spaces


def place(sections, spaces):
    """SECTIONS: (object, section name, size, alignment). The output section
    lines that place each."""
    items = []
    for obj, name, size, align in sections:
        kind = kind_of(name)
        window = keep = None
        if kind == "vram":
            rule = {part[0]: int(part[1:]) for part in name.split(".")[2].split("_")}
            # A section larger than its window stays inside one 64 KB segment.
            window = 4 * rule["b"]
            window = window if size <= window else 0x10000
            align = max(align, rule.get("a", 4))
            keep = rule.get("k", 0)
        if kind and size:
            items.append((kind, obj, name, size, max(align, 1), window, keep))
    items.sort(key=lambda item: (-item[3], item[2]))  # largest first
    lines = ["/* Generated by scripts/secondsight_fit.py: the placed asset sections. */"]
    for i, (kind, obj, name, size, align, window, keep) in enumerate(items):
        options = [
            (interval[1] - interval[0], space, interval, at)
            for space in spaces
            if kind in space.kinds
            for interval, at in space.fits(size, align, kind, window, keep)
        ]
        options.sort(key=lambda o: o[0])
        if not options:
            report = "\n".join(
                f"  {s.name}: " + ", ".join(f"0x{a:X}-0x{b:X} ({b - a})" for a, b in s.free) for s in spaces
            )
            raise SystemExit(f"no free card memory for {name} ({kind}, {size} bytes). Free:\n{report}")
        _, space, interval, at = options[0]
        space.take(interval, at, size)
        lines.append(f"  .asset.p{i} 0x{space.run_address(at, kind):X} : AT(0x{at:X}) {{ {obj}({name}) }}")
    return lines


def park(sections):
    """The output section lines of the first link: every asset section at 0,
    loading nothing."""
    lines = ["/* Generated by scripts/secondsight_fit.py: the asset sections, parked for the first link. */"]
    for i, (obj, name, _, _) in enumerate(sections):
        if kind_of(name) is not None:
            lines.append(f"  .park.{i} 0x0 (NOLOAD) : {{ {obj}({name}) }}")
    return lines


def main(args):
    if len(args) >= 2 and args[0] == "park":
        command, placements, objects = args[0], args[1], args[2:]
    elif len(args) >= 3 and args[0] == "place":
        command, placements, first_link, objects = args[0], args[1], args[2], args[3:]
    else:
        raise SystemExit("usage: secondsight_fit.py park PLACEMENTS OBJECT... | place PLACEMENTS FIRST_LINK OBJECT...")
    sections = [(obj, *part) for obj in objects for part in elf32.section_list(Path(obj))]
    if command == "park":
        lines = park(sections)
    else:
        lines = place(sections, free_spaces(first_link))
    Path(placements).write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main(sys.argv[1:])
