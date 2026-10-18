' ============================================================================
' Chrono Runner TI-99/4A - Boss finale
'
' Port di InitBoss / State_Boss / DrawBossStance (chronorunner_s7_b1.c).
'
' Il boss e' disegnato con i tile: ogni postura e' un rettangolo 14x11 preso
' da uno dei due "fogli" (schermata 85: posture 0-3, schermata 89: 4-7) e
' copiato sull'arena (schermata 84). Pattuglia a destra e a sinistra, ogni
' 4 secondi spara un proiettile verso il giocatore. Saltandogli in testa lo
' si stordisce e si libera un vortice che vola in un angolo: toccandolo, il
' vortice torna indietro e lo colpisce. Al quinto colpo e' sconfitto.
'
' Il tempo rimasto viene salvato (e' il punteggio) e azzerato: una morte
' durante il boss porta sempre al GAME OVER, come nell'originale.
'
' Tutto questo file sta nel banco 9 (BOSS_BANK) insieme ai dati del boss:
' chi lo chiama dal banco 0 deve prima fare BANK SELECT BOSS_BANK.
' Da qui si possono chiamare le procedure del banco 0 che non cambiano banco.
'
' Codice: GPLv3
' ============================================================================

CONST BOSS_SWITCH_FRAMES = 25		' passi tra un cambio di postura e l'altro
CONST BOSS_DEFEAT_FRAMES = 250		' passi sulla postura di sconfitta
CONST BOSS_STANCE_W = 14
CONST BOSS_STANCE_H = 11
CONST BOSS_STANCE_DST_X = 9
CONST BOSS_STANCE_DST_Y = 12
CONST BOSS_HEAD_Y1 = 96				' testa: fascia 24x8 a 40 pixel dal bordo della postura
CONST BOSS_HEAD_Y2 = 103
CONST BOSS_HEAD_OFFSET_X = 40
CONST BOSS_HEAD_W = 23
CONST BOSS_START_X = 16
CONST BOSS_START_Y = 144
CONST BOSS_HITS_REQUIRED = 5
CONST BOSS_PREFIRE = 4				' posture
CONST BOSS_FIRE = 5
CONST BOSS_STUN = 6
CONST BOSS_DEFEAT = 7
CONST BOSS_FIRE_FRAMES = 200			' attesa tra un colpo e l'altro
CONST BOSS_FIRE_PRE_FRAMES = 25
CONST BOSS_FIRE_SHOOT_FRAMES = 50
CONST BOSS_WALK_MARGIN = 8
CONST FIRE_IDLE = 0
CONST FIRE_PRE = 1
CONST FIRE_SHOOT = 2
CONST VX_NONE = 0					' stati del vortice
CONST VX_TO_SLOT = 1
CONST VX_AT_SLOT = 2
CONST VX_TO_BOSS = 3

' Angoli dove si posano i vortici (in tile): un colpo, un angolo
boss_vpos:
	DATA BYTE 4, 19, 6, 4, 24, 4, 26, 19
' Sequenze di pattuglia: postura e spostamento in tile (255 = -1)
boss_wr_st:
	DATA BYTE 2, 0, 1, 3, 2
boss_wr_dx:
	DATA BYTE 0, 0, 1, 1, 0
boss_wl_st:
	DATA BYTE 2, 3, 1, 0, 2
boss_wl_dx:
	DATA BYTE 0, 0, 255, 255, 0

' ----------------------------------------------------------------------------
' InitBoss
' ----------------------------------------------------------------------------
boss_init:	PROCEDURE
	b_hits = 0
	b_dstx = BOSS_STANCE_DST_X
	b_bul = 0
	b_ftimer = 0: b_fphase = FIRE_IDLE
	v_state = VX_NONE: v_anim = 0
	b_dir = 1
	' il tempo rimasto e' il punteggio; azzerato, ogni morte e' game over
	t_min_bk = t_min: t_sec_bk = t_sec
	t_min = 0: t_sec = 0
	dying = 0
	m_dx = 0: m_dy = 0: vel_y = 0

	' Arena: solo le 4 piattaforme
	FOR p = 0 TO BOSS_NPLAT - 1
		#ta = p * 8
		plat_x(p) = boss_plat(#ta): plat_y(p) = boss_plat(#ta + 1)
		plat_dx(p) = boss_plat(#ta + 2): plat_dy(p) = boss_plat(#ta + 3)
		plat_minx(p) = boss_plat(#ta + 4): plat_miny(p) = boss_plat(#ta + 5)
		plat_maxx(p) = boss_plat(#ta + 6): plat_maxy(p) = boss_plat(#ta + 7)
	NEXT p
	lvl_nplat = BOSS_NPLAT: lvl_nmine = 0: lvl_nenemy = 0
	lvl_ktrig = -1
	GOSUB allocate_sprites
	plat_col = COL_BLACK: rew_white = 0

	SCREEN DISABLE
	GOSUB hide_sprites
	SCREEN boss_s84
	b_full = 1						' il primo disegno ripulisce tutto il rettangolo
	GOSUB boss_start_walk
	SCREEN ENABLE

	' ReinitPlayer
	px = BOSS_START_X: py = BOSS_START_Y
	act = ACT_IDLE: anim_step = 0: anim_timer = 0
	player_col1 = COL_BLACK: player_col2 = COL_DARK_YELLOW
	mus_req = MUSIC_BOSS: GOSUB music_select
	END

' ----------------------------------------------------------------------------
' Un passo del combattimento (State_Boss). game_event: EV_DEATH o EV_BOSS_END
' ----------------------------------------------------------------------------
boss_step:	PROCEDURE
	game_event = EV_NONE
	GOSUB read_input
	GOSUB update_platforms
	plat_on = 0
	GOSUB find_platform
	GOSUB update_movement
	GOSUB update_action
	GOSUB set_action
	GOSUB update_animation
	GOSUB update_physics
	pbx2 = px + 15: pby2 = py + 15
	GOSUB draw_player
	GOSUB draw_platforms

	' --- Sparo in tre fasi: attesa, pre-fuoco, fuoco ---
	IF b_fphase = FIRE_IDLE THEN
		' il timer carica solo durante la pattuglia
		IF b_screen < 4 THEN
			b_ftimer = b_ftimer + 1
			IF b_ftimer >= BOSS_FIRE_FRAMES AND b_bul = 0 THEN
				b_ftimer = BOSS_FIRE_PRE_FRAMES
				b_fphase = FIRE_PRE
				b_screen = BOSS_PREFIRE
				GOSUB boss_draw
			END IF
		END IF
	ELSEIF b_fphase = FIRE_PRE THEN
		b_ftimer = b_ftimer - 1
		IF b_ftimer = 0 THEN
			' parte il proiettile dalla testa verso il centro del player
			b_bul = 1
			sfx_id = FX_BULLET: GOSUB sfx_play
			mf_sx = b_dstx * 8 + BOSS_HEAD_OFFSET_X + 8
			mf_sy = (BOSS_HEAD_Y1 + BOSS_HEAD_Y2) / 2
			mf_tx = px + 8: mf_ty = py + 8
			GOSUB move_frames
			bb_sx = mf_sx: bb_sy = mf_sy: bb_tx = mf_tx: bb_ty = mf_ty
			bb_n = mf_n: bb_i = 0
			b_ftimer = BOSS_FIRE_SHOOT_FRAMES
			b_fphase = FIRE_SHOOT
			b_screen = BOSS_FIRE
			GOSUB boss_draw
		END IF
	ELSE
		b_ftimer = b_ftimer - 1
		IF b_ftimer = 0 THEN
			b_fphase = FIRE_IDLE
			b_ftimer = 0
			GOSUB boss_start_walk
		END IF
	END IF

	' --- Proiettile: movimento, disegno, collisione ---
	IF b_bul THEN
		bb_i = bb_i + 1
		l_sx = bb_sx: l_sy = bb_sy: l_tx = bb_tx: l_ty = bb_ty: l_i = bb_i: l_n = bb_n
		GOSUB lerp_xy
		IF bb_i >= bb_n OR l_x < 4 OR l_x > 248 OR l_y > 192 THEN
			b_bul = 0
			SPRITE SPR_VORTEX, 192, 0, 0, 0
		ELSE
			r_ax1 = px: r_ay1 = py: r_ax2 = pbx2: r_ay2 = pby2
			r_bx1 = l_x + 6: r_by1 = l_y + 6: r_bx2 = l_x + 9: r_by2 = l_y + 9
			GOSUB rect_hit
			IF rhit THEN
				b_bul = 0
				SPRITE SPR_VORTEX, 192, 0, 0, 0
				game_event = EV_DEATH
				RETURN
			END IF
			SPRITE SPR_VORTEX, l_y, l_x, FR_BULLET, COL_LIGHT_RED
		END IF
	END IF

	' --- Salto sulla testa (non durante stordimento o sconfitta) ---
	IF b_screen <> BOSS_STUN AND b_screen <> BOSS_DEFEAT THEN
		r_ax1 = px: r_ay1 = py: r_ax2 = pbx2: r_ay2 = pby2
		r_bx1 = b_dstx * 8 + BOSS_HEAD_OFFSET_X: r_by1 = BOSS_HEAD_Y1
		r_bx2 = r_bx1 + BOSS_HEAD_W: r_by2 = BOSS_HEAD_Y2
		GOSUB rect_hit
		IF rhit AND py < BOSS_HEAD_Y1 AND vel_y < 0 THEN
			b_hits = b_hits + 1
			vel_y = FORCE
			jumping = 1
			IF b_hits < BOSS_HITS_REQUIRED THEN
				sfx_id = FX_STOMP_ROBOT
			ELSE
				' sconfitto: musica ferma ed esplosione
				mus_req = MUSIC_NONE: GOSUB music_select
				sfx_id = FX_BOSS_DEATH
			END IF
			GOSUB sfx_play
			IF b_hits < BOSS_HITS_REQUIRED THEN
				' il vortice vola dalla testa al suo angolo
				a = (b_hits - 1) * 2
				mf_sx = b_dstx * 8 + BOSS_HEAD_OFFSET_X + 8
				mf_sy = (BOSS_HEAD_Y1 + BOSS_HEAD_Y2) / 2
				mf_tx = boss_vpos(a) * 8: mf_ty = boss_vpos(a + 1) * 8
				GOSUB move_frames
				v_sx = mf_sx: v_sy = mf_sy: v_tx = mf_tx: v_ty = mf_ty
				v_n = mf_n: v_i = 0
				v_state = VX_TO_SLOT
				v_anim = 0
			END IF
			b_frame = 0
			b_fphase = FIRE_IDLE
			b_ftimer = 0
			IF b_hits >= BOSS_HITS_REQUIRED THEN b_screen = BOSS_DEFEAT ELSE b_screen = BOSS_STUN
			GOSUB boss_draw
		END IF
	END IF

	' --- Cambio di postura ogni 25 passi (fermo se stordito o mentre spara) ---
	IF b_screen <> BOSS_STUN AND b_fphase = FIRE_IDLE THEN
		b_frame = b_frame + 1
		IF b_screen = BOSS_DEFEAT THEN a = BOSS_DEFEAT_FRAMES ELSE a = BOSS_SWITCH_FRAMES
		IF b_frame >= a THEN
			b_frame = 0
			IF b_screen = BOSS_DEFEAT THEN
				mus_req = MUSIC_INTRO: GOSUB music_select
				game_event = EV_BOSS_END: RETURN
			END IF
			IF b_dir THEN
				b_screen = boss_wl_st(b_step): b_dstx = b_dstx + boss_wl_dx(b_step)
			ELSE
				b_screen = boss_wr_st(b_step): b_dstx = b_dstx + boss_wr_dx(b_step)
			END IF
			b_step = b_step + 1
			IF b_step >= 5 THEN
				b_step = 0
				GOSUB boss_choose_dir
				b_dir = a
			END IF
			GOSUB boss_draw
		END IF
	END IF

	' --- Vortice: verso l'angolo, in attesa, di ritorno contro il boss ---
	IF v_state <> VX_NONE THEN
		v_anim = v_anim + 1
		IF v_anim >= 30 THEN v_anim = 0
		f = FR_VORTEX + (v_anim / 10) * 4
		IF v_state = VX_TO_SLOT THEN
			v_i = v_i + 1
			l_sx = v_sx: l_sy = v_sy: l_tx = v_tx: l_ty = v_ty: l_i = v_i: l_n = v_n
			GOSUB lerp_xy
			IF v_i >= v_n THEN v_state = VX_AT_SLOT
			SPRITE SPR_VORTEX, l_y, l_x, f, COL_WHITE
		ELSEIF v_state = VX_AT_SLOT THEN
			SPRITE SPR_VORTEX, v_ty, v_tx, f, COL_WHITE
			r_ax1 = px: r_ay1 = py: r_ax2 = pbx2: r_ay2 = pby2
			r_bx1 = v_tx: r_by1 = v_ty: r_bx2 = v_tx + 15: r_by2 = v_ty + 15
			GOSUB rect_hit
			IF rhit THEN
				' il giocatore lo rimanda contro il boss
				mf_sx = v_tx: mf_sy = v_ty
				mf_tx = b_dstx * 8 + BOSS_HEAD_OFFSET_X + 8
				mf_ty = (BOSS_HEAD_Y1 + BOSS_HEAD_Y2) / 2
				GOSUB move_frames
				v_sx = mf_sx: v_sy = mf_sy: v_tx = mf_tx: v_ty = mf_ty
				v_n = mf_n: v_i = 0
				v_state = VX_TO_BOSS
				sfx_id = FX_VORTEX_FIRE: GOSUB sfx_play
			END IF
		ELSE
			v_i = v_i + 1
			IF v_i >= v_n THEN
				' colpito: il boss riprende la pattuglia
				v_state = VX_NONE
				SPRITE SPR_VORTEX, 192, 0, 0, 0
				sfx_id = FX_STOMP_ROBOT: GOSUB sfx_play	' come l'originale (segnaposto)
				b_fphase = FIRE_IDLE
				b_ftimer = 0
				GOSUB boss_start_walk
			ELSE
				l_sx = v_sx: l_sy = v_sy: l_tx = v_tx: l_ty = v_ty: l_i = v_i: l_n = v_n
				GOSUB lerp_xy
				SPRITE SPR_VORTEX, l_y, l_x, f, COL_LIGHT_RED
			END IF
		END IF
	END IF
	END

' ChooseWalkDir -> a (0 destra, 1 sinistra): continua se c'e' spazio
boss_choose_dir:	PROCEDURE
	IF b_dir = 1 THEN
		IF b_dstx >= BOSS_WALK_MARGIN THEN a = 1 ELSE a = 0
	ELSE
		IF b_dstx + BOSS_STANCE_W + BOSS_WALK_MARGIN <= 32 THEN a = 0 ELSE a = 1
	END IF
	END

' StartBossWalkCycle: riparte dal passo 0 della sequenza
boss_start_walk:	PROCEDURE
	GOSUB boss_choose_dir
	b_dir = a
	b_step = 1
	b_screen = 2				' il passo 0 e' la postura 2 in entrambe le sequenze
	b_frame = 0
	GOSUB boss_draw
	END

' DrawBossStance: sfondo dell'arena (tile 84) e postura corrente.
' La copia e' in assembler: con SCREEN costava piu' di un frame.
boss_draw:	PROCEDURE
	a = b_screen AND 3
	IF a AND 1 THEN b = 17 ELSE b = 1		' colonna nel foglio
	IF a AND 2 THEN c = 13 ELSE c = 1		' riga nel foglio
	#tb = c: #tb = #tb * 32 + b				' offset della postura nel foglio
	#ta = BOSS_STANCE_DST_Y * 32 + b_dstx	' offset di destinazione sullo schermo
	GOSUB boss_draw_asm
	END

' Come l'originale riempie il rettangolo 20x13 da (6,10) con il tile 84 e
' copia 14x11 tile dal foglio (schermata 85 per le posture 0-3, 89 per 4-7)
' a #ta. Il riempimento completo serve solo la prima volta (b_full): poi il
' boss si sposta al massimo di una colonna, quindi basta ripulire le due
' colonne ai lati della postura. Il risultato a schermo e' lo stesso.
' Interrupt sospesi durante le scritture: anche l'interrupt usa la VDP.
boss_draw_asm:	PROCEDURE
	ASM limi 0
	ASM movb @cvb_B_FULL,r0
	ASM jeq bd_side
	ASM clr r0
	ASM movb r0,@cvb_B_FULL
	' >5946 = >5800 (scrittura VDP) + 10*32 + 6. Le costanti sono gia' calcolate:
	' l'assemblatore TI valuta da sinistra a destra, senza precedenze.
	ASM li r3,>5946
	ASM li r4,13
	ASM li r1,>5400
ASM bd_f1:
	ASM swpb r3
	ASM movb r3,@VDPWADR
	ASM swpb r3
	ASM movb r3,@VDPWADR
	ASM li r2,20
ASM bd_f2:
	ASM movb r1,@VDPWDATA
	ASM dec r2
	ASM jne bd_f2
	ASM ai r3,32
	ASM dec r4
	ASM jne bd_f1
	ASM jmp bd_src
	' colonne ai lati (solo se dentro il rettangolo 6-25)
ASM bd_side:
	ASM li r1,>5400
	ASM clr r6
	ASM movb @cvb_B_DSTX,r6
	ASM swpb r6
	ASM mov r6,r7
	ASM dec r7
	ASM ci r7,6
	ASM jl bd_r
	ASM li r3,>5980
	ASM a r7,r3
	ASM bl @bd_col
ASM bd_r:
	ASM mov r6,r7
	ASM ai r7,14
	ASM ci r7,25
	ASM jgt bd_src
	ASM li r3,>5980
	ASM a r7,r3
	ASM bl @bd_col
	ASM jmp bd_src
	' scrive il tile in r1 su 11 righe a partire dall'indirizzo VDP in r3
ASM bd_col:
	ASM li r4,11
ASM bd_cl:
	ASM swpb r3
	ASM movb r3,@VDPWADR
	ASM swpb r3
	ASM movb r3,@VDPWADR
	ASM movb r1,@VDPWDATA
	ASM ai r3,32
	ASM dec r4
	ASM jne bd_cl
	ASM b *r11
	' sorgente: foglio + #tb
ASM bd_src:
	ASM li r5,cvb_BOSS_S85
	ASM movb @cvb_B_SCREEN,r0
	ASM ci r0,>0400
	ASM jl bd_s
	ASM li r5,cvb_BOSS_S89
ASM bd_s:
	ASM a @cvb__TB,r5
	ASM mov @cvb__TA,r3
	ASM ai r3,>5800
	ASM li r4,11
ASM bd_c1:
	ASM swpb r3
	ASM movb r3,@VDPWADR
	ASM swpb r3
	ASM movb r3,@VDPWADR
	ASM li r2,14
ASM bd_c2:
	ASM movb *r5+,@VDPWDATA
	ASM dec r2
	ASM jne bd_c2
	ASM ai r5,32-14
	ASM ai r3,32
	ASM dec r4
	ASM jne bd_c1
	ASM limi 2
	END

' MoveFrames(mf_sx, mf_sy, mf_tx, mf_ty, velocita' 2) -> mf_n
move_frames:	PROCEDURE
	IF mf_tx >= mf_sx THEN a = mf_tx - mf_sx ELSE a = mf_sx - mf_tx
	IF mf_ty >= mf_sy THEN b = mf_ty - mf_sy ELSE b = mf_sy - mf_ty
	IF b > a THEN a = b
	IF a = 0 THEN a = 1
	#tb = a: mf_n = (#tb + 1) / 2
	END

' Interpolazione lineare: l = s + (t - s) * l_i / l_n (con segno)
lerp_xy:	PROCEDURE
	#kt = l_tx: #kt = #kt - l_sx: #kt = #kt * l_i / l_n
	l_x = l_sx + #kt
	#kt = l_ty: #kt = #kt - l_sy: #kt = #kt * l_i / l_n
	l_y = l_sy + #kt
	END
