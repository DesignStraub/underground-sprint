extends Node3D
## Events: Sprint und Rundkurs gegen 3 Gegner im Verkehr, Drift allein auf leerer Strecke mit Punkten.
## Strecke bauen, aufstellen, Countdown, HUD, Zieleinlauf, Ergebnis.

const Catalog := preload("res://scripts/catalog.gd")
const Track := preload("res://scripts/track_builder.gd")
const PlayerCar := preload("res://scripts/player_car.gd")
const AICar := preload("res://scripts/ai_car.gd")
const SPEED_FX := preload("res://shaders/speed_fx.gdshader")
const TACHO := preload("res://scripts/tacho.gd")
const PixelView := preload("res://scripts/pixel_view.gd")
const Traffic := preload("res://scripts/traffic_car.gd")
const SKY_SHADER := preload("res://shaders/night_sky.gdshader")
const RaceShow := preload("res://scripts/race_show.gd")

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
var _wall_bonus := false
var _near := {}  # Verkehrsautos, für die es schon einen Near Miss gab
var _last_lap := 0
var finish_order: Array = []  # "player" oder AI-Knoten in Zielreihenfolge

var fx_mat: ShaderMaterial
var hud := {}
var result_panel: Control
var _last_path := 0
var _last_landings := 0
var _flash_t := 0.0
var pause_panel: Control
var env: Environment
var moon: DirectionalLight3D
var _reverb: AudioEffectReverb
var _tunnel_k := 0.0
var _in_tunnel := false
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
	# 3D-Welt rendert in eine eigene (pixelige) Auflösung, die Oberfläche bleibt scharf
	var view_layer := CanvasLayer.new()
	view_layer.layer = -1
	add_child(view_layer)
	var pv := PixelView.new()
	view_layer.add_child(pv)
	world = pv.world

	track = Track.build(race)
	curve = track["curve"]
	Track.apply_lod(track["node"], GameState.q()["lod"])
	track["node"].process_mode = Node.PROCESS_MODE_PAUSABLE
	world.add_child(track["node"])
	_setup_environment()

	var car_id := GameState.current_car
	player = PlayerCar.new()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.track = track
	world.add_child(player)
	player.setup(car_id, GameState.get_config(car_id))
	player.drift_mode = event_type == "drift"
	player.drag_mode = event_type == "drag"
	# Tempo-Stufe gilt für alle gleich (Spieler und Gegner)
	player.top_speed *= GameState.pace()
	player.accel *= 0.8 + 0.2 * GameState.pace()
	Music.next()  # jedes Rennen mit einem neuen Track
	player.place(Track.xform_at(curve, track["start"], Track.LANES[2]))

	# Gegner mit zufälligem Tuning; Stärke nach Schwierigkeit des Events, leicht steigend mit deinen Siegen
	var rng := RandomNumberGenerator.new()
	rng.seed = race["seed"] * 31 + GameState.wins
	var lanes := [Track.LANES[0], Track.LANES[1], Track.LANES[3]]
	var difficulty: float = 0.84 + race.get("tier", 1) * 0.035 + minf(GameState.total_wins(), 10) * 0.006
	if event_type == "drift":
		# Drift: allein, Zielpunkte je nach Schwierigkeit und Zahl der Kurven (Erstabstimmung, nach Spielgefühl anpassen)
		var k: float = [1.0, 1.0, 1.35, 1.7][race.get("tier", 1)] * track["laps"] * race.get("corners", 12) / 24.0
		drift_targets = [int(700 * k / 10.0) * 10, int(1500 * k / 10.0) * 10, int(2600 * k / 10.0) * 10]
	for i in (0 if event_type == "drift" else 3):
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
		var top: float = Catalog.CARS[id]["top_speed"] * (0.95 + 0.03 * i) * GameState.pace()
		# Drag: alle nebeneinander an der Linie
		var start_d: float = track["start"] if event_type == "drag" else track["start"] + (i - 1) * 4.0
		ai.drag = event_type == "drag"
		ai.setup(track, id, cfg, start_d, lanes[i], top, difficulty + rng.randf_range(-0.03, 0.03))
		ai.accel *= 0.8 + 0.2 * GameState.pace()
		ais.append(ai)

	if track["crossing"]:
		track["crossing"].player = player
	_setup_hall()
	player.audio.bus = "Hall"
	for n in get_tree().get_nodes_in_group("ambient"):
		n.target = player
	# Verkehr nach Schwierigkeit: leicht ohne, mittel wenig, schwer voll
	if event_type == "drag" and race.get("tier", 1) >= 2:
		_spawn_drag_traffic()
	elif event_type != "drift" and race.get("tier", 1) >= 2:
		_spawn_traffic()
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
	else:
		show.ready_set()


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


func _exit_tree() -> void:
	if _reverb:
		_reverb.wet = 0.0


func _setup_environment() -> void:
	env = Environment.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.25, 0.4)
	env.ambient_light_energy = 0.26
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.88
	env.glow_enabled = true
	# Glühen nur für wirklich helle Lichter, kein Weichzeichner über der ganzen Stadt
	env.glow_intensity = 0.6
	env.glow_bloom = 0.02
	env.glow_hdr_threshold = 1.15
	env.fog_enabled = true
	env.fog_light_color = Color(0.09, 0.07, 0.16)
	env.fog_density = 0.0045
	env.fog_sky_affect = 0.15
	# Spiegelungen und Umgebungsverdeckung nur, wenn die Grafikstufe sie vorsieht (die teuersten Effekte)
	var q: Dictionary = GameState.q()
	env.ssr_enabled = q["ssr"] > 0
	env.ssr_max_steps = maxi(q["ssr"], 8)
	env.ssao_enabled = q["ssao"]
	# günstige Varianten: Spiegelungen ohne Unschärfe-Berechnung, Umgebungsverdeckung in halber Auflösung
	RenderingServer.environment_set_ssr_roughness_quality(RenderingServer.ENV_SSR_ROUGHNESS_QUALITY_DISABLED)
	RenderingServer.environment_set_ssao_quality(RenderingServer.ENV_SSAO_QUALITY_LOW, true, 0.5, 2, 50.0, 300.0)
	env.ssao_radius = 1.5
	env.ssao_intensity = 1.6
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	moon = DirectionalLight3D.new()
	moon.light_color = Color(0.55, 0.6, 1.0)
	moon.light_energy = 0.25
	moon.rotation_degrees = Vector3(-50, 30, 0)
	world.add_child(moon)


## Titel während des Kameraflugs: Eventname groß unten, darunter Art und Fahrerfeld
func _build_title() -> void:
	title_layer = CanvasLayer.new()
	title_layer.layer = 2
	add_child(title_layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_layer.add_child(root)
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0.55)
	bar.anchor_top = 1.0
	bar.anchor_right = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_top = -64
	root.add_child(bar)
	var t := _label(root, 30, HORIZONTAL_ALIGNMENT_CENTER)
	t.text = race["name"].to_upper()
	t.anchor_top = 1.0
	t.anchor_right = 1.0
	t.anchor_bottom = 1.0
	t.offset_top = -62
	t.offset_bottom = -26
	var kind := {"sprint": "SPRINT", "circuit": "RUNDKURS · %d RUNDEN" % track["laps"], "drift": "DRIFT · %d RUNDEN" % track["laps"],
		"drag": "DRAG · E/Q SCHALTEN"}
	var sub := _label(root, 11, HORIZONTAL_ALIGNMENT_CENTER)
	sub.text = "%s   ·   %s   ·   Gas/Enter: los" % [kind.get(event_type, "SPRINT"), "ALLEIN" if event_type == "drift" else "4 FAHRER"]
	if race.has("city"):
		sub.text = "%s   ·   %s   ·   Karte © OpenStreetMap-Mitwirkende   ·   Gas/Enter: los" % [race.get("town", "").to_upper(), kind.get(event_type, "SPRINT")]
	sub.modulate = Color(0.6, 0.85, 1.0)
	sub.anchor_top = 1.0
	sub.anchor_right = 1.0
	sub.anchor_bottom = 1.0
	sub.offset_top = -26
	sub.offset_bottom = -8


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
	hud_layer = layer
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
	hud["help"].text = "W/S Gas/Bremse  A/D Lenken\nLeertaste Handbremse  Shift Nitro\nC Kamera  R Zurücksetzen  M Musik\nF Vollbild  Esc Pause"
	hud["help"].modulate.a = 0.7
	if event_type == "drag":
		hud["help"].text = "W Gas  E/Q hoch-/runterschalten\nA/D Spur wechseln  Shift Nitro\nC Kamera  F Vollbild  Esc Pause"

	# Drehzahlmesser unten rechts
	var tacho := Control.new()
	tacho.set_script(TACHO)
	tacho.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	tacho.position = Vector2(-158, -168)
	tacho.size = Vector2(150, 150)
	tacho.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tacho)
	hud["tacho"] = tacho
	if event_type == "drag":
		# Drag: größerer Drehzahlmesser unten rechts mit grünem Schaltbereich und Temperatur
		tacho.drag = true
		tacho.scale = Vector2(1.2, 1.2)
		tacho.offset_left = -186.0
		tacho.offset_right = -36.0
		tacho.offset_top = -186.0
		tacho.offset_bottom = -36.0

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
	# Ortsname (Viertel, Tunnel) oben mittig
	hud["area"] = _label(root, 13, HORIZONTAL_ALIGNMENT_CENTER)
	hud["area"].anchor_left = 0.5
	hud["area"].anchor_right = 0.5
	hud["area"].offset_left = -160
	hud["area"].offset_right = 160
	hud["area"].offset_top = 20
	hud["area"].offset_bottom = 38
	hud["area"].label_settings.font_color = Color(0.85, 0.9, 1.0)
	hud["area"].modulate.a = 0.0

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
				player.cam.make_current()
				show.ready_set()
		State.COUNTDOWN:
			countdown -= dt
			var n := int(ceil(countdown - 1.0))
			hud["center"].text = str(n) if n > 0 else "GO!"
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


## Tunnel: dunkler, Hall an, Wusch beim Reinfahren. Viertel: Name einblenden.
func _update_world(dt: float) -> void:
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
	env.ambient_light_energy = lerpf(0.26, 0.08, _tunnel_k)
	moon.light_energy = lerpf(0.25, 0.0, _tunnel_k)
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
				_show_area(Track.DISTRICTS[arr[di]]["name"])
			_district_i = di
	if _area_t > 0.0:
		_area_t -= dt
		hud["area"].modulate.a = clampf(_area_t / 0.6, 0.0, 1.0) * clampf((3.0 - _area_t) / 0.3, 0.0, 1.0)


func _show_area(text: String) -> void:
	hud["area"].text = text
	_area_t = 3.0


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
			_flash("BANDE! KETTE VERLOREN", Color(1.0, 0.3, 0.3))
		drift_chain = 0.0
		drift_chain_t = 0.0
	var kmh := player.velocity.length() * 3.6
	if player.drifting and player.drift_angle >= 12.0 and kmh > 35.0 and not player.airborne:
		var ang := clampf(player.drift_angle, 0.0, 60.0)
		# Wand-Bonus: nah an der Bande driften zählt mehr
		var wall_dist := Track.hw(track, player.progress) + 0.1 - absf(player.lateral) - 1.0
		var bonus := wall_dist < 2.0
		if bonus and not _wall_bonus:
			_flash("WAND-BONUS", Color(0.4, 0.9, 1.0))
		_wall_bonus = bonus
		drift_chain += (ang - 10.0) * kmh / 100.0 * dt * (1.6 if bonus else 1.0)
		drift_chain_t += dt
		drift_idle = 0.0
	else:
		drift_idle += dt
		if drift_chain > 0.0 and drift_idle > 1.2:
			_bank_drift()


## Perfekter Start: wer bei GO die Drehzahl im grünen Bereich hält, schießt los. Zu viel Gas: Räder drehen durch.
func _launch_check() -> void:
	var fwd: Vector3 = -player.global_basis.z
	if player.rpm > 5400.0 and player.rpm < 6900.0:
		player.velocity += fwd * 9.0
		player.nitro = minf(player.nitro + 0.15, 1.0)
		_flash("PERFEKTER START", Color(0.4, 1.0, 0.5))
	elif player.rpm >= 6900.0:
		_flash("ZU VIEL GAS", Color(1.0, 0.5, 0.2))


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
			player.nitro = minf(player.nitro + 0.12, 1.0)
			_flash("NEAR MISS  +NOS", Color(1.0, 0.85, 0.2))
			Sfx.play("whoosh", -12.0, randf_range(1.1, 1.3))


func _bank_drift() -> void:
	var pts := drift_chain * _drift_mult()
	drift_score += pts
	if pts >= 50.0:
		_flash("+%d" % int(pts), Color(1.0, 0.85, 0.2))
	drift_chain = 0.0
	drift_chain_t = 0.0


func _update_hud() -> void:
	var sf := clampf(absf(player.speed_fwd) / player.top_speed, 0.0, 1.0)
	fx_mat.set_shader_parameter("lines", clampf((sf - 0.45) * 2.0, 0.0, 1.0) + (0.6 if player.nitro_on else 0.0))
	fx_mat.set_shader_parameter("blur", 1.0 if player.nitro_on else sf * 0.25)
	fx_mat.set_shader_parameter("nitro", 1.0 if player.nitro_on else 0.0)

	hud["pos"].text = "%d/4" % _place()
	if event_type == "drift":
		hud["pos"].text = "%d" % int(drift_score)
	if track["loop"]:
		var lap := clampi(player.lap + 1, 1, track["laps"])
		hud["race"].text = "%s   RUNDE %d/%d" % [race["name"].to_upper(), lap, track["laps"]]
		if player.lap != _last_lap and player.lap > 0 and player.lap < track["laps"]:
			_flash("LETZTE RUNDE" if player.lap == track["laps"] - 1 else "RUNDE %d" % (player.lap + 1), Color(0.4, 1.0, 0.5))
		_last_lap = player.lap
	hud["time"].text = _fmt(race_time)
	var tacho = hud["tacho"]
	tacho.rpm = player.rpm
	tacho.speed_kmh = int(absf(player.speed_fwd) * 3.6)
	tacho.gear = "R" if player.speed_fwd < -0.5 else ("N" if state == State.COUNTDOWN or state == State.INTRO else str(player.gear))
	tacho.nitro = player.nitro
	tacho.heat = player.engine_heat
	tacho.nitro_on = player.nitro_on
	hud["progress"].size.x = 198.0 * clampf((player_progress - track["start"]) / (track["finish"] - track["start"]), 0.0, 1.0)
	hud["drift"].text = "DRIFT  +NOS" if player.drifting else ("AIR" if player.airborne else "")
	if state == State.COUNTDOWN:
		hud["drift"].text = "Gas kurz vor GO = perfekter Start"
	if event_type == "drift":
		if drift_chain > 0.0:
			hud["drift"].text = "x%d   %d" % [_drift_mult(), int(drift_chain)]
		else:
			var next := ""
			for i in drift_targets.size():
				if drift_score < drift_targets[i]:
					next = "Platz %d: %d" % [3 - i, drift_targets[i]]
					break
			hud["drift"].text = next
	# Kurze Einblendungen: Abkürzung, Sprungweite, Kamera
	if player.path_id != _last_path:
		var kind: String = track["paths"][player.path_id]["kind"]
		if kind == "alley" or kind == "lake":
			_flash("ABKÜRZUNG!", Color(1.0, 0.6, 0.1))
		elif kind == "fork":
			_flash("ALTSTADT · GEGENVERKEHR!", Color(1.0, 0.75, 0.2))
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
	if state == State.INTRO and (event.is_action_pressed("accelerate") or event.is_action_pressed("ui_accept")):
		show.skip_intro()
		return
	if event.is_action_pressed("camera"):
		player.toggle_camera()
		_flash("Kamera: " + player.CAM_NAMES[player.cam_mode], Color(0.85, 0.9, 1.0))
	elif event.is_action_pressed("reset_car") and state == State.RACING and event_type != "drag":
		var loc := Track.locate(track, player.global_position)
		var p: Dictionary = loc["path"]
		var half: float = p["half_w"] - 2.0
		player.place(Track.xform_at(p["curve"], loc["d"], clampf(loc["lat"], -half, half)))
	elif event.is_action_pressed("pause") and state != State.FINISHED:
		_toggle_pause()


## Drag: Schaltvorgänge melden, Motortemperatur warnen, Totalschaden oder Motorschaden beenden das Rennen
var _heat_warned := false


func _update_drag() -> void:
	match player.shift_result:
		"perfect":
			_flash("PERFEKT GESCHALTET", Color(0.4, 1.0, 0.5))
		"good":
			_flash("GUT GESCHALTET", Color(1.0, 0.9, 0.4))
		"early":
			_flash("ZU FRÜH GESCHALTET", Color(1.0, 0.55, 0.2))
	player.shift_result = ""
	if player.engine_heat > 0.6 and not _heat_warned:
		_heat_warned = true
		_flash("MOTOR ÜBERHITZT – SCHALTEN!", Color(1.0, 0.3, 0.2))
	elif player.engine_heat < 0.3:
		_heat_warned = false
	if state == State.RACING and (player.totaled or player.blown):
		_on_player_dnf("TOTALSCHADEN" if player.totaled else "MOTORSCHADEN")


func _on_player_dnf(reason: String) -> void:
	state = State.FINISHED
	player.controls_enabled = false
	player.finished = true
	hud["center"].label_settings = hud["center"].label_settings.duplicate()
	hud["center"].label_settings.font_size = 40
	hud["center"].text = reason
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
		unlocked = GameState.register_win(event_type)
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
	hud["center"].text = "SIEG!" if place == 1 else "%d. PLATZ" % place
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
	if dnf != "":
		t.text = "Ausgefallen: " + dnf.capitalize()
	if event_type == "drift":
		t.text = "Punkte  %d%s" % [int(drift_score), "   NEUER REKORD" if new_best else ""]
		var tg := _label(vb, 10, HORIZONTAL_ALIGNMENT_CENTER)
		tg.text = "Platz 3: %d   Platz 2: %d   Platz 1: %d" % drift_targets
	if place == 1:
		var w := _label(vb, 11, HORIZONTAL_ALIGNMENT_CENTER)
		w.text = ("Driftsiege gesamt: %d" % GameState.drift_wins) if event_type == "drift" else ("Rennsiege gesamt: %d" % GameState.wins)
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
	for entry in [["Weiter", _toggle_pause], ["Vollbild", GameState.toggle_fullscreen],
			["Neustart", func(): _unpause(); get_tree().reload_current_scene()],
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
