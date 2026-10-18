#!/bin/sh
# Build della cartuccia TI-99/4A.
# Richiede: CVBasic (cvbasic + cartella con i prologue), xdt99 (xas99.py), Python 3.
#   CVBASIC_DIR  cartella di CVBasic (default ~/tools/CVBasic)
#   XDT99_DIR    cartella di xdt99   (default ~/tools/xdt99)
#   MSX_SRC      sorgente Chrono-runners (se impostato, rigenera gli asset)
set -e
CVBASIC_DIR=${CVBASIC_DIR:-$HOME/tools/CVBasic}
XDT99_DIR=${XDT99_DIR:-$HOME/tools/xdt99}
PROG=${1:-chrono}

if [ -n "$MSX_SRC" ]; then
  python3 tools/msx2cvb.py "$MSX_SRC" generated
  python3 tools/audio2cvb.py "$MSX_SRC" generated
fi
mkdir -p out
# Gli INCLUDE sono relativi a questa cartella: si compila da qui
"$CVBASIC_DIR/cvbasic" --ti994a "$PROG.bas" "out/$PROG.a99" "$CVBASIC_DIR/" 2>&1 | tee out/cvbasic.log
if grep -q "^ERROR" out/cvbasic.log; then echo "Compilazione fallita"; exit 1; fi
cd out
rm -f "${PROG}"_b*.bin              # evita di collegare banchi vecchi
python3 "$XDT99_DIR/xas99.py" -b -R "$PROG.a99" -L "$PROG.lst" -E "$PROG.equ"
# Con 10 o piu' banchi xas99 numera i file a due cifre (_b00.bin, _b01.bin ...)
FIRST="${PROG}_b0.bin"
[ -f "${PROG}_b00.bin" ] && FIRST="${PROG}_b00.bin"
python3 "$CVBASIC_DIR/linkticart.py" "$FIRST" "chrono_${PROG}_8.bin" "CHRONO RUNNER"
# linkticart scrive il nome solo nei primi banchi: negli altri resta "CVBASIC GAME"
python3 ../tools/name_replace.py "chrono_${PROG}_8.bin" "CHRONO RUNNER"
# Immagine per MAME (Classic99 e js99er usano direttamente il _8.bin)
python3 ../tools/make_rpk.py "chrono_${PROG}_8.bin"
echo "Cartuccia: out/chrono_${PROG}_8.bin"
