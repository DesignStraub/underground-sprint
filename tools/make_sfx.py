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
    """Seit 2.23 nicht mehr in SOUNDS: skid.wav ist eine echte Aufnahme (CREDITS.md). Bleibt zum Vergleich.
    Reifenquietschen (starkes Rutschen, Drift, durchdrehende Räder). Kein reiner Pfeifton: jeder Reifen schwingt
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


def _bp_noise(rng, n, fc, q):
    return _norm(bandpass([rng.uniform(-1.0, 1.0) for _ in range(n)], fc, q))


def backfire():
    """Fehlzündung im Auspuff (Hochschalten, Gaswegnehmen, Nitro-Zündung): scharfer Knall (breitbandiger Stoß), dumpfer
    Druckschlag aus dem Rohr und ein kurzes Nachknistern. 0,5 s."""
    rng = random.Random(53)
    n = secs(0.5)
    crack = lp([rng.uniform(-1.0, 1.0) for _ in range(n)], 6500.0)
    body = _bp_noise(rng, n, 420.0, 1.4)
    x = []
    ph = 0.0
    for i in range(n):
        t = i / SR
        f = 55.0 + 70.0 * math.exp(-t * 30.0)
        ph += 2.0 * math.pi * f / SR
        boom = math.sin(ph) * math.exp(-t * 16.0) * min(1.0, t / 0.002)
        v = crack[i] * 3.2 * math.exp(-t * 140.0) + body[i] * 0.55 * math.exp(-t * 30.0) + boom * 1.1
        x.append(v)
    # Nachknistern: ein paar kleine Knackser, immer leiser
    t = 0.05
    while t < 0.3:
        o = secs(t)
        a = 0.35 * math.exp(-(t - 0.05) * 9.0) * rng.uniform(0.5, 1.0)
        for j in range(secs(0.004)):
            if o + j < n:
                x[o + j] += rng.uniform(-1.0, 1.0) * a * (1.0 - j / secs(0.004))
        t += rng.uniform(0.012, 0.04)
    x = [math.tanh(1.4 * v) for v in x]
    k = secs(0.05)
    for i in range(k):
        x[n - k + i] *= 1.0 - i / k
    return x


def bov():
    """Blow-off-Ventil (nachgerüsteter Turbo, Gas weg): scharfes "Pschhh" – Rauschen über 1,2 kHz, das hell einsetzt
    und schnell dumpfer wird, mit Klacken des Ventils. 0,55 s."""
    rng = random.Random(59)
    n = secs(0.55)
    nz = [rng.uniform(-1.0, 1.0) for _ in range(n)]
    fcs = [3200.0 + 6500.0 * math.exp(-(i / SR) * 7.0) for i in range(n)]
    hiss = _norm(_hp(_hp(lp_var(nz, fcs), 1200.0), 1200.0))
    x = []
    for i in range(n):
        t = i / SR
        env = min(1.0, t / 0.006) * (0.35 * math.exp(-t * 3.0) + 0.65 * math.exp(-t * 9.0))
        click = rng.uniform(-1.0, 1.0) * math.exp(-t * 600.0)
        x.append(hiss[i] * env + click * 0.5)
    k = secs(0.06)
    for i in range(k):
        x[n - k + i] *= 1.0 - i / k
    return x


def flutter():
    """Turbo-Flattern (Serienlader ohne Ventil, Gas weg): die Luft schlägt im Lader zurück, "tschu-tu-tu-tu" – ein
    Pulszug aus gefiltertem Rauschen, der langsamer und leiser wird, darunter ein fallendes Pfeifen. 0,7 s."""
    rng = random.Random(61)
    n = secs(0.7)
    band = _norm(_hp(lp([rng.uniform(-1.0, 1.0) for _ in range(n)], 2600.0), 450.0))
    x = []
    ph = 0.0
    wph = 0.0
    for i in range(n):
        t = i / SR
        rate = 17.0 - 7.0 * min(1.0, t / 0.6)
        ph += rate / SR
        p = ph % 1.0
        puls = math.exp(-p * 7.0)
        env = min(1.0, t / 0.005) * math.exp(-t * 4.0)
        wph += 2.0 * math.pi * (3000.0 - 1300.0 * min(1.0, t / 0.6)) / SR
        x.append(band[i] * puls * env + math.sin(wph) * 0.05 * env)
    k = secs(0.06)
    for i in range(k):
        x[n - k + i] *= 1.0 - i / k
    return x


def scrape_loop():
    """Blech schrammt an der Wand: körniges Kratzen (Rauschen, schnell zerhackt), metallische Teiltöne der Karosserie,
    die immer wieder angeregt werden, und dumpfes Rumpeln. 2 s nahtlos."""
    rng = random.Random(67)
    n = secs(2.0)
    xf = secs(0.25)
    m = n + xf
    grit = _bp_noise(rng, m, 2400.0, 0.7)
    chop = _wander(rng, m, 60.0)
    exc = [0.0] * m
    i = 0
    while i < m:
        exc[i] = rng.uniform(0.4, 1.0) * (1 if rng.random() < 0.5 else -1)
        i += int(rng.uniform(0.003, 0.02) * SR)
    ring = [0.0] * m
    for fc, q, g in [(1850.0, 18.0, 1.0), (2970.0, 22.0, 0.7), (4410.0, 25.0, 0.45), (1230.0, 14.0, 0.5)]:
        for j, v in enumerate(bandpass(exc, fc, q)):
            ring[j] += v * g
    ring = _norm(ring)
    rum = _norm(lp(lp([rng.uniform(-1.0, 1.0) for _ in range(m)], 220.0), 220.0))
    lvl = _wander(rng, m, 4.0)
    out = []
    for j in range(m):
        g = grit[j] * (0.55 + 0.45 * max(0.0, chop[j]))
        v = (g * 0.75 + ring[j] * 0.6 + rum[j] * 0.5) * (0.85 + 0.15 * lvl[j])
        out.append(math.tanh(1.3 * v))
    return _loop_xfade(out, n, xf)


def road_loop():
    """Abrollen auf Asphalt: Reifen-Brummen (breites Band um 350 Hz) mit feiner Körnung von der Fahrbahn und leichtem
    Schwanken. 2 s nahtlos; die Tonhöhe folgt im Spiel dem Tempo."""
    rng = random.Random(71)
    n = secs(2.0)
    xf = secs(0.3)
    m = n + xf
    hum = _norm([a + 0.5 * b for a, b in zip(bandpass([rng.uniform(-1.0, 1.0) for _ in range(m)], 330.0, 0.7),
                                             bandpass([rng.uniform(-1.0, 1.0) for _ in range(m)], 900.0, 1.1))])
    grit = [0.0] * m
    i = 0
    while i < m:
        grit[i] = rng.uniform(0.2, 1.0) * (1 if rng.random() < 0.5 else -1)
        i += int(rng.uniform(0.001, 0.006) * SR)
    grit = _norm(bandpass(grit, 1400.0, 1.5))
    am = _wander(rng, m, 2.5)
    out = [(hum[j] * 0.85 + grit[j] * 0.2) * (0.88 + 0.12 * am[j]) for j in range(m)]
    return _loop_xfade(out, n, xf)


def wind_loop():
    """Fahrtwind: breites Rauschen (250 Hz – 2,5 kHz) mit langsamen Böen und einem leisen Pfeifen an den Spiegeln.
    3 s nahtlos."""
    rng = random.Random(73)
    n = secs(3.0)
    xf = secs(0.4)
    m = n + xf
    nz = [rng.uniform(-1.0, 1.0) for _ in range(m)]
    body = _norm(_hp(lp(lp(nz, 2500.0), 2500.0), 250.0))
    gust = _wander(rng, m, 0.7)
    gust2 = _wander(rng, m, 3.0)
    whistle = _bp_noise(rng, m, 1700.0, 12.0)
    out = [body[j] * (0.75 + 0.18 * gust[j] + 0.07 * gust2[j]) + whistle[j] * 0.06 * (0.5 + 0.5 * gust[j]) for j in range(m)]
    return _loop_xfade(out, n, xf)


def _tone(f, dur, decay, harm=(1.0, 0.18, 0.06), attack=0.004, vib=0.0):
    """Weicher Ton: Sinus mit leisen Obertönen, kurzer Anstieg, exponentiell abklingend (kein Rechteck)."""
    n = secs(dur)
    x = []
    for i in range(n):
        t = i / SR
        env = min(1.0, t / attack) * math.exp(-t / decay) * min(1.0, (dur - t) / 0.01)
        ph = 2.0 * math.pi * f * (t + vib * math.sin(2.0 * math.pi * 5.5 * t) / (2.0 * math.pi * 5.5))
        x.append(env * sum(a * math.sin(ph * (h + 1)) for h, a in enumerate(harm)))
    return x


def _mix(*parts):
    """Teile mit Versatz mischen: (Signal, Start s, Gain)"""
    n = max(secs(st) + len(sig) for sig, st, g in parts)
    out = [0.0] * n
    for sig, st, g in parts:
        o = secs(st)
        for i, v in enumerate(sig):
            out[o + i] += v * g
    return out


def beep():
    """Countdown 3, 2, 1: kurzer, runder Ton (A5) wie an der Startampel, ohne schnarrende Obertöne. 0,22 s."""
    return _tone(880.0, 0.22, 0.09, (1.0, 0.12, 0.03))


def beep_go():
    """Countdown LOS: eine Oktave höher, länger klingend, dazu ein tiefer, weicher Schlag. 0,9 s."""
    hit = []
    for i in range(secs(0.25)):
        t = i / SR
        hit.append(math.sin(2.0 * math.pi * (70.0 - 25.0 * t) * t) * math.exp(-t / 0.07))
    return _mix((_tone(1760.0, 0.9, 0.32, (1.0, 0.1, 0.02)), 0.0, 1.0), (_tone(880.0, 0.6, 0.18, (1.0, 0.1)), 0.0, 0.35), (hit, 0.0, 0.7))


def turbo_loop():
    """Turbo-Pfeifen: heller Ton (1,1 kHz, geht in 1 s genau auf) mit leichtem Schweben und etwas Luftrauschen."""
    n = secs(1.0)
    xf = secs(0.1)
    air = bandpass(noise(n + xf), 1400.0, 2.0)
    x = []
    for i in range(n + xf):
        t = i / SR
        ph = 2.0 * math.pi * 1100.0 * t + 0.4 * math.sin(2.0 * math.pi * 3.0 * t)
        x.append(math.sin(ph) + 0.12 * math.sin(2 * ph) + air[i] * 0.8)
    return _loop_xfade(x, n, xf)


# --- Menü: kurze, saubere Klicks und Töne (bis 2.21 liefen hier Sprung-, Lande- und Laternen-Geräusche)

def _click(dur, f, decay, bright=0.4):
    """Kurzer Klick: Rauschstoß (hell) und ein kurzer Ton darunter"""
    n = secs(dur)
    nz = _hp(noise(n), 2500.0)
    x = []
    for i in range(n):
        t = i / SR
        x.append(nz[i] * bright * math.exp(-t / 0.004) + math.sin(2.0 * math.pi * f * t) * math.exp(-t / decay))
    return x


def ui_move():
    """Auswahl wandert: sehr kurzes, weiches Ticken (55 ms)."""
    return lp(_click(0.055, 2200.0, 0.012, 0.35), 7000.0)


def ui_change():
    """Wert umschalten (links/rechts, Teil durchblättern): Ticken mit kleinem Ton, eine Spur tiefer (80 ms)."""
    return _mix((_click(0.05, 1500.0, 0.014, 0.3), 0.0, 1.0), (_tone(2400.0, 0.08, 0.02, (1.0,)), 0.0, 0.25))


def ui_select():
    """Bestätigen: zwei schnelle, aufsteigende Töne (E6, H6) mit Klick. 0,26 s."""
    return _mix((_click(0.04, 1800.0, 0.01, 0.4), 0.0, 0.8), (_tone(1318.5, 0.16, 0.05), 0.0, 0.6),
                (_tone(1975.5, 0.22, 0.07), 0.055, 0.55))


def ui_back():
    """Zurück: zwei absteigende, leisere Töne (H5, E5). 0,22 s."""
    return _mix((_click(0.04, 1200.0, 0.01, 0.25), 0.0, 0.6), (_tone(987.8, 0.13, 0.045), 0.0, 0.5),
                (_tone(659.3, 0.18, 0.06), 0.05, 0.5))


def ui_install():
    """Teil eingebaut: satter Schlag (Werkzeug) und ein heller, metallischer Ton darüber, der ausklingt. 0,6 s."""
    n = secs(0.6)
    thump = []
    for i in range(n):
        t = i / SR
        thump.append(math.sin(2.0 * math.pi * (95.0 - 40.0 * t) * t) * math.exp(-t / 0.06))
    ping = [0.0] * n
    for f, a, d in ((2093.0, 1.0, 0.18), (3136.0, 0.45, 0.12), (5274.0, 0.18, 0.06)):
        for i in range(n):
            t = i / SR
            ping[i] += a * math.sin(2.0 * math.pi * f * t) * math.exp(-t / d)
    return _mix((thump, 0.0, 0.9), (_click(0.03, 900.0, 0.01, 0.6), 0.0, 0.6), (ping, 0.012, 0.35), (_tone(2637.0, 0.4, 0.12), 0.07, 0.25))


def ui_locked():
    """Gesperrt: zwei kurze, gedämpfte tiefe Töne. 0,22 s."""
    a = lp(_tone(233.1, 0.08, 0.05, (1.0, 0.5, 0.3, 0.2)), 1500.0)
    return _mix((a, 0.0, 1.0), (a, 0.11, 0.8))


def ui_go():
    """Rennen starten: Luftzug, der hochzieht, mit tiefem Schlag am Ende. 0,7 s."""
    n = secs(0.7)
    nz = noise(n)
    fcs = [400.0 + 3600.0 * (i / n) ** 2 for i in range(n)]
    air = lp_var(nz, fcs)
    x = []
    for i in range(n):
        t = i / SR
        env = (t / 0.5) ** 2 if t < 0.5 else math.exp(-(t - 0.5) / 0.05)
        x.append(air[i] * env * 2.5)
    hit = []
    for i in range(secs(0.3)):
        t = i / SR
        hit.append(math.sin(2.0 * math.pi * (80.0 - 30.0 * t) * t) * math.exp(-t / 0.08))
    return _mix((x, 0.0, 1.0), (hit, 0.48, 0.9), (_tone(1318.5, 0.25, 0.08), 0.48, 0.25))


SOUNDS = {
    "horn": (horn, 0.89), "bell": (bell_loop, 0.7), "rumble": (rumble_loop, 0.89), "thud": (thud, 0.89),
    "whoosh": (whoosh, 0.7), "splash": (splash, 0.89), "clang": (clang, 0.75), "tunnel": (tunnel, 0.8),
    "crowd": (crowd_loop, 0.6), "scrub": (scrub_loop, 0.8), "nitro": (nitro_loop, 0.8),
    "nitro_on": (nitro_on, 0.89), "nitro_off": (nitro_off, 0.85),
    "backfire": (backfire, 0.89), "bov": (bov, 0.85), "flutter": (flutter, 0.85), "scrape": (scrape_loop, 0.8),
    "road": (road_loop, 0.8), "wind": (wind_loop, 0.8), "beep": (beep, 0.6), "beep_go": (beep_go, 0.7),
    "turbo": (turbo_loop, 0.8), "ui_move": (ui_move, 0.5), "ui_change": (ui_change, 0.5), "ui_select": (ui_select, 0.55),
    "ui_back": (ui_back, 0.5), "ui_install": (ui_install, 0.7), "ui_locked": (ui_locked, 0.55), "ui_go": (ui_go, 0.7),
}

if __name__ == "__main__":
    # ohne Argumente alle, sonst nur die genannten (python3 tools/make_sfx.py skid)
    import sys
    for name in sys.argv[1:] or list(SOUNDS):
        fn, gain = SOUNDS[name]
        write(name, fn(), gain)
