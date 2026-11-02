; The format of SSMARIO.DATA. scripts/boot_disk.py writes the file with
; these values, which it reads by name from the debug file of the boot
; loader (build/game-disk/boot.dbg); the boot loader (src/boot.s) reads the
; file. So a name here is also a name in that script.
;
; The file: the header block, the segment data in table order, then the
; card startup records (when DATA_STARTUP is nonzero).
;
; The header block (DATA_HEADER_SIZE bytes):
;   offset          size  field
;   DATA_MAGIC         6  "SS-SMB" (the loader checks the first two bytes)
;   DATA_VERSION       1  DATA_FORMAT
;   DATA_SEGMENTS      1  the segment entries that follow, 1 to MAX_SEGMENTS
;   DATA_STARTUP       1  nonzero: card startup records follow the segments
;   DATA_TABLE        60  MAX_SEGMENTS entries of SEGMENT_ENTRY bytes: the
;                         host address (3), the size (3) of each segment
;   DATA_PROGRESS    144  for each of the PROGRESS_CELLS cells of the
;                         loading bar, the bytes of the file read when it
;                         fills (4 bytes each)
;   (zero up to DATA_HEADER_SIZE)
DATA_HEADER_SIZE    = 512
DATA_MAGIC          = 0
DATA_VERSION        = 6
DATA_SEGMENTS       = 8
DATA_STARTUP        = 9
DATA_TABLE          = 10
DATA_FORMAT         = 2         ; DATA_VERSION of this format
SEGMENT_ENTRY       = 6         ; host address (3 bytes), size (3 bytes)
MAX_SEGMENTS        = 10        ; the segment entries that the table has room for
DATA_PROGRESS       = DATA_TABLE+MAX_SEGMENTS*SEGMENT_ENTRY
PROGRESS_CELLS      = 36        ; the cells of the progress bar of the loading screen (src/boot.s)
PROGRESS_ENTRY      = 4         ; DATA_PROGRESS: the bytes of one cell's count
.assert DATA_PROGRESS+PROGRESS_CELLS*PROGRESS_ENTRY <= DATA_HEADER_SIZE, error

; A card startup record: this header, then RECORD_STORED bytes (a packed
; record) or RECORD_SIZE bytes. A header with a zero size ends the list.
; Each record fits DATA_BUFFER (scripts/boot_disk.py boot_uploads).
;   offset          size  field
;   RECORD_ADDRESS     3  the card address (an UploadData destination,
;                         SS_UPLOAD_LINEAR)
;   RECORD_SIZE        3  the bytes after the unpack; at most DATA_BUFFER_SIZE
;   RECORD_CONTROL     1  RECORD_FINAL_SRAM, RECORD_FINAL_VRAM, RECORD_PACKED
;   RECORD_MASK        1  the VGA map mask: the planes that receive the bytes
;   RECORD_STORED      2  a packed record: the stored bytes
RECORD_ADDRESS      = 0
RECORD_SIZE         = 3
RECORD_CONTROL      = 6
RECORD_MASK         = 7
RECORD_STORED       = 8
RECORD_HEADER_SIZE  = 10
RECORD_ADDRESS_SIZE = 3         ; the bytes of RECORD_ADDRESS
; RECORD_CONTROL bits. The records come in three groups (boot_uploads):
; first the bytes that the firmware does not use while it shows the loading
; screen (video RAM from $8000, card SRAM bank 1), then card SRAM bank 0,
; over the firmware's renderer, then the video RAM below $8000, the
; firmware's text image and font. The first record of the last two groups
; has a flag.
RECORD_FINAL_SRAM   = $80       ; the first record that replaces the firmware renderer
RECORD_FINAL_VRAM   = $40       ; the first record that replaces the firmware text image
RECORD_PACKED       = $20       ; scripts/startup_pack.py packed the stored bytes (src/boot_unpack.s)
