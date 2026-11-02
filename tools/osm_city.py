#!/usr/bin/env python3
"""Städte-Strecken aus OpenStreetMap-Daten (© OpenStreetMap-Mitwirkende, ODbL).

Liest je Stadt einen Overpass-Export (Straßen, Flüsse, Bahngleise; siehe fetch_query()), sucht über echte Straßen
eine Route durch die angegebenen Wegpunkte, rundet zu enge Ecken ab (Mindestradius für die vierspurige Spielstraße)
und schreibt Mittellinie, Straßennamen, Flüsse, Bahnkreuzungen, Hügel und Wahrzeichen nach scripts/city_data.gd.

    python3 tools/osm_city.py <ordner-mit-overpass-json> [stadt ...]

Koordinaten im Spiel: x = Osten, z = Süden (Godot: -Z ist Norden), Meter, Ursprung = Startpunkt der Route.
"""
import heapq
import json
import math
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "scripts", "city_data.gd")

R_MIN = 38.0  # kleinster Kurvenradius der Mittellinie (Fahrbahn 18 m + Gehwege)
STEP = 2.0  # Abtastung beim Glätten
CTRL = 18.0  # Abstand der Kontrollpunkte im Spiel
GAP = 46.0  # Mindestabstand zweier Streckenteile, die nicht direkt aufeinander folgen

# Kosten je Straßenklasse: große Straßen bevorzugt, Wohnstraßen nur wenn nötig
COST = {"motorway": 1.0, "trunk": 1.0, "primary": 1.0, "secondary": 1.05, "tertiary": 1.15, "unclassified": 1.5,
        "residential": 2.2, "living_street": 4.0, "motorway_link": 1.4, "trunk_link": 1.3, "primary_link": 1.3,
        "secondary_link": 1.3, "tertiary_link": 1.3}

# Wegpunkte: (Straßenname, lat, lon) -> nächster Knoten dieser Straße; Name None = beliebige Straße.
# landmarks: (Art, lat, lon[, Name]). hills: (lat, lon, Radius m, Höhe m). river: Breite in m je Flussname.
CITIES = {
    "aachen": {
        "label": "AACHEN", "region": "Städteregion Aachen", "loop": True,
        "via": [("Templergraben", 50.77856, 6.08026), ("Hirschgraben", 50.77898, 6.08306), ("Seilgraben", 50.77838, 6.08617),
                ("Friedrich-Wilhelm-Platz", 50.77420, 6.08740), ("Kapuzinergraben", 50.77249, 6.08573),
                ("Alexianergraben", 50.77225, 6.08256), ("Löhergraben", 50.77259, 6.07893)],
        "landmarks": [("aachen_dom", 50.77476, 6.08399), ("aachen_rathaus", 50.77607, 6.08377),
                      ("elisenbrunnen", 50.77410, 6.08686), ("super_c", 50.77827, 6.07857),
                      ("theater", 50.77254, 6.08714)],
        "hills": [(50.78674, 6.07997, 260.0, 38.0, "park")],
        "rivers": {},
    },
    "wuerzburg": {
        "label": "WÜRZBURG", "region": "Kreisfreie Stadt", "loop": False,
        "via": [("Röntgenring", 49.8003, 9.9320), ("Friedrich-Ebert-Ring", 49.7930, 9.9440),
                ("Sanderring", 49.7880, 9.9345), ("Ludwigsbrücke", 49.7868, 9.9265),
                ("Saalgasse", 49.7920, 9.9235), ("Dreikronenstraße", 49.7960, 9.9230),
                ("Kranenkai", 49.7962, 9.9268), ("Mainkai", 49.7940, 9.9268)],
        "landmarks": [("residenz", 49.79281, 9.93918), ("festung", 49.78980, 9.91924), ("mainbruecke", 49.79298, 9.92566),
                      ("kiliansdom", 49.79341, 9.93231), ("kaeppele", 49.78433, 9.92193),
                      ("marienkapelle", 49.79484, 9.92958), ("alter_kranen", 49.79604, 9.92640)],
        "hills": [(49.7898, 9.9180, 340.0, 85.0, "vineyard"), (49.7838, 9.9205, 230.0, 55.0, "vineyard")],
        "rivers": {"Main": 105.0},
    },
    "badkissingen": {
        "label": "BAD KISSINGEN", "region": "Landkreis Bad Kissingen", "loop": False,
        "via": [("Ludwigstraße", 50.1978, 10.0730), ("Maxstraße", 50.2025, 10.0775), ("Nordring", 50.2095, 10.0758),
                ("Untere Saline", 50.2150, 10.0720), ("Klaushofstraße", 50.2190, 10.0680)],
        "landmarks": [("regentenbau", 50.19787, 10.07460), ("arkadenbau", 50.19745, 10.07550),
                      ("spielbank", 50.19627, 10.07546), ("gradierbau", 50.21800, 10.06930),
                      ("altes_rathaus", 50.19986, 10.07656)],
        "hills": [(50.2050, 10.0920, 420.0, 60.0, "forest")],
        "rivers": {"Fränkische Saale": 30.0},
    },
    "tbb": {
        "label": "TAUBERBISCHOFSHEIM", "region": "Main-Tauber-Kreis", "loop": True,
        "via": [("Schmiederstraße", 49.62389, 9.66487), ("Vitryallee", 49.62187, 9.66574), ("Taubenhausweg", 49.61986, 9.66344),
                ("Dittigheimer Straße", 49.61937, 9.65976), ("Hauptstraße", 49.62111, 9.65989),
                ("Bahnhofstraße", 49.62313, 9.65867)],
        "landmarks": [("tuermersturm", 49.62127, 9.66173), ("tbb_rathaus", 49.62323, 9.66248),
                      ("st_martin", 49.62248, 9.66101)],
        "hills": [],
        "rivers": {"Tauber": 26.0},
    },
    "hammelburg": {
        "label": "HAMMELBURG", "region": "Landkreis Bad Kissingen", "loop": False,
        "via": [("Berliner Straße", 50.1182, 9.9050), ("Berliner Straße", 50.11638, 9.89687), ("Kissinger Straße", 50.11545, 9.89317), ("Am Marktplatz", 50.11516, 9.89015),
                ("Weihertorstraße", 50.11476, 9.88882), (None, 50.11414, 9.88639), (None, 50.11322, 9.88413),
                ("Am Schlossberg", 50.11215, 9.87996), ("Saaleckstraße", 50.1112, 9.8735)],
        "landmarks": [("hammelburg_rathaus", 50.11490, 9.89039), ("saaleck", 50.11078, 9.87201)],
        "hills": [(50.1105, 9.8715, 300.0, 70.0, "vineyard")],
        "rivers": {"Fränkische Saale": 30.0},
    },
    "kreuzberg": {
        "label": "BERLIN", "region": "Bezirk Friedrichshain-Kreuzberg", "loop": True,
        "via": [("Skalitzer Straße", 52.4990, 13.4195), ("Skalitzer Straße", 52.5006, 13.4330), ("Skalitzer Straße", 52.5010, 13.4400),
                ("Oberbaumbrücke", 52.5020, 13.4458), ("Mühlenstraße", 52.50518, 13.4399), ("Mühlenstraße", 52.50773, 13.43595),
                ("Schillingbrücke", 52.5092, 13.4292), ("Köpenicker Straße", 52.50742, 13.42809), ("Köpenicker Straße", 52.50901, 13.42397),
                ("Adalbertstraße", 52.50664, 13.4231), ("Adalbertstraße", 52.50366, 13.42095)],
        "landmarks": [("oberbaumbruecke", 52.50196, 13.44572), ("fernsehturm", 52.52082, 13.40940), ("nkz", 52.49930, 13.41760)],
        "hills": [],
        "rivers": {"Spree": 110.0, "Landwehrkanal": 22.0},
    },
}


def fetch_query(bbox: str) -> str:
    """Overpass-Abfrage, mit der die Rohdaten geladen wurden (bbox = "süd,west,nord,ost")."""
    hw = "|".join(COST.keys()) + "|pedestrian"
    return (f'[out:json][timeout:90];(way["highway"~"^({hw})$"]({bbox});way["waterway"~"^(river|canal)$"]({bbox});'
            f'way["natural"="water"]({bbox});way["railway"="rail"]({bbox}););out geom;')


class Proj:
    def __init__(self, lat0, lon0):
        self.lat0, self.lon0 = lat0, lon0
        self.kx = 111320.0 * math.cos(math.radians(lat0))

    def __call__(self, lat, lon):
        return ((lon - self.lon0) * self.kx, -(lat - self.lat0) * 110574.0)


def load(folder, city):
    data = json.load(open(os.path.join(folder, city + ".json"), encoding="utf-8"))
    nodes, adj, ways = {}, {}, []
    rivers, rails = [], []
    for e in data["elements"]:
        if e["type"] != "way":
            continue
        t = e.get("tags", {})
        geo = [(g["lat"], g["lon"]) for g in e.get("geometry", [])]
        if "highway" in t and t["highway"] in COST:
            ways.append(e)
            ids = e["nodes"]
            for i, nid in enumerate(ids):
                nodes[nid] = geo[i]
            for i in range(len(ids) - 1):
                a, b = ids[i], ids[i + 1]
                L = dist_ll(geo[i], geo[i + 1])
                c = L * COST[t["highway"]]
                info = (t.get("name", ""), t["highway"])
                adj.setdefault(a, []).append((b, c, info))
                adj.setdefault(b, []).append((a, c, info))
        elif t.get("waterway") in ("river", "canal"):
            rivers.append((t.get("name", ""), geo))
        elif t.get("railway") == "rail":
            rails.append(geo)
    return nodes, adj, ways, rivers, rails


def dist_ll(a, b):
    k = math.cos(math.radians(a[0]))
    return math.hypot((a[0] - b[0]) * 110574.0, (a[1] - b[1]) * 111320.0 * k)


def snap(nodes, ways, name, lat, lon):
    best, bd = None, 1e18
    for w in ways:
        if name is not None and w["tags"].get("name") != name:
            continue
        if name is None and w["tags"]["highway"] not in ("primary", "secondary", "tertiary", "trunk"):
            continue
        for nid in w["nodes"]:
            d = dist_ll(nodes[nid], (lat, lon))
            if d < bd:
                best, bd = nid, d
    if best is None:
        raise SystemExit(f"Wegpunkt nicht gefunden: {name} {lat},{lon}")
    return best, bd


def dijkstra(adj, a, b):
    dist, prev = {a: 0.0}, {}
    q = [(0.0, a)]
    while q:
        d, u = heapq.heappop(q)
        if u == b:
            break
        if d > dist.get(u, 1e18):
            continue
        for v, c, info in adj.get(u, []):
            nd = d + c
            if nd < dist.get(v, 1e18):
                dist[v] = nd
                prev[v] = (u, info)
                heapq.heappush(q, (nd, v))
    if b not in prev and a != b:
        raise SystemExit("keine Verbindung")
    path, names = [b], []
    while path[-1] != a:
        u, info = prev[path[-1]]
        names.append(info)
        path.append(u)
    return path[::-1], names[::-1]


def resample(pts, step, closed):
    if closed and pts[0] != pts[-1]:
        pts = pts + [pts[0]]
    out = [pts[0]]
    carry = 0.0
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        L = math.dist(a, b)
        if L < 1e-6:
            continue
        t = step - carry
        while t <= L:
            out.append((a[0] + (b[0] - a[0]) * t / L, a[1] + (b[1] - a[1]) * t / L))
            t += step
        carry = L - (t - step)
    if closed:
        if math.dist(out[-1], out[0]) < step * 0.5:
            out.pop()
    elif math.dist(out[-1], pts[-1]) > 0.1:
        out.append(pts[-1])
    return out


def radius_at(p, i, closed, k=4):
    n = len(p)
    if not closed and (i - k < 0 or i + k >= n):
        return 1e9
    a, b, c = p[(i - k) % n], p[i], p[(i + k) % n]
    ab, bc, ca = math.dist(a, b), math.dist(b, c), math.dist(c, a)
    cross = abs((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]))
    if cross < 1e-9:
        return 1e9
    return ab * bc * ca / (2.0 * cross)


def smooth(pts, closed):
    """Zu enge Stellen lokal glätten, bis überall der Mindestradius erreicht ist."""
    p = resample(pts, STEP, closed)
    for it in range(1500):
        n = len(p)
        bad = [i for i in range(n) if radius_at(p, i, closed) < R_MIN]
        if not bad:
            break
        weight = [0.0] * n
        for i in bad:
            for j in range(-12, 13):
                k = i + j
                if closed:
                    k %= n
                elif k <= 0 or k >= n - 1:
                    continue
                weight[k] = max(weight[k], 1.0 - abs(j) / 13.0)
        q = list(p)
        for i in range(n):
            if weight[i] <= 0.0:
                continue
            acc = [0.0, 0.0]
            cnt = 0
            for j in range(-3, 4):
                k = i + j
                if closed:
                    k %= n
                elif k < 0 or k >= n:
                    continue
                acc[0] += p[k][0]
                acc[1] += p[k][1]
                cnt += 1
            w = weight[i] * 0.8
            q[i] = (p[i][0] + (acc[0] / cnt - p[i][0]) * w, p[i][1] + (acc[1] / cnt - p[i][1]) * w)
        p = q
        if it % 8 == 7:
            p = resample(p, STEP, closed)
    return p


def arclen(p, closed):
    s = [0.0]
    for i in range(1, len(p)):
        s.append(s[-1] + math.dist(p[i - 1], p[i]))
    if closed:
        s.append(s[-1] + math.dist(p[-1], p[0]))
    return s


def nearest(p, q):
    bi, bd = 0, 1e18
    for i, a in enumerate(p):
        d = (a[0] - q[0]) ** 2 + (a[1] - q[1]) ** 2
        if d < bd:
            bi, bd = i, d
    return bi, math.sqrt(bd)


def seg_intersect(a, b, c, d):
    def cr(o, p, q):
        return (p[0] - o[0]) * (q[1] - o[1]) - (p[1] - o[1]) * (q[0] - o[0])
    d1, d2, d3, d4 = cr(c, d, a), cr(c, d, b), cr(a, b, c), cr(a, b, d)
    if (d1 > 0) != (d2 > 0) and (d3 > 0) != (d4 > 0):
        t = d1 / (d1 - d2)
        return t
    return None


def build(folder, city, cfg, report):
    nodes, adj, ways, rivers, rails = load(folder, city)
    snapped = []
    for name, lat, lon in cfg["via"]:
        nid, off = snap(nodes, ways, name, lat, lon)
        snapped.append(nid)
        if off > 120:
            report.append(f"  Wegpunkt {name} liegt {int(off)} m neben der Straße")
    seq = snapped + ([snapped[0]] if cfg["loop"] else [])
    route, names = [], []
    for i in range(len(seq) - 1):
        path, nm = dijkstra(adj, seq[i], seq[i + 1])
        if route:
            path = path[1:]
        route += path
        names += nm
    lat0, lon0 = nodes[route[0]]
    proj = Proj(lat0, lon0)
    raw = [proj(*nodes[n]) for n in route]
    closed = cfg["loop"]
    if closed:
        raw = raw[:-1]
        names = names[:len(raw)]
    # Straßennamen entlang der Rohroute (Länge je Abschnitt)
    raw_s = arclen(raw, False)
    sm = smooth(raw, closed)
    # Rundkurs: Start dorthin legen, wo es am längsten geradeaus geht (Startaufstellung + Kamerafahrt)
    if closed:
        n = len(sm)
        best_i, best_r = 0, -1.0
        for i in range(0, n, 3):
            r = min(radius_at(sm, (i + j) % n, True, 8) for j in range(-45, 80, 3))
            if r > best_r:
                best_i, best_r = i, r
        sm = sm[best_i:] + sm[:best_i]
    s = arclen(sm, closed)
    length = s[-1]
    # Abweichung von der echten Straße
    dev = max(nearest(sm, q)[1] for q in raw[::3])
    rmin = min(radius_at(sm, i, closed) for i in range(len(sm)))
    report.append(f"  Länge {int(length)} m, kleinster Radius {rmin:.0f} m, max. Abweichung von OSM {dev:.1f} m")
    # Engstellen: nicht benachbarte Streckenteile zu dicht beieinander
    n = len(sm)
    issues = 0
    for i in range(0, n, 4):
        for j in range(i + 4, n, 4):
            arc = s[j] - s[i]
            if closed:
                arc = min(arc, length - arc)
            if arc > 160 and math.dist(sm[i], sm[j]) < GAP:
                if issues < 6:
                    report.append(f"  ENG: d={int(s[i])} und d={int(s[j])} nur {math.dist(sm[i], sm[j]):.0f} m auseinander")
                issues += 1
    # Straßennamen: jede Rohroute-Kante auf die geglättete Linie abbilden
    streets = []
    for i in range(len(raw) - 1 if not closed else len(raw)):
        nm = names[i][0] if i < len(names) else ""
        mid = ((raw[i][0] + raw[(i + 1) % len(raw)][0]) / 2, (raw[i][1] + raw[(i + 1) % len(raw)][1]) / 2)
        k, _ = nearest(sm, mid)
        d = s[k]
        if streets and streets[-1][2] == nm and abs(d - streets[-1][1]) < 120:
            streets[-1][1] = max(streets[-1][1], d)
        else:
            streets.append([d, d, nm])
    streets = [st for st in streets if st[2] and st[1] - st[0] > 70]
    report.append("  Straßen: " + " > ".join(f"{st[2]} ({int(st[0])})" for st in streets))
    # Kontrollpunkte
    ctrl = []
    nxt = 0.0
    for i in range(len(sm)):
        if s[i] >= nxt:
            ctrl.append(sm[i])
            nxt = s[i] + CTRL
    if not closed and math.dist(ctrl[-1], sm[-1]) > 4.0:
        ctrl.append(sm[-1])
    # Flüsse: Mittellinien in der Nähe der Strecke
    out_rivers = []
    for name, geo in rivers:
        if name not in cfg["rivers"]:
            continue
        pts = [proj(*g) for g in geo]
        if min(nearest(sm, q)[1] for q in pts[::2] + [pts[-1]]) > 900:
            continue
        out_rivers.append({"name": name, "width": cfg["rivers"][name], "pts": resample(pts, 12.0, False)})
    # Flüsse als zusammenhängende Linien zusammenfügen (OSM teilt sie in viele Wege)
    out_rivers = join_lines(out_rivers)
    for r in out_rivers:
        crossings = []
        for i in range(len(sm) - (0 if closed else 1)):
            a, b = sm[i], sm[(i + 1) % len(sm)]
            for k in range(len(r["pts"]) - 1):
                t = seg_intersect(a, b, r["pts"][k], r["pts"][k + 1])
                if t is not None:
                    crossings.append(round(s[i] + t * math.dist(a, b), 1))
        r["cross"] = crossings
        report.append(f"  Fluss {r['name']}: {len(r['pts'])} Punkte, Brücken bei {crossings}")
    rail_cross = []
    for geo in rails:
        pts = [proj(*g) for g in geo]
        for i in range(len(sm) - (0 if closed else 1)):
            a, b = sm[i], sm[(i + 1) % len(sm)]
            for k in range(len(pts) - 1):
                t = seg_intersect(a, b, pts[k], pts[k + 1])
                if t is not None:
                    rail_cross.append(round(s[i] + t * math.dist(a, b), 1))
    rail_cross = sorted(set(int(x) for x in rail_cross))
    report.append(f"  Bahngleise kreuzen bei {rail_cross}")
    lms = []
    for lm in cfg["landmarks"]:
        x, z = proj(lm[1], lm[2])
        k, dd = nearest(sm, (x, z))
        lms.append({"kind": lm[0], "x": round(x, 1), "z": round(z, 1), "name": lm[3] if len(lm) > 3 else ""})
        report.append(f"  {lm[0]:20s} {lm[3] if len(lm) > 3 else '':14s} {int(dd):4d} m neben der Strecke bei d={int(s[k])}")
    hills = []
    for h in cfg["hills"]:
        x, z = proj(h[0], h[1])
        hills.append({"x": round(x, 1), "z": round(z, 1), "r": h[2], "h": h[3], "kind": h[4]})
    xs = [q[0] for q in sm]
    zs = [q[1] for q in sm]
    pad = 320.0
    bbox = (lat0 - (max(zs) + pad) / 110574.0, lon0 + (min(xs) - pad) / proj.kx,
            lat0 - (min(zs) - pad) / 110574.0, lon0 + (max(xs) + pad) / proj.kx)
    out_b = buildings(folder, city, proj, sm, report)
    return {
        "label": cfg["label"], "region": cfg["region"], "loop": closed, "length": round(length, 1),
        "origin": [lat0, lon0], "bbox": [round(v, 5) for v in bbox], "buildings": out_b,
        "points": [v for q in ctrl for v in (round(q[0], 2), round(q[1], 2))],
        "streets": [[round(a, 1), round(b, 1), nm] for a, b, nm in streets],
        "rivers": [{"name": r["name"], "width": r["width"], "cross": r["cross"],
                    "pts": [v for q in r["pts"] for v in (round(q[0], 1), round(q[1], 1))]} for r in out_rivers],
        "rail": rail_cross, "landmarks": lms, "hills": hills,
    }


LEVEL_H = 3.1
TYPE_H = {"house": 8.0, "detached": 8.0, "semidetached_house": 8.0, "terrace": 10.0, "apartments": 14.0, "residential": 12.0,
          "garage": 3.0, "garages": 3.0, "shed": 3.0, "industrial": 9.0, "warehouse": 9.0, "retail": 9.0, "commercial": 13.0,
          "office": 16.0, "school": 12.0, "university": 16.0, "hospital": 18.0, "hotel": 15.0, "public": 13.0}
SKIP = {"roof", "carport", "construction", "ruins", "bunker", "hut", "kiosk", "service", "transformer_tower"}


def obb(poly):
    """Kleinstes umschließendes Rechteck: Mitte, Länge (entlang Winkel), Breite, Winkel"""
    best = None
    n = len(poly)
    for i in range(n):
        a, b = poly[i], poly[(i + 1) % n]
        ang = math.atan2(b[1] - a[1], b[0] - a[0])
        c, s_ = math.cos(ang), math.sin(ang)
        us = [p[0] * c + p[1] * s_ for p in poly]
        vs = [-p[0] * s_ + p[1] * c for p in poly]
        area = (max(us) - min(us)) * (max(vs) - min(vs))
        if best is None or area < best[0]:
            u0, u1, v0, v1 = min(us), max(us), min(vs), max(vs)
            cu, cv = (u0 + u1) / 2, (v0 + v1) / 2
            best = (area, cu * c - cv * s_, cu * s_ + cv * c, u1 - u0, v1 - v0, ang)
    return best


def buildings(folder, city, proj, route, report):
    """Echte Gebäude aus <stadt>_bld.json (Overpass: way["building"]) als Quader: x, z, Länge, Breite, Winkel, Höhe"""
    path = os.path.join(folder, city + "_bld.json")
    if not os.path.exists(path):
        report.append("  (keine Gebäudedaten)")
        return []
    data = json.load(open(path, encoding="utf-8"))
    out = []
    grid = {}
    for q in route[::5]:
        grid.setdefault((int(q[0] // 100), int(q[1] // 100)), []).append(q)

    def route_dist(x, z):
        best = 1e9
        gx, gz = int(x // 100), int(z // 100)
        for i in range(gx - 4, gx + 5):
            for j in range(gz - 4, gz + 5):
                for q in grid.get((i, j), []):
                    best = min(best, (q[0] - x) ** 2 + (q[1] - z) ** 2)
        return math.sqrt(best)
    for e in data["elements"]:
        t = e.get("tags", {})
        if e["type"] != "way" or "geometry" not in e or t.get("building") in SKIP:
            continue
        poly = [proj(g["lat"], g["lon"]) for g in e["geometry"]]
        if len(poly) > 3 and math.dist(poly[0], poly[-1]) < 0.5:
            poly = poly[:-1]
        if len(poly) < 3:
            continue
        area, cx, cz, L, W, ang = obb(poly)
        if L * W < 30.0 or L * W > 6000.0:
            continue
        rd = route_dist(cx, cz)
        if rd > 330.0 or rd - 0.5 * min(L, W) < 30.0:
            continue
        h = None
        try:
            if "height" in t:
                h = float(t["height"].replace("m", "").strip())
            elif "building:levels" in t:
                h = float(t["building:levels"]) * LEVEL_H + 1.0
        except ValueError:
            h = None
        if h is None:
            h = TYPE_H.get(t.get("building", "yes"), 12.0)
        h = max(3.0, min(h, 40.0))
        # Länge immer die längere Seite (First läuft entlang)
        if W > L:
            L, W, ang = W, L, ang + math.pi / 2
        out += [round(cx, 1), round(cz, 1), round(L, 1), round(W, 1), round(ang, 3), round(h, 1)]
    report.append(f"  Gebäude: {len(out) // 6}")
    return out


def join_lines(rivers):
    """Teilstücke gleichen Namens aneinanderhängen, wo Enden zusammenfallen."""
    out = []
    pool = list(rivers)
    while pool:
        cur = pool.pop(0)
        changed = True
        while changed:
            changed = False
            for o in pool:
                if o["name"] != cur["name"]:
                    continue
                a, b = cur["pts"], o["pts"]
                if math.dist(a[-1], b[0]) < 15:
                    cur["pts"] = a + b[1:]
                elif math.dist(a[0], b[-1]) < 15:
                    cur["pts"] = b + a[1:]
                elif math.dist(a[-1], b[-1]) < 15:
                    cur["pts"] = a + b[::-1][1:]
                elif math.dist(a[0], b[0]) < 15:
                    cur["pts"] = b[::-1] + a[1:]
                else:
                    continue
                pool.remove(o)
                changed = True
                break
        out.append(cur)
    return [r for r in out if len(r["pts"]) > 3]


def gd(v, ind=1):
    """Python-Wert als GDScript-Konstante"""
    t = "\t" * ind
    if isinstance(v, dict):
        return "{\n" + "".join(f'{t}\t"{k}": {gd(x, ind + 1)},\n' for k, x in v.items()) + t + "}"
    if isinstance(v, list):
        if v and all(isinstance(x, (int, float)) for x in v):
            lines = [", ".join(str(float(x)) for x in v[i:i + 16]) for i in range(0, len(v), 16)]
            return "[\n" + "".join(f"{t}\t{ln},\n" for ln in lines) + t + "]"
        return "[" + ", ".join(gd(x, ind) for x in v) + "]"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, str):
        return json.dumps(v, ensure_ascii=False)
    return str(float(v)) if isinstance(v, float) else str(v)


def main():
    folder = sys.argv[1]
    only = sys.argv[2:]
    existing = {}
    out = {}
    for city, cfg in CITIES.items():
        if not cfg["via"]:
            continue
        if only and city not in only:
            continue
        rep = [f"== {city}"]
        out[city] = build(folder, city, cfg, rep)
        print("\n".join(rep))
    cache = os.path.join(folder, "_cache.json")
    if only and os.path.exists(cache):
        existing = json.load(open(cache, encoding="utf-8"))
    existing.update(out)
    json.dump(existing, open(cache, "w", encoding="utf-8"), ensure_ascii=False)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write("extends RefCounted\n## Automatisch erzeugt von tools/osm_city.py, nicht von Hand ändern.\n"
                "## Kartendaten © OpenStreetMap-Mitwirkende, Lizenz ODbL (openstreetmap.org/copyright).\n"
                "## points/pts: flache Listen x0, z0, x1, z1, ... in Metern (x = Osten, z = Süden).\n\n")
        f.write("const CITIES := " + gd(existing, 0) + "\n")


if __name__ == "__main__":
    main()
