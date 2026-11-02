extends Node3D
## Werkzeug: rendert alle Autos schräg von vorn und schräg von hinten (Karosserie, Radkästen, Neon prüfen).
##   Godot --path . res://tools/car_shots.tscn -- --out=/pfad/prefix

const Catalog := preload("res://scripts/catalog.gd")
const Builder := preload("res://scripts/car_builder.gd")

var out := "/tmp/car"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.08, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.6)
	env.ambient_light_energy = 0.6
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 35, 0)
	sun.light_energy = 1.2
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	floor_mi.material_override = Builder.mat(Color(0.12, 0.12, 0.14), 0.0, 0.5)
	add_child(floor_mi)
	var cam := Camera3D.new()
	cam.fov = 32.0
	add_child(cam)
	cam.make_current()
	var cfg := {"paint": 5, "rims": 2, "spoiler": 2, "bodykit": 1, "vinyl": 0, "neon": 2, "engine": 0, "nitro": 0}
	for id in Catalog.CAR_ORDER:
		var car := Builder.build(id, cfg, false)
		add_child(car)
		for view in [["vorn", Vector3(4.2, 1.6, -5.2)], ["hinten", Vector3(-4.0, 1.5, 5.4)], ["seite", Vector3(8.5, 0.8, 0.0)]]:
			cam.position = view[1]
			cam.look_at(Vector3(0, 0.55, 0))
			for i in 8:
				await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s_%s_%s.png" % [out, id, view[0]])
		car.queue_free()
		await get_tree().process_frame
	get_tree().quit()
