; The input settings: one SETTINGS_SIZE image holds all of them
; (src/settings.inc gives the layout; on the disk the file SSMARIO.CONFIG).
; At the start (input_start) defaults checks the image and applies it; the
; options menu changes it and compiles the bindings again. The compiled
; binding columns change only at a load or an edit. Part of the input
; (src/input.s), in its scope.
;
; The compiled bindings: four columns of BIND_COUNT words, one entry for
; each binding record, written by compile_bindings and read by
; compile_masks (src/input_bindings.s) and J13ValidateTracked
; (src/input_j13.s):
;   boundKeys     the ADB key code, or the device key state
;                 (DEVICE_JOYSTICK, DEVICE_PAD1, DEVICE_PAD2 + the device
;                 key); BOUND_FREE for a free record
;   boundSources  the SOURCE_* of the record
;   boundBits     the player bits of its action (input_pads order)
;   boundSystem   the system bits of its action (SYSTEM_MENU)
;
; Routines:
;   defaults          the settings at the start: checked, the sound, J13, the video standard, the bindings
;   compile_bindings  the binding columns and the slot of the SNES MAX reads
.a16
.i16
.include "default_bindings.inc"
LANGSEL_PAL = $10            ; LANGSEL: the 50 Hz display standard
NTSC_BEAM_PERIOD = 131       ; beamPeriod at 60 Hz: 262 lines, two a VERTCNT step
PAL_BEAM_PERIOD = 156        ; beamPeriod at 50 Hz: 312 lines
SLOTS = 7                    ; a SNES MAX adapter in a slot below this: 1-6, not SS_SLOT
SS_SLOT = 3                  ; the slot of the Second Sight (its host registers are slot 3's
                             ; device select range): never an adapter
BOUND_FREE = $FFFF           ; boundKeys: a free record (KEY_CODES or more: compile_masks skips it)

; ---------------------------------------------------------------------------
; defaults: the settings at the start: checked (the defaults when the magic
; or the checksum is wrong), the sound levels, the J13 settings, the beam
; period of the video standard, the bindings.
;
; In:       A16 X16, DBR = this bank, interrupts off (input_start)
; Out:      settings checked; the sound levels sent; j13Enabled, j13Manual,
;           j13MenuSeen; beamPeriod; the bindings compiled
; Changes:  A, X, Y
; Keeps:    D, DBR, A16 X16
; Original: none
; ---------------------------------------------------------------------------
defaults:
  jsr .loword(settings_check)
  jsr .loword(mix_settings)
  jsl J13SettingsLoad
  ; The VERTCNT steps of a picture: PAL_BEAM_PERIOD on a 50 Hz machine
  ; (beamPeriod holds NTSC_BEAM_PERIOD from the assembly).
  a8
  lda f:LANGSEL
  and #LANGSEL_PAL
  beq :+
  lda #PAL_BEAM_PERIOD
  sta a:.loword(beamPeriod)
:
  a16
  jsr .loword(compile_bindings)
  rts

; ---------------------------------------------------------------------------
; compile_bindings: the binding columns (boundKeys, boundSources, boundBits,
; boundSystem) from the BIND_COUNT records, and the slot of the SNES MAX
; reads (the low address byte of pad_latch, pad_data and pad_clock); a slot
; that cannot hold the adapter becomes 0. Then compile_masks.
;
; Self-changing code: the slot goes into the operands of pad_latch,
; pad_data and pad_clock (src/input_devices.s), so pad_read reaches the
; adapter with long addresses and no index.
;
; In:       A16 X16, DBR = this bank
; Out:      the columns, commandMasks; settings+SET_SNES_SLOT checked
; Changes:  A, X, Y
; Keeps:    D, DBR, A16 X16
; Time:     only at a load or an edit, never in a frame
; Original: none
; ---------------------------------------------------------------------------
compile_bindings:
  ldx #0                        ; the column entry (2 bytes)
  ldy #0                        ; the record (BINDING_SIZE bytes)
@binding:
  ; The key and the source; a device key becomes its device key state.
  lda a:.loword(settings+SET_BINDINGS+BIND_KEY),y
  and #$00ff
  sta a:.loword(boundKeys),x
  lda a:.loword(settings+SET_BINDINGS+BIND_SOURCE),y
  and #$00ff
  sta a:.loword(boundSources),x
  cmp #SOURCE_DEVICE_FIRST
  bcc @keyboard
  sec
  sbc #SOURCE_DEVICE_FIRST
  asl a
  asl a
  asl a
  asl a                         ; times DEVICE_KEYS_EACH: the first state of the device
  clc
  adc a:.loword(boundKeys),x
  sta a:.loword(boundKeys),x
@keyboard:
  ; The bits of the action (actionMask, actionSystem); an action of
  ; BIND_ACTIONS or more is a free record.
  stz a:.loword(boundBits),x
  stz a:.loword(boundSystem),x
  phy
  lda a:.loword(settings+SET_BINDINGS+BIND_ACTION),y
  and #$00ff
  cmp #BIND_ACTIONS
  bcs @unused
  asl a
  tay
  lda a:.loword(actionMask),y
  sta a:.loword(boundBits),x
  lda a:.loword(actionSystem),y
  sta a:.loword(boundSystem),x
  bra @next
@unused:
  lda #BOUND_FREE               ; a free record: no key
  sta a:.loword(boundKeys),x
@next:
  ply
  iny
  iny
  iny
  iny                           ; BINDING_SIZE
  inx
  inx
  cpx #BIND_COUNT*2
  bcc @binding
  ; The slot of the SNES MAX adapter in the three slot addresses.
  a8
  lda a:.loword(settings+SET_SNES_SLOT)
  beq @slot_off
  cmp #SLOTS
  bcs @slot_off
  cmp #SS_SLOT
  beq @slot_off
  asl a
  asl a
  asl a
  asl a                         ; times SLOT_DEVICE_SIZE
  clc
  adc #.lobyte(SLOT_DEVICE)
  sta f:pad_data+1
  sta f:pad_latch+1
  inc a                         ; PAD_CLOCK
  sta f:pad_clock+1
  bra @ready
@slot_off:
  stz a:.loword(settings+SET_SNES_SLOT)
@ready:
  a16
  jmp .loword(compile_masks)
.assert BINDING_SIZE = 4 .and DEVICE_KEYS_EACH = 16 .and PAD_CLOCK = 1, error ; the INYs, ASLs and INC above
.assert SLOT_DEVICE_SIZE = 16 .and (SLOT_DEVICE+SLOTS*SLOT_DEVICE_SIZE) & $FF00 = SLOT_DEVICE & $FF00, error ; one low byte
.assert BOUND_FREE >= KEY_CODES, error

; The bits of each BIND_ACTION: the input_pads bits (player 1 low byte,
; player 2 high byte) and the system bits.
actionMask:
  .word PAD_LEFT,PAD_RIGHT,PAD_UP,PAD_DOWN,PAD_A,PAD_B,PAD_START,PAD_SELECT
  .word PAD_LEFT<<8,PAD_RIGHT<<8,PAD_UP<<8,PAD_DOWN<<8,PAD_A<<8,PAD_B<<8,PAD_START<<8,PAD_SELECT<<8
  .word 0                       ; ACTION_MENU
.assert *-actionMask = BIND_ACTIONS*2, error
actionSystem:
  .res 2*::PLAYER_ACTIONS*2, 0  ; the players' actions
  .word SYSTEM_MENU             ; ACTION_MENU
.assert *-actionSystem = BIND_ACTIONS*2, error
.assert ACT_LEFT = 0 .and ACT_RIGHT = 1 .and ACT_UP = 2 .and ACT_DOWN = 3, error ; the table order
.assert ACT_A = 4 .and ACT_B = 5 .and ACT_START = 6 .and ACT_SELECT = 7, error

; The compiled bindings (the header of this file gives the columns).
boundKeys: .res ::BIND_COUNT*2
boundBits: .res ::BIND_COUNT*2
boundSources: .res ::BIND_COUNT*2
boundSystem: .res ::BIND_COUNT*2

; settings: the settings image (src/settings.inc) with the defaults. The
; boot loader reads SSMARIO.CONFIG over it; scripts/boot_disk.py writes the
; file from these bytes with their checksum (the word here stays 0).
settings:
  .byte "SMBKEYS",SETTINGS_VERSION ; SET_MAGIC
.assert *-settings = SET_J13, error
  .byte 0                       ; SET_J13: J13 play off, not chosen
  .byte 0                       ; SET_SNES_SLOT: no adapter
  .byte JOY_PLAYER_DEFAULT      ; SET_JOY_PLAYER
  .byte MIX_LEVEL_DEFAULT       ; SET_MUSIC_LEVEL
  .byte MIX_LEVEL_DEFAULT       ; SET_EFFECTS_LEVEL
.assert *-settings = SET_EFFECTS_LEVEL+1, error
  .res ::SET_BINDINGS-(*-settings),0
  default_bindings
.assert *-settings = SET_BINDINGS_END, error
  .res ::SETTINGS_CHECKSUM-(*-settings),0
  .word 0                       ; the checksum: settings_sum
.assert *-settings = SETTINGS_SIZE, error
.assert SET_SNES_SLOT = SET_J13+1 .and SET_JOY_PLAYER = SET_J13+2 .and SET_MUSIC_LEVEL = SET_J13+3, error
