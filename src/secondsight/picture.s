; The picture loop: for each packet, change the ring, draw the back page and
; show it.
;
; One picture:
;   1. take the packet (stream.s): flags, scroll, sprites, screen records;
;   2. apply the screen records to the ring and the palette (ring.s);
;   3. draw the back page: the columns that the scroll brings in, the
;      background under its old sprites and every dirty cell (page.s), the
;      status band (status.s);
;   4. start the receive of the next packet, now that DMA channel 0 is done
;      for this picture (channel 1 must not wait behind a channel 0 burst
;      while the IIgs sends);
;   5. draw the sprites (sprites.s);
;   6. show the page: the start address while the old page still shows,
;      then at the vertical retrace the pan, the palette and the screen
;      on/off (15-oak-drawing.md, "Page flipping", "Horizontal pixel
;      panning").
; A packet with PF_MENU starts the options menu instead (menu.s).
;
; The card never waits for the IIgs inside a picture; the IIgs sends the
; next packet when it sees the token (src/stream.s).
;
; The phase: the IIgs game clock runs at the picture rate that the mode
; should have (src/clock.s), but the card's clock may be 0.5% off its
; listed rate, and the two crystals differ. So the card measures where each
; packet arrives against its own vertical retrace, and the token of the next
; buffer carries that phase to the IIgs, which moves its clock to hold the
; arrival a little before the retrace (Second Sight reference
; 14-custom-code.md, "Game timing"). PRT0 runs free, one step each 20
; clocks; a time is its count, which falls. retrace_watch stamps an
; arrival during its wait for the retrace; stream_take stamps one after it
; (phase_late). The phase bits of the token:
;   TOKEN_EARLY | units << 1   the packet came that many units before the
;                              retrace (or at least that many, when it came
;                              before the wait began)
;   units << 1, 1-31           it came that many units after the retrace
;   0                          no measurement (the first token of a start)
; A unit is PHASE_UNIT_STEPS steps (142 us); 31 units is the most.

        .include "video.inc"
        .include "ring.inc"
        .include "page.inc"
        .include "packet_layout.inc"
        .include "z180.inc"

        .global picture_loop, back_page, picture_flags
        .global phase_start, phase_late, phase_bits
        .global TOKEN_EARLY, TOKEN_PHASE, PHASE_UNIT_STEPS ; the IIgs reads the phase (src/packet.s)

        .equ STATUS_ON_ROW, STATUS_TILE_ROWS ; first_row under the split
        .if ATTR_PAN_UNIT != 2
        .error "picture_loop doubles the pan with add a,a"
        .endif
        .equ TOKEN_EARLY, 0x80          ; the phase bits of a token: before the retrace
        .equ TOKEN_PHASE, 0x3E          ; the units, bits 1-5
        .equ PHASE_UNIT_STEPS, 128      ; PRT0 steps in a unit: phase_units takes HL >> 7
        .equ PHASE_MAX, 31
        .equ PHASE_PENDING, 0xFF        ; phase_bits: the packet had not come at the retrace
        .equ STREAM_STARTED, PACKET_AREA >> 8 ; BCR1H below this: channel 1 has a byte
        .if (PACKET_AREA & 0xFF) != 0
        .error "retrace_watch reads only BCR1H: PACKET_AREA must be whole pages"
        .endif

        .section .vars.picture,"aw",@nobits
back_page: .ds.b 1                      ; the page drawn now: 0 or 1
picture_flags: .ds.b 1                  ; PKT_FLAGS of the last packet
retrace_stamp: .ds.b 2                  ; PRT0 at the start of the last retrace
phase_bits: .ds.b 1                     ; the phase of the last packet, for the next token (stream_arm)

        .section .text.picture,"ax",@progbits

picture_loop:
        call stream_take
        ld ix,(stream_packet)
; The options menu: the card gives the screen to its firmware (menu.s).
        ld a,(ix+PKT_FLAGS)
        and PF_MENU
        jp nz,menu_enter
; The flags: the status split decides the first row that the pages draw.
        ld a,(ix+PKT_FLAGS)
        ld (picture_flags),a
        ld b,0
        and PF_STATUS
        jr z,1f
        ld b,STATUS_ON_ROW
1:      ld a,(first_row)
        cp b
        jr z,2f
        ld a,b
        ld (first_row),a
        or a
        call z,status_rows_dirty        ; the split went off: rows 0-3 are cells again
2:      ld l,(ix+PKT_SCROLL)
        ld h,(ix+PKT_SCROLL+1)
        ld (scroll_x),hl
        srl h
        rr l
        srl h
        rr l
        srl h
        rr l
        ld (tile_left),hl
; The screen records follow the sprite entries: SPRITE_ENTRY bytes each, in
; 16 bits (64 entries are 256 bytes).
        ld l,(ix+PKT_SPRITES)
        ld h,0
        add hl,hl
        add hl,hl
        ex de,hl                        ; DE = the bytes of the sprite entries
        push ix
        pop hl
        ld bc,PKT_HEADER
        add hl,bc
        add hl,de
        call apply_records
        .if SPRITE_ENTRY != 4
        .error "picture_loop: two ADD HL,HL give SPRITE_ENTRY x the sprites"
        .endif
; The back page.
        ld a,(back_page)
        ld iy,page_states
        or a
        jr z,3f
        ld iy,page_states + P_SIZE
3:      seq_set SEQ_MAP_MASK, ALL_PLANES
        oak_set OAK_READ_SEGMENT, 0     ; the tile art and the pages
        xor a
        ld (current_segment),a
        call page_scroll
        call page_repair
        call page_draw_dirty
        ld a,(first_row)
        or a
        call nz,status_band
        call stream_arm_other           ; the next packet comes while the sprites draw
        ld ix,(stream_packet)
        ld a,(picture_flags)
        and PF_SPRITES
        jr z,4f
        ld a,(ix+PKT_SPRITES)
        or a
        jr z,4f
        ld b,a
        ld de,PKT_HEADER
        add ix,de
        call sprites_draw
4:
; The start address: P_ORIGIN + scroll_x / 4. The CRTC takes it at the next
; vertical retrace, so it is written while the old page still shows.
        ld hl,(scroll_x)
        srl h
        rr l
        srl h
        rr l
        ld e,(iy+P_ORIGIN)
        ld d,(iy+P_ORIGIN+1)
        add hl,de
        ld bc,VGA_CRTC_INDEX
        ld a,CRTC_START_HIGH
        out (c),a
        inc c
        out (c),h
        dec c
        ld a,CRTC_START_LOW
        out (c),a
        inc c
        out (c),l
        call retrace_watch
; At the start of the retrace: the pan, which the attribute controller
; takes at once, so it changes with the start address.
        ld bc,VGA_STATUS
        in a,(c)                        ; the attribute flip-flop to the index
        ld bc,VGA_ATTR
        ld a,ATTR_PAS | ATTR_PANNING
        out (c),a
        ld a,(scroll_x)
        and GROUP_PIXELS - 1            ; the pixels past the start address's group
        add a,a                         ; ATTR_PAN_UNIT for each pixel
        out (c),a
        call palette_commit
; The screen: the backdrop colour everywhere while the background is off.
        ld a,(picture_flags)
        and PF_BACKGROUND
        ld a,DAC_MASK_NONE
        jr z,5f
        ld a,DAC_MASK_ALL
5:      ld bc,VGA_DAC_MASK
        out (c),a
        ld a,(back_page)
        xor 1
        ld (back_page),a
        jp picture_loop

; status_rows_dirty: mark rows 0-3 of every ring column dirty in both pages
; (the split went off, so the pages draw them as cells).
; Changes: AF, BC, DE, HL
status_rows_dirty:
        ld hl,dirty_maps
        ld de,DIRTY_MAP_SIZE
        ld b,STATUS_TILE_ROWS * DIRTY_ROW_BYTES
1:      ld (hl),0xFF
        push hl
        add hl,de
        ld (hl),0xFF
        pop hl
        inc hl
        djnz 1b
        ret

; phase_start: PRT0 runs free from its greatest count, with no interrupt;
; no measurement yet.
; Changes: AF
phase_start:
        xor a
        out0 (TCR),a                    ; PRT0 stops: its registers can be written
        ld (phase_bits),a
        dec a
        out0 (RLDR0L),a
        out0 (RLDR0H),a
        out0 (TMDR0L),a
        out0 (TMDR0H),a
        ld a,TCR_TDE0
        out0 (TCR),a
        ret

; retrace_watch: wait for the start of the next vertical retrace, and find
; where the next packet came against it. A retrace that still runs is the
; one before: the wait is for its end first.
; Out:      retrace_stamp; phase_bits: TOKEN_EARLY and the units, or
;           PHASE_PENDING when the packet has not come
; Changes:  AF, BC, DE, HL
retrace_watch:
        ld bc,VGA_STATUS
1:      in a,(c)
        and STATUS_RETRACE
        jr nz,1b
        call prt0_read
        ex de,hl                        ; DE = now: the bound for a packet that came before
        in0 a,(BCR1H)
        cp STREAM_STARTED
        jr c,3f
; The retrace or the packet, whichever comes first.
2:      in a,(c)
        and STATUS_RETRACE
        jr nz,4f
        in0 a,(BCR1H)
        cp STREAM_STARTED
        jr nc,2b
        call prt0_read
        ex de,hl                        ; DE = the packet's time
3:      in a,(c)
        and STATUS_RETRACE
        jr z,3b
        call prt0_read
        ld (retrace_stamp),hl
        ex de,hl
        or a
        sbc hl,de                       ; HL = the steps from the packet to the retrace
        call phase_units
        add a,a
        or TOKEN_EARLY
        ld (phase_bits),a
        ret
4:      call prt0_read
        ld (retrace_stamp),hl
        ld a,PHASE_PENDING
        ld (phase_bits),a
        ret

; phase_late: stream_take calls it when the packet's first bytes are in.
; A packet that had not come at the retrace: the units after it (at least 1).
; Changes: AF, HL
phase_late:
        ld a,(phase_bits)
        cp PHASE_PENDING
        ret nz
        push de
        call prt0_read
        ex de,hl
        ld hl,(retrace_stamp)
        or a
        sbc hl,de                       ; HL = the steps from the retrace to the packet
        pop de
        call phase_units
        cp PHASE_MAX
        adc a,0                         ; + 1, but not above PHASE_MAX
        add a,a
        ld (phase_bits),a
        ret

; phase_units: A = HL / PHASE_UNIT_STEPS, at most PHASE_MAX.
; Changes: AF, HL
phase_units:
        add hl,hl                       ; H = HL >> 7; the carry: HL was 32768 or more
        ld a,h
        jr c,1f
        cp PHASE_MAX + 1
        ret c
1:      ld a,PHASE_MAX
        ret

; prt0_read: HL = the PRT0 count. The read of TMDR0L holds TMDR0H for the
; read after it (Zilog UM0050, PRT).
; Changes: AF, HL
prt0_read:
        in0 l,(TMDR0L)
        in0 h,(TMDR0H)
        ret

; palette_commit: when the palette changed, write all 32 entries to the
; colour chip: slot n gets the colour of palette_colours[n] (ring.s). The
; slots are the pixel values of the art (scripts/tiles.py); dac_colours
; (colours.s) holds the 8-bit red, green and blue of each of the 64 colours
; of the original's picture chip.
; Changes: AF, BC, DE, HL
palette_commit:
        ld a,(palette_changed)
        or a
        ret z
        xor a
        ld (palette_changed),a
        ld bc,VGA_DAC_WRITE_INDEX
        out (c),a                       ; from slot 0; the index steps after each blue
        inc c                           ; VGA_DAC_DATA
        ld de,palette_colours
        ld a,32
1:      push af
        ld a,(de)
        inc de
        ld l,a
        ld h,0
        push de
        ld e,l
        ld d,h
        add hl,hl
        add hl,de                       ; 3 x colour
        ld de,dac_colours
        add hl,de
        pop de
        ld a,(hl)
        out (c),a                       ; red
        inc hl
        ld a,(hl)
        out (c),a                       ; green
        inc hl
        ld a,(hl)
        out (c),a                       ; blue
        pop af
        dec a
        jr nz,1b
        ret
