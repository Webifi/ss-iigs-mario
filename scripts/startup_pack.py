"""Bounded LZ blocks for startup uploads only; gameplay never decodes these.

A low token stores 1..128 literal bytes. A high token stores a 3..130 byte
copy followed by its 16-bit backward distance. Blocks are at most 16 KB.

"startup_pack.py IN OUT" writes the packed form of file IN to OUT (the
Makefile packs the linked helpers with it).
"""

import sys
from collections import defaultdict, deque
from functools import lru_cache
from pathlib import Path


def _pack(data, lazy=False):
    out = bytearray()
    chains = defaultdict(lambda: deque(maxlen=32))
    literal = bytearray()
    i = 0

    def flush():
        if literal:
            out.append(len(literal) - 1)
            out.extend(literal)
            literal.clear()

    def remember(p):
        if p + 3 <= len(data):
            chains[data[p : p + 3]].append(p)

    def match(p):
        best = 0
        distance = 0
        for old in reversed(chains.get(data[p : p + 3], ())):
            n = 3
            limit = min(130, len(data) - p)
            while n < limit and data[old + n] == data[p + n]:
                n += 1
            if n > best:
                best = n
                distance = p - old
            if n == limit:
                break
        return best, distance

    while i < len(data):
        best, distance = match(i)
        # One literal can expose a much longer existing match. This is a
        # build-only parse choice; the on-card format and decoder stay fixed.
        if lazy and 4 <= best < 128 and match(i + 1)[0] > best + 1:
            best = 0
        if best >= 4:
            flush()
            out.append(128 + best - 3)
            out.extend(distance.to_bytes(2, "little"))
            for p in range(i, i + best):
                remember(p)
            i += best
        else:
            literal.append(data[i])
            remember(i)
            i += 1
            if len(literal) == 128:
                flush()
    flush()
    return bytes(out)


def pack(data):
    return _packed(bytes(data))


@lru_cache(maxsize=512)
def _packed(data):
    assert len(data) <= 16384
    result = min((_pack(data), _pack(data, True)), key=len)
    assert unpack(result) == data
    return result


def unpack(data):
    out = bytearray()
    i = 0
    while i < len(data):
        header = data[i]
        i += 1
        if header & 128:
            n = (header & 127) + 3
            distance = int.from_bytes(data[i : i + 2], "little")
            i += 2
            assert 0 < distance <= len(out)
            for _ in range(n):
                out.append(out[-distance])
        else:
            n = header + 1
            out.extend(data[i : i + n])
            i += n
    return bytes(out)


if __name__ == "__main__":
    Path(sys.argv[2]).write_bytes(pack(Path(sys.argv[1]).read_bytes()))
