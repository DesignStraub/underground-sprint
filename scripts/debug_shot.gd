extends Node
## Nur für Tests und Videos:
##   -- --drive            Autopilot fährt (weicht Verkehr aus, nutzt Nitro)
##   -- --shot=/pfad/pre   speichert Screenshots
##   -- --quit=40          beendet nach 40 Sekunden
##   -- --demo             klickt sich nach dem Intro durchs Menü (Tuning zeigen, Rennen starten)
##   -- --at=lake|crossing|alley|fork|tunnel|el|stadium|<viertel>|d:<meter>   setzt das Auto nach dem Start direkt vor die Stelle
##   -- --race=2           wählt die Strecke (Index in Catalog.RACES)
##   -- --times=1.5,4,8    Zeitpunkte für Screenshots

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
var view: PackedStringArray = []  # --view=pfad:d:quer:höhe:ziel_d:ziel_quer:ziel_höhe  feste Kamera (Weg 0 = Hauptstraße)
var _menu_done := false
var look: PackedStringArray = []  # --look=wahrzeichen:höhe:blickhöhe:abstand[:d]  Kamera von der Straße auf ein Wahrzeichen (Orts-Strecken)
var _vcam: Camera3D
var _drift_t := -1.0  # laufendes Drift-Manöver (--drifty)
var _drift_dir := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			prefix = a.substr(7)
		elif a == "--drive":
			drive = true
		elif a == "--demo":
			demo = true
			drive = true
		elif a.begins_with("--quit="):
			quit_after = float(a.substr(7))
		elif a.begins_with("--at="):
			at = a.substr(5)
			drive = true
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
		if a.begins_with("--tune=") and race and race.has_method("_show_parts") and _t > 0.5 and not _menu_done:
			_menu_done = true  # Test: Tuning-Teileliste einer Kategorie öffnen (z. B. --tune=engine), Kamera fährt hin
			var cat := a.substr(7)
			var grp := "optik" if cat in Catalog.PART_GROUPS["optik"] else "leistung"
			race._show_tuning()
			race._show_parts(cat, grp)
		if a.begins_with("--menu=") and race and race.has_method("_show_events") and _t > 0.8 and not _menu_done:
			_menu_done = true  # Test: Garage direkt auf einer Event-Liste öffnen (z. B. --menu=city, --menu=tuning, --menu=cars, --menu=main)
			var which := a.substr(7)
			if race.has_method("_show_" + which):
				race.call("_show_" + which)  # tuning, cars, settings, races
			elif which != "main":
				race._show_races()
				race._show_events(which)
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
	if OS.get_cmdline_user_args().has("--handling") and race and "curve" in race and race.player and race.state == 1:
		_handling(race, dt)
		return
	# --slidetest: festes Drift-Manöver auf der Geraden (Fahrmodell prüfen): 0,25 s Handbremse + links, dann nur Gas
	if OS.get_cmdline_user_args().has("--slidetest") and race and "curve" in race and race.player and race.state == 1:
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
	if race and "curve" in race and race.player and (OS.get_cmdline_user_args().has("--trace") or OS.get_cmdline_user_args().has("--handling")):
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
	if OS.get_cmdline_user_args().has("--racelog") and race and "curve" in race and race.player and fmod(_t, 3.0) < dt:
		# kompakter Rennverlauf: eigenes Auto, Gegner (Gesamtfortschritt), Bildrate
		var pl = race.player
		print("rl t=%.0f gesamt=%.0f/%.0f platz=%d status=%d wand=%d fps=%d ki=%s" % [_t, pl.total, race.track["finish"], race._place(), race.state,
			pl.wall_hits, Engine.get_frames_per_second(), race.ais.map(func(a): return int(a.total))])
	if prefix != "" and _i < times.size() and _t >= times[_i]:
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [prefix, _i])
		_i += 1
		if _i == times.size() and quit_after <= 0.0:
			get_tree().quit()
	if quit_after > 0.0 and _t >= quit_after:
		get_tree().quit()


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

