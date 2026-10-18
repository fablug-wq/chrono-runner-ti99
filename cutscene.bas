' ============================================================================
' Chrono Runner TI-99/4A - Interprete delle cutscene
'
' Port di cutscene_s0.c / cutscene_s7.c. Gli script originali (CutCmd in
' chronorunner_s5_b1.c) sono convertiti da tools/msx2cvb.py in bytecode
' (generated/bank_cut.bas); le schermate sono in generated/bank_cut_scr.bas.
'
' Come nell'originale si esegue un comando per passo (50 al secondo);
' testo a macchina da scrivere, movimenti e animazioni occupano piu' passi.
' FCTN+9 (BACK) salta la cutscene, come ESC sull'MSX.
'
' Bytecode (codice, parametri):
'   0 END                    1 WAIT n                 2 WAIT_KEY
'   3 TEXT x y n tile*n      4 TEXT_TYPE x y n tile*n 5 CLEAR_TEXT
'   6 SHOW id x y frame col  7 HIDE id                8 MOVE id sx sy ex ey frames
'   9 WALK anim sx sy ex ey speed                     10 ANIM anim x y durata
'  11 FILL tile x y w h      12 LAYOUT scr x y w h    13 MUSIC id   14 MUSIC_STOP
'  15 SFX id                 16 NUMBER var x y
' (x del testo gia' centrata dal convertitore)
'
' Codice: GPLv3
' ============================================================================

CONST CUT_TILE_EMPTY = 47

SIGNED #cut_dx, #cut_dy, #cut_t
DIM cut_spat(32), cut_scol(32)		' frame e colore correnti di ogni sprite
DIM cut_af(3), cut_ac(2)			' animazione corrente: frame e colori dei layer
DIM cut_row(32)					' riga di riempimento per FILL

' Avvia la cutscene che inizia all'offset #cut_pc (Cutscene_Start)
cut_start:	PROCEDURE
	cut_waiting = 0: cut_moving = 0: cut_typing = 0: cut_fc = 0
	spr_count = 16					' l'interrupt veloce copia gli sprite 0-15
	SCREEN DISABLE
	GOSUB hide_sprites
	GOSUB clear_screen
	SCREEN ENABLE
	BANK SELECT CUT_BANK
	END

' Un passo di cutscene (State_Cutscene). game_event = EV_CUT_END alla fine.
cut_step:	PROCEDURE
	game_event = EV_NONE
	GOSUB read_keys
	IF (kbits AND 96) = 96 THEN game_event = EV_CUT_END: RETURN	' BACK: salta
	BANK SELECT CUT_BANK
	IF cut_moving THEN GOSUB cut_move_step: RETURN
	IF cut_typing THEN GOSUB cut_type_step: RETURN

	op = cut_data(#cut_pc)
	IF cut_waiting THEN
		IF op = 1 THEN
			cut_fc = cut_fc + 1
			IF cut_fc >= cut_data(#cut_pc + 1) THEN cut_waiting = 0: #cut_pc = #cut_pc + 2
		ELSE
			j = CONT1
			sp = 0
			IF (j AND $40) OR (kbits AND 16) THEN sp = 1
			IF cut_needrel THEN
				IF sp = 0 THEN cut_needrel = 0
			ELSEIF sp THEN
				cut_waiting = 0: #cut_pc = #cut_pc + 1
			END IF
		END IF
		RETURN
	END IF
	ON op GOSUB cop_end, cop_wait, cop_waitkey, cop_text, cop_type, cop_clear, cop_show, cop_hide, cop_move, cop_walk, cop_anim, cop_fill, cop_layout, cop_music, cop_mstop, cop_sfx, cop_number
	END

' Parametri del comando corrente: cut_p(n) = byte n dopo il codice
' (letti dal banco degli script, gia' selezionato)
cop_end:	PROCEDURE
	game_event = EV_CUT_END
	END

cop_wait:	PROCEDURE
	cut_fc = 0: cut_waiting = 1
	END

cop_waitkey:	PROCEDURE
	' se il tasto e' gia' premuto bisogna prima rilasciarlo
	j = CONT1
	cut_needrel = 0
	IF (j AND $40) OR (kbits AND 16) THEN cut_needrel = 1
	cut_waiting = 1
	END

cop_text:	PROCEDURE
	tx = cut_data(#cut_pc + 1): ty = cut_data(#cut_pc + 2): tn = cut_data(#cut_pc + 3)
	#cut_off = ty: #cut_off = #cut_off * 32 + tx
	IF tn THEN SCREEN cut_data, #cut_pc + 4, #cut_off, tn, 1
	#cut_pc = #cut_pc + 4 + tn
	END

cop_type:	PROCEDURE
	tx = cut_data(#cut_pc + 1): ty = cut_data(#cut_pc + 2): tn = cut_data(#cut_pc + 3)
	cut_ti = 0
	cut_typing = 1
	END

' Macchina da scrivere: un carattere per passo, poi un passo per chiudere
cut_type_step:	PROCEDURE
	IF cut_ti < tn THEN
		#cut_off = ty: #cut_off = #cut_off * 32 + tx + cut_ti + $1800
		VPOKE #cut_off, cut_data(#cut_pc + 4 + cut_ti)
		cut_ti = cut_ti + 1
	ELSE
		cut_typing = 0
		#cut_pc = #cut_pc + 4 + tn
	END IF
	END

' Pulisce le righe di testo 20-23
cop_clear:	PROCEDURE
	SCREEN fill_row, 0, 640, 32, 1
	SCREEN fill_row, 0, 672, 32, 1
	SCREEN fill_row, 0, 704, 32, 1
	SCREEN fill_row, 0, 736, 32, 1
	#cut_pc = #cut_pc + 1
	END

cop_show:	PROCEDURE
	sid = cut_data(#cut_pc + 1)
	sx = cut_data(#cut_pc + 2): sy = cut_data(#cut_pc + 3)
	sf = cut_data(#cut_pc + 4): sc = cut_data(#cut_pc + 5)
	GOSUB cut_sprite
	#cut_pc = #cut_pc + 6
	END

cop_hide:	PROCEDURE
	SPRITE cut_data(#cut_pc + 1), 192, 0, 0, 0
	#cut_pc = #cut_pc + 2
	END

' Sposta uno sprite gia' visibile (mantiene frame e colore)
cop_move:	PROCEDURE
	cut_mid = cut_data(#cut_pc + 1)
	cut_sx = cut_data(#cut_pc + 2): cut_sy = cut_data(#cut_pc + 3)
	#cut_dx = cut_data(#cut_pc + 4): #cut_dx = #cut_dx - cut_sx
	#cut_dy = cut_data(#cut_pc + 5): #cut_dy = #cut_dy - cut_sy
	cut_total = cut_data(#cut_pc + 6)
	cut_anim = 255
	cut_len = 7
	GOSUB cut_setup
	sid = cut_mid: sx = cut_sx: sy = cut_sy: sf = cut_spat(sid): sc = cut_scol(sid)
	GOSUB cut_sprite
	END

' Sprite animato che si sposta (durata = distanza / velocita')
cop_walk:	PROCEDURE
	cut_anim = cut_data(#cut_pc + 1)
	cut_sx = cut_data(#cut_pc + 2): cut_sy = cut_data(#cut_pc + 3)
	#cut_dx = cut_data(#cut_pc + 4): #cut_dx = #cut_dx - cut_sx
	#cut_dy = cut_data(#cut_pc + 5): #cut_dy = #cut_dy - cut_sy
	a = ABS(#cut_dx): b = ABS(#cut_dy)
	IF b > a THEN a = b
	b = cut_data(#cut_pc + 6)
	IF b = 0 THEN b = 1
	cut_total = a / b
	IF cut_total = 0 THEN cut_total = 1
	cut_len = 7
	GOSUB cut_setup
	END

' Sprite animato fermo (durata 0 = 60 passi)
cop_anim:	PROCEDURE
	cut_anim = cut_data(#cut_pc + 1)
	cut_sx = cut_data(#cut_pc + 2): cut_sy = cut_data(#cut_pc + 3)
	#cut_dx = 0: #cut_dy = 0
	cut_total = cut_data(#cut_pc + 4)
	IF cut_total = 0 THEN cut_total = 60
	cut_len = 5
	GOSUB cut_setup
	END

cop_fill:	PROCEDURE
	a = cut_data(#cut_pc + 1)
	tx = cut_data(#cut_pc + 2): ty = cut_data(#cut_pc + 3)
	tn = cut_data(#cut_pc + 4): b = cut_data(#cut_pc + 5)
	FOR i = 0 TO 31: cut_row(i) = a: NEXT i
	#cut_off = ty: #cut_off = #cut_off * 32 + tx
	WHILE b
		SCREEN cut_row, 0, #cut_off, tn, 1
		#cut_off = #cut_off + 32
		b = b - 1
	WEND
	#cut_pc = #cut_pc + 6
	END

' Schermata (sempre larga 32 e allineata a sinistra negli script originali)
cop_layout:	PROCEDURE
	cut_scr = cut_data(#cut_pc + 1)
	cut_y = cut_data(#cut_pc + 3)
	cut_rows = cut_data(#cut_pc + 5)
	GOSUB cut_layout
	#cut_pc = #cut_pc + 6
	END

' Musica ed effetti: arriveranno con l'audio (nell'originale la musica
' delle cutscene e' gia' disattivata)
' Musica: nell'originale questi due comandi non fanno niente (codice commentato)
cop_music:	PROCEDURE
	#cut_pc = #cut_pc + 2
	END

cop_mstop:	PROCEDURE
	#cut_pc = #cut_pc + 1
	END

' Effetto sonoro (stessi numeri di fx_sounds.h)
cop_sfx:	PROCEDURE
	sfx_id = cut_data(#cut_pc + 1)
	GOSUB sfx_play
	#cut_pc = #cut_pc + 2
	END

' Numero a due cifre: 0 = minuti, 1 = secondi rimasti al momento del boss
cop_number:	PROCEDURE
	IF cut_data(#cut_pc + 1) = 0 THEN a = t_min_bk ELSE a = t_sec_bk
	numbuf(0) = a / 10 + 1: numbuf(1) = a % 10 + 1
	#cut_off = cut_data(#cut_pc + 3): #cut_off = #cut_off * 32 + cut_data(#cut_pc + 2)
	SCREEN numbuf, 0, #cut_off, 2, 1
	#cut_pc = #cut_pc + 4
	END

' SetupAnimation: prepara movimento/animazione (cut_anim = 255: sprite semplice)
cut_setup:	PROCEDURE
	cut_fc = 0
	cut_moving = 1
	IF cut_anim = 255 THEN RETURN
	#cut_t = cut_anim: #cut_t = #cut_t * 11
	a_base = cut_anims(#cut_t)
	a_layers = cut_anims(#cut_t + 1)
	a_nframes = cut_anims(#cut_t + 2)
	cut_af(0) = cut_anims(#cut_t + 3)
	cut_af(1) = cut_anims(#cut_t + 4)
	cut_af(2) = cut_anims(#cut_t + 5)
	a_idle = cut_anims(#cut_t + 6)
	a_speed = cut_anims(#cut_t + 7)
	a_loff = cut_anims(#cut_t + 8)
	cut_ac(0) = cut_anims(#cut_t + 9)
	cut_ac(1) = cut_anims(#cut_t + 10)
	a_timer = 0: a_frame = 0
	sx = cut_sx: sy = cut_sy
	a = cut_af(0)
	GOSUB cut_draw_layers
	END

' Cutscene_UpdateMovement
cut_move_step:	PROCEDURE
	cut_fc = cut_fc + 1
	#cut_t = #cut_dx * cut_fc / cut_total
	sx = cut_sx + #cut_t
	#cut_t = #cut_dy * cut_fc / cut_total
	sy = cut_sy + #cut_t
	IF cut_anim = 255 THEN
		sid = cut_mid: sf = cut_spat(sid): sc = cut_scol(sid)
		GOSUB cut_sprite
	ELSE
		a_timer = a_timer + 1
		IF a_timer >= a_speed THEN
			a_timer = 0
			a_frame = a_frame + 1
			IF a_frame >= a_nframes THEN a_frame = 0
		END IF
		a = cut_af(a_frame)
		GOSUB cut_draw_layers
	END IF
	IF cut_fc >= cut_total THEN
		' a fine camminata i layer tornano al frame di riposo
		IF cut_anim <> 255 THEN a = a_idle: GOSUB cut_draw_layers
		cut_moving = 0
		#cut_pc = #cut_pc + cut_len
	END IF
	END

' Disegna i layer dell'animazione corrente in (sx, sy) con frame base a
cut_draw_layers:	PROCEDURE
	FOR i = 0 TO a_layers - 1
		sid = a_base + i
		sf = a + i * a_loff
		sc = cut_ac(i)
		GOSUB cut_sprite
	NEXT i
	END

' SPRITE con memoria di frame e colore (per MOVE)
cut_sprite:	PROCEDURE
	cut_spat(sid) = sf: cut_scol(sid) = sc
	SPRITE sid, sy, sx, sf, sc
	END
