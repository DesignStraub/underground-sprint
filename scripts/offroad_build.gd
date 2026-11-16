extends Node3D
## Gelände bauen und nachladen (seit 2.39, Planung und Abfragen in offroad.gd): Boden als eigenes Gitter (2,5 m,
## shaders/offroad.gdshader, in Kacheln), Teiche, Bäume mit festem Stamm, Findlinge, Gebäude und Maschinen, Rampen
## (Rückseite und Seiten als Wand: man fährt nicht von der Seite auf die Kante hinauf), Zaun mit unsichtbarer Wand
## (12 m wie an den Straßen), Tor mit Schild, ein paar Laternen. Je Fläche ein Knoten. Gebaut wird im Hintergrund-Thread
## (im Browser Schritt für Schritt), sobald man in Sichtweite kommt, und entfernt, wenn man weit weg ist.

const Offroad := preload("res://scripts/offroad.gd")
const Track := preload("res://scripts/track_builder.gd")
const Builder := preload("res://scripts/car_builder.gd")
const Knockable := preload("res://scripts/knockable.gd")
const SHADER := preload("res://shaders/offroad.gdshader")

const STEP := 2.5  # Gitterweite des Bodens (m)
const TILE := 32  # Zellen je Kachel und Richtung (eigene Meshes; kleine Bauschritte, im Browser ohne langes Stocken)
const BUDGET_MS := 6  # Browser: so lange je Bild bauen

var land  # Landscape: Bäume, Häuser und Wasser teilen ihre Meshes und Stoffe
var target: Node3D
var view := 1600.0
var hold := Callable()  # true = gerade nicht bauen (die Welt baut eine Strecke)
var last_event := ""
var _nodes := {}  # Index der Fläche -> Node3D (null: im Bau)
var _task := -1
var _task_i := -1
var _task_out: Node3D
var _job := {}
var _t := 0.0
var _day := 1.0
static var _mats := {}


func setup(land_, view_dist: float) -> void:
	land = land_
	view = view_dist + 500.0
	_make_mats()
	# Mähstreifen der Fairways längs der Fläche (zur Straße hin parallel)
	for a in Offroad.areas:
		if a["kind"] == "golf":
			(_mats["boden_golf"] as ShaderMaterial).set_shader_parameter("stripe_dir", a["u"])


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		if _task_out and not _task_out.is_inside_tree():
			_task_out.free()
	# im Browser halb gebaut (Schritt für Schritt): der Baum hängt noch nicht in der Welt und würde sonst nie frei
	if not _job.is_empty():
		var jr = _job["root"]  # ungetypt: ein schon freigegebener Knoten darf hier nicht zugewiesen werden
		if is_instance_valid(jr) and not (jr as Node).is_inside_tree():
			(jr as Node).free()
		_job = {}


## Alles in Sichtweite sofort bauen (hinter dem Ladebild)
func build_near(p: Vector3) -> void:
	for i in Offroad.areas.size():
		if _dist(i, p) < view and not _nodes.has(i):
			_add_node(i, build_area(i))


func _add_node(i: int, n: Node3D) -> void:
	_nodes[i] = n
	var t0 := Time.get_ticks_usec()
	Track.apply_lod(n, GameState.lod_ranges())
	add_child(n)
	_apply_day(n)
	if OS.get_cmdline_user_args().has("--worldlog"):
		print("GELAENDE %s eingehängt in %.1f ms" % [n.get_meta("area"), (Time.get_ticks_usec() - t0) / 1000.0])


func _dist(i: int, p: Vector3) -> float:
	var a: Dictionary = Offroad.areas[i]
	var m: Vector2 = a["mid"]
	return maxf(Vector2(p.x, p.z).distance_to(m) - maxf(float(a["w"]), float(a["d"])) * 0.6, 0.0)


func _process(_dt: float) -> void:
	last_event = ""
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		var t0 := Time.get_ticks_usec()
		_add_node(_task_i, _task_out)
		last_event = "gelaende+%.1fms" % ((Time.get_ticks_usec() - t0) / 1000.0)
		_task_out = null
	if not _job.is_empty():
		var t1 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t1 < BUDGET_MS:
			if _step(_job):
				_add_node(_job["i"], _job["root"])
				_job = {}
				break
		return
	_t -= _dt
	if _t > 0.0 or target == null or not is_instance_valid(target):
		return
	_t = 0.5
	var p := target.global_position
	for i in _nodes.keys():
		if _nodes[i] != null and _dist(i, p) > view + 900.0:
			(_nodes[i] as Node).queue_free()
			_nodes.erase(i)
	if _task >= 0 or (hold.is_valid() and hold.call()):
		return
	for i in Offroad.areas.size():
		if _nodes.has(i) or _dist(i, p) > view:
			continue
		_nodes[i] = null
		if OS.has_feature("web") or DisplayServer.get_name() == "headless":
			_job = _begin(i)  # Browser (ohne Threads) und headless (Ersatz-Renderer nicht threadsicher): Schritt für Schritt
		else:
			_task_i = i
			_task = WorkerThreadPool.add_task(func(): _task_out = build_area(i), false, "Gelände bauen")
		return


## Ganze Fläche i auf einmal bauen (Thread oder Ladebild)
func build_area(i: int) -> Node3D:
	var t0 := Time.get_ticks_usec()
	var job := _begin(i)
	var worst := 0
	var worst_k := 0
	while true:
		var t1 := Time.get_ticks_usec()
		var k: int = job["k"]
		var done := _step(job)
		if Time.get_ticks_usec() - t1 > worst:
			worst = Time.get_ticks_usec() - t1
			worst_k = k
		if done:
			break
	if OS.get_cmdline_user_args().has("--worldlog"):
		print("GELAENDE %s gebaut in %d ms (%d Schritte, längster %d ms: Schritt %d von %d Kacheln)" % [Offroad.areas[i]["name"],
			(Time.get_ticks_usec() - t0) / 1000, job["k"] + 1, worst / 1000, worst_k, (job["tiles"] as Array).size()])
	return job["root"]


func set_daylight(day: float) -> void:
	_day = day
	for k in _mats:
		if _mats[k] is ShaderMaterial and (_mats[k] as ShaderMaterial).shader == SHADER:
			(_mats[k] as ShaderMaterial).set_shader_parameter("day", day)
	for n in _nodes.values():
		if n != null:
			_apply_day(n)


func _apply_day(n: Node) -> void:
	for l in n.get_meta("lamps", []):
		if is_instance_valid(l):
			(l as OmniLight3D).light_energy = 1.7 * (1.0 - smoothstep(0.25, 0.6, _day))
			(l as OmniLight3D).visible = _day < 0.6


# --- Bauschritte ------------------------------------------------------------------------------------------------------

func _begin(i: int) -> Dictionary:
	var a: Dictionary = Offroad.areas[i]
	var root := Node3D.new()
	root.name = "Gelaende_%d" % i
	root.set_meta("area", a["name"])
	var walls := StaticBody3D.new()
	walls.name = "WallsGelaende"
	root.add_child(walls)
	var m := Offroad.SKIRT + 2.0 * STEP
	var s0 := -float(a["w"]) / 2.0 - m
	var t0 := -m
	var ns := int(ceil((float(a["w"]) + 2.0 * m) / STEP))
	var nt := int(ceil((float(a["d"]) + 2.0 * m) / STEP))
	var tiles := []
	for tj in range(0, nt, TILE):
		for ti in range(0, ns, TILE):
			tiles.append(Vector4i(ti, tj, mini(TILE, ns - ti), mini(TILE, nt - tj)))
	return {"a": a, "root": root, "walls": walls, "i": i, "k": 0, "tiles": tiles, "s0": s0, "t0": t0}


func _step(job: Dictionary) -> bool:
	var k: int = job["k"]
	var tiles: Array = job["tiles"]
	var a: Dictionary = job["a"]
	var root: Node3D = job["root"]
	if k < tiles.size():
		_terrain_tile(root, a, tiles[k], job["s0"], job["t0"])
	else:
		# danach kleine Schritte (je unter 8 ms am Rechner; im Browser einer je Bild, wenn er das Budget übersteigt)
		match k - tiles.size():
			0:
				_water(root, a)
			1:
				_trees(root, a)
			2:
				_rocks(root, a)
			3:
				# Rampen je einzeln
				var rl: Array = a["ramps"]
				var ri: int = job.get("ri", 0)
				if ri < rl.size():
					_ramp(root, a, rl[ri])
				job["ri"] = ri + 1
				if ri + 1 < rl.size():
					return false
			4:
				_fence(root, a, job["walls"])
			5:
				# Gebäude und Maschinen je einzeln
				var bl: Array = a["builds"]
				var bi: int = job.get("bi", 0)
				if bi < bl.size():
					_build(root, a, bl[bi])
				job["bi"] = bi + 1
				if bi + 1 < bl.size():
					return false
			6:
				_knocks(root, a)
			7:
				_gate(root, a)
			8:
				_lamps(root, a)
			9:
				Track._finalize_walls(root)
				return true
	job["k"] = k + 1
	return false


## Boden einer Kachel: Höhe, Normale (aus den Nachbarn), Untergrund-Gewichte (rgba), Übergang nach außen (UV.x).
## Dreiecke nur, wo eine Ecke innerhalb des Randstreifens liegt.
func _terrain_tile(root: Node3D, a: Dictionary, tile: Vector4i, s0: float, t0: float) -> void:
	var n0 := tile.z + 3
	var m0 := tile.w + 3
	var hs := PackedFloat32Array()
	hs.resize(n0 * m0)
	var sds := PackedFloat32Array()
	sds.resize(n0 * m0)
	for j in m0:
		for i in n0:
			var l := Vector2(s0 + (tile.x + i - 1) * STEP, t0 + (tile.y + j - 1) * STEP)
			var sd := Offroad.area_sd(a, l)
			sds[j * n0 + i] = sd
			hs[j * n0 + i] = Offroad.base_h(a, l) if sd < Offroad.SKIRT + 2.0 * STEP else -0.05
	var u: Vector2 = a["u"]
	var v: Vector2 = a["v"]
	var flip := u.x * v.y - u.y * v.x < 0.0
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var vid := PackedInt32Array()
	var W := tile.z + 1
	vid.resize(W * (tile.w + 1))
	vid.fill(-1)
	for j in tile.w + 1:
		for i in W:
			var gi := (j + 1) * n0 + (i + 1)
			if sds[gi] > Offroad.SKIRT + STEP * 1.5:
				continue
			var l := Vector2(s0 + (tile.x + i) * STEP, t0 + (tile.y + j) * STEP)
			var h := hs[gi]
			var gs := (hs[gi + 1] - hs[gi - 1]) / (2.0 * STEP)
			var gt := (hs[gi + n0] - hs[gi - n0]) / (2.0 * STEP)
			var gw := u * gs + v * gt
			var wp := Offroad.world(a, l)
			vid[j * W + i] = verts.size()
			verts.append(Vector3(wp.x, h, wp.y))
			norms.append(Vector3(-gw.x, 1.0, -gw.y).normalized())
			var c := Color(0, 0, 0, 0)
			if sds[gi] < 4.0:
				c = Color(_wt(a, l, 1), _wt(a, l, 2), _wt(a, l, 3), _wt(a, l, 4))
			cols.append(c)
			uvs.append(Vector2(smoothstep(0.0, Offroad.SKIRT, sds[gi]), 0.0))
	for j in tile.w:
		for i in tile.z:
			var ia := vid[j * W + i]
			var ib := vid[j * W + i + 1]
			var ic := vid[(j + 1) * W + i]
			var id := vid[(j + 1) * W + i + 1]
			if ia < 0 or ib < 0 or ic < 0 or id < 0:
				continue
			# Godot-Vorderseite: von oben gesehen im Uhrzeigersinn (wie Track.ground_cell); gespiegelte Flächen andersherum
			if flip:
				idx.append_array([ia, id, ib, ia, ic, id])
			else:
				idx.append_array([ia, ib, id, ia, id, ic])
	if idx.is_empty():
		return
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mi := MeshInstance3D.new()
	mi.name = "Boden"
	mi.mesh = mesh
	mi.material_override = _mats["boden_" + str(a["kind"])]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("lod_class", 2)
	root.add_child(mi)


## Gewicht eines Untergrund-Kanals (0,5 an der Grenze, 3 m Übergang)
func _wt(a: Dictionary, l: Vector2, ch: int) -> float:
	return clampf(0.5 - Offroad.shape_sd(a, l, ch) / 3.0, 0.0, 1.0)


## Teiche: Wasserfläche auf dem Spiegel (reicht unter das Ufer), Schilf am Rand
func _water(root: Node3D, a: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(a["seed"]) + 7
	for pd in a["ponds"]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_normal(Vector3.UP)
		var c: Vector2 = pd["c"]
		var rr: Vector2 = pd["r"]
		var ang: float = pd["a"]
		var lv: float = pd["level"]
		var n := 48
		var ring := []
		for k in n:
			var t := TAU * k / n
			var dir := Vector2(cos(t) * rr.x, sin(t) * rr.y).rotated(ang).normalized()
			# Uferlinie suchen (Boden auf Wasserhöhe), dann etwas weiter unter das Ufer; grob ab der halben Ellipse, dann fein
			var r := Vector2(cos(t) * rr.x, sin(t) * rr.y).length() * 0.6
			while r < maxf(rr.x, rr.y) * 1.6 and Offroad.base_h(a, c + dir * r) < lv:
				r += 2.0
			r = maxf(r - 2.0, 0.0)
			while r < maxf(rr.x, rr.y) * 1.6 and Offroad.base_h(a, c + dir * r) < lv:
				r += 0.5
			ring.append(c + dir * (r + 3.0))
		var cw := Offroad.world(a, c)
		var u: Vector2 = a["u"]
		var v: Vector2 = a["v"]
		var flip := u.x * v.y - u.y * v.x < 0.0
		for k in n:
			var p0 := Offroad.world(a, ring[k])
			var p1 := Offroad.world(a, ring[(k + 1) % n])
			var tri := [Vector3(cw.x, lv, cw.y), Vector3(p0.x, lv, p0.y), Vector3(p1.x, lv, p1.y)]
			if (tri[1] - tri[0]).cross(tri[2] - tri[0]).y > 0.0:
				tri = [tri[0], tri[2], tri[1]]
			for q in tri:
				st.set_uv(Vector2((q.x - cw.x) / 60.0 + 0.5, (q.z - cw.y) / 60.0 + 0.5))
				st.add_vertex(q)
		var mi := MeshInstance3D.new()
		mi.name = "Teich"
		mi.mesh = st.commit()
		mi.material_override = land._water_mat if land else _mats["wasser"]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta("lod_class", 2)
		root.add_child(mi)
		# Schilf
		if land:
			var reeds := []
			var rc := []
			for k in 36:
				var t := rng.randf() * TAU
				var dir := Vector2(cos(t) * rr.x, sin(t) * rr.y).rotated(ang)
				var q := c + dir * rng.randf_range(0.92, 1.08)
				var wq := Offroad.world(a, q)
				var sc := rng.randf_range(0.4, 0.75)
				reeds.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc * 0.5, sc * 0.35, sc * 0.5)),
					Vector3(wq.x, lv - 0.7, wq.y)))
				rc.append(Color(0.35, 0.4, 0.15) * rng.randf_range(0.8, 1.2))
			var mm := MultiMeshInstance3D.new()
			mm.multimesh = land._multimesh(land._meshes["leafy"], reeds, rc)
			mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mm)


## Bäume (Meshes der Landschaft) mit festem Stamm: frontal steht man, streifend gleitet man ab (player_car: rund)
func _trees(root: Node3D, a: Dictionary) -> void:
	if land == null:
		return
	var lists := {0: [], 1: []}
	var cols := {0: [], 1: []}
	var body := StaticBody3D.new()
	body.name = "Staemme"
	body.collision_mask = 0
	root.add_child(body)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(a["seed"]) + 11
	for tr in a["tree_list"]:
		var l: Vector2 = tr[0]
		var s: float = tr[1]
		var kind: int = tr[2]
		var wp := Offroad.world(a, l)
		var y := Offroad.base_h(a, l)
		var b := Basis(Vector3.UP, float(tr[3])).scaled(Vector3(s, s * rng.randf_range(0.9, 1.15), s))
		(lists[kind] as Array).append(Transform3D(b, Vector3(wp.x, y - 0.2, wp.y)))
		var c := Color(0.09, 0.2, 0.08) if kind == 0 else Color(0.17, 0.31, 0.09)
		(cols[kind] as Array).append(c * rng.randf_range(0.8, 1.15))
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = 0.32 * s
		cy.height = 3.0
		cs.shape = cy
		cs.position = Vector3(wp.x, y + 1.3, wp.y)
		body.add_child(cs)
	for kind in [0, 1]:
		if (lists[kind] as Array).is_empty():
			continue
		var mi := MultiMeshInstance3D.new()
		mi.name = "Baeume"
		mi.multimesh = land._multimesh(land._meshes["conifer" if kind == 0 else "leafy"], lists[kind], cols[kind])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.set_meta("lod_class", 2)
		root.add_child(mi)


## Wie Track._bake (Teile je Material zu einem Mesh), aber ohne die Daten vom RenderingServer zurückzuholen: append_from
## wartet dafür auf die Grafikkarte (gut 10 ms für die Bohlen einer Holzrampe oder die Findlinge, im Browser mehr). Teile
## sind fertige Daten (_box_arrays, _rock_arrays) oder ein Mesh (dessen Daten dann einmal geholt werden).
static func _bake_same(parent: Node3D, groups: Dictionary) -> void:
	var cache := {}
	for m in groups:
		var vs := PackedVector3Array()
		var ns := PackedVector3Array()
		var uvs := PackedVector2Array()
		for p in groups[m]:
			var arr: Array
			if p[0] is Array:
				arr = p[0]
			else:
				if not cache.has(p[0]):
					cache[p[0]] = (p[0] as Mesh).surface_get_arrays(0)
				arr = cache[p[0]]
			var xf: Transform3D = p[1]
			var nb := xf.basis.inverse().transposed()
			var v0: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var n0: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var u0: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array(range(v0.size()))
			for i in idx:
				vs.append(xf * v0[i])
				ns.append((nb * n0[i]).normalized())
				uvs.append(u0[i])
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = vs
		out[Mesh.ARRAY_NORMAL] = ns
		out[Mesh.ARRAY_TEX_UV] = uvs
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
		var mi := MeshInstance3D.new()
		mi.mesh = am
		mi.material_override = m
		parent.add_child(mi)


static func _piece(groups: Dictionary, m: Material, arr: Array, xf: Transform3D) -> void:
	if not groups.has(m):
		groups[m] = []
	groups[m].append([arr, xf])


## Quader (wie BoxMesh) als fertige Daten: je Fläche zwei Dreiecke, im Uhrzeigersinn von außen gesehen
static func _box_arrays(size: Vector3) -> Array:
	var hs := size / 2.0
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var uvs := PackedVector2Array()
	# Normale, dann zwei Achsen a, b der Fläche mit a x b = Normale
	for f in [[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.BACK, Vector3.UP], [Vector3.UP, Vector3.BACK, Vector3.RIGHT],
			[Vector3.DOWN, Vector3.RIGHT, Vector3.BACK], [Vector3.BACK, Vector3.RIGHT, Vector3.UP], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT]]:
		var n: Vector3 = f[0]
		var c: Vector3 = n * hs
		var ea: Vector3 = (f[1] as Vector3) * hs
		var eb: Vector3 = (f[2] as Vector3) * hs
		for q in [Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
			vs.append(c + ea * q.x + eb * q.y)
			ns.append(n)
			uvs.append(Vector2(q.x * 0.5 + 0.5, 0.5 - q.y * 0.5))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_TEX_UV] = uvs
	return arr


## Stein: flaches Ellipsoid (wie SphereMesh mit Radius 1, Höhe 1,5, 7 Segmenten, 4 Ringen) als fertige Daten
static func _rock_arrays() -> Array:
	var rows := 5
	var segs := 7
	var pts := []
	for j in rows + 1:
		var th := PI * j / rows
		var row := []
		for i in segs:
			var ph := TAU * i / segs
			row.append(Vector3(sin(th) * cos(ph), cos(th) * 0.75, sin(th) * sin(ph)))
		pts.append(row)
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var uvs := PackedVector2Array()
	for j in rows:
		for i in segs:
			var i2 := (i + 1) % segs
			for tri in [[pts[j][i], pts[j][i2], pts[j + 1][i2]], [pts[j][i], pts[j + 1][i2], pts[j + 1][i]]]:
				var p0: Vector3 = tri[0]
				var p1: Vector3 = tri[1]
				var p2: Vector3 = tri[2]
				var fn := (p1 - p0).cross(p2 - p0)
				if fn.length_squared() < 1e-8:
					continue  # an den Polen
				if fn.dot(p0 + p1 + p2) > 0.0:
					var t := p1
					p1 = p2
					p2 = t
				for q in [p0, p1, p2]:
					vs.append(q)
					ns.append(Vector3(q.x, q.y / 0.5625, q.z).normalized())
					uvs.append(Vector2(0.5 + q.x * 0.5, 0.5 - q.y * 0.5))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_TEX_UV] = uvs
	return arr


## Findlinge: unregelmäßige Steine, fest (große wie eine Wand, kleine wie ein Pfosten)
func _rocks(root: Node3D, a: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(a["seed"]) + 13
	var g := {}
	var sph := _rock_arrays()
	for r in a["rocks"]:
		var l: Vector2 = r[0]
		var rad: float = r[1]
		var wp := Offroad.world(a, l)
		var y := Offroad.base_h(a, l)
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, rng.randf_range(-0.25, 0.25))
		b = b.scaled(Vector3(rad * rng.randf_range(1.0, 1.3), rad * rng.randf_range(0.75, 0.95), rad))
		_piece(g, _mats["fels"], sph, Transform3D(b, Vector3(wp.x, y + rad * 0.25, wp.y)))
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = rad * 0.95
		cy.height = rad * 2.0
		cs.shape = cy
		sb.add_child(cs)
		sb.position = Vector3(wp.x, y + rad * 0.6, wp.y)
		root.add_child(sb)
	_bake_same(root, g)


## Rampen: Keil (Stahl mit Riffelblech und Warnstreifen, Holzbohlen oder Erde), Rückseite und Seiten als Wand
func _ramp(root: Node3D, a: Dictionary, r: Dictionary) -> void:
	var foot := Offroad.world(a, r["c"])
	var dir := Offroad.wdir(a, r["d"])
	var y := Offroad.base_h(a, r["c"])
	var w: float = r["w"]
	var l: float = r["l"]
	var h: float = r["h"]
	var n := Node3D.new()
	n.name = "Rampe"
	n.transform = Transform3D(Basis.looking_at(Vector3(dir.x, 0.0, dir.y), Vector3.UP), Vector3(foot.x, y + 0.01, foot.y))
	root.add_child(n)
	var look: String = r["look"]
	var m: Material = _mats["rampe_" + look]
	Builder._add(n, Track._wedge(w, l, h), m, Vector3.ZERO)
	if look == "stahl":
		var lamp: Material = _mats["lampe_rampe"]
		for s in [-1.0, 1.0]:
			Builder._add(n, Builder.box(Vector3(0.15, 0.15, 0.15)), lamp, Vector3(s * w / 2.0, h + 0.08, -l))
			Builder._add(n, Builder.box(Vector3(0.12, h, 0.12)), _mats["stahl_dunkel"], Vector3(s * (w / 2.0 - 0.2), h / 2.0, -l - 0.1)).set_meta("no_collide", true)
	elif look == "holz":
		# Bohlen quer und zwei Kanthölzer an den Seiten
		var g := {}
		var plank := _box_arrays(Vector3(w, 0.03, 0.05))
		var beam := _box_arrays(Vector3(0.16, 0.16, sqrt(l * l + h * h)))
		for k in int(l / 0.6):
			var z := -0.3 - k * 0.6
			_piece(g, _mats["holz_dunkel"], plank, Transform3D(Basis(Vector3.RIGHT, -atan(h / l)), Vector3(0.0, -z * h / l + 0.02, z)))
		for s in [-1.0, 1.0]:
			_piece(g, _mats["holz_dunkel"], beam, Transform3D(
				Basis(Vector3.RIGHT, atan(h / l)), Vector3(s * (w / 2.0 - 0.08), h / 2.0 + 0.06, -l / 2.0)))
		_bake_same(n, g)
	# Rückseite: wer verkehrt herum kommt, prallt ab (wie die Rampen der Strecken); Seiten: nicht von der Seite auf
	# die hohe Kante (ab einem Drittel der Länge, oben 0,35 m unter der Fahrbahn)
	var back := StaticBody3D.new()
	back.name = "WallsRamp"
	var faces := PackedVector3Array()
	var y0 := -0.6
	var zb := -l - 0.4
	faces.append_array([Vector3(-w / 2.0, y0, zb), Vector3(w / 2.0, y0, zb), Vector3(w / 2.0, h - 1.2, zb),
		Vector3(-w / 2.0, y0, zb), Vector3(w / 2.0, h - 1.2, zb), Vector3(-w / 2.0, h - 1.2, zb)])
	for s in [-1.0, 1.0]:
		var x: float = s * (w / 2.0 + 0.2)
		var za := -l * 0.33
		faces.append_array([Vector3(x, y0, za), Vector3(x, y0, -l), Vector3(x, h - 0.35, -l),
			Vector3(x, y0, za), Vector3(x, h - 0.35, -l), Vector3(x, h * 0.33 - 0.35, za)])
	var sh := ConcavePolygonShape3D.new()
	sh.backface_collision = true
	sh.set_faces(faces)
	var cs := CollisionShape3D.new()
	cs.shape = sh
	back.add_child(cs)
	n.add_child(back)


## Zaun am Umriss (Golfplatz: grüner Maschendraht mit Hecke davor; Kiesgrube: Bauzaun auf Betonfüßen) und die
## unsichtbare Wand (12 m, wie an den Straßen); im Tor offen
func _fence(root: Node3D, a: Dictionary, walls: StaticBody3D) -> void:
	var ol: PackedVector2Array = a["outline_l"]
	var golf: bool = a["kind"] == "golf"
	var posts := []
	var panels := []
	var feet := []
	var hedges := []
	var gs: float = a["gate_s"]
	for k in ol.size():
		var p: Vector2 = ol[k]
		var q: Vector2 = ol[(k + 1) % ol.size()]
		var pieces := [[p, q]]
		if p.y < 1.5 and q.y < 1.5:
			# Straßenseite: Tor ausschneiden
			var lo := minf(p.x, q.x)
			var hi := maxf(p.x, q.x)
			if hi > gs - Offroad.GATE_HALF and lo < gs + Offroad.GATE_HALF:
				pieces = []
				var dirx := signf(q.x - p.x)
				var e0 := gs - Offroad.GATE_HALF * dirx
				var e1 := gs + Offroad.GATE_HALF * dirx
				if (e0 - p.x) * dirx > 0.05:
					pieces.append([p, Vector2(e0, lerpf(p.y, q.y, (e0 - p.x) / (q.x - p.x)))])
				if (q.x - e1) * dirx > 0.05:
					pieces.append([Vector2(e1, lerpf(p.y, q.y, (e1 - p.x) / (q.x - p.x))), q])
		for pc in pieces:
			var la: Vector2 = pc[0]
			var lb: Vector2 = pc[1]
			var wa := Offroad.world(a, la)
			var wb := Offroad.world(a, lb)
			var ha := Offroad.base_h(a, la)
			var hb := Offroad.base_h(a, lb)
			# Golfplatz: die Wand steht an der Innenseite der Hecke (man fährt nicht in die Hecke hinein), am Tor am Zaun
			var ia := _wall_in(a, la) if golf else la
			var ib := _wall_in(a, lb) if golf else lb
			var wia := Offroad.world(a, ia)
			var wib := Offroad.world(a, ib)
			Track._wall_shape(walls, Vector3(wia.x, Offroad.base_h(a, ia) - 0.5, wia.y), Vector3(wib.x, Offroad.base_h(a, ib) - 0.5, wib.y), Track.WALL_H)
			var seg := Vector3(wb.x - wa.x, hb - ha, wb.y - wa.y)
			var len := Vector2(seg.x, seg.z).length()
			if len < 0.2:
				continue
			var basis := Basis.looking_at(Vector3(seg.x, 0.0, seg.z), Vector3.UP)
			var np := maxi(int(round(len / 3.0)), 1)
			for j in np:
				var t0 := float(j) / np
				var t1 := float(j + 1) / np
				var m := (la.lerp(lb, (t0 + t1) / 2.0))
				var wm := Offroad.world(a, m)
				var ym := Offroad.base_h(a, m)
				var plen := len / np
				var pb := basis * Basis.from_scale(Vector3(1.0, 1.0, plen / 3.0))
				panels.append(Transform3D(pb, Vector3(wm.x, ym + (1.0 if golf else 1.05), wm.y)))
				var wpost := Offroad.world(a, la.lerp(lb, t0))
				posts.append(Transform3D(basis, Vector3(wpost.x, Offroad.base_h(a, la.lerp(lb, t0)) + (0.9 if golf else 1.0), wpost.y)))
				if not golf:
					feet.append(Transform3D(basis, Vector3(wpost.x, Offroad.base_h(a, la.lerp(lb, t0)) + 0.08, wpost.y)))
				elif absf(m.x - gs) > Offroad.GATE_HALF + 7.0 or m.y > 3.0:
					# Hecke innen am Zaun (am Tor frei); die Wand steht an ihrer Innenseite (_wall_in)
					var inward := -Offroad._sd_grad(a, m)
					var hm := m + inward * 1.25
					var wh := Offroad.world(a, hm)
					hedges.append(Transform3D(pb, Vector3(wh.x, Offroad.base_h(a, hm) + 0.7, wh.y)))
	if golf:
		Track._multi(root, Builder.box(Vector3(0.08, 1.8, 0.08)), _mats["zaun_gruen"], posts)
		Track._multi(root, Builder.box(Vector3(0.02, 1.6, 3.0)), _mats["maschen_gruen"], panels)
		Track._multi(root, Builder.box(Vector3(1.1, 1.5, 3.0)), _mats["hecke"], hedges)
	else:
		Track._multi(root, Builder.box(Vector3(0.05, 2.0, 0.05)), _mats["bauzaun"], posts)
		Track._multi(root, Builder.box(Vector3(0.02, 1.9, 3.0)), _mats["maschen_grau"], panels)
		Track._multi(root, Builder.box(Vector3(0.25, 0.16, 0.65)), _mats["beton"], feet)


## Wandlinie am Golfplatz: 2,4 m innen (vor der Hecke), zum Tor hin auf den Zaun (dort schließen die Wände der Ausfahrt an)
func _wall_in(a: Dictionary, l: Vector2) -> Vector2:
	var k := 1.0
	if l.y < 3.0:
		k = clampf((absf(l.x - float(a["gate_s"])) - Offroad.GATE_HALF) / 6.0, 0.0, 1.0)
	return l - Offroad._sd_grad(a, l) * 2.4 * k


## Gebäude und Maschinen (fest)
func _build(root: Node3D, a: Dictionary, b: Dictionary) -> void:
	var l: Vector2 = b["c"]
	var wp := Offroad.world(a, l)
	var y := Offroad.base_h(a, l)
	# Drehung: Winkel in Flächenkoordinaten, als Weltrichtung
	var dl := Vector2(cos(float(b["a"])), sin(float(b["a"])))
	var dw := Offroad.wdir(a, dl)
	var xf := Transform3D(Basis.looking_at(Vector3(dw.x, 0.0, dw.y), Vector3.UP), Vector3(wp.x, y, wp.y))
	if b["k"] == "cart":
		_cart(root, xf)
		return
	var n := Node3D.new()
	n.name = str(b["k"]).capitalize()
	n.transform = xf
	root.add_child(n)
	match b["k"]:
		"clubhaus":
			_clubhaus(n, b["size"], a)
		"schuppen":
			_schuppen(n, b["size"])
		"bagger":
			_bagger(n)
		"radlader":
			_radlader(n)
		"kipper":
			_kipper(n)
		"foerderband":
			_foerderband(n, a, l, dl)
		"container":
			_container(n)


func _solid(n: Node3D, size: Vector3, pos: Vector3) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	sb.position = pos
	n.add_child(sb)


## Clubhaus: weiß verputzt, rotes Satteldach, Terrasse mit Sonnenschirmen, Schild über dem Eingang
func _clubhaus(n: Node3D, size: Vector3, a: Dictionary) -> void:
	var w := size.x
	var hgt := size.y
	var dp := size.z
	var g := {}
	# Wände mit dem Haus-Stoff der Landschaft (Fenster, nachts Licht); Länge quer zur Blickrichtung
	if land:
		var mi := MeshInstance3D.new()
		mi.mesh = land._meshes["box"]
		mi.material_override = land.house_mat
		mi.transform = Transform3D(Basis().scaled(Vector3(w, hgt, dp)), Vector3(0, hgt / 2.0, 0))
		n.add_child(mi)
	var roof := MeshInstance3D.new()
	roof.mesh = land._meshes["roof"] if land else Builder.box(Vector3.ONE)
	roof.material_override = _mats["dach"]
	roof.transform = Transform3D(Basis(Vector3.UP, PI / 2.0) * Basis.from_scale(Vector3(dp + 1.2, 4.2, w + 1.2)), Vector3(0, hgt, 0))
	n.add_child(roof)
	# Terrasse (zur Fahrtrichtung -Z) mit Geländer und Schirmen
	_piece(g, _mats["stein"], _box_arrays(Vector3(w * 0.8, 0.3, 5.0)), Transform3D(Basis(), Vector3(0, 0.15, -dp / 2.0 - 2.5)))
	for k in 3:
		var x: float = (k - 1) * w * 0.28
		_piece(g, _mats["holz_dunkel"], _box_arrays(Vector3(0.06, 2.3, 0.06)), Transform3D(Basis(), Vector3(x, 1.4, -dp / 2.0 - 2.6)))
		var cone := CylinderMesh.new()
		cone.top_radius = 0.05
		cone.bottom_radius = 1.6
		cone.height = 0.5
		cone.radial_segments = 8
		Track._part(g, _mats["schirm"], cone, Transform3D(Basis(), Vector3(x, 2.6, -dp / 2.0 - 2.6)))
	_bake_same(n, g)
	_solid(n, Vector3(w, hgt, dp), Vector3(0, hgt / 2.0, 0))
	var lb := Label3D.new()
	lb.text = str(a["name"]).to_upper()
	lb.font_size = 64
	lb.pixel_size = 0.02
	lb.modulate = Color(0.95, 0.85, 0.55)
	lb.outline_size = 8
	lb.outline_modulate = Color(0.05, 0.1, 0.05)
	lb.position = Vector3(0, hgt - 1.4, -dp / 2.0 - 0.06)
	lb.rotation_degrees.y = 180.0
	n.add_child(lb)


## Golfcart: weiß mit grünem Dach, fliegt weg, wenn man es rammt (leicht, kostet etwas Tempo)
func _cart(root: Node3D, xf: Transform3D) -> void:
	var k := Knockable.new()
	k.transform = xf
	k.mass = 140.0
	k.slowdown = 0.8
	var white: Material = _mats["cart_weiss"]
	Builder._add(k, Builder.box(Vector3(1.2, 0.55, 2.3)), white, Vector3(0, 0.55, 0))
	Builder._add(k, Builder.box(Vector3(1.15, 0.5, 0.5)), _mats["sitz"], Vector3(0, 0.95, 0.2))
	Builder._add(k, Builder.box(Vector3(1.25, 0.06, 1.8)), _mats["cart_dach"], Vector3(0, 1.85, 0.05))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			Builder._add(k, Builder.box(Vector3(0.04, 1.0, 0.04)), _mats["stahl_dunkel"], Vector3(sx * 0.55, 1.35, sz * 0.7))
			var wheel := CylinderMesh.new()
			wheel.top_radius = 0.22
			wheel.bottom_radius = 0.22
			wheel.height = 0.16
			wheel.radial_segments = 10
			Builder._add(k, wheel, _mats["reifen"], Vector3(sx * 0.58, 0.22, sz * 0.75)).rotation.z = PI / 2.0
	Track._knock_shape(k, Vector3(1.25, 1.6, 2.3), Vector3(0, 0.85, 0))
	root.add_child(k)


func _schuppen(n: Node3D, size: Vector3) -> void:
	var g := {}
	_piece(g, _mats["holz"], _box_arrays(size), Transform3D(Basis(), Vector3(0, size.y / 2.0, 0)))
	_piece(g, _mats["blech"], _box_arrays(Vector3(size.x + 0.6, 0.15, size.z + 0.6)), Transform3D(Basis(), Vector3(0, size.y + 0.05, 0)))
	_piece(g, _mats["holz_dunkel"], _box_arrays(Vector3(3.2, 3.0, 0.05)), Transform3D(Basis(), Vector3(-2.5, 1.5, -size.z / 2.0 - 0.03)))
	_bake_same(n, g)
	_solid(n, size, Vector3(0, size.y / 2.0, 0))


## Kettenbagger (gelb): Laufwerk, Oberwagen mit Kabine, Ausleger mit Stiel und Löffel
func _bagger(n: Node3D) -> void:
	var g := {}
	var y: Material = _mats["gelb"]
	var dk: Material = _mats["stahl_dunkel"]
	for s in [-1.0, 1.0]:
		_piece(g, dk, _box_arrays(Vector3(0.8, 1.0, 5.0)), Transform3D(Basis(), Vector3(s * 1.5, 0.5, 0)))
	var top := Transform3D(Basis(Vector3.UP, 0.4), Vector3(0, 1.0, 0))
	_piece(g, y, _box_arrays(Vector3(3.0, 1.3, 3.8)), top * Transform3D(Basis(), Vector3(0, 0.75, 0.5)))
	_piece(g, y, _box_arrays(Vector3(1.1, 1.6, 1.5)), top * Transform3D(Basis(), Vector3(0.9, 2.2, -0.6)))
	_piece(g, _mats["glas"], _box_arrays(Vector3(1.0, 0.9, 0.05)), top * Transform3D(Basis(), Vector3(0.9, 2.45, -1.38)))
	_piece(g, y, _box_arrays(Vector3(0.6, 0.6, 5.0)), top * Transform3D(Basis(Vector3.RIGHT, 0.55), Vector3(-0.4, 3.0, -2.4)))
	_piece(g, y, _box_arrays(Vector3(0.5, 0.5, 3.4)), top * Transform3D(Basis(Vector3.RIGHT, -0.9), Vector3(-0.4, 3.2, -5.6)))
	_piece(g, dk, _box_arrays(Vector3(1.3, 1.0, 1.0)), top * Transform3D(Basis(Vector3.RIGHT, 0.4), Vector3(-0.4, 1.0, -6.6)))
	_bake_same(n, g)
	_solid(n, Vector3(3.8, 2.6, 5.0), Vector3(0, 1.3, 0))


## Radlader (gelb): Hinterwagen mit Kabine, Schaufel vorn, große Räder
func _radlader(n: Node3D) -> void:
	var g := {}
	var y: Material = _mats["gelb"]
	_piece(g, y, _box_arrays(Vector3(2.3, 1.4, 4.4)), Transform3D(Basis(), Vector3(0, 1.5, 0.6)))
	_piece(g, y, _box_arrays(Vector3(1.4, 1.5, 1.4)), Transform3D(Basis(), Vector3(0, 2.9, 0.4)))
	_piece(g, _mats["glas"], _box_arrays(Vector3(1.3, 1.0, 0.05)), Transform3D(Basis(), Vector3(0, 3.0, -0.32)))
	_piece(g, _mats["stahl_dunkel"], _box_arrays(Vector3(2.8, 1.0, 1.0)), Transform3D(Basis(Vector3.RIGHT, -0.3), Vector3(0, 0.8, -2.8)))
	for sx in [-1.0, 1.0]:
		for z in [-1.4, 2.0]:
			var wheel := CylinderMesh.new()
			wheel.top_radius = 0.85
			wheel.bottom_radius = 0.85
			wheel.height = 0.6
			wheel.radial_segments = 12
			Track._part(g, _mats["reifen"], wheel, Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(sx * 1.25, 0.85, z)))
	_bake_same(n, g)
	_solid(n, Vector3(3.0, 2.4, 6.6), Vector3(0, 1.2, 0.0))


## Muldenkipper: Fahrerhaus, große Mulde, sechs Räder
func _kipper(n: Node3D) -> void:
	var g := {}
	_piece(g, _mats["orange"], _box_arrays(Vector3(2.5, 1.9, 1.8)), Transform3D(Basis(), Vector3(0, 2.0, -2.8)))
	_piece(g, _mats["glas"], _box_arrays(Vector3(2.2, 0.8, 0.05)), Transform3D(Basis(), Vector3(0, 2.5, -3.72)))
	_piece(g, _mats["stahl_dunkel"], _box_arrays(Vector3(2.4, 0.4, 7.0)), Transform3D(Basis(), Vector3(0, 1.0, 0)))
	_piece(g, _mats["orange"], _box_arrays(Vector3(2.6, 1.5, 4.8)), Transform3D(Basis(Vector3.RIGHT, -0.06), Vector3(0, 2.0, 1.0)))
	_piece(g, _mats["kies_haufen"], _box_arrays(Vector3(2.3, 0.4, 4.4)), Transform3D(Basis(Vector3.RIGHT, -0.06), Vector3(0, 2.8, 1.0)))
	for sx in [-1.0, 1.0]:
		for z in [-2.6, 1.0, 2.4]:
			var wheel := CylinderMesh.new()
			wheel.top_radius = 0.6
			wheel.bottom_radius = 0.6
			wheel.height = 0.45
			wheel.radial_segments = 12
			Track._part(g, _mats["reifen"], wheel, Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(sx * 1.1, 0.6, z)))
	_bake_same(n, g)
	_solid(n, Vector3(2.7, 3.0, 7.4), Vector3(0, 1.5, 0))


## Förderband: schräger Gitterträger vom Boden bis über den Wall, auf Stützen; unten ein Trichter. Fest sind nur
## Trichter und Stützen (darunter hindurchfahren geht, wo es hoch genug ist).
func _foerderband(n: Node3D, a: Dictionary, l: Vector2, dl: Vector2) -> void:
	var g := {}
	var L := 42.0
	var rise := 15.0
	var ang := atan(rise / L)
	var dk: Material = _mats["stahl_dunkel"]
	var beam := Transform3D(Basis(Vector3.RIGHT, ang), Vector3(0, 2.5 + rise / 2.0, -L / 2.0))
	_piece(g, _mats["gelb"], _box_arrays(Vector3(1.4, 0.5, sqrt(L * L + rise * rise))), beam)
	_piece(g, dk, _box_arrays(Vector3(1.0, 0.12, sqrt(L * L + rise * rise))), beam * Transform3D(Basis(), Vector3(0, 0.3, 0)))
	_piece(g, _mats["kies_haufen"], _box_arrays(Vector3(2.6, 1.8, 2.6)), Transform3D(Basis(), Vector3(0, 1.6, 1.0)))
	_solid(n, Vector3(2.6, 3.0, 2.6), Vector3(0, 1.5, 1.0))
	for k in 4:
		var z := -6.0 - k * 10.0
		var top := 2.5 + rise * (-z) / L
		# Stütze auf dem Boden darunter (der Wall steigt an)
		var wp := l + dl * (-z)
		var gy := Offroad.base_h(a, wp) - Offroad.base_h(a, l)
		var hgt := maxf(top - gy, 0.5)
		for s in [-1.0, 1.0]:
			_piece(g, dk, _box_arrays(Vector3(0.25, hgt, 0.25)), Transform3D(Basis(), Vector3(s * 0.7, gy + hgt / 2.0, z)))
		if hgt > 0.6:
			var sb := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			var cy := CylinderShape3D.new()
			cy.radius = 0.45
			cy.height = 3.0
			cs.shape = cy
			sb.add_child(cs)
			sb.position = Vector3(0, gy + 1.5, z)
			n.add_child(sb)
	_bake_same(n, g)


## Baucontainer (zwei übereinander, blau-weiß, mit Fenstern und Treppe) und ein Flutlichtmast daneben
func _container(n: Node3D) -> void:
	var g := {}
	for k in 2:
		var x := 0.0 if k == 0 else 0.4
		_piece(g, _mats["container"], _box_arrays(Vector3(6.0, 2.6, 2.4)), Transform3D(Basis(), Vector3(x, 1.3 + k * 2.65, 0)))
		for wx in [-1.6, 1.4]:
			_piece(g, _mats["glas"], _box_arrays(Vector3(1.1, 0.8, 0.05)), Transform3D(Basis(), Vector3(x + wx, 1.6 + k * 2.65, -1.22)))
	_piece(g, _mats["stahl_dunkel"], _box_arrays(Vector3(0.9, 0.08, 4.0)), Transform3D(Basis(Vector3.RIGHT, 0.7), Vector3(3.5, 1.4, -0.2)))
	_bake_same(n, g)
	_solid(n, Vector3(6.4, 5.4, 2.6), Vector3(0.2, 2.7, 0))


## Leichte Teile, die wegfliegen: Fahnen auf den Grüns, Dixi-Klo, Absperrbaken, Leitkegel
func _knocks(root: Node3D, a: Dictionary) -> void:
	for kd in a["knock"]:
		var l: Vector2 = kd["c"]
		var wp := Offroad.world(a, l)
		var k := Knockable.new()
		k.transform = Transform3D(Basis(Vector3.UP, wp.x * 0.37), Vector3(wp.x, Offroad.base_h(a, l), wp.y))
		match kd["k"]:
			"fahne":
				Builder._add(k, Builder.box(Vector3(0.03, 2.3, 0.03)), _mats["cart_weiss"], Vector3(0, 1.15, 0))
				Builder._add(k, Builder.box(Vector3(0.02, 0.45, 0.65)), _mats["fahne"], Vector3(0, 2.05, 0.33))
				Track._knock_shape(k, Vector3(0.3, 2.3, 0.3), Vector3(0, 1.15, 0))
				k.mass = 2.0
				k.slowdown = 0.995
			"dixi":
				Builder._add(k, Builder.box(Vector3(1.1, 2.2, 1.1)), _mats["dixi"], Vector3(0, 1.1, 0))
				Builder._add(k, Builder.box(Vector3(1.15, 0.12, 1.15)), _mats["cart_weiss"], Vector3(0, 2.25, 0))
				Track._knock_shape(k, Vector3(1.1, 2.3, 1.1), Vector3(0, 1.15, 0))
				k.mass = 70.0
				k.slowdown = 0.9
			"bake":
				Builder._add(k, Builder.box(Vector3(0.12, 1.0, 0.25)), _mats["bake"], Vector3(0, 0.75, 0))
				Builder._add(k, Builder.box(Vector3(0.5, 0.1, 0.4)), _mats["stahl_dunkel"], Vector3(0, 0.05, 0))
				Track._knock_shape(k, Vector3(0.5, 1.25, 0.4), Vector3(0, 0.62, 0))
				k.mass = 9.0
				k.slowdown = 0.98
			"kegel":
				var c := CylinderMesh.new()
				c.top_radius = 0.04
				c.bottom_radius = 0.25
				c.height = 0.7
				c.radial_segments = 8
				Builder._add(k, c, _mats["kegel"], Vector3(0, 0.35, 0))
				Track._knock_shape(k, Vector3(0.5, 0.7, 0.5), Vector3(0, 0.35, 0))
				k.mass = 3.0
				k.slowdown = 0.99
		root.add_child(k)


## Tor: zwei Pfosten mit offenem Schlagbaum, daneben das Schild mit dem Namen (zur Straße hin lesbar)
func _gate(root: Node3D, a: Dictionary) -> void:
	var gs: float = a["gate_s"]
	var v3 := Vector3(float(a["v"].x), 0.0, float(a["v"].y))
	var b := Basis.looking_at(v3, Vector3.UP)  # -Z ins Gelände, Schild von der Straße (+Z) lesbar
	var golf: bool = a["kind"] == "golf"
	var g := {}
	for s in [-1.0, 1.0]:
		var lp := Vector2(gs + s * (Offroad.GATE_HALF + 0.3), 0.6)
		var wp := Offroad.world(a, lp)
		_piece(g, _mats["holz_dunkel"] if golf else _mats["bake"], _box_arrays(Vector3(0.3, 1.4, 0.3)),
			Transform3D(b, Vector3(wp.x, Offroad.base_h(a, lp) + 0.7, wp.y)))
	# Schlagbaum hochgeklappt am linken Pfosten
	var lp0 := Vector2(gs - Offroad.GATE_HALF - 0.3, 0.6)
	var w0 := Offroad.world(a, lp0)
	_piece(g, _mats["bake"], _box_arrays(Vector3(0.12, 5.0, 0.12)), Transform3D(b, Vector3(w0.x, Offroad.base_h(a, lp0) + 3.8, w0.y)))
	_bake_same(root, g)
	# Schild rechts neben dem Tor, schräg zur Straße
	var sp := Vector2(gs + Offroad.GATE_HALF + 4.5, -0.8)
	var ws := Offroad.world(a, sp)
	var sn := Node3D.new()
	sn.name = "Schild"
	sn.transform = Transform3D(b.rotated(Vector3.UP, 0.35 * (1.0 if (a["u"] as Vector2).cross(a["v"]) > 0.0 else -1.0)), Vector3(ws.x, 0.0, ws.y))
	root.add_child(sn)
	var gg := {}
	var board: Material = _mats["schild_gruen"] if golf else _mats["schild_weiss"]
	_piece(gg, _mats["holz_dunkel"] if golf else _mats["stahl_dunkel"], _box_arrays(Vector3(0.18, 3.2, 0.18)), Transform3D(Basis(), Vector3(-2.6, 1.6, 0)))
	_piece(gg, _mats["holz_dunkel"] if golf else _mats["stahl_dunkel"], _box_arrays(Vector3(0.18, 3.2, 0.18)), Transform3D(Basis(), Vector3(2.6, 1.6, 0)))
	_piece(gg, board, _box_arrays(Vector3(6.2, 1.5, 0.12)), Transform3D(Basis(), Vector3(0, 2.5, 0)))
	if not golf:
		_piece(gg, _mats["warnschild"], _box_arrays(Vector3(4.2, 1.1, 0.1)), Transform3D(Basis(), Vector3(0, 1.05, 0.02)))
	_bake_same(sn, gg)
	var t1 := Label3D.new()
	t1.text = str(a["name"]).to_upper()
	t1.font_size = 56
	t1.pixel_size = 0.018
	t1.modulate = Color(0.95, 0.88, 0.6) if golf else Color(0.08, 0.1, 0.14)
	t1.outline_size = 0
	t1.position = Vector3(0, 2.62, 0.08)
	t1.width = 330.0
	t1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sn.add_child(t1)
	var t2 := Label3D.new()
	t2.text = "Gäste willkommen · Bitte Schritt fahren" if golf else "Kies · Sand · Recycling"
	t2.font_size = 26
	t2.pixel_size = 0.018
	t2.modulate = t1.modulate
	t2.outline_size = 0
	t2.position = Vector3(0, 2.0, 0.08)
	sn.add_child(t2)
	if not golf:
		var t3 := Label3D.new()
		t3.text = "BAUSTELLE\nBetreten verboten!\nEltern haften für ihre Kinder"
		t3.font_size = 24
		t3.pixel_size = 0.018
		t3.modulate = Color(0.05, 0.05, 0.05)
		t3.outline_size = 0
		t3.position = Vector3(0, 1.05, 0.08)
		sn.add_child(t3)


## Laternen (Parkplatz, Baustelle): Mast mit Leuchte, Licht nur nachts
func _lamps(root: Node3D, a: Dictionary) -> void:
	var lamps := []
	var g := {}
	for l in a["lights"]:
		var wp := Offroad.world(a, l)
		var y := Offroad.base_h(a, l)
		_piece(g, _mats["stahl_dunkel"], _box_arrays(Vector3(0.14, 6.0, 0.14)), Transform3D(Basis(), Vector3(wp.x, y + 3.0, wp.y)))
		_piece(g, _mats["leuchte"], _box_arrays(Vector3(0.5, 0.18, 0.5)), Transform3D(Basis(), Vector3(wp.x, y + 6.0, wp.y)))
		var ol := OmniLight3D.new()
		ol.light_color = Color(1.0, 0.82, 0.6)
		ol.omni_range = 26.0
		ol.position = Vector3(wp.x, y + 5.6, wp.y)
		ol.shadow_enabled = false
		root.add_child(ol)
		lamps.append(ol)
		var sb := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var cy := CylinderShape3D.new()
		cy.radius = 0.2
		cy.height = 3.0
		cs.shape = cy
		sb.add_child(cs)
		sb.position = Vector3(wp.x, y + 1.5, wp.y)
		root.add_child(sb)
	_bake_same(root, g)
	root.set_meta("lamps", lamps)


# --- Stoffe -------------------------------------------------------------------------------------------------------------

func _make_mats() -> void:
	if not _mats.is_empty():
		return
	for kind in ["golf", "kies"]:
		var m := ShaderMaterial.new()
		m.shader = SHADER
		m.set_shader_parameter("kind", 0 if kind == "golf" else 1)
		_mats["boden_" + kind] = m
	var water := StandardMaterial3D.new()
	water.albedo_color = Color(0.08, 0.14, 0.2)
	water.roughness = 0.1
	water.metallic = 0.3
	_mats["wasser"] = water
	var ramp := ShaderMaterial.new()
	ramp.shader = Track.RAMP_SHADER
	_mats["rampe_stahl"] = ramp
	_mats["rampe_holz"] = Builder.mat(Color(0.45, 0.31, 0.17), 0.0, 0.85)
	_mats["rampe_erde"] = Builder.mat(Color(0.33, 0.24, 0.15), 0.0, 1.0)
	_mats["holz"] = Builder.mat(Color(0.42, 0.3, 0.18), 0.0, 0.85)
	_mats["holz_dunkel"] = Builder.mat(Color(0.25, 0.16, 0.09), 0.0, 0.85)
	_mats["stahl_dunkel"] = Builder.mat(Color(0.18, 0.18, 0.2), 0.6, 0.45)
	_mats["lampe_rampe"] = Builder.mat(Color(1, 0.5, 0.05), 0.0, 0.4, Color(1, 0.45, 0.0), 5.0)
	_mats["fels"] = Builder.mat(Color(0.42, 0.4, 0.37), 0.0, 0.95)
	_mats["zaun_gruen"] = Builder.mat(Color(0.07, 0.2, 0.1), 0.5, 0.5)
	var mg := Builder.mat(Color(0.1, 0.25, 0.12, 0.45), 0.4, 0.6)
	mg.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mg.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["maschen_gruen"] = mg
	var mgr := Builder.mat(Color(0.55, 0.57, 0.6, 0.35), 0.6, 0.5)
	mgr.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mgr.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["maschen_grau"] = mgr
	_mats["bauzaun"] = Builder.mat(Color(0.6, 0.62, 0.64), 0.7, 0.4)
	_mats["beton"] = Builder.mat(Color(0.55, 0.55, 0.53), 0.0, 0.9)
	_mats["hecke"] = Builder.mat(Color(0.05, 0.18, 0.06), 0.0, 0.9)
	_mats["dach"] = Builder.mat(Color(0.48, 0.15, 0.08), 0.0, 0.8)
	_mats["stein"] = Builder.mat(Color(0.6, 0.57, 0.52), 0.0, 0.9)
	_mats["schirm"] = Builder.mat(Color(0.85, 0.85, 0.8), 0.0, 0.7)
	_mats["cart_weiss"] = Builder.mat(Color(0.9, 0.9, 0.88), 0.1, 0.4)
	_mats["cart_dach"] = Builder.mat(Color(0.08, 0.3, 0.14), 0.0, 0.6)
	_mats["sitz"] = Builder.mat(Color(0.12, 0.12, 0.13), 0.0, 0.7)
	_mats["reifen"] = Builder.mat(Color(0.05, 0.05, 0.05), 0.0, 0.9)
	_mats["blech"] = Builder.mat(Color(0.35, 0.36, 0.38), 0.6, 0.5)
	_mats["gelb"] = Builder.mat(Color(0.95, 0.68, 0.05), 0.2, 0.55)
	_mats["orange"] = Builder.mat(Color(0.9, 0.42, 0.08), 0.2, 0.55)
	_mats["glas"] = Builder.mat(Color(0.12, 0.16, 0.2), 0.6, 0.15)
	_mats["kies_haufen"] = Builder.mat(Color(0.58, 0.55, 0.49), 0.0, 1.0)
	_mats["container"] = Builder.mat(Color(0.2, 0.32, 0.62), 0.3, 0.55)
	_mats["fahne"] = Builder.mat(Color(0.9, 0.12, 0.1), 0.0, 0.6)
	_mats["dixi"] = Builder.mat(Color(0.12, 0.35, 0.75), 0.1, 0.5)
	_mats["bake"] = Builder.mat(Color(0.85, 0.12, 0.1), 0.1, 0.5)
	_mats["kegel"] = Builder.mat(Color(1, 0.4, 0.05), 0, 0.5, Color(1, 0.35, 0.0), 0.6)
	_mats["schild_gruen"] = Builder.mat(Color(0.05, 0.2, 0.1), 0.0, 0.6)
	_mats["schild_weiss"] = Builder.mat(Color(0.92, 0.92, 0.9), 0.0, 0.6)
	_mats["warnschild"] = Builder.mat(Color(0.95, 0.75, 0.05), 0.0, 0.6)
	_mats["leuchte"] = Builder.mat(Color(1.0, 0.9, 0.7), 0.0, 0.4, Color(1.0, 0.8, 0.55), 3.0)
