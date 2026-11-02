; The send of the update packet to the card: the bytes in PACKET_BUFFER go
; to the card's receive buffer as fast as the 65816 can write them. The
; packet code (src/packet.s) calls stream_packet once in a frame of the
; original, when the card shows the token of its free buffer, and once when
; the options menu opens (packet_menu). src/packet_layout.inc gives the
; packet; the card takes it in src/secondsight/stream.s.
;
; The method: S points at the card port SS_BURST, and PEI pushes two packet
; bytes from the page that D points at. Four PEIs fill $C0B7-$C0B0 (one
; burst); then S goes back to SS_BURST. A PEI pushes the high byte of its
; word first, so the card receives each byte pair swapped and swaps it back
; (src/secondsight/stream.s stream_take).
;
; Hardware rules (Second Sight reference, docs/09-host-protocol.md, "One
; command, step by step", and docs/14-custom-code.md, "In through event
; bytes and DMA1", "Speeds"):
;   - During a DMA phase each write to any of $C0B0-$C0B7 is one data byte
;     of the card's DMA channel 1; RDY holds the 65816 until the card has
;     taken the byte before, so no byte is lost.
;   - Each of those writes is a slow (1 MHz) slot cycle: a PEI costs about
;     3.88 us from the cycle counts, and 4.46 us measured on a IIgs.
;   - The pushes must reach the I/O page of bank 0, so SHADOW_IOLC is off
;     while they run (Apple IIgs Hardware Reference, the shadow register).
;     The IRQ vector at $FFEE is then the firmware's ROM, so the IRQ stays
;     masked until the RAM is back.
;
; Routines:
;   stream_packet   send the packet to the card

.a8
.i16

STREAM_PAGE = $100              ; the bytes of one direct page: what the PEI operands reach

.segment "SYSRAM"
stream_saved_sp: .res 2         ; stream_packet: the stack pointer while S points at the card port

.segment "NATIVE"

; ---------------------------------------------------------------------------
; stream_packet: send the packet in PACKET_BUFFER to the card: the size word
; and the packet_length bytes after it.
;
; In:       the card shows the token of its free buffer (the caller checked
;           SS_HANDSHAKE); packet_length = the bytes after the size word, an
;           even total; A8 X16, DBR = 0, D = SYSTEM_PAGE; A is not used
; Out:      the packet sent; A8 X16, D = SYSTEM_PAGE
; Changes:  A, X, Y; stream_saved_sp; SHADOW_IOLC off during the send
; Keeps:    DBR, the caller's P (its interrupt flag): the interrupts are
;           off during the send
; Time:     about 2.0-2.5 ms for each KB of the packet: 8 slow slot writes
;           and 21 fast cycles for each burst of 8 bytes
; Original: none
; ---------------------------------------------------------------------------
stream_packet:
        php
        sei
; The pushes go to the slot I/O of bank 0: I/O at $C000 (SHADOW_IOLC off).
        lda f:SHADOW
        and #<~SHADOW_IOLC
        sta f:SHADOW
        a16
        tsc
        sta stream_saved_sp
; Y = the bytes after the last full page, X = the full pages. The count
; includes the 2 bytes of the size word.
        lda packet_length
        clc
        adc #2
        pha
        and #STREAM_PAGE-1
        tay
        pla
        xba
        and #STREAM_PAGE-1
        tax
        lda #.loword(PACKET_BUFFER)     ; D = the first page of the packet
        tcd
        cpx #0
        bne @page
        jmp @tail
; One page: STREAM_PAGE / SS_BURST_SIZE bursts, each of four word pushes
; from the direct page.
@page:
        .repeat STREAM_PAGE/SS_BURST_SIZE, I
        lda #.loword(SS_BURST)
        tcs
        pei (I*SS_BURST_SIZE)
        pei (I*SS_BURST_SIZE+2)
        pei (I*SS_BURST_SIZE+4)
        pei (I*SS_BURST_SIZE+6)
        .endrepeat
        tdc
        clc
        adc #STREAM_PAGE                ; D = the next page
        tcd
        dex
        beq @tail
        jmp @page
; The rest: full bursts while SS_BURST_SIZE or more bytes are left.
@tail:
        cpy #SS_BURST_SIZE
        bcc @short_tail
@eight:
        lda #.loword(SS_BURST)
        tcs
        pei (0)
        pei (2)
        pei (4)
        pei (6)
        tdc
        clc
        adc #SS_BURST_SIZE
        tcd
        tya
        sec
        sbc #SS_BURST_SIZE
        tay
        cmp #SS_BURST_SIZE
        bcs @eight
; The last bytes, a word at a time through SS_DATA_OUT, from the address in
; X, high byte first as a PEI sends it. The stack and D come back first.
@short_tail:
        lda stream_saved_sp
        tcs
        tdc
        tax
        lda #SYSTEM_PAGE
        tcd
        cpy #0
        beq @done
@word:
        lda a:0,x
        xba
        sta f:SS_DATA_OUT
        inx
        inx
        dey
        dey
        bne @word
@done:
; RAM at $C000-$FFFF again (SHADOW_IOLC on), then the caller's P (and its
; interrupt flag).
        a8
        lda f:SHADOW
        ora #SHADOW_IOLC
        sta f:SHADOW
        plp
        rts
.assert SS_BURST_SIZE = 8, error  ; the four PEIs of each burst above
.assert (PACKET_BUFFER & (STREAM_PAGE-1)) = 0, error ; D on a page: each PEI costs no extra cycle
