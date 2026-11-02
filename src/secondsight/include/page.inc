; A page state (page.s page_states): the fields, for the code that draws
; into a page (IY points at the state).

        .ifndef PAGE_INC
        .equ PAGE_INC, 1

        .equ P_ORIGIN, 0                ; word: the group of world tile column 0, pixel row 0
        .equ P_TBASE, 2                 ; word: the world tile column at the page's first group
        .equ P_LEFT, 4                  ; word: the first world tile column that the page holds
        .equ P_RIGHT, 6                 ; word: the last one (below P_LEFT: none)
        .equ P_DIRTY, 8                 ; word: its dirty map
        .equ P_SPRITES, 10              ; word: its sprite records
        .equ P_COUNT, 12                ; byte: the sprite records
        .equ P_BASE, 13                 ; word: the page's first group (page_0 or page_1)
        .equ P_SIZE, 15

; A sprite record: what a page drew, for page_repair.
        .equ SPRITE_RECORD, 3           ; world X (word), top pixel row

        .endif
