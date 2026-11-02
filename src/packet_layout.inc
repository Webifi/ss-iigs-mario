; The update packet from the IIgs to the Second Sight card. The IIgs
; (src/packet.s) writes it after each game update; the card (src/secondsight/
; stream.s, picture.s) draws from it. Both assemblers (ca65 and GNU as) read
; this file, so it holds only decimal NAME = value lines.
;
; The IIgs builds the packet in plain byte order. Its PEI sender puts the two
; bytes of each word on the wire high byte first, so the card receives each
; byte pair swapped and swaps the pairs back before it reads the packet.
;
; The packet: the header, PKT_SPRITES sprite entries, then the write list.

; The header: offsets from the start of the packet.
PKT_SIZE            = 0         ; word: the bytes after this word
PKT_FLAGS           = 2         ; the PF_* flags of the picture
PKT_SPRITES         = 3         ; the sprite entries that follow the header, 0-64
PKT_SCROLL          = 4         ; word: the world X of the left edge of the picture
PKT_HEADER          = 6         ; the bytes of the header

; PKT_FLAGS: what the picture shows (the original's picture chip mask and its
; status split).
PF_BACKGROUND       = 1         ; the background is on: else the whole picture shows the backdrop colour
PF_SPRITES          = 2         ; the sprites are on
PF_STATUS           = 4         ; name-table rows 0-3 stay in place (the split at sprite 0)
PF_MENU             = 8         ; the options menu: the card keeps its state and gives the screen to its firmware (src/secondsight/menu.s)

; A sprite entry: the original's sprite list format.
SPRITE_Y            = 0         ; the top row - 1
SPRITE_TILE         = 1         ; the tile of the sprite pattern table
SPRITE_ATTR         = 2         ; bits 0-1 palette, 5 behind the background, 6 x flip, 7 y flip
SPRITE_X            = 3         ; the left pixel
SPRITE_ENTRY        = 4
SPRITE_LIMIT        = 64        ; the entries of the original's sprite list
; SPRITE_ATTR bits.
ATTR_PALETTE        = 3         ; the sprite palette, 0-3
ATTR_BEHIND         = 32        ; behind the background: shows only over pen 0 of the background
ATTR_BEHIND_BIT     = 5         ; its bit number
ATTR_FLIP_X         = 64        ; mirrored left to right
ATTR_FLIP_Y         = 128       ; mirrored top to bottom

; The screen records. The background is a ring of RING_ROWS x RING_COLUMNS
; cells, each a tile and a palette (0-3); the palette is that of the 2 x 2
; square of cells that holds the cell. The original's name table 0 is ring
; columns 0-31, name table 1 columns 32-63. A record is its kind, then its
; fields, one byte each; REC_END ends the records of a packet.
RING_ROWS           = 30
RING_COLUMNS        = 64
METATILE_ROWS       = 13        ; REC_COLUMN: metatile rows 0-12 are cell rows 4-29
METATILE_FIRST_ROW  = 4         ; the cell row of metatile row 0
REC_END             = 0
REC_CELLS           = 1         ; row, column, count (1-32), then count tiles: across, in the row
REC_SQUARE          = 2         ; row, column (both even), then 4 tiles: top left, top right, bottom left,
                                ; bottom right; the square's palette stays
REC_COLUMN          = 3         ; metatile column (0-31: ring columns 2c and 2c + 1), then METATILE_ROWS
                                ; metatiles: each one's 4 tiles from the card's metatile table, its palette
                                ; its bits 7-6
REC_PALETTES        = 4         ; square row (0-14), square column (0-31), count (1-32), then count palettes
                                ; (0-3): across
REC_COLOURS         = 5         ; first entry (0-31), count (1-32), then count colours (0-63); entries 16,
                                ; 20, 24 and 28 are the same as 0, 4, 8 and 12
REC_CLEAR           = 6         ; the tile: every cell gets it, with palette 0
REC_CELLS_HEAD      = 4         ; the bytes of a REC_CELLS record before its tiles
REC_SQUARE_SIZE     = 7
REC_COLUMN_SIZE     = 2 + METATILE_ROWS
REC_PALETTES_HEAD   = 4
REC_COLOURS_HEAD    = 3
REC_CLEAR_SIZE      = 2

; The receive buffers of the card (secondsight.ld .packets) hold the largest
; packet with its size word.
PACKET_AREA         = 1024
