"""The boot volume and the native segment file, within 1 MB host RAM.

A ProDOS volume: boot0 (bootloader/) loads SSMARIO.SYSTEM, which reads
SSMARIO.DATA and SSMARIO.CONFIG with bootloader/prodos_read.s.
"""

import sys
from types import SimpleNamespace

from roms import ROOT
from debug_symbols import host_symbols
from startup_pack import pack, unpack

sys.path.insert(0, str(ROOT / "bootloader"))
from prodos_volume import Volume, apm, fitted_blocks


PLANE = 0x200000


def symbols(path):
    """The symbols of an ld65 label file: the labels and the areas
    (__NAME_START__, __NAME_SIZE__)."""
    found = {}
    for line in path.read_text().splitlines():
        if len(t := line.split()) == 3:
            found[t[2].lstrip(".")] = int(t[1], 16)
    return found


def boot_uploads(data, H):
    """Keep the firmware's text image and renderer until the final handoff.
    H holds the constants of the boot loader (the data file format,
    DATA_BUFFER_SIZE).

    UploadData uses the current VGA CPU write path. Text characters/attributes and
    the 256 32-byte font cells occupy the first 32 KB of physical VRAM.
    The firmware still executes its $6000-$CFFF renderer and reads $0400 text.
    Preserve order within each class, including later patches to earlier data.
    A record at 0x200000 + plane * 0x40000 + group writes one VGA plane.
    """

    def linear(address, size):
        """The linear video RAM bytes that a record writes."""
        if address < PLANE:
            return range(address, address + size)
        plane, group = (address - PLANE) >> 18, address & 0x3FFFF
        return range(group * 4 + plane, (group + size) * 4 + plane, 4)

    early = []
    code = []
    video = []
    p = 0
    # The reordered transfer must leave every destination byte unchanged,
    # including overlapping initialization records. This is a build check.
    expected = bytearray(0x120000)
    written = bytearray(0x120000)
    while p < len(data):
        address = int.from_bytes(data[p : p + 3], "little")
        size = int.from_bytes(data[p + 3 : p + 6], "little")
        p += 6
        if not size:
            break
        raw = data[p : p + size]
        p += size
        assert len(raw) == size
        if address >= PLANE:
            where = linear(address, size)
            assert where.stop <= 0x100000 + 3, hex(address)
            expected[where.start : where.stop : 4] = raw
            written[where.start : where.stop : 4] = b"\1" * size
            (video if where.start < 0x8000 else early).append((address, raw))
            continue
        assert address + size <= len(expected)
        expected[address : address + size] = raw
        written[address : address + size] = b"\1" * size
        # Split only at protected boundaries; every original byte is sent.
        boundaries = (
            [address]
            + [v for v in (0x8000, 0x100000, 0x110000) if address < v < address + size]
            + [address + size]
        )
        for lo, hi in zip(boundaries, boundaries[1:]):
            target = video if lo < 0x8000 else code if 0x100000 <= lo < 0x110000 else early
            target.append((lo, raw[lo - address : hi - address]))
    result = bytearray()
    actual = bytearray(len(expected))
    actual_written = bytearray(len(expected))
    # VGA text scanout and unchained CPU writes are independent. Each source
    # plane is prepared here, so the loader never shuffles image bytes.
    for records, flag in ((early, 0), (code, H.RECORD_FINAL_SRAM), (video, H.RECORD_FINAL_VRAM)):
        first = True
        for address, raw in records:
            jobs = []
            if address >= PLANE:
                jobs.append((address & 0x3FFFF, raw, 1 << ((address - PLANE) >> 18)))
            elif address < 0x100000:
                for lane in range(4):
                    offset = (lane - address) & 3
                    part = raw[offset::4]
                    if part:
                        jobs.append(((address + offset) // 4, part, 1 << lane))
            else:
                jobs.append((address, raw, 15))
            for target, part, mask in jobs:
                # The boot loader reads each record into DATA_BUFFER.
                for off in range(0, len(part), H.DATA_BUFFER_SIZE):
                    raw_part = part[off : off + H.DATA_BUFFER_SIZE]
                    encoded = pack(raw_part)
                    control = flag if first else 0
                    first = False
                    if len(encoded) + 2 < len(raw_part):
                        assert unpack(encoded) == raw_part
                        control |= H.RECORD_PACKED
                        payload = encoded
                    else:
                        payload = raw_part
                    header = bytearray(H.RECORD_HEADER_SIZE)
                    header[H.RECORD_ADDRESS : H.RECORD_ADDRESS + 3] = (target + off).to_bytes(3, "little")
                    header[H.RECORD_SIZE : H.RECORD_SIZE + 3] = len(raw_part).to_bytes(3, "little")
                    header[H.RECORD_CONTROL] = control
                    header[H.RECORD_MASK] = mask
                    header[H.RECORD_STORED : H.RECORD_STORED + 2] = len(payload).to_bytes(2, "little")
                    result += header + payload
            where = linear(address, len(raw))
            actual[where.start : where.stop : where.step] = raw
            actual_written[where.start : where.stop : where.step] = b"\1" * len(raw)
    assert actual == expected and actual_written == written, "Boot upload order changed card memory"
    return bytes(result) + bytes(H.RECORD_HEADER_SIZE)


def build(case, out=None):
    out = out or ROOT / "build/boot"
    out.mkdir(parents=True, exist_ok=True)
    # The places come from the link of the IIgs program. The formats come from
    # the boot loader, which reads the files: its debug file holds the
    # constants of its includes (src/data_file.inc, settings.inc, ...).
    labels = symbols(case / "host.lbl")
    H = SimpleNamespace(**{k: v for k, v in host_symbols(out / "boot.dbg").items() if k.isidentifier()})
    area = lambda name: (labels[f"__{name}_START__"], labels[f"__{name}_SIZE__"])
    # The load files of src/iigs.cfg, each at the address of its first area.
    regions = [
        (area("NATIVE")[0], "native.bin"),
        (area("BOOT")[0], "host-boot.bin"),
        (area("GAMEPLAY")[0], "gameplay.bin"),
        (area("INPUT")[0], "payload.bin"),
    ]
    payload_end = sum(area("DATA04"))
    blobs = [(address, (case / name).read_bytes(), name) for address, name in regions]
    assert len(blobs) <= H.MAX_SEGMENTS
    for address, data, name in blobs:
        assert address + len(data) <= payload_end, (name, address, len(data))
    for i, (a, d, _) in enumerate(blobs):
        for b, e, _ in blobs[i + 1 :]:
            assert a + len(d) <= b or b + len(e) <= a
    header = bytearray(H.DATA_HEADER_SIZE)
    header[H.DATA_MAGIC : H.DATA_MAGIC + 6] = b"SS-SMB"
    header[H.DATA_VERSION] = H.DATA_FORMAT
    header[H.DATA_SEGMENTS] = len(blobs)
    startup = boot_uploads((case / "card-startup.bin").read_bytes(), H)
    header[H.DATA_STARTUP] = bool(startup)
    for i, (address, data, _) in enumerate(blobs):
        entry = H.DATA_TABLE + i * H.SEGMENT_ENTRY
        header[entry : entry + H.SEGMENT_ENTRY] = address.to_bytes(3, "little") + len(
            data
        ).to_bytes(3, "little")
    boot_start, boot_size = area("BOOT")
    assert boot_start <= labels["game_handoff"] < boot_start + boot_size
    setting_addr = labels["settings"]
    source = next((a, d) for a, d, _ in blobs if a <= setting_addr < a + len(d))
    start = setting_addr - source[0]
    config = bytearray(source[1][start : start + H.SETTINGS_SIZE])
    assert len(config) == H.SETTINGS_SIZE
    checksum = H.SETTINGS_SEED
    for offset in range(0, H.SETTINGS_CHECKSUM, 2):
        checksum = ((checksum << 1) | (checksum >> 15)) & 65535
        checksum ^= int.from_bytes(config[offset : offset + 2], "little")
    config[H.SETTINGS_CHECKSUM : H.SETTINGS_CHECKSUM + 2] = checksum.to_bytes(2, "little")
    body = b"".join(data for _, data, _ in blobs) + startup
    # The bytes of the file read when each cell of the progress bar fills.
    size = len(header) + len(body)
    for cell in range(H.PROGRESS_CELLS):
        at = H.DATA_PROGRESS + 4 * cell
        header[at : at + 4] = ((size * (cell + 1) + H.PROGRESS_CELLS - 1) // H.PROGRESS_CELLS).to_bytes(4, "little")
    bundle = bytes(header) + body
    system = (out / "boot.bin").read_bytes()
    system_load = symbols(out / "boot.lbl")["__SYSTEM_START__"]
    # The volume: the boot block (the Makefile builds boot0.bin and the boot
    # loader), just large enough for the three files.
    disk = Volume("SSMARIO", fitted_blocks([len(config), len(system), len(bundle)]), (out / "boot0.bin").read_bytes())
    disk.install("SSMARIO.CONFIG", config, 6)
    disk.install("SSMARIO.SYSTEM", system, 0xFF, system_load)
    disk.install("SSMARIO.DATA", bundle, 6)
    disk.boot("SSMARIO.SYSTEM")
    image = out / "mario.hdv"
    image.write_bytes(disk.data)
    (out / "mario-scsi.hda").write_bytes(apm(bytes(disk.data), "SSMARIO"))
    return image
