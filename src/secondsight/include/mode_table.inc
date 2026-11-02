; Video mode programming from an editable register table. A record is 4
; bytes: operation (0 OUT, 1 IN), port low, port high, value. 0xFF ends the
; table. No clock, sync, blanking or position is an instruction operand:
; every register value of the mode is in the one table.
;
; mode_table PREFIX, PATCHES: the code before the table PREFIX_data. With
; PATCHES, it first reads the cable sense: an AppleColor RGB monitor
; applies PATCHES (value, address) replacements from PREFIX_rgb. The choice
; is made before any clock or CRTC write, so a VGA signal never reaches an
; RGB monitor. The table and the replacements follow the macro, then
; PREFIX_done.

        .ifndef MODE_TABLE_INC
        .equ MODE_TABLE_INC, 1

        .macro mode_table prefix, patches=0
        .if \patches
        ld bc,VGA_INPUT_STATUS_0
        in a,(c)
        and STATUS_SENSE                ; 1: a VGA monitor
        jp nz,\prefix\()_apply
        ld hl,\prefix\()_rgb
        ld b,\patches
\prefix\()_patch:
        ld a,(hl)
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld (de),a
        djnz \prefix\()_patch
\prefix\()_apply:
        .endif
        mode_apply \prefix, \prefix\()_data
        .endm

; Apply the register table at TABLE; PREFIX_done must follow.
        .macro mode_apply prefix, table
        ld hl,\table
\prefix\()_next:
        ld a,(hl)
        inc hl
        cp 0xFF
        jp z,\prefix\()_done
        ld d,a
        ld c,(hl)
        inc hl
        ld b,(hl)
        inc hl
        ld a,(hl)
        inc hl
        bit 0,d
        jp nz,\prefix\()_read
        out (c),a
        jp \prefix\()_next
\prefix\()_read:
        in a,(c)
        jp \prefix\()_next
        .endm

        .endif
