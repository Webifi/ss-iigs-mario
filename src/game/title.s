; The title mode: its four tasks, the title menu, the start of a game, the
; world select and the title's demo.
;
; Place in the game. mode_dispatch (src/game/frame.s) runs title_mode in
; each frame while mode is MODE_TITLE. Its tasks set up a whole game state
; on the title (init_game, the screen tasks, game_setup: src/game/flow.s,
; screen.s), so that from the title's 26th frame title_menu runs one frame
; of play each frame (game_core): the player stands at the start of world 1
; area 1, or the demo moves him. A start press ends the title in that frame:
; the play mode's task 0 runs in the next.
;
; What comes in: the pads of both players (pad_bits: start and select only
; in the frame they go down, read_pads in the frame before the logic), the
; slow timer demo_timer and the frame timer select_timer (counted by the
; frame before the logic, so the frame in which demo_timer reaches 0 is the
; first frame of the demo), the demo's steps (demo_steps,
; scripts/screen_data.py). What goes out: pad 1's bits for game_core, mode
; and mode_task, the players' records (the world of a world select or a
; continue), the menu's screen records (screen.s draw_mushroom_icon and
; draw_world_digit), and the start of a game.
;
; Original routines: $8231-$838A.

; ---- Values of the original program ----------------------------
SELECT_REPEAT_FRAMES = $10      ; select_timer: 16 frames between two select or B presses that count
WORLD_SELECT_MASK = 7           ; the world select's ring: worlds 0-7
PLAYERS_TOGGLE  = 1             ; two_players XOR this: 1 <-> 2 players
MENU_SELECT     = 0             ; title_menu: the press is select
MENU_WORLD      = 1             ;   the press is B with the world select on
; The digit store.
DIGITS_PLAYERS_SIZE = $18       ; both scores and both coin runs ($07DD-$07F4 of the original)

; The demo's steps (demo_steps, scripts/screen_data.py): two bytes a step.
DEMO_STEP_FRAMES = 0            ; the frames of the step; 0 ends the demo
DEMO_STEP_PADS  = 1             ; pad 1's bits during the step
DEMO_STEP_SIZE  = 2

; ---- State ----------------------------------------------------------------
.segment "AREASTATE"
; The demo's place: demo_pad writes and reads them; each area start (the
; title's task 0 too) clears them, so each demo starts at its first step.
demo_step:      .res 1          ; the steps begun, 0-22 (the original's count: step k uses entry k - 1)
demo_step_timer: .res 1         ; the frames left of the step
.segment "GAMEPLAY"

.a8
.i8

; ---------------------------------------------------------------------------
; title_mode: run the task of the title mode.
;
;   | mode_task | Routine                   | Next                          |
;   |-----------|---------------------------|-------------------------------|
;   | 0         | init_game (flow.s)        | 1 (begin_area moves it on)    |
;   | 1         | screen_routines (screen.s)| 2 at screen task 14           |
;   | 2         | game_setup (flow.s)       | 3 (finish_area_setup)         |
;   | 3         | title_menu                | the game, or task 0 again     |
;
; In:       mode_task (0-3); D = the player's record (the frame's)
; Out:      the task's
; Changes:  A, X, Y, D, the flags
; Time:     12 cycles, then the task
; Original: $8231-$823E
; ---------------------------------------------------------------------------
title_mode:
.a8
.i8
        lda mode_task
        asl a                           ; a word for each task
        tax
        jmp (.loword(title_tasks),x)             ; the task's RTS returns to mode_dispatch's caller
title_tasks:
        .addr init_game, screen_routines, game_setup, title_menu

; ---------------------------------------------------------------------------
; title_menu: title task 3, each frame. Start or A + start
; begins a game; select switches 1 and 2 players; B selects the next world
; after world 8 is won; in the demo, select or start ends the demo. Then
; one frame of play: pad 1 empty on the menu, the demo's bits in the demo.
; null_pad: pad 1 empty, then run_demo. run_demo: one frame of play; when
; the player loses a life (the demo), the title starts again.
; reset_title: the title mode from its task 0 in the next frame, with the
; picture off and no status split.
;
; Why the menu runs the game: only pad 1's byte moves the player in
; game_core (player is 0 on the title), so on the menu the
; player stands; pad 2 counts only for the menu's own tests.
;
; In:       pad_bits (both pads), demo_timer, select_timer, world_select_on,
;           two_players; D = the player's record
; Out:      see above
; Changes:  A, X, Y, D, the flags; what game_core changes
; Time:     about 50 cycles, then game_core
; Original: $8245-$82D7 (null_pad $82BB, run_demo $82C0, reset_title $82C9)
; ---------------------------------------------------------------------------
; The menu and the demo:
;
;   | State | Condition       | Event of a frame              | Next          |
;   |-------|-----------------|-------------------------------|---------------|
;   | Menu  | demo_timer > 0  | start, or A + start, alone    | the game      |
;   | Menu  |                 | select alone (1 in 16 frames) | Menu: 1 <-> 2 |
;   |       |                 |                               | players       |
;   | Menu  |                 | B alone, world select on      | Menu: the     |
;   |       |                 | (1 in 16 frames)              | next world    |
;   | Menu  |                 | demo_timer reaches 0          | Demo          |
;   | Demo  | demo_timer = 0  | start, A + start, select      | title task 0  |
;   | Demo  |                 | the demo's steps end          | title task 0  |
;   | Demo  |                 | the player loses a life       | title task 0  |
;
; "Alone" compares the OR of both pads whole: a start with any other button
; held on either pad is no start. Each select press, and each B press with
; the world select on, sets the demo back to its full wait, also when
; select_timer makes the menu skip the press.
;

title_menu:
.a8
.i8
        ldy #MENU_SELECT
        lda pad_bits
        ora pad_bits + 1                ; either pad
        cmp #PAD_START
        beq start_game
        cmp #PAD_A | PAD_START
        beq start_game                  ; A held: the continue
        cmp #PAD_SELECT
        beq @press
        ldx timers + TIMER_DEMO
        beq @demo
        ldx world_select_on
        beq null_pad                    ; no world select before world 8 is won
        cmp #PAD_B
        bne null_pad
        ldy #MENU_WORLD
; Select, or B with the world select: the demo waits again; a press within
; select_timer's 16 frames of the last one that counted does nothing more.
@press: ldx timers + TIMER_DEMO
        beq reset_title                 ; select in the demo ends it
        ldx #DEMO_WAIT_STEPS
        stx timers + TIMER_DEMO
        ldx timers + TIMER_SELECT
        bne null_pad
        ldx #SELECT_REPEAT_FRAMES
        stx timers + TIMER_SELECT
        cpy #MENU_WORLD
        beq @world
        lda two_players
        eor #PLAYERS_TOGGLE
        sta two_players
        jsr draw_mushroom_icon          ; screen.s: the marker at the other line
        bra null_pad
@world: jsr step_world_select
        bra null_pad
; The demo: pad 1 from the demo's steps. The original stores the pads' OR
; into select_timer here; no frame of the demo reads it, and the
; title's next start clears it.
@demo:  sta timers + TIMER_SELECT
        jsr demo_pad
        bcs reset_title                 ; the steps ended: no frame of play in this frame
        bra run_demo
; Original address: $82BB.
null_pad:
        stz pad_bits                    ; pad 1: no button; pad 2's byte is never read here
; Original address: $82C0.
run_demo:
        jsr game_core                   ; flow.s: one frame of play
        lda player_task
        cmp #PLAYER_TASK_LOSE_LIFE
        beq reset_title                 ; the demo's player lost a life
        rts
; Original address: $82C9.
reset_title:
        stz mode                        ; MODE_TITLE
        stz mode_task                   ; init_game in the next frame
        stz status_split
        inc screen_off                  ; the picture off from the next frame
        rts
.assert MODE_TITLE = 0, error, "reset_title stores 0 as MODE_TITLE"

; ---------------------------------------------------------------------------
; start_game: start alone, or A and start alone: a game begins. In the demo
; the press returns to the title instead (a second start then starts the
; game). With A held, both players start in continue_world, the world of
; the last game over. Both players' hidden 1-up flags and the timer reload
; count go up, the second quest follows world_select_on, and both players'
; score and coin digits are cleared.
;
; The world: world 1 (the title cleared it), the world select's, or with A
; continue_world; the first area of it (set_world).
;
; In:       A8 = the pads (PAD_START, or PAD_A | PAD_START); demo_timer,
;           continue_world, world_select_on
; Out:      mode = MODE_GAME, mode_task = 0 (begin_area in the next frame),
;           demo_timer = 0; the players' records; hard_mode; the digits
; Changes:  A, X, Y, the flags
; Time:     once; about 150 cycles and load_area_pointer
; Original: $82D8-$830D. The original takes the A button from the carry of
;           its pad value shifted left; here the A bit.
; ---------------------------------------------------------------------------
start_game:
.a8
.i8
        ldx timers + TIMER_DEMO
        beq reset_title                 ; a start in the demo: the title again
        bit #PAD_A
        beq @area
        lda continue_world
        jsr set_world
@area:  jsr load_area_pointer ; the area of world, area_index
        inc player_record + PlayerRecord::hidden_1up
        inc other_record + PlayerRecord::hidden_1up
        inc timer_reload                ; the area's time at the first entrance (a count)
        lda #MODE_GAME
        sta mode
        lda world_select_on
        sta hard_mode                   ; a game after world 8 is won: the second quest
        stz mode_task
        stz timers + TIMER_DEMO
        a16
        .repeat DIGITS_PLAYERS_SIZE / 2, I
        stz digits + DIGITS_SCORE_1 + 2 * I
        .endrepeat
        a8
        rts
.assert DIGITS_PLAYERS_SIZE .mod 2 = 0, error, "start_game clears the digits a word at a time"

; ---------------------------------------------------------------------------
; set_world: both players at the first area of world A. The waiting player's
; record is written in a one-player game too; nothing reads it there.
;
; In:       A8 = the world (0-7)
; Out:      player_record and other_record: world = A, area_index = 0
; Changes:  the flags
; Keeps:    A, X, Y, D
; Time:     20 cycles
; Original: $830E-$831C. The original leaves X = 0, which its world step
;           uses as the index of its copy; the port's copy does not
;           need it.
; ---------------------------------------------------------------------------
set_world:
.a8
.i8
        sta player_record + PlayerRecord::world
        sta other_record + PlayerRecord::world
        stz player_record + PlayerRecord::area_index
        stz other_record + PlayerRecord::area_index
        rts

; ---------------------------------------------------------------------------
; step_world_select: the world select's next world, 0-7 in a ring (the first
; step after the title's start gives world 2); both players are put there,
; and the status bar's world digit shows it.
;
; In:       world_select
; Out:      world_select; the players' worlds (set_world); the digit's record
; Changes:  A, X, Y, the flags
; Time:     about 110 cycles
; Original: $829C-$82B8
; ---------------------------------------------------------------------------
step_world_select:
.a8
.i8
        lda world_select
        inc a
        and #WORLD_SELECT_MASK
        sta world_select
        jsr set_world
        jmp draw_world_digit            ; screen.s

; ---------------------------------------------------------------------------
; demo_pad: pad 1's bits in a frame of the demo. Each step holds its pad
; bits for its frames: the frame that begins it and frames - 1 more. A step
; whose frame count is 0 ends the demo. The 21 steps last 1119 frames.
;
; demo_step counts the steps begun, as the original's: step k (1-21) uses
; entry k - 1 of demo_steps, where the original reads its two tables one
; byte before their starts.
;
; In:       demo_step, demo_step_timer
; Out:      carry set: the demo is over (pad 1 unchanged); else carry clear,
;           pad_bits (pad 1) = the step's bits; demo_step, demo_step_timer
; Changes:  A, X, the flags
; Time:     about 40 cycles
; Original: $836B-$838A
; ---------------------------------------------------------------------------
demo_pad:
.a8
.i8
        lda demo_step_timer
        bne @step                       ; the step goes on
        inc demo_step                   ; the next step begins
        lda demo_step
        asl a
        tax
        lda demo_steps - DEMO_STEP_SIZE + DEMO_STEP_FRAMES,x
        sta demo_step_timer
        bne @pads
        sec                             ; its frame count is 0: the demo is over
        rts
@step:  lda demo_step
        asl a
        tax
@pads:  lda demo_steps - DEMO_STEP_SIZE + DEMO_STEP_PADS,x
        sta pad_bits
        dec demo_step_timer
        clc
        rts
.assert DEMO_STEP_SIZE = 2, error, "demo_pad finds a step with one ASL"
