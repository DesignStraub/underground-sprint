extends Node3D
## Werkzeug: Fahrphysik-Messlabor auf einer leeren Fläche (keine Wände, keine Strecke). Jedes Auto fährt feste
## Manöver mit simulierten Eingaben, ausgegeben werden Kennzahlen zum Vergleich mit dem Zielgefühl (NFSU).
##   Godot --headless --path . --fixed-fps 60 res://tools/handling_lab.tscn -- --cars=kaizen,mirai,kaze

const Catalog := preload("res://scripts/catalog.gd")
const PlayerCar := preload("res://scripts/player_car.gd")

const ACTIONS := ["accelerate", "brake", "steer_left", "steer_right", "handbrake", "nitro"]
const TURN_SPEEDS := [40.0, 80.0, 120.0, 160.0, 200.0]

var cars: Array = ["kaizen", "mirai", "ronin", "kaze"]
var car: CharacterBody3D
var _ci := 0
var _test := ""
var _queue: Array = []
var _t := 0.0
var _m := {}  # Messwerte des laufenden Manövers
var _res := {}  # Ergebnisse je Auto
var _last_yaw := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cars="):
			cars = Array(a.substr(7).split(","))
	_next_car()


func _next_car() -> void:
	if _ci >= cars.size():
		get_tree().quit()
		return
	_res = {}
	_queue = ["launch", "brake", "step", "brake_turn", "handbrake", "power"]
	for v in TURN_SPEEDS:
		_queue.append("turn_%d" % int(v))
	_next_test()


func _new_car(v_kmh: float) -> void:
	if car:
		car.queue_free()
	car = PlayerCar.new()
	add_child(car)
	var cfg := {}
	for cat in Catalog.PART_ORDER:
		cfg[cat] = 0
	car.setup(cars[_ci], cfg)
	car.place(Transform3D.IDENTITY)
	car.controls_enabled = true
	car.velocity = Vector3(0, 0, -v_kmh / 3.6)
	car.nitro = 0.0
	_last_yaw = 0.0


func _next_test() -> void:
	for a in ACTIONS:
		Input.action_release(a)
	if _queue.is_empty():
		_report()
		_ci += 1
		_next_car()
		return
	_test = _queue.pop_front()
	_t = 0.0
	_m = {"slip": 0.0, "yaw_hist": [], "heading": 0.0}
	var v0 := 0.0
	match _test:
		"brake":
			v0 = 150.0
		"step":
			v0 = 120.0
		"brake_turn":
			v0 = 130.0
		"handbrake":
			v0 = 80.0
		"power":
			v0 = 45.0
		_:
			if _test.begins_with("turn_"):
				v0 = float(_test.substr(5))
	_new_car(v0)


## Gas so dosieren, dass das Tempo gehalten wird
func _hold(v_kmh: float) -> void:
	var err: float = v_kmh / 3.6 - car.speed_fwd
	Input.action_press("accelerate", clampf(0.35 + err * 0.4, 0.0, 1.0))
	if err < -3.0:
		Input.action_press("brake", 0.3)
	else:
		Input.action_release("brake")


func _physics_process(dt: float) -> void:
	if car == null or _test == "":
		return
	_t += dt
	var yaw := car.global_rotation.y
	var yr := wrapf(yaw - _last_yaw, -PI, PI) / dt
	_last_yaw = yaw
	_m["heading"] += absf(wrapf(yr * dt, -PI, PI))
	# Schräglauf direkt aus Fahrtrichtung und Fahrzeugachse (auch kleine Winkel, die nicht als Drift zählen)
	var hv := Vector3(car.velocity.x, 0, car.velocity.z)
	var sl := 0.0
	if hv.length() > 3.0:
		sl = rad_to_deg(absf((-car.global_basis.z).signed_angle_to(hv, Vector3.UP)))
		if sl > 90.0:
			sl = 180.0 - sl
	_m["slip_now"] = sl
	_m["slip"] = maxf(_m["slip"], sl)
	if OS.get_cmdline_user_args().has("--verbose") and _test == "handbrake" and fmod(_t, 0.1) < dt:
		print("  hb t=%.1f v=%.1f gier=%.2f lenk=%.2f halt=%.2f schräg=%.0f" % [_t, car.speed_fwd, yr, car.steer, car._slip_hold, sl])
	var kmh: float = car.speed_fwd * 3.6
	if _t < 0.05:
		return  # erst nach dem ersten Physikschritt des Autos messen
	if OS.get_cmdline_user_args().has("--verbose") and _test == "launch" and fmod(_t, 1.0) < dt:
		print("  t=%.0f v=%d gang=%d rpm=%d schalt=%.2f y=%.2f" % [_t, int(kmh), car.gear, int(car.rpm), car._shift_timer, car.position.y])
	match _test:
		"launch":
			Input.action_press("accelerate")
			var pos: float = -car.global_position.z
			for mark in [[100.0, "0-100"], [160.0, "0-160"], [200.0, "0-200"]]:
				if kmh >= mark[0] and not _m.has(mark[1]):
					_m[mark[1]] = _t
			for mark in [[402.0, "402m"], [804.0, "804m"]]:
				if pos >= mark[0] and not _m.has(mark[1]):
					_m[mark[1]] = _t
					_m[mark[1] + "_kmh"] = kmh
			if _t > 40.0:
				_res["launch"] = "0-100 %.1fs  0-160 %.1fs  0-200 %s  402m %.1fs (%d km/h)  804m %.1fs  Spitze %d km/h" % [
					_m.get("0-100", -1.0), _m.get("0-160", -1.0), ("%.1fs" % _m["0-200"]) if _m.has("0-200") else "-",
					_m.get("402m", -1.0), int(_m.get("402m_kmh", 0.0)), _m.get("804m", -1.0), int(kmh)]
				_next_test()
		"brake":
			Input.action_press("brake")
			if not _m.has("z0"):
				_m["z0"] = car.global_position.z
			if kmh < 1.0:
				_res["brake"] = "150-0 in %.2fs, %.0f m (%.1f g)" % [_t, absf(car.global_position.z - _m["z0"]), 150.0 / 3.6 / _t / 9.81]
				_next_test()
		"step":
			_hold(120.0)
			if _t > 0.5:
				Input.action_press("steer_right")
			var hist: Array = _m["yaw_hist"]
			hist.append(absf(yr))
			if _t > 3.0:
				var final_yr: float = hist[-1]
				var t63 := -1.0
				for i in hist.size():
					if i * dt > 0.5 and hist[i] >= final_yr * 0.63:
						t63 = i * dt - 0.5
						break
				_res["step"] = "Lenkimpuls 120: 63%% Drehrate nach %.2fs, Drehrate %.2f rad/s, Schräglauf max %.1f°" % [t63, final_yr, _m["slip"]]
				_next_test()
		"brake_turn":
			if _t < 1.2:
				Input.action_press("brake")
				Input.action_press("steer_right")
			else:
				Input.action_release("brake")
				Input.action_release("steer_right")
				Input.action_press("accelerate", 0.5)
			if _t > 1.2 and not _m.has("bt"):
				_m["bt"] = "nach 1,2s: %d km/h, Drehung %.0f°" % [int(kmh), rad_to_deg(_m["heading"])]
			if _t > 3.0:
				_res["brake_turn"] = "Bremsen+Lenken 130: %s, Schräglauf max %.1f°, danach %.1f°" % [_m["bt"], _m["slip"], _m["slip_now"]]
				_next_test()
		"handbrake":
			if _t < 0.8:
				Input.action_press("handbrake")
				Input.action_press("steer_right")
				Input.action_press("accelerate", 0.4)
			else:
				Input.action_release("handbrake")
				Input.action_release("steer_right")
				Input.action_press("accelerate", 0.7)
				if not _m.has("hb_end"):
					_m["hb_end"] = rad_to_deg(_m["heading"])
				if _m["slip_now"] < 3.0 and not _m.has("rec"):
					_m["rec"] = _t - 0.8
			if _t > 3.5:
				_res["handbrake"] = "Handbremse 80: Drehung %.0f° (nach 0,8s %.0f°), Schräglauf max %.1f°, gefangen nach %.2fs, %d km/h" % [
					rad_to_deg(_m["heading"]), _m["hb_end"], _m["slip"], _m.get("rec", -1.0), int(kmh)]
				_next_test()
		"power":
			Input.action_press("accelerate")
			Input.action_press("steer_right")
			if _t > 2.5:
				_res["power"] = "Vollgas+Lenken ab 45: Schräglauf max %.1f°, Drehung %.0f°, %d km/h" % [_m["slip"], rad_to_deg(_m["heading"]), int(kmh)]
				_next_test()
		_:
			var v := float(_test.substr(5))
			_hold(v)
			if _t > 0.3:
				Input.action_press("steer_right")
			if _t > 2.5:
				var hist: Array = _m["yaw_hist"]
				hist.append(absf(yr))
			if _t > 3.5:
				var hist: Array = _m["yaw_hist"]
				var avg := 0.0
				for h in hist:
					avg += h
				avg /= maxf(hist.size(), 1)
				var vs: float = car.velocity.length()
				_res[_test] = "Kurve %3d: Radius %5.1f m, quer %.2f g, Schräglauf %.1f° (max %.1f°), Tempo jetzt %d" % [
					int(v), vs / maxf(avg, 0.001), vs * avg / 9.81, _m["slip_now"], _m["slip"], int(kmh)]
				_next_test()


func _report() -> void:
	var spec: Dictionary = Catalog.CARS[cars[_ci]]
	print("=== %s (accel %.1f, top %.0f, grip %.0f, steer %.2f, drift %.2f)" % [spec["name"], spec["accel"], spec["top_speed"],
		spec["grip"], spec["steer"], spec.get("drift", 0.3)])
	for k in ["launch", "brake", "step", "brake_turn", "handbrake", "power"]:
		print("  ", _res.get(k, "?"))
	for v in TURN_SPEEDS:
		print("  ", _res.get("turn_%d" % int(v), "?"))
