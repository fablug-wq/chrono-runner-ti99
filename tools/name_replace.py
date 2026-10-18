#!/usr/bin/env python3
"""
name_replace.py - Scrive il nome della cartuccia in tutti i banchi.

linkticart.py mette il nome solo nell'header dei primi banchi: negli altri resta
"CVBASIC GAME". Qui si sostituisce il campo del nome (20 byte, preceduto dal
byte di lunghezza >14) in tutta la cartuccia.

Uso: python3 name_replace.py <cartuccia_8.bin> "NOME"
"""
import sys

FIELD = 20
SEARCH = b"\x14" + b"CVBASIC GAME".ljust(FIELD)


def main():
    path, name = sys.argv[1], sys.argv[2].upper()
    if len(name) > FIELD:
        sys.exit("Nome troppo lungo: massimo %d caratteri" % FIELD)
    replace = b"\x14" + name.encode("ascii").ljust(FIELD)
    with open(path, "rb") as f:
        data = f.read()
    count = data.count(SEARCH)
    if count:
        data = data.replace(SEARCH, replace)
        with open(path, "wb") as f:
            f.write(data)
    print("Nome della cartuccia: sostituite %d occorrenze." % count)


if __name__ == "__main__":
    main()
