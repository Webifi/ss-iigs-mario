; The key bindings: each physical key gets its action mask (the player bits
; and the system bits) once, at a load or an edit (compile_masks); at run
; time a key only changes the counts of its actions (apply_key_mask), so two
; keys of one action and two bindings of one key work together. Part of the
; input (src/input.s), in its scope; the main loop and the menu call these,
; never the interrupt.
;
; The physical keys, each with a MASK_SIZE entry in commandMasks:
;   0 to KEY_CODES-1                      the ADB keyboard, by ADB key code
;   KEYBOARD2 to KEYBOARD2+KEY_CODES-1    the J13 keyboard, by ADB key code
;   DEVICE_KEYS to PHYSICAL_KEYS-1        the device keys (deviceKeys): the
;                                         joystick, then pad one, pad two
; A mask entry: the player bits word (player 1 low byte, player 2 high
; byte, in the order of input_pads), then the system bits word
; (SYSTEM_MENU). actionRefs counts, for each of the ACTION_BYTES*8 bits, the
; keys that hold it.
;
; Routines:
;   compile_masks    commandMasks from the compiled bindings; the held keys count again
;   mask_store       one binding's bits into the mask of its physical key
;   apply_key_mask   a physical key pressed or let go: the counts and the held bits
;   set_device       a device key state: a change applies its mask
.a16
.i16
KEY_CODES = 128              ; the ADB key codes of one keyboard
KEYBOARD2 = 128              ; the physical keys of the J13 keyboard start here
DEVICE_KEYS = 256            ; the physical keys of the devices start here
; The device key states (deviceKeys): DEVICE_KEYS_EACH for each device. (A
; constant that a .res needs names the global symbols with "::": ca65 finds
; a global from inside a scope only at the end of the scope.)
DEVICE_JOYSTICK = (::SOURCE_JOYSTICK-::SOURCE_DEVICE_FIRST)*::DEVICE_KEYS_EACH ; the joystick
DEVICE_PAD1 = (::SOURCE_PAD1-::SOURCE_DEVICE_FIRST)*::DEVICE_KEYS_EACH  ; pad one
DEVICE_PAD2 = (::SOURCE_PAD2-::SOURCE_DEVICE_FIRST)*::DEVICE_KEYS_EACH  ; pad two
DEVICE_STATES = (::SOURCE_COUNT-::SOURCE_DEVICE_FIRST)*::DEVICE_KEYS_EACH ; all of them
PHYSICAL_KEYS = DEVICE_KEYS+DEVICE_STATES
MASK_SIZE = 4                ; the player bits word, the system bits word
ACTION_BYTES = 3             ; the action bits that actionRefs counts: 24
SYSTEM_MENU = $01            ; the system bits: the menu key

; ---------------------------------------------------------------------------
; compile_masks: commandMasks from the compiled bindings (boundKeys,
; boundSources, boundBits, boundSystem); ESC opens the menu on both
; keyboards whatever the bindings say; then the keys that are held count
; again with their masks.
;
; In:       A16 X16, DBR = this bank; the compiled bindings (src/input_settings.s)
; Out:      commandMasks, actionRefs, heldCommand, systemCommand; the latches 0
; Changes:  A, X, Y; maskPressed, maskWork, maskBit
; Keeps:    D, DBR, A16 X16
; Time:     only at a load or an edit, never in a frame
; Original: none
; ---------------------------------------------------------------------------
compile_masks:
  ; Every mask and every count to 0, and no action held.
  ldx #PHYSICAL_KEYS*MASK_SIZE-2
@clear:
  stz a:.loword(commandMasks),x
  dex
  dex
  bpl @clear
  ldx #ACTION_BYTES*8-2
@refs:
  stz a:.loword(actionRefs),x
  dex
  dex
  bpl @refs
  stz a:.loword(heldCommand)
  stz a:.loword(systemCommand)
  stz a:.loword(keyLatch)
  stz a:.loword(systemLatch)
  ; Each binding's bits join the mask of its physical key: a device key
  ; state, or the key on the ADB keyboard, the J13 keyboard or both.
  ldx #0
@binding:
  lda a:.loword(boundKeys),x
  cmp #KEY_CODES
  bcs @next                     ; a free record
  lda a:.loword(boundSources),x
  cmp #SOURCE_DEVICE_FIRST
  bcc @keyboard
  lda a:.loword(boundKeys),x    ; a device key state
  ora #DEVICE_KEYS
  jsr .loword(mask_store)
  bra @next
@keyboard:
  bit #SOURCE_ADB
  beq :+
  lda a:.loword(boundKeys),x
  jsr .loword(mask_store)
:
  lda a:.loword(boundSources),x
  bit #SOURCE_J13
  beq @next
  lda a:.loword(boundKeys),x
  ora #KEYBOARD2
  jsr .loword(mask_store)
@next:
  inx
  inx
  cpx #BIND_COUNT*2
  bcc @binding
  ; ESC opens the menu on both keyboards, whatever the bindings say: the
  ; whole mask is replaced, so ESC gives no game action and the menu can
  ; always be reached.
  stz a:.loword(commandMasks+KEY_ESC*MASK_SIZE)
  stz a:.loword(commandMasks+(KEYBOARD2+KEY_ESC)*MASK_SIZE)
  lda #SYSTEM_MENU
  sta a:.loword(commandMasks+KEY_ESC*MASK_SIZE+2)
  sta a:.loword(commandMasks+(KEYBOARD2+KEY_ESC)*MASK_SIZE+2)
  ; The keys that are held count with their masks.
  ldx #0
@keys:
  lda a:.loword(keyHeld),x
  and #HELD_ADB
  beq :+
  phx
  txa
  asl a
  asl a                         ; times MASK_SIZE
  tax
  a8
  lda #1
  jsr .loword(apply_key_mask)
  a16
  plx
:
  lda a:.loword(keyHeld),x
  and #HELD_J13
  beq @advance
  phx
  txa
  ora #KEYBOARD2
  asl a
  asl a
  tax
  a8
  lda #1
  jsr .loword(apply_key_mask)
  a16
  plx
@advance:
  inx
  cpx #KEY_CODES
  bcc @keys
  ldx #0
@device:
  lda a:.loword(deviceKeys),x
  and #$00ff
  beq @device_next
  phx
  txa
  ora #DEVICE_KEYS
  asl a
  asl a
  tax
  a8
  lda #1
  jsr .loword(apply_key_mask)
  a16
  plx
@device_next:
  inx
  cpx #DEVICE_STATES
  bcc @device
  rts

; ---------------------------------------------------------------------------
; mask_store: the bits of the compiled binding X join the mask of the
; physical key A.
;
; In:       A16 X16, DBR = this bank; A the physical key; X the binding
;           times 2
; Out:      commandMasks of the key
; Changes:  A, Y
; Keeps:    X, D, DBR
; Original: none
; ---------------------------------------------------------------------------
mask_store:
  asl a
  asl a                         ; times MASK_SIZE
  tay
  lda a:.loword(boundBits),x
  ora a:.loword(commandMasks),y
  sta a:.loword(commandMasks),y
  lda a:.loword(boundSystem),x
  ora a:.loword(commandMasks+2),y
  sta a:.loword(commandMasks+2),y
  rts

; ---------------------------------------------------------------------------
; apply_key_mask: the physical key X / MASK_SIZE is pressed (A = 1) or let
; go (A = 0): each of its action bits counts up or down in actionRefs; the
; first press sets the bit in heldCommand and keyLatch, the last release
; clears it in heldCommand. Byte 2 of heldCommand and keyLatch is
; systemCommand and systemLatch (input.s keeps them next to each other).
;
; In:       A8 X16, DBR = this bank; A 1 or 0; X the physical key times
;           MASK_SIZE
; Out:      actionRefs, heldCommand, systemCommand, keyLatch, systemLatch;
;           A8
; Changes:  A, X, Y; maskPressed, maskWork, maskBit
; Keeps:    D, DBR
; Time:     about 700 cycles for a key with bits (it walks the 24 bits);
;           about 50 for a key with none (counted from the 65816 cycle
;           table)
; Original: none
; ---------------------------------------------------------------------------
.a8
apply_key_mask:
  ; The key's mask in maskWork; a key with no bit gives nothing.
  sta a:.loword(maskPressed)
  a16
  lda a:.loword(commandMasks),x
  sta a:.loword(maskWork)
  lda a:.loword(commandMasks+2),x
  sta a:.loword(maskWork+2)
  ora a:.loword(maskWork)
  beq @empty                    ; the key gives no action
  ; Each of the ACTION_BYTES * 8 bits: a press counts it up and, from 0,
  ; holds and latches it; a release counts it down and, at 0, lets it go.
  a8
  ldx #0                        ; the bit number (actionRefs)
  ldy #0                        ; the byte of the mask
@byte:
  lda #1
  sta a:.loword(maskBit)
@bit:
  lda a:.loword(maskWork),y
  and a:.loword(maskBit)
  beq @advance
  lda a:.loword(maskPressed)
  beq @up
  inc a:.loword(actionRefs),x
  lda a:.loword(actionRefs),x
  cmp #1
  bne @advance                  ; another key holds it already
  lda a:.loword(heldCommand),y
  ora a:.loword(maskBit)
  sta a:.loword(heldCommand),y
  lda a:.loword(keyLatch),y
  ora a:.loword(maskBit)
  sta a:.loword(keyLatch),y
  bra @advance
@up:
  lda a:.loword(actionRefs),x
  beq @advance
  dec a:.loword(actionRefs),x
  bne @advance                  ; another key still holds it
  lda a:.loword(maskBit)
  eor #$ff
  and a:.loword(heldCommand),y
  sta a:.loword(heldCommand),y
@advance:
  inx
  asl a:.loword(maskBit)
  bne @bit
  iny
  cpy #ACTION_BYTES
  bcc @byte
  rts
@empty:
  a8
  rts

; ---------------------------------------------------------------------------
; set_device: the device key state X becomes A (1 pressed, 0 not); a change
; applies its mask, and a press is the last key for the menu (keyAction =
; the device key, actionSource = its device, inputSerial + 1).
;
; In:       A8 X16, DBR = this bank; A 1 or 0; X a deviceKeys index
;           (DEVICE_JOYSTICK, DEVICE_PAD1 or DEVICE_PAD2 + the device key)
; Out:      deviceKeys; the actions (apply_key_mask); keyAction,
;           actionSource, inputSerial at a press
; Changes:  the flags; devicePressed, maskPressed, maskWork, maskBit
; Keeps:    A, X, Y (with B), D, DBR, the widths
; Time:     13 cycles with no change; with a change about 130 more and
;           apply_key_mask
; Original: none
; ---------------------------------------------------------------------------
set_device:
  cmp a:.loword(deviceKeys),x
  bne @change
  rts                           ; no change: nothing to apply
@change:
  ; The state to set; a press is the last key for the menu.
  php
  ax16
  pha
  phx
  phy
  a8
  sta a:.loword(deviceKeys),x
  sta a:.loword(devicePressed)
  cmp #0                        ; STA sets no flags: test the state to set
  beq @apply                    ; a release changes only the actions
  a16
  txa
  and #DEVICE_KEYS_EACH-1       ; the device key
  sta a:.loword(keyAction)
  txa
  lsr a
  lsr a
  lsr a
  lsr a
  clc
  adc #SOURCE_DEVICE_FIRST      ; the device
  sta a:.loword(actionSource)
  inc a:.loword(inputSerial)
@apply:
  ; The mask of the physical key DEVICE_KEYS + X.
  a16
  txa
  ora #DEVICE_KEYS
  asl a
  asl a                         ; times MASK_SIZE
  tax
  a8
  lda a:.loword(devicePressed)
  jsr .loword(apply_key_mask)
  ax16
  ply
  plx
  pla
  plp
  rts
.assert DEVICE_KEYS_EACH = 16, error ; the four LSRs above

; The binding state.
maskWork: .res MASK_SIZE        ; apply_key_mask: the mask of the key (player bits word, system bits word)
maskBit: .byte 0                ; apply_key_mask: the bit in work
maskPressed: .byte 0            ; apply_key_mask, drain: 1 a press, 0 a release
devicePressed: .byte 0          ; set_device: the state to apply
actionRefs: .res ACTION_BYTES*8 ; the keys that hold each action bit
deviceKeys: .res DEVICE_STATES  ; each device key: 1 pressed (set_device)
commandMasks: .res PHYSICAL_KEYS*MASK_SIZE ; each physical key: its action mask
.assert PHYSICAL_KEYS = DEVICE_KEYS+DEVICE_STATES .and DEVICE_KEYS = 2*KEY_CODES .and MASK_SIZE = 4, error
.assert DEVICE_STATES < KEY_CODES, error ; compile_masks: a device key state is below KEY_CODES, a free record not
