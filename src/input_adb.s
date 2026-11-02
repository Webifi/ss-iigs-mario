; The ADB capture: the key bytes of the ADB keyboard become events in
; inputRing with the tick count (queueInput). Part of the input
; (src/input.s), in its scope; input_capture calls CaptureInput at each
; interrupt (the DOC timer's and the ADB GLU's) when the GLU has work.
;
; The talk to the keyboard (Apple IIgs Firmware Reference, chapter 9, the
; microcontroller commands and its status byte; Hardware Reference,
; chapter 6, keyboard register 0): input_start turns the microcontroller's
; keyboard poll off and the keyboard's service request on. A status byte
; with ADB_KEY_REQUEST says that a device asks for service: the capture
; sends KEY_TALK, and the reply comes as a status byte with
; ADB_REPLY_FOLLOWS and the count, then the key bytes (bit 7 set: a release;
; $FF: no key).
;
; The mouse is not an input of this game, but input_start turns its
; interrupt on, and a full MOUSEDATA keeps the interrupt asking until it is
; read. So the capture reads the mouse bytes, in X and Y pairs (Firmware
; Reference, chapter 10: X, then Y; a Y byte whose X is gone is read once
; and dropped). After MOUSE_TALKS mouse moves the keyboard gets a talk even
; with no request, so a key pressed while the mouse moves is asked for.
;
; The ring entry (INPUT_EVENT_SIZE bytes; src/input.s drain reads it,
; queueInput here and src/input_j13.s queue write it):
;   offset       size  field
;   INPUT_TIME      2  inputClock when the event came
;   INPUT_TYPE      2  INPUT_KEY (ADB) or INPUT_J13
;   INPUT_VALUE     2  the key code; bit 7 (KEY_RELEASE): a release
;   (6)             2  not used: an entry of a power-of-two size wraps
;                      with one AND
;
; Routines:
;   CaptureInput   read the ADB bytes and the mouse bytes, talk to the keyboard
;   queueInput     one key event into inputRing
.a16
.i16
KEY_TALK = GLU_TALK+ADB_KEYBOARD  ; Talk register 0 of the keyboard: its keys
MOUSE_TALKS = 4              ; after this many mouse moves the keys get a turn
INPUT_EVENT_SIZE = 8         ; an inputRing entry (the table above)
INPUT_RING_SIZE = 1024       ; a power of two
INPUT_TIME = 0               ; an entry: inputClock when it came
INPUT_TYPE = 2               ; INPUT_KEY or INPUT_J13
INPUT_VALUE = 4              ; the key byte (bit 7: a release)
INPUT_KEY = 0                ; INPUT_TYPE: an ADB keyboard key byte
INPUT_J13 = 2                ; INPUT_TYPE: a J13 keyboard key byte
HELD_ADB = 1                 ; keyHeld: the ADB keyboard holds the key
HELD_J13 = 2                 ; keyHeld: the J13 keyboard holds the key
; The microcontroller status byte (Firmware Reference, table 9-3).
ADB_REPLY_FOLLOWS = $80      ; reply bytes follow
ADB_STATUS_ERROR = $40       ; the microcontroller had an error (abort/flush)
ADB_STATUS_ESC = $20         ; a press of the Desktop Manager keys (control, open apple, ESC)
ADB_KEY_REQUEST = $08        ; a device asks for service (SRQ)
ADB_REPLY_BITS = $07         ; the reply bytes - 1
; Keyboard register 0 (Hardware Reference, table 6-10).
ADB_NO_KEY = $FF             ; a reply byte: no key
KEY_RELEASE = $80            ; a key byte: a release
.assert (INPUT_EVENT_SIZE & (INPUT_EVENT_SIZE-1)) = 0 .and INPUT_VALUE+2 <= INPUT_EVENT_SIZE, error

; ---------------------------------------------------------------------------
; CaptureInput: read the ADB bytes of the GLU (status bytes and key bytes)
; and the mouse bytes, then send the keyboard a talk when it asked for one.
; A status byte that is not a reply header ends the read of DATAREG: the
; talk below answers its request, and the reply comes with the next
; interrupt.
;
; Self-changing code: J13Pump (src/input_j13.s) sets the operand of
; captureStatusMask to 0 while a row read owns DATAREG, so that this code
; does not read the row's reply; probeADB makes captureTalk a JMP to
; withoutRawKeys when no ADB keyboard answers, so that no empty talks go out.
;
; In:       A8 or A16, X16, DBR = this bank
; Out:      key events in inputRing; keyReply, keyTalk, keyPending,
;           keyHeaderByte, mouseTalkCount; A16
; Changes:  A, X; irqValue
; Keeps:    Y, D, DBR
; Time:     about 60 cycles and two GLU reads for each key byte, and 65
;           for its queueInput; about 40 cycles and two KMSTATUS reads at
;           the end of a pass (counted from the 65816 cycle table)
; Original: none
; ---------------------------------------------------------------------------
CaptureInput:
  a8
  ; A byte in DATAREG: a key byte of the reply that runs, else a status
  ; byte (captureHeader).
captureByte:
              lda f:KMSTATUS
captureStatusMask: and #KM_DATA_FULL    ; the operand is patched (J13Pump)
              beq captureMouse
              lda f:DATAREG
              ldx a:.loword(keyReply)
              beq captureHeader
              cmp #ADB_NO_KEY
              beq capturedKey
              sta a:.loword(irqValue)
              lda #0
              sta a:.loword(irqValue+1)
              a16
              jsr a:.loword(queueInput)
              a8
capturedKey:  dec a:.loword(keyReply)
              bne captureByte
              stz a:.loword(keyTalk)    ; the reply is complete
              bra captureByte
  ; A status byte: a request makes a talk due; a reply header gives the
  ; count of the key bytes that follow.
captureHeader:
              sta a:.loword(keyHeaderByte)
              bit #ADB_KEY_REQUEST
              beq noKeyRequest
              ldx #1
              stx a:.loword(keyPending)
noKeyRequest: lda a:.loword(keyHeaderByte)
              bpl captureMouse          ; bit 7 clear: no reply follows; the pass ends
              and #ADB_REPLY_BITS
              beq emptyKeyReply
              inc a
              sta a:.loword(keyReply)   ; the key bytes that follow
              bra captureByte
emptyKeyReply:
              stz a:.loword(keyTalk)    ; the talk got no key
              bra captureByte
  ; The mouse: a pair of X and Y bytes, or a lone Y byte, read and dropped.
captureMouse: lda f:KMSTATUS
              bpl captureTalk           ; KM_MOUSE_FULL
              bit #KM_MOUSE_Y
              beq mouseXY
              lda f:MOUSEDATA           ; drop an orphan Y, not a pair
              bra captureTalk
mouseXY:      lda f:MOUSEDATA           ; X, then Y: not used by this game
              lda f:MOUSEDATA
              inc a:.loword(mouseTalkCount)
              ldx a:.loword(mouseTalkCount)
              cpx #MOUSE_TALKS
              bcc captureTalk
              ldx #1                    ; the keys get a turn in the motion
              stx a:.loword(keyPending)
  ; The talk: when one is due, none runs and the command register is free.
captureTalk:  ldx a:.loword(keyPending)  ; probeADB may make this a JMP withoutRawKeys
              beq inputCaptured
              ldx a:.loword(keyTalk)
              bne inputCaptured         ; a talk runs already
              lda f:KMSTATUS
              lsr a                     ; KM_COMMAND_FULL: the GLU is busy
              bcs inputCaptured
              lda #KEY_TALK
              sta f:DATAREG
              ldx #1
              stx a:.loword(keyTalk)
              stz a:.loword(mouseTalkCount)
              ; Falls through: the store of withoutRawKeys ends the request.
withoutRawKeys:
              stz a:.loword(keyPending)
inputCaptured:
              a16
              rtl

; ---------------------------------------------------------------------------
; queueInput: put an ADB key event (INPUT_KEY, the key byte irqValue) with
; the time inputClock in inputRing; a full ring drops it. The head moves
; only after the whole entry is written, so the drain never reads a half
; entry.
;
; In:       A16 X16, DBR = this bank; irqValue
; Out:      inputHead
; Changes:  A, X
; Keeps:    Y, D, DBR
; Time:     about 65 cycles
; Original: none
; ---------------------------------------------------------------------------
queueInput:   lda a:.loword(inputClock)
              ldx a:.loword(inputHead)
              sta a:.loword(inputRing+INPUT_TIME),x
              stz a:.loword(inputRing+INPUT_TYPE),x ; INPUT_KEY
              lda a:.loword(irqValue)
              sta a:.loword(inputRing+INPUT_VALUE),x
              txa
              clc
              adc #INPUT_EVENT_SIZE
              and #INPUT_RING_SIZE-1
              cmp a:.loword(inputTail)
              beq inputOverflow         ; full: the event is dropped
              sta a:.loword(inputHead)   ; publish only the complete event
inputOverflow:
              rts

.assert KM_MOUSE_FULL = $80 .and KM_COMMAND_FULL = 1, error ; the BPL and the LSR above
.assert INPUT_KEY = 0, error ; queueInput: the STZ of INPUT_TYPE
.assert INPUT_KEY/2+1 = HELD_ADB .and INPUT_J13/2+1 = HELD_J13, error ; drain: LSR, INC

; The capture state.
.a16
irqValue: .word 0               ; CaptureInput: the key byte for queueInput (high byte 0)
keyTalk: .word 0                ; 1: a talk to the keyboard runs (J13Pump sets it while a row read owns the GLU)
keyPending: .word 0             ; 1: the keyboard asks for a talk
keyReply: .word 0               ; the key bytes of the talk still to come
keyHeaderByte: .word 0          ; the last ADB status byte
mouseTalkCount: .word 0         ; mouse moves since the last keyboard talk
