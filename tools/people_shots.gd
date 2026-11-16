extends Node3D
## Werkzeug: Leute aus people.gd im Überblick (alle Bewegungen, viele Kleidungs-Varianten), nah und als Blockfigur.
##   Godot --path . res://tools/people_shots.tscn -- --out=/pfad/prefix [--t=1.3] [--far] [--night] [--save=test]
##   --far     alle Figuren als Blockfigur (Fernansicht)
##   --night   Nachtlicht: dunkle Umgebung, Straßenlaternen von oben (wie im Rennen)
##   --turn    Modellblatt: dieselben Figuren von vorn, schräg, seitlich und hinten (out_turn.png)
##   --starter Starterin allein: Arme unten, halb, oben, beim GO vorgebeugt (out_starter0..3.png)
##   --bench[=dicht]  Startlinie nachgestellt (Publikum auf beiden Gehwegen, Kamera hinter dem Auto), misst Bildzeit,
##             GPU-Zeit (Mittel und Median), Draw Calls und Dreiecke über 400 Bilder ("PBENCH ..."); dicht: gut 2600
##             Figuren, alle nah. Für GPU-Zeiten unter macOS mit --rendering-driver vulkan starten, den Browser-Weg
##             misst --rendering-method gl_compatibility (dort nur die Bildzeit). --shader=pfad misst einen anderen Shader.

const People := preload("res://scripts/people.gd")

var out := "/tmp/people"
var t_shot := 1.3
var far := false
var night := false
var turn := false
var bench := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--t="):
			t_shot = float(a.substr(4))
		elif a == "--far":
			far = true
		elif a == "--night":
			night = true
		elif a == "--turn":
			turn = true
		elif a == "--bench":
			bench = "start"
		elif a.begins_with("--bench="):
			bench = a.substr(8)
	var t0 := Time.get_ticks_usec()
	People.mesh(0)
	People.mesh(3)
	print("PEOPLE Bauzeit nah+fern: %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	_light(night or bench != "")
	if bench != "":
		_bench()
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	# Reihe vorn: je Bewegung eine Figur, dahinter zwei Reihen mit zufälligen Varianten
	var modes := [People.CHEER, People.DANCE, People.WAIT, People.WAVE, People.CLAP, People.RUN, People.PHONE, People.STARTER]
	var xfs := []
	var ms := []
	for row in 3:
		for i in 8:
			var face := Basis.looking_at(Vector3(0, 0, 1), Vector3.UP)
			xfs.append(Transform3D(face, Vector3((i - 3.5) * 0.85, 0, -row * 1.3)))
			ms.append(modes[i] if row == 0 else modes[rng.randi() % 7])
	if turn:
		_turn(rng)
		return
	if OS.get_cmdline_user_args().has("--starter"):
		_starter()
		return
	# crowd() würfelt Bewegungen aus der Liste: hier je Figur eine eigene Gruppe, damit die Bewegung feststeht
	for k in xfs.size():
		var h: Node3D = People.crowd(self, [xfs[k]], [ms[k]], rng)
		_force_lod(h)
	var st: MeshInstance3D = People.single(self, 2, People.STARTER, Color(0.95, 0.95, 0.97), 0.25, 0.8)
	st.position = Vector3(3.0, 0, 1.2)
	st.rotation.y = PI
	st.material_override.set_shader_parameter("arm", 2.6)
	_count()
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 1.6, 6.8), Vector3(0, 0.95, -1.0))
	cam.make_current()
	await get_tree().create_timer(t_shot).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + ".png")
	# Nahaufnahme der vorderen Reihe (Gesichter)
	cam.look_at_from_position(Vector3(-1.2, 1.55, 2.4), Vector3(-1.2, 1.3, 0.0))
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "_nah.png")
	get_tree().quit()


func _count() -> void:
	var m0: ArrayMesh = People.mesh(0)
	var m3: ArrayMesh = People.mesh(3)
	var i0 := m0.surface_get_array_index_len(0)
	var i3 := m3.surface_get_array_index_len(0)
	print("PEOPLE nah: %d Ecken, %d Dreiecke; fern: %d Ecken, %d Dreiecke" % [m0.surface_get_array_len(0),
		(i0 if i0 > 0 else m0.surface_get_array_len(0)) / 3, m3.surface_get_array_len(0), (i3 if i3 > 0 else m3.surface_get_array_len(0)) / 3])
	# je Variante (UV2.x): Ecken und Dreiecke; Variante 0 ist immer sichtbar
	var arr := m0.surface_get_arrays(0)
	var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var ev := {}
	var et := {}
	for u in uv2:
		ev[int(u.x)] = ev.get(int(u.x), 0) + 1
	for i in range(0, idx.size(), 3):
		var o := int(uv2[idx[i]].x)
		et[o] = et.get(o, 0) + 1
	var keys := ev.keys()
	keys.sort()
	print("PEOPLE je Variante: ", " ".join(keys.map(func(k): return "%d:%d/%d" % [k, ev[k], et.get(k, 0)])))


## nur nah (Standard) oder nur fern (--far) zeigen, unabhängig vom Abstand
func _force_lod(h: Node3D) -> void:
	for c in h.get_children():
		var gi := c as GeometryInstance3D
		var is_far: bool = (c as MultiMeshInstance3D).multimesh.mesh == People.mesh(3)
		gi.visibility_range_begin = 0.0
		gi.visibility_range_end = 0.0 if is_far == far else 0.001
		gi.visibility_range_end_margin = 0.0
		gi.visible = is_far == far


func _light(dark: bool) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.03, 0.06) if dark else Color(0.08, 0.08, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.34, 0.5) if dark else Color(0.5, 0.5, 0.6)
	env.ambient_light_energy = 0.35 if dark else 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	if not dark:
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-35, 25, 0)
		sun.light_energy = 1.3
		add_child(sun)
		return
	# Nacht: Mondlicht schwach, Laternen warm von oben, Leuchtreklame bläulich von der Seite
	var moon := DirectionalLight3D.new()
	moon.rotation_degrees = Vector3(-50, -30, 0)
	moon.light_energy = 0.12
	moon.light_color = Color(0.6, 0.7, 1.0)
	add_child(moon)
	for i in 6:
		for s in [-1.0, 1.0]:
			var o := OmniLight3D.new()
			o.position = Vector3(s * 4.5, 6.0, 4.0 - i * 9.0)
			o.light_color = Color(1.0, 0.82, 0.6)
			o.light_energy = 2.2
			o.omni_range = 14.0
			o.omni_attenuation = 1.2
			add_child(o)
	var neon := OmniLight3D.new()
	neon.position = Vector3(-6.0, 3.0, -2.0)
	neon.light_color = Color(0.9, 0.3, 1.0)
	neon.light_energy = 1.5
	neon.omni_range = 9.0
	add_child(neon)


## Modellblatt: sechs Figuren in Ruhe (Warten) und in Bewegung; jede dreht sich auf der Stelle, damit sie von vorn,
## schräg, seitlich und hinten zu sehen ist (out_turn0..3.png). --modes=2,0,4 wählt die Bewegungen, --seed die Figuren.
func _turn(rng: RandomNumberGenerator) -> void:
	var turns := [0.0, 0.7, PI / 2.0, PI]
	var holders := []
	var modes := [People.WAIT, People.CHEER, People.CLAP, People.PHONE, People.WAVE, People.RUN]
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--modes="):
			modes = Array(a.substr(8).split(",")).map(func(x): return int(x))
		elif a.begins_with("--seed="):
			rng.seed = int(a.substr(7))
	for i in modes.size():
		var h: Node3D = People.crowd(self, [Transform3D.IDENTITY], [modes[i]], rng)
		_force_lod(h)
		h.position = Vector3((i - (modes.size() - 1) * 0.5) * 0.95, 0, 0)
		holders.append(h)
	_count()
	var cam := Camera3D.new()
	cam.fov = 30.0
	add_child(cam)
	cam.make_current()
	cam.look_at_from_position(Vector3(0, 1.05, -6.6), Vector3(0, 0.92, 0))
	await get_tree().create_timer(t_shot).timeout
	for k in turns.size():
		for h in holders:
			(h as Node3D).rotation.y = turns[k]
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out + "_turn%d.png" % k)
	get_tree().quit()


## Starterin allein: Arme unten, halb, oben und beim Vorbeugen (GO), von vorn schräg (out_starter0..3.png)
func _starter() -> void:
	var st: MeshInstance3D = People.single(self, 2, People.STARTER, Color(0.95, 0.95, 0.97), 0.25, 0.8)
	var m: ShaderMaterial = st.material_override
	var cam := Camera3D.new()
	cam.fov = 35.0
	add_child(cam)
	cam.look_at_from_position(Vector3(1.3, 1.5, -3.2), Vector3(0, 1.05, 0))
	cam.make_current()
	await get_tree().create_timer(t_shot).timeout
	var poses := [[0.6, 0.0], [1.6, 0.0], [2.9, 0.0], [0.35, 1.0]]
	for k in poses.size():
		m.set_shader_parameter("arm", poses[k][0])
		m.set_shader_parameter("bow", poses[k][1])
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out + "_starter%d.png" % k)
	get_tree().quit()


## wie People.crowd(), aber mit fester Nah-Grenze statt der Detaildichte aus GameState (die Messung soll nicht
## vom Spielstand abhängen); gleiche Modelle, gleiches Material, gleiche Zellen
func _crowd_local(xfs: Array, modes: Array, rng: RandomNumberGenerator, near: float) -> Node3D:
	var holder := Node3D.new()
	add_child(holder)
	var mat: ShaderMaterial = People.material()
	var cells := {}
	for xf in xfs:
		var p: Vector3 = xf.origin
		var key := Vector2i(floori(p.x / People.CELL), floori(p.z / People.CELL))
		if not cells.has(key):
			cells[key] = []
		var s := rng.randf_range(0.925, 1.075)
		cells[key].append([Transform3D(xf.basis.scaled(Vector3(s, s, s)), p), People.SHIRTS[rng.randi() % People.SHIRTS.size()],
			Color(rng.randf(), rng.randf(), modes[rng.randi() % modes.size()] / 10.0, rng.randf())])
	for key in cells:
		var list: Array = cells[key]
		for lod in 2:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.use_custom_data = true
			mm.mesh = People.mesh(0 if lod == 0 else 3)
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
			holder.add_child(mmi)
	holder.set_meta("mat", mat)
	return holder


## Startlinie nachstellen und messen
func _bench() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var xfs := []
	var dense := bench == "dicht"
	var rows := 10 if dense else 3
	var z := 24.0
	var z_end := -100.0 if dense else -30.0
	while z > z_end:
		for side in [-1.0, 1.0]:
			for row in rows:
				if rng.randf() < (0.95 if dense else 0.72):
					var pos := Vector3(side * (7.0 + 1.1 + row * 1.25 + rng.randf_range(-0.2, 0.2)), 0.15, z + rng.randf_range(-0.5, 0.5))
					var look := Vector3(-side, 0, rng.randf_range(-0.4, 0.4)).normalized()
					xfs.append(Transform3D(Basis.looking_at(look, Vector3.UP), pos))
		z -= 1.6 if not dense else 0.9
	var h: Node3D = _crowd_local(xfs, [People.CHEER, People.CHEER, People.WAVE, People.CLAP], rng, 60.0)
	if dense:
		for c in h.get_children():
			var gi := c as GeometryInstance3D
			var is_far: bool = (c as MultiMeshInstance3D).multimesh.mesh == People.mesh(3)
			gi.visibility_range_begin = 0.0
			gi.visibility_range_end = 0.0
			gi.visible = not is_far
	var st: MeshInstance3D = People.single(self, 2, People.STARTER, Color(0.95, 0.95, 0.97), 0.25, 0.8)
	st.position = Vector3(-2.0, 0, -7.0)
	st.rotation.y = PI
	# --shader=pfad: anderen Shader messen (Versuche, was im Shader wie viel kostet)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shader="):
			var sh: Shader = load(a.substr(9))
			(h.get_meta("mat") as ShaderMaterial).shader = sh
			(st.material_override as ShaderMaterial).shader = sh
	# Boden, damit die Szene nicht nur aus Leuten besteht
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 200)
	ground.mesh = pm
	add_child(ground)
	var cam := Camera3D.new()
	cam.fov = 62.0
	add_child(cam)
	cam.look_at_from_position(Vector3(-2.0, 1.9, 5.4), Vector3(-2.0, 1.1, -7.0))
	cam.make_current()
	_count()
	var vp := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for i in 90:
		await get_tree().process_frame
	var n := 400
	var gpu := 0.0
	var gpus: Array[float] = []
	var draws := 0
	var prims := 0
	var t0 := Time.get_ticks_usec()
	var worst: Array[float] = []
	var last := t0
	for i in n:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst.append((now - last) / 1000.0)
		last = now
		var g := RenderingServer.viewport_get_measured_render_time_gpu(vp)
		gpu += g
		gpus.append(g)
		draws += RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		prims += RenderingServer.viewport_get_render_info(vp, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	var total := (Time.get_ticks_usec() - t0) / 1000.0
	worst.sort()
	gpus.sort()
	print("PBENCH %s figuren=%d renderer=%s frame=%.3fms med=%.3fms gpu=%.3fms gpu_med=%.3fms draws=%d tris=%dk" % [
		bench, xfs.size(), RenderingServer.get_current_rendering_method(), total / n,
		worst[n / 2], gpu / n, gpus[n / 2], draws / n, prims / n / 1000])
	if out != "/tmp/people":
		get_viewport().get_texture().get_image().save_png(out + "_bench.png")
	get_tree().quit()
