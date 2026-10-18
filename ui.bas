' ============================================================================
' Chrono Runner TI-99/4A - Menu, istruzioni, valutazione, crediti
' Port di State_Menu, State_Slideshow e g_InstructionsCutscene (chronorunner.c,
' chronorunner_s5_b1.c). Tutto nel banco 0.
'
' Richiede common.bas (UI_*, FR_*, show_ui).
' Codice: GPLv3
' ============================================================================

CONST MENU_HIGHLIGHT_TILE = 49
CONST MENU_EMPTY_TILE = 47
CONST MENU_START = 0
CONST MENU_HOWTO = 1
CONST MENU_RATING = 2
CONST MENU_CREDITS = 3

' Posizione del cursore per ciascuna voce (colonna, riga)
menu_cols:
	DATA BYTE 12, 10, 8, 6
menu_rows:
	DATA BYTE 11, 13, 15, 17

' ----------------------------------------------------------------------------
' Menu principale. Gestisce da solo istruzioni, valutazione e crediti;
' ritorna solo quando il giocatore sceglie START.
run_menu:	PROCEDURE
menu_restart:
	SCREEN DISABLE
	GOSUB hide_sprites
	ui_screen = UI_MENU
	GOSUB show_ui
	menu_sel = MENU_START
	menu_tile = MENU_HIGHLIGHT_TILE
	GOSUB menu_mark
	SCREEN ENABLE
	GOSUB wait_release
	WHILE 1
		GOSUB menu_wait
		k = CONT1.KEY
		' Su: joystick, E o W. Giu': joystick, X o S. Le frecce del TI (FCTN+E/X)
		' non si possono leggere: CONT1.KEY con FCTN premuto restituisce solo FCTN.
		IF CONT1.UP OR k = 69 OR k = 87 THEN
			IF menu_sel > 0 THEN
				menu_tile = MENU_EMPTY_TILE: GOSUB menu_mark
				menu_sel = menu_sel - 1
				menu_tile = MENU_HIGHLIGHT_TILE: GOSUB menu_mark
			END IF
			GOSUB wait_release
		ELSEIF CONT1.DOWN OR k = 88 OR k = 83 THEN
			IF menu_sel < MENU_CREDITS THEN
				menu_tile = MENU_EMPTY_TILE: GOSUB menu_mark
				menu_sel = menu_sel + 1
				menu_tile = MENU_HIGHLIGHT_TILE: GOSUB menu_mark
			END IF
			GOSUB wait_release
		ELSEIF k = 77 THEN								' M: musica spenta/accesa
			GOSUB music_toggle
			GOSUB wait_release
		ELSEIF CONT1.BUTTON OR k = 32 OR k = 11 THEN	' fuoco, spazio o ENTER
			IF menu_sel = MENU_START THEN
				GOSUB wait_release
				RETURN
			END IF
			IF menu_sel = MENU_HOWTO THEN GOSUB show_howto
			IF menu_sel = MENU_RATING THEN ui_screen = UI_RATING: GOSUB show_page
			IF menu_sel = MENU_CREDITS THEN
				ui_screen = UI_CREDITS1: GOSUB show_page
				ui_screen = UI_CREDITS2: GOSUB show_page
			END IF
			GOTO menu_restart
		END IF
	WEND
	END

' Scrive menu_tile accanto alla voce menu_sel
menu_mark:	PROCEDURE
	#pos = menu_rows(menu_sel)
	#pos = #pos * 32 + menu_cols(menu_sel) + $1800
	VPOKE #pos, menu_tile
	END

' ----------------------------------------------------------------------------
' Mostra la schermata ui_screen e attende un tasto (State_Slideshow)
show_page:	PROCEDURE
	SCREEN DISABLE
	GOSUB hide_sprites
	GOSUB show_ui
	SCREEN ENABLE
	GOSUB wait_key
	END

' ----------------------------------------------------------------------------
' Istruzioni: tre pagine con sprite dimostrativi (g_InstructionsCutscene)
show_howto:	PROCEDURE
	ui_screen = UI_HOWTO1
	GOSUB show_page

	SCREEN DISABLE
	ui_screen = UI_HOWTO2
	GOSUB show_ui
	SPRITE 0, 6 * 8 - 1, 23 * 8, FR_VORTEX, 15
	SPRITE 1, 17 * 8, 2 * 8, FR_PLAYER + 1 * FR_PLAYER_STEP, 1
	SPRITE 2, 19 * 8 - 1, 13 * 8, FR_CRYSTAL, 8
	SPRITE 3, 20 * 8, 2 * 8, FR_PLAYER + 1 * FR_PLAYER_STEP, 1
	SCREEN ENABLE
	GOSUB wait_key

	SCREEN DISABLE
	GOSUB hide_sprites
	ui_screen = UI_HOWTO3
	GOSUB show_ui
	SPRITE 0, 5 * 8 - 1, 1 * 8, FR_PLAYER + 3 * FR_PLAYER_STEP, 1
	SPRITE 1, 1 * 8, 5 * 8, FR_PLAYER + 1 * FR_PLAYER_STEP, 1
	SPRITE 2, 5 * 8 - 1, 8 * 8, FR_ENEMY0 + 4 * 4, 8
	SPRITE 3, 5 * 8 - 1, 14 * 8, FR_KEY, 1
	SPRITE 4, 11 * 8 - 1, 23 * 8, FR_KEY, 1
	SPRITE 5, 11 * 8 - 1, 29 * 8, FR_PLAYER + 6 * FR_PLAYER_STEP, 1
	SPRITE 6, 20 * 8 - 1, 1 * 8, FR_PLAYER + 3 * FR_PLAYER_STEP, 1
	SPRITE 7, 16 * 8 - 1, 5 * 8, FR_PLAYER + 1 * FR_PLAYER_STEP, 1
	SPRITE 8, 20 * 8 - 1, 8 * 8, FR_PLAYER + 3 * FR_PLAYER_STEP, 1
	SCREEN ENABLE
	GOSUB wait_key

	GOSUB hide_sprites
	END

' ----------------------------------------------------------------------------
' Utilita' di input e sprite

' WAIT del menu. Qui gira l'interrupt standard, che suona la musica 5 frame
' su 6: con music60 si azzera il suo contatore cosi' non salta mai.
menu_wait:	PROCEDURE
	WAIT
	IF music60 = 0 THEN RETURN
	' Come nel gioco: un tick saltato ogni music_slow frame. Con 4 nel
	' contatore l'interrupt standard salta il prossimo, con 0 no.
	mslow_cnt = mslow_cnt + 1
	IF music_slow <> 0 AND mslow_cnt >= music_slow THEN
		mslow_cnt = 0
		ASM li r0,>0400
	ELSE
		ASM clr r0
	END IF
	ASM movb r0,@music_frame
	END

' Attende che joystick e tastiera siano rilasciati
wait_release:	PROCEDURE
	DO
		GOSUB menu_wait
		k = CONT1.KEY
	LOOP WHILE CONT1.UP OR CONT1.DOWN OR CONT1.LEFT OR CONT1.RIGHT OR CONT1.BUTTON OR (k <> 15 AND k <> 0)
	END

' Attende fuoco o spazio (dopo il rilascio)
wait_key:	PROCEDURE
	GOSUB wait_release
	DO
		GOSUB menu_wait
		k = CONT1.KEY
		IF k = 77 THEN GOSUB music_toggle: GOSUB wait_release	' M: musica on/off
	LOOP WHILE CONT1.BUTTON = 0 AND k <> 32 AND k <> 11
	GOSUB wait_release
	END

' Nasconde tutti gli sprite (Y=192 e' fuori schermo)
hide_sprites:	PROCEDURE
	FOR i = 0 TO 31
		SPRITE i, 192, 0, 0, 0
	NEXT i
	END
