' ============================================================================
' Chrono Runner TI-99/4A - Interrupt leggero e lettura diretta dei tasti
'
' L'interrupt standard di CVBasic su TI scandisce a ogni frame l'intera
' tastiera (6 colonne, bit per bit): circa 6000 cicli su 50000. Durante il
' gioco installiamo fast_isr, uguale all'originale ma senza quella scansione;
' i tasti che servono li legge read_keys una volta per passo.
' Nel menu si rimette l'interrupt standard (CONT1.KEY funziona normalmente).
'
' fast_isr e' derivato da int_handler di CVBasic 0.9.2
' (c) Oscar Toledo G. / tursilion, licenza BSD.
' Da ricontrollare se si aggiorna CVBasic: usa le sue etichette interne
' (sprites, joy1_data, frame, lfsr, saved_bank, music_*).
' ============================================================================

' Attiva l'interrupt leggero (durante il gioco).
' spr_count = numero di sprite da copiare (impostato da allocate_sprites).
isr_fast_on:	PROCEDURE
	' il chip e' stato scritto dall'interrupt standard: cache da rifare
	ASM li r0,mh_cache
	ASM seto *r0+
	ASM seto *r0+
	ASM seto *r0+
	ASM seto *r0+
	ASM seto *r0+
	ASM seto *r0
	ASM li r0,fast_isr
	ASM mov r0,@>83c4
	END

' Rimette l'interrupt standard di CVBasic (menu, schermate).
' Quello non conosce gli effetti: si ferma quello in corso e si zittisce
' il rumore (il canale C lo riprende la musica).
isr_fast_off:	PROCEDURE
	ASM li r0,int_handler
	ASM mov r0,@>83c4
	#sfx_ptr = 0
	sfx_nlast = 0
	SOUND 3,,0
	END

' Fa partire l'effetto sfx_id (FX_*), interrompendo quello in corso come
' l'originale (priorita' sempre 0). Lo suona l'interrupt veloce sul canale C
' e sul rumore: quel canale lo toglie alla musica finche' l'effetto dura.
' Si puo' chiamare da qualsiasi banco.
sfx_play:	PROCEDURE
	ASM movb @cvb_SFX_ID,r1
	ASM srl r1,7
	ASM mov @sfx_tab(r1),@cvb__SFX_PTR
	END

' Legge direttamente la matrice della tastiera, solo le colonne utili.
' kbits: 1 = W o E, 2 = A o S, 4 = D, 8 = L, 16 = spazio, 32 = FCTN, 64 = 9, 128 = B
' (piu' tasti insieme; FCTN+9 = BACK)
read_keys:	PROCEDURE
	ASM clr r1
	' colonna 0, riga 1: spazio
	ASM li r12,>0024
	ASM clr r13
	ASM ldcr r13,3
	ASM src r12,7
	ASM li r12,>0006
	ASM stcr r13,8
	ASM li r2,>0200
	ASM czc r2,r13
	ASM jne rk_a
	ASM ori r1,>1000
ASM rk_a:
	' colonna 0, riga 4: FCTN
	ASM li r2,>1000
	ASM czc r2,r13
	ASM jne rk_f
	ASM ori r1,>2000
ASM rk_f:
	' colonna 1, riga 1: L, riga 6: W
	ASM li r12,>0024
	ASM li r13,>0100
	ASM ldcr r13,3
	ASM src r12,7
	ASM li r12,>0006
	ASM stcr r13,8
	ASM li r2,>0200
	ASM czc r2,r13
	ASM jne rk_b
	ASM ori r1,>0800
ASM rk_b:
	ASM li r2,>4000
	ASM czc r2,r13
	ASM jne rk_c
	ASM ori r1,>0100
ASM rk_c:
	' colonna 1, riga 5: S = come A (sinistra, freccia del TI)
	ASM li r2,>2000
	ASM czc r2,r13
	ASM jne rk_s
	ASM ori r1,>0200
ASM rk_s:
	' colonna 1, riga 3: 9 (FCTN+9 = BACK)
	ASM li r2,>0800
	ASM czc r2,r13
	ASM jne rk_9
	ASM ori r1,>4000
ASM rk_9:
	' colonna 2, riga 5: D
	ASM li r12,>0024
	ASM li r13,>0200
	ASM ldcr r13,3
	ASM src r12,7
	ASM li r12,>0006
	ASM stcr r13,8
	ASM li r2,>2000
	ASM czc r2,r13
	ASM jne rk_d
	ASM ori r1,>0400
ASM rk_d:
	' colonna 2, riga 6: E = come W (salto, freccia su del TI)
	ASM li r2,>4000
	ASM czc r2,r13
	ASM jne rk_e2
	ASM ori r1,>0100
ASM rk_e2:
	' colonna 5, riga 5: A
	ASM li r12,>0024
	ASM li r13,>0500
	ASM ldcr r13,3
	ASM src r12,7
	ASM li r12,>0006
	ASM stcr r13,8
	ASM li r2,>2000
	ASM czc r2,r13
	ASM jne rk_e
	ASM ori r1,>0200
ASM rk_e:
	' colonna 4, riga 7: B (cheat: vai al boss)
	ASM li r12,>0024
	ASM li r13,>0400
	ASM ldcr r13,3
	ASM src r12,7
	ASM li r12,>0006
	ASM stcr r13,8
	ASM li r2,>8000
	ASM czc r2,r13
	ASM jne rk_g
	ASM ori r1,>8000
ASM rk_g:
	ASM movb r1,@cvb_KBITS
	END

' Tasto M (musica on/off): colonna 3, riga 0. mkey = 1 se premuto.
' Il ciclo principale lo controlla a ogni passo, qualunque sia lo stato.
read_mkey:	PROCEDURE
	ASM clr r1
	ASM li r12,>0024
	ASM li r13,>0300
	ASM ldcr r13,3
	ASM src r12,7
	ASM li r12,>0006
	ASM stcr r13,8
	ASM li r2,>0100
	ASM czc r2,r13
	ASM jne rk_m
	ASM li r1,>0100
ASM rk_m:
	ASM movb r1,@cvb_MKEY
	END

' ----------------------------------------------------------------------------
' Routine di interrupt (non viene mai eseguita in sequenza: si entra solo
' dall'hook >83C4, con WP = GPLWS e interrupt disattivati)
ASM fast_isr:
	ASM lwpi myintwp
	ASM .ifne CVBASIC_BANK_SWITCHING
	ASM mov @>7ffe,@saved_bank
	ASM .endif
	' copia in VRAM (>1B00) solo gli sprite usati dal livello (spr_count),
	' poi il terminatore >D0. Senza rotazione anti-flicker, come sull'MSX.
	ASM li r11,>005b
	ASM movb r11,@VDPWADR
	ASM swpb r11
	ASM movb r11,@VDPWADR
	ASM movb @cvb_SPR_COUNT,r12
	ASM srl r12,8
	ASM jeq fisr_end
	ASM li r13,sprites
	ASM li r11,VDPWDATA
ASM fisr_cp:
	ASM movb *r13+,*r11
	ASM movb *r13+,*r11
	ASM movb *r13+,*r11
	ASM movb *r13+,*r11
	ASM dec r12
	ASM jne fisr_cp
ASM fisr_end:
	ASM li r12,>d000
	ASM movb r12,@VDPWDATA
ASM fisr_joy:
	' joystick 1
	ASM li r12,>0024
	ASM li r13,>0600
	ASM ldcr r13,3
	ASM src r12,7
	ASM li r12,>0006
	ASM stcr r13,8
	ASM bl @convert_joystick
	ASM movb r12,@joy1_data
	' CTRL = secondo pulsante del joystick 1
	ASM li r12,>0024
	ASM clr r13
	ASM ldcr r13,3
	ASM src r12,7
	ASM li r12,>0006
	ASM stcr r13,8
	' FCTN+QUIT (FCTN e '=' nella colonna 0): reset della console, come fa
	' l'interrupt standard di CVBasic
	ASM li r12,>1100
	ASM czc r12,r13
	ASM jne fisr_nq
	ASM clr @intwsr2
	ASM blwp @>0000
ASM fisr_nq:
	ASM li r12,>4000
	ASM czc r12,r13
	ASM jne fisr_noc
	ASM li r11,>8000
	ASM socb r11,@joy1_data
ASM fisr_noc:
	ASM inc @frame
	ASM li r0,3
	ASM a r0,@lfsr
	' --- effetto sonoro sul canale C e sul rumore (generated/audio.bas) ---
	' Prima degli effetti, cosi' la musica sa se il canale C e' occupato
	' (sfx_own). Il fotogramma si scrive a ogni frame; si avanza 5 volte su 6
	' (50 al secondo) oppure sempre con music60.
	ASM clr r0
	ASM movb r0,@cvb_SFX_OWN
	ASM mov @cvb__SFX_PTR,r1
	ASM jeq fisr_s9
	ASM mov @sfx_bsw,r0
	ASM clr *r0
	ASM movb *r1,r2
	ASM swpb r2
	ASM movb @1(r1),r2
	ASM swpb r2
	ASM ci r2,>ffff
	ASM jne fisr_s1
	' fine: zittisce canale C e rumore, il canale C torna alla musica
	ASM clr @cvb__SFX_PTR
	ASM li r0,>dfff
	ASM movb r0,@SOUND
	ASM swpb r0
	ASM movb r0,@SOUND
	ASM clr r0
	ASM movb r0,@cvb_SFX_NLAST
	ASM seto @mh_cache+8
	ASM seto @mh_cache+10
	ASM jmp fisr_s9
ASM fisr_s1:
	' bit 10: fotogramma muto, il canale C resta alla musica
	ASM li r0,>0400
	ASM czc r0,r2
	ASM jne fisr_s2
	ASM movb r0,@cvb_SFX_OWN
	ASM seto @mh_cache+8
	ASM seto @mh_cache+10
	ASM mov r2,r0
	ASM andi r0,>000f
	ASM ori r0,>00c0
	ASM swpb r0
	ASM movb r0,@SOUND
	ASM mov r2,r0
	ASM sla r0,4
	ASM andi r0,>3f00
	ASM movb r0,@SOUND
	ASM mov r2,r0
	ASM srl r0,4
	ASM andi r0,>0f00
	ASM ori r0,>d000
	ASM movb r0,@SOUND
ASM fisr_s2:
	ASM movb @2(r1),r2
	ASM mov r2,r0
	ASM andi r0,>f000
	ASM jeq fisr_s3
	' tipo di rumore: si riscrive solo se cambia (riscriverlo azzera il generatore)
	ASM srl r0,4
	ASM ori r0,>e000
	ASM cb r0,@cvb_SFX_NLAST
	ASM jeq fisr_s4
	ASM movb r0,@cvb_SFX_NLAST
	ASM movb r0,@SOUND
ASM fisr_s4:
	ASM andi r2,>0f00
	ASM ori r2,>f000
	ASM movb r2,@SOUND
	ASM jmp fisr_s5
ASM fisr_s3:
	ASM li r0,>ff00
	ASM movb r0,@SOUND
ASM fisr_s5:
	ASM movb @cvb_MUSIC60,r0
	ASM jne fisr_s6
	ASM ab @fisr_one,@cvb_SFX_DIV
	ASM cb @cvb_SFX_DIV,@fisr_six
	ASM jl fisr_s6
	ASM clr r0
	ASM movb r0,@cvb_SFX_DIV
	ASM jmp fisr_s9
ASM fisr_s6:
	ASM ai r1,3
	ASM mov r1,@cvb__SFX_PTR
ASM fisr_s9:
	ASM .ifne CVBASIC_MUSIC_PLAYER
	' --- musica: al posto di music_hardware di CVBasic, scrive sul chip solo
	' i valori cambiati (mh_cache). Il canale C si salta se e' dell'effetto.
	ASM movb @music_mode,r0
	ASM jeq fisr_m3
	ASM li r3,mh_cache
	ASM mov @audio_freq1,r0
	ASM movb @audio_vol1,r1
	ASM li r2,>8000
	ASM bl @mh_chan
	ASM mov @audio_freq2,r0
	ASM movb @audio_vol2,r1
	ASM li r2,>a000
	ASM bl @mh_chan
	ASM movb @cvb_SFX_OWN,r0
	ASM jne fisr_m1
	ASM mov @audio_freq3,r0
	ASM movb @audio_vol3,r1
	ASM li r2,>c000
	ASM bl @mh_chan
ASM fisr_m1:
	' music_generate: 5 frame su 6 (50 Hz) oppure, con music60, sempre
	' tranne un frame ogni music_slow (rallentamento, 0 = mai)
	ASM movb @cvb_MUSIC60,r0
	ASM jeq fisr_m5
	ASM movb @cvb_MUSIC_SLOW,r0
	ASM jeq fisr_m2
	ASM ab @fisr_one,@cvb_MSLOW_CNT
	ASM cb @cvb_MSLOW_CNT,r0
	ASM jl fisr_m2
	ASM clr r0
	ASM movb r0,@cvb_MSLOW_CNT
	ASM jmp fisr_m3
ASM fisr_m5:
	ASM movb @music_frame,r0
	ASM ai r0,>0100
	ASM ci r0,>0500
	ASM jl fisr_m4
	ASM clr r0
	ASM movb r0,@music_frame
	ASM jmp fisr_m3
ASM fisr_m4:
	ASM movb r0,@music_frame
ASM fisr_m2:
	ASM bl @music_generate
ASM fisr_m3:
	ASM .endif
	ASM .ifne CVBASIC_BANK_SWITCHING
	ASM mov @saved_bank,r0
	ASM clr *r0
	ASM .endif
	ASM lwpi INTWS
	ASM rtwp
ASM fisr_one:
	ASM byte 1
ASM fisr_six:
	ASM byte 6
	ASM even
' Ultimi valori scritti sul chip per i canali A, B, C: frequenza, volume
' (>FFFF = sconosciuto, si riscrive)
ASM mh_cache:
	ASM data -1,-1,-1,-1,-1,-1

' Un canale della musica. r0 = frequenza (>=>0400: muto), r1 = volume AY
' (byte alto), r2 = comando del canale (>8000, >A000, >C000), r3 = cache.
ASM mh_chan:
	ASM ci r0,>0400
	ASM jhe mh_mute
	ASM c r0,*r3
	ASM jeq mh_v
	ASM mov r0,*r3
	ASM mov r0,r4
	ASM andi r4,>000f
	ASM swpb r4
	ASM soc r2,r4
	ASM movb r4,@SOUND
	ASM mov r0,r4
	ASM sla r4,4
	ASM movb r4,@SOUND
ASM mh_v:
	ASM srl r1,8
	ASM movb @ay2sn(r1),r4
	ASM jmp mh_w
ASM mh_mute:
	ASM li r4,>0f00
ASM mh_w:
	ASM ai r2,>1000
	ASM soc r2,r4
	ASM cb r4,@2(r3)
	ASM jeq mh_x
	ASM movb r4,@2(r3)
	ASM movb r4,@SOUND
ASM mh_x:
	ASM ai r3,4
	ASM b *r11
