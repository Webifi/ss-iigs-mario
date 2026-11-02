; The IIgs program of the game: the handoff from the boot loader, the
; startup, the main loop, and the place of every routine and data file.
;
; The boot loader (src/boot.s) loads every file, then jumps to game_handoff
; in emulation mode. The startup clears the RAM, starts the clock and the
; input, starts the card program, and runs the main loop: one frame of the
; original for each frame of the DOC clock (src/clock.s).
;
; Files that end in .inc and are not in src/ are data that the build writes
; (build/game).
.setcpu "65816"
.smart                          ; ca65 follows REP and SEP for the immediate sizes
.include "w65c816.inc"          ; the processor status bits and the width macros
.include "iigs.inc"             ; the IIgs registers and the firmware entries
.include "second_sight.inc"     ; the host side of the Second Sight card
.include "host_memory.inc"      ; the memory map of the host
.include "packet_layout.inc"    ; the update packet to the card
.include "sound.inc"            ; the DOC voices
.include "game/state.inc"       ; the game's state: the object records and the shared variables
.include "secondsight_symbols.inc" ; the Second Sight symbols (build/secondsight/secondsight.elf)
.include "host_data.inc"        ; the labels of the host data (build/game/host_data.s)
.include "sound_bank.inc"       ; the DOC layout and volume tables (build/game, scripts/sound_bank.py)

; src/iigs.cfg places the areas that host_memory.inc names for the code: the
; link stops when the two disagree.
.import __NATIVE_START__, __NATIVE_SIZE__, __BOOT_START__, __BOOT_SIZE__
.import __SOUND_START__, __SOUND_SIZE__, __GAMEPLAY_START__, __GAMEPLAY_SIZE__
.import __OBJECTS_START__, __OBJECTS_SIZE__, __STATE_START__, __STATE_SIZE__
.import __GAMEDATA_RUN_START__, __GAMEDATA_RUN_SIZE__
.import __AREASTATE_RUN__, __AREASTATE_SIZE__, __TITLESTATE_RUN__, __TITLESTATE_SIZE__ ; src/game/flow.s clears them
.import __GAMEDATA_LOAD_START__, __GAMEDATA_LOAD__, __GAMEDATA_RUN__, __GAMEDATA_SIZE__
.import __SYSRAM_START__, __SYSRAM_SIZE__, __SYSPAGE_START__, __SOUNDPAGE_START__
.import __PACKET_START__, __PACKET_SIZE__, __PENDING_START__, __PENDING_SIZE__
.import __INPUT_START__, __INPUT_SIZE__, __DATA03_START__
.assert __NATIVE_START__ = NATIVE_CODE && __NATIVE_SIZE__ = NATIVE_CODE_SIZE, error, "iigs.cfg NATIVE"
.assert __BOOT_START__ = BOOT_CODE && __BOOT_SIZE__ = BOOT_CODE_SIZE, error, "iigs.cfg BOOT"
.assert __SOUND_START__ = SOUND_CODE && __SOUND_SIZE__ = SOUND_CODE_SIZE, error, "iigs.cfg SOUND"
.assert __GAMEPLAY_START__ = GAMEPLAY_CODE && __GAMEPLAY_SIZE__ = GAMEPLAY_CODE_SIZE, error, "iigs.cfg GAMEPLAY"
.assert __OBJECTS_START__ = GAME_OBJECTS && __OBJECTS_SIZE__ = GAME_OBJECTS_SIZE, error, "iigs.cfg OBJECTS"
.assert __STATE_START__ = GAME_STATE && __STATE_SIZE__ = GAME_STATE_SIZE, error, "iigs.cfg STATE"
.assert __GAMEDATA_RUN_START__ = GAME_DATA && __GAMEDATA_RUN_SIZE__ = GAME_DATA_SIZE, error, "iigs.cfg GAMEDATA_RUN"
.assert __GAMEDATA_LOAD_START__ = GAME_DATA_LOAD, error, "iigs.cfg GAMEDATA_LOAD"
.assert __SYSRAM_START__ = SYSTEM_RAM && __SYSRAM_SIZE__ = SYSTEM_RAM_SIZE, error, "iigs.cfg SYSRAM"
.assert __SYSPAGE_START__ = 0 && __SOUNDPAGE_START__ = SOUND_PAGE, error, "iigs.cfg pages" ; SYSPAGE: offsets from SYSTEM_PAGE
.assert __PACKET_START__ = PACKET_BUFFER && __PACKET_SIZE__ = PACKET_BUFFER_SIZE, error, "iigs.cfg PACKET"
.assert __PENDING_START__ = PENDING_WRITES && __PENDING_SIZE__ = PENDING_WRITES_SIZE, error, "iigs.cfg PENDING"
.assert __INPUT_START__ = INPUT_CODE && __INPUT_SIZE__ = INPUT_CODE_SIZE, error, "iigs.cfg INPUT"
.assert __DATA03_START__ = PAYLOAD, error, "iigs.cfg DATA03"

; The Second Sight command handshake. The host writes a command to
; SS_COMMAND, then waits for the card at SS_HANDSHAKE. A missing or stopped
; card makes each wait time out, and the game stops at failed.
SS_POLLS        = $FFFF         ; the handshake reads before a wait fails

.segment "BOOT"
.a8
.i8

; game_handoff: the boot loader jumps here in emulation mode with every file
; loaded. Native mode, the game stack, D and DBR, then the startup.
game_handoff:
        sei                             ; no IRQ until clock_start sets its vector
        clc
        xce                             ; native 65816 mode
        rep #$30
.a16
.i16
        ldx #STACK_TOP
        txs
        lda #SYSTEM_PAGE
        tcd
        sep #$20
.a8
        lda #0
        pha
        plb                             ; DBR = bank 0
        jmp startup

; ram_clear FIRST, LAST: fill FIRST up to (not including) LAST with zeros.
; It writes two zeros at FIRST, then MVN copies each byte to the next one.
; Call with A16 X16. Changes: A, X, Y; DBR becomes the bank of FIRST.
.macro ram_clear first, last
        lda #0
        sta f:first
        ldx #.loword(first)
        ldy #.loword(first)+1
        lda #(last)-(first)-2
        mvn #^(first),#^(first)
.endmacro

; startup: move the original's tables into place, clear the RAM, start the
; clock, the input and the card program, then run the main loop. It never
; returns.
startup:
        rep #$30
.a16
.i16
; The original's tables to their place in bank 0, where the boot loader ran.
        ldx #.loword(__GAMEDATA_LOAD__)
        ldy #.loword(__GAMEDATA_RUN__)
        lda #__GAMEDATA_SIZE__-1
        mvn #^__GAMEDATA_LOAD__,#^__GAMEDATA_RUN__
; The game's RAM and the system pages are in the text pages ($0400-$0BFF):
; no copy to bank $E0, so each write there runs at the fast speed, and the
; Apple screen keeps the spaces of the boot loader (boot.s black_screen)
; while the clears below write zeros there. The options menu lets text page
; 1 through while it shows (src/menu.s).
        sep #$20
.a8
        lda f:SHADOW
        ora #SHADOW_TEXT1|SHADOW_TEXT2
        sta f:SHADOW
        rep #$20
.a16
        jsl input_keep_holes            ; src/input_disk_bridge.s: the disk driver's bytes in the text page
        ram_clear SYSTEM_PAGE, SYSTEM_PAGE+$100
        ram_clear SOUND_PAGE, SOUND_PAGE+$100
        ram_clear SYSTEM_RAM, SYSTEM_RAM+SYSTEM_RAM_SIZE
        ram_clear GAME_OBJECTS, GAME_OBJECTS+GAME_OBJECTS_SIZE
        ram_clear GAME_STATE, GAME_STATE+GAME_STATE_SIZE
        sep #$20
.a8
        lda #0
        pha
        plb                             ; DBR = bank 0 again (the MVN changed it)
        lda #secondsight_READY_TOKEN    ; the card arms receive buffer 0 first
        sta packet_token
        jsl sound_start                 ; src/sound.s: the voices
        jsl monitor_sense               ; src/menu.s: the monitor, from the firmware's status
        jsr clock_start                 ; the DOC timer interrupt, at the rate of that monitor's mode
        jsl input_start                 ; src/input.s: the devices and the settings
; RunCode: the card starts its program at entry_start with the MMU of
; secondsight.ld game_*: there the image runs where the disk loaded it.
        lda #SS_RUN_CODE
        sta f:SS_COMMAND
        jsl command_ready               ; src/menu.s
        lda #secondsight_game_cbr
        sta f:SS_DATA_OUT
        lda #secondsight_game_cbar
        sta f:SS_DATA_OUT
        lda #secondsight_game_bbr
        sta f:SS_DATA_OUT
        lda #<secondsight_entry_start
        sta f:SS_DATA_OUT
        lda #>secondsight_entry_start
        sta f:SS_DATA_OUT
        jsl command_done
        jsl game_power_on               ; src/game/frame.s: the original's start: the title follows
        jmp main_loop

; failed: the card did not answer. Stop here; the screen keeps what it shows.
failed:
        bra failed

; main_loop: one frame of the original for each frame of the clock. The
; game consumes frames_due one at a time; if it falls behind, it runs them
; back to back. The count is eight bits and wraps at 256. The menu clears
; it on exit (src/menu.s); the card can skip pictures (src/packet.s).
; Between frames the menu key opens the options menu (src/menu.s).
main_loop:
        sep #$30
.a8
.i8
        lda frames_due
        bne @frame
        jsl input_idle                  ; src/input.s: the joystick, in time that the game does not use
        bra main_loop
@frame:
        dec frames_due
        jsl input_frame                 ; src/input.s: the pads of this frame, and the menu key
        bcs @menu
        jsl game_frame                  ; src/game/frame.s: the original's frame
        bra main_loop
@menu:
        jsl options_menu                ; src/menu.s
        bra main_loop

.assert ^game_handoff = 0, error        ; the boot loader jumps here with JML

; The routines and their data, by segment (src/iigs.cfg). NATIVE is bank 0
; system code; SOUND is bank 0 too (the sound unit model and the original's
; sound program, which calls it with JSR); GAMEPLAY is bank 1 (the game
; logic, JSR within it); INPUT is the input and the menu.
.segment "NATIVE"
.include "clock.s"
.include "packet.s"
.include "stream.s"

.segment "SOUND"
.include "sound.s"
.include "game/sound_program.s"

.segment "GAMEPLAY"
.include "game/frame.s"
.include "game/title.s"
.include "game/flow.s"
.include "game/screen.s"
.include "game/area.s"
.include "game/player.s"
.include "game/objects.s"
.include "game/movement.s"
.include "game/enemies.s"
.include "game/collision.s"
.include "game/score.s"
.include "game/sprites.s"

.segment "INPUT"
.include "input.s"              ; the input, the options menu, the settings (it includes the rest)
