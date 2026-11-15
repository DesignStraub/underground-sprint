#!/usr/bin/env python3
"""Bildmotive der Fake-Werbeplakate (seit 2.34) als SVG, 256 x 256, transparent. Reines Python.

    python3 tools/poster_gen.py

Schreibt tools/poster_icons/<id>.svg. Die Plakate selbst (Schrift, Farben, Aufteilung) setzt tools/posters.gd in Godot
mit den Schriften des Spiels zu assets/posters/posters.png zusammen. Alle Marken und Texte sind ausgedacht.
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from vinyl_gen import P, poly, pl, path, circ, ell, rect, catmull, ribbon, T, sym  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "poster_icons")
K = "#141414"


def svg(items):
    return '<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">%s</svg>\n' % "".join(items)


def i_phone():
    out = [rect(78, 30, 100, 196, K, 'rx="18"'), rect(88, 50, 80, 150, "#f4f4f4", 'rx="4"'), circ(128, 212, 7, "#555")]
    for k in range(4):
        h = 16 + k * 14
        out.append(rect(100 + k * 15, 120 - h, 10, h, "#bbbbbb"))
    out.append(pl([(96, 64), (162, 130)], "#e0201c", 10))
    out.append(pl([(162, 64), (96, 130)], "#e0201c", 10))
    out.append(rect(100, 150, 56, 8, "#cccccc", 'rx="4"'))
    out.append(rect(100, 166, 40, 8, "#cccccc", 'rx="4"'))
    return svg(out)


def snail(cx, cy, s, shell="#d9a441", body="#c7d36b", extra=None):
    out = []
    bodyp = [(-110, 40), (-90, 10), (40, 12), (90, 0), (110, -30), (122, -26), (118, 20), (90, 46), (-100, 52)]
    out.append(path(catmull(T(bodyp, cx, cy, s), True, 0.8), body, K, 5))
    for dx in (100, 114):
        out.append(pl(T([(dx, -24), (dx + 6, -70)], cx, cy, s), K, 5))
        out.append(circ(cx + (dx + 6) * s, cy - 72 * s, 7 * s, K))
    out.append(circ(cx - 10 * s, cy - 40 * s, 66 * s, shell, 'stroke="%s" stroke-width="5"' % K))
    sp = []
    for k in range(60):
        a = k * 0.32
        r = 60 - k * 0.95
        sp.append((cx - 10 * s + math.cos(a) * r * s, cy - 40 * s + math.sin(a) * r * s))
    out.append(pl(sp, K, 4))
    if extra:
        out += extra
    return out


def i_snail_cable():
    out = snail(118, 170, 0.95)
    # Kabeltrommel auf dem Haus
    out.append(circ(118, 90, 26, "#ff8a00", 'stroke="%s" stroke-width="5"' % K))
    out.append(circ(118, 90, 8, K))
    out.append(path(catmull([(144, 96), (190, 120), (210, 170), (236, 200)], False), "none", "#ff8a00", 7))
    return svg(out)


def i_doener():
    out = [rect(122, 20, 12, 220, "#9e9e9e")]
    spit = [(80, 40), (176, 40), (186, 90), (172, 150), (150, 196), (106, 196), (84, 150), (70, 90)]
    out.append(path(catmull(spit, True, 0.6), "#a0522d", K, 5))
    for k in range(6):
        y = 52 + k * 24
        out.append(pl([(86 + k * 2, y), (170 - k * 2, y + 6)], "#7a3c1c", 5))
    out.append(rect(90, 196, 76, 14, "#9e9e9e", 'stroke="%s" stroke-width="4"' % K))
    return svg(out)


def i_sandal():
    out = []
    sock = [(70, 40), (130, 40), (134, 150), (200, 176), (206, 210), (70, 212)]
    out.append(path(catmull(sock, True, 0.5), "#fafafa", K, 5))
    out.append(rect(70, 52, 64, 10, "#3f6ad8"))
    out.append(rect(70, 70, 64, 6, "#d83f3f"))
    out.append(rect(50, 212, 176, 22, "#6d4c41", 'rx="10" stroke="%s" stroke-width="5"' % K))
    for x in (90, 150):
        out.append(rect(x, 170, 22, 48, "#8d6e63", 'stroke="%s" stroke-width="4"' % K))
    return svg(out)


def i_doc():
    out = [rect(64, 24, 128, 172, "#fafafa", 'stroke="%s" stroke-width="5"' % K)]
    for k in range(8):
        out.append(rect(80, 46 + k * 16, 96 - (k % 3) * 18, 6, "#9e9e9e"))
    out.append(rect(110, 170, 70, 4, K))
    return svg(out)


def i_gnome():
    out = []
    out.append(poly([(128, 16), (180, 116), (76, 116)], "#d32f2f", 'stroke="%s" stroke-width="5"' % K))
    out.append(circ(128, 128, 40, "#ffccbc", 'stroke="%s" stroke-width="5"' % K))
    beard = [(84, 128), (172, 128), (160, 190), (128, 214), (96, 190)]
    out.append(path(catmull(beard, True, 0.7), "#fafafa", K, 5))
    out.append(circ(128, 134, 10, "#ef9a9a", 'stroke="%s" stroke-width="3"' % K))
    out.append(circ(112, 118, 5, K))
    out.append(circ(144, 118, 5, K))
    out.append(rect(92, 196, 72, 40, "#1976d2", 'rx="10" stroke="%s" stroke-width="5"' % K))
    return svg(out)


def i_snail_racer():
    num = [rect(96, 112, 44, 30, "#ffffff", 'stroke="%s" stroke-width="4"' % K)]
    out = snail(128, 176, 0.95, shell="#ffd600", body="#9ccc65")
    out += num
    # Rennhelm-Streifen auf dem Haus
    out.append(path("M70 136 Q118 60 168 120", "none", "#e53935", 10))
    return svg(out)


def i_cake():
    out = [ell(128, 210, 96, 18, "#fafafa", 0, 'stroke="%s" stroke-width="5"' % K)]
    out.append(poly([(60, 196), (196, 196), (196, 150), (60, 120)], "#ffe0b2", 'stroke="%s" stroke-width="5"' % K))
    out.append(poly([(60, 120), (196, 150), (196, 138), (60, 104)], "#f8bbd0", 'stroke="%s" stroke-width="5"' % K))
    out.append(circ(176, 128, 14, "#e53935", 'stroke="%s" stroke-width="4"' % K))
    out.append(path("M150 100 Q164 72 186 100 Q170 92 150 100", "#fafafa", K, 4))
    # Tasse
    out.append(rect(30, 40, 70, 60, "#fafafa", 'rx="8" stroke="%s" stroke-width="5"' % K))
    out.append(circ(104, 66, 14, "none", 'stroke="%s" stroke-width="7"' % K))
    out.append(rect(36, 46, 58, 10, "#6d4c41"))
    for x in (50, 74):
        out.append(path("M%s 30 Q%s 18 %s 6" % (x, x + 10, x), "none", "#9e9e9e", 4))
    return svg(out)


def i_train():
    out = [rect(56, 30, 144, 170, "#eceff1", 'rx="30" stroke="%s" stroke-width="6"' % K)]
    out.append(rect(74, 52, 108, 62, "#90caf9", 'rx="10" stroke="%s" stroke-width="5"' % K))
    out.append(rect(56, 130, 144, 14, "#00897b"))
    out.append(circ(90, 168, 12, "#fff59d", 'stroke="%s" stroke-width="4"' % K))
    out.append(circ(166, 168, 12, "#fff59d", 'stroke="%s" stroke-width="4"' % K))
    out.append(pl([(70, 200), (40, 236)], K, 8))
    out.append(pl([(186, 200), (216, 236)], K, 8))
    # Zzz
    for k, (x, y, s) in enumerate([(196, 40, 18), (218, 18, 13)]):
        out.append(pl([(x, y), (x + s, y), (x, y + s), (x + s, y + s)], K, 4))
    return svg(out)


def i_wing():
    out = []
    out.append(poly([(20, 92), (236, 70), (240, 108), (24, 122)], "#212121", 'stroke="#76ff03" stroke-width="5"'))
    for x in (40, 216):
        out.append(poly([(x - 14, 60), (x + 14, 60), (x + 14, 150), (x - 14, 150)], "#212121", 'stroke="#76ff03" stroke-width="4"'))
    for x in (90, 166):
        out.append(rect(x - 8, 118, 16, 80, "#424242", 'stroke="#76ff03" stroke-width="3"'))
    out.append(rect(50, 196, 156, 18, "#424242", 'stroke="#76ff03" stroke-width="3"'))
    return svg(out)


def i_bins():
    out = []
    for k, c in enumerate(["#fdd835", "#1e88e5", "#6d4c41", "#616161"]):
        x = 12 + k * 60
        out.append(rect(x, 80, 52, 140, c, 'rx="6" stroke="%s" stroke-width="5"' % K))
        out.append(rect(x - 4, 66, 60, 18, c, 'rx="4" stroke="%s" stroke-width="5"' % K))
        out.append(circ(x + 12, 224, 9, K))
        out.append(circ(x + 40, 224, 9, K))
    return svg(out)


def i_coins():
    out = []
    for k, (x, y) in enumerate([(70, 200), (70, 180), (70, 160), (70, 140), (150, 200), (150, 180), (190, 120)]):
        out.append(ell(x + 20, y, 46, 16, "#ffca28", 0, 'stroke="%s" stroke-width="5"' % K))
    out.append(circ(190, 80, 38, "#ffca28", 'stroke="%s" stroke-width="5"' % K))
    out.append(rect(182, 60, 16, 40, K, 'rx="3"'))
    return svg(out)


ICONS = {"phone": i_phone, "snail_cable": i_snail_cable, "doener": i_doener, "sandal": i_sandal, "doc": i_doc,
         "gnome": i_gnome, "snail_racer": i_snail_racer, "cake": i_cake, "train": i_train, "wing": i_wing, "bins": i_bins,
         "coins": i_coins}


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, fn in ICONS.items():
        with open(os.path.join(OUT, name + ".svg"), "w", encoding="utf-8") as fh:
            fh.write(fn())
        print("icon", name)


if __name__ == "__main__":
    main()
