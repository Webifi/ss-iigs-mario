; The screen work of the game: the screen set-up tasks, the screen records
; of the frame, the palettes, the status bar, the screen texts, the area
; columns, the block pictures and the blinking colours (document 02,
; sections 11-20).
;
; Place in the game. The title mode, the play mode and the game over mode
; run screen_routines as their task 1 (src/game/title.s, flow.s), once each
; frame, until the screen of the mode is set up. The record routines are
; called during play: draw_column_tiles and select_list_two by the area
; builder (06), queue_block_metatile, blank_block_picture,
; replace_block_picture and erase_coin_or_axe by the blocks, the coins and
; the axe (07, 05a), store_block_tiles by the bridge (05b),
; write_screen_text by the warp zone (06), queue_player_colors by the
; entrance and the power-ups (04, 07), blink_block_colors by game_core.
;
; Data out: screen records (src/packet_layout.inc). The card draws the
; picture; the game logic describes the changes of each frame. As the
; original's write lists (02 section 11), each frame sends one source,
; screen_source, which the frame's packet code sends after the logic:
;   SOURCE_LIST_1 (0)  screen_list_1: colours, status bar digits, texts,
;                      block pictures (the original's list 1)
;   SOURCE_LIST_2 (6)  screen_list_2: the area columns and the coin or axe
;                      erase (list 2); list 1 waits for a later frame
;   the others         fixed lists of records, screen_rom_lists
;                      (scripts/screen_data.py): the palettes 1-4 and 8-11,
;                      the title 5, the castle messages $0C-$12 (the
;                      original's numbers, 02 section 11.3), and the port's
;                      two forms of the status bar's top line, $13 and $14;
;                      list 1 is lost with them (02 L2)
; The last choice in a frame counts. A record that the logic of frame N
; queues shows in picture N + 1, as the original's write does.
;
; The original's lengths. Two room tests compare list 1's length in the
; original's bytes: blink_block_colors (below BLINK_ROOM) and the balance
; lift ropes (05b). The port's records have other lengths, so beside
; screen_list_1_end (the port's bytes) each writer of list 1 adds its
; record's length in the original's form to screen_list_1_original_end
; (grow_list_1 does both), and whoever empties list 1 clears both.
;
; Merged and split. Text 0 (the status bar's top line with the palettes of
; all of name table 0: 331 bytes as records) does not fit list 1: it is a
; ROM list that draw_status_top chooses. The other texts are forms that the
; builder makes; write_screen_text copies one with a block move. The
; REC_COLUMN record carries the palettes of its squares, so
; write_column_attributes has no records of its own and is select_list_two.
; draw_mushroom_icon (01) and the world digit of the title's world select
; are here with the other writers of list 1. clear_name_tables is the
; frame's (src/game/frame.s), which queues the clear record itself.
;
; Hardware: none.
;
; Original routines: $8567-$874D (the screen tasks), $8808-$88AD
; (write_screen_text, end_screen_wait), $88AE-$89C2 (the column records),
; $89E1-$8A38 (blink_block_colors), $8A4D-$8B07 (the block pictures),
; $8325-$833F (draw_mushroom_icon), $82A9-$82B8 (the world digit).
;
; Routines:
;   screen_routines          the screen task of this frame ($8567)
;   blank_screen_task        task 0: sprites hidden, name tables clear ($858B)
;   setup_lives_colors       task 1: the player's colours on black ($859B)
;   draw_status_top          task 2: the status bar's top line ($8652)
;   draw_status_bottom       task 3: score, coins, world and level ($865A)
;   show_time_up             task 4: TIME UP when the time ran out ($8693)
;   end_screen_wait          tasks 5 and 7: the wait of a screen text ($889D)
;   restart_screen_timer     the screen timer again, the next task ($88A5)
;   show_lives_screen        task 6: the lives screen or GAME OVER ($86A8)
;   print_and_start_timer    a text, the screen timer, the picture on ($86C7)
;   build_column_sets        task 8: one column set of the area ($86E6)
;   queue_area_palette       task 9: the palette of the area type ($85BF)
;   queue_backdrop_color     task 10: a backdrop setting's palette ($85E3)
;   queue_player_colors      the backdrop and the player's colours ($85F1)
;   queue_colour_record      its record, from given colours
;   queue_mushroom_palette   task 11: the mushroom ledges' palette ($8643)
;   draw_title_logo          task 12: the title picture ($86FF)
;   clear_lists_draw_marker  task 13: both lists empty, the marker ($8732)
;   draw_top_score           task 14: the title's top score ($8749)
;   write_screen_text        texts 1-6 into list 1 ($8808)
;   copy_text_template       a text form into list 1
;   write_lives_text         text 1 with its digits
;   queue_one_cell           a record of one cell into list 1
;   draw_world_digit         the title's world digit ($82A9)
;   draw_mushroom_icon       the menu marker at 1 or 2 players ($8325)
;   draw_column_tiles        a metatile column into list 2 ($88AE)
;   select_list_two          list 2 is the source ($89BD; also $896A)
;   blink_block_colors       each 8th frame, the blink colour ($89E1)
;   queue_block_metatile     a metatile's picture at a block ($8A6D)
;   store_block_tiles        a tile set at a square, list 1 ($8ACD)
;   erase_coin_or_axe        the blank picture, list 2 ($8A4D)
;   metatile_square          the square of a collision buffer cell
;   square_place             a square's place as one word
;   put_square               write a REC_SQUARE record
;   grow_list_1              count a record of list 1 in both lengths


; ---- Values of the original program (02 unless named) -------------------------
TILE_DASH       = $28           ; the dash between the world and the level digits (02 section 15)
TILE_CROWN      = $9F           ; before the lives digit from 10 lives on (02 section 16.1)
TILE_MENU_MARKER = $CE          ; the title's menu marker (01 section 7.2)
STATUS_WORLD_ROW = 3            ; the status bar's world, dash and level: row 3 ($2073)
STATUS_WORLD_COLUMN = 19        ;   columns 19-21
STATUS_WORLD_TILES = 3
STATUS_WORLD_ORIGINAL_SIZE = 6  ; the original's record: 3 head bytes, 3 tiles
PLAYER_COLOURS_ENTRY = 16       ; $3F10: sprite palette 0, whose colour 0 is the backdrop entry 0 (02 section 14.3)
PLAYER_COLOURS  = 4             ; the record's colours: the backdrop, the player's three
COLOUR_RECORD_ORIGINAL_SIZE = 7 ; the original's record: 3 head bytes, 4 colours
PLAYER_COLOUR_GROUP = 3         ; player_colours: 3 colours for each of Mario, Luigi and fire
MARIO_COLOURS   = 0 * PLAYER_COLOUR_GROUP
LUIGI_COLOURS   = 1 * PLAYER_COLOUR_GROUP
FIRE_COLOURS    = 2 * PLAYER_COLOUR_GROUP
LIVES_SCREEN_BACKDROP = 2       ; backdrop_colours entry 2: black, the lives screen's backdrop (02 section 13 task 1)
SCREEN_WAIT_STEPS = 7           ; screen_timer of TIME UP and the lives screen: 127-147 frames (02 section 13)
GAME_OVER_WAIT_STEPS = $12      ; screen_timer of GAME OVER: 358-378 frames
AREA_STYLE_MUSHROOM = 1         ; area_style of the mushroom ledges (02 section 13 task 11)
BACKDROP_FIRST_SETTING = 4      ; the backdrop settings are 4-7; 0 is none (02 section 14.3)
TOP_SCORE_FIELDS = $FA          ; refresh_status_number's two fields: $A none, $F the top score (07 section 13)
BLINK_FRAME_MASK = 7            ; the blink steps on each 8th frame (02 section 19.1)
BLINK_ROOM      = $31           ; the original's list 1 room limit of the blink record
BLINK_COLOURS   = 4             ; the blink record's colours: background palette 3
BLINK_ORIGINAL_SIZE = 7         ; the original's record: 3 head bytes, 4 colours
BLINK_STEPS     = 6             ; the blink colours of blink_colour_steps: a cycle of 48 frames
SQUARE_ORIGINAL_SIZE = 10       ; the original's block picture: 2 records of 2 tiles (02 section 18.2)
WORLD_DIGIT_ORIGINAL_SIZE = 4   ; the original's world step list: one record of one tile (01 section 7.1)
MENU_MARKER_ORIGINAL_SIZE = 7   ; the original's marker list: one record of 3 tiles down (01 section 7.2)
MENU_MARKER_CELLS = 3           ; the marker column: rows 18, 19, 20
WARP_TEXT_ORIGINAL_SIZE = $2C   ; the original's list 1 length after the warp zone text (02 section 16.1)
ROW_OFFSET_SHIFT = 3            ; a collision buffer row offset (16 a metatile row) / 8: two cell rows a metatile
.assert RING_COLUMNS = 2 * 32, error, "scripts/screen_data.py numbers name table 1 as ring columns 32-63"

; The sources that this file chooses (02 section 11.3: the original's
; numbers; $13 and $14 are the port's own).
SOURCE_CAVE_PALETTE = 3         ; the underground palette: a black backdrop
SOURCE_TITLE    = 5             ; the title picture (the original's list at $0300)
SOURCE_MUSHROOM_PALETTE = $0B   ; the mushroom ledges: the backdrop and background palette 0
SOURCE_STATUS_TOP_MARIO = $13   ; text 0 with MARIO: the status bar's top line, the palettes of name table 0
SOURCE_STATUS_TOP_LUIGI = $14   ; text 0 with LUIGI
.assert (SOURCE_STATUS_TOP_LUIGI + 1) * ROM_LIST_ENTRY = SCREEN_ROM_LISTS_SIZE, lderror, "screen.s: screen_rom_lists (scripts/screen_data.py) ends with the two forms of text 0"

; The metatiles that queue_block_metatile shows (02 section 18.1).
METATILE_LINED_BRICK = $51      ; the brick with the light top line
METATILE_LINED_BRICK_COINS = $58 ; the same picture: a brick that holds coins
METATILE_BRICK  = $52
METATILE_BRICK_COINS = $5D
; The tile sets of block_square_tiles (02 section 18.1).
BLOCK_SET_LINED_BRICK = 0
BLOCK_SET_BRICK = 1
BLOCK_SET_EMPTY = 2             ; the empty block: any other metatile
BLOCK_SET_WATER_BLANK = 4       ; four tiles of pen 2: a taken coin or axe in a water area

; The screen texts (02 section 16.2). Text 0 is draw_status_top's ROM list;
; write_screen_text writes texts 1-6.
TEXT_LIVES      = 1
TEXT_TIME_UP    = 2
TEXT_GAME_OVER  = 3
TEXT_WARP_ZONE  = 4             ; 4-6: the warp zone of warp_zone 4-6
; The text forms of text_templates, a word each.
TEMPLATE_LIVES  = 0
TEMPLATE_TIME_UP = 2            ; + 0 one player, + 2 MARIO, + 4 LUIGI
TEMPLATE_GAME_OVER = 8          ; the same three forms
TEMPLATE_WARP_ZONE = 14         ; + 2 x (warp_zone - 4)
TEMPLATE_NAMED  = 2             ; from the form without the name to MARIO's, and on to LUIGI's
.assert TEMPLATE_NAMED = 2, error, "screen.s: write_screen_text steps a form with two INX"
; The lives screen's digits (02 section 16.1, step 3).
LIVES_ROW       = 14
LIVES_CROWN_COLUMN = 17
LIVES_CROWN_CELLS = 2           ; the crown and the units: one record
LIVES_UNITS_COLUMN = 18
LIVES_DECIMAL   = 10            ; the lives digit is reduced by 10 once, with the crown
LIVES_WORLD_ROW = 10
LIVES_WORLD_COLUMN = 17
LIVES_LEVEL_COLUMN = 19

; The screen tasks (screen_task), in the order of screen_tasks.
SCREEN_TASK_LIVES = 6           ; show_lives_screen: show_time_up's next task without TIME UP
SCREEN_TASK_COLUMNS = 8         ; build_column_sets: where the lives screen's skip goes
SCREEN_TASKS    = 15

; The fields of the screen records: the kind, then one byte for each field
; (src/packet_layout.inc).
ONE_CELL        = 1             ; the count of a record of one cell
ONE_CELL_SIZE   = CELLS_TILES + ONE_CELL ; its bytes
SQUARE_ROW      = 1             ; SQUARE_ROW and SQUARE_COLUMN are written as one word (put_square)
SQUARE_COLUMN   = 2
SQUARE_TILES    = 3
SQUARE_TILE_COUNT = 4
COLUMN_COLUMN   = 1
COLUMN_METATILES = 2
COLOURS_FIRST   = 1
COLOURS_COUNT   = 2
COLOURS_DATA    = 3
.assert CELLS_TILES = REC_CELLS_HEAD, error, "screen.s: the REC_CELLS fields of packet_layout.inc"
.assert SQUARE_COLUMN = SQUARE_ROW + 1, error, "screen.s: put_square writes the row and the column as one word"
.assert SQUARE_TILES + SQUARE_TILE_COUNT = REC_SQUARE_SIZE, error, "screen.s: the REC_SQUARE fields"
.assert COLUMN_METATILES + METATILE_ROWS = REC_COLUMN_SIZE, error, "screen.s: the REC_COLUMN fields"
.assert COLOURS_DATA = REC_COLOURS_HEAD, error, "screen.s: the REC_COLOURS fields"
.assert MENU_MARKER_RECORDS_SIZE = MENU_MARKER_CELLS * ONE_CELL_SIZE, lderror, "screen.s: menu_marker_records (scripts/screen_data.py) is 3 one-cell records, top first"

; ---- State ----------------------------------------------------------------
.segment "AREASTATE"
colour_step:    .res 1          ; the blink step, 0 to BLINK_STEPS - 1: blink_block_colors only; each area start clears it
column_sets:    .res 1          ; the column sets left at an area's start, 11 down to $FF: begin_area (flow.s) writes
                                ; it, build_column_sets counts it (02 section 13 task 8)
.segment "GAMEPLAY"

.a8
.i8

; ---------------------------------------------------------------------------
; screen_routines: run the screen task of this frame.
;
; The screen tasks, one in each frame (screen_task), and what moves on:
;
;   | Task | Routine                 | Next                                    |
;   |------|-------------------------|-----------------------------------------|
;   | 0    | blank_screen_task       | 1                                       |
;   | 1    | setup_lives_colors      | 2                                       |
;   | 2    | draw_status_top         | 3                                       |
;   | 3    | draw_status_bottom      | 4                                       |
;   | 4    | show_time_up            | 5 with TIME UP, else 6                  |
;   | 5    | end_screen_wait         | 6 when screen_timer is 0                |
;   | 6    | show_lives_screen       | 7 with the lives screen, else 8; the    |
;   |      |                         | game over mode leaves the tasks here    |
;   | 7    | end_screen_wait         | 8 when screen_timer is 0                |
;   | 8    | build_column_sets       | 9 after the 12th column set             |
;   | 9    | queue_area_palette      | 10                                      |
;   | 10   | queue_backdrop_color    | 11                                      |
;   | 11   | queue_mushroom_palette  | 12                                      |
;   | 12   | draw_title_logo         | 13 on the title; else the mode moves on |
;   | 13   | clear_lists_draw_marker | 14 (the title only)                     |
;   | 14   | draw_top_score          | the title mode moves on                 |
;
; begin_area (flow.s) and begin_game_over set screen_task to 0. status_split
; is 0 and game_core does not run while these tasks run.
;
; In:       screen_task (0-14); D = the player's record (the frame's)
; Out:      the task's
; Changes:  A, X, Y, D (the tasks call other parts), the flags
; Time:     12 cycles, then the task
; Original: $8567-$858A
; ---------------------------------------------------------------------------
screen_routines:
        lda screen_task
        asl a                           ; a word for each task
        tax
        jmp (.loword(screen_tasks),x)            ; the task's RTS returns to the mode's caller
screen_tasks:
        .addr blank_screen_task, setup_lives_colors, draw_status_top, draw_status_bottom
        .addr show_time_up, end_screen_wait, show_lives_screen, end_screen_wait
        .addr build_column_sets, queue_area_palette, queue_backdrop_color, queue_mushroom_palette
        .addr draw_title_logo, clear_lists_draw_marker, draw_top_score
.assert * - screen_tasks = 2 * SCREEN_TASKS, error, "screen.s: screen_tasks"

; ---------------------------------------------------------------------------
; blank_screen_task: screen task 0. Every sprite leaves the picture and both
; name tables are cleared. Outside the title the frame sends the
; underground palette: its backdrop is black, which is all that a picture
; that is off shows.
;
; In:       mode
; Out:      screen_source = SOURCE_CAVE_PALETTE (not on the title);
;           screen_task + 1
; Changes:  A, X, the flags
; Original: $858B-$859A
; ---------------------------------------------------------------------------
blank_screen_task:
        jsr hide_all_sprites            ; frame.s: every sprite of sprite_list below the picture
        jsr clear_name_tables           ; frame.s: the clear record, list 1 empty, picture_scroll 0
        lda mode
        beq @next                       ; the title chooses its palette at task 9
        lda #SOURCE_CAVE_PALETTE
        sta screen_source
@next:  inc screen_task
        rts

; ---------------------------------------------------------------------------
; setup_lives_colors: screen task 1. The player colour record on a black
; backdrop with the player's own colours, never the fire colours: the
; lives screen shows the player as he starts.
;
; The original saves backdrop and player_power, sets them to 2 and 0 for
; queue_player_colors and puts them back. Here queue_colour_record gets the
; backdrop colour and the colours directly; the two variables do not
; change, as after the original's restore.
;
; In:       player
; Out:      a REC_COLOURS record at the end of screen_list_1; screen_task + 1
; Changes:  A, X, Y, the flags
; Original: $859B-$85BA
; ---------------------------------------------------------------------------
setup_lives_colors:
        ldx #LIVES_SCREEN_BACKDROP      ; backdrop colour 2: black
        ldy #MARIO_COLOURS
        lda player
        beq @record
        ldy #LUIGI_COLOURS
@record:
        jsr queue_colour_record
        inc screen_task
        rts

; ---------------------------------------------------------------------------
; draw_status_top: screen task 2. The status bar's top line (the player's
; name, WORLD, TIME, the fixed 0 of the score, the coin and the times sign)
; and the palettes of all of name table 0: text 0 of the original.
;
; Why a ROM list: text 0 sets 63 attribute bytes, the palettes of 238
; squares, 298 bytes of REC_PALETTES records: more than list 1 holds. In
; the original the text replaces list 1 from its start, nothing is added to
; list 1 after it in this frame, and source 0 then sends just the text. The
; ROM list, which drops list 1, sends the same. The name is LUIGI only in a
; two-player game with player 1 on the screen (02 section 16.1, step 4).
;
; In:       two_players, player
; Out:      screen_source = SOURCE_STATUS_TOP_MARIO or _LUIGI; screen_task + 1
; Changes:  A, X, the flags
; Original: $8652-$8659, with write_screen_text's text 0 ($8808)
; ---------------------------------------------------------------------------
draw_status_top:
        lda #SOURCE_STATUS_TOP_MARIO
        ldx two_players
        beq @source                     ; one player: MARIO
        ldx player
        beq @source
        lda #SOURCE_STATUS_TOP_LUIGI
@source:
        sta screen_source
        inc screen_task
        rts

; ---------------------------------------------------------------------------
; draw_status_bottom: screen task 3. The coin and score records of the
; player on the screen (pick_status_nybbles, 07), then the record of the
; world digit, the dash and the level digit on status bar row 3.
;
; In:       player_record: world, level (0-7, 0-3)
; Out:      the records at the end of screen_list_1; screen_task + 1
; Changes:  A, X, Y, the flags; what pick_status_nybbles changes
; Original: $865A-$8692
; ---------------------------------------------------------------------------
draw_status_bottom:
        jsr pick_status_nybbles         ; 07: the coins and the score of the player on the screen
        ldx screen_list_1_end
        lda #REC_CELLS
        sta screen_list_1 + RECORD_KIND,x
        lda #STATUS_WORLD_ROW
        sta screen_list_1 + CELLS_ROW,x
        lda #STATUS_WORLD_COLUMN
        sta screen_list_1 + CELLS_COLUMN,x
        lda #STATUS_WORLD_TILES
        sta screen_list_1 + CELLS_COUNT,x
; Tile n shows the digit n: the world and the level are shown from 1.
        lda player_record + PlayerRecord::world
        inc a
        sta screen_list_1 + CELLS_TILES,x
        lda #TILE_DASH
        sta screen_list_1 + CELLS_TILES + 1,x
        lda player_record + PlayerRecord::level
        inc a
        sta screen_list_1 + CELLS_TILES + 2,x
        lda #REC_CELLS_HEAD + STATUS_WORLD_TILES
        ldy #STATUS_WORLD_ORIGINAL_SIZE
        jsr grow_list_1
        inc screen_task
        rts

; ---------------------------------------------------------------------------
; show_time_up: screen task 4. When the time ran out (time_up): TIME UP
; (text 2), the screen timer and the picture on; task 5 waits. Else the
; wait of task 5 is skipped.
;
; In:       time_up
; Out:      time_up = 0, text 2 in list 1, screen_timer, screen_off = 0,
;           screen_task 5; or screen_task 6
; Changes:  A, X, Y, the flags
; Original: $8693-$86A7
; ---------------------------------------------------------------------------
show_time_up:
        lda time_up
        beq @skip
        stz time_up
        lda #TEXT_TIME_UP
        jmp print_and_start_timer
@skip:  lda #SCREEN_TASK_LIVES          ; past the wait of task 5
        sta screen_task
        rts

; ---------------------------------------------------------------------------
; end_screen_wait: screen tasks 5 and 7. Wait until the screen timer ends;
; then every sprite leaves the picture (the lives screen's player) and the
; screen timer starts again for the next task.
; restart_screen_timer: the screen timer at SCREEN_WAIT_STEPS slow steps,
; then the next screen task.
;
; In:       timers + TIMER_SCREEN (a slow timer)
; Out:      when it is 0: the sprites hidden, the timer = SCREEN_WAIT_STEPS,
;           screen_task + 1
; Changes:  A, X, the flags
; Original: $889D-$88AD (restart_screen_timer: $88A5)
; ---------------------------------------------------------------------------
end_screen_wait:
        lda timers + TIMER_SCREEN
        beq @end
        rts                             ; the text still shows
@end:   jsr hide_all_sprites            ; frame.s
restart_screen_timer:
        lda #SCREEN_WAIT_STEPS
        sta timers + TIMER_SCREEN
        inc screen_task
        rts

; ---------------------------------------------------------------------------
; show_lives_screen: screen task 6.
;   - The title: no lives screen; on to task 8.
;   - The game over mode: GAME OVER (text 3) and screen_timer =
;     GAME_OVER_WAIT_STEPS; the mode leaves the screen tasks.
;   - Play: the lives screen (the player's picture, text 1), the screen
;     timer and the picture on; but not after a pipe or vine entrance
;     (entrance_alt), nor after a pipe intro scene (no_lives_screen) outside
;     a castle: then on to task 8.
; print_and_start_timer: text A, the screen timer, the next screen task, the
; picture on (TIME UP and the lives screen show with the picture on).
;
; In:       mode, entrance_alt, area_type, no_lives_screen; A8 = the text
;           at print_and_start_timer
; Out:      see above
; Changes:  A, X, Y, the flags
; Original: $86A8-$86E5 (print_and_start_timer: $86C7)
; ---------------------------------------------------------------------------
show_lives_screen:
        lda mode
        beq @columns                    ; the title
        cmp #MODE_GAME_OVER
        beq @game_over
        lda entrance_alt
        bne @columns                    ; down a pipe, up a vine: no lives screen
        lda area_type
        cmp #AREA_CASTLE
        beq @lives                      ; a castle always shows it
        lda no_lives_screen
        beq @lives
@columns:                               ; no lives screen: the area after a pipe intro scene
        lda #SCREEN_TASK_COLUMNS
        sta screen_task
        rts
@game_over:
        lda #GAME_OVER_WAIT_STEPS
        sta timers + TIMER_SCREEN
        lda #TEXT_GAME_OVER
        jsr write_screen_text
        inc mode_task                   ; wait_game_over (flow.s) from the next frame
        rts
@lives: jsr draw_lives_screen_player    ; 11: the player's picture beside the lives
        lda #TEXT_LIVES
print_and_start_timer:
        jsr write_screen_text
        jsr restart_screen_timer
        stz screen_off                  ; the picture on from the next frame
        rts

; ---------------------------------------------------------------------------
; build_column_sets: screen task 8. With the picture off, one whole column
; set of the area (the builder's eight steps: four cell columns, two COLUMN
; records) and list 2 as the source. After the last of the sets that
; begin_area counts (column_sets, 11 down to $FF: 12 frames) the next task
; follows.
;
; Why the picture is off: in the original a whole set does not fit in a
; vertical blank; the frames of this task show the backdrop, and the port
; shows the same pictures.
;
; In:       parser_task (06), column_sets
; Out:      the set's records in screen_list_2; screen_source = SOURCE_LIST_2;
;           screen_off + 1; column_sets - 1; screen_task + 1 after the last
; Changes:  A, X, Y, D, the flags; what step_column_builder changes
; Original: $86E6-$86FE
; ---------------------------------------------------------------------------
build_column_sets:
        inc screen_off                  ; the next picture off
@step:  jsr step_column_builder         ; 06: one step of the area builder
        lda parser_task
        bne @step                       ; the set has steps left
        dec column_sets
        bpl @send
        inc screen_task                 ; the last set of the area start
@send:  lda #SOURCE_LIST_2
        sta screen_source
        rts

; ---------------------------------------------------------------------------
; queue_area_palette: screen task 9. The 32 colours of the area type go in
; the next frame: area_palette_sources holds the source of each area type
; (the original's area_palette_index, sources 1-4).
;
; In:       area_type (0-3)
; Out:      screen_source; screen_task + 1
; Changes:  A, X, the flags
; Original: $85BF-$85C8
; ---------------------------------------------------------------------------
queue_area_palette:
        ldx area_type
        lda area_palette_sources,x
        sta screen_source
        inc screen_task
        rts

; ---------------------------------------------------------------------------
; queue_backdrop_color: screen task 10. An area with a backdrop setting
; (4-7) sends the setting's source (backdrop_sources: list 1 for setting 4,
; the snow palettes, the castle palette); then the player colour record
; follows in list 1, and is lost with list 1 when the source is a ROM list
; (02 section 14.4, item 4).
;
; In:       backdrop (0, or 4-7)
; Out:      screen_source; screen_task + 1; queue_player_colors'
; Changes:  A, X, Y, the flags
; Original: $85E3-$85F0, falling into $85F1. The original reads its table
;           at $85C7 + backdrop, 4 bytes before it (02 L10); backdrop is 0
;           (not read) or 4-7, so only the table is read, as here.
; ---------------------------------------------------------------------------
queue_backdrop_color:
        ldx backdrop
        beq @next                       ; no setting: the area palette of task 9 stays
        lda backdrop_sources - BACKDROP_FIRST_SETTING,x ; settings 4-7
        sta screen_source
@next:  inc screen_task
; Falls into queue_player_colors.

; ---------------------------------------------------------------------------
; queue_player_colors: the player colour record at the end of list 1: the
; backdrop colour, then the three colours of sprite palette 0: Mario's,
; Luigi's, or the fire colours of either. Written from entry 16 (the
; original's $3F10), which is also entry 0, the backdrop of the picture.
;
; The backdrop: the backdrop setting's colour, or the area type's when the
; area has no setting (backdrop_colours: entries 0-3 the area types, 4-7
; the settings). The first colour of each group of the original's
; player_palettes is never shown (02 L11): player_colours holds the other
; three.
; queue_colour_record: the same record from the colours given.
;
; Callers: screen task 10, setup_entry_and_timer (04), collect_powerup and
; force_player_hurt (07); setup_lives_colors calls queue_colour_record.
;
; In:       backdrop, area_type, player, player_power
;           queue_colour_record: X8 = the backdrop colour (0-7), Y8 = the
;           colours' offset in player_colours (*_COLOURS)
; Out:      the REC_COLOURS record at the end of screen_list_1; both
;           lengths of list 1 grown
; Changes:  A, X, Y, the flags
; Keeps:    D
; Time:     about 110 cycles
; Original: $85F1-$8642
; ---------------------------------------------------------------------------
queue_player_colors:
        ldx backdrop
        bne @colours
        ldx area_type                   ; no backdrop setting: the area type's backdrop
@colours:
        ldy #FIRE_COLOURS               ; a fiery player, Mario or Luigi
        lda player_power
        cmp #POWER_FIRE
        beq queue_colour_record
        ldy #MARIO_COLOURS
        lda player
        beq queue_colour_record
        ldy #LUIGI_COLOURS
queue_colour_record:
        lda backdrop_colours,x
        ldx screen_list_1_end           ; the record goes at the end of list 1
        sta screen_list_1 + COLOURS_DATA,x
        lda player_colours,y
        sta screen_list_1 + COLOURS_DATA + 1,x
        lda player_colours + 1,y
        sta screen_list_1 + COLOURS_DATA + 2,x
        lda player_colours + 2,y
        sta screen_list_1 + COLOURS_DATA + 3,x
        lda #REC_COLOURS
        sta screen_list_1 + RECORD_KIND,x
        lda #PLAYER_COLOURS_ENTRY
        sta screen_list_1 + COLOURS_FIRST,x
        lda #PLAYER_COLOURS
        sta screen_list_1 + COLOURS_COUNT,x
        lda #REC_COLOURS_HEAD + PLAYER_COLOURS
        ldy #COLOUR_RECORD_ORIGINAL_SIZE
        jmp grow_list_1

; ---------------------------------------------------------------------------
; queue_mushroom_palette: screen task 11. An area with the mushroom ledges
; sends the mushroom palette (the backdrop and background palette 0).
;
; In:       area_style
; Out:      screen_source = SOURCE_MUSHROOM_PALETTE with style 1;
;           screen_task + 1
; Changes:  A, the flags
; Original: $8643-$8651
; ---------------------------------------------------------------------------
queue_mushroom_palette:
        lda area_style
        cmp #AREA_STYLE_MUSHROOM
        bne @next
        lda #SOURCE_MUSHROOM_PALETTE
        sta screen_source
@next:  inc screen_task
        rts

; ---------------------------------------------------------------------------
; draw_title_logo: screen task 12. On the title the title picture goes in
; the next frame: the box and the logo, the copyright, the menu texts, TOP-
; and the palettes of the title's squares (SOURCE_TITLE, from the
; original's list in the tile art, 01 section 4.1). In the other modes the
; mode moves on: its screen is ready.
;
; The original copies its title list from the tile art to $0300-$0439, over
; both write lists and the bytes after them, and sends it from there;
; screen task 13 clears those pages again. The port sends the list as a ROM
; list; list 1 is dropped by that choice, as the copy overwrote it.
;
; In:       mode
; Out:      screen_source = SOURCE_TITLE and screen_task + 1; or mode_task + 1
; Changes:  A, the flags
; Original: $86FF-$8731
; ---------------------------------------------------------------------------
draw_title_logo:
        lda mode
        bne @ready
        lda #SOURCE_TITLE
        sta screen_source
        inc screen_task
        rts
@ready: inc mode_task                   ; finish_area_setup (flow.s) from the next frame
        rts

; ---------------------------------------------------------------------------
; clear_lists_draw_marker: screen task 13, on the title only (outside it
; task 12 ends the tasks). Both lists empty, then the menu marker.
;
; The original clears $0300-$04FF: its write lists, which the port empties
; here, and the bytes that its title copy wrote over, which the port never
; writes. The other variables of those pages are 0 since the area start: on
; the title the area builder builds world 1 area 1, a ground area of the
; tree style (its header bytes $50 $21, read from the program), so it makes
; no cannon or whirlpool record, and in world 1 area 1 no pipe starts a
; piranha plant (06 section 4).
;
; In:       nothing
; Out:      screen_list_1 and screen_list_2 empty, then the marker's records
;           in list 1; screen_task + 1
; Changes:  A, X, Y, the flags
; Original: $8732-$8748
; ---------------------------------------------------------------------------
clear_lists_draw_marker:
        stz screen_list_1_end
        stz screen_list_1_original_end
        stz screen_list_2_end
        jsr draw_mushroom_icon
        inc screen_task
        rts

; ---------------------------------------------------------------------------
; draw_top_score: screen task 14, on the title only. The top score's record
; (refresh_status_number with the top score field alone, 07: its first
; digit blank when it is 0); then the title mode moves on.
;
; In:       nothing
; Out:      the record in list 1; mode_task + 1
; Changes:  A, X, Y, the flags; what refresh_status_number changes
; Original: $8749-$8751
; ---------------------------------------------------------------------------
draw_top_score:
        lda #TOP_SCORE_FIELDS
        jsr refresh_status_number       ; 07
        inc mode_task                   ; game_setup (flow.s) from the next frame
        rts

; ---------------------------------------------------------------------------
; write_screen_text: screen text A into list 1, which it replaces from its
; start. The forms of each text are ROM templates; scripts/screen_data.py
; puts the name and the warp worlds into them at build time, as the
; original's code puts them into its copy:
;
;   | Text | Forms (text_templates)                 | Then                     |
;   |------|----------------------------------------|--------------------------|
;   | 1    | the lives screen                       | the lives, world, level  |
;   | 2    | TIME UP: one player, MARIO, LUIGI      |                          |
;   | 3    | GAME OVER: one player, MARIO, LUIGI    |                          |
;   | 4-6  | the warp zone of warp_zone 4-6         | the original's length    |
;
; The name (02 section 16.1, step 4; 09 section 6.1): two players only; the
; player on the screen, but for TIME UP outside the game over mode the
; other player (02 L17, 09 Q1: lose_a_life has swapped the players when the
; other has lives; when he has none the text still names him).
;
; The original's length: texts 1-3 do not change screen_list_1_original_end,
; 0 in every frame that writes them (02 L6); texts 4-6 set it to
; WARP_TEXT_ORIGINAL_SIZE, and the records that list 1 held are lost.
;
; Callers: show_time_up, show_lives_screen; warp_zone_lock (06) with
; warp_zone 4-6.
;
; In:       A8 = the text, 1-6; two_players, player, mode; for text 1 the
;           player record (lives, world, level)
; Out:      screen_list_1 = the text; screen_list_1_end = its length
; Changes:  A, X, Y, the flags; A8 I8 at the exit
; Keeps:    D
; Time:     about 100 cycles + 7 a byte of the form (11-100 bytes)
; Original: $8808-$889C
; ---------------------------------------------------------------------------
write_screen_text:
        cmp #TEXT_LIVES
        beq write_lives_text
        cmp #TEXT_WARP_ZONE
        bcs @warp
; Texts 2 and 3: the form without the name, or with MARIO or LUIGI.
        ldx #TEMPLATE_GAME_OVER
        cmp #TEXT_TIME_UP
        bne @players
        ldx #TEMPLATE_TIME_UP
@players:
        ldy two_players
        beq copy_text_template          ; one player: no name
        inx
        inx                             ; the form with MARIO
        ldy player                      ; the name of the player on the screen
        cmp #TEXT_TIME_UP
        bne @name
        lda mode
        cmp #MODE_GAME_OVER
        beq @name
        tya
        eor #1                          ; TIME UP in the play mode: the other player
        tay
@name:  tya
        beq copy_text_template
        inx
        inx                             ; the form with LUIGI
        bra copy_text_template
; Texts 4-6: the warp zone's form with its three pipe worlds.
@warp:  sec
        sbc #TEXT_WARP_ZONE
        asl a
        clc
        adc #TEMPLATE_WARP_ZONE
        tax
        lda #WARP_TEXT_ORIGINAL_SIZE
        sta screen_list_1_original_end
; Falls into copy_text_template.

; ---------------------------------------------------------------------------
; copy_text_template: the text form X into list 1, from its start.
;
; In:       X8 = the form's word offset in text_templates (TEMPLATE_*)
; Out:      screen_list_1 = the form; screen_list_1_end = its length
; Changes:  A, X, Y, the flags; A8 I8 at the exit
; Keeps:    D
; Time:     about 60 cycles + 7 a byte (the block move)
; Original: the copy loop of $881B-$8832
; ---------------------------------------------------------------------------
copy_text_template:
        ax16
        lda f:text_template_sizes,x
        pha                             ; the length, for the list's end
        lda f:text_templates,x
        tax                             ; the form (bank 0)
        ldy #screen_list_1              ; the list's start: the text replaces the list
        lda 1,s
        dec a                           ; MVN moves A + 1 bytes
        mvn #^lives_text_records, #^screen_list_1 ; every form is host data of bank 0, as lives_text_records
        pla
        ax8
        sta screen_list_1_end           ; the low byte: a form is shorter than 256 bytes
        rts

; ---------------------------------------------------------------------------
; write_lives_text: text 1, the lives screen: its form, then the records of
; its digits (02 section 16.1, step 3). The lives shown are the lives after
; the one in play plus 1; from 10 on, the crown and the units. The
; reduction by 10 is made once only, so 19 lives or more show letter tiles
; (02 L18), as the original's 8-bit sums give.
;
; Why records after the form: the original stores the digits into its copy
; of the text; here the digit records come after the form's records, so
; the card writes the digits last: the same cells.
;
; In:       player_record: lives, world, level
; Out:      list 1 = the form and the digit records (at most 63 bytes)
; Changes:  A, X, Y, the flags
; Original: $8808-$885E, text 1
; ---------------------------------------------------------------------------
write_lives_text:
        ldx #TEMPLATE_LIVES
        jsr copy_text_template
; The lives: one cell, or the crown and the units in one record of 2.
        lda player_record + PlayerRecord::lives
        inc a
        cmp #LIVES_DECIMAL
        bcc @units
        sbc #LIVES_DECIMAL              ; the carry is set by the compare
        ldx screen_list_1_end
        sta screen_list_1 + CELLS_TILES + 1,x
        lda #TILE_CROWN
        sta screen_list_1 + CELLS_TILES,x
        lda #LIVES_CROWN_COLUMN
        sta screen_list_1 + CELLS_COLUMN,x
        lda #LIVES_CROWN_CELLS
        sta screen_list_1 + CELLS_COUNT,x
        lda #LIVES_ROW
        sta screen_list_1 + CELLS_ROW,x
        lda #REC_CELLS
        sta screen_list_1 + RECORD_KIND,x
        txa
        clc
        adc #REC_CELLS_HEAD + LIVES_CROWN_CELLS
        sta screen_list_1_end
        bra @world
@units: ldx #LIVES_ROW
        ldy #LIVES_UNITS_COLUMN
        jsr queue_one_cell
; The world and the level of the player on the screen, shown from 1.
@world: lda player_record + PlayerRecord::world
        inc a
        ldx #LIVES_WORLD_ROW
        ldy #LIVES_WORLD_COLUMN
        jsr queue_one_cell
        lda player_record + PlayerRecord::level
        inc a
        ldx #LIVES_WORLD_ROW
        ldy #LIVES_LEVEL_COLUMN
        jmp queue_one_cell

; ---------------------------------------------------------------------------
; queue_one_cell: a REC_CELLS record of one cell at the end of list 1. The
; caller counts the original's bytes when the original's list grows.
;
; In:       A8 = the tile; X8 = the cell row (0-29); Y8 = the ring column
;           (0-63)
; Out:      the record; screen_list_1_end + ONE_CELL_SIZE
; Changes:  A, X, the flags
; Keeps:    Y, D
; Time:     about 50 cycles
; Original: none
; ---------------------------------------------------------------------------
queue_one_cell:
        pha                             ; the tile
        txa
        ldx screen_list_1_end
        sta screen_list_1 + CELLS_ROW,x
        tya
        sta screen_list_1 + CELLS_COLUMN,x
        pla
        sta screen_list_1 + CELLS_TILES,x
        lda #ONE_CELL
        sta screen_list_1 + CELLS_COUNT,x
        lda #REC_CELLS
        sta screen_list_1 + RECORD_KIND,x
        txa
        clc
        adc #ONE_CELL_SIZE
        sta screen_list_1_end
        rts

; ---------------------------------------------------------------------------
; draw_world_digit: the status bar's world digit after the title's world
; select (title.s step_world_select): the digit of player_record's world,
; at the place of the original's template (world_digit_place, 01 section
; 7.1). The original copies its template over list 1 with list 1's length;
; list 1 is empty in that frame (01 L5), so adding the record is the same.
;
; In:       player_record: world
; Out:      the record at the end of list 1; both lengths of list 1 grown
; Changes:  A, X, Y, the flags
; Original: $82A9-$82B8
; ---------------------------------------------------------------------------
draw_world_digit:
        lda player_record + PlayerRecord::world
        inc a                           ; tile n shows the digit n: worlds 1-8
        ldx world_digit_place           ; the cell row
        ldy world_digit_place + 1       ; the ring column
        jsr queue_one_cell
        lda screen_list_1_original_end
        clc
        adc #WORLD_DIGIT_ORIGINAL_SIZE
        sta screen_list_1_original_end
        rts

; ---------------------------------------------------------------------------
; draw_mushroom_icon: the menu marker beside 1 PLAYER GAME or 2 PLAYER GAME:
; the three cells of column 9, rows 18-20 of name table 0. One player: the
; marker at row 18, rows 19-20 blank. Two players: rows 18-19 blank, the
; marker at row 20. The cells keep the title's palette 1.
;
; The template (menu_marker_records, from the original's
; mushroom_icon_writes) is the one-player form, three one-cell records, top
; first. For two players the first and the third tile change, as the
; original's code changes them ($0304, $0306). Like draw_world_digit, the
; records are added to the empty list 1 (01 L5).
;
; Callers: title_menu (select), screen task 13.
;
; In:       two_players
; Out:      the records at the end of list 1; both lengths grown
; Changes:  A, X, Y, the flags; A8 I8 at the exit
; Time:     about 170 cycles
; Original: $8325-$833F
; ---------------------------------------------------------------------------
draw_mushroom_icon:
        ax16
        lda screen_list_1_end
        and #$00FF                      ; the length is a byte
        clc
        adc #screen_list_1
        tay                             ; the end of list 1
        ldx #menu_marker_records
        lda #MENU_MARKER_RECORDS_SIZE - 1 ; MVN moves A + 1 bytes
        mvn #^menu_marker_records, #^screen_list_1
        ax8
        lda two_players
        beq @length
        ldx screen_list_1_end
        lda #BLANK_TILE
        sta screen_list_1 + CELLS_TILES,x ; row 18
        lda #TILE_MENU_MARKER
        sta screen_list_1 + 2 * ONE_CELL_SIZE + CELLS_TILES,x ; row 20
@length:
        lda #<MENU_MARKER_RECORDS_SIZE  ; the low byte: the constant is host data's (an import)
        ldy #MENU_MARKER_ORIGINAL_SIZE
        jmp grow_list_1

; ---------------------------------------------------------------------------
; draw_column_tiles: one metatile column of the area into list 2 as a
; REC_COLUMN record: its 13 metatiles (rows 4-29) at ring columns 2c and
; 2c + 1. The card makes each metatile's four tiles from its metatile table
; and gives the square the metatile's palette (bits 7-6), so the record
; does the work of the original's two draw_column_tiles calls and of
; write_column_attributes. List 2 is the source of the frame.
;
; Why one record for the two cell columns: the original sends them in two
; frames, but both are past the picture's right edge then (06 section 11:
; the built columns run 128 pixels ahead), so the picture is the same.
;
; The area builder (06) calls it once for each metatile column, at the
; first of the column's two drawing steps, and calls select_list_two at
; the other drawing step and at the attribute step: list 2 is then the
; source in the same five frames of each set as in the original, and
; list 1 waits in those frames as it does there (02 section 11.4).
;
; In:       A8 = the ring metatile column, 0-31 (the world's metatile column
;           mod 32); column_metatiles (06): the 13 metatiles, row 0 first
; Out:      the record at the end of screen_list_2; screen_list_2_end grown;
;           screen_source = SOURCE_LIST_2
; Changes:  A, X, Y, the flags; A8 I8 at the exit
; Keeps:    D
; Time:     about 160 cycles
; Original: $88AE-$8969
; ---------------------------------------------------------------------------
draw_column_tiles:
        ldx screen_list_2_end
        sta screen_list_2 + COLUMN_COLUMN,x
        lda #REC_COLUMN
        sta screen_list_2 + RECORD_KIND,x
        ax16
        txa
        clc
        adc #screen_list_2 + COLUMN_METATILES
        tay                             ; the record's metatiles
        ldx #column_metatiles
        lda #METATILE_ROWS - 1          ; MVN moves A + 1 bytes
        mvn #^column_metatiles, #^screen_list_2
        ax8
        lda screen_list_2_end
        clc
        adc #REC_COLUMN_SIZE
        sta screen_list_2_end
; Falls into select_list_two.

; ---------------------------------------------------------------------------
; select_list_two: list 2 is the source of this frame.
; write_column_attributes: the same. The original's attribute records of a
; set (seven bytes after its four cell columns) are the palettes that the
; set's REC_COLUMN records carry; the frame of that step still sends list 2.
;
; In:       nothing
; Out:      screen_source = SOURCE_LIST_2
; Changes:  A, the flags
; Keeps:    X, Y, D
; Original: $89BD-$89C2; write_column_attributes $896A-$89C2
; ---------------------------------------------------------------------------
write_column_attributes:
select_list_two:
        lda #SOURCE_LIST_2
        sta screen_source
        rts

; ---------------------------------------------------------------------------
; blink_block_colors: each 8th frame, the colours of background palette 3
; (the question blocks, the coins, the status bar's coin icon): the area
; type's colours, with colour 1 the next of six blink colours. The record's
; first entry, 12, is never shown (pen 0 shows the backdrop).
;
; When the original's list 1 has no room (BLINK_ROOM, in its own bytes) no
; record is added and colour_step does not move. A blink record that the
; frame drops with list 1 (a ROM list chosen in this frame) is not seen,
; and colour_step has moved (02 section 19.1).
;
; Called by game_core (flow.s) in each frame of play and of the title.
;
; In:       frame_count, area_type, colour_step, screen_list_1_original_end
; Out:      the REC_COLOURS record at the end of list 1; colour_step + 1,
;           6 becomes 0
; Changes:  A, X, Y, the flags
; Keeps:    D
; Time:     12 cycles; about 150 in a blink frame
; Original: $89E1-$8A38. The original starts its copy with Y = A = 0 from
;           the frame test (02 L9); the port writes the fields directly.
; ---------------------------------------------------------------------------
blink_block_colors:
        lda frame_count
        and #BLINK_FRAME_MASK
        bne @done                       ; not the 8th frame
        lda screen_list_1_original_end
        cmp #BLINK_ROOM
        bcs @done                       ; no room in the original's list 1
        ldx screen_list_1_end
        lda #REC_COLOURS
        sta screen_list_1 + RECORD_KIND,x
        lda blink_colours_entry         ; entry 12 ($3F0C, from the original's template)
        sta screen_list_1 + COLOURS_FIRST,x
        lda #BLINK_COLOURS
        sta screen_list_1 + COLOURS_COUNT,x
; Colours 0, 2 and 3 of the area type; colour 1 the step of the blink.
        lda area_type
        asl a
        asl a
        tay                             ; 4 colours for each area type
        lda block_palettes,y
        sta screen_list_1 + COLOURS_DATA,x
        lda block_palettes + 2,y
        sta screen_list_1 + COLOURS_DATA + 2,x
        lda block_palettes + 3,y
        sta screen_list_1 + COLOURS_DATA + 3,x
        ldy colour_step
        lda blink_colour_steps,y
        sta screen_list_1 + COLOURS_DATA + 1,x
        lda #REC_COLOURS_HEAD + BLINK_COLOURS
        ldy #BLINK_ORIGINAL_SIZE
        jsr grow_list_1
        inc colour_step                 ; the next blink colour; after the last, the first
        lda colour_step
        cmp #BLINK_STEPS
        bcc @done
        stz colour_step
@done:  rts

; ---------------------------------------------------------------------------
; queue_block_metatile: the picture of metatile A at a collision buffer
; cell, at the end of list 1: the brick with the light top line for $51 and
; $58, the brick for $52 and $5D, blank for 0, the empty block for any
; other. The square keeps its palette.
; blank_block_picture: the same with metatile 0: a block that the player
; bumps or breaks (the block object shows it while it moves).
; replace_block_picture: the same. The original also raises block_residual,
; which nothing reads (02 L16), and lowers the block's block_replace, which
; its only caller sets to 0 right after (replace_bumped_metatile, 05a
; section 17.12): the port does neither.
;
; The cell: X = its ring metatile column (0-31: the collision buffer's
; column, + 16 in the second buffer, which is name table 1), Y = its row
; offset in the buffer (16 a row: $00-$C0), as the tile probe of 07 gives
; them. Callers: bump_block_from_below, replace_bumped_metatile (07, 05a).
;
; In:       A8 = the metatile; X8, Y8 = the cell
; Out:      the REC_SQUARE record at the end of screen_list_1; both lengths
;           of list 1 grown
; Changes:  A, X, Y, the flags; A8 I8 at the exit
; Keeps:    D
; Time:     about 170 cycles
; Original: $8A6B (blank_block_picture), $8A61 (replace_block_picture),
;           $8A6D-$8A96 (queue_block_metatile, grow_list_ten_bytes)
; ---------------------------------------------------------------------------
blank_block_picture:
        lda #METATILE_EMPTY
replace_block_picture:
queue_block_metatile:
        cmp #METATILE_EMPTY
        beq @blank
        cmp #METATILE_LINED_BRICK_COINS
        beq @lined
        cmp #METATILE_LINED_BRICK
        beq @lined
        cmp #METATILE_BRICK_COINS
        beq @brick
        cmp #METATILE_BRICK
        beq @brick
        lda #BLOCK_SET_EMPTY
        bra @square
@blank: lda #BLOCK_SET_BLANK
        bra @square
@lined: lda #BLOCK_SET_LINED_BRICK
        bra @square
@brick: lda #BLOCK_SET_BRICK
@square:
        jsr metatile_square             ; X, Y = the square's cell row and ring column
; Falls into store_block_tiles.

; ---------------------------------------------------------------------------
; store_block_tiles: tile set A at a square, at the end of list 1. The
; bridge (bridge_collapse_task, 05b) takes a piece away with
; BLOCK_SET_BLANK. The original's grow_list_ten_bytes is part of it.
;
; In:       A8 = the tile set (BLOCK_SET_*, 0-4); X8 = the square's cell row
;           (even, 4-28); Y8 = its ring column (even, 0-62)
; Out:      the REC_SQUARE record at the end of screen_list_1; both lengths
;           of list 1 grown
; Changes:  A, X, Y, the flags; A8 I8 at the exit
; Keeps:    D
; Time:     about 130 cycles
; Original: $8ACD-$8B07 (store_block_tiles), $8A8F-$8A96
;           (grow_list_ten_bytes)
; ---------------------------------------------------------------------------
store_block_tiles:
        pha                             ; the tile set
        jsr square_place                ; Y16 = the place
.i16
        a16
        lda screen_list_1_end
        and #$00FF                      ; the length is a byte
        clc
        adc #screen_list_1
        tax                             ; the record's address: the end of list 1
        a8
        pla
        jsr put_square
        sep #P_X8
.i8
        lda #REC_SQUARE_SIZE
        ldy #SQUARE_ORIGINAL_SIZE
        jmp grow_list_1

; ---------------------------------------------------------------------------
; erase_coin_or_axe: a taken coin or the touched axe leaves the picture: the
; blank tile set at the cell, as the whole of list 2, which is the frame's
; source. In a water area the blank is pen 2, the water's colour (02
; section 18.1).
;
; Why the whole list: the original writes its two records at the start of
; list 2 and does not change list 2's length. List 2 is empty in that
; frame's logic (the frame's send emptied it), so its records are the whole
; list; update_scroll_vars sees list 2 chosen and adds no column in the same
; frame (02 L7).
;
; In:       X8 = the ring metatile column (0-31), Y8 = the row offset
;           ($00-$C0), as queue_block_metatile; area_type
; Out:      screen_list_2 = the REC_SQUARE record; screen_source =
;           SOURCE_LIST_2
; Changes:  A, X, Y, the flags; A8 I8 at the exit
; Keeps:    D
; Time:     about 130 cycles
; Original: $8A4D-$8A60. The original returns X = area_type (02 L7); its
;           callers load X again (05a section 17.9).
; ---------------------------------------------------------------------------
erase_coin_or_axe:
        jsr metatile_square
        jsr square_place                ; Y16 = the place
.i16
        ldx #screen_list_2              ; the record's address: the start of list 2
        lda area_type
        cmp #AREA_WATER
        bne @land
        lda #BLOCK_SET_WATER_BLANK
        bra @put
@land:  lda #BLOCK_SET_BLANK
@put:   jsr put_square
        sep #P_X8
.i8
        lda #REC_SQUARE_SIZE
        sta screen_list_2_end
        lda #SOURCE_LIST_2
        sta screen_source
        rts

; ---------------------------------------------------------------------------
; metatile_square: the square of a collision buffer cell: cell row 4 + 2 x
; the metatile row (two cell rows a metatile, under the status bar's four),
; ring column 2 x the metatile column.
;
; In:       X8 = the ring metatile column (0-31); Y8 = the row offset (16 a
;           metatile row, $00-$C0)
; Out:      X8 = the square's cell row; Y8 = its ring column
; Changes:  the flags
; Keeps:    A, D
; Time:     38 cycles
; Original: the address part of $8A97-$8ACC (write_metatile_record)
; ---------------------------------------------------------------------------
metatile_square:
        pha
        tya
        .repeat ROW_OFFSET_SHIFT
        lsr a
        .endrepeat                      ; two cell rows a metatile row
        clc
        adc #METATILE_FIRST_ROW
        pha                             ; the cell row
        txa
        asl a                           ; two ring columns a metatile column
        tay
        plx
        pla
        rts

; ---------------------------------------------------------------------------
; square_place: a square's place as the REC_SQUARE fields' word: the cell
; row (low byte) and the ring column (high byte).
;
; In:       A8 I8; X8 = the cell row; Y8 = the ring column
; Out:      Y16 = the place; A8 I16; X16 = its input, A = the cell row
; Changes:  A, Y, the flags
; Keeps:    D
; Time:     16 cycles
; Original: none
; ---------------------------------------------------------------------------
square_place:
        tya
        xba                             ; the ring column to the high byte of C
        txa                             ; the cell row to the low byte
        x16
        tay                             ; with X 16 bits, TAY copies all of C
        rts

; ---------------------------------------------------------------------------
; put_square: one REC_SQUARE record: the kind, the place and the four tiles
; of a tile set of block_square_tiles (top left, top right, bottom left,
; bottom right, the record's order).
;
; Why X holds the address: the record goes into list 1 or list 2; indexed
; stores with small offsets from X write into either.
;
; In:       A8 = the tile set (BLOCK_SET_*, 0-4); X16 = the record's address
;           (bank 0); Y16 = the place from square_place
; Out:      the record's REC_SQUARE_SIZE bytes; A8 I16
; Changes:  A, Y, the flags
; Keeps:    X, D
; Time:     about 60 cycles
; Original: $8ACD-$8B07 (the stores of store_block_tiles)
; ---------------------------------------------------------------------------
put_square:
.a8
.i16
        pha                             ; the tile set
        a16
        tya
        sta a:SQUARE_ROW,x              ; the cell row and the ring column
        a8
        pla
        asl a
        asl a                           ; SQUARE_TILE_COUNT tiles a set
        a16
        and #$00FF                      ; the set's offset is a byte
        tay
        lda block_square_tiles,y        ; top left, top right
        sta a:SQUARE_TILES,x
        lda block_square_tiles + 2,y    ; bottom left, bottom right
        sta a:SQUARE_TILES + 2,x
        a8
        lda #REC_SQUARE
        sta a:RECORD_KIND,x
        rts

; ---------------------------------------------------------------------------
; grow_list_1: count a record that a routine has written at the end of
; list 1, in the port's length and in the original's.
;
; In:       A8 = the record's bytes in the port; Y8 = its bytes in the
;           original's write list
; Out:      screen_list_1_end + A; screen_list_1_original_end + Y
; Changes:  A, the flags
; Keeps:    X, Y, D
; Time:     24 cycles
; Original: the length stores of the list 1 writers ($863F set_list_end and
;           the others)
; ---------------------------------------------------------------------------
grow_list_1:
.a8
.i8
        clc
        adc screen_list_1_end
        sta screen_list_1_end
        tya
        clc
        adc screen_list_1_original_end
        sta screen_list_1_original_end
        rts

; ---- The text forms ---------------------------------------------------------
; text_templates, text_template_sizes: the forms of texts 1-6 (TEMPLATE_*),
; host data of bank 0 (scripts/screen_data.py). In the code bank: read with
; long addressing (copy_text_template).
text_templates:
        .addr lives_text_records
        .addr time_up_alone_records, time_up_mario_records, time_up_luigi_records
        .addr game_over_alone_records, game_over_mario_records, game_over_luigi_records
        .addr warp_zone_4_records, warp_zone_5_records, warp_zone_6_records
.assert * - text_templates = TEMPLATE_WARP_ZONE + 3 * 2, error, "screen.s: text_templates and TEMPLATE_*"
text_template_sizes:
        .word LIVES_TEXT_RECORDS_SIZE
        .word TIME_UP_ALONE_RECORDS_SIZE, TIME_UP_MARIO_RECORDS_SIZE, TIME_UP_LUIGI_RECORDS_SIZE
        .word GAME_OVER_ALONE_RECORDS_SIZE, GAME_OVER_MARIO_RECORDS_SIZE, GAME_OVER_LUIGI_RECORDS_SIZE
        .word WARP_ZONE_4_RECORDS_SIZE, WARP_ZONE_5_RECORDS_SIZE, WARP_ZONE_6_RECORDS_SIZE
.assert * - text_template_sizes = TEMPLATE_WARP_ZONE + 3 * 2, error, "screen.s: text_template_sizes and TEMPLATE_*"
.assert TEMPLATE_TIME_UP + 2 * TEMPLATE_NAMED < TEMPLATE_GAME_OVER, error, "screen.s: the three forms of TIME UP"
.assert TEMPLATE_GAME_OVER + 2 * TEMPLATE_NAMED < TEMPLATE_WARP_ZONE, error, "screen.s: the three forms of GAME OVER"
