"""The tile art of the card, from the tile ROM (8 KB: the sprite pattern
table, tiles $00-$FF at $0000, then the background pattern table at $1000).

A tile is 16 bytes: bit plane 0 of rows 0-7, then bit plane 1. Pixel x of
row y has pen (plane0[y] >> (7 - x)) & 1 | ((plane1[y] >> (7 - x)) & 1) << 1.

The card's pixel values are colour chip slots, the original's palette
entries: a background pixel of palette p and pen c is 4 p + c, but pen 0 is
0 (the backdrop, entry 0, in every palette); a sprite pixel is 16 + 4 p + c
(src/secondsight/ring.s, picture.s).

The builder writes (src/secondsight/sprites.s, status.s, page.s read them):
- chr_sprites, chr_bg: the two pattern tables as they are, each one 4 KB
  page of SRAM (.desc), for the card's sprite art cache and status copies.
- sprite_opacity, bg_opacity: for each tile row, a byte with bit 7 - x set
  where pixel x has a pen other than 0 (.common, 256-aligned).
- metatile_tiles: the 4 tiles of each metatile number m (0-255), for the
  COLUMN screen record (src/secondsight/ring.s record_column): four 256-byte
  parts, index m: the left top, left bottom, right top and right bottom
  tile (.common, 256-aligned). From the program's metatile tables (document
  02 section 17.4): metatile_table_low/high ($8B08, $8B0C) give the table of
  palette m >> 6; entry m & $3F of it holds the 4 tiles in that order. An
  entry past a table's last one reads the next table, as the original does.
- tile_art: every background tile in every palette, in video RAM: cell
  (palette p, tile t) is 16 groups from group 16 x (256 p + t) of tile_art:
  8 rows of 2 groups. Group g of a row holds pixels 4 g to 4 g + 3, pixel
  4 g + q in plane q, at linear byte 4 x group + q.
"""

from asset_source import Source
import secondsight_link

TILE_BYTES = 16
TABLE_TILES = 256
TABLE_BYTES = TILE_BYTES * TABLE_TILES
PALETTES = 4
CELL_GROUPS = 16  # 8 rows of 2 groups (src/secondsight/include/video.inc TILE_ART_GROUPS)
PROGRAM_BASE = 0x8000  # the CPU address of the program's first byte
METATILE_TABLE_LOW = 0x8B08  # the low bytes of the 4 metatile tile tables (02 section 17.4)
METATILE_TABLE_HIGH = 0x8B0C  # their high bytes
METATILES = 256
METATILE_TILES = 4


def pens(tile):
    """The 8 x 8 pens of a 16-byte tile, row by row."""
    return [
        [((tile[y] >> (7 - x)) & 1) | (((tile[8 + y] >> (7 - x)) & 1) << 1) for x in range(8)]
        for y in range(8)
    ]


def opacity(table):
    """The opacity byte of each row of each tile of a pattern table."""
    out = bytearray()
    for t in range(TABLE_TILES):
        tile = table[t * TILE_BYTES : (t + 1) * TILE_BYTES]
        out += bytes(tile[y] | tile[8 + y] for y in range(8))
    return bytes(out)


def tile_art(table):
    """The linear video RAM bytes of every background cell."""
    out = bytearray(PALETTES * TABLE_TILES * CELL_GROUPS * 4)
    for p in range(PALETTES):
        for t in range(TABLE_TILES):
            grid = pens(table[t * TILE_BYTES : (t + 1) * TILE_BYTES])
            first = (p * TABLE_TILES + t) * CELL_GROUPS
            for y in range(8):
                for x in range(8):
                    pen = grid[y][x]
                    group = first + 2 * y + x // 4
                    out[4 * group + x % 4] = 4 * p + pen if pen else 0
    return bytes(out)


def metatile_tiles(program):
    """The four 256-byte parts of the metatile table (see the module header)."""
    parts = [bytearray(METATILES) for _ in range(METATILE_TILES)]
    for m in range(METATILES):
        palette = m >> 6
        low = program[METATILE_TABLE_LOW - PROGRAM_BASE + palette]
        high = program[METATILE_TABLE_HIGH - PROGRAM_BASE + palette]
        entry = (high << 8 | low) + METATILE_TILES * (m & 0x3F) - PROGRAM_BASE
        for k in range(METATILE_TILES):
            parts[k][m] = program[entry + k]
    return b"".join(parts)


def build(tiles, program):
    """Write the card's tile art sources. TILES: the 8 KB tile ROM;
    PROGRAM: the 32 KB program (the metatile tables)."""
    assert len(tiles) == 2 * TABLE_BYTES
    sprites, background = tiles[:TABLE_BYTES], tiles[TABLE_BYTES:]
    source = Source("the pattern tables and their opacity (scripts/tiles.py)")
    for name, table in (("chr_sprites", sprites), ("chr_bg", background)):
        source.section(f".desc.{name}").label(name).data(table)
    for name, table in (("sprite_opacity", sprites), ("bg_opacity", background)):
        source.section(f".common.{name}").align(256).label(name).data(opacity(table))
    source.section(".common.metatile_tiles").align(256).label("metatile_tiles").data(metatile_tiles(program))
    secondsight_link.asset("tiles", source)
    art = Source("the background tile art in video RAM (scripts/tiles.py)")
    # One 8K-group window (32 KB) holds two palettes; the art starts a window,
    # so no cell crosses one (page.s shows one window in the bank area).
    art.section(".vram.b8192_a32768_k0.tile_art").label("tile_art").data(tile_art(background))
    secondsight_link.asset("tile_art", art)
