; The IIgs side of the Second Sight card in slot 3: its host registers, the
; firmware commands that the boot loader and the options menu send, and the
; VGA registers that they set through the firmware. src/game.s and
; src/boot.s include this file.
;
; Each access to $C0B0-$C0B7, a read or a write, raises an event on the
; card: the Z180's INT1, which is also the DMA request of its DMA channel 1.
; During a DMA phase each write there is one data byte, and RDY holds the
; 65816 until the card has taken the byte before. A read of $C0B8 raises
; no event, so the code polls the handshake byte there.

SS_COMMAND      = $E0C0B0       ; write: a command byte
SS_DATA_OUT     = $E0C0B1       ; write: parameters and bulk data to the card
SS_DATA_IN      = $E0C0B2       ; read: results from the card (each read loads the next byte)
SS_BURST        = $E0C0B7       ; top of $C0B0-$C0B7: each write there is one packet byte
SS_BURST_SIZE   = 8             ; the bytes of $C0B0-$C0B7: one burst of pushes
SS_HANDSHAKE    = $E0C0B8       ; read: the handshake byte of the card (no event)

; Firmware commands
SS_GET_STATUS   = $00           ; 13 reads: one dummy, then SS_STATUS_SIZE bytes
SS_SET_MODE     = $01           ; mode, SS_EMULATION or SS_NATIVE; completion SS_DONE or SS_MODE_FAILED
SS_UPLOAD_DATA  = $02           ; SS_UPLOAD_PARAMETERS bytes, then the data
SS_SCREEN_OFF   = $04           ; no parameters, no completion: the handshake byte does not change
SS_RUN_CODE     = $09           ; CBR, CBAR, BBR, address (2); no completion
SS_SET_SHADOW   = $0B           ; SS_SHADOW_ALL or SS_SHADOW_NONE
SS_SET_VGA_REG  = $0C           ; SS_VGA_REG_PARAMETERS bytes

; Handshake values
SS_PHASE_DONE   = $00           ; the phase is finished
SS_READY        = $01           ; the card waits for bytes, or has bytes to read
SS_DONE         = $A5           ; SetMode finished
SS_MODE_FAILED  = $A6           ; SetMode: the monitor has no such mode

; GetStatus: the bytes after the dummy read
SS_STATUS_SIZE  = 12
SS_SIGNATURE    = 0             ; "GSVGA"
SS_SIGNATURE_SIZE = 5
SS_STATUS_COUNT = 5             ; the count of the bytes that follow: SS_STATUS_BYTES
SS_STATUS_BYTES = 6
SS_SENSE        = 10            ; the card's input status 0 ($3C2): the monitor sense (secondsight_STATUS_SENSE)
.assert SS_SIGNATURE+SS_SIGNATURE_SIZE = SS_STATUS_COUNT, error

; SetMode
SS_MODE_TEXT40  = $FC           ; 40 x 24 text: the firmware has it for both monitors
SS_EMULATION    = 0             ; the firmware draws the Apple screen
SS_NATIVE       = 1             ; native VGA mode: the firmware draws nothing

; SetShadow
SS_SHADOW_ALL   = $00           ; copy the Apple video writes
SS_SHADOW_NONE  = $04           ; stop all copies

; UploadData: flag, destination (3), length (3), IIgs source (3, ignored)
SS_UPLOAD_PARAMETERS = 10
SS_UPLOAD_LINEAR = 1            ; flag: a 24-bit card offset: $000000-$07FFFF video RAM, $100000-$11FFFF SRAM

; SetVGAReg: index port (2), index, data port (2), value
SS_VGA_REG_PARAMETERS = 6

; The firmware's 40-column text screen in video RAM (mode SS_MODE_TEXT40):
; two plane addresses for each cell, the character at the even one in
; plane 0 (the text mode does not show plane 0 at the odd one),
; TEXT_COLUMNS cells for each row.
SS_TEXT40       = $000000
SS_TEXT40_CELL  = 2             ; the plane addresses of a cell

; Card VGA ports, register indexes and values for SS_SET_VGA_REG. The card
; code uses the same names (src/secondsight/include/vga.inc).
VGA_SEQ_INDEX   = $03C4
VGA_SEQ_DATA    = $03C5
VGA_GC_INDEX    = $03CE
VGA_GC_DATA     = $03CF
SEQ_MAP_MASK    = $02           ; the planes that a CPU write reaches
ALL_PLANES      = $0F           ; SEQ_MAP_MASK: the four planes
CHARACTER_PLANE = $01           ; SEQ_MAP_MASK: plane 0, the characters of the text mode
SEQ_MEMORY_MODE = $04
SEQ_PLANAR      = $06           ; SEQ_MEMORY_MODE: extended memory, odd/even off, chain 4 off:
                                ; each CPU address is one byte of each plane that SEQ_MAP_MASK selects
GC_MODE         = $05
GC_WRITE_MODE_0 = $00           ; GC_MODE: write mode 0, read mode 0, no odd/even, no 256-colour shift
