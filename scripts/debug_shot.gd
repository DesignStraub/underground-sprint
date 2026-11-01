extends Node
## Nur für Tests und Videos:
##   -- --drive            Autopilot fährt (weicht Verkehr aus, nutzt Nitro)
##   -- --shot=/pfad/pre   speichert Screenshots
##   -- --quit=40          beendet nach 40 Sekunden
##   -- --demo             klickt sich nach dem Intro durchs Menü (Tuning zeigen, Rennen starten)

const Track := preload("res://scripts/track_builder.gd")

var prefix := ""
var drive := false
var quit_after := 0.0
var times := [1.5, 6.0, 9.0, 16.0, 24.0, 32.0]
var _t := 0.0
var _i := 0
var _lane := Track.LANES[2]
var demo := false
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
	if drive and race and "curve" in race and race.player:
		var pl = race.player
		var look: float = 25.0 + absf(pl.speed_fwd) * 1.6
		if not _lane_free(race, _lane, -3.0, look):
			var best: float = _lane
			var cost := 1e9
			for l in Track.LANES:
				if _lane_free(race, l, -4.0, look) and absf(l - pl.lateral) < cost:
					cost = absf(l - pl.lateral)
					best = l
			_lane = best
		var d: float = pl.progress + 18.0 + absf(pl.speed_fwd) * 0.35
		var f := Track.frame_at(race.curve, d)
		var tgt: Vector3 = f["pos"] + f["right"] * _lane
		var side: float = (tgt - pl.global_position).dot(pl.global_basis.x)
		Input.action_release("steer_left")
		Input.action_release("steer_right")
		if absf(side) > 0.3:
			Input.action_press("steer_right" if side > 0.0 else "steer_left", clampf(absf(side) / 3.0, 0.0, 1.0))
		# Vor engen Kurven vom Gas
		var f0 := Track.frame_at(race.curve, pl.progress)
		var f1 := Track.frame_at(race.curve, pl.progress + 30.0 + absf(pl.speed_fwd))
		var bend: float = (f0["fwd"] as Vector3).angle_to(f1["fwd"])
		var too_fast: bool = bend > 0.5 and pl.speed_fwd > 38.0
		if too_fast:
			Input.action_release("accelerate")
		else:
			Input.action_press("accelerate")
		if bend < 0.15 and pl.nitro > 0.3 and pl.speed_fwd > 20.0 and _lane_free(race, _lane, 0.0, 80.0):
			Input.action_press("nitro")
		else:
			Input.action_release("nitro")
	if prefix != "" and _i < times.size() and _t >= times[_i]:
		get_viewport().get_texture().get_image().save_png("%s_%d.png" % [prefix, _i])
		_i += 1
		if _i == times.size() and quit_after <= 0.0:
			get_tree().quit()
	if quit_after > 0.0 and _t >= quit_after:
		get_tree().quit()
