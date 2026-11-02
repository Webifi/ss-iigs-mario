; The settings block: one disk block, the file SSMARIO.CONFIG. The game keeps
; it at `settings` (src/input_settings.s, with the defaults); the boot loader
; reads the file over it (src/boot.s load_settings), and the options menu
; writes it back (src/input_disk.s settings_save). scripts/boot_disk.py reads
; SETTINGS_SIZE, SETTINGS_CHECKSUM and SETTINGS_SEED from the debug file of
; the boot loader, which includes this file, and writes the file from the
; bytes at `settings`. So this file holds only NAME = value lines and
; .assert checks: nothing that puts bytes into the boot loader.
;
; The block:
;   offset             size  field
;   SET_MAGIC             8  "SMBKEYS", then SETTINGS_VERSION
;   SET_J13               1  J13_ON, J13_CHOSEN
;   SET_SNES_SLOT         1  the slot of a SNES MAX adapter: 1, 2, 4, 5 or 6; 0 none
;   SET_JOY_PLAYER        1  the player of the joystick: JOY_PLAYER_1 or JOY_PLAYER_2
;   SET_MUSIC_LEVEL       1  0 to MIX_LEVEL_MAX
;   SET_EFFECTS_LEVEL     1  0 to MIX_LEVEL_MAX
;   (zero up to SET_BINDINGS)
;   SET_BINDINGS        256  BIND_COUNT binding records of BINDING_SIZE bytes
;   (zero up to SETTINGS_CHECKSUM)
;   SETTINGS_CHECKSUM     2  settings_sum of the bytes before it
SETTINGS_SIZE       = 512       ; one ProDOS block: the file is a seedling
SETTINGS_CHECKSUM   = 510       ; 2 bytes: settings_sum of the bytes before it
SETTINGS_SEED       = $1985     ; the start value of settings_sum

; The fields (src/input_settings.s gives the defaults).
SET_MAGIC           = 0         ; "SMBKEYS", then SETTINGS_VERSION
SET_J13             = 8         ; J13_ON, J13_CHOSEN
SET_SNES_SLOT       = 9         ; the slot of a SNES MAX adapter; 0 none
SET_JOY_PLAYER      = 10        ; the player of the joystick: JOY_PLAYER_1 or JOY_PLAYER_2
SET_MUSIC_LEVEL     = 11        ; the music level, 0 to MIX_LEVEL_MAX
SET_EFFECTS_LEVEL   = 12        ; the effects level, 0 to MIX_LEVEL_MAX
SET_BINDINGS        = 32        ; BIND_COUNT records of BINDING_SIZE bytes
SET_BINDINGS_END    = SET_BINDINGS+BIND_COUNT*BINDING_SIZE
SETTINGS_MAGIC0     = 'S'|('M'<<8)  ; the magic as four words, for 16-bit compares
SETTINGS_MAGIC1     = 'B'|('K'<<8)
SETTINGS_MAGIC2     = 'E'|('Y'<<8)
SETTINGS_MAGIC3     = 'S'|(SETTINGS_VERSION<<8)
SETTINGS_VERSION    = 1         ; the last byte of the magic: the format of this file
J13_ON              = 1         ; SET_J13: the play reads the J13 keyboard
J13_CHOSEN          = 2         ; SET_J13: set by hand; else the first menu use may turn J13 on
MIX_LEVEL_MAX       = 15        ; SET_MUSIC_LEVEL, SET_EFFECTS_LEVEL: the full level
MIX_LEVEL_DEFAULT   = MIX_LEVEL_MAX
JOY_PLAYER_1        = 0         ; SET_JOY_PLAYER: the joystick plays for player 1
JOY_PLAYER_2        = 1         ; SET_JOY_PLAYER: the joystick plays for player 2
JOY_PLAYER_DEFAULT  = JOY_PLAYER_2 ; the player of the joystick in the default bindings

; A binding record: one key or device button and the action that it gives.
;   offset        size  field
;   BIND_KEY         1  the ADB key code (0-127), or the device key (DEV_*)
;   BIND_SOURCE      1  SOURCE_*: the keyboards or the device of the key
;   BIND_ACTION      1  the action (ACT_*, ACTION_P2 + ACT_*, ACTION_MENU);
;                       BIND_ACTIONS or more: a free record
;   (3)              1  0: not used (a record of four bytes is reached
;                       with two shifts)
BIND_COUNT          = 64        ; the records of the block
BIND_KEY            = 0
BIND_SOURCE         = 1
BIND_ACTION         = 2
BINDING_SIZE        = 4
BIND_NONE           = $FF       ; BIND_KEY and BIND_ACTION of a free record

; BIND_ACTION: the eight buttons of the pad of player 1, the same of player
; 2 (ACTION_P2 + ACT_*), then the key that opens the options menu.
ACT_LEFT            = 0
ACT_RIGHT           = 1
ACT_UP              = 2
ACT_DOWN            = 3
ACT_A               = 4         ; jump
ACT_B               = 5         ; run and fire
ACT_START           = 6
ACT_SELECT          = 7
PLAYER_ACTIONS      = 8
ACTION_P2           = PLAYER_ACTIONS
ACTION_MENU         = 2*PLAYER_ACTIONS
BIND_ACTIONS        = ACTION_MENU+1

; BIND_SOURCE: the keyboards (the keyHeld bits HELD_ADB and HELD_J13 of
; src/input_adb.s), then the devices. The key of a device binding is the
; number of its device key: DEVICE_KEYS_EACH of them for each device.
SOURCE_NONE         = 0
SOURCE_ADB          = 1         ; the ADB keyboard
SOURCE_J13          = 2         ; the J13 keyboard of a ROM 00 or ROM 01 IIgs
SOURCE_KEYBOARDS    = SOURCE_ADB|SOURCE_J13 ; both keyboards
SOURCE_JOYSTICK     = 4         ; the joystick of the game port
SOURCE_PAD1         = 5         ; pad one of the SNES MAX adapter
SOURCE_PAD2         = 6         ; pad two
SOURCE_DEVICE_FIRST = SOURCE_JOYSTICK
SOURCE_COUNT        = 7

; The device keys (BIND_KEY of a device binding). The joystick: its four
; directions, then its two buttons. A pad (src/input_devices.s pad_read):
; device key n of DEV_PAD_RIGHT to DEV_PAD_B is bit n of the first 8 bits
; that the pad sends, which come in last to first (SNES: B, Y, SELECT,
; START, UP, DOWN, LEFT, RIGHT); DEV_PAD_A to DEV_PAD_R are the next four
; bits in the order sent.
DEVICE_KEYS_EACH    = 16
DEV_RIGHT           = 0         ; the joystick
DEV_LEFT            = 1
DEV_DOWN            = 2
DEV_UP              = 3
DEV_BUTTON1         = 4         ; button 0 of the game port (BUTN0)
DEV_BUTTON2         = 5         ; button 1 of the game port (BUTN1)
DEV_PAD_RIGHT       = 0         ; a pad
DEV_PAD_LEFT        = 1
DEV_PAD_DOWN        = 2
DEV_PAD_UP          = 3
DEV_PAD_START       = 4
DEV_PAD_SELECT      = 5
DEV_PAD_Y           = 6         ; SNES Y; B of an NES pad
DEV_PAD_B           = 7         ; SNES B; A of an NES pad
DEV_PAD_A           = 8         ; SNES only
DEV_PAD_X           = 9
DEV_PAD_L           = 10
DEV_PAD_R           = 11
DEV_PAD_KEYS        = 12

.assert SET_EFFECTS_LEVEL = SET_MUSIC_LEVEL+1, error
.assert SET_BINDINGS_END <= SETTINGS_CHECKSUM .and SETTINGS_CHECKSUM = SETTINGS_SIZE-2, error
.assert SOURCE_KEYBOARDS < SOURCE_DEVICE_FIRST .and DEV_PAD_KEYS <= DEVICE_KEYS_EACH, error
