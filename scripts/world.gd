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
const PauseSettings := preload("res://scripts/pause_settings.gd")
const TACHO := preload("res://scripts/tacho.gd")
const SPEED_FX := preload("res://shaders/speed_fx.gdshader")
const SKY_SHADER := preload("res://shaders/night_sky.gdshader")
const WorldMinimap := preload("res://scripts/world_minimap.gd")
const MapView := preload("res://scripts/world_map_view.gd")
const Secrets := preload("res://scripts/secrets.gd")
const HighwayRace := preload("res://scripts/highway_race.gd")  # Autobahn-Rennen von Stadt zu Stadt (seit 2.43)
const DriftMeter := preload("res://scripts/drift_meter.gd")  # Drift-Wertung mit Anzeige (seit 2.45)
const DriftZones := preload("res://scripts/drift_zones.gd")  # Driftzone in jeder Stadt (seit 2.45)
const Traffic := preload("res://scripts/traffic_car.gd")
const Challenger := preload("res://scripts/challenger_car.gd")
const Builder := preload("res://scripts/car_builder.gd")
const WorldTour := preload("res://scripts/world_tour.gd")
const WorldIntro := preload("res://scripts/world_intro.gd")
const Offroad := preload("res://scripts/offroad.gd")  # Gelände zum Austoben (seit 2.39)
const OffroadBuild := preload("res://scripts/offroad_build.gd")
const OffroadTest := preload("res://scripts/offroad_test.gd")
const DUEL_GAP := 300.0  # so viel Vorsprung entscheidet ein Duell

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
static var _tt_stage := 0  # Test --wtravel: 0 Karte öffnen, 1 Leertaste drücken, 2 gereist
var _tt_t := 0.0
static var target := -1  # auf der Karte gewähltes Ziel (Rennen), gilt für diese Sitzung
static var _travel_arrival := false  # Schnellreise: beim Neuladen den kurzen Anflug zeigen
static var _travel_to := -1  # Schnellreise (seit 2.42): Rennen, an dessen Stadteingang man nach dem Neuladen ankommt
static var _travel_xf := Transform3D.IDENTITY  # Springen von der Karte (seit 2.49): Ankunft hier nach dem Neuladen
static var _travel_xf_on := false
var _spawn_saved := false  # Start am gemerkten Ort (GameState.world_pos), nach dem Bau der Umgebung geprüft
var _spawn_src := "test"  # woher der Startpunkt kommt (Ausgabe beim Laden)
## Autobahn-Rennen (seit 2.43, highway_race.gd): geplante Rennen, das laufende, Startsäulen, Punkte der Gegner
var hw_defs: Array = []
var hrace: Node = null
var _hw_markers := {}  # Rennen -> Lichtsäule am Start
var _near_hw := -1
var hw_pins: Array = []  # Gegner auf der Minikarte (meta "off", solange kein Rennen läuft)

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
var settings_panel: PauseSettings  # Esc > Einstellungen (seit 2.52)
var fx_mat: ShaderMaterial
var _fx_rect: ColorRect
var _nitro_fx := 0.0
var _cam_yaw_prev := 0.0
var _swing := 0.0
var _area_t := 0.0
var _area_name := ""
var _district_entry := {}  # Strecke, deren Viertel gerade gilt
var _district_key := ""
var _ready_done := false
var traffic: Array = []
var _near := {}  # Verkehrsautos, für die es schon „knapp vorbei“ gab
var _near_chain := 0  # Knapp-vorbei-Kette (je höchstens 4 s Abstand)
var _near_chain_t := 0.0
# Drift in der freien Fahrt (seit 2.32, _update_world_drift): laufende Kette, Driftzeit (Multiplikator), Pause
var drift_meter: Control  # Drift-Wertung und Anzeige oben in der Mitte (seit 2.45)
var _dr_landings := 0
var _xp_save_t := 0.0
var _lu_t := 0.0  # Level-Einblendung
var _feed: VBoxContainer  # Einblendungen über der Minikarte (knapp vorbei)
var _tq: Array = []  # [Eintrag, Plan] wartet aufs Einsetzen (ein paar pro Bild, sonst ruckelt es beim Nachladen)
var _trng := RandomNumberGenerator.new()
var _traffic_snd_t := 0.0
var _leader_t := 0.0
var _segs: Array = []
var _rings: Array = []  # je Ring (0 innen, 1 außen) seine Stücke der Reihe nach
## Herausforderer (selten, nur auf der Autobahn): überholt dich, fährt vor dir her; dicht dran startet Enter ein Duell
var challenger: Node = null
var _ch_pin: Node3D  # Stellvertreter für die Minikarte (roter Punkt, solange es einen Herausforderer gibt)
var _ch_t := 0.0  # Sekunden freie Fahrt auf der Autobahn bis zum nächsten
var _duel := 0  # 0 keins (er fährt vor dir her), 1 Duell läuft, 2 entschieden (er fährt weg oder fällt zurück)
var _ch_prompt := false
var _off_ring_t := 0.0
var _ch_log := 0.0
var quiet := false  # Tests (--wtour): kein Verkehr, keine Herausforderer
## Anflug von oben nach dem Laden (world_intro.gd); solange er läuft: nicht fahren, nichts nachbauen, HUD aus
var _intro: Node = null
## Gelände (seit 2.39): Golfplatz und Kiesgrube, gebaut und nachgeladen von offroad_build.gd
var offroad_node: Node3D
var _offroad_shown := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameState.in_world = true
	quiet = Array(OS.get_cmdline_user_args()).any(func(a): return a.begins_with("--wtour") or a.begins_with("--drivebot") \
		or a.begins_with("--otest"))
	# headless (Tests): der Ersatz-Renderer ist nicht threadsicher, Meshes aus dem Bau-Thread zerschießen dort die RIDs
	_hitch = OS.get_cmdline_user_args().has("--hitch")
	_threads = not OS.has_feature("web") and OS.get_processor_count() > 1 and not OS.get_cmdline_user_args().has("--nothreads") \
		and DisplayServer.get_name() != "headless"
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
	hw_defs = HighwayRace.plan(layout)
	for c in layout["cities"]:
		entries.append({"kind": "city", "race": c["race"], "xf": c["xf"], "center": c["center"], "radius": c["radius"],
			"state": "none", "track": {}, "race_index": c["race_index"], "start": c["start_world"], "exit": c["exit_world"],
			"exit2": c.get("exit2_world", Vector3(1e9, 0, 1e9))})
	for s in layout["segments"]:
		var ri: int = s.get("ring", 0)
		while _rings.size() <= ri:
			_rings.append([])
		entries.append({"kind": "seg", "race": s["race"], "xf": Transform3D.IDENTITY, "center": s["center"], "radius": s["radius"],
			"state": "none", "track": {}, "race_index": -1, "seg_i": _rings[ri].size(), "ring": ri, "n": _segs.size()})
		_rings[ri].append(entries[-1])
		_segs.append(entries[-1])
	_trng.seed = 4711
	Traffic.prepare_sound()
	Traffic.prewarm()
	_setup_environment()

	var returning := has_return  # Rückkehr aus Rennen oder Garage (_spawn_xf setzt es zurück)
	var spawn := _spawn_xf()
	await _build_near(spawn.origin, cover)
	# gemerkter Ort (seit 2.42): nur, wenn dort noch eine Fahrbahn oder ein Gelände ist (nach einem Update kann dort jetzt
	# ein Haus stehen oder die Straße anders liegen), sonst am Eingang der zuletzt erreichten Stadt
	if _spawn_saved and not _spot_ok(spawn.origin):
		print("START: gemerkter Ort (%.0f, %.0f) nicht mehr befahrbar, Start am Stadteingang" % [spawn.origin.x, spawn.origin.z])
		spawn = _fallback_xf()
		_spawn_src = "Stadteingang statt gemerktem Ort"
		await _build_near(spawn.origin, cover)

	cover.get_meta("label").text = tr("Welt wird gebaut … Landschaft")
	await get_tree().process_frame
	land.build_near(spawn.origin)
	offroad_node.build_near(spawn.origin)
	var pc := PlayerCar.new()
	pc.process_mode = Node.PROCESS_MODE_PAUSABLE
	pc.track = _best_track(spawn.origin)
	world.add_child(pc)
	pc.setup(GameState.current_car, GameState.get_config(GameState.current_car))
	pc.top_speed *= GameState.pace()
	pc.accel *= GameState.accel_k()
	pc.place(spawn)
	pc.drift_mode = GameState.world_drift or OS.get_cmdline_user_args().has("--botdrift")
	print("START %s: (%.0f, %.1f, %.0f), Stadt zuletzt %s, entdeckt %d" % [_spawn_src, spawn.origin.x, spawn.origin.y,
		spawn.origin.z, GameState.last_town, GameState.towns_known.size()])
	_note_spot(spawn, true)  # hier geht es weiter, falls man gleich wieder beendet (etwa nach einer Schnellreise)
	_save_spot()
	var zoom := _intro_kind(returning)
	pc.controls_enabled = zoom == ""  # mit Anflug erst, wenn die Kamera hinter dem Auto ist
	player = pc
	land.target = pc
	offroad_node.target = pc
	player.cam.make_current()
	var pw := Track.poster_warm()  # Plakat-Stoff gleich übersetzen, nicht erst an der ersten Plakatwand (seit 2.34)
	if pw:
		player.cam.add_child(pw)
		get_tree().create_timer(2.0).timeout.connect(pw.queue_free)
	for n in get_tree().get_nodes_in_group("ambient"):
		n.target = player
	for e in entries:
		if e["state"] == "ready" and e["track"]["crossing"]:
			e["track"]["crossing"].player = player
	_set_active(_entry_of(pc.track))
	# bis die Warteschlange leer oder der Verkehr voll ist (sonst hing das Laden, wenn mehr geplant war als Platz)
	while not _tq.is_empty() and traffic.size() < TRAFFIC_MAX:
		_spawn_queued(100)
	_build_hud()
	if zoom != "":
		_intro = WorldIntro.new()
		add_child(_intro)
		_intro.setup(self, zoom)
	# ab jetzt Vinyl-Bilder (Herausforderer mitten in der Fahrt) im Hintergrund laden, nicht im Bild
	Builder.async_vinyls = true
	world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	Music.world_go("" if active.is_empty() or active["kind"] == "seg" else str(Catalog.RACES[active["race_index"]].get("town", "")))
	await get_tree().process_frame
	if _intro and WorldIntro.covered(player):
		_intro_done(true, false)  # im Tunnel: kein Anflug (von oben sähe man nur die Decke)
	if _intro:
		await _intro.prewarm()  # Ansichten von oben noch hinter dem Ladebild einmal zeichnen
	cover.queue_free()
	_ready_done = true
	if _intro:
		# HUD erst mit der Landung (hinter dem Ladebild war es sichtbar: so sind seine Shader schon übersetzt)
		hud["root"].modulate.a = 0.0
		_intro.start()
	if OS.get_cmdline_user_args().has("--worldcheck"):
		_world_check()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hwrace=") and not hw_defs.is_empty():
			get_tree().create_timer(1.0).timeout.connect(_start_highway.bind(int(a.substr(9)) % hw_defs.size()))
		if a.begins_with("--dzone="):  # Test: 40 m vor der Driftzone der Stadt von Rennen i (mit --wstart=i)
			get_tree().create_timer(0.5).timeout.connect(_dzone_test.bind(int(a.substr(8))))
	if OS.get_cmdline_user_args().has("--lvltest"):  # Test: Bild der Level-Anzeige
		get_tree().create_timer(1.0).timeout.connect(func(): _show_level_up([tr("LEVEL %d") % 18, tr("Auto: ") + "Ryujin 30Z",
			tr("Titel: ") + tr("Drift-Samurai"), tr("Vinyl: ") + tr("Glitch")]))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wtour"):
			var tour := WorldTour.new()
			tour.w = self
			tour.only = a.substr(8) if a.length() > 8 else ""
			add_child(tour)
		if a.begins_with("--otest="):  # Test im Gelände (offroad_test.gd): Fahrten, Sprünge, Bäume, Zaun, Wasser
			var ot := OffroadTest.new()
			ot.w = self
			ot.case = a.substr(8)
			add_child(ot)


## Anflug von oben (world_intro.gd): "start" nach Losfahren in der Garage, "short" (kürzer) nach Schnellreise und bei
## der Rückkehr aus Rennen oder Garage. Aus bei Fahr- und Prüftests (--wtour, --wdrive, --ctest ...) und mit --nozoom.
func _intro_kind(returning: bool) -> String:
	var travel := _travel_arrival
	_travel_arrival = false
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--zkind="):  # Test: Art erzwingen
			return a.substr(8)
		if a in ["--nozoom", "--wdrive", "--worldcheck", "--wmap", "--lvltest"] or a.begins_with("--wtour") or a.begins_with("--hwrace") \
				or a.begins_with("--drivebot") or a.begins_with("--ctest") or a.begins_with("--wcam") or a.begins_with("--otest"):
			return ""
	return "short" if travel or returning else "start"


## Ende des Anflugs (world_intro.gd; played false: abgesagt, z. B. im Tunnel): fahren, HUD blendet ein, oben der Ort
## (als _set_active ihn beim Laden setzte, gab es das HUD noch nicht)
func _intro_done(skipped: bool, played := true) -> void:
	if not played and _intro:
		_intro.cancel()
	_intro = null
	player.controls_enabled = true
	if not played:
		hud["root"].modulate.a = 1.0
		return
	create_tween().tween_property(hud["root"], "modulate:a", 1.0, 0.25 if skipped else 0.4)
	if not active.is_empty():
		_area_name = _area_title(active)
		hud["area"].text = _area_name
		_area_t = 4.0


func _exit_tree() -> void:
	# erst den Bau im Hintergrund abwarten (er liest noch Offroad.areas), dann aufräumen
	if _task >= 0:
		Track.wait_build(_task)
		_task = -1
	Builder.async_vinyls = false
	Offroad.areas = []  # im Rennen gibt es kein Gelände
	if GameState.xp_dirty or _spot_dirty:
		GameState.save_game()


## Fenster schließen (Rechner): den Ort noch merken und speichern
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and _ready_done and player != null:
		_note_spot()
		if _spot_dirty or GameState.xp_dirty:
			_save_spot()


## Startpunkt: nach einem Rennen am Marker, sonst am Start des ersten Rennens, Blick zur Ausfahrt (zur Autobahn)
func _spawn_xf() -> Transform3D:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--hwrace=") and not hw_defs.is_empty():  # Test: am Start dieses Autobahn-Rennens
			return hw_defs[int(a.substr(9)) % hw_defs.size()]["start_xf"]
		# Test: --wspawn=ring:k (auf dem Ring bei Punkt k, in Fahrtrichtung) oder --wspawn=exit:i (an der Ausfahrt
		# der Stadt von Rennen i, Blick zur Autobahn)
		if a.begins_with("--wspawn="):
			var parts := a.substr(9).split(":")
			if parts[0] == "xy":  # --wspawn=xy:x:z:grad (Blickrichtung, 0 = Norden/-Z)
				var yaw := deg_to_rad(float(parts[3]) if parts.size() > 3 else 0.0)
				return Transform3D(Basis(Vector3.UP, -yaw), Vector3(float(parts[1]), 0.5, float(parts[2])))
			if parts[0] == "strasse":  # --wspawn=strasse:rennen:Name[:m[:rück]]  auf einer echten Straße (city_net) der Stadt
				for c in layout["cities"]:
					if int(c["race_index"]) != int(parts[1]):
						continue
					var sj := Track.begin(c["race"])
					(sj["root"] as Node).free()
					for p in sj["track"]["paths"]:
						if str(p.get("street_name", "")) == parts[2]:
							var pc: Curve3D = p["curve"]
							var m := clampf(float(parts[3]) if parts.size() > 3 else 40.0, 2.0, pc.get_baked_length() - 2.0)
							var sx := Track.xform_at(pc, m, 0.0)
							if parts.size() > 4:
								sx.basis = sx.basis.rotated(Vector3.UP, PI)
							sx = (c["xf"] as Transform3D) * sx
							sx.origin.y += 0.5
							return sx
					push_warning("--wspawn=strasse: keine Straße %s" % parts[2])
			if parts[0] == "gelaende":  # --wspawn=gelaende:i[:t[:s[:grad]]]  im Gelände i, t m hinter dem Tor (Flächenkoordinaten)
				return _offroad_gate_xf(int(parts[1]), float(parts[2]) if parts.size() > 2 else 12.0,
					float(parts[3]) if parts.size() > 3 else 0.0, float(parts[4]) if parts.size() > 4 else 0.0)
			if parts[0] == "seg":  # --wspawn=seg:ring:stück:meter  auf einem Autobahnstück (Ring 2 Kreisel, 3-6 Diagonalen)
				for sg in layout["segments"]:
					if sg.get("ring", 0) == int(parts[1]):
						if int(parts[2]) == 0:
							var sj := Track.begin(sg["race"])
							(sj["root"] as Node).free()
							var sxf := Track.xform_at(sj["track"]["curve"], float(parts[3]), 2.0 if sg["race"].get("type", "") == "dreieck" else 6.75, true)
							sxf.origin.y += 0.5
							return sxf
						parts[2] = str(int(parts[2]) - 1)
			if parts[0] == "rline":  # --wspawn=rline:j[:m]  auf Auffahrt/Verbindung j (tools/world_map --worldlog), m Meter vom Ring
				var rl: PackedVector2Array = layout["ramp_lines"][int(parts[1]) % layout["ramp_lines"].size()]
				var want := float(parts[2]) if parts.size() > 2 else 60.0
				var acc := 0.0
				for k in rl.size() - 1:
					var sl := rl[k].distance_to(rl[k + 1])
					if acc + sl >= want or k == rl.size() - 2:
						var p := rl[k].lerp(rl[k + 1], clampf((want - acc) / maxf(sl, 0.01), 0.0, 1.0))
						var dv := (rl[k + 1] - rl[k]).normalized()
						var gy := land.ground_h(p) + 1.1 if land != null else 0.5  # Verbindung mit Höhenprofil (seit 2.40)
						return Transform3D(Basis.looking_at(Vector3(dv.x, 0.0, dv.y), Vector3.UP), Vector3(p.x, gy, p.y))
					acc += sl
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
					# --wspawn=exit:i:m  m Meter von der Ausfahrt in die Stadt hinein (Standard 30)
					return Transform3D(Basis.looking_at(-n, Vector3.UP), ex + n * (float(parts[2]) if parts.size() > 2 else 30.0))
	if has_return:
		has_return = false
		_spawn_src = "Rückkehr"
		return return_xf
	if _travel_xf_on:
		_travel_xf_on = false
		_spawn_src = "Sprung"
		return _travel_xf
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wstart="):  # Test: Start am Eingang der Stadt dieses Rennens (wie nach einer Schnellreise)
			_travel_to = int(a.substr(9))
	if _travel_to >= 0:
		var ri := _travel_to
		_travel_to = -1
		if _has_city(ri):
			_spawn_src = "Schnellreise"
			return _gate_xf(ri)
	# Losfahren (seit 2.42): wo man zuletzt war, ohne Auswahl der Startstadt
	if GameState.world_pos.size() == 4 and not OS.get_cmdline_user_args().has("--nosavedpos"):
		var wp: Array = GameState.world_pos
		_spawn_saved = true
		_spawn_src = "gemerkter Ort"
		return Transform3D(Basis(Vector3.UP, float(wp[3])), Vector3(float(wp[0]), float(wp[1]), float(wp[2])))
	return _fallback_xf()


## Start ohne (passenden) gemerkten Ort: am Eingang der zuletzt erreichten Stadt; ganz neues Spiel: am Start des ersten
## Rennens in Frankfurt, Blick zur Ausfahrt
func _fallback_xf() -> Transform3D:
	var tri := _town_race(GameState.last_town)
	_spawn_src = "Stadteingang"
	if tri >= 0:
		return _gate_xf(tri)
	_spawn_src = "neues Spiel"
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


## Im Gelände i, t m hinter dem Tor (s seitlich, grad gedreht), Blick hinein: Test --wspawn=gelaende, Sprungziel der Karte
func _offroad_gate_xf(i: int, t := 12.0, s := 0.0, grad := 0.0) -> Transform3D:
	var ar: Dictionary = layout["offroad"][i]
	var gl := Vector2(float(ar["gate_s"]) + s, t)
	var gdir := Offroad.wdir(ar, Vector2(0, 1).rotated(deg_to_rad(grad)))
	var gw := Offroad.world(ar, gl)
	return Transform3D(Basis.looking_at(Vector3(gdir.x, 0.0, gdir.y), Vector3.UP), Vector3(gw.x, Offroad.base_h(ar, gl), gw.y))


func _has_city(ri: int) -> bool:
	return layout["cities"].any(func(c): return c["race_index"] == ri)


## Stadteingang (Schnellreise, Neustart in einer Stadt): an der Ausfahrt der Stadt dieses Rennens, 40 m hinein, Blick
## in die Stadt
func _gate_xf(ri: int) -> Transform3D:
	for c in layout["cities"]:
		if c["race_index"] == ri:
			var ex: Vector3 = c["exit_world"]
			var n := Vector3(ex.x, 0, ex.z).normalized()
			return Transform3D(Basis.looking_at(n, Vector3.UP), ex + n * 40.0 + Vector3(0, 0.5, 0))
	return Transform3D.IDENTITY


## Rennen, an dessen Eingang man in dieser Stadt ankommt: wie auf der Karte das erste der Stadt (kleinster Winkel);
## -1: keine solche Stadt
func _town_race(town: String) -> int:
	var best := -1
	var bphi := 1e9
	for c in layout["cities"]:
		if town != "" and str(Catalog.RACES[c["race_index"]].get("town", "")) == town and float(c["phi_w"]) < bphi:
			bphi = float(c["phi_w"])
			best = c["race_index"]
	return best


## Alles in der Nähe gleich bauen (hinter dem Ladebild)
func _build_near(at: Vector3, cover: Node) -> void:
	var near := entries.filter(func(e): return e["state"] == "none" and _dist(e, at) < LOAD_PAD * 0.6)
	near.sort_custom(func(a, b): return _dist(a, at) < _dist(b, at))
	for i in near.size():
		cover.get_meta("label").text = tr("Welt wird gebaut … %d / %d") % [i + 1, near.size()]
		await get_tree().process_frame
		var job := Track.begin(near[i]["race"])
		job["nobatch"] = true
		while Track.step(job) < 1.0:
			pass
		_finish(near[i], job)


## Ist p (gemerkter Ort) befahrbar? Auf einer fertig gebauten Fahrbahn in passender Höhe (_score: unter 0 heißt
## innerhalb der Fahrbahn, eine Fahrbahn weit darüber oder darunter zählt nicht) oder in einem Gelände
func _spot_ok(p: Vector3) -> bool:
	for e in entries:
		if e["state"] == "ready" and _dist(e, p) < 50.0 and _score(e, p) < -0.3:
			return true
	var a := Offroad.find(Vector2(p.x, p.z))
	if not a.is_empty():
		var l := Offroad.local(a, Vector2(p.x, p.z))
		return Offroad.area_sd(a, l) < -4.0 and absf(p.y - Offroad.base_h(a, l)) < 4.0
	return false


func _dist(e: Dictionary, p: Vector3) -> float:
	return maxf(Vector2(p.x - e["center"].x, p.z - e["center"].z).length() - e["radius"], 0.0)


func _entry_of(track: Dictionary) -> Dictionary:
	for e in entries:
		if e["track"] == track and not track.is_empty():
			return e
	return {}


# --- Nachladen ------------------------------------------------------------------

# --- Ruckler messen (--hitch): Bilder über 25 ms mit dem, was im Bild davor Zeit kostete ---------------------------
var _hitch := false
var _prof := {}
var _prof_t := 0
var _events := []


## Test: --wshot=/pfad/bild.png[:sekunden] speichert nach der Wartezeit (Standard 4 s) ein Bild und beendet das Spiel
var _shot_t := -1.0

func _shot_check(dt: float) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wshot="):
			var parts := a.substr(8).split(":")
			if _shot_t < 0.0:
				_shot_t = float(parts[1]) if parts.size() > 1 else 4.0
			_shot_t -= dt
			if _shot_t <= 0.0 and not _hid:
				for b in OS.get_cmdline_user_args():
					if b.begins_with("--whathide="):  # Test: Meshes mit diesem Shader/Farbe am Punkt --whatsat ausblenden
						var xz := PackedStringArray(["0", "0"])
						for c2 in OS.get_cmdline_user_args():
							if c2.begins_with("--whatsat="):
								xz = c2.substr(10).split(":")
						_hide_at(self, Vector3(float(xz[0]), 0.0, float(xz[1])), b.substr(11))
						_hid = true
						_shot_t = 0.3
						return
			if _shot_t <= 0.0:
				get_viewport().get_texture().get_image().save_png(parts[0])
				print("WSHOT ", parts[0], " fps=", Engine.get_frames_per_second(), " draw=",
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), " prims=",
					RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
				for b in OS.get_cmdline_user_args():
					if b.begins_with("--whatsat="):  # Test: welche Meshes liegen flach an diesem Weltpunkt (x:z)?
						var xz := b.substr(10).split(":")
						_whats_at(self, Vector3(float(xz[0]), 0.0, float(xz[1])))
				get_tree().quit()
			return


var _hid := false


func _hide_at(n: Node, p: Vector3, what: String) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			var mi := c as MeshInstance3D
			var bb: AABB = mi.global_transform * mi.get_aabb()
			var mo = mi.material_override if mi.material_override else mi.mesh.surface_get_material(0)
			var tag := (mo as ShaderMaterial).shader.resource_path if mo is ShaderMaterial else "std"
			if p.x > bb.position.x and p.x < bb.end.x and p.z > bb.position.z and p.z < bb.end.z and (what in tag or what == str(mi.name)):
				mi.visible = false
				print("HIDE ", mi.name, " ", tag)
		_hide_at(c, p, what)


func _whats_at(n: Node, p: Vector3) -> void:
	for c in n.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh != null and (c as MeshInstance3D).is_visible_in_tree():
			var bb: AABB = (c as MeshInstance3D).global_transform * (c as MeshInstance3D).get_aabb()
			if p.x > bb.position.x and p.x < bb.end.x and p.z > bb.position.z and p.z < bb.end.z \
					and bb.position.y < 0.5 and bb.end.y > -1.0 and bb.size.x < 2000.0:
				var mi := c as MeshInstance3D
				var mo = mi.material_override if mi.material_override else mi.mesh.surface_get_material(0)
				var info := str(mi.mesh.get_class()) + " v=" + str(mi.mesh.surface_get_array_len(0) if mi.mesh is ArrayMesh else -1)
				if mo is ShaderMaterial:
					info += " shader=" + str((mo as ShaderMaterial).shader.resource_path)
				elif mo is StandardMaterial3D:
					info += " col=" + str((mo as StandardMaterial3D).albedo_color)
				print("WHAT ", c.name, " aabb=", bb, " ", info)
		_whats_at(c, p)


func _prof_mark(key: String) -> void:
	if not _hitch:
		return
	var now := Time.get_ticks_usec()
	_prof[key] = _prof.get(key, 0) + now - _prof_t
	_prof_t = now


func _event(what: String) -> void:
	if _hitch:
		_events.append(what)


func _hitch_frame(dt: float) -> void:
	if dt > 0.025:
		var parts := []
		if land and land.last_event != "":
			parts.append(land.last_event)
		if offroad_node and offroad_node.last_event != "":
			parts.append(offroad_node.last_event)
		for k in _prof:
			if _prof[k] > 1500:
				parts.append("%s=%.1f" % [k, _prof[k] / 1000.0])
		print("HITCH %.0f ms bei %.0f km/h t=%.1f | %s | %s | proc=%.1f phys=%.1f bau=%s | draw=%d obj=%d" % [dt * 1000.0, player.velocity.length() * 3.6,
			Time.get_ticks_msec() / 1000.0, " ".join(parts), ", ".join(_events),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			"ja" if _task >= 0 else "nein",
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.OBJECT_COUNT)])
	_prof.clear()
	_events.clear()
	if land:
		land.last_event = ""


func _finish(e: Dictionary, job: Dictionary) -> void:
	_event("fertig " + str(e["race"].get("name", "?")))
	var tr: Dictionary = job["track"]
	var root: Node3D = tr["node"]
	if _plugs.has(e["race_index"]) and e["kind"] == "city":
		(_plugs[e["race_index"]] as Node3D).visible = false  # Flussbett und Trog der Stadt sind jetzt da
	root.transform = e["xf"]
	Track.apply_lod(root, GameState.lod_ranges())
	root.process_mode = Node.PROCESS_MODE_PAUSABLE
	world.add_child(root)
	e["track"] = tr
	e["state"] = "ready"
	Track.set_daytime(tr, mood.get("day", 0.0))
	e["feet"] = job.get("buildings", []) + job.get("occupied", [])  # Häuser und Bauwerke (für --worldcheck)
	if e["kind"] == "city":
		_add_marker(e)
		_add_drift_zone(e)
		_add_secrets(e)
	_plan_traffic(e)
	if player and tr["crossing"]:
		tr["crossing"].player = player
	if player:
		for n in root.find_children("*", "", true, false):
			if n.is_in_group("ambient"):
				n.target = player


func _drop(e: Dictionary) -> void:
	if e["state"] != "ready" or e == active:
		return
	_event("weg " + str(e["race"].get("name", "?")))
	var root: Node = e["track"]["node"]
	traffic = traffic.filter(func(t): return is_instance_valid(t) and not root.is_ancestor_of(t))
	_tq = _tq.filter(func(q): return not is_same(q[0], e))
	root.queue_free()
	e["track"] = {}
	e["state"] = "none"
	if _plugs.has(e["race_index"]) and e["kind"] == "city":
		(_plugs[e["race_index"]] as Node3D).visible = true
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
	var loc := Track.locate(tr, lp)
	# Brücken (seit 2.36, Autobahndreiecke): eine Fahrbahn weit über oder unter dem Auto zählt nicht, sonst fiel man auf
	# der Brücke auf den Ring darunter (und unter der Brücke hinauf auf sie)
	var dy := absf(lp.y - Track.elev_at((loc["path"] as Dictionary)["curve"], loc["d"]))
	return loc["score"] + maxf(dy - 4.0, 0.0) * 3.0


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
	_event("aktiv " + str(e["race"].get("name", "?")))
	active = e
	player.track = e["track"]
	Track.apply_street_light(e["track"])
	var name := _area_title(e)
	Music.city("" if e["kind"] == "seg" else str(Catalog.RACES[e["race_index"]].get("town", "")))
	if e["kind"] != "seg":
		_reach_town(str(Catalog.RACES[e["race_index"]].get("town", "")))
	if name != _area_name and hud.has("area"):
		_area_name = name
		hud["area"].text = name
		_area_t = 4.0


## Name oben beim Wechsel der Strecke: Stadt oder Autobahn-Abschnitt
func _area_title(e: Dictionary) -> String:
	return str(e["race"].get("area", "AUTOBAHN")) if e["kind"] == "seg" else str(Catalog.RACES[e["race_index"]].get("town", "")).to_upper()


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
	if race["name"] in GameState.won_events:
		return  # gewonnen: kein Marker mehr in der Welt
	if not GameState.career_open(race["name"]):
		col = Color(0.45, 0.47, 0.52)  # gesperrt: grau
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
	if hrace != null:
		if _near_marker != -1 or _near_hw != -1:
			_near_marker = -1
			_near_hw = -1
			hud["prompt"].visible = false
		return
	var p := player.global_position
	_update_hw_markers(p)
	if _near_hw >= 0:
		return
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
				line = tr("Gesperrt: %s (du bist Level %d)") % [GameState.lock_text(race["name"]), GameState.level()]
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
	_note_spot(xf, true)  # wer im Rennen beendet, startet beim nächsten Mal am Marker
	_save_spot()
	GameState.race_index = i
	get_tree().change_scene_to_file("res://scenes/race.tscn")


# --- Umgebung, HUD -------------------------------------------------------------------

## Tag-Nacht-Wechsel: die Uhr läuft 1 Spielstunde je echter Minute (ein Tag in 24 Minuten), Start am Abend.
## Moods.at_hour überblendet Himmel, Licht, Nebel und Farbfilter; Sonne und Mond wandern mit.
const DAY_MINUTES := 24.0
var tod := 20.0  # Uhrzeit (Stunden)
var _sky_mat: ShaderMaterial
var _ground_mat: ShaderMaterial
var _plugs := {}  # Rennen -> Pfropfen in den Löchern des Bodens (sichtbar, solange die Stadt nicht geladen ist)
var land: Landscape
var _wcam: Camera3D
var _tod_t := 0.0


func _update_daylight(dt: float, force := false) -> void:
	tod = fposmod(tod + dt * 24.0 / (DAY_MINUTES * 60.0), 24.0)
	_tod_t -= dt
	if _tod_t > 0.0 and not force:
		return
	_tod_t = 0.25  # viermal je Sekunde reicht, die Uhr geht langsam
	var m := Moods.at_hour(tod)
	mood = m
	env.ambient_light_color = m["amb"]
	env.ambient_light_energy = m["amb_e"]
	env.fog_light_color = m["fog"]
	env.fog_density = m["fog_d"]
	env.adjustment_saturation = m["sat"]
	env.adjustment_contrast = m["con"]
	env.adjustment_brightness = m["bri"]
	var day: float = m["day"]
	# Sonne: geht um 6 Uhr im Osten auf, steht mittags hoch, um 18 Uhr im Westen unter; nachts der Mond (fest)
	var sun_e := sin(PI * (tod - 6.0) / 12.0)
	var sun_az := lerpf(-100.0, 100.0, clampf((tod - 6.0) / 12.0, 0.0, 1.0))
	var sun_rot := Vector3(-maxf(rad_to_deg(asin(clampf(sun_e, 0.0, 1.0))) * 0.9, 10.0), sun_az, 0.0)
	moon.rotation_degrees = Vector3(-50.0, 30.0, 0.0).lerp(sun_rot, clampf(day * 1.5, 0.0, 1.0))
	moon.light_color = m["moon"]
	moon.light_energy = m["moon_e"]
	env.tonemap_exposure = lerpf(0.88, 0.8, day)
	if _sky_mat:
		_sky_mat.set_shader_parameter("top_col", m["top"])
		_sky_mat.set_shader_parameter("hor_col", m["hor"])
		_sky_mat.set_shader_parameter("glow_col", m["glow"])
		_sky_mat.set_shader_parameter("stars", m["stars"])
		_sky_mat.set_shader_parameter("day", day)
		_sky_mat.set_shader_parameter("sun_dir", -moon.global_basis.z if moon.is_inside_tree() else -moon.basis.z)
	for e in entries:
		if e["state"] == "ready":
			Track.set_daytime(e["track"], day)
	if land:
		# Nebelbänke: nachts, am stärksten im Morgengrauen (5-8 Uhr), tagsüber weg
		var dawn := sin(PI * clampf((tod - 4.5) / 4.0, 0.0, 1.0))
		land.set_daylight(day, clampf((1.0 - day) * 0.45 + dawn * 0.5, 0.0, 0.75))
	if offroad_node:
		offroad_node.set_daylight(day)
	if player and player.tire_fx:
		player.tire_fx.day = day


func _setup_environment() -> void:
	mood = Moods.get_mood(Layout.MOOD)
	env = Environment.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky_mat.set_shader_parameter("top_col", mood["top"])
	sky_mat.set_shader_parameter("hor_col", mood["hor"])
	sky_mat.set_shader_parameter("glow_col", mood["glow"])
	sky_mat.set_shader_parameter("stars", mood["stars"])
	sky_mat.set_shader_parameter("land", 1.0)  # Hügel statt Skyline rundum
	_sky_mat = sky_mat
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
	# mit Löchern über allen Tunneltrögen und Flussbetten (sonst lag er wie ein Deckel über dem Trog)
	var ground := MeshInstance3D.new()
	var ext: float = (layout["ring_r"] + 9000.0) * 2.0
	var gst := SurfaceTool.new()
	gst.begin(Mesh.PRIMITIVE_TRIANGLES)
	gst.set_normal(Vector3.UP)
	Track.ground_cell(gst, Vector2(-ext / 2.0, -ext / 2.0), ext, layout["holes"])
	ground.mesh = gst.commit()
	# Landschaft (Felder, Hügel, Wald, Dörfer, Windparks); der flache Boden trägt dieselben Felder
	land = Landscape.new()
	land.name = "Landschaft"
	land.setup(layout)
	land.hold = func() -> bool: return _task >= 0 or _intro != null  # beim Anflug von oben nichts nachbauen
	world.add_child(land)
	# Gelände (seit 2.39): Flächen der Welt für Auto und Landschaft, Bau und Nachladen wie die Landschaft
	Offroad.areas = layout.get("offroad", [])
	offroad_node = OffroadBuild.new()
	offroad_node.name = "Gelaende"
	offroad_node.setup(land, GameState.view_distance())
	# nicht zugleich mit einer Strecke bauen (im Browser baut die Welt Schritt für Schritt in _job)
	offroad_node.hold = func() -> bool: return _task >= 0 or not _job.is_empty() or _intro != null
	world.add_child(offroad_node)
	ground.material_override = land.land_mat
	_ground_mat = land.land_mat
	Track.land_mat = land.land_mat  # Böschungen der Autobahn tragen dieselben Felder wie das Gelände
	# Pfropfen (seit 2.33): die Löcher einer Stadt (Flussbett, Tunneltrog) sind nur offen, solange sie geladen ist.
	# Wasser und Ufermauern gehören zur Stadt; war sie nicht geladen, sah man durch die Löcher in den Himmel.
	for c in layout["cities"]:
		var ch := PackedVector3Array()
		var cx: Transform3D = c["xf"]
		for h in c["holes_local"]:
			var w: Vector3 = cx * Vector3(h.x, 0.0, h.y)
			ch.append(Vector3(w.x, w.z, h.z))
		if ch.is_empty():
			continue
		var pst := SurfaceTool.new()
		pst.begin(Mesh.PRIMITIVE_TRIANGLES)
		pst.set_normal(Vector3.UP)
		if _plug_cell(pst, Vector2(-ext / 2.0, -ext / 2.0), ext, ch) == 0:
			continue
		var plug := MeshInstance3D.new()
		plug.name = "Pfropfen_%d" % c["race_index"]
		plug.mesh = pst.commit()
		plug.material_override = land.land_mat
		plug.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ground.add_child(plug)
		_plugs[c["race_index"]] = plug
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tod="):  # Test: Uhrzeit beim Start (Stunden), z.B. --tod=13
			tod = float(a.substr(6))
	_update_daylight(0.0, true)
	ground.position.y = -0.12
	if not OS.get_cmdline_user_args().has("--noground"):  # Test: ohne den großen Boden (was deckt was zu?)
		world.add_child(ground)


## Gegenstück zu Track.ground_cell: genau die Zellen, die dort wegen der Löcher holes fehlen (dasselbe Raster, daher
## ohne Fuge). Liegt eine Zelle ganz in einem Loch, kommt sie am Stück. Gibt die Zahl der Zellen zurück.
func _plug_cell(st: SurfaceTool, o: Vector2, s: float, holes: PackedVector3Array) -> int:
	var c := o + Vector2(s, s) * 0.5
	var near := PackedVector3Array()
	for h in holes:
		var reach := s * 0.7072 + h.z
		if Vector2(h.x, h.y).distance_squared_to(c) < reach * reach:
			near.append(h)
	if near.is_empty():
		return 0
	var inside := false
	for h in near:
		if Vector2(h.x, h.y).distance_to(c) + s * 0.7072 < h.z:
			inside = true
			break
	if not inside:
		if s > 2.0:
			var hs := s * 0.5
			var n := 0
			for k in 4:
				n += _plug_cell(st, o + Vector2(k % 2, k / 2) * hs, hs, near)
			return n
		inside = false
		for h in near:
			if Vector2(h.x, h.y).distance_squared_to(c) < h.z * h.z:
				inside = true
				break
		if not inside:
			return 0
	for v in [Vector2(0, 0), Vector2(s, 0), Vector2(s, s), Vector2(0, 0), Vector2(s, s), Vector2(0, s)]:
		st.add_vertex(Vector3(o.x + v.x, 0.0, o.y + v.y))
	return 1


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


## HUD-Schrift (seit 2.48 wie die Menüs): Inter, dünne halbdurchsichtige Kontur und weicher Schatten statt der dicken
## schwarzen Kontur (wirkte grob)
func _label(parent: Node, size: int, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.horizontal_alignment = align
	l.add_theme_font_override("font", UI.font("cond", 0.0))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("outline_size", 2)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
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
	hud["root"] = root
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
	# Links über dem Radar wie im Rennen (seit 2.48): Meldungen, Drift, Gebietsname klein; bis 2.47 stand der Name groß
	# oben in der Mitte (im Sichtfeld, die Ortsschilder zeigen ohnehin, wo man ist)
	var left := VBoxContainer.new()
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.alignment = BoxContainer.ALIGNMENT_END
	left.add_theme_constant_override("separation", 2)
	left.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	left.offset_left = 14.0
	left.offset_right = 14.0 + 250.0
	left.offset_bottom = -WorldMinimap.SIZE - 12.0
	left.offset_top = left.offset_bottom - 200.0
	root.add_child(left)
	hud["left"] = left
	var area := _label(left, 11)
	area.add_theme_font_override("font", UI.font("wide", 0.0, 1))
	area.add_theme_color_override("font_color", Color(0.86, 0.9, 0.96))
	area.uppercase = true
	area.visible = false
	hud["area"] = area
	var prompt := _label(root, 15, HORIZONTAL_ALIGNMENT_CENTER)
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
	help.text = tr("Frei fahren: Marker anfahren startet ein Rennen\nM Karte  C Kamera  R Zurücksetzen  Esc Menü")
	help.modulate.a = 0.7
	hud["help"] = help
	# Fahrer-Level (seit 2.35 unten statt oben links): eine schmale Leiste über die ganze Bildschirmbreite am unteren
	# Rand, darüber klein Level und XP. Dezent, das Bild gehört der Straße.
	var xbg := ColorRect.new()
	xbg.color = Color(0, 0, 0, 0.45)
	xbg.anchor_top = 1.0
	xbg.anchor_bottom = 1.0
	xbg.anchor_right = 1.0
	xbg.offset_top = -3.0
	xbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(xbg)
	var xfill := ColorRect.new()
	xfill.color = Color(UI.CYAN.r, UI.CYAN.g, UI.CYAN.b, 0.8)
	xfill.anchor_top = 1.0
	xfill.anchor_bottom = 1.0
	xfill.offset_top = -3.0
	xfill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(xfill)
	var ll := _label(root, 9, HORIZONTAL_ALIGNMENT_CENTER)
	ll.anchor_left = 0.5
	ll.anchor_right = 0.5
	ll.anchor_top = 1.0
	ll.anchor_bottom = 1.0
	ll.offset_left = -200.0
	ll.offset_right = 200.0
	ll.offset_top = -17.0
	ll.offset_bottom = -4.0
	ll.modulate.a = 0.75
	hud["lvl"] = ll
	hud["lvl_fill"] = xfill
	# laufender Drift unten in der Mitte: Punkte und Multiplikator, solange die Kette läuft
	var dm := _label(root, 18, HORIZONTAL_ALIGNMENT_CENTER)
	dm.anchor_left = 0.5
	dm.anchor_right = 0.5
	dm.anchor_top = 1.0
	dm.anchor_bottom = 1.0
	dm.offset_left = -200.0
	dm.offset_right = 200.0
	dm.offset_top = -66.0
	dm.offset_bottom = -42.0
	dm.add_theme_font_override("font", UI.font("wide", 0.15))
	dm.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	dm.visible = false
	hud["drift"] = dm  # seit 2.45 ungenutzt (drift_meter zeigt den Drift)
	drift_meter = DriftMeter.new()
	drift_meter.player = player
	drift_meter.visible = false
	drift_meter.banked.connect(_on_drift_banked)
	drift_meter.lost.connect(_on_drift_lost)
	left.add_child(drift_meter)
	# Level aufgestiegen (seit 2.35 dezent unten über der Leiste statt groß in der Mitte): Level und das Wichtigste,
	# was es freischaltet; alles Weitere steht in der Garage unter Fahrer
	var lu := _label(root, 14, HORIZONTAL_ALIGNMENT_CENTER)
	lu.anchor_left = 0.5
	lu.anchor_right = 0.5
	lu.anchor_top = 1.0
	lu.anchor_bottom = 1.0
	lu.offset_left = -300.0
	lu.offset_right = 300.0
	lu.offset_top = -112.0
	lu.offset_bottom = -70.0
	lu.add_theme_font_override("font", UI.font("wide", 0.15))
	lu.add_theme_color_override("font_color", Color(0.4, 1.0, 0.55))
	lu.visible = false
	hud["levelup"] = lu
	_update_level_hud()
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
	# gewonnene Rennen verschwinden aus der Welt und von der Minikarte (wie in Underground); die große Karte zeigt sie golden
	var open_pins := []
	for i in _pins:
		if not Catalog.RACES[i]["name"] in GameState.won_events:
			open_pins.append(_pins[i])
	_ch_pin = Node3D.new()
	_ch_pin.set_meta("hud_col", Color(1.0, 0.2, 0.15))
	_ch_pin.set_meta("off", true)
	world.add_child(_ch_pin)
	open_pins.append(_ch_pin)
	# Autobahn-Rennen (seit 2.43): Start als blauer Punkt, Gegner im Rennen als rote Punkte
	for i in hw_defs.size():
		var hp := Node3D.new()
		hp.position = (hw_defs[i]["start_xf"] as Transform3D).origin
		hp.set_meta("hud_col", HighwayRace.AB_COL)
		world.add_child(hp)
		open_pins.append(hp)
		_add_hw_marker(i)
	for i in HighwayRace.GEGNER:
		var rp := Node3D.new()
		rp.set_meta("hud_col", Color(1.0, 0.3, 0.2))
		rp.set_meta("off", true)
		world.add_child(rp)
		open_pins.append(rp)
		hw_pins.append(rp)
	_ch_t = 3.0 if OS.get_cmdline_user_args().has("--challenger") else randf_range(70.0, 160.0)
	minimap.setup_world(layout["roads"], player, open_pins, _offroad_map())
	for ri in _dz:  # Driftzonen der Städte, die schon hinter dem Ladebild gebaut wurden
		var dze: Dictionary = _dz[ri]["e"]
		if dze["state"] == "ready":
			minimap.add_zone(_dz[ri]["key"], DriftZones.polyline(dze["track"], _dz[ri], dze["xf"]))
	minimap.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	minimap.offset_left = 8.0
	minimap.offset_right = 8.0 + WorldMinimap.SIZE
	minimap.offset_top = -WorldMinimap.SIZE - 8.0
	minimap.offset_bottom = -8.0
	_feed = VBoxContainer.new()
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_feed.add_theme_constant_override("separation", -1)
	_feed.alignment = BoxContainer.ALIGNMENT_END
	left.add_child(_feed)
	left.move_child(_feed, 0)  # oben die Meldungen, darunter Drift und Gebietsname (wie im Rennen)
	left.move_child(hud["area"], left.get_child_count() - 1)
	var dp := _label(root, 12)  # oben links statt in der Mitte (seit 2.48)
	dp.offset_left = 12.0
	dp.offset_top = 10.0
	dp.offset_right = 340.0
	dp.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	dp.visible = false
	hud["duel_prompt"] = dp
	var duel := Control.new()  # Duell-Leiste oben links statt oben in der Mitte (seit 2.48)
	duel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	duel.offset_left = 2.0
	duel.offset_right = 342.0
	duel.offset_top = 8.0
	duel.offset_bottom = 54.0
	duel.visible = false
	root.add_child(duel)
	var dl := _label(duel, 13, HORIZONTAL_ALIGNMENT_CENTER)
	dl.size = Vector2(340, 24)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.position = Vector2(10, 28)
	bg.size = Vector2(320, 9)
	duel.add_child(bg)
	var fill := ColorRect.new()
	fill.position = Vector2(170, 28)
	fill.size = Vector2(0, 9)
	duel.add_child(fill)
	var mid := ColorRect.new()
	mid.color = Color(1, 1, 1, 0.8)
	mid.position = Vector2(169, 25)
	mid.size = Vector2(2, 15)
	duel.add_child(mid)
	hud["duel"] = duel
	hud["duel_label"] = dl
	hud["duel_fill"] = fill
	_set_target(target)
	_build_pause(root)
	var map_layer := CanvasLayer.new()
	map_layer.layer = 5
	add_child(map_layer)
	map_view = MapView.new()
	map_view.visible = false
	map_layer.add_child(map_view)
	map_view.setup(layout, player, hw_defs, _gate_xf, _offroad_gate_xf)
	map_view.areas = _offroad_map()
	for vl in layout.get("vlakes", []):
		map_view.lakes.append([Vector2(vl["pos"].x, vl["pos"].y) if vl["pos"] is Vector2 else Vector2(vl["pos"].x, vl["pos"].z), float(vl["r"])])
	if land:
		map_view.relief = land.map_texture(map_view.relief_lo, map_view.relief_hi, 320)
		var rl: Vector2 = map_view.relief_lo
		var rh: Vector2 = map_view.relief_hi
		map_view.villages = land.villages().filter(func(v): return v[0].x > rl.x and v[0].x < rh.x and v[0].y > rl.y and v[0].y < rh.y)
		if layout.has("center"):
			map_view.center_town = [Vector2(layout["center"].x, layout["center"].z), Layout.CENTER_NAME.to_upper()]
	map_view.district_fn = _map_districts
	map_view.target = target
	map_view.target_chosen.connect(_set_target)
	map_view.target_pos_chosen.connect(_set_target_pos)
	map_view.jump.connect(_jump)
	map_view.closed.connect(_close_map)


## Viertel der gebauten Städte für die große Karte (seit 2.49): Name in der Mitte jedes Abschnitts gleicher Gegend
func _map_districts() -> Array:
	var out := []
	for e in entries:
		if e["kind"] != "city" or e["state"] != "ready" or (e["track"] as Dictionary).is_empty():
			continue
		var trk: Dictionary = e["track"]
		var arr: Array = trk.get("districts", [])
		var c: Curve3D = trk["curve"]
		var xf: Transform3D = e["xf"]
		var i := 0
		while i < arr.size():
			var j := i
			while j + 1 < arr.size() and arr[j + 1] == arr[i]:
				j += 1
			var md := clampf((float(i) + float(j) + 1.0) * 0.5 * Track.DISTRICT_LEN, 0.0, c.get_baked_length())
			var p: Vector3 = xf * c.sample_baked(md)
			out.append([Vector2(p.x, p.z), tr(Track.DISTRICTS[arr[i]]["name"])])
			i = j + 1
	return out


## Gelände für die Karten: [Umriss (Welt x, z), Farbe, Name, Teiche als Umrisse]
func _offroad_map() -> Array:
	var out := []
	for a in layout.get("offroad", []):
		var ponds := []
		for pd in a["ponds"]:
			var pl := PackedVector2Array()
			for k in 24:
				var t := TAU * k / 24.0
				var q: Vector2 = pd["c"] + Vector2(cos(t) * pd["r"].x, sin(t) * pd["r"].y).rotated(pd["a"])
				pl.append(Offroad.world(a, q))
			ponds.append(pl)
		out.append([a["outline"], Color(0.16, 0.4, 0.2, 0.55) if a["kind"] == "golf" else Color(0.55, 0.47, 0.33, 0.55), a["name"], ponds])
	return out


func _build_pause(root: Control) -> void:
	# Abdunklung hinter dem Menü (seit 2.35), mit dem Menü sichtbar
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.visible = false
	root.add_child(dim)
	pause_panel = VBoxContainer.new()
	pause_panel.theme = UI.theme()
	pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_panel.position = Vector2(-70, -72)  # über dem Musik-Hinweis unten rechts
	pause_panel.custom_minimum_size = Vector2(140, 0)
	pause_panel.add_theme_constant_override("separation", 3)
	pause_panel.visible = false
	root.add_child(pause_panel)
	settings_panel = PauseSettings.new()
	root.add_child(settings_panel)
	settings_panel.closed.connect(_settings_closed.bind(pause_panel))
	var upd_dim := func(): dim.visible = pause_panel.visible or settings_panel.visible
	pause_panel.visibility_changed.connect(upd_dim)
	settings_panel.visibility_changed.connect(upd_dim)
	var title := UI.label(pause_panel, 20, "cond", UI.TEXT, 1, HORIZONTAL_ALIGNMENT_CENTER)
	title.text = tr("PAUSE")
	for entry in [["Weiter", _toggle_pause], ["Karte", func(): _toggle_pause(); _open_map()],
			["Tuning", _to_garage.bind("tuning")], ["Auto wechseln", _to_garage.bind("cars")], ["Fahrer", _to_garage.bind("driver")],
			["Einstellungen", _open_settings],
			["Garage", _leave_to_garage], ["Rennen aufgeben", _give_up]]:
		var b := Button.new()
		b.text = tr(entry[0]).to_upper()  # wie in der Garage: Großbuchstaben, linksbündig
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(entry[1])
		b.set_meta("key", entry[0])
		pause_panel.add_child(b)
		UI.menu_fx(b)  # Auswahl gleitet ein, Maus darüber wählt aus (wie in der Garage)


## Esc > Einstellungen: Lautstärke, Kamera & Tempo, Anzeige, ohne die Welt zu verlassen
func _open_settings() -> void:
	pause_panel.visible = false
	settings_panel.open()


func _settings_closed(panel: Control) -> void:
	panel.visible = true
	for b in panel.get_children():
		if b.get_meta("key", "") == "Einstellungen":
			(b as Button).grab_focus()


## Esc > Garage: ins Hauptmenü der Garage; "Losfahren" bringt einen an die gemerkte Stelle zurück (seit 2.42)
func _leave_to_garage() -> void:
	_unpause()
	_note_spot()
	_save_spot()
	GameState.in_world = false
	get_tree().change_scene_to_file("res://scenes/garage.tscn")


## Esc > Tuning / Auto wechseln: Garage öffnet direkt dort, "Fertig" bringt einen an dieselbe Stelle zurück
func _to_garage(menu: String) -> void:
	_unpause()
	_note_spot()
	_save_spot()
	return_xf = player.global_transform
	has_return = true
	GameState.world_menu = menu
	get_tree().change_scene_to_file("res://scenes/garage.tscn")


func _open_map() -> void:
	get_tree().paused = true
	Music.set_paused(true)
	hud["prompt"].visible = false
	map_view.open(target)


## Springen (Karte, seit 2.49; vorher Schnellreise nur in Städte): Welt neu laden, Ankunft an diesem Ort (Stadteingang,
## Tor eines Geländes, vor dem Start eines Autobahn-Rennens)
func _jump(xf: Transform3D) -> void:
	_travel_xf = xf
	_travel_xf_on = true
	has_return = false
	_travel_arrival = true  # kurzer Anflug von oben am Ziel
	get_tree().paused = false
	Music.set_paused(false)
	Music.race_loading()  # leiser während des Ladens, world_go macht wieder voll
	get_tree().change_scene_to_file("res://scenes/world.tscn")


## Test --wtravel=<Rennen>[:pause]: Karte öffnen (mit :pause über das Esc-Menü), die Stadt dieses Rennens wählen und
## echt die Leertaste drücken (Input.parse_input_event, wie eine Taste); nach dem Neuladen meldet die Welt, wo man steht
func _travel_test(dt: float) -> void:
	var arg := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--wtravel="):
			arg = a.substr(10)
	if arg == "" or player == null or (_intro != null and _tt_stage < 2):
		return  # erst nach dem Anflug die Karte öffnen (jede Taste überspringt ihn nur)
	var ri := int(arg.split(":")[0])
	_tt_t += dt
	if _tt_stage == 0 and _tt_t > 1.5:
		if arg.ends_with(":pause"):
			_toggle_pause()
			var kb := pause_panel.get_child(2) as Button  # "Karte" im Esc-Menü: Fokus darauf, dann Enter wie echt
			kb.grab_focus()
			kb.emit_signal("pressed")
		else:
			var m := InputEventKey.new()
			m.physical_keycode = KEY_M
			m.keycode = KEY_M
			m.pressed = true
			Input.parse_input_event(m)
		_tt_stage = 1
		_tt_t = 0.0
	elif _tt_stage == 1 and _tt_t > 0.8 and map_view.visible:
		var town: String = map_view.towns[map_view.town_of(ri)]["name"]
		map_view.select_town(town)
		print("TRAVEL map open, town ", town, ", focus ", get_viewport().gui_get_focus_owner())
		# seit 2.42: erst eine noch nicht entdeckte Stadt (Leertaste darf nichts tun), dann entdeckt und echt reisen
		GameState.towns_known.erase(town)
		_tt_press(KEY_SPACE)
		_tt_stage = 4
		_tt_t = 0.0
	elif _tt_stage == 4 and _tt_t > 1.0:
		var town: String = map_view.places[map_view.sel]["name"]
		print("TRAVEL gesperrt %s: Karte offen=%s" % ["OK" if map_view.visible else "FAIL", map_view.visible])
		GameState.reach_town(town)
		_tt_press(KEY_SPACE)
		_tt_stage = 2
		_tt_t = 0.0
	elif _tt_stage == 1 and _tt_t > 3.0:
		print("TRAVEL FAIL: Karte nicht offen")
		get_tree().quit()
	elif _tt_stage == 2 and _tt_t > 4.0:
		var want := Vector3.ZERO
		for c in layout["cities"]:
			if c["race_index"] == ri:
				want = c["exit_world"]
		var d := Vector2(player.global_position.x - want.x, player.global_position.z - want.z).length()
		print("TRAVEL %s: %.0f m vom Stadteingang (Rennen %d), paused=%s" % ["OK" if d < 120.0 else "FAIL", d, ri, get_tree().paused])
		get_tree().quit()


func _tt_press(key: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = key
		e.keycode = key
		e.pressed = pressed
		Input.parse_input_event(e)


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


## Ziel ohne Rennen (Karte, seit 2.49): Flagge auf der Minikarte an diesem Ort
func _set_target_pos(pos: Vector3, on: bool) -> void:
	if on:
		target = -1
	if minimap:
		minimap.set_target(pos, on)


func _toggle_pause() -> void:
	var p := not get_tree().paused
	get_tree().paused = p
	pause_panel.visible = p
	# im Autobahn-Rennen: "Rennen aufgeben" statt Karte und Garage (seit 2.43)
	for b in pause_panel.get_children():
		if b is Button:
			var key: String = b.get_meta("key", "")
			if key == "Rennen aufgeben":
				b.visible = hrace != null
			elif key in ["Karte", "Tuning", "Auto wechseln", "Fahrer", "Garage"]:
				b.visible = hrace == null
	Music.set_paused(p)
	if p:
		(pause_panel.get_child(1) as Button).grab_focus()


func _unpause() -> void:
	get_tree().paused = false
	Music.set_paused(false)


func _unhandled_input(event: InputEvent) -> void:
	if not _ready_done or _intro != null:
		return  # beim Anflug gehört jede Eingabe ihm (überspringen)
	if map_view and map_view.visible:
		map_view._handle(event)
		return
	if event.is_action_pressed("drift_toggle") and not get_tree().paused and player:
		# Q: Fahr- und Drift-Modus umschalten (Drift: Heck kommt leicht, wie in den Drift-Events)
		get_viewport().set_input_as_handled()
		GameState.world_drift = not GameState.world_drift
		player.drift_mode = GameState.world_drift
		_flash(tr("DRIFT-MODUS") if player.drift_mode else tr("FAHR-MODUS"), Color(1.0, 0.55, 0.12) if player.drift_mode else UI.CYAN)
		Sfx.ui("change")
		return
	# Enter bestätigt; die Leertaste ist Handbremse (steckt in Godots ui_accept mit drin, startete sonst beim Driften
	# am Marker ein Rennen oder ein Duell)
	var accept := event.is_action_pressed("ui_accept") and not event.is_action_pressed("handbrake")
	if _ch_prompt and _duel == 0 and not get_tree().paused and accept:
		get_viewport().set_input_as_handled()
		_start_duel()
		return
	if _near_hw >= 0 and hrace == null and not get_tree().paused and accept:
		get_viewport().set_input_as_handled()
		_start_highway(_near_hw)
		return
	if _near_marker >= 0 and not get_tree().paused and accept \
			and GameState.career_open(Catalog.RACES[_near_marker]["name"]):
		get_viewport().set_input_as_handled()
		_start_race(_near_marker)
		return
	if event.is_action_pressed("map") and not get_tree().paused and hrace == null:  # im Autobahn-Rennen keine Karte
		_open_map()
		return
	if event.is_action_pressed("camera") and not get_tree().paused:
		player.toggle_camera()
	elif event.is_action_pressed("reset_car") and not get_tree().paused and not player.track.is_empty():
		if player.offroad_reset():
			return  # Gelände: aufrecht an Ort und Stelle statt zurück auf die Straße
		var xf: Transform3D = player.track["xf"]
		var loc := Track.locate(player.track, xf.affine_inverse() * player.global_position)
		var p: Dictionary = loc["path"]
		var half: float = p["half_w"] - 2.0
		player.place(xf * Track.xform_at(p["curve"], loc["d"], clampf(loc["lat"], -half, half)))
	elif event.is_action_pressed("pause", false, true):
		if settings_panel.visible:
			get_viewport().set_input_as_handled()
			settings_panel.back()
			return
		_toggle_pause()


func _process(dt: float) -> void:
	if not _ready_done:
		return
	if get_tree().paused:
		if OS.get_cmdline_user_args().has("--wmap") or OS.get_cmdline_user_args().has("--wsettings"):
			_shot_check(dt)  # Test: Bild der offenen Karte bzw. der Einstellungen
		_travel_test(dt)
		return
	_travel_test(dt)
	if OS.get_cmdline_user_args().has("--wmap") and _shot_t < 0.0 and map_view and not map_view.visible:
		_open_map()
	if OS.get_cmdline_user_args().has("--wsettings") and _intro == null and not settings_panel.visible and not get_tree().paused:  # Test: Esc > Einstellungen
		_toggle_pause()
		_open_settings()
	if OS.get_cmdline_user_args().has("--wdrive"):
		_autopilot()
	for a in OS.get_cmdline_user_args():
		# Test: --wcam=zurück:höhe:voraus[:drehung]  Kamera hinter/über dem Auto (Landschaft von oben ansehen)
		if a.begins_with("--wcam=") and player:
			var cc := a.substr(7).split(":")
			if _wcam == null:
				_wcam = Camera3D.new()
				_wcam.far = 6000.0
				_wcam.fov = 60.0
				world.add_child(_wcam)
			var fwd := -player.global_basis.z
			if cc.size() > 3:
				fwd = fwd.rotated(Vector3.UP, deg_to_rad(float(cc[3])))
			var cp := player.global_position
			_wcam.global_position = cp - fwd * float(cc[0]) + Vector3.UP * float(cc[1])
			_wcam.look_at(cp + fwd * float(cc[2]), Vector3.UP)
			_wcam.make_current()
		if a.begins_with("--camat=") and player:  # Test: freie Kamera bei x:y:z, Blick auf tx:ty:tz (Plakate, Wände)
			var cv := a.substr(8).split(":")
			if _wcam == null:
				_wcam = Camera3D.new()
				_wcam.far = 6000.0
				_wcam.fov = 50.0
				world.add_child(_wcam)
			_wcam.global_position = Vector3(float(cv[0]), float(cv[1]), float(cv[2]))
			_wcam.look_at(Vector3(float(cv[3]), float(cv[4]), float(cv[5])), Vector3.UP)
			_wcam.make_current()
		if a.begins_with("--ctest="):
			if _ct.is_empty():
				_ctest_setup(a.substr(8))
			_ctest_step(dt)
	if _hitch:
		_hitch_frame(dt)
	_shot_check(dt)
	_update_daylight(dt)
	_prof_t = Time.get_ticks_usec()
	if _intro == null:  # beim Anflug nichts nachbauen: kein Ruckler, keine Stadt taucht im Bild auf
		_update_streaming()
	_prof_mark("streaming")
	_spawn_queued(3)
	_prof_mark("spawn")
	_update_traffic_sound(dt)
	_update_markers()
	_update_secrets(dt)
	_check_near_miss()
	_update_world_drift(dt)
	_update_challenger(dt)
	_update_feed(dt)
	_update_level_banner(dt)
	_update_last_spot(dt)
	_update_drift_zones(dt)
	_prof_mark("rest")
	var tacho = hud["tacho"]
	tacho.rpm = player.rpm
	tacho.speed_kmh = int(absf(player.speed_fwd) * 3.6)
	tacho.gear = "R" if player.reverse_gear or player.speed_fwd < -0.5 else str(player.gear)
	tacho.nitro = player.nitro
	tacho.heat = player.engine_heat
	tacho.nitro_on = player.nitro_on
	_update_district()
	if _area_t > 0.0:
		_area_t -= dt
		hud["area"].modulate.a = 0.9 * clampf(_area_t / 0.6, 0.0, 1.0)
		hud["area"].visible = true
	else:
		hud["area"].modulate.a = 0.0
		hud["area"].visible = false
	if _intro != null:
		_intro.step(dt)  # nach dem Tageslicht (setzt den Nebel nach Höhe), vor der Unschärfe
	_update_speed_fx(dt)


## Stadtviertel: beim Wechsel in eine andere Gegend steht ihr Name oben (wie im Rennen), nicht beim ersten Hineinfahren
## in die Stadt (da steht der Ortsname)
var _village_shown := ""
var _vill := []


func _update_district() -> void:
	# Gelände (seit 2.39): Name beim Hineinfahren, wie bei Vierteln und Dörfern
	var on: String = str(player.offroad.get("name", "")) if not player.offroad.is_empty() else ""
	if on != _offroad_shown:
		_offroad_shown = on
		if on != "":
			hud["area"].text = on.to_upper()
			_area_t = 4.0
			_reach_place("gelaende:" + on, on, PLACE_XP)
	if on != "":
		return
	# Autobahn über Land: Name des nächsten Dorfes einblenden, wenn man vorbeifährt (wie die Gebietsnamen in NFS)
	if not active.is_empty() and active["kind"] == "seg" and land:
		var pp := Vector2(player.global_position.x, player.global_position.z)
		var near := ""
		if _vill.is_empty():
			_vill = land.villages()
			if layout.has("center"):
				_vill.append([Vector2(layout["center"].x, layout["center"].z), Layout.CENTER_NAME])
		for v in _vill:
			if pp.distance_to(v[0]) < (Layout.CENTER_R if v[1] == Layout.CENTER_NAME else 650.0):
				near = v[1]
		if near != "" and near != _village_shown:
			hud["area"].text = near.to_upper()
			_area_t = 4.0
		_village_shown = near
		return
	if active.is_empty() or active["kind"] == "seg" or player.path_id != 0:
		return
	var arr: Array = (active["track"] as Dictionary)["districts"]
	if arr.is_empty():
		return
	var di := clampi(int(player.progress / Track.DISTRICT_LEN), 0, arr.size() - 1)
	var key: String = arr[di]
	if active != _district_entry:
		_district_entry = active
		_district_key = key
		return
	if key != _district_key:
		_district_key = key
		hud["area"].text = tr(Track.DISTRICTS[key]["name"])
		_area_t = 4.0


## Knapp vorbei (wie in Underground): nur bei hohem Tempo und wirklich knapp. Ab 120 km/h, mindestens 40 km/h
## schneller als das Auto, an dem man vorbeizieht (oder Gegenverkehr), mit höchstens 1,2 m Luft zwischen den
## Karosserien. Je knapper und schneller, desto mehr Nitro; unter 0,5 m „SEHR KNAPP“. Mehrere hintereinander
## (je höchstens 4 s Abstand) zählen als Kette und geben mehr. Wer es rammt, bekommt nichts (das Auto ist dann ein
## Wrack, und eine Berührung schließt den Bonus ohnehin aus: die Luft muss größer als 0,1 m bleiben).
const NEAR_MIN_V := 120.0 / 3.6
const NEAR_REL_V := 40.0 / 3.6
const NEAR_GAP := 1.2

func _check_near_miss() -> void:
	if not player.controls_enabled:
		return
	_near_chain_t -= get_process_delta_time()
	if _near_chain_t <= 0.0:
		_near_chain = 0
	var fwd: Vector3 = -player.global_basis.z
	var right := Vector3(-fwd.z, 0, fwd.x).normalized()
	var v := player.velocity.length()
	for t in traffic:
		if not is_instance_valid(t) or t.wrecked or not t.is_inside_tree() or t == challenger:
			continue
		var rel: Vector3 = t.global_position - player.global_position
		var id: int = t.get_instance_id()
		if rel.length() > 30.0:
			_near.erase(id)
			continue
		if v < NEAR_MIN_V or _near.has(id) or absf(rel.y) > 3.0:
			continue
		var along := rel.dot(fwd)
		if absf(along) > (float(t.length) / 2.0 + 1.0):
			continue  # erst zählen, wenn man auf gleicher Höhe ist
		var gap: float = absf(rel.dot(right)) - player.half_width - float(t._half_w)
		var tv: Vector3 = -t.global_basis.z * float(t.speed)
		var relv := (player.velocity - tv).dot(fwd)
		if gap < 0.1 or gap > NEAR_GAP or absf(relv) < NEAR_REL_V:
			continue
		_near[id] = true
		_near_chain += 1
		_near_chain_t = 4.0
		var close := 1.0 - (gap - 0.1) / (NEAR_GAP - 0.1)  # 0 bei 1,2 m, 1 bei 0,1 m
		var pts := int(round((250.0 + 350.0 * close) * clampf(v / NEAR_MIN_V, 1.0, 1.6) * (1.0 + 0.25 * (_near_chain - 1))))
		var txt := tr("SEHR KNAPP") if gap < 0.5 else tr("KNAPP VORBEI")
		if _near_chain > 1:
			txt += "  x%d" % _near_chain
		_flash(txt, Color(1.0, 0.55, 0.15) if gap < 0.5 else Color(1.0, 0.85, 0.2), pts)
		if drift_meter:
			drift_meter.add_bonus(pts * 0.6, "KNAPP VORBEI")  # im Drift: Extrapunkte für die Kette (seit 2.45)
		Sfx.play("whoosh", -9.0 if gap < 0.5 else -12.0, randf_range(1.1, 1.3))


## Einblendung über der Minikarte; Punkte füllen Nitro (wie im Rennen: 300 Punkte = 7,5 % einer Serienflasche)
func _flash(text: String, col: Color, pts := 0, xp := -1) -> void:
	if _feed == null:
		return
	var l := _label(_feed, 11)
	l.add_theme_color_override("font_color", col)
	l.text = text + ("   +%d" % pts if pts > 0 else "")
	l.set_meta("t", 3.2)
	while _feed.get_child_count() > 4:
		var old := _feed.get_child(0)
		_feed.remove_child(old)
		old.queue_free()
	if pts > 0:
		player.nitro = minf(player.nitro + minf(pts / 4000.0, 0.12) / player.nitro_cap, 1.0)
		# Stilpunkte sind Erfahrung (seit 2.32), in der freien Fahrt seit 2.35 nur ein Zehntel (Driften eigens, siehe
		# DRIFT_XP): Rennen sollen deutlich mehr bringen (ein Rennsieg 3000 bis 7500 XP, eine Minute Driften gut 600)
		var lines := GameState.add_xp(xp if xp >= 0 else int(round(pts * WORLD_XP)), false)
		if not lines.is_empty():
			_show_level_up(lines)
		_update_level_hud()


# --- Driftzonen (seit 2.45, drift_zones.gd) ------------------------------------------------------------------

## In jeder Stadt der kurvigste Abschnitt der Hauptstraße: wer vorwärts über die orange Linie fährt, startet die Zone;
## alle Drifts bis zur zweiten Linie zählen (die laufende Kette wird dort gutgeschrieben). Bronze, Silber, Gold je nach
## Länge; neue Medaillen bringen Erfahrung, die Bestleistung steht am Schild. Abgebrochen: rückwärts, von der
## Hauptstraße ab (über 3 s), im Autobahn-Rennen.
const DZ_STAR_XP := 400
var _dz := {}  # Rennen (Stadt) -> Zone {e, d0, d1, targets, key, name, label}
var _dz_on: Dictionary = {}
var _dz_score := 0
var _dz_last := 0.0
var _dz_prev := -1.0
var _dz_off_t := 0.0


func _add_drift_zone(e: Dictionary) -> void:
	var tr: Dictionary = e["track"]
	var z := DriftZones.plan(tr)
	if z.is_empty():
		return
	var ri: int = e["race_index"]
	var town := str(Catalog.RACES[ri].get("town", ""))
	z["e"] = e
	z["key"] = "%s#%d" % [town, ri]
	z["name"] = town
	z["targets"] = DriftZones.targets(z)
	var best := int(GameState.drift_best.get(z["key"], 0))
	z["label"] = DriftZones.build_gates(tr, z, tr("DRIFTZONE"), _dz_best_line(best, z["targets"]))
	_dz[ri] = z
	if minimap:
		minimap.add_zone(z["key"], DriftZones.polyline(tr, z, e["xf"]))


func _dz_best_line(best: int, tg: Array) -> String:
	if best <= 0:
		return tr("GOLD %s") % DriftMeter.fmt(int(tg[2]))
	var st := DriftZones.stars(best, tg)
	return tr("BESTE %s") % DriftMeter.fmt(best) + ("  ·  " + tr(DriftZones.STARS[st - 1]) if st > 0 else "")


func _dzone_test(ri: int) -> void:
	if not _dz.has(ri):
		print("DZTEST: keine Driftzone für Rennen ", ri)
		return
	var z: Dictionary = _dz[ri]
	var e: Dictionary = z["e"]
	var tr: Dictionary = e["track"]
	var d := float(z["d0"]) - 40.0
	var xf: Transform3D = (e["xf"] as Transform3D) * Track.xform_at(tr["curve"], d, Track.lane_lat(tr, d, 2.25), true)
	xf.origin.y += 0.5
	player.place(xf)
	player.track = tr
	_set_active(e)
	print("DZTEST Zone %s: %.0f bis %.0f m, Ziele %s" % [z["name"], z["d0"], z["d1"], str(z["targets"])])


func _dz_add(pts: int) -> void:
	if not _dz_on.is_empty():
		_dz_score += pts


func _update_drift_zones(dt: float) -> void:
	if player == null or drift_meter == null:
		return
	if hrace != null or not player.controls_enabled:
		if not _dz_on.is_empty():
			_dz_cancel()
		_dz_prev = -1.0
		return
	if _dz_on.is_empty():
		# Einfahrt: auf der Hauptstraße dieser Stadt vorwärts über die erste Linie
		if active.is_empty() or active["kind"] != "city" or player.path_id != 0 or not _dz.has(active["race_index"]):
			_dz_prev = -1.0
			return
		var z: Dictionary = _dz[active["race_index"]]
		if not is_same(z["e"], active):
			return
		var p: float = player.progress
		if _dz_prev >= 0.0 and _dz_prev < float(z["d0"]) and p >= float(z["d0"]) and p - _dz_prev < 30.0:
			_dz_on = z
			_dz_score = 0
			_dz_last = p
			_dz_off_t = 0.0
			hud["area"].text = tr("DRIFTZONE %s") % str(z["name"]).to_upper()
			_area_t = 3.0
		_dz_prev = p
		return
	var zz := _dz_on
	if is_same(active, zz["e"]) and player.path_id == 0:
		var p: float = player.progress
		if p >= float(zz["d1"]):
			_dz_finish()
			return
		if p < _dz_last - 25.0:
			_dz_cancel()
			return
		_dz_last = maxf(_dz_last, p)
		_dz_off_t = 0.0
	else:
		_dz_off_t += dt
		if _dz_off_t > 3.0:
			_dz_cancel()
			return
	var tg: Array = zz["targets"]
	var cur: int = _dz_score + int(drift_meter.value())
	var nxt := ""
	for k in tg.size():
		if cur < int(tg[k]):
			nxt = tr(DriftZones.STARS[k]) + " " + DriftMeter.fmt(int(tg[k]))
			break
	drift_meter.zone_text = "%s  ·  %s%s" % [tr("DRIFTZONE %s") % str(zz["name"]).to_upper(), DriftMeter.fmt(cur),
		("  /  " + nxt) if nxt != "" else "  ·  " + tr("GOLD")]


func _dz_finish() -> void:
	drift_meter.bank_now()  # die laufende Kette zählt noch (banked -> _dz_add)
	var z := _dz_on
	_dz_on = {}
	drift_meter.zone_text = ""
	var tg: Array = z["targets"]
	var best := int(GameState.drift_best.get(z["key"], 0))
	var st := DriftZones.stars(_dz_score, tg)
	var xp := maxi(st - DriftZones.stars(best, tg), 0) * DZ_STAR_XP
	if _dz_score > best:
		GameState.drift_best[z["key"]] = _dz_score
		best = _dz_score
		GameState.save_game()
	var medal := tr(DriftZones.STARS[st - 1]) if st > 0 else tr("KEINE MEDAILLE")
	_flash("%s: %s  ·  %s" % [tr("DRIFTZONE %s") % str(z["name"]).to_upper(), DriftMeter.fmt(_dz_score), medal],
		UI.GOLD if st == 3 else Color(1.0, 0.6, 0.2), xp, xp)
	if is_instance_valid(z.get("label")):
		(z["label"] as Label3D).text = tr("DRIFTZONE") + "\n" + _dz_best_line(best, tg)
	print("DRIFTZONE %s: %d Punkte, %s (Ziele %s), %d XP" % [z["name"], _dz_score, medal, str(tg), xp])


func _dz_cancel() -> void:
	_dz_on = {}
	drift_meter.zone_text = ""
	_flash(tr("DRIFTZONE ABGEBROCHEN"), Color(1.0, 0.35, 0.3))


# --- Autobahn-Rennen (seit 2.43, highway_race.gd) -------------------------------------------------------------

## Blaue Lichtsäule am Start (auf der Auffahrt, kurz vor dem Ortsausgang), Name darüber; gewonnen: golden
func _add_hw_marker(i: int) -> void:
	var df: Dictionary = hw_defs[i]
	var won: bool = df["name"] in GameState.highway_won
	var col: Color = UI.GOLD if won else HighwayRace.AB_COL
	var m := Node3D.new()
	m.transform = df["start_xf"]
	m.position.y = 0.0
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
	lbl.text = str(df["name"]).to_upper()
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.font = UI.font("wide", 0.15)
	lbl.font_size = 96
	lbl.pixel_size = 0.02
	lbl.modulate = col
	lbl.outline_size = 12
	lbl.outline_modulate = Color(0, 0, 0, 0.8)
	lbl.position.y = 9.0
	m.add_child(lbl)
	var ol := OmniLight3D.new()
	ol.light_color = col
	ol.light_energy = 2.0
	ol.omni_range = 16.0
	ol.position.y = 3.0
	m.add_child(ol)
	world.add_child(m)
	_hw_markers[i] = m


func _update_hw_markers(p: Vector3) -> void:
	var near := -1
	for i in _hw_markers:
		var m: Node3D = _hw_markers[i]
		var q: Vector3 = m.global_position
		var dd := Vector2(p.x - q.x, p.z - q.z).length()
		if dd < MARKER_R:
			near = i
		var beam: MeshInstance3D = m.get_node("Beam")
		var a := 0.16 * clampf((dd - MARKER_R - 2.0) / 25.0, 0.0, 1.0)
		(beam.material_override as StandardMaterial3D).albedo_color.a = a
		beam.visible = a > 0.005
	if near != _near_hw:
		_near_hw = near
		if near >= 0:
			var df: Dictionary = hw_defs[near]
			_reach_place("hw:" + str(df["name"]), str(df["name"]), 0)
			var line := tr("Enter: Autobahn-Rennen starten")
			if GameState.best_times.has(df["name"]):
				line += "\n" + tr("Bestzeit: %s") % HighwayRace._fmt(float(GameState.best_times[df["name"]]))
			hud["prompt"].text = "%s\n%s" % [str(df["name"]).to_upper(), line]
			hud["prompt"].visible = true
		else:
			hud["prompt"].visible = false
			_near_marker = -2  # Hinweis an einem Rennen-Marker neu zeigen


func _start_highway(i: int) -> void:
	if hrace != null or player == null:
		return
	_remove_challenger()
	hud["prompt"].visible = false
	if map_view and map_view.visible:
		map_view.visible = false
		_unpause()
	for k in _hw_markers:
		(_hw_markers[k] as Node3D).visible = false  # im Rennen keine Startsäulen
	hrace = HighwayRace.new()
	hrace.w = self
	add_child(hrace)
	hrace.start(hw_defs[i])


## highway_race.gd: Rennen vorbei (Ziel, aufgegeben, abgebrochen); Startsäule golden, wenn gewonnen
func _highway_done() -> void:
	hrace = null
	_near_hw = -2
	_set_target(target)
	for k in _hw_markers:
		(_hw_markers[k] as Node3D).visible = true
	for i in _hw_markers:
		if hw_defs[i]["name"] in GameState.highway_won:
			var m: Node3D = _hw_markers[i]
			for c in m.get_children():
				if c is Label3D:
					(c as Label3D).modulate = UI.GOLD
				elif c is OmniLight3D:
					(c as OmniLight3D).light_color = UI.GOLD
				elif c is MeshInstance3D:
					var mt := (c as MeshInstance3D).material_override as StandardMaterial3D
					var a: float = mt.albedo_color.a
					mt.albedo_color = Color(UI.GOLD.r, UI.GOLD.g, UI.GOLD.b, a)
					if mt.emission_enabled:
						mt.emission = UI.GOLD


## Esc > Rennen aufgeben
func _give_up() -> void:
	_toggle_pause()
	if hrace != null:
		hrace.abort(tr("RENNEN AUFGEGEBEN"))


# --- Letzter Ort und entdeckte Städte (seit 2.42) -----------------------------------------------------------------

## Beim Losfahren geht es dort weiter, wo man zuletzt war. Gemerkt wird alle 3 s eine sichere Stelle: das Auto steht
## oder fährt aufrecht auf einer Fahrbahn oder im Gelände (nicht in der Luft, im Wasser, beim Überschlag oder Anflug).
## In die Datei (im Browser auch in den localStorage) höchstens alle 20 s, dazu vor Rennen, Garage und Schnellreise
## und beim Schließen des Fensters.
const SPOT_EVERY := 3.0
const SPOT_SAVE := 20.0
## Erfahrung für eine neu entdeckte Stadt (ein Rennsieg bringt 3000 bis 7500, eine Minute Driften gut 600)
const TOWN_XP := 500
var _spot_t := 0.0
var _spot_save_t := 0.0
var _spot_dirty := false


func _update_last_spot(dt: float) -> void:
	_spot_t += dt
	_spot_save_t += dt
	if _spot_t >= SPOT_EVERY:
		_spot_t = 0.0
		_note_spot()
	if _spot_dirty and _spot_save_t > SPOT_SAVE:
		_save_spot()


## Stelle merken: xf mit force (Rennen-Marker, Ankunft), sonst wo das Auto gerade ist, wenn das sicher ist
func _note_spot(xf := Transform3D(), force := false) -> void:
	if not force:
		if player == null or _intro != null or not player.controls_enabled or player.airborne or player.sinking > 0.0 \
				or player.tumbling or player.global_basis.y.y < 0.9:
			return
		var on_road: bool = not player.loc.is_empty() and float(player.loc.get("score", 1.0)) < -0.3
		if not on_road and player.offroad.is_empty():
			return
		xf = player.global_transform
	var f := -xf.basis.z
	GameState.world_pos = [snappedf(xf.origin.x, 0.01), snappedf(xf.origin.y, 0.01), snappedf(xf.origin.z, 0.01),
		snappedf(atan2(-f.x, -f.z), 0.001)]
	_spot_dirty = true


func _save_spot() -> void:
	_spot_save_t = 0.0
	_spot_dirty = false
	GameState.save_game()


## Stadt erreicht: als letzte merken; beim ersten Mal ist die Schnellreise dorthin frei (Zeile über der Minikarte, etwas
## Erfahrung). Beim Laden (noch kein HUD) still, etwa die Startstadt eines neuen Spiels.
func _reach_town(town: String) -> void:
	if not GameState.reach_town(town):
		return
	print("STADT entdeckt: ", town)
	_spot_dirty = true
	if _feed == null:
		return
	_flash(tr("STADT ENTDECKT: %s") % town.to_upper(), UI.GOLD, TOWN_XP, TOWN_XP)
	_flash(tr("Springen hierher frei (Karte: M)"), Color(0.75, 0.8, 0.88))
	GameState.save_game()


# --- Verstecktes: Werkstätten und Kennzeichen (seit 2.50, secrets.gd) -------------------------------------------

const SHOP_XP := 800
const PLATE_XP := 400
var _secrets: Array = []  # {key, kind ("shop"/"plate"), town, e, pos (Welt), node, xf (Ankunft)}


## Stadt gebaut: Werkstatt und Kennzeichen der Stadt (nur in ihrer ersten Strecke, mehrere Rennen teilen sich die Stadt)
func _add_secrets(e: Dictionary) -> void:
	var town := str(Catalog.RACES[e["race_index"]].get("town", ""))
	if town == "" or _town_race(town) != e["race_index"]:
		return
	var trk: Dictionary = e["track"]
	var root: Node3D = trk["node"]
	var xf: Transform3D = e["xf"]
	var pl := Secrets.plan(trk, int(e["race"].get("seed", 1)))
	var ks := "werkstatt:" + town
	if Catalog.find_option("paint", ks) >= 0:
		var shop: Dictionary = pl["shop"]
		var n := Secrets.build_shop(shop, GameState.place_known(ks))
		root.add_child(n)
		var wp: Vector3 = xf * (shop["p"] as Vector3)
		var away: Vector3 = xf.basis * (shop["face"] as Vector3)
		_secrets.append({"key": ks, "kind": "shop", "town": town, "e": e, "pos": wp, "node": n,
			"yaw": atan2(-away.z, away.x)})
	var kp := "kennzeichen:" + town
	var pi := Catalog.find_option("plate", kp)
	if pi >= 0 and not GameState.place_known(kp):
		var plate: Dictionary = pl["plate"]
		var n2 := Secrets.build_plate(plate, str(Catalog.PARTS["plate"]["options"][pi]["code"]))
		root.add_child(n2)
		_secrets.append({"key": kp, "kind": "plate", "town": town, "e": e, "pos": xf * (plate["p"] as Vector3), "node": n2})
	if OS.get_cmdline_user_args().has("--worldlog"):
		for sx in _secrets:
			if sx["town"] == town:
				print("VERSTECK %s %s bei %s" % [town, sx["kind"], str(sx["pos"])])


func _update_secrets(dt: float) -> void:
	if player == null or _secrets.is_empty():
		return
	var pp := player.global_position
	for i in range(_secrets.size() - 1, -1, -1):
		var s: Dictionary = _secrets[i]
		if s["e"]["state"] != "ready" or not is_instance_valid(s["node"]):
			_secrets.remove_at(i)  # Stadt entladen: kommt beim nächsten Bau wieder
			continue
		var q: Vector3 = s["pos"]
		if s["kind"] == "plate":
			(s["node"] as Node3D).get_node("Spin").rotate_y(dt * 1.4)
			if Vector2(pp.x - q.x, pp.z - q.z).length() < Secrets.PLATE_R and absf(pp.y + 1.0 - q.y) < 3.0:
				_found_secret(s)
				(s["node"] as Node3D).queue_free()
				_secrets.remove_at(i)
		elif not GameState.place_known(s["key"]):
			if Vector2(pp.x - q.x, pp.z - q.z).length() < Secrets.SHOP_R:
				_found_secret(s)


func _found_secret(s: Dictionary) -> void:
	if not GameState.reach_place(s["key"]):
		return
	var f := -player.global_basis.z
	GameState.secret_pos[s["key"]] = [snappedf(player.global_position.x, 0.01), snappedf(player.global_position.y, 0.01),
		snappedf(player.global_position.z, 0.01), snappedf(atan2(-f.x, -f.z), 0.001)]
	print("VERSTECK gefunden: ", s["key"])
	Sfx.ui("install")
	if s["kind"] == "shop":
		var opt: Dictionary = Catalog.PARTS["paint"]["options"][Catalog.find_option("paint", s["key"])]
		_flash(tr("VERSTECKTE WERKSTATT: %s") % str(s["town"]).to_upper(), Color(1.0, 0.62, 0.16), SHOP_XP, SHOP_XP)
		_flash(tr("Neuer Lack in der Garage: %s") % tr(str(opt["name"])), Color(0.75, 0.8, 0.88))
		_flash(tr("Springen hierher frei (Karte: M)"), Color(0.75, 0.8, 0.88))
	else:
		var po: Dictionary = Catalog.PARTS["plate"]["options"][Catalog.find_option("plate", s["key"])]
		_flash(tr("KENNZEICHEN GEFUNDEN: %s") % str(po["code"]), UI.GOLD, PLATE_XP, PLATE_XP)
		_flash(tr("In der Garage: Optik > Kennzeichen"), Color(0.75, 0.8, 0.88))
	GameState.save_game()


## Erfahrung für ein neu entdecktes Gelände (eine Stadt bringt 500)
const PLACE_XP := 300


## Ort außer einer Stadt erreicht (seit 2.49): beim ersten Mal ein Sprungziel auf der Karte (Zeile über der Minikarte)
func _reach_place(key: String, label: String, xp: int) -> void:
	if not GameState.reach_place(key):
		return
	print("ORT entdeckt: ", key)
	_spot_dirty = true
	if _feed == null:
		return
	if xp > 0:
		_flash(tr("NEU AUF DER KARTE: %s") % label.to_upper(), UI.GOLD, xp, xp)
	else:
		_flash(tr("NEU AUF DER KARTE: %s") % label.to_upper(), UI.GOLD)
	_flash(tr("Springen hierher frei (Karte: M)"), Color(0.75, 0.8, 0.88))
	GameState.save_game()


# --- Fahrer-Level und Drift in der freien Fahrt (seit 2.32) ------------------------------------------------------

var _xp_k := -1.0  # angezeigter Anteil der Leiste (läuft weich nach)
const WORLD_XP := 0.1  # Anteil der Stilpunkte in der freien Fahrt, der als Erfahrung zählt
const DUEL_XP := 1500  # gewonnenes Duell (zählt wie ein kleines Rennen)
const DRIFT_XP := 0.04  # Erfahrung je Punkt einer Drift-Kette in der freien Fahrt (ohne Multiplikator)


func _update_level_hud() -> void:
	if not hud.has("lvl"):
		return
	var li := GameState.level_info()
	if _lu_t <= 0.0:
		hud["lvl"].text = tr("LEVEL %d") % li["level"] + "   ·   " + GameState.title_name().to_upper() + "   ·   " \
			+ "%d / %d XP" % [li["into"], li["need"]]
		hud["lvl"].remove_theme_color_override("font_color")
		hud["lvl"].modulate.a = 0.75
	var k := clampf(float(li["into"]) / float(li["need"]), 0.0, 1.0)
	if _xp_k < 0.0 or k < _xp_k:
		_xp_k = k  # Start oder neues Level: von vorn
	hud["lvl_fill"].set_meta("k", k)


## Leiste weich zum Stand nachführen (sonst springt sie bei jedem Punkt)
func _update_xp_bar(dt: float) -> void:
	if not hud.has("lvl_fill"):
		return
	var k: float = hud["lvl_fill"].get_meta("k", 0.0)
	_xp_k = move_toward(_xp_k, k, dt * 0.6)
	var w: float = (hud["lvl_fill"].get_parent() as Control).size.x
	hud["lvl_fill"].offset_right = w * _xp_k


func _show_level_up(lines: Array) -> void:
	# erste Zeile "LEVEL n", darunter höchstens ein Gewinn (Auto oder Stufe zuerst), der Rest steht in der Garage
	var best := ""
	for l in lines.slice(1):
		if best == "" or str(l).begins_with(tr("Auto: ")) or str(l).begins_with(tr("STUFE")):
			best = l
			if str(l).begins_with(tr("Auto: ")):
				break
	var more := lines.size() - 1 - (1 if best != "" else 0)
	# seit 2.35 in der kleinen Zeile über der XP-Leiste (vorher groß über dem Auto): sie leuchtet 4 s grün auf
	var txt := tr("%s ERREICHT") % str(lines[0]) + ("   ·   " + best if best != "" else "") + (("   ·   " + tr("+%d mehr") % more) if more > 0 else "")
	hud["lvl"].text = txt
	hud["lvl"].add_theme_color_override("font_color", Color(0.45, 1.0, 0.6))
	hud["lvl"].modulate.a = 1.0
	_lu_t = 4.0
	Sfx.ui("go")


func _update_level_banner(dt: float) -> void:
	_update_xp_bar(dt)
	if _lu_t > 0.0:
		_lu_t -= dt
		if _lu_t <= 0.0:
			_update_level_hud()  # zurück zu Level und XP
		if _lu_t <= 0.0:
			hud["levelup"].visible = false
	# XP gesammelt speichern (nicht bei jedem knapp vorbei die Datei schreiben)
	_xp_save_t += dt
	if GameState.xp_dirty and _xp_save_t > 15.0:
		_xp_save_t = 0.0
		GameState.save_game()


## Driften in der offenen Welt gibt Punkte wie im Rennen (Winkel x Tempo), gutgeschrieben, wenn der Drift sauber zu
## Ende ist. Lange Ketten zählen mehr: Drifts, die mit weniger als knapp 1 s Pause ineinander übergehen, bilden eine
## Kette, je 3 s Driftzeit +1 auf den Multiplikator (bis x5). Wand oder Crash: Kette weg. Sprünge geben Punkte nach
## Flugzeit. Alles läuft über _flash: Nitro, XP, Zeile über der Minikarte.
func _update_world_drift(dt: float) -> void:
	if player == null or not player.controls_enabled:
		return
	if player.landings != _dr_landings:
		_dr_landings = player.landings
		if player.last_air > 0.6:
			_flash(tr("SPRUNG  %.1f s") % player.last_air, Color(0.4, 0.85, 1.0), int(player.last_air * 300.0 / 10.0) * 10)
	drift_meter.step(dt)


## Drift gutgeschrieben (drift_meter): Zeile über der Minikarte mit Nitro und Erfahrung (ohne Multiplikator: eine
## Minute gutes Driften bringt so gut 600 XP, ein Rennsieg 3000 bis 7500); in einer Driftzone zählt er dort mit
func _on_drift_banked(pts: int, raw: float, m: int) -> void:
	_flash(tr("DRIFT") + ("  x%d" % m if m > 1 else ""), Color(1.0, 0.85, 0.2), pts, int(raw * DRIFT_XP))
	_dz_add(pts)


func _on_drift_lost(pts: int) -> void:
	if pts >= 150:
		_flash(tr("KETTE VERLOREN"), Color(1.0, 0.35, 0.3))


func _update_feed(dt: float) -> void:
	for l in _feed.get_children():
		var t: float = l.get_meta("t") - dt
		l.set_meta("t", t)
		l.modulate.a = clampf(t / 0.5, 0.0, 1.0)
		if t <= 0.0:
			_feed.remove_child(l)
			l.queue_free()


# --- Herausforderer ------------------------------------------------------------------------------------------

## Alle paar Minuten freier Fahrt auf der Autobahn taucht einer auf (-- --challenger: nach 3 s, zum Testen).
## Vor dem Duell überholt er dich und fährt dann etwas langsamer vor dir her; dicht dran (35 m) fordert Enter ihn heraus.
## Im Duell fährt er so schnell wie dein Auto (Schwierigkeit: 92/97/100 %) und schlängelt sich durch den Verkehr.
## 300 m Vorsprung gewinnt, 300 m Rückstand verliert; wer die Autobahn verlässt, gibt auf.
func _update_challenger(dt: float) -> void:
	if not _ct.is_empty() or not _ready_done or quiet or hrace != null:
		return
	if challenger != null and not is_instance_valid(challenger):
		_remove_challenger()  # mit seinem Autobahnstück entfernt
	var pe := _entry_of(player.track)
	var on_ring: bool = not player.track.is_empty() and pe.get("kind", "") == "seg" and pe["race"].get("type", "") != "dreieck" \
		and player.offroad.is_empty()
	if challenger == null:
		if on_ring and absf(player.speed_fwd) > 12.0:
			_ch_t -= dt
			if _ch_t <= 0.0:
				_spawn_challenger()
		return
	var ch = challenger
	var fwd: Vector3 = -ch.global_basis.z
	var rel: Vector3 = player.global_position - ch.global_position
	var gap := rel.dot(fwd)  # + du liegst vorn
	var dist := rel.length()
	var top: float = ch.get_meta("top")
	ch.others = traffic  # die Liste wird beim Entladen neu angelegt
	_ch_pin.global_position = ch.global_position
	var prompt := false
	match _duel:
		0:
			var pv := player.velocity.dot(fwd)
			# noch nicht vorbei: überholen; danach gemütlich (gut 100 km/h), damit du aufschließen kannst
			ch.base_speed = clampf(pv + 9.0, 32.0, top) if gap > -30.0 else 29.0
			prompt = dist < 35.0 and gap < 6.0
			if dist > 700.0:
				_remove_challenger()
				return
		1:
			# Gummiband, aber schwach: liegst du weit vorn, gibt er alles (etwas mehr), weit hinten nimmt er etwas raus
			ch.base_speed = top * (1.03 if gap > 120.0 else (0.96 if gap < -150.0 else 1.0))
			_off_ring_t = 0.0 if on_ring else _off_ring_t + dt
			_update_duel_hud(gap)
			if gap >= DUEL_GAP:
				_end_duel(true)
			elif gap <= -DUEL_GAP or _off_ring_t > 4.0:
				_end_duel(false)
		2:
			if dist > 450.0:
				_remove_challenger()
				return
	if OS.get_cmdline_user_args().has("--challenger"):
		# Test: Verlauf jede Sekunde ("CH ..."), Duell startet von selbst, sobald man dicht dran ist
		_ch_log -= dt
		if _ch_log <= 0.0:
			_ch_log = 0.5
			var lead := "-"
			if is_instance_valid(ch.leader):
				lead = "%.0fm/%dkmh/spur%.1f" % [(ch.leader.progress - ch.progress) * ch.dir, int(ch.leader.speed * 3.6), ch.leader.lateral()]
			print("CH duell=%d abst=%.0f vorsprung=%.0f er=%d du=%d spur=%.1f/%.1f vordermann=%s wagen=%s" % [_duel, dist, gap, int(ch.speed * 3.6),
				int(absf(player.speed_fwd) * 3.6), ch.lane, ch.lateral(), lead, ch.car_id])
		if prompt and _duel == 0:
			_start_duel()
			return
	if prompt != _ch_prompt:
		_ch_prompt = prompt
		hud["duel_prompt"].text = "%s: %s\n%s" % [tr("HERAUSFORDERER"), Catalog.CARS[ch.car_id]["name"].to_upper(), tr("Enter: Duell starten")]
	hud["duel_prompt"].visible = _ch_prompt and _duel == 0 and _near_marker < 0


## Hinter dir auf deiner Fahrbahn einsetzen (170 m zurück, notfalls auf dem Stück davor), ein Auto passend zu deinem
func _spawn_challenger() -> void:
	var e := _entry_of(player.track)
	var tr: Dictionary = e["track"]
	var xf: Transform3D = e["xf"]
	var c: Curve3D = tr["curve"]
	var d := c.get_closest_offset(xf.affine_inverse() * player.global_position)
	var sgn := 1.0 if (xf.basis * Track.frame_at(c, d)["fwd"]).dot(player.velocity) >= 0.0 else -1.0
	var dd := d - sgn * 170.0
	if dd < 5.0 or dd > float(tr["length"]) - 5.0:
		var e2: Dictionary = _seg_next(e, dd > 5.0)
		if e2["state"] != "ready":
			_ch_t = 5.0
			return
		dd = dd - float(tr["length"]) if dd > 5.0 else float(e2["track"]["length"]) + dd
		e = e2
		tr = e["track"]
		if dd < 5.0 or dd > float(tr["length"]) - 5.0:
			_ch_t = 5.0
			return
	# Auto: ungefähr so schnell wie deins, nicht dasselbe
	var mine: float = Catalog.CARS[GameState.current_car]["top_speed"]
	var pool: Array = Catalog.CAR_ORDER.filter(func(id): return id != GameState.current_car \
		and absf(float(Catalog.CARS[id]["top_speed"]) / mine - 1.0) < 0.1 and not id in Catalog.EXOTICS)
	if pool.is_empty():
		pool = Catalog.CAR_ORDER.filter(func(id): return id != GameState.current_car)
	var id: String = pool[_trng.randi() % pool.size()]
	var cfg := {}
	for cat in Catalog.PART_ORDER:
		if cat == "spur":
			continue  # ohne eigene Zufallszahl (seit 2.37), der übrige Verkehr bleibt wie vorher
		cfg[cat] = _trng.randi() % Catalog.PARTS[cat]["options"].size()
		# entfernte Vinyls (seit 2.36 ausgeblendet) auf ein sichtbares umbiegen, ohne weitere Zufallszahl (Felder bleiben
		# gleich). Zoll nicht: die alten relativen Größen gelten weiter (siehe race.gd)
		while cat != "rimsize" and Catalog.PARTS[cat]["options"][cfg[cat]].get("hidden", false):
			cfg[cat] = (cfg[cat] + 5) % Catalog.PARTS[cat]["options"].size()
	cfg["spur"] = (int(cfg["paint"]) + int(cfg["rims"])) % Catalog.PARTS["spur"]["options"].size()
	cfg["rimsize"] = Builder.rival_rimsize(id, cfg)  # wie bei den Gegnern im Rennen: keine Riesenfelgen, nichts unter Minimum
	var ch := Challenger.new()
	ch.process_mode = Node.PROCESS_MODE_PAUSABLE
	ch.curve = tr["curve"]
	ch.track = tr
	ch.blocks = tr["blocks"]
	ch.progress = dd
	ch.lane = sgn * 6.75
	ch.dir = sgn
	ch.speed = maxf(absf(player.speed_fwd) + 6.0, 28.0)
	ch.base_speed = ch.speed
	ch.track_length = tr["length"]
	ch.parent_basis = (e["xf"] as Transform3D).basis
	ch.player_path = -1
	ch.on_end = _traffic_end
	ch.others = traffic
	ch.set_meta("e", e)
	ch.set_meta("top", player.top_speed * PlayerCar.VMAX_K * [0.92, 0.97, 1.0][GameState.difficulty])
	(tr["node"] as Node).add_child(ch)
	ch.setup_racer(id, cfg)
	ch.place()
	traffic.append(ch)
	challenger = ch
	_duel = 0
	_ch_pin.set_meta("off", false)
	_flash(tr("HERAUSFORDERER IM ANMARSCH"), Color(1.0, 0.35, 0.3))


func _start_duel() -> void:
	_duel = 1
	_off_ring_t = 0.0
	_ch_prompt = false
	hud["duel_prompt"].visible = false
	hud["duel"].visible = true
	Sfx.ui("go")
	_flash(tr("DUELL: 300 M VORSPRUNG GEWINNT"), Color(1.0, 0.35, 0.3))


func _update_duel_hud(gap: float) -> void:
	var k := clampf(gap / DUEL_GAP, -1.0, 1.0)
	var fill: ColorRect = hud["duel_fill"]
	fill.color = Color(0.3, 1.0, 0.45) if k >= 0.0 else Color(1.0, 0.3, 0.25)
	fill.size.x = absf(k) * 160.0
	fill.position.x = 170.0 if k >= 0.0 else 170.0 - fill.size.x
	hud["duel_label"].text = "%s  %s%d m" % [tr("DUELL"), "+" if gap >= 0.0 else "−", int(absf(gap))]


func _end_duel(won: bool) -> void:
	_duel = 2
	hud["duel"].visible = false
	if won:
		GameState.outruns += 1
		GameState.save_game()
		challenger.base_speed = 22.0  # gibt auf und fällt zurück
		_flash(tr("HERAUSFORDERER ABGEHÄNGT (%d)") % GameState.outruns, Color(0.4, 1.0, 0.5), 1000)
		# Duell gewonnen: Erfahrung wie ein kleines Rennen (die Stilpunkte oben zählen in der Welt nur zu einem Zehntel)
		var dl := GameState.add_xp(DUEL_XP - int(round(1000 * WORLD_XP)), false)
		if not dl.is_empty():
			_show_level_up(dl)
		_update_level_hud()
		Sfx.ui("install")
	else:
		challenger.base_speed = challenger.get_meta("top")
		_flash(tr("DUELL VERLOREN") if _off_ring_t <= 4.0 else tr("DUELL AUFGEGEBEN"), Color(1.0, 0.35, 0.3))


func _remove_challenger() -> void:
	if is_instance_valid(challenger):
		traffic.erase(challenger)
		challenger.queue_free()
	challenger = null
	_duel = 0
	_ch_prompt = false
	if _ch_pin:
		_ch_pin.set_meta("off", true)
	if hud.has("duel"):
		hud["duel"].visible = false
		hud["duel_prompt"].visible = false
	_ch_t = randf_range(90.0, 200.0)


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
		print("WD pos=(%.0f,%.0f) y=%.1f fahrbahn=%.1f luft=%s v=%d strecke=%s weg=%s d=%.0f geladen=%d baut=%s fps=%d verkehr=%d schlange=%d" % [player.global_position.x, player.global_position.z,
			player.global_position.y, (xf * Vector3(0, Track.elev_at(c, d), 0)).y, str(player.airborne),
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
	# seit 2.49 ab 75 km/h, voll bei 225 (vorher 90 bis 235): weniger km/h, das Tempogefühl kommt wie in Underground
	# aus Unschärfe und Lichtspuren
	var sk := smoothstep(75.0, 225.0, kmh)
	# Anflug von oben: Zoom-Unschärfe nur während der Sprünge, Fluchtpunkt ist das Auto im Bild
	var zb: float = _intro.blur * lvl if _intro != null else 0.0
	var blur := lvl * (0.115 * sk * sk + 0.075 * _nitro_fx) + zb
	var sw := lvl * _swing * smoothstep(0.2, 0.5, sk)
	var nit := _nitro_fx if lvl > 0.0 else 0.0
	_fx_rect.visible = blur + absf(sw) > 0.0004 or nit > 0.001
	if _fx_rect.visible:
		fx_mat.set_shader_parameter("blur", blur)
		fx_mat.set_shader_parameter("swing", sw)
		fx_mat.set_shader_parameter("nitro", nit)
		var trail: float = _intro.trail * minf(lvl, 1.0) if _intro != null else 0.0
		fx_mat.set_shader_parameter("speed", maxf(sk * minf(lvl, 1.0), trail) if blur > 0.0 else 0.0)
		fx_mat.set_shader_parameter("focus", _intro.focus if _intro != null else Vector2(0.5, 0.46))


# --- Verkehr ----------------------------------------------------------------------
## Jede geladene Strecke bekommt Verkehr: auf der Autobahn sechs Spuren mit festem Tempo je Spur (so holen sich
## Autos auf derselben Spur nie ein), in den Städten wie im Rennen. Die Autos hängen am Knoten ihrer Strecke und
## verschwinden mit ihr. Am Ende eines Autobahnstücks fahren sie aufs nächste weiter, sonst werden sie außer Sicht
## neu eingesetzt.

func _plan_traffic(e: Dictionary) -> void:
	if not _ct.is_empty() or quiet or e["race"].get("type", "") == "dreieck":
		return  # Autobahndreiecke: Rampen ohne Verkehr (wie die Auffahrten)
	var tr: Dictionary = e["track"]
	var L: float = tr["length"]
	# nachts weniger Verkehr (seit 2.29): die Abstände wachsen bis aufs 1,8-Fache
	var dens := lerpf(1.8, 1.0, float(mood.get("day", 0.0)))
	if e["kind"] == "seg":
		var d := _trng.randf_range(10.0, 80.0)
		while d < L - 10.0:
			var lane: float = Track.AB_LANES[_trng.randi() % Track.AB_LANES.size()]
			var outer := absf(lane) > 10.0
			var kind: String = ["lkw", "lkw", "bus", "van", "van", "sedan"][_trng.randi() % 6] if outer else ["sedan", "sedan", "taxi", "van"][_trng.randi() % 4]
			_tq.append([e, {"d": d, "lane": lane, "speed": AB_SPEED[absf(lane)], "kind": kind}])
			d += _trng.randf_range(60.0, 120.0) * dens
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
		d2 += _trng.randf_range(70.0, 140.0) * dens


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


## Nächstes (fwd) oder voriges Stück desselben Rings
func _seg_next(e: Dictionary, fwd: bool) -> Dictionary:
	var rg: Array = _rings[e["ring"]]
	var i := int(e["seg_i"]) + (1 if fwd else -1)
	if e["race"].get("open", false) and (i < 0 or i >= rg.size()):
		return {"state": "none"}  # Diagonale: am Ende geht es über die Auffahrt weiter, der Verkehr nicht
	return rg[(i + rg.size()) % rg.size()]


## Wagen am Ende seines Wegs: aufs nächste (oder vorige) Autobahnstück, sonst außer Sicht neu einsetzen
func _traffic_end(t: Node) -> void:
	if not is_instance_valid(t) or not t.is_inside_tree():
		return
	var e: Dictionary = t.get_meta("e")
	if e["state"] != "ready":
		return
	if e["kind"] == "seg":
		var fwd: bool = t.progress > t.track_length / 2.0
		var n2: Dictionary = _seg_next(e, fwd)
		if n2["state"] == "ready":
			var nt: Dictionary = n2["track"]
			t.get_parent().remove_child(t)
			(nt["node"] as Node).add_child(t)
			t.set_meta("e", n2)
			t.move_to(nt, 1.5 if fwd else float(nt["length"]) - 1.5)
			return
	if t == challenger:
		_remove_challenger()  # nächstes Stück noch nicht gebaut: lieber weg als außer Sicht neu einsetzen
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
		"frontal": [6.75, -30.0, 180.0, 6.75, -90.0, 30.0, "sedan"],  # Geisterfahrer frontal: Überschlag
		"frontal_slow": [6.75, -6.0, 180.0, 6.75, -40.0, 8.0, "sedan"],  # langsam frontal: zurückprallen
		"wall10": [11.25, 42.0, 10.0, 0.0, 0.0, 0.0, ""],
		"wall30": [11.25, 42.0, 30.0, 0.0, 0.0, 0.0, ""],
		"wall60": [11.25, 42.0, 60.0, 0.0, 0.0, 0.0, ""],
		"wall90": [11.25, 30.0, 90.0, 0.0, 0.0, 0.0, ""],
		"median30": [2.25, 42.0, -30.0, 0.0, 0.0, 0.0, ""],
		"accel": [6.75, 0.0, 0.0, 0.0, 0.0, 0.0, ""],
		"near": [4.0, 42.0, 0.0, 6.75, 14.0, 30.0, "sedan"],  # knapp vorbei: 2,75 m daneben überholen (Nitro)
		"nearslow": [4.0, 30.0, 0.0, 6.75, 14.0, 18.0, "sedan"],  # nur 108 km/h: kein Nitro
		"nearwide": [3.0, 42.0, 0.0, 6.75, 14.0, 30.0, "sedan"],  # 1,9 m Luft: kein Nitro
		"nearclose": [4.6, 42.0, 0.0, 6.75, 14.0, 30.0, "sedan"],  # 0,3 m Luft: SEHR KNAPP
		"chal": [-6.75, 0.0, 0.0, 6.75, 90.0, 30.0, "sedan"],  # Herausforderer (160 km/h) hinter einem Pkw: Spurwechsel?
	}
	var k: Array = cases[case]
	var xf := Track.xform_at(c, d0, Track.lane_lat(tr, d0, k[0]), true)
	xf.basis = xf.basis * Basis(Vector3.UP, deg_to_rad(-k[2]))
	player.place(xf)
	player.velocity = -xf.basis.z * absf(k[1])
	player.speed_fwd = absf(k[1])
	if case.begins_with("near"):
		player.nitro = 0.3
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
	if case == "chal":
		var ch := Challenger.new()
		ch.curve = c
		ch.track = tr
		ch.blocks = tr["blocks"]
		ch.progress = d0 + 10.0
		ch.lane = 6.75
		ch.dir = 1.0
		ch.speed = 44.0
		ch.base_speed = 44.0
		ch.track_length = tr["length"]
		ch.parent_basis = (active["xf"] as Transform3D).basis
		ch.player_path = -1
		ch.others = traffic
		(tr["node"] as Node).add_child(ch)
		ch.setup_racer("kumo", {})
		ch.place()
		traffic.append(ch)
		challenger = ch
	_ct = {"case": case, "t": 0.0, "next": 0.0, "hold": case.begins_with("wall") or case.begins_with("median") or case == "accel",
		"marks": [60, 100, 150, 200, 250]}


func _ctest_step(dt: float) -> void:
	_ct["t"] += dt
	for a in ["steer_left", "steer_right", "accelerate", "nitro", "brake", "handbrake"]:
		Input.action_release(a)
	if _ct["hold"] or _ct["case"].begins_with("rear") or _ct["case"] in ["bus", "near", "nearslow", "nearwide", "nearclose"]:
		Input.action_press("accelerate")
	if _ct["case"] == "accel":
		# Beschleunigung ohne Nitro: Zeit bis 60/100/150/200/250 km/h, danach Endtempo nach 40 s
		var kmh: float = absf(player.speed_fwd) * 3.6
		while not _ct["marks"].is_empty() and kmh >= _ct["marks"][0]:
			print("ACC 0-%d km/h: %.2f s (Gang %d)" % [_ct["marks"][0], _ct["t"], player.gear])
			_ct["marks"].pop_front()
		if _ct["t"] > 40.0:
			print("ACC nach 40 s: %d km/h" % int(kmh))
			get_tree().quit()
		return
	if _ct["t"] < _ct["next"]:
		return
	_ct["next"] += 0.1
	var pl = player
	var s := "CT %s t=%.1f v=%3d fwd=%3d gier=%4d stun=%.2f spin=%.1f roll=%s crashes=%d wand=%d nitro=%.3f" % [_ct["case"], _ct["t"],
		int(pl.velocity.length() * 3.6), int(pl.speed_fwd * 3.6), int(rad_to_deg(pl.global_basis.z.signed_angle_to(Track.frame_at(pl.track["curve"], pl.progress)["fwd"] * -1.0, Vector3.UP))),
		pl.stun, pl._spin, str(pl.tumbling), pl.crashes, pl.wall_hits, pl.nitro]
	if not traffic.is_empty():
		var t = traffic[0]
		var q: Vector3 = t.global_transform.affine_inverse() * pl.global_position
		var inside: bool = absf(q.x) < 1.9 and absf(q.z) < t.length / 2.0 + 2.0
		if traffic.size() > 1:
			s += " | B v=%d spur=%.1f luecke=%.0f" % [int(t.speed * 3.6), t.lateral(), traffic[1].progress - t.progress]
		s += " | ver v=%3d wrack=%s abst=%.1f quer=%.1f laengs=%.1f%s" % [int(t.velocity_vec.length() * 3.6), str(t.wrecked),
			t.global_position.distance_to(pl.global_position), q.x, q.z, " DRIN" if inside else ""]
	if is_instance_valid(challenger) and _ct["case"] == "chal":
		var t0 = traffic[0]
		s += " | herausf v=%d spur=%.1f/%.1f vor_pkw=%.1f" % [int(challenger.speed * 3.6), challenger.lane, challenger.lateral(),
			(t0.progress - challenger.progress)]
	print(s)
	if _ct["t"] > (8.0 if _ct["case"] in ["wreck", "bus", "standing", "chal"] else 3.0):
		get_tree().quit()



# --- Test: ganze Welt auf Überlappungen prüfen (--worldcheck) ------------------------------------
## Baut alle Strecken und prüft jedes Haus und Bauwerk gegen die Fahrbahnen aller anderen Strecken (Ring, Auffahrten,
## Straßen der Nachbarstädte). Gibt jede Überschneidung aus ("WC ...") und am Ende eine Zusammenfassung.
func _world_check() -> void:
	var t0 := Time.get_ticks_msec()
	for e in entries:
		if e["state"] == "none":
			var job := Track.begin(e["race"])
			job["nobatch"] = true
			while Track.step(job) < 1.0:
				pass
			_finish(e, job)
	print("WC alle %d Strecken gebaut in %d ms" % [entries.size(), Time.get_ticks_msec() - t0])
	var total := 0
	var pairs := {}
	for a in entries:
		var xa: Transform3D = a["xf"]
		for o in a.get("feet", []):
			if o.has("ko"):
				continue  # Sperrfläche selbst
			var p: Vector3 = xa * Vector3(o["pos"].x, 0.0, o["pos"].z)
			var r: float = Vector2(o["foot"][3], o["foot"][4]).length() if o.has("foot") else float(o.get("r", 5.0))
			# Gelände (seit 2.39): kein Haus im Zaun und nicht auf seinem Randstreifen
			if Offroad.land_free(Vector2(p.x, p.z), r) < 0.0:
				total += 1
				var gk := "GELAENDE %s" % _wc_name(a)
				pairs[gk] = pairs.get(gk, 0) + 1
				if pairs[gk] <= 3:
					print("WC %s steht im Gelände bei (%.0f, %.0f) r=%.0f" % [_wc_name(a), p.x, p.z, r])
			for b in entries:
				if b == a or _dist(b, p) > r:
					continue
				var loc := Track.locate(b["track"], (b["xf"] as Transform3D).affine_inverse() * p)
				if loc.is_empty():
					continue
				if loc["score"] < r * 0.6 + Track.WALK:
					total += 1
					var key := "%s -> %s" % [_wc_name(a), _wc_name(b)]
					pairs[key] = pairs.get(key, 0) + 1
					if pairs[key] <= 3:
						print("WC %s steht auf %s (%s) bei (%.0f, %.0f) r=%.0f abstand=%.1f" % [_wc_name(a), _wc_name(b),
							loc["path"]["kind"], p.x, p.z, r, loc["score"]])
	# Straßen gegen Straßen: kreuzt eine Stadtstraße den Ring oder eine Nachbarstadt (außer an der eigenen Ausfahrt)?
	for a in entries:
		if a["kind"] != "city":
			continue
		var xa: Transform3D = a["xf"]
		for pth in a["track"]["paths"]:
			var c: Curve3D = pth["curve"]
			var d := 0.0
			while d < c.get_baked_length():
				var p: Vector3 = xa * c.sample_baked(d)
				d += 15.0
				if Vector2(p.x - a["exit"].x, p.z - a["exit"].z).length() < 80.0 \
						or Vector2(p.x - a["exit2"].x, p.z - a["exit2"].z).length() < 80.0:
					continue  # an den eigenen Ausfahrten treffen sich die Straßen absichtlich
				for b in entries:
					if b == a or _dist(b, p) > 30.0:
						continue
					var loc := Track.locate(b["track"], (b["xf"] as Transform3D).affine_inverse() * p)
					if not loc.is_empty() and loc["score"] < 0.0:
						total += 1
						var key := "STRASSE %s -> %s" % [_wc_name(a), _wc_name(b)]
						pairs[key] = pairs.get(key, 0) + 1
						if pairs[key] <= 2:
							print("WC Straße von %s (%s) auf %s (%s) bei (%.0f, %.0f)" % [_wc_name(a), pth["kind"], _wc_name(b),
								loc["path"]["kind"], p.x, p.z])
	print("WC SUMME %d Überschneidungen" % total)
	for k in pairs:
		print("WC   %4d  %s" % [pairs[k], k])
	get_tree().quit()


func _wc_name(e: Dictionary) -> String:
	return ("%s %d/%d" % [e["race"]["name"], e["ring"], e["seg_i"]]) if e["kind"] == "seg" else str(Catalog.RACES[e["race_index"]]["name"])
