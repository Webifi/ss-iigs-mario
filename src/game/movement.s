; The shared moves of the objects, the enemy slot loop, the enemy spawns and
; the start of each enemy kind (document 05a sections 3 and 18-22; the
; original's $BF02-$C8D6).
;
; The moves: every object of the game moves by the same two routines. The
; X position is 24 bits (Object::x_fraction, then the word x_pos: the page
; in its high byte, the pixel in its low byte) and moves by the X speed, a
; signed byte in 1/16 pixel each frame. The Y position is 24 bits too
; (y_fraction, then the word y_pos: Y high in its high byte) and moves by
; the Y speed, a signed word in 1/256 pixel each frame; apply_gravity then
; adds the pull of the frame to the speed and keeps it under a top speed.
; The fall routines give each kind its pull and its top speed. They run in
; 16-bit adds where the original makes two or three 8-bit adds with their
; carries; the bits are the same (each routine says where). The player
; (document 04), the enemies (05b) and the objects (objects.s) call them.
;
; The enemy slot loop: game_core (03) runs enemies_and_loops for each of
; the six enemy slots once each frame (the victory mode for slot 0 only),
; then score_numbers (07) for the same slot. An active slot runs its kind's
; routine (run_enemy_slot: the routines of 05b and objects.s); a free slot
; reads the next spawn record of the area (read_enemy_spawns): the castle
; maze loop check, a queued wave, an enemy of the list, an area link, or
; the next enemy of a running wave. The enemy lists are converted at build
; time by the levels part (scripts/area_data.py, src/game/area.s) into
; spawn records with their pages resolved (06 section 12, 05a L33); this
; file applies the reading rules that depend on the frame: the screen
; edges, the free slots, slot 5's filter, hard mode, the waits.
;
; The start of each kind (route_enemy_start, from the spawns, the groups
; and the waves): the start values of 05a section 21, into the enemy's
; record. A kind's own values live in the union fields of Object (05a
; section 2.3, state.inc), so a started enemy keeps every field that its
; start does not write, as in the original (05a section 2.4, L14).
;
; Registers: A8 I8 at each entry and exit unless a header says otherwise.
; DBR = bank 0. D = the record of the object that a routine works on
; (state.inc); a routine that steps D over other records puts it back.
; The routines of other parts that this file calls are expected to return
; with D, DBR and the widths of their entry.
; The dispatch tables (enemy_starts, wave_starts, enemy_runs) are in this
; bank: JMP (table,X) reads its address from the program bank.
;
; Merged and split against the original:
; - move_enemy_sideways and move_object_sideways are one routine: the
;   original's move_enemy_sideways only turned the enemy number into the
;   object slot, and D is the record here.
; - apply_gravity has two entries: apply_gravity (the down pull only, the
;   original's A = 0) and apply_gravity_up (the down and the up pull, A not
;   0). apply_vertical_move is apply_gravity under its own name.
; - The original's shared tails of the fall routines (set_top_speed_three,
;   drop_object_max_a, red_paratroopa_move, red_paratroopa_gravity) are
;   gone: each fall routine loads its pull and its top speed.
; - The loop check (check_loop) is its own routine; the original keeps it
;   at the start of read_enemy_spawns.
; - The list stepping (step_enemy_list, step_list_two, step_list_three) is
;   one step to the next spawn record (step_spawn_record): the records have
;   no byte lengths and the build resolved the page flag.
; - The start routines share their tails by the job (the box, the speed,
;   the facing); a store that a later step of the same start replaces is
;   not made (no_wave_code, start_nothing_last, store_enemy_speed,
;   tall_box_return, store_box_return, big_lift_box_kind are gone).
; - place_at_right_edge and finish_flame_start are one routine.
;
; Routines:
;   move_player_sideways     the player's sideways move, unless the spring holds him ($BF09)
;   move_object_sideways     X += the X speed x 16 (also move_enemy_sideways) ($BF0F, $BF02)
;   apply_gravity            the Y move by the speed, then the down pull and its limit ($BFD7)
;   apply_gravity_up         apply_gravity, then the up pull and its limit ($BFD7)
;   move_player_up_down      the player's fall ($BF4D)
;   drop_enemy_fast          a falling enemy; a spiny egg falls slower ($BF63)
;   drop_falling_lift        a falling lift ($BF6B)
;   red_paratroopa_down      a red paratroopa's way down ($BF70)
;   red_paratroopa_up        a red paratroopa's way up ($BF75)
;   move_drop_lift           a drop lift ($BF88)
;   move_enemy_slowly        a slow fall: blooper, swimming cheep-cheep, Bowser ($BF8C)
;   move_leaper_vertically   a leaper: lava ball, leaping paratroopa, bullet bill ($BF92)
;   apply_vertical_move      apply_gravity for the flying cheep-cheep ($BF96)
;   drop_block_object        a bumped block or a brick piece ($BFA4)
;   lower_lift               a lift on its way down ($BFB4)
;   raise_lift               a lift on its way up ($BFB7)
;   enemies_and_loops        one enemy slot of the frame ($C047)
;   check_loop               the loop check of a castle maze ($C0CC-$C12E)
;   send_player_back         a missed loop: the player and the lists 4 pages back ($C08C)
;   read_enemy_spawns        a free slot takes the next spawn record ($C0CC)
;   step_spawn_record        the list goes on with the next record ($C250-$C26B)
;   take_queued_enemy        a free slot takes the wave's next enemy or the second vine ($C216)
;   start_enemy_object       state 0, then the start of the kind ($C226)
;   route_enemy_start        the start of the slot's kind ($C26C)
;   start_*                  the start routines of the kinds ($C2F0-$C881)
;   clear_enemy_vspeed       the Y speed 0 ($C363)
;   begin_wave               a wave kind: the wave runs ($C7A0)
;   stop_waves               the waves stop; Lakitu leaves ($C7B8)
;   run_cloud_rider_wave     Lakitu comes back, or throws a spiny egg ($C3A4)
;   start_flying_fish        a flying cheep-cheep of the wave ($C4A8)
;   start_bowser_flame       a flame from Bowser's mouth or from the edge ($C5A3)
;   place_at_right_edge      an enemy 32 pixels past the screen's right edge ($C5D8, $C61F)
;   start_firework           a firework burst over the castle ($C63D)
;   start_bullet_fish_wave   a bullet bill or a swimming cheep-cheep of the wave ($C69C)
;   pick_unused_row          the wave's enemy takes a row that the wave has not used ($C6D6)
;   copy_enemy_to_free_slot  the second half of Bowser or of a long fire bar ($C575)
;   start_enemy_group        the two or three enemies of a group ($C71B)
;   offset_lift_x            a lift's X by an offset ($C871)
;   run_enemy_slot           the routine of the slot's kind each frame ($C882)
;   run_nothing              the routine of the kinds that do nothing each frame ($C8D6)

.a8
.i8

; ---- Values of the original program (05a unless named) -------------------
STATE_LAKITU_LEAVES = 1          ; the state of a Lakitu that leaves (05b)
; The spawn records of the levels part (06; see read_enemy_spawns).
; The enemy slot that a value names: the enemy number e = slot - SLOT_ENEMY,
; 0-5 (vine_slots, duplicate_slot, bowser_front_slot, balance_side,
; Object::hammer_owner and the second half's Object::active $80 + e hold
; enemy numbers, as in the original).

; ---- Values of this file ---------------------------------------------------
BYTE_SIGN       = $80           ; the sign bit of a byte: (b xor $80) - $80 extends it to a word
FRACTION_HALF   = $0080         ; a Y speed word: its fraction is 1/2 or more (05a 3.3)
FRACTION_ALL    = $00FF         ; a Y speed word: the fraction 255/256
; The pull (1/256 pixel each frame) and the top speed (whole pixels) of
; each fall routine (05a 3.4).
PLAYER_TOP_SPEED = 4            ; move_player_up_down
FAST_DROP_PULL  = $3D           ; drop_enemy_fast
SPINY_EGG_PULL  = $20           ;   for a spiny egg
FAST_DROP_TOP   = 3
FALLING_LIFT_PULL = $20         ; drop_falling_lift
FALLING_LIFT_TOP = 3
PARATROOPA_PULL_DOWN = 3        ; red_paratroopa_down, red_paratroopa_up
PARATROOPA_PULL_UP = 6
PARATROOPA_TOP  = 2
DROP_LIFT_PULL  = $7F           ; move_drop_lift
DROP_LIFT_TOP   = 2
SLOW_PULL       = $0F           ; move_enemy_slowly
SLOW_TOP        = 2
LEAPER_PULL     = $1C           ; move_leaper_vertically
LEAPER_TOP      = 3
BLOCK_PULL      = $50           ; drop_block_object (its top speed: block_fall_limit)
LIFT_PULL_DOWN  = 5             ; lower_lift, raise_lift: the kind $29 rule never applies (05a L16)
LIFT_PULL_UP    = 10
LIFT_TOP        = 3
; The enemy slot loop and the spawns (05a 18-20).
ONE_VINE        = 1             ; vine_count: one vine grows (take_queued_enemy then starts the second)
PARSER_STEP     = 7             ; parser_task AND this: the step of the column builder's round (06)
PARSER_BUILT    = 7             ;   this step: the builder built a column in the frame before (05a 18.1)
LOOP_CHECKS     = 11            ; the castle maze loop checks (loop_worlds, loop_pages, loop_heights)
LOOP_GROUP      = 3             ; world 7 counts its checks in groups of three (05a 19.2)
LOOP_BACK       = $0400         ; a missed loop: 4 pages back (05a 19.4)
SPAWN_AHEAD     = $30           ; an entry starts 48 pixels past the screen's right edge (05a 20.2)
COLUMN_MASK     = $FFF0         ; a world X word: its 16-pixel column
ENEMY_Y_DROP    = 8             ; the kinds below KIND_BOWSER_FLAME start 8 pixels lower (05a 21.1)
NEW_ENEMY_MASK  = 1             ; Object::offscreen at a start: no box tests until the first box (07)
START_KINDS     = $37           ; the kinds of enemy_starts: $00-$36
; The start values (05a 21.2-21.13).
RED_KOOPA_STATE = 1             ; a red koopa starts in state 1
LAVA_START      = $0202         ; a lava ball: Y high 2 (below the picture), Y 2
LAVA_WAIT       = 1             ;   its slow timer
RESCUED_Y       = $B8           ; the retainer or the princess
PARATROOPA_LOW_RANGE = $30      ; a red paratroopa above Y $80 turns $30 lower,
PARATROOPA_HIGH_RANGE = $E0     ;   else $20 higher (+ $E0, 8 bits)
PIRANHA_SPEED   = 1
PIRANHA_RISE    = $18           ; its high Y is this above its low Y
LEAPING_PARATROOPA_SPEED = $F8  ; -1/2 pixel each frame
LIFT_START_RISE = 2             ; a balance lift starts 2 pixels higher
DROP_LIFT_FLAG  = $FF           ; a drop lift's Object::on_lift at its start
UP_DOWN_RANGE   = $40           ; an up-down lift: its middle Y is $40 below or above its start
LIFT_UP_SPEED   = $FF10         ; a lift that rises: -240/256 pixel each frame
LIFT_DOWN_SPEED = $00F0         ; a lift that sinks: +240/256
LIFT_RIGHT      = 0             ; offset_lift_x entries: +8 (lift_offsets),
LIFT_MIDDLE     = 1             ;   +12,
LIFT_LEFT       = 2             ;   -8
FIRE_BAR_MOVE   = 4             ; a fire bar's centre: 4 pixels right and down
BOWSER_FIRST_WAIT = $DF         ; bowser_breath_timer; also his first direction (05a L32, 05b L5)
BOWSER_START_HITS = 5
BOWSER_START_SPEED = 2
; The waves (05a 21.4-21.9).
CLOUD_RIDER_GAP = $80           ; frenzy timer: frames between two spiny eggs
LAKITU_ROUNDS   = 7             ; rounds of CLOUD_RIDER_GAP without Lakitu before he comes back
LAKITU_LOW_LIMIT = $2C          ; no egg while the player's Y is above this
LAKITU_RETURN_Y = $20           ; a returning Lakitu's Y, 32 pixels past the right edge
EGG_DROP        = 8             ; a spiny egg starts 8 pixels above Lakitu
SPINY_EGG_SPEED = $FD00         ; up 3 pixels each frame
EDGE_GAP        = $20           ; place_at_right_edge: 32 pixels past the screen's right edge
FISH_SLOTS      = 3             ; flying cheep-cheeps only in slots below this, one more with hard_mode_2
FISH_JUMP_SPEED = $FB           ; up 5 pixels each frame
FISH_STILL      = 0             ; the player's speed class: still
FISH_MOVING     = 4             ; the player's speed class: moving (flying_fish_x_speeds rows of 4)
FISH_FAST       = $19           ; the player's X speed byte from this on (unsigned): the fast class
FISH_START_Y    = $01F8         ; Y high 1, Y $F8: below the picture
FLAME_TARGET_ABOVE = 0          ; bowser_flame_y_force entry 0: the target height is above the flame
FLAME_BACK      = $0E           ; a flame starts this left of Bowser's X (8 bits: 05a L7)
FLAME_DROP      = 8             ; and 8 pixels below his Y
FLAME_GAP       = $20           ; frenzy timer: next_flame_gap + this,
FLAME_GAP_HARD  = $10           ;   minus this with hard_mode_2
FIREWORK_GAP    = $20           ; frenzy timer: frames between two bursts
FIREWORK_BACK   = $30           ; the bursts are placed from the castle flag's X - this
FISH_WAVE_SLOTS = 3             ; the swimming cheep-cheeps of wave $17: slots below this
FISH_WAVE_GREY  = $AA           ; random + e from this on: the other kind of cheep-cheep
FISH_KIND_PICK  = 1             ; (y AND this): the entry of wave_fish_kinds
ALL_ROWS        = $FF           ; bit_filter: every row of wave $17 is used
WAVE_ROWS       = 7             ; the row number's mask: rows 0-7
WAVE_GAP        = $20           ; frenzy timer: frames between two enemies of wave $17
GROUP_COUNT     = 2             ; a group: 2 enemies, 3 when bit 0 of its number is 1
GROUP_LOW_Y     = $B0           ; a group's Y, before the start's + 8:
GROUP_HIGH_Y    = $70           ;   this one when bit 1 of its number is 1
GROUP_GAP       = $18           ; the members stand 24 pixels apart
GROUP_GOOMBAS   = 4             ; groups 0-3 are goombas (buzzy beetles in hard mode), 4-7 koopas
GROUP_THREE     = 1             ; bit of the group number: three members
GROUP_HIGH      = 2             ; bit of the group number: the high row

.segment "AREASTATE"
gravity_pull:   .res 2          ; apply_gravity: the down pull of this call, as a word
gravity_top:    .res 2          ; apply_gravity: the top speed x 256 (also read by apply_gravity_up)
spawn_limit:    .res 2          ; read_enemy_spawns: the 16-pixel column 48 pixels past the right edge
fish_random:    .res 1          ; start_flying_fish: random + e AND 3 (05a 21.5 t1)
fish_start:     .res 1          ; start_flying_fish: the X start entry of a still player (05a 21.5 t0)
group_kind:     .res 1          ; start_enemy_group: the kind of the members
group_y:        .res 1          ; start_enemy_group: the members' Y
group_x:        .res 2          ; start_enemy_group: the next member's world X
.segment "GAMEPLAY"

; ---------------------------------------------------------------------------
; move_player_sideways: the player's sideways move (05a 3.2). While the jump
; spring holds him (spring_anim not 0) he does not move, and the spring's
; step comes back as the pixels moved: move_on_ground and
; move_sideways_in_air (04) store it as his push on the scroll (05a L22).
;
; In:       D = the player's record
; Out:      as move_object_sideways; or A = spring_anim (1-4)
; Changes:  A, the flags
; Keeps:    X, Y, D
; Time:     each frame of play, about 90 cycles (10 while the spring holds him)
; Original: $BF09-$BF0E
; ---------------------------------------------------------------------------
move_player_sideways:
.a8
.i8
        lda spring_anim
        beq move_object_sideways        ; no spring step: the move (the next routine)
        rts                             ; the spring holds him: its step is his push (05a L22)

; ---------------------------------------------------------------------------
; move_object_sideways (also move_enemy_sideways): the object moves sideways
; by its X speed (05a 3.1, 3.2). The speed is a signed byte in 1/16 pixel
; each frame; the move adds the speed x 16, sign extended, to the 24-bit X:
; one 16-bit add of the fraction and the pixel, then the page with the
; carry and the sign. The original's three adds (fraction, pixel with the
; carry, page with the carry and $FF or 0) give the same bits.
;
; In:       D = the record; Object::x_speed
; Out:      Object::x_fraction, x_pos moved; A = the whole pixels of the
;           move, -8 to +8 (the pixel byte after the move minus the one
;           before; the player's push on the scroll (04) and 05b read it)
; Changes:  A, the flags
; Keeps:    X, Y, D
; Time:     about 80 cycles; many times each frame
; Original: $BF0F-$BF4C (move_object_sideways), $BF02-$BF08
;           (move_enemy_sideways: the enemy number to the object slot)
; ---------------------------------------------------------------------------
move_enemy_sideways:
move_object_sideways:
.a8
.i8
        lda Object::x_pos               ; the pixel before the move, for the pixels moved
        pha
; The move in 1/256 pixel: the speed byte sign extended, x 16.
        a16
        lda Object::x_speed
        and #$00FF
        eor #BYTE_SIGN
        sec
        sbc #BYTE_SIGN
        asl a
        asl a
        asl a
        asl a
; The fraction and the pixel in one add; the carry out of the pixel and the
; sign of the move go into the page.
        clc
        adc Object::x_fraction
        sta Object::x_fraction
        a8
        lda Object::x_pos+1
        adc #0
        bit Object::x_speed
        bpl @page
        dec a                           ; a move to the left: + $FF, the sign of the speed
@page:
        sta Object::x_pos+1
        pla                             ; the pixels moved: the new pixel - the old one
        eor #$FF
        sec
        adc Object::x_pos
        rts

; ---------------------------------------------------------------------------
; apply_gravity: the vertical move of the object, then the pull of the frame
; (05a 3.3). The speed of before the pull moves the object: the 24-bit Y
; (y_fraction, the pixel, Y high) gains the Y speed, sign extended. Then the
; down pull adds to the speed, and the down limit sets the speed to the top
; speed when its whole part is the top speed or more by the original's
; 8-bit test (bit 7 of whole - top clear) and its fraction is 1/2 or more:
; a speed of top + 0 to top + 127/256 is not limited.
;
; The 16-bit forms give the original's bits: the Y move is one 16-bit add of
; (fraction, pixel) + (speed fraction, speed whole) and an 8-bit add of the
; carry and the sign to Y high; the pull is a 16-bit add to the speed word;
; the limit test subtracts top x 256 from the speed word, so bit 15 of the
; result is bit 7 of the original's whole - top, and bit 7 is the
; fraction's.
;
; In:       D = the record; A = the down pull (1/256 pixel each frame,
;           0-255); Y = the top speed (whole pixels down, 1-8)
; Out:      Object::y_fraction, y_pos, y_speed; gravity_top = the top
;           speed x 256 (apply_gravity_up reads it)
; Changes:  A, the flags, gravity_pull, gravity_top
; Keeps:    X, Y, D
; Time:     about 100 cycles; several times each frame
; Original: $BFD7-$C018 (apply_gravity with A = 0)
; ---------------------------------------------------------------------------
apply_gravity:
.a8
.i8
        a16
        and #$00FF
        sta gravity_pull
        tya                             ; the top speed (Y8: the high byte 0)
        xba
        sta gravity_top
; The move by the speed of before the pull.
        clc
        lda Object::y_fraction          ; the fraction and the pixel
        adc Object::y_speed
        sta Object::y_fraction
        a8
        lda Object::y_pos+1             ; Y high: + the carry, + $FF for a rising object
        adc #0
        bit Object::y_speed_whole
        bpl @high
        dec a
@high:
        sta Object::y_pos+1
; The down pull and the down limit.
        a16
        lda Object::y_speed
        clc
        adc gravity_pull
        sta Object::y_speed
        sec
        sbc gravity_top                 ; bit 15: bit 7 of the original's whole - top
        bmi @done
        bit #FRACTION_HALF
        beq @done
        lda gravity_top                 ; the top speed, fraction 0
        sta Object::y_speed
@done:
        a8
        rts

; ---------------------------------------------------------------------------
; apply_gravity_up: apply_gravity, then the up pull of the frame and the up
; limit (05a 3.3, steps 4-5). The up pull subtracts from the speed; when the
; whole part is then below -top by the original's 8-bit test (bit 7 of
; whole - (-top) set) and the fraction is below 1/2, the speed becomes
; -top + 255/256. Adding top x 256 to the speed word gives the original's
; whole - (-top) in the high byte.
;
; In:       D = the record; A = the down pull; X = the up pull (1/256 pixel
;           each frame, 0-255); Y = the top speed
; Out:      as apply_gravity
; Changes:  A, the flags, gravity_pull, gravity_top
; Keeps:    X, Y, D
; Time:     about 150 cycles
; Original: $BFD7-$C046 (apply_gravity with A not 0)
; ---------------------------------------------------------------------------
apply_gravity_up:
.a8
.i8
        jsr apply_gravity
        a16
        txa                             ; the up pull (X8: the high byte 0)
        eor #$FFFF
        sec
        adc Object::y_speed             ; the speed - the up pull
        sta Object::y_speed
        clc
        adc gravity_top                 ; bit 15: bit 7 of whole - (-top)
        bpl @done
        bit #FRACTION_HALF
        bne @done
        lda #FRACTION_ALL               ; whole -top, fraction 255/256
        sec
        sbc gravity_top
        sta Object::y_speed
@done:
        a8
        rts

; ---------------------------------------------------------------------------
; The fall routines (05a 3.4): each gives apply_gravity the pull and the top
; speed of its objects.
;
; In:       D = the record (the player's for move_player_up_down)
; Out:      as apply_gravity
; Changes:  A, Y, the flags, gravity_pull, gravity_top
; Keeps:    X, D
; Time:     apply_gravity's (apply_gravity_up's) and 10 cycles; 20 for the
;           two with the up pull, which keep X around it
; Original: the addresses in each line (the original's routines end with
;           X = obj_slot; here X is kept)
; ---------------------------------------------------------------------------

; move_player_up_down ($BF4D-$BF62): the player falls with gravity_up (04).
; While the timers run (no timer_hold) the jump spring holds him: no move.
; During timer_hold he falls even while the spring moves.
move_player_up_down:
.a8
.i8
        lda timer_hold
        bne @fall
        lda spring_anim
        bne @held
@fall:
        lda gravity_up
        ldy #PLAYER_TOP_SPEED
        jmp apply_gravity
@held:
        rts

; drop_enemy_fast ($BF63-$BF6A): a falling enemy; a spiny egg falls slower.
drop_enemy_fast:
.a8
.i8
        lda #FAST_DROP_PULL
        ldy Object::state
        cpy #ENEMY_SPINY_EGG
        bne @pull
        lda #SPINY_EGG_PULL
@pull:
        ldy #FAST_DROP_TOP
        jmp apply_gravity

; drop_falling_lift ($BF6B-$BF6F).
drop_falling_lift:
.a8
.i8
        lda #FALLING_LIFT_PULL
        ldy #FALLING_LIFT_TOP
        jmp apply_gravity

; red_paratroopa_down ($BF70-$BF74): the down pull only.
red_paratroopa_down:
.a8
.i8
        lda #PARATROOPA_PULL_DOWN
        ldy #PARATROOPA_TOP
        jmp apply_gravity

; red_paratroopa_up ($BF75-$BF76): the down pull, then the up pull.
red_paratroopa_up:
.a8
.i8
        phx
        lda #PARATROOPA_PULL_DOWN
        ldx #PARATROOPA_PULL_UP
        ldy #PARATROOPA_TOP
        jsr apply_gravity_up
        plx
        rts

; move_drop_lift ($BF88-$BF8B).
move_drop_lift:
.a8
.i8
        lda #DROP_LIFT_PULL
        ldy #DROP_LIFT_TOP
        jmp apply_gravity

; move_enemy_slowly ($BF8C-$BF91): the blooper, the swimming cheep-cheeps,
; the bridge fall and Bowser (05b).
move_enemy_slowly:
.a8
.i8
        lda #SLOW_PULL
        ldy #SLOW_TOP
        jmp apply_gravity

; move_leaper_vertically ($BF92-$BF93): the lava ball, the leaping
; paratroopa, the bullet bill, the swooping cheep-cheep (05b).
move_leaper_vertically:
.a8
.i8
        lda #LEAPER_PULL
        ldy #LEAPER_TOP
        jmp apply_gravity

; drop_block_object ($BFA4-$BFAC): a bumped block or a brick piece (objects.s
; run_block_objects): the top speed is entry 1 of the original's
; block_fall_limits (entry 0 has no reader, 05a L17).
drop_block_object:
.a8
.i8
        lda #BLOCK_PULL
        ldy block_fall_limit
        jmp apply_gravity

; lower_lift ($BFB4-$BFB6): a lift on its way down: the down pull only. The
; original would give kind $29 the pull 9, but only kinds $24 and $25 come
; here (05a L16).
lower_lift:
.a8
.i8
        lda #LIFT_PULL_DOWN
        ldy #LIFT_TOP
        jmp apply_gravity

; raise_lift ($BFB7-$BFD0): a lift on its way up: the down pull, then the up
; pull (05a L16 as lower_lift).
raise_lift:
.a8
.i8
        phx
        lda #LIFT_PULL_DOWN
        ldx #LIFT_PULL_UP
        ldy #LIFT_TOP
        jsr apply_gravity_up
        plx
        rts

; apply_vertical_move ($BF96-$BF9E): apply_gravity under the name that the
; swooping cheep-cheep (05b swoop_fish) calls, with A = the down pull ($0D)
; and Y = the top speed (5). The original's register roles were the other
; way round (Y the pull, A the top speed).
apply_vertical_move = apply_gravity

; ---------------------------------------------------------------------------
; enemies_and_loops: one enemy slot in the frame (05a 18.1). A second half
; (Bowser's, a long fire bar's: Object::active $80 + the first half's
; enemy number) stays while its first half is active, and does nothing
; else. An active slot runs its kind's routine. A free slot reads the next
; spawn record, except in the frame after the column builder built a column
; (parser_task AND 7 = 7, as the builder's step left it in the frame
; before): one frame of each round of eight in which no free slot takes an
; enemy.
;
; In:       D = the record of the enemy slot (game_core: slots 0-5; the
;           victory mode: slot 0)
; Out:      D the same record (score_numbers, 07, runs next for it)
; Changes:  A, X, Y, and what the slot's routine changes
; Time:     each frame for each enemy slot
; Original: $C047-$C06A
; ---------------------------------------------------------------------------
enemies_and_loops:
.a8
.i8
        lda Object::active
        bmi @second_half
        beq @free
        jmp run_enemy_slot
; A second half ends with its first half: X16 = the first half's record.
@second_half:
        and #SECOND_HALF_OF
        xba
        lda #0
        x16
        tax
        lda enemy_objects + Object::active, x
        sep #P_X8
        bne @done
        stz Object::active
@done:
        rts
@free:
        lda parser_task
        and #PARSER_STEP
        cmp #PARSER_BUILT
        beq @done
        jmp read_enemy_spawns

; ---------------------------------------------------------------------------
; check_loop: the loop check of a castle maze (05a 19.2). A castle repeats a
; part of its area until the player takes the right path: the area builder
; sets loop_command at a check's column (06). At the first column of a page
; (parse_column 0) the check i of this world and parse page decides: the
; player passes when his Y is the check's and he stands on the ground. In
; worlds other than 7 a miss sends him back at once; world 7 counts its
; checks in groups of three, and the group sends him back when not all three
; passed. No check of this world and page: loop_command stays.
;
; In:       loop_command not 0; parse_column 0; the player's record
; Out:      loop_command, loop_correct, loop_passes; a miss: the player,
;           the screen and the lists 4 pages back, enemy slots 0-4 erased
; Changes:  A, X, Y
; Time:     about 150 cycles, at the turn of each free slot while a check is
;           due
; Original: $C0CC-$C12E (the start of read_enemy_spawns)
; ---------------------------------------------------------------------------
check_loop:
.a8
.i8
        ldx #LOOP_CHECKS - 1            ; the highest check of this world and page
@find:
        lda loop_worlds,x
        cmp player_record + PlayerRecord::world
        bne @next
        lda loop_pages,x
        cmp parse_page
        beq @found
@next:
        dex
        bpl @find
        rts                             ; no check here: loop_command stays
@found:
        lda player_object + Object::y_pos
        cmp loop_heights,x
        bne @miss
        lda player_object + Object::state
        cmp #PLAYER_ON_GROUND
        bne @miss
; A pass: outside world 7 the loop ends; in world 7 it counts.
        lda player_record + PlayerRecord::world
        cmp #WORLD_7
        bne @clear
        inc loop_correct
        bra @count
@miss:
        lda player_record + PlayerRecord::world
        cmp #WORLD_7
        bne @back
@count:
        inc loop_passes
        lda loop_passes
        cmp #LOOP_GROUP
        bne @checked                    ; the group goes on: the counts stay
        lda loop_correct
        cmp #LOOP_GROUP
        beq @clear                      ; all three passed
@back:
        jsr send_player_back
        jsr erase_all_enemies           ; 05b: enemy slots 0-4 and frenzy_kind
@clear:
        stz loop_passes
        stz loop_correct
@checked:
        stz loop_command
        rts

; ---------------------------------------------------------------------------
; send_player_back: a missed loop sends the player, the screen and the area
; builder 4 pages back, and the enemy list starts again from its first
; record (05a 19.4). Four pages are two laps of the name tables and of the
; collision buffers, so the screen and the buffers stay valid (06 section
; 15). The entries of the pages left of the screen are passed over by the
; left-edge rule of read_enemy_spawns.
;
; In:       X = the loop check (0 to LOOP_CHECKS - 1)
; Out:      the player's, screen_left's and screen_right's pages - 4;
;           enemy_offset 0; the area builder at the check's rewind point
; Changes:  A, and what rewind_area_objects changes
; Time:     once for each missed loop
; Original: $C08C-$C0CB
; ---------------------------------------------------------------------------
send_player_back:
.a8
.i8
        a16
        lda player_object + Object::x_pos
        sec
        sbc #LOOP_BACK
        sta player_object + Object::x_pos
        lda screen_left
        sec
        sbc #LOOP_BACK
        sta screen_left
        lda screen_right
        sec
        sbc #LOOP_BACK
        sta screen_right
        a8
        stz enemy_offset
; The levels part: parse_page and the area list's page 4 back, its page step
; 0, its place = loop_rewind_offsets[X] (06 section 15).
        jmp rewind_area_objects

; ---------------------------------------------------------------------------
; read_enemy_spawns: a free enemy slot takes the next spawn record of the
; area (05a 20.2). One call starts at most one record (a group starts two
; or three enemies). The records are read in order: one that waits blocks
; the later ones.
;
; The levels part converts each area's enemy list at build time into spawn
; records, with the original's page rules applied (the page flag counted
; once, the entry after a page skip that loses its page flag, the row-15
; entry with the page flag that is an enemy, 05a L33). next_spawn_record
; (src/game/area.s) gives the record that enemy_offset names in:
;   spawn_kind      SPAWN_END, SPAWN_SKIP, SPAWN_LINK, or the enemy kind
;                   (the list's byte 1 AND $3F: $00-$36 one enemy, $37-$3E
;                   a group)
;   spawn_hard_only not 0: an entry only for hard_mode_2 (byte 1 bit 6)
;   spawn_x         the entry's world X: page x 256 + column x 16 (a word)
;   spawn_y         the entry's Y: its row x 16
;   spawn_area_byte, spawn_link_world, spawn_entrance_page: a link's area
;                   byte (all 8 bits), world and entrance page
;
; The rules, in the original's order:
; 1. The loop check, when one is due at the first column of a page.
; 2. A queued wave (frenzy_queue) starts in this slot.
; 3. The end of the list: take_queued_enemy.
; 4. Slot 5 reads only the links and the power-up entries; another record
;    waits, untouched.
; 5. A page skip: a slot 0-4 goes on with the next record in the same call.
; 6. The slot takes the entry's X first (it stays in a slot that does not
;    start, 05a 20.2).
; 7. Left of the screen's right edge: a link counts; any other entry is
;    passed over (it never starts).
; 8. Past the column 48 pixels past the right edge: the entry waits;
;    take_queued_enemy.
; 9. The slot takes the entry's Y (also kept when it does not start). A
;    link counts. A hard-mode entry without hard_mode_2 is passed over. A
;    group starts its enemies. A goomba is a buzzy beetle in hard mode. The
;    enemy starts; when its start leaves the slot free (stop_waves, a
;    Lakitu during a wave, 05a L30) the entry stays for the next call.
; The loop check's second run after a page skip in the original changes
; nothing (it cleared loop_command or found no check), so the port goes on
; at step 3.
;
; In:       D = the free slot's record (Object::active 0)
; Out:      the slot, enemy_offset, area_byte, entrance_page, the waves
; Changes:  A, X, Y, spawn_limit, and what the start routines change
; Time:     at the turn of each free slot each frame: about 120 cycles for a
;           waiting entry
; Original: $C0CC-$C215, $C22E-$C24F (with step_enemy_list $C250,
;           step_list_three $C25B, step_list_two $C25E)
; ---------------------------------------------------------------------------
read_enemy_spawns:
.a8
.i8
        lda loop_command
        beq @queued
        lda parse_column
        bne @queued
        jsr check_loop
@queued:
        lda frenzy_queue
        beq @record
        sta Object::kind
        lda #ENEMY_ACTIVE
        sta Object::active
        stz frenzy_queue
        jmp start_enemy_object
@record:
        jsr next_spawn_record           ; the levels part: the spawn_* values of record enemy_offset
        lda spawn_kind
        cmp #SPAWN_END
        bne @slot_5
        jmp take_queued_enemy
@slot_5:
        cmp #SPAWN_LINK
        beq @edges
        ldx Object::slot
        cpx #SLOT_SPECIAL
        bne @skip
        cmp #KIND_POWERUP
        beq @edges
        rts                             ; slot 5: this entry waits
@skip:
        cmp #SPAWN_SKIP
        bne @edges
        inc enemy_offset                ; a page skip: on with the next record
        bra @record
; The entry's place against the screen.
@edges:
        a16
        lda screen_right
        clc
        adc #SPAWN_AHEAD
        and #COLUMN_MASK
        sta spawn_limit
        lda spawn_x
        sta Object::x_pos               ; also in a slot that does not start
        cmp screen_right
        bcc @behind
        lda spawn_limit
        cmp spawn_x
        a8
        bcs @window
        jmp take_queued_enemy           ; past the limit: the entry waits
@behind:
        a8
        lda spawn_kind
        cmp #SPAWN_LINK
        beq @link
        bra step_spawn_record           ; the screen passed it: it never starts
@window:
        lda spawn_y
        sta Object::y_pos               ; also in a slot that does not start
        lda #Y_HIGH_SCREEN
        sta Object::y_pos+1
        lda spawn_kind
        cmp #SPAWN_LINK
        beq @link
        lda spawn_hard_only
        beq @kind
        lda hard_mode_2
        beq step_spawn_record           ; an entry for hard mode only
@kind:
        lda spawn_kind
        cmp #KIND_GROUP
        bcc @one
        cmp #KIND_GROUP_END
        bcs @one                        ; kind $3F: one enemy (no list holds it, 05a L12)
        jmp start_enemy_group
@one:
        cmp #KIND_GOOMBA
        bne @start
        ldx hard_mode
        beq @start
        lda #KIND_BUZZY_BEETLE
@start:
        sta Object::kind
        lda #ENEMY_ACTIVE
        sta Object::active
        jsr start_enemy_object
        lda Object::active
        bne step_spawn_record
        rts                             ; the start left the slot free: the entry stays (05a L30)
; A link counts for its world: the area that a pipe or a vine of this area
; leads to (06 section 13).
@link:
        lda spawn_link_world
        cmp player_record + PlayerRecord::world
        bne step_spawn_record
        lda spawn_area_byte
        sta area_byte
        lda spawn_entrance_page
        sta entrance_page
        ; falls into step_spawn_record

; ---------------------------------------------------------------------------
; step_spawn_record: the list goes on with the next record (05a 20.5). The
; original steps its byte offset by 2 or 3 and clears its page step; the
; records have neither.
;
; In:       enemy_offset
; Out:      enemy_offset + 1
; Changes:  the flags
; Time:     8 cycles
; Original: $C250-$C26B (step_enemy_list, step_list_three, step_list_two)
; ---------------------------------------------------------------------------
step_spawn_record:
.a8
.i8
        inc enemy_offset
        rts

; ---------------------------------------------------------------------------
; take_queued_enemy: a free slot at the end of the list, or before an entry
; that waits, takes the running wave's next enemy, or the second vine
; object while one vine grows (05a 20.3). The slot's Object::active is not
; set here: the wave's routine sets it when it puts an enemy in the slot.
; The kind stays in the slot's kind byte even when the wave puts nothing
; there (05a L25).
;
; In:       D = the free slot's record
; Out:      the slot, as the start of the kind leaves it
; Changes:  A, X, Y, and what the start routines change
; Time:     each frame for each free slot during a wave
; Original: $C216-$C225
; ---------------------------------------------------------------------------
take_queued_enemy:
.a8
.i8
        lda frenzy_kind
        bne @start
        lda vine_count
        cmp #ONE_VINE
        bne @none
        lda #KIND_VINE
@start:
        sta Object::kind
        bra start_enemy_object
@none:
        rts

; ---------------------------------------------------------------------------
; start_enemy_object: the slot's state 0, then the start of its kind (05a
; 20.4).
; route_enemy_start: the start of the slot's kind (05a 21.1): the kinds
; below KIND_BOWSER_FLAME start 8 pixels lower (an 8-bit add: Y high stays)
; and take no part in the box tests until their routine builds their box;
; then the kind's start routine. The original's jump routine leaves
; values in Y, the carry and its scratch bytes; each one that a start
; routine reads has its own name here (05a L3, L23).
;
; In:       D = the record, with its kind, place, Object::active and (but
;           for start_enemy_group's members) the state 0 set
; Out:      the start values of the kind (05a 21.2)
; Changes:  A, X, Y, and what the start routine changes
; Time:     at each start
; Original: $C226-$C22D (start_enemy_object), $C26C-$C2EF (route_enemy_start)
; ---------------------------------------------------------------------------
start_enemy_object:
.a8
.i8
        stz Object::state
route_enemy_start:
.a8
.i8
        lda Object::kind
        cmp #KIND_BOWSER_FLAME
        bcs @start
        lda Object::y_pos
        adc #ENEMY_Y_DROP               ; the carry is clear: the kind is below KIND_BOWSER_FLAME
        sta Object::y_pos
        lda #NEW_ENEMY_MASK
        sta Object::offscreen
        lda Object::kind
@start:
        asl a
        tax
        jmp (.loword(enemy_starts),x)
; The start routine of each kind, $00-$36 (05a 21.2). The kinds that no list,
; wave or builder starts (05a 21.2 "in no list") keep the original's entry.
enemy_starts:
        .addr start_walker              ; $00 green koopa
        .addr start_walker              ; $01
        .addr start_walker              ; $02 buzzy beetle
        .addr start_red_koopa           ; $03
        .addr start_nothing             ; $04
        .addr start_hammer_bro          ; $05
        .addr start_goomba              ; $06
        .addr start_squid               ; $07 blooper
        .addr start_bullet_bill         ; $08 bullet bill of a wave
        .addr start_nothing             ; $09
        .addr start_fish                ; $0A grey cheep-cheep
        .addr start_fish                ; $0B red cheep-cheep
        .addr start_lava_ball           ; $0C
        .addr start_piranha             ; $0D
        .addr start_leaping_paratroopa  ; $0E green paratroopa, leaping
        .addr start_red_paratroopa      ; $0F
        .addr start_flyer_or_swimmer    ; $10 green paratroopa, flying
        .addr start_cloud_rider         ; $11 Lakitu
        .addr begin_wave                ; $12 the spiny wave
        .addr start_nothing             ; $13
        .addr begin_wave                ; $14 the flying cheep-cheep wave
        .addr begin_wave                ; $15 the Bowser flame wave
        .addr begin_wave                ; $16 the fireworks
        .addr begin_wave                ; $17 the bullet bill and cheep-cheep wave
        .addr stop_waves                ; $18
        .addr start_nothing             ; $19
        .addr start_nothing             ; $1A
        .addr start_fire_bar            ; $1B-$1E fire bars
        .addr start_fire_bar
        .addr start_fire_bar
        .addr start_fire_bar
        .addr start_long_fire_bar       ; $1F
        .addr start_nothing             ; $20-$23
        .addr start_nothing
        .addr start_nothing
        .addr start_nothing
        .addr start_scale_lift          ; $24 balance lift
        .addr start_up_down_lift        ; $25
        .addr start_big_lift_up         ; $26
        .addr start_big_lift_down       ; $27
        .addr start_side_lift           ; $28
        .addr start_drop_lift           ; $29
        .addr start_side_lift           ; $2A right-moving lift
        .addr start_lift_up             ; $2B small lift going up
        .addr start_lift_down           ; $2C small lift going down
        .addr start_bowser              ; $2D
        .addr set_powerup_start         ; $2E power-up (objects.s)
        .addr start_second_vine         ; $2F vine (objects.s, 05a L3)
        .addr start_nothing             ; $30 flagpole flag
        .addr start_nothing             ; $31 castle flag
        .addr start_nothing             ; $32 jump spring
        .addr start_nothing             ; $33 cannon bullet bill
        .addr start_nothing             ; $34 warp zone
        .addr start_rescued_person      ; $35
        .addr start_nothing             ; $36
.assert * - enemy_starts = START_KINDS * 2, error, "enemy_starts: one entry for each kind $00-$36"

; ---------------------------------------------------------------------------
; The small start routines (05a 21.3). Each one writes only its kind's
; start values into D's record: the box (Object::box), the facing (2:
; left), the speeds, the kind's own fields.
;
; In:       D = the enemy's record (route_enemy_start; start_lava_ball also
;           from move_lava_ball, 05b; start_piranha also from
;           build_vertical_pipe, 06)
; Out:      the start values
; Changes:  A, X, Y, the flags
; Time:     at each start, under 60 cycles
; Original: the addresses in each line
; ---------------------------------------------------------------------------

; start_nothing ($C2F0, also start_nothing_last $C881 and no_wave_code
; $C7B7): the kinds that start with the values that their caller set.
start_nothing:
.a8
.i8
        rts

; start_walker ($C30E-$C318): a walking enemy: its walk speed (faster in
; hard mode), the tall box, facing left, no Y speed.
start_walker:
.a8
.i8
        jsr set_walk_speed
        bra use_tall_box

; start_goomba ($C2F1-$C2F6): as start_walker, with the small box.
start_goomba:
.a8
.i8
        jsr set_walk_speed
        bra use_small_box

; start_red_koopa ($C31E-$C325): as start_walker, in state 1.
start_red_koopa:
.a8
.i8
        jsr start_walker
        lda #RED_KOOPA_STATE
        sta Object::state
        rts

; set_walk_speed (part of $C30E-$C318): the X speed walk_speeds[hard_mode].
set_walk_speed:
.a8
.i8
        ldx #0
        lda hard_mode
        beq @speed
        inx
@speed:
        lda walk_speeds,x
        sta Object::x_speed
        rts

; start_hammer_bro ($C328-$C33C): no throw yet, no X speed, the slow timer
; before the first walk toward the player, its own box, facing left.
start_hammer_bro:
.a8
.i8
        stz Object::hammer_timer
        stz Object::x_speed
        ldy hard_mode_2
        lda hammer_bro_walk_times,y
        ldx Object::slot
        sta timers + TIMER_ENEMY_INTERVAL - SLOT_ENEMY,x
        lda #BOX_HAMMER_BRO
        bra box_and_face_left

; start_flyer_or_swimmer ($C33D-$C341): the flying green paratroopa and
; Lakitu: no X speed, the tall box, facing left.
start_flyer_or_swimmer:
.a8
.i8
        stz Object::x_speed
        bra use_tall_box

; start_squid ($C342-$C345): the blooper: its speed 0, the small box.
start_squid:
.a8
.i8
        stz Object::x_speed
        ; falls into use_small_box

; use_small_box ($C346-$C349), use_tall_box ($C35A-$C35B),
; box_and_face_left ($C35C-$C362): the box, facing left, no Y speed.
use_small_box:
.a8
.i8
        lda #BOX_SMALL_ENEMY
        bra box_and_face_left
use_tall_box:
.a8
.i8
        lda #BOX_TALL_ENEMY
box_and_face_left:
.a8
.i8
        sta Object::box
        lda #FACING_LEFT
        sta Object::direction
        ; falls into clear_enemy_vspeed

; ---------------------------------------------------------------------------
; clear_enemy_vspeed: the object's Y speed 0, its fraction too (05a 21.3).
;
; In:       D = the record
; Out:      Object::y_speed 0; A = 0 (both bytes; callers of 05b and 07
;           store it on)
; Changes:  A
; Keeps:    X, Y, D
; Time:     13 cycles
; Original: $C363-$C36A
; ---------------------------------------------------------------------------
clear_enemy_vspeed:
.a8
.i8
        a16
        lda #0
        sta Object::y_speed
        a8
        rts

; start_red_paratroopa ($C34A-$C359): its start Y, and the middle Y of its
; way: $30 lower when it starts above Y $80, else $20 higher. The add is 8
; bits, with the clear carry that the original's jump routine leaves (05a
; L23).
start_red_paratroopa:
.a8
.i8
        lda Object::y_pos
        sta Object::paratroopa_start_y
        ldx #PARATROOPA_LOW_RANGE
        cmp #BYTE_SIGN
        bcc @middle
        ldx #PARATROOPA_HIGH_RANGE
@middle:
        txa
        clc
        adc Object::y_pos
        sta Object::paratroopa_middle_y
        bra use_tall_box

; start_bullet_bill ($C36B-$C374): facing left, the small box; no speed is
; set.
start_bullet_bill:
.a8
.i8
        lda #FACING_LEFT
        sta Object::direction
        lda #BOX_SMALL_ENEMY
        sta Object::box
        rts

; start_fish ($C375-$C384): a cheep-cheep: the small box, facing left, no Y
; speed; its move bit random + e AND $10; its start Y in the Y speed's
; fraction byte (the union field cheep_start_y).
CHEEP_MOVE_BIT  = $10
start_fish:
.a8
.i8
        jsr use_small_box
        ldx Object::slot
        lda random - SLOT_ENEMY,x
        and #CHEEP_MOVE_BIT
        sta Object::cheep_move
        lda Object::y_pos
        sta Object::cheep_start_y
        rts

; start_lava_ball ($C2F7-$C306): below the picture (Y high 2, Y 2), its slow
; timer 1, state 0, the small box. move_lava_ball (05b) also calls it to
; start each leap again.
start_lava_ball:
.a8
.i8
        a16
        lda #LAVA_START
        sta Object::y_pos
        a8
        lda #LAVA_WAIT
        ldx Object::slot
        sta timers + TIMER_ENEMY_INTERVAL - SLOT_ENEMY,x
        stz Object::state
        bra use_small_box

; start_rescued_person ($C307-$C30B): the retainer or the princess at Y $B8.
start_rescued_person:
.a8
.i8
        lda #RESCUED_Y
        sta Object::y_pos
        rts

; start_cloud_rider ($C385-$C389, $C395-$C397): Lakitu waits while a wave
; runs: the slot is erased and the entry stays (05a L30).
; place_cloud_rider ($C38A-$C394): lakitu_timer 0, no X speed, the tall box,
; facing left, no Y speed.
start_cloud_rider:
.a8
.i8
        lda frenzy_kind
        beq place_cloud_rider
        jmp clear_enemy_slot            ; 05b
place_cloud_rider:
.a8
.i8
        stz lakitu_timer
        bra start_flyer_or_swimmer

; start_piranha ($C787-$C79F): its speed 1, state 0, not moving, its low Y =
; its Y and its high Y $18 above, the small box. The area builder (06
; build_vertical_pipe) starts it too.
start_piranha:
.a8
.i8
        lda #PIRANHA_SPEED
        sta Object::piranha_speed
        stz Object::state
        stz Object::piranha_moving
        lda Object::y_pos
        sta Object::piranha_low_y
        sec
        sbc #PIRANHA_RISE
        sta Object::piranha_high_y
        lda #BOX_SMALL_ENEMY
        sta Object::box
        rts

; start_leaping_paratroopa ($C7D1-$C7DE): facing left, X speed -1/2 pixel,
; the tall box.
start_leaping_paratroopa:
.a8
.i8
        lda #FACING_LEFT
        sta Object::direction
        lda #LEAPING_PARATROOPA_SPEED
        sta Object::x_speed
        lda #BOX_TALL_ENEMY
        sta Object::box
        rts

; ---------------------------------------------------------------------------
; The fire bars (05a 21.10). start_long_fire_bar: a second half in a free
; slot holds the bar's other pieces (05b), then start_fire_bar. start_fire_bar:
; the angle's low byte 0, the turn speed and direction of its kind, the
; centre 4 pixels right (with the page) and 4 down (8 bits), the tall box.
;
; In:       D = the fire bar's record; its kind $1B-$1F
; Changes:  A, X, Y
; Original: $C459-$C45B (start_long_fire_bar), $C45C-$C487 (start_fire_bar)
; ---------------------------------------------------------------------------
start_long_fire_bar:
.a8
.i8
        jsr copy_enemy_to_free_slot
start_fire_bar:
.a8
.i8
        stz Object::firebar_angle_low
        lda Object::kind
        sec
        sbc #KIND_FIRE_BAR
        tax
        lda fire_bar_turn_speeds,x
        sta Object::firebar_speed
        lda fire_bar_turn_dirs,x
        sta Object::firebar_turn
        lda Object::y_pos
        clc
        adc #FIRE_BAR_MOVE
        sta Object::y_pos
        a16
        lda Object::x_pos
        clc
        adc #FIRE_BAR_MOVE
        sta Object::x_pos
        a8
        lda #BOX_TALL_ENEMY
        sta Object::box
        rts

; ---------------------------------------------------------------------------
; The lifts (05a 21.11).
;
; In:       D = the lift's record
; Out:      its start values; balance_side (start_scale_lift)
; Changes:  A, X, Y
; Original: $C7DF-$C880 (each routine's own address in its line)
; ---------------------------------------------------------------------------

; start_scale_lift ($C7DF-$C802), kind $24: 2 pixels higher; without
; hard_mode_2 8 pixels left. Balance lifts come in pairs: the first one of a
; pair waits in balance_side (its enemy number), the second one takes it as
; its state and ends the wait. Then 8 pixels right (the net move is 0, or +8
; with hard_mode_2), the fall flag (Object::direction) 0, and the drop
; lift's start.
start_scale_lift:
.a8
.i8
        lda Object::y_pos
        sec
        sbc #LIFT_START_RISE
        sta Object::y_pos
        lda hard_mode_2
        bne @pair
        ldx #LIFT_LEFT
        jsr offset_lift_x
@pair:
        ldx #BALANCE_NONE               ; the second lift of the pair ends the wait
        lda balance_side
        sta Object::state
        bpl @side
        lda Object::slot                ; the first lift waits for its partner
        sec
        sbc #SLOT_ENEMY
        tax
@side:
        stx balance_side
        stz Object::direction
        ldx #LIFT_RIGHT
        jsr offset_lift_x
        ; falls into start_drop_lift

; start_drop_lift ($C803-$C80A), kind $29 (and the end of $24): its on-lift
; byte $FF, then lift_start_common.
start_drop_lift:
.a8
.i8
        lda #DROP_LIFT_FLAG
        sta Object::on_lift
        bra lift_start_common

; start_side_lift ($C80B-$C811), kinds $28 and $2A: no X speed.
start_side_lift:
.a8
.i8
        stz Object::x_speed
        bra lift_start_common

; start_up_down_lift ($C812-$C827), kind $25: its top Y and its middle Y.
; Above Y $80 the top Y is the Y, the middle $40 lower; else the top Y is
; -Y (8 bits) and the middle $40 higher.
start_up_down_lift:
.a8
.i8
        ldx #UP_DOWN_RANGE
        lda Object::y_pos
        bpl @top
        eor #$FF                        ; -Y
        inc a
        ldx #<(-UP_DOWN_RANGE)
@top:
        sta Object::lift_top_y
        txa
        clc
        adc Object::y_pos
        sta Object::lift_middle_y
        ; falls into lift_start_common

; lift_start_common ($C828-$C82A): no Y speed, then set_lift_box.
lift_start_common:
.a8
.i8
        jsr clear_enemy_vspeed
        ; falls into set_lift_box

; set_lift_box ($C82B-$C83E): the large lift's box: the castle's in a castle
; area or with hard_mode_2, else the long one.
set_lift_box:
.a8
.i8
        lda #BOX_LIFT_CASTLE
        ldx area_type
        cpx #AREA_CASTLE
        beq @box
        ldx hard_mode_2
        bne @box
        lda #BOX_LARGE_LIFT
@box:
        sta Object::box
        rts

; start_big_lift_up ($C83F-$C844), kind $26, and start_big_lift_down
; ($C845-$C847), kind $27: the small lift's move, the large lift's box (the
; original's small box first is not stored).
start_big_lift_up:
.a8
.i8
        jsr lift_up_place
        bra set_lift_box
start_big_lift_down:
.a8
.i8
        jsr lift_down_place
        bra set_lift_box

; start_lift_up ($C84B-$C856), kind $2B, and start_lift_down ($C857-$C85F),
; kind $2C: rising or sinking at 240/256 pixel each frame, 12 pixels right,
; the small lift's box (start_small_lift_common $C860-$C86A).
start_lift_up:
.a8
.i8
        jsr lift_up_place
        bra small_lift_box
start_lift_down:
.a8
.i8
        jsr lift_down_place
small_lift_box:
.a8
.i8
        lda #BOX_SMALL_LIFT
        sta Object::box
        rts

; lift_up_place, lift_down_place (part of $C84B-$C862): the Y speed of a
; lift that rises or sinks, and the X 12 pixels right.
lift_up_place:
.a8
.i8
        a16
        lda #LIFT_UP_SPEED
        bra lift_place
lift_down_place:
.a8
.i8
        a16
        lda #LIFT_DOWN_SPEED
lift_place:
.a16
.i8
        sta Object::y_speed
        a8
        ldx #LIFT_MIDDLE
        ; falls into offset_lift_x

; ---------------------------------------------------------------------------
; offset_lift_x: the lift's X moves by one of three offsets, page with the
; carry (a 16-bit add of the offset word; the original adds the low and the
; high byte of the offset).
;
; In:       D = the lift's record; X = the entry (LIFT_RIGHT, LIFT_MIDDLE,
;           LIFT_LEFT)
; Out:      Object::x_pos + lift_offsets[X]
; Changes:  A, X
; Original: $C871-$C880
; ---------------------------------------------------------------------------
offset_lift_x:
.a8
.i8
        txa
        asl a
        tax
        a16
        lda Object::x_pos
        clc
        adc lift_offsets,x
        sta Object::x_pos
        a8
        rts

; ---------------------------------------------------------------------------
; start_bowser: Bowser (05a 21.12): his second half in a free slot, his slot
; in bowser_front_slot, the counters of his fight. His direction starts at
; the breath timer's value $DF (05a L32; 05b L5: draw_enemy and his routine
; read both bits until his routine sets 1 or 2).
;
; In:       D = Bowser's record (kind $2D)
; Changes:  A, X, Y
; Original: $C549-$C574
; ---------------------------------------------------------------------------
start_bowser:
.a8
.i8
        jsr copy_enemy_to_free_slot
        lda Object::slot
        sec
        sbc #SLOT_ENEMY
        sta bowser_front_slot
        stz bowser_body
        stz bridge_collapse
        lda Object::x_pos
        sta bowser_origin_x
        lda #BOWSER_FIRST_WAIT
        sta timers + TIMER_BOWSER_BREATH
        sta Object::direction
        lda #BOWSER_FEET_FRAMES
        sta bowser_feet
        ldx Object::slot
        sta timers + TIMER_ENEMY_FRAME - SLOT_ENEMY,x
        lda #BOWSER_START_HITS
        sta bowser_hits
        lda #BOWSER_START_SPEED
        sta bowser_speed
        rts

; ---------------------------------------------------------------------------
; copy_enemy_to_free_slot: the second half of Bowser or of a long fire bar
; (05a 21.12). It takes the lowest free enemy slot from slot 0 up; the
; original's search has no upper end, so when slots 0-5 are all active it
; takes "slot 6" (05a L8): its active byte is the seventh active byte, here
; the Object::active of the first fireball's record, which no fireball
; reads, and its X and Y are the first fireball's, as in the original
; ($15, $74, $8D, $BC, $D5). The second half gets $80 + the first half's
; enemy number, the place of the first half and Y high 1; its kind is not
; written. The first half becomes active.
;
; In:       D = the first half's record
; Out:      duplicate_slot = the second half's enemy number (0-6); the
;           second half's record
; Changes:  A, X, the flags
; Time:     at the start of Bowser and of a long fire bar
; Original: $C575-$C59C
; ---------------------------------------------------------------------------
copy_enemy_to_free_slot:
.a8
.i8
        ldx #0                          ; X = the enemy number n
@find:
        cpx #ENEMY_SLOTS
        beq @found                      ; none of 0-5 free: the seventh active byte (05a L8)
        txa
        xba
        lda #0
        x16
        tay                             ; Y16 = n x OBJECT_PAGE: its record
        lda enemy_objects + Object::active,y
        sep #P_X8                       ; (SEP keeps the zero flag of the load)
        beq @found
        inx
        bra @find
@found:
        stx duplicate_slot
        txa
        xba
        lda #0
        x16
        tax                             ; X16 = the second half's record
        lda Object::slot
        sec
        sbc #SLOT_ENEMY
        ora #SECOND_HALF                ; $80 + the first half's enemy number
        sta enemy_objects + Object::active,x
        lda #Y_HIGH_SCREEN
        sta enemy_objects + Object::y_pos+1,x
        lda Object::y_pos
        sta enemy_objects + Object::y_pos,x
        a16
        lda Object::x_pos
        sta enemy_objects + Object::x_pos,x
        a8
        sep #P_X8
        lda #ENEMY_ACTIVE
        sta Object::active
        rts

; ---------------------------------------------------------------------------
; The waves (05a 21.4-21.9). A wave kind ($12, $14-$17) that a list entry,
; frenzy_queue, Lakitu, Bowser or the castle flag starts sets frenzy_kind;
; then each free slot that reaches take_queued_enemy runs the wave's routine
; each frame. The wave timer is the frame timer timers + TIMER_FRENZY, the
; same byte as enemy slot 5's frame timer (05a L29: clear_enemy_slot for
; slot 5 stops it).
;
; frenzy_kind   meaning     events
; 0             no wave     a wave kind starts begin_wave (frenzy_kind =
;                           the kind); move_cloud_rider sets $12, Bowser
;                           $15, the castle flag $16 (05b)
; $12, $14-$17  wave k runs each free slot at the end of the list or before
;                           a waiting entry runs wave k's routine; kind $18
;                           (stop_waves), erase_all_enemies, the flame from
;                           Bowser's mouth, move_cloud_rider,
;                           run_castle_flag and fireball_hits_enemy set 0
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; begin_wave: the start of a wave kind: frenzy_kind = the kind, then the
; wave's routine.
;
; In:       D = the slot's record; its kind $12 or $14-$17
; Changes:  A, X, Y, and the wave routine's
; Original: $C7A0-$C7B6
; ---------------------------------------------------------------------------
begin_wave:
.a8
.i8
        lda Object::kind
        sta frenzy_kind
        sec
        sbc #KIND_SPINY
        asl a
        tax
        jmp (.loword(wave_starts),x)
wave_starts:
        .addr run_cloud_rider_wave      ; $12 spinies from Lakitu
        .addr start_nothing             ; $13 (its start is start_nothing: never here)
        .addr start_flying_fish         ; $14
        .addr start_bowser_flame        ; $15
        .addr start_firework            ; $16
        .addr start_bullet_fish_wave    ; $17

; ---------------------------------------------------------------------------
; stop_waves: kind $18 stops the waves: each slot 5-0 whose kind is Lakitu's
; gets the leaving state (the search does not look at Object::active, 05a
; L25); frenzy_kind 0; this slot stays free, so its entry stays and runs
; again each frame until the screen passes it (05a L30).
;
; In:       D = the slot's record
; Changes:  A, X
; Original: $C7B8-$C7D0
; ---------------------------------------------------------------------------
stop_waves:
.a8
.i8
        ax16
        ldx #(ENEMY_SLOTS - 1) * OBJECT_PAGE
@slot:
        sep #P_M8
        lda enemy_objects + Object::kind,x
        cmp #KIND_LAKITU
        bne @next
        lda #STATE_LAKITU_LEAVES
        sta enemy_objects + Object::state,x
@next:
        rep #P_M8
        txa
        sec
        sbc #OBJECT_PAGE
        tax
        bpl @slot
        ax8
        stz frenzy_kind
        stz Object::active
        rts

; ---------------------------------------------------------------------------
; run_cloud_rider_wave: the spiny wave, kind $12 (05a 21.4). Each 128
; frames (the wave timer) in a free slot 0-4: with Lakitu (the highest of
; slots 4-0 whose kind is his, active or not, 05a L25) and the player low
; enough, a spiny egg falls from Lakitu in this slot; without Lakitu, after
; 7 such rounds a Lakitu comes back in the highest free slot 4-0, 32 pixels
; past the screen's right edge.
;
; The original measures the gap to the player for the egg's X speed
; (measure_player_gap, 05b) and then loses the result: every egg starts with
; X speed 0, facing right (05a L5). For a slot of kind $12 the measure
; writes only its own scratch, so the port does not run it.
; A returning Lakitu ends in the flame's start: the flame's box, X fraction
; 0, state 0 (05a L6).
;
; In:       D = the slot's record (its kind $12)
; Out:      the egg in this slot, or the Lakitu in his slot
; Changes:  A, X, Y
; Time:     each frame for each free slot during the wave
; Original: $C3A4-$C44E
; ---------------------------------------------------------------------------
LAKITU_SLOTS    = 5             ; Lakitu and the eggs: enemy slots 0-4
run_cloud_rider_wave:
.a8
.i8
        lda timers + TIMER_FRENZY
        bne @done
        lda Object::slot
        cmp #SLOT_SPECIAL
        bcs @done
        lda #CLOUD_RIDER_GAP
        sta timers + TIMER_FRENZY
; Lakitu: the highest of slots 4-0 with his kind.
        ax16
        ldx #(LAKITU_SLOTS - 1) * OBJECT_PAGE
@find:
        sep #P_M8
        lda enemy_objects + Object::kind,x
        cmp #KIND_LAKITU
        beq @lakitu
        rep #P_M8
        txa
        sec
        sbc #OBJECT_PAGE
        tax
        bpl @find
        ax8
; No Lakitu: he comes back after LAKITU_ROUNDS rounds, in the highest free
; slot of 4-0.
        inc lakitu_timer
        lda lakitu_timer
        cmp #LAKITU_ROUNDS
        bcc @done
        ax16
        ldx #(LAKITU_SLOTS - 1) * OBJECT_PAGE
@free:
        sep #P_M8
        lda enemy_objects + Object::active,x
        beq @return
        rep #P_M8
        txa
        sec
        sbc #OBJECT_PAGE
        tax
        bpl @free
        ax8
@done:
        rts
.a8
.i16
@return:
        phd
        rep #P_M8
        txa
        clc
        adc #enemy_objects
        tcd                             ; D = the free slot's record
        ax8
        lda #KIND_LAKITU
        sta Object::kind
        stz lakitu_timer
        stz Object::x_speed
        lda #FACING_LEFT
        sta Object::direction
        lda #LAKITU_RETURN_Y
        jsr place_at_right_edge         ; Y, X; box BOX_FLAME, active, state 0 (05a L6)
        jsr clear_enemy_vspeed
        pld
        rts
; The egg: in this slot, at Lakitu's place, 8 pixels higher.
.a8
.i16
@lakitu:
        lda player_object + Object::y_pos
        cmp #LAKITU_LOW_LIMIT
        bcc @no_egg
        lda enemy_objects + Object::state,x
        bne @no_egg
        lda enemy_objects + Object::y_pos,x
        sec
        sbc #EGG_DROP
        sta Object::y_pos
        lda #Y_HIGH_SCREEN
        sta Object::y_pos+1
        a16
        lda enemy_objects + Object::x_pos,x
        sta Object::x_pos
        lda #SPINY_EGG_SPEED
        sta Object::y_speed
        ax8
        lda #BOX_SMALL_ENEMY
        sta Object::box
        stz Object::x_speed             ; the measured speed is lost (05a L5)
        lda #FACING_RIGHT
        sta Object::direction
        lda #ENEMY_ACTIVE
        sta Object::active
        lda #ENEMY_SPINY_EGG
        sta Object::state
        rts
.a8
.i16
@no_egg:
        sep #P_X8
        rts

; ---------------------------------------------------------------------------
; start_flying_fish: the flying cheep-cheep wave, kind $14 (05a 21.5). When
; the wave timer is 0, every free slot takes the small box, facing left, no
; Y speed, and starts the next gap; slots 0-2 (0-3 with hard_mode_2) take a
; fish. The fish jumps out of the water ($F8, below the picture) at a speed
; and an X from the player's place that depend on his speed and on the
; random bits:
; - class = 0 for a still player, FISH_MOVING for a moving one, twice that
;   for a fast one (his X speed byte $19 or more: an unsigned test, so any
;   leftward speed is fast);
; - X speed = flying_fish_x_speeds[class + r], r = random + e AND 3, facing
;   right;
; - a still player: the X start entry i = r (or random + 2 + e AND $0F when
;   random + 1 + e AND 3 is not 0); when bit 1 of i is 1 the fish flies left
;   (its speed negated). A moving player: i = class + r.
; - X = the player's X + flying_fish_x_offsets[i] (the build gives the
;   original's add or subtract as a signed word: + for i with bit 1 set).
;
; In:       D = the slot's record (its kind $14)
; Changes:  A, X, Y, fish_random, fish_start
; Time:     each frame for each free slot during the wave
; Original: $C4A8-$C53B, finish_fish_start $C53C-$C548
; ---------------------------------------------------------------------------
FISH_GAP_PICK   = 3             ; random + 1 + e AND this: the gap entry, and the still player's choice
FISH_RANDOM     = 3             ; random + e AND this: r
FISH_START_PICK = $0F           ; random + 2 + e AND this: the still player's other X start entry
FISH_TURN       = 2             ; bit 1 of the X start entry: + offset, and a still player's fish flies left
start_flying_fish:
.a8
.i8
        lda timers + TIMER_FRENZY
        bne @none
        jsr use_small_box
        ldx Object::slot
        lda random + 1 - SLOT_ENEMY,x
        and #FISH_GAP_PICK
        tay
        lda flying_fish_gaps,y
        sta timers + TIMER_FRENZY
        cpx #FISH_SLOTS + SLOT_ENEMY    ; slots 0-2 take a fish,
        bcc @fish
        lda hard_mode_2                 ;   and slot 3 with hard_mode_2
        beq @none
        cpx #FISH_SLOTS + SLOT_ENEMY + 1
        bcc @fish
@none:
        rts
; The fish: its speed and its X start entry.
@fish:
        lda random - SLOT_ENEMY,x
        and #FISH_RANDOM
        sta fish_random
        lda #FISH_JUMP_SPEED
        sta Object::y_speed_whole
        lda #FISH_STILL                 ; the player's speed class
        ldy player_object + Object::x_speed
        beq @class
        lda #FISH_MOVING
        cpy #FISH_FAST
        bcc @class
        asl a
@class:
        tay                             ; Y = the class
        clc
        adc fish_random
        sta fish_start                  ; a still player's entry, unless the random bits choose
        lda random + 1 - SLOT_ENEMY,x
        and #FISH_GAP_PICK
        beq @speed
        lda random + 2 - SLOT_ENEMY,x
        and #FISH_START_PICK
        sta fish_start
@speed:
        tya
        clc
        adc fish_random
        tax                             ; X = class + r: the speed, and a moving player's X entry
        lda flying_fish_x_speeds,x
        sta Object::x_speed
        lda #FACING_RIGHT
        sta Object::direction
        lda player_object + Object::x_speed
        bne @place                      ; a moving player: X entry class + r
        ldx fish_start
        txa
        and #FISH_TURN
        beq @place
        lda Object::x_speed             ; a still player's fish with bit 1: it flies left
        eor #$FF
        inc a
        sta Object::x_speed
        lda #FACING_LEFT
        sta Object::direction
@place:
        txa
        asl a
        tax
        a16
        lda player_object + Object::x_pos
        clc
        adc flying_fish_x_offsets,x
        sta Object::x_pos
        lda #FISH_START_Y
        sta Object::y_pos
        a8
        lda #ENEMY_ACTIVE
        sta Object::active
        rts

; ---------------------------------------------------------------------------
; start_bowser_flame: the Bowser flame wave, kind $15 (05a 21.6). When the
; wave timer is 0: the flame's drift 0 and the flame sound (an OR). With
; Bowser in his slot the flame starts at his mouth: 14 pixels left of his X
; on his page (8 bits: no borrow into the page, 05a L7) and 8 pixels below
; his Y; its height h is random + e AND 3, and it drifts toward
; bowser_flame_heights[h]; frenzy_kind 0 (one flame for each breath) and the
; timer is not set. Without Bowser the flame starts 32 pixels past the
; screen's right edge at the height bowser_flame_heights[h], and the timer
; is the next gap.
;
; In:       D = the slot's record (its kind $15)
; Changes:  A, X, Y
; Original: $C5A3-$C5D7, $C5EC-$C61E
; ---------------------------------------------------------------------------
FLAME_HEIGHT_PICK = 3           ; random + e AND this: the flame's height h
start_bowser_flame:
.a8
.i8
        lda timers + TIMER_FRENZY
        bne @done
        stz Object::flame_drift
        lda #NOISE_BOWSER_FLAME
        tsb snd_noise_queue
        lda bowser_front_slot
        xba
        lda #0
        x16
        tax                             ; X16 = Bowser's record
        lda enemy_objects + Object::kind,x
        cmp #KIND_BOWSER
        beq @mouth
        sep #P_X8
; From the right edge, at a height of the table.
        jsr next_flame_gap              ; 05b: A = the next gap
        clc
        adc #FLAME_GAP
        ldy hard_mode_2
        beq @timer
        sec
        sbc #FLAME_GAP_HARD
@timer:
        sta timers + TIMER_FRENZY
        jsr flame_height
        lda bowser_flame_heights,y
        jmp place_at_right_edge
; From Bowser's mouth.
.a8
.i16
@mouth:
        lda enemy_objects + Object::x_pos+1,x
        sta Object::x_pos+1
        lda enemy_objects + Object::x_pos,x
        sec
        sbc #FLAME_BACK                 ; the page does not borrow (05a L7)
        sta Object::x_pos
        lda enemy_objects + Object::y_pos,x
        clc
        adc #FLAME_DROP
        sta Object::y_pos
        sep #P_X8
        jsr flame_height
        ldx #FLAME_TARGET_ABOVE         ; drift entry 0: the target height above the flame
        lda bowser_flame_heights,y
        cmp Object::y_pos
        bcc @drift
        inx
@drift:
        lda bowser_flame_y_force,x
        sta Object::flame_drift
        stz frenzy_kind
        bra finish_flame_start
@done:
        rts

; flame_height (part of $C5A3-$C61E): the flame's height number h = random
; + e AND 3, in Object::flame_height and in Y.
flame_height:
.a8
.i8
        ldx Object::slot
        lda random - SLOT_ENEMY,x
        and #FLAME_HEIGHT_PICK
        sta Object::flame_height
        tay
        rts

; ---------------------------------------------------------------------------
; place_at_right_edge: the enemy at Y = A, 32 pixels past the screen's right
; edge (page with the carry); then finish_flame_start: the flame's box, Y
; high 1, active, X fraction 0, state 0 (05a 21.6).
;
; In:       D = the enemy's record; A = its Y
; Out:      its place, box, Object::active and state
; Changes:  A
; Original: $C5D8-$C5EB (place_at_right_edge), $C61F-$C630 (finish_flame_start;
;           its A = 0 has no reader here: pick_unused_row clears the Y
;           fraction itself)
; ---------------------------------------------------------------------------
place_at_right_edge:
.a8
.i8
        sta Object::y_pos
        a16
        lda screen_right
        clc
        adc #EDGE_GAP
        sta Object::x_pos
        a8
finish_flame_start:
.a8
.i8
        lda #BOX_FLAME
        sta Object::box
        lda #Y_HIGH_SCREEN
        sta Object::y_pos+1
        lda #ENEMY_ACTIVE
        sta Object::active
        stz Object::x_fraction
        stz Object::state
        rts

; ---------------------------------------------------------------------------
; start_firework: the fireworks, kind $16 (05a 21.7). When the wave timer is
; 0: the next gap, one burst less, and a burst over the castle: the castle
; flag is the highest of slots 5-0 with its kind (the original's search has
; no lower end, 05a L9; the fireworks start only after the castle flag, so
; it is always found); burst i = fireworks_count + the flag's state, at the
; flag's X - $30 + firework_x_offsets[i] (page with the borrow and the
; carry) and firework_y_offsets[i].
;
; In:       D = the slot's record (its kind $16)
; Changes:  A, X, Y
; Original: $C63D-$C689
; ---------------------------------------------------------------------------
start_firework:
.a8
.i8
        lda timers + TIMER_FRENZY
        bne @done
        lda #FIREWORK_GAP
        sta timers + TIMER_FRENZY
        dec fireworks_count
        ax16
        ldx #(ENEMY_SLOTS - 1) * OBJECT_PAGE
@find:
        sep #P_M8
        lda enemy_objects + Object::kind,x
        cmp #KIND_STAR_FLAG
        beq @flag
        rep #P_M8
        txa
        sec
        sbc #OBJECT_PAGE
        tax
        bne @find                       ; slots 5-1 hold no flag: slot 0 (05a L9)
        sep #P_M8
@flag:
        lda enemy_objects + Object::state,x
        clc
        adc fireworks_count
        a16
        and #$00FF
        tay                             ; Y16 = the burst i
        lda firework_x_offsets,y        ; the byte of burst i, as a word
        and #$00FF
        sec
        sbc #FIREWORK_BACK
        clc
        adc enemy_objects + Object::x_pos,x
        sta Object::x_pos
        ax8                             ; Y8 = i
        lda firework_y_offsets,y
        sta Object::y_pos
        lda #Y_HIGH_SCREEN
        sta Object::y_pos+1
        lda #ENEMY_ACTIVE
        sta Object::active
        stz Object::firework_step
        lda #FIREWORK_FRAMES
        sta Object::firework_frames
@done:
        rts

; ---------------------------------------------------------------------------
; start_bullet_fish_wave: the bullet bill and cheep-cheep wave, kind $17
; (05a 21.8). When the wave timer is 0: in a water area slots 0-2 take a
; swimming cheep-cheep (mostly the grey one in world 2, the red one
; elsewhere: random + e $AA or more takes the other); elsewhere a bullet
; bill with the blast sound (an OR), while none of slots 0-4 holds an
; active one. The enemy takes a row that the wave has not used yet
; (pick_unused_row), 32 pixels past the right edge, and starts as its kind.
;
; In:       D = the slot's record (its kind $17)
; Changes:  A, X, Y
; Original: $C69C-$C6D5, $C6FD-$C71A
; ---------------------------------------------------------------------------
BULLET_SLOTS    = 5             ; one bullet bill of the wave at a time among slots 0-4
start_bullet_fish_wave:
.a8
.i8
        lda timers + TIMER_FRENZY
        bne @done
        lda area_type
        cmp #AREA_WATER
        bne @bullet
        lda Object::slot
        cmp #FISH_WAVE_SLOTS + SLOT_ENEMY
        bcs @done
        ldy #0
        ldx Object::slot
        lda random - SLOT_ENEMY,x
        cmp #FISH_WAVE_GREY
        bcc @world
        iny
@world:
        lda player_record + PlayerRecord::world
        cmp #WORLD_2
        beq @fish
        iny
@fish:
        tya
        and #FISH_KIND_PICK
        tay
        lda wave_fish_kinds,y
        bra pick_unused_row
@bullet:
        ax16
        ldx #0
@find:
        sep #P_M8
        lda enemy_objects + Object::active,x
        beq @next
        lda enemy_objects + Object::kind,x
        cmp #KIND_BULLET_FRENZY
        beq @wait
@next:
        rep #P_M8
        txa
        clc
        adc #OBJECT_PAGE
        tax
        cpx #BULLET_SLOTS * OBJECT_PAGE
        bcc @find
        ax8
        lda #SQUARE2_BLAST
        tsb snd_square2_queue
        lda #KIND_BULLET_FRENZY
        bra pick_unused_row
.a8
.i16
@wait:
        sep #P_X8
@done:
        rts

; ---------------------------------------------------------------------------
; pick_unused_row: the wave's enemy takes the next row whose bit_filter bit
; is 0, from the row random + e AND 7 on (7 wraps to 0); when all rows are
; used they start again. Its place: Y = wave_row_ys[row], 32 pixels past the
; right edge, Y fraction 0; the wave timer; then route_enemy_start for the
; kind (8 pixels lower; start_bullet_bill or start_fish give the box).
;
; In:       D = the slot's record; A = the kind
; Changes:  A, X, Y
; Original: $C6D6-$C6FC (and $C6C3-$C6D5)
; ---------------------------------------------------------------------------
pick_unused_row:
.a8
.i8
        sta Object::kind
        lda bit_filter
        cmp #ALL_ROWS
        bne @row
        stz bit_filter
@row:
        ldx Object::slot
        lda random - SLOT_ENEMY,x
@try:
        and #WAVE_ROWS
        tay
        lda single_bit_masks,y
        bit bit_filter
        beq @free
        iny
        tya
        bra @try
@free:
        tsb bit_filter
        lda wave_row_ys,y
        jsr place_at_right_edge
        stz Object::y_fraction
        lda #WAVE_GAP
        sta timers + TIMER_FRENZY
        jmp route_enemy_start

; ---------------------------------------------------------------------------
; start_enemy_group: a group entry of the list starts its two or three
; enemies (05a 21.13). Group g = kind - $37: goombas (buzzy beetles in hard
; mode) for g 0-3, green koopas for 4-7; Y $B0, or $70 when bit 1 of g is 1;
; 2 members, 3 when bit 0 of g is 1. The first stands at the screen's right
; edge (the entry's own column is not used), the next ones 24 pixels apart,
; each in the lowest free slot of 0-4, while one is free. The members' state
; is not written (route_enemy_start directly). The entry is used up even
; when fewer members found a slot.
;
; In:       D = the free slot that read the entry; A = the kind ($37-$3E)
; Out:      the members' slots; enemy_offset + 1
; Changes:  A, X, Y, group_kind, group_y, group_x, group_count
; Original: $C71B-$C786
; ---------------------------------------------------------------------------
GROUP_SLOTS     = 5             ; the members take slots 0-4
start_enemy_group:
.a8
.i8
        sec
        sbc #KIND_GROUP
        tay                             ; Y = g
        ldx #KIND_GREEN_KOOPA
        cmp #GROUP_GOOMBAS
        bcs @kind
        ldx #KIND_GOOMBA
        lda hard_mode
        beq @kind
        ldx #KIND_BUZZY_BEETLE
@kind:
        stx group_kind
        ldx #GROUP_LOW_Y
        tya
        and #GROUP_HIGH
        beq @y
        ldx #GROUP_HIGH_Y
@y:
        stx group_y
        ldx #GROUP_COUNT
        tya
        and #GROUP_THREE
        beq @count
        inx
@count:
        stx group_count
        a16
        lda screen_right
        sta group_x
        a8
        phd
@member:
        ax16
        ldx #0
@find:
        sep #P_M8
        lda enemy_objects + Object::active,x
        beq @place
        rep #P_M8
        txa
        clc
        adc #OBJECT_PAGE
        tax
        cpx #GROUP_SLOTS * OBJECT_PAGE
        bcc @find
        ax8
        bra @done                       ; no free slot: the rest of the group is lost
.a8
.i16
@place:
        rep #P_M8
        txa
        clc
        adc #enemy_objects
        tcd                             ; D = the member's record
        lda group_x
        sta Object::x_pos
        clc
        adc #GROUP_GAP
        sta group_x
        ax8
        lda group_kind
        sta Object::kind
        lda group_y
        sta Object::y_pos
        lda #Y_HIGH_SCREEN
        sta Object::y_pos+1
        lda #ENEMY_ACTIVE
        sta Object::active
        jsr route_enemy_start
        dec group_count
        bne @member
@done:
        pld
        jmp step_spawn_record

; ---------------------------------------------------------------------------
; run_enemy_slot: the routine of the slot's kind, each frame (05a 22.1).
; Kinds below KIND_BOWSER_FLAME are the ordinary enemies (run_ordinary_enemy,
; 05b); the others have the table below, kinds $15-$35. The original's run
; table ends after kind $35: kind $36 is never active (05a L12).
;
; In:       D = the active slot's record
; Out:      the kind's routine's
; Changes:  the kind's routine's
; Time:     each frame for each active enemy slot
; Original: $C882-$C8D5
; ---------------------------------------------------------------------------
RUN_KINDS_END   = $36           ; one past the last kind of enemy_runs
run_enemy_slot:
.a8
.i8
        lda Object::kind
        cmp #KIND_BOWSER_FLAME
        bcs @table
        jmp run_ordinary_enemy          ; 05b
@table:
        asl a
        tax
        jmp (.loword(enemy_runs - KIND_BOWSER_FLAME * 2),x)
enemy_runs:
        .addr run_bowser_fire           ; $15 (05b)
        .addr animate_fireworks         ; $16 (05b)
        .addr run_nothing               ; $17-$1A: the waves run from take_queued_enemy
        .addr run_nothing
        .addr run_nothing
        .addr run_nothing
        .addr run_fire_bar              ; $1B-$22 (05b)
        .addr run_fire_bar
        .addr run_fire_bar
        .addr run_fire_bar
        .addr run_fire_bar
        .addr run_fire_bar
        .addr run_fire_bar
        .addr run_fire_bar
        .addr run_nothing               ; $23
        .addr run_large_lift            ; $24-$2A (05b)
        .addr run_large_lift
        .addr run_large_lift
        .addr run_large_lift
        .addr run_large_lift
        .addr run_large_lift
        .addr run_large_lift
        .addr run_small_lift            ; $2B, $2C (05b)
        .addr run_small_lift
        .addr bowser_actions            ; $2D (05b)
        .addr run_powerup               ; $2E (objects.s)
        .addr run_vine                  ; $2F (objects.s)
        .addr run_nothing               ; $30: the flag runs in run_flag_object (objects.s)
        .addr run_castle_flag           ; $31 (05b)
        .addr run_jump_spring           ; $32 (objects.s)
        .addr run_nothing               ; $33: the cannon bullet runs in run_cannons (objects.s)
        .addr warp_zone_exit_check      ; $34 (objects.s)
        .addr run_rescued_person        ; $35 (05b)
.assert * - enemy_runs = (RUN_KINDS_END - KIND_BOWSER_FLAME) * 2, error, "enemy_runs: one entry for each kind $15-$35"

; ---------------------------------------------------------------------------
; run_nothing: the routine of the kinds that do nothing in the enemy loop
; (05a 22.2).
;
; Original: $C8D6
; ---------------------------------------------------------------------------
run_nothing:
.a8
.i8
        rts
