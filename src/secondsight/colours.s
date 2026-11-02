; The 64 colours of the original's picture chip, for the colour chip of the
; card. The game always shows the RGB colours of the RP2C03B, the picture
; chip of the PlayChoice-10: 3 bits each of red, green and blue. They are a
; fact of that chip, not data of the game, so they are written here: the NES
; cartridge file holds no colours, and the build does not read the
; PlayChoice-10 palette file. The card runs its colour chip with 8 bits a
; channel (mode.s: the Bt481 in 8-bit indexed mode), so 3-bit level n is
; n x 255 / 7, rounded: 0, 36, 73, 109, 146, 182, 219, 255.
;
; dac_colours: red, green, blue of colour n at 3 x n (picture.s
; palette_commit).

        .global dac_colours

        .section .rodata.colours,"a",@progbits
dac_colours:
        .byte 109, 109, 109, 0, 36, 146, 0, 0, 219, 109, 73, 219        ; colours $00-$03
        .byte 146, 0, 109, 182, 0, 109, 182, 36, 0, 146, 73, 0         ; colours $04-$07
        .byte 109, 73, 0, 36, 73, 0, 0, 109, 36, 0, 146, 0           ; colours $08-$0B
        .byte 0, 73, 73, 0, 0, 0, 0, 0, 0, 0, 0, 0              ; colours $0C-$0F
        .byte 182, 182, 182, 0, 109, 219, 0, 73, 255, 146, 0, 255       ; colours $10-$13
        .byte 182, 0, 255, 255, 0, 146, 255, 0, 0, 219, 109, 0         ; colours $14-$17
        .byte 146, 109, 0, 36, 146, 0, 0, 146, 0, 0, 182, 109         ; colours $18-$1B
        .byte 0, 146, 146, 36, 36, 36, 0, 0, 0, 0, 0, 0              ; colours $1C-$1F
        .byte 255, 255, 255, 109, 182, 255, 146, 146, 255, 219, 109, 255    ; colours $20-$23
        .byte 255, 0, 255, 255, 109, 255, 255, 146, 0, 255, 182, 0       ; colours $24-$27
        .byte 219, 219, 0, 109, 219, 0, 0, 255, 0, 73, 255, 219        ; colours $28-$2B
        .byte 0, 255, 255, 73, 73, 73, 0, 0, 0, 0, 0, 0           ; colours $2C-$2F
        .byte 255, 255, 255, 182, 219, 255, 219, 182, 255, 255, 182, 255    ; colours $30-$33
        .byte 255, 146, 255, 255, 182, 182, 255, 219, 146, 255, 255, 73    ; colours $34-$37
        .byte 255, 255, 109, 182, 255, 73, 146, 255, 109, 73, 255, 219    ; colours $38-$3B
        .byte 146, 219, 255, 146, 146, 146, 0, 0, 0, 0, 0, 0          ; colours $3C-$3F
