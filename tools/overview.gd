extends Node3D
## Werkzeug: Bilder einer Strecke aus erhöhter Sicht auf Tunnel, Hochbahn, Stadion, Masten und Viertel.
## godot --path . res://tools/overview.tscn -- --race=1 --out=/pfad/prefix

const Catalog := preload("res://scripts/catalog.gd")
const Track := preload("res://scripts/track_builder.gd")
const SKY_SHADER := preload("res://shaders/night_sky.gdshader")

var shots := []  # [name, cam_pos, look_at]
var cam: Camera3D
var out := "/tmp/overview"
var _i := 0
var _wait := 20


func _ready() -> void:
	var race_i := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--race="):
			race_i = int(a.substr(7))
		elif a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--wait="):
			_wait = int(a.substr(7))  # Frames vor dem ersten Bild (z. B. damit die Hochbahn fährt)
	var t := Track.build(Catalog.RACES[race_i])
	add_child(t["node"])
	var env := Environment.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.25, 0.4)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.fog_enabled = true
	env.fog_light_color = Color(0.09, 0.07, 0.16)
	env.fog_density = 0.0035
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	cam = Camera3D.new()
	cam.far = 2000.0
	cam.fov = 70.0
	add_child(cam)
	cam.make_current()

	var c: Curve3D = t["curve"]
	var at := func(d: float, lat: float, h: float) -> Vector3:
		var f := Track.frame_at(c, d)
		return f["pos"] + f["right"] * lat + Vector3(0, h, 0)
	for k in t["tunnels"].size():
		var tn: Dictionary = t["tunnels"][k]
		shots.append(["tunnel%d" % k, at.call(tn["from"] - 70.0, -4.0, 9.0), at.call(tn["from"], 0.0, 6.0)])
	for e in t["el"]:
		var s: float = e["side"]
		shots.append(["el", at.call(e["from"] + 30.0, -s * 6.0, 4.0), at.call(e["from"] + 90.0, s * 8.0, 9.0)])
		shots.append(["el_top", at.call(e["from"] + 60.0, -s * 30.0, 30.0), at.call(e["from"] + 120.0, s * 8.0, 8.0)])
	if t["stadium_d"] > 0.0:
		var sd: float = t["stadium_d"]
		shots.append(["stadium", at.call(sd - 140.0, 0.0, 35.0), at.call(sd, 0.0, 10.0)])
	for k in t["posts"].size():
		var pd: float = t["posts"][k]
		shots.append(["post%d" % k, at.call(pd - 45.0, 2.0, 3.0), at.call(pd, 0.0, 6.0)])
	# Draufsicht auf die ganze Strecke
	var lo := Vector3(1e9, 0, 1e9)
	var hi := Vector3(-1e9, 0, -1e9)
	for i in 64:
		var q := c.sample_baked(t["length"] * i / 64.0)
		lo = Vector3(minf(lo.x, q.x), 0, minf(lo.z, q.z))
		hi = Vector3(maxf(hi.x, q.x), 0, maxf(hi.z, q.z))
	var mid := (lo + hi) / 2.0
	var ext := maxf(hi.x - lo.x, hi.z - lo.z)
	shots.append(["karte", mid + Vector3(0, ext * 1.25, 0.01), mid])
	var seen := {}
	var arr: Array = t["districts"]
	for i in arr.size():
		if seen.has(arr[i]) or (i + 0.5) * Track.DISTRICT_LEN > t["length"]:
			continue
		seen[arr[i]] = true
		var md := (i + 0.5) * Track.DISTRICT_LEN
		shots.append([arr[i], at.call(md - 90.0, 0.0, 28.0), at.call(md + 40.0, 0.0, 4.0)])


func _process(_dt: float) -> void:
	if _i >= shots.size():
		get_tree().quit()
		return
	var s: Array = shots[_i]
	cam.global_position = s[1]
	cam.look_at(s[2], Vector3.UP)
	_wait -= 1
	if _wait <= 0:
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [out, s[0]])
		_i += 1
		_wait = 6
