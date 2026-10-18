#!/usr/bin/env python3
"""Converte musica ed effetti di Chrono Runner per il TI-99/4A.

  python3 tools/audio2cvb.py <cartella Chrono-runners> <cartella generated>

Musica: i 5 moduli PT3 (sound/*.pt3) diventano sequenze MUSIC di CVBasic,
suonate con PLAY FULL NO DRUMS. Una riga PT3 = una riga MUSIC, con la stessa
velocita' (tick a 50 Hz per riga). Si perdono volumi, ornamenti ed effetti,
che il player di CVBasic non gestisce. Le note fuori dall'estensione del
SN76489 (sotto il La2 a 110 Hz) salgono di un'ottava.

Effetti: il banco AYFX (content/ayfx/fx_chronorunner.h) viene tradotto
fotogramma per fotogramma nei registri del SN76489, 3 byte per fotogramma:
  word: bit 15-12 attenuazione canale C, bit 10 = lascia il canale alla
        musica, bit 9-0 periodo (lo stesso numero dell'AY: stessa formula);
        >FFFF = fine effetto
  byte: bit 7-4 rumore (0 = spento, 4-7 = registro >E4->E7), bit 3-0 att.
Il rumore senza tono usa >E7, che prende la frequenza dal canale C: si mette
li' il periodo del rumore AY (stessa velocita' di scorrimento) a volume zero.

Genera:
  generated/audio.bas       costanti, music_select, tabella effetti (banco 0)
  generated/bank_audio.bas  dati: musica nei banchi 10-11, effetti nel 12

Codice: GPLv3 - Musica ed effetti: Associazione MSX Italia, CC BY-NC-SA 4.0
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pt3parse  # noqa: E402

# id dei brani come in fx_sounds.h, file, etichetta, banco CVBasic
SONGS = [
    (0, 'game_bitslower.pt3', 'mus_game', 10),
    (1, 'gameover.pt3', 'mus_gameover', 10),
    (2, 'german4.pt3', 'mus_menu', 11),
    (3, 'hitlerfinale.pt3', 'mus_boss', 11),
    (4, 'impox160_3ch2.pt3', 'mus_intro', 11),
]
SONG_CONST = ['MUSIC_GAME', 'MUSIC_GAMEOVER', 'MUSIC_MENU', 'MUSIC_BOSS', 'MUSIC_INTRO']
FX_CONST = ['FX_EXIT_DOOR', 'FX_GET_KEY', 'FX_REWIND', 'FX_SHOW_KEY', 'FX_FORCE_FIELD',
            'FX_DEATH', 'FX_JUMP', 'FX_STOMP_ROBOT', 'FX_GET_CRYSTAL', 'FX_GET_VORTEX',
            'FX_BULLET', 'FX_ENTER_VORTEX', 'FX_VORTEX_FIRE', 'FX_BOSS_DEATH',
            'FX_ROBOT_ACTIVATE']
SFX_BANK = 12

# Strumento CVBasic per canale: W piano, X clarinetto, Y flauto, Z basso.
# Ora piano su tutti i canali (scelta di Fabrizio); prima era il flauto.
INSTR = ['W', 'W', 'W']
# Brani suonati una volta sola (MUSIC STOP invece di MUSIC REPEAT)
NO_LOOP = {'mus_gameover'}
MIN_VOL = 6        # note PT3 piu' deboli (echi) diventano silenzio
# Durata massima di ogni nota, in tick (16 = circa 0,3 s): oltre si spegne.
# Arrotondata alle righe del brano (es. velocita' 7 -> 2 righe = 14 tick).
# 0 = nessun limite (la nota dura fino alla successiva, come nel PT3).
NOTE_TICKS = 16

NOTE_NAMES = ['C', 'C', 'D', 'D', 'E', 'F', 'F', 'G', 'G', 'A', 'A', 'B']
SHARP = [0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0]

# Volume AY -> attenuazione SN76489 (la stessa tabella ay2sn di CVBasic)
AY2SN = [15, 15, 15, 14, 14, 14, 13, 11, 10, 8, 7, 5, 4, 3, 1, 0]


def note_name(n):
    """Nota PT3 (0 = Do1) -> nome MUSIC di CVBasic (indice 1 = C2)."""
    idx = n - 11
    while idx < 10:            # sotto A2 il SN76489 non arriva (periodo > 1023)
        idx += 12
    while idx > 61:            # C7 e' l'ultima nota della tabella
        idx -= 12
    o = (idx - 1) // 12 + 2
    k = (idx - 1) % 12
    return NOTE_NAMES[k] + str(o) + ('#' if SHARP[k] else '')   # CVBasic: C3# (diesis dopo l'ottava)


def convert_song(path, label):
    s = pt3parse.parse(path)
    pos = s.positions
    if s.loop == 0 and len(set(pos)) == 1:
        pos = pos[:1]          # stesso pattern ripetuto: basta una volta, poi REPEAT
    out = ['%s:' % label, '\tDATA BYTE %d\t\t\t\t\' tick per riga' % s.speed]
    playing = [False, False, False]
    age = [0, 0, 0]                    # righe da quando e' partita la nota
    max_rows = max(1, round(NOTE_TICKS / s.speed)) if NOTE_TICKS else 1 << 30
    nrows = 0
    for pat in pos:
        out.append('\t\' pattern %d' % pat)
        for row, speed in pt3parse.decode_pattern(s, pat):
            if speed is not None and speed != s.speed:
                raise SystemExit('%s: cambio di velocita\' non gestito' % path)
            cols = []
            for c in range(3):
                e = row[c]
                if e is None:
                    if playing[c] and age[c] >= max_rows:
                        playing[c] = False         # nota troppo lunga: si spegne
                    cols.append('S' if playing[c] else '-')
                    age[c] += 1
                elif e[0] == 'off' or e[4] < MIN_VOL:
                    cols.append('-')
                    playing[c] = False
                else:
                    cols.append(note_name(e[1]) + INSTR[c])
                    playing[c] = True
                    age[c] = 1
            out.append('\tMUSIC ' + ','.join(cols))
            nrows += 1
    out.append('\tMUSIC STOP' if label in NO_LOOP else '\tMUSIC REPEAT')
    return out, nrows * 4 + 5, s


def read_afb(path):
    t = open(path).read()
    return bytes(int(x, 16) for x in re.findall(r'0x([0-9A-Fa-f]{2})', t.split('{', 1)[1]))


def convert_fx(b, i):
    """Un effetto AYFX -> lista di record (word, byte) per il SN76489."""
    off = 1 + 2 * i
    p = off + (b[off] | (b[off + 1] << 8))
    tone, noise = 0, 0
    recs = []
    while True:
        c = b[p]
        p += 1
        if c & 0x20:
            tone = b[p] | (b[p + 1] << 8)
            p += 2
        if c & 0x40:
            n = b[p]
            p += 1
            if n == 0x20:
                break
            noise = n
        vol = c & 15
        tone_on = not (c & 0x10)
        noise_on = not (c & 0x80)
        if vol == 0 or (not tone_on and not noise_on):
            recs.append((0x0400, 0))           # canale C alla musica, niente rumore
            continue
        att = AY2SN[vol]
        per = tone & 0xFFF
        while per > 1023:
            per >>= 1
        per = max(per, 1)
        np_ = max(noise & 31, 1)
        if tone_on:
            w = (att << 12) | per
            if noise_on:
                nt = 4 if np_ < 23 else 5      # >E4 = periodo 16, >E5 = 32
                nb = (nt << 4) | att
            else:
                nb = 0
        else:
            w = (15 << 12) | np_               # solo rumore: >E7 con la frequenza di C
            nb = (7 << 4) | att
        recs.append((w, nb))
    return recs


def main():
    src, dst = sys.argv[1], sys.argv[2]
    hdr = ["' " + '=' * 72,
           "' %s", "' Generato da tools/audio2cvb.py - NON modificare a mano",
           "' Musica ed effetti originali: Associazione MSX Italia, CC BY-NC-SA 4.0",
           "' " + '=' * 72, '']

    # ---- dati nei banchi ----
    data = [l if '%s' not in l else l % 'Musica (banchi 10-11) ed effetti (banco 12)' for l in hdr]
    report = []
    by_bank = {}
    for sid, fn, label, bank in SONGS:
        lines, size, s = convert_song(os.path.join(src, 'sound', fn), label)
        by_bank.setdefault(bank, []).append((lines, size))
        report.append('%-20s %-14s banco %d  %5d byte  velocita %d  "%s" di %s' %
                      (fn, label, bank, size, s.speed, s.name, s.author))
    for bank in sorted(by_bank):
        data.append('\tBANK %d' % bank)
        data.append('')
        for lines, size in by_bank[bank]:
            data += lines
            data.append('')
    afb = read_afb(os.path.join(src, 'content', 'ayfx', 'fx_chronorunner.h'))
    nfx = afb[0]
    assert nfx == len(FX_CONST)
    data.append('\tBANK %d' % SFX_BANK)
    data.append('')
    tot = 0
    for i in range(nfx):
        recs = convert_fx(afb, i)
        bs = []
        for w, nb in recs:
            bs += [w >> 8, w & 255, nb]
        bs += [255, 255]
        tot += len(bs)
        data.append('sfx_%d:\t\t\t\t\t\t\' %s, %d fotogrammi' % (i, FX_CONST[i], len(recs)))
        for k in range(0, len(bs), 24):
            data.append('\tDATA BYTE ' + ','.join('$%02X' % x for x in bs[k:k + 24]))
    report.append('effetti: %d byte nel banco %d' % (tot, SFX_BANK))
    open(os.path.join(dst, 'bank_audio.bas'), 'w').write('\n'.join(data) + '\n')

    # ---- parte nel banco 0 ----
    a = [l if '%s' not in l else l % 'Audio: costanti, scelta del brano, tabella effetti' for l in hdr]
    for i, n in enumerate(SONG_CONST):
        a.append('CONST %s = %d' % (n, i))
    a.append('CONST MUSIC_NONE = 255')
    for i, n in enumerate(FX_CONST):
        a.append('CONST %s = %d' % (n, i))
    a += ['',
          "' Fa partire il brano mus_req (MUSIC_NONE = silenzio) e lo ricorda in cur_song.",
          "' Si puo' chiamare da qualsiasi banco: PLAY va fatto con il banco della",
          "' musica inserito, poi si rimette quello di prima.",
          "' Con music_off = 1 (tasto M) suona il silenzio, ma cur_song si aggiorna:",
          "' riaccendendo (music_toggle) riparte da capo il brano giusto.",
          'music_select:\tPROCEDURE',
          '\tcur_song = mus_req',
          '\tmus_play = mus_req',
          '\tIF music_off THEN mus_play = MUSIC_NONE',
          '\t#mbank = 0',
          '\tASM mov @>7ffe,@cvb__MBANK',
          ]
    first = True
    for sid, fn, label, bank in SONGS:
        kw = 'IF' if first else 'ELSEIF'
        first = False
        a.append('\t%s mus_play = %s THEN' % (kw, SONG_CONST[sid]))
        a.append('\t\tBANK SELECT %d' % bank)
        a.append('\t\tPLAY %s' % label)
    a += ['\tELSE', '\t\tPLAY OFF', '\tEND IF',
          '\tASM mov @cvb__MBANK,r0',
          '\tASM clr *r0',
          '\tEND',
          '',
          "' Tasto M: musica spenta/accesa. Riaccesa, il brano corrente riparte da capo.",
          'music_toggle:\tPROCEDURE',
          '\tmusic_off = music_off XOR 1',
          '\tmus_req = cur_song',
          '\tGOSUB music_select',
          '\tEND',
          '',
          "' Indirizzi degli effetti nel banco %d (l'interrupt inserisce il banco da solo)" % SFX_BANK,
          'ASM even',
          'ASM sfx_bsw:',
          'ASM data >%04x' % (0x6000 + (SFX_BANK + 2) * 2),
          'ASM sfx_tab:']
    for i in range(nfx):
        a.append('ASM data cvb_SFX_%d' % i)
    open(os.path.join(dst, 'audio.bas'), 'w').write('\n'.join(a) + '\n')
    print('\n'.join(report))


if __name__ == '__main__':
    main()
