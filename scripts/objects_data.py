"""The tables of the objects, the shared moves, the enemy spawns and the
enemy starts (document 05a, the original's $B624-$C8D6), in the forms that
src/game/objects.s and src/game/movement.s read.

The ROM tables (address, size, format; document 05a section):
- $B687 fireball_x_speeds, 2 X speed bytes by player_facing - 1 (4.2); and
  $B689, the first byte of the code after them, which a throw with
  player_facing 3 reads (04 L10).
- $B74B bubble_rise_force, 2 bytes of 1/256 pixel by a random bit; $B74D
  bubble_gap_frames, 2 frame counts (5.4); $B7DC and $B7DE, the bytes that
  the bubble of a water area's start reads at index $91 (L4).
- $B84B flag_score_amounts, 5 digits; $B850 flag_score_places, 5 digit_add
  places, by flag_score (9.2).
- $B8B6 spring_top_offsets, 4 pixel bytes by spring_anim - 1 (10.5).
- $B949 vine_height_limits, 2 heights by vine_count - 1; $B94B, the byte
  that vine_count 3 reads past them (11.3, L11).
- $B9BA cannon_rate_masks, 2 masks by hard_mode_2 (12.4).
- $BA31 bullet_x_speeds, 2 X speed bytes by direction - 1 (12.4).
- $BA89 hammer_source_slots, 9 enemy numbers by misc slot (13.4); $BA92
  hammer_x_speeds, 2 X speed bytes by direction - 1.
- $BBF8 coin_digit_places, $BBFA score_digit_places, $BBFC
  status_nybbles_by_player, 2 bytes each by player (15.1).
- $BCEB block_y_by_size, 2 pixel bytes (17.13).
- $BDE8 bumpable_metatiles, 14 metatiles in the order of the effect
  numbers; entries 9-13 are the effects 4-8 again (17.6, 17.7).
- $BF9F block_fall_limits, 2 top speeds; only entry 1 is read (3.4, L17).
- $C06B loop_worlds, $C076 loop_pages, $C081 loop_heights, 11 bytes each by
  loop check (19.1).
- $C30C walk_speeds, 2 X speed bytes by hard_mode; $C326
  hammer_bro_walk_times, 2 slow timer counts by hard_mode_2 (21.3).
- $C44F fire_bar_turn_speeds, $C454 fire_bar_turn_dirs, 5 bytes each by
  kind - $1B (21.10).
- $C488 flying_fish_x_starts, 16 pixel bytes; $C498 flying_fish_x_speeds,
  12 X speed bytes; $C4A4 flying_fish_gaps, 4 frame counts (21.5).
- $C59D bowser_flame_heights, 4 Y bytes; $C5A1 bowser_flame_y_force, 2
  fraction bytes (21.6).
- $C631 firework_x_offsets, $C637 firework_y_offsets, 6 bytes each (21.7).
- $C68A single_bit_masks, 8; $C692 wave_row_ys, 8; $C69A wave_fish_kinds, 2
  (21.8).
- $C86B lift_offsets_low, $C86E lift_offsets_high, 3 bytes each (21.11).

The forms written (each blob labelled with the name the assembly reads; bank
0 unless named otherwise):
- The tables above as bytes, with the entries that the original reads past
  their end added on purpose: fireball_x_speeds (3: facing 1, 2, 3),
  bubble_gap_frames (3: random bit 0, 1, the area start), vine_height_limits
  (3: vine_count 1, 2, 3), and block_fall_limit (1 byte: entry 1).
- bubble_rise_force: 3 words (the bytes zero-extended), by entry x 2: the
  bubble's Y and fraction lose the force in one 16-bit subtract.
- flying_fish_x_offsets: 16 signed words by start entry i: the start byte,
  added when bit 1 of i is 1, else subtracted (the original's two paths,
  21.5 step 9), so the code adds the word to the player's X.
- lift_offsets: 3 words, low and high byte of each offset.
- block_effects (a data bank, read with long addressing): 256 bytes by
  metatile: 0 not bumpable, else the effect number + 1 (1-9; 17.6).
"""

PROGRAM_BASE = 0x8000  # the program ROM is $8000-$FFFF

# The ROM tables (document 05a section in each comment).
FIREBALL_X_SPEEDS = 0xB687  # 4.2: 2 entries
FIREBALL_FACING_BOTH = 0xB689  # 04 L10: the byte that player_facing 3 reads
BUBBLE_RISE_FORCE = 0xB74B  # 5.4: 2 entries
BUBBLE_GAP_FRAMES = 0xB74D  # 5.4: 2 entries
BUBBLE_ENTRANCE_RISE = 0xB7DC  # L4: bubble_rise_force + $91
BUBBLE_ENTRANCE_GAP = 0xB7DE  # L4: bubble_gap_frames + $91
FLAG_SCORE_AMOUNTS = 0xB84B  # 9.2
FLAG_SCORE_PLACES = 0xB850  # 9.2
FLAG_SCORES = 5
SPRING_TOP_OFFSETS = 0xB8B6  # 10.5
SPRING_STEPS = 4
VINE_HEIGHT_LIMITS = 0xB949  # 11.3: 2 entries, then the byte that vine_count 3 reads (L11)
VINE_LIMITS = 3
CANNON_RATE_MASKS = 0xB9BA  # 12.4
BULLET_X_SPEEDS = 0xBA31  # 12.4
HAMMER_SOURCE_SLOTS = 0xBA89  # 13.4
MISC_SLOTS = 9
HAMMER_X_SPEEDS = 0xBA92  # 13.4
BUMPABLE_METATILES = 0xBDE8  # 17.7
BUMPABLE = 14
EFFECTS = 9  # 17.6: entries 9-13 of bumpable_metatiles are the effects 4-8
REPEATED_EFFECTS = 5
BLOCK_FALL_LIMITS = 0xBF9F  # 3.4: entry 1 is the block objects' top speed (L17)
BLOCK_FALL_ENTRY = 1
LOOP_WORLDS = 0xC06B  # 19.1
LOOP_PAGES = 0xC076  # 19.1
LOOP_HEIGHTS = 0xC081  # 19.1
LOOP_CHECKS = 11
WALK_SPEEDS = 0xC30C  # 21.3
HAMMER_BRO_WALK_TIMES = 0xC326  # 21.3
FIRE_BAR_TURN_SPEEDS = 0xC44F  # 21.10
FIRE_BAR_TURN_DIRS = 0xC454  # 21.10
FIRE_BAR_KINDS = 5
FLYING_FISH_X_STARTS = 0xC488  # 21.5
FISH_STARTS = 16
FISH_ADD_BIT = 0x02  # 21.5 step 9: bit 1 of the entry: add, else subtract
FLYING_FISH_X_SPEEDS = 0xC498  # 21.5
FISH_SPEEDS = 12
FLYING_FISH_GAPS = 0xC4A4  # 21.5
FISH_GAPS = 4
BOWSER_FLAME_HEIGHTS = 0xC59D  # 21.6
FLAME_HEIGHTS = 4
BOWSER_FLAME_Y_FORCE = 0xC5A1  # 21.6
FIREWORK_X_OFFSETS = 0xC631  # 21.7
FIREWORK_Y_OFFSETS = 0xC637  # 21.7
FIREWORK_BURSTS = 6
SINGLE_BIT_MASKS = 0xC68A  # 21.8
WAVE_ROW_YS = 0xC692  # 21.8
WAVE_ROWS = 8
WAVE_FISH_KINDS = 0xC69A  # 21.8
LIFT_OFFSETS_LOW = 0xC86B  # 21.11
LIFT_OFFSETS_HIGH = 0xC86E  # 21.11
LIFT_OFFSETS = 3
PAIR = 2  # the tables of two entries (by a flag, a player or a direction)
METATILES = 256
WORD = 0x10000


def build(program, host):
    """The tables of src/game/objects.s and src/game/movement.s.
    PROGRAM: the 32 KB program ROM ($8000 = offset 0)."""
    assert len(program) == 0x8000

    def table(address, count):
        return bytes(program[address - PROGRAM_BASE : address - PROGRAM_BASE + count])

    def byte_at(address):
        return program[address - PROGRAM_BASE]

    def words(values):
        return b"".join((v % WORD).to_bytes(2, "little") for v in values)

    blobs = {
        "fireball_x_speeds": table(FIREBALL_X_SPEEDS, PAIR) + bytes((byte_at(FIREBALL_FACING_BOTH),)),
        "bubble_gap_frames": table(BUBBLE_GAP_FRAMES, PAIR) + bytes((byte_at(BUBBLE_ENTRANCE_GAP),)),
        "bubble_rise_force": words(list(table(BUBBLE_RISE_FORCE, PAIR)) + [byte_at(BUBBLE_ENTRANCE_RISE)]),
        "flag_score_amounts": table(FLAG_SCORE_AMOUNTS, FLAG_SCORES),
        "flag_score_places": table(FLAG_SCORE_PLACES, FLAG_SCORES),
        "spring_top_offsets": table(SPRING_TOP_OFFSETS, SPRING_STEPS),
        "vine_height_limits": table(VINE_HEIGHT_LIMITS, VINE_LIMITS),
        "cannon_rate_masks": table(CANNON_RATE_MASKS, PAIR),
        "bullet_x_speeds": table(BULLET_X_SPEEDS, PAIR),
        "hammer_source_slots": table(HAMMER_SOURCE_SLOTS, MISC_SLOTS),
        "hammer_x_speeds": table(HAMMER_X_SPEEDS, PAIR),
        "block_fall_limit": bytes((byte_at(BLOCK_FALL_LIMITS + BLOCK_FALL_ENTRY),)),
        "loop_worlds": table(LOOP_WORLDS, LOOP_CHECKS),
        "loop_pages": table(LOOP_PAGES, LOOP_CHECKS),
        "loop_heights": table(LOOP_HEIGHTS, LOOP_CHECKS),
        "walk_speeds": table(WALK_SPEEDS, PAIR),
        "hammer_bro_walk_times": table(HAMMER_BRO_WALK_TIMES, PAIR),
        "fire_bar_turn_speeds": table(FIRE_BAR_TURN_SPEEDS, FIRE_BAR_KINDS),
        "fire_bar_turn_dirs": table(FIRE_BAR_TURN_DIRS, FIRE_BAR_KINDS),
        "flying_fish_x_offsets": words(
            start if i & FISH_ADD_BIT else -start
            for i, start in enumerate(table(FLYING_FISH_X_STARTS, FISH_STARTS))
        ),
        "flying_fish_x_speeds": table(FLYING_FISH_X_SPEEDS, FISH_SPEEDS),
        "flying_fish_gaps": table(FLYING_FISH_GAPS, FISH_GAPS),
        "bowser_flame_heights": table(BOWSER_FLAME_HEIGHTS, FLAME_HEIGHTS),
        "bowser_flame_y_force": table(BOWSER_FLAME_Y_FORCE, PAIR),
        "firework_x_offsets": table(FIREWORK_X_OFFSETS, FIREWORK_BURSTS),
        "firework_y_offsets": table(FIREWORK_Y_OFFSETS, FIREWORK_BURSTS),
        "single_bit_masks": table(SINGLE_BIT_MASKS, WAVE_ROWS),
        "wave_row_ys": table(WAVE_ROW_YS, WAVE_ROWS),
        "wave_fish_kinds": table(WAVE_FISH_KINDS, PAIR),
        "lift_offsets": words(
            low | high << 8
            for low, high in zip(table(LIFT_OFFSETS_LOW, LIFT_OFFSETS), table(LIFT_OFFSETS_HIGH, LIFT_OFFSETS))
        ),
    }
    for label, data in blobs.items():
        host.game_blob_at(data, label)

    # block_effects: the effect of each metatile that a head bump changes.
    effects = bytearray(METATILES)
    for entry, metatile in enumerate(table(BUMPABLE_METATILES, BUMPABLE)):
        effect = entry if entry < EFFECTS else entry - REPEATED_EFFECTS
        assert not effects[metatile], f"metatile ${metatile:02X} twice in bumpable_metatiles"
        effects[metatile] = effect + 1
    host.blob_at(bytes(effects), "block_effects")
