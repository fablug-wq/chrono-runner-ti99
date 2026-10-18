' ============================================================================
' Chrono Runner TI-99/4A - Viewer dei livelli (passo 1 del port)
'
' Menu completo (START, HOW TO PLAY, RATING, CREDITS). START permette di sfogliare tutti i 33 livelli con la mappa
' e gli oggetti nelle posizioni iniziali (player, chiave, cristallo,
' piattaforme, mine, nemici).
'
'   Destra / N  = livello successivo
'   Sinistra / P = livello precedente
'   Fuoco / spazio = torna al menu
'
' Codice: GPLv3 - Asset: Associazione MSX Italia, CC BY-NC-SA 4.0
' ============================================================================

	BANK ROM 128
	GOTO main

	INCLUDE "generated/common.bas"
	INCLUDE "ui.bas"

	DIM fill_row(32)
	DIM numbuf(2)

' Il viewer non ha musica: ui.bas chiama music_toggle (tasto M) e usa il
' contatore del player di CVBasic, quindi servono questi due pezzi
music_toggle:	PROCEDURE
	END

main:
	MODE 0
	music60 = 0
	PLAY OFF
	FOR i = 0 TO 31: fill_row(i) = TILE_EMPTY: NEXT i

	SCREEN DISABLE
	GOSUB load_gfx
	SCREEN ENABLE

show_menu:
	GOSUB run_menu		' ritorna quando si sceglie START
	cur_level = 0

show_level:
	SCREEN DISABLE
	GOSUB hide_sprites
	#off = 0
	FOR i = 0 TO 23
		SCREEN fill_row, 0, #off, 32, 1
		#off = #off + 32
	NEXT i
	GOSUB load_level
	IF lvl_name_len > 0 THEN SCREEN lvl_name, 0, 0, lvl_name_len, 1
	numbuf(0) = cur_level / 10 + 1
	numbuf(1) = cur_level % 10 + 1
	SCREEN numbuf, 0, 32, 2, 1
	GOSUB draw_objects
	SCREEN ENABLE
	GOSUB wait_release

input_loop:
	WAIT
	k = CONT1.KEY
	IF CONT1.RIGHT OR k = 78 THEN
		cur_level = cur_level + 1
		IF cur_level >= NUM_LEVELS_ALL THEN cur_level = 0
		GOTO show_level
	END IF
	IF CONT1.LEFT OR k = 80 THEN
		IF cur_level = 0 THEN cur_level = NUM_LEVELS_ALL
		cur_level = cur_level - 1
		GOTO show_level
	END IF
	IF CONT1.BUTTON OR k = 32 THEN GOTO show_menu
	GOTO input_loop

' Disegna gli oggetti del livello nelle posizioni iniziali.
' Stessa assegnazione degli ID sprite dell'originale (AllocateSpriteIDs).
draw_objects:	PROCEDURE
	' Player: 2 layer (nero + giallo scuro), frame 0
	SPRITE 0, lvl_start_y * 8, lvl_start_x * 8, FR_PLAYER, 1
	SPRITE 1, lvl_start_y * 8, lvl_start_x * 8, FR_PLAYER + 4, 10
	' Chiave: visibile subito solo se non legata a un nemico
	IF lvl_ktrig < 0 THEN SPRITE 2, lvl_key_y * 8, lvl_key_x * 8, FR_KEY, 1
	' Cristallo (0,0 = assente)
	IF lvl_crys_x <> 0 OR lvl_crys_y <> 0 THEN SPRITE 3, lvl_crys_y * 8, lvl_crys_x * 8, FR_CRYSTAL, 8
	sid = 7
	j = 0
	WHILE j < lvl_nplat
		SPRITE sid, plat_y(j), plat_x(j), FR_PLATFORM, 1
		sid = sid + 1: j = j + 1
	WEND
	j = 0
	WHILE j < lvl_nmine
		SPRITE sid, mine_y(j), mine_x(j), FR_MINE, 1
		sid = sid + 1: j = j + 1
	WEND
	j = 0
	WHILE j < lvl_nenemy
		f = FR_ENEMY0 + enemy_type(j) * FR_ENEMY_STEP
		IF enemy_dir(j) >= 0 THEN f = f + 8
		c = 1
		IF lvl_ktrig = j THEN c = 6	' nemico che rivela la chiave: rosso scuro
		SPRITE sid, enemy_y(j), enemy_x(j), f, c
		sid = sid + 1: j = j + 1
	WEND
	END

	INCLUDE "generated/bank_gfx.bas"
	INCLUDE "generated/bank_lvl_2.bas"
	INCLUDE "generated/bank_lvl_3.bas"
	INCLUDE "generated/bank_lvl_4.bas"
	INCLUDE "generated/bank_lvl_5.bas"
	INCLUDE "generated/bank_ui.bas"
	INCLUDE "generated/bank_cut_scr.bas"	' serve a cut_layout di common.bas
