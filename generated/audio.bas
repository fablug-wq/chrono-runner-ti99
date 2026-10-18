' ========================================================================
' Audio: costanti, scelta del brano, tabella effetti
' Generato da tools/audio2cvb.py - NON modificare a mano
' Musica ed effetti originali: Associazione MSX Italia, CC BY-NC-SA 4.0
' ========================================================================

CONST MUSIC_GAME = 0
CONST MUSIC_GAMEOVER = 1
CONST MUSIC_MENU = 2
CONST MUSIC_BOSS = 3
CONST MUSIC_INTRO = 4
CONST MUSIC_NONE = 255
CONST FX_EXIT_DOOR = 0
CONST FX_GET_KEY = 1
CONST FX_REWIND = 2
CONST FX_SHOW_KEY = 3
CONST FX_FORCE_FIELD = 4
CONST FX_DEATH = 5
CONST FX_JUMP = 6
CONST FX_STOMP_ROBOT = 7
CONST FX_GET_CRYSTAL = 8
CONST FX_GET_VORTEX = 9
CONST FX_BULLET = 10
CONST FX_ENTER_VORTEX = 11
CONST FX_VORTEX_FIRE = 12
CONST FX_BOSS_DEATH = 13
CONST FX_ROBOT_ACTIVATE = 14

' Fa partire il brano mus_req (MUSIC_NONE = silenzio) e lo ricorda in cur_song.
' Si puo' chiamare da qualsiasi banco: PLAY va fatto con il banco della
' musica inserito, poi si rimette quello di prima.
' Con music_off = 1 (tasto M) suona il silenzio, ma cur_song si aggiorna:
' riaccendendo (music_toggle) riparte da capo il brano giusto.
music_select:	PROCEDURE
	cur_song = mus_req
	mus_play = mus_req
	IF music_off THEN mus_play = MUSIC_NONE
	#mbank = 0
	ASM mov @>7ffe,@cvb__MBANK
	IF mus_play = MUSIC_GAME THEN
		BANK SELECT 10
		PLAY mus_game
	ELSEIF mus_play = MUSIC_GAMEOVER THEN
		BANK SELECT 10
		PLAY mus_gameover
	ELSEIF mus_play = MUSIC_MENU THEN
		BANK SELECT 11
		PLAY mus_menu
	ELSEIF mus_play = MUSIC_BOSS THEN
		BANK SELECT 11
		PLAY mus_boss
	ELSEIF mus_play = MUSIC_INTRO THEN
		BANK SELECT 11
		PLAY mus_intro
	ELSE
		PLAY OFF
	END IF
	ASM mov @cvb__MBANK,r0
	ASM clr *r0
	END

' Tasto M: musica spenta/accesa. Riaccesa, il brano corrente riparte da capo.
music_toggle:	PROCEDURE
	music_off = music_off XOR 1
	mus_req = cur_song
	GOSUB music_select
	END

' Indirizzi degli effetti nel banco 12 (l'interrupt inserisce il banco da solo)
ASM even
ASM sfx_bsw:
ASM data >601c
ASM sfx_tab:
ASM data cvb_SFX_0
ASM data cvb_SFX_1
ASM data cvb_SFX_2
ASM data cvb_SFX_3
ASM data cvb_SFX_4
ASM data cvb_SFX_5
ASM data cvb_SFX_6
ASM data cvb_SFX_7
ASM data cvb_SFX_8
ASM data cvb_SFX_9
ASM data cvb_SFX_10
ASM data cvb_SFX_11
ASM data cvb_SFX_12
ASM data cvb_SFX_13
ASM data cvb_SFX_14
