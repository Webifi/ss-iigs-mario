"""The user's ROM set. The repository holds none of these bytes.

Either source is enough. The NES file and the PlayChoice-10 set carry the
same program and the same tile art. The check is the SHA-1 of those two
parts, not of a header or of a zip.
"""

import hashlib
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROMS = ROOT / "roms"

PRG_SHA1 = "fefa1097449a3a11ebf8c6199e905996c5dc8fbd"
CHR_SHA1 = "394badaf0b0bdd0ea279a1bca89a9d9ddc00b1b5"


def _sha1(data):
    return hashlib.sha1(data).hexdigest()


def _check(part, data, expect):
    got = _sha1(data)
    if got != expect:
        raise SystemExit(f"{part} SHA-1 is {got}, expected {expect}")


def _nes(data):
    if len(data) < 16 or data[:4] != b"NES\x1a":
        return None
    prg_n = data[4]
    chr_n = data[5]
    # NES 2.0 stores extra size in the high nibbles. This game's file does
    # not use them; reject a size this reader would get wrong.
    if data[7] & 0x0C == 0x08 and (data[9] & 0x0F or data[9] >> 4):
        raise SystemExit("NES 2.0 extended sizes are not read by this build")
    prg_len = prg_n * 16384
    chr_len = chr_n * 8192
    if prg_len != 32768 or chr_len != 8192:
        return None
    need = 16 + prg_len + chr_len
    if len(data) < need:
        raise SystemExit(f"NES file is {len(data)} bytes, needs {need}")
    return data[16 : 16 + prg_len], data[16 + prg_len : need]


def _from_zip(path):
    prg = chr_ = None
    nes_name = None
    with zipfile.ZipFile(path) as zf:
        for info in zf.infolist():
            name = Path(info.filename).name
            if name == "u1sm":
                prg = zf.read(info)
            elif name == "u2sm":
                chr_ = zf.read(info)
            elif name.lower().endswith(".nes"):
                nes_name = info
        if prg is None and nes_name is not None:
            found = _nes(zf.read(nes_name))
            if found:
                prg, chr_ = found
    return prg, chr_


def _from_nes(path):
    found = _nes(path.read_bytes())
    if not found:
        return None
    return found


def load():
    """(program, tiles): the 32 KB program and the 8 KB tile art, checked.

    The colours of the picture chip are not read: they are a fact of the
    RP2C03B, written in src/secondsight/colours.s.
    """
    found = []
    if not ROMS.is_dir():
        raise SystemExit(f"no ROM folder at {ROMS}")
    for path in sorted(ROMS.iterdir()):
        if path.name.startswith(".") or path.name == "README.md":
            continue
        if path.suffix.lower() == ".zip":
            prg, chr_ = _from_zip(path)
        elif path.suffix.lower() == ".nes":
            got = _from_nes(path)
            prg, chr_ = got if got else (None, None)
        else:
            continue
        if prg is None:
            continue
        found.append((path.name, prg, chr_))
    if not found:
        raise SystemExit(
            "put the NES cartridge file or pc_smb.zip in roms/ (see roms/README.md)"
        )
    name, prg, chr_ = found[0]
    if chr_ is None:
        raise SystemExit(f"{name} has no tile art")
    for other, oprg, ochr in found[1:]:
        if oprg != prg or ochr != chr_:
            raise SystemExit(f"{name} and {other} are not the same program and tiles")
    _check("program", prg, PRG_SHA1)
    _check("tile art", chr_, CHR_SHA1)
    if len(prg) != 32768 or len(chr_) != 8192:
        raise SystemExit("program or tile art is the wrong size")
    return prg, chr_
