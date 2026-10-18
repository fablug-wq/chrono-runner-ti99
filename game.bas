' ============================================================================
' Chrono Runner TI-99/4A - Stato di gioco: player, piattaforme, oggetti, HUD
'
' Port di State_Game / State_Death / PlayerRestart (chronorunner.c),
' UpdatePlayer* / isPlayer* / Draw* (chronorunner_s7_b1.c) e della fisica
' di Pawn_UpdatePhysics / Pawn_UpdateAnimation (MSXgl engine/src/game/pawn.c).
'
' La logica gira a 50 passi al secondo come sull'MSX: il ciclo principale
' salta un frame video ogni 6 (60 Hz -> 50 Hz), cosi' salti, tempi e
' livelli restano identici all'originale.
'
' Intermezzo, cutscene, boss e audio stanno in flow.bas, cutscene.bas,
' boss.bas, fastisr.bas e generated/audio.bas.
'
' Codice: GPLv3
' ============================================================================

' --- Costanti di PawnData.h / sprite_defs.h ---
CONST GRAVITY = 2
CONST FORCE = 27
CONST TILE_SOLID = 203			' PlayerPhysicsCollision: tile >= 203
CONST TILE_SPIKE_MIN = 198		' isPlayerOnSpikes: 198-202
CONST TILE_SPIKE_MAX = 202
CONST REWIND_MAX = 100			' SNAPSHOT_BUFFER_SIZE

CONST SPR_PLAYER = 0			' 0-1: player (2 layer)
CONST SPR_KEY = 2
CONST SPR_CRYSTAL = 3
CONST SPR_DOC = 4
CONST SPR_VORTEX = 5
CONST SPR_BOOM = 6
CONST SPR_PLATFORM = 7			' 7+: piattaforme

CONST COL_BLACK = 1
CONST COL_MEDIUM_RED = 8
CONST COL_DARK_YELLOW = 10
CONST COL_WHITE = 15

' Azioni del player (enum ANIM_ACTION_ID)
CONST ACT_IDLE = 0
CONST ACT_MOVERIGHT = 1
CONST ACT_MOVELEFT = 2
CONST ACT_JUMPRIGHT = 3
CONST ACT_JUMPLEFT = 4
CONST ACT_FALLRIGHT = 5
CONST ACT_FALLLEFT = 6
CONST ACT_DEATH = 7

' Esito di un passo di gioco (game_event)
CONST EV_NONE = 0
CONST EV_DEATH = 1		' entra nello stato di morte
CONST EV_EXIT = 2		' uscita raggiunta
CONST EV_VORTEX = 3		' vortice: livello segreto
CONST EV_RESPAWN = 4		' fine animazione di morte, livello ricominciato
CONST EV_GAMEOVER = 5		' tempo esaurito
CONST EV_REWIND = 6		' inizia il rewind
CONST EV_REWIND_END = 7	' fine del rewind, si torna a giocare
CONST EV_CUT_END = 8		' fine (o salto) della cutscene
CONST EV_INTER_END = 9	' fine dell'intermezzo, livello caricato
CONST EV_MSG_END = 10	' fine del messaggio a tutto schermo
CONST EV_BOSS_END = 11	' boss sconfitto

CONST COL_GRAY = 14
CONST COL_DARK_RED = 6
CONST COL_LIGHT_RED = 9
CONST COL_MAGENTA = 13

' --- Snapshot per il rewind (snapshot.h / Snapshot_*) ---
' Buffer circolare di 100 passi (2 secondi a 50 Hz): posizione e frame del
' player, posizioni delle piattaforme, stato dei nemici e dei loro campi.
CONST SNAP_SIZE = 100
' Ogni passo occupa 39 byte consecutivi in snapbuf: px, py, frame, poi
' plat_x(4), plat_y(4), enemy_x(4), enemy_y(4), enemy_dir(4), enemy_stun(4),
' enemy_fstate(4), enemy_fx(4), enemy_fy(4). La copia e' in assembler:
' fatta in CVBasic costava quasi un terzo del tempo di un frame.
CONST SNAP_REC = 39
DIM snapbuf(SNAP_SIZE * SNAP_REC)

' --- Stato runtime dei nemici (struct Enemy, oltre ai campi di common.bas) ---
DIM enemy_mdx(MAX_ENEMIES)		' movimento accumulato in ottavi di pixel
DIM enemy_stun(MAX_ENEMIES)		' passi rimanenti di stordimento
DIM enemy_fstate(MAX_ENEMIES)	' 0 nessuno, 1 campo fisso, 2 proiettile, 3 pre-fuoco
DIM enemy_ftimer(MAX_ENEMIES)
DIM enemy_fx(MAX_ENEMIES), enemy_fy(MAX_ENEMIES)
DIM enemy_fmdx(MAX_ENEMIES)		' movimento accumulato del proiettile
DIM enemy_fdir(MAX_ENEMIES)		' direzione del campo, fissata allo sparo
DIM enemy_fbase(MAX_ENEMIES)	' primo frame sprite del tipo di nemico
DIM field_vis(MAX_ENEMIES)		' campo visibile nell'ultimo disegno
SIGNED enemy_mdx, enemy_fmdx, enemy_fdir, d_e, #kt

' Debug: con 1 la chiave e' visibile da subito anche nei livelli dove deve
' rivelarla un nemico.
CONST DEBUG_KEY_ALWAYS = 0

' Cheat: FCTN+L salta il livello (al posto di F1 dell'originale),
' FCTN+B salta direttamente al boss finale (vedi chrono.bas).
' Bisogna rilasciarlo tra un salto e l'altro. Mettere a 0 per disattivarlo.
CONST CHEAT_ENABLED = 1

SIGNED vel_y, m_dx, m_dy, d_x, d_y

' --- Animazioni (g_AnimActions): primo passo e numero di passi per azione ---
anim_first:
	DATA BYTE 0, 8, 11, 14, 15, 16, 17, 18
anim_count:
	DATA BYTE 8, 3, 3, 1, 1, 1, 1, 2
' Frame (indice PLAYER_FRAME) e durata in passi
anim_frm:
	DATA BYTE 0, 9, 10, 9, 10, 9, 10, 9
	DATA BYTE 1, 2, 3
	DATA BYTE 4, 5, 6
	DATA BYTE 3, 6, 1, 4
	DATA BYTE 7, 8
anim_dur:
	DATA BYTE 250, 10, 10, 10, 10, 10, 10, 10
	DATA BYTE 6, 6, 6
	DATA BYTE 6, 6, 6
	DATA BYTE 4, 4, 4, 4
	DATA BYTE 10, 10

' Intestazione HUD "TIME   '  "" gia' convertita in tile (CharToTile)
hud_time:
	DATA BYTE 30, 19, 23, 15, 0, 0, 0, 38, 0, 0, 40

	INCLUDE "generated/tables.bas"

' ============================================================================
' Avvio partita
' ============================================================================
game_new:	PROCEDURE
	t_min = 60: t_sec = 0: t_fs = 0
	rew_energy = 0
	cur_level = 0
	t_min_bk = 0: t_sec_bk = 0
	vel_y = 0: m_dx = 0: m_dy = 0
	jumping = 0
	BORDER COL_BLACK
	END

' ChangeLevel(): schermo vuoto, livello, HUD
change_level:	PROCEDURE
	SCREEN DISABLE
	GOSUB hide_sprites
	GOSUB clear_screen
	GOSUB player_restart
	GOSUB allocate_sprites
	SCREEN hud_time, 0, 2, 11, 1
	GOSUB print_time
	gauge_shown = 255
	GOSUB draw_gauge
	SCREEN ENABLE
	END

' Riempie lo schermo con il tile vuoto (VDP_FillScreen_GM2(TILE_EMPTY))
clear_screen:	PROCEDURE
	#ta = 0
	FOR i = 0 TO 23
		SCREEN fill_row, 0, #ta, 32, 1
		#ta = #ta + 32
	NEXT i
	END

' PlayerRestart(): ricarica il livello e rimette il player all'inizio
player_restart:	PROCEDURE
	GOSUB load_level			' mappa (righe 2-23) + oggetti
	key_x8 = lvl_key_x * 8: key_y8 = lvl_key_y * 8
	key_anim = 0
	key_on = 0
	IF lvl_ktrig < 0 THEN key_on = 1
	IF DEBUG_KEY_ALWAYS THEN key_on = 1
	IF key_on = 0 THEN SPRITE SPR_KEY, 192, 0, 0, 0
	key_fly = 0
	key_last = 0: crys_last = 0: mine_col = 0	' forza il primo disegno
	has_key = 0
	crys_x8 = lvl_crys_x * 8: crys_y8 = lvl_crys_y * 8
	crys_anim = 0
	crys_on = 1
	IF crys_x8 = 0 AND crys_y8 = 0 THEN crys_on = 0
	vortex_anim = 0
	SPRITE SPR_VORTEX, 192, 0, 0, 0
	SPRITE SPR_BOOM, 192, 0, 0, 0
	' ReinitPlayer: azione IDLE dall'inizio, posizione di partenza
	px = lvl_start_x * 8: py = lvl_start_y * 8
	act = ACT_IDLE: anim_step = 0: anim_timer = 0
	dying = 0
	player_col1 = COL_BLACK: player_col2 = COL_DARK_YELLOW
	plat_col = COL_BLACK
	rew_white = 0
	snap_head = 0: snap_count = 0		' Snapshot_Initialize
	' LoadLevel: i campi runtime dei nemici ripartono da zero
	FOR e = 0 TO MAX_ENEMIES - 1
		enemy_mdx(e) = 0: enemy_stun(e) = 0
		enemy_fstate(e) = 0: enemy_ftimer(e) = 0
		enemy_fx(e) = 0: enemy_fy(e) = 0
		enemy_fmdx(e) = 0: enemy_fdir(e) = 0
		enemy_fbase(e) = FR_ENEMY0 + enemy_type(e) * FR_ENEMY_STEP
		field_vis(e) = 1			' il primo disegno nasconde i campi spenti
	NEXT e
	END

' AllocateSpriteIDs: 7+ piattaforme, poi mine, nemici, campi di energia
allocate_sprites:	PROCEDURE
	spr_mine = SPR_PLATFORM + lvl_nplat
	spr_enemy = spr_mine + lvl_nmine
	spr_field = spr_enemy + lvl_nenemy
	spr_count = spr_field + lvl_nenemy		' sprite copiati dall'interrupt veloce
	enemy_anim = 0: enemy_hint = 0: field_anim = 0
	END

' ============================================================================
' Un passo di gioco (State_Game). Risultato in game_event.
' ============================================================================
game_step:	PROCEDURE
	game_event = EV_NONE
	GOSUB tick_down				' orologio (InterruptHook)

	GOSUB read_input			' UpdatePlayerInput
	IF lvl_nplat THEN GOSUB update_platforms
	IF lvl_nenemy THEN GOSUB update_enemies
	plat_on = 0
	IF lvl_nplat THEN GOSUB find_platform		' isPlayerOnPlatform -> plat_on
	GOSUB update_movement		' UpdatePlayerMovement
	GOSUB update_action			' UpdatePlayerAction -> new_act

	IF t_fs = 0 THEN GOSUB print_time
	IF t_min = 0 AND t_sec = 0 THEN game_event = EV_DEATH: RETURN

	GOSUB set_action			' Pawn_SetAction
	GOSUB update_animation		' Pawn_Update: animazione...
	GOSUB update_physics		' ...e collisioni con i tile
	pbx2 = px + 15: pby2 = py + 15	' box del player per le collisioni
	GOSUB draw_player

	' (le chiamate si saltano quando non c'e' niente da disegnare)
	IF key_on OR key_fly THEN GOSUB draw_key
	IF crys_on THEN GOSUB draw_crystal
	IF lvl_nplat THEN GOSUB draw_platforms
	IF lvl_nmine THEN GOSUB draw_mines
	IF lvl_nenemy THEN GOSUB draw_enemies: GOSUB draw_fields
	IF py < 8 THEN GOSUB draw_vortex

	' Vortice (easter egg): bboxCollide con l'angolo (0,0)
	IF px <= 15 AND py <= 15 THEN
		sfx_id = FX_ENTER_VORTEX: GOSUB sfx_play
		game_event = EV_VORTEX: RETURN
	END IF

	' Chiave
	IF key_on THEN
		bx = key_x8: by = key_y8: GOSUB bbox_player
		IF hit THEN
			GOSUB take_key
			key_on = 0
			SPRITE SPR_KEY, 192, 0, 0, 0
		END IF
	END IF

	' Cristallo
	IF crys_on THEN
		bx = crys_x8: by = crys_y8: GOSUB bbox_player
		IF hit THEN
			sfx_id = FX_GET_CRYSTAL: GOSUB sfx_play
			rew_energy = rew_energy + REWIND_MAX / 4
			IF rew_energy > REWIND_MAX THEN rew_energy = REWIND_MAX
			crys_on = 0
			SPRITE SPR_CRYSTAL, 192, 0, 0, 0
		END IF
	END IF

	' Mine (con esplosione), spine, nemici, campi di energia, burrone.
	' Stesso ordine e stessa valutazione in cortocircuito dell'originale:
	' se una condizione e' vera le successive non vengono controllate.
	hit_mine = 0
	IF lvl_nmine THEN GOSUB check_mines
	GOSUB check_spikes
	IF lvl_nenemy THEN
		IF hit = 0 AND hit_mine = 0 THEN GOSUB check_enemies
		IF hit = 0 AND hit_mine = 0 THEN GOSUB check_fields
	END IF
	IF hit OR hit_mine OR py > 192 THEN game_event = EV_DEATH: RETURN

	' Uscita
	IF has_key THEN
		bx = lvl_end_x * 8: by = lvl_end_y * 8: GOSUB bbox_player
		IF hit THEN sfx_id = FX_EXIT_DOOR: GOSUB sfx_play: game_event = EV_EXIT: RETURN
	END IF

	' Cheat: FCTN+L salta il livello
	IF CHEAT_ENABLED THEN
		IF (kbits AND 40) = 40 THEN
			IF cheat_armed THEN cheat_armed = 0: sfx_id = FX_EXIT_DOOR: GOSUB sfx_play: game_event = EV_EXIT: RETURN
		ELSE
			cheat_armed = 1
		END IF
	END IF

	GOSUB snap_capture

	' Fuoco: rewind, se c'e' energia e abbastanza passi registrati
	IF in_fire THEN
		IF rew_energy > 1 AND snap_count >= rew_energy THEN
			player_col1 = COL_WHITE: player_col2 = COL_GRAY
			GOSUB reinit_anim
			sfx_id = FX_REWIND: GOSUB sfx_play
			game_event = EV_REWIND
			RETURN
		END IF
	END IF

	GOSUB draw_gauge
	END

' ============================================================================
' Rewind (State_Rewind): un passo indietro per ogni passo di gioco, finche'
' si tiene premuto il fuoco e c'e' energia
' ============================================================================
rewind_step:	PROCEDURE
	game_event = EV_NONE
	GOSUB read_keys
	IF rew_energy = 0 OR (CONT1.BUTTON = 0 AND (kbits AND 16) = 0) THEN
		player_col1 = COL_BLACK: player_col2 = COL_DARK_YELLOW
		plat_col = COL_BLACK
		rew_white = 0
		GOSUB reinit_anim
		game_event = EV_REWIND_END
		RETURN
	END IF

	' Snapshot_RewindStep
	IF snap_head = 0 THEN snap_head = SNAP_SIZE
	snap_head = snap_head - 1
	snap_count = snap_count - 1
	rew_energy = rew_energy - 1
	GOSUB draw_gauge

	GOSUB snap_restore

	GOSUB draw_player
	plat_col = COL_WHITE			' oggetti in bianco durante il rewind
	rew_white = 1
	GOSUB draw_platforms
	GOSUB draw_enemies
	GOSUB draw_fields
	END

' Snapshot_Capture: salva lo stato nel buffer circolare
snap_capture:	PROCEDURE
	' r2 = snapbuf + snap_head * 39
	ASM movb @cvb_SNAP_HEAD,r1
	ASM srl r1,8
	ASM li r0,39
	ASM mpy r0,r1
	ASM ai r2,array_SNAPBUF
	ASM movb @cvb_PX,*r2+
	ASM movb @cvb_PY,*r2+
	ASM movb @cvb_ANIM_FRAME,*r2+
	ASM li r3,array_PLAT_X
	ASM movb *r3+,*r2+
	ASM movb *r3+,*r2+
	ASM movb *r3+,*r2+
	ASM movb *r3+,*r2+
	ASM li r3,array_PLAT_Y
	ASM movb *r3+,*r2+
	ASM movb *r3+,*r2+
	ASM movb *r3+,*r2+
	ASM movb *r3+,*r2+
	ASM li r3,array_ENEMY_X
	ASM movb *r3+,*r2+
	ASM movb *r3+,*r2+
	ASM movb *r3+,*r2+
	ASM movb *r3+,*r2+
	ASM li r3,array_ENEMY_Y
	ASM movb *r3+,*r2+
	ASM movb *r3+,*r2+
	ASM movb *r3+,*r2+
	ASM movb *r3+,*r2+
	ASM li r3,array_ENEMY_DIR
	ASM movb *r3+,*r2+
	ASM movb *r3+,*r2+
	ASM movb *r3+,*r2+
	ASM movb *r3+,*r2+
	ASM li r3,array_ENEMY_STUN
	ASM movb *r3+,*r2+
	ASM movb *r3+,*r2+
	ASM movb *r3+,*r2+
	ASM movb *r3+,*r2+
	ASM li r3,array_ENEMY_FSTATE
	ASM movb *r3+,*r2+
	ASM movb *r3+,*r2+
	ASM movb *r3+,*r2+
	ASM movb *r3+,*r2+
	ASM li r3,array_ENEMY_FX
	ASM movb *r3+,*r2+
	ASM movb *r3+,*r2+
	ASM movb *r3+,*r2+
	ASM movb *r3+,*r2+
	ASM li r3,array_ENEMY_FY
	ASM movb *r3+,*r2+
	ASM movb *r3+,*r2+
	ASM movb *r3+,*r2+
	ASM movb *r3+,*r2+
	snap_head = snap_head + 1
	IF snap_head = SNAP_SIZE THEN snap_head = 0
	IF snap_count < SNAP_SIZE THEN snap_count = snap_count + 1
	END

' Snapshot_Restore: rimette lo stato del passo snap_head
snap_restore:	PROCEDURE
	ASM movb @cvb_SNAP_HEAD,r1
	ASM srl r1,8
	ASM li r0,39
	ASM mpy r0,r1
	ASM ai r2,array_SNAPBUF
	ASM movb *r2+,@cvb_PX
	ASM movb *r2+,@cvb_PY
	ASM movb *r2+,@cvb_ANIM_FRAME
	ASM li r3,array_PLAT_X
	ASM movb *r2+,*r3+
	ASM movb *r2+,*r3+
	ASM movb *r2+,*r3+
	ASM movb *r2+,*r3+
	ASM li r3,array_PLAT_Y
	ASM movb *r2+,*r3+
	ASM movb *r2+,*r3+
	ASM movb *r2+,*r3+
	ASM movb *r2+,*r3+
	ASM li r3,array_ENEMY_X
	ASM movb *r2+,*r3+
	ASM movb *r2+,*r3+
	ASM movb *r2+,*r3+
	ASM movb *r2+,*r3+
	ASM li r3,array_ENEMY_Y
	ASM movb *r2+,*r3+
	ASM movb *r2+,*r3+
	ASM movb *r2+,*r3+
	ASM movb *r2+,*r3+
	ASM li r3,array_ENEMY_DIR
	ASM movb *r2+,*r3+
	ASM movb *r2+,*r3+
	ASM movb *r2+,*r3+
	ASM movb *r2+,*r3+
	ASM li r3,array_ENEMY_STUN
	ASM movb *r2+,*r3+
	ASM movb *r2+,*r3+
	ASM movb *r2+,*r3+
	ASM movb *r2+,*r3+
	ASM li r3,array_ENEMY_FSTATE
	ASM movb *r2+,*r3+
	ASM movb *r2+,*r3+
	ASM movb *r2+,*r3+
	ASM movb *r2+,*r3+
	ASM li r3,array_ENEMY_FX
	ASM movb *r2+,*r3+
	ASM movb *r2+,*r3+
	ASM movb *r2+,*r3+
	ASM movb *r2+,*r3+
	ASM li r3,array_ENEMY_FY
	ASM movb *r2+,*r3+
	ASM movb *r2+,*r3+
	ASM movb *r2+,*r3+
	ASM movb *r2+,*r3+
	END

' ReinitPlayer: l'animazione riparte dall'azione IDLE (cambio colori nel
' rewind). Posizione e velocita' restano invariate come nell'originale.
reinit_anim:	PROCEDURE
	act = ACT_IDLE: anim_step = 0: anim_timer = 0
	END

' ============================================================================
' Input (isUp/Left/RightPressed): joystick 1, oppure W/A/D da tastiera.
' Su = anche secondo pulsante (CTRL), come TRIGGER_B sull'MSX.
' ============================================================================
read_input:	PROCEDURE
	GOSUB read_keys				' kbits: 1 W, 2 A, 4 D, 8 L, 16 spazio
	j = CONT1					' joystick: 1 su, 2 destra, 4 giu', 8 sinistra, $40 fuoco, $80 CTRL
	in_r = 0: in_l = 0: in_up = 0: in_fire = 0
	IF (j AND 2) OR (kbits AND 4) THEN
		in_r = 1
	ELSEIF (j AND 8) OR (kbits AND 2) THEN
		in_l = 1
	END IF
	IF (j AND $81) OR (kbits AND 1) THEN in_up = 1
	IF (j AND $40) OR (kbits AND 16) THEN in_fire = 1
	END

' ============================================================================
' Piattaforme mobili (UpdatePlatforms)
' ============================================================================
update_platforms:	PROCEDURE
	' UpdatePlatforms in assembler: avanti di dx/dy, inversione agli estremi
	ASM clr r9
ASM up_loop:
	ASM clr r0
	ASM movb @cvb_LVL_NPLAT,r0
	ASM swpb r0
	ASM c r9,r0
	ASM jl up_body
	ASM b @up_done
ASM up_body:
	ASM movb @array_PLAT_X(r9),r0
	ASM ab @array_PLAT_DX(r9),r0
	ASM movb r0,@array_PLAT_X(r9)
	ASM cb r0,@array_PLAT_MAXX(r9)
	ASM jeq up_fx
	ASM cb r0,@array_PLAT_MINX(r9)
	ASM jne up_y
ASM up_fx:
	ASM clr r1
	ASM movb @array_PLAT_DX(r9),r1
	ASM neg r1
	ASM movb r1,@array_PLAT_DX(r9)
ASM up_y:
	ASM movb @array_PLAT_Y(r9),r0
	ASM ab @array_PLAT_DY(r9),r0
	ASM movb r0,@array_PLAT_Y(r9)
	ASM cb r0,@array_PLAT_MAXY(r9)
	ASM jeq up_fy
	ASM cb r0,@array_PLAT_MINY(r9)
	ASM jne up_next
ASM up_fy:
	ASM clr r1
	ASM movb @array_PLAT_DY(r9),r1
	ASM neg r1
	ASM movb r1,@array_PLAT_DY(r9)
ASM up_next:
	ASM inc r9
	ASM b @up_loop
ASM up_done:
	END

' isPlayerOnPlatform: plat_on = indice + 1, oppure 0
find_platform:	PROCEDURE
	' isPlayerOnPlatform in assembler (aritmetica a 16 bit come in C):
	' px+16 > x, px < x+16, py+20 > y, py < y. plat_on = indice+1
	ASM clr r3
	ASM movb @cvb_PX,r3
	ASM swpb r3
	ASM clr r4
	ASM movb @cvb_PY,r4
	ASM swpb r4
	ASM clr r9
ASM fp_loop:
	ASM clr r0
	ASM movb @cvb_LVL_NPLAT,r0
	ASM swpb r0
	ASM c r9,r0
	ASM jl fp_body
	ASM b @fp_done
ASM fp_body:
	ASM clr r1
	ASM movb @array_PLAT_X(r9),r1
	ASM swpb r1
	ASM mov r3,r0
	ASM ai r0,16
	ASM c r0,r1
	ASM jle fp_next
	ASM mov r1,r0
	ASM ai r0,16
	ASM c r3,r0
	ASM jhe fp_next
	ASM clr r2
	ASM movb @array_PLAT_Y(r9),r2
	ASM swpb r2
	ASM mov r4,r0
	ASM ai r0,20
	ASM c r0,r2
	ASM jle fp_next
	ASM c r4,r2
	ASM jhe fp_next
	ASM mov r9,r0
	ASM inc r0
	ASM swpb r0
	ASM movb r0,@cvb_PLAT_ON
	ASM jmp fp_done
ASM fp_next:
	ASM inc r9
	ASM b @fp_loop
ASM fp_done:
	END

' ============================================================================
' UpdatePlayerMovement / UpdatePlayerGravity / GetDPos
' ============================================================================
update_movement:	PROCEDURE
	moving_r = 0: moving_l = 0
	IF in_r THEN
		m_dx = m_dx + 8: moving_r = 1
	ELSEIF in_l THEN
		m_dx = m_dx - 8: moving_l = 1
	END IF

	' Salto: da terra o da una piattaforma
	IF in_up THEN
		IF plat_on <> 0 OR jumping = 0 THEN
			jumping = 1
			vel_y = FORCE
			plat_on = 0
			sfx_id = FX_JUMP: GOSUB sfx_play
		END IF
	END IF

	IF plat_on THEN
		p = plat_on - 1
		py = plat_y(p) - 16
		jumping = 0
		m_dx = m_dx + plat_dx(p) * 8
	END IF

	IF jumping THEN GOSUB apply_gravity

	u = m_dx: d_x = dpos_q(u): m_dx = dpos_r(u)
	u = m_dy: d_y = dpos_q(u): m_dy = dpos_r(u)
	END

apply_gravity:	PROCEDURE
	m_dy = m_dy - vel_y
	vel_y = vel_y - GRAVITY
	IF vel_y < -FORCE THEN vel_y = -FORCE
	END

' UpdatePlayerAction -> new_act
update_action:	PROCEDURE
	new_act = ACT_IDLE
	IF dying THEN
		new_act = ACT_DEATH
	ELSEIF jumping AND vel_y >= 0 THEN
		IF moving_r THEN new_act = ACT_JUMPRIGHT ELSE new_act = ACT_JUMPLEFT
	ELSEIF jumping THEN
		IF moving_r THEN new_act = ACT_FALLRIGHT ELSE new_act = ACT_FALLLEFT
	ELSEIF moving_r THEN
		new_act = ACT_MOVERIGHT
	ELSEIF moving_l THEN
		new_act = ACT_MOVELEFT
	END IF
	END

' ============================================================================
' Animazione (Pawn_SetAction / Pawn_UpdateAnimation)
' ============================================================================
set_action:	PROCEDURE
	IF act <> new_act THEN act = new_act: anim_step = 0: anim_timer = 0
	END

update_animation:	PROCEDURE
	a = anim_first(act)
	IF anim_timer >= anim_dur(a + anim_step) THEN anim_timer = 0: anim_step = anim_step + 1
	IF anim_step >= anim_count(act) THEN anim_timer = 0: anim_step = 0
	anim_frame = anim_frm(a + anim_step) * 8
	anim_timer = anim_timer + 1
	END

' ============================================================================
' Collisioni con i tile (Pawn_UpdatePhysics, box 16x16)
' Verticale: sotto ai 25% e 75% della larghezza, sopra al 50%.
' Orizzontale: al 50% dell'altezza.
' ============================================================================
update_physics:	PROCEDURE
	tx = px + d_x
	ty = py + d_y

	IF d_y > 0 THEN
		' --- Scende ---
		#a = ty: #a = #a + 16
		IF #a < 191 THEN
			#cy = #a / 8
			GOSUB floor_check
			IF hit THEN
				jumping = 0					' PAWN_PHYSICS_COL_DOWN
				ty = #cy * 8 - 16
			END IF
		END IF
	ELSEIF d_y < 0 THEN
		' --- Sale ---
		IF ty > py THEN
			ty = 0							' bordo superiore (blocco)
		ELSE
			#cx = tx: #cx = (#cx + 8) / 8
			#cy = ty / 8
			GOSUB get_tile
			IF tile >= TILE_SOLID THEN
				vel_y = 0					' PAWN_PHYSICS_COL_UP
				ty = #cy * 8 + 8
			END IF
		END IF
	ELSE
		' --- Fermo in verticale: c'e' pavimento? ---
		#a = ty: #a = #a + 16
		#cy = #a / 8
		GOSUB floor_check
		IF hit = 0 THEN jumping = 1		' PAWN_PHYSICS_FALL
	END IF

	IF d_x > 0 THEN
		' --- Destra ---
		a = tx + 16
		IF a < px THEN
			tx = 240						' bordo destro (blocco)
		ELSE
			#cx = tx: #cx = (#cx + 16) / 8
			#cy = ty: #cy = (#cy + 8) / 8
			GOSUB get_tile
			IF tile >= TILE_SOLID THEN tx = #cx * 8 - 16
		END IF
	ELSEIF d_x < 0 THEN
		' --- Sinistra ---
		IF tx > px THEN
			tx = 0							' bordo sinistro (blocco)
		ELSE
			#cx = tx / 8
			#cy = ty: #cy = (#cy + 8) / 8
			GOSUB get_tile
			IF tile >= TILE_SOLID THEN tx = #cx * 8 + 8
		END IF
	END IF

	px = tx
	py = ty
	END

' Pavimento sotto i punti al 25% e al 75% della larghezza (riga #cy)
floor_check:	PROCEDURE
	hit = 0
	#cx = tx: #cx = (#cx + 4) / 8
	last_cx = #cx
	GOSUB get_tile
	IF tile >= TILE_SOLID THEN hit = 1: RETURN
	#cx = tx: #cx = (#cx + 12) / 8
	IF #cx = last_cx THEN RETURN
	GOSUB get_tile
	IF tile >= TILE_SOLID THEN hit = 1
	END

' Legge il tile della cella (#cx, #cy). Fuori mappa = 0, come la VRAM
' vuota oltre la tabella dei nomi sull'MSX.
get_tile:	PROCEDURE
	#ta = #cy * 32 + #cx
	IF #ta >= 768 THEN tile = 0: RETURN
	tile = VPEEK($1800 + #ta)
	END

' isPlayerOnSpikes: tile sotto i piedi, colonna centrale
check_spikes:	PROCEDURE
	#cx = px / 8 + 1
	#cy = py / 8 + 2
	GOSUB get_tile
	hit = 0
	IF tile >= TILE_SPIKE_MIN AND tile <= TILE_SPIKE_MAX THEN hit = 1
	END

' bboxCollide(px, py, bx, by) con box 16x16 -> hit
' (aritmetica a 8 bit come nell'originale)
bbox_player:	PROCEDURE
	hit = 0
	a = px + 15
	IF a < bx THEN RETURN
	a = bx + 15
	IF px > a THEN RETURN
	a = py + 15
	IF a < by THEN RETURN
	a = by + 15
	IF py > a THEN RETURN
	hit = 1
	END

' TakeKey: luce verde sopra l'uscita e porta aperta
take_key:	PROCEDURE
	has_key = 1
	sfx_id = FX_GET_KEY: GOSUB sfx_play
	#ta = lvl_end_y - 1
	#ta = $1800 + #ta * 32 + lvl_end_x
	VPOKE #ta, 48
	VPOKE #ta + 1, 49
	VPOKE #ta + 32, TILE_EMPTY
	VPOKE #ta + 33, TILE_EMPTY
	VPOKE #ta + 64, TILE_EMPTY
	VPOKE #ta + 65, TILE_EMPTY
	END

' ============================================================================
' Disegno sprite
' ============================================================================
draw_player:	PROCEDURE
	a = py - 1					' Pawn_Draw: Y - 1
	SPRITE SPR_PLAYER, a, px, anim_frame, player_col1
	SPRITE SPR_PLAYER + 1, a, px, anim_frame + 4, player_col2
	END

draw_key:	PROCEDURE
	IF key_fly THEN
		' La chiave vola dal nemico colpito alla sua posizione
		fly_idx = fly_idx + 1
		#kt = key_x8: #kt = #kt - fly_sx: #kt = #kt * fly_idx / fly_frames
		kx = fly_sx + #kt
		#kt = key_y8: #kt = #kt - fly_sy: #kt = #kt * fly_idx / fly_frames
		ky = fly_sy + #kt
		IF fly_idx >= fly_frames THEN key_fly = 0: key_on = 1
		SPRITE SPR_KEY, ky, kx, FR_KEY, COL_BLACK
		RETURN
	END IF
	IF key_on = 0 THEN RETURN
	key_anim = key_anim + 1
	IF key_anim >= 40 THEN key_anim = 0
	f = FR_KEY
	IF key_anim >= 20 THEN f = f + 4
	IF f = key_last THEN RETURN			' sprite fermo: si riscrive solo al cambio frame
	key_last = f
	SPRITE SPR_KEY, key_y8, key_x8, f, COL_BLACK
	END

draw_crystal:	PROCEDURE
	IF crys_on = 0 THEN RETURN
	crys_anim = crys_anim + 1
	IF crys_anim >= 32 THEN crys_anim = 0
	f = FR_CRYSTAL
	IF crys_anim >= 16 THEN f = f + 4
	IF f = crys_last THEN RETURN
	crys_last = f
	SPRITE SPR_CRYSTAL, crys_y8, crys_x8, f, COL_MEDIUM_RED
	END

draw_platforms:	PROCEDURE
	fplat = FR_PLATFORM
	GOSUB draw_platforms_asm
	END

draw_platforms_asm:	PROCEDURE
	' sprite 7+ nella copia RAM della tabella sprite
	ASM li r5,sprites+28
	ASM clr r9
ASM dp_loop:
	ASM clr r0
	ASM movb @cvb_LVL_NPLAT,r0
	ASM swpb r0
	ASM c r9,r0
	ASM jl dp_body
	ASM b @dp_done
ASM dp_body:
	ASM movb @array_PLAT_Y(r9),*r5+
	ASM movb @array_PLAT_X(r9),*r5+
	ASM movb @cvb_FPLAT,*r5+
	ASM movb @cvb_PLAT_COL,*r5+
	ASM inc r9
	ASM jmp dp_loop
ASM dp_done:
	END

' Vortice visibile quando il player e' nelle prime 8 righe di pixel
draw_vortex:	PROCEDURE
	IF py >= 8 THEN RETURN
	vortex_anim = vortex_anim + 1
	IF vortex_anim >= 30 THEN vortex_anim = 0
	f = FR_VORTEX + (vortex_anim / 10) * 4
	SPRITE SPR_VORTEX, 0, 0, f, COL_WHITE
	END

' ============================================================================
' Nemici (UpdateEnemies)
' Tipo 0: lento. Tipo 1: veloce. Tipo 2: si ferma e crea un campo di energia
' davanti a se'. Tipo 3: si ferma e spara un proiettile.
' ============================================================================
update_enemies:	PROCEDURE
	' UpdateEnemies in assembler: in CVBasic costava fino a 10.000 cicli
	' per passo con 3 nemici. Logica identica alla versione BASIC precedente
	' (vedi commenti), r9 = indice del nemico.
	ASM clr r9
ASM ue_loop:
	ASM clr r0
	ASM movb @cvb_LVL_NENEMY,r0
	ASM swpb r0
	ASM c r9,r0
	ASM jl ue_body
	ASM b @ue_done
ASM ue_body:
	' --- proiettile in volo (si muove anche se il nemico e' stordito) ---
	ASM clr r8
	ASM movb @array_ENEMY_FSTATE(r9),r8
	ASM ci r8,>0200
	ASM jne ue_nobul
	ASM li r0,>0c00
	ASM movb @array_ENEMY_FDIR(r9),r1
	ASM jgt ue_bd
	ASM li r0,>f400
ASM ue_bd:
	ASM ab @array_ENEMY_FMDX(r9),r0
	ASM srl r0,8
	ASM mov r0,r1
	ASM movb @array_ENEMY_FX(r9),r3
	ASM ab @cvb_DPOS_Q(r1),r3
	ASM movb r3,@array_ENEMY_FX(r9)
	ASM movb @cvb_DPOS_R(r1),@array_ENEMY_FMDX(r9)
	ASM srl r3,8
	ASM ci r3,8
	ASM jl ue_bkill
	ASM ci r3,240
	ASM jle ue_nobul
ASM ue_bkill:
	ASM clr r8
	ASM movb r8,@array_ENEMY_FSTATE(r9)
ASM ue_nobul:
	' --- stordito: conta alla rovescia, niente altro ---
	ASM clr r0
	ASM movb @array_ENEMY_STUN(r9),r0
	ASM jeq ue_nostun
	ASM ai r0,-256
	ASM movb r0,@array_ENEMY_STUN(r9)
	ASM b @ue_next
ASM ue_nostun:
	ASM clr r7
	ASM movb @array_ENEMY_TYPE(r9),r7
	ASM ci r7,>0200
	ASM jl ue_move
	' --- tipi 2 e 3: pre-fuoco (stato 3) ---
	ASM ci r8,>0300
	ASM jne ue_nof3
	ASM clr r0
	ASM movb @array_ENEMY_FTIMER(r9),r0
	ASM ai r0,-256
	ASM movb r0,@array_ENEMY_FTIMER(r9)
	ASM jne ue_nx1
	ASM clr r0
	ASM movb @array_ENEMY_DIR(r9),r0
	ASM movb r0,@array_ENEMY_FDIR(r9)
	ASM sla r0,4
	ASM ab @array_ENEMY_X(r9),r0
	ASM movb r0,@array_ENEMY_FX(r9)
	ASM movb @array_ENEMY_Y(r9),@array_ENEMY_FY(r9)
	ASM ci r7,>0200
	ASM jne ue_shoot
	ASM mov @sfx_tab+8,@cvb__SFX_PTR	' FX_FORCE_FIELD
	ASM li r0,>0100
	ASM movb r0,@array_ENEMY_FSTATE(r9)
	ASM li r0,>6400
	ASM movb r0,@array_ENEMY_FTIMER(r9)
	ASM jmp ue_nx1
ASM ue_shoot:
	ASM mov @sfx_tab+20,@cvb__SFX_PTR	' FX_BULLET
	ASM li r0,>0200
	ASM movb r0,@array_ENEMY_FSTATE(r9)
	ASM clr r0
	ASM movb r0,@array_ENEMY_FMDX(r9)
ASM ue_nx1:
	ASM b @ue_next
ASM ue_nof3:
	' --- campo fisso attivo (stato 1): fermo finche' dura ---
	ASM ci r8,>0100
	ASM jne ue_nof1
	ASM clr r0
	ASM movb @array_ENEMY_FTIMER(r9),r0
	ASM ai r0,-256
	ASM movb r0,@array_ENEMY_FTIMER(r9)
	ASM jne ue_nx2
	ASM movb r0,@array_ENEMY_FSTATE(r9)
ASM ue_nx2:
	ASM b @ue_next
ASM ue_nof1:
	' --- nessun campo: 2 probabilita' su 256 di iniziare il pre-fuoco ---
	ASM mov r8,r8
	ASM jne ue_move
	ASM bl @random
	ASM andi r0,255
	ASM ci r0,2
	ASM jhe ue_move
	ASM li r0,>0300
	ASM movb r0,@array_ENEMY_FSTATE(r9)
	ASM li r0,>1900
	ASM movb r0,@array_ENEMY_FTIMER(r9)
ASM ue_move:
	' --- ronda: limiti, poi velocita' 2/8 (tipo 0) o 4/8 di pixel ---
	ASM clr r3
	ASM movb @array_ENEMY_X(r9),r3
	ASM clr r4
	ASM movb @array_ENEMY_DIR(r9),r4
	ASM cb r3,@array_ENEMY_MINX(r9)
	ASM jhe ue_l1
	ASM movb @array_ENEMY_MINX(r9),r3
	ASM neg r4
ASM ue_l1:
	ASM cb r3,@array_ENEMY_MAXX(r9)
	ASM jle ue_l2
	ASM movb @array_ENEMY_MAXX(r9),r3
	ASM neg r4
ASM ue_l2:
	ASM movb r4,@array_ENEMY_DIR(r9)
	ASM mov r4,r0
	ASM sla r0,1
	ASM mov r7,r7
	ASM jeq ue_s2
	ASM sla r0,1
ASM ue_s2:
	ASM ab @array_ENEMY_MDX(r9),r0
	ASM srl r0,8
	ASM mov r0,r1
	ASM ab @cvb_DPOS_Q(r1),r3
	ASM movb r3,@array_ENEMY_X(r9)
	ASM movb @cvb_DPOS_R(r1),@array_ENEMY_MDX(r9)
ASM ue_next:
	ASM inc r9
	ASM b @ue_loop
ASM ue_done:
	END

' (update_enemy in BASIC sostituita da update_enemies in assembler)

' ============================================================================
' Collisioni con mine, nemici, campi di energia
' ============================================================================

' rectCollide(r_ax1, r_ay1, r_ax2, r_ay2, r_bx1, r_by1, r_bx2, r_by2) -> rhit
rect_hit:	PROCEDURE
	rhit = 0
	IF r_ax2 < r_bx1 THEN RETURN
	IF r_ax1 > r_bx2 THEN RETURN
	IF r_ay2 < r_by1 THEN RETURN
	IF r_ay1 > r_by2 THEN RETURN
	rhit = 1
	END

' Box del player intero (16x16)
set_player_box:	PROCEDURE
	r_ax1 = px: r_ay1 = py: r_ax2 = px + 15: r_ay2 = py + 15
	END

' isPlayerOnMines: box parziale del player (8x16) contro il 2x1 della mina.
' Se colpita, mostra l'esplosione sopra la mina.
check_mines:	PROCEDURE
	GOSUB check_mines_asm
	IF hit_mine THEN SPRITE SPR_BOOM, mine_y(hm) - 16, mine_x(hm), FR_BOOM, COL_WHITE
	END

' isPlayerOnMines in assembler (aritmetica a 8 bit come i parametri u8 in C):
' box (px+4, py, px+11, py+15) contro (x+7, y-1, x+9, y). hm = mina colpita
check_mines_asm:	PROCEDURE
	ASM clr r8
	ASM movb @cvb_PX,r6
	ASM ai r6,>0400
	ASM movb @cvb_PX,r7
	ASM ai r7,>0b00
	ASM clr r9
ASM cm_loop:
	ASM clr r0
	ASM movb @cvb_LVL_NMINE,r0
	ASM swpb r0
	ASM c r9,r0
	ASM jl cm_body
	ASM b @cm_done
ASM cm_body:
	ASM movb @array_MINE_X(r9),r0
	ASM ai r0,>0700
	ASM cb r7,r0
	ASM jl cm_next
	ASM movb @array_MINE_X(r9),r0
	ASM ai r0,>0900
	ASM cb r6,r0
	ASM jh cm_next
	ASM movb @array_MINE_Y(r9),r0
	ASM ai r0,->0100
	ASM cb @cvb_PBY2,r0
	ASM jl cm_next
	ASM cb @cvb_PY,@array_MINE_Y(r9)
	ASM jh cm_next
	ASM li r8,>0100
	ASM mov r9,r0
	ASM swpb r0
	ASM movb r0,@cvb_HM
	ASM jmp cm_done
ASM cm_next:
	ASM inc r9
	ASM b @cm_loop
ASM cm_done:
	ASM movb r8,@cvb_HIT_MINE
	END

' isPlayerHitByEnemies: saltare in testa a un nemico lo stordisce (e puo'
' liberare la chiave), toccarlo altrimenti uccide.
check_enemies:	PROCEDURE
	GOSUB check_enemies_asm
	IF stomp_e < 255 THEN e = stomp_e: GOSUB stomp_enemy
	END

' isPlayerHitByEnemies in assembler. Box del player contro (x+4, y, x+11, y+15).
' Se il player scende sul nemico da sopra lo stordisce (stomp_e = indice),
' altrimenti un nemico non stordito uccide (hit = 1). Stordito da poco (>50): ignorato.
check_enemies_asm:	PROCEDURE
	ASM clr r8
	ASM li r7,>ff00
	ASM clr r9
ASM ce_loop:
	ASM clr r0
	ASM movb @cvb_LVL_NENEMY,r0
	ASM swpb r0
	ASM c r9,r0
	ASM jl ce_body
	ASM b @ce_done
ASM ce_body:
	ASM clr r3
	ASM movb @array_ENEMY_STUN(r9),r3
	ASM ci r3,>3200
	ASM jh ce_next
	ASM movb @array_ENEMY_X(r9),r0
	ASM ai r0,>0400
	ASM cb @cvb_PBX2,r0
	ASM jl ce_next
	ASM movb @array_ENEMY_X(r9),r0
	ASM ai r0,>0b00
	ASM cb @cvb_PX,r0
	ASM jh ce_next
	ASM cb @cvb_PBY2,@array_ENEMY_Y(r9)
	ASM jl ce_next
	ASM movb @array_ENEMY_Y(r9),r0
	ASM ai r0,>0f00
	ASM cb @cvb_PY,r0
	ASM jh ce_next
	' collisione: stordisce se il player e' sopra, sta scendendo e stun < 50
	ASM cb @cvb_PY,@array_ENEMY_Y(r9)
	ASM jhe ce_kill
	ASM movb @cvb_VEL_Y,r0
	ASM jgt ce_kill
	ASM jeq ce_kill
	ASM ci r3,>3200
	ASM jhe ce_kill
	ASM mov r9,r7
	ASM swpb r7
	ASM jmp ce_done
ASM ce_kill:
	ASM mov r3,r3
	ASM jne ce_next
	ASM li r8,>0100
	ASM jmp ce_done
ASM ce_next:
	ASM inc r9
	ASM b @ce_loop
ASM ce_done:
	ASM movb r8,@cvb_HIT
	ASM movb r7,@cvb_STOMP_E
	END

' Il player atterra sul nemico e
stomp_enemy:	PROCEDURE
	enemy_stun(e) = 100
	IF enemy_fstate(e) = 1 THEN enemy_fstate(e) = 0	' spegne il campo fisso, non i proiettili
	vel_y = FORCE						' piccolo salto
	jumping = 1
	sfx_id = FX_STOMP_ROBOT: GOSUB sfx_play
	' Se e' il nemico che custodisce la chiave, la chiave vola al suo posto
	IF key_on = 0 AND key_fly = 0 AND has_key = 0 AND lvl_ktrig = e THEN
		fly_sx = enemy_x(e): fly_sy = enemy_y(e)
		' MoveFrames a velocita' 2
		IF key_x8 >= fly_sx THEN a = key_x8 - fly_sx ELSE a = fly_sx - key_x8
		IF key_y8 >= fly_sy THEN b = key_y8 - fly_sy ELSE b = fly_sy - key_y8
		IF b > a THEN a = b
		IF a = 0 THEN a = 1
		#kt = a: fly_frames = (#kt + 1) / 2
		fly_idx = 0
		key_fly = 1
		sfx_id = FX_SHOW_KEY: GOSUB sfx_play
	END IF
	END

' isPlayerHitByEnergyFields: campo fisso (box 16x16) o proiettile (4x4,
' che sparisce quando colpisce)
check_fields:	PROCEDURE
	' isPlayerHitByEnergyFields in assembler: campo fisso con box 16x16,
	' proiettile 4x4 (x+6..x+9) che sparisce quando colpisce. hit = 1
	ASM clr r8
	ASM clr r9
ASM cf_loop:
	ASM clr r0
	ASM movb @cvb_LVL_NENEMY,r0
	ASM swpb r0
	ASM c r9,r0
	ASM jl cf_body
	ASM b @cf_done
ASM cf_body:
	ASM clr r3
	ASM movb @array_ENEMY_FSTATE(r9),r3
	ASM ci r3,>0100
	ASM jne cf_b
	ASM movb @array_ENEMY_FX(r9),r0
	ASM cb @cvb_PBX2,r0
	ASM jl cf_next
	ASM ai r0,>0f00
	ASM cb @cvb_PX,r0
	ASM jh cf_next
	ASM movb @array_ENEMY_FY(r9),r0
	ASM cb @cvb_PBY2,r0
	ASM jl cf_next
	ASM ai r0,>0f00
	ASM cb @cvb_PY,r0
	ASM jh cf_next
	ASM li r8,>0100
	ASM jmp cf_done
ASM cf_b:
	ASM ci r3,>0200
	ASM jne cf_next
	ASM movb @array_ENEMY_FX(r9),r0
	ASM ai r0,>0600
	ASM cb @cvb_PBX2,r0
	ASM jl cf_next
	ASM ai r0,>0300
	ASM cb @cvb_PX,r0
	ASM jh cf_next
	ASM movb @array_ENEMY_FY(r9),r0
	ASM ai r0,>0600
	ASM cb @cvb_PBY2,r0
	ASM jl cf_next
	ASM ai r0,>0300
	ASM cb @cvb_PY,r0
	ASM jh cf_next
	ASM clr r0
	ASM movb r0,@array_ENEMY_FSTATE(r9)
	ASM li r8,>0100
	ASM jmp cf_done
ASM cf_next:
	ASM inc r9
	ASM b @cf_loop
ASM cf_done:
	ASM movb r8,@cvb_HIT
	END

' ============================================================================
' Disegno di mine, nemici e campi
' ============================================================================

' Le mine lampeggiano: nere nella prima meta' di ogni secondo, rosse nell'altra
draw_mines:	PROCEDURE
	IF t_fs < 25 THEN c = COL_BLACK ELSE c = COL_LIGHT_RED
	IF c = mine_col THEN RETURN			' le mine non si muovono: si ridisegnano solo al cambio colore
	mine_col = c
	m = 0
	WHILE m < lvl_nmine
		SPRITE spr_mine + m, mine_y(m), mine_x(m), FR_MINE, c
		m = m + 1
	WEND
	END

draw_enemies:	PROCEDURE
	enemy_anim = enemy_anim + 1
	IF enemy_anim >= 20 THEN enemy_anim = 0
	enemy_hint = enemy_hint + 1
	IF enemy_hint >= 250 THEN enemy_hint = 0
	' Colore comune e nemico-indizio (chi custodisce la chiave lampeggia)
	hint_e = 255
	IF rew_white THEN
		c0 = COL_WHITE
	ELSE
		c0 = COL_BLACK
		IF key_on = 0 AND has_key = 0 AND enemy_hint < 10 AND lvl_ktrig >= 0 THEN hint_e = lvl_ktrig
	END IF
	anim_add = 0
	IF enemy_anim >= 10 THEN anim_add = 4
	GOSUB draw_enemies_asm
	END

' Scrive direttamente nella copia RAM della tabella sprite di CVBasic
' (sprites: Y, X, frame, colore), come farebbe SPRITE.
' Frame: base del tipo + animazione, +16 stordito, +8 se va a destra.
draw_enemies_asm:	PROCEDURE
	ASM clr r5
	ASM movb @cvb_SPR_ENEMY,r5
	ASM srl r5,6
	ASM ai r5,sprites
	ASM clr r9
ASM de_loop:
	ASM clr r0
	ASM movb @cvb_LVL_NENEMY,r0
	ASM swpb r0
	ASM c r9,r0
	ASM jhe de_done
	ASM movb @array_ENEMY_Y(r9),*r5+
	ASM movb @array_ENEMY_X(r9),*r5+
	ASM movb @array_ENEMY_FBASE(r9),r0
	ASM ab @cvb_ANIM_ADD,r0
	ASM movb @array_ENEMY_STUN(r9),r1
	ASM jeq de_ns
	ASM ai r0,>1000
	ASM jmp de_f
ASM de_ns:
	ASM movb @array_ENEMY_DIR(r9),r1
	ASM jlt de_f
	ASM ai r0,>0800
ASM de_f:
	ASM movb r0,*r5+
	ASM movb @cvb_C0,r0
	ASM mov r9,r1
	ASM swpb r1
	ASM cb r1,@cvb_HINT_E
	ASM jne de_c
	ASM li r0,>0600
ASM de_c:
	ASM movb r0,*r5+
	ASM inc r9
	ASM jmp de_loop
ASM de_done:
	END

draw_fields:	PROCEDURE
	field_anim = field_anim + 1
	IF field_anim >= 16 THEN field_anim = 0
	' frame e colori della passata: proiettile, campo fisso (lampeggia)
	ff = FR_ENERGYFIELD
	IF field_anim >= 8 THEN ff = ff + 4
	fbul = FR_BULLET
	IF rew_white THEN
		cb = COL_WHITE: cf = COL_WHITE
	ELSE
		cb = COL_LIGHT_RED
		IF field_anim AND 1 THEN cf = COL_DARK_RED ELSE cf = COL_MAGENTA
	END IF
	GOSUB draw_fields_asm
	END

' Per ogni nemico: proiettile (stato 2), campo fisso (stato 1), oppure
' sprite nascosto (solo la prima volta dopo che si spegne).
draw_fields_asm:	PROCEDURE
	ASM clr r5
	ASM movb @cvb_SPR_FIELD,r5
	ASM srl r5,6
	ASM ai r5,sprites
	ASM clr r9
ASM df_loop:
	ASM clr r0
	ASM movb @cvb_LVL_NENEMY,r0
	ASM swpb r0
	ASM c r9,r0
	ASM jhe df_done
	ASM clr r0
	ASM movb @array_ENEMY_FSTATE(r9),r0
	ASM ci r0,>0200
	ASM jne df_1
	ASM movb @array_ENEMY_FY(r9),*r5+
	ASM movb @array_ENEMY_FX(r9),*r5+
	ASM movb @cvb_FBUL,*r5+
	ASM movb @cvb_CB,*r5+
	ASM jmp df_vis
ASM df_1:
	ASM ci r0,>0100
	ASM jne df_0
	ASM movb @array_ENEMY_FY(r9),*r5+
	ASM movb @array_ENEMY_FX(r9),*r5+
	ASM movb @cvb_FF,*r5+
	ASM movb @cvb_CF,*r5+
	ASM jmp df_vis
ASM df_0:
	ASM movb @array_FIELD_VIS(r9),r1
	ASM jeq df_skip
	ASM li r1,>c000
	ASM movb r1,*r5
ASM df_skip:
	ASM ai r5,4
ASM df_vis:
	ASM movb r0,@array_FIELD_VIS(r9)
	ASM inc r9
	ASM jmp df_loop
ASM df_done:
	END

' ============================================================================
' HUD: tempo e indicatore del rewind (riga 0)
' ============================================================================
print_time:	PROCEDURE
	numbuf(0) = t_min / 10 + 1: numbuf(1) = t_min % 10 + 1
	SCREEN numbuf, 0, 7, 2, 1
	numbuf(0) = t_sec / 10 + 1: numbuf(1) = t_sec % 10 + 1
	SCREEN numbuf, 0, 10, 2, 1
	END

' DrawRewindGauge: 8 caselle, ridisegnate solo se cambiano
draw_gauge:	PROCEDURE
	a = rew_energy / (REWIND_MAX / 8)
	IF a = gauge_shown THEN RETURN
	gauge_shown = a
	VPOKE $1800 + 20, 90
	FOR i = 0 TO 7
		IF i < a THEN VPOKE $1800 + 21 + i, 62 ELSE VPOKE $1800 + 21 + i, 63
	NEXT i
	END

' ============================================================================
' Orologio (tickDir / warpTime)
' ============================================================================
tick_down:	PROCEDURE
	IF t_fs = 0 THEN
		IF t_sec = 0 THEN
			IF t_min = 0 THEN RETURN
			t_min = t_min - 1
			t_sec = 59
		ELSE
			t_sec = t_sec - 1
		END IF
		t_fs = 49
	ELSE
		t_fs = t_fs - 1
	END IF
	END

tick_up:	PROCEDURE
	IF t_fs < 49 THEN
		t_fs = t_fs + 1
	ELSE
		t_fs = 0
		IF t_sec < 59 THEN
			t_sec = t_sec + 1
		ELSE
			t_sec = 0
			t_min = t_min + 1
		END IF
	END IF
	END

' warpTime: +/- 5 minuti con il conto che scorre (warp_up = 1 aggiunge)
warp_time:	PROCEDURE
	FOR j = 1 TO 50
		IF warp_up THEN
			FOR #w = 1 TO 301: GOSUB tick_up: NEXT #w
		ELSE
			FOR #w = 1 TO 299: GOSUB tick_down: NEXT #w
		END IF
		GOSUB print_time
	NEXT j
	END

' ============================================================================
' Morte (State_Death): salto all'indietro e caduta fuori schermo
' ============================================================================
death_start:	PROCEDURE
	sfx_id = FX_DEATH: GOSUB sfx_play
	m_dx = 0: m_dy = 0
	vel_y = FORCE
	dying = 1
	END

death_step:	PROCEDURE
	game_event = EV_NONE
	IF py < 192 THEN
		GOSUB apply_gravity
		u = m_dy: d_y = dpos_q(u): m_dy = dpos_r(u)
		new_act = ACT_DEATH: GOSUB set_action
		py = py + d_y
		GOSUB update_animation
		GOSUB draw_player
	END IF
	IF py >= 192 THEN
		' Ogni morte costa 5 minuti
		IF t_min <> 0 OR t_sec <> 0 THEN warp_up = 0: GOSUB warp_time
		IF t_min = 0 AND t_sec = 0 THEN
			game_event = EV_GAMEOVER
		ELSE
			BORDER COL_WHITE		' lampo bianco al respawn
			GOSUB player_restart
			WAIT
			BORDER COL_BLACK
			game_event = EV_RESPAWN
		END IF
	END IF
	END
