extends Node3D
## Events: Sprint und Rundkurs gegen 3 Gegner im Verkehr, Drift allein auf leerer Strecke mit Punkten.
## Strecke bauen, aufstellen, Countdown, HUD, Zieleinlauf, Ergebnis.

const Catalog := preload("res://scripts/catalog.gd")
const Track := preload("res://scripts/track_builder.gd")
const PlayerCar := preload("res://scripts/player_car.gd")
const AICar := preload("res://scripts/ai_car.gd")
const SPEED_FX := preload("res://shaders/speed_fx.gdshader")
const TACHO := preload("res://scripts/tacho.gd")
const MINIMAP := preload("res://scripts/minimap.gd")
const HUD_INFO := preload("res://scripts/hud_info.gd")
const Builder := preload("res://scripts/car_builder.gd")
const PixelView := preload("res://scripts/pixel_view.gd")
const Traffic := preload("res://scripts/traffic_car.gd")
const SKY_SHADER := preload("res://shaders/night_sky.gdshader")
const RaceShow := preload("res://scripts/race_show.gd")
const UI := preload("res://scripts/ui_style.gd")
const TOUCH := preload("res://scripts/touch_controls.gd")
const Moods := preload("res://scripts/moods.gd")
const Loading := preload("res://scripts/loading_screen.gd")

enum State { COUNTDOWN, RACING, FINISHED, INTRO }

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
var player_progress := 0.0  # Gesamtfortschritt des Spielers (bei Rundkursen über alle Runden)
var event_type := "sprint"
## Drift-Wertung: gesicherte Punkte, laufende Kette, Dauer der Kette, Zeit seit dem letzten Querfahren
var drift_score := 0.0
var drift_chain := 0.0
var drift_chain_t := 0.0
var drift_idle := 0.0
var drift_targets: Array = []  # Punkte für Platz 3, 2, 1
var _last_crashes := 0
var _last_walls := 0
var _zones := []  # Drift-Bonuszonen: [von, bis, Seite] (Seite +1 rechts, -1 links)
var _zone_mat: ShaderMaterial
var _zone_k := 0.0
var in_zone := false  # Spieler driftet gerade in einer Bonuszone
var _near := {}  # Verkehrsautos, für die es schon einen Near Miss gab
var _last_lap := 0
var finish_order: Array = []  # "player" oder AI-Knoten in Zielreihenfolge

var fx_mat: ShaderMaterial
var _fx_rect: ColorRect  # Bewegungsunschärfe/Nitro-Schimmer über dem Bild; aus, wenn nichts ansteht
var _cam_yaw_prev := 0.0
var _swing := 0.0
var _nitro_fx := 0.0
var hud := {}
var result_panel: Control
var _last_path := 0
var _last_landings := 0
var _last_rollovers := 0
## Punkte-Anzeige unten links (statt Einblendungen in der Bildmitte): Drift, knapp vorbei, Sprung; Punkte füllen
## Nitro ein wenig auf. Jede Zeile blendet nach ein paar Sekunden aus.
var _feed: VBoxContainer
var _style_chain := 0.0  # laufender Drift im Rennen (Punkte, noch nicht gutgeschrieben)
var _style_idle := 0.0
var _style_crashes := 0
var _style_walls := 0
var pause_panel: Control
var env: Environment
var moon: DirectionalLight3D
var _reverb: AudioEffectReverb
var _lowpass: AudioEffectLowPassFilter  # Zeitlupe: Motor und Effekte klingen dumpf
var _bars: Array[ColorRect] = []  # Kino-Balken bei der Sprungkamera
var _bars_k := 0.0
var _tunnel_k := 0.0
var _in_tunnel := false
var _beep_n := 4  # zuletzt gepiepte Countdown-Zahl
var _traffic_snd_t := 0.0
const TRAFFIC_VOICES := 4  # so viele Verkehrsautos sind gleichzeitig zu hören (die nächsten)
var _district_i := -1
var _area_t := 0.0
var show: Node3D  # Publikum, Starterin, Kameraflug, Zielszene
var hud_layer: CanvasLayer
var title_layer: CanvasLayer


func _ready() -> void:
	# Die Szene selbst läuft immer (Pausemenü, Esc), Autos und Strecke sind pausierbar.
	process_mode = Node.PROCESS_MODE_ALWAYS
	race = Catalog.RACES[GameState.race_index]
	event_type = race.get("type", "sprint")
	# Ladebildschirm (die Garage hat denselben schon gezeigt): Strecke und Autos werden in Schritten gebaut, dazwischen
	# kommt jeweils ein Bild, damit der Balken läuft und das Fenster nicht hängt. Solange ist alles pausiert.
	_warming = true
	get_tree().paused = true
	Music.race_loading()
	_loading = Loading.new(race, GameState.current_car)
	add_child(_loading)
	await get_tree().process_frame
	# 3D-Welt rendert in eine eigene (pixelige) Auflösung, die Oberfläche bleibt scharf
	var view_layer := CanvasLayer.new()
	view_layer.layer = -1
	add_child(view_layer)
	var pv := PixelView.new()
	view_layer.add_child(pv)
	world = pv.world
	world.render_target_update_mode = SubViewport.UPDATE_DISABLED  # während des Ladens nichts zeichnen

	var t_load := Time.get_ticks_msec()
	var job := Track.begin(race)
	_loading.progress = 0.04
	await get_tree().process_frame
	while true:
		var tp := Track.step(job)
		_loading.progress = 0.04 + 0.66 * tp
		await get_tree().process_frame
		if tp >= 1.0:
			break
	if OS.get_cmdline_user_args().has("--loadlog"):
		print("LOAD Strecke %d ms, Schritte %s" % [Time.get_ticks_msec() - t_load, str(job["us"].map(func(u): return u / 1000))])
	track = job["track"]
	curve = track["curve"]
	Track.apply_lod(track["node"], GameState.lod_ranges())
	track["node"].process_mode = Node.PROCESS_MODE_PAUSABLE
	world.add_child(track["node"])
	_setup_environment()

	_loading.progress = 0.72
	await get_tree().process_frame

	var car_id := GameState.current_car
	var pc := PlayerCar.new()
	pc.process_mode = Node.PROCESS_MODE_PAUSABLE
	pc.track = track
	world.add_child(pc)
	pc.setup(car_id, GameState.get_config(car_id))
	pc.drift_mode = event_type == "drift"
	pc.drag_mode = event_type == "drag"
	# Tempo-Stufe gilt für alle gleich (Spieler und Gegner)
	pc.top_speed *= GameState.pace()
	pc.accel *= 0.8 + 0.2 * GameState.pace()
	pc.place(Track.xform_at(curve, track["start"], Track.LANES[2]))
	player = pc  # erst fertig eingerichtet sichtbar machen (Testwerkzeug fragt race.player ab)
	_loading.progress = 0.77
	await get_tree().process_frame
	if mood["rain"]:
		_rain = Moods.rain([200, 340, 520][GameState.gv("fx")])
		player.cam.add_child(_rain)

	# Gegner mit zufälligem Tuning. Wie in NFSU fahren sie Autos passend zur Stufe des Events (anfangs Kleinwagen,
	# zuletzt alles bis zum Kaze TT); Können nach Stufe, Schwierigkeit (Einstellungen) und leicht steigend mit Siegen.
	var rng := RandomNumberGenerator.new()
	rng.seed = race["seed"] * 31 + GameState.wins
	var lanes := [Track.LANES[0], Track.LANES[1], Track.LANES[3]]
	var tier: int = race.get("tier", 1)
	var diff: int = GameState.difficulty
	var difficulty: float = [0.0, 0.84, 0.88, 0.92][tier] + [-0.11, 0.0, 0.05][diff] + minf(GameState.total_wins(), 10) * 0.004
	var pool: Array = Catalog.CAR_ORDER.filter(func(id): return Catalog.CARS[id]["top_speed"] <= [0.0, 61.0, 70.0, 99.0][mini(tier + (1 if diff == 2 else 0), 3)])
	if event_type == "drift":
		# Drift: allein, Zielpunkte je nach Stufe, Schwierigkeit und Zahl der Kurven
		drift_targets = Catalog.drift_targets(race, diff)
		_build_drift_zones()
	for i in (0 if event_type == "drift" else 3):
		var id: String = pool[rng.randi() % pool.size()]
		var cfg := {}
		for cat in Catalog.PART_ORDER:
			if cat != "finish":  # Lackart ohne Zufallszahl: sonst änderten sich seit 2.19 alle Gegnerfelder
				cfg[cat] = rng.randi() % Catalog.PARTS[cat]["options"].size()
		cfg["finish"] = (int(race["seed"]) + i * 3 + GameState.wins) % Catalog.PARTS["finish"]["options"].size()
		var ai := AICar.new()
		ai.process_mode = Node.PROCESS_MODE_PAUSABLE
		ai.player = player
		ai.finish = track["finish"]
		ai.traffic = traffic
		ai.crossing = track["crossing"]
		world.add_child(ai)
		var top: float = Catalog.CARS[id]["top_speed"] * (0.95 + 0.03 * i) * GameState.pace()
		# Drag: alle nebeneinander an der Linie
		var start_d: float = track["start"] if event_type == "drag" else track["start"] + (i - 1) * 4.0
		ai.drag = event_type == "drag"
		ai.setup(track, id, cfg, start_d, lanes[i], top, difficulty + rng.randf_range(-0.025, 0.025))
		# Gummiband: liegst du hinten, werden sie etwas langsamer; führst du, holen sie auf Leicht gar nicht,
		# auf Normal etwas und nur auf Schwer stark auf
		ai.rubber = [Vector2(0.82, 1.0), Vector2(0.88, 1.07), Vector2(0.9, 1.15)][diff]
		# Abkürzungen sparen bis zu einem Fünftel der Zeit: in den ersten Rennen (1 Stern) kennen die Gegner
		# sie noch nicht, danach nehmen sie sie auf Leicht selten
		ai.shortcut_k = 0.0 if tier <= 1 else [0.3, 0.8, 1.0][diff]
		ai.accel *= 0.8 + 0.2 * GameState.pace()
		ai.set_meta("hud_col", _hud_col(Builder.paint_color(id, cfg)))
		ais.append(ai)
		_loading.progress = 0.77 + 0.05 * (i + 1)
		await get_tree().process_frame

	for ai in ais:
		ai.rivals = ais
	if track["crossing"]:
		track["crossing"].player = player
	_setup_hall()
	player.audio.bus = "Hall"
	for ai in ais:
		ai.set_bus("Hall")
	for n in get_tree().get_nodes_in_group("ambient"):
		n.target = player
	# Verkehr nach Schwierigkeit: leicht ohne, mittel wenig, schwer voll
	if event_type == "drag" and race.get("tier", 1) >= 2:
		_spawn_drag_traffic()
	elif event_type != "drift" and race.get("tier", 1) >= 2:
		_spawn_traffic()
	if not traffic.is_empty():
		Traffic.prepare_sound()
	_loading.progress = 0.94
	await get_tree().process_frame
	_build_hud()
	show = RaceShow.new()
	show.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.add_child(show)
	show.setup(track, player, 0.0)
	# Kameraflug übers Startfeld (bei Testläufen mit Kommandozeilen-Argumenten nur mit --intro)
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or args.has("--intro"):
		state = State.INTRO
		hud_layer.visible = false
		_build_title()
		show.start_intro()
		Music.hold_toast(true)
	else:
		show.ready_set()
		Music.hold_toast(false)
	if RenderingServer.get_current_rendering_method() == "gl_compatibility" and not OS.get_cmdline_user_args().has("--nowarmup"):
		await _warmup()
	if OS.get_cmdline_user_args().has("--loadlog"):
		print("LOAD gesamt %d ms" % (Time.get_ticks_msec() - t_load))
	world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await get_tree().process_frame
	_loading.finish()
	_loading = null
	get_tree().paused = false
	_warming = false


## Im Browser (WebGL) übersetzt die Grafikkarte jeden Shader erst, wenn er zum ersten Mal im Bild ist; mitten im
## Rennen ruckelt das spürbar. Deshalb noch hinter dem Ladebildschirm: unsichtbare Kameras fahren die Strecke in
## beide Richtungen ab und schauen auf die Autos (Nitroflammen und Rad-Unschärfe kurz an), bis alles einmal
## gezeichnet wurde.
var _warming := false  # Laden und Vorzeichnen: keine Eingaben
var _loading: Loading


func _warmup() -> void:
	var cover: Node = _loading
	# Blickpunkte: alle Wege alle 150 m vorwärts, alle 300 m rückwärts, dazu die Autos am Start
	var views := []
	for p in track["paths"]:
		var c: Curve3D = p["curve"]
		var len := c.get_baked_length()
		var d := 0.0
		while d < len:
			var f := Track.frame_at(c, d)
			var eye: Vector3 = f["pos"] + Vector3(0, f["y"] + 2.5, 0)
			views.append([eye, eye + f["fwd"] * 50.0])
			if fmod(d, 300.0) < 1.0:
				views.append([eye, eye - f["fwd"] * 50.0])
			d += 150.0
	for t in traffic:
		t.place()  # Verkehr steht sonst bis zum ersten Physik-Takt noch nicht auf der Straße
	var flames := []
	for car in [player] + ais:
		var back: Vector3 = car.global_transform.basis.z
		views.append([car.global_position + back * 7.0 + Vector3(0, 2.0, 0), car.global_position])
		for fl in car.model.get_meta("flames") + car.model.get_meta("blurs", []):
			if not fl.visible:
				fl.visible = true
				flames.append(fl)
	views.append([player.cam.global_position, player.cam.global_position - player.cam.global_transform.basis.z * 10.0, player.cam])
	var cams := []
	for i in 6:
		var vp := SubViewport.new()
		vp.size = Vector2i(192, 108)
		vp.world_3d = world.find_world_3d()
		vp.msaa_3d = world.msaa_3d
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var cam := Camera3D.new()
		cam.fov = 95.0
		cam.far = GameState.view_distance()
		vp.add_child(cam)
		cover.add_child(vp)
		cams.append(cam)
	# Tempo-Effekt (Bildschirm-Shader) einmal mitzeichnen: sonst wird er erst übersetzt, wenn man zum ersten Mal schnell
	# genug ist, und das Bild hakt (im Browser bis über 100 ms)
	var fxw := ColorRect.new()
	fxw.set_anchors_preset(Control.PRESET_FULL_RECT)
	var fxm: ShaderMaterial = fx_mat.duplicate()
	fxm.set_shader_parameter("blur", 0.05)
	fxm.set_shader_parameter("nitro", 0.5)
	fxm.set_shader_parameter("speed", 0.5)
	fxw.material = fxm
	cams[0].get_parent().add_child(fxw)
	var i := 0
	while i < views.size():
		for cam in cams:
			if i < views.size():
				var v: Array = views[i]
				if v.size() > 2:
					cam.global_transform = (v[2] as Camera3D).global_transform  # Regen hängt an der Fahrerkamera
				else:
					cam.look_at_from_position(v[0], v[1], Vector3.UP)
				i += 1
		_loading.progress = 0.95 + 0.05 * i / views.size()
		await get_tree().process_frame
	await get_tree().process_frame
	for fl in flames:
		fl.visible = false
	for c in cams:
		c.get_parent().queue_free()




## Drag: langsamer Verkehr auf allen Spuren in unsere Richtung, erst nach dem Start-Stück. Ausweichen per Spurwechsel.
func _spawn_drag_traffic() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = race["seed"] * 7 + 3
	var gap: Vector2 = Vector2(110.0, 190.0) if race.get("tier", 1) >= 3 else Vector2(170.0, 270.0)
	var d: float = track["start"] + 320.0
	while d < track["finish"] - 100.0:
		var t := Traffic.new()
		t.process_mode = Node.PROCESS_MODE_PAUSABLE
		t.curve = curve
		t.blocks = track["blocks"]
		t.progress = d
		t.lane = Track.LANES[rng.randi() % 4]
		t.dir = 1.0
		t.base_speed = rng.randf_range(12.0, 18.0)
		t.speed = t.base_speed
		t.track_length = track["length"]
		t.track = track
		world.add_child(t)
		t.setup(Traffic.KINDS[rng.randi() % Traffic.KINDS.size()], rng)
		traffic.append(t)
		d += rng.randf_range(gap.x, gap.y)


## Verkehr: rechts in Fahrtrichtung, links Gegenverkehr. Erst ein Stück nach dem Start.
## Mittlere Events (2 Sterne) mit halb so viel Verkehr wie schwere.
func _spawn_traffic() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = race["seed"] * 7 + 1
	var gap: float = 1.0 if race.get("tier", 1) >= 3 else 1.9
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
			t.track = track
			t.crossing = track["crossing"]
			world.add_child(t)
			t.setup(Traffic.KINDS[rng.randi() % Traffic.KINDS.size()], rng)
			traffic.append(t)
		d += rng.randf_range(45.0, 95.0) * gap
	# Gabelungen: zweispurig mit Gegenverkehr (deshalb dort kürzer, aber riskant)
	for p in track["paths"]:
		if p["kind"] != "fork":
			continue
		var fd := 25.0
		while fd < p["length"] - 25.0:
			var t := Traffic.new()
			t.process_mode = Node.PROCESS_MODE_PAUSABLE
			t.curve = p["curve"]
			t.track = track
			t.path_id = p["id"]
			t.progress = fd
			t.lane = 2.4 if rng.randf() < 0.45 else -2.4
			t.dir = 1.0 if t.lane > 0.0 else -1.0
			t.base_speed = rng.randf_range(9.0, 13.0)
			t.speed = t.base_speed
			t.track_length = p["length"]
			world.add_child(t)
			t.setup(Traffic.KINDS[rng.randi() % 6], rng)
			traffic.append(t)
			fd += rng.randf_range(30.0, 50.0) * gap


## Bus mit Hall für Motor und Effekte; im Tunnel wird der Hall aufgedreht
func _setup_hall() -> void:
	var idx := AudioServer.get_bus_index("Hall")
	if idx < 0:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "Hall")
		AudioServer.set_bus_send(idx, "Master")
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.55
		rv.damping = 0.35
		rv.spread = 0.8
		rv.hipass = 0.15
		rv.predelay_msec = 35.0
		rv.predelay_feedback = 0.3
		rv.dry = 1.0
		rv.wet = 0.0
		AudioServer.add_bus_effect(idx, rv)
	_reverb = AudioServer.get_bus_effect(idx, 0)
	_reverb.wet = 0.0
	for i in AudioServer.get_bus_effect_count(idx):
		if AudioServer.get_bus_effect(idx, i) is AudioEffectLowPassFilter:
			_lowpass = AudioServer.get_bus_effect(idx, i)
	if _lowpass == null:
		_lowpass = AudioEffectLowPassFilter.new()
		AudioServer.add_bus_effect(idx, _lowpass)
	_lowpass.cutoff_hz = 20000.0


func _exit_tree() -> void:
	Music.hold_toast(false)
	if _reverb:
		_reverb.wet = 0.0
	if _lowpass:
		_lowpass.cutoff_hz = 20000.0
	Engine.time_scale = 1.0


var mood: Dictionary = {}
var _rain: CPUParticles3D


func _setup_environment() -> void:
	mood = Moods.get_mood(race.get("mood", "neon"))
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
	# Glühen nur für wirklich helle Lichter, kein Weichzeichner über der ganzen Stadt
	env.glow_intensity = 0.6
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.15
	env.fog_enabled = true
	env.fog_light_color = mood["fog"]
	env.fog_density = mood["fog_d"]
	# Farbfilter der Stimmung
	env.adjustment_enabled = true
	env.adjustment_saturation = mood["sat"]
	env.adjustment_contrast = mood["con"]
	env.adjustment_brightness = mood["bri"]
	for m in Track._road_mats.values():
		(m as ShaderMaterial).set_shader_parameter("wet", mood["wet"])
	env.fog_sky_affect = 0.15
	# Spiegelungen und Umgebungsverdeckung nur, wenn die Grafikstufe sie vorsieht (die teuersten Effekte)
	env.ssr_enabled = GameState.gfx_available("ssr") and GameState.gv("ssr") > 0
	env.ssr_max_steps = maxi(GameState.gv("ssr"), 8)
	# Stufe "Niedrig": Spiegelungen in halber Auflösung (auf nasser Straße kaum zu unterscheiden, kostet ein Viertel)
	RenderingServer.environment_set_ssr_half_size(GameState.gv("ssr") < 32)
	env.ssao_enabled = GameState.gfx_available("ssao") and GameState.gv("ssao")
	# günstige Variante: Umgebungsverdeckung in halber Auflösung (die Rauheits-Stufe der Spiegelungen gibt es seit
	# Godot 4.7 nicht mehr)
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


## Titel während des Kameraflugs: Eventname groß unten, darunter Art und Fahrerfeld
## Startkarte während des Kameraflugs: farbiges Abzeichen der Art (wie in der Karriere-Liste), groß der Name,
## darunter in der Farbe der Art das Ziel, ganz unten Ort, Fahrerzahl und "Gas/Enter: los"
func _build_title() -> void:
	title_layer = CanvasLayer.new()
	title_layer.layer = 2
	add_child(title_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_layer.add_child(root)
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0.6)
	bar.anchor_top = 1.0
	bar.anchor_right = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_top = -92
	root.add_child(bar)
	var col: Color = UI.TYPE_COL.get(event_type, UI.CYAN)
	var line := ColorRect.new()
	line.color = col
	line.anchor_top = 1.0
	line.anchor_right = 1.0
	line.anchor_bottom = 1.0
	line.offset_top = -93
	line.offset_bottom = -91
	root.add_child(line)
	var kind := {"sprint": tr("SPRINT"), "circuit": tr("RUNDKURS · %d RUNDEN") % track["laps"], "drift": tr("DRIFT · %d RUNDEN") % track["laps"],
		"drag": tr("DRAG")}
	var badge_text: String = kind.get(event_type, "SPRINT")
	var tier: int = race.get("tier", 1)
	var bd := Control.new()
	bd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bd.anchor_top = 1.0
	bd.anchor_right = 1.0
	bd.anchor_bottom = 1.0
	bd.offset_top = -86
	bd.offset_bottom = -70
	root.add_child(bd)
	bd.draw.connect(func():
		var w := UI.badge_width(badge_text, 11, tier)
		UI.draw_badge(bd, Vector2((bd.size.x - w) / 2.0, 0.0), event_type, badge_text, 11, tier,
			race["name"] in GameState.won_events))
	var t := _label(root, 30, HORIZONTAL_ALIGNMENT_CENTER)
	t.text = tr(race["name"]).to_upper()
	t.anchor_top = 1.0
	t.anchor_right = 1.0
	t.anchor_bottom = 1.0
	t.offset_top = -70
	t.offset_bottom = -34
	var g := _label(root, 12, HORIZONTAL_ALIGNMENT_CENTER)
	g.text = tr("ZIEL: ") + _goal_text().to_upper().trim_suffix(".")
	g.label_settings.font_color = col
	g.anchor_top = 1.0
	g.anchor_right = 1.0
	g.anchor_bottom = 1.0
	g.offset_top = -34
	g.offset_bottom = -18
	var sub := _label(root, 9, HORIZONTAL_ALIGNMENT_CENTER)
	var who := tr("ALLEIN") if event_type == "drift" else tr("4 FAHRER")
	var keys := tr("A/D SPUR · S/X SCHALTEN") if event_type == "drag" else ""
	var bits := [race.get("town", "").to_upper(), who]
	if keys != "":
		bits.append(keys)
	if race.has("city"):
		bits.append(tr("Karte © OpenStreetMap-Mitwirkende"))
	bits.append(tr("Gas/Enter: los"))
	sub.text = "   ·   ".join(bits)
	sub.modulate = Color(0.7, 0.85, 1.0)
	sub.anchor_top = 1.0
	sub.anchor_right = 1.0
	sub.anchor_bottom = 1.0
	sub.offset_top = -17
	sub.offset_bottom = -4


## Ziel des Events in einem Satz (Startkarte und Countdown)
func _goal_text() -> String:
	match event_type:
		"circuit":
			return tr(Catalog.EVENT_TYPES["circuit"]["goal"]) % track["laps"]
		"drift":
			return tr("%d Punkte für Platz 1 (Platz 3 ab %d).") % [drift_targets[2], drift_targets[0]]
	return tr(Catalog.EVENT_TYPES.get(event_type, Catalog.EVENT_TYPES["sprint"])["goal"])


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


## Drehzahlmesser rechts: unten (Tastatur) oder oben (Handy, unten liegen die Knöpfe), skaliert um k
func _place_tacho(tacho: Control, k: float, top: bool) -> void:
	tacho.scale = Vector2(k, k)
	tacho.anchor_left = 1.0
	tacho.anchor_right = 1.0
	tacho.anchor_top = 0.0 if top else 1.0
	tacho.anchor_bottom = tacho.anchor_top
	var s: float = TACHO.SIZE
	tacho.offset_left = -s * k - 4.0
	tacho.offset_right = tacho.offset_left + s
	tacho.offset_top = 4.0 if top else -s * k - 2.0
	tacho.offset_bottom = tacho.offset_top + s


## Lackfarbe für Radar und Fortschritt: dunkle Lacke (Schwarz, Candyblau) aufgehellt, damit man sie sieht
static func _hud_col(c: Color) -> Color:
	return Color.from_hsv(c.h, minf(c.s, 0.85), maxf(c.v, 0.8))


func _build_hud() -> void:
	# Bewegungsunschärfe in der 3D-Auflösung rechnen (Ebene im Welt-Viewport), nicht im ganzen Fenster: auf
	# hochauflösenden Bildschirmen sind das nur noch ein Viertel bis die Hälfte der Bildpunkte, und die Kopie des
	# Bildes für den Effekt entfällt im großen Fenster ganz
	var fx_layer := CanvasLayer.new()
	fx_layer.layer = 0
	world.add_child(fx_layer)
	var bar_layer := CanvasLayer.new()
	bar_layer.layer = 0
	add_child(bar_layer)
	var fx := ColorRect.new()
	fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_mat = ShaderMaterial.new()
	fx_mat.shader = SPEED_FX
	fx.material = fx_mat
	fx.visible = false
	fx_layer.add_child(fx)
	_fx_rect = fx
	for top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if top else 1.0
		bar.anchor_bottom = bar.anchor_top
		bar_layer.add_child(bar)
		_bars.append(bar)

	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	hud_layer = layer
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# Platz, Zeit, Runde oben links, Fortschritt mit allen Fahrern oben mittig
	var info := HUD_INFO.new()
	info.drift = event_type == "drift"
	info.racers = ais.size() + 1
	info.laps = track["laps"]
	info.bar_laps = track["laps"] if track["loop"] else 1
	info.title = tr(race["name"]).to_upper()
	info.show_bar = event_type != "drag"
	root.add_child(info)
	hud["info"] = info
	# Radar unten links (im Drag nicht, da geht es nur geradeaus)
	if event_type != "drag":
		var mm := MINIMAP.new()
		root.add_child(mm)
		mm.setup(track, player, ais)
		mm.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		mm.offset_left = 8.0
		mm.offset_right = 8.0 + MINIMAP.SIZE
		mm.offset_top = -MINIMAP.SIZE - 8.0
		mm.offset_bottom = -8.0
		hud["map"] = mm
	# Musiktitel unten mittig, blendet nach ein paar Sekunden aus
	hud["help"] = _label(root, 9, HORIZONTAL_ALIGNMENT_RIGHT)
	hud["help"].set_anchors_preset(Control.PRESET_TOP_RIGHT)
	hud["help"].position = Vector2(-250, 6)
	hud["help"].size = Vector2(240, 60)
	hud["help"].text = tr("W/S Gas/Bremse  A/D Lenken\nLeertaste Handbremse  Shift Nitro\nC Kamera  R Zurücksetzen  M Musik\nF Vollbild  Esc Pause")
	hud["help"].modulate.a = 0.7
	if event_type == "drag":
		hud["help"].text = tr("W Gas  S hoch-, X runterschalten\nA/D Spur wechseln  Shift Nitro\nC Kamera  F Vollbild  Esc Pause")

	# Drehzahlmesser unten rechts
	var tacho := Control.new()
	tacho.set_script(TACHO)
	tacho.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tacho)
	hud["tacho"] = tacho
	tacho.drag = event_type == "drag"
	# Drag: größer, mit grünem Schaltbereich und Temperatur
	_place_tacho(tacho, 1.1 if event_type == "drag" else 1.0, false)

	if GameState.touch_ui():
		# Handy/Tablet: Knöpfe links und rechts unten, Drehzahlmesser klein oben rechts (unten wäre das Auto
		# verdeckt), Tastaturhilfe aus
		var tc := TOUCH.new()
		tc.drag = event_type == "drag"
		add_child(tc)
		hud["help"].visible = false
		_place_tacho(tacho, 0.64 * (1.15 if event_type == "drag" else 1.0), true)
		# Radar links unter der Platzanzeige (unten links liegen die Lenkknöpfe)
		if hud.has("map"):
			var mm: Control = hud["map"]
			mm.scale = Vector2(0.8, 0.8)
			mm.set_anchors_preset(Control.PRESET_TOP_LEFT)
			mm.offset_left = 10.0
			mm.offset_top = 112.0
			mm.offset_right = mm.offset_left + MINIMAP.SIZE
			mm.offset_bottom = mm.offset_top + MINIMAP.SIZE

	hud["center"] = _label(root, 64, HORIZONTAL_ALIGNMENT_CENTER)
	hud["center"].label_settings.font = UI.font("wide", 0.2)
	hud["center"].anchor_left = 0.5
	hud["center"].anchor_right = 0.5
	hud["center"].anchor_top = 0.5
	hud["center"].anchor_bottom = 0.5
	hud["center"].offset_left = -200
	hud["center"].offset_right = 200
	hud["center"].offset_top = -90
	hud["center"].offset_bottom = 0
	# Unter dem Countdown: Art und Ziel in der Farbe der Art, bis kurz nach dem Start
	hud["goal"] = _label(root, 13, HORIZONTAL_ALIGNMENT_CENTER)
	hud["goal"].label_settings.font = UI.font("cond", 0.2)
	hud["goal"].label_settings.font_color = UI.TYPE_COL.get(event_type, UI.CYAN)
	hud["goal"].text = tr(Catalog.EVENT_TYPES[event_type]["label"]).to_upper() + "  ·  " + _goal_text().to_upper().trim_suffix(".")
	hud["goal"].anchor_left = 0.5
	hud["goal"].anchor_right = 0.5
	hud["goal"].anchor_top = 0.5
	hud["goal"].anchor_bottom = 0.5
	hud["goal"].offset_left = -260
	hud["goal"].offset_right = 260
	hud["goal"].offset_top = 2
	hud["goal"].offset_bottom = 22
	hud["goal"].visible = false

	# Unten links über dem Radar (Drag: ohne Radar direkt in der Ecke; Handy: unter dem Radar oben links): Ort,
	# Drift-Kette im Drift-Event, darüber die Punkte-Zeilen. In der Bildmitte steht nur Countdown und Ergebnis.
	var corner := VBoxContainer.new()
	corner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	corner.add_theme_constant_override("separation", 0)
	corner.alignment = BoxContainer.ALIGNMENT_END
	corner.anchor_top = 1.0
	corner.anchor_bottom = 1.0
	corner.offset_left = 10.0
	corner.offset_right = 290.0
	corner.offset_bottom = -12.0 - (MINIMAP.SIZE if hud.has("map") else 0.0)
	corner.offset_top = corner.offset_bottom - 150.0
	if GameState.touch_ui():
		corner.anchor_top = 0.0
		corner.anchor_bottom = 0.0
		corner.alignment = BoxContainer.ALIGNMENT_BEGIN
		corner.offset_top = 112.0 + (MINIMAP.SIZE * 0.8 + 4.0 if hud.has("map") else 0.0)
		corner.offset_bottom = corner.offset_top + 150.0
	root.add_child(corner)
	_feed = VBoxContainer.new()
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.add_theme_constant_override("separation", -2)
	corner.add_child(_feed)
	hud["drift"] = _label(corner, 16)
	hud["drift"].label_settings.font = UI.font("cond", 0.2)
	hud["drift"].label_settings.font_color = Color(1.0, 0.85, 0.2)
	hud["drift"].visible = event_type == "drift"
	hud["area"] = _label(corner, 11)
	hud["area"].label_settings.font = UI.font("cond", 0.2)
	hud["area"].label_settings.font_color = Color(0.85, 0.9, 1.0)
	hud["area"].modulate.a = 0.0
	# Drag: Schalttasten und Schaltergebnis links neben dem Drehzahlmesser
	if event_type == "drag":
		var sk := _label(root, 12, HORIZONTAL_ALIGNMENT_RIGHT)
		sk.label_settings.font = UI.font("cond", 0.2)
		sk.anchor_left = 1.0
		sk.anchor_right = 1.0
		sk.anchor_top = 1.0
		sk.anchor_bottom = 1.0
		sk.offset_right = -TACHO.SIZE * 1.1 - 8.0
		sk.offset_left = sk.offset_right - 220.0
		sk.offset_bottom = -24.0
		sk.offset_top = -78.0
		sk.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		hud["shift"] = sk
		if GameState.touch_ui():
			sk.visible = false  # Handy: Schaltknöpfe auf dem Bildschirm

	_build_pause(root)


func _process(dt: float) -> void:
	if get_tree().paused:
		return
	match state:
		State.INTRO:
			if show.intro_done():
				state = State.COUNTDOWN
				hud_layer.visible = true
				title_layer.queue_free()
				Music.hold_toast(false)
				player.cam.make_current()
				show.ready_set()
		State.COUNTDOWN:
			countdown -= dt
			var n := int(ceil(countdown - 1.0))
			hud["center"].text = str(n) if n > 0 else tr("LOS!")
			if n != _beep_n and n >= 0:
				# Startampel: drei runde Töne, bei LOS eine Oktave höher; die Musik ist bis dahin leiser
				_beep_n = n
				var b := Sfx.play("beep" if n > 0 else "beep_go", -8.0 if n > 0 else -6.0)
				if b:
					b.bus = "Master"  # Ansage, kein Hall
				if n == 0:
					Music.race_go()  # neuer Track zum Start
			hud["goal"].visible = true
			if countdown <= 1.0 and not player.controls_enabled:
				player.controls_enabled = true
				_launch_check()
				for ai in ais:
					ai.running = true
				show.go()
				state = State.RACING
		State.RACING:
			race_time += dt
			if countdown > 0.0:
				countdown -= dt
				if countdown <= 0.0:
					hud["center"].text = ""
			if hud["goal"].visible:
				# Ziel noch gut zwei Sekunden nach dem Start stehen lassen, dann ausblenden
				hud["goal"].modulate.a = clampf(1.0 - (race_time - 2.2) / 0.6, 0.0, 1.0)
				hud["goal"].visible = race_time < 2.8
		State.FINISHED:
			pass

	player_progress = player.total
	# Für Gegner und Verkehr: Position auf dem eigenen Weg, Querlage ohne Mittelstreifen
	var on_main: bool = player.path_id == 0
	var p_lat: float = Track.logical_lat(track, player.progress, player.lateral) if on_main else player.lateral
	var p_d: float = player.progress if on_main else (player.loc["d"] if not player.loc.is_empty() else 0.0)
	for ai in ais:
		ai.player_progress = player.progress
		ai.player_total = player_progress
		ai.player_lateral = p_lat
		ai.player_path = player.path_id
		if ai.total >= track["finish"] and ai.finish_time < 0.0:
			ai.finish_time = race_time
			finish_order.append(ai)
	for t in traffic:
		t.player_progress = p_d
		t.player_lateral = p_lat
		t.player_path = player.path_id
		t.player_pos = player.global_position
	if event_type == "drift":
		_update_drift(dt)
	elif state == State.RACING:
		_check_near_miss()
	if event_type == "drag":
		_update_drag()
	if state == State.RACING and player_progress >= track["finish"]:
		_on_player_finished()

	_update_world(dt)
	_update_hud()
	_update_cinema(dt)


## Verkehr hören: die nächsten paar Autos im Umkreis von 80 m haben Motor und Abrollen an (Dopplereffekt im
## Vorbeifahren), alle anderen sind still. Alle Viertelsekunde neu verteilt.
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
	for t in traffic:
		t.sound(on.has(t), "Hall")


## Tunnel: dunkler, Hall an, Wusch beim Reinfahren. Viertel: Name einblenden.
func _update_world(dt: float) -> void:
	_update_traffic_sound(dt)
	var tun := Track.tunnel_at(track, player.progress) if player.path_id == 0 else {}
	var inside := not tun.is_empty()
	if inside != _in_tunnel:
		_in_tunnel = inside
		var v := absf(player.speed_fwd)
		if v > 15.0:
			Sfx.play("tunnel", -16.0 + minf(v / 6.0, 10.0), 0.9 if inside else 1.15)
		if inside:
			_show_area(tun["name"])
	_tunnel_k = move_toward(_tunnel_k, 1.0 if inside else 0.0, dt * 2.5)
	if _rain:
		_rain.emitting = not inside  # im Tunnel regnet es nicht
	env.ambient_light_energy = lerpf(mood["amb_e"], 0.08, _tunnel_k)
	moon.light_energy = lerpf(mood["moon_e"], 0.0, _tunnel_k)
	if _reverb:
		_reverb.wet = lerpf(0.0, 0.3, _tunnel_k)
	var city: Dictionary = track["city"]
	if not city.is_empty():
		# Orts-Strecke: echter Straßenname beim Abbiegen
		var pd: float = fposmod(player.progress, track["length"]) if track["loop"] else player.progress
		var si := -1
		var streets: Array = city["streets"]
		for i in streets.size():
			if pd >= streets[i][0] - 5.0:
				si = i
		if si != _district_i and si >= 0 and player.path_id == 0:
			if _district_i < 0 or streets[si][2] != streets[_district_i][2]:
				_show_area(streets[si][2].to_upper())
			_district_i = si
	else:
		var arr: Array = track["districts"]
		var di := clampi(int(player.progress / Track.DISTRICT_LEN), 0, arr.size() - 1)
		if di != _district_i:
			if _district_i < 0 or arr[di] != arr[_district_i]:
				_show_area(tr(Track.DISTRICTS[arr[di]]["name"]))
			_district_i = di
	if _area_t > 0.0:
		_area_t -= dt
		hud["area"].modulate.a = 0.8 * clampf(_area_t / 0.6, 0.0, 1.0) * clampf((4.0 - _area_t) / 0.3, 0.0, 1.0)


func _show_area(text: String) -> void:
	hud["area"].text = text
	_area_t = 4.0


func _place() -> int:
	if event_type == "drift":
		var pts := drift_score + drift_chain * _drift_mult()
		var place := 4
		for tgt in drift_targets:
			if pts >= tgt:
				place -= 1
		return place
	if state == State.FINISHED:
		var i := finish_order.find("player")
		return i + 1 if i >= 0 else 4  # ausgefallen
	var place := 1
	for ai in ais:
		if ai.finish_time >= 0.0 or ai.total > player_progress:
			place += 1
	return place


# --- Drift-Wertung -----------------------------------------------------------------

func _drift_mult() -> int:
	return mini(1 + int(drift_chain_t / 2.0), 5)


## Querfahren füllt die Kette: (Winkel - 10°) x Tempo, erst ab 12° zählt es als Drift (leichtes Rutschen nicht).
## Nach 1,2 s ohne Drift wird die Kette mal Multiplikator gutgeschrieben; ein harter Einschlag kostet sie ganz.
func _update_drift(dt: float) -> void:
	if state != State.RACING:
		return
	if player.crashes != _last_crashes or player.wall_hits != _last_walls:
		_last_crashes = player.crashes
		_last_walls = player.wall_hits
		if drift_chain > 0.0:
			_flash(tr("BANDE: KETTE VERLOREN"), Color(1.0, 0.3, 0.3))
		drift_chain = 0.0
		drift_chain_t = 0.0
	var kmh := player.velocity.length() * 3.6
	if player.drifting and player.drift_angle >= 12.0 and kmh > 35.0 and not player.airborne:
		var ang := clampf(player.drift_angle, 0.0, 60.0)
		# Bonuszone wie in Underground: am Außenrand der Kurven (leuchtender Streifen) zählt der Drift doppelt
		in_zone = _in_drift_zone()
		drift_chain += (ang - 10.0) * kmh / 100.0 * dt * (2.0 if in_zone else 1.0)
		drift_chain_t += dt
		drift_idle = 0.0
	else:
		in_zone = false
		drift_idle += dt
		if drift_chain > 0.0 and drift_idle > 1.2:
			_bank_drift()
	if _zone_mat:
		_zone_k = move_toward(_zone_k, 1.0 if in_zone else 0.0, dt * 6.0)
		_zone_mat.set_shader_parameter("active", _zone_k)


## Bonuszonen: Außenrand jeder engeren Kurve (Radius unter 75 m) der Hauptstrecke, je eine aufgemalte Außenspur (seit 2.24 statt eines leuchtenden Streifens)
## von 2,4 m Breite an der Bande. Kurvenrichtung aus der Drehung der Fahrtrichtung über 10 m.
func _build_drift_zones() -> void:
	var curve: Curve3D = track["curve"]
	var length := curve.get_baked_length()
	var step := 2.0
	var marks := []  # je Abtastpunkt: Seite des Außenrands oder 0
	var d := 0.0
	while d < length:
		var fa := Track.frame_at(curve, d - 5.0)
		var fb := Track.frame_at(curve, d + 5.0)
		var turn: float = (fa["fwd"] as Vector3).signed_angle_to(fb["fwd"], Vector3.UP)  # > 0: Linkskurve
		marks.append(0 if absf(turn) < 10.0 / 75.0 else (1 if turn > 0.0 else -1))
		d += step
	# zusammenhängende Stücke derselben Seite; kurze Lücken schließen, Stummel weglassen, an den Enden verlängern
	var i := 0
	while i < marks.size():
		if marks[i] == 0:
			i += 1
			continue
		var side: int = marks[i]
		var j := i
		while j + 1 < marks.size() and (marks[j + 1] == side or (marks[j + 1] == 0 and j + 5 < marks.size() and marks.slice(j + 1, j + 6).has(side))):
			j += 1
		if (j - i) * step >= 12.0:
			_zones.append([maxf(i * step - 6.0, 0.0), minf(j * step + 8.0, length), side])
		i = j + 1
	if _zones.is_empty():
		return
	_zone_mat = ShaderMaterial.new()
	_zone_mat.shader = preload("res://shaders/drift_zone.gdshader")
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in _zones:
		var a: float = z[0]
		var b: float = z[1]
		var side: float = z[2]
		var prev := []
		var t := a
		while true:
			var f := Track.frame_at(curve, t)
			var hw := Track.hw(track, t)
			var fade := clampf(minf(t - a, b - t) / 5.0, 0.0, 1.0)
			var row := []
			for k in 2:
				var lat: float = side * (hw - 2.6 + 2.4 * k)
				var p: Vector3 = f["pos"] + (f["right"] as Vector3) * lat
				row.append([Vector3(p.x, f["y"] + 0.04, p.z), Vector2(float(k), t), fade])
			if not prev.is_empty():
				for q in [[prev[0], prev[1], row[1]], [prev[0], row[1], row[0]]]:
					for v in q:
						st.set_color(Color(1, 1, 1, v[2]))
						st.set_uv(v[1])
						st.set_normal(Vector3.UP)
						st.add_vertex(v[0])
			prev = row
			if t >= b:
				break
			t = minf(t + 1.5, b)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _zone_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)


func _in_drift_zone() -> bool:
	if player.path_id != 0:
		return false
	var d: float = fposmod(player.progress, (track["curve"] as Curve3D).get_baked_length()) if track["loop"] else player.progress
	for z in _zones:
		if d >= z[0] and d <= z[1]:
			var edge := Track.hw(track, d) - absf(player.lateral)
			return signf(player.lateral) == z[2] and edge < 3.2
	return false


## Perfekter Start: wer bei GO die Drehzahl im grünen Bereich hält, schießt los. Zu viel Gas: Räder drehen durch.
## Perfekter Start: kein Satz nach vorn, sondern gut eine Sekunde lang etwas mehr Zug (Kupplung schnalzt sauber).
## Zu viel Gas: die Räder drehen kurz durch und der Start zieht schwächer.
func _launch_check() -> void:
	if player.rpm > 5400.0 and player.rpm < 6900.0:
		player.launch(1.0)
		player.nitro = minf(player.nitro + 0.1, 1.0)
		_flash(tr("PERFEKTER START"), Color(0.4, 1.0, 0.5))
	elif player.rpm >= 6900.0:
		player.launch(-1.0)
		_flash(tr("ZU VIEL GAS"), Color(1.0, 0.5, 0.2))


## Near Miss: knapp an Verkehr vorbei (seitlich 1,7–3,4 m) bei hohem Tempo gibt Nitro, wie in Underground
func _check_near_miss() -> void:
	var fwd: Vector3 = -player.global_basis.z
	var right := Vector3(-fwd.z, 0, fwd.x)
	var fast := player.velocity.length() > 25.0
	for t in traffic:
		if t.wrecked:
			continue
		var rel: Vector3 = t.global_position - player.global_position
		var id: int = t.get_instance_id()
		if rel.length() > 30.0:
			_near.erase(id)
			continue
		var along := rel.dot(fwd)
		var side := absf(rel.dot(right))
		if fast and absf(along) < 2.5 and side > 1.7 and side < 3.4 and not _near.has(id):
			_near[id] = true
			_flash(tr("KNAPP VORBEI"), Color(1.0, 0.85, 0.2), 300)
			Sfx.play("whoosh", -12.0, randf_range(1.1, 1.3))


func _bank_drift() -> void:
	var pts := drift_chain * _drift_mult()
	drift_score += pts
	if pts >= 50.0:
		_flash(tr("DRIFT"), Color(1.0, 0.85, 0.2), int(pts))
	drift_chain = 0.0
	drift_chain_t = 0.0


func _update_hud() -> void:
	var sf := clampf(absf(player.speed_fwd) / player.top_speed, 0.0, 1.0)
	_update_speed_fx(sf)

	var info = hud["info"]
	info.place = _place()
	info.points = int(drift_score)
	if track["loop"]:
		info.lap = clampi(player.lap + 1, 1, track["laps"])
		if player.lap != _last_lap and player.lap > 0 and player.lap < track["laps"]:
			_flash(tr("LETZTE RUNDE") if player.lap == track["laps"] - 1 else tr("RUNDE %d") % (player.lap + 1), Color(0.4, 1.0, 0.5))
		_last_lap = player.lap
	info.time_text = _fmt(race_time)
	var span: float = track["finish"] - track["start"]
	info.bar_player = (player_progress - track["start"]) / span
	info.bar_cars.clear()
	for ai in ais:
		info.bar_cars.append([(ai.total - track["start"]) / span, ai.get_meta("hud_col")])
	# Tastenhilfe nur am Anfang (den Musiktitel zeigt music.gd kurz als Blase)
	if state == State.RACING:
		hud["help"].modulate.a = 0.7 * clampf((12.0 - race_time) / 1.5, 0.0, 1.0)
	var tacho = hud["tacho"]
	tacho.rpm = player.rpm
	tacho.speed_kmh = int(absf(player.speed_fwd) * 3.6)
	tacho.gear = "R" if player.reverse_gear or player.speed_fwd < -0.5 else ("N" if state == State.COUNTDOWN or state == State.INTRO else str(player.gear))
	tacho.nitro = player.nitro
	tacho.heat = player.engine_heat
	tacho.nitro_on = player.nitro_on
	if event_type == "drift":
		if drift_chain > 0.0:
			hud["drift"].text = "x%d   %d%s" % [_drift_mult(), int(drift_chain), tr("   ZONE x2") if in_zone else ""]
		else:
			var next := ""
			for i in drift_targets.size():
				if drift_score < drift_targets[i]:
					next = tr("Platz %d: %d") % [3 - i, drift_targets[i]]
					break
			hud["drift"].text = next
	# Punkte-Zeilen: Abkürzung, Sprung (mit Punkten), Drift im Rennen
	if player.path_id != _last_path:
		var kind: String = track["paths"][player.path_id]["kind"]
		if kind == "alley" or kind == "lake":
			_flash(tr("ABKÜRZUNG"), Color(1.0, 0.6, 0.1))
		elif kind == "fork":
			_flash(tr("GEGENVERKEHR"), Color(1.0, 0.75, 0.2))
		_last_path = player.path_id
	_last_rollovers = player.rollovers
	if player.landings != _last_landings:
		_last_landings = player.landings
		if player.last_air > 0.5 and state == State.RACING:
			var jp := int(player.last_air * 200.0 / 10.0) * 10
			_flash(tr("SPRUNG  %.1f s") % player.last_air, Color(0.4, 0.85, 1.0), jp)
	if event_type != "drift" and event_type != "drag":
		_update_style(get_process_delta_time())
	_update_feed(get_process_delta_time())


func _unhandled_input(event: InputEvent) -> void:
	if _warming:
		return
	if state == State.INTRO and (event.is_action_pressed("accelerate") or event.is_action_pressed("ui_accept")):
		show.skip_intro()
		return
	if event.is_action_pressed("camera"):
		player.toggle_camera()
		_flash(tr("Kamera: ") + tr(player.CAM_NAMES[player.cam_mode]), Color(0.85, 0.9, 1.0))
	elif event.is_action_pressed("reset_car") and state == State.RACING and event_type != "drag":
		var loc := Track.locate(track, player.global_position)
		var p: Dictionary = loc["path"]
		var half: float = p["half_w"] - 2.0
		player.place(Track.xform_at(p["curve"], loc["d"], clampf(loc["lat"], -half, half)))
	elif event.is_action_pressed("pause", false, true) and state != State.FINISHED:  # genau: Alt+Enter ist Vollbild
		_toggle_pause()


## Drag: Schaltvorgänge melden, Motortemperatur warnen, Totalschaden oder Motorschaden beenden das Rennen
var _heat_warned := false


var _shift_msg := ""
var _shift_col := Color.WHITE
var _shift_t := 0.0


func _update_drag() -> void:
	match player.shift_result:
		"perfect":
			_shift_note(tr("PERFEKT GESCHALTET"), Color(0.4, 1.0, 0.5))
		"good":
			_shift_note(tr("GUT GESCHALTET"), Color(1.0, 0.9, 0.4))
		"early":
			_shift_note(tr("ZU FRÜH GESCHALTET"), Color(1.0, 0.55, 0.2))
	player.shift_result = ""
	if player.engine_heat > 0.6 and not _heat_warned:
		_heat_warned = true
		_shift_note(tr("MOTOR HEISS – SCHALTEN!"), Color(1.0, 0.3, 0.2))
	elif player.engine_heat < 0.3:
		_heat_warned = false
	# Schalttasten stehen immer da; darüber kurz das Ergebnis des letzten Schaltvorgangs
	if hud.has("shift"):
		_shift_t = maxf(_shift_t - get_process_delta_time(), 0.0)
		var keys := tr("HOCHSCHALTEN  S   ·   RUNTER  X")
		var sk: Label = hud["shift"]
		sk.text = (_shift_msg + "\n" if _shift_t > 0.0 else "") + keys
		sk.label_settings.font_color = _shift_col if _shift_t > 0.0 else Color(0.85, 0.9, 1.0)


func _shift_note(text: String, col: Color) -> void:
	_shift_msg = text
	_shift_col = col
	_shift_t = 1.4
	if state == State.RACING and (player.totaled or player.blown):
		_on_player_dnf("TOTALSCHADEN" if player.totaled else "MOTORSCHADEN")


func _on_player_dnf(reason: String) -> void:
	state = State.FINISHED
	player.controls_enabled = false
	player.finished = true
	hud["center"].label_settings = hud["center"].label_settings.duplicate()
	hud["center"].label_settings.font_size = 40
	hud["center"].text = tr(reason)
	show.finish(false, false)
	get_tree().create_timer(3.0).timeout.connect(_show_result.bind(4, false, [], reason))


func _on_player_finished() -> void:
	state = State.FINISHED
	finish_order.append("player")
	player.controls_enabled = false
	player.finished = true
	var place := finish_order.find("player") + 1
	if event_type == "drift":
		_bank_drift()
		place = _place()
	var unlocked := []
	if place == 1:
		var stage := Catalog.stage_of(race["name"])
		var nxt := stage + 1
		var was_open := nxt < Catalog.STAGES.size() and GameState.stage_open(nxt)
		GameState.mark_won(race["name"])
		unlocked = GameState.register_win(event_type)
		if stage >= 0 and nxt < Catalog.STAGES.size():
			if not was_open and GameState.stage_open(nxt):
				unlocked.push_front(tr("STUFE %d: %d neue Events") % [nxt + 1, Catalog.STAGES[nxt]["events"].size()])
			elif not was_open:
				var left: int = Catalog.stage_need(stage) - GameState.stage_wins(stage)
				unlocked.push_front(tr("Noch %d Sieg bis Stufe %d" if left == 1 else "Noch %d Siege bis Stufe %d") % [left, nxt + 1])
	var key: String = race["name"]
	var best: float = GameState.best_times.get(key, 0.0)
	var new_best: bool
	if event_type == "drift":
		new_best = drift_score > best  # Drift: Bestwert sind Punkte
		if new_best:
			GameState.best_times[key] = drift_score
	else:
		new_best = best <= 0.0 or race_time < best
		if new_best:
			GameState.best_times[key] = race_time
	GameState.save_game()
	hud["center"].text = tr("SIEG!") if place == 1 else tr("%d. PLATZ" % place)
	# Zielszene: Verkehr in der Nähe verschwindet (sonst fährt er durch die Fans), Kamera kreist, Fans kommen
	for t in traffic.duplicate():
		if t.global_position.distance_to(player.global_position) < 180.0:
			traffic.erase(t)
			t.queue_free()
	# Die Platzierung steht fest: Gegner verschwinden aus der Szene, statt durch die Fans zu fahren
	for ai in ais:
		ai.visible = false
		ai.process_mode = Node.PROCESS_MODE_DISABLED
		ai.collision_layer = 0
	show.finish(place == 1)
	get_tree().create_timer(4.5).timeout.connect(_show_result.bind(place, new_best, unlocked))


func _show_result(place: int, new_best: bool, unlocked: Array, dnf := "") -> void:
	var panel := PanelContainer.new()
	panel.theme = UI.theme()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-150, 0)
	panel.custom_minimum_size = Vector2(300, 0)
	hud["center"].get_parent().add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	var t := _label(vb, 14, HORIZONTAL_ALIGNMENT_CENTER)
	t.text = tr("Zeit  %s%s") % [_fmt(race_time), tr("   NEUE BESTZEIT") if new_best else ""]
	if dnf != "":
		t.text = tr("Ausgefallen: ") + tr(dnf).capitalize()
	if event_type == "drift":
		t.text = tr("Punkte  %d%s") % [int(drift_score), tr("   NEUER REKORD") if new_best else ""]
		var tg := _label(vb, 10, HORIZONTAL_ALIGNMENT_CENTER)
		tg.text = tr("Platz 3: %d   Platz 2: %d   Platz 1: %d") % drift_targets
	if place == 1:
		var w := _label(vb, 11, HORIZONTAL_ALIGNMENT_CENTER)
		w.text = (tr("Driftsiege gesamt: %d") % GameState.drift_wins) if event_type == "drift" else (tr("Rennsiege gesamt: %d") % GameState.wins)
		if unlocked.size() > 0:
			var u := _label(vb, 11, HORIZONTAL_ALIGNMENT_CENTER)
			var lines := unlocked.slice(0, 9)
			if unlocked.size() > 9:
				lines.append(tr("… und %d weitere") % (unlocked.size() - 9))
			u.text = tr("FREIGESCHALTET:\n") + "\n".join(lines)
			u.modulate = Color(0.4, 1.0, 0.5)
	else:
		var w := _label(vb, 11, HORIZONTAL_ALIGNMENT_CENTER)
		w.text = tr("Nur Platz 1 schaltet neue Teile frei.")
		if GameState.difficulty > 0:
			var h := _label(vb, 10, HORIZONTAL_ALIGNMENT_CENTER)
			h.text = tr("Zu schwer? Einstellungen > Schwierigkeit: Leicht")
			h.modulate = Color(0.7, 0.85, 1.0)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(hb)
	var again := Button.new()
	again.text = tr("NOCHMAL")
	again.pressed.connect(func(): get_tree().reload_current_scene())
	hb.add_child(again)
	var back := Button.new()
	back.text = tr("ZUR WELT") if GameState.in_world else "GARAGE"
	back.pressed.connect(func(): get_tree().change_scene_to_file(_back_scene()))
	hb.add_child(back)
	back.grab_focus.call_deferred()


## Nach dem Rennen: zurück in die Open World, wenn man von dort kam, sonst in die Garage
func _back_scene() -> String:
	return "res://scenes/world.tscn" if GameState.in_world else "res://scenes/garage.tscn"


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
	title.label_settings.font = UI.font("cond", 0.22)
	title.label_settings.font_color = UI.GREEN
	title.text = "PAUSE"
	for entry in [["Weiter", _toggle_pause], ["Vollbild", GameState.toggle_fullscreen],
			["Neustart", func(): _unpause(); get_tree().reload_current_scene()],
			["Zur Welt" if GameState.in_world else "Garage", func(): _unpause(); get_tree().change_scene_to_file(_back_scene())]]:
		var b := Button.new()
		b.text = tr(entry[0]).to_upper()
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(entry[1])
		pause_panel.add_child(b)


func _toggle_pause() -> void:
	var p := not get_tree().paused
	get_tree().paused = p
	if p:
		Engine.time_scale = 1.0  # Menü nicht in Zeitlupe; die Sprungkamera stellt sie danach wieder ein
	pause_panel.visible = p
	if p:
		(pause_panel.get_child(1) as Button).grab_focus()


func _unpause() -> void:
	get_tree().paused = false


func _fmt(t: float) -> String:
	return "%d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]



## Bewegungsunschärfe wie in NFS Underground (statt gezeichneter Tempolinien): ab gut 90 km/h verwischt der Bildrand
## in Fahrtrichtung, bis gut 230 km/h deutlich (seit 2.26 stärker und früher als vorher, ab 40 % der Höchstgeschwindigkeit
## mit höchstens einem Drittel davon), Lichter ziehen Spuren, der Rand dunkelt leicht ab; mit Nitro stärker; beim
## Einlenken zusätzlich seitlich (Drehung der Kamera). Stärke aus den Einstellungen (Aus/Dezent/Normal/Stark). Steht
## nichts an, ist das ganze Rechteck aus.
const BLUR_LEVEL := [0.0, 0.55, 1.0, 1.6]


func _update_speed_fx(sf: float) -> void:
	var dt := get_process_delta_time()
	var lvl: float = BLUR_LEVEL[GameState.motion_blur]
	_nitro_fx = move_toward(_nitro_fx, 1.0 if player.nitro_on else 0.0, dt * 4.0)
	var yaw: float = player.cam.global_rotation.y
	var rate := wrapf(yaw - _cam_yaw_prev, -PI, PI) / maxf(dt, 0.001)
	_cam_yaw_prev = yaw
	_swing = lerpf(_swing, clampf(rate * 0.012, -0.03, 0.03), 1.0 - exp(-dt * 10.0))
	var kmh: float = player.velocity.length() * 3.6
	var sk := smoothstep(90.0, 235.0, kmh)
	var blur := lvl * (0.115 * sk * sk + 0.075 * _nitro_fx)
	var sw := lvl * _swing * smoothstep(0.2, 0.5, sf)
	var nit := _nitro_fx if lvl > 0.0 else 0.0
	if _bars_k > 0.0 or state != State.RACING:
		blur = 0.0  # Sprungkamera, Countdown, Ziel: ruhiges Bild
		sw = 0.0
	_fx_rect.visible = blur + absf(sw) > 0.0004 or nit > 0.001
	if _fx_rect.visible:
		fx_mat.set_shader_parameter("blur", blur)
		fx_mat.set_shader_parameter("swing", sw)
		fx_mat.set_shader_parameter("nitro", nit)
		fx_mat.set_shader_parameter("speed", sk * minf(lvl, 1.0) if blur > 0.0 else 0.0)


## Sprungkamera: schwarze Balken oben und unten einfahren, Bewegungsunschärfe aus, Ton in der Zeitlupe dumpf
func _update_cinema(dt: float) -> void:
	var real := dt / maxf(Engine.time_scale, 0.01)
	_bars_k = move_toward(_bars_k, 1.0 if player.jump_cam else 0.0, real * 5.0)
	var h := get_viewport().get_visible_rect().size.y * 0.09 * smoothstep(0.0, 1.0, _bars_k)
	_bars[0].offset_bottom = h
	_bars[1].offset_top = -h
	if _lowpass:
		var slow := clampf((1.0 - Engine.time_scale) / 0.5, 0.0, 1.0)
		_lowpass.cutoff_hz = lerpf(20000.0, 900.0, slow)


## Neue Zeile unten links (höchstens vier, die älteste fällt raus). pts > 0: Punkte dazu, die füllen Nitro ein wenig
## (eine schöne Drift-Kette etwa ein Zehntel, gedeckelt, damit Driften kein Nitro-Automat wird).
func _flash(text: String, col: Color, pts := 0) -> void:
	if _feed == null:
		return
	var l := _label(_feed, 13)
	l.label_settings.font = UI.font("cond", 0.2)
	l.label_settings.font_color = col
	l.text = text + ("   +%d" % pts if pts > 0 else "")
	l.set_meta("t", 3.2)
	_feed.move_child(l, _feed.get_child_count() - 1)
	while _feed.get_child_count() > 4:
		var old := _feed.get_child(0)
		_feed.remove_child(old)
		old.queue_free()
	if pts > 0 and event_type != "drift":
		player.nitro = minf(player.nitro + minf(pts / 4000.0, 0.12) / player.nitro_cap, 1.0)


func _update_feed(dt: float) -> void:
	for l in _feed.get_children():
		var t: float = l.get_meta("t") - dt
		l.set_meta("t", t)
		l.modulate.a = clampf(t / 0.5, 0.0, 1.0)
		if t <= 0.0:
			_feed.remove_child(l)
			l.queue_free()


## Drift im Rennen (nicht im Drift-Event): Punkte wie im Drift-Event, gutgeschrieben, wenn der Drift sauber zu Ende
## ist; Wand oder Crash kosten die Kette.
func _update_style(dt: float) -> void:
	if state != State.RACING:
		_style_chain = 0.0
		return
	if player.crashes != _style_crashes or player.wall_hits != _style_walls:
		_style_crashes = player.crashes
		_style_walls = player.wall_hits
		_style_chain = 0.0
	var kmh := player.velocity.length() * 3.6
	if player.drifting and player.drift_angle >= 12.0 and kmh > 35.0 and not player.airborne:
		_style_chain += (clampf(player.drift_angle, 0.0, 60.0) - 10.0) * kmh / 100.0 * dt * 10.0
		_style_idle = 0.0
	else:
		_style_idle += dt
		if _style_chain > 0.0 and _style_idle > 0.8:
			var pts := int(_style_chain / 10.0) * 10
			if pts >= 50:
				_flash(tr("DRIFT"), Color(1.0, 0.85, 0.2), pts)
			_style_chain = 0.0
