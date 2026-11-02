"""The drawing data of the sprite part (document 11): the poses, tiles and
attributes of every object that the game draws into the sprite list, and
the tables of the offscreen bits, read from the program for
src/game/sprites.s.

Every blob goes into bank 0 (GAMEDATA) with its own label: the drawing
runs each frame and reads its data with absolute addresses (DBR = bank 0).
No tile, palette or pose of the game is typed here: each one is read at the
address of its table or of the operand of the instruction that loads it
(the *_AT constants), at the place that document 11 gives.

ROM tables read (document 11; address, size, format):
- vine_piece_y_adders $E433, 2: the Y offset of each vine part (s12).
- the seven hammer tables $E4C0-$E4DB, 4 bytes each, by spin step (s15):
  first sprite X and Y offsets, second sprite X and Y offsets from the
  first, first and second tile, attributes.
- pole_score_tiles $E541, 10: two tiles for each flagpole score (s13).
- spin_coin_tiles $E682, 4: the tile of each coin step (s15).
- powerup_tiles $E6BE, 16: four tiles per power-up kind, row 1 left,
  right, row 2 left, right; powerup_sprite_flags $E6CE, 4: the palette of
  each kind (s14).
- enemy_frame_tiles $E73E, 258: 43 poses of 6 tiles, three rows of left,
  right; enemy_frame_starts $E840, 27 and enemy_sprite_attrs $E85B, 27: the
  first pose and the attribute bits of each drawing code; enemy_anim_masks
  $E876 (its first byte, the only one read); spring_frame_starts $E878, 5:
  the drawing code of each spring step (s7).
- block_piece_tiles $EBCD, 4: the bumped block, row 1 left, right, row 2
  left, right (s16).
- burst_tiles $ED06, 3: the tile of each burst step (s17).
- player_frame_starts $EE07, 16: the pose of each action; player_frame_tiles
  $EE17, 208: 26 poses of 8 tiles, four rows of left, right; swim_kick_tiles
  $EEE7, 2 (s9).
- lives_screen_player $EF9E, 6: the Y, the mirror control, the attributes,
  the X, an unused byte and the rows of the lives screen's player (s10).
- size_change_offsets $F09C, 20: the steps of the size change (s9).
- x_offscreen_masks $F1E3, 16, x_onscreen_margins $F1F3, 3,
  y_offscreen_masks $F22B, 9, y_onscreen_margins $F234, 3, high_pos_units
  $F237, 2, and the limits and bases that find_x_offscreen and
  find_y_offscreen load as operands (s5).

The forms written (src/game/sprites.s reads them):
- The tables above as the original has them (the tile tables are rows of
  left tile, right tile, which the drawing reads as one 16-bit word), with
  the port's names: vine_part_y, hammer_spin_x, hammer_spin_y,
  hammer_spin_next_x, hammer_spin_next_y, hammer_spin_tile,
  hammer_spin_next_tile, hammer_spin_attr, flag_score_tiles,
  coin_spin_tiles, powerup_pose_tiles, powerup_palettes, enemy_pose_tiles,
  enemy_first_pose, enemy_code_attributes, enemy_step_mask,
  spring_draw_codes, bumped_block_tiles, burst_step_tiles,
  player_action_poses, player_pose_tiles, swim_kick_foot_tiles,
  size_change_poses.
- The lives screen's values one byte each: lives_screen_y,
  lives_screen_mirror, lives_screen_attr, lives_screen_x,
  lives_screen_rows.
- One byte for each tile, attribute or pose that the original loads as an
  operand (the VALUES list below), and burst_attributes: the four
  attributes of the burst's sprites s1-s4, from four operands.
- The offscreen tables, by screen edge (right, left, top, bottom: the order
  in which the original tests them): EDGE_bits, one byte for each 8-pixel
  step of a distance of 0-255 pixels from the edge to the object (step =
  distance / 8; the code takes a distance of a page or more as 255, which
  the original's rule gives the same bits), and EDGE_beyond, the bits for
  a negative distance. offscreen_top_edge and offscreen_bottom_edge: the
  first and the last line of the screen as Y words (Y high x 256 + row).
"""

PROGRAM_BASE = 0x8000  # the program is $8000-$FFFF

# ---- The tables (document 11): label, address, size ------------------------
TABLES = [
    ("vine_part_y", 0xE433, 2),  # s12 vine_piece_y_adders
    ("hammer_spin_x", 0xE4C0, 4),  # s15 hammer_first_x
    ("hammer_spin_y", 0xE4C4, 4),  # hammer_first_y
    ("hammer_spin_next_x", 0xE4C8, 4),  # hammer_second_x: from the first sprite's X
    ("hammer_spin_next_y", 0xE4CC, 4),  # hammer_second_y: from the first sprite's Y
    ("hammer_spin_tile", 0xE4D0, 4),  # hammer_first_tile
    ("hammer_spin_next_tile", 0xE4D4, 4),  # hammer_second_tile
    ("hammer_spin_attr", 0xE4D8, 4),  # hammer_attributes
    ("flag_score_tiles", 0xE541, 10),  # s13 pole_score_tiles
    ("coin_spin_tiles", 0xE682, 4),  # s15 spin_coin_tiles
    ("powerup_pose_tiles", 0xE6BE, 16),  # s14 powerup_tiles
    ("powerup_palettes", 0xE6CE, 4),  # s14 powerup_sprite_flags
    ("enemy_pose_tiles", 0xE73E, 258),  # s7 enemy_frame_tiles
    ("enemy_first_pose", 0xE840, 27),  # s7 enemy_frame_starts
    ("enemy_code_attributes", 0xE85B, 27),  # s7 enemy_sprite_attrs
    ("enemy_step_mask", 0xE876, 1),  # s7 enemy_anim_masks: only its first byte is read
    ("spring_draw_codes", 0xE878, 5),  # s7 spring_frame_starts
    ("bumped_block_tiles", 0xEBCD, 4),  # s16 block_piece_tiles
    ("burst_step_tiles", 0xED06, 3),  # s17 burst_tiles
    ("player_action_poses", 0xEE07, 16),  # s9 player_frame_starts
    ("player_pose_tiles", 0xEE17, 208),  # s9 player_frame_tiles
    ("swim_kick_foot_tiles", 0xEEE7, 2),  # s9 swim_kick_tiles
    ("size_change_poses", 0xF09C, 20),  # s9 size_change_offsets
]

# ---- The lives screen's player (s10): lives_screen_player $EF9E -------------
LIVES_SCREEN_PLAYER = 0xEF9E
LIVES_SCREEN_FIELDS = [  # label, offset in the table ($EFA2 is not read)
    ("lives_screen_y", 0),  # the Y of row 1
    ("lives_screen_mirror", 1),  # the mirror control (bit 1 set: mirrored)
    ("lives_screen_attr", 2),  # the attributes
    ("lives_screen_x", 3),  # the X of the left column
    ("lives_screen_rows", 5),  # the rows
]

# ---- The values that the original loads as operands: label, address -------
VALUES = [
    # s12 draw_vine_stack
    ("vine_attr", 0xE462),  # the left sprites: behind the background, the palette
    ("vine_stem_tile", 0xE47A),
    ("vine_top_tile", 0xE48C),  # the top sprite of part 0
    # s13 draw_flag_sprites: one operand gives the attributes of the flag and
    # of its score number, and the score number's mirror control
    ("flag_attr", 0xE572),
    ("flag_tile", 0xE581),  # s1 and s3
    ("flag_skull_tile", 0xE589),  # s2
    # s11 draw_big_lift
    ("big_lift_tile", 0xE5F5),
    ("cloud_lift_tile", 0xE5FC),  # in the cloud areas
    ("big_lift_attr", 0xE604),
    # s15 draw_spinning_coin
    ("coin_score_attr", 0xE66E),
    ("coin_score_tile", 0xE676),  # the "2" of 200
    ("coin_score_zeros_tile", 0xE67B),  # the "00"
    ("coin_attr", 0xE6B2),  # the upper sprite
    ("coin_lower_attr", 0xE6B7),  # the lower sprite: the upper one upside down
    # s7 draw_enemy
    ("bullet_bill_palette", 0xE8C5),  # rule C: a cannon's bullet bill
    ("enemy_pose_bowser_front_2", 0xE93F),  # rule H
    ("enemy_pose_bowser_rear_2", 0xE954),
    ("enemy_pose_spiny", 0xE966),  # rule I
    ("enemy_pose_spiny_egg", 0xE96E),
    ("enemy_pose_lakitu", 0xE97B),  # rule J
    ("enemy_pose_lakitu_2", 0xE98C),
    ("enemy_pose_koopa_shell_a", 0xE99B),  # rule K
    ("enemy_pose_buzzy_shell_a", 0xE9A3),
    ("enemy_pose_buzzy_shell_b", 0xE9AD),
    ("enemy_pose_koopa_shell_b", 0xE9B7),
    ("enemy_pose_goomba", 0xE9BF),
    ("enemy_pose_flat_goomba", 0xE9C7),
    ("enemy_pose_hammer_bro_3", 0xE9DB),  # rule L
    ("enemy_pose_cheep", 0xE9DF),  # rule M
    ("enemy_pose_blooper", 0xE9EA),
    ("enemy_pose_retainer", 0xEA1B),  # rule N
    ("princess_last_attr", 0xEACF),  # rule T: s6 of code $15
    ("lakitu_cloud_mask", 0xEB21),  # rule U: the left sprite of the cloud row (AND)
    ("lakitu_cloud_bits", 0xEB29),  # the right sprite of the cloud row (OR)
    ("spring_lower_attr", 0xEB55),  # rule V: s3 and s5 (s4 and s6 add the mirror)
    # s16 draw_bumped_block
    ("bumped_block_attr", 0xEBDC),
    ("block_upper_tile", 0xEC03),  # row 1 outside a ground area
    ("used_block_metatile", 0xEC0E),  # the block metatile that shows the used block
    ("used_block_tile", 0xEC12),
    ("used_block_palette", 0xEC19),  # in a ground area; shifted right elsewhere
    # s16 draw_brick_pieces
    ("walk_brick_palette", 0xEC54),  # during the walk to the castle
    ("walk_brick_tile", 0xEC58),
    ("brick_palette", 0xEC60),
    ("brick_tile", 0xEC64),
    # s17 draw_fire_piece_sprite
    ("fireball_tile", 0xECF5),  # the first tile; FC bit 2 gives the next one (EOR)
    ("fireball_attr", 0xECFD),
    # s11 draw_small_lift_sprites
    ("small_lift_tile", 0xED6A),
    ("small_lift_attr", 0xED71),
    # s18 draw_air_bubble
    ("bubble_tile", 0xEDFD),
    ("bubble_attr", 0xEE02),
    # s9 the swim kick (leftover 6): the left tile of row 4 of small swim 3,
    # a byte of player_frame_tiles
    ("small_swim_3_foot_tile", 0xEEB5),
    # s10 draw_lives_screen_player
    ("player_pose_lives_screen", 0xEFAF),
    # s9 check_player_attribs: the poses whose row 4 is a tile and its mirror
    ("player_pose_big_crouch", 0xF0F6),
    ("player_pose_small_stand", 0xF0FA),
    ("player_pose_grow", 0xF0FE),
    ("player_pose_big_stand", 0xF102),
]

# s17 draw_firework_burst: the attributes of s1-s4 (one tile in four mirror
# images), four operands.
BURST_ATTRIBUTES_AT = [0xED4D, 0xED52, 0xED57, 0xED5C]

# Operands that repeat a value of VALUES: the drawing reads the one value.
SAME_AS = {
    0xEB38: 0xEB21,  # rule U, the cloud row's left sprite in pose 2
    0xEB42: 0xEB21,  # rule U upside down: s1
    0xEB4A: 0xEB29,  # rule U upside down: s2
}

# Mirror controls that the original takes from a byte of another use. The
# port draws these rows unmirrored; the check below proves that the
# original's byte has the mirror bit (bit 1, 11 section 6) clear.
MIRROR_BIT = 0x02
NOT_MIRRORED_AT = {
    0xEBDC: 1,  # draw_bumped_block: the attribute byte shifted right once ($EBDF)
    0xE572: 0,  # draw_flag_sprites: the attribute byte itself ($E573, $E575)
    0xE6F2: 0,  # draw_item_sprite: the row count's operand ($E6F3, $E6F5)
}

# ---- The offscreen bits (s5) -------------------------------------------------
X_MASKS, X_MASKS_SIZE = 0xF1E3, 16  # x_offscreen_masks
X_MARGINS = 0xF1F3  # x_onscreen_margins, 3 bytes
X_LIMIT_AT = 0xF216  # find_x_offscreen: the pixel distance from which no column is partly off
X_BASE_AT = 0xF21A  # the first mask entry of the second edge (the left)
Y_MASKS, Y_MASKS_SIZE = 0xF22B, 9  # y_offscreen_masks
Y_MARGINS = 0xF234  # y_onscreen_margins, 3 bytes
Y_EDGE_LOWS = 0xF237  # high_pos_units: the low byte of each Y edge, by edge number
Y_EDGE_HIGH_AT = 0xF246  # find_y_offscreen: the high byte of both Y edges
Y_LIMIT_AT = 0xF258
Y_BASE_AT = 0xF25C  # the first mask entry of the second edge (the bottom)
# Both routines test edge 1 first (the right, the top), then edge 0 (the
# left, the bottom): the edge number indexes the margins and the Y edges,
# and the base is added for edge 0 only (scale_position_diff, $F26D).
FIRST_EDGE, SECOND_EDGE = 1, 0
COLUMN_PIXELS = 8  # scale_position_diff takes the distance in steps of 8 pixels ($F275-$F277)
EDGE_REACH = 256  # the steps of a page of distances: a page or more counts as 255


def build(program, host):
    """Put the drawing data into bank 0. PROGRAM: the 32 KB program ROM."""
    assert len(program) == 0x8000
    at = lambda address: program[address - PROGRAM_BASE]
    run = lambda address, size: bytes(program[address - PROGRAM_BASE : address - PROGRAM_BASE + size])

    for name, address, size in TABLES:
        host.game_blob_at(run(address, size), name)
    for name, offset in LIVES_SCREEN_FIELDS:
        host.game_blob_at(bytes([at(LIVES_SCREEN_PLAYER + offset)]), name)
    for name, address in VALUES:
        host.game_blob_at(bytes([at(address)]), name)
    host.game_blob_at(bytes(at(a) for a in BURST_ATTRIBUTES_AT), "burst_attributes")

    for copy, source in SAME_AS.items():
        assert at(copy) == at(source), f"${copy:04X} differs from ${source:04X}"
    for address, shift in NOT_MIRRORED_AT.items():
        assert (at(address) >> shift) & MIRROR_BIT == 0, f"the mirror control from ${address:04X} mirrors"

    # The columns: the right edge first, then the left (s5, find_x_offscreen).
    x_masks, x_margins = run(X_MASKS, X_MASKS_SIZE), run(X_MARGINS, 3)
    x_limit, x_base = at(X_LIMIT_AT), at(X_BASE_AT)
    for name, edge, base in (("right", FIRST_EDGE, 0), ("left", SECOND_EDGE, x_base)):
        steps, beyond = edge_bits(x_masks, x_margins, edge, base, x_limit)
        host.game_blob_at(steps, f"offscreen_{name}_bits")
        host.game_blob_at(bytes([beyond]), f"offscreen_{name}_beyond")

    # The rows: the top first, then the bottom (s5, find_y_offscreen).
    y_masks, y_margins = run(Y_MASKS, Y_MASKS_SIZE), run(Y_MARGINS, 3)
    y_limit, y_base = at(Y_LIMIT_AT), at(Y_BASE_AT)
    edge_lows, edge_high = run(Y_EDGE_LOWS, 2), at(Y_EDGE_HIGH_AT)
    for name, edge, base in (("top", FIRST_EDGE, 0), ("bottom", SECOND_EDGE, y_base)):
        steps, beyond = edge_bits(y_masks, y_margins, edge, base, y_limit)
        host.game_blob_at(steps, f"offscreen_{name}_bits")
        host.game_blob_at(bytes([beyond]), f"offscreen_{name}_beyond")
        host.game_blob_at(bytes([edge_lows[edge], edge_high]), f"offscreen_{name}_edge")  # a word, low byte first


def edge_bits(masks, margins, edge, base, limit):
    """The offscreen bits of one screen edge, as the original's find_x_offscreen
    and find_y_offscreen give them (11 section 5), for each 8-pixel step of a
    distance of 0-255 pixels from the edge to the object, and for a negative
    distance. A distance below LIMIT selects mask (distance / 8) and 7, plus
    BASE (scale_position_diff); a larger one in the same page, or one of a
    page or more, keeps the margin entry EDGE + 1; a negative one takes the
    margin entry EDGE."""
    assert limit % COLUMN_PIXELS == 0, "a step of 8 pixels is all below or all above the limit"
    far = masks[margins[edge + 1]]
    steps = bytes(
        masks[base + (step & 7)] if step * COLUMN_PIXELS < limit else far
        for step in range(EDGE_REACH // COLUMN_PIXELS)
    )
    return steps, masks[margins[edge]]
