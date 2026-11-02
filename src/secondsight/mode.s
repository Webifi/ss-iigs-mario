; The video mode of the game: 256 x 240 pixels, unchained 256 colours, a
; row pitch of PAGE_PITCH groups. One register table serves both monitors:
; it is the VGA mode, and set_mode first reads the cable sense and, for an
; AppleColor RGB monitor, writes the RGB values over the VGA ones. The choice
; is made before this table writes the clock or CRTC (mode_table.inc). The
; choice does not describe the signal present before the table is applied.
;
; Intended timing: standard monitor timing, with the NES picture, 256 x 240, framed
; in the backdrop colour (overscan, slot 0) as the NTSC NES frames it.
; The table writes clock code 0 to the VGA miscellaneous output, then code 3
; to the Oak clock-select register. The rates below use code 0; verify the
; resulting clock before treating them as measured rates.
;   VGA: the VESA 640 x 480 at 60 Hz timing (VESA DMT v1.0 rev 13, p. 20):
;     clock code 0, 25.175 MHz, lines of 800 dots
;     (100 characters, 31.469 kHz), 525 lines a picture (59.94 Hz), syncs
;     negative, H sync 96 dots after an 8-dot front porch and an 8-dot right
;     border, V sync on lines 490-491. Each 256-colour pixel takes 2 dots
;     (8-bit pixels, as VGA mode 13h; the sequencer does not halve the
;     clock), so the picture is 512 dots of the
;     640-dot window: 64 dots of backdrop on each side (the NES draws 15
;     pixels before its picture and after it). Each picture row shows
;     twice: lines 0-479. Below them the NES's 2 lines of backdrop (4
;     lines); then blank to the end of the picture, as the NES has no border
;     above (nesdev.org/wiki/NTSC_video).
;   AppleColor RGB: the RGB connector halves the clock (U12): the same 800
;     dots take 63.56 us, the NTSC line (15.734 kHz). 262 lines (60.05 Hz),
;     each row once: lines 0-239, 2 lines of backdrop below, V sync on lines
;     245-247 as the NES; the H sync 7 characters (4.4 us, NTSC 4.7 us).
; The registers follow the IBM rules: the blank and retrace start registers
; hold the first character or line of the signal; the horizontal blank end
; is the start plus the width in 6 bits, the horizontal retrace end in 5
; bits, the vertical blank end the last blanked line in 8 bits, the vertical
; retrace end the line after the pulse in 4 bits (IBM VGA XGA Technical
; Reference, pp. 2-57 to 2-73).
; Register meanings: IBM VGA technical reference (CRTC, sequencer, graphics
; controller, attribute controller), OTI-087 databook (Oak extended
; registers).
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
        .equ MODE_CLOCK_KHZ, 25175      ; clock code 0: the VESA 640 x 480 dot clock
        .equ MODE_CHARACTERS, 100       ; the horizontal total, 8 dots each: the VESA 800-dot line
        .equ MODE_SHOWN, 64             ; the characters shown: 256 pixels
        .equ MODE_BORDER, 8             ; 64 dots of backdrop each side: the picture in the middle of the 640 dots
        .equ MODE_HBLANK_START, MODE_SHOWN + MODE_BORDER + 1 ; after the VESA 8-dot right border
        .equ MODE_HBLANK_END, MODE_CHARACTERS - MODE_BORDER - 1 ; 18 characters of blank (VESA), then the 8-dot left border
        .equ MODE_VGA_HSYNC, MODE_HBLANK_START + 1 ; after the VESA 8-dot front porch
        .equ MODE_VGA_HSYNC_END, MODE_VGA_HSYNC + 12 ; 96 dots
        .equ MODE_RGB_HSYNC, MODE_HBLANK_START + 2 ; 1.3 us front porch
        .equ MODE_RGB_HSYNC_END, MODE_RGB_HSYNC + 7 ; 4.4 us
        .if MODE_HBLANK_END - MODE_HBLANK_START != 18
        .error "the VESA horizontal blank is 18 characters"
        .endif
        .equ MODE_DOT_CLOCKS, 1         ; one clock a dot: the sequencer does not halve it
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
        index_reg VGA_SEQ_INDEX, SEQ_CLOCKING, 1 ; 8 dots a character (bit 0), the clock not halved (bit 3 = 0)
        out_reg VGA_MISC_WRITE, 0xE3    ; negative syncs, clock code 0 (bits 3-2), RAM on, colour I/O ports
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
        index_reg OAK_INDEX, OAK_CLOCK_SELECT, 0 ; clock code 0: bits 1-0 are the misc output's bits 3-2 (OTI-087 p. 35)
                                        ; output's bits 3-2 (OTI-087 databook p. 35), so both say 0
        index_reg OAK_INDEX, OAK_MODE_SELECT, 0 ; no Oak packed modes
        index_reg OAK_INDEX, OAK_FIFO_DEPTH, 5 ; the firmware's value for its 256-colour modes
; The unchained 256-colour path.
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
        index_reg VGA_CRTC_INDEX, CRTC_H_BLANK_START, MODE_HBLANK_START, mode_hblank ; after the right border
        index_reg VGA_CRTC_INDEX, CRTC_H_BLANK_END, 0x80 | (MODE_HBLANK_END & 31), mode_hblank_end ; bit 7 = 1: registers $10 and $11 read as the retrace registers, not the light pen
        index_reg VGA_CRTC_INDEX, CRTC_H_SYNC_START, MODE_VGA_HSYNC, mode_hsync
        index_reg VGA_CRTC_INDEX, CRTC_H_SYNC_END, (MODE_VGA_HSYNC_END & 31) | ((MODE_HBLANK_END >> 5) & 1) << 7, mode_hsync_end ; blank end bit 5
        index_reg VGA_CRTC_INDEX, CRTC_V_TOTAL, (MODE_VGA_LINES-2) & 0xFF, mode_vtotal
        index_reg VGA_CRTC_INDEX, CRTC_OVERFLOW, 0x3E, mode_overflow ; bit 8 of shown (479), sync (490), blank (484), split; bit 9 of total (523)
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
        index_reg VGA_CRTC_INDEX, CRTC_V_BLANK_START, 484 & 0xFF, mode_vblank ; line 484: 4 lines of bottom border
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
        rgb_value mode_hblank, MODE_HBLANK_START ; blank start: after the right border
        rgb_value mode_hblank_end, 0x80 | (MODE_HBLANK_END & 31)
        rgb_value mode_hsync, MODE_RGB_HSYNC
        rgb_value mode_hsync_end, (MODE_RGB_HSYNC_END & 31) | ((MODE_HBLANK_END >> 5) & 1) << 7
        rgb_value mode_vtotal, (MODE_RGB_LINES-2) & 0xFF
        rgb_value mode_overflow, 0x11   ; bit 8 of the total (260) and of the line compare
        rgb_value mode_scan, 0x40       ; each row once; bit 9 of the line compare 1 (no split)
        rgb_value mode_vsync, 245       ; sync start: line 245, as the NES
        rgb_value mode_vsync_end, 0x30 | (248 & 15) ; sync end 248: lines 245-247, as the NES
        rgb_value mode_vshown, 239      ; the last shown line
        rgb_value mode_vblank, 242      ; blank start: 2 lines of bottom border, as the NES
        rgb_value mode_vblank_end, 261 & 0xFF ; blank end
