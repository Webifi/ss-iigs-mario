; The player (document 04): the player's routine of each frame (the player
; tasks), the control under the pad, the moves (the walk, the run, the
; jump, the swim, the climb), the scroll that the player pushes, the entry
; into each area, the pipes, the vine, the flagpole, the walk into the
; castle, the size changes, the death, the fire flower's flash, the throw
; of a fireball and the star's colours.
;
; Place in the game. game_core (src/game/flow.s) runs once each frame of
; play, and in the title's demo, in the order of document 03 section 5.2.
; It calls from this file:
;   step 2    run_player_task: the routine of player_task; in control it
;             moves the player and scrolls the screen
;   step 4    throw_fireball, from run_fireballs_and_bubbles
;             (src/game/objects.s), while the player is fiery
;   step 16   update_star_palette
;   step 17   remember_ab_buttons, which runs on into update_scroll_vars
;             (step 18)
; The victory walk (src/game/flow.s, 03 section 6.3) calls
; auto_control_player, scroll_screen and update_scroll_vars; begin_area
; (03 section 4.4) calls set_screen_edges.
;
; What comes in: the pad of the player on the screen (pad_bits + 0, from
; the frame and game_core), the results of the tile test of the frame
; before (the player's state and side bits, src/game/collision.s), the
; spring and lift values (05b), the timers (the frame, 02 section 4).
; What goes out: the player's record (place, speeds, state, box kind,
; sprite attributes), the screen's edges and the picture's scroll, the
; sound commands (snd_*_queue: they play from the next frame, because the
; sound program runs before the game logic, 02 section 2), the area
; changes (mode_task, entrance_alt), the next routine (player_task).
; No hardware: the card draws, the sound part plays, the frame reads the
; pads.
;
; Numbers. The X position is the record's fraction byte and its word x_pos
; (page x 256 + pixel); the Y position is the fraction byte and the word
; y_pos (Y high x 256 + row). The player's X speed is the word at
; x_speed_fraction: the signed byte x_speed (1/16 pixel each frame), which
; moves him, over its fraction byte, which only carries the friction
; steps (04 "Number forms"). The Y speed is the signed 8.8 word y_speed.
; The original works on these one byte at a time, with the carry from
; byte to byte; each 16-bit add or subtract here gives the same bytes and
; the same carries, and the header of each routine says where.
;
; Routines (the original's name and address in each header; merged or
; split where the job is one step; move_player_sideways and
; move_player_up_down, which the moves here call, are src/game/movement.s's,
; with move_object_sideways and apply_gravity):
;   run_player_task        the player's routine of this frame
;   setup_entry_and_timer  task 0: the player's place at an area's start, the timer
;   player_enters_area     task 7: the fall, the pipe intro, the rise, the vine
;   auto_control_player    control_player with a pad byte of its own
;   control_player         task 8: one frame of the player under the pad
;   vine_ride_up           task 1: the climb out of the top of the screen
;   begin_alt_entry        the next area: the player rises from below
;   enter_pipe_down        task 3: down into a pipe
;   shift_player_y         move the player's row by a signed amount
;   enter_pipe_sideways    task 2: into a side pipe
;   wait_pipe_timer        the area changes when the pipe's count ends
;   switch_area_mode       the picture off, the play mode starts an area
;   walk_into_side_pipe    the walk into a side pipe
;   size_change_task       task 9: the player grows
;   injury_blink_task      task 10: the player shrinks, then moves
;   start_size_change      the grow or shrink picture starts
;   death_task             task 11: the player hangs, then falls
;   finish_player_task     back to the control task
;   fire_flower_task       task 12: the flash of the fire colours
;   flash_player_palette   the player's sprite palette from A
;   reset_player_palette   the player's sprite palette 0
;   slide_down_pole        task 4: the slide down the flagpole
;   end_level_walk         task 5: the walk into the castle
;   go_to_next_area        the next area of the world
;   move_by_player_state   the crouch, the forces, the move of the state
;   move_on_ground         the walk
;   move_jump_or_swim      the jump's gravity, the swim
;   move_falling           the fall
;   move_sideways_in_air   the move in the air
;   move_climbing          the climb
;   start_jump_or_stroke   the start of a jump or a stroke
;   set_climb_speed        the climb speed
;   set_player_forces      the climb speed, or the start of a jump or stroke
;   set_sideways_limits    the speed and friction classes; with
;                          pick_speed_limits, their limits and friction
;   pick_anim_rate         the walk picture's rate; the stop of a turn
;                          (with store_anim_rate)
;   apply_friction         the X speed by the pad and the friction (with
;                          store_abs_speed)
;   decide_scroll_amount   the player's push on the screen
;   scroll_screen          the screen moves right
;   hold_player_in_screen  the player stays between the screen's edges
;   set_screen_edges       the right edge from the left edge
;   update_star_palette    the star's colours (game_core step 16)
;   remember_ab_buttons    A and B for the next frame's press tests
;   update_scroll_vars     the column builder after 32 pixels of scroll
;   throw_fireball         a fireball leaves the fiery player's hand
;
; Register widths: A8 I8 at each entry and exit unless a header says
; otherwise; 16-bit work between a16 and a8 inside a routine. DBR = bank 0.
; D = the player's record (player_object) in every routine that takes no
; other record; run_player_task sets it. The routines of other parts that
; this file calls keep D (each call below says what it expects).
;
; ---- The player's record (src/game/state.inc Object, D = player_object) ---
;
; | Field            | Meaning for the player                    | Writers here           |
; |------------------|-------------------------------------------|------------------------|
; | state            | the player's state (table below)          | setup_entry_and_timer, |
; |                  |                                           | player_enters_area,    |
; |                  |                                           | vine_ride_up,          |
; |                  |                                           | start_jump_or_stroke;  |
; |                  |                                           | 07                     |
; | direction        | the move direction: 1 right, 2 left       | control_player,        |
; |                  |                                           | pick_anim_rate         |
; | attributes       | bits 0-1 palette, bit 5 behind the        | setup_entry_and_timer, |
; |                  | background                                | control_player,        |
; |                  |                                           | end_level_walk, the    |
; |                  |                                           | palette routines       |
; | box              | the hit box kind (BOX_PLAYER_*, 07)       | control_player         |
; | collision        | the side bits of the tile test (07): bit  | setup_entry_and_timer; |
; |                  | 0 right, 1 left, 2 down, 3 up free: the   | 07                     |
; |                  | pad's bits, so a pad byte AND it gives    |                        |
; |                  | the free ways                             |                        |
; | x_fraction       | X: 1/256 pixel                            | move_object_sideways   |
; | x_pos            | X: page x 256 + pixel                     | setup_entry_and_timer, |
; |                  |                                           | move_climbing,         |
; |                  |                                           | hold_player_in_screen; |
; |                  |                                           | 05a, 07                |
; | y_fraction       | Y: 1/256 pixel                            | start_jump_or_stroke,  |
; |                  |                                           | move_climbing; 05a     |
; | y_pos            | Y: Y high x 256 + row (Y high 0 above, 1  | setup_entry_and_timer, |
; |                  | on, 2 and more below the screen)          | shift_player_y,        |
; |                  |                                           | move_climbing; 05a, 07 |
; | x_speed_fraction | the X speed's fraction (04                | apply_friction,        |
; |                  | player_x_fraction)                        | pick_anim_rate; 07     |
; | x_speed          | the X speed, signed, 1/16 pixel each      | apply_friction,        |
; |                  | frame                                     | pick_anim_rate,        |
; |                  |                                           | walk_into_side_pipe,   |
; |                  |                                           | hold_player_in_screen; |
; |                  |                                           | 07, 03                 |
; | y_speed          | the Y speed, signed 8.8, + is down        | set_climb_speed,       |
; |                  |                                           | start_jump_or_stroke;  |
; |                  |                                           | 05a, 05b, 07           |
;
; ---- The player's state (Object::state) ------------------------------------
;
; | State            | Move               | Set by                               |
; |------------------|--------------------|--------------------------------------|
; | PLAYER_ON_GROUND | move_on_ground     | the tile test's landing (07); a lift |
; |                  |                    | (05b); setup_entry_and_timer         |
; | PLAYER_JUMPING   | move_jump_or_swim  | start_jump_or_stroke; the tile test  |
; |                  |                    | under water (07)                     |
; | PLAYER_FALLING   | move_falling       | the tile test on land (07): a state  |
; |                  |                    | 0 or 3 before its floor test         |
; | PLAYER_CLIMBING  | move_climbing      | the vine and pole grab (07);         |
; |                  |                    | setup_entry_and_timer,               |
; |                  |                    | player_enters_area, vine_ride_up     |
;
; A frame's move uses the state that the tile test of the frame before left.
;
; ---- The player tasks (player_task, PLAYER_TASK_*) --------------------------
;
; | Task           | Routine               | Started by                   | Next      |
; |----------------|-----------------------|------------------------------|-----------|
; | ENTRANCE_SETUP | setup_entry_and_timer | the area start (0 after the  | ENTRANCE  |
; |                |                       | clear); return_to_game (03)  |           |
; | VINE_CLIMB     | vine_ride_up          | the vine grab above Y $20    | an area   |
; |                |                       | (07)                         | change    |
; | SIDE_PIPE      | enter_pipe_sideways   | the side pipe in control (07)| an area   |
; |                |                       |                              | change    |
; | DOWN_PIPE      | enter_pipe_down       | down on a pipe's top (07)    | an area   |
; |                |                       |                              | change    |
; | FLAGPOLE       | slide_down_pole       | the pole grab (07)           | END_LEVEL |
; | END_LEVEL      | end_level_walk        | the flag down (05b), or no   | the next  |
; |                |                       | flag                         | area      |
; | LOSE_LIFE      | lose_a_life (03)      | control_player: deep enough, | 03        |
; |                |                       | the death song over          |           |
; | ENTRANCE       | player_enters_area    | ENTRANCE_SETUP               | CONTROL   |
; | CONTROL        | control_player        | ENTRANCE, the timed tasks    | 1-4, 6,   |
; |                |                       |                              | 9-12      |
; | CHANGE_SIZE    | size_change_task      | a power-up when small (07)   | CONTROL   |
; | INJURY         | injury_blink_task     | a hurt when big (07)         | CONTROL   |
; | DEATH          | death_task            | a hurt when small, the time  | LOSE_LIFE |
; |                |                       | out (07)                     |           |
; | FIRE_FLOWER    | fire_flower_task      | a power-up when big (07)     | CONTROL   |
;
; The timed tasks start with timer_hold = $FF (07 set_player_routine); the
; frame counts it down before the game logic, so the task sees $FF - k on
; its k-th frame and acts at fixed values (04 "Frame counts of the timed
; tasks").
;
; ---- This part's variables (GAMESTATE, below) -------------------------------
;
; | Name             | Size | Meaning                     | Writers         | Readers         |
; |------------------|------|-----------------------------|-----------------|-----------------|
; | gravity_down     | 1    | the fall gravity: 1/256     | setup_entry_    | move_falling,   |
; |                  |      | pixel each frame, added to  | and_timer,      | move_jump_or_   |
; |                  |      | the Y speed each frame      | start_jump_     | swim            |
; |                  |      |                             | or_stroke       |                 |
; | friction         | 2    | the friction: 1/4096 pixel  | pick_speed_     | apply_friction  |
; |                  |      | each frame, added to the    | limits          |                 |
; |                  |      | word at x_speed_fraction    |                 |                 |
; | max_left_speed   | 1    | the X speed's limit to the  | pick_speed_     | apply_friction  |
; |                  |      | left (negative)             | limits          |                 |
; | max_right_speed  | 1    | the limit to the right      | pick_speed_     | apply_friction  |
; |                  |      |                             | limits          |                 |
; | jump_halt_height | 1    | 0 from an area's start, 1   | start_jump_     | move_jump_or_   |
; |                  |      | from its first jump or      | or_stroke       | swim            |
; |                  |      | stroke on (04's RAM table   |                 |                 |
; |                  |      | lists 1; the area start     |                 |                 |
; |                  |      | clears it, 03 section 4.7)  |                 |                 |
;
; Like the original's, they are 0 after every area start (begin_area's
; clear, 03 section 4.7), as are the bytes of state.inc that this file
; writes, but those that the area start keeps: entrance_alt, player_small,
; pad_override, no_lives_screen, timer_reload and the player record.
;
; ---- The tables (scripts/player_data.py, bank 0) ----------------------------
;
; | Label                   | Entries, form                     | Index          | Original |
; |-------------------------|-----------------------------------|----------------|----------|
; | gravity_held_by_kind    | 7 bytes: the gravity while A is   | the jump kind  | $B424    |
; |                         | held in a rise                    |                |          |
; | gravity_fall_by_kind    | 7 bytes: the fall gravity         | the jump kind  | $B42B    |
; | jump_start_speeds       | 7 words: the start Y speed, 8.8   | 2 x the kind   | $B432,   |
; |                         |                                   |                | $B439    |
; | left_speed_limits       | 3 bytes: the X speed's limit left | the speed class| $B440    |
; | right_speed_limits      | 4 bytes: right; 3: the entry walk | the speed class| $B443    |
; | friction_by_class       | 3 words: the friction             | 2 x the class  | $B447    |
; | climb_speeds            | 3 words: the climb's Y speed, 8.8 | 2 x still, up, | $B44A,   |
; |                         |                                   | down           | $B44D    |
; | anim_rate_by_speed      | 3 bytes: frames per walk picture  | the class      | $B58C    |
; | vine_side_shifts        | 4 words: the signed X shift to    | 2 x the shift  | $B3C7,   |
; |                         | the vine's other side             | index          | $B3CB    |
; | edge_x_inset            | 2 words: pixels inside the edge   | EDGE_*         | $B034    |
; | edge_return_pad         | 2 words: the pad's bit back in    | EDGE_*         | $B036    |
; | hidden_life_coin_goals  | 8 bytes: coins for the hidden 1-up| the world      | $B2C2    |
; | start_x_by_entry        | 4 bytes: X in the page            | entrance_alt   | $9116    |
; | alt_entry_y_index       | 2 bytes: the start row of         | entrance_alt-2 | $911A    |
; |                         | entrance_alt 2 and 3              |                |          |
; | start_y_by_entry        | 9 bytes: the start row's Y        | the start row  | $911C    |
; | start_priority_by_entry | 9 bytes: its sprite attributes;   | the start row  | $9125,   |
; |                         | row 8 is the byte the original    |                | $912D    |
; |                         | reads past its 8 (04 leftover 7)  |                |          |
;
; Original: $AF3B-$AF66 (the star step of game_core), $AF67-$B623 (the end
; of the frame of play, the scroll, the player tasks, control and the
; physics; play_mode and the rest of game_core are src/game/flow.s),
; $9131-$91BC (setup_entry_and_timer), $B62B-$B663 (the throw, in
; run_fireballs_and_bubbles).

.a8
.i8

.assert FACING_RIGHT = PAD_RIGHT && FACING_LEFT = PAD_LEFT, error, "the facing is the pad's direction bit"

; ---- Values of the player part (document 04; the shared ones are in state.inc)
GRAVITY_AREA_START = $28        ; gravity_down at an area's start, until the first jump or stroke
GRAVITY_WATER_TOP = $18         ; gravity_up of a swimmer above the water's top
GRAVITY_DEATH   = $28           ; gravity_up in the death fall
JUMP_SWIM_FRAMES = $20          ; the stroke timer at a jump or a stroke (timers + TIMER_JUMP_SWIM)
RUN_HOLD_FRAMES = $0A           ; the run limits stay this long after B (timers + TIMER_RUNNING)
CLIMB_SIDE_FRAMES = $18         ; frames between two shifts to the vine's other side (TIMER_CLIMB_SIDE)
JUMP_HALT_PIXELS = 1            ; jump_halt_height from the first jump or stroke of an area on
JUMP_KIND_SLOW  = 0             ; the jump kind below JUMP_KIND_1_SPEED
JUMP_KIND_1_SPEED = $09         ; the jump kinds 1-4 start at these speeds (player_speed_abs):
JUMP_KIND_2_SPEED = $10         ;   1/16 pixel each frame
JUMP_KIND_3_SPEED = $19
JUMP_KIND_4_SPEED = $1C
JUMP_KIND_SWIM  = 5             ; the swim stroke's entry in the jump tables
JUMP_KIND_WHIRLPOOL = 6         ; the stroke in a whirlpool
AIR_RUN_SPEED   = $19           ; in the air the run limits hold from this speed on
STRONG_FRICTION_SPEED = $21     ; the strong friction class from this speed on
ANIM_FAST_SPEED = $1C           ; the fast walk picture, and running_speed, from this speed on
ANIM_MIDDLE_SPEED = $0E         ; the middle walk picture from this speed on
TURN_STOP_SPEED = $0B           ; below this speed a button but A stops a turn at once
SPEED_CLASS_RUN = 0             ; the indexes of left_speed_limits and right_speed_limits
SPEED_CLASS_WALK = 1
SPEED_CLASS_WATER = 2
SPEED_CLASS_ENTRY = 3           ; right_speed_limits only: the walk of the entry (task 7)
FRICTION_RUN    = 0             ; the indexes of friction_by_class (words): class 0, 1, 2
FRICTION_WALK   = 2
FRICTION_STRONG = 4
ANIM_CLASS_FAST = 0             ; the indexes of anim_rate_by_speed
ANIM_CLASS_MIDDLE = 1
ANIM_CLASS_SLOW = 2
CLIMB_STILL     = 0             ; the indexes of climb_speeds (words)
CLIMB_UP        = 2
CLIMB_DOWN      = 4
CLIMB_RATE_UP   = 8             ; player_anim_rate in the climb: up, and still or down
CLIMB_RATE      = 4
SHIFT_RIGHT_HELD = 0            ; vine_side_shifts: the right-held pair (words),
SHIFT_LEFT_HELD = 2 * 2         ;   the left-held pair,
SHIFT_FACING_LEFT = 1 * 2       ;   + this when the player faces left
WATER_TOP_Y     = $14           ; above this row a stroke does not rise
WATER_PAD_LIMIT_Y = $D0         ; under water the pad is off from this row down
FRONT_FROM_Y    = $40           ; from this row down control puts the player in front of the background
ENTRY_FALL_Y    = $30           ; above this row the entry is a fall with no pad
PIPE_RISE_END_Y = $91           ; the rise out of a pipe ends above this row
PIPE_RISE_STEP  = $FF           ; shift_player_y: one row up (signed -1)
PIPE_SINK_STEP  = 1             ;   one row down
VINE_GROWN      = $60           ; vine_height when the entrance vine has grown (05a section 11)
VINE_CLIMB_END_Y = $99          ; the entrance climb stops above this row
VINE_STEP_OFF_X = $48           ; the step off the entrance vine ends at this X in the page
VINE_ENTRY_FLOOR = $08          ; the metatile under the entrance vine: any metatile but 0 is a
                                ;   floor for the feet (07 section 4); the original stores it with
                                ;   the A that then is the pad's up bit (04 task 7)
VINE_ENTRY_CELL = 11 * 16 + 4   ; its place: metatile row 11, column 4 of collision_buffer_1
VINE_ENTRY_BLOCK = 0            ; the block object that the entrance vine grows from (start_vine's X)
VINE_ENTRY_BLOCK_Y = $F0        ; that block's row, below the screen's bottom
VINE_EXIT_Y     = $E4           ; the vine ride ends above this row of the page above the screen
SIDE_PIPE_SPEED = 8             ; the walk into a side pipe: half a pixel each frame
COLUMN_PIXELS   = $0F           ; the pixel inside a 16-pixel metatile column
POLE_BOTTOM_Y   = $9E           ; the slide down the pole holds down above this row
POLE_FOOT_Y     = $AE           ; from this row on the walk has left the pole
END_WALK_FLAG_UP = 5            ; star_flag_task when the castle's flag is up (05b)
HIDDEN_1UP_LEVEL = 3            ; the next level (0-3) at whose start the coins of the level that
                                ;   ends can set the hidden 1-up: the world's fourth
FALL_DEPTH      = 4             ; Y high of the exit below the screen: a cloud area, the death task
FALL_DEPTH_SONG = 6             ; the exit of a fall into a hole, whose song starts here
TILE_TEST_OFF   = 1             ; no_collisions: the tile test is off (any value but 0, 07)
SMALL_FLIP      = 1             ; player_small XOR this: the other size (1 small, 0 big)
SCROLL_START_X  = $50           ; the screen follows a push from this screen X on
SCROLL_FULL_X   = $70           ;   by the whole push from this one on, one pixel less before it
SCREEN_RIGHT_OFFSET = $FF       ; the screen's right edge, right of its left edge
RING_WIDTH      = 512           ; the two name tables side by side: picture_scroll's ring (02 section 1)
EDGE_LEFT       = 0             ; the word index of the left edge: screen_left, edge_x_inset,
EDGE_RIGHT      = 2             ;   edge_return_pad; the right edge's (screen_right)
EDGE_RIGHT_ZONE = 16            ; the right edge holds a player less than 16 pixels left of it
                                ;   (screen X 240-255): the column bits of find_x_offscreen
                                ;   (11 section 5) have bit 5 set for exactly these dR 0-15
STAR_MUSIC_TIMER = 4            ; star_timer on the frame where the area song comes back
STAR_FAST_FLASH = 8             ; the star flashes each 2 frames from this star_timer on, else each 8
GROW_START_HOLD = $F8           ; timer_hold values of the timed tasks: the grow starts (frame 7),
GROW_END_HOLD   = $C4           ;   it ends (frame 59)
SHRINK_START_HOLD = $F0         ;   the shrink starts (frame 15),
SHRINK_END_HOLD = $C8           ;   it ends (frame 55)
DEATH_FALL_HOLD = $F0           ;   the death's fall starts below this (frame 16)
FLOWER_END_HOLD = $C0           ;   the fire flower's flash ends (frame 63)
FIREBALL_SLOT_MASK = FIREBALL_SLOTS - 1 ; fireball_count AND this: the slot of the next throw

; The layouts that the 16-bit work of this file reads (state.inc):
.assert Object::x_speed = Object::x_speed_fraction + 1, error, "the X speed word"
.assert Object::y_pos = Object::y_fraction + 1, error, "move_climbing's Y word"
.assert Object::y_speed_whole = Object::y_speed + 1, error, "y_speed: fraction, whole"
.assert screen_right = screen_left + EDGE_RIGHT, error, "hold_player_in_screen's screen_left,y"
.assert FIREBALL_SLOTS = 2, error, "throw_fireball's slot: bit 0 of fireball_count"

.segment "AREASTATE"
; This part's variables: the table in the file header. All are 0 after an
; area start, as in the original.
gravity_down:   .res 1          ; the fall gravity (setup_entry_and_timer, set_player_forces; the falls)
friction:       .res 2          ; the friction word (pick_speed_limits; apply_friction)
max_left_speed: .res 1          ; the X speed limits (pick_speed_limits; apply_friction)
max_right_speed: .res 1
jump_halt_height: .res 1        ; 0, or 1 after an area's first jump (set_player_forces; move_jump_or_swim)

.segment "GAMEPLAY"

; ---------------------------------------------------------------------------
; run_player_task: the player's routine of this frame: the routine of
; player_task (the task table of the file header), entered with D = the
; player's record.
;
; In:       A8 I8; player_task (PLAYER_TASK_*); any D
; Out:      A8 I8; the task's results; D = the player's record, or as
;           lose_a_life (src/game/flow.s) leaves it
; Changes:  A, X, Y, D
; Keeps:    DBR
; Time:     each frame of play: 24 cycles, then the task
; Original: $B04A-$B068 (run_player_task); the original's jump routine
;           leaves registers and scratch bytes that only
;           setup_entry_and_timer's bubble reads (03 L1): see there.
; ---------------------------------------------------------------------------
run_player_task:
.a8
.i8
        pea player_object
        pld                             ; D = the player's record
        lda player_task
        asl a
        tax
        jmp (.loword(player_tasks),x)   ; JMP (abs,X) reads its table from this bank
player_tasks:                           ; in PLAYER_TASK_* order
        .addr setup_entry_and_timer
        .addr vine_ride_up
        .addr enter_pipe_sideways
        .addr enter_pipe_down
        .addr slide_down_pole
        .addr end_level_walk
        .addr lose_a_life               ; src/game/flow.s (03 section 4.12)
        .addr player_enters_area
        .addr control_player
        .addr size_change_task
        .addr injury_blink_task
        .addr death_task
        .addr fire_flower_task
.assert PLAYER_TASK_ENTRANCE_SETUP = 0 && PLAYER_TASK_VINE_CLIMB = 1, error, "player_tasks order"
.assert PLAYER_TASK_SIDE_PIPE = 2 && PLAYER_TASK_DOWN_PIPE = 3, error, "player_tasks order"
.assert PLAYER_TASK_FLAGPOLE = 4 && PLAYER_TASK_END_LEVEL = 5, error, "player_tasks order"
.assert PLAYER_TASK_LOSE_LIFE = 6 && PLAYER_TASK_ENTRANCE = 7, error, "player_tasks order"
.assert PLAYER_TASK_CONTROL = 8 && PLAYER_TASK_CHANGE_SIZE = 9, error, "player_tasks order"
.assert PLAYER_TASK_INJURY = 10 && PLAYER_TASK_DEATH = 11, error, "player_tasks order"
.assert PLAYER_TASK_FIRE_FLOWER = 12, error, "player_tasks order"

; ---------------------------------------------------------------------------
; setup_entry_and_timer: task 0, the first frame of play in each area: the
; player's place and look by the way he enters (entrance_alt) and the
; area's entrance kind (entrance), the game timer when a fresh time is
; due (reload_game_timer), the vine of a vine entrance, the bubble of a
; water area. Then the entry task.
;
; The start row: the area's entrance kind (0-7) for entrance_alt 0 and 1,
; a fixed row for 2 and 3 (alt_entry_y_index). Row 8, entrance_alt 2 (the
; rise out of a pipe or up a vine), has the attribute byte that the
; original reads one past its 8-row table: the player rises behind the
; background (04 leftover 7, 03 L2; the builder takes that byte into row
; 8 of start_priority_by_entry).
;
; The game timer is reload_game_timer's (src/game/score.s, 07 section 14):
; the original's clear of star_timer there is left out, because the area
; start cleared every timer and nothing sets star_timer before this frame
; (03 L10).
;
; In:       D = the player's record; entrance_alt (0-3), entrance (0-7),
;           pad_override, area_type, screen_left; the side bits 0 (the
;           area start's clear)
; Out:      the player's record (page, X, Y, attributes, state, side bits);
;           player_facing, gravity_down, swimming, the halfway page;
;           reload_game_timer's; player_task = PLAYER_TASK_ENTRANCE; D =
;           the player's record
; Changes:  A, X, Y
; Keeps:    D, DBR
; Time:     once per area start: 138-202 cycles (measured on random states),
;           and the calls
; Original: $9131-$91BC (setup_entry_and_timer). Not kept: the original's
;           state 0 before its state 3 of a vine entrance (one store here),
;           and the decrement of the side bits that the area start cleared:
;           they become $FF (04 leftover 9).
; ---------------------------------------------------------------------------
setup_entry_and_timer:
.a8
.i8
; The place: the page of the screen's left edge and the start X of the way
; in; on the screen at the start row's Y, with its attribute byte.
        lda screen_left+1
        sta Object::x_pos+1             ; the page
        ldx entrance_alt
        lda start_x_by_entry,x
        sta Object::x_pos               ; the pixel in the page
        ldy entrance                    ; the start row: the entrance kind for alt 0 and 1,
        cpx #ENTRANCE_ALT_RISE
        bcc @row
        ldy alt_entry_y_index-ENTRANCE_ALT_RISE,x ; a fixed row for 2 and 3
@row:
        lda start_y_by_entry,y
        sta Object::y_pos
        lda #Y_HIGH_SCREEN
        sta Object::y_pos+1
        lda start_priority_by_entry,y   ; row 8: the rise's $20 (04 leftover 7)
        sta Object::attributes
        lda #FACING_RIGHT
        sta player_facing
; The state: on the ground, or on the vine after a vine ride.
        ldx #PLAYER_ON_GROUND
        lda pad_override
        beq @state
        ldx #PLAYER_CLIMBING
@state:
        stx Object::state
        lda #SIDES_FREE                 ; every way free (04 leftover 9)
        sta Object::collision
        lda #GRAVITY_AREA_START
        sta gravity_down
        stz player_record+PlayerRecord::halfway_page ; lose_a_life sets it again (03)
; Under water the player swims (swimming 1).
        stz swimming
        lda area_type
        bne @land                       ; not AREA_WATER (0)
        inc swimming
@land:
        jsr queue_player_colors         ; the player's colours (02 section 14.3)
        jsr reload_game_timer           ; the time, when one is due (src/game/score.s, 07 section 14)
; A vine entrance: block 0 takes the player's column and a row below the
; screen; the vine grows from it in enemy slot 5 (05a section 11).
        lda pad_override
        beq @no_vine
        pea block_objects
        pld                             ; D = block object 0
        jsr set_block_place
        lda #VINE_ENTRY_BLOCK_Y
        sta Object::y_pos               ; its row
        pea special_object
        pld                             ; D = enemy slot 5
        ldx #VINE_ENTRY_BLOCK           ; from block object 0
        jsr start_vine
@no_vine:
; A water area: a bubble leaves the player's mouth. The original calls the
; bubble's start with the values that the code before leaves: bubble 0,
; and the rate index $91 that its jump routine left, which reads the
; entrance's wait and first rise past the bubble's tables (03 L1, 04
; leftover 8, 05a L4). BUBBLE_ENTRANCE is that pair's entry.
        lda area_type
        bne @no_bubble                  ; not AREA_WATER (0)
        pea bubble_objects
        pld                             ; D = bubble 0
        lda #BUBBLE_ENTRANCE
        jsr launch_bubble
@no_bubble:
        pea player_object
        pld
        lda #PLAYER_TASK_ENTRANCE
        sta player_task
        rts
.assert AREA_WATER = 0, error, "setup_entry_and_timer tests area_type for 0"

; ---------------------------------------------------------------------------
; player_enters_area: task 7, the entry, each frame until it is done. The
; cases, in the original's order:
;   - entrance_alt 2 without pad_override: the rise out of a pipe, one row
;     a frame, with no control, until the player is above row $91;
;   - entrance_alt 2 with pad_override: the vine. Nothing until it has
;     grown; then the climb (state 3, no tile test, a floor metatile put
;     under the vine) while the player is at row $99 or lower; above it
;     the step off to the right with the tile test, until X $48;
;   - above row $30: the fall, control with no pad;
;   - the pipe intro (entrance 6 or 7): the walk right; once the side pipe
;     puts the player behind the background (07), into it, and the next
;     area at the end of the pipe's count, without the lives screen;
;   - else ready at once.
; Ready: control (task 8) from the next frame, facing right, a normal
; entry for the next area, the tile test on, no pad override.
;
; In:       D = the player's record; entrance_alt, entrance, pad_override,
;           vine_height, area_change_timer
; Out:      the player moved; the values above
; Changes:  A, X, Y (and control_player's)
; Keeps:    D, DBR
; Time:     each frame of the entry: 31-840 cycles (measured on random
;           states), with the control and without the calls of other parts
; Original: $B069-$B0E5 (player_enters_area)
; ---------------------------------------------------------------------------
player_enters_area:
.a8
.i8
        lda entrance_alt
        cmp #ENTRANCE_ALT_RISE
        beq @rise
        lda Object::y_pos
        cmp #ENTRY_FALL_Y
        bcs @not_falling
        lda #PAD_NONE                   ; from the top: he falls in
        jmp auto_control_player
@not_falling:
        lda entrance
        cmp #ENTRANCE_PIPE_INTRO        ; 6 or 7: the field has 3 bits (06, the area header)
        bcc @ready
        lda Object::attributes
        bne @into_pipe
        lda #PAD_RIGHT                  ; the walk to the pipe
        jmp auto_control_player
@into_pipe:
        jsr walk_into_side_pipe
        dec area_change_timer
        bne @done
        inc no_lives_screen
        jmp go_to_next_area
@rise:
        lda pad_override
        bne @vine
        lda #PIPE_RISE_STEP
        jsr shift_player_y
        lda Object::y_pos
        cmp #PIPE_RISE_END_Y
        bcc @ready
        rts
@vine:
        lda vine_height
        cmp #VINE_GROWN
        bne @done
        lda Object::y_pos
        cmp #VINE_CLIMB_END_Y
        bcc @step_off
        lda #PLAYER_CLIMBING
        sta Object::state
        lda #TILE_TEST_OFF
        sta no_collisions
        lda #VINE_ENTRY_FLOOR
        sta collision_buffer_1+VINE_ENTRY_CELL
        lda #PAD_UP
        bra @control
@step_off:
        stz no_collisions
        lda #PAD_RIGHT
@control:
        jsr auto_control_player
        lda Object::x_pos
        cmp #VINE_STEP_OFF_X
        bcc @done
@ready:
        lda #PLAYER_TASK_CONTROL
        sta player_task
        lda #FACING_RIGHT
        sta player_facing
        stz entrance_alt                ; ENTRANCE_ALT_NORMAL
        stz no_collisions
        stz pad_override
@done:
        rts
.assert ENTRANCE_ALT_NORMAL = 0, error, "player_enters_area clears entrance_alt"

; ---------------------------------------------------------------------------
; auto_control_player: control_player with a pad byte of its own in place
; of the pad: the entry, the pipes, the vine, the pole, the castle walk and
; the victory walk (src/game/flow.s) move the player so.
;
; In:       A8 = the pad byte (PAD_* bits); D = the player's record
; Out:      pad_bits + 0 = A; then control_player's
; Changes:  as control_player
; Keeps:    D, DBR
; Time:     as control_player, and 4 cycles
; Original: $B0E6-$B0E8 (auto_control_player)
; ---------------------------------------------------------------------------
auto_control_player:
.a8
.i8
        sta pad_bits                    ; the pad that control reads
        ; runs on into control_player

; ---------------------------------------------------------------------------
; control_player: one frame of the player under the pad, in the original's
; order: the pad split, the move (move_by_player_state), the hit box kind,
; the move direction, the scroll (with player_screen_x and lift_scroll of
; the frame before), the screen place, the hit box, the tile test (it sets
; the state for the next frame's move), the front bit, then the fall out
; of the bottom of the screen.
;
; The fall: from Y high 2 on the scroll locks. A cloud area (time not up)
; is left at Y high 4, by the top of the next area; this test comes before
; the death, so a player who dies in a cloud area leaves it so and keeps
; his life (04 leftover 12). Else it is a death: the death song starts
; once (not in the death task, whose song started at the hurt), and at Y
; high 6 (4 in the death task), once the song has ended, the life ends.
;
; In:       D = the player's record; pad_bits + 0 (not read in the death
;           task: pad_ab and pad_ud keep the last values, pad_lr is 0)
; Out:      pad_ab, pad_ud, pad_lr; the player's record; the scroll; the
;           tile test's results; scroll_lock, death_music, snd_event_queue,
;           player_task, the area change at the exits
; Changes:  A, X, Y
; Keeps:    D, DBR
; Time:     each frame of control: 273-931 cycles, median 508 (measured on
;           random states), without the calls of other parts
; Original: $B0E9-$B1C6 (control_player). The cloud exit sets
;           entrance_alt 3 at once (the original sets 2 in begin_alt_entry
;           and then adds 1).
; ---------------------------------------------------------------------------
control_player:
.a8
.i8
; The pad: none in the death task. Under water none while the player is
; off the screen or low on it.
        lda player_task
        cmp #PLAYER_TASK_DEATH
        beq @move
        lda area_type
        bne @split                      ; not AREA_WATER (0)
        lda Object::y_pos+1
        cmp #Y_HIGH_SCREEN
        bne @no_pad
        lda Object::y_pos
        cmp #WATER_PAD_LIMIT_Y
        bcc @split
@no_pad:
        stz pad_bits
@split:
        lda pad_bits
        and #PAD_A|PAD_B
        sta pad_ab
        lda pad_bits
        and #PAD_LEFT|PAD_RIGHT
        sta pad_lr
        lda pad_bits
        and #PAD_UP|PAD_DOWN
        sta pad_ud
; Down with left or right on the ground gives no direction and no crouch.
        and #PAD_DOWN
        beq @move
        lda Object::state
        bne @move                       ; not PLAYER_ON_GROUND (0)
        lda pad_lr
        beq @move
        stz pad_lr
        stz pad_ud
@move:
        jsr move_by_player_state
; The hit box kind: small; else big, or big and crouching.
        ldx #BOX_SMALL
        lda player_small
        bne @box
        ldx #BOX_BIG
        lda crouching
        beq @box
        ldx #BOX_CROUCHING
@box:
        stx Object::box
; The move direction from the X speed's sign; a speed of 0 keeps it.
        ldx #FACING_RIGHT
        lda Object::x_speed
        beq @scroll
        bpl @direction
        ldx #FACING_LEFT
@direction:
        stx Object::direction
@scroll:
        jsr decide_scroll_amount
; The screen place, the hit box (box 0, the player's, from his screen
; place) and the tiles.
        jsr check_player_offscreen
        jsr player_screen_position
        ldx #SLOT_PLAYER                ; the player's box: box 0, the number of his slot
        ldy #REL_PLAYER
        jsr compute_hit_box_corners
        jsr check_player_vs_tiles
; In front of the background from row $40 down, in tasks 4, 8, 10 and 11.
; The tasks below 4 (the vine, the pipes), the castle walk (5) and the entry
; (7) keep the bit that the pipes, the entry and the castle set.
        lda Object::y_pos
        cmp #FRONT_FROM_Y
        bcc @below
        lda player_task
        cmp #PLAYER_TASK_END_LEVEL
        beq @below
        cmp #PLAYER_TASK_ENTRANCE
        beq @below
        cmp #PLAYER_TASK_FLAGPOLE
        bcc @below
        lda #ATTR_BEHIND
        trb Object::attributes
; Below the screen. A keeps Y high for the depth tests.
@below:
        lda Object::y_pos+1
        cmp #Y_HIGH_BELOW
        bmi @done                       ; on or above the screen (the original's sign test)
        ldx #SCROLL_LOCKED
        stx scroll_lock
        ldx time_up
        bne @death                      ; the time is up: a death, in a cloud area too
        ldx cloud_override
        bne @cloud
@death:
        ldx player_task
        cpx #PLAYER_TASK_DEATH
        beq @shallow
        ldx death_music
        bne @deep
        ldx #EVENT_DEATH                ; the death song, once
        stx snd_event_queue
        inc death_music                 ; 0 here: 1, it started
@deep:
        cmp #FALL_DEPTH_SONG
        bra @depth
@shallow:
        cmp #FALL_DEPTH
@depth:
        bmi @done                       ; not deep enough yet (a sign test, as the original's)
        lda snd_event_music
        bne @done                       ; the death song still plays
        lda #PLAYER_TASK_LOSE_LIFE
        sta player_task
@done:
        rts
; The cloud exit: the next area starts with the player falling in from the
; top (entrance_alt 3) and no pad override.
@cloud:
        cmp #FALL_DEPTH
        bmi @done
        stz pad_override
        lda #ENTRANCE_ALT_DROP
        sta entrance_alt
        jmp switch_area_mode
.assert PLAYER_ON_GROUND = 0, error, "control_player tests the state for 0"

; ---------------------------------------------------------------------------
; vine_ride_up: task 1, the climb up the vine (at the climb speed) until the
; player is more than 28 pixels above the screen (row $E4 of the page
; above); then the next area, where the player comes up a vine. The pad
; override PAD_UP stays for that area: there it means "came up a vine".
;
; In:       D = the player's record
; Out:      pad_override = PAD_UP, the climb; or the area change
; Changes:  A, X, Y
; Keeps:    D, DBR
; Time:     each frame of the ride: 42-625 cycles (measured on random states),
;           with the control
; Original: $B1C7-$B1DC (vine_ride_up)
; ---------------------------------------------------------------------------
vine_ride_up:
.a8
.i8
        lda Object::y_pos+1
        bne @climb                      ; not Y_HIGH_ABOVE
        lda Object::y_pos
        cmp #VINE_EXIT_Y
        bcc begin_alt_entry
@climb:
        lda #PAD_UP
        sta pad_override
        ldx #PLAYER_CLIMBING
        stx Object::state
        jmp auto_control_player         ; A = PAD_UP: the climb's pad
.assert Y_HIGH_ABOVE = 0, error, "vine_ride_up tests Y high for 0"

; ---------------------------------------------------------------------------
; begin_alt_entry: the next area starts with the player rising from below:
; out of a pipe, or up a vine when pad_override is set.
;
; In:       nothing
; Out:      entrance_alt = ENTRANCE_ALT_RISE; switch_area_mode's
; Changes:  A
; Keeps:    X, Y, D, DBR
; Time:     29 cycles
; Original: $B1DD-$B1E4 (begin_alt_entry)
; ---------------------------------------------------------------------------
begin_alt_entry:
.a8
.i8
        lda #ENTRANCE_ALT_RISE
        sta entrance_alt
        bra switch_area_mode

; ---------------------------------------------------------------------------
; enter_pipe_down: task 3, one row down into the pipe each frame. The
; screen goes on scrolling by the push of the last frame of control (the
; push is not written in this task: 04 leftover 2). When the pipe's count
; ends (48 frames from the pipe test, 07), the next area: the area's own
; entry through a warp zone's pipe, the rise from below out of a castle,
; else the pipe entry.
;
; In:       D = the player's record; area_change_timer, warp_zone, area_type
; Out:      the player and the screen moved; the area change at the end
; Changes:  A, X, Y
; Keeps:    D, DBR
; Time:     each frame of the task: 129-304 cycles (measured on random
;           states), with the scroll
; Original: $B1E5-$B1FF (enter_pipe_down)
; ---------------------------------------------------------------------------
enter_pipe_down:
.a8
.i8
        lda #PIPE_SINK_STEP
        jsr shift_player_y
        jsr decide_scroll_amount
        ldy #ENTRANCE_ALT_NORMAL        ; a warp zone's pipe
        lda warp_zone
        bne wait_pipe_timer
        ldy #ENTRANCE_ALT_RISE          ; out of a castle
        lda area_type
        cmp #AREA_CASTLE
        beq wait_pipe_timer
        ldy #ENTRANCE_ALT_PIPE
        bra wait_pipe_timer

; ---------------------------------------------------------------------------
; shift_player_y: the player's row moves by a signed amount. The original
; adds to the row byte alone, and its carry does not reach Y high: so this
; add is 8-bit on purpose.
;
; In:       A8 = the rows, signed ($FF one up); D = the player's record
; Out:      the row byte of Object::y_pos; Y high as it was
; Changes:  A
; Keeps:    X, Y, D, DBR
; Time:     14 cycles
; Original: $B200-$B205 (shift_player_y)
; ---------------------------------------------------------------------------
shift_player_y:
.a8
.i8
        clc
        adc Object::y_pos
        sta Object::y_pos
        rts

; ---------------------------------------------------------------------------
; enter_pipe_sideways: task 2, the walk into a side pipe. The tile test
; (07) sets the pipe's count again on each frame while the player's X is
; not on a 16-pixel step, so the count runs once the walk stops; at its end
; the next area, where the player rises from below.
;
; In:       D = the player's record; area_change_timer
; Out:      the walk; the area change at the end
; Changes:  A, X, Y
; Keeps:    D, DBR
; Time:     each frame of the task: 372-817 cycles (measured on random
;           states), with the control
; Original: $B206-$B20A (enter_pipe_sideways)
; ---------------------------------------------------------------------------
enter_pipe_sideways:
.a8
.i8
        jsr walk_into_side_pipe
        ldy #ENTRANCE_ALT_RISE
        ; runs on into wait_pipe_timer

; ---------------------------------------------------------------------------
; wait_pipe_timer: one frame of the pipe's count; at its end the next area,
; with the way in of Y.
;
; In:       Y8 = the next area's entrance_alt; area_change_timer
; Out:      area_change_timer - 1; at 0 entrance_alt = Y and
;           switch_area_mode's
; Changes:  the flags
; Keeps:    A, X, Y, D
; Time:     14-33 cycles
; Original: $B20B-$B212 (wait_pipe_timer), its branch turned round so that
;           the change runs on into switch_area_mode
; ---------------------------------------------------------------------------
wait_pipe_timer:
.a8
.i8
        dec area_change_timer
        beq @change
        rts
@change:
        sty entrance_alt
        ; runs on into switch_area_mode

; ---------------------------------------------------------------------------
; switch_area_mode: the player leaves the area: the picture goes off from
; the next frame (02 section 3), no status bar split, and the play mode
; starts an area again from its first task (begin_area) on the next frame;
; game_core stops after the player task of this frame (03 section 5.2).
;
; In:       nothing
; Out:      screen_off + 1, mode_task = 0, status_split = 0
; Changes:  the flags
; Keeps:    A, X, Y, D
; Time:     20 cycles
; Original: $B213-$B21E (switch_area_mode). The original's A = 0 at its
;           end is the halfway page of go_to_next_area (04 leftover 3):
;           go_to_next_area stores the 0 itself.
; ---------------------------------------------------------------------------
switch_area_mode:
.a8
.i8
        inc screen_off
        stz mode_task                   ; the play mode's first task: begin_area
        stz status_split
        rts

; ---------------------------------------------------------------------------
; walk_into_side_pipe: the walk right at half a pixel each frame until the
; player's X is on a 16-pixel step, then a stand with no pad. Control's
; friction acts on that speed in the same frame (with right held it adds
; friction up to the top speed).
;
; In:       D = the player's record
; Out:      Object::x_speed; control_player's
; Changes:  A, X, Y
; Keeps:    D, DBR
; Time:     330-816 cycles (measured on random states), with the control
; Original: $B21F-$B232 (walk_into_side_pipe); the original's speed 8 that
;           its stop then clears is one store here
; ---------------------------------------------------------------------------
walk_into_side_pipe:
.a8
.i8
        lda Object::x_pos
        and #COLUMN_PIXELS
        beq @in
        lda #SIDE_PIPE_SPEED
        sta Object::x_speed
        lda #PAD_RIGHT
        jmp auto_control_player
@in:
        stz Object::x_speed
        lda #PAD_NONE
        jmp auto_control_player

; ---------------------------------------------------------------------------
; size_change_task: task 9, the grow: the picture's change starts on frame
; 7 of the task (timer_hold $F8), the task ends on frame 59 ($C4). The
; player stands still: control does not run.
;
; In:       timer_hold
; Out:      start_size_change's or finish_player_task's
; Changes:  A
; Keeps:    X, Y, D, DBR
; Time:     each frame of the task: 18-41 cycles
; Original: $B233-$B244 (size_change_task)
; ---------------------------------------------------------------------------
size_change_task:
.a8
.i8
        lda timer_hold
        cmp #GROW_START_HOLD
        beq start_size_change
        cmp #GROW_END_HOLD
        beq finish_player_task
        rts

; ---------------------------------------------------------------------------
; injury_blink_task: task 10, the hurt of a big player: still above
; timer_hold $F0; the shrink starts at $F0 (frame 15); below it control
; runs each frame (while the picture changes, move_by_player_state sets the
; forces but does not move him); the task ends at $C8 (frame 55).
;
; In:       D = the player's record; timer_hold
; Out:      the routine's of that frame
; Changes:  A, X, Y
; Keeps:    D, DBR
; Time:     each frame of the task: 17-849 cycles (measured on random states),
;           with the control
; Original: $B245-$B254 (injury_blink_task), which runs on into
;           start_size_change at $F0
; ---------------------------------------------------------------------------
injury_blink_task:
.a8
.i8
        lda timer_hold
        cmp #SHRINK_START_HOLD
        beq start_size_change
        bcs @still
        cmp #SHRINK_END_HOLD
        beq finish_player_task
        jmp control_player
@still:
        rts

; ---------------------------------------------------------------------------
; start_size_change: the grow or shrink picture starts, unless one runs: its
; step from 0, player_resizing set, the size flips. The sprite part (11)
; clears player_resizing at the picture's end (37 to 40 frames later).
;
; In:       player_resizing, player_small
; Out:      player_anim_step = 0, player_resizing = 1, player_small flipped
; Changes:  A
; Keeps:    X, Y, D, DBR
; Time:     13-32 cycles
; Original: $B255-$B268 (start_size_change)
; ---------------------------------------------------------------------------
start_size_change:
.a8
.i8
        lda player_resizing
        bne @done
        stz player_anim_step
        inc player_resizing             ; 0 here: 1
        lda player_small
        eor #SMALL_FLIP
        sta player_small
@done:
        rts

; ---------------------------------------------------------------------------
; death_task: task 11: the player hangs in the air while timer_hold is $F0
; or more (frames 1-15), then falls under control: no pad, the death
; gravity, no tile test (07 skips task 11), the top fall speed.
;
; In:       D = the player's record; timer_hold
; Out:      control_player's
; Changes:  A, X, Y
; Keeps:    D, DBR
; Time:     each frame of the task: 15-844 cycles (measured on random states),
;           with the control
; Original: $B269-$B272 (death_task)
; ---------------------------------------------------------------------------
death_task:
.a8
.i8
        lda timer_hold
        cmp #DEATH_FALL_HOLD
        bcs @hang
        jmp control_player
@hang:
        rts

; ---------------------------------------------------------------------------
; finish_player_task: the end of a timed task: the timers run again, and
; control comes back on the next frame.
;
; In:       nothing
; Out:      timer_hold = 0, player_task = PLAYER_TASK_CONTROL
; Changes:  A
; Keeps:    X, Y, D, DBR
; Time:     16 cycles
; Original: $B273-$B27C (finish_player_task); its A = 8 at the end has no
;           reader
; ---------------------------------------------------------------------------
finish_player_task:
.a8
.i8
        stz timer_hold
        lda #PLAYER_TASK_CONTROL
        sta player_task
        rts

; ---------------------------------------------------------------------------
; fire_flower_task: task 12, the fire colours flash: the palette steps 0,
; 1, 2, 3 each 4 frames; at timer_hold $C0 (frame 63) control comes back
; with palette 0. The flash shows although game_core's star step sets
; palette 0 after the player's picture: this task sets it again before the
; next picture (04 "The star").
;
; In:       timer_hold, frame_count
; Out:      the player's palette; finish_player_task's at the end
; Changes:  A
; Keeps:    X, Y, D, DBR
; Time:     each frame of the task: 39-48 cycles
; Original: $B27D-$B287 and $B297-$B299 (fire_flower_task), which runs on
;           into flash_player_palette
; ---------------------------------------------------------------------------
fire_flower_task:
.a8
.i8
        lda timer_hold
        cmp #FLOWER_END_HOLD
        beq @end
        lda frame_count
        lsr a
        lsr a                           ; the palette: frame_count / 4
        bra flash_player_palette
@end:
        jsr finish_player_task
        bra reset_player_palette

; ---------------------------------------------------------------------------
; update_star_palette: game_core's step 16, after the player's picture: the
; star's colours, which show in the next frame's picture.
;   - Below the screen (Y high 2 on, the original's sign test of Y high -
;     2): the flash steps, with or without a star (04 leftover 13).
;   - Else with no star: palette 0.
;   - Else with star_timer 4 on a frame where interval_count is 0 (the last
;     frame before its tick to 3): the area song comes back, 64 frames
;     before the star's end; during a timer hold interval_count stands, so
;     it comes on each frame of the hold (04 leftover 14).
;   - The flash: palette (frame_count / 2) AND 3 while star_timer is 8 or
;     more, else (frame_count / 8) AND 3.
;
; In:       the player's Y high, timers + TIMER_STAR, interval_count,
;           frame_count (absolute addresses: any D)
; Out:      the player's palette; start_area_music's
; Changes:  A, X, Y (start_area_music's)
; Keeps:    D, DBR
; Time:     each frame of play: 29-68 cycles (measured on random states),
;           without start_area_music
; Original: $AF3B-$AF66 (in game_core), which runs on into
;           flash_player_palette
; ---------------------------------------------------------------------------
update_star_palette:
.a8
.i8
        lda player_object+Object::y_pos+1
        cmp #Y_HIGH_BELOW
        bpl @flash                      ; below the screen
        lda timers+TIMER_STAR
        beq reset_player_palette        ; no star
        cmp #STAR_MUSIC_TIMER
        bne @flash
        lda interval_count
        bne @flash
        jsr start_area_music            ; src/game/flow.s (03 section 4.8)
@flash:
        lda frame_count
        ldx timers+TIMER_STAR
        cpx #STAR_FAST_FLASH
        bcs @fast
        lsr a
        lsr a
@fast:
        lsr a
        ; runs on into flash_player_palette

; ---------------------------------------------------------------------------
; flash_player_palette: the player's sprite palette from bits 0-1 of A; the
; other attribute bits stay. The merge ((A XOR M) AND mask) XOR M keeps M
; outside the mask and takes A inside it, with no scratch byte. Absolute
; addresses: game_core's star step calls it with D at another record.
;
; In:       A8: bits 0-1 the palette
; Out:      player_object + Object::attributes
; Changes:  A
; Keeps:    X, Y, D, DBR
; Time:     20 cycles
; Original: $B288-$B296 (flash_player_palette)
; ---------------------------------------------------------------------------
flash_player_palette:
.a8
.i8
        eor player_object+Object::attributes
        and #ATTR_PALETTE
        eor player_object+Object::attributes
        sta player_object+Object::attributes
        rts

; ---------------------------------------------------------------------------
; reset_player_palette: the player's sprite palette 0.
;
; In:       nothing (absolute addresses: any D)
; Out:      bits 0-1 of player_object + Object::attributes = 0
; Changes:  A
; Keeps:    X, Y, D, DBR
; Time:     14 cycles
; Original: $B29A-$B2A2 (reset_player_palette)
; ---------------------------------------------------------------------------
reset_player_palette:
.a8
.i8
        lda #ATTR_PALETTE
        trb player_object+Object::attributes
        rts

; ---------------------------------------------------------------------------
; slide_down_pole: task 4, the slide down the flagpole while the flag is in
; enemy slot 5: the pole's sound on the first frame (flag_sound, which the
; grab set, 07), then down held (in the climb state, so at the climb
; speed) down to row $9E, a stand below it. Without the flag (it is down,
; or gone): the castle walk.
;
; In:       D = the player's record; the kind of enemy slot 5, flag_sound
; Out:      snd_square1_queue = flag_sound (a plain store, as the
;           original's), flag_sound = 0; control_player's; or player_task
; Changes:  A, X, Y
; Keeps:    D, DBR
; Time:     each frame of the slide: 21-776 cycles (measured on random
;           states), with the control
; Original: $B2A4-$B2C1 (slide_down_pole)
; ---------------------------------------------------------------------------
slide_down_pole:
.a8
.i8
        lda special_object+Object::kind
        cmp #KIND_FLAG
        bne @no_flag
        lda flag_sound
        sta snd_square1_queue
        stz flag_sound
        lda #PAD_DOWN
        ldx Object::y_pos
        cpx #POLE_BOTTOM_Y
        bcc @slide
        lda #PAD_NONE
@slide:
        jmp auto_control_player
@no_flag:
        lda #PLAYER_TASK_END_LEVEL
        sta player_task
        rts

; ---------------------------------------------------------------------------
; end_level_walk: task 5, the walk right into the castle. Off the pole
; (row $AE on) the level's end song starts once (the pole locked the
; scroll; the walk unlocks it). A wall on the right (the castle's door)
; starts the castle's flag and puts the player behind the background. When
; the flag is up (05b), the next level; when that is the world's fourth
; (level 3), enough coins taken in the level that ends (coins_for_1up)
; set hidden_1up: the next hidden 1-up block of the area data shows (09).
;
; In:       D = the player's record; scroll_lock, star_flag_task,
;           coins_for_1up, the player's record of play
; Out:      snd_event_queue, scroll_lock, star_flag_task, the attributes;
;           level, hidden_1up and the next area
; Changes:  A, X, Y
; Keeps:    D, DBR (when load_area_pointer keeps D)
; Time:     each frame of the walk: 362-898 cycles (measured on random
;           states), with the control
; Original: $B2CA-$B314 (end_level_walk), which runs on into
;           go_to_next_area
; ---------------------------------------------------------------------------
end_level_walk:
.a8
.i8
        lda #PAD_RIGHT
        jsr auto_control_player
        lda Object::y_pos
        cmp #POLE_FOOT_Y
        bcc @door
        lda scroll_lock
        beq @door
        lda #EVENT_LEVEL_END
        sta snd_event_queue
        stz scroll_lock
@door:
        lda Object::collision
        lsr a                           ; bit 0: the right side is free
        bcs @flag
        lda star_flag_task
        bne @behind
        inc star_flag_task              ; 0 here: the castle's flag starts
@behind:
        lda #ATTR_BEHIND                ; behind the background, palette 0
        sta Object::attributes
@flag:
        lda star_flag_task
        cmp #END_WALK_FLAG_UP
        beq @next_level
        rts
@next_level:
        inc player_record+PlayerRecord::level
        lda player_record+PlayerRecord::level
        cmp #HIDDEN_1UP_LEVEL
        bne go_to_next_area
        ldx player_record+PlayerRecord::world
        lda coins_for_1up
        cmp hidden_life_coin_goals,x
        bcc go_to_next_area
        inc player_record+PlayerRecord::hidden_1up
        ; runs on into go_to_next_area

; ---------------------------------------------------------------------------
; go_to_next_area: the next area of the world: its pointer (06), a fresh
; time due, the area change, the halfway page 0 (the original stores the A
; = 0 that switch_area_mode leaves: 04 leftover 3), and the event song
; stops.
;
; In:       the player's record of play
; Out:      area_index + 1, load_area_pointer's, timer_reload + 1,
;           switch_area_mode's, halfway_page = 0, snd_event_queue
; Changes:  A, X, Y (load_area_pointer's)
; Keeps:    D, DBR (when load_area_pointer keeps D)
; Time:     60 cycles and load_area_pointer
; Original: $B315-$B328 (go_to_next_area)
; ---------------------------------------------------------------------------
go_to_next_area:
.a8
.i8
        inc player_record+PlayerRecord::area_index
        jsr load_area_pointer
        inc timer_reload                ; a count, as the original's: 0 means no fresh time (03 L8)
        jsr switch_area_mode
        stz player_record+PlayerRecord::halfway_page
        lda #EVENT_SILENCE
        sta snd_event_queue
        rts

; ---------------------------------------------------------------------------
; move_by_player_state: the frame's move. The crouch first (0 when small; on
; the ground the down bit; in the air it stays), then the forces (a jump
; can start even while the size changes), then, unless the picture of a
; size change runs, the move of the state (the table of the file header).
; The vine's side timer starts again while the player does not climb.
;
; In:       D = the player's record; pad_ud, the state
; Out:      crouching; the forces; the move's results
; Changes:  A, X, Y
; Keeps:    D, DBR
; Time:     each frame of control: 86-550 cycles, median 215 (measured on
;           random states), with the forces and the move
; Original: $B329-$B359 (move_by_player_state)
; ---------------------------------------------------------------------------
move_by_player_state:
.a8
.i8
        lda player_small
        beq @big
        stz crouching
        bra @forces
@big:
        lda Object::state
        bne @forces                     ; in the air: the crouch stays
        lda pad_ud
        and #PAD_DOWN
        sta crouching                   ; 0 or PAD_DOWN
@forces:
        jsr set_player_forces
        lda player_resizing
        bne @done
        lda Object::state
        cmp #PLAYER_CLIMBING
        beq @move
        ldx #CLIMB_SIDE_FRAMES
        stx timers+TIMER_CLIMB_SIDE
@move:
        asl a
        tax
        jmp (.loword(player_moves),x)   ; JMP (abs,X) reads its table from this bank
@done:
        rts
player_moves:                           ; by the player's state
        .addr move_on_ground            ; PLAYER_ON_GROUND
        .addr move_jump_or_swim         ; PLAYER_JUMPING
        .addr move_falling              ; PLAYER_FALLING
        .addr move_climbing             ; PLAYER_CLIMBING
.assert PLAYER_ON_GROUND = 0 && PLAYER_JUMPING = 1, error, "player_moves order"
.assert PLAYER_FALLING = 2 && PLAYER_CLIMBING = 3, error, "player_moves order"

; ---------------------------------------------------------------------------
; move_on_ground: the walk: the walk picture's rate, the facing from the
; pad, the pad's push or the friction on the X speed, the X move
; (move_player_sideways, 05a section 3.2). The push on the screen is the X
; move's pixels, or the spring's step that move_player_sideways gives in
; their place while the spring holds the player (04 leftover 1, 05a L22):
; the screen scrolls while he stands on a spring at screen X $50 or more.
; No vertical move on the ground.
;
; In:       D = the player's record; pad_lr
; Out:      player_facing, the X speed and place, player_scroll
; Changes:  A, X, Y
; Keeps:    D, DBR
; Time:     126-181 cycles (measured on random states), without
;           move_player_sideways
; Original: $B35A-$B36C (move_on_ground)
; ---------------------------------------------------------------------------
move_on_ground:
.a8
.i8
        jsr pick_anim_rate
        lda pad_lr
        beq @friction
        sta player_facing
@friction:
        jsr apply_friction              ; A = pad_lr
        jsr move_player_sideways        ; src/game/movement.s (05a section 3.2)
        sta player_scroll
        rts

; ---------------------------------------------------------------------------
; move_jump_or_swim: the rise's gravity, then the swim's picture, the pull
; at the water's top and the swimmer's facing, then the move in the air.
; While the player rises with A held on this frame and the one before, the
; held gravity (gravity_up, set at the start) stays; it also stays while
; he has risen less than jump_halt_height rows since the start (the row
; difference mod 256, as the original's 8-bit subtract). Else the fall
; gravity takes over for the rest of the jump. On a jump's first frame A
; is a press, but the player has not moved, so the held gravity stays.
;
; In:       D = the player's record; pad_ab, pad_ab_last, jump_origin,
;           jump_halt_height, swimming, pad_lr
; Out:      gravity_up, player_facing; the move's results
; Changes:  A, X, Y
; Keeps:    D, DBR
; Time:     50-255 cycles (measured on random states), without the moves of
;           movement.s
; Original: $B376-$B3AB (move_jump_or_swim), which runs on into
;           move_sideways_in_air
; ---------------------------------------------------------------------------
move_jump_or_swim:
.a8
.i8
        lda Object::y_speed_whole
        bpl @fall_gravity               ; not rising
        lda pad_ab
        and pad_ab_last
        and #PAD_A
        bne @swim                       ; A held since the frame before
        lda jump_origin                 ; the start's row
        sec
        sbc Object::y_pos
        cmp jump_halt_height
        bcc @swim                       ; not risen far enough
@fall_gravity:
        lda gravity_down
        sta gravity_up
@swim:
        lda swimming
        beq move_sideways_in_air
        jsr pick_anim_rate
        lda Object::y_pos
        cmp #WATER_TOP_Y
        bcs @facing
        lda #GRAVITY_WATER_TOP          ; the water's top pulls down
        sta gravity_up
@facing:
        lda pad_lr
        beq move_sideways_in_air
        sta player_facing
        bra move_sideways_in_air

; ---------------------------------------------------------------------------
; move_falling: the fall (a walk off a ledge, a bump, a launch): the fall
; gravity of the area's last jump or stroke kind (GRAVITY_AREA_START before
; the first one) becomes the gravity in use; a spring launch gets it too,
; as the tile test gives this state while he rises (04 leftover 15). Then
; the move in the air.
;
; In:       D = the player's record; gravity_down
; Out:      gravity_up; the move's results
; Changes:  A, X, Y
; Keeps:    D, DBR
; Time:     37-119 cycles (measured on random states), without the moves of
;           movement.s
; Original: $B36D-$B375 (move_falling)
; ---------------------------------------------------------------------------
move_falling:
.a8
.i8
        lda gravity_down
        sta gravity_up
        ; runs on into move_sideways_in_air

; ---------------------------------------------------------------------------
; move_sideways_in_air: the move in the air: the X speed changes only while
; left or right is held; the X move (its push on the screen as on the
; ground); the death fall's gravity in the death task; the fall step
; (move_player_up_down: gravity_up, the top speed 4, no step while the
; spring holds the player outside a timer hold, 05a section 3.4). In
; the air the facing changes only when swimming, so a skid's double
; friction applies once the speed's sign turns against the facing.
;
; In:       D = the player's record; pad_lr, player_task
; Out:      the X speed and place, player_scroll, gravity_up; the Y speed
;           and place
; Changes:  A, X, Y
; Keeps:    D, DBR
; Time:     29-110 cycles (measured on random states), without the moves of
;           movement.s
; Original: $B3AC-$B3C6 (move_sideways_in_air), which runs on into
;           move_player_up_down (src/game/movement.s)
; ---------------------------------------------------------------------------
move_sideways_in_air:
.a8
.i8
        lda pad_lr
        beq @move
        jsr apply_friction              ; A = pad_lr
@move:
        jsr move_player_sideways        ; src/game/movement.s: the pixels, or the spring's step
        sta player_scroll
        lda player_task
        cmp #PLAYER_TASK_DEATH
        bne @up_down
        lda #GRAVITY_DEATH
        sta gravity_up
@up_down:
        jmp move_player_up_down         ; src/game/movement.s (05a section 3.4)

; ---------------------------------------------------------------------------
; move_climbing: the climb. The Y move by the climb speed that
; set_player_forces stored this frame, with no gravity; then, with left or
; right held and free (the side bits, 07), the shift to the vine's other
; side, at most once each 24 frames, and the player faces the vine. No X
; speed move, and the push on the screen is not written (04 leftover 2).
;
; The Y move is the 24-bit Y + the 16-bit speed, sign extended. A 16-bit
; add of the fraction and the row (one word, the fraction low) and the
; speed (its fraction low) gives the original's fraction add, its carry
; into the row add, and the row add; the carry out of bit 15 is the carry
; of the row add, which goes into Y high with the speed's sign byte, as
; the original's third add. The side shift is the original's 16-bit
; signed add of page and X.
;
; In:       D = the player's record; pad_lr, player_facing, the side bits,
;           timers + TIMER_CLIMB_SIDE
; Out:      the Y place; the X place, the timer and player_facing at a shift
; Changes:  A, X, Y
; Keeps:    D
; Time:     each frame of a climb: 54-113 cycles (measured on random states)
; Original: $B3CF-$B423 (move_climbing)
; ---------------------------------------------------------------------------
move_climbing:
.a8
.i8
        a16
        lda Object::y_fraction          ; the fraction and the row
        clc
        adc Object::y_speed             ; the speed's fraction and whole pixels
        sta Object::y_fraction
        a8
        lda #0                          ; the speed's sign byte: 0 down ...
        bit Object::y_speed_whole
        bpl @high
        lda #$FF                        ; ... $FF up (LDA and BIT keep the carry)
@high:
        adc Object::y_pos+1
        sta Object::y_pos+1             ; Y high + the sign + the row add's carry
; A side held and free: the shift, once each 24 frames; no side: the timer 0.
        lda pad_lr
        and Object::collision
        beq @no_side
        ldx timers+TIMER_CLIMB_SIDE
        bne @done
        ldx #CLIMB_SIDE_FRAMES
        stx timers+TIMER_CLIMB_SIDE
        ldx #SHIFT_RIGHT_HELD
        lsr a
        bcs @facing                     ; the right bit (with both: right)
        ldx #SHIFT_LEFT_HELD
@facing:
        ldy player_facing
        cpy #FACING_RIGHT
        beq @shift
        inx
        inx                             ; SHIFT_FACING_LEFT: the next word
@shift:
        a16
        lda Object::x_pos
        clc
        adc vine_side_shifts,x
        sta Object::x_pos
        a8
        lda pad_lr
        eor #PAD_LEFT|PAD_RIGHT         ; the other way: facing the vine
        sta player_facing
@done:
        rts
@no_side:
        stz timers+TIMER_CLIMB_SIDE
        rts
.assert SHIFT_FACING_LEFT = 2, error, "move_climbing adds SHIFT_FACING_LEFT with two INX"
.assert SHIFT_RIGHT_HELD = 0, error, "vine_side_shifts: the right-held pair first"

; ---------------------------------------------------------------------------
; start_jump_or_stroke: the start of a jump or a swim stroke
; (set_player_forces):
; the stroke timer, the Y fraction 0, the start's place, the jump state,
; the kind (0-4 by the run speed on land, 5 the stroke, 6 the stroke in a
; whirlpool), the kind's gravities and its start speed (8.8, one word), and
; the sound; a stroke above the water's top keeps only the speed's
; fraction, so it does not rise.
;
; In:       D = the player's record; swimming, the whirlpool flag
;           (cannon_timer + 0, 05a), player_speed_abs, player_small
; Out:      timers + TIMER_JUMP_SWIM, Object::y_fraction, jump_origin,
;           Object::state, jump_halt_height, gravity_up, gravity_down,
;           Object::y_speed, snd_square1_queue
; Changes:  A, X
; Keeps:    Y, D, DBR
; Time:     at a jump or a stroke: 113-136 cycles (measured on random states)
; Original: $B4A0-$B51B (in set_player_forces). Not kept: the original's 0
;           into the Y speed's fraction that the kind's speed then
;           replaces.
; ---------------------------------------------------------------------------
start_jump_or_stroke:
.a8
.i8
        lda #JUMP_SWIM_FRAMES
        sta timers+TIMER_JUMP_SWIM
        stz Object::y_fraction
        a16
        lda Object::y_pos
        sta jump_origin                 ; Y high and the row of the start
        a8
        lda #PLAYER_JUMPING
        sta Object::state
        lda #JUMP_HALT_PIXELS
        sta jump_halt_height
; The kind: the stroke under water (in a whirlpool its own); on land by the
; run speed.
        lda swimming
        beq @land
        ldx #JUMP_KIND_SWIM
        lda cannon_timer                ; the whirlpool flag (byte 0, 05a)
        beq @kind
        ldx #JUMP_KIND_WHIRLPOOL
        bra @kind
@land:
        ldx #JUMP_KIND_SLOW
        lda player_speed_abs
        cmp #JUMP_KIND_1_SPEED
        bcc @kind
        inx
        cmp #JUMP_KIND_2_SPEED
        bcc @kind
        inx
        cmp #JUMP_KIND_3_SPEED
        bcc @kind
        inx
        cmp #JUMP_KIND_4_SPEED
        bcc @kind
        inx
@kind:
        lda gravity_held_by_kind,x
        sta gravity_up
        lda gravity_fall_by_kind,x
        sta gravity_down
        txa
        asl a
        tax
        a16
        lda jump_start_speeds,x
        sta Object::y_speed
        a8
; The sound: the stroke's (the stomp sound), else the jump of the size.
        lda swimming
        beq @jump_sound
        lda #SQUARE1_ENEMY_STOMP
        sta snd_square1_queue
        lda Object::y_pos
        cmp #WATER_TOP_Y
        bcs @done
        stz Object::y_speed_whole       ; at the water's top: the fraction only
@done:
        rts
@jump_sound:
        lda #SQUARE1_BIG_JUMP
        ldx player_small
        beq @sound
        lda #SQUARE1_SMALL_JUMP
@sound:
        sta snd_square1_queue
        rts

; ---------------------------------------------------------------------------
; set_climb_speed: the climb's part of set_player_forces: the climb speed
; (still, up, or down: the pad's up and down bits that the side bits allow;
; with both, up) as one 8.8 word, and the climb picture's rate (8 frames up,
; 4 still or down). The sideways limits stay as they were.
;
; In:       D = the player's record (climbing); pad_ud, the side bits
; Out:      Object::y_speed, player_anim_rate
; Changes:  A, X
; Keeps:    Y, D, DBR
; Time:     each frame of a climb: 46-53 cycles
; Original: $B450-$B478 (in set_player_forces)
; ---------------------------------------------------------------------------
set_climb_speed:
.a8
.i8
        ldx #CLIMB_STILL
        lda pad_ud
        and Object::collision           ; the free ways up and down
        beq @speed
        ldx #CLIMB_UP
        and #PAD_UP
        bne @speed
        ldx #CLIMB_DOWN
@speed:
        a16
        lda climb_speeds,x
        sta Object::y_speed
        a8
        lda #CLIMB_RATE_UP
        bit Object::y_speed_whole
        bmi @rate
        lda #CLIMB_RATE
@rate:
        sta player_anim_rate
        rts

; ---------------------------------------------------------------------------
; set_player_forces: the first part of each frame's move: in the climb the
; climb speed (set_climb_speed); else a jump starts (start_jump_or_stroke)
; on a press of A (down on this frame, not on the one before) with no
; spring under
; the player: on the ground always; in the air only a swim stroke, within
; 32 frames of the last one or while the swimmer does not rise. Then, out
; of the climb, set_sideways_limits.
;
; In:       D = the player's record; pad_ab, pad_ab_last, spring_anim,
;           swimming, timers + TIMER_JUMP_SWIM, the state and Y speed
; Out:      set_climb_speed's; or start_jump_or_stroke's and
;           set_sideways_limits'
; Changes:  A, X, Y
; Keeps:    D, DBR
; Time:     each frame of control: 54-269 cycles (measured on random states),
;           with set_sideways_limits and start_jump_or_stroke
; Original: $B450-$B51B (set_player_forces), which runs on into
;           set_sideways_limits
; ---------------------------------------------------------------------------
set_player_forces:
.a8
.i8
        lda Object::state
        cmp #PLAYER_CLIMBING
        beq set_climb_speed
        lda spring_anim
        bne set_sideways_limits         ; the spring: no jump
        lda pad_ab
        and #PAD_A
        beq set_sideways_limits
        and pad_ab_last
        bne set_sideways_limits         ; held since the frame before
        lda Object::state
        beq @start                      ; on the ground (PLAYER_ON_GROUND)
        lda swimming
        beq set_sideways_limits         ; in the air on land: no jump
        lda timers+TIMER_JUMP_SWIM
        bne @start                      ; within 32 frames of the last stroke
        lda Object::y_speed_whole
        bmi set_sideways_limits         ; rising: no stroke
@start:
        jsr start_jump_or_stroke
        ; runs on into set_sideways_limits

; ---------------------------------------------------------------------------
; set_sideways_limits: the speed class (X) and the friction class (Y, as a
; word index), then their limits and friction (pick_speed_limits):
;
; | Case                                                    | Speed | Friction |
; |---------------------------------------------------------|-------|----------|
; | in the air, player_speed_abs $19 or more                | run   | 0        |
; | in the air, below $19                                   | walk  | 1 or 2   |
; | on the ground in a water area                           | water | 1 or 2   |
; | on the ground, pad_lr not the move direction            | walk  | 1 or 2   |
; | on the ground, toward the move, B held: running_timer 10 | run   | 0        |
; | on the ground, toward the move, B up, running_timer on  | run   | 0        |
; | on the ground, toward the move, B up, running_timer 0   | walk  | 1 or 2   |
;
; "1 or 2": 2 while running_speed is set (after a run) or from speed $21
; on, else 1.
;
; pick_speed_limits: the left and right limits of the class (in the entry,
; task 7, the right limit of the entry walk, which has no left one), and
; the class's friction, twice that in a skid (the facing is not the move
; direction). The facing and the direction are those of the frame before:
; move_on_ground and control_player set them after this, so a turn's
; double friction starts on the frame after the pad turns. The doubling is
; the original's shift of the two friction bytes with the carry between
; them: one 16-bit shift.
;
; In:       D = the player's record; the state, player_speed_abs,
;           area_type, pad_lr, pad_ab, running_timer, running_speed,
;           player_task, player_facing
; Out:      max_left_speed, max_right_speed, friction; running_timer at B
; Changes:  A, X, Y
; Keeps:    D, DBR
; Time:     each frame of control out of the climb: 75-119 cycles (measured on
;           random states)
; Original: $B51C-$B55D (set_sideways_limits), which runs on into
;           $B55E-$B58B (pick_speed_limits)
; ---------------------------------------------------------------------------
set_sideways_limits:
.a8
.i8
        lda Object::state
        beq @ground                     ; PLAYER_ON_GROUND
        lda player_speed_abs
        cmp #AIR_RUN_SPEED
        bcs @run
        bra @walk
@ground:
        lda area_type
        beq @water                      ; AREA_WATER (0)
        lda pad_lr
        cmp Object::direction
        bne @walk
        lda pad_ab
        and #PAD_B
        bne @run_held
        lda timers+TIMER_RUNNING
        bne @run
@walk:
        ldx #SPEED_CLASS_WALK
        bra @slow
@water:
        ldx #SPEED_CLASS_WATER
@slow:
        ldy #FRICTION_WALK
        lda running_speed
        bne @strong
        lda player_speed_abs
        cmp #STRONG_FRICTION_SPEED
        bcc pick_speed_limits
@strong:
        ldy #FRICTION_STRONG
        bra pick_speed_limits
@run_held:
        lda #RUN_HOLD_FRAMES
        sta timers+TIMER_RUNNING
@run:
        ldx #SPEED_CLASS_RUN
        ldy #FRICTION_RUN
        ; runs on into pick_speed_limits
pick_speed_limits:
.a8
.i8
        lda left_speed_limits,x
        sta max_left_speed
        lda player_task
        cmp #PLAYER_TASK_ENTRANCE
        bne @right
        ldx #SPEED_CLASS_ENTRY
@right:
        lda right_speed_limits,x
        sta max_right_speed
        a16
        lda friction_by_class,y
        ldx player_facing
        cpx Object::direction
        beq @friction
        asl a                           ; a skid: twice the friction
@friction:
        sta friction
        a8
        rts

; ---------------------------------------------------------------------------
; pick_anim_rate: the walk picture's rate (anim_rate_by_speed) by the speed:
; the fast class from $1C on, which also sets running_speed (to the speed,
; not 0); the middle class from $0E on; else the slow class. Below $1C, with
; any button but A in the pad (B, select, start, up, down): when the pad's
; direction bits are the move direction, running_speed ends; else, below
; speed $0B,
; the player stops at once and turns to his facing (the speed and its
; fraction 0). The pad here is pad_bits + 0, with the directions that
; control_player's crouch rule took out of pad_lr.
;
; In:       D = the player's record; player_speed_abs, pad_bits + 0,
;           player_facing
; Out:      player_anim_rate; running_speed; at a stop the direction and
;           the X speed word
; Changes:  A, X
; Keeps:    Y, D, DBR
; Time:     31-72 cycles (measured on random states)
; Original: $B58F-$B5C4 (pick_anim_rate), which runs on into $B5C5-$B5CB
;           (store_anim_rate)
; ---------------------------------------------------------------------------
pick_anim_rate:
.a8
.i8
        lda player_speed_abs
        cmp #ANIM_FAST_SPEED
        bcc @slower
        sta running_speed               ; the speed: not 0
        ldx #ANIM_CLASS_FAST
        bra @store
@slower:
        ldx #ANIM_CLASS_MIDDLE
        cmp #ANIM_MIDDLE_SPEED
        bcs @buttons
        ldx #ANIM_CLASS_SLOW
@buttons:
        lda pad_bits
        and #<~PAD_A
        beq @store                      ; no button but A
        and #PAD_LEFT|PAD_RIGHT
        cmp Object::direction
        bne @turn
        stz running_speed
        bra @store
@turn:
        lda player_speed_abs
        cmp #TURN_STOP_SPEED
        bcs @store
        lda player_facing
        sta Object::direction
        a16
        stz Object::x_speed_fraction    ; the speed and its fraction
        a8
@store:
        lda anim_rate_by_speed,x
        sta player_anim_rate
        rts

; ---------------------------------------------------------------------------
; apply_friction: the X speed by the pad and the friction. The pad's ways
; that the side bits allow (a wall clears its side's bit, 07): right (also
; with both) adds the friction, left takes it off; with neither, the
; friction takes the speed toward 0, and nothing changes at an x_speed of
; 0, the fraction left as it is (04 leftovers 4 and 5). A limit sets only
; x_speed: the fraction stays (04 leftover 4). Then player_speed_abs.
;
; The speed is the word at x_speed_fraction (x_speed high, its fraction
; low) and the friction one word: one 16-bit add or subtract gives the
; original's fraction add, its carry into x_speed, and the x_speed add.
; The limits compare x_speed with the original's 8-bit sign test: every
; speed and limit is within -$30 to $30 (04), so the test is a signed
; compare.
;
; In:       A8 = pad_lr; D = the player's record; friction, max_left_speed,
;           max_right_speed
; Out:      the X speed word, player_speed_abs = |x_speed|
; Changes:  A
; Keeps:    X, Y, D, DBR
; Time:     22-72 cycles (measured on random states)
; Original: $B5CC-$B61F (apply_friction), which runs on into $B620-$B623
;           (store_abs_speed)
; ---------------------------------------------------------------------------
apply_friction:
.a8
.i8
        and Object::collision
        beq @no_way
        lsr a
        bcs @up                         ; right held and free (also with left)
        bra @down
@no_way:
        lda Object::x_speed
        beq @store                      ; A = 0: the friction stops at 0
        bmi @up                         ; moving left: toward 0 is up
@down:
        a16
        lda Object::x_speed_fraction
        sec
        sbc friction
        sta Object::x_speed_fraction
        a8
        lda Object::x_speed
        cmp max_left_speed
        bpl @abs
        lda max_left_speed
        sta Object::x_speed
        bra @abs
@up:
        a16
        lda Object::x_speed_fraction
        clc
        adc friction
        sta Object::x_speed_fraction
        a8
        lda Object::x_speed
        cmp max_right_speed
        bmi @abs
        lda max_right_speed
        sta Object::x_speed
@abs:
        lda Object::x_speed
        bpl @store
        eor #$FF
        inc a                           ; the speed without its sign
@store:
        sta player_speed_abs
        rts

; ---------------------------------------------------------------------------
; decide_scroll_amount: the player's push on the screen this frame: the X
; move's pixels (player_scroll) + a lift's push of the frame before
; (lift_scroll), written back. The screen follows a push to the right of a
; player at screen X $50 or more (the screen X that the player's picture
; had on the frame before), by the push less one pixel up to X $6F (1 for a
; push of 1), and by the whole push from X $70 on; not while the scroll is
; locked, nor while a wall holds the player (the side timer, 07), nor for
; a push of 0, to the left, or above $80 (the original's sign test of the
; push - 1). Then the player is held inside the screen.
;
; In:       D = the player's record; player_scroll, lift_scroll,
;           scroll_lock, player_screen_x, timers + TIMER_SIDE_COLLISION
; Out:      player_scroll; scroll_screen's, or scroll_amount = 0 and
;           hold_player_in_screen's
; Changes:  A, Y
; Keeps:    X, D, DBR
; Time:     each frame of control: 78-220 cycles (measured on random states),
;           with the scroll and the hold
; Original: $AF93-$AFC3 (decide_scroll_amount), with its no-scroll step
;           $AFFB-$AFFF
; ---------------------------------------------------------------------------
decide_scroll_amount:
.a8
.i8
        lda player_scroll
        clc
        adc lift_scroll
        sta player_scroll
        lda scroll_lock
        bne @no_scroll
        lda player_screen_x
        cmp #SCROLL_START_X
        bcc @no_scroll
        lda timers+TIMER_SIDE_COLLISION
        bne @no_scroll
        ldy player_scroll
        dey                             ; one pixel less ...
        bmi @no_scroll                  ; (a push of 0, to the left, or above $80)
        bne @middle
        iny                             ; ... but a push of 1 stays 1
@middle:
        lda player_screen_x
        cmp #SCROLL_FULL_X
        bcc scroll_screen
        ldy player_scroll               ; the whole push from X $70 on
        bra scroll_screen
@no_scroll:
        stz scroll_amount
        bra hold_player_in_screen

; ---------------------------------------------------------------------------
; scroll_screen: the screen moves Y pixels right: the scroll of the frame,
; the count toward the next column set, the left edge (16 bits: the
; original's pixel add with its carry into the page), the picture's scroll
; in the ring of the two name tables (the original's scroll_x and the name
; table bit of its chip control: the left edge's low 9 bits), the right
; edge; then the player is held inside the screen.
;
; In:       Y8 = the pixels (0 or more); D = the player's record
; Out:      scroll_amount, scroll_32, screen_left, picture_scroll,
;           screen_right; hold_player_in_screen's
; Changes:  A, Y
; Keeps:    X, D
; Time:     127-160 cycles (measured on random states), with the hold
; Original: $AFC4-$AFFA (scroll_screen). Not kept: the original's store of
;           8 into its scroll interval timer, which no routine reads (03
;           L4).
; ---------------------------------------------------------------------------
scroll_screen:
.a8
.i8
        sty scroll_amount
        tya
        clc
        adc scroll_32
        sta scroll_32
        a16
        tya                             ; the pixels; the high byte 0 (8-bit Y)
        clc
        adc screen_left
        sta screen_left
        and #RING_WIDTH-1
        sta picture_scroll
        a8
        jsr set_screen_edges
        ; runs on into hold_player_in_screen

; ---------------------------------------------------------------------------
; hold_player_in_screen: a player at or left of the screen's left edge, or
; less than 16 pixels left of its right edge, stands at that edge (16
; pixels inside the right one: edge_x_inset), and his X speed stops unless
; the pad points back into the screen (edge_return_pad). A lift's push ends
; with the frame. A player right of the right edge is put at the left
; edge, as the original's offscreen bits read him (04 leftover 11; the
; scroll and this hold keep him from getting there in play).
;
; The original takes the edge from the player's column bits
; (find_x_offscreen, 11 section 5): bit 7 for dR < 0 or dL >= 0, bit 5 for
; dR = 0-15, where dR = screen_right - X and dL = screen_left - X, each a
; 16-bit difference whose sign is the sign of its page byte. The same two
; differences with the same sign tests give the same edges; the sign test
; matters at an area's first page, where a player who walks left of X 0 has
; page $FF until this hold puts him back. The hold's X is the edge's world
; X - the inset: the original's pixel subtract with its borrow out of the
; page, as one 16-bit subtract.
;
; In:       D = the player's record; screen_left, screen_right, pad_lr
; Out:      at an edge the X place and x_speed; lift_scroll = 0
; Changes:  A, Y
; Keeps:    X, D, DBR
; Time:     50-83 cycles (measured on random states)
; Original: $B000-$B033 (hold_player_in_screen), with its use of
;           find_x_offscreen ($F1F6)
; ---------------------------------------------------------------------------
hold_player_in_screen:
.a8
.i8
        a16
        lda screen_right
        sec
        sbc Object::x_pos               ; dR
        bmi @left                       ; right of the right edge (04 leftover 11)
        ldy #EDGE_RIGHT
        cmp #EDGE_RIGHT_ZONE
        bcc @hold                       ; screen X 240-255
        lda screen_left
        sec
        sbc Object::x_pos               ; dL
        bmi @free                       ; right of the left edge (dL < 0)
@left:
        ldy #EDGE_LEFT
@hold:
        lda screen_left,y               ; the edge's world X (screen_right at EDGE_RIGHT)
        sec
        sbc edge_x_inset,y
        sta Object::x_pos
        a8
        lda pad_lr
        cmp edge_return_pad,y
        beq @lift                       ; the pad points back into the screen
        stz Object::x_speed
        bra @lift
@free:
.a16
        a8
@lift:
        stz lift_scroll
        rts

; ---------------------------------------------------------------------------
; set_screen_edges: the screen's right edge, 255 pixels right of its left
; edge: the original's pixel add with its carry into the page, as one
; 16-bit add.
;
; In:       screen_left
; Out:      screen_right
; Changes:  A
; Keeps:    X, Y, D, DBR
; Time:     27 cycles
; Original: $B038-$B049 (set_screen_edges). Its A = the right page at the
;           end is begin_area's start page there; begin_area uses its own
;           start page (03 L5).
; ---------------------------------------------------------------------------
set_screen_edges:
.a8
.i8
        a16
        lda screen_left
        clc
        adc #SCREEN_RIGHT_OFFSET
        sta screen_right
        a8
        rts

; ---------------------------------------------------------------------------
; remember_ab_buttons: the end of a full frame of play: A and B of this
; frame for the next frame's press tests (the jump, the stroke, the throw,
; the spring), and no left or right until control reads the pad again.
; A frame that stops after its player task does not come here, so
; pad_ab_last keeps the frame before it (03 D5).
;
; In:       pad_ab
; Out:      pad_ab_last = pad_ab, pad_lr = 0; update_scroll_vars'
; Changes:  A, X, Y (step_column_builder's)
; Keeps:    D, DBR
; Time:     each frame of play: 27-47 cycles (measured on random states),
;           without step_column_builder
; Original: $AF67-$AF6E (remember_ab_buttons), which runs on into
;           update_scroll_vars
; ---------------------------------------------------------------------------
remember_ab_buttons:
.a8
.i8
        lda pad_ab
        sta pad_ab_last
        stz pad_lr
        jmp update_scroll_vars          ; src/game/area.s: the column builder's step (game_core step 18)

; ---------------------------------------------------------------------------
; throw_fireball: the throw (step 2 of run_fireballs_and_bubbles, 05a
; section 4.1): a press of B (down on this frame, not on the one before)
; throws the fireball of slot fireball_count AND 1 when that slot is free,
; the player is on the screen (Y high 1), does not crouch and does not
; climb: its state FIREBALL_THROWN (move_fireball, src/game/movement.s, starts it in
; the same frame), the fireball sound (a plain store), the throw pose for
; the player's picture (11), and the count. A press that finds the slot
; busy throws nothing, and the next press tries the same slot. The task is
; not tested: only control gives a press of B (04).
;
; In:       the player is fiery (the caller tests player_power, 05a);
;           pad_ab, pad_ab_last, fireball_count, the player's record
;           (absolute addresses)
; Out:      the fireball's state, snd_square1_queue, throw_timer,
;           timers + TIMER_PLAYER_ANIM, fireball_count
; Changes:  A, X, D (the record of the fireball tried)
; Keeps:    Y, DBR
; Time:     each frame of a fiery player: 15 cycles, 111 at most at a throw
;           (measured on random states)
; Original: $B62B-$B663 (in run_fireballs_and_bubbles)
; ---------------------------------------------------------------------------
throw_fireball:
.a8
.i8
        lda pad_ab
        and #PAD_B
        beq @done
        and pad_ab_last
        bne @done                       ; held since the frame before
        lda fireball_count
        and #FIREBALL_SLOT_MASK
        clc
        adc #SLOT_FIREBALL
        tax
        object_from_x                   ; D = the fireball's record
        lda Object::state
        bne @done                       ; the slot is busy
        lda player_object+Object::y_pos+1
        cmp #Y_HIGH_SCREEN
        bne @done
        lda crouching
        bne @done
        lda player_object+Object::state
        cmp #PLAYER_CLIMBING
        beq @done
        lda #SQUARE1_FIREBALL
        sta snd_square1_queue
        lda #FIREBALL_THROWN
        sta Object::state
        lda player_anim_rate
        sta throw_timer
        dec a
        sta timers+TIMER_PLAYER_ANIM    ; the throw pose (11)
        inc fireball_count
@done:
        rts
