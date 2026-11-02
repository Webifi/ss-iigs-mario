; The texts and tables of the options menu (src/menu.s), in the scope of
; the input (src/input.s): the names of the actions, keys, device keys and
; sources, and the default bindings that RESTORE DEFAULT BINDINGS copies.

; menu_name: a text of NAME_SIZE characters, filled with spaces.
.macro menu_name text
  .byte text
  .res NAME_SIZE-.strlen(text), ' '
.endmacro
; menu_source_name: a text of SOURCE_NAME_SIZE characters.
.macro menu_source_name text
  .byte text
  .res SOURCE_NAME_SIZE-.strlen(text), ' '
.endmacro

; menu_apple_rows: the text page offset of each menuText row, from the
; interleaved rows of the text page (TEXT_ROW_r, src/iigs.inc); MENU_CENTRE
; columns centre the layout.
MENU_CENTRE = (::TEXT_COLUMNS-MENU_COLUMNS)/2
menu_apple_rows:
.repeat MENU_ROWS, ROW
  .word .loword(.ident(.sprintf("TEXT_ROW_%d", ROW))-::TEXT_PAGE1)+MENU_CENTRE
.endrepeat
.assert MENU_ROWS <= ::TEXT_ROWS .and MENU_COLUMNS <= ::TEXT_COLUMNS, error

; menu_actions: the name of each BIND_ACTION.
menu_actions:
  menu_name "P1 LEFT"
  menu_name "P1 RIGHT"
  menu_name "P1 UP"
  menu_name "P1 DOWN"
  menu_name "P1 A JUMP"
  menu_name "P1 B RUN"
  menu_name "P1 START"
  menu_name "P1 SELECT"
  menu_name "P2 LEFT"
  menu_name "P2 RIGHT"
  menu_name "P2 UP"
  menu_name "P2 DOWN"
  menu_name "P2 A JUMP"
  menu_name "P2 B RUN"
  menu_name "P2 START"
  menu_name "P2 SELECT"
  menu_name "MENU"
.assert *-menu_actions = BIND_ACTIONS*NAME_SIZE, error

; The keys without a character: menu_named_keys lists their ADB codes,
; menu_key_names their names in the same order, and the function keys come
; last (FUNCTION_FIRST on), named F and their number. A keypad key is named
; PAD and its character, every other key by its character
; (menu_copy_binding_name).
menu_named_keys:
  .byte KEY_RETURN, KEY_TAB, KEY_SPACE, KEY_DELETE, KEY_ESC, KEY_CONTROL
  .byte KEY_COMMAND, KEY_SHIFT, KEY_CAPS_LOCK, KEY_OPTION
  .byte KEY_LEFT, KEY_RIGHT, KEY_DOWN, KEY_UP, KEY_PAD_ENTER, KEY_CLEAR
  .byte KEY_HELP, KEY_HOME, KEY_PAGE_UP, KEY_FORWARD_DELETE, KEY_END, KEY_PAGE_DOWN
menu_function_keys:                 ; named F and their number
  .byte KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8
  .byte KEY_F9, KEY_F10, KEY_F11, KEY_F12, KEY_F13, KEY_F14, KEY_F15
NAMED_KEYS = *-menu_named_keys
menu_key_names:
  menu_name "RETURN"
  menu_name "TAB"
  menu_name "SPACE"
  menu_name "DELETE"
  menu_name "ESC"
  menu_name "CONTROL"
  menu_name "OPEN APPLE"
  menu_name "SHIFT"
  menu_name "CAPS LOCK"
  menu_name "OPTION"
  menu_name "LEFT"
  menu_name "RIGHT"
  menu_name "DOWN"
  menu_name "UP"
  menu_name "PAD ENTER"
  menu_name "CLEAR"
  menu_name "HELP"
  menu_name "HOME"
  menu_name "PAGE UP"
  menu_name "DEL"
  menu_name "END"
  menu_name "PAGE DOWN"
FUNCTION_FIRST = menu_function_keys-menu_named_keys
FUNCTION_KEYS = 15              ; F1 to F15
.assert *-menu_key_names = FUNCTION_FIRST*NAME_SIZE .and NAMED_KEYS-FUNCTION_FIRST = FUNCTION_KEYS, error
; menu_key_characters: the unshifted characters that name the other keys:
; the character whose asciiKeys code (src/input_j13.s) is the key names it.
; Each character here gives a different key code.
menu_key_characters:
  .byte "0123456789abcdefghijklmnopqrstuvwxyz',-./;=[", $5c, "]`"
KEY_CHARACTERS = *-menu_key_characters

; menu_device_names: the device keys of the joystick (DEV_RIGHT ... DEV_BUTTON2).
menu_device_names:
  menu_name "RIGHT"
  menu_name "LEFT"
  menu_name "DOWN"
  menu_name "UP"
  menu_name "BUTTON 1"
  menu_name "BUTTON 2"
.assert *-menu_device_names = (DEV_BUTTON2+1)*NAME_SIZE, error
; menu_pad_names: the device keys of a pad, in the order of DEV_PAD_*
; (src/settings.inc). An NES pad sends its B and A where a SNES pad sends
; Y and B.
menu_pad_names:
  menu_name "RIGHT"
  menu_name "LEFT"
  menu_name "DOWN"
  menu_name "UP"
  menu_name "START"
  menu_name "SELECT"
  menu_name "Y (NES B)"
  menu_name "B (NES A)"
  menu_name "BUTTON A"
  menu_name "BUTTON X"
  menu_name "BUTTON L"
  menu_name "BUTTON R"
.assert *-menu_pad_names = DEV_PAD_KEYS*NAME_SIZE, error
; menu_sources: the name of each BIND_SOURCE.
menu_sources:
  menu_source_name "UNBOUND"
  menu_source_name "ADB KEYBOARD"
  menu_source_name "J13 KEYBOARD"
  menu_source_name "ADB AND J13"
  menu_source_name "JOYSTICK"
  menu_source_name "PAD ONE"
  menu_source_name "PAD TWO"
.assert *-menu_sources = SOURCE_COUNT*SOURCE_NAME_SIZE, error
; menu_default_bindings: RESTORE DEFAULT BINDINGS and settings_check copy
; these.
menu_default_bindings:
  default_bindings
.assert *-menu_default_bindings = BINDINGS_BYTES, error
