; The state of the game: the object records and the variables that two or
; more parts of the game logic use. A variable of one part is in that
; part's own file. The names follow the ROM documents (the notes' rom/
; folder of the port); each comment gives the meaning, the range and the
; parts that write and read it (document number: 01 power-on and title,
; 02 frame and screen, 03 modes, 04 player, 05a objects, 05b enemies,
; 06 levels, 07 collision and score, 08 sound, 09 two players, 11 sprites).
;
; The registers of the game logic (bank 1, src/game/):
;   DBR = bank 0: every variable below is absolute in bank 0, in one of three
;         groups by the original's clears (03 section 4): AREASTATE (each
;         area start clears it: the original's RAM below $074C), TITLESTATE
;         (a game's start clears it: $074C-$076F), GAMESTATE (kept from the
;         power-on). src/game/flow.s clears the first two.
;   D   = the record of the object that the code works on (OBJECTS, one
;         page of bank 0 for each slot): direct page addresses are ALWAYS
;         fields of that record (Object::...). No variable of the game is
;         on the direct page, so an access never depends on where D points.
;   A, X, Y: 8 bits unless a routine's header says otherwise.
;
; The layout is the port's own: the linker places each variable (src/iigs.cfg
; OBJECTS and GAMESTATE). The original's addresses are not used.


; ---- Sizes, slots and values --------------------------------------------------
; The timers (02, section 4): timers + TIMER_*.
TIMER_SELECT    = $00           ; the select button repeat (01)
TIMER_PLAYER_ANIM = $01         ; (04)
TIMER_JUMP_SWIM = $02           ; (04)
TIMER_RUNNING   = $03           ; (04)
TIMER_BLOCK_BOUNCE = $04        ; (07)
TIMER_SIDE_COLLISION = $05      ; (07)
TIMER_SPRING    = $06           ; (05a)
TIMER_GAME_TICK = $07           ; the game timer's tick (05a, 07)
TIMER_CLIMB_SIDE = $09          ; (04)
TIMER_ENEMY_FRAME = $0A         ; + e: each enemy's frame timer (05b)
TIMER_FRENZY    = $0F           ; the wave timer: the same byte as enemy slot 5's frame timer (05a L29)
TIMER_BOWSER_BREATH = $10       ; (05b)
TIMER_STOMP     = $11           ; (07)
TIMER_AIR_BUBBLE = $12          ; one for all the bubbles: frames until a bubble may start (05a)
FRAME_TIMERS    = $14           ; the last frame timer
TIMER_ENEMY_INTERVAL = $16      ; + e: each enemy's slow timer (05b)
TIMER_COIN_BRICK = $1D          ; (07)
TIMER_INJURY    = $1E           ; (04, 07)
TIMER_STAR      = $1F           ; (04, 07)
TIMER_SCREEN    = $20           ; (02, 03)
TIMER_WORLD_END = $21           ; (03)
TIMER_DEMO      = $22           ; (01)
ALL_TIMERS      = $23           ; the last slow timer
INTERVAL_FRAMES = $14           ; interval_count runs from this to -1: the slow timers each 21 frames
COLLISION_BUFFER = 13 * 16      ; a collision buffer: 13 metatile rows of 16 columns (06)
RANDOM_BYTES    = 7             ; the random bits: one 56-bit register (02 section 5)
PLAY_TASK_CORE  = 3             ; mode_task of the game core in MODE_GAME (03); pause_check reads it
CANNONS         = 6             ; the cannon and whirlpool records (05a)
BOX_SLOTS       = 18            ; the collision boxes: player, 6 enemies, 2 fireballs, 9 misc (07)
DIGITS_SIZE     = $24           ; the status digits: top score, scores, coins, time (07)
; The object groups in the order of the screen-place arrays (rel_x, rel_y,
; offscreen_bits) and of the first sprites (sprite_offset) (11).
REL_PLAYER      = 0
REL_ENEMY       = 1
REL_FIREBALL    = 2
REL_BUBBLE      = 3
REL_BLOCK       = 4             ; and 5: the lower block object
REL_MISC        = 6
REL_GROUPS      = 7
SPR_PLAYER      = 0
SPR_ENEMY       = 1             ; 6 enemies
SPR_BLOCK       = 8             ; also the second sprite set of an enemy
SPR_BUBBLE      = 10
SPR_FIREBALL    = 13
SPR_MISC        = 15
SPR_GROUPS      = 24
; The sources of a frame's screen records (02, section 11.3): the original's
; source numbers. 0 is list 1, 6 list 2; the others are ROM record lists.
SOURCE_LIST_1   = 0
SOURCE_LIST_2   = 6
SOURCES         = $15           ; $13, $14: the status bar's top text with MARIO, with LUIGI (02 section 16)
; screen_rom_lists (the screen part's builder): an entry for each source: the
; address of its records (3 bytes, any bank) and their length (2 bytes); the
; entries of SOURCE_LIST_1, SOURCE_LIST_2 and the unused source 7 are 0.
ROM_LIST_ADDRESS = 0
ROM_LIST_LENGTH = 3
ROM_LIST_ENTRY  = 5
; The screen lists of a frame (02, section 11.4): their room in bytes.
SCREEN_LIST_1_SIZE = 128        ; the warp zone text alone is 100 bytes of records
SCREEN_LIST_2_SIZE = 184
MODE_TITLE = 0
MODE_GAME = 1
MODE_VICTORY = 2
MODE_GAME_OVER = 3
WARM_BOOT = $A5                 ; warm_boot: the RAM holds a game

; pad_bits: the bits of the original's pads (02).
PAD_A = $80
PAD_B = $40
PAD_SELECT = $20
PAD_START = $10
PAD_UP = $08
PAD_DOWN = $04
PAD_LEFT = $02
PAD_RIGHT = $01


; Enemy kinds (Object::kind, 05a). Kinds from KIND_TALL on are drawn and hit as
; tall or wide objects.
KIND_GREEN_KOOPA = $00
KIND_BUZZY_BEETLE = $02
KIND_RED_KOOPA = $03
KIND_HAMMER_BRO = $05
KIND_GOOMBA = $06
KIND_BLOOPER = $07
KIND_BULLET_FRENZY = $08        ; the bullet bill of a wave
KIND_TALL = $09
KIND_GREY_CHEEP = $0A
KIND_RED_CHEEP = $0B
KIND_PODOBOO = $0C
KIND_PIRANHA = $0D
KIND_GREEN_PARATROOPA_JUMP = $0E
KIND_RED_PARATROOPA = $0F
KIND_GREEN_PARATROOPA_FLY = $10
KIND_LAKITU = $11
KIND_SPINY = $12
KIND_FLYING_CHEEP = $14         ; also the flying cheep-cheep wave
KIND_BOWSER_FLAME = $15
KIND_FIREWORKS = $16
KIND_BULLET_CHEEP_FRENZY = $17  ; a wave of bullet bills or cheep-cheeps
KIND_STOP_FRENZY = $18
KIND_FIRE_BAR = $1B             ; the first fire bar kind ($1B-$1E; 05a 21.10)
KIND_LONG_FIRE_BAR = $1F        ; the long fire bar; kinds $1F-$22 run as long bars (05a, 05b section 15)
KIND_BALANCE_LIFT = $24         ; the first large lift kind: balance lifts, then $25-$2A (05b section 3)
KIND_LIFTS_END = $2B            ; the first kind after the large lifts
KIND_LINE_LIFT = $2B            ; the small lifts of a lift line: $2B, $2C (05b)
KIND_LINE_LIFT_2 = $2C
KIND_BOWSER = $2D
KIND_POWERUP = $2E
KIND_VINE = $2F
KIND_FLAG = $30                 ; the flagpole flag
KIND_STAR_FLAG = $31            ; the flag on the castle
KIND_SPRING = $32
KIND_BULLET_CANNON = $33        ; the bullet bill of a cannon
KIND_RETAINER = $35             ; the mushroom retainer or the princess
KIND_GROUP = $37                ; the first group of enemies ($37-$3E; 05a 20.1)
KIND_GROUP_END = $3F            ; one past the last group

; The player's routines (player_task), in the order of the original's task
; table (04).
PLAYER_TASK_ENTRANCE_SETUP = 0  ; the start of an area: the place, the timer, a vine or a bubble
PLAYER_TASK_VINE_CLIMB = 1      ; the climb out of a vine at an area's start
PLAYER_TASK_SIDE_PIPE = 2       ; into a pipe from its side
PLAYER_TASK_DOWN_PIPE = 3       ; down into a pipe
PLAYER_TASK_FLAGPOLE = 4        ; the slide down the flagpole
PLAYER_TASK_END_LEVEL = 5       ; the walk to the castle
PLAYER_TASK_LOSE_LIFE = 6       ; after a death
PLAYER_TASK_ENTRANCE = 7        ; the entrance: from the top, a pipe or a vine
PLAYER_TASK_CONTROL = 8         ; play: the pads move the player
PLAYER_TASK_CHANGE_SIZE = 9     ; growing or shrinking
PLAYER_TASK_INJURY = 10         ; the blink after an injury
PLAYER_TASK_DEATH = 11          ; dying
PLAYER_TASK_FIRE_FLOWER = 12    ; the flash of the fire flower

; Sound commands. Square 1 effects (snd_square1_queue):
SQUARE1_SMALL_JUMP = $80
SQUARE1_FLAGPOLE = $40
SQUARE1_FIREBALL = $20
SQUARE1_PIPE_INJURY = $10
SQUARE1_ENEMY_SMACK = $08
SQUARE1_ENEMY_STOMP = $04
SQUARE1_BUMP = $02
SQUARE1_BIG_JUMP = $01
; Square 2 effects (snd_square2_queue):
SQUARE2_BOWSER_FALL = $80
SQUARE2_EXTRA_LIFE = $40
SQUARE2_POWERUP_GRAB = $20
SQUARE2_TIMER_TICK = $10
SQUARE2_BLAST = $08
SQUARE2_GROW_VINE = $04
SQUARE2_GROW_POWERUP = $02
SQUARE2_COIN = $01
; Noise effects (snd_noise_queue):
NOISE_BOWSER_FLAME = $02
NOISE_BRICK_SHATTER = $01
; Area songs (snd_area_queue):
SONG_SILENCE = $80
SONG_STAR = $40
SONG_PIPE_INTRO = $20
SONG_CLOUD = $10
SONG_CASTLE = $08
SONG_UNDERGROUND = $04
SONG_WATER = $02
SONG_GROUND = $01
; Event songs (snd_event_queue):
EVENT_SILENCE = $80             ; silence: the event song stops
EVENT_TIME_RUNNING_OUT = $40
EVENT_LEVEL_END = $20
EVENT_GAME_OVER_ALT = $10
EVENT_CASTLE_END = $08
EVENT_VICTORY = $04
EVENT_GAME_OVER = $02
EVENT_DEATH = $01

; The worlds and levels (world, level): 0-7 and 0-3.
WORLD_2 = 1
WORLD_6 = 5
WORLD_7 = 6
WORLD_8 = 7

; ---- Values that two or more parts use (from the parts) ----------------------
HIDDEN_Y        = $F8           ; a sprite's Y below the 240-line picture (02 section 9.1)
BLANK_TILE      = $24           ; the tile of a clear cell: every pixel pen 0 (02 section 12)
DEMO_WAIT_STEPS = $18           ; demo_timer: 24 slow steps, 484-504 frames, until the demo (01 section 5.3)
DIGITS_SCORE_1  = $06           ; player 1's score: the first of both players' score and coin digits
ENTRANCE_ALT_NORMAL = 0         ; entrance_alt (03 section 4.9): the area header decides
ENTRANCE_ALT_PIPE = 1           ;   down a pipe into the area
ENTRANCE_ALT_RISE = 2           ;   up out of a pipe or up a vine: the area's song goes on
ENTRANCE_ALT_DROP = 3           ;   down from the top, after the bottom of a cloud area
ENTRANCE_PIPE_INTRO = 6         ; entrance: 6 and 7 are the pipe intro scenes
PAD_NONE        = 0             ; a pad byte with no button
POWER_SMALL     = 0             ; player_power (04): small
POWER_BIG       = 1             ;   big
POWER_FIRE      = 2             ;   fiery (02 section 14.3)
AREA_WATER      = 0             ; area_type of a water area
AREA_CASTLE     = 3             ; area_type of a castle: the lives screen always shows (02 section 13 task 6)
METATILE_EMPTY  = $00           ; blank
BLOCK_SET_BLANK = 3             ; four blank tiles: a taken coin or axe, a bridge piece
RECORD_KIND     = 0             ; REC_CELLS
CELLS_ROW       = 1             ; the ring row
CELLS_COLUMN    = 2             ; the ring column of the first cell
CELLS_COUNT     = 3             ; the cells
CELLS_TILES     = 4             ; the tiles, across
AREA_GROUND     = 1             ; area_type of a ground area (06 section 1)
LOW_BYTE        = $00FF         ; a 16-bit A: its low byte (a byte loaded with 8-bit A, then widened)
ENEMY_ACTIVE    = 1             ; Object::active of a started enemy
WHIRLPOOLS      = 5             ; build_pit counts its records 0-4: past 4 it goes back to 0
SPAWN_END       = $FF           ; the end of the area's list
SPAWN_SKIP      = $FE           ; a page skip that the reader takes (its page is in the records after it)
SPAWN_LINK      = $FD           ; an area change
PLAYER_ON_GROUND = 0            ; the player's state (Object::state, 04): on the ground; 07 writes it
PLAYER_JUMPING  = 1             ;   jumping, or swimming (under water the tile test gives 1, 07)
PLAYER_FALLING  = 2             ;   falling: walked off, bumped, launched
PLAYER_CLIMBING = 3             ;   on a vine or the pole
FIREBALL_THROWN = 2             ; a fireball's state (05a section 4.3): thrown on this frame
BUBBLE_ENTRANCE = 2             ; launch_bubble's entry (src/game/objects.s): after the random bit's
FACING_RIGHT    = 1             ; Object::direction and player_facing: right (the pad bit of right, 04, 05b)
FACING_LEFT     = 2             ;   left: bit 1, the pad bit of left and the bit that mirrors a row (11 section 6)
Y_HIGH_ABOVE    = 0             ; Y high (the high byte of y_pos): above the screen
Y_HIGH_SCREEN   = 1             ;   on the screen
Y_HIGH_BELOW    = 2             ;   from 2 on, below it
; Object::box: the hit box kinds (07 section 2, the rows of hit_box_shapes).
BOX_BIG         = 0             ; the player, big (04 control_player)
BOX_SMALL       = 1             ; the player, small
BOX_CROUCHING   = 2             ; the player, big and crouching
BOX_TALL_ENEMY  = 3             ; a tall enemy
BOX_SMALL_LIFT  = 4             ; the small lifts
BOX_LIFT_CASTLE = 5             ; the large lifts in castles or with hard_mode_2
BOX_LARGE_LIFT  = 6             ; the large lifts elsewhere
BOX_FIREBALL    = 7             ; the fireballs and the hammers
BOX_FLAME       = 8             ; the Bowser flame
BOX_SMALL_ENEMY = 9             ; the small enemy box
BOX_BOWSER      = $0A           ; a half of Bowser
BOX_HAMMER_BRO  = $0B           ; the hammer brother
; The player's Object::collision: the sides that the tile test leaves free (07 section 5).
SIDE_RIGHT_FREE = $01           ; bit 0: the right side
SIDE_LEFT_FREE  = $02           ; bit 1: the left side
SIDES_FREE      = $FF           ; every side
; Object::active of the second half of a two-slot object (05a section 2).
SECOND_HALF     = $80           ; this + the first half's enemy number
SECOND_HALF_OF  = $0F           ;   and this mask gives that enemy number back
BLOCK_REPLACE_DUE = 1           ; Object::block_replace: the metatile goes back at the next chance (05a)
; offscreen_bits (11 section 5: 11 writes them, 05b and 07 read them): the
; 8-pixel rows and columns of an object off the screen.
OFFSCREEN_ROW_1 = $80           ; the row at Y to Y + 7
OFFSCREEN_ROW_2 = $40
OFFSCREEN_ROW_3 = $20
OFFSCREEN_ROWS  = $F0           ; rows 1-4
OFFSCREEN_COLUMN_1 = $08        ; X to X + 7 off the screen
OFFSCREEN_COLUMN_2 = $04        ; X + 8 to X + 15
OFFSCREEN_COLUMN_3 = $02
; A misc object's state (05a section 14).
MISC_COIN       = 1             ; a coin rises
MISC_COIN_SCORE = 2             ;   from 2 to $2F (a coin): its "200" rises
MISC_COIN_GONE  = $30           ;   the number's state at which the slot is free
MISC_HAMMER     = $80           ; bit 7: a hammer
HAMMER_FLYING   = 1             ;   a hammer's low 7 bits: 1, it flies
BALANCE_NONE    = $FF           ; balance_side: no balance lift (the player on none; no lift waits for its partner)
SCROLL_LOCKED   = 1             ; scroll_lock: the screen does not scroll (the area's scroll stop flips bit 0, 06)
HAMMER_JUMP_HIGH = $FA          ; the hammer brother's high jump: 6 pixels a frame up (05b; 07 at a wall)
POWERUP_MUSHROOM = 0             ; powerup_kind (05a 16, 07, 11)
POWERUP_FLOWER  = 1             ;   the fire flower
POWERUP_STAR = 2
POWERUP_1UP     = 3
METATILE_VINE = $26              ; the climbable blank of a vine's column
METATILE_COIN_BRICK = $58        ; the coin brick of the ground areas
METATILE_COIN = $C2              ; a coin (not the water coin)
METATILE_USED_BLOCK = $C4        ; the empty block
COIN_POINTS     = 2             ;   200 points (the hundreds)
COINS_FOR_LIFE  = 100           ; a life each 100 coins
SCORE_DIGITS    = 6             ; the digits of a score record: the last record of refresh_status_number
BLOCK_BUMP      = $11           ; Object::state of block b: a bump, before its first run,
BLOCK_BREAK     = $12           ;   a break, before its first run
BLOCK_BOUNCE_FRAMES = $10       ; block_bounce_timer at a bump: no other bump meanwhile
COIN_BRICK_TIME = $0B           ; slow timer steps of a coin brick's coins
ROW_STEP        = $10           ; tile_row: one row
BRICK_PLAYER_SPEED = $FE        ; the player's rise after he breaks a brick: 2 up
BOWSER_FEET_FRAMES = $20        ; bowser_feet and his frame timer at the start
FIREWORK_FRAMES = 8             ; Object::firework_frames at the start
; An enemy's state (05b): the low bits and the flag bits.
ENEMY_KICKED    = $80           ; bit 7: a kicked shell; a power-up that moves
ENEMY_DROP      = $40           ; bit 6: a bit-7 object in the air
ENEMY_DEFEATED  = $20           ; bit 5: defeated, it falls off the screen
HAMMER_BRO_THROWING = $08       ; bit 3: the hammer brother shows its throw (11)
ENEMY_STATE_BITS = $07          ; bits 0-2: the motion, below
ENEMY_WALKING   = 0             ;   on the ground
ENEMY_FALLING   = 1             ;   in the air (walked off a ledge, a hammer brother's jump)
ENEMY_FLIPPED   = 2             ;   knocked up by a block (the whole state byte, in move_ordinary_enemy)
ENEMY_UPSIDE_DOWN = 3           ;   stunned after a knock; 3-4 and 6-7 wait for their slow timer
ENEMY_STOMPED   = 4             ;   a shell or a flat goomba
ENEMY_SPINY_EGG = 5             ;   a spiny's egg (also the whole state byte, check_enemy_in_bounds)
BOWSER_MOUTH_OPEN = $80         ; bowser_body bit 7: his mouth open (11)
BOWSER_FEET_STEP = $01          ; bowser_body bit 0: his feet frame (11)
; The score codes of a score number (Object::score_kind, 07 section 12): the
; points that it gives at its sixth step (score_award_places and
; score_award_amounts), and the 1-up; start_score_number takes them.
SCORE_100       = 1
SCORE_200       = 2
SCORE_400       = 3
SCORE_500       = 4
SCORE_1000      = 6
SCORE_5000      = 9
SCORE_1UP       = $0B
DIGITS_SCORE_2  = $0C           ; player 2's score
DIGITS_TIME     = $21           ; the game time: hundreds, tens, ones
TIME_DIGITS     = 3
DIGIT_HUNDREDS  = 4             ; digit_add + this: the hundreds of a score
DIGIT_TENS      = 5             ; digit_add + this: the tens of a score, the last digit of a number
NYBBLE_TIME     = 4             ; refresh_status_number: the nybble of the time's field; a player's score is the player (07)
PLAYER_FIRST_SPRITE = 1         ; the sprite of the player's top left: his sprites never move (11 section 2)
SMALL_LIFT_TOP  = $20           ; a box whose top is above this is not tested

; ---- The object records ------------------------------------------------------
; The 25 slots of the original (document 05a, section 2), one record each,
; at the start of a page of bank 0: D = the record gives each field with no
; index register and no penalty cycle (D's low byte 0).
OBJECT_SLOTS    = 25
SLOT_PLAYER     = 0             ; the player
SLOT_ENEMY      = 1             ; 6 enemies, and the objects that live in enemy slots
ENEMY_SLOTS     = 6
SLOT_SPECIAL    = SLOT_ENEMY+5  ; enemy slot 5: power-ups, vines, the flagpole flag (05a)
SLOT_FIREBALL   = 7             ; the player's 2 fireballs
FIREBALL_SLOTS  = 2
SLOT_BLOCK      = 9             ; 4 block objects: 9-10 the bumped blocks or the upper brick
BLOCK_SLOTS     = 4             ;   pieces, 11-12 the lower pieces of blocks 0 and 1
SLOT_MISC       = 13            ; 9 misc objects: hammers, coins from blocks
MISC_SLOTS      = 9
SLOT_BUBBLE     = 22            ; 3 air bubbles
BUBBLE_SLOTS    = 3

; A record. X and Y are 24-bit fixed point values, low byte first: the
; fraction (1/256 pixel), then a word (x_pos, y_pos; ca65 reads x and y as
; the index registers). X's word is the world X: the page
; (256 pixels) in the high byte, the pixel in the low byte, so a 16-bit add
; gives the original's two adds with their carry. Y's word is Y high (0 above
; the picture, 1 on it, 2 or more below) and the pixel row (0 the top).
; Fields that a kind lends to values of its own (document 05a, section 2.3)
; are union members: the bytes are the same, as in the original, because a
; started object keeps every field that its start does not write (05a,
; section 2.4).
.struct Object
        slot            .byte   ; the record's own slot number, 0 to OBJECT_SLOTS - 1 (set at the start, never changed)
        state           .byte   ; the state of the object; its meaning is per group (04, 05a, 05b)
        direction       .byte   ; 1 right, 2 left: the player and the enemies (04, 05b)
        attributes      .byte   ; the sprite attributes: bits 0-1 palette, bit 5 behind the background (11)
        box             .byte   ; the collision box kind (07: BOX_*)
        collision       .byte   ; what it can hit (07)
        .union
          x_fraction    .byte   ; 1/256 pixel
          paratroopa_start_y .byte ; a red paratroopa: its start Y (05b)
          lift_top_y    .byte   ; an up-down lift: its top Y (05b)
        .endunion
        x_pos           .word   ; world X: page x 256 + pixel
        .union
          y_fraction    .byte   ; 1/256 pixel
          piranha_high_y .byte  ; a piranha plant: its high Y (05b)
          flame_height  .byte   ; a Bowser flame: its height number (05b)
        .endunion
        y_pos           .word   ; Y high x 256 + pixel row
        x_speed_fraction .byte  ; the player's X speed fraction: with x_speed, his 16-bit X speed (04)
        .union
          x_speed       .byte   ; signed, 1/16 pixel each frame
          spring_rest_y .byte   ; a jump spring: its rest Y (05a)
          piranha_speed .byte   ; a piranha plant: its speed (05b)
          cheep_move    .byte   ; a cheep-cheep: its move bit (05b)
          paratroopa_middle_y .byte ; a red paratroopa: its middle Y (05b)
          lift_middle_y .byte   ; an up-down lift: its middle Y (05b)
          firebar_angle_low .byte ; a fire bar: the low byte of its angle (05b)
          firework_step .byte   ; a firework: its step (05b)
          squid_swim_speed .byte ; a blooper: its sideways speed, 0-2 whole pixels a frame (05b section 10)
          counter_minor .byte   ; a swaying object: its secondary X counter, 0 to the maximum, also its X speed (05b section 9)
        .endunion
        .union
          y_speed       .word   ; signed, 1/256 pixel each frame: the fraction, then the whole pixels
          .struct
            .union
              y_speed_fraction .byte
              cheep_start_y .byte ; a cheep-cheep: its start Y (05b)
              piranha_low_y .byte ; a piranha plant: its low Y (05b)
              flame_drift   .byte ; a Bowser flame: its drift (05b)
              squid_rise    .byte ; a blooper: its rise, 0-2 whole pixels a frame (05b section 10)
            .endunion
            .union
              y_speed_whole .byte
              piranha_moving .byte ; a piranha plant: it moves (05b)
              firework_frames .byte ; a firework: its frame count (05b)
              squid_stroke  .byte ; a blooper: its stroke counter: 0 faster, 1 slower, 2 the sink (05b section 10)
              lakitu_direction .byte ; Lakitu: 0 left, 1 right, the sign of its X speed (05b section 14)
              counter_major .byte ; a swaying object: its primary X counter, bits 0-1 the phase (05b section 9)
              firebar_angle_high .byte ; a fire bar: its step 0-31: 0 up, 8 right, $10 down, $18 left (05b section 15)
            .endunion
          .endstruct
        .endunion
; The enemy slots only.
        active          .byte   ; 0 free, 1 active, $80 + s: the second half of the object in enemy slot s (05a)
        kind            .byte   ; the enemy kind (KIND_*, 05a)
        offscreen       .byte   ; the offscreen bits for the collisions (07, 11)
        shell_chain     .byte   ; the enemies that this kicked shell hit (07)
        .union
          hammer_timer  .byte   ; a hammer brother: frames to its next throw (05b)
          on_lift       .byte   ; a lift: the player stands on it (05b, 07); the same byte, as in the original
        .endunion
        firebar_speed   .byte   ; a fire bar: its turn speed (05b)
        firebar_turn    .byte   ; a fire bar: its turn direction (05b)
        jump_timer      .byte   ; a hammer brother: frames to its next jump (05b)
; The player and the enemies: the score number that floats up from them (07).
        score_kind      .byte   ; 0 none
        score_x         .byte   ; its X on the screen
        score_y         .byte   ; its Y
        score_timer     .byte   ; frames it still floats
; The fireballs.
        bounce          .byte   ; 1 while the fireball bounces off a floor (07)
; The misc objects.
        hammer_owner    .byte   ; the enemy slot that threw the hammer (05a)
        misc_hit        .byte   ; the hammer touched the player (07)
; The block objects 0-1 (slots 9-10): the bumped blocks (05a section 17, 07).
        block_origin_x  .byte
        block_origin_y  .byte
        block_buffer    .byte   ; its place in the collision buffers
        block_metatile  .byte   ; the metatile that replaces it
        block_page      .byte
        block_replace   .byte   ; the metatile is due
.endstruct
.assert Object::x_speed = Object::x_speed_fraction + 1, error, "the player's X speed is one word (04)"
OBJECT_PAGE     = $100          ; the bytes of a slot's page: the record, then its scratch

; The records: OBJECTS (src/iigs.cfg) starts a page of bank 0.
.segment "OBJECTS"
objects:        .res OBJECT_SLOTS * OBJECT_PAGE

; The first record of each group. Code whose D points at another record
; reads a field as an absolute address: for example the player's X from an
; enemy's routine is lda player_object + Object::x_pos, and enemy e's kind
; is enemy_objects + e * OBJECT_PAGE + Object::kind.
player_object   = objects + SLOT_PLAYER * OBJECT_PAGE
enemy_objects   = objects + SLOT_ENEMY * OBJECT_PAGE
special_object  = objects + SLOT_SPECIAL * OBJECT_PAGE
fireball_objects = objects + SLOT_FIREBALL * OBJECT_PAGE
block_objects   = objects + SLOT_BLOCK * OBJECT_PAGE
misc_objects    = objects + SLOT_MISC * OBJECT_PAGE
bubble_objects  = objects + SLOT_BUBBLE * OBJECT_PAGE

; object_from_x: D = the record of slot X (0 to OBJECT_SLOTS - 1).
; In: A8; X the slot. Out: A8. Changes: A (both bytes), the flags.
; Keeps: X, Y. Time: 18 cycles with X8.
.macro object_from_x
        rep #P_M8
        .a16
        txa
        and #$00FF
        xba                     ; A = slot x OBJECT_PAGE
        clc
        adc #objects
        tcd
        sep #P_M8
        .a8
.endmacro

; ---- The frame (02) ---------------------------------------------------------
.segment "AREASTATE"
frame_count:    .res 1          ; +1 each frame (02); read by the animations of 04, 05a, 05b, 11
pad_bits:       .res 2          ; the pads of player 1 and player 2, PAD_* bits (02 read_pads); 04, 03
pad_ab:         .res 1          ; the pad of the player on the screen: A (bit 7), B (bit 6) (02); 04
pad_ud:         .res 1          ;   up (bit 3), down (bit 2)
pad_lr:         .res 1          ;   left (bit 1), right (bit 0)
pad_ab_last:    .res 1          ; pad_ab of the frame before (04)
pad_held:       .res 2          ; per pad: select and start held (01, 02)
.segment "GAMESTATE"
mode:           .res 1          ; MODE_* (02 mode_dispatch; 03)
mode_task:      .res 1          ; the step of the mode (03)
.segment "AREASTATE"
screen_task:    .res 1          ; the step of the screen set-up (02)
.segment "GAMESTATE"
screen_off:     .res 1          ; nonzero: the picture is off (02, 03)
.segment "AREASTATE"
status_split:   .res 1          ; nonzero: the status bar stays in place (02, 03, 06)
.segment "GAMESTATE"
pause:          .res 1          ; bit 0 paused, bit 7 start is held (02); 08, 03
pause_timer:    .res 1          ; frames until start works again (02)
interval_count: .res 1          ; frames until the slow timers step (02)
.segment "AREASTATE"
timer_hold:     .res 1          ; nonzero: the timers wait (02, 03, 04)
.segment "GAMESTATE"
random:         .res RANDOM_BYTES ; the random bits: one step each frame (02); 05a, 05b, 07
; The timers: the frame timers step each frame, the slow timers each 21
; frames (02, section 4). Each is timers + TIMER_*.
timers:         .res ALL_TIMERS + 1

; The sprite list (11): 64 entries of SPRITE_ENTRY bytes in the order of
; packet_layout.inc; the packet sends it (02).
.segment "AREASTATE"
sprite_list:    .res SPRITE_LIMIT * SPRITE_ENTRY
sprite_offset:  .res SPR_GROUPS ; the first sprite of each object group, SPR_* order (02 sprite_shuffle, 11)
shuffle_step:   .res 1          ; the step of the sprite shuffle (02)
shuffle_amounts: .res 3         ; the amounts of the sprite shuffle (02)

; The screen records of the frame (02, section 11; packet_layout.inc records).
; The two lists keep the original's rules of what reaches the screen.
screen_list_1:  .res SCREEN_LIST_1_SIZE ; cells, squares, colours of the frame (02 list 1)
screen_list_1_end: .res 1       ; its length
screen_list_1_original_end: .res 1 ; its length in the original's record bytes: the room tests of
                                ; blink_block_colors (02) and the lift ropes (05b) count those
screen_list_2:  .res SCREEN_LIST_2_SIZE ; area columns, the coin or axe erase (02 list 2)
screen_list_2_end: .res 1
.segment "GAMESTATE"
screen_source:  .res 1          ; the source that the next frame sends: the original's source number
                                ; (02 section 11.3): SOURCE_LIST_1, SOURCE_LIST_2, or a ROM record list
                                ; of screen_rom_lists (the screen part's builder, scripts/screen_data.py)
picture_scroll: .res 2          ; X of the picture's left edge in the 512-pixel ring of the two name
                                ; tables (the original's scroll register and the name table bit of its
                                ; chip control): 06 update_scroll_vars and 02 clear_name_tables write it;
                                ; the frame sends it (PKT_SCROLL)

; ---- The scroll and the screen (04, 06) --------------------------------------
.segment "AREASTATE"
screen_left:    .res 2          ; the world X of the screen's left edge (04, 06, 11)
screen_right:   .res 2          ; of its right edge
.segment "GAMESTATE"
scroll_amount:  .res 1          ; the scroll of this frame (04, 06)
.segment "TITLESTATE"
scroll_fraction: .res 1         ; the fraction of the scroll (04)
.segment "AREASTATE"
scroll_32:      .res 1          ; pixels since the last 32-pixel column set (06)
scroll_lock:    .res 1          ; nonzero: the screen does not scroll (04, 06)
player_scroll:  .res 1          ; how far the player pushed the screen this frame (04, 05a, 05b)
.segment "TITLESTATE"
player_screen_x: .res 1         ; the player's X on the screen, for the scroll (04, 11)
.segment "AREASTATE"
rel_x:          .res REL_GROUPS ; X on the screen of each group's current object, REL_* order (11, 07)
rel_y:          .res REL_GROUPS ; Y on the screen
offscreen_bits: .res REL_GROUPS ; the parts off the screen (11, 07)

; ---- The area (06) ------------------------------------------------------------
.segment "TITLESTATE"
area_type:      .res 1          ; 0 water, 1 ground, 2 underground, 3 castle (06); every part
area_slot:      .res 1          ; the area's slot in the area tables (06, 03)
area_byte:      .res 1          ; the area byte of the level (06, 03)
entrance_page:  .res 1          ; the page where the player enters (03, 06)
entrance_alt:   .res 1          ; the player enters by a pipe or a vine (03, 04)
.segment "AREASTATE"
entrance:       .res 1          ; how the player enters the area (03, 04)
timer_setting:  .res 1          ; the start time of the area (03, 06, 07)
area_style:     .res 1          ; the ledge style: trees, mushrooms, cannons (06, 05a)
cloud_override: .res 1          ; nonzero: the area is in the clouds (06, 03)
backdrop:       .res 1          ; the backdrop setting of the area (02, 06)
loop_command:   .res 1          ; a loop check is due (06, 05a)
loop_correct:   .res 1          ; the right paths taken in a loop area (05a)
loop_passes:    .res 1          ; the checks passed in a loop area (05a)
warp_zone:      .res 1          ; the warp zone: its pipes and its text (06, 07)
swimming:       .res 1          ; nonzero: the area is under water (04, 05a, 06)
collision_buffer_1: .res COLLISION_BUFFER ; the metatiles of a screen: 13 rows of 16 columns (06, 07)
collision_buffer_2: .res COLLISION_BUFFER ; the next screen

; ---- The player (04) ---------------------------------------------------------
player_task:    .res 1          ; the player's routine (PLAYER_TASK_*, 04); 03, 07, 11
player_facing:  .res 1          ; 1 right, 2 left (04, 11)
player_frame:   .res 1          ; the player's frame (04, 11)
.segment "TITLESTATE"
player_power:   .res 1          ; 0 small, 1 big, 2 fire (04, 07, 11)
player_small:   .res 1          ; 0 big, 1 small (04, 07, 11)
.segment "AREASTATE"
player_resizing: .res 1         ; the player grows or shrinks (04, 11)
player_speed_abs: .res 1        ; the player's speed without its sign (04, 07)
running_speed:  .res 1          ; the player runs fast (04)
crouching:      .res 1          ; the player crouches (04, 07, 11)
jump_origin:    .res 2          ; Y high x 256 + Y of the jump's start (04, 07)
throw_timer:    .res 1          ; the throw pose (04, 11)
spring_anim:    .res 1          ; the step of the jump spring (04, 05a)
spring_force:   .res 1          ; the force of the jump spring (05a, 04)
.segment "TITLESTATE"
pad_override:   .res 1          ; the pad bits of the automatic walk (03, 04)
.segment "AREASTATE"
no_collisions:  .res 1          ; nonzero: collisions are off (03, 07)
fireball_count: .res 1          ; the fireballs thrown (04, 05a)
star_flag_task: .res 1          ; the flag on the castle (05b, 03)
flag_touch_y:   .res 1          ; the Y where the player touched the pole (04, 07)
flag_sound:     .res 1          ; the flagpole sound (04, 08)
death_music:    .res 1          ; the death song started (03, 07)
victory_walk_state: .res 1      ; nonzero while the player walks or the screen scrolls to the castle (03, 04)
dest_page:      .res 1          ; the page that the scroll to the castle stops at (03)

; ---- The players' records (03, 09) --------------------------------------------
; The record of the player on the screen, and the same record of the other
; player: swap_players (09) trades them.
.struct PlayerRecord
        lives           .byte
        halfway_page    .byte   ; the halfway page reached
        level           .byte   ; the level of the world, 0-3
        hidden_1up      .byte   ; the hidden 1-up shows
        coins           .byte
        world           .byte   ; 0-7
        area_index      .byte   ; the area of the world
.endstruct
.segment "TITLESTATE"
player_record:  .res .sizeof(PlayerRecord)
other_record:   .res .sizeof(PlayerRecord)
player:         .res 1          ; 0 Mario, 1 Luigi (09, 02, 03)
.segment "GAMESTATE"
two_players:    .res 1          ; 1: a two-player game (01, 03, 09)
.segment "TITLESTATE"
hard_mode:      .res 1          ; the harder enemies of the second quest (03, 05a, 05b)
.segment "AREASTATE"
hard_mode_2:    .res 1          ; the harder enemies of the later levels (03, 05a, 05b)
.segment "TITLESTATE"
world_select:   .res 1          ; the world of the world select (01)
.segment "GAMESTATE"
world_select_on: .res 1         ; the world select works: the game was won (01, 03)
continue_world: .res 1          ; the world of a continue (03)
.segment "TITLESTATE"
no_lives_screen: .res 1         ; skip the lives screen (03)
.segment "AREASTATE"
coins_for_1up:  .res 1          ; the coins for the hidden 1-up (04, 07)
.segment "TITLESTATE"
time_up:        .res 1          ; the time ran out (03, 07)
timer_reload:   .res 1          ; the timer starts again (03, 07)
.segment "GAMESTATE"
warm_boot:      .res 1          ; WARM_BOOT: the RAM holds a game (01)

; ---- The digits (07) ----------------------------------------------------------
; The status digits, one decimal digit in each byte, in the original's
; relative layout (07 gives the offsets of each number).
digits:         .res DIGITS_SIZE
.segment "AREASTATE"
digit_add:      .res 6          ; the digits to add to a score or count (07)

; ---- Enemies and objects (05a, 05b) --------------------------------------------
enemy_offset:   .res 1          ; the next entry of the area's spawn records (05a, 06)
frenzy_kind:    .res 1          ; the enemy kind of a wave (05a, 05b)
frenzy_queue:   .res 1          ; a wave to start (05a, 05b)
duplicate_slot: .res 1          ; the slot of the second enemy of a group (05a)
group_count:    .res 1          ; the enemies of a group still to place (05a)
bit_filter:     .res 1          ; the enemies that a wave already placed (05a)
lakitu_timer:   .res 1          ; frames until Lakitu comes back (05a, 05b)
powerup_kind:   .res 1          ; the power-up of a block: 0 mushroom, 1 flower, 2 star, 3 1-up (05a, 07)
vertical_flip:  .res 1          ; a defeated enemy shows upside down (05b, 11)
stomp_chain:    .res 1          ; the enemies stomped in one jump (07)
bowser_hits:    .res 1          ; the fireballs Bowser still takes (05b, 07)
bowser_front_slot: .res 1       ; the slot of Bowser's front half (05b, 07, 11)
bowser_body:    .res 1          ; Bowser: the body parts drawn (05b, 11)
bowser_feet:    .res 1          ; Bowser: the feet animation (05b, 11)
bowser_draw:    .res 1          ; which half of Bowser is drawn (05b, 11)
bowser_origin_x: .res 1         ; Bowser's start X (05b)
bowser_flame_timer: .res 1      ; (05b)
bowser_speed:   .res 1          ; (05b)
bridge_collapse: .res 1         ; the bridge piece that falls next (05b, 02)
vine_count:     .res 1          ; the vines on the screen (05a, 07)
vine_height:    .res 1          ; (05a)
vine_slots:     .res 3          ; the enemy slots of the vines (05a, 07)
vine_start_y:   .res 1          ; the first vine's start Y (05a, 11)
balance_side:   .res 1          ; the balance lifts: the slot of the waiting lift (05a, 05b)
lift_scroll:    .res 1          ; the scroll that a moving lift gives the player (05b, 04)
cannon_next:    .res 1          ; the next cannon record (also the whirlpools) (05a, 06)
cannon_page:    .res CANNONS    ; per cannon: its page; per whirlpool its left edge's page (05a, 06)
cannon_x:       .res CANNONS    ; per cannon: its X; per whirlpool: its left edge
cannon_y:       .res CANNONS    ; per cannon: its Y; per whirlpool: its length
cannon_timer:   .res CANNONS    ; per cannon: picks to its next shot; byte 0 is also the whirlpool flag (05a)
jump_coin_slot: .res 5          ; the misc slot of a coin from a block (05a, 07)
sprite_offset_select: .res 1    ; which block sprite set a block uses (05a, 11)
fireworks_count: .res 1         ; the fireworks to show (03, 05b)
area_change_timer: .res 1       ; frames until the next area starts (03, 07)
range_from_origin: .res 1       ; how far an enemy moves from its start (05b)
box_corners:    .res BOX_SLOTS * 4 ; per box: left, top, right, bottom (07)
flag_score:     .res 1          ; the flagpole score, 0-4 (07, 11)
flag_score_y:   .res 2          ; the flagpole score number: its fraction, then its Y (07, 11)

; ---- Shared by the parts (from their reports) --------------------------------
.segment "AREASTATE"
gravity_up:     .res 1          ; the player's fall force while A is held (04 writes; 07 at a spring; 05a reads)
player_anim_rate: .res 1        ; frames for each step of the player's animation (04 writes; 11 reads)
player_anim_step: .res 1        ; the step of the player's animation, 0-2 (0-9 in a size change) (11, 04)
parser_task:    .res 1          ; the column builder's next step, 0-8 (06; 02 screen.s, 05a read)
parse_page:     .res 1          ; the page of the column being built, 0-31 (06, 03; 05a reads)
parse_column:   .res 1          ; the column in that page, 0-15 (06; 05a reads)
column_in_buffer: .res 1        ; the column being built in the collision buffers, 0-31 (06, 03; 07 reads)
column_metatiles: .res METATILE_ROWS ; the metatiles of the column built last, top first (06; 02, 07 read)
coin_brick_flag: .res 1         ; one coin brick started its timer (07 sets, 06 and 05a clear and read)
spawn_kind:     .res 1          ; next_spawn_record (06): SPAWN_END, SPAWN_SKIP, SPAWN_LINK or the kind (05a reads)
spawn_hard_only: .res 1         ;   nonzero: the enemy comes only in hard mode
spawn_x:        .res 2          ;   world X: page x 256 + column x 16
spawn_y:        .res 1          ;   row x 16
spawn_area_byte: .res 1         ;   an area link: its area byte
spawn_link_world: .res 1        ;   an area link: its world
spawn_entrance_page: .res 1     ;   an area link: the entrance page
enemy_draw_code: .res 1         ; the drawing code of the enemy being drawn (11); its leftover is 05a L3
probe_row:      .res 2          ; probe_tile (07): the tested cell's row offset (16 x the row, wrapped as the original's),
                                ; 8 bits in the low byte, read as a word with its high byte 0
probe_column:   .res 1          ; probe_tile (07): the tested cell's column, 0-31 (bit 4 the buffer)

; ---- The sound commands (08) -------------------------------------------------
; The game logic writes a command; the sound program takes it in the next frame.
snd_area_queue: .res 1          ; an area song (SONG_*)
snd_event_queue: .res 1         ; an event song (EVENT_*)
snd_square1_queue: .res 1       ; a square 1 effect (SQUARE1_*)
snd_square2_queue: .res 1       ; a square 2 effect (SQUARE2_*)
snd_noise_queue: .res 1         ; a noise effect (NOISE_*)
snd_pause_queue: .res 1         ; the pause sound
snd_event_music: .res 1         ; the event song that plays, 0 none: the sound part writes it; the
                                ; player (04 control_player) and the modes (03 wait_for_area_end) read it

.segment "GAMEPLAY"
