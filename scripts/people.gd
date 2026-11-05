extends RefCounted
## Leute: Figuren aus weichen Grundformen (Hüfte, Rumpf mit Schultern, Hals, Kopf mit Nase, Ohren und Gesicht,
## Ober- und Unterarme mit Ellbogen, Hände, Beine, Turnschuhe mit Sohle), bewegt vom Shader. Kleidung und Frisur
## wechseln je Figur: T-Shirt, Langarm, Hoodie mit Kapuze, offene Jacke; Jeans, Shorts, Rock; kurze oder lange
## Haare, Zopf, Dutt, Glatze, Kappe, Mütze. Alle Varianten stecken in einem Modell; der Shader blendet die nicht
## gewählten Teile aus (UV2.x = Variante), so bleibt es ein MultiMesh je Gruppe.
## In der Ferne eine einfache Blockfigur mit denselben Bewegungen (ab 30–96 m je nach Detaildichte, gemessen zur
## Mitte einer Zelle). Gruppen werden dafür in Zellen von CELL m geteilt, jede mit naher und ferner Fassung.

const SHADER := preload("res://shaders/people.gdshader")

enum { CHEER, DANCE, WAIT, WAVE, CLAP, RUN, PHONE, STARTER }

const SHIRTS := [Color(0.85, 0.1, 0.12), Color(0.1, 0.35, 0.85), Color(0.95, 0.8, 0.1), Color(0.92, 0.92, 0.92),
	Color(0.08, 0.08, 0.09), Color(0.2, 0.75, 0.35), Color(0.95, 0.45, 0.1), Color(0.6, 0.2, 0.75),
	Color(1.0, 0.3, 0.6), Color(0.1, 0.8, 0.9), Color(0.45, 0.47, 0.5), Color(0.55, 0.12, 0.16)]

const CELL := 30.0

## Körperteile (UV.x) für die Bewegung im Shader
enum { P_BODY, P_ARM_L, P_ARM_R, P_LEG_L, P_LEG_R, P_HEAD, P_FORE_L, P_FORE_R }
## Farbgruppen (UV.y), siehe people.gdshader
enum { G_TOP, G_PANTS, G_SKIN, G_HAIR, G_SHOES, G_GLOW, G_ARM, G_SHIN, G_SOLE, G_JACKET, G_CAP, G_PHONE, G_SCREEN,
	G_SKIRT, G_THIGH }
## Varianten (UV2.x): 0 immer sichtbar
enum { O_ALL, O_HAIR_TOP, O_HAIR_LONG, O_PONY, O_BUN, O_CAP, O_BEANIE, O_HOOD, O_SKIRT, O_JACKET, O_STICKS, O_PHONE,
	O_HAIR_NAPE }

## 0/1: Figur (alle Varianten), 2: Starterin (mit Leuchtstäben), 3: Blockfigur für die Ferne
static var _meshes := {}


static func mesh(kind: int) -> ArrayMesh:
	if kind == 1:
		kind = 0
	if _meshes.has(kind):
		return _meshes[kind]
	var m := _far_mesh() if kind == 3 else _detail_mesh(kind == 2)
	_meshes[kind] = m
	return m


static func _detail_mesh(sticks: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Beine: Oberschenkel (oben Hose, unten Hose oder Haut bei Shorts/Rock), Schienbein, Turnschuh mit heller Sohle
	for s in [-1.0, 1.0]:
		var leg := P_LEG_L if s < 0.0 else P_LEG_R
		var x: float = s * 0.09
		_tube(st, [[Vector3(x, 0.94, 0.0), 0.098, 0.102], [Vector3(x, 0.72, -0.006), 0.079, 0.084]], 8, leg, G_PANTS, O_ALL, false, false)
		_tube(st, [[Vector3(x, 0.72, -0.006), 0.079, 0.084], [Vector3(x * 1.02, 0.5, 0.0), 0.062, 0.066]], 8, leg, G_THIGH, O_ALL, false, false)
		_tube(st, [[Vector3(x * 1.02, 0.5, 0.0), 0.061, 0.064], [Vector3(x * 1.04, 0.32, 0.014), 0.055, 0.062],
			[Vector3(x * 1.05, 0.11, 0.0), 0.04, 0.043]], 8, leg, G_SHIN, O_ALL, false, false)
		_ellipsoid(st, Vector3(x * 1.05, 0.035, -0.035), Vector3(0.052, 0.075, 0.125), 8, 6, leg, G_SHOES, O_ALL, 0.0, 0.5)
		_box(st, Vector3(x * 1.05, 0.016, -0.035), Vector3(0.1, 0.032, 0.25), leg, G_SOLE, O_ALL)
	# Hüfte, Rumpf (Taille schmal, Brust und Schultern breiter), Hals
	_tube(st, [[Vector3(0, 0.8, 0.0), 0.1, 0.075], [Vector3(0, 0.86, 0.0), 0.15, 0.096], [Vector3(0, 0.99, 0.0), 0.148, 0.098]],
		10, P_BODY, G_PANTS, O_ALL, true, true)
	_tube(st, [[Vector3(0, 0.98, 0.0), 0.146, 0.097], [Vector3(0, 1.12, 0.0), 0.153, 0.1], [Vector3(0, 1.27, -0.004), 0.178, 0.115],
		[Vector3(0, 1.38, 0.0), 0.198, 0.105], [Vector3(0, 1.44, 0.004), 0.13, 0.085], [Vector3(0, 1.47, 0.006), 0.06, 0.05]],
		10, P_BODY, G_TOP, O_ALL, false, true)
	_tube(st, [[Vector3(0, 1.42, 0.008), 0.047, 0.045], [Vector3(0, 1.545, 0.0), 0.044, 0.044]], 8, P_BODY, G_SKIN, O_ALL, false, false)
	# offene Jacke: Hülle um den Rumpf, vorn in der Mitte offen (dort sieht man das Shirt)
	_tube(st, [[Vector3(0, 0.9, 0.0), 0.162, 0.11], [Vector3(0, 1.12, 0.0), 0.166, 0.112], [Vector3(0, 1.27, -0.004), 0.19, 0.126],
		[Vector3(0, 1.38, 0.0), 0.208, 0.115], [Vector3(0, 1.45, 0.006), 0.13, 0.092]], 10, P_BODY, G_JACKET, O_JACKET, false, false, 0.2)
	# Kapuze des Hoodies, im Nacken
	_ellipsoid(st, Vector3(0, 1.45, 0.085), Vector3(0.13, 0.075, 0.075), 8, 5, P_BODY, G_TOP, O_HOOD)
	# Rock
	_tube(st, [[Vector3(0, 0.99, 0.0), 0.158, 0.106], [Vector3(0, 0.9, 0.0), 0.205, 0.14], [Vector3(0, 0.6, 0.0), 0.25, 0.2]],
		10, P_BODY, G_SKIRT, O_SKIRT, false, false)
	# Arme: Schulter, Oberarm (oben immer Ärmel, unten Ärmel oder Haut), Unterarm, Hand mit Daumen
	for s in [-1.0, 1.0]:
		var up := P_ARM_L if s < 0.0 else P_ARM_R
		var fo := P_FORE_L if s < 0.0 else P_FORE_R
		_ellipsoid(st, Vector3(s * 0.2, 1.38, 0.0), Vector3(0.064, 0.062, 0.066), 8, 6, up, G_TOP, O_ALL)
		_tube(st, [[Vector3(s * 0.235, 1.39, 0.0), 0.062, 0.064], [Vector3(s * 0.248, 1.26, 0.0), 0.056, 0.058]], 8, up, G_TOP, O_ALL, false, false)
		_tube(st, [[Vector3(s * 0.248, 1.26, 0.0), 0.054, 0.056], [Vector3(s * 0.255, 1.13, 0.0), 0.048, 0.049]], 8, up, G_ARM, O_ALL, false, false)
		_ellipsoid(st, Vector3(s * 0.255, 1.13, 0.0), Vector3(0.047, 0.047, 0.048), 6, 4, fo, G_ARM, O_ALL)
		_tube(st, [[Vector3(s * 0.255, 1.13, 0.0), 0.047, 0.048], [Vector3(s * 0.262, 1.0, -0.004), 0.043, 0.045],
			[Vector3(s * 0.266, 0.89, 0.0), 0.034, 0.036]], 8, fo, G_ARM, O_ALL, false, false)
		_ellipsoid(st, Vector3(s * 0.268, 0.84, -0.006), Vector3(0.026, 0.056, 0.042), 6, 5, fo, G_SKIN, O_ALL)
		_ellipsoid(st, Vector3(s * 0.258, 0.855, -0.042), Vector3(0.015, 0.03, 0.016), 5, 4, fo, G_SKIN, O_ALL)
		if sticks:
			_box(st, Vector3(s * 0.268, 0.74, -0.02), Vector3(0.04, 0.24, 0.04), fo, G_GLOW, O_ALL)
	# Handy in der rechten Hand (nur beim Telefonieren sichtbar), Bildschirm zum Kopf
	_box(st, Vector3(0.245, 0.83, -0.035), Vector3(0.014, 0.13, 0.068), P_FORE_R, G_PHONE, O_PHONE)
	_box(st, Vector3(0.237, 0.83, -0.035), Vector3(0.003, 0.115, 0.058), P_FORE_R, G_SCREEN, O_PHONE)
	# Kopf: leicht länglich, Nase, Ohren; Augen, Brauen und Mund malt der Shader
	_ellipsoid(st, Vector3(0, 1.627, 0.004), Vector3(0.093, 0.115, 0.104), 10, 8, P_HEAD, G_SKIN, O_ALL)
	_ellipsoid(st, Vector3(0, 1.606, -0.1), Vector3(0.016, 0.03, 0.022), 6, 4, P_HEAD, G_SKIN, O_ALL)
	for s in [-1.0, 1.0]:
		_ellipsoid(st, Vector3(s * 0.093, 1.618, 0.012), Vector3(0.014, 0.027, 0.019), 6, 4, P_HEAD, G_SKIN, O_ALL)
	# Haare: Oberkopf (ohne Kopfbedeckung), Nacken (kurz, Zopf, Dutt), lang über den Rücken, Zopf, Dutt
	_ellipsoid(st, Vector3(0, 1.636, 0.014), Vector3(0.101, 0.12, 0.113), 10, 6, P_HEAD, G_HAIR, O_HAIR_TOP, 0.0, 0.5)
	_ellipsoid(st, Vector3(0, 1.627, 0.012), Vector3(0.099, 0.117, 0.11), 10, 5, P_HEAD, G_HAIR, O_HAIR_NAPE, 0.4, 0.78, 0.0, 0.5)
	_ellipsoid(st, Vector3(0, 1.5, 0.03), Vector3(0.112, 0.21, 0.105), 10, 7, P_HEAD, G_HAIR, O_HAIR_LONG, 0.2, 0.9, 0.0, 0.5)
	_ellipsoid(st, Vector3(0, 1.58, 0.135), Vector3(0.036, 0.1, 0.036), 6, 6, P_HEAD, G_HAIR, O_PONY)
	_ellipsoid(st, Vector3(0, 1.66, 0.112), Vector3(0.022, 0.022, 0.022), 5, 4, P_HEAD, G_CAP, O_PONY)
	_ellipsoid(st, Vector3(0, 1.735, 0.05), Vector3(0.058, 0.052, 0.058), 8, 6, P_HEAD, G_HAIR, O_BUN)
	# Kappe mit Schirm, Mütze mit Umschlag
	_ellipsoid(st, Vector3(0, 1.648, 0.012), Vector3(0.105, 0.105, 0.116), 10, 6, P_HEAD, G_CAP, O_CAP, 0.0, 0.5)
	_box(st, Vector3(0, 1.66, -0.135), Vector3(0.15, 0.014, 0.1), P_HEAD, G_CAP, O_CAP)
	_ellipsoid(st, Vector3(0, 1.655, 0.01), Vector3(0.106, 0.13, 0.117), 10, 6, P_HEAD, G_CAP, O_BEANIE, 0.0, 0.48)
	_tube(st, [[Vector3(0, 1.645, 0.01), 0.109, 0.12], [Vector3(0, 1.69, 0.01), 0.106, 0.117]], 10, P_HEAD, G_CAP, O_BEANIE, false, false)
	# gemeinsame Ecken zusammenfassen: der Vertex-Shader läuft dann je Ecke nur einmal statt für jedes Dreieck
	st.index()
	return st.commit()


## Blockfigur (wie bis 2.13) für die Ferne: wenige Dreiecke, gleiche Körperteile und Farben
static func _far_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in [-1.0, 1.0]:
		var leg := P_LEG_L if s < 0.0 else P_LEG_R
		_box(st, Vector3(s * 0.09, 0.47, 0.0), Vector3(0.14, 0.74, 0.16), leg, G_PANTS, O_ALL)
		_box(st, Vector3(s * 0.09, 0.05, -0.03), Vector3(0.15, 0.1, 0.25), leg, G_SHOES, O_ALL)
	_box(st, Vector3(0, 0.98, 0), Vector3(0.32, 0.3, 0.2), P_BODY, G_TOP, O_ALL)
	_box(st, Vector3(0, 1.26, 0), Vector3(0.42, 0.28, 0.22), P_BODY, G_TOP, O_ALL)
	for s in [-1.0, 1.0]:
		_box(st, Vector3(s * 0.26, 1.25, 0), Vector3(0.11, 0.3, 0.12), P_ARM_L if s < 0.0 else P_ARM_R, G_TOP, O_ALL)
		_box(st, Vector3(s * 0.26, 0.98, 0), Vector3(0.09, 0.26, 0.1), P_FORE_L if s < 0.0 else P_FORE_R, G_ARM, O_ALL)
	_box(st, Vector3(0, 1.6, 0), Vector3(0.2, 0.24, 0.22), P_HEAD, G_SKIN, O_ALL)
	_box(st, Vector3(0, 1.74, 0.02), Vector3(0.22, 0.07, 0.25), P_HEAD, G_HAIR, O_ALL)
	_box(st, Vector3(0, 1.64, 0.1), Vector3(0.22, 0.18, 0.06), P_HEAD, G_HAIR, O_ALL)
	return st.commit()


## Dreieck so anlegen, dass es von außen (Richtung out) gesehen im Uhrzeigersinn läuft (Godots Vorderseite)
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, uv: Vector2, uv2: Vector2) -> void:
	var out := na + nb + nc
	if (b - a).cross(c - a).dot(out) > 0.0:
		var t := b
		b = c
		c = t
		var tn := nb
		nb = nc
		nc = tn
	for p in [[a, na], [b, nb], [c, nc]]:
		st.set_normal(p[1])
		st.set_uv(uv)
		st.set_uv2(uv2)
		st.add_vertex(p[0])


## Röhre durch Ringe [Mitte, Halbachse x, Halbachse z]; gap: Anteil des Umfangs vorn (-Z), der offen bleibt
static func _tube(st: SurfaceTool, rings: Array, sides: int, part: int, grp: int, opt: int, cap_bottom: bool, cap_top: bool, gap := 0.0) -> void:
	var uv := Vector2(part, grp)
	var uv2 := Vector2(opt, 0)
	var pts := []
	var nrm := []
	for r in rings:
		var c: Vector3 = r[0]
		var rx: float = r[1]
		var rz: float = r[2]
		var row := []
		var nrow := []
		for i in sides + 1:
			# Winkel 0 = hinten (+Z), gap um vorn (PI) herum ausgespart
			var a := PI * gap + (TAU - TAU * gap) * float(i) / sides
			var d := Vector3(sin(a), 0.0, cos(a))
			row.append(c + Vector3(d.x * rx, 0.0, d.z * rz))
			nrow.append(Vector3(d.x / rx, 0.0, d.z / rz).normalized())
		pts.append(row)
		nrm.append(nrow)
	for k in rings.size() - 1:
		for i in sides:
			var a: Vector3 = pts[k][i]
			var b: Vector3 = pts[k][i + 1]
			var c: Vector3 = pts[k + 1][i + 1]
			var d: Vector3 = pts[k + 1][i]
			_tri(st, a, b, c, nrm[k][i], nrm[k][i + 1], nrm[k + 1][i + 1], uv, uv2)
			_tri(st, a, c, d, nrm[k][i], nrm[k + 1][i + 1], nrm[k + 1][i], uv, uv2)
			if gap > 0.0:
				# offene Kanten auch von innen sichtbar: Rückseiten dazu
				_tri(st, a, c, b, -nrm[k][i], -nrm[k + 1][i + 1], -nrm[k][i + 1], uv, uv2)
				_tri(st, a, d, c, -nrm[k][i], -nrm[k + 1][i], -nrm[k + 1][i + 1], uv, uv2)
	for cap in [[cap_bottom, 0, Vector3.DOWN], [cap_top, rings.size() - 1, Vector3.UP]]:
		if not cap[0]:
			continue
		var k: int = cap[1]
		var c: Vector3 = rings[k][0]
		for i in sides:
			_tri(st, c, pts[k][i], pts[k][i + 1], cap[2], cap[2], cap[2], uv, uv2)


## Ellipsoid (oder ein Ausschnitt davon): v von oben (0) nach unten (1), u um die Hochachse (0 = +X, 0.5 = -X über hinten)
static func _ellipsoid(st: SurfaceTool, c: Vector3, r: Vector3, nu: int, nv: int, part: int, grp: int, opt: int,
		v0 := 0.0, v1 := 1.0, u0 := 0.0, u1 := 1.0) -> void:
	var uv := Vector2(part, grp)
	var uv2 := Vector2(opt, 0)
	var grid := []
	for j in nv + 1:
		var th := PI * lerpf(v0, v1, float(j) / nv)
		var row := []
		for i in nu + 1:
			var ph := TAU * lerpf(u0, u1, float(i) / nu)
			var d := Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
			row.append([c + d * r, Vector3(d.x / r.x, d.y / r.y, d.z / r.z).normalized()])
		grid.append(row)
	for j in nv:
		for i in nu:
			var a: Array = grid[j][i]
			var b: Array = grid[j][i + 1]
			var cc: Array = grid[j + 1][i + 1]
			var d: Array = grid[j + 1][i]
			if (a[0] as Vector3).distance_squared_to(b[0]) > 1e-10:
				_tri(st, a[0], b[0], cc[0], a[1], b[1], cc[1], uv, uv2)
			if (cc[0] as Vector3).distance_squared_to(d[0]) > 1e-10:
				_tri(st, a[0], cc[0], d[0], a[1], cc[1], d[1], uv, uv2)


## Quader mit Teil-, Farb- und Variantenkennung
static func _box(st: SurfaceTool, c: Vector3, size: Vector3, part: int, grp: int, opt: int) -> void:
	var h := size / 2.0
	var uv := Vector2(part, grp)
	var uv2 := Vector2(opt, 0)
	var faces := [
		[Vector3.RIGHT, [Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(1, -1, 1)]],
		[Vector3.LEFT, [Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1), Vector3(-1, -1, -1)]],
		[Vector3.UP, [Vector3(-1, 1, -1), Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1)]],
		[Vector3.DOWN, [Vector3(-1, -1, 1), Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1)]],
		[Vector3.BACK, [Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1), Vector3(-1, -1, 1)]],
		[Vector3.FORWARD, [Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, -1, -1)]],
	]
	for f in faces:
		var q: Array = f[1]
		var n: Vector3 = f[0]
		_tri(st, c + q[0] * h, c + q[1] * h, c + q[2] * h, n, n, n, uv, uv2)
		_tri(st, c + q[0] * h, c + q[2] * h, c + q[3] * h, n, n, n, uv, uv2)


static func material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	return m


## Gruppe aus Figuren an den Transformationen xfs (Blick = lokales -Z). modes: Liste möglicher Bewegungen.
## far: Sichtweite (0 = ohne Grenze). Liefert einen Knoten mit je Zelle zwei MultiMeshes (nah detailliert, fern als
## Blockfigur); set_mode() kann später umschalten.
static func crowd(parent: Node3D, xfs: Array, modes: Array, rng: RandomNumberGenerator, far := 0.0) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	var mat := material()
	# Detaildichte Niedrig bis Ultra: 30 / 42 / 60 / 96 m
	var near := maxf(30.0, GameState.gv("detail")[2] * 1.2)
	var cells := {}
	for xf in xfs:
		var p: Vector3 = xf.origin
		var key := Vector2i(floori(p.x / CELL), floori(p.z / CELL))
		if not cells.has(key):
			cells[key] = []
		var s := rng.randf_range(0.9, 1.08)
		var w := rng.randf_range(0.92, 1.12)  # Statur: schmal bis kräftig
		var b: Basis = xf.basis.scaled(Vector3(s * w, s, s * lerpf(1.0, w, 0.6)))
		cells[key].append([Transform3D(b, p), SHIRTS[rng.randi() % SHIRTS.size()],
			Color(rng.randf(), rng.randf(), modes[rng.randi() % modes.size()] / 10.0, rng.randf())])
	for key in cells:
		var list: Array = cells[key]
		for lod in 2:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = mesh(0 if lod == 0 else 3)
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, list[i][0])
				mm.set_instance_color(i, list[i][1])
				mm.set_instance_custom_data(i, list[i][2])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = mat
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if lod == 0:
				mmi.visibility_range_end = near
				mmi.visibility_range_end_margin = 4.0
			else:
				mmi.visibility_range_begin = near
				mmi.visibility_range_begin_margin = 4.0
				if far > 0.0:
					mmi.visibility_range_end = far
					mmi.visibility_range_end_margin = 20.0
					mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			holder.add_child(mmi)
	holder.set_meta("mat", mat)
	return holder


## Alle Figuren einer Gruppe auf eine Bewegung umstellen
static func set_mode(holder: Node3D, mode: int) -> void:
	for c in holder.get_children():
		if c is MultiMeshInstance3D:
			var mm: MultiMesh = c.multimesh
			for i in mm.instance_count:
				var cd := mm.get_instance_custom_data(i)
				cd.b = mode / 10.0
				mm.set_instance_custom_data(i, cd)


## Einzelne Figur mit eigenem Material (Starterin, Fans im Ziel). kind 2: mit Leuchtstäben
static func single(parent: Node3D, kind: int, mode: int, top: Color, skin: float, hair: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh(kind)
	var m := material()
	m.set_shader_parameter("custom", Color(skin, hair, mode / 10.0, randf()))
	m.set_shader_parameter("shirt", Vector3(top.r, top.g, top.b))
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi
