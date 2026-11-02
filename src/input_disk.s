; The settings on the disk: one block that the build keeps for them (the
; file SSMARIO.CONFIG, a seedling: its key block holds the data). Only SAVE
; of the options menu writes it, through the block driver of the boot
; (src/input_disk_bridge.s); the game has no ProDOS code. The check and the
; sum also run at the start (src/input_settings.s defaults). Part of the
; input (src/input.s), in its scope.
;
; Routines:
;   settings_check       wrong magic or checksum: the defaults
;   settings_sum         the checksum of the settings
;   settings_save        read the block, check it, write it, read it back
;   settings_fw_keep     copy the firmware's areas of bank $E1 to firmwareState
;   settings_fw_restore  copy firmwareState back to them
.a16
.i16

; ---------------------------------------------------------------------------
; settings_check: settings with a wrong magic or checksum (no file, a
; damaged file, another format) become the defaults: zeros, the magic, the
; default levels and the default bindings.
;
; In:       A16 X16, DBR = this bank
; Out:      settings valid (its checksum word untouched)
; Changes:  A, X
; Keeps:    Y, D, DBR, A16 X16
; Original: none
; ---------------------------------------------------------------------------
settings_check:
  lda a:.loword(settings+SET_MAGIC)
  cmp #SETTINGS_MAGIC0
  bne @reset
  lda a:.loword(settings+SET_MAGIC+2)
  cmp #SETTINGS_MAGIC1
  bne @reset
  lda a:.loword(settings+SET_MAGIC+4)
  cmp #SETTINGS_MAGIC2
  bne @reset
  lda a:.loword(settings+SET_MAGIC+6)
  cmp #SETTINGS_MAGIC3
  bne @reset
  jsr .loword(settings_sum)
  cmp a:.loword(settings+SETTINGS_CHECKSUM)
  beq @valid
  ; The defaults: zeros up to the checksum, the magic, the levels, the
  ; player of the joystick, the default bindings.
@reset:
  ldx #SETTINGS_CHECKSUM-2
  lda #0
@clear:
  sta a:.loword(settings),x
  dex
  dex
  bpl @clear
  lda #SETTINGS_MAGIC0
  sta a:.loword(settings+SET_MAGIC)
  lda #SETTINGS_MAGIC1
  sta a:.loword(settings+SET_MAGIC+2)
  lda #SETTINGS_MAGIC2
  sta a:.loword(settings+SET_MAGIC+4)
  lda #SETTINGS_MAGIC3
  sta a:.loword(settings+SET_MAGIC+6)
  a8
  lda #MIX_LEVEL_DEFAULT
  sta a:.loword(settings+SET_MUSIC_LEVEL)
  sta a:.loword(settings+SET_EFFECTS_LEVEL)
  lda #JOY_PLAYER_DEFAULT       ; the joystick of the default bindings
  sta a:.loword(settings+SET_JOY_PLAYER)
  a16
  ldx #SET_BINDINGS_END-SET_BINDINGS-2
@copy:
  lda a:.loword(menu_default_bindings),x
  sta a:.loword(settings+SET_BINDINGS),x
  dex
  dex
  bpl @copy
@valid:
  rts
.assert SET_MAGIC = 0, error

; ---------------------------------------------------------------------------
; settings_sum: A = the checksum of the settings before SETTINGS_CHECKSUM: a
; rotate left and an EOR for each word, from SETTINGS_SEED
; (scripts/boot_disk.py makes the same sum for the file of the build).
;
; In:       A16 X16, DBR = this bank
; Out:      A16 the sum
; Changes:  A, X
; Keeps:    Y, D, DBR
; Original: none
; ---------------------------------------------------------------------------
settings_sum:
  lda #SETTINGS_SEED
  ldx #0
@word:
  asl a
  adc #0                        ; the top bit comes back at bit 0
  eor a:.loword(settings),x
  inx
  inx
  cpx #SETTINGS_CHECKSUM
  bcc @word
  rts

; ---------------------------------------------------------------------------
; settings_save: write the settings block: the J13 settings and the
; checksum first; the block is read first and must hold settings (the
; magic), then written, and read back to check. menuMessage: MSG_SAVED, or
; MSG_SAVE_ERROR (no block at the boot, a driver error, another block, a
; read back that differs).
;
; Why the checks: the block number comes from the boot (the key block of
; SSMARIO.CONFIG); a block that does not start with the magic is not that
; file, and the game never writes it.
;
; In:       A16 X16, DBR = this bank (the options menu)
; Out:      the block on the disk; menuMessage; settings+SET_J13 and the
;           checksum word up to date
; Changes:  A, X, Y
; Keeps:    D, DBR, A16 X16, the interrupt flag
; Time:     three block calls of the driver; the interrupts are off meanwhile
; Original: none
; ---------------------------------------------------------------------------
settings_save:
  jsl J13SettingsStore
  jsr .loword(settings_sum)
  sta a:.loword(settings+SETTINGS_CHECKSUM)
  ; A driver below the slot ROMs: the boot found no settings block
  ; (src/boot.s load_settings leaves input_save_driver 0).
  lda a:.loword(input_save_driver)
  cmp #SLOT1_ROM
  bcc @refused
  php
  sei                           ; the bank-0 loan below: no interrupt code may run
  jsr .loword(bridge_open)
  ; Read the block: it must start with the magic of the settings.
  a8
  lda #DRV_READ
  sta a:.loword(input_save_command)
  jsr .loword(disk_call)
  a16
  bcs @error
  ldx #SET_J13-2                ; the magic
@identity:
  lda f:SAVE_BLOCK_BUFFER,x
  cmp a:.loword(settings),x
  bne @error
  dex
  dex
  bpl @identity
  ; Write the settings, then read the block back and compare.
  ldx #SETTINGS_SIZE-2
@copy:
  lda a:.loword(settings),x
  sta f:SAVE_BLOCK_BUFFER,x
  dex
  dex
  bpl @copy
  a8
  lda #DRV_WRITE
  sta a:.loword(input_save_command)
  jsr .loword(disk_call)
  a16
  bcs @error
  a8
  lda #DRV_READ
  sta a:.loword(input_save_command)
  jsr .loword(disk_call)
  a16
  bcs @error
  ldx #SETTINGS_SIZE-2
@verify:
  lda f:SAVE_BLOCK_BUFFER,x
  cmp a:.loword(settings),x
  bne @error
  dex
  dex
  bpl @verify
  jsr .loword(bridge_close)
  plp
  lda #MSG_SAVED
  sta a:.loword(menuMessage)
  rts
@error:
  .a16
  jsr .loword(bridge_close)
  plp
@refused:
  lda #MSG_SAVE_ERROR
  sta a:.loword(menuMessage)
  rts
.assert SET_MAGIC = 0 .and SET_J13 = 8 .and SETTINGS_SIZE = BLOCK_SIZE, error

; ---------------------------------------------------------------------------
; settings_fw_keep: copy the two areas of bank $E1 that the firmware
; reserves (FW_E1_WORK0, FW_E1_WORK1: the bank $E1 vectors and firmware
; work bytes, src/iigs.inc) to firmwareState. input_start keeps them as the
; boot left them; disk_call keeps them again after each block call, as the
; disk firmware left them. The game itself never writes them; the copy
; guards the firmware's state across the game's run.
;
; In:       any widths, D, DBR
; Out:      firmwareState
; Changes:  nothing (all registers kept)
; Original: none
; ---------------------------------------------------------------------------
settings_fw_keep:
  php
  ax16
  pha
  phx
  phy
  phb
  ldx #.loword(FW_E1_WORK0)
  ldy #.loword(firmwareState)
  lda #FW_E1_WORK_SIZE-1
  mvn #^FW_E1_WORK0,#^firmwareState
  ldx #.loword(FW_E1_WORK1)
  ldy #.loword(firmwareState+FW_E1_WORK_SIZE)
  lda #FW_E1_WORK_SIZE-1
  mvn #^FW_E1_WORK1,#^firmwareState
  plb
  ply
  plx
  pla
  plp
  rts

; ---------------------------------------------------------------------------
; settings_fw_restore: copy firmwareState back to the two firmware areas of
; bank $E1, before each block call (disk_call), so the disk firmware finds
; its bytes as it left them.
;
; In:       any widths, D, DBR
; Out:      FW_E1_WORK0, FW_E1_WORK1
; Changes:  nothing (all registers kept)
; Original: none
; ---------------------------------------------------------------------------
settings_fw_restore:
  php
  ax16
  pha
  phx
  phy
  phb
  ldx #.loword(firmwareState)
  ldy #.loword(FW_E1_WORK0)
  lda #FW_E1_WORK_SIZE-1
  mvn #^firmwareState,#^FW_E1_WORK0
  ldx #.loword(firmwareState+FW_E1_WORK_SIZE)
  ldy #.loword(FW_E1_WORK1)
  lda #FW_E1_WORK_SIZE-1
  mvn #^firmwareState,#^FW_E1_WORK1
  plb
  ply
  plx
  pla
  plp
  rts

; The kept firmware areas: FW_E1_WORK0, then FW_E1_WORK1 (settings_fw_keep
; writes them, settings_fw_restore reads them).
firmwareState: .res 2*::FW_E1_WORK_SIZE
