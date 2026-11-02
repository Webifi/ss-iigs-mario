; OTI-087X (Oak) VGA ports and register indexes. The Oak decodes the full
; 16-bit I/O address, so use out (c) with BC set to the port.

        .ifndef VGA_INC
        .equ VGA_INC, 1

        .equ VGA_ATTR, 0x3C0
        .equ VGA_MISC_WRITE, 0x3C2
        .equ VGA_SEQ_INDEX, 0x3C4
        .equ VGA_SEQ_DATA, 0x3C5
        .equ VGA_DAC_MASK, 0x3C6        ; the Bt481 pixel mask
        .equ DAC_MASK_ALL, 0xFF         ; VGA_DAC_MASK: every pixel bit reaches the palette
        .equ DAC_MASK_NONE, 0           ; VGA_DAC_MASK: every pixel shows slot 0
        .equ VGA_DAC_READ_INDEX, 0x3C7
        .equ VGA_DAC_WRITE_INDEX, 0x3C8
        .equ VGA_DAC_DATA, 0x3C9
        .equ VGA_GC_INDEX, 0x3CE
        .equ VGA_GC_DATA, 0x3CF
        .equ VGA_CRTC_INDEX, 0x3D4
        .equ VGA_CRTC_DATA, 0x3D5
        .equ VGA_STATUS, 0x3DA
        .equ STATUS_RETRACE, 0x08       ; VGA_STATUS: the vertical retrace runs
        .equ VGA_INPUT_STATUS_0, 0x3C2  ; read: input status 0 (a write of this port is VGA_MISC_WRITE)
        .equ STATUS_SENSE, 0x10         ; VGA_INPUT_STATUS_0: the monitor sense; the Second Sight
                                        ; cable gives 1 for a VGA monitor, 0 for AppleColor RGB
; The attribute controller (VGA_ATTR): a read of VGA_STATUS resets its
; flip-flop to the index write.
        .equ ATTR_MODE_CONTROL, 0x10    ; graphics or text, colour depth
        .equ ATTR_OVERSCAN, 0x11        ; the palette slot of the border
        .equ ATTR_PANNING, 0x13         ; horizontal pel panning
        .equ ATTR_PAN_UNIT, 2           ; ATTR_PANNING counts 2 for each pixel in 256-colour mode
        .equ ATTR_PAS, 0x20             ; index bit: the palette stays on
        .equ OAK_INDEX, 0x3DE
        .equ OAK_DATA, 0x3DF

; Sequencer
        .equ SEQ_RESET, 0x00            ; 1: synchronous reset, 3: run
        .equ SEQ_CLOCKING, 0x01         ; dots a character, the dot clock divider
        .equ SEQ_MAP_MASK, 0x02         ; the planes that a CPU write reaches
        .equ SEQ_MEMORY_MODE, 0x04      ; 0x0E: chain 4 (packed bytes)
        .equ ALL_PLANES, 0x0F           ; SEQ_MAP_MASK: the four planes
        .equ VGA_PLANES, 4

; Graphics controller
        .equ GC_SET_RESET, 0x00
        .equ GC_ENABLE_SET_RESET, 0x01
        .equ GC_COLOR_COMPARE, 0x02
        .equ GC_DATA_ROTATE, 0x03
        .equ GC_READ_MAP, 0x04
        .equ GC_MODE, 0x05
        .equ GC_MISC, 0x06
        .equ GC_COLOR_DONT_CARE, 0x07
        .equ GC_BIT_MASK, 0x08
        .equ GC_MODE_256, 0x40          ; GC_MODE: the 256-colour shift mode, + the write mode
        .equ GC_WRITE_CPU, GC_MODE_256  ; GC_MODE, write mode 0: the CPU byte, through the function and the bit mask
        .equ GC_WRITE_LATCHES, GC_MODE_256 | 1 ; GC_MODE, write mode 1: each plane gets its latch (a copy of the bytes read)
        .equ GC_FUNCTION_OR, 0x10       ; GC_DATA_ROTATE: the CPU byte ORed with the latches

; CRT controller
        .equ CRTC_H_TOTAL, 0x00         ; the characters of a line - 5
        .equ CRTC_H_SHOWN_END, 0x01     ; the last character shown
        .equ CRTC_H_BLANK_START, 0x02
        .equ CRTC_H_BLANK_END, 0x03     ; bits 0-4 of the blank end (bit 5 in CRTC_H_SYNC_END)
        .equ CRTC_H_SYNC_START, 0x04
        .equ CRTC_H_SYNC_END, 0x05      ; bits 0-4 of the sync end; bit 7: bit 5 of the blank end
        .equ CRTC_V_TOTAL, 0x06         ; bits 0-7 of the lines of a picture - 2
        .equ CRTC_OVERFLOW, 0x07        ; bits 8 and 9 of the vertical counts
        .equ CRTC_PRESET_ROW, 0x08
        .equ CRTC_MAX_SCAN, 0x09        ; bit 7: each row twice; bit 6: bit 9 of the line compare;
                                        ; bit 5: bit 9 of the blank start; bits 0-4: rows of a cell - 1
        .equ CRTC_CURSOR_START, 0x0A    ; bit 5: no text cursor
        .equ CRTC_CURSOR_END, 0x0B
        .equ CRTC_START_HIGH, 0x0C
        .equ CRTC_START_LOW, 0x0D
        .equ CRTC_V_SYNC_START, 0x10    ; bits 0-7
        .equ CRTC_V_SYNC_END, 0x11      ; bits 0-3 of the sync end; bit 7 locks registers 0-7
        .equ CRTC_V_SHOWN_END, 0x12     ; bits 0-7 of the last line shown
        .equ CRTC_OFFSET, 0x13          ; the row pitch, in units of 2 groups (byte mode)
        .equ CRTC_UNDERLINE, 0x14       ; bit 6: double word addresses
        .equ CRTC_V_BLANK_START, 0x15   ; bits 0-7
        .equ CRTC_V_BLANK_END, 0x16
        .equ CRTC_MODE_CONTROL, 0x17    ; bit 7: timing on; bit 6: byte addresses
        .equ CRTC_LINE_COMPARE, 0x18    ; bits 0-7 of the split line

; Oak extended registers (index through OAK_INDEX)
        .equ OAK_MEMORY_MAP, 0x05       ; 0x19: linear 1 MB at Oak 0x100000; 0x00: VGA windows
        .equ OAK_CLOCK_SELECT, 0x06     ; the clock code of the clock chip
        .equ OAK_OVERFLOW, 0x14         ; bit 10 of the vertical counts, start address bit 16, bit 7 interlace
        .equ OAK_INTERLACE_RETRACE, 0x15 ; the odd field's retrace start when interlaced
        .equ OAK_EEPROM_CONTROL, 0x18   ; bit 2 = 0: CSEL2-0 drive the clock chip, not the EEPROM
        .equ OAK_FIFO_DEPTH, 0x20       ; the display FIFO level before a CPU access is served
        .equ OAK_EXTENDED_CRTC, 0x17
        .equ OAK_MODE_SELECT, 0x21      ; 0x04: the Oak packed pixel modes
        .equ OAK_FEATURE_SELECT, 0x22   ; bit 3: the write cache; bit 2: the 64-bit latch
        .equ OAK_READ_SEGMENT, 0x23
        .equ OAK_WRITE_SEGMENT, 0x24
        .equ OAK_COMMON_SEGMENT, 0x25
        .equ OAK_EXPAND_CONTROL, 0x30
        .equ OAK_FOREGROUND, 0x31
        .equ OAK_BACKGROUND, 0x32
        .equ OAK_PATTERN, 0x33
        .equ OAK_PIXEL_MASK, 0x34
        .equ OAK_LATCH_INDEX, 0x35
        .equ OAK_LATCH_DATA, 0x36

; vga_set: write VALUE to register INDEX behind the index port PORT (data
; port PORT+1). oak_set, gc_set, seq_set: the same for the Oak extended
; registers, the graphics controller and the sequencer.
        .macro vga_set port, index, value
        ld bc,\port
        ld a,\index
        out (c),a
        inc c
        ld a,\value
        out (c),a
        .endm

        .macro oak_set index, value
        vga_set OAK_INDEX, \index, \value
        .endm

        .macro gc_set index, value
        vga_set VGA_GC_INDEX, \index, \value
        .endm

        .macro seq_set index, value
        vga_set VGA_SEQ_INDEX, \index, \value
        .endm

        .endif
