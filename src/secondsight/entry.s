; The start of the card program, from the firmware's RunCode command.
;
; RunCode (the IIgs sends it, src/game.s) jumps to entry_start, or to
; entry_resume after the options menu, with the MMU of secondsight.ld
; game_*: logical $2000-$BFFF is physical $12000-$1BFFF, where the disk
; loaded the program image. The image therefore runs where it loaded. The
; entry:
;   1. copies the image into bank 0, physical $02000-$09FFF (DMA channel 0);
;   2. sets run_cbar: logical $0000-$9FFF is then physical bank 0, and the
;      code goes on in the copy, at the same address, with no jump;
;   3. clears the variables (start), or copies them back from the menu save
;      area in bank 1 (resume);
;   4. sets the video mode and the renderer, and runs the picture loop
;      (picture.s), which never returns. The options menu leaves the program
;      through a reset of the firmware (menu.s), so the firmware's stack is
;      not kept.
;
; Routines:
;   entry_start     the first start: the image, clear variables, the art
;   entry_resume    the start after the options menu: the image, the saved
;                   variables
;   copy_image      the program image from SRAM bank 1 into bank 0
;   memory_dma      one burst of DMA channel 0, memory to memory
;   renderer_setup  the video mode, the video RAM window, DMA channel 1

        .include "video.inc"
        .include "packet_layout.inc"

        .global entry_start, entry_resume, memory_dma ; memory_dma: also menu.s
        .global PAGE_GROUPS, STATUS_GROUPS, SLOTS_PER_WINDOW, SPRITE_SLOTS ; for secondsight.ld

        .section .text.entry,"ax",@progbits

; ---------------------------------------------------------------------------
; entry_start: the first start of the program, from RunCode.
;
; In:       the MMU of secondsight.ld game_*; interrupts as the firmware
;           leaves them
; Out:      never returns: picture_loop runs until the options menu
; Changes:  everything; SP = stack__top
; Time:     once; the sprite art (sprites_init) takes about 0.6 s
; Original: none
; ---------------------------------------------------------------------------
entry_start:
        di
        call copy_image
        ld a,run_cbar
        out0 (CBAR),a                   ; from here the code runs in the bank 0 copy
        ld sp,stack__top
; The variables start at 0; the initialised data came with the image.
        ld hl,vars__start
        ld (hl),0
        ld de,vars__start + 1
        ld bc,vars__size - 1
        ldir
        call renderer_setup
        call ring_clear_all
        call page_init
        call sprites_init
        call status_redraw
        jp loop_start

; ---------------------------------------------------------------------------
; entry_resume: the start after the options menu, from RunCode. The menu
; (menu.s) saved the variables in SRAM bank 1 at menu_save; the pages, the
; tile art and the sprite art stay in video RAM, because the firmware's
; text mode uses only the first 32 KB of it.
;
; In:       the MMU of secondsight.ld game_*; the variables at menu_save
; Out:      never returns: picture_loop
; Changes:  everything; SP = stack__top
; Time:     once for each return from the menu
; Original: none
; ---------------------------------------------------------------------------
entry_resume:
        di
        call copy_image
        ld a,run_cbar
        out0 (CBAR),a
        ld sp,stack__top
; The variables come back from the menu save area (physical menu_save).
        ld a,menu_save__low
        out0 (SAR0L),a
        ld a,menu_save__high
        out0 (SAR0H),a
        ld a,menu_save__bank
        out0 (SAR0B),a
        ld hl,state_save__start
        ld a,l
        out0 (DAR0L),a
        ld a,h
        out0 (DAR0H),a
        xor a
        out0 (DAR0B),a
        ld hl,state_save__size
        ld a,l
        out0 (BCR0L),a
        ld a,h
        out0 (BCR0H),a
        call memory_dma
        call renderer_setup
        ld a,1
        ld (palette_changed),a          ; the firmware's text mode set its own colours
; The pages still hold their pictures; the next picture draws on as before.
loop_start:
        xor a
        ld (back_page),a
        call phase_start                ; picture.s: the phase clock, no measurement yet
        ld a,packet_buffer_0 >> 8
        call stream_arm                 ; the first packet comes into buffer 0
        jp picture_loop

; ---------------------------------------------------------------------------
; copy_image: copy the program image from SRAM bank 1 into bank 0 with DMA
; channel 0 (secondsight.ld image__*).
;
; In:       nothing
; Out:      physical image__run to image__end = the image
; Changes:  AF
; Time:     image__size bytes at burst speed, once each start
; Original: none
; ---------------------------------------------------------------------------
copy_image:
        ld a,image_source__low
        out0 (SAR0L),a
        ld a,image_source__high
        out0 (SAR0H),a
        ld a,image_source__bank
        out0 (SAR0B),a
        ld a,image__run & 0xFF
        out0 (DAR0L),a
        ld a,image__run >> 8
        out0 (DAR0H),a
        xor a
        out0 (DAR0B),a
        ld a,image__size & 0xFF
        out0 (BCR0L),a
        ld a,image__size >> 8
        out0 (BCR0H),a
; Falls into memory_dma.

; ---------------------------------------------------------------------------
; memory_dma: run DMA channel 0 as its address and count registers are set:
; memory to memory, both addresses rising, burst (the CPU waits until it
; ends). DCNTL 0: no memory or I/O wait states added, channel 1 not set up
; (renderer_setup sets it after).
;
; In:       SAR0, DAR0, BCR0 set
; Out:      the copy done
; Changes:  AF
; Original: none
; ---------------------------------------------------------------------------
memory_dma:
        xor a
        out0 (DCNTL),a
        ld a,DMODE_BURST
        out0 (DMODE),a
        ld a,DSTAT_DE0 | DSTAT_KEEP1 | DSTAT_DME
        out0 (DSTAT),a
        ret

; ---------------------------------------------------------------------------
; renderer_setup: the video mode, the window of video RAM for the CPU, the
; latch copies, and DMA channel 1 for the packets.
;
; In:       nothing
; Out:      the mode of mode.s; the Oak VGA window at logical PAGE_WINDOW
;           in video RAM half 1; write mode 1 to all planes; the sequencer
;           index at SEQ_MAP_MASK; channel 1 from HOST_DATA
; Changes:  AF, BC, DE, HL
; Original: none
; ---------------------------------------------------------------------------
renderer_setup:
        call set_mode                   ; mode.s
; The Oak VGA window at physical $A0000 (not the linear window), video RAM
; half 1 (any access to $5xxxx selects it; the VGA window needs half 1).
        oak_set OAK_MEMORY_MAP, 0
        set_io LINEAR_WINDOW_OFF, 0
        set_io CBR, (VRAM_HALF1_SELECT - PAGE_WINDOW) >> 12
        ld a,(PAGE_WINDOW)              ; selects video RAM half 1
        oak_set OAK_READ_SEGMENT, 0
        oak_set OAK_WRITE_SEGMENT, 0
        gc_set GC_READ_MAP, 0
        gc_set GC_MODE, GC_WRITE_LATCHES
; seq_set leaves the sequencer index at SEQ_MAP_MASK. The sprite and status
; code then write only the data port (VGA_SEQ_DATA) to change the map mask.
        seq_set SEQ_MAP_MASK, ALL_PLANES
; DMA channel 1: from the IIgs data port to memory, paced by DREQ1 (each
; IIgs write); stream.s sets its destination and count for each packet.
        set_io IAR1L, HOST_DATA
        set_io IAR1H, 0
        set_io IAR1B, 0
        set_io DCNTL, DCNTL_STREAM
        ret
