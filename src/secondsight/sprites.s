; The sprites: the art cache and the drawing of each picture's sprite list.
;
; The art. A sprite tile appears in a horizontal flip; that is its key
; (tile + 256 x flip, SPRITE_KEYS keys). At the start, render_key draws each
; key's 8 x 8 pixels from the tile's two bit planes (chr_sprites, SRAM bank
; 1) into its slot of video RAM, at the four pixel alignments, in palette 0:
; SPRITE_SLOT_BASE + pen. A sprite of palette p is then, for each group, a
; read of the slot's group into the latches and a write of 4 p in write
; mode 0 with the function OR: each plane stores its latch OR 4 p, the pixel
; value SPRITE_SLOT_BASE + 4 p + pen. So no sprite waits for its art, and one
; slot serves the four palettes. A vertical flip reads the slot's rows in
; reverse.
;
; Transparency: the map mask lets a write change only the opaque pixels of
; a group. The mask of a row comes from tables: the opacity byte
; of the tile row (sprite_opacity: bit 7 = the left pixel), flipped by
; bit_reverse for a flipped key, then mask_tables by alignment and group.
;
; A sprite with the behind bit (attribute bit 5) shows only where the
; background has pen 0: its masks lose the opaque pixels of the cells under
; it (bg_opacity, through the same tables at alignment 0).
;
; Draw order: the original shows a lower sprite entry over a higher one, so
; the list is drawn from its last entry to its first. Every sprite is drawn
; on every picture (no limit of 8 on a line, so no flicker), and each page
; records what it drew for page_repair.
;
; key_slots, for each key: byte 0 = the slot's index in its window, byte 1
; = the window.
;
; Routines:
;   sprites_init    the window table, and every key's art
;   sprites_draw    draw the packet's sprite list into the page of IY
;   sprite_one      draw one entry of the list
;   rows_plain, rows_flip_x, rows_flip_y, rows_flip_xy
;                   the rows of a sprite in front of the background
;   sprite_behind   the rows of a sprite behind the background
;   behind_masks    remove the pixels over opaque background from a row
;   render_key      give a key a slot and draw its art there
;   write_slot      write the pixels into a slot at the four alignments
;   expand_tile     the 64 pixel values of a tile (also status.s)

        .include "video.inc"
        .include "ring.inc"
        .include "page.inc"
        .include "packet_layout.inc"

        .global sprites_init, sprites_draw, sprite_records_0, sprite_records_1
        .global expand_tile, pixels, current_segment

        .equ SLOT_WINDOWS, SPRITE_SLOTS / SLOTS_PER_WINDOW
        .equ SPRITE_SLOT_BASE, 16       ; pixel value of sprite palette 0 pen 0
        .if (SPRITE_SLOT_BASE & 0x0F) != 0
        .error "the OR of 4 x palette needs pixel bits 0-3 of the slots free of the base"
        .endif

        .section .vars.sprites,"aw",@nobits
key_slots: .ds.b 2 * SPRITE_KEYS
window_table: .ds.b 2 * SLOT_WINDOWS   ; for each window: the Oak segment, the BBR value
next_index: .ds.b 1                     ; the next free slot: its index in the window
next_window: .ds.b 1                    ; and its window
sprite_records_0: .ds.b SPRITE_RECORD * SPRITE_LIMIT
sprite_records_1: .ds.b SPRITE_RECORD * SPRITE_LIMIT
; The sprite being drawn.
sprite_x: .ds.b 2                       ; world X
sprite_y: .ds.b 1                       ; the top pixel row
sprite_attr: .ds.b 1
sprite_pal: .ds.b 1                     ; 4 x the palette: ORed into the slot's pixels
sprite_rows: .ds.b 1                    ; the rows to draw (fewer at the bottom edge)
sprite_opacity_row: .ds.b 2             ; sprite_opacity + 8 x tile
sprite_art: .ds.b 2                     ; the slot at its alignment, in the bank area
sprite_align: .ds.b 1                   ; X mod 4
sprite_masks: .ds.b 3                   ; the map masks of the three groups of a row
sprite_dest: .ds.b 2                    ; the page window address of the row
sprite_row_i: .ds.b 1                   ; the row being drawn, 0-7
behind_row: .ds.b 1                     ; behind_masks: the tile row
current_segment: .ds.b 1                ; the Oak read segment now set
; render_key, expand_tile, write_slot (and status.s through expand_tile):
        .balign 64
pixels: .ds.b 64                        ; the 8 x 8 pixel values: a row steps 8 with no carry out of the low byte
render_slot: .ds.b 2                    ; the slot in the page window
render_dest: .ds.b 2                    ; write_slot: the slot's groups of the alignment
render_plane: .ds.b 1
render_align: .ds.b 1
render_group: .ds.b 1

        .section .rodata.sprites,"a",@progbits
; slot_offsets: the first group of each slot in its window.
slot_offsets:
        .set k, 0
        .rept SLOTS_PER_WINDOW
        .word k * SLOT_GROUPS
        .set k, k + 1
        .endr

        .section .text.sprites,"ax",@progbits

; sprites_init: no key has a slot, the first slot is free, and the window
; table holds the Oak segment and BBR value of each 8K-group window of the
; slots (sprite_slots__page: the slots' first group / 256, secondsight.ld).
; Changes: AF, BC, DE, HL
sprites_init:
        ld hl,sprite_slots__page        ; the window's first group / 256
        ld de,window_table
        ld b,SLOT_WINDOWS
1:      ld a,h
        ld (de),a                       ; the segment: group bits 16-17
        inc de
        ld a,l
        rrca
        rrca
        rrca
        rrca
        and 0x0E
        add a,ART_BBR_BASE
        ld (de),a                       ; the BBR value of the window in the bank area
        inc de
        push de
        ld de,WINDOW_GROUPS / 256
        add hl,de
        pop de
        djnz 1b
        ld a,0xFF
        ld (current_segment),a
; Every key's art, slot after slot in key order.
        xor a
        ld (next_index),a
        ld (next_window),a
        ld hl,key_slots
        ld de,0                         ; the key: D = the flip, E = the tile
1:      push de
        push hl
        ld a,e
        ld e,d                          ; nonzero: the flip
        call render_key
        pop hl
        inc hl
        inc hl
        pop de
        inc de
        ld a,d
        cp SPRITE_KEYS >> 8
        jr c,1b
        ret
        .if SPRITE_KEYS != 2 * 256
        .error "sprites_init counts the keys as tile + 256 x flip"
        .endif

; ---------------------------------------------------------------------------
; sprites_draw: draw the sprite list of the packet into the page of IY.
;
; In:       IX   the first sprite entry; B the entries (1-64); IY the page
; Out:      the page's sprite records (P_SPRITES, P_COUNT); write mode 1 and
;           the function "the byte itself" again
; Changes:  AF, BC, DE, HL, IX, BC', DE', HL'; BBR, CBR; the Oak read
;           segment (current_segment)
; Time:     each picture: about 3,000 clocks for an 8-row sprite (about 900
;           of setup in sprite_one, about 270 for each row), plus the video
;           RAM waits; a sprite behind the background takes behind_masks for
;           each row too
; Original: none
; ---------------------------------------------------------------------------
sprites_draw:
        push bc
        gc_set GC_MODE, GC_WRITE_CPU     ; write mode 0: the CPU byte through the function
        gc_set GC_DATA_ROTATE, GC_FUNCTION_OR
        pop bc
; The last entry first: IX = the last entry.
        ld a,b
        dec a
        add a,a
        add a,a
        ld e,a
        ld d,0
        add ix,de
        ld l,(iy+P_SPRITES)
        ld h,(iy+P_SPRITES+1)
1:      push bc
        push hl
        call sprite_one
        pop hl
        jr nc,2f                        ; not drawn: no record
; The record: world X, Y.
        ld a,(sprite_x)
        ld (hl),a
        inc hl
        ld a,(sprite_x+1)
        ld (hl),a
        inc hl
        ld a,(sprite_y)
        ld (hl),a
        inc hl
        inc (iy+P_COUNT)
2:      ld de,-SPRITE_ENTRY
        add ix,de
        pop bc
        djnz 1b
        gc_set GC_DATA_ROTATE, 0        ; the function: the byte itself
        gc_set GC_MODE, GC_WRITE_LATCHES ; write mode 1: latch copies again
        ret

; sprite_one: draw the entry at IX into the page of IY.
; In:       IX   the entry; IY the page
; Out:      carry set when it drew (the sprite is on the picture); sprite_x,
;           sprite_y for the page's record
; Changes:  AF, BC, DE, HL, BC', DE', HL'; BBR, CBR; current_segment
sprite_one:
        ld a,(ix+SPRITE_Y)
        cp SCREEN_ROWS - 1
        ret nc                          ; below the picture (the original hides sprites at Y $F8): carry clear
        inc a                           ; the top row: the original draws at Y + 1
        ld (sprite_y),a
        ld b,a
        ld a,SCREEN_ROWS
        sub b
        cp 8
        jr c,1f
        ld a,8
1:      ld (sprite_rows),a
        ld a,(ix+SPRITE_ATTR)
        ld (sprite_attr),a
        ld a,(ix+SPRITE_X)
        ld e,a
        ld d,0
        ld hl,(scroll_x)
        add hl,de
        ld (sprite_x),hl
        ld a,l
        and 3
        ld (sprite_align),a
; The palette, ORed into the art.
        ld a,(ix+SPRITE_ATTR)
        and 3
        add a,a
        add a,a
        ld (sprite_pal),a
; The key: tile + 256 x flip; HL = its key_slots entry.
        ld h,0
        ld a,(ix+SPRITE_ATTR)
        and ATTR_FLIP_X
        jr z,2f
        inc h
2:      ld l,(ix+SPRITE_TILE)
        add hl,hl
        ld de,key_slots
        add hl,de
        ld a,(hl)                       ; the index
        inc hl
        ld e,(hl)                       ; the window
; The slot: window E, index A.
        add a,a
        ld l,a
        ld h,0
        ld bc,slot_offsets
        add hl,bc
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a                          ; HL = the slot's first group in its window
        ld a,(sprite_align)
        ld b,a
        ld c,SLOT_ALIGN_GROUPS
        mlt bc                          ; 24 x alignment
        add hl,bc
        ld a,h
        or ART_WINDOW >> 8
        ld h,a
        ld (sprite_art),hl
        ld d,0
        ld hl,window_table
        add hl,de
        add hl,de
        ld a,(hl)                       ; the segment of the window
        inc hl
        ld e,(hl)                       ; its BBR value
        ld hl,current_segment
        cp (hl)
        jr z,3f
        ld (hl),a
        ld d,a
        ld bc,OAK_INDEX
        ld a,OAK_READ_SEGMENT
        out (c),a
        inc c
        out (c),d
3:      ld a,e
        out0 (BBR),a
; The opacity row of the tile.
        ld l,(ix+SPRITE_TILE)
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld de,sprite_opacity
        add hl,de
        ld (sprite_opacity_row),hl
; The page: P_ORIGIN + X / 4 + PAGE_PITCH x Y, in common area 1.
        ld hl,(sprite_x)
        srl h
        rr l
        srl h
        rr l
        ld e,(iy+P_ORIGIN)
        ld d,(iy+P_ORIGIN+1)
        add hl,de
        ex de,hl
        ld a,(sprite_y)
        ld l,a
        ld h,PAGE_PITCH
        mlt hl
        add hl,de                       ; HL = the sprite's first group
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
        ld e,l                          ; DE = the first group in the page window
; The rows: a sprite behind the background takes sprite_row (behind_masks);
; every other sprite takes the loop of its flips.
        ld a,(sprite_attr)
        bit ATTR_BEHIND_BIT,a
        jp nz,sprite_behind
        and ATTR_FLIP_X | ATTR_FLIP_Y
        jp z,rows_plain
        cp ATTR_FLIP_X
        jp z,rows_flip_x
        cp ATTR_FLIP_Y
        jp z,rows_flip_y
        jp rows_flip_xy

; sprite_rows flip_x, flip_y: the rows of a sprite in front of the
; background. The second register set keeps the mask work: HL' the row's
; opacity, C' the page of group 0's masks (mask_tables + 256 x alignment),
; D' a group's page, E' the opacity (with a flip in x: bit_reverse of it),
; B' the rows left. The first set draws: HL the art row, IY the row's first
; group in the page window, BC the sequencer data port, D 4 x the palette.
; In:       DE   the sprite's first group in the page window
; Out:      carry set (drawn)
; Changes:  AF, BC, DE, HL, BC', DE', HL'
        .macro sprite_rows flip_x, flip_y
        push iy
        push de
        pop iy
        ld a,(sprite_pal)
        ld d,a
        ld hl,(sprite_art)
        .if \flip_y
        ld bc,SLOT_ROW_GROUPS * 7
        add hl,bc                       ; a flip in y reads the rows from the last
        .endif
        exx
        ld hl,(sprite_opacity_row)
        .if \flip_y
        ld bc,7
        add hl,bc
        .endif
        ld a,(sprite_align)
        add a,mask_tables >> 8
        ld c,a
        ld a,(sprite_rows)
        ld b,a
        exx
        ld bc,VGA_SEQ_DATA              ; the sequencer index stays at the map mask
        exx
1:      ld d,c
        ld a,(hl)                       ; the opacity of the row
        .if \flip_y
        dec hl
        .else
        inc hl
        .endif
        .if \flip_x
        ld e,a
        ld d,bit_reverse >> 8
        ld a,(de)
        ld d,c
        .endif
        ld e,a
        ld a,(de)                       ; group 0's mask
        exx
        or a
        jr z,2f
        out (c),a                       ; the mask
        cp (hl)                         ; the art's group into the latches (A stays)
        ld a,d
        ld (iy+0),a                     ; 4 x palette, ORed into each latch
2:      inc hl
        exx
        ld a,d
        add a,4
        ld d,a
        ld a,(de)                       ; group 1's
        exx
        or a
        jr z,3f
        out (c),a
        cp (hl)
        ld a,d
        ld (iy+1),a
3:      inc hl
        exx
        ld a,d
        add a,4
        ld d,a
        ld a,(de)                       ; group 2's
        exx
        or a
        jr z,4f
        out (c),a
        cp (hl)
        ld a,d
        ld (iy+2),a
4:      inc hl
        .if \flip_y
        ld bc,-2 * SLOT_ROW_GROUPS
        add hl,bc                       ; the row before: back over this row and one more
        .endif
        ld bc,PAGE_PITCH
        add iy,bc                       ; the next pixel row of the page
        ld bc,VGA_SEQ_DATA
        exx
        djnz 1b
        exx
        pop iy
        scf                             ; drawn
        ret
        .endm

rows_plain:
        sprite_rows 0, 0
rows_flip_x:
        sprite_rows 1, 0
rows_flip_y:
        sprite_rows 0, 1
rows_flip_xy:
        sprite_rows 1, 1

; sprite_behind: the rows of a sprite behind the background, one row at a
; time: the masks of each row lose the pixels over opaque background
; (behind_masks). sprite_one comes here only for an entry with ATTR_BEHIND.
; In:       DE   the sprite's first group in the page window
; Out:      carry set (drawn)
; Changes:  AF, BC, DE, HL
sprite_behind:
        ld (sprite_dest),de
        xor a
        ld (sprite_row_i),a
sprite_row:
        ld a,(sprite_row_i)
        ld c,a
        ld a,(sprite_attr)
        and ATTR_FLIP_Y
        ld a,c
        jr z,1f
        ld a,7
        sub c                           ; a vertical flip reads the rows in reverse
1:      ld c,a                          ; C = the art row
; The row's opacity (bit 7 = its left pixel); a flipped key's art is
; flipped, so its opacity is too. sprite_opacity is 8-aligned: the row
; index adds without a carry.
        ld hl,(sprite_opacity_row)
        ld a,l
        or c
        ld l,a
        ld a,(hl)
        ld b,a
        ld a,(sprite_attr)
        and ATTR_FLIP_X
        ld a,b
        jr z,2f
        ld h,bit_reverse >> 8
        ld l,a
        ld a,(hl)
; The map masks of the three groups: mask_tables + 1024 x group +
; 256 x alignment + opacity.
2:      ld l,a
        ld a,(sprite_align)
        add a,mask_tables >> 8
        ld h,a
        ld a,(hl)
        ld (sprite_masks),a
        ld a,h
        add a,4
        ld h,a
        ld a,(hl)
        ld (sprite_masks+1),a
        ld a,h
        add a,4
        ld h,a
        ld a,(hl)
        ld (sprite_masks+2),a
        call behind_masks
; The art row: sprite_art + 3 x the art row. A slot never crosses its
; window, so the high byte only takes the carry.
        ld a,c
        add a,a
        add a,c
        ld hl,(sprite_art)
        add a,l
        ld l,a
        jr nc,3f
        inc h
3:      ld de,(sprite_dest)
        ld bc,VGA_SEQ_DATA              ; the sequencer index stays at the map mask
; Each group with opaque pixels: its map mask, then a latch copy (the read
; loads the four planes, the write stores the masked ones).
        .irp group,0,1,2
        ld a,(sprite_masks+\group)
        or a
        jr z,4f
        out (c),a
        cp (hl)                         ; the art's group into the latches
        ld a,(sprite_pal)
        ld (de),a                       ; 4 x palette, ORed into each latch
4:      inc hl
        inc de
        .endr
        ld hl,(sprite_dest)
        ld de,PAGE_PITCH
        add hl,de
        ld (sprite_dest),hl
        ld hl,sprite_row_i
        inc (hl)
        ld a,(hl)
        ld hl,sprite_rows
        cp (hl)
        jp c,sprite_row
        scf                             ; drawn
        ret

; behind_masks: clear, in sprite_masks, the pixels whose background cell has
; an opaque pixel (pen 1-3) there: a sprite with the behind bit shows only
; over pen 0.
; In:       sprite_row_i, sprite_y, sprite_x
; Changes:  AF, DE, HL. Keeps: BC.
behind_masks:
        push bc
        ld a,(sprite_row_i)
        ld b,a
        ld a,(sprite_y)
        add a,b                         ; the pixel row
        ld b,a
        and 7
        ld c,a                          ; C = the row in its tile
        ld a,b
        rrca
        rrca
        rrca
        and 0x1F
        ld (behind_row),a               ; the tile row
        ld hl,(sprite_x)
        srl h
        rr l
        srl h
        rr l                            ; HL = the world group of the first group
        ld de,sprite_masks
        ld b,3
1:      push bc
        push de
        push hl
; The cell under the group: ring column (group / 2) mod 64.
        ld a,l
        rrca
        and RING_COLUMNS - 1
        ld e,a
        ld a,(behind_row)
        ld d,a
        call cell_address               ; ring.s: HL = the tile byte
        ld l,(hl)
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,l
        or c                            ; bg_opacity is 8-aligned
        ld l,a
        ld de,bg_opacity
        add hl,de
        ld e,(hl)                       ; E = the opacity of the cell row
        pop hl
        push hl
        ld a,l
        and 1                           ; the group's half of the cell
        add a,a
        add a,a
        add a,mask_tables >> 8          ; alignment 0, group 0 or 1: pixels 0-3 or 4-7
        ld h,a
        ld l,e
        ld a,(hl)
        cpl                             ; the group's pixels over pen 0
        pop hl
        pop de
        ld b,a                          ; B: the loop count is on the stack
        ld a,(de)
        and b
        ld (de),a
        inc de
        inc hl
        pop bc
        djnz 1b
        pop bc
        ret

; render_key: give a key the next slot, and draw its art there: the tile
; in palette 0 and its flip, at the four alignments.
; In:       HL   the key's key_slots entry; A the tile; E nonzero: flipped
; Out:      the entry: the slot's index in its window, the window
; Changes:  AF, BC, DE, HL; BBR (the bank area); write mode 1 and all planes again
; Time:     about 20,000 clocks
render_key:
        push af
        ld a,(next_index)
        ld c,a
        ld a,(next_window)
        ld b,a
        ld (hl),c                       ; the entry: index, window
        inc hl
        ld (hl),a
        ld a,c                          ; the next free slot
        inc a
        cp SLOTS_PER_WINDOW
        jr c,1f
        ld hl,next_window
        inc (hl)
        xor a
1:      ld (next_index),a
        pop af
        push bc                         ; B = the window, C = the index
; The tile's pixels in palette 0: SPRITE_SLOT_BASE + pen; pen 0 is 0.
        ld d,SPRITE_SLOT_BASE
        ld hl,chr_sprites__bbr
        call expand_tile
; The slot in common area 1, in the window's segment for writes.
        pop bc
        push bc
        ld e,b
        ld d,0
        ld hl,window_table
        add hl,de
        add hl,de
        ld a,(hl)                       ; the segment
        ld d,a
        inc hl
        ld a,(hl)                       ; the BBR value of the window
        sub ART_BBR_BASE
        add a,PAGE_CBR_BASE
        out0 (CBR),a
        ld bc,OAK_INDEX
        ld a,OAK_WRITE_SEGMENT
        out (c),a
        inc c
        out (c),d
        pop bc
        push bc
        ld a,c
        add a,a
        ld l,a
        ld h,0
        ld de,slot_offsets
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        or PAGE_WINDOW & 0xFF
        ld l,a
        ld a,h
        or PAGE_WINDOW >> 8
        ld h,a
        ld (render_slot),hl
        call write_slot
        oak_set OAK_WRITE_SEGMENT, 0    ; the pages again
        pop bc
        ret

; write_slot: write the pixels into the slot at render_slot in write mode 0,
; one plane at a time. Plane q of group g at alignment a shows pixel
; x = 4 g + q - a; only the pixels 0-7 are written (the others are never in
; a map mask). A column of a group is 8 rows, SLOT_ROW_GROUPS apart.
; Changes: AF, BC, DE, HL
; Time:    about 12,000 clocks
write_slot:
        gc_set GC_MODE, GC_WRITE_CPU     ; write mode 0: a CPU write stores its byte
        ld bc,VGA_SEQ_INDEX
        ld a,SEQ_MAP_MASK
        out (c),a                       ; the index stays at the map mask
        xor a
        ld (render_plane),a
1:      ld e,a
        ld d,0
        ld hl,bit_of_column             ; ring.s: 1, 2, 4, 8, ...
        add hl,de
        ld a,(hl)
        ld bc,VGA_SEQ_DATA
        out (c),a                       ; the map mask: plane render_plane
        xor a
        ld (render_align),a
4:      ld a,(render_align)
        ld b,a
        ld c,SLOT_ALIGN_GROUPS
        mlt bc
        ld hl,(render_slot)
        add hl,bc
        ld (render_dest),hl
        xor a
        ld (render_group),a
5:      ld a,(render_group)             ; x = 4 g + q - a
        add a,a
        add a,a
        ld hl,render_plane
        add a,(hl)
        ld hl,render_align
        sub (hl)
        cp 8
        jr nc,7f                        ; outside the tile (below 0 wraps above 7)
; Eight rows: pixels[8 y + x] to the slot group 3 y + g of the alignment.
        ld e,a
        ld d,pixels >> 8
        ld a,e
        add a,pixels & 0xFF
        ld e,a                          ; DE = pixels + x (pixels does not cross a page)
        ld hl,(render_dest)
        ld a,(render_group)
        add a,l
        ld l,a
        jr nc,6f
        inc h
6:      ex de,hl                        ; HL = the pixel, DE = the group of row 0
        .rept 8
        ld a,(hl)
        ld (de),a
        ld a,l
        add a,8
        ld l,a
        inc de
        inc de
        inc de
        .endr
7:      ld hl,render_group
        inc (hl)
        ld a,(hl)
        cp SLOT_ROW_GROUPS
        jr c,5b
        ld hl,render_align
        inc (hl)
        ld a,(hl)
        cp GROUP_PIXELS                 ; the four alignments
        jp c,4b
        ld hl,render_plane
        inc (hl)
        ld a,(hl)
        cp VGA_PLANES
        jp c,1b
        gc_set GC_MODE, GC_WRITE_LATCHES ; write mode 1: latch copies again
        seq_set SEQ_MAP_MASK, ALL_PLANES
        ret
        .if SLOT_ROW_GROUPS != 3
        .error "write_slot steps a row with three INC DE"
        .endif

; expand_tile: the 64 pixel values of a tile, left to right, top to
; bottom, into pixels. render_key and status.s use it.
; In:       A    the tile
;           D    the pixel value of the palette with pen 0 added: 16 + 4 x
;                palette for a sprite, 4 x palette for the background (pen 0
;                itself always gives 0)
;           E    nonzero: mirror each row, left to right (the key's
;                horizontal flip); the rows keep their order
;           HL   the BBR value that shows the pattern table (chr_sprites__bbr
;                or chr_bg__bbr) at the bank area
; Changes:  AF, BC, DE, HL; BBR
; Time:     about 3,000 clocks
expand_tile:
        push af
        ld a,l
        out0 (BBR),a                    ; the pattern table: 256 tiles of 16 bytes, one 4 KB page
        pop af
        push ix
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,h
        or ART_WINDOW >> 8
        ld h,a
        push hl
        pop ix                          ; IX = the tile: bit plane 0, then bit plane 1
        ld hl,pixels
        ld a,e
        or a
        ld e,8                          ; E = the rows
        jr nz,expand_flipped
; A pixel: the plane 1 bit, then the plane 0 bit, into the pen; a pen
; other than 0 adds the palette. The left pixel is bit 7, so the shifts go
; left; a flipped key takes bit 0 first.
        .macro expand_row shift
        ld c,(ix+0)                     ; bit plane 0 of the row
        ld b,(ix+8)                     ; bit plane 1
        inc ix
        .rept 8
        xor a
        \shift b
        adc a,a                         ; ADC, not RLA: it sets Z
        \shift c
        adc a,a
        jr z,9f
        add a,d
9:      ld (hl),a
        inc hl
        .endr
        .endm
1:      expand_row sla
        dec e
        jp nz,1b
        pop ix
        ret
expand_flipped:
1:      expand_row srl
        dec e
        jp nz,1b
        pop ix
        ret

