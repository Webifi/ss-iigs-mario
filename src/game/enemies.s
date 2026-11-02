; Enemy behavior, including movement, attacks, lifts and boss sequences.
; movement.s calls the routine for each active enemy slot in game_core.
; These routines read and update the records in state.inc, call collision.s
; for hits and sprites.s for drawing, and use tables built by
; scripts/enemies_data.py. They also queue sounds, scores and screen changes.
;
; Ordinary enemies are drawn and tested before moving, so collisions use the
; position from the previous move. Frame timers advance each frame; slow
; timers advance every 21 frames. Positions contain a fractional byte and a
; two-byte position; vertical speed is a signed 8.8 word.
;
; A, X and Y are 8-bit unless a routine says otherwise. DBR is bank 0;
; D points to the active enemy record. Routines temporarily using another
; record restore D before returning.

.a8
.i8


; ---- Values of the enemies part ------------------------------
ERASED_ENEMIES  = 5             ; erase_all_enemies empties enemy slots 0-4: slot 5 stays
; Bounds (check_enemy_in_bounds; L8).
BOUND_LOW_KINDS = $49           ; the left bound's distance for kinds below the piranha plant (not 5)
BOUND_HIGH_KINDS = $48          ;   for kinds above it
BOUND_NEAR      = $10           ;   for the hammer brother and the piranha plant
BOUND_NEAR_WRAPPED = $10F       ;   for them when the screen's left pixel is BOUND_NEAR_WRAP_X or more
BOUND_NEAR_WRAP_X = $C7         ; from this left pixel on the original loses the carry of its + $39
BOUND_RIGHT     = $48           ; the right bound: the right edge + this + the carry of the left bound
; Walkers.
GOOMBA_ERASE_TIME = $0E         ; a flat goomba is erased when its slow timer reads this
FRAME_PARITY    = $01           ; frame_count bit 0
; The hammer brother.
HAMMER_LEFT_COLUMNS = OFFSCREEN_COLUMN_1 | OFFSCREEN_COLUMN_2 ; it throws only while both are on the screen
HAMMER_JUMP_LOW = $FD           ;   3 up
HAMMER_LOW_JUMP_Y = $70         ; above this row the low jump; from it to $7F a random one
HAMMER_SHORT_BLOCK = 0          ; t0 and the land block's index: the short block only
HAMMER_LONG_BLOCK = 1           ; t0: the long land block may be picked (in hard_mode_2)
HAMMER_NEXT_JUMP = $C0          ; the next jump in $C0-$FF frames: random+1+e OR this
HAMMER_SWAY_SPEED = 4           ; its sway: a quarter pixel a frame, 64 frames each way
HAMMER_SWAY_PHASE = $40         ; frame_count bit 6: the sway to the left
HAMMER_CHASE_SPEED = $F8        ; after its chase wait: half a pixel a frame left, to the player
; The podoboo.
LAVA_LEAP_FRACTION = $80        ; the leap's speed fraction: random+1+e OR this
LAVA_WAIT_BITS  = $0F           ; its wait: (random+1+e AND this) OR LAVA_WAIT_MIN slow ticks
LAVA_WAIT_MIN   = $06
LAVA_LEAP_SPEED = $F9           ; the leap's whole speed: 7 pixels a frame up, less the fraction
; The red paratroopa and the vertical lift at rest.
REST_SINK_FRAMES = $07          ; 1 pixel each 8 frames: frame_count AND this = 0
; The flying paratroopa.
GREEN_SWAY_MAXIMUM = $13        ; the X counters' maximum: one sway in 320 frames
FLY_BOB_FRAMES  = $03           ; it bobs 1 pixel each 4 frames: frame_count AND this = 0
FLY_BOB_PHASE   = $40           ; frame_count bit 6: down
; The X counters.
COUNTER_FRAMES  = $03           ; the counters step each 4 frames: frame_count AND this = 0
COUNTER_RIGHT   = $02           ; the primary counter's bit 1: the phases to the right
; The blooper.
SQUID_TOP_Y     = $20           ; it never rises above this row
SQUID_STROKE_SINK = $02         ; the stroke counter's bit 1: the sink
SQUID_STEP_FRAMES = $07         ; the stroke steps each 8 frames: frame_count AND this = 0
SQUID_TOP_SPEED = 2             ; the stroke's top speed, whole pixels a frame
SQUID_SINK_TICKS = 2            ; the sink's first part: 2 slow ticks
SQUID_SINK_MARGIN = $10         ; then it sinks while its Y + this (+ L1's carry) is above the player's
; The bullet bill of a wave.
BULLET_SPEED    = $E8           ; 1.5 pixels a frame left
; The swimming cheep-cheeps.
FISH_DRIFT_SLOTS = 2            ; enemy slots below this do not drift
FISH_DRIFT      = $20           ; the drift: 1/8 pixel a frame (Y fraction)
FISH_DRIFT_UP   = $00           ; cheep_move: drift up
FISH_DRIFT_DOWN = $10           ;   down (any value from this on)
FISH_SWING      = $0F           ; the drift turns this many pixels from the start Y
; The flying cheep-cheep.
FISH_PULL       = $0D           ; apply_vertical_move: the down pull, 1/256 pixel a frame per frame
FISH_TOP_SPEED  = 5             ;   the top speed
FISH_ARC_NEAR   = 8             ; within this many pixels of the arc byte the speed's fraction gets + FISH_ARC_NUDGE
FISH_ARC_NUDGE  = $10
; Lakitu.
CLOUD_LEAVE_SPEED = $10         ; when he leaves: 1 pixel a frame
CLOUD_FAR       = $3C           ; the distance limit; from it on he turns back
CLOUD_DISTANCE  = $3C           ; the distance's bits that count: / 4 gives 0-15
CLOUD_RUN_SPEED = $19           ; the player runs from this X speed on (an unsigned compare)
CLOUD_FAST_SCROLL = 2           ;   and the screen scrolls this much or more
CLOUD_LEFT      = 0             ; Object::lakitu_direction: he flies left; also the way to the player
CLOUD_RIGHT     = 1             ;   right
CLOUD_BASE_STILL = 0            ; the bases of cloud_distance_adjusts: the player still, or no scroll
; The piranha plant.
PIRANHA_NEAR    = $21           ; it stays in the pipe while the player is closer than this
PIRANHA_REST    = $40           ; the rest at each end: 64 frames
; The fire bars.
FIREBAR_ANGLE_MASK = $1F        ; the angle's high byte: 32 steps to a turn
FIREBAR_ANGLES  = FIREBAR_ANGLE_MASK + 1
FIREBAR_ANGLE_RIGHT = $08       ; the flat angles that a long bar skips
FIREBAR_ANGLE_LEFT = $18
FIREBAR_SHORT_BALLS = 5         ; the balls after the center: a short bar
FIREBAR_LONG_BALLS = 11         ;   a long bar
FIREBAR_SLOT_BALLS = 5          ; the balls in the bar's own sprites after the center; the rest are in duplicate_slot's
FIREBAR_BALL_BYTES = 2          ; a ball's X offset and Y offset
FIREBAR_REACH_BYTES = FIREBAR_LONG_BALLS * FIREBAR_BALL_BYTES ; one angle's block of fire_bar_pieces
FIREBAR_FAR_X   = $59           ; a ball this far from the center in X wrapped past a screen edge: hidden
FIRE_HIT_RANGE  = 8             ; a test point hits within this many pixels (Y and X)
FIRE_BALL_X_LIMIT = $F0         ; a ball from this screen X on is not tested
FIRE_PLAYER_CENTER = 4          ; the player's test X: his first sprite's X + this
FIRE_LOW_POINT  = $18           ; the test point of a small or crouching player: his Y + this
FIRE_TEST_POINTS = 2            ; the adders of fire_bar_y_adders: points 2 and 3
; Bowser.
BOWSER_GONE_Y   = $E0           ; a falling Bowser from this row on is gone
BOWSER_FACE_FRAMES = $0F        ; he faces left on frames where frame_count AND this = 0
BOWSER_FOLLOW_SPEED = 2         ; bowser_speed while he follows the player
BOWSER_FOLLOW_WAIT = $20        ; his jump timer and the breath timer while he follows
BOWSER_FOLLOW_LIMIT = $C8       ; he follows up to this X in the page
BOWSER_STEP_FRAMES = $03        ; he steps each 4 frames: frame_count AND this = 0
BOWSER_HAMMER_FRAMES = $03      ;   and tries a hammer each 4 frames
BOWSER_RANGE_PICK = $03         ; random+e AND this: one of the four bowser_range_choices
BOWSER_TURN_SPEED = 1           ; bowser_speed at the end of his range: + this, or - this
BOWSER_FLOOR_Y  = $80           ; from this row on he stands on the floor (he does not test the tiles)
BOWSER_JUMP_NOW = 1             ; his jump timer's value of the jump
BOWSER_JUMP_SPEED = $FE00       ; the jump's Y speed, signed 8.8: 2 pixels a frame up
BOWSER_MOUTH_FRAMES = $20       ; the mouth stays open 32 frames
BOWSER_HARD_GAP_CUT = $10       ; the flame gap is this much shorter in hard_mode_2
BOWSER_FLAME_STEPS = 8          ; the steps of the flame cycle (bowser_flame_gaps)
BOWSER_REAR_BEHIND = $10        ; the rear half: 16 pixels behind him
BOWSER_REAR_DROP = 8            ;   and 8 lower
BRIDGE_PIECE_FRAMES = 4         ; a bridge piece each 4 frames (bowser_feet on the bridge)
BRIDGE_PIECES   = 15            ; the axe, the chain, the 13 pieces (bridge_rows)
; Bowser's flame.
FLAME_STEP_FRACTION = $40       ; each frame 1 pixel and this fraction to the left: 1.25 pixels
FLAME_STEP_FRACTION_HARD = $60  ;   1.375 in hard_mode_2
FLAME_STEP_PIXELS = 1
FLAME_FLIP_FRAMES = $02         ; frame_count bit 1: the flipped attributes
FLAME_PARTS     = 3             ; its sprites, 8 pixels apart
FLAME_PART_WIDTH = 8
; The fireworks and the castle flag.
FIREWORK_BURST_STEPS = 3        ; a firework's burst frames; its end at the third step
FIREWORK_POINTS = 5             ; 500 points: digit_add + DIGIT_HUNDREDS
TIME_UNIT_POINTS = 5            ; 50 points: digit_add + DIGIT_TENS
TIME_UNIT_STEP  = $FF           ; digit_add + DIGIT_TENS: the time - 1
BONUS_TICK_FRAMES = $04         ; frame_count bit 2: the tick sound of the time bonus
STAR_FLAG_STEPS = 5             ; the castle flag's steps 0-4; at 5 the level ends
CASTLE_FLAG_TOP = $72           ; the flag rises while its Y is this or more (it stops at $71)
CASTLE_FLAG_WAIT = 6            ; the wait after the fireworks: 6 slow ticks
CASTLE_FLAG_SPRITES = 4
FIREWORKS_NONE  = $FF           ; fireworks_count: none
TIME_ONE_FIREWORK = 1           ; the time's last digit of 1 firework, 3 and 6
TIME_THREE_FIREWORKS = 3
TIME_SIX_FIREWORKS = 6
FIRST_FIREWORK_1 = 5            ; the flag's state: the first index into the firework places
FIRST_FIREWORK_3 = 3
FIRST_FIREWORK_6 = 0
; The lifts.
SCALE_LIFT_GONE = 3             ; a balance lift at Y high 3 is erased
SCALE_TOP_Y     = $2D           ; a balance lift at this row or above is at the top
SCALE_STOP_Y    = $2F           ;   and is put here
SCALE_DRAG      = $0005         ; nobody on the pair: its speed + this (1/256 pixel) for the test
SCALE_REST      = $000B         ;   below this the pair stops
SCALE_ROPE_BROKEN = 1           ; a balance lift's direction: the fall flag
FALL_STOPPED_ENEMY = 1          ; L7: the enemy whose speed stop_lifts clears at the rope's break
ROPE_LIST_ROOM  = $20           ; the ropes only while list 1 is shorter than this
ROPE_ORIGINAL_RECORD = 5        ; the original's rope record: 3 head bytes, 2 tiles (two of them: + 10)
ROPE_CELLS      = 2             ; the cells of a rope record
ROPE_X_SHIFT    = 8             ; the rope's column: the lift's X + this
ROPE_EASY_SHIFT = $10           ;   + this more without hard_mode_2 (with only this add's carry: L6)
ROPE_COLUMN_MASK = $F0          ; the 16-pixel column of that X
ROPE_RISE_ROW   = 8             ; a rising lift's rope row: its Y + this
ROPE_LOW_Y      = $E8           ; a lift from this row on: rows 30-31 become 28-29
ROPE_ROW_FOLD   = $02           ;   the row's bit 1 cleared (the original's low byte AND $BF)
ROPE_ROW_SHIFT  = 3             ; the cell row: the Y / 8
RIGHT_LIFT_SPEED = $10          ; the right-moving lift under the player: 1 pixel a frame
SIDE_LIFT_MAXIMUM = $0E         ; the side lift's X counters: one sway in 240 frames

.assert Object::y_pos = Object::y_fraction + 1, error, "move_lift_vertically: the Y fraction and row are one word"
.assert Object::x_pos = Object::x_fraction + 1, error, "fly_bowser_flame, swim_fish: the X fraction precedes x_pos"
.assert Object::kind = Object::active + 1, error, "clear_enemy_slot clears active and kind as one word"
.assert BRIDGE_ROWS_SIZE = BRIDGE_PIECES, lderror, "bridge_rows: one entry for each bridge piece"
.assert CASTLE_FLAG_TILES_SIZE = CASTLE_FLAG_SPRITES, lderror, "castle_flag_tiles: one entry for each sprite"
.assert FIRE_BAR_PIECES_SIZE = FIREBAR_ANGLES * FIREBAR_REACH_BYTES, lderror, "fire_bar_pieces: 32 angles of 11 balls"
.assert FIREBAR_REACH_BYTES = 22, error, "spin_and_draw_fire_bar multiplies the angle by 22"

; ---- This part's variables -------------------------------------------------
.segment "AREASTATE"
; ---- This part's variables (AREASTATE) -----------------------------
;
; Each is a temporary of one routine: written and read in the same call.
;
; | Name            | Size | Meaning                                       | Routine |
; |-----------------|------|-----------------------------------------------|---------|
; | bounds_left     | 2    | the left bound's distance, then the bound     | check_enemy_in_bounds |
; | bounds_right    | 2    | the right bound (world X)                     | check_enemy_in_bounds |
; | fire_bar_block  | 2    | 2 x the angle, for its block of fire_bar_pieces | spin_and_draw_fire_bar |
; | fire_bar_count  | 1    | the balls after the center: 5 or 11           | spin_and_draw_fire_bar |
; | fire_bar_piece  | 1    | the ball that draws, 0 to fire_bar_count - 1  | spin_and_draw_fire_bar, draw_fire_bar_pieces |
; | fire_bar_sprite | 1    | the sprite entry of the next ball             | the fire bar routines |
; | fire_ball_x     | 1    | the ball's sprite X                           | draw_fire_bar_pieces, check_fire_piece |
; | fire_ball_y     | 1    | the ball's sprite Y                           | draw_fire_bar_pieces, check_fire_piece |
; | fire_player_x   | 1    | the player's sprite X + 4                     | check_fire_piece |
; | fire_bar_reach  | 22   | the X and Y offsets of the 11 balls at this angle | the fire bar routines |
; | flame_columns   | 1    | the flame's offscreen bits, shifted out       | fly_bowser_flame |
;

bounds_left:    .res 2          ; check_enemy_in_bounds: the left bound's distance, then the left bound
bounds_right:   .res 2          ; check_enemy_in_bounds: the right bound
fire_bar_block: .res 2          ; spin_and_draw_fire_bar: 2 x the angle
fire_bar_count: .res 1          ; spin_and_draw_fire_bar: the balls after the center
fire_bar_piece: .res 1          ; the ball that draws (the original's t0)
fire_bar_sprite: .res 1         ; the sprite entry of the next ball (the original's t6 between balls)
fire_ball_x:    .res 1          ; the ball's sprite X (t6 in the test)
fire_ball_y:    .res 1          ; the ball's sprite Y (t7)
fire_player_x:  .res 1          ; check_fire_piece: the player's sprite X + 4 (t4)
fire_bar_reach: .res FIREBAR_REACH_BYTES ; the X and Y offsets of the balls at this frame's angle
flame_columns:  .res 1          ; fly_bowser_flame: the offscreen bits, shifted out
.segment "GAMEPLAY"

; ===========================================================================
; The common run routines
; ===========================================================================

; ---------------------------------------------------------------------------
; run_rescued_person: the mushroom retainer or the princess (kind $35), and
; each half of Bowser (draw_bowser_half): the offscreen bits, the screen
; place and the drawing. It does not move, is not tested here and is never
; erased by the bounds.
;
; In:       D = the record
; Out:      the slot's sprites
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 20 cycles and the three routines
; Original: $C8D7-$C8DF (run_rescued_person)
; ---------------------------------------------------------------------------
run_rescued_person:
.a8
.i8
        jsr check_enemy_offscreen ; offscreen_bits + REL_ENEMY
        jsr enemy_screen_position ; rel_x, rel_y + REL_ENEMY
        jmp draw_enemy ; the slot's six sprites

; ---------------------------------------------------------------------------
; run_ordinary_enemy: an enemy of kinds $00-$14 each frame: drawn and tested
; at its place of the frame before, then moved by its kind's rule (not
; during the hold), then the bounds (also during the hold).
;
; The drawing can erase the enemy (below the screen); the steps after it
; then see the empty slot, as in the original: its kind is 0, so its move is
; the walk of kind 0 at the X speed that the slot keeps. The kind is read
; for the move after the collisions, which can change it (a stomped
; paratroopa becomes a koopa). The attributes are cleared before the drawing
; reads them, so a move's writes to them have no effect.
;
; In:       D = the enemy's record
; Out:      the record moved; its sprites; the collisions' results
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 60 cycles and the routines it calls
; Original: $C8E0-$C904 (run_ordinary_enemy)
; ---------------------------------------------------------------------------
run_ordinary_enemy:
.a8
.i8
        stz Object::attributes          ; no extra attributes for the drawing
        jsr check_enemy_offscreen
        jsr enemy_screen_position
        jsr draw_enemy ; it ORs the attributes into the sprites
        jsr enemy_hit_box ; from the place drawn
        jsr check_enemy_vs_tiles ; landing, walls, ledges
        jsr enemies_bump_enemies
        jsr player_hits_enemy ; stomps, kicks, the player's injury
        lda timer_hold
        bne @bounds                     ; the hold: no move
        jsr move_enemy_by_kind
@bounds:
        jmp check_enemy_in_bounds

; ---- The tables (scripts/enemies_data.py, bank 0) --------------------------
;
; | Label                  | Entries, form                                  | Index | Original |
; |------------------------|------------------------------------------------|-------|----------|
; | hammer_throw_gaps      | 2: frames between throws                       | hard_mode_2 | $C9CE |
; | shell_air_slowdowns    | 2: signed X speed adders of a kicked shell in the air | 0 right, 1 left | $C9D0 entries 1, 3 |
; | revived_shell_speeds   | 4: signed X speeds of a revive                 | frame parity + 2 x hard_mode | $C9D4 |
; | hammer_jump_timers     | 2: frames before a jumping brother can land     | t0 AND random+2+e | $CA10 |
; | squid_rate_masks       | 2: masks on random+1+e for the aim             | hard_mode_2 | $CB87 |
; | swim_fish_x_speeds     | 2: the X fraction lost each frame              | kind - $0A | $CC46 |
; | fire_bar_pieces        | 32 angles x 11 balls x (X offset, Y offset), signed | 22 x angle + 2 x ball | $CCC7, $CD2A, $CD2E |
; | fire_bar_y_adders      | 2: the Y offsets of test points 2 and 3        | the point - 1 | $CD3A |
; | fish_arc_heights       | 16: screen Y values that nudge the arc         | the Y speed's fraction / 16 | $CED5 |
; | cloud_distance_adjusts | 3: Lakitu's speed bases                        | the base 0-2 | $CF25 |
; | bridge_rows            | 15: the ring row of the top left cell of each bridge piece's square | bridge_collapse | $CFDD, $D028 |
; | bridge_columns         | 15: its ring column (the code gives store_block_tiles their metatile place) | bridge_collapse | $CFDD |
; | bowser_range_choices   | 4: walk ranges (pixels), jump timers (frames)  | random+e AND 3 | $D061 |
; | bowser_flame_gaps      | 8: frames between flames                       | bowser_flame_timer | $D1D1 |
; | castle_flag_dy, castle_flag_dx, castle_flag_tiles | 4 each, in sprite order | the sprite 0-3 | $D2CD, $D2D1, $D2D5 |
; | bowser_flame_tile, bowser_flame_attr, bowser_flame_flipped_attr, castle_flag_attr, rope_left_tile, rope_right_tile, rope_blank_tile | 1 each | - | the operands of $D227, $D22B, $D233, $D37D, $D4EA, $D4EF, $D4F7 |
;
; The objects part's table bowser_flame_heights ($C59D, 4 bytes, by the
; flame's height number) gives a flame's target height.
;
; Original: $C8D7-$D6D8, but run_nothing ($C8D6, 05a).

; Merged: count_x_moves_green ($CB45) is the maximum's load in
; move_flying_paratroopa; turn_fire_bar ($D410) and the original's first
; and unused call of fire_bar_piece_offset (L3) are steps of
; spin_and_draw_fire_bar, and fire_bar_piece_offset is the build-time table
; fire_bar_pieces; hide_far_fire_piece ($CDE6) is a step of
; draw_fire_bar_pieces and compare_fire_piece ($CE32) of check_fire_piece;
; bowser_goto_flames ($D139) is a branch; draw_partner_rope ($D4FF) and
; finish_rope_record ($D530) are steps of move_partner_lift; store_lift_carry
; ($D628) is a step of shift_player_with_lift; carry_player_small_lift
; ($D671) is a step of move_small_lift. The port's own: scale_partner,
; place_player_on_lift. The original's second calls of
; check_enemy_offscreen and enemy_screen_position in run_bowser_fire, and
; its second enemy_screen_position in run_small_lift, give the same values
; as the first and are not made.
;

; ---------------------------------------------------------------------------
; move_enemy_by_kind: the move of kinds $00-$14, by the kind as it is after
; the collisions. The original's dispatch leaves the carry of its index
; shift (0) for the move; only move_squid reads it, and it computes that
; carry itself, so nothing reads a register from this jump.
;
; In:       D = the enemy's record; Object::kind $00-$14
; Out:      the kind's move
; Changes:  A, X, Y
; Original: $C905-$C934 (move_enemy_by_kind, move_nothing)
; ---------------------------------------------------------------------------
move_enemy_by_kind:
.a8
.i8
        lda Object::kind
        asl a
        tax
        jmp (.loword(ordinary_moves),x)
ordinary_moves:
        .addr move_ordinary_enemy       ; $00 green koopa
        .addr move_ordinary_enemy       ; $01 red koopa that walks off ledges
        .addr move_ordinary_enemy       ; $02 buzzy beetle
        .addr move_ordinary_enemy       ; $03 red koopa
        .addr move_ordinary_enemy       ; $04
        .addr drive_hammer_bro          ; $05 hammer brother
        .addr move_ordinary_enemy       ; $06 goomba
        .addr move_squid                ; $07 blooper
        .addr fly_bullet_bill           ; $08 bullet bill of a wave
        .addr move_nothing              ; $09
        .addr swim_fish                 ; $0A grey cheep-cheep
        .addr swim_fish                 ; $0B red cheep-cheep
        .addr move_lava_ball            ; $0C podoboo
        .addr bob_piranha               ; $0D piranha plant
        .addr move_leaper               ; $0E leaping green paratroopa
        .addr move_red_paratroopa       ; $0F red paratroopa
        .addr move_flying_paratroopa    ; $10 flying green paratroopa
        .addr move_cloud_rider          ; $11 Lakitu
        .addr move_ordinary_enemy       ; $12 spiny
        .addr move_nothing              ; $13
        .addr swoop_fish                ; $14 flying cheep-cheep
.assert * - ordinary_moves = 2 * (KIND_FLYING_CHEEP + 1), error, "ordinary_moves: one entry for each kind $00-$14"
move_nothing:
.a8
.i8
        rts

; ---------------------------------------------------------------------------
; run_bowser_fire: a flame of Bowser or of the flame wave (kind $15) each
; frame: its flight and its sprites (fly_bowser_flame, which also makes the
; offscreen bits and the screen place after the move), its test against the
; player at the place after this frame's move, and the bounds. A flame does
; not test the tiles or the other enemies: it flies through walls.
;
; In:       D = the flame's record
; Out:      the record; three sprites; the collision's results
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 30 cycles and the routines it calls
; Original: $C935-$C946 (run_bowser_fire)
; ---------------------------------------------------------------------------
run_bowser_fire:
.a8
.i8
        jsr fly_bowser_flame
        jsr enemy_hit_box
        jsr player_hits_enemy
        jmp check_enemy_in_bounds

; ---------------------------------------------------------------------------
; run_fire_bar: a fire bar (kinds $1B-$22) each frame: its turn, its balls
; and their test (spin_and_draw_fire_bar), then the bounds.
;
; In:       D = the fire bar's record
; Out:      the record; the balls' sprites; a hurt player
; Changes:  A, X, Y
; Keeps:    D
; Time:     the two routines
; Original: $C947-$C94C (run_fire_bar)
; ---------------------------------------------------------------------------
run_fire_bar:
.a8
.i8
        jsr spin_and_draw_fire_bar
        jmp check_enemy_in_bounds

; ---------------------------------------------------------------------------
; run_small_lift: a small lift of a lift line (kinds $2B, $2C) each frame:
; its box and the player's place on it, its drawing, then its move and
; the player carried, then the bounds. The lift is drawn before it moves.
; The original takes the screen place a second time before the drawing; the
; hit test writes only the box and the player, so the first place serves.
;
; In:       D = the lift's record
; Out:      the record; its sprites; the player on it
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 30 cycles and the routines it calls
; Original: $C94D-$C964 (run_small_lift)
; ---------------------------------------------------------------------------
run_small_lift:
.a8
.i8
        jsr check_enemy_offscreen
        jsr enemy_screen_position
        jsr small_lift_hit_box
        jsr small_lift_hit_test ; Object::on_lift = 0, or the box he stands on
        jsr draw_small_lift_sprites ; the lift and its copy 128 lines lower
        jsr move_small_lift
        jmp check_enemy_in_bounds

; ---------------------------------------------------------------------------
; run_large_lift: a large lift (kinds $24-$2A) each frame: its box and the
; player's place on it, then, when the timers run, the move of its
; kind and its screen place after the move, then its drawing and the
; bounds. The lift moves before it is drawn.
;
; In:       D = the lift's record
; Out:      the record; its sprites; the player on it
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 40 cycles and the routines it calls
; Original: $C965-$C981 (run_large_lift)
; ---------------------------------------------------------------------------
run_large_lift:
.a8
.i8
        jsr check_enemy_offscreen
        jsr enemy_screen_position
        jsr large_lift_hit_box
        jsr big_lift_hit_test ; Object::on_lift = $FF, or the lift he stands on
        lda timer_hold
        bne @draw                       ; the hold: no move, the place stays
        jsr large_lift_steps
        jsr enemy_screen_position       ; the place after the move
@draw:
        jsr draw_big_lift
        jmp check_enemy_in_bounds

; ---------------------------------------------------------------------------
; large_lift_steps: the move of a large lift's kind.
;
; In:       D = the lift's record; Object::kind $24-$2A
; Out:      the kind's move
; Changes:  A, X, Y
; Original: $C982-$C997 (large_lift_steps)
; ---------------------------------------------------------------------------
large_lift_steps:
.a8
.i8
        lda Object::kind
        sec
        sbc #KIND_BALANCE_LIFT
        asl a
        tax
        jmp (.loword(large_lift_moves),x)
large_lift_moves:
        .addr run_scale_lift            ; $24 a balance lift
        .addr run_vertical_lift         ; $25 up and down
        .addr move_big_lift             ; $26 a lift line, going up
        .addr move_big_lift             ; $27 a lift line, going down
        .addr run_horizontal_lift       ; $28 sways sideways
        .addr run_drop_lift             ; $29 drops under the player
        .addr run_right_lift            ; $2A moves right under the player

; ---------------------------------------------------------------------------
; clear_enemy_slot: an enemy slot empty: its active flag, kind, state, score
; number, slow timer, shell chain, attributes and frame timer become 0.
; The place, the speeds and the other fields stay: the
; slot's next object keeps them. For enemy 5 the frame
; timer is the wave timer. The original returns A = 0; this one
; keeps A, and its callers store their own 0.
;
; In:       D = the enemy's record
; Out:      the slot empty; X = Object::slot
; Changes:  X
; Keeps:    A, Y, D
; Time:     about 45 cycles
; Original: $C998-$C9AF (clear_enemy_slot)
; ---------------------------------------------------------------------------
clear_enemy_slot:
.a8
.i8
        rep #P_M8
.a16
        stz Object::active              ; active and kind: the slot is free
        sep #P_M8
.a8
        stz Object::state
        stz Object::score_kind          ; no score number
        stz Object::shell_chain
        stz Object::attributes
        ldx Object::slot
        stz timers + TIMER_ENEMY_INTERVAL - SLOT_ENEMY,x
        stz timers + TIMER_ENEMY_FRAME - SLOT_ENEMY,x
        rts

; ---------------------------------------------------------------------------
; erase_all_enemies: enemy slots 4 down to 0 empty (not slot 5), and no
; wave. The callers: bridge_collapse_task, bowser_actions, and the loop
; check of a maze castle (read_enemy_spawns) when the player takes a
; wrong path.
;
; In:       any D
; Out:      enemy slots 0-4 empty (clear_enemy_slot); frenzy_kind = 0
; Changes:  A, X
; Keeps:    Y, D
; Time:     about 380 cycles
; Original: $D071-$D07E (erase_all_enemies)
; ---------------------------------------------------------------------------
erase_all_enemies:
.a8
.i8
        phd
        ldx #SLOT_ENEMY + ERASED_ENEMIES - 1 ; enemy 4, then down to enemy 0
@slot:
        object_from_x
        jsr clear_enemy_slot            ; X = the slot again
        dex
        cpx #SLOT_ENEMY
        bcs @slot
        pld
        stz frenzy_kind
        rts

; ---------------------------------------------------------------------------
; check_enemy_in_bounds: the erase of an enemy far left or far right of the
; screen. Kind $14 (the flying cheep-cheep) is never erased
; here. The bounds are world X words from the screen's edges; the X
; compares take the sign of the 16-bit difference (bit 15, the original's
; page difference's sign bit), so they hold for differences of less than
; 128 pages.
;
; The distances of the left bound are the original's sums with the carries
; of its compares: $49 for kinds below the piranha plant ($0D) but the
; hammer brother, $48 above; $10 for the hammer brother and the piranha
; plant, or $10F when the screen's left pixel is $C7 or more, where the
; original loses the carry of its + $39 and the bound is a page further
; left. The right bound is the right edge + $48 + the carry of the left
; bound's subtract: + $49, or + $48 when the left bound is below world X 0.
;
; At or past the right bound an object stays when its whole state byte is 5
; (a spiny's egg, or any object with state 5), or it is the piranha plant,
; the flagpole flag, the castle flag or the jump spring (the two flags never
; come here). Else it is erased.
;
; In:       D = the enemy's record
; Out:      the slot erased (clear_enemy_slot), or kept
; Changes:  A, X; bounds_left, bounds_right
; Keeps:    Y, D
; Time:     about 110 cycles
; Original: $D67A-$D6D5 (check_enemy_in_bounds); callers also run_jump_spring,
;           the cannon bullet and the power-up
; ---------------------------------------------------------------------------
check_enemy_in_bounds:
.a8
.i8
        lda Object::kind
        cmp #KIND_FLYING_CHEEP
        beq @keep
; The left bound's distance by the kind.
        cmp #KIND_HAMMER_BRO
        beq @near
        cmp #KIND_PIRANHA
        beq @near
        rep #P_M8                       ; (the carry of the compare stays)
.a16
        lda #BOUND_LOW_KINDS
        bcc @distance                   ; a kind below the piranha plant
        lda #BOUND_HIGH_KINDS
        bra @distance
@near:
.a8
        lda screen_left                 ; the left edge's pixel
        cmp #BOUND_NEAR_WRAP_X
        rep #P_M8
.a16
        lda #BOUND_NEAR
        bcc @distance
        lda #BOUND_NEAR_WRAPPED         ; L8
@distance:
; The bounds: the left edge - the distance; the right edge + $48 + the
; carry of that subtract.
        sta bounds_left
        lda screen_left
        sec
        sbc bounds_left
        sta bounds_left                 ; carry clear: below world X 0
        lda screen_right
        adc #BOUND_RIGHT
        sta bounds_right
; Left of the left bound: erased. Left of the right bound: kept.
        lda Object::x_pos
        sec
        sbc bounds_left
        bmi @erase
        lda Object::x_pos
        sec
        sbc bounds_right
        sep #P_M8                       ; (the sign of the subtract stays)
.a8
        bmi @keep
; At or past the right bound: kept by its state or its kind.
        lda Object::state
        cmp #ENEMY_SPINY_EGG
        beq @keep
        lda Object::kind
        cmp #KIND_PIRANHA
        beq @keep
        cmp #KIND_FLAG
        beq @keep
        cmp #KIND_STAR_FLAG
        beq @keep
        cmp #KIND_SPRING
        beq @keep
        jmp clear_enemy_slot
@erase:
.a16
        sep #P_M8
.a8
        jmp clear_enemy_slot
@keep:
.a8
        rts

; ===========================================================================
; The walkers and their kin (19, 20)
; ===========================================================================

; ---------------------------------------------------------------------------
; move_lava_ball: the podoboo (kind $0C). While its slow timer runs it flies
; (move_leaper_vertically: pull $1C, top 3 down): up from below the screen,
; back below it, and it waits there. When the timer ends it starts again
; below the screen (start_lava_ball) with a new leap: Y speed $F9 + a
; fraction of $80-$FF (about 6.5 to 6 pixels a frame up) and a new wait of
; 6, 7, 14 or 15 slow ticks. It has no X move.
;
; In:       D = the podoboo's record
; Out:      the record
; Changes:  A, X, Y
; Time:     about 15 cycles, 60 at a new leap, and the routines it calls
; Original: $C9B0-$C9CD (move_lava_ball)
; ---------------------------------------------------------------------------
move_lava_ball:
.a8
.i8
        ldx Object::slot
        lda timers + TIMER_ENEMY_INTERVAL - SLOT_ENEMY,x
        bne @fly
        jsr start_lava_ball ; below the screen, still, state 0, box 9, direction 2
        ldx Object::slot
        lda random + 1 - SLOT_ENEMY,x
        ora #LAVA_LEAP_FRACTION
        sta Object::y_speed_fraction
        and #LAVA_WAIT_BITS
        ora #LAVA_WAIT_MIN
        sta timers + TIMER_ENEMY_INTERVAL - SLOT_ENEMY,x
        lda #LAVA_LEAP_SPEED
        sta Object::y_speed_whole
@fly:
        jmp move_leaper_vertically

; ---------------------------------------------------------------------------
; drive_hammer_bro: the hammer brother (kind $05) each frame.
; A defeated brother falls. While its jump timer runs (it counts down here,
; 1 a frame) it throws: each hammer_throw_gaps + 1 frames (49, or 29 in
; hard_mode_2) while its left 16 pixels are on the screen; a throw that
; finds no free misc slot tries again 1 frame sooner. When the jump timer is
; 0 and it stands on the ground it jumps: from the lower half (row $80 on)
; the high jump, above row $70 the low jump, between them a random one.
; Then it sways and faces the player (walk_hammer_bro).
;
; In:       D = the brother's record
; Out:      the record; a hammer started (throw_hammer)
; Changes:  A, X, Y
; Time:     about 60 cycles and the routines it calls
; Original: $C9D8-$CA36 (drive_hammer_bro)
; ---------------------------------------------------------------------------
drive_hammer_bro:
.a8
.i8
        lda Object::state
        and #ENEMY_DEFEATED
        beq @alive
        jmp drop_defeated_enemy
@alive:
        lda Object::jump_timer
        beq @jump
        dec Object::jump_timer
; The throw.
        lda offscreen_bits + REL_ENEMY
        and #HAMMER_LEFT_COLUMNS
        bne walk_hammer_bro             ; its left 16 pixels are not all on the screen
        lda Object::hammer_timer
        bne @count
        ldy hard_mode_2
        lda hammer_throw_gaps,y
        sta Object::hammer_timer
        jsr throw_hammer ; carry set when a hammer started
        bcc @count
        lda #HAMMER_BRO_THROWING
        tsb Object::state               ; the throw pose (sprite code draws the hammer up)
        bra walk_hammer_bro
@count:
        dec Object::hammer_timer
        bra walk_hammer_bro
; The jump, when it stands on the ground.
@jump:
        lda Object::state
        and #ENEMY_STATE_BITS
        cmp #ENEMY_FALLING
        beq walk_hammer_bro
        ldx #HAMMER_SHORT_BLOCK         ; t0
        lda Object::y_pos
        bmi @high                       ; the lower half of the screen
        cmp #HAMMER_LOW_JUMP_Y
        bcs @random
        ldx #HAMMER_LONG_BLOCK          ; above $70: the low jump, and the long block may come
        bra @low
@random:
        ldy Object::slot
        lda random + 1 - SLOT_ENEMY,y
        lsr a
        bcs @low                        ; bit 0 of random+1+e: the low jump
@high:
        lda #HAMMER_JUMP_HIGH
        bra launch_hammer_bro_jump
@low:
        lda #HAMMER_JUMP_LOW
        ; runs on into launch_hammer_bro_jump

; ---------------------------------------------------------------------------
; launch_hammer_bro_jump: a hammer brother's jump starts: its Y speed, the
; state's air bit, the frames before it can land (its frame timer: collision code lets
; it land only when this is 0, so it passes through the bricks meanwhile:
; $20, or $37 when t0 AND random+2+e picks it in hard_mode_2), and its next
; jump in $C0-$FF frames. Then its walk (walk_hammer_bro). The collision
; part enters here when the brother meets a wall (bump_or_hammer_jump:
; A = HAMMER_JUMP_HIGH, X = HAMMER_SHORT_BLOCK).
;
; In:       D = the brother's record; A8 = the jump's Y speed, whole pixels
;           (HAMMER_JUMP_HIGH or HAMMER_JUMP_LOW); X8 = t0: HAMMER_LONG_BLOCK
;           when the long land block may come, else HAMMER_SHORT_BLOCK
; Out:      the record (y_speed_whole; the fraction stays), the jump timers
; Changes:  A, X, Y
; Time:     about 50 cycles and walk_hammer_bro
; Original: $CA37-$CA57 (launch_hammer_bro_jump)
; ---------------------------------------------------------------------------
launch_hammer_bro_jump:
.a8
.i8
        sta Object::y_speed_whole
        lda #ENEMY_FALLING
        tsb Object::state
        txa
        ldx Object::slot
        and random + 2 - SLOT_ENEMY,x   ; t0 AND random+2+e
        ldy hard_mode_2
        bne @land_block
        lda #HAMMER_SHORT_BLOCK         ; the short block only
@land_block:
        tay
        lda hammer_jump_timers,y
        sta timers + TIMER_ENEMY_FRAME - SLOT_ENEMY,x
        lda random + 1 - SLOT_ENEMY,x
        ora #HAMMER_NEXT_JUMP
        sta Object::jump_timer
        ; runs on into walk_hammer_bro

; ---------------------------------------------------------------------------
; walk_hammer_bro: the hammer brother's walk: a sway of 4 units each way,
; 64 frames each (frame_count bit 6); it faces the player, and when it is at
; or right of him and its chase wait (its slow timer from the start, $80 or
; $50 slow ticks) has ended, it walks to him at half a pixel a frame. Then
; its move (move_ordinary_enemy: in a jump, pull $3D, top 3).
;
; In:       D = the brother's record
; Out:      the record moved
; Changes:  A, X, Y
; Time:     about 45 cycles and move_ordinary_enemy
; Original: $CA58-$CA76 (walk_hammer_bro)
; ---------------------------------------------------------------------------
walk_hammer_bro:
.a8
.i8
        ldy #HAMMER_SWAY_SPEED
        lda frame_count
        and #HAMMER_SWAY_PHASE
        beq @sway
        ldy #<-HAMMER_SWAY_SPEED
@sway:
        sty Object::x_speed
; It faces the player: the sign of its X - his X (player_enemy_gap).
        ldy #FACING_RIGHT
        rep #P_M8
.a16
        lda Object::x_pos
        sec
        sbc player_object + Object::x_pos
        sep #P_M8                       ; (the sign of the subtract stays)
.a8
        bmi @face                       ; left of the player: it faces right
        ldy #FACING_LEFT
        ldx Object::slot
        lda timers + TIMER_ENEMY_INTERVAL - SLOT_ENEMY,x
        bne @face
        lda #HAMMER_CHASE_SPEED
        sta Object::x_speed
@face:
        sty Object::direction
        ; runs on into move_ordinary_enemy

; ---- The state byte of the walking enemies (Object::state) --
;
; | Bits          | Meaning                                       | Set by |
; |---------------|-----------------------------------------------|--------|
; | 7             | a kicked shell (or the power-up's move)       | collision code, object code |
; | 6             | a bit-7 object in the air                     | collision code |
; | 5             | defeated: it falls off the screen             | collision code |
; | 3             | the hammer brother shows its throw            | drive_hammer_bro; run_hammer (object code) clears it |
; | 0-2 = 0       | walking                                       | object code, the revive here |
; | 0-2 = 1       | in the air (a hammer brother's jump: bit 0)   | collision code, launch_hammer_bro_jump |
; | 0-2 = 2       | knocked up by a block: falls at its full speed | collision code |
; | 0-2 = 3       | stunned after a knock                         | collision code |
; | 0-2 = 4       | stomped: a shell, or a flat goomba            | collision code |
; | 0-2 = 5       | a spiny's egg                                 | object code |
;
; | State of a walker | Each frame (move_ordinary_enemy)            | Leaves when |
; |-------------------|---------------------------------------------|-------------|
; | walking           | moves by its X speed                        | collision code changes it |
; | in the air (1, 2) | falls (drop_enemy_fast) at its X speed       | collision code lands it |
; | stunned, stomped  | still                                       | its slow timer ends: walks at 8 (12 in hard_mode) units |
; | flat goomba       | still                                       | its slow timer reads $0E: erased |
; | kicked shell      | its X speed; in the air 24 units slower      | collision code |
; | defeated          | falls at its X speed                        | the drawing erases it below the screen (sprite code) |
; | spiny's egg       | falls (pull $20) at its X speed             | collision code makes it a spiny when it lands |
;

; ---------------------------------------------------------------------------
; move_ordinary_enemy: the move of a walker by its state. It handles kinds
; $00-$04, $06 and $12, the end of the
; hammer brother's move, and the power-up's. In the air (bit 6, or
; motion 1, 2 or 5) it falls with drop_enemy_fast (pull $3D, $20 for an egg;
; top 3) and moves at its X speed; a kicked shell in the air moves 24 units
; slower (shell_air_slowdowns, by the sign of its speed; the X speed is put
; back after the move). The power-up in the air moves at its full speed. A
; stunned or stomped enemy waits for its slow timer, then walks again at
; revived_shell_speeds in a direction from the frame's parity, with no move
; in that frame; a flat goomba is erased when its timer reads $0E (so a
; goomba stomped in hard_mode, timer $0B, walks again).
;
; In:       D = the enemy's record
; Out:      the record moved
; Changes:  A, X, Y
; Time:     about 40 cycles and the routines it calls
; Original: $CA77-$CAE4, $CAEB-$CAF8 (move_ordinary_enemy)
; ---------------------------------------------------------------------------
move_ordinary_enemy:
.a8
.i8
        lda Object::state
        bit #ENEMY_DROP
        bne @fall
        bit #ENEMY_KICKED
        bne @walk                       ; a kicked shell on the ground: its full speed
        bit #ENEMY_DEFEATED
        bne drop_defeated_enemy
        and #ENEMY_STATE_BITS
        beq @walk
        cmp #ENEMY_SPINY_EGG
        beq @fall
        cmp #ENEMY_UPSIDE_DOWN
        bcs @stunned                    ; 3, 4, 6, 7
@fall:
        jsr drop_enemy_fast ; pull $3D ($20 for state 5), top 3 down
        lda Object::state
        cmp #ENEMY_FLIPPED
        beq @walk                       ; knocked up: its full speed
        and #ENEMY_DROP
        beq @walk
        lda Object::kind
        cmp #KIND_POWERUP
        beq @walk
; A kicked shell in the air: its speed 24 units nearer 0 for the move.
        lda Object::x_speed
        pha
        bmi @left
        clc
        adc shell_air_slowdowns         ; a speed to the right
        bra @slowed
@left:
        clc
        adc shell_air_slowdowns+1       ; a speed to the left
@slowed:
        sta Object::x_speed
        jsr move_enemy_sideways
        pla
        sta Object::x_speed
        rts
@walk:
        jmp move_enemy_sideways ; X + the X speed
; Stunned or stomped: the revive when the slow timer ends.
@stunned:
        ldx Object::slot
        lda timers + TIMER_ENEMY_INTERVAL - SLOT_ENEMY,x
        bne @waits
        stz Object::state               ; it walks again
        lda frame_count
        and #FRAME_PARITY
        tay                             ; d: 0 on even frames, 1 on odd frames
        clc
        adc #FACING_RIGHT
        sta Object::direction           ; right on even frames, left on odd ones
        lda hard_mode
        beq @speed
        iny
        iny                             ; the hard_mode speeds
@speed:
        lda revived_shell_speeds,y
        sta Object::x_speed
        rts
@waits:
        cmp #GOOMBA_ERASE_TIME
        bne @still
        lda Object::kind
        cmp #KIND_GOOMBA
        bne @still
        jmp clear_enemy_slot
@still:
        rts

; ---------------------------------------------------------------------------
; drop_defeated_enemy: a defeated enemy falls (drop_enemy_fast) and moves at
; its X speed.
;
; In:       D = the enemy's record
; Out:      the record moved
; Changes:  A, X, Y
; Time:     the two moves
; Original: $CAE5-$CAEA (drop_defeated_enemy)
; ---------------------------------------------------------------------------
drop_defeated_enemy:
.a8
.i8
        jsr drop_enemy_fast
        jmp move_enemy_sideways

; ---------------------------------------------------------------------------
; move_leaper: the leaping green paratroopa (kind $0E), and the star:
; move_leaper_vertically (pull $1C, top 3 down), then the move at its X
; speed. collision code gives it Y speed $FD each time it lands: it bounces.
;
; In:       D = the record
; Out:      the record moved
; Changes:  A, X, Y
; Time:     the two moves
; Original: $CAF9-$CAFE (move_leaper)
; ---------------------------------------------------------------------------
move_leaper:
.a8
.i8
        jsr move_leaper_vertically
        jmp move_enemy_sideways

; ---------------------------------------------------------------------------
; move_red_paratroopa: the red paratroopa (kind $0F) swings up and down
; around its middle Y (paratroopa_middle_y): above it red_paratroopa_down
; (pull 3, top 2), from it on red_paratroopa_up (net 3 up, top 2). The rest
; rule, only when both bytes of its Y speed are 0 at once: the Y fraction
; 0, and above its start Y it sinks 1 pixel each 8 frames. No X move.
;
; In:       D = the paratroopa's record
; Out:      the record moved
; Changes:  A, X, Y
; Time:     about 30 cycles and the routines it calls
; Original: $CAFF-$CB24 (move_red_paratroopa)
; ---------------------------------------------------------------------------
move_red_paratroopa:
.a8
.i8
        rep #P_M8
.a16
        lda Object::y_speed
        sep #P_M8                       ; (the zero flag of the word stays)
.a8
        bne @swing
        stz Object::y_fraction
        lda Object::y_pos
        cmp Object::paratroopa_start_y
        bcs @swing
        lda frame_count
        and #REST_SINK_FRAMES
        bne @rest
        inc Object::y_pos               ; the row only, as the original's 8-bit add
@rest:
        rts
@swing:
        lda Object::y_pos
        cmp Object::paratroopa_middle_y
        bcc @down
        jmp red_paratroopa_up
@down:
        jmp red_paratroopa_down

; ---------------------------------------------------------------------------
; move_flying_paratroopa: the flying green paratroopa (kind $10): its sway
; by the X counters (maximum $13: up to 19/16 pixel a frame, one sway in 320
; frames), and a bob of 1 pixel each 4 frames: 16 pixels down in 64 frames,
; 16 up in the next 64 (frame_count bit 6).
;
; In:       D = the paratroopa's record
; Out:      the record moved
; Changes:  A, X, Y
; Time:     about 30 cycles and the routines it calls
; Original: $CB25-$CB46 (move_flying_paratroopa, count_x_moves_green)
; ---------------------------------------------------------------------------
move_flying_paratroopa:
.a8
.i8
        lda #GREEN_SWAY_MAXIMUM
        jsr count_x_moves
        jsr move_by_counters
        lda frame_count
        bit #FLY_BOB_FRAMES
        bne @done
        and #FLY_BOB_PHASE
        beq @up
        inc Object::y_pos               ; the row only
        rts
@up:
        dec Object::y_pos
@done:
        rts

; ---------------------------------------------------------------------------
; count_x_moves: the X counters of a swaying object (the flying paratroopa,
; the side lift), on frames where frame_count AND 3 = 0: in an even phase of
; the primary counter the secondary counter runs up to the maximum, in an
; odd phase down to 0; at either end the primary counter steps instead. So
; each change of direction takes one step more; the primary counter wraps
; at 256 and only its bits 0-1 count.
;
; In:       D = the object's record; A8 = the maximum
; Out:      Object::counter_minor, Object::counter_major
; Changes:  A, Y
; Time:     about 30 cycles
; Original: $CB47-$CB65 (count_x_moves)
; ---------------------------------------------------------------------------
count_x_moves:
.a8
.i8
        tay                             ; Y = the maximum
        lda frame_count
        and #COUNTER_FRAMES
        bne @done
        lda Object::counter_major
        lsr a
        bcs @down                       ; an odd phase
        tya
        cmp Object::counter_minor
        beq @phase                      ; at the maximum
        inc Object::counter_minor
        rts
@down:
        lda Object::counter_minor
        beq @phase                      ; at 0
        dec Object::counter_minor
        rts
@phase:
        inc Object::counter_major
@done:
        rts

; ---------------------------------------------------------------------------
; move_by_counters: the sideways move by the X counters: in the primary
; counter's phases 2 and 3 to the right at the secondary counter's speed,
; in phases 0 and 1 to the left at its negative; the secondary counter (the
; X speed byte) is put back after the move. So the object speeds up and
; slows down to the left, then to the right.
;
; In:       D = the object's record
; Out:      A8 = the whole pixels moved, signed (move_enemy_sideways); the
;           record moved; Object::direction
; Changes:  A, X, Y
; Time:     about 40 cycles and move_enemy_sideways
; Original: $CB66-$CB86 (move_by_counters)
; ---------------------------------------------------------------------------
move_by_counters:
.a8
.i8
        lda Object::counter_minor
        pha                             ; the counter, back after the move
        ldy #FACING_RIGHT
        lda Object::counter_major
        and #COUNTER_RIGHT
        bne @move                       ; phases 2, 3: the counter is the speed
        lda Object::counter_minor
        eor #$FF
        inc a
        sta Object::x_speed             ; phases 0, 1: its negative
        ldy #FACING_LEFT
@move:
        sty Object::direction
        jsr move_enemy_sideways
        tay                             ; the pixels moved
        pla
        sta Object::counter_minor
        tya
        rts

; ---------------------------------------------------------------------------
; move_squid: the blooper (kind $07). A defeated blooper
; sinks (move_enemy_slowly: pull $0F, top 2), with no X move. Else it may
; aim: on frames where random+1+e AND squid_rate_masks[hard_mode_2] is 0
; (about 1 frame in 64, or 1 in 4 in hard_mode_2), in an odd enemy slot it
; takes the player's facing, in an even slot it faces the player. Then its
; stroke (swim_squid), its rise (its Y - Object::squid_rise, kept only from row $20
; on: it never rises above it), and its swim: Object::squid_swim_speed pixels
; sideways in its direction, with the carry into the page.
;
; L1: the original's sink test in swim_squid adds the carry that this code
; leaves: 1 on an aim frame in an odd slot, and in an even slot the carry of
; the gap's subtract (the blooper's X at or right of the player's, unsigned);
; 0 on other frames. The port computes that value (c) and gives it to
; swim_squid.
;
; In:       D = the blooper's record
; Out:      the record moved
; Changes:  A, X, Y
; Time:     about 70 cycles and swim_squid
; Original: $CB89-$CBDE (move_squid)
; ---------------------------------------------------------------------------
move_squid:
.a8
.i8
        lda Object::state
        and #ENEMY_DEFEATED
        beq @alive
        jmp move_enemy_slowly
@alive:
; The aim.
        ldy #0                          ; c: no aim
        ldx Object::slot
        lda random + 1 - SLOT_ENEMY,x
        ldx hard_mode_2
        and squid_rate_masks,x
        bne @stroke
        lda Object::slot
        sec
        sbc #SLOT_ENEMY                 ; the enemy number
        lsr a
        bcc @even
        lda player_object + Object::direction ; an odd slot: the player's facing
        sta Object::direction
        iny                             ; c = 1
        bra @stroke
@even:
        ldx #FACING_LEFT
        rep #P_M8
.a16
        lda Object::x_pos
        cmp player_object + Object::x_pos ; its X - his X (player_enemy_gap)
        sep #P_M8                       ; (the flags of the compare stay)
.a8
        bpl @face                       ; at or right of the player: it faces left
        ldx #FACING_RIGHT
@face:
        stx Object::direction
        bcc @stroke                     ; c = the compare's carry: X at or right of his, unsigned
        iny
@stroke:
        jsr swim_squid
; The rise, not above row $20.
        lda Object::y_pos
        sec
        sbc Object::squid_rise
        cmp #SQUID_TOP_Y
        bcc @swim
        sta Object::y_pos               ; the row only
; The swim, with the carry or the borrow into the page.
@swim:
        rep #P_M8
.a16
        lda Object::squid_swim_speed
        and #$00FF                      ; the speed byte alone (the next byte is the rise)
        ldx Object::direction
        cpx #FACING_RIGHT
        bne @to_left
        clc
        adc Object::x_pos
        sta Object::x_pos
        sep #P_M8
.a8
        rts
@to_left:
.a16
        eor #$FFFF                      ; X - the speed: the complement + X + 1
        sec
        adc Object::x_pos
        sta Object::x_pos
        sep #P_M8
.a8
        rts

; ---------------------------------------------------------------------------
; swim_squid: the blooper's stroke. Counter 0: each 8th
; frame the rise + 1 and the swim speed = the rise; at 2, counter 1.
; Counter 1: each 8th frame the rise - 1, the swim speed = it; at 0, counter
; 2 and its slow timer = 2. Counter 2: it sinks 1 pixel on each even frame
; while the timer runs, then on while its Y + $10 + c is above the player's
; Y (an 8-bit sum: from row $F0 on it wraps and the blooper sinks on); when
; it is not, counter 0. One stroke: 32 pixels up and sideways in 24 frames.
;
; In:       D = the blooper's record; Y8 = c, 0 or 1 (L1, move_squid)
; Out:      the stroke fields, the record's row
; Changes:  A, X
; Keeps:    Y
; Time:     about 30 cycles
; Original: $CBDF-$CC35 (swim_squid)
; ---------------------------------------------------------------------------
swim_squid:
.a8
.i8
        lda Object::squid_stroke
        and #SQUID_STROKE_SINK
        bne @sink
        lda frame_count
        and #SQUID_STEP_FRAMES
        bne @done
        lda Object::squid_stroke
        lsr a
        bcs @slower
; Counter 0: faster.
        inc Object::squid_rise
        lda Object::squid_rise
        sta Object::squid_swim_speed
        cmp #SQUID_TOP_SPEED
        bne @done
        inc Object::squid_stroke        ; counter 1
        rts
; Counter 1: slower.
@slower:
        dec Object::squid_rise
        lda Object::squid_rise
        sta Object::squid_swim_speed
        bne @done
        inc Object::squid_stroke        ; counter 2: the sink
        ldx Object::slot
        lda #SQUID_SINK_TICKS
        sta timers + TIMER_ENEMY_INTERVAL - SLOT_ENEMY,x
        rts
; Counter 2: the sink.
@sink:
        ldx Object::slot
        lda timers + TIMER_ENEMY_INTERVAL - SLOT_ENEMY,x
        bne @sink_step
        cpy #1                          ; carry = c
        lda Object::y_pos
        adc #SQUID_SINK_MARGIN
        cmp player_object + Object::y_pos ; the player's row
        bcc @sink_step
        stz Object::squid_stroke        ; counter 0
        rts
@sink_step:
        lda frame_count
        lsr a
        bcs @done                       ; odd frames: no step
        inc Object::y_pos               ; the row only
@done:
        rts

; ---------------------------------------------------------------------------
; fly_bullet_bill: the bullet bill of a wave (kind $08): 1.5 pixels a frame
; to the left, always; a defeated one falls (move_leaper_vertically: pull
; $1C, top 3) with no X move.
;
; In:       D = the bullet's record
; Out:      the record moved
; Changes:  A, X, Y
; Time:     about 15 cycles and the move
; Original: $CC36-$CC45 (fly_bullet_bill)
; ---------------------------------------------------------------------------
fly_bullet_bill:
.a8
.i8
        lda Object::state
        and #ENEMY_DEFEATED
        beq @fly
        jmp move_leaper_vertically
@fly:
        lda #BULLET_SPEED
        sta Object::x_speed
        jmp move_enemy_sideways

; ---------------------------------------------------------------------------
; swim_fish: the swimming cheep-cheeps (kinds $0A grey, $0B red). A defeated one sinks (move_enemy_slowly), with no X move. Else it
; loses swim_fish_x_speeds[kind - $0A] of X fraction each frame ($40, a
; quarter pixel, or $80), with the borrow into the X word: always left. In
; enemy slots 2-5 it also drifts 1/8 pixel a frame up (cheep_move below
; $10) or down, the 24-bit Y with its high byte; the drift turns when the
; fish is 15 pixels or more from its start Y (cheep_start_y): up when it is
; below it, down when above (bob_fish_vertically). So it swings between 15
; pixels above and below its start, 240 frames from one side to the other.
;
; In:       D = the fish's record
; Out:      the record moved
; Changes:  A, X, Y
; Time:     about 70 cycles
; Original: $CC4A-$CCC6 (swim_fish, bob_fish_vertically)
; ---------------------------------------------------------------------------
swim_fish:
.a8
.i8
        lda Object::state
        and #ENEMY_DEFEATED
        beq @alive
        jmp move_enemy_slowly
@alive:
; The X: the fraction step with the borrow into the pixel and the page.
        lda Object::kind
        sec
        sbc #KIND_GREY_CHEEP
        tax
        lda Object::x_fraction
        sec
        sbc swim_fish_x_speeds,x
        sta Object::x_fraction
        rep #P_M8
.a16
        lda Object::x_pos
        sbc #0
        sta Object::x_pos
        sep #P_M8
.a8
; The drift, in enemy slots 2-5: the Y fraction with the carry or the borrow
; into the row and the Y high.
        lda Object::slot
        cmp #SLOT_ENEMY + FISH_DRIFT_SLOTS
        bcc @done
        lda Object::cheep_move
        cmp #FISH_DRIFT_DOWN
        bcc @up
        lda Object::y_fraction
        clc
        adc #FISH_DRIFT
        sta Object::y_fraction
        rep #P_M8
.a16
        lda Object::y_pos
        adc #0
        bra @drifted
@up:
.a8
        lda Object::y_fraction
        sec
        sbc #FISH_DRIFT
        sta Object::y_fraction
        rep #P_M8
.a16
        lda Object::y_pos
        sbc #0
@drifted:
        sta Object::y_pos
        sep #P_M8
.a8
; The turn of the drift: d = its row - its start row, 8 bits, signed.
        ldy #FISH_DRIFT_UP
        lda Object::y_pos
        sec
        sbc Object::cheep_start_y
        bpl @below
        ldy #FISH_DRIFT_DOWN
        eor #$FF
        inc a                           ; |d|
@below:
        cmp #FISH_SWING
        bcc @done
        sty Object::cheep_move
@done:
        rts

; ---------------------------------------------------------------------------
; swoop_fish: the flying cheep-cheep (kind $14). A defeated
; one falls (move_leaper_vertically) with no X move. Else it moves at its X
; speed, then flies with apply_vertical_move (pull $0D, top 5). The arc's
; nudge: i = its Y speed's fraction / 16 (0-15); when its row is within 8
; pixels of fish_arc_heights[i], the fraction gets + $10 (8 bits: no carry
; into the whole speed). The original reads its 5-byte table with i up to
; 15, so the next table and the first bytes of its own code take part:
; fish_arc_heights holds those 16 bytes. Its writes of the attributes (0
; when defeated, flying_fish_priority[i] else) have no effect: the next run
; clears the attributes before the drawing, so the port
; makes none.
;
; In:       D = the fish's record
; Out:      the record moved
; Changes:  A, X, Y
; Time:     about 40 cycles and the routines it calls
; Original: $CEDF-$CF24 (swoop_fish)
; ---------------------------------------------------------------------------
swoop_fish:
.a8
.i8
        lda Object::state
        and #ENEMY_DEFEATED
        beq @alive
        jmp move_leaper_vertically
@alive:
        jsr move_enemy_sideways
        lda #FISH_PULL
        ldy #FISH_TOP_SPEED
        jsr apply_vertical_move ; A the pull, Y the top speed
; The arc's nudge.
        lda Object::y_speed_fraction
        lsr a
        lsr a
        lsr a
        lsr a
        tax                             ; i, 0-15
        lda Object::y_pos
        sec
        sbc fish_arc_heights,x
        bpl @near
        eor #$FF
        inc a                           ; |row - the arc byte|, 8 bits
@near:
        cmp #FISH_ARC_NEAR
        bcs @done
        lda Object::y_speed_fraction
        clc
        adc #FISH_ARC_NUDGE
        sta Object::y_speed_fraction
@done:
        rts

; ---------------------------------------------------------------------------
; move_cloud_rider: Lakitu (kind $11). A defeated Lakitu
; falls (drop_enemy_fast) with no X move. While his state is 0 the spiny
; wave stays on (frenzy_kind = $12) and his speed comes from his
; distance to the player (measure_player_gap); when his state is not 0
; (stop_waves: the wave ended) he leaves: his direction 0, no wave,
; speed $10. His X speed is the speed toward his direction (Object::lakitu_direction
; 1: right, else left), and he moves.
;
; In:       D = Lakitu's record
; Out:      the record moved; frenzy_kind
; Changes:  A, X, Y
; Time:     about 40 cycles and the routines it calls
; Original: $CF28-$CF6B (move_cloud_rider)
; ---------------------------------------------------------------------------
move_cloud_rider:
.a8
.i8
        lda Object::state
        and #ENEMY_DEFEATED
        beq @alive
        jmp drop_enemy_fast
@alive:
        lda Object::state
        beq @follow
        stz Object::lakitu_direction    ; he leaves to the left
        stz frenzy_kind
        lda #CLOUD_LEAVE_SPEED
        bra @speed
@follow:
        lda #KIND_SPINY
        sta frenzy_kind                 ; the spiny wave stays on
        jsr measure_player_gap
@speed:
        sta Object::x_speed
        ldy #FACING_RIGHT
        lda Object::lakitu_direction
        lsr a
        bcs @move                       ; bit 0: right
        lda Object::x_speed
        eor #$FF
        inc a
        sta Object::x_speed
        ldy #FACING_LEFT
@move:
        sty Object::direction
        jmp move_enemy_sideways

; ---------------------------------------------------------------------------
; measure_player_gap: Lakitu's speed from his distance to the player. The distance t0 is the low byte of |his X - the player's X|
; (a gap of 256 pixels or more reads as its remainder), at most $3C.
; At $3C, when he flies away from the player he turns: at once when he
; flies left; when he flies right he slows by 1 unit a frame and that is his
; speed until it reaches 0, then he turns. The speed is a base -
; ((t0 AND $3C) / 4 + 1): the base of cloud_distance_adjusts by the
; player's move: 0 when the player is still, or the screen does not scroll,
; or Lakitu flies left; 1 when the player moves and the screen scrolls; 2
; when the player's X speed is $19 or more (an unsigned compare) and the
; screen scrolls 2 pixels or more.
;
; Only Lakitu's run calls it in the port: the spiny egg's start in the
; original also calls it, with no effect. So its kind tests ($11 in
; the turn, $12 for the player's move) are always true and false here.
;
; In:       D = Lakitu's record
; Out:      A8 = the speed, 1/16 pixel a frame (positive); Object::lakitu_direction;
;           Object::x_speed when he slows
; Changes:  A, X, Y
; Time:     about 70 cycles
; Original: $CF6C-$CFDC (measure_player_gap)
; ---------------------------------------------------------------------------
measure_player_gap:
.a8
.i8
; The distance and the direction toward the player.
        ldy #CLOUD_LEFT                 ; he is at or right of the player: toward him is left
        rep #P_M8
.a16
        lda Object::x_pos
        sec
        sbc player_object + Object::x_pos ; his X - the player's X (player_enemy_gap)
        sep #P_M8                       ; (the sign of the subtract stays); A = its low byte
.a8
        bpl @gap
        ldy #CLOUD_RIGHT                ; he is left of the player
        eor #$FF
        inc a
@gap:
        cmp #CLOUD_FAR
        bcc @distance
; Far: he turns toward the player.
        cpy Object::lakitu_direction
        beq @far
        lda Object::lakitu_direction
        beq @turn                       ; flying left: at once
        dec Object::x_speed             ; flying right: 1 unit slower
        lda Object::x_speed
        bne @done                       ; still moving: that is his speed
@turn:
        sty Object::lakitu_direction
@far:
        lda #CLOUD_FAR
; d = (the distance AND $3C) / 4.
@distance:
        and #CLOUD_DISTANCE
        lsr a
        lsr a
        tax                             ; d, 0-15
; The base by the player's move.
        ldy #CLOUD_BASE_STILL
        lda player_object + Object::x_speed
        beq @base
        lda scroll_amount
        beq @base
        iny                             ; he moves and the screen scrolls
        lda player_object + Object::x_speed
        cmp #CLOUD_RUN_SPEED
        bcc @flying_left
        lda scroll_amount
        cmp #CLOUD_FAST_SCROLL
        bcc @flying_left
        iny                             ; he runs and the screen scrolls fast
@flying_left:
        lda Object::lakitu_direction
        bne @base
        ldy #CLOUD_BASE_STILL
@base:
        txa
        eor #$FF                        ; -(d + 1)
        clc
        adc cloud_distance_adjusts,y
@done:
        rts

; ---------------------------------------------------------------------------
; bob_piranha: the piranha plant (kind $0D). While its state
; is not 0 or its frame timer runs (a rest) nothing moves. At rest at an end
; (piranha_moving 0): after a rise (piranha_speed negative) it turns at
; once; in the pipe it stays while the player is less than $21 pixels away
; (the low byte of the gap, L12), else it turns: the step's sign flips and it
; moves. Moving: on odd frames, when the timers run, its row + the step;
; at the end of the move (piranha_low_y going down, piranha_high_y going
; up) it rests 64 frames. It rises 24 pixels in 48 frames. Its write of the
; attributes has no effect (the drawing gives the plant its priority),
; so the port makes none.
;
; In:       D = the plant's record
; Out:      the record moved
; Changes:  A, X, Y
; Time:     about 60 cycles
; Original: $D3B0-$D40F (bob_piranha)
; ---------------------------------------------------------------------------
bob_piranha:
.a8
.i8
        lda Object::state
        bne @done
        ldx Object::slot
        lda timers + TIMER_ENEMY_FRAME - SLOT_ENEMY,x
        bne @done                       ; a rest
        lda Object::piranha_moving
        bne @move
        lda Object::piranha_speed
        bmi @turn                       ; it rose last
        rep #P_M8
.a16
        lda Object::x_pos
        sec
        sbc player_object + Object::x_pos ; (player_enemy_gap)
        sep #P_M8                       ; (the sign stays); A = the gap's low byte
.a8
        bpl @gap
        eor #$FF
        inc a
@gap:
        cmp #PIRANHA_NEAR
        bcc @done                       ; the player is near: it stays in the pipe
@turn:
        lda Object::piranha_speed
        eor #$FF
        inc a
        sta Object::piranha_speed
        inc Object::piranha_moving      ; 0 to 1: it moves
@move:
        lda Object::piranha_low_y       ; going down: the bottom
        ldy Object::piranha_speed
        bpl @end
        lda Object::piranha_high_y      ; going up: the top
@end:
        tax                             ; X = the end of the move
        lda frame_count
        lsr a
        bcc @done                       ; even frames: no step
        lda timer_hold
        bne @done
        lda Object::y_pos
        clc
        adc Object::piranha_speed
        sta Object::y_pos               ; the row only
        cpx Object::y_pos
        bne @done
        stz Object::piranha_moving      ; at the end: a rest
        ldx Object::slot
        lda #PIRANHA_REST
        sta timers + TIMER_ENEMY_FRAME - SLOT_ENEMY,x
@done:
        rts

; ===========================================================================
; The fire bars
; ===========================================================================

; ---------------------------------------------------------------------------
; spin_and_draw_fire_bar: a fire bar's turn, its balls and their test. When
; the bar's own column is off the screen (offscreen bit 3) nothing is drawn
; or tested, though balls could reach the screen. When the timers run, the
; 16-bit angle (Object::firebar_angle_high:angle_low) turns by the turn speed, up
; or down by its turn direction, and its high byte is kept to 0-31 (the
; original's turn_fire_bar); a long bar (kinds $1F on) never shows the two
; flat angles 8 and $18, where its 12 sprites would share one row: it takes
; the next one. Then the center ball at the bar's screen place in its first
; sprite, and 5 (short) or 11 (long) balls, ball p at 8 (p + 1) pixels from
; the center; the balls after the fifth go into the sprites of the bar's
; second slot (duplicate_slot, its enemy number; one value for all
; bars, L11).
;
; The original computes each ball's offsets from its angle at run time
; (fire_bar_piece_offset), and once more before the center with any index,
; whose results are not used. The port reads them from fire_bar_pieces
; (the builder's table of 32 angles x 11 balls): one block move copies this
; angle's 22 bytes into fire_bar_reach.
;
; In:       D = the fire bar's record
; Out:      the angle; the balls' sprites (Y, X here; the tile and
;           attributes by draw_fire_piece_sprite); a hit: the player hurt
; and enemy 0's direction
; Changes:  A, X, Y; the fire bar temporaries
; Time:     about 250 cycles and 120 for each ball, and the routines it calls
; Original: $CD3C-$CDBA (spin_and_draw_fire_bar), $D410-$D431 (turn_fire_bar),
;           $CE8E-$CED4 (fire_bar_piece_offset, as the build-time table)
; ---------------------------------------------------------------------------
spin_and_draw_fire_bar:
.a8
.i8
        jsr check_enemy_offscreen
        lda offscreen_bits + REL_ENEMY
        and #OFFSCREEN_COLUMN_1
        beq @on_screen
        rts
@on_screen:
; The turn, when the timers run: the angle's fraction + or - the speed, the
; carry or the borrow into its step.
        lda timer_hold
        bne @angle
        lda Object::firebar_turn
        bne @back
        lda Object::firebar_angle_low
        clc
        adc Object::firebar_speed
        sta Object::firebar_angle_low
        lda Object::firebar_angle_high
        adc #0
        bra @turned
@back:
        lda Object::firebar_angle_low
        sec
        sbc Object::firebar_speed
        sta Object::firebar_angle_low
        lda Object::firebar_angle_high
        sbc #0
@turned:
        and #FIREBAR_ANGLE_MASK
        sta Object::firebar_angle_high
; A long bar skips the flat angles.
@angle:
        lda Object::firebar_angle_high
        ldy Object::kind
        cpy #KIND_LONG_FIRE_BAR
        bcc @offsets
        cmp #FIREBAR_ANGLE_RIGHT
        beq @skip
        cmp #FIREBAR_ANGLE_LEFT
        bne @offsets
@skip:
        inc a
        sta Object::firebar_angle_high
; The balls' offsets at this angle: fire_bar_pieces + 22 x the angle, copied.
@offsets:
        rep #P_M8 | P_X8
.a16
.i16
        and #FIREBAR_ANGLE_MASK         ; the angle as a word
        asl a
        sta fire_bar_block              ; 2 x the angle
        asl a
        asl a                           ; 8 x (the shifts of a value below 32 leave the carry clear)
        adc fire_bar_block              ; 10 x
        asl a                           ; 20 x
        adc fire_bar_block              ; 22 x
        adc #fire_bar_pieces
        tax                             ; from the angle's block
        ldy #fire_bar_reach             ; to fire_bar_reach
        lda #FIREBAR_REACH_BYTES - 1
        mvn #^fire_bar_pieces, #^fire_bar_reach ; (bank 0 to bank 0: DBR stays 0)
        sep #P_M8 | P_X8
.a8
.i8
; The center ball: the bar's first sprite at its screen place.
        jsr enemy_screen_position
        ldx Object::slot
        ldy sprite_offset + SPR_ENEMY - SLOT_ENEMY,x
        sty fire_bar_sprite
        lda rel_y + REL_ENEMY
        sta sprite_list + SPRITE_Y,y
        sta fire_ball_y
        lda rel_x + REL_ENEMY
        sta sprite_list + SPRITE_X,y
        sta fire_ball_x
        jsr check_fire_piece
; The balls after the center.
        ldy #FIREBAR_SHORT_BALLS
        lda Object::kind
        cmp #KIND_LONG_FIRE_BAR
        bcc @count
        ldy #FIREBAR_LONG_BALLS
@count:
        sty fire_bar_count
        stz fire_bar_piece
@ball:
        jsr draw_fire_bar_pieces
        inc fire_bar_piece
        lda fire_bar_piece
        cmp fire_bar_count
        bcs @done
        cmp #FIREBAR_SLOT_BALLS
        bne @ball
        ldx duplicate_slot              ; the sixth ball on: the second slot's sprites
        lda sprite_offset + SPR_ENEMY,x ; (duplicate_slot: an enemy number)
        sta fire_bar_sprite
        bra @ball
@done:
        rts

; ---------------------------------------------------------------------------
; draw_fire_bar_pieces: one ball of a fire bar: its sprite X
; = the center's screen X + its X offset (8 bits); a ball whose X is $59 or
; more pixels from the center's (8 bits: it wrapped past a screen edge, as
; the true distance is at most 88) is hidden (the original's
; hide_far_fire_piece), and so is every ball of a bar whose screen Y is
; $F8; else its Y = the center's screen Y + its Y offset (8 bits: a ball
; above the top wraps to the bottom rows). Then its tile and test
; (check_fire_piece).
;
; In:       D = the fire bar's record; fire_bar_piece = the ball p;
;           fire_bar_sprite = its sprite entry; fire_bar_reach
; Out:      the ball's sprite; fire_bar_sprite = the next entry
; Changes:  A, X, Y; fire_ball_x, fire_ball_y, fire_player_x
; Time:     about 60 cycles and check_fire_piece
; Original: $CDBB-$CE07 (draw_fire_bar_pieces, hide_far_fire_piece)
; ---------------------------------------------------------------------------
draw_fire_bar_pieces:
.a8
.i8
        lda fire_bar_piece
        asl a
        tax                             ; the ball's offsets in fire_bar_reach
        ldy fire_bar_sprite
        lda rel_x + REL_ENEMY
        clc
        adc fire_bar_reach,x
        sta sprite_list + SPRITE_X,y
        sta fire_ball_x
; Its distance from the center in X, 8 bits.
        sec
        sbc rel_x + REL_ENEMY
        bcs @distance                   ; X at or right of the center's: X - center
        eor #$FF
        inc a                           ; center - X
@distance:
        cmp #FIREBAR_FAR_X
        bcs @hide
        lda rel_y + REL_ENEMY
        cmp #HIDDEN_Y
        beq @y                          ; the bar hidden: the ball too
        clc
        adc fire_bar_reach+1,x
        bra @y
@hide:
        lda #HIDDEN_Y
@y:
        sta sprite_list + SPRITE_Y,y
        sta fire_ball_y
        ; runs on into check_fire_piece

; ---------------------------------------------------------------------------
; check_fire_piece: a fire bar ball's tile and attributes
; (draw_fire_piece_sprite), then its test against the player (the
; original's compare_fire_piece), then the next sprite entry. No test while
; the star or the hold runs, or while the player is off the screen (Y high
; not 1). The test points: a big player standing: his Y, Y + $0C, Y + $18
; (fire_bar_y_adders); a small or crouching player: Y + $18 only. A point
; hits when |its Y - the ball's Y| < 8 (8 bits, signed), the ball's X is
; below $F0, and |the player's test X - the ball's X| < 8, where his test X
; is his first sprite's X + 4: he is drawn after the enemies, so that X
; is of the frame before while his Y is of this frame.
;
; The first hit ends the test: enemy 0's direction = 1 when the player's
; test X is the ball's X or more, else 2, whatever enemy slot 0 holds (L4:
; hurt_player does not read it; a walker there shows that facing until its
; own code sets it again); then hurt_player ( it does nothing while the
; player is already hurt).
;
; In:       D = the fire bar's record; Y8 = the ball's sprite entry
;           (fire_bar_sprite); fire_ball_x, fire_ball_y
; Out:      the sprite's tile and attributes; fire_bar_sprite = the next
;           entry; a hit
; Changes:  A, X, Y; fire_player_x
; Time:     about 40 cycles, up to 150 with three test points
; Original: $CE08-$CE8D (check_fire_piece, compare_fire_piece)
; ---------------------------------------------------------------------------
check_fire_piece:
.a8
.i8
        jsr draw_fire_piece_sprite ; Y = the sprite entry
        lda timers + TIMER_STAR
        ora timer_hold
        bne @next
        lda player_object + Object::y_pos + 1
        cmp #Y_HIGH_SCREEN
        bne @next
; The first test point, and the adders of the others.
        ldx #0                          ; the next point's adder
        lda player_object + Object::y_pos
        ldy player_small
        bne @low_only
        ldy crouching
        beq @point
@low_only:
        ldx #FIRE_TEST_POINTS           ; no other point
        clc
        adc #FIRE_LOW_POINT
@point:
        sec
        sbc fire_ball_y
        bpl @dy
        eor #$FF
        inc a
@dy:
        cmp #FIRE_HIT_RANGE
        bcs @miss
        lda fire_ball_x
        cmp #FIRE_BALL_X_LIMIT
        bcs @miss
        lda sprite_list + PLAYER_FIRST_SPRITE * SPRITE_ENTRY + SPRITE_X
        clc
        adc #FIRE_PLAYER_CENTER
        sta fire_player_x
        sec
        sbc fire_ball_x
        bpl @dx
        eor #$FF
        inc a
@dx:
        cmp #FIRE_HIT_RANGE
        bcc @hit
@miss:
        cpx #FIRE_TEST_POINTS
        beq @next
        lda player_object + Object::y_pos
        clc
        adc fire_bar_y_adders,x
        inx
        bra @point
; A hit: enemy 0's direction, then the hurt.
@hit:
        ldx #FACING_RIGHT
        lda fire_player_x
        cmp fire_ball_x
        bcs @side
        ldx #FACING_LEFT
@side:
        stx enemy_objects + Object::direction ; enemy slot 0, whatever it holds
        jsr hurt_player
@next:
        lda fire_bar_sprite
        clc
        adc #SPRITE_ENTRY
        sta fire_bar_sprite
        rts

; ===========================================================================
; Bowser, his bridge and his flames (17)
; ===========================================================================

; ---------------------------------------------------------------------------
; bridge_collapse_task: the first task of the victory mode, each frame:
; Bowser's bridge falls, one piece each 4 frames (bowser_feet), the first
; when bowser_feet (1-$20 from his walk) reaches 0: the axe, the chain,
; then the 13 pieces from right to left, 15 in 60 frames. Each piece is a
; blank square in list 1 (store_block_tiles with the blank set, at the
; metatile place of the cells of bridge_rows and bridge_columns: the
; original's two records of 2 tiles in name table 0), the blast sound and
; the brick sound, and a step of his feet. After the last piece he falls
; (state $40, the fall sound in place of the blast) and the next frames move
; him down (move_enemy_slowly) until row $E0. The task ends when he is
; gone: below row $E0, any other state, or a kind other than Bowser's in
; his slot (collision code changes it when fire beats him): the event song stops, the
; next victory task, erase_all_enemies.
;
; In:       any D (the victory mode: the player's)
; Out:      Bowser's records; list 1; the sound commands; mode_task
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 60 cycles, 120 with a piece, and the routines it calls
; Original: $CFEC-$D060 (bridge_collapse_task)
; ---------------------------------------------------------------------------
bridge_collapse_task:
.a8
.i8
        phd
        lda bowser_front_slot           ; his enemy number
        clc
        adc #SLOT_ENEMY
        tax
        object_from_x                   ; D = Bowser's front half
        lda Object::kind
        cmp #KIND_BOWSER
        bne @end
        lda Object::state
        beq @collapse
        and #ENEMY_DROP
        beq @end                        ; any other state: he is beaten
        lda Object::y_pos
        cmp #BOWSER_GONE_Y
        bcs @end
        jsr move_enemy_slowly ; he falls
        bra @draw
; The collapse: a piece each 4 frames.
@collapse:
        dec bowser_feet
        bne @draw
        lda #BRIDGE_PIECE_FRAMES
        sta bowser_feet
        lda bowser_body
        eor #BOWSER_FEET_STEP
        sta bowser_body
        ldy bridge_collapse
        lda bridge_rows,y
        sec
        sbc #METATILE_FIRST_ROW
        lsr a
        tax                             ; the square's metatile row
        lda bridge_columns,y
        lsr a
        tay                             ; its ring metatile column
        lda #BLOCK_SET_BLANK
        jsr store_block_tiles ; the blank square, both lengths of list 1 grown
        lda #SQUARE2_BLAST
        sta snd_square2_queue
        lda #NOISE_BRICK_SHATTER
        sta snd_noise_queue
        inc bridge_collapse
        lda bridge_collapse
        cmp #BRIDGE_PIECES
        bne @draw
        rep #P_M8
.a16
        stz Object::y_speed             ; (clear_enemy_vspeed)
        sep #P_M8
.a8
        lda #ENEMY_DROP
        sta Object::state               ; he falls
        lda #SQUARE2_BOWSER_FALL
        sta snd_square2_queue
@draw:
        jsr draw_whole_bowser
        pld
        rts
; He is gone.
@end:
        lda #EVENT_SILENCE
        sta snd_event_queue
        inc mode_task
        jsr erase_all_enemies
        pld
        rts

; ---------------------------------------------------------------------------
; bowser_actions: Bowser (kind $2D) each frame, in the
; original's order. Defeated (bit 5, by fireballs): below row $E0
; erase_all_enemies, else he falls (move_enemy_slowly) and is drawn. Else
; there is no wave while he lives; during the hold only his fire code and
; his drawing run. While his mouth is open he does not walk. His walk: his
; feet step each 32 frames; he faces left each 16 frames; while his jump
; timer runs and he is left of the player he follows him (2 pixels each 4
; frames, up to X $C8; no flame meanwhile); each 4 frames he steps by
; bowser_speed within range_from_origin of his origin (a new range from
; bowser_range_choices each time he passes his origin), turning at its ends
; when he faces left. His X is the pixel byte only, with no page change.
; Then his gravity and hammers (bowser_gravity_hammers) and his fire
; (bowser_breath_step), which run on into draw_whole_bowser.
;
; Bowser's start writes his direction $DF: this code reads
; it as the original does (= 1 for the turn, its bit 0 for the rear half),
; and draw_enemy reads its bit 1, until his first face-left frame.
;
; In:       D = Bowser's front record
; Out:      his records; frenzy_kind; the breath timer; a hammer
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 120 cycles and the routines it calls
; Original: $D065-$D070, $D07F-$D10E (bowser_actions)
; ---------------------------------------------------------------------------
bowser_actions:
.a8
.i8
        lda Object::state
        and #ENEMY_DEFEATED
        beq @alive
        lda Object::y_pos
        cmp #BOWSER_GONE_Y
        bcc @falls
        jmp erase_all_enemies
@falls:
        jsr move_enemy_slowly
        jmp draw_whole_bowser
@alive:
        stz frenzy_kind                 ; no wave while he lives (his fire sets the flame)
        lda timer_hold
        beq @mouth
        jmp bowser_breath_step
@mouth:
        bit bowser_body
        bpl @feet
        jmp bowser_gravity_hammers      ; the mouth open: no walk
; His feet: a step each 32 frames.
@feet:
        dec bowser_feet
        bne @face
        lda #BOWSER_FEET_FRAMES
        sta bowser_feet
        lda bowser_body
        eor #BOWSER_FEET_STEP
        sta bowser_body
; He faces left each 16 frames.
@face:
        lda frame_count
        and #BOWSER_FACE_FRAMES
        bne @follow
        lda #FACING_LEFT
        sta Object::direction
; He follows the player while his jump timer runs and the player is right
; of him.
@follow:
        ldx Object::slot
        lda timers + TIMER_ENEMY_FRAME - SLOT_ENEMY,x ; his jump timer
        beq @walk
        rep #P_M8
.a16
        lda Object::x_pos
        sec
        sbc player_object + Object::x_pos ; (player_enemy_gap)
        sep #P_M8                       ; (the sign stays)
.a8
        bpl @walk                       ; at or right of the player
        lda #FACING_RIGHT
        sta Object::direction
        lda #BOWSER_FOLLOW_SPEED
        sta bowser_speed
        lda #BOWSER_FOLLOW_WAIT
        sta timers + TIMER_ENEMY_FRAME - SLOT_ENEMY,x
        sta timers + TIMER_BOWSER_BREATH
        lda Object::x_pos
        cmp #BOWSER_FOLLOW_LIMIT
        bcs bowser_gravity_hammers
; His walk: a step each 4 frames, within his range of his origin.
@walk:
        lda frame_count
        and #BOWSER_STEP_FRAMES
        bne bowser_gravity_hammers
        lda Object::x_pos
        cmp bowser_origin_x
        bne @step
        ldx Object::slot
        lda random - SLOT_ENEMY,x       ; random+e
        and #BOWSER_RANGE_PICK
        tay
        lda bowser_range_choices,y
        sta range_from_origin
@step:
        lda Object::x_pos
        clc
        adc bowser_speed
        sta Object::x_pos               ; the pixel byte only
        ldy Object::direction
        cpy #FACING_RIGHT
        beq bowser_gravity_hammers
        ldy #<-BOWSER_TURN_SPEED
        sec
        sbc bowser_origin_x             ; d = X - his origin, 8 bits
        bpl @range                      ; right of the origin: the turn is to the left
        eor #$FF
        inc a
        ldy #BOWSER_TURN_SPEED
@range:
        cmp range_from_origin
        bcc bowser_gravity_hammers
        sty bowser_speed
        ; runs on into bowser_gravity_hammers

; ---------------------------------------------------------------------------
; bowser_gravity_hammers: Bowser's jump and fall. While his jump timer runs
; he stands; at 1 he jumps: his row - 1 and the Y speed 2 pixels a frame up.
; When it is 0 he is in the air: move_enemy_slowly (pull $0F, top 2); in
; worlds 6-8 a hammer each 4 frames (throw_hammer: it takes his place and
; direction); from row $80 on he is on the floor (he does not test the
; tiles): his jump timer = bowser_range_choices[random+e AND 3] ($11-$41
; frames). Then his fire (bowser_breath_step).
;
; In:       D = Bowser's front record
; Out:      his record; a hammer
; Changes:  A, X, Y
; Time:     about 50 cycles and the routines it calls
; Original: $D10F-$D148 (bowser_gravity_hammers, bowser_goto_flames)
; ---------------------------------------------------------------------------
bowser_gravity_hammers:
.a8
.i8
        ldx Object::slot
        lda timers + TIMER_ENEMY_FRAME - SLOT_ENEMY,x
        bne @standing
        jsr move_enemy_slowly
        lda player_record + PlayerRecord::world
        cmp #WORLD_6
        bcc @floor
        lda frame_count
        and #BOWSER_HAMMER_FRAMES
        bne @floor
        jsr throw_hammer
@floor:
        lda Object::y_pos
        cmp #BOWSER_FLOOR_Y
        bcc bowser_breath_step
        ldx Object::slot
        lda random - SLOT_ENEMY,x       ; random+e
        and #BOWSER_RANGE_PICK
        tay
        lda bowser_range_choices,y      ; here as frames: his jump timer
        sta timers + TIMER_ENEMY_FRAME - SLOT_ENEMY,x
        bra bowser_breath_step
@standing:
        cmp #BOWSER_JUMP_NOW
        bne bowser_breath_step
        dec Object::y_pos
        rep #P_M8
.a16
        lda #BOWSER_JUMP_SPEED          ; (clear_enemy_vspeed, then the whole speed)
        sta Object::y_speed
        sep #P_M8
.a8
        ; runs on into bowser_breath_step

; ---------------------------------------------------------------------------
; bowser_breath_step: Bowser's fire, only in worlds 1-5 and 8. When the
; breath timer ends his mouth flips: open for 32 frames; when it closes the
; breath timer = the next gap of the flame cycle (next_flame_gap: 191 or 64
; frames, 16 less in hard_mode_2) and a flame starts at his mouth through
; the wave start (frenzy_kind = $15). Then his drawing.
;
; In:       D = Bowser's front record
; Out:      bowser_body, the breath timer, frenzy_kind; his drawing
; Changes:  A, X, Y
; Time:     about 30 cycles and draw_whole_bowser
; Original: $D149-$D17A (bowser_breath_step)
; ---------------------------------------------------------------------------
bowser_breath_step:
.a8
.i8
        lda player_record + PlayerRecord::world
        cmp #WORLD_8
        beq @fire
        cmp #WORLD_6
        bcs draw_whole_bowser           ; worlds 6 and 7: no fire
@fire:
        lda timers + TIMER_BOWSER_BREATH
        bne draw_whole_bowser
        lda #BOWSER_MOUTH_FRAMES
        sta timers + TIMER_BOWSER_BREATH
        lda bowser_body
        eor #BOWSER_MOUTH_OPEN
        sta bowser_body
        bmi draw_whole_bowser           ; it opened: the flame comes when it closes
        jsr next_flame_gap
        ldy hard_mode_2
        beq @gap
        sec
        sbc #BOWSER_HARD_GAP_CUT
@gap:
        sta timers + TIMER_BOWSER_BREATH
        lda #KIND_BOWSER_FLAME
        sta frenzy_kind
        ; runs on into draw_whole_bowser

; ---------------------------------------------------------------------------
; draw_whole_bowser: both halves of Bowser: the front half in his slot, then
; the rear half in the slot of duplicate_slot (an enemy number): 16
; pixels behind him (right of him when bit 0 of his direction is 0, left of
; him when it is 1), 8 lower, the pixel bytes only, with his state and
; direction and kind $2D; each half is drawn and tested on its own
; (draw_bowser_half). bowser_draw is 0 after both.
;
; In:       D = Bowser's front record
; Out:      the rear half's record; both halves' sprites; bowser_draw = 0
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 90 cycles and two draw_bowser_half
; Original: $D17B-$D1BB (draw_whole_bowser)
; ---------------------------------------------------------------------------
draw_whole_bowser:
.a8
.i8
        jsr draw_bowser_half            ; the front half
        phd
        lda Object::direction
        pha
        lda Object::state
        pha
        lda Object::y_pos
        clc
        adc #BOWSER_REAR_DROP
        pha
        ldy #BOWSER_REAR_BEHIND
        lda Object::direction
        lsr a
        bcc @rear_x                     ; bit 0 clear: he faces left, the rear is to his right
        ldy #<-BOWSER_REAR_BEHIND
@rear_x:
        tya
        clc
        adc Object::x_pos
        tay                             ; the rear's X, across the change of D
        lda duplicate_slot              ; the rear half's enemy number
        clc
        adc #SLOT_ENEMY
        tax
        object_from_x                   ; D = the rear half
        sty Object::x_pos               ; the pixel byte only
        pla
        sta Object::y_pos               ; the row only
        pla
        sta Object::state
        pla
        sta Object::direction
        lda #KIND_BOWSER
        sta Object::kind
        jsr draw_bowser_half            ; the rear half
        pld
        stz bowser_draw
        rts

; ---------------------------------------------------------------------------
; draw_bowser_half: one half of Bowser: bowser_draw + 1 (1 while the front
; half draws, 2 for the rear: the drawing picks the half by it), its
; offscreen bits, screen place and drawing (run_rescued_person), and, when
; its state is 0, its box ($0A) and its test against the player.
;
; In:       D = the half's record
; Out:      bowser_draw; the half's sprites; the collision's results
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 30 cycles and the routines it calls
; Original: $D1BC-$D1D0 (draw_bowser_half)
; ---------------------------------------------------------------------------
draw_bowser_half:
.a8
.i8
        inc bowser_draw
        jsr run_rescued_person
        lda Object::state
        bne @done
        lda #BOX_BOWSER
        sta Object::box
        jsr enemy_hit_box
        jmp player_hits_enemy
@done:
        rts

; ---------------------------------------------------------------------------
; next_flame_gap: the next gap of the flame cycle (bowser_flame_gaps: 191 or
; 64 frames), and the cycle's step on, 0-7. Bowser's breath and the flame
; wave's start step the same cycle.
;
; In:       nothing
; Out:      A8 = the gap in frames; bowser_flame_timer
; Changes:  A, Y
; Keeps:    X, D
; Time:     about 25 cycles
; Original: $D1D9-$D1EA (next_flame_gap)
; ---------------------------------------------------------------------------
next_flame_gap:
.a8
.i8
        ldy bowser_flame_timer
        tya
        inc a
        and #BOWSER_FLAME_STEPS - 1
        sta bowser_flame_timer
        lda bowser_flame_gaps,y
        rts

; ---------------------------------------------------------------------------
; fly_bowser_flame: a flame's flight and its sprites. When
; the timers run it flies 1.25 pixels a frame left (1.375 in hard_mode_2):
; the 24-bit X - $0140 ($0160), with the borrow from the fraction into the
; X word; and while its row differs from its target height
; (bowser_flame_heights[flame_height]) it moves 1 pixel a frame toward
; it (flame_drift, +1 or -1; 0 for a flame of the wave). Then its screen
; place and offscreen bits, and with state 0 three sprites 8 pixels apart
; (a flame that the star knocked out has state bit 5 and shows none):
; its first tile and the next two, the attributes with a flip in Y on frames
; where frame_count bit 1 is 1; each offscreen column bit hides a sprite:
; bit 3 the first, bit 2 the second, bit 1 the third, and bit 0 the slot's
; fourth sprite, which is not a part of the flame.
;
; The original moves rel_x on by 24 pixels in its sprite loop and so takes
; the screen place and the offscreen bits again in run_bowser_fire; this
; loop keeps rel_x, and run_bowser_fire uses the values made here.
;
; In:       D = the flame's record
; Out:      the record; rel_x, rel_y, offscreen_bits + REL_ENEMY; the
;           flame's sprites
; Changes:  A, X, Y; flame_columns
; Time:     about 140 cycles and the routines it calls
; Original: $D1EB-$D294 (fly_bowser_flame); the second calls of
;           check_enemy_offscreen and enemy_screen_position in
;           run_bowser_fire ($C938-$C93D)
; ---------------------------------------------------------------------------
fly_bowser_flame:
.a8
.i8
        lda timer_hold
        bne @place
; The flight to the left.
        lda Object::x_fraction
        sec
        ldy hard_mode_2
        bne @hard
        sbc #FLAME_STEP_FRACTION
        bra @fraction
@hard:
        sbc #FLAME_STEP_FRACTION_HARD
@fraction:
        sta Object::x_fraction
        rep #P_M8
.a16
        lda Object::x_pos
        sbc #FLAME_STEP_PIXELS          ; with the borrow of the fraction
        sta Object::x_pos
        sep #P_M8
.a8
; Toward its target height.
        ldx Object::flame_height
        lda Object::y_pos
        cmp bowser_flame_heights,x      ; the flame height table
        beq @place
        clc
        adc Object::flame_drift
        sta Object::y_pos               ; the row only
@place:
        jsr enemy_screen_position
        jsr check_enemy_offscreen
        lda Object::state
        bne @done                       ; knocked out by the star: no sprites
; Its three sprites.
        ldx Object::slot
        ldy sprite_offset + SPR_ENEMY - SLOT_ENEMY,x
        lda rel_y + REL_ENEMY
        sta sprite_list + SPRITE_Y,y
        sta sprite_list + SPRITE_ENTRY + SPRITE_Y,y
        sta sprite_list + 2 * SPRITE_ENTRY + SPRITE_Y,y
        lda bowser_flame_tile
        sta sprite_list + SPRITE_TILE,y
        inc a
        sta sprite_list + SPRITE_ENTRY + SPRITE_TILE,y
        inc a
        sta sprite_list + 2 * SPRITE_ENTRY + SPRITE_TILE,y
        lda frame_count
        and #FLAME_FLIP_FRAMES
        beq @plain
        lda bowser_flame_flipped_attr   ; frame_count bit 1: flipped in Y
        bra @attr
@plain:
        lda bowser_flame_attr
@attr:
        sta sprite_list + SPRITE_ATTR,y
        sta sprite_list + SPRITE_ENTRY + SPRITE_ATTR,y
        sta sprite_list + 2 * SPRITE_ENTRY + SPRITE_ATTR,y
        lda rel_x + REL_ENEMY
        sta sprite_list + SPRITE_X,y
        clc
        adc #FLAME_PART_WIDTH
        sta sprite_list + SPRITE_ENTRY + SPRITE_X,y
        clc
        adc #FLAME_PART_WIDTH
        sta sprite_list + 2 * SPRITE_ENTRY + SPRITE_X,y
; Each column off the screen hides its sprite (bit 0: the slot's fourth).
        lda offscreen_bits + REL_ENEMY
        sta flame_columns
        lda #HIDDEN_Y
        lsr flame_columns
        bcc @column_3
        sta sprite_list + FLAME_PARTS * SPRITE_ENTRY + SPRITE_Y,y
@column_3:
        lsr flame_columns
        bcc @column_2
        sta sprite_list + 2 * SPRITE_ENTRY + SPRITE_Y,y
@column_2:
        lsr flame_columns
        bcc @column_1
        sta sprite_list + SPRITE_ENTRY + SPRITE_Y,y
@column_1:
        lsr flame_columns
        bcc @done
        sta sprite_list + SPRITE_Y,y
@done:
        rts
.assert FLAME_PARTS = 3, error, "fly_bowser_flame writes three sprites"

; ===========================================================================
; The castle flag, the fireworks
; ===========================================================================

; ---------------------------------------------------------------------------
; animate_fireworks: a firework (kind $16): its burst frame (firework_step)
; steps each 8 frames (firework_frames counts them; the first frame shows
; 7), and it is drawn each frame (draw_firework_burst, which reads the
; place of the fireball group: the firework's screen place is copied there;
; the fireballs ran earlier in the frame, so this has no other effect). In
; its 24th run, at burst frame 3, it ends with no drawing: only its active
; flag is cleared (L14: the kind and the other fields stay), the blast
; sound, and 500 points (add_end_points).
;
; In:       D = the firework's record
; Out:      the record; four sprites; at the end the score and the status
; Changes:  A, X, Y
; Time:     about 50 cycles and the routines it calls
; Original: $D295-$D2CC (animate_fireworks)
; ---------------------------------------------------------------------------
animate_fireworks:
.a8
.i8
        dec Object::firework_frames
        bne @draw
        lda #FIREWORK_FRAMES
        sta Object::firework_frames
        inc Object::firework_step
        lda Object::firework_step
        cmp #FIREWORK_BURST_STEPS
        bcs @end
@draw:
        jsr enemy_screen_position
        lda rel_y + REL_ENEMY
        sta rel_y + REL_FIREBALL
        lda rel_x + REL_ENEMY
        sta rel_x + REL_FIREBALL
        ldx Object::slot
        ldy sprite_offset + SPR_ENEMY - SLOT_ENEMY,x
        lda Object::firework_step
        jmp draw_firework_burst ; A = the burst frame, Y = the first sprite
@end:
        stz Object::active              ; the flag only
        lda #SQUARE2_BLAST
        sta snd_square2_queue
        lda #FIREWORK_POINTS
        sta digit_add + DIGIT_HUNDREDS
        jmp add_end_points

; ---------------------------------------------------------------------------
; run_castle_flag: the flag on the castle (kind $31): no wave, then the step
; of star_flag_task (the end-of-level walk, sets 1 when the player
; enters the castle; at 5, player code ends the level):
;
; | Step | Routine             | Does                                  | Next when |
; |------|---------------------|---------------------------------------|-----------|
; | 0    | castle_flag_return  | nothing (the flag is not drawn)       | player code sets 1 |
; | 1    | pick_firework_count | the fireworks by the time's last digit | at once |
; | 2    | award_time_bonus    | the time to points, 1 unit a frame    | the time is 000 |
; | 3    | raise_castle_flag   | the flag rises, then the fireworks    | the fireworks are done |
; | 4    | wait_for_area_end   | waits                                 | its timer and the event song end |
;
; In:       D = the castle flag's record
; Out:      frenzy_kind = 0; the step's work
; Changes:  A, X, Y
; Time:     about 25 cycles and the step
; Original: $D2D9-$D2F1, $D311 (run_castle_flag, castle_flag_return)
; ---------------------------------------------------------------------------
run_castle_flag:
.a8
.i8
        stz frenzy_kind
        lda star_flag_task
        cmp #STAR_FLAG_STEPS
        bcs castle_flag_return
        asl a
        tax
        jmp (.loword(castle_flag_steps),x)
castle_flag_steps:
        .addr castle_flag_return        ; 0
        .addr pick_firework_count       ; 1
        .addr award_time_bonus          ; 2
        .addr raise_castle_flag         ; 3
        .addr wait_for_area_end         ; 4
.assert * - castle_flag_steps = 2 * STAR_FLAG_STEPS, error, "castle_flag_steps: one entry for each step"
castle_flag_return:
.a8
.i8
        rts

; ---------------------------------------------------------------------------
; pick_firework_count: the fireworks by the last digit of the time at this
; frame: 1 gives 1 firework and the flag's state 5; 3 gives 3 and 3; 6 gives
; 6 and 0; any other none ($FF) and 0. The flag's state is the first index
; into the firework places (start_firework). Then the next step.
;
; In:       D = the castle flag's record; the time's digits
; Out:      fireworks_count, Object::state, star_flag_task + 1
; Changes:  A, Y
; Time:     about 30 cycles
; Original: $D2F2-$D310 (pick_firework_count)
; ---------------------------------------------------------------------------
pick_firework_count:
.a8
.i8
        lda digits + DIGITS_TIME + TIME_DIGITS - 1 ; the time's ones
        ldy #FIRST_FIREWORK_1
        cmp #TIME_ONE_FIREWORK
        beq @count
        ldy #FIRST_FIREWORK_3
        cmp #TIME_THREE_FIREWORKS
        beq @count
        ldy #FIRST_FIREWORK_6
        cmp #TIME_SIX_FIREWORKS
        beq @count
        lda #FIREWORKS_NONE
@count:
        sta fireworks_count             ; the digit is the count
        sty Object::state
        inc star_flag_task
        rts

; ---------------------------------------------------------------------------
; award_time_bonus: the time to points, one unit a frame: the time - 1 and
; 50 points (add_end_points), with the tick sound on frames where
; frame_count bit 2 is 1; when the time is 000, the next step.
;
; In:       the time's digits; frame_count; player
; Out:      the time and the score digits, their status records;
;           snd_square2_queue; star_flag_task
; Changes:  A, X, Y
; Time:     about 40 cycles and the routines it calls
; Original: $D312-$D335 (award_time_bonus)
; ---------------------------------------------------------------------------
award_time_bonus:
.a8
.i8
        lda digits + DIGITS_TIME
        ora digits + DIGITS_TIME + 1
        ora digits + DIGITS_TIME + TIME_DIGITS - 1
        bne @tick
        inc star_flag_task
        rts
@tick:
        lda frame_count
        and #BONUS_TICK_FRAMES
        beq @count
        lda #SQUARE2_TIMER_TICK
        sta snd_square2_queue
@count:
        lda #TIME_UNIT_STEP
        sta digit_add + DIGIT_TENS
        ldy #DIGITS_TIME + TIME_DIGITS - 1 ; the time's ones
        jsr add_digit_amounts ; the time - 1
        lda #TIME_UNIT_POINTS
        sta digit_add + DIGIT_TENS      ; 50 points (the score's ones digit is a fixed 0)
        ; runs on into add_end_points

; ---------------------------------------------------------------------------
; add_end_points: the points of digit_add to the score of the player on the
; screen (add_digit_amounts at his score's last digit), then the time and
; his score printed again (refresh_status_number with the time's field, 4,
; and his score's, the player number).
;
; In:       digit_add; player
; Out:      the score digits; the status records
; Changes:  A, X, Y
; Time:     about 30 cycles and the routines it calls
; Original: $D336-$D34D (add_end_points)
; ---------------------------------------------------------------------------
add_end_points:
.a8
.i8
        ldy #DIGITS_SCORE_1 + SCORE_DIGITS - 1 ; player 1's tens
        lda player
        beq @add
        ldy #DIGITS_SCORE_2 + SCORE_DIGITS - 1 ; player 2's
@add:
        jsr add_digit_amounts
        lda player
        asl a
        asl a
        asl a
        asl a                           ; the high nybble: his score's field
        ora #NYBBLE_TIME                ; the low nybble: the time's
        jmp refresh_status_number

; ---------------------------------------------------------------------------
; raise_castle_flag: the flag rises 1 pixel a frame while its row is $72 or
; more (it stops at $71); then, while fireworks are left (fireworks_count 1
; or more), the firework wave (frenzy_kind = $16: a firework each 32 frames
; through the wave start, each one taking 1 from fireworks_count); when
; none is left, a wait of 6 slow ticks and the next step. The flag is drawn
; each frame.
;
; In:       D = the castle flag's record
; Out:      its row; frenzy_kind; its slow timer; star_flag_task; its sprites
; Changes:  A, X, Y
; Time:     about 20 cycles and draw_castle_flag
; Original: $D34E-$D364, $D396-$D3A1 (raise_castle_flag)
; ---------------------------------------------------------------------------
raise_castle_flag:
.a8
.i8
        lda Object::y_pos
        cmp #CASTLE_FLAG_TOP
        bcc @raised
        dec Object::y_pos
        jmp draw_castle_flag
@raised:
        lda fireworks_count
        beq @ended
        bmi @ended
        lda #KIND_FIREWORKS
        sta frenzy_kind
        jmp draw_castle_flag
@ended:
        jsr draw_castle_flag
        ldx Object::slot
        lda #CASTLE_FLAG_WAIT
        sta timers + TIMER_ENEMY_INTERVAL - SLOT_ENEMY,x
        inc star_flag_task
        rts

; ---------------------------------------------------------------------------
; draw_castle_flag: the castle flag's four sprites, a 16 x 16 flag: each at
; its screen place + its offsets (castle_flag_dy, castle_flag_dx, 8 bits),
; its tile, and castle_flag_attr (behind the background).
;
; In:       D = the castle flag's record
; Out:      its screen place; its four sprites
; Changes:  A, X, Y
; Time:     about 160 cycles and enemy_screen_position
; Original: $D365-$D395 (draw_castle_flag)
; ---------------------------------------------------------------------------
draw_castle_flag:
.a8
.i8
        jsr enemy_screen_position
        ldx Object::slot
        ldy sprite_offset + SPR_ENEMY - SLOT_ENEMY,x
        ldx #0
@sprite:
        lda rel_y + REL_ENEMY
        clc
        adc castle_flag_dy,x
        sta sprite_list + SPRITE_Y,y
        lda castle_flag_tiles,x
        sta sprite_list + SPRITE_TILE,y
        lda castle_flag_attr
        sta sprite_list + SPRITE_ATTR,y
        lda rel_x + REL_ENEMY
        clc
        adc castle_flag_dx,x
        sta sprite_list + SPRITE_X,y
        iny
        iny
        iny
        iny
        inx
        cpx #CASTLE_FLAG_SPRITES
        bcc @sprite
        rts
.assert SPRITE_ENTRY = 4, error, "draw_castle_flag steps the sprite entry with four INY"

; ---------------------------------------------------------------------------
; wait_for_area_end: the flag is drawn; when its slow timer has ended and no
; event song plays (snd_event_music), the last step (star_flag_task 5:
; player code ends the level).
;
; In:       D = the castle flag's record
; Out:      its sprites; star_flag_task
; Changes:  A, X, Y
; Time:     about 20 cycles and draw_castle_flag
; Original: $D3A2-$D3AF (wait_for_area_end)
; ---------------------------------------------------------------------------
wait_for_area_end:
.a8
.i8
        jsr draw_castle_flag
        ldx Object::slot
        lda timers + TIMER_ENEMY_INTERVAL - SLOT_ENEMY,x
        bne @wait
        lda snd_event_music ; the event song that plays
        bne @wait
        inc star_flag_task
@wait:
        rts

; ===========================================================================
; The lifts
; ===========================================================================

; ---------------------------------------------------------------------------
; run_scale_lift: a pair of balance lifts (kind $24). The second lift of a
; pair (its state = its partner's enemy number, 0-5) runs both; the first
; (state $FF) only waits (its own hit test, drawing and bounds run). Each
; lift of a pair is erased at Y high 3 in its own run. The pair:
;
; | State of the pair | Each frame                                  | Leaves when |
; |-------------------|---------------------------------------------|-------------|
; | still             | no move, no rope records                    | the player steps on a lift |
; | the player on one | it sinks (lower_lift: 5/256 a frame per frame, top 3), the partner rises as much; rope records | he steps off (it slows), a lift reaches row $2D |
; | nobody, moving    | it slows by 5/256 a frame per frame          | the speed + 5/256 is 0 to $0A/256: still |
; | at the top        | the top lift at row $2F, both stop          | at once: still; the rope breaks when the player stands on the other lift |
; | falling           | both fall (drop_falling_lift, pull $20, top 3); the player rides | each lift is erased at Y high 3 |
;
; Its partner's slot is not checked: when the partner was erased first
; and another enemy took its slot, that enemy's row is moved.
;
; In:       D = the running lift's record
; Out:      both lifts; the player on them; list 1 (the ropes)
; Changes:  A, X, Y
; Time:     about 100 cycles, 250 with the ropes, and the routines it calls
; Original: $D432-$D4A6 (run_scale_lift)
; ---------------------------------------------------------------------------
run_scale_lift:
.a8
.i8
        lda Object::y_pos + 1
        cmp #SCALE_LIFT_GONE
        bne @paired
        jmp clear_enemy_slot
@paired:
        lda Object::state
        bpl @fall_flag
        rts                             ; the first lift of a pair
@fall_flag:
        lda Object::direction
        beq @top
        jmp drop_both_lifts             ; the rope broke
; This lift at the top: it stops 2 pixels lower, or the rope breaks when the
; player stands on the partner.
@top:
        lda #SCALE_TOP_Y
        cmp Object::y_pos
        bcc @partner_top
        lda Object::state
        cmp Object::on_lift
        bne @this_stops
        jmp start_lift_fall
@this_stops:
        lda #SCALE_STOP_Y
        sta Object::y_pos
        bra @stop
; The partner at the top: the same, with the player on this lift.
@partner_top:
        phd
        jsr scale_partner
        lda Object::y_pos
        pld
        cmp #SCALE_TOP_Y + 1            ; (after pld: it changes the flags)
        bcs @move                       ; the partner below the top
        lda Object::slot
        sec
        sbc #SLOT_ENEMY                 ; this lift's enemy number
        cmp Object::on_lift
        bne @partner_stops
        jmp start_lift_fall
@partner_stops:
        phd
        jsr scale_partner
        lda #SCALE_STOP_Y
        sta Object::y_pos
        pld
@stop:
        ldx Object::state
        jmp stop_lifts
; The move of this lift; move_partner_lift moves the partner the other way.
@move:
        lda Object::y_pos
        pha                             ; the row before the move
        lda Object::on_lift
        bpl @someone
; Nobody on the pair: it slows, and stops near 0.
        rep #P_M8
.a16
        lda Object::y_speed
        clc
        adc #SCALE_DRAG
        cmp #SCALE_REST                 ; unsigned: a rising speed is above it too
        sep #P_M8                       ; (the carry stays)
.a8
        bcc @still
        xba                             ; the whole pixels of the sum
        bmi @lower                      ; it rises: pulled down
        bra @raise                      ; it sinks: pulled up
@still:
        ldx Object::state
        jsr stop_lifts
        bra move_partner_lift
; The player on this lift: it sinks; on the partner: it rises.
@someone:
        lda Object::slot
        sec
        sbc #SLOT_ENEMY
        cmp Object::on_lift
        bne @raise
@lower:
        jsr lower_lift
        bra move_partner_lift
@raise:
        jsr raise_lift
        ; runs on into move_partner_lift

; ---------------------------------------------------------------------------
; move_partner_lift: the partner of the running balance lift moves by the
; opposite amount (its row + the row before - the row after, 8 bits: its Y
; high stays); the player stays on the lift he stands on; while this lift
; moves (its Y speed not 0) and list 1 holds less than $20 bytes in the
; original's record form (screen_list_1_original_end), the ropes: a record of this lift's two rope cells (the rope when it
; sinks, blank when it rises) and one of the partner's (the other way); each
; counts 5 bytes of the original's (its length + 10, as there).
;
; In:       D = the running lift's record; its row before the move on the
;           stack (one byte, above the return address)
; Out:      the partner's row; the player; list 1 and its two lengths
; Changes:  A, X, Y
; Time:     about 60 cycles, 220 with the ropes, and the routines it calls
; Original: $D4A7-$D540 (move_partner_lift, draw_partner_rope,
;           finish_rope_record)
; ---------------------------------------------------------------------------
move_partner_lift:
.a8
.i8
        pla
        sec
        sbc Object::y_pos               ; the row before - the row after
        tay
        phd
        jsr scale_partner               ; (keeps Y)
        tya
        clc
        adc Object::y_pos
        sta Object::y_pos               ; the partner's row only
        pld
; The player stays on the lift he stands on.
        lda Object::on_lift
        bmi @ropes
        jsr place_player_on_lift
; The ropes.
@ropes:
        rep #P_M8
.a16
        lda Object::y_speed
        sep #P_M8                       ; (the zero flag of the word stays)
.a8
        beq @done
        lda screen_list_1_original_end  ; list 1's length in the original's record bytes
        cmp #ROPE_LIST_ROOM
        bcs @done
        lda Object::y_speed_whole       ; bit 7: this lift rises
        jsr queue_lift_rope
        lda Object::y_speed_whole
        eor #$FF                        ; the partner moves the other way
        tay
        phd
        jsr scale_partner
        tya
        jsr queue_lift_rope
        pld
@done:
        rts

; ---------------------------------------------------------------------------
; queue_lift_rope: a REC_CELLS record of the two rope cells above a balance
; lift, at the end of list 1. The cells: the left cell of the 16-pixel
; column at the lift's X + 8, and $10 more in the easier areas (hard_mode_2
; 0), where the original clears the carry before the second add, so its page
; takes only that add's carry (L6: from X $F8 on the cells go into the other
; name table, 256 pixels to the left on the 512-pixel pair); the row of its Y
; / 8, or (Y + 8) / 8 when it rises (8 bits); for a lift at row $E8 or more
; the row's bit 1 is cleared (the original's low byte AND $BF: rows 30 and 31,
; the attribute area, become 28 and 29; a rising lift from row $F8 on gives
; row 0, which this does not change). The tiles: the rope when the lift
; sinks, blank when it rises. The ring column is name table x 32 + the cell
; column (src/secondsight/ring.s).
;
; In:       D = the lift's record; A8 bit 7: 1 when the lift rises
; Out:      the record at the end of screen_list_1; screen_list_1_end + 6,
;           screen_list_1_original_end + 5 (grow_list_1)
; Changes:  A, X, Y
; Time:     about 130 cycles
; Original: $D541-$D597 (queue_lift_rope), the record writes of
;           $D4D6-$D52F
; ---------------------------------------------------------------------------
queue_lift_rope:
.a8
.i8
        tay                             ; Y bit 7: it rises
; The row.
        bpl @sinks
        lda Object::y_pos
        clc
        adc #ROPE_RISE_ROW
        bra @row
@sinks:
        lda Object::y_pos
@row:
        lsr a
        lsr a
        lsr a                           ; the cell row, 0-31
        .assert ROPE_ROW_SHIFT = 3, error, "queue_lift_rope: three shifts"
        ldx Object::y_pos
        cpx #ROPE_LOW_Y
        bcc @row_set
        and #<~ROPE_ROW_FOLD
@row_set:
        pha
; The column, with the carry of the last add into the page.
        lda Object::x_pos
        clc
        adc #ROPE_X_SHIFT
        ldx hard_mode_2
        bne @carry
        clc                             ; the first add's carry is lost
        adc #ROPE_EASY_SHIFT
@carry:
        tax                             ; X = the pixel
        lda Object::x_pos + 1
        adc #0                          ; the page
        lsr a                           ; carry = its bit 0: the name table
        txa
        and #ROPE_COLUMN_MASK
        ror a                           ; the name table to bit 7, the 16-pixel column to bits 6-3
        lsr a
        lsr a                           ; name table x 32 + the even cell column: the ring column
; The record.
        ldx screen_list_1_end
        sta screen_list_1 + CELLS_COLUMN,x
        pla
        sta screen_list_1 + CELLS_ROW,x
        lda #REC_CELLS
        sta screen_list_1 + RECORD_KIND,x
        lda #ROPE_CELLS
        sta screen_list_1 + CELLS_COUNT,x
        tya
        bmi @blank
        lda rope_left_tile
        sta screen_list_1 + CELLS_TILES,x
        lda rope_right_tile
        bra @tiles
@blank:
        lda rope_blank_tile
        sta screen_list_1 + CELLS_TILES,x
@tiles:
        sta screen_list_1 + CELLS_TILES + 1,x
        lda #CELLS_TILES + ROPE_CELLS
        ldy #ROPE_ORIGINAL_RECORD
        jmp grow_list_1 ; both lengths of list 1
.assert CELLS_TILES = REC_CELLS_HEAD, error, "queue_lift_rope: the REC_CELLS fields"

; ---------------------------------------------------------------------------
; start_lift_fall: the rope of a balance pair breaks: 1000 points (the score
; number at the player's screen place), the running lift's fall flag, and
; stop_lifts. L7: the original means the partner's offscreen bits here, and
; its check_enemy_offscreen returns X = this lift and Y = 1; so the score
; and the flag go to the running lift (as needed), the partner's offscreen
; bits stay in offscreen_bits for this lift's drawing in this frame, and
; stop_lifts clears the Y speeds of this lift and of enemy 1, not of the
; partner (unless the partner is enemy 1): the partner falls with the speed
; it had, and whatever is in enemy slot 1 loses its Y speed once.
;
; In:       D = the running lift's record
; Out:      offscreen_bits + REL_ENEMY (the partner's); the score number;
; the fall flag; the speeds of stop_lifts
; Changes:  A, X, Y
; Time:     about 60 cycles and the routines it calls
; Original: $D598-$D5B0 (start_lift_fall)
; ---------------------------------------------------------------------------
start_lift_fall:
.a8
.i8
        phd
        jsr scale_partner
        jsr check_enemy_offscreen ; the partner's bits
        pld
        lda #SCORE_1000
        jsr start_score_number ; for this lift's slot
        lda rel_x + REL_PLAYER
        sta Object::score_x             ; at the player's screen place
        lda player_object + Object::y_pos
        sta Object::score_y
        lda #SCALE_ROPE_BROKEN
        sta Object::direction
        ldx #FALL_STOPPED_ENEMY         ; L7
        ; runs on into stop_lifts

; ---------------------------------------------------------------------------
; stop_lifts: the Y speed (both bytes) of the running lift and of the lift
; of enemy number X become 0.
;
; In:       D = the running lift's record; X8 = the other lift's enemy
;           number, 0-5 (its partner, or 1: start_lift_fall)
; Out:      the two Y speeds 0
; Changes:  A, X
; Time:     about 30 cycles
; Original: $D5B1-$D5BA (stop_lifts)
; ---------------------------------------------------------------------------
stop_lifts:
.a8
.i8
        rep #P_M8 | P_X8
.a16
.i16
        stz Object::y_speed             ; (clear_enemy_vspeed)
        txa
        xba
        tax                             ; that enemy's record - enemy_objects
        stz enemy_objects + Object::y_speed,x
        sep #P_M8 | P_X8
.a8
.i8
        rts
.assert OBJECT_PAGE = $100, error, "stop_lifts: an enemy number x 256 is its record's offset"

; ---------------------------------------------------------------------------
; drop_both_lifts: the rope broke: both lifts fall (drop_falling_lift: pull
; $20, top 3 down), this lift then its partner, and the player rides the
; lift he stands on.
;
; In:       D = the running lift's record
; Out:      both lifts moved; the player
; Changes:  A, X, Y
; Time:     about 40 cycles and the routines it calls
; Original: $D5BB-$D5D2 (drop_both_lifts)
; ---------------------------------------------------------------------------
drop_both_lifts:
.a8
.i8
        jsr drop_falling_lift ; this lift
        phd
        jsr scale_partner
        jsr drop_falling_lift           ; the partner
        pld
        lda Object::on_lift
        bmi @done
        jmp place_player_on_lift
@done:
        rts

; ---------------------------------------------------------------------------
; scale_partner: D = the record of the running balance lift's partner, the
; enemy number in its state (not checked: L9). The caller pushes its D before
; (phd) and pulls it after (pld).
;
; In:       D = the running lift's record
; Out:      D = the partner's record
; Changes:  A, X
; Keeps:    Y
; Time:     about 30 cycles
; Original: none
; ---------------------------------------------------------------------------
scale_partner:
.a8
.i8
        lda Object::state
        clc
        adc #SLOT_ENEMY
        tax
        object_from_x
        rts

; ---------------------------------------------------------------------------
; place_player_on_lift: the player stays on the lift of enemy number A
; (stand_on_vertical_lift with D = that lift: 32 pixels above its row, his Y
; speed 0).
;
; In:       A8 = the lift's enemy number, 0-5; any D
; Out:      the player's place
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 40 cycles and stand_on_vertical_lift
; Original: none (the original's calls with X = lift_collision)
; ---------------------------------------------------------------------------
place_player_on_lift:
.a8
.i8
        clc
        adc #SLOT_ENEMY
        tax
        phd
        object_from_x
        jsr stand_on_vertical_lift
        pld
        rts

; ---------------------------------------------------------------------------
; run_vertical_lift: the lift that moves up and down (kind $25): around its
; middle (lift_middle_y), above it lower_lift, from it on raise_lift (5/256
; a frame per frame, top 3): 64 pixels each side. The rest rule, only when
; both bytes of its Y speed are 0 at once: the Y fraction 0, and above
; lift_top_y it sinks 1 pixel each 8 frames. Then the player stays on it.
;
; In:       D = the lift's record
; Out:      the record moved; the player
; Changes:  A, X, Y
; Time:     about 30 cycles and the routines it calls
; Original: $D5D3-$D5FD (run_vertical_lift)
; ---------------------------------------------------------------------------
run_vertical_lift:
.a8
.i8
        rep #P_M8
.a16
        lda Object::y_speed
        sep #P_M8                       ; (the zero flag of the word stays)
.a8
        bne @swing
        stz Object::y_fraction
        lda Object::y_pos
        cmp Object::lift_top_y
        bcs @swing
        lda frame_count
        and #REST_SINK_FRAMES
        bne carry_player_on_lift
        inc Object::y_pos               ; the row only
        bra carry_player_on_lift
@swing:
        lda Object::y_pos
        cmp Object::lift_middle_y
        bcc @lower
        jsr raise_lift
        bra carry_player_on_lift
@lower:
        jsr lower_lift
        ; runs on into carry_player_on_lift

; ---------------------------------------------------------------------------
; carry_player_on_lift: when the player stands on this large lift (on_lift
; not negative), he stays on it (stand_on_vertical_lift).
;
; In:       D = the lift's record
; Out:      the player's place
; Changes:  A, X, Y
; Time:     about 10 cycles and stand_on_vertical_lift
; Original: $D5FE-$D606 (carry_player_on_lift)
; ---------------------------------------------------------------------------
carry_player_on_lift:
.a8
.i8
        lda Object::on_lift
        bmi @done
        jmp stand_on_vertical_lift
@done:
        rts

; ---------------------------------------------------------------------------
; run_horizontal_lift: the lift that sways sideways (kind $28): the X
; counters with the maximum $0E (14/16 pixel a frame at most, one sway in
; 240 frames) and its move; the player on it moves with it.
;
; In:       D = the lift's record
; Out:      the record moved; the player
; Changes:  A, X, Y
; Time:     about 20 cycles and the routines it calls
; Original: $D607-$D613 (run_horizontal_lift)
; ---------------------------------------------------------------------------
run_horizontal_lift:
.a8
.i8
        lda #SIDE_LIFT_MAXIMUM
        jsr count_x_moves
        jsr move_by_counters            ; A = the pixels moved
        ldx Object::on_lift
        bmi @done
        jmp shift_player_with_lift
@done:
        rts

; ---------------------------------------------------------------------------
; shift_player_with_lift: the player moves with the lift he stands on: his X
; word + the move, sign-extended (the original's X add and its page add with
; the carry or the borrow); lift_scroll = the move (the scroll adds it to his
; push and clears it); and he stays on the lift (stand_on_vertical_lift).
;
; In:       D = the lift's record; A8 = the move, signed pixels
; Out:      the player's X, lift_scroll, his place on the lift
; Changes:  A, X, Y
; Time:     about 30 cycles and stand_on_vertical_lift
; Original: $D614-$D630 (shift_player_with_lift, store_lift_carry)
; ---------------------------------------------------------------------------
shift_player_with_lift:
.a8
.i8
        sta lift_scroll
        rep #P_M8
.a16
        and #$00FF
        eor #$0080
        sec
        sbc #$0080                      ; the move as a signed word
        clc
        adc player_object + Object::x_pos
        sta player_object + Object::x_pos
        sep #P_M8
.a8
        jmp stand_on_vertical_lift

; ---------------------------------------------------------------------------
; run_drop_lift: the lift that drops while the player stands on it (kind
; $29): move_drop_lift (pull $7F, top 2 down) and the player stays on it.
; Its speed stays when he steps off.
;
; In:       D = the lift's record
; Out:      the record moved; the player
; Changes:  A, X, Y
; Time:     about 10 cycles and the routines it calls
; Original: $D631-$D63C (run_drop_lift)
; ---------------------------------------------------------------------------
run_drop_lift:
.a8
.i8
        lda Object::on_lift
        bmi @done
        jsr move_drop_lift
        jmp stand_on_vertical_lift
@done:
        rts

; ---------------------------------------------------------------------------
; run_right_lift: the lift that moves right once the player stands on it
; (kind $2A): it moves at its X speed (0 from its start); while he stands on
; it its speed is $10 (1 pixel a frame right) and he moves with it. The
; first standing frame moves it by the speed before the set (0).
;
; In:       D = the lift's record
; Out:      the record moved; the player
; Changes:  A, X, Y
; Time:     about 15 cycles and the routines it calls
; Original: $D63D-$D64E (run_right_lift)
; ---------------------------------------------------------------------------
run_right_lift:
.a8
.i8
        jsr move_enemy_sideways ; A = the pixels moved
        ldx Object::on_lift
        bmi @done
        ldx #RIGHT_LIFT_SPEED
        stx Object::x_speed
        jmp shift_player_with_lift
@done:
        rts

; ---------------------------------------------------------------------------
; move_big_lift: a large lift of a lift line (kinds $26, $27): its move
; (move_lift_vertically), then the player stays on it.
;
; In:       D = the lift's record
; Out:      the record moved; the player
; Changes:  A, X, Y
; Time:     about 40 cycles and stand_on_vertical_lift
; Original: $D64F-$D654 (move_big_lift)
; ---------------------------------------------------------------------------
move_big_lift:
.a8
.i8
        jsr move_lift_vertically
        bra carry_player_on_lift

; ---------------------------------------------------------------------------
; move_small_lift: a small lift of a lift line (kinds $2B, $2C): its move
; (move_lift_vertically), then, when the player stands on one of its two
; boxes (on_lift 1 or 2), he stays on it (stand_on_small_lift). During the
; hold the lift does not move but the player is still put on it.
;
; In:       D = the lift's record
; Out:      the record moved; the player
; Changes:  A, X, Y
; Time:     about 40 cycles and stand_on_small_lift
; Original: $D655-$D65A (move_small_lift), $D671-$D679
;           (carry_player_small_lift)
; ---------------------------------------------------------------------------
move_small_lift:
.a8
.i8
        jsr move_lift_vertically
        lda Object::on_lift
        beq @done
        jmp stand_on_small_lift ; A = his box
@done:
        rts

; ---------------------------------------------------------------------------
; move_lift_vertically: the move of a lift of a lift line when the timers
; run: the Y fraction and row, one word, + the Y speed (15/16 pixel a frame
; up or down, from the start): no gravity, and the Y high does not
; change, so the row wraps at 256 and the lifts of a line come round from the
; bottom to the top or back (the word's carry is the original's carry from
; the fraction into the row; the carry out of the row is lost, as there).
;
; In:       D = the lift's record
; Out:      Object::y_fraction, the row of Object::y_pos
; Changes:  A
; Time:     about 25 cycles
; Original: $D65B-$D670 (move_lift_vertically)
; ---------------------------------------------------------------------------
move_lift_vertically:
.a8
.i8
        lda timer_hold
        bne @done
        rep #P_M8
.a16
        lda Object::y_fraction          ; the fraction, then the row
        clc
        adc Object::y_speed
        sta Object::y_fraction
        sep #P_M8
.a8
@done:
        rts
