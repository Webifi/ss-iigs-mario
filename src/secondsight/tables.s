; Constant tables of the drawing code, computed by the assembler.
;
; mask_tables: the map masks of an 8-pixel row at each alignment. Three
; tables of 1 KB, one for each of the three groups that an 8-pixel row at
; alignment a covers (pixels at a .. a + 7 of a 12-pixel span). Entry
; 1024 x g + 256 x a + O: the map mask of group g (bit q = plane q =
; pixel 4 g + q of the span) for the opacity byte O of the row (bit 7 =
; pixel 0 of the row). Pixel x of the row is pixel a + x of the span.
; Alignment 0 also gives the background's opacity per group: group 0 =
; pixels 0-3, group 1 = pixels 4-7 of a cell (sprites.s behind_masks).
;
; bit_reverse: each byte with its bits in reverse order: the opacity of a
; row drawn with a horizontal flip.

        .global mask_tables, bit_reverse

; mask_byte G, A, O: the map mask of group G at alignment A for opacity O.
        .macro mask_byte g, a, o
        .set mask, 0
        .irp q, 0, 1, 2, 3
        .set x, 4 * \g + \q - \a
        .if (x >= 0) && (x <= 7)
        .set mask, mask | ((((\o) >> (7 - x)) & 1) << \q)
        .endif
        .endr
        .byte mask
        .endm

        .section .rodata.tables,"a",@progbits
        .balign 256
mask_tables:
        .irp g, 0, 1, 2
        .irp a, 0, 1, 2, 3
        .set opacity, 0
        .rept 256
        mask_byte \g, \a, opacity
        .set opacity, opacity + 1
        .endr
        .endr
        .endr

bit_reverse:
        .set value, 0
        .rept 256
        .set reversed, 0
        .irp bit, 0, 1, 2, 3, 4, 5, 6, 7
        .set reversed, reversed | (((value >> \bit) & 1) << (7 - \bit))
        .endr
        .byte reversed
        .set value, value + 1
        .endr
