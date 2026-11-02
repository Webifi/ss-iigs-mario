; The input of the game: the ADB keyboard, the J13 keyboard of a ROM 00 or
; ROM 01 IIgs, the joystick of the game port and the two pads of a SNES MAX
; adapter become the pads of the two players, in the bit order of the
; original's pads (input_pads), and the menu key. The actions are the eight
; buttons of each player's pad and the menu key.
;
; How the input flows:
;   - The DOC timer interrupt calls input_tick at each tick (4 in each
;     picture of the mode, about 240 Hz, src/clock.s): it counts the tick
;     (inputClock, the time of the events) and runs the J13 work of a tick.
;   - Each interrupt, the DOC timer's and the ADB GLU's, ends with
;     input_capture (src/clock.s clock_irq). It reads the ADB keyboard bytes
;     from the GLU and the J13 keyboard (src/input_adb.s, src/input_j13.s),
;     and puts each key press and release, with the tick count, in the event
;     ring inputRing. input_start turns on the GLU's data and mouse
;     interrupts, so each ADB byte is read when it comes.
;   - The main loop calls input_frame once for each frame of the original
;     (60.1 Hz). It applies the events of the ring (drain), reads the devices
;     that have no events (the joystick and the pads, src/input_devices.s),
;     and writes input_pads: the held buttons and the buttons pressed since
;     the last frame. A key that two sources hold stays held until both let
;     it go. Each key changes the counts of the actions that its bindings
;     give (src/input_bindings.s), so two keys of one action work together.
;   - The main loop calls input_idle while it waits for the next frame:
;     there the joystick axes are read, which takes 1.78 ms of waiting
;     for the paddle timers. When no wait came, input_frame reads them.
;   - The menu key (ESC, or a key bound to ACTION_MENU) makes input_frame
;     return carry set; the main loop then runs options_menu (src/menu.s).
;
; Memory: the code and its data are in the INPUT segment (bank 2); input_pads
; is in SYSRAM (bank 0). The code runs with the data bank = its own bank
; (absolute addresses), reaches other banks with long addresses, and uses no
; direct page, so it keeps the caller's D. Only the disk calls set D = 0
; (src/input_disk_bridge.s).
;
; Hardware rules (Apple IIgs Hardware Reference; Second Sight reference
; docs/reference/z180-io-ports.md, "Apple event addresses"):
;   - None of the registers that the play reads (KBD, KBDSTRB, KEYMODREG,
;     DATAREG, KMSTATUS, MOUSEDATA, BUTN0, BUTN1, PADDL0, PADDL1, PTRIG,
;     VERTCNT, the slot I/O of the adapter, never in slot 3) raises a Second
;     Sight event, so the input never disturbs the packet stream of the card.
;
; Routines (the interface, JSL):
;   input_start    the devices and the settings at the start
;   input_tick     one DOC timer tick: the event time and the J13 work
;   input_capture  the ADB capture (from each interrupt)
;   input_frame    the pads of one frame, and the menu key
;   input_idle     the joystick axes, in the main loop's wait
;   input_keep_holes  the screen holes of the boot (src/input_disk_bridge.s)
;   options_menu   the options menu (src/menu.s)
;   monitor_sense  the monitor sense byte of the card's firmware, for the
;                  clock at the start (src/menu.s)
;   command_ready, command_done  the handshakes of a card command (src/menu.s)
; Routines (in this file, JSR):
;   input_sample   one sample: the J13 mode, the events up to this tick, the devices
;   drain          apply the events of the ring up to inputUntil
;   drain_transition  an edge that must wait for the next drain
; The other files of the input (included below, in the scope of this
; file): input_bindings.s, input_adb.s, input_j13.s, input_devices.s,
; input_settings.s, input_audio.s, input_disk.s, input_disk_bridge.s,
; menu.s, menu_text.inc.

.include "settings.inc"

; input_pads: the pads of this frame, for the game (src/frame.s read_pads):
; byte 0 player 1, byte 1 player 2; a bit is 1 while its button is pressed,
; in the original's order (PAD_A $80, PAD_B $40, PAD_SELECT $20, PAD_START
; $10, PAD_UP $08, PAD_DOWN $04, PAD_LEFT $02, PAD_RIGHT $01). input_frame
; writes it; the game reads it.
.pushseg
.segment "SYSRAM"
input_pads: .res 2
.popseg

.a8
.i16
.scope input
KEY_DRAIN_MAX = 4096         ; input_start: the most DATAREG bytes of the boot to drop
J13_ESCAPE = 0               ; j13Mode: the J13 code looks only for ESC
J13_MENU = 1                 ; j13Mode: the options menu and the title: every J13 key
J13_PLAY = 2                 ; j13Mode: the play reads the J13 rows each frame

; ---------------------------------------------------------------------------
; input_start: start the input at the start of the game: forget the held
; keys, keep the firmware work areas of the disk (for the settings save),
; find the J13 keyboard, empty the ADB GLU and set its modes, then the
; settings (checked, or the defaults) with the bindings and the sound
; levels. With an ADB keyboard the game asks for the keys itself (no
; keyboard poll by the microcontroller, the keyboard's service request on);
; else the microcontroller polls the keyboard (KBD, for the J13 code). The
; capture starts at the end (ready), and the GLU's data and mouse
; interrupts go on.
;
; Why the interrupts: each GLU byte is read at the interrupt that it
; raises, as the firmware's own ADB code reads them (Apple IIgs Firmware
; Reference, chapter 9: each microcontroller status byte interrupts the
; system), not up to a DOC tick (4.2 ms) later.
;
; Why the drain: DATAREG can still hold bytes of the boot (replies and
; status bytes for the firmware); they are read and dropped, so the first
; byte that the capture reads belongs to its own talks.
;
; In:       A8 X16, D = SYSTEM_PAGE, DBR = 0 (startup, after clock_start)
;           settings   the block that the boot loader read, or the defaults
; Out:      ready = 1; input_pads = 0; the sound levels sent (sound_set_mix);
;           the GLU's data and mouse interrupts on (KMSTATUS)
; Changes:  A, X, Y; keyHeld, firmwareState, the J13 state; the GLU modes;
;           the J13 keyboard settings; the settings and bindings (defaults)
; Keeps:    D, DBR, the widths, the interrupt flag
; Time:     once, at the start
; Original: none
; ---------------------------------------------------------------------------
input_start:
  php
  sei                           ; the capture must not run before ready
  ax16
  phb
  phk
  plb                           ; DBR = this bank
  ldx #KEY_CODES-1
  a8
  lda #0
@held:
  sta a:.loword(keyHeld),x      ; no key held by any source
  dex
  bpl @held
  a16
  jsr .loword(settings_fw_keep) ; the firmware's areas of bank $E1, as the boot left them
  jsl J13Init
  a8
  ; The bytes that the GLU still holds from the boot are dropped.
  ldy #KEY_DRAIN_MAX
@drain:
  lda f:KMSTATUS
  and #KM_DATA_FULL
  beq @modes
  lda f:DATAREG
  dey
  bne @drain
@modes:
  ; An ADB keyboard: the game talks to it (no GLU keyboard poll, its
  ; service request on). Else the GLU polls the keyboard (KBD).
  lda a:.loword(j13AdbPresent)
  beq @compat
  lda #GLU_SET_MODES
  jsr .loword(sendBounded)
  lda #GLU_NO_KEY_POLL          ; the mouse poll stays on
  jsr .loword(sendBounded)
  lda #GLU_SRQ_ON+ADB_KEYBOARD
  jsr .loword(sendBounded)
  bra @ready
@compat:
  lda #GLU_CLEAR_MODES          ; the GLU polls the keyboard (KBD)
  jsr .loword(sendBounded)
  lda #GLU_NO_KEY_POLL
  jsr .loword(sendBounded)
@ready:
  a16
  jsl J13Prime
  jsl J13Menu
  jsr .loword(defaults)         ; the settings, the sound levels, the bindings
  a8
  lda #0
  sta f:input_pads              ; no button pressed
  sta f:input_pads+1
  lda #1
  sta a:.loword(ready)          ; the capture may run (input_capture)
  lda #KM_MOUSE_IRQ|KM_DATA_IRQ
  sta f:KMSTATUS                ; each ADB byte interrupts (input_capture)
  plb
  plp
  rtl

; ---------------------------------------------------------------------------
; input_tick: one DOC timer tick: count it (inputClock, the time of the
; events) and run the J13 work of a tick (the send alarm of a row read; in
; J13_PLAY the keys and the row batch).
;
; In:       A8 X16, D = SOUND_PAGE, DBR = 0 (src/clock.s clock_irq, timer
;           ticks only); the interrupt saved the registers
; Out:      inputClock + 1
; Changes:  A, X, Y
; Keeps:    D, DBR, A8 X16
; Time:     about 50 cycles without a J13 keyboard (counted from the 65816
;           cycle table); with one, sendAlarm, or in J13_PLAY j13Irq
; Original: none
; ---------------------------------------------------------------------------
input_tick:
  phb
  phk
  plb                           ; DBR = this bank
  lda a:.loword(ready)
  beq @done                     ; before input_start: no tick
  ax16
  inc a:.loword(inputClock)
  ; The J13 work of a tick (none without a J13 keyboard).
  lda a:.loword(j13Available)
  beq @j13_done
  lda a:.loword(j13SendTimer)
  beq :+
  jsr .loword(sendAlarm)        ; a row read owns the GLU: its next byte
:
  lda a:.loword(j13Mode)
  cmp #J13_PLAY
  bne @j13_done
  jsr .loword(readControllerClock)
  jsr .loword(j13Irq)           ; the keys, and the row batch when it is due
@j13_done:
  a8
@done:
  plb
  rtl

; ---------------------------------------------------------------------------
; input_capture: the ADB capture, at the end of each interrupt (the DOC
; timer's and the ADB GLU's). It reads the ADB GLU when it has work: a byte
; in DATAREG or MOUSEDATA, a keyboard that asks for a talk, or a row read
; that owns the GLU (src/input_adb.s CaptureInput, src/input_j13.s J13Pump).
; Its reads of DATAREG and MOUSEDATA end the GLU's interrupt.
;
; In:       A8 X16, D = SOUND_PAGE, DBR = 0 (src/clock.s clock_irq); the
;           interrupt saved the registers
; Out:      events in inputRing
; Changes:  A, X, Y
; Keeps:    D, DBR, A8 X16
; Time:     about 75 cycles and one KMSTATUS read with no work (counted
;           from the 65816 cycle table; each I/O access also waits for the
;           1 MHz bus); CaptureInput about 125 cycles for each key byte
; Original: none
; ---------------------------------------------------------------------------
input_capture:
  phb
  phk
  plb                           ; DBR = this bank
  lda a:.loword(ready)
  beq @done                     ; before input_start: no capture
  ax16
  jsr .loword(capture_adb)
  a8
@done:
  plb
  rtl

; ---------------------------------------------------------------------------
; capture_adb: read the ADB GLU when it has work: a row read that owns it
; (J13Pump), or a byte, or a keyboard that asks for a talk (CaptureInput).
; The disk bridge calls it after a block call too.
;
; In:       A16 X16, DBR = this bank
; Out:      events in inputRing; A16
; Changes:  A, X, Y
; Keeps:    D, DBR
; Time:     about 40 cycles and one KMSTATUS read with no work
; Original: none
; ---------------------------------------------------------------------------
.a16
capture_adb:
  lda a:.loword(j13Owner)
  bne @work
  a8
  lda f:KMSTATUS
  and #KM_MOUSE_FULL|KM_DATA_FULL
  a16
  bne @work
  lda a:.loword(keyPending)
  bne @work
  rts
@work:
  lda a:.loword(j13Owner)
  beq :+
  jsr .loword(J13Pump)          ; a row read: its next step
:
  jsl CaptureInput              ; returns A16
  rts

; ---------------------------------------------------------------------------
; input_frame: the pads of this frame and the menu key, once for each frame
; of the original. It samples the input (input_sample), then writes
; input_pads: the held buttons and the buttons pressed since the last frame
; (keyLatch), so a press and release inside one frame shows once. A button
; that is held when the options menu closes does not count until it is let
; go (menuHeld): the key or button that closed the menu must not reach the
; game. The menu takes each pad or joystick button as RETURN (src/menu.s
; menu_key), and those buttons are game buttons too: the default bindings
; give pad START, SELECT, B and Y and both joystick buttons a game action
; (src/default_bindings.inc).
;
; In:       A8 I8, D = SYSTEM_PAGE, DBR = 0 (src/game.s main_loop)
; Out:      input_pads  player 1, player 2 (bit set: pressed)
;           carry set   the menu key went down in this frame
;           A8 I8, D and DBR as they came
; Changes:  A, X, Y; the latches; menuHeld, frameMask, menuOpen,
;           menuWasDown; inputFrames + 1
; Time:     about 330 cycles and two button reads with no events, no J13
;           keyboard, no pad and no joystick read (counted from the 65816
;           cycle table); each key event about 1,000 more (drain); a SNES
;           MAX read about 2,700 cycles and 33 slot accesses; a joystick
;           read here (no input_idle in this frame) 1.78 ms (PADDLE_HIGH
;           VERTCNT steps)
; Original: none (the original reads its pads at $8E5C, src/frame.s
;           read_pads, from input_pads)
; ---------------------------------------------------------------------------
.a8
.i8
input_frame:
  php
  phb
  phk
  plb                           ; DBR = this bank
  ax16
  jsr .loword(input_sample)
  ; A button held since the menu leaves menuHeld when it is let go; the
  ; game sees the held buttons and the latched presses of the others.
  lda a:.loword(heldCommand)
  and a:.loword(menuHeld)
  sta a:.loword(menuHeld)
  eor #$ffff
  sta a:.loword(frameMask)
  lda a:.loword(heldCommand)
  ora a:.loword(keyLatch)
  and a:.loword(frameMask)
  sta f:input_pads              ; player 1 low byte, player 2 high byte
  ; The menu key: a press opens the menu once; it must be let go before it
  ; opens the menu again (menuWasDown).
  stz a:.loword(menuOpen)
  lda a:.loword(systemCommand)
  ora a:.loword(systemLatch)
  and #SYSTEM_MENU
  bne @menu_down
  stz a:.loword(menuWasDown)    ; let go: the next press opens the menu
  bra @latches
@menu_down:
  lda a:.loword(menuWasDown)
  bne @latches
  lda #1
  sta a:.loword(menuWasDown)
  sta a:.loword(menuOpen)
@latches:
  ; The latches start again for the next frame.
  stz a:.loword(keyLatch)
  stz a:.loword(systemLatch)
  inc a:.loword(inputFrames)
  plb
  plp                           ; A8 I8, and the caller's interrupt flag
  lda f:menuOpen
  lsr a                         ; carry = menuOpen
  rtl

; ---------------------------------------------------------------------------
; input_idle: the joystick axes in the main loop's wait for the next frame,
; once a frame: the read waits for the paddle timers (1.78 ms), so it
; belongs in time that the game does not use. Nothing with no joystick.
;
; In:       any widths, D, DBR
; Out:      the joystick's device keys; joyUpdate = inputFrames
; Changes:  nothing (all registers kept)
; Time:     about 100 cycles with no read; once a frame with a joystick
;           1.78 ms
; Original: none
; ---------------------------------------------------------------------------
input_idle:
  php
  ax16
  pha
  phx
  phy
  phb
  phk
  plb
  a8
  jsr .loword(devices_idle)
  ax16
  plb
  ply
  plx
  pla
  plp
  rtl

; ---------------------------------------------------------------------------
; input_sample: one sample of the input: set the J13 mode and let the J13
; code read, apply the events up to this tick, then read the devices without
; events (the joystick and the pads). The menu calls it as well.
;
; The J13 mode: the options menu and the title (mode MODE_TITLE, which
; also plays the demo) read every J13 key (J13_MENU), so ESC, START and
; SELECT work there before J13 play is on; the play reads the J13 rows when
; J13 play is on (J13_PLAY), else only ESC (J13_ESCAPE).
;
; In:       A16 X16, DBR = this bank
; Out:      heldCommand, systemCommand, keyLatch, systemLatch, keyAction
; Changes:  A, X, Y; inputUntil, inputLimit; the J13 mode
; Keeps:    D, DBR
; Time:     about 45 cycles with no J13 keyboard, and the drain and
;           devices_sample
; Original: none
; ---------------------------------------------------------------------------
.a16
.i16
input_sample:
  ; The events up to this tick; the J13 mode of this sample.
  lda a:.loword(inputClock)
  sta a:.loword(inputUntil)
  lda a:.loword(j13Available)
  beq @events
  lda a:.loword(menuMode)
  bne @menu
  lda f:mode                    ; the original's mode (src/game_ram.inc)
  and #$00ff
  cmp #MODE_TITLE
  beq @menu
  lda a:.loword(j13Enabled)
  beq @raw
  lda #J13_PLAY
  bra @mode
@menu:
  lda #J13_MENU
  bra @mode
@raw:
  lda #J13_ESCAPE
@mode:
  cmp a:.loword(j13Mode)
  beq @same
  jsl setMode
@same:
  lda a:.loword(j13Mode)
  cmp #J13_PLAY
  bne @poll
  jsl J13Frame
  bra @events
@poll:
  jsl J13Poll
@events:
  ; The events in the ring when the drain starts, then the devices.
  lda a:.loword(inputHead)
  sta a:.loword(inputLimit)
  jsr .loword(drain)
  jsr .loword(devices_sample)
  rts

; ---------------------------------------------------------------------------
; drain: apply the events of inputRing before inputLimit with a time of
; inputUntil or less. A key byte changes the held bit of its source
; (keyHeld) and the actions of its bindings (apply_key_mask): a key stays
; held until all its sources let it go. A press of an action that this
; drain released, or a release of one that it pressed, waits for the next
; drain (drain_transition), so each frame sees each edge. src/input_adb.s
; gives the ring entry.
;
; In:       A16 X16, DBR = this bank; inputLimit, inputUntil
; Out:      inputTail; keyHeld; heldCommand, systemCommand, keyLatch,
;           systemLatch; keyAction, actionSource, inputSerial (the last press)
; Changes:  A, X, Y; keySource, keyRaw, maskPressed, maskIndex, maskWork,
;           maskBit, drainPress, drainRelease
; Keeps:    D, DBR, A16
; Time:     about 40 cycles with no event; about 1,000 for each key event
;           (drain_transition and apply_key_mask included; counted from the
;           65816 cycle table)
; Original: none
; ---------------------------------------------------------------------------
drain:
  stz a:.loword(drainPress)
  stz a:.loword(drainPress+2)
  stz a:.loword(drainRelease)
  stz a:.loword(drainRelease+2)
@loop:
  ; The next event, unless the ring is empty or the event came later.
  ldx a:.loword(inputTail)
  cpx a:.loword(inputLimit)
  bne :+
  jmp .loword(@done)            ; no more events
:
  lda a:.loword(inputUntil)
  sec
  sbc a:.loword(inputRing+INPUT_TIME),x
  bpl :+
  jmp .loword(@done)            ; a later event: the next drain applies it
:
  ; Its source bit (keyHeld), the key code, and the press or the release.
  lda a:.loword(inputRing+INPUT_TYPE),x
  lsr a
  inc a                         ; INPUT_KEY: HELD_ADB; INPUT_J13: HELD_J13
  sta a:.loword(keySource)
  lda a:.loword(inputRing+INPUT_VALUE),x
  sta a:.loword(keyRaw)
  and #KEY_CODES-1
  tay
  a8
  lda a:.loword(keyRaw)
  bmi @release                  ; bit 7: a release
  lda a:.loword(keyHeld),y
  and a:.loword(keySource)
  bne @unchanged                ; the source holds it already
  lda #1
  sta a:.loword(maskPressed)
  jsr .loword(drain_transition)
  bcc :+
  a16
  jmp .loword(@done)
:
  .a8
  lda a:.loword(keyHeld),y
  ora a:.loword(keySource)
  sta a:.loword(keyHeld),y
  a16
  lda a:.loword(keyRaw)         ; the last key, for the menu
  sta a:.loword(keyAction)
  lda a:.loword(keySource)
  sta a:.loword(actionSource)
  inc a:.loword(inputSerial)
  a8
  bra @apply
@release:
  .a8
  lda a:.loword(keyHeld),y
  and a:.loword(keySource)
  beq @unchanged                ; the source does not hold it
  stz a:.loword(maskPressed)
  jsr .loword(drain_transition)
  bcc :+
  a16
  jmp .loword(@done)
:
  .a8
  lda a:.loword(keySource)
  eor #$ff
  and a:.loword(keyHeld),y
  sta a:.loword(keyHeld),y
@apply:
  .a8
  lda a:.loword(maskPressed)    ; X: the mask from drain_transition
  jsr .loword(apply_key_mask)
@unchanged:
  ; The event is done: the tail moves past it.
  a16
  lda a:.loword(inputTail)
  clc
  adc #INPUT_EVENT_SIZE
  and #INPUT_RING_SIZE-1
  sta a:.loword(inputTail)
  jmp .loword(@loop)
@done:
  .a16
  rts

; ---------------------------------------------------------------------------
; drain_transition: the edge of the key keyRaw from keySource. Carry set when
; the edge must wait for the next drain: a press of an action that this
; drain released, or a release of one that it pressed. Else its actions go
; into drainPress or drainRelease, and X is the offset of its mask.
;
; In:       A8 X16, DBR = this bank; keyRaw, keySource; maskPressed 1 a
;           press, 0 a release
; Out:      carry; X = the physical key (KEYBOARD2 + the code for a J13 key)
;           times MASK_SIZE; A8
; Changes:  A, X; maskIndex, drainPress, drainRelease
; Keeps:    Y, D, DBR
; Time:     about 125 cycles (counted from the 65816 cycle table)
; Original: none
; ---------------------------------------------------------------------------
.a8
drain_transition:
  a16
  lda a:.loword(keySource)
  dec a
  xba
  lsr a                         ; HELD_J13: KEYBOARD2; HELD_ADB: 0
  sta a:.loword(maskIndex)
  lda a:.loword(keyRaw)
  and #KEY_CODES-1
  ora a:.loword(maskIndex)
  asl a
  asl a                         ; times MASK_SIZE
  tax
  a8
  lda a:.loword(maskPressed)
  beq @up
  a16
  lda a:.loword(commandMasks),x
  and a:.loword(drainRelease)
  bne @blocked
  lda a:.loword(commandMasks+2),x
  and a:.loword(drainRelease+2)
  bne @blocked
  lda a:.loword(commandMasks),x
  ora a:.loword(drainPress)
  sta a:.loword(drainPress)
  lda a:.loword(commandMasks+2),x
  ora a:.loword(drainPress+2)
  sta a:.loword(drainPress+2)
  bra @ok
@up:
  a16
  lda a:.loword(commandMasks),x
  and a:.loword(drainPress)
  bne @blocked
  lda a:.loword(commandMasks+2),x
  and a:.loword(drainPress+2)
  bne @blocked
  lda a:.loword(commandMasks),x
  ora a:.loword(drainRelease)
  sta a:.loword(drainRelease)
  lda a:.loword(commandMasks+2),x
  ora a:.loword(drainRelease+2)
  sta a:.loword(drainRelease+2)
@ok:
  a8
  clc
  rts
@blocked:
  a8
  sec
  rts
.assert HELD_J13 = 2 .and KEYBOARD2 = 128 .and MASK_SIZE = 4, error ; the DEC, XBA, LSR and the ASLs above

.include "input_bindings.s"
.include "input_adb.s"
.include "input_j13.s"
.include "input_devices.s"
.include "input_settings.s"
.include "input_audio.s"
.include "input_disk.s"
.include "input_disk_bridge.s"
.include "menu.s"
.include "menu_text.inc"

; The input state. Each variable: its users.
.a16
ready: .word 0                  ; 1 after input_start: input_tick and input_capture may run
inputClock: .word 0             ; input_tick: the ticks since input_start (the event times)
inputFrames: .word 0            ; input_frame: the frames since input_start
inputHead: .word 0              ; inputRing: the offset of the next event (the capture)
inputTail: .word 0              ; inputRing: the offset of the next event to apply (drain)
inputLimit: .word 0             ; drain: the head when the drain starts
inputUntil: .word 0             ; drain: the last time to apply
inputSerial: .word 0            ; the count of presses (the menu sees a key)
inputRing: .res INPUT_RING_SIZE ; the events (drain gives the entry)
keyRaw: .word 0                 ; drain: the key byte
keySource: .word HELD_ADB       ; drain: the keyHeld bit of the key's source
keyAction: .word NONE           ; the last key or device key pressed (the menu)
actionSource: .word 0           ; the SOURCE_* of keyAction (the menu)
heldCommand: .word 0            ; the held action bits: player 1 low byte, player 2 high byte
systemCommand: .word 0          ; the held system bits (SYSTEM_MENU)
keyLatch: .word 0               ; the player bits pressed since the last frame
systemLatch: .word 0            ; the system bits pressed since the last frame
menuHeld: .word 0               ; the player bits held when the menu closed (input_frame)
frameMask: .word 0              ; input_frame: the bits that the game may see
menuOpen: .word 0               ; input_frame: 1 when the menu key went down
menuWasDown: .word 0            ; 1: the menu key is held since it opened or closed the menu
drainPress: .res MASK_SIZE      ; drain: the actions that it pressed
drainRelease: .res MASK_SIZE    ; drain: the actions that it released
maskIndex: .word 0              ; drain_transition: KEYBOARD2 or 0
menuMode: .word 0               ; 1 while the options menu shows
keyHeld: .res KEY_CODES         ; each key code: the HELD_* bits of its sources
.assert systemCommand = heldCommand+2 .and systemLatch = keyLatch+2, error ; apply_key_mask: byte 2 is the system byte
.endscope

; The interface: the entries that the rest of the game calls.
input_start = input::input_start
input_tick = input::input_tick
input_capture = input::input_capture
input_frame = input::input_frame
input_idle = input::input_idle
input_keep_holes = input::input_keep_holes
options_menu = input::options_menu
monitor_sense = input::monitor_sense
command_ready = input::command_ready
command_done = input::command_done
