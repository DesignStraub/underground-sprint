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
CORNER_R = 11.0
MIN_LEN = 24.0
BLOCK_PAD = 9.0  # Abstand der Straßenmitte zu Sperrflächen
DENSE = 4.0  # Wege dazwischen alle so viele Meter ein Knoten (sonst übersieht man Kreuzungen mit der Strecke)  # kürzere Straßen (zwischen zwei Enden) lohnen nicht
MOUTH_MIN_ANG = 38.0  # flacher darf eine Straße nicht in die Hauptstraße münden (Grad)
CLS = {"primary": "breit", "secondary": "strasse", "tertiary": "strasse", "unclassified": "strasse",
       "residential": "strasse", "primary_link": "strasse", "secondary_link": "strasse", "tertiary_link": "strasse",
       "living_street": "gasse", "pedestrian": "gasse"}
CITIES = ["aachen"]


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


def build(folder, city):
    org, ctrl, loop = city_block(city)
    proj = Proj(org[0], org[1])
    main = densify(ctrl + ([ctrl[0]] if loop else []), 2.0)
    # Sperrflächen aus dem Spiel (tools/net_blocks.gd): Korridore der Ausfahrten (nach hinten bis zur Hauptstraße
    # verlängert), Wahrzeichen, Hügel; dazu die genaue Mittellinie
    blocked = lambda q: False
    bp = os.path.join(folder, city + "_blocks.json")
    if os.path.exists(bp):
        blk = json.load(open(bp, encoding="utf-8"))
        main = [tuple(q) for q in blk["main"]]
        caps = []
        for c in blk["caps"]:
            a, b, r = (c[0], c[1]), (c[2], c[3]), c[4]
            dl = math.dist(a, b) or 1.0
            a = (a[0] - (b[0] - a[0]) / dl * 70.0, a[1] - (b[1] - a[1]) / dl * 70.0)
            caps.append((a, b, r + BLOCK_PAD))
        circ = [((c[0], c[1]), c[2] + BLOCK_PAD) for c in blk["circles"]]
        blocked = lambda q: any(seg_dist(q, a, b) < r for a, b, r in caps) or any(math.dist(q, c) < r for c, r in circ)
    else:
        print("  (keine Sperrflächen: %s fehlt)" % bp)
    near = Near(main)
    data = json.load(open(os.path.join(folder, city + "_streets.json"), encoding="utf-8"))
    # Knoten -> Lage; Wege (ohne Zufahrten/Parkplätze: "service" nur mit Namen)
    ways = []
    fake = [0]  # Zwischenknoten: negative IDs
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
        nodes, dgeo = [e["nodes"][0]], [geo[0]]
        for k in range(1, len(geo)):
            a, b = geo[k - 1], geo[k]
            n = int(math.dist(a, b) / DENSE)
            for j in range(1, n + 1):
                tt = j / (n + 1)
                fake[0] -= 1
                nodes.append(fake[0])
                dgeo.append((a[0] + (b[0] - a[0]) * tt, a[1] + (b[1] - a[1]) * tt))
            nodes.append(e["nodes"][k])
            dgeo.append(b)
        ways.append({"nodes": nodes, "geo": dgeo, "name": t.get("name", ""), "cls": CLS.get(hw, "gasse"), "hw": hw})
    pos = {}
    for w in ways:
        for n, q in zip(w["nodes"], w["geo"]):
            pos[n] = q
    # Zustand je Knoten: "M" (gehört zur Hauptstraße), "F" (zu weit draußen), "" (Netz)
    state = {}
    for n, q in pos.items():
        d = far_dist(near, q)
        state[n] = "M" if d < MAIN_CUT else ("F" if d > REACH or blocked(q) else "")
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
    for si, st in enumerate(out):
        if st["len"] < MIN_LEN or not st["ok"]:
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
    old = {}
    if os.path.exists(OUT):
        src = open(OUT, encoding="utf-8").read()
        for c in re.findall(r'^\t"([a-z]+)": \[', src, re.M):
            old[c] = True
    res = {c: build(folder, c) for c in cities}
    lines = ["extends RefCounted", "## Automatisch erzeugt von tools/osm_net.py, nicht von Hand ändern.",
             "## Kartendaten © OpenStreetMap-Mitwirkende, Lizenz ODbL (openstreetmap.org/copyright).",
             "## Echte Straßen um die Strecke als Nebenstraßen der freien Fahrt: pts (x0, z0, x1, z1, ... wie city_data),",
             "## cls (gasse/strasse/breit), ends: [{main: true} = Einmündung in die Hauptstraße | {street: i} = an Straße i].",
             "", "const NETS := {"]
    for c, streets in res.items():
        lines.append(f'\t"{c}": ' + gd(streets, 1) + ",")
    lines.append("}")
    open(OUT, "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print("geschrieben:", OUT)


if __name__ == "__main__":
    main()
