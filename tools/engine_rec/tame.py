#!/usr/bin/env python3
"""Schrille Motorschleifen entschärfen (seit 2.52): Tiefpass (Butterworth 2. Ordnung, mehrfach hintereinander) über
jede Schleife einer Bank, Pegel danach wie vorher. Der Filter läuft zweimal über die Schleife und behält den zweiten
Durchgang, so stimmen Anfang und Ende wieder überein (nahtlos).

  python3 tools/engine_rec/tame.py assets/engine/v10 2200 2

Bisher angewandt (danach build_banks.sh nicht ohne diesen Schritt neu laufen lassen):
  v10  2200 Hz, 2 Stufen (Kagura V10: die Aufnahme kreischte, knapp die Hälfte der Energie lag bei 2-6 kHz)
  f6   3000 Hz, 1 Stufe  (Kaze TT und die anderen Boxer-Sechszylinder klangen oben heraus schrill)
"""
import math, os, struct, sys, wave


def biquad_lp(x, fc, sr):
    w = 2 * math.pi * fc / sr
    q = 1 / math.sqrt(2)
    al = math.sin(w) / (2 * q)
    cw = math.cos(w)
    b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
    a0, a1, a2 = 1 + al, -2 * cw, 1 - al
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    y = []
    x1 = x2 = y1 = y2 = 0.0
    for s in x + x:  # zweimal: der zweite Durchgang ist eingeschwungen und schließt nahtlos
        o = b0 * s + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, s, y1, o
        y.append(o)
    return y[len(x):]


def main():
    d, fc, n = sys.argv[1], float(sys.argv[2]), int(sys.argv[3])
    for f in sorted(os.listdir(d)):
        if not f.endswith(".wav"):
            continue
        p = os.path.join(d, f)
        w = wave.open(p)
        sr, ch, sw, nf = w.getframerate(), w.getnchannels(), w.getsampwidth(), w.getnframes()
        raw = w.readframes(nf)
        w.close()
        assert ch == 1 and sw == 2
        x = list(struct.unpack("<%dh" % nf, raw))
        r0 = math.sqrt(sum(v * v for v in x) / nf)
        y = x
        for _ in range(n):
            y = biquad_lp(y, fc, sr)
        r1 = math.sqrt(sum(v * v for v in y) / nf) or 1.0
        k = r0 / r1
        out = [max(-32767, min(32767, int(round(v * k)))) for v in y]
        w = wave.open(p, "wb")
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(struct.pack("<%dh" % nf, *out))
        w.close()
        print(f, "Pegel x%.2f" % k)


main()
