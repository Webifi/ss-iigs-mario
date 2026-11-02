/* The memory map of the Second Sight program (Z180), for GNU ld.

   The card program keeps the firmware alive: it never writes the firmware's
   vectors and handlers (SRAM $0000-$03FF, $0C00-$1FFF) or its fonts and
   mode records (SRAM $A000-$CFFF), and it leaves the first 32 KB of video
   RAM to the firmware's text screen. The options menu then needs no copy of
   the card in IIgs memory: the card puts the firmware's renderers back from
   the EPROM and returns to the firmware, which shows the Apple text page.

   Addresses
   - The VMA of an output section is its Z180 logical address. The LMA is
     its load address: load_sram + the physical SRAM address, or a linear
     video RAM byte address (group x 4 + plane, 0x000000-0x0FFFFF).
   - The program image runs at logical $2000-$9FFF. The disk loads it into
     SRAM bank 1 ($12000-$19FFF). That range is where the card copies the
     Apple's auxiliary hires and Super Hi-Res pages, so the image stays only
     while the IIgs writes none of them: the IIgs code never writes bank $E1
     $2000-$9FFF, and it keeps the shadow of those pages off (src/boot.s
     SHADOW_GRAPHICS), so its own banks 0 and 1 never reach them.
   - RunCode starts the program with the MMU of game_* below: logical
     $2000-$BFFF is then physical $12000-$1BFFF, so the image runs where it
     loaded. The entry copies the image to bank 0 ($02000-$09FFF) and sets
     run_cbar: logical $0000-$9FFF is then common area 0, physical bank 0,
     and the code goes on in the copy with no jump.
   - While the game runs, the bank area $A000-$BFFF (BBR) and common area 1
     $C000-$FFFF (CBR) show two parts of video RAM: the bank area the art,
     common area 1 the page that the card draws.
   - Logical $2000-$73FF: code, constants and the asset data of the fitter.
     $7400 up to the stack: the variables. $0400-$0BFF: the receive buffers.

   Loading
   - An output section with data loads every byte from its start to its end.
   - An output section of variables only (NOLOAD) loads nothing; the entry
     clears it.

   The options menu (menu.s)
   - The card copies its variables (state_save__start to state_save__end)
     into SRAM bank 1 at menu_save, puts the firmware's renderers back from
     the EPROM and returns to the firmware. On the way back the entry copies
     the image and the variables back into bank 0.

   Free space
   - scripts/secondsight_fit.py puts the asset sections into the free spaces
     below: .common (FIT_COMMON) in the image, .vram into free video RAM
     (FIT_VRAM). Each free space NAME gives:
       fit_NAME__start, fit_NAME__end  its load addresses [start, end)
       fit_NAME__label                 the label of a record at its start
       fit_NAME__kinds                 the kinds of sections that it takes
   - The Makefile links twice: the first link (fitting/placements.ld parks the
     asset sections) gives the free space; the fitter writes placements.ld for
     the final link. */

load_sram = 0x100000;           /* load address of SRAM byte 0 */

/* The program image: its run range in bank 0, and where the disk loads it. */
image__run = 0x2000;
image__end = 0xA000;
image__load = load_sram + 0x12000;
image__size = image__end - image__run;

/* SRAM bank 1 $C000-$FFFF is the only part of bank 1 that no firmware part
   ever writes (second-sight-reference reference/z180-memory-map.md, "SRAM
   ownership"). It holds what must outlive the options menu besides the image:
   the variables that the menu saves ($C000-$DFFF) and the pattern tables
   ($E000-$FFFF, fit_bank1 below). */
menu_save = 0x1C000;            /* physical: bank 1 $C000-$DFFF */
menu_save__limit = 0x2000;
pattern_tables = 0x1E000;       /* physical: bank 1 $E000-$FFFF, two 4 KB pages */

/* The MMU. RunCode (the IIgs, src/game.s) gives game_cbar, game_bbr and
   game_cbr: common area 0 $0000-$1FFF, the bank area $2000-$BFFF at physical
   $12000-$1BFFF (BBR $10), common area 1 $C000-$FFFF (CBR $84, not used).
   run_cbar: common area 0 $0000-$9FFF, the bank area $A000-$BFFF, common
   area 1 $C000-$FFFF. */
game_cbar = 0xC2;
game_bbr = 0x10;
game_cbr = 0x84;
run_cbar = 0xCA;
art_window = 0xA000;            /* the bank area: 8 KB of video RAM (the art) */

/* Video RAM, in groups (the CPU address in the VGA window, plus 0x10000 for
   each Oak segment). A group is four pixels, one in each plane.
   - Groups 0-8191 (the first 32 KB): the firmware's text screen.
   - page_0, page_1: the two display pages (page.s): 240 rows of
     PAGE_PITCH groups, plus the scroll room.
   - The BG tile art: placed by the fitter in fit_vram_tiles.
   - status_copies: the status bar at each pan of 0-3 pixels (status.s).
   - sprite_slots: the sprite art (sprites.s), a slot for each key, in
     8K-group windows of SLOTS_PER_WINDOW slots. */
firmware_text__groups = 0x2000;
page_0 = firmware_text__groups;
page_1 = page_0 + PAGE_GROUPS;
pages__end = page_1 + PAGE_GROUPS;
status_copies = 0x10000;
sprite_slots = 0x14000;
sprite_slots__end = sprite_slots + SPRITE_SLOTS / SLOTS_PER_WINDOW * 0x2000;
sprite_slot_windows = (sprite_slots__end - sprite_slots) / 0x2000;

/* The kinds of asset sections (scripts/secondsight_fit.py). */
FIT_RECORD = 0x01;      /* banked data read through the bank area: stays in one 4 KB page */
FIT_COMMON = 0x10;      /* data that the CPU reads at its logical address */
FIT_VRAM = 0x20;        /* video RAM */

SECTIONS
{
  /* The receive buffers of the packets (stream.s), in bank 0 $0400-$0BFF:
     the Apple text page copy, which the game turns off. DMA channel 1 fills
     one while the card draws from the other. The menu does not keep them:
     the firmware shows its text page there. */
  .packets 0x0400 (NOLOAD) : {
    *(.packets.buffer_0)
    *(.packets.buffer_1)
  }
  ASSERT(. <= 0x0C00, "the receive buffers reach $0C00")

  /* ---- The program image: logical $2000-$9FFF ---- */

  .text image__run : AT(image__load) {
    *(.text.entry)
    *(.text.menu)                       /* below $6000: menu.s restores the firmware's code over $6000-$9FFF */
    *(.text*)
  }

  .rodata . : AT(LOADADDR(.text) + SIZEOF(.text)) {
    *(.rodata*)
  }

  fit_image__start = LOADADDR(.rodata) + SIZEOF(.rodata);
  fit_image__end = image__load + (state_save__start - image__run);
  fit_image__label = load_sram + ADDR(.rodata) + SIZEOF(.rodata); /* the image runs at its load address less (image__load - load_sram - image__run) */
  fit_image__kinds = FIT_COMMON;

  /* The variables: the menu keeps them, the entry clears them at start. */
  state_save__start = 0x7400;
  .data state_save__start : AT(image__load + (state_save__start - image__run)) {
    *(.data*)
  }
  .vars . (NOLOAD) : {
    *(.vars*)
  }
  state_save__end = .;
  ASSERT(state_save__end - state_save__start <= menu_save__limit, "the variables do not fit the menu save area")
  ASSERT(menu_save + menu_save__limit <= pattern_tables, "the menu save area reaches the pattern tables")


  /* The stack: the last bytes of the image. */
  stack__top = image__end;
  ASSERT(state_save__end <= stack__top - 0x200, "the variables reach the stack")

  INCLUDE placements.ld
  /DISCARD/ : { *(.text*) *(.rodata*) *(.data*) *(.bss*) }
}

/* The free video RAM for the fitter: the BG tile art (64 KB) goes here. */
fit_vram_tiles__start = 4 * (((pages__end + 0x1FFF) / 0x2000) * 0x2000);
fit_vram_tiles__end = 4 * status_copies;
fit_vram_tiles__label = fit_vram_tiles__start;
fit_vram_tiles__kinds = FIT_VRAM;

/* SRAM bank 1 $1E000-$1FFFF: the pattern tables (scripts/tiles.py), each one
   4 KB page, read through the bank area. The status bar reads chr_bg during
   the whole game, after an options menu too, so the tables cannot be in bank 1
   $1A000-$1BFFF: each start of the firmware's Super Hi-Res emulation copies
   its code there (second-sight-reference reference/z180-memory-map.md). */
fit_bank1__start = load_sram + pattern_tables;
fit_bank1__end = load_sram + 0x20000;
fit_bank1__label = fit_bank1__start;
fit_bank1__kinds = FIT_RECORD;

/* The values that the hand-written sources use. */
/* The bytes of the DMA addresses of entry.s. */
image_source__low = (image__load - load_sram) & 0xFF;
image_source__high = ((image__load - load_sram) >> 8) & 0xFF;
image_source__bank = (image__load - load_sram) >> 16;
menu_save__low = menu_save & 0xFF;
menu_save__high = (menu_save >> 8) & 0xFF;
menu_save__bank = menu_save >> 16;
vars__start = ADDR(.vars);
/* The high bytes of the two receive buffers XOR: the other buffer (stream.s). */
stream_other = (packet_buffer_0 >> 8) ^ (packet_buffer_1 >> 8);
vars__size = state_save__end - vars__start;
state_save__size = state_save__end - state_save__start;
/* The BBR value that shows a pattern table's 4 KB page at the bank area. */
chr_sprites__bbr = ((chr_sprites - load_sram) >> 12) - (art_window >> 12);
chr_bg__bbr = ((chr_bg - load_sram) >> 12) - (art_window >> 12);
/* The tile art: its first group in segment 0. */
tile_art__group = tile_art >> 2;
/* The Oak segment of the status copies; the first group of the sprite slots / 256. */
status_copies__segment = status_copies >> 16;
sprite_slots__page = sprite_slots >> 8;

/* Checks of the layout that the code needs. */
ASSERT(image__run == 0x2000 && game_bbr == 0x10, "the image must run where it loads under the RunCode MMU (entry.s)")
ASSERT(LOADADDR(.rodata) + SIZEOF(.rodata) <= fit_image__end, "the code and constants reach the variables")
ASSERT(menu_end <= 0x6000, "the options menu entry must run below the firmware's code (menu.s)")
ASSERT(stack__top <= 0xA000, "the program's bank 0 use must stay below the bank area")
ASSERT(pages__end <= 0x10000, "the pages leave video RAM segment 0")
ASSERT((sprite_slots & 0x1FFF) == 0 && (sprite_slots__end & 0x1FFF) == 0, "the sprite slots start and end on an 8K-group window")
ASSERT(status_copies + 4 * STATUS_GROUPS <= sprite_slots, "the status copies reach the sprite slots")
ASSERT((status_copies & 0xFFFF) == 0, "status.s draws the copies from group 0 of their segment")
ASSERT(tile_art + 0x10000 <= 0x40000 && (tile_art & 0x7FFF) == 0, "page.s reads the tile art in segment 0 from 8K-group windows")
ASSERT((chr_sprites & 0xFFF) == 0 && (chr_bg & 0xFFF) == 0, "a pattern table starts a 4 KB page (sprites.s expand_tile)")
ASSERT((sprite_opacity & 0xFF) == 0 && (bg_opacity & 0xFF) == 0, "the opacity tables start a 256-byte page")
ASSERT(packet_buffer_0 == 0x0400 && packet_buffer_1 == 0x0800, "stream_arm makes the token from bit 3 of the buffer's high byte")
ASSERT(sprite_slot_windows * SLOTS_PER_WINDOW >= SPRITE_SLOTS, "the sprite slots do not fit their windows")
