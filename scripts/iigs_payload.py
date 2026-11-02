"""The host data of the asset builder, as sources for the IIgs link.

The asset builder gives the host data as blobs (blob_at and the others). Each
blob goes into a segment of src/iigs.cfg with room for it, by its rule; the
room of each area comes from the label file of a link of the config alone
(build/game/areas/areas.lbl, the __NAME_START__ and __NAME_SIZE__ symbols).
save() writes the blobs as build/game/host_data.s, host_data.bin and
host_data.inc; "make iigs" links them with the 65816 program (src/game.s).
"""

import re

BANK = 0x10000  # a 65816 bank: a blob stays inside one

# The segments of each rule, in the order of use: the areas of src/iigs.cfg
# with these names that the map has (Host.__init__).
DATA_PREFIX = "DATA"  # DATA03, DATA04, ...: the payload banks
GAME = ["GAMEDATA"]  # the original's tables: data that the game logic reads in bank 0
# A segment whose area has another name (a segment that loads in one place
# and runs in another: the room is the room of its run area).
AREA_OF = {"GAMEDATA": "GAMEDATA_RUN"}
SIZES = {"byte": 1, "word": 2, "faraddr": 3}  # bytes of each HostData directive


class Address:
    """A host address: the label of host data, plus an offset. Host data
    refers to other host data by label; ld65 gives the values."""

    def __init__(self, label):
        self.label = label


class HostData:
    """Host data: bytes and values (numbers, Addresses or ca65 expressions)."""

    def __init__(self):
        self.parts = []  # (kind, values)

    def _add(self, kind, values):
        self.parts.append((kind, values))
        return self

    def byte(self, *values):
        return self._add("byte", values)

    def word(self, *values):
        return self._add("word", values)

    def faraddr(self, *values):
        return self._add("faraddr", values)

    def data(self, raw):
        return self._add("data", bytes(raw))

    def size(self):
        """The bytes of the data."""
        return sum(len(values) if kind == "data" else SIZES[kind] * len(values) for kind, values in self.parts)

    __len__ = size

    def source(self, incbin):
        """The ca65 lines of the data; INCBIN(bytes) gives the line of raw bytes."""
        value = lambda v: v.label if isinstance(v, Address) else v if isinstance(v, str) else f"${v:X}"
        lines = []
        for kind, values in self.parts:
            if kind == "data":
                lines += incbin(values)
            else:
                lines.append(f"  .{kind} " + ", ".join(value(v) for v in values))
        return lines


def areas(labels):
    """{area: (start, size)} of the ld65 label file LABELS (define = yes)."""
    symbols, found = {}, {}
    for value, name in re.findall(r"^al ([0-9A-Fa-f]+) \.__(\w+)__$", labels.read_text(), re.MULTILINE):
        symbols[name] = int(value, 16)
    for name, start in symbols.items():
        if name.endswith("_START"):
            area = name[: -len("_START")]
            found[area] = (start, symbols[f"{area}_SIZE"])
    return found


class Host:
    def __init__(self, out):
        self.out = out
        out.mkdir(parents=True, exist_ok=True)
        self.area = areas(out / "areas/areas.lbl")  # area -> (start, size)
        for segment, area in AREA_OF.items():
            if area in self.area:
                self.area[segment] = self.area[area]
        self.used = dict.fromkeys(self.area, 0)
        self.data = sorted(a for a in self.area if a.startswith(DATA_PREFIX))
        self.game = [a for a in GAME if a in self.area]
        self.segments = {}  # segment -> [(label, data, end)]: the blobs in order
        self.names = set()
        self.imports = set()  # labels of the IIgs program that host data names (.global in host_data.s)

    def _fit(self, data, name, segments, length=None):
        """DATA in the first of SEGMENTS with room: its Address. LENGTH names
        a 16-bit constant: the bytes of the blob (LABEL_END - LABEL)."""
        size = len(data)
        segment = next((s for s in segments if self.used[s] + size <= self.area[s][1]), None)
        if segment is None:
            room = ", ".join(f"{s} {self.area[s][1] - self.used[s]}" for s in segments)
            raise RuntimeError(f"no room for host data {name} ({size} bytes). Free: {room}")
        assert size <= BANK
        self.used[segment] += size
        label = name or f"host_data_{len(self.names)}"
        assert label not in self.names, label
        self.names.add(label)
        self.segments.setdefault(segment, []).append((label, data, length))
        return Address(label)

    def blob_at(self, data, name=None, length=None):
        """DATA in the payload, inside one bank."""
        return self._fit(data, name, self.data, length)

    def game_blob_at(self, data, name=None, length=None):
        """DATA in bank 0 (GAMEDATA), after the blobs before it: the game
        logic reads it with absolute addresses. LENGTH names its size
        (blob_at)."""
        return self._fit(data, name, self.game, length)

    def write(self, name, data):
        """Write DATA (bytes or text) to build/game/NAME only when it differs:
        a file that does not change keeps its time, so make does not assemble
        or link again."""
        path = self.out / name
        data = data.encode() if isinstance(data, str) else bytes(data)
        if not (path.exists() and path.read_bytes() == data):
            path.write_bytes(data)

    def save(self):
        """host_data.s, host_data.bin and host_data.inc: the blobs of each
        segment in order. A segment in bank 0 is absolute, the others far."""
        raw = bytearray()

        def incbin(data):
            raw.extend(data)
            return [f'  .incbin "host_data.bin", {len(raw) - len(data)}, {len(data)}'] if data else []

        # Bank 0: 16-bit labels (the game logic reads its data with DBR = 0);
        # the other banks: 24-bit labels.
        size = lambda segment: "absolute" if self.area[segment][0] < BANK else "far"
        lines = [
            "; Generated by scripts/iigs_payload.py: the host data.",
            ".p816",
            '.include "packet_layout.inc"',  # the record kinds of the screen records (scripts/screen_data.py)
            '.include "host_data.inc"',
            *(f".global {name}" for name in sorted(self.imports)),
        ]
        names = []
        for segment in self.game + self.data:
            if not self.segments.get(segment):
                continue
            lines.append(f'.segment "{segment}": {size(segment)}')
            for label, data, length in self.segments[segment]:
                names.append(f".global {label}: {size(segment)}")
                lines.append(f"{label}:")
                if isinstance(data, HostData):
                    lines += data.source(incbin)
                else:
                    lines += incbin(bytes(data))
                if length:
                    names.append(f".global {length}: absolute")
                    lines += [f"{label}_END:", f"{length} = .loword({label}_END-{label})"]
        self.write("host_data.bin", raw)
        self.write("host_data.s", "\n".join(lines) + "\n")
        self.write("host_data.inc", "; Generated by scripts/iigs_payload.py: the labels of the host data.\n" + "\n".join(names) + "\n")
