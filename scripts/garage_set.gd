extends RefCounted
## Garage mit Rollenprüfstand (seit 2.38, für garage.gd): eine Werkstatthalle statt des Fotostudios mit Drehteller. Das
## Auto steht in der Mitte und fährt auf der Stelle. Seit 2.39 sieht man kein Laufband mehr: es liegt bündig im Boden,
## läuft von Tor zu Tor unter beiden Toren durch und sieht aus wie der Beton daneben (garage_floor.gdshader), ohne
## Rahmen, Anfang oder Ende; seine Ränder sind Plattenfugen wie alle anderen, weiter außen markieren zwei weiße Linien
## die Fahrspur durch die Halle.
## Rundherum eine Rückwand aus gestrichenen Steinen mit Lochwand, Werkbank, Werkzeugwagen und Reifenregal, an beiden
## Stirnseiten ein offenes Rolltor (dort fahren die Autos herein und hinaus), vor dem Auto ein Kühlgebläse wie an
## echten Prüfständen. Das Auto steht mit der Front nach +Z (garage.gd dreht den Stellplatz), die Kamera auf der Seite
## +X, die Werkzeugwand dahinter bei -X.
## Sparsam: alles Feste ist je Material zu einem Mesh verschmolzen, Kleinteile tragen ihre Farbe als Vertexfarbe, nichts
## davon wirft Schatten. Zusammen rund zehn Draw Calls.

const Builder := preload("res://scripts/car_builder.gd")
const FLOOR_SHADER := preload("res://shaders/garage_floor.gdshader")
const WALL_SHADER := preload("res://shaders/garage_wall.gdshader")

const LANE_HALF := 1.4  # halbe Breite des Laufbands im Boden (es reicht von Tor zu Tor und weiter)
const BACK_X := -6.5  # Rückwand (Innenseite)
const END_Z := 9.5  # Stirnwände (Innenseite), darin die Tore
const DOOR := Vector2(4.4, 3.6)  # Torbreite, Torhöhe
const FAN_POS := Vector3(-2.05, 0.0, 4.75)  # Kühlgebläse vor dem Auto, von der Kamera aus dahinter, bläst auf die Front


## Baut die Halle in parent. Rückgabe: belt (Material des Bodens, darin das Band: offset, blur), rotor (Flügelrad des
## Gebläses, dreht um seine z-Achse), glints (zwei Lichter, die nur das Auto treffen: wandernde Spiegelungen beim Fahren)
static func build(parent: Node) -> Dictionary:
	var out := {}
	var off := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Boden: Beton mit Plattenfugen, in der Mitte das Band (das Muster darauf wandert im Shader), weiße Linien der
	# Fahrspur. Bis 2.38 lag das Band als eigene Fläche mit Stahlrahmen, Randstrichen und schraffierten Auffahrten auf
	# dem Boden: man sah Anfang und Ende.
	var fm := ShaderMaterial.new()
	fm.shader = FLOOR_SHADER
	fm.set_shader_parameter("lane_half", LANE_HALF)
	fm.set_shader_parameter("line_x", 2.3)
	var pm := PlaneMesh.new()
	pm.size = Vector2(34, 34)
	_mi(parent, pm, fm, Vector3.ZERO).cast_shadow = off  # unter ihm liegt nichts, das er beschatten könnte
	out["belt"] = fm

	# Rolltore: Führungsschienen links und rechts, aufgerollter Panzer oben
	var steel := Builder.mat(Color(0.36, 0.37, 0.39), 0.8, 0.36)
	var parts := []
	for s in [-1.0, 1.0]:
		for side in [-1.0, 1.0]:
			parts.append([Builder.box(Vector3(0.14, DOOR.y, 0.16)), Transform3D(Basis(), Vector3(side * (DOOR.x / 2.0 + 0.07), DOOR.y / 2.0, s * (END_Z - 0.1)))])
		var drum := CylinderMesh.new()
		drum.top_radius = 0.34
		drum.bottom_radius = 0.34
		drum.height = DOOR.x + 0.5
		drum.radial_segments = 20
		drum.rings = 1
		parts.append([drum, Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(0, DOOR.y + 0.36, s * (END_Z - 0.4)))])
	var sm := _mi(parent, _merged(parts), steel, Vector3.ZERO)
	sm.cast_shadow = off

	# Wände: Rückwand und zwei Stirnwände mit Toröffnung (Steine, Sockel, Lochwand im Shader)
	var wm := ShaderMaterial.new()
	wm.shader = WALL_SHADER
	wm.set_shader_parameter("board_x", BACK_X)
	wm.set_shader_parameter("board", Vector4(-3.7, 1.05, 0.5, 2.45))
	var wh := 6.5
	var w := []
	w.append([Builder.box(Vector3(0.3, wh, END_Z * 2.0 + 0.6)), Transform3D(Basis(), Vector3(BACK_X - 0.15, wh / 2.0, 0))])
	var far_x := 11.0
	for s in [-1.0, 1.0]:
		var zc: float = s * (END_Z + 0.15)
		var lw := DOOR.x / 2.0 - BACK_X
		w.append([Builder.box(Vector3(lw, wh, 0.3)), Transform3D(Basis(), Vector3(BACK_X + lw / 2.0, wh / 2.0, zc))])
		var rw := far_x - DOOR.x / 2.0
		w.append([Builder.box(Vector3(rw, wh, 0.3)), Transform3D(Basis(), Vector3(DOOR.x / 2.0 + rw / 2.0, wh / 2.0, zc))])
		w.append([Builder.box(Vector3(DOOR.x, wh - DOOR.y, 0.3)), Transform3D(Basis(), Vector3(0, DOOR.y + (wh - DOOR.y) / 2.0, zc))])
	var wmi := _mi(parent, _merged(w), wm, Vector3.ZERO)
	wmi.cast_shadow = off

	# Kleinteile mit Vertexfarben: Werkbank, Werkzeug, Werkzeugwagen, Reifenregal, Regal, Lampengehäuse, Gebläse
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_props(st)
	_fan_body(st)
	var props := StandardMaterial3D.new()
	props.vertex_color_use_as_albedo = true
	props.vertex_color_is_srgb = true
	props.metallic = 0.3
	props.roughness = 0.55
	var pmi := _mi(parent, st.commit(), props, Vector3.ZERO)
	pmi.cast_shadow = off

	# Flügelrad des Gebläses (dreht sich, garage.gd)
	var fan := Node3D.new()
	fan.position = FAN_POS + Vector3(0, 0.66, 0)
	fan.rotation.y = _fan_yaw()
	parent.add_child(fan)
	var rt := SurfaceTool.new()
	rt.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 5:
		var a := TAU * k / 5.0
		var b := Basis(Vector3.BACK, a) * Basis(Vector3.UP, deg_to_rad(28.0))
		_cbox(rt, Transform3D(b, Basis(Vector3.BACK, a) * Vector3(0, 0.2, 0)), Vector3(0.11, 0.3, 0.012), Color(0.55, 0.56, 0.58))
	_ccyl(rt, Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(0, 0, 0.02)), 0.075, 0.12, Color(0.16, 0.16, 0.17), 14)
	var rotor := _mi(fan, rt.commit(), props, Vector3.ZERO)
	rotor.cast_shadow = off
	out["rotor"] = rotor

	# Leuchtstoffröhren an der Rückwand (hell, ohne eigenes Licht: das gibt der Wandstrahler)
	var lamp := StandardMaterial3D.new()
	lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lamp.albedo_color = Color(1.0, 0.97, 0.9) * 1.25
	var tubes := []
	for z in [-5.2, 0.0, 5.2]:
		tubes.append([Builder.box(Vector3(0.05, 0.045, 1.5)), Transform3D(Basis(), Vector3(BACK_X + 0.09, 3.5, z))])
	var lmi := _mi(parent, _merged(tubes), lamp, Vector3.ZERO)
	lmi.cast_shadow = off

	# Wandernde Spiegelungen: zwei Lichter, die nur das Auto treffen (Ebene der Autos), fast nur Glanz, kaum Fläche
	var glints: Array[OmniLight3D] = []
	for k in 2:
		var gl := OmniLight3D.new()
		gl.light_cull_mask = Builder.CAR_LAYER
		gl.light_color = Color(1.0, 0.97, 0.92)
		gl.light_energy = 0.0
		gl.light_specular = 3.0
		gl.omni_range = 4.0
		gl.omni_attenuation = 1.5
		parent.add_child(gl)
		glints.append(gl)
	out["glints"] = glints
	return out


## Gebläse schaut auf die Front des Autos
static func _fan_yaw() -> float:
	var to := Vector3(0, 0, 2.2) - FAN_POS
	return atan2(to.x, to.z)


## Ständer, Gehäusering und Gitter des Gebläses (fest, in den Kleinteilen)
static func _fan_body(st: SurfaceTool) -> void:
	var xf := Transform3D(Basis(Vector3.UP, _fan_yaw()), FAN_POS)
	var steel := Color(0.34, 0.35, 0.37)
	var dark := Color(0.07, 0.07, 0.075)
	var c := Vector3(0, 0.66, 0)
	_ctorus(st, xf * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), c), 0.5, 0.045, Color(0.12, 0.13, 0.14), 28, 6)
	_ctorus(st, xf * Transform3D(Basis(Vector3.RIGHT, PI / 2.0), c + Vector3(0, 0, 0.07)), 0.27, 0.008, steel, 20, 4)
	for a in [0.0, PI / 2.0]:
		_cbox(st, xf * Transform3D(Basis(Vector3.BACK, a), c + Vector3(0, 0, 0.07)), Vector3(1.0, 0.012, 0.012), steel)
	for s in [-1.0, 1.0]:
		_cbox(st, xf * Transform3D(Basis(Vector3.BACK, s * 0.12), Vector3(s * 0.5, 0.36, 0)), Vector3(0.05, 0.62, 0.05), dark)
	_cbox(st, xf * Transform3D(Basis(), Vector3(0, 0.025, 0)), Vector3(1.2, 0.05, 0.42), dark)


## Werkbank mit Lochwand darüber, Werkzeugwagen, Reifenregal, Wandregal, Gehäuse der Röhren
static func _props(st: SurfaceTool) -> void:
	var bx := BACK_X
	var steel := Color(0.3, 0.31, 0.33)
	var dark := Color(0.06, 0.06, 0.065)
	var wood := Color(0.3, 0.21, 0.13)
	var chrome := Color(0.66, 0.67, 0.7)
	var red := Color(0.5, 0.055, 0.045)
	var rubber := Color(0.04, 0.04, 0.043)
	var I := Basis()
	# Werkbank unter der Lochwand (z -3.6 … 0.4)
	var zc := -1.6
	_cbox(st, Transform3D(I, Vector3(bx + 0.36, 0.895, zc)), Vector3(0.7, 0.05, 4.0), wood)
	_cbox(st, Transform3D(I, Vector3(bx + 0.36, 0.22, zc)), Vector3(0.62, 0.03, 3.9), steel)
	for lx in [0.06, 0.64]:
		for lz in [-1.94, 1.94]:
			_cbox(st, Transform3D(I, Vector3(bx + lx, 0.435, zc + lz)), Vector3(0.05, 0.87, 0.05), steel)
	# Schraubstock, Werkzeugkiste, Dosen, Kisten im Fach
	_cbox(st, Transform3D(I, Vector3(bx + 0.5, 0.95, zc - 1.55)), Vector3(0.2, 0.06, 0.26), Color(0.12, 0.17, 0.24))
	_cbox(st, Transform3D(I, Vector3(bx + 0.5, 1.03, zc - 1.55)), Vector3(0.12, 0.11, 0.22), Color(0.12, 0.17, 0.24))
	_cbox(st, Transform3D(I, Vector3(bx + 0.33, 1.02, zc + 1.25)), Vector3(0.3, 0.2, 0.55), red)
	_cbox(st, Transform3D(I, Vector3(bx + 0.33, 1.13, zc + 1.25)), Vector3(0.12, 0.02, 0.3), chrome)
	for k in 3:
		_ccyl(st, Transform3D(I, Vector3(bx + 0.25, 1.0, zc + 0.2 + k * 0.13)), 0.045, 0.16, [Color(0.6, 0.45, 0.06), Color(0.1, 0.22, 0.5), Color(0.45, 0.07, 0.05)][k], 10)
	_cbox(st, Transform3D(I, Vector3(bx + 0.36, 0.36, zc - 0.9)), Vector3(0.5, 0.25, 0.6), Color(0.14, 0.15, 0.17))
	_cbox(st, Transform3D(I, Vector3(bx + 0.36, 0.33, zc + 0.6)), Vector3(0.5, 0.2, 0.5), Color(0.28, 0.2, 0.12))
	# Werkzeug an der Lochwand: Schlüssel nach Größe, Schraubendreher, Hammer, ein Zettel
	var tx := bx + 0.025
	for k in 9:
		var ln := 0.14 + k * 0.024
		var z := -3.45 + k * 0.065
		_cbox(st, Transform3D(I, Vector3(tx, 2.3 - ln / 2.0, z)), Vector3(0.012, ln, 0.024 + k * 0.002), chrome)
		_cbox(st, Transform3D(I, Vector3(tx, 2.3, z)), Vector3(0.012, 0.035, 0.045 + k * 0.003), chrome)
	for k in 5:
		var z := -2.65 + k * 0.075
		_ccyl(st, Transform3D(I, Vector3(tx + 0.01, 2.22, z)), 0.016, 0.1, [red, Color(0.75, 0.6, 0.08), Color(0.1, 0.3, 0.65), red, Color(0.08, 0.4, 0.15)][k], 8)
		_cbox(st, Transform3D(I, Vector3(tx + 0.01, 2.09, z)), Vector3(0.007, 0.16, 0.007), chrome)
	_cbox(st, Transform3D(I, Vector3(tx, 1.75, -2.1)), Vector3(0.014, 0.32, 0.03), wood)
	_cbox(st, Transform3D(I, Vector3(tx + 0.01, 1.92, -2.1)), Vector3(0.035, 0.045, 0.13), dark)
	for k in 2:
		_cbox(st, Transform3D(Basis(Vector3.RIGHT, 0.18 * (k * 2 - 1)), Vector3(tx, 1.7, -1.55 + k * 0.05)), Vector3(0.012, 0.26, 0.018), Color(0.6, 0.1, 0.08))
	_cbox(st, Transform3D(I, Vector3(tx + 0.005, 1.95, -0.3)), Vector3(0.004, 0.3, 0.21), Color(0.72, 0.72, 0.68))
	_cbox(st, Transform3D(I, Vector3(tx, 1.55, -0.95)), Vector3(0.02, 0.03, 0.6), steel)
	for k in 7:
		_ccyl(st, Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(tx + 0.03, 1.55, -1.2 + k * 0.08)), 0.014 + k * 0.002, 0.05, chrome, 8)
	# Wandregal oben (Kartons, Ölkanister)
	_cbox(st, Transform3D(I, Vector3(bx + 0.18, 2.78, zc)), Vector3(0.36, 0.03, 4.2), steel)
	for k in 6:
		var z := zc - 1.8 + k * 0.68
		if k % 2 == 0:
			_cbox(st, Transform3D(I, Vector3(bx + 0.18, 2.94, z)), Vector3(0.3, 0.3, 0.42), Color(0.3, 0.22, 0.13))
		else:
			_ccyl(st, Transform3D(I, Vector3(bx + 0.18, 2.93, z)), 0.11, 0.28, [Color(0.5, 0.06, 0.05), Color(0.1, 0.2, 0.45), Color(0.62, 0.5, 0.08)][k / 2], 12)
	# Werkzeugwagen (rot, Schubladen mit Griffen) neben der Werkbank
	var cz := 1.45
	var cx := bx + 0.3
	_cbox(st, Transform3D(I, Vector3(cx, 0.58, cz)), Vector3(0.56, 0.86, 1.1), red)
	_cbox(st, Transform3D(I, Vector3(cx - 0.02, 1.22, cz)), Vector3(0.5, 0.38, 1.04), red)
	_cbox(st, Transform3D(I, Vector3(cx - 0.02, 1.425, cz)), Vector3(0.52, 0.03, 1.06), dark)
	_cbox(st, Transform3D(I, Vector3(cx, 1.005, cz)), Vector3(0.58, 0.02, 1.12), dark)
	for y in [0.3, 0.44, 0.58, 0.72, 0.86, 1.11, 1.27]:
		_cbox(st, Transform3D(I, Vector3(cx + 0.28 - (0.02 if y > 1.0 else 0.0), y, cz)), Vector3(0.006, 0.008, 1.02), dark)
		_cbox(st, Transform3D(I, Vector3(cx + 0.29 - (0.02 if y > 1.0 else 0.0), y - 0.035, cz)), Vector3(0.016, 0.012, 0.7), chrome)
	for lz in [-0.48, 0.48]:
		for lx in [-0.2, 0.2]:
			_ccyl(st, Transform3D(Basis(Vector3.BACK, PI / 2.0), Vector3(cx + lx, 0.075, cz + lz)), 0.06, 0.04, dark, 10)
	_cbox(st, Transform3D(I, Vector3(cx + 0.31, 0.9, cz + 0.6)), Vector3(0.02, 0.02, 0.1), chrome)
	# Reifenregal: zwei Ebenen mit stehenden Reifen
	var rz0 := 3.0
	var rz1 := 5.9
	for y in [0.42, 1.36]:
		for dx in [0.15, 0.55]:
			_cbox(st, Transform3D(I, Vector3(bx + dx, y, (rz0 + rz1) / 2.0)), Vector3(0.04, 0.04, rz1 - rz0), steel)
	for z in [rz0, (rz0 + rz1) / 2.0, rz1]:
		for dx in [0.15, 0.55]:
			_cbox(st, Transform3D(I, Vector3(bx + dx, 1.0, z)), Vector3(0.04, 2.0, 0.04), steel)
	for row in 2:
		var y: float = [0.42, 1.36][row] + 0.33
		for k in 9:
			var z := rz0 + 0.22 + k * 0.305
			var r := 0.31 - 0.015 * ((k + row) % 3)
			_ccyl(st, Transform3D(Basis(Vector3.RIGHT, PI / 2.0), Vector3(bx + 0.35, y - 0.31 + r, z)), r, 0.22, rubber, 18)
	# Gehäuse der Röhren
	for z in [-5.2, 0.0, 5.2]:
		_cbox(st, Transform3D(I, Vector3(bx + 0.05, 3.53, z)), Vector3(0.1, 0.06, 1.6), dark)


static func _mi(parent: Node, mesh: Mesh, m: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


## Grundkörper zu einem Mesh verschmelzen: [[Mesh, Transform3D], …] (alle mit demselben Material)
static func _merged(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for p in parts:
		st.append_from(p[0], 0, p[1])
	return st.commit()


## Quader mit Vertexfarbe (Mitte und Lage in xf, Größe s), Vorderseiten im Uhrzeigersinn
static func _cbox(st: SurfaceTool, xf: Transform3D, s: Vector3, col: Color) -> void:
	var h := s / 2.0
	var faces := [[Vector3.RIGHT, Vector3.UP, Vector3.BACK, h.x, h.y, h.z], [Vector3.LEFT, Vector3.BACK, Vector3.UP, h.x, h.z, h.y],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT, h.y, h.z, h.x], [Vector3.DOWN, Vector3.RIGHT, Vector3.BACK, h.y, h.x, h.z],
		[Vector3.BACK, Vector3.RIGHT, Vector3.UP, h.z, h.x, h.y], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT, h.z, h.y, h.x]]
	for f in faces:
		var n: Vector3 = f[0]
		var a: Vector3 = f[1] * f[4]
		var b: Vector3 = f[2] * f[5]
		var c: Vector3 = n * f[3]
		var p := [c - a - b, c + a - b, c + a + b, c - a + b]
		var nw := (xf.basis * n).normalized()
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_color(col)
			st.set_normal(nw)
			st.add_vertex(xf * (p[i] as Vector3))


## Zylinder entlang der lokalen y-Achse (Radius r, Höhe h) mit Deckeln
static func _ccyl(st: SurfaceTool, xf: Transform3D, r: float, h: float, col: Color, seg: int) -> void:
	for i in seg:
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var q := [d0 * r + Vector3(0, -h / 2.0, 0), d1 * r + Vector3(0, -h / 2.0, 0), d1 * r + Vector3(0, h / 2.0, 0), d0 * r + Vector3(0, h / 2.0, 0)]
		var nn := [d0, d1, d1, d0]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.set_normal((xf.basis * (nn[k] as Vector3)).normalized())
			st.add_vertex(xf * (q[k] as Vector3))
		for cap in [-1.0, 1.0]:
			var y: float = cap * h / 2.0
			var tri := [Vector3(0, y, 0), d0 * r + Vector3(0, y, 0), d1 * r + Vector3(0, y, 0)]
			var order := [0, 1, 2] if cap > 0.0 else [0, 2, 1]
			for k in order:
				st.set_color(col)
				st.set_normal((xf.basis * Vector3(0, cap, 0)).normalized())
				st.add_vertex(xf * (tri[k] as Vector3))


## Ring um die lokale y-Achse (Radius R, Rohr r)
static func _ctorus(st: SurfaceTool, xf: Transform3D, R: float, r: float, col: Color, seg: int, rings: int) -> void:
	for i in seg:
		for j in rings:
			var pts := []
			var nrm := []
			for e in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
				var a: float = TAU * float(e[0]) / seg
				var b: float = TAU * float(e[1]) / rings
				var d := Vector3(cos(a), 0, sin(a))
				var n := d * cos(b) + Vector3(0, sin(b), 0)
				pts.append(d * R + n * r)
				nrm.append(n)
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_color(col)
				st.set_normal((xf.basis * (nrm[k] as Vector3)).normalized())
				st.add_vertex(xf * (pts[k] as Vector3))
