extends Node3D
## Werkzeug: rendert alle Autos schräg von vorn und schräg von hinten (Karosserie, Radkästen, Neon prüfen).
##   Godot --path . res://tools/car_shots.tscn -- --out=/pfad/prefix [--cars=kaizen,hachi] [--stock] (ab Werk, ohne Tuning)

const Catalog := preload("res://scripts/catalog.gd")
const Builder := preload("res://scripts/car_builder.gd")

var out := "/tmp/car"
var cars: Array = Catalog.CAR_ORDER
var stock := false
var lights := false  # --lights: mit Scheinwerfern und Lichtteppichen auf dem Boden
var cfgs: Array = []  # --cfgs: je Eintrag ein Bild je Ansicht, Dateiname mit laufender Nummer
var views: Array = []
var spin_v := 0.0  # --spin=m/s: Räder vor dem Bild so lange drehen lassen (Unschärfe testen)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--cars="):
			cars = Array(a.substr(7).split(","))
		elif a == "--stock":
			stock = true
		elif a == "--lights":
			lights = true
		elif a.begins_with("--cfgs="):
			# mehrere Ausstattungen nacheinander: "rims:4,spoiler:5;rims:5" (fehlende Kategorien = Serie)
			for one in a.substr(7).split(";"):
				var c := {}
				for kv in one.split(","):
					if ":" in kv:
						c[kv.get_slice(":", 0)] = int(kv.get_slice(":", 1))
				cfgs.append(c)
		elif a.begins_with("--spin="):
			spin_v = float(a.substr(7))
		elif a.begins_with("--views="):
			views = Array(a.substr(8).split(","))
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
	if stock:
		cfg = {}
		for cat in Catalog.PART_ORDER:
			cfg[cat] = 0
	var all_views := [["vorn", Vector3(4.2, 1.6, -5.2)], ["hinten", Vector3(-4.0, 1.5, 5.4)], ["seite", Vector3(8.5, 0.8, 0.0)],
		["jagd", Vector3(0.0, 1.75, 6.2)], ["front", Vector3(0.0, 1.2, -6.0)], ["rad", Vector3(2.6, 0.5, -2.6)], ["felge", Vector3.ZERO], ["oben", Vector3(3.0, 4.2, -4.4)],
		["heck", Vector3.ZERO], ["bug", Vector3.ZERO], ["hoch", Vector3(0.5, 18.0, -2.0)]]
	if cfgs.is_empty():
		cfgs = [cfg]
	for id in cars:
		for ci in cfgs.size():
			var car := Builder.build(id, cfgs[ci], lights)
			add_child(car)
			for view in all_views:
				if (views.is_empty() and view[0] in ["rad", "felge", "oben", "heck", "bug"]) or (not views.is_empty() and not view[0] in views):
					continue
				cam.position = view[1]
				cam.fov = 32.0
				var look := Vector3(0, 0.55, 0)
				var Lh: float = Catalog.CARS[id]["length"] / 2.0
				if view[0] == "heck":
					look = Vector3(0, 0.42, Lh - 0.3)
					cam.position = Vector3(-1.9, 1.05, Lh + 2.9)
				elif view[0] == "bug":
					look = Vector3(0, 0.45, -Lh + 0.5)
					cam.position = Vector3(2.0, 1.3, -Lh - 2.9)
				if view[0] == "felge":
					# Felge fast von der Seite, nah
					var Sf: Dictionary = Builder.SHAPES.get(id, {})
					look = Vector3(Catalog.CARS[id]["width"] / 2.0 - 0.1, Builder.wheel_r(Sf), -Lh + Builder.axle(Sf))
					cam.position = look + Vector3(1.05, 0.08, -0.32)
					cam.fov = 30.0
				if view[0] == "rad":
					# vorderes rechtes Rad, schräg von vorn
					var Sh: Dictionary = Builder.SHAPES.get(id, {})
					look = Vector3(Catalog.CARS[id]["width"] / 2.0 - 0.1, Builder.wheel_r(Sh), -Lh + Builder.axle(Sh))
					cam.position = look + Vector3(1.25, 0.12, -0.55)
				cam.look_at(look)
				for i in 8:
					if spin_v != 0.0:
						Builder.animate(car, spin_v, 0.0, 0.0, 0.0, false, 1.0 / 60.0)
					await RenderingServer.frame_post_draw
				var tag: String = id if cfgs.size() == 1 else "%s_%02d" % [id, ci]
				get_viewport().get_texture().get_image().save_png("%s_%s_%s.png" % [out, tag, view[0]])
			car.queue_free()
			await get_tree().process_frame
	get_tree().quit()
