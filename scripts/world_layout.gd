extends RefCounted
## Open World "Mini-Deutschland": alle Strecken (ohne Drag) liegen außen an einem Autobahnring, ungefähr in der
## Himmelsrichtung ihrer Stadt (vom Mittelpunkt Deutschlands aus gesehen). Jede Stadt hat eine Ausfahrt
## (track_builder._plan_world_exit), die zum Ring zeigt; eine gerade Auffahrt verbindet sie mit der Autobahn.
## Der Ring besteht aus Stücken von gut 2,5 km, die wie Strecken gebaut und nachgeladen werden.
##
## Ergebnis (build()): {"cities": [{race_index, race, xf, center, radius, exit_world, start_world}],
##   "segments": [{race, center, radius}], "ring_r"}; alles in Weltkoordinaten (Meter, y = 0).

const Catalog := preload("res://scripts/catalog.gd")
const Track := preload("res://scripts/track_builder.gd")

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
			"phi": atan2(gz, gx) + i * 1e-4, "start_local": Track.frame_at(tr["curve"], tr["start"])["pos"], "polys_local": polys})
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
		c["ring_k"] = k
		c["exit_world"] = exit_w
		c["start_world"] = xf * c["start_local"]
		c["center"] = rp + N * (c["gap"] + c["far"] / 2.0)
		c["radius"] = maxf(c["far"] / 2.0, (c["lat1"] - c["lat0"]) / 2.0) + 200.0
		c["race"] = world_race(c["race_index"], xf)
		c["roads"] = []
		for pl in c["polys_local"]:
			var w2 := PackedVector2Array()
			for q in pl[0]:
				var wq: Vector3 = xf * q
				w2.append(Vector2(wq.x, wq.z))
			c["roads"].append([w2, pl[1]])
		ramps.append({"k": k, "from": rp, "end": exit_w, "name": Catalog.RACES[c["race_index"]].get("town", "")})
	# Ring in Stücke teilen; Grenzen nicht in der Nähe einer Auffahrt
	var ramp_k := {}
	for r in ramps:
		ramp_k[r["k"]] = r
	var segments := []
	var per := int(SEG_LEN / RING_STEP)
	var k0 := 0
	while k0 < m:
		var k1 := mini(k0 + per, m)
		if k1 < m:
			while _near_ramp(ramp_k, k1, m, 3):
				k1 += 1
		if m - k1 < per / 2:
			k1 = m  # Rest zum letzten Stück
		var pts := []
		for k in range(k0, k1 + 1):
			pts.append(ring[k % m])
		var rs := []
		for k in range(k0 + 1, k1):
			if ramp_k.has(k % m):
				rs.append(ramp_k[k % m])
		var mid: Vector3 = pts[pts.size() / 2]
		segments.append({"race": {"name": "Autobahn", "type": "autobahn", "seed": 9000 + segments.size(), "pts": pts,
			"districts": {"highway": 1.0}, "mood": MOOD, "ramps": rs, "world": true},
			"center": mid, "radius": (k1 - k0) * RING_STEP / 2.0 + 150.0})
		k0 = k1
	# Straßen für die Karten (Weltkoordinaten x, z): Ring, Auffahrten, alle Wege der Städte
	var roads := []
	var rl := PackedVector2Array()
	for q in ring:
		rl.append(Vector2(q.x, q.z))
	rl.append(rl[0])
	roads.append([rl, 0])
	for r in ramps:
		roads.append([PackedVector2Array([Vector2(r["from"].x, r["from"].z), Vector2(r["end"].x, r["end"].z)]), 1])
	for c in cities:
		roads.append_array(c["roads"])
	_add_keepout(cities, ring, ramps)
	_cache = {"cities": cities, "segments": segments, "ring_r": R, "ring": ring, "roads": roads}
	if OS.get_cmdline_user_args().has("--worldlog"):
		print("WELT Ring %.0f m (Umfang %.1f km), %d Städte, %d Stücke, Planung %d ms" % [R, TAU * R / 1000.0, cities.size(),
			segments.size(), Time.get_ticks_msec() - t0])
		for c in cities:
			print("  %-28s phi=%.2f gap=%.0f breite=%.0f tiefe=%.0f" % [Catalog.RACES[c["race_index"]]["name"], c["phi_w"], c["gap"],
				c["lat1"] - c["lat0"], c["far"]])
	return _cache


static func _near_ramp(ramp_k: Dictionary, k: int, m: int, w: int) -> bool:
	for dk in range(-w, w + 1):
		if ramp_k.has((k + dk + m) % m):
			return true
	return false


## Sperrflächen: jede Stadt bekommt die fremden Fahrbahnen in ihrer Nähe (Ring, alle Auffahrten, Straßen der
## Nachbarstädte) als Kreise in ihren eigenen Koordinaten (race["keepout"]); der Streckenbau stellt dort keine Häuser
## hin (track_builder Schritt 2: wie belegte Flächen). Sonst ragen Häuser aus echten Stadtplänen auf die Autobahn.
static func _add_keepout(cities: Array, ring: Array, ramps: Array) -> void:
	var ring_r: float = Track.HALF_W + Track.AB_EXTRA + Track.MED + Track.WALK + 3.0
	var lines := []  # [Weltpunkte, Radius, Stadt (eigene Straßen auslassen) oder -1]
	var rl := []
	for q in ring:
		rl.append(q)
	rl.append(ring[0])
	lines.append([rl, ring_r, -1])
	for r in ramps:
		lines.append([[r["from"], r["end"]], Track.HALF_W + Track.WALK + 2.0, -1])
	for c in cities:
		for road in c["roads"]:
			var pl := []
			for q in road[0]:
				pl.append(Vector3(q.x, 0.0, q.y))
			lines.append([pl, Track.HALF_W + Track.WALK + 2.0 if road[1] == 0 else 9.0, c["race_index"]])
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
						ko.append({"pos": inv * q, "r": ln[1], "ko": true})
		c["race"]["keepout"] = ko
