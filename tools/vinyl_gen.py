#!/usr/bin/env python3
"""Vinyls und Embleme als SVG erzeugen (seit 2.33). Reines Python, keine Pakete.

    python3 tools/vinyl_gen.py            # alle
    python3 tools/vinyl_gen.py tribal inferno # nur diese

Vinyl (assets/vinyls/<id>.svg, 2048 x 1024): oben (y 0..512) die Flanke, x 0 = Bug, x 2048 = Heck, y 0 = Gürtellinie,
y 512 = Schweller. Unten (y 512..1024) die Draufsicht: x wie oben, y 512 = linke Seite, 768 = Mitte, 1024 = rechte
Seite. Der Shader car_paint legt beides relativ zu Länge, Breite und Gürtellinie aufs Auto, so passt jedes Motiv auf
jedes Auto. Grob, wo was sitzt (4,4-m-Auto): Radläufe bei x 200..580 und 1470..1850 (dort bleibt von der Flanke nur
der obere Streifen bis y ~100), Türen dazwischen; Haube x 0..~750, Dach ~1000..1350, Heckdeckel ab ~1800.

"""
import math
import os
import random
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VDIR = os.path.join(ROOT, "assets", "vinyls")
W, H = 2048, 1024
SY0, SY1 = 4, 508  # Flanke (Rand frei lassen: Mipmaps bluten sonst in die andere Hälfte)
TY0, TY1 = 516, 1020  # Draufsicht
TC = 768  # Mittellinie der Draufsicht


# --- Grundbausteine ---------------------------------------------------------------------------------------------------

def f(v):
    s = "%.1f" % v
    return s[:-2] if s.endswith(".0") else s


def P(pts):
    return " ".join("%s,%s" % (f(x), f(y)) for x, y in pts)


def poly(pts, fill, extra=""):
    return '<polygon points="%s" fill="%s" %s/>' % (P(pts), fill, extra)


def pl(pts, stroke, sw, extra=""):
    return '<polyline points="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round" %s/>' % (
        P(pts), stroke, f(sw), extra)


def path(d, fill="none", stroke=None, sw=None, extra=""):
    s = '<path d="%s" fill="%s"' % (d, fill)
    if stroke:
        s += ' stroke="%s" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round"' % (stroke, f(sw))
    return s + " %s/>" % extra


def circ(x, y, r, fill, extra=""):
    return '<circle cx="%s" cy="%s" r="%s" fill="%s" %s/>' % (f(x), f(y), f(r), fill, extra)


def ell(x, y, rx, ry, fill, rot=0.0, extra=""):
    t = ' transform="rotate(%s %s %s)"' % (f(rot), f(x), f(y)) if rot else ""
    return '<ellipse cx="%s" cy="%s" rx="%s" ry="%s" fill="%s"%s %s/>' % (f(x), f(y), f(rx), f(ry), fill, t, extra)


def rect(x, y, w, h, fill, extra=""):
    return '<rect x="%s" y="%s" width="%s" height="%s" fill="%s" %s/>' % (f(x), f(y), f(w), f(h), fill, extra)


def g(items, extra=""):
    return "<g %s>%s</g>" % (extra, "".join(items))


def catmull(pts, closed=True, k=1.0):
    """Glatte Kurve durch alle Punkte (Catmull-Rom als kubische Bézier)."""
    n = len(pts)
    if n < 3:
        return "M" + " L".join("%s %s" % (f(x), f(y)) for x, y in pts)
    d = "M%s %s" % (f(pts[0][0]), f(pts[0][1]))
    rng = range(n) if closed else range(n - 1)
    for i in rng:
        p0 = pts[(i - 1) % n] if closed or i > 0 else pts[0]
        p1 = pts[i]
        p2 = pts[(i + 1) % n]
        p3 = pts[(i + 2) % n] if closed or i + 2 < n else pts[-1]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6.0 * k, p1[1] + (p2[1] - p0[1]) / 6.0 * k)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6.0 * k, p2[1] - (p3[1] - p1[1]) / 6.0 * k)
        d += " C%s %s %s %s %s %s" % (f(c1[0]), f(c1[1]), f(c2[0]), f(c2[1]), f(p2[0]), f(p2[1]))
    return d + (" Z" if closed else "")


def lerp(a, b, t):
    return a + (b - a) * t


def lerp2(a, b, t):
    return (lerp(a[0], b[0], t), lerp(a[1], b[1], t))


def bez(p0, p1, p2, t):
    """Quadratische Bézier."""
    u = 1 - t
    return (u * u * p0[0] + 2 * u * t * p1[0] + t * t * p2[0], u * u * p0[1] + 2 * u * t * p1[1] + t * t * p2[1])


def bez3(p0, p1, p2, p3, t):
    u = 1 - t
    return (u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
            u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1])


def ribbon(spine, widths, k=1.0):
    """Geschlossene Form um eine Mittellinie (Liste von Punkten) mit Breiten je Punkt (spitz zulaufend: 0)."""
    left, right = [], []
    n = len(spine)
    for i in range(n):
        a = spine[max(i - 1, 0)]
        b = spine[min(i + 1, n - 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / ln, dx / ln
        w = widths[i] / 2.0
        left.append((spine[i][0] + nx * w, spine[i][1] + ny * w))
        right.append((spine[i][0] - nx * w, spine[i][1] - ny * w))
    return catmull(left + right[::-1], True, k)


def mirror_top(items_fn):
    """Draufsicht symmetrisch: items_fn(s) mit s = +1 (rechts) und -1 (links) um die Mittellinie."""
    return items_fn(1) + items_fn(-1)


def ty(s, off):
    """y in der Draufsicht: off Pixel von der Mitte zur Seite s."""
    return TC + s * off


def hsh(ix, iy, seed):
    n = (ix * 374761393 + iy * 668265263 + seed * 2147483647) & 0xFFFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def noise(x, y, seed=0):
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a = hsh(ix, iy, seed)
    b = hsh(ix + 1, iy, seed)
    c = hsh(ix, iy + 1, seed)
    d = hsh(ix + 1, iy + 1, seed)
    return lerp(lerp(a, b, sx), lerp(c, d, sx), sy)


def fbm(x, y, seed=0, oct=3):
    v, a, s = 0.0, 0.5, 1.0
    for o in range(oct):
        v += a * noise(x * s, y * s, seed + o * 17)
        a *= 0.5
        s *= 2.0
    return v / (1.0 - 0.5 ** oct)


def lin_grad(gid, x1, y1, x2, y2, stops):
    st = "".join('<stop offset="%s" stop-color="%s"%s/>' % (f(o), c, (' stop-opacity="%s"' % f(a)) if a < 1 else "")
                 for o, c, a in [(s[0], s[1], s[2] if len(s) > 2 else 1.0) for s in stops])
    return '<linearGradient id="%s" gradientUnits="userSpaceOnUse" x1="%s" y1="%s" x2="%s" y2="%s">%s</linearGradient>' % (
        gid, f(x1), f(y1), f(x2), f(y2), st)


def rad_grad(gid, cx, cy, r, stops):
    st = "".join('<stop offset="%s" stop-color="%s"%s/>' % (f(o), c, (' stop-opacity="%s"' % f(a)) if a < 1 else "")
                 for o, c, a in [(s[0], s[1], s[2] if len(s) > 2 else 1.0) for s in stops])
    return '<radialGradient id="%s" gradientUnits="userSpaceOnUse" cx="%s" cy="%s" r="%s">%s</radialGradient>' % (
        gid, f(cx), f(cy), f(r), st)


def vinyl(side, top, defs=""):
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d"><defs>'
            '<clipPath id="cs"><rect x="0" y="%d" width="%d" height="%d"/></clipPath>'
            '<clipPath id="ct"><rect x="0" y="%d" width="%d" height="%d"/></clipPath>%s</defs>'
            '<g clip-path="url(#cs)">%s</g><g clip-path="url(#ct)">%s</g></svg>\n') % (
        W, H, W, H, SY0, W, SY1 - SY0, TY0, W, TY1 - TY0, defs, "".join(side), "".join(top))


# --- Vinyls -------------------------------------------------------------------------------------------------------------
# Einfarbige Masken (tint) sind weiß: der Shader färbt sie in der Folienfarbe.

def v_speedlines():
    r = random.Random(11)
    side, top = [], []
    for i in range(34):
        y = r.uniform(30, 480)
        ln = r.uniform(500, 1500) * (1.15 if 140 < y < 330 else 0.8)
        th = r.uniform(5, 20)
        x1 = W + 10
        x0 = x1 - ln
        side.append(poly([(x0, y), (x1, y - th / 2), (x1, y + th / 2)], "#fff"))
    # ein breiter Keil oben an der Gürtellinie
    side.append(poly([(260, 40), (W + 10, 18), (W + 10, 70)], "#fff"))
    for s in (1, -1):
        for i in range(9):
            o = r.uniform(170, 245)
            ln = r.uniform(500, 1300)
            th = r.uniform(5, 14)
            top.append(poly([(W + 10 - ln, ty(s, o)), (W + 10, ty(s, o) - th / 2), (W + 10, ty(s, o) + th / 2)], "#fff"))
    return vinyl(side, top)


def tribal_spike(p0, p1, tip, w0, bend):
    """Gebogene, bauchige Klinge von der Basis (p0..p1) zur Spitze; bend wölbt sie (Pixel, quer zur Richtung)."""
    mx, my = (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2
    dx, dy = tip[0] - mx, tip[1] - my
    ln = math.hypot(dx, dy) or 1
    nx, ny = -dy / ln, dx / ln
    c = (mx + dx * 0.45 + nx * bend, my + dy * 0.45 + ny * bend)
    a = [bez(p0, (c[0] + nx * w0 * 0.55, c[1] + ny * w0 * 0.55), tip, t / 14.0) for t in range(15)]
    b = [bez(tip, (c[0] - nx * w0 * 0.25, c[1] - ny * w0 * 0.25), p1, t / 14.0) for t in range(1, 14)]
    return a + b


def blade(base, w0, ang, ln, bend):
    a = math.radians(ang)
    ux, uy = math.cos(a), math.sin(a)
    tip = (base[0] + ux * ln, base[1] + uy * ln)
    p0 = (base[0] - uy * w0 / 2, base[1] + ux * w0 / 2)
    p1 = (base[0] + uy * w0 / 2, base[1] - ux * w0 / 2)
    return tribal_spike(p0, p1, tip, w0, bend)


def v_tribal():
    side, top = [], []
    # Hauptschwung: vom vorderen Kotflügel nach hinten, fett vorn, spitz hinten; Klingen biegen nach hinten ab
    spine = [(90, 330), (260, 210), (520, 150), (820, 170), (1100, 235), (1380, 240), (1660, 180), (1900, 110), (2040, 70)]
    widths = [30, 150, 175, 150, 120, 95, 60, 25, 0]
    side.append(path(ribbon(spine, widths), "#fff"))
    for t, ang, ln, bend, w in [(0.12, 55, 330, 90, 120), (0.26, 30, 420, 110, 115), (0.4, 40, 360, 100, 100),
                                (0.55, 28, 330, 90, 85), (0.7, 35, 260, 70, 60),
                                (0.2, -28, 300, -80, 90), (0.36, -22, 280, -70, 75), (0.52, -18, 230, -60, 60)]:
        k = int(t * (len(spine) - 1))
        f_ = t * (len(spine) - 1) - k
        base = lerp2(spine[k], spine[k + 1], f_)
        side.append(poly(blade(base, w, ang, ln, -bend), "#fff"))
    # Haken nach vorn unten am Kotflügel
    side.append(poly(blade((170, 280), 110, 140, 260, -80), "#fff"))

    def hood(s):
        out = []
        sp = [(20, ty(s, 15)), (200, ty(s, 50)), (430, ty(s, 120)), (680, ty(s, 200)), (860, ty(s, 245))]
        out.append(path(ribbon(sp, [60, 120, 95, 50, 0]), "#fff"))
        for t, ang, ln, w in [(0.25, 55, 230, 70), (0.5, 40, 220, 55), (0.15, -35, 160, 50)]:
            k = int(t * 4)
            base = lerp2(sp[k], sp[k + 1], t * 4 - k)
            out.append(poly(blade(base, w, ang * s, ln, -60 * s), "#fff"))
        return out
    top += mirror_top(hood)

    def deck(s):
        return [poly(blade((1870, ty(s, 70)), 80, 25 * s, 200, -40 * s), "#fff")]
    top += mirror_top(deck)
    return vinyl(side, top)


def v_splitter():
    r = random.Random(7)
    side, top = [], []
    # Splitter fliegen vom Bug nach hinten: vorn dicht und groß, hinten klein und vereinzelt
    for i in range(170):
        t = r.random() ** 1.7
        x = 60 + t * 1700
        y = r.uniform(30, 490)
        sz = lerp(120, 18, t) * r.uniform(0.6, 1.2)
        ang = r.uniform(-0.35, 0.35)
        a = (x + math.cos(ang) * sz * 1.4, y + math.sin(ang) * sz * 1.4)
        b = (x - math.cos(ang + 1.6) * sz * 0.45, y - math.sin(ang + 1.6) * sz * 0.45)
        c = (x + math.cos(ang + 1.9) * sz * 0.5, y + math.sin(ang + 1.9) * sz * 0.5)
        if r.random() < 0.5:
            side.append(poly([a, b, c], "#fff"))
        else:
            d = (x - math.cos(ang) * sz * 0.4, y - math.sin(ang) * sz * 0.4)
            side.append(poly([a, b, d, c], "#fff"))
    # vorn eine geschlossene, gezackte Fläche
    edge = [(0, 0)]
    y = 0
    while y < 520:
        edge.append((r.uniform(180, 320), y))
        y += r.uniform(30, 70)
    edge.append((0, 520))
    side.append(poly(edge, "#fff"))

    def hood(s):
        out = []
        rr = random.Random(9)
        for i in range(70):
            t = rr.random() ** 1.6
            x = 40 + t * 900
            o = rr.uniform(0, 250)
            sz = lerp(90, 14, t)
            ang = rr.uniform(-0.4, 0.4)
            cx, cy = x, ty(s, o)
            out.append(poly([(cx + math.cos(ang) * sz * 1.3, cy + math.sin(ang) * sz * 1.3),
                             (cx - math.cos(ang + 1.5) * sz * 0.4, cy - math.sin(ang + 1.5) * sz * 0.4),
                             (cx + math.cos(ang + 2.0) * sz * 0.5, cy + math.sin(ang + 2.0) * sz * 0.5)], "#fff"))
        return out
    top += mirror_top(hood)
    return vinyl(side, top)


def v_tiger():
    r = random.Random(21)
    side, top = [], []

    def stripe(x, y_top, ln, w, lean, fork, flip=1):
        # spitz zulaufender, leicht gewellter Streifen mit Gabel
        spine = []
        n = 9
        for i in range(n):
            t = i / (n - 1)
            spine.append((x + lean * t + math.sin(t * 5 + x) * 12, y_top + flip * ln * t))
        widths = [w * (1 - t) ** 0.8 * (0.8 + 0.4 * math.sin(t * 7 + x * 0.01)) for t in [i / (n - 1) for i in range(n)]]
        widths[-1] = 0
        out = [path(ribbon(spine, widths), "#fff")]
        if fork:
            k = 3
            b = spine[k]
            sp2 = [b, (b[0] + lean * 0.4 + 40, b[1] + flip * ln * 0.25), (b[0] + lean * 0.6 + 90, b[1] + flip * ln * 0.45)]
            out.append(path(ribbon(sp2, [w * 0.5, w * 0.3, 0]), "#fff"))
        return out
    x = 40
    while x < 2000:
        w = r.uniform(40, 80)
        side += stripe(x, -10, r.uniform(250, 470), w, r.uniform(60, 160), r.random() < 0.5)
        if r.random() < 0.7:
            side += stripe(x + r.uniform(40, 90), 522, r.uniform(150, 300), w * 0.8, r.uniform(60, 140), r.random() < 0.4, -1)
        x += r.uniform(110, 170)

    def deck(s):
        out = []
        rr = random.Random(5 + s)
        x = 30
        while x < 2030:
            ln = rr.uniform(90, 200)
            w = rr.uniform(30, 55)
            sp = [(x, ty(s, 262)), (x + 40, ty(s, 262 - ln * 0.5)), (x + 70, ty(s, 262 - ln))]
            out.append(path(ribbon(sp, [w, w * 0.6, 0]), "#fff"))
            x += rr.uniform(90, 150)
        return out
    top += mirror_top(deck)
    return vinyl(side, top)


def v_checker():
    r = random.Random(4)
    side, top = [], []
    sq = 44
    for gx in range(0, W // sq + 1):
        for gy in range(0, 520 // sq + 1):
            if (gx + gy) % 2:
                continue
            x = gx * sq
            t = (x - 700) / 1100.0  # 0 vorn am Übergang, 1 hinten
            if t < 0:
                continue
            keep = min(t * 1.6, 1.0)
            if r.random() > keep:
                continue
            s = sq * min(0.35 + t * 0.9, 1.0)
            side.append(rect(x + (sq - s) / 2, gy * sq + (sq - s) / 2, s, s, "#fff"))
    # dünne Linie davor
    side.append(rect(380, 230, 520, 10, "#fff"))
    side.append(rect(520, 260, 380, 6, "#fff"))
    for gx in range(0, W // sq + 1):
        for gy in range(-6, 7):
            if (gx + gy) % 2:
                continue
            x = gx * sq
            t = (x - 1050) / 900.0
            if t < 0 or r.random() > min(t * 1.6, 1.0):
                continue
            s = sq * min(0.35 + t * 0.9, 1.0)
            top.append(rect(x + (sq - s) / 2, TC + gy * sq + (sq - s) / 2, s, s, "#fff"))
    return vinyl(side, top)


def flame_tongues(x0, yc, h, ln, n, seed, wig=34.0, sc=1.0):
    """Hot-Rod-Flammen: n Zungen von der Basis (x0, über die Höhe h um yc) nach hinten, geschwungen, spitz. Liefert
    Ribbons (Pfade) und die Basisfläche."""
    rr = random.Random(seed)
    out = []
    for i in range(n):
        t = i / (n - 1) if n > 1 else 0.5
        y0 = yc - h / 2 + t * h
        L = ln * (0.5 + 0.5 * math.sin(math.pi * (0.12 + 0.76 * t))) * rr.uniform(0.85, 1.12) * sc
        ph = rr.uniform(0, 6.28)
        sp = []
        m = 12
        for k in range(m):
            u = k / (m - 1)
            sp.append((x0 + L * u, y0 + math.sin(ph + u * 5.2) * wig * u + (t - 0.5) * 50 * u - 30 * u * u))
        wd = [h / n * 1.9 * sc * (1 - u) ** 0.75 for u in [k / (m - 1) for k in range(m)]]
        wd[-1] = 0
        out.append((sp, wd))
    return out


def v_flames():
    side, top = [], []
    layers = [("#1c1c1c", 1.0, 0, 10), ("#d4100c", 1.0, 0, 0), ("#ff6a00", 0.78, 40, 0), ("#ffd200", 0.55, 80, 0)]
    for col, k, sh, grow in layers:
        tg = flame_tongues(40 + sh, 300, 330 * (0.75 + 0.25 * k), 1550, 7, 12, sc=k)
        for sp, wd in tg:
            side.append(path(ribbon(sp, [w + grow for w in wd]), col))
        side.append(ell(40 + sh * 0.6, 300, 120 * k + grow / 2, 175 * (0.75 + 0.25 * k) + grow / 2, col))

    def hood(s):
        out = []
        for col, k, sh, grow in layers:
            tg = flame_tongues(20 + sh, ty(s, 120), 230 * (0.75 + 0.25 * k), 760, 5, 30 + s, 22, k)
            for sp, wd in tg:
                out.append(path(ribbon(sp, [w + grow for w in wd]), col))
        return out
    top += mirror_top(hood)
    return vinyl(side, top)


def v_camo():
    side, top = [], []
    pal = ["#2b2f33", "#4a5056", "#6c747b", "#1b4f5c", "#0f1113"]
    px = 22
    for region, y0, y1, seed in [(side, 0, 520, 1), (top, 512, 1024, 2)]:
        for gy in range(y0 // px, y1 // px + 1):
            for gx in range(0, W // px + 1):
                x, y = gx * px, gy * px
                # Pixel-Ausfransung nach vorn: vorn wenige Blöcke
                t = min(max((x - 120) / 600.0, 0.0), 1.0)
                if hsh(gx, gy, 99 + seed) > t * 1.15:
                    continue
                v = fbm(x / 260.0, y / 160.0, seed, 3)
                v2 = fbm(x / 90.0, y / 90.0, seed + 5, 2)
                k = int(min(max((v * 0.75 + v2 * 0.35 - 0.2) * 4.0, 0), 4))
                region.append(rect(x, y, px + 0.6, px + 0.6, pal[k]))
    return vinyl(side, top)


def bolt_path(x0, y0, x1, y1, r, seg=9, jag=50):
    pts = [(x0, y0)]
    for i in range(1, seg):
        t = i / seg
        pts.append((lerp(x0, x1, t) + r.uniform(-jag, jag) * 0.4, lerp(y0, y1, t) + r.uniform(-jag, jag)))
    pts.append((x1, y1))
    return pts


def v_bolts():
    r = random.Random(17)
    side, top = [], []
    defs = ""
    for (x0, y0, x1, y1, w) in [(1980, 120, 260, 300, 1.0), (1900, 360, 700, 200, 0.7), (1700, 60, 900, 430, 0.55)]:
        pts = bolt_path(x0, y0, x1, y1, r, 9, 120)
        side.append(pl(pts, "#1fb5ff", 90 * w, 'stroke-opacity="0.12"'))
        side.append(pl(pts, "#2fd5ff", 50 * w, 'stroke-opacity="0.25"'))
        side.append(pl(pts, "#7deaff", 26 * w, 'stroke-opacity="0.7"'))
        side.append(pl(pts, "#ffffff", 11 * w))
        # Verästelungen
        for k in range(2, 9, 3):
            bx, by = pts[k]
            br = bolt_path(bx, by, bx - r.uniform(150, 320), by + r.uniform(-140, 140), r, 4, 40)
            side.append(pl(br, "#4fe3ff", 12 * w, 'stroke-opacity="0.4"'))
            side.append(pl(br, "#e8fbff", 4 * w))

    def hood(s):
        rr = random.Random(40 + s)
        pts = bolt_path(980, ty(s, 60), 40, ty(s, 210), rr, 8, 50)
        return [pl(pts, "#2fd5ff", 36, 'stroke-opacity="0.18"'), pl(pts, "#4fe3ff", 18, 'stroke-opacity="0.45"'),
                pl(pts, "#e8fbff", 7)]
    top += mirror_top(hood)
    return vinyl(side, top, defs)


def petal_pts(cx, cy, ang, ln, w):
    """Kirschblütenblatt: vom Mittelpunkt nach außen, vorn mit kleiner Kerbe."""
    ux, uy = math.cos(ang), math.sin(ang)
    nx, ny = -uy, ux
    def P_(a, b):
        return (cx + ux * a + nx * b, cy + uy * a + ny * b)
    pts = []
    for t in range(9):
        u = t / 8
        pts.append(P_(ln * u, w * 0.5 * math.sin(math.pi * min(u * 1.1, 1.0)) ** 0.7))
    pts.append(P_(ln * 0.88, 0))
    for t in range(8, -1, -1):
        u = t / 8
        pts.append(P_(ln * u, -w * 0.5 * math.sin(math.pi * min(u * 1.1, 1.0)) ** 0.7))
    return pts


def blossom(cx, cy, r, rot, col="#ffb3cf", col2="#ff6fa8"):
    out = []
    for k in range(5):
        a = rot + k * math.tau / 5
        out.append(poly(petal_pts(cx, cy, a, r, r * 0.9), col))
        out.append(poly(petal_pts(cx, cy, a, r * 0.45, r * 0.4), col2))
    out.append(circ(cx, cy, r * 0.16, "#ffe36e"))
    for k in range(5):
        a = rot + (k + 0.5) * math.tau / 5
        out.append(circ(cx + math.cos(a) * r * 0.3, cy + math.sin(a) * r * 0.3, r * 0.05, "#c2185b"))
    return out


def v_sakura():
    r = random.Random(31)
    side, top = [], []
    br = "#2a1714"
    main = [(2060, 470), (1850, 420), (1620, 330), (1400, 280), (1150, 250), (900, 190), (700, 120)]
    side.append(path(ribbon(main, [46, 40, 34, 28, 22, 14, 2]), br))
    twigs = [[(1620, 330), (1560, 220), (1500, 140)], [(1400, 280), (1330, 380), (1220, 430)],
             [(1150, 250), (1100, 150), (1020, 90)], [(1850, 420), (1800, 300), (1760, 210)]]
    for tw in twigs:
        side.append(path(ribbon(tw, [16, 9, 2]), br))
    flowers = [(1500, 140, 46), (1560, 210, 34), (1220, 430, 44), (1300, 375, 30), (1020, 90, 40), (1100, 160, 32),
               (700, 120, 38), (800, 170, 30), (900, 190, 26), (1760, 210, 42), (1700, 360, 36), (1400, 280, 30),
               (1950, 440, 34), (1180, 245, 24)]
    for (x, y, rr) in flowers:
        side += blossom(x, y, rr * 1.5, r.uniform(0, 6.28))
    for i in range(46):
        x = r.uniform(80, 1500) * (0.6 + 0.4 * r.random())
        y = r.uniform(30, 480)
        sz = r.uniform(10, 20)
        side.append(poly(petal_pts(x, y, r.uniform(0, 6.28), sz * 1.6, sz), "#ffc2d9" if i % 3 else "#ff8fbd"))

    def deck(s):
        out = []
        rr = random.Random(50 + s)
        for i in range(26):
            x = rr.uniform(20, 900)
            o = rr.uniform(10, 245)
            sz = rr.uniform(10, 18)
            out.append(poly(petal_pts(x, ty(s, o), rr.uniform(0, 6.28), sz * 1.6, sz), "#ffc2d9" if i % 3 else "#ff8fbd"))
        return out
    top += mirror_top(deck)
    top.append(path(ribbon([(2050, ty(1, 200)), (1960, ty(1, 120)), (1880, ty(1, 40))], [22, 14, 3]), br))
    top += blossom(1930, ty(1, 150), 34, 0.4) + blossom(1890, ty(1, 60), 28, 1.2) + blossom(1990, ty(-1, 140), 30, 2.0)
    return vinyl(side, top)


def v_wave():
    r = random.Random(41)
    side, top = [], []
    deep, mid, light, foam = "#0e2a63", "#1f57a8", "#5aa0e6", "#f4f8ff"
    # Wellenberg: steigt von hinten unten auf, Kamm bei x 1150, rollt nach vorn über
    crest = [(2060, 330), (1800, 260), (1500, 160), (1250, 70), (1080, 40), (930, 80), (860, 160), (900, 230),
             (980, 230), (1000, 170)]
    body = [(700, 520), (760, 470), (820, 400)] + crest[::-1][3:] + [(2060, 330), (2060, 520)]
    body = [(700, 520), (800, 430), (900, 330), (1000, 260), (1080, 210), (1160, 160), (1250, 110), (1300, 90)] + \
           [(1500, 180), (1800, 270), (2060, 330), (2060, 520)]
    side.append(poly(body, deep))
    curl = crest[1:]
    side.append(path(catmull([(1800, 262), (1500, 160), (1250, 70), (1080, 40), (930, 80), (860, 160), (905, 232), (985, 232),
                              (1010, 170), (1080, 130), (1250, 130), (1500, 210), (1800, 290)], True, 1.0), deep))
    # Bänder im Wasser
    for k in range(6):
        o = 30 + k * 45
        pts = [(900 + k * 20 + 40, 250 + o), (1100, 190 + o), (1300, 150 + o), (1550, 230 + o), (1850, 300 + o), (2060, 350 + o)]
        side.append(pl(pts, mid if k % 2 else light, 12 - k, 'stroke-opacity="0.85"'))
    # Gischt-Krallen am Kamm
    for i in range(16):
        t = i / 15
        x, y = bez3((1800, 262), (1350, 60), (1000, -10), (880, 170), t)
        a = math.atan2(-1, -0.4) + r.uniform(-0.6, 0.6)
        ln = r.uniform(40, 80)
        side.append(poly(blade((x, y), 30, math.degrees(a), ln, 18), foam))
        side.append(circ(x, y, r.uniform(10, 18), foam))
    for i in range(30):
        side.append(circ(r.uniform(820, 1500), r.uniform(10, 200), r.uniform(4, 10), foam))
    # vorn kleine Wellen
    for i in range(5):
        x0 = 120 + i * 120
        side.append(path(catmull([(x0, 480), (x0 + 40, 430), (x0 + 90, 440), (x0 + 70, 470), (x0 + 110, 480)], False, 1.0),
                         "none", light, 10))

    def hood(s):
        out = []
        sz = 52
        for gx in range(0, 18):
            for gy in range(0, 6):
                x = gx * sz + (sz / 2 if gy % 2 else 0)
                o = gy * sz * 0.5 + 10
                if x > 820 - gy * 40:
                    continue
                for k, c in enumerate([deep, mid, light, foam]):
                    out.append(circ(x, ty(s, 255 - o), sz * (0.62 - k * 0.14), c))
        return out
    top += mirror_top(hood)
    return vinyl(side, top)


LETTERS = {  # Skelette in einem Feld 0..1 (x) x 0..1 (y), je Buchstabe Liste von Strichen
    "N": [[(0, 1), (0.02, 0), (0.98, 1), (1, 0)]],
    "F": [[(0.05, 1), (0, 0), (0.95, 0.02)], [(0.02, 0.5), (0.7, 0.48)]],
    "G": [[(0.95, 0.15), (0.6, 0.0), (0.2, 0.08), (0.0, 0.5), (0.18, 0.92), (0.6, 1.0), (0.98, 0.82), (0.98, 0.55), (0.55, 0.55)]],
}


def v_graffiti():
    r = random.Random(52)
    side, top = [], []
    defs = lin_grad("gf", 0, 90, 0, 430, [(0, "#fff36b"), (0.5, "#ffb000"), (1, "#ff3d7f")])
    # Hintergrund: Pfeil-Schwung und Farbspritzer
    side.append(path(ribbon([(380, 400), (700, 470), (1100, 460), (1500, 380), (1850, 250)], [30, 70, 80, 60, 10]), "#7a2cff"))
    side.append(poly([(1850, 250), (1760, 180), (1960, 200), (1900, 330)], "#7a2cff"))
    for i in range(14):
        x, y = r.uniform(450, 1750), r.uniform(40, 480)
        side.append(circ(x, y, r.uniform(6, 26), ["#19e3ff", "#ff2bd6", "#7cff00"][i % 3]))
    letters = "NFG"
    x0, y0, lw, lh, gap = 560, 100, 280, 300, 50
    strokes = []
    for i, ch in enumerate(letters):
        lx = x0 + i * (lw + gap) + (i % 2) * 10
        tilt = [-0.06, 0.04, -0.03][i]
        for st in LETTERS[ch]:
            pts = [(lx + px * lw + (py - 0.5) * lh * tilt, y0 + py * lh + (20 if i == 1 else 0)) for px, py in st]
            strokes.append(pts)
    sw = 92
    for pts in strokes:  # Schatten
        side.append(pl([(x + 22, y + 22) for x, y in pts], "#2b0a4f", sw + 26))
    for pts in strokes:  # Kontur
        side.append(pl(pts, "#111", sw + 26))
    for pts in strokes:  # Füllung
        side.append(pl(pts, "url(#gf)", sw))
    for pts in strokes:  # Glanz
        side.append(pl([(x - 14, y - 16) for x, y in pts[:2]], "#fff", 14, 'stroke-opacity="0.85"'))
    # Tropfen
    for i in range(9):
        x = r.uniform(x0 + 10, x0 + 3 * (lw + gap) - 60)
        y = y0 + lh + r.uniform(20, 50)
        ln = r.uniform(40, 120)
        side.append(pl([(x, y - 30), (x, y + ln)], "#ffb000", 14))
        side.append(circ(x, y + ln + 6, 11, "#ff3d7f"))
    # Sterne
    for (x, y, rr) in [(470, 90, 40), (1580, 110, 34), (1640, 420, 26)]:
        st = []
        for k in range(8):
            a = k * math.pi / 4
            q = rr if k % 2 == 0 else rr * 0.32
            st.append((x + math.cos(a) * q, y + math.sin(a) * q))
        side.append(poly(st, "#fff"))

    def deck(s):
        out = []
        rr = random.Random(60 + s)
        for i in range(10):
            x, o = rr.uniform(30, 800), rr.uniform(30, 240)
            out.append(circ(x, ty(s, o), rr.uniform(8, 30), ["#19e3ff", "#ff2bd6", "#ffb000"][i % 3]))
        out.append(path(ribbon([(40, ty(s, 230)), (400, ty(s, 200)), (800, ty(s, 230)), (1100, ty(s, 245))], [20, 40, 30, 0]), "#7a2cff"))
        return out
    top += mirror_top(deck)
    return vinyl(side, top, defs)


def hexagon(cx, cy, r):
    return [(cx + r * math.cos(math.radians(60 * k + 30)), cy + r * math.sin(math.radians(60 * k + 30))) for k in range(6)]


def v_hex():
    r = random.Random(61)
    side, top = [], []
    R = 34
    dx, dy = R * math.sqrt(3), R * 1.5

    def grid(y0, y1, xfade0, xfade1, out, seed):
        rr = random.Random(seed)
        row = 0
        y = y0
        while y < y1 + R:
            x = (dx / 2 if row % 2 else 0)
            while x < W + R:
                t = (x - xfade0) / (xfade1 - xfade0)
                if t > 0 and rr.random() < min(t * 1.3, 1.0):
                    c = "#19e3ff" if rr.random() < (1 - t) * 0.7 + 0.3 else "#ff2bd6"
                    if rr.random() < 0.18 * t:
                        out.append(poly(hexagon(x, y, R * 0.86), c, 'fill-opacity="0.85"'))
                    else:
                        out.append(poly(hexagon(x, y, R * 0.86), "none", 'stroke="%s" stroke-width="5" stroke-opacity="%s"' % (c, f(0.4 + 0.6 * min(t, 1)))))
                x += dx
            y += dy
            row += 1
    grid(-10, 520, 500, 1700, side, 1)
    # Lichtkante
    side.append(pl([(500, 470), (1000, 470), (1060, 430), (2048, 430)], "#19e3ff", 6))
    grid(512, 1024, 900, 1900, top, 2)
    return vinyl(side, top)


def v_circuit():
    r = random.Random(71)
    side, top = [], []
    green, glow = "#3dff9a", "#00ff88"

    def trace(x, y, steps, out, ymin, ymax, rr, sw=7):
        pts = [(x, y)]
        d = 0
        for i in range(steps):
            if rr.random() < 0.3:
                d = rr.choice([-1, 1]) if d == 0 else 0
            ln = rr.uniform(40, 110)
            nx = x - ln
            ny = y + (ln * d if d else 0)
            if ny < ymin or ny > ymax:
                d = 0
                ny = y
            x, y = nx, ny
            pts.append((x, y))
        out.append(pl(pts, glow, sw * 3.2, 'stroke-opacity="0.18"'))
        out.append(pl(pts, green, sw))
        out.append(circ(x, y, sw * 2.0, green))
        out.append(circ(x, y, sw * 0.9, "#06140c"))
        return pts
    for i in range(22):
        y = r.uniform(30, 490)
        trace(r.uniform(1900, 2060), y, r.randint(6, 16), side, 20, 500, r)
    for (x, y, w, h) in [(1500, 200, 140, 90), (1150, 330, 110, 70)]:
        side.append(rect(x, y, w, h, "#0b1f15", 'stroke="%s" stroke-width="5"' % green))
        for k in range(5):
            side.append(rect(x + 12 + k * (w - 24) / 4 - 4, y - 16, 8, 16, green))
            side.append(rect(x + 12 + k * (w - 24) / 4 - 4, y + h, 8, 16, green))

    def hood(s):
        out = []
        rr = random.Random(80 + s)
        for i in range(9):
            o = rr.uniform(20, 240)
            trace(rr.uniform(780, 900), ty(s, o), rr.randint(5, 11), out, ty(s, 250) if s < 0 else ty(s, 10),
                  ty(s, 10) if s < 0 else ty(s, 250), rr, 6)
        return out
    top += mirror_top(hood)
    return vinyl(side, top)


def splat(cx, cy, rad, col, rr, drips=0, out=None):
    pts = []
    n = 28
    for k in range(n):
        a = k / n * math.tau
        q = rad * (0.75 + 0.35 * rr.random())
        if rr.random() < 0.25:
            q *= 1.5
        pts.append((cx + math.cos(a) * q, cy + math.sin(a) * q))
    out.append(path(catmull(pts, True, 0.8), col))
    for k in range(int(rad / 6)):
        a = rr.uniform(0, math.tau)
        d = rad * rr.uniform(1.2, 2.4)
        out.append(circ(cx + math.cos(a) * d, cy + math.sin(a) * d, rr.uniform(2, rad * 0.14), col))
    for k in range(drips):
        x = cx + rr.uniform(-rad * 0.6, rad * 0.6)
        ln = rr.uniform(rad * 0.6, rad * 2.0)
        out.append(pl([(x, cy), (x, cy + ln)], col, rr.uniform(8, 16)))
        out.append(circ(x, cy + ln + 4, 10, col))


def v_splatter():
    r = random.Random(81)
    side, top = [], []
    cols = ["#ff2bd6", "#ffe600", "#00e5ff", "#7cff00", "#ff6a00"]
    for i, (x, y, rad) in enumerate([(1700, 200, 120), (1350, 330, 95), (1020, 170, 110), (720, 300, 80), (1900, 400, 70),
                                     (450, 160, 55), (1180, 80, 50), (1550, 440, 60)]):
        splat(x, y, rad, cols[i % len(cols)], r, 2 if y < 350 else 0, side)

    def deck(s):
        out = []
        rr = random.Random(90 + s)
        for i, (x, o, rad) in enumerate([(300, 120, 70), (650, 200, 55), (1180, 80, 60), (1900, 150, 60)]):
            splat(x, ty(s, o), rad, cols[(i + (2 if s > 0 else 0)) % len(cols)], rr, 0, out)
        return out
    top += mirror_top(deck)
    return vinyl(side, top)


def v_sunrays():
    side, top = [], []
    red = "#d3141c"
    cx, cy = 2130, 560
    n = 16
    for k in range(n):
        a0 = math.radians(180 - 75 + k * 150 / n)
        a1 = a0 + math.radians(150 / n * 0.55)
        L = 2400
        side.append(poly([(cx, cy), (cx + math.cos(a0) * L, cy - math.sin(a0) * L * 0.8),
                          (cx + math.cos(a1) * L, cy - math.sin(a1) * L * 0.8)], red))
    side.append(circ(cx, cy, 330, red))
    side.append(circ(cx, cy, 330, "none", 'stroke="#ffffff" stroke-width="10"'))
    # vorn ausblenden: weiße Fläche wäre Lack, also einfach abschneiden mit Zacken
    tc = 1980
    for k in range(18):
        a0 = math.radians(180 - 60 + k * 120 / 18)
        a1 = a0 + math.radians(120 / 18 * 0.55)
        L = 1500
        top.append(poly([(tc, TC), (tc + math.cos(a0) * L, TC - math.sin(a0) * L * 0.4),
                         (tc + math.cos(a1) * L, TC - math.sin(a1) * L * 0.4)], red))
    top.append(circ(tc + 60, TC, 160, red))
    return vinyl(side, top)


def v_glitch():
    r = random.Random(91)
    side, top = [], []
    dark, mag, cyan = "#0b0b12", "#ff1f8f", "#19e3ff"

    def split(y0, y1, xa, xb, out, rr, scan=True):
        # Grenze von (xa oben) nach (xb unten), in Scheiben versetzt
        y = y0
        left = []
        while y < y1:
            h = rr.uniform(8, 46)
            x = lerp(xa, xb, (y - y0) / (y1 - y0)) + (rr.uniform(-90, 90) if rr.random() < 0.55 else 0)
            left += [(x, y), (x, y + h)]
            y += h
        poly_pts = left + [(W + 20, y1), (W + 20, y0)]
        out.append(poly([(x - 22, y) for x, y in left] + [(W + 20, y1), (W + 20, y0)], mag))
        out.append(poly([(x + 12, y) for x, y in left] + [(W + 20, y1), (W + 20, y0)], cyan))
        out.append(poly([(x + 30, y) for x, y in left] + [(W + 20, y1), (W + 20, y0)], dark))
        if scan:
            yy = y0 + 6
            while yy < y1:
                out.append(rect(lerp(xa, xb, (yy - y0) / (y1 - y0)) + 120, yy, W, 3, "#1e1e2c"))
                yy += 14
        # Pixelblöcke an der Kante
        for k in range(40):
            yy = rr.uniform(y0, y1)
            x = lerp(xa, xb, (yy - y0) / (y1 - y0)) + rr.uniform(-260, 60)
            sz = rr.choice([8, 12, 16, 24])
            out.append(rect(x, yy, sz * rr.uniform(1, 4), sz, rr.choice([mag, cyan, dark, "#ffffff"])))
    split(0, 520, 760, 1250, side, r)
    split(512, 1024, 1050, 1050, top, random.Random(5), False)
    return vinyl(side, top)


def v_prism():
    side, top = [], []
    stops = [(0.0, "#19e3ff"), (0.17, "#7a5cff"), (0.34, "#ff2bd6"), (0.5, "#ff8a3d"), (0.66, "#ffe14d"), (0.83, "#5cffb0"), (1.0, "#19e3ff")]
    defs = lin_grad("pr", 250, 600, 2150, -350, stops) + lin_grad("pr2", 700, 1024, 2100, 512, stops) + \
        lin_grad("sh", 0, 0, 2048, 0, [(0, "#ffffff", 0.0), (0.5, "#ffffff", 0.35), (1, "#ffffff", 0.0)])
    edge = [(420, -10), (300, 120), (380, 230), (250, 360), (330, 530)]
    side.append(poly(edge + [(W + 10, 530), (W + 10, -10)], "url(#pr)", 'fill-opacity="0.92"'))
    for k in range(7):
        x = 600 + k * 230
        side.append(poly([(x, -10), (x + 60, -10), (x - 120, 530), (x - 180, 530)], "url(#sh)"))
    top.append(poly([(900, 500), (760, 640), (840, 768), (760, 896), (900, 1030), (W + 10, 1030), (W + 10, 500)], "url(#pr2)", 'fill-opacity="0.92"'))
    return vinyl(side, top, defs)


def T(pts, ox, oy, sx=1.0, sy=None, rot=0.0):
    """Punkte verschieben, skalieren (sx, sy), drehen (Grad)."""
    sy = sx if sy is None else sy
    c, s_ = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    return [(ox + (x * sx) * c - (y * sy) * s_, oy + (x * sx) * s_ + (y * sy) * c) for x, y in pts]


def sym(half):
    """Rechte Hälfte (x >= 0, von oben nach unten) zu einer symmetrischen Form ergänzen."""
    return half + [(-x, y) for x, y in reversed(half)]


def koi(cx, cy, ln, ang, cid, body_c="#f7f4ee", spot_c="#ff4a1c", dark_c="#1a1a1a", seed=1):
    """Koi, Kopf in Richtung ang (Grad, 180 = nach links/vorn). Liefert (defs, items)."""
    rr = random.Random(seed)
    a = math.radians(ang)
    ux, uy = math.cos(a), math.sin(a)
    sp = [(cx + ux * ln * (0.5 - t) + -uy * math.sin(t * 3.0) * ln * 0.05, cy + uy * ln * (0.5 - t) + ux * math.sin(t * 3.0) * ln * 0.05)
          for t in [k / 14 for k in range(15)]]
    wd = [ln * w for w in [0.08, 0.19, 0.25, 0.27, 0.26, 0.24, 0.21, 0.18, 0.14, 0.11, 0.08, 0.06, 0.05, 0.045, 0.04]]
    body = ribbon(sp, wd)
    defs = '<clipPath id="%s">%s</clipPath>' % (cid, path(body, "#000"))
    out = []
    # Schwanzflosse: zwei Lappen
    tail = sp[-1]
    tx, ty_ = -ux, -uy
    nx, ny = -uy, ux
    for sgn in (1, -1):
        tip = (tail[0] + tx * ln * 0.28 + nx * sgn * ln * 0.2, tail[1] + ty_ * ln * 0.28 + ny * sgn * ln * 0.2)
        mid = (tail[0] + tx * ln * 0.1 + nx * sgn * ln * 0.02, tail[1] + ty_ * ln * 0.1 + ny * sgn * ln * 0.02)
        out.append(path(catmull([tail, (tail[0] + nx * sgn * ln * 0.12 + tx * ln * 0.1, tail[1] + ny * sgn * ln * 0.12 + ty_ * ln * 0.1), tip,
                                 (tip[0] - tx * ln * 0.08, tip[1] - ty_ * ln * 0.08), mid], True, 0.8), spot_c, extra='fill-opacity="0.85"'))
    # Brustflossen
    for sgn in (1, -1):
        b = sp[4]
        tip = (b[0] + nx * sgn * ln * 0.24 - ux * ln * 0.12, b[1] + ny * sgn * ln * 0.24 - uy * ln * 0.12)
        out.append(path(catmull([b, (b[0] + nx * sgn * ln * 0.16, b[1] + ny * sgn * ln * 0.16), tip,
                                 (b[0] + nx * sgn * ln * 0.08 - ux * ln * 0.1, b[1] + ny * sgn * ln * 0.08 - uy * ln * 0.1)], True, 0.9),
                        spot_c, extra='fill-opacity="0.7"'))
    out.append(path(body, body_c))
    patches = []
    for k in range(6):
        t = rr.uniform(0.15, 0.85)
        p = sp[int(t * 14)]
        r0 = ln * rr.uniform(0.07, 0.13)
        pts = []
        for j in range(12):
            q = r0 * rr.uniform(0.7, 1.3)
            pts.append((p[0] + math.cos(j * math.tau / 12) * q * 1.4, p[1] + math.sin(j * math.tau / 12) * q))
        patches.append(path(catmull(pts, True), spot_c))
    patches.append(circ(sp[1][0], sp[1][1], ln * 0.1, spot_c))  # Kopffleck (Tancho)
    for k in range(5):
        p = sp[rr.randint(5, 12)]
        patches.append(circ(p[0] + rr.uniform(-ln * 0.05, ln * 0.05), p[1] + rr.uniform(-ln * 0.05, ln * 0.05), ln * rr.uniform(0.012, 0.025), dark_c))
    # Schuppen
    for k in range(3, 12):
        p = sp[k]
        for j in (-1, 0, 1):
            q = (p[0] + nx * j * wd[k] * 0.28, p[1] + ny * j * wd[k] * 0.28)
            patches.append(path("M%s %s A%s %s 0 0 0 %s %s" % (f(q[0] + nx * 12), f(q[1] + ny * 12), f(14), f(14),
                                                               f(q[0] - nx * 12), f(q[1] - ny * 12)), "none", "#000", 2.5, 'stroke-opacity="0.18"'))
    out.append(g(patches, 'clip-path="url(#%s)"' % cid))
    out.append(path(body, "none", "#2a1a12", 4, 'stroke-opacity="0.5"'))
    h = sp[0]
    for sgn in (1, -1):
        e = (h[0] + ux * ln * 0.02 + nx * sgn * ln * 0.07, h[1] + uy * ln * 0.02 + ny * sgn * ln * 0.07)
        out.append(circ(e[0], e[1], ln * 0.018, dark_c))
        bar = [(h[0] + ux * ln * 0.06 + nx * sgn * ln * 0.03, h[1] + uy * ln * 0.06 + ny * sgn * ln * 0.03),
               (h[0] + ux * ln * 0.11 + nx * sgn * ln * 0.07, h[1] + uy * ln * 0.11 + ny * sgn * ln * 0.07),
               (h[0] + ux * ln * 0.12 + nx * sgn * ln * 0.13, h[1] + uy * ln * 0.12 + ny * sgn * ln * 0.13)]
        out.append(path(catmull(bar, False), "none", "#2a1a12", 4))
    return defs, out


def ripples(cx, cy, n, r0, col, sx=1.0):
    return [ell(cx, cy, r0 * (k + 1) * sx, r0 * (k + 1) * 0.35, "none", 0, 'stroke="%s" stroke-width="5" stroke-opacity="%s"' % (col, f(0.7 - k * 0.15)))
            for k in range(n)]


def v_koi():
    side, top = [], []
    d1, k1 = koi(1060, 250, 900, 178, "k1", seed=3)
    side += ripples(1500, 400, 4, 70, "#7fc8ff", 2.2) + ripples(560, 90, 3, 50, "#7fc8ff", 2.0)
    side += k1
    d2, k2 = koi(420, TC, 640, 180, "k2", "#f3c432", "#1a1a1a", "#1a1a1a", seed=8)
    d3, k3 = koi(1500, TC + 60, 460, 200, "k3", seed=5)
    top += ripples(800, TC - 120, 3, 60, "#7fc8ff", 1.6) + k2 + k3
    return vinyl(side, top, d1 + d2 + d3)


def feather(x, y, ang, ln, w, fill, edge):
    pts = petal_pts(x, y, math.radians(ang), ln, w)
    return [poly(pts, fill, 'stroke="%s" stroke-width="3"' % edge),
            pl([(x, y), (x + math.cos(math.radians(ang)) * ln * 0.85, y + math.sin(math.radians(ang)) * ln * 0.85)], edge, 2.5)]


def v_wings():
    side, top = [], []
    white, shade, edge, gold = "#f7f9ff", "#d9e2f3", "#9aaccc", "#e3b448"
    root = (720, 170)
    lead = [(root[0] + 1250 * t, root[1] - 110 * math.sin(t * 2.4) + 20 * t) for t in [k / 20 for k in range(21)]]
    # Handschwingen (lang, hinten), dann Armschwingen, dann Deckfedern
    for k in range(13):
        t = 0.45 + k * 0.045
        p = lead[min(int(t * 20), 20)]
        side += feather(p[0] - 40, p[1] + 30, 62 - k * 3.5, 330 - k * 6, 70, white if k % 2 else shade, edge)
    for k in range(12):
        t = 0.05 + k * 0.04
        p = lead[int(t * 20)]
        side += feather(p[0], p[1] + 40, 78 - k * 1.5, 300 - k * 4, 74, shade if k % 2 else white, edge)
    for k in range(18):
        t = k / 18 * 0.95
        p = lead[int(t * 20)]
        side += feather(p[0] + 10, p[1] + 6, 70 - t * 30, 160, 64, white, edge)
    side.append(pl(lead, gold, 16))
    side.append(pl(lead[:12], "#fff3c4", 5))

    def hood(s):
        out = []
        for k in range(9):
            out += feather(120 + k * 60, ty(s, 60 + k * 10), s * (25 + k * 4), 210, 56, white if k % 2 else shade, edge)
        return out
    top += mirror_top(hood)
    top.append(ell(1180, TC, 150, 110, "none", 0, 'stroke="%s" stroke-width="24"' % gold))
    top.append(ell(1180, TC, 150, 110, "none", 0, 'stroke="#fff3c4" stroke-width="6"'))
    return vinyl(side, top)


# Mini-Schrift in Strichen (Feld 0..1 x 0..1), eckig wie auf Maschinen
FONT = {
    "0": [[(0, 0.15), (0.15, 0), (0.85, 0), (1, 0.15), (1, 0.85), (0.85, 1), (0.15, 1), (0, 0.85), (0, 0.15)]],
    "7": [[(0, 0), (1, 0), (1, 0.2), (0.45, 1)]],
    "U": [[(0, 0), (0, 0.85), (0.15, 1), (0.85, 1), (1, 0.85), (1, 0)]],
    "N": [[(0, 1), (0, 0), (1, 1), (1, 0)]],
    "I": [[(0.5, 0), (0.5, 1)]],
    "T": [[(0, 0), (1, 0)], [(0.5, 0), (0.5, 1)]],
    "-": [[(0.15, 0.5), (0.85, 0.5)]],
    "D": [[(0, 0), (0.75, 0), (1, 0.25), (1, 0.75), (0.75, 1), (0, 1), (0, 0)]],
    "A": [[(0, 1), (0, 0.25), (0.25, 0), (0.75, 0), (1, 0.25), (1, 1)], [(0, 0.55), (1, 0.55)]],
    "G": [[(1, 0.15), (0.85, 0), (0.15, 0), (0, 0.15), (0, 0.85), (0.15, 1), (0.85, 1), (1, 0.85), (1, 0.55), (0.55, 0.55)]],
    "E": [[(1, 0), (0, 0), (0, 1), (1, 1)], [(0, 0.5), (0.7, 0.5)]],
    "R": [[(0, 1), (0, 0), (0.85, 0), (1, 0.15), (1, 0.4), (0.85, 0.55), (0, 0.55)], [(0.5, 0.55), (1, 1)]],
    "S": [[(1, 0.1), (0.85, 0), (0.15, 0), (0, 0.15), (0, 0.4), (0.15, 0.5), (0.85, 0.5), (1, 0.6), (1, 0.85), (0.85, 1), (0.15, 1), (0, 0.9)]],
    "Y": [[(0, 0), (0.5, 0.5), (1, 0)], [(0.5, 0.5), (0.5, 1)]],
    "B": [[(0, 0), (0, 1), (0.85, 1), (1, 0.85), (1, 0.62), (0.85, 0.5), (0, 0.5)], [(0, 0), (0.8, 0), (0.95, 0.12), (0.95, 0.38), (0.8, 0.5)]],
    "X": [[(0, 0), (1, 1)], [(1, 0), (0, 1)]],
    "O": [[(0, 0.15), (0.15, 0), (0.85, 0), (1, 0.15), (1, 0.85), (0.85, 1), (0.15, 1), (0, 0.85), (0, 0.15)]],
    "L": [[(0, 0), (0, 1), (1, 1)]],
    "C": [[(1, 0.1), (0.85, 0), (0.15, 0), (0, 0.15), (0, 0.85), (0.15, 1), (0.85, 1), (1, 0.9)]],
    "K": [[(0, 0), (0, 1)], [(1, 0), (0, 0.55), (1, 1)]],
    "H": [[(0, 0), (0, 1)], [(1, 0), (1, 1)], [(0, 0.5), (1, 0.5)]],
    "M": [[(0, 1), (0, 0), (0.5, 0.5), (1, 0), (1, 1)]],
    "P": [[(0, 1), (0, 0), (0.85, 0), (1, 0.15), (1, 0.4), (0.85, 0.55), (0, 0.55)]],
    "V": [[(0, 0), (0.5, 1), (1, 0)]],
    "1": [[(0.2, 0.2), (0.55, 0), (0.55, 1)]],
    "2": [[(0, 0.15), (0.15, 0), (0.85, 0), (1, 0.15), (1, 0.4), (0, 1), (1, 1)]],
    "3": [[(0, 0), (1, 0), (0.45, 0.45), (0.85, 0.45), (1, 0.6), (1, 0.85), (0.85, 1), (0, 1)]],
}


def stroke_text(text, x, y, h, col, sw, spacing=0.35, cap="square", slant=0.0):
    out = []
    w = h * 0.62
    for ch in text:
        if ch == " ":
            x += w * 0.7
            continue
        for st in FONT.get(ch, []):
            pts = [(x + px * w + (1 - py) * h * slant, y + py * h) for px, py in st]
            out.append('<polyline points="%s" fill="none" stroke="%s" stroke-width="%s" stroke-linecap="%s" stroke-linejoin="miter"/>' % (
                P(pts), col, f(sw), cap))
        x += w * (1 + spacing)
    return out


def hazard(x, y, w, h, n_w=40):
    out = [rect(x, y, w, h, "#ffd000")]
    k = x - h
    while k < x + w:
        out.append(poly([(max(k, x), y + h - (max(k, x) - k)), (min(k + n_w, x + w), y + h - (min(k + n_w, x + w) - k)),
                         (min(k + n_w + h, x + w), y + h - min(h, min(k + n_w + h, x + w) - k - n_w)), (max(k + h, x), y)], "#141414")
                   if False else poly([(k, y + h), (k + n_w, y + h), (k + n_w + h, y), (k + h, y)], "#141414"))
        k += n_w * 2
    return out


def v_unit07():
    """Mecha-Lackierung. Mit Schrift, also rechts nicht gespiegelt: das Muster liegt dort andersherum, deshalb ist es
    vorn und hinten gleich aufgebaut."""
    side, top = [], []
    purple, purple2, green, orange, dark = "#5a2a8c", "#46206e", "#7cff3a", "#ff7a00", "#1d0b33"
    defs = '<clipPath id="hz"><rect x="574" y="440" width="900" height="40"/></clipPath>'
    side.append(rect(0, 0, W, 520, purple))
    for m in (False, True):
        X = (lambda x: W - x) if m else (lambda x: x)
        def Q(pts):
            return [(X(x), y) for x, y in pts]
        side.append(poly(Q([(0, 0), (300, 0), (420, 200), (380, 520), (0, 520)]), green))
        side.append(poly(Q([(300, 0), (420, 200), (430, 225), (310, 25)]), orange))
        side.append(poly(Q([(420, 200), (700, 200), (740, 160), (1024, 160), (1024, 185), (750, 185), (710, 225), (430, 225)]), green))
        side.append(poly(Q([(380, 330), (560, 330), (600, 400), (380, 400)]), purple2))
        side.append(pl(Q([(600, 0), (620, 160)]), dark, 6))
        side.append(pl(Q([(380, 400), (600, 400), (640, 330), (1024, 330)]), dark, 6))
        for k in range(3):
            side.append(rect(X(470 + k * 30) - (20 if m else 0), 250, 20, 50, green))
    side.append(g(hazard(574, 440, 900, 40, 34), 'clip-path="url(#hz)"'))
    side += stroke_text("07", 880, 225, 180, "#141414", 54)
    side += stroke_text("07", 872, 217, 180, "#ffffff", 36)
    side += stroke_text("UNIT-07", 870, 40, 50, "#ffffff", 9, 0.4)
    # Draufsicht: lila mit grüner Mittelbahn, orange Kanten, Warnstreifen auf der Haube
    top.append(rect(0, 512, W, 512, purple))
    top.append(poly([(0, TC - 50), (W, TC - 30), (W, TC + 30), (0, TC + 50)], green))
    top.append(poly([(0, TC - 34), (W, TC - 18), (W, TC + 18), (0, TC + 34)], dark))
    for sgn in (1, -1):
        top.append(poly([(0, ty(sgn, 200)), (900, ty(sgn, 170)), (1000, ty(sgn, 230)), (W, ty(sgn, 230)), (W, ty(sgn, 256)), (0, ty(sgn, 256))], orange))
    top.append(g(hazard(60, TC + 90, 420, 46, 30)))
    top.append(g(hazard(60, TC - 136, 420, 46, 30)))
    return vinyl(side, top, defs)


def octa(cx, cy, w, h, out):
    top_c, left_c, right_c, bot_l, bot_r = "#eafcff", "#9fe8ff", "#56c8ff", "#2a7cff", "#1b4fc4"
    pts = {"t": (cx, cy - h), "b": (cx, cy + h), "l": (cx - w, cy), "r": (cx + w, cy), "f": (cx - w * 0.15, cy + h * 0.06)}
    out.append(poly([pts["t"], pts["l"], pts["f"]], left_c))
    out.append(poly([pts["t"], pts["f"], pts["r"]], right_c))
    out.append(poly([pts["b"], pts["l"], pts["f"]], bot_l))
    out.append(poly([pts["b"], pts["f"], pts["r"]], bot_r))
    out.append(poly([pts["t"], pts["l"], pts["b"], pts["r"]], "none", 'stroke="#ffffff" stroke-width="4"'))


def v_angel():
    side, top = [], []
    defs = lin_grad("beam", 0, 0, 0, 520, [(0, "#ffffff", 0.0), (0.5, "#bff6ff", 0.55), (1, "#ffffff", 0.0)]) + \
        rad_grad("glow", 1000, 260, 330, [(0, "#bff6ff", 0.75), (0.6, "#56c8ff", 0.18), (1, "#56c8ff", 0.0)])
    side.append(circ(1000, 260, 330, "url(#glow)"))
    side.append(rect(985, 0, 30, 520, "url(#beam)"))
    side.append(rect(400, 252, 1500, 16, "url(#beam)", 'transform="rotate(90 1150 260)" opacity="0"'))
    for k, (rx, ry, sw, op) in enumerate([(430, 120, 6, 0.9), (560, 160, 3, 0.6), (700, 205, 2, 0.4)]):
        side.append(ell(1000, 260, rx, ry, "none", -6, 'stroke="#dffbff" stroke-width="%s" stroke-opacity="%s"' % (sw, f(op))))
    for k in range(18):
        a = math.radians(k * 20 + 5)
        side.append(pl([(1000 + math.cos(a) * 180, 260 + math.sin(a) * 120), (1000 + math.cos(a) * 900, 260 + math.sin(a) * 520)],
                       "#dffbff", 2, 'stroke-opacity="0.35"'))
    octa(1000, 260, 150, 220, side)
    r = random.Random(12)
    for k in range(16):
        a = r.uniform(0, math.tau)
        d = r.uniform(260, 820)
        x, y = 1000 + math.cos(a) * d, 260 + math.sin(a) * d * 0.4
        s_ = r.uniform(12, 30)
        side.append(poly([(x, y - s_), (x + s_ * 0.6, y + s_ * 0.5), (x - s_ * 0.6, y + s_ * 0.5)], "#bff6ff", 'fill-opacity="0.8"'))
    # Draufsicht: Ringe auf dem Dach, Strahlen über die Haube
    for k, (rx, sw) in enumerate([(160, 10), (230, 4), (300, 2)]):
        top.append(ell(1180, TC, rx, rx * 0.75, "none", 0, 'stroke="#dffbff" stroke-width="%s" stroke-opacity="%s"' % (sw, f(0.9 - k * 0.25))))
    octa(1180, TC, 80, 110, top)
    for sgn in (1, -1):
        for k in range(5):
            top.append(pl([(900, ty(sgn, 40 + k * 40)), (40, ty(sgn, 60 + k * 45))], "#dffbff", 3, 'stroke-opacity="0.5"'))
    return vinyl(side, top, defs)


# --- Seit 2.36: einfarbige Flammen, ein Tribal und zwei Rennsport-Motive (alle tint) -----------------------------------
# Die Gesichter (Kitsune- und Oni-Maske, Drachenkopf, Mecha-Kopf) sind seit 2.36 raus: sie wirkten auf dem Auto billig.

SX = 0.58  # Flanke: ein Pixel in x ist auf dem Auto gut 1,7-mal so lang wie in y (4,4 m auf 2048, ~0,65 m auf 512)


def lick(x0, y0, ln, w0, amp, ph, lam, curl, fan, n=30, pw=1.5):
    """Flammenzunge nach hinten (x wächst): Welle (Amplitude amp, Wellenlänge lam, Phase ph), die zur Spitze hin
    wächst; die Spitze rollt um curl Pixel ein, fan neigt die Zunge. Breit bis kurz vor der Spitze (1 - u^pw).
    Liefert (Mittellinie, Breiten) für ribbon(). Benachbarte Zungen mit verschiedener Phase kreuzen sich: dazwischen
    bleiben die typischen Flammen-Löcher."""
    sp, wd = [], []
    for k in range(n):
        u = k / (n - 1)
        x = x0 + ln * u
        y = y0 + amp * math.sin(math.tau * (x - x0) / lam + ph) * u ** 0.6 + fan * ln * u
        y += curl * max(0.0, u - 0.7) ** 2 / (0.3 ** 2)
        sp.append((x, y))
        wd.append(w0 * (1 - u ** pw))
    wd[-1] = 0
    return sp, wd


FLAME_SIDE = [  # y0, Länge, Breite, Welle, Phase, Wellenlänge, Einrollen, Neigung
    (70, 830, 92, 39, 0.2, 570, -60, -0.03), (155, 1210, 104, 49, 1.5, 615, 70, -0.03), (240, 1445, 112, 55, 3.0, 675, -75, 0.0),
    (325, 1070, 104, 49, 0.9, 600, 70, 0.02), (410, 1290, 100, 52, 2.2, 645, -70, 0.03), (480, 765, 80, 36, 3.6, 525, 55, 0.02)]
FLAME_HOOD = [(50, 520, 78, 24, 0.4, 430, -40, 0.0), (125, 680, 84, 28, 1.8, 470, 44, 0.03), (200, 470, 74, 22, 3.1, 410, -36, 0.06)]
FLAME_HEAD = [(-30, 22), (140, 30), (230, 150), (200, 260), (230, 380), (140, 490), (-30, 498)]  # Flanke vorn: geschlossene Front


def flame_shapes(s=0):
    """Pfade der Feuerzungen: s = 0 die Flanke, s = ±1 eine Hälfte der Haube (Draufsicht)."""
    if s == 0:
        out = [ribbon(*lick(150, y0, ln, w0, amp, ph, lam, curl, fan)) for y0, ln, w0, amp, ph, lam, curl, fan in FLAME_SIDE]
        return out + [catmull(FLAME_HEAD, True)]
    out = [ribbon(*lick(60, ty(s, o), ln, w0, amp * s, ph, lam, curl * s, fan * s)) for o, ln, w0, amp, ph, lam, curl, fan in FLAME_HOOD]
    return out + [catmull([(-30, ty(s, 0)), (100, ty(s, 0)), (150, ty(s, 130)), (100, ty(s, 262)), (-30, ty(s, 262))], True)]


def v_flamelicks():
    """Feuerzungen: klassische Hot-Rod-Flammen in einer Farbe, vom vorderen Kotflügel über die Tür; auf der Haube
    von der Nase zur Scheibe."""
    side = [path(d, "#fff") for d in flame_shapes()]
    top = [path(d, "#fff") for d in flame_shapes(1) + flame_shapes(-1)]
    return vinyl(side, top)


def rot_lick(base, ang, ln, w0, amp, ph, lam, curl, sx=1.0):
    """lick() in eine Richtung gedreht (ang in Grad, 0 = nach hinten, -90 = nach oben), danach x um sx gestaucht."""
    sp, wd = lick(0, 0, ln, w0, amp, ph, lam, curl, 0.0)
    c, s_ = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    return [(base[0] + (x * c - y * s_) * sx, base[1] + x * s_ + y * c) for x, y in sp], wd


def v_inferno():
    """Inferno: Flammen schlagen vom Schweller schräg nach oben und hinten über die Türen, als führe das Auto durchs
    Feuer; auf der Haube züngeln sie von der Nase her."""
    r = random.Random(5)
    side, top = [], []
    x, i = 560, 0
    while x < 1560:
        ln = r.uniform(300, 520) * (1.15 if i % 2 else 0.85)
        sp, wd = rot_lick((x, 540), -62 + r.uniform(-6, 6), ln, r.uniform(60, 80), r.uniform(26, 36), r.uniform(0, 6.2),
                          r.uniform(260, 330), (-1 if i % 2 else 1) * r.uniform(30, 50), SX * 1.25)
        side.append(path(ribbon(sp, wd), "#fff"))
        x += r.uniform(46, 62)
        i += 1
    side.append(rect(540, 470, 1040, 60, "#fff"))

    def hood(s):
        out = [path(ribbon(*lick(60, ty(s, o), ln * 0.8, w0 * 0.9, amp * s, ph, lam, curl * s, fan * s)), "#fff")
               for o, ln, w0, amp, ph, lam, curl, fan in FLAME_HOOD]
        out.append(path(catmull([(-30, ty(s, 0)), (90, ty(s, 0)), (130, ty(s, 130)), (90, ty(s, 262)), (-30, ty(s, 262))], True), "#fff"))
        return out
    top += mirror_top(hood)
    return vinyl(side, top)


def outline_mask(mid, shapes, t):
    """Maske: nur der Umriss um die Vereinigung der Formen (t Pixel nach außen). Weißer Strich (2t) um jede Form, dann
    alle Formen schwarz darüber: übrig bleibt die äußere Hälfte der Striche, Linien im Inneren verschwinden."""
    ds = "".join('<path d="%s"/>' % d for d in shapes)
    return ('<mask id="%s" maskUnits="userSpaceOnUse" x="-50" y="-50" width="%d" height="%d"><g fill="none" stroke="#fff" '
            'stroke-width="%s" stroke-linejoin="miter" stroke-miterlimit="12">%s</g><g fill="#000">%s</g></mask>') % (
        mid, W + 100, H + 100, f(2 * t), ds, ds)


def v_ghostflames():
    """Geisterflammen: die Feuerzungen nur als Umriss, innen ein Hauch Farbe (wie gepinselte Ghost Flames). Am
    schönsten Ton in Ton: Schwarz auf Grau, Weiß auf Silber."""
    side_d = flame_shapes()
    top_d = flame_shapes(1) + flame_shapes(-1)
    defs = outline_mask("gs", side_d, 14) + outline_mask("gt", top_d, 11)
    side = ['<g opacity="0.34" fill="#fff">%s</g>' % "".join('<path d="%s"/>' % d for d in side_d),
            rect(-50, -50, W + 100, 620, "#fff", 'mask="url(#gs)"')]
    top = ['<g opacity="0.34" fill="#fff">%s</g>' % "".join('<path d="%s"/>' % d for d in top_d),
           rect(-50, 500, W + 100, 600, "#fff", 'mask="url(#gt)"')]
    return vinyl(side, top, defs)


def on_spine(spine, t):
    k = min(int(t * (len(spine) - 1)), len(spine) - 2)
    return lerp2(spine[k], spine[k + 1], t * (len(spine) - 1) - k)


def v_updraft():
    """Aufwind: Tribal, das hinter dem Vorderrad unten ansetzt und über die Tür zum Heck hin aufsteigt; lange, gebogene
    Klingen laufen mit dem Schwung nach hinten oben aus. Auf der Haube zwei Schwünge von der Scheibe zur Nase."""
    side, top = [], []
    spine = [(600, 470), (820, 440), (1040, 372), (1250, 272), (1450, 160), (1650, 92), (1850, 58), (2040, 38)]
    side.append(path(ribbon(spine, [40, 120, 140, 120, 90, 60, 32, 0]), "#fff"))
    for t, ang, ln, w, bend in [(0.08, -40, 520, 100, -150), (0.22, -36, 540, 96, -150), (0.37, -32, 470, 84, -130),
                                (0.52, -26, 360, 66, -100), (0.16, 6, 420, 70, 90), (0.32, 2, 330, 56, 70)]:
        side.append(poly(blade(on_spine(spine, t), w, ang, ln, bend), "#fff"))

    def hood(s):
        sp = [(730, ty(s, 236)), (560, ty(s, 190)), (360, ty(s, 120)), (170, ty(s, 56)), (30, ty(s, 18))]
        out = [path(ribbon(sp, [40, 96, 84, 46, 0]), "#fff")]
        for t, ang, ln, w, bend in [(0.12, 186, 330, 70, 110), (0.32, 190, 280, 60, 90)]:
            out.append(poly(blade(on_spine(sp, t), w, ang * s, ln, bend * s), "#fff"))
        return out
    top += mirror_top(hood)
    return vinyl(side, top)


# Blockziffern der Startnummer (Feld 0..1 x 0..1, je ein Umriss ohne Löcher)
DIGITS = {
    "4": [(0, 0), (0.2, 0), (0.2, 0.5), (0.62, 0.5), (0.62, 0), (0.82, 0), (0.82, 0.5), (1, 0.5), (1, 0.68), (0.82, 0.68),
          (0.82, 1), (0.62, 1), (0.62, 0.68), (0, 0.68)],
    "2": [(0.1, 0), (0.9, 0), (1, 0.1), (1, 0.59), (0.2, 0.59), (0.2, 0.82), (1, 0.82), (1, 1), (0, 1), (0, 0.51), (0.1, 0.41),
          (0.8, 0.41), (0.8, 0.18), (0, 0.18), (0, 0.1)],
}


def digits_d(text, x, y, h, w, gap):
    """Umrisse der Ziffern als Pfad-Teile (mit evenodd in einer Fläche werden sie ausgestanzt)."""
    out = []
    for ch in text:
        out.append("M" + " L".join("%s %s" % (f(x + px * w), f(y + py * h)) for px, py in DIGITS[ch]) + " Z")
        x += w + gap
    return " ".join(out)


def circle_d(cx, cy, r):
    return "M%s %s A%s %s 0 1 0 %s %s A%s %s 0 1 0 %s %s Z" % (f(cx - r), f(cy), f(r), f(r), f(cx + r), f(cy), f(r), f(r), f(cx - r), f(cy))


def v_racenumber():
    """Startnummer: runde Startnummer-Fläche mittig auf der Tür, die 42 ausgestanzt (dort scheint der Lack durch),
    Doppellinie unter der Fensterlinie, feine Linie am Schweller; oben ein breiter Streifen links der Mitte mit
    Begleitlinien. Mit Schrift, also rechts nicht gespiegelt: alles ist vorn und hinten gleich aufgebaut."""
    side, top = [], []
    cx, cy, r = 1024, 262, 196
    d = circle_d(cx, cy, r) + " " + digits_d("42", cx - 132, cy - 105, 210, 118, 28)
    # Kreis und Ziffern in Auto-Maß, dann in x gestaucht: auf dem Auto ein Kreis
    side.append('<g transform="translate(%s %s) scale(%s 1) translate(%s %s)">%s</g>' % (
        f(cx), f(cy), f(SX), f(-cx), f(-cy), path(d, "#fff", extra='fill-rule="evenodd"')))
    side += [rect(-10, 22, W + 20, 30, "#fff"), rect(-10, 64, W + 20, 10, "#fff"), rect(-10, 452, W + 20, 18, "#fff")]
    for a, b in [(ty(-1, 26), ty(-1, 116)), (ty(-1, 132), ty(-1, 146)), (ty(1, 10), ty(1, 18))]:
        top.append(rect(-10, min(a, b), W + 20, abs(b - a), "#fff"))
    return vinyl(side, top)


def v_checkstripe():
    """Karo-Streifen: Band unten über die Tür, das nach hinten in zwei Reihen Karos ausläuft (die Karos werden seltener
    und kleiner), darüber eine feine Linie; oben zwei Streifen über Haube, Dach und Heck, die vorn auf der Haube als
    Karoblock beginnen."""
    r = random.Random(14)
    side, top = [], []
    y0, y1 = 296, 404
    side.append(rect(540, y0, 520, y1 - y0, "#fff"))
    side.append(rect(540, y0 - 28, 700, 10, "#fff"))
    sq_h = (y1 - y0) / 2.0
    sq_w = sq_h * SX
    x, col = 1060.0, 0
    while x < 1700:
        t = (x - 1060) / 640.0
        for row in range(2):
            if (col + row) % 2 or (t > 0.25 and r.random() < (t - 0.25) * 1.3):
                continue
            k = 1.0 if t < 0.3 else max(0.45, 1.0 - (t - 0.3) * 0.9)
            side.append(rect(x + sq_w * (1 - k) / 2, y0 + row * sq_h + sq_h * (1 - k) / 2, sq_w * k, sq_h * k, "#fff"))
        x += sq_w
        col += 1
    q = 32.0  # Karo quer (y); längs gestreckt, denn in der Draufsicht ist ein Pixel quer gut 1,66-mal so lang
    ql = q * 1.66
    rows = int(round(270 / ql))
    for i in range(rows):
        for j in range(4):
            if (i + j) % 2 == 0:
                top.append(rect(i * ql, TC - 2 * q + j * q, ql, q, "#fff"))
    for sgn in (1, -1):
        top.append(rect(rows * ql, min(ty(sgn, 14), ty(sgn, 64)), W + 10 - rows * ql, 50, "#fff"))
    return vinyl(side, top)


VINYLS = {
    "speedlines": v_speedlines,
    "tribal": v_tribal,
    "splitter": v_splitter,
    "tiger": v_tiger,
    "checker": v_checker,
    "flames": v_flames,
    "camo": v_camo,
    "bolts": v_bolts,
    "sakura": v_sakura,
    "wave": v_wave,
    "graffiti": v_graffiti,
    "hex": v_hex,
    "circuit": v_circuit,
    "splatter": v_splatter,
    "sunrays": v_sunrays,
    "glitch": v_glitch,
    "prism": v_prism,
    "koi": v_koi,
    "wings": v_wings,
    "unit07": v_unit07,
    "angel": v_angel,
    "flamelicks": v_flamelicks,
    "inferno": v_inferno,
    "ghostflames": v_ghostflames,
    "updraft": v_updraft,
    "racenumber": v_racenumber,
    "checkstripe": v_checkstripe,
}


def main():
    only = sys.argv[1:]
    os.makedirs(VDIR, exist_ok=True)
    for name, fn in VINYLS.items():
        if only and name not in only:
            continue
        with open(os.path.join(VDIR, name + ".svg"), "w", encoding="utf-8") as fh:
            fh.write(fn())
        print("vinyl", name)



if __name__ == "__main__":
    main()
