; The 65816 processor: the status bits, the opcodes that the code writes as
; instructions, and the macros that set the register widths (W65C816S data
; sheet). src/game.s and src/boot.s include this file.

; The processor status bits (P). REP clears the given bits, SEP sets them.
P_CARRY         = $01
P_ZERO          = $02
P_IRQ_OFF       = $04           ; set: the CPU ignores IRQ
P_DECIMAL       = $08
P_X8            = $10           ; set: X and Y are 8 bits (native mode)
P_M8            = $20           ; set: A and memory operations are 8 bits (native mode)
P_OVERFLOW      = $40
P_NEGATIVE      = $80

; The opcodes that the code writes as instructions.
OPCODE_JMP      = $4C           ; JMP absolute: src/input_j13.s probeADB writes it into CaptureInput
OPCODE_RTL      = $6B           ; RTL: the way back of the disk call stub (src/input_disk_bridge.s)

; Register widths. The sources assemble with .smart, so ca65 follows the REP
; or SEP of each macro and gives the immediate operands after it their
; size. .smart follows the source order only: a label that code with
; another width reaches needs its own .a8/.a16/.i8/.i16 (scripts/width_lint.py
; checks the immediates).
.macro a8                       ; A and memory: 8 bits
  sep #::P_M8
.endmacro
.macro a16                      ; A and memory: 16 bits
  rep #::P_M8
.endmacro
.macro x16                      ; X and Y: 16 bits
  rep #::P_X8
.endmacro
.macro ax8                      ; A, X and Y: 8 bits
  sep #::P_M8|::P_X8
.endmacro
.macro ax16                     ; A, X and Y: 16 bits
  rep #::P_M8|::P_X8
.endmacro
