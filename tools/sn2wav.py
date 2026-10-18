"""Ricostruisce l'audio del SN76489 dal registro di scritture dell'emulatore
(lista di (ciclo CPU, byte)) e lo salva come WAV mono 22050 Hz.
Serve solo per controllare musica ed effetti senza un emulatore completo."""
import struct
import wave

CPU = 3000000.0
SN = 3579545.0 / 16.0           # frequenza dei contatori
RATE = 22050
ATT = [10 ** (-2 * i / 20) for i in range(15)] + [0.0]


def render(log, path, cpu=CPU):
    per = [1024, 1024, 1024, 0]
    att = [15, 15, 15, 15]
    latch = 0
    cnt = [0.0] * 4
    out = [1, 1, 1, 1]
    lfsr = 0x4000
    noise_ctl = 0
    samples = []
    t_end = log[-1][0] if log else 0
    li = 0
    step = SN / RATE
    n = int(t_end / cpu * RATE)
    for k in range(n):
        t = k / RATE * cpu
        while li < len(log) and log[li][0] <= t:
            b = log[li][1]
            li += 1
            if b & 0x80:
                latch = (b >> 4) & 7
                ch = latch >> 1
                if latch & 1:
                    att[ch] = b & 15
                elif ch < 3:
                    per[ch] = (per[ch] & 0x3F0) | (b & 15)
                else:
                    noise_ctl = b & 7
                    lfsr = 0x4000
            else:
                ch = latch >> 1
                if not (latch & 1) and ch < 3:
                    per[ch] = (per[ch] & 15) | ((b & 63) << 4)
        acc = 0.0
        for ch in range(3):
            p = per[ch] or 1024
            cnt[ch] += step
            while cnt[ch] >= p:
                cnt[ch] -= p
                out[ch] = -out[ch]
            acc += out[ch] * ATT[att[ch]]
        r = noise_ctl & 3
        np_ = (per[2] or 1024) if r == 3 else (16 << r)
        cnt[3] += step
        while cnt[3] >= np_:
            cnt[3] -= np_
            fb = ((lfsr ^ (lfsr >> 1)) & 1) if noise_ctl & 4 else (lfsr & 1)
            lfsr = (lfsr >> 1) | (fb << 14)
        acc += (1 if lfsr & 1 else -1) * ATT[att[3]]
        samples.append(int(max(-1, min(1, acc / 4)) * 30000))
    w = wave.open(path, 'wb')
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(RATE)
    w.writeframes(struct.pack('<%dh' % len(samples), *samples))
    w.close()
