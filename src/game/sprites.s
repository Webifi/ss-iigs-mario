; The drawing of every object into the 64-entry sprite list, with the
; screen place and the offscreen bits that each drawing uses (document 11:
; the original's $E435-$F2C9).
;
; The game logic of a frame writes the list (state.inc sprite_list, the
; entry of packet_layout.inc: Y, tile, attributes, X); the next frame sends
; it to the card, which shows it by the original picture chip's rules (11
; section 1: lines Y + 1 to Y + 8, no wrap past column 255, the lower
; sprite in front, the behind bit). Before the logic the frame
; (src/game/frame.s) hides sprites 1-63 and moves the objects' first
; sprites (sprite_offset, 02 section 9). The object parts then call the
; routines here in the engine's order (11 section 3):
;   1. the fireballs, their bursts and the air bubbles (05a);
;   2. for each enemy slot 0-5, the slot's routine (05b: an enemy, Bowser's
;      halves, a lift, the vine, the power-up) and its score number (07);
;   3. the player (03 game_core: check_player_offscreen,
;      player_screen_position, draw_player; the victory mode: the place
;      and draw_player only);
;   4. the block objects 1, then 0;
;   5. the misc objects 8 down to 0 (hammers, coins from blocks);
;   6. the flagpole flag in enemy slot 5.
; The lives screen draws the player once (draw_lives_screen_player).
; Objects share sprites (11 section 2), and a later write wins for each
; byte that it writes. So each drawing here writes the same bytes as the
; original, in the same order, the tiles, attributes and X bytes of the
; sprites that it hides too: the list is the original's byte for byte at
; the end of each drawing.
;
; In:  the object's record (D), sprite_offset, screen_left, screen_right,
;      frame_count, timer_hold, the timers, and what each header names.
; Out: sprite_list; rel_x, rel_y and offscreen_bits (also read by 04, 05b,
;      07); vertical_flip; player_frame, player_screen_x (the scroll of the
;      next frame reads it, 04), player_anim_step, the animation timer,
;      throw_timer, player_resizing; and the state changes of the drawings
;      themselves: a hammer off the screen ends, a coin's number rises, a
;      fireball's burst steps and ends, an enemy below the screen is erased
;      (clear_enemy_slot, 05b).
;
; Data: the tiles, attributes and poses of every object and the offscreen
; tables come from the program through scripts/sprites_data.py, as
; labelled bytes in bank 0 (absolute reads, DBR = 0). The drawing rules of
; the enemy codes (draw_code_rules) are a table of this file, in the code's
; bank 1, read with long addressing.
;
; The original's routines, and where they are here:
;   $F12A-$F17F  the screen positions: the entries and screen_position
;   $F180-$F1D6  the offscreen entries and store_offscreen_bits
;   $F1F6-$F281  find_x_offscreen, find_y_offscreen; scale_position_diff and
;                the mask and margin tables become offscreen_step and the
;                edge tables of the build
;   $F282-$F2C9  draw_sprite_pair; draw_tile_pair ($EBB2) and
;                draw_enemy_tile_pair ($EBAA) are the tile loads of its callers
;   $E5B3-$E5C7  set_six_sprite_y and its entries; place_six_sprites ($E4AE)
;                and hide_left_column ($EC4A) are the stores of their callers
;   $E87D-$EBCC  draw_enemy with its steps (draw_flipped_bowser $E946,
;                pick_hammer_bro_frame $E9CA, freeze_anim_check $EA29,
;                defeated_flip_check $EA37, draw_enemy_rows $EA4B) and
;                hide_enemy_offscreen ($EB64, with hide_enemy_row $EBB7 and
;                hide_enemy_column $EBC1)
;   $EEE9-$F129  draw_player and its routines (the size offset $F091 is
;                size_action, offset_for_this_frame $F062 and
;                offset_from_anim_step $F0D0 are pose_of_step and
;                pose_at_step, fixed_frame_actions $F028 is fixed_pose)
;   $EFA4 draw_lives_screen_player, $E5C8 draw_big_lift, $ED66
;   draw_small_lift_sprites, $E435 draw_vine_stack, $E54B draw_flag_sprites,
;   $E6D2 draw_item_sprite, $E4DC draw_spinning_hammer, $E686
;   draw_spinning_coin (with its score part $E655), $EBD1 draw_bumped_block,
;   $EC53 draw_brick_pieces (with check_left_edge_bit $EC46), $ECDE
;   draw_player_fireball, $ECED draw_fire_piece_sprite, $ED09
;   draw_fireball_burst, $ED17 draw_firework_burst, $EDE1 draw_air_bubble
;
; Routines (* the entries that other parts call):
;   *player_screen_position, *enemy_screen_position,
;   *fireball_screen_position, *bubble_screen_position,
;   *misc_screen_position     rel_x, rel_y of the object's group
;   *block_screen_position    the same for both pieces of a block object
;   screen_position           the shared part
;   *check_player_offscreen, *check_enemy_offscreen,
;   *check_fireball_offscreen, *check_bubble_offscreen,
;   *check_misc_offscreen, *check_block_offscreen
;                             offscreen_bits of the object's group
;   store_offscreen_bits      the shared part
;   *find_x_offscreen         the object's 8-pixel columns off the screen
;   find_y_offscreen          its 8-pixel rows off the screen
;   offscreen_step            a distance from an edge as an edge table index
;   set_row_mirror            the mirror of the rows of one drawing
;   draw_sprite_pair          one row of two sprites
;   hide_six_sprites, set_six_sprite_y, set_four_sprite_y,
;   set_three_sprite_y, *set_two_sprite_y
;                             one byte of six, four, three or two sprites
;   *draw_enemy               an enemy: its pose, flips and mirror
;   hide_enemy_offscreen      the enemy's columns and rows off the screen
;   *draw_player              the player
;   draw_player_frame         the player's pose drawn, the throw, the rows off
;   choose_player_action      the pose of the player's action
;   fixed_pose, size_action, pose_of_step, pose_at_step, animate_player
;                             the steps of the action poses
;   apply_size_change_frame   the pose of the size change
;   check_player_attribs      rows drawn as a tile and its mirror
;   draw_player_rows, draw_player_row
;                             the player's rows
;   *draw_lives_screen_player the player on the lives screen
;   *draw_big_lift, *draw_small_lift_sprites
;   *draw_vine_stack, *draw_flag_sprites, *draw_item_sprite
;   *draw_spinning_hammer, *draw_spinning_coin
;   *draw_bumped_block, *draw_brick_pieces
;   *draw_player_fireball, *draw_fire_piece_sprite, *draw_fireball_burst,
;   *draw_firework_burst, *draw_air_bubble
;
; Registers: A8 I8 at each entry and exit unless a header says otherwise.
; DBR = bank 0. D = the record of the object drawn (state.inc); "D any" in
; a header: the routine reads no record. s1, s2, ... are the sprites of an
; object from its first one: sk is at its sprite offset + 4 (k - 1).

.a8
.i8

; ---- Values of the drawing (document 11) ------------------------------------
SPRITE_PIXELS   = 8             ; a sprite's width and height; the step between rows and columns (11 section 1)
BOWSER_DRAW_FRONT = 1           ; bowser_draw (05b): 1 the front half draws, 2 the rear half

; The objects' groups of sprites (11 section 2).
PLAYER_SPRITES  = 8
PLAYER_ROWS     = 4             ; the player's rows of two sprites
BRICK_LOWER_SLOTS = 2           ; a block object's lower piece: the record two slots on (state.inc)
POSE_ROW_BYTES  = 2             ; a row of a pose in the tile tables: the left tile, the right tile
ENEMY_POSE_TILES = 6            ; an enemy pose: three rows; its second step is the next pose (rule O)
PLAYER_POSE_TILES = 8           ; a player pose: four rows; the step adds this (11 section 9)
; draw_enemy (11 section 7).
DRAW_CODE_BULLET = KIND_BULLET_FRENZY ; the drawing code of a bullet bill: the kind of a wave's bullet
DRAW_CODE_FIRST_TURNED = 4      ; rule P: codes from 4 on turn over when defeated; 0-3 (koopas,
                                ;   the buzzy beetle) take the shell poses (rule K)
DRAW_CODE_PRINCESS = $15        ; rule C: the code of the princess or the retainer
DRAW_CODE_BOWSER_FRONT = $16    ; rule E: Bowser's halves
DRAW_CODE_BOWSER_REAR = $17
DRAW_CODE_FIRST_SPRING = $18    ; the jump spring's codes $18-$1A
DRAW_CODES      = $1B           ; the codes of the tables
DRAW_STATE_BITS = $1F           ; the draw state: the low 5 bits of the enemy's state
MIRRORED_DRAW_STATE = 3         ; the draw state of the spring and the retainer (rules C, N): from 2
                                ;   on the halves are mirrored (rule T)
UPSIDE_DOWN     = 1             ; vertical_flip: rules D and P write 1; any value but 0 turns the enemy over
GOOMBA_TURN_FRAMES = $08        ; rule F: FC bit 3 clear: the goomba's mirror
BOWSER_REAR_RAISE = $10         ; rule H: a defeated Bowser's rear half, 16 lines higher
LAKITU_LOW_FRENZY = $10         ; rules J and U: Lakitu's second pose while frenzy_timer is below this
STEP_INTERVAL_LIMIT = 5         ; rule M: from this interval timer on, no second pose
BLOOPER_STILL_INTERVAL = 1      ; rule M: a blooper at this interval timer keeps its first pose
BLOOPER_DROP    = 3             ; rule M: the blooper's second pose, 3 lines lower
; draw_player (11 section 9). The action indexes of player_action_poses;
; the small player's are 8 on.
PLAYER_ACTION_JUMP = 0
PLAYER_ACTION_SWIM = 1
PLAYER_ACTION_STAND = 2
PLAYER_ACTION_SKID = 3
PLAYER_ACTION_WALK = 4
PLAYER_ACTION_CLIMB = 5
PLAYER_ACTION_CROUCH = 6
PLAYER_ACTION_THROW = 7         ; the big fire throw (only the fire player throws)
PLAYER_SMALL_ACTIONS = 8        ; + the action: the small player's pose
PLAYER_ACTION_KILLED = 14       ; the small player's crouch entry: the killed pose
PLAYER_ACTION_GROW_BASE = 15    ; small standing: the base of the growing steps
WALK_STEPS      = 3             ; the walk and the swim strokes: 3 steps; the climb 2
SWIM_STEPS      = 3
CLIMB_STEPS     = 2
SKID_SPEED      = 9             ; a turn from this player_speed_abs on shows the skid
SIZE_CHANGE_STEPS = 10          ; the size change: 10 steps; size_change_poses has the growing
                                ;   steps, then the shrinking ones
SIZE_STEP_FRAMES = 4            ; a size change step each 4 frames (FC and 3 = 0)
SWIM_KICK_FRAMES = $04          ; FC bit 2 clear: the swim kick shows
KICK_FOOT_BIG   = 0             ; swim_kick_foot_tiles: the big player's foot, the small player's
KICK_FOOT_SMALL = 1
LIVES_SCREEN_LAST_ATTR = ATTR_FLIP_X ; s8 on the lives screen: sprite 9's cleared attributes ($00,
                                ;   leftover 3) with the mirror bit
; The other objects.
VINE_PART_SPRITES = 6
VINE_ZIGZAG_X   = 6             ; the vine's right sprites, 6 pixels right of its left ones (s12)
VINE_SHOWN_LINES = $64          ; a vine sprite shows from the vine's start up to 99 lines above it
FLAG_SCORE_GAP  = 12            ; the flag's score number, 12 right of its right column (20 of its X)
FLAG_SCORE_SPRITE = 3           ; the score number's first sprite: s4
FLAG_HIDE_COLUMNS = OFFSCREEN_COLUMN_1 | OFFSCREEN_COLUMN_2 | OFFSCREEN_COLUMN_3
BIG_LIFT_SPRITES = 6
SMALL_LIFT_GAP  = $80           ; the lower small lift, 128 lines below the upper one (s11)
POWERUP_DROP    = 8             ; the power-up's rows start 8 lines below its Y (s14)
HAMMER_SPIN_STEPS = 4           ; the hammer's spin steps, each 4 frames (FC shr 2)
HAMMER_HELD_STEP = 0            ; the step of a hammer in the hand, or while the game is frozen
HAMMER_GONE_BITS = OFFSCREEN_ROWS | OFFSCREEN_COLUMN_1 | OFFSCREEN_COLUMN_2 ; s15: the hammer ends
COIN_SPIN_STEPS = 4             ; the coin's tiles, each 2 frames (FC shr 1)
BRICK_RIGHT_GAP = 6             ; s16: the right piece's X = 2 O - L + 6 + the two carries
BRICK_SPIN_SHIFT = 4            ; s16: FC shifted left 4: bit 2 gives the X flip, bit 3 the Y flip
BURST_STEPS     = 3             ; s17: the burst's steps, each 2 frames; the 7th frame ends it
BURST_STEP_BITS = $07           ; s17: (state shr 1) and 7: the step
BURST_CENTRE    = 4             ; s17: the burst's sprites start 4 left of and 4 above the fireball's
FIRE_TILE_SHIFT = 2             ; s17: FC bit 2 gives the fireball's second tile, each 4 frames
FIRE_FLIP_FRAMES = $08          ; s17: FC bit 3 flips the fireball both ways, each 8 frames
EDGE_REACH      = $100          ; the edge tables cover distances 0-255 from an edge (11 section 5)

; ---- Variables of the drawing -------------------------------------------------
.segment "AREASTATE"
sprite_row_y:   .res 1          ; draw_sprite_pair: the Y of the next row of two sprites (+8 each row)
sprite_row_attr_x: .res 2       ; draw_sprite_pair: the row's attributes (with ATTR_FLIP_X when
                                ;   mirrored, set_row_mirror), then the X of its left sprite
sprite_row_mirror: .res 1       ; draw_sprite_pair: bit 7 set: the rows are mirrored (set_row_mirror)
sprite_rows_left: .res 1        ; draw_player_row: the rows still to draw
draw_first_sprite: .res 1       ; the offset of the drawn object's first sprite (the drawings)
offscreen_column_bits: .res 1   ; store_offscreen_bits: the column bits while the rows are found
enemy_draw_state: .res 1        ; draw_enemy: the draw state (rules C, F, I, N, P; read by K, T)
enemy_draw_status: .res 1       ; draw_enemy: the enemy's state as the rules read it (0 for a
                                ;   cannon's bullet bill, rule C)
enemy_mirror_control: .res 1    ; draw_enemy: the mirror control of the rows (bit 1: mirrored)
enemy_pose:     .res 1          ; draw_enemy: the pose, an offset in enemy_pose_tiles
player_row_bits: .res 1         ; draw_player_frame: the row bits still to test
animation_steps: .res 1         ; animate_player: the steps of the animation
big_lift_columns: .res 1        ; draw_big_lift: the column bits still to test
vine_draw_part: .res 1          ; draw_vine_stack: the part, 0 or 1
brick_screen_origin: .res 1     ; draw_brick_pieces: the block's start on the screen (O, s16)
brick_draw_palette: .res 1      ; draw_brick_pieces: the pieces' palette
.segment "GAMEPLAY"

; draw_code_rules: the rules of draw_enemy that hold for a set of drawing
; codes (11 section 7), one byte for each code; draw_enemy reads it with
; long addressing (the table is in the code's bank).
DRAW_RULE_FIXED_POSE = $01      ; rule N: no 2-step animation (codes $06, $08, $0C, $18-$1A)
DRAW_RULE_OUTER_ROWS = $02      ; rule S: upside down, rows 1 and 3 change places (codes $05, $11,
                                ;   $15-$1A); the other codes swap rows 2 and 3
DRAW_RULE_MIRRORED = $04        ; rule T: the halves are always mirrored (codes $07, $0C, $0D)
draw_code_rules:
        .byte 0                                         ; $00 koopa
        .byte 0                                         ; $01 koopa
        .byte 0                                         ; $02 buzzy beetle
        .byte 0                                         ; $03 koopa
        .byte 0                                         ; $04 koopa
        .byte DRAW_RULE_OUTER_ROWS                      ; $05 hammer brother
        .byte DRAW_RULE_FIXED_POSE                      ; $06 goomba
        .byte DRAW_RULE_MIRRORED                        ; $07 blooper
        .byte DRAW_RULE_FIXED_POSE                      ; $08 bullet bill
        .byte 0                                         ; $09 winged koopa
        .byte 0                                         ; $0A cheep-cheep
        .byte 0                                         ; $0B cheep-cheep
        .byte DRAW_RULE_FIXED_POSE | DRAW_RULE_MIRRORED ; $0C podoboo
        .byte DRAW_RULE_MIRRORED                        ; $0D piranha plant
        .byte 0                                         ; $0E winged koopa
        .byte 0                                         ; $0F winged koopa
        .byte 0                                         ; $10 winged koopa
        .byte DRAW_RULE_OUTER_ROWS                      ; $11 Lakitu
        .byte 0                                         ; $12 spiny
        .byte 0                                         ; $13 (no enemy has it)
        .byte 0                                         ; $14 cheep-cheep
        .byte DRAW_RULE_OUTER_ROWS                      ; $15 princess, retainer
        .byte DRAW_RULE_OUTER_ROWS                      ; $16 Bowser's front half
        .byte DRAW_RULE_OUTER_ROWS                      ; $17 Bowser's rear half
        .byte DRAW_RULE_FIXED_POSE | DRAW_RULE_OUTER_ROWS ; $18 jump spring 1
        .byte DRAW_RULE_FIXED_POSE | DRAW_RULE_OUTER_ROWS ; $19 jump spring 2
        .byte DRAW_RULE_FIXED_POSE | DRAW_RULE_OUTER_ROWS ; $1A jump spring 3
.assert * - draw_code_rules = DRAW_CODES, error, "draw_code_rules: one byte for each drawing code"

.assert SPRITE_Y = 0 && SPRITE_TILE = 1 && SPRITE_ATTR = 2 && SPRITE_X = 3, error, "the byte steps (iny) and the word stores of this file follow the sprite entry"
.assert SPRITE_PIXELS = 1 << 3 && PLAYER_POSE_TILES = 1 << 3, error, "three shifts multiply or divide by 8"


; ===========================================================================
; The screen places (11 section 4)
; ===========================================================================

; ---------------------------------------------------------------------------
; player_screen_position, enemy_screen_position, fireball_screen_position,
; bubble_screen_position, misc_screen_position: the place on the screen of
; the object in D, in the bytes of its group: rel_y = its Y row; rel_x = its
; X pixel - the screen's left pixel, in 8 bits. The page is not used, so
; rel_x is right only for an object 0-255 pixels right of the left edge;
; the offscreen bits catch the other places. A drawing reads its group's
; bytes, so it follows its own position call.
;
; In:       D = the object's record (the player's for the player)
; Out:      rel_x + group, rel_y + group
; Changes:  A, X
; Keeps:    Y
; Time:     33 cycles with the call
; Original: $F12A, $F152, $F13B, $F131, $F148 (the entries),
;           $F171 (to_screen_coordinates, here screen_position)
; ---------------------------------------------------------------------------
player_screen_position:
.a8
.i8
        ldx #REL_PLAYER
        bra screen_position
enemy_screen_position:
.a8
.i8
        ldx #REL_ENEMY
        bra screen_position
fireball_screen_position:
.a8
.i8
        ldx #REL_FIREBALL
        bra screen_position
bubble_screen_position:
.a8
.i8
        ldx #REL_BUBBLE
        bra screen_position
misc_screen_position:
.a8
.i8
        ldx #REL_MISC
; screen_position: the shared part, for the group in X8.
screen_position:
.a8
.i8
        lda Object::y_pos               ; the row: the low byte of the Y word
        sta rel_y,x
        lda Object::x_pos               ; the pixel in its page
        sec
        sbc screen_left                 ; the left edge's pixel (the low byte of its world X)
        sta rel_x,x
        rts

; ---------------------------------------------------------------------------
; block_screen_position: the places of both pieces of a block object: the
; upper one (D, group REL_BLOCK) and the lower one, whose record is two
; slots on (group REL_BLOCK + 1). A bumped block uses the first only.
;
; In:       D = a block object's record (SLOT_BLOCK or SLOT_BLOCK + 1)
; Out:      rel_x, rel_y + REL_BLOCK and REL_BLOCK + 1
; Changes:  A, X
; Keeps:    Y, D
; Time:     102 cycles with the call
; Original: $F159 (block_screen_position)
; ---------------------------------------------------------------------------
block_screen_position:
.a8
.i8
        ldx #REL_BLOCK
        jsr screen_position
        phd
        a16
        tdc
        clc
        adc #BRICK_LOWER_SLOTS * OBJECT_PAGE ; D = the lower piece's record
        tcd
        a8
        ldx #REL_BLOCK + 1
        jsr screen_position
        pld
        rts


; ===========================================================================
; The offscreen bits (11 section 5)
; ===========================================================================

; ---------------------------------------------------------------------------
; check_player_offscreen, check_enemy_offscreen, check_fireball_offscreen,
; check_bubble_offscreen, check_misc_offscreen, check_block_offscreen: the
; offscreen bits of the object in D, in offscreen_bits of its group: bits
; 7-4 its 8-pixel rows 1-4 from its Y, bits 3-0 its 8-pixel columns 1-4
; from its X, set when off the screen by the exact rules of
; find_x_offscreen and find_y_offscreen (not a plain clip: their edges are
; part of the game). A block object gets the bits of its upper piece.
;
; In:       D = the object's record
; Out:      A8 = the bits, also at offscreen_bits + group; N, Z from them
; Changes:  A, X, offscreen_column_bits
; Keeps:    Y
; Time:     145-285 cycles with the call (both edges of each axis: the most)
; Original: $F180, $F1AF, $F187, $F191, $F19B, $F1B6 (the entries);
;           $F1BA, $F1C0, $F1D7 (store_offscreen_offset,
;           compute_offscreen_bits, merge_offscreen_bits: here
;           store_offscreen_bits)
; ---------------------------------------------------------------------------
check_player_offscreen:
.a8
.i8
        ldx #REL_PLAYER
        bra store_offscreen_bits
check_enemy_offscreen:
.a8
.i8
        ldx #REL_ENEMY
        bra store_offscreen_bits
check_fireball_offscreen:
.a8
.i8
        ldx #REL_FIREBALL
        bra store_offscreen_bits
check_bubble_offscreen:
.a8
.i8
        ldx #REL_BUBBLE
        bra store_offscreen_bits
check_misc_offscreen:
.a8
.i8
        ldx #REL_MISC
        bra store_offscreen_bits
check_block_offscreen:
.a8
.i8
        ldx #REL_BLOCK
; store_offscreen_bits: the shared part, for the group in X8.
store_offscreen_bits:
.a8
.i8
        phx
        jsr find_x_offscreen
        lsr
        lsr
        lsr
        lsr                             ; columns 1-4 (bits 7-4 of the eight) in bits 3-0
        sta offscreen_column_bits
        jsr find_y_offscreen
        asl
        asl
        asl
        asl                             ; rows 1-4 in bits 7-4
        plx
        ora offscreen_column_bits
        sta offscreen_bits,x
        rts

; ---------------------------------------------------------------------------
; find_x_offscreen: the 8-pixel columns of the object in D that count as
; off the screen: bit 7 the column at X to X + 7, down to bit 0 the column
; at X + 56 to X + 63 (11 section 5).
;
; The right edge first: dR = screen_right - X, a 16-bit difference (its
; sign is the sign of the original's page byte). Below 0 (the object right
; of the edge): all columns; 0-55: the columns past screen column 255; 56
; or more: the left edge decides. Then dL = screen_left - X. Below 0 (right
; of the edge): none; 0-55: the columns left of the edge, with the first
; one at dL = 0 (the original's one column of strictness: an object at
; screen X 0 loses its left column); 56 or more: all. The build gives the
; bits of each 8-pixel step of each edge (scripts/sprites_data.py, from the
; original's masks and margins); as in the original, a 0 from the right
; edge sends the test on to the left edge.
;
; In:       D = the object's record; screen_left, screen_right
; Out:      A8 = the column bits
; Changes:  A, X
; Keeps:    Y
; Time:     40-120 cycles with the call (the left edge too: the most)
; Original: $F1F6-$F22A (find_x_offscreen), $F26D (scale_position_diff),
;           $F1E3, $F1F3 (x_offscreen_masks, x_onscreen_margins)
; ---------------------------------------------------------------------------
find_x_offscreen:
.a8
.i8
        a16
        lda screen_right
        sec
        sbc Object::x_pos               ; dR
        bmi @past_right
        jsr offscreen_step
.a8
        lda offscreen_right_bits,x
        bne @done                       ; the right edge decides
        bra @left_edge
@past_right:
.a16
        a8
        lda offscreen_right_beyond
        bne @done
@left_edge:
.a8
        a16
        lda screen_left
        sec
        sbc Object::x_pos               ; dL
        bmi @inside_left
        jsr offscreen_step
.a8
        lda offscreen_left_bits,x
        rts
@inside_left:
.a16
        a8
        lda offscreen_left_beyond
@done:
.a8
        rts

; ---------------------------------------------------------------------------
; find_y_offscreen: the 8-pixel rows of the object in D that count as off
; the screen: bit 3 the row at Y to Y + 7, down to bit 0 the row at Y + 24
; to Y + 31 (11 section 5). On the screen the Y word is $0100-$01FF (Y high
; 1, offscreen_top_edge and offscreen_bottom_edge from the build).
;
; The top first: dT = the top edge - the Y word. Below 0 (lower than the
; top): the bottom decides; 0-31: the rows above the top, one row lenient
; (an object 1-7 lines above the top gets 0, and the bottom decides); 32 or
; more: all. Then dB = the bottom edge - the Y word: below 0: all; 0-31:
; the rows past the bottom line; 32 or more: none.
;
; In:       D = the object's record
; Out:      A8 = the row bits, 0-$0F
; Changes:  A, X
; Keeps:    Y
; Time:     60-120 cycles with the call (the bottom too: the most)
; Original: $F239-$F26C (find_y_offscreen), $F26D (scale_position_diff),
;           $F22B, $F234, $F237 (y_offscreen_masks, y_onscreen_margins,
;           high_pos_units)
; ---------------------------------------------------------------------------
find_y_offscreen:
.a8
.i8
        a16
        lda offscreen_top_edge
        sec
        sbc Object::y_pos               ; dT
        bmi @below_top
        jsr offscreen_step
.a8
        lda offscreen_top_bits,x
        bne @done                       ; the top decides
        bra @bottom_edge
@below_top:
.a16
        a8
        lda offscreen_top_beyond
        bne @done
@bottom_edge:
.a8
        a16
        lda offscreen_bottom_edge
        sec
        sbc Object::y_pos               ; dB
        bmi @past_bottom
        jsr offscreen_step
.a8
        lda offscreen_bottom_bits,x
        rts
@past_bottom:
.a16
        a8
        lda offscreen_bottom_beyond
@done:
.a8
        rts

; ---------------------------------------------------------------------------
; offscreen_step: a distance from a screen edge as an index of the edge
; tables: the distance in 8-pixel steps, with a distance of a page or more
; taken as 255. The original reads its far margin for both (the page byte
; 1 or more, or a pixel distance at or past its limit), and the table holds
; that margin's bits in its last steps.
;
; In:       A16 = the distance, 0 to $7FFF
; Out:      A8; X8 = the step, 0-31
; Changes:  A, X
; Keeps:    Y
; Time:     30 cycles with the call
; Original: $F26D-$F281 (scale_position_diff), with the margin rule of
;           $F207-$F213
; ---------------------------------------------------------------------------
offscreen_step:
.a16
.i8
        cmp #EDGE_REACH
        bcc @in_reach
        lda #EDGE_REACH - 1
@in_reach:
        lsr
        lsr
        lsr                             ; / SPRITE_PIXELS
        tax
        a8
        rts


; ===========================================================================
; Rows of two sprites, and one byte of several sprites (11 section 6)
; ===========================================================================

; ---------------------------------------------------------------------------
; set_row_mirror: the mirror of the rows that draw_sprite_pair draws next.
; A mirror control with bit 1 set mirrors them (a direction of FACING_LEFT,
; or any value with that bit, as the original tests it: Bowser's start
; direction $DF, 05b L5). A mirrored row shows its tiles changed over and
; both sprites flipped left to right.
;
; In:       A8 = the mirror control; sprite_row_attr_x
; Out:      sprite_row_mirror bit 7 = mirrored; ATTR_FLIP_X added to the
;           attributes of sprite_row_attr_x when mirrored
; Changes:  A
; Keeps:    X, Y
; Time:     25-35 cycles with the call
; Original: $F282-$F285 and $F292-$F2A0 (draw_sprite_pair's mirror test and
;           its attributes)
; ---------------------------------------------------------------------------
set_row_mirror:
.a8
.i8
        lsr
        lsr                             ; bit 1 into the carry
        ror sprite_row_mirror           ; and into bit 7 (the other bits are not read)
        bpl @done
        lda sprite_row_attr_x
        ora #ATTR_FLIP_X
        sta sprite_row_attr_x
@done:
        rts
.assert FACING_LEFT = 1 << 1, error, "set_row_mirror takes the mirror bit as bit 1"

; ---------------------------------------------------------------------------
; draw_sprite_pair: one row of two sprites: the left tile on the left, or
; the two changed over when the rows are mirrored; both at sprite_row_y,
; with the attributes of sprite_row_attr_x; the right sprite 8 pixels right
; of the left one (mod 256). Then the next row: 8 lines lower (mod 256),
; two sprites on. A sprite's attributes and X are next to each other, so
; one 16-bit store writes both, and the 16-bit add of 8 to the X byte is the
; original's 8-bit add (its carry leaves the word).
;
; In:       A16 = the row's tiles, the left one in the low byte (the build's
;           tile tables keep the original's left, right order)
;           Y8 = the offset of the row's left sprite
;           sprite_row_y, sprite_row_attr_x, sprite_row_mirror
; Out:      A8; Y = Y + 2 sprites; sprite_row_y + 8
; Changes:  A, Y, sprite_row_y
; Keeps:    X
; Time:     95 cycles with the call
; Original: $F282-$F2C9 (draw_sprite_pair)
; ---------------------------------------------------------------------------
draw_sprite_pair:
.a16
.i8
        a8
        bit sprite_row_mirror
        bpl @tiles
        xba                             ; mirrored: the right tile on the left
@tiles:
.a8
        sta sprite_list+SPRITE_TILE,y
        xba
        sta sprite_list+SPRITE_ENTRY+SPRITE_TILE,y
        lda sprite_row_y
        sta sprite_list+SPRITE_Y,y
        sta sprite_list+SPRITE_ENTRY+SPRITE_Y,y
        clc
        adc #SPRITE_PIXELS
        sta sprite_row_y                ; the next row
        a16
        lda sprite_row_attr_x
        sta sprite_list+SPRITE_ATTR,y   ; the attributes and the X of the left sprite
        clc
        adc #SPRITE_PIXELS << 8         ; the right sprite: 8 pixels on
        sta sprite_list+SPRITE_ENTRY+SPRITE_ATTR,y
        a8
        tya
        clc
        adc #2 * SPRITE_ENTRY
        tay
        rts

; ---------------------------------------------------------------------------
; set_six_sprite_y, set_four_sprite_y, set_three_sprite_y, set_two_sprite_y:
; one byte of six, four, three or two sprites in a row of the list: A at
; Y, Y + 4, ... With Y = a first sprite's offset they set the Y bytes; one
; more (SPRITE_TILE), the tiles; two more (SPRITE_ATTR), the attributes.
; Each entry falls into the next: they share the stores of the last
; sprites. hide_six_sprites: six sprites hidden.
;
; In:       A8 = the byte (hide_six_sprites: none); Y8 = the offset of the
;           byte in the first sprite
; Out:      the bytes; hide_six_sprites: A = HIDDEN_Y
; Changes:  nothing (hide_six_sprites: A)
; Time:     12 cycles for the call and 5 a sprite: 22 for two, 42 for six
; Original: $E5B3-$E5C7 (hide_six_sprites, set_six_sprite_y,
;           set_four_sprite_y, set_three_sprite_y, set_two_sprite_y)
; ---------------------------------------------------------------------------
hide_six_sprites:
.a8
.i8
        lda #HIDDEN_Y
set_six_sprite_y:
.a8
.i8
        sta sprite_list+5*SPRITE_ENTRY,y
        sta sprite_list+4*SPRITE_ENTRY,y
set_four_sprite_y:
.a8
.i8
        sta sprite_list+3*SPRITE_ENTRY,y
set_three_sprite_y:
.a8
.i8
        sta sprite_list+2*SPRITE_ENTRY,y
set_two_sprite_y:
.a8
.i8
        sta sprite_list+SPRITE_ENTRY,y
        sta sprite_list,y
        rts


; ===========================================================================
; Enemies (11 sections 7 and 8)
; ===========================================================================

; ---------------------------------------------------------------------------
; draw_enemy: an enemy in the six sprites of its slot: three rows of two
; from its pose, then its flips and the mirror of its halves, then the
; parts off the screen hidden; an enemy below the screen is erased (11
; section 7, rules A-W, in the original's order). The ordinary enemies,
; the bullet bills, the jump spring, the princess and the retainer, and
; each half of Bowser (05b draw_bowser_half sets bowser_draw) draw here.
;
; The rules that hold for a set of drawing codes are draw_code_rules; the
; rules of one kind test its kind. The poses that the rules pick are the
; build's bytes, read from the original's operands. The rows that the rules
; read back (rules S and T) are the ones that its rows wrote, as in the
; original.
;
; In:       D = the enemy's record; rel_x + REL_ENEMY (enemy_screen_position),
;           offscreen_bits + REL_ENEMY (check_enemy_offscreen); bowser_draw,
;           bowser_body, spring_anim, the enemy timers, timer_hold,
;           frame_count, the world
; Out:      s1-s6 of the slot, vertical_flip; the record erased when the
;           enemy is below the screen (clear_enemy_slot)
; Changes:  A, X, Y, the row variables, the enemy_draw variables
; Time:     about 800 cycles, at most about 1,000; 70 for a piranha plant in its pipe
; Original: $E87D-$EB63 (draw_enemy, with draw_flipped_bowser $E946,
;           pick_hammer_bro_frame $E9CA, freeze_anim_check $EA29,
;           defeated_flip_check $EA37, draw_enemy_rows $EA4B,
;           draw_enemy_tile_pair $EBAA)
; ---------------------------------------------------------------------------
draw_enemy:
.a8
.i8
; A. The start: row 1 at the enemy's Y, the left column at its screen X,
; the slot's own sprites, its direction and attributes; not upside down.
        ldx Object::slot
        lda sprite_offset+SPR_ENEMY-SLOT_ENEMY,x
        sta draw_first_sprite
        lda Object::y_pos
        sta sprite_row_y
        lda rel_x+REL_ENEMY
        sta sprite_row_attr_x+1
        lda Object::attributes
        sta sprite_row_attr_x
        lda Object::direction
        sta enemy_mirror_control
        stz vertical_flip
; B. A piranha plant that waits in its pipe (its speed's bit 7 clear, its
; frame timer running) draws nothing: its sprites stay hidden.
        lda Object::kind
        cmp #KIND_PIRANHA
        bne @code
        lda Object::piranha_speed
        bmi @code
        lda timers+TIMER_ENEMY_FRAME-SLOT_ENEMY,x
        beq @code
        rts
; C. The drawing code is the kind, and the draw state the state's low 5
; bits, but for the retainer or princess (code $15, not mirrored), a
; cannon's bullet bill (one line higher, its own palette, behind the
; background while it leaves the cannon, drawn as a wave's bullet bill) and
; the jump spring (its step's code).
@code:
        lda Object::state
        sta enemy_draw_status
        and #DRAW_STATE_BITS
        sta enemy_draw_state
        lda Object::kind
        cmp #KIND_RETAINER
        bne @cannon
        stz enemy_draw_state
        ldy #FACING_RIGHT
        sty enemy_mirror_control
        lda #DRAW_CODE_PRINCESS
@cannon:
        cmp #KIND_BULLET_CANNON
        bne @spring
        dec sprite_row_y
        lda timers+TIMER_ENEMY_FRAME-SLOT_ENEMY,x
        beq @out_of_cannon
        lda #ATTR_BEHIND
@out_of_cannon:
        ora bullet_bill_palette
        sta sprite_row_attr_x           ; in place of the slot's attributes
        stz enemy_draw_state
        stz enemy_draw_status
        lda #DRAW_CODE_BULLET
@spring:
        cmp #KIND_SPRING
        bne @podoboo
        ldy #MIRRORED_DRAW_STATE
        sty enemy_draw_state
        ldy spring_anim
        lda spring_draw_codes,y
; D. A podoboo shows upside down while it falls or stays.
@podoboo:
        sta enemy_draw_code
        cmp #KIND_PODOBOO
        bne @bowser
        lda Object::y_speed_whole
        bmi @bowser
        inc vertical_flip               ; UPSIDE_DOWN
; E. Each half of Bowser has its code.
@bowser:
        lda bowser_draw
        beq @goomba
        ldy #DRAW_CODE_BOWSER_FRONT
        cmp #BOWSER_DRAW_FRONT
        beq @half
        ldy #DRAW_CODE_BOWSER_REAR
@half:
        sty enemy_draw_code
; F. A goomba knocked or stomped (any state from 2 on, its whole byte) has
; draw state 4; a goomba that walks mirrors itself each 8 frames (FC bit
; 3 clear), unless defeated or frozen.
@goomba:
        lda enemy_draw_code
        cmp #KIND_GOOMBA
        bne @code_values
        lda Object::state
        cmp #ENEMY_FLIPPED
        bcc @goomba_walks
        ldy #ENEMY_STOMPED
        sty enemy_draw_state
@goomba_walks:
        and #ENEMY_DEFEATED
        ora timer_hold
        bne @code_values
        lda frame_count
        and #GOOMBA_TURN_FRAMES
        bne @code_values
        lda enemy_mirror_control
        eor #FACING_RIGHT | FACING_LEFT
        sta enemy_mirror_control
; G. The code's attribute bits and first pose.
@code_values:
        ldy enemy_draw_code
        lda enemy_code_attributes,y
        ora sprite_row_attr_x
        sta sprite_row_attr_x
        lda enemy_first_pose,y
        sta enemy_pose
; H. Bowser's halves: the second front pose while the mouth is open, the
; second rear pose on the feet's second step; defeated, each half upside
; down, the rear one 16 lines higher. vertical_flip takes the pose, which
; is never 0. Then the rows.
        lda bowser_draw
        beq @spiny
        cmp #BOWSER_DRAW_FRONT
        bne @rear_half
        bit bowser_body
        bpl @front_defeated             ; BOWSER_MOUTH_OPEN: bit 7
        lda enemy_pose_bowser_front_2
        sta enemy_pose
@front_defeated:
        lda enemy_draw_status
        and #ENEMY_DEFEATED
        beq @bowser_rows
        bra @turn_over
@rear_half:
        lda bowser_body
        and #BOWSER_FEET_STEP
        beq @rear_defeated
        lda enemy_pose_bowser_rear_2
        sta enemy_pose
@rear_defeated:
        lda enemy_draw_status
        and #ENEMY_DEFEATED
        beq @bowser_rows
        lda sprite_row_y
        sec
        sbc #BOWSER_REAR_RAISE
        sta sprite_row_y
@turn_over:
        lda enemy_pose
        sta vertical_flip
@bowser_rows:
        jmp @rows
; I. The spiny's egg (draw state 5): the egg pose, mirrored. Then rule L.
@spiny:
        lda enemy_pose
        cmp enemy_pose_spiny
        bne @lakitu_pose
        lda enemy_draw_state
        cmp #ENEMY_SPINY_EGG
        bne @to_hammer_bro
        lda enemy_pose_spiny_egg
        sta enemy_pose
        lda #FACING_LEFT
        sta enemy_mirror_control
@to_hammer_bro:
        bra @hammer_bro
; J. Lakitu's second pose while frenzy_timer is low (not when defeated).
; Then rule P.
@lakitu_pose:
        cmp enemy_pose_lakitu
        bne @shells
        lda enemy_draw_status
        and #ENEMY_DEFEATED
        bne @to_defeated
        lda timers+TIMER_FRENZY
        cmp #LAKITU_LOW_FRENZY
        bcs @to_defeated
        lda enemy_pose_lakitu_2
        sta enemy_pose
@to_defeated:
        jmp @defeated
; K. The shells: a koopa or buzzy beetle from draw state 2 on shows shell
; A (the buzzy's 1 line lower); in draw state 4 every code shows shell B,
; 1 more line lower for the buzzy (2 in all) and 2 for the others; a goomba
; there shows the goomba pose 2 lines lower, or the flat goomba 1 line
; lower when it is not defeated.
@shells:
        ldx enemy_draw_code
        cpx #DRAW_CODE_FIRST_TURNED
        bcs @stomped
        lda enemy_draw_state
        cmp #ENEMY_FLIPPED
        bcc @stomped
        lda enemy_pose_koopa_shell_a
        sta enemy_pose
        cpx #KIND_BUZZY_BEETLE
        bne @stomped
        lda enemy_pose_buzzy_shell_a
        sta enemy_pose
        inc sprite_row_y
@stomped:
        lda enemy_draw_state
        cmp #ENEMY_STOMPED
        bne @hammer_bro
        lda enemy_pose_buzzy_shell_b
        sta enemy_pose
        inc sprite_row_y
        cpx #KIND_BUZZY_BEETLE
        beq @hammer_bro
        lda enemy_pose_koopa_shell_b
        sta enemy_pose
        inc sprite_row_y
        cpx #KIND_GOOMBA
        bne @hammer_bro
        lda enemy_pose_goomba
        sta enemy_pose
        lda enemy_draw_status
        and #ENEMY_DEFEATED
        bne @hammer_bro
        lda enemy_pose_flat_goomba
        sta enemy_pose
        dec sprite_row_y
; L. The hammer brother: state 0, the 2-step rule; the throw bit, the
; third pose and the 2-step rule; else its first pose.
@hammer_bro:
        lda enemy_draw_code
        cmp #KIND_HAMMER_BRO
        bne @cheep
        lda enemy_draw_status
        beq @step_rule
        and #HAMMER_BRO_THROWING
        beq @defeated
        lda enemy_pose_hammer_bro_3
        sta enemy_pose
        bra @step_rule
; M. A cheep-cheep takes the 2-step rule. The others keep their first pose
; while their interval timer is 5 or more; the blooper takes its second
; pose by its interval timer (0, 2, 3 or 4), 3 lines lower, without the
; frame test.
@cheep:
        lda enemy_pose
        cmp enemy_pose_cheep
        beq @step_rule
        ldx Object::slot
        lda timers+TIMER_ENEMY_INTERVAL-SLOT_ENEMY,x
        cmp #STEP_INTERVAL_LIMIT
        bcs @defeated
        ldx enemy_pose
        cpx enemy_pose_blooper
        bne @step_rule
        cmp #BLOOPER_STILL_INTERVAL
        beq @defeated
        lda sprite_row_y
        clc
        adc #BLOOPER_DROP
        sta sprite_row_y
        bra @second_pose
; N. The 2-step rule: none for the codes of fixed poses; the princess in
; world 8, else the retainer (mirrored); for the others the second pose
; while FC bit 3 is clear (enemy_step_mask: 8 frames each pose, in phase
; for all enemies).
@step_rule:
        ldx enemy_draw_code
        lda f:draw_code_rules,x
        and #DRAW_RULE_FIXED_POSE
        bne @defeated
        cpx #DRAW_CODE_PRINCESS
        bne @step_test
        lda player_record+PlayerRecord::world
        cmp #WORLD_8
        bcs @defeated
        lda enemy_pose_retainer
        sta enemy_pose
        lda #MIRRORED_DRAW_STATE
        sta enemy_draw_state
        bra @defeated
@step_test:
        lda frame_count
        and enemy_step_mask
        bne @defeated
; O. The second pose, unless the enemy is a kicked shell or defeated, or
; the game is frozen.
@second_pose:
        lda enemy_draw_status
        and #ENEMY_KICKED | ENEMY_DEFEATED
        ora timer_hold
        bne @defeated
        lda enemy_pose
        clc
        adc #ENEMY_POSE_TILES
        sta enemy_pose
; P. A defeated enemy from code 4 on is upside down, with draw state 0.
@defeated:
        lda enemy_draw_status
        and #ENEMY_DEFEATED
        beq @rows
        lda enemy_draw_code
        cmp #DRAW_CODE_FIRST_TURNED
        bcc @rows
        lda #UPSIDE_DOWN
        sta vertical_flip
        stz enemy_draw_state
; Q. Three rows from the pose: Y0, Y0 + 8, Y0 + 16. The pose at $FC (jump
; spring 3) reads its third row from the table's bytes 256 and 257, its own
; (the original's 8-bit index wraps to bytes 0 and 1, which hold the same
; tiles: leftover 2).
@rows:
        lda enemy_mirror_control
        jsr set_row_mirror
        ldx enemy_pose
        ldy draw_first_sprite
        a16
        lda enemy_pose_tiles,x
        jsr draw_sprite_pair
.a8
        a16
        lda enemy_pose_tiles+POSE_ROW_BYTES,x
        jsr draw_sprite_pair
.a8
        a16
        lda enemy_pose_tiles+2*POSE_ROW_BYTES,x
        jsr draw_sprite_pair
.a8
; R. A bullet bill shows no flip beyond its direction, also when defeated
; (leftover 8).
        ldy draw_first_sprite
        lda enemy_draw_code
        cmp #DRAW_CODE_BULLET
        bne @upside_down
@to_hide:
        jmp @hide                       ; (rule T's branches to W come here: W is out of their reach)
; S. Upside down: all six attributes are s1's with the Y flip; the tiles of
; rows 1 and 3 (three-row poses) or of rows 2 and 3 (two-row poses) change
; places; the Y bytes stay.
@upside_down:
        lda vertical_flip
        beq @mirror
        lda sprite_list+SPRITE_ATTR,y
        ora #ATTR_FLIP_Y
        sta sprite_list+SPRITE_ATTR,y
        sta sprite_list+SPRITE_ENTRY+SPRITE_ATTR,y
        sta sprite_list+2*SPRITE_ENTRY+SPRITE_ATTR,y
        sta sprite_list+3*SPRITE_ENTRY+SPRITE_ATTR,y
        sta sprite_list+4*SPRITE_ENTRY+SPRITE_ATTR,y
        sta sprite_list+5*SPRITE_ENTRY+SPRITE_ATTR,y
        ldx enemy_draw_code
        lda f:draw_code_rules,x
        and #DRAW_RULE_OUTER_ROWS
        beq @rows_2_3
        tyx                             ; X = row 1
        bra @swap_rows
@rows_2_3:
        tya
        clc
        adc #2 * SPRITE_ENTRY
        tax                             ; X = row 2
; The row at X and row 3 change their tiles; XBA keeps one tile while the
; other moves.
@swap_rows:
        lda sprite_list+SPRITE_TILE,x
        xba
        lda sprite_list+4*SPRITE_ENTRY+SPRITE_TILE,y
        sta sprite_list+SPRITE_TILE,x
        xba
        sta sprite_list+4*SPRITE_ENTRY+SPRITE_TILE,y
        lda sprite_list+SPRITE_ENTRY+SPRITE_TILE,x
        xba
        lda sprite_list+5*SPRITE_ENTRY+SPRITE_TILE,y
        sta sprite_list+SPRITE_ENTRY+SPRITE_TILE,x
        xba
        sta sprite_list+5*SPRITE_ENTRY+SPRITE_TILE,y
; T. The mirror of the halves: none for Bowser and the hammer brother
; (their direction only); always for the blooper, the podoboo and the
; piranha plant; for the spiny in its egg; for the others from draw state
; 2 on. The princess's code first sets s6's attributes (the retainer's are
; mirrored below). Mirrored: the left column keeps s1's flip Y, behind bit
; and palette; the right column adds the X flip (and the Y flip for the
; egg); a stomped enemy (draw state 4) has rows 2 and 3 upside down.
@mirror:
        lda bowser_draw
        bne @to_hide
        ldx enemy_draw_code
        cpx #KIND_HAMMER_BRO
        beq @to_hide
        lda f:draw_code_rules,x
        and #DRAW_RULE_MIRRORED
        bne @mirrored
        cpx #KIND_SPINY
        beq @spiny_mirror
        cpx #DRAW_CODE_PRINCESS
        bne @by_state
        lda princess_last_attr
        sta sprite_list+5*SPRITE_ENTRY+SPRITE_ATTR,y
@by_state:
        lda enemy_draw_state
        cmp #ENEMY_FLIPPED
        bcc @lakitu
        bra @mirrored
@spiny_mirror:
        lda enemy_draw_state
        cmp #ENEMY_SPINY_EGG
        bne @lakitu
@mirrored:
        lda sprite_list+SPRITE_ATTR,y
        and #ATTR_FLIP_Y | ATTR_BEHIND | ATTR_PALETTE
        sta sprite_list+SPRITE_ATTR,y
        sta sprite_list+2*SPRITE_ENTRY+SPRITE_ATTR,y
        sta sprite_list+4*SPRITE_ENTRY+SPRITE_ATTR,y
        ora #ATTR_FLIP_X
        ldx enemy_draw_state
        cpx #ENEMY_SPINY_EGG
        bne @right_column
        ora #ATTR_FLIP_Y
@right_column:
        sta sprite_list+SPRITE_ENTRY+SPRITE_ATTR,y
        sta sprite_list+3*SPRITE_ENTRY+SPRITE_ATTR,y
        sta sprite_list+5*SPRITE_ENTRY+SPRITE_ATTR,y
        cpx #ENEMY_STOMPED
        bne @lakitu
        lda sprite_list+2*SPRITE_ENTRY+SPRITE_ATTR,y
        ora #ATTR_FLIP_Y
        sta sprite_list+2*SPRITE_ENTRY+SPRITE_ATTR,y
        sta sprite_list+4*SPRITE_ENTRY+SPRITE_ATTR,y
        ora #ATTR_FLIP_X
        sta sprite_list+3*SPRITE_ENTRY+SPRITE_ATTR,y
        sta sprite_list+5*SPRITE_ENTRY+SPRITE_ATTR,y
; U. Lakitu's cloud row (row 3, row 1 upside down) mirrored; in his second
; pose (frenzy_timer low) row 2 as the cloud row's right half.
@lakitu:
        lda enemy_draw_code
        cmp #KIND_LAKITU
        bne @spring_rows
        lda vertical_flip
        bne @lakitu_upside_down
        lda sprite_list+4*SPRITE_ENTRY+SPRITE_ATTR,y
        and lakitu_cloud_mask
        sta sprite_list+4*SPRITE_ENTRY+SPRITE_ATTR,y
        lda sprite_list+5*SPRITE_ENTRY+SPRITE_ATTR,y
        ora lakitu_cloud_bits
        sta sprite_list+5*SPRITE_ENTRY+SPRITE_ATTR,y
        ldx timers+TIMER_FRENZY
        cpx #LAKITU_LOW_FRENZY
        bcs @hide
        sta sprite_list+3*SPRITE_ENTRY+SPRITE_ATTR,y
        and lakitu_cloud_mask
        sta sprite_list+2*SPRITE_ENTRY+SPRITE_ATTR,y
        bra @hide
@lakitu_upside_down:
        lda sprite_list+SPRITE_ATTR,y
        and lakitu_cloud_mask
        sta sprite_list+SPRITE_ATTR,y
        lda sprite_list+SPRITE_ENTRY+SPRITE_ATTR,y
        ora lakitu_cloud_bits
        sta sprite_list+SPRITE_ENTRY+SPRITE_ATTR,y
        bra @hide
; V. The jump spring: rows 2 and 3 upside down in their own palette, the
; right column mirrored.
@spring_rows:
        cmp #DRAW_CODE_FIRST_SPRING
        bcc @hide
        lda spring_lower_attr
        sta sprite_list+2*SPRITE_ENTRY+SPRITE_ATTR,y
        sta sprite_list+4*SPRITE_ENTRY+SPRITE_ATTR,y
        ora #ATTR_FLIP_X
        sta sprite_list+3*SPRITE_ENTRY+SPRITE_ATTR,y
        sta sprite_list+5*SPRITE_ENTRY+SPRITE_ATTR,y
; W. The parts off the screen: the fall-through into hide_enemy_offscreen.
@hide:

; ---------------------------------------------------------------------------
; hide_enemy_offscreen: the sprites of an enemy slot whose column or row is
; off the screen, hidden: column 2 (bit 2) s2, s4, s6; column 1 (bit 3)
; s1, s3, s5; row 3 (bit 5) s5, s6; row 2 (bit 6) s3, s4; row 1 (bit 7)
; s1, s2. When row 1 is off and the enemy is below the screen (Y high 2
; exactly), it is erased, unless it is a podoboo (which jumps from there):
; the only state change of an enemy's drawing, made during the draw.
;
; In:       D = the record; Y8 = the slot's first sprite;
;           offscreen_bits + REL_ENEMY
; Out:      Y bytes of the slot's sprites; the record erased (clear_enemy_slot)
; Changes:  A (and what clear_enemy_slot changes)
; Keeps:    X, Y unless the record is erased
; Time:     50-125 cycles
; Original: $EB64-$EBA9 (hide_enemy_offscreen), $EBB7 (hide_enemy_row),
;           $EBC1 (hide_enemy_column)
; ---------------------------------------------------------------------------
hide_enemy_offscreen:
.a8
.i8
        lda offscreen_bits+REL_ENEMY
        and #OFFSCREEN_COLUMN_2
        beq @column_1
        lda #HIDDEN_Y
        sta sprite_list+SPRITE_ENTRY+SPRITE_Y,y
        sta sprite_list+3*SPRITE_ENTRY+SPRITE_Y,y
        sta sprite_list+5*SPRITE_ENTRY+SPRITE_Y,y
@column_1:
        lda offscreen_bits+REL_ENEMY
        and #OFFSCREEN_COLUMN_1
        beq @row_3
        lda #HIDDEN_Y
        sta sprite_list+SPRITE_Y,y
        sta sprite_list+2*SPRITE_ENTRY+SPRITE_Y,y
        sta sprite_list+4*SPRITE_ENTRY+SPRITE_Y,y
@row_3:
        lda offscreen_bits+REL_ENEMY
        and #OFFSCREEN_ROW_3
        beq @row_2
        lda #HIDDEN_Y
        sta sprite_list+4*SPRITE_ENTRY+SPRITE_Y,y
        sta sprite_list+5*SPRITE_ENTRY+SPRITE_Y,y
@row_2:
        lda offscreen_bits+REL_ENEMY
        and #OFFSCREEN_ROW_2
        beq @row_1
        lda #HIDDEN_Y
        sta sprite_list+2*SPRITE_ENTRY+SPRITE_Y,y
        sta sprite_list+3*SPRITE_ENTRY+SPRITE_Y,y
@row_1:
        lda offscreen_bits+REL_ENEMY
        bpl @done                       ; OFFSCREEN_ROW_1: bit 7
        lda #HIDDEN_Y
        sta sprite_list+SPRITE_Y,y
        sta sprite_list+SPRITE_ENTRY+SPRITE_Y,y
        lda Object::kind
        cmp #KIND_PODOBOO
        beq @done
        lda Object::y_pos+1             ; Y high
        cmp #Y_HIGH_BELOW
        bne @done
        jmp clear_enemy_slot
@done:
        rts
.assert OFFSCREEN_ROW_1 = 1 << 7, error, "hide_enemy_offscreen tests row 1 as bit 7"


; ===========================================================================
; The player (11 sections 9 and 10)
; ===========================================================================

; ---------------------------------------------------------------------------
; draw_player: the player in sprites 1-8, four rows of two (sprite_offset's
; player entry, which the shuffle never moves). In the injury blink nothing
; is drawn on odd frames, and player_screen_x keeps the value of the last
; drawn frame for the scroll of the next frame (leftover 5). The pose: the
; killed pose in the death task, the step of the size change while the
; player grows or shrinks, else the pose of his action; a swimmer off the
; ground then kicks.
;
; In:       D = the player's record; rel_x, rel_y, offscreen_bits of
;           REL_PLAYER (check_player_offscreen and player_screen_position;
;           the victory mode keeps the last bits); the timers, swimming,
;           player_task, player_resizing, player_small, player_facing
; Out:      s1-s8; player_frame, player_screen_x, player_anim_step, the
;           animation timer, throw_timer, player_resizing
; Changes:  A, X, Y, the row variables
; Time:     about 800 cycles, at most about 1,550 (the throw pose draws the rows twice);
;           20 on a frame that the blink skips
; Original: $EEE9-$EF44 (draw_player, pick_player_frame $EF34)
; ---------------------------------------------------------------------------
draw_player:
.a8
.i8
; Rule 1: the injury blink, 30 Hz.
        lda timers+TIMER_INJURY
        beq @pose
        lda frame_count
        lsr                             ; bit 0: an odd frame
        bcs @done
@pose:
        lda player_task
        cmp #PLAYER_TASK_DEATH
        beq @killed
        lda player_resizing
        bne @resizing
        lda swimming
        beq @action
        lda Object::state
        beq @action                     ; PLAYER_ON_GROUND: no kick
        jsr choose_player_action
        jsr draw_player_frame
; Rule 6: the swim kick, 4 frames of each 8 (FC bit 2 clear): the left tile
; of row 4 (s7 facing right; s8 facing left, where the row is mirrored)
; becomes the kick's foot; the small player's third swim pose keeps its
; own foot (its tile compared with the table's byte, leftover 6).
        lda frame_count
        and #SWIM_KICK_FRAMES
        bne @done
        ldy sprite_offset+SPR_PLAYER
        lda player_facing
        lsr                             ; bit 0: facing right, the foot in s7
        bcs @foot
        tya
        clc
        adc #SPRITE_ENTRY
        tay                             ; facing left: in s8
@foot:
        ldx #KICK_FOOT_BIG
        lda player_small
        beq @kick
        lda sprite_list+6*SPRITE_ENTRY+SPRITE_TILE,y
        cmp small_swim_3_foot_tile
        beq @done
        ldx #KICK_FOOT_SMALL
@kick:
        lda swim_kick_foot_tiles,x
        sta sprite_list+6*SPRITE_ENTRY+SPRITE_TILE,y
@done:
        rts
@action:
        jsr choose_player_action
        bra draw_player_frame
@resizing:
        jsr apply_size_change_frame
        bra draw_player_frame
@killed:
        lda player_action_poses+PLAYER_ACTION_KILLED
.assert PLAYER_ON_GROUND = 0, error, "draw_player tests the state for 0"
; (falls into draw_player_frame)

; ---------------------------------------------------------------------------
; draw_player_frame: the player's pose drawn: four rows, the rows of
; check_player_attribs, the fire throw pose, then the rows off the screen
; hidden (only rows: the scroll keeps the player on the screen, 04).
;
; The throw pose shows while the animation timer is below throw_timer:
; then throw_timer takes the timer's value and the big throw pose is drawn
; over the rows, all four for a player who stands still (X speed and pad
; both 0), else three (row 4 keeps the walking legs); check_player_attribs
; does not run again. Any other frame clears throw_timer.
;
; In:       A8 = the pose (an offset in player_pose_tiles); D = the
;           player's record
; Out:      s1-s8, player_frame, throw_timer, player_screen_x
; Changes:  A, X, Y, the row variables, player_row_bits
; Time:     about 700 cycles, at most about 1,270 (the throw pose)
; Original: $EF45-$EF9D (draw_player_frame)
; ---------------------------------------------------------------------------
draw_player_frame:
.a8
.i8
        sta player_frame
        lda #PLAYER_ROWS
        jsr draw_player_rows
        jsr check_player_attribs
        lda throw_timer
        beq @hide_rows
        lda timers+TIMER_PLAYER_ANIM
        cmp throw_timer
        stz throw_timer                 ; STZ keeps the compare's carry
        bcs @hide_rows
        sta throw_timer
        lda player_action_poses+PLAYER_ACTION_THROW
        sta player_frame
        ldx #PLAYER_ROWS
        lda Object::x_speed
        ora pad_lr
        beq @throw_rows
        dex
@throw_rows:
        txa
        jsr draw_player_rows
; The rows off the screen: rows 1-4 by bits 7-4.
@hide_rows:
        ldy sprite_offset+SPR_PLAYER
        lda offscreen_bits+REL_PLAYER
        sta player_row_bits
        ldx #PLAYER_ROWS
@row:
        asl player_row_bits             ; this row's bit
        bcc @next_row
        lda #HIDDEN_Y
        jsr set_two_sprite_y
@next_row:
        tya
        clc
        adc #2 * SPRITE_ENTRY
        tay
        dex
        bne @row
        rts

; ---------------------------------------------------------------------------
; choose_player_action: the pose of the player's action, by his state
; (11 section 9). Climbing: the climb, still while his Y speed is 0, else 2
; steps. Falling: the walk pose of the current step, which does not move.
; Jumping: the crouch or the jump, fixed; swimming: the strokes of 3 steps
; while the stroke timer or the step is not 0 or A is held, else the first
; swim pose (its step is 0 there) with no advance. On the ground (and any
; other state): the crouch; standing (X speed and pad both 0); the skid at
; a speed of 9 or more against his facing; else the walk of 3 steps. The
; small player's actions are 8 on.
;
; In:       D = the player's record; crouching, swimming, pad_lr, pad_ab,
;           player_speed_abs, player_facing, player_small
; Out:      A8 = the pose; player_anim_step, the animation timer
; Changes:  A, Y, animation_steps
; Keeps:    X
; Time:     65-170 cycles with the call
; Original: $EFEC-$F027 (choose_player_action), $F034-$F061 (its branches)
; ---------------------------------------------------------------------------
choose_player_action:
.a8
.i8
        lda Object::state
        cmp #PLAYER_CLIMBING
        beq @climbing
        cmp #PLAYER_FALLING
        beq @falling
        cmp #PLAYER_JUMPING
        bne @on_ground
        lda swimming
        bne @swimming
        ldy #PLAYER_ACTION_CROUCH
        lda crouching
        bne fixed_pose
        ldy #PLAYER_ACTION_JUMP
        bra fixed_pose
@on_ground:
        ldy #PLAYER_ACTION_CROUCH
        lda crouching
        bne fixed_pose
        ldy #PLAYER_ACTION_STAND
        lda Object::x_speed
        ora pad_lr
        beq fixed_pose
        lda player_speed_abs
        cmp #SKID_SPEED
        bcc @walking
        lda Object::direction
        and player_facing
        bne @walking                    ; moving the way he faces
        ldy #PLAYER_ACTION_SKID
        bra fixed_pose
@walking:
        ldy #PLAYER_ACTION_WALK
        jsr size_action
        lda #WALK_STEPS
        bra animate_player
@falling:
        ldy #PLAYER_ACTION_WALK
        jsr size_action
        bra pose_of_step
@climbing:
        ldy #PLAYER_ACTION_CLIMB
        lda Object::y_speed_whole
        beq fixed_pose
        jsr size_action
        lda #CLIMB_STEPS
        bra animate_player
@swimming:
        ldy #PLAYER_ACTION_SWIM
        jsr size_action
        lda timers+TIMER_JUMP_SWIM
        ora player_anim_step
        bne @strokes
        bit pad_ab
        bmi @strokes                    ; PAD_A: bit 7
        bra pose_of_step
@strokes:
        lda #SWIM_STEPS
        bra animate_player
.assert PAD_A = 1 << 7, error, "choose_player_action tests A as bit 7"

; ---------------------------------------------------------------------------
; fixed_pose: an action without animation: its step 0, its pose.
;
; In:       Y8 = the action (without the small player's 8)
; Out:      A8 = the pose; player_anim_step = 0
; Changes:  A, Y
; Keeps:    X
; Time:     35-40 cycles
; Original: $F028-$F033 (fixed_frame_actions)
; ---------------------------------------------------------------------------
fixed_pose:
.a8
.i8
        jsr size_action
        stz player_anim_step
        lda player_action_poses,y
        rts

; ---------------------------------------------------------------------------
; size_action: the action of the small player: 8 on.
;
; In:       Y8 = the action; player_small
; Out:      Y8 = the action of the player's size
; Changes:  A, Y
; Keeps:    X
; Time:     20-26 cycles with the call
; Original: $F091-$F09B (get_size_offset)
; ---------------------------------------------------------------------------
size_action:
.a8
.i8
        lda player_small
        beq @done
        tya
        clc
        adc #PLAYER_SMALL_ACTIONS
        tay
@done:
        rts

; ---------------------------------------------------------------------------
; pose_of_step, pose_at_step: the pose of an action at the current step
; (pose_of_step) or at the step in A (pose_at_step): the action's first
; pose + 8 tiles each step.
;
; In:       Y8 = the action of the player's size; pose_at_step: A8 = the step (0-2)
; Out:      A8 = the pose
; Changes:  A
; Keeps:    X, Y
; Time:     28 cycles with the call
; Original: $F062 (offset_for_this_frame), $F0D0 (offset_from_anim_step)
; ---------------------------------------------------------------------------
pose_of_step:
.a8
.i8
        lda player_anim_step
pose_at_step:
.a8
.i8
        asl
        asl
        asl                             ; x PLAYER_POSE_TILES
        clc
        adc player_action_poses,y
        rts

; ---------------------------------------------------------------------------
; animate_player: the pose of the current step; when the animation timer
; has run out, it takes player_anim_rate again (04 sets the rate) and the
; step moves on, back to 0 after the last. The step that moves shows from
; the next frame.
;
; In:       A8 = the steps (3 or 2); Y8 = the action of the player's size
; Out:      A8 = the pose; player_anim_step, the animation timer
; Changes:  A, animation_steps
; Keeps:    X, Y
; Time:     55-80 cycles
; Original: $F06F-$F090 (animate_player), with walk_frame_cycle $F068 and
;           climb_frame_cycle $F06D (the step counts)
; ---------------------------------------------------------------------------
animate_player:
.a8
.i8
        sta animation_steps
        jsr pose_of_step
        pha
        lda timers+TIMER_PLAYER_ANIM
        bne @pose
        lda player_anim_rate
        sta timers+TIMER_PLAYER_ANIM
        lda player_anim_step
        inc a
        cmp animation_steps
        bcc @step
        lda #0                          ; past the last step: the first
@step:
        sta player_anim_step
@pose:
        pla
        rts

; ---------------------------------------------------------------------------
; apply_size_change_frame: the pose of the size change: the step moves on
; each 4 frames (FC and 3 = 0); after the 10th step it is 0 and the change
; ends (player_resizing = 0: the task of 04 waits for it). Growing: small
; standing, the grow pose or big standing, by size_change_poses; shrinking:
; small swim 1 where the shrinking steps are not 0, else big swim 1. The
; frame that ends the change draws step 0.
;
; In:       player_anim_step, player_small, frame_count
; Out:      A8 = the pose; player_anim_step, player_resizing
; Changes:  A, Y
; Keeps:    X
; Time:     45-70 cycles with the call
; Original: $F0B0-$F0E8 (apply_size_change_frame)
; ---------------------------------------------------------------------------
apply_size_change_frame:
.a8
.i8
        ldy player_anim_step
        lda frame_count
        and #SIZE_STEP_FRAMES - 1
        bne @pose
        iny
        cpy #SIZE_CHANGE_STEPS
        bcc @step
        ldy #0
        sty player_resizing             ; the end of the change
@step:
        sty player_anim_step
@pose:
        lda player_small
        bne @shrinking
        lda size_change_poses,y         ; 0-2: the step of the growing poses
        ldy #PLAYER_ACTION_GROW_BASE
        bra pose_at_step
@shrinking:
        lda size_change_poses+SIZE_CHANGE_STEPS,y
        beq @big
        lda player_action_poses+PLAYER_SMALL_ACTIONS+PLAYER_ACTION_SWIM
        rts
@big:
        lda player_action_poses+PLAYER_ACTION_SWIM
        rts

; ---------------------------------------------------------------------------
; check_player_attribs: the rows of a pose whose two tiles are one tile,
; drawn as the tile and its mirror whatever the facing: in the death task
; and in big standing rows 3 and 4; in the crouch, small standing and the
; grow pose row 4. The left sprite loses both flips, the right one gets the
; X flip; the behind bit and the palette stay. (Document 11 gives big
; standing row 4 only; the original's test of that pose falls into the
; death task's row 3, and its rows 3 and 4 are both one tile.)
;
; In:       player_task, player_frame; the player's sprites
; Out:      s5-s8's attributes
; Changes:  A, Y
; Keeps:    X
; Time:     50-100 cycles with the call
; Original: $F0E9-$F129 (check_player_attribs)
; ---------------------------------------------------------------------------
check_player_attribs:
.a8
.i8
        ldy sprite_offset+SPR_PLAYER
        lda player_task
        cmp #PLAYER_TASK_DEATH
        beq @row_3
        lda player_frame
        cmp player_pose_big_crouch
        beq @row_4
        cmp player_pose_small_stand
        beq @row_4
        cmp player_pose_grow
        beq @row_4
        cmp player_pose_big_stand
        beq @row_3                      ; big standing: rows 3 and 4
        rts
@row_3:
        lda sprite_list+4*SPRITE_ENTRY+SPRITE_ATTR,y
        and #<~(ATTR_FLIP_X | ATTR_FLIP_Y)
        sta sprite_list+4*SPRITE_ENTRY+SPRITE_ATTR,y
        lda sprite_list+5*SPRITE_ENTRY+SPRITE_ATTR,y
        and #<~(ATTR_FLIP_X | ATTR_FLIP_Y)
        ora #ATTR_FLIP_X
        sta sprite_list+5*SPRITE_ENTRY+SPRITE_ATTR,y
@row_4:
        lda sprite_list+6*SPRITE_ENTRY+SPRITE_ATTR,y
        and #<~(ATTR_FLIP_X | ATTR_FLIP_Y)
        sta sprite_list+6*SPRITE_ENTRY+SPRITE_ATTR,y
        lda sprite_list+7*SPRITE_ENTRY+SPRITE_ATTR,y
        and #<~(ATTR_FLIP_X | ATTR_FLIP_Y)
        ora #ATTR_FLIP_X
        sta sprite_list+7*SPRITE_ENTRY+SPRITE_ATTR,y
        rts

; ---------------------------------------------------------------------------
; draw_player_rows: the player's rows from his pose: row 1 at his screen
; Y, the left column at his screen X, mirrored when he faces left, every
; sprite with his attributes (04 and the star colours set them). It writes
; player_screen_x, which the scroll of the next frame reads: its only
; writer (leftover 5). draw_player_row: the rows from the pose offset in X
; at the sprite in Y, as the lives screen enters it.
;
; In:       A8 = the rows (3 or 4); D = the player's record; player_frame,
;           rel_x, rel_y of REL_PLAYER, player_facing, sprite_offset
;           draw_player_row: X8 = the pose, Y8 = the first sprite,
;           sprite_rows_left = the rows, the row variables set
; Out:      the rows' sprites; player_screen_x
; Changes:  A, X, Y, the row variables
; Time:     about 120 cycles a row: 420-560 for the player's rows
; Original: $EFBE-$EFDB (draw_player_rows), $EFDC-$EFEB (draw_player_row)
; ---------------------------------------------------------------------------
draw_player_rows:
.a8
.i8
        sta sprite_rows_left
        lda rel_x+REL_PLAYER
        sta player_screen_x
        sta sprite_row_attr_x+1
        lda Object::attributes
        sta sprite_row_attr_x
        lda rel_y+REL_PLAYER
        sta sprite_row_y
        lda player_facing
        jsr set_row_mirror
        ldx player_frame
        ldy sprite_offset+SPR_PLAYER
draw_player_row:
.a8
.i8
        a16
        lda player_pose_tiles,x
        jsr draw_sprite_pair
.a8
        inx
        inx                             ; the next row of the pose (POSE_ROW_BYTES)
        dec sprite_rows_left
        bne draw_player_row
        rts
.assert POSE_ROW_BYTES = 2, error, "draw_player_row steps a row with two INX"

; ---------------------------------------------------------------------------
; draw_lives_screen_player: the small player standing on the lives screen,
; in sprites 1-8, from the original's table of his place, mirror control,
; attributes and rows (11 section 10); then sprite 8 as the mirror of its
; left neighbour. The original takes sprite 8's attributes from sprite 9's,
; which the area setup clears before every lives screen and nothing writes
; in between (leftover 3): the mirror bit alone.
;
; In:       D any
; Out:      sprites 1-8
; Changes:  A, X, Y, the row variables
; Time:     550 cycles with the call, once for each lives screen
; Original: $EFA4-$EFBD (draw_lives_screen_player), $EF9E (its table)
; ---------------------------------------------------------------------------
draw_lives_screen_player:
.a8
.i8
        lda lives_screen_y
        sta sprite_row_y
        lda lives_screen_attr
        sta sprite_row_attr_x
        lda lives_screen_x
        sta sprite_row_attr_x+1
        lda lives_screen_mirror
        jsr set_row_mirror
        lda lives_screen_rows
        sta sprite_rows_left
        ldx player_pose_lives_screen
        ldy #PLAYER_FIRST_SPRITE * SPRITE_ENTRY
        jsr draw_player_row
        lda #LIVES_SCREEN_LAST_ATTR
        sta sprite_list+(PLAYER_FIRST_SPRITE + PLAYER_SPRITES - 1) * SPRITE_ENTRY + SPRITE_ATTR
        rts


; ===========================================================================
; Lifts, the vine, the flag, the power-up (11 sections 11-14)
; ===========================================================================

; ---------------------------------------------------------------------------
; draw_big_lift: a large lift, six sprites side by side, 8 pixels apart; in
; a castle and with the harder enemies (hard_mode_2) only four show (s5
; and s6 hidden). The girder tile, or the cloud in the cloud areas. Each
; sprite whose 8-pixel column is off the screen is hidden (the column bits
; of the lift itself, 7 down to 2 for s1-s6); all six when its row is.
;
; In:       D = the lift's record; rel_x, offscreen_bits of REL_ENEMY
; Out:      s1-s6 of the slot
; Changes:  A, X, Y, big_lift_columns, draw_first_sprite
; Time:     450-580 cycles with the call
; Original: $E5C8-$E654 (draw_big_lift), with place_six_sprites $E4AE
; ---------------------------------------------------------------------------
draw_big_lift:
.a8
.i8
        ldx Object::slot
        ldy sprite_offset+SPR_ENEMY-SLOT_ENEMY,x
        sty draw_first_sprite
        lda rel_x+REL_ENEMY
        sta sprite_list+SPRITE_X,y
        clc
        adc #SPRITE_PIXELS
        sta sprite_list+SPRITE_ENTRY+SPRITE_X,y
        clc
        adc #SPRITE_PIXELS
        sta sprite_list+2*SPRITE_ENTRY+SPRITE_X,y
        clc
        adc #SPRITE_PIXELS
        sta sprite_list+3*SPRITE_ENTRY+SPRITE_X,y
        clc
        adc #SPRITE_PIXELS
        sta sprite_list+4*SPRITE_ENTRY+SPRITE_X,y
        clc
        adc #SPRITE_PIXELS
        sta sprite_list+5*SPRITE_ENTRY+SPRITE_X,y
        lda Object::y_pos
        jsr set_four_sprite_y
        ldx area_type
        cpx #AREA_CASTLE
        beq @short
        ldx hard_mode_2
        beq @long
@short:
        lda #HIDDEN_Y
@long:
        sta sprite_list+4*SPRITE_ENTRY+SPRITE_Y,y
        sta sprite_list+5*SPRITE_ENTRY+SPRITE_Y,y
        lda big_lift_tile
        ldx cloud_override
        beq @tile
        lda cloud_lift_tile
@tile:
        iny                             ; SPRITE_TILE
        jsr set_six_sprite_y
        lda big_lift_attr
        iny                             ; SPRITE_ATTR
        jsr set_six_sprite_y
; The columns of the lift: bit 7 for s1 down to bit 2 for s6.
        jsr find_x_offscreen
        sta big_lift_columns
        ldy draw_first_sprite
        ldx #BIG_LIFT_SPRITES
@column:
        asl big_lift_columns
        bcc @next_column
        lda #HIDDEN_Y
        sta sprite_list+SPRITE_Y,y
@next_column:
        tya
        clc
        adc #SPRITE_ENTRY
        tay
        dex
        bne @column
; The lift's row.
        ldy draw_first_sprite
        lda offscreen_bits+REL_ENEMY
        bpl @done                       ; OFFSCREEN_ROW_1
        jmp hide_six_sprites
@done:
        rts

; ---------------------------------------------------------------------------
; draw_small_lift_sprites: a pair of small lifts, 128 lines apart: s1-s3
; the upper one, s4-s6 the lower one (its Y + $80, mod 256), three sprites
; side by side each; a lift above line $20 (the status bar's lines) is
; hidden. Bit 3 of the offscreen bits hides s1 and s4, bit 2 s2 and s5,
; bit 1 s3 and s6; the rows are not tested.
;
; In:       D = the lift's record; rel_x, offscreen_bits of REL_ENEMY
; Out:      s1-s6 of the slot
; Changes:  A, X, Y
; Time:     245-280 cycles with the call
; Original: $ED66-$EDE0 (draw_small_lift_sprites)
; ---------------------------------------------------------------------------
draw_small_lift_sprites:
.a8
.i8
        ldx Object::slot
        ldy sprite_offset+SPR_ENEMY-SLOT_ENEMY,x
        lda small_lift_tile
        iny                             ; SPRITE_TILE
        jsr set_six_sprite_y
        lda small_lift_attr
        iny                             ; SPRITE_ATTR
        jsr set_six_sprite_y
        dey
        dey
        lda rel_x+REL_ENEMY
        sta sprite_list+SPRITE_X,y
        sta sprite_list+3*SPRITE_ENTRY+SPRITE_X,y
        clc
        adc #SPRITE_PIXELS
        sta sprite_list+SPRITE_ENTRY+SPRITE_X,y
        sta sprite_list+4*SPRITE_ENTRY+SPRITE_X,y
        clc
        adc #SPRITE_PIXELS
        sta sprite_list+2*SPRITE_ENTRY+SPRITE_X,y
        sta sprite_list+5*SPRITE_ENTRY+SPRITE_X,y
        lda Object::y_pos
        cmp #SMALL_LIFT_TOP
        bcs @upper
        lda #HIDDEN_Y
@upper:
        jsr set_three_sprite_y
        lda Object::y_pos
        clc
        adc #SMALL_LIFT_GAP
        cmp #SMALL_LIFT_TOP
        bcs @lower
        lda #HIDDEN_Y
@lower:
        sta sprite_list+3*SPRITE_ENTRY+SPRITE_Y,y
        sta sprite_list+4*SPRITE_ENTRY+SPRITE_Y,y
        sta sprite_list+5*SPRITE_ENTRY+SPRITE_Y,y
        lda offscreen_bits+REL_ENEMY
        and #OFFSCREEN_COLUMN_1
        beq @column_2
        lda #HIDDEN_Y
        sta sprite_list+SPRITE_Y,y
        sta sprite_list+3*SPRITE_ENTRY+SPRITE_Y,y
@column_2:
        lda offscreen_bits+REL_ENEMY
        and #OFFSCREEN_COLUMN_2
        beq @column_3
        lda #HIDDEN_Y
        sta sprite_list+SPRITE_ENTRY+SPRITE_Y,y
        sta sprite_list+4*SPRITE_ENTRY+SPRITE_Y,y
@column_3:
        lda offscreen_bits+REL_ENEMY
        and #OFFSCREEN_COLUMN_3
        beq @done
        lda #HIDDEN_Y
        sta sprite_list+2*SPRITE_ENTRY+SPRITE_Y,y
        sta sprite_list+5*SPRITE_ENTRY+SPRITE_Y,y
@done:
        rts

; ---------------------------------------------------------------------------
; draw_vine_stack: one part of the vine: a column of six sprites in the
; sprites of the enemy slot that vine_slots names for the part, from the
; vine's screen place (part 1 48 lines under part 0: one column of twelve).
; The left sprites at the vine's X, the right ones 6 pixels right and
; mirrored: the vine zigzags; behind the background. The stem tile, the top
; tile on part 0's first sprite. A sprite shows only from the vine's start
; Y up to 99 lines above it: (vine_start_y - its Y) mod 256 below $64.
; The vine's offscreen bits are not used here (run_vine erases the vine
; after the draw, 05a).
;
; In:       Y8 = the part, 0 or 1; vine_slots[part] = the enemy (0-5) of
;           its sprites; rel_x, rel_y of REL_ENEMY (slot 5, the vine);
;           vine_start_y (the first vine's start)
; Out:      the six sprites; Y8 = the part
; Changes:  A, X, vine_draw_part
; Time:     380-435 cycles with the call
; Original: $E435-$E4AD (draw_vine_stack), with place_six_sprites $E4AE
; ---------------------------------------------------------------------------
draw_vine_stack:
.a8
.i8
        sty vine_draw_part
        ldx vine_slots,y
        lda rel_y+REL_ENEMY
        clc
        adc vine_part_y,y
        ldy sprite_offset+SPR_ENEMY,x
        sta sprite_list+SPRITE_Y,y
        clc
        adc #SPRITE_PIXELS
        sta sprite_list+SPRITE_ENTRY+SPRITE_Y,y
        clc
        adc #SPRITE_PIXELS
        sta sprite_list+2*SPRITE_ENTRY+SPRITE_Y,y
        clc
        adc #SPRITE_PIXELS
        sta sprite_list+3*SPRITE_ENTRY+SPRITE_Y,y
        clc
        adc #SPRITE_PIXELS
        sta sprite_list+4*SPRITE_ENTRY+SPRITE_Y,y
        clc
        adc #SPRITE_PIXELS
        sta sprite_list+5*SPRITE_ENTRY+SPRITE_Y,y
        lda rel_x+REL_ENEMY
        sta sprite_list+SPRITE_X,y
        sta sprite_list+2*SPRITE_ENTRY+SPRITE_X,y
        sta sprite_list+4*SPRITE_ENTRY+SPRITE_X,y
        clc
        adc #VINE_ZIGZAG_X
        sta sprite_list+SPRITE_ENTRY+SPRITE_X,y
        sta sprite_list+3*SPRITE_ENTRY+SPRITE_X,y
        sta sprite_list+5*SPRITE_ENTRY+SPRITE_X,y
        lda vine_attr
        sta sprite_list+SPRITE_ATTR,y
        sta sprite_list+2*SPRITE_ENTRY+SPRITE_ATTR,y
        sta sprite_list+4*SPRITE_ENTRY+SPRITE_ATTR,y
        ora #ATTR_FLIP_X
        sta sprite_list+SPRITE_ENTRY+SPRITE_ATTR,y
        sta sprite_list+3*SPRITE_ENTRY+SPRITE_ATTR,y
        sta sprite_list+5*SPRITE_ENTRY+SPRITE_ATTR,y
        lda vine_stem_tile
        iny                             ; SPRITE_TILE
        jsr set_six_sprite_y
        dey
        lda vine_draw_part
        bne @heights
        lda vine_top_tile
        sta sprite_list+SPRITE_TILE,y
@heights:
        ldx #VINE_PART_SPRITES
@sprite:
        lda vine_start_y
        sec
        sbc sprite_list+SPRITE_Y,y
        cmp #VINE_SHOWN_LINES
        bcc @next_sprite
        lda #HIDDEN_Y
        sta sprite_list+SPRITE_Y,y
@next_sprite:
        tya
        clc
        adc #SPRITE_ENTRY
        tay
        dex
        bne @sprite
        ldy vine_draw_part
        rts

; ---------------------------------------------------------------------------
; draw_flag_sprites: the flagpole flag, three sprites: s1, s2 at the flag's
; Y, s3 a row under s2; and, once the player touched the pole, his score
; number in s4, s5 (one row, 20 pixels right of the flag, at its own Y).
; Any of the flag's three columns off the screen hides s1-s6.
;
; The score number's X is the flag's X + 8, then + 12, in 8 bits; the
; original adds s3's row to the flag's Y with the carry of that second add
; (leftover 1): at screen X 236-247 the lowest flag sprite is one line
; lower. The add follows that sum here, so the carry is the same. One
; operand of the original gives the flag's attributes and the score
; number's attributes and mirror control (not mirrored; the build checks
; the byte).
;
; In:       D = the flag's record (slot 5); rel_x, offscreen_bits of
;           REL_ENEMY; flag_touch_y, flag_score, flag_score_y
; Out:      s1-s5 of the slot (s1-s6 hidden off the screen)
; Changes:  A, X, Y, the row variables, draw_first_sprite
; Time:     135-300 cycles with the call
; Original: $E54B-$E5B2 (draw_flag_sprites)
; ---------------------------------------------------------------------------
draw_flag_sprites:
.a8
.i8
        ldx Object::slot
        ldy sprite_offset+SPR_ENEMY-SLOT_ENEMY,x
        sty draw_first_sprite
        lda rel_x+REL_ENEMY
        sta sprite_list+SPRITE_X,y
        clc
        adc #SPRITE_PIXELS
        sta sprite_list+SPRITE_ENTRY+SPRITE_X,y
        sta sprite_list+2*SPRITE_ENTRY+SPRITE_X,y
        clc
        adc #FLAG_SCORE_GAP
        sta sprite_row_attr_x+1         ; the score number's X; the carry goes on
        lda Object::y_pos
        sta sprite_list+SPRITE_Y,y
        sta sprite_list+SPRITE_ENTRY+SPRITE_Y,y
        adc #SPRITE_PIXELS              ; + the carry of the score number's X (leftover 1)
        sta sprite_list+2*SPRITE_ENTRY+SPRITE_Y,y
        lda flag_attr
        sta sprite_list+SPRITE_ATTR,y
        sta sprite_list+SPRITE_ENTRY+SPRITE_ATTR,y
        sta sprite_list+2*SPRITE_ENTRY+SPRITE_ATTR,y
        sta sprite_row_attr_x
        lda flag_tile
        sta sprite_list+SPRITE_TILE,y
        sta sprite_list+2*SPRITE_ENTRY+SPRITE_TILE,y
        lda flag_skull_tile
        sta sprite_list+SPRITE_ENTRY+SPRITE_TILE,y
        lda flag_touch_y
        beq @offscreen
        lda flag_score_y+1              ; its Y (the byte after its fraction)
        sta sprite_row_y
        stz sprite_row_mirror
        lda flag_score
        asl                             ; two tiles a score
        tax
        tya
        clc
        adc #FLAG_SCORE_SPRITE * SPRITE_ENTRY
        tay
        a16
        lda flag_score_tiles,x
        jsr draw_sprite_pair
.a8
@offscreen:
        ldy draw_first_sprite
        lda offscreen_bits+REL_ENEMY
        and #FLAG_HIDE_COLUMNS
        beq @done
        jmp hide_six_sprites
@done:
        rts

; ---------------------------------------------------------------------------
; draw_item_sprite: the power-up in enemy slot 5: two rows, 8 and 16 lines
; under its Y, not mirrored, with the kind's palette and the slot's behind
; bit (it rises from the block). The fire flower and the star change their
; palette each 2 frames ((FC shr 1) and 3; the flower's stem keeps its
; palette), and their right column is mirrored. Then the parts off the
; screen, as an enemy's (the rows of the bits are 8 lines above the rows of
; the sprites); a power-up below the screen is erased.
;
; In:       D = slot 5's record; rel_x, rel_y, offscreen_bits of REL_ENEMY;
;           powerup_kind
; Out:      s1-s4 of slot 5 (s1-s6 hidden by the offscreen bits)
; Changes:  A, X, Y, the row variables
; Time:     315-470 cycles with the call
; Original: $E6D2-$E73D (draw_item_sprite)
; ---------------------------------------------------------------------------
draw_item_sprite:
.a8
.i8
        lda rel_y+REL_ENEMY
        clc
        adc #POWERUP_DROP
        sta sprite_row_y
        lda rel_x+REL_ENEMY
        sta sprite_row_attr_x+1
        ldx powerup_kind
        lda powerup_palettes,x
        ora Object::attributes          ; the behind bit while it rises
        sta sprite_row_attr_x
        stz sprite_row_mirror           ; the original's mirror control 1 (the build checks it)
        txa
        asl
        asl                             ; four tiles a kind
        tax
        ldy sprite_offset+SPR_ENEMY+SLOT_SPECIAL-SLOT_ENEMY
        a16
        lda powerup_pose_tiles,x
        jsr draw_sprite_pair
.a8
        a16
        lda powerup_pose_tiles+POSE_ROW_BYTES,x
        jsr draw_sprite_pair
.a8
        ldy sprite_offset+SPR_ENEMY+SLOT_SPECIAL-SLOT_ENEMY
        lda powerup_kind
        beq @offscreen                  ; POWERUP_MUSHROOM
        cmp #POWERUP_1UP
        beq @offscreen
        lda frame_count
        lsr
        and #ATTR_PALETTE
        ora Object::attributes
        sta sprite_list+SPRITE_ATTR,y
        sta sprite_list+SPRITE_ENTRY+SPRITE_ATTR,y
        ldx powerup_kind
        cpx #POWERUP_FLOWER
        beq @mirror
        sta sprite_list+2*SPRITE_ENTRY+SPRITE_ATTR,y
        sta sprite_list+3*SPRITE_ENTRY+SPRITE_ATTR,y
@mirror:
        lda sprite_list+SPRITE_ENTRY+SPRITE_ATTR,y
        ora #ATTR_FLIP_X
        sta sprite_list+SPRITE_ENTRY+SPRITE_ATTR,y
        lda sprite_list+3*SPRITE_ENTRY+SPRITE_ATTR,y
        ora #ATTR_FLIP_X
        sta sprite_list+3*SPRITE_ENTRY+SPRITE_ATTR,y
@offscreen:
        jmp hide_enemy_offscreen
.assert POWERUP_MUSHROOM = 0, error, "draw_item_sprite tests the mushroom as 0"


; ===========================================================================
; Misc objects (11 section 15)
; ===========================================================================

; ---------------------------------------------------------------------------
; draw_spinning_hammer: a hammer, two sprites placed by its spin step: the
; first from the hammer's screen place, the second from the first. The
; step is 0 while the game is frozen or the hammer is in the thrower's
; hand; in flight it moves on each 4 frames ((FC shr 2) and 3). Any of its
; rows, or column 1 or 2, off the screen ends the hammer (state 0) and
; hides it.
;
; In:       D = the misc object's record; rel_x, rel_y, offscreen_bits of
;           REL_MISC; timer_hold
; Out:      s1, s2 of the misc slot; the hammer's state 0 off the screen
; Changes:  A, X, Y
; Time:     115-155 cycles with the call
; Original: $E4DC-$E540 (draw_spinning_hammer)
; ---------------------------------------------------------------------------
draw_spinning_hammer:
.a8
.i8
        ldx Object::slot
        ldy sprite_offset+SPR_MISC-SLOT_MISC,x
        ldx #HAMMER_HELD_STEP
        lda timer_hold
        bne @step
        lda Object::state
        and #<~MISC_HAMMER
        cmp #HAMMER_FLYING
        bne @step
        lda frame_count
        lsr
        lsr
        and #HAMMER_SPIN_STEPS - 1
        tax
@step:
        lda rel_y+REL_MISC
        clc
        adc hammer_spin_y,x
        sta sprite_list+SPRITE_Y,y
        clc
        adc hammer_spin_next_y,x
        sta sprite_list+SPRITE_ENTRY+SPRITE_Y,y
        lda rel_x+REL_MISC
        clc
        adc hammer_spin_x,x
        sta sprite_list+SPRITE_X,y
        clc
        adc hammer_spin_next_x,x
        sta sprite_list+SPRITE_ENTRY+SPRITE_X,y
        lda hammer_spin_tile,x
        sta sprite_list+SPRITE_TILE,y
        lda hammer_spin_next_tile,x
        sta sprite_list+SPRITE_ENTRY+SPRITE_TILE,y
        lda hammer_spin_attr,x
        sta sprite_list+SPRITE_ATTR,y
        sta sprite_list+SPRITE_ENTRY+SPRITE_ATTR,y
        lda offscreen_bits+REL_MISC
        and #HAMMER_GONE_BITS
        beq @done
        stz Object::state
        lda #HIDDEN_Y
        jmp set_two_sprite_y
@done:
        rts

; ---------------------------------------------------------------------------
; draw_spinning_coin: a coin from a block (misc state 1), two sprites: the
; upper one at the coin's Y, the lower one a row under it, upside down; the
; tile changes each 2 frames ((FC shr 1) and 3). From misc state 2 on, its
; "200": the number rises 1 line each 2 frames (the misc object's Y - 1 on
; frames with FC bit 0 clear, the low byte only, as the original), two
; sprites side by side. There is no offscreen test.
;
; In:       D = the misc object's record; rel_x of REL_MISC
; Out:      s1, s2 of the misc slot; the Y of the number
; Changes:  A, X, Y
; Time:     95 cycles with the call
; Original: $E686-$E6BD (draw_spinning_coin), $E655-$E681 (its score part)
; ---------------------------------------------------------------------------
draw_spinning_coin:
.a8
.i8
        ldx Object::slot
        ldy sprite_offset+SPR_MISC-SLOT_MISC,x
        lda Object::state
        cmp #MISC_COIN_SCORE
        bcs @score
        lda Object::y_pos
        sta sprite_list+SPRITE_Y,y
        clc
        adc #SPRITE_PIXELS
        sta sprite_list+SPRITE_ENTRY+SPRITE_Y,y
        lda rel_x+REL_MISC
        sta sprite_list+SPRITE_X,y
        sta sprite_list+SPRITE_ENTRY+SPRITE_X,y
        lda frame_count
        lsr
        and #COIN_SPIN_STEPS - 1
        tax
        lda coin_spin_tiles,x
        sta sprite_list+SPRITE_TILE,y
        sta sprite_list+SPRITE_ENTRY+SPRITE_TILE,y
        lda coin_attr
        sta sprite_list+SPRITE_ATTR,y
        lda coin_lower_attr
        sta sprite_list+SPRITE_ENTRY+SPRITE_ATTR,y
        rts
@score:
        lda frame_count
        lsr                             ; bit 0: odd frames keep the Y
        bcs @shown
        dec Object::y_pos
@shown:
        lda Object::y_pos
        sta sprite_list+SPRITE_Y,y
        sta sprite_list+SPRITE_ENTRY+SPRITE_Y,y
        lda rel_x+REL_MISC
        sta sprite_list+SPRITE_X,y
        clc
        adc #SPRITE_PIXELS
        sta sprite_list+SPRITE_ENTRY+SPRITE_X,y
        lda coin_score_attr
        sta sprite_list+SPRITE_ATTR,y
        sta sprite_list+SPRITE_ENTRY+SPRITE_ATTR,y
        lda coin_score_tile
        sta sprite_list+SPRITE_TILE,y
        lda coin_score_zeros_tile
        sta sprite_list+SPRITE_ENTRY+SPRITE_TILE,y
        rts


; ===========================================================================
; Block objects (11 section 16)
; ===========================================================================

; ---------------------------------------------------------------------------
; draw_bumped_block: a bumped block, two rows of two sprites from its
; tiles, not mirrored (the original's mirror control is the attribute byte
; shifted right; the build checks it). Outside a ground area row 1 shows
; the row 2 tile. The used block (its metatile the used block's): one tile
; in its four mirror images, palette 3 in a ground area, else 1. Column 2
; off the screen hides s2, s4; column 1 s1, s3.
;
; In:       D = the block object's record; rel_x, rel_y, offscreen_bits of
;           REL_BLOCK; area_type
; Out:      s1-s4 of the block's sprite set
; Changes:  A, X, Y, the row variables
; Time:     290-400 cycles with the call
; Original: $EBD1-$EC52 (draw_bumped_block, with check_left_edge_bit $EC46)
; ---------------------------------------------------------------------------
draw_bumped_block:
.a8
.i8
        lda rel_y+REL_BLOCK
        sta sprite_row_y
        lda rel_x+REL_BLOCK
        sta sprite_row_attr_x+1
        lda bumped_block_attr
        sta sprite_row_attr_x
        stz sprite_row_mirror
        ldx Object::slot
        ldy sprite_offset+SPR_BLOCK-SLOT_BLOCK,x
        sty draw_first_sprite
        a16
        lda bumped_block_tiles
        jsr draw_sprite_pair
.a8
        a16
        lda bumped_block_tiles+POSE_ROW_BYTES
        jsr draw_sprite_pair
.a8
        ldy draw_first_sprite
        lda area_type
        cmp #AREA_GROUND
        beq @used
        lda block_upper_tile
        sta sprite_list+SPRITE_TILE,y
        sta sprite_list+SPRITE_ENTRY+SPRITE_TILE,y
@used:
        lda Object::block_metatile
        cmp used_block_metatile
        bne @offscreen
        lda used_block_tile
        iny                             ; SPRITE_TILE
        jsr set_four_sprite_y
        dey
        lda used_block_palette
        ldx area_type
        cpx #AREA_GROUND
        beq @palette
        lsr                             ; outside a ground area: palette 1
@palette:
        sta sprite_list+SPRITE_ATTR,y
        ora #ATTR_FLIP_X
        sta sprite_list+SPRITE_ENTRY+SPRITE_ATTR,y
        ora #ATTR_FLIP_Y
        sta sprite_list+3*SPRITE_ENTRY+SPRITE_ATTR,y
        and #ATTR_FLIP_Y | ATTR_PALETTE
        sta sprite_list+2*SPRITE_ENTRY+SPRITE_ATTR,y
@offscreen:
        lda offscreen_bits+REL_BLOCK
        and #OFFSCREEN_COLUMN_2
        beq @column_1
        lda #HIDDEN_Y
        sta sprite_list+SPRITE_ENTRY+SPRITE_Y,y
        sta sprite_list+3*SPRITE_ENTRY+SPRITE_Y,y
@column_1:
        lda offscreen_bits+REL_BLOCK
        and #OFFSCREEN_COLUMN_1
        beq @done
        lda #HIDDEN_Y
        sta sprite_list+SPRITE_Y,y
        sta sprite_list+2*SPRITE_ENTRY+SPRITE_Y,y
@done:
        rts

; ---------------------------------------------------------------------------
; draw_brick_pieces: the four pieces of a broken brick: s1, s2 the upper
; pair (the upper piece's place), s3, s4 the lower pair (the lower piece's
; place); each pair is a left piece and a right piece mirrored about the
; block's start. One tile and palette (another during the walk to the
; castle); the pieces spin each 4 frames (FC bit 2 the X flip, bit 3 the Y
; flip).
;
; The right piece's X, from O = (the block's start X - the screen's left
; pixel) mod 256 and the left piece's X L, in 8 bits with the original's
; two carries (leftover 4): c2 = 1 when O >= L; t = (O - L) + O + c2; c3 =
; the carry of t; R = t + 6 + c3. Column 1 of the upper piece off the
; screen hides s1, s3; its row 1 off hides s1, s2; a block in the right half
; of the screen whose right piece wrapped to the left (s1's X not below
; s2's) hides s2, s4. The lower piece has no row test (07 keeps its Y at
; $F0 or less).
;
; In:       D = the block object's record (the upper piece); rel_x, rel_y of
;           REL_BLOCK and REL_BLOCK + 1, offscreen_bits + REL_BLOCK;
;           player_task, screen_left
; Out:      s1-s4 of the block's sprite set
; Changes:  A, X, Y, brick_screen_origin, brick_draw_palette
; Time:     255-315 cycles with the call
; Original: $EC53-$ECDD (draw_brick_pieces, with check_left_edge_bit $EC46)
; ---------------------------------------------------------------------------
draw_brick_pieces:
.a8
.i8
        lda player_task
        cmp #PLAYER_TASK_END_LEVEL
        beq @walk
        lda brick_palette
        sta brick_draw_palette
        lda brick_tile
        bra @tiles
@walk:
        lda walk_brick_palette
        sta brick_draw_palette
        lda walk_brick_tile
@tiles:
        ldx Object::slot
        ldy sprite_offset+SPR_BLOCK-SLOT_BLOCK,x
        iny                             ; SPRITE_TILE
        jsr set_four_sprite_y
        lda frame_count
        asl
        asl
        asl
        asl                             ; BRICK_SPIN_SHIFT: FC bits 2, 3 to the flips
        and #ATTR_FLIP_X | ATTR_FLIP_Y
        ora brick_draw_palette
        iny                             ; SPRITE_ATTR
        jsr set_four_sprite_y
        dey
        dey
        lda rel_y+REL_BLOCK
        jsr set_two_sprite_y
        lda rel_x+REL_BLOCK
        sta sprite_list+SPRITE_X,y
        lda Object::block_origin_x
        sec
        sbc screen_left
        sta brick_screen_origin         ; O
        sec
        sbc rel_x+REL_BLOCK             ; O - L, the carry c2
        adc brick_screen_origin         ; + O + c2, the carry c3
        adc #BRICK_RIGHT_GAP            ; + 6 + c3
        sta sprite_list+SPRITE_ENTRY+SPRITE_X,y
        lda rel_y+REL_BLOCK+1
        sta sprite_list+2*SPRITE_ENTRY+SPRITE_Y,y
        sta sprite_list+3*SPRITE_ENTRY+SPRITE_Y,y
        lda rel_x+REL_BLOCK+1
        sta sprite_list+2*SPRITE_ENTRY+SPRITE_X,y
        lda brick_screen_origin
        sec
        sbc rel_x+REL_BLOCK+1
        adc brick_screen_origin
        adc #BRICK_RIGHT_GAP
        sta sprite_list+3*SPRITE_ENTRY+SPRITE_X,y
        lda offscreen_bits+REL_BLOCK
        and #OFFSCREEN_COLUMN_1
        beq @row_1
        lda #HIDDEN_Y
        sta sprite_list+SPRITE_Y,y
        sta sprite_list+2*SPRITE_ENTRY+SPRITE_Y,y
@row_1:
        lda offscreen_bits+REL_BLOCK
        bpl @wrapped                    ; OFFSCREEN_ROW_1: bit 7
        lda #HIDDEN_Y
        jsr set_two_sprite_y
@wrapped:
        lda brick_screen_origin
        bpl @done                       ; the block in the left half
        lda sprite_list+SPRITE_X,y
        cmp sprite_list+SPRITE_ENTRY+SPRITE_X,y
        bcc @done
        lda #HIDDEN_Y
        sta sprite_list+SPRITE_ENTRY+SPRITE_Y,y
        sta sprite_list+3*SPRITE_ENTRY+SPRITE_Y,y
@done:
        rts
.assert ATTR_FLIP_X = 1 << (2 + BRICK_SPIN_SHIFT) && ATTR_FLIP_Y = 1 << (3 + BRICK_SPIN_SHIFT), error, "draw_brick_pieces: FC bits 2 and 3 become the flips"


; ===========================================================================
; Fireballs, fire bar pieces, bursts, air bubbles (11 sections 17 and 18)
; ===========================================================================

; ---------------------------------------------------------------------------
; draw_player_fireball: a fireball of the player, its own sprite at its
; screen place, then its tile and attributes (draw_fire_piece_sprite, by
; the fall-through). Its routine (05a) draws it only while its offscreen
; bits and $CC are 0.
;
; In:       D = the fireball's record; rel_x, rel_y of REL_FIREBALL
; Out:      the fireball's sprite
; Changes:  A, X, Y
; Time:     70 cycles with the call
; Original: $ECDE-$ECEC (draw_player_fireball)
; ---------------------------------------------------------------------------
draw_player_fireball:
.a8
.i8
        ldx Object::slot
        ldy sprite_offset+SPR_FIREBALL-SLOT_FIREBALL,x
        lda rel_y+REL_FIREBALL
        sta sprite_list+SPRITE_Y,y
        lda rel_x+REL_FIREBALL
        sta sprite_list+SPRITE_X,y
; (falls into draw_fire_piece_sprite)

; ---------------------------------------------------------------------------
; draw_fire_piece_sprite: the tile and attributes of a fireball or of a
; fire bar's ball: the second tile while FC bit 2 is set (each 4 frames),
; flipped both ways while FC bit 3 is set (each 8 frames).
;
; In:       Y8 = the sprite's offset in sprite_list; D any
; Out:      the sprite's tile and attributes
; Changes:  A
; Keeps:    X, Y
; Time:     45 cycles with the call
; Original: $ECED-$ED05 (draw_fire_piece_sprite)
; ---------------------------------------------------------------------------
draw_fire_piece_sprite:
.a8
.i8
        lda frame_count
        lsr
        lsr                             ; FIRE_TILE_SHIFT: bit 2 to bit 0
        and #1
        eor fireball_tile               ; the first tile has bit 0 clear
        sta sprite_list+SPRITE_TILE,y
        lda frame_count
        and #FIRE_FLIP_FRAMES
        beq @upright
        lda #ATTR_FLIP_X | ATTR_FLIP_Y
@upright:
        ora fireball_attr
        sta sprite_list+SPRITE_ATTR,y
        rts
.assert FIRE_TILE_SHIFT = 2, error, "draw_fire_piece_sprite shifts twice"

; ---------------------------------------------------------------------------
; draw_fireball_burst: a fireball's burst (its state from $80 on), in the
; four sprites of the block set of its number: the state steps each frame;
; the steps 0, 0, 1, 1, 2, 2 ((the state before the step shr 1) and 7)
; draw, the 7th frame ends the fireball (state 0) with no draw.
;
; In:       D = the fireball's record; rel_x, rel_y of REL_FIREBALL
; Out:      s1-s4 of the block set; the fireball's state
; Changes:  A, X, Y
; Time:     170 cycles with the call; 30 on the burst's last frame
; Original: $ED09-$ED16 (draw_fireball_burst), $ED61-$ED65 (its end)
; ---------------------------------------------------------------------------
draw_fireball_burst:
.a8
.i8
        ldx Object::slot
        ldy sprite_offset+SPR_BLOCK-SLOT_FIREBALL,x
        lda Object::state
        inc Object::state
        lsr
        and #BURST_STEP_BITS
        cmp #BURST_STEPS
        bcc draw_firework_burst
        stz Object::state               ; the burst's end
        rts

; ---------------------------------------------------------------------------
; draw_firework_burst: one step of a burst: four sprites of one tile in its
; four mirror images, a 16 by 16 burst centred on the middle of the
; fireball's 8 by 8 place; no offscreen test (near the left edge X - 4
; wraps to the right edge, as in the original). The castle's fireworks
; (05b) first copy their place into the fireball group's bytes.
;
; In:       A8 = the step, 0-2; Y8 = the first sprite's offset; rel_x,
;           rel_y of REL_FIREBALL; D any
; Out:      s1-s4
; Changes:  A, X
; Keeps:    Y
; Time:     150 cycles with the call
; Original: $ED17-$ED60 (draw_firework_burst)
; ---------------------------------------------------------------------------
draw_firework_burst:
.a8
.i8
        tax
        lda burst_step_tiles,x
        iny                             ; SPRITE_TILE
        jsr set_four_sprite_y
        dey
        lda rel_y+REL_FIREBALL
        sec
        sbc #BURST_CENTRE
        sta sprite_list+SPRITE_Y,y
        sta sprite_list+2*SPRITE_ENTRY+SPRITE_Y,y
        clc
        adc #SPRITE_PIXELS
        sta sprite_list+SPRITE_ENTRY+SPRITE_Y,y
        sta sprite_list+3*SPRITE_ENTRY+SPRITE_Y,y
        lda rel_x+REL_FIREBALL
        sec
        sbc #BURST_CENTRE
        sta sprite_list+SPRITE_X,y
        sta sprite_list+SPRITE_ENTRY+SPRITE_X,y
        clc
        adc #SPRITE_PIXELS
        sta sprite_list+2*SPRITE_ENTRY+SPRITE_X,y
        sta sprite_list+3*SPRITE_ENTRY+SPRITE_X,y
        lda burst_attributes
        sta sprite_list+SPRITE_ATTR,y
        lda burst_attributes+1
        sta sprite_list+SPRITE_ENTRY+SPRITE_ATTR,y
        lda burst_attributes+2
        sta sprite_list+2*SPRITE_ENTRY+SPRITE_ATTR,y
        lda burst_attributes+3
        sta sprite_list+3*SPRITE_ENTRY+SPRITE_ATTR,y
        rts

; ---------------------------------------------------------------------------
; draw_air_bubble: an air bubble, its own sprite at its screen place; none
; while the player is not on the screen (his Y high not 1) or the bubble's
; column is off the screen.
;
; In:       D = the bubble's record; rel_x, rel_y, offscreen_bits of
;           REL_BUBBLE
; Out:      the bubble's sprite
; Changes:  A, X, Y
; Time:     15-65 cycles with the call
; Original: $EDE1-$EE06 (draw_air_bubble)
; ---------------------------------------------------------------------------
draw_air_bubble:
.a8
.i8
        lda player_object+Object::y_pos+1 ; the player's Y high
        cmp #Y_HIGH_SCREEN
        bne @done
        lda offscreen_bits+REL_BUBBLE
        and #OFFSCREEN_COLUMN_1
        bne @done
        ldx Object::slot
        ldy sprite_offset+SPR_BUBBLE-SLOT_BUBBLE,x
        lda rel_x+REL_BUBBLE
        sta sprite_list+SPRITE_X,y
        lda rel_y+REL_BUBBLE
        sta sprite_list+SPRITE_Y,y
        lda bubble_tile
        sta sprite_list+SPRITE_TILE,y
        lda bubble_attr
        sta sprite_list+SPRITE_ATTR,y
@done:
        rts
