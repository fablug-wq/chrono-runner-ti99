#!/usr/bin/env python3
"""
gen_tables.py - Tabelle precalcolate per la fisica del player.

GetDPos() dell'originale (chronorunner.c) converte un accumulatore in ottavi di
pixel nello spostamento in pixel, usando sdiv() di math_utils.h, e poi riduce
l'accumulatore al resto. sdiv() non e' una divisione esatta per i positivi
(per es. 15 -> 2): per avere esattamente gli stessi salti la replichiamo
con due tabelle da 256 byte indicizzate dal valore del byte (0-255).

Uso: python3 gen_tables.py <file .bas di output>
"""
import sys


def sdiv(n, k=3):
    adj = (n >> k) & ((1 << k) - 1)      # Python: >> aritmetico come SDCC su int
    return (n + adj) >> k


def rem(m):
    while m >= 8:
        m -= 8
    while m <= -8:
        m += 8
    return m


def main():
    q, r = [], []
    for b in range(256):
        n = b - 256 if b > 127 else b
        q.append(sdiv(n) & 0xFF)
        r.append(rem(n) & 0xFF)
    out = ["' Generato da tools/gen_tables.py - NON modificare a mano",
           "' Indice = byte dell'accumulatore (0-255, i negativi da 128 in su)",
           "dpos_q:"]
    for i in range(0, 256, 16):
        out.append("\tDATA BYTE " + ",".join("$%02X" % v for v in q[i:i + 16]))
    out.append("dpos_r:")
    for i in range(0, 256, 16):
        out.append("\tDATA BYTE " + ",".join("$%02X" % v for v in r[i:i + 16]))
    with open(sys.argv[1], "w") as f:
        f.write("\n".join(out) + "\n")


if __name__ == "__main__":
    main()
