# Boot loader

A boot block and a file reader that start a program from a ProDOS volume
without ProDOS. The volume stays a normal ProDOS volume: disk tools see and
copy its files.

boot0 reads blocks the same way as the boot block of ProDOS: through the
ProDOS block driver of the boot slot, before any system is loaded. A device
that boots a ProDOS disk boots boot0 too, for example:

- an Apple SCSI card with a BlueSCSI, ZuluSCSI or SCSI2SD (use the image
  with the Apple partition map, `apm()`)
- a CFFA3000, a MicroDrive/Turbo, a BOOTI
- a FloppyEmu or another SmartPort device, in hard disk or 3.5-inch mode
- the IIgs 3.5-inch drive

It does not boot from a 5.25-inch drive.

| File | Contents |
|---|---|
| `boot0.s` | Block 0. Loads one file to $2000 and runs it |
| `boot0.cfg` | The ld65 memory map of block 0 |
| `prodos_read.s` | Opens and reads files, for the program that boot0 starts |
| `prodos_volume.py` | Builds the volume, and the image for an Apple SCSI card |

## boot0.s

The firmware loads block 0 to $0800 and starts it with X = slot * 16. boot0
finds the boot file in the volume directory, loads it to $2000 and jumps
there in emulation mode with X = the ProDOS unit number of the boot drive.

- The boot file is a seedling or a sapling of at most $9E00 bytes, in the
  volume directory. `Volume.boot(name)` writes its name into the block.
- boot0 uses $0800-$0DFF and zero page $42-$49 until the jump.
- It is 6502 code, so the boot file can start on any Apple II.

## prodos_read.s

`.include` it in the boot file. It reads seedling, sapling and tree files
of the volume directory as a byte stream. One file is open at a time.

The program defines `PR_ZP` (4 zero-page bytes) and two 512-byte buffers,
`PR_DBUF` and `PR_IBUF`. Call it in emulation mode with D = 0.

| Call | In | Out |
|---|---|---|
| `pr_init` | A = the boot unit (X at $2000) | `pr_unit`, `pr_driver` |
| `pr_open` | A/Y = the name: a length byte, then the name in upper case | carry set: not found; else `pr_storage`, `pr_key`, `pr_eof`, mark 0 |
| `pr_read` | `pr_dest`, `pr_count` | `pr_count` = the bytes read (fewer at the end); carry set: disk error |
| `pr_call` | $42 command, $43 unit, $44 buffer, $46 block | the block driver |

A program writes a block with `pr_call` (command 2). For a one-block file,
`pr_key` after `pr_open` is the block that holds its data.

## prodos_volume.py

Assemble block 0 first: `ca65 boot0.s` and `ld65 -C boot0.cfg` give the 512
bytes of boot0.bin.

```python
blocks = fitted_blocks([len(code)])  # just large enough for the files
volume = Volume("NAME", blocks, boot0_bin_bytes)
volume.install("GAME.SYSTEM", code, 0xFF, 0x2000)
volume.boot("GAME.SYSTEM")
image = bytes(volume.data)        # .hdv / .po; 1600 blocks for an 800K disk
scsi = apm(image, "NAME")         # for an Apple SCSI card
```
