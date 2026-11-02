"""Prepare enemy behavior tables from the game program ROM.

scripts/assets.py passes build() the program and a host-data writer. ROM
addresses below use $8000 as byte zero. The writer places the results in
bank 0 for src/game/enemies.s.

These tables provide enemy movement, timing and drawing values. The builder
also converts the fire bar positions, bridge cells and castle flag tables
into forms the IIgs code can use directly.
"""

PROGRAM_BASE = 0x8000  # the program is $8000-$FFFF

# ---- The tables: label, address, size ------------
TABLES = [
    # hammer_throw_gaps $C9CE, 2: frames between two hammers, by hard_mode_2.
    ("hammer_throw_gaps", 0xC9CE, 2),  # by hard_mode_2
    # revived_shell_speeds $C9D4, 4: signed X speeds of a revive, by the
    #   frame's parity + 2 in hard_mode.
    ("revived_shell_speeds", 0xC9D4, 4),  # frame parity + 2 x hard_mode
    # hammer_jump_timers $CA10, 2: frames of a hammer brother's jump before it
    #   can land.
    ("hammer_jump_timers", 0xCA10, 2),  # launch_hammer_bro_jump
    # squid_rate_masks $CB87, 2: masks on random+1+e for the blooper's aim, by
    #   hard_mode_2.
    ("squid_rate_masks", 0xCB87, 2),  # by hard_mode_2
    # swim_fish_x_speeds $CC46, 4 (2 read): the X fraction that a swimming
    #   cheep-cheep loses each frame, by kind - $0A.
    # swim_fish_x_speeds: the 2 bytes that the original reads.
    ("swim_fish_x_speeds", 0xCC46, 2),  # by kind - $0A; bytes 2 and 3 are not read
    # fire_bar_y_adders $CD3A, 2: the Y offsets of the player's second and
    #   third test points.
    ("fire_bar_y_adders", 0xCD3A, 2),  # compare_fire_piece: test points 2 and 3
    # cloud_distance_adjusts $CF25, 3: Lakitu's speed bases.
    ("cloud_distance_adjusts", 0xCF25, 3),  # move_cloud_rider
    # bowser_range_choices $D061, 4: Bowser's walk ranges in pixels, and his
    #   jump timer's frames.
    ("bowser_range_choices", 0xD061, 4),  # by random+e AND 3
    # bowser_flame_gaps $D1D1, 8: frames between Bowser's flames, one cycle.
    ("bowser_flame_gaps", 0xD1D1, 8),  # next_flame_gap: by bowser_flame_timer
]

# slowdown_adders $C9D0, 4: signed X speed adders of the sideways move, by
#   0 (full speed) or 1 (a kicked shell in the air), + 2 for a speed to the
#   left.
SLOWDOWN_ADDERS = 0xC9D0  # 4 signed adders, index 0 or 1, + 2 for a speed to the left
SLOWDOWN_FULL = (0, 2)  # the entries of the full-speed move (index 0, and 0 + 2)
SLOWDOWN_AIR = (1, 3)  # the entries of a kicked shell in the air: right, left

# the fire bar tables, one after the other: each ends where the next
# one starts.
# fire_bar_offsets $CCC7, 99: rows of 9 offsets, one row for each ball p
#   after the center, entry s the offset at fold step s;
#   fire_bar_mirror_bits $CD2A, 4: bit 0 the X offset adds, bit 1 the Y
#   offset adds, by angle / 8; fire_bar_piece_starts $CD2E, 12: each row's
#   start in fire_bar_offsets (entry 11 is not read).
FIRE_BAR_OFFSETS = 0xCCC7  # rows of FOLD_STEPS offsets, one row for each ball after the center
FIRE_BAR_MIRROR_BITS = 0xCD2A  # by angle / 8, one entry for each quadrant
FIRE_BAR_PIECE_STARTS = 0xCD2E  # the row start of each ball in FIRE_BAR_OFFSETS
FOLD_STEPS = 9  # fire_bar_piece_offset step 1: s runs 0-8, so a row holds 9 offsets
FOLD_LIMIT = 9  # when s = angle AND $0F is 9 or more, s = HALF_TURN_STEPS - s
HALF_TURN_STEPS = 16  # the angle steps of a half turn ($0F + 1)
QUARTER_SHIFT = 3  # the quadrant is angle / 8 (fire_bar_piece_offset step 3)
QUARTER_STEPS = 1 << QUARTER_SHIFT  # step 2: the Y offset folds the angle + 8 (a quarter turn later)
MIRROR_X_ADDS = 0x01  # fire_bar_mirror_bits bit 0: the X offset adds (draw_fire_bar_pieces step 1)
MIRROR_Y_ADDS = 0x02  # bit 1: the Y offset adds (step 3)

# fish_arc_subtracts $CED5, 5, read with indexes 0-15: 16 bytes
#   from $CED5 (the table, flying_fish_priority and 6 bytes of swoop_fish).
FISH_ARC, FISH_ARC_READ = 0xCED5, 16  # swoop_fish: indexes 0-15

# bridge_piece_addrs $CFDD, 15: the low byte of the name table address of
#   each bridge piece; its high byte is the operand at BRIDGE_HIGH_AT.
BRIDGE_PIECE_ADDRS = 0xCFDD  # bridge_collapse_task: by bridge_collapse
BRIDGE_PIECE_ADDRS_LAST = 0xCFEB  # its last entry (the table ends here); bridge_collapse_task's code follows
BRIDGE_HIGH_AT = 0xD028  # the operand of the load of the address's high byte ($CFEC + $3B)
NAME_TABLE_BASE = 0x2000  # the picture chip's name table 0
NAME_TABLE_SIZE = 0x400  # each name table: 32 x 30 cells and the attribute bytes
NAME_TABLE_COLUMNS = 32  # cells in a name table row; ring column = 32 n + column

# castle_flag_y_adders $D2CD, castle_flag_x_adders $D2D1,
#   castle_flag_tiles $D2D5, 4 each: by sprite k of the castle flag, which
#   draw_castle_flag draws k = 3 down to 0 into its sprites 0 to 3.
CASTLE_FLAG_Y_ADDERS = 0xD2CD  # draw_castle_flag, by sprite k (drawn k = 3 down to 0
CASTLE_FLAG_X_ADDERS = 0xD2D1  # into the flag's sprites 0-3); the three tables follow each
CASTLE_FLAG_TILES = 0xD2D5  # other, so each is as long as the gap to the next

# ---- The values that the original loads as operands: label, address -------
# The operands of the tiles and attributes that the original loads as
#   values: Bowser's flame (its first tile, its two attributes), the castle
#   flag's attributes, the balance lift rope's two tiles and the blank tile.
VALUES = [
    # fly_bowser_flame: the first of its three tiles (the next two are
    # this + 1 and + 2, the code's increment), the attributes, and the
    # attributes on frames with bit 1 of frame_count set (flipped in Y)
    ("bowser_flame_tile", 0xD228),
    ("bowser_flame_attr", 0xD22C),
    ("bowser_flame_flipped_attr", 0xD234),
    # draw_castle_flag: behind the background, its palette
    ("castle_flag_attr", 0xD37E),
    # move_partner_lift: the rope cells of a sinking lift, the blank
    # cells of a rising one
    ("rope_left_tile", 0xD4EB),
    ("rope_right_tile", 0xD4F0),
    ("rope_blank_tile", 0xD4F8),
]

# Operands that repeat a value of VALUES: the code reads the one value.
SAME_AS = {
    0xD51C: 0xD4EB,  # the partner's rope cells
    0xD521: 0xD4F0,
    0xD529: 0xD4F8,  # the partner's blank cells
}


def build(program, host):
    """Put the enemies' data into bank 0. PROGRAM: the 32 KB program ROM."""
    assert len(program) == 0x8000
    at = lambda address: program[address - PROGRAM_BASE]
    run = lambda address, size: bytes(program[address - PROGRAM_BASE : address - PROGRAM_BASE + size])

    # hammer_throw_gaps, revived_shell_speeds, hammer_jump_timers,
    #   squid_rate_masks, fire_bar_y_adders, cloud_distance_adjusts,
    #   bowser_range_choices, bowser_flame_gaps: as the original has them.
    for name, address, size in TABLES:
        host.game_blob_at(run(address, size), name)
    # bowser_flame_tile, bowser_flame_attr, bowser_flame_flipped_attr,
    #   castle_flag_attr, rope_left_tile, rope_right_tile, rope_blank_tile: one
    #   byte each.
    for name, address in VALUES:
        host.game_blob_at(bytes([at(address)]), name)
    for copy, source in SAME_AS.items():
        assert at(copy) == at(source), f"${copy:04X} differs from ${source:04X}"

    # The sideways move: only a kicked shell in the air has an adder.
    # shell_air_slowdowns: slowdown_adders entries 1 and 3 (the adders of a
    #   kicked shell in the air for a speed to the right, then to the left);
    #   the check below proves that entries 0 and 2 are 0, so the port moves at
    #   the full speed without an add.
    adders = run(SLOWDOWN_ADDERS, 4)
    assert all(adders[i] == 0 for i in SLOWDOWN_FULL), "slowdown_adders: a full-speed entry is not 0"
    host.game_blob_at(bytes(adders[i] for i in SLOWDOWN_AIR), "shell_air_slowdowns")

    # fire_bar_pieces: for each angle 0-31, for each ball p after the center
    #   (0-10), its X offset and its Y offset from the center, signed bytes: the
    #   offsets of fire_bar_offsets with the fold of the angle and the signs of
    #   fire_bar_mirror_bits applied (fire_bar_piece_offset and
    #   draw_fire_bar_pieces). FIRE_BAR_PIECES_SIZE is its size.
    host.game_blob_at(fire_bar_pieces(program, at), "fire_bar_pieces", "FIRE_BAR_PIECES_SIZE")
    # fish_arc_heights: the 16 bytes from $CED5.
    host.game_blob_at(run(FISH_ARC, FISH_ARC_READ), "fish_arc_heights")

    # bridge_rows, bridge_columns: for each bridge piece, the ring row and the
    #   ring column of the top left cell of its 2 x 2 square (the card's ring:
    #   name table n, row r, column c is ring row r, ring column 32 n + c); enemies.s gives the screen part's
    #   store_block_tiles their metatile place. BRIDGE_ROWS_SIZE is the count of
    #   pieces.
    rows, columns = bridge_squares(at)
    host.game_blob_at(rows, "bridge_rows", "BRIDGE_ROWS_SIZE")
    host.game_blob_at(columns, "bridge_columns")

    # The castle flag: in the order of its sprites (sprite j gets k = 3 - j).
    # castle_flag_dy, castle_flag_dx, castle_flag_tiles: the three tables in
    #   the order of the flag's sprites 0-3 (k = 3 - sprite).
    #   CASTLE_FLAG_TILES_SIZE is the count of sprites.
    sprites = CASTLE_FLAG_X_ADDERS - CASTLE_FLAG_Y_ADDERS
    assert CASTLE_FLAG_TILES - CASTLE_FLAG_X_ADDERS == sprites
    order = range(sprites - 1, -1, -1)
    host.game_blob_at(bytes(at(CASTLE_FLAG_Y_ADDERS + k) for k in order), "castle_flag_dy")
    host.game_blob_at(bytes(at(CASTLE_FLAG_X_ADDERS + k) for k in order), "castle_flag_dx")
    host.game_blob_at(bytes(at(CASTLE_FLAG_TILES + k) for k in order), "castle_flag_tiles", "CASTLE_FLAG_TILES_SIZE")


def fire_bar_pieces(program, at):
    """The X and Y offset of each ball of a fire bar at each angle, as the
    original's fire_bar_piece_offset and draw_fire_bar_pieces make them:
    fold the angle into a step 0-8 for X and a quarter turn later for Y,
    read the ball's row of fire_bar_offsets at those steps, and give each
    offset the sign of the angle's quadrant."""
    offsets = program[FIRE_BAR_OFFSETS - PROGRAM_BASE : FIRE_BAR_MIRROR_BITS - PROGRAM_BASE]
    assert len(offsets) % FOLD_STEPS == 0
    balls = len(offsets) // FOLD_STEPS
    quadrants = FIRE_BAR_PIECE_STARTS - FIRE_BAR_MIRROR_BITS
    fold = lambda s: HALF_TURN_STEPS - s if s >= FOLD_LIMIT else s
    signed = lambda value, adds: value if adds else -value
    out = bytearray()
    for angle in range(quadrants << QUARTER_SHIFT):
        mirror = at(FIRE_BAR_MIRROR_BITS + (angle >> QUARTER_SHIFT))
        x_step = fold(angle % HALF_TURN_STEPS)
        y_step = fold((angle + QUARTER_STEPS) % HALF_TURN_STEPS)
        for ball in range(balls):
            row = at(FIRE_BAR_PIECE_STARTS + ball)
            dx = signed(offsets[row + x_step], mirror & MIRROR_X_ADDS)
            dy = signed(offsets[row + y_step], mirror & MIRROR_Y_ADDS)
            out += bytes([dx & 0xFF, dy & 0xFF])
    return bytes(out)


def bridge_squares(at):
    """The ring row and column of each bridge piece's top left cell, from
    the original's name table address (the high byte of the code's operand,
    the low byte from bridge_piece_addrs)."""
    high = at(BRIDGE_HIGH_AT)
    rows, columns = bytearray(), bytearray()
    for piece in range(BRIDGE_PIECE_ADDRS_LAST - BRIDGE_PIECE_ADDRS + 1):
        address = high << 8 | at(BRIDGE_PIECE_ADDRS + piece)
        table, cell = divmod(address - NAME_TABLE_BASE, NAME_TABLE_SIZE)
        row, column = divmod(cell, NAME_TABLE_COLUMNS)
        assert row % 2 == 0 and column % 2 == 0, f"bridge piece {piece}: a square starts at an even row and column"
        rows.append(row)
        columns.append(NAME_TABLE_COLUMNS * table + column)
    return bytes(rows), bytes(columns)
