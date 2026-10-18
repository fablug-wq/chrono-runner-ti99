' ============================================================================
' Chrono Runner TI-99/4A - Sequenza di gioco, intermezzo, messaggi
'
' Port di AdvanceSequence / State_Intermission / State_MessageScreen
' (chronorunner.c). La sequenza (seq_type / seq_par in common.bas) e'
' generata da InitLevels: intro, livelli, cutscene di meta' e fine mondo,
' boss e finale.
'
' Codice: GPLv3
' ============================================================================

' Testi gia' convertiti in tile (CharToTile)
txt_room:
	DATA BYTE 28, 25, 25, 23						' ROOM
txt_ready:
	DATA BYTE 17, 15, 30, 0, 28, 15, 11, 14, 35, 43	' GET READY!
txt_gameover:
	DATA BYTE 17, 11, 23, 15, 0, 25, 32, 15, 28	' GAME OVER
txt_end:
	DATA BYTE 30, 18, 15, 0, 15, 24, 14			' THE END

' ----------------------------------------------------------------------------
' AdvanceSequence: passa alla voce successiva e imposta state
' ----------------------------------------------------------------------------
advance_seq:	PROCEDURE
adv_again:
	IF seq_idx >= SEQ_LEN THEN
		' Fine del gioco
		msg_txt = 1: msg_len = 7: #msg_dur = 150
		GOSUB msg_start
		state = ST_MSG
		RETURN
	END IF
	t = seq_type(seq_idx)
	IF t = SEQ_CUTSCENE THEN
		#cut_pc = #cut_start(seq_par(seq_idx))
		seq_idx = seq_idx + 1
		GOSUB cut_start
		state = ST_CUT
	ELSEIF t = SEQ_BOSS THEN
		seq_idx = seq_idx + 1
		BANK SELECT BOSS_BANK
		GOSUB boss_init
		state = ST_BOSS
	ELSE
		next_lvl = seq_par(seq_idx)
		GOSUB inter_start
		state = ST_INTER
	END IF
	END

' ----------------------------------------------------------------------------
' Intermezzo prima di ogni livello: avanzamento, stanza, tempo, nome
' ----------------------------------------------------------------------------
inter_start:	PROCEDURE
	IF cur_song <> MUSIC_GAME THEN mus_req = MUSIC_GAME: GOSUB music_select
	SCREEN DISABLE
	GOSUB hide_sprites
	ui_screen = UI_INTERMISSION
	GOSUB show_ui

	' Barra di avanzamento sulla riga 16: verde fatto, rosso da fare
	#ta = next_lvl: #ta = #ta * 30 / NUM_LEVELS
	prog = #ta
	FOR i = 0 TO 29
		IF i < prog THEN cut_row(i) = 49 ELSE cut_row(i) = 51
	NEXT i
	SCREEN cut_row, 0, 16 * 32 + 2, 30, 1
	VPOKE $1800 + 16 * 32 + 2 + prog, 48

	SCREEN txt_room, 0, 18 * 32 + 5, 4, 1
	a = next_lvl + 1
	numbuf(0) = a / 10 + 1: numbuf(1) = a % 10 + 1
	SCREEN numbuf, 0, 18 * 32 + 10, 2, 1

	SCREEN hud_time, 0, 18 * 32 + 18, 11, 1
	numbuf(0) = t_min / 10 + 1: numbuf(1) = t_min % 10 + 1
	SCREEN numbuf, 0, 18 * 32 + 23, 2, 1
	numbuf(0) = t_sec / 10 + 1: numbuf(1) = t_sec % 10 + 1
	SCREEN numbuf, 0, 18 * 32 + 26, 2, 1

	' Nome del livello centrato sulla riga 20 (solo dati, senza disegnare la mappa)
	cur_level = next_lvl
	lvl_noscreen = 1
	GOSUB load_level
	lvl_noscreen = 0
	IF lvl_name_len THEN
		#ta = lvl_name_len / 2
		#ta = 20 * 32 + 16 - #ta
		SCREEN lvl_name, 0, #ta, lvl_name_len, 1
	END IF

	SCREEN txt_ready, 0, 23 * 32 + 11, 10, 1
	SCREEN ENABLE
	inter_count = 0
	END

' Due secondi di attesa (o FCTN+L con il cheat), poi il livello
inter_step:	PROCEDURE
	game_event = EV_NONE
	inter_count = inter_count + 1
	GOSUB read_keys
	IF inter_count > 100 OR (CHEAT_ENABLED AND (kbits AND 40) = 40 AND inter_count > 10) THEN
		' ChangeLevel: si entra nel livello e la sequenza avanza
		cur_level = next_lvl
		seq_idx = seq_idx + 1
		GOSUB change_level
		game_event = EV_INTER_END
	END IF
	END

' ----------------------------------------------------------------------------
' Messaggio a tutto schermo (GAME OVER, THE END), poi si torna al menu
' msg_txt: 0 = GAME OVER, 1 = THE END
' ----------------------------------------------------------------------------
msg_start:	PROCEDURE
	' GAME OVER ha il suo brano (in loop), THE END il silenzio
	IF msg_txt = 0 THEN mus_req = MUSIC_GAMEOVER ELSE mus_req = MUSIC_NONE
	GOSUB music_select
	SCREEN DISABLE
	GOSUB hide_sprites
	GOSUB clear_screen
	#ta = 12 * 32 + 16 - msg_len / 2
	IF msg_txt = 0 THEN SCREEN txt_gameover, 0, #ta, msg_len, 1 ELSE SCREEN txt_end, 0, #ta, msg_len, 1
	SCREEN ENABLE
	#msg_count = 0
	END

msg_step:	PROCEDURE
	game_event = EV_NONE
	#msg_count = #msg_count + 1
	IF #msg_count >= #msg_dur THEN game_event = EV_MSG_END
	END
