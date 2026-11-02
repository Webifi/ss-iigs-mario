#!/bin/sh
# Build the Apple IIgs + Second Sight disk image of Super Mario Bros. from the ROM files in roms/.
set -e
cd "$(dirname "$0")"
for tool in ca65 ld65; do
  command -v "$tool" >/dev/null 2>&1 || { echo "$tool not found. Install cc65 (macOS: brew install cc65)." >&2; exit 1; }
done
for tool in z80-elf-as z80-elf-ld z80-elf-objcopy z80-elf-nm; do
  command -v "$tool" >/dev/null 2>&1 || { echo "$tool not found. Install GNU binutils for the z80-elf target." >&2; exit 1; }
done
command -v make >/dev/null 2>&1 || { echo "make not found. Install GNU make." >&2; exit 1; }
python3 -c 'import sys; sys.exit(sys.version_info < (3, 12))' 2>/dev/null || { echo "python3 is not Python 3.12 or newer. Install it (macOS: brew install python) and put it first on PATH." >&2; exit 1; }
if ! cmp -s requirements.txt .venv/requirements.txt 2>/dev/null; then
  python3 -m venv --clear .venv
  .venv/bin/python -m pip install --quiet -r requirements.txt
  cp requirements.txt .venv/requirements.txt
fi
make -j"$(getconf _NPROCESSORS_ONLN)" PYTHON=.venv/bin/python
echo "Disk images:"
ls -1 build/game-disk/mario-*.hdv build/game-disk/mario-*-scsi.hda
