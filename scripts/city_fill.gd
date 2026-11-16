extends RefCounted
## Stadtfüllung der erfundenen Städte (seit 2.39). Bis 2.38 standen hinter der Straßenfront nur zwei Häuserreihen,
## danach kamen gleich Felder (in Frankfurt Hochhäuser, direkt dahinter Raps), in den Rundkursen lag innen eine große
## graue Fläche. Jetzt reicht die Stadt je nach Viertel 170–260 m hinter die Gehwegkante, in Rundkursen bis zur Mitte.
##
## Aufbau: Blöcke in Bändern entlang der Straße (wie eine Stadt, die an ihrer Hauptstraße gewachsen ist), um jeden
## Block eine halbe Erschließungsstraße (Gehweg, Fahrbahn mit parkenden Autos, Bäume, Laternen; nicht befahrbar),
## zusammen ein Straßennetz. Je Viertel und Abstand eine Nutzung: Blockrand mit Innenhof, Bürohäuser, Türme, Altstadt,
## Zeilen, Reihen-, Einfamilienhäuser und Villen mit Gärten, Hallen, Lager, Containerflächen; dazu Parks, Plätze,
## Parkplätze, Schule, Kirche, Sportplatz, Kleingärten, Brachen. Dicht und hoch an der Straße, nach außen niedriger und
## grüner, am Stadtrand Gärten.
##
## Nie auf Wegen (track["paths"], auch Nebenstraßen und Ausfahrten; genau gegen das Rechteck der Zelle), fremden
## Fahrbahnen (track["keepout"]: zur Nachbarstadt nur bis zur Mitte, von Autobahnringen mit ihren Häusern 110 m weg),
## Wasser (eigene Flüsse und Seen, Löcher der Nachbarn), Hügeln, Bahn, Wahrzeichen; einzelne Häuser und Bäume auch nicht
## auf den Häusern der Front. Jede Fläche gehört dem Straßenstück, dem sie am nächsten ist (sonst schöben sich in
## Kurven und Rundkursen Blöcke verschiedener Seiten übereinander). Lücken (Ecken, Inneres der Rundkurse) füllen danach
## kleinere, frei ausgerichtete Blöcke (_gap).
##
## Kosten: Häuser im Häuser-Batch der Strecke (track_builder._bb_box, je 120-m-Zelle ein Mesh mit den übrigen Häusern),
## Böden und kleine Körper (Hecken, Lauben, Container, Kräne, Laternenmasten) je 240-m-Zelle ein Mesh mit
## Vertexfarben, Bäume, Autos und Leuchten je ein MultiMesh mit Sichtweite. Planung und Bau in Schritten: im Browser
## 6 ms je Bild, im Bau-Thread am Stück. Die Welt plant die Blöcke schon beim Laden (world_layout, ohne Häuser der
## Front), damit die Landschaft dort flach bleibt und Stadtboden hat (world_points). Nur in der Welt; Rennen bauen
## ohne (race["fill"] bzw. --racefill zum Testen, --nofill schaltet sie in der Welt ab).

const Track := preload("res://scripts/track_builder.gd")
const Design := preload("res://scripts/track_design.gd")
const People := preload("res://scripts/people.gd")
const Traffic := preload("res://scripts/traffic_car.gd")

const FRONT := 62.0  # so weit hinter der Gehwegkante der Hauptstraße beginnen die Blöcke (davor Front und zwei Reihen)
const FRONT_BRANCH := 28.0  # ... hinter dem Rand einer Querstraße (dort steht nur eine Häuserreihe)
const STREET := 12.0  # Erschließungsstraße zwischen zwei Blöcken: je 2 m Gehweg, 8 m Fahrbahn mit Parkstreifen
const WALKW := 2.0
const CELL := 240.0  # Böden, kleine Körper, Bäume, Autos, Laternen: je Zelle ein Mesh bzw. MultiMesh
const IX_CELL := 40.0  # Raster für Abstandsabfragen (Wegpunkte, Sperrflächen)
const RING_CLEAR := 110.0  # Abstand zur Mitte eines Autobahnrings (dort stehen dessen Häuser bis gut 105 m)
const VORONOI := 16.0  # zur Nachbarstadt: nur wo die eigene Straße mindestens so viel näher ist
const MAX_BANDS := 7  # Rundkurse: innen bis zu so viele Bänder (bis zur Mitte)
const FLOOR := 3.2

## Viertel (track_builder.DISTRICTS): Tiefe der Blöcke je Band (ohne Straße; das letzte Band ist der Stadtrand),
## Blocklänge entlang der Straße, Höhen je Zone (an der Straße, dahinter, Rand), Nutzungen je Zone mit Gewicht
const STYLE := {
	"downtown": {"bands": [58.0, 52.0, 46.0], "len": [80.0, 112.0], "h": [[22.0, 44.0], [15.0, 27.0], [7.0, 11.0]],
		"use": [{"rand": 4.0, "buero": 3.0, "turm": 1.6, "platz": 0.8, "park": 0.7, "parken": 0.7},
			{"rand": 4.0, "zeilen": 1.5, "buero": 1.5, "park": 1.0, "schule": 0.7, "kirche": 0.4, "parken": 0.6, "platz": 0.4},
			{"efh": 2.5, "reihen": 2.0, "zeilen": 1.2, "garten": 1.2, "sport": 0.9, "park": 1.0}]},
	"boulevard": {"bands": [54.0, 48.0, 42.0], "len": [74.0, 102.0], "h": [[16.0, 23.0], [13.0, 19.0], [7.0, 11.0]],
		"use": [{"rand": 7.0, "park": 1.0, "platz": 1.0, "kirche": 0.6, "parken": 0.5},
			{"rand": 5.0, "zeilen": 1.2, "park": 1.2, "schule": 0.7, "kirche": 0.5, "parken": 0.5, "platz": 0.4},
			{"villen": 3.0, "reihen": 2.0, "garten": 1.5, "sport": 1.0, "park": 1.5}]},
	"shops": {"bands": [50.0, 44.0, 40.0], "len": [64.0, 92.0], "h": [[13.0, 19.0], [10.0, 16.0], [7.0, 10.0]],
		"use": [{"rand": 6.5, "platz": 1.5, "parken": 1.0, "park": 0.5, "kirche": 0.5},
			{"rand": 5.0, "zeilen": 1.5, "park": 1.0, "schule": 0.7, "parken": 0.9, "kirche": 0.5, "platz": 0.5},
			{"efh": 3.5, "reihen": 2.5, "garten": 1.5, "sport": 1.0, "park": 1.5}]},
	"chinatown": {"bands": [46.0, 42.0], "len": [54.0, 78.0], "h": [[12.0, 20.0], [9.0, 15.0]],
		"use": [{"rand": 7.5, "platz": 1.2, "parken": 0.8, "park": 0.5},
			{"reihen": 3.5, "rand": 3.0, "garten": 2.0, "park": 1.5, "sport": 0.6}]},
	"residential": {"bands": [42.0, 40.0, 38.0], "len": [46.0, 68.0], "h": [[10.0, 15.0], [8.0, 12.0], [6.5, 9.0]],
		"use": [{"altstadt": 6.0, "kirche": 0.8, "platz": 1.2, "park": 1.0, "parken": 0.5},
			{"altstadt": 3.0, "reihen": 2.5, "efh": 2.0, "park": 1.0, "schule": 0.6, "kirche": 0.5, "garten": 0.5},
			{"efh": 4.5, "garten": 2.5, "sport": 1.0, "park": 1.0, "reihen": 1.0}]},
	"industrial": {"bands": [78.0, 70.0], "len": [96.0, 150.0], "h": [[9.0, 14.0], [7.0, 12.0]],
		"use": [{"halle": 4.0, "lager": 2.5, "container": 2.2, "parken": 0.8},
			{"halle": 3.5, "container": 2.5, "lager": 2.0, "parken": 0.8, "brache": 1.0, "garten": 0.6}]},
	"highway": {"bands": [64.0, 56.0], "len": [86.0, 130.0], "h": [[14.0, 32.0], [8.0, 14.0]],
		"use": [{"buero": 4.0, "parken": 2.2, "halle": 2.5, "turm": 0.8},
			{"halle": 3.5, "parken": 2.0, "buero": 2.5, "zeilen": 1.0, "park": 1.0, "sport": 0.6}]},
}
## Seltene Nutzungen: Mindestabstand zur nächsten gleichen (m) und Mindestgröße des Blocks (halbe Tiefe, halbe Länge)
const RARE := {"kirche": [520.0, 17.0, 22.0], "schule": [800.0, 21.0, 27.0], "sport": [650.0, 24.0, 34.0],
	"platz": [260.0, 14.0, 16.0], "park": [170.0, 12.0, 14.0], "turm": [150.0, 20.0, 20.0], "parken": [200.0, 12.0, 16.0],
	"garten": [0.0, 16.0, 20.0], "container": [0.0, 20.0, 26.0], "halle": [0.0, 18.0, 22.0], "buero": [0.0, 18.0, 24.0]}

## Farben (sRGB wie Builder.mat): Böden und kleine Körper
const C_ASPHALT := Color(0.15, 0.15, 0.16)
const C_WALK := Color(0.42, 0.41, 0.39)
const C_LAWN := Color(0.2, 0.33, 0.13)
const C_LAWN2 := Color(0.25, 0.37, 0.14)
const C_PAVE := Color(0.5, 0.48, 0.44)
const C_PATH := Color(0.55, 0.5, 0.4)
const C_CONCRETE := Color(0.36, 0.36, 0.35)
const C_LINE := Color(0.85, 0.85, 0.82)
const C_HEDGE := Color(0.09, 0.2, 0.08)
const C_WATER := Color(0.09, 0.17, 0.23)
const C_TRACK := Color(0.55, 0.24, 0.17)
const C_PITCH := Color(0.18, 0.4, 0.15)
const C_SAND := Color(0.72, 0.64, 0.46)
const C_SOIL := Color(0.3, 0.21, 0.13)
const C_GRAVEL := Color(0.47, 0.44, 0.38)
const CONTAINER := [Color(0.62, 0.14, 0.08), Color(0.1, 0.24, 0.52), Color(0.8, 0.45, 0.08), Color(0.12, 0.42, 0.22),
	Color(0.55, 0.56, 0.58), Color(0.75, 0.7, 0.15), Color(0.42, 0.12, 0.1)]
const SHEDS := [Color(0.55, 0.32, 0.18), Color(0.25, 0.42, 0.3), Color(0.62, 0.6, 0.55), Color(0.42, 0.2, 0.15), Color(0.3, 0.38, 0.5)]

static var _mats := {}  # geteilte Materialien (_mat)
static var _meshes := {}  # geteilte Formen: Baum, Auto, Leuchte
static var off := false  # Test: Füllung aus (Messwerkzeuge vergleichen im selben Lauf)
## Test (dbg = true, Draufsicht-Werkzeug): warum Blöcke nicht passten (Grund -> Anzahl) und wo (dbg_rej)
static var dbg := false
static var why := {}
static var dbg_rej := []
static var dbg_pos := Vector3.ZERO
static var _wk := ""


static func _no(k: String) -> void:
	if dbg:
		why[k + _wk] = why.get(k + _wk, 0) + 1
		dbg_rej.append([dbg_pos, k])


# --- Wer bekommt eine Füllung? ---------------------------------------------------------------------------------------

## Erfundene Städte (keine echten Stadtpläne) mit Häusern: Sprints, Rundkurse, Drift-Kurse; nicht Autobahn, Drag,
## Waldstrecke, Berg. Nur in der Welt: im Rennen sieht man nachts fast nur die Front, das Laden dauerte 0,2–0,5 s länger
## (race["fill"] bzw. --racefill baut sie trotzdem).
static func wanted(track: Dictionary, race: Dictionary) -> bool:
	if not track["city"].is_empty() or track.has("mountain") or race.get("forest", false):
		return false
	if off or OS.get_cmdline_user_args().has("--nofill"):
		return false  # Test: wie bis 2.38 (Vergleichsbilder, Kosten)
	if not track["type"] in ["sprint", "circuit", "drift"]:
		return false
	return track["world"] or race.get("fill", false) or OS.get_cmdline_user_args().has("--racefill")


# --- Planung ----------------------------------------------------------------------------------------------------------

## Ganze Planung am Stück (Welt beim Laden, Prüfwerkzeuge)
static func plan(track: Dictionary, seed: int, quick := false) -> Dictionary:
	var P := plan_begin(track, seed, quick)
	while not plan_step(track, P, -1):
		pass
	return P


## Blöcke in Weltkoordinaten für die Landschaft (landscape.gd: dort flach und Stadtboden): je Block x, z der Mitte und
## halbe Diagonale der Zelle (mit Straße)
static func world_points(track: Dictionary, seed: int, xf: Transform3D) -> PackedVector3Array:
	var P := plan(track, seed, true)
	var out := PackedVector3Array()
	for b in P["blocks"]:
		var w: Vector3 = xf * (b["c"] as Vector3)
		out.append(Vector3(w.x, w.z, Vector2(b["hd"] + STREET * 0.5, b["hl"] + STREET * 0.5).length()))
	return out


static func plan_begin(track: Dictionary, seed: int, quick := false) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 7919 + 211
	var gens := _gens(track)
	var P := {"ix": _path_index(track, track["paths"]), "gix": _path_index(track, gens), "ko": _ko_index(track), "rng": rng,
		"blocks": [], "bgrid": {}, "tasks": [], "ti": 0, "poly": PackedVector2Array(), "holes": _holes_local(track),
		"quick": quick, "gens": gens, "seed": seed, "occ": {}, "houses": {}}
	if track["loop"]:
		var bp: PackedVector3Array = (track["curve"] as Curve3D).get_baked_points()
		var poly := PackedVector2Array()
		for i in range(0, bp.size(), 6):
			poly.append(Vector2(bp[i].x, bp[i].z))
		P["poly"] = poly
	for k in MAX_BANDS:
		for gi in gens.size():
			for side in [-1.0, 1.0]:
				P["tasks"].append([k, gi, side])
	# danach Lücken: im Inneren der Rundkurse ein Raster, sonst entlang der Straßen in der Tiefe des ersten Bands
	# (Ecken und Knicke, wo die Bänder nicht hinreichen)
	var cand := []
	if not (P["poly"] as PackedVector2Array).is_empty():
		var lo := Vector2(1e9, 1e9)
		var hi := Vector2(-1e9, -1e9)
		for q in P["poly"]:
			lo = lo.min(q)
			hi = hi.max(q)
		var gz := lo.y + 14.0
		while gz < hi.y:
			var gx := lo.x + 14.0
			while gx < hi.x:
				if Geometry2D.is_point_in_polygon(Vector2(gx, gz), P["poly"]):
					cand.append(Vector2(gx, gz))
				gx += 28.0
			gz += 28.0
	for gi in gens.size():
		var g: Dictionary = gens[gi]
		var c: Curve3D = g["curve"]
		var L: float = g["length"]
		var d := 10.0
		while d < L - 10.0:
			var dk := _dkey(track, g, d)
			if STYLE.has(dk):
				var f := Track.frame_at(c, d)
				var t: float = _front(track, g, d, dk) + (float(STYLE[dk]["bands"][0]) + STREET) * 0.5
				for side in [-1.0, 1.0]:
					var q: Vector3 = f["pos"] + f["right"] * side * t
					cand.append(Vector2(q.x, q.z))
			d += 28.0
	for i in range(0, cand.size(), 40):
		P["tasks"].append(["gap", cand.slice(i, i + 40)])
	return P


## Planung in Stücken; budget_ms < 0: alles. true = fertig (dann sind auch die Nutzungen verteilt).
static func plan_step(track: Dictionary, P: Dictionary, budget_ms: int) -> bool:
	var t0 := Time.get_ticks_msec()
	var tasks: Array = P["tasks"]
	while P["ti"] < tasks.size():
		var t: Array = tasks[P["ti"]]
		var done := true
		if t[0] is String:
			for q in t[1]:
				_gap(track, P, q)
		else:
			done = _band(track, P, t, 12 if budget_ms >= 0 else 100000)
		if done:
			P["ti"] += 1
		if budget_ms >= 0 and Time.get_ticks_msec() - t0 >= budget_ms:
			return false
	if not P["quick"] and not P.has("used"):
		_assign(track, P)
		P["used"] = true
	return true


## Straßen, an denen Blöcke wachsen: die Hauptstraße und lange Querstraßen durchs Innere (keine Ausfahrten, Gassen,
## Durchfahrten; die Nebenstraßen hinter der ersten Reihe liegen schon im Bereich der Front)
static func _gens(track: Dictionary) -> Array:
	var out := []
	for p in track["paths"]:
		if p["id"] != 0:
			var k: String = p["kind"]
			if k in ["ramp", "slip", "passage", "spur", "lake", "alley", "fork"] or float(p["length"]) < 200.0:
				continue
			if k == "lane" and not p.get("cross", false):
				continue
		out.append(p)
	return out


## Viertel an der Stelle s eines Wegs (Querstraßen: wo sie abzweigen)
static func _dkey(track: Dictionary, g: Dictionary, s: float) -> String:
	var arr: Array = track["districts"]
	var d: float = s if g["id"] == 0 else float(g["from"])
	if track["loop"]:
		d = fposmod(d, track["length"])
	return arr[clampi(int(d / Track.DISTRICT_LEN), 0, arr.size() - 1)]


## Querabstand von der Mitte des Wegs, ab dem die Blöcke beginnen
static func _front(track: Dictionary, g: Dictionary, s: float, dk: String) -> float:
	if g["id"] != 0:
		return float(g["half_w"]) + FRONT_BRANCH
	var dist: Dictionary = Track.DISTRICTS.get(dk, {})
	return Track.hw(track, s) + Track.WALK + dist.get("setback", 0.0) + Track._lift(track, s) * 1.6 + FRONT


## Ein Band (k) an einer Seite eines Wegs entlang: Blöcke so lang wie gewünscht (in der Kurve auf der Höhe der
## Blockmitte gemessen), in Knicken kürzer; zu enge Knicke bleiben frei
## Aufgabe t = [Band k, Weg gi, Seite]; höchstens n Blöcke je Aufruf (Browser), die Stelle s steht dann in t[3].
## true = Band fertig
static func _band(track: Dictionary, P: Dictionary, t: Array, n_max: int) -> bool:
	var k: int = t[0]
	var gi: int = t[1]
	var side: float = t[2]
	var g: Dictionary = P["gens"][gi]
	var c: Curve3D = g["curve"]
	var L: float = g["length"]
	var loop: bool = g["id"] == 0 and track["loop"]
	var rng: RandomNumberGenerator = P["rng"]
	if t.size() < 4:
		t.append(rng.randf_range(0.0, 36.0) + (0.0 if loop else 6.0))
	var s: float = t[3]
	var s_end := L if loop else L - 6.0
	var n := 0
	while s < s_end:
		n += 1
		if n > n_max:
			t[3] = s
			return false
		var dk := _dkey(track, g, s)
		var st: Dictionary = STYLE.get(dk, {})
		var dist: Dictionary = Track.DISTRICTS.get(dk, {})
		if st.is_empty() or dist.get("rural", false):
			s += 25.0
			continue
		var bands: Array = st["bands"]
		var nb := bands.size()
		if k >= nb and not loop:
			s += 30.0
			continue
		var t0 := _front(track, g, s, dk)
		for j in k:
			t0 += float(bands[mini(j, bands.size() - 1)]) + STREET
		var dep: float = bands[mini(k, bands.size() - 1)]
		var tm := t0 + (dep + STREET) * 0.5
		var want: float = rng.randf_range(st["len"][0], st["len"][1]) + STREET
		var adv := _advance(c, s, side, tm, want, loop, L)
		var sb: float = adv[0]
		if adv[1]:
			_try_block(track, P, gi, side, k, s, minf(sb, s_end), tm, dep, dk, k >= nb)
		s = sb
	return true


## Ende eines Blocks ab s: Sehne auf Höhe tm etwa want lang, Drehung der Straße höchstens 26 Grad. [s_b, brauchbar]
static func _advance(c: Curve3D, s: float, side: float, tm: float, want: float, loop: bool, L: float) -> Array:
	var fa := Track.frame_at(c, s)
	var pa: Vector3 = fa["pos"] + fa["right"] * side * tm
	var sb := s + want
	for it in 3:
		var fb := Track.frame_at(c, sb)
		var pb: Vector3 = fb["pos"] + fb["right"] * side * tm
		var ch := Vector2(pb.x - pa.x, pb.z - pa.z).length()
		if ch < 1.0:
			break
		sb = s + (sb - s) * clampf(want / ch, 0.25, 4.0)
	sb = clampf(sb, s + 6.0, s + want * 4.0)
	if not loop:
		sb = minf(sb, L)
	var fb2 := Track.frame_at(c, sb)
	var ang: float = (fa["fwd"] as Vector3).angle_to(fb2["fwd"])
	var lim := deg_to_rad(26.0)
	if ang > lim:
		sb = s + maxf((sb - s) * lim / ang, 6.0)
		var fb3 := Track.frame_at(c, sb)
		var pb3: Vector3 = fb3["pos"] + fb3["right"] * side * tm
		if Vector2(pb3.x - pa.x, pb3.z - pa.z).length() < want * 0.45:
			return [s + maxf(sb - s, 8.0), false]
	return [sb, true]


## Block zwischen s_a und s_b im Band um tm prüfen und annehmen (zuerst ganz, dann kleiner)
static func _try_block(track: Dictionary, P: Dictionary, gi: int, side: float, k: int, sa: float, sb: float, tm: float,
		dep: float, dk: String, extra: bool) -> void:
	var g: Dictionary = P["gens"][gi]
	if dbg:
		_wk = "_b%d_g%d" % [k, gi]
	var c: Curve3D = g["curve"]
	var fa := Track.frame_at(c, sa)
	var fb := Track.frame_at(c, sb)
	var pa: Vector3 = fa["pos"] + fa["right"] * side * tm
	var pb: Vector3 = fb["pos"] + fb["right"] * side * tm
	var ch := Vector3(pb.x - pa.x, 0.0, pb.z - pa.z)
	var cl := ch.length()
	if cl < 30.0:
		_no("kurz")
		return
	var out: Vector3 = ((fa["right"] as Vector3) + (fb["right"] as Vector3)) * side
	var x := Vector3(-ch.z, 0.0, ch.x) / cl
	if x.dot(out) < 0.0:
		x = -x
	if (fb["pos"] - fa["pos"]).dot(ch) <= 0.0:
		_no("rueckwaerts")
		return  # Innenseite einer engen Kurve: die versetzte Linie läuft rückwärts
	var ctr := Vector3((pa.x + pb.x) * 0.5, 0.0, (pa.z + pb.z) * 0.5)
	dbg_pos = ctr
	var c2 := Vector2(ctr.x, ctr.z)
	var inside: bool = not (P["poly"] as PackedVector2Array).is_empty() and Geometry2D.is_point_in_polygon(c2, P["poly"])
	if extra and not inside:
		_no("extra_aussen")
		return  # zusätzliche Bänder nur im Inneren eines Rundkurses
	# Besitz: kein anderes Stück einer Hauptstraße oder Querstraße näher als dieses (sonst gehört die Fläche dorthin);
	# Nebenstraßen hinter der Front zählen nicht, an ihnen gilt nur der Abstand (_area_ok)
	var sm := (sa + sb) * 0.5
	var fm := Track.frame_at(c, sm)
	var hw_g: float = (Track.hw(track, sm) + Track.WALK) if g["id"] == 0 else float(g["half_w"])
	var dg := Vector2(ctr.x - fm["pos"].x, ctr.z - fm["pos"].z).length() - hw_g
	if _edge_dist(P["gix"], c2, dg - 12.0) < dg - 12.0:
		_no("besitz")
		return
	# Nachbarstädte: nur bis zur Mitte; Autobahnringe: Abstand für ihre Häuser
	if not _ko_center_ok(P, c2, dg + hw_g):
		_no("nachbar")
		return
	var hd := dep * 0.5
	var hl := cl * 0.5 - STREET * 0.5
	var z := x.cross(Vector3.UP)
	for attempt in 3:
		if hl < 12.0 or hd < 10.0:
			_no("klein")
			return
		var ex := hd + STREET * 0.5
		var ez := hl + STREET * 0.5
		var aok := _area_ok(track, P, ctr, x, z, ex, ez)
		if aok and not _overlaps(P, ctr, x, z, ex, ez):
			break
		if attempt == 2:
			_no("flaeche" if not aok else "ueberlapp")
			return
		hl *= 0.78
		hd *= 0.84
	var b := {"c": ctr, "x": x, "z": z, "hd": hd, "hl": hl, "k": k, "dk": dk, "inside": inside, "s": sm, "g": gi,
		"side": side, "use": "", "tm": tm}
	var bands: int = (STYLE[dk]["bands"] as Array).size()
	# Zone: 0 an der Straße, 1 dahinter, 2 Stadtrand (Rundkurse innen nie Stadtrand)
	b["zone"] = mini(k, bands - 1)
	if inside:
		b["zone"] = mini(k, mini(1, bands - 1))
	_accept(P, b)


## Lücke bei p füllen: liegt p in keinem Block, einen freien Block nach der nächsten Hauptstraße bzw. Querstraße
## ausrichten, erst groß, dann kleiner. Abstand zur Front wie die Bänder (FRONT bzw. FRONT_BRANCH, etwas weniger).
static func _gap(track: Dictionary, P: Dictionary, p: Vector2) -> void:
	if dbg:
		_wk = "_gap"
	if _covered(P, p):
		return
	# billige Prüfungen zuerst: auf oder an einem Weg, einer Sperrfläche, im Wasser
	if _edge_dist(P["ix"], p, 8.0) < 7.0 or not _ko_point_ok(P, p) or _in_hole(P, p, 4.0):
		return
	if not track["rivers"].is_empty() and Track._river_near(track, Vector3(p.x, 0.0, p.y), 6.0) < 5.0:
		return
	var gix: Dictionary = P["gix"]
	var ni := _nearest(gix, p, 330.0)
	if ni < 0:
		return
	var ref: Array = gix["ref"][ni]
	var g: Dictionary = P["gens"][ref[0]]
	var dk := _dkey(track, g, ref[1])
	if not STYLE.has(dk) or Track.DISTRICTS.get(dk, {}).get("rural", false):
		return
	var st: Dictionary = STYLE[dk]
	var main: bool = g["id"] == 0
	var front: float = (FRONT - 8.0) if main else FRONT_BRANCH - 4.0
	var de := p.distance_to(gix["pts"][ni]) - float(gix["hw"][ni])
	var inside: bool = not (P["poly"] as PackedVector2Array).is_empty() and Geometry2D.is_point_in_polygon(p, P["poly"])
	var reach: float = front + float(st["bands"][0]) + STREET
	if not inside and (de > reach + 10.0 or de < front):
		return
	var tan: Vector2 = gix["tan"][ni]
	var z := Vector3(tan.x, 0.0, tan.y)
	var x := z.cross(Vector3.DOWN)  # quer; Seite egal, x × oben = z bleibt rechtshändig
	z = x.cross(Vector3.UP)
	var ctr := Vector3(p.x, 0.0, p.y)
	dbg_pos = ctr
	if not _ko_center_ok(P, p, de + float(gix["hw"][ni])):
		_no("nachbar")
		return
	var dep: float = st["bands"][0]
	var sizes := [[dep * 0.5, float(st["len"][0]) * 0.5], [dep * 0.36, float(st["len"][0]) * 0.34], [12.0, 13.0]]
	var last := ""
	for sz in sizes:
		var hd: float = sz[0]
		var hl: float = sz[1]
		var ex := hd + STREET * 0.5
		var ez := hl + STREET * 0.5
		if not _front_ok(gix, P["gens"], ctr, x, z, ex, ez, front):
			last = "g_front"
			continue
		if _overlaps(P, ctr, x, z, ex, ez):
			last = "g_block"
			continue
		if not _area_ok(track, P, ctr, x, z, ex, ez):
			last = "g_flaeche"
			continue
		if not (P["houses"] as Dictionary).is_empty():
			var foot := [p, Vector2(x.x, x.z), Vector2(z.x, z.z), hd, hl]
			if _occ_pen(P["houses"], foot, Vector2(hd, hl).length()) > 4.0:
				last = "g_haus"
				continue
		var b := {"c": ctr, "x": x, "z": z, "hd": hd, "hl": hl, "k": 0, "dk": dk, "inside": inside, "s": float(ref[1]),
			"g": ref[0], "side": 0.0, "use": "", "tm": de, "gap": true}
		b["zone"] = 0 if de < 120.0 else mini(1, (st["bands"] as Array).size() - 1)
		_accept(P, b)
		return
	# kein Block passt (meist liegt die Lücke zwischen den hinteren Reihen und den Querstraßen): ein Hof ohne eigene
	# Straße und ohne Häuser (Boden, Bäume, Autos, Garagen), bis 2,5 m an jede Wegkante, aber nur, wo kein Haus steht;
	# erst groß, auch etwas neben dem Rasterpunkt. Nur beim Bauen (die Häuser der Front sind erst dann bekannt)
	var houses: Dictionary = P["houses"]
	if P["quick"]:
		_no("luecke_" + last)
		return  # Planung beim Laden: Höfe liegen zwischen Häusern an den Straßen, dort ist die Landschaft ohnehin Stadt
	var offs := [Vector2.ZERO, Vector2(0.45, 0.0), Vector2(-0.45, 0.0), Vector2(0.0, 0.45), Vector2(0.0, -0.45)]
	for sz in [[24.0, 30.0], [17.0, 21.0], [12.0, 15.0], [8.0, 10.0], [6.0, 7.0], [4.5, 5.5]]:
		var hd2: float = sz[0]
		var hl2: float = sz[1]
		for off in offs:
			var c3: Vector3 = ctr + x * off.x * hd2 + z * off.y * hl2
			var p3 := Vector2(c3.x, c3.z)
			if _overlaps_tight(P, c3, x, z, hd2 + 1.0, hl2 + 1.0):
				continue
			if not houses.is_empty():
				var foot2 := [p3, Vector2(x.x, x.z), Vector2(z.x, z.z), hd2, hl2]
				if _occ_pen(houses, foot2, Vector2(hd2, hl2).length()) > 1.0:
					continue
			if not _area_ok(track, P, c3, x, z, hd2 + 1.0, hl2 + 1.0, 1.5):
				continue
			var bh := {"c": c3, "x": x, "z": z, "hd": hd2, "hl": hl2, "k": 0, "dk": dk, "inside": inside, "s": float(ref[1]),
				"g": ref[0], "side": 0.0, "use": "hof", "tm": de, "gap": true, "zone": 0}
			_accept(P, bh, 1.0)
			return
	_no("luecke_" + last)


## Überlappt das Rechteck (ohne Straße) eine schon angenommene Zelle überhaupt (mehr als 0,5 m)?
static func _overlaps_tight(P: Dictionary, ctr: Vector3, x: Vector3, z: Vector3, ex: float, ez: float) -> bool:
	var foot := [Vector2(ctr.x, ctr.z), Vector2(x.x, x.z), Vector2(z.x, z.z), ex, ez]
	var key := Vector2i(floori(ctr.x / 80.0), floori(ctr.z / 80.0))
	for gx in range(key.x - 2, key.x + 3):
		for gz in range(key.y - 2, key.y + 3):
			for o in P["bgrid"].get(Vector2i(gx, gz), []):
				if Track._foot_pen(foot, o) > 0.5:
					return true
	return false


## Liegt p in einer schon angenommenen Zelle?
static func _covered(P: Dictionary, p: Vector2) -> bool:
	var key := Vector2i(floori(p.x / 80.0), floori(p.y / 80.0))
	for gx in range(key.x - 2, key.x + 3):
		for gz in range(key.y - 2, key.y + 3):
			for o in P["bgrid"].get(Vector2i(gx, gz), []):
				var rel: Vector2 = p - o[0]
				if absf(rel.dot(o[1])) < o[3] and absf(rel.dot(o[2])) < o[4]:
					return true
	return false


## Hält die Zelle zu allen Haupt- und Querstraßen den Abstand der Front ein (Ecken und Kantenmitten)?
static func _front_ok(gix: Dictionary, gens: Array, ctr: Vector3, x: Vector3, z: Vector3, ex: float, ez: float, front: float) -> bool:
	for su in [-1.0, 0.0, 1.0]:
		for sv in [-1.0, 0.0, 1.0]:
			var q: Vector3 = ctr + x * su * ex + z * sv * ez
			var ni := _nearest(gix, Vector2(q.x, q.z), front + 2.0)
			if ni >= 0:
				var g: Dictionary = gens[gix["ref"][ni][0]]
				var need: float = (FRONT - 10.0) if g["id"] == 0 else (FRONT_BRANCH - 6.0)
				if Vector2(q.x, q.z).distance_to(gix["pts"][ni]) - float(gix["hw"][ni]) < need:
					return false
	return true


## Block annehmen: in die Liste und ins Raster der Zellen (pad: halbe Straße ringsum, beim Hof nur 1 m)
static func _accept(P: Dictionary, b: Dictionary, pad := STREET * 0.5) -> void:
	P["blocks"].append(b)
	var ctr: Vector3 = b["c"]
	var foot := [Vector2(ctr.x, ctr.z), Vector2(b["x"].x, b["x"].z), Vector2(b["z"].x, b["z"].z), b["hd"] + pad,
		b["hl"] + pad]
	var key := Vector2i(floori(ctr.x / 80.0), floori(ctr.z / 80.0))
	if not P["bgrid"].has(key):
		P["bgrid"][key] = []
	P["bgrid"][key].append(foot)


## Überlappt die Zelle (Block mit halber Straße) einen schon angenommenen Block mehr als eine halbe Straße?
static func _overlaps(P: Dictionary, ctr: Vector3, x: Vector3, z: Vector3, ex: float, ez: float) -> bool:
	var foot := [Vector2(ctr.x, ctr.z), Vector2(x.x, x.z), Vector2(z.x, z.z), ex, ez]
	var key := Vector2i(floori(ctr.x / 80.0), floori(ctr.z / 80.0))
	for gx in range(key.x - 2, key.x + 3):
		for gz in range(key.y - 2, key.y + 3):
			for o in P["bgrid"].get(Vector2i(gx, gz), []):
				if Track._foot_pen(foot, o) > STREET * 0.5 + 1.0:
					return true
	return false


## Ecken, Kantenmitten und Mitte der Zelle: Abstand zu Wegen (margin zur Wegkante), Sperrflächen, Wasser, Bahn,
## Hügeln, Parks, Wahrzeichen
static func _area_ok(track: Dictionary, P: Dictionary, ctr: Vector3, x: Vector3, z: Vector3, ex: float, ez: float,
		margin := 5.0) -> bool:
	var rad := Vector2(ex, ez).length()
	var pts: Array = [ctr]
	for su in [-1.0, 0.0, 1.0]:
		for sv in [-1.0, 0.0, 1.0]:
			if su != 0.0 or sv != 0.0:
				pts.append(ctr + x * su * ex + z * sv * ez)
	# lange Zellen: noch Punkte dazwischen
	if ez > 45.0:
		for su in [-1.0, 1.0]:
			for sv in [-0.5, 0.5]:
				pts.append(ctr + x * su * ex + z * sv * ez)
	# erst für die ganze Zelle (ein Kreis um die Mitte), nur wenn der nicht frei ist, genau gegen das Rechteck
	var c2 := Vector2(ctr.x, ctr.z)
	var foot := [c2, Vector2(x.x, x.z), Vector2(z.x, z.z), ex, ez]
	if _edge_dist(P["ix"], c2, rad + margin + 1.0) < rad + margin and _paths_hit(P["ix"], foot, rad, margin):
		_no("f_weg")
		return false
	if not _ko_disc_free(P, c2, rad) and _ko_hit(P, foot, rad):
		_no("f_sperr")
		return false
	if not track["rivers"].is_empty() and Track._river_near(track, ctr, rad + 8.0) < rad + 8.0:
		for q in pts:
			if Track._river_near(track, q, 8.0) < 7.0:
				_no("f_fluss")
				return false
	for q in pts:
		if Track._in_lake(track, q, 8.0) or _in_hole(P, Vector2(q.x, q.z), 6.0):
			_no("f_loch")
			return false
	if track["crossing_d"] >= 0.0 and Track._rail_clearance(track, ctr) < rad + 10.0:
		for q in pts:
			if Track._rail_clearance(track, q) < 9.0:
				return false
	if not track["hills"].is_empty():
		for q in pts:
			if Track.hill_h(track, q) > 0.3:
				return false
	# entworfene Städte: Hang mit Weinbergen und Wald (Stuttgart, Nürnberg, Heidelberg) freihalten
	if track.has("terrain_lay") and (track["terrain_lay"] as Dictionary).has("hill"):
		var hr: Array = track["terrain_lay"]["hill"]
		for q in pts:
			if q.x > hr[0] - 25.0 and q.x < hr[2] + 25.0 and q.z > hr[1] - 25.0 and q.z < hr[3] + 25.0:
				return false
	if track.has("terrain"):
		for q in pts:
			if Design.terrain_h(track, q) > 0.4:
				return false
	for tri in track["parks"]:
		for q in pts:
			if Geometry2D.point_is_inside_triangle(Vector2(q.x, q.z), Vector2(tri[0].x, tri[0].z), Vector2(tri[1].x, tri[1].z),
					Vector2(tri[2].x, tri[2].z)):
				return false
	# Wahrzeichen und Bauwerke (nur beim Bauen bekannt): die Zelle darf sie nicht nennenswert überdecken
	if not P["occ"].is_empty():
		if _occ_pen(P["occ"], foot, rad) > 2.5:
			_no("f_wahrz")
			return false
	return true


# --- Abstandsabfragen -------------------------------------------------------------------------------------------------

## Wegpunkte der Wege paths alle 4 m mit halber Breite (bis zur Randwand) in einem Raster
static func _path_index(track: Dictionary, paths: Array) -> Dictionary:
	var cells := {}
	var pts := PackedVector2Array()
	var hws := PackedFloat32Array()
	var tans := PackedVector2Array()
	var refs := []  # [Index in paths, Stelle d]
	var hmax := 0.0
	for pi in paths.size():
		var p: Dictionary = paths[pi]
		var c: Curve3D = p["curve"]
		var L := c.get_baked_length()
		var n := maxi(int(L / 4.0), 1)
		var main: bool = p["id"] == 0
		for k in n + 1:
			var d := L * k / n
			var q := c.sample_baked(d)
			var q2 := c.sample_baked(minf(d + 2.0, L)) - c.sample_baked(maxf(d - 2.0, 0.0))
			# bis zur Randwand: Hauptstraße mit Gehweg, Gabelung mit Bankett, sonst die Fahrbahn; Straßen des Straßennetzes
			# (street_net.gd) mit Gehweg und Parkbucht bzw. Grünstreifen bis zur Hauskante
			var hw: float = (Track.hw(track, d) + Track.WALK) if main else float(p["half_w"]) + (3.0 if p["kind"] == "fork" else 0.0)
			if not main and p.has("walk"):
				var sp: Array = p.get("strip", [0.0, 0.0])
				hw += float(p["walk"]) + maxf(float(sp[0]), float(sp[1]))
			pts.append(Vector2(q.x, q.z))
			hws.append(hw)
			tans.append(Vector2(q2.x, q2.z).normalized())
			refs.append([pi, d])
			hmax = maxf(hmax, hw)
			var key := Vector2i(floori(q.x / IX_CELL), floori(q.z / IX_CELL))
			if not cells.has(key):
				cells[key] = []
			cells[key].append(pts.size() - 1)
	return {"cells": cells, "pts": pts, "hw": hws, "hmax": hmax, "tan": tans, "ref": refs}


## Nächster Wegpunkt zu p (bis limit): Index oder -1
static func _nearest(ix: Dictionary, p: Vector2, limit: float) -> int:
	var reach := int(ceil((limit + float(ix["hmax"])) / IX_CELL))
	var key := Vector2i(floori(p.x / IX_CELL), floori(p.y / IX_CELL))
	var best := limit
	var bi := -1
	var pts: PackedVector2Array = ix["pts"]
	var hws: PackedFloat32Array = ix["hw"]
	var cells: Dictionary = ix["cells"]
	for r in reach + 1:
		# Ring für Ring nach außen; fertig, wenn der Ring weiter weg liegt als der beste Treffer
		if bi >= 0 and (r - 1) * IX_CELL > best + float(ix["hmax"]):
			break
		for gx in range(key.x - r, key.x + r + 1):
			for gz in range(key.y - r, key.y + r + 1):
				if maxi(absi(gx - key.x), absi(gz - key.y)) != r:
					continue
				var arr = cells.get(Vector2i(gx, gz))
				if arr == null:
					continue
				for i in arr:
					var d := p.distance_to(pts[i]) - hws[i]
					if d < best:
						best = d
						bi = i
	return bi


## Abstand von p zur nächsten Wegkante, genau bis limit (darüber kommt limit zurück)
static func _edge_dist(ix: Dictionary, p: Vector2, limit: float) -> float:
	var reach := int(ceil((maxf(limit, 0.0) + float(ix["hmax"]) + 3.0) / IX_CELL))
	var key := Vector2i(floori(p.x / IX_CELL), floori(p.y / IX_CELL))
	var best := limit
	var pts: PackedVector2Array = ix["pts"]
	var hws: PackedFloat32Array = ix["hw"]
	var cells: Dictionary = ix["cells"]
	for gx in range(key.x - reach, key.x + reach + 1):
		for gz in range(key.y - reach, key.y + reach + 1):
			var arr = cells.get(Vector2i(gx, gz))
			if arr == null:
				continue
			for i in arr:
				var d := p.distance_to(pts[i]) - hws[i] - 1.0  # Abtastung alle 4 m: bis 1 m zu weit
				if d < best:
					best = d
					if best < limit - 50.0:
						return best
	return best


## Sperrflächen (fremde Fahrbahnen) im Raster; Art "w" (world_layout._add_keepout): ring, city, ramp, ix ...
static func _ko_index(track: Dictionary) -> Dictionary:
	var cells := {}
	var rmax := 0.0
	for ko in track["keepout"]:
		var p: Vector3 = ko["pos"]
		var key := Vector2i(floori(p.x / IX_CELL), floori(p.z / IX_CELL))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(ko)
		rmax = maxf(rmax, float(ko["r"]))
	return {"cells": cells, "rmax": rmax}


## Blockmitte: zu fremden Stadtstraßen und Ringen höchstens bis zur Mitte (mit VORONOI Vorsprung für die eigene
## Straße, own = Abstand zur Mitte der eigenen Straße), zu Ringen RING_CLEAR
static func _ko_center_ok(P: Dictionary, p: Vector2, own: float) -> bool:
	var ko: Dictionary = P["ko"]
	var lim := own + VORONOI
	var reach := int(ceil(maxf(lim, RING_CLEAR) / IX_CELL)) + 1
	var key := Vector2i(floori(p.x / IX_CELL), floori(p.y / IX_CELL))
	var cells: Dictionary = ko["cells"]
	for gx in range(key.x - reach, key.x + reach + 1):
		for gz in range(key.y - reach, key.y + reach + 1):
			var arr = cells.get(Vector2i(gx, gz))
			if arr == null:
				continue
			for o in arr:
				var w: String = o.get("w", "")
				if w == "" or w == "ramp" or w == "ix":
					continue  # nur Abstand (an den Ecken), keine Mitte
				var d := p.distance_to(Vector2(o["pos"].x, o["pos"].z))
				if d < lim or (w == "ring" and d < RING_CLEAR):
					return false
	return true


## Abstand des Punkts q vom Rechteck foot [Mitte, Achse x, Achse z, halbe Länge x, halbe Länge z] (innen negativ)
static func _rect_dist(foot: Array, q: Vector2) -> float:
	var rel: Vector2 = q - foot[0]
	var du := absf(rel.dot(foot[1])) - float(foot[3])
	var dv := absf(rel.dot(foot[2])) - float(foot[4])
	if du < 0.0 and dv < 0.0:
		return maxf(du, dv)
	return Vector2(maxf(du, 0.0), maxf(dv, 0.0)).length()


## Kommt ein Weg (Wegpunkte mit halber Breite) dem Rechteck foot (Umkreis rad) näher als margin?
static func _paths_hit(ix: Dictionary, foot: Array, rad: float, margin: float) -> bool:
	var c2: Vector2 = foot[0]
	var reach := int(ceil((rad + margin + float(ix["hmax"]) + 3.0) / IX_CELL))
	var key := Vector2i(floori(c2.x / IX_CELL), floori(c2.y / IX_CELL))
	var pts: PackedVector2Array = ix["pts"]
	var hws: PackedFloat32Array = ix["hw"]
	var cells: Dictionary = ix["cells"]
	for gx in range(key.x - reach, key.x + reach + 1):
		for gz in range(key.y - reach, key.y + reach + 1):
			var arr = cells.get(Vector2i(gx, gz))
			if arr == null:
				continue
			for i in arr:
				if _rect_dist(foot, pts[i]) - hws[i] - 2.0 < margin:  # Abtastung alle 4 m: bis 2 m dazwischen
					return true
	return false


## Kommt eine Sperrfläche dem Rechteck foot näher als ihr Radius plus 10 m (Ringe: RING_CLEAR zur Mitte)?
static func _ko_hit(P: Dictionary, foot: Array, rad: float) -> bool:
	var ko: Dictionary = P["ko"]
	var c2: Vector2 = foot[0]
	var reach := int(ceil((rad + maxf(float(ko["rmax"]) + 12.0, RING_CLEAR)) / IX_CELL))
	var key := Vector2i(floori(c2.x / IX_CELL), floori(c2.y / IX_CELL))
	var cells: Dictionary = ko["cells"]
	for gx in range(key.x - reach, key.x + reach + 1):
		for gz in range(key.y - reach, key.y + reach + 1):
			var arr = cells.get(Vector2i(gx, gz))
			if arr == null:
				continue
			for o in arr:
				var d := _rect_dist(foot, Vector2(o["pos"].x, o["pos"].z))
				if d < float(o["r"]) + 10.0 or (o.get("w", "") == "ring" and d < RING_CLEAR):
					return true
	return false


## Kreis um p (Radius rad): hält jeder Punkt darin den Abstand von _ko_point_ok zu allen Sperrflächen ein?
static func _ko_disc_free(P: Dictionary, p: Vector2, rad: float) -> bool:
	var ko: Dictionary = P["ko"]
	var reach := int(ceil((rad + maxf(float(ko["rmax"]) + 12.0, RING_CLEAR)) / IX_CELL))
	var key := Vector2i(floori(p.x / IX_CELL), floori(p.y / IX_CELL))
	var cells: Dictionary = ko["cells"]
	for gx in range(key.x - reach, key.x + reach + 1):
		for gz in range(key.y - reach, key.y + reach + 1):
			var arr = cells.get(Vector2i(gx, gz))
			if arr == null:
				continue
			for o in arr:
				var d := p.distance_to(Vector2(o["pos"].x, o["pos"].z)) - rad
				if d < float(o["r"]) + 10.0 or (o.get("w", "") == "ring" and d < RING_CLEAR):
					return false
	return true


## Ecke einer Zelle: Abstand zu jeder Sperrfläche (Ringe: RING_CLEAR zur Mitte)
static func _ko_point_ok(P: Dictionary, p: Vector2) -> bool:
	var ko: Dictionary = P["ko"]
	var reach := int(ceil(maxf(float(ko["rmax"]) + 12.0, RING_CLEAR) / IX_CELL))
	var key := Vector2i(floori(p.x / IX_CELL), floori(p.y / IX_CELL))
	var cells: Dictionary = ko["cells"]
	for gx in range(key.x - reach, key.x + reach + 1):
		for gz in range(key.y - reach, key.y + reach + 1):
			var arr = cells.get(Vector2i(gx, gz))
			if arr == null:
				continue
			for o in arr:
				var d := p.distance_to(Vector2(o["pos"].x, o["pos"].z))
				if d < float(o["r"]) + 10.0 or (o.get("w", "") == "ring" and d < RING_CLEAR):
					return false
	return true


## Löcher im Boden der Nachbarn (Flussbetten, Tröge) in Streckenkoordinaten, nur in der Nähe der Strecke, im Raster:
## Zelle -> [Vector3(x, z, Radius)] (alle Städte zusammen sind einige Tausend)
static func _holes_local(track: Dictionary) -> Dictionary:
	var cells := {}
	var wh: PackedVector3Array = track.get("world_holes", PackedVector3Array())
	if wh.is_empty():
		return {"cells": cells, "rmax": 0.0}
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for p in track["paths"]:
		for q in (p["curve"] as Curve3D).get_baked_points():
			lo = lo.min(Vector2(q.x, q.z))
			hi = hi.max(Vector2(q.x, q.z))
	lo -= Vector2(500.0, 500.0)
	hi += Vector2(500.0, 500.0)
	var inv: Transform3D = (track["xf"] as Transform3D).affine_inverse()
	var rmax := 0.0
	for h in wh:
		var q: Vector3 = inv * Vector3(h.x, 0.0, h.y)
		if q.x < lo.x or q.z < lo.y or q.x > hi.x or q.z > hi.y:
			continue
		var key := Vector2i(floori(q.x / IX_CELL), floori(q.z / IX_CELL))
		if not cells.has(key):
			cells[key] = []
		cells[key].append(Vector3(q.x, q.z, h.z))
		rmax = maxf(rmax, h.z)
	return {"cells": cells, "rmax": rmax}


static func _in_hole(P: Dictionary, p: Vector2, margin: float) -> bool:
	var H: Dictionary = P["holes"]
	var cells: Dictionary = H["cells"]
	if cells.is_empty():
		return false
	var reach := int(ceil((float(H["rmax"]) + margin) / IX_CELL))
	var key := Vector2i(floori(p.x / IX_CELL), floori(p.y / IX_CELL))
	for gx in range(key.x - reach, key.x + reach + 1):
		for gz in range(key.y - reach, key.y + reach + 1):
			for h in cells.get(Vector2i(gx, gz), []):
				if p.distance_to(Vector2(h.x, h.y)) < h.z + margin:
					return true
	return false


## Raster der Wahrzeichen, Bauwerke und vorhandenen Häuser (ohne Sperrflächen), wie track_builder._grid_add
static func _occ_grid(items: Array) -> Dictionary:
	var g := {}
	for o in items:
		if o.has("ko"):
			continue
		Track._grid_add(g, o.duplicate())
	return g


## Wie weit überdeckt das Rechteck foot (Radius rad) Einträge des Rasters? (größte Eindringtiefe)
static func _occ_pen(grid: Dictionary, foot: Array, rad: float) -> float:
	if grid.is_empty():
		return 0.0
	var c2: Vector2 = foot[0]
	var key := Vector2i(floori(c2.x / Track.LOT_CELL), floori(c2.y / Track.LOT_CELL))
	var best := 0.0
	var reach := int(ceil((rad + float(grid["fmax"])) / Track.LOT_CELL))
	var cells: Dictionary = grid["feet"]
	for gx in range(key.x - reach, key.x + reach + 1):
		for gz in range(key.y - reach, key.y + reach + 1):
			for o in cells.get(Vector2i(gx, gz), []):
				if c2.distance_to(o["foot"][0]) < rad + o["fr"]:
					best = maxf(best, Track._foot_pen(foot, o["foot"]))
	reach = int(ceil((rad + float(grid["cmax"])) / Track.LOT_CELL))
	cells = grid["circ"]
	for gx in range(key.x - reach, key.x + reach + 1):
		for gz in range(key.y - reach, key.y + reach + 1):
			for o in cells.get(Vector2i(gx, gz), []):
				# Kreis gegen Rechteck: Abstand der Mitte zum Rechteck
				var rel: Vector2 = Vector2(o["pos"].x, o["pos"].z) - c2
				var lu := absf(rel.dot(foot[1])) - float(foot[3])
				var lv := absf(rel.dot(foot[2])) - float(foot[4])
				var dd := Vector2(maxf(lu, 0.0), maxf(lv, 0.0)).length()
				if lu < 0.0 and lv < 0.0:
					dd = maxf(lu, lv)
				best = maxf(best, float(o["r"]) - dd)
	return best


# --- Nutzungen verteilen ----------------------------------------------------------------------------------------------

static func _assign(track: Dictionary, P: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(P["seed"]) * 31 + 977
	var placed := {}  # Nutzung -> [Lagen]
	for b in P["blocks"]:
		if b["use"] != "":
			continue  # Hof (Lücke zwischen den Häusern): schon festgelegt
		var st: Dictionary = STYLE[b["dk"]]
		var uses: Dictionary = st["use"][mini(int(b["zone"]), (st["use"] as Array).size() - 1)]
		var pick := ""
		for attempt in 4:
			var u := _wpick(uses, rng)
			if RARE.has(u):
				var rr: Array = RARE[u]
				if b["hd"] < rr[1] or b["hl"] < rr[2]:
					continue
				var near := false
				for q in placed.get(u, []):
					if (q as Vector3).distance_to(b["c"]) < rr[0]:
						near = true
						break
				if near:
					continue
			pick = u
			break
		if pick == "":
			pick = "rand" if int(b["zone"]) < 2 else "efh"
			if b["dk"] == "industrial":
				pick = "halle"
			elif b["dk"] == "residential" and int(b["zone"]) == 0:
				pick = "altstadt"
		b["use"] = pick
		if not placed.has(pick):
			placed[pick] = []
		placed[pick].append(b["c"])


static func _wpick(w: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in w:
		total += float(w[k])
	var r := rng.randf() * total
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			return k
	return w.keys()[0]


# --- Bauen ------------------------------------------------------------------------------------------------------------

## Bau in Schritten (track_builder Schritt 4). Erst Planung, dann Block für Block, am Ende Meshes und MultiMeshes.
## true = fertig. Zeitbudget: im Bau-Thread am Stück, im Browser wenige Millisekunden je Bild, im Rennen größer.
static func step(root: Node3D, track: Dictionary, job: Dictionary) -> bool:
	var budget := -1
	if OS.get_thread_caller_id() == OS.get_main_thread_id():
		budget = 6 if track["world"] else 40
	var t0 := Time.get_ticks_msec()
	if not job.has("fill"):
		var race: Dictionary = job["race"]
		var P := plan_begin(track, int(race.get("seed", 0)), false)
		# Blöcke meiden Wahrzeichen, Bauwerke und Hochbahn; einzelne Häuser und Bäume auch die Häuser der Front
		var occ: Array = job["occupied"].duplicate()
		for eb in track.get("el_blocks", []):
			occ.append({"pos": Vector3(eb[0].x, 0.0, eb[0].y), "r": 0.0, "foot": eb})
		P["occ"] = _occ_grid(occ)
		P["houses"] = _occ_grid(occ + job["buildings"])
		job["fill"] = {"P": P, "bi": 0, "done": false, "cells": {}, "feet": [], "people": [], "grid": P["houses"], "own": {},
			"dens": _density()}
	var F: Dictionary = job["fill"]
	var P2: Dictionary = F["P"]
	if not P2.has("used"):
		if not plan_step(track, P2, maxi(budget - (Time.get_ticks_msec() - t0), 1) if budget >= 0 else -1):
			return false
	var blocks: Array = P2["blocks"]
	Track._box_tag = "fuellung"
	while F["bi"] < blocks.size():
		_build_block(track, F, blocks[F["bi"]], int(F["bi"]))
		F["bi"] += 1
		if budget >= 0 and Time.get_ticks_msec() - t0 >= budget:
			Track._box_tag = ""
			return false
	Track._box_tag = ""
	if not _flush(root, track, F, t0, budget):
		return false
	job["buildings"].append_array(F["feet"])
	job["fill_blocks"] = blocks  # für Prüfwerkzeuge (Draufsicht)
	job.erase("fill")
	return true


## Fortschritt für den Ladebalken (0..1)
static func progress(job: Dictionary) -> float:
	if not job.has("fill"):
		return 0.0
	var F: Dictionary = job["fill"]
	var P: Dictionary = F["P"]
	var pp := float(P["ti"]) / maxf(float((P["tasks"] as Array).size()), 1.0)
	var bp := float(F["bi"]) / maxf(float((P["blocks"] as Array).size()), 1.0)
	var fp := float(F.get("ki", 0)) / maxf(float((F["cells"] as Dictionary).size()), 1.0)
	return pp * 0.3 + bp * 0.6 + fp * 0.1


## Dichte von Bäumen, Autos und Leuten nach Detailstufe (Browser höchstens mittel)
static func _density() -> float:
	var lvl := clampi(int(GameState.gfx.get("detail", 2)), 0, 3)
	var d: float = [0.45, 0.65, 0.85, 1.0][lvl]
	if OS.has_feature("web"):
		d = minf(d, 0.55)
	return d


## Ein Block: halbe Straße ringsum (Gehweg, Fahrbahn, parkende Autos, Bäume, Laternen), dann die Nutzung
static func _build_block(track: Dictionary, F: Dictionary, b: Dictionary, bi: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(F["P"]["seed"]) * 1009 + bi * 7907 + 3
	var use: String = b["use"]
	var green: bool = use in ["park", "garten", "sport", "brache"]
	if dbg:
		_wk = "rahmen"
	if use != "hof":
		_frame(track, F, b, rng, green)
	if dbg:
		_wk = use
		why["nutzung_" + use] = why.get("nutzung_" + use, 0) + 1
	match use:
		"rand":
			_rand(F, b, rng, false)
		"altstadt":
			_rand(F, b, rng, true)
		"buero":
			_buero(F, b, rng)
		"turm":
			_turm(F, b, rng)
		"zeilen":
			_zeilen(F, b, rng)
		"reihen":
			_reihen(F, b, rng)
		"efh":
			_efh(F, b, rng, false)
		"villen":
			_efh(F, b, rng, true)
		"park":
			_park(F, b, rng)
		"platz":
			_platz(F, b, rng)
		"parken":
			_parken(F, b, rng)
		"schule":
			_schule(F, b, rng)
		"kirche":
			_kirche(F, b, rng)
		"sport":
			_sport(F, b, rng)
		"garten":
			_garten(F, b, rng)
		"halle":
			_halle(F, b, rng, false)
		"lager":
			_halle(F, b, rng, true)
		"container":
			_container(F, b, rng)
		"brache":
			_brache(F, b, rng)
		"hof":
			_hof(F, b, rng)


# --- Bausteine --------------------------------------------------------------------------------------------------------

## Punkt im Block (u quer von der Straße weg, v entlang)
static func _lp(b: Dictionary, u: float, v: float) -> Vector3:
	return b["c"] + b["x"] * u + b["z"] * v


## Zelle (Batch) zu einem Punkt: {"flat": Boden, "solid": kleine Körper und Laternenmasten, "trees", "cars", "lamps"}
static func _cell(F: Dictionary, p: Vector3) -> Dictionary:
	var key := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
	var cells: Dictionary = F["cells"]
	if not cells.has(key):
		# Böden und kleine Körper in einem Mesh (ein Draw Call je Zelle)
		var geo := Geo.new()
		cells[key] = {"flat": geo, "solid": geo, "trees": [], "tcol": [], "cars": [], "ccol": [], "lamps": []}
	return cells[key]


## Fläche (Rechteck im Block, u0..u1 quer, v0..v1 entlang) auf Höhe y
static func _rect(F: Dictionary, b: Dictionary, u0: float, u1: float, v0: float, v1: float, y: float, col: Color) -> void:
	var a := _lp(b, u0, v0)
	var c := _lp(b, u1, v1)
	(_cell(F, (a + c) * 0.5)["flat"] as Geo).quad(a + Vector3(0, y, 0), _lp(b, u1, v0) + Vector3(0, y, 0), c + Vector3(0, y, 0),
		_lp(b, u0, v1) + Vector3(0, y, 0), col)


## Flaches Rechteck um Mitte p mit Achse ax (halbe Längen ha entlang ax, hb quer)
static func _flat_obb(F: Dictionary, p: Vector3, ax: Vector3, ha: float, hb: float, y: float, col: Color) -> void:
	var bx := ax.cross(Vector3.UP)
	var o := Vector3(p.x, y, p.z)
	(_cell(F, p)["flat"] as Geo).quad(o - ax * ha - bx * hb, o + ax * ha - bx * hb, o + ax * ha + bx * hb, o - ax * ha + bx * hb, col)


## Körper (Quader ohne Boden) mit Vertexfarbe: Mitte unten p, Achse ax, Maße (entlang ax, Höhe, quer)
static func _solid(F: Dictionary, p: Vector3, ax: Vector3, size: Vector3, col: Color, y0 := 0.0) -> void:
	(_cell(F, p)["solid"] as Geo).box(Vector3(p.x, y0, p.z), ax, size, col)


static func _tree(F: Dictionary, p: Vector3, rng: RandomNumberGenerator, s := 1.0) -> void:
	if rng.randf() > minf(F["dens"] * 1.2, 1.0):
		if dbg:
			why["baum_dichte"] = why.get("baum_dichte", 0) + 1
		return
	if _hit(F, p, 1.2):
		if dbg:
			why["baum_haus"] = why.get("baum_haus", 0) + 1
		return
	if dbg:
		why["baum_ok_" + _wk] = why.get("baum_ok_" + _wk, 0) + 1
	var cl := _cell(F, p)
	var k := s * rng.randf_range(0.75, 1.2)
	cl["trees"].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(k, k * rng.randf_range(0.9, 1.15), k)),
		Vector3(p.x, 0.0, p.z)))
	var g := rng.randf_range(0.8, 1.15)
	cl["tcol"].append(Color(0.17 * g, 0.31 * g, 0.1 * g) if rng.randf() < 0.8 else Color(0.32 * g, 0.3 * g, 0.12 * g))


## Parkendes Auto: Lage p, Blick entlang ax
static func _car(F: Dictionary, p: Vector3, ax: Vector3, rng: RandomNumberGenerator, van_p := 0.12) -> void:
	if rng.randf() > F["dens"]:
		return
	var cl := _cell(F, p)
	var b := Basis.looking_at(ax, Vector3.UP)
	if rng.randf() < 0.5:
		b = b.rotated(Vector3.UP, PI)
	var col: Color = Traffic.COLORS[rng.randi() % Traffic.COLORS.size()]
	if rng.randf() < 0.05:
		col = Color(0.95, 0.75, 0.05)  # Taxi
	if rng.randf() < van_p:
		# Transporter: dasselbe Modell höher und länger (ein MultiMesh je Zelle für alle Autos)
		b = b * Basis.from_scale(Vector3(1.1, 1.75, 1.15))
		if rng.randf() < 0.6:
			col = Color(0.85, 0.85, 0.85)
	cl["cars"].append(Transform3D(b, Vector3(p.x, 0.0, p.z)))
	cl["ccol"].append(col)


## Laterne: Mast und Ausleger in den kleinen Körpern der Zelle, die Leuchte (leuchtet nachts) als MultiMesh
static func _lamp(F: Dictionary, p: Vector3, face: Vector3) -> void:
	if _hit(F, p, 0.6):
		return
	var cl := _cell(F, p)
	var g: Geo = cl["solid"]
	g.box(Vector3(p.x, 0.0, p.z), face, Vector3(0.14, 7.0, 0.14), Color(0.22, 0.23, 0.24))
	g.box(Vector3(p.x, 6.9, p.z) + face * 0.7, face, Vector3(1.4, 0.1, 0.1), Color(0.22, 0.23, 0.24))
	cl["lamps"].append(Transform3D(Basis.looking_at(face, Vector3.UP), Vector3(p.x, 0.0, p.z) + face * 1.3))


## Steht an p (Radius r) schon ein Haus der Front oder ein Wahrzeichen?
static func _hit(F: Dictionary, p: Vector3, r: float) -> bool:
	var foot := [Vector2(p.x, p.z), Vector2(1, 0), Vector2(0, 1), r, r]
	return _occ_pen(F["grid"], foot, r * 1.42) > 0.05


## Haus im Häuser-Batch der Strecke: Mitte ctr (Boden), Achse a (Tiefe d entlang a, Breite w quer), Höhe h.
## look: Stil, Farbe, Licht, Dach (siehe _look). Gibt false zurück, wenn dort schon etwas steht: ein Haus der Front,
## ein Wahrzeichen oder ein Haus der Füllung (F["own"]; Nachbarblöcke greifen in Kurven ineinander). Sich berühren
## dürfen sie (Blockrand), ineinander ragen nicht.
static func _house(F: Dictionary, ctr: Vector3, a: Vector3, d: float, w: float, h: float, look: Dictionary, roof := false,
		gable := false) -> bool:
	var bz := a.cross(Vector3.UP)
	var foot := [Vector2(ctr.x, ctr.z), Vector2(a.x, a.z), Vector2(bz.x, bz.z), d * 0.5, w * 0.5]
	var rad := Vector2(d, w).length() * 0.5
	if _occ_pen(F["grid"], foot, rad) > 0.4 or _occ_pen(F["own"], foot, rad) > 0.25:
		return false
	Track._grid_add(F["own"], {"pos": ctr, "foot": foot})
	var basis := Basis(a, Vector3.UP, bz)
	Track._box_id += 1
	var tint: Vector3 = look["tint"] * F["rngv"].randf_range(0.9, 1.1) if F.has("rngv") else look["tint"]
	Track._bb_box(Transform3D(basis * Basis.from_scale(Vector3(d, h, w)), ctr + Vector3(0, h * 0.5, 0)), tint, look["lit"],
		look["seed"] + F["feet"].size() * 0.37, look["style"], look.get("glass", 0.0))
	if roof:
		Track._bb_roof(ctr, basis, w, d, h, gable, look["roof"], tint, look["style"], look["seed"], look["lit"])
	F["feet"].append({"pos": ctr, "r": Vector2(d, w).length() * 0.4, "foot": foot})
	return true


## Fassade, Farbe und Dach eines Hauses aus dem Viertel (track_builder.DISTRICTS)
static func _look(dk: String, rng: RandomNumberGenerator, style := -1.0) -> Dictionary:
	var dist: Dictionary = Track.DISTRICTS[dk]
	var styles: Array = dist["styles"]
	var tints: Array = dist["tints"]
	var tint: Color = tints[rng.randi() % tints.size()]
	var v := rng.randf_range(0.8, 1.2)
	var rt: Array = dist.get("roof_tints", [Color(0.3, 0.13, 0.09)])
	var rc: Color = rt[rng.randi() % rt.size()]
	var rk := rng.randf_range(0.85, 1.15)
	return {"style": style if style >= 0.0 else float(styles[rng.randi() % styles.size()]),
		"tint": Vector3(tint.r * v, tint.g * v, tint.b * v), "lit": float(dist["lit"]) * rng.randf_range(0.7, 1.3),
		"seed": rng.randf() * 100.0, "roof": Vector3(rc.r * rk, rc.g * rk, rc.b * rk)}


static func _floors(h: float) -> float:
	return maxf(roundf((h - 1.0) / FLOOR), 2.0) * FLOOR + 1.0


## Halbe Straße um den Block: Gehweg (2 m) am Block, Fahrbahn bis zur Zellgrenze, parkende Autos am Bordstein,
## Straßenbäume und Laternen auf dem Gehweg. Seiten, die an Wege oder Sperrflächen stoßen, bleiben frei.
static func _frame(track: Dictionary, F: Dictionary, b: Dictionary, rng: RandomNumberGenerator, green: bool) -> void:
	var hd: float = b["hd"]
	var hl: float = b["hl"]
	var hs := STREET * 0.5
	var P: Dictionary = F["P"]
	var trees: bool = rng.randf() < {"boulevard": 0.85, "residential": 0.55, "shops": 0.45, "downtown": 0.4}.get(b["dk"], 0.25)
	var park_p: float = {"industrial": 0.35, "highway": 0.4, "downtown": 0.6}.get(b["dk"], 0.55)
	# vier Seiten: [Mitte (u, v), Richtung entlang, halbe Blocklänge, nach außen]. Längsseiten: Gehweg bis über die
	# Ecke, Fahrbahn bis zur Zellgrenze; Stirnseiten: Gehweg am Block, Fahrbahn bis an den Gehweg der Längsseite
	var sides := [[Vector2(-hd, 0.0), "z", hl, -1.0, "x"], [Vector2(hd, 0.0), "z", hl, 1.0, "x"],
		[Vector2(0.0, -hl), "x", hd, -1.0, "z"], [Vector2(0.0, hl), "x", hd, 1.0, "z"]]
	for sd in sides:
		var m: Vector2 = sd[0]
		var along: Vector3 = b[sd[1]]
		var outw: Vector3 = b[sd[4]] * float(sd[3])
		var half: float = sd[2]
		var long_side: bool = sd[4] == "x"
		var base := _lp(b, m.x, m.y)
		# Seite frei? Mitte und Enden der Fahrbahn prüfen
		var ok := true
		for t in [-1.0, 0.0, 1.0]:
			var q: Vector3 = base + outw * (hs - 1.0) + along * t * (half + hs)
			if _edge_dist(P["ix"], Vector2(q.x, q.z), 4.0) < 3.0 or not _ko_point_ok(P, Vector2(q.x, q.z)):
				ok = false
		if not ok:
			continue
		if green and int(b["zone"]) >= 2 and sd[3] > 0.0 and long_side:
			continue  # Stadtrand: Gärten und Sportplätze grenzen direkt ans Feld
		var walk_c := base + outw * (WALKW * 0.5)
		var road_c := base + outw * (WALKW + (hs - WALKW) * 0.5)
		_flat_obb(F, walk_c, along, half + (WALKW if long_side else 0.0), WALKW * 0.5, 0.1, C_WALK)
		_flat_obb(F, road_c, along, half + (hs if long_side else WALKW), (hs - WALKW) * 0.5, 0.04, C_ASPHALT)
		# parkende Autos (längs, 1,1 m vom Bordstein), Bäume und Laternen auf dem Gehweg
		var t := -half + rng.randf_range(1.0, 5.0)
		while t < half - 3.0:
			if rng.randf() < park_p:
				_car(F, base + outw * (WALKW + 1.15) + along * t, along, rng)
			t += rng.randf_range(5.6, 6.6)
		if trees:
			t = -half + rng.randf_range(4.0, 8.0)
			while t < half - 3.0:
				_tree(F, base + outw * 0.9 + along * t, rng, 0.75)
				t += rng.randf_range(9.0, 12.0)
		if long_side or half > 30.0:
			t = -half + rng.randf_range(6.0, 20.0)
			while t < half - 4.0:
				_lamp(F, base + outw * (WALKW - 0.35) + along * t, outw)
				t += rng.randf_range(32.0, 40.0)


## Blockrand (Mietshäuser, Büros) oder Altstadt (schmale Häuser mit steilen Dächern, Giebel zur Straße): Häuser rund
## um den Block, innen ein Hof (Rasen mit Bäumen oder gepflastert mit Autos)
static func _rand(F: Dictionary, b: Dictionary, rng: RandomNumberGenerator, alt: bool) -> void:
	var dk: String = b["dk"]
	var st: Dictionary = STYLE[dk]
	var hr: Array = st["h"][mini(int(b["zone"]), (st["h"] as Array).size() - 1)]
	var dist: Dictionary = Track.DISTRICTS[dk]
	var hd: float = b["hd"]
	var hl: float = b["hl"]
	var bd := rng.randf_range(10.0, 12.5) if alt else (rng.randf_range(13.0, 16.0) if dk == "downtown" else rng.randf_range(11.0, 13.5))
	bd = minf(bd, hd * 0.8)
	var seg: Array = [7.0, 11.0] if alt else ([16.0, 30.0] if dk == "downtown" else [10.0, 20.0])
	var roof_p: float = 0.95 if alt else float(dist.get("roof", 0.0))
	var gable_p: float = 0.6 if alt else float(dist.get("gable", 0.0)) * 0.5
	var glass_p := 0.0 if alt or int(b["zone"]) > 0 else 0.3 * float(dist.get("shop", 0.0))
	F["rngv"] = rng
	# Längsseiten (an den Straßen entlang v) über die ganze Länge, Stirnseiten dazwischen
	for su in [-1.0, 1.0]:
		var v := -hl
		while v < hl - 3.0:
			var w := minf(rng.randf_range(seg[0], seg[1]), hl - v)
			if hl - v - w < seg[0] * 0.6:
				w = hl - v
			var h := _floors(rng.randf_range(hr[0], hr[1]))
			if absf(v + w * 0.5) > hl - w and rng.randf() < 0.4:
				h += FLOOR  # Eckhaus etwas höher
			var lk := _look(dk, rng)
			lk["glass"] = 1.0 if rng.randf() < glass_p else 0.0
			# Altstadt: Straßenflucht etwas unregelmäßig (Haus weniger tief, die Hofseite bleibt, damit die Häuser der
			# Stirnseiten genau anstoßen statt hineinzuragen)
			var inset := rng.randf_range(0.0, 1.2) if alt else 0.0
			var ctr := _lp(b, su * (hd - (bd + inset) * 0.5), v + w * 0.5)
			var pitched := h < 26.0 and rng.randf() < roof_p
			if rng.randf() > 0.06:
				_house(F, ctr, b["x"], bd - inset, w - (0.0 if not alt else rng.randf_range(0.0, 0.3)), h, lk, pitched,
					pitched and rng.randf() < gable_p)
			v += w
	for sv in [-1.0, 1.0]:
		var u := -hd + bd
		var u_end := hd - bd
		while u < u_end - 3.0:
			var w := minf(rng.randf_range(seg[0], seg[1]), u_end - u)
			if u_end - u - w < seg[0] * 0.6:
				w = u_end - u
			var h := _floors(rng.randf_range(hr[0], hr[1]))
			var lk := _look(dk, rng)
			var pitched := h < 26.0 and rng.randf() < roof_p
			if rng.randf() > 0.15:
				_house(F, _lp(b, u + w * 0.5, sv * (hl - bd * 0.5)), b["z"], bd, w, h, lk, pitched, pitched and rng.randf() < gable_p)
			u += w
	# Hof
	var iu := hd - bd - 0.5
	var iv := hl - bd - 0.5
	if iu > 3.0 and iv > 3.0:
		if rng.randf() < 0.65 or alt:
			_rect(F, b, -iu, iu, -iv, iv, 0.05, C_LAWN if rng.randf() < 0.6 else C_LAWN2)
			for i in rng.randi_range(2, 3 + int(iu * iv / 70.0)):
				_tree(F, _lp(b, rng.randf_range(-iu + 2.0, iu - 2.0), rng.randf_range(-iv + 2.0, iv - 2.0)), rng, 0.9)
		else:
			_rect(F, b, -iu, iu, -iv, iv, 0.05, C_PAVE)
			var v := -iv + 3.0
			while v < iv - 3.0 and iu > 5.0:
				_car(F, _lp(b, -iu + 2.6, v), b["x"], rng, 0.08)
				v += 2.7
		# Hinterhaus oder Garagen im großen Hof
		if iu > 12.0 and iv > 18.0 and rng.randf() < 0.3:
			_house(F, _lp(b, 0.0, 0.0), b["x"], minf(iu, 9.0), minf(iv * 1.2, 26.0), _floors(rng.randf_range(6.0, 10.0)), _look(dk, rng))


## Bürohäuser: zwei, drei Riegel längs (Bandfenster, Glas), dazwischen ein Platz mit Bäumen
static func _buero(F: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> void:
	var dk: String = b["dk"]
	var st: Dictionary = STYLE[dk]
	var hr: Array = st["h"][mini(int(b["zone"]), (st["h"] as Array).size() - 1)]
	var hd: float = b["hd"]
	var hl: float = b["hl"]
	_rect(F, b, -hd, hd, -hl, hl, 0.05, C_PAVE)
	var bd := minf(rng.randf_range(14.0, 18.0), hd * 0.7)
	var n := 2 if hd < 30.0 else 3
	F["rngv"] = rng
	for i in n:
		var u := lerpf(-hd + bd * 0.5 + 1.5, hd - bd * 0.5 - 1.5, float(i) / maxf(n - 1, 1)) if n > 1 else 0.0
		if n == 3 and i == 1:
			continue  # Mitte frei: Platz
		var len := hl * 2.0 - rng.randf_range(4.0, 16.0)
		var lk := _look(dk, rng, [1.0, 3.0, 0.0][rng.randi() % 3])
		_house(F, _lp(b, u, rng.randf_range(-2.0, 2.0)), b["z"], len, bd, _floors(rng.randf_range(hr[0], hr[1] * 1.15)), lk)
	for i in rng.randi_range(4, 9):
		_tree(F, _lp(b, rng.randf_range(-6.0, 6.0), rng.randf_range(-hl + 4.0, hl - 4.0)), rng)


## Hochhaus auf einem Sockel, Platz davor
static func _turm(F: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> void:
	var dk: String = b["dk"]
	var hd: float = b["hd"]
	var hl: float = b["hl"]
	_rect(F, b, -hd, hd, -hl, hl, 0.05, C_PAVE)
	F["rngv"] = rng
	var pd := hd * 2.0 - 8.0
	var pw := hl * 2.0 - 10.0
	var base := _look(dk, rng, 0.0)
	if not _house(F, _lp(b, 0.0, 0.0), b["x"], pd, pw, _floors(rng.randf_range(6.0, 10.0)), base):
		return
	var n := 1 if hl < 45.0 else 2
	for i in n:
		var v := 0.0 if n == 1 else (-hl * 0.45 if i == 0 else hl * 0.45)
		var ts := minf(minf(rng.randf_range(20.0, 28.0), pd - 4.0), hl * (1.6 if n == 1 else 0.8))
		var th := rng.randf_range(55.0, 105.0) if dk == "downtown" else rng.randf_range(36.0, 60.0)
		var lk := _look(dk, rng, [3.0, 1.0, 3.0][rng.randi() % 3])
		var ctr := _lp(b, rng.randf_range(-2.0, 2.0), v)
		# Turm über dem Sockel, bis zum Boden (im Sockel nicht sichtbar): dasselbe Haus wie der Sockel (gleiche Haus-Nr.,
		# track_check zählt Sockel, Turm und Krone als ein Haus), Platz prüft der Sockel
		var basis := Basis(b["x"], Vector3.UP, b["z"])
		Track._bb_box(Transform3D(basis * Basis.from_scale(Vector3(ts, th, ts)), ctr + Vector3(0, th * 0.5, 0)), lk["tint"], lk["lit"],
			lk["seed"], lk["style"], 0.0)
		if rng.randf() < 0.45:
			var ch := rng.randf_range(5.0, 10.0)
			Track._bb_box(Transform3D(basis * Basis.from_scale(Vector3(ts * 0.55, ch, ts * 0.55)), ctr + Vector3(0, th + ch * 0.5, 0)),
				lk["tint"] * 1.1, lk["lit"], lk["seed"] + 2.0, lk["style"], 0.0, th)


## Zeilenbau: drei, vier Riegel quer zur Straße, Rasen dazwischen, Stellplätze an den Enden
static func _zeilen(F: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> void:
	var dk: String = b["dk"]
	var hd: float = b["hd"]
	var hl: float = b["hl"]
	_rect(F, b, -hd, hd, -hl, hl, 0.05, C_LAWN)
	F["rngv"] = rng
	var pitch := rng.randf_range(26.0, 32.0)
	var n := maxi(int((hl * 2.0 - 6.0) / pitch), 1)
	var lk := _look(dk, rng, [6.0, 4.0, 0.0][rng.randi() % 3])
	var roofed := rng.randf() < 0.5
	var h := _floors(rng.randf_range(12.0, 16.0))
	for i in n:
		var v := -hl + 3.0 + pitch * (i + 0.5) + (hl * 2.0 - 6.0 - pitch * n) * 0.5
		var len := hd * 2.0 - 12.0
		lk["seed"] = rng.randf() * 100.0
		_house(F, _lp(b, 2.0, v), b["z"], 11.0, len, h, lk, roofed)
		for k in 2:
			_tree(F, _lp(b, rng.randf_range(-hd + 4.0, hd - 4.0), v + pitch * 0.5), rng)
	# Stellplätze an der Straßenseite
	_rect(F, b, -hd, -hd + 6.0, -hl, hl, 0.06, C_ASPHALT)
	var v2 := -hl + 2.0
	while v2 < hl - 2.0:
		_car(F, _lp(b, -hd + 3.0, v2), b["x"], rng, 0.1)
		v2 += 2.7


## Reihenhäuser: zwei Zeilen an den Längsseiten, Vorgarten, Gärten mit Hecken nach innen
static func _reihen(F: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> void:
	var dk: String = b["dk"]
	var hd: float = b["hd"]
	var hl: float = b["hl"]
	_rect(F, b, -hd, hd, -hl, hl, 0.05, C_LAWN2)
	F["rngv"] = rng
	var front := 4.5
	var dep := minf(10.0, hd - front - 0.8)  # die beiden Zeilen treffen sich nicht in der Mitte
	if dep < 6.0:
		_garten(F, b, rng)
		return
	var lk := _look("residential" if dk != "chinatown" else dk, rng, [6.0, 4.0][rng.randi() % 2])
	for su in [-1.0, 1.0]:
		var u: float = su * (hd - front - dep * 0.5)
		var v := -hl + 2.0
		var hh := _floors(rng.randf_range(7.0, 9.5))
		while v < hl - 8.0:
			var w := rng.randf_range(6.0, 7.5)
			var lk2 := lk.duplicate()
			lk2["tint"] = lk["tint"] * rng.randf_range(0.85, 1.2)
			lk2["seed"] = rng.randf() * 100.0
			_house(F, _lp(b, u, v + w * 0.5), b["x"], dep, w, hh, lk2, true, false)
			# Garten hinter dem Haus mit Hecke
			var gu0: float = su * (hd - front - dep)
			var gu1 := 0.0
			_solid(F, _lp(b, (gu0 + gu1) * 0.5, v), b["x"], Vector3(absf(gu0 - gu1), 1.0, 0.5), C_HEDGE)
			if rng.randf() < 0.35:
				_tree(F, _lp(b, lerpf(gu0, gu1, 0.6), v + w * 0.5), rng, 0.7)
			v += w
		_solid(F, _lp(b, su * (hd - front * 0.5), 0.0), b["z"], Vector3(hl * 2.0 - 4.0, 0.7, 0.45), C_HEDGE)


## Einfamilienhäuser (villa: Stadtvillen mit großen Gärten): Häuser an den Längsseiten, Hecken, Bäume, Auto vor der Tür
static func _efh(F: Dictionary, b: Dictionary, rng: RandomNumberGenerator, villa: bool) -> void:
	var hd: float = b["hd"]
	var hl: float = b["hl"]
	_rect(F, b, -hd, hd, -hl, hl, 0.05, C_LAWN)
	F["rngv"] = rng
	var plot := rng.randf_range(24.0, 30.0) if villa else rng.randf_range(15.0, 19.0)
	for su in [-1.0, 1.0]:
		var v := -hl
		while v < hl - plot * 0.7:
			var pw := minf(plot, hl - v)
			var hw := rng.randf_range(12.0, 15.0) if villa else rng.randf_range(8.5, 11.0)
			var hdp := rng.randf_range(11.0, 13.0) if villa else rng.randf_range(8.0, 10.0)
			hw = minf(hw, pw - 4.0)
			var setback := rng.randf_range(5.0, 7.0)
			hdp = minf(hdp, hd - setback - 0.8)  # die Häuser beider Seiten treffen sich nicht in der Mitte
			var u: float = su * (hd - setback - hdp * 0.5)
			var lk := _look("residential", rng, 6.0)
			var h := _floors(rng.randf_range(9.0, 12.0)) if villa else rng.randf_range(6.0, 7.5)
			var jit := rng.randf_range(-1.0, 1.0) * minf((pw - hw) * 0.5 - 1.0, 1.0)
			if hdp >= 6.0:
				_house(F, _lp(b, u, v + pw * 0.5 + jit), b["x"], hdp, hw, h, lk, true, rng.randf() < 0.3)
			# Hecke zum Nachbarn, Bäume im Garten, Auto in der Einfahrt
			_solid(F, _lp(b, su * hd * 0.5, v), b["x"], Vector3(hd - 1.0, 1.1, 0.5), C_HEDGE)
			for i in (rng.randi_range(1, 3) if villa else rng.randi_range(0, 2)):
				_tree(F, _lp(b, su * rng.randf_range(2.0, hd - setback - hdp - 1.0), v + rng.randf_range(2.0, pw - 2.0)), rng, 0.8)
			if rng.randf() < 0.55:
				_car(F, _lp(b, su * (hd - 3.0), v + pw * 0.5 + hw * 0.5 + 1.8), b["x"], rng, 0.1)
			v += pw


## Park: Rasen, Wege übers Kreuz, Bäume in Gruppen, manchmal ein Teich oder ein Spielplatz, Leute
static func _park(F: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> void:
	var hd: float = b["hd"]
	var hl: float = b["hl"]
	_rect(F, b, -hd, hd, -hl, hl, 0.05, C_LAWN)
	_rect(F, b, -1.6, 1.6, -hl, hl, 0.07, C_PATH)
	_rect(F, b, -hd, hd, -1.6, 1.6, 0.075, C_PATH)
	var pond := rng.randf() < 0.35 and hd > 16.0 and hl > 18.0
	var pc := Vector2(rng.randf_range(-hd * 0.4, hd * 0.4), rng.randf_range(-hl * 0.4, hl * 0.4))
	pc = Vector2(signf(pc.x) * maxf(absf(pc.x), 9.0), signf(pc.y) * maxf(absf(pc.y), 9.0))
	var pr := minf(hd, hl) * 0.32
	if pond:
		(_cell(F, b["c"])["flat"] as Geo).disc(_lp(b, pc.x, pc.y) + Vector3(0, 0.09, 0), pr, C_WATER, 14)
		(_cell(F, b["c"])["flat"] as Geo).disc(_lp(b, pc.x, pc.y) + Vector3(0, 0.08, 0), pr + 1.2, C_GRAVEL, 14)
	elif rng.randf() < 0.5:
		# Spielplatz: Sandfläche, bunte Geräte
		var q := _lp(b, pc.x, pc.y)
		_flat_obb(F, q, b["x"], 7.0, 6.0, 0.08, C_SAND)
		for i in 3:
			_solid(F, q + b["x"] * rng.randf_range(-5.0, 5.0) + b["z"] * rng.randf_range(-4.0, 4.0), b["x"],
				Vector3(rng.randf_range(1.0, 2.5), rng.randf_range(0.8, 2.6), rng.randf_range(1.0, 2.0)), SHEDS[rng.randi() % SHEDS.size()] * 1.4)
	# Bäume in Gruppen: je Gruppe eine Mitte, drum herum drei bis sechs
	var n := int(hd * hl / 120.0) + 2
	for gi in n:
		var gc := Vector2(rng.randf_range(-hd + 4.0, hd - 4.0), rng.randf_range(-hl + 4.0, hl - 4.0))
		for i in rng.randi_range(3, 6):
			var u := gc.x + rng.randf_range(-6.0, 6.0)
			var v := gc.y + rng.randf_range(-6.0, 6.0)
			if absf(u) > hd - 1.5 or absf(v) > hl - 1.5 or absf(u) < 3.0 or absf(v) < 3.0 \
					or (pond and Vector2(u, v).distance_to(pc) < pr + 4.0):
				continue
			_tree(F, _lp(b, u, v), rng, rng.randf_range(0.95, 1.45))
	# Bänke an den Wegen, Leute
	for i in 6:
		var along := rng.randf_range(-hl + 4.0, hl - 4.0)
		_solid(F, _lp(b, 2.6 * (1.0 if i % 2 == 0 else -1.0), along), b["z"], Vector3(1.6, 0.5, 0.5), Color(0.32, 0.22, 0.13))
	_people(F, b, rng, int(hd * hl / 90.0))


## Platz: Pflaster, Brunnen, Bäume am Rand, Bänke, Leute; im Marktviertel Marktstände
static func _platz(F: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> void:
	var hd: float = b["hd"]
	var hl: float = b["hl"]
	_rect(F, b, -hd, hd, -hl, hl, 0.05, C_PAVE * 1.08)
	var g: Geo = _cell(F, b["c"])["solid"]
	var r := minf(minf(hd, hl) * 0.3, 7.0)
	# Brunnen: Beckenrand, Wasser, Säule in der Mitte
	g.cyl(_lp(b, 0.0, 0.0), r, 0.55, Color(0.55, 0.53, 0.5), 16, false)
	g.ring(_lp(b, 0.0, 0.0) + Vector3(0, 0.55, 0), r - 0.2, 0.2, Color(0.6, 0.58, 0.55), 16)
	(_cell(F, b["c"])["flat"] as Geo).disc(_lp(b, 0.0, 0.0) + Vector3(0, 0.42, 0), r - 0.4, C_WATER * 1.2, 16)
	g.cyl(_lp(b, 0.0, 0.0), 0.5, 2.6, Color(0.58, 0.56, 0.52), 8)
	for su in [-1.0, 1.0]:
		var v := -hl + 4.0
		while v < hl - 3.0:
			_tree(F, _lp(b, su * (hd - 3.0), v), rng, 0.9)
			v += rng.randf_range(8.0, 11.0)
	if b["dk"] == "shops" or rng.randf() < 0.35:
		# Marktstände in zwei Reihen
		for su in [-1.0, 1.0]:
			var v := -hl + 6.0
			while v < hl - 6.0:
				if absf(v) > r + 3.0:
					var q := _lp(b, su * (r + 5.0), v)
					_solid(F, q, b["z"], Vector3(3.0, 2.6, 2.6), Color(0.85, 0.85, 0.82) if rng.randf() < 0.5 else SHEDS[rng.randi() % SHEDS.size()] * 1.5)
				v += 4.0
	_people(F, b, rng, int(hd * hl / 70.0))


## Parkplatz mit Reihen und Linien; in der Innenstadt manchmal ein Parkhaus
static func _parken(F: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> void:
	var dk: String = b["dk"]
	var hd: float = b["hd"]
	var hl: float = b["hl"]
	_rect(F, b, -hd, hd, -hl, hl, 0.05, C_ASPHALT * 1.15)
	if dk in ["downtown", "shops"] and rng.randf() < 0.4:
		F["rngv"] = rng
		_house(F, _lp(b, 0.0, 0.0), b["x"], hd * 2.0 - 6.0, hl * 2.0 - 6.0, rng.randf_range(10.0, 15.0), _look(dk, rng, 2.0))
		return
	# Reihen quer zur Länge: je Reihe zwei Stellplatzzeilen (5 m) und eine Fahrgasse (6 m)
	var u := -hd + 2.0
	while u + 10.0 < hd - 1.0:
		for k in 2:
			var uu := u + 2.5 + k * 5.0
			var v := -hl + 2.0
			while v < hl - 2.0:
				var q := _lp(b, uu, v + 1.25)
				_flat_obb(F, _lp(b, uu, v), b["x"], 2.5, 0.06, 0.08, C_LINE)
				if rng.randf() < 0.72:
					_car(F, q, b["x"], rng, 0.12)
				v += 2.6
		u += 16.0
	for i in rng.randi_range(2, 5):
		_tree(F, _lp(b, rng.randf_range(-hd + 1.0, hd - 1.0), (hl - 1.0) * (1.0 if i % 2 == 0 else -1.0)), rng)


## Schule: L aus zwei Flügeln, Schulhof, Sportfeld, Bäume
static func _schule(F: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> void:
	var hd: float = b["hd"]
	var hl: float = b["hl"]
	_rect(F, b, -hd, hd, -hl, hl, 0.05, C_PAVE)
	F["rngv"] = rng
	var lk := _look("boulevard", rng, [0.0, 6.0][rng.randi() % 2])
	lk["tint"] = Vector3(0.62, 0.58, 0.5) * rng.randf_range(0.85, 1.05)
	var h := _floors(rng.randf_range(10.0, 13.0))
	# L aus zwei Flügeln, der zweite stößt an den ersten an
	_house(F, _lp(b, -hd + 8.0, -hl * 0.2), b["z"], hl * 1.5, 14.0, h, lk)
	var w2 := hd * 1.6 - 15.5
	_house(F, _lp(b, -hd + 15.0 + w2 * 0.5, hl - 8.0), b["x"], w2, 14.0, h, lk)
	# Sportfeld in der freien Ecke
	var fu := hd * 0.35
	var fv := -hl * 0.35
	var fw := minf(hd * 0.55, 16.0)
	var fl := minf(hl * 0.55, 24.0)
	_rect(F, b, fu - fw, fu + fw, fv - fl, fv + fl, 0.07, C_TRACK)
	_rect(F, b, fu - fw + 2.0, fu + fw - 2.0, fv - fl + 2.0, fv + fl - 2.0, 0.08, C_PITCH)
	for i in rng.randi_range(4, 8):
		_tree(F, _lp(b, hd - 2.5, rng.randf_range(-hl + 3.0, hl - 3.0)), rng)
	_people(F, b, rng, 10)


## Kirche: Schiff mit Satteldach, Turm mit spitzem Helm, Kirchhof mit Bäumen
static func _kirche(F: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> void:
	var hd: float = b["hd"]
	var hl: float = b["hl"]
	_rect(F, b, -hd, hd, -hl, hl, 0.05, C_LAWN)
	_rect(F, b, -hd, 0.0, -2.0, 2.0, 0.07, C_PATH)
	F["rngv"] = rng
	var lk := _look("residential", rng, 6.0)
	lk["tint"] = [Vector3(0.55, 0.5, 0.42), Vector3(0.5, 0.26, 0.18), Vector3(0.6, 0.58, 0.52)][rng.randi() % 3]
	lk["roof"] = [Vector3(0.14, 0.15, 0.17), Vector3(0.32, 0.13, 0.08), Vector3(0.2, 0.36, 0.3)][rng.randi() % 3]
	var nave_l := minf(minf(hl * 1.5, hl * 2.0 - 18.0), 34.0)  # Turm (7,5 m) bleibt im Block
	var nave_w := minf(hd * 0.9, 15.0)
	var ctr := _lp(b, 2.0, 0.0)
	if not _house(F, ctr, b["z"], nave_l, nave_w, 13.0, lk, true, false):
		return
	# Turm am Ende zur Straße, Helm als Pyramide (im Häuser-Batch)
	var tp: Vector3 = ctr - b["z"] * (nave_l * 0.5 + 3.5)
	var th := rng.randf_range(28.0, 38.0)
	var basis := Basis(b["x"], Vector3.UP, b["z"])
	# Turm am Schiff: dasselbe Haus (gleiche Haus-Nr.)
	Track._bb_box(Transform3D(basis * Basis.from_scale(Vector3(7.5, th, 7.5)), tp + Vector3(0, th * 0.5, 0)), lk["tint"], 0.15,
		lk["seed"] + 1.0, 6.0, 0.0)
	var st := Track._bb_st(tp)
	var top: Vector3 = tp + Vector3(0, th + rng.randf_range(12.0, 18.0), 0)
	var hx: Vector3 = b["x"] * 4.0
	var hz: Vector3 = b["z"] * 4.0
	var base: Vector3 = tp + Vector3(0, th, 0)
	var corners := [base - hx - hz, base + hx - hz, base + hx + hz, base - hx + hz]
	var rcol := Color(lk["roof"].x, lk["roof"].y, lk["roof"].z, 0.0)
	for i in 4:
		var a: Vector3 = corners[i]
		var c: Vector3 = corners[(i + 1) % 4]
		var nrm := (c - a).cross(top - a).normalized()
		if nrm.dot((a + c) * 0.5 - tp) < 0.0:
			nrm = -nrm
		Track._bb_poly(st, [a, c, top], nrm, rcol, Vector2(lk["seed"], 7.0), a, (c - a).normalized(), th, Color((c - a).length(), th + 15.0, Track.FACE_GABLE))
	F["feet"].append({"pos": tp, "r": 4.0, "foot": [Vector2(tp.x, tp.z), Vector2(b["x"].x, b["x"].z), Vector2(b["z"].x, b["z"].z), 3.75, 3.75]})
	for i in rng.randi_range(6, 12):
		var u := rng.randf_range(-hd + 2.0, hd - 2.0)
		var v := rng.randf_range(-hl + 2.0, hl - 2.0)
		if absf(u - 2.0) < nave_w * 0.5 + 3.0 and absf(v) < nave_l * 0.5 + 9.0:
			continue
		_tree(F, _lp(b, u, v), rng)


## Sportplatz: Rasen mit Linien, Laufbahn, Tore, Flutlicht, Vereinsheim
static func _sport(F: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> void:
	var hd: float = b["hd"]
	var hl: float = b["hl"]
	_rect(F, b, -hd, hd, -hl, hl, 0.05, C_LAWN2)
	var fw := minf(hd - 4.0, 34.0)
	var fl := minf(hl - 5.0, 52.0)
	_rect(F, b, -fw, fw, -fl, fl, 0.06, C_TRACK)
	var pw := fw - 4.0
	var pl := fl - 5.0
	_rect(F, b, -pw, pw, -pl, pl, 0.07, C_PITCH)
	# Linien: Rand, Mittellinie, Mittelkreis, Strafräume
	for s in [-1.0, 1.0]:
		_rect(F, b, s * pw - 0.1, s * pw + 0.1, -pl, pl, 0.08, C_LINE)
		_rect(F, b, -pw, pw, s * pl - 0.1, s * pl + 0.1, 0.08, C_LINE)
		_rect(F, b, -pw * 0.55, pw * 0.55, s * (pl - pl * 0.3) - 0.1, s * (pl - pl * 0.3) + 0.1, 0.08, C_LINE)
		for su in [-1.0, 1.0]:
			_rect(F, b, su * pw * 0.55 - 0.1, su * pw * 0.55 + 0.1, s * pl * 0.7, s * pl, 0.08, C_LINE)
		_solid(F, _lp(b, 0.0, s * (pl + 0.6)), b["x"], Vector3(7.3, 2.4, 0.15), C_LINE)
	_rect(F, b, -pw, pw, -0.1, 0.1, 0.08, C_LINE)
	(_cell(F, b["c"])["flat"] as Geo).ring(_lp(b, 0.0, 0.0) + Vector3(0, 0.085, 0), minf(pw * 0.3, 9.0), 0.2, C_LINE, 20)
	# Flutlicht an den Ecken, Vereinsheim
	for su in [-1.0, 1.0]:
		for sv in [-1.0, 1.0]:
			var q := _lp(b, su * (fw + 1.5), sv * (fl * 0.6))
			_solid(F, q, b["x"], Vector3(0.4, 18.0, 0.4), Color(0.5, 0.5, 0.52))
			_solid(F, q, b["x"], Vector3(2.4, 1.2, 0.6), Color(0.9, 0.9, 0.85), 18.0)
	F["rngv"] = rng
	_house(F, _lp(b, hd - 6.0, -hl + 8.0), b["x"], 9.0, 14.0, 4.5, _look("residential", rng, 6.0), true)
	_people(F, b, rng, 14)


## Kleingärten: Parzellen mit Laube, Beeten, Hecken, Obstbäumen, ein Weg in der Mitte
static func _garten(F: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> void:
	var hd: float = b["hd"]
	var hl: float = b["hl"]
	_rect(F, b, -hd, hd, -hl, hl, 0.05, C_LAWN2)
	_rect(F, b, -1.5, 1.5, -hl, hl, 0.07, C_GRAVEL)
	for su in [-1.0, 1.0]:
		var v := -hl + 1.0
		while v < hl - 10.0:
			var pw := rng.randf_range(11.0, 14.0)
			var u0: float = su * 2.0
			var u1: float = su * (hd - 1.0)
			var q := _lp(b, (u0 + u1) * 0.5, v + pw * 0.5)
			# Beete
			var bed := C_SOIL if rng.randf() < 0.5 else Color(0.22, 0.3, 0.12)
			_flat_obb(F, _lp(b, lerpf(u0, u1, 0.7), v + pw * 0.5), b["x"], absf(u1 - u0) * 0.22, pw * 0.3, 0.07, bed)
			# Laube
			var sc: Color = SHEDS[rng.randi() % SHEDS.size()]
			var sp := _lp(b, lerpf(u0, u1, 0.25), v + pw * 0.5 + rng.randf_range(-2.0, 2.0))
			_solid(F, sp, b["x"], Vector3(3.0, 2.3, 2.6), sc)
			_solid(F, sp, b["x"], Vector3(3.4, 0.25, 3.0), Color(0.18, 0.12, 0.1), 2.3)
			# Hecke zur nächsten Parzelle, Obstbaum
			_solid(F, _lp(b, (u0 + u1) * 0.5, v), b["x"], Vector3(absf(u1 - u0), 1.1, 0.5), C_HEDGE)
			if rng.randf() < 0.6:
				_tree(F, _lp(b, lerpf(u0, u1, rng.randf_range(0.5, 0.9)), v + rng.randf_range(2.0, pw - 2.0)), rng, 0.55)
			v += pw
	_people(F, b, rng, 4)


## Gewerbe: große Hallen (Wellblech) mit Hof, Lkw an den Toren; Lager: lange Hallen mit Rampen
static func _halle(F: Dictionary, b: Dictionary, rng: RandomNumberGenerator, lager: bool) -> void:
	var dk: String = b["dk"]
	var hd: float = b["hd"]
	var hl: float = b["hl"]
	_rect(F, b, -hd, hd, -hl, hl, 0.05, C_CONCRETE)
	F["rngv"] = rng
	var st: Dictionary = STYLE[dk]
	var hr: Array = st["h"][mini(int(b["zone"]), (st["h"] as Array).size() - 1)]
	var h := rng.randf_range(hr[0], hr[1]) if dk == "industrial" else rng.randf_range(7.0, 11.0)
	var lk := _look(dk, rng, 2.0)
	if dk != "industrial":
		var tints: Array = Track.DISTRICTS["industrial"]["tints"]
		var t: Color = tints[rng.randi() % tints.size()]
		lk["tint"] = Vector3(t.r, t.g, t.b) * rng.randf_range(0.9, 1.4)
	if lager:
		var dep := minf(rng.randf_range(24.0, 32.0), hd * 2.0 - 16.0)
		_house(F, _lp(b, hd - dep * 0.5 - 4.0, 0.0), b["x"], dep, hl * 2.0 - 8.0, h, lk)
		# Rampen und Lkw an der Hofseite
		var v := -hl + 8.0
		while v < hl - 8.0:
			_flat_obb(F, _lp(b, hd - dep - 5.0, v), b["x"], 1.5, 1.6, 0.07, Color(0.08, 0.08, 0.08))
			if rng.randf() < 0.45:
				_car(F, _lp(b, hd - dep - 9.0, v), b["x"], rng, 0.85)
			v += 9.0
	else:
		var annex := hd > 24.0 and hl > 28.0  # Bürotrakt vorn, nur wo neben der Halle Platz ist
		var n := 1 if hl < 50.0 or rng.randf() < 0.4 else 2
		for i in n:
			var len := (hl * 2.0 - 10.0) / n - (4.0 if n > 1 else 0.0)
			var v := -hl + 5.0 + len * 0.5 + i * (len + 8.0)
			var dep := minf(rng.randf_range(28.0, 50.0), hd * 2.0 - (18.0 if annex else 12.0))
			_house(F, _lp(b, hd - dep * 0.5 - 3.0, v), b["x"], dep, len, h * rng.randf_range(0.85, 1.1), lk)
		# Bürotrakt, Stellplätze
		var v2 := -hl + 3.0
		if annex:
			_house(F, _lp(b, -hd + 7.0, -hl + 12.0), b["x"], 10.0, 18.0, _floors(8.0), _look("highway", rng, 1.0))
			v2 = -hl + 25.0
		while v2 < hl - 3.0:
			if rng.randf() < 0.6:
				_car(F, _lp(b, -hd + 4.0, v2), b["x"], rng, 0.35)
			v2 += 2.7


## Containerfläche: gestapelte Container in Reihen, Portalkran, Lkw
static func _container(F: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> void:
	var hd: float = b["hd"]
	var hl: float = b["hl"]
	_rect(F, b, -hd, hd, -hl, hl, 0.05, C_CONCRETE * 0.9)
	var u := -hd + 4.0
	while u < hd - 6.0:
		var v := -hl + 4.0
		while v < hl - 13.0:
			var stack := rng.randi_range(0, 4)
			for k in stack:
				_solid(F, _lp(b, u + 1.25, v + 6.1), b["z"], Vector3(12.2, 2.55, 2.45), CONTAINER[rng.randi() % CONTAINER.size()]
					* rng.randf_range(0.85, 1.1), k * 2.6)
			v += 12.8
		u += rng.randf_range(2.6, 3.0) if rng.randf() < 0.75 else 8.0
	if rng.randf() < 0.6:
		# Portalkran über die Breite
		var v := rng.randf_range(-hl * 0.5, hl * 0.5)
		var kc := Color(0.75, 0.45, 0.1) if rng.randf() < 0.5 else Color(0.2, 0.35, 0.55)
		for su in [-1.0, 1.0]:
			_solid(F, _lp(b, su * (hd - 3.0), v), b["x"], Vector3(1.4, 22.0, 1.4), kc)
		_solid(F, _lp(b, 0.0, v), b["x"], Vector3(hd * 2.0 - 4.0, 2.0, 2.0), kc, 22.0)
	for i in rng.randi_range(2, 5):
		_car(F, _lp(b, rng.randf_range(-hd + 3.0, hd - 3.0), (hl - 3.0) * (1.0 if i % 2 == 0 else -1.0)), b["z"], rng, 0.9)


## Hof zwischen den Häusern (Lücke ohne eigene Straße): Rasen mit Bäumen und Bänken, gepflasterter Hof mit Autos oder
## Schotter mit einer Garagenzeile
static func _hof(F: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> void:
	var hd: float = b["hd"]
	var hl: float = b["hl"]
	if hd >= 16.0 and hl >= 18.0:
		# große Lücke: kleiner Park oder Platz (ohne eigene Straße ringsum)
		if rng.randf() < 0.6:
			_park(F, b, rng)
		else:
			_platz(F, b, rng)
		return
	var r := rng.randf()
	if r < 0.55:
		_rect(F, b, -hd, hd, -hl, hl, 0.05, C_LAWN if rng.randf() < 0.6 else C_LAWN2)
		var n := int(hd * hl / 45.0) + 1
		for i in n:
			_tree(F, _lp(b, rng.randf_range(-hd + 1.5, hd - 1.5), rng.randf_range(-hl + 1.5, hl - 1.5)), rng, rng.randf_range(0.8, 1.2))
		if hd > 7.0 and rng.randf() < 0.5:
			_solid(F, _lp(b, 0.0, 0.0), b["z"], Vector3(1.6, 0.5, 0.5), Color(0.32, 0.22, 0.13))
		if hd * hl > 150.0:
			_people(F, b, rng, 2)
	else:
		var paved := r < 0.8
		_rect(F, b, -hd, hd, -hl, hl, 0.05, C_PAVE if paved else C_GRAVEL)
		# Stellplätze an der langen Seite, gegenüber eine Garagenzeile (große Höfe)
		var v := -hl + 1.6
		while v < hl - 1.6 and hd > 4.5:
			if rng.randf() < 0.75:
				_car(F, _lp(b, -hd + 2.8, v), b["x"], rng, 0.1)
			v += 2.7
		if hd > 9.0 and hl > 8.0:
			var gl := hl * 2.0 - 2.0
			_solid(F, _lp(b, hd - 3.2, 0.0), b["z"], Vector3(gl, 2.6, 5.6), Color(0.5, 0.49, 0.46))
			var gv := -hl + 1.0 + 1.5
			while gv < hl - 1.5:
				_solid(F, _lp(b, hd - 6.03, gv), b["z"], Vector3(2.5, 2.1, 0.06), Color(0.28, 0.29, 0.31))  # Tor
				gv += 3.0
		for i in rng.randi_range(0, 2):
			_tree(F, _lp(b, rng.randf_range(-hd + 1.5, hd - 1.5), (hl - 1.5) * (1.0 if i % 2 == 0 else -1.0)), rng, 0.85)


## Brache: Schotter und Wiese, Büsche, ein paar Bäume
static func _brache(F: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> void:
	var hd: float = b["hd"]
	var hl: float = b["hl"]
	_rect(F, b, -hd, hd, -hl, hl, 0.05, C_GRAVEL * 0.85)
	for i in 4:
		_flat_obb(F, _lp(b, rng.randf_range(-hd * 0.6, hd * 0.6), rng.randf_range(-hl * 0.6, hl * 0.6)), b["x"],
			rng.randf_range(6.0, hd * 0.5), rng.randf_range(6.0, hl * 0.5), 0.06 + i * 0.004, Color(0.28, 0.33, 0.15))
	for i in rng.randi_range(5, 12):
		_tree(F, _lp(b, rng.randf_range(-hd + 2.0, hd - 2.0), rng.randf_range(-hl + 2.0, hl - 2.0)), rng, rng.randf_range(0.5, 0.9))


## Leute im Park, auf dem Platz, im Schulhof (tagsüber), als ein MultiMesh je Strecke am Ende
static func _people(F: Dictionary, b: Dictionary, rng: RandomNumberGenerator, n: int) -> void:
	n = int(n * F["dens"])
	for i in n:
		var p := _lp(b, rng.randf_range(-b["hd"] + 3.0, b["hd"] - 3.0), rng.randf_range(-b["hl"] + 3.0, b["hl"] - 3.0))
		var face := Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU)
		F["people"].append(Transform3D(Basis.looking_at(face, Vector3.UP), Vector3(p.x, 0.05, p.z)))
		if rng.randf() < 0.45:
			# zu zweit im Gespräch
			var p2 := p + face * 0.9
			F["people"].append(Transform3D(Basis.looking_at(-face, Vector3.UP), Vector3(p2.x, 0.05, p2.z)))


# --- Zum Schluss: Meshes und MultiMeshes ------------------------------------------------------------------------------

## Meshes und MultiMeshes Zelle für Zelle (Browser: im Zeitbudget, true = fertig), am Ende die Leute
static func _flush(root: Node3D, track: Dictionary, F: Dictionary, t0: int, budget: int) -> bool:
	if not F.has("holder"):
		var hn := Node3D.new()
		hn.name = "Stadtfuellung"
		root.add_child(hn)
		F["holder"] = hn
		F["keys"] = (F["cells"] as Dictionary).keys()
		F["ki"] = 0
	var holder: Node3D = F["holder"]
	var det: Array = GameState.gv("detail")
	var view := GameState.view_distance()
	var keys: Array = F["keys"]
	while F["ki"] < keys.size():
		if budget >= 0 and Time.get_ticks_msec() - t0 >= budget:
			return false
		var cl: Dictionary = F["cells"][keys[F["ki"]]]
		F["ki"] += 1
		var flat: Geo = cl["flat"]
		if not flat.empty():
			var mi := MeshInstance3D.new()
			mi.mesh = flat.mesh()
			mi.material_override = _mat("ground")
			mi.set_meta("no_merge", true)
			mi.set_meta("lod_class", 2)
			holder.add_child(mi)
		_mm(holder, _tree_mesh(), cl["trees"], cl["tcol"], view + 100.0, false)
		_mm(holder, _car_mesh(), cl["cars"], cl["ccol"], float(det[1]) + 120.0, false)
		_mm(holder, _lamp_mesh(), cl["lamps"], [], float(det[1]) + 200.0, false)
	if not (F["people"] as Array).is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = int(F["P"]["seed"]) + 5
		var day := Node3D.new()
		holder.add_child(day)
		var crowd := People.crowd(day, F["people"], [People.WAIT, People.PHONE, People.WAIT, People.WAVE, People.CLAP], rng, 200.0)
		crowd.name = "PassantenTag"
		if not track.has("fill_people"):
			track["fill_people"] = []
		track["fill_people"].append(crowd)
	return true


static func _mm(parent: Node3D, mesh: Mesh, xfs: Array, cols: Array, far: float, shadow: bool) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		if not cols.is_empty():
			mm.set_instance_color(i, cols[i])
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = far
	mi.visibility_range_end_margin = 30.0
	mi.set_meta("lod_class", 2)
	parent.add_child(mi)


# --- Gemeinsame Materialien und Formen (einmal gebaut, danach geteilt) -----------------------------------------------

static func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		"ground":
			m.vertex_color_use_as_albedo = true
			m.vertex_color_is_srgb = true
			m.roughness = 0.92
		"crown":
			m.vertex_color_use_as_albedo = true
			m.roughness = 0.95
		"car":
			m.vertex_color_use_as_albedo = true
			m.vertex_color_is_srgb = true
			m.roughness = 0.35
			m.metallic = 0.35
		"lamp":
			m.albedo_color = Color(1.0, 0.85, 0.6)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.75, 0.45)
			m.emission_energy_multiplier = 2.6
	_mats[key] = m
	return m


## Stadtbaum: Stamm und runde Krone (Krone in der Farbe der Instanz)
## Stadtbaum: Stamm und runde Krone in einer Fläche (Vertexfarben; die Farbe der Instanz färbt die Krone grün und den
## braunen Stamm dunkel), ein Draw Call je Zelle
static func _tree_mesh() -> ArrayMesh:
	if _meshes.has("tree"):
		return _meshes["tree"]
	var g := Geo.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.24
	trunk.height = 3.2
	trunk.radial_segments = 5
	trunk.rings = 1
	g.prim(trunk, Transform3D(Basis(), Vector3(0, 1.6, 0)), Color(0.55, 0.42, 0.32))
	var sph := SphereMesh.new()
	sph.radius = 2.4
	sph.height = 4.4
	sph.radial_segments = 7
	sph.rings = 4
	g.prim(sph, Transform3D(Basis(), Vector3(0, 4.9, 0)), Color(1, 1, 1))
	var sph2 := SphereMesh.new()
	sph2.radius = 1.6
	sph2.height = 2.8
	sph2.radial_segments = 6
	sph2.rings = 3
	g.prim(sph2, Transform3D(Basis(), Vector3(0.9, 6.1, 0.4)), Color(1, 1, 1))
	var am := g.mesh()
	am.surface_set_material(0, _mat("crown"))
	_meshes["tree"] = am
	return am


## Parkendes Auto in den Maßen des Verkehrs (traffic_car: Limousine 1,8 x 4,5 m; Transporter als höher gestreckte
## Instanz): Karosserie weiß (färbt die Instanz), Scheiben, Räder, Leuchten dunkel bzw. farbig
static func _car_mesh() -> ArrayMesh:
	if _meshes.has("car"):
		return _meshes["car"]
	var g := Geo.new()
	var fp := Vector2(1.8, 4.5)
	var h := 0.65
	var clear := 0.28
	g.tbox(Vector3(0, clear, 0), fp, fp - Vector2(0.08, 0.25), h, 0.0, Color(1, 1, 1))
	g.tbox(Vector3(0, clear + h, 0.2), Vector2(1.6, 2.3), Vector2(1.35, 1.7), 0.52, 0.1, Color(0.06, 0.07, 0.09))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			g.box(Vector3(sx * (fp.x * 0.5 - 0.16), 0.0, sz * (fp.y * 0.5 - 0.85)), Vector3.RIGHT, Vector3(0.3, 0.62, 0.62),
				Color(0.04, 0.04, 0.04))
		g.box(Vector3(sx * (fp.x * 0.5 - 0.3), clear + 0.3, fp.y * 0.5 + 0.01), Vector3.RIGHT, Vector3(0.35, 0.14, 0.04),
			Color(0.7, 0.05, 0.03))
		g.box(Vector3(sx * (fp.x * 0.5 - 0.3), clear + 0.3, -fp.y * 0.5 - 0.01), Vector3.RIGHT, Vector3(0.35, 0.14, 0.04),
			Color(0.95, 0.95, 0.88))
	var m := g.mesh()
	m.surface_set_material(0, _mat("car"))
	_meshes["car"] = m
	return m


## Leuchte einer Laterne (der Mast steht in den kleinen Körpern der Zelle)
static func _lamp_mesh() -> ArrayMesh:
	if _meshes.has("lamp"):
		return _meshes["lamp"]
	var am := ArrayMesh.new()
	var st := SurfaceTool.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.36, 0.14, 0.62)
	st.append_from(hm, 0, Transform3D(Basis(), Vector3(0, 6.86, 0.0)))
	st.commit(am)
	am.surface_set_material(0, _mat("lamp"))
	_meshes["lamp"] = am
	return am


## Geometrie mit Vertexfarben (Böden, kleine Körper): Ecken, Normalen, Farben, Indizes
class Geo:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var i := PackedInt32Array()

	func empty() -> bool:
		return v.is_empty()

	## Viereck a, b, c, d (Normale aus der Lage, zeigt nach oben bzw. außen); Godot: Dreiecke im Uhrzeigersinn
	func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, col: Color, nrm := Vector3.ZERO) -> void:
		var nn := nrm if nrm != Vector3.ZERO else Vector3.UP
		var k := v.size()
		v.append_array([a, b, cc, d])
		n.append_array([nn, nn, nn, nn])
		c.append_array([col, col, col, col])
		if (b - a).cross(cc - a).dot(nn) > 0.0:
			i.append_array([k, k + 2, k + 1, k, k + 3, k + 2])
		else:
			i.append_array([k, k + 1, k + 2, k, k + 2, k + 3])

	## Quader ohne Boden: Fußmitte p, Achse ax (Länge size.x entlang ax, Höhe size.y, Breite size.z quer)
	func box(p: Vector3, ax: Vector3, size: Vector3, col: Color) -> void:
		var bx := ax.cross(Vector3.UP)
		var hx := ax * size.x * 0.5
		var hz := bx * size.z * 0.5
		var up := Vector3(0, size.y, 0)
		var q := [p - hx - hz, p + hx - hz, p + hx + hz, p - hx + hz]
		quad(q[0] + up, q[1] + up, q[2] + up, q[3] + up, col, Vector3.UP)
		for k in 4:
			var a: Vector3 = q[k]
			var b: Vector3 = q[(k + 1) % 4]
			var nrm := (b - a).cross(Vector3.UP).normalized()
			if nrm.dot((a + b) * 0.5 - p) < 0.0:
				nrm = -nrm
			quad(a, b, b + up, a + up, col * 0.92, nrm)

	## Quader, oben schmaler (wie Builder.tapered_box): Fußmitte p, unten/oben Breite x Länge, Höhe h, oben nach z versetzt
	func tbox(p: Vector3, bottom: Vector2, top: Vector2, h: float, top_z: float, col: Color) -> void:
		var b0 := [Vector3(-bottom.x, 0, -bottom.y) * 0.5, Vector3(bottom.x, 0, -bottom.y) * 0.5, Vector3(bottom.x, 0, bottom.y) * 0.5,
			Vector3(-bottom.x, 0, bottom.y) * 0.5]
		var t0 := [Vector3(-top.x * 0.5, h, top_z - top.y * 0.5), Vector3(top.x * 0.5, h, top_z - top.y * 0.5),
			Vector3(top.x * 0.5, h, top_z + top.y * 0.5), Vector3(-top.x * 0.5, h, top_z + top.y * 0.5)]
		quad(p + t0[0], p + t0[1], p + t0[2], p + t0[3], col, Vector3.UP)
		for k in 4:
			var a: Vector3 = p + b0[k]
			var b: Vector3 = p + b0[(k + 1) % 4]
			var ta: Vector3 = p + t0[k]
			var tb: Vector3 = p + t0[(k + 1) % 4]
			var nrm := (b - a).cross(ta - a).normalized()
			var mid := (a + b + ta + tb) * 0.25
			if nrm.dot(mid - (p + Vector3(0, h * 0.5, top_z * 0.5))) < 0.0:
				nrm = -nrm
			quad(a, b, tb, ta, col * 0.9, nrm)

	## Runde Fläche (Teich, Becken) als Fächer
	func disc(p: Vector3, r: float, col: Color, segs: int) -> void:
		var k := v.size()
		v.append(p)
		n.append(Vector3.UP)
		c.append(col)
		for s in segs:
			var a := TAU * s / segs
			v.append(p + Vector3(cos(a) * r, 0, sin(a) * r))
			n.append(Vector3.UP)
			c.append(col)
		for s in segs:
			var a1 := k + 1 + s
			var a2 := k + 1 + (s + 1) % segs
			# von oben im Uhrzeigersinn
			if (v[a1] - p).cross(v[a2] - p).dot(Vector3.UP) > 0.0:
				i.append_array([k, a2, a1])
			else:
				i.append_array([k, a1, a2])

	## Ring (Mittelkreis) auf dem Boden
	func ring(p: Vector3, r: float, w: float, col: Color, segs: int) -> void:
		for s in segs:
			var a0 := TAU * s / segs
			var a1 := TAU * (s + 1) / segs
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			quad(p + d0 * (r - w), p + d1 * (r - w), p + d1 * (r + w), p + d0 * (r + w), col)

	## Zylinder (Brunnenbecken, Säule) ohne Boden; cap: mit Deckel
	func cyl(p: Vector3, r: float, h: float, col: Color, segs: int, cap := true) -> void:
		for s in segs:
			var a0 := TAU * s / segs
			var a1 := TAU * (s + 1) / segs
			var d0 := Vector3(cos(a0), 0, sin(a0))
			var d1 := Vector3(cos(a1), 0, sin(a1))
			quad(p + d0 * r, p + d1 * r, p + d1 * r + Vector3(0, h, 0), p + d0 * r + Vector3(0, h, 0), col * 0.92,
				((d0 + d1) * 0.5).normalized())
		if cap:
			disc(p + Vector3(0, h, 0), r, col, segs)

	## fertige Form (CylinderMesh, SphereMesh ...) mit Lage xf und einer Farbe übernehmen
	func prim(pm: PrimitiveMesh, xf: Transform3D, col: Color) -> void:
		var arrs := pm.get_mesh_arrays()
		var pv: PackedVector3Array = arrs[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = arrs[Mesh.ARRAY_NORMAL]
		var pi: PackedInt32Array = arrs[Mesh.ARRAY_INDEX]
		var k := v.size()
		for j in pv.size():
			v.append(xf * pv[j])
			n.append((xf.basis * pn[j]).normalized())
			c.append(col)
		for j in pi:
			i.append(k + j)

	func mesh() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_INDEX] = i
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m
