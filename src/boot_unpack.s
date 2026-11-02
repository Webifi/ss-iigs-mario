; The decoder of a packed card startup record (part of the boot loader,
; src/boot.s, which includes this file). scripts/startup_pack.py packs a
; record when that makes it smaller (data_file.inc RECORD_PACKED); the
; boot loader reads its stored bytes into DATA_BUFFER, and startup_unpack
; writes the record to STARTUP_UNPACK_OUTPUT, from where the loader sends
; it to the card.
;
; The packed form: a token byte, then its bytes, up to the record's size.
;   token below TOKEN_MATCH   token + 1 literal bytes follow
;   token TOKEN_MATCH or more a match: (token - TOKEN_MATCH) + MATCH_MIN
;                             bytes copied from the output, at the 16-bit
;                             distance back that follows
;
; MVN does both copies: it copies A + 1 bytes from X to Y, forward, one byte
; at a time, so a match that overlaps its own output repeats its pattern.
; MVN sets the data bank to the destination bank, so the variables are in
; page zero and the source bytes are read with long addresses.
;
; Routines:
;   startup_unpack   unpack one record

UNPACK_SOURCE = DATA_BUFFER & $FF0000   ; the bank of the source: X holds the rest of its address
TOKEN_MATCH = $80               ; the first match token
MATCH_MIN = 3                   ; the bytes of the shortest match

; ---------------------------------------------------------------------------
; startup_unpack: unpack the record in DATA_BUFFER to STARTUP_UNPACK_OUTPUT.
;
; In:       unpack_end = the unpacked size (at most DATA_BUFFER_SIZE);
;           DATA_BUFFER = the packed bytes; native mode, A16 X16, interrupts
;           off (src/boot.s load_secondsight)
; Out:      STARTUP_UNPACK_OUTPUT = the record; Y = the end of the output;
;           A8
; Changes:  A, X, Y; unpack_end (the end address of the output),
;           unpack_length, unpack_distance
; Keeps:    D, DBR (MVN changes it; it comes back at the end)
; Original: none
; ---------------------------------------------------------------------------
.a16
.i16
startup_unpack:
  phb
  ldx #.loword(DATA_BUFFER)
  ldy #.loword(STARTUP_UNPACK_OUTPUT)
  ; unpack_end: the end address of the output, for the compare with Y.
  a16
  lda unpack_end
  clc
  adc #.loword(STARTUP_UNPACK_OUTPUT)
  sta unpack_end
  a8
@token:
  lda f:UNPACK_SOURCE,x
  bmi @match                    ; TOKEN_MATCH and up
  ; A literal run: MVN copies token + 1 bytes from the source.
  inx
  a16
  and #$00ff                    ; the count - 1
  mvn #^DATA_BUFFER,#^STARTUP_UNPACK_OUTPUT
  a8
  bra @next
@match:
  ; A match: the count - 1, then the distance word; MVN copies from
  ; Y - distance in the output.
  inx
  and #<~TOKEN_MATCH
  clc
  adc #MATCH_MIN-1              ; the count - 1
  a16
  and #$00ff
  sta unpack_length
  lda f:UNPACK_SOURCE,x
  sta unpack_distance
  inx
  inx
  phx                           ; the source of the next token
  tya
  sec
  sbc unpack_distance
  tax
  lda unpack_length
  mvn #^STARTUP_UNPACK_OUTPUT,#^STARTUP_UNPACK_OUTPUT
  plx
  a8
@next:
  cpy unpack_end
  bcc @token
  plb
  rts
.assert TOKEN_MATCH = $80, error ; the BMI above
