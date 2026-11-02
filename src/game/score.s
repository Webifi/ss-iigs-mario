; The score of the game: the score numbers that float up from the enemies,
; the digit arithmetic of the scores, the coins and the game timer, the
; status bar numbers, the top score, the coins and their 1-up, and the game
; timer's tick and its warning.
;
; Where it runs:
;   - the frame (game_frame step 10): top_score_update, each frame, also
;     on the title;
;   - the game core (game_core), in play and in the title's demo:
;     score_numbers right after each enemy number's routine (0-5), and
;     tick_game_timer late in the core, after everything that can add score;
;   - the rules that give points or coins (collision.s, objects.s and enemies.s) call
;     start_score_number, add_score, add_one_coin, add_digit_amounts and
;     refresh_status_number; the status bar setup calls
;     pick_status_nybbles, the title's top score refresh_status_number;
;     setup_entry_and_timer calls reload_game_timer.
;
; Data: the digit store (state.inc digits: one decimal digit 0-9 in each
; byte, the highest first, in the original's relative layout), digit_add
; (the amounts of the six places of a run), the score number
; fields of the enemy records (Object::score_*), the player record's lives
; and coins. Out: the digits, the status number records in screen list 1
; (REC_CELLS, list 1), the score number sprites in
; sprite_list, the sound commands.
;
; In the title mode (mode 0) add_digit_amounts changes no digit: the demo
; plays with the score, the coins and the time standing (add_one_coin still
; counts the coin count and the lives, as the original's).
;
; Registers: A8 I8 at each entry and exit; DBR = bank 0; D = the enemy's
; record for start_score_number and score_numbers, any D for the others.
;
; Original: $849F-$8566 (score_numbers and its tables), $8EF4-$8FBB (the
; status numbers, the digit arithmetic, the top score), $BBF8-$BC48 (the
; coin and score adders), $B74F-$B7A3 (the game timer), $DA11-$DA24
; (start_score_number), and the timer part of setup_entry_and_timer
; ($9178-$9196) as reload_game_timer, split off for the modes part.
; compare_with_top ($8F9E) is the second half of top_score_update; store_sum_digit
; ($8F75) is a step of add_digit_amounts.
;

.a8
.i8

; ---- Values of this part -------------------------------------------------
; The digit store (state.inc digits): the start of each run.
DIGITS_TOP      = $00           ; the top score: 6 digits, millions to tens
DIGIT_PLACES    = 6             ; digit_add: the amounts of a run's six places, the highest first
DIGIT_FIRST_PLACE = 0           ; digit_add's first place: a score's millions
DECIMAL_BASE    = 10
DIGIT_BORROW    = 9             ; a digit whose sum is negative becomes 9
.assert DIGITS_TIME + TIME_DIGITS = DIGITS_SIZE, error, "the time ends the digit store"
; The score numbers.
SCORE_STEPS     = $30           ; a score number's steps (its time)
SCORE_AWARD_STEP = $2B          ; the step whose time is this before the step gives the points: the sixth
SCORE_TOP       = $18           ; a score number rises 1 pixel a step until its Y is below this
SCORE_SPRITE_RISE = 8           ; while it rises its sprites are 8 above its Y
SCORE_STOP_EXTRA = 1            ; and 1 more once it stops: the original's borrow of the compare
SCORE_SPRITE_GAP = 8            ; the right sprite is 8 pixels right of the left one
SCORE_PALETTE   = 2             ; the sprites' attributes: sprite palette 2
SCORE_OWN_SPRITES_STATE = 2     ; a low kind from this state on shows its number in its own sprites
; The coins.
COIN_ONES       = 1             ; add_one_coin: one coin
; The status numbers.
NUMBER_FIELDS   = 6             ; print_number_field: fields 0-5 (values $F, 0-4); 6-15 write nothing
FIELD_ROW       = 0             ; number_fields (scripts/collision_data.py): per field the cell row,
FIELD_COLUMN    = 1             ;   the cell column (ring columns 0-31: name table 0),
FIELD_COUNT     = 2             ;   the digits,
FIELD_FIRST     = 3             ;   the offset of the first digit in the digit store
FIELD_BYTES     = 4
ORIGINAL_RECORD_HEAD = 3        ; the original's record: address high, address low, control, then the tiles
ZERO_SUPPRESS_TILE = $24        ; refresh_status_number: the blank tile that a leading 0 of the score shows
NYBBLE_MASK     = $0F           ; print_number_field: a field's nybble
NYBBLE_NONE     = $0A           ; a nybble of no field
; The game timer.
TIME_TICK_FRAMES = $18          ; TIMER_GAME_TICK: one unit each 24 frames
TIME_WARNING_HUNDREDS = 1       ; the time 100: the hurry song
TIME_MINUS_ONE  = $FF           ; digit_add's amount -1
TIME_START_TENS = 0             ; an area's start time: N, 0, 1 (the first tick shows N00)
TIME_START_ONES = 1
Y_BELOW_SCREEN  = 2             ; Y high of a player below the screen: no tick

; ---- The variables of this part ------------------------------------------
.segment "AREASTATE"
top_check_run:  .res 1          ; compare_with_top: the offset of the score's first digit
number_digits:  .res 1          ; print_number_field: the digits still to copy

.segment "GAMEPLAY"

; ---------------------------------------------------------------------------
; start_score_number: a score number starts at an enemy: its code, 48 steps
; of time, the enemy's Y and the screen X of the enemy group (rel_x +
; REL_ENEMY: the enemy whose routine runs, also when the number is
; another's). A later start for the same enemy replaces an
; earlier one.
;
; In:       A8 I8; A = the score code (SCORE_*); D = the enemy's record
; Out:      its score fields; A = the screen X used by check_enemy_vs_tiles
; Changes:  A
; Keeps:    X, Y, D
; Time:     about 30 cycles
; Original: $DA11-$DA24 (start_score_number)
; ---------------------------------------------------------------------------
start_score_number:
.a8
.i8
        sta Object::score_kind
        lda #SCORE_STEPS
        sta Object::score_timer
        lda Object::y_pos
        sta Object::score_y
        lda rel_x+REL_ENEMY
        sta Object::score_x
        rts

; ---------------------------------------------------------------------------
; score_numbers: one step of an enemy's score number, right after the
; enemy's routine (so a number started by an enemy for its own or a higher
; enemy number takes its first step in the same frame). A code above the
; 1-up becomes the 1-up. At time 0 the number ends. Else the time counts
; down; at the sixth step the 1-up gives a life (with its sound) and every
; code its points (score_award_places/amounts: a digit place and an amount;
; the 1-up adds 0 and still prints the score). The number rises 1 pixel a
; step until its Y is below $18; its two sprites (the enemy's own first two
; for a spiny, a piranha plant, the grey and red cheep-cheeps and a low kind
; in state 2 or more, else the block object's of sprite_offset_select) show
; the code's two tiles in palette 2, 8 above the Y while it rises and 9 once
; it stops.
;
; In:       A8 I8; D = the enemy's record
; Out:      its score fields; the lives, the score; two sprite entries
; Changes:  A, X, Y
; Keeps:    D
; Time:     each frame for each enemy: under 20 cycles without a number,
;           about 120 with one, and the score print at its sixth step
; Original: $84C3-$8566 (score_numbers)
; ---------------------------------------------------------------------------
score_numbers:
.a8
.i8
        lda Object::score_kind
        beq @done
        cmp #SCORE_1UP + 1
        bcc @time
        lda #SCORE_1UP
        sta Object::score_kind
@time:  lda Object::score_timer
        bne @step
        stz Object::score_kind          ; its time ran out
@done:  rts
@step:  dec Object::score_timer
        cmp #SCORE_AWARD_STEP
        bne @sprites
; The sixth step: the 1-up's life, then the points.
        ldx Object::score_kind
        cpx #SCORE_1UP
        bne @points
        inc player_record+PlayerRecord::lives ; no limit: a signed byte
        lda #SQUARE2_EXTRA_LIFE
        sta snd_square2_queue
@points:
        ldy score_award_places,x
        lda score_award_amounts,x
        sta digit_add,y
        jsr add_score
; The two sprites.
@sprites:
        lda Object::kind
        cmp #KIND_SPINY
        beq @own
        cmp #KIND_PIRANHA
        beq @own
        cmp #KIND_HAMMER_BRO
        beq @block
        cmp #KIND_GREY_CHEEP
        beq @own
        cmp #KIND_RED_CHEEP
        beq @own
        cmp #KIND_TALL
        bcs @block
        lda Object::state
        cmp #SCORE_OWN_SPRITES_STATE
        bcs @own
@block: ldx sprite_offset_select
        ldy sprite_offset+SPR_BLOCK,x
        bra @rise
@own:   ldx Object::slot
        ldy sprite_offset+SPR_ENEMY-SLOT_ENEMY,x
; The rise, and the sprites' Y.
@rise:  lda Object::score_y
        cmp #SCORE_TOP
        bcc @stopped
        dec a
        sta Object::score_y
        sec
        sbc #SCORE_SPRITE_RISE
        bra @place
@stopped:
        sec
        sbc #SCORE_SPRITE_RISE + SCORE_STOP_EXTRA
@place: sta sprite_list+SPRITE_Y,y
        sta sprite_list+SPRITE_ENTRY+SPRITE_Y,y
        lda Object::score_x
        sta sprite_list+SPRITE_X,y
        clc
        adc #SCORE_SPRITE_GAP
        sta sprite_list+SPRITE_ENTRY+SPRITE_X,y
        lda #SCORE_PALETTE
        sta sprite_list+SPRITE_ATTR,y
        sta sprite_list+SPRITE_ENTRY+SPRITE_ATTR,y
        lda Object::score_kind
        asl a
        tax
        lda score_number_tiles,x
        sta sprite_list+SPRITE_TILE,y
        lda score_number_tiles+1,x
        sta sprite_list+SPRITE_ENTRY+SPRITE_TILE,y
        rts

; ---------------------------------------------------------------------------
; add_digit_amounts: the six amounts of digit_add into the run of six digits
; that ends at Y, from the last place up. A negative sum makes the digit 9
; and borrows 1 from the next place; a sum of 10 or more takes 10 off and
; carries 1. A carry or borrow out of the run's first place is lost: a score
; wraps from 9,999,990 to 0, and the coins carry into digits that nothing
; shows. In the title mode the digits stay. digit_add
; becomes 0 in both cases.
;
; In:       A8 I8; Y = the offset of the run's last digit in digits; digit_add
; Out:      the digits; digit_add = 0
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 150 cycles
; Original: $8F5F-$8F96 (add_digit_amounts, store_sum_digit $8F75)
; ---------------------------------------------------------------------------
add_digit_amounts:
.a8
.i8
        lda mode
        beq @clear                      ; MODE_TITLE: the digits stand
        ldx #DIGIT_PLACES - 1
@place: lda digit_add,x
        clc
        adc digits,y
        bmi @borrow
        cmp #DECIMAL_BASE
        bcs @carry
@store: sta digits,y
        dey
        dex
        bpl @place
@clear: a16
        stz digit_add
        stz digit_add+2
        stz digit_add+4
        a8
        rts
@borrow:
        cpx #DIGIT_FIRST_PLACE
        beq @nine                       ; out of the first place: lost
        dec digit_add-1,x
@nine:  lda #DIGIT_BORROW
        bra @store
@carry: sbc #DECIMAL_BASE               ; the carry is set
        cpx #DIGIT_FIRST_PLACE
        beq @store                      ; out of the first place: lost
        inc digit_add-1,x
        bra @store
.assert MODE_TITLE = 0, error, "add_digit_amounts: the title mode is 0"
.assert DIGIT_PLACES = 6, error, "add_digit_amounts: three words clear digit_add"

; ---------------------------------------------------------------------------
; add_one_coin: one coin for the player on the screen: 1 into the coin
; digits, the coin count + 1, and at 100 the count starts at 0 again with a
; life and the extra-life sound (it replaces the coin sound of the frame);
; then 200 points (add_score). The count and the life change in the title
; mode too.
;
; In:       A8 I8; any D
; Out:      the coin digits, player_record coins and lives, the score
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 1,300 cycles (two digit runs and the print)
; Original: $BBFE-$BC26 (add_one_coin)
; ---------------------------------------------------------------------------
add_one_coin:
.a8
.i8
        lda #COIN_ONES
        sta digit_add+DIGIT_TENS
        ldx player
        ldy coin_digit_places,x
        jsr add_digit_amounts
        inc player_record+PlayerRecord::coins
        lda player_record+PlayerRecord::coins
        cmp #COINS_FOR_LIFE
        bne @points
        stz player_record+PlayerRecord::coins
        inc player_record+PlayerRecord::lives ; no limit: a signed byte
        lda #SQUARE2_EXTRA_LIFE
        sta snd_square2_queue
@points:
        lda #COIN_POINTS
        sta digit_add+DIGIT_HUNDREDS
        ; falls into add_score

; ---------------------------------------------------------------------------
; add_score: digit_add into the score of the player on the screen, then
; pick_status_nybbles. pick_status_nybbles: the print of that player's coins
; and score (status_nybbles_by_player). refresh_status_number: the print of
; the fields of the two nybbles in A (print_coins_and_score); then the
; first digit of the last field printed shows blank when it is 0. Every
; caller prints a six-digit field last (a score, or the top score on the
; title), so that is its millions digit.
;
; In:       A8 I8; digit_add (add_score); A = two nybbles
;           (refresh_status_number); any D
; Out:      the score digits, the records in screen list 1
; Changes:  A, X, Y
; Keeps:    D
; Time:     about 1,000 cycles (the run and two records)
; Original: $BC27-$BC2F (add_score), $BC30-$BC35 (pick_status_nybbles),
;           $BC36-$BC48 (refresh_status_number)
; ---------------------------------------------------------------------------
add_score:
.a8
.i8
        ldx player
        ldy score_digit_places,x
        jsr add_digit_amounts
pick_status_nybbles:
.a8
.i8
        ldy player
        lda status_nybbles_by_player,y
refresh_status_number:
.a8
.i8
        jsr print_coins_and_score
        ldx screen_list_1_end
        lda screen_list_1-SCORE_DIGITS,x ; the first tile of the last record
        bne @done
        lda #ZERO_SUPPRESS_TILE
        sta screen_list_1-SCORE_DIGITS,x
@done:  rts

; ---------------------------------------------------------------------------
; print_coins_and_score: the status numbers of two fields: the low nybble's
; field first, then the high nybble's. print_number_field: the field of one
; nybble n, (n + 1) AND 15: 0 the top score, 1-2 the players' scores, 3-4
; their coins, 5 the time; 6-15 write nothing. Its record goes to the end of
; screen list 1: REC_CELLS at the field's cell row and column (number_fields,
; name table 0), the digits as their tiles (tile n shows the digit n), and
; the list's end byte after it. screen_list_1_original_end grows by the
; record's length in the original's format, for the room rules.
;
; In:       A8 I8; A = two nybbles (print_coins_and_score), one nybble in
;           the low bits (print_number_field); the digits
; Out:      screen_list_1, screen_list_1_end, screen_list_1_original_end
; Changes:  A, X, Y, number_digits
; Keeps:    D
; Time:     about 150 cycles for a six-digit field
; Original: $8F06-$8F10 (print_coins_and_score), $8F11-$8F5E
;           (print_number_field)
; ---------------------------------------------------------------------------
print_coins_and_score:
.a8
.i8
        pha
        jsr print_number_field
        pla
        lsr a
        lsr a
        lsr a
        lsr a
print_number_field:
.a8
.i8
        inc a
        and #NYBBLE_MASK
        cmp #NUMBER_FIELDS
        bcs @done
        asl a
        asl a
        tay                             ; the field's entry of number_fields
        ldx screen_list_1_end
        lda #REC_CELLS
        sta screen_list_1,x
        lda number_fields+FIELD_ROW,y
        sta screen_list_1+1,x
        lda number_fields+FIELD_COLUMN,y
        sta screen_list_1+2,x
        lda number_fields+FIELD_COUNT,y
        sta screen_list_1+3,x
        sta number_digits
        clc
        adc #ORIGINAL_RECORD_HEAD
        adc screen_list_1_original_end
        sta screen_list_1_original_end
        lda number_fields+FIELD_FIRST,y
        tay
@digit: lda digits,y
        sta screen_list_1+REC_CELLS_HEAD,x
        inx
        iny
        dec number_digits
        bne @digit
        lda #REC_END
        sta screen_list_1+REC_CELLS_HEAD,x
        txa
        clc
        adc #REC_CELLS_HEAD
        sta screen_list_1_end
@done:  rts
.assert FIELD_BYTES = 4, error, "print_number_field: a field's entry is two shifts"
.assert REC_CELLS_HEAD = 4, error, "print_number_field: kind, row, column, count"

; ---------------------------------------------------------------------------
; top_score_update: player 1's score, then player 2's, against the top
; score, each frame: a score equal to or above the top score replaces it.
; compare_with_top: one score. The digits compare from the
; first: at the first that differs a higher score digit copies the six
; digits; equal scores need no copy (the copy would change nothing).
;
; In:       A8 I8; any D; compare_with_top: X = the offset of the score's
;           first digit
; Out:      the top score's digits
; Changes:  A, X, Y, top_check_run
; Keeps:    D
; Time:     each frame, under 200 cycles
; Original: $8F97-$8F9D (top_score_update), $8F9E-$8FBB (compare_with_top)
; ---------------------------------------------------------------------------
top_score_update:
.a8
.i8
        ldx #DIGITS_SCORE_1
        jsr compare_with_top
        ldx #DIGITS_SCORE_2
compare_with_top:
.a8
.i8
        stx top_check_run
        ldy #DIGITS_TOP
@digit: lda digits,x
        cmp digits,y
        bne @differ
        inx
        iny
        cpy #DIGITS_TOP + SCORE_DIGITS
        bcc @digit
        rts                             ; equal
@differ:
        bcc @done                       ; lower
        ldx top_check_run
        a16
        lda digits,x                    ; the six digits, as three words
        sta digits+DIGITS_TOP
        lda digits+2,x
        sta digits+DIGITS_TOP+2
        lda digits+4,x
        sta digits+DIGITS_TOP+4
        a8
@done:  rts
.assert SCORE_DIGITS = 6, error, "compare_with_top: three words copy a score"

; ---------------------------------------------------------------------------
; tick_game_timer: the game timer, late in the game core. Not in the title
; mode, in the player tasks below the control task or in the death task,
; for a player below the screen, or while the tick timer runs (it counts
; only while the frame timers step). At 000 the player dies (power 0, then
; force_player_hurt) and the time-up flag counts (the mode shows TIME UP). At 100
; the hurry song starts (it plays as the time goes to 099). Else the time
; loses one unit and its field is printed; the next unit comes 24 frames
; later.
;
; In:       A8 I8; any D
; Out:      the time digits, the tick timer, the print; or the death
; Changes:  A, X, Y
; Keeps:    D
; Time:     each frame: under 40 cycles; about 400 at a tick
; Original: $B74F-$B7A3 (tick_game_timer)
; ---------------------------------------------------------------------------
tick_game_timer:
.a8
.i8
        lda mode
        beq @done                       ; the title and its demo
        lda player_task
        cmp #PLAYER_TASK_CONTROL
        bcc @done
        cmp #PLAYER_TASK_DEATH
        beq @done
        lda player_object+Object::y_pos+1
        cmp #Y_BELOW_SCREEN
        bcs @done
        lda timers+TIMER_GAME_TICK
        bne @done
        lda digits+DIGITS_TIME
        ora digits+DIGITS_TIME+1
        ora digits+DIGITS_TIME+2
        beq @time_up
        lda digits+DIGITS_TIME
        cmp #TIME_WARNING_HUNDREDS
        bne @tick
        lda digits+DIGITS_TIME+1
        ora digits+DIGITS_TIME+2
        bne @tick
        lda #EVENT_TIME_RUNNING_OUT
        sta snd_event_queue
@tick:  lda #TIME_TICK_FRAMES
        sta timers+TIMER_GAME_TICK
        lda #TIME_MINUS_ONE
        sta digit_add+DIGIT_TENS
        ldy #DIGITS_TIME + TIME_DIGITS - 1
        jsr add_digit_amounts
        lda #(NYBBLE_NONE << 4) | NYBBLE_TIME
        jmp print_coins_and_score
@time_up:
        stz player_power                ; small: the hurt is the death
        jsr force_player_hurt
        inc time_up
@done:  rts

; ---------------------------------------------------------------------------
; reload_game_timer: the time at an area's start (the timer part of
; setup_entry_and_timer): when the area has a time (timer_setting not 0)
; and the time is due (timer_reload not 0): N01 with N =
; timer_hundreds_by_setting[setting] (400, 300, 200; the first tick shows
; N00), and timer_reload clears. Else the digits stay: an area entered by a
; pipe keeps the time, and with no time the reload waits for the next area
; with one. The original also clears the star timer here; the area start
; has cleared every timer before (begin_area), so that store is left out.
;
; In:       A8 I8; any D; timer_setting, timer_reload
; Out:      the time digits, timer_reload
; Changes:  A, Y
; Keeps:    X, D
; Time:     about 40 cycles
; Original: $9178-$9196 (in setup_entry_and_timer)
; ---------------------------------------------------------------------------
reload_game_timer:
.a8
.i8
        ldy timer_setting
        beq @done
        lda timer_reload
        beq @done
        lda timer_hundreds_by_setting,y
        sta digits+DIGITS_TIME
        lda #TIME_START_TENS
        sta digits+DIGITS_TIME+1
        lda #TIME_START_ONES
        sta digits+DIGITS_TIME+2
        stz timer_reload
@done:  rts
