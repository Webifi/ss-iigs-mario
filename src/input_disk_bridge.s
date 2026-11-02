; The disk bridge: one block read or write through the block driver of the
; boot while the game runs (SAVE of the options menu, src/input_disk.s).
; Part of the input (src/input.s), in its scope.
;
; What the driver needs (ProDOS 8 Technical Reference, the block device
; drivers; Apple IIgs Firmware Reference, SmartPort):
;   - to be called from bank-0 code, in emulation mode, with D = 0, DBR = 0
;     and the stack in page one;
;   - its parameters: for a ProDOS block driver in page zero (DRV_COMMAND,
;     DRV_UNIT, DRV_BUFFER, DRV_BLOCK); for a SmartPort the command byte and
;     the address of its parameter list in the 3 bytes after its JSR;
;   - a 512-byte buffer in bank 0;
;   - the I/O and the ROM at $C000-$FFFF (SHADOW_IOLC off);
;   - its RAM as the boot left it: the firmware's areas of bank $E1
;     (settings_fw_restore) and the screen holes of the text page, the
;     TEXT_HOLE_SIZE bytes at the end of each TEXT_GROUP group of
;     $0400-$07FF, which are the RAM of the slot firmware (Apple IIe
;     Technical Reference, the screen holes) (holesKept).
; The boot loader found the driver and the block (src/boot.s
; load_settings, locate_smartport) and wrote them to input_save_*.
;
; The driver uses page zero and the stack page ($0000-$01FF), where the
; game keeps nothing (no segment of src/iigs.cfg is there), so they are not
; kept. The save borrows, with the interrupts off (bridge_open,
; bridge_close):
;   BRIDGE_AREA (in PACKET_BUFFER)        the block buffer, the call stub, the
;                                         SmartPort parameter list: not kept
; PACKET_BUFFER holds no state while the menu shows: packet_menu sent its
; last packet, and the next packet is written anew. The text page holds the
; menu then (src/menu.s keeps the game's bytes there), so the screen holes
; may take the firmware's bytes during the save.
;
; The call itself (disk_call) stays in this bank: it pushes the way back
; (an RTL address in this bank, then the return address that the driver
; takes) and enters the driver with an RTL. The driver's RTS lands on the
; RTL byte of the stub in bank 0, which comes back here.
;
; The stub (BRIDGE_CALL), as a SmartPort expects the bytes after its JSR:
;   offset        size  field
;   CALL_COMMAND     1  the SmartPort command: DRV_READ or DRV_WRITE
;   CALL_LIST        2  the address of BRIDGE_LIST
;   CALL_RTL         1  OPCODE_RTL: the way back
; The SmartPort parameter list (BRIDGE_LIST):
;   LIST_COUNT       1  SP_BLOCK_PARAMETERS
;   LIST_UNIT        1  the SmartPort unit (input_save_sp_unit)
;   LIST_BUFFER      2  SAVE_BLOCK_BUFFER
;   LIST_BLOCK       3  the block number
;
; Routines:
;   input_keep_holes  keep the screen holes of the boot (startup, before the game RAM clears)
;   bridge_open       borrow the bank-0 RAM, write the stub, the holes in
;   bridge_close      the holes out
;   disk_call         one block command through the driver
;   holes_in          holesKept into the screen holes of the text page
;   holes_out         the screen holes into holesKept
.a16
.i16
SP_BLOCK_PARAMETERS = 3      ; the parameter count of SmartPort ReadBlock and WriteBlock
BLOCK_SIZE = 512             ; a ProDOS block
DRIVER_BANK = ^ZERO_PAGE     ; the driver and the stub run in bank 0
BRIDGE_AREA = PACKET_BUFFER  ; the bank-0 RAM of the buffer and the stub
SAVE_BLOCK_BUFFER = BRIDGE_AREA
BRIDGE_CALL = SAVE_BLOCK_BUFFER+BLOCK_SIZE ; the call stub
CALL_COMMAND = 0
CALL_LIST = 1
CALL_RTL = 3
CALL_SIZE = 4
BRIDGE_LIST = BRIDGE_CALL+CALL_SIZE ; the SmartPort parameter list
LIST_COUNT = 0
LIST_UNIT = 1
LIST_BUFFER = 2
LIST_BLOCK = 4
LIST_SIZE = 7
BRIDGE_AREA_SIZE = BLOCK_SIZE+CALL_SIZE+LIST_SIZE ; the borrowed bytes of BRIDGE_AREA
HOLES_SIZE = ::TEXT_GROUPS*::TEXT_HOLE_SIZE ; the hole bytes of the text page (holesKept)
.assert BRIDGE_AREA_SIZE <= PACKET_BUFFER_SIZE, error

; ---------------------------------------------------------------------------
; input_keep_holes: keep the screen holes of the text page as the boot left
; them (the block driver's own RAM), before the game's RAM covers them. The
; bridge gives them back to the driver for each call.
;
; In:       any widths, D, DBR; called once by the startup (src/game.s)
;           before the game RAM ($0000-$07FF) is cleared
; Out:      holesKept
; Changes:  nothing (all registers kept)
; Original: none
; ---------------------------------------------------------------------------
input_keep_holes:
  php
  ax16
  pha
  phx
  phy
  phb
  phk
  plb                           ; DBR = this bank
  jsr .loword(holes_out)
  plb
  ply
  plx
  pla
  plp
  rtl

; ---------------------------------------------------------------------------
; bridge_open: borrow the bank-0 RAM of the block calls: write the stub and
; the parameter list into BRIDGE_AREA
; (which holds nothing while the menu shows), and give the driver its
; screen holes.
;
; In:       A16 X16, DBR = this bank; interrupts off until bridge_close
; Out:      the stub and the list but its command; the holes of
;           the text page
; Changes:  A, X, Y
; Keeps:    D, DBR, A16 X16
; Original: none
; ---------------------------------------------------------------------------
bridge_open:
  ; The stub and the SmartPort parameter list.
  a8
  lda #OPCODE_RTL
  sta f:BRIDGE_CALL+CALL_RTL
  lda #SP_BLOCK_PARAMETERS
  sta f:BRIDGE_LIST+LIST_COUNT
  lda a:.loword(input_save_sp_unit)
  sta f:BRIDGE_LIST+LIST_UNIT
  lda #0
  sta f:BRIDGE_LIST+LIST_BLOCK+2 ; the top byte of the block number
  a16
  lda #.loword(BRIDGE_LIST)
  sta f:BRIDGE_CALL+CALL_LIST
  lda #.loword(SAVE_BLOCK_BUFFER)
  sta f:BRIDGE_LIST+LIST_BUFFER
  lda a:.loword(input_save_block)
  sta f:BRIDGE_LIST+LIST_BLOCK
  jmp .loword(holes_in)         ; its RTS returns to the caller

; ---------------------------------------------------------------------------
; bridge_close: keep the screen holes as the driver left them.
;
; In:       A16 X16, DBR = this bank; interrupts off
; Out:      holesKept
; Changes:  A, X, Y
; Keeps:    D, DBR, A16 X16
; Original: none
; ---------------------------------------------------------------------------
bridge_close:
  jmp .loword(holes_out)        ; its RTS returns to the caller

; ---------------------------------------------------------------------------
; disk_call: run the command input_save_command on input_save_block with
; the buffer SAVE_BLOCK_BUFFER: a SmartPort call when the boot found the
; SmartPort unit of its slot (input_save_sp_unit), else a call of the ProDOS
; block driver (input_save_driver). After the call the $E1 areas are kept
; again and the ADB GLU is read (the keys of the call's time).
;
; Trick: the call is an RTL to the driver's entry - 1, with the way back on
; the stack below it: the return address that the driver's RTS takes
; (input_save_return), then @back - 1 and this bank for the RTL of the
; stub. A SmartPort reads its command and list after that return address
; and returns past them, on the same RTL.
;
; In:       A8 or A16, X16, DBR = this bank; bridge_open has run;
;           interrupts off
; Out:      carry = the driver's error flag; A8
; Changes:  A, X, Y; input_save_carry, input_save_shadow, input_save_stack,
;           input_save_target, input_save_return; the stub's command
; Keeps:    D, DBR, SHADOW
; Time:     the driver's (a disk access); the interrupts stay off
; Original: none
; ---------------------------------------------------------------------------
disk_call:
  ax16
  phd
  phb
  jsr .loword(settings_fw_restore) ; the $E1 areas as the driver left them
  ; The command into the stub; the entry and the return address of the
  ; driver (each - 1: an RTL and an RTS add 1).
  a8
  lda a:.loword(input_save_command)
  sta f:BRIDGE_CALL+CALL_COMMAND
  a16
  lda a:.loword(input_save_sp_unit)
  and #$00ff
  beq @block_driver
  lda a:.loword(input_save_sp_entry)
  dec a
  sta a:.loword(input_save_target)
  lda #.loword(BRIDGE_CALL-1)   ; a SmartPort reads the stub after its return address
  bra @return_set
@block_driver:
  lda a:.loword(input_save_driver)
  dec a
  sta a:.loword(input_save_target)
  lda #.loword(BRIDGE_CALL+CALL_RTL-1) ; the RTS of the driver lands on the RTL
@return_set:
  sta a:.loword(input_save_return)
  ; D = page zero and DBR = bank 0, as the driver expects.
  lda #.loword(ZERO_PAGE)
  tcd
  a8
  lda #DRIVER_BANK
  pha
  plb
  ; The I/O and the ROM at $C000-$FFFF again for the driver.
  lda f:SHADOW
  sta f:input_save_shadow
  and #<~SHADOW_IOLC
  sta f:SHADOW
  ; The parameters of a ProDOS block driver in page zero.
  lda f:input_save_command
  sta z:DRV_COMMAND
  lda f:input_save_unit
  sta z:DRV_UNIT
  a16
  lda #.loword(SAVE_BLOCK_BUFFER)
  sta z:DRV_BUFFER
  lda f:input_save_block
  sta z:DRV_BLOCK
  ; Emulation mode with the stack in page one; keep the native stack pointer.
  tsc
  sta f:input_save_stack
  ax8
  sec
  xce                           ; carry 1: emulation mode
  ldx #<EMULATION_STACK_TOP
  txs
  ; The way back: the RTL of the stub pulls @back - 1 and this bank; the
  ; driver's RTS pulls input_save_return.
  phk
  per @back-1
  lda f:input_save_return+1
  pha
  lda f:input_save_return
  pha
  ; Enter the driver: an RTL pulls its entry - 1 and bank 0.
  lda #DRIVER_BANK
  pha
  lda f:input_save_target+1
  pha
  lda f:input_save_target
  pha
  rtl
@back:
  ; Emulation mode in this bank; D = 0, DBR = 0. Keep the error flag (the
  ; carry); the caller needs no error code.
  lda #0
  rol a                         ; A = the carry
  sta f:input_save_carry
  clc
  xce                           ; native mode again
  ax16
  lda f:input_save_stack
  tcs
  a8
  lda f:input_save_shadow
  sta f:SHADOW                  ; RAM at $C000-$FFFF again (the IRQ vector)
  plb
  pld
  ax16
  jsr .loword(settings_fw_keep) ; the areas as the driver left them
  jsr .loword(capture_adb)      ; the ADB bytes of the call's time
  a8
  lda a:.loword(input_save_carry)
  lsr a                         ; carry = the driver's error flag
  rts

; ---------------------------------------------------------------------------
; holes_in: holesKept into the screen holes of the text page: TEXT_HOLE_SIZE
; bytes at TEXT_HOLE of each of the TEXT_GROUPS groups.
;
; In:       A16 X16, DBR = this bank
; Out:      the screen holes of TEXT_PAGE
; Changes:  A, X, Y
; Keeps:    D, DBR, A16 X16
; Original: none
; ---------------------------------------------------------------------------
holes_in:
  ldy #0                        ; the kept byte
  ldx #0                        ; the hole byte, from the first hole
@byte:
  a8
  lda a:.loword(holesKept),y
  sta f:TEXT_PAGE+TEXT_HOLE,x
  a16
  iny
  inx
  txa
  and #TEXT_HOLE_SIZE-1
  bne @byte
  txa
  clc
  adc #TEXT_GROUP-TEXT_HOLE_SIZE ; the holes of the next group
  tax
  cpy #HOLES_SIZE
  bcc @byte
  rts

; ---------------------------------------------------------------------------
; holes_out: the screen holes of the text page into holesKept (the same
; walk as holes_in).
;
; In:       A16 X16, DBR = this bank
; Out:      holesKept
; Changes:  A, X, Y
; Keeps:    D, DBR, A16 X16
; Original: none
; ---------------------------------------------------------------------------
holes_out:
  ldy #0
  ldx #0
@byte:
  a8
  lda f:TEXT_PAGE+TEXT_HOLE,x
  sta a:.loword(holesKept),y
  a16
  iny
  inx
  txa
  and #TEXT_HOLE_SIZE-1
  bne @byte
  txa
  clc
  adc #TEXT_GROUP-TEXT_HOLE_SIZE
  tax
  cpy #HOLES_SIZE
  bcc @byte
  rts
.assert TEXT_PAGE+TEXT_HOLE+(TEXT_GROUPS-1)*TEXT_GROUP+TEXT_HOLE_SIZE = TEXT_PAGE+TEXT_PAGE_SIZE, error ; the last hole ends the page
.assert (TEXT_HOLE_SIZE & (TEXT_HOLE_SIZE-1)) = 0 .and (TEXT_GROUP & (TEXT_HOLE_SIZE-1)) = 0, error ; the AND: a power of two that divides a group

; The state of the bridge. The boot loader writes the first five
; (src/boot.s, by these names, through build/game-disk/boot_settings.inc);
; the bridge keeps the rest.
.a8
input_save_sp_entry: .word 0    ; the SmartPort entry address (the block driver + 3)
input_save_sp_unit: .byte 0     ; the SmartPort unit; 0: use input_save_driver
input_save_driver: .word 0      ; the ProDOS block driver address; 0: no settings block
input_save_block: .word 0       ; the block of SSMARIO.CONFIG
input_save_unit: .byte 0        ; the ProDOS unit number (DSSS0000)
input_save_command: .byte 0     ; DRV_READ or DRV_WRITE
input_save_carry: .byte 0       ; disk_call: the driver's error flag (carry), 0 or 1
input_save_shadow: .byte 0      ; disk_call: SHADOW of the game during the call
input_save_stack: .word 0       ; disk_call: the native stack pointer during the call
input_save_target: .word 0      ; disk_call: the driver's entry - 1
input_save_return: .word 0      ; disk_call: the address that the driver returns to - 1
holesKept: .res HOLES_SIZE      ; the screen holes of the boot, then of the last call
