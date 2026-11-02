; The packet stream from the IIgs: DMA channel 1 receives each update packet
; from the card port into one of two receive buffers, while the card draws
; from the other (src/packet_layout.inc gives the packet).
;
; The handshake: stream_arm starts channel 1 on a buffer and writes the
; buffer's token to HOST_DATA, where the IIgs reads it as the handshake byte
; (src/second_sight.inc SS_HANDSHAKE, src/packet.s); the IIgs then sends the
; packet. The IIgs PEI sender puts the two bytes of each word on the wire
; high byte first, so stream_take swaps each byte pair back.
;
; Routines:
;   stream_arm        start the receive into a buffer and show its token
;   stream_arm_other  the same for the buffer that does not hold the packet
;   stream_take       wait for the whole packet, then put its bytes in order
;   stream_wait       wait until channel 1 has stored a number of bytes

        .include "video.inc"
        .include "packet_layout.inc"

        .global stream_arm, stream_arm_other, stream_take, stream_packet
        .global READY_TOKEN, packet_buffer_0, packet_buffer_1

        .equ READY_TOKEN, 0x40          ; buffer 0; buffer 1 is READY_TOKEN + 1 (the IIgs: src/packet.s)

; The two receive buffers (secondsight.ld .packets): 1 KB each, at $0400 and
; $0800. A buffer is named by its high byte; bit 3 of it is the buffer
; number (stream_arm).
        .section .packets.buffer_0,"aw",@nobits
        .balign 256
packet_buffer_0: .ds.b PACKET_AREA
        .section .packets.buffer_1,"aw",@nobits
packet_buffer_1: .ds.b PACKET_AREA

        .section .vars.stream,"aw",@nobits
stream_receive: .ds.b 2                 ; the buffer that channel 1 fills (stream_arm writes it)
stream_end_count: .ds.b 2               ; stream_wait: the channel 1 count to wait for
stream_packet: .ds.b 2                  ; the packet that the card draws: its first byte
                                        ; (stream_take writes it; picture.s reads it)

        .section .text.stream,"ax",@progbits

; ---------------------------------------------------------------------------
; stream_arm: start receiving into the buffer whose high byte is A, and show
; its token to the IIgs.
;
; In:       A        the high byte of packet_buffer_0 or packet_buffer_1;
;           phase_bits (picture.s)
; Out:      stream_receive  the buffer; its size word is 0 until the packet
;           comes; HOST_DATA = the token
; Changes:  AF, HL
; Keeps:    BC, DE
; Original: none (the card side of the link)
; ---------------------------------------------------------------------------
stream_arm:
        ld h,a
        ld l,0
        ld (stream_receive),hl
        ld (hl),0                       ; a size word of 0: no packet yet
        inc hl
        ld (hl),0
; Channel 1: from the card port (IAR1, set at the start) to the buffer, at
; most PACKET_AREA bytes; DREQ1 paces it, one byte for each IIgs write.
        ld a,h
        out0 (MAR1H),a
        xor a
        out0 (MAR1L),a
        out0 (MAR1B),a                  ; bank 0: the buffers are in common area 0
        ld a,PACKET_AREA & 0xFF
        out0 (BCR1L),a
        ld a,PACKET_AREA >> 8
        out0 (BCR1H),a
        ld a,DSTAT_DE1 | DSTAT_KEEP0 | DSTAT_DME ; start channel 1; channel 0 keeps its state
        out0 (DSTAT),a
; The token: READY_TOKEN for buffer 0 ($04xx), READY_TOKEN + 1 for buffer 1
; ($08xx), with the phase of the last packet (picture.s). The IIgs reads it
; as its handshake byte and then sends.
        ld a,h
        rrca
        rrca
        rrca
        and 1
        add a,READY_TOKEN
        ld hl,phase_bits
        or (hl)
        out0 (HOST_DATA),a
        ret

; stream_arm_other: stream_arm for the buffer that stream_packet is not in.
; Changes: AF, HL. Keeps: BC, DE.
stream_arm_other:
        ld a,(stream_receive+1)
        xor stream_other                ; secondsight.ld: the bits that differ between the high bytes
        jp stream_arm

; ---------------------------------------------------------------------------
; stream_take: wait until the whole packet is in the receive buffer, stop
; channel 1, and swap each byte pair back into packet order.
;
; In:       stream_receive
; Out:      stream_packet  the first byte of the packet (its size word)
; Changes:  AF, BC, DE, HL
; Time:     each picture: the wait, then 63 clocks for each two bytes of
;           the packet (the swap loop)
; Original: none
; ---------------------------------------------------------------------------
stream_take:
; Wait for the size word: channel 1 has stored 2 bytes when its count is
; PACKET_AREA - 2 or less.
        ld hl,PACKET_AREA - 2
        ld (stream_end_count),hl
        call stream_wait
        call phase_late                 ; picture.s: a packet after the retrace
; The wire holds the size high byte first: (hl) is the high byte, (hl+1)
; the low byte.
        ld hl,(stream_receive)
        ld d,(hl)
        inc hl
        ld e,(hl)
        dec hl
; The packet is complete when 2 + size bytes have come, rounded up to a
; whole word (the IIgs sends words).
        inc de
        inc de
        inc de
        res 0,e
        push de                         ; the bytes of the packet on the wire
        push hl                         ; the buffer
        ld hl,PACKET_AREA
        or a
        sbc hl,de
        ld (stream_end_count),hl
        pop hl
        call stream_wait
        ld a,DSTAT_KEEP0 | DSTAT_DME    ; stop channel 1; channel 0 keeps its state
        out0 (DSTAT),a
        ld (stream_packet),hl
; Swap each byte pair back: HL walks the packet, BC counts the pairs.
        pop bc
        srl b
        rr c
1:      ld a,(hl)
        inc hl
        ld e,(hl)
        ld (hl),a
        dec hl
        ld (hl),e
        inc hl
        inc hl
        dec bc
        ld a,b
        or c
        jp nz,1b
        ret

; stream_wait: wait until the channel 1 count is stream_end_count or less.
; The count is read high, low, high again, so a borrow into the high byte
; between the reads cannot give a wrong count; the count only falls.
; Changes: AF, BC. Keeps: DE, HL.
stream_wait:
        push hl
1:      in0 a,(BCR1H)
        ld b,a
        in0 a,(BCR1L)
        ld c,a
        in0 a,(BCR1H)
        cp b
        jp nz,1b
        ld hl,(stream_end_count)
        or a
        sbc hl,bc
        jp c,1b                         ; the count is still above the end count
        pop hl
        ret
