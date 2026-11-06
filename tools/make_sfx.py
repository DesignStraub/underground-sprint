#!/usr/bin/env python3
"""Erzeugt die Soundeffekte des Spiels als WAV (synthetisch, keine fremden Dateien).

Aufruf: python3 tools/make_sfx.py [name ...]   ->  assets/sfx/*.wav
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


def _wander(rng, n, fc):
    """Langsam schwankende Kurve -1..1 (tiefpassgefiltertes Rauschen, auf den Spitzenwert gebracht)."""
    a = 1.0 - math.exp(-2.0 * math.pi * fc / SR)
    y = 0.0
    out = []
    # zweimal filtern: weicher, ohne Knicke
    y2 = 0.0
    for _ in range(n):
        y += a * (rng.uniform(-1.0, 1.0) - y)
        y2 += a * (y - y2)
        out.append(y2)
    peak = max(1e-9, max(abs(v) for v in out))
    return [v / peak for v in out]


def _loop_xfade(x, n, xf):
    """Ende (n..n+xf) gleichmäßig in den Anfang überblenden -> nahtlose Schleife der Länge n."""
    for i in range(xf):
        k = i / xf
        x[i] = x[i] * math.sqrt(k) + x[n + i] * math.sqrt(1.0 - k)
    return x[:n]


def _norm(x):
    p = max(1e-9, max(abs(v) for v in x))
    return [v / p for v in x]


def _hp(x, fc):
    low = lp(x, fc)
    return [a - b for a, b in zip(x, low)]


def _saw_blep(rng, m, f0, slow_amt, fast_amt, jit, seed_fc=(1.2, 11.0)):
    """Haft-Gleit-Schwingung eines Reifens: Sägezahn (langsam spannen, schlagartig rutschen) mit unruhiger Periode
    und schwankender Stärke je Schwingung. Bandbegrenzt (PolyBLEP), damit nichts kratzig zurückspiegelt."""
    slow = _wander(rng, m, seed_fc[0])
    fast = _wander(rng, m, seed_fc[1])
    out = []
    ph = 0.0
    amp = 1.0
    j = 0.0
    for i in range(m):
        f = f0 * (1.0 + slow_amt * slow[i] + fast_amt * fast[i] + j)
        dt = f / SR
        ph += dt
        if ph >= 1.0:
            ph -= 1.0
            amp = 1.0 + rng.uniform(-0.35, 0.35)
            j = rng.uniform(-jit, jit)
        v = 2.0 * ph - 1.0
        if ph < dt:
            t = ph / dt
            v -= t + t - t * t - 1.0
        elif ph > 1.0 - dt:
            t = (ph - 1.0) / dt
            v -= t * t + t + t + 1.0
        out.append(v * amp)
    return out


def skid_loop():
    """Reifenquietschen (starkes Rutschen, Drift, durchdrehende Räder). Kein reiner Pfeifton: jeder Reifen schwingt
    im Haft-Gleit-Takt (rauer Sägezahn mit unruhiger Periode), der Klang kommt aus den Resonanzen von Reifen und
    Karosserie (Bandpässe um 1,2 / 2,3 / 3,6 kHz). Dazu Rattern (die Haftung reißt im Takt von 10–30 Hz ab),
    Zischen und etwas Sättigung. 2,4 s nahtlos."""
    rng = random.Random(23)
    n = secs(2.4)
    xf = secs(0.3)
    m = n + xf
    x = [0.0] * m
    # zwei Reifen fast gleich hoch (Schwebung statt Akkord: ein Akkord klingt nach Pfeife oder Orgel)
    for f0, amp in [(760.0, 1.0), (787.0, 0.7)]:
        saw = _saw_blep(rng, m, f0, 0.05, 0.015, 0.035)
        body = [0.0] * m
        for fc, q, g in [(1200.0, 3.0, 1.0), (2300.0, 4.0, 0.75), (3600.0, 5.0, 0.4)]:
            for i, v in enumerate(bandpass(saw, fc, q)):
                body[i] += v * g
        low = lp(saw, 900.0)
        for i in range(m):
            x[i] += (body[i] + 0.35 * low[i]) * amp
    x = _norm(x)
    # Rattern: Haftung reißt ab und kommt wieder (unregelmäßig, 10–30 Hz)
    chat = _wander(rng, m, 22.0)
    lvl = _wander(rng, m, 3.0)
    hiss = _norm(bandpass([rng.uniform(-1.0, 1.0) for _ in range(m)], 3200.0, 0.8))
    out = []
    for i in range(m):
        a = (0.78 + 0.22 * lvl[i]) * (1.0 - 0.3 * max(0.0, chat[i]))
        v = math.tanh(1.8 * x[i] * a) + 0.12 * hiss[i]
        out.append(v)
    return _loop_xfade(out, n, xf)


def scrub_loop():
    """Reifen schrubben (leichtes Rutschen, Kurve am Limit, Anfang eines Drifts): raues, eher tiefes Rauschen mit
    Körnung vom Asphalt, kein Ton. 2 s nahtlos."""
    rng = random.Random(31)
    n = secs(2.0)
    xf = secs(0.25)
    m = n + xf
    nz = [rng.uniform(-1.0, 1.0) for _ in range(m)]
    body = _norm([a + 0.6 * b for a, b in zip(bandpass(nz, 380.0, 0.8), bandpass(nz, 1100.0, 1.2))])
    # Körnung: viele kleine Stöße (Steinchen, Fugen), durch einen Bandpass um 1,6 kHz
    grit = [0.0] * m
    i = 0
    while i < m:
        grit[i] = rng.uniform(0.3, 1.0) * (1 if rng.random() < 0.5 else -1)
        i += int(rng.uniform(0.002, 0.012) * SR)
    grit = _norm(bandpass(grit, 1600.0, 2.0))
    am = _wander(rng, m, 14.0)
    out = [(body[i] * 0.8 + grit[i] * 0.35) * (0.8 + 0.2 * am[i]) for i in range(m)]
    return _loop_xfade(out, n, xf)


def nitro_loop():
    """Nitro: scharfes Fauchen aus den Düsen (Rauschen 1,5–7 kHz, flatternd), dumpfes Brausen der Flamme im
    Auspuff und ein leiser, heller Pfeifton. 2 s nahtlos."""
    rng = random.Random(41)
    n = secs(2.0)
    xf = secs(0.25)
    m = n + xf
    nz = [rng.uniform(-1.0, 1.0) for _ in range(m)]
    hiss = _norm(lp(_hp(nz, 1500.0), 7000.0))
    roar = _norm(lp(lp([rng.uniform(-1.0, 1.0) for _ in range(m)], 170.0), 170.0))
    mid = _norm(bandpass([rng.uniform(-1.0, 1.0) for _ in range(m)], 700.0, 0.9))
    flut = _wander(rng, m, 16.0)
    out = []
    ph = 0.0
    for i in range(m):
        t = i / SR
        ph += 2.0 * math.pi * 2650.0 * (1.0 + 0.008 * math.sin(2.0 * math.pi * 5.0 * t)) / SR
        v = hiss[i] * (0.7 + 0.3 * flut[i]) * 0.75 + roar[i] * 0.9 + mid[i] * 0.3 + math.sin(ph) * 0.06
        out.append(v)
    return _loop_xfade(out, n, xf)


def nitro_on():
    """Nitro zünden: Klacken des Ventils, ein dumpfer Stoß, dann schießt das Zischen hoch (Filter öffnet sich) und
    ein Wusch läuft durch; klingt auf den Pegel der Dauerschleife aus. 1,4 s."""
    rng = random.Random(43)
    n = secs(1.4)
    nz = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    fcs = [1500.0 + 8000.0 * min(1.0, (i / SR) / 0.22) - 2500.0 * max(0.0, (i / SR - 0.22) / 1.2) for i in range(n)]
    hiss = _norm(_hp(lp_var(nz, fcs), 900.0))
    sweep = [400.0 + 2600.0 * min(1.0, (i / SR) / 0.5) for i in range(n)]
    wl = lp_var([rng.uniform(-1.0, 1.0) for _ in range(n)], sweep)
    whoosh = _norm(_hp(wl, 300.0))
    out = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        env_h = min(1.0, t / 0.03) * (0.45 + 0.55 * math.exp(-t * 2.2))
        env_w = math.sin(math.pi * min(1.0, t / 0.7)) ** 2
        f = 48.0 + 60.0 * math.exp(-t * 18.0)
        ph += 2.0 * math.pi * f / SR
        boom = math.sin(ph) * math.exp(-t * 9.0) * min(1.0, t / 0.008)
        click = rng.uniform(-1.0, 1.0) * math.exp(-t * 400.0)
        out.append(hiss[i] * env_h * 0.8 + whoosh[i] * env_w * 0.45 + boom * 0.9 + click * 0.7)
    # die letzten 0,15 s sanft auf null
    k = secs(0.15)
    for i in range(k):
        out[n - k + i] *= 1.0 - i / k
    return out


def nitro_off():
    """Nitro abblasen (Loslassen): kurzes, helles Zischen aus dem Ventil, das schnell dumpfer und leiser wird,
    dazu ein leises Ploppen im Auspuff. 0,6 s."""
    rng = random.Random(47)
    n = secs(0.6)
    nz = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    fcs = [7000.0 * math.exp(-(i / SR) * 5.0) + 900.0 for i in range(n)]
    hiss = _norm(_hp(lp_var(nz, fcs), 700.0))
    out = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        env = min(1.0, t / 0.01) * math.exp(-t * 6.5)
        f = 70.0 + 40.0 * math.exp(-t * 25.0)
        ph += 2.0 * math.pi * f / SR
        pop = math.sin(ph) * math.exp(-(t - 0.04) ** 2 / 0.0006) * 0.5
        out.append(hiss[i] * env + pop)
    k = secs(0.08)
    for i in range(k):
        out[n - k + i] *= 1.0 - i / k
    return out


SOUNDS = {
    "horn": (horn, 0.89), "bell": (bell_loop, 0.7), "rumble": (rumble_loop, 0.89), "thud": (thud, 0.89),
    "whoosh": (whoosh, 0.7), "splash": (splash, 0.89), "clang": (clang, 0.75), "tunnel": (tunnel, 0.8),
    "crowd": (crowd_loop, 0.6), "skid": (skid_loop, 0.8), "scrub": (scrub_loop, 0.8), "nitro": (nitro_loop, 0.8),
    "nitro_on": (nitro_on, 0.89), "nitro_off": (nitro_off, 0.85),
}

if __name__ == "__main__":
    # ohne Argumente alle, sonst nur die genannten (python3 tools/make_sfx.py skid)
    import sys
    for name in sys.argv[1:] or list(SOUNDS):
        fn, gain = SOUNDS[name]
        write(name, fn(), gain)
