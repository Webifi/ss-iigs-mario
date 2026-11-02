; The two display pages: the scroll of each page, and the background cells
; that it draws from the ring (ring.s).
;
; A page is a forward-moving buffer (video.inc): world group g of pixel row y
; is at P_ORIGIN + PAGE_PITCH x y + g. The card draws only into the back
; page; the front page shows. Each page remembers the world tile columns
; that it holds (P_LEFT to P_RIGHT) and has its own dirty map, so a cell
; that changed while the page was in front is drawn when it is the back page
; again.
;
; The window of a picture is world tile columns tile_left to tile_left + 32:
; the 33 columns that a pan of 1-3 pixels shows. Cells outside the window
; are not drawn; a column is drawn whole when it enters the window.
;
; A page state: page.inc. picture.s runs, for the back page of each
; picture: page_scroll, page_repair, page_draw_dirty, then the sprites
; (sprites.s) and the status band (status.s).
;
; Routines:
;   page_init        both pages hold nothing
;   page_scroll      draw the columns that the scroll brings into the window
;   page_restart     a page starts again at its base (inside page_scroll)
;   page_columns     draw a run of columns (inside page_scroll)
;   draw_column      draw one tile column of the window
;   clear_dirty      clear one dirty bit of a page
;   mark_page_dirty  set one dirty bit of a page
;   dirty_byte       the byte and the bit of a cell in a dirty map
;   draw_cell        draw one cell from the ring into a page
;   page_draw_dirty  draw the dirty cells of the window
;   page_repair      mark the cells under the page's old sprites dirty
;   repair_sprite    mark the cells under one sprite
;   repair_row       mark one or two cells of a tile row

        .include "video.inc"
        .include "ring.inc"
        .include "page.inc"

        .global page_states, page_init, page_scroll, page_repair, page_draw_dirty
        .global scroll_x, tile_left, first_row
        .equ WINDOW_LAST, VISIBLE_TILES - 1 ; tile_left + this: the last column of the window
; The scroll a page takes before it starts again at its base: the window's
; last group, and a sprite past it, must stay in the page. A sprite writes 3
; groups of each row from its first group (sprites.s), so one at the
; window's right edge reaches 2-3 groups past the window: SPRITE_REACH
; keeps a margin of 8.
        .equ SPRITE_REACH, 8            ; groups
        .equ ROOM_TILES, (SCROLL_ROOM - 2 * VISIBLE_TILES - SPRITE_REACH) / 2
        .equ CELL_ROW_GAP, PAGE_PITCH - 2 ; from the end of a cell row to the next row

        .section .vars.page,"aw",@nobits
page_states: .ds.b 2 * P_SIZE
scroll_x: .ds.b 2                       ; the world X of the picture's left edge: picture.s writes it from
                                        ; the packet; page.s, sprites.s and status.s read it
tile_left: .ds.b 2                      ; scroll_x / 8: the first column of the window (picture.s writes it)
first_row: .ds.b 1                      ; the first tile row that the pages draw: 4 under the status split,
                                        ; else 0 (picture.s writes it from PF_STATUS)
window_row: .ds.b 2                     ; page_draw_dirty: the row of window_masks for tile_left

        .section .rodata.page,"a",@progbits
; row_groups: TILE_PITCH x row for each tile row: the group of the row's
; first pixel row from P_ORIGIN.
row_groups:
        .set row, 0
        .rept TILE_ROWS
        .word row * TILE_PITCH
        .set row, row + 1
        .endr

; window_masks: for each ring column S of tile_left, the 8 bytes of a dirty
; map row with the bits of the window's ring columns S to S + WINDOW_LAST
; (mod 64). A comparison gives -1 for true: the negation makes it 1.
        .macro window_byte first, byte
        .set mask, 0
        .set bit, 0
        .rept 8
        .set mask, mask | ((-((((8 * \byte + bit - \first) & (RING_COLUMNS - 1))) <= WINDOW_LAST)) << bit)
        .set bit, bit + 1
        .endr
        .byte mask
        .endm
window_masks:
        .set first, 0
        .rept RING_COLUMNS
        .set byte, 0
        .rept DIRTY_ROW_BYTES
        window_byte first, byte
        .set byte, byte + 1
        .endr
        .set first, first + 1
        .endr

        .section .text.page,"ax",@progbits

; ---------------------------------------------------------------------------
; page_init: both pages hold no column, have no sprites, and take their
; bases and dirty maps.
;
; In:       nothing
; Out:      page_states: P_BASE, P_DIRTY, P_SPRITES set; P_COUNT 0; P_RIGHT
;           below P_LEFT (no column)
; Changes:  AF, DE, HL, IY
; Original: none
; ---------------------------------------------------------------------------
page_init:
        ld iy,page_states
        ld hl,sprite_records_0
        ld (iy+P_SPRITES),l
        ld (iy+P_SPRITES+1),h
        ld hl,page_0
        ld de,dirty_maps
        call 1f
        ld iy,page_states + P_SIZE
        ld hl,sprite_records_1
        ld (iy+P_SPRITES),l
        ld (iy+P_SPRITES+1),h
        ld hl,page_1
        ld de,dirty_maps + DIRTY_MAP_SIZE
1:      ld (iy+P_BASE),l
        ld (iy+P_BASE+1),h
        ld (iy+P_DIRTY),e
        ld (iy+P_DIRTY+1),d
        ld (iy+P_COUNT),0
        ld (iy+P_LEFT),1                ; P_RIGHT < P_LEFT: no column
        ld (iy+P_LEFT+1),0
        ld (iy+P_RIGHT),0
        ld (iy+P_RIGHT+1),0
        ret

; ---------------------------------------------------------------------------
; page_scroll: bring the page of IY to the window of tile_left. A page whose
; columns do not reach the window, or that has no room left for it, starts
; again at its base and draws the whole window.
;
; In:       IY   the page; tile_left, first_row
; Out:      the page holds columns tile_left to tile_left + WINDOW_LAST;
;           P_LEFT, P_RIGHT, and after a restart P_TBASE and P_ORIGIN
; Changes:  AF, BC, DE, HL, IX
; Time:     one column (26-30 cells of draw_cell) for each 8 pixels of
;           scroll; a restart draws 33 columns
; Original: none
; ---------------------------------------------------------------------------
page_scroll:
        ld l,(iy+P_RIGHT)
        ld h,(iy+P_RIGHT+1)
        ld e,(iy+P_LEFT)
        ld d,(iy+P_LEFT+1)
        or a
        sbc hl,de
        jr c,page_restart               ; the page holds no column
        ld hl,(tile_left)
        ld e,(iy+P_LEFT)
        ld d,(iy+P_LEFT+1)
        or a
        sbc hl,de
        jr c,page_restart               ; the window starts left of the page's columns
        ld hl,(tile_left)
        ld e,(iy+P_TBASE)
        ld d,(iy+P_TBASE+1)
        or a
        sbc hl,de
        ld de,ROOM_TILES
        or a
        sbc hl,de
        jr nc,page_restart              ; no room left in the page
; The first column to draw: P_RIGHT + 1, or tile_left when that is later.
        ld l,(iy+P_RIGHT)
        ld h,(iy+P_RIGHT+1)
        inc hl
        ld de,(tile_left)
        push hl
        or a
        sbc hl,de
        pop hl
        jr nc,page_columns              ; P_RIGHT + 1 >= tile_left
        ex de,hl                        ; HL = tile_left
        jr page_columns

; page_restart: the window starts at the page's base: P_TBASE = tile_left,
; P_ORIGIN = P_BASE - 2 x tile_left, then all the window's columns.
page_restart:
        ld hl,(tile_left)
        ld (iy+P_TBASE),l
        ld (iy+P_TBASE+1),h
        ld e,(iy+P_BASE)                ; P_ORIGIN = P_BASE - 2 x tile_left
        ld d,(iy+P_BASE+1)
        ex de,hl
        or a
        sbc hl,de
        or a
        sbc hl,de
        ld (iy+P_ORIGIN),l
        ld (iy+P_ORIGIN+1),h
        ld hl,(tile_left)

; page_columns: draw the columns from HL to tile_left + WINDOW_LAST, and set
; P_LEFT and P_RIGHT to the window. In: HL the first column; IY the page.
page_columns:
        push hl
        ld hl,(tile_left)
        ld (iy+P_LEFT),l
        ld (iy+P_LEFT+1),h
        ld de,WINDOW_LAST
        add hl,de
        ld (iy+P_RIGHT),l
        ld (iy+P_RIGHT+1),h
        pop de                          ; DE = the column to draw
1:      ld l,(iy+P_RIGHT)
        ld h,(iy+P_RIGHT+1)
        or a
        sbc hl,de
        ret c                           ; past the last column
        push de
        call draw_column
        pop de
        inc de
        jr 1b

; ---------------------------------------------------------------------------
; draw_column: draw rows first_row-29 of world tile column DE into the page
; of IY, and clear their dirty bits in that page.
;
; In:       DE   the world tile column; IY the page; first_row
; Out:      the column's cells in the page; their dirty bits clear
; Changes:  AF, BC, HL
; Keeps:    DE, IX, IY
; Time:     26-30 x (draw_cell + clear_dirty)
; Original: none
; ---------------------------------------------------------------------------
draw_column:
        ld a,(first_row)
        ld c,a
1:      push bc
        call draw_cell
        call clear_dirty
        pop bc
        inc c
        ld a,c
        cp TILE_ROWS
        jr c,1b
        ret

; clear_dirty: clear the dirty bit of row C, world tile column DE in the
; page of IY. Changes: AF, B, HL. Keeps: C, DE, IX, IY.
clear_dirty:
        call dirty_byte
        ld a,b
        cpl
        and (hl)
        ld (hl),a
        ret

; mark_page_dirty: set the dirty bit of row C, world tile column DE in the
; page of IY only. Changes: AF, B, HL. Keeps: C, DE, IX, IY.
mark_page_dirty:
        call dirty_byte
        ld a,b
        or (hl)
        ld (hl),a
        ret

; dirty_byte: HL = the byte and B = the bit of row C, world tile column DE
; in the dirty map of IY. The map has a bit for each ring column, the world
; column mod 64: DIRTY_ROW_BYTES bytes a row, bit q of byte b for ring
; column 8 b + q.
; Changes: AF, B, HL. Keeps: C, DE, IX, IY.
dirty_byte:
        push de
        ld a,e
        and 7
        ld e,a
        ld d,0
        ld hl,bit_of_column
        add hl,de
        ld b,(hl)                       ; B = the bit of the column in its byte
        pop de
        push de
        ld a,e
        and 0x38
        rrca
        rrca
        rrca
        ld e,a                          ; E = (column mod 64) / 8: the byte in the row
        ld d,0
        ld l,c
        ld h,DIRTY_ROW_BYTES
        mlt hl
        add hl,de
        ld e,(iy+P_DIRTY)
        ld d,(iy+P_DIRTY+1)
        add hl,de
        pop de
        ret

; ---------------------------------------------------------------------------
; draw_cell: draw the ring cell of row C, world tile column DE into the
; page of IY: 8 pixel rows of 2 groups, copied by the latches from the
; cell's tile and palette in the tile art. A latch copy moves the 4 planes
; of a group with one read and one write, so a cell is 16 reads and 16
; writes of video RAM.
;
; In:       C    the tile row; DE the world tile column; IY the page;
;           write mode 1 (GC_WRITE_LATCHES) to all planes; the Oak read and
;           write segments 0 (the tile art and the pages)
; Out:      the cell in the page
; Changes:  AF, HL, BBR (the art's window), CBR (the page's window)
; Keeps:    BC, DE, IX, IY
; Time:     about 800 clocks of instructions (368 of them the 8-row copy)
;           plus the waits of the 32 video RAM accesses (15-oak-drawing.md)
; Original: none
; ---------------------------------------------------------------------------
draw_cell:
        push bc
        push de
        push de                         ; a second copy: the column for the page address
; The tile and the palette of the cell (ring.s: ring_tiles starts a page).
        ld l,c
        ld h,RING_COLUMNS
        mlt hl                          ; 64 x row
        ld a,e
        and RING_COLUMNS - 1
        or l
        ld l,a
        ld a,h
        add a,ring_tiles >> 8
        ld h,a
        ld b,(hl)                       ; B = the tile
        add a,RING_STRIDE >> 8
        ld h,a
        ld a,(hl)                       ; A = the palette
; The art group: tile_art__group + 4096 x palette + 16 x tile.
        add a,a
        add a,a
        add a,a
        add a,a                         ; 16 x palette: the high byte of 4096 x palette
        ld l,b
        ld b,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl                       ; 16 x tile
        ld a,h
        add a,b
        ld h,a
        ld de,tile_art__group
        add hl,de
; The bank area shows the 8K-group window of the art.
        ld a,h
        rrca
        rrca
        rrca
        rrca
        and 0x0E
        add a,ART_BBR_BASE
        out0 (BBR),a
        ld a,h
        and 0x1F
        or ART_WINDOW >> 8
        ld h,a                          ; HL = the art in the bank area
        ex (sp),hl                      ; keep it; HL = the column
; The page group: P_ORIGIN + 2 x column + row_groups[row].
        ld e,(iy+P_ORIGIN)
        ld d,(iy+P_ORIGIN+1)
        add hl,hl
        add hl,de
        ex de,hl                        ; DE = P_ORIGIN + 2 x column
        ld l,c
        ld h,0
        add hl,hl
        ld bc,row_groups
        add hl,bc
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        add hl,de                       ; HL = the group of the cell
; Common area 1 shows 16K groups from the cell's 8K-group window.
        ld a,h
        rrca
        rrca
        rrca
        rrca
        and 0x0E
        add a,PAGE_CBR_BASE
        out0 (CBR),a
        ld a,h
        and 0x1F
        or PAGE_WINDOW >> 8
        ld d,a
        ld e,l                          ; DE = the cell in the page window
        pop hl                          ; HL = the art
; Eight pixel rows: two latch copies each, then the next row of the page.
        .rept 8
        ldi
        ldi
        ex de,hl
        ld bc,CELL_ROW_GAP
        add hl,bc
        ex de,hl
        .endr
        pop de
        pop bc
        ret

; ---------------------------------------------------------------------------
; page_draw_dirty: draw each dirty cell of the window, rows first_row-29,
; into the page of IY, and clear the page's dirty bits of those rows. A
; dirty cell outside the window needs no bit: page_scroll draws a column
; whole when it enters the window (window_masks).
;
; In:       IY   the page; tile_left, first_row
; Out:      the window's dirty cells drawn; the rows' dirty bits clear
; Changes:  AF, BC, DE, HL, IX, window_row
; Time:     each picture: about 57 clocks for each map byte with no dirty
;           cell (DIRTY_ROW_BYTES a row, 26-30 rows), plus a draw_cell for
;           each dirty cell of the window
; Original: none
; ---------------------------------------------------------------------------
page_draw_dirty:
        ld a,(tile_left)
        and RING_COLUMNS - 1
        ld l,a
        ld h,DIRTY_ROW_BYTES
        mlt hl
        ld de,window_masks
        add hl,de
        ld (window_row),hl              ; the window's bits of a map row
        ld a,(first_row)
        ld c,a
dirty_row:
        ld l,c
        ld h,DIRTY_ROW_BYTES
        mlt hl
        ld e,(iy+P_DIRTY)
        ld d,(iy+P_DIRTY+1)
        add hl,de                       ; HL = the row's first byte
        ld ix,(window_row)
        ld b,0                          ; B = the first ring column of the byte
dirty_byte_loop:
        ld a,(hl)
        or a
        jr z,dirty_next_byte
        ld (hl),0                       ; drawn now, or outside the window
        and (ix+0)
        jr z,dirty_next_byte
        push hl
        push bc
        ld e,a                          ; E = the bits not yet seen
        ld d,b                          ; D = the ring column of bit 0 of E
dirty_bit:
        srl e
        jr nc,dirty_next_bit
; The window holds ring column D as world column tile_left + d, where
; d = (D - tile_left) mod 64.
        push de
        ld a,(tile_left)
        ld b,a
        ld a,d
        sub b
        and RING_COLUMNS - 1
        ld e,a
        ld d,0
        ld hl,(tile_left)
        add hl,de
        ex de,hl                        ; DE = the world tile column
        call draw_cell
        pop de
dirty_next_bit:
        inc d
        ld a,e
        or a
        jr nz,dirty_bit
        pop bc
        pop hl
dirty_next_byte:
        inc hl
        inc ix
        ld a,b
        add a,8
        ld b,a
        cp RING_COLUMNS
        jr c,dirty_byte_loop
        inc c
        ld a,c
        cp TILE_ROWS
        jr c,dirty_row
        ret

; ---------------------------------------------------------------------------
; page_repair: mark dirty, in the page of IY only, the cells under each
; sprite that the page drew on its last picture (P_COUNT records at
; P_SPRITES, written by sprites.s); page_draw_dirty then puts the
; background back. The records are then used up.
;
; In:       IY   the page
; Out:      the dirty bits of those cells; P_COUNT 0
; Changes:  AF, BC, DE, HL
; Time:     each picture: one repair_sprite for each sprite record
; Original: none
; ---------------------------------------------------------------------------
page_repair:
        ld a,(iy+P_COUNT)
        or a
        ret z
        ld (iy+P_COUNT),0
        ld b,a
        ld l,(iy+P_SPRITES)
        ld h,(iy+P_SPRITES+1)
1:      push bc
        ld e,(hl)                       ; DE = the sprite's world X
        inc hl
        ld d,(hl)
        inc hl
        ld a,(hl)                       ; A = its top pixel row
        inc hl
        push hl
        call repair_sprite
        pop hl
        pop bc
        djnz 1b
        ret

; repair_sprite: mark the cells under an 8 x 8 sprite at world X DE, pixel
; row A: tile columns X / 8 and (X + 7) / 8, tile rows A / 8 and (A + 7) / 8
; (below TILE_ROWS and from first_row on). In: IY the page.
; Changes: AF, BC, DE, HL
repair_sprite:
        ld c,a
        ld hl,7
        add hl,de
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l                            ; HL = (X + 7) / 8
        srl d
        rr e
        srl d
        rr e
        srl d
        rr e                            ; DE = X / 8
        ld a,c
        add a,7
        rrca
        rrca
        rrca
        and 0x1F
        ld b,a                          ; B = (A + 7) / 8
        ld a,c
        rrca
        rrca
        rrca
        and 0x1F
        ld c,a                          ; C = A / 8
        push hl
        push bc
        call repair_row
        pop bc
        pop hl
        ld a,b
        cp c
        ret z                           ; one tile row
        ld c,b
; Falls into repair_row for the second tile row.

; repair_row: mark row C at column DE, and at column HL (DE + 1) when it
; differs; a row past TILE_ROWS or above first_row is not marked.
; In: IY the page. Changes: AF, B, HL. Keeps: C, DE.
repair_row:
        ld a,c
        cp TILE_ROWS
        ret nc
        ld a,(first_row)
        ld b,a
        ld a,c
        cp b
        ret c                           ; a status row while the split is on
        push hl
        call mark_page_dirty
        pop hl
        or a
        sbc hl,de
        ret z
        inc de
        call mark_page_dirty
        dec de
        ret
