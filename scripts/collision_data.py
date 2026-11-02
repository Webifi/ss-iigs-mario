"""The data of the collision and score part of the game logic.

The original program keeps the rules of its collisions, block hits, score
numbers and status bar numbers in small tables. This builder reads each one
from the program ROM at the address that document 07 gives (07 section n in
each comment) and writes it in the form that the 65816 code reads, as host
data in bank 0 (GAMEDATA, host.game_blob_at): the game logic runs with
DBR = 0 and reads each table with absolute indexed addressing.

Readers: src/game/collision.s (the boxes, the tile tests, the hits) and
src/game/score.s (the score numbers, the digits, the status numbers, the
game timer).

ROM tables read (address, format) and the forms written (label: layout):

  $DF8B solid_bound_by_palette, $DF96 climbable_bound_by_palette: 4 bytes
        each, one metatile bound per palette class (the metatile's bits
        7-6).
        metatile_class: 256 bytes, one per metatile. Bit 7: solid (the
        metatile is at or above its class's solid bound); bit 6: climbable
        (at or above the climbable bound). The code reads it with
        BIT metatile_class,X: N = solid, V = climbable.
  $BDE8 bumpable_metatiles: 14 metatiles.
        bump_metatiles: the 14 metatiles, in the original's order.
        bump_gifts: 14 bytes, the gift of each entry: the entry number,
        and entries 9-13 (the bricks of the areas that are not ground
        areas) the same gifts as 4-8 (07 section 6, hit_block).
        BUMP_METATILES_SIZE: the entries (the search's length).
  $E3B0 tile_point_x_adders, $E3CC tile_point_y_adders: 28 bytes each.
        tile_point_x, tile_point_y: the same bytes: the X and Y offset of
        each test point from the object's X and Y.
  $E3AD tile_adder_set_starts: 3 bytes.
        tile_point_sets: the first test point of the player's three sets.
  $DC62 player_head_limits: 2 bytes.
        player_head_limits: the same bytes.
  $E1FD hit_box_shapes: 12 rows of 4 bytes.
        hit_box_shapes: the same rows (left, top, right, bottom).
  $DE03 area_change_waits, $DE25 climb_x_adders, $DE27 climb_page_adders,
  $DE29 flagpole_score_heights, $BCEB block_y_by_size, $D84F
  kicked_shell_speeds, $D851 demoted_koopa_speeds, $D892
  shell_chain_scores, $D965 stomp_score_codes, $D9D2 shell_revive_times,
  $D736 bowser_disguises, $DFBF enemy_land_x_speeds, $DC17
  small_lift_stand_adders, $849F score_number_tiles, $BBF8
  coin_digit_places, $BBFA score_digit_places, $BBFC
  status_nybbles_by_player: the same bytes, under the same names.
  $DA25 enemy_bit_set_masks: 7 masks.
        enemy_bit_masks: the masks of enemy numbers 0-5 (the seventh has
        no reader).
  $DFB9 enemy_landing_states: 6 bytes.
        enemy_landing_states: 128 bytes from $DFB9: the table and the bytes
        after it, which the original reads for a state of 6 to $7F (07
        section 17, leftover 14).
  $87F2 warp_zone_worlds (02): groups of 4 bytes, the world digit tile of
        each pipe. $9CB4 world_area_starts and $9CBC area_slots (06): the
        area byte of each world's first area.
        warp_pipe_worlds: 12 bytes, 3 per group (left, middle, right pipe)
        for the groups 0-3 of warp_zone AND 3: the digit tile - 1, the
        world that enter_pipe_check stores. The blank tile $24 gives world
        $23 (07 leftover 15); group 3 reads the bytes after the table.
        warp_pipe_areas: 12 bytes: the area byte of that world's first
        area, read as the original reads it, past both tables for world
        $23 (07 section 5, enter_pipe_check).
  $84B7 score_number_digits: 12 bytes, a digit place (high nybble) and an
        amount (low nybble) per score code.
        score_award_places, score_award_amounts: 12 bytes each, the two
        nybbles apart.
  $8EF4 status_field_places: per field the name table address low byte
        and the digit count; the high byte is a constant of the code
        (FIELD_HIGH, TOP_FIELD_HIGH). $8F00 status_digit_ends: the end of
        each field's digits in the digit store.
        number_fields: 6 entries of 4 bytes: the cell row, the cell column
        (name table 0: ring columns 0-31), the digit count, the offset of
        the first digit in the digit store (07 section 13).
  $912D timer_start_hundreds (03, the timer part is 07 section 14): 4
        bytes.
        timer_hundreds_by_setting: the same bytes (entry 0 has no reader).
"""

PROGRAM_BASE = 0x8000  # the program ROM is $8000-$FFFF

# Document 07 section 4: the metatile classes and the test points.
SOLID_BOUNDS = 0xDF8B  # solid_bound_by_palette: 4 bytes, one per palette class
CLIMB_BOUNDS = 0xDF96  # climbable_bound_by_palette: 4 bytes
TILE_POINT_X = 0xE3B0  # tile_point_x_adders: 28 bytes
TILE_POINT_Y = 0xE3CC  # tile_point_y_adders: 28 bytes
TILE_POINTS = 28
POINT_SETS = 0xE3AD  # tile_adder_set_starts: 3 bytes
POINT_SET_COUNT = 3
# Document 07 section 2: the box shapes.
HIT_BOX_SHAPES = 0xE1FD  # hit_box_shapes: 12 rows of 4 bytes
HIT_BOX_BYTES = 48
# Document 07 section 5: the player against the tiles.
PLAYER_HEAD_LIMITS = 0xDC62  # player_head_limits: 2 bytes
AREA_CHANGE_WAITS = 0xDE03  # area_change_waits: 2 bytes
CLIMB_X_ADDERS = 0xDE25  # climb_x_adders: 2 bytes
CLIMB_PAGE_ADDERS = 0xDE27  # climb_page_adders: 2 bytes
FLAGPOLE_HEIGHTS = 0xDE29  # flagpole_score_heights: 5 bytes
WARP_ZONE_WORLDS = 0x87F2  # warp_zone_worlds (02 section 16.2): groups of 4 bytes
WARP_GROUP_BYTES = 4
WARP_GROUPS = 4  # warp_zone AND 3: groups 0-3 (3 reads past the 3 groups of the table)
PIPES_PER_GROUP = 3  # the left, middle and right pipe (byte 3 of a group has no reader)
WORLD_AREA_STARTS = 0x9CB4  # world_area_starts (06): the first area of each world
AREA_SLOTS = 0x9CBC  # area_slots (06): the area byte of each area
# Document 07 section 6: the block hits.
BUMPABLE = 0xBDE8  # bumpable_metatiles: 14 bytes
BUMPABLE_COUNT = 14
SECOND_BRICK_SET = 9  # hit_block: entries 9-13 give the gifts of entries 4-8
BRICK_SET_GAP = 5
BLOCK_Y_BY_SIZE = 0xBCEB  # block_y_by_size: 2 bytes
# Document 07 sections 7-11: the enemies, the fireballs, the lifts.
ENEMY_LANDING_STATES = 0xDFB9  # enemy_landing_states: 6 bytes, read for states 0-$7F (leftover 14)
LANDING_STATE_READS = 0x80
ENEMY_LAND_X_SPEEDS = 0xDFBF  # enemy_land_x_speeds: 2 bytes
KICKED_SHELL_SPEEDS = 0xD84F  # kicked_shell_speeds: 2 bytes
DEMOTED_KOOPA_SPEEDS = 0xD851  # demoted_koopa_speeds: 2 bytes
SHELL_CHAIN_SCORES = 0xD892  # shell_chain_scores: 3 bytes
STOMP_SCORE_CODES = 0xD965  # stomp_score_codes: 4 bytes
SHELL_REVIVE_TIMES = 0xD9D2  # shell_revive_times: 2 bytes
BOWSER_DISGUISES = 0xD736  # bowser_disguises: 8 bytes, one per world
ENEMY_BIT_MASKS = 0xDA25  # enemy_bit_set_masks: 7 bytes, enemy numbers 0-5 read
ENEMY_NUMBERS = 6
SMALL_LIFT_ADDERS = 0xDC17  # small_lift_stand_adders: 2 bytes
# Document 07 sections 12-14: the score numbers, the status numbers, the timer.
SCORE_NUMBER_TILES = 0x849F  # score_number_tiles: 2 tiles for each of 12 codes
SCORE_CODES = 12
SCORE_NUMBER_DIGITS = 0x84B7  # score_number_digits: 12 bytes, place and amount nybbles
STATUS_FIELD_PLACES = 0x8EF4  # status_field_places: per field the address low byte and the count
STATUS_DIGIT_ENDS = 0x8F00  # status_digit_ends: 6 bytes
FIELD_HIGH = 0x8F21  # print_number_field ($8F11): the operand of its load of the address high byte
TOP_FIELD_HIGH = 0x8F27  # the same, for field 0 (the top score on the title)
STATUS_FIELD_COUNT = 6  # the entries of status_digit_ends
COIN_DIGIT_PLACES = 0xBBF8  # coin_digit_places: 2 bytes
SCORE_DIGIT_PLACES = 0xBBFA  # score_digit_places: 2 bytes
STATUS_NYBBLES = 0xBBFC  # status_nybbles_by_player: 2 bytes
PLAYERS = 2
TIMER_START_HUNDREDS = 0x912D  # timer_start_hundreds: 4 bytes, one per time setting
TIME_SETTINGS = 4

# The picture chip's name table 0 (02 section 1): 32 cells a row.
NAME_TABLE_0 = 0x2000
ROW_CELLS = 32
CLASS_SHIFT = 6  # a metatile's palette class is its bits 7-6
SOLID_FLAG = 0x80  # metatile_class bit 7 (N of BIT)
CLIMB_FLAG = 0x40  # metatile_class bit 6 (V of BIT)


def build(program, host):
    """Write the tables of src/game/collision.s and src/game/score.s.
    PROGRAM: the 32 KB program ROM ($8000 = offset 0)."""
    assert len(program) == 0x8000

    def at(address):
        return program[address - PROGRAM_BASE]

    def run(address, count):
        return bytes(program[address - PROGRAM_BASE : address - PROGRAM_BASE + count])

    # The metatile classes: one flag byte per metatile.
    solid = run(SOLID_BOUNDS, 4)
    climb = run(CLIMB_BOUNDS, 4)
    classes = bytearray()
    for metatile in range(256):
        group = metatile >> CLASS_SHIFT
        classes.append(
            (SOLID_FLAG if metatile >= solid[group] else 0) | (CLIMB_FLAG if metatile >= climb[group] else 0)
        )
    host.game_blob_at(bytes(classes), "metatile_class")

    # The bumpable metatiles and the gift of each.
    host.game_blob_at(run(BUMPABLE, BUMPABLE_COUNT), "bump_metatiles", "BUMP_METATILES_SIZE")
    gifts = bytes(i - BRICK_SET_GAP if i >= SECOND_BRICK_SET else i for i in range(BUMPABLE_COUNT))
    host.game_blob_at(gifts, "bump_gifts")

    # The test points and the boxes.
    host.game_blob_at(run(TILE_POINT_X, TILE_POINTS), "tile_point_x")
    host.game_blob_at(run(TILE_POINT_Y, TILE_POINTS), "tile_point_y")
    host.game_blob_at(run(POINT_SETS, POINT_SET_COUNT), "tile_point_sets")
    host.game_blob_at(run(PLAYER_HEAD_LIMITS, 2), "player_head_limits")
    host.game_blob_at(run(HIT_BOX_SHAPES, HIT_BOX_BYTES), "hit_box_shapes")

    # The player's tile test.
    host.game_blob_at(run(AREA_CHANGE_WAITS, 2), "area_change_waits")
    host.game_blob_at(run(CLIMB_X_ADDERS, 2), "climb_x_adders")
    host.game_blob_at(run(CLIMB_PAGE_ADDERS, 2), "climb_page_adders")
    host.game_blob_at(run(FLAGPOLE_HEIGHTS, 5), "flagpole_score_heights")
    worlds = bytearray()
    areas = bytearray()
    for group in range(WARP_GROUPS):
        for pipe in range(PIPES_PER_GROUP):
            world = (at(WARP_ZONE_WORLDS + WARP_GROUP_BYTES * group + pipe) - 1) & 0xFF
            first = at(WORLD_AREA_STARTS + world)  # 8-bit index, as the original's
            worlds.append(world)
            areas.append(at(AREA_SLOTS + first))
    host.game_blob_at(bytes(worlds), "warp_pipe_worlds")
    host.game_blob_at(bytes(areas), "warp_pipe_areas")

    # The block hits, the enemies, the lifts.
    host.game_blob_at(run(BLOCK_Y_BY_SIZE, 2), "block_y_by_size")
    host.game_blob_at(run(ENEMY_LANDING_STATES, LANDING_STATE_READS), "enemy_landing_states")
    host.game_blob_at(run(ENEMY_LAND_X_SPEEDS, 2), "enemy_land_x_speeds")
    host.game_blob_at(run(KICKED_SHELL_SPEEDS, 2), "kicked_shell_speeds")
    host.game_blob_at(run(DEMOTED_KOOPA_SPEEDS, 2), "demoted_koopa_speeds")
    host.game_blob_at(run(SHELL_CHAIN_SCORES, 3), "shell_chain_scores")
    host.game_blob_at(run(STOMP_SCORE_CODES, 4), "stomp_score_codes")
    host.game_blob_at(run(SHELL_REVIVE_TIMES, 2), "shell_revive_times")
    host.game_blob_at(run(BOWSER_DISGUISES, 8), "bowser_disguises")
    host.game_blob_at(run(ENEMY_BIT_MASKS, ENEMY_NUMBERS), "enemy_bit_masks")
    host.game_blob_at(run(SMALL_LIFT_ADDERS, 2), "small_lift_stand_adders")

    # The score numbers.
    host.game_blob_at(run(SCORE_NUMBER_TILES, 2 * SCORE_CODES), "score_number_tiles")
    digits = run(SCORE_NUMBER_DIGITS, SCORE_CODES)
    host.game_blob_at(bytes(d >> 4 for d in digits), "score_award_places")
    host.game_blob_at(bytes(d & 0x0F for d in digits), "score_award_amounts")

    # The status bar numbers: the cell row and column of each field.
    fields = bytearray()
    for field in range(STATUS_FIELD_COUNT):
        high = at(TOP_FIELD_HIGH if field == 0 else FIELD_HIGH)
        low, count = at(STATUS_FIELD_PLACES + 2 * field), at(STATUS_FIELD_PLACES + 2 * field + 1)
        cell = (high << 8 | low) - NAME_TABLE_0
        fields += bytes((cell // ROW_CELLS, cell % ROW_CELLS, count, at(STATUS_DIGIT_ENDS + field) - count))
    host.game_blob_at(bytes(fields), "number_fields")
    host.game_blob_at(run(COIN_DIGIT_PLACES, PLAYERS), "coin_digit_places")
    host.game_blob_at(run(SCORE_DIGIT_PLACES, PLAYERS), "score_digit_places")
    host.game_blob_at(run(STATUS_NYBBLES, PLAYERS), "status_nybbles_by_player")
    host.game_blob_at(run(TIMER_START_HUNDREDS, TIME_SETTINGS), "timer_hundreds_by_setting")
