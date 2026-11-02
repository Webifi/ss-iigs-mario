; The options menu (ESC): the controls of both players and the menu key,
; the devices, the sound levels, SAVE and RESUME. Part of the input
; (src/input.s), in its scope.
;
; The menu stops the game: the main loop calls options_menu when
; input_frame returned carry set, and the menu runs until the player leaves
; it. The DOC interrupt goes on (the clock, the sound tick, the input
; capture). The game's state stays; its frames do not run.
;
; The screen: the card keeps its state and restarts its
; firmware (src/secondsight/menu.s), which shows the Apple 40-column text
; page in its own text mode for both monitors. The firmware
; copies the IIgs writes of text page 1 into its own copy (SetShadow
; SS_SHADOW_ALL); the IIgs copies its bank-0 writes there to bank $E0 only
; while SHADOW_TEXT1 is off. The game keeps nothing in text page 1
; ($0400-$07FF: no segment of src/iigs.cfg is there), so the menu clears it
; and leaves its text there at the end. On the way back the card gets its
; program again with RunCode at entry_resume (src/secondsight/entry.s).
;
; The Apple video switches ($C00C-$C00F, $C050-$C057) and the text colours
; ($C022) are Second Sight events: the menu writes them only while the
; firmware runs, never while the card program receives packets.
;
.a16
.i16
MENU_ROWS = 24               ; menuText: the rows of a page
MENU_COLUMNS = 28            ; menuText: the characters of a row
MENU_MARK = $d5              ; the marker: menu_publish makes it $55, the MouseText arrow
MENU_COLOURS = $f0           ; TBCOLOR: white text on black
MENU_WAIT = 8                ; inputClock ticks between two menu samples (33 ms)
MENU_PITCH = 2*MENU_COLUMNS  ; a list: a choice on each second row
MENU_LIST = 3*MENU_COLUMNS   ; row 3: the first choice
MENU_FOOTER = 22*MENU_COLUMNS ; row 22: the message
NAME_SIZE = 10               ; a name of menu_actions, menu_key_names, ...
SOURCE_NAME_SIZE = 14        ; a name of menu_sources
LEVEL_TEXT_SIZE = 2          ; a level of menu_level_numbers
LEVEL_PITCH = MENU_COLUMNS   ; MP_LEVEL: a level on each row
BINDINGS_BYTES = SET_BINDINGS_END-SET_BINDINGS ; the binding records
NO_BINDING = BINDINGS_BYTES  ; menu_find_binding: the action has no binding
ACTION_COLUMN = 2            ; MP_ACTIONS: the action name
KEY_COLUMN = 14              ; MP_ACTIONS: the name of the bound key
BINDING_COLUMN = 12          ; MP_BINDING: the name of the bound key
DEVICE_COLUMN = 19           ; MP_DEVICES: the values
SOUND_COLUMN = 22            ; MP_SOUND: the values
LEVEL_COLUMN = 2             ; MP_LEVEL: the levels
DEVICE_BUTTONS = DEV_BUTTON1 ; a device key from this on is a button (RETURN)
; menuPage: the page that shows.
MP_MAIN = 0
MP_GROUPS = 1                ; player 1, player 2, the menu key
MP_DEVICES = 2
MP_SOUND = 3
MP_BINDING = 4               ; the binding of one action
MP_LEVEL = 5                 ; a level
MP_ACTIONS = 6               ; the actions of a group
; menuAction: the choice on the page.
MAIN_SAVE = 3                ; MP_MAIN: 0-2 open MP_GROUPS-MP_SOUND
MAIN_RESUME = 4
MAIN_CHOICES = 5
GROUP_BACK = 3
GROUP_CHOICES = 4
DEVICE_J13 = 0               ; MP_DEVICES
DEVICE_SLOT = 1
DEVICE_RECHECK = 2
DEVICE_JOY_PLAYER = 3
DEVICE_DEFAULTS = 4
DEVICE_BACK = 5
DEVICE_CHOICES = 6
SOUND_EFFECTS = 1            ; MP_SOUND: 0 the music level
SOUND_BACK = 2
SOUND_CHOICES = 3
BINDING_CHANGE = 0           ; MP_BINDING (menuChoice)
BINDING_ADD = 1
BINDING_REMOVE = 2
BINDING_NEXT = 3
BINDING_BOTH = 4
BINDING_BACK = 5
BINDING_CHOICES = 6
LISTEN_CHANGE = 1            ; menuListen: the next key replaces the binding
LISTEN_ADD = 2               ; menuListen: the next key is one more binding
; menuMessage: the message of the footer (menu_messages entry + 1); 0 none.
MSG_SAVED = 1
MSG_NO_ROOM = 2              ; no free binding record
MSG_SAVE_ERROR = 3
; The card handshakes. A poll of SS_HANDSHAKE takes about 5-7 us (one slow
; read and a few fast instructions).
FIRMWARE_ROUNDS = 256        ; firmware_wait: times SS_POLLS polls, about 1.5 minutes: the
                             ; bound of src/boot.s detect_secondsight for a firmware that starts
MODE_ROUNDS = 8              ; setmode_done: times SS_POLLS polls, about 4 s: SetMode takes
                             ; effect at a vertical blank
PAD_PREFIX = 4               ; menu_pad_prefix: "PAD ", then the keypad character
DECIMAL = 10                 ; the F keys: a number of one or two digits
CASE_BIT = $20               ; ASCII: the bit that makes a letter lower case

; ---------------------------------------------------------------------------
; options_menu: the options menu, until the player leaves it (ESC on the
; main page, or RESUME). Each MENU_WAIT ticks a sample of the input, a key,
; and a page drawn again after a change. At the end the buttons that are
; held wait for their release before the game sees them (menuHeld), the
; menu key must be let go before it opens the menu again (menuWasDown), and
; the frames of the menu's time are not owed to the game (frames_due = 0).
;
; In:       A8 I8, D = SYSTEM_PAGE, DBR = 0 (src/game.s main_loop)
; Out:      the settings as the player left them; the card runs its program
; Changes:  A, X, Y; frames_due; the menu state; menuMode, menuWasDown,
;           menuHeld, the latches; the J13 mode (J13Menu)
; Keeps:    D, DBR, the widths
; Original: none
; ---------------------------------------------------------------------------
options_menu:
.a8
.i8
  php
  ax16
  phb
  phk
  plb                           ; DBR = this bank
  ; The menu state of each visit: the main page, no wait, no message.
  lda #1
  sta a:.loword(menuMode)
  sta a:.loword(menuDirty)
  stz a:.loword(menuPage)       ; MP_MAIN
  stz a:.loword(menuAction)
  stz a:.loword(menuAlias)
  stz a:.loword(menuListen)
  stz a:.loword(menuMessage)
  lda a:.loword(inputSerial)
  sta a:.loword(menuSerial)     ; a key held at the open is no menu key
  jsl J13Menu
  jsl sound_hold                ; src/sound.s: the sound unit stops with the game
  jsr .loword(menu_open)
@loop:
  ; A sample of the input; the page again after a change.
  lda #JOY_READ_NOW             ; the joystick at each sample
  sta a:.loword(joyUpdate)
  jsr .loword(input_sample)
  stz a:.loword(keyLatch)       ; the game sees none of the menu's presses
  stz a:.loword(systemLatch)
  lda a:.loword(menuDirty)
  beq @input
  stz a:.loword(menuDirty)
  jsr .loword(menu_draw)
@input:
  ; A press since the last sample (inputSerial moved): ESC, a key of the
  ; wait, or a key of the page.
  lda a:.loword(inputSerial)
  cmp a:.loword(menuSerial)
  bne :+
  jmp .loword(@wait)            ; no key
:
  sta a:.loword(menuSerial)
  lda a:.loword(keyAction)
  cmp #KEY_ESC                  ; a device key is 0-15: never KEY_ESC
  bne @key
  ; ESC: the wait for a key stops; else the page before shows.
  lda a:.loword(menuListen)
  beq :+
  stz a:.loword(menuListen)
  bra @changed
:
  lda a:.loword(menuPage)
  bne :+
  jmp .loword(@resume)          ; MP_MAIN
:
  cmp #MP_BINDING
  bne :+
  jsr .loword(menu_binding_back)
  bra @changed
:
  cmp #MP_ACTIONS
  bne :+
  lda #MP_GROUPS
  sta a:.loword(menuPage)
  stz a:.loword(menuAction)
  bra @changed
:
  cmp #MP_LEVEL
  bne :+
  lda #MP_SOUND
  sta a:.loword(menuPage)
  bra @changed
:
  stz a:.loword(menuPage)       ; MP_GROUPS, MP_DEVICES, MP_SOUND: MP_MAIN
  stz a:.loword(menuAction)
  bra @changed
@key:
  lda a:.loword(menuListen)
  beq @navigate
  jsr .loword(menu_bind)
  bra @changed
@navigate:
  jsr .loword(menu_key)
@changed:
  lda a:.loword(menuMode)
  beq @resume                   ; RESUME
  lda #1
  sta a:.loword(menuDirty)
@wait:
  ; The menu is not a game frame: it waits MENU_WAIT ticks of the DOC
  ; interrupt for the next sample.
  lda a:.loword(inputClock)
  sta a:.loword(menuTime)
@tick:
  lda a:.loword(inputClock)
  sec
  sbc a:.loword(menuTime)
  cmp #MENU_WAIT
  bcc @tick
  jmp .loword(@loop)
@resume:
  ; The menu closes: the card program again, the sound goes on.
  stz a:.loword(menuMode)
  jsr .loword(menu_close)
  jsl sound_release             ; src/sound.s: the sound unit goes on
  lda #1
  sta a:.loword(menuWasDown)    ; the key that closed the menu does not open it
  lda a:.loword(heldCommand)
  sta a:.loword(menuHeld)       ; held buttons wait for their release
  stz a:.loword(keyLatch)
  stz a:.loword(systemLatch)
  ; The time in the menu is not owed to the game: no frame is due.
  a8
  lda #0
  sta f:frames_due
  plb
  plp
  rtl

; ---------------------------------------------------------------------------
; menu_open: give the screen to the card's firmware and show the text page:
;   1. packet_menu (src/packet.s) sends the pending writes, then a packet
;      with PF_MENU; the card keeps its state and restarts its firmware.
;   2. firmware_wait: the firmware answers GetStatus with its signature.
;   3. The Apple video switches of 40-column text page 1 (the firmware sees
;      them), SetShadow SS_SHADOW_ALL (the firmware copies the text page),
;      SetMode SS_MODE_TEXT40 with SS_EMULATION (the firmware's 40-column
;      text mode, which it has for both monitors), ALTCHAR (MouseText: the
;      marker), the menu's colours.
;   4. SHADOW_TEXT1 off: the IIgs copies its text page writes to bank $E0,
;      where the card sees them.
;   5. The text page clears.
; The video switches and the colours of the game are kept for menu_close
; (their reads are not Second Sight events).
;
; In:       A16 X16, DBR = this bank
; Out:      the firmware shows the cleared text page; A16
; Changes:  A, X, Y; menuSavedText, menuSavedPage, menuSavedColumns,
;           menuSavedColour, menuShadow, firmwareStatus; SHADOW, TBCOLOR,
;           the video switches
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
; The firmware handshake (menu_open, menu_close): the menu packet, then
; the firmware's idle handshake and GetStatus (firmware_wait), then each
; command waits for SS_READY before its bytes (command_ready) and for
; SS_PHASE_DONE after them (command_done); SetMode then for SS_DONE
; (setmode_done). A card that does not answer within the bound stops the
; game (src/game.s failed).
;
menu_open:
  ; The game's video switches and colours, for menu_close.
  a8
  lda f:RDTEXT
  sta a:.loword(menuSavedText)
  lda f:RDPAGE2
  sta a:.loword(menuSavedPage)
  lda f:RD80VID
  sta a:.loword(menuSavedColumns)
  lda f:TBCOLOR
  sta a:.loword(menuSavedColour)
  jsl packet_menu               ; src/packet.s: the writes, then PF_MENU
  jsr .loword(firmware_wait)
  ; The firmware's screen: 40-column text page 1, the copy on, its text
  ; mode, MouseText, the menu's colours.
  lda #0
  sta f:CLR80VID                ; 40 columns
  lda f:TXTSET                  ; text
  lda f:TXTPAGE1                ; page 1
  lda #SS_SET_SHADOW
  sta f:SS_COMMAND
  jsl command_ready
  lda #SS_SHADOW_ALL
  sta f:SS_DATA_OUT
  jsl command_done
  lda #SS_SET_MODE
  sta f:SS_COMMAND
  jsl command_ready
  lda #SS_MODE_TEXT40
  sta f:SS_DATA_OUT
  lda #SS_EMULATION
  sta f:SS_DATA_OUT
  jsl command_done
  jsr .loword(setmode_done)
  lda #0
  sta f:SETALTCHAR              ; after SetMode: the firmware shows MouseText again
  lda #MENU_COLOURS
  sta f:TBCOLOR
  ; The text page: copied to bank $E0 while the menu shows.
  lda f:SHADOW
  sta a:.loword(menuShadow)
  and #<~SHADOW_TEXT1
  sta f:SHADOW
  a16
  jmp .loword(menu_clear_apple)

; ---------------------------------------------------------------------------
; menu_close: the screen back to the card program: the game's colours and
; video switches (the firmware still runs), a blank text page in bank $E0
; (the IIgs display shows spaces again, as after the boot), SetShadow
; SS_SHADOW_NONE (the card stops its copy), SHADOW as before (the text page
; not copied again), then RunCode at entry_resume with the game's MMU (as src/game.s starts the
; card at entry_start), and the token of receive buffer 0 for the next
; packet (packet_token).
;
; In:       A16 X16, DBR = this bank
; Out:      the card runs its program; packet_token = READY_TOKEN; the
;           A16
; Changes:  A, X, Y; SHADOW, TBCOLOR, the video switches
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
menu_close:
  ; The game's colours and video switches, while the firmware still runs
  ; (they are Second Sight events).
  a8
  lda a:.loword(menuSavedColour)
  sta f:TBCOLOR
  lda a:.loword(menuSavedColumns)
  bpl :+
  sta f:SET80VID
  bra :++
: sta f:CLR80VID
:
  lda a:.loword(menuSavedPage)
  bpl :+
  lda f:TXTPAGE2
  bra :++
: lda f:TXTPAGE1
:
  lda a:.loword(menuSavedText)
  bpl :+
  lda f:TXTSET
  bra :++
: lda f:TXTCLR
:
  ; A blank text page, then the copy stops and the text page is the game's
  ; RAM again (SHADOW as before the menu).
  a16
  jsr .loword(menu_clear_apple)
  a8
  lda #SS_SET_SHADOW
  sta f:SS_COMMAND
  jsl command_ready
  lda #SS_SHADOW_NONE
  sta f:SS_DATA_OUT
  jsl command_done
  lda a:.loword(menuShadow)
  sta f:SHADOW                  ; the text page is not copied again
  ; RunCode: the card program goes on at entry_resume.
  a8
  lda #SS_RUN_CODE
  sta f:SS_COMMAND
  jsl command_ready
  lda #secondsight_game_cbr
  sta f:SS_DATA_OUT
  lda #secondsight_game_cbar
  sta f:SS_DATA_OUT
  lda #secondsight_game_bbr
  sta f:SS_DATA_OUT
  lda #<secondsight_entry_resume
  sta f:SS_DATA_OUT
  lda #>secondsight_entry_resume
  sta f:SS_DATA_OUT
  jsl command_done
  lda #secondsight_READY_TOKEN  ; the card arms receive buffer 0 first
  sta f:packet_token
  a16
  rts

; ---------------------------------------------------------------------------
; monitor_sense: the monitor sense byte of the firmware's status, for the game
; clock (src/clock.s clock_start). The startup (src/game.s) calls it before
; RunCode, while the firmware still runs.
;
; In:       A8 X16; the firmware waits for a command; JSL
; Out:      A   the sense byte (SS_SENSE); the firmware waits for a command
; Changes:  A, X, Y; firmwareStatus
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
.a8
monitor_sense:
  phb
  phk
  plb                           ; DBR = this bank
  jsr .loword(firmware_wait)
  lda a:.loword(firmwareStatus+SS_SENSE)
  plb
  rtl

; ---------------------------------------------------------------------------
; firmware_wait: wait for the card's firmware after the menu packet, or at
; the start. The firmware writes 0 to the handshake when it starts; until
; then the card shows the token of the menu packet. A command before that
; 0 would be lost: the firmware's write acknowledges a pending event.
; Then GetStatus (as src/boot.s detect_secondsight,
; with its wait): one dummy read, SS_STATUS_SIZE bytes, the signature
; "GSVGA" and the count SS_STATUS_BYTES; then the end of its phase. A card
; that does not answer stops the game (src/game.s failed).
;
; In:       A8 X16, DBR = this bank
; Out:      the firmware waits for a command; firmwareStatus
; Changes:  A, X, Y
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
.a8
firmware_wait:
  ldy #FIRMWARE_ROUNDS
@round:
  ldx #SS_POLLS
@idle:
  lda f:SS_HANDSHAKE
  beq @status                   ; SS_PHASE_DONE: the firmware's idle handshake
  dex
  bne @idle
  dey
  bne @round
  jml failed
@status:
  lda #SS_GET_STATUS
  sta f:SS_COMMAND
  ldy #FIRMWARE_ROUNDS
@answer:
  ldx #SS_POLLS
@ready:
  lda f:SS_HANDSHAKE
  cmp #SS_READY
  beq @reply
  dex
  bne @ready
  dey
  bne @answer
  jml failed
@reply:
  lda f:SS_DATA_IN              ; the dummy read: the handshake byte
  ldx #0
@read:
  lda f:SS_DATA_IN
  sta a:.loword(firmwareStatus),x
  inx
  cpx #SS_STATUS_SIZE
  bne @read
  ldx #SS_SIGNATURE_SIZE-1
@signature:
  lda a:.loword(firmwareStatus+SS_SIGNATURE),x
  cmp a:.loword(firmware_signature),x
  bne @failed
  dex
  bpl @signature
  lda a:.loword(firmwareStatus+SS_STATUS_COUNT)
  cmp #SS_STATUS_BYTES
  bne @failed
  jsl command_done              ; the firmware ends the GetStatus phase
  rts
@failed:
  jml failed

; ---------------------------------------------------------------------------
; command_ready: wait until the card is ready for the bytes of a command
; (SS_READY). No answer in SS_POLLS polls stops the game (failed). JSL:
; the startup (src/game.s) and the menu call it.
;
; In:       A8 X16
; Out:      the card waits for the bytes
; Changes:  A, X
; Keeps:    Y, D, DBR
; Original: none
; ---------------------------------------------------------------------------
command_ready:
  ldx #SS_POLLS
@poll:
  lda f:SS_HANDSHAKE
  cmp #SS_READY
  beq @ok
  dex
  bne @poll
  jml failed
@ok:
  rtl

; ---------------------------------------------------------------------------
; command_done: wait until the card has read the bytes of a command
; (SS_PHASE_DONE). No answer in SS_POLLS polls stops the game (failed).
; JSL: the startup (src/game.s) and the menu call it.
;
; In:       A8 X16
; Out:      the phase is finished
; Changes:  A, X
; Keeps:    Y, D, DBR
; Original: none
; ---------------------------------------------------------------------------
command_done:
  ldx #SS_POLLS
@poll:
  lda f:SS_HANDSHAKE            ; SS_PHASE_DONE is 0
  beq @ok
  dex
  bne @poll
  jml failed
@ok:
  rtl

; ---------------------------------------------------------------------------
; setmode_done: wait until SetMode is finished (SS_DONE); SS_MODE_FAILED
; (the monitor has no such mode) or no answer in MODE_ROUNDS rounds stops
; the game (failed).
;
; In:       A8 X16
; Out:      the mode is set
; Changes:  A, X, Y
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
setmode_done:
  ldy #MODE_ROUNDS
@round:
  ldx #SS_POLLS
@poll:
  lda f:SS_HANDSHAKE
  cmp #SS_DONE
  beq @ok
  cmp #SS_MODE_FAILED
  beq @failed
  dex
  bne @poll
  dey
  bne @round
@failed:
  jml failed
@ok:
  rts
.assert SS_PHASE_DONE = 0, error ; the BEQs of command_done and firmware_wait

; ---------------------------------------------------------------------------
; menu_key: a key on a menu page. A device gives its directions as the
; arrow keys and its buttons as RETURN.
;
; In:       A16 X16, DBR = this bank; keyAction, actionSource
; Out:      menuPage, menuAction, menuChoice, menuListen, menuAlias,
;           menuBase, menuLimit, menuMode, the settings
; Changes:  A, X, Y
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
.a16
; The pages (menuPage), with the keys that move between them:
;   MP_MAIN     CONTROLS, DEVICES, SOUND, SAVE, RESUME. RETURN on the first
;               three opens their page; ESC or RESUME leaves the menu.
;   MP_GROUPS   PLAYER 1, PLAYER 2, MENU KEY, BACK: RETURN opens MP_ACTIONS.
;   MP_ACTIONS  the actions of a group with their selected binding; UP and
;               DOWN choose, RETURN opens MP_BINDING of the action; ESC or
;               BACK: MP_GROUPS.
;   MP_BINDING  one action: CHANGE (the next key replaces the binding), ADD
;               (the next key is one more binding), REMOVE, NEXT BINDING,
;               BOTH KEYBOARDS, BACK. While the menu waits for a key, ESC
;               stops the wait.
;   MP_DEVICES  J13 PLAY, SNES MAX SLOT, RECHECK JOYSTICK, JOYSTICK PLAYER,
;               RESTORE DEFAULT BINDINGS, BACK: RETURN or RIGHT changes.
;   MP_SOUND    MUSIC VOLUME, EFFECTS VOLUME, BACK: RETURN opens MP_LEVEL.
;   MP_LEVEL    the levels 0 to MIX_LEVEL_MAX: RETURN sets the level (the
;               sound takes it at once) and goes back to MP_SOUND.
; A device gives its directions as the arrow keys and its buttons as RETURN.
;
menu_key:
  ; The key: a keyboard key as it is; a device direction as an arrow key,
  ; a device button as RETURN.
  lda a:.loword(actionSource)
  cmp #SOURCE_DEVICE_FIRST
  bcc @keyboard
  lda a:.loword(keyAction)
  cmp #DEVICE_BUTTONS
  bcs @button
  asl a
  tax
  lda a:.loword(menu_direction_keys),x
  bra @dispatch
@button:
  lda #KEY_RETURN
  bra @dispatch
@keyboard:
  lda a:.loword(keyAction)
@dispatch:
  ; MP_BINDING and MP_LEVEL have their own keys; UP and DOWN move the
  ; choice; RETURN or RIGHT acts on it.
  ldx a:.loword(menuPage)
  cpx #MP_BINDING
  bne :+
  jmp .loword(@binding_menu)
:
  cpx #MP_LEVEL
  bne :+
  jmp .loword(menu_level_key)
:
  cmp #KEY_UP
  bne :+
  jmp .loword(@up)
:
  cmp #KEY_DOWN
  bne :+
  jmp .loword(@down)
:
  cpx #MP_SOUND
  beq @audio
  cmp #KEY_RETURN
  beq @enter
  cmp #KEY_RIGHT
  beq @right
  rts
@audio:
  jmp .loword(menu_audio_key)
@right:
  cpx #MP_DEVICES               ; RIGHT changes a device value
  bne :+
  jmp .loword(@device)
:
  rts
@enter:
  cpx #MP_MAIN
  beq @main
  cpx #MP_GROUPS
  beq @control_group
  cpx #MP_ACTIONS
  beq @controls
  cpx #MP_DEVICES
  bne :+
  jmp .loword(@device)
:
  rts
@main:
  lda a:.loword(menuAction)
  cmp #MAIN_SAVE
  bcc @open_page
  bne :+
  jmp .loword(settings_save)
:
  stz a:.loword(menuMode)       ; MAIN_RESUME
  rts
@open_page:
  inc a                         ; MP_GROUPS, MP_DEVICES or MP_SOUND
  sta a:.loword(menuPage)
  stz a:.loword(menuAction)
  stz a:.loword(menuAlias)
  rts
@control_group:
  lda a:.loword(menuAction)
  cmp #GROUP_BACK
  beq @back
  asl a
  tax
  lda a:.loword(menu_group_bases),x
  sta a:.loword(menuBase)
  lda a:.loword(menu_group_limits),x
  sta a:.loword(menuLimit)
  lda #MP_ACTIONS
  sta a:.loword(menuPage)
  stz a:.loword(menuAction)
  stz a:.loword(menuAlias)
  rts
@controls:
  lda a:.loword(menuAction)
  cmp a:.loword(menuLimit)
  beq @group_back               ; BACK
  clc
  adc a:.loword(menuBase)
  sta a:.loword(menuAction)     ; the BIND_ACTION
  lda #MP_BINDING
  sta a:.loword(menuPage)
  stz a:.loword(menuChoice)
  rts
@group_back:
  lda #MP_GROUPS
  sta a:.loword(menuPage)
  stz a:.loword(menuAction)
  rts
@back:
  stz a:.loword(menuPage)       ; MP_MAIN
  stz a:.loword(menuAction)
  rts
@device:
  lda a:.loword(menuAction)
  cmp #DEVICE_BACK
  beq @back
  jmp .loword(menu_device)
@up:
  lda a:.loword(menuAction)
  beq @done
  dec a:.loword(menuAction)
  stz a:.loword(menuAlias)
@done:
  rts
@down:
  lda a:.loword(menuPage)
  beq @main_limit
  cmp #MP_GROUPS
  beq @group_limit
  cmp #MP_ACTIONS
  beq @controls_limit
  cmp #MP_DEVICES
  beq @device_limit
  lda #SOUND_BACK
  bra @limit
@main_limit:
  lda #MAIN_RESUME
  bra @limit
@group_limit:
  lda #GROUP_BACK
  bra @limit
@controls_limit:
  lda a:.loword(menuLimit)
  bra @limit
@device_limit:
  lda #DEVICE_BACK
@limit:
  cmp a:.loword(menuAction)
  beq @done
  inc a:.loword(menuAction)
  stz a:.loword(menuAlias)
  rts
@binding_menu:
  cmp #KEY_UP
  beq @choice_up
  cmp #KEY_DOWN
  beq @choice_down
  cmp #KEY_RETURN
  bne @done
  lda a:.loword(menuChoice)
  beq @replace                  ; BINDING_CHANGE
  dec a
  beq @add                      ; BINDING_ADD
  dec a
  beq @delete                   ; BINDING_REMOVE
  dec a
  beq @next_alias               ; BINDING_NEXT
  dec a
  beq @both                     ; BINDING_BOTH
  jmp .loword(menu_binding_back) ; BINDING_BACK
@choice_up:
  lda a:.loword(menuChoice)
  beq @done
  dec a:.loword(menuChoice)
  rts
@choice_down:
  lda a:.loword(menuChoice)
  cmp #BINDING_BACK
  beq @done
  inc a:.loword(menuChoice)
  rts
@next_alias:
  inc a:.loword(menuAlias)
  rts
@replace:
  lda #LISTEN_CHANGE
  sta a:.loword(menuListen)
  rts
@add:
  lda #LISTEN_ADD
  sta a:.loword(menuListen)
  rts
@delete:
  jsr .loword(menu_selected_binding)
  cpx #NO_BINDING
  bcc :+
  rts
:
  lda #BIND_NONE                ; BIND_KEY; BIND_SOURCE: SOURCE_NONE
  sta a:.loword(settings+SET_BINDINGS+BIND_KEY),x
  sta a:.loword(settings+SET_BINDINGS+BIND_ACTION),x
  jmp .loword(compile_bindings)
@both:
  jsr .loword(menu_selected_binding)
  cpx #NO_BINDING
  bcc :+
  rts
:
  lda a:.loword(settings+SET_BINDINGS+BIND_SOURCE),x
  and #$00ff
  cmp #SOURCE_DEVICE_FIRST      ; keys only
  bcc :+
  rts
:
  a8
  lda #SOURCE_KEYBOARDS
  sta a:.loword(settings+SET_BINDINGS+BIND_SOURCE),x
  a16
  jmp .loword(compile_bindings)
.assert BINDING_CHANGE = 0 .and BINDING_ADD = 1 .and BINDING_REMOVE = 2 .and BINDING_NEXT = 3 .and BINDING_BOTH = 4, error
.assert BIND_SOURCE = BIND_KEY+1 .and SOURCE_NONE = 0 .and BIND_NONE = $ff, error ; @delete: one word store

; ---------------------------------------------------------------------------
; menu_binding_back: from MP_BINDING back to its action on MP_ACTIONS:
; menuAction becomes the action's place in its group again.
;
; In:       A16, DBR = this bank; menuAction (a BIND_ACTION), menuBase
; Out:      menuAction, menuPage = MP_ACTIONS
; Changes:  A
; Keeps:    X, Y, D, DBR
; Original: none
; ---------------------------------------------------------------------------
menu_binding_back:
  lda a:.loword(menuAction)
  sec
  sbc a:.loword(menuBase)
  sta a:.loword(menuAction)
  lda #MP_ACTIONS
  sta a:.loword(menuPage)
  rts

; ---------------------------------------------------------------------------
; menu_device: RETURN or RIGHT on a choice of MP_DEVICES: J13 play on or
; off (with a J13 keyboard), the next SNES MAX slot, look for the joystick
; again, the joystick to the other player, the default bindings.
;
; In:       A16 X16, DBR = this bank; menuAction below DEVICE_BACK
; Out:      the settings; the bindings compiled again
; Changes:  A, X, Y
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
menu_device:
  lda a:.loword(menuAction)
  bne @slot                     ; DEVICE_J13
  lda a:.loword(j13Available)
  bne :+
  rts
:
  lda a:.loword(j13Enabled)
  eor #J13_ON
  sta a:.loword(j13Enabled)
  lda #J13_CHOSEN
  sta a:.loword(j13Manual)
  jsl J13SettingsStore
  rts
@slot:
  dec a
  bne @joystick                 ; DEVICE_SLOT
  ; The next slot that can hold the adapter: 1, 2, 4, 5, 6, then 0 (none).
  a8
  lda a:.loword(settings+SET_SNES_SLOT)
  inc a
  cmp #SS_SLOT
  bne :+
  inc a
:
  cmp #SLOTS
  bcc :+
  lda #0
:
  sta a:.loword(settings+SET_SNES_SLOT)
  a16
  jmp .loword(compile_bindings)
@joystick:
  dec a
  bne @player                   ; DEVICE_RECHECK
  a8
  stz a:.loword(joyAbsent)
  stz a:.loword(joyPresent)     ; the first read waits for the stick again
  stz a:.loword(joyCheck)
  a16
  lda #JOY_READ_NOW
  sta a:.loword(joyUpdate)
  rts
@player:
  dec a
  bne @defaults                 ; DEVICE_JOY_PLAYER
  jmp .loword(menu_player_change)
@defaults:
  a8                            ; DEVICE_DEFAULTS
  lda #JOY_PLAYER_DEFAULT
  sta a:.loword(settings+SET_JOY_PLAYER)
  a16
  ldx #BINDINGS_BYTES-2
@copy:
  lda a:.loword(menu_default_bindings),x
  sta a:.loword(settings+SET_BINDINGS),x
  dex
  dex
  bpl @copy
  jmp .loword(compile_bindings)
.assert DEVICE_J13 = 0 .and DEVICE_SLOT = 1 .and DEVICE_RECHECK = 2 .and DEVICE_JOY_PLAYER = 3 .and DEVICE_DEFAULTS = 4, error

; ---------------------------------------------------------------------------
; menu_player_change: the joystick goes to the other player
; (SET_JOY_PLAYER), and its bindings to player actions move with it.
;
; In:       A16 X16, DBR = this bank
; Out:      settings+SET_JOY_PLAYER, the joystick's records; compiled again
; Changes:  A, X, Y; menuPlayer
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
menu_player_change:
  a8
  lda a:.loword(settings+SET_JOY_PLAYER)
  eor #JOY_PLAYER_1 ^ JOY_PLAYER_2 ; the other player
  sta a:.loword(settings+SET_JOY_PLAYER)
  a16
  and #$00ff
  sta a:.loword(menuPlayer)     ; the player it goes to: 0 player 1, 1 player 2
  ldx #0
@player_loop:
  lda a:.loword(settings+SET_BINDINGS+BIND_SOURCE),x
  and #$00ff
  cmp #SOURCE_JOYSTICK
  bne @player_next
  lda a:.loword(settings+SET_BINDINGS+BIND_ACTION),x
  and #$00ff
  cmp #ACTION_MENU
  bcs @player_next              ; not a player's action
  ldy a:.loword(menuPlayer)
  bne @to_p2
  cmp #ACTION_P2
  bcc @player_next
  sec
  sbc #ACTION_P2
  bra @player_store
@to_p2:
  cmp #ACTION_P2
  bcs @player_next
  clc
  adc #ACTION_P2
@player_store:
  a8
  sta a:.loword(settings+SET_BINDINGS+BIND_ACTION),x
  a16
@player_next:
  inx
  inx
  inx
  inx                           ; BINDING_SIZE
  cpx #BINDINGS_BYTES
  bcc @player_loop
  jmp .loword(compile_bindings)

; ---------------------------------------------------------------------------
; menu_bind: the key of the wait (keyAction, actionSource) goes to the
; action menuAction: in the selected binding (LISTEN_CHANGE), or in a free
; record (LISTEN_ADD, or the action has no binding). No free record:
; MSG_NO_ROOM. The joystick belongs to one player: a joystick key bound to
; an action of the other player moves the joystick and its player bindings
; to that player.
;
; In:       A16 X16, DBR = this bank
; Out:      the binding record; compiled again; menuListen 0
; Changes:  A, X, Y; menuPlayer, menuMessage
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
menu_bind:
  lda a:.loword(menuListen)
  cmp #LISTEN_ADD
  beq @free
  jsr .loword(menu_selected_binding)
  cpx #NO_BINDING
  bcc @store
@free:
  ldx #0
@find:
  lda a:.loword(settings+SET_BINDINGS+BIND_ACTION),x
  and #$00ff
  cmp #BIND_ACTIONS
  bcs @store                    ; a free record
  inx
  inx
  inx
  inx
  cpx #BINDINGS_BYTES
  bcc @find
  lda #MSG_NO_ROOM              ; every binding stays
  sta a:.loword(menuMessage)
  stz a:.loword(menuListen)
  rts
@store:
  lda a:.loword(actionSource)
  cmp #SOURCE_JOYSTICK
  bne @write
  lda a:.loword(menuAction)
  cmp #ACTION_MENU
  bcs @write                    ; not a player's action
  cmp #ACTION_P2
  lda #0
  bcc :+
  inc a                         ; a player 2 action: 1
:
  sta a:.loword(menuPlayer)
  phx
  lda a:.loword(settings+SET_JOY_PLAYER)
  and #$00ff
  cmp a:.loword(menuPlayer)
  beq :+
  jsr .loword(menu_player_change)
:
  plx
@write:
  jsr .loword(menu_unbind_key)
  a8
  lda a:.loword(keyAction)
  sta a:.loword(settings+SET_BINDINGS+BIND_KEY),x
  lda a:.loword(actionSource)
  sta a:.loword(settings+SET_BINDINGS+BIND_SOURCE),x
  lda a:.loword(menuAction)
  sta a:.loword(settings+SET_BINDINGS+BIND_ACTION),x
  a16
  stz a:.loword(menuListen)
  stz a:.loword(menuMessage)
  jmp .loword(compile_bindings)

; ---------------------------------------------------------------------------
; menu_unbind_key: the key keyAction of actionSource leaves every other
; binding (X: the record that takes it, kept). A binding of the same device
; or keyboards goes; one of both keyboards keeps the keyboard that is not
; taken (SOURCE_ADB and SOURCE_J13 are the bits of SOURCE_KEYBOARDS).
;
; In:       A16 X16, DBR = this bank; X the record
; Out:      the other records
; Changes:  A, Y; menuTemp, menuCount
; Keeps:    X, D, DBR
; Original: none
; ---------------------------------------------------------------------------
menu_unbind_key:
  stx a:.loword(menuTemp)
  ldy #0
@record:
  cpy a:.loword(menuTemp)
  beq @next
  lda a:.loword(settings+SET_BINDINGS+BIND_ACTION),y
  and #$00ff
  cmp #BIND_ACTIONS
  bcs @next                     ; a free record
  lda a:.loword(settings+SET_BINDINGS+BIND_KEY),y
  and #$00ff
  cmp a:.loword(keyAction)
  bne @next
  lda a:.loword(settings+SET_BINDINGS+BIND_SOURCE),y
  and #$00ff
  tax                           ; X = its source
  cmp a:.loword(actionSource)
  beq @free
  cmp #SOURCE_KEYBOARDS+1
  bcs @next                     ; another device
  lda a:.loword(actionSource)
  cmp #SOURCE_KEYBOARDS+1
  bcs @next                     ; a device key is no keyboard key
  eor #$ffff
  sta a:.loword(menuCount)
  txa
  and a:.loword(menuCount)      ; the keyboards that stay
  beq @free
  a8
  sta a:.loword(settings+SET_BINDINGS+BIND_SOURCE),y
  a16
  bra @next
@free:
  a8
  lda #BIND_NONE
  sta a:.loword(settings+SET_BINDINGS+BIND_KEY),y
  sta a:.loword(settings+SET_BINDINGS+BIND_ACTION),y
  lda #SOURCE_NONE
  sta a:.loword(settings+SET_BINDINGS+BIND_SOURCE),y
  a16
@next:
  iny
  iny
  iny
  iny                           ; BINDING_SIZE
  cpy #BINDINGS_BYTES
  bcc @record
  ldx a:.loword(menuTemp)
  rts
.assert SOURCE_KEYBOARDS = SOURCE_ADB|SOURCE_J13 .and BINDING_SIZE = 4, error

; ---------------------------------------------------------------------------
; menu_selected_binding: X = the offset of the binding menuAlias of the
; action menuAction (past the last one: the first again), or NO_BINDING.
; It sets menuFindAction and menuFindAlias and falls through into
; menu_find_binding.
;
; In:       A16 X16, DBR = this bank
; Out:      X
; Changes:  A, X, Y; menuFindAction, menuFindAlias
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
menu_selected_binding:
  lda a:.loword(menuAction)
  sta a:.loword(menuFindAction)
  lda a:.loword(menuAlias)
  sta a:.loword(menuFindAlias)
  ; Falls through into menu_find_binding.

; ---------------------------------------------------------------------------
; menu_find_binding: X = the offset of the binding menuFindAlias (counted
; from 0) of the action menuFindAction; past the last one, the first; no
; binding: NO_BINDING.
;
; In:       A16 X16, DBR = this bank; menuFindAction, menuFindAlias
; Out:      X
; Changes:  A, X, Y; menuFindAlias
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
menu_find_binding:
  ldx #0
  ldy #NO_BINDING               ; Y: the first binding of the action
@record:
  lda a:.loword(settings+SET_BINDINGS+BIND_ACTION),x
  and #$00ff
  cmp a:.loword(menuFindAction)
  bne @next
  cpy #NO_BINDING
  bne :+
  txy
:
  lda a:.loword(menuFindAlias)
  beq @done
  dec a:.loword(menuFindAlias)
@next:
  inx
  inx
  inx
  inx
  cpx #BINDINGS_BYTES
  bcc @record
  tyx                           ; past the last binding: the first
@done:
  rts

; ---------------------------------------------------------------------------
; menu_audio_key: RETURN on MP_SOUND: a level opens MP_LEVEL at its value;
; BACK goes to the main page.
;
; In:       A16 X16, DBR = this bank; A the key
; Out:      menuPage, menuChoice, menuAction
; Changes:  A, X
; Keeps:    Y, D, DBR
; Original: none
; ---------------------------------------------------------------------------
menu_audio_key:
  cmp #KEY_RETURN
  beq :+
  rts
:
  ldx a:.loword(menuAction)
  cpx #SOUND_BACK
  beq @back
  lda a:.loword(settings+SET_MUSIC_LEVEL),x
  and #$00ff
  sta a:.loword(menuChoice)
  lda #MP_LEVEL
  sta a:.loword(menuPage)
  rts
@back:
  stz a:.loword(menuPage)       ; MP_MAIN
  stz a:.loword(menuAction)
  rts
.assert SET_EFFECTS_LEVEL = SET_MUSIC_LEVEL+SOUND_EFFECTS, error

; ---------------------------------------------------------------------------
; menu_level_key: MP_LEVEL: UP and DOWN move the choice; RETURN sets the
; level of menuAction (the music or the effects), sends both levels to the
; sound code at once, and goes back to MP_SOUND.
;
; In:       A16 X16, DBR = this bank; A the key
; Out:      menuChoice; the level in the settings and in the sound code;
;           menuPage
; Changes:  A, X, Y
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
menu_level_key:
  cmp #KEY_UP
  beq @up
  cmp #KEY_DOWN
  beq @down
  cmp #KEY_RETURN
  bne @done
  ldx a:.loword(menuAction)
  lda a:.loword(menuChoice)
  a8
  sta a:.loword(settings+SET_MUSIC_LEVEL),x
  a16
  jsr .loword(mix_apply)
  lda #MP_SOUND
  sta a:.loword(menuPage)
  rts
@up:
  lda a:.loword(menuChoice)
  beq @done
  dec a:.loword(menuChoice)
  rts
@down:
  lda a:.loword(menuChoice)
  cmp #MIX_LEVEL_MAX
  beq @done
  inc a:.loword(menuChoice)
@done:
  rts

; ---------------------------------------------------------------------------
; menu_clear_apple: the text page all spaces (TEXT_SPACE), through the IIgs
; copy to bank $E0 while it is on.
;
; In:       A16 X16
; Out:      TEXT_PAGE all TEXT_SPACE
; Changes:  A, X
; Keeps:    Y, D, DBR
; Original: none
; ---------------------------------------------------------------------------
menu_clear_apple:
  a8
  lda #TEXT_SPACE
  ldx #TEXT_PAGE_SIZE-1
@clear:
  sta f:TEXT_PAGE,x
  dex
  bpl @clear
  a16
  rts

; ---------------------------------------------------------------------------
; menu_draw: draw the page menuPage in menuText and publish it.
;
; In:       A16 X16, DBR = this bank
; Out:      menuText; the text page
; Changes:  A, X, Y; the drawing variables (menuDest, menuCount, menuTemp,
;           menuFindAction, menuFindAlias, menuLevel, menuRow, menuFlat)
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
; The layout: the menu draws a page in menuText (MENU_ROWS x MENU_COLUMNS
; characters), then menu_publish copies it to the centre of the text page.
; MENU_MARK, the choice marker, becomes $55 there: the MouseText right
; arrow (ALTCHAR on).
;
menu_draw:
  a8
  lda #' '
  ldx #MENU_ROWS*MENU_COLUMNS-1
@blank:
  sta f:menuText,x
  dex
  bpl @blank
  a16
  lda a:.loword(menuPage)
  beq @main
  cmp #MP_GROUPS
  beq @controls
  cmp #MP_DEVICES
  beq @devices
  cmp #MP_SOUND
  beq @audio
  cmp #MP_LEVEL
  bne :+
  jmp .loword(menu_draw_level)
:
  cmp #MP_ACTIONS
  bne :+
  jmp .loword(menu_draw_controls)
:
  jmp .loword(menu_draw_binding)  ; MP_BINDING
@main:
  ldx #0
  ldy #.loword(menu_title_main)
  jsr .loword(menu_put)
  ldy #.loword(menu_main_text)
  lda #MAIN_CHOICES
  jmp .loword(menu_draw_choices)
@devices:
  ldx #0
  ldy #.loword(menu_title_devices)
  jsr .loword(menu_put)
  jmp .loword(menu_draw_devices)
@audio:
  ldx #0
  ldy #.loword(menu_title_sound)
  jsr .loword(menu_put)
  jmp .loword(menu_draw_audio)
@controls:
  ldx #0
  ldy #.loword(menu_title_controls)
  jsr .loword(menu_put)
  ldy #.loword(menu_group_text)
  lda #GROUP_CHOICES
  jmp .loword(menu_draw_choices)

; ---------------------------------------------------------------------------
; menu_draw_controls: MP_ACTIONS: the title of the group, each action with
; its selected binding (or UNBOUND), then BACK.
;
; In:       A16 X16, DBR = this bank
; Out:      menuText; the text page (menu_footer)
; Changes:  A, X, Y; menuFindAction, menuFindAlias, menuDest,
;           menuBindingSource, menuTemp
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
menu_draw_controls:
  ldx a:.loword(menuBase)
  cpx #0
  bne :+
  ldy #.loword(menu_title_p1)
  bra @title
:
  cpx #ACTION_P2
  bne :+
  ldy #.loword(menu_title_p2)
  bra @title
:
  ldy #.loword(menu_title_menu_key)
@title:
  ldx #0
  jsr .loword(menu_put)
  lda a:.loword(menuBase)
  sta a:.loword(menuFindAction)
  lda #MENU_LIST
  sta a:.loword(menuDest)
@action:
  stz a:.loword(menuFindAlias)
  lda a:.loword(menuFindAction)
  sec
  sbc a:.loword(menuBase)
  cmp a:.loword(menuAction)
  bne :+
  lda a:.loword(menuAlias)      ; the selected action: its selected binding
  sta a:.loword(menuFindAlias)
  a8
  ldx a:.loword(menuDest)
  lda #MENU_MARK
  sta f:menuText,x
  a16
:
  lda a:.loword(menuFindAction)
  jsr .loword(menu_name_offset)
  clc
  adc #.loword(menu_actions)
  tay
  ldx a:.loword(menuDest)
  inx
  inx                           ; ACTION_COLUMN
  jsr .loword(menu_copy_name)
  jsr .loword(menu_find_binding)
  cpx #NO_BINDING
  bcs @unbound
  lda a:.loword(settings+SET_BINDINGS+BIND_SOURCE),x
  and #$00ff
  sta a:.loword(menuBindingSource)
  lda a:.loword(settings+SET_BINDINGS+BIND_KEY),x
  and #$00ff
  pha
  lda a:.loword(menuDest)
  clc
  adc #KEY_COLUMN
  tax
  pla
  jsr .loword(menu_copy_binding_name)
  bra @next
@unbound:
  lda a:.loword(menuDest)
  clc
  adc #KEY_COLUMN
  tax
  ldy #.loword(menu_unbound)
  jsr .loword(menu_put)
@next:
  lda a:.loword(menuDest)
  clc
  adc #MENU_PITCH
  sta a:.loword(menuDest)
  inc a:.loword(menuFindAction)
  lda a:.loword(menuFindAction)
  sec
  sbc a:.loword(menuBase)
  cmp a:.loword(menuLimit)
  bcs :+
  jmp .loword(@action)
:
  ldx a:.loword(menuDest)
  ldy #.loword(menu_back)
  jsr .loword(menu_put)
  lda a:.loword(menuAction)
  cmp a:.loword(menuLimit)
  bne menu_footer
  ldx a:.loword(menuDest)
  a8
  lda #MENU_MARK
  sta f:menuText,x
  a16
  ; Falls through into menu_footer.

; ---------------------------------------------------------------------------
; menu_footer: the message menuMessage (if any) on the footer row, then
; menu_publish.
;
; In:       A16 X16, DBR = this bank
; Out:      menuText; the text page
; Changes:  A, X, Y; menuRow, menuFlat, menuDest, menuCount
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
menu_footer:
  lda a:.loword(menuMessage)
  beq @publish
  dec a
  asl a
  tax
  lda a:.loword(menu_messages),x
  tay
  ldx #MENU_FOOTER
  jsr .loword(menu_put)
@publish:
  jmp .loword(menu_publish)
.assert ACTION_COLUMN = 2, error  ; the two INXs above

; ---------------------------------------------------------------------------
; menu_draw_choices: the A choices from Y (menu_list), then the marker at
; menuAction: it falls through into menu_draw_marker.
;
; In:       A16 X16, DBR = this bank; A the count, Y the first text
; Out:      menuText; the text page
; Changes:  A, X, Y; menuCount, menuDest, menuTemp, menuRow, menuFlat
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
menu_draw_choices:
  jsr .loword(menu_list)
  lda a:.loword(menuAction)
  ; Falls through into menu_draw_marker.

; ---------------------------------------------------------------------------
; menu_draw_marker: the marker at the choice A of a list, then the footer.
;
; In:       A16 X16, DBR = this bank; A the choice
; Out:      menuText; the text page
; Changes:  A, X, Y; menuTemp, menuRow, menuFlat, menuDest, menuCount
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
menu_draw_marker:
  sta a:.loword(menuTemp)       ; X = MENU_LIST + A * MENU_PITCH
  asl a
  asl a
  asl a
  sec
  sbc a:.loword(menuTemp)
  asl a
  asl a
  asl a
  clc
  adc #MENU_LIST
  tax
  a8
  lda #MENU_MARK
  sta f:menuText,x
  a16
  jmp .loword(menu_footer)
.assert MENU_PITCH = 7*8, error   ; the shifts above: (8A - A) * 8

; ---------------------------------------------------------------------------
; menu_draw_binding: MP_BINDING: the action, its selected binding (the key
; and its source) or UNBOUND, WAITING in a wait for a key, the choices.
;
; In:       A16 X16, DBR = this bank
; Out:      menuText; the text page
; Changes:  A, X, Y; menuBindingSource, menuTemp, menuFindAction,
;           menuFindAlias, the drawing variables
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
menu_draw_binding:
  lda a:.loword(menuAction)
  jsr .loword(menu_name_offset)
  clc
  adc #.loword(menu_actions)
  tay
  ldx #0
  jsr .loword(menu_copy_name)
  jsr .loword(menu_selected_binding)
  cpx #NO_BINDING
  bcs @no_binding
  lda a:.loword(settings+SET_BINDINGS+BIND_SOURCE),x
  and #$00ff
  sta a:.loword(menuBindingSource)
  lda a:.loword(settings+SET_BINDINGS+BIND_KEY),x
  and #$00ff
  ldx #BINDING_COLUMN
  jsr .loword(menu_copy_binding_name)
  ; The source of the binding on row 1, unless the menu waits for a key.
  lda a:.loword(menuListen)
  bne @choices
  lda a:.loword(menuBindingSource)
  asl a
  sta a:.loword(menuTemp)
  asl a
  asl a
  asl a
  sec
  sbc a:.loword(menuTemp)       ; times SOURCE_NAME_SIZE
  clc
  adc #.loword(menu_sources)
  tay
  ldx #MENU_COLUMNS             ; row 1
  lda #SOURCE_NAME_SIZE
  jsr .loword(menu_copy)
  bra @choices
@no_binding:
  ldx #BINDING_COLUMN
  ldy #.loword(menu_unbound)
  jsr .loword(menu_put)
@choices:
  lda a:.loword(menuListen)
  beq :+
  ldx #MENU_COLUMNS
  ldy #.loword(menu_waiting)
  jsr .loword(menu_put)
:
  ldy #.loword(menu_binding_text)
  lda #BINDING_CHOICES
  jsr .loword(menu_list)
  lda a:.loword(menuChoice)
  jmp .loword(menu_draw_marker)
.assert SOURCE_NAME_SIZE = 16-2, error ; the shifts above: 16S - 2S

; ---------------------------------------------------------------------------
; menu_draw_devices: MP_DEVICES: the choices, their values in DEVICE_COLUMN
; and the marker.
;
; In:       A16 X16, DBR = this bank
; Out:      menuText; the text page
; Changes:  A, X, Y; the drawing variables
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
menu_draw_devices:
  ldy #.loword(menu_device_text)
  lda #DEVICE_CHOICES
  jsr .loword(menu_list)
  lda a:.loword(j13Available)
  bne :+
  ldx #MENU_LIST+DEVICE_J13*MENU_PITCH+DEVICE_COLUMN
  ldy #.loword(menu_unavailable)
  jsr .loword(menu_put)
  bra @slot_value
:
  lda a:.loword(j13Enabled)
  ldx #MENU_LIST+DEVICE_J13*MENU_PITCH+DEVICE_COLUMN
  jsr .loword(menu_draw_boolean)
@slot_value:
  lda a:.loword(settings+SET_SNES_SLOT)
  and #$00ff
  bne :+
  ldx #MENU_LIST+DEVICE_SLOT*MENU_PITCH+DEVICE_COLUMN
  ldy #.loword(menu_off)
  jsr .loword(menu_put)
  bra @joy_value
:
  ora #'0'
  a8
  sta f:menuText+MENU_LIST+DEVICE_SLOT*MENU_PITCH+DEVICE_COLUMN
  a16
@joy_value:
  lda a:.loword(joyAbsent)
  and #$00ff
  beq :+
  ldy #.loword(menu_unavailable)
  bra @joy_status
:
  ldy #.loword(menu_found)
@joy_status:
  ldx #MENU_LIST+DEVICE_RECHECK*MENU_PITCH+DEVICE_COLUMN
  jsr .loword(menu_put)
  a8
  lda #'P'
  sta f:menuText+MENU_LIST+DEVICE_JOY_PLAYER*MENU_PITCH+DEVICE_COLUMN
  lda a:.loword(settings+SET_JOY_PLAYER)
  clc
  adc #'1'                      ; 0 player 1, 1 player 2
  sta f:menuText+MENU_LIST+DEVICE_JOY_PLAYER*MENU_PITCH+DEVICE_COLUMN+1
  a16
  lda a:.loword(menuAction)
  jmp .loword(menu_draw_marker)

; ---------------------------------------------------------------------------
; menu_list: A zero-ended texts from Y (one after the other) on the rows of
; a list from MENU_LIST, MENU_PITCH apart.
;
; In:       A16 X16, DBR = this bank; A the count (1 or more), Y the first text
; Out:      menuText; Y past the last text
; Changes:  A, X, Y; menuCount, menuDest
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
menu_list:
  sta a:.loword(menuCount)
  lda #MENU_LIST
  sta a:.loword(menuDest)
@row:
  ldx a:.loword(menuDest)
  jsr .loword(menu_put)
  iny                           ; past the zero
  lda a:.loword(menuDest)
  clc
  adc #MENU_PITCH
  sta a:.loword(menuDest)
  dec a:.loword(menuCount)
  bne @row
  rts

; ---------------------------------------------------------------------------
; menu_draw_boolean: ON or OFF (the low byte of A: 0 is OFF) at menuText+X.
;
; In:       A16 X16, DBR = this bank; A the value, X the place
; Out:      menuText
; Changes:  A, X, Y
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
menu_draw_boolean:
  and #$00ff
  beq :+
  ldy #.loword(menu_on)
  bra @write
:
  ldy #.loword(menu_off)
@write:
  jmp .loword(menu_put)

; ---------------------------------------------------------------------------
; menu_draw_audio: MP_SOUND: the choices, the two levels in SOUND_COLUMN,
; and the marker.
;
; In:       A16 X16, DBR = this bank
; Out:      menuText; the text page
; Changes:  A, X, Y; the drawing variables
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
menu_draw_audio:
  ldy #.loword(menu_audio_text)
  lda #SOUND_CHOICES
  jsr .loword(menu_list)
  lda a:.loword(settings+SET_MUSIC_LEVEL)
  ldx #MENU_LIST+SOUND_COLUMN
  jsr .loword(menu_draw_level_number)
  lda a:.loword(settings+SET_EFFECTS_LEVEL)
  ldx #MENU_LIST+SOUND_EFFECTS*MENU_PITCH+SOUND_COLUMN
  jsr .loword(menu_draw_level_number)
  lda a:.loword(menuAction)
  jmp .loword(menu_draw_marker)

; ---------------------------------------------------------------------------
; menu_draw_level_number: the level (the low byte of A, 0 to MIX_LEVEL_MAX)
; at menuText+X, LEVEL_TEXT_SIZE characters of menu_level_numbers.
;
; In:       A16 X16, DBR = this bank; A the level, X the place
; Out:      menuText
; Changes:  A, X, Y; menuCount
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
menu_draw_level_number:
  and #$00ff
  asl a                         ; times LEVEL_TEXT_SIZE
  clc
  adc #.loword(menu_level_numbers)
  tay
  lda #LEVEL_TEXT_SIZE
  jmp .loword(menu_copy)
.assert LEVEL_TEXT_SIZE = 2, error ; the ASL above

; ---------------------------------------------------------------------------
; menu_draw_level: MP_LEVEL: the title, the levels 0 to MIX_LEVEL_MAX, one
; on each row of the list, and the marker at menuChoice.
;
; In:       A16 X16, DBR = this bank
; Out:      menuText; the text page
; Changes:  A, X, Y; menuLevel, menuDest, menuTemp, the drawing variables
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
menu_draw_level:
  ldx #0
  ldy #.loword(menu_level_music)
  lda a:.loword(menuAction)
  beq :+
  ldy #.loword(menu_level_effects)
:
  jsr .loword(menu_put)
  lda #MENU_LIST+LEVEL_COLUMN
  sta a:.loword(menuDest)
  stz a:.loword(menuLevel)
@row:
  lda a:.loword(menuLevel)
  ldx a:.loword(menuDest)
  jsr .loword(menu_draw_level_number)
  lda a:.loword(menuDest)
  clc
  adc #LEVEL_PITCH
  sta a:.loword(menuDest)
  inc a:.loword(menuLevel)
  lda a:.loword(menuLevel)
  cmp #MIX_LEVEL_MAX+1
  bcc @row
  ; The marker at the row of menuChoice.
  lda a:.loword(menuChoice)
  sta a:.loword(menuTemp)
  asl a
  asl a
  asl a
  sec
  sbc a:.loword(menuTemp)
  asl a
  asl a                         ; times LEVEL_PITCH
  clc
  adc #MENU_LIST
  tax
  a8
  lda #MENU_MARK
  sta f:menuText,x
  a16
  jmp .loword(menu_footer)
.assert LEVEL_PITCH = 7*4, error ; the shifts above: (8A - A) * 4
.assert MENU_LIST+MIX_LEVEL_MAX*LEVEL_PITCH < MENU_FOOTER, error ; the levels end above the footer

; ---------------------------------------------------------------------------
; menu_copy_binding_name: at X the name of the key A of the source
; menuBindingSource: the name of a key without a character
; (menu_named_keys), "PAD" and the character of a keypad key (keypadKeys),
; the unshifted character of another key (asciiKeys), else KEY and the code
; in hex; for a device the name of its device key (the joystick, or a pad).
;
; In:       A16 X16, DBR = this bank; A the key, X the place in menuText;
;           menuBindingSource
; Out:      menuText
; Changes:  A, X, Y; menuTemp, menuKeyName, menuPlayer, menuCount
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
menu_copy_binding_name:
  phx
  ldx a:.loword(menuBindingSource)
  cpx #SOURCE_DEVICE_FIRST
  bcc :+
  jmp .loword(@device)
:
  tax                           ; X = the key code
  a8
  stx a:.loword(menuTemp)
  lda #' '
  ldy #NAME_SIZE-1
@blank:
  sta a:.loword(menuKeyName),y
  dey
  bpl @blank
  ldy #NAMED_KEYS-1
@named:
  txa
  cmp a:.loword(menu_named_keys),y
  beq @long
  dey
  bpl @named
  ldx #KEYPAD_CHARS-1
@keypad:
  lda f:keypadKeys,x
  cmp a:.loword(menuTemp)
  beq @keypad_key
  dex
  bpl @keypad
  ldy #KEY_CHARACTERS-1
@character:
  a16
  lda a:.loword(menu_key_characters),y
  and #$00ff
  tax
  a8
  lda f:asciiKeys,x
  cmp a:.loword(menuTemp)
  beq @character_key
  dey
  bpl @character
  ldx a:.loword(menuTemp)
  bra @hex
@keypad_key:
  txa                           ; the keypad character
  sta a:.loword(menuKeyName+PAD_PREFIX)
  ldy #PAD_PREFIX-1
@prefix:
  lda a:.loword(menu_pad_prefix),y
  sta a:.loword(menuKeyName),y
  dey
  bpl @prefix
  bra @name
@character_key:
  txa                           ; the character, a letter as a capital
  cmp #'a'
  bcc :+
  cmp #'z'+1
  bcs :+
  and #<~CASE_BIT
:
  sta a:.loword(menuKeyName)
@name:
  a16
  ldy #.loword(menuKeyName)
  plx
  jmp .loword(menu_copy_name)
@long:
  .a8
  cpy #FUNCTION_FIRST
  bcs @function
  a16
  tya
  jsr .loword(menu_name_offset)
  clc
  adc #.loword(menu_key_names)
  bra @copy
@function:                      ; F and the number of the key, 1-15
  .a8
  lda #'F'
  sta a:.loword(menuKeyName)
  tya
  sec
  sbc #FUNCTION_FIRST-1
  cmp #DECIMAL
  bcc @digit
  sbc #DECIMAL                  ; carry is set
  pha
  lda #'1'
  sta a:.loword(menuKeyName+1)
  pla
  ora #'0'
  sta a:.loword(menuKeyName+2)
  jmp .loword(@name)
@digit:
  ora #'0'
  sta a:.loword(menuKeyName+1)
  jmp .loword(@name)
@hex:
  ; KEY and the code in two hex digits; menuPlayer keeps the code across
  ; menu_put.
  a16
  txa
  sta a:.loword(menuPlayer)     ; the code
  ldy #.loword(menu_key_prefix)
  plx
  jsr .loword(menu_put)
  lda a:.loword(menuPlayer)
  pha
  lsr a
  lsr a
  lsr a
  lsr a
  tay
  a8
  lda a:.loword(menu_hex),y
  sta f:menuText,x
  inx
  a16
  pla
  and #$000f                    ; the low digit
  tay
  a8
  lda a:.loword(menu_hex),y
  sta f:menuText,x
  a16
  rts
@device:
  jsr .loword(menu_name_offset)
  ldx a:.loword(menuBindingSource)
  cpx #SOURCE_PAD1
  bcs @pad
  clc
  adc #.loword(menu_device_names)
  bra @copy
@pad:
  clc
  adc #.loword(menu_pad_names)
@copy:
  .a16
  tay
  plx
  jmp .loword(menu_copy_name)
.assert SOURCE_JOYSTICK+1 = SOURCE_PAD1 .and SOURCE_PAD2 = SOURCE_PAD1+1, error ; @device: the joystick, else a pad

; ---------------------------------------------------------------------------
; menu_name_offset: A = A * NAME_SIZE (8A + 2A), the offset of a name in
; menu_actions, menu_key_names, menu_device_names or menu_pad_names.
;
; In:       A16, DBR = this bank; A the name number
; Out:      A16 the offset
; Changes:  A; menuTemp
; Keeps:    X, Y, D, DBR
; Original: none
; ---------------------------------------------------------------------------
menu_name_offset:
  asl a
  sta a:.loword(menuTemp)
  asl a
  asl a
  clc
  adc a:.loword(menuTemp)
  rts
.assert NAME_SIZE = 10, error ; 8A + 2A

; ---------------------------------------------------------------------------
; menu_put: the zero-ended text at Y (in this bank) to menuText+X; it stops
; with Y at the zero. A text fits on its row.
;
; In:       A16 X16, DBR = this bank; Y the text, X the place
; Out:      menuText; X past the text, Y at its zero; A16
; Changes:  A, X, Y
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
menu_put:
  a8
@byte:
  lda a:0,y
  beq @done
  sta f:menuText,x
  inx
  iny
  bra @byte
@done:
  a16
  rts
; ---------------------------------------------------------------------------
; menu_copy_name: NAME_SIZE bytes from Y to menuText+X: it falls through
; into menu_copy with the count.
;
; In:       A16 X16, DBR = this bank; Y the name, X the place
; Out:      menuText; X and Y past the name
; Changes:  A, X, Y; menuCount
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
menu_copy_name:
  lda #NAME_SIZE
  ; Falls through into menu_copy.

; ---------------------------------------------------------------------------
; menu_copy: A bytes (1 or more) from Y to menuText+X.
;
; In:       A16 X16, DBR = this bank; A the count, Y the source, X the place
; Out:      menuText; X and Y past the bytes; A16
; Changes:  A, X, Y; menuCount
; Keeps:    D, DBR
; Original: none
; ---------------------------------------------------------------------------
menu_copy:
  sta a:.loword(menuCount)
  a8
@byte:
  lda a:0,y
  sta f:menuText,x
  inx
  iny
  a16
  dec a:.loword(menuCount)
  a8
  bne @byte
  a16
  rts

; ---------------------------------------------------------------------------
; menu_publish: copy the MENU_ROWS x MENU_COLUMNS layout to the centre of
; the 40-column text page (menu_apple_rows) with bit 7 flipped: a character
; of menuText becomes normal text, and MENU_MARK the MouseText arrow.
;
; In:       A16 X16, DBR = this bank
; Out:      the text page
; Changes:  A, X; menuRow, menuFlat, menuDest, menuCount
; Keeps:    Y, D, DBR
; Original: none
; ---------------------------------------------------------------------------
menu_publish:
  stz a:.loword(menuRow)
  stz a:.loword(menuFlat)
@row:
  lda a:.loword(menuRow)
  asl a
  tax
  lda a:.loword(menu_apple_rows),x
  sta a:.loword(menuDest)
  lda #MENU_COLUMNS
  sta a:.loword(menuCount)
@column:
  ldx a:.loword(menuFlat)
  a8
  lda f:menuText,x
  eor #TEXT_NORMAL
  ldx a:.loword(menuDest)
  sta f:TEXT_PAGE,x
  a16
  inc a:.loword(menuFlat)
  inc a:.loword(menuDest)
  dec a:.loword(menuCount)
  bne @column
  inc a:.loword(menuRow)
  lda a:.loword(menuRow)
  cmp #MENU_ROWS
  bcc @row
  rts

; The menu texts. A choice text starts with two spaces: the marker and a
; gap.
menu_direction_keys: .word KEY_RIGHT,KEY_LEFT,KEY_DOWN,KEY_UP  ; device keys 0-3
.assert DEV_RIGHT = 0 .and DEV_LEFT = 1 .and DEV_DOWN = 2 .and DEV_UP = 3, error
.assert DEV_PAD_RIGHT = 0 .and DEV_PAD_LEFT = 1 .and DEV_PAD_DOWN = 2 .and DEV_PAD_UP = 3, error
menu_title_main: .asciiz "SUPER MARIO BROS. OPTIONS"
menu_title_controls: .asciiz "CONTROLS"
menu_title_p1: .asciiz "PLAYER 1"
menu_title_p2: .asciiz "PLAYER 2"
menu_title_menu_key: .asciiz "MENU KEY (ESC ALWAYS)"
menu_title_devices: .asciiz "DEVICES"
menu_title_sound: .asciiz "SOUND"
menu_key_prefix: .asciiz "KEY "
menu_pad_prefix: .byte "PAD "      ; menu_copy_binding_name: a keypad key
menu_hex: .byte "0123456789ABCDEF"
.assert menu_hex-menu_pad_prefix = PAD_PREFIX, error
menu_unavailable: .asciiz "NO DEVICE"
menu_found: .asciiz "FOUND"
menu_unbound: .asciiz "UNBOUND"
menu_waiting: .asciiz "WAITING"
menu_back: .asciiz "  BACK"
menu_on: .asciiz "ON"
menu_off: .asciiz "OFF"
menu_messages: .word .loword(menu_saved),.loword(menu_full),.loword(menu_error)  ; MSG_*
menu_saved: .asciiz "SETTINGS SAVED"
menu_full: .asciiz "BINDINGS FULL"
menu_error: .asciiz "SAVE FAILED"
menu_main_text:
  .asciiz "  CONTROLS"
  .asciiz "  DEVICES"
  .asciiz "  SOUND"
  .asciiz "  SAVE"
  .asciiz "  RESUME"
menu_group_text:
  .asciiz "  PLAYER 1"
  .asciiz "  PLAYER 2"
  .asciiz "  MENU KEY"
  .asciiz "  BACK"
menu_binding_text:
  .asciiz "  CHANGE"
  .asciiz "  ADD"
  .asciiz "  REMOVE"
  .asciiz "  NEXT BINDING"
  .asciiz "  BOTH KEYBOARDS"
  .asciiz "  BACK"
menu_device_text:
  .asciiz "  J13 PLAY"
  .asciiz "  SNES MAX SLOT"
  .asciiz "  RECHECK JOYSTICK"
  .asciiz "  JOYSTICK PLAYER"
  .asciiz "  RESTORE DEFAULT BINDINGS"
  .asciiz "  BACK"
menu_audio_text:
  .asciiz "  MUSIC VOLUME"
  .asciiz "  EFFECTS VOLUME"
  .asciiz "  BACK"
menu_level_music: .asciiz "MUSIC VOLUME"
menu_level_effects: .asciiz "EFFECTS VOLUME"
menu_level_numbers: .byte "0 1 2 3 4 5 6 7 8 9 101112131415" ; LEVEL_TEXT_SIZE each
.assert *-menu_level_numbers = (MIX_LEVEL_MAX+1)*LEVEL_TEXT_SIZE, error
firmware_signature: .byte "GSVGA"   ; firmware_wait: the GetStatus signature
.assert *-firmware_signature = SS_SIGNATURE_SIZE, error
; MP_GROUPS: the first action and the count of actions of each group.
menu_group_bases: .word 0,ACTION_P2,ACTION_MENU
menu_group_limits: .word PLAYER_ACTIONS,PLAYER_ACTIONS,1

; The menu state.
.a16
menuSavedColour: .byte 0        ; TBCOLOR before the menu
menuSavedText: .byte 0          ; RDTEXT, RDPAGE2, RD80VID before the menu
menuSavedPage: .byte 0
menuSavedColumns: .byte 0
menuShadow: .byte 0             ; SHADOW before the menu
menuDirty: .word 0              ; 1: draw the page again
menuPage: .word 0               ; MP_*
menuAction: .word 0             ; the choice; on MP_BINDING the action
menuAlias: .word 0              ; the selected binding of the action
menuChoice: .word 0             ; the choice on MP_BINDING, the level on MP_LEVEL
menuBase: .word 0               ; MP_ACTIONS: the first action of the group
menuLimit: .word 0              ; MP_ACTIONS: the count of actions (BACK)
menuPlayer: .word 0             ; menu_player_change, menu_bind: the player, 0 player 1,
                                ; 1 player 2; menu_copy_binding_name: the key code of KEY nn
menuListen: .word 0             ; LISTEN_*: the menu waits for a key; 0 no
menuMessage: .word 0            ; MSG_*; 0 none
menuSerial: .word 0             ; inputSerial at the last key
menuTime: .word 0               ; inputClock at the last sample
menuFindAction: .word 0         ; menu_find_binding: the action
menuFindAlias: .word 0          ; menu_find_binding: the binding number
menuDest: .word 0               ; the menuText offset of the next row
menuBindingSource: .word 0      ; menu_copy_binding_name: the source
menuTemp: .word 0               ; a scratch word: the factor of the multiplies (menu_draw_marker,
                                ; menu_draw_binding, menu_draw_level, menu_name_offset), the
                                ; record of menu_unbind_key, the key of menu_copy_binding_name
menuKeyName: .res NAME_SIZE     ; menu_copy_binding_name: a key named by its character
menuCount: .word 0              ; menu_list, menu_copy: the count
menuLevel: .word 0              ; menu_draw_level: the level of the row
menuRow: .word 0                ; menu_publish: the row
menuFlat: .word 0               ; menu_publish: the menuText offset
firmwareStatus: .res ::SS_STATUS_SIZE ; firmware_wait: the GetStatus bytes (monitor_sense reads the sense byte)
menuText: .res MENU_ROWS*MENU_COLUMNS ; the page that menu_publish shows
