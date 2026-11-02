; The video memory layout and the drawing constants of the card program.
;
; Unchained 256-colour mode: one CPU address in the VGA window is one group
; of four neighbouring pixels, one pixel in each plane (map mask bit q =
; pixel 4 x group + q). In write mode 1 a read loads the four planes into
; the latches and a write stores them: one LDI copies four pixels.
;
; Video RAM addresses here are groups: the CPU address in the VGA window
; plus 0x10000 for each Oak segment (OAK_READ_SEGMENT, OAK_WRITE_SEGMENT).
; secondsight.ld places the areas (page_0, page_1, status_copies,
; sprite_slots) and the fitter places the BG tile art.

        .ifndef VIDEO_INC
        .equ VIDEO_INC, 1

        .include "second_sight.inc"
        .include "vga.inc"
        .include "z180.inc"

; ---- The picture -----------------------------------------------------------
; The original's picture: 256 x 240 pixels, 32 x 30 tiles of 8 x 8.
        .equ SCREEN_ROWS, 240           ; pixel rows
        .equ GROUP_PIXELS, 4            ; the pixels of a group: one in each plane
        .equ TILE_ROWS, 30              ; tile rows of the name tables
        .equ VISIBLE_TILES, 33          ; tile columns that a pan of 1-3 pixels shows

; ---- The pages --------------------------------------------------------------
; Each page is a forward-moving buffer: world group g of pixel row y is at
; page_origin + PAGE_PITCH x y + g. The start address moves forward as the
; picture scrolls, so a column is drawn one time and stays in place.
; PAGE_PITCH is at least two groups wider than the 66 groups that a pan
; shows; 72 keeps a sprite drawn up to 24 pixels right of the picture off
; every visible cell of the row below.
        .equ PAGE_PITCH, 72             ; groups of a row (CRTC $13 = 36)
        .equ SCROLL_ROOM, 2048          ; groups of scroll before a page starts again at its base
        .equ PAGE_GROUPS, SCREEN_ROWS * PAGE_PITCH + SCROLL_ROOM
        .equ TILE_PITCH, 8 * PAGE_PITCH ; groups from one tile row to the next

; ---- The status bar ---------------------------------------------------------
; Name-table rows 0-3 stay in place while the rest scrolls (the original
; splits the picture at sprite 0). The card keeps four copies of these 32
; pixel rows, each shifted right by one pan value (0-3 pixels), and copies
; the one that matches the pan into the page on each picture.
        .equ STATUS_TILE_ROWS, 4
        .equ STATUS_ROWS, 8 * STATUS_TILE_ROWS
        .equ STATUS_GROUPS, STATUS_ROWS * PAGE_PITCH

; ---- The sprite art -----------------------------------------------------------
; A slot holds one sprite tile in one horizontal flip, in palette 0, at the
; four pixel alignments: 4 x 8 rows x 3 groups (sprites.s ORs the palette in
; as it draws). A vertical flip reads the rows in reverse order. Slots never
; cross an 8K-group window, so one BBR value shows a whole slot in the bank
; area. Every key has its slot from the start.
        .equ SPRITE_KEYS, 2 * 256       ; each tile, unflipped and flipped
        .equ SLOT_ROW_GROUPS, 3
        .equ SLOT_ALIGN_GROUPS, 8 * SLOT_ROW_GROUPS ; one alignment
        .equ SLOT_GROUPS, 4 * SLOT_ALIGN_GROUPS
        .equ WINDOW_GROUPS, 0x2000      ; the 8 KB bank area shows 8K groups
        .equ SLOTS_PER_WINDOW, WINDOW_GROUPS / SLOT_GROUPS
        .equ SPRITE_SLOTS, (SPRITE_KEYS + SLOTS_PER_WINDOW - 1) / SLOTS_PER_WINDOW * SLOTS_PER_WINDOW

; ---- The BG tile art ----------------------------------------------------------
; Each background tile in each palette: 8 rows of 2 groups, row after row.
; Cell (palette p, tile t) starts 16 x (256 p + t) groups after tile_art.
        .equ TILE_ART_GROUPS, 16

; ---- The MMU windows while the card draws -----------------------------------
; The bank area (ART_WINDOW, 8 KB) shows the art, common area 1
; (PAGE_WINDOW, 16 KB) shows the page. BBR or CBR = base + 2 x (the 8K-group
; window of the VGA window): physical = logical + base x 4 KB.
        .equ ART_WINDOW, 0xA000
        .equ PAGE_WINDOW, 0xC000
        .equ ART_BBR_BASE, (VGA_WINDOW - ART_WINDOW) >> 12
        .equ PAGE_CBR_BASE, (VGA_WINDOW - PAGE_WINDOW) >> 12

        .endif
