; ---------------------------------------------------------------------------
; area.s: the areas of the game: the area records, the column builder's
; steps, the enemy spawn records and the area changes.
;
; Place in the game. The original makes each column of an area during play
; from its compact area list: at each 32 pixels of scroll its column builder
; runs one "set" of eight steps, one step a frame, which builds two metatile
; columns and sends them to the picture chip. The area lists
; never change, so scripts/area_data.py runs the builder's rules at build
; time over every area list, from every start page and after every loop
; rewind, and writes for each column build of the original a record: the
; column's 13 metatiles and 13 collision buffer bytes, and its events, the
; part of the build that depends on the game at run time (an enemy start, a
; cannon record, the scroll lock...) in the original's order. This file
; keeps the original's eight steps and its counter, so every column, every
; event and every screen record happens in the frame where the original's
; does:
;   - step_column_builder: one step; build_column_sets (the screen part,
;     screen task 8) runs whole sets at an area's start, 12 frames.
;   - update_scroll_vars: the last step of game_core and of the walk
;     after a world's end: one step a frame while a set runs, or a new set
;     after each 32 pixels of scroll.
;   - load_area_pointer, find_area_byte: the area byte of a world's slot,
;     for the start of a level.
;   - load_area_addresses: begin_area: the area's header values, its
;     records and spawn records, the builder at the start page.
;   - next_spawn_record, rewind_area_objects: the enemy list reader and the
;     castle loops of the objects part (src/game/movement.s).
;
; Data in (scripts/area_data.py; its module header gives the formats and
; the ROM tables they come from; the structs below give the fields):
;   area_columns     (a data bank) each distinct column: AreaColumn
;   area_programs    (a data bank) the column records: ColumnRecord,
;                    ColumnEvent; the event routines are labels of this file
;   area_records     (a data bank) area_by_byte, the AreaRecords, the
;                    rewind tables (RewindEntry)
;   spawn_records    (a data bank) the enemy lists: SpawnRecord
;   world_area_starts, area_slots (a data bank) the original's two tables
; Data out: column_metatiles and the collision buffers (state.inc), the
; header values, the enemy slots and the other state that the events
; write (each event routine's header), the spawn_* values for the objects
; part, the COLUMN records through the screen part.
;
; The registers: DBR = bank 0, as for all the game logic. The data banks
; are read with long indexed loads (X = an offset from the blob's label;
; each blob lies in one bank). D is free: an event that starts an enemy
; sets D to the enemy's record, and build_column keeps its caller's D.
;
; Original routines: $92B0-$9CB3 (the builder and the loader of the area
; lists), $AF6F-$AF92 (update_scroll_vars), $C08C-$C0CB (send_player_back,
; its builder part), $C144-$C26B (the reading of the enemy list).
;

; ---- Values of the original program -----------------------
SOURCE_BOWSER_PALETTE = 8       ; screen_source: Bowser's palette, the axe's
AREA_TYPE_BITS  = $60           ; an area byte: bits 6-5 the type
AREA_TYPE_SHIFT = 5
AREA_NUMBER_MASK = $1F          ; bits 4-0 the list number within the type
AREA_BYTE_MASK  = $7F           ; bit 7 is read by no reader of an area byte
COLUMN_STEPS    = 8             ; the steps of a set
STEP_KIND       = 3             ; a step AND this: 3 a build, 2 a draw, 1 the second draw, 0 next_column
SET_SCROLL      = 32            ; update_scroll_vars: the pixels of scroll for each set
PAGE_COLUMNS    = 16            ; the metatile columns of a page
BUFFER_RING_COLUMNS = 32        ; the collision buffers' ring: two pages; also the ring's metatile columns
LOOP_BACK_PAGES = 4             ; send_player_back: the pages that the parser goes back
FIRST_FREE_ENEMY = 0            ; find_free_enemy_slot: enemy slots 0-4
LAST_FREE_ENEMY = 4
CASTLE_FLAG_Y   = $90           ; build_end_castle: the flag's Y on the castle
FLAG_Y          = $30           ; build_flagpole: the flag's Y at the top of the pole
FLAG_SCORE_START_Y = $B0        ; build_flagpole: the Y of the flagpole's score number
NO_WAVE         = 0             ; frenzy_queue: no request
WARP_ZONE_WORLD_1 = 4           ; warp_zone in world 1; + 1 elsewhere, + 2 in a ground area.
                                ; The same number is write_screen_text's text
OBJECT_Y_HIGH   = Object::y_pos + 1 ; y_pos: the pixel row, then Y high (state.inc)
flag_score_pixel = flag_score_y + 1 ; flag_score_y: the fraction, then the Y (state.inc)

; The kinds of the spawn records that are not enemies (the objects part names
; them too). An enemy's kind is its list byte 1 AND $3F, 0-$3F.

; ---- The forms of scripts/area_data.py ---------------------------------------
; area_columns: each distinct column of the game once.
.struct AreaColumn
        metatiles       .res ::METATILE_ROWS ; the metatiles, row 0 first (the screen's column)
        collision       .res ::METATILE_ROWS ; the collision buffer column: a metatile, or 0 for one
                                             ; that the collision tests do not see
.endstruct

; area_programs: one ColumnRecord for each column build of the original, in
; build order; the next column's record follows, or a jump event names it.
.struct ColumnRecord
        column          .word   ; bits 14-0: the column's offset in area_columns;
                                ; COLUMN_HAS_EVENTS: the events count and the events follow
        events          .byte   ; with COLUMN_HAS_EVENTS: the ColumnEvents that follow (1-255)
.endstruct
COLUMN_HAS_EVENTS = $8000
COLUMN_OFFSET   = COLUMN_HAS_EVENTS - 1
.assert COLUMN_HAS_EVENTS = $8000, error, "build_column tests COLUMN_HAS_EVENTS as the sign of the column word"
NO_EVENTS_SIZE  = ColumnRecord::events ; a record without events: its column word

.struct ColumnEvent
        routine         .word   ; the event's routine in this bank (a label of this file)
        position        .word   ; a world X (page x 256 + pixel), or an offset (the routine says)
        value           .byte   ; a Y, a length, a kind, a setting or a count (the routine says)
.endstruct

; area_records: area_by_byte (AREA_BYTES words: the offset of the AreaRecord
; of each area byte AND $7F), the AreaRecords, the rewind tables.
AREA_BYTES      = $80
START_PAGES     = 32            ; begin_area's start page, 0-31 (an entrance page has 5 bits)
.struct AreaRecord
        entrance        .byte   ; the header's entrance, 0-7
        timer_setting   .byte   ; its time setting, 0-3
        backdrop        .byte   ; its backdrop setting, 0 or 4-7
        area_style      .byte   ; its ledge style, 0-2
        cloud_override  .byte   ; its cloud flag, 0 or 3
        spawn_list      .word   ; the offset of the area's first record in spawn_records
        rewinds         .word   ; the offset of its rewind table in area_records; 0: the area has no loop
        starts          .res 2 * ::START_PAGES ; per start page: the offset in area_programs of its first
                                ; record (a page without an object: the record of backloading_never_ends)
.endstruct
; A rewind table: an entry for each record that the builder can read next
; at a loop check of the area; the search for the builder's record always
; ends in it (scripts/area_data.py, Area.add_rewinds).
.struct RewindEntry
        record          .word   ; the record that the builder reads next at the check
        after           .word   ; the record to read after the rewind
.endstruct

; spawn_records: the enemy lists, one record per entry, in list order (the
; first record of an area: AreaRecord::spawn_list). enemy_offset counts the
; records.
.struct SpawnRecord
        kind            .byte   ; the enemy kind, or SPAWN_END, SPAWN_SKIP, SPAWN_LINK
        hard_only       .byte   ; 1: the entry spawns only with hard_mode_2 (byte 1 bit 6)
        x_pos           .word   ; world X: page x 256 + column x 16
        y_pos           .byte   ; the row x 16: the Y that the reader gives the slot
        area_byte       .byte   ; a link: the area byte, all 8 bits
        link_world      .byte   ; a link: the world that it counts in
        entrance_page   .byte   ; a link: the entrance page
.endstruct
.assert .sizeof(SpawnRecord) = 8, error, "next_spawn_record: three shifts for a record"

; The data's labels and values, for scripts/area_data.py's host data.
.export COLUMN_HAS_EVENTS: absolute, SPAWN_END: absolute, SPAWN_SKIP: absolute, SPAWN_LINK: absolute
.export start_piranha_plant, record_cannon, record_whirlpool, start_castle_flag, start_jump_spring
.export start_flagpole_flag, select_bowser_palette, warp_zone_lock, toggle_scroll_lock
.export queue_wave_request, count_loop_looks, set_backdrop, clear_coin_brick_flag, place_hidden_1up
.export store_past_column, jump_to_column, backloading_never_ends

.assert collision_buffer_2 = collision_buffer_1 + COLLISION_BUFFER, error, "build_column: buffer 2 follows buffer 1"

; ---- State -------------------------------------------------------------------
.segment "AREASTATE"
column_record:  .res 2          ; the offset in area_programs of the record of the next column build:
                                ; load_area_addresses, build_column, rewind_area_objects
column_content: .res 2          ; build_column: the offset in area_columns of the column it copies;
                                ; place_hidden_1up gives it the column with the block
event_next:     .res 2          ; build_column: the offset of the next event, and after the last one
                                ; the next record (jump_to_column sets it)
event_count:    .res 1          ; build_column: the events of the record still to run
event_routine:  .res 2          ; build_column: the event's routine (call_event jumps through it)
event_position:                 ; the event's position word:
event_x:        .res 1          ;   its pixel in the page
event_page:     .res 1          ;   its page
event_value:    .res 1          ; the event's value byte
area_record:    .res 2          ; the offset in area_records of the area's AreaRecord: load_area_addresses
                                ; writes it, rewind_area_objects reads it
spawn_list:     .res 2          ; the offset in spawn_records of the area's first spawn record:
                                ; load_area_addresses writes it, next_spawn_record reads it
.segment "GAMEPLAY"

; ---------------------------------------------------------------------------
; find_area_byte: the area byte of the current player's world and area
; number (the slot in the world's play order). The game's area numbers stay
; inside the world's slots: the last slot of a world ends in the victory
; mode, which starts the next world at area 0, so no read passes the
; end of area_slots (the original would read the table after it).
;
; In:       A8 I8; player_record world (0-7) and area_index
; Out:      A = the area byte (area_slots[world_area_starts[world] + area])
; Changes:  A, X, the flags
; Keeps:    Y, D
; Time:     30 cycles
; Original: $9C13-$9C21 (its index in Y is not used by any caller)
; ---------------------------------------------------------------------------
find_area_byte:
.a8
.i8
        ldx player_record + PlayerRecord::world
        lda f:world_area_starts,x       ; the world's first slot
        clc
        adc player_record + PlayerRecord::area_index
        tax
        lda f:area_slots,x
        rts

; ---------------------------------------------------------------------------
; load_area_pointer: the current player's area: area_byte from the world and
; the area number, and its area_type. The start of a game, the next world,
; the title and its demo, a restart after a lost life and the next area
; of a level (go_to_next_area) call it.
;
; In:       A8 I8; player_record world and area_index
; Out:      area_byte; A = area_type, stored
; Changes:  A, X, the flags
; Keeps:    Y, D
; Time:     50 cycles
; Original: $9C03-$9C08
; ---------------------------------------------------------------------------
load_area_pointer:
.a8
.i8
        jsr find_area_byte
        sta area_byte
; Falls into area_type_from_byte, as the original does.

; ---------------------------------------------------------------------------
; area_type_from_byte: the area type of an area byte, bits 6-5: 0 water, 1
; ground, 2 underground, 3 castle.
;
; In:       A8 = an area byte
; Out:      A = area_type, stored
; Changes:  A, the flags
; Keeps:    X, Y, D
; Time:     20 cycles
; Original: $9C09-$9C12
; ---------------------------------------------------------------------------
area_type_from_byte:
.a8
.i8
        and #AREA_TYPE_BITS
        .repeat AREA_TYPE_SHIFT
        lsr a
        .endrepeat
        sta area_type
        rts

; ---------------------------------------------------------------------------
; load_area_addresses: the start of the area of area_byte at page parse_page
; (begin_area sets both and column_in_buffer first). The original reads
; the area list's header here and starts its parser on the list; the port
; takes the header values and the first record from page parse_page from
; the area's record: the build ran the parser, its backloading pass over the
; pages before the start page included.
;
; The builder's start: no column of the area built yet (parse_column 0,
; parser_task 0), as begin_area's memory clear leaves the original's. The
; spawn list starts at its first record (enemy_offset 0). The header values
; are those that begin_area's clear and the header leave (a
; header without a backdrop setting or the cloud flag leaves them 0).
;
; In:       A8 I8; area_byte; parse_page = the start page (0-31)
; Out:      area_type, area_slot, entrance, timer_setting, backdrop,
;           area_style, cloud_override; area_record, spawn_list,
;           enemy_offset 0; column_record = the first record from the page;
;           parse_column 0; parser_task 0
; Changes:  A, X, the flags; A8 I8 at the exit
; Keeps:    Y, D
; Time:     about 200 cycles, once for each area start
; Original: $9C22-$9CB3; the builder parts of begin_area $8FE4-$9060
; ---------------------------------------------------------------------------
load_area_addresses:
.a8
.i8
        lda area_byte
        jsr area_type_from_byte
        lda area_byte
        and #AREA_NUMBER_MASK
        sta area_slot                   ; the list number within the type
; The area's record: area_by_byte at the start of area_records.
        lda area_byte
        a16
        and #AREA_BYTE_MASK             ; also clears the high byte of C
        asl a                           ; a word for each area byte
        x16
        tax
        lda f:area_records,x
        sta area_record
        tax
        lda f:area_records + AreaRecord::spawn_list,x
        sta spawn_list
; The first record from the start page: a word for each page.
        a8
        lda parse_page
        asl a
        a16
        and #LOW_BYTE                   ; the page's word offset (C's high byte cleared)
        clc
        adc area_record
        tax
        lda f:area_records + AreaRecord::starts,x
        sta column_record
; The header values.
        ldx area_record
        a8
        lda f:area_records + AreaRecord::entrance,x
        sta entrance
        lda f:area_records + AreaRecord::timer_setting,x
        sta timer_setting
        lda f:area_records + AreaRecord::backdrop,x
        sta backdrop
        lda f:area_records + AreaRecord::area_style,x
        sta area_style
        lda f:area_records + AreaRecord::cloud_override,x
        sta cloud_override
        sep #P_X8
.i8
        stz enemy_offset
        stz parse_column
        stz parser_task
        rts

; ---------------------------------------------------------------------------
; update_scroll_vars: the area builder's step of a frame of play, the last
; step of game_core and of the walk after a world's end (victory_walk).
; A set runs one step a frame; a new set starts after each 32 pixels of
; scroll (scroll_32, which scroll_screen adds to), with list 2 empty. No
; step runs in a frame in which a coin or the axe was erased (list 2 is the
; source already: erase_coin_or_axe), so such a frame delays the builder by
; one frame.
;
; The original's scroll test is signed: a new set starts only when
; scroll_32 - 32 is 0-$7F. scroll_32 stays far below that.
;
; In:       A8 I8; screen_source, parser_task, scroll_32
; Out:      a step of the set (step_column_builder); at a new set
;           scroll_32 - 32 and screen_list_2_end 0
; Changes:  A, X, Y, D, the flags; what the step changes
; Time:     about 25 cycles without a step
; Original: $AF6F-$AF92
; ---------------------------------------------------------------------------
update_scroll_vars:
.a8
.i8
        lda screen_source
        cmp #SOURCE_LIST_2
        beq @done                       ; a coin or axe erase took list 2 this frame
        lda parser_task
        bne step_column_builder         ; a set runs: its next step
        lda scroll_32
        sec
        sbc #SET_SCROLL
        bpl @new_set                    ; the original's signed test (bmi after cmp)
@done:
.a8
.i8
        rts
@new_set:
.a8
.i8
        sta scroll_32
        stz screen_list_2_end           ; list 2 starts empty with each set
; Falls into step_column_builder: the set's first step.

; ---------------------------------------------------------------------------
; step_column_builder: one step of the set, by parser_task (the table in
; this file's header). parser_task is 8 during the first step and counts
; down; after the last step (0) it is 0 again and list 2 is the source once
; more (the original's attribute records).
;
; parser_task is read by enemies_and_loops: in the frame after step 7
; (parser_task 7) no free enemy slot reads the spawn list.
;
; In:       A8 I8; parser_task (0 between sets)
; Out:      the step's work; parser_task - 1
; Changes:  A, X, Y, D, the flags; what the step changes
; Time:     about 40 cycles + the step's
; Original: $92B0-$92C7, run_column_task $92C8-$92DA
; ---------------------------------------------------------------------------
; The eight steps of a set (parser_task counts 8 down to 1 during the
; steps, 0 between sets):
;
;   | Step | parser_task | Work (original)                | Here                       |
;   |------|-------------|--------------------------------|----------------------------|
;   | 7    | 8           | build_column, an even column   | build_column: a record     |
;   | 6    | 7           | draw_column_tiles, left half   | draw_column_tiles: COLUMN  |
;   | 5    | 6           | draw_column_tiles, right half  | select_list_two            |
;   | 4    | 5           | next_column                    | next_column                |
;   | 3    | 4           | build_column, the odd column   | build_column: a record     |
;   | 2    | 3           | draw_column_tiles, left half   | draw_column_tiles: COLUMN  |
;   | 1    | 2           | draw_column_tiles, right half  | select_list_two            |
;   | 0    | 1           | next_column                    | next_column                |
;   | (after step 0)     | write_column_attributes        | select_list_two            |
;
; Each drawing step and the attribute step make list 2 the frame's screen
; source, as the original's write select 6 does: list 1 waits in the same
; five frames of each set. The COLUMN record carries both
; cell columns and their palettes (src/packet_layout.inc), so the second
; drawing step and the attribute step send no record of their own: the
; original's two cell columns go out in two frames, but both are past the
; picture's right edge then (the built columns run 128 pixels ahead).
;
step_column_builder:
.a8
.i8
        lda parser_task
        bne @counted
        lda #COLUMN_STEPS
        sta parser_task                 ; a set starts
@counted:
.a8
.i8
        dec a                           ; this step: 7 down to 0
        and #STEP_KIND
        asl a
        tax
        jsr (.loword(column_steps),x)   ; the table is in this bank: ld65 wants its 16-bit address
        dec parser_task
        bne @done
        jmp select_list_two             ; screen.s: after the set's last step, list 2 (the attributes)
@done:
.a8
.i8
        rts

; The work of each step, by step AND STEP_KIND.
column_steps:
        .addr next_column               ; steps 4 and 0
        .addr select_list_two           ; steps 5 and 1: the right cell column is in the COLUMN record
        .addr draw_area_column          ; steps 6 and 2
        .addr build_column              ; steps 7 and 3

; ---------------------------------------------------------------------------
; next_column: the parser moves to the next column of the area: the next
; column of the page, or column 0 of the next page; the collision buffer
; column follows in the ring of 32.
;
; In:       A8 I8; parse_column, parse_page, column_in_buffer
; Out:      the same, one column on
; Changes:  A, the flags
; Keeps:    X, Y, D
; Time:     about 30 cycles
; Original: $92DB-$92F6
; ---------------------------------------------------------------------------
next_column:
.a8
.i8
        lda parse_column
        inc a
        and #PAGE_COLUMNS - 1
        sta parse_column
        bne @buffer
        inc parse_page                  ; past column 15: the next page
@buffer:
.a8
.i8
        lda column_in_buffer
        inc a
        and #BUFFER_RING_COLUMNS - 1
        sta column_in_buffer
        rts

; ---------------------------------------------------------------------------
; draw_area_column: the COLUMN record of the column that the step before
; built, at its ring column: the collision buffer column, which is the
; world's metatile column mod 32, as in the ring.
;
; In:       A8 I8; column_in_buffer; column_metatiles
; Out:      draw_column_tiles' (screen.s): the record; list 2 the source
; Changes:  A, X, Y, the flags
; Keeps:    D
; Time:     about 170 cycles
; Original: $88AE-$8969 (draw_column_tiles, the left half's call)
; ---------------------------------------------------------------------------
draw_area_column:
.a8
.i8
        lda column_in_buffer
        jmp draw_column_tiles           ; screen.s: In A = the ring metatile column

; ---------------------------------------------------------------------------
; build_column: the column of the parser, as the original builds it at steps
; 7 and 3: its events in the original's order, then its 13 metatiles into
; column_metatiles (draw_column_tiles sends them at the next step; the
; collision part reads them past its buffers) and its 13 collision bytes
; into the collision buffer column of column_in_buffer. The events come
; first, as in the original, whose object routines run before the column's
; store into the collision buffer.
;
; A record: its column word (the column's offset in area_columns; bit 15
; COLUMN_HAS_EVENTS: an event count and the events follow), the events of 5
; bytes each. The next record follows the last event, unless a jump event
; names another one (jump_to_column sets event_next). Each event's routine
; runs with its position in event_position, its value in event_value, A8 I8,
; and may change any register, D included.
;
; The collision buffers: two of 13 rows of 16 columns, buffer 2 right after
; buffer 1 (state.inc); buffer column b (0-31) is column b AND 15 of buffer
; b / 16, its row r at 16 r. The two buffers form a ring of two pages, so
; four pages back (a loop rewind) is the same place.
;
; In:       A8 I8; column_record; column_in_buffer
; Out:      the events done; column_metatiles; the collision buffer column;
;           column_record = the next record
; Changes:  A, X, Y, the flags; what the events change
; Keeps:    D
; Time:     about 330 cycles (the copy: 26 long reads and stores, 250), about
;           90 more for each event, and the events' own; at most two builds
;           a frame (screen task 8), else one in four frames of a set
; Original: $93FC-$9503 (build_column, fill_terrain_rows); the run-time
;           parts of the object routines are the event routines
; ---------------------------------------------------------------------------
; Merged and split against the original:
; - The parser (read_area_objects, dispatch_area_object,
;   start_or_run_object), the object routines' drawing, fill_column_rows,
;   the scenery and the terrain run at build time; their run-time work
;   is the events below. build_column is the record's copy and its events;
;   the original's collision store (fill_terrain_rows' end) is the copy of
;   the record's collision column.
; - The events are the run-time parts of build_vertical_pipe (the piranha
;   plant), build_cannon_stack and build_pit (the records), build_end_castle
;   (the castle flag), place_jump_spring, build_flagpole (the flag),
;   build_axe (Bowser's palette), warp_zone_lock, toggle_scroll_lock,
;   queue_wave_request, dispatch_area_object (the loop command's looks),
;   change_scenery_and_color (the backdrop), build_coin_brick (its flag),
;   build_hidden_extra_life (the block when its flag is set), and
;   fill_column_rows' store past the column buffer (store_past_column).
; - The two draw_column_tiles steps of a column are one COLUMN record and
;   one select_list_two (the screen part, src/game/screen.s).
; - step_enemy_list, step_list_two, step_list_three: one record of the port's
;   list (the objects part's step_spawn_record).
; - send_player_back's builder part (the parse page, the area list's
;   place, page and page flag) is rewind_area_objects.
; - The original's column address ($0720-$0721) is the ring column of the
;   COLUMN record: column_in_buffer, the parse column mod 32.
;
build_column:
.a8
.i8
        phd
        ax16
        ldx column_record
        lda f:area_programs + ColumnRecord::column,x
        bmi @events                     ; COLUMN_HAS_EVENTS
        sta column_content
        txa
        clc
        adc #NO_EVENTS_SIZE             ; the next record: right after the column word
        bra @next
@events:
.a16
.i16
        and #COLUMN_OFFSET
        sta column_content
        txa
        clc
        adc #.sizeof(ColumnRecord)
        sta event_next                  ; the first event
        a8
        lda f:area_programs + ColumnRecord::events,x
        sta event_count
; The events, in the original's order.
@event:
.a8
.i16
        ldx event_next
        a16
        lda f:area_programs + ColumnEvent::routine,x
        sta event_routine
        lda f:area_programs + ColumnEvent::position,x
        sta event_position
        txa
        clc
        adc #.sizeof(ColumnEvent)
        sta event_next
        a8
        lda f:area_programs + ColumnEvent::value,x
        sta event_value
        sep #P_X8
.i8
        jsr call_event
        x16
        dec event_count
        bne @event
        a16
        lda event_next                  ; past the last event, or the jump's record
@next:
.a16
.i16
        sta column_record
; The column: its metatiles for the screen part, its collision bytes for the
; collision tests. Y = the collision buffer column's offset from buffer 1.
        lda column_in_buffer
        and #BUFFER_RING_COLUMNS - 1    ; (the high byte of the word read is cleared)
        cmp #PAGE_COLUMNS
        bcc @buffer_1
        adc #COLLISION_BUFFER - PAGE_COLUMNS - 1 ; buffer 2: the carry is set, so - 1
@buffer_1:
.a16
.i16
        tay
        ldx column_content
        a8
        .repeat METATILE_ROWS, row
        lda f:area_columns + AreaColumn::metatiles + row,x
        sta column_metatiles + row
        .endrepeat
        .repeat METATILE_ROWS, row
        lda f:area_columns + AreaColumn::collision + row,x
        sta collision_buffer_1 + PAGE_COLUMNS * row,y
        .endrepeat
        sep #P_X8
.i8
        pld
        rts

; ---------------------------------------------------------------------------
; call_event: the jump to the event's routine, so that build_column can JSR
; to an address from its data: the routine's RTS returns to build_column.
; JMP (abs) reads the address from bank 0 (event_routine) and jumps within
; this bank, where the routines are.
;
; In:       A8 I8; event_routine, event_position, event_value
; Out:      the event's
; Changes:  what the event changes
; Time:     5 cycles + the event's
; Original: none
; ---------------------------------------------------------------------------
call_event:
.a8
.i8
        jmp (event_routine)

; ---------------------------------------------------------------------------
; start_piranha_plant: the piranha plant of a vertical pipe, at the pipe's
; left column, in the first free enemy slot 0-4; none when all five are in
; use. The first area of world 1 (world and area number both 0) has no
; plants; so have the areas that its pipes lead to, where the area number
; stays 0. The plant's start (start_piranha) sets its
; speed and its low and high Y.
;
; In:       A8 I8; event_position = the plant's world X (the pipe's middle);
;           event_value = its Y (the pipe's top row)
; Out:      the slot: x_pos, Y high, active, y_pos, kind, then
;           start_piranha's values
; Changes:  A, X, Y, D, the flags
; Time:     about 150 cycles
; Original: $98F2-$9924 (build_vertical_pipe)
; ---------------------------------------------------------------------------
start_piranha_plant:
.a8
.i8
        lda player_record + PlayerRecord::world
        ora player_record + PlayerRecord::area_index
        beq @done                       ; world 1, its first area: no plants
        jsr find_free_enemy_slot
        bcs @done                       ; slots 0-4 in use: no plant
        a16
        lda event_position
        sta Object::x_pos
        a8
        lda #Y_HIGH_SCREEN
        sta OBJECT_Y_HIGH
        lda #ENEMY_ACTIVE
        sta Object::active
        lda event_value
        sta Object::y_pos
        lda #KIND_PIRANHA
        sta Object::kind
        jmp start_piranha ; D = the plant's record
@done:
.a8
.i8
        rts

; ---------------------------------------------------------------------------
; record_cannon, record_whirlpool: a cannon's or a whirlpool's record in
; cannon_page, cannon_x and cannon_y at cannon_next, which moves on. The
; cannons (build_cannon_stack) use the records 0-5; the whirlpools
; (build_pit, the first column of a pit in a water area) go back to record
; 0 after record 4. run_cannons and pull_in_whirlpools read them.
;
; In:       A8 I8; event_position = the cannon's world X, or the
;           whirlpool's left edge (one column left of the pit);
;           event_value = the cannon top's Y, or the whirlpool's length in
;           pixels ((L + 2) x 16, a byte)
; Out:      the record; cannon_next
; Changes:  A, X, the flags
; Keeps:    Y, D
; Time:     about 60 cycles
; Original: $9A85-$9AA4 (build_cannon_stack), $9B4B-$9B72 (build_pit)
; ---------------------------------------------------------------------------
record_cannon:
.a8
.i8
        lda #CANNONS
        bra store_record
record_whirlpool:
.a8
.i8
        lda #WHIRLPOOLS
; Falls into store_record. A = the records that it counts.
store_record:
.a8
.i8
        pha
        ldx cannon_next
        lda event_value
        sta cannon_y,x
        lda event_page
        sta cannon_page,x
        lda event_x
        sta cannon_x,x
        inx
        txa
        cmp 1,s                         ; past the last record of its kind
        bcc @keep
        lda #0                          ; back to the first record
@keep:
.a8
        sta cannon_next
        pla
        rts

; ---------------------------------------------------------------------------
; start_castle_flag: the flag on the castle at the end of a level, at the
; castle's middle column (not on page 0, where a level starts at a castle).
; It takes the first free enemy slot 0-4, and slot 5 when all five are in
; use: the original does not test find_free_enemy_slot's carry here, so the flag then writes over the power-up or the flagpole flag.
;
; In:       A8 I8; event_position = the flag's world X
; Out:      the slot: x_pos, Y high, active, y_pos, kind
; Changes:  A, D, the flags
; Keeps:    X, Y
; Time:     about 90 cycles
; Original: $984B-$9868 (build_end_castle)
; ---------------------------------------------------------------------------
start_castle_flag:
.a8
.i8
        jsr find_free_enemy_slot        ; slot 5 when none is free
        a16
        lda event_position
        sta Object::x_pos
        lda #Y_HIGH_SCREEN * 256 + CASTLE_FLAG_Y
        sta Object::y_pos               ; Y high and Y
        a8
        lda #ENEMY_ACTIVE
        sta Object::active
        lda #KIND_STAR_FLAG
        sta Object::kind
        rts

; ---------------------------------------------------------------------------
; start_jump_spring: a jump spring, an enemy in the first free enemy slot
; 0-4, or slot 5 when all five are in use (as start_castle_flag). Its
; rest Y is its Y. Its active byte goes up by 1: it is 2 when the spring
; takes slot 5 from an active object.
;
; In:       A8 I8; event_position = the spring's world X; event_value = its Y
; Out:      the slot: x_pos, y_pos, spring_rest_y, kind, Y high, active + 1
; Changes:  A, D, the flags
; Keeps:    X, Y
; Time:     about 100 cycles
; Original: $9AD6-$9AF3 (place_jump_spring)
; ---------------------------------------------------------------------------
start_jump_spring:
.a8
.i8
        jsr find_free_enemy_slot        ; slot 5 when none is free
        a16
        lda event_position
        sta Object::x_pos
        a8
        lda event_value
        sta Object::y_pos
        sta Object::spring_rest_y
        lda #KIND_SPRING
        sta Object::kind
        lda #Y_HIGH_SCREEN
        sta OBJECT_Y_HIGH
        inc Object::active
        rts

; ---------------------------------------------------------------------------
; start_flagpole_flag: the flag of the flagpole, always in enemy slot 5,
; 8 pixels left of the pole, at its top; the flagpole's score number starts
; at Y $B0. Its active byte goes up by 1. Its Y high is not written: it
; keeps what slot 5 held (0 after the area's start, or what a
; power-up in slot 5 left).
;
; In:       A8 I8; event_position = the flag's world X
; Out:      slot 5: x_pos, y_pos (its pixel row), kind, active + 1;
;           flag_score_pixel
; Changes:  A, D, the flags
; Keeps:    X, Y
; Time:     about 70 cycles
; Original: $99B1-$99CF (build_flagpole)
; ---------------------------------------------------------------------------
start_flagpole_flag:
.a8
.i8
        a16
        lda #special_object
        tcd                             ; enemy slot 5
        lda event_position
        sta Object::x_pos
        a8
        lda #FLAG_Y
        sta Object::y_pos               ; the pixel row only
        lda #FLAG_SCORE_START_Y
        sta flag_score_pixel
        lda #KIND_FLAG
        sta Object::kind
        inc Object::active
        rts

; ---------------------------------------------------------------------------
; select_bowser_palette: the axe's column: the next frame sends Bowser's
; palette (source 8). Like every ROM list, it drops the
; frame's list 1 records.
;
; In:       A8 I8
; Out:      screen_source = SOURCE_BOWSER_PALETTE
; Changes:  A, the flags
; Keeps:    X, Y, D
; Time:     12 cycles
; Original: $9A09-$9A0D (build_axe)
; ---------------------------------------------------------------------------
select_bowser_palette:
.a8
.i8
        lda #SOURCE_BOWSER_PALETTE
        sta screen_source
        rts

; ---------------------------------------------------------------------------
; warp_zone_lock: a warp zone: warp_zone gets its number (4 in world 1, 6 in
; a ground area of another world, else 5; enter_pipe_check reads its
; pipes' worlds by it), the warp zone text with its three world digits goes
; into list 1 from its start (write_screen_text; the records that list 1
; held are lost), the piranha plants go, and the scroll lock flips.
;
; In:       A8 I8; player_record world; area_type
; Out:      warp_zone; list 1 = the text; the plants' slots free;
;           scroll_lock bit 0 flipped
; Changes:  A, X, Y, the flags
; Keeps:    D
; Time:     about 300 cycles + the text's copy
; Original: $96F2-$970C
; ---------------------------------------------------------------------------
warp_zone_lock:
.a8
.i8
        ldx #WARP_ZONE_WORLD_1
        lda player_record + PlayerRecord::world
        beq @number
        inx                             ; 5: another world
        lda area_type
        cmp #AREA_GROUND
        bne @number
        inx                             ; 6: a ground area of another world
@number:
        stx warp_zone
        txa
        jsr write_screen_text           ; screen.s: texts 4-6, the warp zone of warp_zone
        lda #KIND_PIRANHA
        jsr clear_enemies_of_kind
; Falls into toggle_scroll_lock, as the original does.

; ---------------------------------------------------------------------------
; toggle_scroll_lock: the scroll lock's bit 0 flips. While it is set the
; screen does not scroll.
;
; In:       A8 I8
; Out:      scroll_lock
; Changes:  A, the flags
; Keeps:    X, Y, D
; Time:     14 cycles
; Original: $970D-$9715
; ---------------------------------------------------------------------------
toggle_scroll_lock:
.a8
.i8
        lda scroll_lock
        eor #SCROLL_LOCKED
        sta scroll_lock
        rts

; ---------------------------------------------------------------------------
; queue_wave_request: a wave object: frenzy_queue gets the wave's enemy kind,
; or no request while an enemy slot 0-4 holds that kind. The search reads
; the kind bytes only, so a free slot that keeps the kind counts too. read_enemy_spawns starts the request in the next free slot.
;
; In:       A8 I8; event_value = the wave's kind (wave_kinds: $14, $17, $18)
; Out:      frenzy_queue
; Changes:  A, D, the flags
; Keeps:    X, Y
; Time:     about 150 cycles
; Original: $972B-$973F
; ---------------------------------------------------------------------------
queue_wave_request:
.a8
.i8
        a16
        lda #enemy_objects + LAST_FREE_ENEMY * OBJECT_PAGE
@look:
.a16
.i8
        tcd                             ; enemy slots 4 down to 0
        a8
        lda Object::kind
        cmp event_value
        beq @running                    ; an enemy of the kind: no new wave
        a16
        tdc
        sec
        sbc #OBJECT_PAGE
        cmp #enemy_objects + FIRST_FREE_ENEMY * OBJECT_PAGE
        bcs @look
        a8
        lda event_value
        bra @queue
@running:
.a8
.i8
        lda #NO_WAVE
@queue:
.a8
.i8
        sta frenzy_queue
        rts

; ---------------------------------------------------------------------------
; count_loop_looks: the looks at a castle maze's loop command object in this
; column. Each time that a free object slot of the parser looks at it, even
; before its column, loop_command goes up by 1; the build
; counts the column's looks. The loop check (check_loop) runs while
; loop_command is not 0 and clears it.
;
; In:       A8 I8; event_value = the looks (1-255)
; Out:      loop_command + the looks (a byte)
; Changes:  A, the flags
; Keeps:    X, Y, D
; Time:     20 cycles
; Original: $95D4-$95DC (dispatch_area_object)
; ---------------------------------------------------------------------------
; Original address: $95DA.
count_loop_looks:
.a8
.i8
        lda loop_command
        clc
        adc event_value
        sta loop_command
        rts

; ---------------------------------------------------------------------------
; set_backdrop: a scenery change object with a backdrop setting (4-7). The
; build applies the foreground, the background and the terrain of the
; scenery changes; only the backdrop is read at run time
; (queue_backdrop_color at the area's start, queue_player_colors later).
; The lists change the backdrop only at page 0 column 6, in the area's
; first 24 columns, so the start's screen task 10 sends it.
;
; In:       A8 I8; event_value = the setting
; Out:      backdrop
; Changes:  A, the flags
; Keeps:    X, Y, D
; Time:     12 cycles
; Original: $96E2-$96F1 (change_scenery_and_color)
; ---------------------------------------------------------------------------
; Original address: $96E9.
set_backdrop:
.a8
.i8
        lda event_value
        sta backdrop
        rts

; ---------------------------------------------------------------------------
; clear_coin_brick_flag: a brick with coins: the flag that starts the coin
; time at its first bump is clear again.
;
; In:       A8 I8
; Out:      coin_brick_flag = 0
; Changes:  nothing else
; Keeps:    A, X, Y, D
; Time:     10 cycles
; Original: $9B14-$9B18 (build_coin_brick)
; ---------------------------------------------------------------------------
clear_coin_brick_flag:
.a8
.i8
        stz coin_brick_flag
        rts

; ---------------------------------------------------------------------------
; place_hidden_1up: a hidden 1-up block: it is in the column only while the
; current player's hidden 1-up flag is set, and the flag then clears, so a
; later hidden 1-up block of the player's game is not built until the flag
; is set again. The build makes the column with the block
; too; build_column copies that one.
;
; In:       A8 I8; event_position = the offset in area_columns of the
;           column with the block; player_record hidden_1up
; Out:      with the flag set: column_content = that column, the flag 0
; Changes:  A, the flags
; Keeps:    X, Y, D
; Time:     about 30 cycles
; Original: $9B01-$9B0D (build_hidden_extra_life)
; ---------------------------------------------------------------------------
place_hidden_1up:
.a8
.i8
        lda player_record + PlayerRecord::hidden_1up
        beq @done
        stz player_record + PlayerRecord::hidden_1up
        a16
        lda event_position
        sta column_content
        a8
@done:
.a8
.i8
        rts

; ---------------------------------------------------------------------------
; store_past_column: a mushroom ledge at row 11: the original draws its stem
; from row 13, one byte past its 13-byte column buffer, into the byte after
; it: hammer_owner of misc slot 0 gets the stem's metatile.
; Its values (an enemy number 0-5, or this one) never meet a rule of
; fill_column_rows that keeps a byte, so the store always happens. In the
; game it happens in three columns of world 4-3. The collision part reads
; the same byte past its buffers.
;
; In:       A8 I8; event_value = the metatile
; Out:      misc slot 0's hammer_owner
; Changes:  A, the flags
; Keeps:    X, Y, D
; Time:     12 cycles
; Original: $9B9D (fill_column_rows' store, from build_cap_ledge $97A8)
; ---------------------------------------------------------------------------
store_past_column:
.a8
.i8
        lda event_value
        sta misc_objects + Object::hammer_owner
        rts

; ---------------------------------------------------------------------------
; jump_to_column: the next record is elsewhere: a stream of records from a
; start page or after a loop rewind goes on in the stream from page 0 where
; both make the same columns, and the stream from page 0 goes back three
; pages after its last object, where its columns repeat. It is the last
; event of its record: build_column takes event_next as the next record.
;
; In:       A8 I8; event_position = the offset in area_programs of the next
;           record
; Out:      event_next
; Changes:  A, the flags
; Keeps:    X, Y, D
; Time:     20 cycles
; Original: none
; ---------------------------------------------------------------------------
jump_to_column:
.a8
.i8
        a16
        lda event_position
        sta event_next
        a8
        rts

; ---------------------------------------------------------------------------
; backloading_never_ends: the first column of an area that starts at a page
; without an object. The original's parser skips the objects of the pages
; before the start page in its first column and stops at the first object
; of the start page; with none there it repeats that pass forever, and the
; game stops in screen task 8 with the picture off. The
; start pages that the game's tables give all have objects (the build
; asserts it). Another page comes only from an entrance page that outlives
; a lost life: return_to_game does not clear entrance_alt;
; player_enters_area clears it at the end of an entry, so a
; life lost during an entry would restart the level's area at that page,
; and in a two-player game the other player's area; the timer and the
; enemy contacts take no life then. The
; port stops in the same frame as the original.
;
; In:       nothing
; Out:      never returns
; Changes:  nothing
; Time:     never ends
; Original: $9508-$9588 (read_area_objects' repeated pass)
; ---------------------------------------------------------------------------
backloading_never_ends:
        bra backloading_never_ends

; ---------------------------------------------------------------------------
; find_free_enemy_slot: the first enemy slot 0-4 whose active byte is 0;
; slot 5 (the special slot) when all five are in use.
;
; In:       A8 I8
; Out:      D = the slot's record; carry clear for a free slot, set for
;           slot 5
; Changes:  A, D, the flags
; Keeps:    X, Y
; Time:     about 40 cycles + 30 for each slot in use
; Original: $994A-$9956
; ---------------------------------------------------------------------------
find_free_enemy_slot:
.a8
.i8
        a16
        lda #enemy_objects + FIRST_FREE_ENEMY * OBJECT_PAGE
@look:
.a16
.i8
        tcd
        a8
        lda Object::active
        beq @free
        a16
        tdc
        clc
        adc #OBJECT_PAGE
        cmp #special_object
        bcc @look                       ; slots 0-4
        tcd                             ; none free: slot 5, the carry set by the compare
        a8
        rts
@free:
.a8
.i8
        clc
        rts
.assert special_object = enemy_objects + (LAST_FREE_ENEMY + 1) * OBJECT_PAGE, error, "find_free_enemy_slot: slot 5 follows slots 0-4"

; ---------------------------------------------------------------------------
; clear_enemies_of_kind: every enemy slot 0-4 whose kind is A becomes free
; (its active byte 0). warp_zone_lock removes the piranha plants with it,
; the flagpole's grab (grab_climbable) the cannons' bullet bills.
;
; In:       A8 I8; A = the kind
; Out:      the slots of that kind free
; Changes:  the flags
; Keeps:    A, X, Y, D
; Time:     about 170 cycles
; Original: $9716-$9727 (it leaves A = 0 and X = $FF; no caller reads them)
; ---------------------------------------------------------------------------
clear_enemies_of_kind:
.a8
.i8
        pha                             ; the kind, compared on the stack
        phd
        a16
        lda #enemy_objects + LAST_FREE_ENEMY * OBJECT_PAGE
@look:
.a16
.i8
        tcd                             ; enemy slots 4 down to 0
        a8
        lda Object::kind
        cmp 3,s                         ; the kind, under the saved D
        bne @next
        stz Object::active
@next:
.a8
.i8
        a16
        tdc
        sec
        sbc #OBJECT_PAGE
        cmp #enemy_objects + FIRST_FREE_ENEMY * OBJECT_PAGE
        bcs @look
        a8
        pld
        pla
        rts

; ---------------------------------------------------------------------------
; next_spawn_record: the spawn record that enemy_offset names in the area's
; list, for read_enemy_spawns. The build resolved the enemy list's
; page rules: each record has its page,
; and a page skip that the reader takes is a record of kind SPAWN_SKIP,
; where slot 5 stops as at the original's page skip.
;
; In:       A8 I8; enemy_offset (the record's number in the list), spawn_list
; Out:      spawn_kind (the enemy kind, or SPAWN_END, SPAWN_SKIP,
;           SPAWN_LINK), spawn_hard_only (1: only with hard_mode_2), spawn_x
;           (word: page x 256 + column x 16), spawn_y (row x 16), and for a
;           link spawn_area_byte, spawn_link_world, spawn_entrance_page
; Changes:  A, X, the flags; A8 I8 at the exit
; Keeps:    Y, D
; Time:     about 110 cycles
; Original: $C144-$C24F (the list reads of read_enemy_spawns), with
;           step_enemy_list $C250-$C26B
; ---------------------------------------------------------------------------
next_spawn_record:
.a8
.i8
        lda enemy_offset
        ax16
        and #LOW_BYTE                   ; the record's number (C's high byte cleared)
        .repeat 3
        asl a                           ; x .sizeof(SpawnRecord)
        .endrepeat
        clc
        adc spawn_list
        tax
        lda f:spawn_records + SpawnRecord::x_pos,x
        sta spawn_x
        a8
        lda f:spawn_records + SpawnRecord::kind,x
        sta spawn_kind
        lda f:spawn_records + SpawnRecord::hard_only,x
        sta spawn_hard_only
        lda f:spawn_records + SpawnRecord::y_pos,x
        sta spawn_y
        lda f:spawn_records + SpawnRecord::area_byte,x
        sta spawn_area_byte
        lda f:spawn_records + SpawnRecord::link_world,x
        sta spawn_link_world
        lda f:spawn_records + SpawnRecord::entrance_page,x
        sta spawn_entrance_page
        sep #P_X8
.i8
        rts

; ---------------------------------------------------------------------------
; rewind_area_objects: the area builder's part of send_player_back, at
; a missed loop of a castle maze: the parse page goes back 4 pages, and the
; builder goes on with the records after the rewind. The original sets its
; list place to the check's rewind offset with the area object page 4 back
; and the page flag clear, and keeps its object slots; the
; build ran that from every state that the builder can be in at a check.
; The record that the builder reads next names that state: at a check
; before the build of the check column (between two sets) it is that
; column's record, after the build (the frames after step 7) the next
; column's. The area's rewind table holds each such record with the record
; after the rewind; the search always ends in it (scripts/area_data.py,
; Area.add_rewinds). The collision buffer column stays: four pages are two
; laps of the buffers' ring and of the picture's.
;
; In:       A8 I8; X = the check (not needed: the record names it);
;           column_record, area_record, parse_page
; Out:      parse_page - 4; column_record = the record after the rewind
; Changes:  A, X, the flags; A8 I8 at the exit
; Keeps:    Y, D
; Time:     about 60 cycles + 30 for each entry before the record's
; Original: $C093-$C09B, $C0AE-$C0B6, $C0BC, $C0C5-$C0CA (send_player_back)
; ---------------------------------------------------------------------------
rewind_area_objects:
.a8
.i8
        lda parse_page
        sec
        sbc #LOOP_BACK_PAGES
        sta parse_page
        ax16
        ldx area_record
        lda f:area_records + AreaRecord::rewinds,x
        tax                             ; the area's rewind table
@look:
.a16
.i16
        lda f:area_records + RewindEntry::record,x
        cmp column_record
        beq @found
        txa
        clc
        adc #.sizeof(RewindEntry)
        tax
        bra @look
@found:
.a16
.i16
        lda f:area_records + RewindEntry::after,x
        sta column_record
        ax8
        rts
