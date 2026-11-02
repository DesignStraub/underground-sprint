extends RefCounted
## Leute: Blockfiguren (Beine, Rumpf, Arme, Kopf, Haare), bewegt vom Shader. Gruppen als MultiMesh,
## einzelne Figuren (Starterin) als MeshInstance mit eigenen Werten.

const SHADER := preload("res://shaders/people.gdshader")

enum { CHEER, DANCE, WAIT, WAVE, CLAP, RUN, PHONE, STARTER }

const SHIRTS := [Color(0.85, 0.1, 0.12), Color(0.1, 0.35, 0.85), Color(0.95, 0.8, 0.1), Color(0.92, 0.92, 0.92),
	Color(0.08, 0.08, 0.09), Color(0.2, 0.75, 0.35), Color(0.95, 0.45, 0.1), Color(0.6, 0.2, 0.75),
	Color(1.0, 0.3, 0.6), Color(0.1, 0.8, 0.9)]

## 0 kurze Haare, 1 lange Haare, 2 Starterin (lange Haare, Leuchtstäbe in den Händen)
static var _meshes := {}


static func mesh(kind: int) -> ArrayMesh:
	if _meshes.has(kind):
		return _meshes[kind]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Beine mit Schuhen
	for s in [-1.0, 1.0]:
		var leg := 3 if s < 0.0 else 4
		_box(st, Vector3(s * 0.09, 0.47, 0.0), Vector3(0.14, 0.74, 0.16), leg, 1)
		_box(st, Vector3(s * 0.09, 0.05, -0.03), Vector3(0.15, 0.1, 0.25), leg, 4)
	# Rumpf (oben breiter), Hals
	_box(st, Vector3(0, 0.98, 0), Vector3(0.32, 0.3, 0.2), 0, 0)
	_box(st, Vector3(0, 1.26, 0), Vector3(0.42, 0.28, 0.22), 0, 0)
	_box(st, Vector3(0, 1.44, 0), Vector3(0.1, 0.08, 0.1), 0, 2)
	# Arme: Ärmel, Unterarm, Hand
	for s in [-1.0, 1.0]:
		var a := 1 if s < 0.0 else 2
		_box(st, Vector3(s * 0.26, 1.25, 0), Vector3(0.11, 0.3, 0.12), a, 0)
		_box(st, Vector3(s * 0.26, 0.98, 0), Vector3(0.09, 0.26, 0.1), a, 2)
		if kind == 2:
			_box(st, Vector3(s * 0.26, 0.76, -0.02), Vector3(0.05, 0.22, 0.05), a, 5)
	# Kopf, Haare
	_box(st, Vector3(0, 1.6, 0), Vector3(0.2, 0.24, 0.22), 5, 2)
	_box(st, Vector3(0, 1.74, 0.02), Vector3(0.22, 0.07, 0.25), 5, 3)
	_box(st, Vector3(0, 1.64, 0.1), Vector3(0.22, 0.18, 0.06), 5, 3)
	if kind >= 1:
		_box(st, Vector3(0, 1.42, 0.13), Vector3(0.24, 0.36, 0.06), 5, 3)
	var m := st.commit()
	_meshes[kind] = m
	return m


## Quader mit Teil- und Farbkennung im UV
static func _box(st: SurfaceTool, c: Vector3, size: Vector3, part: int, grp: int) -> void:
	var h := size / 2.0
	var uv := Vector2(part, grp)
	# je Seite: Normale und vier Ecken; Dreiecke 0-2-1 / 0-3-2 laufen von außen gesehen im Uhrzeigersinn
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
		for i in [0, 2, 1, 0, 3, 2]:
			st.set_normal(f[0])
			st.set_uv(uv)
			st.add_vertex(c + (q[i] as Vector3) * h)


static func material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	return m


## Gruppe aus Figuren an den Transformationen xfs (Blick = lokales -Z). modes: Liste möglicher Bewegungen.
## Liefert einen Knoten mit zwei MultiMeshes (kurze/lange Haare); set_mode() kann später umschalten.
static func crowd(parent: Node3D, xfs: Array, modes: Array, rng: RandomNumberGenerator) -> Node3D:
	var holder := Node3D.new()
	parent.add_child(holder)
	var lists := [[], []]
	for xf in xfs:
		lists[rng.randi() % 2].append(xf)
	var mat := material()
	for k in 2:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mesh(k)
		mm.instance_count = lists[k].size()
		for i in lists[k].size():
			var xf: Transform3D = lists[k][i]
			var s := rng.randf_range(0.9, 1.08)
			mm.set_instance_transform(i, Transform3D(xf.basis.scaled(Vector3(s, s, s)), xf.origin))
			mm.set_instance_color(i, SHIRTS[rng.randi() % SHIRTS.size()])
			mm.set_instance_custom_data(i, Color(rng.randf(), rng.randf(), modes[rng.randi() % modes.size()] / 10.0, rng.randf()))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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


## Einzelne Figur mit eigenem Material (Starterin, Fans im Ziel)
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
