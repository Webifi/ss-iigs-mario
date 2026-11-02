"""The player's tables (document 04), read from the program and written in
the forms that src/game/player.s reads.

Every blob goes into bank 0 (GAMEDATA) with its own label: the player's
code runs each frame and reads its tables with absolute addresses (DBR =
bank 0). No value of a table is typed here: each one is read at the
address that document 04 gives ("Movement tables", "The player tasks").

ROM tables read (address, size, format; all bytes):
- gravity_held_by_kind $B424, 7: the gravity while A is held in a rise,
  1/256 pixel each frame, added to the Y speed each frame; by jump kind
  (0-4 the jumps by run speed, 5 the swim stroke, 6 the stroke in a
  whirlpool).
- gravity_fall_by_kind $B42B, 7: the fall gravity after it, the same unit.
- jump_speed_by_kind $B432, 7: the start Y speed's whole pixels, signed
  (up is negative); jump_fraction_by_kind $B439, 7: its fraction, 1/256
  pixel.
- left_speed_limits $B440, 3, and right_speed_limits $B443, 4: the X
  speed's limits, signed, 1/16 pixel each frame, by speed class (0 run, 1
  walk, 2 water; right entry 3 the entry walk).
- friction_by_class $B447, 3: the friction's low byte (its high byte is
  0), 1/4096 pixel each frame, by friction class.
- climb_y_speeds $B44A, 3: the climb's Y speed in whole pixels, signed;
  climb_y_forces $B44D, 3: its fraction; by 0 still, 1 up, 2 down.
- anim_rate_by_speed $B58C, 3: frames per walk picture, by picture class.
- vine_side_shift_low $B3C7, 4, and vine_side_shift_high $B3CB, 4: the low
  and high bytes of a signed X shift in pixels, by shift index (0 right
  held facing right, 1 right held facing left, 2 left held facing right,
  3 left held facing left).
- edge_x_inset $B034, 2: pixels inside the screen's left and right edge;
  edge_return_pad $B036, 2: the pad's direction bit back into the screen
  at each edge.
- hidden_life_coin_goals $B2C2, 8: coins (a binary count) by world.
- start_x_by_entry $9116, 4: X in the page, by entrance_alt.
- alt_entry_y_index $911A, 2: the start row of entrance_alt 2 and 3.
- start_y_by_entry $911C, 9: the start row's Y, by row 0-8.
- start_priority_by_entry $9125, 8: the start row's sprite attribute byte,
  by row 0-7. The original reads row 8 one byte past the table: the first
  byte of timer_start_hundreds, $912D (04 leftover 7, 03 L2), whose time
  entries scripts/collision_data.py reads for the game timer.

The forms written (labels, in this order):
- gravity_held_by_kind, gravity_fall_by_kind: 7 bytes each, as read.
- jump_start_speeds: 7 words, the start Y speed as one signed 8.8 word
  (the whole pixels high, the fraction low), by kind.
- left_speed_limits (3 bytes), right_speed_limits (4 bytes): as read.
- friction_by_class: 3 words, the friction (high byte 0), by class.
- climb_speeds: 3 words, the climb's Y speed as one signed 8.8 word.
- anim_rate_by_speed: 3 bytes, as read.
- vine_side_shifts: 4 words, the signed shift, by shift index.
- edge_x_inset, edge_return_pad: 2 words each (the byte, high byte 0), by
  edge: player.s indexes them with the word index of the screen's edges.
- hidden_life_coin_goals: 8 bytes, as read.
- start_x_by_entry (4 bytes), alt_entry_y_index (2 bytes),
  start_y_by_entry (9 bytes): as read.
- start_priority_by_entry: 9 bytes, rows 0-7 and the leftover row 8.
"""

PROGRAM_BASE = 0x8000  # the program is $8000-$FFFF

# ---- The tables (document 04 "Movement tables"): address, size ------------
GRAVITY_HELD_BY_KIND = 0xB424  # 7: set_player_forces
GRAVITY_FALL_BY_KIND = 0xB42B  # 7: set_player_forces
JUMP_SPEED_BY_KIND = 0xB432  # 7: set_player_forces, the whole pixels
JUMP_FRACTION_BY_KIND = 0xB439  # 7: set_player_forces, the fraction
JUMP_KINDS = 7  # kinds 0-4 the jumps, 5 the stroke, 6 the stroke in a whirlpool
LEFT_SPEED_LIMITS = 0xB440  # 3: pick_speed_limits
RIGHT_SPEED_LIMITS = 0xB443  # 4: pick_speed_limits (entry 3: the entry walk)
SPEED_CLASSES = 3  # run, walk, water
FRICTION_BY_CLASS = 0xB447  # 3: pick_speed_limits
FRICTION_CLASSES = 3
CLIMB_Y_SPEEDS = 0xB44A  # 3: set_player_forces, the whole pixels
CLIMB_Y_FORCES = 0xB44D  # 3: set_player_forces, the fraction
CLIMB_MOVES = 3  # still, up, down
ANIM_RATE_BY_SPEED = 0xB58C  # 3: store_anim_rate
ANIM_CLASSES = 3
VINE_SIDE_SHIFT_LOW = 0xB3C7  # 4: move_climbing
VINE_SIDE_SHIFT_HIGH = 0xB3CB  # 4: move_climbing
VINE_SHIFTS = 4
EDGE_X_INSET = 0xB034  # 2: hold_player_in_screen
EDGE_RETURN_PAD = 0xB036  # 2: hold_player_in_screen
EDGES = 2  # left, right
HIDDEN_LIFE_COIN_GOALS = 0xB2C2  # 8: end_level_walk
WORLDS = 8

# ---- The entry tables (document 04 setup_entry_and_timer, 03 section 4.9) --
START_X_BY_ENTRY = 0x9116  # 4: by entrance_alt 0-3
ENTRANCE_ALTS = 4
ALT_ENTRY_Y_INDEX = 0x911A  # 2: the rows of entrance_alt 2 and 3
ALT_ROWS = 2
START_Y_BY_ENTRY = 0x911C  # 9: rows 0-7 (entrance 0-7) and row 8
START_ROWS = 9
START_PRIORITY_BY_ENTRY = 0x9125  # 8: rows 0-7
PRIORITY_ROWS = 8
# Row 8 of start_priority_by_entry: the original reads it one byte past its
# 8 rows, from the first byte of timer_start_hundreds (04 leftover 7).
START_PRIORITY_ROW_8 = 0x912D


def build(program, host):
    """The player's tables into GAMEDATA. PROGRAM: the 32 KB program ROM,
    $8000 = offset 0."""
    assert len(program) == 0x8000

    def run(address, size):
        return bytes(program[address - PROGRAM_BASE + i] for i in range(size))

    def word_of(high, low):
        """A word from its two bytes: a signed 8.8 speed is its whole pixels
        (high) and its fraction (low); a signed shift its two bytes."""
        return high << 8 | low

    def words(values):
        """Words, low byte first."""
        return bytes(b for v in values for b in (v & 0xFF, v >> 8))

    host.game_blob_at(run(GRAVITY_HELD_BY_KIND, JUMP_KINDS), "gravity_held_by_kind")
    host.game_blob_at(run(GRAVITY_FALL_BY_KIND, JUMP_KINDS), "gravity_fall_by_kind")
    wholes = run(JUMP_SPEED_BY_KIND, JUMP_KINDS)
    fractions = run(JUMP_FRACTION_BY_KIND, JUMP_KINDS)
    host.game_blob_at(words(map(word_of, wholes, fractions)), "jump_start_speeds")
    host.game_blob_at(run(LEFT_SPEED_LIMITS, SPEED_CLASSES), "left_speed_limits")
    host.game_blob_at(run(RIGHT_SPEED_LIMITS, SPEED_CLASSES + 1), "right_speed_limits")
    host.game_blob_at(words(run(FRICTION_BY_CLASS, FRICTION_CLASSES)), "friction_by_class")
    wholes = run(CLIMB_Y_SPEEDS, CLIMB_MOVES)
    fractions = run(CLIMB_Y_FORCES, CLIMB_MOVES)
    host.game_blob_at(words(map(word_of, wholes, fractions)), "climb_speeds")
    host.game_blob_at(run(ANIM_RATE_BY_SPEED, ANIM_CLASSES), "anim_rate_by_speed")
    highs = run(VINE_SIDE_SHIFT_HIGH, VINE_SHIFTS)
    lows = run(VINE_SIDE_SHIFT_LOW, VINE_SHIFTS)
    host.game_blob_at(words(map(word_of, highs, lows)), "vine_side_shifts")
    host.game_blob_at(words(run(EDGE_X_INSET, EDGES)), "edge_x_inset")
    host.game_blob_at(words(run(EDGE_RETURN_PAD, EDGES)), "edge_return_pad")
    host.game_blob_at(run(HIDDEN_LIFE_COIN_GOALS, WORLDS), "hidden_life_coin_goals")
    host.game_blob_at(run(START_X_BY_ENTRY, ENTRANCE_ALTS), "start_x_by_entry")
    host.game_blob_at(run(ALT_ENTRY_Y_INDEX, ALT_ROWS), "alt_entry_y_index")
    host.game_blob_at(run(START_Y_BY_ENTRY, START_ROWS), "start_y_by_entry")
    priorities = run(START_PRIORITY_BY_ENTRY, PRIORITY_ROWS) + run(START_PRIORITY_ROW_8, 1)
    host.game_blob_at(priorities, "start_priority_by_entry")
