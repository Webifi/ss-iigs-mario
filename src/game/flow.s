; The modes and the flow of a game (documents 03 and 09): the play mode,
; the victory mode and the game over mode with their tasks, the start of a
; game and of each area, the state groups that those starts clear, the area
; song, a lost life, the game over, the turns of two players, and one frame
; of play (game_core).
;
; Place in the game. mode_dispatch (src/game/frame.s) runs play_mode,
; victory_mode or game_over_mode in each frame that is not paused, by mode
; (title_mode: src/game/title.s). Each runs the task of mode_task; one task
; runs in each frame, and a task stays until a routine writes mode_task or
; mode. The player part (src/game/player.s) runs lose_a_life as player task
; 6; title_menu runs game_core in the title's frames.
;
; The modes (03 section 2.3; mode_task):
;
;   | Mode     | Task | Routine              | Next                          |
;   |----------|------|----------------------|-------------------------------|
;   | play     | 0    | begin_area           | 1 (one frame)                 |
;   |          | 1    | screen_routines      | 2 at screen task 12           |
;   |          | 2    | finish_area_setup    | 3 (one frame)                 |
;   |          | 3    | game_core            | an event below                |
;   | victory  | 0    | bridge_collapse_task | 1 when Bowser is gone (05b)   |
;   |          | 1    | victory_setup        | 2 (one frame)                 |
;   |          | 2    | victory_walk         | 3 when the walk and the       |
;   |          |      |                      | scroll have stopped           |
;   |          | 3    | victory_messages     | 4 after 257 or 448 frames     |
;   |          | 4    | end_world            | the next world, or the title  |
;   | game over| 0    | begin_game_over      | 1 (one frame)                 |
;   |          | 1    | screen_routines      | 2 at screen task 6            |
;   |          | 2    | wait_game_over       | the other player, or the title|
;
; The events of play (03 section 2.2): an area change (switch_area_mode,
; 04) and a lost life with lives left (lose_a_life, return_to_game): play
; task 0; no life left: the game over mode; the axe (touch_axe, 07): the
; victory mode; the other player goes on (end_game_for_player): play task
; 0; no other player: the title (mode 0).
;
; The state groups. The original clears its RAM by address ranges; the
; port's state is grouped by the same lifetimes (03 section 4.7, 10):
;   AREASTATE    segment: what each area start clears (the original's RAM
;                below $074C): begin_area, and so init_game
;   TITLESTATE   segment: what a game's start on the title clears and an
;                area start keeps ($074C-$076F and the sound program's
;                $07B0-$07CF): init_game
;   GAMESTATE    the rest: kept from the power-on (the clear of src/game.s)
; and beside the segments: the object records (each field but the slot
; number: area state), the timers below demo_timer (area state, 03 section
; 4.4), and the sound program's two groups (src/game/sound_program.s
; sound_state: its first group is area state, the second title state).
;
; Two players (09). player_record is the record of the player on the
; screen and other_record the waiting player's; swap_players trades them
; with player. A player whose lives are negative (bit 7) never gets a turn
; again (09 Q2).
;
; Numbers. The screen's left edge is the word screen_left (page x 256 +
; pixel): begin_area sets its page byte. picture_scroll is the picture's
; left edge in the ring of the two name tables (state.inc): the original's
; scroll register and the name table bit of its chip control.
;
; Merged and split. victory_step (the victory mode's task jump) and
; next_mode_task, next_victory_task are inside the routines. The original's
; clear_game_memory is clear_area_state and clear_title_state. The scroll
; routines, setup_entry_and_timer (player task 0), the star palette and the
; end of game_core (remember_ab_buttons, update_scroll_vars) are the player
; part's (src/game/player.s, document 04).
;
; Routines:
;   play_mode            the task of the play mode ($AEDC)
;   game_over_mode       the task of the game over mode ($9218)
;   victory_mode         the victory mode's task, the retainer, the player ($838B)
;   init_game            a game's state on the title, then begin_area ($8FCF)
;   begin_area           the start of an area ($8FE4)
;   game_setup           a game's lives, the small player, then finish ($9061)
;   finish_area_setup    the last step of an area's start ($9071)
;   clear_area_state     the area group of the state ($90CC with Y = $4B)
;   clear_title_state    the title group of the state ($90CC with Y = $6F)
;   start_area_music     the area's song ($90ED)
;   lose_a_life          player task 6: a life lost ($91CD)
;   begin_game_over      the game over mode's start ($9224)
;   wait_game_over       the GAME OVER wait ($9237)
;   end_game_for_player  the other player's turn, or the title ($9248)
;   return_to_game       the play mode with the record on the screen ($9264)
;   swap_players         the other player's turn when he has lives ($9282)
;   game_core            one frame of play ($AEEA)
;   victory_setup        the walk's end page, the castle song ($83B0)
;   victory_walk         the walk to the retainer, the scroll ($83BD)
;   victory_messages     the castle messages ($83F6, $8418)
;   end_world            the next world, or the end of the game ($8461)
;
; Original routines: $838B-$849E, $8FCF-$92AF, $AEDC-$AF66 (without the star
; palette $AF3B-$AF66).

; ---- Values of the original program (03 section 8) -----------------------------
ENTRANCE_PIPE_INTRO_2 = ENTRANCE_PIPE_INTRO + 1
HALFWAY_ENTRANCE = 2            ; entrance at a halfway start: on the ground (03 section 4.4)
SONG_CLOUD_INDEX = 4            ; area_song_by_type: the cloud song
SONG_PIPE_INTRO_INDEX = 5       ;   the pipe intro song
COLUMN_SETS_AT_START = $0B      ; column_sets: 12 column sets before the area shows (06 section 11)
BUFFER_COLUMNS_SHIFT = 4        ; column_in_buffer: the page's bit 0 x 16, the buffer of the page (06)
PAGE_ODD        = 1             ; bit 0 of a page: name table and collision buffer 1 or 2
HARD_WORLD      = 4             ; world 5: from its level 3 on the enemies are harder
HARD_LEVEL      = 2             ; level 3
PICTURE_OFF     = 1             ; screen_off from begin_area: the picture of the next frame off
LIVES_AT_START  = 2             ; lives after the one in play: three lives (03 section 4.5)
PLAYER_SMALL    = 1             ; player_small: the player starts small
TIMER_RELOAD_DUE = 1            ; timer_reload from game_setup: the next timed entrance loads the time
LEVEL_START_PAGE = 0            ; halfway_page: a restart from the level's start
WORLD_SELECT_WON = 1            ; world_select_on after world 8: the second quest and the world select
SHUFFLE_AMOUNT_0 = $58          ; shuffle_amounts: the sprite shuffle's three steps (02 section 9.2)
SHUFFLE_AMOUNT_1 = $48
SHUFFLE_AMOUNT_2 = $38
PICTURE_PAGE_BIT = $0100        ; picture_scroll and screen_left: bit 0 of the page, the name table
WORLD_END_STEPS = 6             ; world_end_timer: 106-126 frames after the messages (03 section 2.4)
LIVES_NONE      = $FF           ; end_world: the winner's lives, so his game ends
PLAYER_TOGGLE   = 1             ; player XOR this: the other player
WALK_END_X      = $60           ; victory_walk: the X in dest_page where the walk stops
WALK_SCROLL_FRACTION = $80      ; scroll_fraction + this each scrolled frame: 1.5 pixels a frame
WALK_SCROLL_PIXELS = 1          ; and the carry gives the second pixel of each other frame
MESSAGE_STEP_COUNT = 4          ; message_counter + this each frame: a step each 64 frames
MESSAGE_ELSEWHERE = 2           ; the message of step 2 in worlds 1-7: the princess is in another castle
MESSAGE_WORLD_END = 4           ; worlds 1-7: the step that ends the messages, without its count
MESSAGE_QUEST_FIRST = 3         ; world 8: the first step with a message after the thanks
MESSAGE_LAST_STEP = 7           ; the count that reaches this step ends the messages
SOURCE_MESSAGES = $0C           ; the source of the castle message 0 (02 section 11.3); + n for message n
SPRITE_ZERO_ENTRY = 0           ; sprite_list + this: sprite 0, the status split's marker

; The first sprites: finish_area_setup copies default_sprite_starts to the
; entries below the misc objects' (02 section 9.2).
DEFAULT_SPRITE_STARTS = SPR_MISC

; ---- State ----------------------------------------------------------------
.segment "AREASTATE"
; The castle message counter (03 section 6.4): the original's message_step x
; 256 + message_step_2. victory_messages adds 4 each frame, so its high byte
; is the 64-frame step; each area start clears it.
message_counter: .res 2
.segment "GAMEPLAY"

; zero_fill FIRST, SIZE: SIZE bytes of bank 0 from FIRST become 0: a zero
; word at FIRST, then MVN copies each byte to the one after it. SIZE is 2 or
; more. In: A16 X16. Changes: A, X, Y.
.macro zero_fill first, size
        stz first
        ldx #first
        ldy #first + 1
        lda #size - 2                   ; MVN moves A + 1 bytes: first + 1 to first + size - 1
        mvn #^(first), #^(first)
.endmacro
.assert __AREASTATE_SIZE__ >= 2, lderror, "flow.s: zero_fill needs AREASTATE of 2 bytes or more"
.assert __TITLESTATE_SIZE__ >= 2, lderror, "flow.s: zero_fill needs TITLESTATE of 2 bytes or more"
.assert SOUND_AREA_STATE_SIZE >= 2, lderror, "flow.s: zero_fill of the sound program's area state"
.assert SOUND_STATE_SIZE - SOUND_AREA_STATE_SIZE >= 2, lderror, "flow.s: zero_fill of the sound program's title state"

.a8
.i8

; ---------------------------------------------------------------------------
; play_mode, game_over_mode: run the task of the mode (the table above).
;
; In:       mode_task; D = the player's record (the frame's)
; Out:      the task's
; Changes:  A, X, Y, D, the flags
; Time:     12 cycles, then the task
; Original: $AEDC-$AEE9 (play_mode), $9218-$9223 (game_over_mode)
; ---------------------------------------------------------------------------
play_mode:
.a8
.i8
        lda mode_task
        asl a                           ; a word for each task
        tax
        jmp (.loword(play_tasks),x)
play_tasks:
        .addr begin_area, screen_routines, finish_area_setup, game_core
.assert PLAY_TASK_CORE = 3, error, "play_tasks: game_core is task PLAY_TASK_CORE"

game_over_mode:
.a8
.i8
        lda mode_task
        asl a
        tax
        jmp (.loword(game_over_tasks),x)
game_over_tasks:
        .addr begin_game_over, screen_routines, wait_game_over

; ---------------------------------------------------------------------------
; victory_mode: each frame of the victory: the task of mode_task, then, once
; the bridge has fallen (mode_task not 0, read after the task), enemy slot 0
; (the retainer comes into it from the area's list as the screen scrolls),
; then the player's place on the screen and his sprites. Nothing else of
; play runs (03 section 6.1).
;
; In:       mode_task (0-4); D = the player's record (the frame's)
; Out:      the task's; the retainer's slot; the player's sprites
; Changes:  A, X, Y, D, the flags
; Time:     about 40 cycles, then the routines
; Original: $838B-$83AF (victory_mode, victory_step)
; ---------------------------------------------------------------------------
victory_mode:
.a8
.i8
        lda mode_task
        asl a                           ; a word for each task
        tax
        jsr (.loword(victory_tasks),x)           ; victory_step: the task of this frame
        lda mode_task
        beq @player                     ; the bridge still falls
        pea enemy_objects
        pld                             ; D = enemy slot 0
        jsr enemies_and_loops           ; 05a: the slot's enemy, or the next of the list
@player:
        pea player_object
        pld
        jsr player_screen_position      ; 11
        jmp draw_player                 ; 11
victory_tasks:
        .addr bridge_collapse_task, victory_setup, victory_walk, victory_messages, end_world

; ---------------------------------------------------------------------------
; init_game: title task 0: the state of a game from its start. The title
; group is cleared (the area group is cleared by begin_area, which
; follows), the title's demo waits its full time, and the area is world 1
; area 1 (the cleared world and area_index). Then begin_area.
;
; Kept from the game before (03 section 4.7): mode, mode_task, the picture
; flags, the pause, two_players, the interval counter, the timers from
; demo_timer up, the random bits, the top score and the digits,
; world_select_on, continue_world.
;
; In:       D = the player's record
; Out:      the title group 0; demo_timer = DEMO_WAIT_STEPS; area_byte,
;           area_type (load_area_pointer); then begin_area's
; Changes:  A, X, Y, D, the flags
; Time:     once for each title start: the clears, about 7 cycles a byte
; Original: $8FCF-$8FE3. The original clears $0000-$076F, the area group
;           too, which begin_area clears again before anything reads it;
;           the port clears it once, in begin_area.
; ---------------------------------------------------------------------------
init_game:
.a8
.i8
        jsr clear_title_state
        lda #DEMO_WAIT_STEPS
        sta timers + TIMER_DEMO
        jsr load_area_pointer           ; 06: the area of world and area_index (both 0)
; Falls into begin_area.

; ---------------------------------------------------------------------------
; begin_area: play task 0, and title task 0 after init_game: the start of an
; area, in one frame (03 section 4.4).
;   1. The area group of the state cleared, and the timers below demo_timer.
;   2. The start page P: the player record's halfway page, or the entrance
;      page after a pipe or a vine (entrance_alt). The screen's left edge
;      is pixel 0 of page P, and its right edge 255 pixels on.
;   3. The area builder starts at page P (06): parse_page P and the
;      collision buffer column of the page (column_in_buffer).
;   4. Twelve column sets before the area shows (column_sets, screen task
;      8); the area's lists and header (load_area_addresses, 06).
;   5. The harder enemies (hard_mode_2): in the second quest, and from world
;      5 level 3 on. A halfway start enters on the ground (entrance 2).
;   6. The area song silent, the picture off, the next task.
;
; The original's column address of its first column (02 section 17) is not
; kept: the area builder gives draw_column_tiles (screen.s) its column.
;
; In:       player_record (halfway page, world, level), entrance_alt,
;           entrance_page, hard_mode, area_byte
; Out:      the area group 0, then the values above; mode_task + 1
; Changes:  A, X, Y, D (the player's record at the exit), the flags
; Time:     once for each area start: the clears, about 7 cycles a byte
; Original: $8FE4-$9060. The original takes the name table of its first
;           column from the A that set_screen_edges returns, the right
;           edge's page; it is P (03 L5), which the port uses.
; ---------------------------------------------------------------------------
begin_area:
.a8
.i8
        jsr clear_area_state
        pea player_object
        pld                             ; D = the player's record again
        lda player_record + PlayerRecord::halfway_page
        ldx entrance_alt
        beq @page                       ; the level's start or its halfway page
        lda entrance_page               ; after a pipe or a vine
@page:  sta screen_left + 1             ; the left edge's page; its pixel is 0 from the clear
        sta parse_page                  ; 06
        jsr set_screen_edges            ; 04: screen_right
        lda screen_left + 1
        and #PAGE_ODD
        .repeat BUFFER_COLUMNS_SHIFT
        asl a
        .endrepeat
        sta column_in_buffer            ; 06: the buffer of the page, its column 0
        lda #COLUMN_SETS_AT_START
        sta column_sets
        jsr load_area_addresses         ; 06: the lists and the header of area_byte
; The harder enemies: the second quest, a world after world 5, or world 5
; from its level 3. hard_mode_2 is 0 after the clear; the original adds 1.
        lda hard_mode
        bne @hard
        lda player_record + PlayerRecord::world
        cmp #HARD_WORLD
        bcc @halfway                    ; worlds 1-4
        bne @hard                       ; worlds 6-8
        lda player_record + PlayerRecord::level
        cmp #HARD_LEVEL
        bcc @halfway                    ; 5-1, 5-2
@hard:  inc hard_mode_2
@halfway:
        lda player_record + PlayerRecord::halfway_page
        beq @song
        lda #HALFWAY_ENTRANCE           ; the header's entrance gives way
        sta entrance
@song:  lda #SONG_SILENCE
        sta snd_area_queue              ; the area song stops; finish_area_setup chooses the next
        lda #PICTURE_OFF
        sta screen_off
        inc mode_task                   ; the screen tasks from the next frame
        rts

; ---------------------------------------------------------------------------
; game_setup: title task 2: a game's lives at its start (three for each
; player: the count is the lives after the one in play), the player small,
; the timer to load at the first area; then finish_area_setup.
;
; In:       nothing
; Out:      timer_reload = 1, player_small = 1, both lives = 2; then
;           finish_area_setup's
; Changes:  A, X, Y, the flags
; Original: $9061-$9070
; ---------------------------------------------------------------------------
game_setup:
.a8
.i8
        lda #TIMER_RELOAD_DUE
        sta timer_reload                ; the time is loaded at the first entrance
        lda #PLAYER_SMALL
        sta player_small
        lda #LIVES_AT_START
        sta player_record + PlayerRecord::lives
        sta other_record + PlayerRecord::lives ; also in a one-player game (09 Q4)
; Falls into finish_area_setup.

; ---------------------------------------------------------------------------
; finish_area_setup: play task 2, and title task 2 after game_setup: the
; last step of an area's start, in one frame (03 section 4.6). The picture
; on from the next frame; the time-up and no-lives-screen flags cleared
; (the original also clears its parser's backloading flag, which the
; build-time area data does not need, 06); no balance lift; the picture's name table
; follows the screen's page; the area song; the sprite shuffle's amounts,
; the first sprite of each object group and sprite 0 at the status bar;
; the status split on.
;
; The original clears $0300-$03FF again here (03 L10). The bytes of that
; page that the screen tasks write are both write lists, empty in this
; frame (the frame's send emptied them), and the attribute buffer, which
; the port does not have; the port clears nothing again. The original's
; empty_return and unused_ff_store calls are left out: the $FF of
; unused_ff_store is read only by the collision part's reads past its
; buffers, which take it as a constant (03 L3; 07: PAST_FF).
;
; In:       screen_left, picture_scroll
; Out:      see above; mode_task + 1
; Changes:  A, X, Y, the flags
; Time:     once for each area start: about 250 cycles
; Original: $9071-$90CB
; ---------------------------------------------------------------------------
finish_area_setup:
.a8
.i8
        stz screen_off                  ; the picture on
        stz time_up
        stz no_lives_screen
        lda #BALANCE_NONE
        sta balance_side
; The picture's name table: bit 0 of the screen's page, with the scroll's
; pixel unchanged ((A XOR M) AND bit XOR M takes the bit from A).
        a16
        lda screen_left
        eor picture_scroll
        and #PICTURE_PAGE_BIT
        eor picture_scroll
        sta picture_scroll
        a8
        jsr start_area_music
; The sprite shuffle and the first sprites (02 section 9.2): the first
; frame of play draws with the set after this one.
        lda #SHUFFLE_AMOUNT_0
        sta shuffle_amounts
        lda #SHUFFLE_AMOUNT_1
        sta shuffle_amounts + 1
        lda #SHUFFLE_AMOUNT_2
        sta shuffle_amounts + 2
        ax16
        ldx #default_sprite_starts
        ldy #sprite_offset
        lda #DEFAULT_SPRITE_STARTS - 1  ; MVN moves A + 1 bytes
        mvn #^default_sprite_starts, #^sprite_offset
; Sprite 0: the split's marker (Y $18, its tile, behind the background, X
; $58), two words.
        lda sprite_zero_entry
        sta sprite_list + SPRITE_ZERO_ENTRY
        lda sprite_zero_entry + 2
        sta sprite_list + SPRITE_ZERO_ENTRY + 2
        ax8
        inc status_split                ; 0 here: the status bar stays in place
        inc mode_task                   ; game_core or title_menu from the next frame
        rts
.assert SPRITE_ENTRY = 4, error, "finish_area_setup copies sprite 0 as two words"

; ---------------------------------------------------------------------------
; clear_area_state: the state that each area start clears (the original's
; RAM below $074C, 03 section 4.4 step 1, and the timers $0780-$07A1, step
; 2): the AREASTATE segment, the sound program's first group, the timers
; below demo_timer, and every field of each object record but its slot
; number.
;
; In:       nothing
; Out:      the area group 0
; Changes:  A, X, Y, D (the last object record), the flags; A8 I8 at the exit
; Time:     about 7 cycles a byte of the segments, and about 2,200 for the
;           25 records
; Original: $90CC-$90E6 (clear_game_memory with Y = $4B), $8FE9-$8FF2
; ---------------------------------------------------------------------------
OBJECT_CLEAR_WORDS = (.sizeof(Object) - Object::state + 1) / 2
.assert Object::slot = 0 && Object::state = 1, error, "clear_area_state keeps byte 0 of each record, the slot"
clear_area_state:
.a8
.i8
        ax16
        zero_fill __AREASTATE_RUN__, __AREASTATE_SIZE__
        zero_fill sound_state, SOUND_AREA_STATE_SIZE ; 08: the original's $F0-$F9
        .repeat (TIMER_WORLD_END + 1) / 2, I
        stz timers + 2 * I              ; the timers below demo_timer
        .endrepeat
; The object records: each field after the slot number, with D at the
; record (the last word may reach the first byte of the record's scratch).
        lda #objects
@record:
        tcd
        .repeat OBJECT_CLEAR_WORDS, I
        stz Object::state + 2 * I
        .endrepeat
        clc
        adc #OBJECT_PAGE
        cmp #objects + OBJECT_SLOTS * OBJECT_PAGE
        bcc @record
        ax8
        rts
.assert (TIMER_WORLD_END + 1) .mod 2 = 0 && TIMER_DEMO = TIMER_WORLD_END + 1, error, "clear_area_state: the timers below demo_timer, a word at a time"

; ---------------------------------------------------------------------------
; clear_title_state: the state that a game's start on the title clears and
; an area start keeps (the original's $074C-$076F and $07B0-$07CF, 03
; section 4.3): the TITLESTATE segment and the sound program's second group.
;
; In:       nothing
; Out:      the title group 0
; Changes:  A, X, Y, the flags; A8 I8 at the exit
; Time:     about 7 cycles a byte
; Original: $90CC-$90E6 (clear_game_memory with Y = $6F), $8FD4-$8FDB
; ---------------------------------------------------------------------------
clear_title_state:
.a8
.i8
        ax16
        zero_fill __TITLESTATE_RUN__, __TITLESTATE_SIZE__
        zero_fill sound_area_state_end, SOUND_STATE_SIZE - SOUND_AREA_STATE_SIZE ; 08: the original's $07B0-$07CA
        ax8
        rts

; ---------------------------------------------------------------------------
; start_area_music: the area's song into snd_area_queue (the sound program
; takes it in the next frame, 08). No song on the title. A pipe intro scene
; (entrance 6 or 7) has its own song, unless the player rises out of a pipe
; or a vine (entrance_alt 2); a cloud area the cloud song; else the song of
; the area type.
;
; Callers: finish_area_setup; update_star_palette (04) when the star ends.
;
; In:       mode, entrance_alt, entrance, area_type, cloud_override
; Out:      snd_area_queue
; Changes:  A, Y, the flags
; Keeps:    X, D
; Time:     about 30 cycles
; Original: $90ED-$9115
; ---------------------------------------------------------------------------
start_area_music:
.a8
.i8
        lda mode
        beq @done                       ; the title
        lda entrance_alt
        cmp #ENTRANCE_ALT_RISE
        beq @area
        ldy #SONG_PIPE_INTRO_INDEX
        lda entrance
        cmp #ENTRANCE_PIPE_INTRO
        beq @song
        cmp #ENTRANCE_PIPE_INTRO_2
        beq @song
@area:  ldy area_type
        lda cloud_override
        beq @song
        ldy #SONG_CLOUD_INDEX
@song:  lda area_song_by_type,y
        sta snd_area_queue
@done:  rts

; ---------------------------------------------------------------------------
; lose_a_life: player task 6, after a death: the picture off, the split off,
; the event song stops, one life less. With no life left (the sign of the
; lives byte, 03 L7) the game over mode starts. Else the level starts again
; from its halfway page, when the screen's left edge reached it, the other
; player takes his turn when he has lives (09 section 5.2), and the play
; mode starts the area of the record on the screen.
;
; halfway_pages_by_level (scripts/screen_data.py) is the original's
; halfway_pages as a byte for each world and level: the page from which a
; restart begins, 0 for none.
;
; In:       player_record: lives, world, level; screen_left (the area where
;           the player died, also a bonus area)
; Out:      mode = MODE_GAME_OVER, mode_task = 0; or the halfway page, the
;           swap and return_to_game's
; Changes:  A, X, Y, the flags
; Time:     once for each lost life
; Original: $91CD-$9217
; ---------------------------------------------------------------------------
lose_a_life:
.a8
.i8
        inc screen_off                  ; the picture off from the next frame
        stz status_split
        lda #EVENT_SILENCE
        sta snd_event_queue
        dec player_record + PlayerRecord::lives
        bpl @halfway                    ; bit 7 clear: lives left
        lda #MODE_GAME_OVER
        sta mode
        stz mode_task                   ; begin_game_over in the next frame
        rts
@halfway:
        lda player_record + PlayerRecord::world
        asl a
        asl a                           ; four levels a world
        ora player_record + PlayerRecord::level
        tax
        lda halfway_pages_by_level,x
        cmp screen_left + 1
        beq @store                      ; the left edge reached the halfway page
        bcc @store
        lda #LEVEL_START_PAGE           ; not reached: the level's start
@store: sta player_record + PlayerRecord::halfway_page
        jsr swap_players
        jmp return_to_game

; ---------------------------------------------------------------------------
; begin_game_over: game over task 0, one frame: the screen tasks from their
; start (with GAME OVER at task 6), the status split off, the game over
; song, the picture off.
;
; In:       nothing
; Out:      screen_task = 0, status_split = 0, snd_event_queue, screen_off + 1,
;           mode_task + 1
; Changes:  A, the flags
; Original: $9224-$9236
; ---------------------------------------------------------------------------
begin_game_over:
.a8
.i8
        stz screen_task                 ; blank_screen_task in the next frame
        stz status_split
        lda #EVENT_GAME_OVER
        sta snd_event_queue
        inc screen_off
        inc mode_task
        rts

; ---------------------------------------------------------------------------
; wait_game_over: game over task 2, each frame: the picture on; start on pad
; 1 (only pad 1, 09 Q3, also in Luigi's game) or the end of the screen
; timer (358-378 frames) ends the wait (end_game_for_player). The players
; are not swapped yet: GAME OVER names the player whose game ended.
;
; In:       pad_bits (pad 1, as the frame read it), screen_timer
; Out:      screen_off = 0; end_game_for_player's at the end of the wait
; Changes:  A, X, Y, the flags
; Original: $9237-$9247
; ---------------------------------------------------------------------------
wait_game_over:
.a8
.i8
        stz screen_off
        lda pad_bits
        and #PAD_START
        bne end_game_for_player
        lda timers + TIMER_SCREEN
        beq end_game_for_player
        rts

; ---------------------------------------------------------------------------
; end_game_for_player: the game of the player on the screen has ended (the
; game over, or B after world 8). The event song stops. When the other
; player has lives, he goes on with his own record (return_to_game). Else
; the world of this player is the continue world, and the title starts.
;
; In:       two_players, other_record (lives), player_record (world)
; Out:      return_to_game's, or continue_world, mode = MODE_TITLE,
;           mode_task = 0, screen_timer = 0
; Changes:  A, X, Y, the flags
; Original: $9248-$9263. Its ASL of A = 0 before the stores has no effect
;           (03 L9).
; ---------------------------------------------------------------------------
end_game_for_player:
.a8
.i8
        lda #EVENT_SILENCE
        sta snd_event_queue
        jsr swap_players
        bcc return_to_game              ; the other player goes on
        lda player_record + PlayerRecord::world
        sta continue_world              ; start with A on the title continues here
        stz mode_task
        stz timers + TIMER_SCREEN
        stz mode                        ; MODE_TITLE: init_game in the next frame
        rts

; ---------------------------------------------------------------------------
; return_to_game: the play mode from its task 0 with the record on the
; screen: its area (world, area_index: the level's area, not a bonus area),
; the player small with no power, the area's time at the entrance, the
; timers running, the player's first task.
;
; In:       player_record (world, area_index)
; Out:      area_byte, area_type; player_small = 1, timer_reload + 1,
;           timer_hold = 0, player_power = 0, player_task = 0, mode_task = 0,
;           mode = MODE_GAME
; Changes:  A, X, Y, the flags
; Original: $9264-$9281. timer_reload is a count (03 L8): + 1 makes it not 0.
; ---------------------------------------------------------------------------
return_to_game:
.a8
.i8
        jsr load_area_pointer           ; 06
        lda #PLAYER_SMALL
        sta player_small
        inc timer_reload
        stz timer_hold
        stz player_power
        stz player_task                 ; PLAYER_TASK_ENTRANCE_SETUP
        stz mode_task                   ; begin_area in the next frame
        lda #MODE_GAME
        sta mode
        rts
.assert PLAYER_TASK_ENTRANCE_SETUP = 0, error, "return_to_game stores 0 as PLAYER_TASK_ENTRANCE_SETUP"

; ---------------------------------------------------------------------------
; swap_players: in a two-player game whose waiting player has lives (bit 7
; of his lives clear, 09 Q2), his turn: player flips and the two records
; trade places.
;
; In:       two_players, player, player_record, other_record
; Out:      carry clear: swapped; carry set: no other player goes on
; Changes:  A, X, the flags
; Keeps:    Y, D
; Time:     about 160 cycles with the swap
; Original: $9282-$92A9
; ---------------------------------------------------------------------------
swap_players:
.a8
.i8
        lda two_players
        beq @alone
        lda other_record + PlayerRecord::lives
        bmi @alone                      ; the other player is out
        lda player
        eor #PLAYER_TOGGLE
        sta player
        ldx #.sizeof(PlayerRecord) - 1
@byte:  lda player_record,x
        pha
        lda other_record,x
        sta player_record,x
        pla
        sta other_record,x
        dex
        bpl @byte
        clc
        rts
@alone: sec
        rts

; ---------------------------------------------------------------------------
; game_core: one frame of play: play task 3, and title task 3 (the title's
; player and its demo). The steps, in the original's order (03 section 5.2):
;    1. Pad 1's byte = the pad of the player whose turn it is (09 section 7).
;    2. The player's task (04), with the scroll inside control.
;    3. A task that left play (an area change, a lost life, the game over,
;       the axe) ends the frame here: no object moves, no timer ticks, no
;       column is built, no sprite is drawn (03 D3).
;    4. The fireballs and the bubbles (05a).
;    5. Enemy slots 0-5: the slot's enemy, or the next of the area's list
;       (05a, 05b), then its score number (07).
;    6. The player's offscreen bits and place on the screen, 7. his sprites
;       (11).
;    8. A bumped block's metatile comes back (07); 9. the block objects 1,
;       then 0 (05a).
;   10-14. The misc objects, the cannons, the whirlpools, the flagpole's
;       flag (05a, 05b), the game timer (07).
;   15. The blinking colours (screen.s).
;   16. The star's palette (04 update_star_palette).
;   17-18. A and B for the next frame, then the area builder
;       (04 remember_ab_buttons, update_scroll_vars).
;
; In:       pad_bits, player, mode_task; D = the player's record
; Out:      the frame of play
; Changes:  A, X, Y, D, the flags
; Time:     about 180 cycles of its own, and the routines
; Original: $AEEA-$AF3A (steps 16-18: $AF3B-$AF92, src/game/player.s)
; ---------------------------------------------------------------------------
game_core:
.a8
.i8
        ldx player
        lda pad_bits,x
        sta pad_bits                    ; Luigi plays with pad 2
        jsr run_player_task             ; 04: D = the player's record
        lda mode_task
        cmp #PLAY_TASK_CORE
        bcs @play
        rts                             ; the task left play
@play:  jsr run_fireballs_and_bubbles   ; 05a
; The enemy slots, each with D at its record: enemies_and_loops returns
; with the same D for the slot's score number.
        a16
        lda #enemy_objects
@enemy: tcd
        a8
        jsr enemies_and_loops           ; 05a
        jsr score_numbers               ; 07
        a16
        tdc
        clc
        adc #OBJECT_PAGE                ; the next slot's record
        cmp #enemy_objects + ENEMY_SLOTS * OBJECT_PAGE
        bcc @enemy
; The player: his place, his sprites.
        lda #player_object
        tcd
        a8
        jsr check_player_offscreen      ; 11
        jsr player_screen_position      ; 11
        jsr draw_player                 ; 11
        jsr replace_bumped_metatile     ; 07
        pea block_objects + OBJECT_PAGE ; block 1, then block 0
        pld
        jsr run_block_objects           ; 05a
        pea block_objects
        pld
        jsr run_block_objects
        pea player_object
        pld                             ; D = the player's record for the rest
        jsr run_misc_objects            ; 05a
        jsr run_cannons                 ; 05b
        jsr pull_in_whirlpools          ; 05a
        jsr run_flag_object             ; 05a
        jsr tick_game_timer             ; 07
        jsr blink_block_colors          ; screen.s
        jsr update_star_palette         ; 04
        jmp remember_ab_buttons         ; 04: then update_scroll_vars

; ---------------------------------------------------------------------------
; victory_setup: victory task 1, one frame: the walk ends in the page after
; the screen's right edge; the castle's end song.
;
; In:       screen_right
; Out:      dest_page; snd_event_queue = EVENT_CASTLE_END; mode_task + 1
; Changes:  A, the flags
; Original: $83B0-$83BC
; ---------------------------------------------------------------------------
victory_setup:
.a8
.i8
        lda screen_right + 1            ; the page of the right edge
        inc a
        sta dest_page
        lda #EVENT_CASTLE_END
        sta snd_event_queue
        inc mode_task
        rts

; ---------------------------------------------------------------------------
; victory_walk: victory task 2, each frame. The player walks right (the
; pad's right bit) until X $60 of the walk's end page, then stands; the
; screen scrolls until its left edge is in that page, 1.5 pixels a frame
; (1 and 2 by turns: scroll_fraction + $80 gives the second pixel by its
; carry), with the area builder after each scroll. When the player stands
; and the screen does not scroll, the messages follow.
;
; scroll_fraction is not cleared at a castle (03 L6): the first step of the
; next castle's walk is 1 or 2 pixels by where the last walk left it, and
; both players share it.
;
; In:       dest_page, the player's X, screen_left, scroll_fraction;
;           D = the player's record
; Out:      victory_walk_state; the player's control (auto_control_player);
;           the scroll (scroll_screen, update_scroll_vars); mode_task + 1
; Changes:  A, X, Y, the flags; what those routines change
; Time:     about 60 cycles, and the routines
; Original: $83BD-$83F5 (next_victory_task: $845D)
; ---------------------------------------------------------------------------
victory_walk:
.a8
.i8
        stz victory_walk_state
        ldy #PAD_NONE                   ; no button: the player stands
        lda player_object + Object::x_pos + 1
        cmp dest_page
        bne @walk                       ; another page: on (also past it, as the original)
        lda player_object + Object::x_pos
        cmp #WALK_END_X
        bcs @control
@walk:  inc victory_walk_state
        ldy #PAD_RIGHT
@control:
        tya
        jsr auto_control_player         ; 04
        lda screen_left + 1
        cmp dest_page
        beq @still                      ; the screen is there
        lda scroll_fraction
        clc
        adc #WALK_SCROLL_FRACTION
        sta scroll_fraction
        lda #WALK_SCROLL_PIXELS
        adc #0                          ; + the carry: 1 or 2 pixels
        tay
        jsr scroll_screen               ; 04
        jsr update_scroll_vars          ; 04: the area builder
        inc victory_walk_state
@still: lda victory_walk_state
        bne @done
        inc mode_task                   ; the messages from the next frame
@done:  rts

; ---------------------------------------------------------------------------
; victory_messages: victory task 3, each frame (03 section 6.4). The
; counter message_counter counts 4 a frame; at each 64-frame step (its low
; byte 0) the step S may send a message (a source of the frame:
; SOURCE_MESSAGES + n for the original's message 12 + n, into name table 1):
;
;   | Worlds 1-7 | S = 0 thanks (n 0 MARIO, 1 LUIGI), 2 the princess is in |
;   |            | another castle; S = 4 ends the task without the count     |
;   | World 8    | S = 0 thanks; 3 the victory song and the quest is over;  |
;   |            | 4 WE PRESENT YOU A NEW QUEST; 5 PUSH BUTTON B; 6 TO     |
;   |            | SELECT A WORLD;                                          |
;   |            | the count that makes S 7 ends the task (frame 447)       |
;
; The end: world_end_timer = 6 slow steps, and end_world from the next
; frame. The task lasts 257 frames in worlds 1-7, 448 in world 8. The
; original's other steps (S 1 and 3 in worlds 1-7, 1 and 2 in world 8) send
; nothing; its rule for S 9 and more is never reached (S ends at 4 or 7).
;
; In:       message_counter (0 from the area start), world, player
; Out:      screen_source; snd_event_queue (EVENT_VICTORY); message_counter;
;           world_end_timer and mode_task + 1 at the end
; Changes:  A, X, the flags
; Time:     about 40 cycles
; Original: $83F6-$8417 (victory_messages), $8418-$8460
;           (choose_castle_message, next_victory_task)
; ---------------------------------------------------------------------------
victory_messages:
.a8
.i8
        lda message_counter
        bne @count                      ; not a step's first frame
        lda message_counter + 1         ; S
        beq @thanks                     ; S 0 in every world
        ldx player_record + PlayerRecord::world
        cpx #WORLD_8
        beq @world_8
        cmp #MESSAGE_ELSEWHERE
        beq @message                    ; n = S = 2
        cmp #MESSAGE_WORLD_END
        beq @end
        bra @count                      ; S 1 and 3
@world_8:
        cmp #MESSAGE_QUEST_FIRST
        bcc @count                      ; S 1 and 2
        bne @message                    ; S 4-6: n = S
        ldx #EVENT_VICTORY              ; S 3: the victory song with the quest's end
        stx snd_event_queue
        bra @message
@thanks:
        lda player                      ; n 0: THANK YOU MARIO!, 1: THANK YOU LUIGI!
@message:
        asl a                           ; a source for each message
        clc
        adc #SOURCE_MESSAGES
        sta screen_source
@count:
        a16
        lda message_counter
        clc
        adc #MESSAGE_STEP_COUNT
        sta message_counter
        a8
        lda message_counter + 1
        cmp #MESSAGE_LAST_STEP
        bcc @done
@end:   lda #WORLD_END_STEPS
        sta timers + TIMER_WORLD_END
        inc mode_task
@done:  rts

; ---------------------------------------------------------------------------
; end_world: victory task 4, each frame, after world_end_timer. Worlds 1-7:
; the next world's first area and level, the timer to load, the play mode
; (the player keeps his power and size). World 8: each frame, B on either
; pad (a held B counts) turns the world select on and ends the winner's game
; (lives $FF): end_game_for_player. Without B the task waits for ever.
;
; In:       world_end_timer, world, pad_bits (both pads, as the frame read
;           them)
; Out:      the record's world, level, area_index; area_byte (load_area_
;           pointer); timer_reload + 1; mode = MODE_GAME, mode_task = 0; or
;           world_select_on = 1, lives = LIVES_NONE, end_game_for_player's
; Changes:  A, X, Y, the flags
; Original: $8461-$849E
; ---------------------------------------------------------------------------
end_world:
.a8
.i8
        lda timers + TIMER_WORLD_END
        bne @wait
        lda player_record + PlayerRecord::world
        cmp #WORLD_8
        bcs @won
        stz player_record + PlayerRecord::area_index
        stz player_record + PlayerRecord::level
        stz mode_task
        inc player_record + PlayerRecord::world
        jsr load_area_pointer           ; 06
        inc timer_reload
        lda #MODE_GAME
        sta mode                        ; begin_area in the next frame
@wait:  rts
@won:   lda pad_bits
        ora pad_bits + 1
        and #PAD_B
        beq @wait
        lda #WORLD_SELECT_WON
        sta world_select_on
        lda #LIVES_NONE
        sta player_record + PlayerRecord::lives
        jmp end_game_for_player
