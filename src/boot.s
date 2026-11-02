; The boot loader: the file SSMARIO.SYSTEM. bootloader/boot0.s loads it to
; SYSTEM_LOAD and starts it in emulation mode with X = the ProDOS unit of
; the boot drive. It loads the whole game before the game runs; the game
; never reads the disk again, except the settings save.
;
; The steps:
;   1. boot (BOOT segment, 6502 code): a machine that is not a IIgs shows a
;      message and stops. On a IIgs the loader moves to BOOT_LOADER, out of
;      the bank-0 RAM that the game's code takes.
;   2. loader: the loading screen on the Apple text page, which the card's
;      firmware shows through its text mirror; the fast RAM check
;      (check_memory); the Second Sight check (detect_secondsight).
;   3. SSMARIO.DATA (src/data_file.inc): the header block, then each
;      segment of the table into its host address, through DATA_BUFFER.
;   4. The card startup records of the file into the card
;      (load_secondsight): its program, tables and art.
;   5. SSMARIO.CONFIG over the settings image (load_settings), the block
;      driver and the SmartPort of the boot slot for the settings save
;      (locate_smartport).
;   6. The text page blank, the memory switches of the game, ScreenOff,
;      then JML to the game's handoff (src/game.s game_handoff).
; The progress bar fills with the bytes of SSMARIO.DATA read (load_progress).
;
; Data in: SSMARIO.DATA, SSMARIO.CONFIG (bootloader/prodos_read.s reads
; them through the block driver of the boot slot). Data out: the game's
; segments in host RAM; the card's startup records in card memory; the
; settings at INPUT_SETTINGS; the driver, unit, block and SmartPort entry
; of the settings save at INPUT_SAVE_* (build/game-disk/boot_settings.inc
; gives these addresses of the game's link).
;
; The card's screen during the load (the text mirror):
;   state    what the card shows                   the event that ends it
;   MIRROR   the firmware's text emulation draws    load_secondsight starts:
;            the Apple text page from its copy (the SetShadow SS_SHADOW_NONE,
;            copy is on from the card's start): the then freeze_mirror sets
;            loading screen and the bar of          SetMode native
;            draw_progress                          (mirror_disabled)
;   FROZEN   the last text image: the firmware      the first record with
;            draws nothing; mirror_progress puts    RECORD_FINAL_SRAM
;            the bar cells into its text video RAM  (mirror_final)
;   FINAL    the last text image; the bar stops     the first record with
;                                                   RECORD_FINAL_VRAM
;                                                   (video_final)
;   BLANK    ScreenOff before each upload: the text the card program sets
;            video RAM becomes the game's           its game mode at its
;                                                   entry (src/secondsight)
; mirror_frozen: 1 while the VGA upload registers are set; each upload
; clears it and sets them again (freeze_mirror), because a disk read can
; make the card set its mode again (erratum E29, below).
;
; Hardware rules:
;   - IDROUTINE ($FE1F), called with the carry set, clears the carry only
;     on a IIgs (Apple IIgs Firmware Reference, p. 250).
;   - The block driver: emulation mode, page zero and the page-one stack of
;     bank 0, and it may change any of page zero (bootloader/prodos_read.s).
;   - The Second Sight commands (Second Sight reference,
;     docs/reference/host-commands.md): GetStatus, SetShadow, SetMode,
;     SetVGAReg, UploadData, ScreenOff. UploadData writes through the VGA
;     CPU write path as the registers set it; an upload must not cross video
;     $80000: scripts/boot_disk.py gives each video record a plane offset
;     below $40000 and at most DATA_BUFFER_SIZE bytes.
;   - Erratum E29 of the card's ROM 1.4 (docs/reference/errata.md): with
;     the text emulation off, an Apple display switch makes the card set
;     its SetMode mode again: SetVGAReg changes are lost and a ScreenOff is
;     undone. The disk firmware may set the display switches, so the
;     loader sets the upload registers again after each disk read and
;     sends ScreenOff again after the last.
;   - The card copies the IIgs's writes to the graphics pages of banks
;     $E0/$E1 into its SRAM (docs/reference/z180-memory-map.md, SRAM
;     ownership), so the loader stops the IIgs's copy of those pages to
;     $E0/$E1 (SHADOW_GRAPHICS) once the card's own data loads.
;
; Routines:
;   boot               the IIgs check, then the move to BOOT_LOADER
;   loader             the load, then the handoff to the game
;   read_block         read bytes of SSMARIO.DATA into DATA_BUFFER
;   load_settings      SSMARIO.CONFIG over the settings image
;   locate_smartport   the SmartPort entry and unit of the boot slot
;   load_secondsight   the card startup records into the card
;   wait_ready, wait_done  the handshake of a card command
;   startup_unpack     unpack a record (src/boot_unpack.s)
;   detect_secondsight the card's GetStatus and its signature
;   check_memory       the fast RAM banks; memory_probe_word,
;                      memory_bank_found, memory_bank_bit its parts
;   firmware_banks     the firmware's count of the fast RAM
;   memory_details     the RAM lines of the memory error screen;
;                      memory_hex, memory_kilobytes its digits
;   boot_screen        the loading screen
;   clear_text         the text page all spaces
;   black_screen       the text page blank for the game
;   load_progress      count the bytes read, then draw the bar
;   draw_progress      the bar on the Apple text page
;   mirror_progress    the bar in the card's text video RAM
;   freeze_mirror      the text mirror off; the VGA upload registers
;   text_emulation     SetMode 40-column text, emulation on or off
;   unsupported_driver, no_memory, no_secondsight, failed, requirement_error
;                      the error screens
.setcpu "65816"
.include "w65c816.inc"
.include "iigs.inc"
.include "second_sight.inc"
.include "host_memory.inc"
.include "data_file.inc"
.include "settings.inc"
.smart
.macpack longbranch
.a8
.i8
; src/boot.cfg places the loader: it must agree with host_memory.inc.
.import __SYSTEM_START__, __SYSTEM_SIZE__, __LOADER_START__, __LOADER_SIZE__
.import __LOADERZP_START__, __LOADERZP_SIZE__
.assert __SYSTEM_START__ = SYSTEM_LOAD && __SYSTEM_SIZE__ = SYSTEM_BOOT_SIZE, error, "boot.cfg SYSTEM"
.assert __LOADER_START__ = BOOT_LOADER && __LOADER_SIZE__ = BOOT_LOADER_SIZE, error, "boot.cfg LOADER"
.assert __LOADERZP_START__ = LOADER_ZERO_PAGE && __LOADERZP_SIZE__ = LOADER_ZERO_PAGE_SIZE, error, "boot.cfg LOADERZP"
; The text screens: the rows and columns of each line.
PAGE = $100                       ; a page: the reach of an 8-bit index
TITLE_LENGTH = 17                 ; the game's title on the text screen, centred
TITLE_COLUMN = (TEXT_COLUMNS-TITLE_LENGTH)/2
NOT_IIGS_COLUMN = 6               ; the message of a machine that is not a IIgs (row 11)
ERROR_COLUMN = 8                  ; the error message (row 11)
DETAIL_COLUMN = 4                 ; the RAM lines of the memory error (rows 13-15)
LOADING_LENGTH = 7                ; "LOADING" (row 21), centred
LOADING_COLUMN = (TEXT_COLUMNS-LOADING_LENGTH)/2
.assert TEXT_PAGE_SIZE = 4*PAGE, error ; the four stores of the clear loops

; ---------------------------------------------------------------------------
; boot: the entry of SSMARIO.SYSTEM. A machine that is not a IIgs gets a
; message and stops; this path is 6502 code, so it runs on any Apple II. A
; IIgs moves the LOADER segment, which follows this segment in the file, to
; BOOT_LOADER and runs it.
;
; In:       emulation mode, X = the ProDOS unit of the boot drive (boot0)
; Out:      the loader runs (never returns)
; Changes:  everything; PR_UNIT ($43) = the boot unit
; Original: none
; ---------------------------------------------------------------------------
.segment "BOOT"
boot:
.setcpu "6502"
  stx z:PR_UNIT                     ; the boot unit, for pr_init
  ; IDROUTINE: call with carry set; only a IIgs clears it.
  cld
  sec
  jsr IDROUTINE
  bcs not_iigs
  jmp is_iigs                       ; a branch does not reach over the message
not_iigs:
  ; Main 40-column text page 1, the primary characters, all spaces.
  lda #0
  sta .loword(KBD)                  ; 80STORE off
  sta .loword(RDMAINRAM)
  sta .loword(WRMAINRAM)
  sta .loword(SETSLOTCXROM)
  sta .loword(CLR80VID)
  sta .loword(CLRALTCHAR)
  bit .loword(TXTSET)
  bit .loword(MIXCLR)
  bit .loword(TXTPAGE1)
  ldx #0
  lda #TEXT_SPACE
@clear:
  sta .loword(TEXT_PAGE1),x
  sta .loword(TEXT_PAGE1)+PAGE,x
  sta .loword(TEXT_PAGE1)+2*PAGE,x
  sta .loword(TEXT_PAGE1)+3*PAGE,x
  inx
  bne @clear
  ; The title and the message, then stop.
  ldx #TITLE_LENGTH-1          ; the title, centred
@title:
  lda boot_title,x
  ora #TEXT_NORMAL
  sta .loword(TEXT_ROW_2)+TITLE_COLUMN,x
  dex
  bpl @title
  ldx #0
@message:
  lda not_iigs_message,x
  beq @hold
  ora #TEXT_NORMAL
  sta .loword(TEXT_ROW_11)+NOT_IIGS_COLUMN,x
  inx
  bne @message
@hold:
  jmp @hold
boot_title: .byte "SUPER MARIO BROS."
.assert * - boot_title = TITLE_LENGTH, error, "TITLE_LENGTH"
not_iigs_message: .asciiz "THIS GAME REQUIRES AN APPLE IIGS"
.setcpu "65816"
is_iigs:
  ; Native mode for the MVN: the LOADER segment from after this segment to
  ; BOOT_LOADER.
  clc
  xce
  ax16
  ldx #.loword(SYSTEM_LOAD+SYSTEM_BOOT_SIZE)
  ldy #loader
  lda #loader_end-loader-1
  mvn #^SYSTEM_LOAD,#^loader
  jmp loader

.segment "LOADER"
.include "boot_settings.inc"    ; the game's places: INPUT_SETTINGS, INPUT_SAVE_*, GAME_HANDOFF
PROBE_TOP_BANK = $7f         ; the top bank of the memory probe
MEMORY_FIRST_BANK = ^INPUT_CODE ; the game's lowest bank above the motherboard's $00/$01
MEMORY_LAST_BANK = ^(PENDING_WRITES+PENDING_WRITES_SIZE-1) ; the game's highest bank (src/iigs.cfg)
PROBE_OFFSET = $5a5a         ; the word probe: its address in each bank
PROBE_WORD = $a55a           ; and its value: two unequal bytes, so an empty bus fails
MEMORY_BITMAP_SIZE = 16      ; memory_bitmap: a bit for each bank $00-$7F
MOTHERBOARD_BANKS = %11      ; memory_bitmap byte 0: banks $00 and $01 are motherboard RAM
SLOW_BANKS = 2               ; banks $E0 and $E1: in the RAM count of memory_details
BANK_KB = 64                 ; the kilobytes of a bank
UNIT_DEVICE = $f0            ; a ProDOS unit number: bit 7 the drive, bits 4-6 the slot
UNIT_SLOT = $70
; A slot ROM page $Cn: a ProDOS block device has ID_BYTE1 at $Cn01, $00 at
; $Cn03 and ID_BYTE5 at $Cn05; a SmartPort also $00 at $Cn07 (ProDOS 8
; Technical Reference, the block device ID bytes; Firmware Reference,
; SmartPort). $CnFF: the offset of the block entry; the SmartPort entry is
; SMARTPORT_ENTRY after it.
ID_OFFSET1 = 1
ID_OFFSET3 = 3
ID_OFFSET5 = 5
ID_OFFSET7 = 7
ID_BYTE1 = $20
ID_BYTE5 = $03
SMARTPORT_ENTRY = 3
BLOCK_ENTRY = $ff
SMARTPORT_DRIVE1 = 1         ; the SmartPort unit of drive 1; drive 2 is the next
ROMVER_01 = 1                ; ROMVER: ROM 01 and ROM 03 keep the bank count at
ROMVER_03 = 3                ; FW_BANKS_ROM03, ROM 00 at FW_BANKS_ROM00
FW_BANKS_MIN = 2             ; a firmware bank count from this
FW_BANKS_END = $81           ; up to under this is believed
NEWVIDEO_SHR = $80           ; NEWVIDEO: super hi-res on
CLOCKCTL_BORDER = $0f        ; CLOCKCTL: the border colour
BOOT_COLOURS = $60           ; TBCOLOR: medium blue text (6), black background (0)
; The progress bar cells: MouseText on the text page (Apple IIgs Hardware
; Reference, figure C-2), and the codes of the same cells in the card
; firmware's text font (draw_progress, mirror_progress).
MT_RIGHT_LINE = $5a          ; a line at the right edge of a cell
MT_LEFT_LINE = $5f           ; a line at the left edge of a cell
MT_CELL_EMPTY = $5c          ; an outlined empty cell
MT_CELL_FULL = $4e           ; a filled cell
FONT_CELL_EMPTY = $dc        ; the firmware's alternate font has MT_CELL_EMPTY at this glyph
FONT_CELL_FULL = $ce         ; and MT_CELL_FULL at this one
FONT_ODD_FILL = $10          ; the byte of a cell's odd plane address (not shown)
; The progress bar: PROGRESS_CELLS (data_file.inc) cells on a text row of the
; loading screen.
PROGRESS_ROW = 22
PROGRESS_COLUMN = 2
PROGRESS_TEXT = .ident(.sprintf("TEXT_ROW_%d", PROGRESS_ROW))+PROGRESS_COLUMN
SEND_UNROLL = 4              ; load_secondsight: the bytes of one pass of the send loops
KB_DIGITS = 4                ; memory_kilobytes: the decimal digits (memory_tens)
; Loader page-zero variables. The block driver may change any of page zero
; (bootloader/prodos_read.s), so nothing here lives across a disk read.
.pushseg
.segment "LOADERZP": zeropage
probe_ptr: .res 3            ; check_memory, locate_smartport: the probe address
pr_zp: .res 4                ; the file reader's pointers
unpack_end: .res 2           ; startup_unpack: the end address of the output
unpack_length: .res 2        ; startup_unpack: a match: the byte count - 1
unpack_distance: .res 2      ; startup_unpack: a match: the distance back
.popseg

; ---------------------------------------------------------------------------
; loader: load the game and start it (the steps of the file header).
;
; In:       native mode, A16 X16 (boot); PR_UNIT = the boot unit
; Out:      never returns: JML GAME_HANDOFF in emulation mode, or an error
;           screen that stops
; Changes:  everything
; Original: none
; ---------------------------------------------------------------------------
.a16
.i16
loader:
  ; Page zero, the page-one stack and emulation mode: the block driver's.
  lda #0
  tcd
  ldx #.loword(EMULATION_STACK_TOP)
  txs
  ax8
  sec
  xce
.a8
.i8
  ; The file reader on the boot unit; the loading screen; the RAM and the
  ; card that the game needs.
  lda z:PR_UNIT
  jsr pr_init
  jsr boot_screen
  jsr check_memory
  jcs no_memory
  jsr detect_secondsight
  jcs no_secondsight
  ; SSMARIO.DATA: its header block, with the magic ("SS"), the format and
  ; a segment count.
  lda #<path
  ldy #>path
  jsr pr_open
  jcs failed
  lda #<DATA_HEADER_SIZE
  sta read_request
  lda #>DATA_HEADER_SIZE
  sta read_request+1
  jsr read_block
  jcs failed
  lda DATA_BUFFER+DATA_MAGIC
  cmp #'S'
  jne failed
  lda DATA_BUFFER+DATA_MAGIC+1
  cmp #'S'
  jne failed
  lda DATA_BUFFER+DATA_VERSION
  cmp #DATA_FORMAT
  jne failed
  lda DATA_BUFFER+DATA_SEGMENTS
  jeq failed
  sta segments
  lda DATA_BUFFER+DATA_STARTUP
  sta startup_records
  lda pr_unit
  and #UNIT_DEVICE
  sta boot_unit
  lda pr_driver
  sta boot_driver
  lda pr_driver+1
  sta boot_driver+1
  ; The settings save calls the driver later, from the game
  ; (src/input_disk_bridge.s), and the game's code covers the RAM: only a
  ; SmartPort or a driver in the slot ROMs can serve it. Any other driver
  ; stops the boot here, while the card's text emulation still shows the
  ; text page. (INPUT_SAVE_SP_UNIT is in the INPUT segment, which the load
  ; below covers; locate_smartport runs again after it.)
  lda #0
  sta f:INPUT_SAVE_SP_UNIT
  jsr locate_smartport
  lda f:INPUT_SAVE_SP_UNIT
  bne :+
  lda boot_driver+1
  cmp #>SLOT1_ROM
  jcc unsupported_driver
  cmp #>SLOT_ROMS_END
  jcs unsupported_driver
:
  ; The segment table and the progress thresholds of the header block:
  ; DATA_BUFFER takes the segment data next.
  ldx #0
@headers:
  lda DATA_BUFFER+DATA_TABLE,x
  sta headers,x
  inx
  cpx #MAX_SEGMENTS*SEGMENT_ENTRY
  bne @headers
  ldx #0
@thresholds:
  lda DATA_BUFFER+DATA_PROGRESS,x
  sta progress_thresholds,x
  inx
  cpx #PROGRESS_CELLS*PROGRESS_ENTRY
  bne @thresholds
  ; Each segment of the table: its host address and its size.
  stz current
@segment:
  ldx current
  lda headers,x
  sta dest
  lda headers+1,x
  sta dest+1
  lda headers+2,x
  sta dest+2
  lda headers+3,x
  sta remaining
  lda headers+4,x
  sta remaining+1
  lda headers+5,x
  sta remaining+2
@chunk:
  ; amount = the bytes of this block: DATA_BUFFER_SIZE, but no more than
  ; the rest of the bank of dest (one MVN stays in one bank) or the bytes
  ; left of the segment.
  clc
  xce
  ax16
.a16
.i16
  lda #DATA_BUFFER_SIZE
  sta amount
  lda dest
  beq @remaining
  eor #$ffff
  inc                           ; the bytes up to the end of the bank
  cmp amount
  bcs @remaining
  sta amount
@remaining:
  a8
.a8
  lda remaining+2
  bne @amount                   ; 64 KB or more left
  a16
.a16
  lda remaining
  cmp amount
  bcs @amount
  sta amount
@amount:
  ; Read the block (emulation mode); a short read is an error.
  a16
  lda amount
  sta read_request
  ax8
.a8
.i8
  sec
  xce
  jsr read_block
  jcs failed_far
  clc
  xce
  ax16
.a16
.i16
  lda amount
  cmp read_actual
  jne failed_native
  ; Copy it to dest. Self-changing code: the store to @copy+1 sets the
  ; destination bank of the MVN. Bank 1 $C000-$FFFF is RAM only with
  ; SHADOW_IOLC set, and with it set the IRQ vector is RAM that the loader
  ; does not fill, so the interrupts stay off during the copy.
  ldx #.loword(DATA_BUFFER)
  ldy dest
  a8
.a8
  lda dest+2
  sta @copy+1
  php
  sei
  lda f:SHADOW
  pha
  ora #SHADOW_IOLC
  sta f:SHADOW
  a16
.a16
  lda amount
  dec
@copy:
  mvn #^DATA_BUFFER,#0        ; the destination bank: dest+2
  a8
.a8
  pla
  sta f:SHADOW               ; the I/O and the language card again
  plp
  lda #0
  pha
  plb                        ; DBR = 0 again (the MVN set the destination bank)
  ; dest moves on and remaining goes down by amount (3-byte values).
  a16
.a16
  lda dest
  clc
  adc amount
  sta dest
  a8
.a8
  lda dest+2
  adc #0
  sta dest+2
  a16
.a16
  lda remaining
  sec
  sbc amount
  sta remaining
  a8
.a8
  lda remaining+2
  sbc #0
  sta remaining+2
  a16
.a16
  lda remaining
  ora remaining+1            ; bytes 0-1 or bytes 1-2: zero when all three are
  bne @more
  ; The next segment, or the end of the table.
  ax8
.a8
.i8
  sec
  xce
  lda current
  clc
  adc #SEGMENT_ENTRY
  sta current
  dec segments
  beq @ready
  jmp @segment
@more:
  jmp @chunk
@ready:
  ; From here on, no write of banks 0 and 1 to $2000-$9FFF may reach the
  ; graphics pages of $E0/$E1: the card copies those pages into its SRAM
  ; (bank 0 $2000-$5FFF, bank 1 $2000-$9FFF), and load_secondsight puts the
  ; card's program image into its SRAM bank 1 (src/secondsight/secondsight.ld).
  ; The text pages stay shadowed: the card shows the loader's text through
  ; its text mirror.
  lda f:SHADOW
  ora #SHADOW_GRAPHICS
  sta f:SHADOW
  ; The card's records, the settings, the SmartPort of the save.
  lda startup_records
  beq :+
  jsr load_secondsight
:
  jsr load_settings
  jsr locate_smartport
  ; The game's screen and memory switches: a blank text page, the slot
  ; ROMs at $C100-$CFFF (the save calls the driver there), main RAM for
  ; reads and writes, slot 4 to its card ROM.
  jsr black_screen
  lda #0
  sta f:SETSLOTCXROM
  sta f:RDMAINRAM
  sta f:WRMAINRAM
  lda f:SLTROMSEL
  ora #SLTROMSEL_SLOT4
  sta f:SLTROMSEL
  ; The disk reads are over: one more ScreenOff, which no later disk read
  ; can undo (erratum E29), keeps the card's screen blank until the card
  ; program sets the game's mode. ScreenOff has no handshake.
  lda #SS_SCREEN_OFF
  sta .loword(SS_COMMAND)
  jml GAME_HANDOFF
; failed_native, failed_far: a load error, from native mode or from a
; distance (JMP), to the error screen.
failed_native:
  ax8
.a8
.i8
  sec
  xce
failed_far:
  jmp failed

; ---------------------------------------------------------------------------
; read_block: read read_request bytes of SSMARIO.DATA, from its mark, into
; DATA_BUFFER, then count them on the progress bar (load_progress).
;
; In:       emulation mode, D = 0; read_request
; Out:      carry set: a disk error; else read_actual = the bytes read
;           (fewer at the end of the file)
; Changes:  A, X, Y (the file reader); pr_dest, pr_count; the progress
; Original: none
; ---------------------------------------------------------------------------
read_block:
  lda #<DATA_BUFFER
  sta pr_dest
  lda #>DATA_BUFFER
  sta pr_dest+1
  lda read_request
  sta pr_count
  lda read_request+1
  sta pr_count+1
  jsr pr_read
  bcs @done
  lda pr_count
  sta read_actual
  lda pr_count+1
  sta read_actual+1
  pha
  phx
  phy
  jsr load_progress
  ply
  plx
  pla
  clc
@done:
  rts

; ---------------------------------------------------------------------------
; load_settings: read SSMARIO.CONFIG over the settings image of the game
; (INPUT_SETTINGS); the game checks its magic and its checksum
; (src/input_disk.s settings_check) and takes the defaults when they are
; wrong. The file must be a seedling: SAVE writes its one block in place,
; at the key block. With no such file the save driver stays 0 and the game
; refuses SAVE.
;
; In:       emulation mode, D = 0; boot_unit, boot_driver; the game's
;           segments loaded
; Out:      INPUT_SETTINGS; INPUT_SAVE_UNIT, INPUT_SAVE_BLOCK,
;           INPUT_SAVE_DRIVER
; Changes:  A, X, Y; the file reader's state
; Original: none
; ---------------------------------------------------------------------------
load_settings:
  lda boot_unit
  sta f:INPUT_SAVE_UNIT
  lda #<config_path
  ldy #>config_path
  jsr pr_open
  bcs @done
  lda pr_storage
  cmp #PR_SEEDLING           ; a seedling: the key block holds the data
  bne @done
  lda pr_key
  sta f:INPUT_SAVE_BLOCK
  lda pr_key+1
  sta f:INPUT_SAVE_BLOCK+1
  lda boot_driver
  sta f:INPUT_SAVE_DRIVER
  lda boot_driver+1
  sta f:INPUT_SAVE_DRIVER+1
  ; The block into DATA_BUFFER, then (native mode) to INPUT_SETTINGS.
  lda #<DATA_BUFFER
  sta pr_dest
  lda #>DATA_BUFFER
  sta pr_dest+1
  stz pr_count
  lda #>SETTINGS_SIZE
  sta pr_count+1
  jsr pr_read
  bcs @done
  clc
  xce
  ax16
  ldx #.loword(DATA_BUFFER)
  ldy #.loword(INPUT_SETTINGS)
  lda #SETTINGS_SIZE-1
  mvn #^DATA_BUFFER,#^INPUT_SETTINGS
  ax8
  lda #0
  pha
  plb                        ; DBR = 0 again (the MVN set the destination bank)
  sec
  xce
@done:
  rts
.assert (SETTINGS_SIZE & (PAGE-1)) = 0, error ; pr_count: whole pages
config_path: .byte 14,"SSMARIO.CONFIG"
boot_unit: .byte 0           ; the boot unit (DSSS0000)
boot_driver: .word 0         ; the block driver of the boot slot

; ---------------------------------------------------------------------------
; locate_smartport: the SmartPort entry of the boot slot (the block driver
; + SMARTPORT_ENTRY) and its unit, for the save bridge, when the driver is
; the slot's own and the slot firmware is a SmartPort (its ID bytes).
;
; In:       emulation mode, D = 0; boot_driver, boot_unit
; Out:      INPUT_SAVE_SP_UNIT (1 drive 1, 2 drive 2) and
;           INPUT_SAVE_SP_ENTRY when a SmartPort serves the boot unit; else
;           INPUT_SAVE_SP_UNIT untouched (the caller zeroes it first)
; Changes:  A, Y; probe_ptr; smart_unit, smart_slot, smart_entry
; Keeps:    X
; Original: none
; ---------------------------------------------------------------------------
locate_smartport:
  stz smart_unit
  ; A driver in the slot ROMs, in the slot of the boot unit.
  lda boot_driver+1
  cmp #>SLOT1_ROM
  jcc @done
  cmp #>SLOT_ROMS_END
  jcs @done
  sec
  sbc #>SLOT1_ROM-1             ; the slot
  asl
  asl
  asl
  asl
  sta smart_slot
  lda boot_unit
  and #UNIT_SLOT
  cmp smart_slot
  jne @done
  ; The SmartPort entry and unit, if the slot's ID bytes say SmartPort and
  ; its $CnFF entry is the boot driver.
  lda boot_driver
  clc
  adc #SMARTPORT_ENTRY
  jcs @done
  sta smart_entry
  lda boot_driver+1
  sta smart_entry+1
  lda #SMARTPORT_DRIVE1         ; drive 1, or the next unit for drive 2 (unit bit 7)
  bit boot_unit
  bpl :+
  inc
:
  sta smart_unit
  lda smart_entry+1
  cmp #>SLOT1_ROM
  jcc @done
  cmp #>SLOT_ROMS_END
  jcs @done
  sta probe_ptr+1
  stz probe_ptr
  ldy #ID_OFFSET1
  lda (probe_ptr),y
  cmp #ID_BYTE1
  jne @done
  ldy #ID_OFFSET3
  lda (probe_ptr),y
  jne @done
  iny
  iny                           ; ID_OFFSET5
  lda (probe_ptr),y
  cmp #ID_BYTE5
  jne @done
  iny
  iny                           ; ID_OFFSET7
  lda (probe_ptr),y             ; $Cn07: a SmartPort
  jne @done
  ldy #BLOCK_ENTRY
  lda (probe_ptr),y
  clc
  adc #SMARTPORT_ENTRY
  jcs @done
  cmp smart_entry
  jne @done
  lda smart_unit
  sta f:INPUT_SAVE_SP_UNIT
  lda smart_entry
  sta f:INPUT_SAVE_SP_ENTRY
  lda smart_entry+1
  sta f:INPUT_SAVE_SP_ENTRY+1
@done:
  rts
.assert ID_OFFSET5 = ID_OFFSET3+2 .and ID_OFFSET7 = ID_OFFSET5+2, error ; the INYs
smart_unit: .byte 0          ; locate_smartport: the SmartPort unit
smart_slot: .byte 0          ; locate_smartport: the slot of the driver, x 16
smart_entry: .word 0         ; locate_smartport: the SmartPort entry

; ---------------------------------------------------------------------------
; load_secondsight: the card startup records of SSMARIO.DATA into the card
; (data_file.inc): its program, its tables and its art. Each record fits
; DATA_BUFFER (scripts/boot_disk.py boot_uploads); a packed record is
; unpacked to STARTUP_UNPACK_OUTPUT first. The game keeps no copy of these
; bytes in host RAM. The text mirror moves through its states (the file
; header) on the way.
;
; For each record: its header, then its bytes (the disk read comes first:
; the disk firmware may set the Apple display switches), then the upload
; registers again (freeze_mirror), then UploadData with the record's
; address and its bytes, then the bar (mirror_progress).
;
; In:       emulation mode, D = 0; SSMARIO.DATA open at the first record
; Out:      the records in the card; the text mirror FINAL or BLANK; a
;           ScreenOff after the last record
; Changes:  A, X, Y; record_header, amount, read_request, read_actual,
;           send_limit, upload_map_mask, the mirror state; the progress
; Original: none
; ---------------------------------------------------------------------------
.a8
.i8
load_secondsight:
  ; The card copies no more Apple video writes (SetShadow SS_SHADOW_NONE);
  ; the text mirror freezes.
  lda #SS_SET_SHADOW
  sta .loword(SS_COMMAND)
  jsr wait_ready
  lda #SS_SHADOW_NONE
  sta .loword(SS_DATA_OUT)
  jsr wait_done
  jsr freeze_mirror
@record:
  ; The header of the next record; a zero size ends the list.
  lda #RECORD_HEADER_SIZE
  sta read_request
  stz read_request+1
  jsr read_block
  jcs failed
  ldx #RECORD_HEADER_SIZE-1
@keep:
  lda DATA_BUFFER,x
  sta record_header,x
  dex
  bpl @keep
  lda record_header+RECORD_SIZE
  ora record_header+RECORD_SIZE+1
  bne :+
  ; The end. ScreenOff keeps the card's screen blank until the card
  ; program sets the game's mode at its entry: a mode that the firmware
  ; sets again here (erratum E29) would show the loaded art while the IIgs
  ; starts.
  lda #SS_SCREEN_OFF
  sta .loword(SS_COMMAND)
  rts
:
  ; The flags of the last two groups (the text mirror states FINAL and
  ; BLANK).
  lda record_header+RECORD_CONTROL
  and #RECORD_FINAL_SRAM
  beq :+
  lda #1
  sta mirror_final
:
  lda record_header+RECORD_CONTROL
  and #RECORD_FINAL_VRAM
  beq :+
  lda #1
  sta video_final
  lda #SS_SCREEN_OFF         ; the text video RAM is about to become game data:
  sta .loword(SS_COMMAND)    ; blank only this final, short part
:
  lda record_header+RECORD_MASK
  sta upload_map_mask
  ; The record's bytes: RECORD_SIZE, or RECORD_STORED of a packed record
  ; (nonzero and below DATA_BUFFER_SIZE).
  lda record_header+RECORD_SIZE
  sta amount
  sta read_request
  lda record_header+RECORD_SIZE+1
  sta amount+1
  sta read_request+1
  lda record_header+RECORD_CONTROL
  and #RECORD_PACKED
  beq @read_upload
  lda record_header+RECORD_STORED
  sta read_request
  lda record_header+RECORD_STORED+1
  sta read_request+1
  ora read_request
  jeq failed
  lda read_request+1
  cmp #>DATA_BUFFER_SIZE
  jcs failed
@read_upload:
  jsr read_block
  jcs failed
  lda record_header+RECORD_CONTROL
  and #RECORD_PACKED
  beq @upload_ready
  ; A packed record: unpack it (native mode, interrupts off). The disk
  ; firmware may have changed SHADOW: the graphics pages off again before
  ; the unpack writes STARTUP_UNPACK_OUTPUT. The text pages stay copied.
  lda f:SHADOW
  ora #SHADOW_GRAPHICS
  sta f:SHADOW
  php
  sei
  clc
  xce
  ax16
  lda read_actual
  cmp read_request
  jne failed_native
  lda amount
  sta read_actual            ; the unpacked size, for the check below
  sta unpack_end
  jsr startup_unpack
  ax8
  sec
  xce
  plp
@upload_ready:
  ; The upload registers again after the disk read; ScreenOff again in the
  ; BLANK state.
  stz mirror_frozen
  jsr freeze_mirror
  lda video_final
  beq :+
  lda #SS_SCREEN_OFF
  sta .loword(SS_COMMAND)
:
  ; UploadData: SS_UPLOAD_LINEAR, the record's address, its size (3 bytes)
  ; and the IIgs source (3 bytes, which the card ignores).
  lda #SS_UPLOAD_DATA
  sta .loword(SS_COMMAND)
  jsr wait_ready
  lda #SS_UPLOAD_LINEAR
  sta .loword(SS_DATA_OUT)
  ldx #0
@address:
  lda record_header+RECORD_ADDRESS,x
  sta .loword(SS_DATA_OUT)
  inx
  cpx #RECORD_ADDRESS_SIZE
  bne @address
  lda amount
  sta .loword(SS_DATA_OUT)
  lda amount+1
  sta .loword(SS_DATA_OUT)
  lda #0                     ; the high byte of the length, then the source
  sta .loword(SS_DATA_OUT)
  sta .loword(SS_DATA_OUT)
  sta .loword(SS_DATA_OUT)
  sta .loword(SS_DATA_OUT)
  jsr wait_done
  jsr wait_ready
  ; The data phase: amount bytes from DATA_BUFFER, or from
  ; STARTUP_UNPACK_OUTPUT for a packed record; whole passes of SEND_UNROLL
  ; bytes, then the rest one at a time (native mode, long stores to the
  ; card's port).
  clc
  xce
  ax16
.a16
.i16
  lda amount
  cmp read_actual
  jne failed_native
  and #.loword(~(SEND_UNROLL-1)) ; the bytes of the whole passes
  sta send_limit
  ldx #0
  a8
.a8
  lda record_header+RECORD_CONTROL
  and #RECORD_PACKED
  bne @send_unpacked
  cpx send_limit
  beq @send_tail
@send:
.repeat SEND_UNROLL
  lda f:DATA_BUFFER,x
  sta f:SS_DATA_OUT
  inx
.endrepeat
  cpx send_limit
  bcc @send
@send_tail:
  cpx amount
  beq @sent
@send_tail_loop:
  lda f:DATA_BUFFER,x
  sta f:SS_DATA_OUT
  inx
  cpx amount
  bcc @send_tail_loop
  bra @sent
@send_unpacked:
  cpx send_limit
  beq @unpacked_tail
@unpacked_loop:
.repeat SEND_UNROLL
  lda f:STARTUP_UNPACK_OUTPUT,x
  sta f:SS_DATA_OUT
  inx
.endrepeat
  cpx send_limit
  bcc @unpacked_loop
@unpacked_tail:
  cpx amount
  beq @sent
@unpacked_tail_loop:
  lda f:STARTUP_UNPACK_OUTPUT,x
  sta f:SS_DATA_OUT
  inx
  cpx amount
  bcc @unpacked_tail_loop
@sent:
  ; The end of the data phase, the bar, the next record.
  ax8
.a8
.i8
  sec
  xce
  jsr wait_done
  jsr mirror_progress
  jmp @record

; ---------------------------------------------------------------------------
; wait_ready: wait until the card shows SS_READY: it waits for the bytes of
; a command. No bound: the loader checked the card (detect_secondsight).
;
; In:       emulation mode, D = 0
; Out:      the card waits for the bytes
; Changes:  A
; Keeps:    X, Y
; Original: none
; ---------------------------------------------------------------------------
wait_ready:
  lda .loword(SS_HANDSHAKE)
  cmp #SS_READY
  bne wait_ready
  rts

; ---------------------------------------------------------------------------
; wait_done: wait until the card shows SS_PHASE_DONE: it has read the bytes
; of the phase. No bound, as wait_ready.
;
; In:       emulation mode, D = 0
; Out:      the phase is finished
; Changes:  A
; Keeps:    X, Y
; Original: none
; ---------------------------------------------------------------------------
wait_done:
  lda .loword(SS_HANDSHAKE)
  bne wait_done                 ; SS_PHASE_DONE is 0
  rts
.assert SS_PHASE_DONE = 0, error ; the BNE of wait_done
send_limit: .res 2           ; load_secondsight: amount rounded down to whole passes

.include "boot_unpack.s"
.a8
.i8

; ---------------------------------------------------------------------------
; detect_secondsight: the card's GetStatus (host-commands.md): one dummy
; read, then SS_STATUS_SIZE bytes. The card is there when the signature
; "GSVGA" and the count SS_STATUS_BYTES agree. The loader opens no file
; before this check.
;
; In:       emulation mode, D = 0
; Out:      carry clear: the card answered; firmware_status. Carry set: no
;           card (no answer in 65,536 x 256 polls, or another signature)
; Changes:  A, X, Y
; Original: none
; ---------------------------------------------------------------------------
detect_secondsight:
  stz .loword(SS_COMMAND)    ; SS_GET_STATUS
  ; The answer: SS_READY, within 65,536 x 256 polls.
  ldy #0
  ldx #0
@wait:
  lda .loword(SS_HANDSHAKE)
  cmp #SS_READY
  beq @reply
  dex
  bne @wait
  dey
  bne @wait
  sec
  rts
@reply:
  ; The dummy read returns the handshake byte; then the status bytes.
  lda .loword(SS_DATA_IN)
  ldx #0
@read:
  lda .loword(SS_DATA_IN)
  sta firmware_status,x
  inx
  cpx #SS_STATUS_SIZE
  bne @read
  ldx #SS_SIGNATURE_SIZE-1
@signature:
  lda firmware_status+SS_SIGNATURE,x
  cmp firmware_signature,x
  bne @absent
  dex
  bpl @signature
  lda firmware_status+SS_STATUS_COUNT
  cmp #SS_STATUS_BYTES
  bne @absent
  clc
  rts
@absent:
  sec
  rts
.assert SS_GET_STATUS = 0, error ; the STZ of the command

; ---------------------------------------------------------------------------
; check_memory: find the banks of fast RAM, and fail when a bank that the
; game uses (MEMORY_FIRST_BANK to MEMORY_LAST_BANK) is missing. It runs
; before the first load, so its marks overwrite nothing that is needed.
;
; The probe writes a mark into every bank from PROBE_TOP_BANK down to
; MEMORY_FIRST_BANK, then reads the banks in the same order, once with a
; byte at offset 0 and once with PROBE_WORD at PROBE_OFFSET. The access
; before each read is to another bank at the same offset, so an
; accelerator's cache (Zip Chip, TransWarp: direct-mapped, the full address
; as the tag) cannot answer a read from its copy of the probe's own write.
; Banks $80-$FE (ROM, I/O, slow RAM) are never probed. A bank that either
; mark finds counts as RAM: one bad byte does not reject a bank.
;
; In:       emulation mode, D = 0
; Out:      carry clear: every bank of the game is RAM
;           carry set: memory_missing = the first missing bank
;           memory_bitmap  a bit for each bank $00-$7F that holds RAM
; Changes:  A, X; probe_ptr, probe_bit; the marks in the banks
; Keeps:    Y
; Original: none
; ---------------------------------------------------------------------------
check_memory:
  php
  sei
  clc
  xce
  x16
.a8
.i16
  ; The byte marks: bank b gets b xor $FF at b:0000.
  stz probe_ptr
  stz probe_ptr+1
  lda #PROBE_TOP_BANK
@write_byte:
  sta probe_ptr+2
  eor #$ff
  sta [probe_ptr]
  eor #$ff
  dec
  cmp #MEMORY_FIRST_BANK
  bcs @write_byte
  ; No bank found yet but the motherboard's $00 and $01.
  ldx #MEMORY_BITMAP_SIZE-1
@clear_bitmap:
  stz memory_bitmap,x
  dex
  bpl @clear_bitmap
  lda #MOTHERBOARD_BANKS
  sta memory_bitmap
  ; Read the byte marks back in the same order.
  lda #PROBE_TOP_BANK
@read_byte:
  sta probe_ptr+2
  eor #$ff
  cmp [probe_ptr]
  bne @next_byte
  lda probe_ptr+2
  jsr memory_bank_bit
  lda memory_bitmap,x
  ora probe_bit
  sta memory_bitmap,x
@next_byte:
  lda probe_ptr+2
  dec
  cmp #MEMORY_FIRST_BANK
  bcs @read_byte
  ; The word marks at PROBE_OFFSET, written, then read back.
  ldx #PROBE_OFFSET
  stx probe_ptr
  lda #PROBE_TOP_BANK
@write_word:
  sta probe_ptr+2
  jsr memory_probe_word
.a16
  sta [probe_ptr]
  a8
.a8
  lda probe_ptr+2
  dec
  cmp #MEMORY_FIRST_BANK
  bcs @write_word
  lda #PROBE_TOP_BANK
@read_word:
  sta probe_ptr+2
  jsr memory_probe_word
.a16
  cmp [probe_ptr]
  a8
.a8
  bne @next_word
  lda probe_ptr+2
  jsr memory_bank_bit
  lda memory_bitmap,x
  ora probe_bit
  sta memory_bitmap,x
@next_word:
  lda probe_ptr+2
  dec
  cmp #MEMORY_FIRST_BANK
  bcs @read_word
  ; Every bank of the game must be there.
  lda #MEMORY_FIRST_BANK
@required:
  jsr memory_bank_found
  bcc @missing
  inc
  cmp #MEMORY_LAST_BANK+1
  bcc @required
  ax8
.a8
.i8
  sec
  xce
  plp
  clc
  rts
@missing:
.a8
.i16
  sta memory_missing
  ax8
.a8
.i8
  sec
  xce
  plp
  sec
  rts

; ---------------------------------------------------------------------------
; memory_probe_word: A = the word mark of the bank A: the bank xor
; PROBE_WORD, so each bank holds a different value.
;
; In:       A8 the bank, X16
; Out:      A16 the mark
; Changes:  A
; Keeps:    X, Y
; Original: none
; ---------------------------------------------------------------------------
.a8
.i16
memory_probe_word:
  a16
.a16
  and #$00ff
  eor #PROBE_WORD
  rts

; ---------------------------------------------------------------------------
; memory_bank_found: carry = the bit of the bank A in memory_bitmap.
;
; In:       A8 the bank, X16
; Out:      carry set: the bank holds RAM; A8 the bank
; Changes:  X; probe_bit
; Keeps:    A, Y
; Original: none
; ---------------------------------------------------------------------------
.a8
.i16
memory_bank_found:
  jsr memory_bank_bit
  pha
  lda memory_bitmap,x
  and probe_bit
  cmp #1                        ; carry set for any bit set
  pla
  rts

; ---------------------------------------------------------------------------
; memory_bank_bit: X = the byte of the bank A in memory_bitmap (bank / 8),
; probe_bit = its bit (1 << (bank mod 8)).
;
; In:       A8 the bank, X16
; Out:      X16 the byte, probe_bit; A8 the bank
; Changes:  X; probe_bit
; Keeps:    A, Y
; Original: none
; ---------------------------------------------------------------------------
.a8
.i16
memory_bank_bit:
  pha
  a16
.a16
  and #7
  tax
  a8
.a8
  lda memory_bits,x
  sta probe_bit
  lda 1,s
  a16
.a16
  and #$00ff
  lsr
  lsr
  lsr
  tax
  a8
.a8
  pla
  rts

; ---------------------------------------------------------------------------
; firmware_banks: the first bank after the fast RAM that the firmware
; counted at its reset (FW_BANKS_ROM00 or FW_BANKS_ROM03, by the ROM
; version), or 0 when the ROM version or the count is not a known one. The
; firmware counts only the top bank and does not see a hole below it (its
; RAM sizing, read from the three ROMs), so the loader only shows this
; count on the memory error screen.
;
; In:       A8
; Out:      A8 the count, or 0; Z set only for 0
; Changes:  A
; Keeps:    X, Y
; Original: none
; ---------------------------------------------------------------------------
firmware_banks:
  lda f:ROMVER
  beq @rom00
  cmp #ROMVER_01
  beq @rom01_03
  cmp #ROMVER_03
  bne @unknown
@rom01_03:
  lda f:FW_BANKS_ROM03
  bra @check
@rom00:
  lda f:FW_BANKS_ROM00
@check:
  cmp #FW_BANKS_MIN
  bcc @unknown
  cmp #FW_BANKS_END
  bcc @done                     ; below FW_BANKS_END: Z clear
@unknown:
  lda #0
@done:
  rts

; ---------------------------------------------------------------------------
; memory_details: the three RAM lines of the memory error screen: the RAM
; found (the banks of memory_bitmap and the two slow banks), the RAM that
; the firmware counted, the first missing bank. Only a failed bank check
; calls it, after the main error line.
;
; In:       A8 X8, emulation mode; memory_bitmap, memory_missing
; Out:      the lines on the text page (rows 13-15)
; Changes:  A, X, Y; found_value, firmware_value, missing_value;
;           probe_number, probe_digit
; Original: none
; ---------------------------------------------------------------------------
.a8
.i8
memory_details:
  ; The RAM found: the bits of memory_bitmap and SLOW_BANKS.
  clc
  xce
  x16
.i16
  ldy #SLOW_BANKS
  ldx #MEMORY_BITMAP_SIZE-1
@byte:
  lda memory_bitmap,x
@bit:
  asl
  bcc :+
  iny
:
  cmp #0
  bne @bit
  dex
  bpl @byte
  a16
.a16
  tya
  ldx #found_value
  jsr memory_kilobytes
.a8
  ; The firmware's count (its banks and the two slow banks), when it has
  ; one; else firmware_value keeps "UNKNOWN". Z: firmware_banks sets it
  ; only for an unknown count.
  jsr firmware_banks
  beq @no_firmware
  a16
.a16
  and #$00ff
  inc
  inc                           ; + SLOW_BANKS
  ldx #firmware_value
  jsr memory_kilobytes
.a8
@no_firmware:
  ; The first missing bank in two hex digits.
  lda memory_missing
  lsr
  lsr
  lsr
  lsr
  jsr memory_hex
  sta missing_value
  lda memory_missing
  and #15                       ; the low digit
  jsr memory_hex
  sta missing_value+1
  ; The three lines.
  ax8
.a8
.i8
  sec
  xce
  ldx #0
@found:
  lda found_text,x
  beq @firmware_start
  ora #TEXT_NORMAL
  sta f:TEXT_ROW_13+DETAIL_COLUMN,x
  inx
  bne @found
@firmware_start:
  ldx #0
@firmware:
  lda firmware_text,x
  beq @missing_start
  ora #TEXT_NORMAL
  sta f:TEXT_ROW_14+DETAIL_COLUMN,x
  inx
  bne @firmware
@missing_start:
  ldx #0
@missing:
  lda missing_text,x
  beq @done
  ora #TEXT_NORMAL
  sta f:TEXT_ROW_15+DETAIL_COLUMN,x
  inx
  bne @missing
@done:
  rts
.assert SLOW_BANKS = 2, error ; the two INCs above

; ---------------------------------------------------------------------------
; memory_hex: A = the hex digit character of A (0-15).
;
; In:       A8 the value, 0-15
; Out:      A8 the character
; Changes:  A
; Keeps:    X, Y
; Original: none
; ---------------------------------------------------------------------------
.a8
.i16
memory_hex:
  cmp #10
  bcc :+
  adc #'A'-'0'-10-1             ; carry 1 from the CMP
:
  adc #'0'
  rts

; ---------------------------------------------------------------------------
; memory_kilobytes: the text of A x BANK_KB at X: KB_DIGITS decimal digits
; with no leading zero for the thousands (every count here is 256 KB or
; more), then K and a zero byte. Each digit counts the subtractions of its
; power of ten (memory_tens).
;
; In:       A16 the banks, X16 the address of the text
; Out:      the text; A8
; Changes:  A, X, Y; probe_number, probe_digit
; Original: none
; ---------------------------------------------------------------------------
.a16
.i16
memory_kilobytes:
  asl
  asl
  asl
  asl
  asl
  asl                           ; x BANK_KB
  sta probe_number
  ldy #0
@place:
  lda #'0'
  sta probe_digit
  lda probe_number
@subtract:
  cmp memory_tens,y
  bcc @digit
  sbc memory_tens,y
  inc probe_digit
  bra @subtract
@digit:
  sta probe_number
  a8
.a8
  lda probe_digit
  cpy #0
  bne @store
  cmp #'0'
  beq @next                     ; no thousands digit
@store:
  sta a:0,x
  inx
@next:
  a16
.a16
  iny
  iny
  cpy #KB_DIGITS*2
  bcc @place
  a8
.a8
  lda #'K'
  sta a:0,x
  stz a:1,x
  rts
.assert BANK_KB = 1 << 6, error ; the six ASLs above

memory_bits: .byte 1,2,4,8,16,32,64,128 ; memory_bank_bit: the bit of each bank in its byte
memory_tens: .word 1000,100,10,1 ; memory_kilobytes: the powers of ten of the digits
.assert * - memory_tens = KB_DIGITS*2, error
memory_bitmap: .res MEMORY_BITMAP_SIZE  ; check_memory: a bit for each bank found
memory_missing: .byte 0      ; check_memory: the first missing bank of the game; 0 none
found_text: .byte "RAM FOUND: "
found_value: .res 6          ; "nnnnK", 0
firmware_text: .byte "FIRMWARE: "
firmware_value: .asciiz "UNKNOWN"
missing_text: .byte "FAST BANK $"
missing_value: .byte "00 IS NOT RAM",0
.a8
.i8

; ---------------------------------------------------------------------------
; boot_screen: the loading screen: 40-column text page 1 with MouseText
; (the bar), no super hi-res, the loader's colours, the title, LOADING and
; the empty bar. The card's firmware shows it through its text mirror.
;
; In:       emulation mode
; Out:      the screen; the video switches
; Changes:  A, X
; Keeps:    Y
; Original: none
; ---------------------------------------------------------------------------
boot_screen:
  lda #0
  sta f:KBD                      ; 80STORE off, main 40-column text page
  sta f:CLR80VID
  sta f:SETALTCHAR               ; alternate characters enable MouseText
  sta f:TXTSET
  sta f:MIXCLR
  sta f:TXTPAGE1
  lda f:NEWVIDEO
  and #<~NEWVIDEO_SHR
  sta f:NEWVIDEO
  lda #BOOT_COLOURS
  sta f:TBCOLOR
  lda f:CLOCKCTL
  and #<~CLOCKCTL_BORDER         ; a black border
  sta f:CLOCKCTL
  jsr clear_text
  ldx #TITLE_LENGTH-1
@title:
  lda title,x
  ora #TEXT_NORMAL
  sta f:TEXT_ROW_2+TITLE_COLUMN,x  ; row 2, centred
  dex
  bpl @title
  ldx #LOADING_LENGTH-1
@label:
  lda loading_text,x
  ora #TEXT_NORMAL
  sta f:TEXT_ROW_21+LOADING_COLUMN,x ; row 21, centred
  dex
  bpl @label
  jsr draw_progress
  rts

; ---------------------------------------------------------------------------
; clear_text: text page 1 of bank $E0 all TEXT_SPACE, a page at a time.
;
; In:       emulation mode
; Out:      the text page
; Changes:  A, X
; Keeps:    Y
; Original: none
; ---------------------------------------------------------------------------
clear_text:
  ldx #0
  lda #TEXT_SPACE
@clear:
  sta f:TEXT_PAGE1,x
  sta f:TEXT_PAGE1+PAGE,x
  sta f:TEXT_PAGE1+2*PAGE,x
  sta f:TEXT_PAGE1+3*PAGE,x
  inx
  bne @clear
  rts

; ---------------------------------------------------------------------------
; black_screen: the text page all spaces, which the colours of boot_screen
; show black, so the IIgs display stays blank through the play (the game
; keeps the text page out of bank $E0, src/game.s) and after the menu. The
; colours stay: a TBCOLOR write is a Second Sight event (Second Sight
; reference, docs/reference/z180-io-ports.md, "Apple event addresses"),
; which the card program's DMA would take as a packet byte.
;
; In:       emulation mode
; Out:      the text page
; Changes:  A, X
; Keeps:    Y
; Original: none
; ---------------------------------------------------------------------------
black_screen:
  jsr clear_text
  rts

; ---------------------------------------------------------------------------
; load_progress: count the bytes just read (read_actual) in loaded_bytes,
; then fill each cell whose threshold they reached (progress_thresholds,
; from the exact size of SSMARIO.DATA) and draw the bar. The disk reads of
; the segments and of the card records move the same bar.
;
; In:       emulation mode, D = 0; read_actual
; Out:      loaded_bytes, progress_done; the bar (draw_progress)
; Changes:  A, X
; Keeps:    Y
; Original: none
; ---------------------------------------------------------------------------
load_progress:
  clc
  xce
  ax16
.a16
.i16
  lda loaded_bytes
  clc
  adc read_actual
  sta loaded_bytes
  lda loaded_bytes+2
  adc #0
  sta loaded_bytes+2
@threshold:
  ; The next cell fills when loaded_bytes reaches its 4-byte threshold.
  lda progress_done
  cmp #PROGRESS_CELLS
  bcs @draw
  asl
  asl                           ; x PROGRESS_ENTRY
  tax
  lda loaded_bytes+2
  cmp progress_thresholds+2,x
  bcc @draw
  bne @advance
  lda loaded_bytes
  cmp progress_thresholds,x
  bcc @draw
@advance:
  inc progress_done
  bra @threshold
@draw:
  ax8
.a8
.i8
  sec
  xce
  jsr draw_progress
  rts
.assert PROGRESS_ENTRY = 4, error ; the two ASLs above

; ---------------------------------------------------------------------------
; draw_progress: the bar on the Apple text page: a line at each end, then
; PROGRESS_CELLS cells, the first progress_done full.
;
; In:       emulation mode; progress_done
; Out:      the bar on the text page
; Changes:  A, X
; Keeps:    Y
; Original: none
; ---------------------------------------------------------------------------
draw_progress:
  lda #MT_RIGHT_LINE
  sta f:PROGRESS_TEXT-1      ; closes the bar's left end
  lda #MT_LEFT_LINE
  sta f:PROGRESS_TEXT+PROGRESS_CELLS   ; closes the bar's right end
  ldx #0
@cell:
  cpx progress_done
  lda #MT_CELL_EMPTY
  bcs :+
  lda #MT_CELL_FULL
:
  sta f:PROGRESS_TEXT,x
  inx
  cpx #PROGRESS_CELLS
  bne @cell
  rts

; ---------------------------------------------------------------------------
; mirror_progress: the bar in the card's text video RAM, in the FROZEN
; state, when progress_done changed: only the PROGRESS_CELLS characters of
; the bar, in plane 0, so the firmware's text image and its font stay. A
; SetMode of the text mode would clear both text planes before it draws, so
; it cannot refresh the bar. The firmware's text mode (ROM 1.4) has two
; plane addresses for each cell (SS_TEXT40); its alternate font has the
; MouseText cells at the glyphs FONT_CELL_EMPTY and FONT_CELL_FULL.
;
; In:       emulation mode, D = 0; progress_done, mirrored_progress,
;           mirror_final
; Out:      the bar on the card's screen; mirrored_progress
; Changes:  A, X, Y; upload_map_mask (CHARACTER_PLANE), mirror_frozen
; Original: none
; ---------------------------------------------------------------------------
mirror_progress:
  lda mirror_final
  bne @done
  lda progress_done
  cmp mirrored_progress
  beq @done
  sta mirrored_progress
  ; The upload registers with plane 0 only; then UploadData of bar_upload.
  lda #CHARACTER_PLANE       ; the characters only; the attributes and the font stay
  sta upload_map_mask
  stz mirror_frozen
  jsr freeze_mirror
  lda #SS_UPLOAD_DATA
  sta .loword(SS_COMMAND)
  jsr wait_ready
  ldx #0
@parameter:
  lda bar_upload,x
  sta .loword(SS_DATA_OUT)
  inx
  cpx #SS_UPLOAD_PARAMETERS
  bne @parameter
  jsr wait_done
  jsr wait_ready
  ; Each cell: its glyph, then the byte of its odd address.
  ldx #0
@cell:
  cpx progress_done
  lda #FONT_CELL_EMPTY
  bcs :+
  lda #FONT_CELL_FULL
:
  sta .loword(SS_DATA_OUT)
  lda #FONT_ODD_FILL
  sta .loword(SS_DATA_OUT)
  inx
  cpx #PROGRESS_CELLS
  bne @cell
  jsr wait_done
@done:
  rts

; ---------------------------------------------------------------------------
; freeze_mirror: unless mirror_frozen: the first time, the text mirror off
; (SetMode SS_MODE_TEXT40 with SS_NATIVE: the firmware draws nothing, and
; the last text image stays); then each time the VGA upload registers
; (upload_registers): the map mask of the record (upload_map_mask), the
; planar memory mode, write mode 0. UploadData writes through this CPU
; write path, so each byte goes to the selected planes as it comes; the
; build prepared each plane's bytes (scripts/boot_disk.py boot_uploads).
; The text scan stays on, and the display mode is not set again.
;
; In:       emulation mode, D = 0; mirror_frozen, mirror_disabled,
;           upload_map_mask
; Out:      mirror_frozen = 1; mirror_disabled = SS_NATIVE
; Changes:  A, X, Y
; Original: none
; ---------------------------------------------------------------------------
freeze_mirror:
  lda mirror_frozen
  bne @done
  lda #1
  sta mirror_frozen
  lda mirror_disabled
  bne @register_setup
  lda #SS_NATIVE             ; the flag of SetMode and the value of mirror_disabled
  sta mirror_disabled
  jsr text_emulation
@register_setup:
  ; One SetVGAReg for each SS_VGA_REG_PARAMETERS bytes of upload_registers.
  ldx #0
@register:
  lda #SS_SET_VGA_REG
  sta .loword(SS_COMMAND)
  jsr wait_ready
  ldy #SS_VGA_REG_PARAMETERS
@byte:
  lda upload_registers,x
  sta .loword(SS_DATA_OUT)
  inx
  dey
  bne @byte
  jsr wait_done
  cpx #upload_registers_end-upload_registers
  bne @register
@done:
  rts

; ---------------------------------------------------------------------------
; text_emulation: SetMode SS_MODE_TEXT40 with the emulation flag A, then
; wait for its SS_DONE (no bound).
;
; In:       emulation mode, D = 0; A = SS_EMULATION or SS_NATIVE
; Out:      the mode set
; Changes:  A
; Keeps:    X, Y
; Original: none
; ---------------------------------------------------------------------------
text_emulation:
  pha
  lda #SS_SET_MODE
  sta .loword(SS_COMMAND)
  jsr wait_ready
  lda #SS_MODE_TEXT40
  sta .loword(SS_DATA_OUT)
  pla
  sta .loword(SS_DATA_OUT)
  jsr wait_done
@mode:
  lda .loword(SS_HANDSHAKE)
  cmp #SS_DONE
  bne @mode
  rts

; ---------------------------------------------------------------------------
; unsupported_driver, no_memory, no_secondsight, failed: the error screens:
; requirement_error shows the title and the message at X (low) and Y
; (high), with the RAM lines after a failed memory check, and stops.
; unsupported_driver comes before load_secondsight, while the card's text
; emulation still shows the text page; it sets the emulation again before
; the message goes there.
;
; Self-changing code: the message address goes into the operand of the
; LDA at error_text.
;
; In:       emulation mode, D = 0
; Out:      never returns
; Changes:  A, X, Y
; Original: none
; ---------------------------------------------------------------------------
unsupported_driver:
  lda #SS_EMULATION
  jsr text_emulation
  ldx #<unsupported_driver_message
  ldy #>unsupported_driver_message
  jmp requirement_error
no_memory:
  ldx #<no_memory_message
  ldy #>no_memory_message
  bra requirement_error
no_secondsight:
  ldx #<no_secondsight_message
  ldy #>no_secondsight_message
requirement_error:
  stx error_text+1
  sty error_text+2
  jsr clear_text
  ldx #TITLE_LENGTH-1
@title:
  lda title,x
  ora #TEXT_NORMAL
  sta f:TEXT_ROW_2+TITLE_COLUMN,x
  dex
  bpl @title
  ldx #0
error_text:
  lda a:0,x                  ; the operand is the message address
  beq @details
  ora #TEXT_NORMAL
  sta f:TEXT_ROW_11+ERROR_COLUMN,x
  inx
  bne error_text
@details:
  lda memory_missing
  beq @hold
  jsr memory_details
@hold:
  bra @hold
failed:
  ldx #<load_error_message
  ldy #>load_error_message
  bra requirement_error
load_error_message: .asciiz "LOAD ERROR"
no_secondsight_message: .asciiz "SECOND SIGHT NOT DETECTED"
no_memory_message: .asciiz "THE GAME REQUIRES 1 MB OF MEMORY"
unsupported_driver_message: .asciiz "UNSUPPORTED BOOT DEVICE DRIVER"
title: .byte "SUPER MARIO BROS."
.assert * - title = TITLE_LENGTH, error, "TITLE_LENGTH"
loading_text: .byte "LOADING"
.assert * - loading_text = LOADING_LENGTH, error
firmware_signature: .byte "GSVGA" ; detect_secondsight: the GetStatus signature
.assert * - firmware_signature = SS_SIGNATURE_SIZE, error

; The loader's state. The text mirror (the file header gives its states).
firmware_status: .res SS_STATUS_SIZE ; detect_secondsight: the GetStatus bytes
video_final: .byte 0         ; 1 from the first RECORD_FINAL_VRAM record on: ScreenOff before each upload
mirror_frozen: .byte 0       ; 1: the upload registers are set since the last disk read
mirror_disabled: .byte 0     ; SS_NATIVE: the text emulation is off (the last image stays); 0: on
mirror_final: .byte 0        ; 1 from the first RECORD_FINAL_SRAM record on: the bar stops
mirrored_progress: .byte 0   ; mirror_progress: the progress_done of the bar on the card
bar_upload:                  ; UploadData of the progress bar cells
  .byte SS_UPLOAD_LINEAR
  .faraddr SS_TEXT40+(PROGRESS_ROW*TEXT_COLUMNS+PROGRESS_COLUMN)*SS_TEXT40_CELL ; plane 0
  .faraddr PROGRESS_CELLS*SS_TEXT40_CELL ; each character byte and its unused odd address
  .faraddr 0                 ; the IIgs source: the card ignores it
.assert * - bar_upload = SS_UPLOAD_PARAMETERS, error
upload_registers:            ; freeze_mirror: SS_VGA_REG_PARAMETERS bytes for each register
  .word VGA_SEQ_INDEX        ; sequencer map mask: the planes of the record
  .byte SEQ_MAP_MASK
  .word VGA_SEQ_DATA
upload_map_mask:
  .byte ALL_PLANES
  .word VGA_SEQ_INDEX        ; unchained, odd/even CPU writes disabled
  .byte SEQ_MEMORY_MODE
  .word VGA_SEQ_DATA
  .byte SEQ_PLANAR
  .word VGA_GC_INDEX         ; write mode 0, no odd/even read addressing
  .byte GC_MODE
  .word VGA_GC_DATA
  .byte GC_WRITE_MODE_0
upload_registers_end:
.assert (upload_registers_end - upload_registers) .mod SS_VGA_REG_PARAMETERS = 0, error
; The progress.
loaded_bytes: .dword 0       ; load_progress: the bytes of SSMARIO.DATA read
progress_done: .word 0       ; load_progress: the full cells, 0 to PROGRESS_CELLS
; The bytes of SSMARIO.DATA read when each progress cell fills: a copy of the
; table of the data file header (DATA_PROGRESS, scripts/boot_disk.py).
progress_thresholds: .res PROGRESS_CELLS*PROGRESS_ENTRY
; The load.
path: .byte 12,"SSMARIO.DATA"
read_request: .res 2         ; read_block: the bytes to read
read_actual: .res 2          ; read_block: the bytes read; load_secondsight: the record's size
segments: .res 1             ; the segment loop: the segments left
current: .res 1              ; the segment loop: the offset of the segment's entry in headers
headers: .res MAX_SEGMENTS*SEGMENT_ENTRY ; a copy of the segment table of the header block
startup_records: .res 1      ; DATA_STARTUP: nonzero: card startup records follow
record_header: .res RECORD_HEADER_SIZE ; load_secondsight: the header of the record
dest: .res 3                 ; the segment loop: the next host address
remaining: .res 3            ; the segment loop: the bytes left to read
amount: .res 2               ; the bytes of this block, or of the record
probe_bit: .res 1            ; check_memory: the bit of the bank in memory_bitmap
probe_number: .res 2         ; memory_kilobytes: the value left to print
probe_digit: .res 1          ; memory_kilobytes: the digit
; The file reader: its zero page and its two buffers.
PR_ZP = pr_zp
PR_DBUF = .loword(READER_BUFFERS)
PR_IBUF = .loword(READER_BUFFERS)+PR_BLOCK_SIZE
.assert READER_BUFFERS+READER_BUFFERS_SIZE <= BOOT_LOADER, error
.assert READER_BUFFERS_SIZE = 2*PR_BLOCK_SIZE, error
.a8
.i8
.include "prodos_read.s"
loader_end:
