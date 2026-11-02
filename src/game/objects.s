; The objects of the game that are not enemies (document 05a sections 4-17;
; the original's $B624-$BF01): the player's fireballs, the air bubbles, the
; game timer, the warp zone object, the whirlpools, the flagpole flag, the
; jump spring, the vine, the cannons and their bullet bills, the hammers,
; the coins that jump out of blocks, the coin and score adds, the power-ups,
; and the blocks that the player's head bumps or breaks.
;
; game_core (03) runs each frame of play, in this order: run_fireballs_and_
; bubbles (step 4), then (after the enemy loop) replace_bumped_metatile,
; run_block_objects for block 1 and block 0, run_misc_objects, run_cannons,
; pull_in_whirlpools, run_flag_object and tick_game_timer (steps 8-14). The
; enemy loop runs run_powerup, run_vine, run_jump_spring and
; warp_zone_exit_check for their kinds (movement.s run_enemy_slot); the
; spawns start set_powerup_start and start_second_vine; the player's head
; test (07 check_player_vs_tiles) calls bump_block_from_below; the area
; start (04 setup_entry_and_timer) calls set_block_place, start_vine and
; launch_bubble. The order of the steps decides some results (05a 1.2): a
; bumped block moves in its bump frame; a bounce that ends in frame N puts
; its metatile back in frame N + 1 at the earliest, and only when screen
; list 1 is empty; a hammer thrown in the enemy loop flies in the same frame;
; a cannon's bullet bill first moves in the next frame.
;
; Data in: the object records (state.inc), the pads, the timers, the random
; bits, the collision buffers (the cell of the last tile probe in probe_row
; and probe_column, as 07 and 02 name it), the tables of
; scripts/objects_data.py. Data out: the records, the collision buffers, the
; digit store and screen list 1 (through 07's add_digit_amounts and
; print_coins_and_score, and 02's block pictures), the sound commands.
;
; Registers: A8 I8 at each entry and exit unless a header says otherwise.
; DBR = bank 0. D = the record of the object that a routine works on; a
; routine that steps D over other records puts it back. The routines of other
; parts that this file calls are expected to return with D, DBR and the
; widths of their entry.
;
; Merged and split against the original:
; - The fireball, bubble, misc and block loops step D over the records; the
;   original keeps the slot in X and obj_slot.
; - whirlpool_pull and apply_whirlpool_pull are part of pull_in_whirlpools.
; - place_spring_top is part of run_jump_spring; draw_flag_and_number of
;   run_flag_object.
; - start_vine has a second entry, start_second_vine: the vine object that
;   take_queued_enemy starts, at the place that the original's jump
;   routine leaves (05a L3).
; - next_bullet_slot and check_cannon_bullet are part of run_cannons;
;   next_misc_object of run_misc_objects.
; - is_bumpable_block, bumpable_metatiles and the effect table are one table
;   by metatile (block_effects, made at build time); flip_block_slot_bit is
;   part of bump_block_from_below.
; - The cell of a block or of the vine in the collision buffers is written
;   by store_probe_cell (07, collision.s: the original's (t6),y with t2).
;
; Routines:
;   run_fireballs_and_bubbles  a throw, the two fireballs, the bubbles ($B624)
;   move_fireball           one fireball: start, flight, burst ($B689)
;   try_new_bubble          a bubble rises, or starts when the timer allows ($B6F9)
;   launch_bubble           a bubble at the player's mouth ($B70B)
;   move_bubble             a bubble rises to the top of the water ($B732)
;   tick_game_timer         the game timer: hurry, time up, one unit each 24 frames ($B74F)
;   warp_zone_exit_check    the warp zone object unlocks the scroll ($B7A4)
;   pull_in_whirlpools      a whirlpool pulls the player to its middle and down ($B7B8)
;   run_flag_object         the flagpole flag slides; the score at the bottom ($B855)
;   run_jump_spring         the jump spring squashes and throws the player ($B8BA)
;   finish_spring_frame     the spring's picture and its next step ($B902)
;   start_vine              a vine at a block's place ($B91E)
;   start_second_vine       the second vine object of take_queued_enemy ($B91E, L3)
;   run_vine                the vine grows and its column becomes climbable ($B94B)
;   run_cannons             the cannons fire bullet bills ($B9BC)
;   run_cannon_bullet       a cannon's bullet bill: aim, fly, hit, draw ($BA33)
;   throw_hammer            a hammer in the thrower's hand ($BA94)
;   run_hammer              a hammer: in the hand, thrown, flying ($BAC3)
;   hammer_collide_and_draw the hammer hits the player, then shows ($BB28)
;   finish_hammer_frame     the hammer's screen place, box and picture ($BB2B)
;   run_misc_objects        the coins from blocks and the hammers ($BB96)
;   find_free_misc_slot     a misc slot for a coin ($BB84)
;   pop_block_coin          a coin jumps out of a coin block ($BB38)
;   launch_jump_coin        a coin on top of a bumped block jumps out ($BB51)
;   set_coin_hop            the coin's jump, its sound, the coin count ($BB6C)
;   add_one_coin            one coin; 100 coins give a life; 200 points ($BBFE)
;   add_score               the digit amounts to the player's score ($BC27)
;   pick_status_nybbles     the status fields of the player's coins and score ($BC30)
;   refresh_status_number   print them; the score's first 0 blank ($BC36)
;   release_powerup         a power-up rises out of a block ($BC49)
;   set_powerup_start       the power-up's state, box, kind and sound ($BC60)
;   run_powerup             the power-up rises, moves, is taken ($BC85)
;   finish_powerup_frame    its screen place, box, picture, hits ($BCD8)
;   bump_block_from_below   the player's head hits a block ($BCED)
;   set_block_place         the bumped block's column from the player's ($BD84)
;   hit_block               the block bounces and gives what it holds ($BD9B)
;   block_gives_mushroom    the gifts: a mushroom or a flower, a star, a 1-up ($BDD2-$BDD8)
;   block_gives_vine        the gift: a vine ($BDDF)
;   break_brick             a big player breaks a brick ($BE02)
;   check_coin_above_block  a coin on top of a bumped block jumps out ($BE1F)
;   scatter_brick_chunks    the pieces of a broken brick start ($BE41)
;   run_block_objects       a bumped block or the brick pieces move ($BE70)
;   replace_bumped_metatile a bumped block's metatile goes back ($BED4)

.a8
.i8

; ---- Values of this file ---------------------------------------------------
; The fireballs (05a 4).
FIREBALL_FLYING = 1             ; Object::state of a fireball: it flies
                                ;   (0 none; bit 7: its burst, which draw_fireball_burst counts)
FIREBALL_HAND_X = 4             ; it starts 4 pixels right of the player's X
FIREBALL_DROP_SPEED = 4         ; its Y speed at the throw, down
FIREBALL_PULL   = $50
FIREBALL_TOP    = 3
FIREBALL_GONE   = (OFFSCREEN_ROW_1 | OFFSCREEN_ROW_2) | (OFFSCREEN_COLUMN_1 | OFFSCREEN_COLUMN_2) ; off the picture: the fireball ends
; The air bubbles (05a 5).
BUBBLE_RANDOM   = 1             ; random + 1 + u AND this: the bubble's table entry
BUBBLE_GONE     = $F8           ; Y of a bubble that waits for the timer
BUBBLE_TOP      = $20           ; a bubble that rises above this Y is gone
BUBBLE_MOUTH_LEFT = 0           ; it starts at the player's X when he faces left,
BUBBLE_MOUTH_RIGHT = 9          ; 9 pixels right of the player's X when he faces right
BUBBLE_MOUTH_Y  = 8             ;   and 8 pixels below his Y
; The whirlpools (05a 8).
WHIRLPOOL_ON    = 1             ; cannon_timer's first byte: the player is in a whirlpool
WHIRLPOOL_PULL  = $10
WHIRLPOOL_TOP   = 1
; The flagpole flag (05a 9).
FLAG_BOTTOM_Y   = $AA           ; the flag at the bottom of the pole: the score
PLAYER_POLE_BOTTOM = $A2        ; the player at the bottom of the pole: the score
FLAG_SLIDE      = $01FF         ; the flag sinks, its score number rises: 511/256 pixel each frame
; The jump spring (05a 10).
SPRING_MOVE     = 2             ; the player sinks or rises 2 pixels each frame
SPRING_RISING   = 2             ; bit of spring_anim - 1: the steps that lift the player
SPRING_FIRST_PRESS = 1          ; from this step on a press of A gives the high jump
SPRING_LAUNCH   = 3             ; the step that launches the player
SPRING_HIGH_FORCE = $F4         ; the launch speed with A pressed: 12 up
SPRING_STEP_FRAMES = 4          ; frames of each step
; The vine (05a 11).
VINE_SHOWN      = 8             ; the vine shows from this height on
VINE_CLIMB_HEIGHT = $20         ; its column becomes climbable from this height on
FRAME_BIT_1     = 2             ; frame_count bit 1: the vine grows 2 frames of each 4
; The cannons (05a 12).
CANNON_RELOAD   = $0E           ; picks between two shots of a cannon
BULLET_DROP     = 8             ; the bullet bill starts 8 pixels above the cannon's top
BULLET_FLYING   = 1             ; Object::state of a cannon bullet: fired (0: not yet)
BULLET_WAIT     = $0A           ; its frame timer at the shot
SHOT_GAP_ADD    = $28           ; no shot while (gap + $28 + the carry) AND $FF is below $50 (05a L10)
SHOT_GAP        = $50
; The hammers (05a 13).
HAMMER_SLOT_PICK = 7            ; random + 1 AND this: the misc slot of a hammer,
HAMMER_SLOT_LAST = 8            ;   or (when 0) random + 1 AND this
HAMMER_IN_HAND  = $90           ; misc state: bit 7 a hammer, $10 the frames in the hand
HAMMER_STEPS    = $7F           ; misc state AND this: the hammer's count
HAMMER_THROW    = 2             ; the count of the throw; above it the hammer is in the hand
HAMMER_THROW_SPEED = $FE        ; up 2 pixels each frame
THROW_POSE      = $08           ; the thrower's state bit 3: the throw pose
HAMMER_HAND_X   = 2             ; the hand: 2 pixels right of the thrower's X,
HAMMER_HAND_Y   = $0A           ;   10 above his Y
HAMMER_PULL     = $10
HAMMER_TOP      = 4
; The coins from blocks (05a 14, 15).
COIN_TURN_SPEED = 5             ; the coin's Y speed whole at which it turns into its number
COIN_PULL       = $50
COIN_TOP        = 6
COIN_POP_RISE   = $10           ; a coin block's coin starts this above the block, one more when
                                ;   misc slot 8 was free (05a L1)
COIN_X_INSET    = 5             ; the coin's X: 5 pixels into its column
COIN_ABOVE_DROP = $20           ; a coin above a block: its row offset + this, + 1 in buffer 2 (05a L2)
COIN_SPEED      = $FB           ; up 5 pixels each frame
; The power-ups (05a 16).
POWERUP_RISE_START = 8          ; it starts 8 pixels above the block's Y
POWERUP_RISING  = 1             ; Object::state: it rises (1-$11), shows from POWERUP_SHOWN,
POWERUP_SHOWN   = 6
POWERUP_RISE_END = $11          ;   moves after this one
POWERUP_MOVING  = $80           ;   it moves
POWERUP_RISE_FRAMES = 3         ; frame_count AND this = 0: one step of the rise
POWERUP_SPEED   = $10           ; +1 pixel each frame
; The blocks (05a 17).
BLOCK_STATE_LOW = $0F           ;   the first run keeps this part:
BLOCK_BUMPED    = 1             ;   1 a bumped block, 2 brick pieces, 0 free
BLOCK_PIECES    = 2
BLOCK_LOWER     = 2             ; the lower piece of block b is block object b + 2 (state.inc)
BLOCK_IN_ROW    = 5             ; a bumped block with (Y AND $0F) below this is back in its row
ROW_PIXELS      = $0F           ; Y AND this: the pixel in the row
BRICK_X_SPEED   = $F0           ; the brick pieces: 1 pixel left each frame
BRICK_UPPER_SPEED = $FA00       ;   the upper pieces: up 6, fraction 0
BRICK_LOWER_SPEED = $FC00       ;   the lower pieces: up 4
BRICK_LOWER_DROP = 8            ;   the lower pieces start 8 pixels lower
PIECES_BOTTOM   = $F0           ; the pieces end at this Y

.segment "AREASTATE"
whirlpool_left: .res 2          ; pull_in_whirlpools: the whirlpool's left edge, world X
.segment "GAMEPLAY"

; ---------------------------------------------------------------------------
; run_fireballs_and_bubbles: a fiery player throws a fireball when B goes
; down; then the two fireballs run, and in water areas the three air
; bubbles (05a 4.1). Below fire power the throw and the two fireballs are
; skipped: a fireball in flight stops and does not show, and goes on from
; its place when the player is fiery again (05a L27). The throw needs the
; fireball that fireball_count picks to be free (the other one does not
; count), the player on the picture, not crouching, not climbing.
;
; In:       any D
; Out:      D as it was; the fireballs, the bubbles, throw_timer,
;           the player's animation timer, fireball_count
; Changes:  A, X, Y
; Time:     each frame of play
; Original: $B624-$B686
; ---------------------------------------------------------------------------
run_fireballs_and_bubbles:
.a8
.i8
        phd
        lda player_power
        cmp #POWER_FIRE
        bcc @bubbles
        jsr throw_fireball              ; 04 (player.s): a press of B throws
        pea fireball_objects
        pld
        jsr move_fireball
        pea fireball_objects + OBJECT_PAGE
        pld
        jsr move_fireball
; The bubbles, whatever the player's power is: bubble 2, 1, then 0.
@bubbles:
        lda area_type
        cmp #AREA_WATER
        bne @done
        pea bubble_objects + (BUBBLE_SLOTS - 1) * OBJECT_PAGE
        pld
@bubble:
        jsr try_new_bubble
        jsr bubble_screen_position      ; 11
        jsr check_bubble_offscreen      ; 11
        jsr draw_air_bubble             ; 11
        a16
        tdc
        sec
        sbc #OBJECT_PAGE
        tcd
        cmp #bubble_objects
        a8
        bcs @bubble
@done:
        pld
        rts

; ---------------------------------------------------------------------------
; move_fireball: one fireball (05a 4.3).
;
; state           meaning            each frame                     next
; 0               none               nothing                        2 at a throw
; FIREBALL_THROWN thrown this frame  the start, then the flight     1
; FIREBALL_FLYING it flies           the flight                     0 off the picture;
;                                                                   $80 at a hit or a burst (07)
; $80-$85         the burst          draw_fireball_burst adds 1      0 at $86 (11)
;
; The start: 4 pixels right of the player's X (page with the carry), at his
; Y with Y high 1 (his own: the throw needs it), 4 pixels a frame down, the
; X speed of his facing (facing 3, both directions held, reads the byte
; after the table, 04 L10), the fireball's box. The fractions and the bounce
; flag keep what the slot's last flight left (05a L13). The flight: the
; fall (pull $50, top 3: the start speed 4 is above the top, the limit
; takes it to 3 when the fraction reaches 1/2), the move, the screen place,
; the box, the tiles (07: the bounce or the burst); off the picture the
; fireball ends, else it hits the enemies and shows.
;
; In:       D = the fireball's record
; Changes:  A, X, Y
; Original: $B689-$B6F8
; ---------------------------------------------------------------------------
move_fireball:
.a8
.i8
        lda Object::state
        bmi @burst
        beq @done
        cmp #FIREBALL_THROWN
        bne @flight
        a16
        lda player_object + Object::x_pos
        clc
        adc #FIREBALL_HAND_X
        sta Object::x_pos
        lda player_object + Object::y_pos
        sta Object::y_pos
        a8
        ldy player_facing
        lda fireball_x_speeds - 1,y
        sta Object::x_speed
        lda #FIREBALL_DROP_SPEED
        sta Object::y_speed_whole
        lda #BOX_FIREBALL
        sta Object::box
        lda #FIREBALL_FLYING
        sta Object::state
@flight:
        lda #FIREBALL_PULL
        ldy #FIREBALL_TOP
        jsr apply_gravity
        jsr move_object_sideways
        jsr fireball_screen_position    ; 11
        jsr check_fireball_offscreen    ; 11
        jsr fireball_hit_box            ; 07
        jsr fireball_vs_tiles           ; 07: it bounces, or it bursts
        lda offscreen_bits + REL_FIREBALL
        and #FIREBALL_GONE
        bne @gone                       ; also a burst that fireball_vs_tiles started
        jsr fireballs_vs_enemies        ; 07
        jmp draw_player_fireball        ; 11
@gone:
        stz Object::state
@done:
        rts
@burst:
        jsr fireball_screen_position
        jmp draw_fireball_burst         ; 11: it counts the burst and ends it

; ---------------------------------------------------------------------------
; try_new_bubble: a bubble rises; a bubble that waits at Y $F8 starts again
; at the player's mouth when the bubbles' shared wait (timers +
; TIMER_AIR_BUBBLE, a frame timer) is over (05a 5.1). Each bubble's table
; entry is its random bit, random + 1 + u AND 1.
; launch_bubble: the bubble at the player's mouth: 9 pixels right of his X
; when he faces right (8 and the carry of the facing bit), else at his X,
; 8 pixels below his Y; the next wait; then its first rise (05a 5.2). The Y
; fraction keeps the bubble's earlier value. The area start (04
; setup_entry_and_timer) calls it for bubble 0 with the entry
; BUBBLE_ENTRANCE: the bytes that the original reads at index $91 (the
; jump routine's leftover): a wait of 4 frames and a first rise of $F9
; (05a L4).
; move_bubble: the bubble rises by its entry's force (1/256 pixel each
; frame); above Y $20 it is gone and waits at Y $F8 (05a 5.3). Its Y high
; does not change. One 16-bit subtract from the Y fraction and the pixel
; gives the original's borrow.
;
; In:       D = the bubble's record; launch_bubble, move_bubble: A = the
;           entry (0 or 1 a random bit, BUBBLE_ENTRANCE)
; Out:      the bubble's place; the wait
; Changes:  A, X, Y
; Time:     each frame for each bubble in a water area, about 60 cycles
; Original: $B6F9-$B70A (try_new_bubble), $B70B-$B731 (launch_bubble),
;           $B732-$B74A (move_bubble)
; ---------------------------------------------------------------------------
try_new_bubble:
.a8
.i8
        ldx Object::slot
        lda random + 1 - SLOT_BUBBLE,x
        and #BUBBLE_RANDOM
        ldx Object::y_pos
        cpx #BUBBLE_GONE
        bne move_bubble
        ldx timers + TIMER_AIR_BUBBLE
        beq launch_bubble
        rts                             ; it waits for the timer
launch_bubble:
.a8
.i8
        tay                             ; Y = the entry
        ldx #BUBBLE_MOUTH_LEFT
        lda player_facing
        and #FACING_RIGHT
        beq @mouth
        ldx #BUBBLE_MOUTH_RIGHT
@mouth:
        txa
        a16
        and #$00FF
        clc
        adc player_object + Object::x_pos
        sta Object::x_pos
        a8
        lda player_object + Object::y_pos
        clc
        adc #BUBBLE_MOUTH_Y
        sta Object::y_pos
        lda #Y_HIGH_SCREEN
        sta Object::y_pos+1
        lda bubble_gap_frames,y
        sta timers + TIMER_AIR_BUBBLE
        tya
move_bubble:
.a8
.i8
        asl a
        tay                             ; the entry's force word
        a16
        lda Object::y_fraction          ; the fraction and the pixel
        sec
        sbc bubble_rise_force,y
        cmp #BUBBLE_TOP << 8
        bcs @store
        and #$00FF                      ; above the top: gone, at Y $F8
        ora #BUBBLE_GONE << 8
@store:
        sta Object::y_fraction
        a8
        rts

; ---------------------------------------------------------------------------
; warp_zone_exit_check: the warp zone object, kind $34 (05a 7.1). While the
; scroll is locked and the player's Y AND his Y high is 0, the scroll
; unlocks, warp_zone counts one up, and the object ends. The test is a bit
; AND (05a L24): true above the picture, and also on it at any even Y.
;
; In:       D = the warp zone object's record
; Changes:  A, and what clear_enemy_slot changes
; Original: $B7A4-$B7B7
; ---------------------------------------------------------------------------
warp_zone_exit_check:
.a8
.i8
        lda scroll_lock
        beq @done
        lda player_object + Object::y_pos
        and player_object + Object::y_pos+1
        bne @done
        stz scroll_lock
        inc warp_zone
        jmp clear_enemy_slot            ; 05b
@done:
        rts

; ---------------------------------------------------------------------------
; pull_in_whirlpools: a whirlpool pulls the player (05a 8.1). In water areas
; the cannon records hold up to 5 whirlpools (cannon_page: its page, 0 for
; none; cannon_x: its left edge; cannon_y: its width; 06 build_pit). The
; highest whirlpool that holds the player's X acts: on odd frames he moves
; one pixel toward its middle (left of the middle or at it: right, only
; while his right side is free; right of it: left), and he sinks: a second
; apply_gravity in the frame (05a L28: his Y moves by his speed twice, his
; fall is limited to 1). The whirlpool flag (cannon_timer's first byte)
; tells set_player_forces (04) in the next frame that he is in one.
;
; The edges are world X words: the record's page and X joined by XBA; each
; test is the sign of a 16-bit difference, as the original's page byte's
; bit 7.
;
; In:       any D
; Out:      D as it was; the player's X, Y and Y speed; cannon_timer's first
;           byte
; Changes:  A, X, Y, whirlpool_left
; Time:     each frame in a water area: about 60 cycles a whirlpool
; Original: $B7B8-$B84A (with whirlpool_pull $B839 and apply_whirlpool_pull
;           $B83B)
; ---------------------------------------------------------------------------
pull_in_whirlpools:
.a8
.i8
        lda area_type
        cmp #AREA_WATER
        bne @done
        stz cannon_timer                ; the whirlpool flag
        lda timer_hold
        bne @done
        ldx #WHIRLPOOLS - 1
@whirlpool:
        lda cannon_page,x
        beq @next
        xba
        lda cannon_x,x
        a16                             ; the left edge, page and X
        sta whirlpool_left
        lda player_object + Object::x_pos
        sec
        sbc whirlpool_left
        bmi @outside                    ; the player is left of it
        lda cannon_y,x                  ; the width
        and #$00FF
        clc
        adc whirlpool_left
        sec
        sbc player_object + Object::x_pos
        bpl @inside                     ; the right edge is not left of the player
@outside:
        a8
@next:
        dex
        bpl @whirlpool
@done:
        rts
; The pull of whirlpool X: on odd frames toward its middle = the left edge +
; width / 2 (the shift drops the width's low bit).
.a16
@inside:
        a8
        lda frame_count
        lsr a
        bcc @pull                       ; even frames: no side move
        a16
        lda cannon_y,x
        and #$00FF
        lsr a
        clc
        adc whirlpool_left              ; the middle
        sec
        sbc player_object + Object::x_pos
        bmi @left                       ; the player is right of the middle
        a8
        lda player_object + Object::collision
        and #SIDE_RIGHT_FREE
        beq @pull
        a16
        inc player_object + Object::x_pos
        bra @moved
@left:
        dec player_object + Object::x_pos
@moved:
        a8
@pull:
        lda #WHIRLPOOL_ON
        sta cannon_timer
        phd
        pea player_object
        pld
        lda #WHIRLPOOL_PULL
        ldy #WHIRLPOOL_TOP
        jsr apply_gravity
        pld
        rts

; ---------------------------------------------------------------------------
; run_flag_object: the flagpole flag, kind $30 in enemy slot 5 (05a 9.1;
; kind $30 has no routine in the enemy loop). While the player slides down
; the pole the flag sinks and its score number rises, 511/256 pixel a frame
; (the flag's add starts with a clear carry, 05a L23); when the flag or the
; player reaches the bottom, the score of the height where he took the pole
; (flag_score, 07) and the walk to the castle. The flag shows each frame
; (draw_flag_and_number).
;
; In:       any D
; Out:      D as it was; the flag's Y, flag_score_y, the score, player_task
; Changes:  A, X, Y
; Time:     each frame of play
; Original: $B855-$B8AB, draw_flag_and_number $B8AC-$B8B5
; ---------------------------------------------------------------------------
run_flag_object:
.a8
.i8
        phd
        pea special_object
        pld
        lda Object::kind
        cmp #KIND_FLAG
        bne @done
        lda player_task
        cmp #PLAYER_TASK_FLAGPOLE
        bne @draw
        lda player_object + Object::state
        cmp #PLAYER_CLIMBING
        bne @draw
        lda Object::y_pos
        cmp #FLAG_BOTTOM_Y
        bcs @score
        lda player_object + Object::y_pos
        cmp #PLAYER_POLE_BOTTOM
        bcs @score
        a16
        lda Object::y_fraction          ; the flag's fraction and Y (Y high stays)
        clc
        adc #FLAG_SLIDE
        sta Object::y_fraction
        lda flag_score_y                ; the number's fraction and Y
        sec
        sbc #FLAG_SLIDE
        sta flag_score_y
        a8
        bra @draw
@score:
        ldy flag_score
        lda flag_score_amounts,y
        ldx flag_score_places,y
        sta digit_add,x
        jsr add_score
        lda #PLAYER_TASK_END_LEVEL
        sta player_task
@draw:
        jsr check_enemy_offscreen       ; 11
        jsr enemy_screen_position       ; 11
        jsr draw_flag_sprites           ; 11
@done:
        pld
        rts

; ---------------------------------------------------------------------------
; run_jump_spring: the jump spring, kind $32 (05a 10). land_on_spring (07)
; starts a jump: spring_anim 1, spring_force $F9 (7 up), the spring timer 3.
;
; spring_anim  the player each frame        the spring's top   a press of A
; 0            -                            as it was          -
; 1            Y + 2                        rest + entry 0     no effect
; 2            Y + 2                        rest + entry 1     force $F4
; 3            Y - 2                        rest + entry 2     force $F4
; 4            Y - 2, then the launch:      rest + entry 3     force $F4 (before
;              Y speed = spring_force,                         the launch)
;              spring_anim 0
; Each step lasts 4 frames (the first one the landing frame and 3 more), the
; last one 1 frame. The spring's rest Y is in its X speed byte
; (Object::spring_rest_y, 06 place_jump_spring). During the freeze nothing
; moves. finish_spring_frame: the picture, the bounds, the next step.
;
; In:       D = the spring's record
; Changes:  A, Y, and what the routines of 07 and 11 change
; Original: $B8BA-$B8D8, place_spring_top $B8D9-$B901,
;           finish_spring_frame $B902-$B91D
; ---------------------------------------------------------------------------
run_jump_spring:
.a8
.i8
        jsr check_enemy_offscreen       ; 11
        lda timer_hold
        bne finish_spring_frame
        lda spring_anim
        beq finish_spring_frame
        dec a
        tay                             ; the step, 0-3
        and #SPRING_RISING
        bne @rise
        lda player_object + Object::y_pos
        clc
        adc #SPRING_MOVE
        bra @player
@rise:
        lda player_object + Object::y_pos
        sec
        sbc #SPRING_MOVE
@player:
        sta player_object + Object::y_pos
        lda Object::spring_rest_y
        clc
        adc spring_top_offsets,y
        sta Object::y_pos
        cpy #SPRING_FIRST_PRESS
        bcc @launch
        lda pad_ab
        and #PAD_A
        beq @launch
        and pad_ab_last
        bne @launch                     ; held from the frame before: no press
        lda #SPRING_HIGH_FORCE
        sta spring_force
@launch:
        cpy #SPRING_LAUNCH
        bne finish_spring_frame
        lda spring_force
        sta player_object + Object::y_speed_whole
        stz spring_anim
finish_spring_frame:
.a8
.i8
        jsr enemy_screen_position       ; 11
        jsr draw_enemy                  ; 11
        jsr check_enemy_in_bounds       ; 07
        lda spring_anim
        beq @done
        lda timers + TIMER_SPRING
        bne @done
        lda #SPRING_STEP_FRAMES
        sta timers + TIMER_SPRING
        inc spring_anim
@done:
        rts

; ---------------------------------------------------------------------------
; start_vine: a vine object at a block's place: block b's page and X, its Y
; (not its Y high) (05a 11.1). The first vine object gives vine_start_y;
; vine_slots holds each vine object's enemy number; the vine sound. Only the
; vine in enemy slot 5 grows and shows; a second vine object makes it
; taller.
; start_second_vine: the start of kind $2F in enemy_starts (movement.s): the
; vine object that take_queued_enemy starts while one vine grows. The
; original's jump routine leaves Y = 2 x $2F + 2 = $60, so this vine takes
; its page from the second fireball's Y, its X from draw_enemy's drawing
; code byte (enemy_draw_code, 11) and its Y from digit_add place 3 (05a L3).
; Nothing reads these values: the vine's growth and its drawing use slot 5,
; and the collisions use boxes (07 L9; enemies_bump_enemies passes over the
; kinds from $15 on).
;
; In:       D = the vine object's record (start_vine: enemy slot 5; 04
;           setup_entry_and_timer at a vine entrance after set_block_place
;           for block 0, and block_gives_vine); start_vine: X = the block
;           slot b (0 or 1)
; Out:      the vine object; vine_count, vine_slots, vine_start_y; the vine
;           sound
; Changes:  A, X
; Original: $B91E-$B948
; ---------------------------------------------------------------------------
L3_DIGIT_PLACE  = 3             ; digit_add place 3: the second vine's Y (05a L3)
start_vine:
.a8
.i8
        txa
        xba
        lda #0
        x16
        tax                             ; X16 = block b's record
        a16
        lda block_objects + Object::x_pos,x
        sta Object::x_pos
        a8
        lda block_objects + Object::y_pos,x
        sep #P_X8
        bra vine_at
start_second_vine:
.a8
.i8
        lda fireball_objects + OBJECT_PAGE + Object::y_pos
        sta Object::x_pos+1
        lda enemy_draw_code
        sta Object::x_pos
        lda digit_add + L3_DIGIT_PLACE
vine_at:
.a8
.i8
        sta Object::y_pos
        ldx vine_count
        bne @slot
        sta vine_start_y
@slot:
        lda Object::slot
        sec
        sbc #SLOT_ENEMY
        sta vine_slots,x
        inc vine_count
        lda #KIND_VINE
        sta Object::kind
        lda #ENEMY_ACTIVE
        sta Object::active
        lda #SQUARE2_GROW_VINE
        sta snd_square2_queue
        rts

; ---------------------------------------------------------------------------
; run_vine: the vine, kind $2F (05a 11.2). Only the vine in enemy slot 5
; acts. It grows 1 pixel on 2 frames of each 4, to the height of its count
; (vine_height_limits: $30 for one vine object, $60 for two; a third entry
; for vine_count 3, the byte after the table, 05a L11). From 8 pixels on it
; shows (draw_vine_stack, one part for each vine object). When its column
; is off the picture every vine object ends. From 32 pixels on, the cell
; under the probe point of the vine (4 right, 16 down) becomes the climbable
; vine metatile when it is empty and inside the 13 rows.
;
; In:       D = the vine object's record
; Changes:  A, X, Y, and what the routines of 05b, 07 and 11 change
; Time:     each frame of a vine
; Original: $B94B-$B9B9
; ---------------------------------------------------------------------------
run_vine:
.a8
.i8
        lda Object::slot
        cmp #SLOT_SPECIAL
        bne @done
        ldy vine_count
        lda vine_height
        cmp vine_height_limits - 1,y
        beq @grown
        lda frame_count
        and #FRAME_BIT_1
        beq @grown
        dec Object::y_pos               ; the top 1 pixel higher (Y high stays)
        inc vine_height
@grown:
        lda vine_height
        cmp #VINE_SHOWN
        bcc @done
        jsr enemy_screen_position       ; 11
        jsr check_enemy_offscreen       ; 11
        ldy #0
@part:
        jsr draw_vine_stack             ; 11: part Y (kept)
        iny
        cpy vine_count
        bne @part
        lda offscreen_bits + REL_ENEMY
        and #(OFFSCREEN_COLUMN_1 | OFFSCREEN_COLUMN_2)
        beq @climb
; The column left the picture: each vine object ends, the last one first.
        phd
        ldy vine_count
@erase:
        dey
        bmi @erased
        phy
        lda vine_slots,y
        clc
        adc #SLOT_ENEMY
        tax
        object_from_x
        jsr clear_enemy_slot            ; 05b
        ply
        bra @erase
@erased:
        pld
        stz vine_count
        stz vine_height
        rts
@climb:
        lda vine_height
        cmp #VINE_CLIMB_HEIGHT
        bcc @done
        ldy #POINT_VINE
        jsr probe_tile                  ; 07: A = the metatile; probe_row, probe_column
        ldx probe_row
        cpx #COLLISION_BUFFER           ; a row offset from 13 x 16 on: outside the buffer
        bcs @done                       ; above or below the 13 rows
        cmp #METATILE_EMPTY
        bne @done
        lda #METATILE_VINE
        jmp store_probe_cell            ; 07
@done:
        rts

; ---------------------------------------------------------------------------
; run_cannons: the cannons fire bullet bills, in areas that are not water
; areas (05a 12.2). For enemy slots 2, 1, 0: a free slot picks a cannon by
; its random bits (random + 1 + e AND cannon_rate_masks[hard_mode_2]: the
; smaller mask of hard_mode_2 picks the cannons more often); a picked
; cannon counts down (its timer: picks to its next shot), and at 0 fires
; when the freeze is off: the bullet bill starts 8 pixels above the
; cannon's top, kind $33, and first moves in the next frame. A slot that
; holds a cannon bullet (kind $33 has no routine in the enemy loop) runs it
; here while it is in bounds.
;
; In:       any D
; Out:      D as it was; the cannon records; the bullets
; Changes:  A, X, Y
; Time:     each frame of play outside water areas
; Original: $B9BC-$BA19, check_cannon_bullet $BA1A-$BA2C,
;           next_bullet_slot $BA2D-$BA30
; ---------------------------------------------------------------------------
CANNON_SLOTS    = 3             ; the cannons fire into enemy slots 0-2
run_cannons:
.a8
.i8
        lda area_type
        cmp #AREA_WATER
        beq @done
        phd
        pea enemy_objects + (CANNON_SLOTS - 1) * OBJECT_PAGE
        pld
@slot:
        lda Object::active
        bne @bullet
        ldx Object::slot
        lda random + 1 - SLOT_ENEMY,x
        ldy hard_mode_2
        and cannon_rate_masks,y
        cmp #CANNONS
        bcs @bullet
        tax                             ; X = the cannon
        lda cannon_page,x
        beq @bullet
        lda cannon_timer,x
        beq @ready
        dec cannon_timer,x              ; the original's subtract with the clear carry (05a L23)
        bra @bullet
@ready:
        lda timer_hold
        bne @bullet
        lda #CANNON_RELOAD
        sta cannon_timer,x
        lda cannon_page,x
        xba
        lda cannon_x,x
        a16
        sta Object::x_pos
        a8
        lda cannon_y,x
        sec
        sbc #BULLET_DROP
        sta Object::y_pos
        lda #Y_HIGH_SCREEN
        sta Object::y_pos+1
        lda #ENEMY_ACTIVE
        sta Object::active
        stz Object::state
        lda #BOX_SMALL_ENEMY
        sta Object::box
        lda #KIND_BULLET_CANNON
        sta Object::kind
        bra @next                       ; it flies from the next frame on
@bullet:
        lda Object::kind
        cmp #KIND_BULLET_CANNON
        bne @next
        jsr check_enemy_in_bounds       ; 07: it may end the bullet
        lda Object::active
        beq @next
        jsr check_enemy_offscreen       ; 11
        jsr run_cannon_bullet
@next:
        a16
        tdc
        sec
        sbc #OBJECT_PAGE
        tcd
        cmp #enemy_objects
        a8
        bcs @slot
        pld
@done:
        rts

; ---------------------------------------------------------------------------
; run_cannon_bullet: a cannon's bullet bill (05a 12.3). In its first frame
; (state 0) it aims: it flies toward the player at 1.5 pixels a frame, with
; the blast sound, unless the player is too close: the low byte of the gap
; bullet - player, plus $28 and the carry of the gap's page subtract, below
; $50 (05a L10: 0-38 pixels left of the bullet or 1-40 right, and by the
; low byte's wrap also 217-255 right of it); then it ends. Off the picture
; on both columns before the aim, it ends. A defeated bullet falls. Each
; frame: the move, the screen place, the box, the player's hit, the picture.
; During the freeze it only shows.
;
; The gap is one 16-bit subtract: its carry is the original's carry of the
; page subtract, its bit 15 the page byte's sign (the side).
;
; In:       D = the bullet's record
; Changes:  A, X, Y, and what the routines of 05b, 07 and 11 change
; Original: $BA33-$BA88
; ---------------------------------------------------------------------------
run_cannon_bullet:
.a8
.i8
        lda timer_hold
        bne @draw
        lda Object::state
        bne @flies
        lda offscreen_bits + REL_ENEMY
        and #(OFFSCREEN_COLUMN_1 | OFFSCREEN_COLUMN_2)
        cmp #(OFFSCREEN_COLUMN_1 | OFFSCREEN_COLUMN_2)
        beq @end
        a16
        lda Object::x_pos
        sec
        sbc player_object + Object::x_pos ; the gap; the carry: no borrow
        a8
        adc #SHOT_GAP_ADD               ; the shot's test value (05a L10)
        xba                             ; A = the gap's page byte, B = the test value
        bmi @right                      ; the bullet is left of the player: it flies right
        ldy #FACING_LEFT
        bra @aim
@right:
        ldy #FACING_RIGHT
@aim:
        sty Object::direction
        lda bullet_x_speeds - FACING_RIGHT,y
        sta Object::x_speed
        xba
        cmp #SHOT_GAP
        bcc @end                        ; the player is too close: no shot
        lda #BULLET_FLYING
        sta Object::state
        lda #BULLET_WAIT
        ldx Object::slot
        sta timers + TIMER_ENEMY_FRAME - SLOT_ENEMY,x
        lda #SQUARE2_BLAST
        sta snd_square2_queue
@flies:
        lda Object::state
        and #ENEMY_DEFEATED
        beq @move
        jsr drop_enemy_fast
@move:
        jsr move_enemy_sideways
@draw:
        jsr check_enemy_offscreen       ; 11
        jsr enemy_screen_position       ; 11
        jsr enemy_hit_box               ; 07
        jsr player_hits_enemy           ; 07
        jmp draw_enemy                  ; 11
@end:
        jmp clear_enemy_slot            ; 05b

; ---------------------------------------------------------------------------
; throw_hammer: a hammer brother or Bowser (05b) starts a hammer in its hand
; (05a 13.1). The misc slot m = random + 1 AND 7, or AND 8 when that is 0;
; the hammer needs m free and the enemy slot hammer_source_slots[m] free
; (slots 4, 5 and "6" for the three groups of misc slots; "6" is the seventh
; active byte, the first fireball record's, which only copy_enemy_to_free_slot
; writes: 05a L15, L8). Then the hammer's owner, its state (bit 7 a hammer,
; $10 frames in the hand) and the fireball box; run_hammer places it in the
; same frame.
;
; In:       D = the thrower's record
; Out:      the carry set: a hammer started; clear: none
; Changes:  A, X, Y
; Original: $BA94-$BAC2
; ---------------------------------------------------------------------------
throw_hammer:
.a8
.i8
        lda random + 1
        and #HAMMER_SLOT_PICK
        bne @slot
        lda random + 1
        and #HAMMER_SLOT_LAST
@slot:
        tay                             ; Y = m
        xba
        lda #0
        x16
        tax                             ; X16 = misc slot m's record
        lda misc_objects + Object::state,x
        bne @none
        lda hammer_source_slots,y       ; the enemy number that must be free
        phx
        xba
        lda #0
        tax
        lda enemy_objects + Object::active,x
        plx                             ; (PLX sets the flags: test below)
        cmp #0
        bne @none
        lda Object::slot
        sec
        sbc #SLOT_ENEMY
        sta misc_objects + Object::hammer_owner,x
        lda #HAMMER_IN_HAND
        sta misc_objects + Object::state,x
        lda #BOX_FIREBALL
        sta misc_objects + Object::box,x
        sep #P_X8
        sec
        rts
@none:
        sep #P_X8
        clc
        rts

; ---------------------------------------------------------------------------
; run_hammer: a hammer (05a 13.2). Its count s = state AND $7F.
;
; s           work                                                    next
; 3 and up    in the thrower's hand: s - 1; 2 pixels right of his X   s - 1
;             (page with the carry), 10 above his Y, Y high 1; no hit
; 2           the throw: 2 up; the thrower's throw pose ends; the X   1
;             speed of his direction; then in the hand once more
; 1 (or 0)    it flies: the fall (pull $10, top 4), the move, the      stays
;             player's hit
; A hammer starts at s = $10: 14 frames in the hand, the throw in the
; 15th, it leaves the hand in the 16th. The Y speed fraction is not set at
; the throw (05a L13). During the freeze it only shows. It ends when
; draw_spinning_hammer finds it off the picture (11).
;
; In:       D = the hammer's misc record
; Changes:  A, X, Y, and what the routines of 07 and 11 change
; Original: $BAC3-$BB27
; ---------------------------------------------------------------------------
run_hammer:
.a8
.i8
        lda timer_hold
        bne finish_hammer_frame
        lda Object::hammer_owner
        xba
        lda #0
        x16
        tax                             ; X16 = the thrower's record
        lda Object::state
        and #HAMMER_STEPS
        cmp #HAMMER_THROW
        beq @throw
        bcs @hand
        sep #P_X8
        lda #HAMMER_PULL
        ldy #HAMMER_TOP
        jsr apply_gravity
        jsr move_object_sideways
        bra hammer_collide_and_draw
.a8
.i16
@throw:
        lda #HAMMER_THROW_SPEED
        sta Object::y_speed_whole
        lda enemy_objects + Object::state,x
        and #<~THROW_POSE
        sta enemy_objects + Object::state,x
        lda enemy_objects + Object::direction,x
        a16
        and #$00FF
        tay                             ; Y16 = the thrower's direction
        a8
        lda hammer_x_speeds - FACING_RIGHT,y
        sta Object::x_speed
@hand:
        dec Object::state               ; the count (bit 7 stays)
        a16
        lda enemy_objects + Object::x_pos,x
        clc
        adc #HAMMER_HAND_X
        sta Object::x_pos
        a8
        lda enemy_objects + Object::y_pos,x
        sec
        sbc #HAMMER_HAND_Y
        sta Object::y_pos
        lda #Y_HIGH_SCREEN
        sta Object::y_pos+1
        sep #P_X8
        bra finish_hammer_frame

; ---------------------------------------------------------------------------
; hammer_collide_and_draw: the hammer hits the player (07), then
; finish_hammer_frame: its offscreen bits, screen place, box and picture
; (05a 13.3).
;
; In:       D = the hammer's misc record
; Changes:  what the routines of 07 and 11 change
; Original: $BB28-$BB2A, $BB2B-$BB37
; ---------------------------------------------------------------------------
hammer_collide_and_draw:
.a8
.i8
        jsr hammer_hits_player          ; 07
finish_hammer_frame:
.a8
.i8
        jsr check_misc_offscreen        ; 11
        jsr misc_screen_position        ; 11
        jsr misc_hit_box                ; 07
        jmp draw_spinning_hammer        ; 11

; ---------------------------------------------------------------------------
; run_misc_objects: the misc objects, slots 8 down to 0 (05a 14.1, 14.2).
;
; state      meaning                     each frame                       next
; 0          free                        nothing                          1 or $90
; 1          a coin jumps out of a block the fall (pull $50, top 6); at   2
;                                        a Y speed whole of exactly 5 it
;                                        turns into its number; shows
; 2-$2F      the coin's score number     state + 1; X + the scroll (it    0 at $30
;                                        keeps its place on the picture);
;                                        at $30 free, else shows
; bit 7 set  a hammer                    run_hammer                       (13.2)
; A coin turns into its number 29 to 32 frames after its start (the Y speed
; fraction that the slot holds from its earlier object, 05a L13); the
; number shows 46 frames.
;
; In:       any D
; Out:      D as it was; the misc objects
; Changes:  A, X, Y
; Time:     each frame of play
; Original: $BB96-$BBF3, next_misc_object $BBF4-$BBF7
; ---------------------------------------------------------------------------
run_misc_objects:
.a8
.i8
        phd
        pea misc_objects + (MISC_SLOTS - 1) * OBJECT_PAGE
        pld
@object:
        lda Object::state
        beq @next
        bmi @hammer
        cmp #MISC_COIN
        bne @number
        lda #COIN_PULL
        ldy #COIN_TOP
        jsr apply_gravity
        lda Object::y_speed_whole
        cmp #COIN_TURN_SPEED
        bne @coin
        inc Object::state               ; it turns into its number
@coin:
        jsr misc_screen_position        ; 11
        jsr check_misc_offscreen        ; 11
        jsr misc_hit_box                ; 07
        jsr draw_spinning_coin          ; 11
        bra @next
@number:
        inc Object::state
        lda scroll_amount
        a16
        and #$00FF
        clc
        adc Object::x_pos
        sta Object::x_pos
        a8
        lda Object::state
        cmp #MISC_COIN_GONE
        bne @coin
        stz Object::state
        bra @next
@hammer:
        jsr run_hammer
@next:
        a16
        tdc
        sec
        sbc #OBJECT_PAGE
        tcd
        cmp #misc_objects
        a8
        bcs @object
        pld
        rts

; ---------------------------------------------------------------------------
; find_free_misc_slot: the misc slot of a coin from a block: the first free
; one of misc slots 8, 7, 6, else slot 8 (the coin replaces its object)
; (05a 14.3). The carry tells pop_block_coin whether slot 8 was free (05a
; L1). jump_coin_slot keeps the misc number found: no routine reads it by
; name, but the tile probes of 07 read it as one of the bytes past the
; second collision buffer (collision.s past_buffer_bytes).
;
; Out:      X16 = the misc record's offset from misc_objects; the carry
;           clear when misc slot 8 was free, else set; jump_coin_slot = the
;           misc number; I16
; Changes:  A, X, the flags
; Original: $BB84-$BB95
; ---------------------------------------------------------------------------
COIN_SLOT       = MISC_SLOTS - 1 ; the first misc slot that a coin tries; then the two below it
find_free_misc_slot:
.a8
.i8
        x16
        clc
        ldx #COIN_SLOT * OBJECT_PAGE
        lda misc_objects + Object::state,x
        beq @found
        sec
        ldx #(COIN_SLOT - 1) * OBJECT_PAGE
        lda misc_objects + Object::state,x
        beq @found
        ldx #(COIN_SLOT - 2) * OBJECT_PAGE
        lda misc_objects + Object::state,x
        beq @found
        ldx #COIN_SLOT * OBJECT_PAGE
@found:
        rep #P_M8
.a16
        txa
        xba                             ; A = the misc number (the record's page)
        sep #P_M8
.a8
        sta jump_coin_slot
        rts

; ---------------------------------------------------------------------------
; pop_block_coin: a coin block's gift: a coin jumps out of the block (05a
; 14.4): on the block's page, 5 pixels into its column, 17 pixels above it
; when misc slot 8 was free, 16 when it was not (05a L1).
; launch_jump_coin: a coin that sat on the cell above a bumped block jumps
; out (05a 14.5): its page = the block's, its X = the column x 16 + 5, its
; Y = the cell's row offset + $20, + 1 in the second collision buffer (the
; bit that the 4 shifts of the column move out: 05a L2).
; set_coin_hop: the coin's start, 5 up, its sound, one coin to the count
; (05a 14.6). The original also sets obj_slot to the block slot (05a L19:
; no reader in the port).
;
; In:       D = block b's record; launch_jump_coin: probe_row, probe_column =
;           the coin's cell (check_coin_above_block)
; Out:      the coin's misc record; the coin count, the score, coins_for_1up
; Changes:  A, X, Y, and what add_one_coin changes
; Original: $BB38-$BB50, $BB51-$BB6B, $BB6C-$BB83
; ---------------------------------------------------------------------------
pop_block_coin:
.a8
.i8
        jsr find_free_misc_slot
.i16
        lda Object::y_pos
        sbc #COIN_POP_RISE              ; with the carry: 17 or 16 above the block (05a L1)
        sta misc_objects + Object::y_pos,x
        a16
        lda Object::x_pos
        ora #COIN_X_INSET
        sta misc_objects + Object::x_pos,x
        a8
        bra set_coin_hop
launch_jump_coin:
.a8
.i8
        jsr find_free_misc_slot
.i16
        lda Object::block_page
        sta misc_objects + Object::x_pos+1,x
        lda probe_column
        asl a                           ; the column x 16; the carry: bit 4, the second buffer
        asl a
        asl a
        asl a
        ora #COIN_X_INSET
        sta misc_objects + Object::x_pos,x
        lda probe_row
        adc #COIN_ABOVE_DROP            ; + 1 in the second buffer (05a L2)
        sta misc_objects + Object::y_pos,x
set_coin_hop:
.a8
.i16
        lda #COIN_SPEED
        sta misc_objects + Object::y_speed_whole,x
        lda #Y_HIGH_SCREEN
        sta misc_objects + Object::y_pos+1,x
        lda #MISC_COIN
        sta misc_objects + Object::state,x
        sep #P_X8
        lda #SQUARE2_COIN
        sta snd_square2_queue
        jsr add_one_coin
        inc coins_for_1up
        rts

; ---------------------------------------------------------------------------
; release_powerup: a power-up rises out of block b: kind $2E in enemy slot
; 5 (it replaces what the slot holds), at the block's page and X, 8 pixels
; above its Y, Y high 1 (05a 16.1).
; set_powerup_start: slot 5 rises (state 1), active, the tall box; a
; mushroom is a fire flower for a big or fiery player; behind the
; background; the power-up sound (05a 16.2). It writes slot 5 whatever D is,
; as the original: it is also the start of kind $2E in enemy_starts, which
; no list holds.
;
; In:       release_powerup: D = block b's record; powerup_kind
; Out:      slot 5's record; powerup_kind
; Changes:  A
; Original: $BC49-$BC5F, $BC60-$BC84
; ---------------------------------------------------------------------------
release_powerup:
.a8
.i8
        lda #KIND_POWERUP
        sta special_object + Object::kind
        a16
        lda Object::x_pos
        sta special_object + Object::x_pos
        a8
        lda Object::y_pos
        sec
        sbc #POWERUP_RISE_START
        sta special_object + Object::y_pos
        lda #Y_HIGH_SCREEN
        sta special_object + Object::y_pos+1
set_powerup_start:
.a8
.i8
        lda #POWERUP_RISING
        sta special_object + Object::state
        lda #ENEMY_ACTIVE
        sta special_object + Object::active
        lda #BOX_TALL_ENEMY
        sta special_object + Object::box
        lda powerup_kind
        cmp #POWERUP_STAR
        bcs @behind                     ; a star or a 1-up stays
        lda player_power
        cmp #POWER_FIRE
        bcc @kind
        lda #POWERUP_FLOWER
@kind:
        sta powerup_kind
@behind:
        lda #ATTR_BEHIND
        sta special_object + Object::attributes
        lda #SQUARE2_GROW_POWERUP
        sta snd_square2_queue
        rts

; ---------------------------------------------------------------------------
; run_powerup: the power-up, kind $2E in enemy slot 5 (05a 16.3, 16.4).
;
; state       meaning       each frame                                next
; 0           none          nothing                                   1
; 1-$11       it rises      on frames with frame_count AND 3 = 0: Y   + 1 each
;                           - 1, state + 1; after $11 the move        4 frames
;                           starts; it shows from state 6
; $80         it moves      the mushroom and the 1-up walk and fall,  -
;                           the star leaps, the flower stays; not
;                           during the freeze
; The move starts at +1 pixel a frame to the right, in front of the
; background. It rises 17 pixels in 68 frames. finish_powerup_frame: the
; screen place, the box, the picture, the player's touch (07: from state 6
; on, while it still rises), the bounds.
;
; In:       D = the power-up's record (slot 5: the only slot with kind $2E)
; Changes:  A, X, Y, and what the routines of 05b, 07 and 11 change
; Original: $BC85-$BCD7, finish_powerup_frame $BCD8-$BCEA
; ---------------------------------------------------------------------------
run_powerup:
.a8
.i8
        lda Object::state
        beq @done
        bmi @moving
        lda frame_count
        and #POWERUP_RISE_FRAMES
        bne @rising
        dec Object::y_pos
        lda Object::state
        inc Object::state
        cmp #POWERUP_RISE_END
        bcc @rising
        lda #POWERUP_SPEED              ; the move starts
        sta Object::x_speed
        lda #POWERUP_MOVING
        sta Object::state
        stz Object::attributes          ; in front of the background
        lda #FACING_RIGHT
        sta Object::direction
@rising:
        lda Object::state
        cmp #POWERUP_SHOWN
        bcs finish_powerup_frame
@done:
        rts
@moving:
        lda timer_hold
        bne finish_powerup_frame
        lda powerup_kind
        cmp #POWERUP_MUSHROOM
        beq @walk
        cmp #POWERUP_1UP
        beq @walk
        cmp #POWERUP_STAR
        bne finish_powerup_frame        ; the flower stays
        jsr move_leaper                 ; 05b
        jsr enemy_land_check            ; 07
        bra finish_powerup_frame
@walk:
        jsr move_ordinary_enemy         ; 05b
        jsr check_enemy_vs_tiles        ; 07
finish_powerup_frame:
.a8
.i8
        jsr enemy_screen_position       ; 11
        jsr check_enemy_offscreen       ; 11
        jsr enemy_hit_box               ; 07
        jsr draw_item_sprite            ; 11
        jsr player_hits_enemy           ; 07
        jmp check_enemy_in_bounds       ; 07

; ---------------------------------------------------------------------------
; scatter_brick_chunks: the broken brick becomes two objects, block b (the
; upper pieces) and block b + 2 (the lower ones), each drawn as two pieces
; (05a 17.10): the X for draw_brick_pieces; both 1 pixel a frame left; the
; upper ones 6 up, the lower ones 4 up (the fractions 0); the lower ones on
; the upper ones' page and X, 8 pixels lower (their Y high is not written).
;
; In:       D = block b's record
; Changes:  A, X
; Original: $BE41-$BE6F (its second store of the upper Y speed is not made)
; ---------------------------------------------------------------------------
scatter_brick_chunks:
.a8
.i8
        lda Object::x_pos
        sta Object::block_origin_x
        ax16
        tdc
        clc
        adc #BLOCK_LOWER * OBJECT_PAGE
        tax                             ; X16 = the lower pieces' record
        lda #BRICK_UPPER_SPEED
        sta Object::y_speed
        lda #BRICK_LOWER_SPEED
        sta a:Object::y_speed,x
        lda Object::x_pos
        sta a:Object::x_pos,x
        a8
        lda #BRICK_X_SPEED
        sta Object::x_speed
        sta a:Object::x_speed,x
        lda Object::y_pos
        clc
        adc #BRICK_LOWER_DROP
        sta a:Object::y_pos,x
        sep #P_X8
        rts

; ---------------------------------------------------------------------------
; run_block_objects: block object b moves (05a 17.11). The state's first
; nybble ($10) lasts until this first run, which keeps the low nybble.
;
; state       meaning          work                                   next
; 0           free             nothing                                $11 or $12 at a bump
; 1 ($11)     a bumped block   the fall (drop_block_object), the      1, or 0 with its
;                              picture; back in its row when (Y AND   metatile due
;                              $0F) is below 5
; 2 ($12)     brick pieces     the fall and the move of the upper     2 or 0
;                              and the lower object, the picture;
;                              above the picture they go on; else
;                              the lower ones stop at Y $F0 and the
;                              pieces end when the upper ones reach it
; A bumped block rises 2 a frame against the pull $50 and is back in its row
; in its 14th frame (the bump frame is the first).
;
; In:       D = block b's record (game_core: block 1, then block 0)
; Changes:  A, X, Y, and what the routines of 11 change
; Original: $BE70-$BED3
; ---------------------------------------------------------------------------
BLOCK_FREE      = 0
run_block_objects:
.a8
.i8
        lda Object::state
        beq @done
        and #BLOCK_STATE_LOW
        cmp #BLOCK_BUMPED
        beq @bumped
        jsr drop_block_object
        jsr move_object_sideways
        phd
        a16
        tdc
        clc
        adc #BLOCK_LOWER * OBJECT_PAGE
        tcd                             ; D = the lower pieces
        a8
        jsr drop_block_object
        jsr move_object_sideways
        pld
        jsr block_screen_position       ; 11
        jsr check_block_offscreen       ; 11
        jsr draw_brick_pieces           ; 11
        lda Object::y_pos+1
        beq @pieces                     ; above the picture: they go on
        ax16
        tdc
        clc
        adc #BLOCK_LOWER * OBJECT_PAGE
        tax                             ; X16 = the lower pieces' record
        a8
        lda #PIECES_BOTTOM
        cmp a:Object::y_pos,x
        bcs @lower
        sta a:Object::y_pos,x
@lower:
        sep #P_X8
        lda Object::y_pos
        cmp #PIECES_BOTTOM
        bcs @free
@pieces:
        lda #BLOCK_PIECES
        bra @store
@bumped:
        jsr drop_block_object
        jsr block_screen_position       ; 11
        jsr check_block_offscreen       ; 11
        jsr draw_bumped_block           ; 11
        lda Object::y_pos
        and #ROW_PIXELS
        cmp #BLOCK_IN_ROW
        lda #BLOCK_BUMPED
        bcs @store
        lda #BLOCK_REPLACE_DUE
        sta Object::block_replace       ; back in its row: its metatile is due
@free:
        lda #BLOCK_FREE
@store:
        sta Object::state
@done:
        rts

; ---------------------------------------------------------------------------
; replace_bumped_metatile: for block 1, then block 0: when screen list 1 is
; empty and the block's metatile is due, the cell gets it, and its picture
; (02 replace_block_picture) (05a 17.12). The wait for an empty list makes
; the metatile wait: the bump frame always has its blank picture (and a
; score after a brick), so a broken brick's empty metatile comes in the next
; frame, and block 0 waits one more frame when block 1 wrote its record in
; the same call. The original's block_residual has no reader (05a L21) and
; its decrement of the flag is overwritten: neither is kept.
;
; In:       any D
; Out:      D as it was; the cells; screen list 1
; Changes:  A, X, Y, probe_row, probe_column
; Time:     each frame of play
; Original: $BED4-$BF01
; ---------------------------------------------------------------------------
replace_bumped_metatile:
.a8
.i8
        phd
        pea block_objects + OBJECT_PAGE ; block 1, then block 0
        pld
@block:
        lda screen_list_1_end
        bne @next
        lda Object::block_replace
        beq @next
        lda Object::block_buffer
        sta probe_column
        lda Object::block_origin_y
        sta probe_row
        lda Object::block_metatile
        jsr store_probe_cell            ; 07
        ldx probe_column
        ldy probe_row
        lda Object::block_metatile
        jsr replace_block_picture       ; 02: X = the ring column, Y = the row offset
        stz Object::block_replace
@next:
        a16
        tdc
        sec
        sbc #OBJECT_PAGE
        tcd
        cmp #block_objects
        a8
        bcs @block
        pld
        rts
