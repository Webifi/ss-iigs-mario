# Super Mario Bros. for the Apple IIgs with Second Sight

> **Prerelease.** This build is not finished.

A port of Nintendo's *Super Mario Bros.* to the Apple IIgs with a Sequential
Systems Second Sight card. The build reads the game from the NES cartridge file
or from the PlayChoice-10 arcade set. The game runs as native 65816 and Z180
code.

This repository contains no ROM data. Everything the game needs is made from
your own ROM files when you build.

## What you need to play

- An Apple IIgs with RAM in banks $02-$05: a ROM 03, or a ROM 01 with a
  memory card of 256 KB or more
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

The disk images are in `build/game-disk/`, each just large enough for the
game and its settings file. HASH in their names is a short hash of the
volume (6 hex digits), so each build of other game data has its own name:

- `mario-HASH.hdv`: a ProDOS volume, for a CFFA3000, a FloppyEmu or another
  SmartPort hard disk, a MicroDrive/Turbo, a BOOTI or an emulator
- `mario-HASH-scsi.hda`: the same volume with an Apple partition map, for an Apple
  SCSI card with a BlueSCSI, ZuluSCSI or SCSI2SD
- `debug.sym`: the debug symbols of this build, every IIgs and Second Sight
  address, for emulator debug runs (format in `scripts/debug_symbols.py`)

## Play

Start the IIgs from the SSMARIO volume. The game loads and shows its title,
and after a short wait the demo plays, as on the NES. Select chooses a 1 or 2
player game, and Start starts it. In a 2 player game, player 2 plays Luigi.

### Default controls

| Action | Player 1 (Mario) | Player 2 (Luigi) |
|---|---|---|
| Move | W A S D, I J K L, arrow keys, keypad 8 4 5 6 | Joystick |
| A (jump, swim) | Control | Shift, keypad Enter, joystick button 1 |
| B (run, fire) | Option, Command | Joystick button 2 |
| Start | 1 | 2 |
| Select | 5 | 6 |

Esc opens the options menu. You cannot change the Esc key.

The keyboard keys work on the ADB keyboard and on a J13 keyboard. Option and
Command work only on the ADB keyboard: on a J13 keyboard the two Apple keys
are the joystick buttons.

SNES pads on a SNES MAX adapter: pad one is player 1, pad two is player 2.
The direction pad moves, B is A (jump), Y is B (run), and Start and Select are
the buttons of that player. On an NES pad, A jumps and B runs. Set the slot
of the adapter in the DEVICES menu first.

### Options menu

Push Esc during the game to stop it and open the menu. Use the up and down
arrows to choose, and Return to select. Esc goes back one page, and Esc on
the first page goes back to the game. A joystick or a pad also works: its
directions are the arrows, and its buttons are Return.

- **CONTROLS**: the bindings of PLAYER 1, PLAYER 2 and the MENU KEY. Choose an
  action, then CHANGE (the next key or device input replaces the binding),
  ADD (the next input is one more binding), REMOVE, NEXT BINDING, or BOTH
  KEYBOARDS (the binding is for the ADB keyboard, the J13 keyboard, or both).
  There is space for 64 bindings.
- **DEVICES**: Return or the right arrow changes a value.
  - J13 PLAY: ON makes the game read the J13 keyboard during play (default
    OFF). The menu always reads it.
  - SNES MAX SLOT: the slot of the adapter (1, 2, 4, 5 or 6). The default is
    none.
  - RECHECK JOYSTICK: look for the joystick again.
  - JOYSTICK PLAYER: move the joystick and its bindings to the other player
    (default player 2).
  - RESTORE DEFAULT BINDINGS: all bindings go back to the table above.
- **SOUND**: MUSIC VOLUME and EFFECTS VOLUME (0 to 15, default 15). Choose a
  level with the arrows, and set it with Return.
- **SAVE**: write all the settings to the file SSMARIO.CONFIG on the SSMARIO
  volume. The game reads them at the next start. Without SAVE, the changes
  stay only until you switch off or restart the IIgs.
- **RESUME**: go back to the game.

The game reads the monitor type from the card when it starts, and its speed
follows the picture rate of that monitor's mode: 60.06 frames a second on
VGA and 60.17 on AppleColor RGB, near the NES's 60.10.

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
