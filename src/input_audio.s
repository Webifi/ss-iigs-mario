; The sound mix of the settings: the music level and the effects level, 0
; to MIX_LEVEL_MAX (src/settings.inc). They change only at the settings load
; (src/input_settings.s defaults) and in the options menu (src/menu.s
; menu_level_key); src/sound.s applies them (sound_set_mix). Part of the
; input (src/input.s), in its scope.
;
; Routines:
;   mix_settings   the levels limited to MIX_LEVEL_MAX, then mix_apply
;   mix_apply      send both levels to the sound code
.a16
.i16

; ---------------------------------------------------------------------------
; mix_settings: the mix fields of the settings: a level above MIX_LEVEL_MAX
; (a damaged or foreign file) becomes MIX_LEVEL_MAX; then it falls through
; into mix_apply.
;
; In:       A16 X16, DBR = this bank
; Out:      settings+SET_MUSIC_LEVEL, SET_EFFECTS_LEVEL at most
;           MIX_LEVEL_MAX; the levels sent
; Changes:  A, X, Y
; Keeps:    D, DBR, A16 X16
; Original: none
; ---------------------------------------------------------------------------
mix_settings:
  a8
  lda a:.loword(settings+SET_MUSIC_LEVEL)
  cmp #MIX_LEVEL_MAX+1
  bcc :+
  lda #MIX_LEVEL_MAX
  sta a:.loword(settings+SET_MUSIC_LEVEL)
:
  lda a:.loword(settings+SET_EFFECTS_LEVEL)
  cmp #MIX_LEVEL_MAX+1
  bcc :+
  lda #MIX_LEVEL_MAX
  sta a:.loword(settings+SET_EFFECTS_LEVEL)
:
  a16
  ; Falls through into mix_apply, which sends the levels.

; ---------------------------------------------------------------------------
; mix_apply: send the music level and the effects level of the settings to
; the sound code (src/sound.s sound_set_mix, which sets its own data bank).
;
; In:       A16 X16, DBR = this bank
; Out:      the sound code has the levels
; Changes:  A, X, Y
; Keeps:    D, DBR, the widths
; Original: none
; ---------------------------------------------------------------------------
.a16
mix_apply:
  php
  ax16
  lda a:.loword(settings+SET_EFFECTS_LEVEL)
  and #$00ff
  tax                           ; X = the effects level
  lda a:.loword(settings+SET_MUSIC_LEVEL)
  and #$00ff
  a8                            ; A = the music level
  jsl sound_set_mix             ; A8 X16: A the music level, X the effects level
  plp
  rts
