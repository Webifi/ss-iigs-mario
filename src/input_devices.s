; The input devices without events: the joystick of the game port (its
; axes timed by the video counter, not by CPU loops) and the two pads of a
; SNES MAX adapter (its protocol: Lukazi's SNES MAX adapter and its example
; code SNES_MAX_ASS5; no slot probe: the slot is a setting). Each sets its
; device key states (set_device, src/input_bindings.s). Part of the input
; (src/input.s), in its scope; input_frame and the menu sample them
; (devices_sample), input_idle reads the joystick axes (devices_idle).
;
; The joystick (Apple IIgs Hardware Reference, chapter 7, the game I/O): a read of
; PTRIG starts the two paddle timers; PADDL0 and PADDL1 keep bit 7 set until
; their timer ends, later for a larger resistance of the stick. A centred
; stick ends between the two thresholds. So two reads tell the three
; positions of an axis: still running at PADDLE_LOW is not left or up; still
; running at PADDLE_HIGH is right or down. The thresholds count VERTCNT
; steps (two 63.6 us lines each), so they do not depend on the CPU speed.
; BUTN0 and BUTN1 are the two buttons.
;
; Routines:
;   devices_sample   the joystick buttons, the pads, the axes once a frame
;   devices_idle     the axes in the main loop's wait, once a frame
;   joy_read         the two axes: the four directions of the joystick
;   joy_check        is a stick there (its timers end)?
;   joy_wait, joy_elapsed  the VERTCNT steps since the trigger
;   pad_read         the two pads of the SNES MAX adapter
PAD_SLOT = 1                 ; the adapter slot until compile_bindings patches the operands
PADDLE_LOW = 8               ; joy_read: the low and high thresholds, in
PADDLE_HIGH = 14             ; VERTCNT steps (two 63.6 us lines each)
PADDLE_ABSENT = 32           ; a stick still high after this is not there
PADDLE_LOW_LATE = 10         ; a read later than this is not used
PADDLE_HIGH_LATE = 16
JOY_READ_NOW = $ffff         ; joyUpdate: read the axes at the next sample
PAD_BITS = 16                ; the bits of one SNES MAX read
PAD_FIRST_BITS = 8           ; the bits of the first byte of a pad (also an NES pad)
PAD_EXTRA_LAST = $08         ; pad_read: the mask after the last extra bit (R)
PAD_RELEASED = $ff           ; a pad byte: the adapter sends 0 for a pressed button
PAD_CLOCK = 1                ; the adapter: SLOT_DEVICE+slot*16: latch and read; +1: clock
PAD_COUNT = 2                ; the pads of the adapter
JOY_AXES = 2                 ; the joystick axes: X, then Y

.a16
.i16
; ---------------------------------------------------------------------------
; devices_sample: one sample of the devices: the joystick buttons (as the
; Apple keys of the J13 switches allow), the pads, and the joystick axes
; once a frame (in the idle time when it came, else here).
;
; Why the button rules: ADB reports the keyboard's own Apple keys, and they
; also set BUTN0 and BUTN1. The J13 keyboard has only the shared switches: a
; bound J13 Apple key belongs to the keyboard; without a binding the switch
; is the joystick's. Both switches held together on that wire look the same.
;
; In:       A16 X16, DBR = this bank
; Out:      the device key states of the joystick and the pads; A16
; Changes:  A, X, Y
; Keeps:    D, DBR
; Time:     about 105 cycles and two button reads with no change and no
;           read; a SNES MAX read about 2,700 cycles more; the axes (when
;           not read in the idle time) 1.78 ms (counted from the 65816
;           cycle table)
; Original: none
; ---------------------------------------------------------------------------
devices_sample:
  ; Button 0: pressed, unless the ADB keyboard's open apple holds it or a
  ; bound J13 open apple owns it.
  a8
  ldx #DEVICE_JOYSTICK+DEV_BUTTON1
  lda f:BUTN0
  bpl @button0_up
  lda a:.loword(keyHeld+KEY_COMMAND)
  and #HELD_ADB                 ; ADB has its own physical key identity
  bne @button0_up
  lda a:.loword(keyHeld+KEY_COMMAND)
  and #HELD_J13
  beq @button0_joy
  lda a:.loword(commandMasks+(KEYBOARD2+KEY_COMMAND)*MASK_SIZE)
  ora a:.loword(commandMasks+(KEYBOARD2+KEY_COMMAND)*MASK_SIZE+1)
  ora a:.loword(commandMasks+(KEYBOARD2+KEY_COMMAND)*MASK_SIZE+2)
  bne @button0_up               ; the J13 key is bound: the keyboard's
@button0_joy:
  lda #1
  bra @button0
@button0_up:
  lda #0
@button0:
  jsr .loword(set_device)
  ; Button 1: the same with option.
  inx                           ; DEV_BUTTON2
  lda f:BUTN1
  bpl @button1_up
  lda a:.loword(keyHeld+KEY_OPTION)
  and #HELD_ADB
  bne @button1_up
  lda a:.loword(keyHeld+KEY_OPTION)
  and #HELD_J13
  beq @button1_joy
  lda a:.loword(commandMasks+(KEYBOARD2+KEY_OPTION)*MASK_SIZE)
  ora a:.loword(commandMasks+(KEYBOARD2+KEY_OPTION)*MASK_SIZE+1)
  ora a:.loword(commandMasks+(KEYBOARD2+KEY_OPTION)*MASK_SIZE+2)
  bne @button1_up
@button1_joy:
  lda #1
  bra @button1
@button1_up:
  lda #0
@button1:
  jsr .loword(set_device)
  ; The pads, when the settings name a slot.
  lda a:.loword(settings+SET_SNES_SLOT)
  beq @no_pad
  jsr .loword(pad_read)
@no_pad:
  ; The axes once a frame: in the idle time when it came, else here.
  lda a:.loword(joyAbsent)
  bne @done
  a16
  lda a:.loword(inputFrames)
  cmp a:.loword(joyUpdate)
  beq @done16
  a8
  jsr .loword(joy_read)
@done:
  a16
@done16:
  rts
.assert DEV_BUTTON2 = DEV_BUTTON1+1, error ; the INX above

; ---------------------------------------------------------------------------
; devices_idle: the joystick axes in the idle time, once a frame. The
; paddles are RC timers: only the two thresholds are read, whatever the CPU
; speed.
;
; In:       A8 X16, DBR = this bank
; Out:      the joystick's direction states; joyUpdate = inputFrames
; Changes:  A, X, Y
; Keeps:    D, DBR, A8 X16
; Time:     31 cycles with no read; with a read 1.78 ms
; Original: none
; ---------------------------------------------------------------------------
.a8
devices_idle:
  lda a:.loword(joyAbsent)
  bne @done
  a16
  lda a:.loword(inputFrames)
  cmp a:.loword(joyUpdate)
  a8
  beq @done                     ; read in this frame already
  jsr .loword(joy_read)
@done:
  rts

; ---------------------------------------------------------------------------
; joy_read: start the paddle timers; at PADDLE_LOW read both paddles, at
; PADDLE_HIGH both; a read too late (an interrupt in the wait) keeps the
; directions before. Both axes still high at PADDLE_HIGH: right and down
; from a stick that is known to be there, and the next read checks it first
; (joy_check); before that, joy_check waits for the stick at once. Then the
; four directions of the joystick.
;
; In:       A8 X16, DBR = this bank
; Out:      the four direction states of the joystick; joyUpdate = inputFrames
; Changes:  A, X, Y; joyBeam, joyLowX, joyLowY, joyHighX, joyHighY,
;           joyCheck, joyPresent, joyAbsent
; Keeps:    D, DBR, A8 X16
; Time:     1.78 ms at most: PADDLE_HIGH VERTCNT steps of 127 us from the
;           trigger; the first check of an absent stick waits PADDLE_ABSENT
;           steps (4.1 ms)
; Original: none
; ---------------------------------------------------------------------------
joy_read:
  ; A check that the last read asked for: no stick, no read.
  lda a:.loword(joyCheck)
  beq @start
  stz a:.loword(joyCheck)
  jsr .loword(joy_check)
  bcc @start
  jmp .loword(@stamp)           ; no stick
@start:
  ; The trigger, then both timers at PADDLE_LOW and at PADDLE_HIGH. Each
  ; read is made with the interrupts off, right after its step check, and a
  ; read later than the _LATE step is not used.
  lda f:VERTCNT
  sta a:.loword(joyBeam)
  lda f:PTRIG                   ; the paddle timers start
  lda #PADDLE_LOW
  jsr .loword(joy_wait)
  php
  sei
  jsr .loword(joy_elapsed)
  cmp #PADDLE_LOW_LATE
  bcc :+
  plp
  jmp .loword(@stamp)
:
  lda f:PADDL0
  sta a:.loword(joyLowX)
  lda f:PADDL1
  sta a:.loword(joyLowY)
  plp
  lda #PADDLE_HIGH
  jsr .loword(joy_wait)
  php
  sei
  jsr .loword(joy_elapsed)
  cmp #PADDLE_HIGH_LATE
  bcc :+
  plp
  jmp .loword(@stamp)
:
  lda f:PADDL0
  sta a:.loword(joyHighX)
  lda f:PADDL1
  sta a:.loword(joyHighY)
  plp
  lda a:.loword(joyHighX)
  and a:.loword(joyHighY)
  bpl @connected
  ; Both axes high past the high threshold: right and down, or no stick.
  lda a:.loword(joyPresent)
  beq :+
  inc a:.loword(joyCheck)
  bra @connected
:
  jsr .loword(joy_check)
  bcs @stamp
@connected:
  ; Right and down: still high at PADDLE_HIGH; left and up: low at PADDLE_LOW.
  ldx #DEVICE_JOYSTICK+DEV_RIGHT
  ldy #0                        ; X axis, then Y axis
@axis:
  lda a:.loword(joyHighX),y
  asl a
  lda #0
  rol a
  jsr .loword(set_device)       ; DEV_RIGHT, DEV_DOWN
  inx
  lda a:.loword(joyLowX),y
  eor #$80
  asl a
  lda #0
  rol a
  jsr .loword(set_device)       ; DEV_LEFT, DEV_UP
  inx
  iny
  cpy #JOY_AXES
  bcc @axis
@stamp:
  a16
  lda a:.loword(inputFrames)
  sta a:.loword(joyUpdate)
  a8
  rts
.assert DEV_RIGHT = 0 .and DEV_LEFT = 1 .and DEV_DOWN = 2 .and DEV_UP = 3, error ; the axis loop order
.assert joyLowY = joyLowX+1 .and joyHighY = joyHighX+1, error

; ---------------------------------------------------------------------------
; joy_check: both axes stayed high to PADDLE_HIGH in the read that started at
; joyBeam. A stick ends its timers by PADDLE_ABSENT; a missing stick never
; does. Timers that ended already need no wait. Carry clear: the stick is
; there (joyPresent). Carry set: no stick (joyAbsent): no more reads, and
; the joystick's direction keys are let go.
;
; In:       A8 X16, DBR = this bank
; Out:      carry; joyPresent or joyAbsent
; Changes:  A, X; joyThreshold
; Keeps:    Y, D, DBR, A8 X16
; Time:     with the timers still running, PADDLE_ABSENT steps from the
;           trigger (4.1 ms)
; Original: none
; ---------------------------------------------------------------------------
joy_check:
  lda f:PADDL0
  and f:PADDL1
  bpl @there
  lda #PADDLE_ABSENT
  jsr .loword(joy_wait)
  lda f:PADDL0
  and f:PADDL1
  bmi @absent
@there:
  lda #1
  sta a:.loword(joyPresent)
  clc
  rts
@absent:
  lda #1
  sta a:.loword(joyAbsent)      ; no more axis reads (RECHECK JOYSTICK clears it)
  ldx #DEVICE_JOYSTICK
  lda #0
@release:
  jsr .loword(set_device)
  inx
  cpx #DEVICE_JOYSTICK+DEV_BUTTON1
  bcc @release
  sec
  rts

; ---------------------------------------------------------------------------
; joy_wait: wait until A VERTCNT steps have passed since joyBeam. The
; interrupts stay on in the wait.
;
; In:       A8 the steps, X16, DBR = this bank; joyBeam, beamPeriod
; Out:      A8 the steps since joyBeam
; Changes:  A; joyThreshold
; Keeps:    X, Y, D, DBR
; Time:     the steps asked for, 127 us each
; Original: none
; ---------------------------------------------------------------------------
joy_wait:
  sta a:.loword(joyThreshold)
@wait:
  jsr .loword(joy_elapsed)
  cmp a:.loword(joyThreshold)
  bcc @wait
  rts
; ---------------------------------------------------------------------------
; joy_elapsed: A = the VERTCNT steps since joyBeam; VERTCNT wraps at
; beamPeriod, the steps of a picture of the video standard.
;
; In:       A8, DBR = this bank; joyBeam, beamPeriod
; Out:      A8 the steps
; Changes:  A
; Keeps:    X, Y, D, DBR
; Time:     about 20 cycles and one VERTCNT read
; Original: none
; ---------------------------------------------------------------------------
joy_elapsed:
  lda f:VERTCNT
  sec
  sbc a:.loword(joyBeam)
  bcs :+
  clc
  adc a:.loword(beamPeriod)
:
  rts

; ---------------------------------------------------------------------------
; pad_read: read the SNES MAX adapter in the slot of the settings (the card
; has no ROM to find): a write of SLOT_DEVICE + slot * 16 latches the pads,
; a read there gives the next bit of both pads (bit 7 pad one, bit 6 pad
; two; 0 = pressed), a write of the next address clocks both pads. PAD_BITS
; bits each: the first 8 (also those of an NES pad) to the device keys 0-7,
; bits 8-11 (A, X, L, R of a SNES pad) to the device keys 8-11.
;
; Self-changing code: compile_bindings patches the low byte of the
; addresses of pad_latch, pad_data and pad_clock with the slot.
;
; In:       A8 X16, DBR = this bank
; Out:      the device key states of DEVICE_PAD1 and DEVICE_PAD2
; Changes:  A, X, Y; padBits, padSerial, padPressed, padMask
; Keeps:    D, DBR, A8 X16
; Time:     about 2,700 cycles and 33 slot accesses with no button change
;           (counted from the 65816 cycle table)
; Original: none
; ---------------------------------------------------------------------------
pad_read:
  ; Latch the pads, then PAD_BITS bits: each read gives bit 7 of pad one
  ; and bit 6 of pad two; a write of the next address clocks the next bit.
  stz a:.loword(padBits)
  stz a:.loword(padBits+1)
  stz a:.loword(padBits+2)
  stz a:.loword(padBits+3)
  lda #0
pad_latch:
  sta f:SLOT_DEVICE+PAD_SLOT*SLOT_DEVICE_SIZE ; the slot is patched: latch the pads
  ldx #0
pad_bit:
  cpx #PAD_FIRST_BITS           ; bits 8-15 go to padBits+2
  bcc @first
  ldy #2
  bra @read
@first:
  ldy #0
@read:
pad_data:
  lda f:SLOT_DEVICE+PAD_SLOT*SLOT_DEVICE_SIZE ; the slot is patched: bit 7 pad one, bit 6 pad two
  sta a:.loword(padSerial)
  asl a
  lda a:.loword(padBits),y
  rol a
  sta a:.loword(padBits),y
  lda a:.loword(padSerial)
  asl a
  asl a
  lda a:.loword(padBits+1),y
  rol a
  sta a:.loword(padBits+1),y
pad_clock:
  sta f:SLOT_DEVICE+PAD_SLOT*SLOT_DEVICE_SIZE+PAD_CLOCK ; the slot is patched: the next bit
  inx
  cpx #PAD_BITS
  bcc pad_bit
  ; The first byte of each pad: bit n is device key n (0-7), the last bit
  ; read in bit 0.
  ldx #0
@pad:
  lda a:.loword(padBits),x
  eor #PAD_RELEASED             ; pressed = 1
  sta a:.loword(padPressed)
  txa
  beq :+
  lda #DEVICE_PAD2-DEVICE_PAD1
:
  clc
  adc #DEVICE_PAD1
  tay
  lda #1
  sta a:.loword(padMask)
@button:
  lda a:.loword(padPressed)
  and a:.loword(padMask)
  beq :+
  lda #1
:
  phx
  tyx
  jsr .loword(set_device)
  plx
  iny
  asl a:.loword(padMask)
  bne @button
  inx
  cpx #PAD_COUNT
  bcc @pad
  ; The second byte of each pad: A, X, L, R in its top bits, the first one
  ; read in bit 7: device keys 8-11.
  ldx #0
@extra:
  lda a:.loword(padBits+2),x
  eor #PAD_RELEASED
  sta a:.loword(padPressed)
  txa
  beq :+
  lda #DEVICE_PAD2-DEVICE_PAD1
:
  clc
  adc #DEVICE_PAD1+DEV_PAD_A
  tay
  lda #$80
  sta a:.loword(padMask)
@extra_bit:
  lda a:.loword(padPressed)
  and a:.loword(padMask)
  beq :+
  lda #1
:
  phx
  tyx
  jsr .loword(set_device)
  plx
  iny
  lsr a:.loword(padMask)
  lda a:.loword(padMask)
  cmp #PAD_EXTRA_LAST
  bne @extra_bit
  inx
  cpx #PAD_COUNT
  bcc @extra
  rts
.assert DEV_PAD_A = PAD_FIRST_BITS .and DEV_PAD_R = DEV_PAD_A+3, error

; The device state.
joyUpdate: .word JOY_READ_NOW   ; inputFrames of the last axis read (JOY_READ_NOW: at the next sample)
joyAbsent: .byte 0              ; 1: no stick: no axis reads
joyPresent: .byte 0             ; joy_check saw the timers of the stick end
joyCheck: .byte 0               ; joy_read: both axes stayed high; check the stick first
joyBeam: .byte 0                ; VERTCNT at the trigger
joyThreshold: .byte 0           ; joy_wait: the steps to wait for
joyLowX: .byte 0                ; PADDL0 at PADDLE_LOW (joy_read indexes X, then Y)
joyLowY: .byte 0                ; PADDL1 at PADDLE_LOW
joyHighX: .byte 0               ; PADDL0 at PADDLE_HIGH
joyHighY: .byte 0               ; PADDL1 at PADDLE_HIGH
beamPeriod: .byte NTSC_BEAM_PERIOD ; VERTCNT steps of a picture (defaults sets PAL_BEAM_PERIOD at 50 Hz)
padSerial: .byte 0              ; pad_read: the adapter byte of this bit
padBits: .res 4                 ; the bits of pad one, pad two (byte 0-1), then of their second bytes
padPressed: .byte 0             ; the byte in work, 1 = pressed
padMask: .byte 0                ; the bit in work
