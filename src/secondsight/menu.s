; The options menu, card side: give the screen to the card's firmware, and
; take it back.
;
; The options menu runs on the IIgs as Apple II text, which the firmware
; shows on every monitor at its own timings. The card program keeps the
; first 32 KB of video RAM free for the firmware's text mode
; (secondsight.ld), and keeps its own master image in SRAM bank 1. Its
; running copy in bank 0 ($2000-$9FFF) covers the firmware's code at
; $6000-$9FFF, and the firmware's own variables in $0000-$03FF and
; $0C00-$1FFF changed while it ran before RunCode. So:
;   enter: the variables go to the menu save area in bank 1, and the
;          firmware's parts of SRAM ($0000-$03FF, $0C00-$1FFF, $6000-$FFFF)
;          come back from the EPROM, as its cold start copies them. Then the
;          card jumps to the firmware's reset. With SRAM mapped at $0000 the
;          reset skips its own copy from the EPROM, so the firmware must be
;          back first. The
;          copies cover the card's stack ($9Fxx): after them nothing calls
;          or returns. The firmware then serves the IIgs again (SetMode,
;          SetShadow ...).
;   leave: the IIgs runs entry_resume (entry.s) with RunCode: the image and
;          the variables come back from bank 1, the mode is set again, and the
;          picture loop goes on. The pages and the art in video RAM stayed.
; The IIgs side: src/menu.s.
;
; Routines:
;   menu_enter   save the variables and restart the firmware (picture.s
;                jumps here for a packet with PF_MENU)

        .include "video.inc"

        .global menu_enter, menu_end

        .equ FIRMWARE_RESET, 0x0000     ; the firmware's reset vector

; firmware_copy START, BYTES: copy BYTES of the firmware image from the
; EPROM back into SRAM at START (through SRAM_MIRROR), with DMA channel 0 in
; burst mode, and wait in line for its end: no call, no stack.
        .macro firmware_copy start, bytes
        set_io SAR0L, (EPROM + \start) & 0xFF
        set_io SAR0H, ((EPROM + \start) >> 8) & 0xFF
        set_io SAR0B, (EPROM + \start) >> 16
        set_io DAR0L, (SRAM_MIRROR + \start) & 0xFF
        set_io DAR0H, ((SRAM_MIRROR + \start) >> 8) & 0xFF
        set_io DAR0B, (SRAM_MIRROR + \start) >> 16
        set_io BCR0L, (\bytes) & 0xFF
        set_io BCR0H, (\bytes) >> 8
        set_io DCNTL, 0
        set_io DMODE, DMODE_BURST
        set_io DSTAT, DSTAT_DE0 | DSTAT_KEEP1 | DSTAT_DME
1:      in0 a,(DSTAT)
        and DSTAT_DE0
        jp nz,1b
        .endm

        .section .text.menu,"ax",@progbits

; ---------------------------------------------------------------------------
; menu_enter: the packet asked for the options menu (PF_MENU).
; This code and memory_dma (entry.s) run from below $6000 (secondsight.ld
; links them first and checks it): the third copy writes over $6000-$9FFF.
;
; In:       the picture loop's state; DMA channels idle
; Out:      does not return: the firmware runs
; Changes:  everything
; Time:     once for each options menu
; Original: none
; ---------------------------------------------------------------------------
menu_enter:
        di
; The variables (state_save__start to state_save__end) to the menu save
; area in bank 1 (physical menu_save), with DMA channel 0.
        ld hl,state_save__start
        ld a,l
        out0 (SAR0L),a
        ld a,h
        out0 (SAR0H),a
        xor a
        out0 (SAR0B),a
        ld a,menu_save__low
        out0 (DAR0L),a
        ld a,menu_save__high
        out0 (DAR0H),a
        ld a,menu_save__bank
        out0 (DAR0B),a
        ld hl,state_save__size
        ld a,l
        out0 (BCR0L),a
        ld a,h
        out0 (BCR0H),a
        call memory_dma                 ; entry.s: the CPU waits until the burst ends
; The firmware's parts, from the EPROM (its low 64 KB is the image that the
; firmware's cold start copies, at the same offsets).
        firmware_copy FIRMWARE_VECTORS, FIRMWARE_VECTORS_BYTES
        firmware_copy FIRMWARE_HANDLERS, FIRMWARE_HANDLERS_BYTES
        firmware_copy FIRMWARE_RENDERERS, FIRMWARE_RENDERERS_BYTES
; The firmware's MMU at its reset: the bank area and common area 1 at their
; reset values; the reset code sets the rest.
        xor a
        out0 (BBR),a
        out0 (CBR),a
        jp FIRMWARE_RESET
menu_end:
