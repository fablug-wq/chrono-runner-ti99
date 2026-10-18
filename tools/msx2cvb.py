#!/usr/bin/env python3
"""
msx2cvb.py - Converte gli asset di Chrono Runner (MSX, MSXgl) in sorgenti CVBasic
per TI-99/4A.

Uso:
    python3 msx2cvb.py <cartella Chrono-runners-main> <cartella di output>

Genera nella cartella di output:
    common.bas      - CONST, DIM e procedure del banco 0 (caricamento grafica,
                      caricamento livelli, schermate UI)
    bank_gfx.bas    - banco con tileset (pattern + colori) e sprite
    bank_lvl_N.bas  - banchi con mappe e oggetti dei livelli
    bank_ui.bas     - banco con le schermate di menu / intermezzo / crediti
    report.txt      - riepilogo di cosa e' stato generato e occupazione banchi

Il VDP del TI-99/4A e' lo stesso TMS9918A dell'MSX1: pattern, colori, mappe e
sprite vengono copiati 1:1, senza alcuna conversione di formato.
"""

import os
import re
import sys

# ---------------------------------------------------------------------------
# Configurazione
# ---------------------------------------------------------------------------

BANK_BUDGET = 8000          # byte utili per banco da 8K (header CVBasic escluso, con margine)
LEVEL_ROWS = 22             # le mappe dei livelli sono 32x22, disegnate dalla riga 2
LEVEL_TARGET_OFFSET = 64    # riga 2 * 32 colonne
MAX_PLATFORMS = 4
MAX_MINES = 6
MAX_ENEMIES = 4
NAME_LEN = 32

FIRST_GFX_BANK = 1          # numerazione banchi CVBasic (1 = primo banco dopo il fisso)

# Ordine di caricamento degli sprite, identico a sprite_defs.h / InitializeSprite().
# (file, numero di frame, layer per frame)
SPRITE_SOURCES = [
    ("player",      11, 2),
    ("key",          2, 1),
    ("crystal",      2, 1),
    ("doc",          4, 1),
    ("vortex",       3, 1),
    ("platform",     1, 1),
    ("mine",         1, 1),
    ("boom",         1, 1),
    ("enemy0",       6, 1),
    ("enemy1",       6, 1),
    ("enemy2",       6, 1),
    ("enemy3",       6, 1),
    ("energyfield",  2, 1),
    ("bullet",       1, 1),
    ("hitler",       1, 1),
]

# Schermate non di gioco usate in chronorunner_s1_b1.c
UI_SCREENS = [
    ("menu",          2),
    ("credits1",     80),
    ("credits2",     81),
    ("rating",       92),
    ("intermission", 15),
    ("howto1",       95),   # istruzioni (g_InstructionsCutscene), pagina 1
    ("howto2",       98),   # pagina 2
    ("howto3",       99),   # pagina 3
]

# QR code dei livelli segreti sostituiti nella versione TI.
# schermata -> (indirizzo, moduli 25x25, '#' = nero).
# Il QR dell'originale nella schermata 48 (livello 29, primo segreto) punta a MSXgl;
# qui punta alla pagina di CVBasic. Versione 2 (25x25), correzione M, modo byte, maschera 6.
# Senza "https://" perche' con il prefisso (34 caratteri) non ci sta in un QR versione 2.
# Generato con: segno.make_qr(url, version=2, error='m', boost_error=False, mode='byte')
QR_PATCHES = {
    48: ("nanochess.org/cvbasic.html", [
        "#######.###..##...#######",
        "#.....#.##...##...#.....#",
        "#.###.#.#.#.###.#.#.###.#",
        "#.###.#....#.#..#.#.###.#",
        "#.###.#.##......#.#.###.#",
        "#.....#...#.##..#.#.....#",
        "#######.#.#.#.#.#.#######",
        ".........###.#.##........",
        "#..######..#..##.#..#.###",
        "#.#..#..##.#.###....##...",
        "#.#######...#.###..#.##.#",
        ".##.##.#.###..####...##.#",
        "##...##...#.#..##.#..#.##",
        "##.##....##.#####...###..",
        "####..##....#..#.#..#..##",
        "#..#...#.#.....#.#..###..",
        "#.#.#.###...###.#######..",
        "........##...#..#...#.##.",
        "#######.#.##....#.#.#...#",
        "#.....#.#....##.#...##...",
        "#.###.#.##.##.########...",
        "#.###.#.#.##.###.###...##",
        "#.###.#...###.#....###.##",
        "#.....#....#.....###.####",
        "#######.####....##..##..#",
    ]),
}
QR_COL, QR_ROW = 10, 2      # angolo del QR nella mappa 32x22 (13x13 tile)


def patch_qr(scr, modules):
    """Scrive un QR 25x25 nella mappa, come Toolkit/qr2tiles.py dell'originale:
    un tile ogni 2x2 moduli (TL*8+TR*4+BL*2+BR), 0 -> tile 100 (bianco),
    15 -> tile 47 (nero), gli altri -> 182..195. Il 26esimo modulo e' bianco."""
    def px(x, y):
        return 1 if x < 25 and y < 25 and modules[y][x] == "#" else 0
    for ty in range(13):
        for tx in range(13):
            p = (px(tx * 2, ty * 2) * 8 + px(tx * 2 + 1, ty * 2) * 4 +
                 px(tx * 2, ty * 2 + 1) * 2 + px(tx * 2 + 1, ty * 2 + 1))
            tile = 100 if p == 0 else 47 if p == 15 else 181 + p
            scr[(QR_ROW + ty) * 32 + QR_COL + tx] = tile

# ---------------------------------------------------------------------------
# Parsing di base
# ---------------------------------------------------------------------------

HEX_RE = re.compile(r"0x([0-9A-Fa-f]{1,2})")


def read(path):
    with open(path, "r", encoding="latin-1") as f:
        return f.read()


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//[^\n]*", "", text)
    return text


def c_byte_array(text, name):
    """Estrae i byte di 'const unsigned char name[] = { ... };'"""
    m = re.search(r"\b" + re.escape(name) + r"\s*\[\s*\]\s*=\s*\{(.*?)\};", text, re.S)
    if not m:
        raise ValueError("array %s non trovato" % name)
    body = strip_comments(m.group(1))
    return [int(h, 16) for h in HEX_RE.findall(body)]


def split_top(s):
    """Divide per virgole al livello zero, rispettando stringhe e parentesi."""
    out, cur, depth, q, esc = [], "", 0, False, False
    for ch in s:
        if q and esc:
            esc = False
            cur += ch
            continue
        if q and ch == "\\":
            esc = True
            cur += ch
            continue
        if ch == '"':
            q = not q
        if not q:
            if ch in "({":
                depth += 1
            elif ch in ")}":
                depth -= 1
            elif ch == "," and depth == 0:
                out.append(cur.strip())
                cur = ""
                continue
        cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def c_int(expr):
    expr = expr.strip()
    if re.fullmatch(r"0[xX][0-9A-Fa-f]+", expr):
        return int(expr, 16)
    if not re.fullmatch(r"[0-9+\-*/() ]+", expr):
        raise ValueError("espressione non numerica: %r" % expr)
    return int(eval(expr, {"__builtins__": {}}, {}))


def struct_array(text, kind):
    """Restituisce {nome: [[campi], ...]} per 'struct <kind> nome[] = {...};'"""
    res = {}
    for m in re.finditer(r"struct\s+" + kind + r"\s+(\w+)\s*\[\s*\]\s*=\s*\{(.*?)\};", text, re.S):
        items = re.findall(r"\{([^{}]*)\}", m.group(2))
        res[m.group(1)] = [[c_int(v) for v in split_top(it)] for it in items]
    return res


# ---------------------------------------------------------------------------
# Conversioni specifiche
# ---------------------------------------------------------------------------

def char_to_tile(c):
    """Stessa tabella di CharToTile() in chronorunner_s7_b1.c"""
    o = ord(c)
    if 48 <= o <= 57:
        return 1 + (o - 48)
    if 65 <= o <= 90:
        return 11 + (o - 65)
    return {"!": 43, '"': 40, "'": 38, "(": 220, ",": 39, "-": 42,
            ".": 37, ":": 41, "?": 44,
            "+": 99}.get(c, 0)     # '+' non c'e' nel font MSX: tile 99 (libero) ridefinito da plus_tile


def s8(v):
    """Intero con segno -> byte (complemento a 2)"""
    return v & 0xFF


def parse_levels(src):
    lvl_dir = os.path.join(src, "content", "levels")
    levels = {}
    for fn in sorted(os.listdir(lvl_dir)):
        if not fn.endswith("_lvl.h"):
            continue
        text = strip_comments(read(os.path.join(lvl_dir, fn)))
        plats = struct_array(text, "Platform")
        mines = struct_array(text, "Mine")
        enems = struct_array(text, "Enemy")
        for m in re.finditer(r"struct\s+Level\s+(\w+)\s*=\s*\{(.*?)\};", text, re.S):
            f = split_top(m.group(2))
            if len(f) != 17:
                raise ValueError("%s: %d campi invece di 17" % (fn, len(f)))
            scr = re.search(r"g_Screen(\d+)", f[15]).group(1)
            name = re.search(r'"(.*)"', f[16]).group(1)
            lv = {
                "file": fn,
                "screen": int(scr),
                "start": (c_int(f[0]), c_int(f[1])),
                "end": (c_int(f[2]), c_int(f[3])),
                "key": (c_int(f[4]), c_int(f[5])),
                "crystal": (c_int(f[6]), c_int(f[7])),
                "platforms": plats.get(f[9], []) if f[9] != "NULL" else [],
                "mines": mines.get(f[11], []) if f[11] != "NULL" else [],
                "enemies": enems.get(f[13], []) if f[13] != "NULL" else [],
                "key_trigger": c_int(f[14]),
                "name": name,
            }
            # Coerenza contatori dichiarati
            for idx, key in ((8, "platforms"), (10, "mines"), (12, "enemies")):
                if not f[idx].startswith("numberof"):
                    n = c_int(f[idx])
                    if n != len(lv[key]):
                        raise ValueError("%s: %s dichiarati %d, trovati %d" % (fn, key, n, len(lv[key])))
            levels[m.group(1)] = lv
    return levels


def parse_level_order(src):
    text = strip_comments(read(os.path.join(src, "chronorunner.c")))
    body = re.search(r"void\s+InitLevels\s*\(\s*\)\s*\{(.*?)\n\}", text, re.S).group(1)
    main = re.findall(r"ADD_LEVEL\((\w+)\)", body)
    secret = re.findall(r"g_LevelOrder\[l\+\+\]\s*=\s*&(\w+)", body)
    return main, secret


def level_record(lv):
    """Record a dimensione fissa letto da read_level_obj (vedi common.bas)."""
    r = [lv["start"][0], lv["start"][1], lv["end"][0], lv["end"][1],
         lv["key"][0], lv["key"][1], lv["crystal"][0], lv["crystal"][1],
         s8(lv["key_trigger"])]
    p = lv["platforms"]
    assert len(p) <= MAX_PLATFORMS, lv["file"]
    r.append(len(p))
    for i in range(MAX_PLATFORMS):
        if i < len(p):
            x, y, dx, dy, mnx, mny, mxx, mxy = p[i]
            r += [x, y, s8(dx), s8(dy), mnx, mny, mxx, mxy]
        else:
            r += [0] * 8
    m = lv["mines"]
    assert len(m) <= MAX_MINES, lv["file"]
    r.append(len(m))
    for i in range(MAX_MINES):
        r += list(m[i]) if i < len(m) else [0, 0]
    e = lv["enemies"]
    assert len(e) <= MAX_ENEMIES, lv["file"]
    r.append(len(e))
    for i in range(MAX_ENEMIES):
        if i < len(e):
            x, y, d, mnx, mxx, t = e[i][:6]
            if any(e[i][6:]):
                raise ValueError("%s: nemico %d con stato iniziale non nullo" % (lv["file"], i))
            r += [x, y, s8(d), mnx, mxx, t]
        else:
            r += [0] * 6
    name = lv["name"][:NAME_LEN]
    tiles = [char_to_tile(c) for c in name]
    r.append(len(tiles))
    r += tiles + [0] * (NAME_LEN - len(tiles))
    for v in r:
        assert 0 <= v <= 255, (lv["file"], v)
    return r


RECORD_SIZE = 9 + 1 + MAX_PLATFORMS * 8 + 1 + MAX_MINES * 2 + 1 + MAX_ENEMIES * 6 + 1 + NAME_LEN


# ---------------------------------------------------------------------------
# Emissione CVBasic
# ---------------------------------------------------------------------------

def data_lines(data, per_line=16, indent="\t"):
    out = []
    for i in range(0, len(data), per_line):
        out.append(indent + "DATA BYTE " + ",".join("$%02X" % b for b in data[i:i + per_line]))
    return out


def header(title):
    return ["' " + "=" * 72,
            "' " + title,
            "' Generato da tools/msx2cvb.py - NON modificare a mano",
            "' Asset originali: Associazione MSX Italia, licenza CC BY-NC-SA 4.0",
            "' " + "=" * 72, ""]


# ---------------------------------------------------------------------------
# Cutscene: script C (chronorunner_s5_b1.c) -> bytecode per l'interprete
# ---------------------------------------------------------------------------

CUT_CONSTS = {
    "laySize": 4, "NULL": 0,
    "COLOR_BLACK": 1, "COLOR_DARK_RED": 6, "COLOR_MEDIUM_RED": 8, "COLOR_LIGHT_RED": 9,
    "COLOR_DARK_YELLOW": 10, "COLOR_LIGHT_YELLOW": 11, "COLOR_MAGENTA": 13,
    "COLOR_GRAY": 14, "COLOR_WHITE": 15,
    "PLAYER_SPRITE_ID": 0, "KEY_SPRITE_ID": 2, "CRYSTAL_SPRITE_ID": 3, "DOC_SPRITE_ID": 4,
    "VORTEX_SPRITE_ID": 5, "BOOM_SPRITE_ID": 6,
    "CUTSCENE_TOP_Y": 0, "CUTSCENE_GFX_Y": 2, "CUTSCENE_GFX_ROWS": 18, "CUTSCENE_TEXT_Y": 20,
    "CUTSCENE_SCREEN_W": 32, "CUTSCENE_SCREEN_H": 24, "CUTSCENE_TILE_EMPTY": 47,
}
CUT_FRAMES = {   # macro di sprite_defs.h -> (base, passo)
    "PLAYER_FRAME": (0, 8), "KEY_FRAME": (88, 4), "CRYSTAL_FRAME": (96, 4), "DOC_FRAME": (104, 4),
    "VORTEX_FRAME": (120, 4), "ENERGYFIELD_FRAME": (240, 4), "BULLET_FRAME": (248, 4),
    "HITLER_FRAME": (252, 4),
}
# Codici del bytecode (stesso ordine di CutCmd_Type)
CUT_OPS = ["END", "WAIT", "WAIT_KEY", "TEXT", "TEXT_TYPE", "CLEAR_TEXT", "SPRITE_SHOW",
           "SPRITE_HIDE", "SPRITE_MOVE", "SPRITE_WALK", "SPRITE_ANIM", "FILL", "LOAD_LAYOUT",
           "MUSIC", "MUSIC_STOP", "SFX", "NUMBER"]
CUT_NUMBER_VARS = {"g_RemainingMinutesBackup": 0, "g_RemainingSecondsBackup": 1}


def cut_eval(expr, extra):
    expr = expr.strip()
    m = re.fullmatch(r"(\w+)\((.*)\)", expr)
    if m and m.group(1) in CUT_FRAMES:
        base, step = CUT_FRAMES[m.group(1)]
        return base + step * cut_eval(m.group(2), extra)
    if m and m.group(1) == "ENEMY_FRAME":
        t, f = split_top(m.group(2))
        return 144 + 24 * cut_eval(t, extra) + 4 * cut_eval(f, extra)
    for k, v in list(CUT_CONSTS.items()) + list(extra.items()):
        expr = re.sub(r"\b%s\b" % k, str(v), expr)
    return c_int(expr)


def cut_text_tiles(lit):
    t = bytes(lit, "latin-1").decode("unicode_escape")
    return [char_to_tile(c) for c in t]


def parse_cutscenes(src):
    text = strip_comments(read(os.path.join(src, "chronorunner_s5_b1.c")))
    fx = {}
    for m in re.finditer(r"#define\s+(FX_\w+)\s+(\d+)", read(os.path.join(src, "fx_sounds.h"))):
        fx[m.group(1)] = int(m.group(2))
    # Definizioni di animazione (inizializzatori designati o posizionali)
    anims, anim_index = [], {}
    fields = ["baseId", "numLayers", "numFrames", "frames", "idleFrame", "animSpeed",
              "layerOffset", "colors"]
    for m in re.finditer(r"CutSpriteAnimDef\s+(\w+)\s*=\s*\{(.*?)\};", text, re.S):
        items = split_top(m.group(2))
        vals = {}
        for i, it in enumerate(items):
            dm = re.match(r"\.(\w+)\s*=\s*(.*)", it, re.S)
            name, val = (dm.group(1), dm.group(2)) if dm else (fields[i], it)
            vals[name] = val
        frames = [cut_eval(x, fx) for x in split_top(vals["frames"].strip()[1:-1])]
        frames = (frames + [0, 0, 0])[:3]
        colors = [cut_eval(x, fx) for x in split_top(vals["colors"].strip()[1:-1])]
        colors = (colors + [0, 0])[:2]
        rec = [cut_eval(vals["baseId"], fx), cut_eval(vals["numLayers"], fx),
               cut_eval(vals["numFrames"], fx)] + frames + [
               cut_eval(vals["idleFrame"], fx), cut_eval(vals["animSpeed"], fx),
               cut_eval(vals["layerOffset"], fx)] + colors
        anim_index[m.group(1)] = len(anims)
        anims.append((m.group(1), rec))
    # Script
    scripts = []
    screens = []
    for m in re.finditer(r"const\s+CutCmd\s+(\w+)\[\]\s*=\s*\{(.*?)\n\};", text, re.S):
        name = m.group(1)
        if name == "g_InstructionsCutscene":
            continue            # le istruzioni sono gia' gestite dal menu (ui.bas)
        code = []
        intro_done = False
        cmds = [c for c in split_top(m.group(2)) if c.strip()]
        for c in cmds:
            cm = re.match(r"CUT_(\w+)\s*\((.*)\)\s*$", c.strip(), re.S)
            if not cm:
                raise ValueError("comando non riconosciuto in %s: %r" % (name, c))
            op, args = cm.group(1), split_top(cm.group(2)) if cm.group(2).strip() else []
            E = lambda x: cut_eval(x, fx)
            if op == "END":
                code += [0]
            elif op == "WAIT":
                code += [1, E(args[0])]
            elif op == "WAIT_KEY":
                code += [2]
            elif op in ("TEXT", "TEXT_TYPE"):
                lit = re.search(r'"((?:[^"\\]|\\.)*)"', args[0]).group(1)
                lines = [(lit, E(args[1]))]
                if name == "g_IntroCutscene" and lit == "PRESS SPACE KEY" and not intro_done:
                    # Versione TI: all'avvio due righe, con il tasto per saltare l'intro
                    lines = [("PRESS SPACE KEY TO START", 21), ("PRESS FCTN+9 TO SKIP INTRO", 23)]
                    intro_done = True
                for lit, row in lines:
                    tiles = cut_text_tiles(lit)
                    code += [3 if op == "TEXT" else 4, (32 - len(tiles)) // 2, row, len(tiles)] + tiles
            elif op == "CLEAR_TEXT":
                code += [5]
            elif op == "SPRITE_SHOW":
                sid, x, y, pat, col = map(E, args)
                code += [6, sid, x, y, pat, col]
            elif op == "SPRITE_HIDE":
                code += [7, E(args[0])]
            elif op == "SPRITE_MOVE":
                code += [8] + [E(a) for a in args]
            elif op == "SPRITE_WALK":
                code += [9, anim_index[args[0].strip().lstrip("&")]] + [E(a) for a in args[1:]]
            elif op == "SPRITE_ANIM":
                code += [10, anim_index[args[0].strip().lstrip("&")]] + [E(a) for a in args[1:]]
            elif op == "FILL":
                code += [11] + [E(a) for a in args]
            elif op == "LOAD_LAYOUT":
                scr = int(re.search(r"g_Screen(\d+)", args[0]).group(1))
                if scr not in screens:
                    screens.append(scr)
                code += [12, screens.index(scr)] + [E(a) for a in args[1:]]
            elif op == "MUSIC":
                code += [13, E(args[0])]
            elif op == "MUSIC_STOP":
                code += [14]
            elif op == "SFX":
                code += [15, E(args[0])]
            elif op == "NUMBER":
                code += [16, CUT_NUMBER_VARS[args[0].strip()], E(args[1]), E(args[2])]
            else:
                raise ValueError("comando cutscene sconosciuto: " + op)
        if not code or code[-1] != 0 or cmds[-1].strip() != "CUT_END()":
            if not cmds[-1].strip().startswith("CUT_END"):
                code += [0]          # g_TrueEndingCutscene non ha CUT_END nell'originale
        for v in code:
            assert 0 <= v <= 255, (name, v)
        scripts.append((name, code))
    return anims, scripts, screens


def parse_sequence(src, level_order):
    text = strip_comments(read(os.path.join(src, "chronorunner.c")))
    body = re.search(r"void\s+InitLevels\s*\(\s*\)\s*\{(.*?)\n\}", text, re.S).group(1)
    seq = []
    lvl = 0
    for m in re.finditer(r"ADD_(LEVEL|CUTSCENE|BOSS)\((\w*)\)", body):
        if m.group(1) == "LEVEL":
            seq.append(("L", lvl, m.group(2)))
            lvl += 1
        elif m.group(1) == "CUTSCENE":
            seq.append(("C", m.group(2), None))
        else:
            seq.append(("B", 0, None))
    return seq


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    src, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    report = []

    # ---------------- Tileset ----------------
    tt = read(os.path.join(src, "content", "tile", "data_tile_gm2.h"))
    tile_col = c_byte_array(tt, "g_DataMapGM2_Colors")
    tile_pat = c_byte_array(tt, "g_DataMapGM2_Patterns")
    assert len(tile_pat) == 2048 and len(tile_col) == 2048, (len(tile_pat), len(tile_col))

    # ---------------- Sprite ----------------
    spr = []
    frame_consts = []
    for name, frames, layers in SPRITE_SOURCES:
        t = read(os.path.join(src, "content", "sprite", name + "_sprt_layer.h"))
        arr = re.search(r"const unsigned char (\w+)\[\]", t).group(1)
        d = c_byte_array(t, arr)
        expected = frames * layers * 32
        if len(d) != expected:
            raise ValueError("sprite %s: %d byte, attesi %d" % (name, len(d), expected))
        frame_consts.append((name, len(spr) // 8, frames, layers))  # indice pattern 8x8 = valore 'f' di SPRITE
        spr += d
    assert len(spr) == 64 * 32, len(spr)

    gfx_size = len(tile_pat) + len(tile_col) + len(spr)
    gfx = header("Banco grafica: tileset Screen 2 (256 pattern + colori) e 64 sprite 16x16")
    gfx += ["\tBANK %d" % FIRST_GFX_BANK, "",
            "' NB: su TI-99 il conteggio di DEFINE CHAR/COLOR sta in un byte: 256 diventa 0",
            "' e la routine copia 64K in VRAM. Per questo si carica in due blocchi da 128.",
            "gfx_load_bank:\tPROCEDURE",
            "\tDEFINE CHAR 0,128,gfx_tiles_pat_a",
            "\tDEFINE CHAR 128,128,gfx_tiles_pat_b",
            "\tDEFINE COLOR 0,128,gfx_tiles_col_a",
            "\tDEFINE COLOR 128,128,gfx_tiles_col_b",
            "\tDEFINE SPRITE 0,64,gfx_sprites",
            "\tEND", "",
            "gfx_tiles_pat_a:"] + data_lines(tile_pat[:1024]) + ["gfx_tiles_pat_b:"] + data_lines(tile_pat[1024:])
    gfx += ["", "gfx_tiles_col_a:"] + data_lines(tile_col[:1024]) + ["gfx_tiles_col_b:"] + data_lines(tile_col[1024:])
    gfx += ["", "gfx_sprites:"] + data_lines(spr)
    with open(os.path.join(out, "bank_gfx.bas"), "w") as f:
        f.write("\n".join(gfx) + "\n")
    report.append("Banco %d (grafica): %d byte" % (FIRST_GFX_BANK, gfx_size))

    # ---------------- Livelli ----------------
    levels = parse_levels(src)
    main_order, secret_order = parse_level_order(src)
    order = main_order + secret_order
    scr_dir = os.path.join(src, "content", "screens")

    per_level = LEVEL_ROWS * 32 + RECORD_SIZE + 40   # + margine per il codice di caricamento
    per_bank = BANK_BUDGET // per_level
    lvl_banks = []      # lista di liste di (indice, nome struct)
    for i, lname in enumerate(order):
        if not lvl_banks or len(lvl_banks[-1]) >= per_bank:
            lvl_banks.append([])
        lvl_banks[-1].append((i, lname))

    level_bank, level_sub = [], []
    bank_no = FIRST_GFX_BANK + 1
    for group in lvl_banks:
        lines = header("Banco livelli %d" % bank_no) + ["\tBANK %d" % bank_no, ""]
        procs = ["lv%d_%s" % (idx, ln.replace("level_", "")) for idx, ln in group]
        lines += ["lvl_load_bank%d:\tPROCEDURE" % bank_no,
                  "\tON lvl_sub GOSUB " + ",".join(procs),
                  "\tEND", ""]
        size = 0
        for sub, ((idx, lname), proc) in enumerate(zip(group, procs)):
            lv = levels[lname]
            scr = c_byte_array(read(os.path.join(scr_dir, "screen_%d.h" % lv["screen"])),
                               "g_Screen%d" % lv["screen"])
            if len(scr) != LEVEL_ROWS * 32:
                raise ValueError("screen_%d: %d byte invece di %d" % (lv["screen"], len(scr), LEVEL_ROWS * 32))
            if lv["screen"] in QR_PATCHES:
                patch_qr(scr, QR_PATCHES[lv["screen"]][1])
            rec = level_record(lv)
            size += len(scr) + len(rec)
            lines += ["' Livello %d: %s (%s, screen_%d)" % (idx, lv["name"], lv["file"], lv["screen"]),
                      "%s:\tPROCEDURE" % proc,
                      "\tIF lvl_noscreen = 0 THEN SCREEN %s_map,0,%d,32,%d" % (proc, LEVEL_TARGET_OFFSET, LEVEL_ROWS),
                      "\tRESTORE %s_obj" % proc,
                      "\tGOSUB read_level_obj",
                      "\tEND", "",
                      "%s_map:" % proc] + data_lines(scr, 32) + ["", "%s_obj:" % proc] + data_lines(rec) + [""]
            level_bank.append(bank_no)
            level_sub.append(sub)
        with open(os.path.join(out, "bank_lvl_%d.bas" % bank_no), "w") as f:
            f.write("\n".join(lines) + "\n")
        report.append("Banco %d (livelli %d-%d): %d byte di dati" %
                      (bank_no, group[0][0], group[-1][0], size))
        bank_no += 1

    # ---------------- Schermate UI ----------------
    ui_bank = bank_no
    lines = header("Banco schermate UI (menu, crediti, valutazione, intermezzo)")
    lines += ["\tBANK %d" % ui_bank, "",
              "ui_show_bank:\tPROCEDURE",
              "\tON ui_screen GOSUB " + ",".join("ui_%s" % n for n, _ in UI_SCREENS),
              "\tEND", ""]
    size = 0
    for n, s in UI_SCREENS:
        scr = c_byte_array(read(os.path.join(scr_dir, "screen_%d.h" % s)), "g_Screen%d" % s)
        assert len(scr) == 768, (s, len(scr))
        if n == "menu":
            # Versione TI: il port e' scritto in CVBasic
            for i in range(2, 23):
                scr[20 * 32 + i] = 47
            for i, ch in enumerate("POWERED BY CVBASIC"):
                scr[20 * 32 + 4 + i] = 47 if ch == " " else char_to_tile(ch)
        if n == "howto1":
            # Versione TI: al posto di ESC si salta con FCTN+9; in piu' M per la musica
            def put(row, col, txt):
                for i, ch in enumerate(txt):
                    scr[row * 32 + col + i] = 47 if ch == " " else char_to_tile(ch)
            # Tabella dei tasti (righe 12-18) spostata a destra di un carattere
            for row in range(12, 19):
                r = scr[row * 32:row * 32 + 32]
                scr[row * 32:row * 32 + 32] = [47] + r[:31]
            # Disegno del joystick (righe 3-10, colonne 0-8) a destra di un carattere
            for row in range(3, 11):
                r = scr[row * 32:row * 32 + 10]
                scr[row * 32:row * 32 + 10] = [47] + r[:9]
            # Ultime due righe come le altre (tasto, freccia, azione), spostate di uno
            for row, key, action in ((20, "M", "MUSIC ON-OFF"), (22, "FCTN+9", "SKIP INTRO")):
                scr[row * 32:row * 32 + 32] = [47] * 32
                put(row, 1, key)
                scr[row * 32 + 8] = 49
                put(row, 10, action)
        size += len(scr)
        lines += ["ui_%s:\tPROCEDURE" % n, "\tSCREEN ui_%s_map" % n, "\tEND", "",
                  "ui_%s_map:" % n] + data_lines(scr, 32) + [""]
    with open(os.path.join(out, "bank_ui.bas"), "w") as f:
        f.write("\n".join(lines) + "\n")
    report.append("Banco %d (schermate UI): %d byte" % (ui_bank, size))

    # ---------------- Cutscene ----------------
    anims, scripts, cut_screens = parse_cutscenes(src)
    script_index = {n: i for i, (n, _) in enumerate(scripts)}
    cut_scr_bank = ui_bank + 1
    cut_bank = ui_bank + 2
    lines = header("Banco schermate delle cutscene (32x18 o 32x24)")
    lines += ["\tBANK %d" % cut_scr_bank, "",
              "' cut_scr = indice, cut_off = offset di destinazione, cut_rows = righe",
              "cut_layout_bank:\tPROCEDURE",
              "\tON cut_scr GOSUB " + ",".join("cs_%d" % n for n in cut_screens),
              "\tEND", ""]
    size = 0
    for n in cut_screens:
        scr = c_byte_array(read(os.path.join(scr_dir, "screen_%d.h" % n)), "g_Screen%d" % n)
        size += len(scr)
        lines += ["cs_%d:\tPROCEDURE" % n, "\tSCREEN cs_%d_map, 0, #cut_off, 32, cut_rows" % n, "\tEND", "",
                  "cs_%d_map:" % n] + data_lines(scr, 32) + [""]
    with open(os.path.join(out, "bank_cut_scr.bas"), "w") as f:
        f.write("\n".join(lines) + "\n")
    report.append("Banco %d (schermate cutscene): %d byte" % (cut_scr_bank, size))

    data, offsets = [], []
    for name, code in scripts:
        offsets.append(len(data))
        data += code
    anim_data = []
    for name, rec in anims:
        anim_data += rec
    lines = header("Banco script delle cutscene (bytecode, vedi cutscene.bas)")
    lines += ["\tBANK %d" % cut_bank, "",
              "' Animazioni (CutSpriteAnimDef), 11 byte ciascuna:",
              "' baseId, numLayers, numFrames, frames(3), idleFrame, animSpeed, layerOffset, colors(2)"]
    for i, (name, rec) in enumerate(anims):
        lines.append("'   %d = %s" % (i, name))
    lines += ["cut_anims:"] + data_lines(anim_data, 11) + ["", "' Script"]
    for (name, code), off in zip(scripts, offsets):
        lines.append("'   %s: offset %d, %d byte" % (name, off, len(code)))
    lines += ["cut_data:"] + data_lines(data)
    with open(os.path.join(out, "bank_cut.bas"), "w") as f:
        f.write("\n".join(lines) + "\n")
    report.append("Banco %d (script cutscene): %d byte" % (cut_bank, len(data) + len(anim_data)))

    seq = parse_sequence(src, order)

    # ---------------- Boss ----------------
    boss_bank = cut_bank + 1
    lines = header("Banco del boss: arena (84) e fogli delle posture (85: 0-3, 89: 4-7)")
    lines += ["\tBANK %d" % boss_bank, ""]
    size = 0
    for n in (84, 85, 89):
        scr = c_byte_array(read(os.path.join(scr_dir, "screen_%d.h" % n)), "g_Screen%d" % n)
        assert len(scr) == 768
        size += len(scr)
        lines += ["boss_s%d:" % n] + data_lines(scr, 32) + [""]
    with open(os.path.join(out, "bank_boss.bas"), "w") as f:
        f.write("\n".join(lines) + "\n")
    report.append("Banco %d (boss): %d byte" % (boss_bank, size))
    # ---------------- Logo AMI (ShowAmi), dati nel banco 13 dopo lo splash ----------------
    # Screen 1 (MODE 2 di CVBasic). I 41 caratteri del logo vanno da 128 in su,
    # perche' MODE 2 carica il font di CVBasic in 32-127 (serve per la riga
    # aggiunta in fondo); il carattere 0 (vuoto) diventa lo spazio 32.
    am = read(os.path.join(src, "content", "splash", "ami_screen1.h"))
    ami_pat = c_byte_array(am, "g_AMI_PatternTable")
    ami_col6 = c_byte_array(am, "g_AMI_ColorTable")
    ami_names = c_byte_array(am, "g_AMI_NameTable")
    assert len(ami_pat) <= 128 * 8 and len(ami_names) == 128
    ami_col = [0xF4] * 32                      # testo: bianco su blu, come lo sfondo del logo
    for i, cv in enumerate(ami_col6):
        ami_col[16 + i] = cv                   # gruppi di 8 caratteri da 128
    ami_names = [32 if t == 0 else 128 + t for t in ami_names]
    lines = header("Logo Associazione MSX Italia (ShowAmi): Screen 1, 4 righe che salgono")
    lines += ["' Nessun BANK: si include subito dopo splash_data.bas (banco 13)", "",
              "ami_pat:\t\t\t\t' %d caratteri dal 128" % (len(ami_pat) // 8)] + data_lines(ami_pat, 8)
    lines += ["", "ami_col:\t\t\t\t' tabella colori di Screen 1 (32 gruppi da 8 caratteri)"] + data_lines(ami_col, 16)
    lines += ["", "ami_names:\t\t\t\t' 32x4"] + data_lines(ami_names, 32)
    with open(os.path.join(out, "ami.bas"), "w") as f:
        f.write("\n".join(lines) + "\n")
    report.append("Logo AMI: %d byte (banco 13)" % (len(ami_pat) + 32 + 128))

    s7 = strip_comments(read(os.path.join(src, "chronorunner_s7_b1.c")))
    boss_plats = struct_array(s7, "Platform")["g_BossPlatformsROM"]

    # ---------------- common.bas (banco 0) ----------------
    c = header("Definizioni comuni (banco 0): costanti, variabili livello, caricatori")
    c += ["' --- Tile speciali ---",
          "CONST TILE_EMPTY = 47", "",
          "' --- Frame sprite (valore 'f' di SPRITE, = indice pattern MSX) ---"]
    for name, base, frames, layers in frame_consts:
        c.append("CONST FR_%s = %d\t' %d frame, %d layer" % (name.upper(), base, frames, layers))
    c += ["CONST FR_PLAYER_STEP = 8\t' player: frame n = FR_PLAYER + n*8, layer 1 = +4",
          "CONST FR_ENEMY_STEP = 24\t' nemico tipo t = FR_ENEMY0 + t*24, frame n = +n*4", "",
          "' --- Livelli ---",
          "CONST NUM_LEVELS = %d\t' livelli della sequenza principale" % len(main_order),
          "CONST NUM_LEVELS_ALL = %d\t' + livelli segreti" % len(order),
          "CONST MAX_PLATFORMS = %d" % MAX_PLATFORMS,
          "CONST MAX_MINES = %d" % MAX_MINES,
          "CONST MAX_ENEMIES = %d" % MAX_ENEMIES,
          "CONST LEVEL_MAP_OFFSET = %d\t' la mappa parte dalla riga 2" % LEVEL_TARGET_OFFSET, "",
          "' --- Schermate UI (valori per ui_screen) ---"]
    for i, (n, _) in enumerate(UI_SCREENS):
        c.append("CONST UI_%s = %d" % (n.upper(), i))
    c += ["",
          "' --- Stato del livello corrente (caricato da read_level_obj) ---",
          "DIM plat_x(MAX_PLATFORMS), plat_y(MAX_PLATFORMS), plat_dx(MAX_PLATFORMS), plat_dy(MAX_PLATFORMS)",
          "DIM plat_minx(MAX_PLATFORMS), plat_miny(MAX_PLATFORMS), plat_maxx(MAX_PLATFORMS), plat_maxy(MAX_PLATFORMS)",
          "DIM mine_x(MAX_MINES), mine_y(MAX_MINES)",
          "DIM enemy_x(MAX_ENEMIES), enemy_y(MAX_ENEMIES), enemy_dir(MAX_ENEMIES)",
          "DIM enemy_minx(MAX_ENEMIES), enemy_maxx(MAX_ENEMIES), enemy_type(MAX_ENEMIES)",
          "DIM lvl_name(%d)" % NAME_LEN,
          "SIGNED plat_dx, plat_dy, enemy_dir, lvl_ktrig", "",
          "' Indice livello -> banco e posizione nel banco",
          "level_bank_tab:"] + data_lines(level_bank) + ["level_sub_tab:"] + data_lines(level_sub) + [""]
    c += ["' Carica grafica (tileset + sprite) in VRAM",
          "load_gfx:\tPROCEDURE",
          "\tBANK SELECT %d" % FIRST_GFX_BANK,
          "\tGOSUB gfx_load_bank",
          "\tEND", "",
          "' Disegna la mappa del livello cur_level e ne carica gli oggetti",
          "' (con lvl_noscreen = 1 carica solo i dati, senza disegnare: serve all'intermezzo)",
          "load_level:\tPROCEDURE",
          "\tlvl_sub = level_sub_tab(cur_level)",
          "\tON level_bank_tab(cur_level) - %d GOSUB %s" %
          (FIRST_GFX_BANK + 1, ",".join("load_level_b%d" % (FIRST_GFX_BANK + 1 + i) for i in range(len(lvl_banks)))),
          "\tEND", ""]
    for i in range(len(lvl_banks)):
        b = FIRST_GFX_BANK + 1 + i
        c += ["load_level_b%d:\tPROCEDURE" % b, "\tBANK SELECT %d" % b,
              "\tGOSUB lvl_load_bank%d" % b, "\tEND", ""]
    c += ["' Mostra la schermata UI indicata da ui_screen (32x24)",
          "show_ui:\tPROCEDURE",
          "\tBANK SELECT %d" % ui_bank,
          "\tGOSUB ui_show_bank",
          "\tEND", "",
          "' Legge il record oggetti (%d byte) puntato dall'ultimo RESTORE" % RECORD_SIZE,
          "read_level_obj:\tPROCEDURE",
          "\tREAD BYTE lvl_start_x: READ BYTE lvl_start_y",
          "\tREAD BYTE lvl_end_x: READ BYTE lvl_end_y",
          "\tREAD BYTE lvl_key_x: READ BYTE lvl_key_y",
          "\tREAD BYTE lvl_crys_x: READ BYTE lvl_crys_y",
          "\tREAD BYTE lvl_ktrig\t' -1 = chiave visibile, 0-3 = nemico da colpire",
          "\tREAD BYTE lvl_nplat",
          "\tFOR lvl_i = 0 TO MAX_PLATFORMS - 1",
          "\t\tREAD BYTE plat_x(lvl_i): READ BYTE plat_y(lvl_i)",
          "\t\tREAD BYTE plat_dx(lvl_i): READ BYTE plat_dy(lvl_i)",
          "\t\tREAD BYTE plat_minx(lvl_i): READ BYTE plat_miny(lvl_i)",
          "\t\tREAD BYTE plat_maxx(lvl_i): READ BYTE plat_maxy(lvl_i)",
          "\tNEXT lvl_i",
          "\tREAD BYTE lvl_nmine",
          "\tFOR lvl_i = 0 TO MAX_MINES - 1",
          "\t\tREAD BYTE mine_x(lvl_i): READ BYTE mine_y(lvl_i)",
          "\tNEXT lvl_i",
          "\tREAD BYTE lvl_nenemy",
          "\tFOR lvl_i = 0 TO MAX_ENEMIES - 1",
          "\t\tREAD BYTE enemy_x(lvl_i): READ BYTE enemy_y(lvl_i): READ BYTE enemy_dir(lvl_i)",
          "\t\tREAD BYTE enemy_minx(lvl_i): READ BYTE enemy_maxx(lvl_i): READ BYTE enemy_type(lvl_i)",
          "\tNEXT lvl_i",
          "\tREAD BYTE lvl_name_len",
          "\tFOR lvl_i = 0 TO %d" % (NAME_LEN - 1),
          "\t\tREAD BYTE lvl_name(lvl_i)",
          "\tNEXT lvl_i",
          "\tEND", ""]

    c += ["' --- Cutscene e sequenza di gioco ---",
          "CONST CUT_SCR_BANK = %d" % cut_scr_bank,
          "CONST CUT_BANK = %d" % cut_bank]
    for i, (name, code) in enumerate(scripts):
        c.append("CONST CUT_%s = %d" % (re.sub(r"^g_|Cutscene$", "", name).upper(), offsets[i]))
    c += ["CONST SEQ_BOSS_IDX = %d\t' posizione del boss nella sequenza (cheat B)" % [t for t, _, _ in seq].index("B"),
          "CONST SEQ_LEN = %d" % len(seq), "CONST SEQ_LEVEL = 0", "CONST SEQ_CUTSCENE = 1", "CONST SEQ_BOSS = 2",
          "' Sequenza (InitLevels): tipo e parametro (indice livello o offset script / 4)",
          "seq_type:"] + data_lines([{"L": 0, "C": 1, "B": 2}[t] for t, _, _ in seq])
    seq_par = []
    for t, v, _ in seq:
        if t == "L":
            seq_par.append(v)
        elif t == "C":
            seq_par.append(script_index[v])
        else:
            seq_par.append(0)
    c += ["seq_par:"] + data_lines(seq_par)
    c += ["' Offset di ciascuno script in cut_data (indice = numero dello script)", "#cut_start:"]
    c += ["\tDATA " + ",".join(str(o) for o in offsets)]
    c += ["",
          "' Disegna la schermata di cutscene cut_scr a partire dalla riga cut_y (cut_rows righe)",
          "cut_layout:\tPROCEDURE",
          "\t#cut_off = cut_y: #cut_off = #cut_off * 32",
          "\tBANK SELECT CUT_SCR_BANK",
          "\tGOSUB cut_layout_bank",
          "\tBANK SELECT CUT_BANK",
          "\tEND", ""]

    c += ["' --- Boss ---", "CONST BOSS_BANK = %d" % boss_bank,
          "' Piattaforme dell'arena (g_BossPlatformsROM): x, y, dx, dy, minx, miny, maxx, maxy",
          "boss_plat:"] + data_lines([s8(v) for p_ in boss_plats for v in p_], 8)
    c += ["CONST BOSS_NPLAT = %d" % len(boss_plats), ""]
    with open(os.path.join(out, "common.bas"), "w") as f:
        f.write("\n".join(c) + "\n")

    # ---------------- Report ----------------
    report.insert(0, "Livelli: %d principali + %d segreti" % (len(main_order), len(secret_order)))
    report.insert(1, "Record oggetti livello: %d byte" % RECORD_SIZE)
    report.append("")
    report.append("Sequenza: " + " ".join(("L%d" % v) if t == "L" else ("[%s]" % v if t == "C" else "[BOSS]") for t, v, _ in seq))
    report.append("")
    report.append("Ordine livelli (indice: struct -> file, schermata, nome):")
    for i, ln in enumerate(order):
        lv = levels[ln]
        report.append("  %2d  banco %d  %-12s %-14s screen_%-3d %s%s" %
                      (i, level_bank[i], ln, lv["file"], lv["screen"], lv["name"],
                       "  [segreto]" if i >= len(main_order) else ""))
    report.append("")
    report.append("Costanti sprite:")
    for name, base, frames, layers in frame_consts:
        report.append("  FR_%-12s = %3d" % (name.upper(), base))
    with open(os.path.join(out, "report.txt"), "w") as f:
        f.write("\n".join(report) + "\n")
    print("\n".join(report[:len(lvl_banks) + 5]))


if __name__ == "__main__":
    main()
