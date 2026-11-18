extends Node
## Autobahn-Rennen (seit 2.43, Fahrplan Punkt 2): Sprint über die echte Autobahn der offenen Welt, von einer Stadt in
## die nächste. Start auf der Auffahrt am Ortsausgang der einen Stadt (blaue Lichtsäule wie ein Autobahnschild), über
## den inneren Ring mit allem Verkehr, Ziel am Ortseingang der anderen. Drei Gegner (highway_racer.gd) fahren dieselbe
## Strecke. Alle Rennen laufen in der Richtung, in der die Städte rechts liegen: Auffahrt und Ausfahrt sind dann
## Rechtskurven, niemand kreuzt die Gegenfahrbahn.
## Kein Szenenwechsel: die Welt läuft weiter (Verkehr, Nachladen, Tageszeit); world.gd hält solange Karte, Marker,
## Herausforderer und Schnellreise an. Fortschritt: Lage auf der Route als Linienzug (Auffahrt, Ringpunkte, Ausfahrt),
## nur in einem Fenster um den letzten Stand gesucht, Abkürzungen durch die Mitte zählen also nicht.
## Tests: world.tscn -- --hwrace=i (Start an Rennen i, sofort los) --hwbot (fährt selbst) --hwlog (alle 2 s Stand).

const Racer := preload("res://scripts/highway_racer.gd")
const Track := preload("res://scripts/track_builder.gd")
const PlayerCar := preload("res://scripts/player_car.gd")
const Builder := preload("res://scripts/car_builder.gd")
const UI := preload("res://scripts/ui_style.gd")
const Catalog := preload("res://scripts/catalog.gd")

## [Autobahn, Rennen der Stadt A, Rennen der Stadt B, Stufe (Erfahrung wie Catalog.race_xp)]. Die Richtung legt plan()
## fest (Städte rechts), der Name folgt ihr.
const DEFS := [
	["A1", 3, 4, 1],  # Dortmund – Köln
	["A3", 0, 4, 1],  # Frankfurt – Köln
	["A1", 7, 5, 2],  # Hamburg – Bremen
	["A6", 12, 6, 2],  # Heidelberg – Stuttgart
	["A20", 13, 7, 3],  # Rostock – Hamburg
	["A7", 16, 17, 3],  # Würzburg – Bad Kissingen
	["A9", 20, 1, 3],  # Berlin – München
]
const START_IN := 26.0  # Startaufstellung: so weit vom Ortsausgang auf der Auffahrt
const FINISH_IN := 26.0  # Ziel: so weit vor dem Ortseingang (dahinter rollen die Gegner aus)
const AB_COL := Color(0.25, 0.52, 1.0)  # Blau wie die Autobahnschilder
const GEGNER := 3

var w: Node  # world.gd
var def: Dictionary
var racers: Array = []
var state := 0  # 0 Countdown, 1 Rennen, 2 im Ziel (Ergebnis steht), 3 vorbei
var t := 0.0
var p_d := 0.0  # Spieler: Meter auf der Route
var place := 0
var _count := 3.99
var _beep := -1
var _end_t := 0.0
var _off_t := 0.0
var _finished_ai := 0
var _top: Array = []
var _info: Label
var _center: Label
var _log_t := 0.0
var _bot := false
var _log := false


# --- Planung (einmal beim Laden der Welt) ---------------------------------------------------------------------

## Rennen aus der Weltanlage: je Eintrag {name, auto, a, b, ta, tb, tier, ramp_a, ramp_b, dirk, pts, cum, length,
## start_xf, finish_d, ring0, ring1}; Rennen, deren Städte keine Auffahrt am inneren Ring haben, fallen weg
static func plan(layout: Dictionary) -> Array:
	var ring: Array = layout["ring"]
	var m := ring.size()
	var ramps := {}
	for s in layout["segments"]:
		if int(s.get("ring", 0)) != 0:
			continue
		for r in s["race"].get("ramps", []):
			for c in layout["cities"]:
				if Vector2(c["exit_world"].x - r["end"].x, c["exit_world"].z - r["end"].z).length() < 1.0:
					ramps[c["race_index"]] = r
	var out := []
	for dd in DEFS:
		var a: int = dd[1]
		var b: int = dd[2]
		if not ramps.has(a) or not ramps.has(b):
			continue
		var dirk := _right_dir(ring, ramps[a])
		var span := posmod((int(ramps[b]["k"]) - int(ramps[a]["k"])) * dirk, m)
		if span > m / 2:
			var tmp := a
			a = b
			b = tmp
			span = posmod((int(ramps[b]["k"]) - int(ramps[a]["k"])) * dirk, m)
		var ra: Dictionary = ramps[a]
		var rb: Dictionary = ramps[b]
		var ea: Vector3 = ra["end"]
		var fa: Vector3 = ra["from"]
		var start := ea + (fa - ea).normalized() * START_IN
		var pts := PackedVector3Array([start, fa])
		for i in range(1, span):
			pts.append(ring[posmod(int(ra["k"]) + i * dirk, m)])
		var fb: Vector3 = rb["from"]
		var eb: Vector3 = rb["end"]
		pts.append(fb)
		pts.append(eb)
		var cum := PackedFloat32Array([0.0])
		for i in range(1, pts.size()):
			cum.append(cum[i - 1] + _flat(pts[i] - pts[i - 1]).length())
		var L: float = cum[cum.size() - 1]
		var ta := _short(str(Catalog.RACES[a].get("town", "")))
		var tb := _short(str(Catalog.RACES[b].get("town", "")))
		out.append({"name": "%s %s–%s" % [dd[0], ta, tb], "auto": dd[0], "a": a, "b": b, "ta": ta, "tb": tb,
			"tier": dd[3], "ramp_a": ra, "ramp_b": rb, "dirk": dirk, "pts": pts, "cum": cum, "length": L,
			"start_xf": Transform3D(Basis.looking_at(_flat(fa - ea), Vector3.UP), start + Vector3(0, 0.5, 0)),
			"finish_d": L - FINISH_IN, "ring0": cum[1], "ring1": cum[cum.size() - 2]})
	return out


## Richtung auf dem Ring (+1: steigende Ringpunkte), in der die Stadt dieser Auffahrt rechts liegt
static func _right_dir(ring: Array, r: Dictionary) -> int:
	var m := ring.size()
	var k: int = r["k"]
	var tg: Vector3 = ring[(k + 1) % m] - ring[(k - 1 + m) % m]
	return 1 if (r["end"] - r["from"]).dot(tg.cross(Vector3.UP)) > 0.0 else -1


static func _short(town: String) -> String:
	return town.replace(" am Main", "")


static func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## Punkt der Route bei d Metern
static func point_at(df: Dictionary, d: float) -> Vector3:
	var pts: PackedVector3Array = df["pts"]
	var cum: PackedFloat32Array = df["cum"]
	d = clampf(d, 0.0, cum[cum.size() - 1])
	var i := cum.bsearch(d) - 1
	i = clampi(i, 0, pts.size() - 2)
	var sl: float = maxf(cum[i + 1] - cum[i], 0.001)
	return pts[i].lerp(pts[i + 1], clampf((d - cum[i]) / sl, 0.0, 1.0))


## Lage von p auf der Route nahe dem letzten Stand: Vector2(Meter, Abstand zur Linie)
static func project(df: Dictionary, p: Vector3, last: float, back := 80.0, ahead := 320.0) -> Vector2:
	var pts: PackedVector3Array = df["pts"]
	var cum: PackedFloat32Array = df["cum"]
	var best := Vector2(last, 1e9)
	var q := Vector2(p.x, p.z)
	for i in pts.size() - 1:
		if cum[i + 1] < last - back or cum[i] > last + ahead:
			continue
		var a := Vector2(pts[i].x, pts[i].z)
		var b := Vector2(pts[i + 1].x, pts[i + 1].z)
		var ab := b - a
		var k := clampf((q - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		var dist := q.distance_to(a + ab * k)
		if dist < best.y:
			best = Vector2(cum[i] + k * (cum[i + 1] - cum[i]), dist)
	return best


# --- Rennen ------------------------------------------------------------------------------------------------------

func start(df: Dictionary) -> void:
	def = df
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_bot = OS.get_cmdline_user_args().has("--hwbot")
	_log = OS.get_cmdline_user_args().has("--hwlog") or _bot
	var seg_a := _seg_with(def["ramp_a"])
	var seg_b := _seg_with(def["ramp_b"])
	if seg_a.is_empty() or seg_b.is_empty() or seg_a["state"] != "ready":
		print("HWRACE: Startstück nicht gebaut")
		w._highway_done()
		queue_free()
		return
	# Abschnitte: Auffahrt A hinunter, Ringstücke in Fahrtrichtung bis zum Stück mit der Ausfahrt B, Ausfahrt B
	var dirk: int = def["dirk"]
	var legs: Array = [{"e": seg_a, "kind": "ramp", "dir": -1.0, "ramp": def["ramp_a"]}]
	var e: Dictionary = seg_a
	for guard in 40:
		legs.append({"e": e, "kind": "main", "dir": float(dirk)})
		if e == seg_b:
			break
		e = w._seg_next(e, dirk > 0)
	legs.append({"e": seg_b, "kind": "ramp", "dir": 1.0, "ramp": def["ramp_b"]})
	var tr: Dictionary = seg_a["track"]
	var ra := Racer.find_ramp(tr, def["ramp_a"])
	if ra.is_empty():
		print("HWRACE: Auffahrt nicht gefunden")
		w._highway_done()
		queue_free()
		return
	var rl: float = ra["length"]
	var d0 := rl - START_IN
	# Spieler vorn rechts, Gegner daneben und dahinter (Auffahrt: vier Spuren, Blick zum Ring)
	var pxf: Transform3D = (seg_a["xf"] as Transform3D) * Track.xform_at(ra["curve"], d0, -2.25, true)
	pxf.basis = pxf.basis * Basis(Vector3.UP, PI)
	pxf.origin.y += 0.5
	w.player.place(pxf)
	w.player.track = tr
	w._set_active(seg_a)
	w.player.controls_enabled = false
	var grid := [[d0, 2.25], [d0 + 10.0, -2.25], [d0 + 10.0, 2.25]]
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var ids := _pick_cars(rng)
	# Gegner etwa so schnell wie dein Auto ohne Nitro (Leicht etwas langsamer, Schwer etwas schneller), dazu Gummiband
	var vmax: float = w.player.top_speed * PlayerCar.VMAX_K * [0.94, 1.0, 1.05][GameState.difficulty]
	for i in GEGNER:
		var r := Racer.new()
		r.process_mode = Node.PROCESS_MODE_PAUSABLE
		r.race = self
		r.legs = legs
		r.others = w.traffic
		r.player_path = -1
		r.on_end = r.route_end
		r.speed = 0.0
		r.base_speed = 0.0
		r.top = vmax * [0.98, 1.0, 1.03][i]
		_top.append(r.top)
		(tr["node"] as Node).add_child(r)
		r.enter_leg(0, false)
		r.progress = grid[i][0]
		r._lane_cur = float(grid[i][1])  # Querlage auf dem Weg der Auffahrt (wie beim Spieler, -2,25 = rechts)
		r.lane = r._lane_cur
		r.finish_d = 0.0
		r.setup_racer(ids[i], _cfg(ids[i], rng))
		r.place()
		w.traffic.append(r)
		racers.append(r)
	# Ziel: auf der Ausfahrt B, FINISH_IN vor ihrem Ende (wird beim Betreten des Abschnitts in Meter des Wegs gerechnet)
	for r in racers:
		r.set_meta("finish_in", FINISH_IN)
	_build_hud()
	_info.text = str(def["name"]).to_upper()
	w.minimap.set_route(_route2d())
	w.minimap.set_target(def["pts"][def["pts"].size() - 1], true)
	for i in racers.size():
		var pin: Node3D = w.hw_pins[i]
		pin.set_meta("off", false)
	print("HWRACE Start: %s, %.0f m, Gegner %s" % [def["name"], def["length"], ", ".join(ids)])


## Autobahnstück (Welt-Eintrag), an dem diese Rampe hängt
func _seg_with(ramp: Dictionary) -> Dictionary:
	for e in w.entries:
		if e["kind"] != "seg" or int(e.get("ring", 0)) != 0:
			continue
		for r in e["race"].get("ramps", []):
			if Vector2(r["end"].x - ramp["end"].x, r["end"].z - ramp["end"].z).length() < 1.0:
				return e
	return {}


## Drei Autos ungefähr so schnell wie deins (wie der Herausforderer), nicht deins
func _pick_cars(rng: RandomNumberGenerator) -> Array:
	var mine: float = Catalog.CARS[GameState.current_car]["top_speed"]
	var pool: Array = Catalog.CAR_ORDER.filter(func(id): return id != GameState.current_car \
		and absf(float(Catalog.CARS[id]["top_speed"]) / mine - 1.0) < 0.12 and not id in Catalog.EXOTICS)
	if pool.size() < GEGNER:
		pool = Catalog.CAR_ORDER.filter(func(id): return id != GameState.current_car and not id in Catalog.EXOTICS)
	var out := []
	while out.size() < GEGNER:
		var id: String = pool[rng.randi() % pool.size()]
		if not id in out or pool.size() < GEGNER:
			out.append(id)
	return out


func _cfg(id: String, rng: RandomNumberGenerator) -> Dictionary:
	var cfg := {}
	for cat in Catalog.PART_ORDER:
		if cat == "spur":
			continue
		cfg[cat] = rng.randi() % Catalog.PARTS[cat]["options"].size()
		while cat != "rimsize" and Catalog.PARTS[cat]["options"][cfg[cat]].get("hidden", false):
			cfg[cat] = (cfg[cat] + 5) % Catalog.PARTS[cat]["options"].size()
	cfg["spur"] = (int(cfg["paint"]) + int(cfg["rims"])) % Catalog.PARTS["spur"]["options"].size()
	cfg["rimsize"] = Builder.rival_rimsize(id, cfg)
	return cfg


func _route2d() -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in def["pts"]:
		out.append(Vector2(q.x, q.z))
	return out


func _build_hud() -> void:
	var root: Control = w.hud["root"]
	# oben links wie Platz und Zeit im Rennen (seit 2.48; bis 2.47 oben in der Mitte im Sichtfeld)
	_info = w._label(root, 12)
	_info.offset_left = 12.0
	_info.offset_top = 10.0
	_info.offset_right = 320.0
	_center = w._label(root, 32, HORIZONTAL_ALIGNMENT_CENTER)
	_center.anchor_left = 0.5
	_center.anchor_right = 0.5
	_center.anchor_top = 0.3
	_center.anchor_bottom = 0.3
	_center.offset_left = -400.0
	_center.offset_right = 400.0
	_center.add_theme_color_override("font_color", UI.TEXT)


func _process(dt: float) -> void:
	if state == 3 or w.player == null:
		return
	var player: Node3D = w.player
	match state:
		0:
			_count -= dt
			var n := int(ceil(_count - 1.0))
			_center.text = str(n) if n > 0 else tr("LOS!")
			if n != _beep and n >= 0:
				_beep = n
				var b := Sfx.play("beep" if n > 0 else "beep_go", -8.0 if n > 0 else -6.0)
				if b:
					b.bus = "Master"
			if _count <= 1.0:
				state = 1
				player.controls_enabled = true
				for r in racers:
					if is_instance_valid(r):
						r.holding = false
		1:
			t += dt
			if _count > 0.0:
				_count -= dt
				if _count <= 0.0:
					_center.text = ""
		2:
			_end_t -= dt
			if _end_t <= 0.0:
				_cleanup()
				return
	# Spieler auf der Route; weit daneben (Abkürzung, falsche Richtung): Hinweis, nach 25 s abgebrochen
	var pr := project(def, player.global_position, p_d)
	if pr.y < 60.0:
		p_d = maxf(p_d, pr.x) if pr.x > p_d - 40.0 else p_d
		_off_t = 0.0
	elif state == 1:
		_off_t += dt
		if _off_t > 4.0:
			_center.text = tr("ZURÜCK AUF DIE STRECKE")
		if _off_t > 25.0:
			abort(tr("RENNEN ABGEBROCHEN"))
			return
	if state == 1 and _off_t <= 4.0 and _count <= 0.0 and _center.text != "":
		_center.text = ""
	# Gegner: Lage auf der Route, Gummiband (vorn etwas langsamer, hinten etwas schneller), Punkte auf der Minikarte
	var ahead := 0
	for i in racers.size():
		var r = racers[i]
		var pin: Node3D = w.hw_pins[i]
		if not is_instance_valid(r) or not r.is_inside_tree():
			pin.set_meta("off", true)
			continue
		if not r.finished:
			var rp := project(def, r.global_position, r.route_d)
			if rp.y < 60.0:
				r.route_d = maxf(r.route_d, rp.x)
		var gap: float = r.route_d - p_d
		var k := 1.0
		if gap > 120.0:
			k = lerpf(1.0, 0.85, clampf((gap - 120.0) / 280.0, 0.0, 1.0))
		elif gap < -40.0:
			k = lerpf(1.0, 1.22, clampf((-gap - 40.0) / 260.0, 0.0, 1.0))
		r.top = _top[i] * k
		if r.finished or r.route_d > p_d:
			ahead += 1
		pin.global_position = r.global_position
	if state == 1:
		place = ahead + 1
		var left: float = maxf(float(def["finish_d"]) - p_d, 0.0)
		_info.text = "%s\n%s   %s   %s" % [str(def["name"]).to_upper(), tr("PLATZ %d / %d") % [place, racers.size() + 1],
			_fmt(t), tr("NOCH %.1f KM") % (left / 1000.0)]
		if p_d >= float(def["finish_d"]):
			_player_finished()
	if _bot and state == 1:
		_drive_bot()
	if state == 1 and t > 6.0 and OS.get_cmdline_user_args().has("--hwabort"):
		# Test: Esc-Menü öffnen und "Rennen aufgeben" drücken wie echt
		w._toggle_pause()
		for b in w.pause_panel.get_children():
			if b is Button and b.get_meta("key", "") == "Rennen aufgeben":
				print("HWRACE Test: Rennen aufgeben sichtbar=%s, Karte sichtbar=%s" % [b.visible,
					w.pause_panel.get_child(2).visible])
				b.emit_signal("pressed")
		return
	if _log:
		_log_t += dt
		if _log_t > 2.0:
			_log_t = 0.0
			var rs := []
			for r in racers:
				if is_instance_valid(r):
					rs.append("%.0f/%s/%d" % [r.route_d, "Ziel" if r.finished else str(r.leg), int(r.speed * 3.6)])
			print("HW t=%.1f platz=%d spieler=%.0f m (%d km/h) gegner=%s" % [t, place, p_d, int(absf(player.speed_fwd) * 3.6), str(rs)])


static func _fmt(s: float) -> String:
	return "%d:%05.2f" % [int(s / 60.0), fmod(s, 60.0)]


## Gegner im Ziel (highway_racer.gd)
func ai_finished(_r: Node) -> void:
	_finished_ai += 1


func _player_finished() -> void:
	state = 2
	_end_t = 5.0
	place = 1 + _finished_ai
	var name: String = def["name"]
	var first_win: bool = place == 1 and not name in GameState.highway_won
	var best := not GameState.best_times.has(name) or t < float(GameState.best_times[name])
	if best:
		GameState.best_times[name] = t
	if place == 1 and not name in GameState.highway_won:
		GameState.highway_won.append(name)
	var xp := Catalog.race_xp(int(def["tier"]), place, first_win)
	_center.add_theme_color_override("font_color", UI.GOLD if place == 1 else UI.TEXT)
	_center.text = tr("%d. PLATZ") % place + "\n" + _fmt(t) + ("   " + tr("NEUE BESTZEIT") if best else "")
	_info.text = str(def["name"]).to_upper()
	w._flash(tr("%d. PLATZ: %s") % [place, name.to_upper()], UI.GOLD if place == 1 else Color(0.85, 0.88, 0.95), xp, xp)
	Sfx.ui("install" if place == 1 else "go")
	GameState.save_game()
	if _bot:
		for act in ["accelerate", "brake", "steer_left", "steer_right"]:
			Input.action_release(act)
	print("HWRACE Ziel: %s Platz %d, %s, %d XP%s" % [name, place, _fmt(t), xp, " (Bestzeit)" if best else ""])


## Rennen abbrechen (Esc > Rennen aufgeben, zu weit weg von der Strecke)
func abort(msg: String) -> void:
	if state >= 2:
		return
	w._flash(msg, Color(1.0, 0.35, 0.3))
	print("HWRACE abgebrochen: ", msg)
	w.player.controls_enabled = true
	_cleanup()


func _cleanup() -> void:
	state = 3
	for i in racers.size():
		var r = racers[i]
		if is_instance_valid(r):
			w.traffic.erase(r)
			r.queue_free()
		(w.hw_pins[i] as Node3D).set_meta("off", true)
	racers.clear()
	if is_instance_valid(_info):
		_info.queue_free()
	if is_instance_valid(_center):
		_center.queue_free()
	w.minimap.set_route(PackedVector2Array())
	w._highway_done()
	queue_free()
	if OS.get_cmdline_user_args().has("--hwquit"):
		w.get_tree().quit()


## Test (--hwbot): fährt die Route selbst ab, rechts auf der Fahrbahn, bremst vor den Abbiegungen
func _drive_bot() -> void:
	var p: Node3D = w.player
	var v := absf(float(p.speed_fwd))
	var look := p_d + 14.0 + v * 0.45
	var q := point_at(def, look)
	var q2 := point_at(def, look + 6.0)
	var fd := _flat(q2 - q).normalized()
	var on_ring: bool = look > float(def["ring0"]) + 14.0 and look < float(def["ring1"]) - 14.0
	var tgt := q + fd.cross(Vector3.UP) * (6.0 if on_ring else 2.5)
	var side := (tgt - p.global_position).dot(p.global_basis.x)
	Input.action_release("steer_left")
	Input.action_release("steer_right")
	if side > 0.5:
		Input.action_press("steer_right", clampf(side / 5.0, 0.2, 1.0))
	elif side < -0.5:
		Input.action_press("steer_left", clampf(-side / 5.0, 0.2, 1.0))
	# vor einer Abbiegung (Richtung ändert sich stark) rechtzeitig auf gut 50 km/h bremsen
	var turn := -1.0
	var here := _flat(point_at(def, p_d + 3.0) - point_at(def, p_d)).normalized()
	for k in 16:
		var s := 10.0 + k * 20.0
		var a := _flat(point_at(def, p_d + s + 3.0) - point_at(def, p_d + s)).normalized()
		if absf(here.signed_angle_to(a, Vector3.UP)) > 0.7:
			turn = s
			break
	var brake := turn >= 0.0 and v > sqrt(14.0 * 14.0 + 2.0 * 6.0 * turn)
	if brake:
		Input.action_release("accelerate")
		Input.action_press("brake")
	else:
		Input.action_release("brake")
		Input.action_press("accelerate")
