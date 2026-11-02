# ROM files

Put one of these into this folder. Both hold the same game program and tile
art.

- **The NES cartridge file** (`.nes`, 40,976 bytes), or a `.zip` that holds it.
- **The PlayChoice-10 set** `pc_smb.zip` (MAME). The build reads these files
  from it:

| File | Size | Contents |
|---|---|---|
| `u1sm` | 32 KB | Game program, $8000-$FFFF |
| `u2sm` | 8 KB | Tile art |

The build checks the SHA-1 of the program and of the tile art. For the NES
file it checks the data after the 16-byte header, so a different header
does not matter.
