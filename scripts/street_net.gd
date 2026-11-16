extends RefCounted
## Open World (seit 2.39): Straßennetz der freien Fahrt neben der Hauptstraße. Bis 2.38 bog jede Nebenstraße
## rechtwinklig mit 18 m Radius ab, lief als genaue Parallele hinter der ersten Häuserreihe und kam rechtwinklig
## zurück, immer 10 m breit. Jetzt:
## - Einmündungen schräg (50-90°), weite Bögen (24-46 m), die Nebenstraße schwingt und wechselt den Abstand;
## - Breite je Viertel: Gasse (eine Spur), Straße (zwei Spuren, Gehwege), breite Straße (vier Spuren, Bankenviertel,
##   Hafen, Prachtallee); dazu Parkbuchten mit parkenden Autos oder Grünstreifen mit Bäumen;
## - Kreuzungen: Straßen links und rechts an derselben Stelle (in einer Flucht), mit Ampeln;
## - lange Parallelstraßen mit einer Verbindung in der Mitte (zweiter Weg hinaus);
## - Querverbindungen quer durch Rundkurse und zwischen nahen Teilen derselben Strecke (in den echten Städten
##   entlang der Lücken zwischen den Häusern, also echten Straßen);
## - Plätze und Parkplätze auf Fahrbahnhöhe, auf die man fahren kann.
## Nur in der Welt (race["world"]); eigener Zufall, der Rest der Strecke bleibt wie im Rennen.
##
## Wege (track["paths"]): "lane" (Straße, Gasse, Querverbindung), "passage" (schmale Durchfahrt), "platz". Zusätzlich
## je Weg: "net" (true), "cls", "walk" (Gehweg je Seite), "strip" ([links, rechts]: Parkbucht/Grünstreifen),
## "strip_kind" (["park"|"gruen"|"", ...]), "lanes" (Markierung), "cobble", "ends" (Einmündungen).
## Die Breite bis zur Hauskante liefert edge(); die Stadtfüllung hält mit Track._lot_free davon Abstand.

const Track := preload("res://scripts/track_builder.gd")
const City := preload("res://scripts/city_builder.gd")

const CLS := {
	"gasse": {"half": 3.3, "lanes": 0.0, "walk": 1.0},
	"strasse": {"half": 4.6, "lanes": 2.0, "walk": 2.4},
	"breit": {"half": 7.0, "lanes": 4.0, "walk": 3.2},
}
const STRIP_W := 2.4  # Parkbucht bzw. Grünstreifen zwischen Fahrbahn und Gehweg
## Straßenklasse je Viertel (Gewichte)
const CLS_BY := {
	"downtown": {"breit": 0.5, "strasse": 0.5},
	"industrial": {"breit": 0.45, "strasse": 0.55},
	"boulevard": {"breit": 0.35, "strasse": 0.65},
	"highway": {"breit": 0.4, "strasse": 0.6},
	"campus_de": {"breit": 0.3, "strasse": 0.7},
	"innenstadt_de": {"strasse": 0.7, "gasse": 0.15, "breit": 0.15},
	"residential": {"gasse": 0.45, "strasse": 0.55},
	"altstadt_de": {"gasse": 0.5, "strasse": 0.5},
	"chinatown": {"gasse": 0.5, "strasse": 0.5},
	"shops": {"gasse": 0.35, "strasse": 0.65},
	"kiez_de": {"gasse": 0.3, "strasse": 0.6, "breit": 0.1},
	"kurviertel_de": {"strasse": 0.8, "gasse": 0.2},
	"vorstadt_de": {"strasse": 0.85, "gasse": 0.15},
}
## Altstadt-Gassen mit Kopfsteinpflaster
const COBBLE := ["residential", "altstadt_de", "chinatown"]
const MAIN_CELL := 16.0
const HOUSE_ROOM := 13.0  # hinter einer Nebenstraße muss noch eine Häuserreihe Platz haben

## Test (Prüfwerkzeuge): Gründe, warum Kandidaten nicht passten (Q_ = Querverbindungen)
static var why := {}
static var _pre := ""


# --- Planung ---------------------------------------------------------------------------------------------------------

## Straßennetz einer Welt-Stadt planen (nach Ausfahrten und Querstraßen der Entwürfe)
static func plan(track: Dictionary, race: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(race["seed"]) * 31 + 7
	# Querstraßen der Entwürfe (track_design.plan_cross): Gehwege, Parkbuchten, Ampeln wie die neuen Straßen
	for p in track["paths"]:
		if p["kind"] == "lane" and p.get("cross", false) and not p.has("net"):
			p.merge({"net": true, "from_design": true, "cls": "strasse", "walk": CLS["strasse"]["walk"], "strip": [0.0, STRIP_W if rng.randf() < 0.5 else 0.0],
				"lanes": 2.0, "cobble": 0.0, "ends": [{"at": 0, "d": p["from"]}, {"at": 0, "d": p["to"]}]})
			p["strip_kind"] = ["", "park" if p["strip"][1] > 0.0 else ""]
	var ctx := _ctx(track, race)
	_pre = "Q_"
	_plan_links(ctx, rng)
	_pre = ""
	_plan_parallels(ctx, rng)
	_plan_plazas(ctx, rng)
	_drop_keepout(ctx)
	_plan_junctions(ctx)
	for z in ctx["mz"]:
		track["zones"].append({"from": z[0] - z[1], "to": z[0] + z[1]})
	track["net"] = true


static func _w(k: String) -> bool:
	why[_pre + k] = why.get(_pre + k, 0) + 1
	return false


## Suchraster: Hauptstraße alle 2 m, vorhandene Abzweige, Sperrflächen der Welt, Häuser der echten Städte,
## Wahrzeichen, Ausfahrten (dort führt die Auffahrt zur Autobahn weiter)
static func _ctx(track: Dictionary, race: Dictionary) -> Dictionary:
	var curve: Curve3D = track["curve"]
	var L: float = track["length"]
	var mp := PackedVector2Array()
	var md := PackedFloat32Array()
	var mh := PackedFloat32Array()
	var cells := {}
	var d := 0.0
	while d <= L:
		var q := curve.sample_baked(d)
		var k := mp.size()
		mp.append(Vector2(q.x, q.z))
		md.append(d)
		mh.append(Track.hw(track, d))
		var key := Vector2i(floori(q.x / MAIN_CELL), floori(q.z / MAIN_CELL))
		if not cells.has(key):
			cells[key] = PackedInt32Array()
		cells[key].append(k)
		d += 2.0
	var ctx := {"track": track, "race": race, "curve": curve, "L": L, "loop": track["loop"], "mp": mp, "md": md, "mh": mh,
		"mcells": cells, "bcells": {}, "kcells": {}, "kgrid": {}, "ocells": {}, "circles": [], "caps": [], "osm": false, "mz": [], "tails": [], "skip_zones": []}
	# Ende eines Sprints: world_layout plant die Stadt mit gerader Ausfahrt hinter dem Ziel, gebaut wird sie bei
	# eingeschlossenem Ziel mit Rückführung auf die Strecke (tail_join). Geplant wird beide Male gleich (Kappe am Ende),
	# was der Rückführung im Weg steht, fällt danach weg (_drop_keepout)
	for p in track["paths"]:
		if p["id"] == 0:
			continue
		if p.get("tail", false) and float(p["from"]) > 1.0:
			ctx["tails"].append(p)
			if p.has("join"):
				ctx["skip_zones"].append(float(p["join"]))  # Zone der Einmündung (_plan_tail_join): erst danach
			continue
		_add_branch_cells(ctx, p)
	if not ctx["loop"]:
		var fe := Track.frame_at(curve, L)
		var ea: Vector3 = fe["pos"] - fe["fwd"] * 10.0
		var eb: Vector3 = fe["pos"] + fe["fwd"] * 260.0
		ctx["caps"].append([Vector2(ea.x, ea.z), Vector2(eb.x, eb.z), 34.0])
	# Sperrflächen der Welt (fremde Fahrbahnen) gelten erst nach der Planung (_drop_keepout): world_layout plant die
	# Städte ohne sie (Karten), der Bau mit ihnen; so ist das Netz auf Karte und Straße dasselbe, bis auf Wege, die auf
	# einer fremden Fahrbahn lägen
	for ko in track["keepout"]:
		var kk := Vector2i(floori(ko["pos"].x / 32.0), floori(ko["pos"].z / 32.0))
		if not ctx["kgrid"].has(kk):
			ctx["kgrid"][kk] = []
		ctx["kgrid"][kk].append([Vector2(ko["pos"].x, ko["pos"].z), float(ko["r"])])
	var city: Dictionary = track["city"]
	var data: Array = city.get("buildings", [])
	ctx["osm"] = not data.is_empty()
	for i in range(0, data.size(), 6):
		var c := Vector2(data[i], data[i + 1])
		var ok := Vector2i(floori(c.x / 24.0), floori(c.y / 24.0))
		if not ctx["ocells"].has(ok):
			ctx["ocells"][ok] = []
		ctx["ocells"][ok].append([c, Vector2(data[i + 2], data[i + 3]).length() * 0.42])
	# Wahrzeichen (echte Städte und Entwürfe) und Hügel: Straßen bleiben weg, Wahrzeichen bleiben an ihrem Platz
	for lm in city.get("landmarks", []):
		var info: Dictionary = City.INFO.get(lm["kind"], {"hd": 10.0, "hl": 10.0})
		if lm["kind"] in ["fernsehturm", "mainbruecke", "oberbaumbruecke", "hohenzollernbruecke"]:
			continue
		ctx["circles"].append([Vector2(lm["x"], lm["z"]), maxf(info["hl"], info["hd"]) + 14.0, "wahrzeichen"])
	if race.has("layout"):
		var lay: Dictionary = Track.Design.LAYOUTS.get(race["layout"], {})
		for lm in lay.get("landmarks", []):
			if lm.has("x"):
				var info2: Dictionary = City.INFO.get(lm["kind"], {"hd": 12.0, "hl": 12.0})
				var r: float = 75.0 if lm["kind"] == "arena" else maxf(info2["hl"], info2["hd"]) + 14.0
				ctx["circles"].append([Vector2(lm["x"], lm["z"]), r, "wahrzeichen"])
	for h in track["hills"]:
		ctx["circles"].append([h["c"], float(h["r"]) * 0.9, "huegel"])
	for v in track.get("hochstrassen", []):
		for o in v.get("gleis_occ", []):
			ctx["circles"].append([Vector2(o["pos"].x, o["pos"].z), float(o["r"]) + 4.0, "gleis"])
	# Ausfahrten: die Auffahrt zur Autobahn (bzw. die Verbindung zum Ring) läuft vom Ende gerade weiter
	for key in ["world_exit", "world_exit2"]:
		var ex: Dictionary = track[key]
		if not ex.is_empty() and (ctx["loop"] or key == "world_exit"):
			var a: Vector3 = ex["end"] - ex["dir"] * 10.0
			var b: Vector3 = ex["end"] + ex["dir"] * 260.0
			ctx["caps"].append([Vector2(a.x, a.z), Vector2(b.x, b.z), 34.0])
	return ctx


static func _add_branch_cells(ctx: Dictionary, p: Dictionary) -> void:
	var c: Curve3D = p["curve"]
	var L := c.get_baked_length()
	var reach := edge(p, 1.0) if p.has("net") else float(p["half_w"]) + (3.0 if p["kind"] == "fork" else 0.0)
	var d := 0.0
	while d <= L:
		var q := c.sample_baked(d)
		var key := Vector2i(floori(q.x / MAIN_CELL), floori(q.z / MAIN_CELL))
		if not ctx["bcells"].has(key):
			ctx["bcells"][key] = []
		ctx["bcells"][key].append([Vector2(q.x, q.z), reach, int(p["id"])])
		d += 2.0


## Abstand zur Fahrbahnkante der Hauptstraße (bis max genau) und Weg-Meter des nächsten Punkts
static func _main_near(ctx: Dictionary, q: Vector2, mx := 80.0) -> Vector2:
	var cells: Dictionary = ctx["mcells"]
	var mp: PackedVector2Array = ctx["mp"]
	var mh: PackedFloat32Array = ctx["mh"]
	var md: PackedFloat32Array = ctx["md"]
	var best := mx
	var bd := -1.0
	var r := int(ceil(mx / MAIN_CELL))
	var key := Vector2i(floori(q.x / MAIN_CELL), floori(q.y / MAIN_CELL))
	for gx in range(key.x - r, key.x + r + 1):
		for gz in range(key.y - r, key.y + r + 1):
			var arr = cells.get(Vector2i(gx, gz))
			if arr == null:
				continue
			for k in arr:
				var dist := q.distance_to(mp[k]) - mh[k]
				if dist < best:
					best = dist
					bd = md[k]
	return Vector2(best, bd)


## Abstand zur Kante (Gehweg) des nächsten anderen Abzweigs; skip: Wege, die hier einmünden dürfen
static func _branch_near(ctx: Dictionary, q: Vector2, skip: Array, mx := 60.0) -> float:
	var cells: Dictionary = ctx["bcells"]
	var best := mx
	var r := int(ceil(mx / MAIN_CELL))
	var key := Vector2i(floori(q.x / MAIN_CELL), floori(q.y / MAIN_CELL))
	for gx in range(key.x - r, key.x + r + 1):
		for gz in range(key.y - r, key.y + r + 1):
			var arr = cells.get(Vector2i(gx, gz))
			if arr == null:
				continue
			for e in arr:
				if e[2] in skip:
					continue
				best = minf(best, q.distance_to(e[0]) - e[1])
	return best


## Liegt q (mit Radius r) auf einer fremden Fahrbahn der Welt, an einer Ausfahrt, einem Wahrzeichen, Hügel, Gleisfeld?
static func _blocked(ctx: Dictionary, q: Vector2, r: float) -> String:
	var kk := Vector2i(floori(q.x / 32.0), floori(q.y / 32.0))
	for gx in range(kk.x - 2, kk.x + 3):
		for gz in range(kk.y - 2, kk.y + 3):
			for e in ctx["kcells"].get(Vector2i(gx, gz), []):
				if q.distance_to(e[0]) < r + e[1]:
					return "keepout"
	for c in ctx["circles"]:
		if q.distance_to(c[0]) < r + c[1]:
			return c[2]
	for cp in ctx["caps"]:
		var a: Vector2 = cp[0]
		var ab: Vector2 = cp[1] - a
		var t := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		if q.distance_to(a + ab * t) < r + cp[2]:
			return "ausfahrt"
	var track: Dictionary = ctx["track"]
	var q3 := Vector3(q.x, 0.0, q.y)
	if not track["rivers"].is_empty() and Track._river_near(track, q3, r + 8.0) < r + 6.0:
		return "wasser"
	if Track._in_lake(track, q3, r + 6.0):
		return "wasser"
	if Track._rail_clearance(track, q3) < r + 6.0:
		return "bahn"
	if track.has("terrain") and Track.Design.terrain_h(track, q3) > 0.3:
		return "gelaende"
	for tri in track["parks"]:
		if Geometry2D.point_is_inside_triangle(q, Vector2(tri[0].x, tri[0].z), Vector2(tri[1].x, tri[1].z), Vector2(tri[2].x, tri[2].z)):
			return "park"
	return ""


## Echte Städte: wie viele Häuser lägen auf dem Weg (die Bebauung weicht ihm aus)? Wenige heißt: er folgt einer echten
## Straße zwischen den Häusern.
static func _osm_cost(ctx: Dictionary, pts: PackedVector2Array, reach: float) -> int:
	if not ctx["osm"]:
		return 0
	var hit := {}
	for q in pts:
		var kk := Vector2i(floori(q.x / 24.0), floori(q.y / 24.0))
		for gx in range(kk.x - 1, kk.x + 2):
			for gz in range(kk.y - 1, kk.y + 2):
				var arr = ctx["ocells"].get(Vector2i(gx, gz))
				if arr == null:
					continue
				for i in arr.size():
					var e: Array = arr[i]
					if q.distance_to(e[0]) < reach + e[1]:
						hit[Vector3i(gx, gz, i)] = true
	return hit.size()


## Kann die Hauptstraße bei d eine Einmündung zur Seite s aufnehmen? (flach, kein Tunnel/Trog/Brücke, keine Hochbahn
## auf der Seite, kein Mittelstreifen, kein Bahnübergang, kein anderer Abzweig, nicht zu kurvig)
static func _mouth_ok(ctx: Dictionary, d: float, s: float, w: float, allow_d := -1e9) -> bool:
	var track: Dictionary = ctx["track"]
	# eigene Einmündungen (Abstand zueinander); an allow_d mündet gegenüber schon eine (Kreuzung in einer Flucht)
	for z in ctx["mz"]:
		if absf(z[0] - allow_d) > 3.0 and _ldist(ctx, d, z[0]) < z[1] + w + 16.0:
			return _w("mund_eigen")
	var curve: Curve3D = ctx["curve"]
	var L: float = ctx["L"]
	if not ctx["loop"]:
		var end: float = minf(L - 60.0, track["finish"] - 30.0)
		if d < 50.0 or d > end:
			return _w("mund_ende")
	var dd := d - w - 18.0
	while dd <= d + w + 18.0:
		var x := fposmod(dd, L) if ctx["loop"] else dd
		if _zone(ctx, x) or Track._trough_at(track, x) != 0 or not Track.tunnel_at(track, x, 12.0).is_empty() \
				or not Track.bridge_at(track, x).is_empty() or absf(Track.elev_at(curve, x)) > 0.05 or Track._el_side(track, x, 12.0) == s \
				or Track.median_at(track, x) > 0.05:
			return _w("mund_zone")
		dd += 5.0
	if track["crossing_d"] >= 0.0 and absf(d - track["crossing_d"]) < 70.0:
		return _w("mund_bahn")
	if Track._min_radius(curve, d, ctx["loop"]) < 45.0:
		return _w("mund_kurve")
	return true


static func _zone(ctx: Dictionary, d: float) -> bool:
	var track: Dictionary = ctx["track"]
	var L: float = track["length"]
	for z in track["zones"]:
		var skip := false
		for jd in ctx["skip_zones"]:
			if is_equal_approx(z["from"], jd - 40.0) and is_equal_approx(z["to"], jd + 40.0):
				skip = true
		if skip:
			continue
		for sh in ([0.0, L, -L] if track["loop"] else [0.0]):
			if d + sh > z["from"] and d + sh < z["to"]:
				return true
	return false


## Straßenklasse für ein Viertel
static func _pick_cls(ctx: Dictionary, d: float, rng: RandomNumberGenerator) -> String:
	var track: Dictionary = ctx["track"]
	var arr: Array = track["districts"]
	var key: String = arr[clampi(int(fposmod(d, ctx["L"]) / Track.DISTRICT_LEN), 0, arr.size() - 1)]
	var wts: Dictionary = CLS_BY.get(key, {"strasse": 1.0})
	var tot := 0.0
	for k in wts:
		tot += wts[k]
	var x := rng.randf() * tot
	for k in wts:
		x -= wts[k]
		if x <= 0.0:
			return k
	return "strasse"


static func _district_key(ctx: Dictionary, d: float) -> String:
	var arr: Array = ctx["track"]["districts"]
	return arr[clampi(int(fposmod(d, ctx["L"]) / Track.DISTRICT_LEN), 0, arr.size() - 1)]


## Querschnitt einer neuen Straße: Klasse, Gehweg, Streifen je Seite
static func _section(ctx: Dictionary, cls: String, d: float, rng: RandomNumberGenerator) -> Dictionary:
	var c: Dictionary = CLS[cls]
	var sec := {"cls": cls, "half": c["half"], "walk": c["walk"], "lanes": c["lanes"], "strip": [0.0, 0.0], "strip_kind": ["", ""],
		"cobble": 1.0 if cls == "gasse" and _district_key(ctx, d) in COBBLE else 0.0}
	if cls == "gasse":
		return sec
	for i in 2:
		var x := rng.randf()
		var green: bool = Track.DISTRICTS.get(_district_key(ctx, d), {}).get("trees", 0.3) > 0.3
		if cls == "breit":
			if x < 0.45:
				sec["strip_kind"][i] = "gruen" if green or x < 0.2 else "park"
			elif x < 0.85:
				sec["strip_kind"][i] = "park"
		elif x < 0.42:
			sec["strip_kind"][i] = "park"
		elif x < 0.6 and green:
			sec["strip_kind"][i] = "gruen"
		if sec["strip_kind"][i] != "":
			sec["strip"][i] = STRIP_W
	return sec


## Abstand von der Mitte bis zur Hauskante (Gehweg hinten) auf Seite sd (-1 links, +1 rechts in Wegrichtung)
static func edge(p: Dictionary, sd: float) -> float:
	if not p.has("net"):
		return float(p["half_w"])
	return float(p["half_w"]) + float(p["strip"][0 if sd < 0.0 else 1]) + float(p["walk"])


static func reach(p: Dictionary) -> float:
	return maxf(edge(p, -1.0), edge(p, 1.0))


# --- Formen ----------------------------------------------------------------------------------------------------------

## Polygonzug mit gerundeten Ecken (Radius je Eckpunkt, rad[0] und rad[-1] ungenutzt), gleichmäßig alle step m
static func _fillet(pts: Array, rad: Array, step: float) -> PackedVector2Array:
	var dense := PackedVector2Array()
	dense.append(pts[0])
	for i in range(1, pts.size() - 1):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var c: Vector2 = pts[i + 1]
		if rad.is_empty() or float(rad[i]) <= 0.0:
			dense.append(b)
			continue
		var u := (b - a).normalized()
		var v := (c - b).normalized()
		var phi := u.angle_to(v)
		if absf(phi) < 0.01:
			dense.append(b)
			continue
		var r: float = rad[i]
		var t := r * tan(absf(phi) / 2.0)
		# erstes und letztes Stück gehören je einer Ecke ganz, die übrigen teilen sich zwei Ecken
		var tmax := minf(a.distance_to(b) * (0.98 if i == 1 else 0.49), b.distance_to(c) * (0.98 if i == pts.size() - 2 else 0.49))
		if t > tmax:
			t = tmax
			r = t / tan(absf(phi) / 2.0)
		var ts := b - u * t
		var nrm := Vector2(-u.y, u.x) * signf(phi)
		var ctr := ts + nrm * r
		var n := maxi(int(absf(phi) * r / 2.0), 3)
		for k in n + 1:
			var ang := phi * float(k) / n
			dense.append(ctr + (ts - ctr).rotated(ang))
	dense.append(pts[pts.size() - 1])
	# gleichmäßig neu abtasten
	var out := PackedVector2Array()
	out.append(dense[0])
	var acc := 0.0
	for i in range(1, dense.size()):
		var a2: Vector2 = dense[i - 1]
		var b2: Vector2 = dense[i]
		var sl := a2.distance_to(b2)
		var pos := step - acc
		while pos <= sl:
			out.append(a2.lerp(b2, pos / sl))
			pos += step
		acc = sl - (pos - step)
	if out[out.size() - 1].distance_to(dense[dense.size() - 1]) > 0.3:
		out.append(dense[dense.size() - 1])
	return out


## (Weg-Meter, Abstand) neben der Hauptstraße -> Streckenkoordinaten
static func _map(ctx: Dictionary, al: PackedVector2Array, s: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var curve: Curve3D = ctx["curve"]
	for v in al:
		var x := fposmod(v.x, ctx["L"]) if ctx["loop"] else v.x
		out.append(Track._beside(curve, x, v.y * s))
	return out


static func _flat2(pts: PackedVector3Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in pts:
		out.append(Vector2(q.x, q.z))
	return out


## Engster Bogen eines Linienzugs (aus drei Punkten im Abstand k)
static func _tightest(pts: PackedVector2Array, k := 3) -> float:
	var best := 1e9
	for i in range(k, pts.size() - k):
		var a := pts[i - k]
		var b := pts[i]
		var c := pts[i + k]
		var area := absf((b - a).cross(c - a)) / 2.0
		if area > 1e-3:
			best = minf(best, a.distance_to(b) * b.distance_to(c) * c.distance_to(a) / (4.0 * area))
	return best


## Prüft einen Weg (Punkte alle gut 2,5 m, Anfang und Ende an der Hauptstraße bzw. an Wegen aus skip): Abstand zur
## Hauptstraße (nur der eigene Abschnitt darf nahe sein), zu anderen Wegen, Sperrflächen, Wasser, Wahrzeichen.
## mouths: Weg-Meter der eigenen Einmündungen in die Hauptstraße; behind: Seite, auf der dahinter Häuser Platz brauchen
static func _check(ctx: Dictionary, pts: PackedVector3Array, sec: Dictionary, mouths: Array, skip: Array) -> bool:
	var rr: float = sec["half"] + maxf(sec["strip"][0], sec["strip"][1]) + sec["walk"]
	var n := pts.size()
	var flat := _flat2(pts)
	if _tightest(flat) < (15.0 if sec["cls"] == "gasse" else 20.0):
		return _w("eng")
	# Knick: neben einer engen Kurve der Hauptstraße kann die Form umklappen (kleiner als die Prüfung oben sieht)
	for i in range(1, n - 1):
		var u := flat[i] - flat[i - 1]
		var v := flat[i + 1] - flat[i]
		if u.length() < 0.5 or v.length() < 0.5 or absf(u.angle_to(v)) > deg_to_rad(30.0):
			return _w("knick")
	var acc := 0.0
	var total := 0.0
	for i in range(1, n):
		total += flat[i].distance_to(flat[i - 1])
	for i in n:
		if i > 0:
			acc += flat[i].distance_to(flat[i - 1])
		var q := flat[i]
		var mn := _main_near(ctx, q, Track.WALK + rr + 8.0)
		var from_end := minf(acc, total - acc)
		# an der eigenen Einmündung darf die Hauptstraße nah sein, sonst nicht
		var own := false
		for md in mouths:
			var dl := absf(mn.y - md)
			if ctx["loop"]:
				dl = minf(dl, ctx["L"] - dl)
			if dl < 48.0 + from_end * 0.4:
				own = true
		if mn.x < Track.WALK + rr + 6.0:
			if not own or from_end > 70.0:
				return _w("hauptstrasse")
			if mn.x < -1.0 and from_end > Track.HALF_W + 16.0:
				return _w("hauptstrasse")
		if from_end > Track.HALF_W + Track.WALK + 4.0 or skip.size() > 0:
			var bn := _branch_near(ctx, q, skip if from_end < 40.0 else [], rr + 8.0)
			if bn < rr + 6.0:
				return _w("abzweig")
		if mn.x > Track.WALK + 1.0:
			var why_b := _blocked(ctx, q, rr + 2.0)
			if why_b != "":
				return _w(why_b)
	return true


## Weg anlegen (Kurve, Querschnitt, Suchraster)
static func _add(ctx: Dictionary, kind: String, pts: PackedVector3Array, sec: Dictionary, from: float, to: float, side: float,
		extra := {}) -> Dictionary:
	var track: Dictionary = ctx["track"]
	var c := Curve3D.new()
	c.bake_interval = 1.0
	for q in pts:
		c.add_point(q)
	var p := {"id": track["paths"].size(), "kind": kind, "curve": c, "half_w": sec["half"], "length": c.get_baked_length(),
		"from": from, "to": to, "closed": false, "side": side, "net": true, "cls": sec["cls"], "walk": sec["walk"],
		"strip": sec["strip"].duplicate(), "strip_kind": sec["strip_kind"].duplicate(), "lanes": sec["lanes"],
		"cobble": sec["cobble"], "ends": []}
	p.merge(extra, true)
	track["paths"].append(p)
	_add_branch_cells(ctx, p)
	return p


static func _mouth_zone(ctx: Dictionary, d: float, w: float) -> void:
	ctx["mz"].append([d, w + 4.0])


# --- Querverbindungen ------------------------------------------------------------------------------------------------

## Wo die Hauptstraße sich selbst nahe kommt (innen im Rundkurs, U-Bögen der Sprints): eine Straße quer hinüber.
## Kandidaten: Punktpaare 70-330 m auseinander, entlang der Strecke viel weiter; Bogen (kubisch) von Einmündung zu
## Einmündung, die Enden schräg oder rechtwinklig. In echten Städten zählt, wie viele Häuser im Weg stünden: so folgen
## die Querverbindungen den echten Straßen.
static func _plan_links(ctx: Dictionary, rng: RandomNumberGenerator) -> void:
	var track: Dictionary = ctx["track"]
	var curve: Curve3D = ctx["curve"]
	var L: float = ctx["L"]
	var have := 0
	for p in track["paths"]:
		if p.get("cross", false):
			have += 1
	var want := (2 if L < 2500.0 else 3) if ctx["loop"] else (1 if L < 2000.0 else 2)
	if ctx["osm"]:
		want += 1
	want -= have
	if want <= 0:
		return
	# Abtastung alle 20 m mit Raster; echte Städte: nur Stellen mit einer Lücke zwischen den Häusern (Mitte jeder Lücke,
	# Abtastung alle 4 m), dort beginnt meist eine echte Seitenstraße
	var sp := []
	var grid := {}
	if ctx["osm"] and not _any_pair(ctx):
		return
	var mouths := _gap_mouths(ctx) if ctx["osm"] else []
	if ctx["osm"] and mouths.is_empty():
		return
	var d := 0.0
	var mi := 0
	while (ctx["osm"] and mi < mouths.size()) or (not ctx["osm"] and d < L):
		if ctx["osm"]:
			d = mouths[mi][0]
		var f := Track.frame_at(curve, d)
		var q := Vector2(f["pos"].x, f["pos"].z)
		var e := [d, q, Vector2(f["right"].x, f["right"].z), mouths[mi][1] if ctx["osm"] else 0.0]
		var key := Vector2i(floori(q.x / 110.0), floori(q.y / 110.0))
		if not grid.has(key):
			grid[key] = []
		grid[key].append(sp.size())
		sp.append(e)
		d += 20.0
		mi += 1
	var cands := []
	for i in sp.size():
		var a: Array = sp[i]
		var ka := Vector2i(floori(a[1].x / 110.0), floori(a[1].y / 110.0))
		for gx in range(ka.x - 6, ka.x + 7):
			for gz in range(ka.y - 6, ka.y + 7):
				for j in grid.get(Vector2i(gx, gz), []):
					if j <= i:
						continue
					var b: Array = sp[j]
					var dist: float = a[1].distance_to(b[1])
					if dist < 70.0 or dist > (560.0 if ctx["loop"] or ctx["osm"] else 330.0):
						continue
					var along: float = absf(b[0] - a[0])
					if ctx["loop"]:
						along = minf(along, L - along)
					if along < maxf(dist * (1.4 if ctx["loop"] else 2.6), 260.0):
						continue
					var dir: Vector2 = (b[1] - a[1]) / dist
					# beide Enden zeigen ungefähr zur anderen Seite (nicht entlang der Straße)
					var sa: float = dir.dot(a[2])
					var sb: float = -dir.dot(b[2])
					if absf(sa) < 0.6 or absf(sb) < 0.6:
						continue
					if ctx["osm"] and (signf(sa) != a[3] or signf(sb) != b[3]):
						continue  # Lücke auf der anderen Seite
					cands.append([dist + rng.randf() * 60.0, i, j, signf(sa), signf(sb)])
	cands.sort_custom(func(x, y): return x[0] < y[0])
	why["Q_kandidaten"] = why.get("Q_kandidaten", 0) + cands.size()
	var tried := 0
	var made := []
	var mouth_cache := {}
	var mouth_fine := func(i: int, sd: float) -> bool:
		var key := Vector2i(i, int(sd))
		if not mouth_cache.has(key):
			mouth_cache[key] = _mouth_ok(ctx, sp[i][0], sd, CLS["strasse"]["half"] + CLS["strasse"]["walk"])
		return mouth_cache[key]
	for cd in cands:
		if want <= 0 or tried > 40:
			break
		if not mouth_fine.call(cd[1], cd[3]) or not mouth_fine.call(cd[2], cd[4]):
			continue
		var a: Array = sp[cd[1]]
		var b: Array = sp[cd[2]]
		var near_made := false
		for m in made:
			if minf(_ldist(ctx, a[0], m[0]), _ldist(ctx, a[0], m[1])) < 160.0 or minf(_ldist(ctx, b[0], m[0]), _ldist(ctx, b[0], m[1])) < 160.0:
				near_made = true
		if near_made:
			continue
		tried += 1
		var best := {}
		if ctx["osm"]:
			best = _route_link(ctx, a[0], b[0], cd[3], cd[4], rng)
		else:
			for att in 2:
				var r := _try_link(ctx, a[0], b[0], cd[3], cd[4], rng, att)
				if not r.is_empty() and (best.is_empty() or r["cost"] < best["cost"]):
					best = r
		if best.is_empty():
			continue
		var p := _add(ctx, "lane", best["pts"], best["sec"], a[0], b[0], 0.0, {"cross": true})
		p["ends"] = [{"at": 0, "d": a[0]}, {"at": 0, "d": b[0]}]
		_mouth_zone(ctx, a[0], best["sec"]["half"] + best["sec"]["walk"])
		_mouth_zone(ctx, b[0], best["sec"]["half"] + best["sec"]["walk"])
		made.append([a[0], b[0]])
		want -= 1


## Echte Städte: Querverbindung durch die Lücken zwischen den Häusern (A* auf einem 5-m-Raster, Häuser samt Abstand
## teuer), also möglichst entlang einer echten Straße. Von einer Lücke an der Hauptstraße (hinter ihrem Gehweg) zur
## anderen, gestrafft und mit gerundeten Ecken. Straße mit Gehwegen, wo sie hindurchpasst, sonst Gasse.
static func _route_link(ctx: Dictionary, da: float, db: float, sa: float, sb: float, rng: RandomNumberGenerator) -> Dictionary:
	var curve: Curve3D = ctx["curve"]
	var gw: float = CLS["gasse"]["half"]
	if not _mouth_ok(ctx, da, sa, gw) or not _mouth_ok(ctx, db, sb, gw):
		return {}
	var g = _astar(ctx)
	if g == null:
		return {}
	var fa := Track.frame_at(curve, da)
	var fb := Track.frame_at(curve, db)
	var pa: Vector3 = fa["pos"] + fa["right"] * sa * (Track.hw(ctx["track"], da) + Track.WALK + gw + 12.0)
	var pb: Vector3 = fb["pos"] + fb["right"] * sb * (Track.hw(ctx["track"], db) + Track.WALK + gw + 12.0)
	var ia := _cell(g, Vector2(pa.x, pa.z))
	var ib := _cell(g, Vector2(pb.x, pb.z))
	var astar: AStarGrid2D = g["g"]
	if not astar.region.has_point(ia) or not astar.region.has_point(ib) or astar.is_point_solid(ia) or astar.is_point_solid(ib):
		return _w_d("astar_ende")
	var ids: Array[Vector2i] = astar.get_id_path(ia, ib)
	if ids.size() < 3:
		return _w_d("astar_kein_weg")
	# Linienzug: Einmündung, gerades Stück, Weg durch die Lücken (gestrafft: Punkte, zu denen die Sicht frei ist,
	# werden übersprungen), gerades Stück, Einmündung; Ecken mit 26 m Radius gerundet
	var cells := [Vector2(pa.x, pa.z)]
	for k in range(1, ids.size() - 1):
		cells.append(g["lo"] + (Vector2(ids[k]) + Vector2(0.5, 0.5)) * g["cell"])
	cells.append(Vector2(pb.x, pb.z))
	var raw := [Vector2(fa["pos"].x, fa["pos"].z)]
	var i0 := 0
	raw.append(cells[0])
	while i0 < cells.size() - 1:
		var j := cells.size() - 1
		while j > i0 + 1 and not _los(g, cells[i0], cells[j]):
			j -= 1
		raw.append(cells[j])
		i0 = j
	raw.append(Vector2(fb["pos"].x, fb["pos"].z))
	var rad := [0.0]
	for k in range(1, raw.size() - 1):
		rad.append(26.0)
	rad.append(0.0)
	var flat := _fillet(raw, rad, 2.5)
	if flat.size() < 8:
		return {}
	var length := 0.0
	for k in range(1, flat.size()):
		length += flat[k].distance_to(flat[k - 1])
	if length > fa["pos"].distance_to(fb["pos"]) * 1.6 + 60.0:
		return _w_d("astar_umweg")
	var pts := PackedVector3Array()
	for q in flat:
		pts.append(Vector3(q.x, 0.0, q.y))
	# breiteste Klasse, die hindurchpasst (kaum ein Haus im Weg)
	for cls in ["strasse", "gasse"]:
		var sec := _section(ctx, cls, da, rng)
		sec["strip"] = [0.0, 0.0]
		sec["strip_kind"] = ["", ""]
		var w: float = sec["half"] + sec["walk"]
		var cost := _osm_cost(ctx, flat.slice(10, flat.size() - 10), w)
		if cost > (4 if cls == "strasse" else 14):
			continue
		if not _mouth_ok(ctx, da, sa, w) or not _mouth_ok(ctx, db, sb, w) or not _check(ctx, pts, sec, [da, db], []):
			continue
		return {"pts": pts, "sec": sec, "cost": cost}
	return _w_d("haeuser")


## Echte Städte: Stellen an der Hauptstraße, an denen hinter dem Gehweg eine Lücke zwischen den Häusern beginnt
## ([Weg-Meter, Seite], Mitte jeder Lücke)
static func _gap_mouths(ctx: Dictionary) -> Array:
	var g = _astar(ctx)
	if g == null:
		return []
	var astar: AStarGrid2D = g["g"]
	var curve: Curve3D = ctx["curve"]
	var L: float = ctx["L"]
	var gw: float = CLS["gasse"]["half"]
	var out := []
	for s in [-1.0, 1.0]:
		var run := []
		var d := 0.0
		while d < L + 4.0:
			var free := false
			if d < L:
				var f := Track.frame_at(curve, d)
				var lead: float = Track.hw(ctx["track"], d) + Track.WALK + gw + 12.0
				free = true
				for k in [lead, lead + 5.0]:
					var q: Vector3 = f["pos"] + f["right"] * s * k
					var c := _cell(g, Vector2(q.x, q.z))
					if not astar.region.has_point(c) or astar.is_point_solid(c) or astar.get_point_weight_scale(c) > 40.0:
						free = false
			if free:
				run.append(d)
			elif not run.is_empty():
				if run.size() >= 2:
					out.append([run[run.size() / 2], s])
				run = []
			d += 4.0
	out.sort_custom(func(a, b): return a[0] < b[0])
	return out


## Freie Sicht im Raster von a nach b (keine gesperrte Zelle, kein Haus selbst; der Rand um Häuser zählt als frei)
static func _los(g: Dictionary, a: Vector2, b: Vector2) -> bool:
	var astar: AStarGrid2D = g["g"]
	var n := maxi(int(a.distance_to(b) / 2.0), 1)
	for k in n + 1:
		var c := _cell(g, a.lerp(b, float(k) / n))
		if not astar.region.has_point(c) or astar.is_point_solid(c) or astar.get_point_weight_scale(c) > 40.0:
			return false
	return true


static func _cell(g: Dictionary, q: Vector2) -> Vector2i:
	var v: Vector2 = (q - g["lo"]) / g["cell"]
	return Vector2i(floori(v.x), floori(v.y))


## Raster für die Wegsuche (einmal je Stadt): Häuser der echten Stadt samt Abstand für eine Gasse teuer (das Haus
## selbst sehr teuer), gesperrt sind Hauptstraße samt Gehweg und Abstand, Wasser, Wahrzeichen, Sperrflächen. Rundkurse
## nur innen (dort laufen die Querverbindungen), sonst rund um die Strecke.
static func _astar(ctx: Dictionary) -> Variant:
	if ctx.has("astar"):
		return ctx["astar"]
	ctx["astar"] = null
	var track: Dictionary = ctx["track"]
	var mp: PackedVector2Array = ctx["mp"]
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for q in mp:
		lo = lo.min(q)
		hi = hi.max(q)
	lo -= Vector2(40, 40)
	hi += Vector2(40, 40)
	var cell := 5.0
	var nx := int((hi.x - lo.x) / cell) + 1
	var nz := int((hi.y - lo.y) / cell) + 1
	if nx * nz > 200000:
		return null
	var clear: float = CLS["gasse"]["half"] + 0.5
	var g := AStarGrid2D.new()
	g.region = Rect2i(0, 0, nx, nz)
	g.cell_size = Vector2(cell, cell)
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	g.update()
	var out := {"g": g, "lo": lo, "cell": cell}
	var poly := PackedVector2Array()
	if ctx["loop"]:
		for k in range(0, mp.size(), 4):
			poly.append(mp[k])
	var data: Array = track["city"].get("buildings", [])
	for i in range(0, data.size(), 6):
		var c := Vector2(data[i], data[i + 1])
		if c.x < lo.x or c.y < lo.y or c.x > hi.x or c.y > hi.y:
			continue
		if not poly.is_empty() and not Geometry2D.is_point_in_polygon(c, poly):
			continue
		var ang: float = data[i + 4]
		var along := Vector2(cos(ang), sin(ang))
		# Häuser nicht gesperrt, aber teuer (Abstand 30-mal, das Haus selbst 80-mal): der Weg folgt den Lücken, wo es
		# welche gibt, und reißt sonst möglichst wenige Häuser ab (die Bebauung weicht ihm aus)
		_mark_rect(g, out, c, along, Vector2(-along.y, along.x), data[i + 2] * 0.5 + clear, data[i + 3] * 0.5 + clear, 30.0)
		_mark_rect(g, out, c, along, Vector2(-along.y, along.x), data[i + 2] * 0.5, data[i + 3] * 0.5, 80.0)
	# Hauptstraße: dort entlang führt der Weg nicht (er soll quer hindurch)
	var mh: PackedFloat32Array = ctx["mh"]
	for k in range(0, mp.size(), 4):
		_mark_disc(g, out, mp[k], mh[k] + Track.WALK + clear + 6.0)
	for cc in ctx["circles"]:
		_mark_disc(g, out, cc[0], cc[1] + clear)
	for kk in ctx["kcells"]:
		for e in ctx["kcells"][kk]:
			_mark_disc(g, out, e[0], e[1] + clear)
	for rv in track["rivers"]:
		var rp: PackedVector2Array = rv["pts"]
		var rh: PackedFloat32Array = rv["hw"]
		for k in rp.size() - 1:
			var hr: float = maxf(rh[k], rh[k + 1])
			if hr < 1.5:
				continue
			var n := maxi(int(rp[k].distance_to(rp[k + 1]) / 4.0), 1)
			for j in n + 1:
				_mark_disc(g, out, rp[k].lerp(rp[k + 1], float(j) / n), hr + clear + 4.0)
	ctx["astar"] = out
	return out


static func _mark_rect(g: AStarGrid2D, out: Dictionary, c: Vector2, u: Vector2, v: Vector2, hu: float, hv: float, wt := 0.0) -> void:
	var ext := Vector2(absf(u.x) * hu + absf(v.x) * hv, absf(u.y) * hu + absf(v.y) * hv)  # Hülle des gedrehten Rechtecks
	var lo: Vector2 = out["lo"]
	var cell: float = out["cell"]
	var c0 := _cell(out, c - ext)
	var c1 := _cell(out, c + ext)
	for ix in range(maxi(c0.x, 0), mini(c1.x, g.region.size.x - 1) + 1):
		for iz in range(maxi(c0.y, 0), mini(c1.y, g.region.size.y - 1) + 1):
			var q: Vector2 = lo + Vector2(ix + 0.5, iz + 0.5) * cell - c
			if absf(q.dot(u)) <= hu and absf(q.dot(v)) <= hv:
				var id := Vector2i(ix, iz)
				if wt <= 0.0:
					g.set_point_solid(id, true)
				elif g.get_point_weight_scale(id) < wt:
					g.set_point_weight_scale(id, wt)


static func _mark_disc(g: AStarGrid2D, out: Dictionary, c: Vector2, r: float) -> void:
	var lo: Vector2 = out["lo"]
	var cell: float = out["cell"]
	var c0 := _cell(out, c - Vector2(r, r))
	var c1 := _cell(out, c + Vector2(r, r))
	for ix in range(maxi(c0.x, 0), mini(c1.x, g.region.size.x - 1) + 1):
		for iz in range(maxi(c0.y, 0), mini(c1.y, g.region.size.y - 1) + 1):
			if (lo + Vector2(ix + 0.5, iz + 0.5) * cell).distance_to(c) <= r:
				g.set_point_solid(Vector2i(ix, iz), true)


## Vorprüfung für die echten Städte (das Raster für die Wegsuche kostet): gibt es Stellen der Hauptstraße, die sich
## quer gegenüberliegen (etwas großzügiger als die eigentliche Suche)?
static func _any_pair(ctx: Dictionary) -> bool:
	var curve: Curve3D = ctx["curve"]
	var L: float = ctx["L"]
	var sp := []
	var d := 0.0
	while d < L:
		var f := Track.frame_at(curve, d)
		sp.append([d, Vector2(f["pos"].x, f["pos"].z), Vector2(f["right"].x, f["right"].z)])
		d += 10.0
	for i in sp.size():
		for j in range(i + 1, sp.size()):
			var dist: float = sp[i][1].distance_to(sp[j][1])
			if dist < 60.0 or dist > 580.0:
				continue
			var along: float = _ldist(ctx, sp[i][0], sp[j][0])
			if along < maxf(dist * (1.3 if ctx["loop"] else 2.4), 240.0):
				continue
			var dir: Vector2 = (sp[j][1] - sp[i][1]) / dist
			if absf(dir.dot(sp[i][2])) >= 0.5 and absf(dir.dot(sp[j][2])) >= 0.5:
				return true
	return false


static func _ldist(ctx: Dictionary, a: float, b: float) -> float:
	var x := absf(a - b)
	return minf(x, ctx["L"] - x) if ctx["loop"] else x


static func _try_link(ctx: Dictionary, da: float, db: float, sa: float, sb: float, rng: RandomNumberGenerator, att: int) -> Dictionary:
	var curve: Curve3D = ctx["curve"]
	var cls := _pick_cls(ctx, da, rng)
	if cls == "gasse" and rng.randf() < 0.6:
		cls = "strasse"  # Querverbindungen sind meist richtige Straßen
	var sec := _section(ctx, cls, da, rng)
	var w: float = sec["half"] + sec["walk"]
	if not _mouth_ok(ctx, da, sa, w) or not _mouth_ok(ctx, db, sb, w):
		return {}
	var fa := Track.frame_at(curve, da)
	var fb := Track.frame_at(curve, db)
	var pa: Vector3 = fa["pos"]
	var pb: Vector3 = fb["pos"]
	var span := pa.distance_to(pb)
	# Ende schräg: Richtung um bis zu 32° zur Straße hin gedreht (in Richtung der anderen Einmündung)
	var ta: Vector3 = fa["right"] * sa
	var tb: Vector3 = fb["right"] * sb
	var toward: Vector3 = (pb - pa).normalized()
	var ka: float = [0.0, 0.45, -0.3, 0.55][att]
	var kb: float = [0.0, -0.35, 0.5, 0.3][att]
	ta = (ta + (toward - ta * ta.dot(toward)) * ka).normalized()
	tb = (tb + (-toward - tb * tb.dot(-toward)) * kb).normalized()
	var k: float = [0.38, 0.32, 0.42, 0.3][att]
	var pts := PackedVector3Array()
	var n := maxi(int(span * 1.3 / 2.5), 12)
	var c1: Vector3 = pa + ta * span * k
	var c2: Vector3 = pb + tb * span * k
	var raw := []
	for j in n + 1:
		var t := float(j) / n
		var u := 1.0 - t
		var q: Vector3 = pa * u * u * u + c1 * 3.0 * u * u * t + c2 * 3.0 * u * t * t + pb * t * t * t
		raw.append(Vector2(q.x, q.z))
	var flat := _fillet(raw, [], 2.5)  # nur gleichmäßig abtasten
	for q in flat:
		pts.append(Vector3(q.x, 0.0, q.y))
	if not _check(ctx, pts, sec, [da, db], []):
		return {}
	var cost := _osm_cost(ctx, flat.slice(10, flat.size() - 10), sec["half"] + sec["walk"])
	if cost > (5 if ctx["osm"] else 0):
		return _w_d("haeuser")
	return {"pts": pts, "sec": sec, "cost": cost * 30.0 + span * 0.05}


static func _w_d(k: String) -> Dictionary:
	_w(k)
	return {}


# --- Parallelstraßen, Kreuzungen, Verbindungen -----------------------------------------------------------------------

## Entlang der Hauptstraße Blöcke zum Drumherumfahren: Straße hinaus (schräg oder rechtwinklig), im weiten Bogen
## hinter die erste Häuserreihe, dort schwingend weiter, im Bogen zurück. Mal gegenüber an derselben Stelle eine
## zweite (Kreuzung), bei langen Blöcken eine Verbindung in der Mitte.
static func _plan_parallels(ctx: Dictionary, rng: RandomNumberGenerator) -> void:
	var track: Dictionary = ctx["track"]
	var L: float = ctx["L"]
	var end: float = L - 70.0 if ctx["loop"] else minf(L - 90.0, track["finish"] - 40.0)
	var d := rng.randf_range(50.0, 120.0)
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	while d < end:
		var placed := {}
		var span := rng.randf_range(90.0, 170.0) if rng.randf() < 0.6 else rng.randf_range(170.0, 300.0)
		if d + span < end:
			for s in [side, -side]:
				placed = _try_parallel(ctx, d, d + span, s, rng)
				if not placed.is_empty():
					side = -s
					break
		if placed.is_empty():
			d += 18.0
			continue
		# Kreuzung: gegenüber eine Straße in derselben Flucht, an der zweiten Einmündung nach vorn oder an der ersten
		# nach hinten (je zwei Längen versucht)
		var s0: float = placed["side"]
		var next_d: float = placed["to"] + rng.randf_range(50.0, 130.0)
		var crossed := false
		if rng.randf() < 0.8:
			for span2 in [rng.randf_range(110.0, 200.0), rng.randf_range(80.0, 110.0)]:
				var p2 := _try_parallel(ctx, placed["to"], placed["to"] + span2, -s0, rng, placed["th"][1])
				if not p2.is_empty():
					next_d = p2["to"] + rng.randf_range(40.0, 110.0)
					side = s0
					crossed = true
					break
		if not crossed and rng.randf() < 0.7:
			for span3 in [rng.randf_range(100.0, 160.0), rng.randf_range(75.0, 100.0)]:
				if placed["from"] - span3 > 60.0 and not _try_parallel(ctx, placed["from"] - span3, placed["from"], -s0, rng, -1.0,
						placed["th"][0]).is_empty():
					break
		d = next_d


## Eine Parallelstraße von d1 bis d2 auf Seite s. th1/th2 vorgegeben (Kreuzung in einer Flucht), sonst zufällig.
static func _try_parallel(ctx: Dictionary, d1: float, d2: float, s: float, rng: RandomNumberGenerator, th1 := -1.0, th2 := -1.0) -> Dictionary:
	var cls := _pick_cls(ctx, (d1 + d2) / 2.0, rng)
	var allow := d1 if th1 > 0.0 else (d2 if th2 > 0.0 else -1e9)
	var best := {}
	for att in (5 if ctx["osm"] else 3):
		var sec := _section(ctx, cls, d1, rng)
		var w: float = sec["half"] + sec["walk"]
		if att == 0 and (not _mouth_ok(ctx, d1, s, w, allow) or not _mouth_ok(ctx, d2, s, w, allow)):
			return {}
		var r := _parallel_shape(ctx, d1, d2, s, sec, rng, th1, th2)
		if r.is_empty():
			continue
		if not _check(ctx, r["pts"], sec, [d1, d2], []):
			continue
		# dahinter Platz für eine Häuserreihe (nicht direkt an der nächsten Straße oder am Wasser)
		var room := true
		var far: PackedVector2Array = r["far"]
		for q in far:
			if _main_near(ctx, q, 40.0).x < 20.0 or _blocked(ctx, q, 2.0) != "" or _branch_near(ctx, q, [], 30.0) < 4.0:
				room = false
				break
		if not room:
			_w("dahinter")
			continue
		var cost := _osm_cost(ctx, _flat2(r["pts"]), sec["half"] + sec["walk"])
		if ctx["osm"] and cost > 6:
			_w("haeuser")
			continue
		if best.is_empty() or cost < best["cost"]:
			best = r
			best["sec"] = sec
			best["cost"] = cost
		if not ctx["osm"]:
			break
	if best.is_empty():
		return {}
	var sec2: Dictionary = best["sec"]
	var p := _add(ctx, "lane", best["pts"], sec2, d1, d2, s)
	p["ends"] = [{"at": 0, "d": d1}, {"at": 0, "d": d2}]
	p["th"] = best["th"]
	var w2: float = sec2["half"] + sec2["walk"]
	_mouth_zone(ctx, d1, w2)
	_mouth_zone(ctx, d2, w2)
	# lange Blöcke: Verbindung in der Mitte (richtige Straße oder schmale Durchfahrt zwischen den Häusern)
	if d2 - d1 >= 150.0:
		_try_connector(ctx, p, best, rng)
	elif d2 - d1 >= 105.0 and rng.randf() < 0.6:
		_try_connector(ctx, p, best, rng, true)
	return p


## Form einer Parallelstraße in (Weg-Meter, Abstand): Einmündung unter th1 bzw. th2 (Grad zur Hauptstraße, 90 =
## rechtwinklig; kleiner = schräg zur Mitte des Blocks), Bögen mit 24-46 m, dazwischen schwingend (Abstand wechselt)
static func _parallel_shape(ctx: Dictionary, d1: float, d2: float, s: float, sec: Dictionary, rng: RandomNumberGenerator,
		th1 := -1.0, th2 := -1.0) -> Dictionary:
	var track: Dictionary = ctx["track"]
	var base := 0.0
	var dd := d1
	while dd <= d2:
		base = maxf(base, Track.hw(track, fposmod(dd, ctx["L"]) if ctx["loop"] else dd))
		dd += 10.0
	var rr: float = sec["half"] + sec["walk"] + maxf(sec["strip"][0], sec["strip"][1])
	var omin: float = base + Track.WALK + 21.0 + rr
	var angs := [90.0, 90.0, 75.0, 65.0, 55.0]
	var a1: float = th1 if th1 > 0.0 else angs[rng.randi() % angs.size()]
	var a2: float = th2 if th2 > 0.0 else angs[rng.randi() % angs.size()]
	var off1 := omin + rng.randf_range(0.0, 16.0)
	var off2 := omin + rng.randf_range(0.0, 16.0)
	var x1: float = d1 + off1 / tan(deg_to_rad(a1))
	var x2: float = d2 - off2 / tan(deg_to_rad(a2))
	var R1 := rng.randf_range(24.0, 40.0) + (6.0 if sec["cls"] == "breit" else 0.0)
	var R2 := rng.randf_range(24.0, 40.0) + (6.0 if sec["cls"] == "breit" else 0.0)
	# gerade aus der Hauptstraße heraus bis hinter ihren Gehweg, erst dann der Bogen (Tangente R·tan(Winkel/2))
	var lead := base + Track.WALK + 3.0
	off1 = maxf(off1, lead + 22.0 * tan(deg_to_rad(a1) / 2.0) * sin(deg_to_rad(a1)))
	off2 = maxf(off2, lead + 22.0 * tan(deg_to_rad(a2) / 2.0) * sin(deg_to_rad(a2)))
	R1 = minf(R1, (off1 - lead) / (tan(deg_to_rad(a1) / 2.0) * sin(deg_to_rad(a1))))
	R2 = minf(R2, (off2 - lead) / (tan(deg_to_rad(a2) / 2.0) * sin(deg_to_rad(a2))))
	x1 = d1 + off1 / tan(deg_to_rad(a1))
	x2 = d2 - off2 / tan(deg_to_rad(a2))
	if x2 - x1 < 30.0:
		return _w_d("kurz")
	var poly := [Vector2(d1, 0.0), Vector2(x1, off1)]
	var rad := [0.0, R1]
	# schwingen: bei langen Blöcken ein oder zwei Zwischenpunkte mit anderem Abstand
	var mids := 0 if x2 - x1 < 90.0 else (1 if x2 - x1 < 200.0 else 2)
	for k in mids:
		var t := float(k + 1) / (mids + 1) + rng.randf_range(-0.08, 0.08)
		poly.append(Vector2(lerpf(x1, x2, t), omin + rng.randf_range(0.0, 22.0)))
		rad.append(rng.randf_range(90.0, 180.0))
	poly.append(Vector2(x2, off2))
	rad.append(R2)
	poly.append(Vector2(d2, 0.0))
	rad.append(0.0)
	var al := _fillet(poly, rad, 2.5)
	var pts := _map(ctx, al, s)
	# Kurven der Hauptstraße: innen wird alles enger (Punkte rücken zusammen); dort nur bei weitem Bogen
	var far := PackedVector2Array()
	for i in range(0, al.size(), 6):
		var v: Vector2 = al[i]
		if v.y > omin - 4.0:
			far.append(_flat2(_map(ctx, PackedVector2Array([Vector2(v.x, v.y + rr + HOUSE_ROOM)]), s))[0])
	return {"pts": pts, "al": al, "far": far, "th": [a1, a2], "off": [off1, off2]}


## Verbindung von der Hauptstraße zur Mitte einer langen Parallelstraße (T an beiden Enden); narrow: schmale
## Durchfahrt (eine Spur) zwischen den Häusern. Gegenüber manchmal eine Straße in derselben Flucht (Kreuzung).
static func _try_connector(ctx: Dictionary, lane: Dictionary, shape: Dictionary, rng: RandomNumberGenerator, narrow := false) -> void:
	var al: PackedVector2Array = shape["al"]
	var s: float = lane["side"]
	var d1: float = lane["from"]
	var d2: float = lane["to"]
	for att in 3:
		var dm := lerpf(d1, d2, rng.randf_range(0.4, 0.6))
		var th: float = 90.0 if narrow or att == 2 else [70.0, 110.0][rng.randi() % 2]
		var sec: Dictionary = {"cls": "gasse", "half": Track.PASSAGE_HALF, "walk": 0.0, "lanes": 0.0, "strip": [0.0, 0.0],
			"strip_kind": ["", ""], "cobble": 0.0} if narrow else _section(ctx, _pick_cls(ctx, dm, rng), dm, rng)
		if not narrow and sec["cls"] == "gasse":
			sec = {"cls": "gasse", "half": CLS["gasse"]["half"], "walk": CLS["gasse"]["walk"], "lanes": 0.0, "strip": [0.0, 0.0],
				"strip_kind": ["", ""], "cobble": sec["cobble"]}
		if not _mouth_ok(ctx, dm, s, sec["half"] + sec["walk"]):
			continue
		# Ziel: Punkt der Parallelstraße, den die Linie unter th trifft (Vorzeichenwechsel zwischen zwei Punkten)
		var cot := cos(deg_to_rad(th)) / sin(deg_to_rad(th))
		var hit := Vector2.ZERO
		var hit_i := -1
		for i in range(1, al.size()):
			var v0: Vector2 = al[i - 1]
			var v1: Vector2 = al[i]
			if v0.y < 12.0 or v1.y < 12.0:
				continue
			var g0: float = dm + cot * v0.y - v0.x
			var g1: float = dm + cot * v1.y - v1.x
			if signf(g0) != signf(g1):
				hit = v0.lerp(v1, g0 / (g0 - g1))
				hit_i = i
				break
		if hit_i < 0:
			continue
		var line := PackedVector2Array()
		var n := maxi(int(Vector2(dm, 0.0).distance_to(hit) / 2.5), 4)
		for j in n + 1:
			line.append(Vector2(dm, 0.0).lerp(hit, float(j) / n))
		var pts := _map(ctx, line, s)
		if not _check(ctx, pts, sec, [dm], [lane["id"]]):
			continue
		var kind := "passage" if narrow else "lane"
		var p := _add(ctx, kind, pts, sec, dm, dm, s)
		p["ends"] = [{"at": 0, "d": dm}, {"at": lane["id"], "d": (lane["curve"] as Curve3D).get_closest_offset(pts[pts.size() - 1])}]
		_mouth_zone(ctx, dm, sec["half"] + sec["walk"])
		if not narrow and rng.randf() < 0.55:
			# gegenüber in derselben Flucht weiter: Kreuzung (Parallelstraße auf der anderen Seite, ab hier nach vorn
			# oder nach hinten)
			var span := rng.randf_range(90.0, 170.0)
			if th > 90.5 or (th > 89.5 and rng.randf() < 0.5):
				_try_parallel(ctx, dm, dm + span, -s, rng, 180.0 - th)
			else:
				_try_parallel(ctx, dm - span, dm, -s, rng, -1.0, th)
		return


# --- Plätze ----------------------------------------------------------------------------------------------------------

## Offene Plätze und Parkplätze auf Fahrbahnhöhe neben den neuen Straßen (Sackgasse mit Wänden ringsum, Einfahrt offen):
## Altstadt und Markt mit Pflaster (Marktplatz), sonst Asphalt mit Stellplätzen
static func _plan_plazas(ctx: Dictionary, rng: RandomNumberGenerator) -> void:
	var track: Dictionary = ctx["track"]
	var lanes := []
	for p in track["paths"]:
		if p.get("net", false) and p["kind"] == "lane" and p["cls"] != "gasse":
			lanes.append(p)
	var made := 0
	var limit := 1 + int(ctx["L"] / 1800.0)
	for p in lanes:
		if made >= limit:
			break
		if rng.randf() > 0.5:
			continue
		var c: Curve3D = p["curve"]
		var len: float = p["length"]
		if len < 120.0:
			continue
		for att in 4:
			var dl := rng.randf_range(0.3, 0.7) * len
			var sd := 1.0 if rng.randf() < 0.5 else -1.0
			var f := Track.frame_at(c, dl)
			var market: bool = _district_key(ctx, p["from"]) in COBBLE + ["shops", "innenstadt_de", "kiez_de", "kurviertel_de"]
			var half := snappedf(rng.randf_range(9.0, 13.0), 1.0)  # ganze Meter: je Breite ein Straßenmaterial, nicht je Platz
			var depth := rng.randf_range(24.0, 34.0)
			var e0 := edge(p, sd)
			var pts := PackedVector3Array()
			var k := 0.0
			while k <= e0 + depth + 0.01:
				pts.append(f["pos"] + f["right"] * sd * k)
				k += 2.0
			# Platz frei von Hauptstraße, anderen Wegen (außer der eigenen Straße), Wasser, Sperrflächen
			var ok := true
			for i in pts.size():
				var q := Vector2(pts[i].x, pts[i].z)
				if float(i) * 2.0 < e0 + 2.0:
					continue
				for lat in [-half, 0.0, half]:
					var qq: Vector2 = q + Vector2(f["fwd"].x, f["fwd"].z) * lat
					if _main_near(ctx, qq, 40.0).x < Track.WALK + 6.0 or _branch_near(ctx, qq, [p["id"]], 40.0) < 5.0 \
							or _blocked(ctx, qq, 3.0) != "":
						ok = false
				if not ok:
					break
			if not ok:
				_w("platz")
				continue
			var sec := {"cls": "platz", "half": half, "walk": 0.0, "lanes": 0.0, "strip": [0.0, 0.0], "strip_kind": ["", ""],
				"cobble": 1.0 if market else 0.0}
			var pz := _add(ctx, "platz", pts, sec, p["from"], p["to"], sd, {"market": market, "on": p["id"], "at": dl})
			pz["ends"] = [{"at": p["id"], "d": dl}]
			made += 1
			break


# --- Einmündungen ------------------------------------------------------------------------------------------------------

## Neue Wege auf fremden Fahrbahnen der Welt (Ring, Auffahrten, Nachbarstädte) fallen weg, mit allem, was an ihnen
## hängt (Verbindungen, Plätze); die Nummern der übrigen Wege rücken nach
static func _drop_keepout(ctx: Dictionary) -> void:
	var track: Dictionary = ctx["track"]
	# Ausfahrt hinter dem Ziel bzw. Rückführung auf die Strecke wie eine fremde Fahrbahn
	for tp in ctx["tails"]:
		var tc: Curve3D = tp["curve"]
		var td := 0.0
		while td <= tc.get_baked_length():
			var tq := tc.sample_baked(td)
			var tk := Vector2i(floori(tq.x / 32.0), floori(tq.z / 32.0))
			if not ctx["kgrid"].has(tk):
				ctx["kgrid"][tk] = []
			ctx["kgrid"][tk].append([Vector2(tq.x, tq.z), float(tp["half_w"]) + Track.WALK + 2.0])
			td += 6.0
	if ctx["kgrid"].is_empty():
		return
	var drop := {}
	for p in track["paths"]:
		if not p.has("net") or p.has("from_design"):
			continue
		for e in p["ends"]:
			for jd in ctx["skip_zones"]:
				if int(e["at"]) == 0 and absf(float(e["d"]) - jd) < 40.0 + reach(p) + 14.0:
					drop[p["id"]] = true
		var c: Curve3D = p["curve"]
		var L := c.get_baked_length()
		var r := reach(p) + 2.0
		var d := 0.0
		while d <= L and not drop.has(p["id"]):
			var q := c.sample_baked(d)
			var q2 := Vector2(q.x, q.z)
			var kk := Vector2i(floori(q.x / 32.0), floori(q.z / 32.0))
			for gx in range(kk.x - 1, kk.x + 2):
				for gz in range(kk.y - 1, kk.y + 2):
					for e in ctx["kgrid"].get(Vector2i(gx, gz), []):
						if q2.distance_to(e[0]) < r + e[1]:
							drop[p["id"]] = true
			d += 4.0
	if drop.is_empty():
		return
	# was an einem weggefallenen Weg hängt, fällt mit
	var changed := true
	while changed:
		changed = false
		for p in track["paths"]:
			if drop.has(p["id"]) or not p.has("net"):
				continue
			var dep: bool = drop.has(int(p.get("on", -1)))
			for e in p["ends"]:
				dep = dep or drop.has(int(e["at"]))
			if dep:
				drop[p["id"]] = true
				changed = true
	why["keepout_weg"] = why.get("keepout_weg", 0) + drop.size()
	var keep := []
	var remap := {}
	for p in track["paths"]:
		if not drop.has(p["id"]):
			remap[p["id"]] = keep.size()
			keep.append(p)
	for p in keep:
		p["id"] = remap[p["id"]]
		if p.has("on"):
			p["on"] = remap[int(p["on"])]
		for e in p.get("ends", []):
			e["at"] = remap[int(e["at"])]
	for lk in track["lakes"]:
		lk["path"] = remap.get(lk["path"], lk["path"])
	track["paths"] = keep


## Einmündungen sammeln: in die Hauptstraße (T, oder X, wenn gegenüber eine andere Straße einmündet) und in andere
## neue Straßen. Kreuzungen an der Hauptstraße bekommen Ampeln, Einmündungen ein Vorfahrt-achten-Schild.
static func _plan_junctions(ctx: Dictionary) -> void:
	var track: Dictionary = ctx["track"]
	var js := []
	for p in track["paths"]:
		if not p.get("net", false) or p["kind"] == "platz":
			continue
		var c: Curve3D = p["curve"]
		for k in (p["ends"] as Array).size():
			var e: Dictionary = p["ends"][k]
			if int(e["at"]) != 0:
				continue
			js.append({"d": float(e["d"]), "path": p["id"], "start": k == 0, "pos": c.sample_baked(0.0 if k == 0 else c.get_baked_length())})
	for j in js:
		j["x"] = false
		for o in js:
			if o["path"] != j["path"] and _ldist(ctx, j["d"], o["d"]) < 14.0:
				var pj: Dictionary = track["paths"][j["path"]]
				var po: Dictionary = track["paths"][o["path"]]
				if signf(_side_at(ctx, pj, j)) != signf(_side_at(ctx, po, o)):
					j["x"] = true
	track["junctions"] = js


## Auf welcher Seite der Hauptstraße liegt der Weg an dieser Einmündung?
static func _side_at(ctx: Dictionary, p: Dictionary, j: Dictionary) -> float:
	var c: Curve3D = p["curve"]
	var q := c.sample_baked(20.0 if j["start"] else c.get_baked_length() - 20.0)
	var f := Track.frame_at(ctx["curve"], j["d"])
	return (q - f["pos"]).dot(f["right"])


# --- Schnelle Abstände (Bau in der Welt) -------------------------------------------------------------------------------

## Suchraster aller Wege für den Bau (track["sgrid"]): die Abstandsfragen beim Bau (Gehweg, Wände, Häuser, Laternen)
## liefen sonst über jede Kurve ganz (bei 40 Wegen mehrere Sekunden je Stadt). Nur Welt-Städte; Rennen rechnen genau.
const GRID := 12.0
const COARSE := 64.0
const REACH_MAX := 14.0  # breitester Weg bis zur Hauskante (Platz: halbe Breite)


static func make_grid(track: Dictionary) -> void:
	var fine := {}
	var coarse := {}
	var mg := {}
	for p in track["paths"]:
		var c: Curve3D = p["curve"]
		var L := c.get_baked_length()
		var main: bool = p["id"] == 0
		var stp := 2.0 if main else 1.0
		var d := 0.0
		while d <= L + 0.01:
			var q := c.sample_baked(minf(d, L))
			var q2 := Vector2(q.x, q.z)
			var key := Vector2i(floori(q.x / GRID), floori(q.z / GRID))
			if main:
				if not mg.has(key):
					mg[key] = []
				mg[key].append([q2, Track.hw(track, minf(d, L))])
			else:
				if not fine.has(key):
					fine[key] = []
				# [Punkt, Weg, halbe Fahrbahn, bis Hauskante, Sackgasse, Abstand der Häuser (Track._lot_free)]
				var need: float = reach(p) - float(p["half_w"]) + 0.3 if p.has("net") else {"fork": 3.0, "spur": 1.0}.get(p["kind"], 0.3)
				fine[key].append([q2, int(p["id"]), float(p["half_w"]), reach(p), p["kind"] == "spur", float(p["half_w"]) + need])
				coarse[Vector2i(floori(q.x / COARSE), floori(q.z / COARSE))] = true
			d += stp
	track["sgrid"] = {"f": fine, "c": coarse, "m": mg}
	track["parked"] = []  # parkende Autos der ganzen Stadt (build_junctions setzt sie zusammen)
	track["trees"] = []  # Bäume in Grünstreifen und auf Plätzen (ebenso)


## Zellen im Ring k um key (k = 0: nur key)
static func _ring(key: Vector2i, k: int) -> Array:
	if k == 0:
		return [key]
	var out := []
	for x in range(-k, k + 1):
		out.append(key + Vector2i(x, -k))
		out.append(key + Vector2i(x, k))
	for z in range(-k + 1, k):
		out.append(key + Vector2i(-k, z))
		out.append(key + Vector2i(k, z))
	return out


## Häuser (Track._lot_free): liegt ein Weg samt nötigem Abstand im Grundriss foot ([Mitte, Achse u, Achse v, halbe
## Länge u, halbe Länge v])? Jeder Wegpunkt (alle 1 m) als Rechteck um den Grundriss, vergrößert um Fahrbahn und Abstand
static func lot_hit(track: Dictionary, foot: Array) -> bool:
	var fine: Dictionary = track["sgrid"]["f"]
	var c: Vector2 = foot[0]
	var u: Vector2 = foot[1]
	var v: Vector2 = foot[2]
	var hu: float = foot[3]
	var hv: float = foot[4]
	var r := Vector2(hu, hv).length() + REACH_MAX + 3.5
	var k0 := Vector2i(floori((c.x - r) / GRID), floori((c.y - r) / GRID))
	var k1 := Vector2i(floori((c.x + r) / GRID), floori((c.y + r) / GRID))
	for gx in range(k0.x, k1.x + 1):
		for gz in range(k0.y, k1.y + 1):
			var arr = fine.get(Vector2i(gx, gz))
			if arr == null:
				continue
			for e in arr:
				var q: Vector2 = e[0] - c
				var need: float = e[5]
				if absf(q.dot(u)) < hu + need and absf(q.dot(v)) < hv + need:
					return true
	return false


## wie Track._main_clearance (Abstand zur Fahrbahnkante der Hauptstraße), bis mx genau, sonst 1e9
static func main_clear(track: Dictionary, pos: Vector3, mx := 20.0) -> float:
	var mg: Dictionary = track["sgrid"]["m"]
	var q := Vector2(pos.x, pos.z)
	var key := Vector2i(floori(q.x / GRID), floori(q.y / GRID))
	var best := 1e9
	for k in int(ceil(mx / GRID)) + 1:
		if k >= 2 and (k - 1) * GRID - Track.HALF_W - 6.0 > best:
			break
		for ck in _ring(key, k):
			var arr = mg.get(ck)
			if arr == null:
				continue
			for e in arr:
				best = minf(best, q.distance_to(e[0]) - e[1])
	return best


## wie Track._branch_clearance: Abstand zur Fahrbahnkante (to_edge: bei neuen Straßen zur Hauskante) des nächsten
## Abzweigs außer own, bis 64 m genau, sonst 1e9
static func branch_clear(track: Dictionary, pos: Vector3, skip_spurs: bool, to_edge: bool, own := -1) -> float:
	var g: Dictionary = track["sgrid"]
	var q := Vector2(pos.x, pos.z)
	var cc := Vector2i(floori(q.x / COARSE), floori(q.y / COARSE))
	var any := false
	for gx in range(cc.x - 1, cc.x + 2):
		for gz in range(cc.y - 1, cc.y + 2):
			if g["c"].has(Vector2i(gx, gz)):
				any = true
	if not any:
		return 1e9
	var fine: Dictionary = g["f"]
	var key := Vector2i(floori(q.x / GRID), floori(q.y / GRID))
	var best := 1e9
	for k in int(ceil(COARSE / GRID)) + 1:
		if k >= 2 and (k - 1) * GRID - REACH_MAX > best:
			break
		for ck in _ring(key, k):
			var arr = fine.get(ck)
			if arr == null:
				continue
			for e in arr:
				if e[1] == own or (skip_spurs and e[4]):
					continue
				best = minf(best, q.distance_to(e[0]) - (e[3] if to_edge else e[2]))
	return best


# --- Bau -------------------------------------------------------------------------------------------------------------

## Neue Straße bauen: Fahrbahn mit Markierung je Klasse, Parkbucht (Asphalt, Stellplätze) oder Grünstreifen, Gehwege
## mit Bordstein, Wand an der Hauskante (offen, wo die Hauptstraße oder ein anderer Weg anschließt); Plätze mit Wänden
## ringsum und offener Einfahrt
static func build_street(root: Node3D, track: Dictionary, p: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Curve3D = p["curve"]
	var len: float = p["length"]
	var half: float = p["half_w"]
	var walk: float = p["walk"]
	var sw: Array = p["strip"]
	var sk: Array = p["strip_kind"]
	var platz: bool = p["kind"] == "platz"
	var road := _st()
	var park := _st()
	var green := _st()
	var walk_st := _st()
	var n_park := 0
	var n_green := 0
	var n_walk := 0
	var walls := StaticBody3D.new()
	walls.name = "WallsBranch%d" % p["id"]
	root.add_child(walls)
	var up := Vector3(0, Track.CURB_H, 0)
	var lift := Vector3(0, 0.004, 0)  # Gehweg der Nebenstraße knapp über dem der Hauptstraße (an der Ecke liegen beide)
	var runs := [[], []]  # je Seite: gebaute Stücke des Streifens [d0, d1]
	var wall_runs := [[], []]  # je Seite: Wandstücke [Punkt a, Punkt b, d] (für Hecken, Mauern, Poller am Platz)
	var own: int = p["id"]
	var step := 2.0
	var d := 0.0
	var prev := {}
	while d <= len + 0.01:
		var f := Track.frame_at(c, d)
		var cp: Vector3 = f["pos"]
		cp.y = 0.0
		var cur := {"c": cp, "r": f["right"], "d": d}
		if not prev.is_empty():
			var r0: Vector3 = prev["r"]
			var r1: Vector3 = cur["r"]
			var c0: Vector3 = prev["c"]
			var c1: Vector3 = cur["c"]
			if r0.dot(r1) < 0.8:
				prev = cur
				d = minf(d + step, len) if d < len - 0.01 else len + 1.0
				continue
			var mid: Vector3 = (c0 + c1) / 2.0
			var rm: Vector3 = ((r0 + r1) / 2.0).normalized()
			# weit weg von Hauptstraße und anderen Wegen: alles ohne weitere Abfragen (spart fast alle Rasterabfragen)
			var reach_all: float = half + maxf(float(sw[0]), float(sw[1])) + walk + 1.0
			var mc0 := main_clear(track, mid)
			var free := mc0 > reach_all + Track.WALK + 2.0 and branch_clear(track, mid, true, true, own) > reach_all + 1.5
			if mc0 > -0.3:
				Track._strip(road, c0 - r0 * half, c0 + r0 * half, c1 - r1 * half, c1 + r1 * half, prev["d"], d)
			for i in 2:
				var sd := -1.0 if i == 0 else 1.0
				var a1: float = half + float(sw[i])
				var a2: float = a1 + walk
				# Streifen nur, wo er ganz neben dem Gehweg der Hauptstraße und keinem anderen Weg liegt
				var strip_ok: bool = float(sw[i]) > 0.0
				if strip_ok and not free:
					var sm: Vector3 = mid + rm * sd * (half + float(sw[i]) * 0.5)
					strip_ok = main_clear(track, sm) > Track.WALK + 1.0 and branch_clear(track, sm, true, false, own) > 0.5 \
						and branch_clear(track, mid + rm * sd * a1, true, false, own) > 0.3
				var w0: float = a1 if strip_ok else half
				# Gehweg: außerhalb der Fahrbahn der Hauptstraße und anderer Wege
				var walk_ok := walk > 0.0
				if walk_ok and not free:
					var wi: Vector3 = mid + rm * sd * (w0 + 0.3)
					var wo: Vector3 = mid + rm * sd * (a2 - 0.2)
					walk_ok = main_clear(track, wi) > 0.3 and main_clear(track, wo) > 0.3 \
						and branch_clear(track, wi, true, false, own) > 0.3 and branch_clear(track, wo, true, false, own) > 0.3
				if strip_ok:
					var st: SurfaceTool = park if sk[i] == "park" else green
					var y := up + lift if sk[i] == "gruen" else Vector3(0, 0.002, 0)
					var ia := c0 + r0 * sd * half
					var oa := c0 + r0 * sd * a1
					var ib := c1 + r1 * sd * half
					var ob := c1 + r1 * sd * a1
					if sd < 0.0:
						Track._strip(st, oa + y, ia + y, ob + y, ib + y, prev["d"], d)
					else:
						Track._strip(st, ia + y, oa + y, ib + y, ob + y, prev["d"], d)
					if sk[i] == "park":
						n_park += 1
					else:
						n_green += 1
						Track._strip_v(walk_st, ia + lift, ib + lift, Track.CURB_H, sd < 0.0)
					runs[i].append([prev["d"], d])
				if walk_ok:
					var ia2 := c0 + r0 * sd * w0
					var oa2 := c0 + r0 * sd * a2
					var ib2 := c1 + r1 * sd * w0
					var ob2 := c1 + r1 * sd * a2
					if sd < 0.0:
						Track._strip(walk_st, oa2 + up + lift, ia2 + up + lift, ob2 + up + lift, ib2 + up + lift, prev["d"], d)
					else:
						Track._strip(walk_st, ia2 + up + lift, oa2 + up + lift, ib2 + up + lift, ob2 + up + lift, prev["d"], d)
					if not (strip_ok and sk[i] == "gruen"):
						Track._strip_v(walk_st, ia2 + lift, ib2 + lift, Track.CURB_H, sd < 0.0)
					n_walk += 1
				# Wand an der Hauskante: nicht an der Hauptstraße (bis hinter ihren Gehweg) und nicht, wo ein anderer Weg
				# anschließt (dessen ganze Breite samt Gehwegen bleibt offen)
				var wa: Vector3 = c0 + r0 * sd * (a2 + 0.3)
				var wb: Vector3 = c1 + r1 * sd * (a2 + 0.3)
				var wm: Vector3 = (wa + wb) / 2.0
				if not free and main_clear(track, wm) < Track.WALK + 0.4:
					continue
				if not free and branch_clear(track, wm, true, true, own) < 0.3:
					continue
				Track._wall_shape(walls, wa, wb)
				wall_runs[i].append([wa, wb, d, rm * sd])
		prev = cur
		if d < len - 0.01 and d + step > len:
			d = len
		else:
			d += step
	# Platz: Wand quer über das Ende
	if platz:
		var fe := Track.frame_at(c, len)
		var ea: Vector3 = fe["pos"] - fe["right"] * (half + 0.3) + fe["fwd"] * 0.3
		var eb: Vector3 = fe["pos"] + fe["right"] * (half + 0.3) + fe["fwd"] * 0.3
		ea.y = 0.0
		eb.y = 0.0
		Track._wall_shape(walls, ea, eb)
		wall_runs[1].append([ea, eb, len, fe["fwd"]])
	var y_off := 0.008 if platz else (0.01 if (p["ends"] as Array).size() > 1 and int(p["ends"][1]["at"]) != 0 else 0.012)
	Track._road_mesh(root, road, p["lanes"], half * 2.0, p["cobble"], y_off)
	if n_park > 0:
		Track._road_mesh(root, park, 0.0, STRIP_W, 0.0, 0.0)
	if n_green > 0:
		Track._flush(root, green, Track.Builder.mat(Color(0.07, 0.16, 0.06), 0.0, 0.95))
	if n_walk > 0:
		Track._flush(root, walk_st, Track._walk_mat(maxf(walk, 1.0), _district_key_t(track, p["from"])))
	_strip_details(root, track, p, runs, rng)
	_borders(root, track, p, wall_runs, rng)
	if platz:
		_plaza_details(root, track, p, rng)


static func _st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _district_key_t(track: Dictionary, d: float) -> String:
	var arr: Array = track["districts"]
	return arr[clampi(int(fposmod(d, track["length"]) / Track.DISTRICT_LEN), 0, arr.size() - 1)]


## Parkbuchten: Stellplätze (weiße Striche) und parkende Autos (fest, mit Lücken); Grünstreifen: Bäume (feste Stämme)
static func _strip_details(root: Node3D, track: Dictionary, p: Dictionary, runs: Array, rng: RandomNumberGenerator) -> void:
	var c: Curve3D = p["curve"]
	var half: float = p["half_w"]
	var cars := []  # [Transform]
	var lines := []
	for i in 2:
		var sd := -1.0 if i == 0 else 1.0
		var kind: String = p["strip_kind"][i]
		if kind == "":
			continue
		# zusammenhängende Stücke
		var segs := []
		for r in runs[i]:
			if not segs.is_empty() and absf(segs[-1][1] - r[0]) < 0.1:
				segs[-1][1] = r[1]
			else:
				segs.append([r[0], r[1]])
		for sg in segs:
			var a: float = sg[0] + 3.0
			var b: float = sg[1] - 3.0
			if kind == "park":
				var x := a
				while x + 5.6 <= b:
					var f := Track.frame_at(c, x + 2.8)
					var pos: Vector3 = f["pos"] + f["right"] * sd * (half + STRIP_W * 0.5 + 0.15)
					pos.y = 0.0
					# in engen Bögen (unter 70 m) parkt keiner: dort schneidet man die Kurve
					var fa2 := Track.frame_at(c, x - 4.0)
					var fb2 := Track.frame_at(c, x + 9.6)
					var bend: float = (fa2["fwd"] as Vector3).angle_to(fb2["fwd"]) / 13.6
					if bend < 1.0 / 70.0 and rng.randf() < 0.72:
						var bs := Basis.looking_at(f["fwd"] * (1.0 if rng.randf() < 0.5 else -1.0), Vector3.UP)
						cars.append(Transform3D(bs, pos + f["fwd"] * rng.randf_range(-0.3, 0.3)))
					var fl := Track.frame_at(c, x)
					lines.append(Transform3D(Basis.looking_at(fl["right"], Vector3.UP), fl["pos"] + fl["right"] * sd * (half + STRIP_W * 0.5) + Vector3(0, 0.02, 0)))
					x += 5.6
			else:
				var x2 := a + rng.randf_range(1.0, 4.0)
				while x2 < b:
					var f2 := Track.frame_at(c, x2)
					var tp: Vector3 = f2["pos"] + f2["right"] * sd * (half + STRIP_W * 0.5)
					tp.y = Track.CURB_H
					track["trees"].append(tp)
					x2 += rng.randf_range(9.0, 13.0)
	if not lines.is_empty():
		Track._multi(root, Track.Builder.box(Vector3(STRIP_W - 0.3, 0.02, 0.12)), Track.Builder.mat(Color(0.8, 0.8, 0.78), 0.0, 0.6), lines)
	track["parked"].append_array(cars)


## Straßenbäume der ganzen Stadt als MultiMesh (Stamm, Krone in drei Größen und Tönen) mit festen Stämmen (rund: wer
## streift, gleitet ab); einzeln gebaut kostete jeder Baum zwei Zeichenaufrufe
static func _trees(root: Node3D, pos: Array, rng: RandomNumberGenerator) -> void:
	if pos.is_empty():
		return
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.18
	trunk.height = 2.4
	trunk.radial_segments = 6
	var trunks := []
	var crowns := [[], [], []]
	var body := StaticBody3D.new()
	body.name = "Strassenbaeume"
	root.add_child(body)
	for p in pos:
		trunks.append(Transform3D(Basis(), p + Vector3(0, 1.2, 0)))
		var k := rng.randi() % 3
		var r: float = [1.3, 1.6, 1.9][k]
		crowns[k].append(Transform3D(Basis().rotated(Vector3.UP, rng.randf() * TAU), p + Vector3(0, 2.4 + r, 0)))
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = 0.22
		cy.height = 2.0
		cs.shape = cy
		cs.position = p + Vector3(0, 1.0, 0)
		body.add_child(cs)
	Track._multi(root, trunk, Track.Builder.mat(Color(0.12, 0.08, 0.05), 0.0, 0.9), trunks)
	for k in 3:
		var crown := SphereMesh.new()
		var r2: float = [1.3, 1.6, 1.9][k]
		crown.radius = r2
		crown.height = r2 * 2.3
		crown.radial_segments = 7
		crown.rings = 4
		var g: float = [0.7, 0.9, 1.1][k]
		Track._multi(root, crown, Track.Builder.mat(Color(0.03 * g, 0.12 * g, 0.04 * g), 0.0, 0.9), crowns[k])


## Parkende Autos: Modelle des Verkehrs (geteilt, ohne leuchtende Lampen), je Teil ein MultiMesh; Kollision je Auto
## als Kasten (man kracht hinein wie in eine Wand, sie stehen fest)
static func parked_cars(root: Node3D, cars: Array, rng: RandomNumberGenerator) -> void:
	if cars.is_empty():
		return
	var models: Dictionary = load("res://scripts/traffic_car.gd")._models
	var keys := models.keys().filter(func(k): return String(k).begins_with("sedan") or String(k).begins_with("van") \
		or String(k).begins_with("taxi"))
	keys.sort()
	# höchstens fünf Modelle je Stadt: jedes Teil jedes Modells ist ein Zeichenaufruf (MultiMesh)
	if keys.size() > 5:
		var pick := []
		for k in 5:
			pick.append(keys[(rng.randi() % keys.size())])
		keys = pick
	var groups := {}  # [Mesh, Material] -> Transforms
	var body := StaticBody3D.new()
	body.name = "ParkedCars"
	root.add_child(body)
	var simple := []
	for xf in cars:
		var key: String = keys[rng.randi() % keys.size()] if not keys.is_empty() else ""
		var van := key.begins_with("van")
		var size := Vector3(2.0, 2.3, 5.2) if van else Vector3(1.8, 1.5, 4.5)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.transform = Transform3D(xf.basis, xf.origin + Vector3(0, size.y / 2.0 + 0.1, 0))
		body.add_child(cs)
		if key == "":
			simple.append(xf)
			continue
		for it in models[key]:
			if it[0] is String or not it[0] is Mesh:
				continue
			var m = it[2]
			if m is BaseMaterial3D and (m as BaseMaterial3D).emission_enabled:
				continue  # Scheinwerfer und Rücklichter aus
			var gk := [it[0], m]
			if not groups.has(gk):
				groups[gk] = []
			groups[gk].append(xf * (it[1] as Transform3D))
	for gk in groups:
		Track._multi(root, gk[0], gk[1], groups[gk])
	if not simple.is_empty():
		var paint := Track.Builder.mat(Color(0.3, 0.32, 0.36), 0.3, 0.4)
		var glass := Track.Builder.mat(Color(0.04, 0.05, 0.07), 0.6, 0.15)
		var bx := []
		var cb := []
		for xf in simple:
			bx.append(xf * Transform3D(Basis(), Vector3(0, 0.6, 0)))
			cb.append(xf * Transform3D(Basis(), Vector3(0, 1.25, 0.2)))
		Track._multi(root, Track.Builder.box(Vector3(1.8, 0.75, 4.4)), paint, bx)
		Track._multi(root, Track.Builder.box(Vector3(1.55, 0.55, 2.2)), glass, cb)


## Sichtbare Ränder entlang der Wände, wo kein Haus davor steht, macht _build_fences (Zaun, Hecke, Mauer). Am Platz
## selbst: Hecke oder niedrige Mauer ringsum, an der Einfahrt Poller bis zur Wand.
static func _borders(root: Node3D, track: Dictionary, p: Dictionary, wall_runs: Array, rng: RandomNumberGenerator) -> void:
	if p["kind"] != "platz":
		return
	var hedge: bool = not p.get("market", false)
	var thick := 0.9 if hedge else 0.6
	var xfs := []
	for i in 2:
		for w in wall_runs[i]:
			var a: Vector3 = w[0]
			var b: Vector3 = w[1]
			var len := a.distance_to(b)
			if len < 0.2:
				continue
			# Innenseite auf der Linie der Wand
			var mid: Vector3 = (a + b) / 2.0 + (w[3] as Vector3) * thick * 0.5
			xfs.append(Transform3D(Basis.looking_at((b - a).normalized(), Vector3.UP) * Basis.from_scale(Vector3(1.0, 1.0, len + 0.05)), mid))
	if xfs.is_empty():
		return
	if hedge:
		var hm := Track.Builder.mat(Color(0.05, 0.2, 0.07), 0.0, 0.9)
		var xh := []
		for x in xfs:
			xh.append(x * Transform3D(Basis(), Vector3(0, 0.65, 0)))
		Track._multi(root, Track.Builder.box(Vector3(thick, 1.3, 1.0)), hm, xh)
	else:
		var sm := Track.Builder.mat(Color(0.42, 0.38, 0.33), 0.0, 0.9)
		var xm := []
		for x in xfs:
			xm.append(x * Transform3D(Basis(), Vector3(0, 0.45, 0)))
		Track._multi(root, Track.Builder.box(Vector3(thick, 0.9, 1.0)), sm, xm)


## Platz: Marktplatz (Pflaster, Brunnen, Bäume, Bänke) oder Parkplatz (Stellplätze quer, parkende Autos)
static func _plaza_details(root: Node3D, track: Dictionary, p: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Curve3D = p["curve"]
	var len: float = p["length"]
	var half: float = p["half_w"]
	var parent: Dictionary = track["paths"][int(p["on"])]
	var e0: float = edge(parent, float(p["side"])) + 2.0
	var f0 := Track.frame_at(c, len)
	if p.get("market", false):
		# Brunnen in der Mitte (fest), Bäume an den Seiten
		var fc := Track.frame_at(c, (e0 + len) / 2.0 + 2.0)
		var fside := 1.0 if rng.randf() < 0.5 else -1.0
		var ctr: Vector3 = fc["pos"] + fc["right"] * fside * (half - 4.5)
		ctr.y = 0.0
		var stone := Track.Builder.mat(Color(0.5, 0.47, 0.42), 0.0, 0.85)
		var water := Track.Builder.mat(Color(0.15, 0.3, 0.4), 0.4, 0.1)
		var basin := CylinderMesh.new()
		basin.top_radius = 2.6
		basin.bottom_radius = 2.8
		basin.height = 0.6
		basin.radial_segments = 16
		Track.Builder._add(root, basin, stone, ctr + Vector3(0, 0.3, 0))
		var wtr := CylinderMesh.new()
		wtr.top_radius = 2.3
		wtr.bottom_radius = 2.3
		wtr.height = 0.05
		wtr.radial_segments = 16
		Track.Builder._add(root, wtr, water, ctr + Vector3(0, 0.56, 0))
		var col := CylinderMesh.new()
		col.top_radius = 0.25
		col.bottom_radius = 0.35
		col.height = 2.4
		col.radial_segments = 8
		Track.Builder._add(root, col, stone, ctr + Vector3(0, 1.2, 0))
		Track._solid_cyl(root, 2.8, 1.2, ctr + Vector3(0, 0.6, 0))
		for sd in [-1.0, 1.0]:
			var x := e0 + 3.0
			while x < len - 3.0:
				var f := Track.frame_at(c, x)
				var tp: Vector3 = f["pos"] + f["right"] * sd * (half - 2.0)
				tp.y = 0.0
				if tp.distance_to(ctr) > 5.0:
					track["trees"].append(tp)
				x += rng.randf_range(8.0, 11.0)
		return
	# Parkplatz: Reihe quer an jeder Seite (Stellplätze 2,6 m breit), in der Mitte frei zum Wenden
	var cars := []
	var lines := []
	for sd in [-1.0, 1.0]:
		var x := e0 + 1.5
		while x + 2.6 < len - 0.5:
			var f := Track.frame_at(c, x + 1.3)
			var pos: Vector3 = f["pos"] + f["right"] * sd * (half - 2.6)
			pos.y = 0.0
			if rng.randf() < 0.65:
				cars.append(Transform3D(Basis.looking_at(f["right"] * sd, Vector3.UP), pos))
			var fl := Track.frame_at(c, x)
			lines.append(Transform3D(Basis.looking_at(fl["fwd"], Vector3.UP), fl["pos"] + fl["right"] * sd * (half - 2.6) + Vector3(0, 0.02, 0)))
			x += 2.6
	Track._multi(root, Track.Builder.box(Vector3(0.12, 0.02, 4.6)), Track.Builder.mat(Color(0.8, 0.8, 0.78), 0.0, 0.6), lines)
	track["parked"].append_array(cars)
	# Schild "P"
	var sp: Vector3 = Track.frame_at(c, e0)["pos"] + Track.frame_at(c, e0)["right"] * (half - 0.8)
	sp.y = 0.0
	_sign(root, sp, Basis.looking_at(-Track.frame_at(c, e0)["fwd"], Vector3.UP), "P", Color(0.1, 0.3, 0.75))


## Schild auf einem Pfosten (umfahrbar): Text auf farbiger Tafel
static func _sign(root: Node3D, pos: Vector3, basis: Basis, text: String, col: Color) -> void:
	var k := Track.Knockable.new()
	k.transform = Transform3D(basis, pos + Vector3(0, Track.CURB_H, 0))
	k.mass = 8.0
	k.slowdown = 0.99
	var grey := Track.Builder.mat(Color(0.45, 0.46, 0.48), 0.6, 0.4)
	Track.Builder._add(k, Track.Builder.box(Vector3(0.07, 2.4, 0.07)), grey, Vector3(0, 1.2, 0))
	Track.Builder._add(k, Track.Builder.box(Vector3(0.7, 0.7, 0.05)), Track.Builder.mat(col, 0.0, 0.5), Vector3(0, 2.3, -0.04))
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = 0.008
	l.modulate = Color(1, 1, 1)
	l.position = Vector3(0, 2.3, -0.07)
	l.rotation.y = PI
	l.double_sided = false
	k.add_child(l)
	Track._knock_shape(k, Vector3(0.3, 2.4, 0.3), Vector3(0, 1.2, 0))
	root.add_child(k)


## Einmündungen: an Kreuzungen der Hauptstraße Ampeln (für die Hauptstraße und die Querstraße) und Zebrastreifen über
## die Querstraße, an Einmündungen ein Vorfahrt-achten-Schild
static func build_junctions(root: Node3D, track: Dictionary, rng: RandomNumberGenerator) -> void:
	root.set_meta("track_ref", track)
	parked_cars(root, track.get("parked", []), rng)
	track["parked"] = []
	_trees(root, track.get("trees", []), rng)
	track["trees"] = []
	var main: Curve3D = track["curve"]
	var white := Track.Builder.mat(Color(0.85, 0.85, 0.85), 0.0, 0.5)
	var zebra := []
	var mm := {}  # Ampeln und Schilder der ganzen Stadt: Teil -> [Mesh, Material, Lagen] (je Teil ein MultiMesh)
	for j in track.get("junctions", []):
		var p: Dictionary = track["paths"][j["path"]]
		if p["kind"] == "passage":
			continue
		var c: Curve3D = p["curve"]
		var L := c.get_baked_length()
		var fm := Track.frame_at(main, j["d"])
		var hwm: float = Track.hw(track, j["d"])
		# Stelle auf der Nebenstraße gleich hinter dem Gehweg der Hauptstraße, Blick zur Hauptstraße
		var dd := 0.0
		var at := -1.0
		while dd < minf(L, 60.0):
			var x: float = dd if j["start"] else L - dd
			if main_clear(track, c.sample_baked(x)) > Track.WALK + 1.5:
				at = x
				break
			dd += 1.0
		if at < 0.0:
			continue
		var fs := Track.frame_at(c, at)
		var toward: Vector3 = -fs["fwd"] if j["start"] else fs["fwd"]
		var half: float = p["half_w"]
		# Zebrastreifen über die Nebenstraße
		if p["cls"] != "gasse":
			var zc: Vector3 = fs["pos"] + toward * 1.5
			var bz := Basis.looking_at(toward, Vector3.UP)
			var n := int(half * 2.0 / 2.0)
			for i in n:
				var lx := -half + 1.0 + i * 2.0
				zebra.append(Transform3D(bz, Vector3(zc.x, 0.03, zc.z) + bz.x * lx))
		var right_side: Vector3 = toward.cross(Vector3.UP).normalized()  # rechts in Fahrtrichtung zur Hauptstraße
		var corner: Vector3 = fs["pos"] + right_side * (half + 0.9) - toward * 0.5
		corner.y = 0.0
		if j["x"]:
			# Kreuzung: Hauptstraße und Querstraße abwechselnd grün (halber Umlauf versetzt, Umlauf 12 s)
			var ph := 3.0 * float(posmod(int(j["d"]), 4))
			_signal(root, mm, corner, -toward, half, ph + 6.0)
			# Ampel für die Hauptstraße an dieser Ecke (gegen die Fahrtrichtung, die hier ankommt)
			var sd := signf((fs["pos"] - fm["pos"]).dot(fm["right"]))
			var dirm: Vector3 = fm["fwd"] * -sd  # Verkehr auf dieser Seite kommt aus dieser Richtung
			var mc: Vector3 = fm["pos"] + fm["right"] * sd * (hwm + 1.0) + dirm * (half + 2.5)
			mc.y = 0.0
			_signal(root, mm, mc, dirm, hwm * 0.45, ph, true)
		else:
			_yield_sign(root, mm, corner, -toward)
	if not zebra.is_empty():
		Track._multi(root, Track.Builder.box(Vector3(1.0, 0.02, 3.0)), white, zebra)
	for key in mm:
		Track._multi(root, mm[key][0], mm[key][1], mm[key][2])
	root.remove_meta("track_ref")


## Steht ein Mast hier auf keiner Fahrbahn (weder Hauptstraße noch ein Weg)?
static func _free_spot(root: Node3D, pos: Vector3) -> bool:
	var track: Dictionary = root.get_meta("track_ref")
	return main_clear(track, pos) > 0.4 and branch_clear(track, pos, true, false) > 0.4


static func _mm_add(mm: Dictionary, key: String, mesh: Mesh, mat: Material, xf: Transform3D) -> void:
	if not mm.has(key):
		mm[key] = [mesh, mat, []]
	mm[key][2].append(xf)


## Ampel an der Ecke: Mast, Ausleger über die Fahrbahn (arm m), Kopf mit drei Lichtern (traffic_light.gdshader,
## Umlauf ab phase); fester Mast
static func _signal(root: Node3D, mm: Dictionary, pos: Vector3, face: Vector3, arm: float, phase: float, big := false) -> void:
	if not _free_spot(root, pos):
		return
	var t := Transform3D(Basis.looking_at(-face, Vector3.UP), pos + Vector3(0, Track.CURB_H, 0))
	var dark := Track.Builder.mat(Color(0.06, 0.06, 0.07), 0.6, 0.4)
	var unit := Track.Builder.box(Vector3.ONE)
	var h := 5.0 if big else 3.6
	_mm_add(mm, "mast", unit, dark, t * Transform3D(Basis.from_scale(Vector3(0.16, h, 0.16)), Vector3(0, h / 2.0, 0)))
	var ax := minf(arm, 4.5) if big else 0.0
	if ax > 0.0:
		_mm_add(mm, "mast", unit, dark, t * Transform3D(Basis.from_scale(Vector3(ax + 0.2, 0.12, 0.12)), Vector3(-ax / 2.0, h, 0)))
	var head_pos := Vector3(-ax, h - 0.6 if big else h - 0.5, 0)
	_mm_add(mm, "mast", unit, dark, t * Transform3D(Basis.from_scale(Vector3(0.42, 1.25, 0.32)), head_pos))
	for k in 3:
		var key := "licht%d_%d" % [k, int(phase)]
		if not mm.has(key):
			var sm := SphereMesh.new()
			sm.radius = 0.12
			sm.height = 0.24
			sm.radial_segments = 8
			sm.rings = 4
			var lm := ShaderMaterial.new()
			lm.shader = Track.LIGHT_SHADER
			lm.set_shader_parameter("which", float(k))
			lm.set_shader_parameter("phase", phase)
			mm[key] = [sm, lm, []]
		mm[key][2].append(t * Transform3D(Basis(), head_pos + Vector3(0, 0.38 - k * 0.38, 0.17)))
	Track._solid_cyl(root, 0.14, 2.0, pos + Vector3(0, 1.0 + Track.CURB_H, 0))


## Vorfahrt achten: rot-weißes Dreieck mit der Spitze nach unten auf einem Pfosten (fest wie ein Poller)
static func _yield_sign(root: Node3D, mm: Dictionary, pos: Vector3, face: Vector3) -> void:
	if not _free_spot(root, pos):
		return
	var t := Transform3D(Basis.looking_at(-face, Vector3.UP), pos + Vector3(0, Track.CURB_H, 0))
	var grey := Track.Builder.mat(Color(0.45, 0.46, 0.48), 0.6, 0.4)
	_mm_add(mm, "pfosten", Track.Builder.box(Vector3(0.07, 2.3, 0.07)), grey, t * Transform3D(Basis(), Vector3(0, 1.15, 0)))
	if not mm.has("dreieck_rot"):
		mm["dreieck_rot"] = [_tri(0.8), Track.Builder.mat(Color(0.85, 0.08, 0.06), 0.0, 0.5), []]
		mm["dreieck_weiss"] = [_tri(0.55), Track.Builder.mat(Color(0.95, 0.95, 0.93), 0.0, 0.5), []]
	mm["dreieck_rot"][2].append(t * Transform3D(Basis(), Vector3(0, 2.15, 0.06)))
	mm["dreieck_weiss"][2].append(t * Transform3D(Basis(), Vector3(0, 2.15 + 0.06, 0.08)))
	Track._solid_cyl(root, 0.06, 2.0, pos + Vector3(0, 1.0 + Track.CURB_H, 0))


## Dreieck (Spitze unten) der Seitenlänge a, zur Straße (+Z) gewandt, beidseitig
static func _tri(a: float) -> ArrayMesh:
	var h := a * 0.866
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var v := [Vector3(-a / 2.0, h / 3.0, 0), Vector3(a / 2.0, h / 3.0, 0), Vector3(0, -h * 2.0 / 3.0, 0)]
	for tri in [[v[0], v[2], v[1]], [v[0], v[1], v[2]]]:
		for q in tri:
			st.add_vertex(q)
	st.generate_normals()
	return st.commit()


## Bodenhöhe auf einer neuen Straße: Gehweg und Grünstreifen haben Bordsteinhöhe, Parkbucht und Fahrbahn nicht
static func curb(p: Dictionary, lat: float) -> bool:
	var i := 0 if lat < 0.0 else 1
	var a := absf(lat)
	var h: float = p["half_w"]
	if a <= h + 0.05 or float(p["walk"]) <= 0.0:
		return false
	if p["strip_kind"][i] == "park" and a <= h + float(p["strip"][i]):
		return false
	return true
