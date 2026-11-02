; The background ring: the card's copy of the original's two name tables,
; and the palette. The screen records of each packet (src/packet_layout.inc
; REC_*) change them here.
;
; The original shows a 64 x 30 tile ring: name table 0 is ring columns 0-31,
; name table 1 columns 32-63, and world tile column T is ring column
; T mod 64 (the scroll register takes the low bit of the screen page as the
; name table bit). Each cell holds a tile and its palette; the attribute
; bytes of the original only set cell palettes and are not kept.
;
; A changed cell is marked in the dirty map of each page (page.s draws it on
; that page's next picture). A changed cell of the status rows (name table 0,
; rows 0-3) is marked in status_dirty too, and the end of the records draws
; each such cell into the status copies once (status.s): a level start
; changes a status cell several times (the clear, its tile, its palette).
;
; Routines:
;   ring_clear_all      start: every cell tile 0, every dirty bit set
;   apply_records       apply one packet's screen records
;   record_cells, record_square, record_column, record_palettes,
;   record_colours, record_clear
;                       the record kinds (inside apply_records)
;   set_square_palette  the palette of a 2 x 2 square
;   set_cell_tile, set_cell_palette  one cell, when it differs
;   cell_changed        mark a cell dirty, and a status cell for its copies
;   status_flush        draw the changed status cells into their copies
;   mark_cell_dirty     a cell's bit in both dirty maps
;   cell_address        a cell's tile byte in the ring
;
; Fields of the ring, each RING_COLUMNS x TILE_ROWS bytes, row after row:
;   ring_tiles      the tile of each cell (background pattern table)
;   ring_palettes   the palette of each cell, 0-3
; palette_colours: the original's 32 palette bytes ($3F00-$3F1F): bits 0-5
; a colour of the picture chip. picture.s writes them to the colour chip at
; the next flip when palette_changed is nonzero.

        .include "video.inc"
        .include "ring.inc"
        .include "packet_layout.inc"

        .global ring_tiles, ring_palettes, palette_colours, palette_changed
        .global ring_clear_all, apply_records, mark_cell_dirty, dirty_maps
        .global bit_of_column, cell_address

        .equ NAME_TABLE_COLUMNS, 32     ; the ring columns of one of the original's name tables
        .equ PALETTE_ENTRIES, 32        ; the original's palette: 4 background and 4 sprite palettes
        .equ PALETTE_PENS, 4            ; the entries of one palette
        .equ PALETTE_MIRROR, 16         ; a sprite palette's pen 0 entry is the background entry 16 lower
        .equ COLOUR_BITS, 0x3F          ; the bits of one of the picture chip's colours
        .equ START_COLOUR, 0x0F         ; black: the palette until the game sends its own

        .section .vars.ring,"aw",@nobits
        .balign 256
ring_tiles: .ds.b RING_STRIDE
ring_palettes: .ds.b RING_STRIDE
; One dirty map for each page: bit (column mod 8) of byte row x 8 +
; column / 8 is set when the cell changed after the page last drew it.
dirty_maps: .ds.b 2 * DIRTY_MAP_SIZE
        .balign PALETTE_ENTRIES
palette_colours: .ds.b PALETTE_ENTRIES  ; record_colours writes it; picture.s palette_commit reads it
palette_changed: .ds.b 1                ; nonzero: palette_colours changed since the last flip
column_metatile: .ds.b 1                ; record_column: the metatile being drawn
status_dirty: .ds.b STATUS_TILE_ROWS * 4 ; a bit for each status cell: 4 bytes of 8 columns a row

        .section .rodata.ring,"a",@progbits
; bit_of_column: the dirty-map bit of a column, by column mod 8.
bit_of_column:
        .byte 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80

        .section .text.ring,"ax",@progbits

; ring_clear_all: every cell tile 0 in palette 0, every dirty bit set, the
; palette black. The game clears the ring itself (REC_CLEAR) before it
; shows a picture; this gives the card a known start.
; Changes: AF, BC, DE, HL
ring_clear_all:
        ld hl,ring_tiles
        ld (hl),0
        ld de,ring_tiles + 1
        ld bc,RING_STRIDE - 1
        ldir
        ld hl,ring_palettes
        ld (hl),0
        ld de,ring_palettes + 1
        ld bc,RING_STRIDE - 1
        ldir
        ld hl,dirty_maps
        ld (hl),0xFF
        ld de,dirty_maps + 1
        ld bc,2 * DIRTY_MAP_SIZE - 1
        ldir
        ld hl,palette_colours
        ld (hl),START_COLOUR
        ld de,palette_colours + 1
        ld bc,PALETTE_ENTRIES - 1
        ldir
        ld a,1
        ld (palette_changed),a
        ret

; ---------------------------------------------------------------------------
; apply_records: apply the screen records of a packet (src/packet_layout.inc
; REC_*), then draw the changed status cells into their copies once
; (status_flush).
;
; In:       HL   the first record (after the packet's sprite entries)
; Out:      the ring, the dirty maps, the status copies, the palette
; Changes:  AF, BC, DE, HL, IX
; Time:     each picture: about 300 clocks for each changed cell, 150 for an
;           unchanged one; a REC_CLEAR is about 1,000,000 clocks
; Original: the effects of $8E92-$8EE6 (the write lists) and $8E19
;           (the clear), as ring cells (document 02 sections 11-20)
; ---------------------------------------------------------------------------
apply_records:
        ld a,(hl)
        inc hl
        cp REC_CELLS
        jr z,record_cells
        cp REC_SQUARE
        jr z,record_square
        cp REC_COLUMN
        jp z,record_column
        cp REC_PALETTES
        jp z,record_palettes
        cp REC_COLOURS
        jp z,record_colours
        cp REC_CLEAR
        jp z,record_clear
        jp status_flush                 ; REC_END
        .if REC_END != 0
        .error "apply_records: REC_END is the only kind not tested"
        .endif

; record_cells: row, column, count, then count tiles, across. A column past
; the last one of its name table goes on at column 0 of the next row of the
; same table, as the picture chip's address does.
record_cells:
        ld d,(hl)                       ; D = the row
        inc hl
        ld e,(hl)                       ; E = the ring column
        inc hl
        ld b,(hl)                       ; B = the count
        inc hl
1:      ld c,(hl)
        inc hl
        push hl                         ; set_cell_tile changes HL
        call set_cell_tile
        pop hl
        ld a,e
        inc e
        and NAME_TABLE_COLUMNS - 1
        cp NAME_TABLE_COLUMNS - 1
        jr nz,2f
        ld a,e
        sub NAME_TABLE_COLUMNS          ; back to column 0 of the table
        ld e,a
        inc d                           ; of the next row
2:      djnz 1b
        jp apply_records

; record_square: row, column (both even), then the 4 tiles of a 2 x 2
; square: top left, top right, bottom left, bottom right. The palette stays.
record_square:
        ld d,(hl)
        inc hl
        ld e,(hl)
        inc hl
        ld b,2                          ; two rows
1:      ld c,(hl)
        inc hl
        push hl                         ; set_cell_tile changes HL
        call set_cell_tile
        pop hl
        inc e
        ld c,(hl)
        inc hl
        push hl
        call set_cell_tile
        pop hl
        dec e
        inc d
        djnz 1b
        jp apply_records

; record_column: the metatile column c (0-31: ring columns 2c and 2c + 1),
; then METATILE_ROWS metatiles, top first: metatile r covers cell rows
; METATILE_FIRST_ROW + 2r and + 2r + 1. Each metatile's 4 tiles come from
; the metatile table (scripts/tiles.py metatile_tiles: four 256-byte parts,
; left top, left bottom, right top, right bottom, by metatile), and its
; palette is its bits 7-6, for the whole square.
record_column:
        ld a,(hl)
        inc hl
        add a,a
        ld e,a                          ; E = the left ring column
        ld d,METATILE_FIRST_ROW         ; D = the top row of the metatile
        ld b,METATILE_ROWS
1:      push bc
        ld a,(hl)                       ; A = the metatile
        inc hl
        push hl
        ld (column_metatile),a
        ld l,a
        ld h,metatile_tiles >> 8        ; part 0: the left top tile
        ld c,(hl)
        push hl
        call set_cell_tile              ; keeps BC, DE
        pop hl
        inc h                           ; part 1: the left bottom tile
        inc d
        ld c,(hl)
        push hl
        call set_cell_tile
        pop hl
        inc h                           ; part 2: the right top tile
        dec d
        inc e
        ld c,(hl)
        push hl
        call set_cell_tile
        pop hl
        inc h                           ; part 3: the right bottom tile
        inc d
        ld c,(hl)
        call set_cell_tile
        dec d
        dec e
        ld a,(column_metatile)
        rlca
        rlca
        and PALETTE_PENS - 1            ; bits 7-6: the palette
        ld c,a
        call set_square_palette
        pop hl
        pop bc
        inc d
        inc d                           ; the next metatile row
        djnz 1b
        jp apply_records

; record_palettes: square row, square column, count, then count palettes
; (0-3): each sets the palette of a 2 x 2 square of cells, across.
record_palettes:
        ld a,(hl)
        inc hl
        add a,a
        ld d,a                          ; D = the square's top row
        ld a,(hl)
        inc hl
        add a,a
        ld e,a                          ; E = its left column
        ld b,(hl)
        inc hl
1:      ld c,(hl)
        inc hl
        push hl                         ; set_square_palette changes HL
        call set_square_palette
        pop hl
        inc e
        inc e
        djnz 1b
        jp apply_records

; record_colours: first entry, count, then count colours. Entries 16, 20, 24
; and 28 are the same bytes as 0, 4, 8 and 12 (the picture chip mirrors
; them); entry 0 is the backdrop: every background pixel of pen 0. The
; colour chip slot of an entry is the entry (pixel values, tiles.py).
record_colours:
        ld e,(hl)                       ; E = the entry
        inc hl
        ld b,(hl)                       ; B = the count
        inc hl
1:      ld a,e
        and PALETTE_ENTRIES - 1
        ld c,a
        and PALETTE_PENS - 1
        jr nz,2f
        ld a,c
        and PALETTE_MIRROR - 1          ; pen 0 of a sprite palette: the background's byte
        ld c,a
2:      ld a,(hl)
        inc hl
        and COLOUR_BITS                 ; the original's colours have 6 bits
        push hl
        ld h,palette_colours >> 8
        ld l,a
        ld a,c
        or palette_colours & 0xFF       ; palette_colours is 32-aligned: no carry
        ld c,l                          ; C = the colour
        ld l,a
        ld a,c
        cp (hl)
        jr z,3f
        ld (hl),a
        ld a,1
        ld (palette_changed),a
3:      pop hl
        inc e
        djnz 1b
        jp apply_records

; record_clear: the tile; every cell of the ring gets it, with palette 0
; (the original's clear of both name tables, document 02 section 12).
record_clear:
        ld c,(hl)                       ; C = the tile
        inc hl
        push hl
        ld d,0
1:      ld e,0
2:      call set_cell_tile              ; keeps BC, DE
        push bc
        ld c,0
        call set_cell_palette
        pop bc
        inc e
        ld a,e
        cp RING_COLUMNS
        jr c,2b
        inc d
        ld a,d
        cp RING_ROWS
        jr c,1b
        pop hl
        jp apply_records

; set_square_palette: palette C for the 2 x 2 cells from row D, column E.
; set_cell_palette skips a row past the last one (the last square row of the
; original's attribute bytes covers rows 30 and 31, which no tile row has).
; Changes: AF, HL, IX. Keeps: BC, DE.
set_square_palette:
        push de
        call set_cell_palette
        inc e
        call set_cell_palette
        dec e
        inc d
        call set_cell_palette
        inc e
        call set_cell_palette
        pop de
        ret

; set_cell_tile: tile C into the cell at row D, ring column E, when it
; differs.
; Changes: AF, HL, IX. Keeps: BC, DE.
set_cell_tile:
        ld a,d
        cp TILE_ROWS
        ret nc
        call cell_address
        ld a,c
        cp (hl)
        ret z
        ld (hl),a
        jp cell_changed

; set_cell_palette: palette C into the cell at row D, ring column E, when it
; differs.
; Changes: AF, HL, IX. Keeps: BC, DE.
set_cell_palette:
        ld a,d
        cp TILE_ROWS
        ret nc
        call cell_address
        ld a,h
        add a,RING_STRIDE >> 8          ; the palette byte of the cell
        ld h,a
        ld a,c
        cp (hl)
        ret z
        ld (hl),a
        ; fall through

; cell_changed: mark the cell at row D, ring column E dirty in both pages;
; a status cell (rows 0-3 of name table 0) also goes into the status copies.
; Changes: AF, HL, IX. Keeps: BC, DE.
cell_changed:
        call mark_cell_dirty
        ld a,d
        cp STATUS_TILE_ROWS
        ret nc
        ld a,e
        cp NAME_TABLE_COLUMNS
        ret nc
; A status cell: its bit in status_dirty.
        push bc
        ld a,d
        add a,a
        add a,a                         ; 4 bytes a row
        ld c,a
        ld a,e
        rrca
        rrca
        rrca
        and 3
        add a,c
        ld c,a
        ld b,0
        ld hl,status_dirty
        add hl,bc
        ld a,e
        and 7
        ld c,a
        ld ix,bit_of_column
        add ix,bc
        ld a,(ix+0)
        or (hl)
        ld (hl),a
        pop bc
        ret

; status_flush: draw each status cell of status_dirty into the status
; copies (status.s status_cell, which keeps BC and DE), and clear its bit.
; Changes: AF, BC, DE, HL, IX
status_flush:
        ld hl,status_dirty
        ld d,0                          ; D = the row
1:      ld b,0                          ; B = the ring column of bit 0 of the byte
2:      ld a,(hl)
        or a
        jr z,4f
        ld (hl),0
        push hl
        ld c,a                          ; C = the bits not yet drawn
        ld e,b                          ; E = the column of bit 0 of C
3:      srl c
        call c,status_cell
        inc e
        ld a,c
        or a
        jr nz,3b
        pop hl
4:      inc hl
        ld a,b
        add a,8                         ; the 8 columns of the next byte
        ld b,a
        cp NAME_TABLE_COLUMNS           ; the status rows are in name table 0
        jr c,2b
        inc d
        ld a,d
        cp STATUS_TILE_ROWS
        jr c,1b
        ret

; mark_cell_dirty: set the bit of row D, ring column E in both dirty maps.
; Changes: AF, HL, IX. Keeps: BC, DE.
mark_cell_dirty:
        push bc
        ld a,e
        and 7
        ld c,a
        ld b,0
        ld ix,bit_of_column
        add ix,bc
        ld b,(ix+0)                     ; B = the bit
        ld l,d
        ld h,DIRTY_ROW_BYTES
        mlt hl                          ; the first byte of the row
        ld a,e
        rrca
        rrca
        rrca
        and 7
        add a,l
        ld l,a                          ; no carry: the map rows are 8 bytes, 30 rows
        push de
        ld de,dirty_maps
        add hl,de
        ld a,(hl)
        or b
        ld (hl),a
        ld de,DIRTY_MAP_SIZE
        add hl,de
        ld a,(hl)
        or b
        ld (hl),a
        pop de
        pop bc
        ret

; cell_address: HL = the ring_tiles byte of row D, ring column E (ring_tiles
; starts a 256-byte page). Its palette byte is RING_STRIDE later.
; Changes: AF, HL. Keeps: BC, DE.
cell_address:
        ld l,d
        ld h,RING_COLUMNS
        mlt hl
        ld a,l
        add a,e
        ld l,a
        ld a,h
        adc a,ring_tiles >> 8
        ld h,a
        ret
