; The IIgs memory map of the game: every fixed area, its size and its use,
; for the code. src/iigs.cfg places the same areas for ld65; src/game.s
; checks that the two agree.

; Bank 0: the system pages and variables, the code of bank 0, and the
; game's state (src/game/state.inc): the object records (GAME_OBJECTS, one
; page each), the variables (GAME_STATE), and the game's bank-0 tables
; (GAME_DATA, labelled by the asset build). The system code runs with
; D = SYSTEM_PAGE, the sound interrupt with D = SOUND_PAGE, the game logic
; with D = an object record.
SYSTEM_PAGE         = $000800
SOUND_PAGE          = $000900

; The Apple text page. The game runs with it not copied to bank $E0
; (SHADOW_TEXT1); the options menu writes it (src/menu.s).
TEXT_PAGE           = $000400

; System variables (src/*.s SYSRAM), then the stack.
SYSTEM_RAM          = $000A00
SYSTEM_RAM_SIZE     = $1400
STACK_TOP           = $001FFF

; Code in bank 0.
NATIVE_CODE         = $002000   ; the system code: the clock, the packet, the stream to the card
NATIVE_CODE_SIZE    = $4000
BOOT_CODE           = $006000   ; the entry, the startup, the handoff from the boot loader
BOOT_CODE_SIZE      = $0400
SOUND_CODE          = $006400   ; the sound program and the sound unit model
SOUND_CODE_SIZE     = $1C00

; The packet to the card: built here, where the PEI sender reads it as its
; direct page (src/stream.s).
PACKET_BUFFER       = $008000
PACKET_BUFFER_SIZE  = $0400

; The game's state (src/game/state.inc): the 25 object records, each one
; page so that D at a record has a low byte of 0, then the variables.
GAME_OBJECTS        = $008800
GAME_OBJECTS_SIZE   = 25 * $100
GAME_STATE          = $00A100
GAME_STATE_SIZE     = $0F00
; The game's bank-0 tables (the asset build's game_blob_at): they run here
; and load in bank 3 (GAME_DATA_LOAD); the handoff moves them (src/game.s).
GAME_DATA           = $00B000
GAME_DATA_SIZE      = $1000
GAME_DATA_LOAD      = $030000

; Bank 1: the game logic (src/game/): code only (JSR within the bank).
GAMEPLAY_CODE       = $010000
GAMEPLAY_CODE_SIZE  = $10000

; Bank 2: the input, the options menu and the settings.
INPUT_CODE          = $020000
INPUT_CODE_SIZE     = $10000

; Banks 3-4: host data (the songs, the area records ...), after GAME_DATA_LOAD.
PAYLOAD             = $031000
PAYLOAD_END         = $050000

; Bank 5: the queue of the picture chip writes that wait for the card
; (src/packet.s): a level start writes several packets' worth in a frame.
PENDING_WRITES      = $050000
PENDING_WRITES_SIZE = $4000

; At boot the loader reads the DATA file through DATA_BUFFER (the system
; pages and variables, which the startup then clears).
DATA_BUFFER         = $000800
DATA_BUFFER_SIZE    = $1000

; The boot loader (src/boot.s). boot0 loads SSMARIO.SYSTEM to SYSTEM_LOAD; its
; BOOT segment moves the LOADER segment, which follows it in the file, to
; BOOT_LOADER. The loader runs there in emulation mode until the handoff.
SYSTEM_LOAD         = $002000
SYSTEM_BOOT_SIZE    = $0100
BOOT_LOADER         = $00A000
BOOT_LOADER_SIZE    = $1000
LOADER_ZERO_PAGE    = $000020   ; the loader's page-zero variables
LOADER_ZERO_PAGE_SIZE = $0020

; The file reader (bootloader/prodos_read.s): a data block and an index block.
READER_BUFFERS      = $009000
READER_BUFFERS_SIZE = $0400

; The card startup decoder (src/boot_unpack.s) expands one packed record of
; at most DATA_BUFFER_SIZE bytes here.
STARTUP_UNPACK_OUTPUT = $00B000

; Bank-zero page zero and the page-one stack: the firmware's in emulation
; mode. The boot loader runs with them; the save bridge keeps a copy of page
; zero and calls the block driver with them.
ZERO_PAGE           = $000000
ZERO_PAGE_SIZE      = $0100
EMULATION_STACK_TOP = $0001FF

.assert SYSTEM_RAM+SYSTEM_RAM_SIZE <= STACK_TOP-$1FF, error
.assert NATIVE_CODE+NATIVE_CODE_SIZE <= BOOT_CODE, error
.assert BOOT_CODE+BOOT_CODE_SIZE = SOUND_CODE, error
.assert SOUND_CODE+SOUND_CODE_SIZE <= PACKET_BUFFER, error
.assert (PACKET_BUFFER & $FF) = 0, error ; the PEI sender's direct page (src/stream.s)
.assert PAYLOAD_END <= PENDING_WRITES && PENDING_WRITES+PENDING_WRITES_SIZE <= $060000, error
.assert PACKET_BUFFER+PACKET_BUFFER_SIZE <= GAME_OBJECTS, error
.assert (GAME_OBJECTS & $FF) = 0, error ; D at a record: a low byte of 0 (src/game/state.inc)
.assert GAME_OBJECTS+GAME_OBJECTS_SIZE <= GAME_STATE && GAME_STATE+GAME_STATE_SIZE <= GAME_DATA, error
.assert GAME_DATA+GAME_DATA_SIZE <= $00C000, error
.assert GAME_DATA_LOAD+GAME_DATA_SIZE <= PAYLOAD, error
.assert STARTUP_UNPACK_OUTPUT+DATA_BUFFER_SIZE <= $00C000, error
.assert BOOT_LOADER >= GAME_OBJECTS && READER_BUFFERS >= GAME_OBJECTS, error ; the loader runs where the game's state goes: the startup clears it after the handoff
