; The frame of the game: the power-on of the original and its frame
; interrupt, which runs all of the game once each frame.
;
; The IIgs main loop (src/game.s) calls game_power_on once at the start and
; game_frame once for each frame of the DOC clock (src/clock.s): 4 ticks for
; each picture of the card's mode, so the game runs at the picture rate of
; the monitor (about 59.94 Hz on VGA, 60.05 Hz on AppleColor RGB). The
; original runs its frame from the picture chip's vertical blank interrupt.
; The port sends that picture work as a packet to the card (src/packet.s).
; The clock counts frames due; if the game falls behind it catches up, subject
; to the eight-bit count and the menu reset described in src/game.s.
;
; Register widths: A8 I8 at each entry and exit unless a header says
; otherwise. DBR = bank 0 (the game's variables). D = the player's record
; outside the object code (state.inc).

.a8
.i8

; Values of the frame.
RANDOM_SEED     = $A5           ; the first random byte at every start
RANDOM_TAP      = $02           ; the bit of random bytes 0 and 1 whose XOR enters the bits
PAUSE_ON        = $01           ; pause: bit 0, the game is paused
PAUSE_HELD      = $80           ; pause: bit 7, a start press was taken
PAUSE_WAIT      = $2B           ; frames before start works again
PAD_EDGE_BUTTONS = PAD_SELECT | PAD_START ; buttons that count only in the frame they go down
SHUFFLE_RING_START = $28        ; sprite_offset from this on is in the shuffle ring of sprites 10-63
SHUFFLE_FIRST_GROUPS = 15       ; sprite_offset entries 0-14 take the shuffle
SHUFFLE_STEPS   = 3             ; shuffle_step runs 0-2
MISC_SETS       = 3             ; the misc entries copy enemy entries 5, 6 and 7
MISC_SPRITE_STEP = 8            ; each copy is 2 sprites (8 bytes) after the one before
SPRITE_ZERO_BYTES = SPRITE_ENTRY ; hide_sprites starts after sprite 0

.segment "GAMEPLAY"

; ---------------------------------------------------------------------------
; game_power_on: the original's power-on. The IIgs startup
; (src/game.s) has cleared all of the game's state before, so every start is
; the original's cold start: the IIgs has no reset into a running game, and
; the warm start's kept top score does not occur.
;
; In:       any widths (the startup has X at 16 bits); DBR = 0; the state
;           cleared
; Out:      A8 I8; mode = MODE_TITLE, mode_task = 0; the picture off; the
;           records' slot numbers; warm_boot and the first random byte set
; Changes:  A, X, Y, D (the player's record)
; Time:     once
; Original: $8000-$8056 (game_power_on)
; ---------------------------------------------------------------------------
game_power_on:
        sep #P_M8 | P_X8
.a8
.i8
        phd
; Each record knows its slot (state.inc Object::slot).
        ldx #OBJECT_SLOTS - 1
@slot:
        object_from_x
        stx Object::slot
        dex
        bpl @slot
        pea player_object
        pld
; The original's steps 7-14: the title mode, the start marks, the sound
; unit's channels, the picture off, no sprite, blank name tables.
        lda #MODE_TITLE
        sta mode
        lda #WARM_BOOT
        sta warm_boot
        lda #RANDOM_SEED
        sta random                      ; the other six random bytes are 0
        jsl sound_power_on              ; src/game/sound_program.s: sample level 0, the four channels on
        jsr hide_all_sprites
        jsr clear_name_tables
        inc screen_off                  ; the picture stays off
        pld
        rtl

; ---------------------------------------------------------------------------
; game_frame: one frame of the original, steps 1-15.
;
; In:       A8 I8; DBR = 0; any D
; Out:      A8 I8; D as it was
; Changes:  A, X, Y
; Time:     each frame
; Original: $8082-$8181 (the frame interrupt)
; ---------------------------------------------------------------------------
; The steps of game_frame, in the original's order:
;   1-6   the picture: the packet with the sprite list, the screen records
;         of the frame's source and the scroll, all as the logic of the
;         frame before left them (packet_frame)
;   7     the sound program (sound_frame)
;   8     the pads (read_pads)
;   9     the pause (pause_check)
;   10    the top score (top_score_update)
;   11    the timers and frame_count, when not paused (step_timers)
;   12    one step of the random bits, also when paused (step_random)
;   13    with the status split, when not paused: hide_sprites and
;         sprite_shuffle (the original also waits for the sprite 0 hit
;         here: the card keeps the status rows in place itself)
;   14    the scroll: in the packet of step 1-6
;   15    when not paused: the game logic of the mode (mode_dispatch)
;

game_frame:
.a8
.i8
        phd
        pea player_object
        pld
        jsl packet_frame                ; steps 1-6 and 14: src/packet.s
        jsl sound_frame                 ; step 7: src/game/sound_program.s
        jsr read_pads                   ; step 8
        jsr pause_check                 ; step 9
        jsr top_score_update            ; step 10: src/game/score.s
        lda pause
        lsr a
        bcs @paused                     ; bit 0: paused
        jsr step_timers                 ; step 11
        jsr step_random                 ; step 12
; Step 13: with the status split, the sprites of the frame start hidden and
; the objects' first sprites move on in the ring.
        lda status_split
        beq @logic
        jsr hide_sprites
        jsr sprite_shuffle
@logic:
        jsr mode_dispatch               ; step 15
        pld
        rtl
@paused:
        jsr step_random                 ; step 12 runs also while paused
        pld
        rtl

; ---------------------------------------------------------------------------
; read_pads: the pads of the frame. The input (src/input.s)
; gives the held buttons of both pads in the original's bit order
; (input_pads); start and select count only in the frame they go down:
; while either stays down from a frame in which it counted, both are
; cleared.
;
; In:       input_pads (bank 2: player 1, then player 2), pad_held
; Out:      pad_bits (player 1, player 2), pad_held
; Changes:  A, X
; Time:     each frame, about 60 cycles
; Original: $8E5C-$8E91 (read_pads)
; ---------------------------------------------------------------------------
read_pads:
.a8
.i8
        ldx #1                          ; pad 2, then pad 1
@pad:
        lda f:input_pads,x
        sta pad_bits,x
        and #PAD_EDGE_BUTTONS
        and pad_held,x
        beq @record
        lda pad_bits,x                  ; an edge button stays down: both edges off,
        and #<~PAD_EDGE_BUTTONS         ; pad_held as it is
        sta pad_bits,x
        bra @next
@record:
        lda pad_bits,x
        sta pad_held,x
@next:
        dex
        bpl @pad
        rts

; ---------------------------------------------------------------------------
; pause_check: start on pad 1 pauses or resumes the game, in the victory
; mode or in the game core of the play mode. The pause takes
; effect in the same frame.
;
; In:       mode, mode_task, pad_bits (pad 1), pause, pause_timer
; Out:      pause, pause_timer, snd_pause_queue (1 pause, 2 resume)
; Changes:  A
; Time:     each frame, under 40 cycles
; Original: $8182-$81C5 (pause_check)
; ---------------------------------------------------------------------------
pause_check:
.a8
.i8
        lda mode
        cmp #MODE_VICTORY
        beq @counts
        cmp #MODE_GAME
        bne @done
        lda mode_task
        cmp #PLAY_TASK_CORE
        bne @done
@counts:
        lda pause_timer
        beq @start
        dec pause_timer
        rts
@start:
        lda pad_bits                    ; pad 1
        and #PAD_START
        bne @pressed
        lda #PAUSE_HELD
        trb pause                       ; start is up: the next press counts
        rts
@pressed:
        bit pause
        bmi @done                       ; this press was taken already
        lda #PAUSE_WAIT
        sta pause_timer
        lda pause
        inc a                           ; 1 when the game pauses, 2 when it resumes
        sta snd_pause_queue
        lda pause
        eor #PAUSE_ON
        ora #PAUSE_HELD
        sta pause
@done:
        rts

; ---------------------------------------------------------------------------
; step_timers: the timers and frame_count. timer_hold = n
; stops the timers and the interval counter for n - 1 frames. The frame
; timers count each frame, the slow timers when interval_count runs below 0
; (each 21 frames); a timer stays at 0. frame_count counts on while the
; timers hold.
;
; In:       timer_hold, interval_count, timers
; Out:      the same, and frame_count + 1
; Changes:  A, X
; Time:     each frame not paused: about 400 cycles when the slow timers
;           count, about 250 when they do not
; Original: $80F0-$811A
; ---------------------------------------------------------------------------
step_timers:
.a8
.i8
        lda timer_hold
        beq @count
        dec timer_hold
        bne @frame                      ; the timers hold this frame
@count:
        ldx #FRAME_TIMERS               ; the frame timers only
        dec interval_count
        bpl @timers
        lda #INTERVAL_FRAMES
        sta interval_count
        ldx #ALL_TIMERS                 ; the slow timers count too
@timers:
        lda timers,x
        beq @next
        dec timers,x
@next:
        dex
        bpl @timers
@frame:
        inc frame_count
        rts

; ---------------------------------------------------------------------------
; step_random: one step of the random bits: the seven bytes
; are one 56-bit register with random+0 at its top; it shifts right by one
; bit, and bit 1 of byte 0 XOR bit 1 of byte 1 enters at the top. The bytes
; are rotated one by one: the register's bit order runs from byte 0 down to
; byte 6, the reverse of a 16-bit word's byte order.
;
; In:       random
; Out:      random
; Changes:  A, the flags
; Time:     each frame, 60 cycles
; Original: $811B-$8137
; ---------------------------------------------------------------------------
step_random:
.a8
.i8
        lda random
        eor random+1
        and #RANDOM_TAP
        cmp #RANDOM_TAP                 ; carry = the XOR of the two bits
        .repeat RANDOM_BYTES, I
        ror random+I
        .endrepeat
        rts

; ---------------------------------------------------------------------------
; hide_all_sprites, hide_sprites: every sprite of the list, or every sprite
; but sprite 0 (the status split's marker), below the picture. hide_all_sprites runs only while status_split is 0.
;
; In:       nothing
; Out:      the Y byte of the sprites = HIDDEN_Y
; Changes:  A, X
; Time:     about 1,000 cycles (hide_all_sprites, 64 sprites)
; Original: $8220 (hide_all_sprites), $8223-$8230 (hide_sprites)
; ---------------------------------------------------------------------------
hide_all_sprites:
.a8
.i8
        ldx #0
        bra hide_from_x
hide_sprites:
.a8
.i8
        ldx #SPRITE_ZERO_BYTES
hide_from_x:
        lda #HIDDEN_Y
@sprite:
        sta sprite_list+SPRITE_Y,x
        inx
        inx
        inx
        inx
        bne @sprite                     ; 64 entries of 4 bytes: X wraps to 0 at the end
        rts
.assert SPRITE_LIMIT * SPRITE_ENTRY = 256, error, "hide_from_x ends when X wraps"

; ---------------------------------------------------------------------------
; sprite_shuffle: the objects' first sprites take turns at the front of the
; sprite list. Each of sprite_offset's entries 0-14 that is
; in the ring of sprites 10-63 (SHUFFLE_RING_START on) moves on by the
; step's amount; a sum past $FF adds SHUFFLE_RING_START more, so the offsets
; stay in the ring. The three amounts add up to the ring's size, so the
; offsets come back every three frames. The misc entries 15-23 follow
; entries 5, 6 and 7: each one and the two sets of 2 sprites after it.
;
; In:       sprite_offset, shuffle_step, shuffle_amounts
; Out:      sprite_offset, shuffle_step
; Changes:  A, X, Y
; Time:     each frame with the split, not paused: about 350 cycles
; Original: $81C6-$8211 (sprite_shuffle); the original's unused load of
;           area_type is not kept
; ---------------------------------------------------------------------------
sprite_shuffle:
.a8
.i8
        ldy shuffle_step
        ldx #SHUFFLE_FIRST_GROUPS - 1
@entry:
        lda sprite_offset,x
        cmp #SHUFFLE_RING_START
        bcc @next                       ; below the ring: the entry stays
        clc
        adc shuffle_amounts,y
        bcc @store
        adc #SHUFFLE_RING_START - 1     ; past $FF: past the sprites below the ring (the carry adds the 1)
@store:
        sta sprite_offset,x
@next:
        dex
        bpl @entry
        iny
        cpy #SHUFFLE_STEPS
        bcc @step
        ldy #0
@step:
        sty shuffle_step
; The misc entries: three sets of three, from entries 5, 6 and 7.
        ldx #0
        ldy #SPR_ENEMY + 4              ; entry 5
@set:
        lda sprite_offset,y
        sta sprite_offset+SPR_MISC,x
        clc
        adc #MISC_SPRITE_STEP
        sta sprite_offset+SPR_MISC+1,x
        adc #MISC_SPRITE_STEP           ; no set passes $FF
        sta sprite_offset+SPR_MISC+2,x
        inx
        inx
        inx
        iny
        cpx #MISC_SETS * 3
        bcc @set
        rts

; ---------------------------------------------------------------------------
; mode_dispatch: the routine of the mode. The original's
; jump routine leaves registers that no mode routine reads,
; so the port's JMP leaves none on purpose.
;
; In:       mode (MODE_*)
; Out:      the mode routine's
; Changes:  the mode routine's
; Original: $8212-$821F (mode_dispatch)
; ---------------------------------------------------------------------------
mode_dispatch:
.a8
.i8
        lda mode
        asl a
        tax
        jmp (.loword(mode_routines),x) ; the table is in this bank (bank 1): ld65 wants its 16-bit address
mode_routines:
        .addr title_mode                ; MODE_TITLE: src/game/title.s
        .addr play_mode                 ; MODE_GAME: src/game/flow.s
        .addr victory_mode              ; MODE_VICTORY: src/game/flow.s
        .addr game_over_mode            ; MODE_GAME_OVER: src/game/flow.s
.assert MODE_TITLE = 0 && MODE_GAME = 1 && MODE_VICTORY = 2 && MODE_GAME_OVER = 3, error, "mode_routines order"

; ---------------------------------------------------------------------------
; clear_name_tables: both name tables blank (every cell BLANK_TILE, every
; palette 0), list 1 empty, the scroll at 0. The original
; writes the picture chip at once, with the picture off; the port queues
; the clear among the screen records (src/packet.s packet_clear).
;
; In:       nothing
; Out:      screen_list_1_end and screen_list_1_original_end = 0; picture_scroll = 0
; Changes:  A
; Time:     about 100 cycles (the card clears its ring)
; Original: $8E19-$8E5B (clear_name_tables)
; ---------------------------------------------------------------------------
clear_name_tables:
.a8
.i8
        lda #BLANK_TILE
        jsl packet_clear                ; src/packet.s
        stz screen_list_1_end
        stz screen_list_1_original_end
        stz picture_scroll
        stz picture_scroll+1
        rts
