"""Lettore di moduli PT3 (Vortex Tracker II / Pro Tracker 3).

Serve a tools/audio2cvb.py: legge l'ordine dei pattern e, per ogni riga,
l'evento di ciascun canale (nota, nota spenta o niente), con sample,
ornamento e volume correnti. Effetti e inviluppi vengono letti ma ignorati:
il player MUSIC di CVBasic non li puo' riprodurre.

Codice: GPLv3
"""

# byte dei parametri dei comandi speciali 1-9 (letti dopo la nota)
CMD_PARAMS = {1: 3, 2: 5, 3: 1, 4: 1, 5: 2, 6: 0, 7: 0, 8: 3, 9: 1}


def u16(d, o):
    return d[o] | (d[o + 1] << 8)


class Song:
    pass


def parse(path):
    d = open(path, 'rb').read()
    s = Song()
    s.name = d[30:62].decode('latin1').strip()
    s.author = d[66:98].decode('latin1').strip()
    s.table = d[99]
    s.speed = d[100]
    s.loop = d[102]
    s.pat_ptr = u16(d, 103)
    s.samples = [u16(d, 105 + 2 * i) for i in range(32)]
    s.ornaments = [u16(d, 169 + 2 * i) for i in range(16)]
    pos = []
    i = 201
    while d[i] != 0xFF:
        pos.append(d[i] // 3)
        i += 1
    s.positions = pos
    s.data = d
    return s


def decode_pattern(s, pat, unknown=None):
    """Righe del pattern: lista di (riga, speed) con riga = [ev0, ev1, ev2].
    ev = None (nessun evento), ('off',) oppure
    ('note', nota, sample, ornamento, volume). speed = nuova velocita' o None."""
    d = s.data
    ptrs = [u16(d, s.pat_ptr + pat * 6 + 2 * c) for c in range(3)]
    skip = [1, 1, 1]          # righe tra un evento e l'altro (comando B1)
    wait = [0, 0, 0]
    st = [dict(sample=1, orn=0, vol=15) for _ in range(3)]
    rows = []
    while True:
        row = [None, None, None]
        speed = None
        for c in range(3):
            if wait[c] > 0:
                wait[c] -= 1
                continue
            p = ptrs[c]
            ev = None
            cmds = []
            while True:
                b = d[p]
                p += 1
                if b == 0x00:               # fine pattern (conta solo il canale A)
                    return rows
                if b >= 0xF0:
                    st[c]['orn'] = b - 0xF0
                    st[c]['sample'] = d[p] // 2
                    p += 1
                elif b >= 0xD1:
                    st[c]['sample'] = b - 0xD0
                elif b == 0xD0:             # riga vuota
                    break
                elif b >= 0xC1:
                    st[c]['vol'] = b - 0xC0
                elif b == 0xC0:             # nota spenta
                    ev = ('off',)
                    break
                elif b >= 0xB2:             # inviluppo: tipo + periodo
                    p += 2
                elif b == 0xB1:
                    skip[c] = d[p]
                    p += 1
                elif b == 0xB0:
                    pass
                elif b >= 0x50:
                    ev = ('note', b - 0x50)
                    break
                elif b >= 0x40:
                    st[c]['orn'] = b - 0x40
                elif b >= 0x20:             # periodo del rumore
                    pass
                elif b >= 0x10:             # inviluppo/sample
                    if b != 0x10:
                        p += 3
                    st[c]['sample'] = d[p] // 2
                    p += 1
                else:                       # 01-09: comandi speciali
                    cmds.append(b)
            # i parametri seguono la nota, dall'ultimo comando al primo
            for cm in reversed(cmds):
                if cm == 9:
                    speed = d[p]
                elif unknown is not None:
                    unknown.add(cm)
                p += CMD_PARAMS.get(cm, 0)
            ptrs[c] = p
            wait[c] = skip[c] - 1
            if ev and ev[0] == 'note':
                row[c] = ('note', ev[1], st[c]['sample'], st[c]['orn'], st[c]['vol'])
            elif ev:
                row[c] = ev
        rows.append((row, speed))


if __name__ == '__main__':
    import sys
    for f in sys.argv[1:]:
        s = parse(f)
        unk = set()
        tot = sum(len(decode_pattern(s, pt, unk)) for pt in s.positions)
        print(f, repr(s.name), 'speed', s.speed, 'pos', s.positions, 'loop', s.loop,
              'righe', tot, 'comandi ignorati', sorted(unk))
