# Super Mario Bros. for the Apple IIgs with Second Sight

> **Prerelease.** This build is not finished.

A port of Nintendo's *Super Mario Bros.* to the Apple IIgs with a Sequential
Systems Second Sight card. The build reads the game from the NES cartridge file
or from the PlayChoice-10 arcade set. The game runs as native 65816 and Z180
code.

This repository contains no ROM data. Everything the game needs is made from
your own ROM files when you build.

## What you need to play

- A ROM 03 Apple IIgs, or a ROM 01 with a memory card of 256 KB or more
- A Second Sight card in slot 3, with a VGA monitor or an AppleColor RGB
  monitor on the card
- A hard disk device for the disk image (see the list under Build)
- Optional: a game-port joystick, a J13 keyboard (ROM 00 and ROM 01), or a
  SNES MAX adapter with one or two SNES or NES pads

## Build

You need:

- Python 3.12 or newer, as `python3`
- cc65 (`ca65` and `ld65`; macOS: `brew install cc65`)
- GNU binutils for the `z80-elf` target (`z80-elf-as`, `z80-elf-ld`, `z80-elf-objcopy`
  and `z80-elf-nm`)
- make
- a network connection for the first build, which installs the Python packages
  into `.venv/`

1. Put your ROM file into `roms/` (see `roms/README.md`).
2. Run `./build.sh`.

The disk images are in `build/game-disk/`. The code in each name (HASH, for
example `mario-6dc1d6.hdv`) changes when the game changes, so you can tell
builds apart:

- `mario-HASH.hdv`: a ProDOS volume, for a CFFA3000, a FloppyEmu or another
  SmartPort hard disk, a MicroDrive/Turbo, a BOOTI or an emulator
- `mario-HASH-scsi.hda`: the same volume with an Apple partition map, for an Apple
  SCSI card with a BlueSCSI, ZuluSCSI or SCSI2SD
- `debug.sym`: the debug symbols of this build, every IIgs and Second Sight
  address, for emulator debug runs (format in `scripts/debug_symbols.py`)

## Play

Boot the IIgs from the SSMARIO disk. When it has loaded, the game shows its
title screen and then the demo, like the NES. Press 5 (Select) to pick a 1 or
2 player game, then 1 (Start). Player 2 plays Luigi.

### Default controls

| Action | Player 1 (Mario) | Player 2 (Luigi) |
|---|---|---|
| Move | W A S D, I J K L, arrow keys, keypad 8 4 5 6 | Joystick |
| A (jump, swim) | Control | Shift, keypad Enter, joystick button 1 |
| B (run, fire) | Option, Command | Joystick button 2 |
| Start | 1 | 2 |
| Select | 5 | 6 |

Press Esc for the options menu. Esc cannot be changed.

The keys work on the ADB keyboard and on a J13 keyboard. On a J13 keyboard,
Option and Command are the joystick buttons, so use them on the ADB keyboard.

SNES pads (on a SNES MAX adapter): pad one is player 1, pad two is player 2.
The D-pad moves, B jumps, Y runs, and Start and Select work as on the NES. On
an NES pad, A jumps and B runs. Set the adapter's slot in the DEVICES menu
first.

### Options menu

Press Esc during play to pause and open the menu. The up and down arrows
choose, Return selects, and Esc goes back. Esc on the first page returns to
the game. A joystick or a pad works too: move to choose, press a button to
select.

- **CONTROLS**: change the keys for PLAYER 1, PLAYER 2 and the MENU KEY. Pick
  an action, then CHANGE its key, ADD another key, or REMOVE one. After CHANGE
  or ADD, press the new key or button. NEXT BINDING steps through the keys of
  an action that has more than one. BOTH KEYBOARDS picks whether a key works
  on the ADB keyboard, the J13 keyboard, or both.
- **DEVICES**: Return or the right arrow changes a setting.
  - J13 PLAY: turn on to play with a J13 keyboard (default off). The menu
    always works with it.
  - SNES MAX SLOT: the adapter's slot (1, 2, 4, 5 or 6). Default: none.
  - RECHECK JOYSTICK: look for the joystick again, for example after you plug
    one in.
  - JOYSTICK PLAYER: which player uses the joystick (default player 2).
  - RESTORE DEFAULT BINDINGS: puts all keys back as in the table above.
- **SOUND**: music and effects volume (0 to 15, default 15). Pick a level with
  the arrows and press Return.
- **SAVE**: saves all settings to the disk. Without SAVE, your changes are lost
  when you restart or switch off the IIgs.
- **RESUME**: back to the game.

The game runs at 60.06 frames a second on VGA and 60.17 on AppleColor RGB,
close to the NES's 60.10.

## Folders

| Folder | Contents |
|---|---|
| `src/` | 65816 source for the IIgs, and the formats that both programs share |
| `src/game/` | The game logic, ported to the 65816 |
| `src/secondsight/` | Z180 source for the Second Sight card |
| `bootloader/` | The boot block and file reader that replace ProDOS (see its README) |
| `scripts/` | The build: ROM reading, art, sound, card data, disk image |
| `roms/` | Your ROM file (not in the repository) |
| `build/` | Build output (not in the repository) |
