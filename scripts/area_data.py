"""Build area columns and enemy spawn records from the game program ROM.

scripts/assets.py passes build() the program and a host-data writer. Area
layouts are fixed, so this module runs the column builder before play. It
builds variants for entry pages, castle-loop rewinds, world 8 water areas
and the hidden 1-up block. Each column has 13 background blocks, collision
bytes and events that still depend on live play.

src/game/area.s reads the records on the original eight-step schedule and
performs events such as enemy starts and scroll locks. A stream that rejoins
the page-zero path ends with a jump to the matching column. Assembly labels
resolve the event routines and record flags at link time.
"""

from iigs_payload import HostData

PROGRAM_BASE = 0x8000  # the CPU address of the program's first byte

# ---- The order of the worlds and the list pointers (2) ------------------
# world_area_starts $9CB4 (8), area_slots $9CBC (36): the area byte of each
#   slot of each world.
WORLD_AREA_STARTS = 0x9CB4  # world_area_starts: the first slot of each world in area_slots
AREA_SLOTS = 0x9CBC  # area_slots: one area byte per slot, in play order
WORLDS = 8
SLOTS = 36
# enemy_list_bases $9CE0 (4), enemy_list_low $9CE4 (34), enemy_list_high
#   $9D06 (34), area_list_bases $9D28 (4), area_list_low $9D2C (34),
#   area_list_high $9D4E (34): the address of each list by type and number.
ENEMY_LIST_BASES = 0x9CE0  # enemy_list_bases: the first enemy list of each area type
ENEMY_LIST_LOW = 0x9CE4  # enemy_list_low/high: the address of each enemy list
ENEMY_LIST_HIGH = 0x9D06
AREA_LIST_BASES = 0x9D28  # area_list_bases: the first area list of each area type
AREA_LIST_LOW = 0x9D2C  # area_list_low/high: the address of each area list
AREA_LIST_HIGH = 0x9D4E
AREA_TYPES = 4  # 0 water, 1 ground, 2 underground, 3 castle
LISTS_OF_TYPE = (3, 22, 3, 6)  # the list numbers of each type
TYPE_WATER, TYPE_GROUND, TYPE_UNDERGROUND, TYPE_CASTLE = range(AREA_TYPES)
AREA_TYPE_SHIFT = 5  # the area byte: bits 6-5 the type, bits 4-0 the list number
AREA_NUMBER_MASK = 0x1F
AREA_BYTE_MASK = 0x7F  # bit 7 of an area byte is read by no reader
AREA_BYTES = 0x80
WORLD_8 = 7  # the world whose water areas have the castle floor
# halfway_pages $91BD (16): the start page after a lost life.
HALFWAY_PAGES = 0x91BD  # 16: two levels a byte, the odd level in the high nybble
ENTRANCE_PIPE_INTROS = (6, 7)  # the header entrances of the pipe intro areas (player_enters_area)
START_PAGES = 32  # begin_area's start page: an area change's entrance page has 5 bits
START_SET_PAGES = 2  # the 24 columns of an area start end in page S + 1: play meets column 0 at S + 2

# ---- The area list --------------------------------------------------------
HEADER_BYTES = 2
OBJECT_BYTES = 2
# The area lists: a 2-byte header, 2-byte objects, the end byte $FD. The enemy lists: 2-byte entries (3 for an area change), the
#   end byte $FF.
AREA_LIST_END = 0xFD  # byte 0 of the end of an area list
ROW_FIELD = 0x0F  # byte 0 bits 3-0: the row field
COLUMN_SHIFT = 4  # byte 0 bits 7-4: the column in the page
PAGE_SELECT = 0x80  # byte 1 bit 7: the object is on the next page
ROW_GROUP_12, ROW_GROUP_13, ROW_GROUP_14, ROW_GROUP_15 = 12, 13, 14, 15
GROUP_KIND = 0x70  # byte 1 bits 6-4: a group's kind, or the size class of a large object
GROUP_SHIFT = 4
LENGTH_FIELD = 0x0F  # byte 1 bits 3-0: L, the length or height
SMALL_KIND = 0x0F  # byte 1 bits 3-0: the kind of a small object
PIPE_CLASS = 7  # byte 1 bits 6-4 of a vertical pipe
PIPE_ENTERABLE = 0x08  # byte 1 bit 3 of a vertical pipe
PIPE_HEIGHT = 0x07  # byte 1 bits 2-0 of a vertical pipe: its shaft
ROW_13_SPECIAL = 0x40  # byte 1 bit 6 of a row 13 object: not a page skip
ROW_13_KIND = 0x3F
ROW_13_KIND_BITS = 0x7F  # byte 1 AND $7F of the loop command is LOOP_COMMAND
PAGE_SKIP_PAGE = 0x1F  # byte 1 bits 4-0 of a page skip
LOOP_COMMAND = 0x4B  # the loop command object
SCENERY_COLOUR = 0x40  # byte 1 bit 6 of a row 14 object: the foreground or the backdrop
SCENERY_TERRAIN = 0x0F
SCENERY_BACKGROUND = 0x30
SCENERY_BACKGROUND_SHIFT = 4
SCENERY_VALUE = 0x07
BACKDROP_FIRST = 4  # a scenery value of 4-7 is a backdrop setting
HEADER_SCENERY = 0x07  # header byte 0 bits 2-0: the foreground, or a backdrop setting 4-7
HEADER_ENTRANCE = 0x38  # byte 0 bits 5-3
HEADER_ENTRANCE_SHIFT = 3
HEADER_TIME = 0xC0  # byte 0 bits 7-6
HEADER_TIME_SHIFT = 6
HEADER_TERRAIN = 0x0F  # header byte 1 bits 3-0
HEADER_BACKGROUND = 0x30  # byte 1 bits 5-4
HEADER_BACKGROUND_SHIFT = 4
HEADER_STYLE = 0xC0  # byte 1 bits 7-6: the area style, or 3 for the cloud flag
HEADER_STYLE_SHIFT = 6
STYLE_CLOUD = 3  # the style value that sets the cloud flag (and style 0)
CLOUD_FLAG = 3  # cloud_override when it is set
STYLE_TREES, STYLE_MUSHROOMS, STYLE_CANNONS = range(3)

# ---- Column layout and terrain ------------------------------------------------
ROWS = 13  # metatile rows 0-12 of a column
PAGE_COLUMNS = 16
BACK_SCENERY_PAGES = 3  # the background repeats every three pages
BACK_SCENERY_LAST_ROW = 10  # a background piece stops before row 11
PIECE_ROWS = 3  # the metatiles of a background piece, top first
TERRAIN_BYTE_ROWS = 8  # rows of terrain pattern byte 0 (byte 1: rows 8-12)
UNDERGROUND_FLOOR_ROW = 11  # from this row the terrain of an underground area is the ground block
CLOUD_TERRAIN_KEEP = 0x08  # in a cloud area pattern byte 1 keeps bit 3 only (row 11)
PALETTE_SHIFT = 6  # a metatile's palette: bits 7-6
COUNT_FREE = 0xFF  # an object slot's counter while the slot is free
OBJECT_SLOTS = 3
TO_FLOOR = 0x0F  # a fill count that reaches row 12 from any row
SIGN = 0x80
BYTE = 0xFF

# ---- The ROM tables of the builder (8, 9) ---------------------------------
# back_scenery_starts $92F7 (3), back_scenery_rows $92FA (144),
#   back_scenery_pieces $938A (36), fore_scenery_starts $93AE (3),
#   fore_scenery_rows $93B1 (39), floor_tiles_by_type $93D8 (4),
#   terrain_patterns $93DC (32), single_bit_masks $C68A (8),
#   storable_bound_by_palette $9504 (4).
BACK_SCENERY_STARTS = 0x92F7
BACK_SCENERY_ROWS = 0x92FA  # bits 7-4 the top row, bits 3-0 the piece (0 none)
BACK_SCENERY_PIECES = 0x938A  # 12 pieces of 3 metatiles
BACK_SCENERY_SETS = 3
BACK_SCENERY_PIECE_COUNT = 12
FORE_SCENERY_STARTS = 0x93AE
FORE_SCENERY_ROWS = 0x93B1  # 3 sets of 13 rows; 0 keeps the row
FORE_SCENERY_SETS = 3
FLOOR_TILES_BY_TYPE = 0x93D8
TERRAIN_PATTERNS = 0x93DC  # 16 patterns of 2 bytes
TERRAIN_PATTERN_COUNT = 16
SINGLE_BIT_MASKS = 0xC68A  # the bit of each row in a pattern byte
STORABLE_BOUND_BY_PALETTE = 0x9504  # per palette: the lowest metatile that the collision buffer keeps
PALETTES = 4
# The object tables: pulley_tiles $97B7 (3),
#   end_castle_pieces $97CF (55), side_pipe_shaft_codes $989F (4),
#   side_pipe_top_tiles $98A3 (4), side_pipe_bottom_tiles $98A7 (4),
#   pipe_top_tiles $98DD (8), coin_metatile_by_type $99EE (4),
#   castle_prop_rows $99FB (3), castle_prop_metatiles $99FE (3),
#   solid_metatile_by_type $9A25 (4), brick_metatile_by_type $9A29 (5),
#   stair_heights $9AA5 (9), stair_top_rows $9AAE (9), pit_top_metatile
#   $9B3D (4), bumpable_metatiles $BDE8 (14), wave_kinds $9728 (3).
PULLEY_TILES = 0x97B7  # the left pulley, the rope, the right pulley
END_CASTLE_PIECES = 0x97CF  # 11 rows of 5 metatiles, top first, the right column first
CASTLE_COLUMNS = 5
CASTLE_ROWS = 11
SIDE_PIPE_SHAFT_CODES = 0x989F  # by the column's counter: the shaft (0 none), the upper half, the lower half
SIDE_PIPE_TOP_TILES = 0x98A3
SIDE_PIPE_BOTTOM_TILES = 0x98A7
SIDE_PIPE_TILES = 4
PIPE_TOP_TILES = 0x98DD  # the tops, then the shafts, by the counter; the plain pipes 4 bytes on
PIPE_TOP_TILE_COUNT = 8
PLAIN_PIPE_TILES = 4
PIPE_SHAFT_TILES = 2
COIN_METATILE_BY_TYPE = 0x99EE
CASTLE_PROP_ROWS = 0x99FB  # the row of the axe, the chain, Bowser's bridge
CASTLE_PROP_METATILES = 0x99FE
CASTLE_PROPS = 3
CASTLE_PROP_FIRST = 2  # their row 13 kinds are 2, 3, 4
SOLID_METATILE_BY_TYPE = 0x9A25
BRICK_METATILE_BY_TYPE = 0x9A29  # by the type, then the cloud block
BRICK_CLOUD = 4
STAIR_HEIGHTS = 0x9AA5
STAIR_TOP_ROWS = 0x9AAE
STAIR_STEPS = 9  # the staircase counter's start
PIT_TOP_METATILE = 0x9B3D
BUMPABLE_METATILES = 0xBDE8  # the question blocks, the hidden blocks, the bricks with items
BUMPABLE_COUNT = 14
ITEM_BRICK_OTHER = 5  # the bricks outside ground areas are 5 entries on
WAVE_KINDS = 0x9728  # the enemy kind of the wave objects (row 13 kinds 8-10)
WAVE_COUNT = 3
WAVE_FIRST = 8
# loop_worlds $C06B (11), loop_pages $C076 (11), loop_rewind_offsets
#   $9BF8 (11): the loop checks and where they send the list back.
LOOP_REWIND_OFFSETS = 0x9BF8  # the area list offset of each loop check's rewind
LOOP_WORLDS = 0xC06B  # the world of each loop check
LOOP_PAGES = 0xC076  # the parse page of each loop check
LOOP_CHECKS = 11
LOOP_BACK_PAGES = 4  # send_player_back: the pages that the parser goes back

# The metatiles that the object routines load as immediates: the address of
# each operand (the routine in the comment).
# The metatiles that the object routines load as immediates, each at the
#   address of its operand (the *_AT constants): no metatile number of the
#   game is typed here.
GREEN_LEDGE_LEFT_AT = 0x9763  # build_green_ledge: the left end
GREEN_LEDGE_MIDDLE_AT = 0x976A  # the middle
GREEN_LEDGE_TRUNK_AT = 0x976F  # the trunk under the middle
GREEN_LEDGE_RIGHT_AT = 0x9774  # the right end
CAP_LEDGE_LEFT_AT = 0x9787  # build_cap_ledge: the left end
CAP_LEDGE_RIGHT_AT = 0x978C  # the right end
CAP_LEDGE_MIDDLE_AT = 0x979A  # the middle
CAP_LEDGE_STEM_TOP_AT = 0x97A4  # the stem's top
CAP_LEDGE_STEM_AT = 0x97A9  # the stem
CASTLE_DOOR_BRICK_AT = 0x986A  # build_end_castle: the brick past the door
SPOUT_TOP_AT = 0x9878  # build_spout_pipe: the top
SPOUT_MOUTH_AT = 0x987D  # the mouth under it
POND_SURFACE_AT = 0x995B  # build_pond: the surface
POND_WATER_AT = 0x9964  # the water under it
PRIZE_ROW_BLOCK_AT = 0x9974  # build_prize_row_*: the question block with a coin
BRIDGE_RAIL_AT = 0x9988  # build_rope_bridge_*: the rail
BRIDGE_AT = 0x9990  # the bridge under it
BALL_COLUMN_AT = 0x999A  # unused_ball_column: the flag ball
FLAGPOLE_BALL_AT = 0x999F  # build_flagpole: the ball
FLAGPOLE_AT = 0x99A8  # the pole
FLAGPOLE_BASE_AT = 0x99AD  # the solid block under it
ROPE_AT = 0x99EA  # draw_rope_tiles: the vertical rope
SCALE_ROPE_BLANK_AT = 0x99DE  # build_scale_rope: the blank of the column
USED_BLOCK_AT = 0x9A1F  # build_used_block
CANNON_TOP_AT = 0x9A6F  # build_cannon_stack: the barrel
CANNON_MIDDLE_AT = 0x9A78  # the top
CANNON_STAND_AT = 0x9A81  # the stand
STAIR_BLOCK_AT = 0x9ACF  # build_staircase: the solid block
SPRING_TOP_AT = 0x9AF7  # place_jump_spring: the top
SPRING_FOOT_AT = 0x9AFC  # the foot
WORLD_8_WATER_FLOOR_AT = 0x947A  # build_column: the terrain of a water area in world 8
CLOUD_FLOOR_AT = 0x9487  # the terrain of a cloud area
UNDERGROUND_FLOOR_AT = 0x94C7  # the terrain of an underground area from row 11
KEEP_TREE_MIDDLE_AT = 0x9B86  # fill_column_rows: a tree ledge middle is kept
KEEP_CAP_MIDDLE_AT = 0x9B8A  # a mushroom ledge middle is kept
FILL_COIN_BLOCK_AT = 0x9B8E  # the question block with a coin is replaced
KEEP_FROM_AT = 0x9B92  # the metatiles from this one on are kept (after the test above)
KEEP_GROUND_AT = 0x9B96  # the ground block is kept under a mushroom stem
STEM_OVER_GROUND_AT = 0x9B9A  # the mushroom stem

# The rows and counts of the object routines.
STEM_ROW = 1  # a mushroom ledge's stem top is one row under its cap
CASTLE_DOOR_ROW = 10
CASTLE_FIXED = 4  # build_end_castle: five columns
SIDE_PIPE_FIXED = 3  # the exit pipe and the entrance pipe: four columns
ENTRANCE_PIPE_ROW = 10  # the entrance pipe's t: the row of its lower half
ENTRANCE_PIPE_CLEAR_ROWS = 7  # it clears rows 0-6 over its shaft
ENTRANCE_PIPE_TOP_ROW = 7
VERTICAL_PIPE_FIXED = 1  # two columns
POND_SURFACE_ROW = 10
POND_WATER_ROW = 11
POND_WATER_COUNT = 1  # two rows
PRIZE_ROWS = (3, 7)  # build_prize_row_high, build_prize_row_low (row 12 kinds 6, 7)
PRIZE_ROW_FIRST = 6
BRIDGE_ROWS = (6, 7, 9)  # build_rope_bridge_high, _mid, _low (row 12 kinds 2-4)
BRIDGE_FIRST = 2
BALL_COLUMN_ROW = 2
FLAGPOLE_BALL_ROW = 0
FLAGPOLE_ROW = 1
FLAGPOLE_COUNT = 8  # rows 1-9
FLAGPOLE_BASE_ROW = 10
SCALE_ROPE_ROW = 1
PULLEY_ROW = 0
PIT_ROW = 8
BRIDGE_FIXED = 12  # Bowser's bridge: 13 columns
SIDE_PIPE_LOWEST_BOTTOM = 2  # draw_side_pipe needs the shaft's end row t - 2 to be a row

# The world X of what the objects start, from the X of the parser's column.
PIRANHA_X_OFFSET = 8  # build_vertical_pipe: the plant is in the middle of the pipe
FLAGPOLE_X_OFFSET = -8  # build_flagpole: the flag hangs left of the pole
WHIRLPOOL_X_OFFSET = -16  # build_pit: the whirlpool starts one column left of the pit
WHIRLPOOL_EXTRA_COLUMNS = 2  # its length: L + 2 columns
COLUMN_PIXELS = 16
ROW_PIXELS = 16
FIRST_ROW_Y = 32  # row 0 is under the status bar
WORD = 0xFFFF

# ---- The enemy lists -----------------------------------
ENEMY_LIST_END = 0xFF
ENEMY_ROW_LINK = 14  # an area change: 3 bytes
ENEMY_ROW_PAGE_SKIP = 15
ENEMY_PAGE_SELECT = 0x80
ENEMY_HARD_ONLY = 0x40
ENEMY_KIND = 0x3F
ENEMY_COLUMN = 0xF0  # byte 0 bits 7-4: the column (x 16 is the X in the page)
ENEMY_ROW_SHIFT = 4  # byte 0 shifted left 4: the row x 16 (the Y that the reader writes)
LINK_WORLD_SHIFT = 5  # byte 2 bits 7-5: the world of an area change
LINK_PAGE = 0x1F  # byte 2 bits 4-0: the entrance page
ENEMY_ENTRY_BYTES = 2
LINK_ENTRY_BYTES = 3

# ---- The port's forms (src/game/area.s: the structs and the flags) ----------------------
COLUMN_BYTES = 2 * ROWS  # an area_columns entry: the metatiles, then the collision column
RECORD_BYTES = 2  # ColumnRecord::column
EVENTS_COUNT_BYTES = 1  # ColumnRecord::events
EVENT_BYTES = 5  # ColumnEvent: routine (word), position (word), value (byte)
COLUMN_OFFSET_LIMIT = 0x8000  # the column word keeps its top bit for COLUMN_HAS_EVENTS
SPAWN_BYTES = 8  # SpawnRecord: kind, hard_only, x_pos (word), y_pos, area_byte, link_world, entrance_page
SPAWN_LIST_LIMIT = 0x100  # enemy_offset is a byte: the number of a record in its list
SPAWN_KINDS = {'end': 'SPAWN_END', 'skip': 'SPAWN_SKIP', 'link': 'SPAWN_LINK'}  # src/game/area.s
# The operand of read_enemy_spawns' kind test of enemy slot 5 ($C160, the
#   power-up's kind): no page skip may have that page.
SLOT_5_KIND_AT = 0xC160  # read_enemy_spawns: the operand of the kind that slot 5 reads (the power-up)
AREA_RECORD_BYTES = 5 + 2 + 2 + 2 * START_PAGES  # AreaRecord: 5 header bytes, spawn_list, rewinds, starts
REWIND_ENTRY_BYTES = 4  # RewindEntry: record (word), after (word)

# The run-time routine of each event (labels of src/game/area.s).
EVENT_ROUTINES = {
    'piranha': 'start_piranha_plant',
    'cannon': 'record_cannon',
    'whirlpool': 'record_whirlpool',
    'castle_flag': 'start_castle_flag',
    'spring': 'start_jump_spring',
    'flagpole': 'start_flagpole_flag',
    'axe': 'select_bowser_palette',
    'warp_zone': 'warp_zone_lock',
    'scroll_lock': 'toggle_scroll_lock',
    'wave': 'queue_wave_request',
    'loop_look': 'count_loop_looks',
    'backdrop': 'set_backdrop',
    'coin_brick': 'clear_coin_brick_flag',
    'hidden_1up': 'place_hidden_1up',
    'past_column': 'store_past_column',
    'jump': 'jump_to_column',
    'never_ends': 'backloading_never_ends',
}

# The objects: the routine of each object, by its row field
# and kind.
(VERTICAL_PIPE, LEDGE, BRICK_ROW, SOLID_ROW, COIN_ROW, BRICK_COLUMN, SOLID_COLUMN, PIT, PULLEY_ROPE,
 ROPE_BRIDGE, POND, PRIZE_ROW, LONG_ROPE, SCALE_ROPE, END_CASTLE, STAIRCASE, EXIT_PIPE, BALL_COLUMN,
 PRIZE_BLOCK, HIDDEN_1UP, ITEM_BRICK, COIN_BRICK, SPOUT_PIPE, USED_BLOCK, JUMP_SPRING, ENTRANCE_PIPE,
 FLAGPOLE, AXE, CASTLE_PROP, BOWSER_BRIDGE, WARP_ZONE, SCROLL_LOCK, WAVE, LOOP_OBJECT, SCENERY) = range(35)
LARGE_ROUTINES = {1: LEDGE, 2: BRICK_ROW, 3: SOLID_ROW, 4: COIN_ROW, 5: BRICK_COLUMN, 6: SOLID_COLUMN, 7: VERTICAL_PIPE}
ROW_12_ROUTINES = (PIT, PULLEY_ROPE, ROPE_BRIDGE, ROPE_BRIDGE, ROPE_BRIDGE, POND, PRIZE_ROW, PRIZE_ROW)
ROW_15_ROUTINES = (LONG_ROPE, SCALE_ROPE, END_CASTLE, STAIRCASE, EXIT_PIPE, BALL_COLUMN)
SMALL_ROUTINES = (PRIZE_BLOCK, PRIZE_BLOCK, PRIZE_BLOCK, HIDDEN_1UP, ITEM_BRICK, ITEM_BRICK, ITEM_BRICK,
                  COIN_BRICK, ITEM_BRICK, SPOUT_PIPE, USED_BLOCK, JUMP_SPRING)
ROW_13_ROUTINES = (ENTRANCE_PIPE, FLAGPOLE, AXE, CASTLE_PROP, BOWSER_BRIDGE, WARP_ZONE, SCROLL_LOCK,
                   SCROLL_LOCK, WAVE, WAVE, WAVE, LOOP_OBJECT, SCENERY)


class Rom:
    """The 32 KB program; $8000 is offset 0."""

    # Keep the 32 KB program ROM used by the area builder.
    def __init__(self, program):
        assert len(program) == 0x8000
        self.program = program

    # Read the byte at the original program ADDRESS.
    def byte(self, address):
        return self.program[address - PROGRAM_BASE]

    # Read a little-endian address from ROM bytes at LOW and HIGH.
    def word(self, low, high):
        return self.byte(low) | self.byte(high) << 8

    # Read SIZE bytes starting at the original program ADDRESS.
    def table(self, address, size):
        return self.program[address - PROGRAM_BASE: address - PROGRAM_BASE + size]


class Metatiles:
    """The metatile numbers and the tables of the builder's rules."""

    # Read the block numbers and area-building tables from ROM.
    def __init__(self, rom):
        b = rom.byte
        self.green = (b(GREEN_LEDGE_LEFT_AT), b(GREEN_LEDGE_MIDDLE_AT), b(GREEN_LEDGE_RIGHT_AT))
        self.trunk = b(GREEN_LEDGE_TRUNK_AT)
        self.cap = (b(CAP_LEDGE_LEFT_AT), b(CAP_LEDGE_MIDDLE_AT), b(CAP_LEDGE_RIGHT_AT))
        self.stem_top = b(CAP_LEDGE_STEM_TOP_AT)
        self.stem = b(CAP_LEDGE_STEM_AT)
        self.castle_door_brick = b(CASTLE_DOOR_BRICK_AT)
        self.spout = (b(SPOUT_TOP_AT), b(SPOUT_MOUTH_AT))
        self.pond = (b(POND_SURFACE_AT), b(POND_WATER_AT))
        self.prize_row_block = b(PRIZE_ROW_BLOCK_AT)
        self.bridge = (b(BRIDGE_RAIL_AT), b(BRIDGE_AT))
        self.ball = b(BALL_COLUMN_AT)
        self.flagpole = (b(FLAGPOLE_BALL_AT), b(FLAGPOLE_AT), b(FLAGPOLE_BASE_AT))
        self.rope = b(ROPE_AT)
        self.scale_blank = b(SCALE_ROPE_BLANK_AT)
        self.used_block = b(USED_BLOCK_AT)
        self.cannon = (b(CANNON_TOP_AT), b(CANNON_MIDDLE_AT), b(CANNON_STAND_AT))
        self.stair_block = b(STAIR_BLOCK_AT)
        self.spring = (b(SPRING_TOP_AT), b(SPRING_FOOT_AT))
        self.world_8_water_floor = b(WORLD_8_WATER_FLOOR_AT)
        self.cloud_floor = b(CLOUD_FLOOR_AT)
        self.underground_floor = b(UNDERGROUND_FLOOR_AT)
        self.keep_middles = (b(KEEP_TREE_MIDDLE_AT), b(KEEP_CAP_MIDDLE_AT))
        self.fill_coin_block = b(FILL_COIN_BLOCK_AT)
        self.keep_from = b(KEEP_FROM_AT)
        self.keep_ground = b(KEEP_GROUND_AT)
        self.stem_over_ground = b(STEM_OVER_GROUND_AT)
        self.back_starts = rom.table(BACK_SCENERY_STARTS, BACK_SCENERY_SETS)
        self.back_rows = rom.table(BACK_SCENERY_ROWS, BACK_SCENERY_SETS * BACK_SCENERY_PAGES * PAGE_COLUMNS)
        self.back_pieces = rom.table(BACK_SCENERY_PIECES, BACK_SCENERY_PIECE_COUNT * PIECE_ROWS)
        self.fore_starts = rom.table(FORE_SCENERY_STARTS, FORE_SCENERY_SETS)
        self.fore_rows = rom.table(FORE_SCENERY_ROWS, FORE_SCENERY_SETS * ROWS)
        self.floor_by_type = rom.table(FLOOR_TILES_BY_TYPE, AREA_TYPES)
        self.terrain_patterns = rom.table(TERRAIN_PATTERNS, 2 * TERRAIN_PATTERN_COUNT)
        self.bits = rom.table(SINGLE_BIT_MASKS, TERRAIN_BYTE_ROWS)
        self.storable = rom.table(STORABLE_BOUND_BY_PALETTE, PALETTES)
        self.pulley = rom.table(PULLEY_TILES, 3)
        self.castle = rom.table(END_CASTLE_PIECES, CASTLE_COLUMNS * CASTLE_ROWS)
        self.side_shaft = rom.table(SIDE_PIPE_SHAFT_CODES, SIDE_PIPE_TILES)
        self.side_top = rom.table(SIDE_PIPE_TOP_TILES, SIDE_PIPE_TILES)
        self.side_bottom = rom.table(SIDE_PIPE_BOTTOM_TILES, SIDE_PIPE_TILES)
        self.pipe_tops = rom.table(PIPE_TOP_TILES, PIPE_TOP_TILE_COUNT)
        self.coin_by_type = rom.table(COIN_METATILE_BY_TYPE, AREA_TYPES)
        self.prop_rows = rom.table(CASTLE_PROP_ROWS, CASTLE_PROPS)
        self.prop_metatiles = rom.table(CASTLE_PROP_METATILES, CASTLE_PROPS)
        self.solid_by_type = rom.table(SOLID_METATILE_BY_TYPE, AREA_TYPES)
        self.brick_by_type = rom.table(BRICK_METATILE_BY_TYPE, AREA_TYPES + 1)
        self.stair_heights = rom.table(STAIR_HEIGHTS, STAIR_STEPS)
        self.stair_tops = rom.table(STAIR_TOP_ROWS, STAIR_STEPS)
        self.pit_by_type = rom.table(PIT_TOP_METATILE, AREA_TYPES)
        self.bumpable = rom.table(BUMPABLE_METATILES, BUMPABLE_COUNT)
        self.wave_kinds = rom.table(WAVE_KINDS, WAVE_COUNT)

    def collision(self, column):
        """The collision buffer column of a column."""
        return bytes(v if v >= self.storable[v >> PALETTE_SHIFT] else 0 for v in column)


def area_of(area_byte):
    """(area type, list number) of an area byte."""
    return (area_byte & AREA_BYTE_MASK) >> AREA_TYPE_SHIFT, area_byte & AREA_NUMBER_MASK


# Find an area or enemy list address for AREA_TYPE and NUMBER.
# BASES selects the first list; LOW and HIGH hold its address bytes.
def list_address(rom, bases, low, high, area_type, number):
    i = rom.byte(bases + area_type) + number
    return rom.word(low + i, high + i)


class Header:
    """The two header bytes of an area list, as load_area_addresses leaves
    their variables (begin_area clears them before)."""

    # Decode the two area header bytes into entrance, timer and scenery
    # settings. A cloud style sets the cloud flag and uses style zero.
    def __init__(self, byte0, byte1):
        scenery = byte0 & HEADER_SCENERY
        self.backdrop = scenery if scenery >= BACKDROP_FIRST else 0
        self.foreground = 0 if scenery >= BACKDROP_FIRST else scenery
        self.entrance = (byte0 & HEADER_ENTRANCE) >> HEADER_ENTRANCE_SHIFT
        self.timer_setting = (byte0 & HEADER_TIME) >> HEADER_TIME_SHIFT
        self.terrain = byte1 & HEADER_TERRAIN
        self.background = (byte1 & HEADER_BACKGROUND) >> HEADER_BACKGROUND_SHIFT
        style = (byte1 & HEADER_STYLE) >> HEADER_STYLE_SHIFT
        self.cloud = CLOUD_FLAG if style == STYLE_CLOUD else 0
        self.style = 0 if style == STYLE_CLOUD else style


class Event:
    """A run-time event of a column build: its name (EVENT_ROUTINES), a
    world X (page x 256 + pixel) and a byte."""

    # Record the event NAME, its world X position and its byte VALUE.
    def __init__(self, name, x=0, value=0):
        self.name, self.x, self.value = name, x, value

    # Return the event fields used to compare or deduplicate events.
    def key(self):
        return (self.name, self.x, self.value)

    # Show the event name and its position and value in hexadecimal.
    def __repr__(self):
        return f"{self.name}(${self.x:04X}, ${self.value:02X})"


class NoObjectOnStartPage(Exception):
    """The start page has no object (other than a page skip): the original's
    read_area_objects repeats its backloading pass forever."""


class ColumnBuilder:
    """The original's column builder for one area, from
    begin_area at start page START. build() makes one column, as
    build_column does at steps 7 and 3 of a set; next_column() steps the
    parser, as steps 4 and 0 do. Each method follows the original routine
    named in its comment."""

    def __init__(self, tiles, area_type, objects, header, world, start):
        self.t = tiles
        self.area_type = area_type
        self.objects = objects  # the area list from its first object
        self.world = world
        self.style = header.style
        self.cloud = header.cloud
        self.terrain = header.terrain
        self.background = header.background
        self.foreground = header.foreground
        self.backdrop = header.backdrop
        # begin_area
        self.page = start
        self.column = 0
        self.backloading = start
        self.offset = 0
        self.object_page = 0
        self.page_step = 0
        self.slot_offset = [0] * OBJECT_SLOTS
        self.slot_count = [COUNT_FREE] * OBJECT_SLOTS
        self.mushroom_half = [0] * OBJECT_SLOTS
        self.staircase = 0
        self.slot = 0  # obj_slot
        self.behind = 0  # parser_behind
        # The hidden 1-up flag is the game's (
        # build_hidden_extra_life): the build makes each column with it
        # clear, and again with it set when the column has such a block.
        self.hidden_1up = 0
        self.hidden_1up_seen = False
        # column_metatiles: the backloading pass runs before the column is
        # cleared, so what it would draw is lost
        self.col = [0] * ROWS
        self.events = []

    def key(self):
        """The builder state that decides every later column and event: the
        parser, the list, the busy slots (their offset, counter and, for a
        mushroom ledge, its stem counter), a running staircase's counter,
        the scenery."""
        slots = []
        stair = None
        for x in range(OBJECT_SLOTS):
            if self.slot_count[x] == COUNT_FREE:
                slots.append(None)
                continue
            routine = self.routine_of(self.slot_offset[x])[0]
            half = self.mushroom_half[x] if routine == LEDGE and self.style == STYLE_MUSHROOMS else None
            if routine == STAIRCASE:
                stair = self.staircase
            slots.append((self.slot_offset[x], self.slot_count[x], half))
        return (self.page, self.column, self.offset, self.object_page, self.page_step, self.backloading,
                self.terrain, self.background, self.foreground, self.backdrop, tuple(slots), stair)

    def snapshot(self):
        c = object.__new__(ColumnBuilder)
        c.__dict__ = dict(self.__dict__)
        c.slot_offset = list(self.slot_offset)
        c.slot_count = list(self.slot_count)
        c.mushroom_half = list(self.mushroom_half)
        c.col = list(self.col)
        c.events = list(self.events)
        return c

    def b0(self, y):
        return self.objects[y]

    def b1(self, y):
        return self.objects[y + 1]

    def routine_of(self, y):
        """(routine, kind) of the object at offset Y (dispatch_area_object); kind: the routine's variant."""
        b0, b1 = self.b0(y), self.b1(y)
        row = b0 & ROW_FIELD
        if row == ROW_GROUP_14:
            return SCENERY, 0
        if row == ROW_GROUP_13:
            kind = b1 & ROW_13_KIND
            if not b1 & ROW_13_SPECIAL:
                return None, 0  # a page skip
            assert kind < len(ROW_13_ROUTINES), f"row 13 kind {kind} jumps past the table"
            return ROW_13_ROUTINES[kind], kind
        if row < ROW_GROUP_12:
            size = (b1 & GROUP_KIND) >> GROUP_SHIFT
            if size == 0:
                kind = b1 & SMALL_KIND
                assert kind < len(SMALL_ROUTINES), f"small kind {kind} is not in the lists"
                return SMALL_ROUTINES[kind], kind
            if size == PIPE_CLASS and b1 & PIPE_ENTERABLE:
                return VERTICAL_PIPE, 0
            return LARGE_ROUTINES[size], size
        kind = (b1 & GROUP_KIND) >> GROUP_SHIFT
        if row == ROW_GROUP_12:
            return ROW_12_ROUTINES[kind], kind
        assert row == ROW_GROUP_15
        assert kind < len(ROW_15_ROUTINES), f"row 15 kind {kind} is not in the lists"
        return ROW_15_ROUTINES[kind], kind

    def skip_object_bytes(self):
        self.offset += OBJECT_BYTES
        assert self.offset <= BYTE, "area_offset is a byte"
        self.page_step = 0

    # ---- one column (build_column) ----
    def build(self):
        """The column at the parser: (13 metatiles, events)."""
        self.events = []
        if self.backloading:
            self.read_area_objects()
        col = self.col = [0] * ROWS
        t = self.t
        if self.background:
            assert self.page < SIGN  # build_column's page mod 3 loop tests the sign
            i = (self.page % BACK_SCENERY_PAGES) * PAGE_COLUMNS + t.back_starts[self.background - 1] + self.column
            v = t.back_rows[i]
            if v:
                piece, row = v & 0x0F, v >> 4
                assert piece and row <= BACK_SCENERY_LAST_ROW
                for j in range(PIECE_ROWS):
                    col[row + j] = t.back_pieces[(piece - 1) * PIECE_ROWS + j]
                    if row + j == BACK_SCENERY_LAST_ROW:
                        break
        if self.foreground:
            start = t.fore_starts[self.foreground - 1]
            for row in range(ROWS):
                v = t.fore_rows[start + row]
                if v:
                    col[row] = v
        if self.area_type == TYPE_WATER and self.world == WORLD_8:
            floor = t.world_8_water_floor
        else:
            floor = t.cloud_floor if self.cloud else t.floor_by_type[self.area_type]
        low, high = t.terrain_patterns[2 * self.terrain], t.terrain_patterns[2 * self.terrain + 1]
        if self.cloud:
            high &= CLOUD_TERRAIN_KEEP
        for row in range(ROWS):
            if self.area_type == TYPE_UNDERGROUND and row == UNDERGROUND_FLOOR_ROW:
                floor = t.underground_floor
            pattern = low if row < TERRAIN_BYTE_ROWS else high
            if pattern & t.bits[row % TERRAIN_BYTE_ROWS]:
                col[row] = floor
        self.read_area_objects()
        return list(col), self.events

    def next_column(self):
        self.column += 1
        if self.column == PAGE_COLUMNS:
            self.column = 0
            self.page = (self.page + 1) & BYTE

    # ---- read_area_objects ----
    def read_area_objects(self):
        last = None
        while True:
            # a pass that leaves the list as it found it repeats forever
            # (backloading with no object on the start page)
            state = (self.offset, self.object_page, self.page_step, tuple(self.slot_count), self.backloading)
            if state == last:
                raise NoObjectOnStartPage(self.page)
            last = state
            x = OBJECT_SLOTS - 1
            while x >= 0:
                self.slot = x
                self.behind = 0
                y = self.offset
                if self.b0(y) == AREA_LIST_END or self.slot_count[x] != COUNT_FREE:
                    self.dispatch()
                else:
                    if self.b1(y) & PAGE_SELECT and not self.page_step:
                        self.page_step = 1
                        self.object_page = (self.object_page + 1) & BYTE
                    row = self.b0(y) & ROW_FIELD
                    taken = False
                    if row == ROW_GROUP_13 and not self.b1(y) & ROW_13_SPECIAL and not self.page_step:
                        self.object_page = self.b1(y) & PAGE_SKIP_PAGE
                        self.page_step = 1
                        self.skip_object_bytes()
                        taken = True
                    elif row == ROW_GROUP_14 and self.backloading:
                        self.dispatch()
                        taken = True
                    if not taken:
                        if self.object_page < self.page:
                            self.behind = 1
                            self.skip_object_bytes()
                        else:
                            self.dispatch()
                # age_active_object counts the slot of obj_slot (the end of
                # backloading sets it to 0)
                x = self.slot
                if self.slot_count[x] != COUNT_FREE:
                    self.slot_count[x] = (self.slot_count[x] - 1) & BYTE
                x -= 1
            if not (self.behind or self.backloading):
                return

    def dispatch(self):
        """dispatch_area_object and start_or_run_object."""
        x = self.slot
        busy = self.slot_count[x] != COUNT_FREE
        y = self.slot_offset[x] if busy else self.offset
        if self.b0(y) == AREA_LIST_END:
            return
        routine, kind = self.routine_of(y)
        if routine is None:
            return  # a page skip: nothing to do here
        if (self.b0(y) & ROW_FIELD) == ROW_GROUP_13 and self.b1(y) & ROW_13_KIND_BITS == LOOP_COMMAND:
            self.events.append(Event('loop_look'))
        if not busy:
            if self.object_page != self.page:
                if not ((self.b0(self.offset) & ROW_FIELD) == ROW_GROUP_14 and self.backloading):
                    return
            elif self.backloading:
                self.backloading = 0
                self.behind = 0
                self.slot = 0
                return
            elif self.b0(self.offset) >> COLUMN_SHIFT != self.column:
                return
            self.slot_offset[x] = self.offset
            self.skip_object_bytes()
        self.run(routine, kind, x)

    # ---- the helpers of the object routines ----
    def set_fixed_length(self, x, count):
        """True at the object's first column (its counter is set)."""
        if self.slot_count[x] & SIGN:
            self.slot_count[x] = count
            return True
        return False

    def row_len(self, x):
        """read_object_row_len: (r, L) of the slot's object."""
        y = self.slot_offset[x]
        return self.b0(y) & ROW_FIELD, self.b1(y) & LENGTH_FIELD

    def fill(self, metatile, row, count):
        """fill_column_rows: draw METATILE from ROW for COUNT + 1 rows (a
        byte tested for its sign), keeping some metatiles; the row after."""
        t = self.t
        while True:
            if row >= ROWS:
                # the first row of a fill past row 12 (a mushroom stem under
                # a cap at row 11): see past_column
                self.past_column(row, metatile)
                return row + 1
            v = self.col[row]
            if v == 0:
                keep = False
            elif v in t.keep_middles:
                keep = True
            elif v == t.fill_coin_block:
                keep = False
            elif v >= t.keep_from:
                keep = True
            else:
                keep = v == t.keep_ground and metatile == t.stem_over_ground
            if not keep:
                self.col[row] = metatile
            row += 1
            if row >= ROWS:
                return row
            count = (count - 1) & BYTE
            if count & SIGN:
                return row

    def put(self, row, metatile):
        if row >= ROWS:
            self.past_column(row, metatile)
            return
        self.col[row] = metatile

    def past_column(self, row, metatile):
        """A store at row 13. The original's column buffer (13 bytes) is
        followed by hammer_owner of misc slot 0, which gets
        the metatile; the column does not change. Its values (an enemy slot
        0-5, or this store) never meet a keep rule of fill_column_rows, so
        the store always happens."""
        assert row == ROWS, f"a store at row {row}, past the byte after the column"
        self.events.append(Event('past_column', 0, metatile))

    def column_x(self, offset=0):
        """The world X of the parser's column plus OFFSET, with the carry or
        borrow into the page (column_x_pixels, then the page)."""
        return (self.page * 256 + self.column * COLUMN_PIXELS + offset) & WORD

    def row_y(self, row):
        """row_y_pixels."""
        return (row * ROW_PIXELS + FIRST_ROW_Y) & BYTE

    # ---- the object routines ----
    def run(self, routine, kind, x):
        t = self.t
        ev = self.events.append
        if routine == VERTICAL_PIPE:
            self.set_fixed_length(x, VERTICAL_PIPE_FIXED)
            r, length = self.row_len(x)
            height = length & PIPE_HEIGHT
            n = self.slot_count[x]
            tile = n + (PLAIN_PIPE_TILES if kind else 0)
            if n:
                ev(Event('piranha', self.column_x(PIRANHA_X_OFFSET), self.row_y(r)))
            self.put(r, t.pipe_tops[tile])
            self.fill(t.pipe_tops[tile + PIPE_SHAFT_TILES], r + 1, (height - 1) & BYTE)
        elif routine == LEDGE and self.style == STYLE_TREES:
            r, length = self.row_len(x)
            n = self.slot_count[x]
            if n == 0:
                self.fill(t.green[2], r, 0)
                return
            if n & SIGN:
                self.slot_count[x] = length
                if self.page | self.column:
                    self.fill(t.green[0], r, 0)
                    return
            self.put(r, t.green[1])
            self.fill(t.trunk, r + 1, TO_FLOOR)
        elif routine == LEDGE and self.style == STYLE_MUSHROOMS:
            r, length = self.row_len(x)
            if self.set_fixed_length(x, length):
                self.mushroom_half[x] = self.slot_count[x] >> 1
                self.fill(t.cap[0], r, 0)
                return
            n = self.slot_count[x]
            if n == 0:
                self.fill(t.cap[2], r, 0)
                return
            self.put(r, t.cap[1])
            if n == self.mushroom_half[x]:
                self.put(r + STEM_ROW, t.stem_top)
                self.fill(t.stem, r + STEM_ROW + 1, TO_FLOOR)
        elif routine == LEDGE:
            assert self.style == STYLE_CANNONS  # build_cannon_stack (the header leaves styles 0-2)
            r, length = self.row_len(x)
            self.put(r, t.cannon[0])
            if length >= 1:
                self.put(r + 1, t.cannon[1])
            if length >= 2:
                self.fill(t.cannon[2], r + 2, length - 2)
            ev(Event('cannon', self.column_x(), self.row_y(r)))
        elif routine in (BRICK_ROW, SOLID_ROW, COIN_ROW):
            if routine == BRICK_ROW:
                metatile = t.brick_by_type[BRICK_CLOUD if self.cloud else self.area_type]
            elif routine == SOLID_ROW:
                metatile = t.solid_by_type[self.area_type]
            else:
                metatile = t.coin_by_type[self.area_type]
            r, length = self.row_len(x)
            self.set_fixed_length(x, length)
            self.fill(metatile, r, 0)
        elif routine in (BRICK_COLUMN, SOLID_COLUMN):
            metatile = (t.brick_by_type if routine == BRICK_COLUMN else t.solid_by_type)[self.area_type]
            r, length = self.row_len(x)
            self.fill(metatile, r, length)
        elif routine == PIT:
            r, length = self.row_len(x)
            if self.set_fixed_length(x, length) and self.area_type == TYPE_WATER:
                ev(Event('whirlpool', self.column_x(WHIRLPOOL_X_OFFSET),
                         ((length + WHIRLPOOL_EXTRA_COLUMNS) * COLUMN_PIXELS) & BYTE))
            self.fill(t.pit_by_type[self.area_type], PIT_ROW, TO_FLOOR)
        elif routine == PULLEY_ROPE:
            r, length = self.row_len(x)
            if self.set_fixed_length(x, length):
                tile = t.pulley[0]
            else:
                tile = t.pulley[1] if self.slot_count[x] else t.pulley[2]
            self.put(PULLEY_ROW, tile)
        elif routine == ROPE_BRIDGE:
            row = BRIDGE_ROWS[kind - BRIDGE_FIRST]
            r, length = self.row_len(x)
            self.set_fixed_length(x, length)
            self.put(row, t.bridge[0])
            self.fill(t.bridge[1], row + 1, 0)
        elif routine == POND:
            r, length = self.row_len(x)
            self.set_fixed_length(x, length)
            self.put(POND_SURFACE_ROW, t.pond[0])
            self.fill(t.pond[1], POND_WATER_ROW, POND_WATER_COUNT)
        elif routine == PRIZE_ROW:
            row = PRIZE_ROWS[kind - PRIZE_ROW_FIRST]
            r, length = self.row_len(x)
            self.set_fixed_length(x, length)
            self.put(row, t.prize_row_block)
        elif routine == LONG_ROPE:
            self.fill(t.rope, 0, TO_FLOOR)
        elif routine == SCALE_ROPE:
            self.fill(t.scale_blank, SCALE_ROPE_ROW, TO_FLOOR)
            r, length = self.row_len(x)
            self.fill(t.rope, SCALE_ROPE_ROW, length)
        elif routine == END_CASTLE:
            r, top = self.row_len(x)
            assert top < CASTLE_ROWS
            self.set_fixed_length(x, CASTLE_FIXED)
            n = self.slot_count[x]
            for row in range(top, CASTLE_ROWS):
                self.put(row, t.castle[(row - top) * CASTLE_COLUMNS + n])
            if self.page:
                if n == 1 or (top == 0 and n == 3):
                    self.put(CASTLE_DOOR_ROW, t.castle_door_brick)
                elif n == 2:
                    ev(Event('castle_flag', self.column_x()))
        elif routine == STAIRCASE:
            r, length = self.row_len(x)
            if self.set_fixed_length(x, length):
                self.staircase = STAIR_STEPS
            self.staircase -= 1
            assert self.staircase >= 0, "a staircase of more than 9 columns reads past its tables"
            self.fill(t.stair_block, t.stair_tops[self.staircase], t.stair_heights[self.staircase])
        elif routine in (EXIT_PIPE, ENTRANCE_PIPE):
            self.set_fixed_length(x, SIDE_PIPE_FIXED)
            if routine == EXIT_PIPE:
                r, bottom = self.row_len(x)
            else:
                bottom = ENTRANCE_PIPE_ROW
            assert bottom >= SIDE_PIPE_LOWEST_BOTTOM
            n = self.slot_count[x]
            row = bottom - 1
            shaft = t.side_shaft[n]
            if shaft:
                row = self.fill(shaft, 0, bottom - 2)
            self.put(row, t.side_top[n])
            self.put(row + 1, t.side_bottom[n])
            if routine == ENTRANCE_PIPE and shaft:
                for r in range(ENTRANCE_PIPE_CLEAR_ROWS):
                    self.put(r, 0)
                self.put(ENTRANCE_PIPE_TOP_ROW, t.pipe_tops[n])
        elif routine == BALL_COLUMN:
            r, length = self.row_len(x)
            self.fill(t.ball, BALL_COLUMN_ROW, length)
        elif routine == PRIZE_BLOCK:
            r, length = self.row_len(x)
            self.fill(t.bumpable[kind], r, 0)
        elif routine == HIDDEN_1UP:
            self.hidden_1up_seen = True
            if self.hidden_1up:
                self.hidden_1up = 0
                self.item_brick(x, kind)
        elif routine == ITEM_BRICK:
            self.item_brick(x, kind)
        elif routine == COIN_BRICK:
            ev(Event('coin_brick'))
            self.item_brick(x, kind)
        elif routine == SPOUT_PIPE:
            r, length = self.row_len(x)
            self.put(r, t.spout[0])
            self.put(r + 1, t.spout[1])
        elif routine == USED_BLOCK:
            r, length = self.row_len(x)
            self.fill(t.used_block, r, 0)
        elif routine == JUMP_SPRING:
            r, length = self.row_len(x)
            ev(Event('spring', self.column_x(), self.row_y(r)))
            self.put(r, t.spring[0])
            self.put(r + 1, t.spring[1])
        elif routine == FLAGPOLE:
            self.put(FLAGPOLE_BALL_ROW, t.flagpole[0])
            self.fill(t.flagpole[1], FLAGPOLE_ROW, FLAGPOLE_COUNT)
            self.put(FLAGPOLE_BASE_ROW, t.flagpole[2])
            ev(Event('flagpole', self.column_x(FLAGPOLE_X_OFFSET)))
        elif routine in (AXE, CASTLE_PROP, BOWSER_BRIDGE):
            if routine == AXE:
                ev(Event('axe'))
            if routine == BOWSER_BRIDGE:
                self.set_fixed_length(x, BRIDGE_FIXED)
            i = kind - CASTLE_PROP_FIRST
            self.fill(t.prop_metatiles[i], t.prop_rows[i], 0)
        elif routine == WARP_ZONE:
            ev(Event('warp_zone'))
        elif routine == SCROLL_LOCK:
            ev(Event('scroll_lock'))
        elif routine == WAVE:
            ev(Event('wave', 0, t.wave_kinds[kind - WAVE_FIRST]))
        elif routine == LOOP_OBJECT:
            pass  # the loop command draws nothing; dispatch counts its looks
        elif routine == SCENERY:
            b1 = self.b1(self.slot_offset[x])
            if not b1 & SCENERY_COLOUR:
                self.terrain = b1 & SCENERY_TERRAIN
                self.background = (b1 & SCENERY_BACKGROUND) >> SCENERY_BACKGROUND_SHIFT
            else:
                v = b1 & SCENERY_VALUE
                if v >= BACKDROP_FIRST:
                    self.backdrop = v
                    self.foreground = 0
                    ev(Event('backdrop', 0, v))
                else:
                    self.foreground = v
        else:
            raise AssertionError(routine)

    def item_brick(self, x, kind):
        """build_item_brick: the bumpable metatile of KIND (5 entries on
        outside ground areas) at the object's row."""
        r, length = self.row_len(x)
        entry = kind + (0 if self.area_type == TYPE_GROUND else ITEM_BRICK_OTHER)
        self.fill(self.t.bumpable[entry], r, 0)


# ---- The streams of records ---------------------------------------------------------------
class Record:
    """One column build of the original: its column number (page x 16 +
    column), its metatiles, its events, the column when the hidden 1-up
    flag is set (None when the column has no hidden 1-up block)."""

    def __init__(self, number, column, events, variant, key, state):
        self.number = number
        self.column = column
        self.events = events
        self.variant = variant
        self.key = key  # the builder state before the build
        self.state = state  # the builder before the build (for the loop rewinds)
        self.jump = None  # (stream, index): the record after this one, when it is not the next


class Stream:
    """The records of one run of the builder: from page 0 until its columns
    repeat after the last object; from another start page or after a loop
    rewind until its state is the state of the stream from page 0 at the
    same column (then it jumps there)."""

    def __init__(self, name):
        self.name = name
        self.records = []
        self.entry = None  # (stream, index) when the stream has no record of its own
        self.index = None  # the stream from page 0: (column, state) -> its record


def column_number(builder):
    return builder.page * PAGE_COLUMNS + builder.column


def build_record(builder):
    """One build of BUILDER, with its hidden 1-up variant."""
    key = builder.key()
    number = column_number(builder)
    before = builder.snapshot()
    column, events = builder.build()
    variant = None
    if builder.hidden_1up_seen:
        other = before.snapshot()
        other.hidden_1up = 1
        alt, alt_events = other.build()
        assert [e.key() for e in alt_events] == [e.key() for e in events]
        assert other.key() == builder.key(), "a hidden 1-up block changes no later column"
        variant = alt
        builder.hidden_1up_seen = False
        events = events + [Event('hidden_1up')]
    return Record(number, column, events, variant, key, before)


def list_ended(builder):
    return builder.objects[builder.offset] == AREA_LIST_END and all(c == COUNT_FREE for c in builder.slot_count)


def main_stream(builder):
    """The stream from page 0. After the last object a column depends only
    on its place in the three-page background cycle, so the stream jumps
    back three pages once that cycle has been built."""
    stream = Stream('page 0')
    cycle = {}
    while True:
        if list_ended(builder):
            key = builder.key()
            norm = (builder.page % BACK_SCENERY_PAGES,) + key[1:]
            if norm in cycle:
                stream.records[-1].jump = (stream, cycle[norm])
                stream.index = {(r.number, r.key): i for i, r in enumerate(stream.records)}
                return stream
            cycle[norm] = len(stream.records)
        stream.records.append(build_record(builder))
        builder.next_column()


def joined_stream(name, builder, main):
    """A stream that runs until its builder state is MAIN's at the same
    column; from there the two make the same columns and events."""
    stream = Stream(name)
    while True:
        at = main.index.get((column_number(builder), builder.key()))
        if at is not None:
            if stream.records:
                stream.records[-1].jump = (main, at)
            else:
                stream.entry = (main, at)
            return stream
        assert len(stream.records) < len(main.records), f"{name} never joins the stream from page 0"
        stream.records.append(build_record(builder))
        builder.next_column()


def send_player_back(builder, rom, check):
    """The builder's part of send_player_back: the parse
    page and the area object page go back 4 pages, the area page flag
    clears, the list goes back to the check's rewind offset. The object
    slots, the staircase and the scenery stay."""
    b = builder.snapshot()
    b.page = (b.page - LOOP_BACK_PAGES) & BYTE
    b.object_page = (b.object_page - LOOP_BACK_PAGES) & BYTE
    b.page_step = 0
    b.offset = rom.byte(LOOP_REWIND_OFFSETS + check)
    return b


class Area:
    """An area as the game plays it: an area list with its header and area
    type (and the world, for the water areas of world 8), its enemy list,
    and its streams."""

    def __init__(self, rom, tiles, area_byte, world, worlds):
        self.area_type, self.number = area_of(area_byte)
        self.area_byte = area_byte & AREA_BYTE_MASK
        self.world = world
        self.worlds = worlds  # the worlds where the game plays it
        address = list_address(rom, AREA_LIST_BASES, AREA_LIST_LOW, AREA_LIST_HIGH, self.area_type, self.number)
        self.header = Header(rom.byte(address), rom.byte(address + 1))
        self.objects = rom.program[address + HEADER_BYTES - PROGRAM_BASE:]
        self.enemy_list = list_address(rom, ENEMY_LIST_BASES, ENEMY_LIST_LOW, ENEMY_LIST_HIGH,
                                       self.area_type, self.number)
        self.rom, self.tiles = rom, tiles
        self.main = main_stream(self.builder(0))
        self.starts = {0: (self.main, 0)}  # page: (stream, index), or None: the page has no object
        for page in range(1, START_PAGES):
            self.add_start(page)
        self.rewinds = {}  # (stream, index) of the next record at a check: the entry after the rewind
        self.extra = []  # the streams after the rewinds

    def builder(self, start):
        return ColumnBuilder(self.tiles, self.area_type, self.objects, self.header, self.world, start)

    def add_start(self, page):
        """The stream from start page PAGE, or None when the page has no
        object: there the original's first column never ends."""
        try:
            stream = joined_stream(f"page {page}", self.builder(page), self.main)
        except NoObjectOnStartPage:
            self.starts[page] = None
            return
        self.starts[page] = stream.entry or (stream, 0)

    def has_loops(self):
        return any(e.name == 'loop_look' for r in self.main.records for e in r.events)

    def add_rewinds(self):
        """The streams after the loop rewinds. A check runs
        at column 0 of its page, before that column's build (the builder
        waits between two sets: the next record is that column's) or after
        it (the frames after step 7: the next record is the next column's).
        So the record that the builder reads next names the builder's state
        at the check, in every stream the game can be in, and that record
        gets the stream that follows the rewind from that state. The streams
        after a rewind are searched the same way until no new one comes. A
        check runs only in play: in a stream from start page S from page
        S + 2 on, and not at the first column of a stream after a rewind
        made before that column's build (the check has just cleared
        loop_command, and no build has looked at a loop object since)."""
        rom = self.rom
        assert len(self.worlds) == 1, "an area with loops is played in one world"
        checks = {}
        for check in range(LOOP_CHECKS):
            if rom.byte(LOOP_WORLDS + check) in self.worlds:
                number = rom.byte(LOOP_PAGES + check) * PAGE_COLUMNS
                assert number not in checks, "two checks of one world at one page"
                checks[number] = check
        streams = [(self.main, 0, True)]
        for page, entry in self.starts.items():
            if entry and entry[0] is not self.main:
                streams.append((entry[0], (page + START_SET_PAGES) * PAGE_COLUMNS, True))
        done = set()
        while streams:
            stream, play, first_before = streams.pop()
            if id(stream) in done:
                continue
            done.add(id(stream))
            for i, record in enumerate(stream.records):
                check = checks.get(record.number)
                if check is None or record.number < play:
                    continue
                moments = [(record.jump or (stream, i + 1), True)]
                if i or first_before:
                    moments.insert(0, ((stream, i), False))
                for at, built in moments:
                    if at in self.rewinds:
                        continue
                    b = record.state.snapshot()
                    if built:
                        b.build()
                    b = send_player_back(b, rom, check)
                    if built:
                        b.next_column()
                    name = f"rewind {check} {'after' if built else 'before'} from {stream.name}"
                    after = joined_stream(name, b, self.main)
                    self.rewinds[at] = after.entry or (after, 0)
                    if after.records:
                        streams.append((after, 0, built))
                        self.extra.append(after)

    def streams(self):
        return [self.main] + [e[0] for e in self.starts.values() if e and e[0] is not self.main] + self.extra


# ---- The enemy lists ----------------------------------------------------------------------
class SpawnEntry:
    """One record of the port's enemy list: an entry with its page resolved
    by the reader's rules."""

    def __init__(self, kind, x=0, y=0, enemy=0, hard=False, area_byte=0, world=0, page=0):
        self.kind = kind  # 'enemy', 'link', 'skip', 'end'
        self.x = x  # world X: page x 256 + column x 16
        self.y = y  # the row x 16 (8 bits), as the reader writes it into the slot
        self.enemy = enemy  # byte 1 AND $3F: the enemy kind (the page of a skip)
        self.hard = hard  # the entry spawns only with hard mode 2
        self.area_byte = area_byte  # a link: the area byte, all 8 bits
        self.world = world  # a link: the world it counts in
        self.page = page  # a link: the entrance page


def spawn_entries(rom, address):
    """The records of the enemy list at ADDRESS. The page of each entry
    follows the reader's rules: an entry's page
    select bit adds 1 to the running page only while the page flag is
    clear, and sets the flag; a row 15 entry is a page skip only while the
    flag is clear, and sets it; the flag clears when an entry is stepped
    past. So the entry after a page skip has its page select ignored, and a
    row 15 entry with bit 7 set is an enemy at row 15. The pages
    do not depend on when the entries are read: an entry that waits keeps
    the flag set, so its page select counts once, and a rewind starts the
    list again from its first entry with the page and the flag clear."""
    entries = []
    page = 0
    flag = 0
    offset = 0
    while True:
        b0 = rom.byte(address + offset)
        if b0 == ENEMY_LIST_END:
            entries.append(SpawnEntry('end'))
            return entries
        b1 = rom.byte(address + offset + 1)
        row = b0 & ROW_FIELD
        if b1 & ENEMY_PAGE_SELECT and not flag:
            page = (page + 1) & BYTE
            flag = 1
        if row == ENEMY_ROW_PAGE_SKIP and not flag:
            page = b1 & ENEMY_KIND
            flag = 1
            entries.append(SpawnEntry('skip', enemy=b1 & ENEMY_KIND))
            offset += ENEMY_ENTRY_BYTES
            continue
        x = (page << 8 | (b0 & ENEMY_COLUMN)) & WORD
        y = (b0 << ENEMY_ROW_SHIFT) & BYTE
        if row == ENEMY_ROW_LINK:
            b2 = rom.byte(address + offset + 2)
            entries.append(SpawnEntry('link', x, y, b1 & ENEMY_KIND, area_byte=b1,
                                      world=b2 >> LINK_WORLD_SHIFT, page=b2 & LINK_PAGE))
            offset += LINK_ENTRY_BYTES
        else:
            entries.append(SpawnEntry('enemy', x, y, b1 & ENEMY_KIND, hard=bool(b1 & ENEMY_HARD_ONLY)))
            offset += ENEMY_ENTRY_BYTES
        flag = 0


def game_starts(rom):
    """Every (area byte, world, start page) that the game's own tables give
    begin_area: each slot of each world from page 0, the
    level's halfway page (not in the pipe intro areas: the player walks
    there in the entry task, where the timer does not count, and their enemy list is empty), and the entrance page of every
    area change in the world it names. The streams cover every page 0-31
    of each area; these starts decide which areas there are and their
    worlds, and each of them must have an object."""
    starts = rom.table(WORLD_AREA_STARTS, WORLDS)
    slots = rom.table(AREA_SLOTS, SLOTS)
    halfway = rom.table(HALFWAY_PAGES, 2 * WORLDS)
    found = set()
    for w in range(WORLDS):
        end = starts[w + 1] if w + 1 < WORLDS else SLOTS
        level = 0
        for s in range(starts[w], end):
            area_byte = slots[s] & AREA_BYTE_MASK
            found.add((area_byte, w, 0))
            t, n = area_of(area_byte)
            address = list_address(rom, AREA_LIST_BASES, AREA_LIST_LOW, AREA_LIST_HIGH, t, n)
            if Header(rom.byte(address), rom.byte(address + 1)).entrance in ENTRANCE_PIPE_INTROS:
                continue
            byte = halfway[2 * w + level // 2]
            page = byte >> 4 if level % 2 == 0 else byte & 0x0F
            found.add((area_byte, w, page))
            level += 1
    for t in range(AREA_TYPES):
        for n in range(LISTS_OF_TYPE[t]):
            address = list_address(rom, ENEMY_LIST_BASES, ENEMY_LIST_LOW, ENEMY_LIST_HIGH, t, n)
            for e in spawn_entries(rom, address):
                if e.kind == 'link':
                    found.add((e.area_byte & AREA_BYTE_MASK, e.world, e.page))
    return found


def game_areas(rom, tiles):
    """{area byte: Area}, one for each of the 34 area lists, with the
    worlds where the game plays it."""
    starts = game_starts(rom)
    worlds = {}
    for area_byte, w, _page in starts:
        worlds.setdefault(area_byte, set()).add(w)
    areas = {}
    for area_byte in sorted(worlds):
        t, n = area_of(area_byte)
        world_8 = WORLD_8 in worlds[area_byte]
        # a water area is played in world 8 or in the others, never both
        assert t != TYPE_WATER or not world_8 or worlds[area_byte] == {WORLD_8}
        world = WORLD_8 if t == TYPE_WATER and world_8 else min(worlds[area_byte])
        areas[area_byte] = Area(rom, tiles, area_byte, world, worlds[area_byte])
    assert len(areas) == sum(LISTS_OF_TYPE)
    for area_byte, _world, page in starts:
        assert areas[area_byte].starts[page], f"area ${area_byte:02X} starts at page {page}: no object there"
    for area in areas.values():
        if area.has_loops():
            area.add_rewinds()
    return areas


# ---- The port's forms ------------------------------------------------------------------
def record_events(record):
    """The record's events as the port writes them: the loop looks of a
    column in one event (only their count matters: the loop check reads
    loop_command after the column)."""
    looks = sum(1 for e in record.events if e.name == 'loop_look')
    out = []
    for e in record.events:
        if e.name != 'loop_look':
            out.append(e)
        elif looks:
            out.append(Event('loop_look', 0, looks))
            looks = 0
    return out


# area_columns (a data bank): every distinct column once, 26 bytes: the 13
#   metatiles, row 0 first, then the 13 bytes of its collision buffer column
#   (the metatile, or 0 below storable_bound_by_palette of its palette).
class Layout:
    """area_columns and area_programs: every stream of every area, each
    record at its offset."""

    def __init__(self, tiles, areas):
        self.tiles = tiles
        self.columns = {}  # metatiles -> offset in area_columns
        self.column_bytes = bytearray()
        self.offset = {}  # (id(stream), index) -> offset in area_programs
        self.streams = []
        seen = set()
        for area in areas:
            for stream in area.streams():
                if id(stream) not in seen:
                    seen.add(id(stream))
                    self.streams.append(stream)
        size = 0
        for stream in self.streams:
            for i, r in enumerate(stream.records):
                self.offset[(id(stream), i)] = size
                size += RECORD_BYTES + self.events_bytes(r)
        self.never_ends = size  # the record of a start page without an object
        size += RECORD_BYTES + EVENTS_COUNT_BYTES + EVENT_BYTES
        self.size = size

    @staticmethod
    def event_count(record):
        return len(record_events(record)) + (1 if record.jump else 0)

    def events_bytes(self, record):
        n = self.event_count(record)
        return EVENTS_COUNT_BYTES + EVENT_BYTES * n if n else 0

    def column(self, metatiles):
        metatiles = bytes(metatiles)
        if metatiles not in self.columns:
            self.columns[metatiles] = len(self.column_bytes)
            entry = metatiles + self.tiles.collision(metatiles)
            assert len(entry) == COLUMN_BYTES
            self.column_bytes += entry
            assert len(self.column_bytes) <= COLUMN_OFFSET_LIMIT
        return self.columns[metatiles]

    def at(self, entry):
        stream, i = entry
        return self.offset[(id(stream), i)]

    def start(self, area, page):
        entry = area.starts[page]
        return self.never_ends if entry is None else self.at(entry)

    # area_programs (a data bank): the ColumnRecords. A record: its column
    #   (word: the offset in area_columns; COLUMN_HAS_EVENTS when events follow),
    #   then with events their count (byte) and the events, 5 bytes each: the
    #   run-time routine (word: a label of src/game/area.s), a position (word: a
    #   world X, page x 256 + pixel, or an offset), a value (byte). The record
    #   of a start page that has no object: one event that never ends.
    def programs(self, host):
        data = HostData()

        def event(name, position=0, value=0):
            routine = EVENT_ROUTINES[name]
            host.imports.add(routine)
            data.word(f".loword({routine})", position)
            data.byte(value)

        def head(column, count):
            if count:
                host.imports.add('COLUMN_HAS_EVENTS')
                data.word(f"${column:04X}|COLUMN_HAS_EVENTS")
                data.byte(count)
            else:
                data.word(column)

        for stream in self.streams:
            for r in stream.records:
                events = record_events(r)
                head(self.column(r.column), self.event_count(r))
                for e in events:
                    if e.name == 'hidden_1up':
                        event('hidden_1up', self.column(r.variant))
                    else:
                        event(e.name, e.x, e.value)
                if r.jump:
                    event('jump', self.at(r.jump))
        # the record of a start page without an object: its column is never
        # copied (the event never ends), so it names the first column
        head(0, 1)
        event('never_ends')
        assert data.size() == self.size
        return data


# spawn_records (a data bank): each enemy list as SpawnRecords of 8 bytes in list order, with the pages resolved here
#   by the reader's rules: kind (byte 1 AND $3F, or SPAWN_END,
#   SPAWN_SKIP: a page skip that the reader takes, where slot 5 stops as at
#   the original's, SPAWN_LINK), hard_only (1: only with hard mode 2),
#   x_pos (word: page x 256 + column x 16), y_pos (row x 16), and for a link
#   its area byte, its world and its entrance page.
def spawn_records(rom, areas, host):
    """spawn_records: each area's enemy list as SpawnRecords, in list order;
    {area byte: the offset of its first record}."""
    data = HostData()
    first = {}
    size = 0
    slot_5_kind = rom.byte(SLOT_5_KIND_AT)
    for area_byte, area in sorted(areas.items()):
        first[area_byte] = size
        entries = spawn_entries(rom, area.enemy_list)
        assert len(entries) <= SPAWN_LIST_LIMIT, "enemy_offset is a byte"
        for e in entries:
            if e.kind == 'enemy':
                kind = e.enemy
            else:
                # the reader's slot 5 lets a skip pass only as the power-up's
                # kind would: no page skip has that page
                assert e.kind != 'skip' or e.enemy != slot_5_kind
                kind = f"<({SPAWN_KINDS[e.kind]})"
                host.imports.add(SPAWN_KINDS[e.kind])
            data.byte(kind, 1 if e.hard else 0)
            data.word(e.x)
            link = e.kind == 'link'
            data.byte(e.y, e.area_byte if link else 0, e.world if link else 0, e.page if link else 0)
            size += SPAWN_BYTES
    assert data.size() == size
    return data, first


# area_records (a data bank): area_by_byte, a word for each area byte AND
#   $7F: the offset of its AreaRecord (0: no list has that area byte). An
#   AreaRecord: the header values (entrance, timer_setting, backdrop,
#   area_style, cloud_override as begin_area leaves them), the
#   offset of its first record in spawn_records, the offset of its rewind table
#   (0: none), then for each start page 0-31 the offset of the first record
#   in area_programs. A rewind table: per entry the record that the builder
#   reads next at a loop check and the record to read after the rewind; it
#   holds every record that the builder can read next at a check of the
#   area (Area.add_rewinds), so the run-time search always ends in it.
def area_records(layout, areas, spawn_first):
    """area_records: area_by_byte, the AreaRecords, the rewind tables."""
    data = HostData()
    record = {}
    tables = {}
    offset = 2 * AREA_BYTES
    for area_byte in sorted(areas):
        record[area_byte] = offset
        offset += AREA_RECORD_BYTES
    for area_byte, area in sorted(areas.items()):
        if area.rewinds:
            tables[area_byte] = offset
            offset += REWIND_ENTRY_BYTES * len(area.rewinds)
    data.word(*(record.get(b, 0) for b in range(AREA_BYTES)))
    for area_byte, area in sorted(areas.items()):
        h = area.header
        data.byte(h.entrance, h.timer_setting, h.backdrop, h.style, h.cloud)
        data.word(spawn_first[area_byte], tables.get(area_byte, 0))
        data.word(*(layout.start(area, page) for page in range(START_PAGES)))
    for _area_byte, area in sorted(areas.items()):
        for at, after in sorted(area.rewinds.items(), key=lambda kv: layout.at(kv[0])):
            data.word(layout.at(at), layout.at(after))
    assert data.size() == offset
    return data


# world_area_starts, area_slots (a data bank): as the ROM has them.
def build(program, host):
    """Build area columns, spawn records and area tables in host data."""
    rom = Rom(program)
    tiles = Metatiles(rom)
    areas = game_areas(rom, tiles)
    layout = Layout(tiles, areas.values())
    programs = layout.programs(host)
    host.blob_at(bytes(layout.column_bytes), "area_columns")
    host.blob_at(programs, "area_programs")
    spawn, first = spawn_records(rom, areas, host)
    host.blob_at(spawn, "spawn_records")
    host.blob_at(area_records(layout, areas, first), "area_records")
    host.blob_at(rom.table(WORLD_AREA_STARTS, WORLDS), "world_area_starts")
    host.blob_at(rom.table(AREA_SLOTS, SLOTS), "area_slots")
