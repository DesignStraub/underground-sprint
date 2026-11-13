extends Node
## Test der ganzen Welt (world.tscn -- --wtour[=ring|outer|cities|<Name>]): ein Autopilot fährt jede Straße ab, ohne
## Verkehr, und meldet alles, was auf einer freien Straße nicht passieren darf:
##   WAND   Berührung mit Wand oder Hindernis, obwohl er in der Spur fährt (mit dem Ding, woran er stieß)
##   FEST   steckt fest (unter 2 m/s für 3 s), wird 30 m weitergesetzt
##   FALL   fällt unter die Straße, wird zurückgesetzt
##   NEBEN  mehr als einen Gehweg neben der Fahrbahn
##   KIPPT  Überschlag
## Ablauf: innerer Ring einmal ganz, Außenring einmal ganz, dann jede Stadt: Auffahrt vom Ring, Ausfahrt der Stadt,
## Hauptstraße (Sprint bis hinter das Ziel und über die Verbindung zum Ring; Rundkurs eine Runde und wieder hinaus),
## dazu jede Abkürzung/Gabelung. Nacheinander liegende Stücke fährt er ohne Absetzen (Nahtstellen werden mitgeprüft).
## Am Ende "TOUR SUMME ...". Schneller als Echtzeit: mit --fixed-fps 60 starten.

const Track := preload("res://scripts/track_builder.gd")
const Catalog := preload("res://scripts/catalog.gd")

var w: Node  # world.gd
var only := ""
var legs: Array = []  # {e, find (Callable track -> path id), rev, name}
var _li := -1
var _leg: Dictionary = {}
var _state := 0  # 0 warten auf Bau, 1 fährt
var _d := 0.0  # Weg-Meter auf dem aktuellen Weg
var _to := 0.0
var _dir := 1.0
var _path: Dictionary = {}
var _track: Dictionary = {}
var _xf := Transform3D.IDENTITY
var _slow_t := 0.0
var _t := 0.0
var _walls := 0
var _travel := 0.0
var _last_off := -1e9
var _counts := {}
var _wait_t := 0.0
var _total_m := 0.0


func _ready() -> void:
	w.player.debug_hits = true
	_plan()
	print("TOUR %d Abschnitte" % legs.size())
	_next()


func _plan() -> void:
	var rings: Array = w._rings
	if only == "" or only == "ring":
		for e in rings[0]:
			legs.append({"e": e, "find": func(_tr): return 0, "rev": false, "name": "Ring %d" % e["seg_i"]})
	if only == "" or only == "outer":
		for e in rings[1]:
			legs.append({"e": e, "find": func(_tr): return 0, "rev": false, "name": "Außenring %d" % e["seg_i"]})
	if only == "ring" or only == "outer":
		return
	for e in w.entries:
		if e["kind"] != "city":
			continue
		var race: Dictionary = Catalog.RACES[e["race_index"]]
		var nm: String = race["name"]
		if only != "" and only != "cities" and not nm.to_lower().begins_with(only.to_lower()):
			continue
		var town: String = race.get("town", "")
		var seg_in := _seg_with_ramp(town, false)
		if not seg_in.is_empty():
			legs.append({"e": seg_in, "find": _ramp_finder(town, false), "rev": false, "name": nm + ": Auffahrt"})
		var loop: bool = race.get("type", "sprint") != "sprint"
		if not loop:
			legs.append({"e": e, "find": func(tr): return _city_path(tr, "tail0"), "rev": true, "name": nm + ": Ausfahrt"})
			legs.append({"e": e, "find": func(_tr): return 0, "rev": false, "name": nm + ": Hauptstraße"})
			legs.append({"e": e, "find": func(tr): return _city_path(tr, "tail1"), "rev": false, "name": nm + ": Ziel-Ausfahrt"})
			var seg2 := _seg_with_ramp(town, true)
			if not seg2.is_empty():
				legs.append({"e": seg2, "find": _ramp_finder(town, true), "rev": true, "name": nm + ": Verbindung"})
		else:
			legs.append({"e": e, "find": func(tr): return _city_path(tr, "exit"), "rev": true, "name": nm + ": Ausfahrt"})
			legs.append({"e": e, "find": func(_tr): return 0, "rev": false, "name": nm + ": Runde", "loop": true})
			legs.append({"e": e, "find": func(tr): return _city_path(tr, "exit"), "rev": false, "name": nm + ": hinaus"})
		for k in 24:  # Abkürzungen, Gabelungen, Nebenstraßen und Durchfahrten (Kreuzberg hat gut 20)
			legs.append({"e": e, "find": func(tr): return _city_path(tr, "branch%d" % k), "rev": false, "name": nm + ": Abzweig %d" % k,
				"optional": true})


func _seg_with_ramp(town: String, conn: bool) -> Dictionary:
	for e in w._segs:
		for r in e["race"].get("ramps", []):
			if r.get("name", "") == town and r.has("c1") == conn:
				return e
	return {}


func _ramp_finder(town: String, conn: bool) -> Callable:
	return func(tr: Dictionary) -> int:
		for p in tr["paths"]:
			if p["kind"] == "ramp" and p.get("name", "") == town and p.get("conn", false) == conn:
				return p["id"]
		return -1


## Wege einer Stadt: tail0 (Ausfahrt am Start), tail1 (hinter dem Ziel), exit (Ausfahrt eines Rundkurses),
## branchN (N-te Abkürzung/Gabelung/See-Umfahrung/Nebenstraße/Durchfahrt; Sackgassen und Ausfahrten zählen nicht)
func _city_path(tr: Dictionary, what: String) -> int:
	var L: float = tr["length"]
	var bi := 0
	for p in tr["paths"]:
		if p["id"] == 0:
			continue
		var k: String = p["kind"]
		if what == "tail0" and k == "ramp" and p.get("tail", false) and p["from"] < 1.0:
			return p["id"]
		if what == "tail1" and k == "ramp" and p.get("tail", false) and p["from"] > L - 1.0:
			return p["id"]
		if what == "exit" and k == "ramp" and not p.get("tail", false):
			return p["id"]
		if what.begins_with("branch") and k != "ramp" and k != "spur":
			if what == "branch%d" % bi:
				return p["id"]
			bi += 1
	return -1


func _next() -> void:
	_li += 1
	for a in ["steer_left", "steer_right", "accelerate", "brake", "nitro", "handbrake"]:
		Input.action_release(a)
	if _li >= legs.size():
		print("TOUR SUMME %.1f km gefahren, %s" % [_total_m / 1000.0, str(_counts)])
		get_tree().quit()
		return
	_leg = legs[_li]
	_state = 0
	_wait_t = 0.0
	# in die Nähe setzen, damit die Strecke gebaut wird (wenn sie es nicht schon ist)
	var e: Dictionary = _leg["e"]
	if e["state"] != "ready":
		w.player.place(Transform3D(Basis(), (e["center"] as Vector3) + Vector3(0, 0.6, 0)))


func _physics_process(dt: float) -> void:
	if _li < 0 or _li >= legs.size():
		return
	var pl = w.player
	if _state == 0:
		var e: Dictionary = _leg["e"]
		if _wait_t == 0.0:
			_wait_t = Time.get_ticks_msec() / 1000.0
		if e["state"] != "ready":
			if Time.get_ticks_msec() / 1000.0 - _wait_t > 150.0:  # echte Sekunden (mit --fixed-fps läuft das Spiel schneller)
				_report("BAU", "Strecke wird nicht fertig")
				_next()
			return
		_track = e["track"]
		_xf = e["xf"]
		var pid: int = _leg["find"].call(_track)
		if pid < 0:
			if not _leg.get("optional", false):
				_report("FEHLT", "Weg nicht gefunden")
			_next()
			return
		_path = _track["paths"][pid]
		if OS.get_cmdline_user_args().has("--wpaths") and not _track.has("_dumped"):
			_track["_dumped"] = true
			print("STRECKE %s länge=%.0f bahn=%.0f" % [_leg["name"], _track["length"], _track.get("crossing_d", -1.0)])
			for q in _track["paths"]:
				var qc: Curve3D = q["curve"]
				print("PFAD %d %s from=%.0f to=%.0f len=%.0f hw=%.1f tail=%s conn=%s a=%s b=%s" % [q["id"], q["kind"], q["from"], q["to"], qc.get_baked_length(),
					q["half_w"], q.get("tail", false), q.get("conn", false), (_xf * qc.sample_baked(0.0)).snapped(Vector3.ONE), (_xf * qc.sample_baked(qc.get_baked_length())).snapped(Vector3.ONE)])
		var L: float = (_path["curve"] as Curve3D).get_baked_length()
		_dir = -1.0 if _leg["rev"] else 1.0
		_d = L - 1.0 if _leg["rev"] else 1.0
		_to = 1.0 if _leg["rev"] else L - 1.0
		if _leg.get("loop", false):
			# Runde ab der Einmündung der Ausfahrt (da kommt man her)
			var ei := _city_path(_track, "exit")
			if ei >= 0:
				_d = _track["paths"][ei]["from"]
			_to = _d + L - 4.0
		# liegt der Anfang da, wo das Auto gerade ist (vorheriges Stück endete hier)? Dann einfach weiterfahren
		var start_w: Vector3 = _xf * _pos(_d)
		if pl.global_position.distance_to(start_w) > 25.0 or pl.velocity.length() < 3.0:
			var f := Track.frame_at(_path["curve"], fposmod(_d, L))
			var lat := _lat(fposmod(_d, L))
			var b := Basis.looking_at((_xf.basis * f["fwd"] * _dir).normalized(), Vector3.UP)
			pl.place(Transform3D(b, start_w + _xf.basis * (f["right"] * lat) + Vector3(0, 0.4, 0)))
			pl.velocity = b * Vector3(0, 0, -12.0)
			pl.speed_fwd = 12.0
		_state = 1
		_t = 0.0
		_slow_t = 0.0
		_walls = pl.wall_hits
		_travel = 0.0
		return
	_t += dt
	var c: Curve3D = _path["curve"]
	var L2: float = c.get_baked_length()
	var loop: bool = _leg.get("loop", false)
	# Lage auf dem Weg: nächster Punkt in der Nähe der letzten (sonst springt er bei engen Kurven auf ein anderes Stück)
	var lp: Vector3 = _xf.affine_inverse() * pl.global_position
	var best := 1e9
	var bd := _d
	var s := -12.0
	while s <= 40.0:
		var dd := _d + s * _dir
		if not loop:
			dd = clampf(dd, 0.0, L2)  # nicht über das Ende hinaus zählen
		var q: Vector3 = _pos(dd)
		var dist := Vector2(q.x - lp.x, q.z - lp.z).length()
		if dist < best - 0.01:
			best = dist
			bd = dd
		s += 2.0
	_travel += absf(bd - _d)
	_total_m += absf(bd - _d)
	_d = bd
	var f := Track.frame_at(c, fposmod(_d, L2) if loop else clampf(_d, 0.0, L2))
	var lat_now: float = (lp - f["pos"]).dot(f["right"])
	# fertig?
	if (_to - _d) * _dir <= 6.0:
		_counts["ok"] = _counts.get("ok", 0) + 1
		_next()
		return
	if _t > L2 / 8.0 + 40.0:
		_report("ZEIT", "Abschnitt nicht in der Zeit geschafft (%.0f von %.0f m)" % [absf(_d - (L2 - 1.0 if _leg["rev"] else 1.0)), L2])
		_next()
		return
	# Auffälligkeiten
	if pl.wall_hits != _walls:
		_walls = pl.wall_hits
		var dm := fposmod(_d, L2)
		var extra := ""
		if _path["id"] == 0:
			extra = " hw=%.1f mitte=%.1f trog=%d" % [Track.hw(_track, dm), Track.median_at(_track, dm), Track._trough_at(_track, dm)]
			if OS.get_cmdline_user_args().has("--wpaths"):
				# Verlauf um die Stelle: Richtung (Grad) und Höhe alle 10 m
				var cv: Curve3D = _track["curve"]
				var prof := []
				for k in range(-6, 7):
					var fk := Track.frame_at(cv, fposmod(dm + k * 10.0, L2))
					prof.append("%.0f/%.1f" % [rad_to_deg(atan2(fk["fwd"].x, fk["fwd"].z)), fk["y"]])
				extra += " verlauf=" + " ".join(prof)
		_report("WAND", "%s quer=%.1f%s" % [pl.last_hit if "last_hit" in pl else pl._collider_name, lat_now, extra])
	var half: float = Track.hw(_track, fposmod(_d, L2)) if _path["id"] == 0 else float(_path.get("half_w", Track.HALF_W))
	if absf(lat_now) > half + Track.WALK + 3.0:
		if _d * _dir - _last_off > 50.0:
			_last_off = _d * _dir
			_report("NEBEN", "quer=%.1f" % lat_now)
	var road_y: float = (_xf * (f["pos"] + Vector3(0, f["y"], 0))).y
	if pl.global_position.y < road_y - 2.5:
		_report("FALL", "Höhe %.1f, Straße %.1f" % [pl.global_position.y, road_y])
		_reset_ahead(10.0)
		return
	if pl.tumbling:
		_report("KIPPT", "")
	if absf(pl.speed_fwd) < 2.0 and _t > 3.0:
		_slow_t += dt
		if _slow_t > 3.0:
			_report("FEST", "quer=%.1f %s" % [lat_now, pl._collider_name])
			_reset_ahead(30.0)
			return
	else:
		_slow_t = 0.0
	_drive(pl, c, L2, loop)


func _pos(d: float) -> Vector3:
	var c: Curve3D = _path["curve"]
	var L: float = c.get_baked_length()
	var dd := fposmod(d, L) if _leg.get("loop", false) else clampf(d, 0.0, L)
	var f := Track.frame_at(c, dd)
	return f["pos"] + Vector3(0, f["y"], 0)


## Querlage an Weg-Meter d: Hauptstraße über Track.lane_lat (Mittelstreifen und Inseln versetzen die Spuren)
func _lat(d: float) -> float:
	if _path["id"] == 0:
		return Track.lane_lat(_track, d, _lane())
	return _lane()


## Spur: auf der Hauptstraße rechts (in Fahrtrichtung), auf Auffahrten und Abzweigen leicht rechts der Mitte
func _lane() -> float:
	if _path["id"] == 0 and _leg["e"]["kind"] == "seg":
		return 6.75 * _dir
	if _path["id"] == 0:
		return 2.25 * _dir
	if _path["kind"] != "ramp":
		return 0.0  # Gassen und Abkürzungen: Mitte (an den Wänden stehen absichtlich Container und Kisten)
	return 2.0 * _dir


func _drive(pl: Node, c: Curve3D, L: float, loop: bool) -> void:
	var look := 14.0 + absf(pl.speed_fwd) * 0.5
	var dt := _d + look * _dir
	var ft := Track.frame_at(c, fposmod(dt, L) if loop else clampf(dt, 0.0, L))
	var tgt: Vector3 = _xf * (ft["pos"] + ft["right"] * _lat(fposmod(dt, L) if loop else clampf(dt, 0.0, L)) + Vector3(0, ft["y"], 0))
	var to: Vector3 = tgt - pl.global_position
	var side: float = to.dot(pl.global_basis.x)
	for a in ["steer_left", "steer_right", "accelerate", "brake"]:
		Input.action_release(a)
	if side > 0.4:
		Input.action_press("steer_right", clampf(side / 5.0, 0.15, 1.0))
	elif side < -0.4:
		Input.action_press("steer_left", clampf(-side / 5.0, 0.15, 1.0))
	# Tempo nach der Kurve voraus
	var f0 := Track.frame_at(c, fposmod(_d, L) if loop else clampf(_d, 0.0, L))
	var a1 := 0.0
	for ahead in [25.0, 50.0, 80.0]:
		var da: float = _d + ahead * _dir
		var fa := Track.frame_at(c, fposmod(da, L) if loop else clampf(da, 0.0, L))
		a1 = maxf(a1, (f0["fwd"] as Vector3).angle_to(fa["fwd"]) * 60.0 / ahead)
	var vt := lerpf(42.0, 13.0, clampf(a1 / 0.9, 0.0, 1.0))
	# zeigt das Auto noch nicht in Wegrichtung (Abbiegen an einer Einmündung)? Dann langsam, wie ein Spieler
	var want_dir: Vector3 = (_xf.basis * ft["fwd"] * _dir)
	var head := (-pl.global_basis.z as Vector3).angle_to(Vector3(want_dir.x, 0, want_dir.z))
	vt = minf(vt, lerpf(42.0, 8.0, clampf(head / 0.9, 0.0, 1.0)))
	# vor dem Ende des Abschnitts abbremsen, wenn es danach um die Ecke geht (Einmündung): nur Ringstücke laufen gerade weiter
	var nxt: Dictionary = legs[_li + 1] if _li + 1 < legs.size() else {}
	var straight_on: bool = not nxt.is_empty() and nxt["e"]["kind"] == "seg" and _leg["e"]["kind"] == "seg" and _path["id"] == 0
	if not straight_on:
		vt = minf(vt, 9.0 + sqrt(2.0 * 5.0 * maxf((_to - _d) * _dir - 6.0, 0.0)))
	var v: float = pl.speed_fwd
	if v < vt - 1.0:
		Input.action_press("accelerate")
	elif v > vt + 3.0:
		Input.action_press("brake")


func _reset_ahead(m: float) -> void:
	var c: Curve3D = _path["curve"]
	var L: float = c.get_baked_length()
	_d += m * _dir
	if (_to - _d) * _dir <= 6.0:
		_next()
		return
	var loop: bool = _leg.get("loop", false)
	var f := Track.frame_at(c, fposmod(_d, L) if loop else clampf(_d, 0.0, L))
	var b := Basis.looking_at((_xf.basis * f["fwd"] * _dir).normalized(), Vector3.UP)
	w.player.place(Transform3D(b, _xf * _pos(_d) + _xf.basis * (f["right"] * _lat(fposmod(_d, L) if loop else clampf(_d, 0.0, L))) + Vector3(0, 0.4, 0)))
	w.player.velocity = b * Vector3(0, 0, -10.0)
	_slow_t = 0.0
	_t = maxf(_t - 5.0, 0.0)


func _report(kind: String, msg: String) -> void:
	_counts[kind] = _counts.get(kind, 0) + 1
	var p: Vector3 = w.player.global_position
	print("TB %-5s %-40s weg=%s d=%.0f pos=(%.0f, %.0f) %s" % [kind, _leg.get("name", "?"), _path.get("kind", "?"), _d, p.x, p.z, msg])
