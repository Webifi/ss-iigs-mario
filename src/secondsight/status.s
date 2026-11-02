; The status bar: name-table rows 0-3 of name table 0, which the original
; keeps in place while the rest of the picture scrolls (it sets the scroll
; only after sprite 0, $8082-$80D1).
;
; The card cannot split the picture at the top (the split of the Oak keeps
; its fixed part at the bottom), so it keeps four copies of the 32 status
; rows in video RAM (status_copies), copy p shifted right by p pixels. On
; each picture under the split, one DMA copies the copy that matches the pan
; into the page at the start address; the pan then moves it back by p
; pixels, so the status bar shows in place.
;
; A copy has the page's pitch (PAGE_PITCH groups a row), so the whole band
; is one run of STATUS_GROUPS groups in both.
;
; Routines:
;   status_cell       draw one status cell into the four copies
;   status_copy_cell  draw the cell's pixels into one copy
;   status_column     write one pixel column of the cell into one copy
;   status_redraw     draw all 128 status cells (the start)
;   status_band       copy the band into the page of IY

        .include "video.inc"
        .include "ring.inc"
        .include "page.inc"

        .global status_cell, status_redraw, status_band

        .equ STATUS_COLUMNS, 32         ; name table 0: ring columns 0-31
        .equ STATUS_COPIES, GROUP_PIXELS ; one copy for each pan of 0-3 pixels
        .equ CELL_PIXELS, 8             ; the pixels of a cell row
        .equ STATUS_CELLS, STATUS_TILE_ROWS * STATUS_COLUMNS
        .equ NO_PALETTE, 0xFF           ; status_drawn: no cell has this palette (0-3)

        .section .vars.status,"aw",@nobits
status_copy: .ds.b 1                    ; the copy being drawn, 0 to STATUS_COPIES - 1
status_x0: .ds.b 1                      ; the cell's first pixel in the copy row: 8 x column + copy
status_plane: .ds.b 1
status_base: .ds.b 2                    ; the cell's first row in the copy, in the page window
status_drawn: .ds.b 2 * STATUS_CELLS    ; the tile, then (STATUS_CELLS later) the palette, that each cell's copies hold

        .section .text.status,"ax",@progbits

; ---------------------------------------------------------------------------
; status_cell: draw the cell at row D (0-3), ring column E (0-31) into the
; four copies, from its tile and palette in the ring, when they differ from
; what the copies hold (status_drawn): a level start writes most status
; cells again with what they had. ring.s calls it for each changed status
; cell of a packet (status_dirty).
;
; In:       D    the status row, 0-3; E the ring column, 0-31
; Out:      the cell in the four copies; status_drawn; write mode 1 to all
;           planes and the Oak write segment 0 again
; Changes:  AF, HL, IX; BBR, CBR
; Keeps:    BC, DE
; Time:     about 17,000 clocks to draw; about 200 when the cell is the same
; Original: none
; ---------------------------------------------------------------------------
status_cell:
        push bc
        push de
        call cell_address               ; ring.s: HL = the tile byte
        ld b,(hl)                       ; B = the tile
        ld a,h
        add a,RING_STRIDE >> 8
        ld h,a
        ld c,(hl)                       ; C = the palette
; The cell's entry: row x 32 + column (rows 0-3 lose no bit in the rotates).
        ld a,d
        rrca
        rrca
        rrca
        or e
        ld l,a
        ld h,0
        ld de,status_drawn
        add hl,de                       ; HL = the tile that the copies hold
        ld a,b
        cp (hl)
        ld (hl),a
        ld de,STATUS_CELLS
        add hl,de                       ; its palette (ADD HL keeps Z)
        jr nz,1f
        ld a,c
        cp (hl)
        jp z,status_cell_done           ; the copies hold this tile and palette
1:      ld (hl),c
        ld a,c
        add a,a
        add a,a
        ld d,a                          ; D = 4 x palette: the background pixel values
        ld e,0                          ; no flip
        ld a,b
        ld hl,chr_bg__bbr
        call expand_tile                ; sprites.s: pixels
        pop de
        push de
; The copies are in segment 1 from group 0, inside one 16K window.
        oak_set OAK_WRITE_SEGMENT, status_copies__segment
        ld a,PAGE_CBR_BASE
        out0 (CBR),a
        gc_set GC_MODE, GC_WRITE_CPU     ; write mode 0
        xor a
        ld (status_copy),a
1:      call status_copy_cell
        ld hl,status_copy
        inc (hl)
        ld a,(hl)
        cp STATUS_COPIES
        jr c,1b
        gc_set GC_MODE, GC_WRITE_LATCHES ; write mode 1 again
        seq_set SEQ_MAP_MASK, ALL_PLANES
        oak_set OAK_WRITE_SEGMENT, 0    ; the pages again
status_cell_done:
        pop de
        pop bc
        ret

; status_copy_cell: the pixels into copy status_copy, cell row D, column E.
; Pixel x of a row goes to pixel x0 + x of the copy row (x0 = 8 E + copy):
; group (x0 + x) / 4, plane (x0 + x) mod 4. Plane by plane: the two pixel
; columns of the cell that each plane holds.
; In: D the row, E the column; pixels (expand_tile); write mode 0.
; Out: the copy's cell. Changes: AF, BC, HL. Keeps: DE.
status_copy_cell:
        push de
; status_base: copy x STATUS_GROUPS + row x TILE_PITCH, in the page window.
        ld a,(status_copy)
        ld hl,0
        ld bc,STATUS_GROUPS
        or a
        jr z,2f
1:      add hl,bc
        dec a
        jr nz,1b
2:      ld a,d
        ld bc,TILE_PITCH
        or a
        jr z,4f
3:      add hl,bc
        dec a
        jr nz,3b
4:      ld a,h
        or PAGE_WINDOW >> 8
        ld h,a
        ld (status_base),hl
        ld a,e
        add a,a
        add a,a
        add a,a
        ld hl,status_copy
        add a,(hl)
        ld (status_x0),a                ; at most 8 x 31 + 3 = 251
        xor a
        ld (status_plane),a
5:      ld e,a
        ld d,0
        ld hl,bit_of_column             ; ring.s: 1, 2, 4, 8
        add hl,de
        ld bc,VGA_SEQ_INDEX
        ld a,SEQ_MAP_MASK
        out (c),a
        inc c
        ld a,(hl)
        out (c),a                       ; the map mask: this plane
; The cell's first pixel column in this plane: x = (plane - x0) mod 4; then
; x + 4, the next pixel of the same plane.
        ld a,(status_x0)
        ld b,a
        ld a,(status_plane)
        sub b
        and GROUP_PIXELS - 1
6:      push af
        call status_column
        pop af
        add a,GROUP_PIXELS
        cp CELL_PIXELS
        jr c,6b
        ld hl,status_plane
        inc (hl)
        ld a,(hl)
        cp VGA_PLANES
        jr c,5b
        pop de
        ret

; status_column: write pixel column A (0-7) of the cell, 8 rows, into the
; plane of the map mask: group (x0 + A) / 4 of each row of the copy.
; Changes: AF, BC, DE, HL
status_column:
        ld c,a                          ; C = the column
        ld a,(status_x0)
        add a,c                         ; x0 + A: up to 258, with the carry
        rra
        srl a                           ; the group: (x0 + A) / 4
        ld hl,(status_base)
        add a,l
        ld l,a
        jr nc,1f
        inc h
1:      ex de,hl                        ; DE = the group in row 0 of the cell
        ld a,c
        add a,pixels & 0xFF
        ld l,a
        ld h,pixels >> 8                ; HL = pixels[A] (pixels does not cross a page)
        ld bc,PAGE_PITCH
        .rept 8
        ld a,(hl)
        ld (de),a
        ld a,l
        add a,8
        ld l,a                          ; the next row of the cell
        ex de,hl
        add hl,bc                       ; the next row of the copy
        ex de,hl
        .endr
        ret

; ---------------------------------------------------------------------------
; status_redraw: draw every status cell into the copies (the start: the
; ring's cells then match the copies).
;
; In:       the ring's status cells
; Out:      the four copies; status_drawn
; Changes:  AF, BC, DE, HL, IX
; Time:     once at the start: 128 x status_cell, about 2.2 million clocks
; Original: none
; ---------------------------------------------------------------------------
status_redraw:
        ld hl,status_drawn + STATUS_CELLS
        ld b,STATUS_CELLS
3:      ld (hl),NO_PALETTE              ; every cell differs from what the copies hold
        inc hl
        djnz 3b
        ld d,0
1:      ld e,0
2:      call status_cell
        inc e
        ld a,e
        cp STATUS_COLUMNS
        jr c,2b
        inc d
        ld a,d
        cp STATUS_TILE_ROWS
        jr c,1b
        ret

; ---------------------------------------------------------------------------
; status_band: one DMA copies the copy of the picture's pan into the 32
; status rows of the page of IY at its start address. Write mode 1 must be
; on with all planes: each byte of the DMA is a four-pixel latch copy.
;
; In:       IY   the page; scroll_x
; Out:      the status rows of the page
; Changes:  AF, BC, DE, HL; the Oak read segment (current_segment)
; Time:     each picture under the split: STATUS_GROUPS x 14 clocks, about
;           32,000
; Original: none
; ---------------------------------------------------------------------------
status_band:
; The source: copy (scroll_x mod 4), in segment 1 from group 0.
        ld a,(scroll_x)
        and GROUP_PIXELS - 1
        ld hl,0
        ld bc,STATUS_GROUPS
        or a
        jr z,2f
1:      add hl,bc
        dec a
        jr nz,1b
2:      ld a,l
        out0 (SAR0L),a
        ld a,h
        out0 (SAR0H),a
        ld a,VGA_WINDOW >> 16
        out0 (SAR0B),a
; The destination: the start address, P_ORIGIN + scroll_x / 4.
        ld hl,(scroll_x)
        srl h
        rr l
        srl h
        rr l
        ld e,(iy+P_ORIGIN)
        ld d,(iy+P_ORIGIN+1)
        add hl,de
        ld a,l
        out0 (DAR0L),a
        ld a,h
        out0 (DAR0H),a
        ld a,VGA_WINDOW >> 16
        out0 (DAR0B),a
        ld a,STATUS_GROUPS & 0xFF
        out0 (BCR0L),a
        ld a,STATUS_GROUPS >> 8
        out0 (BCR0H),a
        oak_set OAK_READ_SEGMENT, status_copies__segment
        ld a,status_copies__segment
        ld (current_segment),a          ; sprites.s: the read segment now set
        ld a,DMODE_BURST                ; memory to memory, both addresses rising, burst
        out0 (DMODE),a
        ld a,DSTAT_DE0 | DSTAT_KEEP1 | DSTAT_DME ; start channel 0; channel 1 keeps its state
        out0 (DSTAT),a                  ; the CPU waits until the burst ends
        ret
