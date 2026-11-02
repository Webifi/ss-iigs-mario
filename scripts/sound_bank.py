"""Build the IIgs sound-chip data used by the game's sound model.

scripts/assets.py calls build() to create wave tables and volume settings
for src/sound.s. The two square channels and triangle play these waves on
DOC oscillators. The noise sequence is made at startup by src/sound.s; this
module reserves its place in DOC RAM. Menu sound levels use the volume tables.
"""

import math

import numpy as np

CPU = 1789772.7  # the NES CPU clock (NTSC), Hz
# The four sound channels and the clock use five oscillators. With only
# five enabled, the louder music clipped after the board's filter. The DOC
# output averages its N + 2 slots, so 26 enabled oscillators reduce each
# channel to one quarter of its five-oscillator level. The unused oscillators
# are halted and silent. At 26, the four channels at their maximum registers
# average under 0.11 of one slot's full swing.
DOC_VOICES = 26  # the enabled DOC oscillators (src/sound.inc and src/clock.s take it from sound_bank.inc)
DOC_SLOT_RATE = 894886  # the DOC's oscillator slots a second: 7,159,090 Hz / 8
SCAN_RATE = DOC_SLOT_RATE / (DOC_VOICES + 2)  # each voice is read this often, Hz
# Limit harmonics at the highest pitch in each octave. The board filter is
# about -3 dB near 8.5 kHz and -10 dB at 10.7 kHz. A DOC table read can
# hold or skip bytes; the table size and limit keep resulting images above
# IMAGE_FLOOR.
HARMONIC_LIMIT = 11000.0  # Hz: the highest harmonic at the top pitch of a table
IMAGE_FLOOR = 20000.0  # Hz: the lowest image of a held or skipped byte
assert SCAN_RATE - HARMONIC_LIMIT >= IMAGE_FLOOR
OCTAVES = range(3, 11)  # k: periods 2^k .. 2^(k+1) - 1
MIX_LEVELS = 16  # the options menu levels 0-15 (linear amplitude level/15)
DAC_STEPS = 32  # the sample channel's level, in steps of 4 (src/sound.s)

# The pulse sequences of the four duty settings, one step per eighth of a
# cycle (NES sound unit). Duty 3 is duty 1 turned over: src/sound.s plays it
# with the duty 1 tables, which sound the same.
DUTIES = ((0, 1, 0, 0, 0, 0, 0, 0), (0, 1, 1, 0, 0, 0, 0, 0), (0, 1, 1, 1, 1, 0, 0, 0))
TRIANGLE = tuple(range(15, -1, -1)) + tuple(range(16))  # the 32 steps

# DOC RAM: the noise in the first half, the waves from WAVES_DOC, the clock's
# page at the top (src/clock.s CLOCK_PAGE).
NOISE_DOC = 0x0000
NOISE_SIZE = 0x8000
WAVES_DOC = 0x8000
CLOCK_DOC = 0xFF00


def pulse_level(v):
    """The NES mixer's output of one square at level V (the other at 0)."""
    return 0.0 if v == 0 else 95.88 / (8128.0 / v + 100.0)


def tnd(t, n, d):
    """The NES mixer's triangle, noise and sample output."""
    x = t / 8227.0 + n / 12241.0 + d / 22638.0
    return 0.0 if x == 0 else 159.79 / (1.0 / x + 100.0)


def knee_volume(register):
    """The DOC's effective volume for volume REGISTER on a ROM 01 or ROM 03
    board: a 1N914 diode (Is 2.5 nA, n 1.75) before the DOC's reference input
    takes its drop off the volume voltage (5 V full scale, 1 kOhm load)."""
    low, high = 0.0, (5 * register / 256) / 1000
    for _ in range(64):
        mid = (low + high) / 2
        if mid * 1000 + 1.75 * 0.025852 * math.log1p(mid / 2.5e-9) > 5 * register / 256:
            high = mid
        else:
            low = mid
    return 256 * ((low + high) / 2) * 1000 / 5


KNEE = [knee_volume(r) for r in range(256)]


def volume_register(effective):
    """The register whose effective volume is nearest to EFFECTIVE."""
    return min(range(256), key=lambda r: abs(KNEE[r] - effective))


def band_limited(steps, harmonics, length):
    """One cycle of the step wave STEPS (equal steps), with harmonics 1 to
    HARMONICS and its mean, at LENGTH points."""
    steps = np.asarray(steps, dtype=float)
    m = len(steps)
    n = np.arange(1, harmonics + 1)[:, None]
    j = np.arange(m)[None, :]
    # The Fourier coefficient of each harmonic: each step's integral.
    coefficients = (steps * (np.exp(-2j * np.pi * n * j / m) - np.exp(-2j * np.pi * n * (j + 1) / m))).sum(axis=1)
    coefficients /= 2j * np.pi * n[:, 0]
    phase = np.arange(length) / length
    wave = np.full(length, steps.mean())
    wave += 2 * (coefficients[:, None] * np.exp(2j * np.pi * n * phase[None, :])).real.sum(axis=0)
    return wave


# Each table holds one wave cycle and covers periods 2^k through 2^(k+1)-1.
# Tables for a channel share phase, so octave or duty changes do not click.
def octave_tables(steps, cycles_per_period):
    """The band-limited tables of a channel whose pitch is
    CPU / (CYCLES_PER_PERIOD x (P + 1)), one per octave."""
    tables = []
    for k in OCTAVES:
        top = CPU / (cycles_per_period * (2**k + 1))
        bottom = CPU / (cycles_per_period * 2 ** (k + 1))
        harmonics = max(1, int(HARMONIC_LIMIT // top))
        length = 256
        while (length - harmonics) * bottom < IMAGE_FLOOR or length < 2 * harmonics + 2:
            length *= 2
        tables.append(band_limited(steps, harmonics, length))
    return tables


def centered(levels):
    """LEVELS moved so that their highest and lowest are equally far from 0,
    and scaled to a jump of 1 between them."""
    low, high = min(levels), max(levels)
    return [(v - (low + high) / 2) / (high - low) for v in levels]


def quantize(wave, scale):
    """DOC samples: 1 to 255 around 128 (0 would stop the voice)."""
    samples = np.rint(128 + wave * scale).astype(int)
    assert samples.min() >= 1 and samples.max() <= 255
    return bytes(samples.tolist())


def build(host):
    # The waves. One scale for all squares and one for the triangle: the
    # largest peak (with the band limit's overshoot) is 127.
    pulses = [octave_tables(centered(d), 16) for d in DUTIES]
    shape = [tnd(t, 0, 0) for t in TRIANGLE]  # the mixer's curve bends the steps
    triangles = octave_tables(centered(shape), 32)
    pulse_scale = 127 / max(np.abs(t).max() for duty in pulses for t in duty)
    triangle_scale = 127 / max(np.abs(t).max() for t in triangles)
    noise_scale = 254  # src/sound.s writes the noise as 128 - 127 and 128 + 127: a jump of 254

    # Their place in DOC RAM: each table at a multiple of its size, the
    # largest first.
    tables = [(f"PULSE_{s}_{i}", quantize(t, pulse_scale)) for s, duty in enumerate(pulses) for i, t in enumerate(duty)]
    tables += [(f"TRIANGLE_{i}", quantize(t, triangle_scale)) for i, t in enumerate(triangles)]
    image = bytearray()
    lines = []
    for name, data in sorted(tables, key=lambda entry: -len(entry[1])):
        at = WAVES_DOC + len(image)
        assert at % len(data) == 0, name
        image += data
        size_code = int(math.log2(len(data))) - 8
        lines.append(f"{name.replace('_', '_PAGE_', 1)} = ${at >> 8:02X}")
        lines.append(f"{name.replace('_', '_SIZE_', 1)} = {size_code}            ; {len(data)} bytes")
    assert WAVES_DOC + len(image) <= CLOCK_DOC
    waves = host.blob_at(bytes(image), "sound_waves")

    # The volume registers. A channel's DOC wave has a jump of SCALE samples
    # where the NES channel's output has a jump of LEVEL; the register gives
    # the jump LEVEL x K / SCALE in the DOC's effective volume (the knee).
    # K puts the loudest channel at register 255.
    def effective(level, scale, k):
        return k * level / scale

    loudest = max(pulse_level(15) / pulse_scale, (tnd(15, 0, 0) - tnd(0, 0, 0)) / triangle_scale, tnd(0, 15, 0) / noise_scale)
    k = KNEE[255] / loudest
    mixes = [level / (MIX_LEVELS - 1) for level in range(MIX_LEVELS)]
    pulse = bytes(volume_register(effective(pulse_level(v), pulse_scale, k) * m) for m in mixes for v in range(16))
    triangle = bytes(
        volume_register(effective(tnd(15, 0, 4 * q) - tnd(0, 0, 4 * q), triangle_scale, k) * m)
        for m in mixes
        for q in range(DAC_STEPS)
    )
    noise = bytes(
        volume_register(effective(tnd(0, v, 4 * q) - tnd(0, 0, 4 * q), noise_scale, k) * m)
        for m in mixes
        for q in range(DAC_STEPS)
        for v in range(16)
    )
    volumes = host.blob_at(pulse + triangle + noise, "sound_volumes")

    host.write(
        "sound_bank.inc",
        "; Generated by scripts/sound_bank.py: the DOC data of the sound unit model.\n"
        f"DOC_VOICES = {DOC_VOICES}                ; the enabled oscillators: the sound unit's 4, the idle ones, the clock last\n"
        f"SOUND_WAVES = {waves.label}            ; host data: the wave tables, as DOC RAM from SOUND_WAVES_DOC\n"
        f"SOUND_WAVES_DOC = ${WAVES_DOC:04X}\n"
        f"SOUND_WAVES_SIZE = ${len(image):04X}\n"
        f"NOISE_PAGE = ${NOISE_DOC >> 8:02X}             ; the noise: {NOISE_SIZE} bytes (src/sound.s makes it)\n"
        f"; The volume registers: [menu level 0-15][...]\n"
        f"SOUND_PULSE_VOLUMES = {volumes.label}       ; [level][channel level 0-15]\n"
        f"SOUND_TRIANGLE_VOLUMES = {volumes.label}+{len(pulse)} ; [level][sample level / 4]\n"
        f"SOUND_NOISE_VOLUMES = {volumes.label}+{len(pulse) + len(triangle)} ; [level][sample level / 4][channel level]\n"
        "; The wave tables: their DOC page and their size code (256 << code bytes).\n"
        "; PULSE_s_k: duty 12.5% (s 0), 25% (1), 50% (2); octave k - 3.\n" + "\n".join(lines) + "\n"
    )
