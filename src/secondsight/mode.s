; The video mode of the game: 256 x 240 pixels, unchained 256 colours, a
; row pitch of PAGE_PITCH groups. One register table serves both monitors:
; it is the VGA mode, and set_mode first reads the cable sense and, for an
; AppleColor RGB monitor, writes the RGB values over the VGA ones. The choice
; is made before any clock or CRTC write, so a VGA signal never reaches an
; RGB monitor (mode_table.inc).
;
; Timing: the NES picture, 256 x 240, with the blanking right after it:
; the monitor scales what the signal shows, as it does for any mode. Clock
; code 3,
; 44.9 MHz (reference/clocks.md, the frequency table), halved by the
; sequencer; each 256-colour pixel takes 2 of those dots, 4 clocks.
;   VGA: 22.45 MHz dots, 89 characters of 8 dots a line: 31.53 kHz, the VGA
;     line. Each picture row shows twice: 480 of 525 lines, 60.0588 Hz.
;   AppleColor RGB: the RGB connector halves the clock again (U12): 11.2 MHz
;     dots, the same 89 characters: 15.77 kHz, the TV line. Each row shows
;     once: 240 of 262 lines, 60.1735 Hz.
; Both: MODE_SHOWN characters shown (256 pixels). The horizontal blanking
; starts right after them and ends one character before the next line's
; picture: the CRTC compares only 6 bits of the blank end, so it cannot end
; at the line total, and one character (4 pixels) of overscan in the
; backdrop colour (slot 0) is the least it leaves. The vertical blanking
; likewise leaves one line. The sync sits inside the blanking.
; Register meanings: IBM VGA technical reference (CRTC, sequencer, graphics
; controller, attribute controller), OTI-087 databook (Oak extended
; registers), Second Sight reference 14-custom-code.md ("Building a mode").
;
; Routines:
;   set_mode   the mode of the monitor that the cable sense shows

        .include "video.inc"
        .include "mode_table.inc"

        .global set_mode

; A record: operation (0 OUT, 1 IN), port low, port high, value.
        .macro out_reg port, value
        .byte 0, (\port) & 0xFF, (\port) >> 8, \value
        .endm
        .macro in_reg port
        .byte 1, (\port) & 0xFF, (\port) >> 8, 0
        .endm
; An indexed register: the index to PORT, the value to PORT + 1. LABEL, if
; given, names the value record (an RGB replacement writes its byte).
        .macro index_reg port, index, value, label
        out_reg \port, \index
        .ifnb \label
\label:
        .endif
        out_reg (\port) + 1, \value
        .endm
; An RGB replacement: VALUE over the value byte of the record LABEL.
        .macro rgb_value label, value
        .byte \value
        .word \label + 3
        .endm

        .equ RGB_PATCHES, 13            ; the rgb_value lines of mode_rgb

; The numbers that set the picture rate. The IIgs game clock runs at 4 ticks
; for each picture of the mode: src/clock.s computes its DOC timer from
; MODE_CLOCK_KHZ and MODE_VGA_PICTURE or MODE_RGB_PICTURE (the build gives
; them to it as secondsight_* symbols).
        .equ MODE_CLOCK_KHZ, 44900      ; clock code 3 (reference/clocks.md)
        .equ MODE_CHARACTERS, 89        ; the horizontal total, 8 dots each
        .equ MODE_SHOWN, 64             ; the characters shown: 256 pixels
        .equ MODE_HBLANK_END, MODE_CHARACTERS - 1 ; the latest blank end that the 6-bit compare reaches
        .equ MODE_DOT_CLOCKS, 2         ; the sequencer halves the clock
        .equ MODE_VGA_LINES, 525
        .equ MODE_RGB_LINES, 262
        .equ MODE_RGB_DIVIDE, 2         ; U12 halves the clock again on RGB
; The clock periods of one picture.
        .equ MODE_VGA_PICTURE, MODE_DOT_CLOCKS * 8 * MODE_CHARACTERS * MODE_VGA_LINES
        .equ MODE_RGB_PICTURE, MODE_RGB_DIVIDE * MODE_DOT_CLOCKS * 8 * MODE_CHARACTERS * MODE_RGB_LINES
        .global MODE_CLOCK_KHZ, MODE_VGA_PICTURE, MODE_RGB_PICTURE, STATUS_SENSE
        .if ((MODE_VGA_LINES - 2) >> 8) != 2 || ((MODE_RGB_LINES - 2) >> 8) != 1
        .error "mode_overflow and its RGB value hold bits 8-9 of the vertical totals"
        .endif

        .section .text.mode,"ax",@progbits

; ---------------------------------------------------------------------------
; set_mode: program the clock, the sequencer, the colour chip, the Oak, the
; CRT controller and the attribute controller from mode_data, with the RGB
; values of mode_rgb on an AppleColor RGB monitor.
;
; In:       nothing
; Out:      the mode is set; the attribute controller flip-flop is at the
;           index
; Changes:  AF, BC, DE, HL
; Time:     at each start and each return from the options menu
; Original: none
; ---------------------------------------------------------------------------
set_mode:
        mode_table mode, RGB_PATCHES
mode_done:
        ret

        .section .data.mode,"aw",@progbits

; The VGA table. mode_rgb replaces the bytes that differ.
mode_data:
mode_clock:
        out_reg CLOCK_VGA, 0            ; the board's pixel clock: VGA (RGB: CLOCK_RGB)
        index_reg VGA_SEQ_INDEX, SEQ_RESET, 1 ; sequencer reset while the clock changes
        index_reg VGA_SEQ_INDEX, SEQ_CLOCKING, 9 ; 8 dots a character (bit 0), the clock halved (bit 3)
        out_reg VGA_MISC_WRITE, 0xEF    ; negative syncs, clock code 3 (bits 3-2), RAM on, colour I/O ports
; Bt481 command register A: four reads of the pixel mask after a read of the
; read index open it; 0 selects 8-bit indexed pixels. Then the pixel mask.
        in_reg VGA_DAC_READ_INDEX
        in_reg VGA_DAC_MASK
        in_reg VGA_DAC_MASK
        in_reg VGA_DAC_MASK
        in_reg VGA_DAC_MASK
        out_reg VGA_DAC_MASK, 0         ; command register A: indexed pixels
        out_reg VGA_DAC_WRITE_INDEX, 0  ; closes the command register
        out_reg VGA_DAC_MASK, DAC_MASK_ALL
        index_reg OAK_INDEX, OAK_CLOCK_SELECT, 3 ; code 3, 44.9 MHz
        index_reg OAK_INDEX, OAK_MODE_SELECT, 0 ; no Oak packed modes
        index_reg OAK_INDEX, OAK_FIFO_DEPTH, 5 ; the firmware's value for its 256-colour modes
; The unchained 256-colour path (15-oak-drawing.md, "Unchained 256-color mode").
        index_reg VGA_SEQ_INDEX, SEQ_MAP_MASK, ALL_PLANES
        index_reg VGA_SEQ_INDEX, SEQ_MEMORY_MODE, 6 ; chain 4 off, odd/even off, extended memory
        index_reg VGA_GC_INDEX, GC_SET_RESET, 0
        index_reg VGA_GC_INDEX, GC_ENABLE_SET_RESET, 0
        index_reg VGA_GC_INDEX, GC_DATA_ROTATE, 0
        index_reg VGA_GC_INDEX, GC_READ_MAP, 0
        index_reg VGA_GC_INDEX, GC_MODE, GC_WRITE_CPU ; 256-colour shift, write mode 0
        index_reg VGA_GC_INDEX, GC_MISC, 5 ; graphics, the 64 KB window at $A0000
        index_reg VGA_GC_INDEX, GC_COLOR_DONT_CARE, 15
        index_reg VGA_GC_INDEX, GC_BIT_MASK, 0xFF
        index_reg OAK_INDEX, OAK_FEATURE_SELECT, 8 ; the write cache on, the 64-bit latch off
        index_reg OAK_INDEX, OAK_EXPAND_CONTROL, 0 ; no colour expansion, no pixel mask
        index_reg OAK_INDEX, OAK_READ_SEGMENT, 0
        index_reg OAK_INDEX, OAK_WRITE_SEGMENT, 0
        index_reg OAK_INDEX, OAK_OVERFLOW, 0 ; no interlace; bit 10 of each vertical count 0
        index_reg OAK_INDEX, OAK_INTERLACE_RETRACE, 0 ; not used without interlace
        index_reg OAK_INDEX, OAK_EEPROM_CONTROL, 0 ; CSEL2-0 drive the clock chip
        index_reg OAK_INDEX, OAK_EXTENDED_CRTC, 0 ; start address bits 16-18
; The CRT controller. CRTC_V_SYNC_END first: bit 7 = 0 unlocks registers 0-7.
        index_reg VGA_CRTC_INDEX, CRTC_V_SYNC_END, 0x30
        index_reg VGA_CRTC_INDEX, CRTC_H_TOTAL, MODE_CHARACTERS-5
        index_reg VGA_CRTC_INDEX, CRTC_H_SHOWN_END, MODE_SHOWN-1 ; 8 dots, 4 pixels each
        index_reg VGA_CRTC_INDEX, CRTC_H_BLANK_START, MODE_SHOWN, mode_hblank ; right after the picture
        index_reg VGA_CRTC_INDEX, CRTC_H_BLANK_END, 0x80 | (MODE_HBLANK_END & 31), mode_hblank_end ; bit 7 = 1: registers $10 and $11 read as the retrace registers, not the light pen
        index_reg VGA_CRTC_INDEX, CRTC_H_SYNC_START, 69, mode_hsync ; 1.8 us after the blank
        index_reg VGA_CRTC_INDEX, CRTC_H_SYNC_END, (80 & 31) | ((MODE_HBLANK_END >> 5) & 1) << 7, mode_hsync_end ; sync end 80 (3.9 us); blank end bit 5
        index_reg VGA_CRTC_INDEX, CRTC_V_TOTAL, (MODE_VGA_LINES-2) & 0xFF, mode_vtotal
        index_reg VGA_CRTC_INDEX, CRTC_OVERFLOW, 0x3E, mode_overflow ; bit 8 of shown (479), sync (490), blank (480), split; bit 9 of total (523)
        index_reg VGA_CRTC_INDEX, CRTC_PRESET_ROW, 0x00
        index_reg VGA_CRTC_INDEX, CRTC_MAX_SCAN, 0xC0, mode_scan ; each row twice (bit 7); bit 9 of the line compare 1 (no split)
        index_reg VGA_CRTC_INDEX, CRTC_CURSOR_START, 0x20 ; no text cursor
        index_reg VGA_CRTC_INDEX, CRTC_CURSOR_END, 0x00
        index_reg VGA_CRTC_INDEX, CRTC_START_HIGH, 0
        index_reg VGA_CRTC_INDEX, CRTC_START_LOW, 0
        index_reg VGA_CRTC_INDEX, CRTC_V_SYNC_START, 490 & 0xFF, mode_vsync ; line 490
        index_reg VGA_CRTC_INDEX, CRTC_V_SYNC_END, 0x30 | (492 & 15), mode_vsync_end ; sync end 492; registers 0-7 stay unlocked
        index_reg VGA_CRTC_INDEX, CRTC_V_SHOWN_END, 479 & 0xFF, mode_vshown ; line 479
        index_reg VGA_CRTC_INDEX, CRTC_OFFSET, PAGE_PITCH / 2
        index_reg VGA_CRTC_INDEX, CRTC_UNDERLINE, 0x00 ; no double word addresses
        index_reg VGA_CRTC_INDEX, CRTC_V_BLANK_START, 480 & 0xFF, mode_vblank ; line 480
        index_reg VGA_CRTC_INDEX, CRTC_V_BLANK_END, 524 & 0xFF, mode_vblank_end ; line 524
        index_reg VGA_CRTC_INDEX, CRTC_MODE_CONTROL, 0xC3 ; timing on, byte addresses, the CGA and Hercules address maps off
        index_reg VGA_CRTC_INDEX, CRTC_LINE_COMPARE, 0xFF ; with its bits 8 and 9 set: no split
; The attribute controller: a read of the status port resets its flip-flop.
        in_reg VGA_STATUS
        out_reg VGA_ATTR, ATTR_PAS | ATTR_MODE_CONTROL
        out_reg VGA_ATTR, 0x41          ; graphics, 8-bit colour
        out_reg VGA_ATTR, ATTR_PAS | ATTR_OVERSCAN
        out_reg VGA_ATTR, 0             ; slot 0, the backdrop
        index_reg VGA_SEQ_INDEX, SEQ_RESET, 3 ; the sequencer runs again
        .byte 0xFF                      ; the end of the table

; The AppleColor RGB values: the TV line and field, each picture row shown
; once. The horizontal counts are those of VGA (the connector halves the
; clock), with the sync of the TV line.
mode_rgb:
        rgb_value mode_clock - 2, CLOCK_RGB ; the port byte of the clock record
        rgb_value mode_hblank, MODE_SHOWN ; blank start: right after the picture
        rgb_value mode_hblank_end, 0x80 | (MODE_HBLANK_END & 31)
        rgb_value mode_hsync, 71        ; sync start: 5 us after the blank
        rgb_value mode_hsync_end, (78 & 31) | ((MODE_HBLANK_END >> 5) & 1) << 7 ; sync end 78 (5.0 us)
        rgb_value mode_vtotal, (MODE_RGB_LINES-2) & 0xFF
        rgb_value mode_overflow, 0x11   ; bit 8 of the total (260) and of the line compare
        rgb_value mode_scan, 0x40       ; each row once; bit 9 of the line compare 1 (no split)
        rgb_value mode_vsync, 243       ; sync start: line 243
        rgb_value mode_vsync_end, 0x30 | (246 & 15) ; sync end 246
        rgb_value mode_vshown, 239      ; the last shown line
        rgb_value mode_vblank, 240      ; blank start
        rgb_value mode_vblank_end, 261 & 0xFF ; blank end
