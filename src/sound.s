; The NES sound unit model: the state of the NES sound unit, kept from the
; calls of a ported NES sound program (src/sound.inc: one call for each store
; of the original to its sound unit), and played on four DOC voices at each
; tick of the clock (src/clock.s: 4 in each picture of the mode, about 240 Hz,
; the rate of the NES's own envelope clock). Nothing here is particular to
; one game.
;
; The model follows the NES sound unit: the frame sequencer with its quarter
; and half frame clocks, the envelopes, the length counters, the sweeps, the
; triangle's linear counter, the enable bits, and the mixer's levels (also
; the sample channel's level, which makes the triangle and the noise
; quieter). The DOC plays each channel from the wave tables of
; scripts/sound_bank.py with the volume registers of that file: everything
; that the game does not change while it runs is in those tables.
;
; The calls keep the latches (apu_regs) in the order of the NES's registers,
; so each channel's four latches are at its channel offset. A call that
; changes a latch only marks its channel (apu_settled); a call whose store is
; an event runs its routine below at once, in the order of the program's
; calls. The sound program runs with the interrupts off (src/game/
; sound_program.s), so no tick falls between the calls of one frame, as no
; clock of the NES falls between the stores of its sound program.
;
; A tick only steps the counters and recomputes a channel that changed (a
; call of the program, a counter that changed its sound); a DOC register is
; written only when its value changes.
;
; Not modeled: the sample channel's playback (only its level), the noise's
; short sequence (NOISE_SHORT: the 93-step sequence; the long one plays), the
; square's phase reset at a length load, and the cross levels of the mixer
; (two channels that play together are a little quieter on the NES than
; each alone). A NES game that needs one of them adds it here.
;
; Routines:
;   sound_start        the DOC voices, the waves and the noise (JSL, startup)
;   sound_set_mix      the music and effects levels of the options menu (JSL)
;   sound_tick         one tick of the sound unit, played on the DOC (JSL, clock_irq)
;   apu_sweep_x        the call apu_sweep: a square's sweep (src/sound.inc)
;   apu_period_x       the call apu_period: a square's or the triangle's period
;   apu_length_x       the call apu_length: a length load
;   apu_enable_bits    the call apu_enable: the channel enable bits
;   apu_sequence_start the call apu_sequence: the frame sequencer's mode and start
;   apu_set_effects    the channels that play an effect (src/game/sound_program.s)
;   sound_hold         the options menu: the voices silent, the sound unit stopped (JSL)
;   sound_release      after the menu: the sound unit goes on where it stopped (JSL)

TICK_CYCLES = 7445              ; NES CPU cycles in one tick: 29,780.5 / 4
PULSE_RESOLUTION = 0            ; the DOC resolution of the squares' tables
TRIANGLE_RESOLUTION = 1         ; of the triangle's (its pitch is half a square's)
NOISE_RESOLUTION = 7            ; of the noise (one pass is the whole accumulator)
; The DOC frequency of period P for the squares and the triangle: one table
; pass of 2^(17+R) accumulator units is one wave cycle. A square plays
; 1,789,773 / (16 x (P + 1)) Hz, and the NES CPU clock is twice the DOC's
; 894,886 Hz, which scans DOC_VOICES + 2 slots; so FC = (DOC_VOICES + 2) x
; 2^(14+R) / (P + 1). The triangle (32 steps, R + 1) has the same FC. The
; resolutions are the lowest that keep FC exact enough at the lowest
; periods; a higher one would take period 7 over 16 bits.
FC_SCALE = (DOC_VOICES + 2) << (14 + PULSE_RESOLUTION)
.assert FC_SCALE = (DOC_VOICES + 2) << (13 + TRIANGLE_RESOLUTION), error, "one frequency table for both"
.assert FC_SCALE / 8 < $10000, error, "period 7 in the 16-bit frequency"
; The noise steps 1,789,773 / period times a second. The long table holds
; 32768 steps, one pass of the accumulator: FC = (DOC_VOICES + 2) x 2^10 /
; period. Slow noise plays its first 4096 steps (size code 4): FC =
; (DOC_VOICES + 2) x 2^13 / period, eight times as exact; that loop lasts
; more than a second at those rates.
NOISE_STEPS = 32768
NOISE_SIZE_LONG = 7
NOISE_SIZE_SLOW = 4
NOISE_FC_LONG = (DOC_VOICES + 2) << 10
NOISE_FC_SLOW = (DOC_VOICES + 2) << 13
NOISE_SLOW_FIRST = 11           ; the first period number (508 cycles) of the slow table
NOISE_HIGH = 128 + 127          ; the noise's two samples (scripts/sound_bank.py: a jump of 254)
NOISE_LOW = 128 - 127

; The forms of the values are in src/sound.inc (CONTROL_*, SWEEP_*, ...).
PERIOD_AUDIBLE = 8              ; a square under this period is silent
PERIOD_MAX = $7FF               ; a sweep target over this is silent

; The frame sequencer's events: the CPU cycle after its reset, and the
; clocks (SEQUENCE_*). The last event of a mode starts it again.
SEQUENCE_QUARTER = 1            ; the envelopes and the triangle's linear counter
SEQUENCE_HALF = 2               ; the length counters and the sweeps
SEQUENCE_LAST = $80
SEQUENCE_FIVE = 0               ; the offsets of the two modes in sequence_cycles
SEQUENCE_FOUR = 8

.segment "SOUNDPAGE"
; The latches of the calls (src/sound.inc APU_*), in the NES's register order:
; each channel's control, sweep and period (a word) at its offset, then the
; sample level, the enable bits and the sequencer's mode.
apu_regs: .res APU_REGISTERS
apu_effects: .res 1             ; bit (VOICE_*): the channel plays an effect
apu_held: .res 1                ; not 0: the options menu holds the sound unit (no ticks)
; The state of each channel, at the channel's offset (APU_SQUARE1 ... APU_NOISE).
; apu_settled: 0: the channel's DOC voice is computed again at the next tick.
apu_settled: .res 16
apu_length_counter: .res 16     ; the length counter: 0 is silent
apu_envelope_start: .res 16     ; 1: the envelope starts again at the next quarter frame
apu_envelope_divider: .res 16
apu_envelope_decay: .res 16     ; the envelope's volume, 15 down to 0
apu_sweep_divider: .res 8       ; the squares only
apu_sweep_reload: .res 8
apu_linear: .res 1              ; the triangle's linear counter
apu_linear_reload: .res 1
apu_sequence_position: .res 2   ; NES CPU cycles since the sequencer's reset
apu_sequence_event: .res 2      ; the next event (an offset in sequence_cycles)
apu_sequence_first: .res 2      ; the first event of the mode
apu_change: .res 2              ; sweep_target: the period's change
apu_target: .res 2              ; sweep_target: the target period
apu_index: .res 2               ; the outputs: an index in a volume table
; What each DOC voice holds, at the channel's offset.
voice_frequency: .res 16        ; a word
voice_volume: .res 16
voice_wave: .res 16
voice_table: .res 16

.segment "SOUNDRAM"
; The volume registers of the two levels of the options menu: row 0 music,
; row 1 effects (sound_set_mix, from scripts/sound_bank.py).
mix_pulse: .res 2 * 16          ; [row][channel level]
mix_triangle: .res 2 * 32       ; [row][sample level / 4]
mix_noise: .res 2 * 512         ; [row][sample level / 4][channel level]
mix_level: .res 2               ; sound_set_mix: the level of the row it copies
noise_shift: .res 2             ; sound_start: the noise's shift register
noise_next: .res 2

.segment "SOUND"
.a8
.i16

; sound_start: the four voices, the waves and the noise in DOC RAM, and the
; sound unit at its power-on state (all channels off, four-step mode). The
; levels stay 0 until sound_set_mix. The noise is made here from the NES's
; shift register: faster than a load from the disk.
; In:       A8 X16, DBR = 0, interrupts off (JSL from the startup, before
;           clock_start); the SOUNDPAGE variables cleared
; Out:      DOC RAM: the waves and the noise; the four voices silent;
;           apu_sequence_first, apu_sequence_event: the four-step mode
; Changes:  A, X, Y, the flags
; Keeps:    D, DBR
; Time:     once, at the start (the DOC RAM writes wait for the GLU)
; Original: none
sound_start:
        php
        sei
; The owner's master volume, kept for every SOUNDCTL write (src/clock.s).
; It comes from the firmware's copy: the volume bits of SOUNDCTL are write
; only and read as 1s (volume 15) on the hardware, in MAME and in GS2.
        lda f:CP_VOLUME
        and #SOUNDCTL_VOLUME
        sta doc_master
@ready:
        lda f:SOUNDCTL
        bmi @ready
        lda doc_master
        ora #SOUNDCTL_RAM|SOUNDCTL_INC
        sta f:SOUNDCTL
; The waves, from the host data of scripts/sound_bank.py.
        lda #<SOUND_WAVES_DOC
        sta f:SOUNDADRL
        lda #>SOUND_WAVES_DOC
        sta f:SOUNDADRH
        ldx #0
@wave:
        lda f:SOUND_WAVES,x
        xba
@wave_busy:
        lda f:SOUNDCTL
        bmi @wave_busy
        xba
        sta f:SOUNDDATA
        inx
        cpx #SOUND_WAVES_SIZE
        bne @wave
; The noise: the NES's 15-bit shift register from 1, one sample a step. The
; channel sounds while bit 0 is 0; then bits 0 and 1 give bit 14 of the next step.
        lda #0
        sta f:SOUNDADRL
        lda #NOISE_PAGE
        sta f:SOUNDADRH
        rep #$20
.a16
        lda #1
        sta noise_shift
        ldx #NOISE_STEPS
@noise:
        lda noise_shift
        lsr a
        sta noise_next
        sep #$20
.a8
        lda #NOISE_HIGH
        bcc @sample
        lda #NOISE_LOW
@sample:
        xba
@noise_busy:
        lda f:SOUNDCTL
        bmi @noise_busy
        xba
        sta f:SOUNDDATA
        rep #$20
.a16
        lda noise_shift
        eor noise_next
        lsr a                           ; carry: bit 0 xor bit 1
        lda noise_next
        bcc @shifted
        ora #$4000
@shifted:
        sta noise_shift
        dex
        bne @noise
        sep #$20
.a8
        lda doc_master
        sta f:SOUNDCTL                  ; register mode
; The voices: silent, running, on a valid table.
        ldx #APU_NOISE
@voice:
        stz voice_volume,x
        lda #0
        jsr write_volume
        stz voice_frequency,x
        stz voice_frequency+1,x
        jsr write_frequency
        lda #PULSE_PAGE_2_0
        sta voice_wave,x
        jsr write_wave
        lda #(PULSE_SIZE_2_0 << 3) | PULSE_RESOLUTION
        sta voice_table,x
        jsr write_table
        lda #0                          ; free run, not halted
        xba
        lda #DOC_CONTROL
        jsr doc_voice_write
        dex
        dex
        dex
        dex
        bpl @voice
        ldx #SEQUENCE_FOUR
        stx apu_sequence_first
        stx apu_sequence_event
        plp
        rtl

; sound_set_mix: the levels of the options menu: the music level for the
; channels that play music, the effects level for those that play an effect
; (apu_effects). Each level is a row of the build's volume tables, copied
; with block moves; the ticks wait for the whole copy.
; In:       A8 X16, A = the music level 0-15, X = the effects level 0-15 (JSL
;           from the input's settings and the options menu)
; Out:      mix_pulse, mix_triangle, mix_noise; every channel's voice again
;           at the next tick
; Changes:  A, X, Y, the flags, mix_level
; Keeps:    D, DBR
; Time:     about 7,900 cycles: 1,120 bytes of block moves at 7 cycles a byte,
;           at a change of a level
; Original: none
.macro mix_row table, shift, destination
        lda mix_level
  .repeat shift
        asl a
  .endrepeat
        clc
        adc #.loword(table)
        tax
        ldy #.loword(destination)
        lda #(1 << shift) - 1
        mvn #^(table), #^(destination)
.endmacro
sound_set_mix:
        php
        sei                             ; the ticks wait for the whole row
        phb
        pha
        lda #0
        pha
        plb                             ; DBR = bank 0
        pla
        rep #$30
.a16
.i16
        phx
        and #$000F
        sta mix_level
        mix_row SOUND_PULSE_VOLUMES, 4, mix_pulse
        mix_row SOUND_TRIANGLE_VOLUMES, 5, mix_triangle
        mix_row SOUND_NOISE_VOLUMES, 9, mix_noise
        pla
        and #$000F
        sta mix_level
        mix_row SOUND_PULSE_VOLUMES, 4, mix_pulse+16
        mix_row SOUND_TRIANGLE_VOLUMES, 5, mix_triangle+32
        mix_row SOUND_NOISE_VOLUMES, 9, mix_noise+512
        sep #$20
.a8
        stz apu_settled+APU_SQUARE1
        stz apu_settled+APU_SQUARE2
        stz apu_settled+APU_TRIANGLE
        stz apu_settled+APU_NOISE
        plb
        plp
        rtl

; sound_hold: the options menu stops the game, so the sound unit stops too,
; as a paused NES would: the ticks skip it, and the four voices go silent
; (a held note would sound for the whole menu).
; sound_release: the ticks run again, and each channel goes back to its
; voice at the next tick, from the state that it had.
; In:       any widths, any DBR (JSL from src/menu.s)
; Out:      apu_held; sound_hold: the four voices' volume 0; sound_release:
;           every channel's voice again at the next tick
; Changes:  nothing
; Keeps:    A, X, Y, D, DBR, the widths
; Time:     at the menu's opening and closing
; Original: none
sound_hold:
        php
        rep #$30
.a16
.i16
        pha
        phx
        phb
        pea 0
        plb
        plb                             ; DBR = bank 0
        sep #$20
.a8
        sei
        lda #1
        sta apu_held
@ready:
        lda f:SOUNDCTL
        bmi @ready
        lda doc_master
        sta f:SOUNDCTL                  ; register mode, the owner's master volume
        ldx #APU_NOISE
@voice:
        lda #0
        jsr set_volume
        dex
        dex
        dex
        dex
        bpl @voice
        rep #$20
.a16
        plb
        plx
        pla
        plp
        rtl
sound_release:
        php
        sep #$20
.a8
        phb
        pha
        lda #0
        pha
        plb                             ; DBR = bank 0
        stz apu_settled+APU_SQUARE1
        stz apu_settled+APU_SQUARE2
        stz apu_settled+APU_TRIANGLE
        stz apu_settled+APU_NOISE
        stz apu_held
        pla
        plb
        plp
        rtl

; ---- The calls of the sound program (src/sound.inc) ----
.a8
.i8

; apu_sweep_x: the call apu_sweep: a square's sweep. The divider reloads at
; the next half clock, also when the value stays.
; In:       A8 = the sweep (SWEEP_*); X = the square (APU_SQUARE1, APU_SQUARE2);
;           X 8 or 16 bits
; Out:      apu_regs + X + APU_SWEEP = A; apu_sweep_reload + X = 1
; Changes:  the flags
; Keeps:    A, X, Y
; Time:     33-42 cycles with the JSR and the RTS
; Original: none (the NES's $4001, $4005)
apu_sweep_x:
.a8
        cmp apu_regs+APU_SWEEP,x
        beq @reload
        sta apu_regs+APU_SWEEP,x
        stz apu_settled,x               ; the silence test of the voice reads the sweep
@reload:
        pha
        lda #1
        sta apu_sweep_reload,x
        pla
        rts

; apu_period_x: the call apu_period: a square's or the triangle's period.
; In:       A16 = the period, 0-$7FF; X = the channel (APU_SQUARE1,
;           APU_SQUARE2, APU_TRIANGLE); X 8 or 16 bits
; Out:      A8 (A's two bytes keep the period); apu_regs + X + APU_PERIOD = the period
; Changes:  the flags
; Keeps:    X, Y
; Time:     23-33 cycles with the JSR and the RTS
; Original: none (the NES's $4002-$4003, $4006-$4007, $400A-$400B)
apu_period_x:
.a16
        cmp apu_regs+APU_PERIOD,x
        beq @same
        sta apu_regs+APU_PERIOD,x
        sep #P_M8
.a8
        stz apu_settled,x
        rts
@same:
.a16
        sep #P_M8
.a8
        rts

; apu_length_x: the call apu_length: a length load. The length counter takes
; the NES length of the index when the channel is on; the envelope starts
; again at 15 at the next quarter clock (the triangle: its linear counter
; reloads at the next quarter clock).
; In:       A8 = the length index, 0-31; X = the channel; X 8 or 16 bits
; Out:      apu_length_counter + X; apu_envelope_start + X or apu_linear_reload = 1
; Changes:  the flags; X's high byte (0)
; Keeps:    A, X (the channel), Y
; Time:     73-77 cycles with the JSR and the RTS
; Original: none (the NES's $4003, $4007, $400B, $400F)
apu_length_x:
.a8
        phy                             ; Y in the caller's width, before the switch
        php
        sep #P_X8                       ; X keeps its low byte, the channel
.i8
        pha
        tay                             ; Y = the length index
        lda apu_regs+APU_STATUS
        and channel_bits,x
        beq @off                        ; a channel that is off takes no length
        lda length_table,y
        sta apu_length_counter,x
@off:
        lda #1
        cpx #APU_TRIANGLE
        beq @linear
        sta apu_envelope_start,x
        bra @mark
@linear:
        sta apu_linear_reload
@mark:
        stz apu_settled,x
        pla
        plp                             ; the caller's index width again
        ply
        rts

; apu_enable_bits: the call apu_enable: the channel enable bits. A channel
; that is off loses its length counter, so it stays silent until a length
; load while it is on. With all channels on no channel loses anything: the
; sound program makes that call in every frame, so it returns at once.
; In:       A8 = the channels that are on (CHANNEL_*); X 8 or 16 bits
; Out:      apu_regs + APU_STATUS = A; apu_length_counter = 0 of each channel that is off
; Changes:  X, the flags
; Keeps:    A, Y
; Time:     20 cycles with the JSR and the RTS with all channels on; else 171
; Original: none (the NES's $4015)
apu_enable_bits:
.a8
        sta apu_regs+APU_STATUS
        cmp #CHANNELS_ALL
        bne @off
        rts                             ; all on: no length is lost
@off:
        phy                             ; Y in the caller's width, before the switch
        php
        sep #P_X8
.i8
        pha
        ldx #APU_NOISE
@channel:
        lda apu_regs+APU_STATUS
        and channel_bits,x
        bne @next
        stz apu_length_counter,x
        stz apu_settled,x
@next:
        txa
        sec
        sbc #4
        tax
        bpl @channel
        pla
        plp                             ; the caller's index width again
        ply
        rts

; apu_sequence_start: the call apu_sequence: the frame sequencer's mode, and
; its start. In five-step mode the start also gives a quarter and a half
; clock at once.
; In:       A8 = the mode (SEQUENCE_FIVE_STEP or 0); X 8 or 16 bits
; Out:      apu_regs + APU_FRAME = A; the sequence at its start
; Changes:  X, the flags
; Keeps:    A, Y
; Time:     368-809 cycles with the JSR, the RTS and the clocks of five-step mode
; Original: none (the NES's $4017)
apu_sequence_start:
.a8
        phy                             ; Y in the caller's width, before the switch
        php
        pha
        sta apu_regs+APU_FRAME
        rep #P_X8
.i16
        ldx #SEQUENCE_FOUR
        bit #SEQUENCE_FIVE_STEP
        beq @mode
        ldx #SEQUENCE_FIVE
@mode:
        stx apu_sequence_first
        stx apu_sequence_event
        ldx #0
        stx apu_sequence_position
        bit #SEQUENCE_FIVE_STEP
        beq @done
        jsr quarter_frame
        jsr half_frame
@done:
        pla
        plp                             ; the caller's index width again
        ply
        rts

; apu_set_effects: the channels that play an effect (bit VOICE_* set, the
; CHANNEL_* bits); they play at the effects level of the options menu, the
; others at the music level. A change marks every channel's voice.
; In:       A8 = the bits; I8
; Out:      apu_effects
; Changes:  the flags
; Keeps:    A, X, Y
; Time:     16-35 cycles with the JSR and the RTS
; Original: none (the port's options menu)
apu_set_effects:
.a8
.i8
        cmp apu_effects
        beq @same
        sta apu_effects
        stz apu_settled+APU_SQUARE1
        stz apu_settled+APU_SQUARE2
        stz apu_settled+APU_TRIANGLE
        stz apu_settled+APU_NOISE
@same:
        rts

; ---- The tick ----
.a8
.i16

; sound_tick: one tick of the sound unit, 4 in each picture of the mode.
; The frame sequencer gives the clocks whose time came, then each changed
; channel goes to its DOC voice.
; In:       A8 X16, D = SOUND_PAGE, DBR = 0 (JSL from clock_irq; the GLU in
;           register mode)
; Out:      the sound unit's counters; the DOC voices of the changed channels
; Changes:  A, X, Y, the flags
; Keeps:    D, DBR
; Time:     89-1,369 cycles (median 341) with the JSL and the RTL, the GLU
;           ready, over 160,000 ticks of random commands
; Original: none (the NES sound unit's frame sequencer and channels)
sound_tick:
.a8
.i16
        lda apu_held
        beq @run
        rtl                             ; the options menu holds the sound unit
@run:
        rep #$20
.a16
        lda apu_sequence_position
        clc
        adc #TICK_CYCLES
        sta apu_sequence_position
@event:
.a16
        ldx apu_sequence_event
        lda apu_sequence_position
        cmp sequence_cycles,x
        bcc @outputs
        sep #$20
.a8
        lda sequence_clocks,x
        lsr a
        bcc @half
        jsr quarter_frame
@half:
        ldx apu_sequence_event
        lda sequence_clocks,x
        and #SEQUENCE_HALF
        beq @next
        jsr half_frame
@next:
        ldx apu_sequence_event
        lda sequence_clocks,x
        bmi @restart
        inx
        inx
        stx apu_sequence_event
        rep #$20
        bra @event
@restart:
        rep #$20
.a16
        lda apu_sequence_position
        sec
        sbc sequence_cycles,x
        sta apu_sequence_position
        lda apu_sequence_first
        sta apu_sequence_event
        bra @event
; The channels that changed.
@outputs:
        sep #$20
.a8
        ldx #APU_SQUARE1
        lda apu_settled,x
        bne @square2
        jsr pulse_output
@square2:
        ldx #APU_SQUARE2
        lda apu_settled,x
        bne @triangle
        jsr pulse_output
@triangle:
        lda apu_settled+APU_TRIANGLE
        bne @noise
        jsr triangle_output
@noise:
        lda apu_settled+APU_NOISE
        bne @done
        jsr noise_output
@done:
        rtl


; quarter_frame: the quarter clock: the envelopes of the squares and the
; noise, and the triangle's linear counter.
; In:       A8 X16
; Out:      the envelopes, apu_linear, apu_linear_reload; changed voices marked
; Changes:  A, X, the flags
; Keeps:    Y
; Time:     144-275 cycles with the JSR and the RTS
; Original: none (the NES sound unit)
quarter_frame:
.a8
.i16
        ldx #APU_SQUARE1
        jsr envelope_clock
        ldx #APU_SQUARE2
        jsr envelope_clock
        ldx #APU_NOISE
        jsr envelope_clock
; The linear counter: it loads from the triangle's control after a length load, else it
; counts down to 0. The triangle starts or stops when it leaves or reaches 0.
        lda apu_linear_reload
        beq @count
        lda apu_regs+APU_TRIANGLE+APU_CONTROL
        and #TRIANGLE_RELOAD
        bra @set
@count:
        lda apu_linear
        beq @control                    ; stays at 0
        dec a
@set:
        pha
        lda apu_linear
        beq @was_stopped
        pla
        sta apu_linear
        bne @control                    ; runs on
        bra @changed                    ; stops
@was_stopped:
        pla
        sta apu_linear
        beq @control                    ; stays stopped
@changed:
        stz apu_settled+APU_TRIANGLE
; The reload stays while the hold bit of the triangle's control holds the counters.
@control:
        lda apu_regs+APU_TRIANGLE+APU_CONTROL
        bmi @done                       ; TRIANGLE_HOLD
        stz apu_linear_reload
@done:
        rts

; envelope_clock: one quarter frame of an envelope. Its divider counts
; down from the level bits of the channel's control; at 0 the volume steps
; down from 15 to 0 (then starts again at 15 when the envelope loops).
; In:       X = the channel (APU_SQUARE1, APU_SQUARE2, APU_NOISE); A8 X16
; Out:      the channel's envelope; its voice marked when its volume changed
; Changes:  A, the flags
; Keeps:    X, Y
; Time:     34-74 cycles with the JSR and the RTS
; Original: none (the NES sound unit)
envelope_clock:
.a8
.i16
        lda apu_envelope_start,x
        beq @divider
        stz apu_envelope_start,x
        lda #15
        sta apu_envelope_decay,x
        bra @changed
@divider:
        lda apu_envelope_divider,x
        beq @step
        dec apu_envelope_divider,x
        rts
@step:
        lda apu_envelope_decay,x
        beq @end
        dec apu_envelope_decay,x
        bra @changed
@end:
        lda apu_regs+APU_CONTROL,x
        and #CONTROL_LOOP
        beq @reload                     ; stays at 0
        lda #15
        sta apu_envelope_decay,x
@changed:
        lda apu_regs+APU_CONTROL,x
        and #CONTROL_CONSTANT
        bne @reload                     ; a constant volume does not follow it
        stz apu_settled,x
@reload:
        lda apu_regs+APU_CONTROL,x
        and #CONTROL_LEVEL
        sta apu_envelope_divider,x
        rts

; half_frame: the half clock: the length counters, then the sweeps of the
; squares (it falls into sweep_clock for square 2).
; In:       A8 X16
; Out:      the length counters, the sweeps, the squares' periods
; Changes:  A, X, Y, the flags
; Time:     152-587 cycles with the JSR and the RTS
; Original: none (the NES sound unit)
half_frame:
.a8
.i16
        ldx #APU_NOISE
@length:
        lda apu_length_counter,x
        beq @next
        lda apu_regs+APU_CONTROL,x
        and halt_bits,x
        bne @next                       ; held
        dec apu_length_counter,x
        bne @next
        stz apu_settled,x               ; the channel goes silent
@next:
        dex
        dex
        dex
        dex
        bpl @length
        ldx #APU_SQUARE1
        jsr sweep_clock
        ldx #APU_SQUARE2

; sweep_clock: one half frame of a square's sweep. When its divider is at 0,
; the period moves to the target (if the sweep is on, its shift is not 0 and
; the channel is not silent); then the divider reloads, else it counts down.
; In:       X = the square (APU_SQUARE1, APU_SQUARE2); A8 X16
; Out:      the square's sweep divider and period; its voice marked
; Changes:  A, Y, the flags
; Keeps:    X
; Time:     34-218 cycles with the JSR and the RTS
; Original: none (the NES sound unit)
sweep_clock:
.a8
.i16
        lda apu_sweep_divider,x
        bne @count
        lda apu_regs+APU_SWEEP,x
        bpl @reload                     ; off
        and #SWEEP_SHIFT
        beq @reload
        jsr sweep_target
        bcs @reload                     ; silent
        rep #$20
.a16
        lda apu_target
        sta apu_regs+APU_PERIOD,x
        sep #$20
.a8
        stz apu_settled,x
        bra @reload
@count:
        lda apu_sweep_reload,x
        bne @reload
        dec apu_sweep_divider,x
        rts
@reload:
        lda apu_regs+APU_SWEEP,x
        lsr a
        lsr a
        lsr a
        lsr a
        and #SWEEP_RATE >> SWEEP_RATE_SHIFT
        sta apu_sweep_divider,x
        stz apu_sweep_reload,x
        rts

; sweep_target: a square's target period: the period plus or minus the
; period shifted right by the sweep's shift (square 1 subtracts one more).
; In:       X = the square (APU_SQUARE1, APU_SQUARE2); A8 X16
; Out:      apu_target = the target; carry set when the square is silent:
;           its period is under 8, or the target is over $7FF (a lower
;           target never silences); A8
; Changes:  A, Y, the flags, apu_change
; Keeps:    X
; Time:     32-143 cycles with the JSR and the RTS
; Original: none (the NES sound unit)
sweep_target:
.a8
.i16
        rep #$20
.a16
        lda apu_regs+APU_PERIOD,x
        cmp #PERIOD_AUDIBLE
        bcc @silent
        lda apu_regs+APU_SWEEP,x        ; the sweep (and the period's low byte above it)
        and #SWEEP_SHIFT
        tay
        lda apu_regs+APU_PERIOD,x
        cpy #0
        beq @shifted
@shift:
        lsr a
        dey
        bne @shift
@shifted:
        sta apu_change
        lda apu_regs+APU_SWEEP,x
        and #SWEEP_NEGATE
        bne @negate
        lda apu_regs+APU_PERIOD,x
        clc
        adc apu_change
        sta apu_target
        cmp #PERIOD_MAX+1
        sep #$20
.a8
        rts
@negate:
.a16
        lda apu_regs+APU_PERIOD,x
        sec
        sbc apu_change
        cpx #APU_SQUARE1
        bne @set
        dec a                           ; square 1's adder takes one more
@set:
        sta apu_target
        sep #$20
.a8
        clc
        rts
@silent:
.a16
        sep #$20
.a8
        sec
        rts

; ---- The DOC voices ----

; pulse_output: a square to its voice: silent without a length, under
; period 8 or over the sweep's limit; else its level (the constant volume or
; the envelope's) at the row of its menu level, its wave and its frequency.
; In:       X = the square (APU_SQUARE1, APU_SQUARE2); A8 X16
; Out:      the voice's DOC registers that changed; apu_settled + X = 1
; Changes:  A, Y, the flags
; Keeps:    X
; Time:     40-240 cycles with the JSR and the RTS, the GLU ready
; Original: none (the NES sound unit)
pulse_output:
.a8
.i16
        lda #1
        sta apu_settled,x
        lda apu_length_counter,x
        beq @silent
        jsr sweep_target
        bcs @silent
        lda apu_regs+APU_CONTROL,x
        bit #CONTROL_CONSTANT
        bne @level
        lda apu_envelope_decay,x
@level:
        pha
        lda apu_effects
        and channel_bits,x
        cmp #1                          ; carry: the effects row
        pla
        rep #$20
.a16
        and #$000F
        bcc @row
        ora #16
@row:
        tay
        sep #$20
.a8
        lda mix_pulse,y
        beq @silent
        pha
; The wave: the duty's tables, the octave of the period.
        rep #$20
.a16
        lda apu_regs+APU_PERIOD,x
        lsr a
        lsr a
        lsr a
        tay
        sep #$20
.a8
        lda apu_regs+APU_CONTROL,x
        lsr a
        lsr a
        lsr a
        and #DUTY_75 >> 3               ; the duty x 8
        ora period_octaves,y
        rep #$20
.a16
        and #$00FF
        tay
        sep #$20
.a8
        lda pulse_wave_pages,y
        jsr set_wave
        lda pulse_wave_tables,y
        jsr set_table
        jsr period_frequency
        pla
        jmp set_volume
@silent:
        lda #0
        jmp set_volume

; triangle_output: the triangle to its voice. It has no volume of its own:
; the sample channel's level and the menu's level give its register. It
; plays while both its counters run; else it holds the step where it is
; (frequency 0), as the NES's triangle does, so it stops without a click.
; In:       A8 X16
; Out:      the voice's DOC registers that changed; its apu_settled = 1
; Changes:  A, X, Y, the flags
; Time:     125-426 cycles with the JSR and the RTS, the GLU ready
; Original: none (the NES sound unit)
triangle_output:
.a8
.i16
        ldx #APU_TRIANGLE
        lda #1
        sta apu_settled,x
        rep #$20
.a16
        lda apu_regs+APU_DAC            ; the level (and the latch after it, never written)
        and #%01111100
        lsr a
        lsr a                           ; the level / 4
        sta apu_index
        sep #$20
.a8
        lda apu_effects
        and #1 << VOICE_TRIANGLE
        asl a
        asl a
        asl a                           ; 32: the effects row
        ora apu_index
        rep #$20
.a16
        and #$00FF
        tay
        sep #$20
.a8
        lda mix_triangle,y
        jsr set_volume
        lda apu_length_counter+APU_TRIANGLE
        beq @hold
        lda apu_linear
        beq @hold
        rep #$20
.a16
        lda apu_regs+APU_TRIANGLE+APU_PERIOD
        lsr a
        lsr a
        lsr a
        tay
        sep #$20
.a8
        lda period_octaves,y
        rep #$20
.a16
        and #$00FF
        tay
        sep #$20
.a8
        lda triangle_wave_pages,y
        jsr set_wave
        lda triangle_wave_tables,y
        jsr set_table
        jmp period_frequency
@hold:
        rep #$20
.a16
        lda #0
        jmp set_frequency

; noise_output: the noise to its voice: silent without a length; else its
; level (constant or the envelope's) with the sample channel's level, at
; the row of its menu level, and the frequency of its period.
; In:       A8 X16
; Out:      the voice's DOC registers that changed; its apu_settled = 1
; Changes:  A, X, Y, the flags, apu_index
; Time:     43-119 cycles with the JSR and the RTS, the GLU ready
; Original: none (the NES sound unit)
noise_output:
.a8
.i16
        ldx #APU_NOISE
        lda #1
        sta apu_settled,x
        lda apu_length_counter,x
        beq @silent
        lda apu_regs+APU_CONTROL,x
        bit #CONTROL_CONSTANT
        bne @level
        lda apu_envelope_decay,x
@level:
        rep #$20
.a16
        and #$000F
        sta apu_index
        lda apu_regs+APU_DAC            ; the level (and the latch after it, never written)
        and #%01111100                  ; the level / 4, x 4
        asl a
        asl a                           ; x 16: one row of 16 channel levels
        ora apu_index
        sta apu_index
        sep #$20
.a8
        lda apu_effects
        and #1 << VOICE_NOISE
        lsr a
        lsr a                           ; 2: the effects row is 512 bytes on
        ora apu_index+1
        sta apu_index+1
        ldy apu_index
        lda mix_noise,y
        beq @silent
        pha
; The period: the long table, or its first 4096 steps for slow noise.
        rep #$20
.a16
        lda apu_regs+APU_NOISE+APU_PERIOD
        and #NOISE_PERIOD_INDEX
        tay
        sep #$20
.a8
        lda #NOISE_PAGE
        jsr set_wave
        lda noise_tables,y
        jsr set_table
        rep #$20
.a16
        tya
        asl a
        tay
        lda noise_frequencies,y
        jsr set_frequency
.a8                                     ; set_frequency returns with 8-bit A
        pla
        jmp set_volume
@silent:
        lda #0
        jmp set_volume

; period_frequency: the DOC frequency of the channel's period.
; set_frequency: A16 = a frequency for the channel's voice.
; set_volume, set_wave, set_table: A = a value for the voice's register.
; Each writes the DOC only when the value changes.
; In:       X = the channel (APU_*); A8 X16 (set_frequency: A16)
; Out:      A8; voice_frequency, voice_volume, voice_wave, voice_table
; Changes:  A, Y (period_frequency), the flags
; Keeps:    X
; Time:     17-144 cycles with the JSR and the RTS, the GLU ready
; Original: none
period_frequency:
.a8
.i16
        rep #$20
.a16
        lda apu_regs+APU_PERIOD,x
        asl a
        tay
        lda period_frequencies,y
set_frequency:
.a16
        cmp voice_frequency,x
        beq @same
        sta voice_frequency,x
        sep #$20
.a8
        jmp write_frequency
@same:
.a16
        sep #$20
.a8
        rts
set_volume:
.a8
.i16
        cmp voice_volume,x
        beq @same
        sta voice_volume,x
        jmp write_volume
@same:
        rts
set_wave:
.a8
.i16
        cmp voice_wave,x
        beq @same
        sta voice_wave,x
        jmp write_wave
@same:
        rts
set_table:
.a8
.i16
        cmp voice_table,x
        beq @same
        sta voice_table,x
        jmp write_table
@same:
        rts

; write_volume, write_wave, write_table: A into that register of the
; channel's voice. write_frequency: voice_frequency of the channel.
; doc_voice_write: B into register group A of the channel's voice. Each
; waits for the GLU before its access (SOUNDCTL bit 7: busy).
; In:       X = the channel (APU_*); A8; the GLU in register mode
; Out:      the DOC register
; Changes:  A, the flags
; Keeps:    X, Y
; Time:     41-105 cycles with the JSR and the RTS, the GLU ready
; Original: none
write_volume:
.a8
.i16
        xba
        lda #DOC_VOLUME
        bra doc_voice_write
write_wave:
.a8
.i16
        xba
        lda #DOC_WAVE
        bra doc_voice_write
write_table:
.a8
.i16
        xba
        lda #DOC_TABLE
        bra doc_voice_write
write_frequency:
.a8
.i16
        lda voice_frequency,x
        xba
        lda #DOC_FREQ_LOW
        jsr doc_voice_write
        lda voice_frequency+1,x
        xba
        lda #DOC_FREQ_HIGH
doc_voice_write:
.a8
.i16
        ora voice_numbers,x
        pha
@busy:
        lda f:SOUNDCTL
        bmi @busy
        pla
        sta f:SOUNDADRL
        xba
        sta f:SOUNDDATA
        rts

; ---- Tables ----

; Per channel, at its register offset: its bit in $4015 and in apu_effects
; (the NES's order is the order of the VOICE_* numbers), its DOC voice, and
; the control bit that holds its length counter.
.assert VOICE_SQUARE1 = 0 && VOICE_SQUARE2 = 1 && VOICE_TRIANGLE = 2 && VOICE_NOISE = 3, error, "the NES channel order"
channel_bits:
        .byte 1 << VOICE_SQUARE1, 0, 0, 0, 1 << VOICE_SQUARE2, 0, 0, 0
        .byte 1 << VOICE_TRIANGLE, 0, 0, 0, 1 << VOICE_NOISE, 0, 0, 0
voice_numbers:
        .byte VOICE_SQUARE1, 0, 0, 0, VOICE_SQUARE2, 0, 0, 0
        .byte VOICE_TRIANGLE, 0, 0, 0, VOICE_NOISE, 0, 0, 0
halt_bits:
        .byte CONTROL_LOOP, 0, 0, 0, CONTROL_LOOP, 0, 0, 0
        .byte TRIANGLE_HOLD, 0, 0, 0, CONTROL_LOOP, 0, 0, 0

; The length counter's load for each length index (NES sound unit: bits 7-3 of its length stores).
length_table:
        .byte 10, 254, 20, 2, 40, 4, 80, 6, 160, 8, 60, 10, 14, 12, 26, 14
        .byte 12, 16, 24, 18, 48, 20, 96, 22, 192, 24, 72, 26, 16, 28, 32, 30
.assert * - length_table = LENGTH_INDEXES, error, "a length for each length index"

; The frame sequencer's events, five-step mode then four-step mode, in NES
; CPU cycles after the reset (apu_sequence_position counts CPU cycles; the
; sound unit's sequencer steps at 3728.5, 7456.5 and 11185.5 of its own
; cycles, two CPU cycles each). The last event of a mode is its period
; (18,641 and 14,915 sound unit cycles), where the sequencer starts again.
; The five-step mode's step at 14,914.5 gives no clock.
sequence_cycles:
        .word 7457, 14913, 22371, 37282
        .word 7457, 14913, 22371, 29830
sequence_clocks:
        .word SEQUENCE_QUARTER, SEQUENCE_QUARTER | SEQUENCE_HALF
        .word SEQUENCE_QUARTER, SEQUENCE_QUARTER | SEQUENCE_HALF | SEQUENCE_LAST
        .word SEQUENCE_QUARTER, SEQUENCE_QUARTER | SEQUENCE_HALF
        .word SEQUENCE_QUARTER, SEQUENCE_QUARTER | SEQUENCE_HALF | SEQUENCE_LAST
.assert SEQUENCE_FOUR = 8, error, "the four-step events follow the four five-step events"

; The octave of a period (0 for periods 8-15 ... 7 for 1024-2047), by the
; period / 8: the table of that octave in scripts/sound_bank.py. Periods
; under 8 (the triangle only) play the first table.
period_octaves:
.repeat 256, step
  .if step >= 128
        .byte 7
  .elseif step >= 64
        .byte 6
  .elseif step >= 32
        .byte 5
  .elseif step >= 16
        .byte 4
  .elseif step >= 8
        .byte 3
  .elseif step >= 4
        .byte 2
  .elseif step >= 2
        .byte 1
  .else
        .byte 0
  .endif
.endrepeat

; The squares' DOC page and table register by the duty x 8 + the octave.
; Duty 3 (75%) is duty 1 (25%) turned over: it plays duty 1's tables.
pulse_wave_pages:
.repeat 4, duty
  .repeat 8, octave
        .byte .ident(.sprintf("PULSE_PAGE_%d_%d", duty - (duty / 3) * 2, octave))
  .endrepeat
.endrepeat
pulse_wave_tables:
.repeat 4, duty
  .repeat 8, octave
        .byte (.ident(.sprintf("PULSE_SIZE_%d_%d", duty - (duty / 3) * 2, octave)) << 3) | PULSE_RESOLUTION
  .endrepeat
.endrepeat
triangle_wave_pages:
.repeat 8, octave
        .byte .ident(.sprintf("TRIANGLE_PAGE_%d", octave))
.endrepeat
triangle_wave_tables:
.repeat 8, octave
        .byte (.ident(.sprintf("TRIANGLE_SIZE_%d", octave)) << 3) | TRIANGLE_RESOLUTION
.endrepeat

; The noise: its table register and DOC frequency by its period number
; (NES sound unit: the noise's 16 periods in CPU cycles).
.macro noise_period cycles, number
  .if number < NOISE_SLOW_FIRST
        .word (NOISE_FC_LONG + (cycles) / 2) / (cycles)
  .else
        .word (NOISE_FC_SLOW + (cycles) / 2) / (cycles)
  .endif
.endmacro
noise_frequencies:
        noise_period 4, 0
        noise_period 8, 1
        noise_period 16, 2
        noise_period 32, 3
        noise_period 64, 4
        noise_period 96, 5
        noise_period 128, 6
        noise_period 160, 7
        noise_period 202, 8
        noise_period 254, 9
        noise_period 380, 10
        noise_period 508, 11
        noise_period 762, 12
        noise_period 1016, 13
        noise_period 2034, 14
        noise_period 4068, 15
noise_tables:
.repeat 16, number
  .if number < NOISE_SLOW_FIRST
        .byte (NOISE_SIZE_LONG << 3) | NOISE_RESOLUTION
  .else
        .byte (NOISE_SIZE_SLOW << 3) | NOISE_RESOLUTION
  .endif
.endrepeat
.assert NOISE_STEPS = 256 << NOISE_SIZE_LONG, error, "the long noise table"
.assert NOISE_PAGE & ((NOISE_STEPS >> 8) - 1) = 0, error, "the noise table at a multiple of its size"
.assert SOUND_WAVES_DOC + SOUND_WAVES_SIZE <= CLOCK_PAGE << 8, error, "the waves under the clock's page"
.assert SOUND_WAVES_DOC >= (NOISE_PAGE << 8) + NOISE_STEPS || SOUND_WAVES_DOC + SOUND_WAVES_SIZE <= NOISE_PAGE << 8, error, "the waves apart from the noise"

; The DOC frequency of each period of the squares and the triangle (2048
; words: bank 0 system data, segment NATIVE). Periods under 7 are above the
; DOC's range (the triangle at 15 kHz and up, which no NES song plays): they
; get the highest frequency.
.segment "NATIVE"
period_frequencies:
.repeat 2048, period
  .if period < 7
        .word $FFFF
  .else
        .word (FC_SCALE + (period + 1) / 2) / (period + 1)
  .endif
.endrepeat
.segment "SOUND"
