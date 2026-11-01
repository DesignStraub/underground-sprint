extends RefCounted
## Erzeugt eine Sprintstrecke durch eine nächtliche Stadt aus einem Seed.
## Hauptstraße mit Gehweg, Abkürzungen (kurvige Gasse, Seesprung über eine Schanze), Seitenstraßen mit Ampeln,
## Bahnübergang mit Rampe, Baustellen, Stadtviertel mit unterschiedlicher Bebauung, Wahrzeichen, Laternen.
##
## Wege ("paths"): Index 0 ist die Hauptstraße, danach Abkürzungen und Seitenstraßen. Jeder Weg hat eine eigene
## Mittellinie (Curve3D). Rennfortschritt wird immer in Metern der Hauptstraße gemessen.

const Builder := preload("res://scripts/car_builder.gd")
const Knockable := preload("res://scripts/knockable.gd")
const RailCrossing := preload("res://scripts/rail_crossing.gd")
const ROAD_SHADER := preload("res://shaders/road.gdshader")
const BUILDING_SHADER := preload("res://shaders/building.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")
const RAMP_SHADER := preload("res://shaders/ramp.gdshader")
const BLINK_SHADER := preload("res://shaders/blink.gdshader")
const LIGHT_SHADER := preload("res://shaders/traffic_light.gdshader")

const HALF_W := 9.0  # 4 Spuren à 4,5 m
const LANES := [-6.75, -2.25, 2.25, 6.75]
const WALK := 5.0  # Gehwegbreite
const CURB_H := 0.2
const WALL_H := 12.0  # hoch genug, dass man auch im Sprung nicht rausfliegt
const LAMP_STEP := 38.0
const RAMP_H := 1.7
const RAIL_RAMP_H := 3.7
const SC_HALF := 5.0
const ALLEY_HALF := 5.0
const SPUR_HALF := 6.0
const SIGNS := ["MOTEL", "24H", "TUNING", "BAR", "HOTEL", "NOODLES", "CLUB", "GARAGE", "PARTS", "NEON"]
const SHOPS := ["PIZZA", "DÖNER", "KIOSK", "BÄCKEREI", "APOTHEKE", "FRISEUR", "TATTOO", "AUTOTEILE",
	"WÄSCHEREI", "SPÄTI", "SUSHI", "BURGER", "HANDY SHOP", "BLUMEN", "JUWELIER", "SPIELHALLE", "MUSIK",
	"SNEAKER", "NAILS", "WETTBÜRO", "CAFE", "BAR", "TUNING", "REIFEN", "VIDEOTHEK", "ASIA IMBISS",
	"BUCHLADEN", "GAMES", "FITNESS", "OPTIKER", "SHISHA", "PFANDHAUS"]
const BRANDS := ["KAIZEN MOTORS", "VORTEX GT-R", "NOS", "MIRAI 240R", "TURBO COLA", "ONE HUMANITY",
	"NEON NIGHTS", "SPEED FM", "DRIFT KINGS", "UNDERGROUND"]
const NEON := [Color(1, 0.1, 0.6), Color(0.1, 0.8, 1), Color(0.7, 0.2, 1), Color(1, 0.5, 0.1), Color(0.2, 1, 0.4), Color(1, 0.9, 0.3)]

## Stadtviertel: Bebauung, Fassadenstile (siehe building.gdshader), Farben, Ausstattung
const DISTRICTS := {
	"downtown": {"shop": 0.3, "low": [6.0, 10.0], "tall": [24.0, 90.0], "tall_p": 0.7, "styles": [0, 1, 3, 3],
		"tints": [Color(0.08, 0.09, 0.11), Color(0.13, 0.14, 0.17), Color(0.05, 0.07, 0.1)], "lit": 0.45,
		"trees": 0.1, "billboard": 0.3, "neon_edge": 0.3, "lamp": Color(0.8, 0.88, 1.0)},
	"shops": {"shop": 0.8, "low": [5.0, 9.0], "tall": [12.0, 26.0], "tall_p": 0.35, "styles": [0, 4],
		"tints": [Color(0.22, 0.12, 0.09), Color(0.17, 0.16, 0.14), Color(0.11, 0.11, 0.13)], "lit": 0.5,
		"trees": 0.35, "billboard": 0.15, "neon_edge": 0.1, "lamp": Color(1.0, 0.68, 0.35)},
	"residential": {"shop": 0.2, "low": [9.0, 16.0], "tall": [16.0, 30.0], "tall_p": 0.3, "styles": [4, 4, 0],
		"tints": [Color(0.28, 0.13, 0.08), Color(0.3, 0.25, 0.18), Color(0.22, 0.2, 0.18)], "lit": 0.55,
		"trees": 0.6, "billboard": 0.0, "neon_edge": 0.0, "lamp": Color(1.0, 0.75, 0.45)},
	"industrial": {"shop": 0.05, "low": [7.0, 12.0], "tall": [12.0, 22.0], "tall_p": 0.2, "styles": [2, 2, 0],
		"tints": [Color(0.15, 0.17, 0.18), Color(0.2, 0.18, 0.14), Color(0.1, 0.14, 0.15)], "lit": 0.3,
		"trees": 0.0, "billboard": 0.1, "neon_edge": 0.0, "lamp": Color(0.9, 0.95, 1.0), "containers": true},
}
const DISTRICT_LEN := 380.0


static func build(race: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = race["seed"]
	var root := Node3D.new()
	root.name = "Track"

	var gen := _centerline(race, rng)
	var pts: Array = gen["pts"]
	var curve := Curve3D.new()
	curve.bake_interval = 1.0
	for i in pts.size():
		var prev: Vector3 = pts[maxi(i - 1, 0)]
		var nxt: Vector3 = pts[mini(i + 1, pts.size() - 1)]
		var t: Vector3 = (nxt - prev) * 0.22
		curve.add_point(pts[i], -t, t)
	var length := curve.get_baked_length()

	var track := {
		"node": root, "curve": curve, "length": length, "start": 25.0, "finish": length - 80.0,
		"blocks": [], "ramps": [], "lakes": [], "zones": [], "crossing": null, "crossing_d": -1.0,
		"districts": [], "parks": [],
		"paths": [{"id": 0, "kind": "main", "curve": curve, "half_w": HALF_W, "length": length, "from": 0.0, "to": length}],
	}
	var weights: Dictionary = race.get("districts", {"downtown": 1.0})
	var dd := 0.0
	while dd < length + DISTRICT_LEN:
		track["districts"].append(_pick(weights, rng))
		dd += DISTRICT_LEN

	for b in gen["bulges"]:
		_plan_shortcut(track, b, rng)
	_plan_crossing(track, rng)
	_plan_spurs(track, rng)

	_build_road(root, track)
	for p in track["paths"]:
		if p["id"] != 0:
			_build_branch(root, track, p, rng)
	_build_lakes(root, track, rng)
	_build_ramps(root, track)
	if track["crossing_d"] > 0.0:
		var rc := RailCrossing.new()
		root.add_child(rc)
		rc.setup(frame_at(curve, track["crossing_d"]), track["crossing_d"], HALF_W, WALK)
		track["crossing"] = rc
	_build_roadworks(root, track, rng)
	var occupied := _build_landmarks(root, track, rng)
	_build_city(root, track, rng, occupied)
	_build_lamps(root, track)
	_build_props(root, track, rng)
	_build_steam(root, track, rng)
	_gate(root, curve, track["start"] + 12.0, "START", Color(0.2, 1.0, 0.4))
	_gate(root, curve, track["finish"], "ZIEL", Color(1.0, 0.2, 0.4))

	# Boden (sichtbar) + Boden-Kollision nur für umherfliegende Teile
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6000, 6000)
	ground.mesh = pm
	ground.material_override = Builder.mat(Color(0.03, 0.03, 0.035), 0.0, 0.9)
	ground.position = Vector3(0, -0.05, 0)
	root.add_child(ground)
	var gb := StaticBody3D.new()
	gb.collision_layer = Knockable.GROUND
	gb.collision_mask = 0
	var gs := CollisionShape3D.new()
	gs.shape = WorldBoundaryShape3D.new()
	gb.add_child(gs)
	root.add_child(gb)
	return track


static func _pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in weights:
		total += weights[k]
	var r := rng.randf() * total
	for k in weights:
		r -= weights[k]
		if r <= 0.0:
			return k
	return weights.keys()[0]


static func _dir(h: float) -> Vector3:
	return Vector3(-sin(h), 0, -cos(h))


static func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


## Mittellinie der Hauptstraße. An geplanten Stellen macht sie einen Bogen ("bulge"),
## die Sehne dieses Bogens wird später zur Abkürzung.
static func _centerline(race: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var pts := [Vector3.ZERO]
	var heading := 0.0
	var p := _dir(heading) * 160.0
	pts.append(p)
	var bulges := []
	var plan: Dictionary = race.get("bulges", {})
	for i in race["segments"]:
		if plan.has(i):
			var kind: String = plan[i]
			var a := 150.0 if kind == "lake" else 120.0
			p += _dir(heading) * 80.0
			pts.append(p)
			var p0 := p
			var side := -signf(heading) if absf(heading) > 0.15 else (1.0 if rng.randf() < 0.5 else -1.0)
			var defl := deg_to_rad(60.0) * side
			var p1 := p0 + _dir(heading + defl) * a
			var p2 := p1 + _dir(heading - defl) * a
			pts.append(p1)
			pts.append(p2)
			p = p2 + _dir(heading) * 80.0
			pts.append(p)
			bulges.append({"kind": kind, "p0": p0, "p1": p1, "p2": p2, "heading": heading, "a": a})
			continue
		heading = clampf(heading + deg_to_rad(rng.randf_range(-race["max_turn"], race["max_turn"])), -1.3, 1.3)
		p += _dir(heading) * rng.randf_range(70.0, 150.0)
		pts.append(p)
	p += _dir(heading) * 200.0
	pts.append(p)
	return {"pts": pts, "bulges": bulges}


static func frame_at(curve: Curve3D, d: float) -> Dictionary:
	var len := curve.get_baked_length()
	var a := curve.sample_baked(clampf(d - 1.0, 0.0, len))
	var b := curve.sample_baked(clampf(d + 1.0, 0.0, len))
	var fwd := (b - a)
	fwd.y = 0.0
	fwd = fwd.normalized()
	if fwd == Vector3.ZERO:
		fwd = Vector3.FORWARD
	return {"pos": curve.sample_baked(clampf(d, 0.0, len)), "fwd": fwd, "right": Vector3(-fwd.z, 0, fwd.x)}


## Transform an Streckenposition d, seitlich versetzt um lateral, Blick in Fahrtrichtung.
static func xform_at(curve: Curve3D, d: float, lateral: float) -> Transform3D:
	var f := frame_at(curve, d)
	var pos: Vector3 = f["pos"] + f["right"] * lateral
	var basis := Basis.looking_at(f["fwd"], Vector3.UP)
	return Transform3D(basis, Vector3(pos.x, 0, pos.z))


# --- Abfragen für Fahrzeuge -----------------------------------------------------

## Auf welchem Weg steht pos? Liefert {path, d, lat, score}; score < 0 heißt "auf der Fahrbahn".
static func locate(track: Dictionary, pos: Vector3) -> Dictionary:
	var best := {}
	var best_score := 1e9
	for p in track["paths"]:
		var c: Curve3D = p["curve"]
		var d := c.get_closest_offset(pos)
		var f := frame_at(c, d)
		var dist := _flat(pos - f["pos"]).length()
		var lat: float = (pos - f["pos"]).dot(f["right"])
		var score: float = dist - p["half_w"]
		if p["id"] != 0:
			score += 0.5  # bei Überlappung (Einmündungen) gilt die Hauptstraße
		if score < best_score:
			best_score = score
			best = {"path": p, "d": d, "lat": lat, "score": score}
	return best


## Rennfortschritt in Metern der Hauptstraße
static func race_progress(loc: Dictionary) -> float:
	var p: Dictionary = loc["path"]
	if p["id"] == 0:
		return loc["d"]
	return lerpf(p["from"], p["to"], clampf(loc["d"] / p["length"], 0.0, 1.0))


## Bodenhöhe und Wasser an einer Weg-Position (Rampen, Gehweg)
static func ground_path(track: Dictionary, path_id: int, d: float, lat: float, score := -1.0) -> Dictionary:
	var h := 0.0
	var on_ramp := false
	if path_id == 0 and score > 0.2:
		h = CURB_H
	for r in track["ramps"]:
		if r["path"] == path_id and d >= r["d0"] and d <= r["d1"] and lat >= r["lat0"] and lat <= r["lat1"]:
			var rh: float = r["h"] * (d - r["d0"]) / (r["d1"] - r["d0"])
			if rh > h:
				h = rh
				on_ramp = true
	return {"h": h, "ramp": on_ramp, "water": false}


static func ground(track: Dictionary, loc: Dictionary, pos: Vector3) -> Dictionary:
	var p: Dictionary = loc["path"]
	var g := ground_path(track, p["id"], loc["d"], loc["lat"], loc["score"])
	for lk in track["lakes"]:
		var l: Vector3 = pos - lk["center"]
		if absf(l.dot(lk["au"])) < lk["hu"] and absf(l.dot(lk["av"])) < lk["hv"]:
			var in_gap: bool = loc["d"] > lk["gap0"] and loc["d"] < lk["gap1"]
			var on_causeway: bool = p["id"] == lk["path"] and absf(loc["lat"]) <= p["half_w"] + 0.4 and not in_gap
			if not on_causeway:
				g["water"] = true
	return g


# --- Planung ----------------------------------------------------------------

static func _in_zone(track: Dictionary, d: float, margin: float) -> bool:
	for z in track["zones"]:
		if d > z["from"] - margin and d < z["to"] + margin:
			return true
	return false


## Abstand zur nächsten Nebenstraße (Abkürzung/Seitenstraße) minus deren halbe Breite
static func _branch_clearance(track: Dictionary, pos: Vector3) -> float:
	var best := 1e9
	for p in track["paths"]:
		if p["id"] == 0:
			continue
		var c: Curve3D = p["curve"]
		var q := c.get_closest_point(pos)
		best = minf(best, _flat(pos - q).length() - p["half_w"])
	return best


static func _main_clearance(track: Dictionary, pos: Vector3) -> float:
	var c: Curve3D = track["curve"]
	return _flat(pos - c.get_closest_point(pos)).length() - HALF_W


static func _rail_clearance(track: Dictionary, pos: Vector3) -> float:
	if track["crossing_d"] < 0.0:
		return 1e9
	var f := frame_at(track["curve"], track["crossing_d"])
	return absf((pos - f["pos"]).dot(f["fwd"])) - 3.0


static func _in_lake(track: Dictionary, pos: Vector3, margin: float) -> bool:
	for lk in track["lakes"]:
		var l: Vector3 = pos - lk["center"]
		if absf(l.dot(lk["au"])) < lk["hu"] + margin and absf(l.dot(lk["av"])) < lk["hv"] + margin:
			return true
	return false


static func _plan_shortcut(track: Dictionary, b: Dictionary, rng: RandomNumberGenerator) -> void:
	var curve: Curve3D = track["curve"]
	var a: float = b["a"]
	var p0: Vector3 = b["p0"]
	var du := _dir(b["heading"])
	var dv := Vector3(-du.z, 0, du.x)
	var vb := signf((b["p1"] - p0).dot(dv))  # Richtung zur Ausbuchtung der Hauptstraße
	var w := 1.0 if rng.randf() < 0.5 else -1.0
	var lake: bool = b["kind"] == "lake"
	var half := SC_HALF if lake else ALLEY_HALF
	var uv: Array
	if lake:
		uv = [[0.0, 0.0], [0.16, 6.0 * w], [0.3, -4.0 * w], [0.4, 0.0], [0.5, 0.0], [0.6, 0.0], [0.7, 0.0],
			[0.78, 0.0], [0.9, 5.0 * w], [1.0, 0.0]]
	else:
		uv = [[0.0, 0.0], [0.18, 3.5 * w], [0.36, -3.5 * w], [0.54, 3.5 * w], [0.72, -3.5 * w], [0.88, 2.5 * w], [1.0, 0.0]]
	var pts := []
	for e in uv:
		pts.append(p0 + du * (e[0] * a) + dv * e[1])
	var sc := Curve3D.new()
	sc.bake_interval = 1.0
	for i in pts.size():
		var prev: Vector3 = pts[maxi(i - 1, 0)]
		var nxt: Vector3 = pts[mini(i + 1, pts.size() - 1)]
		var t: Vector3 = (nxt - prev) * 0.2
		sc.add_point(pts[i], -t, t)
	var path := {"id": track["paths"].size(), "kind": b["kind"], "curve": sc, "half_w": half,
		"length": sc.get_baked_length(), "from": curve.get_closest_offset(p0), "to": curve.get_closest_offset(b["p2"]),
		"closed": false, "p0": p0, "p1": b["p1"], "p2": b["p2"]}
	track["paths"].append(path)
	track["zones"].append({"from": path["from"] - 30.0, "to": path["from"] + 45.0})
	track["zones"].append({"from": path["to"] - 45.0, "to": path["to"] + 30.0})
	if lake:
		var r0 := sc.get_closest_offset(p0 + du * (0.47 * a))
		var r1 := sc.get_closest_offset(p0 + du * (0.535 * a))
		var g1 := sc.get_closest_offset(p0 + du * (0.68 * a))
		track["ramps"].append({"path": path["id"], "d0": r0, "d1": r1, "lat0": -half, "lat1": half, "h": RAMP_H})
		track["lakes"].append({"path": path["id"], "center": p0 + du * (0.6 * a) + dv * vb * 10.0,
			"au": du, "av": dv * vb, "hu": 0.24 * a, "hv": 38.0, "gap0": r1, "gap1": g1})
		track["parks"].append([p0, b["p1"], b["p2"]])


## Bahnübergang auf einem geraden Stück, mit Rampe auf der rechten Außenspur
static func _plan_crossing(track: Dictionary, rng: RandomNumberGenerator) -> void:
	var curve: Curve3D = track["curve"]
	var L: float = track["length"]
	for attempt in 120:
		var d := rng.randf_range(0.28, 0.75) * L
		if _in_zone(track, d, 140.0):
			continue
		var f0 := frame_at(curve, d - 45.0)
		var f1 := frame_at(curve, d + 80.0)
		if (f0["fwd"] as Vector3).angle_to(f1["fwd"]) > 0.12 or _in_zone(track, d + 80.0, 30.0):
			continue
		track["crossing_d"] = d
		track["zones"].append({"from": d - 80.0, "to": d + 30.0})
		track["ramps"].append({"path": 0, "d0": d - 23.0, "d1": d - 9.5, "lat0": 4.6, "lat1": HALF_W - 0.1, "h": RAIL_RAMP_H})
		track["blocks"].append({"from": d - 70.0, "to": d + 5.0, "lane": LANES[3]})
		return


## Kreuzungen: kurze Seitenstraßen nach links und rechts (Sackgassen) mit Ampeln und Zebrastreifen
static func _plan_spurs(track: Dictionary, rng: RandomNumberGenerator) -> void:
	var curve: Curve3D = track["curve"]
	var L: float = track["length"]
	var count := 2 + int(L / 1400.0)
	for k in count:
		for attempt in 40:
			var d := rng.randf_range(0.1, 0.92) * L
			if _in_zone(track, d, 70.0):
				continue
			var f0 := frame_at(curve, d - 25.0)
			var f1 := frame_at(curve, d + 25.0)
			if (f0["fwd"] as Vector3).angle_to(f1["fwd"]) > 0.15:
				continue
			var f := frame_at(curve, d)
			for side in [-1.0, 1.0]:
				var sc := Curve3D.new()
				sc.bake_interval = 1.0
				sc.add_point(f["pos"])
				sc.add_point(f["pos"] + f["right"] * side * (HALF_W + WALK + 34.0))
				track["paths"].append({"id": track["paths"].size(), "kind": "spur", "curve": sc, "half_w": SPUR_HALF,
					"length": sc.get_baked_length(), "from": d, "to": d, "closed": true, "side": side})
			track["zones"].append({"from": d - 20.0, "to": d + 20.0})
			break


# --- Straßen ----------------------------------------------------------------

static func _road_mesh(root: Node3D, st: SurfaceTool, lanes: float, width: float, cobble: float, y := 0.0) -> MeshInstance3D:
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := ShaderMaterial.new()
	m.shader = ROAD_SHADER
	mi.material_override = m
	mi.set_instance_shader_parameter("lanes", lanes)
	mi.set_instance_shader_parameter("road_w", width)
	mi.set_instance_shader_parameter("cobble", cobble)
	mi.position.y = y
	root.add_child(mi)
	return mi


static func _wall_shape(walls: StaticBody3D, a: Vector3, b: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.6, WALL_H, a.distance_to(b) + 0.6)
	cs.shape = bs
	var dir := (b - a)
	dir.y = 0.0
	cs.transform = Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), (a + b) / 2 + Vector3(0, WALL_H / 2, 0))
	walls.add_child(cs)


static func _build_road(root: Node3D, track: Dictionary) -> void:
	var curve: Curve3D = track["curve"]
	var length: float = track["length"]
	var road := SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walk := SurfaceTool.new()
	walk.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walls := StaticBody3D.new()
	root.add_child(walls)

	var step := 3.0
	var d := 0.0
	var prev := {}
	var outer := HALF_W + WALK
	while d <= length:
		var f := frame_at(curve, d)
		var c: Vector3 = f["pos"]
		var r: Vector3 = f["right"]
		var cur := {
			"l": c - r * HALF_W, "r": c + r * HALF_W,
			"lw": c - r * (outer + 0.3), "rw": c + r * (outer + 0.3),
			"lo": c - r * outer, "ro": c + r * outer,
			"lm": c - r * (HALF_W + WALK * 0.5), "rm": c + r * (HALF_W + WALK * 0.5), "d": d,
		}
		if not prev.is_empty():
			_strip(road, prev["l"], prev["r"], cur["l"], cur["r"], prev["d"], d)
			var up := Vector3(0, CURB_H, 0)
			# Gehweg und Wand nur dort, wo keine Nebenstraße abzweigt
			if _branch_clearance(track, (prev["lm"] + cur["lm"]) / 2) > WALK * 0.5 + 0.5:
				_strip(walk, prev["lo"] + up, prev["l"] + up, cur["lo"] + up, cur["l"] + up, 0.0, 0.0)
				_strip_v(walk, prev["l"], cur["l"], CURB_H, true)
			if _branch_clearance(track, (prev["rm"] + cur["rm"]) / 2) > WALK * 0.5 + 0.5:
				_strip(walk, prev["r"] + up, prev["ro"] + up, cur["r"] + up, cur["ro"] + up, 0.0, 0.0)
				_strip_v(walk, prev["r"], cur["r"], CURB_H, false)
			for side in ["lw", "rw"]:
				if _branch_clearance(track, (prev[side] + cur[side]) / 2) > 1.0:
					_wall_shape(walls, prev[side], cur[side])
		prev = cur
		d += step

	_road_mesh(root, road, 4.0, HALF_W * 2.0, 0.0)
	walk.generate_normals()
	var walk_mi := MeshInstance3D.new()
	walk_mi.mesh = walk.commit()
	walk_mi.material_override = Builder.mat(Color(0.16, 0.16, 0.17), 0.0, 0.7)
	root.add_child(walk_mi)


## Horizontaler Streifen; a/b = vorherige Kante links/rechts, c/d = aktuelle.
static func _strip(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, v0: float, v1: float) -> void:
	# Von oben gesehen im Uhrzeigersinn (Godot-Vorderseite), Fahrtrichtung ist "oben"
	var verts := [[a, Vector2(0, v0)], [c, Vector2(0, v1)], [b, Vector2(1, v0)],
		[b, Vector2(1, v0)], [c, Vector2(0, v1)], [d, Vector2(1, v1)]]
	for vv in verts:
		st.set_uv(vv[1])
		st.add_vertex(vv[0])


static func _strip_v(st: SurfaceTool, a: Vector3, b: Vector3, h: float, flip: bool) -> void:
	var up := Vector3(0, h, 0)
	var tris := [a, b + up, b, a, a + up, b + up] if flip else [a, b, b + up, a, b + up, a + up]
	for v in tris:
		st.set_uv(Vector2.ZERO)
		st.add_vertex(v)


## Abkürzung oder Seitenstraße: Fahrbahn, Wände, Ausstattung
static func _build_branch(root: Node3D, track: Dictionary, p: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Curve3D = p["curve"]
	var len: float = p["length"]
	var half: float = p["half_w"]
	var kind: String = p["kind"]
	var gap0 := 1e9
	var gap1 := -1e9
	for lk in track["lakes"]:
		if lk["path"] == p["id"]:
			gap0 = lk["gap0"]
			gap1 = lk["gap1"]
	var road := SurfaceTool.new()
	road.begin(Mesh.PRIMITIVE_TRIANGLES)
	var walls := StaticBody3D.new()
	root.add_child(walls)
	var brick := ShaderMaterial.new()
	brick.shader = BUILDING_SHADER
	var hedge := Builder.mat(Color(0.04, 0.16, 0.06), 0.0, 0.9)
	var concrete := Builder.mat(Color(0.3, 0.3, 0.31), 0.0, 0.85)
	var step := 2.0
	var d := 0.0
	var prev := {}
	while d <= len + 0.01:
		var f := frame_at(c, d)
		var cp: Vector3 = f["pos"]
		var r: Vector3 = f["right"]
		var cur := {"l": cp - r * half, "r": cp + r * half, "lw": cp - r * (half + 0.3), "rw": cp + r * (half + 0.3), "d": d}
		if not prev.is_empty():
			var mid: Vector3 = (prev["l"] + cur["r"]) / 2
			var in_gap: bool = d > gap0 and prev["d"] < gap1
			if _main_clearance(track, mid) > -0.3 and not in_gap:
				_strip(road, prev["l"], prev["r"], cur["l"], cur["r"], prev["d"], d)
			for side in ["lw", "rw"]:
				var wm: Vector3 = (prev[side] + cur[side]) / 2
				if _main_clearance(track, wm) < WALK + 0.4 or (d > gap0 - 1.0 and prev["d"] < gap1 + 1.0):
					continue
				_wall_shape(walls, prev[side], cur[side])
				var seg: Vector3 = cur[side] - prev[side]
				var basis := Basis.looking_at(seg.normalized(), Vector3.UP)
				if kind == "alley":
					var bw := MeshInstance3D.new()
					bw.mesh = Builder.box(Vector3(0.5, 4.5, seg.length() + 0.1))
					bw.material_override = brick
					bw.transform = Transform3D(basis, wm + Vector3(0, 2.25, 0))
					bw.set_instance_shader_parameter("style", 4.0)
					bw.set_instance_shader_parameter("tint", Vector3(0.24, 0.11, 0.07))
					bw.set_instance_shader_parameter("shop_glass", 0.0)
					bw.set_instance_shader_parameter("seed", float(p["id"]))
					root.add_child(bw)
				elif kind == "lake":
					var near_lake := _in_lake(track, wm, 2.0)
					var hm := MeshInstance3D.new()
					hm.mesh = Builder.box(Vector3(0.6 if near_lake else 1.0, 0.5 if near_lake else 1.0, seg.length() + 0.1))
					hm.material_override = concrete if near_lake else hedge
					hm.transform = Transform3D(basis, wm + Vector3(0, 0.25 if near_lake else 0.5, 0))
					root.add_child(hm)
		prev = cur
		d += step
	var lanes := 2.0 if kind == "spur" else 0.0
	_road_mesh(root, road, lanes, half * 2.0, 1.0 if kind == "alley" else 0.0, 0.012)

	match kind:
		"alley":
			_alley_details(root, track, p, rng)
		"lake":
			_shortcut_sign(root, track, p)
			var lamp_m := Builder.mat(Color(1, 0.85, 0.6), 0.0, 0.3, Color(1.0, 0.75, 0.45), 4.0)
			var dl := 12.0
			var s := 1.0
			while dl < len - 8.0:
				if dl < gap0 - 6.0 or dl > gap1 + 6.0:
					var f := frame_at(c, dl)
					var pos: Vector3 = f["pos"] + f["right"] * s * (half + 1.2)
					if _main_clearance(track, pos) > WALK + 1.0:
						var cyl := CylinderMesh.new()
						cyl.top_radius = 0.07
						cyl.bottom_radius = 0.09
						cyl.height = 4.0
						Builder._add(root, cyl, Builder.mat(Color(0.1, 0.1, 0.1), 0.5, 0.4), pos + Vector3(0, 2.0, 0))
						var sm := SphereMesh.new()
						sm.radius = 0.3
						sm.height = 0.6
						Builder._add(root, sm, lamp_m, pos + Vector3(0, 4.1, 0))
						var ol := OmniLight3D.new()
						ol.light_color = Color(1.0, 0.75, 0.45)
						ol.light_energy = 1.6
						ol.omni_range = 13.0
						ol.position = pos + Vector3(0, 3.8, 0)
						root.add_child(ol)
					s = -s
				dl += 22.0
		"spur":
			_spur_details(root, track, p, rng)


## Gasse: Lichterketten, Müllcontainer, Kisten, Hinweisschild
static func _alley_details(root: Node3D, track: Dictionary, p: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Curve3D = p["curve"]
	var len: float = p["length"]
	var half: float = p["half_w"]
	_shortcut_sign(root, track, p)
	var bulb_cols := [Color(1, 0.8, 0.45), Color(1, 0.4, 0.6), Color(0.5, 0.8, 1), Color(0.6, 1, 0.5)]
	var cable := Builder.mat(Color(0.03, 0.03, 0.03), 0.3, 0.6)
	var d := 18.0
	while d < len - 12.0:
		var f := frame_at(c, d)
		if _main_clearance(track, f["pos"]) > WALK + 4.0:
			var a: Vector3 = f["pos"] - f["right"] * (half + 0.3) + Vector3(0, 5.2, 0)
			var b: Vector3 = f["pos"] + f["right"] * (half + 0.3) + Vector3(0, 5.2, 0)
			for i in 9:
				var t := i / 8.0
				var q := a.lerp(b, t) - Vector3(0, sin(t * PI) * 0.9, 0)
				var col: Color = bulb_cols[i % bulb_cols.size()]
				var sm := SphereMesh.new()
				sm.radius = 0.09
				sm.height = 0.18
				sm.radial_segments = 6
				sm.rings = 3
				Builder._add(root, sm, Builder.mat(col, 0.0, 0.4, col, 6.0), q)
				if i < 8:
					var q2 := a.lerp(b, (i + 1) / 8.0) - Vector3(0, sin((i + 1) / 8.0 * PI) * 0.9, 0)
					var seg := q2 - q
					var cm := MeshInstance3D.new()
					cm.mesh = Builder.box(Vector3(0.02, 0.02, seg.length()))
					cm.material_override = cable
					cm.transform = Transform3D(Basis.looking_at(seg.normalized(), Vector3.UP), (q + q2) / 2)
					root.add_child(cm)
			var ol := OmniLight3D.new()
			ol.light_color = Color(1.0, 0.7, 0.55)
			ol.light_energy = 1.4
			ol.omni_range = 11.0
			ol.position = f["pos"] + Vector3(0, 4.0, 0)
			root.add_child(ol)
		d += 14.0
	# Container und Kisten an den Wänden (harte Hindernisse)
	var cols := [Color(0.1, 0.3, 0.15), Color(0.15, 0.2, 0.45), Color(0.45, 0.25, 0.08)]
	for i in 4:
		var dd := len * rng.randf_range(0.2, 0.8)
		var f := frame_at(c, dd)
		if _main_clearance(track, f["pos"]) < WALK + 6.0:
			continue
		var s := 1.0 if rng.randf() < 0.5 else -1.0
		var n := Node3D.new()
		var pos: Vector3 = f["pos"] + f["right"] * s * (half - 0.9)
		n.transform = Transform3D(Basis.looking_at(f["fwd"], Vector3.UP), pos)
		root.add_child(n)
		if i % 2 == 0:
			Builder._add(n, Builder.box(Vector3(1.4, 1.3, 2.0)), Builder.mat(cols[i % cols.size()], 0.4, 0.5), Vector3(0, 0.65, 0))
			Builder._add(n, Builder.box(Vector3(1.5, 0.1, 2.1)), Builder.mat(Color(0.05, 0.05, 0.05), 0.3, 0.5), Vector3(0, 1.35, 0))
			_solid(n, Vector3(1.4, 1.6, 2.0), Vector3(0, 0.8, 0))
		else:
			var crate := Builder.mat(Color(0.35, 0.24, 0.12), 0.0, 0.8)
			Builder._add(n, Builder.box(Vector3(1.0, 1.0, 1.0)), crate, Vector3(0, 0.5, 0))
			Builder._add(n, Builder.box(Vector3(0.9, 0.9, 0.9)), crate, Vector3(0.1, 1.45, 0.05))
			_solid(n, Vector3(1.0, 2.0, 1.0), Vector3(0, 1.0, 0))


## Orangefarbenes Schild "ABKÜRZUNG" an der Einfahrt
static func _shortcut_sign(root: Node3D, track: Dictionary, p: Dictionary) -> void:
	var c: Curve3D = p["curve"]
	var d := 4.0
	while d < 60.0 and _main_clearance(track, c.sample_baked(d)) < 2.0:
		d += 2.0
	var f := frame_at(c, d)
	var pos: Vector3 = f["pos"] + f["right"] * (p["half_w"] + 0.8)
	var n := Node3D.new()
	n.transform = Transform3D(Basis.looking_at(f["fwd"], Vector3.UP), pos)
	root.add_child(n)
	var orange := Builder.mat(Color(1, 0.5, 0.05), 0.0, 0.5, Color(1, 0.45, 0.0), 2.5)
	Builder._add(n, Builder.box(Vector3(0.1, 2.4, 0.1)), Builder.mat(Color(0.2, 0.2, 0.2), 0.5, 0.4), Vector3(0, 1.2, 0))
	Builder._add(n, Builder.box(Vector3(2.4, 0.8, 0.08)), orange, Vector3(0, 2.4, 0))
	var l := Label3D.new()
	l.text = "ABKÜRZUNG >>" if p["kind"] == "alley" else "SPRUNG! >>"
	l.font_size = 44
	l.pixel_size = 0.01
	l.modulate = Color(0, 0, 0)
	l.shaded = false
	l.position = Vector3(0, 2.4, 0.06)
	n.add_child(l)


## Seitenstraße: Zebrastreifen, Ampeln, Absperrung am Ende, Gebäude als Abschluss
static func _spur_details(root: Node3D, track: Dictionary, p: Dictionary, rng: RandomNumberGenerator) -> void:
	var c: Curve3D = p["curve"]
	var len: float = p["length"]
	var main: Curve3D = track["curve"]
	var fm := frame_at(main, p["from"])
	var white := Builder.mat(Color(0.85, 0.85, 0.85), 0.0, 0.5)
	var side: float = p["side"]
	# Zebrastreifen über die Hauptstraße (je Kreuzung einmal) und über die Einmündung
	if side > 0.0:
		for off in [-(SPUR_HALF + 3.0), SPUR_HALF + 3.0]:
			var n := Node3D.new()
			n.transform = Transform3D(Basis.looking_at(fm["fwd"], Vector3.UP), fm["pos"] + fm["fwd"] * off + Vector3(0, 0.015, 0))
			root.add_child(n)
			for i in 9:
				Builder._add(n, Builder.box(Vector3(1.0, 0.02, 3.2)), white, Vector3(-HALF_W + 1.0 + i * 2.0, 0, 0))
	var fe := frame_at(c, HALF_W + WALK + 2.5)
	var zn := Node3D.new()
	zn.transform = Transform3D(Basis.looking_at(fe["fwd"], Vector3.UP), fe["pos"] + Vector3(0, 0.03, 0))
	root.add_child(zn)
	for i in 6:
		Builder._add(zn, Builder.box(Vector3(1.0, 0.02, 3.0)), white, Vector3(-SPUR_HALF + 1.0 + i * 2.0, 0, 0))
	# Ampel an der Ecke, für den Verkehr auf der Hauptstraße
	var corner: Vector3 = fm["pos"] + fm["right"] * side * (HALF_W + 1.0) - fm["fwd"] * side * (SPUR_HALF + 1.5)
	var tl := Node3D.new()
	var face: Vector3 = -fm["fwd"] * side
	tl.transform = Transform3D(Basis.looking_at(-face, Vector3.UP), corner + Vector3(0, CURB_H, 0))
	root.add_child(tl)
	var dark := Builder.mat(Color(0.06, 0.06, 0.07), 0.6, 0.4)
	Builder._add(tl, Builder.box(Vector3(0.18, 5.0, 0.18)), dark, Vector3(0, 2.5, 0))
	var arm := MeshInstance3D.new()
	arm.mesh = Builder.box(Vector3(3.2, 0.12, 0.12))
	arm.material_override = dark
	arm.position = Vector3(-1.5, 5.0, 0)  # lokales -X zeigt zur Fahrbahnmitte
	tl.add_child(arm)
	var head_pos := Vector3(-3.0, 4.4, 0)
	Builder._add(tl, Builder.box(Vector3(0.45, 1.3, 0.35)), dark, head_pos)
	var lmat := ShaderMaterial.new()
	lmat.shader = LIGHT_SHADER
	var phase := rng.randf() * 12.0
	for k in 3:
		var sm := SphereMesh.new()
		sm.radius = 0.13
		sm.height = 0.26
		sm.radial_segments = 8
		sm.rings = 4
		var lm := Builder._add(tl, sm, lmat, head_pos + Vector3(0, 0.4 - k * 0.4, 0.18))
		lm.set_instance_shader_parameter("which", float(k))
		lm.set_instance_shader_parameter("phase", phase)
	# Absperrung + Gebäude am Ende der Sackgasse
	var fz := frame_at(c, len - 1.0)
	var bar := Node3D.new()
	bar.transform = Transform3D(Basis.looking_at(fz["fwd"], Vector3.UP), fz["pos"])
	root.add_child(bar)
	var stripe := Builder.mat(Color(0.9, 0.15, 0.1), 0.0, 0.6)
	for i in 5:
		Builder._add(bar, Builder.box(Vector3(2.4, 0.9, 0.5)), stripe if i % 2 == 0 else white, Vector3(-SPUR_HALF + 1.2 + i * 2.4, 0.45, 0))
	_solid(bar, Vector3(SPUR_HALF * 2.0 + 1.0, WALL_H, 0.6), Vector3(0, WALL_H / 2.0, 0))
	var bmat := ShaderMaterial.new()
	bmat.shader = BUILDING_SHADER
	var h := rng.randf_range(14.0, 40.0)
	var b := MeshInstance3D.new()
	b.mesh = BoxMesh.new()
	b.material_override = bmat
	b.transform = Transform3D(Basis.looking_at(fz["fwd"], Vector3.UP) * Basis.from_scale(Vector3(SPUR_HALF * 2.0 + 16.0, h, 14.0)),
		fz["pos"] + fz["fwd"] * 8.0 + Vector3(0, h / 2.0, 0))
	b.set_instance_shader_parameter("seed", rng.randf() * 100.0)
	b.set_instance_shader_parameter("style", float(rng.randi() % 5))
	b.set_instance_shader_parameter("tint", Vector3(0.12, 0.12, 0.14))
	root.add_child(b)


static func _solid(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.position = pos
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	parent.add_child(sb)


# --- See, Park, Rampen ------------------------------------------------------

static func _build_lakes(root: Node3D, track: Dictionary, rng: RandomNumberGenerator) -> void:
	var wm := ShaderMaterial.new()
	wm.shader = WATER_SHADER
	var rim := Builder.mat(Color(0.32, 0.32, 0.33), 0.0, 0.85)
	for lk in track["lakes"]:
		var au: Vector3 = lk["au"]
		var av: Vector3 = lk["av"]
		var hu: float = lk["hu"]
		var hv: float = lk["hv"]
		var basis := Basis.looking_at(au, Vector3.UP)
		var water := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(hv * 2.0, hu * 2.0)
		water.mesh = pm
		water.material_override = wm
		water.transform = Transform3D(basis, lk["center"] + Vector3(0, 0.005, 0))
		root.add_child(water)
		# Uferkante
		for s in [-1.0, 1.0]:
			Builder._add(root, Builder.box(Vector3(0.6, 0.4, hu * 2.0)), rim, lk["center"] + av * s * hv + Vector3(0, 0.2, 0)).basis = basis
		# Schilf und ein paar Lichter auf dem Wasser
		for i in 10:
			var pos: Vector3 = lk["center"] + au * rng.randf_range(-hu, hu) + av * (hv - rng.randf_range(0.5, 3.0)) * (1.0 if rng.randf() < 0.5 else -1.0)
			if _branch_clearance(track, pos) < 3.0:
				continue
			for k in 4:
				var reed := MeshInstance3D.new()
				reed.mesh = Builder.box(Vector3(0.05, rng.randf_range(0.8, 1.6), 0.05))
				reed.material_override = Builder.mat(Color(0.12, 0.18, 0.06), 0.0, 0.9)
				reed.position = pos + Vector3(rng.randf_range(-0.6, 0.6), 0.5, rng.randf_range(-0.6, 0.6))
				reed.rotation = Vector3(rng.randf_range(-0.2, 0.2), 0, rng.randf_range(-0.2, 0.2))
				root.add_child(reed)
	# Grünfläche im Inneren des Bogens, mit Bäumen
	var grass := Builder.mat(Color(0.03, 0.08, 0.035), 0.0, 0.95)
	for tri in track["parks"]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var a: Vector3 = tri[0]
		var b: Vector3 = tri[1]
		var c: Vector3 = tri[2]
		var n := (b - a).cross(c - a)
		var verts := [a, b, c] if n.y < 0.0 else [a, c, b]
		for v in verts:
			st.set_normal(Vector3.UP)
			st.add_vertex(v + Vector3(0, -0.02, 0))
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = grass
		root.add_child(mi)
		for i in 40:
			var r1 := rng.randf()
			var r2 := rng.randf()
			if r1 + r2 > 1.0:
				r1 = 1.0 - r1
				r2 = 1.0 - r2
			var pos := a + (b - a) * r1 + (c - a) * r2
			if _main_clearance(track, pos) < WALK + 3.0 or _branch_clearance(track, pos) < 3.0 or _in_lake(track, pos, 2.0):
				continue
			_tree(root, pos, rng, false)


static func _tree(root: Node3D, pos: Vector3, rng: RandomNumberGenerator, solid: bool) -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.12
	trunk.bottom_radius = 0.18
	trunk.height = 2.4
	trunk.radial_segments = 6
	Builder._add(root, trunk, Builder.mat(Color(0.12, 0.08, 0.05), 0.0, 0.9), pos + Vector3(0, 1.2, 0))
	var crown := SphereMesh.new()
	var r := rng.randf_range(1.2, 1.9)
	crown.radius = r
	crown.height = r * 2.3
	crown.radial_segments = 7
	crown.rings = 4
	var g := rng.randf_range(0.6, 1.1)
	Builder._add(root, crown, Builder.mat(Color(0.03 * g, 0.12 * g, 0.04 * g), 0.0, 0.9), pos + Vector3(0, 2.4 + r, 0))
	if solid:
		var sb := StaticBody3D.new()
		sb.position = pos + Vector3(0, 1.0, 0)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.5, 2.0, 0.5)
		cs.shape = bs
		sb.add_child(cs)
		root.add_child(sb)


## Keil: Breite x, Länge entlang -Z, steigt von 0 auf h.
static func _wedge(w: float, l: float, h: float) -> ArrayMesh:
	var bl0 := Vector3(-w / 2, 0, 0)
	var br0 := Vector3(w / 2, 0, 0)
	var bl1 := Vector3(-w / 2, 0, -l)
	var br1 := Vector3(w / 2, 0, -l)
	var tl := Vector3(-w / 2, h, -l)
	var tr := Vector3(w / 2, h, -l)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	Builder._quad(st, bl0, br0, tr, tl)
	Builder._quad(st, br1, bl1, tl, tr)
	for tri in [[bl0, tl, bl1], [br0, br1, tr]]:
		var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
		for v in [tri[0], tri[2], tri[1]]:
			st.set_normal(n)
			st.add_vertex(v)
	return st.commit()


static func _build_ramps(root: Node3D, track: Dictionary) -> void:
	var rm := ShaderMaterial.new()
	rm.shader = RAMP_SHADER
	var lamp := Builder.mat(Color(1, 0.5, 0.05), 0.0, 0.4, Color(1, 0.45, 0.0), 5.0)
	for r in track["ramps"]:
		var p: Dictionary = track["paths"][r["path"]]
		var c: Curve3D = p["curve"]
		var lat: float = (r["lat0"] + r["lat1"]) / 2.0
		var w: float = r["lat1"] - r["lat0"]
		var l: float = r["d1"] - r["d0"]
		var x := xform_at(c, r["d0"], lat)
		x.origin.y = 0.0 if r["path"] == 0 else 0.012
		var n := Node3D.new()
		n.transform = x
		root.add_child(n)
		Builder._add(n, _wedge(w, l, r["h"]), rm, Vector3.ZERO)
		for s in [-1.0, 1.0]:
			Builder._add(n, Builder.box(Vector3(0.15, 0.15, 0.15)), lamp, Vector3(s * w / 2.0, r["h"] + 0.08, -l))
		# Stützen unter der Abrisskante
		for s in [-1.0, 1.0]:
			Builder._add(n, Builder.box(Vector3(0.12, r["h"], 0.12)), Builder.mat(Color(0.1, 0.1, 0.1), 0.6, 0.4), Vector3(s * (w / 2.0 - 0.2), r["h"] / 2.0, -l - 0.1))


# --- Baustellen ----------------------------------------------------------------

## Baustellen sperren eine Außenspur auf ~30 m. Ergänzt track["blocks"] für KI und Verkehr.
static func _build_roadworks(root: Node3D, track: Dictionary, rng: RandomNumberGenerator) -> void:
	var curve: Curve3D = track["curve"]
	var length: float = track["length"]
	var stripe := Builder.mat(Color(0.9, 0.15, 0.1), 0.0, 0.6)
	var white := Builder.mat(Color(0.9, 0.9, 0.9), 0.0, 0.6)
	var warn := Builder.mat(Color(1, 0.7, 0.1), 0.0, 0.4, Color(1, 0.6, 0.0), 5.0)
	var count := 2 + int(length / 1200.0)
	for k in count:
		var d0 := length * (0.2 + 0.65 * (k + rng.randf() * 0.6) / count)
		var tries := 0
		while _in_zone(track, d0, 50.0) and tries < 20:
			d0 += 37.0
			tries += 1
		if _in_zone(track, d0, 50.0) or d0 > length - 150.0:
			continue
		var lane: float = LANES[0] if rng.randf() < 0.5 else LANES[3]
		var len := 30.0
		track["blocks"].append({"from": d0 - 14.0, "to": d0 + len + 4.0, "lane": lane})
		track["zones"].append({"from": d0 - 14.0, "to": d0 + len + 4.0})
		var dd := 0.0
		while dd <= len:
			var taper := clampf(dd / 8.0, 0.0, 1.0)
			var lat := lane + signf(lane) * (1.8 - taper * 1.8) - signf(lane) * 2.0 * taper
			var n := Node3D.new()
			n.transform = xform_at(curve, d0 + dd, lat)
			root.add_child(n)
			Builder._add(n, Builder.box(Vector3(0.5, 0.9, 2.6)), stripe if int(dd / 3.0) % 2 == 0 else white, Vector3(0, 0.45, 0))
			Builder._add(n, Builder.box(Vector3(0.2, 0.2, 0.2)), warn, Vector3(0, 1.0, 0))
			_solid(n, Vector3(0.5, 1.6, 2.6), Vector3(0, 0.8, 0))
			dd += 3.0
		var sign_n := Node3D.new()
		sign_n.transform = xform_at(curve, d0 - 10.0, lane)
		root.add_child(sign_n)
		Builder._add(sign_n, Builder.box(Vector3(1.8, 1.4, 0.1)), warn, Vector3(0, 1.4, 0))
		_solid(sign_n, Vector3(1.8, 2.0, 0.4), Vector3(0, 1.0, 0))
		var l := Label3D.new()
		l.text = "BAUSTELLE"
		l.font_size = 40
		l.pixel_size = 0.01
		l.modulate = Color(0, 0, 0)
		l.shaded = false
		l.position = Vector3(0, 1.4, 0.07)
		sign_n.add_child(l)


# --- Wahrzeichen -------------------------------------------------------------

## Knoten am Straßenrand der Hauptstraße: lokales -Z zeigt zur Straße.
static func _roadside(root: Node3D, curve: Curve3D, d: float, side: float, dist: float) -> Node3D:
	var f := frame_at(curve, d)
	var n := Node3D.new()
	var pos: Vector3 = f["pos"] + f["right"] * side * dist
	n.transform = Transform3D(Basis.looking_at(-f["right"] * side, Vector3.UP), Vector3(pos.x, 0, pos.z))
	root.add_child(n)
	return n


static func _label(parent: Node3D, text: String, col: Color, size: int, pos: Vector3, glow := 2.5) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.02
	l.modulate = Color(col.r * glow, col.g * glow, col.b * glow)
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.position = pos
	l.rotation_degrees.y = 180.0  # Label ist von +Z lesbar, Straße liegt bei -Z
	parent.add_child(l)
	return l


## Baut Kirche, Krankenhaus, Tankstelle. Liefert belegte Flächen [{pos, r}] für die übrige Bebauung.
static func _build_landmarks(root: Node3D, track: Dictionary, rng: RandomNumberGenerator) -> Array:
	var curve: Curve3D = track["curve"]
	var length: float = track["length"]
	var occupied := []
	var side := 1.0 if rng.randf() < 0.5 else -1.0
	var plan := [[0.22, "church", 30.0], [0.42, "gas", 22.0], [0.58, "hospital", 26.0], [0.8, "church", 30.0]]
	if length < 1800.0:
		plan.resize(3)
	for entry in plan:
		var depth: float = entry[2]
		var placed := false
		for shift in [0.0, 70.0, -70.0, 140.0, -140.0, 210.0]:
			var d: float = length * entry[0] + shift
			if _in_zone(track, d, 40.0):
				continue
			for s in [side, -side]:
				var dist := HALF_W + WALK + 1.5 + depth / 2.0
				var f := frame_at(curve, d)
				var pos: Vector3 = f["pos"] + f["right"] * s * dist
				if _branch_clearance(track, pos) < depth or _in_lake(track, pos, depth) or _rail_clearance(track, pos) < depth:
					continue
				var n := _roadside(root, curve, d, s, dist)
				match entry[1]:
					"church":
						_church(n)
					"gas":
						_gas_station(n)
					"hospital":
						_hospital(n)
				occupied.append({"pos": n.position, "r": depth + 6.0})
				placed = true
				side = -s
				break
			if placed:
				break
	return occupied


static func _church(n: Node3D) -> void:
	var stone := Builder.mat(Color(0.5, 0.47, 0.43), 0.0, 0.9)
	var slate := Builder.mat(Color(0.15, 0.17, 0.2), 0.3, 0.6)
	var gold := Builder.mat(Color(1, 0.8, 0.3), 0.8, 0.3, Color(1, 0.75, 0.3), 3.0)
	Builder._add(n, Builder.box(Vector3(12, 12, 24)), stone, Vector3(0, 6, 4))
	var roof := PrismMesh.new()
	roof.size = Vector3(12.8, 6, 24.4)
	Builder._add(n, roof, slate, Vector3(0, 15, 4))
	Builder._add(n, Builder.box(Vector3(6, 24, 6)), stone, Vector3(0, 12, -11))
	var spire := CylinderMesh.new()
	spire.top_radius = 0.0
	spire.bottom_radius = 4.2
	spire.height = 14.0
	spire.radial_segments = 4
	Builder._add(n, spire, slate, Vector3(0, 31, -11)).rotation_degrees.y = 45.0
	Builder._add(n, Builder.box(Vector3(0.3, 3.0, 0.3)), gold, Vector3(0, 39.5, -11))
	Builder._add(n, Builder.box(Vector3(1.6, 0.3, 0.3)), gold, Vector3(0, 40.0, -11))
	var clock := CylinderMesh.new()
	clock.top_radius = 1.4
	clock.bottom_radius = 1.4
	clock.height = 0.2
	clock.radial_segments = 16
	Builder._add(n, clock, Builder.mat(Color(1, 0.95, 0.8), 0, 0.5, Color(1, 0.9, 0.7), 2.5), Vector3(0, 19, -14.05)).rotation_degrees.x = 90
	Builder._add(n, Builder.box(Vector3(2.6, 4.5, 0.3)), Builder.mat(Color(0.3, 0.2, 0.1), 0, 0.5, Color(1, 0.6, 0.25), 1.5), Vector3(0, 2.25, -14.05))
	var glass_cols := [Color(0.2, 0.4, 1), Color(1, 0.2, 0.2), Color(1, 0.8, 0.2), Color(0.3, 1, 0.5)]
	for s in [-1, 1]:
		for i in 5:
			var gc: Color = glass_cols[(i + (1 if s > 0 else 0)) % glass_cols.size()]
			Builder._add(n, Builder.box(Vector3(0.2, 5.0, 1.6)), Builder.mat(gc, 0, 0.3, gc, 2.0), Vector3(s * 6.05, 6.5, -4.0 + i * 4.5))
	# Strebepfeiler und Rosette
	for s in [-1, 1]:
		for i in 6:
			Builder._add(n, Builder.box(Vector3(0.8, 9.0, 0.9)), stone, Vector3(s * 6.3, 4.5, -6.25 + i * 4.5))
	var rose := CylinderMesh.new()
	rose.top_radius = 1.6
	rose.bottom_radius = 1.6
	rose.height = 0.2
	rose.radial_segments = 12
	Builder._add(n, rose, Builder.mat(Color(0.6, 0.2, 0.8), 0, 0.3, Color(0.7, 0.3, 1.0), 2.5), Vector3(0, 12.0, -8.05)).rotation_degrees.x = 90
	for s in [-1, 1]:
		var sp := SpotLight3D.new()
		var pos := Vector3(s * 6.0, 0.5, -15.5)
		sp.transform = Transform3D(Basis.looking_at(Vector3(0, 18, -11) - pos, Vector3.UP), pos)
		sp.light_color = Color(1, 0.85, 0.6)
		sp.light_energy = 6.0
		sp.spot_range = 40.0
		sp.spot_angle = 22.0
		n.add_child(sp)


static func _hospital(n: Node3D) -> void:
	var bmat := ShaderMaterial.new()
	bmat.shader = BUILDING_SHADER
	var b := MeshInstance3D.new()
	b.mesh = BoxMesh.new()
	b.material_override = bmat
	b.transform = Transform3D(Basis.from_scale(Vector3(44, 24, 18)), Vector3(0, 12, 6))
	b.set_instance_shader_parameter("seed", 3.0)
	b.set_instance_shader_parameter("tint", Vector3(0.55, 0.57, 0.6))
	b.set_instance_shader_parameter("shop_glass", 0.0)
	b.set_instance_shader_parameter("style", 1.0)
	b.set_instance_shader_parameter("lit_chance", 0.6)
	n.add_child(b)
	var red := Builder.mat(Color(1, 0.05, 0.05), 0, 0.4, Color(1, 0.05, 0.05), 5.0)
	var white := Builder.mat(Color(0.9, 0.9, 0.92), 0.1, 0.5)
	Builder._add(n, Builder.box(Vector3(6, 6, 0.6)), white, Vector3(0, 27.5, -2.6))
	Builder._add(n, Builder.box(Vector3(1.4, 5, 0.3)), red, Vector3(0, 27.5, -2.95))
	Builder._add(n, Builder.box(Vector3(5, 1.4, 0.3)), red, Vector3(0, 27.5, -2.95))
	_label(n, "KRANKENHAUS", Color(0.7, 0.9, 1.0), 160, Vector3(0, 21, -3.1), 2.0)
	# Hubschrauberlandeplatz auf dem Dach
	var pad := CylinderMesh.new()
	pad.top_radius = 5.0
	pad.bottom_radius = 5.0
	pad.height = 0.2
	pad.radial_segments = 20
	Builder._add(n, pad, Builder.mat(Color(0.15, 0.15, 0.16), 0, 0.7), Vector3(12, 24.1, 8))
	var hl := Label3D.new()
	hl.text = "H"
	hl.font_size = 300
	hl.pixel_size = 0.02
	hl.modulate = Color(1.2, 1.2, 1.2)
	hl.shaded = false
	hl.position = Vector3(12, 24.22, 8)
	hl.rotation_degrees.x = -90
	n.add_child(hl)
	Builder._add(n, Builder.box(Vector3(14, 0.4, 6)), white, Vector3(-10, 4.2, -6))
	for x in [-16.5, -3.5]:
		Builder._add(n, Builder.box(Vector3(0.4, 4.2, 0.4)), white, Vector3(x, 2.1, -8.6))
	Builder._add(n, Builder.box(Vector3(9, 1.3, 0.3)), red, Vector3(-10, 5.1, -9.1))
	_label(n, "NOTAUFNAHME", Color(1, 1, 1), 90, Vector3(-10, 5.1, -9.3), 1.5)
	var ol := OmniLight3D.new()
	ol.position = Vector3(-10, 3.5, -6)
	ol.light_color = Color(0.85, 0.95, 1.0)
	ol.light_energy = 2.5
	ol.omni_range = 12.0
	n.add_child(ol)
	var amb := Node3D.new()
	amb.position = Vector3(-10, 0, -6)
	amb.rotation_degrees.y = 90
	n.add_child(amb)
	Builder._add(amb, Builder.box(Vector3(2.1, 2.3, 5.6)), white, Vector3(0, 1.45, 0))
	Builder._add(amb, Builder.box(Vector3(2.12, 0.3, 5.62)), Builder.mat(Color(0.9, 0.1, 0.05), 0, 0.5), Vector3(0, 1.3, 0))
	var blue := Builder.mat(Color(0.1, 0.3, 1), 0, 0.3, Color(0.1, 0.3, 1), 6.0)
	Builder._add(amb, Builder.box(Vector3(1.4, 0.18, 0.3)), blue, Vector3(0, 2.7, -2.4))
	var bl := OmniLight3D.new()
	bl.position = Vector3(0, 3.2, -2.4)
	bl.light_color = Color(0.15, 0.35, 1.0)
	bl.omni_range = 14.0
	amb.add_child(bl)
	bl.ready.connect(func():
		var tw := bl.create_tween().set_loops()
		tw.tween_property(bl, "light_energy", 6.0, 0.08)
		tw.tween_property(bl, "light_energy", 0.0, 0.25)
		tw.tween_interval(0.15))


static func _gas_station(n: Node3D) -> void:
	var white := Builder.mat(Color(0.85, 0.85, 0.88), 0.2, 0.5)
	var red := Builder.mat(Color(0.8, 0.1, 0.1), 0.1, 0.5)
	var panel := Builder.mat(Color(1, 1, 1), 0, 0.4, Color(0.95, 0.97, 1.0), 3.0)
	Builder._add(n, Builder.box(Vector3(20, 0.8, 12)), white, Vector3(0, 5.6, -4))
	Builder._add(n, Builder.box(Vector3(20.1, 0.3, 12.1)), red, Vector3(0, 5.6, -4))
	Builder._add(n, Builder.box(Vector3(19, 0.08, 11)), panel, Vector3(0, 5.17, -4))
	for x in [-8.0, 8.0]:
		for z in [-8.0, 0.0]:
			Builder._add(n, Builder.box(Vector3(0.6, 5.2, 0.6)), white, Vector3(x, 2.6, z))
	var disp := Builder.mat(Color(0.2, 1, 0.4), 0, 0.4, Color(0.2, 1, 0.4), 3.0)
	for x in [-4.0, 4.0]:
		Builder._add(n, Builder.box(Vector3(1.4, 0.25, 5)), white, Vector3(x, 0.12, -4))
		Builder._add(n, Builder.box(Vector3(0.8, 1.8, 0.6)), red, Vector3(x, 1.1, -4))
		Builder._add(n, Builder.box(Vector3(0.5, 0.3, 0.62)), disp, Vector3(x, 1.5, -4))
	for x in [-5.0, 5.0]:
		var l := OmniLight3D.new()
		l.position = Vector3(x, 4.6, -4)
		l.light_energy = 3.0
		l.omni_range = 16.0
		l.light_color = Color(0.92, 0.96, 1.0)
		n.add_child(l)
	var bmat := ShaderMaterial.new()
	bmat.shader = BUILDING_SHADER
	var b := MeshInstance3D.new()
	b.mesh = BoxMesh.new()
	b.material_override = bmat
	b.transform = Transform3D(Basis.from_scale(Vector3(14, 4.5, 8)), Vector3(0, 2.25, 6))
	b.set_instance_shader_parameter("seed", 9.0)
	b.set_instance_shader_parameter("tint", Vector3(0.3, 0.3, 0.32))
	n.add_child(b)
	_label(n, "24/7 SHOP", Color(1, 0.3, 0.3), 70, Vector3(0, 3.8, 1.9))
	Builder._add(n, Builder.box(Vector3(0.5, 9, 0.5)), white, Vector3(11, 4.5, -10))
	Builder._add(n, Builder.box(Vector3(3.4, 3.4, 0.4)), Builder.mat(Color(0.05, 0.05, 0.08), 0, 0.5), Vector3(11, 9.5, -10))
	_label(n, "TANKE\nSUPER  1,89\nDIESEL 1,79", Color(1, 0.8, 0.2), 40, Vector3(11, 9.5, -10.25))
	# Geparktes Auto an der Zapfsäule
	Builder._add(n, Builder.tapered_box(Vector2(1.8, 4.4), Vector2(1.7, 4.2), 0.65, 0.0), Builder.mat(Color(0.4, 0.05, 0.05), 0.5, 0.3), Vector3(-6.5, 0.25, -4))
	Builder._add(n, Builder.tapered_box(Vector2(1.6, 2.2), Vector2(1.3, 1.4), 0.5, 0.1), Builder.mat(Color(0.02, 0.03, 0.05), 0.7, 0.1), Vector3(-6.5, 0.9, -3.8))


# --- Bebauung --------------------------------------------------------------

static func _district_at(track: Dictionary, d: float) -> Dictionary:
	var arr: Array = track["districts"]
	var i := clampi(int(d / DISTRICT_LEN), 0, arr.size() - 1)
	return DISTRICTS[arr[i]]


static func _build_city(root: Node3D, track: Dictionary, rng: RandomNumberGenerator, occupied: Array) -> void:
	var bmat := ShaderMaterial.new()
	bmat.shader = BUILDING_SHADER
	var placed := []  # [{pos, r}]
	# Häuserzeilen: an der Hauptstraße beidseitig, an den Abkürzungen ebenfalls
	var frontages := []
	for side in [-1.0, 1.0]:
		frontages.append({"path": track["paths"][0], "side": side, "edge": HALF_W + WALK})
	for p in track["paths"]:
		if p["kind"] == "alley" or p["kind"] == "lake":
			for side in [-1.0, 1.0]:
				frontages.append({"path": p, "side": side, "edge": p["half_w"] + 0.8})
	for fr in frontages:
		var p: Dictionary = fr["path"]
		var c: Curve3D = p["curve"]
		var len: float = p["length"]
		var side: float = fr["side"]
		var d := rng.randf_range(0.0, 8.0)
		while d < len:
			var dist: Dictionary = _district_at(track, d if p["id"] == 0 else p["from"])
			var tall: bool = rng.randf() < dist["tall_p"]
			var shop: bool = not tall and rng.randf() < dist["shop"]
			var w := rng.randf_range(8.0, 15.0) if not tall else rng.randf_range(14.0, 26.0)
			var depth := rng.randf_range(10.0, 16.0) if not tall else rng.randf_range(14.0, 24.0)
			var hr: Array = dist["tall"] if tall else dist["low"]
			var h := rng.randf_range(hr[0], hr[1])
			if shop:
				h = rng.randf_range(5.0, 9.0)
			var f := frame_at(c, d)
			var gap := rng.randf_range(0.4, 2.0)
			var center: Vector3 = f["pos"] + f["right"] * side * (fr["edge"] + gap + depth / 2)
			var radius := Vector2(w, depth).length() / 2
			var ok: bool = _flat(center - c.get_closest_point(center)).length() > fr["edge"] + radius * 0.7
			ok = ok and _main_clearance(track, center) > WALK + radius * 0.75
			ok = ok and _branch_clearance(track, center) > 1.0 + radius * 0.7
			ok = ok and not _in_lake(track, center, radius * 0.7)
			ok = ok and _rail_clearance(track, center) > 5.0 + radius * 0.7
			if ok:
				for o in occupied + placed:
					if _flat(center - o["pos"]).length() < o["r"] + radius * 0.65:
						ok = false
						break
			if ok and dist.has("containers") and rng.randf() < 0.3:
				_containers(root, center, Basis.looking_at(f["fwd"], Vector3.UP), rng)
				placed.append({"pos": center, "r": radius * 0.8})
			elif ok:
				var basis := Basis.looking_at(f["fwd"], Vector3.UP)
				var face_dir: Vector3 = -f["right"] * side  # zeigt zur Straße
				_building(root, bmat, center, basis, w, depth, h, tall, shop, dist, face_dir, f["right"] * side, rng)
				placed.append({"pos": center, "r": radius * 0.8})
			d += w + rng.randf_range(0.5, 3.5)


## Ein Gebäude mit Fassade, ggf. Sockel + Turm + Krone, Dachaufbauten, Werbung, Laden
static func _building(root: Node3D, bmat: ShaderMaterial, center: Vector3, basis: Basis, w: float, depth: float, h: float,
		tall: bool, shop: bool, dist: Dictionary, face_dir: Vector3, away: Vector3, rng: RandomNumberGenerator) -> void:
	var styles: Array = dist["styles"]
	var tints: Array = dist["tints"]
	var style: float = styles[rng.randi() % styles.size()]
	var tint: Color = tints[rng.randi() % tints.size()]
	var v := rng.randf_range(0.8, 1.2)
	var tv := Vector3(tint.r * v, tint.g * v, tint.b * v)
	var seed := rng.randf() * 100.0
	var lit: float = dist["lit"] * rng.randf_range(0.7, 1.3)
	var top_h := h
	var top_center := center
	var top_w := w
	var top_d := depth
	if tall and h > 26.0 and rng.randf() < 0.55:
		# Sockelbau + zurückgesetzter Turm
		var ph := rng.randf_range(6.0, 9.0)
		_box_building(root, bmat, center, basis, w, depth, ph, 0.0, tv * 0.9, seed + 1.0, 1.0, lit)
		top_w = w * 0.7
		top_d = depth * 0.7
		top_center = center + away * depth * 0.1
		_box_building(root, bmat, top_center, basis, top_w, top_d, h, style, tv, seed, 0.0, lit)
	else:
		_box_building(root, bmat, center, basis, w, depth, h, style, tv, seed, 1.0 if not tall or rng.randf() < 0.7 else 0.0, lit)
	if tall and h > 45.0 and rng.randf() < 0.45:
		# Krone
		var ch := rng.randf_range(5.0, 12.0)
		_box_building(root, bmat, top_center, basis, top_w * 0.55, top_d * 0.55, ch, style, tv * 1.1, seed + 2.0, 0.0, lit, top_h)
		top_h += ch
		top_w *= 0.55
		top_d *= 0.55
	var roof_y := top_h
	# Dachaufbauten
	var grey := Builder.mat(Color(0.25, 0.25, 0.27), 0.5, 0.5)
	for i in rng.randi_range(0, 3):
		var off := basis * Vector3(rng.randf_range(-top_d, top_d) * 0.3, 0, rng.randf_range(-top_w, top_w) * 0.3)
		Builder._add(root, Builder.box(Vector3(1.6, 1.0, 1.2)), grey, top_center + off + Vector3(0, roof_y + 0.5, 0)).basis = basis
	if not tall and rng.randf() < 0.35:
		# Wassertank auf Stelzen
		var tank := CylinderMesh.new()
		tank.top_radius = 1.2
		tank.bottom_radius = 1.2
		tank.height = 2.2
		tank.radial_segments = 10
		var tp := top_center + away * top_d * 0.2 + Vector3(0, roof_y + 2.6, 0)
		Builder._add(root, tank, Builder.mat(Color(0.3, 0.2, 0.12), 0.0, 0.8), tp)
		for k in 4:
			var o := Vector3(cos(k * PI / 2) * 0.9, -1.6, sin(k * PI / 2) * 0.9)
			Builder._add(root, Builder.box(Vector3(0.1, 1.2, 0.1)), grey, tp + o)
	if tall and rng.randf() < 0.6:
		# Antenne mit rotem Blinklicht
		var ah := rng.randf_range(5.0, 14.0)
		var ap := top_center + Vector3(0, roof_y + ah / 2.0, 0)
		Builder._add(root, Builder.box(Vector3(0.15, ah, 0.15)), grey, ap)
		var bm := ShaderMaterial.new()
		bm.shader = BLINK_SHADER
		var sm := SphereMesh.new()
		sm.radius = 0.3
		sm.height = 0.6
		var light := Builder._add(root, sm, bm, top_center + Vector3(0, roof_y + ah, 0))
		light.set_instance_shader_parameter("phase", rng.randf())
	if rng.randf() < dist["billboard"] and h < 40.0 and top_center == center:
		_billboard(root, center + face_dir * (depth * 0.5 - 1.5), face_dir, roof_y, rng)
	if rng.randf() < dist["neon_edge"]:
		var nc: Color = NEON[rng.randi() % NEON.size()]
		var nm := Builder.mat(nc, 0.0, 0.4, nc, 5.0)
		var along := basis.z
		for s in [-1.0, 1.0]:
			var corner: Vector3 = top_center + face_dir * (top_d * 0.5 + 0.08) + along * s * (top_w * 0.5 + 0.08)
			Builder._add(root, Builder.box(Vector3(0.15, top_h - 6.0, 0.15)), nm, corner + Vector3(0, 4.0 + (top_h - 6.0) / 2.0, 0))
	var face_pos := center + face_dir * (depth / 2 + 0.15)
	var face_basis := Basis.looking_at(-face_dir, Vector3.UP)  # +Z zeigt zur Straße
	if shop:
		var awning_cols := [Color(0.6, 0.05, 0.05), Color(0.05, 0.35, 0.15), Color(0.1, 0.15, 0.5), Color(0.5, 0.3, 0.05), Color(0.35, 0.05, 0.4)]
		var aw := MeshInstance3D.new()
		aw.mesh = Builder.box(Vector3(w * 0.85, 0.15, 1.6))
		aw.material_override = Builder.mat(awning_cols[rng.randi() % awning_cols.size()], 0.1, 0.6)
		aw.transform = Transform3D(face_basis, face_pos + Vector3(0, 3.6, 0) + face_dir * 0.8)
		root.add_child(aw)
		if rng.randf() < 0.35:
			var open := Label3D.new()
			open.text = "OPEN"
			open.font_size = 32
			open.pixel_size = 0.012
			open.modulate = Color(3.0, 0.4, 1.5)
			open.shaded = false
			open.transform = Transform3D(face_basis, face_pos + Vector3(0, 2.4, 0) + face_dir * 0.05 + basis.z * w * 0.25)
			root.add_child(open)
	if shop or rng.randf() < 0.3:
		var col: Color = NEON[rng.randi() % NEON.size()]
		var lbl := Label3D.new()
		lbl.text = SHOPS[rng.randi() % SHOPS.size()] if shop else SIGNS[rng.randi() % SIGNS.size()]
		lbl.font_size = 64 if shop else 96
		lbl.pixel_size = 0.02
		lbl.modulate = Color(col.r * 3.0, col.g * 3.0, col.b * 3.0)
		lbl.shaded = false
		lbl.double_sided = false
		var y := 4.6 if shop else rng.randf_range(6.0, minf(h - 2.0, 14.0))
		lbl.transform = Transform3D(face_basis, face_pos + Vector3(0, y, 0))
		root.add_child(lbl)
	if style == 4.0 and rng.randf() < 0.5:
		# Balkone übereinander
		var bc := Builder.mat(Color(0.2, 0.2, 0.22), 0.5, 0.5)
		var floors := int((h - 4.2) / 3.2)
		var off := basis.z * rng.randf_range(-w * 0.3, w * 0.3)
		for k in mini(floors, 6):
			Builder._add(root, Builder.box(Vector3(2.4, 0.12, 1.0)), bc, face_pos + off + face_dir * 0.5 + Vector3(0, 4.2 + k * 3.2, 0)).basis = face_basis
			Builder._add(root, Builder.box(Vector3(2.4, 0.9, 0.05)), bc, face_pos + off + face_dir * 1.0 + Vector3(0, 4.65 + k * 3.2, 0)).basis = face_basis


static func _box_building(root: Node3D, bmat: ShaderMaterial, center: Vector3, basis: Basis, w: float, depth: float, h: float,
		style: float, tint: Vector3, seed: float, shop_glass: float, lit: float, base_y := 0.0) -> void:
	var b := MeshInstance3D.new()
	b.mesh = BoxMesh.new()
	b.material_override = bmat
	b.transform = Transform3D(basis * Basis.from_scale(Vector3(depth, h, w)), center + Vector3(0, base_y + h / 2, 0))
	b.set_instance_shader_parameter("seed", seed)
	b.set_instance_shader_parameter("tint", tint)
	b.set_instance_shader_parameter("style", style)
	b.set_instance_shader_parameter("shop_glass", shop_glass)
	b.set_instance_shader_parameter("lit_chance", lit)
	root.add_child(b)


## Leuchtende Werbetafel auf dem Dach, zur Straße gedreht
static func _billboard(root: Node3D, pos: Vector3, face_dir: Vector3, roof_y: float, rng: RandomNumberGenerator) -> void:
	var n := Node3D.new()
	n.transform = Transform3D(Basis.looking_at(-face_dir, Vector3.UP), pos + Vector3(0, roof_y, 0))
	root.add_child(n)
	var dark := Builder.mat(Color(0.08, 0.08, 0.09), 0.6, 0.4)
	var col: Color = NEON[rng.randi() % NEON.size()]
	Builder._add(n, Builder.box(Vector3(9.0, 3.6, 0.3)), Builder.mat(col * 0.25, 0.0, 0.5, col * 0.5, 1.2), Vector3(0, 4.2, 0))
	Builder._add(n, Builder.box(Vector3(9.3, 0.2, 0.4)), dark, Vector3(0, 2.3, 0))
	for x in [-3.5, 3.5]:
		Builder._add(n, Builder.box(Vector3(0.2, 2.4, 0.2)), dark, Vector3(x, 1.2, 0))
	var l := Label3D.new()
	l.text = BRANDS[rng.randi() % BRANDS.size()]
	l.font_size = 120
	l.pixel_size = 0.012
	l.modulate = Color(2.5, 2.5, 2.5)
	l.outline_modulate = Color(col.r, col.g, col.b, 1.0)
	l.outline_size = 16
	l.shaded = false
	l.position = Vector3(0, 4.2, 0.17)
	n.add_child(l)
	var sl := SpotLight3D.new()
	sl.position = Vector3(0, 2.4, 1.5)
	sl.rotation_degrees.x = 60
	sl.light_color = Color(1, 0.95, 0.85)
	sl.light_energy = 2.0
	sl.spot_range = 6.0
	sl.spot_angle = 50.0
	n.add_child(sl)


## Containerstapel im Industrieviertel
static func _containers(root: Node3D, center: Vector3, basis: Basis, rng: RandomNumberGenerator) -> void:
	var cols := [Color(0.6, 0.12, 0.08), Color(0.08, 0.2, 0.5), Color(0.75, 0.4, 0.05), Color(0.1, 0.4, 0.2), Color(0.5, 0.5, 0.52)]
	for i in 2:
		for j in 3:
			var stack := rng.randi_range(1, 3)
			for k in stack:
				var pos := center + basis * Vector3((i - 0.5) * 2.8, 0, (j - 1) * 6.4) + Vector3(0, 1.3 + k * 2.6, 0)
				Builder._add(root, Builder.box(Vector3(2.4, 2.55, 6.1)), Builder.mat(cols[rng.randi() % cols.size()], 0.4, 0.6), pos).basis = basis


## Laternen: fliegen weg, wenn man sie trifft (und gehen aus). Lichtfarbe je Viertel.
static func _build_lamps(root: Node3D, track: Dictionary) -> void:
	var curve: Curve3D = track["curve"]
	var length: float = track["length"]
	var pole_m := Builder.mat(Color(0.2, 0.2, 0.22), 0.6, 0.4)
	var d := 20.0
	var side := 1.0
	while d < length:
		var f := frame_at(curve, d)
		var base: Vector3 = f["pos"] + f["right"] * side * (HALF_W + 0.8)
		if _branch_clearance(track, base) > 2.5 and (track["crossing_d"] < 0.0 or absf(d - track["crossing_d"]) > 14.0):
			var lc: Color = _district_at(track, d)["lamp"]
			var lamp_m := Builder.mat(lc, 0.0, 0.3, lc, 5.0)
			var lamp := Knockable.new()
			lamp.mass = 60.0
			lamp.slowdown = 0.9
			lamp.set_meta("clang", true)
			lamp.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
			lamp.center_of_mass = Vector3(0, 2.0, 0)
			lamp.transform = Transform3D(Basis.looking_at(-f["right"] * side, Vector3.UP), Vector3(base.x, CURB_H, base.z))
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.12
			cyl.bottom_radius = 0.15
			cyl.height = 8.0
			Builder._add(lamp, cyl, pole_m, Vector3(0, 4.0, 0))
			Builder._add(lamp, Builder.box(Vector3(0.15, 0.15, 2.4)), pole_m, Vector3(0, 8.0, -1.1))
			Builder._add(lamp, Builder.box(Vector3(0.5, 0.12, 0.9)), lamp_m, Vector3(0, 7.9, -2.2))
			var cs := CollisionShape3D.new()
			var shape := CylinderShape3D.new()
			shape.radius = 0.25
			shape.height = 8.0
			cs.shape = shape
			cs.position.y = 4.0
			lamp.add_child(cs)
			var light := OmniLight3D.new()
			light.light_color = lc
			light.light_energy = 2.2
			light.omni_range = 20.0
			light.omni_attenuation = 1.2
			light.position = Vector3(0, 7.3, -2.2)
			lamp.add_child(light)
			root.add_child(lamp)
		d += LAMP_STEP
		side = -side


## Gehweg-Möblierung: leichte Sachen fliegen weg, schwere (Hydrant, Poller, Kübel, Haltestelle, Bäume) sind hart.
static func _build_props(root: Node3D, track: Dictionary, rng: RandomNumberGenerator) -> void:
	var curve: Curve3D = track["curve"]
	var length: float = track["length"]
	var green := Builder.mat(Color(0.1, 0.35, 0.15), 0.2, 0.6)
	var orange := Builder.mat(Color(1, 0.4, 0.05), 0, 0.5, Color(1, 0.35, 0.0), 0.6)
	var blue := Builder.mat(Color(0.1, 0.2, 0.6), 0.3, 0.5)
	var yellow := Builder.mat(Color(1, 0.8, 0.05), 0.2, 0.5)
	var wood := Builder.mat(Color(0.35, 0.22, 0.12), 0.0, 0.8)
	var red := Builder.mat(Color(0.8, 0.05, 0.05), 0.3, 0.4)
	var dark := Builder.mat(Color(0.12, 0.12, 0.13), 0.5, 0.5)
	var concrete := Builder.mat(Color(0.35, 0.35, 0.36), 0.0, 0.9)
	var bush := Builder.mat(Color(0.05, 0.25, 0.08), 0.0, 0.9)
	var glass := Builder.mat(Color(0.3, 0.4, 0.5), 0.6, 0.1)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color.a = 0.3
	var ad := Builder.mat(Color(1, 1, 1), 0, 0.4, Color(0.9, 0.95, 1.0), 2.5)

	for side in [-1.0, 1.0]:
		var d := rng.randf_range(5.0, 12.0)
		while d < length - 10.0:
			var lamp_phase := fmod(d - 20.0 + LAMP_STEP * 2.0, LAMP_STEP)
			var f := frame_at(curve, d)
			if lamp_phase < 3.0 or lamp_phase > LAMP_STEP - 3.0 or _in_zone(track, d, 4.0) \
					or _branch_clearance(track, f["pos"] + f["right"] * side * (HALF_W + 2.5)) < 4.0:
				d += 4.0
				continue
			var dist: Dictionary = _district_at(track, d)
			if rng.randf() < dist["trees"]:
				var tp: Vector3 = f["pos"] + f["right"] * side * (HALF_W + WALK - 1.3)
				var ring := CylinderMesh.new()
				ring.top_radius = 0.7
				ring.bottom_radius = 0.7
				ring.height = 0.25
				ring.radial_segments = 8
				Builder._add(root, ring, concrete, tp + Vector3(0, CURB_H + 0.12, 0))
				_tree(root, tp + Vector3(0, CURB_H, 0), rng, true)
				d += rng.randf_range(8.0, 14.0)
				continue
			var kind := rng.randi() % 10
			var off := HALF_W + rng.randf_range(1.0, WALK - 0.9)
			var pos: Vector3 = f["pos"] + f["right"] * side * off
			var basis := Basis.looking_at(-f["right"] * side, Vector3.UP)
			var xf := Transform3D(basis, Vector3(pos.x, CURB_H, pos.z))
			if kind <= 5:
				var k := Knockable.new()
				k.transform = xf
				var sz := Vector3.ONE
				match kind:
					0, 1:
						var c := CylinderMesh.new()
						c.top_radius = 0.35
						c.bottom_radius = 0.3
						c.height = 1.0
						c.radial_segments = 10
						Builder._add(k, c, green, Vector3(0, 0.5, 0))
						sz = Vector3(0.7, 1.0, 0.7)
						k.mass = 15.0
					2:
						var c := CylinderMesh.new()
						c.top_radius = 0.04
						c.bottom_radius = 0.25
						c.height = 0.7
						c.radial_segments = 8
						Builder._add(k, c, orange, Vector3(0, 0.35, 0))
						sz = Vector3(0.5, 0.7, 0.5)
						k.mass = 3.0
						k.slowdown = 0.99
					3:
						Builder._add(k, Builder.box(Vector3(0.5, 1.1, 0.5)), blue, Vector3(0, 0.55, 0))
						sz = Vector3(0.5, 1.1, 0.5)
						k.mass = 20.0
					4:
						Builder._add(k, Builder.box(Vector3(0.5, 0.6, 0.35)), yellow, Vector3(0, 1.0, 0))
						Builder._add(k, Builder.box(Vector3(0.08, 0.7, 0.08)), dark, Vector3(0, 0.35, 0))
						sz = Vector3(0.5, 1.3, 0.4)
						k.mass = 25.0
					5:
						Builder._add(k, Builder.box(Vector3(1.8, 0.1, 0.5)), wood, Vector3(0, 0.45, 0))
						Builder._add(k, Builder.box(Vector3(1.8, 0.5, 0.08)), wood, Vector3(0, 0.75, 0.22))
						sz = Vector3(1.8, 0.9, 0.5)
						k.mass = 40.0
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = sz
				cs.shape = bs
				cs.position.y = sz.y / 2.0
				k.add_child(cs)
				root.add_child(k)
			else:
				var s := Node3D.new()
				s.transform = xf
				root.add_child(s)
				match kind:
					6:
						var c := CylinderMesh.new()
						c.top_radius = 0.16
						c.bottom_radius = 0.2
						c.height = 0.8
						c.radial_segments = 8
						Builder._add(s, c, red, Vector3(0, 0.4, 0))
						_solid(s, Vector3(0.45, 1.0, 0.45), Vector3(0, 0.5, 0))
					7:
						for i in 3:
							var c := CylinderMesh.new()
							c.top_radius = 0.12
							c.bottom_radius = 0.12
							c.height = 0.9
							c.radial_segments = 8
							Builder._add(s, c, dark, Vector3(-1.5 + i * 1.5, 0.45, 0))
							_solid(s, Vector3(0.3, 1.0, 0.3), Vector3(-1.5 + i * 1.5, 0.5, 0))
					8:
						Builder._add(s, Builder.box(Vector3(1.4, 0.6, 1.4)), concrete, Vector3(0, 0.3, 0))
						var sm := SphereMesh.new()
						sm.radius = 0.75
						sm.height = 1.2
						sm.radial_segments = 8
						sm.rings = 4
						Builder._add(s, sm, bush, Vector3(0, 1.0, 0))
						_solid(s, Vector3(1.4, 1.2, 1.4), Vector3(0, 0.6, 0))
					9:
						s.transform.origin = Vector3(pos.x, CURB_H, pos.z) + f["right"] * side * (HALF_W + WALK - 1.1 - off)
						Builder._add(s, Builder.box(Vector3(3.6, 0.12, 1.5)), dark, Vector3(0, 2.5, 0))
						Builder._add(s, Builder.box(Vector3(3.6, 2.4, 0.06)), glass, Vector3(0, 1.25, 0.7))
						Builder._add(s, Builder.box(Vector3(0.06, 2.4, 1.4)), ad, Vector3(1.75, 1.25, 0))
						Builder._add(s, Builder.box(Vector3(2.4, 0.08, 0.4)), wood, Vector3(-0.3, 0.45, 0.45))
						_solid(s, Vector3(3.6, 2.5, 1.5), Vector3(0, 1.25, 0))
			d += rng.randf_range(7.0, 15.0)


## Dampf aus Gullys
static func _build_steam(root: Node3D, track: Dictionary, rng: RandomNumberGenerator) -> void:
	var curve: Curve3D = track["curve"]
	var length: float = track["length"]
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 15.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0.25, 0.35, 0.0)
	pm.scale_min = 1.6
	pm.scale_max = 3.2
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.35
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.0))
	grad.add_point(0.25, Color(1, 1, 1, 1.0))
	grad.set_color(grad.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	var quad := QuadMesh.new()
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(0.75, 0.8, 0.9, 0.09)
	quad.material = m
	var cover := Builder.mat(Color(0.08, 0.08, 0.08), 0.6, 0.5)
	var d := rng.randf_range(80.0, 160.0)
	while d < length - 50.0:
		if not _in_zone(track, d, 10.0):
			var f := frame_at(curve, d)
			var pos: Vector3 = f["pos"] + f["right"] * LANES[rng.randi() % 4]
			var gp := GPUParticles3D.new()
			gp.amount = 20
			gp.lifetime = 3.5
			gp.preprocess = 3.0
			gp.process_material = pm
			gp.draw_pass_1 = quad
			gp.position = pos + Vector3(0, 0.1, 0)
			root.add_child(gp)
			var disc := CylinderMesh.new()
			disc.top_radius = 0.45
			disc.bottom_radius = 0.45
			disc.height = 0.02
			disc.radial_segments = 12
			Builder._add(root, disc, cover, pos + Vector3(0, 0.01, 0))
		d += rng.randf_range(160.0, 280.0)


static func _gate(root: Node3D, curve: Curve3D, d: float, text: String, col: Color) -> void:
	var f := frame_at(curve, d)
	var basis := Basis.looking_at(f["fwd"], Vector3.UP)
	var em := Builder.mat(col, 0.0, 0.4, col, 3.0)
	var dark := Builder.mat(Color(0.1, 0.1, 0.12), 0.5, 0.4)
	for s in [-1, 1]:
		var pillar := Node3D.new()
		pillar.transform = Transform3D(basis, f["pos"] + f["right"] * s * (HALF_W + 1.4))
		root.add_child(pillar)
		Builder._add(pillar, Builder.box(Vector3(0.8, 7.0, 0.8)), dark, Vector3(0, 3.5, 0))
		_solid(pillar, Vector3(0.8, 7.0, 0.8), Vector3(0, 3.5, 0))
	var beam := MeshInstance3D.new()
	beam.mesh = Builder.box(Vector3(HALF_W * 2 + 3.6, 1.4, 0.6))
	beam.material_override = dark
	beam.transform = Transform3D(basis, f["pos"] + Vector3(0, 7.2, 0))
	root.add_child(beam)
	var strip := MeshInstance3D.new()
	strip.mesh = Builder.box(Vector3(HALF_W * 2 + 3.6, 0.15, 0.65))
	strip.material_override = em
	strip.transform = Transform3D(basis, f["pos"] + Vector3(0, 6.5, 0))
	root.add_child(strip)
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 128
	lbl.pixel_size = 0.012
	lbl.modulate = Color(col.r * 2.5, col.g * 2.5, col.b * 2.5)
	lbl.shaded = false
	lbl.double_sided = true
	lbl.transform = Transform3D(Basis.looking_at(f["fwd"], Vector3.UP), f["pos"] + Vector3(0, 7.25, 0) - f["fwd"] * 0.35)
	root.add_child(lbl)
	var tile_m := Builder.mat(Color(0.9, 0.9, 0.9), 0.0, 0.4)
	for i in 16:
		for row in 2:
			if (i + row) % 2 == 0:
				continue
			var tile := MeshInstance3D.new()
			tile.mesh = Builder.box(Vector3(HALF_W * 2 / 16.0, 0.02, 0.9))
			tile.material_override = tile_m
			var lat := -HALF_W + (i + 0.5) * HALF_W * 2 / 16.0
			tile.transform = Transform3D(basis, f["pos"] + f["right"] * lat + f["fwd"] * (row * 0.9) + Vector3(0, 0.01, 0))
			root.add_child(tile)
