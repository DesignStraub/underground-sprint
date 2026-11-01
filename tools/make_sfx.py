#!/usr/bin/env python3
"""Erzeugt die Soundeffekte des Spiels als WAV (synthetisch, keine fremden Dateien).

Aufruf: python3 tools/make_sfx.py   ->  assets/sfx/*.wav
"""
import math
import os
import random
import struct
import wave

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "sfx")
random.seed(7)


def write(name, x, gain=0.89):
    peak = max(1e-9, max(abs(s) for s in x))
    g = gain / peak
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * g)) * 32767)) for s in x))
    print(name, f"{len(x) / SR:.2f}s")


def lp(x, fc):
    a = 1.0 - math.exp(-2.0 * math.pi * fc / SR)
    y = 0.0
    out = []
    for s in x:
        y += a * (s - y)
        out.append(y)
    return out


def lp_var(x, fcs):
    y = 0.0
    out = []
    for s, fc in zip(x, fcs):
        y += (1.0 - math.exp(-2.0 * math.pi * fc / SR)) * (s - y)
        out.append(y)
    return out


def noise(n):
    return [random.uniform(-1.0, 1.0) for _ in range(n)]


def secs(t):
    return int(t * SR)


def horn():
    """Zughorn: Akkord aus drei sägezahnartigen Tönen, leicht schwebend."""
    n = secs(1.9)
    freqs = [277.2, 349.2, 415.3]
    x = []
    for i in range(n):
        t = i / SR
        env = min(1.0, t / 0.08) * (1.0 if t < 1.5 else max(0.0, 1.0 - (t - 1.5) / 0.4))
        s = 0.0
        for k, f in enumerate(freqs):
            f2 = f * (1.0 + 0.003 * math.sin(2 * math.pi * (4.5 + k) * t))
            for h in range(1, 9):
                s += math.sin(2 * math.pi * f2 * h * t + k) / h
        x.append(math.tanh(s * 0.35) * env)
    return lp(x, 2600)


def bell_loop():
    """Bahnübergangs-Glocke: zwei Schläge pro Sekunde, nahtlos loopbar."""
    n = secs(1.0)
    parts = [(1180, 1.0), (2840, 0.5), (4410, 0.25), (590, 0.3)]
    x = [0.0] * n
    for hit in (0.0, 0.5):
        o = secs(hit)
        for i in range(secs(0.5)):
            t = i / SR
            s = sum(a * math.sin(2 * math.pi * f * t) for f, a in parts)
            s *= math.exp(-t * 9.0)
            if t < 0.004:
                s += random.uniform(-1, 1) * (1 - t / 0.004)
            x[(o + i) % n] += s
    return x


def rumble_loop():
    """Zug-Rumpeln mit Schienenstößen (tack-tack), 2 s nahtlos."""
    n = secs(2.0)
    base = lp(noise(n + secs(0.2)), 140)[secs(0.2):]
    mid = lp(noise(n + secs(0.2)), 700)[secs(0.2):]
    x = [base[i] * 3.0 + mid[i] * 0.6 * (0.7 + 0.3 * math.sin(2 * math.pi * 6 * i / SR)) for i in range(n)]
    for hit in (0.12, 0.27, 1.12, 1.27):
        o = secs(hit)
        for i in range(secs(0.09)):
            t = i / SR
            s = (random.uniform(-1, 1) * 0.6 + math.sin(2 * math.pi * 880 * t) * 0.5) * math.exp(-t * 60)
            x[(o + i) % n] += s * 1.4
    # Ende/Anfang weich überblenden
    f = secs(0.05)
    for i in range(f):
        a = i / f
        x[i] = x[i] * a + x[n - f + i] * (1 - a)
    return x[: n - f]


def thud():
    """Landung: tiefer Schlag + Fahrwerk."""
    n = secs(0.8)
    nz = lp(noise(n), 420)
    x = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        f = 40 + 80 * math.exp(-t * 12)
        ph += 2 * math.pi * f / SR
        s = math.sin(ph) * math.exp(-t * 6) * 1.2
        s += nz[i] * 3.0 * math.exp(-t * 22)
        s += (math.sin(2 * math.pi * 330 * t) + math.sin(2 * math.pi * 517 * t)) * 0.12 * math.exp(-t * 14)
        x.append(s)
    return x


def whoosh():
    """Absprung: Luftrauschen, das anschwillt und abfällt."""
    n = secs(0.9)
    nz = noise(n)
    fcs = [400 + 2400 * math.sin(math.pi * i / n) for i in range(n)]
    hi = lp_var(nz, fcs)
    lo = lp(nz, 250)
    return [(hi[i] - lo[i]) * math.sin(math.pi * i / n) ** 2 for i in range(n)]


def splash():
    """Wasser: Klatscher + abklingendes Rauschen + Blubbern."""
    n = secs(1.8)
    nz = noise(n)
    fcs = [600 + 3500 * math.exp(-i / SR * 3.5) for i in range(n)]
    x = [v * math.exp(-i / SR * 2.6) * 1.6 for i, v in enumerate(lp_var(nz, fcs))]
    low = lp(noise(n), 120)
    for i in range(secs(0.3)):
        x[i] += low[i] * 6 * math.exp(-i / SR * 10)
    for _ in range(26):
        o = secs(random.uniform(0.2, 1.5))
        f0 = random.uniform(300, 800)
        for i in range(secs(0.05)):
            t = i / SR
            if o + i < n:
                x[o + i] += math.sin(2 * math.pi * (f0 + 4000 * t) * t) * 0.25 * math.sin(math.pi * t / 0.05)
    return x


def clang():
    """Laterne getroffen: Metallmast, unharmonische Teiltöne."""
    n = secs(1.4)
    parts = [(523, 1.0, 3.0), (1406, 0.6, 4.5), (2632, 0.4, 6.0), (3714, 0.25, 8.0), (5100, 0.15, 11.0)]
    x = []
    for i in range(n):
        t = i / SR
        s = sum(a * math.sin(2 * math.pi * f * t) * math.exp(-t * d) for f, a, d in parts)
        if t < 0.006:
            s += random.uniform(-1, 1) * 1.5 * (1 - t / 0.006)
        x.append(s)
    return x


def bandpass(x, fc, q):
    """Zweipoliger Bandpass (RBJ-Biquad)."""
    w = 2 * math.pi * fc / SR
    alpha = math.sin(w) / (2 * q)
    b0, b2 = alpha, -alpha
    a0, a1, a2 = 1 + alpha, -2 * math.cos(w), 1 - alpha
    x1 = x2 = y1 = y2 = 0.0
    out = []
    for s in x:
        y = (b0 * s + b2 * x2 - a1 * y1 - a2 * y2) / a0
        x2, x1 = x1, s
        y2, y1 = y1, y
        out.append(y)
    return out


def tunnel():
    """Tunnel-Einfahrt: dumpfer Druckstoß + Luftrauschen, das schnell abklingt."""
    n = secs(1.0)
    nz = noise(n)
    fcs = [300 + 1500 * math.exp(-i / SR * 5.0) for i in range(n)]
    air = lp_var(nz, fcs)
    low = lp(nz, 90)
    x = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        f = 70 - 35 * min(1.0, t / 0.4)
        ph += 2 * math.pi * f / SR
        env = min(1.0, t / 0.03) * math.exp(-t * 5.0)
        s = math.sin(ph) * env * 0.9
        s += air[i] * 2.2 * min(1.0, t / 0.06) * math.exp(-t * 3.5)
        s += low[i] * 6.0 * env
        x.append(s)
    return x


def crowd_loop():
    """Stadion: Menge aus Vokal-Formanten auf Rauschen, langsam wogend, mit Jubel-Wellen. 4 s nahtlos."""
    n = secs(4.0)
    pad = secs(0.3)
    nz = noise(n + pad)
    voice = [a + b * 0.7 + c * 0.4 for a, b, c in zip(bandpass(nz, 650, 1.2), bandpass(nz, 1150, 1.6), bandpass(nz, 2500, 2.5))]
    voice = voice[pad:]
    murmur = lp(noise(n + pad), 400)[pad:]
    x = []
    for i in range(n):
        t = i / SR
        # Schwankungen mit Perioden, die in 4 s aufgehen -> nahtlos
        w = 0.7 + 0.15 * math.sin(2 * math.pi * 0.5 * t) + 0.1 * math.sin(2 * math.pi * 1.25 * t + 1.0)
        cheer = math.exp(-((t - 1.3) ** 2) / 0.12) * 0.6 + math.exp(-((t - 3.1) ** 2) / 0.2) * 0.4
        x.append(voice[i] * (w + cheer) + murmur[i] * 2.0)
    f = secs(0.08)
    for i in range(f):
        a = i / f
        x[i] = x[i] * a + x[n - f + i] * (1 - a)
    return x[: n - f]


if __name__ == "__main__":
    write("horn", horn())
    write("bell", bell_loop(), 0.7)
    write("rumble", rumble_loop())
    write("thud", thud())
    write("whoosh", whoosh(), 0.7)
    write("splash", splash())
    write("clang", clang(), 0.75)
    write("tunnel", tunnel(), 0.8)
    write("crowd", crowd_loop(), 0.6)
