; The default bindings: the macro default_bindings writes BIND_COUNT binding
; records (src/settings.inc), the free ones last. The settings image
; (src/input_settings.s) holds them at SET_BINDINGS; settings_check and
; RESTORE DEFAULT BINDINGS copy them again from menu_default_bindings
; (src/menu_text.inc). Both keyboards share the keys (SOURCE_KEYBOARDS); the
; menu can split a binding.

; bind KEY, SOURCE, ACTION: one binding record (BINDING_SIZE bytes), counted
; in BIND_RECORDS.
.macro bind key, source, action
  .byte key, source, action, 0
  BIND_RECORDS .set BIND_RECORDS+1
.endmacro

.macro default_bindings
  BIND_RECORDS .set 0
; The keyboard: player 1 moves with W A S D, I J K L, the arrows and keypad
; 8 4 5 6; control is A (jump) and both Apple keys, option and open apple,
; are B (run and fire). 1 and 2 are the two players' START, 5 and 6 their
; SELECT. Player 2 has shift and keypad enter for A, and the joystick. The
; Apple keys are bound on the ADB keyboard only: on a ROM 00 or ROM 01 IIgs
; the J13 Apple keys are the wires of the joystick buttons
; (src/input_devices.s devices_sample), so there they stay the joystick's.
  bind KEY_W, SOURCE_KEYBOARDS, ACT_UP
  bind KEY_A, SOURCE_KEYBOARDS, ACT_LEFT
  bind KEY_S, SOURCE_KEYBOARDS, ACT_DOWN
  bind KEY_D, SOURCE_KEYBOARDS, ACT_RIGHT
  bind KEY_I, SOURCE_KEYBOARDS, ACT_UP
  bind KEY_J, SOURCE_KEYBOARDS, ACT_LEFT
  bind KEY_K, SOURCE_KEYBOARDS, ACT_DOWN
  bind KEY_L, SOURCE_KEYBOARDS, ACT_RIGHT
  bind KEY_UP, SOURCE_KEYBOARDS, ACT_UP
  bind KEY_LEFT, SOURCE_KEYBOARDS, ACT_LEFT
  bind KEY_DOWN, SOURCE_KEYBOARDS, ACT_DOWN
  bind KEY_RIGHT, SOURCE_KEYBOARDS, ACT_RIGHT
  bind KEY_PAD_8, SOURCE_KEYBOARDS, ACT_UP
  bind KEY_PAD_4, SOURCE_KEYBOARDS, ACT_LEFT
  bind KEY_PAD_5, SOURCE_KEYBOARDS, ACT_DOWN
  bind KEY_PAD_6, SOURCE_KEYBOARDS, ACT_RIGHT
  bind KEY_CONTROL, SOURCE_KEYBOARDS, ACT_A
  bind KEY_OPTION, SOURCE_ADB, ACT_B
  bind KEY_COMMAND, SOURCE_ADB, ACT_B
  bind KEY_SHIFT, SOURCE_KEYBOARDS, ACTION_P2+ACT_A
  bind KEY_PAD_ENTER, SOURCE_KEYBOARDS, ACTION_P2+ACT_A
  bind KEY_1, SOURCE_KEYBOARDS, ACT_START
  bind KEY_2, SOURCE_KEYBOARDS, ACTION_P2+ACT_START
  bind KEY_5, SOURCE_KEYBOARDS, ACT_SELECT
  bind KEY_6, SOURCE_KEYBOARDS, ACTION_P2+ACT_SELECT
; The joystick for player 2 (JOY_PLAYER_DEFAULT): button 1 jumps, button 2
; runs.
  bind DEV_LEFT, SOURCE_JOYSTICK, ACTION_P2+ACT_LEFT
  bind DEV_RIGHT, SOURCE_JOYSTICK, ACTION_P2+ACT_RIGHT
  bind DEV_UP, SOURCE_JOYSTICK, ACTION_P2+ACT_UP
  bind DEV_DOWN, SOURCE_JOYSTICK, ACTION_P2+ACT_DOWN
  bind DEV_BUTTON1, SOURCE_JOYSTICK, ACTION_P2+ACT_A
  bind DEV_BUTTON2, SOURCE_JOYSTICK, ACTION_P2+ACT_B
; The SNES MAX pads: pad one player 1, pad two player 2. An NES pad sends
; its B and A where a SNES pad sends Y and B, so both kinds have B on the
; left and A on the right. Only the first 8 bits are bound: after them an
; NES pad sends the level of its grounded serial input, which reads as
; pressed, so a default binding of a SNES-only button would hold its action.
  bind DEV_PAD_LEFT, SOURCE_PAD1, ACT_LEFT
  bind DEV_PAD_RIGHT, SOURCE_PAD1, ACT_RIGHT
  bind DEV_PAD_UP, SOURCE_PAD1, ACT_UP
  bind DEV_PAD_DOWN, SOURCE_PAD1, ACT_DOWN
  bind DEV_PAD_B, SOURCE_PAD1, ACT_A
  bind DEV_PAD_Y, SOURCE_PAD1, ACT_B
  bind DEV_PAD_START, SOURCE_PAD1, ACT_START
  bind DEV_PAD_SELECT, SOURCE_PAD1, ACT_SELECT
  bind DEV_PAD_LEFT, SOURCE_PAD2, ACTION_P2+ACT_LEFT
  bind DEV_PAD_RIGHT, SOURCE_PAD2, ACTION_P2+ACT_RIGHT
  bind DEV_PAD_UP, SOURCE_PAD2, ACTION_P2+ACT_UP
  bind DEV_PAD_DOWN, SOURCE_PAD2, ACTION_P2+ACT_DOWN
  bind DEV_PAD_B, SOURCE_PAD2, ACTION_P2+ACT_A
  bind DEV_PAD_Y, SOURCE_PAD2, ACTION_P2+ACT_B
  bind DEV_PAD_START, SOURCE_PAD2, ACTION_P2+ACT_START
  bind DEV_PAD_SELECT, SOURCE_PAD2, ACTION_P2+ACT_SELECT
; The menu key: ESC on both keyboards. ESC opens the menu whatever the
; bindings say (src/input_bindings.s compile_masks); this record shows it on
; the MENU KEY page.
  bind KEY_ESC, SOURCE_KEYBOARDS, ACTION_MENU
; The free records.
  .assert BIND_RECORDS <= ::BIND_COUNT, error
  .repeat ::BIND_COUNT-BIND_RECORDS
    bind BIND_NONE, SOURCE_NONE, BIND_NONE
  .endrepeat
.endmacro
