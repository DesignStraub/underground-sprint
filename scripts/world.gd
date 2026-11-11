extends Node3D
## Open World "Mini-Deutschland" (seit 2.28): frei fahren auf dem Autobahnring und durch die Städte.
## Lage aller Strecken: world_layout.gd. Strecken in der Nähe werden nebenher gebaut (am Rechner in einem
## eigenen Thread, im Browser Schritt für Schritt), weit entfernte wieder entfernt. Das Auto fährt immer auf der
## Strecke, deren Fahrbahn ihm am nächsten ist (player.track wechselt an den Übergängen Auffahrt/Ausfahrt).
## An jedem Start steht ein Marker: hineinfahren, Enter, und das Rennen startet wie bisher mit Ladebildschirm.

const Catalog := preload("res://scripts/catalog.gd")
const Track := preload("res://scripts/track_builder.gd")
const Layout := preload("res://scripts/world_layout.gd")
const PlayerCar := preload("res://scripts/player_car.gd")
const PixelView := preload("res://scripts/pixel_view.gd")
const Moods := preload("res://scripts/moods.gd")
const UI := preload("res://scripts/ui_style.gd")
const TACHO := preload("res://scripts/tacho.gd")
const SPEED_FX := preload("res://shaders/speed_fx.gdshader")
const SKY_SHADER := preload("res://shaders/night_sky.gdshader")
const WorldMinimap := preload("res://scripts/world_minimap.gd")
const MapView := preload("res://scripts/world_map_view.gd")
const Traffic := preload("res://scripts/traffic_car.gd")

const LOAD_PAD := 700.0  # Strecke bauen, wenn man so nah am Rand ihres Umkreises ist
const DROP_PAD := 1300.0  # ... und wieder entfernen, wenn man so weit weg ist
const MARKER_R := 9.0
const BLUR_LEVEL := [0.0, 0.55, 1.0, 1.6]
const TRAFFIC_MAX := 160
const TRAFFIC_VOICES := 4
## Autobahn: Tempo je Spur (innen schnell, außen Lkw und Busse) in m/s
const AB_SPEED := {2.25: 36.0, 6.75: 30.0, 11.25: 24.0}

## Rückkehr nach einem Rennen: dort wieder einsetzen (gilt für diese Sitzung)
static var return_xf := Transform3D.IDENTITY
static var has_return := false
static var target := -1  # auf der Karte gewähltes Ziel (Rennen), gilt für diese Sitzung

var world: SubViewport
var player: CharacterBody3D
var env: Environment
var moon: DirectionalLight3D
var mood: Dictionary
var layout: Dictionary
var entries: Array = []  # {kind, race, xf, center, radius, state ("none"/"building"/"ready"), track, idx, race_index}
var active: Dictionary = {}
var _task := -1
var _task_entry: Dictionary = {}
var _job: Dictionary = {}  # Browser: laufender Bau Schritt für Schritt
var _threads := false
var _markers := {}  # race_index -> Node3D
var _near_marker := -1
var hud := {}
var minimap: Control
var map_view: Control
var _pins := {}  # race_index -> Node3D am Start (für die Minikarte, immer da)
var pause_panel: Control
var fx_mat: ShaderMaterial
var _fx_rect: ColorRect
var _nitro_fx := 0.0
var _cam_yaw_prev := 0.0
var _swing := 0.0
var _area_t := 0.0
var _area_name := ""
var _ready_done := false
var traffic: Array = []
var _tq: Array = []  # [Eintrag, Plan] wartet aufs Einsetzen (ein paar pro Bild, sonst ruckelt es beim Nachladen)
var _trng := RandomNumberGenerator.new()
var _traffic_snd_t := 0.0
var _leader_t := 0.0
var _segs: Array = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.in_world = true
	_threads = not OS.has_feature("web") and OS.get_processor_count() > 1 and not OS.get_cmdline_user_args().has("--nothreads")
	var view_layer := CanvasLayer.new()
	view_layer.layer = -1
	add_child(view_layer)
	var pv := PixelView.new()
	view_layer.add_child(pv)
	world = pv.world
	world.render_target_update_mode = SubViewport.UPDATE_DISABLED
	var cover := _cover()
	await get_tree().process_frame

	layout = Layout.build()
	for c in layout["cities"]:
		entries.append({"kind": "city", "race": c["race"], "xf": c["xf"], "center": c["center"], "radius": c["radius"],
			"state": "none", "track": {}, "race_index": c["race_index"], "start": c["start_world"], "exit": c["exit_world"]})
	for s in layout["segments"]:
		entries.append({"kind": "seg", "race": s["race"], "xf": Transform3D.IDENTITY, "center": s["center"], "radius": s["radius"],
			"state": "none", "track": {}, "race_index": -1, "seg_i": _segs.size()})
		_segs.append(entries[-1])
	_trng.seed = 4711
	Traffic.prepare_sound()
	_setup_environment()

	var spawn := _spawn_xf()
	# alles in der Nähe gleich bauen (hinter dem Ladebild)
	var near := entries.filter(func(e): return _dist(e, spawn.origin) < LOAD_PAD * 0.6)
	near.sort_custom(func(a, b): return _dist(a, spawn.origin) < _dist(b, spawn.origin))
	for i in near.size():
		cover.get_meta("label").text = tr("Welt wird gebaut … %d / %d") % [i + 1, near.size()]
		await get_tree().process_frame
		var job := Track.begin(near[i]["race"])
		job["nobatch"] = true
		while Track.step(job) < 1.0:
			pass
		_finish(near[i], job)

	var pc := PlayerCar.new()
	pc.process_mode = Node.PROCESS_MODE_PAUSABLE
	pc.track = _best_track(spawn.origin)
	world.add_child(pc)
	pc.setup(GameState.current_car, GameState.get_config(GameState.current_car))
	pc.top_speed *= GameState.pace()
	pc.accel *= 0.8 + 0.2 * GameState.pace()
	pc.place(spawn)
	pc.controls_enabled = true
	player = pc
	player.cam.make_current()
	for n in get_tree().get_nodes_in_group("ambient"):
		n.target = player
	_set_active(_entry_of(pc.track))
	while not _tq.is_empty():
		_spawn_queued(100)
	_build_hud()
	world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	Music.race_go()
	await get_tree().process_frame
	cover.queue_free()
	_ready_done = true


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## Startpunkt: nach einem Rennen am Marker, sonst am Start des ersten Rennens, Blick zur Ausfahrt (zur Autobahn)
func _spawn_xf() -> Transform3D:
	for a in OS.get_cmdline_user_args():
		# Test: --wspawn=ring:k (auf dem Ring bei Punkt k, in Fahrtrichtung) oder --wspawn=exit:i (an der Ausfahrt
		# der Stadt von Rennen i, Blick zur Autobahn)
		if a.begins_with("--wspawn="):
			var parts := a.substr(9).split(":")
			if parts[0] == "ring":
				var ring: Array = layout["ring"]
				var k := int(parts[1]) % ring.size()
				var p0: Vector3 = ring[k]
				var p1: Vector3 = ring[(k + 1) % ring.size()]
				var p0r := p0 + (p1 - p0).normalized().cross(Vector3.UP) * -4.5
				return Transform3D(Basis.looking_at(p1 - p0, Vector3.UP), p0r)
			for c in layout["cities"]:
				if c["race_index"] == int(parts[1]):
					var ex: Vector3 = c["exit_world"]
					var n := Vector3(ex.x, 0, ex.z).normalized()
					if parts[0] == "ramp":  # auf dem Ring vor der Auffahrt, Blick zur Stadt
						return Transform3D(Basis.looking_at(n, Vector3.UP), ex - n * (c["gap"] - 6.0))
					return Transform3D(Basis.looking_at(-n, Vector3.UP), ex + n * 30.0)
	if has_return:
		has_return = false
		return return_xf
	var c: Dictionary = layout["cities"][0]
	for cc in layout["cities"]:
		if cc["race_index"] == 0:
			c = cc
	var job := Track.begin(c["race"])
	var tr: Dictionary = job["track"]
	(job["root"] as Node).free()
	var xf: Transform3D = c["xf"] * Track.xform_at(tr["curve"], tr["start"] - 8.0, Track.LANES[1])
	xf.basis = xf.basis * Basis(Vector3.UP, PI)
	return xf


func _dist(e: Dictionary, p: Vector3) -> float:
	return maxf(Vector2(p.x - e["center"].x, p.z - e["center"].z).length() - e["radius"], 0.0)


func _entry_of(track: Dictionary) -> Dictionary:
	for e in entries:
		if e["track"] == track and not track.is_empty():
			return e
	return {}


# --- Nachladen ------------------------------------------------------------------

func _finish(e: Dictionary, job: Dictionary) -> void:
	var tr: Dictionary = job["track"]
	var root: Node3D = tr["node"]
	root.transform = e["xf"]
	Track.apply_lod(root, GameState.lod_ranges())
	root.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.add_child(root)
	e["track"] = tr
	e["state"] = "ready"
	if e["kind"] == "city":
		_add_marker(e)
	_plan_traffic(e)
	if player:
		for n in root.find_children("*", "", true, false):
			if n.is_in_group("ambient"):
				n.target = player


func _drop(e: Dictionary) -> void:
	if e["state"] != "ready" or e == active:
		return
	var root: Node = e["track"]["node"]
	traffic = traffic.filter(func(t): return is_instance_valid(t) and not root.is_ancestor_of(t))
	_tq = _tq.filter(func(q): return not is_same(q[0], e))
	root.queue_free()
	e["track"] = {}
	e["state"] = "none"
	if _markers.has(e["race_index"]):
		_markers[e["race_index"]].queue_free()
		_markers.erase(e["race_index"])


func _thread_build(e: Dictionary) -> void:
	var log := OS.get_cmdline_user_args().has("--worldlog")
	var t0 := Time.get_ticks_msec()
	var job := Track.begin(e["race"])
	job["nobatch"] = true
	if log:
		print("BAU start %s" % e["race"]["name"])
	var n := 0
	while Track.step(job) < 1.0:
		n += 1
		if log:
			print("BAU %s schritt %d %d ms" % [e["race"]["name"], n, Time.get_ticks_msec() - t0])
	e["job"] = job
	if log:
		print("BAU fertig %s %d ms" % [e["race"]["name"], Time.get_ticks_msec() - t0])


func _update_streaming() -> void:
	var pos := player.global_position
	# laufender Bau fertig?
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_finish(_task_entry, _task_entry["job"])
		_task_entry.erase("job")
		_task_entry = {}
	if not _job.is_empty():
		if Track.step(_job["job"]) >= 1.0:
			_finish(_job["entry"], _job["job"])
			_job = {}
		return
	if _task >= 0:
		return
	# nächste fehlende Strecke in Reichweite (die nächste zuerst)
	var best: Dictionary = {}
	var bd := 1e9
	for e in entries:
		var d := _dist(e, pos)
		if e["state"] == "ready" and d > DROP_PAD:
			_drop(e)
		elif e["state"] == "none" and d < LOAD_PAD and d < bd:
			bd = d
			best = e
	if best.is_empty():
		return
	best["state"] = "building"
	if _threads:
		_task_entry = best
		_task = WorkerThreadPool.add_task(_thread_build.bind(best), false, "Strecke bauen")
	else:
		_job = {"entry": best, "job": Track.begin(best["race"])}
		_job["job"]["nobatch"] = true


# --- Auf welcher Strecke fährt man? ------------------------------------------------

func _score(e: Dictionary, p: Vector3) -> float:
	var tr: Dictionary = e["track"]
	var lp: Vector3 = (e["xf"] as Transform3D).affine_inverse() * p
	return Track.locate(tr, lp)["score"]


func _best_track(p: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var bs := 1e9
	for e in entries:
		if e["state"] != "ready" or _dist(e, p) > 50.0:
			continue
		var s := _score(e, p)
		if s < bs:
			bs = s
			best = e
	return best["track"] if not best.is_empty() else {}


func _set_active(e: Dictionary) -> void:
	if e.is_empty():
		return
	active = e
	player.track = e["track"]
	Track.apply_street_light(e["track"])
	var name: String = "AUTOBAHN" if e["kind"] == "seg" else str(Catalog.RACES[e["race_index"]].get("town", "")).to_upper()
	if name != _area_name and hud.has("area"):
		_area_name = name
		hud["area"].text = name
		_area_t = 4.0


func _physics_process(_dt: float) -> void:
	if not _ready_done or get_tree().paused:
		return
	var p := player.global_position
	var cur := 1e9
	if not active.is_empty() and active["state"] == "ready":
		cur = _score(active, p)
	var best := {}
	var bs := cur - 0.3  # etwas Trägheit, damit es an den Nahtstellen nicht hin und her springt
	for e in entries:
		if e == active or e["state"] != "ready" or _dist(e, p) > 50.0:
			continue
		var s := _score(e, p)
		if s < bs:
			bs = s
			best = e
	if not best.is_empty():
		_set_active(best)
	_feed_traffic()


# --- Rennen-Marker -------------------------------------------------------------------

func _add_marker(e: Dictionary) -> void:
	var i: int = e["race_index"]
	var race: Dictionary = Catalog.RACES[i]
	var col: Color = UI.TYPE_COL.get(race.get("type", "sprint"), UI.CYAN)
	if not GameState.career_open(race["name"]):
		col = Color(0.45, 0.47, 0.52)  # gesperrt: grau
	elif race["name"] in GameState.won_events:
		col = col.lerp(Color(1.0, 0.8, 0.2), 0.5)  # gewonnen: golden angehaucht
	var tr: Dictionary = e["track"]
	var xf: Transform3D = e["xf"] * Track.xform_at(tr["curve"], tr["start"], 0.0)
	var m := Node3D.new()
	m.transform = xf
	var cyl := CylinderMesh.new()
	cyl.top_radius = MARKER_R
	cyl.bottom_radius = MARKER_R
	cyl.height = 26.0
	cyl.cap_top = false
	cyl.cap_bottom = false
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(col.r, col.g, col.b, 0.16)
	var mi := MeshInstance3D.new()
	mi.name = "Beam"
	mi.mesh = cyl
	mi.material_override = mat
	mi.position.y = 13.0
	m.add_child(mi)
	var ring := TorusMesh.new()
	ring.inner_radius = MARKER_R - 0.35
	ring.outer_radius = MARKER_R
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.albedo_color = col
	rmat.emission_enabled = true
	rmat.emission = col
	rmat.emission_energy_multiplier = 3.0
	var rmi := MeshInstance3D.new()
	rmi.mesh = ring
	rmi.material_override = rmat
	rmi.position.y = 0.15
	m.add_child(rmi)
	var lbl := Label3D.new()
	lbl.text = tr(race["name"]).to_upper()
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font = UI.font("wide", 0.15)
	lbl.font_size = 96
	lbl.pixel_size = 0.02
	lbl.modulate = col
	lbl.outline_size = 12
	lbl.outline_modulate = Color(0, 0, 0, 0.8)
	lbl.position.y = 9.0
	lbl.no_depth_test = false
	m.add_child(lbl)
	var ol := OmniLight3D.new()
	ol.light_color = col
	ol.light_energy = 2.0
	ol.omni_range = 16.0
	ol.position.y = 3.0
	m.add_child(ol)
	world.add_child(m)
	_markers[i] = m


func _update_markers() -> void:
	var p := player.global_position
	var near := -1
	for i in _markers:
		var m: Node3D = _markers[i]
		var q: Vector3 = m.global_position
		var dd := Vector2(p.x - q.x, p.z - q.z).length()
		if dd < MARKER_R:
			near = i
		# Lichtsäule von innen nicht mehr sehen (färbte das ganze Bild)
		var beam: MeshInstance3D = m.get_node("Beam")
		var a := 0.16 * clampf((dd - MARKER_R - 2.0) / 25.0, 0.0, 1.0)
		(beam.material_override as StandardMaterial3D).albedo_color.a = a
		beam.visible = a > 0.005
	if near != _near_marker:
		_near_marker = near
		if near >= 0:
			var race: Dictionary = Catalog.RACES[near]
			var line := tr("Enter: Rennen starten")
			if not GameState.career_open(race["name"]):
				var st := Catalog.stage_of(race["name"])
				line = tr("Gesperrt: erst %d Siege in Stufe „%s“") % [Catalog.stage_need(st - 1), tr(Catalog.STAGES[st - 1]["name"])] \
					if st > 0 else tr("Gesperrt")
			hud["prompt"].text = "%s\n%s" % [tr(race["name"]).to_upper(), line]
		hud["prompt"].visible = near >= 0


func _start_race(i: int) -> void:
	# nach dem Rennen hier weiter, mit Blick vom Start weg Richtung Ausfahrt
	var m: Node3D = _markers[i]
	var xf := m.global_transform
	xf.origin += -xf.basis.z * -12.0
	xf.basis = xf.basis * Basis(Vector3.UP, PI)
	return_xf = xf
	has_return = true
	GameState.race_index = i
	get_tree().change_scene_to_file("res://scenes/race.tscn")


# --- Umgebung, HUD -------------------------------------------------------------------

func _setup_environment() -> void:
	mood = Moods.get_mood(Layout.MOOD)
	env = Environment.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("top_col", mood["top"])
	sky_mat.set_shader_parameter("hor_col", mood["hor"])
	sky_mat.set_shader_parameter("glow_col", mood["glow"])
	sky_mat.set_shader_parameter("stars", mood["stars"])
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = mood["amb"]
	env.ambient_light_energy = mood["amb_e"]
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.88
	env.glow_enabled = GameState.gv("bloom")
	env.glow_intensity = 0.6
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.15
	env.fog_enabled = true
	env.fog_light_color = mood["fog"]
	env.fog_density = mood["fog_d"]
	env.adjustment_enabled = true
	env.adjustment_saturation = mood["sat"]
	env.adjustment_contrast = mood["con"]
	env.adjustment_brightness = mood["bri"]
	for m in Track._road_mats.values():
		(m as ShaderMaterial).set_shader_parameter("wet", mood["wet"])
	env.fog_sky_affect = 0.15
	env.ssr_enabled = GameState.gfx_available("ssr") and GameState.gv("ssr") > 0
	env.ssr_max_steps = maxi(GameState.gv("ssr"), 8)
	RenderingServer.environment_set_ssr_half_size(GameState.gv("ssr") < 32)
	env.ssao_enabled = GameState.gfx_available("ssao") and GameState.gv("ssao")
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_LOW, true, 0.5, 2, 50.0, 300.0)
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.6
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	moon = DirectionalLight3D.new()
	moon.light_color = mood["moon"]
	moon.light_energy = mood["moon_e"]
	moon.rotation_degrees = Vector3(-50, 30, 0)
	world.add_child(moon)
	# Boden überall (zwischen den Städten), knapp unter dem Boden der Strecken
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	var ext: float = (layout["ring_r"] + 9000.0) * 2.0
	pm.size = Vector2(ext, ext)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.025, 0.028, 0.03)
	gm.roughness = 0.95
	ground.material_override = gm
	ground.position.y = -0.12
	world.add_child(ground)


func _cover() -> CanvasLayer:
	var cl := CanvasLayer.new()
	cl.layer = 60
	add_child(cl)
	var bg := ColorRect.new()
	bg.color = Color(0.012, 0.014, 0.03)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(bg)
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", UI.font("cond", 0.2))
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", UI.CYAN)
	l.size = Vector2(500, 40)
	l.position = Vector2(-250, -20)
	l.text = tr("Welt wird gebaut …")
	cl.add_child(l)
	cl.set_meta("label", l)
	return cl


func _label(parent: Node, size: int, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align
	l.add_theme_font_override("font", UI.font("cond", 0.2))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _build_hud() -> void:
	var fx_layer := CanvasLayer.new()
	fx_layer.layer = 0
	world.add_child(fx_layer)
	var fx := ColorRect.new()
	fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_mat = ShaderMaterial.new()
	fx_mat.shader = SPEED_FX
	fx.material = fx_mat
	fx.visible = false
	fx_layer.add_child(fx)
	_fx_rect = fx
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var tacho := Control.new()
	tacho.set_script(TACHO)
	tacho.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tacho)
	var s: float = TACHO.SIZE
	tacho.anchor_left = 1.0
	tacho.anchor_right = 1.0
	tacho.anchor_top = 1.0
	tacho.anchor_bottom = 1.0
	tacho.offset_left = -s - 4.0
	tacho.offset_right = tacho.offset_left + s
	tacho.offset_top = -s - 2.0
	tacho.offset_bottom = tacho.offset_top + s
	hud["tacho"] = tacho
	var area := _label(root, 30, HORIZONTAL_ALIGNMENT_CENTER)
	area.anchor_left = 0.5
	area.anchor_right = 0.5
	area.offset_left = -300.0
	area.offset_right = 300.0
	area.offset_top = 40.0
	area.add_theme_font_override("font", UI.font("wide", 0.15))
	hud["area"] = area
	var prompt := _label(root, 20, HORIZONTAL_ALIGNMENT_CENTER)
	prompt.anchor_left = 0.5
	prompt.anchor_right = 0.5
	prompt.anchor_top = 0.24
	prompt.anchor_bottom = 0.24
	prompt.offset_left = -300.0
	prompt.offset_right = 300.0
	prompt.add_theme_color_override("font_color", UI.CYAN)
	prompt.visible = false
	hud["prompt"] = prompt
	var help := _label(root, 9, HORIZONTAL_ALIGNMENT_RIGHT)
	help.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	help.position = Vector2(-250, 6)
	help.size = Vector2(240, 60)
	help.text = tr("Frei fahren: Marker anfahren startet ein Rennen\nTab Karte  C Kamera  R Zurücksetzen  Esc Menü")
	help.modulate.a = 0.7
	hud["help"] = help
	# Minikarte unten links: alle Straßen der Welt, Rennen in Sicht, gewähltes Ziel als Flagge
	for c in layout["cities"]:
		var pin := Node3D.new()
		pin.position = c["start_world"]
		var race: Dictionary = Catalog.RACES[c["race_index"]]
		pin.set_meta("hud_col", UI.TYPE_COL.get(race.get("type", "sprint"), UI.CYAN) if GameState.career_open(race["name"]) else Color(0.5, 0.52, 0.58))
		world.add_child(pin)
		_pins[c["race_index"]] = pin
	minimap = WorldMinimap.new()
	root.add_child(minimap)
	minimap.setup_world(layout["roads"], player, _pins.values())
	minimap.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	minimap.offset_left = 8.0
	minimap.offset_right = 8.0 + WorldMinimap.SIZE
	minimap.offset_top = -WorldMinimap.SIZE - 8.0
	minimap.offset_bottom = -8.0
	_set_target(target)
	_build_pause(root)
	var map_layer := CanvasLayer.new()
	map_layer.layer = 5
	add_child(map_layer)
	map_view = MapView.new()
	map_view.visible = false
	map_layer.add_child(map_view)
	map_view.setup(layout["roads"], layout["cities"], player)
	map_view.target = target
	map_view.target_chosen.connect(_set_target)
	map_view.closed.connect(_close_map)


func _build_pause(root: Control) -> void:
	pause_panel = VBoxContainer.new()
	pause_panel.theme = UI.theme()
	pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_panel.position = Vector2(-70, -50)
	pause_panel.custom_minimum_size = Vector2(140, 0)
	pause_panel.add_theme_constant_override("separation", 3)
	pause_panel.visible = false
	root.add_child(pause_panel)
	var title := _label(pause_panel, 28, HORIZONTAL_ALIGNMENT_CENTER)
	title.text = tr("PAUSE")
	for entry in [["Weiter", _toggle_pause], ["Karte", func(): _toggle_pause(); _open_map()],
			["Tuning", _to_garage.bind("tuning")], ["Auto wechseln", _to_garage.bind("cars")],
			["Vollbild", GameState.toggle_fullscreen],
			["Garage", func(): _unpause(); GameState.in_world = false; get_tree().change_scene_to_file("res://scenes/garage.tscn")]]:
		var b := Button.new()
		b.text = tr(entry[0])
		b.pressed.connect(entry[1])
		pause_panel.add_child(b)


## Esc > Tuning / Auto wechseln: Garage öffnet direkt dort, "Fertig" bringt einen an dieselbe Stelle zurück
func _to_garage(menu: String) -> void:
	_unpause()
	return_xf = player.global_transform
	has_return = true
	GameState.world_menu = menu
	get_tree().change_scene_to_file("res://scenes/garage.tscn")


func _open_map() -> void:
	get_tree().paused = true
	Music.set_paused(true)
	hud["prompt"].visible = false
	map_view.open(target)


func _close_map() -> void:
	_unpause()
	_near_marker = -2  # Hinweis am Marker neu zeigen


func _set_target(i: int) -> void:
	target = i
	if minimap == null:
		return
	if i >= 0 and _pins.has(i):
		minimap.set_target(_pins[i].position, true)
	else:
		minimap.set_target(Vector3.ZERO, false)


func _toggle_pause() -> void:
	var p := not get_tree().paused
	get_tree().paused = p
	pause_panel.visible = p
	Music.set_paused(p)
	if p:
		(pause_panel.get_child(1) as Button).grab_focus()


func _unpause() -> void:
	get_tree().paused = false
	Music.set_paused(false)


func _unhandled_input(event: InputEvent) -> void:
	if not _ready_done:
		return
	if map_view and map_view.visible:
		map_view._handle(event)
		return
	if _near_marker >= 0 and not get_tree().paused and event.is_action_pressed("ui_accept") \
			and GameState.career_open(Catalog.RACES[_near_marker]["name"]):
		get_viewport().set_input_as_handled()
		_start_race(_near_marker)
		return
	if event.is_action_pressed("map") and not get_tree().paused:
		_open_map()
		return
	if event.is_action_pressed("camera") and not get_tree().paused:
		player.toggle_camera()
	elif event.is_action_pressed("reset_car") and not get_tree().paused and not player.track.is_empty():
		var xf: Transform3D = player.track["xf"]
		var loc := Track.locate(player.track, xf.affine_inverse() * player.global_position)
		var p: Dictionary = loc["path"]
		var half: float = p["half_w"] - 2.0
		player.place(xf * Track.xform_at(p["curve"], loc["d"], clampf(loc["lat"], -half, half)))
	elif event.is_action_pressed("pause", false, true):
		_toggle_pause()


func _process(dt: float) -> void:
	if not _ready_done:
		return
	if get_tree().paused:
		return
	if OS.get_cmdline_user_args().has("--wdrive"):
		_autopilot()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ctest="):
			if _ct.is_empty():
				_ctest_setup(a.substr(8))
			_ctest_step(dt)
	_update_streaming()
	_spawn_queued(3)
	_update_traffic_sound(dt)
	_update_markers()
	var tacho = hud["tacho"]
	tacho.rpm = player.rpm
	tacho.speed_kmh = int(absf(player.speed_fwd) * 3.6)
	tacho.gear = "R" if player.reverse_gear or player.speed_fwd < -0.5 else str(player.gear)
	tacho.nitro = player.nitro
	tacho.heat = player.engine_heat
	tacho.nitro_on = player.nitro_on
	if _area_t > 0.0:
		_area_t -= dt
		hud["area"].modulate.a = 0.85 * clampf(_area_t / 0.6, 0.0, 1.0)
	else:
		hud["area"].modulate.a = 0.0
	_update_speed_fx(dt)


## Test (--wdrive): fährt die Hauptstraße der aktuellen Strecke entlang (Ring: von Stück zu Stück), mit Nitro.
## Gibt alle 2 s Lage, Tempo, aktive Strecke und Bauzustand aus ("WD ...").
var _wd_t := 0.0


func _autopilot() -> void:
	var tr: Dictionary = player.track
	if tr.is_empty() or player.loc.is_empty():
		return
	var xf: Transform3D = tr["xf"]
	# Weg, auf dem man gerade ist (Auffahrt, Ausfahrt, Hauptstraße)
	var c: Curve3D = player.loc["path"]["curve"]
	var lp := xf.affine_inverse() * player.global_position
	var d := c.get_closest_offset(lp)
	var f := Track.frame_at(c, d)
	var sgn := 1.0 if (xf.basis * f["fwd"]).dot(-player.global_basis.z) >= 0.0 else -1.0
	var ft := Track.frame_at(c, d + sgn * (18.0 + absf(player.speed_fwd) * 0.6))
	var lane: float = Track.lane_lat(tr, d, 2.25) if player.loc["path"]["id"] == 0 else 2.0
	var tgt: Vector3 = xf * (ft["pos"] + ft["right"] * sgn * lane)
	var to := tgt - player.global_position
	var side := to.dot(player.global_basis.x)
	Input.action_release("steer_left")
	Input.action_release("steer_right")
	if side > 0.6:
		Input.action_press("steer_right", clampf(side / 6.0, 0.2, 1.0))
	elif side < -0.6:
		Input.action_press("steer_left", clampf(-side / 6.0, 0.2, 1.0))
	Input.action_press("accelerate")
	if player.speed_fwd > 30.0:
		Input.action_press("nitro")
	else:
		Input.action_release("nitro")
	_wd_t += get_process_delta_time()
	if _wd_t > 2.0:
		_wd_t = 0.0
		var built := entries.filter(func(e): return e["state"] == "ready").size()
		print("WD pos=(%.0f,%.0f) v=%d strecke=%s weg=%s d=%.0f geladen=%d baut=%s fps=%d verkehr=%d schlange=%d" % [player.global_position.x, player.global_position.z,
			int(player.speed_fwd * 3.6), active.get("race", {}).get("name", "-"), player.loc["path"]["kind"], d, built, str(_task >= 0 or not _job.is_empty()),
			Engine.get_frames_per_second(), traffic.size(), _tq.size()])


func _update_speed_fx(dt: float) -> void:
	var lvl: float = BLUR_LEVEL[GameState.motion_blur]
	_nitro_fx = move_toward(_nitro_fx, 1.0 if player.nitro_on else 0.0, dt * 4.0)
	var yaw: float = player.cam.global_rotation.y
	var rate := wrapf(yaw - _cam_yaw_prev, -PI, PI) / maxf(dt, 0.001)
	_cam_yaw_prev = yaw
	_swing = lerpf(_swing, clampf(rate * 0.012, -0.03, 0.03), 1.0 - exp(-dt * 10.0))
	var kmh: float = player.velocity.length() * 3.6
	var sk := smoothstep(90.0, 235.0, kmh)
	var blur := lvl * (0.115 * sk * sk + 0.075 * _nitro_fx)
	var sw := lvl * _swing * smoothstep(0.2, 0.5, sk)
	var nit := _nitro_fx if lvl > 0.0 else 0.0
	_fx_rect.visible = blur + absf(sw) > 0.0004 or nit > 0.001
	if _fx_rect.visible:
		fx_mat.set_shader_parameter("blur", blur)
		fx_mat.set_shader_parameter("swing", sw)
		fx_mat.set_shader_parameter("nitro", nit)
		fx_mat.set_shader_parameter("speed", sk * minf(lvl, 1.0) if blur > 0.0 else 0.0)


# --- Verkehr ----------------------------------------------------------------------
## Jede geladene Strecke bekommt Verkehr: auf der Autobahn sechs Spuren mit festem Tempo je Spur (so holen sich
## Autos auf derselben Spur nie ein), in den Städten wie im Rennen. Die Autos hängen am Knoten ihrer Strecke und
## verschwinden mit ihr. Am Ende eines Autobahnstücks fahren sie aufs nächste weiter, sonst werden sie außer Sicht
## neu eingesetzt.

func _plan_traffic(e: Dictionary) -> void:
	if not _ct.is_empty():
		return
	var tr: Dictionary = e["track"]
	var L: float = tr["length"]
	if e["kind"] == "seg":
		var d := _trng.randf_range(10.0, 80.0)
		while d < L - 10.0:
			var lane: float = Track.AB_LANES[_trng.randi() % Track.AB_LANES.size()]
			var outer := absf(lane) > 10.0
			var kind: String = ["bus", "van", "van", "sedan"][_trng.randi() % 4] if outer else ["sedan", "sedan", "taxi", "van"][_trng.randi() % 4]
			_tq.append([e, {"d": d, "lane": lane, "speed": AB_SPEED[absf(lane)], "kind": kind}])
			d += _trng.randf_range(60.0, 120.0)
		return
	var d2: float = 30.0
	while d2 < L - 30.0:
		var lane2: float = Track.LANES[_trng.randi() % 4]
		var blocked: bool = tr["crossing_d"] > 0.0 and absf(d2 - tr["crossing_d"]) < 40.0
		for b in tr["blocks"]:
			if absf(b["lane"] - lane2) < 1.0 and d2 > b["from"] - 20.0 and d2 < b["to"] + 20.0:
				blocked = true
		if not blocked:
			_tq.append([e, {"d": d2, "lane": lane2, "speed": _trng.randf_range(10.0, 16.0),
				"kind": Traffic.KINDS[_trng.randi() % Traffic.KINDS.size()]}])
		d2 += _trng.randf_range(70.0, 140.0)


func _spawn_queued(n: int) -> void:
	var lp_cache := {}
	while n > 0 and not _tq.is_empty() and traffic.size() < TRAFFIC_MAX:
		var q: Array = _tq.pop_front()
		var e: Dictionary = q[0]
		var plan: Dictionary = q[1]
		if e["state"] != "ready":
			continue
		var tr: Dictionary = e["track"]
		# nicht direkt vor der Nase auftauchen (ab der ersten Fahrt; beim Bauen hinter dem Ladebild egal)
		if _ready_done:
			var lp: Vector3 = (e["xf"] as Transform3D).affine_inverse() * player.global_position
			if (tr["curve"] as Curve3D).sample_baked(plan["d"]).distance_to(lp) < 160.0:
				continue
		var t := Traffic.new()
		t.process_mode = Node.PROCESS_MODE_PAUSABLE
		t.curve = tr["curve"]
		t.track = tr
		t.blocks = tr["blocks"]
		t.progress = plan["d"]
		t.lane = plan["lane"]
		t.dir = 1.0 if plan["lane"] > 0.0 else -1.0
		t.base_speed = plan["speed"]
		t.speed = plan["speed"]
		t.track_length = tr["length"]
		t.crossing = tr["crossing"]
		t.parent_basis = (e["xf"] as Transform3D).basis
		t.player_path = -1
		if e["kind"] == "seg" or not tr["loop"]:
			t.on_end = _traffic_end
		t.set_meta("e", e)
		(tr["node"] as Node).add_child(t)
		t.setup(plan["kind"], _trng)
		t.place()
		traffic.append(t)
		n -= 1


## Wagen am Ende seines Wegs: aufs nächste (oder vorige) Autobahnstück, sonst außer Sicht neu einsetzen
func _traffic_end(t: Node) -> void:
	if not is_instance_valid(t) or not t.is_inside_tree():
		return
	var e: Dictionary = t.get_meta("e")
	if e["state"] != "ready":
		return
	if e["kind"] == "seg":
		var fwd: bool = t.progress > t.track_length / 2.0
		var n2: Dictionary = _segs[(int(e["seg_i"]) + (1 if fwd else -1) + _segs.size()) % _segs.size()]
		if n2["state"] == "ready":
			var nt: Dictionary = n2["track"]
			t.get_parent().remove_child(t)
			(nt["node"] as Node).add_child(t)
			t.set_meta("e", n2)
			t.move_to(nt, 1.5 if fwd else float(nt["length"]) - 1.5)
			return
	var tr: Dictionary = e["track"]
	var L: float = tr["length"]
	var lp: Vector3 = (e["xf"] as Transform3D).affine_inverse() * player.global_position
	var far := maxf(GameState.view_distance() + 60.0, 300.0)
	for i in 12:
		var d := _trng.randf_range(40.0, L - 40.0)
		if (tr["curve"] as Curve3D).sample_baked(d).distance_to(lp) > far:
			t.move_to(tr, d)
			return
	t.move_to(tr, 40.0 if t.dir > 0.0 else L - 40.0)


## Was der Verkehr vom Spieler wissen muss (in den Koordinaten seiner Strecke): wo er ist, und auf derselben
## Strecke auch Weg, Meter und Spur, damit die Autos vor ihm bremsen
func _feed_traffic() -> void:
	if traffic.is_empty():
		return
	var proot: Node = player.track.get("node") if not player.track.is_empty() else null
	var on_main: bool = player.path_id == 0
	var p_lat: float = 0.0
	var p_d: float = 0.0
	var p_v: float = 0.0
	if proot and not player.loc.is_empty():
		p_lat = Track.logical_lat(player.track, player.progress, player.lateral) if on_main else player.lateral
		p_d = player.progress if on_main else player.loc["d"]
		var pf: Vector3 = Track.frame_at(player.loc["path"]["curve"], p_d)["fwd"]
		p_v = ((proot as Node3D).transform.basis.inverse() * player.velocity).dot(pf)
	_leader_t -= get_physics_process_delta_time()
	if _leader_t <= 0.0:
		_leader_t = 0.2
		Traffic.link_leaders(traffic)
	var local := {}
	for t in traffic:
		var par: Node = t.get_parent()
		if par == null:
			continue
		if not local.has(par):
			local[par] = (par as Node3D).transform.affine_inverse() * player.global_position
		t.player_pos = local[par]
		if par == proot:
			t.player_progress = p_d
			t.player_lateral = p_lat
			t.player_path = player.path_id
			t.player_speed = p_v
		else:
			t.player_path = -1


## Wie im Rennen: nur die nächsten paar Autos im Umkreis von 80 m sind zu hören
func _update_traffic_sound(dt: float) -> void:
	_traffic_snd_t -= dt
	if _traffic_snd_t > 0.0 or traffic.is_empty():
		return
	_traffic_snd_t = 0.25
	var near := []
	var pp: Vector3 = player.global_position
	for t in traffic:
		var d2: float = (t.global_position - pp).length_squared()
		if d2 < 6400.0 and not t.wrecked:
			near.append([d2, t])
	near.sort_custom(func(a, b): return a[0] < b[0])
	var on := {}
	for i in mini(near.size(), TRAFFIC_VOICES):
		on[near[i][1]] = true
	var bus: String = player.audio.bus if player.audio else "Master"
	for t in traffic:
		t.sound(on.has(t), bus)


# --- Test: Zusammenstöße (--ctest=fall) -----------------------------------------------------
## Feste Szenen auf der Autobahn, misst alle 0,1 s Tempo, Drehung, Benommenheit, Überschlag und ob der Spieler
## im anderen Auto steckt ("CT ..."). Fälle: rear40, rear120, side, standing, wrongway, wall10/30/60/90
var _ct := {}


func _ctest_setup(case: String) -> void:
	for t in traffic:
		t.queue_free()
	traffic.clear()
	_tq.clear()
	var tr: Dictionary = player.track
	var c: Curve3D = tr["curve"]
	var d0: float = player.progress
	var cases := {
		# Spieler-Spur, Tempo, Drehung (Grad, + nach rechts), Verkehr: Spur, Abstand, Tempo, Art
		"rear40": [6.75, 42.0, 0.0, 6.75, 30.0, 30.0, "sedan"],
		"rear120": [11.25, 70.0, 0.0, 11.25, 60.0, 24.0, "bus"],
		"side": [2.25, 32.0, 12.0, 6.75, 0.0, 30.0, "sedan"],
		"wreck": [11.25, 0.0, 0.0, 11.25, 40.0, 24.0, "sedan"],
		"standing": [2.25, 0.0, 0.0, 2.25, -70.0, 36.0, "sedan"],
		"wrongway": [6.75, -35.0, 180.0, 6.75, -80.0, 30.0, "van"],
		"bus": [6.75, 42.0, 0.0, 6.75, 30.0, 30.0, "bus"],
		"wall10": [11.25, 42.0, 10.0, 0.0, 0.0, 0.0, ""],
		"wall30": [11.25, 42.0, 30.0, 0.0, 0.0, 0.0, ""],
		"wall60": [11.25, 42.0, 60.0, 0.0, 0.0, 0.0, ""],
		"wall90": [11.25, 30.0, 90.0, 0.0, 0.0, 0.0, ""],
		"median30": [2.25, 42.0, -30.0, 0.0, 0.0, 0.0, ""],
	}
	var k: Array = cases[case]
	var xf := Track.xform_at(c, d0, Track.lane_lat(tr, d0, k[0]), true)
	xf.basis = xf.basis * Basis(Vector3.UP, deg_to_rad(-k[2]))
	player.place(xf)
	player.velocity = -xf.basis.z * absf(k[1])
	player.speed_fwd = absf(k[1])
	if k[6] != "":
		_tq.append([active, {"d": d0 + k[4], "lane": k[3], "speed": k[5], "kind": k[6]}])
		var rd := _ready_done
		_ready_done = false
		_spawn_queued(1)
		_ready_done = rd
		traffic[0].player_path = -1
	if case == "wreck":
		# Wrack 140 m vor dem Spieler auf derselben Spur: der Wagen dahinter muss bremsen und die Spur wechseln
		_tq.append([active, {"d": d0 + 140.0, "lane": 11.25, "speed": 0.0, "kind": "van"}])
		var rd2 := _ready_done
		_ready_done = false
		_spawn_queued(1)
		_ready_done = rd2
		traffic[1].push(Vector3.ZERO)
	_ct = {"case": case, "t": 0.0, "next": 0.0, "hold": case.begins_with("wall") or case.begins_with("median")}


func _ctest_step(dt: float) -> void:
	_ct["t"] += dt
	for a in ["steer_left", "steer_right", "accelerate", "nitro", "brake", "handbrake"]:
		Input.action_release(a)
	if _ct["hold"] or _ct["case"].begins_with("rear") or _ct["case"] == "bus":
		Input.action_press("accelerate")
	if _ct["t"] < _ct["next"]:
		return
	_ct["next"] += 0.1
	var pl = player
	var s := "CT %s t=%.1f v=%3d fwd=%3d gier=%4d stun=%.2f spin=%.1f roll=%s crashes=%d wand=%d" % [_ct["case"], _ct["t"],
		int(pl.velocity.length() * 3.6), int(pl.speed_fwd * 3.6), int(rad_to_deg(pl.global_basis.z.signed_angle_to(Track.frame_at(pl.track["curve"], pl.progress)["fwd"] * -1.0, Vector3.UP))),
		pl.stun, pl._spin, str(pl.tumbling), pl.crashes, pl.wall_hits]
	if not traffic.is_empty():
		var t = traffic[0]
		var q: Vector3 = t.global_transform.affine_inverse() * pl.global_position
		var inside: bool = absf(q.x) < 1.9 and absf(q.z) < t.length / 2.0 + 2.0
		if traffic.size() > 1:
			s += " | B v=%d spur=%.1f luecke=%.0f" % [int(t.speed * 3.6), t.lateral(), traffic[1].progress - t.progress]
		s += " | ver v=%3d wrack=%s abst=%.1f quer=%.1f laengs=%.1f%s" % [int(t.velocity_vec.length() * 3.6), str(t.wrecked),
			t.global_position.distance_to(pl.global_position), q.x, q.z, " DRIN" if inside else ""]
	print(s)
	if _ct["t"] > (8.0 if _ct["case"] in ["wreck", "bus", "standing"] else 3.0):
		get_tree().quit()
