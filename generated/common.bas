' ========================================================================
' Definizioni comuni (banco 0): costanti, variabili livello, caricatori
' Generato da tools/msx2cvb.py - NON modificare a mano
' Asset originali: Associazione MSX Italia, licenza CC BY-NC-SA 4.0
' ========================================================================

' --- Tile speciali ---
CONST TILE_EMPTY = 47

' --- Frame sprite (valore 'f' di SPRITE, = indice pattern MSX) ---
CONST FR_PLAYER = 0	' 11 frame, 2 layer
CONST FR_KEY = 88	' 2 frame, 1 layer
CONST FR_CRYSTAL = 96	' 2 frame, 1 layer
CONST FR_DOC = 104	' 4 frame, 1 layer
CONST FR_VORTEX = 120	' 3 frame, 1 layer
CONST FR_PLATFORM = 132	' 1 frame, 1 layer
CONST FR_MINE = 136	' 1 frame, 1 layer
CONST FR_BOOM = 140	' 1 frame, 1 layer
CONST FR_ENEMY0 = 144	' 6 frame, 1 layer
CONST FR_ENEMY1 = 168	' 6 frame, 1 layer
CONST FR_ENEMY2 = 192	' 6 frame, 1 layer
CONST FR_ENEMY3 = 216	' 6 frame, 1 layer
CONST FR_ENERGYFIELD = 240	' 2 frame, 1 layer
CONST FR_BULLET = 248	' 1 frame, 1 layer
CONST FR_HITLER = 252	' 1 frame, 1 layer
CONST FR_PLAYER_STEP = 8	' player: frame n = FR_PLAYER + n*8, layer 1 = +4
CONST FR_ENEMY_STEP = 24	' nemico tipo t = FR_ENEMY0 + t*24, frame n = +n*4

' --- Livelli ---
CONST NUM_LEVELS = 29	' livelli della sequenza principale
CONST NUM_LEVELS_ALL = 33	' + livelli segreti
CONST MAX_PLATFORMS = 4
CONST MAX_MINES = 6
CONST MAX_ENEMIES = 4
CONST LEVEL_MAP_OFFSET = 64	' la mappa parte dalla riga 2

' --- Schermate UI (valori per ui_screen) ---
CONST UI_MENU = 0
CONST UI_CREDITS1 = 1
CONST UI_CREDITS2 = 2
CONST UI_RATING = 3
CONST UI_INTERMISSION = 4
CONST UI_HOWTO1 = 5
CONST UI_HOWTO2 = 6
CONST UI_HOWTO3 = 7

' --- Stato del livello corrente (caricato da read_level_obj) ---
DIM plat_x(MAX_PLATFORMS), plat_y(MAX_PLATFORMS), plat_dx(MAX_PLATFORMS), plat_dy(MAX_PLATFORMS)
DIM plat_minx(MAX_PLATFORMS), plat_miny(MAX_PLATFORMS), plat_maxx(MAX_PLATFORMS), plat_maxy(MAX_PLATFORMS)
DIM mine_x(MAX_MINES), mine_y(MAX_MINES)
DIM enemy_x(MAX_ENEMIES), enemy_y(MAX_ENEMIES), enemy_dir(MAX_ENEMIES)
DIM enemy_minx(MAX_ENEMIES), enemy_maxx(MAX_ENEMIES), enemy_type(MAX_ENEMIES)
DIM lvl_name(32)
SIGNED plat_dx, plat_dy, enemy_dir, lvl_ktrig

' Indice livello -> banco e posizione nel banco
level_bank_tab:
	DATA BYTE $02,$02,$02,$02,$02,$02,$02,$02,$02,$03,$03,$03,$03,$03,$03,$03
	DATA BYTE $03,$03,$04,$04,$04,$04,$04,$04,$04,$04,$04,$05,$05,$05,$05,$05
	DATA BYTE $05
level_sub_tab:
	DATA BYTE $00,$01,$02,$03,$04,$05,$06,$07,$08,$00,$01,$02,$03,$04,$05,$06
	DATA BYTE $07,$08,$00,$01,$02,$03,$04,$05,$06,$07,$08,$00,$01,$02,$03,$04
	DATA BYTE $05

' Carica grafica (tileset + sprite) in VRAM
load_gfx:	PROCEDURE
	BANK SELECT 1
	GOSUB gfx_load_bank
	END

' Disegna la mappa del livello cur_level e ne carica gli oggetti
' (con lvl_noscreen = 1 carica solo i dati, senza disegnare: serve all'intermezzo)
load_level:	PROCEDURE
	lvl_sub = level_sub_tab(cur_level)
	ON level_bank_tab(cur_level) - 2 GOSUB load_level_b2,load_level_b3,load_level_b4,load_level_b5
	END

load_level_b2:	PROCEDURE
	BANK SELECT 2
	GOSUB lvl_load_bank2
	END

load_level_b3:	PROCEDURE
	BANK SELECT 3
	GOSUB lvl_load_bank3
	END

load_level_b4:	PROCEDURE
	BANK SELECT 4
	GOSUB lvl_load_bank4
	END

load_level_b5:	PROCEDURE
	BANK SELECT 5
	GOSUB lvl_load_bank5
	END

' Mostra la schermata UI indicata da ui_screen (32x24)
show_ui:	PROCEDURE
	BANK SELECT 6
	GOSUB ui_show_bank
	END

' Legge il record oggetti (113 byte) puntato dall'ultimo RESTORE
read_level_obj:	PROCEDURE
	READ BYTE lvl_start_x: READ BYTE lvl_start_y
	READ BYTE lvl_end_x: READ BYTE lvl_end_y
	READ BYTE lvl_key_x: READ BYTE lvl_key_y
	READ BYTE lvl_crys_x: READ BYTE lvl_crys_y
	READ BYTE lvl_ktrig	' -1 = chiave visibile, 0-3 = nemico da colpire
	READ BYTE lvl_nplat
	FOR lvl_i = 0 TO MAX_PLATFORMS - 1
		READ BYTE plat_x(lvl_i): READ BYTE plat_y(lvl_i)
		READ BYTE plat_dx(lvl_i): READ BYTE plat_dy(lvl_i)
		READ BYTE plat_minx(lvl_i): READ BYTE plat_miny(lvl_i)
		READ BYTE plat_maxx(lvl_i): READ BYTE plat_maxy(lvl_i)
	NEXT lvl_i
	READ BYTE lvl_nmine
	FOR lvl_i = 0 TO MAX_MINES - 1
		READ BYTE mine_x(lvl_i): READ BYTE mine_y(lvl_i)
	NEXT lvl_i
	READ BYTE lvl_nenemy
	FOR lvl_i = 0 TO MAX_ENEMIES - 1
		READ BYTE enemy_x(lvl_i): READ BYTE enemy_y(lvl_i): READ BYTE enemy_dir(lvl_i)
		READ BYTE enemy_minx(lvl_i): READ BYTE enemy_maxx(lvl_i): READ BYTE enemy_type(lvl_i)
	NEXT lvl_i
	READ BYTE lvl_name_len
	FOR lvl_i = 0 TO 31
		READ BYTE lvl_name(lvl_i)
	NEXT lvl_i
	END

' --- Cutscene e sequenza di gioco ---
CONST CUT_SCR_BANK = 7
CONST CUT_BANK = 8
CONST CUT_WORLD1END = 0
CONST CUT_WORLD2END = 181
CONST CUT_WORLD3END = 365
CONST CUT_WORLD4END = 540
CONST CUT_WORLD1MID = 711
CONST CUT_WORLD2MID = 890
CONST CUT_WORLD3MID = 1049
CONST CUT_WORLD4MID = 1202
CONST CUT_INTRO = 1415
CONST CUT_TRUECOLORS = 2149
CONST CUT_PREBOSS = 2556
CONST CUT_PREFIGHT = 2709
CONST CUT_FINAL = 3069
CONST CUT_TRUEENDING = 3350
CONST SEQ_BOSS_IDX = 41	' posizione del boss nella sequenza (cheat B)
CONST SEQ_LEN = 44
CONST SEQ_LEVEL = 0
CONST SEQ_CUTSCENE = 1
CONST SEQ_BOSS = 2
' Sequenza (InitLevels): tipo e parametro (indice livello o offset script / 4)
seq_type:
	DATA BYTE $01,$00,$00,$00,$00,$01,$00,$00,$00,$01,$00,$00,$00,$00,$01,$00
	DATA BYTE $00,$00,$01,$00,$00,$00,$00,$01,$00,$00,$00,$01,$00,$00,$00,$00
	DATA BYTE $01,$00,$00,$00,$01,$01,$01,$00,$01,$02,$01,$01
seq_par:
	DATA BYTE $08,$00,$01,$02,$03,$04,$04,$05,$06,$00,$07,$08,$09,$0A,$05,$0B
	DATA BYTE $0C,$0D,$01,$0E,$0F,$10,$11,$06,$12,$13,$14,$02,$15,$16,$17,$18
	DATA BYTE $07,$19,$1A,$1B,$03,$09,$0A,$1C,$0B,$00,$0C,$0D
' Offset di ciascuno script in cut_data (indice = numero dello script)
#cut_start:
	DATA 0,181,365,540,711,890,1049,1202,1415,2149,2556,2709,3069,3350

' Disegna la schermata di cutscene cut_scr a partire dalla riga cut_y (cut_rows righe)
cut_layout:	PROCEDURE
	#cut_off = cut_y: #cut_off = #cut_off * 32
	BANK SELECT CUT_SCR_BANK
	GOSUB cut_layout_bank
	BANK SELECT CUT_BANK
	END

' --- Boss ---
CONST BOSS_BANK = 9
' Piattaforme dell'arena (g_BossPlatformsROM): x, y, dx, dy, minx, miny, maxx, maxy
boss_plat:
	DATA BYTE $08,$68,$00,$FF,$08,$38,$08,$B0
	DATA BYTE $50,$30,$01,$00,$28,$30,$D0,$30
	DATA BYTE $A0,$40,$FF,$00,$28,$40,$D0,$40
	DATA BYTE $E8,$48,$00,$01,$E8,$38,$E8,$B0
CONST BOSS_NPLAT = 4

