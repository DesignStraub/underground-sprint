extends Node3D
## Werkzeug: alle Verkehrsfahrzeuge (traffic_models.gd, seit 2.41) nebeneinander, schräg von vorn und von hinten.
##   Godot --path . res://tools/traffic_shots.tscn -- --out=/pfad/prefix

const Traffic := preload("res://scripts/traffic_car.gd")
const Models := preload("res://scripts/traffic_models.gd")
const Builder := preload("res://scripts/car_builder.gd")


func _ready() -> void:
	var out := "/tmp/verkehr"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.65, 0.78)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 30, 0)
	sun.light_energy = 1.3
	add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(120, 60)
	fl.mesh = pm
	fl.material_override = Builder.mat(Color(0.18, 0.18, 0.2), 0.0, 0.8)
	add_child(fl)
	var plan := [["sedan", "limousine", Color(0.45, 0.1, 0.1)], ["sedan", "kombi", Color(0.25, 0.3, 0.4)],
		["sedan", "kleinwagen", Color(0.7, 0.7, 0.68)], ["sedan", "suv", Color(0.15, 0.15, 0.17)],
		["taxi", "limousine", Models.TAXI_IVORY], ["van", "", Color(0.85, 0.85, 0.85)], ["bus", "", Color(0.9, 0.85, 0.1)],
		["lkw", "", Color(0.08, 0.2, 0.55)]]
	var x := 0.0
	for it in plan:
		var t: Node3D = Traffic.new()
		t.kind = it[0]
		t.form = it[1]
		t._model(it[2])
		var w := 3.2 if it[0] in ["bus", "lkw"] else 2.6
		x += w / 2.0
		t.position = Vector3(x, 0, 0)
		t.process_mode = Node.PROCESS_MODE_DISABLED  # kein Fahren ohne Strecke
		add_child(t)
		x += w / 2.0 + 0.6
	var cam := Camera3D.new()
	cam.fov = 30.0
	add_child(cam)
	cam.make_current()
	var mid := x / 2.0
	# vorn (-Z): ganze Reihe, hinten (+Z): ganze Reihe, nah: die ersten drei Pkw schräg von vorn
	for v in [["vorn", Vector3(mid - 10.0, 7.0, -34.0), Vector3(mid, 1.2, -3.0)], ["hinten", Vector3(mid + 10.0, 7.0, 36.0), Vector3(mid, 1.2, 3.0)],
			["nah", Vector3(-3.0, 2.4, -9.0), Vector3(3.6, 0.9, -1.0)], ["seite", Vector3(mid, 3.0, -1.0) + Vector3(0, 0, 0), Vector3(mid, 1.0, 0)]]:
		if v[0] == "seite":
			continue
		cam.position = v[1]
		cam.look_at(v[2], Vector3.UP)
		for i in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [out, v[0]])
	get_tree().quit()
