extends Node3D
## Sprintrennen: Strecke bauen, Spieler + 3 Gegner aufstellen, Countdown, HUD, Zieleinlauf, Ergebnis.

const Catalog := preload("res://scripts/catalog.gd")
const Track := preload("res://scripts/track_builder.gd")
const PlayerCar := preload("res://scripts/player_car.gd")
const AICar := preload("res://scripts/ai_car.gd")
const SPEED_FX := preload("res://shaders/speed_fx.gdshader")
const TACHO := preload("res://scripts/tacho.gd")
const PixelView := preload("res://scripts/pixel_view.gd")
const Traffic := preload("res://scripts/traffic_car.gd")
const SKY_SHADER := preload("res://shaders/night_sky.gdshader")

enum State { COUNTDOWN, RACING, FINISHED }

var race: Dictionary
var track: Dictionary
var curve: Curve3D
var player: CharacterBody3D
var ais: Array = []
var traffic: Array = []
var world: SubViewport
var state := State.COUNTDOWN
var countdown := 3.99
var race_time := 0.0
var player_progress := 0.0
var finish_order: Array = []  # "player" oder AI-Knoten in Zielreihenfolge

var fx_mat: ShaderMaterial
var hud := {}
var result_panel: Control
var _last_path := 0
var _last_landings := 0
var _flash_t := 0.0
var pause_panel: Control


func _ready() -> void:
	# Die Szene selbst läuft immer (Pausemenü, Esc), Autos und Strecke sind pausierbar.
	process_mode = Node.PROCESS_MODE_ALWAYS
	race = Catalog.RACES[GameState.race_index]
	# 3D-Welt rendert in eine eigene (pixelige) Auflösung, die Oberfläche bleibt scharf
	var view_layer := CanvasLayer.new()
	view_layer.layer = -1
	add_child(view_layer)
	var pv := PixelView.new()
	view_layer.add_child(pv)
	world = pv.world

	track = Track.build(race)
	curve = track["curve"]
	track["node"].process_mode = Node.PROCESS_MODE_PAUSABLE
	world.add_child(track["node"])
	_setup_environment()

	var car_id := GameState.current_car
	player = PlayerCar.new()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.track = track
	world.add_child(player)
	player.setup(car_id, GameState.get_config(car_id))
	player.place(Track.xform_at(curve, track["start"], Track.LANES[2]))

	# Gegner mit zufälligem Tuning, Stärke wächst mit deinen Siegen
	var rng := RandomNumberGenerator.new()
	rng.seed = race["seed"] * 31 + GameState.wins
	var lanes := [Track.LANES[0], Track.LANES[1], Track.LANES[3]]
	var difficulty := 0.86 + minf(GameState.wins, 8) * 0.018
	for i in 3:
		var id: String = Catalog.CAR_ORDER[rng.randi() % Catalog.CAR_ORDER.size()]
		var cfg := {}
		for cat in Catalog.PART_ORDER:
			cfg[cat] = rng.randi() % Catalog.PARTS[cat]["options"].size()
		var ai := AICar.new()
		ai.process_mode = Node.PROCESS_MODE_PAUSABLE
		ai.player = player
		ai.finish = track["finish"]
		ai.traffic = traffic
		ai.crossing = track["crossing"]
		world.add_child(ai)
		var top: float = Catalog.CARS[id]["top_speed"] * (0.95 + 0.03 * i)
		ai.setup(track, id, cfg, track["start"] + (i - 1) * 4.0, lanes[i], top, difficulty + rng.randf_range(-0.03, 0.03))
		ais.append(ai)

	if track["crossing"]:
		track["crossing"].player = player
	_spawn_traffic()
	_build_hud()


## Verkehr: rechts in Fahrtrichtung, links Gegenverkehr. Erst ein Stück nach dem Start.
func _spawn_traffic() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = race["seed"] * 7 + 1
	var d: float = track["start"] + 160.0
	while d < track["length"] - 30.0:
		var lane: float = Track.LANES[rng.randi() % 4]
		var blocked: bool = track["crossing_d"] > 0.0 and absf(d - track["crossing_d"]) < 40.0
		for b in track["blocks"]:
			if absf(b["lane"] - lane) < 1.0 and d > b["from"] - 20.0 and d < b["to"] + 20.0:
				blocked = true
		if not blocked:
			var t := Traffic.new()
			t.process_mode = Node.PROCESS_MODE_PAUSABLE
			t.curve = curve
			t.blocks = track["blocks"]
			t.progress = d
			t.lane = lane
			t.dir = 1.0 if lane > 0.0 else -1.0
			t.base_speed = rng.randf_range(10.0, 16.0)
			t.speed = t.base_speed
			t.track_length = track["length"]
			t.crossing = track["crossing"]
			world.add_child(t)
			t.setup(Traffic.KINDS[rng.randi() % Traffic.KINDS.size()], rng)
			traffic.append(t)
		d += rng.randf_range(45.0, 95.0)


func _setup_environment() -> void:
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
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.09, 0.07, 0.16)
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.15
	env.ssr_enabled = true
	env.ssr_max_steps = 48
	env.ssao_enabled = true
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.6
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.6, 1.0)
	moon.light_energy = 0.25
	moon.rotation_degrees = Vector3(-50, 30, 0)
	world.add_child(moon)


func _label(parent: Node, size: int, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.outline_size = 4
	ls.outline_color = Color(0, 0, 0, 0.9)
	l.label_settings = ls
	l.horizontal_alignment = align
	parent.add_child(l)
	return l


func _bar(parent: Node, pos: Vector2, size: Vector2, col: Color) -> ColorRect:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.position = pos
	bg.size = size
	parent.add_child(bg)
	var fg := ColorRect.new()
	fg.color = col
	fg.position = Vector2(1, 1)
	fg.size = size - Vector2(2, 2)
	bg.add_child(fg)
	return fg


func _build_hud() -> void:
	var fx_layer := CanvasLayer.new()
	fx_layer.layer = 0
	add_child(fx_layer)
	var fx := ColorRect.new()
	fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_mat = ShaderMaterial.new()
	fx_mat.shader = SPEED_FX
	fx.material = fx_mat
	fx_layer.add_child(fx)

	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	hud["pos"] = _label(root, 26)
	hud["pos"].position = Vector2(12, 6)
	hud["time"] = _label(root, 14)
	hud["time"].position = Vector2(12, 40)
	hud["race"] = _label(root, 10)
	hud["race"].position = Vector2(12, 58)
	hud["race"].text = race["name"].to_upper()
	hud["music"] = _label(root, 10)
	hud["music"].position = Vector2(12, 342)
	hud["help"] = _label(root, 9, HORIZONTAL_ALIGNMENT_RIGHT)
	hud["help"].set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hud["help"].position = Vector2(-250, 6)
	hud["help"].size = Vector2(240, 60)
	hud["help"].text = "W/S Gas/Bremse  A/D Lenken\nLeertaste Handbremse  Shift Nitro\nC Kamera  R Zurücksetzen  M Musik  Esc Pause"
	hud["help"].modulate.a = 0.7

	# Drehzahlmesser unten rechts
	var tacho := Control.new()
	tacho.set_script(TACHO)
	tacho.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	tacho.position = Vector2(-158, -168)
	tacho.size = Vector2(150, 150)
	tacho.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tacho)
	hud["tacho"] = tacho

	# Fortschritt oben mittig
	hud["progress"] = _bar(root, Vector2(220, 10), Vector2(200, 6), Color(0.9, 0.9, 1.0))

	hud["center"] = _label(root, 64, HORIZONTAL_ALIGNMENT_CENTER)
	hud["center"].anchor_left = 0.5
	hud["center"].anchor_right = 0.5
	hud["center"].anchor_top = 0.5
	hud["center"].anchor_bottom = 0.5
	hud["center"].offset_left = -200
	hud["center"].offset_right = 200
	hud["center"].offset_top = -90
	hud["center"].offset_bottom = 0

	hud["drift"] = _label(root, 14, HORIZONTAL_ALIGNMENT_CENTER)
	hud["drift"].position = Vector2(220, 300)
	hud["drift"].size = Vector2(200, 20)
	hud["flash"] = _label(root, 22, HORIZONTAL_ALIGNMENT_CENTER)
	hud["flash"].anchor_left = 0.5
	hud["flash"].anchor_right = 0.5
	hud["flash"].offset_left = -180
	hud["flash"].offset_right = 180
	hud["flash"].offset_top = 44
	hud["flash"].offset_bottom = 74

	_build_pause(root)


func _process(dt: float) -> void:
	if get_tree().paused:
		return
	match state:
		State.COUNTDOWN:
			countdown -= dt
			var n := int(ceil(countdown - 1.0))
			hud["center"].text = str(n) if n > 0 else "GO!"
			if countdown <= 1.0 and not player.controls_enabled:
				player.controls_enabled = true
				for ai in ais:
					ai.running = true
				state = State.RACING
		State.RACING:
			race_time += dt
			if countdown > 0.0:
				countdown -= dt
				if countdown <= 0.0:
					hud["center"].text = ""
		State.FINISHED:
			pass

	player_progress = player.progress
	for ai in ais:
		ai.player_progress = player_progress
		ai.player_lateral = player.lateral
		ai.player_path = player.path_id
		if ai.progress >= track["finish"] and ai.finish_time < 0.0:
			ai.finish_time = race_time
			finish_order.append(ai)
	for t in traffic:
		t.player_progress = player_progress
		t.player_lateral = player.lateral
		t.player_path = player.path_id
	if state == State.RACING and player_progress >= track["finish"]:
		_on_player_finished()

	_update_hud()


func _place() -> int:
	if state == State.FINISHED:
		return finish_order.find("player") + 1
	var place := 1
	for ai in ais:
		if ai.finish_time >= 0.0 or ai.progress > player_progress:
			place += 1
	return place


func _update_hud() -> void:
	var sf := clampf(absf(player.speed_fwd) / player.top_speed, 0.0, 1.0)
	fx_mat.set_shader_parameter("lines", clampf((sf - 0.45) * 2.0, 0.0, 1.0) + (0.6 if player.nitro_on else 0.0))
	fx_mat.set_shader_parameter("blur", 1.0 if player.nitro_on else sf * 0.25)
	fx_mat.set_shader_parameter("nitro", 1.0 if player.nitro_on else 0.0)

	hud["pos"].text = "%d/4" % _place()
	hud["time"].text = _fmt(race_time)
	var tacho = hud["tacho"]
	tacho.rpm = player.rpm
	tacho.speed_kmh = int(absf(player.speed_fwd) * 3.6)
	tacho.gear = "R" if player.speed_fwd < -0.5 else ("N" if state == State.COUNTDOWN else str(player.gear))
	tacho.nitro = player.nitro
	tacho.nitro_on = player.nitro_on
	hud["progress"].size.x = 198.0 * clampf((player_progress - track["start"]) / (track["finish"] - track["start"]), 0.0, 1.0)
	hud["drift"].text = "DRIFT  +NOS" if player.drifting else ("AIR" if player.airborne else "")
	# Kurze Einblendungen: Abkürzung, Sprungweite, Kamera
	if player.path_id != _last_path:
		var kind: String = track["paths"][player.path_id]["kind"]
		if kind == "alley" or kind == "lake":
			_flash("ABKÜRZUNG!", Color(1.0, 0.6, 0.1))
		_last_path = player.path_id
	if player.landings != _last_landings:
		_last_landings = player.landings
		if player.last_air > 0.5:
			_flash("AIR  %.1f s" % player.last_air, Color(0.4, 0.85, 1.0))
	if _flash_t > 0.0:
		_flash_t -= get_process_delta_time()
		hud["flash"].modulate.a = clampf(_flash_t / 0.4, 0.0, 1.0)
	hud["music"].text = ("Musik: " + Music.current_title) if Music.current_title != "" else "Keine Musik: mp3/ogg in den Ordner music/ legen"


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera"):
		player.toggle_camera()
		_flash("Kamera: " + player.CAM_NAMES[player.cam_mode], Color(0.85, 0.9, 1.0))
	elif event.is_action_pressed("reset_car") and state == State.RACING:
		var loc := Track.locate(track, player.global_position)
		var p: Dictionary = loc["path"]
		var half: float = p["half_w"] - 2.0
		player.place(Track.xform_at(p["curve"], loc["d"], clampf(loc["lat"], -half, half)))
	elif event.is_action_pressed("pause") and state != State.FINISHED:
		_toggle_pause()


func _on_player_finished() -> void:
	state = State.FINISHED
	finish_order.append("player")
	player.controls_enabled = false
	player.finished = true
	var place := finish_order.find("player") + 1
	var unlocked := []
	if place == 1:
		unlocked = GameState.register_win()
	var key: String = race["name"]
	var best: float = GameState.best_times.get(key, 0.0)
	var new_best := best <= 0.0 or race_time < best
	if new_best:
		GameState.best_times[key] = race_time
	GameState.save_game()
	hud["center"].text = "SIEG!" if place == 1 else "%d. PLATZ" % place
	_show_result(place, new_best, unlocked)


func _show_result(place: int, new_best: bool, unlocked: Array) -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-150, 0)
	panel.custom_minimum_size = Vector2(300, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.08, 0.88)
	sb.border_color = Color(0.2, 0.7, 1.0)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	hud["center"].get_parent().add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	var t := _label(vb, 14, HORIZONTAL_ALIGNMENT_CENTER)
	t.text = "Zeit  %s%s" % [_fmt(race_time), "   NEUE BESTZEIT" if new_best else ""]
	if place == 1:
		var w := _label(vb, 11, HORIZONTAL_ALIGNMENT_CENTER)
		w.text = "Siege gesamt: %d" % GameState.wins
		if unlocked.size() > 0:
			var u := _label(vb, 11, HORIZONTAL_ALIGNMENT_CENTER)
			u.text = "FREIGESCHALTET:\n" + "\n".join(unlocked)
			u.modulate = Color(0.4, 1.0, 0.5)
	else:
		var w := _label(vb, 11, HORIZONTAL_ALIGNMENT_CENTER)
		w.text = "Nur Platz 1 schaltet neue Teile frei."
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(hb)
	var again := Button.new()
	again.text = "Nochmal"
	again.pressed.connect(func(): get_tree().reload_current_scene())
	hb.add_child(again)
	var back := Button.new()
	back.text = "Garage"
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/garage.tscn"))
	hb.add_child(back)
	back.grab_focus.call_deferred()


func _build_pause(root: Control) -> void:
	pause_panel = VBoxContainer.new()
	pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_panel.position = Vector2(-60, -40)
	pause_panel.custom_minimum_size = Vector2(120, 0)
	pause_panel.visible = false
	root.add_child(pause_panel)
	var title := _label(pause_panel, 20, HORIZONTAL_ALIGNMENT_CENTER)
	title.text = "PAUSE"
	for entry in [["Weiter", _toggle_pause], ["Neustart", func(): _unpause(); get_tree().reload_current_scene()],
			["Garage", func(): _unpause(); get_tree().change_scene_to_file("res://scenes/garage.tscn")]]:
		var b := Button.new()
		b.text = entry[0]
		b.pressed.connect(entry[1])
		pause_panel.add_child(b)


func _toggle_pause() -> void:
	var p := not get_tree().paused
	get_tree().paused = p
	pause_panel.visible = p
	if p:
		(pause_panel.get_child(1) as Button).grab_focus()


func _unpause() -> void:
	get_tree().paused = false


func _fmt(t: float) -> String:
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]



func _flash(text: String, col: Color) -> void:
	hud["flash"].text = text
	hud["flash"].label_settings.font_color = col
	hud["flash"].modulate.a = 1.0
	_flash_t = 1.6
