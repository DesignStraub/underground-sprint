extends Node
## Nur für Tests und Videos:
##   -- --drive            Autopilot fährt (weicht Verkehr aus, nutzt Nitro)
##   -- --shot=/pfad/pre   speichert Screenshots
##   -- --quit=40          beendet nach 40 Sekunden
##   -- --demo             klickt sich nach dem Intro durchs Menü (Tuning zeigen, Rennen starten)
##   -- --at=lake|crossing|alley|tunnel|el|stadium|<viertel>   setzt das Auto nach dem Start direkt vor die Stelle
##   -- --race=2           wählt die Strecke (Index in Catalog.RACES)
##   -- --times=1.5,4,8    Zeitpunkte für Screenshots

const Track := preload("res://scripts/track_builder.gd")

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
	if at != "" and race and "curve" in race and race.player:
		if not _placed and race.state == 1:
			_placed = true
			_place_at(race)
	if drive and race and "curve" in race and race.player and not race.player.loc.is_empty():
		var pl = race.player
		var p: Dictionary = race.track["paths"][pl.path_id]
		var on_main: bool = p["id"] == 0
		var look: float = 25.0 + absf(pl.speed_fwd) * 1.6
		if on_main and not lock_lane and not _lane_free(race, _lane, -3.0, look):
			var best: float = _lane
			var cost := 1e9
			for l in Track.LANES:
				if _lane_free(race, l, -4.0, look) and absf(l - pl.lateral) < cost:
					cost = absf(l - pl.lateral)
					best = l
			_lane = best
		var dl: float = pl.loc["d"] + 14.0 + absf(pl.speed_fwd) * 0.3
		var f := Track.frame_at(p["curve"], dl)
		var tgt: Vector3 = f["pos"] + f["right"] * (_lane if on_main else 0.0)
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
	if OS.get_cmdline_user_args().has("--trace") and race and "curve" in race and race.player and fmod(_t, 0.1) < dt:
		var pl = race.player
		var near := ""
		for t in race.traffic:
			if absf(t.progress - pl.progress) < 12.0:
				near += " T(%.1f,%.1f)" % [t.progress - pl.progress, t.lateral()]
		print("t=%.1f d=%.1f lat=%.2f v=%.1f path=%d fps=%d%s" % [_t, pl.progress, pl.lateral, pl.speed_fwd, pl.path_id, Engine.get_frames_per_second(), near])
		for n in get_tree().get_nodes_in_group("ambient"):
			if "_cars" in n:
				print("   zug aktiv=%s d=%.0f (%.0f-%.0f) sichtbar=%s y=%.1f" % [n._active, n._d, n.d_from, n.d_to, n._cars[0].visible, n._cars[0].global_position.y])
	if prefix != "" and _i < times.size() and _t >= times[_i]:
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [prefix, _i])
		_i += 1
		if _i == times.size() and quit_after <= 0.0:
			get_tree().quit()
	if quit_after > 0.0 and _t >= quit_after:
		get_tree().quit()


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
					d = tr["tunnels"][0]["from"] - 90.0
				"el":
					d = tr["el"][0]["from"] - 220.0
				"stadium":
					d = tr["stadium_d"] - 160.0
			_drop(race, d)
		"lake", "alley":
			for p in tr["paths"]:
				if p["kind"] == at:
					var d := 30.0
					for r in tr["ramps"]:
						if r["path"] == p["id"]:
							d = r["d0"] - 12.0
					pl.place(Track.xform_at(p["curve"], d, 0.0))
					pl.velocity = -pl.global_basis.z * (38.0 if at == "lake" else 22.0)
					break
		_:
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
