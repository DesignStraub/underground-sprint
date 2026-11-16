extends RefCounted
## Open World "Mini-Deutschland": alle Strecken (ohne Drag) liegen außen an einem Autobahnring, ungefähr in der
## Himmelsrichtung ihrer Stadt (vom Mittelpunkt Deutschlands aus gesehen). Jede Stadt hat eine Ausfahrt
## (track_builder._plan_world_exit), die zum Ring zeigt; eine gerade Auffahrt verbindet sie mit der Autobahn.
## Der Ring besteht aus Stücken von gut 2,5 km, die wie Strecken gebaut und nachgeladen werden.
##
## Ergebnis (build()): {"cities": [{race_index, race, xf, center, radius, exit_world, start_world}],
##   "segments": [{race, center, radius}], "ring_r"}; alles in Weltkoordinaten (Meter, y = 0).
## Seit 2.36 münden Querspangen und Spangen, wo Platz ist, über Autobahndreiecke in die Ringe ("ixs", Stücke vom Typ
## "dreieck", scripts/interchange.gd); manche lange Kuppe ist eine Talbrücke über einem See ("vlakes"), manche Strecke
## über Land ein Einschnitt ("cuts", landscape.gd). --noix: Welt ohne all das (Vergleich).

const Catalog := preload("res://scripts/catalog.gd")
const Track := preload("res://scripts/track_builder.gd")
const Interchange := preload("res://scripts/interchange.gd")
const Offroad := preload("res://scripts/offroad.gd")  # Gelände zum Austoben (seit 2.39)
const CityFill := preload("res://scripts/city_fill.gd")  # Stadtfüllung hinter der Straßenfront (seit 2.39)

const GEO_CENTER := Vector2(10.4, 51.1)  # Länge, Breite: ungefähr die Mitte Deutschlands
const GAP_MIN := 150.0  # Mittellinie Autobahn bis Ausfahrt der Stadt (Platz für Lärmschutzwand und Häuser am Ring)
const SIDE_MARGIN := 140.0  # seitlicher Abstand zwischen Städten am Ring (Häuser stehen bis gut 60 m neben der Straße)
const SEG_LEN := 2600.0
const RING_STEP := 80.0
const MOOD := "mitternacht"

static var _cache := {}


## Rennen, die in der Welt liegen (Drag ist seit 2.24 draußen)
static func world_races() -> Array:
	var out := []
	for i in Catalog.RACES.size():
		if Catalog.RACES[i].get("type", "sprint") != "drag":
			out.append(i)
	return out


## Rennen als Welt-Strecke (mit Ausfahrt, Lage in der Welt)
static func world_race(i: int, xf := Transform3D.IDENTITY) -> Dictionary:
	var r: Dictionary = Catalog.RACES[i].duplicate()
	r["world"] = true
	r["xf"] = xf
	return r


static func build() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var t0 := Time.get_ticks_msec()
	var cities := []
	for i in world_races():
		var job := Track.begin(world_race(i))
		var tr: Dictionary = job["track"]
		(job["root"] as Node).free()
		if OS.get_cmdline_user_args().has("--crosslog"):
			print("CROSS %-28s crossing_d=%.0f L=%.0f" % [Catalog.RACES[i]["name"], tr["crossing_d"], tr["length"]])
		var ex: Dictionary = tr["world_exit"]
		if ex.is_empty():
			push_warning("Welt: Strecke %d ohne Ausfahrt" % i)
			continue
		# Kanonische Lage: Ausfahrt im Ursprung, Richtung von der Stadt weg = -Z (zum Ring), Stadt liegt bei +Z
		var dir: Vector3 = ex["dir"]
		var yaw := atan2(dir.x, dir.z) - PI  # Drehung, die dir auf (0, 0, -1) bringt
		var b0 := Basis(Vector3.UP, -yaw)
		var pts := []
		var polys := []  # für die Karten: [Punkte alle 8 m (Streckenkoordinaten), Art 0 Haupt / 1 Abzweig / 2 Sackgasse]
		for p in tr["paths"]:
			var bp: PackedVector3Array = (p["curve"] as Curve3D).get_baked_points()
			for k in range(0, bp.size(), 15):
				pts.append(b0 * (bp[k] - ex["end"]))
			var pl := PackedVector3Array()
			for k in range(0, bp.size(), 8):
				pl.append(bp[k])
			pl.append(bp[bp.size() - 1])
			if p["kind"] == "main" and tr["loop"]:
				pl.append(bp[0])
			polys.append([pl, 0 if p["kind"] == "main" else (2 if p["kind"] == "spur" else 1)])
		var lat0 := 1e9
		var lat1 := -1e9
		var rad0 := 0.0
		var far := 0.0
		for q in pts:
			# kanonisch +X zeigt in der Welt gegen die Drehrichtung des Rings: Seitenlage gespiegelt
			lat0 = minf(lat0, -q.x)
			lat1 = maxf(lat1, -q.x)
			rad0 = minf(rad0, q.z)
			far = maxf(far, q.z)
		var geo: Vector2 = Catalog.RACES[i]["geo"]
		var gx := (geo.y - GEO_CENTER.x) * cos(deg_to_rad(geo.x))
		var gz := -(geo.x - GEO_CENTER.y)
		cities.append({"race_index": i, "b0": b0, "end_local": ex["end"], "lat0": lat0 - SIDE_MARGIN / 2.0,
			"lat1": lat1 + SIDE_MARGIN / 2.0, "gap": maxf(GAP_MIN, -rad0 + 160.0), "far": far,
			"phi": atan2(gz, gx) + i * 1e-4, "start_local": Track.frame_at(tr["curve"], tr["start"])["pos"], "polys_local": polys,
			"holes_local": Track.ground_holes(tr), "bld_local": _building_points(tr),
			"exit2_local": tr["world_exit2"], "hills_local": tr.get("hills", [])})
		# Stadtfüllung (seit 2.39): Planung aufheben, die Blöcke kommen nach den Sperrflächen (fill_world)
		if CityFill.wanted(tr, world_race(i)):
			cities[-1]["plan_track"] = tr
	cities.sort_custom(func(a, b): return a["phi"] < b["phi"])
	# Platz am Ring: zwischen zwei Nachbarn rechte Kante des einen + linke Kante des anderen (am Ring gemessen)
	var n := cities.size()
	var need := []
	var total := 0.0
	for k in n:
		var a: Dictionary = cities[k]
		var b: Dictionary = cities[(k + 1) % n]
		var s: float = a["lat1"] - b["lat0"]
		need.append(s)
		total += s
	# Ring etwas größer als nötig: der Spielraum rückt jede Stadt möglichst nah an ihre echte Himmelsrichtung
	var R := maxf(total / TAU * 1.18, 2500.0)
	var x := []
	for k in n:
		x.append(float(cities[k]["phi"]))
	for it in 400:
		if it < 250:
			for k in n:
				x[k] += (float(cities[k]["phi"]) - x[k]) * 0.04
		for k in n:
			var k2 := (k + 1) % n
			var gap: float = (x[k2] + (TAU if k2 == 0 else 0.0)) - x[k]
			var mn: float = need[k] / R
			if gap < mn:
				var push := (mn - gap) / 2.0
				x[k] -= push
				x[k2] += push
	for k in n:
		cities[k]["phi_w"] = x[k]
	# Ring: Kreis mit sanften Wellen (sieht nicht wie mit dem Zirkel gezogen aus)
	var ring := []
	var m := int(TAU * R / RING_STEP)
	for k in m:
		var a := TAU * k / m
		var rr := R + 45.0 * sin(a * 3.0 + 0.7) + 30.0 * sin(a * 7.0 + 2.1)
		ring.append(Vector3(cos(a) * rr, 0.0, sin(a) * rr))
	# Städte setzen: Ausfahrt zeigt zur Autobahn, Stadt liegt außen
	var ramps := []
	for c in cities:
		var a: float = c["phi_w"]
		var k := int(round(a / TAU * m)) % m
		if k < 0:
			k += m
		var rp: Vector3 = ring[k]
		var N := Vector3(rp.x, 0.0, rp.z).normalized()
		# kanonisch: Stadt bei +Z, Ring bei -Z. Welt: +Z -> N
		var yaw_w := atan2(N.x, N.z)
		var basis: Basis = Basis(Vector3.UP, yaw_w) * c["b0"]
		var exit_w: Vector3 = rp + N * c["gap"]
		var xf := Transform3D(basis, exit_w - basis * c["end_local"])
		c["xf"] = xf
		# Hügel der Stadt (Weinberge, Wald) in Weltkoordinaten: dort kein Autobahndreieck (seit 2.36)
		c["hills_world"] = []
		for hl in c["hills_local"]:
			var hw3: Vector3 = xf * Vector3(hl["c"].x, 0.0, hl["c"].y)
			c["hills_world"].append([Vector2(hw3.x, hw3.z), float(hl["r"])])
		c["ring_k"] = k
		c["exit_world"] = exit_w
		c["start_world"] = xf * c["start_local"]
		c["race"] = world_race(c["race_index"], xf)
		c["race"]["no_ground"] = true  # Boden kommt von der Landschaft (Stadtmaske), kein hartes Quadrat in den Feldern
		c["roads"] = []
		for pl in c["polys_local"]:
			var w2 := PackedVector2Array()
			for q in pl[0]:
				var wq: Vector3 = xf * q
				w2.append(Vector2(wq.x, wq.z))
			c["roads"].append([w2, pl[1]])
		# Umkreis aus allen Wegen der Stadt (seit 2.33): vorher lag die Mitte auf der Achse Ring-Ausfahrt, und die zweite
		# Ausfahrt langer Sprints (Bad Kissingen, Rostock) lag über 800 m außerhalb; kam man dort an, war die Stadt nicht
		# geladen (Straße endete im Leeren)
		var lo := Vector2(1e9, 1e9)
		var hi := Vector2(-1e9, -1e9)
		for rd in c["roads"]:
			for q in rd[0]:
				lo = lo.min(q)
				hi = hi.max(q)
		var mid2 := (lo + hi) / 2.0
		var reach2 := 0.0
		for rd in c["roads"]:
			for q in rd[0]:
				reach2 = maxf(reach2, (q as Vector2).distance_to(mid2))
		c["center"] = Vector3(mid2.x, 0.0, mid2.y)
		c["radius"] = reach2 + 200.0
		var bw := PackedVector2Array()
		for q in c["bld_local"]:
			var wq: Vector3 = xf * Vector3(q.x, 0.0, q.y)
			bw.append(Vector2(wq.x, wq.z))
		c["bld_world"] = bw
		ramps.append({"k": k, "from": rp, "end": exit_w, "name": Catalog.RACES[c["race_index"]].get("town", ""),
			"forest": Catalog.RACES[c["race_index"]].get("forest", false), "zone": ramp_zone(c["race_index"])})
	# Außenring um alle Städte und zweite Ausfahrten der Sprints (hinter dem Ziel) an einen der beiden Ringe
	# Mitte: Kreisel mit vier Diagonalen zum inneren Ring (Querverbindungen durch die Mitte), vor den Ziel-Ausfahrten
	# geplant, damit die ihnen am Ring ausweichen
	var mid := _plan_middle(ring, ramps)
	var oring := _outer_ring(cities, R)
	var oramps := []
	_connect_ends(cities, ring, oring, ramps, oramps)
	# Spangen zwischen innerem und äußerem Ring durch die Lücken zwischen den Städten (seit 2.31): mehr Wege, nicht
	# nur rundherum
	var spokes := _plan_spokes(cities, ring, oring, ramps, oramps)
	# Autobahndreiecke (seit 2.36): wo Platz ist, münden Querspangen und Spangen über eine Brücke und vier Rampen in die
	# Ringe statt flach quer (scripts/interchange.gd); kürzt die Stämme und nimmt ihre flachen Auffahrten heraus
	var ixs := _plan_interchanges(cities, ring, oring, ramps, oramps, mid, spokes)
	for c in cities:
		if not (c["exit2_local"] as Dictionary).is_empty() and not c.has("exit2_ring"):
			if Catalog.RACES[c["race_index"]]["type"] in ["circuit", "drift"]:
				c["race"]["no_exit2"] = true  # Rundkurs: zweite Ausfahrt ohne Weg zum Ring, dann gibt es sie nicht
			else:
				c["race"]["tail_join"] = true  # Ziel eingeschlossen: die Straße dahinter führt zurück auf die Strecke
	# Nähte der Ringe nicht unter der Brücke eines Dreiecks (Schlupfwege und Zonen hängen an jedem Stück, das sie berühren)
	var avoid := [{}, {}]
	for j in ixs:
		var mm: int = (ring if j["host"] == 0 else oring).size()
		for dk in range(-3, 4):
			avoid[j["host"]][posmod(int(j["kr"]) + dk, mm)] = true
	var segments := _split(ring, ramps, 9000, 0, "", avoid[0])
	var osegs := _split(oring, oramps, 9500, 1, "", avoid[1])
	_ix_attach(ixs, segments, ring.size(), 0)
	_ix_attach(ixs, osegs, oring.size(), 1)
	segments.append_array(osegs)
	var msegs := _split(mid["rb"], mid["rb_ramps"], 9800, 2, "Kreisel")
	for i in mid["arms"].size():
		msegs.append_array(_split_open(mid["arms"][i], 9900 + i * 50, 3 + i, "Querspange"))
	for i in spokes.size():
		msegs.append_array(_split_open(spokes[i], 9600 + i * 50, 3 + mid["arms"].size() + i, "Spange"))
	segments.append_array(msegs)
	# Autobahn über Land, Stadt nur um die Auffahrten der Städte und am Kreisel (seit 2.29; davor säumten Hochhäuser
	# die ganze Autobahn, und die Welt sah überall gleich aus). Die Landschaft (landscape.gd) fragt dasselbe ab.
	var urban := []
	var zones := []  # Viertel am Ring je Auffahrt (ramp_zone)
	for r in ramps + oramps:
		if not r.get("wide", false) and not r.get("forest", false):
			urban.append(r["from"])
			zones.append(r.get("zone", "highway"))
	var rbc := Vector3.ZERO
	for q in mid["rb"]:
		rbc += q / float(mid["rb"].size())
	urban.append(rbc)
	zones.append("highway")
	var quiet := []  # um die Dreiecke Land (keine Häuser, Lärmschutzwände, Straßenbrücken an den Rampen)
	for j in ixs:
		quiet.append([j["J"], j["reach"]])
	for sg in segments:
		sg["race"]["district_seq"] = _district_seq(sg["race"]["pts"], urban, rbc, zones, quiet)
		sg["race"]["no_ground"] = true
		if sg.get("ring", 0) <= 1:
			_ring_crests(sg)
	# Talbrücken (seit 2.36): manche lange Kuppe der Ringe wird eine hohe Brücke über einen See
	var vlakes := _plan_viaducts(segments, cities, ramps + oramps)
	# Einschnitte (seit 2.36): mal niedriger, der Ring läuft zwischen Böschungen, ein Feldweg führt darüber
	var cuts := _plan_cuts(segments)
	# die Dreiecke selbst: eigene Stücke (nach den Ringen und der Mitte)
	var ix_ring0 := 3 + (mid["arms"] as Array).size() + spokes.size()
	for ni in ixs.size():
		var jx: Dictionary = ixs[ni]
		segments.append({"race": jx["race"], "center": jx["center"], "radius": jx["radius"], "ring": ix_ring0 + ni})
	# Straßen für die Karten (Weltkoordinaten x, z): Ring, Auffahrten, alle Wege der Städte
	var roads := []
	var rl := PackedVector2Array()
	for q in ring:
		rl.append(Vector2(q.x, q.z))
	rl.append(rl[0])
	roads.append([rl, 0])
	var orl := PackedVector2Array()
	for q in oring:
		orl.append(Vector2(q.x, q.z))
	orl.append(orl[0])
	roads.append([orl, 0])
	for line in [mid["rb"] + [mid["rb"][0]]] + mid["arms"] + spokes:
		var ml := PackedVector2Array()
		for q in line:
			ml.append(Vector2(q.x, q.z))
		roads.append([ml, 0])
	var ramp_lines := []  # nur die Auffahrten (für die Baumreihen der Landschaft)
	for r in ramps + oramps + mid["rb_ramps"]:
		var rp2 := PackedVector2Array()
		for q in _ramp_pts(r):
			rp2.append(Vector2(q.x, q.z))
		roads.append([rp2, 1])
		ramp_lines.append(rp2)
	for c in cities:
		roads.append_array(c["roads"])
	var ix_lines := []  # Wege der Dreiecke: auf die Karten, und die Städte bauen nicht darauf
	for j in ixs:
		for lk in j["race"]["links"]:
			var lp: Array = lk["pts"]
			var l2 := PackedVector2Array()
			for k in range(0, lp.size(), 2):
				l2.append(Vector2(lp[k].x, lp[k].z))
			l2.append(Vector2(lp[-1].x, lp[-1].z))
			roads.append([l2, 1])
			ix_lines.append(lp)
	_add_keepout(cities, ring, ramps + oramps, oring, osegs, ix_lines, spokes)
	_middle_keepout(msegs, ring, mid)
	# Gelände zum Austoben (seit 2.39, offroad.gd): Golfplatz und Kiesgrube an der nördlichen Querspange, je mit eigener
	# Ausfahrt (race["ramps"] des Stücks) und als Sperrfläche für Häuser; Ausfahrt auf die Karten und in die flache Zone
	var offroad := [] if OS.get_cmdline_user_args().has("--nooffroad") else Offroad.plan(segments)
	for a in offroad:
		roads.append([a["access"], 1])
	# Löcher im Boden (Tunneltröge, Flussbetten) aller Städte in Weltkoordinaten an jede Strecke: ihr Boden darf sie
	# nicht zudecken, auch nicht den Trog der Nachbarstadt
	var holes := PackedVector3Array()
	for c in cities:
		var cx: Transform3D = c["xf"]
		for h in c["holes_local"]:
			var w: Vector3 = cx * Vector3(h.x, 0.0, h.y)
			holes.append(Vector3(w.x, w.z, h.z))
	for c in cities:
		c["race"]["world_holes"] = holes
	for sg in segments:
		sg["race"]["world_holes"] = holes
	# Stadtfüllung (seit 2.39, city_fill.gd): Blöcke hinter der Straßenfront der erfundenen Städte schon hier planen
	# (mit Sperrflächen und Löchern der Nachbarn), damit die Landschaft dort flach bleibt und Stadtboden hat
	var tf := Time.get_ticks_msec()
	for c in cities:
		if c.has("plan_track"):
			var ptr: Dictionary = c["plan_track"]
			ptr["keepout"] = c["race"]["keepout"]
			ptr["world_holes"] = holes
			ptr["xf"] = c["xf"]
			c["fill_world"] = CityFill.world_points(ptr, int(c["race"]["seed"]), c["xf"])
			c.erase("plan_track")
	if OS.get_cmdline_user_args().has("--worldlog"):
		print("WELT Stadtfüllung geplant in %d ms" % (Time.get_ticks_msec() - tf))
	_cache = {"cities": cities, "segments": segments, "ring_r": R, "ring": ring, "oring": oring, "roads": roads, "holes": holes,
		"urban": urban, "center": rbc, "ramp_lines": ramp_lines, "ixs": ixs, "vlakes": vlakes, "cuts": cuts, "offroad": offroad}
	if OS.get_cmdline_user_args().has("--worldlog"):
		for j in ixs:
			var jp: Vector3 = j["J"]
			print("WELT %-30s Ring %d bei (%.0f, %.0f) Brücke %.1f m, Rampen %s" % [j["race"]["name"], j["host"], jp.x, jp.z,
				j["h"], ", ".join(j["race"]["links"].map(func(l): return "%s %.0f m" % [l["name"], Interchange.smooth_curve(l["pts"]).get_baked_length()]))])
		for msg in _ix_log:
			print(msg)
		for vl in vlakes:
			print("WELT Talbrücke %.1f m über einem See (r %.0f m) bei (%.0f, %.0f)" % [vl["h"], vl["r"], vl["pos"].x, vl["pos"].y])
		for ct in cuts:
			var cp: Vector3 = ct["pts"][ct["pts"].size() / 2]
			print("WELT Einschnitt %.1f m tief, %.0f m lang, bei (%.0f, %.0f)" % [ct["h"], (ct["pts"].size() - 1) * 10.0, cp.x, cp.z])
		var olen := 0.0
		for k in oring.size():
			olen += (oring[k] as Vector3).distance_to(oring[(k + 1) % oring.size()])
		print("WELT Ring %.0f m (Umfang %.1f km), Außenring %.1f km, %d Städte, %d Stücke, Planung %d ms" % [R, TAU * R / 1000.0,
			olen / 1000.0, cities.size(), segments.size(), Time.get_ticks_msec() - t0])
		for c in cities:
			if not c["exit2_local"].is_empty():
				print("  zweite Ausfahrt %-24s -> %s" % [Catalog.RACES[c["race_index"]]["name"],
					["innerer Ring", "Außenring"][c["exit2_ring"]] if c.has("exit2_ring") else ("entfällt (kein Weg)" if c["race"].get("no_exit2", false) else "zurück auf die eigene Strecke")])
		for c in cities:
			print("  %-28s phi=%.2f gap=%.0f breite=%.0f tiefe=%.0f" % [Catalog.RACES[c["race_index"]]["name"], c["phi_w"], c["gap"],
				c["lat1"] - c["lat0"], c["far"]])
	return _cache


## Echte Städte (OpenStreetMap): Lage der Häuser (jedes zweite, Streckenkoordinaten x, z). Die Landschaft hält dort
## den Boden flach und färbt ihn als Stadt (seit 2.30; davor lagen zwischen Häusern weit weg von der Strecke Wiesen
## und Hänge mitten in Aachen)
static func _building_points(tr: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	var data: Array = tr["city"].get("buildings", []) if tr["city"] is Dictionary else []
	for i in range(0, data.size(), 12):
		out.append(Vector2(data[i], data[i + 1]))
	return out


const CENTER_R := 750.0  # Stadt in der Kartenmitte (um den Kreisel): Innenstadt statt Schnellstraße
const CENTER_NAME := "Erfurt"  # Landeshauptstadt nahe dem Mittelpunkt Deutschlands
const URBAN_R := 420.0  # so weit um eine Auffahrt (und um den Kreisel) ist die Autobahn Stadt


## Viertel am Ring vor einer Stadt (seit 2.33): Großstädte Hochhäuser ("highway"), Hafenstädte Hallen und Kräne
## ("hafen_ab"), kleinere und echte Orts-Städte niedrige Häuser mit Ziegeldach ("ortsrand_de"). Vorher stand vor jeder
## Stadt dieselbe Hochhausschlucht, auch vor Fachwerk und Hafen.
static func ramp_zone(i: int) -> String:
	var r: Dictionary = Catalog.RACES[i]
	var name: String = r.get("name", "")
	if name.begins_with("Hafen"):
		return "hafen_ab"
	if r.has("city") and str(r.get("town", "")) != "Berlin":
		return "ortsrand_de"
	if str(r.get("town", "")) in ["Heidelberg"]:
		return "ortsrand_de"
	return "highway"


## Viertel je 400 m eines Autobahnstücks: das Viertel der nächsten Auffahrt (Stadt) in deren Nähe, sonst "land"
static func _district_seq(pts: Array, urban: Array, center := Vector3(1e9, 0, 1e9), zones := [], quiet := []) -> Array:
	var seq := []
	var acc := 0.0
	var next := 200.0  # Mitte des ersten Abschnitts
	for k in pts.size() - 1:
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[k + 1]
		var l := a.distance_to(b)
		while next <= acc + l:
			var q := a.lerp(b, (next - acc) / maxf(l, 0.001))
			var calm := false  # an einem Autobahndreieck: Land (seine Rampen liegen dort, wo sonst Häuser stünden)
			for qz in quiet:
				if Vector2(q.x - qz[0].x, q.z - qz[0].z).length() < float(qz[1]):
					calm = true
			if calm:
				seq.append("land")
			elif Vector2(q.x - center.x, q.z - center.z).length() < CENTER_R:
				seq.append(["downtown", "shops", "boulevard"][seq.size() % 3])  # Erfurt in der Mitte: Innenstadt
			else:
				var zi := -1
				var zd := URBAN_R
				for ui in urban.size():
					var du := Vector2(q.x - urban[ui].x, q.z - urban[ui].z).length()
					if du < zd:
						zd = du
						zi = ui
				seq.append("land" if zi < 0 else (zones[zi] if zi < zones.size() else "highway"))
			next += 400.0
		acc += l
	if seq.is_empty():
		seq.append("land")
	return seq


## Kuppen auf den Ringen (seit 2.29): in Überland-Abschnitten ab 1,2 km ohne Auffahrt hebt sich die Autobahn auf
## einen Damm (6-10 m, 170 m Anstieg), sonst lief der Ring flach wie ein Brett um die Karte
static func _ring_crests(sg: Dictionary) -> void:
	var race: Dictionary = sg["race"]
	var pts: Array = race["pts"]
	var cum := [0.0]
	for k in pts.size() - 1:
		cum.append(cum[k] + (pts[k] as Vector3).distance_to(pts[k + 1]))
	var total: float = cum[cum.size() - 1]
	if total < 1500.0:
		return
	# Lage der Auffahrten auf dem Stück (Meter) und wie weit eine Kuppe davon wegbleibt; Autobahndreiecke (seit 2.36):
	# über ihre ganze Länge flach (die Rampen fädeln auf Höhe des Rings ein, die Brücke ist auf ihn abgestimmt)
	var ramp_d := []
	var marks := []
	for r in race["ramps"]:
		marks.append([r["from"], 300.0])
	for nc in race.get("no_crest", []):
		marks.append([nc[0], float(nc[1])])
	for mk in marks:
		var best := 1e9
		var bd := 0.0
		for k in pts.size():
			var dd := Vector2(pts[k].x - mk[0].x, pts[k].z - mk[0].z).length()
			if dd < best:
				best = dd
				bd = cum[k]
		ramp_d.append([bd, mk[1]])
	var seq: Array = race["district_seq"]
	var crests := []
	var rng := RandomNumberGenerator.new()
	rng.seed = int(race["seed"]) * 31 + 7
	var i := 0
	while i < seq.size():
		if seq[i] != "land":
			i += 1
			continue
		var j := i
		while j < seq.size() and seq[j] == "land":
			j += 1
		var a := maxf(i * 400.0 + 150.0, 260.0)
		var e := minf(minf(j * 400.0, total) - 150.0, total - 260.0)
		for rdm in ramp_d:
			var rd: float = rdm[0]
			var mg: float = rdm[1]
			if rd > a - mg and rd < e + mg:
				# Auffahrt im Abschnitt: nur die längere Seite davon nutzen
				if rd - a > e - rd:
					e = rd - mg
				else:
					a = rd + mg
		if e - a >= 900.0 and a > 200.0 and e < total - 200.0:
			crests.append([a / total, e / total, rng.randf_range(6.0, 10.0)])
		i = j
	if not crests.is_empty():
		race["crests"] = crests


static func is_urban(q: Vector3, urban: Array, extra := 0.0) -> bool:
	for u in urban:
		if Vector2(q.x - u.x, q.z - u.z).length() < URBAN_R + extra:
			return true
	return false


## Ring in Stücke teilen (Grenzen nicht in der Nähe einer Auffahrt, nicht in einem Dreieck: avoid). ring_i: 0 innen,
## 1 außen
static func _split(ring: Array, ramps: Array, seed0: int, ring_i: int, name := "", avoid := {}) -> Array:
	var m := ring.size()
	var ramp_k := {}
	for r in ramps:
		ramp_k[r["k"]] = r
	var segments := []
	var per := int(SEG_LEN / RING_STEP)
	# erste Naht bei Punkt 0, außer dort liegt eine Auffahrt oder ein Dreieck (seit 2.36): dann ein Stück weiter
	var ks := 0
	while not avoid.is_empty() and ks < m - 1 and (_near_ramp(ramp_k, ks, m, 3) or avoid.has(ks)):
		ks += 1
	var kend := ks + m
	var k0 := ks
	while k0 < kend:
		var k1 := mini(k0 + per, kend)
		if k1 < kend:
			while _near_ramp(ramp_k, k1 % m, m, 3) or avoid.has(k1 % m):
				k1 += 1
		if kend - k1 < per / 2:
			k1 = kend  # Rest zum letzten Stück
		var pts := []
		for k in range(k0, k1 + 1):
			pts.append(ring[k % m])
		var rs := []
		for k in range(k0 + 1, k1):
			if ramp_k.has(k % m):
				rs.append(ramp_k[k % m])
		var mid: Vector3 = pts[pts.size() / 2]
		segments.append({"race": {"name": name if name != "" else ("Autobahn" if ring_i == 0 else "Außenring"), "type": "autobahn", "seed": seed0 + segments.size(),
			"pts": pts, "districts": {"highway": 1.0}, "mood": MOOD, "ramps": rs, "world": true},
			"center": mid, "radius": (k1 - k0) * RING_STEP / 2.0 + 150.0, "ring": ring_i, "k0": k0, "k1": k1})
		k0 = k1
	return segments


const RB_R := 150.0  # Kreisel in der Kartenmitte: Radius seiner Mittellinie
const ARM_IN := 130.0  # Auffahrt vom Ring bzw. vom Kreisel bis zum Anfang einer Diagonale


## Mitte der Karte: ein großer Kreisel (Autobahn 3+3 rund um einen Platz) und vier Diagonalen ("Querspange") vom
## inneren Ring dorthin, leicht geschwungen (eine S-Kurve, an den Enden gerade). Die Winkel liegen möglichst weit weg
## von den Auffahrten der Städte. Die Diagonalen hängen wie Städte über Auffahrten am Ring und am Kreisel (ramps,
## "wide": so breit wie die Autobahn); ihre Auffahrten am Ring kommen in ramps dazu.
static func _plan_middle(ring: Array, ramps: Array) -> Dictionary:
	var m := ring.size()
	var taken := []
	for r in ramps:
		taken.append(TAU * float(r["k"]) / m)
	var best_a := 0.0
	var best_s := -1.0
	for deg in 90:
		var a0 := deg_to_rad(float(deg))
		var sc := 1e9
		for i in 4:
			for t in taken:
				sc = minf(sc, absf(wrapf(a0 + i * PI / 2.0 - t, -PI, PI)))
		if sc > best_s:
			best_s = sc
			best_a = a0
	var nrb := 24
	var rb := []
	for k in nrb:
		var a := best_a + PI / 4.0 + TAU * k / nrb  # Punkt 0 zwischen zwei Diagonalen (dort schließt der Kreis)
		rb.append(Vector3(cos(a) * RB_R, 0.0, sin(a) * RB_R))
	var arms := []
	var rb_ramps := []
	for i in 4:
		var a := best_a + i * PI / 2.0
		var kr := posmod(int(round(a / TAU * m)), m)
		var rp: Vector3 = ring[kr]
		var dir_in := -Vector3(rp.x, 0.0, rp.z).normalized()
		var p0 := rp + dir_in * ARM_IN
		var krb := posmod(6 * i - 3, nrb)
		var bp: Vector3 = rb[krb]
		var p1 := bp + Vector3(bp.x, 0.0, bp.z).normalized() * ARM_IN
		var L := p0.distance_to(p1)
		var n := int(ceil(L / RING_STEP))
		var side := Vector3(-dir_in.z, 0.0, dir_in.x) * (1.0 if i % 2 == 0 else -1.0)
		var pts := []
		for j in n + 1:
			var t := float(j) / n
			pts.append(p0.lerp(p1, t) + side * sin(t * TAU) * sin(t * PI) * 170.0)
		arms.append(pts)
		ramps.append({"k": kr, "from": rp, "end": p0, "name": "", "wide": true})
		rb_ramps.append({"k": krb, "from": bp, "end": p1, "name": "", "wide": true})
	return {"rb": rb, "rb_ramps": rb_ramps, "arms": arms}


const SPOKE_CLEAR := 230.0  # so weit bleibt eine Spange von Straßen und Häusern der Städte weg
const SPOKE_MAX := 7


## Spangen: gerade Autobahnstücke (mit leichtem Schwung) vom inneren zum äußeren Ring, wo zwischen zwei Städten Platz
## ist: Linie radial nach außen bis zum Außenring, überall mindestens SPOKE_CLEAR von Stadtstraßen und Häusern, nicht
## an anderen Auffahrten, mindestens 40 Grad zur nächsten Spange. Hängen wie die Diagonalen über breite Auffahrten an
## beiden Ringen (ramps, oramps).
static func _plan_spokes(cities: Array, ring: Array, oring: Array, ramps: Array, oramps: Array) -> Array:
	var m := ring.size()
	var mo := oring.size()
	var cell := 200.0
	var grid := {}
	for c in cities:
		var pts := []
		for rd in c["roads"]:
			var pl: PackedVector2Array = rd[0]
			for k in range(0, pl.size(), 2):
				pts.append(pl[k])
		for q in c.get("bld_world", PackedVector2Array()):
			pts.append(q)
		for q in pts:
			var key := Vector2i(floori(q.x / cell), floori(q.y / cell))
			if not grid.has(key):
				grid[key] = []
			grid[key].append(q)
	var clear := func(q: Vector3) -> bool:
		var p := Vector2(q.x, q.z)
		var key := Vector2i(floori(p.x / cell), floori(p.y / cell))
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				for o in grid.get(key + Vector2i(dx, dy), []):
					if p.distance_to(o) < SPOKE_CLEAR:
						return false
		return true
	var near_ramp := func(list: Array, k: int, n: int) -> bool:
		for r in list:
			var dk: int = absi(int(r["k"]) - k)
			if mini(dk, n - dk) < 8:
				return true
		return false
	var out := []
	var angs := []
	for step in 240:
		if out.size() >= SPOKE_MAX:
			break
		var a := TAU * step / 240.0
		var ok := true
		for b in angs:
			if absf(wrapf(a - b, -PI, PI)) < deg_to_rad(40.0):
				ok = false
		if not ok:
			continue
		var kr := posmod(int(round(a / TAU * m)), m)
		if near_ramp.call(ramps, kr, m):
			continue
		var rp: Vector3 = ring[kr]
		var dir := Vector3(rp.x, 0.0, rp.z).normalized()
		var ko := 0
		var best := 1e9
		for k in mo:
			var q: Vector3 = oring[k]
			var dd := absf(wrapf(atan2(q.z, q.x) - atan2(dir.z, dir.x), -PI, PI))
			if dd < best:
				best = dd
				ko = k
		if near_ramp.call(oramps, ko, mo):
			continue
		var op: Vector3 = oring[ko]
		var p0 := rp + dir * ARM_IN
		var p1 := op + (rp - op).normalized() * ARM_IN
		var L := p0.distance_to(p1)
		if L < 700.0:
			continue
		var n := int(ceil(L / RING_STEP))
		var side := Vector3(-dir.z, 0.0, dir.x) * (1.0 if step % 2 == 0 else -1.0)
		var pts := []
		for j in n + 1:
			var t := float(j) / n
			pts.append(p0.lerp(p1, t) + side * sin(t * TAU) * sin(t * PI) * minf(120.0, L * 0.08))
		for j in range(0, 41):
			var q: Vector3 = rp.lerp(p0, j / 40.0) if j < 5 else Vector3.ZERO
			if j < 5 and not clear.call(q):
				ok = false
		for q in pts + [op]:
			if not clear.call(q):
				ok = false
				break
		if not ok:
			continue
		angs.append(a)
		out.append(pts)
		ramps.append({"k": kr, "from": rp, "end": p0, "name": "AUSSENRING", "wide": true})
		oramps.append({"k": ko, "from": op, "end": p1, "name": "INNENRING", "wide": true})
	return out


## Offene Straße (Diagonale) in Stücke von gut SEG_LEN teilen; die Enden bekommen im Mittelstreifen eine Lücke
## (dort mündet die Auffahrt). "open": der Verkehr fährt am Ende nicht auf das erste Stück weiter.
static func _split_open(pts: Array, seed0: int, ring_i: int, name: String) -> Array:
	var per := int(SEG_LEN / RING_STEP)
	var out := []
	var k0 := 0
	var m := pts.size() - 1
	while k0 < m:
		var k1 := mini(k0 + per, m)
		if m - k1 < per / 2:
			k1 = m
		var sp := pts.slice(k0, k1 + 1)
		# eine Kuppe je Stück (über die Häuser hinweg, mit Tempo hebt man oben kurz ab), weit weg von den Nähten
		var crng := RandomNumberGenerator.new()
		crng.seed = seed0 * 7 + out.size()
		var c0 := crng.randf_range(0.18, 0.3)
		var crests := [[c0, c0 + crng.randf_range(0.35, 0.5), crng.randf_range(5.0, 9.0)]]
		# nur, wenn sie hineinpasst (seit 2.36): auf kurzen Stücken überlappten sich die beiden 170-m-Anstiege, die Straße
		# endete oben an einer Kante und fiel 5-9 m senkrecht ab (Spange am Außenring, Überschlag)
		var plen := 0.0
		for k in sp.size() - 1:
			plen += (sp[k] as Vector3).distance_to(sp[k + 1])
		if (float(crests[0][1]) - float(crests[0][0])) * plen < 2.0 * 170.0 + 60.0:
			crests = []
		out.append({"race": {"name": name, "type": "autobahn", "seed": seed0 + out.size(), "pts": sp,
			"districts": {"highway": 1.0}, "mood": MOOD, "ramps": [], "world": true, "open": true,
			"gap_start": k0 == 0, "gap_end": k1 == m, "crests": crests},
			"center": sp[sp.size() / 2], "radius": (k1 - k0) * RING_STEP / 2.0 + 150.0, "ring": ring_i})
		k0 = k1
	return out


## Häuser der Mitte (Kreisel, Diagonalen) nicht auf den Ring, den Kreisel oder eine andere Diagonale
static func _middle_keepout(msegs: Array, ring: Array, mid: Dictionary) -> void:
	var r: float = Track.HALF_W + Track.AB_EXTRA + Track.MED + Track.WALK + 3.0
	var lines := [[ring + [ring[0]], -1], [mid["rb"] + [mid["rb"][0]], 2]]
	for i in mid["arms"].size():
		lines.append([mid["arms"][i], 3 + i])
	for rr in mid["rb_ramps"]:
		lines.append([[rr["from"], rr["end"]], 2])
	for sg in msegs:
		var ctr: Vector3 = sg["center"]
		var reach: float = sg["radius"] + 300.0
		var ko := []
		for ln in lines:
			if ln[1] == sg["ring"]:
				continue
			var pts: Array = ln[0]
			for k in pts.size() - 1:
				var a: Vector3 = pts[k]
				var b: Vector3 = pts[k + 1]
				var n := maxi(int(a.distance_to(b) / 8.0), 1)
				for j in n:
					var q := a.lerp(b, float(j) / n)
					if Vector2(q.x - ctr.x, q.z - ctr.z).length() < reach:
						ko.append({"pos": q, "r": r, "ko": true})
		sg["race"]["keepout"] = ko


## Außenring: läuft in sanften Bögen außen um alle Städte. Jeder Straßenpunkt einer Stadt hebt den Ring an seiner
## Stelle auf mindestens 260 m Abstand an, mit einer Kuppe vom Radius 900 m (Parabel über die Bogenlänge), damit es
## keine Knicke gibt; dazwischen mindestens 700 m außerhalb des inneren Rings. Zum Schluss leicht geglättet.
static func _outer_ring(cities: Array, R: float) -> Array:
	var pts2 := []
	var rmax := R
	for c in cities:
		for road in c["roads"]:
			for q in road[0]:
				pts2.append(q)
				rmax = maxf(rmax, (q as Vector2).length())
	var m := int(TAU * (rmax + 400.0) / RING_STEP)
	var need := PackedFloat32Array()
	need.resize(m)
	need.fill(R + 700.0)
	const RC := 900.0
	for q in pts2:
		var rq: float = (q as Vector2).length()
		var a := atan2(q.y, q.x)
		var top := rq + 260.0
		var span := sqrt(2.0 * RC * maxf(top - (R + 700.0), 0.0))  # so weit (Bogen) reicht die Kuppe
		var w := int(ceil(span / rq / (TAU / m)))
		var k0 := int(round(a / TAU * m))
		for dk in range(-w, w + 1):
			var sdist := absf(dk) * (TAU / m) * rq
			var k := posmod(k0 + dk, m)
			need[k] = maxf(need[k], top - sdist * sdist / (2.0 * RC))
	# glätten, aber nie unter den nötigen Abstand: so füllen sich die spitzen Täler zwischen zwei Kuppen zu Bögen
	var r := need
	for it in 400:
		var nr := PackedFloat32Array()
		nr.resize(m)
		for k in m:
			nr[k] = maxf(need[k], 0.25 * r[posmod(k - 1, m)] + 0.5 * r[k] + 0.25 * r[(k + 1) % m])
		r = nr
	for it in 3:
		var nr2 := PackedFloat32Array()
		nr2.resize(m)
		for k in m:
			nr2[k] = 0.25 * r[posmod(k - 1, m)] + 0.5 * r[k] + 0.25 * r[(k + 1) % m]
		r = nr2
	if OS.get_cmdline_user_args().has("--worldlog"):
		# engster Bogen des Außenrings (Umkreis von drei Punkten im Abstand von je 2 Schritten)
		var rmin := 1e9
		for k in m:
			var pa := Vector2(cos(TAU * (k - 2) / m), sin(TAU * (k - 2) / m)) * r[posmod(k - 2, m)]
			var pb := Vector2(cos(TAU * k / m), sin(TAU * k / m)) * r[k]
			var pc := Vector2(cos(TAU * (k + 2) / m), sin(TAU * (k + 2) / m)) * r[(k + 2) % m]
			var area := absf((pb - pa).cross(pc - pa))
			if area > 1e-3:
				rmin = minf(rmin, pa.distance_to(pb) * pb.distance_to(pc) * pc.distance_to(pa) / (2.0 * area))
		print("WELT Außenring: engster Bogen %.0f m" % rmin)
	var out := []
	for k in m:
		var a := TAU * k / m
		out.append(Vector3(cos(a) * r[k], 0.0, sin(a) * r[k]))
	return out


## Punkte einer Auffahrt (gerade oder Bogen mit Anfassern c1/c2)
static func _ramp_pts(r: Dictionary) -> Array:
	if r.has("pts"):
		return r["pts"]
	return [r["from"], r["end"]]


static func _bez(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var u := 1.0 - t
	return p0 * (u * u * u) + p1 * (3.0 * u * u * t) + p2 * (3.0 * u * t * t) + p3 * (t * t * t)


## Zweite Ausfahrt der Sprints (hinter dem Ziel) mit dem nächsten freien Ring verbinden: eine Straße im Bogen vom Ring
## (senkrecht abgehend) bis zum Ende der Ausfahrt (in ihrer Richtung ankommend). Gesucht wird auf beiden Ringen bis
## 1,2 km zur Seite; die Straße darf keiner anderen Straße näher als 32 m kommen und nicht zu eng kurven. Die kürzeste
## gültige gewinnt. Ohne gültige führt die Straße hinter dem Ziel zurück auf die eigene Strecke (race["tail_join"]).
static func _connect_ends(cities: Array, ring: Array, oring: Array, ramps_in: Array, ramps_out: Array) -> void:
	const CELL := 50.0
	var grid := {}  # Zelle -> [Punkt 2D, Stadt]
	var add := func(q: Vector2, owner: int) -> void:
		var key := Vector2i(floori(q.x / CELL), floori(q.y / CELL))
		if not grid.has(key):
			grid[key] = []
		grid[key].append([q, owner])
	for c in cities:
		for road in c["roads"]:
			for q in road[0]:
				add.call(q, c["race_index"])
	for rg in [ring, oring]:
		for k in rg.size():
			var a3: Vector3 = rg[k]
			var b3: Vector3 = rg[(k + 1) % rg.size()]
			for j in 10:
				var q3 := a3.lerp(b3, j / 10.0)
				add.call(Vector2(q3.x, q3.z), -1 if rg == ring else -2)
	for r in ramps_in:
		for j in 40:
			var q4: Vector3 = (r["from"] as Vector3).lerp(r["end"], j / 40.0)
			add.call(Vector2(q4.x, q4.z), -3)
	var near := func(q: Vector2, rad: float, skip: int) -> bool:
		var c0 := Vector2i(floori(q.x / CELL), floori(q.y / CELL))
		var n := int(ceil(rad / CELL))
		for dx in range(-n, n + 1):
			for dz in range(-n, n + 1):
				for e in grid.get(c0 + Vector2i(dx, dz), []):
					if e[1] != skip and (e[0] as Vector2).distance_to(q) < rad:
						return true
		return false
	for c in cities:
		var ex2: Dictionary = c["exit2_local"]
		if ex2.is_empty():
			continue
		var xf: Transform3D = c["xf"]
		var e2: Vector3 = xf * (ex2["end"] as Vector3)
		e2.y = 0.0
		var d2: Vector3 = xf.basis * (ex2["dir"] as Vector3)
		d2.y = 0.0
		d2 = d2.normalized()
		var best := {}
		var best_len := 1e9
		for which in 2:
			var rg: Array = ring if which == 0 else oring
			var m := rg.size()
			var k0 := int(round(atan2(e2.z, e2.x) / TAU * m))
			for cand in 81 * 3:
				var dk := cand / 3 - 40
				var hk: float = [0.3, 0.45, 0.6][cand % 3]  # Länge der Anfasser (Anteil der Luftlinie)
				var k := posmod(k0 + dk, m)
				var rp: Vector3 = rg[k]
				var nrm := Vector3(rp.x, 0.0, rp.z).normalized()
				var sd := signf((e2 - rp).dot(nrm))
				var L := rp.distance_to(e2)
				if L < 120.0:
					continue
				var c1 := rp + nrm * sd * L * hk
				var c2 := e2 + d2 * L * hk
				var pts := []
				var ok := true
				var prev_dir := Vector3.ZERO
				var length := 0.0
				for j in 41:
					var q := _bez(rp, c1, c2, e2, j / 40.0)
					if j > 0:
						var sg: Vector3 = q - pts[-1]
						length += sg.length()
						if prev_dir != Vector3.ZERO and prev_dir.angle_to(sg) > deg_to_rad(9.0):
							ok = false  # zu enge Kurve (gut 9° je Vierzigstel)
							break
						prev_dir = sg
					pts.append(q)
				if not ok or length >= best_len:
					continue  # zu eng, oder es gibt schon eine kürzere
				# für den Abstand dicht abtasten (gut 10 m): mit nur 41 Punkten liegen sie bei langen Verbindungen fast
				# 70 m auseinander, und eine Straße quer dazwischen fiel durch den 32-m-Radius (Würzburg: Rampe quer
				# durch die eigene Hauptstraße)
				var nd := maxi(40, int(ceil(length / 10.0)))
				pts = []
				for j in nd + 1:
					pts.append(_bez(rp, c1, c2, e2, float(j) / nd))
				var acc := 0.0
				for j in range(1, pts.size()):
					acc += (pts[j] as Vector3).distance_to(pts[j - 1])
					if acc < 50.0 or length - acc < 50.0:
						continue
					var q2 := Vector2(pts[j].x, pts[j].z)
					# andere Straßen (auch die eigene Stadt), der andere Ring, die geraden Auffahrten
					if near.call(q2, 32.0, -1 if which == 0 else -2):
						ok = false
						break
					# den eigenen Ring nur am Anfang berühren
					if acc > 90.0 and near.call(q2, 36.0, -99) and _near_only(grid, q2, 36.0, -1 if which == 0 else -2, CELL):
						ok = false
						break
				if not ok:
					continue
				for o in ramps_in + ramps_out:
					if not o.has("pts"):
						continue
					var op: Array = o["pts"]
					for i5 in range(0, op.size(), 2):
						for i6 in range(0, pts.size(), 2):
							if (op[i5] as Vector3).distance_to(pts[i6]) < 40.0:
								ok = false
								break
						if not ok:
							break
					if not ok:
						break
				if ok and length < best_len:
					best_len = length
					best = {"k": k, "from": rp, "end": e2, "c1": c1, "c2": c2, "pts": pts, "ring": which,
						"name": Catalog.RACES[c["race_index"]].get("town", ""), "forest": Catalog.RACES[c["race_index"]].get("forest", false),
						"zone": ramp_zone(c["race_index"])}
		if not best.is_empty():
			(ramps_in if best["ring"] == 0 else ramps_out).append(best)
			c["exit2_ring"] = best["ring"]
			c["exit2_world"] = e2


## Liegt in der Nähe nur der Ring "owner"? (für: die Straße läuft am eigenen Ring entlang oder kreuzt ihn)
static func _near_only(grid: Dictionary, q: Vector2, rad: float, owner: int, cell: float) -> bool:
	var c0 := Vector2i(floori(q.x / cell), floori(q.y / cell))
	var n := int(ceil(rad / cell))
	for dx in range(-n, n + 1):
		for dz in range(-n, n + 1):
			for e in grid.get(c0 + Vector2i(dx, dz), []):
				if e[1] == owner and (e[0] as Vector2).distance_to(q) < rad:
					return true
	return false


static func _near_ramp(ramp_k: Dictionary, k: int, m: int, w: int) -> bool:
	for dk in range(-w, w + 1):
		if ramp_k.has((k + dk + m) % m):
			return true
	return false


## Sperrflächen: jede Stadt bekommt die fremden Fahrbahnen in ihrer Nähe (Ring, alle Auffahrten, Straßen der
## Nachbarstädte) als Kreise in ihren eigenen Koordinaten (race["keepout"]); der Streckenbau stellt dort keine Häuser
## hin (track_builder Schritt 2: wie belegte Flächen). Sonst ragen Häuser aus echten Stadtplänen auf die Autobahn.
## Seit 2.39 mit Art ("w": ring, ramp, city, ix, spoke), danach richtet sich die Stadtfüllung (city_fill.gd); die Spangen
## kommen nur für sie dazu (die übrige Bebauung bleibt ohnehin 230 m weg, _plan_spokes).
static func _add_keepout(cities: Array, ring: Array, ramps: Array, oring: Array, osegs: Array, ix_lines := [], spokes := []) -> void:
	var ring_r: float = Track.HALF_W + Track.AB_EXTRA + Track.MED + Track.WALK + 5.0  # 2.32: +2 m (Bad Kissingen stand knapp drauf)
	var lines := []  # [Weltpunkte, Radius, Stadt (eigene Straßen auslassen) oder -1, Art]
	for pl in ix_lines:
		lines.append([pl, Interchange.HALF + 9.0, -1, "ix"])  # Rampen und Brücken der Autobahndreiecke (seit 2.36)
	var rl := []
	for q in ring:
		rl.append(q)
	rl.append(ring[0])
	lines.append([rl, ring_r, -1, "ring"])
	var orl := oring.duplicate()
	orl.append(oring[0])
	lines.append([orl, ring_r, -2, "ring"])
	for sp in spokes:
		lines.append([sp, ring_r, -3, "spoke"])
	for r in ramps:
		# Bögen zu den Ziel-Ausfahrten: etwas mehr Platz (die Kreise sitzen auf den Sehnen des Bogens)
		lines.append([_ramp_pts(r), Track.HALF_W + Track.WALK + (8.0 if r.has("c1") else 2.0) + (Track.AB_EXTRA + 3.0 if r.get("wide", false) else 0.0), -1, "ramp"])
	for c in cities:
		for road in c["roads"]:
			var pl := []
			for q in road[0]:
				pl.append(Vector3(q.x, 0.0, q.y))
			# Nebenwege seit 2.39 bis 12,6 m breit bis zur Hauskante (breite Straße mit Grünstreifen), Plätze 13 m: 18 m
			lines.append([pl, Track.HALF_W + Track.WALK + 2.0 if road[1] == 0 else 18.0, c["race_index"], "city"])
	for c in cities:
		var inv: Transform3D = (c["xf"] as Transform3D).affine_inverse()
		var ctr: Vector3 = c["center"]
		var reach: float = c["radius"] + 700.0
		var ko := []
		for ln in lines:
			if ln[2] == c["race_index"]:
				continue
			var pts: Array = ln[0]
			for k in pts.size() - 1:
				var a: Vector3 = pts[k]
				var b: Vector3 = pts[k + 1]
				var n := maxi(int(a.distance_to(b) / 8.0), 1)
				for j in n:
					var q := a.lerp(b, float(j) / n)
					if Vector2(q.x - ctr.x, q.z - ctr.z).length() < reach:
						ko.append({"pos": inv * q, "r": ln[1], "ko": true, "w": ln[3]})
		c["race"]["keepout"] = ko
	# Außenring: seine Häuser dürfen nicht auf die Straßen der Städte (der innere Ring liegt weit genug weg)
	for sg in osegs:
		var ctr2: Vector3 = sg["center"]
		var reach2: float = sg["radius"] + 300.0
		var ko2 := []
		for ln in lines:
			if ln[2] == -2 or ln[2] == -3:
				continue
			var pts2: Array = ln[0]
			for k in pts2.size() - 1:
				var a2: Vector3 = pts2[k]
				var b2: Vector3 = pts2[k + 1]
				var n2 := maxi(int(a2.distance_to(b2) / 8.0), 1)
				for j in n2:
					var q2 := a2.lerp(b2, float(j) / n2)
					if Vector2(q2.x - ctr2.x, q2.z - ctr2.z).length() < reach2:
						ko2.append({"pos": q2, "r": ln[1], "ko": true})
		sg["race"]["keepout"] = ko2


# --- Autobahndreiecke (seit 2.36) -------------------------------------------------------------------------------------

## Höhe der Brücke je Art: Querspangen am inneren Ring niedriger (13,5 m, gerade über den Wänden des Rings), Spangen am
## inneren Ring höher, am Außenring am höchsten. So geht es mal höher, mal niedriger über die Autobahn.
const IX_H := {"arm": 13.5, "spoke0": 16.5, "spoke1": 20.0}
## Abstände der Dreieck-Wege zu allem anderen (m): Stadtstraßen und Häuser, Auffahrten und Verbindungen der Städte,
## der andere Ring, andere Spangen/Querspangen und Dreiecke, der Kreisel
const IX_CLEAR := {"city": 75.0, "ramp": 50.0, "ring": 90.0, "arm": 60.0, "spok": 60.0, "ix": 60.0, "wide": 50.0, "rb": 90.0}
static var _ix_log: Array = []
static var _ix_names: Array = []


## Jede breite Einmündung einer Querspange (innerer Ring) oder Spange (beide Ringe) wird, wo Platz ist, ein
## Autobahndreieck. Prüft alle Wege gegen Städte, Auffahrten, den anderen Ring, andere Stämme und schon geplante
## Dreiecke; kürzt den Stamm bis zum Abzweig und nimmt die flache Auffahrt aus ramps/oramps. Liefert je Dreieck
## {race, host, kr, J, h, center, radius, reach, slips, zone_k, ...}.
static func _plan_interchanges(cities: Array, ring: Array, oring: Array, ramps: Array, oramps: Array, mid: Dictionary,
		spokes: Array) -> Array:
	_ix_log = []
	_ix_names = []
	if OS.get_cmdline_user_args().has("--noix"):
		return []  # Test: Welt ohne Autobahndreiecke und Talbrücken (Vorher-Bilder, --noix)
	const CELL := 50.0
	var grid := {}
	var add := func(q: Vector2, tag: String) -> void:
		var key := Vector2i(floori(q.x / CELL), floori(q.y / CELL))
		if not grid.has(key):
			grid[key] = []
		grid[key].append([q, tag])
	var add_line := func(pts: Array, tag: String) -> void:
		for k in pts.size() - 1:
			var a: Vector3 = pts[k]
			var b: Vector3 = pts[k + 1]
			var n := maxi(int(a.distance_to(b) / 10.0), 1)
			for j in n:
				var q := a.lerp(b, float(j) / n)
				add.call(Vector2(q.x, q.z), tag)
	for c in cities:
		for rd in c["roads"]:
			for q in rd[0]:
				add.call(q, "city")
		for q in c.get("bld_world", PackedVector2Array()):
			add.call(q, "city")
	for hi in 2:
		for r in (ramps if hi == 0 else oramps):
			if r.get("wide", false):
				add_line.call(_ramp_pts(r), "wide%d:%d" % [hi, r["k"]])
				continue
			# Auffahrt einer Stadt: ohne ihre ersten 30 m (die liegen im Ring selbst, jenseits des Mittelstreifens)
			var rp: Array = _ramp_pts(r)
			for k in rp.size() - 1:
				var a: Vector3 = rp[k]
				var b: Vector3 = rp[k + 1]
				var n := maxi(int(a.distance_to(b) / 10.0), 1)
				for jj in n:
					var q := a.lerp(b, float(jj) / n)
					if q.distance_to(r["from"]) > 30.0:
						add.call(Vector2(q.x, q.z), "ramp")
	add_line.call(ring + [ring[0]], "ring0")
	add_line.call(oring + [oring[0]], "ring1")
	add_line.call(mid["rb"] + [mid["rb"][0]], "rb")
	for i in mid["arms"].size():
		add_line.call(mid["arms"][i], "arm%d" % i)
	for j in spokes.size():
		add_line.call(spokes[j], "spok%d" % j)
	var clear := func(q: Vector3, own: Array) -> String:
		var p2 := Vector2(q.x, q.z)
		var key := Vector2i(floori(p2.x / CELL), floori(p2.y / CELL))
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				for e in grid.get(key + Vector2i(dx, dy), []):
					var tag: String = e[1]
					if tag in own:
						continue
					var lim: float = IX_CLEAR.get(tag.left(4) if not tag.begins_with("ring") else "ring", IX_CLEAR.get(tag.left(3), 60.0))
					if tag.begins_with("ix"):
						lim = IX_CLEAR["ix"]
					if p2.distance_to(e[0]) < lim:
						return tag
		return ""
	var cands := []
	for i in mid["arms"].size():
		cands.append({"host": 0, "arm": true, "i": i, "end": 0, "h": IX_H["arm"], "dest": CENTER_NAME.to_upper()})
	for j in spokes.size():
		cands.append({"host": 0, "arm": false, "i": j, "end": 0, "h": IX_H["spoke0"], "dest": "AUSSENRING"})
	for j in spokes.size():
		cands.append({"host": 1, "arm": false, "i": j, "end": 1, "h": IX_H["spoke1"], "dest": "INNENRING"})
	var out := []
	for cd in cands:
		var stem: Array = (mid["arms"][cd["i"]] if cd["arm"] else spokes[cd["i"]]).duplicate()
		if cd["end"] == 1:
			stem.reverse()
		var host: Array = ring if cd["host"] == 0 else oring
		var rlist: Array = ramps if cd["host"] == 0 else oramps
		var r_idx := -1
		for k in rlist.size():
			if rlist[k].get("wide", false) and (rlist[k]["end"] as Vector3).distance_to(stem[0]) < 1.0:
				r_idx = k
		if r_idx < 0:
			continue
		var kr: int = rlist[r_idx]["k"]
		var label := "%s %d am %s" % ["Querspange" if cd["arm"] else "Spange", cd["i"], ["Ring", "Außenring"][cd["host"]]]
		var own := ["ring%d" % cd["host"], ("arm%d" if cd["arm"] else "spok%d") % cd["i"], "wide%d:%d" % [cd["host"], kr]]
		var why := ""
		var p := {}
		# erst die weite Form, wo es eng ist die knappe (engere Flügel, kürzere Einfädelstreifen)
		for opt in [{}, Interchange.COMPACT]:
			why = ""
			p = Interchange.plan(host, kr, stem, cd["h"], opt)
			if p.is_empty():
				why = "Stamm zu kurz oder Flügel zu steil"
				continue
			why = _ix_check(p, clear, own, cities)
			if why == "":
				break
		if why != "":
			_ix_log.append("WELT Dreieck entfällt: %s (%s)" % [label, why])
			continue
		rlist.remove_at(r_idx)
		var cut: Array = p["stem_cut"]
		if cd["end"] == 1:
			cut.reverse()
		if cd["arm"]:
			mid["arms"][cd["i"]] = cut
		else:
			spokes[cd["i"]] = cut
		for lk in p["links"]:
			add_line.call(lk["pts"], "ix%d" % out.size())
		out.append(_ix_finish(p, cd, kr, out.size(), cities, rlist, host.size()))
	# Wegweiser: kein Mast auf einem anderen Weg (Rampen eines benachbarten Dreiecks, Auffahrten, Häuser); sonst ein Stück
	# weiter vor oder zurück, notfalls entfällt das Schild
	var post_free := func(q: Vector3) -> bool:
		var p2 := Vector2(q.x, q.z)
		var key := Vector2i(floori(p2.x / CELL), floori(p2.y / CELL))
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				for e in grid.get(key + Vector2i(dx, dy), []):
					if p2.distance_to(e[0]) < (Interchange.HALF + 4.0 if str(e[1]).begins_with("ix") else 14.0):
						return false
		return true
	for j in out:
		var keep := []
		for sg in j["race"]["signs"]:
			for alt in sg["alts"]:
				var fw: Vector3 = alt["fwd"]
				var rt := Vector3(-fw.z, 0.0, fw.x)
				var ok := true
				for px in sg["posts"]:
					if not post_free.call((alt["pos"] as Vector3) + rt * float(px)):
						ok = false
				if ok:
					sg["pos"] = alt["pos"]
					sg["fwd"] = alt["fwd"]
					keep.append(sg)
					break
		j["race"]["signs"] = keep
	return out


## Prüft ein geplantes Dreieck: Abstand aller Wege zu Städten, Auffahrten, Ringen, Stämmen und anderen Dreiecken
## (clear), Krümmung der Rampen, Hügel der Städte. Liefert den Grund, warum es nicht passt, oder "".
static func _ix_check(p: Dictionary, clear: Callable, own: Array, cities: Array) -> String:
	for lk in p["links"]:
		var lp: Array = lk["pts"]
		for k in range(0, lp.size(), 3):
			var hit: String = clear.call(lp[k], own)
			if hit != "":
				return "%s an %s" % [lk["name"], hit]
		var rmin := Interchange.min_radius(lp)
		if lk["name"] != "B" and rmin < (55.0 if lk["name"].begins_with("F") else 120.0):
			return "%s zu eng (%.0f m)" % [lk["name"], rmin]
	for c in cities:
		for hl in c["hills_world"]:
			for lk in p["links"]:
				for q in lk["pts"]:
					if Vector2(q.x, q.z).distance_to(hl[0]) < hl[1] + 50.0:
						return "%s am Hügel von %s" % [lk["name"], Catalog.RACES[c["race_index"]].get("town", "?")]
	return ""


## Nächste Stadt (Auffahrt mit Namen) auf dem Ring ab Punkt kr in Richtung dirk (+1: mit den Punkten)
static func _next_town(rlist: Array, m: int, kr: int, dirk: int) -> String:
	var best := 1 << 30
	var name := ""
	for r in rlist:
		if r.get("wide", false) or str(r.get("name", "")) == "":
			continue
		var dk := posmod((int(r["k"]) - kr) * dirk, m)
		if dk > 2 and dk < best:
			best = dk
			name = r["name"]
	return name


## Fertiges Dreieck: Name (nächste Stadt), Wegweiser, Schlupfwege für den Ring, Umkreis zum Nachladen
static func _ix_finish(p: Dictionary, cd: Dictionary, kr: int, n: int, cities: Array, rlist: Array, m: int) -> Dictionary:
	var J: Vector3 = p["J"]
	var s: float = p["s"]
	# Name nach der nächsten Stadt, die noch kein Dreieck hat
	var towns := []
	for c in cities:
		towns.append([Vector2(J.x - c["exit_world"].x, J.z - c["exit_world"].z).length(), str(Catalog.RACES[c["race_index"]].get("town", ""))])
	towns.sort_custom(func(a, b): return a[0] < b[0])
	var town: String = towns[0][1]
	for t in towns:
		if not t[1] in _ix_names and t[1] != "":
			town = t[1]
			break
	_ix_names.append(town)
	var name := "Dreieck %s" % town
	var dirk := 1 if s > 0.0 else -1  # Fahrtrichtung der Fahrbahn auf der Seite des Stamms, in Ringpunkten
	var dest_p := _next_town(rlist, m, kr, dirk).to_upper()
	var dest_m := _next_town(rlist, m, kr, -dirk).to_upper()
	var ring_name: String = ["Autobahnring", "Außenring"][cd["host"]]
	var links: Array = p["links"]
	var hc := Interchange.smooth_curve(p["host_pts"])
	var signs := []
	# Schilderbrücke über dem Stamm, gut 230 m vor dem Abzweig: rechts zur nahen Fahrbahn, geradeaus über die Brücke
	var sc := Interchange.smooth_curve(p["stem_cut"] if cd["end"] == 0 else _reversed(p["stem_cut"]))
	var alts := []
	for dd in [200.0, 170.0, 240.0, 140.0]:
		var fs := Track.frame_at(sc, minf(dd, sc.get_baked_length() * 0.4))
		alts.append({"pos": fs["pos"], "fwd": -(fs["fwd"] as Vector3)})
	signs.append({"pos": alts[0]["pos"], "fwd": alts[0]["fwd"], "alts": alts, "posts": [-22.9, 22.9], "span": [-22.9, 22.9],
		"panels": [[7.4, dest_m, ring_name, "unten", 7.0], [15.0, dest_p, ring_name, "rechts", 6.4]]})
	# Kragarm-Wegweiser über jeder Fahrbahn des Rings, 260 m vor dem Ende ihrer Ausfahrt (NE nahe, FE ferne Seite)
	for li in [2, 3]:
		var lp: Array = links[li]["pts"]
		var de := hc.get_closest_offset(lp[-1])
		var near: bool = li == 2
		var dk := -s if near else s  # vom Ende der Ausfahrt weiter gegen die Fahrtrichtung der Leser
		var ring_alts := []
		for dd in [260.0, 200.0, 320.0, 150.0, 400.0]:
			var fr := Track.frame_at(hc, de + dk * dd)
			ring_alts.append({"pos": fr["pos"], "fwd": (fr["fwd"] as Vector3) * (s if near else -s)})
		signs.append({"pos": ring_alts[0]["pos"], "fwd": ring_alts[0]["fwd"], "alts": ring_alts, "posts": [22.9], "span": [3.2, 22.9],
			"panels": [[7.4, dest_p if near else dest_m, "", "unten", 7.0], [15.0, cd["dest"], name, "rechts", 6.4]]})
	# Schlupfwege: die Enden der Rampen, wo sie neben dem Ring laufen (dort keine Randwand des Rings)
	var slips := []
	for li in range(1, links.size()):
		var lp: Array = links[li]["pts"]
		var i0 := lp.size() - 1
		while i0 > 0:
			var q: Vector3 = lp[i0 - 1]
			var hq := hc.get_closest_point(q)
			if Vector2(q.x - hq.x, q.z - hq.z).length() > Interchange.RING_WALL + Interchange.HALF + 14.0:
				break
			i0 -= 1
		slips.append(lp.slice(maxi(i0 - 1, 0)))
	# Umkreis (zum Nachladen) und Reichweite entlang des Rings (für Zonen und Kuppen)
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	var reach := 0.0
	var pts_all := []
	for lk in links:
		pts_all.append_array(lk["pts"])
	for sg in signs:
		pts_all.append(sg["pos"])
	for q in pts_all:
		lo = lo.min(Vector2(q.x, q.z))
		hi = hi.max(Vector2(q.x, q.z))
		reach = maxf(reach, Vector2(q.x - J.x, q.z - J.z).length())
	var ctr := (lo + hi) / 2.0
	var rad := 0.0
	for q in pts_all:
		rad = maxf(rad, Vector2(q.x, q.z).distance_to(ctr))
	var zone_a: Vector3 = Track.frame_at(hc, float(p["dJ"]) - reach - 40.0)["pos"]
	var zone_b: Vector3 = Track.frame_at(hc, float(p["dJ"]) + reach + 40.0)["pos"]
	var race := {"name": name, "type": "dreieck", "seed": 9700 + n, "pts": links[0]["pts"], "links": links,
		"host_pts": p["host_pts"], "s": s, "world": true, "open": true, "mood": MOOD, "districts": {"land": 1.0},
		"area": ("AUTOBAHNDREIECK " + town).to_upper(), "signs": signs, "ramps": []}
	return {"race": race, "host": cd["host"], "kr": kr, "J": J, "h": cd["h"], "center": Vector3(ctr.x, 0.0, ctr.y),
		"radius": rad + 60.0, "reach": reach + 100.0, "slips": slips, "zone": [zone_a, zone_b], "stem_end": cd["end"]}


static func _reversed(a: Array) -> Array:
	var b := a.duplicate()
	b.reverse()
	return b


## Schlupfwege, Zonen und flache Abschnitte der Dreiecke an die Stücke ihres Rings hängen (host: 0 innen, 1 außen)
static func _ix_attach(ixs: Array, segs: Array, m: int, host: int) -> void:
	for j in ixs:
		if j["host"] != host:
			continue
		var kr: int = j["kr"]
		var zk := int(ceil(float(j["reach"]) / RING_STEP)) + 2
		for sg in segs:
			var k0: int = sg["k0"]
			var k1: int = sg["k1"]
			var race: Dictionary = sg["race"]
			var spts: Array = race["pts"]
			# Schlupfweg an jedes Stück, dem er nahe kommt (liegt eine Naht in der Einmündung, an beide)
			for sl in j["slips"]:
				var touch := false
				for q in sl:
					for sp in spts:
						if Vector2(q.x - sp.x, q.z - sp.z).length() < 90.0:
							touch = true
							break
					if touch:
						break
				if touch:
					race["slips"] = race.get("slips", []) + [sl]
			# Zone und Kuppenverbot auch für Nachbarstücke, wenn das Dreieck bis dorthin reicht
			var near := false
			for dk in range(-zk, zk + 1):
				if posmod(kr + dk - k0, m) <= k1 - k0:
					near = true
					break
			if near:
				race["xzones"] = race.get("xzones", []) + [j["zone"]]
				race["no_crest"] = race.get("no_crest", []) + [[j["J"], float(j["reach"]) + 250.0]]



# --- Talbrücken (seit 2.36) -------------------------------------------------------------------------------------------

const VIA_RISE := 235.0  # Anstieg einer Talbrücke (länger als bei den Kuppen: höher, und man hebt oben nicht ab)
const VIA_LEN := 1150.0  # so lang muss eine Kuppe mindestens sein


## Mal höher: auf jedem zweiten Ringstück mit einer langen Kuppe (ab VIA_LEN) wird die längste eine Talbrücke, 12-14,5 m
## hoch auf Pfeilern (interchange.viaducts; track_builder baut dort keinen Damm), mit einem See darunter (die Landschaft
## legt ihn an, landscape._plan_sites). Kein See, wo Häuser oder Straßen einer Stadt in der Nähe sind. Liefert die Seen
## [{pos (x, z), r, h}].
static func _plan_viaducts(segments: Array, cities: Array, ramps: Array) -> Array:
	if OS.get_cmdline_user_args().has("--noix"):
		return []  # Test: Welt wie vor 2.36 (Vorher-Bilder)
	var near_pts := []
	for c in cities:
		for rd in c["roads"]:
			for q in rd[0]:
				near_pts.append(q)
		for q in c.get("bld_world", PackedVector2Array()):
			near_pts.append(q)
	for r in ramps:
		for q in _ramp_pts(r):
			near_pts.append(Vector2(q.x, q.z))
	var lakes := []
	var count := 0
	for sg in segments:
		if sg.get("ring", 0) > 1 or not sg["race"].has("crests"):
			continue
		var race: Dictionary = sg["race"]
		var pts: Array = race["pts"]
		var cum := [0.0]
		for k in pts.size() - 1:
			cum.append(cum[k] + (pts[k] as Vector3).distance_to(pts[k + 1]))
		var total: float = cum[-1]
		var best := -1
		var best_len := 0.0
		for ci in race["crests"].size():
			var cl: float = (float(race["crests"][ci][1]) - float(race["crests"][ci][0])) * total
			if cl > best_len:
				best_len = cl
				best = ci
		if best < 0 or best_len < VIA_LEN:
			continue
		count += 1
		if count % 2 == 0:
			continue  # nicht überall: dazwischen bleiben die Kuppen auf Dämmen
		var cr: Array = race["crests"][best]
		var rng := RandomNumberGenerator.new()
		rng.seed = int(race["seed"]) * 17 + 3
		var h := rng.randf_range(12.0, 14.5)
		cr[2] = h
		cr.append(VIA_RISE)
		race["viaducts"] = [[cr[0], cr[1]]]
		# See unter der Mitte, so groß, wie die Brücke hoch genug ist
		var md: float = (float(cr[0]) + float(cr[1])) / 2.0 * total
		var mid: Vector3 = pts[0]
		for k in pts.size() - 1:
			if md >= cum[k] and md <= cum[k + 1]:
				mid = (pts[k] as Vector3).lerp(pts[k + 1], (md - cum[k]) / maxf(cum[k + 1] - cum[k], 0.01))
		var r_l := minf(175.0, (best_len - 2.0 * VIA_RISE) / 2.0 - 30.0)
		if r_l < 70.0:
			continue
		var m2 := Vector2(mid.x, mid.z)
		var ok := true
		for q in near_pts:
			if m2.distance_to(q) < r_l + 90.0:
				ok = false
				break
		if ok:
			lakes.append({"pos": m2, "r": r_l, "h": h})
	return lakes



# --- Einschnitte (seit 2.36) ------------------------------------------------------------------------------------------

const CUT_LEN := 700.0
const CUT_CLEAR := 360.0  # so weit weg von Auffahrten


## Mal niedriger: auf jedem zweiten Ringstück ohne Talbrücke ein Abschnitt über Land (CUT_LEN, ohne Kuppe, weit weg von
## Auffahrten und Dreiecken), an dem das Gelände links und rechts 9-12 m hoch ansteigt: Böschungen, oben Felder, ein
## Feldweg auf einer Brücke darüber (landscape.gd baut beides). Der Ring selbst bleibt eben; über dem Abschnitt keine
## Plakate (Zone). Liefert [{pts (Mittellinie alle 10 m), h}].
static func _plan_cuts(segments: Array) -> Array:
	if OS.get_cmdline_user_args().has("--noix"):
		return []
	var cuts := []
	var count := 0
	for sg in segments:
		if sg.get("ring", 0) > 1:
			continue
		var race: Dictionary = sg["race"]
		var pts: Array = race["pts"]
		var c := Interchange.smooth_curve(pts)
		var total := c.get_baked_length()
		var blocked := []
		for cr in race.get("crests", []):
			blocked.append([float(cr[0]) * total - 200.0, float(cr[1]) * total + 200.0])
		for r in race.get("ramps", []):
			var dr := c.get_closest_offset(r["from"])
			blocked.append([dr - CUT_CLEAR, dr + CUT_CLEAR])
		for nc in race.get("no_crest", []):
			var dn := c.get_closest_offset(nc[0])
			blocked.append([dn - float(nc[1]), dn + float(nc[1])])
		var seq: Array = race.get("district_seq", [])
		var found := -1.0
		var st := 300.0
		while st + CUT_LEN < total - 300.0:
			var ok := true
			for b in blocked:
				if b[1] > st and b[0] < st + CUT_LEN:
					ok = false
			for k in range(int(st / 400.0), mini(int((st + CUT_LEN) / 400.0) + 1, seq.size())):
				if seq[k] != "land":
					ok = false
			if ok:
				found = st
				break
			st += 50.0
		if found < 0.0:
			continue
		count += 1
		if count % 2 == 0 and count > 2:
			continue  # nicht auf jedem Stück
		var rng := RandomNumberGenerator.new()
		rng.seed = int(race["seed"]) * 29 + 11
		var cp := []
		var d := found
		while d <= found + CUT_LEN + 0.01:
			cp.append(c.sample_baked(d))
			d += 10.0
		cuts.append({"pts": cp, "h": rng.randf_range(9.0, 12.0)})
		race["xzones"] = race.get("xzones", []) + [[cp[0], cp[-1]]]
	return cuts
