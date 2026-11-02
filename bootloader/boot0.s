; Boot block of a ProDOS volume (block 0): loads one file of the volume
; directory to $2000 and runs it. No ProDOS.
;
; The firmware of a block device (SmartPort, an Apple SCSI card, a CFFA,
; the IIgs 3.5-inch drive) loads block 0 to $0800 and jumps to $0801 in
; emulation mode with X = slot * 16. This block reads through the block
; driver of that slot ($Cn00 + the byte at $CnFF; ProDOS 8 Technical
; Reference, the block device drivers).
;
; The file is a seedling or a sapling in the volume directory, at most
; $9E00 bytes. The name goes in bytes 4-19 (prodos_volume.py). The file
; starts at $2000 in emulation mode with X = the ProDOS unit number of the
; boot drive. The block uses $0A00-$0DFF and $42-$49.
;
; The volume (ProDOS 8 Technical Reference, the disk formats): the volume
; directory starts at block DIR_BLOCK; each directory block holds the
; number of the next one at DIR_NEXT (0: the last), then DIR_ENTRIES
; entries of ENTRY_SIZE bytes from DIR_ENTRY. An entry: byte 0 the storage
; type (high nibble) and the name length (low nibble), then the name; the
; key block at KEY_POINTER. A seedling's key block is its data. A sapling's
; key block is its index block: the low bytes of up to 256 block numbers,
; then their high bytes at INDEX_HIGH; the first zero number ends it.
;
; 6502 code: on any Apple II the file starts and can show its own message.

        .setcpu "6502"

CMD     = $42                   ; the block driver: command,
UNIT    = $43                   ;   unit,
BUF     = $44                   ;   buffer,
BLK     = $46                   ;   block
PTR     = $48                   ; the directory entry
DIR     = $0A00                 ; a directory block
INDEX   = $0C00                 ; the index block of the file
INDEX_HIGH = 256                ; an index block: the high bytes of its block numbers
LOAD    = $2000
TEXT    = $0400                 ; the text page
NORMAL  = $80                   ; a text page character: bit 7 set: normal text
SLOT_ROM = $C0                  ; + the slot: the page of the slot ROM
DRIVER_OFFSET = $FF             ; $CnFF: the offset of the block driver
READ_BLOCK = 1                  ; the block driver command
DIR_BLOCK = 2                   ; the volume directory starts at this block
DIR_NEXT = 2                    ; a directory block: the next block (2 bytes),
DIR_ENTRY = 4                   ;   the first entry,
DIR_ENTRIES = 13                ;   the entries,
ENTRY_SIZE = 39                 ;   of this size
NAME_BITS = $0F                 ; an entry: byte 0: the storage type and the name length
SEEDLING = $10                  ; storage types (byte 0, high nibble)
SAPLING = $20
TREE = $30
KEY_POINTER = 17                ; an entry: the key block (2 bytes)

        .segment "CODE"
; $0800: the firmware does not run this byte (it enters at $0801). $01 as
; in the boot block of ProDOS, where the Disk II boot ROM takes it as the
; count of sectors to load.
        .byte   $01
        jmp     boot
name:   .res    16              ; the boot file: its name length, then the name (prodos_volume.py)

; ---------------------------------------------------------------------------
; boot: find the file of name in the volume directory, load it to LOAD and
; run it.
;
; In:       emulation mode, X = slot * 16 (the firmware of the boot slot)
; Out:      the file runs with X = the boot unit; a disk error or no such
;           file: BOOT ERROR and a stop (fail)
; Changes:  everything; $0A00-$0DFF, $42-$49
; Original: none
; ---------------------------------------------------------------------------
; Find the block driver: $Cn00 + the byte at $CnFF of the boot slot n.
boot:   stx     UNIT
        txa
        lsr     a
        lsr     a
        lsr     a
        lsr     a
        ora     #SLOT_ROM
        sta     driver+1
        sta     PTR+1
        lda     #DRIVER_OFFSET
        sta     PTR
        ldy     #0
        lda     (PTR),y
        sta     driver
; Read the directory blocks, from DIR_BLOCK.
        lda     #DIR_BLOCK
        ldx     #0
dirblk: ldy     #>DIR
        jsr     read
; Each entry of the block: the same name length and name, then a seedling
; or a sapling.
        lda     #<(DIR + DIR_ENTRY)
        sta     PTR
        lda     #>(DIR + DIR_ENTRY)
        sta     PTR+1
        ldx     #DIR_ENTRIES
entry:  ldy     #0
        lda     (PTR),y
        and     #NAME_BITS
        cmp     name
        bne     skip
        tay
same:   lda     (PTR),y
        cmp     name,y
        bne     skip
        dey
        bne     same
        lda     (PTR),y         ; Y = 0: the storage type and the name length
        cmp     #TREE
        bcs     skip
        cmp     #SEEDLING
        bcs     found           ; a seedling or a sapling
skip:   lda     PTR
        clc
        adc     #ENTRY_SIZE
        sta     PTR
        bcc     :+
        inc     PTR+1
:       dex
        bne     entry
; The next directory block; block 0 ends the directory: no such file.
        lda     DIR+DIR_NEXT
        ldx     DIR+DIR_NEXT+1
        bne     dirblk
        tay
        bne     dirblk
        beq     fail

; The file. CMP #SAPLING leaves the carry set for a sapling; LDY, LDA, TAX
; and DEY change only N and Z, so the carry still tells it at BCC last,
; with X:A = the key block.
found:  cmp     #SAPLING
        ldy     #KEY_POINTER+1
        lda     (PTR),y
        tax
        dey
        lda     (PTR),y         ; the key block
        ldy     #>LOAD
        bcc     last            ; a seedling: the key block holds the data
; A sapling: its index block, then each of its blocks into the next two
; pages from LOAD.
        ldy     #>INDEX
        jsr     read
        lda     #>LOAD
        sta     page
next:   ldy     index
        lda     INDEX+INDEX_HIGH,y
        tax
        lda     INDEX,y
        bne     :+
        cpx     #0
        beq     run             ; the index ends at the first zero pointer
:       inc     index
        ldy     page
        inc     page
        inc     page            ; a block is two pages
        jsr     read
        jmp     next
last:   jsr     read
; Run the file with X = the boot unit.
run:    ldx     UNIT
        jmp     LOAD

; ---------------------------------------------------------------------------
; read: read block X:A to page Y through the block driver (call: the JMP
; through driver, whose RTS returns to read); a disk error goes to fail.
;
; In:       X:A the block, Y the page of the buffer
; Out:      the block in the buffer
; Changes:  A, X, Y (the driver); CMD, BUF, BLK, the driver's page zero
; Original: none
; ---------------------------------------------------------------------------
read:   sta     BLK
        stx     BLK+1
        sty     BUF+1
        lda     #0
        sta     BUF
        lda     #READ_BLOCK
        sta     CMD
        jsr     call
        bcs     fail
        rts
call:   jmp     (driver)        ; the driver's RTS returns to read

; ---------------------------------------------------------------------------
; fail: BOOT ERROR on the first text row, then stop.
;
; In:       nothing
; Out:      never returns
; Changes:  A, Y
; Original: none
; ---------------------------------------------------------------------------
fail:   ldy     #message_end-message-1
:       lda     message,y
        ora     #NORMAL
        sta     TEXT,y
        dey
        bpl     :-
hang:   jmp     hang

message: .byte  "BOOT ERROR"
message_end:
index:  .byte   0               ; the entry of the index block to read next
page:   .byte   0               ; the page that the next block goes to
driver: .word   0               ; the block driver of the boot slot
        .assert <driver <> $FF, lderror, "6502 JMP (abs) cannot read a vector at $xxFF"
        .assert * <= $0A00, lderror, "boot0 is larger than one block"
