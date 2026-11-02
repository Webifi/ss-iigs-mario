"""The songs and the sound effect tables of the original's sound program, in
the forms that the port's sound program reads (src/game/sound_program.s).

The original keeps its music in its own byte format (document 08, sections
8.2-8.4): song headers that share bytes, parts that share bytes, note values
that index a period table, length bytes and packed bytes that index a tempo
table, and 0 bytes with a meaning for each channel. This build reads every
song the way the original's music step does, frame by frame from the song's
first frame until its square 2 part ends (08 section 8.7), and writes what
each channel then does in the port's own form: the frames of each note, its
period as the sound unit model takes it, and for the triangle and the drums
the values of each note's stores. The song rules that depend only on the song
(its volume table, the triangle's hold rule, whether the drums play) are
applied here, per song. No code that runs in the game reads the original's
song format.

ROM tables read (PROGRAM_BASE = $8000 is offset 0 of the program):

  SONG_HEADER_OFFSETS $F90D  49 bytes: song n's header is at $F90D + byte n - 1
                             (08 8.2). A header is 6 bytes: the tempo row, the
                             data address (low, high), the triangle, square 1
                             and noise part offsets from that address.
  NOTE_PERIODS        $FF00  51 entries of 2 bytes: period bits 8-10, bits 0-7;
                             indexed by the note value 0, 2, ... $64 (08 8.4).
  NOTE_LENGTHS        $FF66  48 bytes: six tempo rows of 8 lengths in frames (8.4).
  the song data       $F9B8-$FEFC, at the header addresses (8.3).
  CASTLE_END_VOLUMES  $FF96  4 square control values (8.5).
  AREA_VOLUMES        $FF9A  8 square control values (8.5).
  WATER_VOLUMES       $FFA2  40 square control values (8.5).
  STOMP_VOLUMES       $F3B1  14 square control values (08 7.2, table 10).
  EXTRA_LIFE_NOTES    $F4D4  6 note values (7.3).
  POWERUP_GRAB_NOTES  $F4DA  30 note values, 27 of them read (7.3, 12 item 12).
  GROW_NOTES          $F4F8  32 note values, $04 a rest (7.3).
  BRICK_NOISE_PERIODS $F62B  16 noise period indexes (7.4).
  BOWSER_FLAME_VOLUMES $FFCA 32 noise control values (7.4).
  BRICK_NOISE_VOLUMES $FFEA  16 noise control values (7.4).

The values that the build writes are in the forms of the sound unit model's
calls (src/sound.inc): a period is a word (11 bits for the squares and the
triangle); a square or noise control is the duty (bits 7-6), the constant
volume flag (bit 4) and the level (bits 3-0); a triangle control is the hold
(bit 7) and the linear reload value (bits 6-0); a noise period is the short
sequence flag (bit 7) and the period index (bits 3-0); a length is a length
index 0-31.

Forms written. The data that the sound program reads every frame of an effect
or a note is in bank 0 (host.game_blob_at, absolute addressing); the songs
are in a data bank (host.blob_at, long addressing):

  note_periods (bank 0): 51 words, the period of each note value: the word at
      byte offset N is the period of note value N (the effects name their
      notes by the original's note values; the rest $04 has the period 0).
  stomp_volumes (bank 0): 14 bytes, square controls; entry i at the effect's
      count i + 1.
  extra_life_periods (bank 0): 6 words, entry i at the count 8 x (i + 1).
  powerup_grab_periods (bank 0): 27 words, entry i at the count 2 x (i + 1);
      the original's last 3 notes are never read (08 12 item 12).
  grow_periods (bank 0): 32 words, entry i at the step i; 0 is a rest.
  brick_noise_periods, brick_noise_volumes (bank 0): 16 bytes each, the noise
      period and control of the burst i = count / 2.
  bowser_flame_volumes (bank 0): 32 bytes, the noise control of i - 1 for
      i = count / 2 from 32 down to 1.

  event_songs (data bank): 9 words: the SongRecord offset in song_lists of
      the event song of command bit b (b = 0-7) at the normal tempo, then of
      the time-out song at the fast tempo (08 8.10).
  area_songs (data bank): 8 pairs of words: by area command bit, the record
      at the normal tempo, then at the fast tempo.
  ground_parts (data bank, size GROUND_PARTS_SIZE): one pair of words for
      each ground part, songs 17 to 49 in order (08 8.9): normal, fast.
  song_lists (data bank): the SongRecords, then the part lists. Offset 0 is
      a record, so 0 never names a list:
    SongRecord, 11 bytes (src/game/sound_program.s .struct SongRecord):
      +0  square 2 list      +2  square 1 list, 0 = the song has no square 1 part
      +4  triangle list, 0 = the song ends in its first frame
      +6  drum list, 0 = the song plays no drums (08 8.13 step 1)
      +8  volume_base: the offset in music_volumes of the song's volume table
      +9  volume_start: the volume step of a note's first frame (the table's
          size: its first frame reads the byte after the table, 08 12 item 1)
      +10 volume_steps: 0 = the song has no volume steps (the death, the
          alternate game over and the silence songs, 08 8.5); its notes still
          set the step to volume_start
    Square part (square 2 and square 1), one SquareNote of 3 bytes per note:
      frames (1-255), period (a word; 0 = a rest). frames 0: square 2: the
      song ends here (the original's 0 byte); square 1: the death sound
      setting, one byte (the original's 0 byte in a square 1 part, 08 8.3).
    Triangle part, one TriangleNote of 4 bytes per note: frames, period (0 =
      a rest), the triangle control after the note's stores (08 8.7).
    Drum list, one DrumBeat of 4 bytes per beat: frames, the noise control,
      the noise period, the length index; frames 0: the beats start again
      from the list's start (one byte).

  music_volumes (bank 0): the original's three volume tables as they lie in
      the program, castle end (4), area (8), water (40), then the byte after
      the water table (the first byte of the flame's table): 53 square
      controls. A square's volume step (0-40) indexes the table of the song
      that plays from its volume_base. The first frame of a note reads the
      byte after its table (08 12 item 1). A step that an effect kept from a
      song with a longer table reads past the shorter table of the next song
      into the tables after it, as in the original; the steps reach at most
      40, so every read stays inside these 53 bytes.
"""

PROGRAM_BASE = 0x8000

# The song headers (08 8.2, table 10).
SONG_HEADER_OFFSETS = 0xF90D
SONG_NUMBERS = 49  # song numbers 1-49 (08 8.1)
HEADER_ROW, HEADER_DATA, HEADER_TRIANGLE, HEADER_SQUARE1, HEADER_NOISE = 0, 1, 3, 4, 5

# The song numbers (08 8.1): event songs 1 + the command bit, area songs 9 + the
# command bit, the ground song's parts 17-49 (8.9).
FIRST_EVENT_SONG = 1
FIRST_AREA_SONG = 9
FIRST_GROUND_PART = 17
COMMAND_BITS = 8
TIME_OUT_BIT = 6  # event $40: the time-out song, at the fast tempo (08 8.10)
GROUND_AREA = 0x01  # the area command of the ground song

# The note tables (08 8.4).
NOTE_PERIODS = 0xFF00
NOTE_VALUES = 51  # entries 0, 2, ... $64
NOTE_LENGTHS = 0xFF66
FAST_TEMPO = 8  # the length table offset after a time-out command (08 8.10)
NOTE_LENGTH_BITS = 0x07  # the length index of a length byte (8.3)

# The bytes of the song data (08 8.3).
SONG_END = 0x00  # square 2: the end; square 1: the death sound setting; noise: the loop
LENGTH_BYTE = 0x80  # square 2 and the triangle: bit 7 set is a length byte
PACKED_NOTE = 0x3E  # square 1: the note of a packed byte; noise: the beat kind

# The song rules that depend on the song (08 8.5, 8.7, 8.13): command bits.
NO_VOLUME_EVENTS = 0x91  # death, alternate game over, silence: no volume table
CASTLE_END_EVENT = 0x08  # the castle end table (checked first)
AREA_TABLE_AREAS = 0x7D  # these area songs read the area table; the others the water table
HOLD_EVENTS = 0x6E  # the triangle hold rule: game over, victory, castle end, end of level, time-out
HOLD_AREAS = 0x0A  # and the water and castle songs
HOLD_FRAMES = 18  # a note of 18 frames or more holds
TRIANGLE_HOLD = 0xFF  # the triangle control of a held note: hold, reload 127
TRIANGLE_CASTLE_END = 0x0F  # a shorter note of the castle end song: 15 quarter clocks
TRIANGLE_COUNT = 0x1F  # at a length byte, and a shorter note of the other songs: 31
DRUM_AREAS = 0xF3  # the drums play for these area songs only

# The drum beats (08 8.13): the stores of each beat kind.
BEAT_LONG = 0x30
BEAT_LOW = 0x20
BEAT_SHORT = 0x10  # bit 4 set and not BEAT_LONG
HIT_CONTROL = 0x1C  # constant volume 12
SILENT_CONTROL = 0x10  # constant volume 0
LONG_HIT = (HIT_CONTROL, 0x03, 11)  # control, period index 3, length index 11: five frames
LOW_HIT = (HIT_CONTROL, 0x0C, 3)  # period index 12, length index 3: one frame
SHORT_HIT = (HIT_CONTROL, 0x03, 3)
NOISE_PERIOD_FORM = 0x8F  # the short sequence flag and the period index of a noise period
LENGTH_INDEX_SHIFT = 3  # a length store's index is in its bits 7-3

# The volume tables (08 8.5, 12 item 1): address and entries, one after the
# other in the program. The first-frame value of each is the byte after it;
# the byte after the water table is the first of the flame's.
CASTLE_END_VOLUMES = (0xFF96, 4)
AREA_VOLUMES = (0xFF9A, 8)
WATER_VOLUMES = (0xFFA2, 40)

# The effect tables (08 section 7, table 10): address and entries read.
STOMP_VOLUMES = (0xF3B1, 14)
EXTRA_LIFE_NOTES = (0xF4D4, 6)
POWERUP_GRAB_NOTES = (0xF4DA, 27)  # 30 bytes; the count reads 27 (08 12 item 12)
GROW_NOTES = (0xF4F8, 32)
BRICK_NOISE_PERIODS = (0xF62B, 16)
BRICK_NOISE_VOLUMES = (0xFFEA, 16)
BOWSER_FLAME_VOLUMES = (0xFFCA, 32)

# The port's forms (the module header): sizes and markers.
SONG_RECORD_SIZE = 11
NO_LIST = 0  # a SongRecord list offset: no part
MARKER = 0  # a frames byte of 0: the end, the death sound setting or the loop
FRAMES_MAX = 255
PERIOD_MAX = 0x7FF


class Program:
    """The 32 KB program: bytes by their original address."""

    def __init__(self, program):
        assert len(program) == 0x8000
        self.data = program

    def byte(self, address):
        return self.data[address - PROGRAM_BASE]

    def bytes(self, address, count):
        return [self.byte(address + i) for i in range(count)]

    def header(self, number):
        """Song NUMBER's header: (row, data address, triangle, square 1, noise offsets)."""
        at = SONG_HEADER_OFFSETS + self.byte(SONG_HEADER_OFFSETS + number - 1)
        h = self.bytes(at, 6)
        data = h[HEADER_DATA] | h[HEADER_DATA + 1] << 8
        return h[HEADER_ROW], data, h[HEADER_TRIANGLE], h[HEADER_SQUARE1], h[HEADER_NOISE]

    def period(self, note):
        """The period of NOTE in the model's form: 0 for a rest. The original's
        note store skips a note whose low byte is 0 (08 8.4); only the rest $04
        is such a note, and its whole entry is 0."""
        assert note % 2 == 0 and note < 2 * NOTE_VALUES, f"note ${note:02X}"
        high, low = self.bytes(NOTE_PERIODS + note, 2)
        assert low != 0 or high == 0, f"note ${note:02X}: a rest with high bits"
        period = high << 8 | low if low else 0
        assert period <= PERIOD_MAX
        return period


def word(value):
    return [value & 0xFF, value >> 8]


def packed_length_index(value):
    """The length index of a packed square 1 or noise byte (08 8.3): bit 0 x 4
    + bit 7 x 2 + bit 6."""
    return (value & 1) << 2 | (value >> 7) << 1 | (value >> 6) & 1


class Song:
    """One song number at one tempo, as the original plays it from its first
    frame (08 8.6-8.8): the lists of its four channels."""

    def __init__(self, program, number, extra, event, area):
        self.program = program
        self.row, self.data, self.triangle_offset, self.square1_offset, self.noise_offset = program.header(number)
        self.extra = extra
        self.event = event  # the song's snd_event_music and snd_area_music
        self.area = area
        self.number = number

    def byte(self, offset):
        # Every offset of the original is 8 bits from the data address (08 8.3).
        return self.program.byte(self.data + (offset & 0xFF))

    def length_index(self, index):
        """The note_lengths index of length index INDEX (0-7) at the song's tempo."""
        return self.row + self.extra + index

    def frames(self, index):
        frames = self.program.byte(NOTE_LENGTHS + self.length_index(index))
        assert 1 <= frames <= FRAMES_MAX
        return frames

    def square2(self):
        """Square 2 (08 8.7): its notes until the 0 byte, and the song's frames."""
        notes, offset, frames, length = [], 0, 0, None
        while True:
            value = self.byte(offset)
            offset += 1
            if value == SONG_END:
                return notes, frames
            if value & LENGTH_BYTE:
                length = self.frames(value & NOTE_LENGTH_BITS)
                value = self.byte(offset)
                offset += 1
            # Every square 2 part starts with a length byte: no note takes a
            # length from the song before.
            assert length is not None, f"song {self.number}: square 2 starts without a length"
            notes.append((length, self.program.period(value)))
            frames += length

    def square1(self, song_frames):
        """Square 1 (8.7): its notes that start before the song ends, with each
        0 byte (the death sound setting) as a marker before the next note."""
        if not self.square1_offset:
            return None
        events, offset, frames = [], self.square1_offset, 0
        while frames < song_frames:
            value = self.byte(offset)
            offset += 1
            if value == SONG_END:
                events.append(None)
                continue
            length = self.frames(packed_length_index(value))
            events.append((length, self.program.period(value & PACKED_NOTE)))
            frames += length
        return events

    def triangle(self, song_frames):
        """The triangle (8.7): its notes that start before the song ends, each with
        the triangle control that its stores leave. The part starts at the
        header's triangle offset with no test: offset 0 plays square 2's bytes
        (the underground song, 08 12 item 7)."""
        notes, offset, frames, length = [], self.triangle_offset, 0, None
        control = None
        hold_rule = bool(self.event & HOLD_EVENTS or self.area & HOLD_AREAS)
        while frames < song_frames:
            value = self.byte(offset)
            offset += 1
            # A 0 byte would store control 0 and leave the count at 0 (08 12
            # item 8): no song reaches one.
            assert value != SONG_END, f"song {self.number}: the triangle reaches a 0 byte"
            if value & LENGTH_BYTE:
                length = self.frames(value & NOTE_LENGTH_BITS)
                control = TRIANGLE_COUNT
                value = self.byte(offset)
                offset += 1
                assert value != SONG_END, f"song {self.number}: the triangle reaches a 0 byte"
            assert length is not None and control is not None, f"song {self.number}: the triangle starts without a length"
            if hold_rule:
                control = (
                    TRIANGLE_HOLD if length >= HOLD_FRAMES
                    else TRIANGLE_CASTLE_END if self.event & CASTLE_END_EVENT
                    else TRIANGLE_COUNT
                )
            notes.append((length, self.program.period(value), control))
            frames += length
        return notes

    def drums(self):
        """The drums (8.13): the beats from the loop point to the 0 byte that
        sends the reader back to it. The stores of a beat come from its kind;
        a silent beat stores the data byte as its period and the note_lengths
        index of its length as its length store (08 12 item 3): the port keeps
        the short sequence flag and the period index of that byte, and the
        length index of that store's bits 7-3."""
        if not self.area & DRUM_AREAS:
            return None
        beats, offset = [], self.noise_offset
        while True:
            value = self.byte(offset)
            offset += 1
            if value == SONG_END:
                assert beats, f"song {self.number}: an empty drum loop"
                return beats
            assert len(beats) < 256, f"song {self.number}: no end of the drum loop"
            index = packed_length_index(value)
            kind = value & PACKED_NOTE
            if kind == BEAT_LONG:
                stores = LONG_HIT
            elif kind == BEAT_LOW:
                stores = LOW_HIT
            elif kind & BEAT_SHORT:
                stores = SHORT_HIT
            else:
                stores = (SILENT_CONTROL, value & NOISE_PERIOD_FORM, self.length_index(index) >> LENGTH_INDEX_SHIFT)
            beats.append((self.frames(index),) + stores)

    def volumes(self):
        """The song's volume fields (08 8.5): the offset of its table in
        music_volumes, the step of a note's first frame (the table's size)
        and whether the volume steps run. A song without volume steps still
        sets the step of its notes: to the water table's size, the table that
        the original's choice gives an event song that is not the castle end."""
        if self.event & CASTLE_END_EVENT:
            table = CASTLE_END_VOLUMES
        elif self.area & AREA_TABLE_AREAS:
            table = AREA_VOLUMES
        else:
            table = WATER_VOLUMES
        address, entries = table
        return address - CASTLE_END_VOLUMES[0], entries, int(not self.event & NO_VOLUME_EVENTS)

    def lists(self):
        """The bytes of the song's four lists (None: no list) and its volume fields."""
        notes, song_frames = self.square2()
        square2 = [b for frames, period in notes for b in [frames] + word(period)] + [MARKER]
        square1 = self.square1(song_frames)
        if square1 is not None:
            square1 = [b for event in square1 for b in ([MARKER] if event is None else [event[0]] + word(event[1]))]
        triangle = None
        if song_frames:
            triangle = [b for frames, period, control in self.triangle(song_frames) for b in [frames] + word(period) + [control]]
        drums = None
        if song_frames:
            beats = self.drums()
            if beats is not None:
                drums = [b for beat in beats for b in beat] + [MARKER]
        if not song_frames:
            square1 = None  # the song ends in its first frame: nothing but square 2 is read
        return square2, square1, triangle, drums, self.volumes()


def song_rules(number):
    """The song's (event, area) bits: the snd_event_music and snd_area_music
    that the original plays it with."""
    if number < FIRST_AREA_SONG:
        return 1 << (number - FIRST_EVENT_SONG), 0
    if number < FIRST_GROUND_PART:
        return 0, 1 << (number - FIRST_AREA_SONG)
    return 0, GROUND_AREA


class SongLists:
    """song_lists: the records, then the lists (each list once)."""

    def __init__(self, program):
        self.program = program
        self.lists = {}  # list bytes -> its order
        self.records = {}  # (list keys, volume fields) -> its index

    def record(self, number, extra):
        event, area = song_rules(number)
        lists = Song(self.program, number, extra, event, area).lists()
        keys = []
        for part in lists[:4]:
            if part is None:
                keys.append(None)
            else:
                keys.append(self.lists.setdefault(bytes(part), len(self.lists)))
        key = (tuple(keys), lists[4])
        return self.records.setdefault(key, len(self.records))

    def layout(self):
        """The blob's bytes and the offset of each record."""
        offset = SONG_RECORD_SIZE * len(self.records)
        list_at = {}
        body = []
        for data, order in sorted(self.lists.items(), key=lambda item: item[1]):
            list_at[order] = offset + len(body)
            body += list(data)
        records = []
        for (keys, volumes), index in sorted(self.records.items(), key=lambda item: item[1]):
            fields = [NO_LIST if key is None else list_at[key] for key in keys]
            records += [b for field in fields for b in word(field)] + list(volumes)
        data = records + body
        assert len(data) < 0x10000
        return bytes(data), [SONG_RECORD_SIZE * i for i in range(len(self.records))]


def build(program, host):
    """The song and effect data, as host data (the module header)."""
    rom = Program(program)

    # The effect tables, in bank 0.
    host.game_blob_at(bytes(b for note in range(0, 2 * NOTE_VALUES, 2) for b in word(rom.period(note))), "note_periods")
    host.game_blob_at(bytes(rom.bytes(*STOMP_VOLUMES)), "stomp_volumes")
    for (address, entries), name in (
        (EXTRA_LIFE_NOTES, "extra_life_periods"),
        (POWERUP_GRAB_NOTES, "powerup_grab_periods"),
        (GROW_NOTES, "grow_periods"),
    ):
        host.game_blob_at(bytes(b for note in rom.bytes(address, entries) for b in word(rom.period(note))), name)
    periods = rom.bytes(*BRICK_NOISE_PERIODS)
    assert all(p == p & NOISE_PERIOD_FORM for p in periods)
    host.game_blob_at(bytes(periods), "brick_noise_periods")
    host.game_blob_at(bytes(rom.bytes(*BRICK_NOISE_VOLUMES)), "brick_noise_volumes")
    host.game_blob_at(bytes(rom.bytes(*BOWSER_FLAME_VOLUMES)), "bowser_flame_volumes")
    # The three volume tables of the music as they lie in the program, and the
    # byte after the water table: the first-frame value of the water notes (08
    # 12 item 1). The steps reach at most the water table's size.
    first, (water, entries) = CASTLE_END_VOLUMES[0], WATER_VOLUMES
    assert AREA_VOLUMES[0] == first + CASTLE_END_VOLUMES[1] and water == AREA_VOLUMES[0] + AREA_VOLUMES[1]
    host.game_blob_at(bytes(rom.bytes(first, water + entries + 1 - first)), "music_volumes")

    # The songs, in a data bank.
    songs = SongLists(rom)
    event = [songs.record(FIRST_EVENT_SONG + bit, 0) for bit in range(COMMAND_BITS)]
    event.append(songs.record(FIRST_EVENT_SONG + TIME_OUT_BIT, FAST_TEMPO))
    area = [songs.record(FIRST_AREA_SONG + bit, extra) for bit in range(COMMAND_BITS) for extra in (0, FAST_TEMPO)]
    parts = [songs.record(number, extra) for number in range(FIRST_GROUND_PART, SONG_NUMBERS + 1) for extra in (0, FAST_TEMPO)]
    data, record_at = songs.layout()
    table = lambda indexes: bytes(b for index in indexes for b in word(record_at[index]))
    host.blob_at(data, "song_lists")
    host.blob_at(table(event), "event_songs")
    host.blob_at(table(area), "area_songs")
    host.blob_at(table(parts), "ground_parts", "GROUND_PARTS_SIZE")
