"""Convert fixed game screen updates into records for the Second Sight card.

scripts/assets.py passes build() the program ROM, tile ROM and a host-data
writer. The original screen writes contain an address, control byte and
data: bit 7 selects vertical writes, bit 6 repeats a byte, and bits 5-0 give
the count. A zero byte ends the list.

This module applies each list to a model of the two background name tables,
then emits cell, palette and colour records from src/packet_layout.inc. A
later write to a cell wins. The card applies all of a list before showing
the picture. The two name tables form a single ring of columns on the card.
"""

from iigs_payload import HostData

PROGRAM_BASE = 0x8000  # the CPU address of the program's first byte

# ---- The sources --------------------------------------------
# write_list_low $805A, write_list_high $806D (19 bytes each): the address
#   of each source's list. RAM addresses are the original's
#   lists 1 and 2 and its title buffer.
WRITE_LIST_LOW = 0x805A  # write_list_low: the low byte of each source's list
WRITE_LIST_HIGH = 0x806D  # write_list_high: the high byte
WRITE_LISTS = 19  # sources 0-$12
RAM_END = 0x0800  # an address below this is the original's RAM
TITLE_BUFFER = 0x0300  # source 5: the title list's copy in RAM
# The port's records of each ROM source, by the original's source number.
# The palette lists $8CA4-$8D53 (sources 1-4 and 8-11) and the messages
#   $8D54-$8E03 (sources $0C-$12): write lists.
SOURCE_NAMES = {
    1: "water_palette",
    2: "ground_palette",
    3: "cave_palette",
    4: "castle_palette",
    5: "title",
    8: "bowser_palette",
    9: "day_snow_palette",
    10: "night_snow_palette",
    11: "mushroom_palette",
    12: "thank_mario",
    13: "thank_luigi",
    14: "princess_elsewhere",
    15: "quest_over",
    16: "new_quest",
    17: "push_b",
    18: "choose_world",
}
# The port's own sources after the original's: text 0's two forms.
PORT_SOURCES = ("status_top_mario", "status_top_luigi")

# ---- The title list --------------------------------------------
# The title list: tile art $1EC0, 314 bytes copied, a write list.
TITLE_LIST = 0x1EC0  # in the tile art: the place of background tiles $EC-$FF
TITLE_LIST_BYTES = 0x13A  # the bytes that the original copies to $0300

# ---- The texts ----------------------------------------------
# screen_text $8752: the text records, each text ending with $FF;
#   text_record_starts $87FE (10 bytes): the start of each text form;
#   luigi_text $87ED (5 bytes); warp_zone_worlds $87F2 (3 groups of 4 bytes,
#   bytes 0-2 used).
SCREEN_TEXT = 0x8752  # screen_text: the records of the texts, each ending with TEXT_END
TEXT_RECORD_STARTS = 0x87FE  # text_record_starts: the offset of each form in screen_text
TEXT_END = 0xFF  # the end of a text in screen_text
LUIGI_TEXT = 0x87ED  # luigi_text: the five tiles of LUIGI
NAME_TILES = 5
NAME_OFFSET = 3  # write_screen_text copies LUIGI to $0304: the text's bytes 3-7, the first record's data
WARP_ZONE_WORLDS = 0x87F2  # warp_zone_worlds: per warp zone 4 bytes, the pipes' world tiles in bytes 0-2
WARP_ZONE_GROUP = 4
WARP_PIPES = 3
WARP_DIGITS_OFFSET = 27  # write_screen_text stores the pipes' worlds at $031C + 4 i: the text's bytes 27 + 4 i
WARP_DIGITS_STEP = 4
WARP_ZONES = (4, 5, 6)  # warp_zone and the text numbers of the warp zones
# The forms of text_record_starts: index 2 x text,
# + 1 without the name; the warp zones all use 8.
FORM_STATUS_TOP = 0
FORM_LIVES = 2
FORM_TIME_UP_NAMED = 4
FORM_TIME_UP_ALONE = 5
FORM_GAME_OVER_NAMED = 6
FORM_GAME_OVER_ALONE = 7
FORM_WARP_ZONE = 8

# ---- The title's menu and the blink -------------
# world_select_writes $823F (6 bytes) and mushroom_icon_writes $831D (8
#   bytes): whole write lists with the length byte first.
WORLD_SELECT_WRITES = 0x823F  # world_select_writes: list 1's length, then one record
MUSHROOM_ICON_WRITES = 0x831D  # mushroom_icon_writes: list 1's length, then one record
TEMPLATE_LIST_START = 1  # the record follows the length byte
# blink_write_template $89C9 (8 bytes), blink_color_steps $89C3 (6),
#   block_palettes_by_area $89D1 (16).
BLINK_WRITE_TEMPLATE = 0x89C9  # blink_write_template: a record of 4 colours of palette 3
BLINK_COLOR_STEPS = 0x89C3  # blink_color_steps: 6 colours
BLINK_STEPS = 6
BLOCK_PALETTES_BY_AREA = 0x89D1  # block_palettes_by_area: 4 colours per area type
BLOCK_PALETTES = 16
# block_tile_sets $8A39 (20 bytes: 5 sets of top left, top right, bottom
#   left, bottom right).
BLOCK_TILE_SETS = 0x8A39  # block_tile_sets
BLOCK_TILES = 20

# ---- The palettes and the player's colours ----------------------
# area_palette_index $85BB (4), backdrop_ctrl_source $85CB (4),
#   backdrop_colors $85CF (8), player_palettes $85D7 (12).
AREA_PALETTE_INDEX = 0x85BB  # area_palette_index: the source of each area type's palette
AREA_TYPES = 4
BACKDROP_CTRL_SOURCE = 0x85CB  # backdrop_ctrl_source: the source of backdrop settings 4-7
BACKDROP_SETTINGS = 4
BACKDROP_COLORS = 0x85CF  # backdrop_colors: entries 0-3 by area type, 4-7 by setting
BACKDROP_COLOURS = 8
PLAYER_PALETTES = 0x85D7  # player_palettes: Mario, Luigi, fire, 4 colours each
PLAYER_GROUPS = 3
PLAYER_GROUP = 4  # Mario, Luigi, fire: 4 colours a group
FIRST_SHOWN_COLOUR = 1  # the first colour of a group is never shown: the backdrop replaces it

# ---- The demo ------------------------------------------------
# demo_pads $8340 (21), demo_frames $8355 (22).
DEMO_PADS = 0x8340  # demo_pads: the pad bits of steps 1-21
DEMO_FRAMES = 0x8355  # demo_frames: the frames of steps 1-22; a 0 ends the demo
DEMO_END = 0

# ---- The modes ---------------------------------------------------------
# default_sprite_starts $8FBC (15), sprite_zero_setup $8FCB (4),
#   area_song_by_type $90E7 (6), halfway_pages $91BD (16).
DEFAULT_SPRITE_STARTS = 0x8FBC  # default_sprite_starts
SPRITE_STARTS = 15
SPRITE_ZERO_SETUP = 0x8FCB  # sprite_zero_setup: Y, tile, attribute, X (a sprite entry)
SPRITE_ENTRY_BYTES = 4  # an NES sprite entry: Y, tile, attribute, X
AREA_SONG_BY_TYPE = 0x90E7  # area_song_by_type: area types 0-3, the cloud, the pipe intro
AREA_SONGS = 6
HALFWAY_PAGES = 0x91BD  # halfway_pages: levels 1-2 and 3-4 of each world, two nybbles
WORLDS = 8
LEVELS = 4
LEVELS_IN_BYTE = 2  # a byte holds two levels: the odd level (1 or 3) in the high nybble
NYBBLE_BITS = 4
NYBBLE_MASK = 0x0F

# ---- The original's write lists -----------------------
LIST_END = 0  # the end of a write list
CONTROL_DOWN = 0x80  # control: the address steps by a row
CONTROL_REPEAT = 0x40  # control: one data byte, count times
CONTROL_COUNT = 0x3F  # control: the count (0 would be 256; no list uses it)
NAME_TABLE_0 = 0x2000  # the cells of name table 0, row x 32 + column
NAME_TABLE_BYTES = 0x400  # a name table: 960 cells, then 64 attribute bytes
ATTRIBUTE_START = 0x3C0  # the attribute bytes of a name table
ATTRIBUTE_COLUMNS = 8  # an attribute byte: the palettes of 4 x 4 cells, two bits a square
PALETTE_START = 0x3F00  # the 32 colour entries
PALETTE_ENTRIES = 32
TABLE_COLUMNS = 32  # cells in a row of a name table; name table n is ring columns 32 n to 32 n + 31
TABLE_ROWS = ATTRIBUTE_START // TABLE_COLUMNS  # 30 rows of cells
ROW_STEP = 32  # the address step down
SQUARE_CELLS = 2  # a square is 2 x 2 cells; a REC_PALETTES palette covers one
PALETTE_BITS = 2
PALETTE_MASK = 3
RECORD_COUNT_LIMIT = 32  # REC_CELLS, REC_PALETTES, REC_COLOURS: a count of 1-32 (packet_layout.inc)


def write_records(data, start, end_byte=LIST_END):
    """The records of an original write list from START to its end byte:
    (address, step, data bytes), and the offset of the end byte."""
    records = []
    i = start
    while data[i] != end_byte:
        address = data[i] << 8 | data[i + 1]
        control = data[i + 2]
        count = control & CONTROL_COUNT
        assert count, f"a write record of 256 bytes at offset {i}"
        if control & CONTROL_REPEAT:
            values = [data[i + 3]] * count
            i += 4
        else:
            values = list(data[i + 3 : i + 3 + count])
            i += 3 + count
        records.append((address, ROW_STEP if control & CONTROL_DOWN else 1, values))
    return records, i


def cell_place(address):
    """The ring row and the ring column of the cell at name table address
    ADDRESS."""
    table, place = divmod(address - NAME_TABLE_0, NAME_TABLE_BYTES)
    assert table in (0, 1) and address >= NAME_TABLE_0 and place < ATTRIBUTE_START, hex(address)
    row, column = divmod(place, TABLE_COLUMNS)
    return row, TABLE_COLUMNS * table + column


class Picture:
    """What a write list leaves in the name tables and the palette: the
    cells and the squares that it writes (the last write of each), and its
    colour writes in their order."""

    # Start with no changed cells, palette squares or colour writes.
    def __init__(self):
        self.cells = {}  # (ring row, ring column): tile
        self.squares = {}  # (square row, square column): palette
        self.colours = []  # (first entry, colours)

    # Apply RECORDS in order. Keep colour writes in order and the last
    # tile or palette written at each position; return this picture.
    def apply(self, records):
        for address, step, values in records:
            if address >= PALETTE_START:
                first = address - PALETTE_START
                assert step == 1 and first + len(values) <= PALETTE_ENTRIES, hex(address)
                self.colours.append((first, values))
                continue
            for value in values:
                self.write(address, value)
                address += step
        return self

    # Apply VALUE at the original picture-memory ADDRESS. Tile bytes
    # change cells; an attribute byte sets the palettes of four squares.
    def write(self, address, value):
        table, offset = divmod(address - NAME_TABLE_0, NAME_TABLE_BYTES)
        assert table in (0, 1) and address >= NAME_TABLE_0, hex(address)
        if offset < ATTRIBUTE_START:
            self.cells[cell_place(address)] = value
            return
        attribute_row, attribute_column = divmod(offset - ATTRIBUTE_START, ATTRIBUTE_COLUMNS)
        for quarter in range(4):  # bits 1-0 top left, 3-2 top right, 5-4 bottom left, 7-6 bottom right
            row = SQUARE_CELLS * attribute_row + quarter // SQUARE_CELLS
            column = (TABLE_COLUMNS // SQUARE_CELLS) * table + SQUARE_CELLS * attribute_column + quarter % SQUARE_CELLS
            if row < TABLE_ROWS // SQUARE_CELLS:  # attribute row 7 has no lower squares
                self.squares[(row, column)] = value >> (PALETTE_BITS * quarter) & PALETTE_MASK

    def records(self):
        """The port's records: the cells and the squares as runs along a
        row, then the colours."""
        out = HostData()
        for kind, places in (("REC_CELLS", self.cells), ("REC_PALETTES", self.squares)):
            for row, column, values in runs(places):
                out.byte(kind, row, column, len(values)).data(values)
        for first, values in self.colours:
            out.byte("REC_COLOURS", first, len(values)).data(values)
        return out


def runs(places):
    """The written places of a row as runs of next columns: (row, first
    column, values), no run longer than a record's count."""
    found = []
    for (row, column), value in sorted(places.items()):
        last = found[-1] if found else None
        if last and last[0] == row and last[1] + len(last[2]) == column and len(last[2]) < RECORD_COUNT_LIMIT:
            last[2].append(value)
        else:
            found.append((row, column, [value]))
    return found


def list_records(data, start, end_byte=LIST_END):
    """The port's records of the write list at START."""
    records, _ = write_records(data, start, end_byte)
    return Picture().apply(records).records()


def form_records(form):
    """The port's records of a text form (its bytes without the end byte)."""
    return list_records(bytes(form) + bytes((LIST_END,)), 0)


def text_form(program, at, form):
    """The bytes of text form FORM of screen_text, without its end byte."""
    start = SCREEN_TEXT + at(TEXT_RECORD_STARTS + form) - PROGRAM_BASE
    end = program.index(TEXT_END, start)
    return bytearray(program[start:end])


def build(program, host, tile_rom):
    """The screen records and tables into the host data. PROGRAM: the 32 KB
    program ROM; TILE_ROM: the 8 KB tile art (the title list)."""
    assert len(program) == 0x8000
    at = lambda address: program[address - PROGRAM_BASE]
    run = lambda address, size: bytes(program[address - PROGRAM_BASE : address - PROGRAM_BASE + size])
    offset = lambda address: address - PROGRAM_BASE

    # The fixed lists that the frame sends: the ROM sources, then the two
    # forms of text 0 (MARIO, and LUIGI over the first record's tiles).
    # The records of those lists (a data bank): *_palette_records,
    #   title_records, status_top_mario_records, status_top_luigi_records,
    #   thank_mario_records ... choose_world_records.
    lists = {}
    for source in range(WRITE_LISTS):
        address = at(WRITE_LIST_LOW + source) | at(WRITE_LIST_HIGH + source) << 8
        if address == TITLE_BUFFER:
            title = bytes(tile_rom[TITLE_LIST : TITLE_LIST + TITLE_LIST_BYTES])
            _, end = write_records(title, 0)
            assert end < TITLE_LIST_BYTES, "the title list ends inside the bytes that the original copies"
            lists[source] = list_records(title, 0)
        elif address >= RAM_END:
            lists[source] = list_records(program, offset(address))
        assert (source in lists) == (source in SOURCE_NAMES), f"source {source}: ${address:04X}"
    status_top = text_form(program, at, FORM_STATUS_TOP)
    text_lists = [form_records(form) for form in (status_top, luigi_form(status_top, run))]
    # screen_rom_lists: for each source 0-$14, 5 bytes: the address of its
    #   records (faraddr) and their length (word) (state.inc ROM_LIST_*): sources
    #   1-5 and 8-$12 the port's records of the original's lists, $13 and $14 the
    #   port's two forms of text 0 (screen.s SOURCE_STATUS_TOP_MARIO, _LUIGI);
    #   0, 6 and 7 (the RAM lists) are 0. SCREEN_ROM_LISTS_SIZE: its bytes. The
    #   frame's send reads it (src/game/frame.s, src/packet.s).
    table = HostData()
    for source in range(WRITE_LISTS + len(PORT_SOURCES)):
        records = lists.get(source) if source < WRITE_LISTS else text_lists[source - WRITE_LISTS]
        if records is None:
            table.faraddr(0).word(0)  # list 1, list 2: the frame sends them from the RAM
            continue
        name = SOURCE_NAMES[source] if source < WRITE_LISTS else PORT_SOURCES[source - WRITE_LISTS]
        table.faraddr(host.blob_at(records, f"{name}_records")).word(len(records))
    host.game_blob_at(table, "screen_rom_lists", "SCREEN_ROM_LISTS_SIZE")

    # The text forms that write_screen_text copies into list 1.
    # The text forms that write_screen_text copies into list 1 (bank 0, with
    #   their sizes *_RECORDS_SIZE): lives_text_records (text 1),
    #   time_up_alone_records, time_up_mario_records, time_up_luigi_records (text
    #   2), game_over_alone_records, _mario_, _luigi_ (text 3),
    #   warp_zone_4_records, _5_, _6_ (texts 4-6). The LUIGI forms and the warp
    #   zones' pipe worlds are the original's rules of write_screen_text applied
    #   here: LUIGI over the first record's five tiles, the world digits into the
    #   three one-tile records.
    forms = {
        "lives_text": text_form(program, at, FORM_LIVES),
        "time_up_alone": text_form(program, at, FORM_TIME_UP_ALONE),
        "time_up_mario": text_form(program, at, FORM_TIME_UP_NAMED),
        "game_over_alone": text_form(program, at, FORM_GAME_OVER_ALONE),
        "game_over_mario": text_form(program, at, FORM_GAME_OVER_NAMED),
    }
    forms["time_up_luigi"] = luigi_form(forms["time_up_mario"], run)
    forms["game_over_luigi"] = luigi_form(forms["game_over_mario"], run)
    warp = text_form(program, at, FORM_WARP_ZONE)
    for group, zone in enumerate(WARP_ZONES):
        text = bytearray(warp)
        for pipe in range(WARP_PIPES):
            text[WARP_DIGITS_OFFSET + WARP_DIGITS_STEP * pipe] = at(WARP_ZONE_WORLDS + WARP_ZONE_GROUP * group + pipe)
        forms[f"warp_zone_{zone}"] = text
    for name, form in forms.items():
        host.game_blob_at(form_records(form), f"{name}_records", f"{name.upper()}_RECORDS_SIZE")

    # The title's menu: the marker's three cells, the world digit's place.
    # menu_marker_records (MENU_MARKER_RECORDS_SIZE): the marker's three
    #   one-cell records, top first. world_digit_place: the cell row and the ring
    #   column of the world digit. blink_colours_entry: the first colour entry of
    #   the blink record.
    marker = list_records(program, offset(MUSHROOM_ICON_WRITES) + TEMPLATE_LIST_START)
    host.game_blob_at(marker, "menu_marker_records", "MENU_MARKER_RECORDS_SIZE")
    (address, _, _), = write_records(program, offset(WORLD_SELECT_WRITES) + TEMPLATE_LIST_START)[0]
    host.game_blob_at(bytes(cell_place(address)), "world_digit_place")

    # player_colours: 3 groups (Mario, Luigi, fire) of 3 colours, the
    #   original's groups without their first byte, which is never shown. backdrop_colours, block_palettes, blink_colour_steps,
    #   block_square_tiles, area_palette_sources, backdrop_sources,
    #   area_song_by_type, default_sprite_starts, sprite_zero_entry: as the ROM
    #   has them (the sources are the original's source numbers, which the port
    #   keeps).
    # The blink, the block pictures, the player's colours.
    (blink_address, _, _), = write_records(program, offset(BLINK_WRITE_TEMPLATE))[0]
    host.game_blob_at(bytes((blink_address - PALETTE_START,)), "blink_colours_entry")
    host.game_blob_at(run(BLINK_COLOR_STEPS, BLINK_STEPS), "blink_colour_steps")
    host.game_blob_at(run(BLOCK_PALETTES_BY_AREA, BLOCK_PALETTES), "block_palettes")
    host.game_blob_at(run(BLOCK_TILE_SETS, BLOCK_TILES), "block_square_tiles")
    host.game_blob_at(run(AREA_PALETTE_INDEX, AREA_TYPES), "area_palette_sources")
    host.game_blob_at(run(BACKDROP_CTRL_SOURCE, BACKDROP_SETTINGS), "backdrop_sources")
    host.game_blob_at(run(BACKDROP_COLORS, BACKDROP_COLOURS), "backdrop_colours")
    host.game_blob_at(
        bytes(at(PLAYER_PALETTES + PLAYER_GROUP * group + colour) for group in range(PLAYER_GROUPS)
              for colour in range(FIRST_SHOWN_COLOUR, PLAYER_GROUP)),
        "player_colours",
    )

    # The demo: (frames, pad bits) for each step, then the 0 that ends it.
    # demo_steps: for each step of the demo its frames and its pad bits, then
    #   one 0 byte.
    steps = bytearray()
    step = 0
    while at(DEMO_FRAMES + step) != DEMO_END:
        steps += bytes((at(DEMO_FRAMES + step), at(DEMO_PADS + step)))
        step += 1
    steps.append(DEMO_END)
    host.game_blob_at(bytes(steps), "demo_steps")

    # halfway_pages_by_level: one byte for each world x 4 + level, the page
    #   of a restart.
    # The modes' tables.
    host.game_blob_at(run(DEFAULT_SPRITE_STARTS, SPRITE_STARTS), "default_sprite_starts")
    host.game_blob_at(run(SPRITE_ZERO_SETUP, SPRITE_ENTRY_BYTES), "sprite_zero_entry")
    host.game_blob_at(run(AREA_SONG_BY_TYPE, AREA_SONGS), "area_song_by_type")
    # Byte 2 w + 1 for levels 3-4 (index 2, 3); the high nybble for the odd
    # levels 1 and 3 (index 0, 2).
    host.game_blob_at(
        bytes(at(HALFWAY_PAGES + LEVELS // LEVELS_IN_BYTE * world + level // LEVELS_IN_BYTE)
              >> (0 if level % LEVELS_IN_BYTE else NYBBLE_BITS) & NYBBLE_MASK
              for world in range(WORLDS) for level in range(LEVELS)),
        "halfway_pages_by_level",
    )


def luigi_form(text, run):
    """A text form with LUIGI over the five tiles of its first record (the
    original's write_screen_text)."""
    named = bytearray(text)
    named[NAME_OFFSET : NAME_OFFSET + NAME_TILES] = run(LUIGI_TEXT, NAME_TILES)
    return named
