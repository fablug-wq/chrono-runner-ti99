#!/usr/bin/env python3
"""
ti99emu.py - Emulatore minimale TI-99/4A (TMS9900 + TMS9918A) per collaudare
e profilare le cartucce CVBasic senza la ROM della console.

Non e' un emulatore completo: niente GROM, niente audio, niente ROM di sistema.
Il gestore di interrupt della console viene simulato (salva il contesto in
>83C0, legge lo stato VDP, chiama l'hook utente in >83C4 come fa la console).
Basta per eseguire i programmi CVBasic, che non usano la ROM.

Uso tipico (da Python):
    emu = TI99("out/chrono_chrono_8.bin", symbols="out/chrono.equ")
    emu.run_frames(120, joy=lambda f: "")       # 2 secondi senza input
    emu.screenshot("menu.png")

I cicli sono stimati: tempi base del datasheet + 4 cicli di attesa per ogni
accesso alla memoria a 8 bit (tutto tranne ROM console e scratchpad).
Un frame NTSC dura circa 50.000 cicli a 3 MHz.
"""
import sys

CPU_HZ = 3000000
FRAME_CYCLES = CPU_HZ // 60

ST_LGT, ST_AGT, ST_EQ, ST_C, ST_OV, ST_OP = 0x8000, 0x4000, 0x2000, 0x1000, 0x0800, 0x0400


def s16(v):
    return v - 0x10000 if v & 0x8000 else v


def s8(v):
    return v - 0x100 if v & 0x80 else v


class VDP:
    def __init__(self):
        self.vram = bytearray(16384)
        self.reg = [0] * 8
        self.addr = 0
        self.latch = None
        self.readahead = 0
        self.status = 0

    def write_addr(self, v):
        if self.latch is None:
            self.latch = v
        else:
            if v & 0x80:
                self.reg[v & 7] = self.latch
            else:
                self.addr = ((v & 0x3F) << 8) | self.latch
                if not (v & 0x40):
                    self.readahead = self.vram[self.addr]
                    self.addr = (self.addr + 1) & 0x3FFF
            self.latch = None

    def write_data(self, v):
        self.latch = None
        self.vram[self.addr] = v
        self.readahead = v
        self.addr = (self.addr + 1) & 0x3FFF

    def read_data(self):
        self.latch = None
        v = self.readahead
        self.readahead = self.vram[self.addr]
        self.addr = (self.addr + 1) & 0x3FFF
        return v

    def read_status(self):
        self.latch = None
        v = self.status
        self.status &= 0x1F
        return v

    def int_line(self):
        return (self.status & 0x80) and (self.reg[1] & 0x20)

    # Rendering Graphics II + sprite (sufficiente per i nostri screenshot)
    PAL = [(0, 0, 0), (0, 0, 0), (33, 200, 66), (94, 220, 120), (84, 85, 237), (125, 118, 252),
           (212, 82, 77), (66, 235, 245), (252, 85, 84), (255, 121, 120), (212, 193, 84),
           (230, 206, 128), (33, 176, 59), (201, 91, 186), (204, 204, 204), (255, 255, 255)]

    def render(self):
        from PIL import Image
        r = self.reg
        img = Image.new("RGB", (256, 192), self.PAL[r[7] & 15])
        px = img.load()
        blank = not (r[1] & 0x40)
        if not blank:
            name = (r[2] & 0x0F) * 0x400
            gm2 = r[0] & 2                          # Graphics II; altrimenti Graphics I (Screen 1)
            col = (r[3] & 0x80) << 6 if gm2 else r[3] * 0x40
            pat = (r[4] & 0x04) << 11 if gm2 else (r[4] & 7) * 0x800
            back = r[7] & 15
            for i in range(768):
                ch = self.vram[name + i]
                third = (i // 256) * 0x800 if gm2 else 0
                cx, cy = (i % 32) * 8, (i // 32) * 8
                for row in range(8):
                    bits = self.vram[pat + third + ch * 8 + row]
                    c = self.vram[col + third + ch * 8 + row] if gm2 else self.vram[col + ch // 8]
                    fg, bg = c >> 4, c & 15
                    for b in range(8):
                        v = fg if bits & (0x80 >> b) else bg
                        if v == 0:
                            v = back
                        px[cx + b, cy + row] = self.PAL[v]
            sat = (r[5] & 0x7F) * 0x80
            spat = (r[6] & 0x07) * 0x800
            big = r[1] & 2
            sprites = []
            for n in range(32):
                y = self.vram[sat + n * 4]
                if y == 0xD0:
                    break
                sprites.append((n, y, self.vram[sat + n * 4 + 1], self.vram[sat + n * 4 + 2],
                                self.vram[sat + n * 4 + 3]))
            for n, y, x, f, c in reversed(sprites):
                color = c & 15
                if color == 0:
                    continue
                if c & 0x80:
                    x -= 32
                yy = y + 1 if y < 0xE0 else y - 255
                size = 16 if big else 8
                base = spat + ((f & 0xFC) if big else f) * 8
                for row in range(size):
                    for half in range(2 if big else 1):
                        bits = self.vram[base + half * 16 + row]
                        for b in range(8):
                            if bits & (0x80 >> b):
                                X, Y = x + half * 8 + b, yy + row
                                if 0 <= X < 256 and 0 <= Y < 192:
                                    px[X, Y] = self.PAL[color]
        return img


class TI99:
    def __init__(self, cart, symbols=None):
        data = open(cart, "rb").read()
        self.banks = [data[i:i + 8192] for i in range(0, len(data), 8192)]
        self.nbanks = len(self.banks)
        self.bank = 0
        self.ram = bytearray(65536)
        self.vdp = VDP()
        self.cycles = 0
        self.wait_cycles = 0
        self.keys = set()           # tasti premuti: 'U','D','L','R','F' joystick, oppure caratteri
        self.crusel = 0
        self.symbols = []
        if symbols:
            self.load_symbols(symbols)
        self.profile = {}
        self.profiling = False
        # Avvio come farebbe la console: WP GPLWS, PC dall'header della cartuccia
        self.WP = 0x83E0
        self.ST = 0
        prog = self.rw(0x6006)
        self.PC = self.rw(prog + 2)
        self.next_int = FRAME_CYCLES
        self.frame = 0
        self.timers = {}           # nome -> [entrate, cicli totali, max]
        self.watch = {}            # indirizzo procedura -> nome
        self.pending = []          # (indirizzo di ritorno, ciclo di inizio, nome, cicli ISR all'inizio)
        self.in_isr = False
        self.isr_cycles = 0        # cicli spesi negli interrupt (esclusi dai tempi delle procedure)
        self.sndlog = None         # lista (ciclo, byte) se si vuole registrare il SN76489

    # ---------------------------------------------------------------- simboli
    def load_symbols(self, path):
        # formato xas99 -E:  "NOME:" e alla riga dopo "equ  >ADDR"
        name = None
        for line in open(path):
            t = line.split()
            if not t:
                continue
            if t[0].endswith(":"):
                name = t[0][:-1]
                if len(t) >= 3 and t[1].lower() == "equ":
                    t = t[1:]
                else:
                    continue
            if name and t[0].lower() == "equ" and t[1].startswith(">"):
                try:
                    self.symbols.append((int(t[1][1:], 16), name))
                except ValueError:
                    pass
                name = None
        self.symbols.sort()
        self.symaddr = {n.upper(): a for a, n in self.symbols}

    def sym_of(self, addr):
        import bisect
        i = bisect.bisect_right(self.symbols, (addr, "￿")) - 1
        return self.symbols[i][1] if i >= 0 else "?"

    # ---------------------------------------------------------------- memoria
    def slow(self, a):
        return not (a < 0x2000 or 0x8000 <= a < 0x8400)

    def rw(self, a):
        a &= 0xFFFE
        if self.slow(a):
            self.cycles += 4
        if 0x6000 <= a < 0x8000:
            b = self.banks[self.bank]
            return (b[a - 0x6000] << 8) | b[a - 0x5FFF]
        if 0x8000 <= a < 0x8400:
            a = 0x8300 | (a & 0xFF)
            return (self.ram[a] << 8) | self.ram[a + 1]
        if 0x8800 <= a < 0x8C00:
            if a & 2:
                return self.vdp.read_status() << 8
            return self.vdp.read_data() << 8
        if 0x8400 <= a < 0xA000:
            return 0
        return (self.ram[a] << 8) | self.ram[a + 1]

    def ww(self, a, v):
        a &= 0xFFFE
        v &= 0xFFFF
        if self.slow(a):
            self.cycles += 4
        if 0x6000 <= a < 0x8000:
            self.bank = ((a - 0x6000) >> 1) % self.nbanks
            return
        if 0x8000 <= a < 0x8400:
            a = 0x8300 | (a & 0xFF)
        elif 0x8400 <= a < 0x8800:
            if self.sndlog is not None:     # suono: registro delle scritture
                self.sndlog.append((self.cycles, v >> 8))
            return
        elif 0x8800 <= a < 0x9000:
            if a >= 0x8C00:
                if a & 2:
                    self.vdp.write_addr(v >> 8)
                else:
                    self.vdp.write_data(v >> 8)
            return
        elif 0x9000 <= a < 0xA000 or a < 0x2000 or 0x4000 <= a < 0x6000:
            return
        self.ram[a] = v >> 8
        self.ram[a + 1] = v & 0xFF

    def rb(self, a):
        w = self.rw(a)
        return (w >> 8) if not (a & 1) else (w & 0xFF)

    def wb(self, a, v):
        v &= 0xFF
        if 0x6000 <= a < 0x8000 or 0x8400 <= a < 0x9000 or a < 0x2000:   # I/O e banchi
            self.ww(a & 0xFFFE, v << 8)
            return
        if 0x9000 <= a < 0xA000 or 0x4000 <= a < 0x6000:
            return
        if self.slow(a):
            self.cycles += 4
        if 0x8000 <= a < 0x8400:
            a = 0x8300 | (a & 0xFF)
        self.ram[a] = v

    def reg(self, n):
        return self.rw(self.WP + 2 * n)

    def setreg(self, n, v):
        self.ww(self.WP + 2 * n, v)

    # ---------------------------------------------------------------- CRU
    # Tastiera/joystick: colonna selezionata con LDCR a >0024 (3 bit),
    # righe lette con STCR da >0006 (8 bit), attive basse.
    KEYMAP = [
        ["=", " ", "\r", None, "FCTN", "SHIFT", "CTRL", None],
        [".", "L", "O", "9", "2", "S", "W", "X"],
        [",", "K", "I", "8", "3", "D", "E", "C"],
        ["M", "J", "U", "7", "4", "F", "R", "V"],
        ["N", "H", "Y", "6", "5", "G", "T", "B"],
        ["/", ";", "P", "0", "1", "A", "Q", "Z"],
        ["F", "L", "R", "D", "U", None, None, None],    # joystick 1 (simboli 'J'+...)
        [None] * 8,
    ]

    def cru_read_rows(self):
        col = self.crusel & 7
        v = 0xFF
        for row, k in enumerate(self.KEYMAP[col]):
            if k is None:
                continue
            name = ("J" + k) if col == 6 else k
            if name in self.keys:
                v &= ~(1 << row)
        return v

    def ldcr(self, base_bit, value, count):
        if base_bit == 0x12:            # >0024 >> 1: selezione colonna
            self.crusel = value & 7

    def stcr(self, base_bit, count):
        if base_bit == 3:               # >0006 >> 1
            return self.cru_read_rows() & ((1 << count) - 1)
        return (1 << count) - 1

    # ---------------------------------------------------------------- operandi
    def operand(self, T, R, byte):
        """Restituisce l'indirizzo dell'operando (e aggiorna l'autoincremento)."""
        if T == 0:
            return self.WP + 2 * R
        if T == 1:
            self.cycles += 4
            return self.reg(R)
        if T == 2:
            self.cycles += 8
            a = self.rw(self.PC)
            self.PC = (self.PC + 2) & 0xFFFF
            if R:
                a = (a + self.reg(R)) & 0xFFFF
            return a
        # T == 3: *R+
        self.cycles += 6 if byte else 8
        a = self.reg(R)
        self.setreg(R, a + (1 if byte else 2))
        return a

    def flags_word(self, v):
        self.ST &= ~(ST_LGT | ST_AGT | ST_EQ)
        if v == 0:
            self.ST |= ST_EQ
        else:
            self.ST |= ST_LGT
            if not (v & 0x8000):
                self.ST |= ST_AGT

    def flags_byte(self, v):
        self.ST &= ~(ST_LGT | ST_AGT | ST_EQ | ST_OP)
        if v == 0:
            self.ST |= ST_EQ
        else:
            self.ST |= ST_LGT
            if not (v & 0x80):
                self.ST |= ST_AGT
        if bin(v).count("1") & 1:
            self.ST |= ST_OP

    def compare(self, a, b, bits):
        self.ST &= ~(ST_LGT | ST_AGT | ST_EQ)
        if a == b:
            self.ST |= ST_EQ
        else:
            if a > b:
                self.ST |= ST_LGT
            sa = a - (1 << bits) if a >> (bits - 1) else a
            sb = b - (1 << bits) if b >> (bits - 1) else b
            if sa > sb:
                self.ST |= ST_AGT

    def add_flags(self, a, b, r, bits, sub=False):
        mask = (1 << bits) - 1
        sign = 1 << (bits - 1)
        self.ST &= ~(ST_C | ST_OV)
        if sub:
            if a >= b:                      # a - b senza prestito
                self.ST |= ST_C
            if ((a ^ b) & (a ^ r)) & sign:
                self.ST |= ST_OV
        else:
            if a + b > mask:
                self.ST |= ST_C
            if (~(a ^ b) & (a ^ r)) & sign:
                self.ST |= ST_OV

    # ---------------------------------------------------------------- CPU
    def interrupt(self):
        """Simula il gestore della ROM console: contesto in >83C0, hook utente."""
        self.in_isr = True
        self.isr_start = self.cycles
        old_wp, old_pc, old_st = self.WP, self.PC, self.ST
        self.WP = 0x83C0
        self.setreg(13, old_wp)
        self.setreg(14, old_pc)
        self.setreg(15, old_st)
        self.ST &= 0xFFF0
        st = self.vdp.read_status()
        self.wb(0x837B, st)
        self.wb(0x8379, (self.rb(0x8379) + 1) & 0xFF)
        hook = self.rw(0x83C4)
        self.WP = 0x83E0
        if hook:
            self.PC = hook
        else:
            self.WP = 0x83C0
            self.PC = self.reg(14)
            self.ST = self.reg(15)
            self.WP = self.reg(13)
        self.cycles += 200          # costo approssimato della parte in ROM console

    def step(self):
        pc = self.PC
        if self.profiling:
            c0 = self.cycles
        if self.pending and pc == self.pending[-1][0]:
            ret, start, name, isr0 = self.pending.pop()
            t = self.timers.setdefault(name, [0, 0, 0])
            d = self.cycles - start - (self.isr_cycles - isr0)
            t[0] += 1
            t[1] += d
            t[2] = max(t[2], d)
        if pc in self.watch:
            ret = self.rw(self.reg(10))     # cima dello stack CVBasic (r10)
            self.pending.append((ret, self.cycles, self.watch[pc], self.isr_cycles))
        op = self.rw(pc)
        self.PC = (pc + 2) & 0xFFFF
        self.execute(op)
        if self.profiling:
            key = self.sym_of(pc) if not (0x6000 <= pc < 0x8000) else "bank%d" % self.bank
            self.profile[key] = self.profile.get(key, 0) + self.cycles - c0
        # interrupt video
        if self.cycles >= self.next_int:
            self.next_int += FRAME_CYCLES
            self.vdp.status |= 0x80
            self.frame += 1
        if (self.ST & 0xF) >= 1 and self.vdp.int_line():
            self.interrupt()

    def execute(self, op):
        hi = op >> 12
        if hi >= 4:                                 # formato I
            byte = bool(op & 0x1000)
            Td, D, Ts, S = (op >> 10) & 3, (op >> 6) & 15, (op >> 4) & 3, op & 15
            kind = op & 0xE000
            self.cycles += 14
            sa = self.operand(Ts, S, byte)
            if byte:
                sv = self.rb(sa)
            else:
                sv = self.rw(sa)
            da = self.operand(Td, D, byte)
            if kind == 0xC000:                      # MOV / MOVB
                if self.slow(da):                   # il 9900 legge comunque la destinazione
                    self.cycles += 4
                if byte:
                    self.wb(da, sv)
                    self.flags_byte(sv)
                else:
                    self.ww(da, sv)
                    self.flags_word(sv)
                return
            dv = self.rb(da) if byte else self.rw(da)
            bits = 8 if byte else 16
            mask = (1 << bits) - 1
            if kind == 0x8000:                      # C / CB
                self.compare(sv, dv, bits)
                if byte:
                    self.ST &= ~ST_OP
                    if bin(sv).count("1") & 1:
                        self.ST |= ST_OP
                return
            if kind == 0xA000:                      # A
                r = (dv + sv) & mask
                self.add_flags(dv, sv, r, bits)
            elif kind == 0x6000:                    # S
                r = (dv - sv) & mask
                self.add_flags(dv, sv, r, bits, sub=True)
            elif kind == 0xE000:                    # SOC
                r = dv | sv
            elif kind == 0x4000:                    # SZC
                r = dv & ~sv & mask
            else:
                raise RuntimeError("op %04X" % op)
            if byte:
                self.wb(da, r)
                self.flags_byte(r)
            else:
                self.ww(da, r)
                self.flags_word(r)
            return

        if hi == 3 or hi == 2:
            sub = (op >> 10) & 0xF
            D, Ts, S = (op >> 6) & 15, (op >> 4) & 3, op & 15
            if sub in (0xC, 0xD):                   # LDCR / STCR
                count = D if D else 16
                byte = count <= 8
                a = self.operand(Ts, S, byte)
                base = (self.reg(12) >> 1) & 0x7FF
                self.cycles += 20 + 2 * count
                if sub == 0xC:
                    v = self.rb(a) if byte else self.rw(a)
                    self.ldcr(base, v, count)
                    if byte:
                        self.flags_byte(v)
                    else:
                        self.flags_word(v)
                else:
                    v = self.stcr(base, count)
                    if byte:
                        self.wb(a, v)
                        self.flags_byte(v)
                    else:
                        self.ww(a, v)
                        self.flags_word(v)
                return
            if sub == 0xE:                          # MPY
                self.cycles += 52
                a = self.operand(Ts, S, False)
                m = self.rw(a)
                r = m * self.reg(D)
                self.setreg(D, r >> 16)
                self.setreg((D + 1) & 15, r & 0xFFFF)
                return
            if sub == 0xF:                          # DIV
                self.cycles += 124
                a = self.operand(Ts, S, False)
                dvs = self.rw(a)
                hiw = self.reg(D)
                if dvs <= hiw:
                    self.ST |= ST_OV
                    return
                self.ST &= ~ST_OV
                num = (hiw << 16) | self.reg((D + 1) & 15)
                self.setreg(D, num // dvs)
                self.setreg((D + 1) & 15, num % dvs)
                return
            # COC, CZC, XOR (XOP non usato)
            self.cycles += 14
            a = self.operand(Ts, S, False)
            sv = self.rw(a)
            dv = self.reg(D)
            if sub == 0x8:                          # COC
                self.ST &= ~ST_EQ
                if (sv & dv) == sv:
                    self.ST |= ST_EQ
            elif sub == 0x9:                        # CZC
                self.ST &= ~ST_EQ
                if (sv & dv) == 0:
                    self.ST |= ST_EQ
            elif sub == 0xA:                        # XOR
                r = sv ^ dv
                self.setreg(D, r)
                self.flags_word(r)
            else:
                raise RuntimeError("op %04X" % op)
            return

        if hi == 1:                                 # salti e bit CRU
            code = (op >> 8) & 0xF
            disp = s8(op & 0xFF)
            st = self.ST
            L, A, E, C, O, P = (st & ST_LGT, st & ST_AGT, st & ST_EQ, st & ST_C, st & ST_OV, st & ST_OP)
            if code >= 0xD:
                base = ((self.reg(12) >> 1) + disp) & 0xFFF
                self.cycles += 12
                if code == 0xF:                     # TB
                    self.ST &= ~ST_EQ
                    if base == 0x12 or True:
                        pass
                return
            take = [True, (not A) and not E, (not L) or E, E, L or E, A, not E, not C, C, not O,
                    (not L) and not E, L and not E, P][code]
            if take:
                self.PC = (self.PC + 2 * disp) & 0xFFFF
                self.cycles += 10
            else:
                self.cycles += 8
            return

        if (op & 0xFC00) == 0x0800 or (op & 0xFC00) == 0x0C00 or (op >> 8) in (8, 9, 10, 11):
            kind = (op >> 8) & 3
            cnt = (op >> 4) & 15
            R = op & 15
            if cnt == 0:
                cnt = self.reg(0) & 15 or 16
                self.cycles += 8
            self.cycles += 12 + 2 * cnt
            v = self.reg(R)
            self.ST &= ~(ST_C | ST_OV)
            if kind == 0:                           # SRA
                for _ in range(cnt):
                    c = v & 1
                    v = (v >> 1) | (v & 0x8000)
                if c:
                    self.ST |= ST_C
            elif kind == 1:                         # SRL
                for _ in range(cnt):
                    c = v & 1
                    v >>= 1
                if c:
                    self.ST |= ST_C
            elif kind == 2:                         # SLA
                ov = False
                for _ in range(cnt):
                    c = v >> 15
                    nv = (v << 1) & 0xFFFF
                    if (nv ^ v) & 0x8000:
                        ov = True
                    v = nv
                if c:
                    self.ST |= ST_C
                if ov:
                    self.ST |= ST_OV
            else:                                   # SRC
                for _ in range(cnt):
                    c = v & 1
                    v = (v >> 1) | (c << 15)
                if c:
                    self.ST |= ST_C
            self.setreg(R, v)
            self.flags_word(v)
            return

        if 0x0400 <= op < 0x0800:                   # formato VI
            kind = (op >> 6) & 15
            T, S = (op >> 4) & 3, op & 15
            byte = False
            a = self.operand(T, S, byte)
            if kind == 0x0:                         # BLWP
                self.cycles += 26
                nwp, npc = self.rw(a), self.rw(a + 2)
                owp, opc, ost = self.WP, self.PC, self.ST
                self.WP = nwp
                self.setreg(13, owp)
                self.setreg(14, opc)
                self.setreg(15, ost)
                self.PC = npc
                return
            if kind == 0x1:                         # B
                self.cycles += 8
                self.PC = a
                return
            if kind == 0x2:                         # X
                self.cycles += 8
                self.execute(self.rw(a))
                return
            if kind == 0xA:                         # BL
                self.cycles += 12
                self.setreg(11, self.PC)
                self.PC = a
                return
            self.cycles += 10
            v = self.rw(a)
            if kind == 0x3:                         # CLR
                self.ww(a, 0)
            elif kind == 0x4:                       # NEG
                r = (-v) & 0xFFFF
                self.ww(a, r)
                self.flags_word(r)
                self.ST &= ~(ST_C | ST_OV)
                if v == 0x8000:
                    self.ST |= ST_OV
                if v == 0:
                    self.ST |= ST_C
            elif kind == 0x5:                       # INV
                r = (~v) & 0xFFFF
                self.ww(a, r)
                self.flags_word(r)
            elif kind in (0x6, 0x7, 0x8, 0x9):      # INC, INCT, DEC, DECT
                n = {0x6: 1, 0x7: 2, 0x8: -1, 0x9: -2}[kind]
                r = (v + n) & 0xFFFF
                if n > 0:
                    self.add_flags(v, n, r, 16)
                else:
                    self.add_flags(v, -n, r, 16, sub=True)
                self.ww(a, r)
                self.flags_word(r)
            elif kind == 0xB:                       # SWPB
                self.ww(a, ((v << 8) | (v >> 8)) & 0xFFFF)
            elif kind == 0xC:                       # SETO
                self.ww(a, 0xFFFF)
            elif kind == 0xD:                       # ABS
                self.flags_word(v)
                self.ST &= ~(ST_C | ST_OV)
                if v & 0x8000:
                    if v == 0x8000:
                        self.ST |= ST_OV
                    self.ww(a, (-v) & 0xFFFF)
            else:
                raise RuntimeError("op %04X" % op)
            return

        if 0x0200 <= op < 0x0400:                   # formato VIII
            kind = (op >> 5) & 15
            R = op & 15
            if kind in (0, 1, 2, 3, 4):
                imm = self.rw(self.PC)
                self.PC = (self.PC + 2) & 0xFFFF
            if kind == 0:                           # LI
                self.cycles += 12
                self.setreg(R, imm)
                self.flags_word(imm)
            elif kind == 1:                         # AI
                self.cycles += 14
                v = self.reg(R)
                r = (v + imm) & 0xFFFF
                self.add_flags(v, imm, r, 16)
                self.setreg(R, r)
                self.flags_word(r)
            elif kind == 2:                         # ANDI
                self.cycles += 14
                r = self.reg(R) & imm
                self.setreg(R, r)
                self.flags_word(r)
            elif kind == 3:                         # ORI
                self.cycles += 14
                r = self.reg(R) | imm
                self.setreg(R, r)
                self.flags_word(r)
            elif kind == 4:                         # CI
                self.cycles += 14
                self.compare(self.reg(R), imm, 16)
            elif kind == 5:                         # STWP
                self.cycles += 8
                self.setreg(R, self.WP)
            elif kind == 6:                         # STST
                self.cycles += 8
                self.setreg(R, self.ST)
            elif kind == 7:                         # LWPI
                self.cycles += 10
                self.WP = self.rw(self.PC)
                self.PC = (self.PC + 2) & 0xFFFF
            elif kind == 8:                         # LIMI
                self.cycles += 16
                self.ST = (self.ST & 0xFFF0) | (self.rw(self.PC) & 15)
                self.PC = (self.PC + 2) & 0xFFFF
            elif kind == 0xC:                       # RTWP
                self.cycles += 14
                r13, r14, r15 = self.reg(13), self.reg(14), self.reg(15)
                self.WP, self.PC, self.ST = r13, r14, r15
                if self.in_isr and self.WP != 0x83C0:
                    self.in_isr = False
                    self.isr_cycles += self.cycles - self.isr_start
            else:
                self.cycles += 12                   # IDLE, RSET, CKON... ignorati
            return
        raise RuntimeError("opcode non supportato %04X a %04X" % (op, (self.PC - 2) & 0xFFFF))

    # ---------------------------------------------------------------- comandi
    def run_frames(self, n, joy=None):
        end = self.frame + n
        while self.frame < end:
            if joy:
                self.keys = joy(self.frame)
            self.step()

    def time_procs(self, names):
        """Misura il tempo inclusivo delle procedure CVBasic indicate."""
        for n in names:
            a = self.symaddr.get(("cvb_" + n).upper())
            if a is not None:
                self.watch[a] = n

    def screenshot(self, path):
        self.vdp.render().resize((512, 384)).save(path)


if __name__ == "__main__":
    print(__doc__)
