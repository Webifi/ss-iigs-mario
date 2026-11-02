; The packet to the card: the original's picture chip work at the start of
; each frame (document 02, steps 2-6 and 14), sent to the card as one packet
; (src/packet_layout.inc).
;
; Each frame, packet_frame:
;   1. adds the screen records of the frame's source (screen_source: list 1,
;      list 2, or a ROM record list of screen_rom_lists) to the pending
;      records, a queue in PENDING_WRITES: the bytes from pending_head to
;      pending_length; then empties the list sent, or list 1 for any other
;      source, as the original empties its write lists (02 section 11.4);
;   2. if the card shows the token of its free receive buffer, gives the
;      token's phase of the packet before to the clock (src/clock.s
;      clock_phase), then sends a packet: the flags, the scroll, the visible
;      sprites of the sprite list, then the oldest pending records, as many
;      whole records as fit the packet.
; It runs before the logic of the frame, so the packet holds the state that
; the logic of the frame before left: the original's picture N shows the
; state after logic N-1 (02 section 2).
; The token is READY_TOKEN, with the buffer in bit 0 and the phase in the
; bits of TOKEN_EARLY and TOKEN_PHASE (src/secondsight/picture.s); the
; firmware's handshake values never have bit 6 set.
; The game logic never waits for the card. A card that is still drawing
; gets no packet this frame; a frame with more records than a packet holds
; (a level start: the clear and a whole new screen) sends them over the next
; packets. While records wait in the queue, the packets keep the background
; and the sprites off, so the screen never shows a picture that has only
; some of them. Only a full queue makes the game wait for the card
; (packet_flush).
;
; Routines:
;   packet_frame   the picture chip work of one frame (JSL from game_frame)
;   packet_clear   the original's direct clear of both name tables (JSL)
;   packet_menu    the options menu: the pending records, then PF_MENU (JSL)
;   add_records    add a list of records to the queue
;   record_size    the bytes of one record of the queue
;   packet_drain   send packets until the queue is empty
;   packet_flush   wait for the card, then send one packet
;   packet_send    build the packet and send it

.a8
.i8

; The records that always fit a packet: the receive area less the header
; (its first word is the size word), a full sprite list and the end byte of
; the records. A packet of PACKET_AREA bytes is even, so it needs no pad byte.
PACKET_RECORD_ROOM = PACKET_AREA - PKT_HEADER - SPRITE_ENTRY*SPRITE_LIMIT - 1
VISIBLE_Y_LIMIT = 239           ; a sprite entry with Y from this on shows no row (the card draws at Y + 1)
PAD_UNIT = 2                    ; the sender sends whole words: a packet ends on an even byte
.assert (PACKET_AREA .mod PAD_UNIT) = 0, error, "a full packet needs no pad byte"
; A wait for the card gives up after SS_WAIT_ROUNDS x SS_POLLS reads of its
; handshake, about 2 s: a picture that draws a whole screen and new sprites
; takes about 0.2 s, and only a card that stopped takes longer.
SS_WAIT_ROUNDS = 10
TOKEN_KEY = secondsight_READY_TOKEN | 1 ; the bits of a token that name the buffer
SCROLL_RING_BITS = $01FF        ; picture_scroll: X in the 512-pixel ring of the two name tables
.assert (TOKEN_KEY & (secondsight_TOKEN_EARLY | secondsight_TOKEN_PHASE)) = 0, error
.assert RING_COLUMNS * 8 = SCROLL_RING_BITS + 1, error, "the ring is 512 pixels wide"

; The system direct page (src/iigs.cfg SYSPAGE): its labels are direct page
; offsets; these routines run with D = SYSTEM_PAGE.
.segment "SYSPAGE": zeropage
packet_source:  .res 3          ; add_records: the records to add (any bank)
source_length:  .res 2          ; add_records: their length in bytes

.segment "SYSRAM"
pending_length: .res 2          ; the end of the queue in PENDING_WRITES
pending_head:   .res 2          ; its first byte not sent; pending_head = pending_length: empty (both 0)
packet_token:   .res 1          ; the token of the card buffer that the next packet goes to (src/stream.s)
card_token:     .res 1          ; packet_frame: the token that the card shows
phase_valid:    .res 1          ; 1: the last packet went from packet_frame, so the card's phase is a frame's
packet_length:  .res 2          ; the bytes of the packet after its size word (src/stream.s)
packet_chunk_end: .res 2        ; packet_send: the records of the queue that the packet takes

.segment "NATIVE"

; record_heads, record_counts: for each record kind (REC_*), the bytes of
; its fixed part, and the offset of its count byte (0: the kind has no
; count; its size is the fixed part). record_size reads them.
record_heads:
        .byte 0                         ; REC_END: not in the queue
        .byte REC_CELLS_HEAD
        .byte REC_SQUARE_SIZE
        .byte REC_COLUMN_SIZE
        .byte REC_PALETTES_HEAD
        .byte REC_COLOURS_HEAD
        .byte REC_CLEAR_SIZE
record_counts:
        .byte 0
        .byte REC_CELLS_HEAD - 1        ; row, column, count
        .byte 0
        .byte 0
        .byte REC_PALETTES_HEAD - 1     ; square row, square column, count
        .byte REC_COLOURS_HEAD - 1      ; first entry, count
        .byte 0
.assert ROM_LIST_ENTRY = 5, error, "packet_frame: source x 5 is source x 4 + source"
.assert REC_CELLS = 1 && REC_SQUARE = 2 && REC_COLUMN = 3 && REC_PALETTES = 4 && REC_COLOURS = 5 && REC_CLEAR = 6, error, "record_heads order"

; ---------------------------------------------------------------------------
; packet_frame: the picture chip work of one frame (02 steps 2-6 and 14):
; the records of the frame's source to the queue, the list emptied, then a
; packet when the card is free.
;
; In:       A8 I8; DBR = 0; any D (game_frame)
; Out:      the same registers; screen_source = SOURCE_LIST_1; the list of
;           the source emptied
; Changes:  A, X, Y
; Time:     each frame: the record copy (MVN, 7 cycles a byte) and, when the
;           card is free, packet_send
; Original: $8082-$80DD, $815C-$816E (the picture chip writes of the frame)
; ---------------------------------------------------------------------------
packet_frame:
        phd
        phb
        phk
        plb                             ; DBR = bank 0: this code and the game's variables
        pea SYSTEM_PAGE
        pld
        rep #$10
.i16
; The records of the source (the original's step 4).
        lda screen_source
        cmp #SOURCE_LIST_1
        bne @not_list_1
        ldx #.loword(screen_list_1)
        lda screen_list_1_end
        bra @bank_0
@not_list_1:
        cmp #SOURCE_LIST_2
        bne @rom_list
        ldx #.loword(screen_list_2)
        lda screen_list_2_end
@bank_0:
        stx packet_source
        stz packet_source+2
        sta source_length
        stz source_length+1
        bra @add
@rom_list:
        rep #$20
.a16
        and #$00FF
        sta source_length               ; source x ROM_LIST_ENTRY, through source_length
        asl a
        asl a
        clc
        adc source_length
        tax
        lda f:screen_rom_lists+ROM_LIST_ADDRESS,x
        sta packet_source
        lda f:screen_rom_lists+ROM_LIST_LENGTH,x
        sta source_length
        sep #$20
.a8
        lda f:screen_rom_lists+ROM_LIST_ADDRESS+2,x
        sta packet_source+2
@add:
        jsr add_records
; Empty the list sent, or list 1 for every other source (the original's
; step 5): the records that list 1 holds when a ROM list goes are lost, as
; in the original (02 section 11.4, rule 2).
        lda screen_source
        cmp #SOURCE_LIST_2
        bne @empty_1
        stz screen_list_2_end
        bra @emptied
@empty_1:
        stz screen_list_1_end
        stz screen_list_1_original_end
@emptied:
        lda #SOURCE_LIST_1
        sta screen_source
; The packet, when the card shows the token of its free buffer.
        lda f:SS_HANDSHAKE
        sta card_token
        and #TOKEN_KEY
        cmp packet_token
        bne @busy                       ; the card still draws: no packet this frame
        lda phase_valid
        beq @send
        lda card_token
        jsr clock_phase                 ; src/clock.s: the phase of the last packet
@send:
        jsr packet_send
        lda #1
        sta phase_valid
        bra @sent
@busy:
        stz phase_valid
@sent:
        sep #$10
.i8
        plb
        pld
        rtl

; ---------------------------------------------------------------------------
; packet_clear: the original's direct clear of both name tables
; (clear_name_tables, 02 section 12): a REC_CLEAR record in the queue, at
; its place among the records. The original writes the chip at once,
; outside the frame's send; the queue keeps that order.
;
; In:       A   the tile of every cell; A8; any X width, D, DBR
; Out:      the record queued
; Changes:  A
; Original: $8E19-$8E5B (the chip writes only; the RAM side is the caller's)
; ---------------------------------------------------------------------------
packet_clear:
        phd
        phb
        php
        phk
        plb                             ; DBR = bank 0
        pea SYSTEM_PAGE
        pld
        rep #$10
.i16
        phx
        phy
        pha
        ldx pending_length
        cpx #PENDING_WRITES_SIZE - REC_CLEAR_SIZE + 1
        bcc @fits
        jsr packet_drain
        ldx pending_length
@fits:
        lda #REC_CLEAR
        sta f:PENDING_WRITES,x
        pla
        sta f:PENDING_WRITES+1,x
        inx
        inx
        stx pending_length
        ply
        plx
        plp
        plb
        pld
        rtl

; ---------------------------------------------------------------------------
; packet_menu: the options menu starts: the pending records go to the card
; (a packet as usual), then a packet with PF_MENU only, after which the card
; gives the screen to its firmware (src/secondsight/menu.s). The game waits
; for the card here.
;
; In:       A8; any X width, D, DBR
; Out:      the caller's widths, D, DBR
; Changes:  A, X, Y
; Original: none
; ---------------------------------------------------------------------------
packet_menu:
        php
        phd
        phb
        phk
        plb
        pea SYSTEM_PAGE
        pld
        sep #$20
.a8
        rep #$10
.i16
        jsr packet_drain                ; the pending records, the sprites and the scroll of now
        ldy #SS_WAIT_ROUNDS
@round:
        ldx #SS_POLLS
@wait:
        lda f:SS_HANDSHAKE
        and #TOKEN_KEY
        cmp packet_token
        beq @send
        dex
        bne @wait
        dey
        bne @round
        jmp failed
@send:
        lda #PF_MENU
        sta PACKET_BUFFER+PKT_FLAGS
        stz PACKET_BUFFER+PKT_SPRITES
        stz PACKET_BUFFER+PKT_SCROLL
        stz PACKET_BUFFER+PKT_SCROLL+1
        lda #REC_END
        sta PACKET_BUFFER+PKT_HEADER
        rep #$20
.a16
; The size word: the header after it and the end byte, rounded up to an
; even total.
        lda #((PKT_HEADER + 2) & $FFFE) - 2
        sta PACKET_BUFFER+PKT_SIZE
        sta packet_length
        sep #$20
.a8
        jsr stream_packet
        lda packet_token
        eor #1
        sta packet_token
        plb
        pld
        plp
        rtl

; ---------------------------------------------------------------------------
; add_records: add the records at [packet_source], source_length bytes, to
; the queue. When the queue lacks the room, the pending records go to the
; card first (packet_drain); a source is at most a few hundred bytes, so the
; empty queue always holds it. The lists of the frame are in bank 0 and go
; with one block move; a ROM record list (any bank) goes byte by byte,
; because MVN takes its banks from the instruction.
;
; In:       [packet_source], source_length; D = SYSTEM_PAGE, DBR = 0, A8 I16
; Out:      pending_length + source_length
; Changes:  A, X, Y
; Time:     7 cycles a byte from bank 0 (MVN); about 16 a byte from another
;           bank
; Original: none
; ---------------------------------------------------------------------------
add_records:
        rep #$20
.a16
        lda source_length
        beq @done                       ; an empty list
        clc
        adc pending_length
        cmp #PENDING_WRITES_SIZE + 1
        bcc @room
        sep #$20
.a8
        jsr packet_drain
@room:
        sep #$20
.a8
        lda packet_source+2
        rep #$20
.a16
        bne @far
        lda pending_length
        clc
        adc #.loword(PENDING_WRITES)
        tay                             ; the destination
        ldx packet_source               ; the source, in bank 0
        lda source_length
        dec a                           ; MVN moves A + 1 bytes
        phb
        mvn #0,#^PENDING_WRITES         ; MVN source bank, destination bank: bank 0 to the queue
        plb
        bra @moved
@far:
        ldx pending_length
        ldy #0
        sep #$20
.a8
@byte:
        lda [packet_source],y
        sta f:PENDING_WRITES,x
        inx
        iny
        cpy source_length
        bne @byte
        rep #$20
.a16
@moved:
        lda pending_length
        clc
        adc source_length
        sta pending_length
@done:
        sep #$20
.a8
        rts

; ---------------------------------------------------------------------------
; record_size: the bytes of the record at PENDING_WRITES + X.
;
; In:       X   its offset in the queue; DBR = 0, A16 I16
; Out:      A   its size in bytes
; Changes:  A, Y
; Original: none
; ---------------------------------------------------------------------------
record_size:
.a16
.i16
        lda f:PENDING_WRITES,x
        and #$00FF
        tay                             ; Y = the kind
        lda record_counts,y
        and #$00FF
        beq @fixed
        phx
        clc
        adc 1,s
        tax                             ; X = the count byte
        lda f:PENDING_WRITES,x
        plx
        and #$00FF                      ; the count
        bra @head
@fixed:
        lda #0
@head:
        sep #$20
.a8
        clc
        adc record_heads,y
        xba
        adc #0                          ; the carry of the low byte
        xba
        rep #$20
.a16
        rts

; ---------------------------------------------------------------------------
; packet_drain: send packets until the queue is empty (packet_flush).
; In: D = SYSTEM_PAGE, DBR = 0, A8 I16. Changes: A, X, Y.
; ---------------------------------------------------------------------------
packet_drain:
.a8
.i16
        jsr packet_flush
        rep #$20
.a16
        lda pending_length
        sep #$20
.a8
        bne packet_drain                ; SEP keeps the Z of the 16-bit load
        rts

; ---------------------------------------------------------------------------
; packet_flush: wait for the card, then send a packet: the oldest pending
; records with the sprites and the scroll of now. A card that does not
; answer stops the game (game.s failed). packet_source and source_length
; stay as they are.
; In: D = SYSTEM_PAGE, DBR = 0, A8 I16. Changes: A, X, Y.
; ---------------------------------------------------------------------------
packet_flush:
        stz phase_valid                 ; the phase of this packet is not a frame's
        ldy #SS_WAIT_ROUNDS
@round:
        ldx #SS_POLLS
@wait:
        lda f:SS_HANDSHAKE
        and #TOKEN_KEY
        cmp packet_token
        beq packet_send
        dex
        bne @wait
        dey
        bne @round
        jmp failed

; ---------------------------------------------------------------------------
; packet_send: build the packet in PACKET_BUFFER and send it.
;
; In:       the card shows packet_token; D = SYSTEM_PAGE, DBR = 0, A8 I16
; Out:      the packet sent; pending_head past its records; packet_token the
;           other buffer
; Changes:  A, X
; Time:     about 1,500 cycles for the sprites, 7 cycles a record byte, then
;           the send (stream.s)
; Original: none (the card side of the original's steps 2-6 and 14)
; ---------------------------------------------------------------------------
packet_send:
        phy
; The flags: the picture is on when screen_off was 0 (the original's step
; 2: the background and the sprites together), and the status split.
        stz PACKET_BUFFER+PKT_FLAGS
        lda screen_off
        bne @split
        lda #PF_BACKGROUND | PF_SPRITES
        sta PACKET_BUFFER+PKT_FLAGS
@split:
        lda status_split
        beq @scroll
        lda #PF_STATUS
        tsb PACKET_BUFFER+PKT_FLAGS
; The scroll: the world X of the picture's left edge. Its low 9 bits are
; the original's scroll (picture_scroll, the name table bit as bit 8), so
; the card's ring column of a world column is the original's name-table
; column; its high bits are those of the screen's left edge, so the world X
; grows with the area and the card's pages never see a jump back.
@scroll:
        rep #$20
.a16
        lda screen_left
        and #.loword(~SCROLL_RING_BITS)
        sta PACKET_BUFFER+PKT_SCROLL
        lda picture_scroll
        and #SCROLL_RING_BITS
        tsb PACKET_BUFFER+PKT_SCROLL
        sep #$20
.a8
; The sprites: the entries of the sprite list that show a row, in order.
        ldx #0                          ; the entry in the sprite list
        ldy #PKT_HEADER                 ; the byte of the packet
@sprite:
        lda sprite_list+SPRITE_Y,x
        cmp #VISIBLE_Y_LIMIT
        bcs @hidden
        rep #$20
.a16
        lda sprite_list,x               ; the four bytes as two words
        sta PACKET_BUFFER,y
        lda sprite_list+2,x
        sta PACKET_BUFFER+2,y
        sep #$20
.a8
        iny
        iny
        iny
        iny
@hidden:
        inx
        inx
        inx
        inx
        cpx #SPRITE_ENTRY*SPRITE_LIMIT
        bcc @sprite
        rep #$20
.a16
        tya
        sec
        sbc #PKT_HEADER
        lsr a
        lsr a
        sep #$20
.a8
        sta PACKET_BUFFER+PKT_SPRITES
; The oldest pending records: all of them when they fit, else the whole
; records from pending_head that fit PACKET_RECORD_ROOM; one block move.
        rep #$20
.a16
        lda pending_length
        sec
        sbc pending_head
        bne @some
        jmp @end                        ; none
@some:
        cmp #PACKET_RECORD_ROOM + 1
        bcc @chunk                      ; A = all of them
        ldx pending_head
@record:
        stx packet_chunk_end
        phy
        jsr record_size
        ply
        clc
        adc packet_chunk_end
        tax                             ; the end of this record
        sec
        sbc pending_head
        cmp #PACKET_RECORD_ROOM + 1
        bcc @record                     ; it fits: try the next one
        lda packet_chunk_end
        sec
        sbc pending_head                ; A = the records that fit
@chunk:
        sta packet_chunk_end
        phy
        tya
        clc
        adc #PACKET_BUFFER
        tay                             ; the destination
        lda pending_head
        clc
        adc #.loword(PENDING_WRITES)
        tax                             ; the source
        lda packet_chunk_end
        dec a                           ; MVN moves A + 1 bytes
        phb
        mvn #^PENDING_WRITES,#^PACKET_BUFFER
        plb
        ply
        tya
        clc
        adc packet_chunk_end
        tay
        lda pending_head
        clc
        adc packet_chunk_end
        cmp pending_length
        bne @left
        stz pending_length              ; the queue is empty: it starts again at 0
        lda #0
        bra @head
@left:
        pha
        sep #$20
.a8
        lda #PF_BACKGROUND | PF_SPRITES
        trb PACKET_BUFFER+PKT_FLAGS     ; records still wait: the screen stays off
        rep #$20
.a16
        pla
@head:
        sta pending_head
@end:
        sep #$20
.a8
        lda #REC_END
        sta PACKET_BUFFER,y
        iny
; The size word: the bytes after it, the end byte included; the sender
; sends whole words, so the count rounds up to an even total.
        rep #$20
.a16
        tya
        inc a
        and #$FFFE
        dec a
        dec a
        sta PACKET_BUFFER+PKT_SIZE
        sta packet_length
        sep #$20
.a8
        jsr stream_packet
        lda packet_token
        eor #1
        sta packet_token
        ply
        rts
