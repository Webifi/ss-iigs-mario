; The NES sound unit model (src/sound.s): its channels, the forms of the
; values that it takes, its calls, and the DOC voices.
;
; A NES sound program drives the model through calls, one call for each
; store that the original makes to its sound unit. Each call names its
; channel and takes its value in the form below:
;
;   apu_control CHANNEL     A8   a square's duty and volume or envelope, the
;                                noise's volume or envelope, the triangle's
;                                linear counter
;   apu_sweep CHANNEL       A8   a square's sweep
;   apu_period CHANNEL      A16  a square's or the triangle's period
;   apu_noise_period        A8   the noise's period index and sequence
;   apu_length CHANNEL      A8   a length index: the length counter loads
;   apu_enable              A8   the channels that are on
;   apu_sequence            A8   the frame sequencer's mode; it starts again
;   apu_sample_level        A8   the sample channel's output level
;
; A call that changes only a latch (the control, the period, the sample
; level) marks the channel's DOC voice for the next tick, and only when the
; value changes. A call whose store is an event of the sound unit (a sweep, a
; length load, the enable bits, the sequencer) runs its routine at once, so
; the events happen in the order of the program's calls, as on the NES.
; src/sound.s keeps the state of the sound unit and plays it on the DOC at
; each tick of the clock (src/clock.s). Nothing in this file or in
; src/sound.s is particular to one game.
;
; Every call takes A8 (apu_period: A16) and returns A8; the index width may
; be 8 or 16 bits. A call keeps A and Y; the calls with a routine (apu_sweep,
; apu_period, apu_length, apu_enable, apu_sequence) change X. All change the
; flags. DBR = bank 0.

.ifndef SOUND_INC
SOUND_INC = 1

; The DOC voices: one for each channel of the sound unit, the idle
; oscillators, then the clock (src/clock.s CLOCK_VOICE, the last enabled
; oscillator). DOC_VOICES, the enabled count, comes from the build's
; sound_bank.inc (scripts/sound_bank.py, which gives the reason).
VOICE_SQUARE1 = 0
VOICE_SQUARE2 = 1
VOICE_TRIANGLE = 2
VOICE_NOISE = 3

; The channels. Each per-channel table of src/sound.s has 4 bytes for each
; channel, at the channel's offset, so one index register reaches a
; channel's latches and its state.
APU_SQUARE1 = $00
APU_SQUARE2 = $04
APU_TRIANGLE = $08
APU_NOISE = $0C

; The latches of the model (apu_regs, src/sound.s), in the order of the NES's
; registers ($4000 + offset). A channel's latches, from its offset:
APU_CONTROL = 0                 ; its control (apu_control)
APU_SWEEP = 1                   ; a square's sweep (apu_sweep)
APU_PERIOD = 2                  ; its period, a word (apu_period, apu_noise_period)
; The latches that belong to no channel.
APU_DAC = $11                   ; the sample channel's output level (apu_sample_level)
APU_STATUS = $15                ; the channel enable bits (apu_enable)
APU_FRAME = $17                 ; the frame sequencer's mode (apu_sequence)
APU_REGISTERS = $18

; The control of a square (apu_control): the duty, and either a constant
; volume (CONTROL_CONSTANT | the volume) or an envelope that decays from 15
; with the level as its rate (the decay restarts at each length load).
DUTY_12 = %00000000             ; 12.5%
DUTY_25 = %01000000
DUTY_50 = %10000000
DUTY_75 = %11000000             ; played as 25% (the same sound, turned over)
CONTROL_LOOP = %00100000        ; the envelope loops; the length counter holds
CONTROL_CONSTANT = %00010000    ; the level is the volume; else the envelope's rate
CONTROL_LEVEL = %00001111       ; the volume or the envelope's rate, 0-15
; The control of the noise: the same without the duty. The control of the
; triangle: its linear counter.
TRIANGLE_HOLD = %10000000       ; the counters hold; the linear counter reloads each quarter clock
TRIANGLE_RELOAD = %01111111     ; the linear counter's reload value, in quarter clocks

; The sweep of a square (apu_sweep): every rate + 1 half clocks the period
; changes by itself shifted right by the shift.
SWEEP_ENABLE = %10000000
SWEEP_RATE = %01110000
SWEEP_RATE_SHIFT = 4            ; the rate is in bits 6-4
SWEEP_NEGATE = %00001000        ; the period goes down (square 1: by one more)
SWEEP_SHIFT = %00000111

; The period of the noise (apu_noise_period).
NOISE_SHORT = %10000000         ; the short sequence (the model plays the long one)
NOISE_PERIOD_INDEX = %00001111  ; the period: an index of the NES's 16 noise periods

; A length index (apu_length), 0-31: the length counter loads the NES's
; length of that index (src/sound.s length_table).
LENGTH_INDEXES = 32

; The channel bits (apu_enable, apu_set_effects), in the NES's order.
CHANNEL_SQUARE1 = 1 << VOICE_SQUARE1
CHANNEL_SQUARE2 = 1 << VOICE_SQUARE2
CHANNEL_TRIANGLE = 1 << VOICE_TRIANGLE
CHANNEL_NOISE = 1 << VOICE_NOISE
CHANNELS_NONE = 0
CHANNELS_ALL = CHANNEL_SQUARE1 | CHANNEL_SQUARE2 | CHANNEL_TRIANGLE | CHANNEL_NOISE

; The frame sequencer's mode (apu_sequence).
SEQUENCE_FIVE_STEP = %10000000  ; five steps; the start gives a quarter and a half clock at once

; The latch calls (apu_control, apu_noise_period, apu_sample_level) are
; inline: a compare, and the store and the mark when the value changes. Their
; skip is an unnamed label, which keeps the caller's @ labels in scope (a
; named label, also a .local one, would end that scope): a caller's own :+ or
; :- must not reach across one of these calls.

; apu_control CHANNEL: A8 = the channel's control (the forms above). No
; event. Keeps A, X, Y.
.macro apu_control channel
        cmp apu_regs+(channel)+APU_CONTROL
        beq :+
        sta apu_regs+(channel)+APU_CONTROL
        stz apu_settled+(channel)       ; the voice again at the next tick
:
.endmacro

; apu_sweep CHANNEL: A8 = a square's sweep. Event: the sweep's divider
; reloads at the next half clock (also when the value stays). Keeps A, Y.
.macro apu_sweep channel
        ldx #channel
        jsr apu_sweep_x
.endmacro

; apu_period CHANNEL: A16 = a square's or the triangle's period, 0-$7FF. No
; event. Out: A8. Keeps the value in A's two bytes, and Y.
.macro apu_period channel
        ldx #channel
        jsr apu_period_x
.a8
.endmacro

; apu_noise_period: A8 = the noise's period (NOISE_SHORT, NOISE_PERIOD_INDEX).
; No event. Keeps A, X, Y.
.macro apu_noise_period
        cmp apu_regs+APU_NOISE+APU_PERIOD
        beq :+
        sta apu_regs+APU_NOISE+APU_PERIOD
        stz apu_settled+APU_NOISE
:
.endmacro

; apu_length CHANNEL: A8 = a length index, 0-31. Event: the length counter
; loads (when the channel is on), and the envelope starts again at 15 at the
; next quarter clock (the triangle: its linear counter reloads). Keeps A, Y.
.macro apu_length channel
        ldx #channel
        jsr apu_length_x
.endmacro

; apu_enable: A8 = the channels that are on (CHANNEL_*). Event: a channel
; that is off loses its length counter, and a length load does not reach it.
; Keeps A, Y.
.macro apu_enable
        jsr apu_enable_bits
.endmacro

; apu_sequence: A8 = the frame sequencer's mode (SEQUENCE_FIVE_STEP or 0).
; Event: the sequence starts again; in five-step mode the start gives a
; quarter clock and a half clock at once. Keeps A, Y.
.macro apu_sequence
        jsr apu_sequence_start
.endmacro

; apu_sample_level: A8 = the sample channel's output level, 0-127. In the
; NES mixer it makes the triangle and the noise quieter. No event. Keeps A,
; X, Y.
.macro apu_sample_level
        cmp apu_regs+APU_DAC
        beq :+
        sta apu_regs+APU_DAC
        stz apu_settled+APU_TRIANGLE    ; the level changes both voices
        stz apu_settled+APU_NOISE
:
.endmacro

.endif
