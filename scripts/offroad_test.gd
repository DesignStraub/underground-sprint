extends Node
## Test im Gelände (seit 2.39): world.tscn -- --otest=<fall>. Fährt selbst (Gas, Bremse, Lenken wie ein Spieler) und
## meldet alle 0,2 s "OT ..." (Lage in Flächenkoordinaten, Tempo, Höhe über dem Boden, Untergrund, Flug) und am Ende
## "OT ENDE ..." mit den Befunden:
##   FALL    unter dem Boden (mehr als 0,3 m)        RUCK   Höhe springt am Boden um mehr als 0,5 m in einem Takt
##   RAUS    weder im Gelände noch auf einer Straße    HAENGT unter 1 m/s für 3 s bei Gas
##   WAND    Berührung mit Wand, Zaun, Baum, Fels (mit dem, woran)
## Fälle (i: Gelände, 0 Golfplatz, 1 Kiesgrube):
##   ein:<i>               von der Querspange über die Ausfahrt hinein, eine Runde über Wegpunkte, wieder hinaus
##   rampen:<i>[:kmh]      jede Rampe nacheinander: Anlauf, Sprung, Landung (Sprungkamera, Flugzeit, Höhe)
##   kuppen:<i>[:kmh]      über jeden hohen Hügel und Haufen (Abheben an der Kuppe)
##   baum:<i>[:kmh]        frontal gegen einen Baum           zaun:<i>[:grad[:kmh]]  gegen den Zaun
##   wasser:<i>            in den Teich: Spritzer, Neustart an sicherer Stelle, trocken
##   drift:<i>             Gas und Lenken auf Gras bzw. Kies (Driftwinkel), dann Handbremse
## --oframes=/pfad/bild:t0:t1:n  speichert von t0 bis t1 (Testzeit, s) jedes n-te Bild (Bildserie für die Doku)

const Offroad := preload("res://scripts/offroad.gd")
const Track := preload("res://scripts/track_builder.gd")

var w: Node  # world.gd
var case := ""
var _a: Dictionary = {}
var _ai := 0
var _t := 0.0
var _log := 0.0
var _route: Array = []  # [Welt x, z, Tempo m/s]
var _wi := 0
var _found := {"FALL": 0, "RUCK": 0, "RAUS": 0, "HAENGT": 0, "WAND": 0}
var _walls := 0
var _slow := 0.0
var _prev_y := INF
var _jumps := []  # [Flugzeit, Höhe]
var _land := 0
var _air0 := Vector3.ZERO
var _peak := -INF
var _queue: Array = []  # rampen/kuppen: weitere Versuche
var _phase := ""
var _phase_t := 0.0
var _target_v := 0.0
var _aim := Vector2.ZERO
var _aim_dir := Vector2.ZERO
var _hold_line := false
var _started := false
var _cams := 0
var _extra := {}
var _air_t := -1.0  # Zeitpunkt des Absprungs (erste Landung zählt, nicht das Nachfedern)
var _was_sinking := false


func _ready() -> void:
	process_priority = -10
	process_physics_priority = -10
	var p := case.split(":")
	_ai = int(p[1]) if p.size() > 1 else 0
	var list: Array = w.layout.get("offroad", [])
	if _ai >= list.size():
		print("OT FEHLT Gelände %d" % _ai)
		get_tree().quit()
		return
	_a = list[_ai]
	print("OT START %s in %s" % [case, _a["name"]])
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--oframes="):
			var fp := arg.substr(10).split(":")
			_frames = [fp[0], float(fp[1]), float(fp[2]), int(fp[3]) if fp.size() > 3 else 3]


var _frames := []  # [Pfad, t0, t1, n]
var _frame_i := 0


func _process(_dt: float) -> void:
	if _frames.is_empty() or _t < float(_frames[1]) or _t > float(_frames[2]):
		return
	_frame_i += 1
	if _frame_i % int(_frames[3]) == 0:
		get_viewport().get_texture().get_image().save_png("%s_%04d.png" % [_frames[0], _frame_i])


func _physics_process(dt: float) -> void:
	if not w._ready_done or w.player == null:
		return
	var pl = w.player
	if not _started:
		_started = true
		pl.debug_hits = true
		_setup(pl)
	_t += dt
	_phase_t += dt
	for act in ["steer_left", "steer_right", "accelerate", "brake", "handbrake", "nitro"]:
		Input.action_release(act)
	_check(pl, dt)
	match _phase:
		"route":
			_drive_route(pl)
		"line":
			_drive_line(pl)
		"drift":
			_drive_drift(pl)
		"done":
			return
	if _t > 150.0:
		_finish("Zeit")


func _setup(pl) -> void:
	var p := case.split(":")
	var kind := p[0]
	match kind:
		"ein":
			_route_in(pl)
		"rampen", "kuppen":
			var kmh := float(p[2]) if p.size() > 2 else 0.0
			if kind == "rampen":
				for r in _a["ramps"]:
					_queue.append(["rampe", r, kmh if kmh > 0.0 else 95.0])
			else:
				for pr in _a["prims"]:
					if (pr["k"] == "hill" or pr["k"] == "pile") and float(pr["h"]) >= 2.4:
						_queue.append(["kuppe", pr, kmh if kmh > 0.0 else 75.0])
			_next_try(pl)
		"baum":
			_tree(pl, float(p[2]) if p.size() > 2 else 60.0)
		"zaun":
			_fence(pl, float(p[2]) if p.size() > 2 else 30.0, float(p[3]) if p.size() > 3 else 70.0)
		"wasser":
			_water(pl)
		"drift":
			_drift(pl)
		_:
			print("OT unbekannter Fall %s" % kind)
			get_tree().quit()


# --- Fälle -----------------------------------------------------------------------------------------------------------

## Von der Querspange ins Gelände und wieder hinaus: Start 230 m vor der Ausfahrt auf der rechten Spur
func _route_in(pl) -> void:
	var host := _host()
	var tr: Dictionary = host["track"]
	var c: Curve3D = tr["curve"]
	var d0: float = _a["exit_d"]
	var gate := Offroad.world(_a, Vector2(_a["gate_s"], 0.0))
	var f := Track.frame_at(c, d0)
	var side := signf((Vector3(gate.x, 0, gate.y) - f["pos"]).dot(f["right"]))  # Ausfahrt rechts (+1) oder links (-1)
	var dir := side  # rechts fahren: Ausfahrt rechts heißt in Streckenrichtung
	var start := Track.xform_at(c, d0 - dir * 230.0, 6.75 * side)
	if dir < 0.0:
		start.basis = start.basis * Basis(Vector3.UP, PI)
	pl.place(start)
	pl.velocity = -start.basis.z * 24.0
	pl.speed_fwd = 24.0
	var lane := func(dd: float, lat: float) -> Vector2:
		var ff := Track.frame_at(c, dd)
		var q: Vector3 = ff["pos"] + ff["right"] * lat
		return Vector2(q.x, q.z)
	# wie ein Fahrer: rechte Spur, vor der Ausfahrt abbremsen, eng einbiegen
	_route = [[lane.call(d0 - dir * 90.0, 11.25 * side), 20.0], [lane.call(d0 - dir * 24.0, 11.25 * side), 7.0],
		[lane.call(d0 - dir * 6.0, 15.0 * side), 6.0], [lane.call(d0, 24.0 * side), 7.0]]
	var gs: float = _a["gate_s"]
	var inner: Array = [[Vector2(gs, -6.0), 11.0], [Vector2(gs, 16.0), 13.0]]
	if _a["kind"] == "golf":
		inner += [[Vector2(-112, 38), 16.0], [Vector2(-60, 92), 20.0], [Vector2(20, 112), 22.0], [Vector2(70, 160), 18.0],
			[Vector2(10, 248), 18.0], [Vector2(-110, 250), 16.0], [Vector2(-150, 150), 14.0], [Vector2(-140, 60), 12.0],
			[Vector2(gs, 22.0), 9.0], [Vector2(gs, -8.0), 9.0]]
	else:
		inner += [[Vector2(-75, 60), 14.0], [Vector2(-90, 110), 16.0], [Vector2(-60, 175), 14.0], [Vector2(0, 200), 14.0],
			[Vector2(70, 250), 12.0], [Vector2(140, 170), 14.0], [Vector2(60, 122), 14.0], [Vector2(-10, 44), 12.0],
			[Vector2(gs, 22.0), 9.0], [Vector2(gs, -8.0), 9.0]]
	for q in inner:
		_route.append([Offroad.world(_a, q[0]), q[1]])
	# zurück auf die Straße (rechts einfädeln: in Streckenrichtung bei Ausfahrt rechts) und ein Stück weiter
	_route += [[lane.call(d0, 24.0 * side), 6.0], [lane.call(d0, 15.0 * side), 6.0], [lane.call(d0 + dir * 30.0, 8.0 * side), 12.0],
		[lane.call(d0 + dir * 160.0, 6.75 * side), 24.0]]
	_wi = 0
	_phase = "route"


func _host() -> Dictionary:
	for e in w.entries:
		if e["kind"] == "seg" and e["state"] == "ready":
			for p in e["track"]["paths"]:
				if p.get("gelaende", false) and str(p.get("name", "")) == str(_a["exit"]):
					return e
	return w.active


## Nächster Versuch (Rampe oder Kuppe): 80 m Anlauf entlang der Achse, mit Tempo
func _next_try(pl) -> void:
	if _queue.is_empty():
		_finish("alle Versuche")
		return
	var q: Array = _queue.pop_front()
	var what: String = q[0]
	var dir: Vector2
	var tip: Vector2
	if what == "rampe":
		var r: Dictionary = q[1]
		dir = Offroad.wdir(_a, r["d"])
		tip = Offroad.world(_a, r["c"])
		_extra = {"was": "Rampe %s h=%.1f" % [r["look"], r["h"]]}
	else:
		var pr: Dictionary = q[1]
		var c: Vector2 = pr["c"]
		# quer über die schmale Seite (Wall, längliche Hügel), sonst die Richtung mit dem meisten Platz dahinter
		var rr: Vector2 = pr["r"]
		var best_d := Vector2(1, 0)
		var best_room := -1e9
		for k in 16:
			var dl := Vector2.from_angle(TAU * k / 16.0)
			if rr.x > rr.y * 1.8 and absf(dl.dot(Vector2.from_angle(float(pr["a"])))) > 0.35:
				continue
			var room := 0.0
			while room < 70.0 and Offroad.area_sd(_a, c + dl * (room + 2.0)) < -6.0:
				room += 2.0
			var back := 0.0
			while back < 70.0 and Offroad.area_sd(_a, c - dl * (back + 2.0)) < -6.0:
				back += 2.0
			if minf(room, back) > best_room:
				best_room = minf(room, back)
				best_d = dl
		dir = Offroad.wdir(_a, best_d)
		# Anlauf beginnt am Fuß des Hügels
		var foot := maxf(rr.x, rr.y) * 1.2 + 2.0
		if absf(best_d.dot(Vector2.from_angle(float(pr["a"])))) < 0.5:
			foot = minf(rr.x, rr.y) * 1.2 + 2.0
		tip = Offroad.world(_a, c - best_d * foot)
		_extra = {"was": "%s h=%.1f bei (%.0f, %.0f)" % [pr["k"], pr["h"], c.x, c.y]}
	# Anlauf bis 75 m, aber nur auf ebenem Boden (nicht über Wall oder Haufen hinweg)
	var h0 := Offroad.base_h(_a, Offroad.local(_a, tip))
	var run := 10.0
	while run < 75.0:
		var ql := Offroad.local(_a, tip - dir * (run + 2.0))
		if absf(Offroad.base_h(_a, ql) - h0) > 0.25 or Offroad.area_sd(_a, ql) > -8.0:
			break
		run += 2.0
	var start := tip - dir * run
	var gl := Offroad.local(_a, start)
	pl.place(Transform3D(Basis.looking_at(Vector3(dir.x, 0, dir.y), Vector3.UP), Vector3(start.x, Offroad.base_h(_a, gl) + 0.05, start.y)))
	_prev_y = INF
	_target_v = float(q[2]) / 3.6
	pl.velocity = Vector3(dir.x, 0, dir.y) * _target_v
	pl.speed_fwd = _target_v
	_aim = tip
	_aim_dir = dir
	_land = pl.landings
	_peak = -INF
	_phase = "line"
	_phase_t = 0.0
	_hold_line = true
	_cams = 0
	_air_t = -1.0
	print("OT VERSUCH %s Anlauf %.0f m mit %.0f km/h" % [_extra.get("was", case), run, q[2]])


func _drive_line(pl) -> void:
	var p := Vector2(pl.global_position.x, pl.global_position.z)
	# auf der Linie halten: Ziel 25 m voraus auf der Achse
	var along := (p - _aim).dot(_aim_dir)
	var tgt := _aim + _aim_dir * (along + 25.0)
	_steer_to(pl, tgt)
	_speed_to(pl, _target_v)
	if pl.airborne:
		if _air_t < 0.0:
			_air_t = _t
			_air0 = pl.global_position
		_peak = maxf(_peak, pl.global_position.y)
		if pl.jump_cam:
			_cams += 1
	var jumps := case.begins_with("rampen") or case.begins_with("kuppen")
	if not jumps:
		return
	if pl.landings > _land and _air_t >= 0.0:
		_land = pl.landings
		var fl := _t - _air_t
		var dist := Vector2(pl.global_position.x - _air0.x, pl.global_position.z - _air0.z).length()
		print("OT LANDUNG %s flug=%.2f s weit=%.0f m höhe=%.1f m v=%.0f km/h kamera=%s" % [_extra.get("was", case), fl, dist, _peak - _air0.y,
			absf(pl.speed_fwd) * 3.6, "ja" if _cams > 0 else "nein"])
		_jumps.append([fl, _peak - _air0.y])
		_queue_next_in(1.5)
		return
	if pl.sinking > 0.0:
		print("OT INS WASSER %s (%.0f km/h)" % [_extra.get("was", case), absf(pl.speed_fwd) * 3.6])
		_jumps.append([-1.0, 0.0])
		_queue_next_in(2.5)
		return
	if _phase_t > 9.0:
		print("OT KEIN SPRUNG %s (%.0f km/h)" % [_extra.get("was", case), absf(pl.speed_fwd) * 3.6])
		_next_try(pl)


func _queue_next_in(s: float) -> void:
	_phase = "wait"
	get_tree().create_timer(s).timeout.connect(func(): _next_try(w.player))


func _tree(pl, kmh: float) -> void:
	# Baum mit freiem Anlauf (40 m): nächster Baum zum Tor, vor dem nichts steht
	var best: Array = []
	var bd := 1e9
	for tr in _a["tree_list"]:
		var l: Vector2 = tr[0]
		var free := true
		for o in _a["tree_list"]:
			if o != tr and (o[0] as Vector2).distance_to(l - Vector2(0, 20)) < 22.0:
				free = false
		if free and l.distance_to(Vector2(_a["gate_s"], 40.0)) < bd and Offroad.area_sd(_a, l - Vector2(0, 40)) < -5.0:
			bd = l.distance_to(Vector2(_a["gate_s"], 40.0))
			best = tr
	if best.is_empty():
		_finish("kein Baum")
		return
	var tl: Vector2 = best[0]
	var tw := Offroad.world(_a, tl)
	var sl: Vector2 = tl - Vector2(0, 35)
	var sw := Offroad.world(_a, sl)
	var dir := (tw - sw).normalized()
	pl.place(Transform3D(Basis.looking_at(Vector3(dir.x, 0, dir.y), Vector3.UP), Vector3(sw.x, Offroad.base_h(_a, sl) + 0.05, sw.y)))
	_target_v = kmh / 3.6
	pl.velocity = Vector3(dir.x, 0, dir.y) * _target_v
	pl.speed_fwd = _target_v
	_aim = tw
	_aim_dir = dir
	_extra = {"baum": tw, "r": 0.32 * float(best[1])}
	_phase = "line"
	_phase_t = 0.0
	_queue = []
	get_tree().create_timer(3.5).timeout.connect(func():
		var p: Vector3 = w.player.global_position
		var d := Vector2(p.x, p.z).distance_to(tw)
		print("OT BAUM abstand Mitte %.2f m (Stamm %.2f) v=%.0f km/h wand=%d %s" % [d, _extra["r"], absf(w.player.speed_fwd) * 3.6,
			w.player.wall_hits, "DURCH" if (Vector2(p.x, p.z) - tw).dot(dir) > 1.0 else "davor"])
		_finish("Baum"))


func _fence(pl, deg: float, kmh: float) -> void:
	# Zaunpunkt weit hinten (gegenüber dem Tor), Anlauf 45 m von innen, deg Grad zur Senkrechten
	var ol: PackedVector2Array = _a["outline_l"]
	var best := Vector2.ZERO
	var bt := -1e9
	for q in ol:
		if q.y > bt:
			bt = q.y
			best = q
	var n := Offroad._sd_grad(_a, best)  # nach außen
	var inside := best - n * 45.0
	var dl := n.rotated(deg_to_rad(deg))
	var sw := Offroad.world(_a, inside)
	var dir := Offroad.wdir(_a, dl).normalized()
	pl.place(Transform3D(Basis.looking_at(Vector3(dir.x, 0, dir.y), Vector3.UP), Vector3(sw.x, Offroad.base_h(_a, inside) + 0.05, sw.y)))
	_target_v = kmh / 3.6
	pl.velocity = Vector3(dir.x, 0, dir.y) * _target_v
	pl.speed_fwd = _target_v
	_aim = sw + dir * 45.0
	_aim_dir = dir
	_phase = "line"
	_phase_t = 0.0
	get_tree().create_timer(4.5).timeout.connect(func():
		var p: Vector3 = w.player.global_position
		var sd := Offroad.area_sd(_a, Offroad.local(_a, Vector2(p.x, p.z)))
		print("OT ZAUN %s (Abstand zum Zaun %.1f m) v=%.0f km/h wand=%d" % ["DRINNEN" if sd < 0.0 else "DRAUSSEN", -sd,
			absf(w.player.speed_fwd) * 3.6, w.player.wall_hits])
		_finish("Zaun"))


func _water(pl) -> void:
	var pd: Dictionary = _a["ponds"][0]
	var c: Vector2 = pd["c"]
	var start := c - Vector2(0, float(pd["r"].y) + 40.0)
	if Offroad.area_sd(_a, start) > -6.0:
		start = c + Vector2(0, float(pd["r"].y) + 40.0)
	var sw := Offroad.world(_a, start)
	var cw := Offroad.world(_a, c)
	var dir := (cw - sw).normalized()
	pl.place(Transform3D(Basis.looking_at(Vector3(dir.x, 0, dir.y), Vector3.UP), Vector3(sw.x, Offroad.base_h(_a, start) + 0.05, sw.y)))
	_target_v = 14.0
	pl.velocity = Vector3(dir.x, 0, dir.y) * _target_v
	pl.speed_fwd = _target_v
	_aim = cw
	_aim_dir = dir
	_phase = "line"
	_phase_t = 0.0
	_extra = {"spritzer": false}
	get_tree().create_timer(7.0).timeout.connect(func():
		var p: Vector3 = w.player.global_position
		var l := Offroad.local(_a, Vector2(p.x, p.z))
		print("OT WASSER spritzer=%s neu bei (%.0f, %.0f) %s %s" % ["ja" if _extra["spritzer"] else "NEIN", l.x, l.y,
			"im Gelände" if Offroad.area_sd(_a, l) < 0.0 else "DRAUSSEN", "trocken" if Offroad.pond_at(_a, l).is_empty() else "NASS"])
		_finish("Wasser"))


func _drift(pl) -> void:
	# freie Fläche: Golfplatz Rough vor dem Clubhaus, Kiesgrube Sohle
	var l := Vector2(-40, 60) if _a["kind"] == "golf" else Vector2(20, 180)
	var sw := Offroad.world(_a, l)
	var dir := Offroad.wdir(_a, Vector2(1, 0))
	pl.place(Transform3D(Basis.looking_at(Vector3(dir.x, 0, dir.y), Vector3.UP), Vector3(sw.x, Offroad.base_h(_a, l) + 0.05, sw.y)))
	pl.velocity = Vector3(dir.x, 0, dir.y) * 16.0
	pl.speed_fwd = 16.0
	_phase = "drift"
	_phase_t = 0.0


func _drive_drift(pl) -> void:
	# 0-4 s Vollgas, voll eingelenkt (Heck kommt?), 4-6 s Gas weg, 6-6,4 s Handbremse, 6,4-9 s Gas halb eingelenkt
	var t := _phase_t
	if t < 4.0:
		Input.action_press("accelerate")
		Input.action_press("steer_right")
	elif t < 6.0:
		pass
	elif t < 6.4:
		Input.action_press("handbrake")
		Input.action_press("steer_right")
	elif t < 9.0:
		Input.action_press("accelerate")
		Input.action_press("steer_right", 0.6)
	else:
		_finish("Drift")


# --- Fahren und Prüfen ----------------------------------------------------------------------------------------------

func _drive_route(pl) -> void:
	if _wi >= _route.size():
		_finish("Weg zu Ende")
		return
	var p := Vector2(pl.global_position.x, pl.global_position.z)
	var wp: Vector2 = _route[_wi][0]
	if p.distance_to(wp) < (6.0 if float(_route[_wi][1]) < 10.0 else 9.0):
		_wi += 1
		return
	_steer_to(pl, wp)
	_speed_to(pl, _route[_wi][1])


func _steer_to(pl, tgt: Vector2) -> void:
	var f := -pl.global_basis.z as Vector3
	var fd := Vector2(f.x, f.z).normalized()
	var p := Vector2(pl.global_position.x, pl.global_position.z)
	var d := (tgt - p).normalized()
	var ang := fd.angle_to(d)  # > 0: Ziel rechts (Bildschirm-Koordinaten x, z)
	var s := clampf(ang * 2.2, -1.0, 1.0)
	if s > 0.02:
		Input.action_press("steer_right", s)
	elif s < -0.02:
		Input.action_press("steer_left", -s)


func _speed_to(pl, v: float) -> void:
	var cur: float = pl.speed_fwd
	if cur < v - 1.0:
		Input.action_press("accelerate", 1.0)
	elif cur > v + 3.0:
		Input.action_press("brake", clampf((cur - v) / 8.0, 0.3, 1.0))
	elif cur < v:
		Input.action_press("accelerate", 0.5)


func _check(pl, dt: float) -> void:
	var p: Vector3 = pl.global_position
	var p2 := Vector2(p.x, p.z)
	var a := Offroad.find(p2)
	var gh := NAN
	if not a.is_empty():
		var g := Offroad.ground(a, p2)
		gh = g["h"]
		if not g["water"] and p.y < float(g["h"]) - 0.3 and pl.sinking <= 0.0:
			_found["FALL"] += 1
			if _found["FALL"] < 4:
				print("OT FALL y=%.2f Boden %.2f bei %s" % [p.y, g["h"], p2])
	elif not pl.track.is_empty() and float(pl.loc.get("score", 0.0)) > 7.0 and pl.sinking <= 0.0 and not pl.tumbling:
		_found["RAUS"] += 1
		if _found["RAUS"] < 4:
			print("OT RAUS bei %s score=%.1f" % [p2, pl.loc["score"]])
	if not pl.airborne and _prev_y != INF and absf(p.y - _prev_y) > 0.5 and pl.sinking <= 0.0 and not _was_sinking:
		_found["RUCK"] += 1
		print("OT RUCK %.2f -> %.2f bei %s gelände=%s" % [_prev_y, p.y, p2, "ja" if not a.is_empty() else "nein"])
	_prev_y = p.y
	_was_sinking = pl.sinking > 0.0
	if pl.sinking > 0.0:
		_extra["spritzer"] = true
	if pl.wall_hits != _walls:
		_walls = pl.wall_hits
		_found["WAND"] += 1
		print("OT WAND %s" % pl.last_hit)
	var kmh: float = absf(pl.speed_fwd) * 3.6
	if _phase == "route" and kmh < 3.6 and _phase_t > 3.0:
		_slow += dt
		if _slow > 3.0:
			_found["HAENGT"] += 1
			print("OT HAENGT bei %s" % p2)
			_slow = 0.0
			_wi += 1
	else:
		_slow = 0.0
	_log -= dt
	if _log <= 0.0:
		_log = 0.2
		var l := Offroad.local(_a, p2)
		print("OT t=%.1f v=%3d (s %.0f, t %.0f) y=%.2f boden=%s untergrund=%s flug=%s drift=%.0f grip=%.2f gelände=%s wp=%d gas=%.2f gang=%d stun=%.1f" % [_t, int(kmh),
			l.x, l.y, p.y, "-" if is_nan(gh) else "%.2f" % gh, pl.surface, "ja" if pl.airborne else "nein", pl.drift_angle,
			float(pl._sf["grip"]), "ja" if not pl.offroad.is_empty() else "nein", _wi, pl._thr_s, pl.gear, pl.stun])


func _finish(why: String) -> void:
	if _phase == "done":
		return
	_phase = "done"
	var js := ", ".join(_jumps.map(func(j): return ("%.2fs/%.1fm" % [j[0], j[1]]) if j[0] >= 0.0 else "Wasser"))
	print("OT ENDE %s (%s) nach %.1f s: FALL=%d RUCK=%d RAUS=%d HAENGT=%d WAND=%d Sprünge=%d [%s]" % [case, why, _t, _found["FALL"],
		_found["RUCK"], _found["RAUS"], _found["HAENGT"], _found["WAND"], _jumps.size(), js])
	get_tree().create_timer(0.3).timeout.connect(func(): get_tree().quit())
