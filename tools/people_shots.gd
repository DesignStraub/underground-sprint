extends Node3D
## Werkzeug: Leute aus people.gd im Überblick (alle Bewegungen, viele Kleidungs-Varianten), nah und als Blockfigur.
##   Godot --path . res://tools/people_shots.tscn -- --out=/pfad/prefix [--t=1.3] [--far]

const People := preload("res://scripts/people.gd")

var out := "/tmp/people"
var t_shot := 1.3
var far := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--t="):
			t_shot = float(a.substr(4))
		elif a == "--far":
			far = true
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.08, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.6)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	sun.light_energy = 1.3
	add_child(sun)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	# Reihe vorn: je Bewegung eine Figur, dahinter zwei Reihen mit zufälligen Varianten
	var modes := [People.CHEER, People.DANCE, People.WAIT, People.WAVE, People.CLAP, People.RUN, People.PHONE, People.STARTER]
	var xfs := []
	var ms := []
	for row in 3:
		for i in 8:
			var face := Basis.looking_at(Vector3(0, 0, 1) if row < 3 else Vector3(1, 0, 0), Vector3.UP)
			xfs.append(Transform3D(face, Vector3((i - 3.5) * 0.85, 0, -row * 1.3)))
			ms.append(modes[i] if row == 0 else modes[rng.randi() % 7])
	# crowd() würfelt Bewegungen aus der Liste: hier je Figur eine eigene Gruppe, damit die Bewegung feststeht
	for k in xfs.size():
		var h := People.crowd(self, [xfs[k]], [ms[k]], rng)
		if far:
			for c in h.get_children():
				(c as GeometryInstance3D).visibility_range_begin = 0.0 if c.multimesh.mesh == People.mesh(3) else 999.0
				(c as GeometryInstance3D).visibility_range_end = 0.0 if c.multimesh.mesh == People.mesh(3) else 1000.0
	var st := People.single(self, 2, People.STARTER, Color(0.95, 0.95, 0.97), 0.25, 0.8)
	st.position = Vector3(3.0, 0, 1.2)
	st.rotation.y = PI
	st.material_override.set_shader_parameter("arm", 2.6)
	print("PEOPLE nah: %d Ecken, %d Dreiecke; fern: %d Ecken" % [People.mesh(0).surface_get_array_len(0), People.mesh(0).surface_get_array_index_len(0) / 3, People.mesh(3).surface_get_array_len(0)])
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
