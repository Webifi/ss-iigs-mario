; The name-table ring (ring.s): its shape, for the code that reads it.

        .ifndef RING_INC
        .equ RING_INC, 1

        .include "packet_layout.inc"    ; RING_COLUMNS, RING_ROWS: the ring of the screen records
        .equ RING_STRIDE, 0x800         ; ring_palettes - ring_tiles: whole 256-byte pages
        .equ DIRTY_ROW_BYTES, RING_COLUMNS / 8 ; a dirty map: a bit for each cell
        .equ DIRTY_MAP_SIZE, DIRTY_ROW_BYTES * TILE_ROWS

        .endif
