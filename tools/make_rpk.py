#!/usr/bin/env python3
"""make_rpk.py - Cartuccia CVBasic (_8.bin) -> immagine RPK per MAME.

Classic99 e js99er aprono direttamente il file _8.bin. MAME vuole invece un
RPK: uno zip con la ROM e un layout.xml che descrive la scheda. Le cartucce
CVBasic sono a banchi da 8 KB non-inverted (si scrive a >6000 + 2*n per il
banco n): in MAME e' la scheda "paged378", come indica il README TI99 di CVBasic.

Uso: python3 make_rpk.py <cartuccia_8.bin> [<uscita.rpk>]
     (senza uscita: stesso nome, con estensione .rpk)

Avvio in MAME: mame ti99_4a -ioport peb -ioport:peb:slot3 32kmem -cart1 gioco.rpk
(serve l'espansione di memoria da 32K)

Codice: GPLv3
"""
import os
import sys
import zipfile

LAYOUT = """<?xml version="1.0" encoding="utf-8"?>
<romset version="1.0">
   <resources>
      <rom id="romimage" file="%s"/>
   </resources>
   <configuration>
      <pcb type="paged378">
         <socket id="rom_socket" uses="romimage"/>
      </pcb>
   </configuration>
</romset>
"""


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__.split("\n\n")[2])
    rom = sys.argv[1]
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.splitext(rom)[0] + ".rpk"
    name = os.path.basename(rom)
    size = os.path.getsize(rom)
    if size % 8192:
        sys.exit("%s: %d byte, non e' un multiplo di 8 KB" % (rom, size))
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr("layout.xml", LAYOUT % name)
        z.write(rom, name)
    print("RPK per MAME: %s (%d KB, scheda paged378)" % (out, size // 1024))


if __name__ == "__main__":
    main()
