"""Read 32-bit little-endian ELF files: object files and executables of
GNU binutils."""

import struct

SHT_PROGBITS, SHT_SYMTAB, SHT_NOBITS = 1, 2, 8
SHN_UNDEF = 0


def read(path):
    """The bytes and section headers of a 32-bit little-endian ELF file, and
    a function that reads a name from a string table."""
    data = path.read_bytes()
    assert data[:6] == b"\x7fELF\x01\x01", path
    (offset,) = struct.unpack_from("<I", data, 0x20)
    size, count, names = struct.unpack_from("<HHH", data, 0x2E)
    headers = [struct.unpack_from("<10I", data, offset + i * size) for i in range(count)]

    def string(table, at):
        start = headers[table][4] + at
        return data[start : data.index(b"\0", start)].decode()

    return data, headers, lambda header: string(names, header[0]), string


def loads(path):
    """Run address, load address and contents of each PROGBITS section of an
    executable: the load address comes from the program header that holds it."""
    data, headers, name, _ = read(path)
    (offset,) = struct.unpack_from("<I", data, 0x1C)
    size, count = struct.unpack_from("<HH", data, 0x2A)
    segments = [struct.unpack_from("<8I", data, offset + i * size) for i in range(count)]
    loads = {}
    for h in headers:
        if h[1] != SHT_PROGBITS or not h[5]:
            continue
        segment = next(s for s in segments if s[0] == 1 and s[1] <= h[4] < s[1] + s[4])
        loads[name(h)] = (h[3], segment[3] + h[4] - segment[1], data[h[4] : h[4] + h[5]])
    return loads


def global_symbols(path):
    data, headers, _, string = read(path)
    table = next(h for h in headers if h[1] == SHT_SYMTAB)
    found = {}
    for at in range(table[4], table[4] + table[5], 16):
        st_name, value, _, info, _, index = struct.unpack_from("<IIIBBH", data, at)
        label = string(table[6], st_name)
        if info >> 4 == 1 and index != SHN_UNDEF:
            found[label] = value
    return found


def section_list(obj):
    """(name, size, alignment) of each section of an object file."""
    data, headers, name, _ = read(obj)
    return [(name(h), h[5], h[8]) for h in headers if h[1] in (SHT_PROGBITS, SHT_NOBITS)]
