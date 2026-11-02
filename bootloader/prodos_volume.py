"""ProDOS volumes that boot with boot0.s, and device images for SCSI cards.

    blocks = fitted_blocks([len(code), ...])  # the fewest blocks that hold the files
    volume = Volume("NAME", blocks, boot0)   # boot0: the 512 bytes of block 0
    volume.install("GAME.SYSTEM", code, 0xFF, 0x2000)
    volume.boot("GAME.SYSTEM")
    image = bytes(volume.data)            # .po / .hdv / 800K disk
    scsi = apm(image, "NAME")             # an Apple SCSI card (BlueSCSI)
"""

import hashlib
import struct

BLOCK = 512
NAME_OFFSET = 4  # boot0.s: the boot file name, a length byte and 15 bytes
FIRST_FREE = 6  # blocks 0-1 the boot, 2-5 the volume directory; the bitmap follows
BITMAP_BLOCKS = 4096  # the blocks that one bitmap block maps
INDEX_POINTERS = 256  # the block numbers of an index block


def file_blocks(size):
    """The blocks of a file of SIZE bytes as install writes it: its data
    blocks, and a sapling's index block or a tree's index blocks."""
    data = max(1, -(-size // BLOCK))
    if data == 1:
        return 1
    if data <= INDEX_POINTERS:
        return data + 1
    return data + -(-data // INDEX_POINTERS) + 1


def fitted_blocks(sizes):
    """The fewest blocks of a volume that holds files of SIZES bytes: the
    boot and directory blocks, the bitmap and the files, with no free block
    (a save writes in place)."""
    files = sum(file_blocks(size) for size in sizes)
    bitmap = 1
    while -(-(FIRST_FREE + bitmap + files) // BITMAP_BLOCKS) > bitmap:
        bitmap += 1
    return FIRST_FREE + bitmap + files


class Volume:
    def __init__(self, name, blocks, boot):
        assert 1 <= len(name) <= 15 and name.isascii() and name[0].isalpha()
        assert len(boot) == BLOCK
        bitmap_blocks = -(-blocks // BITMAP_BLOCKS)
        self.data = bytearray(blocks * BLOCK)
        self.data[:BLOCK] = boot
        for block in range(2, FIRST_FREE):  # the volume directory
            struct.pack_into(
                "<HH", self.data, block * BLOCK, block - 1 if block > 2 else 0,
                block + 1 if block < FIRST_FREE - 1 else 0,
            )
        h = bytearray(39)
        h[0] = 0xF0 | len(name)
        h[1 : 1 + len(name)] = name.encode()
        h[30] = 0xE3
        h[31:33] = bytes((39, 13))
        struct.pack_into("<HHH", h, 33, 0, FIRST_FREE, blocks)
        self.data[2 * BLOCK + 4 : 2 * BLOCK + 43] = h
        self.bitmap = FIRST_FREE
        self.blocks = blocks
        for block in range(FIRST_FREE + bitmap_blocks, blocks):
            self.data[6 * BLOCK + block // 8] |= 128 >> (block & 7)

    def block(self, n):
        return self.data[n * BLOCK : (n + 1) * BLOCK]

    def write(self, n, data):
        assert len(data) <= BLOCK
        self.data[n * BLOCK : (n + 1) * BLOCK] = bytes(data).ljust(BLOCK, b"\0")

    def entries(self):
        block = 2
        while block:
            data = self.block(block)
            for i in range(1 if block == 2 else 0, 13):
                yield block * BLOCK + 4 + 39 * i
            block = int.from_bytes(data[2:4], "little")

    def allocate(self):
        for block in range(self.blocks):
            p = self.bitmap * BLOCK + block // 8
            bit = 128 >> (block & 7)
            if self.data[p] & bit:
                self.data[p] &= 255 ^ bit
                return block
        raise ValueError("The volume is full")

    def pointers(self, numbers):
        data = bytearray(BLOCK)
        for i, n in enumerate(numbers):
            data[i] = n & 255
            data[256 + i] = n >> 8
        return data

    def install(self, name, data, filetype, aux=0):
        """Add a file to the volume directory. Its data blocks are
        contiguous, in order."""
        assert 1 <= len(name) <= 15 and name.isascii() and name[0].isalpha()
        assert not any(
            self.data[a] & 15 and self.data[a + 1 : a + 1 + (self.data[a] & 15)] == name.encode()
            for a in self.entries()
        )
        entry = next(a for a in self.entries() if self.data[a] >> 4 == 0)
        blocks = []
        for pos in range(0, len(data), BLOCK):
            n = self.allocate()
            self.write(n, data[pos : pos + BLOCK])
            blocks.append(n)
        used = len(blocks)
        if len(blocks) == 1:
            storage = 1
            key = blocks[0]
        elif len(blocks) <= 256:
            storage = 2
            key = self.allocate()
            self.write(key, self.pointers(blocks))
            used += 1
        else:
            storage = 3
            indexes = []
            for i in range(0, len(blocks), 256):
                n = self.allocate()
                self.write(n, self.pointers(blocks[i : i + 256]))
                indexes.append(n)
            key = self.allocate()
            self.write(key, self.pointers(indexes))
            used += len(indexes) + 1
        record = bytearray(39)
        record[0] = (storage << 4) | len(name)
        record[1 : 1 + len(name)] = name.encode()
        record[16] = filetype
        struct.pack_into("<HH", record, 17, key, used)
        record[21:24] = len(data).to_bytes(3, "little")
        record[30] = 0xE3
        struct.pack_into("<H", record, 31, aux)
        struct.pack_into("<H", record, 37, 2)
        self.data[entry : entry + 39] = record
        count = int.from_bytes(self.data[2 * BLOCK + 37 : 2 * BLOCK + 39], "little") + 1
        self.data[2 * BLOCK + 37 : 2 * BLOCK + 39] = count.to_bytes(2, "little")
        assert self.read(record) == data
        return dict(
            name=name,
            bytes=len(data),
            storage=storage,
            blocks=used,
            first_block=blocks[0],
            sha256=hashlib.sha256(data).hexdigest(),
        )

    def read(self, record):
        storage = record[0] >> 4
        key = int.from_bytes(record[17:19], "little")
        size = int.from_bytes(record[21:24], "little")

        def ptrs(block):
            b = self.block(block)
            return [b[i] | b[256 + i] << 8 for i in range(256)]

        blocks = (
            [key]
            if storage == 1
            else ptrs(key)
            if storage == 2
            else [n for b in ptrs(key) if b for n in ptrs(b)]
        )
        return b"".join(self.block(b) if b else bytes(BLOCK) for b in blocks)[:size]

    def boot(self, name):
        """Make boot0.s load and run the file NAME (a seedling or sapling of
        at most $9E00 bytes)."""
        record = next(
            self.data[a : a + 39]
            for a in self.entries()
            if self.data[a] & 15 == len(name) and self.data[a + 1 : a + 1 + len(name)] == name.encode()
        )
        assert record[0] >> 4 in (1, 2) and int.from_bytes(record[21:24], "little") <= 0x9E00
        self.data[NAME_OFFSET : NAME_OFFSET + 16] = bytes((len(name),)) + name.encode().ljust(15, b"\0")


def apm(volume, name, first=64):
    """A device image for the SCSI cards of Apple (with a BlueSCSI): an Apple
    partition map, then VOLUME at block FIRST as an Apple_PRODOS partition.
    The card boots the partition and gives its blocks to boot0.s."""
    blocks = first + len(volume) // BLOCK
    image = bytearray(first * BLOCK) + volume
    struct.pack_into(">2sHI", image, 0, b"ER", BLOCK, blocks)
    parts = (
        (b"Apple", b"Apple_partition_map", 1, first - 1),
        (name.encode(), b"Apple_PRODOS", first, blocks - first),
    )
    for i, (part, kind, start, count) in enumerate(parts):
        e = BLOCK * (1 + i)
        struct.pack_into(
            ">2sHIII32s32sII", image, e, b"PM", 0, len(parts), start, count, part, kind, 0, count
        )
        struct.pack_into(">I", image, e + 88, 0x37)  # valid, allocated, in use, read, write
    return bytes(image)
