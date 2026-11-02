; The game clock: the DOC timer oscillator interrupts four times in each
; picture of the card's video mode, and the main loop runs one frame of the
; original at each fourth tick (frames_due). The game therefore runs at the
; picture rate of the mode (src/secondsight/mode.s), which is near the rate
; of the original, the NTSC NES rate 1,789,773 / 29,780.5 =
; 60.0988 Hz: 60.0588 Hz on VGA, 60.173 Hz on AppleColor RGB. The sound unit
; model (src/sound.s) steps its envelopes at each tick, four times in each
; frame, as the NES does. The startup reads the monitor from the firmware's
; status (the sense byte): the card sets the mode of that monitor.
;
; The timer is the last enabled oscillator (CLOCK_VOICE): it plays a silent
; page of DOC RAM in free-run mode with its interrupt on. Each pass through
; the 256-byte page is one tick. The DOC steps each enabled oscillator once
; in each scan of DOC_SLOTS slots, DOC_SLOT_RATE / DOC_SLOTS scans a second,
; and a table at resolution 0 plays F / 2^17 passes in each scan (Apple
; IIgs Hardware Reference, chapter 5, p. 113: the output frequency is
; SR x F / 2^(17 + resolution), with the scan rate SR = 894,886 Hz / (the
; enabled oscillators + 2)). So F = 2^17 x 4 x the picture rate x DOC_SLOTS
; / DOC_SLOT_RATE. F is not a whole number: the tick adds the fraction each
; time and uses F + 1 when it carries, so the average is exact.
;
; The computed rate is not the card's real rate: each output of the card's
; clock chip can be 0.5% off its listed frequency, and its crystal is not
; the IIgs's (Second Sight reference, docs/14-custom-code.md, "Game
; timing"). At 60 Hz, 0.5% would slip a frame every 3.3 s: a picture shown
; twice, or a frame never shown. So the card measures where each packet
; comes against its vertical retrace and sends the phase back in its token
; (src/secondsight/picture.s), and clock_phase moves F to hold each packet a
; little before the retrace. The game never waits for the card.
;
; Data in: the sense byte (clock_start), the card's token (clock_phase).
; Data out: frames_due (src/game.s main_loop counts it down), the ticks of
; input_tick and sound_tick.
;
; Hardware rules:
;   - The DOC keeps no register of a disabled oscillator: they are not
;     refreshed (Ensoniq 5503 data sheet, the oscillator enable register).
;     So the oscillators go on first, then their registers.
;   - The sound GLU: wait while SOUNDCTL shows busy before each access; a
;     read of SOUNDDATA returns the byte that the access before fetched and
;     starts the next fetch (Apple IIgs Hardware Reference, pp. 104-107).
;   - A read of DOC_IRQ acknowledges the oscillator that it reports; while
;     another interrupt waits, the DOC keeps the IRQ line low (Ensoniq 5503
;     data sheet, the interrupt register).
;   - The native-mode IRQ vector is at $FFEE; with SHADOW_IOLC set,
;     $C000-$FFFF of bank 0 is RAM, so the vector is RAM that clock_start
;     writes (Hardware Reference, the shadow register).
;
; Routines:
;   clock_start   the timer and its interrupt (JSR, from the startup)
;   clock_phase   move F by the phase of the last packet (JSR, src/packet.s)
;   clock_irq     the interrupt (the IRQ vector)
;   doc_write     one DOC register write

.a8
.i16

CLOCK_VOICE = DOC_VOICES - 1    ; the timer: the last enabled oscillator
CLOCK_PAGE = $FF                ; the DOC RAM page of the timer's silent wave
CLOCK_WAVE_SIZE = $100          ; the bytes of that wave: one 256-byte table
DOC_TABLE_256 = $00             ; DOC_TABLE: a 256-byte table, resolution 0
DOC_SILENCE = $80               ; the zero level of a DOC sample (0 halts an oscillator)
DOC_SLOT_RATE = 894886          ; the oscillator slots a second: 7,159,090 Hz / 8, rounded
DOC_SLOTS = DOC_VOICES + 2      ; the slots of one scan: the enabled oscillators and two more
TICKS_PER_FRAME = 4

; doc_rate PICTURE, INTEGER, FRACTION: INTEGER and FRACTION (1/65536) of F
; for TICKS_PER_FRAME ticks in each picture of PICTURE clock periods at the
; mode's clock. F x 65536 = 2^17 x 4 x 65536 x DOC_SLOTS x the clock /
; (DOC_SLOT_RATE x PICTURE). Each step keeps its product under 2^31, for a
; ca65 with 32-bit integers: the quotients come out 11 bits at a time.
.macro doc_rate picture, integer, fraction
.local clock, q0, r0, q1, r1, q2, rate, g0, s0, g1, s1, g2, fixed
        clock = secondsight_MODE_CLOCK_KHZ * 1000
        q0 = clock / (picture)
        r0 = clock .mod (picture)
        q1 = r0 * 2048 / (picture)
        r1 = r0 * 2048 .mod (picture)
        q2 = r1 * 2048 / (picture)
        rate = q0 * $400000 + q1 * 2048 + q2    ; the picture rate, x 2^22
; F x 65536 for one slot: rate x 2^35 / (2^22 x DOC_SLOT_RATE) =
; rate x 2^13 / DOC_SLOT_RATE.
        g0 = rate / DOC_SLOT_RATE
        s0 = rate .mod DOC_SLOT_RATE
        g1 = s0 * 2048 / DOC_SLOT_RATE
        s1 = s0 * 2048 .mod DOC_SLOT_RATE
        g2 = s1 * 4 / DOC_SLOT_RATE
        fixed = (g0 * 8192 + g1 * 4 + g2) * DOC_SLOTS
        integer = fixed >> 16
        fraction = fixed & $FFFF
.endmacro
.assert TICKS_PER_FRAME = 4, error      ; doc_rate: the 4 of 2^35 = 2^17 x 4 x 65536
        doc_rate secondsight_MODE_VGA_PICTURE, CLOCK_VGA, CLOCK_VGA_FRACTION
        doc_rate secondsight_MODE_RGB_PICTURE, CLOCK_RGB, CLOCK_RGB_FRACTION
; The phase loop (clock_phase): each packet's phase from the card, in units
; of 142 us (secondsight_PHASE_UNIT_STEPS), less PHASE_TARGET, is the error.
; F = the computed F + (PHASE_GAIN x the error + the sum of the errors) x
; PHASE_SCALE / 256. The gains hold the packet within about 1.3 ms before to
; 0.4 ms after the target with the card's clock 0.5% off either way, and lock
; in about 2 s from any phase (a simulation of the loop with the measured
; jitter of the packet, 0.8 ms). The gains are those of 7 slots; F grows
; with the slots, so PHASE_SCALE keeps each correction the same share of F.
PHASE_TARGET = -3               ; 3 units before the card's retrace
PHASE_GAIN = 8                  ; the error's own weight: clock_phase shifts it 3 times
PHASE_SUM_LIMIT = 351           ; the sum moves F by at most this / 256 of F at 7 slots: 0.56%
PHASE_SCALE_SHIFT = 2           ; PHASE_SCALE = 1 << this: DOC_SLOTS / 7
PHASE_ERROR_MAX = (secondsight_TOKEN_PHASE >> 1) - PHASE_TARGET ; 34: the largest error (the most units after)
.assert DOC_SLOTS = 7 << PHASE_SCALE_SHIFT, error, "the phase loop's scale"
; F with the largest correction must fit the 16-bit frequency.
.assert CLOCK_VGA + 1 + (((PHASE_GAIN * PHASE_ERROR_MAX + PHASE_SUM_LIMIT) << PHASE_SCALE_SHIFT) >> 8) < $FFFF, error
.assert CLOCK_RGB + 1 + (((PHASE_GAIN * PHASE_ERROR_MAX + PHASE_SUM_LIMIT) << PHASE_SCALE_SHIFT) >> 8) < $FFFF, error

; The clock state (bank 0; the interrupt and the main loop run with DBR = 0).
.segment "SYSRAM"
clock_step_fraction: .res 2     ; F for the running mode: its fraction, in 1/65536 (clock_phase writes it)
clock_step: .res 2              ; and its whole part
clock_nominal: .res 4           ; F of the mode as computed: the fraction, then the whole part
clock_error_sum: .res 2         ; clock_phase: the sum of the phase errors
.assert clock_step = clock_step_fraction + 2, error ; clock_phase writes F x 65536 as bytes 1-2 and 3
clock_fraction: .res 2          ; clock_irq: the fraction of F not yet used
clock_ticks: .res 1             ; clock_irq: the ticks of the frame: 0-3
frames_due: .res 1              ; the frames that the main loop still has to run (clock_irq counts up,
                                ; src/game.s main_loop down, src/menu.s clears it)
doc_master: .res 1              ; the owner's master volume (SOUNDCTL_VOLUME bits): src/sound.s
                                ; sound_start reads it from CP_VOLUME at the start; never changed

.segment "NATIVE"

; ---------------------------------------------------------------------------
; clock_start: the timer oscillator and its interrupt, at the rate of the
; mode for the monitor. The other interrupt sources go off; input_start
; (src/input.s) then turns on the ADB GLU's.
;
; In:       A   the sense byte of the firmware's status (SS_SENSE); A8 X16,
;           DBR = 0; the sound unit's voices set and doc_master read (src/sound.s
;           sound_start)
; Out:      the timer runs; the interrupts are on (CLI at the end, whatever
;           the caller's flag)
; Changes:  A, X; clock_step, clock_step_fraction, clock_nominal,
;           clock_error_sum, clock_fraction, clock_ticks, frames_due;
;           SHADOW (SHADOW_IOLC set: RAM at $C000-$FFFF), the
;           IRQ vector ($FFEE), INTEN, VGCINT, SCANINT (all 0), KMSTATUS
;           (its three interrupt enables off); the DOC: DOC_ENABLE, the
;           control and volume of the idle oscillators, the timer's
;           registers, DOC RAM page CLOCK_PAGE; SOUNDCTL (register mode)
; Keeps:    Y, D, DBR
; Original: none
; ---------------------------------------------------------------------------
clock_start:
        php
        sei
; F of the monitor's mode: the VGA list when the sense bit is set.
        a16
        and #secondsight_STATUS_SENSE
        bne @vga
        lda #CLOCK_RGB
        ldx #CLOCK_RGB_FRACTION
        bra @rate
@vga:
        lda #CLOCK_VGA
        ldx #CLOCK_VGA_FRACTION
@rate:
        sta clock_step
        sta clock_nominal+2
        stx clock_step_fraction
        stx clock_nominal
        ldx #0
        stx clock_error_sum
        a8
; The enabled oscillators: DOC_ENABLE holds (the last one) x 2. Then the
; idle ones between the sound unit's voices and the timer: halted and
; silent. Their registers are written after the enable (the DOC keeps no
; register of a disabled oscillator).
        ldx #DOC_ENABLE
        lda #CLOCK_VOICE*2
        jsr doc_write
        ldx #DOC_CONTROL+VOICE_NOISE+1
        lda #DOC_HALT                   ; halted, free run, no interrupt
@idle:
        jsr doc_write
        inx
        cpx #DOC_CONTROL+CLOCK_VOICE
        bne @idle
        ldx #DOC_VOLUME+VOICE_NOISE+1
        lda #0                          ; volume 0: silent
@silent:
        jsr doc_write
        inx
        cpx #DOC_VOLUME+CLOCK_VOICE
        bne @silent
; The timer's wave: one page of DOC RAM, all DOC_SILENCE, through the GLU
; in RAM mode with the address incrementing after each byte.
@ready:
        lda f:SOUNDCTL
        bmi @ready                      ; SOUNDCTL_BUSY
        lda doc_master
        ora #SOUNDCTL_RAM|SOUNDCTL_INC
        sta f:SOUNDCTL
        lda #0
        sta f:SOUNDADRL
        lda #CLOCK_PAGE
        sta f:SOUNDADRH
        ldx #CLOCK_WAVE_SIZE
@silence:
        lda f:SOUNDCTL
        bmi @silence                    ; SOUNDCTL_BUSY
        lda #DOC_SILENCE
        sta f:SOUNDDATA
        dex
        bne @silence
; The timer's registers: silent, the page, a 256-byte table, F.
        ldx #DOC_VOLUME+CLOCK_VOICE
        lda #0                          ; volume 0: silent
        jsr doc_write
        ldx #DOC_WAVE+CLOCK_VOICE
        lda #CLOCK_PAGE
        jsr doc_write
        ldx #DOC_TABLE+CLOCK_VOICE
        lda #DOC_TABLE_256
        jsr doc_write
        ldx #DOC_FREQ_HIGH+CLOCK_VOICE
        lda clock_step+1
        jsr doc_write
        ldx #DOC_FREQ_LOW+CLOCK_VOICE
        lda clock_step
        jsr doc_write
        stz clock_ticks
        stz frames_due
        stz clock_fraction
        stz clock_fraction+1
; The interrupt: the vector in RAM, and no other source. INTEN, VGCINT
; and SCANINT at 0: no Mega II, video or scan line interrupt; KMSTATUS:
; no ADB interrupt until input_start.
        lda f:SHADOW
        ora #SHADOW_IOLC
        sta f:SHADOW                    ; RAM at $C000-$FFFF: the vector in RAM
        a16
        lda #.loword(clock_irq)
        sta f:IRQ_VECTOR
        a8
        lda #0
        sta f:INTEN
        sta f:VGCINT
        sta f:SCANINT
        lda f:KMSTATUS
        and #<~(KM_MOUSE_IRQ|KM_DATA_IRQ|KM_KEY_IRQ)
        sta f:KMSTATUS
; The timer starts: free run, interrupt on.
        ldx #DOC_CONTROL+CLOCK_VOICE
        lda #DOC_IRQ_ENABLE
        jsr doc_write
        plp
        cli
        rts

; ---------------------------------------------------------------------------
; clock_phase: move F by the phase of the last packet: the error is the
; phase less PHASE_TARGET, in units (+ after the card's retrace, - before);
; the sum of the errors stays within PHASE_SUM_LIMIT. The next tick takes
; this F.
;
; In:       A   the card's token (src/secondsight/picture.s: its phase bits,
;               secondsight_TOKEN_EARLY and secondsight_TOKEN_PHASE);
;           A8 X16, DBR = 0
; Out:      clock_step_fraction+1, clock_step+1: F x 65536 with the
;           correction; clock_error_sum
; Changes:  A, X
; Keeps:    Y, D, DBR, A8 X16
; Time:     about 130 cycles, once in a frame (src/packet.s packet_frame)
; Original: none
; ---------------------------------------------------------------------------
.a8
.i16
clock_phase:
        bit #secondsight_TOKEN_EARLY | secondsight_TOKEN_PHASE
        beq @none                       ; no measurement
; The phase in units: the TOKEN_PHASE bits, negative when TOKEN_EARLY says
; the packet came before the retrace.
        a16
        and #$00FF
        tax                             ; X = the token
        and #secondsight_TOKEN_PHASE
        lsr a                           ; A = the units
        cpx #secondsight_TOKEN_EARLY
        bcc @after                      ; bit 7 clear: after the retrace
        eor #$FFFF
        inc a                           ; before it: negative
; The error, and the sum of the errors within +-PHASE_SUM_LIMIT.
@after:
        sec
        sbc #.loword(PHASE_TARGET)      ; the error
        pha
        clc
        adc clock_error_sum
        bmi @negative
        cmp #PHASE_SUM_LIMIT + 1
        bcc @summed
        lda #PHASE_SUM_LIMIT
        bra @summed
@negative:
        cmp #.loword(-PHASE_SUM_LIMIT)
        bcs @summed
        lda #.loword(-PHASE_SUM_LIMIT)
@summed:
        sta clock_error_sum
; The correction: (PHASE_GAIN x the error + the sum) x PHASE_SCALE.
        pla
        asl a
        asl a
        asl a                           ; x PHASE_GAIN
        clc
        adc clock_error_sum
  .repeat PHASE_SCALE_SHIFT
        asl a                           ; x PHASE_SCALE
  .endrepeat
; F x 65536 + the correction x 256: bytes 1-2, then byte 3 with the sign.
        tax
        clc
        adc clock_nominal+1
        sta clock_step_fraction+1       ; the high byte of the fraction, the low byte of F
        txa
        and #$8000                      ; the sign of the correction
        beq @positive
        lda #$00FF                      ; a negative correction: byte 3 adds $FF
@positive:
        a8
        adc clock_nominal+3             ; with the carry of bytes 1-2
        sta clock_step+1                ; the high byte of F
@none:
        rts
.assert PHASE_GAIN = 8, error           ; clock_phase: three shifts

; ---------------------------------------------------------------------------
; clock_irq: the IRQ. A timer tick sets the frequency of its next pass,
; runs the input tick and the sound tick (src/input.s, src/sound.s), and
; counts a frame each TICKS_PER_FRAME ticks. Other DOC interrupts are only
; acknowledged. Each interrupt ends with the input capture (src/input.s); an
; ADB GLU interrupt runs only the capture and does not touch the DOC. A
; main-loop upload to DOC RAM (src/sound.s) keeps its GLU mode and address:
; they go on the stack and come back.
;
; In:       an IRQ: the DOC (a table end with its interrupt on) or the ADB
;           GLU (a full register whose interrupt is on); any widths, D, DBR
; Out:      clock_step's frequency in the timer, frames_due + 1 at each
;           fourth tick; the work of input_tick, sound_tick, input_capture
; Changes:  clock_fraction, clock_ticks, frames_due; the DOC: the timer's
;           frequency, the interrupt that DOC_IRQ reports acknowledged
; Keeps:    every register (the stack), the GLU state of a main-loop upload
; Time:     a timer tick: about 380 cycles and 16 I/O accesses at the 1 MHz
;           speed (about 150 us), and about 70 cycles and 7 accesses more
;           during a main-loop upload, plus input_tick, sound_tick and
;           input_capture; about 240 ticks a second (4 in each picture). An
;           ADB interrupt: about 110 cycles and 2 accesses, plus
;           input_capture (counted from the 65816 cycle table, the
;           interrupt entry and RTI included)
; Original: none
; ---------------------------------------------------------------------------
clock_irq:
        ax16
        pha
        phx
        phy
        phd
        phb
        lda #SOUND_PAGE
        tcd
        phk
        plb                             ; DBR = bank 0
        a8
; An ADB interrupt (a full GLU register whose interrupt is on): only the
; input capture. A timer interrupt that came at the same time keeps the
; IRQ line low, so it interrupts again at once after the RTI.
        lda f:KMSTATUS
        and #KM_MOUSE_FULL|KM_DATA_FULL
        lsr a                           ; each full bit on its interrupt bit
        and f:KMSTATUS
        beq @pending
        jmp @restored
@pending:
        lda f:SOUNDCTL
        bmi @pending                    ; SOUNDCTL_BUSY
; A main-loop upload in RAM mode: its GLU mode and address go on the stack,
; then the marker 1; else the marker 0.
        bit #SOUNDCTL_RAM
        beq @register_mode
        and #SOUNDCTL_RAM|SOUNDCTL_INC
        ora doc_master
        pha
        lda f:SOUNDADRL
        pha
        lda f:SOUNDADRH
        pha
        lda doc_master
        sta f:SOUNDCTL                  ; register mode
        lda #1
        bra @marked
@register_mode:
        lda #0
@marked:
        pha
; The interrupt register: the first read of SOUNDDATA returns the byte of
; the access before and starts the fetch of DOC_IRQ, which acknowledges the
; oscillator that it reports.
        lda #DOC_IRQ
        sta f:SOUNDADRL
        lda f:SOUNDDATA
@fetch:
        lda f:SOUNDCTL
        bmi @fetch                      ; SOUNDCTL_BUSY: the fetch runs
; The second read returns DOC_IRQ, and it starts one more fetch. The
; address moves to DOC_FREQ_LOW (oscillator 0) first, a register whose read
; changes nothing: a second fetch of DOC_IRQ would acknowledge the next
; waiting oscillator, and its interrupt would be lost.
        lda #DOC_FREQ_LOW
        sta f:SOUNDADRL
        lda f:SOUNDDATA
        cmp #DOC_IRQ_NONE
        bcs @restore                    ; bit 7 set: no oscillator interrupt
        lsr a
        and #DOC_OSCILLATORS - 1        ; the oscillator
        cmp #CLOCK_VOICE
        bne @restore                    ; another oscillator: acknowledged only
; The next pass: F, or F + 1 when the fraction carries.
        a16
        lda clock_fraction
        clc
        adc clock_step_fraction
        sta clock_fraction
        lda clock_step
        adc #0
        a8
        xba
        ldx #DOC_FREQ_HIGH+CLOCK_VOICE
        jsr doc_write                   ; keeps A and B
        xba
        ldx #DOC_FREQ_LOW+CLOCK_VOICE
        jsr doc_write
; The work of a tick, and a frame at each TICKS_PER_FRAME ticks.
        jsl input_tick                  ; src/input.s: the event time and the J13 work
        jsl sound_tick                  ; src/sound.s: the sound of this quarter frame
        inc clock_ticks
        lda clock_ticks
        cmp #TICKS_PER_FRAME
        bcc @restore
        stz clock_ticks
        inc frames_due
; The GLU state of a main-loop upload goes back (the marker 1).
@restore:
        pla
        beq @restored
@ready:
        lda f:SOUNDCTL
        bmi @ready                      ; SOUNDCTL_BUSY
        pla
        sta f:SOUNDADRH
        pla
        sta f:SOUNDADRL
        pla
        sta f:SOUNDCTL
@restored:
        jsl input_capture               ; src/input.s: the ADB bytes, at each interrupt
        ax16
        plb
        pld
        ply
        plx
        pla
        rti
.assert ^clock_irq = 0, error           ; the IRQ vector holds a bank-0 address
.assert KM_MOUSE_FULL >> 1 = KM_MOUSE_IRQ .and KM_DATA_FULL >> 1 = KM_DATA_IRQ, error ; the LSR
.assert SOUNDCTL_BUSY = $80 .and DOC_FREQ_LOW = 0, error ; the BMIs; oscillator 0's register

; ---------------------------------------------------------------------------
; doc_write: write A to the DOC register X, with the interrupts off: the
; GLU in register mode with the owner's volume, the address, the byte.
;
; In:       A8 the value, X16 the DOC register, DBR = 0
; Out:      the DOC register
; Changes:  SOUNDCTL (register mode), SOUNDADRL
; Keeps:    A (with B), X, Y, D, DBR, P
; Time:     50 cycles and 4 I/O accesses, and the JSR (6 cycles)
; Original: none
; ---------------------------------------------------------------------------
.a8
.i16
doc_write:
        php
        sei
        pha
@busy:
        lda f:SOUNDCTL
        bmi @busy                       ; SOUNDCTL_BUSY
        lda doc_master
        sta f:SOUNDCTL                  ; register mode, the owner's volume
        txa
        sta f:SOUNDADRL
        pla
        sta f:SOUNDDATA
        plp
        rts
