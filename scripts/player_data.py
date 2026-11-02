"""Prepare the player movement and area-entry tables for the IIgs game.

scripts/assets.py passes build() the 32 KB program ROM and a host-data
writer. The addresses below refer to the original program, whose $8000 is
byte zero of that ROM. The writer places the results in bank 0 for
src/game/player.s. Some source tables contain separate high and low bytes;
build() joins them into little-endian words used by the 65816 code.
"""

PROGRAM_BASE = 0x8000  # the program is $8000-$FFFF

# ---- The tables : address, size ------------
# Gravity while the jump button is held. Each byte adds 1/256 pixel per
# frame to vertical speed. Kinds 0-4 are jumps at different run speeds;
# 5 is a swim stroke and 6 is a stroke in a whirlpool.
GRAVITY_HELD_BY_KIND = 0xB424  # 7: set_player_forces
# Gravity after the held phase, in the same units and jump-kind order.
GRAVITY_FALL_BY_KIND = 0xB42B  # 7: set_player_forces
# Initial vertical speed, split into signed whole pixels and fractions of
# 1/256 pixel. Negative speed moves up. build() combines each pair into
# one signed 8.8 word for each of the seven jump kinds.
JUMP_SPEED_BY_KIND = 0xB432  # 7: set_player_forces, the whole pixels
JUMP_FRACTION_BY_KIND = 0xB439  # 7: set_player_forces, the fraction
JUMP_KINDS = 7  # kinds 0-4 the jumps, 5 the stroke, 6 the stroke in a whirlpool
# Signed horizontal speed limits in 1/16 pixel per frame. The first three
# classes are running, walking and water; the right table also has a limit
# for the entrance walk.
LEFT_SPEED_LIMITS = 0xB440  # 3: pick_speed_limits
RIGHT_SPEED_LIMITS = 0xB443  # 4: pick_speed_limits (entry 3: the entry walk)
SPEED_CLASSES = 3  # run, walk, water
# Fractional friction for the three speed classes, in 1/4096 pixel per
# frame. The ROM stores the low byte; build() supplies a zero high byte.
FRICTION_BY_CLASS = 0xB447  # 3: pick_speed_limits
FRICTION_CLASSES = 3
# Climb speed as signed whole pixels and 1/256-pixel fractions. The three
# entries are standing still, climbing up and climbing down; build() joins
# each pair of bytes into one signed 8.8 word.
CLIMB_Y_SPEEDS = 0xB44A  # 3: set_player_forces, the whole pixels
CLIMB_Y_FORCES = 0xB44D  # 3: set_player_forces, the fraction
CLIMB_MOVES = 3  # still, up, down
# Frames per walking animation picture for the three speed classes.
ANIM_RATE_BY_SPEED = 0xB58C  # 3: store_anim_rate
ANIM_CLASSES = 3
# Signed pixel shifts for changing sides of a vine. The entries are: right
# held while facing right, right held while facing left, left held while
# facing right, and left held while facing left. Low and high bytes become
# four signed words.
VINE_SIDE_SHIFT_LOW = 0xB3C7  # 4: move_climbing
VINE_SIDE_SHIFT_HIGH = 0xB3CB  # 4: move_climbing
VINE_SHIFTS = 4
# Pixels inside the left and right screen edges, followed by the direction
# button that returns the player from each edge. build() expands each byte
# to a word because player.s indexes the edge tables with a word index.
EDGE_X_INSET = 0xB034  # 2: hold_player_in_screen
EDGE_RETURN_PAD = 0xB036  # 2: hold_player_in_screen
EDGES = 2  # left, right
# Coin counts required to show the hidden 1-up block, one per world.
HIDDEN_LIFE_COIN_GOALS = 0xB2C2  # 8: end_level_walk
WORLDS = 8

# ---- The entry tables  --
# Initial X within the page for entrance_alt values 0-3.
START_X_BY_ENTRY = 0x9116  # 4: by entrance_alt 0-3
ENTRANCE_ALTS = 4
# Start-row indexes for entrance_alt values 2 and 3.
ALT_ENTRY_Y_INDEX = 0x911A  # 2: the rows of entrance_alt 2 and 3
ALT_ROWS = 2
# Initial Y for each of nine start rows.
START_Y_BY_ENTRY = 0x911C  # 9: rows 0-7 (entrance 0-7) and row 8
START_ROWS = 9
# Sprite attributes for start rows 0-7. The original also reads row 8,
# one byte past this table, from the first game-timer value at $912D.
START_PRIORITY_BY_ENTRY = 0x9125  # 8: rows 0-7
PRIORITY_ROWS = 8
# Row 8 of start_priority_by_entry: the original reads it one byte past its
# 8 rows, from the first byte of timer_start_hundreds. The checked ROM
# has $20 at $912D; the following bytes are $04, $03 and $02.
START_PRIORITY_ROW_8 = 0x912D


def build(program, host):
    """The player's tables into GAMEDATA. PROGRAM: the 32 KB program ROM,
    $8000 = offset 0."""
    assert len(program) == 0x8000

    # Read SIZE bytes from the program ROM starting at ADDRESS.
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
