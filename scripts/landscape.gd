class_name Landscape
extends Node3D
## Landschaft der Open World zwischen Städten und Autobahnen (seit 2.29; davor lag dort eine leere graue Fläche):
## Hügel, die abseits der Straßen sanft ansteigen, Felder (shaders/land.gdshader), Wälder, Dörfer mit Kirchturm,
## Windparks mit Gefahrenfeuer und nachts Nebelbänke über den Wiesen. Gebaut in Kacheln zu 1 km rund um den Spieler,
## im Hintergrund-Thread; nah an Straßen und in Städten bleibt alles flach (dort liegen Strecken und Häuser).
## Alles hier ist Kulisse ohne Kollision: Straßen sind ummauert, man kommt nicht hin.

const LAND_SHADER := preload("res://shaders/land.gdshader")
const HOUSE_SHADER := preload("res://shaders/house.gdshader")
const FOG_SHADER := preload("res://shaders/fog_bank.gdshader")
const BEACON_SHADER := preload("res://shaders/beacon.gdshader")
const WATER_SHADER := preload("res://shaders/water.gdshader")
const Layout := preload("res://scripts/world_layout.gd")
const Catalog := preload("res://scripts/catalog.gd")

const CHUNK := 1000.0
const STEP := 25.0  # Gitterweite des Geländes
const N := 40  # Zellen je Kachel und Richtung
var VIEW := 3300.0  # so weit werden Kacheln geladen (setup: Sichtweite der Kamera plus Rand)
const ROAD_CELL := 100.0
const ROAD_FLAT := 55.0  # bis hier neben einer Straße ist das Gelände flach
const RISE := 330.0  # dann steigt es auf dieser Strecke an
const FOREST_FLAT := 30.0  # Waldstrecke: schmal flach, dann gleich Hang
const CITY_FLAT := 150.0  # neben Stadtstraßen flach (dort stehen zwei, drei Häuserreihen)
const HILL_H := 115.0

var layout: Dictionary
var target: Node3D
var land_mat: ShaderMaterial
var house_mat: ShaderMaterial
var fog_mat: ShaderMaterial
var beacon_mat: ShaderMaterial
var _roof_mat: StandardMaterial3D
var _trunk_mat: StandardMaterial3D
var _crown_mat: StandardMaterial3D
var _tower_mat: StandardMaterial3D
var _blade_mat: StandardMaterial3D

var _road := {}  # Rasterzelle -> PackedVector2Array (Punkte alle 20 m auf Autobahnen und Auffahrten)
var _croad := {}  # dasselbe für die Straßen der Städte
var _froad := {}  # Waldstrecken: Landstraße ohne Häuser, der Wald reicht bis ans Bankett
var _urban := []
var _villages := []  # {pos, r, level, seed, name}
var _parks := []  # {pos, seed, dir}
var _lakes := []  # {pos, r, level}
var _lines := []  # Hochspannungsleitungen: Masten [Vector2] je Leitung
var _marks := []  # Wahrzeichen: {kind ("kraftwerk", "burg", "turm"), pos}
var _concrete_mat: StandardMaterial3D
var _steam_mat: StandardMaterial3D
var _water_mat: ShaderMaterial
var _steel_mat: StandardMaterial3D
var _hill := FastNoiseLite.new()
var _detail := FastNoiseLite.new()
var _forest := FastNoiseLite.new()
var _chunks := {}  # Vector2i -> Node3D (oder null, solange er gebaut wird)
var _task := -1
var _task_key := Vector2i.ZERO
var _task_out: Node3D
var _t := 0.0
var _rotors := []
var _tree_step := 9.0
var last_event := ""  # für --hitch: was die Landschaft in diesem Bild getan hat
var hold := Callable()  # true = gerade nicht bauen (die Welt baut eine Strecke: beide zugleich ruckelten)
var _meshes := {}

const VILLAGE_NAMES := ["Oberweiler", "Kirchheim", "Lindenau", "Birkenfeld", "Hohenstein", "Mühlbach", "Eichstetten", "Wiesental", "Rotenburg", "Sonnenberg", "Tannhausen", "Grünwald", "Steinach", "Haselbach", "Altdorf", "Buchholz", "Unterried", "Waldhausen", "Kleinfeld", "Bergrheinfeld", "Erlenbach", "Hirschau", "Fischbach", "Ahornhof", "Weidenstetten", "Lerchenau", "Rabenstein", "Moosbrunn", "Hagenau", "Kesselbach", "Ulmenhof", "Dornstetten", "Falkenried", "Brunnthal", "Eschenau", "Hüttenbach", "Kranichfeld", "Lauterbach", "Mittelweiler", "Neuhaus", "Ochsenfurt-Au", "Pfaffenhofen", "Quellbach", "Reichenau", "Schönwald", "Talheim", "Uhlenhorst", "Vogelsang", "Wolfsried", "Zellerau", "Amselfeld", "Bärental", "Dachsberg", "Eulenbach", "Fuchsstadt", "Gänsewies", "Hasenmühle", "Igelsbach", "Krähenwinkel", "Lindenhof", "Marderau", "Nesselried", "Otterbach", "Rehweiler"]


func setup(lay: Dictionary) -> void:
	layout = lay
	# Die Kamera sieht nur so weit wie die Sichtweite (600-1400 m); weiter draußen stehen die Hügel im Himmel
	VIEW = maxf(GameState.view_distance() + 700.0, 1300.0)
	_tree_step = [13.0, 11.0, 9.5, 9.0][clampi(int(GameState.gfx.get("detail", 2)), 0, 3)]
	if OS.has_feature("web"):
		_tree_step = maxf(_tree_step, 13.0)
	_hill.seed = 2029
	_hill.frequency = 1.0 / 1900.0
	_hill.fractal_octaves = 3
	_detail.seed = 77
	_detail.frequency = 1.0 / 420.0
	_detail.fractal_octaves = 2
	_forest.seed = 4242
	_forest.frequency = 1.0 / 750.0
	_forest.fractal_octaves = 3
	# Autobahn, Kreisel, Diagonalen und Auffahrten: flach bis ROAD_FLAT; Stadtstraßen (mit Häusern daneben) bis CITY_FLAT
	for rd in layout["roads"]:
		if rd[1] == 1:
			_add_line(_road, rd[0])
	for sg in layout["segments"]:
		var pl := PackedVector2Array()
		for q in sg["race"]["pts"]:
			pl.append(Vector2(q.x, q.z))
		_add_line(_road, pl)
	for c in layout["cities"]:
		var forest: bool = c.get("forest", false) or Catalog.RACES[c["race_index"]].get("forest", false) if c.has("race_index") else c.get("forest", false)
		for rd in c["roads"]:
			_add_line(_froad if forest else _croad, rd[0])
		for q in c.get("bld_world", PackedVector2Array()):
			var cell := Vector2i(floori(q.x / ROAD_CELL), floori(q.y / ROAD_CELL))
			var arr: PackedVector2Array = _croad.get(cell, PackedVector2Array())
			arr.append(q)
			_croad[cell] = arr
	_urban = layout.get("urban", [])
	_plan_sites()
	_make_materials()
	_make_mask()


func _add_line(grid: Dictionary, pl: PackedVector2Array) -> void:
	for k in pl.size() - 1:
		var a := pl[k]
		var b := pl[k + 1]
		var n := maxi(int(a.distance_to(b) / 20.0), 1)
		for j in n + 1:
			var p := a.lerp(b, j / float(n))
			var c := Vector2i(floori(p.x / ROAD_CELL), floori(p.y / ROAD_CELL))
			var arr: PackedVector2Array = grid.get(c, PackedVector2Array())
			arr.append(p)
			grid[c] = arr  # Packed-Arrays kommen als Kopie aus dem Dictionary: zurückschreiben


## Abstand zur nächsten Straße im Raster grid (bis 500 m genau; nichts gefunden: 10 km). Flachzone plus Anstieg
## (CITY_FLAT + RISE) bleiben unter 500 m, so springt das Gelände an der Suchgrenze nicht (bis 2.29 nur 400 m:
## die Hügel erreichten nie ihre volle Höhe)
func _dist(grid: Dictionary, p: Vector2) -> float:
	var c := Vector2i(floori(p.x / ROAD_CELL), floori(p.y / ROAD_CELL))
	var best := 1e8
	for dy in range(-5, 6):
		for dx in range(-5, 6):
			var arr = grid.get(c + Vector2i(dx, dy))
			if arr == null:
				continue
			for q in arr:
				best = minf(best, p.distance_squared_to(q))
	return sqrt(best)


func road_dist(p: Vector2) -> float:
	return _dist(_road, p)


func city_dist(p: Vector2) -> float:
	return _dist(_croad, p)


## Wie weit ist p vom Rand der flachen Zone entfernt (unter 0: in der Zone neben einer Straße oder in der Stadt)?
func free_dist(p: Vector2) -> float:
	return minf(minf(road_dist(p) - ROAD_FLAT, city_dist(p) - CITY_FLAT), _dist(_froad, p) - FOREST_FLAT)


func forest_dist(p: Vector2) -> float:
	return _dist(_froad, p) if not _froad.is_empty() else 400.0


## Geländehöhe ohne Rücksicht auf Straßen (für Dörfer und Windparks)
func raw_height(p: Vector2) -> float:
	# Simplex liegt meist zwischen -0.5 und 0.5: auf 0..1 strecken, Kuppen betonen
	var n := clampf(_hill.get_noise_2d(p.x, p.y) * 1.1 + 0.5, 0.0, 1.0)
	return pow(n, 1.7) * HILL_H + _detail.get_noise_2d(p.x, p.y) * 12.0 + 6.0


## Höhe mit vorberechnetem Abstand zur flachen Zone (free_dist); unter 0 heißt: unter dem flachen Boden versteckt
func height_at(p: Vector2, free: float) -> float:
	if free <= 0.0:
		return -0.6
	var fade := smoothstep(0.0, RISE, free)
	var h := raw_height(p)
	for v in _villages:
		var dv := p.distance_to(v["pos"])
		if dv < v["r"] + 160.0:
			h = lerpf(v["level"], h, smoothstep(v["r"], v["r"] + 160.0, dv))
	for lk in _lakes:
		var dl := p.distance_to(lk["pos"])
		if dl < lk["r"] * 1.15 + 180.0:
			# Mulde: im See bis 5 m unter dem Wasser, am Ufer sanft hinauf ins Gelände (Ufer unregelmäßig, lake_r)
			var lr := lake_r(lk, (p - lk["pos"]).angle())
			var bowl: float = lk["level"] - 5.0 * (1.0 - clampf(dl / lr, 0.0, 1.0))
			if dl < lr:
				h = bowl
			else:
				h = lerpf(lk["level"] + 0.4, h, smoothstep(lr, lr + 180.0, dl))
	return fade * h - (1.0 - fade) * 0.6


func _plan_sites() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2029
	var ext: float = layout["ring_r"] + 5200.0
	var vi := 0
	var x := -ext
	while x < ext:
		var z := -ext
		while z < ext:
			var p := Vector2(x + rng.randf_range(200, 1100), z + rng.randf_range(200, 1100))
			var rd := road_dist(p)
			if rd >= 240.0 and city_dist(p) > 330.0 and rng.randf() < (0.85 if rd < 400.0 else 0.4):
				var ok := true
				for v in _villages:
					if p.distance_to(v["pos"]) < 1300.0:
						ok = false
				if ok:
					_villages.append({"pos": p, "r": rng.randf_range(90.0, 150.0), "level": raw_height(p), "seed": rng.randi(),
						"name": VILLAGE_NAMES[vi % VILLAGE_NAMES.size()]})
					vi += 1
			z += 1300.0
		x += 1300.0
	x = -ext
	while x < ext:
		var z := -ext
		while z < ext:
			var p := Vector2(x + rng.randf_range(200, 1500), z + rng.randf_range(200, 1500))
			var ok := road_dist(p) >= 280.0 and city_dist(p) > 400.0 and rng.randf() < 0.4
			for v in _villages:
				if p.distance_to(v["pos"]) < 700.0:
					ok = false
			if ok:
				_parks.append({"pos": p, "seed": rng.randi(), "n": rng.randi_range(3, 6)})
			z += 1700.0
		x += 1700.0
	# Seen: in freien Lagen (weit genug von Straße, Stadt, Dorf, Windpark), Wasser auf Geländehöhe
	x = -ext
	while x < ext:
		var z := -ext
		while z < ext:
			var p := Vector2(x + rng.randf_range(200, 1700), z + rng.randf_range(200, 1700))
			var r := rng.randf_range(110.0, 240.0)
			var ok := free_dist(p) > r + 90.0 and rng.randf() < 0.7
			for v in _villages:
				if p.distance_to(v["pos"]) < v["r"] + r + 250.0:
					ok = false
			for pk in _parks:
				if p.distance_to(pk["pos"]) < r + 700.0:
					ok = false
			if ok:
				_lakes.append({"pos": p, "r": r, "level": maxf(raw_height(p) - 2.0, 3.0)})
			z += 1900.0
		x += 1900.0
	# Hochspannungsleitungen: gerade Trassen quer über die Karte, Masten alle 320 m (nicht in der Flachzone an
	# Straßen und Städten, nicht in Dörfern und Seen); wo kein Mast stehen darf, wird die Leitung unterbrochen
	for li in 5:
		var ang := rng.randf() * PI
		var dir := Vector2.from_angle(ang)
		var off := dir.orthogonal() * rng.randf_range(-ext * 0.7, ext * 0.7)
		var masts := []
		var t := -ext
		while t < ext:
			var p := off + dir * t
			var ok := free_dist(p) > 40.0
			for v in _villages:
				if p.distance_to(v["pos"]) < v["r"] + 60.0:
					ok = false
			for lk in _lakes:
				if p.distance_to(lk["pos"]) < lk["r"] + 30.0:
					ok = false
			if ok:
				masts.append(p)
			elif masts.size() >= 2:
				_lines.append(masts)
				masts = []
			else:
				masts = []
			t += 320.0
		if masts.size() >= 2:
			_lines.append(masts)
	# Wahrzeichen: zwei Kraftwerke mit Kühltürmen (freie Lage), drei Burgen auf den höchsten freien Kuppen
	var tries := 0
	while _marks.filter(func(m): return m["kind"] == "kraftwerk").size() < 2 and tries < 400:
		tries += 1
		var p := Vector2(rng.randf_range(-ext, ext), rng.randf_range(-ext, ext)) * 0.8
		if free_dist(p) > 230.0 and _site_free(p, 520.0):
			_marks.append({"kind": "kraftwerk", "pos": p})
	var cands := []
	for k in 900:
		var p := Vector2(rng.randf_range(-ext, ext), rng.randf_range(-ext, ext)) * 0.85
		if free_dist(p) > 240.0:
			cands.append([raw_height(p), p])
	cands.sort_custom(func(a, b): return a[0] > b[0])
	for cd in cands:
		if _marks.filter(func(m): return m["kind"] == "burg").size() >= 3:
			break
		if _site_free(cd[1], 900.0):
			_marks.append({"kind": "burg", "pos": cd[1]})
	# Fernsehturm in der Mitte des Kreisels
	var rbc := Vector3.ZERO
	var urb: Array = layout.get("urban", [])
	if not urb.is_empty():
		rbc = urb[urb.size() - 1]
	_marks.append({"kind": "turm", "pos": Vector2(rbc.x, rbc.z)})


## Abstand zu Dörfern, Seen, Windparks und anderen Wahrzeichen
func _site_free(p: Vector2, gap: float) -> bool:
	for v in _villages:
		if p.distance_to(v["pos"]) < v["r"] + gap * 0.5:
			return false
	for lk in _lakes:
		if p.distance_to(lk["pos"]) < lk["r"] + gap * 0.4:
			return false
	for pk in _parks:
		if p.distance_to(pk["pos"]) < gap * 0.6:
			return false
	for m in _marks:
		if p.distance_to(m["pos"]) < gap:
			return false
	return true


func _make_materials() -> void:
	land_mat = ShaderMaterial.new()
	land_mat.shader = LAND_SHADER
	house_mat = ShaderMaterial.new()
	house_mat.shader = HOUSE_SHADER
	fog_mat = Mist.material()
	beacon_mat = ShaderMaterial.new()
	beacon_mat.shader = BEACON_SHADER
	_roof_mat = StandardMaterial3D.new()
	_roof_mat.vertex_color_use_as_albedo = true
	_roof_mat.roughness = 0.8
	_trunk_mat = StandardMaterial3D.new()
	_trunk_mat.albedo_color = Color(0.2, 0.14, 0.09)
	_crown_mat = StandardMaterial3D.new()
	_crown_mat.vertex_color_use_as_albedo = true
	_crown_mat.roughness = 0.95
	_tower_mat = StandardMaterial3D.new()
	_tower_mat.albedo_color = Color(0.86, 0.87, 0.88)
	_tower_mat.roughness = 0.5
	_blade_mat = StandardMaterial3D.new()
	_blade_mat.albedo_color = Color(0.9, 0.91, 0.92)
	_blade_mat.roughness = 0.4
	_concrete_mat = StandardMaterial3D.new()
	_concrete_mat.albedo_color = Color(0.68, 0.67, 0.64)
	_concrete_mat.roughness = 0.9
	_concrete_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_steam_mat = StandardMaterial3D.new()
	_steam_mat.albedo_color = Color(0.95, 0.96, 0.98, 0.75)
	_steam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_steam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	_steam_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = WATER_SHADER
	_water_mat.set_shader_parameter("mirror", 0.6)
	_steel_mat = StandardMaterial3D.new()
	_steel_mat.albedo_color = Color(0.55, 0.57, 0.6)
	_steel_mat.metallic = 0.6
	_steel_mat.roughness = 0.45
	_meshes["conifer"] = _tree_mesh(true)
	_meshes["leafy"] = _tree_mesh(false)
	var box := BoxMesh.new()
	_meshes["box"] = box
	_meshes["roof"] = _roof_mesh()


## Stadtboden als Maske für den Bodenshader (seit 2.29 haben Städte in der Open World keinen eigenen dunklen Boden
## mehr, sonst endeten sie an einem harten Quadrat mitten in den Feldern): um Stadtstraßen und die Stadtabschnitte
## der Autobahn dunkler Asphalt- und Pflasterboden, weich in die Felder übergehend.
func _make_mask() -> void:
	var S := 1024
	var ext: float = layout["ring_r"] + 5200.0
	var img := Image.create(S, S, false, Image.FORMAT_RG8)
	var k := S / (2.0 * ext)
	var paint := func(p: Vector2, r: float, col := Color(1, 0, 0)) -> void:
		var c := Vector2i(int((p.x + ext) * k), int((p.y + ext) * k))
		var rr := maxi(int(r * k), 1)
		img.fill_rect(Rect2i(c.x - rr, c.y - rr, rr * 2 + 1, rr * 2 + 1), col)
	for arr in _froad.values():
		for q in arr:
			paint.call(q, 380.0, Color(0, 1, 0))  # Waldboden
	for arr in _croad.values():
		for q in arr:
			paint.call(q, 125.0)
	for arr in _road.values():
		for q in arr:
			if Layout.is_urban(Vector3(q.x, 0, q.y), _urban, -150.0):
				paint.call(q, 70.0)
	img.resize(S / 8, S / 8, Image.INTERPOLATE_BILINEAR)
	img.resize(S, S, Image.INTERPOLATE_CUBIC)
	land_mat.set_shader_parameter("urban_mask", ImageTexture.create_from_image(img))
	land_mat.set_shader_parameter("mask_rect", Vector3(-ext, -ext, 2.0 * ext))


## Reliefkarte für die große Karte (seit 2.29): Hügel schattiert, Wald grün, Stadt grau, auf Kartenfarben abgedunkelt
func map_texture(lo: Vector2, hi: Vector2, px := 220) -> ImageTexture:
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var ext := hi - lo
	var mask: Texture2D = land_mat.get_shader_parameter("urban_mask")
	var mimg: Image = mask.get_image() if mask else null
	var mr: Vector3 = land_mat.get_shader_parameter("mask_rect")
	for j in px:
		for i in px:
			var p := lo + Vector2((i + 0.5) / px * ext.x, (j + 0.5) / px * ext.y)
			var h := raw_height(p)
			var hx := raw_height(p + Vector2(60, 0))
			var hz := raw_height(p + Vector2(0, 60))
			var shade := clampf(0.5 + (h - hx) * 0.02 + (h - hz) * 0.02, 0.0, 1.0)
			var c := Color(0.05, 0.07, 0.1).lerp(Color(0.13, 0.17, 0.2), shade)
			var f := _forest.get_noise_2d(p.x, p.y)
			if f > 0.1:
				c = c.lerp(Color(0.05, 0.2, 0.1), 0.7)
			if mimg:
				var u := (p - Vector2(mr.x, mr.y)) / mr.z
				var mp := mimg.get_pixel(clampi(int(u.x * mimg.get_width()), 0, mimg.get_width() - 1), clampi(int(u.y * mimg.get_height()), 0, mimg.get_height() - 1))
				c = c.lerp(Color(0.16, 0.17, 0.2), smoothstep(0.3, 0.6, mp.r))
				c = c.lerp(Color(0.04, 0.22, 0.1), smoothstep(0.3, 0.6, mp.g) * 0.8)
			img.set_pixel(i, j, c)
	return ImageTexture.create_from_image(img)


## Dörfer für die Karte: [Lage, Name]
func villages() -> Array:
	return _villages.map(func(v): return [v["pos"], v["name"]])


## Tag/Nacht: day 0..1 (aus der Weltuhr), fog_k 0..1 (Nebelstärke für die Nebelbänke)
func set_daylight(day: float, fog_k: float) -> void:
	land_mat.set_shader_parameter("day", day)
	house_mat.set_shader_parameter("night", 1.0 - smoothstep(0.15, 0.55, day))
	beacon_mat.set_shader_parameter("night", 1.0 - smoothstep(0.2, 0.6, day))
	fog_mat.set_shader_parameter("strength", fog_k)
	fog_mat.set_shader_parameter("tint", Color(0.55, 0.6, 0.72).lerp(Color(0.85, 0.85, 0.82), day))


# --- Bauen ------------------------------------------------------------------------------------------------------

## Alles in der Nähe sofort bauen (hinter dem Ladebild)
func build_near(p: Vector3, radius := 1600.0) -> void:
	if _web():
		return
	for key in _wanted(p, radius):
		var n := build_chunk(key)
		_chunks[key] = n
		add_child(n)


func _wanted(p: Vector3, radius: float) -> Array:
	var out := []
	var c := Vector2i(floori(p.x / CHUNK), floori(p.z / CHUNK))
	var r := int(ceil(radius / CHUNK)) + 1
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var k := c + Vector2i(dx, dy)
			var mid := (Vector2(k) + Vector2(0.5, 0.5)) * CHUNK
			if mid.distance_to(Vector2(p.x, p.z)) < radius + CHUNK * 0.71:
				out.append(k)
	out.sort_custom(func(a, b): return (Vector2(a) + Vector2(0.5, 0.5)).distance_to(Vector2(p.x, p.z) / CHUNK) \
		< (Vector2(b) + Vector2(0.5, 0.5)).distance_to(Vector2(p.x, p.z) / CHUNK))
	return out


func _process(dt: float) -> void:
	for r in _rotors:
		if is_instance_valid(r):
			(r as Node3D).rotate_object_local(Vector3.FORWARD, dt * 1.1)
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if _chunks.has(_task_key):
			_chunks[_task_key] = _task_out
			var t0 := Time.get_ticks_usec()
			add_child(_task_out)
			last_event = "land+%.1fms" % ((Time.get_ticks_usec() - t0) / 1000.0)
			for r in _task_out.get_meta("rotors", []):
				_rotors.append(r)
		else:
			_task_out.free()
	_t -= dt
	if _t > 0.0 or target == null or not is_instance_valid(target) or _web():
		return
	_t = 0.4
	var p := target.global_position
	# entfernte Kacheln weg
	for key in _chunks.keys():
		var mid := (Vector2(key) + Vector2(0.5, 0.5)) * CHUNK
		if mid.distance_to(Vector2(p.x, p.z)) > VIEW + CHUNK * 1.5 and _chunks[key] != null:
			var n: Node3D = _chunks[key]
			for r in n.get_meta("rotors", []):
				_rotors.erase(r)
			n.queue_free()
			_chunks.erase(key)
	if _task >= 0 or (hold.is_valid() and hold.call()):
		return
	for key in _wanted(p, VIEW):
		if not _chunks.has(key):
			_chunks[key] = null
			_task_key = key
			if DisplayServer.get_name() == "headless":
				_task_out = build_chunk(key)
				_chunks[key] = _task_out
				add_child(_task_out)
				for r in _task_out.get_meta("rotors", []):
					_rotors.append(r)
			else:
				_task = WorkerThreadPool.add_task(func(): _task_out = build_chunk(key))
			return


## Im Browser (ohne Threads) nur der Feldboden: das Bauen einer Kachel dauert dort ein paar hundert Millisekunden am
## Stück und ruckelte bei jeder neuen Kachel
func _web() -> bool:
	return OS.has_feature("web")


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if _task_out and not _task_out.is_inside_tree():
			_task_out.free()


func build_chunk(key: Vector2i) -> Node3D:
	var root := Node3D.new()
	root.name = "Land_%d_%d" % [key.x, key.y]
	var o := Vector2(key) * CHUNK
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key) + 99
	# Straßenabstand und Höhe auf dem Gitter
	var dr := PackedFloat32Array()
	var hs := PackedFloat32Array()
	dr.resize((N + 1) * (N + 1))
	hs.resize((N + 1) * (N + 1))
	var any := false
	for j in N + 1:
		for i in N + 1:
			var p := o + Vector2(i, j) * STEP
			var d := free_dist(p)
			dr[j * (N + 1) + i] = d
			var h := height_at(p, d)
			hs[j * (N + 1) + i] = h
			any = any or h > 0.0
	if any:
		_terrain(root, o, hs)
	_trees(root, o, dr, rng)
	for v in _villages:
		if _in_chunk(v["pos"], o):
			_village(root, v)
	for pk in _parks:
		if _in_chunk(pk["pos"], o):
			_windpark(root, pk)
	for lk in _lakes:
		if _in_chunk(lk["pos"], o):
			_lake(root, lk)
	_power_lines(root, o)
	for m in _marks:
		if _in_chunk(m["pos"], o):
			_landmark(root, m)
	_fog_banks(root, o, dr, hs, rng)
	return root


func _in_chunk(p: Vector2, o: Vector2) -> bool:
	return p.x >= o.x and p.x < o.x + CHUNK and p.y >= o.y and p.y < o.y + CHUNK


func _grid_h(o: Vector2, hs: PackedFloat32Array, p: Vector2) -> float:
	var g := (p - o) / STEP
	var i := clampi(int(g.x), 0, N - 1)
	var j := clampi(int(g.y), 0, N - 1)
	var fx := clampf(g.x - i, 0.0, 1.0)
	var fy := clampf(g.y - j, 0.0, 1.0)
	var a := lerpf(hs[j * (N + 1) + i], hs[j * (N + 1) + i + 1], fx)
	var b := lerpf(hs[(j + 1) * (N + 1) + i], hs[(j + 1) * (N + 1) + i + 1], fx)
	return lerpf(a, b, fy)


func _terrain(root: Node3D, o: Vector2, hs: PackedFloat32Array) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var W := N + 1
	var nrm := PackedVector3Array()
	nrm.resize(W * W)
	for j in W:
		for i in W:
			var hl := hs[j * W + maxi(i - 1, 0)]
			var hr := hs[j * W + mini(i + 1, N)]
			var hd := hs[maxi(j - 1, 0) * W + i]
			var hu := hs[mini(j + 1, N) * W + i]
			nrm[j * W + i] = Vector3(hl - hr, 2.0 * STEP, hd - hu).normalized()
	for j in N:
		for i in N:
			var a := j * W + i
			var b := a + 1
			var c := a + W
			var d := c + 1
			for tri in [[a, d, b], [a, c, d]]:
				if maxf(hs[tri[0]], maxf(hs[tri[1]], hs[tri[2]])) <= -0.1:
					continue
				for v in tri:
					st.set_normal(nrm[v])
					st.add_vertex(Vector3(o.x + (v % W) * STEP, hs[v], o.y + (v / W) * STEP))
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = land_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## Wälder: dichte Bestände, wo das Waldrauschen hoch ist, Nadel- und Laubbäume gemischt; dazu einzelne Bäume
## und Baumreihen auf den Feldern. Nicht nah an Straßen, nicht in Stadtnähe, nicht im Dorf.
func _trees(root: Node3D, o: Vector2, dr: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	var lists := {"conifer": [], "leafy": []}
	var cols := {"conifer": [], "leafy": []}
	var step := _tree_step
	var hs_cache := {}
	var y := 0.0
	while y < CHUNK:
		var x := 0.0
		while x < CHUNK:
			var p := o + Vector2(x + rng.randf_range(0, step), y + rng.randf_range(0, step))
			x += step
			var f := _forest.get_noise_2d(p.x, p.y)
			var fd := forest_dist(p)
			if fd < 420.0:
				f = maxf(f, 0.35 - fd / 1600.0)  # an der Waldstrecke dichter Wald
			var single := rng.randf() < 0.0025
			if f < 0.1 and not single:
				continue
			var g := (p - o) / STEP
			var i := clampi(int(g.x), 0, N - 1)
			var j := clampi(int(g.y), 0, N - 1)
			var d := dr[j * (N + 1) + i]
			if d < -20.0 and not (fd < 60.0 and fd > 16.0 and d > -FOREST_FLAT + 16.0):
				continue  # Autobahn: ab 35 m Bäume; Stadt: erst hinter den Häusern; Waldstrecke: ab dem Bankett
			if d < 90.0 and Layout.is_urban(Vector3(p.x, 0, p.y), _urban, 150.0):
				continue
			if f < 0.17 and not single and rng.randf() < 0.6:
				continue  # Waldrand lichter
			if f < 0.1 and single and rng.randf() < 0.7:
				continue
			var skip := false
			for v in _villages:
				if p.distance_to(v["pos"]) < v["r"] + 15.0:
					skip = true
			for pk in _parks:
				if p.distance_to(pk["pos"]) < 600.0 and rng.randf() < 0.85:
					skip = true
			for lk in _lakes:
				if p.distance_to(lk["pos"]) < lk["r"] + 12.0:
					skip = true
			for m in _marks:
				if p.distance_to(m["pos"]) < (160.0 if m["kind"] == "kraftwerk" else 70.0):
					skip = true
			if skip:
				continue
			var h := maxf(height_at(p, d), -0.12)
			var kind := "conifer" if _detail.get_noise_2d(p.x * 3.0, p.y * 3.0) > -0.05 else "leafy"
			var s := rng.randf_range(0.75, 1.35)
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.85, 1.2), s))
			(lists[kind] as Array).append(Transform3D(b, Vector3(p.x, h - 0.2, p.y)))
			var c := Color(0.09, 0.2, 0.08) if kind == "conifer" else Color(0.16, 0.3, 0.09)
			(cols[kind] as Array).append(c * rng.randf_range(0.75, 1.2))
		y += step
	for kind in lists:
		var arr: Array = lists[kind]
		if arr.is_empty():
			continue
		var mm := _multimesh(_meshes[kind], arr, cols[kind])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = VIEW - 300.0
		root.add_child(mi)


## MultiMesh mit Farben in einem Stück füllen (ein Aufruf an den Renderer statt zwei je Instanz: beim Bauen im
## Hintergrund-Thread blockierten tausende Einzelaufrufe den Hauptthread)
func _multimesh(mesh: Mesh, xfs: Array, cols: Array) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	var buf := PackedFloat32Array()
	buf.resize(xfs.size() * 16)
	for k in xfs.size():
		var t: Transform3D = xfs[k]
		var c: Color = cols[k]
		var o := k * 16
		buf[o] = t.basis.x.x
		buf[o + 1] = t.basis.y.x
		buf[o + 2] = t.basis.z.x
		buf[o + 3] = t.origin.x
		buf[o + 4] = t.basis.x.y
		buf[o + 5] = t.basis.y.y
		buf[o + 6] = t.basis.z.y
		buf[o + 7] = t.origin.y
		buf[o + 8] = t.basis.x.z
		buf[o + 9] = t.basis.y.z
		buf[o + 10] = t.basis.z.z
		buf[o + 11] = t.origin.z
		buf[o + 12] = c.r
		buf[o + 13] = c.g
		buf[o + 14] = c.b
		buf[o + 15] = c.a
	mm.buffer = buf
	return mm


func _tree_mesh(conifer: bool) -> ArrayMesh:
	var am := ArrayMesh.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.25
	trunk.bottom_radius = 0.35
	trunk.height = 4.0 if conifer else 3.6
	trunk.radial_segments = 5
	trunk.rings = 1
	var st := SurfaceTool.new()
	st.append_from(trunk, 0, Transform3D(Basis(), Vector3(0, trunk.height / 2.0, 0)))
	st.commit(am)
	am.surface_set_material(0, _trunk_mat)
	var st2 := SurfaceTool.new()
	if conifer:
		for k in 3:
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 3.0 - k * 0.7
			cone.height = 5.0 - k * 0.6
			cone.radial_segments = 7
			cone.rings = 1
			st2.append_from(cone, 0, Transform3D(Basis(), Vector3(0, 3.0 + k * 2.6 + cone.height / 2.0, 0)))
	else:
		var sph := SphereMesh.new()
		sph.radius = 3.2
		sph.height = 5.6
		sph.radial_segments = 7
		sph.rings = 4
		st2.append_from(sph, 0, Transform3D(Basis(), Vector3(0, 5.8, 0)))
		var sph2 := SphereMesh.new()
		sph2.radius = 2.2
		sph2.height = 3.8
		sph2.radial_segments = 6
		sph2.rings = 3
		st2.append_from(sph2, 0, Transform3D(Basis(), Vector3(1.4, 7.4, 0.6)))
	st2.commit(am)
	am.surface_set_material(1, _crown_mat)
	return am


## Satteldach: Grundfläche 1 × 1 (x quer, z längs), First in z-Richtung auf Höhe 1
func _roof_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(-0.5, 0, -0.5)
	var b := Vector3(0.5, 0, -0.5)
	var c := Vector3(0.5, 0, 0.5)
	var d := Vector3(-0.5, 0, 0.5)
	var t0 := Vector3(0, 1, -0.5)
	var t1 := Vector3(0, 1, 0.5)
	var quads := [[a, t0, t1, d], [b, c, t1, t0]]
	for q in quads:
		var n: Vector3 = (q[1] - q[0]).cross(q[3] - q[0]).normalized()
		for v in [q[0], q[1], q[2], q[0], q[2], q[3]]:
			st.set_normal(n)
			st.add_vertex(v)
	for g in [[a, b, t0], [c, d, t1]]:
		var n: Vector3 = (g[1] - g[0]).cross(g[2] - g[0]).normalized()
		for v in g:
			st.set_normal(n)
			st.add_vertex(v)
	return st.commit()


## Dorf: Häuser um einen Kern mit Kirche, Satteldächer in Ziegelrot und Schiefer, Putz in hellen Farben
func _village(root: Node3D, v: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = v["seed"]
	var c: Vector2 = v["pos"]
	var y0: float = v["level"]
	var walls := []
	var wcols := []
	var roofs := []
	var rcols := []
	var put := [Color(0.92, 0.9, 0.84), Color(0.95, 0.88, 0.7), Color(0.86, 0.84, 0.8), Color(0.9, 0.8, 0.72),
		Color(0.8, 0.82, 0.78), Color(0.96, 0.94, 0.9), Color(0.85, 0.7, 0.55)]
	var dach := [Color(0.5, 0.16, 0.08), Color(0.42, 0.13, 0.07), Color(0.2, 0.21, 0.24), Color(0.55, 0.22, 0.1)]
	var placed := []
	# Kirche in der Mitte
	var ang0 := rng.randf() * TAU
	var cb := Basis(Vector3.UP, ang0)
	walls.append(Transform3D(cb.scaled(Vector3(11, 9, 22)), Vector3(c.x, y0 + 4.5, c.y)))
	wcols.append(Color(0.93, 0.91, 0.86))
	roofs.append(Transform3D(cb.scaled(Vector3(12, 7, 23)), Vector3(c.x, y0 + 9.0, c.y)))
	rcols.append(Color(0.45, 0.14, 0.08))
	var tower_p := Vector3(c.x, y0, c.y) + cb * Vector3(0, 0, -13.5)
	var tw := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(5.5, 26, 5.5)
	tw.mesh = tb
	tw.material_override = _tower_mat
	tw.position = tower_p + Vector3(0, 13, 0)
	tw.rotation.y = ang0
	root.add_child(tw)
	var sp := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 4.0
	cone.height = 14.0
	cone.radial_segments = 4
	cone.rings = 1
	sp.mesh = cone
	var spm := StandardMaterial3D.new()
	spm.albedo_color = Color(0.18, 0.2, 0.24)
	sp.material_override = spm
	sp.position = tower_p + Vector3(0, 33, 0)
	sp.rotation.y = ang0 + PI / 4.0
	root.add_child(sp)
	placed.append([c, 16.0])
	# Häuser
	var n := int(v["r"] / 5.0)
	for k in n:
		for attempt in 6:
			var a := rng.randf() * TAU
			var rr: float = sqrt(rng.randf()) * float(v["r"])
			var p := c + Vector2(cos(a), sin(a)) * rr
			var w := rng.randf_range(8.0, 13.0)
			var dp := rng.randf_range(9.0, 14.0)
			var free := true
			for q in placed:
				if p.distance_to(q[0]) < q[1] + maxf(w, dp) * 0.6:
					free = false
					break
			if not free:
				continue
			var hgt := rng.randf_range(5.5, 8.5)
			# Häuser zur Dorfmitte ausgerichtet (Straßendorf-Gefühl), leicht verdreht
			var b := Basis(Vector3.UP, -a + rng.randf_range(-0.25, 0.25))
			walls.append(Transform3D(b.scaled(Vector3(w, hgt, dp)), Vector3(p.x, y0 + hgt / 2.0 - 0.3, p.y)))
			wcols.append(put[rng.randi() % put.size()])
			roofs.append(Transform3D(b.scaled(Vector3(w + 0.8, rng.randf_range(3.5, 5.5), dp + 0.8)), Vector3(p.x, y0 + hgt - 0.3, p.y)))
			rcols.append(dach[rng.randi() % dach.size()] * rng.randf_range(0.85, 1.1))
			placed.append([p, maxf(w, dp) * 0.6])
			break
	for set in [[walls, wcols, _meshes["box"], house_mat], [roofs, rcols, _meshes["roof"], _roof_mat]]:
		var mm := _multimesh(set[2], set[0], set[1])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = set[3]
		root.add_child(mi)
	_village_road(root, v)
	# Dorflicht: eine Laterne an der Kirche (warm), damit das Dorf nachts von weitem zu sehen ist
	var ol := OmniLight3D.new()
	ol.light_color = Color(1.0, 0.7, 0.4)
	ol.light_energy = 1.5
	ol.omni_range = 60.0
	ol.position = Vector3(c.x, y0 + 6.0, c.y)
	ol.distance_fade_enabled = true
	ol.distance_fade_begin = 1200.0
	ol.distance_fade_length = 300.0
	ol.shadow_enabled = false
	root.add_child(ol)


## Wahrzeichen: Kraftwerk mit Kühltürmen und Dampf, Burg auf der Kuppe, Fernsehturm am Kreisel
func _landmark(root: Node3D, m: Dictionary) -> void:
	var p: Vector2 = m["pos"]
	var h := maxf(height_at(p, free_dist(p)), 0.0) - 0.5
	var base := Vector3(p.x, h, p.y)
	var add := func(mesh: Mesh, mat: Material, pos: Vector3, rot := 0.0) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = pos
		mi.rotation.y = rot
		root.add_child(mi)
		return mi
	match m["kind"]:
		"kraftwerk":
			# zwei Kühltürme (taillierte Schale aus drei Kegelstümpfen), Maschinenhaus, rot-weißer Schornstein
			for k in 2:
				var tp := base + Vector3(k * 120.0 - 60.0, 0, 0)
				if not _meshes.has("cooling"):
					_meshes["cooling"] = _cooling_tower()
				add.call(_meshes["cooling"], _concrete_mat, tp)
				# Dampfwolke über dem Turm
				for c in 4:
					var sp := SphereMesh.new()
					sp.radius = 26.0 + c * 6.0
					sp.height = (26.0 + c * 6.0) * 1.4
					sp.radial_segments = 12
					sp.rings = 6
					var sm := add.call(sp, _steam_mat, tp + Vector3(c * 9.0, 140.0 + c * 22.0, c * 4.0)) as MeshInstance3D
					sm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var hall := BoxMesh.new()
			hall.size = Vector3(110, 35, 50)
			add.call(hall, _tower_mat, base + Vector3(0, 17.5, 110))
			for k in 6:
				var cs := CylinderMesh.new()
				cs.top_radius = 3.0
				cs.bottom_radius = 3.6
				cs.height = 25.0
				cs.radial_segments = 12
				cs.rings = 1
				var red := StandardMaterial3D.new()
				red.albedo_color = Color(0.75, 0.1, 0.08) if k % 2 == 0 else Color(0.92, 0.92, 0.9)
				add.call(cs, red, base + Vector3(80, 12.5 + k * 25.0, 110))
			var lamp := BoxMesh.new()
			lamp.size = Vector3(1.5, 1.0, 1.5)
			add.call(lamp, beacon_mat, base + Vector3(80, 151, 110))
		"burg":
			# Burg: Ringmauer, Bergfried, Palas mit Dach, zwei Ecktürme
			var stone := StandardMaterial3D.new()
			stone.albedo_color = Color(0.55, 0.5, 0.44)
			stone.roughness = 0.95
			var roof := StandardMaterial3D.new()
			roof.albedo_color = Color(0.3, 0.12, 0.08)
			for k in 4:
				var wall := BoxMesh.new()
				wall.size = Vector3(70, 10, 3) if k % 2 == 0 else Vector3(3, 10, 50)
				var wp := Vector3(0, 5, 25 if k == 0 else -25) if k % 2 == 0 else Vector3(35 if k == 1 else -35, 5, 0)
				add.call(wall, stone, base + wp)
			var keep := BoxMesh.new()
			keep.size = Vector3(11, 38, 11)
			add.call(keep, stone, base + Vector3(-18, 19, -6))
			var kr := CylinderMesh.new()
			kr.top_radius = 0.0
			kr.bottom_radius = 8.5
			kr.height = 10.0
			kr.radial_segments = 4
			add.call(kr, roof, base + Vector3(-18, 43, -6), PI / 4.0)
			var palas := BoxMesh.new()
			palas.size = Vector3(30, 16, 14)
			add.call(palas, stone, base + Vector3(14, 8, 4))
			var pr := PrismMesh.new()
			pr.size = Vector3(30, 8, 14)
			var prm := add.call(pr, roof, base + Vector3(14, 20, 4)) as MeshInstance3D
			prm.rotation.y = 0.0
			for cx in [-35.0, 35.0]:
				var tw := CylinderMesh.new()
				tw.top_radius = 4.5
				tw.bottom_radius = 5.0
				tw.height = 16.0
				tw.radial_segments = 12
				add.call(tw, stone, base + Vector3(cx, 8, 25))
				var tc := CylinderMesh.new()
				tc.top_radius = 0.0
				tc.bottom_radius = 5.6
				tc.height = 7.0
				tc.radial_segments = 12
				add.call(tc, roof, base + Vector3(cx, 19.5, 25))
			var ol := OmniLight3D.new()
			ol.light_color = Color(1.0, 0.75, 0.45)
			ol.light_energy = 2.0
			ol.omni_range = 45.0
			ol.position = base + Vector3(0, 12, 0)
			ol.distance_fade_enabled = true
			ol.distance_fade_begin = 1000.0
			root.add_child(ol)
		"turm":
			# Fernsehturm: Betonschaft, Kugel mit Aussichtsfenstern, Antenne mit Gefahrenfeuer
			var shaft := CylinderMesh.new()
			shaft.top_radius = 4.5
			shaft.bottom_radius = 9.0
			shaft.height = 190.0
			shaft.radial_segments = 20
			shaft.rings = 1
			add.call(shaft, _concrete_mat, base + Vector3(0, 95, 0))
			var ball := SphereMesh.new()
			ball.radius = 16.0
			ball.height = 30.0
			ball.radial_segments = 24
			ball.rings = 12
			add.call(ball, _tower_mat, base + Vector3(0, 195, 0))
			var ring := CylinderMesh.new()
			ring.top_radius = 16.4
			ring.bottom_radius = 16.4
			ring.height = 2.2
			ring.radial_segments = 24
			var glass := StandardMaterial3D.new()
			glass.albedo_color = Color(0.1, 0.12, 0.16)
			glass.emission_enabled = true
			glass.emission = Color(1.0, 0.8, 0.5)
			glass.emission_energy_multiplier = 0.8
			add.call(ring, glass, base + Vector3(0, 195, 0))
			var ant := CylinderMesh.new()
			ant.top_radius = 0.6
			ant.bottom_radius = 1.6
			ant.height = 60.0
			ant.radial_segments = 8
			var red := StandardMaterial3D.new()
			red.albedo_color = Color(0.8, 0.12, 0.08)
			add.call(ant, red, base + Vector3(0, 240, 0))
			var lamp := BoxMesh.new()
			lamp.size = Vector3(1.4, 1.2, 1.4)
			add.call(lamp, beacon_mat, base + Vector3(0, 271, 0))


## Kühlturm: Rotationshyperboloid (Taille bei 2/3 der Höhe), 130 m hoch, innen und außen sichtbar
func _cooling_tower() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var H := 130.0
	var segs := 32
	var rings := 14
	var prof := func(y: float) -> float:
		var t := (y - H * 0.68) / (H * 0.42)
		return 27.0 * sqrt(1.0 + t * t * 1.6)
	for j in rings:
		var y0 := H * j / rings
		var y1 := H * (j + 1) / rings
		var r0: float = prof.call(y0)
		var r1: float = prof.call(y1)
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			var p00 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
			var p01 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
			var p10 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
			var p11 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
			for v in [p00, p10, p11, p00, p11, p01]:
				st.set_normal(Vector3(v.x, 0, v.z).normalized())
				st.add_vertex(v)
	var m := st.commit()
	return m


## Kreisstraße vom Dorf zur nächsten Autobahn oder Stadtstraße (nur Optik, folgt dem Gelände, endet vor der
## Leitplanke): ohne sie standen die Dörfer wie abgeworfen mitten in den Feldern
func _village_road(root: Node3D, v: Dictionary) -> void:
	var c: Vector2 = v["pos"]
	var best := 1e12
	var q := Vector2.ZERO
	var cc := Vector2i(floori(c.x / ROAD_CELL), floori(c.y / ROAD_CELL))
	for grid in [_road, _croad]:
		for dy in range(-9, 10):
			for dx in range(-9, 10):
				var arr = grid.get(cc + Vector2i(dx, dy))
				if arr == null:
					continue
				for p in arr:
					var d2 := c.distance_squared_to(p)
					if d2 < best:
						best = d2
						q = p
	if best > 1100.0 * 1100.0:
		return
	var len := sqrt(best)
	var dir := (q - c) / len
	var side := dir.orthogonal()
	var bend := (absi(int(c.x * 3.0 + c.y)) % 5 - 2) * 0.12 * len
	var pts := PackedVector2Array()
	var n := maxi(int(len / 10.0), 2)
	for k in n + 1:
		var t := float(k) / n
		var p: Vector2 = c.lerp(q, t) + side * sin(t * PI) * bend
		if p.distance_to(q) < 28.0:
			break
		pts.append(p)
	if pts.size() < 2:
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := 3.0
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for k in pts.size():
		var a: Vector2 = pts[maxi(k - 1, 0)]
		var b: Vector2 = pts[mini(k + 1, pts.size() - 1)]
		var nrm := (b - a).normalized().orthogonal()
		var p: Vector2 = pts[k]
		var lp := p + nrm * hw
		var rp := p - nrm * hw
		var l3 := Vector3(lp.x, maxf(height_at(lp, free_dist(lp)), -0.12) + 0.08, lp.y)
		var r3 := Vector3(rp.x, maxf(height_at(rp, free_dist(rp)), -0.12) + 0.08, rp.y)
		if k > 0:
			for vtx in [prev_l, l3, r3, prev_l, r3, prev_r]:
				st.set_normal(Vector3.UP)
				st.add_vertex(vtx)
		prev_l = l3
		prev_r = r3
	var mi := MeshInstance3D.new()
	st.generate_normals()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.13, 0.13, 0.14)
	m.roughness = 0.85
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## Windpark: drei bis sechs Anlagen in einer lockeren Reihe, alle mit dem Wind (aus Westen) ausgerichtet
func _windpark(root: Node3D, pk: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = pk["seed"]
	var c: Vector2 = pk["pos"]
	var along := Vector2.from_angle(rng.randf() * PI)
	var rotors := []
	for k in pk["n"]:
		var p: Vector2 = c + along * (k - int(pk["n"]) / 2.0) * 280.0 + along.orthogonal() * rng.randf_range(-60, 60)
		var h := maxf(height_at(p, free_dist(p)), 0.0)
		var base := Vector3(p.x, h - 1.0, p.y)
		var tower := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.3
		cyl.bottom_radius = 2.6
		cyl.height = 100.0
		cyl.radial_segments = 10
		cyl.rings = 1
		tower.mesh = cyl
		tower.material_override = _tower_mat
		tower.position = base + Vector3(0, 50, 0)
		root.add_child(tower)
		var head := Node3D.new()
		head.position = base + Vector3(0, 100, 0)
		head.rotation.y = PI * 0.5  # Rotor zeigt nach Westen
		root.add_child(head)
		var nac := MeshInstance3D.new()
		var nb := BoxMesh.new()
		nb.size = Vector3(3.4, 3.6, 11.0)
		nac.mesh = nb
		nac.material_override = _tower_mat
		nac.position = Vector3(0, 0, 2.5)
		head.add_child(nac)
		var lamp := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(0.8, 0.6, 0.8)
		lamp.mesh = lb
		lamp.material_override = beacon_mat
		lamp.position = Vector3(0, 2.2, 4.0)
		head.add_child(lamp)
		var rotor := Node3D.new()
		rotor.position = Vector3(0, 0, -3.6)
		rotor.rotation.z = rng.randf() * TAU
		head.add_child(rotor)
		var hub := MeshInstance3D.new()
		var hs := SphereMesh.new()
		hs.radius = 1.6
		hs.height = 3.2
		hs.radial_segments = 8
		hs.rings = 4
		hub.mesh = hs
		hub.material_override = _blade_mat
		rotor.add_child(hub)
		for b in 3:
			var blade := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(2.2, 46.0, 0.5)
			blade.mesh = bm
			blade.material_override = _blade_mat
			var ba := b * TAU / 3.0
			blade.transform = Transform3D(Basis(Vector3.FORWARD, ba), Basis(Vector3.FORWARD, ba) * Vector3(0, 24.0, 0))
			rotor.add_child(blade)
		rotors.append(rotor)
	root.set_meta("rotors", rotors)


## Uferlinie: Radius je Richtung (0,8- bis 1,15-mal r), fest je See
func lake_r(lk: Dictionary, a: float) -> float:
	var ph: float = lk["pos"].x * 0.013 + lk["pos"].y * 0.007
	return lk["r"] * (0.97 + 0.12 * sin(a * 2.0 + ph) + 0.07 * sin(a * 5.0 + ph * 2.3) + 0.03 * sin(a * 11.0 + ph * 0.7))


## See: Wasserfläche (spiegelnd wie die Stadtteiche) mit unregelmäßigem Ufer, Schilf am Ufer
func _lake(root: Node3D, lk: Dictionary) -> void:
	var w := MeshInstance3D.new()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var n := 64
	for k in n:
		var a0 := k * TAU / n
		var a1 := (k + 1) * TAU / n
		var r0 := lake_r(lk, a0) + 4.0
		var r1 := lake_r(lk, a1) + 4.0
		st.set_uv(Vector2(0.5, 0.5))
		st.add_vertex(Vector3.ZERO)
		st.set_uv(Vector2(0.5 + cos(a0) * 0.5, 0.5 + sin(a0) * 0.5))
		st.add_vertex(Vector3(cos(a0) * r0, 0, sin(a0) * r0))
		st.set_uv(Vector2(0.5 + cos(a1) * 0.5, 0.5 + sin(a1) * 0.5))
		st.add_vertex(Vector3(cos(a1) * r1, 0, sin(a1) * r1))
	w.mesh = st.commit()
	w.material_override = _water_mat
	w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.position = Vector3(lk["pos"].x, lk["level"] - 0.25, lk["pos"].y)
	root.add_child(w)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(lk["pos"].x * 7.0 + lk["pos"].y)
	var reeds := []
	var cols := []
	for k in 140:
		var a := rng.randf() * TAU
		var rr: float = lake_r(lk, a) + rng.randf_range(-3.0, 7.0)
		var q: Vector2 = lk["pos"] + Vector2.from_angle(a) * rr
		var sc := rng.randf_range(0.6, 1.1)
		reeds.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc * 0.5, sc * 0.35, sc * 0.5)), Vector3(q.x, lk["level"] - 0.6, q.y)))
		cols.append(Color(0.35, 0.4, 0.15) * rng.randf_range(0.8, 1.2))
	var mm := _multimesh(_meshes["leafy"], reeds, cols)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## Hochspannungsleitung: Gittermasten (Stahl, vier Ausleger) mit durchhängenden Seilen; je Kachel die Masten,
## die darin stehen, samt Seilen zum nächsten Mast
func _power_lines(root: Node3D, o: Vector2) -> void:
	var g := {}
	for line in _lines:
		for k in line.size():
			var p: Vector2 = line[k]
			if not _in_chunk(p, o):
				continue
			var h := maxf(height_at(p, free_dist(p)), 0.0)
			var nxt: Vector2 = line[mini(k + 1, line.size() - 1)]
			var prv: Vector2 = line[maxi(k - 1, 0)]
			var along := (nxt - prv).normalized()
			var yaw := atan2(along.x, along.y)
			var b := Basis(Vector3.UP, yaw)
			var base := Vector3(p.x, h, p.y)
			# Mast: vier schräge Eckstiele, oben schmal, Querriegel, zwei Traversen
			for cx in [-1.0, 1.0]:
				for cz in [-1.0, 1.0]:
					var bot := base + b * Vector3(cx * 3.2, 0, cz * 3.2)
					var top := base + b * Vector3(cx * 0.9, 38.0, cz * 0.9)
					_beam(g, bot, top, 0.35)
			for lv in [12.0, 22.0, 30.0]:
				var wdt := lerpf(3.2, 0.9, lv / 38.0)
				for cz in [-1.0, 1.0]:
					_beam(g, base + b * Vector3(-wdt, lv, cz * wdt), base + b * Vector3(wdt, lv, cz * wdt), 0.2)
			for arm in [[26.0, 9.0], [33.0, 7.0]]:
				_beam(g, base + b * Vector3(-arm[1], arm[0], 0), base + b * Vector3(arm[1], arm[0], 0), 0.45)
			_beam(g, base + b * Vector3(0, 38.0, 0), base + b * Vector3(0, 42.0, 0), 0.3)
			# Seile zum nächsten Mast (drei je Seite), leicht durchhängend in vier Stücken
			if k + 1 < line.size():
				var p2: Vector2 = line[k + 1]
				var h2 := maxf(height_at(p2, free_dist(p2)), 0.0)
				var b2 := Basis(Vector3.UP, yaw)
				for arm in [[26.0, 9.0], [33.0, 7.0]]:
					for sx in [-1.0, 1.0]:
						var a3 := base + b * Vector3(sx * arm[1], arm[0] - 0.8, 0)
						var e3 := Vector3(p2.x, h2, p2.y) + b2 * Vector3(sx * arm[1], arm[0] - 0.8, 0)
						var prev := a3
						for s2 in range(1, 5):
							var t := s2 / 4.0
							var q := a3.lerp(e3, t) - Vector3(0, sin(t * PI) * 7.0, 0)
							_beam(g, prev, q, 0.06)
							prev = q
	if g.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in g["parts"]:
		st.append_from(_meshes["box"], 0, part)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _steel_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## Balken von a nach b (Kantenlänge th) als Teil für _power_lines
func _beam(g: Dictionary, a: Vector3, b: Vector3, th: float) -> void:
	if not g.has("parts"):
		g["parts"] = []
	var d := b - a
	var l := d.length()
	if l < 0.01:
		return
	var y := d / l
	var x := y.cross(Vector3.UP if absf(y.y) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	g["parts"].append(Transform3D(Basis(x * th, y * l, z * th), (a + b) / 2.0))


## Nebelbänke: weiche Schichten über Wiesen nahe der Straße (sonst sieht man sie nicht), nachts und morgens
func _fog_banks(root: Node3D, o: Vector2, dr: PackedFloat32Array, hs: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	for k in 3:
		var p := o + Vector2(rng.randf_range(100, CHUNK - 100), rng.randf_range(100, CHUNK - 100))
		var g := (p - o) / STEP
		var d := dr[clampi(int(g.y), 0, N) * (N + 1) + clampi(int(g.x), 0, N)]
		if d < 5.0 or d > 550.0 or rng.randf() < 0.35:
			continue
		var h := maxf(_grid_h(o, hs, p), 0.0)
		var size := rng.randf_range(260.0, 420.0)
		for layer in 3:
			var q := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(size, size) * (1.0 - layer * 0.15)
			q.mesh = pm
			q.material_override = fog_mat
			q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			q.position = Vector3(p.x, h + 0.8 + layer * 1.6, p.y)
			q.visibility_range_end = 1800.0
			root.add_child(q)
