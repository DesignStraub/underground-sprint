#!/usr/bin/env python3
"""Echtes Straßennetz einer Stadt (© OpenStreetMap-Mitwirkende, ODbL) als Nebenstraßen der freien Fahrt (seit 2.52).

Liest einen Overpass-Export der Straßen um die Strecke (<stadt>_streets.json, Abfrage siehe QUERY) und die Mittellinie
der Strecke aus scripts/city_data.gd, und schreibt scripts/city_net.gd: je Stadt eine Liste von Straßen mit Name,
Klasse, Punkten (Streckenkoordinaten wie city_data: x = Osten, z = Süden, Ursprung = origin) und Enden.

Ablauf:
- Straßen der Strecke selbst (näher als MAIN_CUT an der Mittellinie) fallen weg; wo eine Straße die Strecke kreuzt
  oder an ihr endet, wird ihr Ende eine Einmündung in die Hauptstraße ("main").
- nur bis REACH von der Strecke (dort stehen die echten Häuser), dahinter abgeschnitten;
- Sackgassen werden so lange gekappt, bis jede Straße an beiden Enden irgendwo anschließt (Hauptstraße oder andere
  Straße): keine Stummel, die nirgendwohin führen;
- Wege, die an einer Kreuzung geradeaus weitergehen, werden eine Straße (Kreuzungen offen, T-Einmündungen als Ende
  an der anderen Straße);
- Ecken abgerundet (CORNER_R), alle STEP m ein Punkt.

    python3 tools/osm_net.py <ordner-mit-overpass-json> [stadt ...]
"""
import json
import math
import os
import random
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "scripts", "city_net.gd")
CITY_DATA = os.path.join(ROOT, "scripts", "city_data.gd")

QUERY = ('[out:json][timeout:90];way["highway"~"^(primary|secondary|tertiary|unclassified|residential|living_street|'
         'pedestrian|service|primary_link|secondary_link|tertiary_link)$"](süd,west,nord,ost);out geom;')

MAIN_CUT = 19.0  # so nah an der Mittellinie gehört alles zur Hauptstraße (9 m Fahrbahn, 5 m Gehweg, Rand)
REACH = 300.0  # so weit von der Strecke reicht das Netz (Häuser gibt es bis 330 m)
STEP = 2.5
CORNER_R = 16.0  # seit 2.52 (vorher 11): weniger eckige Kurven in den Gassen
MIN_LEN = 24.0
LOOP_MIN = 140.0  # kürzere Schleifen an dieselbe Straße fallen weg
BLOCK_PAD = 9.0  # Abstand der Straßenmitte zu Sperrflächen
DUAL_GAP = 28.0  # Richtungsfahrbahnen höchstens so weit auseinander
DENSE = 4.0  # Wege dazwischen alle so viele Meter ein Knoten (sonst übersieht man Kreuzungen mit der Strecke)  # kürzere Straßen (zwischen zwei Enden) lohnen nicht
MOUTH_MIN_ANG = 38.0  # flacher darf eine Straße nicht in die Hauptstraße münden (Grad)
CLS = {"primary": "breit", "secondary": "strasse", "tertiary": "strasse", "unclassified": "strasse",
       "residential": "strasse", "primary_link": "strasse", "secondary_link": "strasse", "tertiary_link": "strasse",
       "living_street": "gasse", "pedestrian": "gasse"}
CITIES = ["aachen", "koeln"]
REACH_D = 250.0  # entworfene Städte: so weit von der Strecke
# Entworfene Städte (track_design-Layout statt OSM): Raster und Straßennamen
DESIGN = {
    "koeln": {
        "seed": 51, "spacing": (84.0, 74.0), "angle": 0.21, "warp": 24.0, "jitter": 8.0, "drop": 0.15, "diag": 0.07,
        "arterial": 4, "main_band": 30.0, "gasse_x": -330.0, "west_of": -52.0,  # Rhein: nur das linke Ufer
        "rows": ["Hohe Straße", "Schildergasse", "Breite Straße", "Ehrenstraße", "Zülpicher Straße", "Aachener Straße",
                 "Venloer Straße", "Severinstraße", "Apostelnstraße", "Mittelstraße", "Friesenstraße", "Komödienstraße",
                 "Gereonstraße", "Hahnenstraße", "Richmodstraße", "Glockengasse", "Brückenstraße", "Sternengasse"],
        "cols": ["Cäcilienstraße", "Weyerstraße", "Pfeilstraße", "Benesisstraße", "Lindenstraße", "Roonstraße",
                 "Kyffhäuserstraße", "Engelbertstraße", "Händelstraße", "Brüsseler Straße", "Bismarckstraße",
                 "Moltkestraße", "Lütticher Straße", "Maastrichter Straße", "Limburger Straße", "Flandrische Straße",
                 "Antwerpener Straße", "Genter Straße", "Lübecker Straße", "Luxemburger Straße", "Bonner Straße",
                 "Vorgebirgstraße", "Eifelstraße", "Volksgartenstraße"],
    },
}


class Proj:
    def __init__(self, lat0, lon0):
        self.lat0, self.lon0 = lat0, lon0
        self.kx = 111320.0 * math.cos(math.radians(lat0))

    def __call__(self, lat, lon):
        return ((lon - self.lon0) * self.kx, -(lat - self.lat0) * 110574.0)


def city_block(city):
    src = open(CITY_DATA, encoding="utf-8").read()
    i = src.index('\t"%s": {' % city)
    blk = src[i:]
    def nums(key):
        k = blk.index('"%s": [' % key)
        e = blk.index("]", k)
        return [float(v) for v in re.findall(r"-?\d+(?:\.\d+)?", blk[k + len(key) + 4:e])]
    org = nums("origin")
    pts = nums("points")
    loop = blk[:blk.index('"length"')].find('"loop": true') >= 0
    return org, [(pts[k], pts[k + 1]) for k in range(0, len(pts), 2)], loop


def densify(line, step):
    out = [line[0]]
    for a, b in zip(line, line[1:]):
        n = max(1, int(math.dist(a, b) / step))
        for j in range(1, n + 1):
            t = j / n
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


class Near:
    """Abstand zur Mittellinie (Raster 20 m)"""
    def __init__(self, pts):
        self.g = {}
        for k, q in enumerate(pts):
            self.g.setdefault((int(q[0] // 20), int(q[1] // 20)), []).append(k)
        self.pts = pts

    def __call__(self, q, rad=60.0):
        gx, gz = int(q[0] // 20), int(q[1] // 20)
        n = int(rad // 20) + 1
        best, bk = 1e9, -1
        for i in range(gx - n, gx + n + 1):
            for j in range(gz - n, gz + n + 1):
                for k in self.g.get((i, j), []):
                    d = math.dist(self.pts[k], q)
                    if d < best:
                        best, bk = d, k
        return best, bk


def far_dist(near, q):
    d, _ = near(q, 60.0)
    if d < 1e8:
        return d
    best = min(math.dist(p, q) for p in near.pts[::4])
    return best


def fillet(pts, r, step):
    """Polygonzug mit gerundeten Ecken, gleichmäßig neu abgetastet (wie street_net._fillet)"""
    if len(pts) < 3:
        return resample(pts, step)
    dense = [pts[0]]
    for i in range(1, len(pts) - 1):
        a, b, c = pts[i - 1], pts[i], pts[i + 1]
        u = (b[0] - a[0], b[1] - a[1])
        v = (c[0] - b[0], c[1] - b[1])
        lu, lv = math.hypot(*u), math.hypot(*v)
        if lu < 0.1 or lv < 0.1:
            continue
        u = (u[0] / lu, u[1] / lu)
        v = (v[0] / lv, v[1] / lv)
        phi = math.atan2(u[0] * v[1] - u[1] * v[0], u[0] * v[0] + u[1] * v[1])
        if abs(phi) < 0.05:
            dense.append(b)
            continue
        t = r * math.tan(abs(phi) / 2)
        tmax = min(lu * (0.98 if i == 1 else 0.49), lv * (0.98 if i == len(pts) - 2 else 0.49))
        rr = r
        if t > tmax:
            t = tmax
            rr = t / math.tan(abs(phi) / 2)
        ts = (b[0] - u[0] * t, b[1] - u[1] * t)
        sg = 1.0 if phi > 0 else -1.0
        nrm = (-u[1] * sg, u[0] * sg)
        ctr = (ts[0] + nrm[0] * rr, ts[1] + nrm[1] * rr)
        n = max(3, int(abs(phi) * rr / 2))
        for k in range(n + 1):
            ang = phi * k / n
            dx, dz = ts[0] - ctr[0], ts[1] - ctr[1]
            ca, sa = math.cos(ang), math.sin(ang)
            dense.append((ctr[0] + dx * ca - dz * sa, ctr[1] + dx * sa + dz * ca))
    dense.append(pts[-1])
    return resample(dense, step)


def resample(line, step):
    out = [line[0]]
    acc = 0.0
    for a, b in zip(line, line[1:]):
        sl = math.dist(a, b)
        if sl < 1e-6:
            continue
        pos = step - acc
        while pos <= sl:
            t = pos / sl
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
            pos += step
        acc = sl - (pos - step)
    if math.dist(out[-1], line[-1]) > 0.3:
        out.append(line[-1])
    return out


def simplify(line, tol=1.2):
    """Douglas-Peucker: kleine Zacken der OSM-Linie weg, damit die Rundung echte Ecken trifft"""
    if len(line) < 3:
        return line
    if math.dist(line[0], line[-1]) < 1.0 and len(line) > 3:
        # geschlossener Ring (Kreisverkehr): am weitesten entfernten Punkt teilen, sonst fiele er zu einem Punkt zusammen
        k = max(range(len(line)), key=lambda i: math.dist(line[0], line[i]))
        return simplify(line[:k + 1], tol)[:-1] + simplify(line[k:], tol)
    a, b = line[0], line[-1]
    ab = (b[0] - a[0], b[1] - a[1])
    lab = math.hypot(*ab) or 1e-6
    best, bi = 0.0, 0
    for i in range(1, len(line) - 1):
        q = line[i]
        d = abs(ab[0] * (q[1] - a[1]) - ab[1] * (q[0] - a[0])) / lab
        if d > best:
            best, bi = d, i
    if best < tol:
        return [a, b]
    return simplify(line[:bi + 1], tol)[:-1] + simplify(line[bi:], tol)


def seg_dist(q, a, b):
    ab = (b[0] - a[0], b[1] - a[1])
    l2 = ab[0] * ab[0] + ab[1] * ab[1] or 1e-9
    t = max(0.0, min(1.0, ((q[0] - a[0]) * ab[0] + (q[1] - a[1]) * ab[1]) / l2))
    return math.dist(q, (a[0] + ab[0] * t, a[1] + ab[1] * t))


def add_way(ways, fake, node_ids, geo, name, cls, oneway=False):
    """Weg mit Zwischenknoten alle DENSE m (negative IDs) anlegen"""
    nodes, dgeo = [node_ids[0]], [geo[0]]
    for k in range(1, len(geo)):
        a, b = geo[k - 1], geo[k]
        n = int(math.dist(a, b) / DENSE)
        for j in range(1, n + 1):
            tt = j / (n + 1)
            fake[0] -= 1
            nodes.append(fake[0])
            dgeo.append((a[0] + (b[0] - a[0]) * tt, a[1] + (b[1] - a[1]) * tt))
        nodes.append(node_ids[k])
        dgeo.append(b)
    ways.append({"nodes": nodes, "geo": dgeo, "name": name, "cls": cls, "oneway": oneway})


def osm_ways(folder, city, ways, fake):
    org, _, _ = city_block(city)
    proj = Proj(org[0], org[1])
    data = json.load(open(os.path.join(folder, city + "_streets.json"), encoding="utf-8"))
    # ohne Zufahrten/Parkplätze: "service" nur mit Namen
    for e in data["elements"]:
        t = e.get("tags", {})
        hw = t.get("highway", "")
        if e["type"] != "way" or hw not in CLS and hw != "service":
            continue
        if hw == "service" and ("name" not in t or t.get("service") in ("parking_aisle", "driveway")):
            continue
        if t.get("area") == "yes" or t.get("tunnel") in ("yes", "building_passage") or t.get("bridge") == "yes" \
                or t.get("access") in ("private", "no") or t.get("layer", "0") not in ("0", ""):
            continue
        geo = [proj(g["lat"], g["lon"]) for g in e["geometry"]]
        add_way(ways, fake, e["nodes"], geo, t.get("name", ""), CLS.get(hw, "gasse"), t.get("oneway") == "yes")
    merge_duals(ways)


def merge_duals(ways):
    """Richtungsfahrbahnen (zwei Einbahn-Wege gleichen Namens nebeneinander): nur die längere bleibt, als Straße in
    beide Richtungen. Was an der anderen hing (Seitenstraßen), mündet am nächsten Knoten der bleibenden ein."""
    order = sorted(range(len(ways)), key=lambda i: -len(ways[i]["nodes"]))
    kept, drop = [], {}
    for i in order:
        w = ways[i]
        if w.get("oneway") and w["name"]:
            for k in kept:
                w2 = ways[k]
                if not w2.get("oneway") or w2["name"] != w["name"]:
                    continue
                g2 = w2["geo"]
                close = sum(1 for q in w["geo"] if min(math.dist(q, x) for x in g2) < DUAL_GAP)
                if close >= 0.7 * len(w["geo"]):
                    drop[i] = k
                    break
            if i in drop:
                continue
        kept.append(i)
    alias = {}  # Knoten der weggefallenen Fahrbahn -> nächster Knoten der bleibenden
    for i, k in drop.items():
        w, w2 = ways[i], ways[k]
        for n, q in zip(w["nodes"], w["geo"]):
            j = min(range(len(w2["geo"])), key=lambda m: math.dist(q, w2["geo"][m]))
            alias[n] = (w2["nodes"][j], w2["geo"][j])
    out = []
    for i, w in enumerate(ways):
        if i in drop:
            continue
        if any(n in alias for n in w["nodes"]):
            w["geo"] = [alias[n][1] if n in alias else q for n, q in zip(w["nodes"], w["geo"])]
            w["nodes"] = [alias[n][0] if n in alias else n for n in w["nodes"]]
        out.append(w)
    ways[:] = out



def design_ways(cfg, main, ways, fake):
    """Entworfene Städte: unregelmäßiges Raster (gedreht, verbogen, verschoben, einzelne Stücke fehlen, ein paar
    Diagonalen), Namen je Rasterlinie; was zu weit draußen, im Fluss oder in Sperrflächen liegt, kappt build()"""
    rng = random.Random(cfg["seed"])
    sx, sz = cfg["spacing"]
    ca, sa = math.cos(cfg["angle"]), math.sin(cfg["angle"])
    xs = [q[0] for q in main]
    zs = [q[1] for q in main]
    pad = REACH_D + 120.0
    lo = (min(xs) - pad, min(zs) - pad)
    hi = (max(xs) + pad, max(zs) + pad)
    cx, cz = (lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2
    ext = max(hi[0] - lo[0], hi[1] - lo[1]) * 0.75
    ni, nj = int(ext / sx) + 1, int(ext / sz) + 1
    w = cfg["warp"]
    grid = {}
    for i in range(-ni, ni + 1):
        for j in range(-nj, nj + 1):
            u, v = i * sx, j * sz
            x = cx + u * ca - v * sa
            z = cz + u * sa + v * ca
            x += w * math.sin(z * 0.0105 + 1.3) + w * 0.5 * math.sin(z * 0.031 + x * 0.004)
            z += w * math.sin(x * 0.0125 + 0.4) + w * 0.5 * math.sin(x * 0.027 - z * 0.005)
            x += rng.uniform(-cfg["jitter"], cfg["jitter"])
            z += rng.uniform(-cfg["jitter"], cfg["jitter"])
            if lo[0] <= x <= hi[0] and lo[1] <= z <= hi[1]:
                grid[(i, j)] = (len(grid) + 1, (x, z))
    rows, cols = cfg["rows"], cfg["cols"]
    def cls_for(i, j, horiz, q):
        k = j if horiz else i
        if k % cfg["arterial"] == 0:
            return "breit" if k % (cfg["arterial"] * 2) == 0 and q[0] > cfg["gasse_x"] else "strasse"
        return "gasse" if q[0] < cfg["gasse_x"] and rng.random() < 0.6 else "strasse"
    for (i, j), (nid, q) in grid.items():
        for di, dj, horiz in ((1, 0, True), (0, 1, False)):
            o = grid.get((i + di, j + dj))
            if o is None or rng.random() < cfg["drop"]:
                continue
            name = rows[j % len(rows)] if horiz else cols[i % len(cols)]
            mid = ((q[0] + o[1][0]) / 2, (q[1] + o[1][1]) / 2)
            add_way(ways, fake, [nid, o[0]], [q, o[1]], name, cls_for(i, j, horiz, mid))
        o = grid.get((i + 1, j + 1))
        if o is not None and rng.random() < cfg["diag"]:
            add_way(ways, fake, [nid, o[0]], [q, o[1]], "", "gasse")


def build(folder, city):
    cfg = DESIGN.get(city)
    main_cut = cfg["main_band"] if cfg else MAIN_CUT
    reach = REACH_D if cfg else REACH
    blocked = lambda q: False
    main = None
    nomouth = []
    bp = os.path.join(folder, city + "_blocks.json")
    if os.path.exists(bp):
        # Sperrflächen aus dem Spiel (tools/net_blocks.gd): Korridore der Ausfahrten (nach hinten bis zur Hauptstraße
        # verlängert), Wahrzeichen, Hügel; die genaue Mittellinie und wo nichts einmünden darf
        blk = json.load(open(bp, encoding="utf-8"))
        main = [tuple(q) for q in blk["main"]]
        nomouth = blk.get("nomouth", [])
        caps = []
        for c in blk["caps"]:
            a, b, r = (c[0], c[1]), (c[2], c[3]), c[4]
            dl = math.dist(a, b) or 1.0
            a = (a[0] - (b[0] - a[0]) / dl * 70.0, a[1] - (b[1] - a[1]) / dl * 70.0)
            caps.append((a, b, r + BLOCK_PAD))
        circ = [((c[0], c[1]), c[2] + BLOCK_PAD) for c in blk["circles"]]
        west = cfg.get("west_of", 1e9) if cfg else 1e9
        blocked = lambda q: q[0] > west or any(seg_dist(q, a, b) < r for a, b, r in caps) or any(math.dist(q, c) < r for c, r in circ)
    elif cfg:
        sys.exit("entworfene Stadt braucht %s (tools/net_blocks.gd)" % bp)
    else:
        print("  (keine Sperrflächen: %s fehlt)" % bp)
        _, ctrl, loop = city_block(city)
        main = densify(ctrl + ([ctrl[0]] if loop else []), 2.0)
    near = Near(main)
    ways = []
    fake = [0]  # Zwischenknoten: negative IDs
    if cfg:
        design_ways(cfg, main, ways, fake)
    else:
        osm_ways(folder, city, ways, fake)
    pos = {}
    for w in ways:
        for n, q in zip(w["nodes"], w["geo"]):
            pos[n] = q
    # Zustand je Knoten: "M" (gehört zur Hauptstraße), "F" (zu weit draußen), "" (Netz)
    state = {}
    for n, q in pos.items():
        d = far_dist(near, q)
        st = "M" if d < main_cut else ("F" if d > reach or blocked(q) else "")
        if st != "F" and d < main_cut + 14.0 and nomouth:
            _, mk = near(q, 60.0)
            if mk >= 0 and nomouth[mk]:
                st = "F"  # hier darf nichts in die Hauptstraße münden (Tunnel, Mittelstreifen, enge Kurve ...)
        state[n] = st
    # Kanten: zwischen zwei Netz-Knoten; an einem M-Knoten: Einmündung (Ende wird bis zur Mittellinie verlängert)
    edges = []  # {a, b, pts, name, cls}; a/b: Knoten-ID oder ("main", Index auf main)
    for w in ways:
        ns = w["nodes"]
        for k in range(len(ns) - 1):
            a, b = ns[k], ns[k + 1]
            sa, sb = state[a], state[b]
            if sa == "F" or sb == "F" or (sa == "M" and sb == "M"):
                continue
            pa, pb = pos[a], pos[b]
            if sa == "M" or sb == "M":
                # Stück von der Kante der Hauptstraße bis zum Netz-Knoten; die Einmündung zur Mittellinie
                mi = a if sa == "M" else b
                ni = b if sa == "M" else a
                seg = densify([pos[mi], pos[ni]], 1.0)
                # erster Punkt außerhalb von MAIN_CUT
                cut = None
                for q in seg:
                    if far_dist(near, q) >= MAIN_CUT:
                        cut = q
                        break
                if cut is None:
                    continue
                _, mk = near(cut, 80.0)
                end = ("main", mk)
                pts = [main[mk], cut, pos[ni]] if math.dist(cut, pos[ni]) > 0.5 else [main[mk], pos[ni]]
                edges.append({"a": end, "b": ni, "pts": pts, "name": w["name"], "cls": w["cls"]})
            else:
                edges.append({"a": a, "b": b, "pts": [pa, pb], "name": w["name"], "cls": w["cls"]})
    # doppelte Kanten (Richtungsfahrbahnen derselben Straße teilen sich keine Knoten, aber gleiche Knotenpaare)
    seen = set()
    uniq = []
    for e in edges:
        key = (str(e["a"]), str(e["b"]))
        if key in seen or (key[1], key[0]) in seen:
            continue
        seen.add(key)
        uniq.append(e)
    edges = uniq
    # Sackgassen kappen: Knoten mit nur einer Kante (außer Einmündungen in die Hauptstraße) fallen weg, bis keine mehr
    changed = True
    while changed:
        changed = False
        deg = {}
        for e in edges:
            for k in ("a", "b"):
                if not isinstance(e[k], tuple):
                    deg[e[k]] = deg.get(e[k], 0) + 1
        keep = []
        for e in edges:
            dead = any(not isinstance(e[k], tuple) and deg[e[k]] < 2 for k in ("a", "b"))
            if dead:
                changed = True
            else:
                keep.append(e)
        edges = keep
    # Ketten bilden: über Knoten mit genau zwei Kanten zusammenhängen; an Kreuzungen geradeaus weiter (gleicher Name
    # bevorzugt), so wird eine Straße eine Linie
    adj = {}
    for i, e in enumerate(edges):
        for k in ("a", "b"):
            if not isinstance(e[k], tuple):
                adj.setdefault(e[k], []).append(i)
    used = [False] * len(edges)

    def oriented(i, start):
        e = edges[i]
        pts = e["pts"] if e["a"] == start else list(reversed(e["pts"]))
        other = e["b"] if e["a"] == start else e["a"]
        return pts, other

    def heading(p0, p1):
        return math.atan2(p1[1] - p0[1], p1[0] - p0[0])

    def continue_from(node, pts, name):
        """nächste unbenutzte Kante an node, die am geradesten weiterführt (höchstens 50° Knick)"""
        h0 = heading(pts[-2], pts[-1]) if len(pts) > 1 else 0.0
        # Ecke ohne Kreuzung (nur zwei Kanten): immer weiter, auch rechtwinklig (wird gerundet); sonst bliebe dort ein
        # Ende am Ende, und an der Außenseite der Ecke fehlte die Wand
        if len(adj.get(node, [])) == 2:
            for j in adj[node]:
                if not used[j]:
                    p2, _ = oriented(j, node)
                    dh = abs((heading(p2[0], p2[1]) - h0 + math.pi) % (2 * math.pi) - math.pi)
                    return j if dh < math.radians(115) else -1  # spitze Kehre: zwei Straßen, sonst ein Zacken
            return -1
        best, bi = 1e9, -1
        for j in adj.get(node, []):
            if used[j]:
                continue
            p2, _ = oriented(j, node)
            dh = abs((heading(p2[0], p2[1]) - h0 + math.pi) % (2 * math.pi) - math.pi)
            score = dh - (0.35 if edges[j]["name"] == name and name else 0.0)
            if dh < math.radians(50) and score < best:
                best, bi = score, j
        return bi

    streets = []
    order = sorted(range(len(edges)), key=lambda i: (0 if isinstance(edges[i]["a"], tuple) or isinstance(edges[i]["b"], tuple) else 1))
    for i in order:
        if used[i]:
            continue
        used[i] = True
        e = edges[i]
        start = e["a"]
        pts, cur = oriented(i, start)
        names = [e["name"]]
        cls = [e["cls"]]
        # vorwärts
        while not isinstance(cur, tuple):
            j = continue_from(cur, pts, names[-1])
            if j < 0:
                break
            used[j] = True
            p2, cur = oriented(j, cur)
            pts = pts + p2[1:]
            names.append(edges[j]["name"])
            cls.append(edges[j]["cls"])
        end_b = cur
        # rückwärts
        cur = start
        while not isinstance(cur, tuple):
            rev = list(reversed(pts))
            j = continue_from(cur, rev, names[0])
            if j < 0:
                break
            used[j] = True
            p2, cur = oriented(j, cur)
            pts = list(reversed(p2)) + pts[1:]
            names.insert(0, edges[j]["name"])
            cls.insert(0, edges[j]["cls"])
        streets.append({"pts": pts, "a": cur, "b": end_b, "names": names, "cls": cls})
    # Knoten -> Straßen, die durch ihn laufen (für T-Einmündungen)
    on_node = {}
    for si, st in enumerate(streets):
        for q in st["pts"]:
            pass
    node_pos_to_street = {}
    for si, st in enumerate(streets):
        for q in st["pts"]:
            node_pos_to_street.setdefault((round(q[0], 2), round(q[1], 2)), set()).add(si)
    out = []
    for si, st in enumerate(streets):
        ends = []
        ok = True
        for k in ("a", "b"):
            nd = st[k]
            if isinstance(nd, tuple):
                ends.append({"main": True})
                continue
            q = pos[nd]
            others = node_pos_to_street.get((round(q[0], 2), round(q[1], 2)), set()) - {si}
            if not others:
                ok = False  # Ende ohne Anschluss (darf nach dem Kappen nicht vorkommen)
            ends.append({"street": min(others) if others else -1})
        length = sum(math.dist(a, b) for a, b in zip(st["pts"], st["pts"][1:]))
        name = max(set(n for n in st["names"] if n), key=st["names"].count, default="")
        cls_rank = {"breit": 2, "strasse": 1, "gasse": 0}
        cl = max(st["cls"], key=lambda c: (st["cls"].count(c), cls_rank[c]))
        out.append({"pts": st["pts"], "ends": ends, "name": name, "cls": cl, "len": length, "ok": ok})
    # Einmündungswinkel an der Hauptstraße prüfen, zu kurze und zu flache weg (und was nur an ihnen hing)
    def mouth_angle(st, k):
        p = st["pts"] if k == 0 else list(reversed(st["pts"]))
        _, mk = near(p[0], 40.0)
        a = main[max(mk - 3, 0)]
        b = main[min(mk + 3, len(main) - 1)]
        tdir = heading(a, b)
        q = next((x for x in p if math.dist(x, p[0]) > 22.0), p[-1])
        sdir = heading(p[0], q)
        d = abs((sdir - tdir + math.pi) % (2 * math.pi) - math.pi)
        return math.degrees(min(d, math.pi - d))
    drop = set()
    carried = set(e["street"] for st in out for e in st["ends"] if "street" in e)  # an diesen hängen andere
    for si, st in enumerate(out):
        if st["len"] < MIN_LEN or not st["ok"]:
            drop.add(si)
        # kurze Schleife zurück an dieselbe Straße (Wendeschleife, Zwickel): führt nirgendwohin, und im engen Zwickel
        # stünden die Wände auf der Fahrbahn
        e0, e1 = st["ends"]
        if st["len"] < LOOP_MIN and (e0.get("main") and e1.get("main") or e0.get("street", -1) == e1.get("street", -2)) \
                and si not in carried:
            drop.add(si)
        for k in (0, 1):
            if st["ends"][k].get("main") and mouth_angle(st, k) < MOUTH_MIN_ANG:
                drop.add(si)
    changed = True
    while changed:
        changed = False
        for si, st in enumerate(out):
            if si in drop:
                continue
            if any(e.get("street", -2) in drop for e in st["ends"]):
                drop.add(si)
                changed = True
    keep = [si for si in range(len(out)) if si not in drop]
    remap = {si: k for k, si in enumerate(keep)}
    res = []
    for si in keep:
        st = out[si]
        line = fillet(simplify(st["pts"]), CORNER_R, STEP)
        if len(line) < 6:
            print("  WARNUNG: %s nach dem Runden nur %d Punkte" % (st["name"], len(line)))
        ends = [({"main": True} if e.get("main") else {"street": remap[e["street"]]}) for e in st["ends"]]
        res.append({"name": st["name"], "cls": st["cls"], "ends": ends,
                    "pts": [v for q in line for v in (round(q[0], 1), round(q[1], 1))]})
    total = sum(o["len"] for k, o in enumerate(out) if k in remap)
    nm = sum(1 for o in res for e in o["ends"] if e.get("main"))
    print(f"{city}: {len(res)} Straßen, {total / 1000:.1f} km, {nm} Einmündungen in die Hauptstraße")
    for o in res:
        print(f"   {o['cls']:7s} {o['name'] or '-':28s} {len(o['pts']) // 2 * STEP:6.0f} m  Enden {o['ends']}")
    return res


def gd(v, ind=1):
    t = "\t" * ind
    if isinstance(v, dict):
        return "{" + ", ".join(f'"{k}": {gd(x, ind + 1)}' for k, x in v.items()) + "}"
    if isinstance(v, list):
        if v and isinstance(v[0], (int, float)):
            rows = [", ".join(str(x) for x in v[k:k + 16]) for k in range(0, len(v), 16)]
            return "[\n" + ",\n".join(t + "\t" + r for r in rows) + ",\n" + t + "]"
        return "[\n" + ",\n".join(t + "\t" + gd(x, ind + 1) for x in v) + ",\n" + t + "]"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    return str(v)


def main():
    folder = sys.argv[1]
    cities = sys.argv[2:] or CITIES
    # nur die genannten Städte neu, die übrigen aus der vorhandenen Datei behalten (als Text)
    keep_txt = {}
    if os.path.exists(OUT):
        src = open(OUT, encoding="utf-8").read()
        for m in re.finditer(r'^\t"([a-z]+)": \[\n.*?^\t\],$', src, re.M | re.S):
            if m.group(1) not in cities:
                keep_txt[m.group(1)] = m.group(0)
    res = {c: build(folder, c) for c in cities}
    lines = ["extends RefCounted", "## Automatisch erzeugt von tools/osm_net.py, nicht von Hand ändern.",
             "## Kartendaten © OpenStreetMap-Mitwirkende, Lizenz ODbL (openstreetmap.org/copyright).",
             "## Echte Straßen um die Strecke als Nebenstraßen der freien Fahrt: pts (x0, z0, x1, z1, ... wie city_data),",
             "## cls (gasse/strasse/breit), ends: [{main: true} = Einmündung in die Hauptstraße | {street: i} = an Straße i].",
             "", "const NETS := {"]
    for c, txt in keep_txt.items():
        lines.append(txt)
    for c, streets in res.items():
        lines.append(f'\t"{c}": ' + gd(streets, 1) + ",")
    lines.append("}")
    open(OUT, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print("geschrieben:", OUT)


if __name__ == "__main__":
    main()
