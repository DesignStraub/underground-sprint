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
			"phi": atan2(gz, gx) + i * 1e-4, "start_local": Track.frame_at(tr["curve"], tr["start"])["pos"], "polys_local": polys,
			"holes_local": Track.ground_holes(tr), "bld_local": _building_points(tr),
			"exit2_local": tr["world_exit2"]})
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
		c["race"]["no_ground"] = true  # Boden kommt von der Landschaft (Stadtmaske), kein hartes Quadrat in den Feldern
		c["roads"] = []
		for pl in c["polys_local"]:
			var w2 := PackedVector2Array()
			for q in pl[0]:
				var wq: Vector3 = xf * q
				w2.append(Vector2(wq.x, wq.z))
			c["roads"].append([w2, pl[1]])
		var bw := PackedVector2Array()
		for q in c["bld_local"]:
			var wq: Vector3 = xf * Vector3(q.x, 0.0, q.y)
			bw.append(Vector2(wq.x, wq.z))
		c["bld_world"] = bw
		ramps.append({"k": k, "from": rp, "end": exit_w, "name": Catalog.RACES[c["race_index"]].get("town", ""),
			"forest": Catalog.RACES[c["race_index"]].get("forest", false)})
	# Außenring um alle Städte und zweite Ausfahrten der Sprints (hinter dem Ziel) an einen der beiden Ringe
	# Mitte: Kreisel mit vier Diagonalen zum inneren Ring (Querverbindungen durch die Mitte), vor den Ziel-Ausfahrten
	# geplant, damit die ihnen am Ring ausweichen
	var mid := _plan_middle(ring, ramps)
	var oring := _outer_ring(cities, R)
	var oramps := []
	_connect_ends(cities, ring, oring, ramps, oramps)
	for c in cities:
		if not (c["exit2_local"] as Dictionary).is_empty() and not c.has("exit2_ring"):
			c["race"]["tail_join"] = true  # Ziel eingeschlossen: die Straße dahinter führt zurück auf die Strecke
	var segments := _split(ring, ramps, 9000, 0)
	var osegs := _split(oring, oramps, 9500, 1)
	segments.append_array(osegs)
	var msegs := _split(mid["rb"], mid["rb_ramps"], 9800, 2, "Kreisel")
	for i in mid["arms"].size():
		msegs.append_array(_split_open(mid["arms"][i], 9900 + i * 50, 3 + i, "Querspange"))
	segments.append_array(msegs)
	# Autobahn über Land, Stadt nur um die Auffahrten der Städte und am Kreisel (seit 2.29; davor säumten Hochhäuser
	# die ganze Autobahn, und die Welt sah überall gleich aus). Die Landschaft (landscape.gd) fragt dasselbe ab.
	var urban := []
	for r in ramps + oramps:
		if not r.get("wide", false) and not r.get("forest", false):
			urban.append(r["from"])
	var rbc := Vector3.ZERO
	for q in mid["rb"]:
		rbc += q / float(mid["rb"].size())
	urban.append(rbc)
	for sg in segments:
		sg["race"]["district_seq"] = _district_seq(sg["race"]["pts"], urban)
		sg["race"]["no_ground"] = true
		if sg.get("ring", 0) <= 1:
			_ring_crests(sg)
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
	for line in [mid["rb"] + [mid["rb"][0]]] + mid["arms"]:
		var ml := PackedVector2Array()
		for q in line:
			ml.append(Vector2(q.x, q.z))
		roads.append([ml, 0])
	for r in ramps + oramps + mid["rb_ramps"]:
		var rp2 := PackedVector2Array()
		for q in _ramp_pts(r):
			rp2.append(Vector2(q.x, q.z))
		roads.append([rp2, 1])
	for c in cities:
		roads.append_array(c["roads"])
	_add_keepout(cities, ring, ramps + oramps, oring, osegs)
	_middle_keepout(msegs, ring, mid)
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
	_cache = {"cities": cities, "segments": segments, "ring_r": R, "ring": ring, "oring": oring, "roads": roads, "holes": holes,
		"urban": urban}
	if OS.get_cmdline_user_args().has("--worldlog"):
		var olen := 0.0
		for k in oring.size():
			olen += (oring[k] as Vector3).distance_to(oring[(k + 1) % oring.size()])
		print("WELT Ring %.0f m (Umfang %.1f km), Außenring %.1f km, %d Städte, %d Stücke, Planung %d ms" % [R, TAU * R / 1000.0,
			olen / 1000.0, cities.size(), segments.size(), Time.get_ticks_msec() - t0])
		for c in cities:
			if not c["exit2_local"].is_empty():
				print("  Ziel-Ausfahrt %-26s -> %s" % [Catalog.RACES[c["race_index"]]["name"],
					["innerer Ring", "Außenring"][c["exit2_ring"]] if c.has("exit2_ring") else "zurück auf die eigene Strecke"])
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


const URBAN_R := 420.0  # so weit um eine Auffahrt (und um den Kreisel) ist die Autobahn Stadt


## Viertel je 400 m eines Autobahnstücks: "highway" (Stadt) nahe einer Auffahrt, sonst "land"
static func _district_seq(pts: Array, urban: Array) -> Array:
	var seq := []
	var acc := 0.0
	var next := 200.0  # Mitte des ersten Abschnitts
	for k in pts.size() - 1:
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[k + 1]
		var l := a.distance_to(b)
		while next <= acc + l:
			var q := a.lerp(b, (next - acc) / maxf(l, 0.001))
			seq.append("highway" if is_urban(q, urban) else "land")
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
	# Lage der Auffahrten auf dem Stück (Meter)
	var ramp_d := []
	for r in race["ramps"]:
		var best := 1e9
		var bd := 0.0
		for k in pts.size():
			var dd := Vector2(pts[k].x - r["from"].x, pts[k].z - r["from"].z).length()
			if dd < best:
				best = dd
				bd = cum[k]
		ramp_d.append(bd)
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
		for rd in ramp_d:
			if rd > a - 300.0 and rd < e + 300.0:
				# Auffahrt im Abschnitt: nur die längere Seite davon nutzen
				if rd - a > e - rd:
					e = rd - 300.0
				else:
					a = rd + 300.0
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


## Ring in Stücke teilen (Grenzen nicht in der Nähe einer Auffahrt). ring_i: 0 innen, 1 außen
static func _split(ring: Array, ramps: Array, seed0: int, ring_i: int, name := "") -> Array:
	var m := ring.size()
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
		segments.append({"race": {"name": name if name != "" else ("Autobahn" if ring_i == 0 else "Außenring"), "type": "autobahn", "seed": seed0 + segments.size(),
			"pts": pts, "districts": {"highway": 1.0}, "mood": MOOD, "ramps": rs, "world": true},
			"center": mid, "radius": (k1 - k0) * RING_STEP / 2.0 + 150.0, "ring": ring_i})
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
						"name": Catalog.RACES[c["race_index"]].get("town", ""), "forest": Catalog.RACES[c["race_index"]].get("forest", false)}
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
static func _add_keepout(cities: Array, ring: Array, ramps: Array, oring: Array, osegs: Array) -> void:
	var ring_r: float = Track.HALF_W + Track.AB_EXTRA + Track.MED + Track.WALK + 3.0
	var lines := []  # [Weltpunkte, Radius, Stadt (eigene Straßen auslassen) oder -1]
	var rl := []
	for q in ring:
		rl.append(q)
	rl.append(ring[0])
	lines.append([rl, ring_r, -1])
	var orl := oring.duplicate()
	orl.append(oring[0])
	lines.append([orl, ring_r, -2])
	for r in ramps:
		# Bögen zu den Ziel-Ausfahrten: etwas mehr Platz (die Kreise sitzen auf den Sehnen des Bogens)
		lines.append([_ramp_pts(r), Track.HALF_W + Track.WALK + (8.0 if r.has("c1") else 2.0) + (Track.AB_EXTRA + 3.0 if r.get("wide", false) else 0.0), -1])
	for c in cities:
		for road in c["roads"]:
			var pl := []
			for q in road[0]:
				pl.append(Vector3(q.x, 0.0, q.y))
			lines.append([pl, Track.HALF_W + Track.WALK + 2.0 if road[1] == 0 else 12.0, c["race_index"]])
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
	# Außenring: seine Häuser dürfen nicht auf die Straßen der Städte (der innere Ring liegt weit genug weg)
	for sg in osegs:
		var ctr2: Vector3 = sg["center"]
		var reach2: float = sg["radius"] + 300.0
		var ko2 := []
		for ln in lines:
			if ln[2] == -2:
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
