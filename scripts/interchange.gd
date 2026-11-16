extends RefCounted
## Autobahndreiecke (seit 2.36): wo eine Querspange oder Spange auf einen Ring trifft, gibt es keine flache Einmündung
## mehr (gerade Rampe quer zum Ring, Lücke im Mittelstreifen), sondern ein Kreuzungsbauwerk wie in Underground:
##  - Der Stamm (Querspange, Spange) teilt sich in drei Wege (Sperrflächen mit Leitschwellen, Schilderbrücke davor):
##    rechts eine Rampe, die ebenerdig neben dem Ring einfädelt (NR), links eine, die vom Ring abzweigt (NE).
##  - Geradeaus führt eine Brücke über den Ring (13-19 m hoch, Pfeiler, Betonschutzwand, Laternen) und teilt sich
##    drüben in der Luft in zwei Flügel, die im weiten Bogen hinunter zur anderen Fahrbahn des Rings führen (FM
##    fädelt ein, FE zweigt ab).
## Jede Rampe hat zwei Spuren mit Gegenverkehr (wie alle Straßen im Spiel); in Fahrtrichtung befahren führt jede der vier
## Rampen von genau einer Richtungsfahrbahn des Rings zum Stamm oder umgekehrt: aus jeder Richtung geht es ohne Wenden
## weiter, und nirgends kreuzt man den Gegenverkehr auf gleicher Höhe.
## Geplant in world_layout (plan), gebaut als eigene Strecke im Stil von track_builder (begin/step), die Welt lädt sie
## nach wie ein Autobahnstück. Der Ring bekommt an den Einmündungen "slip"-Wege (track_builder._plan_autobahn): dort
## fehlen seine Randwand, das Bankett und die Laternen, die Rampe baut den Übergang selbst.

const Track := preload("res://scripts/track_builder.gd")
const Builder := preload("res://scripts/car_builder.gd")

const HALF := 5.5  # halbe Breite einer Rampe (zwei Spuren à 4,5 m, Seitenstreifen)
const EDGE := 0.6  # Schutzwand: so weit außerhalb der Fahrbahn
const RING_HW := Track.HALF_W + Track.AB_EXTRA + Track.MED  # Fahrbahnrand des Rings (mit Mittelstreifen)
const RING_WALL := RING_HW + Track.WALK + 0.3  # Randwand des Rings
const JOIN := RING_HW + HALF  # Mittellinie einer Rampe, die neben dem Ring herläuft
const JOIN_END := RING_HW - 0.5  # Ende der Rampe: gut zur Hälfte in der rechten Spur des Rings
const L_JOIN := 90.0  # so lange läuft eine Rampe neben dem Ring her (Beschleunigungs- bzw. Verzögerungsstreifen)
const L_TAPER := 110.0  # danach läuft sie über diese Länge in die rechte Spur aus (gut 1:18)
const V_F := 34.0  # Brücke: so weit hinter der Mitte des Rings teilt sie sich in die Flügel
const R_WING := 85.0  # Bogen der Flügel (gut 100 km/h)
const PTS_STEP := 4.0
const STEP := 2.0
const DECK := 3.0  # ab dieser Höhe Brücke (Platte auf Pfeilern), darunter Rampe zwischen Stützmauern
const DECK_T := 1.6  # Dicke der Brückenplatte
const PILLAR_STEP := 34.0
const GORE := 5.0  # Sperrfläche an Gabelungen: bis zu dieser Breite befahrbar, dann beginnt die Schutzwand (Nase)
const LAMP_STEP := 48.0
## Wege eines Dreiecks (in dieser Reihenfolge): B Brücke vom Abzweig über den Ring, NR/NE ebenerdige Rampen am Abzweig
## (einfädeln in die nahe Fahrbahn / von ihr abzweigen), FE/FM Flügel hinter dem Ring (von der fernen Fahrbahn abzweigen /
## in sie einfädeln)


# --- Planung ------------------------------------------------------------------------------------------------------

## Kurve durch Punkte wie track_builder.begin (Anfasser 0,22 * (nächster - voriger)): liegt genau wie die gebaute
static func smooth_curve(pts: Array) -> Curve3D:
	var c := Curve3D.new()
	c.bake_interval = 1.0
	var n := pts.size()
	for i in n:
		var prev: Vector3 = pts[maxi(i - 1, 0)]
		var nxt: Vector3 = pts[mini(i + 1, n - 1)]
		var t: Vector3 = (nxt - prev) * 0.22
		c.add_point(pts[i], -t, t)
	return c


static func _bez(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return p0 * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t * t * t)


## Linienzug mit Punkten im Abstand step (erster und letzter Punkt bleiben)
static func resample(dense: Array, step: float) -> Array:
	var out := [dense[0]]
	var acc := 0.0
	var nxt := step
	for i in range(1, dense.size()):
		var a: Vector3 = dense[i - 1]
		var b: Vector3 = dense[i]
		var l := a.distance_to(b)
		if l < 1e-6:
			continue
		while nxt <= acc + l:
			out.append(a.lerp(b, (nxt - acc) / l))
			nxt += step
		acc += l
	if (out[-1] as Vector3).distance_to(dense[-1]) > step * 0.3:
		out.append(dense[-1])
	else:
		out[-1] = dense[-1]
	return out


## Bezier als Linienzug (ohne den Anfangspunkt)
static func _bez_pts(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> Array:
	var dense := []
	for i in 401:
		dense.append(_bez(p0, p1, p2, p3, i / 400.0))
	return resample(dense, PTS_STEP).slice(1)


## Kreisbogen ab p0 (Richtung dir0) zur Seite side, Radius r, Winkel ang (ohne den Anfangspunkt)
static func _arc_pts(p0: Vector3, dir0: Vector3, side: Vector3, r: float, ang: float) -> Array:
	var out := []
	var n := maxi(int(ceil(r * ang / PTS_STEP)), 2)
	for i in range(1, n + 1):
		var th := ang * i / n
		out.append(p0 + dir0 * (r * sin(th)) + side * (r * (1.0 - cos(th))))
	return out


## Neben dem Ring: ab Ring-Meter d1 in Richtung dk (+1/-1) auf der Seite ls (+1 rechts, -1 links der Ringrichtung)
## L_JOIN parallel, dann über L_TAPER hinein in die rechte Spur
static func _join_pts(hc: Curve3D, d1: float, dk: float, ls: float, lj := L_JOIN, lt := L_TAPER) -> Array:
	var out := []
	var x := PTS_STEP
	while x <= lj + lt + 0.01:
		var f := Track.frame_at(hc, d1 + dk * x)
		var lat := JOIN if x <= lj else lerpf(JOIN, JOIN_END, smoothstep(0.0, 1.0, (x - lj) / lt))
		out.append((f["pos"] as Vector3) + (f["right"] as Vector3) * ls * lat)
		x += PTS_STEP
	return out


static func _cum(pts: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.0])
	for i in range(1, pts.size()):
		out.append(out[i - 1] + (pts[i] as Vector3).distance_to(pts[i - 1]))
	return out


## Anstieg der Brücke für Höhe h: so lang, dass man oben auch mit 90 m/s nicht abhebt (v² · Krümmung < Schwerkraft
## des Spiels, 18 m/s²; Krümmung der Rampe höchstens 6h/L²)
static func rise_len(h: float, v := 90.0) -> float:
	return sqrt(6.0 * h * v * v / 18.0)


## Ring um die Stelle kr als Kurve (32 Punkte, gut 2,5 km)
static func host_pts(host: Array, kr: int) -> Array:
	var m := host.size()
	var hp := []
	for k in range(-16, 17):
		hp.append(host[posmod(kr + k, m)])
	return hp


## Dreieck an der Stelle kr des Rings host (geschlossener Linienzug), wo der Stamm stem (Linienzug, beginnt am Ring)
## einmündet; h: Höhe der Brücke. Liefert {} wenn der Stamm zu kurz ist, sonst die Wege ("links": [{name, pts, elev}])
## und den gekürzten Stamm ("stem_cut", beginnt am Abzweig Q). opt (für enge Stellen): r_wing (Bogen der Flügel),
## sk (Länge ihrer S-Kurve zurück zum Ring je Meter Abstand), lj/lt (Einfädelstreifen und Auslauf)
const COMPACT := {"r_wing": 62.0, "sk": 2.1, "lj": 70.0, "lt": 95.0}


static func plan(host: Array, kr: int, stem: Array, h: float, opt := {}) -> Dictionary:
	var r_wing: float = opt.get("r_wing", R_WING)
	var sk: float = opt.get("sk", 2.7)
	var lj: float = opt.get("lj", L_JOIN)
	var lt: float = opt.get("lt", L_TAPER)
	var hp := host_pts(host, kr)
	var hc := smooth_curve(hp)
	var sc := smooth_curve(stem)
	var rise := rise_len(h)
	var v_q := 40.0 + rise + 45.0
	var SL := sc.get_baked_length()
	var dq := -1.0
	var d := 0.0
	while d < SL:
		var q := sc.sample_baked(d)
		var hq := hc.get_closest_point(q)
		if Vector2(q.x - hq.x, q.z - hq.z).length() >= v_q:
			dq = d
			break
		d += 2.0
	if dq < 0.0 or SL - dq < 420.0:
		return {}
	var Q := sc.sample_baked(dq)
	Q.y = 0.0
	var cut := [Q]
	for p in stem:
		if sc.get_closest_offset(p) > dq + 40.0:
			cut.append(p)
	if cut.size() < 3:
		return {}
	var tq: Vector3 = (cut[1] as Vector3) - Q  # Richtung des Stamms am Abzweig, vom Ring weg
	tq.y = 0.0
	tq = tq.normalized()
	var dJ := hc.get_closest_offset(Q)
	var fJ := Track.frame_at(hc, dJ)
	var J: Vector3 = fJ["pos"]
	var s := signf((Q - J).dot(fJ["right"]))  # Stamm rechts (+1) oder links (-1) der Ringrichtung
	var n: Vector3 = (fJ["right"] as Vector3) * s  # zum Stamm
	var tau: Vector3 = (fJ["fwd"] as Vector3) * s  # Fahrtrichtung der Fahrbahn auf der Seite des Stamms (Rechtsverkehr)
	var F := J - n * V_F
	var lb := Q.distance_to(F)
	var links := []
	var B := [Q] + _bez_pts(Q, Q - tq * lb * 0.4, F + n * lb * 0.25, F)
	links.append({"name": "B", "pts": B, "elev": [{"a": 40.0, "b": 40.0 + rise, "c": 1e6, "e": 1e6 + 1.0, "h": h}]})
	# ebenerdige Rampen: am Abzweig neben der Brücke, im Viertelkreis zum Ring, dann daneben her
	var w := Vector3(-tq.z, 0.0, tq.x)
	if w.dot(tau) < 0.0:
		w = -w
	var R := v_q - JOIN
	for side in [1.0, -1.0]:
		var st: Vector3 = Q + w * side * 2.0 * HALF
		var d1: float = dJ + s * side * (2.0 * HALF + R)
		var f1 := Track.frame_at(hc, d1)
		var p1: Vector3 = (f1["pos"] as Vector3) + (f1["right"] as Vector3) * s * JOIN
		var h1: Vector3 = (f1["fwd"] as Vector3) * s * side
		var pts := [st] + _bez_pts(st, st - tq * R * 0.55, p1 - h1 * R * 0.55, p1) + _join_pts(hc, d1, s * side, s, lj, lt)
		links.append({"name": "NR" if side > 0.0 else "NE", "pts": pts, "elev": []})
	# Flügel: hinter dem Ring in der Luft auseinander, im Bogen zur Seite und in einer S-Kurve hinunter zum Ring
	for side in [1.0, -1.0]:
		var arc := _arc_pts(F, -n, tau * side, r_wing, PI / 2.0)
		var a_end: Vector3 = arc[-1]
		var dv := V_F + r_wing - JOIN
		var d2: float = dJ + s * side * (r_wing + dv * sk)
		var f2 := Track.frame_at(hc, d2)
		var p2: Vector3 = (f2["pos"] as Vector3) - (f2["right"] as Vector3) * s * JOIN
		var h2: Vector3 = (f2["fwd"] as Vector3) * s * side
		var sl := a_end.distance_to(p2)
		var pts := [F] + arc + _bez_pts(a_end, a_end + tau * side * sl * 0.42, p2 - h2 * sl * 0.42, p2) + _join_pts(hc, d2, s * side, -s, lj, lt)
		# Gefälle: oben bis zur Hälfte des Bogens, dann gleichmäßig hinunter, unten, bevor die Rampe an die Randwand
		# des Rings kommt (dort steht sie auf dem Boden)
		var cum := _cum(pts)
		var e_w := -1.0
		for i in range(pts.size() - 1, -1, -1):
			var q: Vector3 = pts[i]
			var hq := hc.get_closest_point(q)
			if Vector2(q.x - hq.x, q.z - hq.z).length() >= RING_WALL + HALF + 4.0:
				e_w = cum[i]
				break
		var c_w := r_wing * PI / 4.0
		if e_w - c_w < rise_len(h, 60.0):
			return {}
		links.append({"name": "FE" if side > 0.0 else "FM", "pts": pts, "elev": [{"a": -1000.0, "b": -999.0, "c": c_w, "e": e_w, "h": h}]})
	return {"links": links, "stem_cut": cut, "J": J, "n": n, "tau": tau, "s": s, "F": F, "Q": Q, "h": h, "host_pts": hp, "dJ": dJ}


## Mindestabstand der Krümmung eines Wegs (für die Prüfung in world_layout): kleinster Radius über je 3 Punkte
static func min_radius(pts: Array) -> float:
	var rmin := 1e9
	for i in range(2, pts.size() - 2, 2):
		var a: Vector3 = pts[i - 2]
		var b: Vector3 = pts[i]
		var c: Vector3 = pts[i + 2]
		var ab := Vector2(b.x - a.x, b.z - a.z)
		var ac := Vector2(c.x - a.x, c.z - a.z)
		var area := absf(ab.cross(ac))
		if area > 1e-3:
			rmin = minf(rmin, ab.length() * Vector2(c.x - b.x, c.z - b.z).length() * ac.length() / (2.0 * area))
	return rmin


# --- Bau ------------------------------------------------------------------------------------------------------------

static func begin(race: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(race.get("seed", 1))
	var root := Node3D.new()
	root.name = "Dreieck"
	root.set_meta("race_name", race.get("name", "?"))
	root.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED  # Schilder bleiben deutsch
	var paths := []
	for i in (race["links"] as Array).size():
		var lk: Dictionary = race["links"][i]
		var c := smooth_curve(lk["pts"])
		if not (lk.get("elev", []) as Array).is_empty():
			c.set_meta("elev", lk["elev"])
		var L := c.get_baked_length()
		paths.append({"id": i, "kind": "main" if i == 0 else "ramp", "curve": c, "half_w": HALF, "length": L,
			"from": 0.0, "to": L, "closed": false, "side": 0.0, "name": lk["name"]})
	var main: Curve3D = paths[0]["curve"]
	var L0: float = paths[0]["length"]
	var track := {
		"node": root, "curve": main, "length": L0, "start": 0.0, "finish": L0, "type": "autobahn", "loop": false, "laps": 1,
		"blocks": [], "ramps": [], "lakes": [], "zones": [], "crossing": null, "crossing_d": -1.0,
		"districts": ["land"], "parks": [], "ponds": [], "tunnels": [], "el": [], "posts": [], "stadium_d": -1.0,
		"medians": [], "elev0": [], "force_stadium": false, "city": {}, "rivers": [], "bridges": [], "hills": [],
		"spectators": [], "walkers": [], "pools": [], "extra": HALF - Track.HALF_W, "paths": paths,
		"xf": Transform3D.IDENTITY, "world_exit": {}, "world_exit2": {}, "tail_join": false, "no_exit2": true, "keepout": [],
		"world_holes": PackedVector3Array(), "world": true, "no_ground": true, "dreieck": true,
	}
	return {"race": race, "rng": rng, "root": root, "track": track, "i": 0, "ix": true, "occupied": [], "buildings": [],
		"us": []}


const STEPS := 6


static func step(job: Dictionary) -> float:
	var i: int = job["i"]
	var t0 := Time.get_ticks_usec()
	match i:
		0:
			_prepare(job)
		1:
			_roads(job)
		2:
			_edges(job)
		3:
			_structure(job)
		4:
			_furniture(job)
		5:
			var root: Node3D = job["root"]
			Track._bake_street_light(root, job["track"])
			Track._finalize_walls(root)
			job.erase("ixd")
	job["us"].append(Time.get_ticks_usec() - t0)
	job["i"] = i + 1
	return 1.0 if i + 1 >= STEPS else float(i + 1) / STEPS


## Abtastung aller Wege alle STEP Meter: Lage, Richtung, Höhe; Lage zum Ring (hlat: quer zur Ringmitte, + rechts der
## Ringrichtung; hr: Querrichtung des Rings dort; hd: Ring-Meter)
static func _prepare(job: Dictionary) -> void:
	var race: Dictionary = job["race"]
	var tr: Dictionary = job["track"]
	var hc := smooth_curve(race["host_pts"])
	var links := []
	for p in tr["paths"]:
		var c: Curve3D = p["curve"]
		var L: float = p["length"]
		var fr := []
		var d := 0.0
		while true:
			var f := Track.frame_at(c, d)
			var hd := hc.get_closest_offset(f["pos"])
			var hf := Track.frame_at(hc, hd)
			f["hlat"] = ((f["pos"] as Vector3) - (hf["pos"] as Vector3)).dot(hf["right"])
			f["hr"] = hf["right"]
			f["hp"] = hf["pos"]
			f["hd"] = hd
			f["d"] = d
			fr.append(f)
			if d >= L:
				break
			d = minf(d + STEP, L)
		links.append({"c": c, "L": L, "f": fr, "name": p["name"]})
	# Partner an Gabelungen (zwischen beiden eine Sperrfläche bis GORE breit): Brücke mit den ebenerdigen Rampen am
	# Abzweig, die beiden Flügel hinter dem Ring
	var partners := {0: [1, 2], 1: [0], 2: [0], 3: [4], 4: [3]}
	var walls := StaticBody3D.new()
	walls.name = "WallsDreieck"
	(job["root"] as Node3D).add_child(walls)
	job["ixd"] = {"hc": hc, "links": links, "partners": partners, "noses": [], "walls": walls, "lamps": []}


## Index eines anderen Wegs, auf dessen Fahrbahn p (Höhe y) liegt (gleiche Höhe), sonst -1. margin: dazu,
## partner_gap: an Gabelungen zählt bis zu dieser Breite neben dem Partner noch dazu (Sperrfläche)
static func _other(ixd: Dictionary, li: int, p: Vector3, y: float, margin: float, partner_gap := 0.0) -> int:
	var links: Array = ixd["links"]
	for j in links.size():
		if j == li:
			continue
		var c: Curve3D = links[j]["c"]
		var p0 := Vector3(p.x, 0.0, p.z)
		var q := c.get_closest_point(p0)
		var dd := Vector2(p.x - q.x, p.z - q.z).length()
		var reach := HALF + margin + (partner_gap if j in ixd["partners"].get(li, []) else 0.0)
		if dd < reach:
			var yj := Track.elev_at(c, c.get_closest_offset(p0))
			if absf(yj - y) < 1.5:
				return j
	return -1


## Seite des Rings von einem Abtastpunkt aus: +1, wenn der Ring rechts des Wegs liegt
static func _ring_side(f: Dictionary) -> float:
	return signf((f["right"] as Vector3).dot(-(f["hr"] as Vector3) * signf(f["hlat"])))


## Fahrbahnen (Asphalt mit Markierung; wo sich zwei Wege überlappen, ohne), Füllflächen zur Ringfahrbahn mit
## Leitschwellen, Sperrflächen an den Gabelungen
static func _roads(job: Dictionary) -> void:
	var root: Node3D = job["root"]
	var ixd: Dictionary = job["ixd"]
	var links: Array = ixd["links"]
	var white := Builder.mat(Color(0.86, 0.86, 0.84), 0.0, 0.6, Color(0.9, 0.9, 0.88), 0.25)
	white.cull_mode = BaseMaterial3D.CULL_DISABLED
	var paint := SurfaceTool.new()
	paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gore := SurfaceTool.new()
	gore.begin(Mesh.PRIMITIVE_TRIANGLES)
	for li in links.size():
		var fr: Array = links[li]["f"]
		var road := SurfaceTool.new()
		road.begin(Mesh.PRIMITIVE_TRIANGLES)
		var pad := SurfaceTool.new()
		pad.begin(Mesh.PRIMITIVE_TRIANGLES)
		var nr := 0
		var np := 0
		for k in range(1, fr.size()):
			var a: Dictionary = fr[k - 1]
			var b: Dictionary = fr[k]
			var ya := Vector3(0, a["y"], 0)
			var yb := Vector3(0, b["y"], 0)
			var al: Vector3 = (a["pos"] as Vector3) - (a["right"] as Vector3) * HALF + ya
			var ar: Vector3 = (a["pos"] as Vector3) + (a["right"] as Vector3) * HALF + ya
			var bl: Vector3 = (b["pos"] as Vector3) - (b["right"] as Vector3) * HALF + yb
			var br: Vector3 = (b["pos"] as Vector3) + (b["right"] as Vector3) * HALF + yb
			var mid: Vector3 = ((a["pos"] as Vector3) + (b["pos"] as Vector3)) / 2.0
			var my: float = (float(a["y"]) + float(b["y"])) / 2.0
			# geteilt mit einem anderen Weg (Gabelung) oder in der Ringfahrbahn (Ende der Einfädelspur): ohne Markierung
			var shared := _other(ixd, li, mid, my, 0.0) >= 0 or (absf(float(a["hlat"])) < JOIN - 0.6 and my < 0.5)
			b["shared"] = shared
			if shared:
				var o := Vector3(0, 0.014 + 0.004 * li, 0)
				Track._strip(pad, al + o, ar + o, bl + o, br + o, a["d"], b["d"])
				np += 1
			else:
				Track._strip(road, al, ar, bl, br, a["d"], b["d"])
				nr += 1
			# Füllfläche zwischen Ringfahrbahn und Rampe (dort fehlt das Bankett des Rings), mit Leitschwellen
			var ha: float = a["hlat"]
			var hb: float = b["hlat"]
			var lim := RING_WALL + HALF + EDGE + 0.6  # bis zur Nase; dahinter Wiese zwischen Randwand und Rampe
			if float(a["y"]) < 0.3 and float(b["y"]) < 0.3 and absf(ha) > JOIN - 1.0 and absf(ha) < lim and absf(hb) < lim \
					and signf(ha) == signf(hb):
				var rs := _ring_side(a)
				var ea: Vector3 = (a["pos"] as Vector3) + (a["right"] as Vector3) * rs * HALF
				var eb: Vector3 = (b["pos"] as Vector3) + (b["right"] as Vector3) * rs * HALF
				var ga: Vector3 = (a["hp"] as Vector3) + (a["hr"] as Vector3) * signf(ha) * RING_HW
				var gb: Vector3 = (b["hp"] as Vector3) + (b["hr"] as Vector3) * signf(hb) * RING_HW
				var o2 := Vector3(0, 0.01, 0)
				if rs > 0.0:
					Track._strip(gore, ea + o2, ga + o2, eb + o2, gb + o2, a["d"], b["d"])
				else:
					Track._strip(gore, ga + o2, ea + o2, gb + o2, eb + o2, a["d"], b["d"])
				var gap := absf(ha) - HALF - RING_HW
				if gap > 0.8 and k % 3 == 0:
					var dirv: Vector3 = ((b["pos"] as Vector3) - (a["pos"] as Vector3)).normalized()
					_chevron(paint, ga, eb + dirv * 3.5, 0.03)
			if nr >= 30:
				Track._road_mesh(root, road, 2.0, HALF * 2.0, 0.0)
				road = SurfaceTool.new()
				road.begin(Mesh.PRIMITIVE_TRIANGLES)
				nr = 0
		if nr > 0:
			Track._road_mesh(root, road, 2.0, HALF * 2.0, 0.0)
		if np > 0:
			Track._road_mesh(root, pad, 0.0, HALF * 2.0, 0.0)
	# Sperrflächen an den Gabelungen (zwischen Partnern, bis GORE breit)
	for li in links.size():
		for pj in ixd["partners"].get(li, []):
			if pj > li:
				_gore(ixd, li, pj, paint, gore)
	Track._road_mesh(root, gore, 0.0, 6.0, 0.0)
	paint.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = paint.commit()
	mi.material_override = white
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## Leitschwelle (weißer Streifen, 0,6 m breit) von a nach b, y über der Fahrbahn
static func _chevron(st: SurfaceTool, a: Vector3, b: Vector3, y: float) -> void:
	var d := b - a
	d.y = 0.0
	if d.length() < 0.5:
		return
	var side := Vector3(-d.z, 0.0, d.x).normalized() * 0.2
	var o := Vector3(0, y, 0)
	for v in [a - side + o, b - side + o, b + side + o, a - side + o, b + side + o, a + side + o]:
		st.set_normal(Vector3.UP)
		st.add_vertex(v)


## Sperrfläche zwischen zwei auseinanderlaufenden Wegen li und pj: Asphalt ohne Markierung mit weißen Leitschwellen,
## an der Nase (Breite GORE + 0,8 m) beginnen die Schutzwände; merkt sich die Nase in ixd["noses"]
static func _gore(ixd: Dictionary, li: int, pj: int, paint: SurfaceTool, asphalt: SurfaceTool) -> void:
	var links: Array = ixd["links"]
	var fa: Array = links[li]["f"]
	var cb: Curve3D = links[pj]["c"]
	var prev := []
	for k in fa.size():
		var f: Dictionary = fa[k]
		var p: Vector3 = f["pos"]
		var q := cb.get_closest_point(p)
		var gap := Vector2(p.x - q.x, p.z - q.z).length() - 2.0 * HALF
		var y: float = f["y"]
		var yq := Track.elev_at(cb, cb.get_closest_offset(p))
		if absf(y - yq) > 1.5 or float(f["d"]) > 200.0:
			break
		if gap <= 0.05:
			prev = []
			continue
		var dirn: Vector3 = q - p
		dirn.y = 0.0
		dirn = dirn.normalized()
		var e1: Vector3 = p + dirn * HALF + Vector3(0, y, 0)
		var e2: Vector3 = q - dirn * HALF + Vector3(0, yq, 0)
		if not prev.is_empty():
			var o := Vector3(0, 0.012, 0)
			var rs := signf((f["right"] as Vector3).dot(dirn))
			if rs > 0.0:
				Track._strip(asphalt, prev[0] + o, prev[1] + o, e1 + o, e2 + o, prev[2], f["d"])
			else:
				Track._strip(asphalt, prev[1] + o, prev[0] + o, e2 + o, e1 + o, prev[2], f["d"])
		prev = [e1, e2, f["d"]]
		if gap >= GORE + 0.8:
			ixd["noses"].append({"a": e1, "b": e2, "dir": (f["fwd"] as Vector3)})
			break
		if k % 3 == 0 and gap > 0.6:
			_chevron(paint, e1, e2 + (f["fwd"] as Vector3) * 3.0, 0.03)


## Schutzwände (Beton, Kollision), auf Dämmen Stützmauern, Rückstrahler, Plätze für die Laternen
static func _edges(job: Dictionary) -> void:
	var root: Node3D = job["root"]
	var ixd: Dictionary = job["ixd"]
	var links: Array = ixd["links"]
	var walls: StaticBody3D = ixd["walls"]
	var conc := Builder.mat(Color(0.47, 0.47, 0.46), 0.0, 0.85)
	conc.cull_mode = BaseMaterial3D.CULL_DISABLED
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ret := SurfaceTool.new()
	ret.begin(Mesh.PRIMITIVE_TRIANGLES)
	var refl := []
	for li in links.size():
		var fr: Array = links[li]["f"]
		var on := {-1.0: [], 1.0: []}
		for side in [-1.0, 1.0]:
			for k in fr.size():
				var f: Dictionary = fr[k]
				var y: float = f["y"]
				var p: Vector3 = (f["pos"] as Vector3) + (f["right"] as Vector3) * side * (HALF + EDGE)
				var ok := _other(ixd, li, p, y, 0.2, GORE) < 0
				# zum Ring hin: an der Einmündung (im Bankett des Rings) keine Wand
				if ok and y < 1.0 and _ring_side(f) == side and absf(float(f["hlat"])) - HALF - EDGE < RING_WALL - 0.3:
					ok = false
				on[side].append(ok)
		for side in [-1.0, 1.0]:
			for k in range(1, fr.size()):
				if not (on[side][k] and on[side][k - 1]):
					continue
				var a: Dictionary = fr[k - 1]
				var b: Dictionary = fr[k]
				var oa: Vector3 = (a["right"] as Vector3) * side
				var ob: Vector3 = (b["right"] as Vector3) * side
				var pa: Vector3 = (a["pos"] as Vector3) + oa * (HALF + EDGE) + Vector3(0, a["y"], 0)
				var pb: Vector3 = (b["pos"] as Vector3) + ob * (HALF + EDGE) + Vector3(0, b["y"], 0)
				Track._wall_shape(walls, pa, pb)
				_barrier(st, pa, pb, oa, ob)
				var ya: float = a["y"]
				var yb: float = b["y"]
				if ya > 0.3 or yb > 0.3:
					# Stützmauer (Rampe) bzw. Gesims (Brücke) außen bündig mit der Schutzwand
					var wa := pa + oa * 0.3
					var wb := pb + ob * 0.3
					var bot_a := -0.15 if ya < DECK else ya - DECK_T
					var bot_b := -0.15 if yb < DECK else yb - DECK_T
					_wall_face(ret, Vector3(wa.x, bot_a, wa.z), Vector3(wb.x, bot_b, wb.z), ya, yb)
				if k % 6 == 0:
					refl.append(Transform3D(Basis.looking_at(b["fwd"], Vector3.UP), pb - ob * 0.02 + Vector3(0, 1.0, 0)))
		# Laternen: alle LAMP_STEP abwechselnd links und rechts, wo die Wand steht
		var since := LAMP_STEP * 0.5 + 11.0 * li
		var ls := 1.0 if li % 2 == 0 else -1.0
		for k in fr.size():
			since += STEP
			if since < LAMP_STEP:
				continue
			for s2 in [ls, -ls]:
				if on[s2][k]:
					ixd["lamps"].append([fr[k], s2])
					since = 0.0
					ls = -s2
					break
	_flush(root, st, conc)
	var ret_m := Builder.mat(Color(0.42, 0.42, 0.41), 0.0, 0.9)
	ret_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_flush(root, ret, ret_m)
	var rmat := Builder.mat(Color(1.0, 0.85, 0.5), 0.0, 0.4, Color(1.0, 0.7, 0.3), 2.5)
	Track._multi(root, Builder.box(Vector3(0.14, 0.09, 0.05)), rmat, refl)
	_closures(job, st)


## Betonschutzwand (New Jersey) von a nach b; oa, ob: nach außen. Fuß innen an der Fahrbahnkante, außen senkrecht.
static func _barrier(st: SurfaceTool, a: Vector3, b: Vector3, oa: Vector3, ob: Vector3) -> void:
	var prof := [Vector2(-0.6, 0.0), Vector2(-0.42, 0.3), Vector2(-0.16, 0.95), Vector2(0.08, 0.95), Vector2(0.3, 0.95), Vector2(0.3, -0.05)]
	for i in prof.size() - 1:
		var p0: Vector2 = prof[i]
		var p1: Vector2 = prof[i + 1]
		var a0 := a + oa * p0.x + Vector3(0, p0.y, 0)
		var a1 := a + oa * p1.x + Vector3(0, p1.y, 0)
		var b0 := b + ob * p0.x + Vector3(0, p0.y, 0)
		var b1 := b + ob * p1.x + Vector3(0, p1.y, 0)
		for v in [a0, b0, b1, a0, b1, a1]:
			st.add_vertex(v)


## Senkrechte Fläche: Fußpunkte a, b, oben bis zu den Höhen ha, hb
static func _wall_face(st: SurfaceTool, a: Vector3, b: Vector3, ha: float, hb: float) -> void:
	var at := Vector3(a.x, ha, a.z)
	var bt := Vector3(b.x, hb, b.z)
	for v in [a, b, bt, a, bt, at]:
		st.add_vertex(v)


static func _flush(root: Node3D, st: SurfaceTool, m: Material) -> void:
	st.generate_normals()
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	root.add_child(mi)


## Abschlusswände: am Abzweig von der Randwand des Stamms zur Außenwand von NR und NE, an den Enden der Rampen im Ring
## zur Randwand des Rings (wo sie wieder beginnt), und quer über die Nasen der Gabelungen mit Anpralldämpfer
static func _closures(job: Dictionary, st: SurfaceTool) -> void:
	var root: Node3D = job["root"]
	var ixd: Dictionary = job["ixd"]
	var links: Array = ixd["links"]
	var hc: Curve3D = ixd["hc"]
	var walls: StaticBody3D = ixd["walls"]
	var conc := Builder.mat(Color(0.47, 0.47, 0.46), 0.0, 0.85)
	conc.cull_mode = BaseMaterial3D.CULL_DISABLED
	var cst := SurfaceTool.new()
	cst.begin(Mesh.PRIMITIVE_TRIANGLES)
	var B0: Dictionary = links[0]["f"][0]
	var stem_wall := Track.HALF_W + Track.AB_EXTRA + Track.WALK + 0.3  # Stamm ohne Mittelstreifen am Ende
	for li in [1, 2]:
		var f0: Dictionary = links[li]["f"][0]
		var sd := signf(((f0["pos"] as Vector3) - (B0["pos"] as Vector3)).dot(B0["right"]))
		var a: Vector3 = (B0["pos"] as Vector3) + (B0["right"] as Vector3) * sd * stem_wall
		var b: Vector3 = (f0["pos"] as Vector3) + (f0["right"] as Vector3) * sd * (HALF + EDGE)
		Track._wall_shape(walls, a - (B0["fwd"] as Vector3) * 0.5, b)
		_barrier(cst, a, b, (B0["fwd"] as Vector3) * -1.0, (B0["fwd"] as Vector3) * -1.0)
	for li in range(1, links.size()):
		var fr: Array = links[li]["f"]
		var fe: Dictionary = fr[-1]
		var sgn := signf(fe["hlat"])
		var hr: Vector3 = fe["hr"]
		var outer: Vector3 = (fe["pos"] as Vector3) + hr * sgn * (HALF + EDGE)
		# der Ring baut seine Randwand erst, wo die Einmündung (Schlupfweg) mehr als 1 m entfernt ist
		var dir: float = signf(float(fe["hd"]) - float(fr[fr.size() - 6]["hd"]))
		var d: float = fe["hd"]
		var c: Curve3D = links[li]["c"]
		var wp := Vector3.ZERO
		for i in 60:
			d += dir
			var hf := Track.frame_at(hc, d)
			wp = (hf["pos"] as Vector3) + (hf["right"] as Vector3) * sgn * RING_WALL
			var q := c.get_closest_point(wp)
			if Vector2(wp.x - q.x, wp.z - q.z).length() - HALF > 1.2:
				break
		# ein Stück an der Randwand des Rings entlang (die beginnt erst am nächsten 3-m-Schritt)
		var hf2 := Track.frame_at(hc, d + dir * 9.0)
		var wp2: Vector3 = (hf2["pos"] as Vector3) + (hf2["right"] as Vector3) * sgn * RING_WALL
		Track._wall_shape(walls, outer, wp)
		Track._wall_shape(walls, wp, wp2)
		_barrier(cst, outer, wp, hr * sgn, hr * sgn)
		# Nase der Ausfahrt bzw. Einfahrt: wo Rampe und Randwand des Rings auseinandergehen, ein Anpralldämpfer
		for k in range(fr.size() - 1, 0, -1):
			var f: Dictionary = fr[k]
			if absf(float(f["hlat"])) > RING_WALL + HALF + EDGE + 0.4 and float(f["y"]) < 0.3:
				var na: Vector3 = (f["hp"] as Vector3) + (f["hr"] as Vector3) * sgn * RING_WALL
				var nb: Vector3 = (f["pos"] as Vector3) + (f["right"] as Vector3) * _ring_side(f) * (HALF + EDGE)
				# Dämpfer zeigt in die Sperrfläche (zur Einmündung hin, also in Richtung der späteren Punkte)
				var fwn: Vector3 = (fr[k - 1]["pos"] as Vector3) - (f["pos"] as Vector3)
				ixd["noses"].append({"a": na, "b": nb, "dir": fwn.normalized(), "ring": true})
				break
	# Nasen: quer zwischen den Schutzwänden, davor ein Anpralldämpfer (gelb-schwarz, man prallt ab wie an der Wand)
	var yel := Builder.mat(Color(1.0, 0.78, 0.05), 0.0, 0.5, Color(1.0, 0.7, 0.05), 0.4)
	var blk := Builder.mat(Color(0.05, 0.05, 0.05), 0.0, 0.6)
	var groups := {}
	for nz in ixd["noses"]:
		var a: Vector3 = nz["a"]
		var b: Vector3 = nz["b"]
		var fw: Vector3 = nz["dir"]
		fw.y = 0.0
		fw = fw.normalized()
		var mid := (a + b) / 2.0
		Track._wall_shape(walls, a, b, 3.0)
		var bas := Basis.looking_at(fw, Vector3.UP)
		for k in 6:
			Track._part(groups, yel if k % 2 == 0 else blk, Builder.box(Vector3(1.05, 0.95, 0.5)),
				Transform3D(bas, mid - fw * (0.3 + k * 0.52) + Vector3(0, 0.47, 0)))
		var tip := mid - fw * 3.3
		Track._wall_shape(walls, a, tip, 3.0)
		Track._wall_shape(walls, tip, b, 3.0)
	Track._bake(root, groups)
	_flush(root, cst, conc)


## Brückenplatten, Pfeiler, Widerlager
static func _structure(job: Dictionary) -> void:
	var root: Node3D = job["root"]
	var ixd: Dictionary = job["ixd"]
	var links: Array = ixd["links"]
	var deck_m := Builder.mat(Color(0.46, 0.46, 0.45), 0.0, 0.85)
	deck_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pil_m := Builder.mat(Color(0.44, 0.44, 0.43), 0.0, 0.88)
	var groups := {}
	var deck := SurfaceTool.new()
	deck.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pillars := []
	for li in links.size():
		var fr: Array = links[li]["f"]
		var since := PILLAR_STEP * 0.5
		for k in range(1, fr.size()):
			var a: Dictionary = fr[k - 1]
			var b: Dictionary = fr[k]
			var ya: float = a["y"]
			var yb: float = b["y"]
			if ya >= DECK - 0.01 and yb >= DECK - 0.01:
				# geteilte Stücke (Gabelung in der Luft): nur der erste Weg baut die Platte
				var mid: Vector3 = ((a["pos"] as Vector3) + (b["pos"] as Vector3)) / 2.0
				var oj := _other(ixd, li, mid, (ya + yb) / 2.0, -1.5)
				if oj < 0 or oj > li:
					var w := HALF + EDGE + 0.3
					var al: Vector3 = (a["pos"] as Vector3) - (a["right"] as Vector3) * w + Vector3(0, ya - DECK_T, 0)
					var ar: Vector3 = (a["pos"] as Vector3) + (a["right"] as Vector3) * w + Vector3(0, ya - DECK_T, 0)
					var bl: Vector3 = (b["pos"] as Vector3) - (b["right"] as Vector3) * w + Vector3(0, yb - DECK_T, 0)
					var br: Vector3 = (b["pos"] as Vector3) + (b["right"] as Vector3) * w + Vector3(0, yb - DECK_T, 0)
					Track._strip(deck, ar, al, br, bl, 0.0, 0.0)
				since += STEP
				if since >= PILLAR_STEP and yb >= DECK + 1.5:
					var pp: Vector3 = b["pos"]
					var ok := absf(float(b["hlat"])) > RING_WALL + 2.5
					for j in links.size():
						if j == li:
							continue
						var cj: Curve3D = links[j]["c"]
						var q := cj.get_closest_point(pp)
						if Vector2(pp.x - q.x, pp.z - q.z).length() < HALF + 2.5 and Track.elev_at(cj, cj.get_closest_offset(pp)) < yb - 2.0:
							ok = false
					for o in pillars:
						if (o as Vector3).distance_to(Vector3(pp.x, 0, pp.z)) < 14.0:
							ok = false
					if ok:
						since = 0.0
						pillars.append(Vector3(pp.x, 0, pp.z))
						var bas := Basis.looking_at(b["fwd"], Vector3.UP)
						var top := yb - DECK_T
						Track._part(groups, pil_m, Builder.tapered_box(Vector2(2.6, 1.9), Vector2(2.1, 1.5), top - 0.8, 0.0), Transform3D(bas, Vector3(pp.x, -0.2, pp.z)))
						Track._part(groups, pil_m, Builder.tapered_box(Vector2(2.4, 1.6), Vector2(2.0 * HALF - 0.5, 2.0), 1.2, 0.0), Transform3D(bas, Vector3(pp.x, top - 1.2, pp.z)))
						job["occupied"].append({"pos": Vector3(pp.x, 0, pp.z), "r": 2.0})
			elif (ya >= DECK) != (yb >= DECK):
				# Widerlager: Ende der Stützmauern, quer unter dem Beginn der Platte
				var f: Dictionary = b if yb >= DECK else a
				var bas2 := Basis.looking_at(f["fwd"], Vector3.UP)
				Track._part(groups, pil_m, Builder.box(Vector3(2.0 * (HALF + EDGE + 0.3), DECK, 1.4)), Transform3D(bas2, (f["pos"] as Vector3) + Vector3(0, DECK / 2.0 - 0.15, 0)))
	_flush(root, deck, deck_m)
	Track._bake(root, groups)


## Laternen auf den Schutzwänden, Wegweiser
static func _furniture(job: Dictionary) -> void:
	var root: Node3D = job["root"]
	var ixd: Dictionary = job["ixd"]
	var pole := Builder.mat(Color(0.22, 0.22, 0.24), 0.6, 0.4)
	var lc := Color(1.0, 0.62, 0.3)
	var head := Builder.mat(lc, 0.0, 0.3, lc, 3.0)
	var groups := {}
	for l in ixd["lamps"]:
		var f: Dictionary = l[0]
		var side: float = l[1]
		var y: float = f["y"]
		var out: Vector3 = (f["right"] as Vector3) * side
		var base: Vector3 = (f["pos"] as Vector3) + out * (HALF + EDGE + 0.1) + Vector3(0, y + 0.95, 0)
		var bas := Basis.looking_at(-out, Vector3.UP)
		var h := 8.0
		Track._part(groups, pole, Builder.box(Vector3(0.22, h, 0.22)), Transform3D(bas, base + Vector3(0, h / 2.0, 0)))
		Track._part(groups, pole, Builder.box(Vector3(0.13, 0.13, 2.6)), Transform3D(bas, base + Vector3(0, h, 0) - out * 1.2))
		Track._part(groups, head, Builder.box(Vector3(0.45, 0.14, 0.9)), Transform3D(bas, base + Vector3(0, h - 0.08, 0) - out * 2.4))
		var light := OmniLight3D.new()
		light.light_color = lc
		light.light_energy = 2.4
		light.omni_range = 22.0
		light.omni_attenuation = 1.2
		light.position = base + Vector3(0, h - 0.6, 0) - out * 2.4
		root.add_child(light)
	Track._bake(root, groups)
	for s in (job["race"].get("signs", []) as Array):
		_sign_bridge(root, job, s)


## Blauer Wegweiser über einer Fahrbahn (wie auf deutschen Autobahnen). s: pos (Mitte der Straße), fwd (Fahrtrichtung
## der Leser), posts (Masten quer, + rechts aus Sicht der Leser), span (Riegel von, bis), panels: [quer, Text,
## Untertext, Pfeil ("unten" Spur geradeaus, "rechts" Ausfahrt), Breite]
static func _sign_bridge(root: Node3D, job: Dictionary, s: Dictionary) -> void:
	var steel := Builder.mat(Color(0.45, 0.46, 0.48), 0.8, 0.35)
	var blue := Builder.mat(Color(0.0, 0.2, 0.52), 0.1, 0.4, Color(0.0, 0.2, 0.52), 0.35)
	var white := Builder.mat(Color(0.9, 0.9, 0.9), 0.0, 0.4, Color(1, 1, 1), 0.6)
	var lamp := Builder.mat(Color(1, 1, 0.9), 0.0, 0.3, Color(1, 0.95, 0.8), 4.0)
	var fwd: Vector3 = s["fwd"]
	fwd.y = 0.0
	fwd = fwd.normalized()
	# lokal: -Z in Fahrtrichtung, +Z zu den Lesern, +X rechts aus ihrer Sicht
	var xf := Transform3D(Basis.looking_at(fwd, Vector3.UP), s["pos"])
	var g := {}
	var y0 := 6.2
	for px in s["posts"]:
		Track._part(g, steel, Builder.box(Vector3(0.45, y0 + 2.4, 0.45)), Transform3D(Basis(), Vector3(px, (y0 + 2.4) / 2.0, 0)))
		job["occupied"].append({"pos": xf * Vector3(px, 0, 0), "r": 1.0})
	var x_a: float = s["span"][0]
	var x_b: float = s["span"][1]
	for yy in [y0 + 0.25, y0 + 2.15]:
		Track._part(g, steel, Builder.box(Vector3(absf(x_b - x_a) + 0.5, 0.28, 0.28)), Transform3D(Basis(), Vector3((x_a + x_b) / 2.0, yy, 0)))
	for pn in s["panels"]:
		var x: float = pn[0]
		var w: float = pn[4]
		Track._part(g, white, Builder.box(Vector3(w + 0.2, 2.7, 0.1)), Transform3D(Basis(), Vector3(x, y0 + 1.2, 0.22)))
		Track._part(g, blue, Builder.box(Vector3(w, 2.5, 0.1)), Transform3D(Basis(), Vector3(x, y0 + 1.2, 0.28)))
		for lx in [-w * 0.3, w * 0.3]:
			Track._part(g, lamp, Builder.box(Vector3(0.5, 0.1, 0.3)), Transform3D(Basis(), Vector3(x + lx, y0 + 2.6, 0.55)))
		var arrow: String = pn[3]
		var ax := w / 2.0 - 0.95
		var l := Label3D.new()
		l.text = pn[1]
		l.font_size = 48
		l.pixel_size = 0.02
		var tw := ThemeDB.fallback_font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 48).x * 0.02
		if tw > w - 2.6:
			l.pixel_size *= (w - 2.6) / tw
		l.modulate = Color(1.6, 1.6, 1.6)
		l.shaded = false
		l.double_sided = false
		l.transform = xf * Transform3D(Basis(), Vector3(x - 0.6, y0 + 1.5, 0.35))
		root.add_child(l)
		if str(pn[2]) != "":
			var sl := Label3D.new()
			sl.text = pn[2]
			sl.font_size = 26
			sl.pixel_size = 0.02
			var sw := ThemeDB.fallback_font.get_string_size(sl.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x * 0.02
			if sw > w - 2.6:
				sl.pixel_size *= (w - 2.6) / sw
			sl.modulate = Color(1.5, 1.5, 1.5)
			sl.shaded = false
			sl.double_sided = false
			sl.transform = xf * Transform3D(Basis(), Vector3(x - 0.6, y0 + 0.6, 0.35))
			root.add_child(sl)
		var aq := QuadMesh.new()
		aq.size = Vector2(1.3, 1.3)
		var ai := MeshInstance3D.new()
		ai.mesh = aq
		var rot := Basis()
		var icon := "pfeil_unten"
		if arrow == "rechts":
			icon = "pfeil_rechts"
			rot = Basis(Vector3.BACK, deg_to_rad(40.0))  # schräg nach rechts oben: Ausfahrt
		ai.material_override = SignIcons.material(icon, Color(1.6, 1.6, 1.6))
		ai.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ai.transform = xf * Transform3D(rot, Vector3(x + ax, y0 + 1.2, 0.35))
		root.add_child(ai)
	Track._bake(root, g, xf)


# --- Talbrücken des Rings (seit 2.36) ---------------------------------------------------------------------------------

const VIA_MIN := 5.5  # ab dieser Höhe steht der Ring auf Pfeilern (wie track_builder._in_viaduct), darunter Damm
const VIA_DECK := 2.2  # Dicke der Platte
const VIA_PIER := 46.0  # Abstand der Pfeiler

## Talbrücke: Platte unter Fahrbahn und Bankett mit Gesims, Doppelpfeiler (je einer unter jeder Richtungsfahrbahn),
## Widerlager, wo der Damm endet. track["viaducts"]: [von, bis] in Metern der Hauptstraße (track_builder._plan_autobahn)
static func viaducts(root: Node3D, track: Dictionary) -> void:
	var curve: Curve3D = track["curve"]
	var deck_m := Builder.mat(Color(0.46, 0.46, 0.45), 0.0, 0.85)
	deck_m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pil_m := Builder.mat(Color(0.43, 0.43, 0.42), 0.0, 0.88)
	var groups := {}
	var deck := SurfaceTool.new()
	deck.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n_deck := 0
	for v in track["viaducts"]:
		var d: float = v[0]
		var since := VIA_PIER * 0.5
		var prev := {}
		while d <= float(v[1]):
			var f := Track.frame_at(curve, d)
			var y: float = f["y"]
			var r: Vector3 = f["right"]
			var w: float = Track.hw(track, d) + Track.WALK + 0.6
			var base: Vector3 = f["pos"]
			var cur := {"l": base - r * w + Vector3(0, y - VIA_DECK, 0), "r": base + r * w + Vector3(0, y - VIA_DECK, 0), "y": y}
			if not prev.is_empty():
				var py: float = prev["y"]
				if y > VIA_MIN and py > VIA_MIN:
					Track._strip(deck, prev["r"], prev["l"], cur["r"], cur["l"], 0.0, 0.0)
					for sd in ["l", "r"]:
						var a: Vector3 = prev[sd]
						var b: Vector3 = cur[sd]
						var top_a := py + Track.CURB_H + 0.1
						var top_b := y + Track.CURB_H + 0.1
						_wall_face(deck, a, b, top_a, top_b)
					n_deck += 1
					since += 3.0
					if since >= VIA_PIER and y > VIA_MIN + 1.5:
						since = 0.0
						var bas := Basis.looking_at(f["fwd"], Vector3.UP)
						var hw: float = Track.hw(track, d)
						for sd2 in [-1.0, 1.0]:
							var pp: Vector3 = base + r * sd2 * hw * 0.5
							var top := y - VIA_DECK - 1.2
							Track._part(groups, pil_m, Builder.tapered_box(Vector2(3.4, 2.4), Vector2(2.6, 1.9), top + 0.8, 0.0),
								Transform3D(bas, Vector3(pp.x, -0.8, pp.z)))
							Track._part(groups, pil_m, Builder.tapered_box(Vector2(3.0, 2.0), Vector2(hw * 0.95, 2.4), 1.2, 0.0),
								Transform3D(bas, Vector3(pp.x, top, pp.z)))
				elif (y > VIA_MIN) != (py > VIA_MIN):
					# Widerlager: der Damm endet an einer Betonwand über seine ganze Breite
					var bas3 := Basis.looking_at(f["fwd"], Vector3.UP)
					var wa := w + VIA_MIN * 1.6
					Track._part(groups, pil_m, Builder.tapered_box(Vector2(wa * 2.0, 1.6), Vector2(w * 2.0, 1.6), VIA_MIN + 0.3, 0.0),
						Transform3D(bas3, base + Vector3(0, -0.2, 0)))
			prev = cur
			d += 3.0
	if n_deck > 0:
		_flush(root, deck, deck_m)
	Track._bake(root, groups)
