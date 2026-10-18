' ============================================================================
' Chrono Runner TI-99/4A - Programma principale
'
' Menu, sequenza completa (intro, intermezzi, livelli, cutscene, boss, finale),
' gioco con player, nemici, mine, piattaforme e rewind.
'
' Comandi: joystick 1 (su o CTRL = salto), oppure W/A/D da tastiera.
'
' Codice: GPLv3 - Asset: Associazione MSX Italia, CC BY-NC-SA 4.0
' ============================================================================

	BANK ROM 128
	GOTO main

' Stati del ciclo principale (definiti prima degli INCLUDE che li usano)
CONST ST_PLAY = 0
CONST ST_DEATH = 1
CONST ST_REWIND = 2
CONST ST_INTER = 3
CONST ST_CUT = 4
CONST ST_MSG = 5
CONST ST_BOSS = 6

' Velocita' della musica e degli effetti: 1 = 60 tick al secondo, come
' l'originale su un MSX a 60 Hz; 0 = 50 tick, come su un MSX europeo.
' La logica di gioco resta comunque a 50 passi al secondo.
CONST MUSIC_60HZ = 1
' Solo con MUSIC_60HZ = 1: la musica salta un tick ogni MUSIC_SLOW frame
' (10 = 10% piu' lenta, 20 = 5%, 0 = nessun rallentamento). Gli effetti no.
CONST MUSIC_SLOW = 10

	INCLUDE "generated/common.bas"
	INCLUDE "generated/audio.bas"
	INCLUDE "ui.bas"

	DIM fill_row(32)
	DIM numbuf(2)

	INCLUDE "game.bas"
	INCLUDE "fastisr.bas"
	INCLUDE "cutscene.bas"
	INCLUDE "flow.bas"

' Il font MSX non ha il '+': lo si disegna nel tile 99, che il gioco non usa,
' con gli stessi colori a righe delle lettere (serve per "FCTN+9")
plus_tile:	PROCEDURE
	DEFINE CHAR 99, 1, plus_pat
	DEFINE COLOR 99, 1, plus_col
	END

plus_pat:
	DATA BYTE $FF, $E7, $E7, $81, $81, $E7, $E7, $FF
plus_col:
	DATA BYTE $10, $1E, $15, $1E, $15, $1E, $15, $1E

' Logo Associazione MSX Italia (ShowAmi): Screen 1 su sfondo blu, le 4 righe
' salgono dalla riga 20 alla 6 (una ogni 2 frame), poi la riga del port in
' fondo e 2,5 secondi di attesa. Dati in generated/ami.bas (banco 13).
show_ami:	PROCEDURE
	MODE 2
	BORDER 4
	SCREEN DISABLE
	BANK SELECT 13
	DEFINE VRAM $0400,328,ami_pat
	DEFINE VRAM $2000,32,ami_col
	CLS
	SCREEN ENABLE
	FOR i = 20 TO 6 STEP -1
		SCREEN ami_names, 0, i * 32, 32, 4
		WAIT: WAIT
	NEXT i
	PRINT AT 22 * 32 + 1, "TI994A port by Fabrizio Luglio"
	FOR #ta = 1 TO 150: WAIT: NEXT #ta
	END

' Splash iniziale in bitmap (ShowSplashScreen): resta almeno 3 secondi,
' poi aspetta spazio, fuoco o ENTER. Il testo che scorre e' da aggiungere.
show_splash:	PROCEDURE
	MODE 1
	SCREEN DISABLE
	BANK SELECT 13
	DEFINE VRAM PLETTER $0000,$1800,image_bitmap
	DEFINE VRAM PLETTER $2000,$1800,image_color
	SCREEN ENABLE
	FOR #ta = 1 TO 150: WAIT: NEXT #ta
	DO
		WAIT
		k = CONT1.KEY
	LOOP WHILE CONT1.BUTTON = 0 AND k <> 32 AND k <> 11
	END

main:
	GOSUB show_ami
	GOSUB show_splash
	MODE 0
	BORDER 1
	FOR i = 0 TO 31: fill_row(i) = TILE_EMPTY: NEXT i
	SCREEN DISABLE
	GOSUB load_gfx
	GOSUB plus_tile
	SCREEN ENABLE
	' Musica: 3 canali, senza batteria (il rumore e' degli effetti)
	PLAY FULL NO DRUMS
	#sfx_ptr = 0: sfx_div = 0: sfx_nlast = 0: sfx_own = 0
	music60 = MUSIC_60HZ
	music_slow = MUSIC_SLOW: mslow_cnt = 0
	music_off = 0: mkey = 0: mkey_prev = 0

menu:
	GOSUB isr_fast_off		' menu: interrupt standard (tastiera completa)
	mus_req = MUSIC_MENU: GOSUB music_select
	GOSUB run_menu
	GOSUB isr_fast_on		' gioco: interrupt leggero
	mus_req = MUSIC_INTRO: GOSUB music_select
	GOSUB game_new
	seq_idx = 0
	GOSUB advance_seq		' intro, poi il primo livello
	tick6 = 0
	#fdone = FRAME

' Ciclo principale: la logica avanza 5 frame su 6 (50 passi al secondo).
' #fdone = ultimo frame gia' usato. Se un passo dura piu' di un frame il
' successivo parte subito, senza aspettare: si recupera il ritardo e il
' frame saltato ogni 6 fa da riserva. Cosi' il gioco rallenta solo se in
' media un passo supera 1,2 frame. Oltre 6 frame di ritardo (caricamento
' di un livello, cambio di schermata) si riparte da adesso.
main_loop:
	WHILE FRAME = #fdone: WEND
	#ta = FRAME - #fdone
	IF #ta > 6 THEN #fdone = FRAME ELSE #fdone = #fdone + 1
	tick6 = tick6 + 1
	IF tick6 >= 6 THEN tick6 = 0: GOTO main_loop

	' M: musica spenta/accesa (solo alla pressione, non finche' resta premuto)
	GOSUB read_mkey
	IF mkey <> 0 AND mkey_prev = 0 THEN GOSUB music_toggle
	mkey_prev = mkey

	IF state = ST_PLAY THEN
		GOSUB game_step
		IF CHEAT_ENABLED AND (kbits AND 160) = 160 THEN
			' Cheat FCTN+B: salta direttamente al boss finale
			seq_idx = SEQ_BOSS_IDX
			GOSUB advance_seq
			GOTO main_loop
		END IF
		IF game_event = EV_DEATH THEN
			GOSUB death_start
			state = ST_DEATH
		ELSEIF game_event = EV_REWIND THEN
			state = ST_REWIND
		ELSEIF game_event = EV_EXIT THEN
			GOSUB advance_seq			' intermezzo o cutscene successiva
		ELSEIF game_event = EV_VORTEX THEN
			' Livello segreto in base al mondo; la sequenza non avanza, quindi
			' all'uscita si riprende dal livello successivo a quello lasciato
			IF cur_level < 7 THEN
				cur_level = NUM_LEVELS
			ELSEIF cur_level < 14 THEN
				cur_level = NUM_LEVELS + 1
			ELSEIF cur_level < 21 THEN
				cur_level = NUM_LEVELS + 2
			ELSE
				cur_level = NUM_LEVELS + 3
			END IF
			warp_up = 1: GOSUB warp_time	' +5 minuti
			rew_energy = REWIND_MAX
			GOSUB change_level
		END IF
	ELSEIF state = ST_REWIND THEN
		GOSUB rewind_step
		IF game_event = EV_REWIND_END THEN state = ST_PLAY
	ELSEIF state = ST_DEATH THEN
		GOSUB death_step
		IF game_event = EV_RESPAWN THEN state = ST_PLAY
		IF game_event = EV_GAMEOVER THEN
			msg_txt = 0: msg_len = 9: #msg_dur = 425
			GOSUB msg_start
			state = ST_MSG
		END IF
	ELSEIF state = ST_INTER THEN
		GOSUB inter_step
		IF game_event = EV_INTER_END THEN state = ST_PLAY
	ELSEIF state = ST_BOSS THEN
		BANK SELECT BOSS_BANK
		GOSUB boss_step
		IF game_event = EV_DEATH THEN
			GOSUB death_start
			state = ST_DEATH			' tempo azzerato: la morte porta al GAME OVER
		ELSEIF game_event = EV_BOSS_END THEN
			GOSUB advance_seq			' cutscene finali
		END IF
	ELSEIF state = ST_CUT THEN
		GOSUB cut_step
		IF game_event = EV_CUT_END THEN GOSUB advance_seq
	ELSE
		GOSUB msg_step
		IF game_event = EV_MSG_END THEN GOTO menu
	END IF
	GOTO main_loop

	INCLUDE "generated/bank_gfx.bas"
	INCLUDE "generated/bank_lvl_2.bas"
	INCLUDE "generated/bank_lvl_3.bas"
	INCLUDE "generated/bank_lvl_4.bas"
	INCLUDE "generated/bank_lvl_5.bas"
	INCLUDE "generated/bank_ui.bas"
	INCLUDE "generated/bank_cut_scr.bas"
	INCLUDE "generated/bank_cut.bas"
	INCLUDE "generated/bank_boss.bas"
	INCLUDE "boss.bas"				' codice del boss, nel banco 9
	INCLUDE "generated/bank_audio.bas"	' banchi 10-12
	INCLUDE "splash_data.bas"			' banco 13
	INCLUDE "generated/ami.bas"		' banco 13, dopo lo splash
