extends Node
## Nur für Tests und Videos:
##   -- --drive            Autopilot fährt (weicht Verkehr aus, nutzt Nitro)
##   -- --shot=/pfad/pre   speichert Screenshots
##   -- --quit=40          beendet nach 40 Sekunden
##   -- --demo             klickt sich nach dem Intro durchs Menü (Tuning zeigen, Rennen starten)
##   -- --at=lake|crossing|alley|fork|tunnel|el|stadium|fans|<viertel>|d:<meter>   setzt das Auto nach dem Start direkt vor die Stelle
##   -- --keys=1.5:ui_cancel,2.0:ui_down   drückt Aktionen zu festen Zeiten (Menüs testen, z. B. Zurück im Tuning)
##   -- --race=2           wählt die Strecke (Index in Catalog.RACES)
##   -- --car=shiden       fährt mit diesem Auto (auch in der Garage vorausgewählt)
##   -- --lang=de          Sprache für Bilder (de/en)
##   -- --times=1.5,4,8    Zeitpunkte für Screenshots
##   -- --crash=30:90[:d]  (oder 30:q quer rutschend, 30:k auf die nächste Laterne) setzt das Auto (bei Strecke d) mit 30 m/s im Winkel 90° nach rechts auf die Wand zu,
##                         gibt den Verlauf aus (Überschlag, Flug, Höhe) – Test der Fallphysik
##   -- --block=d:spur     Spieler steht ab dem Start bei Strecke d auf Spur 0–3 und blockiert; gibt Abstände der
##                         Gegner zum Spieler und untereinander aus (Schiebe-Logik)
##   -- --bench            misst während des Rennens Bildzeit, GPU-Zeit und Draw Calls, gibt am Ende "BENCH ..." aus
##   -- --revtest          Gas 4 s, Bremse 4 s (bis rückwärts), Gas 3 s: gibt alle 0,1 s Tempo, Gang und R aus
##   -- --fulltest         Autopilot fährt das ganze Rennen; meldet Hänger, Stürze, Fahrten neben der Strecke, Ruckler,
##                         hängende Gegner und das Ergebnis ("FT ..."), beendet sich 3 s nach dem Ziel
##   -- --branches         Autopilot nimmt jede Abkürzung (See, Gasse, Gabelung)
##   -- --audiolog         alle 0,25 s Gang/Drehzahl (gehört und für den Vortrieb), Driftwinkel, Reifenquietschen
##   -- --sndtest          Gas, ab 3 s Nitro, ab 7 s Handbremsen-Drift; loggt Pegel von Nitro und Reifen ("snd ...").
##                         Mit --write-movie aufnehmen, --nomusic für die Effekte allein, --sndtrace für jedes Bild
##   -- --lightlog         Größe und Aufbauzeit der Lichtkarte (Laternenlicht auf der Straße)
##   -- --lightpng=/pfad.png  speichert die Lichtkarte als Bild

const Track := preload("res://scripts/track_builder.gd")
const Catalog := preload("res://scripts/catalog.gd")

var prefix := ""
var drive := false
var quit_after := 0.0
var times := [1.5, 6.0, 9.0, 16.0, 24.0, 32.0]
var _t := 0.0
var _i := 0
var _lane := Track.LANES[2]
var demo := false
var at := ""
var lock_lane := false
var _placed := false
## Zeitpunkt (Sekunden seit Start) -> Menü-Eingabe
const DEMO_STEPS := [[5.4, "ui_down"], [6.0, "ui_accept"], [6.9, "ui_right"], [7.6, "ui_right"],
	[8.3, "ui_down"], [8.8, "ui_right"], [9.5, "ui_right"], [10.2, "ui_down"], [10.7, "ui_right"],
	[11.4, "ui_right"], [12.4, "ui_cancel"], [13.2, "ui_accept"], [14.0, "ui_accept"]]
var _step := 0
var sweep: PackedStringArray = []  # --sweep=schritt[:hoch]  Kamera fährt die Hauptstraße in Schritten ab, je Schritt ein Bild nach links und rechts
var _sw_i := 0
var _sw_f := 0
var view: PackedStringArray = []  # --view=pfad:d:quer:höhe:ziel_d:ziel_quer:ziel_höhe  feste Kamera (Weg 0 = Hauptstraße)
var _menu_done := false
var look: PackedStringArray = []  # --look=wahrzeichen:höhe:blickhöhe:abstand[:d]  Kamera von der Straße auf ein Wahrzeichen (Orts-Strecken)
var _vcam: Camera3D
var _drift_t := -1.0  # laufendes Drift-Manöver (--drifty)
var _drift_dir := 0.0
var bench := false
var _bench := []  # je Bild: [Bildzeit ms, GPU ms, CPU-Render ms, Draw Calls, Objekte, Dreiecke]
var _bench_vp := RID()
var _crash: PackedStringArray = []
var _crash_done := false
var _crash_yaw := 0.0
var _crash_t0 := 0.0
var _block: PackedStringArray = []
var _block_done := false
var _added := {}  # in diesem Bild neu hinzugefügte Knoten nach Art (Ruckler-Suche)
var fulltest := false
var branches := false
var _ft := {"last_d": 0.0, "last_t": 0.0, "stuck": 0, "fall": 0, "off": 0, "spikes": 0, "hits": 0, "resets": 0,
	"end_t": -1.0, "us": 0, "ai_last": [], "ai_stuck": 0, "off_t": -10.0, "fall_t": -10.0, "spike_t": -10.0}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			prefix = a.substr(7)
		elif a == "--drive":
			drive = true
		elif a == "--bench":
			bench = true
		elif a == "--fulltest":
			fulltest = true
			drive = true
		elif a == "--branches":
			branches = true
		elif a.begins_with("--crash="):
			_crash = a.substr(8).split(":")
		elif a.begins_with("--block="):
			_block = a.substr(8).split(":")
		elif a == "--demo":
			demo = true
			drive = true
		elif a.begins_with("--quit="):
			quit_after = float(a.substr(7))
		elif a.begins_with("--at="):
			at = a.substr(5)
			drive = true
		elif a.begins_with("--sweep="):
			sweep = a.substr(8).split(":")
		elif a.begins_with("--view="):
			view = a.substr(7).split(":")
		elif a.begins_with("--look="):
			look = a.substr(7).split(":")
		elif a.begins_with("--times="):
			times = []
			for t in a.substr(8).split(","):
				times.append(float(t))


func _lane_free(race, lat: float, from: float, to: float) -> bool:
	for t in race.traffic:
		var rel: float = t.progress - race.player.progress
		var reach := to * (2.2 if t.dir < 0.0 else 1.0)
		if absf(t.lateral() - lat) < 2.8 and rel > from - t.length and rel < reach:
			return false
	for b in race.track["blocks"]:
		if absf(b["lane"] - lat) < 2.8 and b["to"] > race.player.progress + from and b["from"] < race.player.progress + to:
			return false
	return true


func _process(dt: float) -> void:
	_t += dt
	if demo and _step < DEMO_STEPS.size() and _t >= DEMO_STEPS[_step][0]:
		for pressed in [true, false]:
			var ev := InputEventAction.new()
			ev.action = DEMO_STEPS[_step][1]
			ev.pressed = pressed
			Input.parse_input_event(ev)
		_step += 1
	var race = get_tree().current_scene
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--keys="):
			# Test: Aktionen zu festen Zeiten drücken, z. B. --keys=1.5:ui_cancel,2.5:ui_down
			for item in a.substr(7).split(","):
				var tk := float(item.get_slice(":", 0))
				if _t >= tk and _t - get_process_delta_time() < tk:
					for pressed in [true, false]:
						var ev := InputEventAction.new()
						ev.action = item.get_slice(":", 1)
						ev.pressed = pressed
						Input.parse_input_event(ev)
		if a.begins_with("--tune=") and race and race.has_method("_show_parts") and _t > 0.5 and not _menu_done:
			_menu_done = true  # Test: Tuning-Teileliste einer Kategorie öffnen (z. B. --tune=engine), Kamera fährt hin
			var cat := a.substr(7)
			var grp := "optik" if cat in Catalog.PART_GROUPS["optik"] else "leistung"
			race._show_main()
			race._show_tuning()
			race._show_parts(cat, grp)
		if a.begins_with("--menu=") and race and race.has_method("_show_events") and _t > 0.8 and not _menu_done:
			_menu_done = true  # Test: Garage direkt auf einer Event-Liste öffnen (z. B. --menu=city, --menu=tuning, --menu=cars, --menu=main)
			var which := a.substr(7)
			race._show_main()  # erst Hauptmenü (lädt das Auto), auch wenn noch die Sprachwahl offen ist
			if race.has_method("_show_" + which):
				race.call("_show_" + which)  # tuning, cars, settings, races
			elif which != "main":
				race._show_races()
				race._show_events(which)
	if not sweep.is_empty() and race and "curve" in race and race.world and race.track:
		_sweep(race)
		return
	if view.size() >= 7 and race and "curve" in race and race.world:
		if _vcam == null:
			_vcam = Camera3D.new()
			_vcam.fov = 60.0
			_vcam.far = 2000.0
			race.world.add_child(_vcam)
			for ch in race.get_children():
				if ch is CanvasLayer and ch.layer >= 0:
					ch.visible = false  # HUD aus, nur die Welt
		var vc: Curve3D = race.track["paths"][int(view[0])]["curve"]
		var fa := Track.frame_at(vc, float(view[1]))
		var fb := Track.frame_at(vc, float(view[4]))
		_vcam.global_position = fa["pos"] + fa["right"] * float(view[2]) + Vector3(0, float(view[3]), 0)
		_vcam.look_at(fb["pos"] + fb["right"] * float(view[5]) + Vector3(0, float(view[6]), 0), Vector3.UP)
		_vcam.make_current()
	if look.size() >= 4 and race and "curve" in race and race.world:
		var lm: Node3D = race.track["node"].get_node_or_null(look[0])
		if lm:
			if _vcam == null:
				_vcam = Camera3D.new()
				_vcam.fov = 60.0
				_vcam.far = 3000.0
				race.world.add_child(_vcam)
				for ch in race.get_children():
					if ch is CanvasLayer and ch.layer >= 0:
						ch.visible = false
			var q: Vector3 = (race.track["curve"] as Curve3D).get_closest_point(lm.global_position)
			if look.size() >= 5:
				q = Track.frame_at(race.track["curve"], float(look[4]))["pos"]  # Kamera an Streckenmeter statt am nächsten Punkt
			var to := lm.global_position - q
			to.y = 0.0
			to = to.normalized()
			_vcam.global_position = q - to * float(look[3]) + Vector3(0, float(look[1]), 0)
			_vcam.look_at(lm.global_position + Vector3(0, float(look[2]), 0), Vector3.UP)
			_vcam.make_current()
	if at != "" and race and "curve" in race and race.player:
		if not _placed and race.state == 1:
			_placed = true
			_place_at(race)
	if OS.get_cmdline_user_args().has("--revtest") and race and "curve" in race and race.player and race.state == 1:
		_revtest(race, dt)
	if OS.get_cmdline_user_args().has("--handling") and race and "curve" in race and race.player and race.state == 1:
		_handling(race, dt)
		return
	# --sndtest: Gas, dann Nitro, dann ein Drift auf der Geraden; loggt die Pegel von Nitro und Reifen
	# (--nomusic: Musik aus, um die Effekte allein aufzunehmen)
	if OS.get_cmdline_user_args().has("--sndtest") and race and "curve" in race and race.player and race.state == 1:
		var pl = race.player
		if OS.get_cmdline_user_args().has("--nomusic"):
			for mp in Music._players:
				mp.volume_db = -80.0
		if _drift_t < 0.0:
			_drift_t = 0.0
		_drift_t += dt
		for a in ["steer_left", "steer_right", "handbrake", "accelerate", "nitro"]:
			Input.action_release(a)
		var st := _drift_t
		Input.action_press("accelerate")
		if not pl.loc.is_empty() and (st < 7.0 or st > 9.6):
			# außerhalb des Manövers in der Spur halten (sonst schrammt das Auto an der Wand)
			var pth: Dictionary = race.track["paths"][pl.path_id]
			var dl: float = pl.loc["d"] + 14.0 + absf(pl.speed_fwd) * 0.3
			var fr := Track.frame_at(pth["curve"], dl)
			var tg: Vector3 = fr["pos"] + fr["right"] * Track.lane_lat(race.track, dl, _lane)
			var side: float = (tg - pl.global_position).dot(pl.global_basis.x)
			if absf(side) > 0.2:
				Input.action_press("steer_right" if side > 0.0 else "steer_left", clampf(absf(side) / 2.5, 0.0, 1.0))
		if st > 3.0 and st < 6.0:
			Input.action_press("nitro")
		elif st > 7.0 and st < 7.35:
			Input.action_press("handbrake")
			Input.action_press("steer_left")
		elif st > 7.35 and st < 8.6:
			Input.action_press("steer_left", 0.5)
		elif st > 8.6 and st < 9.6:
			Input.action_press("steer_right", 0.6)
		if st > 6.9 and st < 9.8 and OS.get_cmdline_user_args().has("--sndtrace"):
			print("tr t=%.2f v=%.1f lat=%.1f steer=%.2f hold=%.2f winkel=%.0f wall_t=%.1f stun=%.2f hb=%s" % [st, pl.velocity.length(),
				pl.speed_lat, pl.steer, pl._slip_hold, pl.drift_angle, pl._wall_t, pl.stun, Input.is_action_pressed("handbrake")])
		if fmod(st, 0.2) < dt:
			var au = pl.audio
			print("snd t=%.1f v=%.1f nos=%s nos_db=%.1f slip=%.2f skid_db=%.1f scrub_db=%.1f winkel=%.0f" % [st,
				pl.velocity.length(), pl.nitro_on, au._nos.volume_db, au.slip, au._skid.volume_db, au._scrub.volume_db,
				pl.drift_angle])
	# --slidetest: festes Drift-Manöver auf der Geraden (Fahrmodell prüfen): 0,25 s Handbremse + links, dann nur Gas
	elif OS.get_cmdline_user_args().has("--slidetest") and race and "curve" in race and race.player and race.state == 1:
		var pl = race.player
		if _drift_t < 0.0:
			_drift_t = 0.0
			pl.drift_mode = true
			pl.velocity = -pl.global_basis.z * 25.0
		_drift_t += dt
		for a in ["steer_left", "steer_right", "handbrake", "accelerate"]:
			Input.action_release(a)
		Input.action_press("accelerate")
		if _drift_t < 0.25:
			Input.action_press("handbrake")
			Input.action_press("steer_left")
		elif _drift_t > 2.0 and _drift_t < 3.2:
			Input.action_press("steer_right", 0.5)  # gegenlenken
		elif _drift_t > 3.2:
			Input.action_release("accelerate")  # Gas weg: aufrichten
		if fmod(_drift_t, 0.2) < dt:
			print("t=%.1f winkel=%.0f rutscht=%s tempo=%.1f wand=%d" % [_drift_t, pl.drift_angle, pl._sliding, pl.velocity.length(), pl.wall_hits])
	elif drive and race and "curve" in race and race.player and race.player.drag_mode:
		_drag_pilot(race)
	elif drive and race and "curve" in race and race.player and not race.player.loc.is_empty():
		var pl = race.player
		var p: Dictionary = race.track["paths"][pl.path_id]
		var on_main: bool = p["id"] == 0
		var look: float = 25.0 + absf(pl.speed_fwd) * 1.6
		if on_main and not lock_lane and not _lane_free(race, _lane, -3.0, look):
			var best: float = _lane
			var cost := 1e9
			var split := Track.median_at(race.track, pl.progress) > 0.3 or Track.median_at(race.track, pl.progress + look) > 0.3
			for l in Track.LANES:
				if split and signf(l) != signf(_lane):
					continue
				if _lane_free(race, l, -4.0, look) and absf(l - pl.lateral) < cost:
					cost = absf(l - pl.lateral)
					best = l
			_lane = best
		var dl: float = pl.loc["d"] + 14.0 + absf(pl.speed_fwd) * 0.3
		var f := Track.frame_at(p["curve"], dl)
		var tgt: Vector3 = f["pos"] + f["right"] * (Track.lane_lat(race.track, dl, _lane) if on_main else (2.4 if p["kind"] == "fork" else 0.0))
		if branches and on_main:
			# kurz vor der Einmündung auf den Seitenweg zielen
			for q in race.track["paths"]:
				if q["kind"] in ["lake", "alley", "fork"] and pl.progress > q["from"] - 35.0 and pl.progress < q["from"] + 10.0:
					var fq := Track.frame_at(q["curve"], maxf(14.0 + absf(pl.speed_fwd) * 0.3 - (q["from"] - pl.progress), 3.0))
					tgt = fq["pos"] + fq["right"] * (2.4 if q["kind"] == "fork" else 0.0)
		var side: float = (tgt - pl.global_position).dot(pl.global_basis.x)
		Input.action_release("steer_left")
		Input.action_release("steer_right")
		if absf(side) > 0.2:
			Input.action_press("steer_right" if side > 0.0 else "steer_left", clampf(absf(side) / 2.5, 0.0, 1.0))
		# Vor engen Kurven vom Gas
		var f0 := Track.frame_at(p["curve"], pl.loc["d"])
		var f1 := Track.frame_at(p["curve"], pl.loc["d"] + 30.0 + absf(pl.speed_fwd))
		var bend: float = (f0["fwd"] as Vector3).angle_to(f1["fwd"])
		var limit := 38.0 if on_main else 30.0
		if p["kind"] == "lake":
			limit = 40.0
			bend = 0.0
		# --drifty: vor Kurven ein Drift-Manöver wie ein Mensch (Handbremse, voll einlenken, mit Gas quer halten)
		if OS.get_cmdline_user_args().has("--drifty"):
			if _drift_t < 0.0 and bend > 0.3 and pl.speed_fwd > 18.0:
				_drift_t = 0.0
				_drift_dir = signf((f1["fwd"] as Vector3).cross(f0["fwd"]).y)
			if _drift_t >= 0.0:
				_drift_t += dt
				Input.action_release("steer_left")
				Input.action_release("steer_right")
				var hard := 1.0 if _drift_t < 0.35 else 0.55
				Input.action_press("steer_left" if _drift_dir > 0.0 else "steer_right", hard)
				if _drift_t < 0.35:
					Input.action_press("handbrake")
				else:
					Input.action_release("handbrake")
				Input.action_press("accelerate")
				if _drift_t > 1.3:
					_drift_t = -1.0
				return
		Input.action_release("brake")
		if fulltest and bend > 0.5:
			# wie ein Mensch: je enger die Kurve, desto langsamer, und dafür auch bremsen
			limit = clampf(limit - (bend - 0.5) * 16.0, 17.0, limit)
			if pl.speed_fwd > limit + 3.0:
				Input.action_press("brake")
		if bend > 0.5 and pl.speed_fwd > limit:
			Input.action_release("accelerate")
		else:
			Input.action_press("accelerate")
		if bend < 0.15 and pl.nitro > 0.3 and pl.speed_fwd > 20.0 and (not on_main or _lane_free(race, _lane, 0.0, 80.0)):
			Input.action_press("nitro")
		else:
			Input.action_release("nitro")
	if OS.get_cmdline_user_args().has("--log") and race and "curve" in race and race.player and race.track["crossing_d"] > 0.0:
		var pl = race.player
		var rel: float = pl.progress - race.track["crossing_d"]
		if rel > -30.0 and rel < 30.0:
			print("rel=%.1f lat=%.1f y=%.2f vy=%.1f v=%.1f air=%s path=%d train=%s" % [rel, pl.lateral, pl.position.y, pl.vy, pl.speed_fwd, pl.airborne, pl.path_id, race.track["crossing"].train.global_position])
	if fulltest and race and "curve" in race and race.player:
		_fulltest(race)
	if race and "curve" in race and race.player and (OS.get_cmdline_user_args().has("--trace") or OS.get_cmdline_user_args().has("--handling") or not _crash.is_empty()):
		race.player.debug_hits = true
	if race and "curve" in race and race.player and race.player.last_hit != "":
		print("  >> Treffer t=%.1f: %s" % [_t, race.player.last_hit])
		race.player.last_hit = ""
	if OS.get_cmdline_user_args().has("--trace") and race and "curve" in race and race.player and fmod(_t, 0.1) < dt:
		var pl = race.player
		var near := ""
		for t in race.traffic:
			if absf(t.progress - pl.progress) < 12.0:
				near += " T(%.1f,%.1f)" % [t.progress - pl.progress, t.lateral()]
		print("t=%.1f d=%.1f lat=%.2f v=%.1f path=%d y=%.2f luft=%s fps=%d%s" % [_t, pl.progress, pl.lateral, pl.speed_fwd, pl.path_id, pl.position.y, pl.airborne, Engine.get_frames_per_second(), near])
		print("   runde=%d gesamt=%.0f ziel=%.0f status=%d platz=%d drift=%d kette=%d" % [pl.lap, pl.total, race.track["finish"], race.state, race._place(), int(race.drift_score), int(race.drift_chain)])
		print("   rutscht=%s winkel=%.0f tempo=%.1f lenk=%.2f wand=%d manoever=%.2f" % [pl._sliding, pl.drift_angle, pl.velocity.length(), pl.steer, pl.wall_hits, _drift_t])
		for n in get_tree().get_nodes_in_group("ambient"):
			if "_cars" in n:
				print("   zug aktiv=%s d=%.0f (%.0f-%.0f) sichtbar=%s y=%.1f" % [n._active, n._d, n.d_from, n.d_to, n._cars[0].visible, n._cars[0].global_position.y])
	if OS.get_cmdline_user_args().has("--camlog") and race and "curve" in race and race.player and fmod(_t, 0.5) < dt:
		var pl = race.player
		print("cam t=%.1f v=%d abstand=%.2f fov=%.1f" % [_t, int(pl.speed_fwd * 3.6), pl.cam.global_position.distance_to(pl.global_position), pl.cam.fov])
	if OS.get_cmdline_user_args().has("--audiolog") and race and "curve" in race and race.player and fmod(_t, 0.25) < dt:
		# Motor und Reifen: Gang/Drehzahl (gehört) gegen Gang/Drehzahl für den Vortrieb, Driftwinkel, Quietschen
		var pl = race.player
		print("al t=%.2f v=%.1f vf=%.1f gang=%d/%d rpm=%d/%d winkel=%.0f slip=%.2f quietsch=%.1fdB ton=%.2f" % [_t,
			pl.velocity.length(), pl.speed_fwd, pl.gear, pl._pull_gear, int(pl.rpm), int(pl._pull_rpm), pl.drift_angle,
			pl.audio.slip, pl.audio._skid.volume_db, pl.audio._skid.pitch_scale])
	if OS.get_cmdline_user_args().has("--racelog") and race and "curve" in race and race.player and fmod(_t, 3.0) < dt:
		# kompakter Rennverlauf: eigenes Auto, Gegner (Gesamtfortschritt), Bildrate
		var pl = race.player
		print("rl t=%.0f gesamt=%.0f/%.0f platz=%d status=%d wand=%d fps=%d ki=%s" % [_t, pl.total, race.track["finish"], race._place(), race.state,
			pl.wall_hits, Engine.get_frames_per_second(), race.ais.map(func(a): return int(a.total))])
	if prefix != "" and _i < times.size() and _t >= times[_i]:
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [prefix, _i])
		_ft["us"] = Time.get_ticks_usec()  # Speichern zählt nicht als Ruckler
		_i += 1
		if _i == times.size() and quit_after <= 0.0:
			get_tree().quit()
	if bench and race and "curve" in race and race.player:
		_bench_sample(race, dt)
	if OS.get_cmdline_user_args().has("--airlog") and race and "curve" in race and race.player and race.state == 1 and fmod(_t, 0.1) < dt:
		var p2 = race.player
		print("air t=%.1f v=%.1f y=%.2f vy=%.1f luft=%s nick=%.2f roll=%.2f d=%.0f pfad=%d wasser=%.1f" % [_t, p2.velocity.length(), p2.position.y, p2.vy,
			p2.airborne, p2._air_pitch, p2._air_roll, p2.progress, p2.path_id, p2.sinking])
	if not _block.is_empty() and race and "curve" in race and race.player and race.state == 1:
		var bp = race.player
		if not _block_done:
			_block_done = true
			bp.place(Track.xform_at(race.track["curve"], float(_block[0]), Track.LANES[int(_block[1])]))
			bp.controls_enabled = false
		elif fmod(_t, 0.25) < dt:
			var parts := []
			var min_ai := 1e9
			for a in race.ais:
				parts.append("ki d=%.0f spur=%.1f v=%.0f abst=%.1f" % [a.progress, a.lane, a.speed, a.global_position.distance_to(bp.global_position)])
				for b in race.ais:
					if a != b:
						min_ai = minf(min_ai, a.global_position.distance_to(b.global_position))
			print("block t=%.1f spieler d=%.0f v=%.1f | %s | ki-min=%.1f" % [_t, bp.progress, bp.velocity.length(), " | ".join(parts), min_ai])
	if not _crash.is_empty() and race and "curve" in race and race.player and race.state == 1:
		var pl = race.player
		if not _crash_done:
			_crash_done = true
			_crash_t0 = _t
			if _crash.size() > 2:
				pl.place(Track.xform_at(race.track["curve"], float(_crash[2]), float(_crash[3]) if _crash.size() > 3 else 0.0))
			if _crash[1] == "k":
				# auf das nächste Umfahrbare (Laterne, Schild) 25–70 m voraus zielen
				var best: Node3D = null
				var stack: Array = [race.track["node"]]
				while not stack.is_empty():
					var nd: Node = stack.pop_back()
					stack.append_array(nd.get_children())
					if nd is RigidBody3D and nd.has_method("knock"):
						var rel: Vector3 = nd.global_position - pl.global_position
						rel.y = 0.0
						if rel.length() > 25.0 and rel.length() < 70.0 and rel.normalized().dot(-pl.global_basis.z) > 0.85:
							if best == null or rel.length() < (best.global_position - pl.global_position).length():
								best = nd
				if best:
					pl.look_at(Vector3(best.global_position.x, pl.global_position.y, best.global_position.z), Vector3.UP)
					print("crash ziel: %s bei %s" % [best.name, best.global_position])
			elif _crash[1] == "q":
				# quer rutschend (wie nach einem Dreher) nach rechts auf die Wand zu
				pl.velocity = pl.global_basis.x * float(_crash[0])
				return
			else:
				pl.rotate_y(-deg_to_rad(float(_crash[1])))
			pl.velocity = -pl.global_basis.z * float(_crash[0])
			pl.speed_fwd = float(_crash[0])
			_crash_yaw = rad_to_deg(pl.global_rotation.y)
		else:
			# Drehung pro Bild: ruckartige Sprünge der Ausrichtung (Wandkontakt) sichtbar machen
			var yaw: float = rad_to_deg(pl.global_rotation.y)
			var dy := wrapf(yaw - _crash_yaw, -180.0, 180.0)
			_crash_yaw = yaw
			if absf(dy) > 1.5 and _t - _crash_t0 < 4.0:
				print("  dreh t=%.2f %+.1f° (rel. Straße %.0f°) v=%.1f wand=%d" % [_t, dy, rad_to_deg(wrapf(pl.global_rotation.y
					- Basis.looking_at(Track.frame_at(race.track["curve"], pl.progress)["fwd"], Vector3.UP).get_euler().y, -PI, PI)), pl.velocity.length(), pl.wall_hits])
		if _crash_done and fmod(_t, 0.2) < dt:
			print("crash t=%.1f v=%.1f y=%.2f luft=%s ueberschlag=%s roll=%.2f nick=%.2f d=%.0f lat=%.1f" % [_t, pl.velocity.length(),
				pl.position.y, pl.airborne, pl.tumbling, pl._air_roll, pl._air_pitch, pl.progress, pl.lateral])
	if OS.get_cmdline_user_args().has("--drawlog") and race and "curve" in race and race.player and race.state == 1 and fmod(_t, 2.0) < dt:
		var vp: RID = race.world.get_viewport_rid()
		print("DRAWS t=%.0f d=%.0f draws=%d" % [_t, race.player.progress, RenderingServer.viewport_get_render_info(vp,
			RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)])
	if quit_after > 0.0 and _t >= quit_after:
		_bench_report(race)
		get_tree().quit()


func _bench_sample(race, dt: float) -> void:
	if not _bench_vp.is_valid():
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		_bench_vp = race.world.get_viewport_rid()
		get_tree().node_added.connect(func(nd: Node):
			var k: String = nd.get_script().resource_path.get_file() if nd.get_script() else nd.get_class()
			_added[k] = _added.get(k, 0) + 1)
		RenderingServer.viewport_set_measure_render_time(_bench_vp, true)
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
		return
	if race.state != 1:
		return
	if _bench.size() == 600:
		_bench_breakdown(race)
	var rs := RenderingServer
	_bench.append([dt * 1000.0,
		rs.viewport_get_measured_render_time_gpu(_bench_vp) + rs.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()),
		rs.viewport_get_measured_render_time_gpu(_bench_vp),
		rs.viewport_get_render_info(_bench_vp, rs.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, rs.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME),
		rs.viewport_get_render_info(_bench_vp, rs.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, rs.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME),
		rs.viewport_get_render_info(_bench_vp, rs.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, rs.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, _t, _added.duplicate()])
	_added.clear()


## Was steht gerade im Bild? Sichtbare Geometrie nach Herkunft (Auto, Umfahrbares, Strecke ...) gezählt
func _bench_breakdown(race) -> void:
	var cam: Camera3D = race.world.get_camera_3d()
	var planes := cam.get_frustum()
	var out := {}
	var stack: Array = [race.world]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		stack.append_array(nd.get_children())
		if not nd is GeometryInstance3D or not (nd as Node3D).is_visible_in_tree():
			continue
		var gi := nd as GeometryInstance3D
		var aabb := gi.global_transform * gi.get_aabb()
		var c := aabb.get_center()
		var dist := c.distance_to(cam.global_position)
		if dist > cam.far + aabb.size.length() * 0.5 or (gi.visibility_range_end > 0.0 and dist > gi.visibility_range_end) or dist < gi.visibility_range_begin:
			continue
		var inside := true
		for pl in planes:
			if pl.distance_to(c) > aabb.size.length() * 0.5:
				inside = false
				break
		if not inside:
			continue
		var owner_k := "track"
		var p := nd.get_parent()
		while p and p != race.world:
			if p.get_script():
				owner_k = p.get_script().resource_path.get_file()
				break
			p = p.get_parent()
		var k := "%s/%s" % [owner_k, nd.get_class()]
		out[k] = out.get(k, 0) + 1
	var keys := out.keys()
	keys.sort_custom(func(a, b): return out[a] > out[b])
	print("BENCH sichtbar: ", ", ".join(keys.map(func(k): return "%s=%d" % [k, out[k]])))


func _bench_report(race) -> void:
	if not bench or _bench.size() < 10 or not race or not "track" in race:
		return
	var sums := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
	var worst := []
	for s in _bench:
		for k in 8:
			sums[k] += s[k]
		worst.append(s[0])
	worst.sort()
	var n := float(_bench.size())
	var med: float = worst[int(n / 2)]
	var spikes := []  # Ruckler: Bilder über dem Dreifachen des Medians (mind. 20 ms)
	for s in _bench:
		if s[0] > maxf(med * 3.0, 20.0):
			spikes.append("%.1fs:%dms%s" % [s[8], int(s[0]), "" if s[9].is_empty() else str(s[9])])
	var counts := {"mesh": 0, "multimesh": 0, "omni": 0, "spot": 0, "label": 0, "particles": 0, "bodies": 0}
	var stack: Array = [race.world]
	while not stack.is_empty():
		var nd: Node = stack.pop_back()
		if nd is MeshInstance3D:
			counts["mesh"] += 1
		elif nd is MultiMeshInstance3D:
			counts["multimesh"] += 1
		elif nd is OmniLight3D:
			counts["omni"] += 1
		elif nd is SpotLight3D:
			counts["spot"] += 1
		elif nd is Label3D:
			counts["label"] += 1
		elif nd is GPUParticles3D or nd is CPUParticles3D:
			counts["particles"] += 1
		elif nd is PhysicsBody3D:
			counts["bodies"] += 1
		stack.append_array(nd.get_children())
	print("BENCH race=%s q=%d frames=%d frame=%.2fms med=%.2fms p99=%.2fms gpu=%.2fms gpu3d=%.2fms process=%.2fms physics=%.2fms draws=%d objs=%d tris=%dk %s" % [
		race.race["name"], GameState.preset, _bench.size(), sums[0] / n, med, worst[int(n * 0.99) - 1], sums[1] / n, sums[2] / n,
		sums[6] / n, sums[7] / n, int(sums[3] / n), int(sums[4] / n), int(sums[5] / n / 1000.0), counts])
	print("BENCH spikes=%d %s" % [spikes.size(), " ".join(spikes.slice(0, 40))])
	print("BENCH vram=%dMB tex=%dMB buf=%dMB" % [Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0])


## --fulltest: Rennen mit dem Autopiloten durchfahren und alles Auffällige melden. Hängt das Auto, wird es wie mit
## der Rücksetz-Taste zurück auf die Straße gesetzt, damit das Rennen weiterläuft.
func _fulltest(race) -> void:
	var pl = race.player
	var tr: Dictionary = race.track
	pl.debug_hits = true
	if pl.last_hit != "":
		_ft["hits"] += 1
	var now := Time.get_ticks_usec()
	var real_ms: float = (now - _ft["us"]) / 1000.0 if _ft["us"] > 0 else 0.0
	_ft["us"] = now
	if race.state == 2:
		if _ft["end_t"] < 0.0:
			_ft["end_t"] = _t
			print("FT ZIEL rennzeit=%.1f platz=%d ki_ziel=%s" % [race.race_time, race._place(),
				race.ais.map(func(a): return snappedf(a.finish_time, 0.1))])
		elif _t - _ft["end_t"] > 3.0:
			print("FT ENDE hänger=%d stürze=%d neben=%d ruckler=%d treffer=%d wand=%d crashes=%d ki_hänger=%d" % [_ft["stuck"], _ft["fall"],
				_ft["off"], _ft["spikes"], _ft["hits"], pl.wall_hits, pl.crashes, _ft["ai_stuck"]])
			get_tree().quit()
		return
	if race.state != 1 or pl.loc.is_empty():
		return
	for a in race.ais:
		if a.path["id"] != 0 and not _ft.has("ki_ab_%d" % a.path["id"]):
			_ft["ki_ab_%d" % a.path["id"]] = true
			print("FT KI-ABKÜRZUNG %s #%d t=%.1f" % [a.path["kind"], a.path["id"], race.race_time])
	if not _ft.has("ki_info"):
		_ft["ki_info"] = true
		print("FT KI-STÄRKE schwierigkeit=%d spieler_top=%.1f | %s" % [GameState.difficulty, pl.top_speed,
			" | ".join(race.ais.map(func(a): return "top=%.1f können=%.3f eff=%.1f" % [a.top, a.skill, a.top * a.skill]))])
	var where := "t=%.1f d=%.0f pfad=%d(%s) quer=%.1f pos=(%.0f,%.1f,%.0f) v=%.1f" % [race.race_time, pl.progress, pl.path_id,
		tr["paths"][pl.path_id]["kind"], pl.loc["lat"], pl.global_position.x, pl.global_position.y, pl.global_position.z, pl.velocity.length()]
	# Ruckler: echte Bildzeit über 60 ms
	if real_ms > 60.0 and race.race_time > 2.0:
		_ft["spikes"] += 1
		if _t - _ft["spike_t"] > 1.0:
			print("FT RUCKLER %dms %s" % [int(real_ms), where])
		_ft["spike_t"] = _t
	# unter dem Boden (nicht im See)
	var g: Dictionary = Track.ground_path(tr, pl.path_id, pl.loc["d"], pl.loc["lat"], pl.loc["score"])
	if pl.global_position.y < g["base"] - 1.5 and pl.sinking <= 0.0 and _t - _ft["fall_t"] > 2.0:
		_ft["fall"] += 1
		_ft["fall_t"] = _t
		print("FT UNTER BODEN boden=%.1f %s" % [g["base"], where])
	# neben der Strecke: weiter draußen als Fahrbahn + Gehweg
	var out: float = pl.loc["score"] - (Track.WALK if pl.path_id == 0 else 0.0)
	if out > 1.0 and _t - _ft["off_t"] > 2.0:
		_ft["off"] += 1
		_ft["off_t"] = _t
		print("FT NEBEN STRASSE %.1f m %s" % [out, where])
	# Hänger: in 4 s kaum vorangekommen
	if race.race_time - _ft["last_t"] >= 4.0:
		var moved: float = pl.total - _ft["last_d"]
		if moved < 10.0 and race.race_time > 5.0 and pl.sinking <= 0.0 and race.event_type != "drag":
			_ft["stuck"] += 1
			print("FT HÄNGT %.1f m in 4 s %s" % [moved, where])
			var half: float = tr["paths"][pl.path_id]["half_w"] - 2.0
			pl.place(Track.xform_at(tr["paths"][pl.path_id]["curve"], pl.loc["d"], clampf(pl.loc["lat"], -half, half)))
		var last: Array = _ft["ai_last"]
		for i in race.ais.size():
			var a = race.ais[i]
			if i < last.size() and a.finish_time < 0.0 and a.total - last[i] < 10.0 and race.race_time > 6.0:
				_ft["ai_stuck"] += 1
				var near := ""
				for t in race.traffic:
					if t.path_id == a.path["id"] and absf(t.progress - a.d) < 25.0:
						near += " verkehr(%+.0f,%.1f,v=%.0f%s)" % [t.progress - a.d, t.lateral(), t.speed, ",wrack" if t.wrecked else ""]
				for b in race.ais:
					if b != a and b.global_position.distance_to(a.global_position) < 12.0:
						near += " ki(%.0fm)" % b.global_position.distance_to(a.global_position)
				if pl.global_position.distance_to(a.global_position) < 12.0:
					near += " spieler(%.0fm)" % pl.global_position.distance_to(a.global_position)
				if a.crossing and a.crossing.is_blocked() and absf(a.crossing.d_cross - a.d) < 60.0:
					near += " schranke(%+.0f)" % (a.crossing.d_cross - a.d)
				print("FT KI HÄNGT ki=%d d=%.0f weg=%s spur=%.1f→%.1f v=%.1f stun=%.1f block=%.1f pos=(%.0f,%.1f,%.0f) t=%.1f%s" % [i, a.progress,
					a.path["kind"], a.lane, a.lane_target, a.speed, a.stun, a._blocked_t, a.global_position.x, a.global_position.y,
					a.global_position.z, race.race_time, near])
		_ft["ai_last"] = race.ais.map(func(a): return a.total)
		_ft["last_t"] = race.race_time
		_ft["last_d"] = pl.total


## Drag-Autopilot: Vollgas, schaltet im grünen Bereich (--lateshift: erst im Begrenzer), weicht Verkehr per
## Spurwechsel aus, Nitro ab dem 3. Gang
var _tap := ""
var _shift_t := 0.0
var _crash_set := false


func _drag_pilot(race) -> void:
	var pl = race.player
	for a in ["shift_up", "steer_left", "steer_right"]:
		Input.action_release(a)
	if _tap != "":
		_tap = ""
		return  # nach jedem Tippen ein Bild loslassen, sonst zählt der nächste Druck nicht
	Input.action_press("accelerate")
	if not pl.controls_enabled:
		return
	var late := OS.get_cmdline_user_args().has("--lateshift")
	if OS.get_cmdline_user_args().has("--dragcrash") and _t > 9.0 and not race.traffic.is_empty() and not _crash_set:
		_crash_set = true  # Test: Verkehrsauto direkt vor das eigene Auto setzen (Totalschaden)
		var t = race.traffic[0]
		t.progress = pl.progress + 45.0
		t.lane = Track.LANES[pl.drag_lane]
		t._lane_cur = t.lane
	if OS.get_cmdline_user_args().has("--noshift"):
		return  # Test: im 1. Gang im Begrenzer bleiben (Motorschaden)
	if pl.gear < 6 and pl.rpm >= (7950.0 if late else 7250.0) and _t - _shift_t > 0.4:
		_tap = "shift_up"
		_shift_t = _t
	elif not OS.get_cmdline_user_args().has("--nolanes") and not _lane_free(race, Track.LANES[pl.drag_lane], -3.0, 30.0 + absf(pl.speed_fwd) * 1.4):
		for dl in [-1, 1]:
			var nl: int = pl.drag_lane + dl
			if nl >= 0 and nl <= 3 and _lane_free(race, Track.LANES[nl], -6.0, 30.0 + absf(pl.speed_fwd) * 1.4) and not _crash_set:
				_tap = "steer_left" if dl < 0 else "steer_right"
				break
	if _tap != "":
		Input.action_press(_tap)
	if pl.gear >= 3 and not late:
		Input.action_press("nitro")
	if fmod(_t, 0.5) < get_process_delta_time():
		print("drag t=%.1f v=%d gang=%d rpm=%d heiß=%.2f spur=%d platz=%d d=%.0f nos=%.2f%s" % [_t, int(pl.speed_fwd * 3.6), pl.gear, int(pl.rpm),
			pl.engine_heat, pl.drag_lane, race._place(), pl.progress, pl.nitro, " AN" if pl.nitro_on else ""])


func _place_at(race) -> void:
	var tr: Dictionary = race.track
	var pl = race.player
	match at:
		"fans":
			# Test: kurz vor der zweiten Zuschauergruppe an der Hauptstraße anhalten (Platzierung und Licht prüfen)
			var fans: Array = tr["spectators"]
			var d: float = fans[mini(12, fans.size() - 1)][1] - 22.0 if not fans.is_empty() else 100.0
			pl.place(Track.xform_at(tr["curve"], d, Track.LANES[3]))
		"crossing":
			var d: float = tr["crossing_d"] - 150.0
			_lane = Track.LANES[3]
			lock_lane = true
			pl.place(Track.xform_at(tr["curve"], d, Track.LANES[3]))
			pl.velocity = -pl.global_basis.z * 44.0
			for t in race.traffic:
				if absf(t.progress - tr["crossing_d"]) < 400.0:
					t.progress = tr["length"] - 30.0
			var rc = tr["crossing"]
			rc._triggered = true
			rc._t_arrive = rc._clock + 150.0 / 46.0 + 0.15
			rc._dir = 1.0
		"tunnel", "el", "stadium":
			var d := 0.0
			match at:
				"tunnel":
					d = tr["tunnels"][0]["r0"] - 50.0
				"el":
					d = tr["el"][0]["from"] - 220.0
				"stadium":
					d = tr["stadium_d"] - 160.0
			_drop(race, d)
		"lake", "alley", "fork":
			for p in tr["paths"]:
				if p["kind"] == at:
					var d := 30.0
					for r in tr["ramps"]:
						if r["path"] == p["id"]:
							d = r["d0"] - 12.0
					pl.place(Track.xform_at(p["curve"], d, 0.0))
					pl.velocity = -pl.global_basis.z * (38.0 if at != "alley" else 22.0)
					break
		_:
			if at.begins_with("d:"):
				_drop(race, float(at.substr(2)))
				return
			var arr: Array = tr["districts"]
			var i := arr.find(at)
			if i >= 0:
				_drop(race, i * Track.DISTRICT_LEN + 15.0)


## Auto bei d auf die Hauptstraße setzen und Verkehr direkt davor wegräumen
func _drop(race, d: float) -> void:
	var tr: Dictionary = race.track
	var pl = race.player
	_lane = Track.LANES[2]
	pl.place(Track.xform_at(tr["curve"], d, _lane))
	pl.velocity = -pl.global_basis.z * 30.0
	for t in race.traffic:
		if t.progress > d - 30.0 and t.progress < d + 90.0:
			t.progress = tr["length"] - 30.0


## --handling: Fahrverhalten messen. Slalom bei mittlerem Tempo mit Tastatur-Lenkung (voll oder nichts),
## dann flach (15°) und steil (45°) gegen die Randmauer, dann frontal auf eine Mittelstreifen-Spitze.
var _h_phase := -1
var _h_t := 0.0
var _h_v0 := 0.0
const H_TESTS := [["slalom", 0.0], ["wand", 15.0], ["wand", 30.0], ["wand", 45.0], ["insel", 0.0]]


func _handling(race, dt: float) -> void:
	var pl = race.player
	var tr: Dictionary = race.track
	_h_t += dt
	pl.debug_hits = true
	if pl.last_hit != "":
		print("  >> Treffer: ", pl.last_hit)
		pl.last_hit = ""
	for a in ["steer_left", "steer_right", "handbrake", "accelerate", "brake", "nitro"]:
		Input.action_release(a)
	if _h_phase < 0 or (_h_t > 3.5 and _h_phase < H_TESTS.size()):
		_h_phase += 1
		_h_t = 0.0
		if _h_phase >= H_TESTS.size():
			get_tree().quit()
			return
		for t in race.traffic:
			t.progress = tr["length"] - 30.0
		var kind: String = H_TESTS[_h_phase][0]
		var ang: float = H_TESTS[_h_phase][1]
		var d := 260.0
		var lat: float = Track.LANES[1]
		if kind == "insel":
			if tr["medians"].is_empty():
				print("TEST insel: keine Mittelstreifen auf dieser Strecke")
				return
			d = tr["medians"][0]["from"] - 25.0
			lat = 0.0
			_h_v0 = 0.6
		var xf: Transform3D = Track.xform_at(tr["curve"], d, Track.lane_lat(tr, d, lat) if kind != "insel" else 0.0)
		if kind == "wand":
			xf.basis = xf.basis.rotated(Vector3.UP, -deg_to_rad(ang))  # nach rechts zur Mauer
		pl.place(xf)
		pl.velocity = -pl.global_basis.z * (30.0 if kind == "slalom" else 35.0)
		pl.wall_hits = 0
		pl.crashes = 0
		_h_v0 = 0.0
		print("TEST %s %.0f° bei d=%.0f" % [kind, ang, d])
		if _h_phase == 0:
			print("  tunnel=", tr["tunnels"].map(func(t): return [int(t["from"]), int(t["to"])]), " el=", tr["el"].map(func(t): return [int(t["from"]), int(t["to"])]),
				" kreuzung=", int(tr["crossing_d"]), " seitenwege=", tr["paths"].map(func(p): return [p["kind"], int(p.get("from", 0)), int(p.get("to", 0))]))
		return
	var kind: String = H_TESTS[_h_phase][0]
	Input.action_press("accelerate", 0.75)
	if kind == "slalom":
		Input.action_press("steer_left" if int(_h_t / 0.6) % 2 == 0 else "steer_right")
	if kind == "insel":
		var err: float = pl.lateral - 0.6
		if absf(err) > 0.1:
			Input.action_press("steer_left" if err > 0.0 else "steer_right", clampf(absf(err) / 2.0, 0.0, 1.0))

	if fmod(_h_t, 0.1) < dt:
		var yaw_v := atan2(-pl.velocity.x, -pl.velocity.z)
		print("  t=%.1f v=%.1f winkel=%.1f drift=%s halt=%.2f wand=%d crash=%d stun=%.2f lat=%.1f kam=%.3f/%.3f" % [_h_t, pl.velocity.length(),
			pl.drift_angle, pl.drifting, pl._slip_hold, pl.wall_hits, pl.crashes, pl.stun, pl.lateral, pl.cam.h_offset, pl.cam.v_offset])



## Gebäude-Rundgang: alle schritt Meter ein Bild je Straßenseite, schräg nach vorn auf die Häuserzeile
func _sweep(race) -> void:
	if _vcam == null:
		_vcam = Camera3D.new()
		_vcam.fov = 70.0
		_vcam.far = 2000.0
		race.world.add_child(_vcam)
		for ch in race.get_children():
			if ch is CanvasLayer and ch.layer >= 0:
				ch.visible = false
		var cl := CanvasLayer.new()
		cl.layer = 100
		var lb := Label.new()
		lb.name = "SweepLabel"
		lb.add_theme_font_size_override("font_size", 36)
		lb.add_theme_color_override("font_color", Color(1, 1, 0))
		lb.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		lb.add_theme_constant_override("outline_size", 8)
		lb.position = Vector2(12, 8)
		cl.add_child(lb)
		add_child(cl)
	var step := float(sweep[0])
	var high := sweep.size() > 1 and sweep[1] == "hoch"
	var t: Dictionary = race.track
	var d := 20.0 + (_sw_i / 2) * step
	if d > t["length"] - 10.0:
		get_tree().quit()
		return
	var side := -1.0 if _sw_i % 2 == 0 else 1.0
	var c: Curve3D = t["curve"]
	var fa := Track.frame_at(c, d)
	var fb := Track.frame_at(c, minf(d + (40.0 if high else 22.0), t["length"]))
	var hwd := Track.hw(t, d)
	if high:
		_vcam.global_position = fa["pos"] - fa["right"] * side * (hwd + 6.0) + Vector3(0, 22.0 + fa["y"], 0)
		_vcam.look_at(fb["pos"] + fb["right"] * side * (Track.hw(t, d) + Track.WALK + 14.0) + Vector3(0, 4.0, 0), Vector3.UP)
	else:
		_vcam.global_position = fa["pos"] + fa["right"] * side * (hwd - 2.0) + Vector3(0, 1.5 + fa["y"], 0)
		_vcam.look_at(fb["pos"] + fb["right"] * side * (Track.hw(t, d) + Track.WALK + 6.0) + Vector3(0, 6.5, 0), Vector3.UP)
	_vcam.make_current()
	(find_child("SweepLabel", true, false) as Label).text = "%d m %s %s" % [int(d), "L" if side < 0.0 else "R", Track._district_at(t, d)["name"]]
	_sw_f += 1
	if _sw_f >= 4:
		_sw_f = 0
		get_viewport().get_texture().get_image().save_png("%s_%05d_%s.png" % [prefix, int(d), "L" if side < 0.0 else "R"])
		_sw_i += 1


var _rt := -1.0


## --revtest: Übergang Vorwärts – Bremse – Rückwärts – Gas prüfen
func _revtest(race, dt: float) -> void:
	if _rt < 0.0:
		_rt = 0.0
	_rt += dt
	var phase := "gas" if _rt < 4.0 else ("bremse" if _rt < 9.0 else ("gas" if _rt < 13.0 else "aus"))
	for a in ["accelerate", "brake"]:
		Input.action_release(a)
	if phase == "gas":
		Input.action_press("accelerate")
	elif phase == "bremse":
		Input.action_press("brake")
	if fmod(_rt, 0.25) < dt:
		var pl = race.player
		print("REV t=%.2f %s v=%.1f gang=%d R=%s" % [_rt, phase, pl.speed_fwd, pl.gear, pl.reverse_gear])
	if _rt > 14.0:
		get_tree().quit()
