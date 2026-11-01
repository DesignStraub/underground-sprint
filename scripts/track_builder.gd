extends RefCounted
## Erzeugt eine Sprintstrecke durch eine nächtliche Stadt aus einem Seed:
## Straße, befahrbarer Gehweg mit Bordstein, Hindernisse, Baustellen, Läden, Hochhäuser,
## Wahrzeichen (Kirche, Krankenhaus, Tankstelle), Laternen zum Umfahren, Start/Ziel.

const Builder := preload("res://scripts/car_builder.gd")
const Knockable := preload("res://scripts/knockable.gd")
const ROAD_SHADER := preload("res://shaders/road.gdshader")
const BUILDING_SHADER := preload("res://shaders/building.gdshader")

const HALF_W := 9.0  # 4 Spuren à 4,5 m
const LANES := [-6.75, -2.25, 2.25, 6.75]
const WALK := 5.0  # Gehwegbreite
const CURB_H := 0.2
const LAMP_STEP := 38.0
const SIGNS := ["MOTEL", "24H", "TUNING", "BAR", "HOTEL", "NOODLES", "CLUB", "GARAGE", "PARTS", "NEON"]
const SHOPS := ["PIZZA", "DÖNER", "KIOSK", "BÄCKEREI", "APOTHEKE", "FRISEUR", "TATTOO", "AUTOTEILE",
	"WÄSCHEREI", "SPÄTI", "SUSHI", "BURGER", "HANDY SHOP", "BLUMEN", "JUWELIER", "SPIELHALLE", "MUSIK",
	"SNEAKER", "NAILS", "WETTBÜRO", "CAFE", "BAR", "TUNING", "REIFEN", "VIDEOTHEK", "ASIA IMBISS",
	"BUCHLADEN", "GAMES", "FITNESS", "OPTIKER", "SHISHA", "PFANDHAUS"]
const NEON := [Color(1, 0.1, 0.6), Color(0.1, 0.8, 1), Color(0.7, 0.2, 1), Color(1, 0.5, 0.1), Color(0.2, 1, 0.4), Color(1, 0.9, 0.3)]


static func build(race: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = race["seed"]
	var root := Node3D.new()
	root.name = "Track"

	# --- Mittellinie
	var pts := [Vector3.ZERO]
	var heading := 0.0
	var p := Vector3.ZERO
	p += _dir(heading) * 160.0
	pts.append(p)
	for i in race["segments"]:
		heading = clampf(heading + deg_to_rad(rng.randf_range(-race["max_turn"], race["max_turn"])), -1.4, 1.4)
		p += _dir(heading) * rng.randf_range(70.0, 150.0)
		pts.append(p)
	p += _dir(heading) * 200.0
	pts.append(p)

	var curve := Curve3D.new()
	curve.bake_interval = 1.0
	for i in pts.size():
		var prev: Vector3 = pts[maxi(i - 1, 0)]
		var nxt: Vector3 = pts[mini(i + 1, pts.size() - 1)]
		var t: Vector3 = (nxt - prev) * 0.22
		curve.add_point(pts[i], -t, t)
	var length := curve.get_baked_length()
	var start_off := 25.0
	var finish_off := length - 80.0

	_build_road(root, curve, length)
	var blocks := _build_roadworks(root, curve, length, rng)
	var occupied := _build_landmarks(root, curve, length, rng)
	_build_city(root, curve, length, rng, occupied)
	_build_lamps(root, curve, length)
	_build_props(root, curve, length, rng)
	_gate(root, curve, start_off + 12.0, "START", Color(0.2, 1.0, 0.4))
	_gate(root, curve, finish_off, "ZIEL", Color(1.0, 0.2, 0.4))

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

	return {"node": root, "curve": curve, "length": length, "start": start_off, "finish": finish_off, "blocks": blocks}


static func _dir(h: float) -> Vector3:
	return Vector3(-sin(h), 0, -cos(h))


static func frame_at(curve: Curve3D, d: float) -> Dictionary:
	var len := curve.get_baked_length()
	var a := curve.sample_baked(clampf(d - 1.0, 0.0, len))
	var b := curve.sample_baked(clampf(d + 1.0, 0.0, len))
	var fwd := (b - a).normalized()
	if fwd == Vector3.ZERO:
		fwd = Vector3.FORWARD
	return {"pos": curve.sample_baked(clampf(d, 0.0, len)), "fwd": fwd, "right": Vector3(-fwd.z, 0, fwd.x)}


## Transform an Streckenposition d, seitlich versetzt um lateral, Blick in Fahrtrichtung.
static func xform_at(curve: Curve3D, d: float, lateral: float) -> Transform3D:
	var f := frame_at(curve, d)
	var pos: Vector3 = f["pos"] + f["right"] * lateral
	var basis := Basis.looking_at(f["fwd"], Vector3.UP)
	return Transform3D(basis, Vector3(pos.x, 0, pos.z))


## Knoten am Straßenrand: lokales -Z zeigt zur Straße. dist = Abstand der Mitte von der Straßenmitte.
static func _roadside(root: Node3D, curve: Curve3D, d: float, side: int, dist: float) -> Node3D:
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


static func _solid(parent: Node3D, size: Vector3, pos: Vector3) -> void:
	var sb := StaticBody3D.new()
	sb.position = pos
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	parent.add_child(sb)


# --- Straße ----------------------------------------------------------------

static func _build_road(root: Node3D, curve: Curve3D, length: float) -> void:
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
			"lo": c - r * outer, "ro": c + r * outer, "d": d,
		}
		if not prev.is_empty():
			_strip(road, prev["l"], prev["r"], cur["l"], cur["r"], prev["d"], d)
			var up := Vector3(0, CURB_H, 0)
			_strip(walk, prev["lo"] + up, prev["l"] + up, cur["lo"] + up, cur["l"] + up, 0.0, 0.0)
			_strip(walk, prev["r"] + up, prev["ro"] + up, cur["r"] + up, cur["ro"] + up, 0.0, 0.0)
			_strip_v(walk, prev["l"], cur["l"], CURB_H, true)
			_strip_v(walk, prev["r"], cur["r"], CURB_H, false)
			# Harte Grenze hinter dem Gehweg (Hauswände)
			for side in ["lw", "rw"]:
				var a: Vector3 = prev[side]
				var b: Vector3 = cur[side]
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = Vector3(0.6, 3.0, a.distance_to(b) + 0.6)
				cs.shape = bs
				cs.transform = Transform3D(Basis.looking_at((b - a).normalized(), Vector3.UP), (a + b) / 2 + Vector3(0, 1.5, 0))
				walls.add_child(cs)
		prev = cur
		d += step

	var rm := ShaderMaterial.new()
	rm.shader = ROAD_SHADER
	road.generate_normals()
	var road_mi := MeshInstance3D.new()
	road_mi.mesh = road.commit()
	road_mi.material_override = rm
	root.add_child(road_mi)
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


## Baustellen sperren eine Außenspur auf ~30 m. Liefert [{from, to, lane}] für KI und Verkehr.
static func _build_roadworks(root: Node3D, curve: Curve3D, length: float, rng: RandomNumberGenerator) -> Array:
	var blocks := []
	var stripe := Builder.mat(Color(0.9, 0.15, 0.1), 0.0, 0.6)
	var white := Builder.mat(Color(0.9, 0.9, 0.9), 0.0, 0.6)
	var warn := Builder.mat(Color(1, 0.7, 0.1), 0.0, 0.4, Color(1, 0.6, 0.0), 5.0)
	var count := 2 + int(length / 1200.0)
	for k in count:
		var d0 := length * (0.2 + 0.65 * (k + rng.randf() * 0.6) / count)
		var lane: float = LANES[0] if rng.randf() < 0.5 else LANES[3]
		var len := 30.0
		blocks.append({"from": d0 - 14.0, "to": d0 + len + 4.0, "lane": lane})
		var dd := 0.0
		while dd <= len:
			# Erste Barrieren schräg in die Spur, danach parallel zur Nachbarspur
			var taper := clampf(dd / 8.0, 0.0, 1.0)
			var lat := lane + signf(lane) * (1.8 - taper * 1.8) - signf(lane) * 2.0 * taper
			var x := xform_at(curve, d0 + dd, lat)
			var n := Node3D.new()
			n.transform = x
			root.add_child(n)
			Builder._add(n, Builder.box(Vector3(0.5, 0.9, 2.6)), stripe if int(dd / 3.0) % 2 == 0 else white, Vector3(0, 0.45, 0))
			Builder._add(n, Builder.box(Vector3(0.2, 0.2, 0.2)), warn, Vector3(0, 1.0, 0))
			_solid(n, Vector3(0.5, 1.6, 2.6), Vector3(0, 0.8, 0))
			dd += 3.0
		# Warnschild vor der Baustelle
		var sx := xform_at(curve, d0 - 10.0, lane)
		var sign_n := Node3D.new()
		sign_n.transform = sx
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
	return blocks


# --- Wahrzeichen -------------------------------------------------------------

## Baut Kirche, Krankenhaus, Tankstelle. Liefert belegte Flächen [{pos, r}] für die übrige Bebauung.
static func _build_landmarks(root: Node3D, curve: Curve3D, length: float, rng: RandomNumberGenerator) -> Array:
	var occupied := []
	var side := 1 if rng.randf() < 0.5 else -1
	var plan := [[0.22, "church", 30.0], [0.42, "gas", 22.0], [0.58, "hospital", 26.0], [0.8, "church", 30.0]]
	if length < 1800.0:
		plan.resize(3)
	for entry in plan:
		var d: float = length * entry[0]
		var depth: float = entry[2]
		var n := _roadside(root, curve, d, side, HALF_W + WALK + 1.5 + depth / 2.0)
		match entry[1]:
			"church":
				_church(n)
			"gas":
				_gas_station(n)
			"hospital":
				_hospital(n)
		occupied.append({"pos": n.position, "r": depth + 6.0})
		side = -side
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
	# Uhr
	var clock := CylinderMesh.new()
	clock.top_radius = 1.4
	clock.bottom_radius = 1.4
	clock.height = 0.2
	clock.radial_segments = 16
	Builder._add(n, clock, Builder.mat(Color(1, 0.95, 0.8), 0, 0.5, Color(1, 0.9, 0.7), 2.5), Vector3(0, 19, -14.05)).rotation_degrees.x = 90
	# Portal und bunte Kirchenfenster
	Builder._add(n, Builder.box(Vector3(2.6, 4.5, 0.3)), Builder.mat(Color(0.3, 0.2, 0.1), 0, 0.5, Color(1, 0.6, 0.25), 1.5), Vector3(0, 2.25, -14.05))
	var glass_cols := [Color(0.2, 0.4, 1), Color(1, 0.2, 0.2), Color(1, 0.8, 0.2), Color(0.3, 1, 0.5)]
	for s in [-1, 1]:
		for i in 5:
			var gc: Color = glass_cols[(i + (1 if s > 0 else 0)) % glass_cols.size()]
			Builder._add(n, Builder.box(Vector3(0.2, 5.0, 1.6)), Builder.mat(gc, 0, 0.3, gc, 2.0), Vector3(s * 6.05, 6.5, -4.0 + i * 4.5))
	# Angestrahlt von unten
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
	b.set_instance_shader_parameter("tint", Vector3(0.5, 0.52, 0.55))
	b.set_instance_shader_parameter("shop_glass", 0.0)
	n.add_child(b)
	var red := Builder.mat(Color(1, 0.05, 0.05), 0, 0.4, Color(1, 0.05, 0.05), 5.0)
	var white := Builder.mat(Color(0.9, 0.9, 0.92), 0.1, 0.5)
	# Rotes Kreuz auf dem Dach
	Builder._add(n, Builder.box(Vector3(6, 6, 0.6)), white, Vector3(0, 27.5, -2.6))
	Builder._add(n, Builder.box(Vector3(1.4, 5, 0.3)), red, Vector3(0, 27.5, -2.95))
	Builder._add(n, Builder.box(Vector3(5, 1.4, 0.3)), red, Vector3(0, 27.5, -2.95))
	_label(n, "KRANKENHAUS", Color(0.7, 0.9, 1.0), 160, Vector3(0, 21, -3.1), 2.0)
	# Notaufnahme mit Vordach
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
	# Krankenwagen mit Blaulicht
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
	# Shop dahinter
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
	# Preisschild-Mast an der Straße
	Builder._add(n, Builder.box(Vector3(0.5, 9, 0.5)), white, Vector3(11, 4.5, -10))
	Builder._add(n, Builder.box(Vector3(3.4, 3.4, 0.4)), Builder.mat(Color(0.05, 0.05, 0.08), 0, 0.5), Vector3(11, 9.5, -10))
	_label(n, "TANKE\nSUPER  1,89\nDIESEL 1,79", Color(1, 0.8, 0.2), 40, Vector3(11, 9.5, -10.25))


# --- Bebauung --------------------------------------------------------------

static func _build_city(root: Node3D, curve: Curve3D, length: float, rng: RandomNumberGenerator, occupied: Array) -> void:
	var bmat := ShaderMaterial.new()
	bmat.shader = BUILDING_SHADER
	var unit_box := BoxMesh.new()
	var awning_cols := [Color(0.6, 0.05, 0.05), Color(0.05, 0.35, 0.15), Color(0.1, 0.15, 0.5), Color(0.5, 0.3, 0.05), Color(0.35, 0.05, 0.4)]

	for side in [-1, 1]:
		var d := rng.randf_range(0.0, 10.0)
		while d < length:
			var shop := rng.randf() < 0.6
			var w := rng.randf_range(8.0, 15.0) if shop else rng.randf_range(12.0, 24.0)
			var depth := rng.randf_range(10.0, 16.0) if shop else rng.randf_range(12.0, 22.0)
			var h := rng.randf_range(5.0, 9.0) if shop else (rng.randf_range(14.0, 32.0) if rng.randf() < 0.6 else rng.randf_range(32.0, 80.0))
			var f := frame_at(curve, d)
			var gap := rng.randf_range(0.5, 2.5)
			var center: Vector3 = f["pos"] + f["right"] * side * (HALF_W + WALK + gap + depth / 2)
			var nearest := curve.get_closest_point(center)
			var radius := Vector2(w, depth).length() / 2
			var ok := Vector2(center.x - nearest.x, center.z - nearest.z).length() > HALF_W + WALK + radius * 0.75
			for o in occupied:
				if Vector2(center.x - o["pos"].x, center.z - o["pos"].z).length() < o["r"] + radius * 0.8:
					ok = false
			if ok:
				var b := MeshInstance3D.new()
				b.mesh = unit_box
				b.material_override = bmat
				b.transform = Transform3D(Basis.looking_at(f["fwd"], Vector3.UP) * Basis.from_scale(Vector3(depth, h, w)), center + Vector3(0, h / 2, 0))
				b.set_instance_shader_parameter("seed", rng.randf() * 100.0)
				var g := rng.randf_range(0.05, 0.13) if not shop else rng.randf_range(0.08, 0.2)
				b.set_instance_shader_parameter("tint", Vector3(g, g * rng.randf_range(0.9, 1.05), g * 1.1))
				root.add_child(b)
				var face_pos: Vector3 = center - f["right"] * side * (depth / 2 + 0.15)
				var face_basis := Basis.looking_at(f["right"] * side, Vector3.UP)  # +Z zeigt zur Straße
				if shop:
					# Markise + Ladenschild
					var aw := MeshInstance3D.new()
					aw.mesh = Builder.box(Vector3(w * 0.85, 0.15, 1.6))
					var ac: Color = awning_cols[rng.randi() % awning_cols.size()]
					aw.material_override = Builder.mat(ac, 0.1, 0.6)
					aw.transform = Transform3D(face_basis, face_pos + Vector3(0, 3.6, 0) - f["right"] * side * 0.8)
					root.add_child(aw)
				if shop or rng.randf() < 0.35:
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
			d += w + rng.randf_range(0.5, 4.0)


## Laternen: fliegen weg, wenn man sie trifft (und gehen aus).
static func _build_lamps(root: Node3D, curve: Curve3D, length: float) -> void:
	var pole_m := Builder.mat(Color(0.2, 0.2, 0.22), 0.6, 0.4)
	var lamp_m := Builder.mat(Color(1, 0.8, 0.5), 0.0, 0.3, Color(1.0, 0.7, 0.35), 5.0)
	var d := 20.0
	var side := 1
	while d < length:
		var f := frame_at(curve, d)
		var base: Vector3 = f["pos"] + f["right"] * side * (HALF_W + 0.8)
		var lamp := Knockable.new()
		lamp.mass = 60.0
		lamp.slowdown = 0.9
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
		light.light_color = Color(1.0, 0.68, 0.35)
		light.light_energy = 2.2
		light.omni_range = 20.0
		light.omni_attenuation = 1.2
		light.position = Vector3(0, 7.3, -2.2)
		lamp.add_child(light)
		root.add_child(lamp)
		d += LAMP_STEP
		side = -side


## Gehweg-Möblierung: leichte Sachen fliegen weg, schwere (Hydrant, Poller, Kübel, Haltestelle) sind hart.
static func _build_props(root: Node3D, curve: Curve3D, length: float, rng: RandomNumberGenerator) -> void:
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

	for side in [-1, 1]:
		var d := rng.randf_range(5.0, 12.0)
		while d < length - 10.0:
			var lamp_phase := fmod(d - 20.0 + LAMP_STEP * 2.0, LAMP_STEP)
			if lamp_phase < 3.0 or lamp_phase > LAMP_STEP - 3.0:
				d += 4.0
				continue
			var kind := rng.randi() % 10
			var dist := HALF_W + rng.randf_range(1.0, WALK - 0.9)
			var f := frame_at(curve, d)
			var pos: Vector3 = f["pos"] + f["right"] * side * dist
			var basis := Basis.looking_at(-f["right"] * side, Vector3.UP)
			var xf := Transform3D(basis, Vector3(pos.x, CURB_H, pos.z))
			if kind <= 5:
				var k := Knockable.new()
				k.transform = xf
				var sz := Vector3.ONE
				match kind:
					0, 1:  # Mülltonne
						var c := CylinderMesh.new()
						c.top_radius = 0.35
						c.bottom_radius = 0.3
						c.height = 1.0
						c.radial_segments = 10
						Builder._add(k, c, green, Vector3(0, 0.5, 0))
						sz = Vector3(0.7, 1.0, 0.7)
						k.mass = 15.0
					2:  # Pylone
						var c := CylinderMesh.new()
						c.top_radius = 0.04
						c.bottom_radius = 0.25
						c.height = 0.7
						c.radial_segments = 8
						Builder._add(k, c, orange, Vector3(0, 0.35, 0))
						sz = Vector3(0.5, 0.7, 0.5)
						k.mass = 3.0
						k.slowdown = 0.99
					3:  # Zeitungsbox
						Builder._add(k, Builder.box(Vector3(0.5, 1.1, 0.5)), blue, Vector3(0, 0.55, 0))
						sz = Vector3(0.5, 1.1, 0.5)
						k.mass = 20.0
					4:  # Briefkasten
						Builder._add(k, Builder.box(Vector3(0.5, 0.6, 0.35)), yellow, Vector3(0, 1.0, 0))
						Builder._add(k, Builder.box(Vector3(0.08, 0.7, 0.08)), dark, Vector3(0, 0.35, 0))
						sz = Vector3(0.5, 1.3, 0.4)
						k.mass = 25.0
					5:  # Bank
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
					6:  # Hydrant
						var c := CylinderMesh.new()
						c.top_radius = 0.16
						c.bottom_radius = 0.2
						c.height = 0.8
						c.radial_segments = 8
						Builder._add(s, c, red, Vector3(0, 0.4, 0))
						_solid(s, Vector3(0.45, 1.0, 0.45), Vector3(0, 0.5, 0))
					7:  # Poller-Reihe
						for i in 3:
							var c := CylinderMesh.new()
							c.top_radius = 0.12
							c.bottom_radius = 0.12
							c.height = 0.9
							c.radial_segments = 8
							Builder._add(s, c, dark, Vector3(-1.5 + i * 1.5, 0.45, 0))
							_solid(s, Vector3(0.3, 1.0, 0.3), Vector3(-1.5 + i * 1.5, 0.5, 0))
					8:  # Pflanzkübel
						Builder._add(s, Builder.box(Vector3(1.4, 0.6, 1.4)), concrete, Vector3(0, 0.3, 0))
						var sm := SphereMesh.new()
						sm.radius = 0.75
						sm.height = 1.2
						sm.radial_segments = 8
						sm.rings = 4
						Builder._add(s, sm, bush, Vector3(0, 1.0, 0))
						_solid(s, Vector3(1.4, 1.2, 1.4), Vector3(0, 0.6, 0))
					9:  # Bushaltestelle (weit hinten am Gehweg)
						s.transform.origin = Vector3(pos.x, CURB_H, pos.z) + f["right"] * side * (HALF_W + WALK - 1.1 - dist)
						Builder._add(s, Builder.box(Vector3(3.6, 0.12, 1.5)), dark, Vector3(0, 2.5, 0))
						Builder._add(s, Builder.box(Vector3(3.6, 2.4, 0.06)), glass, Vector3(0, 1.25, 0.7))
						Builder._add(s, Builder.box(Vector3(0.06, 2.4, 1.4)), ad, Vector3(1.75, 1.25, 0))
						Builder._add(s, Builder.box(Vector3(2.4, 0.08, 0.4)), wood, Vector3(-0.3, 0.45, 0.45))
						_solid(s, Vector3(3.6, 2.5, 1.5), Vector3(0, 1.25, 0))
			d += rng.randf_range(7.0, 15.0)


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
	# Label3D ist von +Z aus lesbar; der Fahrer kommt von hinten
	lbl.transform = Transform3D(Basis.looking_at(f["fwd"], Vector3.UP), f["pos"] + Vector3(0, 7.25, 0) - f["fwd"] * 0.35)
	root.add_child(lbl)
	# Schachbrett-Linie auf der Straße
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
