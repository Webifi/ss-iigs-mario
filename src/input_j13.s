; Read the J13 keyboard used by ROM 00 and ROM 01 IIgs machines.
; input.s calls these routines to capture presses and releases. J13 is the
; internal keyboard connector; the Apple Desktop Bus (ADB) microcontroller
; scans it. The keyboard GLU is the interface used to send commands and read
; replies from that microcontroller.
;
; The keyboard registers expose the last character and whether a key is
; down, not the state of every held key. When several keys are held, this
; code reads switch rows from a recognized microcontroller ROM to identify
; releases. The clock tick sends the request and input capture takes the
; reply; the GLU is reserved for that read until the reply or timeout.

.a16
.i16
NONE = 255                   ; no key identity (j13Keys, keyAction)
ROMVER_J13_END = 2           ; ROMVER: the J13 keyboard on ROM 00 and 01 only
GLU_WAIT = 16384             ; sendBounded, readBounded: the most status reads
INIT_DRAIN_MAX = 256         ; J13Init: the most DATAREG bytes of the boot to drop
; The microcontroller (the ROM of the ROM 00 and ROM 01 keyboard
; microcontroller, Apple 341-0345, at $1400): its scanner at $18AC reads
; the MCU_ROWS switch rows and keeps them in its RAM from MCU_ROW_FIRST, one
; bit for each switch, 0 while it is down; the routine at $1A10 updates
; them. Its port P3 (RAM address MCU_P3) holds the shift, control and caps
; lock switches, 0 while down. The code checks SIGNATURE_PART bytes at each
; of the two routines (matrixROM) before it reads a row. A command of
; GLU_READ_MEMORY returns one byte (Firmware Reference, chapter 9).
;
MCU_SIGNATURE1 = $18ac       ; the microcontroller ROM: SIGNATURE_PART bytes at
MCU_SIGNATURE2 = $1a10       ; each address must be equal to matrixROM
SIGNATURE_PART = 32
MCU_P3 = $e8                 ; the microcontroller RAM: port 3, the modifier switches
P3_LOW_BITS = KMOD_SHIFT|KMOD_CONTROL|KMOD_CAPS  ; P3: these bits are 0 when down
MCU_ROW_FIRST = $31          ; the microcontroller RAM: the switch rows
MCU_ROWS = 10
MATRIX_KEYS = 64             ; pumpRows, pumpMasks: the identities below this
J13_KEY_SLOTS = 3            ; j13Keys: the most held key identities
ROW_KEYS = 2                 ; knownCount: from this count a release needs the row reads
                             ; (KBDSTRB gives the release of a single key)
QUEUE_ROOM = 10              ; J13Sample: the free events it needs (five
                             ; modifiers, three releases, a release and press)
ROW_WAKES = 2                ; deferRows: the DOC ticks before the row batch
ROW_GAP = 7                  ; inputClock ticks from one row batch to the next: more than
                             ; a frame's 4, so a batch comes at most every second frame
ROW_TIMEOUT = 239            ; inputClock ticks: a longer batch stops the row reads
RECOVER_WAIT = 7             ; inputClock ticks before a lost character is read again
SEND_BUDGET = 16             ; sendAlarm calls for P3 and up to three rows
FINISH_TRIES = 16384         ; finishOwner: J13Pump steps before the row reads stop
TRANSITION_TRIES = 1024      ; readTransition: ADB captures before it stops
NOTICE_MAX = 16              ; the most ADB status bytes before a reply
MODIFIER_KEYS = 5            ; modifierMasks, modifierKeys
NO_FRAME = $ffff             ; rowFrame, rowArmFrame, maskGeneration: not yet
ASCII_ESC = $1b
; j13State: the steps of a row read.
JS_IDLE = 0
JS_ARMED = 1                 ; J13Pump takes the GLU when it is free
JS_ADDRESS = 2               ; GLU_READ_MEMORY went out: next the address
JS_HIGH = 3                  ; next the high byte of the address
JS_REPLY = 4                 ; the reply comes in the capture

; ---------------------------------------------------------------------------
; J13Init: on a ROM 00 or ROM 01 machine: empty the GLU, check that it
; answers, probe the ADB keyboard, set the key buffer and stop the firmware
; key repeat, then compare the microcontroller ROM with matrixROM: when
; equal, the row reads work (j13Matrix).
;
; In:       any widths; interrupts off (input_start)
; Out:      j13Available, j13AdbPresent, j13Matrix; the GLU modes
; Changes:  A, X, Y; keyboardConfig; captureTalk (probeADB)
; Keeps:    DBR, D, the widths
; Time:     once, at the start
; Original: none
; ---------------------------------------------------------------------------
J13Init:
  php
  sei
  ax16
  phb
  phk
  plb
  a8
  lda f:ROMVER
  cmp #ROMVER_J13_END
  bcs initDone                  ; ROM 03: no J13 keyboard
  lda #1
  sta a:.loword(j13Available)
  ; The bytes of the boot in DATAREG, dropped; too many: the GLU is not
  ; there to talk to.
  ldy #INIT_DRAIN_MAX
@drain:
  lda f:KMSTATUS
  and #KM_DATA_FULL
  beq @modes
  lda f:DATAREG
  dey
  bne @drain
  bra initDone
@modes:
  ; The GLU answers; the ADB keyboard, the key buffer, no firmware repeat;
  ; then the two signatures of the microcontroller ROM.
  lda #GLU_READ_MODES            ; the GLU answers
  jsr .loword(sendBounded)
  bcs initDone
  jsr .loword(readBounded)
  bcs initDone
  jsr .loword(probeADB)
  jsr .loword(bufferKeyboard)
  ldx #0
@signature:
  phx
  a16
  txa
  cpx #SIGNATURE_PART
  bcs @second
  clc
  adc #MCU_SIGNATURE1
  bra @address
@second:
  clc
  adc #MCU_SIGNATURE2-SIGNATURE_PART
@address:
  tax
  a8
  jsr .loword(readMCU)
  plx
  bcs initDone
  cmp f:matrixROM,x
  bne initDone
  inx
  cpx #2*SIGNATURE_PART
  bcc @signature
  lda #1
  sta a:.loword(j13Matrix)      ; the known ROM: the row reads work
initDone:
  ax16
  plb
  plp
  rtl

; ---------------------------------------------------------------------------
; J13Prime: empty the key buffer, take the current KBDSTRB and KBD state as
; known, then J13_MENU.
;
; In:       any widths; interrupts off (input_start)
; Out:      sampleAKD, j13LastAscii, j13Mode
; Changes:  A, Y
; Keeps:    X, D, DBR, the widths
; Time:     once, at the start
; Original: none
; ---------------------------------------------------------------------------
J13Prime:
  php
  sei
  ax16
  phb
  phk
  plb
  lda a:.loword(j13Available)
  beq @done
  a8
  lda #GLU_FLUSH_KEYS
  jsr .loword(sendBounded)
  lda f:KBDSTRB
  sta a:.loword(sampleAKD)
  lda f:KBD
  and #<~KBD_STROBE
  sta a:.loword(j13LastAscii)
  a16
  lda #J13_MENU
  sta a:.loword(j13Mode)
@done:
  plb
  plp
  rtl

; ---------------------------------------------------------------------------
; J13Menu: setMode with J13_MENU (the options menu opens, src/menu.s). It
; falls through into setMode.
;
; In:       A16; any X width; JSL
; Out:      j13Mode = J13_MENU
; Changes:  the J13 state (setMode)
; Keeps:    A, X, Y, D, DBR, the widths
; Original: none
; ---------------------------------------------------------------------------
J13Menu:
  .a16
  lda #J13_MENU
  ; Falls through into setMode.

; ---------------------------------------------------------------------------
; setMode: j13Mode = A, outside a timed frame; an owned read ends first. A
; change to J13_ESCAPE, or from it, forgets the held keys; from J13_MENU to
; J13_PLAY or back they stay, and J13_PLAY checks them
; (J13ValidateTracked).
;
; In:       A16 the mode; any X width; JSL (src/input.s input_sample)
; Out:      j13Mode
; Changes:  the J13 state: j13NextMode, rowWakeBudget, j13SendTimer, the
;           held identities
; Keeps:    A, X, Y, D, DBR, the widths
; Time:     only at a change of the mode; J13ValidateTracked reads a row
;           for each held key
; Original: none
; ---------------------------------------------------------------------------
setMode:
  php
  sei
  ax16
  pha
  phx
  phy
  phb
  phk
  plb
  lda a:.loword(j13Available)
  beq @done
  lda 6,s                       ; the mode, below B, Y and X
  sta a:.loword(j13NextMode)
  jsr .loword(finishOwner)
  stz a:.loword(rowWakeBudget)
  stz a:.loword(j13SendTimer)
  lda a:.loword(j13NextMode)
  beq @clear                    ; to J13_ESCAPE
  lda a:.loword(j13Mode)
  bne @keep                     ; not from J13_ESCAPE
@clear:
  jsr .loword(clearHeld)
@keep:
  lda a:.loword(j13NextMode)
  sta a:.loword(j13Mode)
  cmp #J13_PLAY
  bne @done
  jsr .loword(J13ValidateTracked)
@done:
  plb
  ply
  plx
  pla
  plp
  rtl

; ---------------------------------------------------------------------------
; J13SettingsLoad: j13Enabled, j13Manual and j13MenuSeen from SET_J13. A
; choice by hand counts as a menu use; an untouched default can still turn
; on at the first menu use (menuUsed). J13 play needs a J13 keyboard.
;
; In:       A16; JSL (src/input_settings.s defaults)
; Out:      j13Enabled, j13Manual, j13MenuSeen
; Changes:  A
; Keeps:    X, Y, D, DBR
; Original: none
; ---------------------------------------------------------------------------
J13SettingsLoad:
  .a16
  lda f:settings+SET_J13
  and #J13_ON
  and f:j13Available
  sta f:j13Enabled
  lda f:settings+SET_J13
  and #J13_CHOSEN
  sta f:j13Manual
  sta f:j13MenuSeen
  rtl

; ---------------------------------------------------------------------------
; J13SettingsStore: SET_J13 from j13Enabled and j13Manual.
;
; In:       A16; JSL (src/input_disk.s settings_save, src/menu.s)
; Out:      settings+SET_J13
; Changes:  A
; Keeps:    X, Y, D, DBR, A16
; Original: none
; ---------------------------------------------------------------------------
J13SettingsStore:
  lda f:j13Enabled
  ora f:j13Manual
  a8
  sta f:settings+SET_J13
  a16
  rtl

; ---------------------------------------------------------------------------
; J13Poll: the J13 work of a sample in the menu or the title (never in
; J13_PLAY, so no row read): J13_ESCAPE looks only for ESC (escapeSample);
; J13_MENU reads the keys (J13Sample).
;
; In:       A16 X16; JSL (src/input.s input_sample)
; Out:      J13 events in inputRing
; Changes:  A, X, Y
; Keeps:    D, DBR, the widths, the interrupt flag
; Time:     about 75 cycles and one KBD read in J13_ESCAPE with no
;           character; in J13_MENU about 55 and J13Sample (counted from the
;           65816 cycle table)
; Original: none
; ---------------------------------------------------------------------------
J13Poll:
  php
  sei
  ax16
  phb
  phk
  plb
  lda a:.loword(j13Available)
  beq @done
  lda a:.loword(j13Mode)
  beq @escape
  jsr .loword(J13Sample)
  bra @done
@escape:
  jsr .loword(escapeSample)
@done:
  plb
  plp
  rtl

; ---------------------------------------------------------------------------
; J13Frame: the J13 work of a play sample: the keys, the row batch (at once
; or after ROW_WAKES DOC ticks) and a service step.
;
; In:       A16 X16; JSL (src/input.s input_sample, J13_PLAY)
; Out:      J13 events in inputRing
; Changes:  A, X, Y; controllerTime
; Keeps:    D, DBR, the widths, the interrupt flag
; Time:     about 275 cycles and three I/O reads with no key held (J13Sample
;           included; counted from the 65816 cycle table); a key event about
;           100 more each (queue)
; Original: none
; ---------------------------------------------------------------------------
J13Frame:
  php
  sei
  phb
  phk
  plb
  lda a:.loword(inputClock)
  sta a:.loword(controllerTime)
  jsr .loword(J13Sample)
  jsr .loword(deferRows)
  jsr .loword(serviceController)
  plb
  plp
  rtl

; ---------------------------------------------------------------------------
; readControllerClock: controllerTime = inputClock, the time of the
; service and of the row reads.
;
; In:       A16, DBR = this bank
; Out:      A16 = controllerTime = inputClock
; Changes:  A
; Keeps:    X, Y, D, DBR
; Time:     17 cycles
; Original: none
; ---------------------------------------------------------------------------
readControllerClock:
  lda a:.loword(inputClock)
  sta a:.loword(controllerTime)
  rts

; ---------------------------------------------------------------------------
; escapeSample: in J13_ESCAPE an ESC character becomes an ESC press and
; release (the menu opens); it is a menu use too.
;
; In:       A16 X16, DBR = this bank, interrupts off
; Out:      the ESC events; KBDSTRB read (the strobe cleared); A16
; Changes:  A; sampleTimed, sampleTime; j13MenuSeen, j13Enabled (menuUsed)
; Keeps:    X, Y, D, DBR
; Time:     about 20 cycles and one KBD read with no character
; Original: none
; ---------------------------------------------------------------------------
escapeSample:
  a8
  lda f:KBD
  bpl @done                     ; no character
  pha
  lda f:KBDSTRB
  pla
  cmp #ASCII_ESC|KBD_STROBE
  bne @done
  a16
  jsr .loword(queueRoom)
  bcc @done
  jsr .loword(menuUsed)
  stz a:.loword(sampleTimed)
  lda #KEY_ESC
  jsr .loword(queue)
  lda #KEY_ESC|KEY_RELEASE
  jsr .loword(queue)
@done:
  a16
  rts

; ---------------------------------------------------------------------------
; j13Irq: the DOC tick in J13_PLAY: the keys, and at the last of the
; ROW_WAKES ticks of deferRows the row batch.
;
; In:       A16 X16, DBR = this bank (input_tick, interrupts off)
; Out:      J13 events; the row read armed
; Changes:  A, X, Y; rowWakeBudget
; Keeps:    D, DBR, A16 X16
; Time:     about 125 cycles and three I/O reads with no key and no batch
;           (J13Sample included); at a batch scheduleRow and J13Pump more;
;           at each DOC tick in J13_PLAY
; Original: none
; ---------------------------------------------------------------------------
j13Irq:
  jsr .loword(J13Sample)
  lda a:.loword(rowWakeBudget)
  beq @done
  dec a:.loword(rowWakeBudget)
  bne @done
  jsr .loword(scheduleRow)
  jsr .loword(J13Pump)
@done:
  rts

; ---------------------------------------------------------------------------
; J13Sample: one sample of the J13 keyboard. It needs QUEUE_ROOM free
; events, else it waits for the next sample. A character: the modifier
; changes, then the press of its identity. No character: the modifier
; changes from KEYMODREG, and when KBDSTRB shows no key down the release of
; the held identities.
;
; The parts after the character's first reads are sampleModifiers and
; sampleCharacter below; they end in sampleRelease.
;
; In:       A16 X16, DBR = this bank, interrupts off
; Out:      J13 events; sampleAscii, sampleMods, sampleAKD, j13LastAscii,
;           sampleRecover, recoverTime, physicalValid, j13Mods; A16
; Changes:  A, X, Y; nextMods, newKey, sampleTimed, sampleTime; the held
;           identities
; Keeps:    D, DBR
; Time:     about 105 cycles and three I/O reads (KBD, KBDSTRB, KEYMODREG)
;           with no key; about 90 and two reads with a key held in
;           J13_PLAY; each event about 100 more (queue) (counted from the
;           65816 cycle table); at each DOC tick in J13_PLAY, at each
;           sample in J13_MENU
; Original: none
; ---------------------------------------------------------------------------
J13Sample:
  .a16
  lda f:inputHead
  cmp f:inputTail
  beq @room                     ; the ring is empty
  jsr .loword(queueRoom)
  bcs @room
  rts
@room:
  ; A character: KBD with its strobe (bit 7), or a KBD byte that is not the
  ; last character: a character whose strobe a KBDSTRB read cleared too
  ; soon (KBD keeps the byte).
  a8
  lda f:KBD
  bmi sampleFresh
  cmp a:.loword(j13LastAscii)
  beq sampleSlowHeld
  .a8
  ora #KBD_STROBE
sampleFresh:
  sta a:.loword(sampleAscii)
  stz a:.loword(sampleRecover)
  .a8
  and #<~KBD_STROBE
  sta a:.loword(j13LastAscii)
  ; The modifiers of the character, before the KBDSTRB read clears it.
  lda f:KEYMODREG
  sta a:.loword(sampleMods)
sampleMetadata:
  lda f:KBDSTRB
  sta a:.loword(sampleAKD)
  jsr .loword(readModifiers)
  stz a:.loword(sampleTimed)
  jmp .loword(sampleModifiers)
sampleSlowHeld:
  ; The same character: is a key still down (KBDSTRB)?
  .a8
  sta a:.loword(sampleAscii)
  ldx a:.loword(sampleAKD)
  lda f:KBDSTRB
  sta a:.loword(sampleAKD)
  bpl sampleUpCheck
  txa
  bmi sampleDownKnown
  ; Down with no character: the strobe can have raced a KBDSTRB read.
  lda #1
  sta a:.loword(sampleRecover)
  a16
  jsr .loword(readControllerClock)
  clc
  adc #RECOVER_WAIT
  sta a:.loword(recoverTime)
  a8
  bra sampleHeld
sampleDownKnown:
  ldx a:.loword(sampleRecover)
  bne sampleRecovery
sampleHeld:
  ; With a key held, the P3 reads give the live modifiers; no character
  ; means no work here.
  a16
  lda a:.loword(j13Mode)
  cmp #J13_PLAY
  bne @live
  lda a:.loword(physicalValid)
  beq @live
  rts
@live:
  a8
sampleIdleModifiers:
  .a8
  lda f:KEYMODREG
  ; KBDSTRB can clear before KEYMODREG stops showing the last character;
  ; KMOD_LATCH marks a change of the modifiers alone.
  bit #KMOD_LATCH
  bne @latch
  a16
  jmp .loword(sampleRelease)
@latch:
  stz a:.loword(physicalValid)
  sta a:.loword(sampleMods)
  jsr .loword(readModifiers)
  cmp a:.loword(j13Mods)
  beq @same
  stz a:.loword(sampleTimed)
  jsr .loword(updateModifiers)
@same:
  jmp .loword(sampleRelease)
sampleUpCheck:
  ldx a:.loword(sampleRecover)
  beq sampleIdleModifiers
sampleRecovery:
  ; KBDSTRB can rise before the microcontroller writes the character; a
  ; KBDSTRB read then can clear the later strobe, also for the same
  ; character. After RECOVER_WAIT, read the character when KEYMODREG shows
  ; it (KMOD_LATCH 0), or when the key is up again (the tap is complete).
  a16
  jsr .loword(readControllerClock)
  sec
  sbc a:.loword(recoverTime)
  a8
  bmi sampleHeld
  lda f:KEYMODREG
  bit #KMOD_LATCH
  beq @recovered
  bit a:.loword(sampleAKD)
  bmi sampleHeld
@recovered:
  ; The modifiers first: the microcontroller can write the character
  ; during the KBDSTRB read before.
  and #<~KMOD_REPEAT
  sta a:.loword(sampleMods)
  lda f:KBD
  .a8
  ora #KBD_STROBE
  sta a:.loword(sampleAscii)
  .a8
  and #<~KBD_STROBE
  sta a:.loword(j13LastAscii)
  stz a:.loword(sampleRecover)
  jmp .loword(sampleMetadata)

; ---------------------------------------------------------------------------
; readModifiers: A = nextMods = the KMOD_KEYS bits of sampleMods, with the
; Apple keys from BUTN0 and BUTN1 (the J13 Apple keys are those wires).
;
; In:       A8, DBR = this bank; sampleMods
; Out:      A16 = nextMods
; Changes:  A; nextMods
; Keeps:    X, Y, D, DBR
; Time:     about 40 cycles and two button reads
; Original: none
; ---------------------------------------------------------------------------
readModifiers:
  lda a:.loword(sampleMods)
  .a8
  and #KMOD_KEYS
  sta a:.loword(nextMods)
  lda f:BUTN0
  bpl @option
  lda a:.loword(nextMods)
  .a8
  ora #KMOD_COMMAND
  sta a:.loword(nextMods)
@option:
  lda f:BUTN1
  bpl @done
  lda a:.loword(nextMods)
  ora #KMOD_OPTION
  sta a:.loword(nextMods)
@done:
  a16
  lda a:.loword(nextMods)
  rts

; ---------------------------------------------------------------------------
; sampleModifiers: a part of J13Sample, for a character. In J13_PLAY a
; firmware repeat (KMOD_REPEAT) keeps the modifiers of P3, or the ones
; before: KEYMODREG can be wrong then. Then the modifier changes
; (updateModifiers), and the character (sampleCharacter).
;
; In:       A16 X16, DBR = this bank; nextMods, sampleMods (J13Sample)
; Out:      the events of the modifiers and of the character
; Changes:  A, X, Y (as J13Sample)
; Original: none
; ---------------------------------------------------------------------------
sampleModifiers:
  lda a:.loword(j13Mode)
  .a16
  cmp #J13_PLAY
  bne @update
  lda a:.loword(sampleMods)
  bit #KMOD_REPEAT
  beq @update
  lda a:.loword(physicalValid)
  beq @before
  lda a:.loword(physicalMods)
  bra @keep
@before:
  lda a:.loword(j13Mods)
@keep:
  sta a:.loword(nextMods)
@update:
  jsr .loword(updateModifiers)
  bra sampleCharacter

; ---------------------------------------------------------------------------
; updateModifiers: an event for each modifier key whose bit is not the same
; in j13Mods and nextMods; then j13Mods = nextMods.
;
; In:       A16 X16, DBR = this bank; nextMods; the room in inputRing
; Out:      the modifier events; j13Mods
; Changes:  A, X
; Keeps:    Y, D, DBR
; Time:     about 20 cycles with no change; else about 170, and about 130
;           for each changed key (queue)
; Original: none
; ---------------------------------------------------------------------------
updateModifiers:
  lda a:.loword(nextMods)
  cmp a:.loword(j13Mods)
  bne @changed
  rts
@changed:
  ldx #0
@modifier:
  lda a:.loword(nextMods)
  eor a:.loword(j13Mods)
  and f:modifierMasks,x
  and #$00ff
  beq @next
  lda a:.loword(nextMods)
  and f:modifierMasks,x
  and #$00ff
  beq @up
  lda f:modifierKeys,x
  and #$00ff
  bra @queue
@up:
  lda f:modifierKeys,x
  and #$00ff
  ora #KEY_RELEASE
@queue:
  jsr .loword(queue)
@next:
  inx
  cpx #MODIFIER_KEYS
  bcc @modifier
  lda a:.loword(nextMods)
  sta a:.loword(j13Mods)
  rts

; ---------------------------------------------------------------------------
; sampleCharacter: a part of J13Sample: a character that is not a firmware
; repeat gives the press of its identity (asciiKeys; a keypad key:
; keypadKeys). In J13_MENU the first key is a menu use while the menu shows
; (on the title only ESC is), and the held keys are checked first. Then
; sampleRelease: no key down (KBDSTRB) releases the held identities.
;
; In:       A16 X16, DBR = this bank; sampleAscii, sampleMods, sampleAKD
; Out:      the press and release events
; Changes:  A, X, Y; newKey, validateIncoming (as J13Sample)
; Original: none
; ---------------------------------------------------------------------------
sampleCharacter:
  lda a:.loword(sampleAscii)
  bit #KBD_STROBE
  beq sampleRelease
  lda a:.loword(sampleMods)
  bit #KMOD_REPEAT              ; a firmware repeat is not a press
  bne sampleRelease
  lda a:.loword(sampleAscii)
  and #<~KBD_STROBE
  tax
  lda a:.loword(sampleMods)
  bit #KMOD_KEYPAD              ; a keypad key keeps its own ADB code
  beq :+
  cpx #KEYPAD_CHARS
  bcs :+
  lda f:keypadKeys,x
  bra :++
:
  lda f:asciiKeys,x
:
  and #$00ff
  cmp #NONE
  beq sampleRelease
  sta a:.loword(newKey)
  lda a:.loword(j13Mode)
  .a16
  cmp #J13_MENU
  bne sampleOrdinary
  lda a:.loword(j13MenuSeen)
  bne sampleMenuOrdinary
  lda f:menuMode                ; the menu shows: any key is a menu use
  bne sampleMenuUsed
  lda a:.loword(newKey)         ; the title: only ESC (it opens the menu)
  cmp #KEY_ESC
  bne sampleMenuOrdinary
sampleMenuUsed:
  jsr .loword(menuUsed)
sampleMenuOrdinary:
  lda #1
  sta a:.loword(validateIncoming)
  jsr .loword(J13ValidateTracked)
  stz a:.loword(validateIncoming)
sampleOrdinary:
  jsr .loword(ordinaryDown)
sampleRelease:
  lda a:.loword(sampleAKD)
  bit #KBD_STROBE               ; KBDSTRB: a key is down
  bne @done
  lda a:.loword(knownCount)
  beq @done
  stz a:.loword(sampleTimed)
  jsr .loword(releaseOrdinary)
@done:
  rts

; ---------------------------------------------------------------------------
; menuUsed: the first menu use turns J13 play on (j13MenuSeen), unless the
; player chose by hand before (J13SettingsLoad sets j13MenuSeen then).
;
; In:       A16, DBR = this bank
; Out:      j13MenuSeen, j13Enabled
; Changes:  A
; Keeps:    X, Y, D, DBR
; Original: none
; ---------------------------------------------------------------------------
menuUsed:
  lda a:.loword(j13MenuSeen)
  bne @done
  .a16
  lda #1
  sta a:.loword(j13MenuSeen)
  sta a:.loword(j13Enabled)     ; J13_ON
@done:
  rts

; ---------------------------------------------------------------------------
; ordinaryDown: newKey is pressed. Held already: a release and a press. On
; the known ROM a key with a row takes a free slot of j13Keys (no slot free:
; no event); else it releases all the held keys and takes the first slot.
;
; In:       A16 X16, DBR = this bank; newKey; the room in inputRing
; Out:      j13Keys, knownCount; the events
; Changes:  A, X; j13Generation
; Keeps:    Y, D, DBR
; Original: none
; ---------------------------------------------------------------------------
ordinaryDown:
  inc a:.loword(j13Generation)
  ldx #0
@find:
  lda a:.loword(j13Keys),x
  cmp a:.loword(newKey)
  beq @repress
  inx
  inx
  cpx #2*J13_KEY_SLOTS
  bcc @find
  lda a:.loword(j13Matrix)
  beq @single
  ldx a:.loword(newKey)
  cpx #MATRIX_KEYS
  bcs @single
  lda f:pumpMasks,x
  and #$00ff
  beq @single
  ldx #0
@slot:
  lda a:.loword(j13Keys),x
  cmp #NONE
  beq @install
  inx
  inx
  cpx #2*J13_KEY_SLOTS
  bcc @slot
  rts
@single:
  jsr .loword(releaseOrdinary)
  ldx #0
@install:
  lda a:.loword(newKey)
  sta a:.loword(j13Keys),x
  inc a:.loword(knownCount)
  jmp .loword(queue)
@repress:
  ora #KEY_RELEASE
  jsr .loword(queue)
  lda a:.loword(newKey)
  jmp .loword(queue)
; ---------------------------------------------------------------------------
; releaseOrdinary: a release event for each held identity; then none is
; held.
;
; In:       A16 X16, DBR = this bank; the room in inputRing
; Out:      j13Keys all NONE, knownCount 0; the events
; Changes:  A, X; j13Generation
; Keeps:    Y, D, DBR
; Original: none
; ---------------------------------------------------------------------------
releaseOrdinary:
  inc a:.loword(j13Generation)
  ldx #0
@key:
  lda a:.loword(j13Keys),x
  cmp #NONE
  beq @next
  ora #KEY_RELEASE
  jsr .loword(queue)
  lda #NONE
  sta a:.loword(j13Keys),x
@next:
  inx
  inx
  cpx #2*J13_KEY_SLOTS
  bcc @key
  stz a:.loword(knownCount)
  rts

; ---------------------------------------------------------------------------
; queueRoom: carry 1 when inputRing has QUEUE_ROOM free events (the ring
; keeps one entry free: the head never reaches the tail).
;
; In:       A16, DBR = this bank
; Out:      carry
; Changes:  A
; Keeps:    X, Y, D, DBR
; Time:     32 cycles
; Original: none
; ---------------------------------------------------------------------------
queueRoom:
  lda f:inputTail
  sec
  sbc f:inputHead
  dec a
  and #INPUT_RING_SIZE-1
  cmp #QUEUE_ROOM*INPUT_EVENT_SIZE
  rts
; ---------------------------------------------------------------------------
; queue: put the J13 key byte A in inputRing (queueRoom gave the room). The
; events of one sample get one time (sampleTimed); the drain applies them
; together.
;
; In:       A16 the key byte (KEY_RELEASE: a release), DBR = this bank;
;           sampleTimed
; Out:      inputHead; sampleTime, sampleTimed
; Changes:  A
; Keeps:    X, Y, D, DBR
; Time:     about 100 cycles
; Original: none
; ---------------------------------------------------------------------------
queue:
  phx
  phy
  pha
  lda a:.loword(sampleTimed)
  bne @timed
  lda a:.loword(inputClock)
  sta a:.loword(sampleTime)
  inc a:.loword(sampleTimed)
@timed:
  lda f:inputHead
  tax
  lda a:.loword(sampleTime)
  sta f:inputRing+INPUT_TIME,x
  .a16
  lda #INPUT_J13
  sta f:inputRing+INPUT_TYPE,x
  pla
  sta f:inputRing+INPUT_VALUE,x
  txa
  clc
  adc #INPUT_EVENT_SIZE
  and #INPUT_RING_SIZE-1
  sta f:inputHead
  ply
  plx
  rts

; ---------------------------------------------------------------------------
; deferRows: the row batch of a play frame. With ROW_KEYS or more held keys
; it waits for the last of ROW_WAKES DOC ticks after the frame (j13Irq),
; away from the frame's own work; once a frame at most (rowArmFrame). With
; fewer keys (P3 only: KBDSTRB gives the release of one key), or when those
; ticks did not come before the next frame, scheduleRow runs at once.
; scheduleRow arms a batch only ROW_GAP ticks after the last one: ROW_GAP
; (7 ticks, about 29 ms at the 240 Hz clock) is more than the 4 ticks of a
; frame, so a batch comes at most every second frame.
;
; In:       A16 X16, DBR = this bank, interrupts off
; Out:      rowArmFrame, rowWakeBudget; a batch armed (scheduleRow)
; Changes:  A, X, Y
; Keeps:    D, DBR
; Time:     about 30 cycles, or scheduleRow (about 60 with no key held)
; Original: none
; ---------------------------------------------------------------------------
deferRows:
  lda a:.loword(knownCount)
  .a16
  cmp #ROW_KEYS
  bcc @now
  lda a:.loword(inputFrames)
  cmp a:.loword(rowArmFrame)
  beq @done
  sta a:.loword(rowArmFrame)
  lda a:.loword(rowWakeBudget)
  bne @now
  .a16
  lda #ROW_WAKES
  sta a:.loword(rowWakeBudget)
@done:
  rts
@now:
  stz a:.loword(rowWakeBudget)
  jmp .loword(scheduleRow)

; ---------------------------------------------------------------------------
; scheduleRow: in J13_PLAY on the known ROM with a key held, at most once a
; frame (rowFrame) and only ROW_GAP ticks or more after the last batch: arm
; a batch (JS_ARMED) that reads P3, then the rows of rowList.
;
; In:       A16 X16, DBR = this bank; controllerTime
; Out:      j13State, rowAddress, rowsLeft, rowDeadline, rowFrame,
;           lastRowTime; rowMasks and rowList (cacheRows)
; Changes:  A, X, Y
; Keeps:    D, DBR
; Time:     about 60 cycles with no key held; a batch about 150 more and
;           cacheRows
; Original: none
; ---------------------------------------------------------------------------
scheduleRow:
  lda a:.loword(inputFrames)
  cmp a:.loword(rowFrame)
  beq @return
  lda a:.loword(j13Mode)
  .a16
  cmp #J13_PLAY
  bne @return
  lda a:.loword(j13State)
  bne @return
  lda a:.loword(j13Matrix)
  beq @return
  lda a:.loword(knownCount)
  beq @return
  lda a:.loword(inputFrames)
  sta a:.loword(rowFrame)
  lda a:.loword(controllerTime)
  sec
  sbc a:.loword(lastRowTime)
  cmp #ROW_GAP
  bcs @due
@return:
  rts
@due:
  lda a:.loword(controllerTime)
  sta a:.loword(lastRowTime)
  jsr .loword(cacheRows)
  lda a:.loword(rowListSize)
  lsr a
  sta a:.loword(rowsLeft)
  lda #MCU_P3
  sta a:.loword(rowAddress)
  bra scheduleReady

; ---------------------------------------------------------------------------
; scheduleTwoKeys: arm the read of the next row of rowList (after the
; first, round again), with the switch bits that the held keys have there.
; It ends in scheduleRow's part scheduleReady.
;
; In:       A16 X16, DBR = this bank; rowList, rowListSize, rowNext
; Out:      j13State, rowAddress, rowExpected, rowNext, rowDeadline
; Changes:  A, X, Y
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
scheduleTwoKeys:
  jsr .loword(cacheRows)
  ldx a:.loword(rowNext)
  inx
  inx
  cpx a:.loword(rowListSize)
  bcc @index
  ldx #0
@index:
  stx a:.loword(rowNext)
  lda a:.loword(rowList),x
  a8
  sta a:.loword(rowAddress)
  xba
  sta a:.loword(rowExpected)
  a16
scheduleReady:
  lda a:.loword(lastRowTime)
  clc
  adc #ROW_TIMEOUT
  sta a:.loword(rowDeadline)
  .a16
  lda #JS_ARMED
  sta a:.loword(j13State)
  rts

; ---------------------------------------------------------------------------
; cacheRows: rowMasks and rowList for the held keys, when they changed
; (j13Generation differs from maskGeneration).
;
; In:       A16, DBR = this bank
; Out:      rowMasks, rowList, rowListSize, maskGeneration
; Changes:  A, X, Y
; Keeps:    D, DBR
; Time:     about 20 cycles with no change, else J13CacheRows
; Original: none
; ---------------------------------------------------------------------------
cacheRows:
  lda a:.loword(j13Generation)
  cmp a:.loword(maskGeneration)
  beq @done
  jsr .loword(J13CacheRows)
@done:
  rts

; ---------------------------------------------------------------------------
; J13Pump: one step of a row read (from the samples, sendAlarm and the
; capture). JS_ARMED: take the GLU when the ADB capture has no work (no
; talk, no byte, no command): the ADB data interrupt off (the mouse one
; stays), CaptureInput off DATAREG (captureStatusMask 0), GLU_READ_MEMORY
; out. Owned: a byte in DATAREG goes to pumpData; else the next address byte
; goes out when the GLU is free.
;
; Self-changing code: the store to captureStatusMask+1 changes the AND
; operand of src/input_adb.s CaptureInput (KM_DATA_FULL back in
; releaseOwner).
;
; In:       A16 X16, DBR = this bank, interrupts off
; Out:      j13State; at a reply the releases of the held keys whose
;           switch is up; A16
; Changes:  A, X, Y; rowStatus, rowEnables, rowValue, rowDeferred,
;           rowGeneration, rowsLeft, j13Owner, keyTalk, KMSTATUS
; Keeps:    D, DBR
; Time:     13 cycles with no read (JS_IDLE); a step of a read about
;           60-150 cycles and one or two GLU accesses; a reply that
;           releases keys about 100 more for each (queue)
; Original: none
; ---------------------------------------------------------------------------
J13Pump:
  .a16
  lda a:.loword(j13State)
  bne @active
  rts
@active:
  ; JS_ARMED: take the GLU when the capture has no work.
  a8
  lda f:KMSTATUS
  sta a:.loword(rowStatus)
  lda a:.loword(j13State)
  cmp #JS_ARMED
  bne pumpOwned
  lda f:keyTalk
  ora f:keyPending
  beq @free
  brl pumpDone                  ; a keyboard talk first
@free:
  lda a:.loword(rowStatus)
  and #KM_MOUSE_FULL|KM_DATA_FULL|KM_COMMAND_FULL
  beq @take
  brl pumpDone                  ; the GLU is busy
@take:
  lda a:.loword(rowStatus)
  and #KM_MOUSE_IRQ|KM_DATA_IRQ
  sta a:.loword(rowEnables)
  lda a:.loword(rowStatus)
  and #KM_MOUSE_IRQ
  sta f:KMSTATUS
  lda #0                        ; CaptureInput does not read DATAREG
  sta f:captureStatusMask+1
  lda #1
  sta a:.loword(j13Owner)
  sta f:keyTalk                 ; and does not talk to the keyboard
  a16
  jsr .loword(startSendTimer)
  a8
pumpCommand:
  lda #GLU_READ_MEMORY
  sta f:DATAREG
  lda #JS_ADDRESS
  sta a:.loword(j13State)
  a16
  lda a:.loword(j13Generation)
  sta a:.loword(rowGeneration)
  rts
pumpOwned:
  ; Owned: a byte in DATAREG is the reply (pumpData); else the next byte
  ; of the command when the GLU is free.
  .a8
  lda a:.loword(rowStatus)
  bit #KM_DATA_FULL
  bne pumpData
  lda a:.loword(j13State)
  .a8
  cmp #JS_REPLY
  bne @send
  brl pumpDone
@send:
  lda a:.loword(rowStatus)
  and #KM_COMMAND_FULL
  beq @free
  brl pumpDone
@free:
  lda a:.loword(j13State)
  cmp #JS_ADDRESS
  bne @high
  lda a:.loword(rowAddress)
  sta f:DATAREG
  lda #JS_HIGH
  sta a:.loword(j13State)
  brl pumpDone
@high:
  lda #0                        ; the high byte: RAM page 0
  sta f:DATAREG
  lda #JS_REPLY
  sta a:.loword(j13State)
  lda a:.loword(rowEnables)     ; the data interrupt again, for the reply
  sta f:KMSTATUS
  a16
  brl pumpDone
pumpData:
  ; The reply of a P3 read, or of a row read: a row in which only held
  ; switches can be down (and some of them are up) gives releases.
  .a8
  lda f:DATAREG
  sta a:.loword(rowValue)
  lda a:.loword(j13State)
  .a8
  cmp #JS_REPLY
  bne pumpStatusByte
  lda a:.loword(rowAddress)
  cmp #MCU_P3
  bne @matrix
  lda a:.loword(rowValue)       ; a status byte before the reply?
  cmp #ADB_KEY_REQUEST
  beq pumpStatusByte
  cmp #ADB_STATUS_ESC
  beq pumpStatusByte
  cmp #ADB_STATUS_ERROR
  beq pumpStatusByte
  a16
  brl pumpPhysicalReply
@matrix:
  .a8
  lda a:.loword(rowValue)
  eor #$ff                      ; the switches: 1 = down
  cmp a:.loword(rowExpected)
  bne @changed
  a16
  brl batchReadDone             ; no held key went up
@changed:
  .a8
  ora a:.loword(rowExpected)
  cmp a:.loword(rowExpected)
  beq pumpValidReply            ; no other switch is down: held keys went up
  ; A status byte can come before the one-byte row reply.
  lda a:.loword(rowValue)
  and #ADB_REPLY_FOLLOWS|ADB_REPLY_BITS
  beq pumpStatusByte
  a16
  jsr .loword(releaseOwner)
  brl pumpDone                  ; a row that is not clear: no releases
pumpStatusByte:
  .a8
  lda a:.loword(rowValue)
  and #ADB_REPLY_FOLLOWS|ADB_REPLY_BITS
  bne @done
  lda a:.loword(rowValue)
  and #ADB_KEY_REQUEST          ; a keyboard request waits for the end
  ora a:.loword(rowDeferred)
  sta a:.loword(rowDeferred)
@done:
  a16
  rts
pumpValidReply:
  ; The releases: each held key of this row whose switch is up.
  a16
  jsr .loword(queueRoom)
  bcs @room
  brl pumpFinished
@room:
  lda a:.loword(rowGeneration)
  cmp a:.loword(j13Generation)
  beq @current
  brl pumpFinished              ; a key went down after the read started
@current:
  stz a:.loword(sampleTimed)
  ldy #0
rowRelease:
  lda a:.loword(j13Keys),y
  cmp #MATRIX_KEYS
  bcs rowReleaseNext
  tax
  lda f:pumpRows,x
  and #$00ff
  cmp a:.loword(rowAddress)
  bne rowReleaseNext
  lda f:pumpMasks,x
  and a:.loword(rowValue)
  and #$00ff
  beq rowReleaseNext            ; the switch is down
  txa
  ora #KEY_RELEASE
  jsr .loword(queue)
  lda #NONE
  sta a:.loword(j13Keys),y
  dec a:.loword(knownCount)
  inc a:.loword(j13Generation)
rowReleaseNext:
  iny
  iny
  cpy #2*J13_KEY_SLOTS
  bcc rowRelease
batchReadDone:
  dec a:.loword(rowsLeft)
  beq pumpFinished
  jmp .loword(continueHeldRows)
pumpFinished:
  jsr .loword(releaseOwner)
pumpDone:
  a16
  rts

; ---------------------------------------------------------------------------
; pumpPhysicalReply: a part of J13Pump: the P3 reply: the live modifiers
; (KEYMODREG keeps the state of its character while other keys stay down),
; unless a character or a release came after the read started. Then, with
; ROW_KEYS or more held keys, the next row read (continueHeldRows); else
; the GLU goes back.
;
; In:       A16 X16, DBR = this bank; rowValue, rowGeneration
; Out:      physicalMods, physicalValid, the modifier events; the next read
; Changes:  A, X, Y (as J13Pump)
; Original: none
; ---------------------------------------------------------------------------
pumpPhysicalReply:
  lda a:.loword(knownCount)
  beq physicalReturn
  lda a:.loword(rowGeneration)
  cmp a:.loword(j13Generation)
  bne physicalReturn
  lda a:.loword(rowValue)
  eor #P3_LOW_BITS
  and #KMOD_KEYS
  sta a:.loword(physicalMods)
  sta a:.loword(nextMods)
  .a16
  lda #1
  sta a:.loword(physicalValid)
  lda a:.loword(nextMods)
  cmp a:.loword(j13Mods)
  beq physicalNoRoom
  jsr .loword(queueRoom)
  bcc physicalNoRoom
  stz a:.loword(sampleTimed)
  jsr .loword(updateModifiers)
physicalNoRoom:
continueHeldRows:
  ; The next row of the batch: the command again, with the ADB data
  ; interrupt off until the address is out.
  lda a:.loword(knownCount)
  .a16
  cmp #ROW_KEYS
  bcc physicalReturn
  jsr .loword(scheduleTwoKeys)
  a8
  lda a:.loword(rowEnables)
  and #KM_MOUSE_IRQ
  sta f:KMSTATUS
  jmp .loword(pumpCommand)
physicalReturn:
  jmp .loword(releaseOwner)

; ---------------------------------------------------------------------------
; serviceController: one service step of a play sample: J13Pump; a read
; that waits for its reply after rowDeadline stops the row reads (j13Matrix
; 0) and gives the GLU back. Its part serviceTimeout is also the way out of
; sendAlarm at a time out.
;
; In:       A16 X16, DBR = this bank; controllerTime
; Out:      j13State; j13Matrix 0 at a time out
; Changes:  A, X, Y
; Keeps:    D, DBR
; Time:     about 40 cycles with no read
; Original: none
; ---------------------------------------------------------------------------
serviceController:
  jsr .loword(J13Pump)
  lda a:.loword(j13State)
  .a16
  cmp #JS_REPLY
  bcc serviceDone
  lda a:.loword(controllerTime)
  sec
  sbc a:.loword(rowDeadline)
  bmi serviceDone
serviceTimeout:
  stz a:.loword(j13Matrix)
  jmp .loword(releaseOwner)
serviceDone:
  rts

; ---------------------------------------------------------------------------
; releaseOwner: the GLU goes back to the ADB capture: CaptureInput reads
; DATAREG again (its patched operand back to KM_DATA_FULL), a keyboard
; request seen during the read waits (keyPending), the interrupt enables
; are as before, JS_IDLE.
;
; In:       A8 or A16, DBR = this bank
; Out:      j13State JS_IDLE, j13Owner 0, j13SendTimer 0, keyTalk 0,
;           keyPending, KMSTATUS; A16
; Changes:  A; rowDeferred
; Keeps:    X, Y, D, DBR
; Original: none
; ---------------------------------------------------------------------------
releaseOwner:
  a8
  lda #KM_DATA_FULL
  sta f:captureStatusMask+1
  lda #0
  sta f:keyTalk
  sta a:.loword(j13Owner)
  lda a:.loword(rowDeferred)
  beq @none
  lda #1
  sta f:keyPending
@none:
  stz a:.loword(rowDeferred)
  lda a:.loword(rowEnables)
  sta f:KMSTATUS
  a16
  stz a:.loword(j13State)
  stz a:.loword(j13SendTimer)
  rts
; ---------------------------------------------------------------------------
; finishOwner: before a mode change an owned read finishes: a half-sent
; GLU_READ_MEMORY would leave its reply to the ADB capture. After
; FINISH_TRIES steps the row reads stop. Then JS_IDLE.
;
; In:       A16 X16, DBR = this bank, interrupts off
; Out:      j13State JS_IDLE, the GLU back to the capture
; Changes:  A, X, Y
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
finishOwner:
  lda a:.loword(j13Owner)
  beq @idle
  ldy #FINISH_TRIES
@wait:
  phy
  jsr .loword(J13Pump)
  ply
  lda a:.loword(j13Owner)
  beq @idle
  dey
  bne @wait
  stz a:.loword(j13Matrix)
  jmp .loword(releaseOwner)
@idle:
  stz a:.loword(j13State)
  rts

; ---------------------------------------------------------------------------
; sendAlarm: the DOC tick while a read owns the GLU (j13SendTimer): the
; next address byte goes out when the GLU is free, or a reply byte goes to
; J13Pump. After SEND_BUDGET calls the read times out. It does not sample
; the keys.
;
; In:       A16 X16, DBR = this bank (input_tick, interrupts off)
; Out:      j13State, sendBudget; the byte sent; at a time out the GLU back
;           and j13Matrix 0
; Changes:  A, X, Y
; Keeps:    D, DBR
; Time:     about 85 cycles and two GLU accesses when it sends a byte; at
;           each DOC tick while j13SendTimer is set
; Original: none
; ---------------------------------------------------------------------------
sendAlarm:
  .a16
  lda a:.loword(j13State)
  cmp #JS_ADDRESS
  bcc @done
  dec a:.loword(sendBudget)
  beq @timeout
  .a16
  cmp #JS_REPLY
  bcs @done
  a8
  lda f:KMSTATUS
  bit #KM_DATA_FULL
  bne @data
  lsr a                         ; KM_COMMAND_FULL: busy
  bcs @wide
  lda a:.loword(j13State)
  cmp #JS_ADDRESS
  bne @high
  lda a:.loword(rowAddress)
  sta f:DATAREG
  inc a:.loword(j13State)       ; JS_HIGH
  bra @wide
@high:
  lda #0
  sta f:DATAREG
  inc a:.loword(j13State)       ; JS_REPLY
  lda a:.loword(rowEnables)
  sta f:KMSTATUS
@wide:
  a16
@done:
  rts
@timeout:
  jmp .loword(serviceTimeout)
@data:
  a16
  jmp .loword(J13Pump)

; ---------------------------------------------------------------------------
; startSendTimer: sendAlarm runs from this call, SEND_BUDGET times at most.
;
; In:       A16, DBR = this bank
; Out:      sendBudget, j13SendTimer
; Changes:  A
; Keeps:    X, Y, D, DBR
; Original: none
; ---------------------------------------------------------------------------
startSendTimer:
  lda #SEND_BUDGET
  sta a:.loword(sendBudget)
  .a16
  lda #1
  sta a:.loword(j13SendTimer)
  rts

; ---------------------------------------------------------------------------
; clearHeld: forget the held identities and modifiers, keep only the ADB
; bits of keyHeld, and take the current KBDSTRB and KBD state as known.
;
; In:       A16 X16, DBR = this bank
; Out:      j13Keys, j13Mods, knownCount, physicalValid, sampleRecover,
;           keyHeld, sampleAKD, j13LastAscii; A16
; Changes:  A, X; j13Generation
; Keeps:    Y, D, DBR
; Original: none
; ---------------------------------------------------------------------------
clearHeld:
  lda #NONE
  sta a:.loword(j13Keys)
  sta a:.loword(j13Keys+2)
  sta a:.loword(j13Keys+4)
  stz a:.loword(j13Mods)
  stz a:.loword(knownCount)
  stz a:.loword(physicalValid)
  stz a:.loword(sampleRecover)
  inc a:.loword(j13Generation)
  ldx #KEY_CODES-1
  a8
@source:
  lda f:keyHeld,x
  and #HELD_ADB
  sta f:keyHeld,x
  dex
  bpl @source
  lda f:KBDSTRB
  sta a:.loword(sampleAKD)
  lda f:KBD
  .a8
  and #<~KBD_STROBE
  sta a:.loword(j13LastAscii)
  a16
  rts
.assert J13_KEY_SLOTS = 3, error ; the three stores above

; The J13 state.
.a16
keyboardConfig: .res ::CONFIG_BYTES,0  ; stopFirmwareRepeat: the configuration bytes of the microcontroller
validateIncoming: .word 0       ; 1: J13ValidateTracked counts newKey as held (sampleCharacter)
j13Enabled: .word 0             ; J13_ON: the play reads the J13 keyboard
j13AdbPresent: .word 1          ; 1: an ADB keyboard answers (raw keys)
j13Available: .word 0           ; 1: a ROM 00/01 machine
j13Matrix: .word 0              ; 1: the known microcontroller ROM: the row reads work
; The modes (j13Mode; src/input.s input_sample sets them):
;   J13_ESCAPE  the play with J13 play off: only an ESC character counts
;               (escapeSample); it opens the menu.
;   J13_MENU    the options menu and the title: every key, at each sample
;               of the input (J13Poll: once a frame on the title, every
;               MENU_WAIT ticks in the menu); before a character the held
;               keys are checked with a direct row read (J13ValidateTracked).
;   J13_PLAY    the play with J13 play on: the keys at each DOC tick
;               (j13Irq), the row batches for the releases (deferRows,
;               scheduleRow, J13Pump), at most every second frame.
; A change to J13_ESCAPE or from it forgets the held keys; from J13_MENU to
; J13_PLAY or back they stay, and J13_PLAY checks them.
;
j13Mode: .word 0                ; J13_ESCAPE, J13_MENU or J13_PLAY
j13NextMode: .word 0            ; setMode: the mode to set
j13MenuSeen: .word 0            ; 1: the menu has been used (or the player chose J13 play)
j13Manual: .word 0              ; J13_CHOSEN: the player chose J13 play in the menu
j13Owner: .word 0               ; 1: a row read owns the GLU
; The row read (j13State):
;   JS_IDLE     no read; J13Pump returns.
;   JS_ARMED    a read waits for the GLU: when the capture has no work,
;               J13Pump takes the GLU and sends GLU_READ_MEMORY: JS_ADDRESS.
;   JS_ADDRESS  the low address byte goes out when the GLU is free: JS_HIGH.
;   JS_HIGH     the high address byte goes out: JS_REPLY.
;   JS_REPLY    the reply byte comes (J13Pump from the capture); the next row
;               of the batch: JS_ADDRESS again, or the GLU goes back:
;               JS_IDLE (releaseOwner). Past rowDeadline: JS_IDLE, and the
;               row reads stop (j13Matrix 0).
;
j13State: .word 0               ; JS_*
j13SendTimer: .word 0           ; 1: input_tick runs sendAlarm
sendBudget: .word 0             ; sendAlarm calls left before the read times out
j13Keys: .word NONE,NONE,NONE   ; the held key identities
j13Mods: .word 0                ; the modifier bits (KMOD_KEYS) of the last events
knownCount: .word 0             ; the held identities in j13Keys
controllerTime: .word 0         ; inputClock at the service
physicalMods: .word 0           ; the modifier bits of the last P3 read
physicalValid: .word 0          ; 1: physicalMods is later than KEYMODREG
rowDeadline: .word 0            ; inputClock: the read times out after this
nextMods: .word 0               ; updateModifiers: the modifier bits to reach
newKey: .word 0                 ; the identity of the character
j13Generation: .word 0          ; changes with each change of j13Keys
rowGeneration: .word 0          ; j13Generation when the read started
rowNext: .word 0                ; scheduleTwoKeys: the rowList offset of the row
rowFrame: .word NO_FRAME        ; scheduleRow: inputFrames of the last call
rowArmFrame: .word NO_FRAME     ; deferRows: inputFrames of the last arm
rowWakeBudget: .word 0          ; j13Irq: the DOC ticks left before the batch
maskGeneration: .word NO_FRAME  ; j13Generation of rowMasks and rowList
rowMasks: .res MCU_ROWS         ; each MCU row: the switch bits of the held keys
rowList: .res 2*J13_KEY_SLOTS   ; the rows to read: the address, then the bits
rowListSize: .word 0            ; the bytes of rowList
cacheMask: .byte 0              ; J13CacheRows: the switch bit
rowsLeft: .word 0               ; the rows of the batch still to read
rowAddress: .word 0             ; the MCU address of the read: MCU_P3 or a row
rowExpected: .word 0            ; the switch bits of the held keys in the row
rowValue: .word 0               ; the reply byte
rowEnables: .word 0             ; the KMSTATUS interrupt bits before the read
rowStatus: .word 0              ; the KMSTATUS byte of this J13Pump step
rowDeferred: .word 0            ; ADB_KEY_REQUEST: the keyboard asked in the read
lastRowTime: .word 0            ; controllerTime of the last batch
sampleAscii: .word 0            ; the KBD byte; KBD_STROBE: a character
sampleMods: .word 0             ; the KEYMODREG byte of the character
sampleAKD: .word 0              ; the last KBDSTRB byte; KBD_STROBE: a key is down
sampleRecover: .word 0          ; 1: a key went down with no character
recoverTime: .word 0            ; inputClock: the recovery reads after this
j13LastAscii: .word 0           ; the last character (7 bits)
sampleTime: .word 0             ; the time of the events of this sample
sampleTimed: .word 0            ; 1: sampleTime is set for this sample

; ---------------------------------------------------------------------------
; sendBounded: write A8 to DATAREG when the GLU command register is free;
; carry 1 after GLU_WAIT busy reads. No delay write after it: a write of
; $C05F (AN3) is a Second Sight event, and an event while the card's
; DMA channel 1 runs is a DMA request.
;
; In:       A8 the byte
; Out:      carry
; Changes:  Y
; Keeps:    A, X, D, DBR
; Original: none
; ---------------------------------------------------------------------------
sendBounded:
  .a8
  pha
  ldy #GLU_WAIT
@busy:
  lda f:KMSTATUS
  and #KM_COMMAND_FULL
  beq @free
  dey
  bne @busy
  pla
  sec
  rts
@free:
  pla
  sta f:DATAREG
  clc
  rts

; ---------------------------------------------------------------------------
; readBounded: A8 = the next DATAREG byte; carry 1 after GLU_WAIT empty
; reads.
;
; In:       A8
; Out:      A8 the byte; carry
; Changes:  A, Y
; Keeps:    X, D, DBR
; Original: none
; ---------------------------------------------------------------------------
readBounded:
  .a8
  ldy #GLU_WAIT
@empty:
  lda f:KMSTATUS
  and #KM_DATA_FULL
  bne @full
  dey
  bne @empty
  sec
  rts
@full:
  lda f:DATAREG
  clc
  rts

; The modifier keys: their KEYMODREG bits and their key codes.
modifierMasks: .byte KMOD_SHIFT,KMOD_CONTROL,KMOD_CAPS,KMOD_COMMAND,KMOD_OPTION
modifierKeys: .byte KEY_SHIFT,KEY_CONTROL,KEY_CAPS_LOCK,KEY_COMMAND,KEY_OPTION
.assert *-modifierKeys = MODIFIER_KEYS, error

; asciiKeys: the key identity (an ADB key code) of each 7-bit character. The
; arrow characters win (Ctrl-H is LEFT); a shifted sign is its unshifted US
; key. Keys with the same character look the same. The releases come from
; KBDSTRB or a row read.
asciiKeys:
  .byte $31,$00,$0b,$08,$02,$0e,$03,$05,$3b,$30,$3d,$3e,$25,$24,$2d,$1f  ; $00-$0F
  .byte $23,$0c,$0f,$01,$11,$3c,$09,$0d,$07,$10,$06,$35,$2a,$1e,$16,$1b  ; $10-$1F
  .byte $31,$12,$27,$14,$15,$17,$1a,$27,$19,$1d,$1c,$18,$2b,$1b,$2f,$2c  ; $20-$2F
  .byte $1d,$12,$13,$14,$15,$17,$16,$1a,$1c,$19,$29,$29,$2b,$18,$2f,$2c  ; $30-$3F
  .byte $13,$00,$0b,$08,$02,$0e,$03,$05,$04,$22,$26,$28,$25,$2e,$2d,$1f  ; $40-$4F
  .byte $23,$0c,$0f,$01,$11,$20,$09,$0d,$07,$10,$06,$21,$2a,$1e,$16,$1b  ; $50-$5F
  .byte $32,$00,$0b,$08,$02,$0e,$03,$05,$04,$22,$26,$28,$25,$2e,$2d,$1f  ; $60-$6F
  .byte $23,$0c,$0f,$01,$11,$20,$09,$0d,$07,$10,$06,$21,$2a,$1e,$32,$33  ; $70-$7F

; keypadKeys: the ADB key code of each keypad character below KEYPAD_CHARS
; (KEYMODREG KMOD_KEYPAD), so the keypad keys differ from the main keys.
KEYPAD_CHARS = $40
keypadKeys:
.repeat KEYPAD_CHARS, C
  .if C = $0d
    .byte KEY_PAD_ENTER
  .elseif C = '0'
    .byte KEY_PAD_0
  .elseif C >= '1' .and C <= '7'
    .byte KEY_PAD_1+C-'1'
  .elseif C = '8'
    .byte KEY_PAD_8
  .elseif C = '9'
    .byte KEY_PAD_9
  .elseif C = '.'
    .byte KEY_PAD_POINT
  .elseif C = '*'
    .byte KEY_PAD_TIMES
  .elseif C = '+'
    .byte KEY_PAD_PLUS
  .elseif C = '/'
    .byte KEY_PAD_DIVIDE
  .elseif C = '-'
    .byte KEY_PAD_MINUS
  .elseif C = '='
    .byte KEY_PAD_EQUALS
  .else
    .byte NONE
  .endif
.endrepeat
.assert KEY_PAD_7 = KEY_PAD_1+6, error  ; the keypad codes 1-7 are in a row

; ---------------------------------------------------------------------------
; readMCU: A8 = the microcontroller byte at X (GLU_READ_MEMORY: RAM when
; the high byte of X is 0, else ROM); carry 1 when the GLU does not answer.
;
; In:       A8 X16 the address
; Out:      A8 the byte; carry
; Changes:  A, Y
; Keeps:    X, D, DBR
; Original: none
; ---------------------------------------------------------------------------
readMCU:
  .a8
  lda #GLU_READ_MEMORY
  jsr .loword(sendBounded)
  bcs @done
  txa
  jsr .loword(sendBounded)
  bcs @done
  a16
  txa
  xba
  a8
  jsr .loword(sendBounded)
  bcs @done
  jsr .loword(readBounded)
@done:
  rts

; matrixROM: the microcontroller ROM bytes of the known ROM: SIGNATURE_PART
; at MCU_SIGNATURE1 (the scanner), then SIGNATURE_PART at MCU_SIGNATURE2
; (the row update).
matrixROM:
  .byte $3c,$ff,$e4,$a2,$09,$22,$59,$3c,$0a,$48,$c6,$48,$30,$5b,$a5,$48,$aa,$8b,$85,$e4,$b5,$31,$45,$e2,$3c,$ff,$e4,$f0,$ed,$a0,$08,$88
  .byte $22,$b4,$f7,$4c,$05,$15,$31,$95,$31,$60,$8f,$0a,$e7,$0f,$06,$49,$ff,$35,$31,$95,$31,$22,$c5,$33,$1c,$f3,$1a,$a6,$4c,$e0,$37,$f0
.assert *-matrixROM = 2*SIGNATURE_PART, error

; pumpRows, pumpMasks: for each key identity below MATRIX_KEYS, its row in
; the microcontroller RAM and its switch bit there (0 = down). Row $FF and
; bit 0: no row. The keys of one row share one read (rowList).
pumpRows:
  .byte $31,$33,$32,$35,$34,$36,$31,$32,$33,$34,$ff,$35,$32,$33,$34,$35
  .byte $36,$37,$32,$33,$34,$35,$36,$37,$38,$3a,$38,$3a,$39,$39,$3a,$3a
  .byte $38,$39,$39,$38,$37,$3a,$37,$3a,$38,$39,$37,$38,$3a,$36,$37,$39
  .byte $31,$39,$37,$37,$ff,$31,$ff,$ff,$ff,$ff,$ff,$39,$3a,$38,$38,$ff
pumpMasks:
  .byte $04,$04,$04,$04,$04,$04,$08,$08,$08,$08,$00,$08,$02,$02,$02,$02
  .byte $02,$02,$01,$01,$01,$01,$01,$01,$10,$01,$01,$10,$01,$10,$20,$02
  .byte $02,$20,$02,$20,$40,$04,$04,$40,$04,$04,$10,$08,$08,$08,$08,$08
  .byte $02,$40,$20,$80,$00,$01,$00,$00,$00,$00,$00,$80,$80,$80,$40,$00
.assert *-pumpMasks = MATRIX_KEYS, error

; ---------------------------------------------------------------------------
; bufferKeyboard: set the GLU_KEY_BUFFER mode bit, then stop the firmware
; key repeat (stopFirmwareRepeat, by a JMP).
;
; In:       A8 X16
; Out:      the mode bit; the repeat off
; Changes:  A, X, Y; keyboardConfig
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
bufferKeyboard:
  .a8
  lda #GLU_READ_MODES
  jsr .loword(sendBounded)
  bcs @done
  jsr .loword(readBounded)
  bcs @done
  and #GLU_KEY_BUFFER
  bne @done
  lda #GLU_SET_MODES
  jsr .loword(sendBounded)
  bcs @done
  lda #GLU_KEY_BUFFER
  jsr .loword(sendBounded)
@done:
  jmp .loword(stopFirmwareRepeat)

; ---------------------------------------------------------------------------
; stopFirmwareRepeat: read the configuration bytes; when the repeat delay is
; not CONFIG_NO_REPEAT, write them back with it, so the microcontroller
; repeats no key.
;
; In:       A8 X16
; Out:      the configuration of the microcontroller
; Changes:  A, X, Y; keyboardConfig
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
stopFirmwareRepeat:
  .a8
  lda #GLU_READ_CONFIG
  jsr .loword(sendBounded)
  bcs @done
  ldx #0
@read:
  jsr .loword(readBounded)
  bcs @done
  sta f:keyboardConfig,x
  inx
  cpx #CONFIG_BYTES
  bcc @read
  lda f:keyboardConfig+CONFIG_REPEAT_BYTE
  and #CONFIG_DELAY
  cmp #CONFIG_NO_REPEAT
  beq @done
  jsr .loword(sendKeyboardConfig)
  bcs @done
  lda f:keyboardConfig+CONFIG_REPEAT_BYTE
  and #<~CONFIG_DELAY
  ora #CONFIG_NO_REPEAT
  jsr .loword(sendBounded)
@done:
  rts

; ---------------------------------------------------------------------------
; sendKeyboardConfig: GLU_SET_CONFIG and the first two configuration bytes
; as they are; stopFirmwareRepeat sends the third.
;
; In:       A8; keyboardConfig
; Out:      carry 1: the GLU does not answer
; Changes:  A, Y
; Keeps:    X, D, DBR
; Original: none
; ---------------------------------------------------------------------------
sendKeyboardConfig:
  .a8
  lda #GLU_SET_CONFIG
  jsr .loword(sendBounded)
  bcs @done
  lda f:keyboardConfig
  jsr .loword(sendBounded)
  bcs @done
  lda f:keyboardConfig+1
  jsr .loword(sendBounded)
@done:
  rts

; ---------------------------------------------------------------------------
; probeADB: Talk register 3 of the ADB keyboard. No keyboard (no reply, or
; a reply with no byte count): j13AdbPresent 0, and CaptureInput never
; talks to the keyboard, so a bus with only a mouse gets no empty talks.
;
; Self-changing code: with no keyboard it writes JMP withoutRawKeys over
; the first instruction of captureTalk (src/input_adb.s).
;
; In:       A8 X16
; Out:      j13AdbPresent; captureTalk
; Changes:  A, X, Y
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
probeADB:
  .a8
  lda #GLU_TALK+ADB_ID_REGISTER*ADB_REGISTER+ADB_KEYBOARD
  jsr .loword(sendBounded)
  bcs noADBKeyboard
  ldx #NOTICE_MAX
@header:
  jsr .loword(readBounded)
  bcs noADBKeyboard
  .a8
  bit #ADB_REPLY_FOLLOWS
  bne @reply
  dex
  bne @header
  bra noADBKeyboard
@reply:
  and #ADB_REPLY_BITS
  beq noADBKeyboard
  a16
  and #$00ff
  inc a                         ; the reply bytes
  tax
  a8
@bytes:
  jsr .loword(readBounded)
  bcs noADBKeyboard
  dex
  bne @bytes
  rts
noADBKeyboard:
  lda #0
  sta a:.loword(j13AdbPresent)
  lda #OPCODE_JMP
  sta f:captureTalk
  a16
  lda #.loword(withoutRawKeys)
  sta f:captureTalk+1
  a8
  rts

; ---------------------------------------------------------------------------
; J13ValidateTracked: at a mode change, and before a character in J13_MENU:
; read the row of each held identity (readTransition); a key that is up is
; released. In J13_PLAY a key still down is pressed again when a J13
; binding gives it game bits (not a menu action: the ESC that closed the
; menu); then P3 gives the modifiers. Not in a play frame.
;
; In:       A16 X16, DBR = this bank, interrupts off
; Out:      the releases (and presses again) of the held identities; in
;           J13_PLAY physicalMods, physicalValid, j13Mods
; Changes:  A, X, Y; rowAddress, rowExpected, rowValue, nextMods,
;           sampleTimed
; Keeps:    D, DBR
; Time:     one GLU round trip for each held key (readTransition)
; Original: none
; ---------------------------------------------------------------------------
J13ValidateTracked:
  .a16
  lda a:.loword(j13Matrix)
  beq @return
  lda a:.loword(knownCount)
  bne validateStart
  lda a:.loword(j13Mode)
  cmp #J13_PLAY
  bne @return
  brl validateModifiers
@return:
  rts
validateStart:
  stz a:.loword(sampleTimed)
  ldy #0
validateSlot:
  tyx
  lda a:.loword(j13Keys),x
  cmp #MATRIX_KEYS
  bcc @mapped
  brl validateNext
@mapped:
  ; rowExpected: the switch bits of all the held keys in this row.
  tax
  lda f:pumpRows,x
  and #$00ff
  sta a:.loword(rowAddress)
  stz a:.loword(rowExpected)
  ldx #0
validateMask:
  lda a:.loword(j13Keys),x
  cmp #MATRIX_KEYS
  bcs @next
  phx
  tax
  lda f:pumpRows,x
  and #$00ff
  cmp a:.loword(rowAddress)
  bne @done
  lda f:pumpMasks,x
  and #$00ff
  ora a:.loword(rowExpected)
  sta a:.loword(rowExpected)
@done:
  plx
@next:
  inx
  inx
  cpx #2*J13_KEY_SLOTS
  bcc validateMask
  ; The character is a key that is down already, though ordinaryDown has
  ; not put it in j13Keys yet. Its bit counts in a shared row; else UP and a
  ; DOWN make the row of UP look like a status byte, and UP is lost.
  lda a:.loword(validateIncoming)
  beq validateExpected
  lda a:.loword(newKey)
  cmp #MATRIX_KEYS
  bcs validateExpected
  tax
  lda f:pumpRows,x
  and #$00ff
  cmp a:.loword(rowAddress)
  bne validateExpected
  lda f:pumpMasks,x
  and #$00ff
  ora a:.loword(rowExpected)
  sta a:.loword(rowExpected)
validateExpected:
  phy
  lda a:.loword(rowAddress)
  tax
  a8
  jsr .loword(readTransition)
  a16
  ply
  bcs validateForget
  and #$00ff
  sta a:.loword(rowValue)
  eor #$00ff
  ora a:.loword(rowExpected)
  cmp a:.loword(rowExpected)
  bne validateForget            ; an unknown switch is down: the row is not clear
  tyx
  lda a:.loword(j13Keys),x
  tax
  lda f:pumpMasks,x
  and a:.loword(rowValue)
  and #$00ff
  bne validateForget            ; the key is up
  lda a:.loword(j13Mode)
  cmp #J13_PLAY
  bne validateNext
  txa
  ldx #BIND_COUNT*2-2
validateBound:
  ; A J13 binding of the key with game bits: a keyboard binding (a device
  ; binding has its own key numbers) with the J13 bit.
  cmp a:.loword(boundKeys),x
  bne validateBoundNext
  pha
  lda a:.loword(boundBits),x
  beq validateNotGame
  lda a:.loword(boundSources),x
  cmp #SOURCE_DEVICE_FIRST
  bcs validateNotGame
  and #SOURCE_J13
  beq validateNotGame
  pla
  bra validatePublish
validateNotGame:
  pla
validateBoundNext:
  dex
  dex
  bpl validateBound
  bra validateNext
validatePublish:
  jsr .loword(queue)
  bra validateNext
validateForget:
  tyx
  lda a:.loword(j13Keys),x
  ora #KEY_RELEASE
  jsr .loword(queue)
  lda #NONE
  tyx
  sta a:.loword(j13Keys),x
  dec a:.loword(knownCount)
validateNext:
  iny
  iny
  cpy #2*J13_KEY_SLOTS
  bcs validateModifiers
  brl validateSlot
validateModifiers:
  ; In J13_PLAY the live modifiers from P3.
  lda a:.loword(j13Mode)
  cmp #J13_PLAY
  bne @done
  ldx #MCU_P3
  a8
  jsr .loword(readTransition)
  a16
  bcs @done
  eor #P3_LOW_BITS
  and #KMOD_KEYS
  sta a:.loword(physicalMods)
  sta a:.loword(nextMods)
  lda #1
  sta a:.loword(physicalValid)
  stz a:.loword(j13Mods)
  jsr .loword(updateModifiers)
@done:
  rts

; ---------------------------------------------------------------------------
; readTransition: A8 = the microcontroller byte at X, outside a play frame.
; First the ADB capture runs while it has work (TRANSITION_TRIES times at
; most). The status bytes before the reply are skipped; a keyboard request
; among them waits (keyPending). Carry 1: no reply.
;
; In:       A8 X16 the address, DBR = this bank, interrupts off
; Out:      A8 the byte, carry; keyPending at a request
; Changes:  A, X, Y
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
readTransition:
  .a8
  phx
  a16
  ldy #TRANSITION_TRIES
@wait:
  lda a:.loword(keyTalk)
  ora a:.loword(keyPending)
  bne @capture
  a8
  lda f:KMSTATUS
  bit #KM_MOUSE_FULL|KM_DATA_FULL|KM_COMMAND_FULL
  a16
  bne @capture
  plx
  a8
  jsr .loword(readMCU)
  bcs @return
  ldx #NOTICE_MAX
@byte:
  cmp #ADB_KEY_REQUEST
  beq @request
  cmp #ADB_STATUS_ESC
  beq @notice
  cmp #ADB_STATUS_ERROR
  beq @notice
  clc
@return:
  rts
@request:
  lda #1
  sta a:.loword(keyPending)
@notice:
  dex
  beq @timeout
  jsr .loword(readBounded)
  bcc @byte
  rts
@capture:
  phy
  jsl CaptureInput
  ply
  dey
  bne @wait
  plx
  a8
@timeout:
  sec
  rts

; ---------------------------------------------------------------------------
; J13CacheRows: rowMasks = the switch bits of the held keys in each row;
; rowList = the rows that have bits (the address, then the bits);
; maskGeneration = A.
;
; In:       A16 X16, DBR = this bank; A the generation
; Out:      rowMasks, rowList, rowListSize, maskGeneration; A16
; Changes:  A, X, Y; cacheMask
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
J13CacheRows:
  .a16
  sta a:.loword(maskGeneration)
  ldx #MCU_ROWS-2
  .a16
  lda #0
@clear:
  sta a:.loword(rowMasks),x
  dex
  dex
  bpl @clear
  ldy #0
@key:
  lda a:.loword(j13Keys),y
  cmp #MATRIX_KEYS
  bcs @next
  tax
  a8
  lda f:pumpMasks,x
  beq @none
  sta a:.loword(cacheMask)
  lda f:pumpRows,x
  sec
  sbc #MCU_ROW_FIRST
  tax
  lda a:.loword(rowMasks),x
  ora a:.loword(cacheMask)
  sta a:.loword(rowMasks),x
@none:
  a16
@next:
  iny
  iny
  cpy #2*J13_KEY_SLOTS
  bcc @key
  ldx #0
  ldy #0
  a8
@list:
  lda a:.loword(rowMasks),x
  beq @empty
  sta a:.loword(rowList+1),y
  txa
  clc
  adc #MCU_ROW_FIRST
  sta a:.loword(rowList),y
  iny
  iny
@empty:
  inx
  cpx #MCU_ROWS
  bcc @list
  a16
  sty a:.loword(rowListSize)
  rts
