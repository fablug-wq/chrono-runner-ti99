#!/usr/bin/env python3
"""
preview.py - Ricostruisce le schermate dai file .bas generati (non dal C originale)
e le salva come PNG, simulando il VDP TMS9918A. Serve a verificare che i dati
convertiti siano corretti prima di provarli su emulatore.

Uso: python3 preview.py <cartella generated> <cartella output png>
"""
import os
import re
import sys
from PIL import Image

# Palette TMS9918A (valori comunemente usati dagli emulatori)
PAL = [(0, 0, 0), (0, 0, 0), (33, 200, 66), (94, 220, 120), (84, 85, 237), (125, 118, 252),
       (212, 82, 77), (66, 235, 245), (252, 85, 84), (255, 121, 120), (212, 193, 84),
       (230, 206, 128), (33, 176, 59), (201, 91, 186), (204, 204, 204), (255, 255, 255)]


def load_labels(folder):
    """label -> lista di byte, da tutte le DATA BYTE dei file .bas"""
    labels, cur = {}, None
    for fn in sorted(os.listdir(folder)):
        if not fn.endswith(".bas") or fn == "bank_audio.bas":
            continue            # i dati audio non servono alle anteprime
        for line in open(os.path.join(folder, fn)):
            m = re.match(r"^(\w+):\s*$", line)
            if m:
                cur = m.group(1)
                labels[cur] = []
                continue
            m = re.match(r"^\s*DATA BYTE (.*)$", line)
            if m and cur:
                labels[cur] += [int(v.strip().lstrip("$"), 16) for v in m.group(1).split(",")]
            elif re.match(r"^\w+:\s*PROCEDURE", line):
                cur = None
    return labels


def render(names, pat, col, sprites, objs):
    img = Image.new("RGB", (256, 192), PAL[1])
    px = img.load()
    for i, ch in enumerate(names):
        cx, cy = (i % 32) * 8, (i // 32) * 8
        for r in range(8):
            bits, c = pat[ch * 8 + r], col[ch * 8 + r]
            fg, bg = c >> 4, c & 15
            for b in range(8):
                v = fg if bits & (0x80 >> b) else bg
                px[cx + b, cy + r] = PAL[v if v else 1]
    # sprite in ordine inverso: lo sprite 0 ha priorita'
    for (y, x, f, c) in reversed(objs):
        if c == 0:
            continue
        base = (f & 0xFC) * 8
        for r in range(16):
            for half in range(2):
                bits = sprites[base + half * 16 + r]
                for b in range(8):
                    if bits & (0x80 >> b):
                        X, Y = x + half * 8 + b, y + 1 + r
                        if 0 <= X < 256 and 0 <= Y < 192:
                            px[X, Y] = PAL[c]
    return img.resize((512, 384), Image.NEAREST)


def level_objects(rec):
    sx, sy, ex, ey, kx, ky, cx, cy, kt = rec[:9]
    kt = kt - 256 if kt > 127 else kt
    o = [(sy * 8, sx * 8, 0, 1), (sy * 8, sx * 8, 4, 10)]
    if kt < 0:
        o.append((ky * 8, kx * 8, 88, 1))
    if cx or cy:
        o.append((cy * 8, cx * 8, 96, 8))
    p = 9
    n = rec[p]; p += 1
    for i in range(n):
        o.append((rec[p + i * 8 + 1], rec[p + i * 8], 132, 1))
    p += 32
    n = rec[p]; p += 1
    for i in range(n):
        o.append((rec[p + i * 2 + 1], rec[p + i * 2], 136, 1))
    p += 12
    n = rec[p]; p += 1
    for i in range(n):
        x, y, d, _, _, t = rec[p + i * 6:p + i * 6 + 6]
        f = 144 + t * 24 + (8 if d < 128 else 0)
        o.append((y, x, f, 6 if kt == i else 1))
    return o


def main():
    gen, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    L = load_labels(gen)
    pat = L["gfx_tiles_pat_a"] + L["gfx_tiles_pat_b"]
    col = L["gfx_tiles_col_a"] + L["gfx_tiles_col_b"]
    spr = L["gfx_sprites"]
    thumbs = []
    for lab in sorted([k for k in L if re.match(r"lv\d+_.*_map$", k)], key=lambda k: int(k[2:].split("_")[0])):
        base = lab[:-4]
        names = [47] * 64 + L[lab] + [47] * 0
        rec = L[base + "_obj"]
        nl = rec[9 + 1 + 32 + 1 + 12 + 1 + 24]
        name_tiles = rec[-32:][:nl]
        names[:len(name_tiles)] = name_tiles
        idx = int(base[2:].split("_")[0])
        names[32] = idx // 10 + 1
        names[33] = idx % 10 + 1
        img = render(names, pat, col, spr, level_objects(rec))
        img.save(os.path.join(out, base + ".png"))
        thumbs.append(img.resize((256, 192), Image.NEAREST))
    for lab in [k for k in L if k.startswith("ui_") and k.endswith("_map")]:
        render(L[lab], pat, col, spr, []).save(os.path.join(out, lab[:-4] + ".png"))
    # foglio riassuntivo 6 colonne
    cols = 6
    rows = (len(thumbs) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * 260, rows * 196), (40, 40, 40))
    for i, t in enumerate(thumbs):
        sheet.paste(t, ((i % cols) * 260 + 2, (i // cols) * 196 + 2))
    sheet.save(os.path.join(out, "tutti_i_livelli.png"))
    print("%d livelli renderizzati" % len(thumbs))


if __name__ == "__main__":
    main()
