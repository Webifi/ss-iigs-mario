; Collision tests for the player, enemies, fireballs, blocks and lifts.
; game_core and the object code call these routines using the records in
; state.inc. Background tests probe the two collision buffers; object tests
; compare rectangles in box_corners. scripts/collision_data.py prepares the
; block classes, test points and box shapes.
;
; Player and fireball tests run before each enemy's collision and move.
; Hammer tests run later with the miscellaneous objects. Fireball/enemy and
; player/enemy contacts run on even frames; enemy/enemy and hammer/player
; contacts run on odd frames. Box builds, tile tests and lift tests run
; every frame. Hits can change object state, score, sound and screen records.
;
; A, X and Y are 8-bit unless a routine says otherwise. DBR is bank 0;
; D points to the object record named by the routine. Other records use the
; group labels in state.inc.

.a8
.i8

; ---- Values of the original program --------------------
; The test points of the tiles (rows of tile_point_x and tile_point_y). The player's sets: tile_point_sets gives the first point of a
; set; the set's seven points follow it in this order.
POINT_HEAD      = 0             ; + the set's first point: the head
POINT_LEFT_FOOT = 1
POINT_RIGHT_FOOT = 2
POINT_LEFT_UPPER = 3            ; the sides: left upper and lower, then right upper and lower
POINT_SET_BIG   = 0             ; tile_point_sets index: big
POINT_SET_SWIM  = 1             ; big, in a water area
POINT_SET_SMALL = 2             ; small or crouching
POINT_ENEMY_FEET = 21
POINT_ENEMY_LEFT = 22
POINT_ENEMY_RIGHT = 23
POINT_FIREBALL  = 26
POINT_VINE      = 27            ; the vine object's probe (run_vine)
; The metatiles that the rules name.
METATILE_PIPE_LEFT = $10        ; the left and right halves of an enterable pipe's top
METATILE_PIPE_RIGHT = $11
METATILE_SIDE_PIPE_TOP = $1C    ; a side pipe's mouth: top, bottom
METATILE_SIDE_PIPE = $1F
METATILE_BUMPED = $23           ; the solid blank in the cell of a block that moves
METATILE_POLE_BALL = $24        ; the flagpole: the ball, the pole
METATILE_POLE   = $25
METATILE_COIN_BRICK_PLAIN = $5D
METATILE_HIDDEN_COIN = $5F
METATILE_HIDDEN_1UP = $60
METATILE_SPRING_TOP = $67
METATILE_SPRING_BOTTOM = $68
METATILE_WATER_SIDE_PIPE_TOP = $6B ; the water areas' side pipe mouth: top, bottom
METATILE_WATER_SIDE_PIPE = $6C
METATILE_WATER_COIN = $C3
METATILE_AXE    = $C5
; Directions (Object::direction, player_facing).
DIR_SWAP        = FACING_RIGHT | FACING_LEFT ; XOR: the other direction
; An enemy's state.
ENEMY_SHELL_STATES = 6          ; 6 and up: a moving shell, for the shell test
; The box numbers: box_corners + CORNERS x the number. A box's number is its
; record's slot, but for the misc objects.
CORNERS         = 4             ; left, top, right, bottom
CORNER_LEFT     = 0
CORNER_TOP      = 1
CORNER_RIGHT    = 2
CORNER_BOTTOM   = 3
BOX_OF_PLAYER   = 0
BOX_OF_MISC     = 9             ; + the misc number: boxes 9-17 (misc slots 13-21)
.assert BOX_OF_PLAYER = SLOT_PLAYER && SLOT_ENEMY = 1 && SLOT_FIREBALL = 7, error, "the box number is the slot"
.assert BOX_OF_MISC + MISC_SLOTS = BOX_SLOTS, error, "box_corners holds the misc boxes last"

; ---- Values of this part -------------------------------------------------
LOW_NIBBLE      = $0F
ALL_BITS        = $FF           ; EOR with every bit; with INC, the other sign
ROW_MASK        = $F0           ; the top of a 16-pixel metatile row
BUFFER_COLUMNS  = 16            ; the metatile columns of one collision buffer
RING_COLUMN_MASK = 2 * BUFFER_COLUMNS - 1 ; the columns of the two buffers: bit 4 is the buffer
STATUS_BAR_HEIGHT = $20         ; buffer row 0 starts at screen Y $20, below the status bar
BUFFER_PAIR_CELLS = 2 * COLLISION_BUFFER ; the cells of the two buffers: an index from here on is past buffer 2
PAST_BUFFER_BYTES = 3 * BUFFER_COLUMNS ; the original's bytes after buffer 2 that a wrapped row reaches: $06A0-$06CF
PAST_ZERO       = 0             ; past_buffer_bytes: a byte that the original never writes (0)
PAST_FF         = 1             ; a byte that finish_area_setup sets to $FF at each area start
PAST_CONSTANTS  = 2             ; entries below this are constants, not addresses
AREA_START_FILL = $FF           ; the byte of PAST_FF
COIN_SLOT_BYTES = 5             ; state.inc jump_coin_slot: the original's 5 bytes $06B7-$06BB
SCREEN_HALF     = $80           ; the screen's middle: its left X + 128
WRAP_RIGHT      = $FF           ; fix_box_wrap: a right edge that wrapped past 255
WRAP_LEFT       = $A0           ; a left edge from this up wrapped below 0
NO_BOX          = $FF           ; the four corners of a box that is not there
ENEMY_LEFT_MASK = $44           ; enemy_hit_box: row 2 or column 2 off (the enemy at or left of the screen's left edge)
ENEMY_RIGHT_MASK = $48          ; row 2 or column 1 off (right of it)
LIFT_LEFT_MASK  = $04           ; small_lift_hit_box: column 2 off
LIFT_RIGHT_MASK = $08           ; column 1 off
LIFT_OFF_SCREEN = $FE           ; find_x_offscreen from this up: the large lift has no box
PLAYER_LOW_EDGE = $D0           ; player_out_of_range: a player on the screen at this Y or lower
; The player against the tiles.
WALL_RIGHT      = 1             ; wall_side: a wall at the player's right
WALL_LEFT       = 2             ; at his left
PLAYER_TILE_LIMIT = $CF         ; no tile test from this Y down
HEAD_DEPTH      = 4             ; a head hit needs the Y's low nybble at 4 or more
HEAD_STOP_SPEED = 1             ; the Y speed after a head hit: the jump ends
FOOT_DEPTH      = 5             ; feet this deep in a metatile: a wall, not a floor
SIDE_TOP_LIMIT  = $20           ; the upper side point from this Y on
SIDE_LOWER_LIMIT = $08          ; the lower side point from this Y on
SIDE_STOP_FRAMES = $10          ; the side timer of a wall stop (TIMER_SIDE_COLLISION)
SPEED_RIGHTWARD = 1             ; block_player_sideways: the X speed - 1 not negative is a move right
WALL_STEP       = 1             ; a wall pushes the player back 1 pixel
WAIT_FIRST_PAGE = 0             ; area_change_waits: the screen at page 0, at a later page
WAIT_LATER_PAGES = 1
GRAB_FIRST      = 6             ; a pole or vine catches the player when his X's low nybble is 6-9
GRAB_LAST       = 9
VINE_TOP_LIMIT  = $20           ; a vine above this Y: the climb out of the top of the screen
VINE_EDGE       = $10           ; a player this close to the screen's left edge faces left on a vine
FLAG_HEIGHTS    = 4             ; flagpole_score_heights: entries 1-4 (entry 0 has no reader)
AXE_RUN_SPEED   = $18           ; the player's X speed after the axe
SPRING_GRAVITY  = $70           ; land_on_spring: the jump gravity
SPRING_FORCE    = $F9           ; the force of the spring
SPRING_FRAMES   = 3             ; TIMER_SPRING
SPRING_FIRST_STEP = 1           ; spring_anim
PIPE_FRAMES     = $30           ; down a pipe: frames until the area changes
WARP_GROUP      = $03           ; warp_zone: the group of its pipes in the low two bits
WARP_PIPES      = 3             ; warp_pipe_worlds: 3 pipes in each group
WARP_LEFT_PIPE  = $60           ; the player's X below this: the left pipe
WARP_MIDDLE_PIPE = $A0          ; below this: the middle pipe
; The block hits.
BLOCK_CENTRE    = 8             ; set_block_place: the player's middle
BLOCK_Y_BIG     = 0             ; block_y_by_size: a big player standing, a small or crouching one
BLOCK_Y_SMALL   = 1
BLOCK_RISE_SPEED = $FE          ; the bumped block's Y speed
BRICK_TENS      = 5             ; a broken brick: 50 points (digit_add place 5 is the tens)
BLOCK_SELECT_SWAP = 1           ; sprite_offset_select XOR this: the other block object
; The enemies against the tiles.
ENEMY_TILE_TOP  = 6             ; enemy_y_plus_62: the enemy tile tests for Y 6 to $C1
ENEMY_TILE_BOTTOM = $C1
SPINY_TILE_TOP  = $25           ; a spiny above this Y has no tile test
ENEMY_FOOT_TOP  = 8             ; an enemy lands when its Y's low nybble is 8-12
ENEMY_FOOT_RANGE = 5
ENEMY_WAKE_TIME = $10           ; slow ticks that a flipped enemy lies upside down
SPINY_WAKE_TIME = 0             ; a spiny's
SPINY_WALK_SPEED = 8            ; the X speed of a spiny that hatches
SPINY_TURN_FRAMES = $07         ; a spiny turns toward the player unless frame_count AND 7 is 0
ENEMY_SIDE_TOP  = $20           ; no side test above this Y
ENEMY_STAND_Y   = $08           ; enemy_lands: the Y's low nybble on its row
ENEMY_STUN_KEEP = $F0           ; stun_enemy keeps the state's flag bits (the high nybble)
STUN_SPEED      = $FD           ; the Y speed of a stun
STUN_SPEED_SLOW = $FF           ; in a water area, and for a blooper
STUN_DEMOTE     = 9             ; stun_enemy_by_kind: A of 9 or $0D-$10 turns the kind into A AND 1
STUN_DEMOTE_FIRST = $0D
STUN_DEMOTE_LAST = $10
KOOPA_COLOUR    = $01           ; kind AND this: 0 green koopa, 1 red koopa
JUMP_TEST_SPEED = 2             ; enemy_land_check: Y speed + 2 from 3 up (1-$7F, $80-$FD): it falls
JUMP_FALLING    = 3
ENEMY_HOP_SPEED = $FD           ; the jumping paratroopa's and the star's jump
HAMMER_KEEP     = $88           ; hammer_bro_tile_check: the state bits that the landing keeps
HAMMER_IN_AIR   = $01           ; the hammer brother's state bit 0: in the air
HAMMER_PLAIN_JUMP = 0           ; launch_hammer_bro_jump's jump kind (the original's t0)
BUMPED_ENEMY_SPEED = $FC        ; kill_enemy_on_bumped_block: the Y speed
; The fireballs.
FIREBALL_TEST_TOP = $18         ; no tile test above this Y
FIREBALL_BOUNCE_SPEED = $FD
FIREBALL_ROW_MASK = $F8         ; the bounce puts the fireball on an 8-pixel step
FIREBALL_BURST  = $80           ; the fireball's state: it bursts
FIREBALL_BOUNCING = 1           ; Object::bounce: the fireball bounced and has not left the ground
FIREBALL_TESTED_ENEMIES = 5     ; fireballs_vs_enemies tests enemy numbers 4-0, never 5
BOWSER_HOP_SPEED = $FE          ; defeated Bowser's small hop
BOWSER_FALL_WORLDS = 3          ; worlds 1-3: the defeated state + BOWSER_EARLY_STATE
BOWSER_EARLY_STATE = 3
PIRANHA_DROP    = 25            ; knock_out_enemy: the piranha plant's Y + 25
; The player against the enemies.
CONTACT_PLAYER  = $01           ; Object::collision of an enemy: bit 0, the player touches it
HAMMER_TOUCHED  = 1             ; Object::misc_hit: the hammer touches the player
STOMP_REACH     = 12            ; kinds 7 and up: a stomp when the player's Y + 12 is above the enemy's Y
KICK_SCORE_TIMES = 3            ; a kick of a shell whose timer is below 3: shell_chain_scores
STOMP_GROUP_FLYER = 0           ; stomp_score_codes index: cheep-cheep, bullet bills, lava ball
STOMP_BOUNCE    = $FC           ; bounce_player: the player's Y speed
STOMP_BOUNCE_LOW = $FD          ; after the stomp of a flyer, a hammer brother, Lakitu, a blooper
STUN_LIFT       = 2             ; stun_enemy lifts the enemy 2 pixels
INJURY_TIME     = 8             ; TIMER_INJURY, slow ticks of blinking
STAR_TIME       = $23           ; TIMER_STAR, slow ticks
DEATH_JUMP_SPEED = $FC
HURT_STATE      = PLAYER_JUMPING ; the player's state in the injury and death tasks
TIMER_HOLD_ALL  = $FF           ; timer_hold: the timers wait (the frame counts it down)
; The lifts.
LIFT_NOT_ON     = $FF           ; a large lift's Object::on_lift: the player is not on it
SMALL_LIFT_PASSES = 2           ; a small lift is tested at its place and 128 pixels lower
SMALL_LIFT_HIDE = $02           ; offscreen_bits: column 3 off ends the small lift's test
SMALL_LIFT_COPY = $80           ; the second box is 128 pixels lower
LIFT_HEAD_REACH = 4             ; resolve_lift_hit: under the lift
LIFT_FOOT_REACH = 6             ; on it
LIFT_SIDE_REACH = 8             ; at its left side
LIFT_RIGHT_REACH = 9            ; at its right side (the difference less 1)
PLAYER_HEIGHT   = $20           ; the player stands 32 pixels above a lift's Y

; ---- The variables of this part ------------------------------------------
.segment "AREASTATE"
; The place of the last probe (probe_tile), in the original's two values.
; Written by probe_tile (and check_coin_above_block: the row above); read by
; this part's tile rules, the block records (bump_block_from_below), the
; screen part's block pictures (blank_block_picture, erase_coin_or_axe)
; and the objects part (launch_jump_coin, the vine's probe).
                                ; byte; the high byte stays 0, so a 16-bit read is the offset as a word
; check_player_vs_tiles.
player_points:  .res 1          ; the first test point of the player's set (tile_point_sets)
feet_left:      .res 1          ; the metatile under the left foot (enter_pipe_check)
feet_right:     .res 1          ; under the right foot
wall_side:      .res 1          ; block_player_sideways: WALL_RIGHT or WALL_LEFT; also the side test's pass
bumped_metatile: .res 1         ; bump_block_from_below: the metatile that the head hit (hit_block's gift)
; player_enemy_gap: written by it, read by its callers (enemy code reads the low byte too).
enemy_gap:      .res 2          ; the enemy's X - the player's X: page and pixel
; fix_box_wrap.
box_middle:     .res 2          ; the world X of the screen's middle
; compute_hit_box_corners.
box_screen_x:   .res 1          ; the object's screen X (rel_x of its group)
box_screen_y:   .res 1          ; its screen Y
; fireballs_vs_enemies.
fireball_box:   .res 1          ; the fireball's corners: CORNERS x its box number
fireball_slot:  .res 1          ; the fireball's slot
fireball_victim: .res 1         ; the enemy number that the loop tests
; enemies_bump_enemies and resolve_enemy_bump.
bump_first:     .res 2          ; the first enemy's record (the D of the call)
bump_first_bit: .res 1          ; its bit in the other enemies' contact bits (enemy_bit_masks)
bump_first_box: .res 1          ; its corners
bump_second:    .res 1          ; the second enemy's number
; The lift tests.
lift_player_value: .res 1       ; the value that Object::on_lift takes when the player stands on the lift
                                ; (the tested large lift's enemy number, or a small lift's pass)

.segment "GAMEPLAY"

; ===========================================================================
; The hit boxes
; ===========================================================================

; ---------------------------------------------------------------------------
; compute_hit_box_corners: the box of an object from its place on the screen
; and its box kind: each edge is the screen X or Y plus the kind's offset
; (hit_box_shapes), each add in 8 bits and wrapping, with no carry from one
; edge to another, as the original's.
;
; In:       A8 I8; D = the object's record (Object::box: its box kind);
;           X = the box number (0-17); Y = the screen place group (REL_*:
;           rel_x and rel_y of that group hold the object's place)
; Out:      box_corners + CORNERS x box: left, top, right, bottom;
;           X = CORNERS x box
; Changes:  A, X, Y, box_screen_x, box_screen_y
; Keeps:    D
; Time:     about 90 cycles
; Original: $E29C-$E2DD (compute_hit_box_corners); the player's box (box 0,
;           group 0) is built by control_player with it
; ---------------------------------------------------------------------------
compute_hit_box_corners:
.a8
.i8
        lda rel_x,y
        sta box_screen_x
        lda rel_y,y
        sta box_screen_y
        lda Object::box
        asl a
        asl a
        tay                             ; the kind's row of hit_box_shapes
        txa
        asl a
        asl a
        tax                             ; the box's corners
        lda box_screen_x
        clc
        adc hit_box_shapes+CORNER_LEFT,y
        sta box_corners+CORNER_LEFT,x
        lda box_screen_x
        clc
        adc hit_box_shapes+CORNER_RIGHT,y
        sta box_corners+CORNER_RIGHT,x
        lda box_screen_y
        clc
        adc hit_box_shapes+CORNER_TOP,y
        sta box_corners+CORNER_TOP,x
        lda box_screen_y
        clc
        adc hit_box_shapes+CORNER_BOTTOM,y
        sta box_corners+CORNER_BOTTOM,x
        rts

; ---------------------------------------------------------------------------
; fix_box_wrap: a box whose X edges wrapped past a screen edge is clipped to
; the edge. The box's object is right of the screen's middle (its world X at
; or above the left edge + 128) or left of it; on the right side a right edge
; below 128 wrapped past 255 and becomes 255, with the left edge when it
; wrapped too; on the left side a left edge from $A0 up wrapped below 0 and
; becomes 0, with the right edge when it is 128 or more. The world X is
; that of the slot whose number is the box number: the object's own slot,
; but for a misc box (box 9 + m) slot 9 + m, a block object or another misc
; object: its side of the screen clips the hammer's box.
;
; In:       A8 I8; X = CORNERS x the box number; screen_left
; Out:      box_corners of the box
; Changes:  A, Y, box_middle
; Keeps:    X, D
; Time:     about 80 cycles
; Original: $E2DE-$E324 (fix_box_wrap)
; ---------------------------------------------------------------------------
fix_box_wrap:
.a8
.i8
        phx
; The world X of slot (box number) against the screen's middle.
        ax16
        txa
        lsr a
        lsr a                           ; the box number: the slot whose X the original reads
        xba                             ; x OBJECT_PAGE: the record's offset in objects
        tay
        lda screen_left
        clc
        adc #SCREEN_HALF
        sta box_middle
        lda objects+Object::x_pos,y
        cmp box_middle                  ; carry clear: the object is left of the middle
        ax8
        plx
        bcc @left_side
; Right of the middle: a right edge below 128 wrapped past 255.
        lda box_corners+CORNER_RIGHT,x
        bmi @done
        lda #WRAP_RIGHT
        sta box_corners+CORNER_RIGHT,x
        ldy box_corners+CORNER_LEFT,x
        bmi @done
        sta box_corners+CORNER_LEFT,x   ; the left edge wrapped too
@done:  rts
; Left of the middle: a left edge from $A0 up wrapped below 0.
@left_side:
        lda box_corners+CORNER_LEFT,x
        bpl @done
        cmp #WRAP_LEFT
        bcc @done
        stz box_corners+CORNER_LEFT,x
        lda box_corners+CORNER_RIGHT,x
        bpl @done
        stz box_corners+CORNER_RIGHT,x  ; the right edge is past 128 too
        rts
.assert OBJECT_PAGE = $100, error, "fix_box_wrap: a record's offset is the slot in the high byte"

; ---------------------------------------------------------------------------
; fireball_hit_box: the box of a fireball (its box number is its slot), then
; the wrap clip.
;
; In:       A8 I8; D = the fireball's record; its screen place (rel_x,
;           rel_y of REL_FIREBALL)
; Out:      its box_corners
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 180 cycles
; Original: $E22D-$E235 (fireball_hit_box)
; ---------------------------------------------------------------------------
fireball_hit_box:
.a8
.i8
        ldx Object::slot
        ldy #REL_FIREBALL
        jsr compute_hit_box_corners
        jmp fix_box_wrap

; ---------------------------------------------------------------------------
; misc_hit_box: the box of a misc object (a hammer): box 9 + its misc number,
; then the wrap clip, which reads the X of slot 9 + m.
;
; In:       A8 I8; D = the misc object's record; its screen place (REL_MISC)
; Out:      its box_corners
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 180 cycles
; Original: $E236-$E242 (misc_hit_box)
; ---------------------------------------------------------------------------
misc_hit_box:
.a8
.i8
        lda Object::slot
        sec
        sbc #SLOT_MISC - BOX_OF_MISC
        tax
        ldy #REL_MISC
        jsr compute_hit_box_corners
        jmp fix_box_wrap

; ---------------------------------------------------------------------------
; enemy_hit_box, small_lift_hit_box: the box of an enemy (or a small lift),
; or no box while the enemy is off the screen by the rule of its masks
; (box_or_hide).
;
; In:       A8 I8; D = the enemy's record; offscreen_bits + REL_ENEMY and
;           its screen place (the enemy's routine computed them)
; Out:      Object::offscreen, its box_corners
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 220 cycles
; Original: $E243-$E24B (enemy_hit_box), $E24C-$E251 (small_lift_hit_box)
; ---------------------------------------------------------------------------
enemy_hit_box:
.a8
.i8
        lda #ENEMY_LEFT_MASK
        ldy #ENEMY_RIGHT_MASK
        bra box_or_hide
small_lift_hit_box:
.a8
.i8
        lda #LIFT_LEFT_MASK
        ldy #LIFT_RIGHT_MASK

; ---------------------------------------------------------------------------
; box_or_hide: the enemy offscreen mask, then the box. The mask is the left
; one when the enemy's world X is at or left of the screen's left edge, else
; the right one; Object::offscreen = the mask AND the enemy's offscreen bits.
; Not 0: the four corners become NO_BOX (no test of the game overlaps such a
; box). Else build_enemy_hit_box.
;
; In:       A8 I8; A = the left mask, Y = the right mask; D = the enemy's
;           record
; Out:      Object::offscreen, the box
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 210 cycles with a box
; Original: $E252-$E272 (box_or_hide), $E289-$E29B (the no-box part)
; ---------------------------------------------------------------------------
box_or_hide:
.a8
.i8
        tax                             ; the left mask
        a16
        lda Object::x_pos
        sec
        sbc screen_left
        a8
        beq @left                       ; exactly at the left edge
        bmi @left
        tyx                             ; right of the edge: the right mask
@left:  txa
        and offscreen_bits+REL_ENEMY
        sta Object::offscreen
        bne enemy_no_box
        jmp build_enemy_hit_box

; ---------------------------------------------------------------------------
; enemy_no_box: an enemy slot has no box: its four corners become NO_BOX.
;
; In:       A8 I8; D = the enemy's record
; Out:      its box_corners
; Changes:  A, X
; Keeps:    Y, D
; Time:     about 30 cycles
; Original: $E289-$E29B (the no-box part of box_or_hide)
; ---------------------------------------------------------------------------
enemy_no_box:
.a8
.i8
        lda Object::slot
        asl a
        asl a
        tax
        lda #NO_BOX
        sta box_corners+CORNER_LEFT,x
        sta box_corners+CORNER_TOP,x
        sta box_corners+CORNER_RIGHT,x
        sta box_corners+CORNER_BOTTOM,x
        rts

; ---------------------------------------------------------------------------
; large_lift_hit_box: a large lift's box, or none when the lift lies more
; than 47 pixels left of the screen or right of its right edge (the
; horizontal offscreen value $FE or $FF). Object::offscreen is not written.
;
; In:       A8 I8; D = the lift's record
; Out:      its box_corners
; Changes:  A, X, Y
; Keeps:    D
; Time:     find_x_offscreen, then about 180 cycles
; Original: $E273-$E27B (large_lift_hit_box)
; ---------------------------------------------------------------------------
large_lift_hit_box:
.a8
.i8
        jsr find_x_offscreen            ; the sprite part: A = the lift's column bits
        cmp #LIFT_OFF_SCREEN
        bcs enemy_no_box
        ; falls into build_enemy_hit_box

; ---------------------------------------------------------------------------
; build_enemy_hit_box: the box of an enemy slot (its box number is its slot)
; from the enemy group's screen place, then the wrap clip.
;
; In:       A8 I8; D = the enemy's record; its screen place (REL_ENEMY)
; Out:      its box_corners
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 180 cycles
; Original: $E27C-$E288 (build_enemy_hit_box)
; ---------------------------------------------------------------------------
build_enemy_hit_box:
.a8
.i8
        ldx Object::slot
        ldy #REL_ENEMY
        jsr compute_hit_box_corners
        jmp fix_box_wrap

; ---------------------------------------------------------------------------
; player_vs_object: box B against the player's box (box A = box 0).
; hit_box_overlap: box B against box A.
;
; Each axis (X: left and right; Y: top and bottom) is tested with the
; original's six cases on the 8-bit edges, with bl, bh the low and high
; edges of B and al, ah those of A:
;   bl = al: touch.                 bl < al, bl = ah: touch.
;   bl < al, bl < ah: touch when A wraps (ah < al) or bh >= al.
;   bl < al, bl > ah: touch when B wraps (bh < bl) or bh >= al.
;   bl > al, bl <= ah: touch.
;   bl > al, bl > ah: touch when B wraps (bl > bh) and bh >= al.
; For boxes that do not wrap this is the plain overlap, edges included. The
; Y axis is tested only when the X axis touches. The cases are kept because
; the boxes that fix_box_wrap leaves wrapped (7, 9) and the
; Y edges near 255 depend on them.
;
; In:       A8 I8; Y = CORNERS x box B; X = CORNERS x box A
;           (player_vs_object sets X)
; Out:      carry set when the boxes touch
; Changes:  A (player_vs_object: X)
; Keeps:    X, Y, D
; Time:     40-90 cycles
; Original: $E325-$E326 (player_vs_object), $E327-$E387 (hit_box_overlap)
; ---------------------------------------------------------------------------
player_vs_object:
.a8
.i8
        ldx #CORNERS * BOX_OF_PLAYER
hit_box_overlap:
.a8
.i8
        jsr boxes_touch_on_axis         ; X: left and right
        bcc @done
        inx                             ; Y: top and bottom
        iny
        jsr boxes_touch_on_axis
        dex
        dey
@done:  rts

; ---------------------------------------------------------------------------
; boxes_touch_on_axis: one axis of hit_box_overlap, by its six cases.
;
; In:       A8 I8; Y = the box_corners offset of B's low edge (its high edge
;           is 2 bytes on), X = that of A's low edge
; Out:      carry set when they touch on this axis
; Changes:  A
; Keeps:    X, Y, D
; Time:     20-40 cycles
; Original: $E327-$E387 (one pass of hit_box_overlap's loop)
; ---------------------------------------------------------------------------
boxes_touch_on_axis:
.a8
.i8
        lda box_corners,y               ; bl
        cmp box_corners,x               ; al
        beq @touch
        bcs @b_above
        cmp box_corners+CORNER_RIGHT,x  ; ah
        beq @touch
        bcc @b_below_both
; bl < al and bl > ah: A wraps. Touch when B wraps too or reaches A.
        lda box_corners+CORNER_RIGHT,y  ; bh
        cmp box_corners,y
        bcc @touch                      ; bh < bl: B wraps
        cmp box_corners,x               ; carry: bh >= al
        rts
; bl below al and ah: touch when A wraps or B reaches A.
@b_below_both:
        lda box_corners+CORNER_RIGHT,x
        cmp box_corners,x
        bcc @touch                      ; ah < al: A wraps
        lda box_corners+CORNER_RIGHT,y
        cmp box_corners,x               ; carry: bh >= al
        rts
; bl above al: touch when bl is inside A, or B wraps and reaches A.
@b_above:
        cmp box_corners+CORNER_RIGHT,x
        bcc @touch
        beq @touch                      ; bl <= ah
        cmp box_corners+CORNER_RIGHT,y
        bcc @apart
        beq @apart                      ; bl <= bh: B does not wrap
        lda box_corners+CORNER_RIGHT,y
        cmp box_corners,x               ; carry: bh >= al
        rts
@apart: clc
        rts
@touch: sec
        rts

; ===========================================================================
; The tile tests
; ===========================================================================

; probe_cell_index: X16 = the index of the probe's cell in the original's two
; buffers, one after the other: buffer 1's 208 cells, then buffer 2's; an
; index from BUFFER_PAIR_CELLS up is the original's RAM after buffer 2.
; A column of buffer 2 (16-31) starts COLLISION_BUFFER - BUFFER_COLUMNS above
; its number. In: A8 I8; probe_column, probe_row. Out: A16 I16; X = A = the
; index.
.macro probe_cell_index
        lda probe_column
        cmp #BUFFER_COLUMNS
        bcc :+
        adc #COLLISION_BUFFER - BUFFER_COLUMNS - 1 ; the carry adds the 1
:
        ax16
        and #LOW_BYTE
        clc
        adc probe_row                   ; the row offset as a word
        tax
.endmacro

; Original: $D6D9-$E434 and $BCED-$BE40. Merged or split for the port:
;   probe_tile takes every test point: it holds the original's entries
;   probe_tile_feet/head/side ($E3E8-$E3EF), tile_at_enemy_point ($E388),
;   tile_at_fireball ($E39C), tile_lookup_return_y ($E3A3),
;   tile_lookup_finish ($E3A5) and return_tile_part ($E42B); a caller that
;   needs the low nybble of its object's X or Y ($04) reads it itself.
;   check_player_vs_tiles holds check_player_feet ($DCF6) and its side
;   test, whose side metatile goes to check_side_tile; block_player_sideways
;   holds stop_x_speed ($DF66) and halt_player_sideways ($DDFF);
;   landing_state_for_kind holds store_enemy_state ($E0FC); the gifts of
;   hit_block ($BDD2-$BDE7) are local to it; collect_powerup holds
;   become_fiery ($D847); player_hits_enemy goes on in stomp_check and
;   enemy_stomped; the box offsets (enemy_box_offset, enemy_box_offset_for
;   $DC52-$DC61) are 4 x the slot in each caller; enemy_no_box is the no-box
;   part of box_or_hide ($E289); is_solid_tile, is_climbable_tile and
;   palette_class_of_tile ($DF8F-$DFB8) are one lookup of metatile_class;
;   is_hidden_block ($DEBD) and is_spring_tile ($DEDD) are compares in their
;   callers; tile_under_enemy keeps its name for the point of the feet.
;

; ---------------------------------------------------------------------------
; probe_tile: the metatile at a test point of an object, and its place.
; The column is bits 4-8 of the object's world X plus the point's X offset
; (the page's low bit picks the buffer: column 16-31 for an odd page); the
; row offset is (the Y pixel plus the point's Y offset) AND $F0 less the
; status bar, in 8 bits as the original's: a point above buffer row 0 or
; below row 12 wraps, and read_probe_cell reads what the original reads then.
;
; In:       A8 I8; D = the object's record; Y = the test point (POINT_*)
; Out:      A = the metatile, zero flag set when it is 0;
;           probe_column, probe_row = its place
; Changes:  A, X, probe_column, probe_row
; Keeps:    Y, D
; Time:     about 110 cycles
; Original: $E3F0-$E42A (probe_tile) with its entries (file header)
; ---------------------------------------------------------------------------
probe_tile:
.a8
.i8
; The column: one 16-bit add of the offset to page and pixel gives the
; original's carry into the page.
        lda tile_point_x,y
        a16
        and #LOW_BYTE
        clc
        adc Object::x_pos
        lsr a
        lsr a
        lsr a
        lsr a
        a8
        and #RING_COLUMN_MASK
        sta probe_column
; The row offset: 8-bit add and subtract (the Y high byte takes no part).
        lda Object::y_pos
        clc
        adc tile_point_y,y
        and #ROW_MASK
        sec
        sbc #STATUS_BAR_HEIGHT
        sta probe_row
        ; falls into read_probe_cell

; The original's results that come from where its collision buffers lie
; (buffer 1 at $0500, buffer 2 at $05D0 right after it) are reproduced on
; purpose: the place of a probe is a ring column 0-31 (bit 4: the buffer) and
; a row offset (16 x the row), the original's two values; read_probe_cell
; and store_probe_cell take a row offset that wrapped as the original's
; does, to the first rows of buffer 2 for a column of buffer 1 and to the
; original's RAM after buffer 2 for a column of buffer 2 (past_buffer_bytes);
; snap_player_to_vine sets the page only in column 0 of buffer 1 ; launch_jump_coin reads the buffer bit of
; probe_column.
;

; ---------------------------------------------------------------------------
; read_probe_cell: the metatile at the probe's place. A row offset that
; wrapped to $D0-$F0 reads past the column's 13 rows as the original's
; indirect read does: for a column of buffer 1 the cells of buffer 2's rows
; 0-2 in the same column (buffer 2 follows buffer 1 in the original's RAM),
; for a column of buffer 2 the original's RAM after buffer 2
; (read_past_buffers). This happens to fireballs that fall into a pit (Y $E8
; and more), to enemies at Y 6 or 7, and to the side test of the jumping
; paratroopa and the star below Y $DC.
;
; In:       A8 I8; probe_column, probe_row
; Out:      A = the metatile, zero flag set when it is 0
; Changes:  A, X
; Keeps:    Y, D
; Time:     about 50 cycles in the buffers
; Original: the read of probe_tile ($E417); the reads of the vine and
;           of check_coin_above_block, bump_block_from_below
; ---------------------------------------------------------------------------
read_probe_cell:
.a8
.i8
        probe_cell_index
        a8
        cpx #COLLISION_BUFFER
        bcs @second
        lda collision_buffer_1,x
        bra @done
@second:
.a8
.i16
        cpx #BUFFER_PAIR_CELLS
        bcs @past
        lda collision_buffer_2-COLLISION_BUFFER,x
        bra @done
@past:
.a8
.i16
        jsr read_past_buffers
@done:
.a8
.i16
        sep #P_X8                       ; the zero flag of the metatile's load stays
        .i8
        rts

; ---------------------------------------------------------------------------
; store_probe_cell: a metatile into the probe's place, by the index of
; read_probe_cell (a wrapped row writes where the original's indirect store
; writes).
;
; In:       A8 I8; A = the metatile; probe_column, probe_row
; Out:      the cell
; Changes:  A, X
; Keeps:    Y, D
; Time:     about 55 cycles in the buffers
; Original: the stores at $DE20 (erase), $BD65 (bump), $BE34 (coin above),
;           $DFE6 (enemy on a bumped block), the vine's
; ---------------------------------------------------------------------------
store_probe_cell:
.a8
.i8
        pha
        probe_cell_index
        a8
        pla
        cpx #COLLISION_BUFFER
        bcs @second
        sta collision_buffer_1,x
        bra @done
@second:
.a8
.i16
        cpx #BUFFER_PAIR_CELLS
        bcs @past
        sta collision_buffer_2-COLLISION_BUFFER,x
        bra @done
@past:
.a8
.i16
        jsr write_past_buffers
@done:
.a8
.i16
        sep #P_X8
        .i8
        rts

; ---------------------------------------------------------------------------
; read_past_buffers, write_past_buffers: the original's RAM byte at $06A0 +
; p (p = the index - BUFFER_PAIR_CELLS, 0-47), which a wrapped row of a
; buffer 2 column reaches: the port's variable that holds that byte
; (past_buffer_bytes). A byte that the original never writes reads 0 and
; $06C9 reads $FF. Only a byte that held METATILE_BUMPED is written (an
; enemy on it clears it, check_enemy_vs_tiles); of these bytes only
; fireball_count can hold that value.
;
; In:       A8 I16; X = the index; write_past_buffers: A = the byte
; Out:      read_past_buffers: A = the byte, zero flag set when it is 0
; Changes:  A, X
; Keeps:    Y, D
; Time:     about 40 cycles
; Original: none (the effect of the original's buffer place)
; ---------------------------------------------------------------------------
read_past_buffers:
.a8
.i16
        jsr past_buffer_entry
        cpx #PAST_CONSTANTS
        bcc @constant
        lda a:0,x                       ; X holds the variable's address
        rts
@constant:
.a8
.i16
        txa                             ; PAST_ZERO: 0
        beq @zero
        lda #AREA_START_FILL            ; PAST_FF
@zero:  rts

write_past_buffers:
.a8
.i16
        pha
        jsr past_buffer_entry
        pla
        cpx #PAST_CONSTANTS
        bcc @done                       ; never reached: a constant byte holds no METATILE_BUMPED
        sta a:0,x
@done:  rts

; ---------------------------------------------------------------------------
; past_buffer_entry: the entry of past_buffer_bytes for a cell index past
; buffer 2.
;
; In:       A8 I16; X = the index (BUFFER_PAIR_CELLS + p)
; Out:      A8 I16; X = the entry: the variable's address, PAST_ZERO or PAST_FF
; Changes:  A, X
; Keeps:    Y, D
; Time:     about 25 cycles
; Original: none
; ---------------------------------------------------------------------------
past_buffer_entry:
.a8
.i16
        a16
        txa
        sec
        sbc #BUFFER_PAIR_CELLS
        asl a
        tax
        lda f:past_buffer_bytes,x
        tax
        a8
        rts

; past_buffer_bytes: the original's RAM after buffer 2, $06A0-$06CF, one
; entry per byte: the port's variable of the same value, or PAST_ZERO /
; PAST_FF. The values must be the original's: column_in_buffer and
; column_metatiles as the area builder keeps them, hammer_owner the
; enemy number of the thrower and jump_coin_slot the misc number.
past_buffer_bytes:
        .addr column_in_buffer          ; $06A0: the area builder's next buffer column
        .repeat METATILE_ROWS, I
        .addr column_metatiles + I      ; $06A1-$06AD: the metatiles of the column it built last
        .endrepeat
        .repeat MISC_SLOTS, I
        .addr misc_objects + I * OBJECT_PAGE + Object::hammer_owner ; $06AE-$06B6
        .endrepeat
        .repeat COIN_SLOT_BYTES, I
        .addr jump_coin_slot + I        ; $06B7-$06BB
        .endrepeat
        .addr coin_brick_flag           ; $06BC
        .addr PAST_ZERO                 ; $06BD
        .repeat MISC_SLOTS, I
        .addr misc_objects + I * OBJECT_PAGE + Object::misc_hit ; $06BE-$06C6: the hammers' contact
        .endrepeat
        .addr PAST_ZERO, PAST_ZERO      ; $06C7, $06C8
        .addr PAST_FF                   ; $06C9 (finish_area_setup)
        .addr PAST_ZERO                 ; $06CA
        .addr frenzy_kind               ; $06CB
        .addr hard_mode_2               ; $06CC
        .addr frenzy_queue              ; $06CD
        .addr fireball_count            ; $06CE
        .addr duplicate_slot            ; $06CF
.assert * - past_buffer_bytes = 2 * PAST_BUFFER_BYTES, error, "past_buffer_bytes: one entry per byte $06A0-$06CF"

; ---------------------------------------------------------------------------
; is_coin_tile: carry set for the two coin metatiles; then the coin sound
; (square 2) is queued.
;
; In:       A8 I8; A = the metatile
; Out:      carry set for a coin
; Changes:  the flags, snd_square2_queue
; Keeps:    A, X, Y, D
; Time:     under 30 cycles
; Original: $DFA1-$DFAF (is_coin_tile)
; ---------------------------------------------------------------------------
is_coin_tile:
.a8
.i8
        cmp #METATILE_COIN
        beq @coin
        cmp #METATILE_WATER_COIN
        beq @coin
        clc
        rts
@coin:  pha
        lda #SQUARE2_COIN
        sta snd_square2_queue
        pla
        sec
        rts

; ---------------------------------------------------------------------------
; is_nonsolid_tile: the zero flag set for the metatiles that enemies and
; fireballs pass through: the vine's blank, the coins, the hidden blocks.
;
; In:       A8 I8; A = the metatile
; Out:      zero flag set for those
; Changes:  the flags
; Keeps:    A, X, Y, D
; Time:     under 25 cycles
; Original: $E1B5-$E1C7 (is_nonsolid_tile)
; ---------------------------------------------------------------------------
is_nonsolid_tile:
.a8
.i8
        cmp #METATILE_VINE
        beq @done
        cmp #METATILE_COIN
        beq @done
        cmp #METATILE_WATER_COIN
        beq @done
        cmp #METATILE_HIDDEN_COIN
        beq @done
        cmp #METATILE_HIDDEN_1UP
@done:  rts

; ===========================================================================
; The player against the tiles
; ===========================================================================

; ---------------------------------------------------------------------------
; check_player_vs_tiles: the player's head, feet and sides against the
; collision buffers, each frame of the control routine.
;
; The state of the frame: 1 in a water area, else 0 (on the ground) and 3
; (climbing) become 2 (falling); the landing sets 0 again. The side bits
; become SIDES_FREE. Then the steps:
;   head: from player_head_limits down: a coin is taken (the test ends);
;     when the player rises and the Y's low nybble is 4 or more, a solid
;     metatile stops the rise (the bump sound, not for the vine's blank),
;     another one stops it in a water area or while a block bounces, else
;     bump_block_from_below.
;   feet: the left foot's coin is taken (the test ends); the metatile used
;     is the left foot's, else the right one's (a coin there is taken).
;     Climbable, or the player rising: no landing. The axe: touch_axe. A
;     hidden block: the player falls through. During a spring: state 0. A Y
;     nybble of 5 or more: a wall (block_player_sideways, the test ends).
;     Else the landing.
;   sides: left (upper, lower), then right: the first metatile found
;     (check_side_tile).
; The original's tests of Y against $CF, $E4 and $D0 after the start's test
; of Y < $CF never act and are left out.
;
; In:       A8 I8; D = the player's record (control_player)
; Out:      the player's state, Y, Y speed, X and side bits; stomp_chain;
;           the rules' other effects
; Changes:  A, X, Y, the variables of the routines it calls
; Keeps:    D
; Time:     each frame of play: about 900 cycles (seven probes)
; Original: $DC64-$DCF5 (check_player_vs_tiles), $DCF6-$DDFE
;           (check_player_feet)
; ---------------------------------------------------------------------------
check_player_vs_tiles:
.a8
.i8
        lda no_collisions
        bne @done
        lda player_task
        cmp #PLAYER_TASK_DEATH
        beq @done
        cmp #PLAYER_TASK_FLAGPOLE       ; the tasks below 4 have no tile test
        bcc @done
; The state of the frame.
        lda swimming
        beq @on_land
        lda #PLAYER_JUMPING
        sta Object::state
        bra @on_screen
@on_land:
        lda Object::state
        beq @falls
        cmp #PLAYER_CLIMBING
        bne @on_screen
@falls: lda #PLAYER_FALLING
        sta Object::state
@on_screen:
        lda Object::y_pos+1
        cmp #Y_HIGH_SCREEN
        bne @done
        lda #SIDES_FREE
        sta Object::collision
        lda Object::y_pos
        cmp #PLAYER_TILE_LIMIT
        bcc @point_set
@done:  rts
; The point set: small or crouching, big swimming, big.
@point_set:
        ldy #POINT_SET_SMALL
        lda crouching
        bne @set
        lda player_small
        bne @set
        ldy #POINT_SET_SWIM
        lda swimming
        bne @set
        ldy #POINT_SET_BIG
@set:   lda tile_point_sets,y
        sta player_points
; The head, when the player is low enough for its point to be in the rows.
        ldx player_small                ; 0 big, 1 small (a small player never crouches)
        lda crouching
        beq @limit
        inx
@limit: lda Object::y_pos
        cmp player_head_limits,x
        bcc @feet
        ldy player_points               ; + POINT_HEAD
        jsr probe_tile
        beq @feet
        jsr is_coin_tile
        bcs @take_coin                  ; the test ends
        tax                             ; the head metatile
        bit Object::y_speed_whole
        bpl @feet                       ; not rising
        lda Object::y_pos
        and #LOW_NIBBLE
        cmp #HEAD_DEPTH
        bcc @feet
        bit metatile_class,x
        bmi @solid
        lda area_type
        beq @stop_rise                  ; a water area: no block is hit
        lda timers+TIMER_BLOCK_BOUNCE
        bne @stop_rise
        txa
        jsr bump_block_from_below
        bra @feet
@take_coin:
        jmp take_coin_tile
@solid: cpx #METATILE_VINE
        beq @stop_rise
        lda #SQUARE1_BUMP
        sta snd_square1_queue
@stop_rise:
        lda #HEAD_STOP_SPEED
        sta Object::y_speed_whole
; The feet.
@feet:  ldy player_points
        iny                             ; POINT_LEFT_FOOT
        jsr probe_tile
        jsr is_coin_tile
        bcs @take_coin                  ; the test ends
        sta feet_left
        iny                             ; POINT_RIGHT_FOOT
        jsr probe_tile
        sta feet_right
        lda feet_left
        bne @foot
        lda feet_right
        beq @sides
        jsr is_coin_tile
        bcs @take_coin
@foot:  tax                             ; the foot's metatile
        bit metatile_class,x
        bvs @sides                      ; climbable
        bit Object::y_speed_whole
        bmi @sides                      ; rising
        cpx #METATILE_AXE
        bne @not_axe
        jmp touch_axe                   ; the test ends
@not_axe:
        cpx #METATILE_HIDDEN_COIN
        beq @sides                      ; the player falls through a hidden block
        cpx #METATILE_HIDDEN_1UP
        beq @sides
        lda spring_anim
        bne @stand                      ; a spring holds the player: no Y change
        lda Object::y_pos
        and #LOW_NIBBLE
        cmp #FOOT_DEPTH
        bcc @land
        lda Object::direction           ; deep in the metatile: a wall in the way he moves
        sta wall_side
        jmp block_player_sideways       ; the test ends
@land:  txa
        jsr land_on_spring
        lda Object::y_pos
        and #ROW_MASK
        sta Object::y_pos
        jsr enter_pipe_check
        a16
        stz Object::y_speed             ; the Y speed and its fraction
        a8
        stz stomp_chain
@stand: stz Object::state               ; PLAYER_ON_GROUND
; The sides: the left points (wall_side WALL_LEFT), then the right points.
@sides: lda #WALL_LEFT
        sta wall_side
        lda player_points
        clc
        adc #POINT_LEFT_UPPER
        tay
@side:  lda Object::y_pos
        cmp #SIDE_TOP_LIMIT
        bcc @lower                      ; the upper point is in the status bar
        jsr probe_tile
        beq @lower
        cmp #METATILE_SIDE_PIPE_TOP     ; the tops of the side pipes' mouths do not stop
        beq @lower
        cmp #METATILE_WATER_SIDE_PIPE_TOP
        beq @lower
        tax
        bit metatile_class,x
        bvc check_side_tile             ; climbable at the upper point: the lower point decides
@lower: iny
        lda Object::y_pos
        cmp #SIDE_LOWER_LIMIT
        bcc @end
        jsr probe_tile
        bne check_side_tile
        iny                             ; the next pass's upper point
        dec wall_side
        bne @side
@end:   rts
.assert WALL_LEFT = WALL_RIGHT + 1, error, "check_player_vs_tiles: the passes count down"
.assert PLAYER_ON_GROUND = 0, error, "check_player_vs_tiles: stz sets the state"

; ---------------------------------------------------------------------------
; check_side_tile: test the metatile at a side point of the player. A hidden
; block does nothing; a climbable metatile catches him; a
; coin is taken; a jump spring stops him unless it moves; a side pipe's
; mouth takes him when he stands and faces right (the pipe sound once, behind
; the background, the area change wait until his X is on a 16-pixel step,
; the side pipe task from the control task); anything else stops him.
;
; In:       A8 I8; A = the metatile; wall_side = the side; D = the player's
;           record
; Out:      as the rules say
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 60 cycles for a wall
; Original: $DD9C-$DDFE (in check_player_feet)
; ---------------------------------------------------------------------------
check_side_tile:
.a8
.i8
        cmp #METATILE_HIDDEN_COIN
        beq @done
        cmp #METATILE_HIDDEN_1UP
        beq @done
        tax
        bit metatile_class,x
        bvc @not_climbable
        jmp grab_climbable
@not_climbable:
        jsr is_coin_tile
        bcs take_coin_tile
        cmp #METATILE_SPRING_TOP
        beq @spring
        cmp #METATILE_SPRING_BOTTOM
        bne @wall
@spring:
        lda spring_anim
        bne @done
        jmp block_player_sideways
; A side pipe's mouth takes a player on the ground who faces right.
@wall:  ldy Object::state
        bne block_player_sideways
        ldy player_facing
        cpy #FACING_RIGHT
        bne block_player_sideways
        cmp #METATILE_WATER_SIDE_PIPE
        beq @side_pipe
        cmp #METATILE_SIDE_PIPE
        bne block_player_sideways
@side_pipe:
        lda Object::attributes
        bne @behind                     ; the sound only at the first frame
        lda #SQUARE1_PIPE_INJURY
        sta snd_square1_queue
@behind:
        lda #ATTR_BEHIND
        tsb Object::attributes
; Until the player's X sits on a 16-pixel step, the area change waits anew.
        lda Object::x_pos
        and #LOW_NIBBLE
        beq @task
        ldy #WAIT_FIRST_PAGE
        lda screen_left+1               ; the screen's left page
        beq @wait
        ldy #WAIT_LATER_PAGES
@wait:  lda area_change_waits,y
        sta area_change_timer
@task:  lda player_task
        cmp #PLAYER_TASK_CONTROL        ; the entrance task keeps its own
        bne @done
        lda #PLAYER_TASK_SIDE_PIPE
        sta player_task
@done:  rts

; ---------------------------------------------------------------------------
; take_coin_tile: the coin at the probe's place is taken: the cell and its
; picture become empty, the block-coin counter counts it, add_one_coin.
;
; In:       A8 I8; probe_column, probe_row
; Out:      the cell, coins_for_1up, the coin and score digits
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 1,500 cycles (add_one_coin prints the score)
; Original: $DE05-$DE0D (take_coin_tile)
; ---------------------------------------------------------------------------
take_coin_tile:
.a8
.i8
        jsr erase_tile_in_buffer
        inc coins_for_1up
        jmp add_one_coin

; ---------------------------------------------------------------------------
; touch_axe: the axe ends the castle: the victory mode from its first
; task, the player runs right, the axe's cell and picture become empty. The
; cell is the last probe's: when the axe is under the left foot only, that
; is the right foot's cell (the right foot is probed after the left), as in
; the original.
;
; In:       A8 I8; probe_column, probe_row
; Out:      mode, mode_task, the player's X speed, the cell
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 200 cycles
; Original: $DE0E-$DE1B (touch_axe)
; ---------------------------------------------------------------------------
touch_axe:
.a8
.i8
        stz mode_task
        lda #MODE_VICTORY
        sta mode
        lda #AXE_RUN_SPEED
        sta player_object+Object::x_speed
        ; falls into erase_tile_in_buffer

; ---------------------------------------------------------------------------
; erase_tile_in_buffer: the probe's cell becomes empty, and its picture (the
; screen part's erase_coin_or_axe: the blank, or the water blank in a water
; area, at the start of list 2).
;
; In:       A8 I8; probe_column, probe_row
; Out:      the cell, the screen record
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 150 cycles
; Original: $DE1C-$DE24 (erase_tile_in_buffer)
; ---------------------------------------------------------------------------
erase_tile_in_buffer:
.a8
.i8
        lda #METATILE_EMPTY
        jsr store_probe_cell
        ldx probe_column
        ldy probe_row
        jmp erase_coin_or_axe           ; the screen part: X = the ring column 0-31, Y = the row offset

; ---------------------------------------------------------------------------
; block_player_sideways: a wall stops the player. A wall at his right
; (WALL_RIGHT): unless he moves left, his X speed becomes 0 and he steps 1
; pixel left; a wall at his left: unless he moves right (X speed 1 or more
; by the original's signed test), the same with 1 pixel right. A stop sets
; the side timer. Either way the side's free bit is cleared.
;
; In:       A8 I8; wall_side; any D (the player's fields are read by
;           player_object)
; Out:      the player's X, X speed and side bits; timers+TIMER_SIDE_COLLISION
; Changes:  A, X
; Keeps:    Y, D
; Time:     about 60 cycles
; Original: $DF4B-$DF65 (block_player_sideways), $DF66-$DF8A (stop_x_speed),
;           $DDFF-$DE02 (halt_player_sideways)
; ---------------------------------------------------------------------------
block_player_sideways:
.a8
.i8
        lda wall_side
        cmp #WALL_RIGHT
        bne @left_wall
        ldx #SIDE_RIGHT_FREE
        lda player_object+Object::x_speed
        bmi @side_bit                   ; he moves away from the wall
        a16
        lda #.loword(-WALL_STEP)        ; 1 pixel left
        bra @stop
@left_wall:
.a8
        ldx #SIDE_LEFT_FREE
        lda player_object+Object::x_speed
        cmp #SPEED_RIGHTWARD
        bpl @side_bit                   ; he moves away (the original's sign test of the speed - 1)
        a16
        lda #WALL_STEP                  ; 1 pixel right
@stop:
.a16
        clc
        adc player_object+Object::x_pos ; one add to page and pixel: the original's carry
        sta player_object+Object::x_pos
        a8
        stz player_object+Object::x_speed
        lda #SIDE_STOP_FRAMES
        sta timers+TIMER_SIDE_COLLISION
@side_bit:
.a8
        txa
        trb player_object+Object::collision
        rts

; ---------------------------------------------------------------------------
; grab_climbable: a climbable metatile at a side point catches the player
; when his X is in the middle four pixels of a 16-pixel step (its low nybble
; 6-9), else he passes it. The flagpole (outside the walk to the castle):
; facing right, the scroll locks, and unless the slide runs already the
; cannons' bullet bills are removed, the music stops, the pole sound, the
; touch Y and the flag score; the slide starts. The vine above Y $20: the
; climb out of the top. Then snap_player_to_vine.
;
; In:       A8 I8; A = the metatile; D = the player's record; probe_column
; Out:      as the rules say
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 150 cycles
; Original: $DE2E-$DE87 (grab_climbable)
; ---------------------------------------------------------------------------
grab_climbable:
.a8
.i8
        tax
        lda Object::x_pos
        and #LOW_NIBBLE
        cmp #GRAB_FIRST
        bcc @pass
        cmp #GRAB_LAST + 1
        bcs @pass
        cpx #METATILE_POLE_BALL
        beq @pole
        cpx #METATILE_POLE
        beq @pole
        cpx #METATILE_VINE
        bne snap_player_to_vine
        lda Object::y_pos
        cmp #VINE_TOP_LIMIT
        bcs snap_player_to_vine
        lda #PLAYER_TASK_VINE_CLIMB
        sta player_task
        bra snap_player_to_vine
@pass:  rts
@pole:  lda player_task
        cmp #PLAYER_TASK_END_LEVEL
        beq snap_player_to_vine
        lda #FACING_RIGHT
        sta player_facing
        inc scroll_lock
        lda player_task
        cmp #PLAYER_TASK_FLAGPOLE
        beq @slide
        phd                             ; the levels part works on the enemy records
        lda #KIND_BULLET_CANNON
        jsr clear_enemies_of_kind ; enemy numbers 4-0 of that kind end
        pld
        lda #EVENT_SILENCE
        sta snd_event_queue
        lda #SQUARE1_FLAGPOLE
        sta flag_sound
; The flag score: the highest of heights 4-1 that the player's Y reaches,
; else 0 (entry 0 is not read).
        lda Object::y_pos
        sta flag_touch_y
        ldx #FLAG_HEIGHTS
@height:
        cmp flagpole_score_heights,x
        bcs @score
        dex
        bne @height
@score: stx flag_score
@slide: lda #PLAYER_TASK_FLAGPOLE
        sta player_task
        ; falls into snap_player_to_vine

; ---------------------------------------------------------------------------
; snap_player_to_vine: the player climbs: the state, no X speed, and his X
; on the column of the probe: 16 x the column + climb_x_adders[facing] (-7
; facing right, +7 facing left); near the screen's left edge he faces left.
; The page is set only for column 0 of buffer 1 (probe_column 0): the
; screen's right page + climb_page_adders[facing]; in column 0 of buffer 2
; the page stays.
;
; In:       A8 I8; D = the player's record; probe_column
; Out:      the player's state, X speed, player_x_fraction, X, facing
; Changes:  A, Y
; Keeps:    X, D
; Time:     about 80 cycles
; Original: $DE88-$DEBC (snap_player_to_vine)
; ---------------------------------------------------------------------------
snap_player_to_vine:
.a8
.i8
        lda #PLAYER_CLIMBING
        sta Object::state
        stz Object::x_speed
        stz Object::x_speed_fraction ; the fraction of the X speed
        lda Object::x_pos
        sec
        sbc screen_left                 ; the screen X (low bytes)
        cmp #VINE_EDGE
        bcs @facing
        lda #FACING_LEFT
        sta player_facing
@facing:
        ldy player_facing
        lda probe_column
        asl a
        asl a
        asl a
        asl a                           ; 16 x the column in its buffer (the buffer bit drops out)
        clc
        adc climb_x_adders-FACING_RIGHT,y
        sta Object::x_pos
        lda probe_column
        bne @done
        lda screen_right+1
        clc
        adc climb_page_adders-FACING_RIGHT,y
        sta Object::x_pos+1
@done:  rts

; ---------------------------------------------------------------------------
; land_on_spring: feet that land on a jump spring's metatile start the
; spring (the objects part runs it).
;
; In:       A8 I8; A = the foot's metatile
; Out:      gravity_up, spring_force, timers+TIMER_SPRING, spring_anim
; Changes:  A
; Keeps:    X, Y, D
; Time:     under 40 cycles
; Original: $DEC4-$DEDC (land_on_spring), $DEDD-$DEE7 (is_spring_tile)
; ---------------------------------------------------------------------------
land_on_spring:
.a8
.i8
        cmp #METATILE_SPRING_TOP
        beq @spring
        cmp #METATILE_SPRING_BOTTOM
        bne @done
@spring:
        lda #SPRING_GRAVITY
        sta gravity_up ; the gravity in use
        lda #SPRING_FORCE
        sta spring_force
        lda #SPRING_FRAMES
        sta timers+TIMER_SPRING
        lda #SPRING_FIRST_STEP
        sta spring_anim
@done:  rts

; ---------------------------------------------------------------------------
; enter_pipe_check: down held, the right foot on an enterable pipe's right
; top half and the left foot on its left half: down the pipe (48 frames to
; the area change, the pipe sound, the player behind the background). In a
; warp zone the pipe (by the player's X: left below $60, middle below $A0,
; else right) sends him to the first area of its world: warp_pipe_worlds and
; warp_pipe_areas of group warp_zone AND 3 (the blank pipes of
; group 1, reached with warp_zone 1, give world $23); the
; entrance and the level start at 0, the hidden 1-up block shows, the time
; starts again.
;
; In:       A8 I8; D = the player's record; feet_left, feet_right; pad_ud
; Out:      as the rules say
; Changes:  A, X
; Keeps:    Y, D
; Time:     about 30 cycles without a pipe
; Original: $DEE8-$DF4A (enter_pipe_check)
; ---------------------------------------------------------------------------
enter_pipe_check:
.a8
.i8
        lda pad_ud
        and #PAD_DOWN
        beq @done
        lda feet_right
        cmp #METATILE_PIPE_RIGHT
        bne @done
        lda feet_left
        cmp #METATILE_PIPE_LEFT
        bne @done
        lda #PIPE_FRAMES
        sta area_change_timer
        lda #PLAYER_TASK_DOWN_PIPE
        sta player_task
        lda #SQUARE1_PIPE_INJURY
        sta snd_square1_queue
        lda #ATTR_BEHIND
        sta Object::attributes
        lda warp_zone
        beq @done
; The warp: the group's first pipe (3 x the group) + the pipe.
        and #WARP_GROUP
        pha
        asl a                           ; 2 x the group; the carry is clear
        adc 1,s                         ; 3 x the group
        tax
        pla
        lda Object::x_pos
        cmp #WARP_LEFT_PIPE
        bcc @pipe
        inx
        cmp #WARP_MIDDLE_PIPE
        bcc @pipe
        inx
@pipe:  lda warp_pipe_worlds,x
        sta player_record+PlayerRecord::world
        lda warp_pipe_areas,x
        sta area_byte
        lda #EVENT_SILENCE
        sta snd_event_queue
        stz entrance_page
        stz player_record+PlayerRecord::area_index
        stz player_record+PlayerRecord::level
        stz entrance_alt
        inc player_record+PlayerRecord::hidden_1up
        inc timer_reload
@done:  rts
.assert WARP_PIPES = 3, error, "enter_pipe_check: the group x 3 is a shift and an add"

; ===========================================================================
; The block hits from below
; ===========================================================================

; ---------------------------------------------------------------------------
; bump_block_from_below: the player's head hits a block that is not solid.
; The block object of sprite_offset_select takes the bump: its state ($11 a
; bump for a small player, $12 a break for a big one), the blank in the
; picture (the block shows as a sprite while it moves), its place in the
; buffers and the metatile that comes back when its move ends: a plain brick
; stays for a small player and goes for a big one; a bumpable block bounces
; for both and becomes the used block, but a coin brick stays one while its
; coin time runs (one flag for all coin bricks, which the area builder
; clears). The cell becomes METATILE_BUMPED (solid while the block moves),
; the bounce timer runs, the block's X and Y take the player's column and
; row, then hit_block or break_brick. The next bump takes the other block
; object.
;
; In:       A8 I8; A = the head's metatile; probe_column, probe_row = its
;           place; D = the player's record
; Out:      the block object's record; the cell; the rules of hit_block or
;           break_brick
; Changes:  A, X, Y, bumped_metatile
; Keeps:    D
; Time:     about 3,000 cycles with a brick that breaks (its score print)
; Original: $BCED-$BD83 (bump_block_from_below, flip_block_slot_bit $BD7B)
; ---------------------------------------------------------------------------
bump_block_from_below:
.a8
.i8
        sta bumped_metatile
        phd
        lda sprite_offset_select
        clc
        adc #SLOT_BLOCK
        tax
        object_from_x                   ; D = the block object
        lda #BLOCK_BUMP
        ldy player_small
        bne @state
        lda #BLOCK_BREAK
@state: sta Object::state
        ldx probe_column
        ldy probe_row
        jsr blank_block_picture         ; the screen part: X = the ring column 0-31, Y = the row offset
        lda probe_row
        sta Object::block_origin_y
        lda probe_column
        sta Object::block_buffer
; The metatile that comes back (the original reads the cell again).
        jsr read_probe_cell
        jsr is_bumpable_block
        bcs @bumpable
        ldy player_small
        bne @replace                    ; a small player: the brick comes back
        lda #METATILE_EMPTY             ; a big one breaks it
        bra @replace
@bumpable:
        ldy #BLOCK_BUMP                 ; a bumpable block bounces for both sizes
        sty Object::state
        cmp #METATILE_COIN_BRICK
        beq @coin_brick
        cmp #METATILE_COIN_BRICK_PLAIN
        bne @used
@coin_brick:
        ldy coin_brick_flag
        bne @coin_time
        ldy #COIN_BRICK_TIME
        sty timers+TIMER_COIN_BRICK
        inc coin_brick_flag
@coin_time:
        ldy timers+TIMER_COIN_BRICK
        bne @replace                    ; while the time runs, the coin brick stays
@used:  lda #METATILE_USED_BLOCK
@replace:
        sta Object::block_metatile
        jsr set_block_place
        lda #METATILE_BUMPED
        jsr store_probe_cell
        lda #BLOCK_BOUNCE_FRAMES
        sta timers+TIMER_BLOCK_BOUNCE
; The block's Y: the player's Y + block_y_by_size (big standing, or small or
; crouching), on its 16-pixel row.
        ldy #BLOCK_Y_BIG
        lda crouching
        bne @small
        lda player_small
        beq @size
@small: ldy #BLOCK_Y_SMALL
@size:  lda player_object+Object::y_pos
        clc
        adc block_y_by_size,y
        and #ROW_MASK
        sta Object::y_pos
        lda Object::state
        cmp #BLOCK_BUMP
        beq @bump
        jsr break_brick
        bra @flip
@bump:  jsr hit_block
@flip:  lda sprite_offset_select
        eor #BLOCK_SELECT_SWAP
        sta sprite_offset_select        ; the next bump takes the other block object
        pld
        rts

; ---------------------------------------------------------------------------
; set_block_place: a block object at the player's column: X = (the player's
; X + 8) AND $F0 with the page and its carry (also in Object::block_page),
; Y high = the player's.
;
; In:       A8 I8; D = the block object's record
; Out:      its x_pos, block_page, Y high
; Changes:  A
; Keeps:    X, Y, D
; Time:     about 45 cycles
; Original: $BD84-$BD9A (set_block_place); also called by the vine entrance
;           (setup_entry_and_timer, block 0)
; ---------------------------------------------------------------------------
set_block_place:
.a8
.i8
        a16
        lda player_object+Object::x_pos
        clc
        adc #BLOCK_CENTRE
        and #.loword(~LOW_NIBBLE)       ; the 16-pixel column; the page keeps the carry
        sta Object::x_pos
        a8
        xba
        sta Object::block_page          ; the second copy of the page (launch_jump_coin)
        lda player_object+Object::y_pos+1
        sta Object::y_pos+1
        rts

; ---------------------------------------------------------------------------
; hit_block: a block bounces: a coin above it jumps out, the bump sound, the
; block rises (X speed 0, Y speed $FE with fraction 0) and the player's rise
; stops (his Y speed whole 0). A bumpable block gives its gift
; (bump_gifts), by the original's effect table: the mushroom or the flower,
; a coin, the 1-up, the vine, the star. A coin that jumps out from above
; takes the gift away: the original keeps the head's metatile in a scratch
; byte ($05) that the coin's picture write overwrites (
; write_metatile_record writes $03-$05: the high byte of the coin's name
; table address, $20-$27, which is no bumpable metatile), so its gift test
; finds nothing. The block still becomes its replacement metatile.
;
; In:       A8 I8; D = the block object's record; bumped_metatile;
;           probe_column, probe_row
; Out:      the block's speeds, the player's Y speed, the gift
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 300 cycles, and the gift
; Original: $BD9B-$BDD1 (hit_block), $BDD2-$BDE7 (the gifts)
; ---------------------------------------------------------------------------
hit_block:
.a8
.i8
        jsr check_coin_above_block
        php                             ; carry: a coin above jumped out (no gift, see above)
        lda #SQUARE1_BUMP
        sta snd_square1_queue
        stz Object::x_speed
        stz Object::y_speed_fraction
        stz player_object+Object::y_speed_whole
        lda #BLOCK_RISE_SPEED
        sta Object::y_speed_whole
        plp
        bcs @done
        lda bumped_metatile
        jsr is_bumpable_block
        bcc @done
        txa
        asl a                           ; the carry is clear: pop_block_coin starts so (the original's jump)
        tax
        jmp (.loword(@gifts),x)         ; the table is in this bank (K)
@done:  rts
@gifts: .addr @mushroom                 ; a question block with an item
        .addr pop_block_coin            ; a question block with a coin
        .addr pop_block_coin            ; a hidden coin block
        .addr @life                     ; the hidden 1-up block
        .addr @mushroom                 ; a brick with an item
        .addr @vine                     ; a brick with a vine
        .addr @star                     ; a brick with a star
        .addr pop_block_coin            ; a coin brick
        .addr @life                     ; a brick with a 1-up
; The power-up gifts: the kind, then release_powerup (the power-up in
; enemy slot 5 at the block's place; a mushroom is a flower for a big player).
@mushroom:
        lda #POWERUP_MUSHROOM
        bra @powerup
@star:  lda #POWERUP_STAR
        bra @powerup
@life:  lda #POWERUP_1UP
@powerup:
        sta powerup_kind
        jmp release_powerup ; D = the block object
@vine:  ldy sprite_offset_select
        jmp start_vine ; the vine in enemy slot 5 at block Y (D = the block object)

; ---------------------------------------------------------------------------
; is_bumpable_block: is a metatile in the bumpable list, and its gift.
;
; In:       A8 I8; A = the metatile
; Out:      carry set when it is; X = its gift (bump_gifts, 0-8)
; Changes:  X, the flags
; Keeps:    A, Y, D
; Time:     under 140 cycles (14 entries)
; Original: $BDF6-$BE01 (is_bumpable_block)
; ---------------------------------------------------------------------------
is_bumpable_block:
.a8
.i8
        ldx #<(BUMP_METATILES_SIZE - 1)
@entry: cmp bump_metatiles,x
        beq @found
        dex
        bpl @entry
        clc
        rts
@found: pha
        lda bump_gifts,x
        tax
        pla
        sec
        rts

; ---------------------------------------------------------------------------
; break_brick: a big player breaks a brick: a coin above it jumps out, the
; empty metatile goes back at the next chance, the brick sound, the four
; pieces (scatter_brick_chunks), the player's rise slows, 50 points.
;
; In:       A8 I8; D = the block object's record; probe_column, probe_row
; Out:      Object::block_replace, the player's Y speed, the score
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 2,500 cycles (the score print)
; Original: $BE02-$BE1E (break_brick)
; ---------------------------------------------------------------------------
break_brick:
.a8
.i8
        jsr check_coin_above_block
        lda #BLOCK_REPLACE_DUE
        sta Object::block_replace
        lda #NOISE_BRICK_SHATTER
        sta snd_noise_queue
        jsr scatter_brick_chunks ; D = the block object
        lda #BRICK_PLAYER_SPEED
        sta player_object+Object::y_speed_whole
        lda #BRICK_TENS
        sta a:digit_add+DIGIT_TENS       ; DIGIT_TENS: score.s (absolute: the name may come later)
        jmp add_score

; ---------------------------------------------------------------------------
; check_coin_above_block: a coin in the cell above the bumped block (only
; the ground coin) jumps out: the cell and its picture become empty and the
; objects part's launch_jump_coin starts it. probe_row keeps the row above
; (launch_jump_coin reads it).
;
; In:       A8 I8; D = the block object's record; probe_column, probe_row
; Out:      probe_row (the row above, unless the block is in row 0); carry
;           set when a coin jumped out (hit_block then gives no gift)
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 70 cycles without a coin
; Original: $BE1F-$BE40 (check_coin_above_block)
; ---------------------------------------------------------------------------
check_coin_above_block:
.a8
.i8
        lda probe_row
        beq @none                       ; the top row has no cell above
        sec
        sbc #ROW_STEP
        sta probe_row
        jsr read_probe_cell
        cmp #METATILE_COIN
        bne @none
        lda #METATILE_EMPTY
        jsr store_probe_cell
        ldx probe_column
        ldy probe_row
        jsr erase_coin_or_axe           ; the screen part
        jsr launch_jump_coin ; D = the block object; probe_column, probe_row
        sec
        rts
@none:  clc
        rts

; ===========================================================================
; The enemies against the tiles
; ===========================================================================

; ---------------------------------------------------------------------------
; check_enemy_vs_tiles: an enemy's ground and walls. Not for a defeated
; enemy, outside the Y range of enemy_y_plus_62, or for a spiny above Y $25.
; The jumping paratroopa and the hammer brother have their own tests; only
; the kinds $00-$06, the spiny and the power-up go on.
;   No ground (nothing, or a passable metatile): landing_state_for_kind.
;   A block in motion: its cell becomes empty; the power-up is stunned by
;     its kind; a goomba is knocked out, then (as every other kind) gets
;     100 points and the stun with A = the screen X that start_score_number
;     leaves (a screen X of 9 or $0D-$10 changes the kind).
;   Other ground: with the Y's low nybble 8-12 the enemy lands by its state,
; else it falls on.
;
; In:       A8 I8; D = the enemy's record (also the mushroom and the 1-up,
;           run_powerup)
; Out:      the enemy's state, place, speeds, direction, kind; the cell
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 300 cycles
; Original: $DFC1-$E01A, $E067-$E0E1 (check_enemy_vs_tiles)
; ---------------------------------------------------------------------------
check_enemy_vs_tiles:
.a8
.i8
        lda Object::state
        and #ENEMY_DEFEATED
        bne @done
        jsr enemy_y_plus_62
        bcc @done
        lda Object::kind
        cmp #KIND_SPINY
        bne @kind
        lda Object::y_pos
        cmp #SPINY_TILE_TOP
        bcc @done
@kind:  lda Object::kind
        cmp #KIND_GREEN_PARATROOPA_JUMP
        bne @not_jumper
        jmp enemy_land_check
@not_jumper:
        cmp #KIND_HAMMER_BRO
        bne @not_hammer
        jmp hammer_bro_tile_check
@not_hammer:
        cmp #KIND_SPINY
        beq @under
        cmp #KIND_POWERUP
        beq @under
        cmp #KIND_BLOOPER
        bcc @under
@done:  rts
@under: jsr tile_under_enemy
        beq @no_ground
        jsr is_nonsolid_tile
        beq @no_ground
        cmp #METATILE_BUMPED
        bne @ground
; A block in motion under the enemy: the cell becomes empty (this acts once).
        lda #METATILE_EMPTY
        jsr store_probe_cell
        lda Object::kind
        cmp #KIND_BOWSER_FLAME          ; the power-up: the stun by its kind
        bcs @stun
        cmp #KIND_GOOMBA
        bne @points
        jsr kill_enemy_on_bumped_block
@points:
        lda #SCORE_100
        jsr start_score_number          ; A = the enemy group's screen X
@stun:  jmp stun_enemy_by_kind
@no_ground:
        jmp landing_state_for_kind
; Other ground: a landing only with the feet near the row's top.
@ground:
        lda Object::y_pos
        and #LOW_NIBBLE
        sec
        sbc #ENEMY_FOOT_TOP
        cmp #ENEMY_FOOT_RANGE
        bcs @no_ground
        lda Object::state
        bit #ENEMY_DROP
        bne @lands                      ; a falling shell or power-up lands
        bmi @sides                      ; BIT # keeps N: a moving shell or power-up
        cmp #ENEMY_WALKING
        beq @sides
        cmp #ENEMY_SPINY_EGG
        beq @direction
        cmp #ENEMY_UPSIDE_DOWN
        bcs @done                       ; 3, 4, and 6 up: it stays
        cmp #ENEMY_FLIPPED
        bne @direction                  ; 1: falling
; A flipped enemy lands upside down and lies there for its wake time.
        lda #ENEMY_WAKE_TIME
        ldy Object::kind
        cpy #KIND_SPINY
        bne @wake
        lda #SPINY_WAKE_TIME
@wake:  ldx Object::slot
        sta timers+TIMER_ENEMY_INTERVAL-SLOT_ENEMY,x
        lda #ENEMY_UPSIDE_DOWN
        sta Object::state
        jmp enemy_lands
; A falling enemy or a spiny's egg lands; most kinds turn toward the player.
@direction:
        lda Object::kind
        cmp #KIND_GOOMBA
        beq @lands
        cmp #KIND_SPINY
        bne @face
        lda #FACING_RIGHT
        sta Object::direction
        lda #SPINY_WALK_SPEED
        sta Object::x_speed
        lda frame_count
        and #SPINY_TURN_FRAMES
        beq @lands
@face:  ldy #FACING_RIGHT               ; the side it is on: right of the player
        jsr player_enemy_gap
        bpl @side
        iny
@side:  tya
        cmp Object::direction
        bne @lands
        jsr bump_or_hammer_jump         ; it moves away from the player: it turns
@lands: jsr enemy_lands
        lda Object::state
        bmi @shell
        stz Object::state               ; ENEMY_WALKING (a spiny's egg becomes a spiny)
        rts
@shell: and #<~ENEMY_DROP
        sta Object::state
        rts
@sides: jmp check_enemy_sides
.assert ENEMY_WALKING = 0, error, "check_enemy_vs_tiles: stz sets the state"

; ---------------------------------------------------------------------------
; stun_enemy_by_kind: when A is 9 or $0D-$10, the enemy's kind becomes A AND
; 1 (a green or red koopa); then stun_enemy. A is the kind for most callers;
; knock_out_enemy gives a piranha plant's Y + 25 and check_enemy_vs_tiles
; the screen X.
; stun_enemy: the enemy flips up: state (state AND $F0) OR 2, 2 pixels up
; (the Y pixel only), Y speed $FD ($FF in a water area or for a blooper),
; the direction away from the player (the bullet bills keep theirs) and the
; X speed of enemy_land_x_speeds by that side.
;
; In:       A8 I8; A as above (stun_enemy_by_kind); D = the enemy's record
; Out:      the enemy's kind, state, Y, Y speed, direction, X speed;
;           enemy_gap
; Changes:  A, Y
; Keeps:    X, D
; Time:     about 110 cycles
; Original: $E01B-$E02E (stun_enemy_by_kind), $E02F-$E066 (stun_enemy)
; ---------------------------------------------------------------------------
stun_enemy_by_kind:
.a8
.i8
        cmp #STUN_DEMOTE
        beq @demote
        cmp #STUN_DEMOTE_FIRST
        bcc stun_enemy
        cmp #STUN_DEMOTE_LAST + 1
        bcs stun_enemy
@demote:
        and #KOOPA_COLOUR
        sta Object::kind
stun_enemy:
.a8
.i8
        lda Object::state
        and #ENEMY_STUN_KEEP
        ora #ENEMY_FLIPPED
        sta Object::state
        dec Object::y_pos               ; 8 bits: Y high takes no borrow
        dec Object::y_pos
        lda Object::kind
        cmp #KIND_BLOOPER
        beq @slow
        lda #STUN_SPEED
        ldy area_type
        bne @speed
@slow:  lda #STUN_SPEED_SLOW
@speed: sta Object::y_speed_whole
        ldy #FACING_RIGHT               ; at or right of the player: away is right
        jsr player_enemy_gap
        bpl @away
        iny
@away:  lda Object::kind
        cmp #KIND_BULLET_CANNON
        beq @x_speed
        cmp #KIND_BULLET_FRENZY
        beq @x_speed
        sty Object::direction
@x_speed:
        lda enemy_land_x_speeds-FACING_RIGHT,y
        sta Object::x_speed
        rts
.assert STUN_LIFT = 2, error, "stun_enemy: two decrements"

; ---------------------------------------------------------------------------
; landing_state_for_kind: an enemy with no ground under it. A red koopa that
; walks turns at the edge (bump_or_hammer_jump) and the test ends. Else a
; state with bit 7 gets bit 6 (it falls), any other state becomes
; enemy_landing_states[state] (the builder's table holds the bytes after the
; six states too, which the original reads for a state of 6 and up); then check_enemy_sides.
;
; In:       A8 I8; D = the enemy's record
; Out:      the enemy's state; check_enemy_sides
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 130 cycles
; Original: $E0E2-$E0FB (landing_state_for_kind), $E0FC-$E0FD
;           (store_enemy_state)
; ---------------------------------------------------------------------------
landing_state_for_kind:
.a8
.i8
        lda Object::kind
        cmp #KIND_RED_KOOPA
        bne @state
        lda Object::state
        bne @state
        jmp bump_or_hammer_jump
@state: lda Object::state
        bpl @table
        ora #ENEMY_DROP
        bra @store
@table: tax
        lda enemy_landing_states,x
@store: sta Object::state
        ; falls into check_enemy_sides

; ---------------------------------------------------------------------------
; check_enemy_sides: a wall in front of an enemy turns it: an enemy moving
; left probes its left point, one moving right its right point (the X
; part); a metatile that is not 0 and not passable: bump_or_hammer_jump. No
; test above Y $20 (the status bar). The test has no lower limit: the
; jumping paratroopa and the star reach it below the screen's rows, where
; the probe reads what the original reads (read_probe_cell).
;
; In:       A8 I8; D = the enemy's record
; Out:      bump_or_hammer_jump
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 140 cycles
; Original: $E0FE-$E123 (check_enemy_sides)
; ---------------------------------------------------------------------------
check_enemy_sides:
.a8
.i8
        lda Object::y_pos
        cmp #ENEMY_SIDE_TOP
        bcc @done
        ldy #POINT_ENEMY_LEFT
        lda Object::direction
        cmp #FACING_LEFT
        beq @probe
        ldy #POINT_ENEMY_RIGHT
        cmp #FACING_RIGHT
        bne @done                       ; no direction: no side
@probe: jsr probe_tile
        beq @done
        jsr is_nonsolid_tile
        bne bump_or_hammer_jump
@done:  rts

; ---------------------------------------------------------------------------
; bump_or_hammer_jump: an enemy at a wall or an edge: a moving shell in
; enemy numbers 0-4 plays the bump sound; a hammer brother jumps (Y speed
; $FA, the plain jump of launch_hammer_bro_jump); any other kind turns
; (negate_enemy_speed).
;
; In:       A8 I8; D = the enemy's record
; Out:      the sound, the turn or the jump
; Changes:  A, Y
; Keeps:    X, D
; Time:     about 60 cycles
; Original: $E124-$E142 (bump_or_hammer_jump)
; ---------------------------------------------------------------------------
bump_or_hammer_jump:
.a8
.i8
        lda Object::slot
        cmp #SLOT_SPECIAL
        beq @kind
        lda Object::state
        bpl @kind
        lda #SQUARE1_BUMP
        sta snd_square1_queue
@kind:  lda Object::kind
        cmp #KIND_HAMMER_BRO
        beq @jump
        jmp negate_enemy_speed
@jump:  ldy #HAMMER_JUMP_HIGH
        lda #HAMMER_PLAIN_JUMP
        jmp launch_hammer_bro_jump ; D = the brother, Y = the jump's Y speed, A = the jump kind

; ---------------------------------------------------------------------------
; player_enemy_gap: the enemy's world X - the player's world X, one 16-bit
; subtract.
;
; In:       A8 I8; D = the enemy's record
; Out:      enemy_gap = the gap (page and pixel); A = its page part, N its
;           sign (set: the enemy is left of the player); carry set when the
;           enemy's X is the player's or more (the original's carry of its
;           page subtraction, used by the enemy routines)
; Changes:  A
; Keeps:    X, Y, D
; Time:     about 30 cycles
; Original: $E143-$E14E (player_enemy_gap)
; ---------------------------------------------------------------------------
player_enemy_gap:
.a8
.i8
        a16
        lda Object::x_pos
        sec
        sbc player_object+Object::x_pos
        sta enemy_gap
        a8
        xba                             ; the page part; N and Z from it, the carry stays
        rts

; ---------------------------------------------------------------------------
; enemy_lands: the enemy stops falling (its Y speed and fraction 0) and
; stands on its row (Y = (Y AND $F0) OR 8).
;
; In:       A8 I8; D = the enemy's record
; Out:      the enemy's Y speed and Y
; Changes:  A
; Keeps:    X, Y, D
; Time:     about 30 cycles
; Original: $E14F-$E15A (enemy_lands, with clear_enemy_vspeed $C363)
; ---------------------------------------------------------------------------
enemy_lands:
.a8
.i8
        a16
        stz Object::y_speed
        a8
        lda Object::y_pos
        and #ROW_MASK
        ora #ENEMY_STAND_Y
        sta Object::y_pos
        rts

; ---------------------------------------------------------------------------
; enemy_y_plus_62: the Y range of the enemy tile tests: carry set for Y 6 to
; $C1 ((Y + $3E) AND $FF >= $44, as the original's test).
;
; In:       A8 I8; D = the enemy's record
; Out:      carry
; Changes:  A
; Keeps:    X, Y, D
; Time:     under 20 cycles
; Original: $E15B-$E162 (enemy_y_plus_62)
; ---------------------------------------------------------------------------
enemy_y_plus_62:
.a8
.i8
        lda Object::y_pos
        clc
        adc #$FF - ENEMY_TILE_BOTTOM
        cmp #$FF - ENEMY_TILE_BOTTOM + ENEMY_TILE_TOP
        rts

; ---------------------------------------------------------------------------
; enemy_land_check: the jumping paratroopa and the star power-up: in the Y
; range, falling (Y speed + 2 >= 3) and with ground under it (not 0, not
; passable), it lands and jumps again (Y speed $FD). Then check_enemy_sides,
; also outside the range.
;
; In:       A8 I8; D = the enemy's record
; Out:      the enemy's Y, Y speed; check_enemy_sides
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 250 cycles
; Original: $E163-$E184 (enemy_land_check)
; ---------------------------------------------------------------------------
enemy_land_check:
.a8
.i8
        jsr enemy_y_plus_62
        bcc @sides
        lda Object::y_speed_whole
        clc
        adc #JUMP_TEST_SPEED
        cmp #JUMP_FALLING
        bcc @sides
        jsr tile_under_enemy
        beq @sides
        jsr is_nonsolid_tile
        beq @sides
        jsr enemy_lands
        lda #ENEMY_HOP_SPEED
        sta Object::y_speed_whole
@sides: jmp check_enemy_sides

; ---------------------------------------------------------------------------
; hammer_bro_tile_check: the hammer brother's ground: nothing under it: it
; is in the air (state bit 0). A block in motion: knocked out. Ground: while
; its frame timer runs (the jump passes through the bricks) it stays in the
; air; at 0 it lands (state AND $88) and checks its sides.
;
; In:       A8 I8; D = the brother's record
; Out:      the brother's state, Y, Y speed
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 200 cycles
; Original: $E185-$E18D, $E196-$E1AD (hammer_bro_tile_check)
; ---------------------------------------------------------------------------
hammer_bro_tile_check:
.a8
.i8
        jsr tile_under_enemy
        beq @in_air
        cmp #METATILE_BUMPED
        beq kill_enemy_on_bumped_block
        ldx Object::slot
        lda timers+TIMER_ENEMY_FRAME-SLOT_ENEMY,x
        bne @in_air
        lda Object::state
        and #HAMMER_KEEP
        sta Object::state
        jsr enemy_lands
        jmp check_enemy_sides
@in_air:
        lda #HAMMER_IN_AIR
        tsb Object::state
        rts

; ---------------------------------------------------------------------------
; kill_enemy_on_bumped_block: an enemy on a block in motion is knocked out
; and thrown up (Y speed $FC).
;
; In:       A8 I8; D = the enemy's record
; Out:      knock_out_enemy, the Y speed
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 200 cycles
; Original: $E18E-$E195 (kill_enemy_on_bumped_block)
; ---------------------------------------------------------------------------
kill_enemy_on_bumped_block:
.a8
.i8
        jsr knock_out_enemy
        lda #BUMPED_ENEMY_SPEED
        sta Object::y_speed_whole
        rts

; ---------------------------------------------------------------------------
; tile_under_enemy: the metatile under an enemy's feet (POINT_ENEMY_FEET).
;
; In:       A8 I8; D = the enemy's record
; Out:      as probe_tile
; Changes:  A, X, Y, probe_column, probe_row
; Keeps:    D
; Time:     about 115 cycles
; Original: $E1AE-$E1B4 (tile_under_enemy)
; ---------------------------------------------------------------------------
tile_under_enemy:
.a8
.i8
        ldy #POINT_ENEMY_FEET
        jmp probe_tile

; ===========================================================================
; The fireballs
; ===========================================================================

; ---------------------------------------------------------------------------
; fireball_vs_tiles: a fireball over solid ground (from Y $18 down): while
; it falls and has not bounced it bounces (Y speed $FD, onto an 8-pixel
; step); rising or still bouncing it bursts with the bump sound. Off the
; ground its bounce flag clears.
;
; In:       A8 I8; D = the fireball's record
; Out:      the fireball's state, Y, Y speed, bounce
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 160 cycles
; Original: $E1C8-$E1FC (fireball_vs_tiles)
; ---------------------------------------------------------------------------
fireball_vs_tiles:
.a8
.i8
        lda Object::y_pos
        cmp #FIREBALL_TEST_TOP
        bcc @free
        ldy #POINT_FIREBALL
        jsr probe_tile
        beq @free
        jsr is_nonsolid_tile
        beq @free
        lda Object::y_speed_whole
        bmi @burst
        lda Object::bounce
        bne @burst
        lda #FIREBALL_BOUNCE_SPEED
        sta Object::y_speed_whole
        lda #FIREBALL_BOUNCING
        sta Object::bounce
        lda Object::y_pos
        and #FIREBALL_ROW_MASK
        sta Object::y_pos
        rts
@free:  stz Object::bounce
        rts
@burst: lda #FIREBALL_BURST
        sta Object::state
        lda #SQUARE1_BUMP
        sta snd_square1_queue
        rts

; ---------------------------------------------------------------------------
; fireballs_vs_enemies: a flying fireball against enemy numbers 4 down to 0
; (never 5), on even frames. An enemy is skipped when it is defeated,
; inactive, a large lift, a goomba in state 2 or more, or off the screen by
; its mask. A touch bursts the fireball (state $80) and runs
; fireball_hits_enemy; the loop goes on, so a burst fireball can still hit
; a lower enemy number in the same frame. The enemy boxes are those that
; the enemy loop built in the frame before.
;
; In:       A8 I8; D = the fireball's record
; Out:      the fireball's state; fireball_hits_enemy
; Changes:  A, X, Y, fireball_box, fireball_slot, fireball_victim
; Keeps:    D
; Time:     on even frames, about 800 cycles for five enemies
; Original: $D6D9-$D735 (fireballs_vs_enemies)
; ---------------------------------------------------------------------------
fireballs_vs_enemies:
.a8
.i8
        lda Object::state
        beq @done                       ; no fireball
        bmi @done                       ; it bursts
        lda frame_count
        lsr a
        bcs @done                       ; odd frames: none
        lda Object::slot
        sta fireball_slot
        asl a
        asl a
        sta fireball_box                ; its box number is its slot
        phd
        lda #FIREBALL_TESTED_ENEMIES - 1
        sta fireball_victim
@enemy: lda fireball_victim
        clc
        adc #SLOT_ENEMY
        tax
        object_from_x                   ; D = the enemy
        lda Object::state
        and #ENEMY_DEFEATED
        bne @next
        lda Object::active
        beq @next
        lda Object::kind
        cmp #KIND_BALANCE_LIFT
        bcc @goomba
        cmp #KIND_LIFTS_END
        bcc @next                       ; a large lift
@goomba:
        cmp #KIND_GOOMBA
        bne @mask
        lda Object::state
        cmp #ENEMY_FLIPPED
        bcs @next                       ; a flat or defeated goomba
@mask:  lda Object::offscreen
        bne @next
        lda Object::slot
        asl a
        asl a
        tax                             ; the enemy's box (A)
        ldy fireball_box                ; the fireball's box (B)
        jsr hit_box_overlap
        bcc @next
; The fireball bursts, then the hit.
        phd
        ldx fireball_slot
        object_from_x
        lda #FIREBALL_BURST
        sta Object::state
        pld
        jsr fireball_hits_enemy         ; D = the enemy
@next:  dec fireball_victim
        bpl @enemy
        pld
@done:  rts

; ---------------------------------------------------------------------------
; fireball_hits_enemy: what a fireball does to the enemy it touches. The
; enemy's screen place is taken first (the score number's X). A part of
; Bowser (active bit 7, his slot in the low nybble) hurts Bowser. Buzzy
; beetles, wave bullet bills, lava balls and the kinds from $15 up take no
; harm; Bowser loses a hit, and at the last one he falls: no speeds, no
; wave, a small hop, his kind the world's disguise, defeated (+3 in worlds
; 1-3), the fall sound, 5000 points for the part that was hit, the smack
; sound. Any other enemy: knock_out_enemy.
;
; In:       A8 I8; D = the enemy's record
; Out:      as the rules say
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 300 cycles
; Original: $D73E-$D794 (fireball_hits_enemy)
; ---------------------------------------------------------------------------
fireball_hits_enemy:
.a8
.i8
        jsr enemy_screen_position       ; the sprite part: rel_x, rel_y of REL_ENEMY
        phd                             ; the enemy that was hit: its score number
        lda Object::active
        bpl @own
        and #SECOND_HALF_OF
        clc
        adc #SLOT_ENEMY
        tax
        object_from_x                   ; D = the object's first half
        lda Object::kind
        cmp #KIND_BOWSER
        beq @bowser
        pld
        phd
@own:   lda Object::kind
        cmp #KIND_BUZZY_BEETLE
        beq @done
        cmp #KIND_BOWSER
        beq @bowser
        cmp #KIND_BULLET_FRENZY
        beq @done
        cmp #KIND_PODOBOO
        beq @done
        cmp #KIND_BOWSER_FLAME
        bcs @done
        pld
        jmp knock_out_enemy
@bowser:
        dec bowser_hits
        bne @done
        a16
        stz Object::y_speed
        a8
        stz Object::x_speed
        stz frenzy_kind
        lda #BOWSER_HOP_SPEED
        sta Object::y_speed_whole
        ldy player_record+PlayerRecord::world
        lda bowser_disguises,y
        sta Object::kind
        lda #ENEMY_DEFEATED
        cpy #BOWSER_FALL_WORLDS
        bcs @fall
        ora #BOWSER_EARLY_STATE
@fall:  sta Object::state
        lda #SQUARE2_BOWSER_FALL
        sta snd_square2_queue
        pld                             ; D = the part that was hit
        lda #SCORE_5000
        jsr start_score_number
        lda #SQUARE1_ENEMY_SMACK
        sta snd_square1_queue
        rts
@done:  pld
        rts

; ---------------------------------------------------------------------------
; knock_out_enemy: an enemy is defeated by a fireball, the star, a moving
; shell or a block in motion: a piranha plant drops 25 pixels; the stun
; depends on the kind (for a piranha plant, on its new Y); the defeated state, the score number (200; a hammer brother 1000, a
; goomba 100) and the smack sound.
;
; In:       A8 I8; D = the enemy's record
; Out:      as the rules say
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 200 cycles
; Original: $D795-$D7C3 (knock_out_enemy)
; ---------------------------------------------------------------------------
knock_out_enemy:
.a8
.i8
        lda Object::kind
        cmp #KIND_PIRANHA
        bne @stun
        lda Object::y_pos
        clc
        adc #PIRANHA_DROP               ; the original's add of 24 and the carry of its compare
        sta Object::y_pos
@stun:  jsr stun_enemy_by_kind          ; A = the kind, or the piranha plant's Y
        lda Object::state
        and #<~(ENEMY_KICKED | ENEMY_DROP | ENEMY_DEFEATED) ; the flag bits off,
        ora #ENEMY_DEFEATED             ; then defeated
        sta Object::state
        lda #SCORE_200
        ldy Object::kind
        cpy #KIND_HAMMER_BRO
        bne @goomba
        lda #SCORE_1000
@goomba:
        cpy #KIND_GOOMBA
        bne @score
        lda #SCORE_100
@score: jsr start_score_number
        lda #SQUARE1_ENEMY_SMACK
        sta snd_square1_queue
        rts

; ===========================================================================
; The player against the enemies and the hammers
; ===========================================================================

; ---------------------------------------------------------------------------
; hammer_hits_player: a hammer against the player, on odd frames, unless the
; timers wait (that stands for the task test) or the hammer is partly off
; the screen. Apart: its contact byte clears. A touch acts once: the
; contact byte, the hammer flies back, and without the star hurt_player. The
; player's box is the last one that the control routine built.
;
; In:       A8 I8; D = the hammer's record
; Out:      Object::misc_hit, the hammer's X speed, hurt_player
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 100 cycles
; Original: $D7C4-$D7FF (hammer_hits_player)
; ---------------------------------------------------------------------------
hammer_hits_player:
.a8
.i8
        lda frame_count
        lsr a
        bcc @done                       ; even frames: none
        lda timer_hold
        ora offscreen_bits+REL_MISC
        bne @done
        lda Object::slot
        sec
        sbc #SLOT_MISC - BOX_OF_MISC
        asl a
        asl a
        tay                             ; the hammer's box (B)
        jsr player_vs_object
        bcc @apart
        lda Object::misc_hit
        bne @done                       ; this touch acted already
        lda #HAMMER_TOUCHED
        sta Object::misc_hit
        lda Object::x_speed
        eor #ALL_BITS
        inc a                           ; the two's complement
        sta Object::x_speed
        lda timers+TIMER_STAR
        bne @done
        jmp hurt_player
@apart: stz Object::misc_hit
@done:  rts

; ---------------------------------------------------------------------------
; collect_powerup: the player takes the power-up: its slot is cleared, 1000
; points, the power-up sound. The mushroom or flower: a small player grows
; (power 1, the change of size task), a big one becomes fiery (power 2, his
; colours, the fire flower task), a fiery one gets the points only. The
; star: the star timer and the star song. The 1-up: the score number
; becomes the 1-up (no points; the life comes at its sixth step).
;
; In:       A8 I8; D = the power-up's record (enemy slot 5)
; Out:      as the rules say
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 300 cycles
; Original: $D800-$D846 (collect_powerup), $D847-$D84C (become_fiery)
; ---------------------------------------------------------------------------
collect_powerup:
.a8
.i8
        jsr clear_enemy_slot ; D = the slot
        lda #SCORE_1000
        jsr start_score_number
        lda #SQUARE2_POWERUP_GRAB
        sta snd_square2_queue
        lda powerup_kind
        cmp #POWERUP_STAR
        bcc @grow
        cmp #POWERUP_1UP
        beq @life
        lda #STAR_TIME
        sta timers+TIMER_STAR
        lda #SONG_STAR
        sta snd_area_queue
        rts
@life:  lda #SCORE_1UP
        sta Object::score_kind
        rts
@grow:  lda player_power
        beq @big
        cmp #POWER_BIG
        bne @done                       ; fiery: the points only
        lda #POWER_FIRE
        sta player_power
        jsr queue_player_colors         ; the screen part
        lda #PLAYER_TASK_FIRE_FLOWER
        bra @task
@big:   lda #POWER_BIG
        sta player_power
        lda #PLAYER_TASK_CHANGE_SIZE
@task:  ldy #PLAYER_ON_GROUND
        jmp set_player_routine
@done:  rts

; ---------------------------------------------------------------------------
; player_hits_enemy: the player against an enemy, on even frames, while the
; player is in the control task and on the screen, and the enemy is on the
; screen (by its mask) and not defeated. Apart: the contact bit clears (the
; next touch acts). A touch: the power-up is taken; with the star the enemy
; is knocked out; else a touch acts once (the contact bit): by kind
;   spiny, cannon bullet bill: the stomp check;
;   piranha plant, lava ball, kinds from $15, any kind in a water area:
;     hurt_player;
;   a moving shell, or state AND 7 below 2: the stomp check;
;   a flat goomba: nothing; a still shell: the kick.
; The kick: the smack sound, the shell moves away from the player (score
; 400 + the stomp chain, or shell_chain_scores while its timer is below 3).
; The stomp check: a stomp when the player falls, or (kinds 7 up) when his Y
; + 12 is above the enemy's, or while the stomp timer runs; else, unless the
; player blinks, an enemy that moves away from him turns, then hurt_player.
; The stomp: a spiny hurts; else the stomp sound and by kind:
;   the flyers, the hammer brother, Lakitu, the blooper: their score, the
;     lift of the stun (its other changes are replaced), defeated, no
;     speeds, the player's bounce $FD;
;   other kinds 9 and up: the paratroopa loses its wings (kind AND 1),
;     walks again, 400 points, moves away from the player;
;   below 9: flat or a shell (state 4), the stomp chain and its score (the
;     chain + the stomp timer), the stomp timer + 1, the revive time.
; The enemy box lags one move behind the enemy.
;
; In:       A8 I8; D = the enemy's record; its screen place (REL_ENEMY)
; Out:      as the rules say
; Changes:  A, X, Y
; Keeps:    D
; Time:     on even frames about 150 cycles without a touch
; Original: $D853-$D891, $D895-$D92B, $D969-$D9F0 (player_hits_enemy)
; ---------------------------------------------------------------------------
player_hits_enemy:
.a8
.i8
        lda frame_count
        lsr a
        bcs @done                       ; odd frames: none
        jsr player_out_of_range
        bcs @done
        lda Object::offscreen
        bne @done
        lda player_task
        cmp #PLAYER_TASK_CONTROL
        bne @done
        lda Object::state
        and #ENEMY_DEFEATED
        bne @done
        lda Object::slot
        asl a
        asl a
        tay                             ; the enemy's box (B)
        jsr player_vs_object
        bcs @touch
        lda #CONTACT_PLAYER
        trb Object::collision           ; apart: the next touch acts
@done:  rts
@touch: lda Object::kind
        cmp #KIND_POWERUP
        bne @star
        jmp collect_powerup
@star:  lda timers+TIMER_STAR
        beq @contact
        jmp knock_out_enemy
@contact:
        lda Object::collision
        and #CONTACT_PLAYER
        ora Object::offscreen
        bne @done                       ; one touch acts once
        lda #CONTACT_PLAYER
        tsb Object::collision
        ldy Object::kind
        cpy #KIND_SPINY
        beq stomp_check
        cpy #KIND_PIRANHA
        beq @hurt
        cpy #KIND_PODOBOO
        beq @hurt
        cpy #KIND_BULLET_CANNON
        beq stomp_check
        cpy #KIND_BOWSER_FLAME
        bcs @hurt
        lda area_type
        beq @hurt                       ; a water area: every touch hurts
        lda Object::state
        bmi stomp_check                 ; a moving shell
        and #ENEMY_STATE_BITS
        cmp #ENEMY_FLIPPED
        bcc stomp_check
        cpy #KIND_GOOMBA
        beq @done                       ; a flat goomba
; The kick of a still shell.
        lda #SQUARE1_ENEMY_SMACK
        sta snd_square1_queue
        lda #ENEMY_KICKED
        tsb Object::state
        jsr turn_enemy_toward_player
        lda kicked_shell_speeds,y
        sta Object::x_speed
        lda #SCORE_400
        clc
        adc stomp_chain
        ldx Object::slot
        ldy timers+TIMER_ENEMY_INTERVAL-SLOT_ENEMY,x
        cpy #KICK_SCORE_TIMES
        bcs @kick_score
        lda shell_chain_scores,y        ; 8000, 1000, 500 by the shell's timer
@kick_score:
        jmp start_score_number
@hurt:  jmp hurt_player

; ---------------------------------------------------------------------------
; stomp_check: the stomp or the hurt: a stomp when
; the player falls, or for kinds 7 and up when his Y + 12 is above the
; enemy's Y, or while the stomp timer runs (a stomp in this frame); else,
; unless he blinks, an enemy that moves away from him turns, then
; hurt_player.
;
; In:       A8 I8; D = the enemy's record; rel_x of REL_PLAYER and REL_ENEMY
; Out:      enemy_stomped, or the hurt
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 50 cycles to the hurt
; Original: $D8F9-$D92B (in player_hits_enemy)
; ---------------------------------------------------------------------------
stomp_check:
.a8
.i8
        lda player_object+Object::y_speed_whole
        bmi @not_falling
        bne enemy_stomped               ; he falls
@not_falling:
        lda Object::kind
        cmp #KIND_BLOOPER
        bcc @timer
        lda player_object+Object::y_pos
        clc
        adc #STOMP_REACH
        cmp Object::y_pos
        bcc enemy_stomped
@timer: lda timers+TIMER_STOMP
        bne enemy_stomped               ; a stomp in this frame already
        lda timers+TIMER_INJURY
        bne @done
        lda rel_x+REL_PLAYER
        cmp rel_x+REL_ENEMY
        bcs hurt_if_facing_right
        lda Object::direction
        cmp #FACING_RIGHT
        bne hurt_player                 ; it moves toward the player
        jmp turn_enemy_then_hurt
@done:  rts

; ---------------------------------------------------------------------------
; hurt_if_facing_right: an enemy moving right hurts the player as it is;
; one moving left turns first (turn_enemy_then_hurt). turn_enemy_then_hurt:
; reverse_enemy, then hurt_player. hurt_player: nothing while the player
; blinks (the injury timer), else force_player_hurt. force_player_hurt: a
; big or fiery player becomes small, blinks for 8 slow ticks, the injury
; sound, his colours, the injury task; a small player dies: no X speed, the
; death song, Y speed $FC, the death task. set_player_routine: the task
; (A), the player's state (Y), the timers wait (timer_hold $FF; the frame
; counts it down) and no scroll in this frame.
;
; In:       A8 I8; D = the enemy's record (hurt_if_facing_right,
;           turn_enemy_then_hurt); any D (the others);
;           set_player_routine: A = the player task, Y = the player's state
; Out:      as the rules say
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 150 cycles with the colours
; Original: $D9F6-$D9FE (hurt_if_facing_right), $D9FF-$DA04
;           (turn_enemy_then_hurt), $D92C-$D930 (hurt_player), $D931-$D947
;           and $D958-$D964 (force_player_hurt), $D948-$D957
;           (set_player_routine)
; ---------------------------------------------------------------------------
hurt_if_facing_right:
.a8
.i8
        lda Object::direction
        cmp #FACING_RIGHT
        beq hurt_player
turn_enemy_then_hurt:
.a8
.i8
        jsr reverse_enemy
hurt_player:
.a8
.i8
        lda timers+TIMER_INJURY
        beq force_player_hurt
        rts
force_player_hurt:
.a8
.i8
        lda player_power
        beq @dies
        stz player_power                ; POWER_SMALL
        lda #INJURY_TIME
        sta timers+TIMER_INJURY
        lda #SQUARE1_PIPE_INJURY
        sta snd_square1_queue
        jsr queue_player_colors         ; the screen part
        lda #PLAYER_TASK_INJURY
        ldy #HURT_STATE
        bra set_player_routine
@dies:  stz player_object+Object::x_speed
        lda #EVENT_DEATH
        sta snd_event_queue
        lda #DEATH_JUMP_SPEED
        sta player_object+Object::y_speed_whole
        lda #PLAYER_TASK_DEATH
        ldy #HURT_STATE
set_player_routine:
.a8
.i8
        sta player_task
        sty player_object+Object::state
        lda #TIMER_HOLD_ALL
        sta timer_hold
        stz scroll_amount
        rts
.assert POWER_SMALL = 0, error, "force_player_hurt: stz sets the power"

; ---------------------------------------------------------------------------
; enemy_stomped: what a stomp does, by the enemy's
; kind: a spiny hurts the player; else the stomp sound, then the flyers'
; group, a paratroopa, or a goomba, koopa or buzzy beetle (see
; player_hits_enemy).
;
; In:       A8 I8; D = the enemy's record
; Out:      as the rules say
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 150 cycles
; Original: $D969-$D9F0 (in player_hits_enemy)
; ---------------------------------------------------------------------------
enemy_stomped:
.a8
.i8
        lda Object::kind
        cmp #KIND_SPINY
        beq hurt_player
        lda #SQUARE1_ENEMY_STOMP
        sta snd_square1_queue
        lda Object::kind
        ldy #STOMP_GROUP_FLYER
        cmp #KIND_FLYING_CHEEP
        beq @group
        cmp #KIND_BULLET_FRENZY
        beq @group
        cmp #KIND_BULLET_CANNON
        beq @group
        cmp #KIND_PODOBOO               ; never reached: the lava ball hurts above
        beq @group
        iny
        cmp #KIND_HAMMER_BRO
        beq @group
        iny
        cmp #KIND_LAKITU
        beq @group
        iny
        cmp #KIND_BLOOPER
        beq @group
        cmp #KIND_TALL
        bcc @shell
; A paratroopa loses its wings.
        and #KOOPA_COLOUR
        sta Object::kind
        stz Object::state               ; ENEMY_WALKING
        lda #SCORE_400
        jsr start_score_number
        a16
        stz Object::y_speed
        a8
        jsr turn_enemy_toward_player
        lda demoted_koopa_speeds,y
        sta Object::x_speed
        jmp bounce_player
; A flyer, a hammer brother, Lakitu, a blooper: defeated at once. Of
; stun_enemy's changes only its lift of 2 pixels stays: the state and the
; speeds are set below, and the original keeps the direction.
@group: lda stomp_score_codes,y
        jsr start_score_number
        dec Object::y_pos
        dec Object::y_pos
        lda #ENEMY_DEFEATED
        sta Object::state
        a16
        stz Object::y_speed
        a8
        stz Object::x_speed
        lda #STOMP_BOUNCE_LOW
        sta player_object+Object::y_speed_whole
        rts
; A goomba, a koopa, a buzzy beetle: flat or in its shell.
@shell: lda #ENEMY_STOMPED
        sta Object::state
        inc stomp_chain
        lda stomp_chain
        clc
        adc timers+TIMER_STOMP
        jsr start_score_number
        inc timers+TIMER_STOMP          ; 1 for the rest of this frame
        ldy hard_mode
        lda shell_revive_times,y
        ldx Object::slot
        sta timers+TIMER_ENEMY_INTERVAL-SLOT_ENEMY,x
        jmp bounce_player
.assert ENEMY_WALKING = 0, error, "enemy_stomped: stz sets the state"

; ---------------------------------------------------------------------------
; bounce_player: the player bounces up from a stomp (Y speed $FC).
;
; In:       A8 I8; any D
; Out:      the player's Y speed
; Changes:  A
; Keeps:    X, Y, D
; Time:     under 10 cycles
; Original: $D9F1-$D9F5 (bounce_player)
; ---------------------------------------------------------------------------
bounce_player:
.a8
.i8
        lda #STOMP_BOUNCE
        sta player_object+Object::y_speed_whole
        rts

; ---------------------------------------------------------------------------
; turn_enemy_toward_player: the enemy's direction is the side of the player
; that it is on: right (1) at or right of the player, else left (2); so it
; moves away from him.
;
; In:       A8 I8; D = the enemy's record
; Out:      its direction; Y = the direction - 1 (the index of the speed
;           tables); enemy_gap
; Changes:  A, Y
; Keeps:    X, D
; Time:     about 45 cycles
; Original: $DA05-$DA10 (turn_enemy_toward_player)
; ---------------------------------------------------------------------------
turn_enemy_toward_player:
.a8
.i8
        ldy #FACING_RIGHT
        jsr player_enemy_gap
        bpl @store
        iny
@store: sty Object::direction
        dey
        rts

; ===========================================================================
; The enemies against the enemies
; ===========================================================================

; ---------------------------------------------------------------------------
; enemies_bump_enemies: an enemy against the enemy numbers below it, on odd
; frames, outside water areas. The first enemy is the caller's; none for the
; kinds from $15, Lakitu, the piranha plant, or off the screen by its mask.
; A second enemy is skipped when it is inactive or of those kinds or masks.
; A touch with a moving shell in either: resolve_enemy_bump each frame;
; else once (the first enemy's bit in the second's contact bits, which
; clears when they are apart).
;
; In:       A8 I8; D = the first enemy's record
; Out:      the contact bits; resolve_enemy_bump
; Changes:  A, X, Y, the bump_* variables
; Keeps:    D
; Time:     on odd frames about 150 cycles for each lower enemy
; Original: $DA33-$DA55, $DA56-$DAA9, $DAAA-$DAB3 (enemies_bump_enemies,
;           its pair test and next_enemy_pair)
; ---------------------------------------------------------------------------
enemies_bump_enemies:
.a8
.i8
        lda frame_count
        lsr a
        bcc @exit                       ; even frames: none
        lda area_type
        beq @exit                       ; a water area
        lda Object::kind
        cmp #KIND_BOWSER_FLAME
        bcs @exit
        cmp #KIND_LAKITU
        beq @exit
        cmp #KIND_PIRANHA
        beq @exit
        lda Object::offscreen
        beq @first
@exit:  rts
@first: lda Object::slot
        asl a
        asl a
        sta bump_first_box
        lda Object::slot
        sec
        sbc #SLOT_ENEMY
        beq @exit                       ; enemy number 0: none below
        tax
        lda enemy_bit_masks,x
        sta bump_first_bit
        dex
        stx bump_second
        phd
        tdc
        a16
        sta bump_first
        a8
@pair:  lda bump_second
        clc
        adc #SLOT_ENEMY
        tax
        object_from_x                   ; D = the second enemy
        lda Object::active
        beq @next
        lda Object::kind
        cmp #KIND_BOWSER_FLAME
        bcs @next
        cmp #KIND_LAKITU
        beq @next
        cmp #KIND_PIRANHA
        beq @next
        lda Object::offscreen
        bne @next
        lda Object::slot
        asl a
        asl a
        tax                             ; the second's box (A)
        ldy bump_first_box              ; the first's box (B)
        jsr hit_box_overlap
        bcc @apart
        jsr first_enemy_state
        ora Object::state
        bmi @resolve                    ; a moving shell in either
        lda bump_first_bit
        and Object::collision
        bne @next                       ; this touch acted already
        lda bump_first_bit
        tsb Object::collision
@resolve:
        jsr resolve_enemy_bump
        bra @next
@apart: lda bump_first_bit
        trb Object::collision
@next:  dec bump_second
        bpl @pair
        pld
        rts

; ---------------------------------------------------------------------------
; first_enemy_state: the first enemy's state, read through its record's
; address (bump_first) while D is the second enemy's.
;
; In:       A8 I8; bump_first
; Out:      A = the state, N and Z from it
; Changes:  A, X
; Keeps:    Y, D
; Time:     about 20 cycles
; Original: none (the original reads both states by index)
; ---------------------------------------------------------------------------
first_enemy_state:
.a8
.i8
        x16
        ldx bump_first
        lda a:Object::state,x
        sep #P_X8
        .i8
        rts

; use_bump_first: D = the first enemy's record (bump_first). In: A8. Out:
; A8. Changes: A (both bytes).
.macro use_bump_first
        a16
        lda bump_first
        tcd
        a8
.endmacro

; ---------------------------------------------------------------------------
; resolve_enemy_bump: two enemies touch.
;   Either defeated: nothing.
;   The first in state 6 or more (a moving shell; not a hammer brother):
;     when the second is a moving shell too, the first is knocked out
;     (its score number is the knock-out's: the original's 1000 before it
;     never shows); the second is knocked out with the score
;     4 + the first's shell chain; the first's chain + 1.
;   Else the second in state 6 or more (not a hammer brother): the first is
;     knocked out with the score 4 + the second's chain; the second's chain
;     + 1.
;   Else both turn: the second, then the first.
; Every score number takes the screen X of the first enemy (the enemy
; group's place).
;
; In:       A8 I8; D = the second enemy's record; bump_first = the first's
; Out:      as the rules say
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 500 cycles with a knock-out
; Original: $DAB4-$DB1B (resolve_enemy_bump)
; ---------------------------------------------------------------------------
resolve_enemy_bump:
.a8
.i8
        phd                             ; the second
        jsr first_enemy_state
        ora Object::state
        and #ENEMY_DEFEATED
        bne @done
        jsr first_enemy_state
        cmp #ENEMY_SHELL_STATES
        bcc @second_shell
; The first is a moving shell.
        use_bump_first                  ; D = the first
        lda Object::kind
        cmp #KIND_HAMMER_BRO
        beq @done
        pld
        phd                             ; D = the second
        lda Object::state
        bpl @second_hit
        use_bump_first
        jsr knock_out_enemy             ; two shells: the first falls too
        pld
        phd
@second_hit:
        jsr knock_out_enemy
        use_bump_first
        lda Object::shell_chain
        inc Object::shell_chain
        pld
        phd                             ; D = the second
        clc
        adc #SCORE_500
        jsr start_score_number
        bra @done
; The second is a moving shell, or both turn.
@second_shell:
        lda Object::state
        cmp #ENEMY_SHELL_STATES
        bcc @turn
        lda Object::kind
        cmp #KIND_HAMMER_BRO
        beq @done
        lda Object::shell_chain
        inc Object::shell_chain
        pha
        use_bump_first
        jsr knock_out_enemy
        pla
        clc
        adc #SCORE_500
        jsr start_score_number
        bra @done
@turn:  jsr reverse_enemy               ; the second, then the first
        use_bump_first
        jsr reverse_enemy
@done:  pld
        rts

; ---------------------------------------------------------------------------
; reverse_enemy: an enemy turns at another enemy: the spiny, the jumping
; paratroopa and the kinds below 7 (negate_enemy_speed); the piranha plant,
; Lakitu, the hammer brother and the other kinds keep their way.
; negate_enemy_speed: the X speed takes its other sign and the direction
; the other way.
;
; In:       A8 I8; D = the enemy's record
; Out:      its X speed, direction
; Changes:  A
; Keeps:    X, Y, D
; Time:     under 50 cycles
; Original: $DB1C-$DB35 (reverse_enemy), $DB36-$DB44 (negate_enemy_speed)
; ---------------------------------------------------------------------------
reverse_enemy:
.a8
.i8
        lda Object::kind
        cmp #KIND_PIRANHA
        beq @keep
        cmp #KIND_LAKITU
        beq @keep
        cmp #KIND_HAMMER_BRO
        beq @keep
        cmp #KIND_SPINY
        beq negate_enemy_speed
        cmp #KIND_GREEN_PARATROOPA_JUMP
        beq negate_enemy_speed
        cmp #KIND_BLOOPER
        bcc negate_enemy_speed
@keep:  rts
negate_enemy_speed:
.a8
.i8
        lda Object::x_speed
        eor #ALL_BITS
        inc a                           ; the two's complement
        sta Object::x_speed
        lda Object::direction
        eor #DIR_SWAP
        sta Object::direction
        rts

; ===========================================================================
; The lifts and the player
; ===========================================================================

; ---------------------------------------------------------------------------
; big_lift_hit_test: the player against a large lift, each frame before the
; lift moves: the lift's player byte is cleared ($FF); nothing while the
; timers wait or the lift's state has bit 7. A balance lift tests its
; partner (whose enemy number is in its state) first, then itself; other
; kinds only themselves.
; check_player_on_big_lift: one lift's box (enemy number A) against the
; player's box, unless the player is out of range; a touch: resolve_lift_hit
; with that lift's number as the player byte's value. When the tested slot
; holds a small lift's kind, the original's resolve_lift_hit takes the
; byte that this test leaves in its scratch $00 instead: that lift's Y (only
; a balance lift's state can name such a slot).
;
; In:       A8 I8; D = the lift's record; check_player_on_big_lift: A = the
;           tested lift's enemy number
; Out:      Object::on_lift, resolve_lift_hit
; Changes:  A, X, Y, lift_player_value
; Keeps:    D
; Time:     about 150 cycles for each lift without a touch
; Original: $DB45-$DB5E (big_lift_hit_test), $DB5F-$DB7A
;           (check_player_on_big_lift)
; ---------------------------------------------------------------------------
big_lift_hit_test:
.a8
.i8
        lda #LIFT_NOT_ON
        sta Object::on_lift
        lda timer_hold
        bne @done
        lda Object::state
        bpl @test
@done:  rts
@test:  lda Object::kind
        cmp #KIND_BALANCE_LIFT
        bne @own
        lda Object::state               ; the partner's enemy number
        jsr check_player_on_big_lift
@own:   lda Object::slot
        sec
        sbc #SLOT_ENEMY
        ; falls into check_player_on_big_lift

check_player_on_big_lift:
.a8
.i8
        sta lift_player_value
        jsr player_out_of_range
        bcs @done
        lda lift_player_value
        clc
        adc #SLOT_ENEMY                 ; its box number
        asl a
        asl a
        tay
        jsr player_vs_object
        bcc @done
        phd
        lda lift_player_value
        clc
        adc #SLOT_ENEMY
        tax
        object_from_x                   ; D = the tested lift
        lda Object::kind
        cmp #KIND_LINE_LIFT
        beq @lift_y
        cmp #KIND_LINE_LIFT_2
        bne @value
@lift_y:
        lda Object::y_pos               ; the original's $00
        sta lift_player_value
@value: pld
        jmp resolve_lift_hit
@done:  rts

; ---------------------------------------------------------------------------
; small_lift_hit_test: the player against a small lift, each frame: nothing
; while the timers wait; else the player byte becomes 0 and, unless the
; player is out of range, two passes (the lift's place, then 128 pixels
; lower, where the lift is drawn too): the test ends when the lift's third
; column is off the screen; a box from Y $20 down is tested, a touch runs
; resolve_lift_hit with the pass (2, then 1) and ends the test; then the box
; moves 128 pixels down. After a touch in the second pass the box stays
; moved: a fireball of the next frame tests it there.
;
; In:       A8 I8; D = the lift's record
; Out:      Object::on_lift, its box_corners, resolve_lift_hit
; Changes:  A, X, Y, lift_player_value
; Keeps:    D
; Time:     about 200 cycles without a touch
; Original: $DB7B-$DBBB (small_lift_hit_test)
; ---------------------------------------------------------------------------
small_lift_hit_test:
.a8
.i8
        lda timer_hold
        bne @done
        stz Object::on_lift
        jsr player_out_of_range
        bcs @done
        lda #SMALL_LIFT_PASSES
        sta lift_player_value
        lda Object::slot
        asl a
        asl a
        tay                             ; the lift's box (B)
@pass:  lda offscreen_bits+REL_ENEMY
        and #SMALL_LIFT_HIDE
        bne @done
        lda box_corners+CORNER_TOP,y
        cmp #SMALL_LIFT_TOP
        bcc @move
        jsr player_vs_object
        bcc @move
        jmp resolve_lift_hit
@move:  lda box_corners+CORNER_TOP,y
        clc
        adc #SMALL_LIFT_COPY
        sta box_corners+CORNER_TOP,y
        lda box_corners+CORNER_BOTTOM,y
        clc
        adc #SMALL_LIFT_COPY
        sta box_corners+CORNER_BOTTOM,y
        dec lift_player_value
        bne @pass
@done:  rts

; ---------------------------------------------------------------------------
; resolve_lift_hit: the player touches a lift's box: under it while rising
; (the lift's bottom - the player's top below 4): the jump ends (Y speed 1);
; on it while not rising (the player's bottom - the lift's top below 6): the
; lift's player byte = lift_player_value, the player's state 0, done; else
; at its left side (the player's right - the lift's left below 8) or its
; right side (the lift's right - the player's left - 1 below 9):
; block_player_sideways. All differences in 8 bits.
;
; In:       A8 I8; D = the current lift's record (its player byte); Y =
;           CORNERS x the tested lift's box; lift_player_value
; Out:      as the rules say
; Changes:  A, X
; Keeps:    Y, D
; Time:     about 80 cycles
; Original: $DBBC-$DC16 (resolve_lift_hit)
; ---------------------------------------------------------------------------
resolve_lift_hit:
.a8
.i8
        lda box_corners+CORNER_BOTTOM,y
        sec
        sbc box_corners+CORNERS*BOX_OF_PLAYER+CORNER_TOP
        cmp #LIFT_HEAD_REACH
        bcs @on_top
        lda player_object+Object::y_speed_whole
        bpl @on_top
        lda #HEAD_STOP_SPEED
        sta player_object+Object::y_speed_whole
@on_top:
        lda box_corners+CORNERS*BOX_OF_PLAYER+CORNER_BOTTOM
        sec
        sbc box_corners+CORNER_TOP,y
        cmp #LIFT_FOOT_REACH
        bcs @sides
        lda player_object+Object::y_speed_whole
        bmi @sides
        lda lift_player_value
        sta Object::on_lift
        stz player_object+Object::state ; PLAYER_ON_GROUND
        rts
@sides: lda #WALL_RIGHT
        sta wall_side
        lda box_corners+CORNERS*BOX_OF_PLAYER+CORNER_RIGHT
        sec
        sbc box_corners+CORNER_LEFT,y
        cmp #LIFT_SIDE_REACH
        bcc @wall
        lda #WALL_LEFT
        sta wall_side
        lda box_corners+CORNER_RIGHT,y
        clc
        sbc box_corners+CORNERS*BOX_OF_PLAYER+CORNER_LEFT ; less 1 more (the clear carry)
        cmp #LIFT_RIGHT_REACH
        bcs @done
@wall:  jmp block_player_sideways
@done:  rts

; ---------------------------------------------------------------------------
; stand_on_small_lift: the player's feet on a small lift: the lift's Y +
; small_lift_stand_adders[pass] (the box 128 pixels lower for pass 1), then
; the standing part. stand_on_vertical_lift: the lift's Y. The standing part
; (not in the death task, and only for a lift on the screen): the player's Y
; word = (1, the Y) - 32, so Y high takes the borrow; his Y speed and
; fraction 0.
;
; In:       A8 I8; D = the lift's record; stand_on_small_lift: A = the
;           player byte (1 or 2)
; Out:      the player's Y word, Y speed
; Changes:  A, Y
; Keeps:    X, D
; Time:     about 60 cycles
; Original: $DC19-$DC20 (stand_on_small_lift), $DC21-$DC22
;           (stand_on_vertical_lift), $DC23-$DC40 (the standing part)
; ---------------------------------------------------------------------------
stand_on_small_lift:
.a8
.i8
        tay
        lda Object::y_pos
        clc
        adc small_lift_stand_adders-1,y
        bra stand_on_lift
stand_on_vertical_lift:
.a8
.i8
        lda Object::y_pos
stand_on_lift:
.a8
.i8
        ldy player_task
        cpy #PLAYER_TASK_DEATH
        beq @done
        ldy Object::y_pos+1
        cpy #Y_HIGH_SCREEN
        bne @done
        a16
        and #LOW_BYTE
        ora #Y_HIGH_SCREEN << 8
        sec
        sbc #PLAYER_HEIGHT
        sta player_object+Object::y_pos
        stz player_object+Object::y_speed
        a8
@done:  rts

; ---------------------------------------------------------------------------
; player_out_of_range: carry set when the player's four rows are all off the
; screen (offscreen bits $F0 and up), or when he is on the screen (Y high 1)
; at Y $D0 or lower. A player above or below the screen gives carry clear.
;
; In:       A8 I8; any D
; Out:      carry
; Changes:  A
; Keeps:    X, Y, D
; Time:     under 30 cycles
; Original: $DC41-$DC51 (player_out_of_range)
; ---------------------------------------------------------------------------
player_out_of_range:
.a8
.i8
        lda offscreen_bits+REL_PLAYER
        cmp #OFFSCREEN_ROWS
        bcs @done
        lda player_object+Object::y_pos+1
        cmp #Y_HIGH_SCREEN
        bne @clear
        lda player_object+Object::y_pos
        cmp #PLAYER_LOW_EDGE
        rts
@clear: clc
@done:  rts
