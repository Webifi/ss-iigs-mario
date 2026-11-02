; Game music and sound effects, ported from $F2D0-$F90C of the original.
; frame.s calls sound_frame before the game logic each frame. It reads the
; sound command bits and mode from state.inc, then sends channel updates to
; the sound model in src/sound.s. A command written by game logic takes
; effect on the next frame. scripts/song_data.py builds the song and effect
; tables; the game does not decode the original song format.
;
; The frame starts the sequencer, handles pause or effects, then music, and
; clears commands. Later writes to a channel win. Interrupts stay masked
; while the frame's sound writes run, so the model cannot tick between them.
; snd_event_music reports the current event song to the player and mode code.

.include "sound.inc"            ; the model's calls and the forms of their values

; ---- The forms of the build's data (scripts/song_data.py) ------------------
; A song: its parts and its volume table (song_lists).
.struct SongRecord
        square2         .word   ; the offset of its square 2 part in song_lists
        square1         .word   ; its square 1 part; 0: the song has none
        triangle        .word   ; its triangle part
        drums           .word   ; its drum loop; 0: the song plays no drums
        volume_base     .byte   ; its volume table: the offset in music_volumes
        volume_start    .byte   ; the volume step of a note's first frame: the table's size
        volume_steps    .byte   ; 0: the song has no volume steps
.endstruct
; A note of a square part (square 2 and square 1). frames 0: square 2: the
; song ends; square 1: the death sound setting, one byte.
.struct SquareNote
        frames          .byte   ; the frames of the note, 1-255
        period          .word   ; its period; REST: a rest
.endstruct
; A note of a triangle part.
.struct TriangleNote
        frames          .byte
        period          .word   ; REST: a rest
        control         .byte   ; the triangle's control after the note's stores
.endstruct
; A beat of a drum loop. frames 0: the loop starts again, one byte.
.struct DrumBeat
        frames          .byte
        control         .byte   ; the noise's control
        period          .byte   ; the noise's period
        length          .byte   ; the length index
.endstruct
LIST_MARKER = 0                 ; frames 0: the end, the death sound setting, the loop
NO_LIST = 0                     ; a SongRecord offset: no part
REST = 0                        ; the period of a rest
.assert LIST_MARKER = 0 && NO_LIST = 0, error, "a marker or an empty list: the Z flag of its load"
; load_song's count of each part: each reads its first note in the song's
; first frame.
START_COUNT = 1
PERIOD_SIZE = 2                 ; a period in the effect tables is a word
; The tables of songs (event_songs, area_songs, ground_parts): a SongRecord
; offset (a word) for each song, a pair (normal, fast) for the area songs and
; the ground parts.
SONG_RECORD = 2                 ; the bytes of one table entry
COMMAND_BITS = 8                ; the bits of a song command
; event_songs: after the records of the event bits, the time-out song at the
; fast tempo.
TIME_OUT_FAST_RECORD = SONG_RECORD * COMMAND_BITS
TEMPO_NORMAL = 0                ; song_tempo: the offset of a song's normal record in its pair
TEMPO_FAST = SONG_RECORD        ; the fast record (after a time-out command)
SONG_PAIR_SHIFT = 2             ; an area bit or a ground part has 4 bytes: x 4
GROUND_PARTS = GROUND_PARTS_SIZE >> SONG_PAIR_SHIFT ; the ground parts: songs 17-49

; ---- The commands and the values of the program ------------------------
; The pause commands (snd_pause_queue): pause_check writes pause + 1.
PAUSE_SOUND = 1                 ; the game pauses
RESUME_SOUND = 2                ; the game goes on

; A note store: the period, then the length index 1, 254 half clocks (127
; frames), longer than any note of the program.
NOTE_LENGTH = 1
; The program's "sweep off": off, rate 7, down, shift 7; it never silences
; a square.
SWEEP_OFF = 7 << SWEEP_RATE_SHIFT | SWEEP_NEGATE | SWEEP_SHIFT
; The control of a music note: duty 50%, decay rate 2.
MUSIC_CONTROL = DUTY_50 | 2
; The death song's square 1 sweep, from its 0 byte: on, rate 1, up, shift 4:
; each note bends down, once each frame.
DEATH_SWEEP = SWEEP_ENABLE | 1 << SWEEP_RATE_SHIFT | 4
; The rest stores of the songs with no volume steps. At a
; rest the original's note routine stores nothing and leaves its registers:
; the channel's register offset becomes the control and the note value the
; sweep.
SQUARE2_REST_CONTROL = DUTY_12 | 4 ; duty 12.5%, decay rate 4 ($04)
SQUARE2_REST_SWEEP = 4         ; $04: off, rate 0, up, shift 4; it silences only a period above $787
SQUARE1_REST_CONTROL = DUTY_12 | 0 ; duty 12.5%, decay rate 0 ($00)
; The song end: both squares silent, the triangle's linear
; counter to 0.
SONG_END_CONTROL = DUTY_50 | CONTROL_CONSTANT | 0
SONG_END_TRIANGLE = 0
; The songs that play again at their end: ground, water, underground, castle,
; cloud, star: every area song but the pipe intro and the silence.
LOOPING_AREA_SONGS = <~(SONG_PIPE_INTRO | SONG_SILENCE)
; The ground song's parts (ground_part): the part before the lead-in, and the
; part after the last (song 18, part 1).
GROUND_PART_NONE = $FF
GROUND_PART_LOOP = 1
; The sample level: it rises during these songs, to this level.
RAMP_SONGS = SONG_GROUND | SONG_WATER
SAMPLE_LEVEL_TOP = $30

; The pause sound: four tones on square 1 over 42 frames.
PAUSE_FRAMES = 42
PAUSE_CONTROL = DUTY_50 | 4     ; duty 50%, decay rate 4 ($84)
PAUSE_LOW_NOTE = $44            ; frames 1 and 13
PAUSE_HIGH_NOTE = $64           ; frames 7 and 19
PAUSE_SECOND_TONE = 7
PAUSE_THIRD_TONE = 13
PAUSE_FOURTH_TONE = 19

; ---- The effects --------------------------------------------
; The effect of a square: the index of its routine in the tables of its
; channel: 2 x (1 + the place of its command bit in the order bit 7, then
; bits 0 to 6). Square 1 and square 2 share the order.
NO_EFFECT = 0
.assert NO_EFFECT = 0, error, "an effect is stopped with STZ and tested with the Z flag"
EFFECT_STEP = 2                 ; one table entry
FIRST_COMMAND_BIT = %10000000   ; bit 7: the first in the order
SQUARE1_EFFECT_SMALL_JUMP = 2   ; bit 7
SQUARE1_EFFECT_BIG_JUMP = 4     ; bit 0
SQUARE1_EFFECT_BUMP = 6         ; bit 1
SQUARE1_EFFECT_STOMP = 8        ; bit 2
SQUARE1_EFFECT_SMACK = 10       ; bit 3
SQUARE1_EFFECT_PIPE = 12        ; bit 4
SQUARE1_EFFECT_FIREBALL = 14    ; bit 5
SQUARE1_EFFECT_FLAGPOLE = 16    ; bit 6
SQUARE2_EFFECT_BOWSER_FALL = 2  ; bit 7
SQUARE2_EFFECT_COIN = 4         ; bit 0
SQUARE2_EFFECT_GROW_POWERUP = 6 ; bit 1
SQUARE2_EFFECT_GROW_VINE = 8    ; bit 2
SQUARE2_EFFECT_BLAST = 10       ; bit 3
SQUARE2_EFFECT_TICK = 12        ; bit 4
SQUARE2_EFFECT_GRAB = 14        ; bit 5
SQUARE2_EFFECT_EXTRA_LIFE = 16  ; bit 6
NOISE_EFFECT_BRICK = 2          ; bit 0
NOISE_EFFECT_FLAME = 4          ; bit 1
; EFFECT_BIT(index): the command bit of a square effect's index, in the order
; of effect_of_command (index 2 is bit 7, 4 is bit 0, ... 16 is bit 6). The
; asserts check the effect tables against the command bits of state.inc.
.define EFFECT_BIT(index) (1 << ((index / EFFECT_STEP + 6) .mod 8))
.assert SQUARE1_SMALL_JUMP = EFFECT_BIT(SQUARE1_EFFECT_SMALL_JUMP), error, "square1_starts"
.assert SQUARE1_BIG_JUMP = EFFECT_BIT(SQUARE1_EFFECT_BIG_JUMP), error, "square1_starts"
.assert SQUARE1_BUMP = EFFECT_BIT(SQUARE1_EFFECT_BUMP), error, "square1_starts"
.assert SQUARE1_ENEMY_STOMP = EFFECT_BIT(SQUARE1_EFFECT_STOMP), error, "square1_starts"
.assert SQUARE1_ENEMY_SMACK = EFFECT_BIT(SQUARE1_EFFECT_SMACK), error, "square1_starts"
.assert SQUARE1_PIPE_INJURY = EFFECT_BIT(SQUARE1_EFFECT_PIPE), error, "square1_starts"
.assert SQUARE1_FIREBALL = EFFECT_BIT(SQUARE1_EFFECT_FIREBALL), error, "square1_starts"
.assert SQUARE1_FLAGPOLE = EFFECT_BIT(SQUARE1_EFFECT_FLAGPOLE), error, "square1_starts"
.assert SQUARE2_BOWSER_FALL = EFFECT_BIT(SQUARE2_EFFECT_BOWSER_FALL), error, "square2_starts"
.assert SQUARE2_COIN = EFFECT_BIT(SQUARE2_EFFECT_COIN), error, "square2_starts"
.assert SQUARE2_GROW_POWERUP = EFFECT_BIT(SQUARE2_EFFECT_GROW_POWERUP), error, "square2_starts"
.assert SQUARE2_GROW_VINE = EFFECT_BIT(SQUARE2_EFFECT_GROW_VINE), error, "square2_starts"
.assert SQUARE2_BLAST = EFFECT_BIT(SQUARE2_EFFECT_BLAST), error, "square2_starts"
.assert SQUARE2_TIMER_TICK = EFFECT_BIT(SQUARE2_EFFECT_TICK), error, "square2_starts"
.assert SQUARE2_POWERUP_GRAB = EFFECT_BIT(SQUARE2_EFFECT_GRAB), error, "square2_starts"
.assert SQUARE2_EXTRA_LIFE = EFFECT_BIT(SQUARE2_EFFECT_EXTRA_LIFE), error, "square2_starts"
.assert NOISE_BRICK_SHATTER = %00000001 && NOISE_BOWSER_FLAME = %00000010, error, "noise_effects"
; An effect's frame f runs with the count at FRAMES + 1 - f: each effect
; counts its frames down from FRAMES, frame 1 included.

; Square 1 (store order of the original: the sweep, the control, the note).
; The jumps: three parts.
JUMP_FRAMES = 40
SMALL_JUMP_NOTE = $26
BIG_JUMP_NOTE = $18
JUMP_SWEEP = SWEEP_ENABLE | 2 << SWEEP_RATE_SHIFT | 7 ; $A7: on, rate 2, up, shift 7
JUMP_CONTROL = DUTY_50 | 2      ; $82: decay rate 2
JUMP_RISE_FRAME = 4
JUMP_RISE_SWEEP = SWEEP_ENABLE | 7 << SWEEP_RATE_SHIFT | 6 ; $F6
JUMP_RISE_CONTROL = DUTY_25 | CONTROL_CONSTANT | 15 ; $5F
JUMP_FALL_FRAME = 9             ; the decay shows the level that it reached since frame 1
JUMP_FALL_SWEEP = SWEEP_ENABLE | 3 << SWEEP_RATE_SHIFT | SWEEP_NEGATE | 4 ; $BC: down
JUMP_FALL_CONTROL = DUTY_25 | 8 ; $48: decay rate 8
; The flagpole: one note, stored before its sweep and control.
FLAGPOLE_FRAMES = 64
FLAGPOLE_NOTE = $62
FLAGPOLE_SWEEP = JUMP_FALL_SWEEP ; $BC
FLAGPOLE_CONTROL = DUTY_50 | CONTROL_CONSTANT | 9 ; $99
; The bump and the fireball: one note with the same control.
BUMP_FRAMES = 10
BUMP_NOTE = $0C
BUMP_CONTROL = DUTY_50 | CONTROL_CONSTANT | 14 ; $9E
BUMP_SWEEP = SWEEP_ENABLE | 1 << SWEEP_RATE_SHIFT | 3 ; $93
BUMP_SECOND_FRAME = 5
BUMP_SECOND_SWEEP = SWEEP_ENABLE | 3 << SWEEP_RATE_SHIFT | SWEEP_NEGATE | 3 ; $BB
FIREBALL_FRAMES = 5             ; it ends before the bump's second part
FIREBALL_SWEEP = SWEEP_ENABLE | 1 << SWEEP_RATE_SHIFT | SWEEP_NEGATE | 1 ; $99
; The stomp and the swim stroke: the volume of each frame from stomp_volumes.
STOMP_FRAMES = 14
STOMP_NOTE = $26
STOMP_SWEEP = SWEEP_ENABLE | 1 << SWEEP_RATE_SHIFT | SWEEP_NEGATE | 4 ; $9C
STOMP_SECOND_FRAME = 9
; The original stores the low byte $9E of the period here. The note $26
; has the period $0FE (below $100, scripts/song_data.py note_periods) and
; the sweep only lowers it, so the period's high bits are 0.
STOMP_SECOND_PERIOD = $09E
; The smack: a tone with gaps.
SMACK_FRAMES = 14
SMACK_NOTE = $28
SMACK_SWEEP = SWEEP_ENABLE | 4 << SWEEP_RATE_SHIFT | SWEEP_NEGATE | 3 ; $CB
SMACK_CONTROL = DUTY_50 | CONTROL_CONSTANT | 15 ; $9F
SMACK_GAP_CONTROL = DUTY_50 | CONTROL_CONSTANT | 0 ; $90
SMACK_SECOND_FRAME = 7
SMACK_SECOND_PERIOD = $0A0      ; the low byte $A0; the note $28 has the period $0EF
; The pipe and the injury: one note at six frames, when the count has bits 0
; and 1 clear and bit 3 set (frames 4, 8, 20, 24, 36, 40).
PIPE_SOUND_FRAMES = 47
PIPE_NOTE = $44
PIPE_SWEEP = SWEEP_ENABLE | 1 << SWEEP_RATE_SHIFT | 1 ; $91
PIPE_CONTROL = DUTY_50 | CONTROL_CONSTANT | 10 ; $9A
PIPE_TONE_CLEAR = %00000011
PIPE_TONE_SET = %00001000
.assert PIPE_SOUND_FRAMES & PIPE_TONE_CLEAR, error, "the pipe's frame 1 has no note"

; Square 2 (store order of the original: the control, the sweep, the note).
; The coin and the timer tick.
COIN_FRAMES = 53
TICK_FRAMES = 6                 ; it ends before the coin's second tone
COIN_NOTE = $42
COIN_CONTROL = DUTY_50 | 13     ; $8D: decay rate 13
TICK_CONTROL = DUTY_50 | CONTROL_CONSTANT | 8 ; $98
COIN_SECOND_FRAME = 6
COIN_SECOND_PERIOD = $054       ; the low byte $54; the note $42 has the period $071, no sweep
; The power-up and the vine as they grow: grow_frame counts the frames from
; 1; each step of two frames plays grow_periods[step] until the step equals
; the length. square2_effect_frames holds the length and does not count.
GROW_POWERUP_STEPS = 16
GROW_VINE_STEPS = 32
GROW_CONTROL = DUTY_50 | CONTROL_CONSTANT | 13 ; $9D
GROW_STEP_OFFSET = %11111110    ; grow_frame without bit 0: the step x 2, the offset of its period
; The blast (fireworks, cannon bullets, bridge pieces) and Bowser's fall:
; two tones each, the same control.
BLAST_FRAMES = 32
BLAST_CONTROL = DUTY_50 | CONTROL_CONSTANT | 15 ; $9F
BLAST_NOTE = $5E
BLAST_SWEEP = SWEEP_ENABLE | 1 << SWEEP_RATE_SHIFT | 4 ; $94
BLAST_SECOND_FRAME = 9
BLAST_SECOND_NOTE = $18
BLAST_SECOND_SWEEP = SWEEP_ENABLE | 1 << SWEEP_RATE_SHIFT | 3 ; $93
BOWSER_FALL_FRAMES = 56
BOWSER_FALL_NOTE = $18
BOWSER_FALL_SWEEP = SWEEP_ENABLE | 4 << SWEEP_RATE_SHIFT | 4 ; $C4
BOWSER_FALL_SECOND_FRAME = 49
BOWSER_FALL_SECOND_NOTE = $5A
BOWSER_FALL_SECOND_SWEEP = SWEEP_ENABLE | 2 << SWEEP_RATE_SHIFT | 4 ; $A4
; The power-up grab: a note on each even count c, powerup_grab_periods[c/2 - 1].
GRAB_FRAMES = 54
GRAB_CONTROL = DUTY_25 | CONTROL_CONSTANT | 13 ; $5D
; The 1-up: a note when the count is a multiple of 8, extra_life_periods[c/8 - 1].
EXTRA_LIFE_FRAMES = 48
EXTRA_LIFE_CONTROL = DUTY_50 | 2 ; $82: decay rate 2
EXTRA_LIFE_TONE = %00000111     ; a note when these bits of the count are clear

; The noise (store order: the control, the period, the length).
BRICK_FRAMES = 32               ; a burst on each odd count, one frame long
FLAME_FRAMES = 64               ; a burst on each frame
FLAME_PERIOD = 15               ; the period index of the flame (long sequence)
NOISE_BURST_LENGTH = 3          ; the length index 3: 2 half clocks, one frame
NOISE_END_CONTROL = CONTROL_LOOP | CONTROL_CONSTANT | 0 ; the length holds, volume 0 (the
                                ; original's $F0 also sets bits 7-6, which the noise does not use)

; ---- The state of the program ----------------------------------------------
; The original keeps it at $F0-$FF and $07B0-$07CA. Each area
; start clears the first group (the original's $F0-$FF); the start of a game
; clears both. snd_event_music, which the game reads, is
; in the second group of the original ($07B1) and in state.inc.
.segment "GAMESTATE"
sound_state:
; -- Cleared at each area start and at a game start (the original's $F0-$F9).
; The effect that plays on each channel (NO_EFFECT or its *_EFFECT_* index):
; written by the effects and the pause; read by the effects and the music
; (a square's music waits while its effect plays) and by effect_levels.
square1_effect: .res 1          ; (snd_square1_playing $F1)
square2_effect: .res 1          ; (snd_square2_playing $F2)
noise_effect: .res 1            ; (snd_noise_playing $F3)
; The area song that plays (one SONG_* bit), 0 none: written by the song
; loads and the song end; read by music_step, song_end and the sample level.
snd_area_music: .res 1          ; ($F4)
; The next note of each part: an offset in song_lists. load_song writes them,
; song_frame reads and moves them; square1_position 0: no square 1 part.
square2_position: .res 2        ; (the data address and its offsets, $F5-$F9)
square1_position: .res 2
triangle_position: .res 2
sound_area_state_end:
; -- Cleared at a game start (the original's $07B0-$07CA).
drum_position: .res 2           ; the next drum beat; 0: no drums ($07B0)
drum_loop: .res 2               ; the drum loop's start ($07C1)
; The frames to each part's next note, 1-255 (load_song: 1).
square2_count: .res 1           ; ($07B4)
square1_count: .res 1           ; ($07B6)
triangle_count: .res 1          ; ($07B9)
drum_count: .res 1              ; ($07BA)
; The volume step of each square's note, 0-40: a note starts it at
; song_volume_start, a rest at 0; each frame reads music_volumes at
; song_volume_base + the step, then the step goes down to 0 and stays.
square2_volume: .res 1          ; ($07B5)
square1_volume: .res 1          ; ($07B7)
; The song's volume table (load_song, from its SongRecord).
song_volume_base: .res 1        ; its offset in music_volumes
song_volume_start: .res 1       ; the step of a note's first frame
song_volume_steps: .res 1       ; 0: no volume steps
; The sweep of the song's square 1 part: 0 (SWEEP_OFF is stored) or
; DEATH_SWEEP; load_song clears it, the death song's 0 byte sets it.
square1_sweep: .res 1           ; (snd_square1_alt_sweep $07CA)
; The frames left of each effect (written at its start, counted down by it).
square1_effect_frames: .res 1   ; ($07BB)
square2_effect_frames: .res 1   ; ($07BD); a grow effect's length, which does not count
noise_effect_frames: .res 1     ; ($07BF)
grow_frame: .res 1              ; the grow effects' frame, 1-64 ($07BE)
; The pause.
pause_mode: .res 1              ; 0 normal, PAUSE_SOUND paused, RESUME_SOUND resuming ($07C6)
pause_sound: .res 1             ; the sound that plays: 0, PAUSE_SOUND, RESUME_SOUND ($07B2)
pause_frames: .res 1            ; the frames left of it (the original counts them in $07BB)
; The songs.
; song_tempo: TEMPO_NORMAL, or TEMPO_FAST from a time-out command to the next
; event song.
song_tempo: .res 1              ; ($07C4)
snd_area_saved: .res 1          ; the area song when the last event song started ($07C5)
; ground_part: the ground song's part, GROUND_PART_NONE at a ground command,
; then 0-32.
ground_part: .res 1             ; ($07C7)
sample_level: .res 1            ; the sample channel's level, 0-SAMPLE_LEVEL_TOP ($07C0)
sound_state_end:
SOUND_AREA_STATE_SIZE = sound_area_state_end - sound_state
SOUND_STATE_SIZE = sound_state_end - sound_state

; Its place in memory: bank 0, segment SOUND, beside the model, for speed.
; The model's routines are called with JSR (12 cycles with the return) where
; a call from bank 1 would take JSL and RTL (14), and the latch calls are
; stores into the model's bank 0 latches inline. The frame calls sound_frame
; once a frame with JSL. Its variables are in GAMESTATE (bank 0, absolute
; with DBR = 0); it does not use the direct page, so D may point at any
; record. Its effect tables and the music's volume tables (read every frame
; of an effect or a note) are in bank 0; the songs are in a data bank and
; read with long indexed addressing, which costs the same 5 cycles as a bank
; 0 read with a 16-bit index.
;
; The times in the routine headers are 65816 cycles with the call and the
; return, counted over the songs and 40,000 frames of random commands.
.segment "SOUND"
.a8
.i8

; ---------------------------------------------------------------------------
; sound_power_on: the sound unit as the original's power-on leaves it: the sample channel's level 0, and the two
; squares, the triangle and the noise on (the sample channel stays off).
;
; In:       A8 I8; DBR = 0; any D
; Out:      A8 I8
; Changes:  A, X, the flags
; Time:     once
; Original: $8000-$8056 (the sound unit stores of game_power_on)
; ---------------------------------------------------------------------------
sound_power_on:
.a8
.i8
        lda #0
        apu_sample_level
        lda #CHANNELS_ALL
        apu_enable
        rtl

; ---------------------------------------------------------------------------
; sound_frame: one frame of the sound program: the sequencer start and the
; channels on, then the pause sound, or the effects and the music; the
; commands of this frame cleared; the sample level; the channels that play
; an effect to the model. In the title and the demo (mode 0)
; it only turns all channels off and reads no command.
;
; The ticks of the model wait while it runs (SEI): its calls of one frame act
; together, with no clock between them.
;
; In:       A8 I8, DBR = 0, D any (JSL from the frame, src/game/frame.s)
;           mode; the snd_*_queue commands of the frame before
; Out:      the model's calls of this frame; snd_square1_queue,
;           snd_square2_queue, snd_noise_queue, snd_pause_queue = 0; also
;           snd_event_queue and snd_area_queue = 0 unless the pause sound
;           plays (they wait for its end); snd_event_music; apu_set_effects
; Changes:  A, X, Y, the flags; the state of this file
; Keeps:    D, DBR; the interrupt flag (it comes back with the flags)
; Time:     194 cycles in the title; 963-1019 in a frame of the ground song with
;           no effect, 2134 in the frame that starts it; 194-2529 (median 627)
;           in 40,000 frames of random commands
; Original: $F2D0-$F380
; ---------------------------------------------------------------------------
; Stores that a later store of the same frame replaces are not made:
; the stomp's first control, the death song's first square 1 control,
; the brick's and the flame's last controls, the music note's control
; and sweep where a volume step follows. The stomp's and the smack's
; last volumes are made: the cut that follows does not change the
; control, and its level is the envelope's divider period.

sound_frame:
.a8
.i8
        php
        sei                             ; no tick between the calls of this frame
        .assert MODE_TITLE = 0, error, "sound_frame: the mode's Z flag"
        lda mode
        bne @play
        lda #CHANNELS_NONE              ; the title and the demo: silence, nothing else
        apu_enable
        plp
        rtl
@play:
; The sequencer starts again: its quarter and half clock of the frame's
; start act on the stores of the frame before.
        lda #SEQUENCE_FIVE_STEP
        apu_sequence
; All channels on: a channel that the frame before cut or turned off takes
; its next length load.
        lda #CHANNELS_ALL
        apu_enable
; The pause sound runs in the place of the effects and the music while the
; game is paused or resuming, and when the pause command starts it.
        lda pause_mode
        bne @pause
        lda snd_pause_queue
        cmp #PAUSE_SOUND
        bne @game
@pause:
        jsr pause_frame
        bra @commands                   ; the song commands wait for its end
@game:
        jsr square1_effects
        jsr square2_effects
        jsr noise_effects
        jsr music_step
        stz snd_event_queue             ; the song commands are used
        stz snd_area_queue
@commands:
; A command lives one frame.
        stz snd_square1_queue
        stz snd_square2_queue
        stz snd_noise_queue
        stz snd_pause_queue
        jsr sample_level_step
        jsr effect_levels
        plp
        rtl

; ---------------------------------------------------------------------------
; pause_frame: one frame of the pause state: a start of the
; pause or resume sound, a tone, the count, and the sound's end. A start cuts
; every channel and ends the three effects; the sound is four tones on
; square 1; at its end every channel is cut, and a resume sound gives the
; game's sound back.
;
; In:       A8 I8; pause_mode, pause_sound, snd_pause_queue
; Out:      pause_mode, pause_sound, pause_frames; at a start the three effects
;           NO_EFFECT
; Changes:  A, X, the flags
; Keeps:    Y
; Time:     25 cycles while paused; 454 at most (a start)
; Original: $F2E3-$F349
; ---------------------------------------------------------------------------
;   The pause (pause_mode, pause_sound):
;   | state        | mode, sound | each frame                 | moves to                          |
;   |--------------|-------------|----------------------------|-----------------------------------|
;   | normal       | 0, 0        | effects and music          | command PAUSE_SOUND: pause sound  |
;   | pause sound  | 1, 1        | the tones; nothing else    | its end: paused                   |
;   | paused       | 1, 0        | nothing                    | command 1 or 2: that sound        |
;   | resume sound | 2, 2        | the tones; nothing else    | its end: normal                   |
;

pause_frame:
.a8
.i8
        lda pause_sound
        bne @playing
        lda snd_pause_queue
        beq @done                       ; paused: nothing plays
; The start: both bytes take the command; every channel is cut and the
; effects end.
        sta pause_sound
        sta pause_mode
        lda #CHANNELS_NONE
        apu_enable
        stz square1_effect
        stz square2_effect
        stz noise_effect
        lda #CHANNELS_ALL
        apu_enable
        lda #PAUSE_FRAMES
        sta pause_frames
        bra @low                        ; frame 1: the low tone
@playing:
; The tones of frames 7, 13 and 19 (the count is PAUSE_FRAMES + 1 - frame).
        lda pause_frames
        cmp #PAUSE_FRAMES + 1 - PAUSE_SECOND_TONE
        beq @high
        cmp #PAUSE_FRAMES + 1 - PAUSE_THIRD_TONE
        beq @low
        cmp #PAUSE_FRAMES + 1 - PAUSE_FOURTH_TONE
        bne @count
@high:
        rep #P_M8
.a16
        lda note_periods+PAUSE_HIGH_NOTE
        bra @tone
@low:
.a8
        rep #P_M8
.a16
        lda note_periods+PAUSE_LOW_NOTE
@tone:
.a16
        jsr square1_note
.a8
        lda #SWEEP_OFF
        apu_sweep APU_SQUARE1
        lda #PAUSE_CONTROL
        apu_control APU_SQUARE1
@count:
.a8
        dec pause_frames
        bne @done
; The end: every channel off until the next frame turns them on (a cut of
; all four); the resume sound gives the game's sound back.
        lda #CHANNELS_NONE
        apu_enable
        lda pause_sound
        cmp #RESUME_SOUND
        bne @paused
        stz pause_mode
@paused:
        stz pause_sound
@done:
        rts

; ---------------------------------------------------------------------------
; sample_level_step: the sample channel's level, which the NES mixer turns
; into a quieter triangle and noise: during the ground and the water songs it
; rises by 1 each frame to SAMPLE_LEVEL_TOP, else it falls by 1 to 0. The
; store is the level before this frame's step.
;
; In:       A8 I8; sample_level, snd_area_music
; Out:      sample_level; the model's sample level
; Changes:  A, the flags
; Keeps:    X, Y
; Time:     39-56 cycles
; Original: $F367-$F380
; ---------------------------------------------------------------------------
; Corresponding original code: $F35D.

sample_level_step:
.a8
.i8
        lda sample_level
        apu_sample_level
        lda snd_area_music
        and #RAMP_SONGS
        beq @fall
        lda sample_level
        cmp #SAMPLE_LEVEL_TOP
        bcs @done                       ; it stays at the top
        inc sample_level
        rts
@fall:
        lda sample_level
        beq @done                       ; it stays at 0
        dec sample_level
@done:
        rts

; ---------------------------------------------------------------------------
; effect_levels: tell the model which channels play an effect: square 1 for
; its effects and the pause sound, square 2, the noise. The model plays them
; at the effects level of the options menu, the other channels at the music
; level.
;
; In:       A8 I8; square1_effect, pause_sound, square2_effect, noise_effect
; Out:      apu_set_effects (src/sound.s) with the CHANNEL_* bits
; Changes:  A, X, the flags
; Keeps:    Y
; Time:     47-72 cycles
; Original: none (the port's options menu)
; ---------------------------------------------------------------------------
effect_levels:
.a8
.i8
        lda #CHANNELS_NONE
        ldx square1_effect
        bne @square1
        ldx pause_sound
        beq @square2
@square1:
        ora #CHANNEL_SQUARE1
@square2:
        ldx square2_effect
        beq @noise
        ora #CHANNEL_SQUARE2
@noise:
        ldx noise_effect
        beq @set
        ora #CHANNEL_NOISE
@set:
        jmp apu_set_effects

; ---------------------------------------------------------------------------
; cut_channel: a cut: the channel's enable bit off, then all channels on
; again. Its length counter becomes 0, so it is silent until its next length
; load.
;
; In:       A8 = the channel's bit (CHANNEL_*); I8
; Out:      the model's enable calls
; Changes:  A, X, the flags
; Keeps:    Y
; Time:     177-180 cycles
; Original: the pairs of $4015 stores at $F4AB, $F571, $F730
; ---------------------------------------------------------------------------
cut_channel:
.a8
.i8
        eor #CHANNELS_ALL
        apu_enable
        lda #CHANNELS_ALL
        apu_enable
        rts

; ---------------------------------------------------------------------------
; square1_note, square2_note, triangle_note: a note store: the period, then
; the length load of a note (NOTE_LENGTH), which also starts the envelope
; again (the triangle: its linear counter reloads).
;
; In:       A16 = the period, 1-$7FF; I8
; Out:      A8
; Changes:  A, X, the flags
; Keeps:    Y
; Time:     114-127 cycles
; Original: $F38B, $F3A9, $F3AD (their rest test is the caller's)
; ---------------------------------------------------------------------------
square1_note:
.a16
.i8
        apu_period APU_SQUARE1
        lda #NOTE_LENGTH
        apu_length APU_SQUARE1
        rts
square2_note:
.a16
.i8
        apu_period APU_SQUARE2
        lda #NOTE_LENGTH
        apu_length APU_SQUARE2
        rts
triangle_note:
.a16
.i8
        apu_period APU_TRIANGLE
        lda #NOTE_LENGTH
        apu_length APU_TRIANGLE
        rts

; ---------------------------------------------------------------------------
; effect_of_command: the effect of a square's command: its first set bit in
; the order bit 7, then bits 0 to 6. A rotation puts bit 7 below
; bit 0, so the order becomes bit 0 up, and the first set bit is the first
; one that a right shift gives.
;
; In:       A8 = the command, not 0; I8
; Out:      X = the effect: EFFECT_STEP x (1 + the bit's place in that order)
; Changes:  A, the flags
; Keeps:    Y
; Time:     23-100 cycles
; Original: the bit tests of $F41F-$F43D and $F586-$F5A4
; ---------------------------------------------------------------------------
effect_of_command:
.a8
.i8
        cmp #FIRST_COMMAND_BIT          ; carry = bit 7
        rol a                           ; bit 7 into bit 0
        ldx #EFFECT_STEP
@bit:
        lsr a
        bcs @found
        inx
        inx
        bra @bit                        ; A is not 0: a bit comes
@found:
        rts

; ===========================================================================
; Square 1: the jumps, the bump, the stomp and the swim stroke, the smack,
; the pipe and the injury, the fireball, the flagpole.
; ===========================================================================

; ---------------------------------------------------------------------------
; square1_effects: the effect of the command when there is one (the effect
; of its first bit runs its frame 1), else one frame of the effect that
; plays.
;
; In:       A8 I8; snd_square1_queue, square1_effect
; Out:      square1_effect, square1_effect_frames; the effect's calls
; Changes:  A, X, Y, the flags
; Time:     26 cycles with no effect; 342 at most with the effect's frame
; Original: $F41B-$F45A
; ---------------------------------------------------------------------------
;   An effect of a channel (square1_effect, square2_effect, noise_effect):
;   | state   | value     | moves to                                            |
;   |---------|-----------|-----------------------------------------------------|
;   | none    | NO_EFFECT | a command: the effect of its first bit, frame 1     |
;   | playing | an effect | a command: that command's effect (not over the 1-up)|
;   |         |           | its count reaches 0: none, and a cut (the noise:    |
;   |         |           |   the end control, no cut)                          |
;   |         |           | the pause starts, or an area start clears: none     |
;

square1_effects:
.a8
.i8
        lda snd_square1_queue
        beq @continue
        jsr effect_of_command
        stx square1_effect
        jmp (square1_starts-EFFECT_STEP,x)
@continue:
        ldx square1_effect
        beq @none
        jmp (square1_continues-EFFECT_STEP,x)
@none:
        rts

; The routines of each effect, by its square 1 index.
square1_starts:
        .addr start_small_jump, start_big_jump, start_bump, start_stomp
        .addr start_smack, start_pipe, start_fireball, start_flagpole
square1_continues:
        .addr continue_jump, continue_jump, continue_bump, continue_stomp
        .addr continue_smack, continue_pipe
        .addr square1_count_down        ; the fireball: the bump's second part never comes
        .addr square1_count_down        ; the flagpole: one note

; ---------------------------------------------------------------------------
; square1_count_down: one frame of the square 1 effect less; at 0 the effect
; ends. stop_square1_effect: the effect ends: none plays, and square 1 is cut
; (also from the death command and the underground song).
;
; In:       A8 I8; square1_effect_frames
; Out:      square1_effect_frames; at the end square1_effect = NO_EFFECT
; Changes:  A, X, the flags
; Keeps:    Y
; Time:     17 cycles; 198 at the end
; Original: $F4A2, $F4A7
; ---------------------------------------------------------------------------
square1_count_down:
.a8
.i8
        dec square1_effect_frames
        beq stop_square1_effect
        rts
stop_square1_effect:
.a8
.i8
        stz square1_effect
        lda #CHANNEL_SQUARE1
        jmp cut_channel

; ---------------------------------------------------------------------------
; start_small_jump, start_big_jump: the jump's first part: its note (small or
; big), sweep and control. continue_jump: the second part at frame 4, the
; third at frame 9; the jump ends at frame 40.
;
; In:       A8 I8; square1_effect_frames (continue_jump)
; Out:      the calls on square 1; square1_effect_frames
; Changes:  A, X, the flags
; Keeps:    Y
; Time:     200-229 cycles at the start; 34-212 a frame after
; Original: $F3CD-$F3F8
; ---------------------------------------------------------------------------
start_small_jump:
.a8
.i8
        rep #P_M8
.a16
        lda note_periods+SMALL_JUMP_NOTE
        bra start_jump
start_big_jump:
.a8
.i8
        rep #P_M8
.a16
        lda note_periods+BIG_JUMP_NOTE
start_jump:
.a16
        jsr square1_note
.a8
        lda #JUMP_SWEEP
        apu_sweep APU_SQUARE1
        lda #JUMP_CONTROL
        apu_control APU_SQUARE1
        lda #JUMP_FRAMES
        sta square1_effect_frames
        bra square1_count_down          ; frame 1: only the count
continue_jump:
.a8
.i8
        lda square1_effect_frames
        cmp #JUMP_FRAMES + 1 - JUMP_RISE_FRAME
        bne @fall
        lda #JUMP_RISE_SWEEP
        apu_sweep APU_SQUARE1
        lda #JUMP_RISE_CONTROL
        bra @control
@fall:
        cmp #JUMP_FRAMES + 1 - JUMP_FALL_FRAME
        bne square1_count_down
        lda #JUMP_FALL_SWEEP
        apu_sweep APU_SQUARE1
        lda #JUMP_FALL_CONTROL
@control:
        apu_control APU_SQUARE1
        bra square1_count_down

; ---------------------------------------------------------------------------
; start_flagpole: the flagpole's note, its sweep and its control; then it
; only counts its 64 frames (square1_count_down).
;
; In:       A8 I8
; Out:      the calls on square 1; square1_effect_frames
; Changes:  A, X, the flags
; Keeps:    Y
; Time:     210-226 cycles
; Original: $F3BF-$F3CC
; ---------------------------------------------------------------------------
start_flagpole:
.a8
.i8
        rep #P_M8
.a16
        lda note_periods+FLAGPOLE_NOTE
        jsr square1_note
.a8
        lda #FLAGPOLE_SWEEP
        apu_sweep APU_SQUARE1
        lda #FLAGPOLE_CONTROL
        apu_control APU_SQUARE1
        lda #FLAGPOLE_FRAMES
        sta square1_effect_frames
        jmp square1_count_down

; ---------------------------------------------------------------------------
; start_bump, start_fireball: one note with its own sweep and the bump's
; control; the fireball's 5 frames end before the bump's second part.
; continue_bump: the bump's second sweep at frame 5.
;
; In:       A8 I8; square1_effect_frames (continue_bump)
; Out:      the calls on square 1; square1_effect_frames
; Changes:  A, X, Y, the flags
; Time:     202-231 cycles at the start; 32-210 a frame after
; Original: $F3F9-$F41A
; ---------------------------------------------------------------------------
start_bump:
.a8
.i8
        lda #BUMP_FRAMES
        ldy #BUMP_SWEEP
        bra bump_tone
start_fireball:
.a8
.i8
        lda #FIREBALL_FRAMES
        ldy #FIREBALL_SWEEP
bump_tone:
        sta square1_effect_frames
        tya
        apu_sweep APU_SQUARE1
        lda #BUMP_CONTROL
        apu_control APU_SQUARE1
        rep #P_M8
.a16
        lda note_periods+BUMP_NOTE
        jsr square1_note
.a8
        jmp square1_count_down
continue_bump:
.a8
.i8
        lda square1_effect_frames
        cmp #BUMP_FRAMES + 1 - BUMP_SECOND_FRAME
        bne @count
        lda #BUMP_SECOND_SWEEP
        apu_sweep APU_SQUARE1
@count:
        jmp square1_count_down

; ---------------------------------------------------------------------------
; start_stomp: the stomp's note and sweep. continue_stomp (also its frame 1):
; the control of each frame from stomp_volumes, and the second tone's period
; at frame 9 (a period store with no length load).
; The original's first control ($9E) is replaced in frame 1 by the table's:
; it is not stored.
;
; In:       A8 I8; square1_effect_frames (continue_stomp)
; Out:      the calls on square 1; square1_effect_frames
; Changes:  A, X, the flags
; Keeps:    Y
; Time:     228-237 cycles at the start; 43-228 a frame after
; Original: $F45B-$F47C
; ---------------------------------------------------------------------------
start_stomp:
.a8
.i8
        lda #STOMP_FRAMES
        sta square1_effect_frames
        lda #STOMP_SWEEP
        apu_sweep APU_SQUARE1
        rep #P_M8
.a16
        lda note_periods+STOMP_NOTE
        jsr square1_note
.a8
continue_stomp:
.a8
.i8
        ldx square1_effect_frames
        lda stomp_volumes-1,x           ; the count 14 ... 1 reads the entries 13 ... 0
        apu_control APU_SQUARE1
        cpx #STOMP_FRAMES + 1 - STOMP_SECOND_FRAME
        bne @count
        rep #P_M8
.a16
        lda #STOMP_SECOND_PERIOD
        apu_period APU_SQUARE1
@count:
.a8
        jmp square1_count_down

; ---------------------------------------------------------------------------
; start_smack: the smack's note, sweep and control. continue_smack: a silent
; control in the gaps, and at frame 7 the second tone (its period with no
; length load, and the loud control).
;
; In:       A8 I8; square1_effect_frames (continue_smack)
; Out:      the calls on square 1; square1_effect_frames
; Changes:  A, X, the flags
; Keeps:    Y
; Time:     200-226 cycles at the start; 41-219 a frame after
; Original: $F47D-$F4A1
; ---------------------------------------------------------------------------
start_smack:
.a8
.i8
        lda #SMACK_FRAMES
        sta square1_effect_frames
        lda #SMACK_SWEEP
        apu_sweep APU_SQUARE1
        lda #SMACK_CONTROL
        apu_control APU_SQUARE1
        rep #P_M8
.a16
        lda note_periods+SMACK_NOTE
        jsr square1_note
.a8
        jmp square1_count_down
continue_smack:
.a8
.i8
        lda square1_effect_frames
        cmp #SMACK_FRAMES + 1 - SMACK_SECOND_FRAME
        bne @gap
        rep #P_M8
.a16
        lda #SMACK_SECOND_PERIOD
        apu_period APU_SQUARE1
        lda #SMACK_CONTROL
        bra @control
@gap:
.a8
        lda #SMACK_GAP_CONTROL
@control:
        apu_control APU_SQUARE1
        jmp square1_count_down

; ---------------------------------------------------------------------------
; start_pipe: the pipe and the injury: 47 frames; frame 1 plays nothing
; (square 1 keeps its sound). continue_pipe: the note, its sweep and its
; control when the count has bits 0 and 1 clear and bit 3 set.
;
; In:       A8 I8; square1_effect_frames (continue_pipe)
; Out:      the calls on square 1; square1_effect_frames
; Changes:  A, X, the flags
; Keeps:    Y
; Time:     29 cycles at the start; 32-232 a frame after
; Original: $F4B6-$F4D3
; ---------------------------------------------------------------------------
start_pipe:
.a8
.i8
        lda #PIPE_SOUND_FRAMES
        sta square1_effect_frames
        jmp square1_count_down
continue_pipe:
.a8
.i8
        lda square1_effect_frames
        bit #PIPE_TONE_CLEAR
        bne @count
        bit #PIPE_TONE_SET
        beq @count
        lda #PIPE_SWEEP
        apu_sweep APU_SQUARE1
        lda #PIPE_CONTROL
        apu_control APU_SQUARE1
        rep #P_M8
.a16
        lda note_periods+PIPE_NOTE
        jsr square1_note
.a8
@count:
        jmp square1_count_down

; ===========================================================================
; Square 2: Bowser's fall, the coin, the power-up and the vine as they grow,
; the blast, the timer tick, the power-up grab, the 1-up.
; ===========================================================================

; ---------------------------------------------------------------------------
; square2_effects: while the 1-up holds square 2, it goes on and no command
; acts. Else the effect of the command when there is one (the effect of its
; first bit runs its frame 1), else one frame of the effect that plays. A
; command with the 1-up bit and another bit starts the other bit's effect,
; and the 1-up's steps go on from the next frame on that effect's count.
;
; In:       A8 I8; snd_square2_queue, square2_effect
; Out:      square2_effect, square2_effect_frames; the effect's calls
; Changes:  A, X, Y, the flags
; Time:     35 cycles with no effect; 379 at most with the effect's frame
; Original: $F57C-$F5C7
; ---------------------------------------------------------------------------
; The 1-up bit with another bit: square2_effects starts the other bit's
; effect and makes the 1-up the effect that goes on.

square2_effects:
.a8
.i8
        lda square2_effect
        cmp #SQUARE2_EFFECT_EXTRA_LIFE
        bne @command
        jmp continue_extra_life         ; the 1-up: no command acts
@command:
        lda snd_square2_queue
        beq @continue
        jsr effect_of_command
        stx square2_effect
        lda snd_square2_queue
        and #SQUARE2_EXTRA_LIFE
        beq @start
        lda #SQUARE2_EFFECT_EXTRA_LIFE  ; the playing state keeps the 1-up bit
        sta square2_effect
@start:
        jmp (square2_starts-EFFECT_STEP,x)
@continue:
        ldx square2_effect
        beq @none
        jmp (square2_continues-EFFECT_STEP,x)
@none:
        rts

; The routines of each effect, by its square 2 index.
square2_starts:
        .addr start_bowser_fall, start_coin, start_grow_powerup, start_grow_vine
        .addr start_blast, start_tick, start_grab, start_extra_life
square2_continues:
        .addr continue_bowser_fall, continue_coin, continue_grow, continue_grow
        .addr continue_blast
        .addr square2_count_down        ; the tick: the coin's second tone never comes
        .addr continue_grab, continue_extra_life

; ---------------------------------------------------------------------------
; square2_count_down: one frame of the square 2 effect less; at 0 the effect
; ends. end_square2_effect: none plays, and square 2 is cut. cut_square2:
; only the cut, which the death command makes without ending the effect.
;
; In:       A8 I8; square2_effect_frames
; Out:      square2_effect_frames; at the end square2_effect = NO_EFFECT
; Changes:  A, X, the flags
; Keeps:    Y
; Time:     17 cycles; 198 at the end
; Original: $F568-$F57B
; ---------------------------------------------------------------------------
square2_count_down:
.a8
.i8
        dec square2_effect_frames
        beq end_square2_effect
        rts
end_square2_effect:
.a8
.i8
        stz square2_effect
cut_square2:                            ; end_square2_effect falls into it: the cut
.a8
.i8
        lda #CHANNEL_SQUARE2
        jmp cut_channel

; ---------------------------------------------------------------------------
; start_coin, start_tick: one note with its control. continue_coin: the
; coin's second tone at frame 6, a period store with no length load.
;
; In:       A8 I8; square2_effect_frames (continue_coin)
; Out:      the calls on square 2; square2_effect_frames
; Changes:  A, X, Y, the flags
; Time:     202-231 cycles at the start; 32-210 a frame after
; Original: $F518-$F539
; ---------------------------------------------------------------------------
start_coin:
.a8
.i8
        lda #COIN_FRAMES
        ldy #COIN_CONTROL
        bra coin_tone
start_tick:
.a8
.i8
        lda #TICK_FRAMES
        ldy #TICK_CONTROL
coin_tone:
        sta square2_effect_frames
        tya
        apu_control APU_SQUARE2
        lda #SWEEP_OFF
        apu_sweep APU_SQUARE2
        rep #P_M8
.a16
        lda note_periods+COIN_NOTE
        jsr square2_note
.a8
        jmp square2_count_down
continue_coin:
.a8
.i8
        lda square2_effect_frames
        cmp #COIN_FRAMES + 1 - COIN_SECOND_FRAME
        bne @count
        rep #P_M8
.a16
        lda #COIN_SECOND_PERIOD
        apu_period APU_SQUARE2
@count:
.a8
        jmp square2_count_down

; ---------------------------------------------------------------------------
; start_grow_powerup, start_grow_vine: the length (16 or 32 steps of two
; frames), the sweep off once, and grow_frame from 0. continue_grow (also
; its frame 1): the next frame; at the step that equals the length the effect
; ends, else the control and the step's note (a rest stores no period: the
; note before goes on).
;
; In:       A8 I8; grow_frame, square2_effect_frames (the length)
; Out:      the calls on square 2; grow_frame
; Changes:  A, X, the flags
; Keeps:    Y
; Time:     215-241 cycles at the start; 61-208 a frame after
; Original: $F5FC-$F62A
; ---------------------------------------------------------------------------
start_grow_powerup:
.a8
.i8
        lda #GROW_POWERUP_STEPS
        bra start_grow
start_grow_vine:
.a8
.i8
        lda #GROW_VINE_STEPS
start_grow:
        sta square2_effect_frames
        stz grow_frame
        lda #SWEEP_OFF
        apu_sweep APU_SQUARE2
continue_grow:
.a8
.i8
        inc grow_frame
        lda grow_frame
        lsr a                           ; the step: 0 at frame 1, then one for each two frames
        cmp square2_effect_frames
        beq end_square2_effect
        lda #GROW_CONTROL
        apu_control APU_SQUARE2
        lda grow_frame
        and #GROW_STEP_OFFSET
        tax
        rep #P_M8
.a16
        lda grow_periods,x
        beq @rest
        jmp square2_note                ; the note of the step
@rest:
        sep #P_M8
.a8
        rts

; ---------------------------------------------------------------------------
; start_blast, start_bowser_fall: the first tone. continue_blast,
; continue_bowser_fall: the second tone at frame 9 or 49. blast_tone: a tone
; of either, with their shared control.
;
; In:       A8 I8; square2_effect_frames; blast_tone: A16 = the period, Y8 =
;           the sweep
; Out:      the calls on square 2; square2_effect_frames
; Changes:  A, X, Y, the flags
; Time:     205-231 cycles at the start; 31-234 a frame after
; Original: $F53A-$F551, $F5C8-$F5E1
; ---------------------------------------------------------------------------
start_blast:
.a8
.i8
        lda #BLAST_FRAMES
        sta square2_effect_frames
        ldy #BLAST_SWEEP
        rep #P_M8
.a16
        lda note_periods+BLAST_NOTE
        bra blast_tone
continue_blast:
.a8
.i8
        lda square2_effect_frames
        cmp #BLAST_FRAMES + 1 - BLAST_SECOND_FRAME
        beq @second
        jmp square2_count_down
@second:
        ldy #BLAST_SECOND_SWEEP
        rep #P_M8
.a16
        lda note_periods+BLAST_SECOND_NOTE
        bra blast_tone
start_bowser_fall:
.a8
.i8
        lda #BOWSER_FALL_FRAMES
        sta square2_effect_frames
        ldy #BOWSER_FALL_SWEEP
        rep #P_M8
.a16
        lda note_periods+BOWSER_FALL_NOTE
        bra blast_tone
continue_bowser_fall:
.a8
.i8
        lda square2_effect_frames
        cmp #BOWSER_FALL_FRAMES + 1 - BOWSER_FALL_SECOND_FRAME
        beq @second
        jmp square2_count_down
@second:
        ldy #BOWSER_FALL_SECOND_SWEEP
        rep #P_M8
.a16
        lda note_periods+BOWSER_FALL_SECOND_NOTE
blast_tone:
.a16
        jsr square2_note                ; keeps Y, the sweep
.a8
        lda #BLAST_CONTROL
        apu_control APU_SQUARE2
        tya
        apu_sweep APU_SQUARE2
        jmp square2_count_down

; ---------------------------------------------------------------------------
; start_grab: the power-up grab's 54 frames. continue_grab (also its frame
; 1): on each even count c the note powerup_grab_periods[c/2 - 1] (the word
; at c - 2: entries 26 down to 0), with its control and the
; sweep off.
;
; In:       A8 I8; square2_effect_frames
; Out:      the calls on square 2; square2_effect_frames
; Changes:  A, X, the flags
; Keeps:    Y
; Time:     212-238 cycles at the start; 32-216 a frame after
; Original: $F552-$F567
; ---------------------------------------------------------------------------
start_grab:
.a8
.i8
        lda #GRAB_FRAMES
        sta square2_effect_frames
continue_grab:
.a8
.i8
        lda square2_effect_frames
        lsr a
        bcs @count                      ; an odd count: no note
        ldx square2_effect_frames
        rep #P_M8
.a16
        lda powerup_grab_periods-PERIOD_SIZE,x
        jsr square2_note
.a8
        lda #GRAB_CONTROL
        apu_control APU_SQUARE2
        lda #SWEEP_OFF
        apu_sweep APU_SQUARE2
@count:
        jmp square2_count_down

; ---------------------------------------------------------------------------
; start_extra_life: the 1-up's 48 frames. continue_extra_life (also its
; frame 1, and every frame while the 1-up holds square 2): when the count c
; is a multiple of 8, the note extra_life_periods[c/8 - 1] (the word at
; c/4 - 2), its control and the sweep off. With another effect's count c is at most 55, so the entry is at most 5.
;
; In:       A8 I8; square2_effect_frames
; Out:      the calls on square 2; square2_effect_frames
; Changes:  A, X, the flags
; Keeps:    Y
; Time:     214-240 cycles at the start; 29-231 a frame after
; Original: $F5E2-$F5FB
; ---------------------------------------------------------------------------
start_extra_life:
.a8
.i8
        lda #EXTRA_LIFE_FRAMES
        sta square2_effect_frames
continue_extra_life:
.a8
.i8
        lda square2_effect_frames
        bit #EXTRA_LIFE_TONE
        bne @count
        lsr a
        lsr a                           ; c/4 = (c/8) x PERIOD_SIZE
        tax
        rep #P_M8
.a16
        lda extra_life_periods-PERIOD_SIZE,x
        jsr square2_note
.a8
        lda #EXTRA_LIFE_CONTROL
        apu_control APU_SQUARE2
        lda #SWEEP_OFF
        apu_sweep APU_SQUARE2
@count:
        jmp square2_count_down

; ===========================================================================
; The noise: the brick shatter and Bowser's flame. The drums of the
; music share the channel with no lock: a beat replaces the stores of its
; frame.
; ===========================================================================

; ---------------------------------------------------------------------------
; noise_effects: the effect of the command when it has bit 0 (the brick) or
; bit 1 (the flame), else one frame of the effect that plays. The brick's
; frame 1 plays nothing; the flame's frame 1 plays its first burst.
;
; In:       A8 I8; snd_noise_queue, noise_effect
; Out:      noise_effect, noise_effect_frames; the effect's calls
; Changes:  A, X, the flags
; Keeps:    Y
; Time:     26 cycles with no effect; 179 at most with the effect's frame
; Original: $F667-$F67F, play_brick_shatter $F63B, play_bowser_flame $F680
; ---------------------------------------------------------------------------
noise_effects:
.a8
.i8
        lda snd_noise_queue
        beq @continue
        lsr a
        bcs @brick
        lsr a
        bcs @flame
        stz noise_effect                ; no noise effect bit: nothing plays
        rts
@brick:
        lda #NOISE_EFFECT_BRICK
        sta noise_effect
        lda #BRICK_FRAMES
        sta noise_effect_frames
        bra noise_count_down            ; frame 1: an even count, no burst
@flame:
        lda #NOISE_EFFECT_FLAME
        sta noise_effect
        lda #FLAME_FRAMES
        sta noise_effect_frames
        bra continue_bowser_flame
@continue:
        ldx noise_effect
        beq @none
        jmp (noise_continues-EFFECT_STEP,x)
@none:
        rts

; The routines of each effect, by its noise index.
noise_continues:
        .addr continue_brick_shatter, continue_bowser_flame

; ---------------------------------------------------------------------------
; noise_count_down: one frame of the noise effect less; at 0 the end
; control (the length holds, volume 0) and no effect; no cut.
;
; In:       A8 I8; noise_effect_frames
; Out:      noise_effect_frames; at the end noise_effect = NO_EFFECT
; Changes:  A, the flags
; Keeps:    X, Y
; Time:     18 cycles; 37 at the end
; Original: $F658-$F666
; ---------------------------------------------------------------------------
noise_count_down:
.a8
.i8
        dec noise_effect_frames
        bne @going
        lda #NOISE_END_CONTROL
        apu_control APU_NOISE
        stz noise_effect
@going:
        rts

; ---------------------------------------------------------------------------
; continue_brick_shatter: on each odd count, the burst i = count / 2 (15 down
; to 0): its control and period from the build's tables, and a one-frame
; length. The last burst's control (i = 0) is replaced in its frame by the
; end control: it is not stored.
;
; In:       A8 I8; noise_effect_frames
; Out:      the calls on the noise; noise_effect_frames
; Changes:  A, X, the flags
; Keeps:    Y
; Time:     30-157 cycles
; Original: $F640-$F657
; ---------------------------------------------------------------------------
continue_brick_shatter:
.a8
.i8
        lda noise_effect_frames
        lsr a
        bcc noise_count_down            ; an even count: no burst
        tax                             ; X = the burst
        lda brick_noise_periods,x
        apu_noise_period
        txa
        beq @length                     ; the last burst: its control is the end's
        lda brick_noise_volumes,x
        apu_control APU_NOISE
@length:
        lda #NOISE_BURST_LENGTH
        apu_length APU_NOISE
        bra noise_count_down

; ---------------------------------------------------------------------------
; continue_bowser_flame (also its frame 1): each frame, with i = count / 2
; (32 down to 0), the control bowser_flame_volumes[i - 1], the flame's period
; and a one-frame length: a sound with no break. In the last frame (i = 0)
; the original reads the byte before its table, and the end control replaces
; it in the same frame: only the end control is stored.
;
; In:       A8 I8; noise_effect_frames
; Out:      the calls on the noise; noise_effect_frames
; Changes:  A, X, the flags
; Keeps:    Y
; Time:     132-149 cycles
; Original: $F685-$F690
; ---------------------------------------------------------------------------
; The flame's last frame reads the byte before its table: its end
; control replaces it in the same frame, so continue_bowser_flame
; stores only the end control there.

continue_bowser_flame:
.a8
.i8
        lda #FLAME_PERIOD
        apu_noise_period
        lda noise_effect_frames
        lsr a
        beq @length                     ; the last frame: its control is the end's
        tax
        lda bowser_flame_volumes-1,x    ; i = 32 ... 1 reads the entries 31 ... 0
        apu_control APU_NOISE
@length:
        lda #NOISE_BURST_LENGTH
        apu_length APU_NOISE
        bra noise_count_down

; ===========================================================================
; The music.
; ===========================================================================

; ---------------------------------------------------------------------------
; music_step: an event command loads its song, else an area command loads
; its song, else one frame of the song that plays. An event command
; wins over an area command of the same frame.
;
; In:       A8 I8; snd_event_queue, snd_area_queue, snd_event_music,
;           snd_area_music
; Out:      the song state; its calls
; Changes:  A, X, Y, the flags
; Time:     37 cycles with no song; 1438 at most with a song's start
; Original: $F694-$F6A3
; ---------------------------------------------------------------------------
;   The song (snd_event_music, snd_area_music):
;   | state      | event, area | moves to                                                  |
;   |------------|-------------|-----------------------------------------------------------|
;   | no song    | 0, 0        | an event command: that event song; an area command: that  |
;   |            |             |   area song                                               |
;   | area song  | 0, a        | an event command: that event song (a saved); an area      |
;   |            |             |   command: that area song; its end: the same song again,  |
;   |            |             |   the ground song's next part; the pipe intro and silence:|
;   |            |             |   no song                                                 |
;   | event song | e, 0        | a command: that song; its end: the time-out with a saved  |
;   |            |             |   area song: that area song; the victory: again; else no  |
;   |            |             |   song                                                    |
;

; Two more effects of the original's state, kept the same way:
;   - A square's volume step is an index into the table of the song that
;     plays. A step that an effect kept through a song change indexes the
;     next song's table and can read past it into the next table (the build's
;     music_volumes, read with volume_base + the step).
;   - The fast tempo after the time-out song: song_tempo is set by
;     each event song and kept by the area songs.
; The game writes one bit at a time into the song commands, and the
; build gives each song the rules of its bit. A noise command has only bits
; 0 and 1; another bit starts no effect.
;

music_step:
.a8
.i8
        lda snd_event_queue
        beq @area
        jmp load_event_song
@area:
        lda snd_area_queue
        beq @playing
        jmp load_area_song
@playing:
        lda snd_event_music
        ora snd_area_music
        beq @none
        jmp song_frame
@none:
        rts

; ---------------------------------------------------------------------------
; load_event_song: an event song. The death song ends square 1's
; effect and cuts square 2 without ending its effect. The area
; song that plays is saved for the time-out song and stops. The time-out
; song alone plays at the fast tempo, which the area songs then keep until
; the next event song.
;
; In:       A8 = the event command, not 0; I8
; Out:      snd_event_music, snd_area_saved, snd_area_music = 0, song_tempo;
;           then load_song
; Changes:  A, X, Y, the flags
; Time:     529-1291 cycles with load_song and the song's first frame
; Original: $F6A4-$F6C7
; ---------------------------------------------------------------------------
; The death command and square 2: load_event_song cuts square 2 without
; ending its effect (cut_square2).

load_event_song:
.a8
.i8
        sta snd_event_music
        cmp #EVENT_DEATH
        bne @saved
        jsr stop_square1_effect
        jsr cut_square2
@saved:
        lda snd_area_music
        sta snd_area_saved
        stz snd_area_music
        lda snd_event_music
        cmp #EVENT_TIME_RUNNING_OUT
        beq @time_out
        .assert TEMPO_NORMAL = 0, error, "load_event_song: STZ"
        stz song_tempo
        jsr song_bit                    ; X = its record in event_songs
        bra @record
@time_out:
        lda #TEMPO_FAST
        sta song_tempo
        ldx #TIME_OUT_FAST_RECORD
@record:
        rep #P_M8
.a16
        lda f:event_songs,x
        jmp load_song

; ---------------------------------------------------------------------------
; load_area_song: an area song command: the underground song ends
; square 1's effect; the ground song starts again from its lead-in.
; restart_area_song: the area song plays from its start (also at a song's
; end): the ground song plays its next part (after the last part,
; part 1); the song's record at the tempo that plays.
;
; In:       A8 = the area command (one SONG_* bit); I8; ground_part, song_tempo
; Out:      snd_event_music = 0, snd_area_music, ground_part; then load_song
; Changes:  A, X, Y, the flags
; Time:     527-1419 cycles with load_song and the song's first frame
; Original: $F6C8-$F6F4
; ---------------------------------------------------------------------------
; The dead store of the area song path ($F6EF): not made.

load_area_song:
.a8
.i8
        cmp #SONG_UNDERGROUND
        bne @part
        jsr stop_square1_effect
        lda snd_area_queue              ; the command again
@part:
        ldx #GROUND_PART_NONE
        stx ground_part
; Corresponding original code: $F6D4.

restart_area_song:
.a8
.i8
        stz snd_event_music
        sta snd_area_music
        cmp #SONG_GROUND
        bne @area
; The ground song's next part. The original counts $11-$31 and at $32 goes
; back to $11 and steps again: the part after the last is part 1 (song 18).
        ldx ground_part
        inx
        cpx #<GROUND_PARTS
        bne @part_record
        ldx #GROUND_PART_LOOP
@part_record:
        stx ground_part
        txa
        asl a
        asl a                           ; x 4: the part's pair of records
        ora song_tempo
        tax
        rep #P_M8
.a16
        lda f:ground_parts,x
        jmp load_song
@area:
.a8
        jsr song_bit
        txa
        asl a                           ; x 4: the bit's pair of records
        ora song_tempo
        tax
        rep #P_M8
.a16
        lda f:area_songs,x
        jmp load_song
.assert SONG_PAIR_SHIFT = 2, error, "restart_area_song: two ASLs"
.assert GROUND_PARTS_SIZE <= $100, lderror, "restart_area_song: an 8-bit index"

; ---------------------------------------------------------------------------
; song_bit: the song of a song command: its lowest set bit picks it.
;
; In:       A8 = the command, not 0; I8
; Out:      X = SONG_RECORD x the bit's number
; Changes:  A, the flags
; Keeps:    Y
; Time:     19-96 cycles
; Original: $F6F1-$F6F4
; ---------------------------------------------------------------------------
; Corresponding original code: $F6ED.

song_bit:
.a8
.i8
        ldx #0
@bit:
        lsr a
        bcs @found
        inx
        inx
        bra @bit                        ; A is not 0: a bit comes
@found:
        rts
.assert SONG_RECORD = 2, error, "song_bit: two INXs"

; ---------------------------------------------------------------------------
; load_song: start a song from its record: each part at its start, every
; count at 1, no death sweep, the song's volume table, and the triangle cut;
; then the song's first frame runs at once (song_frame, which follows), in
; which every part reads its first note.
;
; In:       A16 = the offset of the song's SongRecord in song_lists; I8
; Out:      the parts' positions and counts, drum_loop, square1_sweep, the
;           song's volume table; then song_frame
; Changes:  A, X, Y, the flags
; Time:     385-1297 cycles with the song's first frame
; Original: $F6F5-$F739
; ---------------------------------------------------------------------------
load_song:
.a16
.i8
        rep #P_X8
.i16
        tax
        lda f:song_lists+SongRecord::square2,x
        sta square2_position
        lda f:song_lists+SongRecord::square1,x
        sta square1_position
        lda f:song_lists+SongRecord::triangle,x
        sta triangle_position
        lda f:song_lists+SongRecord::drums,x
        sta drum_position
        sta drum_loop
        sep #P_M8
.a8
        lda f:song_lists+SongRecord::volume_base,x
        sta song_volume_base
        lda f:song_lists+SongRecord::volume_start,x
        sta song_volume_start
        lda f:song_lists+SongRecord::volume_steps,x
        sta song_volume_steps
        sep #P_X8
.i8
        lda #START_COUNT
        sta square2_count
        sta square1_count
        sta triangle_count
        sta drum_count
        stz square1_sweep
        lda #CHANNEL_TRIANGLE
        jsr cut_channel
; Falls into song_frame: the first frame of the song.

; ---------------------------------------------------------------------------
; song_frame: one frame of the song that plays: square 2, square 1, the
; triangle, the drums, in that order. When square 2's part ends,
; song_end takes the frame: the other parts do not step, and a song that
; starts again plays its first frame at once.
;
; Each square: its count goes down; at 0 the next note of its part. While
; the square's effect plays, the music's data and counts go on, and the note,
; the control, the sweep and the volume step wait. A note stores
; its period and length; with volume steps, each frame's control is the
; step's entry of the song's table, else a note's control is MUSIC_CONTROL
; and a rest's the rest control of its square. Square 2's
; sweep is SWEEP_OFF with each control; square 1 stores its song's sweep
; every frame.
;
; In:       A8 I8; the song state
; Out:      the parts' positions and counts, the volume steps; the calls
; Changes:  A, X, Y, the flags
; Time:     64 cycles at least; 1217 at most with a song end that starts a song
; Original: $F73A-$F8C4
; ---------------------------------------------------------------------------
; The first frame of each note reads past its volume table: the build's
; music_volumes keeps the three tables in the original's order with the
; byte after the water table, and a note's step starts at its table's
; size (song_frame, the square 2 and square 1 notes).
; The death song rests: SQUARE2_REST_CONTROL, SQUARE2_REST_SWEEP and
; SQUARE1_REST_CONTROL, stored at a rest of the songs with no volume
; steps (song_frame).

; Corresponding original code: $F7BC, $F81A, $F86D and $F8F4.

song_frame:
.a8
.i8
        dec square2_count
        bne square2_volume_step
; Square 2's next note.
        rep #P_X8
.i16
        ldx square2_position
        lda f:song_lists+SquareNote::frames,x
        bne @square2_note
        sep #P_X8
.i8
        jmp song_end                    ; the 0 byte: the song ends
@square2_note:
.i16
        sta square2_count
        rep #P_M8
.a16
        lda f:song_lists+SquareNote::period,x
        tay                             ; Y = the period
        txa
        clc
        adc #.sizeof(SquareNote)
        sta square2_position
        tya                             ; A = the period
        sep #P_X8                       ; (A keeps its 16 bits)
.i8
        ldx square2_effect
        bne @square2_waits              ; an effect plays: the music waits
        cmp #REST
        beq @square2_rest
        jsr square2_note
.a8
        lda song_volume_start           ; the first step: past its table
        sta square2_volume
        lda song_volume_steps
        bne square2_volume_body         ; the step gives this frame's control
        lda #MUSIC_CONTROL
        apu_control APU_SQUARE2
        lda #SWEEP_OFF
        apu_sweep APU_SQUARE2
        bra square1_music
@square2_rest:
.a16
        sep #P_M8
.a8
        stz square2_volume
        lda song_volume_steps
        bne square2_volume_body
        lda #SQUARE2_REST_CONTROL       ; the death song's rest
        apu_control APU_SQUARE2
        lda #SQUARE2_REST_SWEEP
        apu_sweep APU_SQUARE2
        bra square1_music
@square2_waits:
.a16
        sep #P_M8
.a8
        bra square1_music
; Square 2's volume step: this frame's control, then the step goes down.
square2_volume_step:
.a8
.i8
        lda square2_effect
        bne square1_music
        lda song_volume_steps
        beq square1_music
square2_volume_body:
        lda square2_volume
        tay                             ; Y = the step of this frame
        clc
        adc song_volume_base
        tax
        lda music_volumes,x
        apu_control APU_SQUARE2
        tya
        beq @held                       ; step 0 stays
        dec square2_volume
@held:
        lda #SWEEP_OFF
        apu_sweep APU_SQUARE2

; Square 1, when the song has a square 1 part.
square1_music:
.a8
.i8
        rep #P_M8
.a16
        lda square1_position
        sep #P_M8                       ; (the Z flag stays)
.a8
        bne @square1_part
        jmp triangle_music              ; the song has no square 1 part
@square1_part:
        dec square1_count
        bne square1_volume_step
        rep #P_X8
.i16
        ldx square1_position
@square1_read:
        lda f:song_lists+SquareNote::frames,x
        bne @square1_note
; The original's 0 byte: the death sound setting. Its control and
; sweep stores are replaced in the same frame by the note's and the sweep
; below; only its sweep for the song stays. It is the first
; byte of the death song's part, read in the frame in which the death
; command has just ended square 1's effect.
        lda #DEATH_SWEEP
        sta square1_sweep
        inx                             ; the marker is one byte
        bra @square1_read
@square1_note:
        sta square1_count
        rep #P_M8
.a16
        lda f:song_lists+SquareNote::period,x
        tay                             ; Y = the period
        txa
        clc
        adc #.sizeof(SquareNote)
        sta square1_position
        tya                             ; A = the period
        sep #P_X8                       ; (A keeps its 16 bits)
.i8
        ldx square1_effect
        bne @square1_waits
        cmp #REST
        beq @square1_rest
        jsr square1_note
.a8
        lda song_volume_start
        sta square1_volume
        lda song_volume_steps
        bne square1_volume_body
        lda #MUSIC_CONTROL
        apu_control APU_SQUARE1
        bra square1_sweep_store
@square1_rest:
.a16
        sep #P_M8
.a8
        stz square1_volume
        lda song_volume_steps
        bne square1_volume_body
        lda #SQUARE1_REST_CONTROL       ; the death song's rest
        apu_control APU_SQUARE1
        bra square1_sweep_store
@square1_waits:
.a16
        sep #P_M8
.a8
        bra triangle_music
; Square 1's volume step, then its sweep: each frame.
square1_volume_step:
.a8
.i8
        lda square1_effect
        bne triangle_music
        lda song_volume_steps
        beq square1_sweep_store
square1_volume_body:
        lda square1_volume
        tay                             ; Y = the step of this frame
        clc
        adc song_volume_base
        tax
        lda music_volumes,x
        apu_control APU_SQUARE1
        tya
        beq square1_sweep_store         ; step 0 stays
        dec square1_volume
square1_sweep_store:
        lda square1_sweep
        bne @sweep
        lda #SWEEP_OFF                  ; no song sweep
@sweep:
        apu_sweep APU_SQUARE1

; The triangle: its count goes down (it has no effect); at 0 its next note:
; the control that the note's stores leave (the build applies the hold rule), then the note store unless it is a rest.
triangle_music:
.a8
.i8
        dec triangle_count
        bne drum_music
        rep #P_X8
.i16
        ldx triangle_position
        lda f:song_lists+TriangleNote::frames,x
        sta triangle_count
        lda f:song_lists+TriangleNote::control,x
        apu_control APU_TRIANGLE
        rep #P_M8
.a16
        lda f:song_lists+TriangleNote::period,x
        tay                             ; Y = the period
        txa
        clc
        adc #.sizeof(TriangleNote)
        sta triangle_position
        tya                             ; A = the period
        sep #P_X8                       ; (A keeps its 16 bits)
.i8
        cmp #REST
        beq @triangle_rest
        jsr triangle_note
.a8
        bra drum_music
@triangle_rest:
.a16
        sep #P_M8
.a8

; The drums, when the song plays them: at the end of a beat the next beat's
; stores; the loop's 0 byte sends the reader to its start.
; The silent drum bytes: the build's drum lists hold the stores of each
; silent beat (scripts/song_data.py Song.drums); drum_music stores them.

drum_music:
.a8
.i8
        rep #P_M8
.a16
        lda drum_position
        sep #P_M8                       ; (the Z flag stays)
.a8
        beq @done
        dec drum_count
        bne @done
        rep #P_X8
.i16
        ldx drum_position
@read:
        lda f:song_lists+DrumBeat::frames,x
        bne @beat
        ldx drum_loop                   ; the loop starts again
        bra @read
@beat:
        sta drum_count
        lda f:song_lists+DrumBeat::control,x
        apu_control APU_NOISE
        lda f:song_lists+DrumBeat::period,x
        apu_noise_period
        lda f:song_lists+DrumBeat::length,x
        pha                             ; the length index, after the position
        rep #P_M8
.a16
        txa
        clc
        adc #.sizeof(DrumBeat)
        sta drum_position
        sep #P_M8 | P_X8
.a8
.i8
        pla
        apu_length APU_NOISE
@done:
        rts

; ---------------------------------------------------------------------------
; song_end: square 2's part ended. After the time-out song the
; saved area song plays from its start (the ground song from its next part);
; the victory song plays again; an area song that loops plays again; any
; other song stops: no song, both squares silent and the triangle's linear
; counter to 0. These stores reach a square on which an effect plays, which
; stays silent until the effect's next control; the noise
; gets none.
;
; In:       A8 I8; snd_event_music, snd_area_saved, snd_area_music
; Out:      the next song (restart_area_song, load_event_song), or no song
; Changes:  A, X, Y, the flags
; Time:     65 cycles to stop; 1188 at most with the next song's start
; Original: $F74B-$F779
; ---------------------------------------------------------------------------
; The song end's control stores reach an effect's square: song_end.

song_end:
.a8
.i8
        lda snd_event_music
        cmp #EVENT_TIME_RUNNING_OUT
        bne @victory
        lda snd_area_saved
        beq @victory                    ; no saved song (A = 0: not the victory)
        jmp restart_area_song
@victory:
        and #EVENT_VICTORY
        beq @area
        jmp load_event_song             ; A = EVENT_VICTORY
@area:
        lda snd_area_music
        and #LOOPING_AREA_SONGS
        beq @stop
        jmp restart_area_song
@stop:
        stz snd_area_music
        stz snd_event_music
        lda #SONG_END_TRIANGLE
        apu_control APU_TRIANGLE
        lda #SONG_END_CONTROL
        apu_control APU_SQUARE1
        apu_control APU_SQUARE2
        rts
