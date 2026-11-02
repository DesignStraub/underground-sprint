extends CharacterBody3D
## Arcade-Fahrphysik mit Heckantrieb: Gänge mit Drehmomentkurve, Grip, der die Fahrtrichtung zur Fahrzeugachse zieht
## (ohne Tempo zu verschenken), mit Handbremse oder viel Gas in engen Kurven kommt das Heck; der Rutschzustand ist
## stufenlos (kein Umschalten zwischen Grip und Drift). Im Drift dreht das Auto um die Vorderachse (Heck schwenkt).
## Wände wie in NFSU: man schrammt entlang und wird parallel gestellt, Verkehr bestraft deutlich härter.
## Handbremse für Drifts, Nitro, Sprünge über Rampen (in der Luft keine Lenkung, Nitro schiebt weiter).
## Kamera: Verfolger (Standard), Stoßstange, Motorhaube – Taste C schaltet durch.
## Drag-Modus wie in NFSU: gelenkt wird automatisch, links/rechts wechselt die Spur, geschaltet wird von Hand
## (im grünen Bereich perfekt), zu lange im Begrenzer überhitzt der Motor, ein Crash mit Verkehr ist Totalschaden.

const Catalog := preload("res://scripts/catalog.gd")
const Builder := preload("res://scripts/car_builder.gd")
const EngineAudio := preload("res://scripts/engine_audio.gd")
const Track := preload("res://scripts/track_builder.gd")
const Knockable := preload("res://scripts/knockable.gd")

## Ende von Gang 1..5 als Anteil der Höchstgeschwindigkeit; der 6. reicht bis über Topspeed
const GEARS := [0.0, 0.16, 0.31, 0.47, 0.63, 0.81, 1.3]
const SHIFT_RPM := 7400.0
const TOP_RPM := 6600.0  # Drehzahl bei Höchstgeschwindigkeit im 6. Gang
const GEAR_PULL := [0.0, 1.0, 0.86, 0.74, 0.63, 0.54, 0.46]
const GRAVITY := 30.0
const MAX_LAUNCH_VY := 10.0  # kurze, knackige Sprünge statt Weitflug
const MIN_RADIUS := 5.2  # kleinster Wendekreis (Radius) bei voll eingeschlagener Lenkung
const BRAKE := 22.0  # m/s² Vollbremsung (gut 2 g: kräftig, aber nicht wie gegen eine Wand)
const DRAG_LIMIT := 8000.0  # Begrenzer im Drag
const PERFECT_SHIFT := Vector2(7100.0, 7650.0)  # grüner Bereich zum Hochschalten
const GOOD_SHIFT := 6200.0
const CAM_NAMES := ["Verfolger", "Stoßstange", "Motorhaube"]

var controls_enabled := false
var finished := false
var cam_mode := 0

var model: Node3D
var cam: Camera3D
var audio: AudioStreamPlayer
var track: Dictionary

var accel := 11.0
var top_speed := 58.0
var grip_k := 8.0
var steer_rate := 2.2
var lat_acc := 28.0  # m/s²: so stark kann das Auto bei Tempo höchstens ums Eck (begrenzt die Drehrate)
var nitro_power := 1.0
var nitro_cap := 1.0

var nitro := 1.0
var nitro_on := false
var speed_fwd := 0.0
var speed_lat := 0.0
var steer := 0.0
var gear := 1
var rpm := 900.0
var drifting := false
var drift_angle := 0.0  # Grad zwischen Fahrtrichtung und Fahrzeugachse
var drift_k := 0.3  # 0..1: wie willig das Auto quer geht (aus dem Katalog)
var crashes := 0  # zählt harte Einschläge (Drift-Kette geht verloren)
var wall_hits := 0  # zählt jede Berührung mit Wand/Bande (Drift-Modus: Kette weg)
## Drift-Modus (Drift-Events): ist das Auto erst quer, hält Gas das Heck draußen, Lenken steuert den Winkel,
## die Fahrtrichtung folgt dem Auto nur langsam. Ohne Gas richtet es sich wieder auf.
var drift_mode := false
## Drag-Modus: Spur 0..3, Motortemperatur 0..1, Ergebnis des letzten Schaltvorgangs (für das HUD), Ausfälle
var drag_mode := false
var drag_lane := 2
var engine_heat := 0.0
var shift_result := ""
var blown := false
var totaled := false
var _limiter := false
var _nos_empty := false
var _sliding := false
var _slide_out := 0.0
var _thr_s := 0.0  # Gas weich nachgeführt (kein Sprung von 0 auf volle Kraft)
var _slip_hold := 0.0  # 0..1: wie sehr das Heck gerade gelöst ist (Handbremse baut auf, Gas hält, klingt weich ab)
var _cam_drift := 0.0  # wie weit die Kamera im Drift in Fahrtrichtung schaut (geglättet)
var _shake_t := 0.0
var _wall_cool := 0.0
var debug_hits := false  # nur für Tests (--handling, --trace): merkt sich, woran das Auto angeeckt ist
var last_hit := ""
var _collider_name := ""
## Rundkurs: abgeschlossene Runden und Gesamtfortschritt (Runden * Länge + Position)
var lap := 0
var total := 0.0
## Position auf der Strecke: Rennfortschritt (Meter Hauptstraße), Querlage, aktueller Weg
var progress := 0.0
var lateral := 0.0
var path_id := 0
var loc := {}
var stun := 0.0
var airborne := false
var air_time := 0.0
var last_air := 0.0  # Dauer des letzten Sprungs (für das HUD)
var landings := 0
var vy := 0.0
var sinking := 0.0

var _shift_timer := 0.0
var _shake := 0.0
var _fov := 72.0
var _length := 4.0
var _spec: Dictionary
var _spin := 0.0
var _on_walk := false
var _crash_cooldown := 0.0
var _ground_vy := 0.0
var _curb_y := 0.0  # Bordstein-Anteil der Höhe (weich), die Fahrbahnhöhe selbst gilt sofort
var _base_y := 0.0
var _base_vy := 0.0
var _base_ok := false
var _slope_pitch := 0.0
var _yaw_prev := 0.0
var _slope_roll := 0.0
var _cam_yaw := 0.0
var _cam_pos := Vector3.ZERO
var _cam_init := false
var _respawn_xf := Transform3D.IDENTITY
var _last_prog := 0.0


func setup(car_id: String, cfg: Dictionary) -> void:
	_spec = Catalog.CARS[car_id]
	var nos := Catalog.part_of(cfg, "nitro")
	# Tuning wirkt wirklich: Motor und Turbo auf Schub und Endtempo, Fahrwerk und Reifen auf Grip und Lenkung
	var st := Catalog.stats(car_id, cfg)
	accel = st["accel"]
	top_speed = st["top"]
	grip_k = st["grip"] * 0.6
	steer_rate = st["steer"]
	lat_acc = 14.0 + st["grip"] * 0.42  # 2,3–2,7 g ab Werk: griffig wie NFSU, aber enge Ecken wollen angebremst werden
	drift_k = st["drift"]
	nitro_power = nos["power"]
	nitro_cap = nos["capacity"]

	model = Builder.build(car_id, cfg)
	add_child(model)
	_length = model.get_meta("length")
	# Grundriss mit runden Ecken (vorn stärker): an Kanten, Pfosten und Inselspitzen gleitet das Auto ab,
	# statt frontal hängen zu bleiben
	var col := CollisionShape3D.new()
	var w: float = model.get_meta("width") / 2.0
	var l := _length / 2.0
	var pts := PackedVector3Array()
	for y in [-0.6, 0.6]:
		for corner in [[Vector2(w, -l), 0.62, Vector2(-1, 1)], [Vector2(-w, -l), 0.62, Vector2(1, 1)],
				[Vector2(w, l), 0.35, Vector2(-1, -1)], [Vector2(-w, l), 0.35, Vector2(1, -1)]]:
			var r: float = corner[1]
			var c: Vector2 = corner[0] + corner[2] * r  # Mittelpunkt der Rundung
			var out: Vector2 = -corner[2]
			for k in 7:
				var a := PI / 2.0 * k / 6.0
				pts.append(Vector3(c.x + out.x * r * sin(a), y, c.y + out.y * r * cos(a)))
	var hull := ConvexPolygonShape3D.new()
	hull.points = pts
	col.shape = hull
	var shape := BoxShape3D.new()
	shape.size = Vector3(w * 2.0, 1.2, _length)
	col.position.y = 0.7
	add_child(col)
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	collision_layer = 2
	collision_mask = 1 | 2
	# Fühler für Laternen, Mülltonnen & Co.
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = Knockable.LAYER
	area.monitorable = false
	var acs := CollisionShape3D.new()
	var abs_shape := BoxShape3D.new()
	abs_shape.size = shape.size + Vector3(0.2, 0.0, 0.3)
	acs.shape = abs_shape
	acs.position.y = 0.7
	area.add_child(acs)
	area.body_entered.connect(_on_prop_hit)
	add_child(area)

	cam = Camera3D.new()
	cam.far = GameState.view_distance()  # dahinter verschluckt ohnehin der Nebel fast alles
	cam.near = 0.05
	add_child(cam)
	cam.make_current()
	_apply_cam()

	audio = EngineAudio.new()
	var snd: Dictionary = _spec["sound"].duplicate()
	var turbo_stage := int(cfg.get("turbo", 0))
	if turbo_stage > 0:
		snd["turbo"] = maxf(snd.get("turbo", 0.0), 0.35 + 0.2 * turbo_stage)  # nachgerüsteter Lader zischt hörbar
	audio.configure(snd)
	add_child(audio)


func _apply_cam() -> void:
	_cam_init = false
	if cam_mode == 0:
		cam.top_level = true
		return
	cam.top_level = false
	cam.transform = Transform3D.IDENTITY
	if cam_mode == 1:
		cam.position = Vector3(0, 0.5, -_length / 2 - 0.05)
		cam.rotation_degrees.x = -1.0
	else:
		cam.position = model.get_meta("eye")
		cam.rotation_degrees.x = -5.0


func toggle_camera() -> void:
	cam_mode = (cam_mode + 1) % CAM_NAMES.size()
	_apply_cam()


func _on_prop_hit(body: Node) -> void:
	if body.has_method("knock") and not body.knocked:
		body.knock(velocity)
		velocity *= 1.0 - (1.0 - body.slowdown) * 0.65  # kostet Tempo, aber man bleibt nicht hängen
		_shake = minf(_shake + 0.12, 1.0)
		audio.crash(0.15 + body.mass / 200.0)
		if body.has_meta("clang"):
			Sfx.play("clang", -6.0, randf_range(0.85, 1.1))


func _physics_process(dt: float) -> void:
	var thr := Input.get_action_strength("accelerate")
	var brk := Input.get_action_strength("brake")
	var steer_in := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	var hb := Input.is_action_pressed("handbrake")
	var want_nitro := Input.is_action_pressed("nitro")
	stun = maxf(stun - dt, 0.0)
	_crash_cooldown = maxf(_crash_cooldown - dt, 0.0)
	_wall_cool = maxf(_wall_cool - dt, 0.0)
	if sinking > 0.0:
		_update_sinking(dt)
		return
	if stun > 0.0:
		# Nach einem Crash kurz keine Kontrolle
		thr = 0.0
		steer_in = 0.0
		want_nitro = false
	if not controls_enabled:
		# Vor dem Start darf man trotzdem am Gas spielen (Drehzahl hochjagen)
		if not finished:
			# Weicher Begrenzer: pendelt sanft knapp unter der Schaltdrehzahl
			var lim := SHIFT_RPM - 300.0 + sin(Time.get_ticks_msec() * 0.025) * 150.0
			rpm = move_toward(rpm, 900.0 + thr * (lim - 900.0), dt * (7000.0 if thr > 0.1 else 4000.0))
		thr = 0.0
		# nach dem Ziel bremsen bis zum Stand (nicht weiter: Bremse im Stand wäre Rückwärtsgang)
		brk = 1.0 if finished and speed_fwd > 0.3 else 0.0
		steer_in = 0.0
		hb = false
		want_nitro = false

	if drag_mode:
		# Drag: Spur per Tipp wechseln, gelenkt wird automatisch; geschaltet wird von Hand
		hb = false
		if controls_enabled and not blown:
			if Input.is_action_just_pressed("steer_left"):
				drag_lane = maxi(drag_lane - 1, 0)
			elif Input.is_action_just_pressed("steer_right"):
				drag_lane = mini(drag_lane + 1, 3)
			if Input.is_action_just_pressed("shift_up") and gear < 6:
				_drag_shift(1)
			elif Input.is_action_just_pressed("shift_down") and gear > 1:
				_drag_shift(-1)
		steer_in = _drag_steer() if controls_enabled or finished else 0.0
		if blown:
			thr = 0.0
			want_nitro = false

	var fwd := -global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0, fwd.x)
	var hvel := Vector3(velocity.x, 0, velocity.z)
	speed_fwd = hvel.dot(fwd)
	speed_lat = hvel.dot(right)
	var spd := absf(speed_fwd)

	# --- Gänge & Drehzahl. Hochschalten am Gangende, Zurückschalten erst deutlich darunter (Hysterese): sonst pendelt
	# das Getriebe an einer Grenze hin und her, jeder Schaltvorgang nimmt kurz den Vortrieb und das Auto kommt nicht weiter.
	var ratio := spd / top_speed
	if drag_mode:
		pass  # Handschaltung (oben)
	elif gear < 6 and ratio > GEARS[gear]:
		gear += 1
		_shift_timer = 0.16
	elif gear > 1 and ratio < GEARS[gear - 1] * 0.88:
		gear -= 1
	_shift_timer = maxf(_shift_timer - dt, 0.0)
	if controls_enabled or finished:
		var target_rpm: float
		if airborne:
			# Räder in der Luft: Motor dreht frei hoch
			target_rpm = 1500.0 + thr * 5800.0
		else:
			# Drehzahl proportional zur Geschwindigkeit im Gang; im 6. Gang liegt Topspeed bei TOP_RPM
			var per_ratio: float = SHIFT_RPM / GEARS[gear] if gear < 6 else TOP_RPM
			target_rpm = clampf(maxf(900.0 + thr * 600.0, ratio * per_ratio), 900.0, SHIFT_RPM + 300.0)
			if drag_mode:
				# ohne Hochschalten dreht der Motor bis in den Begrenzer (dort kein Vortrieb, er wird heiß)
				var raw := maxf(900.0 + thr * 600.0, ratio * per_ratio)
				if gear == 6:
					raw = minf(raw, PERFECT_SHIFT.y - 100.0)  # letzter Gang: Nitro darf über Topspeed schieben, ohne Begrenzer
				_limiter = raw >= DRAG_LIMIT - 40.0 and thr > 0.1
				target_rpm = clampf(raw, 900.0, DRAG_LIMIT)
				if _limiter:
					target_rpm = DRAG_LIMIT - absf(sin(Time.get_ticks_msec() * 0.05)) * 350.0
			if speed_fwd < -0.5:
				target_rpm = 900.0 + spd * 300.0
			if hb and thr > 0.5 and spd < 25.0:
				target_rpm = maxf(target_rpm, 6500.0)
		rpm = move_toward(rpm, target_rpm, dt * (9000.0 if airborne else 20000.0))

	# --- Nitro (funktioniert auch in der Luft). Leer ist leer: erst nach dem Loslassen geht es wieder
	# (sonst hält das minimale Nachladen den Schub bei gedrückter Taste ewig am Leben)
	if not want_nitro:
		_nos_empty = false
	nitro_on = want_nitro and nitro > 0.0 and speed_fwd > 4.0 and not _nos_empty
	if nitro_on:
		nitro = maxf(nitro - dt * 0.3 / nitro_cap, 0.0)
		if nitro <= 0.0:
			_nos_empty = true
	else:
		nitro = minf(nitro + dt * (0.015 + (0.13 if drifting else 0.0)) / nitro_cap, 1.0)

	# --- Längsbeschleunigung (Drehmoment über die Drehzahl, unten herum Traktionsgrenze)
	_thr_s = move_toward(_thr_s, thr, dt * (4.0 if thr > _thr_s else 8.0))
	var tq := 0.78 + 0.22 * sin(clampf((rpm - 1000.0) / 6200.0, 0.0, 1.0) * PI)
	if drag_mode:
		# Drag: Drehmoment kommt erst oben (zu früh schalten kostet richtig), im Begrenzer nichts
		tq = 0.0 if _limiter else 0.55 + 0.45 * smoothstep(2500.0, 6800.0, rpm)
		if controls_enabled and not blown:
			var hot := rpm > PERFECT_SHIFT.y + 100.0 and gear < 6
			engine_heat = clampf(engine_heat + dt * ((0.42 if _limiter else 0.16) if hot else -0.12), 0.0, 1.0)
			if engine_heat >= 1.0:
				blown = true
				Sfx.play("clang", 0.0, 0.6)
				audio.crash(0.8)
	var a := 0.0
	var eff_top := top_speed * (1.0 + 0.22 * nitro_power if nitro_on else 1.0)
	var drag_k := accel * GEAR_PULL[6] / (top_speed * top_speed)
	if nitro_on:
		a += 8.5 * nitro_power
	if airborne:
		a -= drag_k * 0.5 * speed_fwd * absf(speed_fwd)
	else:
		if _shift_timer <= 0.0:
			a += accel * _thr_s * GEAR_PULL[gear] * tq
			if spd < 6.0:
				a *= 0.7 + 0.3 * spd / 6.0  # Räder drehen beim Anfahren etwas durch
		a -= drag_k * speed_fwd * absf(speed_fwd)
		if thr < 0.05:
			a -= signf(speed_fwd) * 1.6  # Motorbremse
		if brk > 0.0:
			if speed_fwd > 1.0:
				a -= BRAKE * brk
			elif speed_fwd > -14.0:
				a -= 9.0 * brk
		if hb:
			a -= signf(speed_fwd) * 4.0
		# Bergauf etwas zäher, bergab etwas Schwung (abgeschwächt, damit es nicht frustriert)
		a -= 6.0 * sin(_slope_pitch)
	if speed_fwd > eff_top:
		a = minf(a, -6.0)
	speed_fwd += a * dt
	if not airborne and absf(speed_fwd) < 0.3 and thr < 0.05 and brk < 0.05:
		speed_fwd = 0.0

	# --- Lenkung (in der Luft wirkungslos). Bei Tempo schlägt das Lenkrad etwas langsamer ein (Tastatur).
	var sf0 := clampf(spd / top_speed, 0.0, 1.0)
	var steer_speed := lerpf(6.0, 3.0, sf0) if absf(steer_in) > 0.01 else lerpf(8.0, 5.0, sf0)
	if steer_in * steer < 0.0:
		steer_speed = lerpf(9.0, 6.0, sf0)  # Gegenlenken geht schneller als Einlenken
	steer = move_toward(steer, steer_in, dt * steer_speed)
	var low_speed := clampf(spd / 2.0, 0.0, 1.0)
	# Drehrate: langsam begrenzt durch den Wendekreis (Lenkgeometrie), bei Tempo durch die Querbeschleunigung
	var lat_eff := lat_acc * (1.0 - 0.12 * sf0)  # bei Topspeed etwas weniger wendig
	var high_speed := minf(1.0, minf(lat_eff / maxf(spd, 0.1), spd / MIN_RADIUS) / steer_rate)
	var l2 := 0.0
	if drift_mode and _sliding and not airborne:
		_slip_hold = 0.6
		l2 = _slide_physics(dt, fwd, right, thr, hb, a, eff_top, low_speed)
	else:
		# Heckantrieb: Vollgas bei engem Einschlag und mittlerem Tempo lässt das Heck etwas kommen (stufenlos)
		var po := 0.0
		if not airborne:
			po = _thr_s * smoothstep(0.35, 0.9, absf(steer)) * smoothstep(6.0, 12.0, spd) \
				* (1.0 - smoothstep(top_speed * 0.4, top_speed * 0.7, spd))
		if hb and spd > 8.0 and not airborne:
			_slip_hold = move_toward(_slip_hold, 1.0, dt * 5.0)
		elif brk > 0.3 and absf(steer) > 0.5 and spd > 18.0 and not airborne:
			# Anbremsen in die Kurve: das Heck wird leicht und kommt ein Stück (wie in NFSU reinbremsen und rutschen)
			_slip_hold = move_toward(_slip_hold, 0.35 * brk * absf(steer), dt * 3.0)
		else:
			# Gas hält den Drift (Driftautos länger), ohne Gas fängt sich das Auto
			_slip_hold = move_toward(_slip_hold, 0.0, dt * lerpf(2.2, 0.9, drift_k) * (1.0 - 0.55 * _thr_s))
		var yaw := 0.0
		if not airborne:
			yaw = -steer * steer_rate * low_speed * high_speed * signf(speed_fwd + 0.001)
			yaw *= 1.0 + (0.12 + 0.2 * drift_k) * _slip_hold + 0.1 * po + (0.4 if hb else 0.0)
			if drift_mode:
				# Drift-Modus: mit Gas und voll eingelenkt bricht das Heck aus
				yaw *= 1.0 + 0.25 * smoothstep(0.5, 1.0, absf(steer)) * _thr_s * smoothstep(10.0, 16.0, spd)
		_spin = move_toward(_spin, 0.0, dt * 2.0)
		_rotate_front((yaw + _spin) * dt, 0.6 * _slip_hold)

		# Neue Fahrzeugachse; Geschwindigkeit bleibt zunächst in Weltrichtung -> Querschlupf entsteht
		var new_fwd := -global_basis.z
		new_fwd.y = 0
		new_fwd = new_fwd.normalized()
		var new_right := Vector3(-new_fwd.z, 0, new_fwd.x)
		var v := fwd * speed_fwd + right * speed_lat
		var f2 := v.dot(new_fwd)
		l2 = v.dot(new_right)

		# --- Grip: Querbewegung abbauen. Die Fahrtrichtung dreht zur Fahrzeugachse, der Betrag bleibt (Kurven
		# schenken kein Tempo); nur das Rutschen radiert je nach Winkel etwas ab.
		if not airborne:
			var gk := grip_k * lerpf(1.0, lerpf(0.35, 0.2, drift_k), _slip_hold) * (1.0 - 0.3 * po)
			if hb:
				gk *= lerpf(0.45, 0.35, drift_k)
			if drift_mode:
				gk *= 0.4  # im Drift-Modus bricht das Heck leichter aus
			if stun > 0.0:
				gk *= 0.25
			var l_new := l2 * exp(-gk * dt)
			# Betrag der Geschwindigkeit bleibt (nur das Rutschen radiert ab), die Richtung dreht zur Fahrzeugachse
			var vs := sqrt(f2 * f2 + l2 * l2)
			var sin_b := absf(l_new) / maxf(vs, 1.0)
			vs = maxf(vs - lerpf(6.0, 3.5, drift_k) * sin_b * dt, 0.0)
			var f_new := signf(f2) * sqrt(maxf(vs * vs - l_new * l_new, 0.0))
			f2 = minf(f_new, maxf(eff_top, speed_fwd))
			l2 = l_new
			var ang := rad_to_deg(atan2(absf(l2), maxf(absf(f2), 0.1)))
			drifting = spd > 10.0 and ang > (6.0 if drifting else 10.0)  # Schwelle mit Puffer: kein Flackern
			drift_angle = ang if drifting else 0.0
			if drift_mode and spd > 10.0 and ang > 9.0 and f2 > 0.0:
				_sliding = true
				_slide_out = 0.0
		else:
			drifting = false
			drift_angle = 0.0
		velocity = new_fwd * f2 + new_right * l2
		velocity.y = 0.0
	var pre := velocity
	move_and_slide()
	_handle_collisions(pre)
	_update_vertical(dt)

	# --- Optik, Kamera, Sound
	var sf := clampf(spd / top_speed, 0.0, 1.0)
	# Gewichtsverlagerung: Nase taucht beim Bremsen ein, hebt sich beim Beschleunigen; Wanken nach der echten
	# Querbeschleunigung (Gierrate * Tempo) nach außen, im Rutschen zusätzlich zur Rutschseite
	var pitch := clampf(a * 0.0028, -0.05, 0.035)
	if airborne:
		pitch = clampf(atan2(vy, maxf(spd, 1.0)) * 0.8, -0.35, 0.3)
	var yaw_now := wrapf(global_rotation.y - _yaw_prev, -PI, PI) / maxf(dt, 0.0001)
	_yaw_prev = global_rotation.y
	var roll := clampf(-yaw_now * spd / 9.81 * 0.022, -0.065, 0.065) - clampf(l2 * 0.003, -0.035, 0.035)
	Builder.animate(model, speed_fwd, steer, 0.0 if airborne else roll, pitch, nitro_on, dt)
	# Ganzes Auto in die Steigung neigen (Trog, Bergstraße)
	if not airborne:
		model.rotation.x = lerp_angle(model.rotation.x, _slope_pitch, 1.0 - exp(-dt * 12.0))
		model.rotation.z = lerp_angle(model.rotation.z, _slope_roll, 1.0 - exp(-dt * 12.0))
	else:
		model.rotation.z = lerp_angle(model.rotation.z, 0.0, 1.0 - exp(-dt * 3.0))
	_update_camera(dt, sf)

	audio.rpm = rpm
	audio.throttle = 1.0 if nitro_on else (Input.get_action_strength("accelerate") if not finished else 0.0)
	audio.nitro = nitro_on
	audio.slip = clampf((absf(l2) - 3.0) / 10.0, 0.0, 1.0) if spd > 5.0 and not airborne else 0.0
	audio.speed = spd


## Drag: Schaltvorgang bewerten. Im grünen Bereich kaum Zugkraftunterbrechung und ein kleiner Schub.
func _drag_shift(dir: int) -> void:
	if dir < 0:
		gear -= 1
		_shift_timer = 0.12
		shift_result = "down"
		return
	if rpm >= PERFECT_SHIFT.x and rpm <= PERFECT_SHIFT.y:
		shift_result = "perfect"
		_shift_timer = 0.04
		velocity += -global_basis.z * 1.6
	elif rpm >= GOOD_SHIFT:
		shift_result = "good"
		_shift_timer = 0.14
	else:
		shift_result = "early"
		_shift_timer = 0.2
	gear += 1


## Drag: auf die gewählte Spur zielen (Blickpunkt vor dem Auto), Lenkung daraus
func _drag_steer() -> float:
	if loc.is_empty():
		return 0.0
	var c: Curve3D = loc["path"]["curve"]
	var d: float = loc["d"] + 7.0 + absf(speed_fwd) * 0.32
	var f := Track.frame_at(c, d)
	var tgt: Vector3 = f["pos"] + f["right"] * Track.lane_lat(track, d, Track.LANES[drag_lane])
	var to := tgt - global_position
	to.y = 0.0
	var fw := -global_basis.z
	fw.y = 0.0
	if to.length() < 0.5:
		return 0.0
	var err := fw.normalized().signed_angle_to(to.normalized(), Vector3.UP)
	return clampf(-err * 4.0, -1.0, 1.0)


## Drehung um die Hochachse; k = 0 dreht um die Wagenmitte, k = 1 um die Vorderachse (das Heck schwenkt aus,
## wie bei einem Hecktriebler im Drift).
func _rotate_front(angle: float, k: float) -> void:
	if k <= 0.0:
		rotate_y(angle)
		return
	var pivot := Vector3(0, 0, -(_length / 2.0 - 0.78))
	var before := global_transform * pivot
	rotate_y(angle)
	var after := global_transform * pivot
	var shift := (before - after) * k
	shift.y = 0.0
	global_position += shift


## Drift-Modus, Auto steht quer: Gas hält den Winkel, Lenken steuert ihn, die Fahrtrichtung dreht langsam nach.
## Liefert die Quergeschwindigkeit (für Sound und Optik).
func _slide_physics(dt: float, fwd: Vector3, right: Vector3, thr: float, hb: bool, a: float, eff_top: float, low_speed: float) -> float:
	var vel := fwd * speed_fwd + right * speed_lat  # enthält schon den Antrieb entlang der Fahrzeugachse
	var beta := atan2(speed_lat, maxf(speed_fwd, 0.5))  # > 0: Auto rutscht nach rechts weg (Linkskurve)
	var yaw := -steer * steer_rate * 0.6 * (0.5 + 0.5 * low_speed)
	yaw += signf(beta) * thr * (0.7 + 0.35 * drift_k) * clampf(absf(beta) / 0.3, 0.0, 1.0)
	yaw -= beta * (1.1 + 0.9 * (1.0 - thr))  # ohne Gas richtet es sich auf
	if hb:
		yaw *= 1.3
	_spin = move_toward(_spin, 0.0, dt * 2.0)
	_rotate_front((clampf(yaw, -3.2, 3.2) + _spin) * dt, 0.85)
	var nf := -global_basis.z
	nf.y = 0.0
	nf = nf.normalized()
	var nr := Vector3(-nf.z, 0, nf.x)
	var vs := vel.length()
	var b2 := atan2(vel.dot(nr), vel.dot(nf))
	# Seitenhalt im Rutschen: die Fahrtrichtung dreht mit begrenzter Rate zur Fahrzeugachse
	var mu := lerpf(12.0, 9.0, drift_k) * (0.6 if hb else 1.0) * (0.3 if stun > 0.0 else 1.0)
	var turn := signf(b2) * minf(absf(b2), mu / maxf(vs, 6.0) * dt)
	vel = vel.rotated(Vector3.UP, turn)
	b2 -= turn
	vs = clampf(vs - lerpf(8.5, 5.5, drift_k) * absf(sin(b2)) * dt, 0.0, maxf(eff_top, 1.0))
	velocity = vel.normalized() * vs if vel.length() > 0.01 else Vector3.ZERO
	velocity.y = 0.0
	drift_angle = rad_to_deg(absf(b2))
	drifting = absf(b2) > deg_to_rad(8.0) and vs > 8.0
	if absf(b2) < deg_to_rad(5.0) or vs < 6.0 or absf(b2) > deg_to_rad(100.0):
		_slide_out += dt
		if _slide_out > 0.15:
			_sliding = false
	else:
		_slide_out = 0.0
	return velocity.dot(nr)


## Höhe: Gehweg, Rampen, Absprung, Flug, Landung, Wasser
func _update_vertical(dt: float) -> void:
	if track.is_empty():
		position.y = 0.0
		return
	loc = Track.locate(track, global_position)
	path_id = loc["path"]["id"]
	progress = Track.race_progress(loc)
	lateral = loc["lat"]
	if track["loop"]:
		var L: float = track["length"]
		if progress < L * 0.25 and _last_prog > L * 0.75:
			lap += 1
		elif progress > L * 0.75 and _last_prog < L * 0.25:
			lap -= 1
		_last_prog = progress
	total = lap * track["length"] + progress
	var g := Track.ground(track, loc, global_position)
	var gh: float = g["h"]
	var base: float = g["base"]
	# Fahrbahnneigung in Fahrtrichtung des Autos
	var pc: Curve3D = loc["path"]["curve"]
	var sl := Track.slope_at(pc, loc["d"])
	var tf: Vector3 = Track.frame_at(pc, loc["d"])["fwd"]
	_slope_pitch = atan(sl * (-global_basis.z).dot(tf))
	_slope_roll = atan(sl * global_basis.x.dot(tf))
	var bvy := (base - _base_y) / maxf(dt, 0.0001)
	var crest := _base_ok and absf(base - _base_y) < 2.0 and bvy < _base_vy - GRAVITY * dt * 1.1 and absf(speed_fwd) > 15.0
	_base_ok = true
	_base_vy = bvy
	_base_y = base
	if airborne:
		vy -= GRAVITY * dt
		position.y += vy * dt
		air_time += dt
		if position.y <= gh:
			_curb_y = gh - base
			vy -= bvy  # Aufprall relativ zur Fahrbahn (bergab landet es sich weicher)
			_land(gh, g["water"])
		return
	var prev := position.y
	if gh - base < _curb_y - 0.35 and absf(speed_fwd) > 6.0 or crest:
		# Rampenende oder Kuppe (die Straße fällt schneller weg, als die Schwerkraft das Auto mitnimmt): abheben
		airborne = true
		vy = minf(_ground_vy, MAX_LAUNCH_VY)
		air_time = 0.0
		Sfx.play("whoosh", -8.0 + clampf(vy, 0.0, 8.0), randf_range(0.9, 1.1))
		return
	if g["water"]:
		_splash()
		return
	# Bordstein: mit Puffer, sonst ruckelt es, wenn man genau an der Kante fährt
	var on_walk: bool = path_id == 0 and loc["score"] > (0.05 if _on_walk else 0.35)
	if on_walk != _on_walk:
		_on_walk = on_walk
		var s := velocity.length()
		_shake = minf(_shake + 0.06 + s * 0.003, 0.4)
		if on_walk:
			velocity *= 0.97
		model.get_meta("body").rotation.z += 0.04 * signf(lateral) * (1.0 if on_walk else -1.0)
	if g["ramp"]:
		_curb_y = gh - base
	else:
		_curb_y = move_toward(_curb_y, gh - base, dt * 3.0)
	position.y = base + _curb_y
	_ground_vy = (position.y - prev) / maxf(dt, 0.0001)


func _land(gh: float, water: bool) -> void:
	var impact := -vy
	airborne = false
	position.y = gh
	vy = 0.0
	last_air = air_time
	landings += 1
	if water:
		_splash()
		return
	Sfx.play("thud", linear_to_db(clampf(impact / 14.0, 0.3, 1.0)), randf_range(0.9, 1.05))
	audio.crash(clampf(impact / 30.0, 0.1, 0.4))
	_shake = minf(_shake + impact * 0.025, 0.7)
	velocity *= 0.97 if impact < 10.0 else 0.92
	model.get_meta("body").rotation.x = -0.08


func _splash() -> void:
	if sinking > 0.0:
		return
	sinking = 1.6
	airborne = false
	Sfx.play("splash")
	audio.crash(0.4)
	_shake = 0.6
	# Zurücksetzen vor die Rampe, mit Anlauf
	var p: Dictionary = loc["path"]
	var d := maxf(loc["d"] - 55.0, 2.0)
	for r in track["ramps"]:
		if r["path"] == p["id"] and loc["d"] > r["d0"] and loc["d"] - r["d0"] < 80.0:
			d = maxf(r["d0"] - 45.0, 2.0)
	_respawn_xf = Track.xform_at(p["curve"], d, 0.0)


func _update_sinking(dt: float) -> void:
	sinking -= dt
	velocity = velocity * 0.92
	position += velocity * dt
	position.y -= dt * 1.2
	rpm = move_toward(rpm, 900.0, dt * 4000.0)
	audio.rpm = rpm
	audio.throttle = 0.0
	audio.speed = 0.0
	_update_camera(dt, 0.0)
	if sinking <= 0.0:
		sinking = 0.0
		place(_respawn_xf)


func _update_camera(dt: float, sf: float) -> void:
	var base := 58.0 if cam_mode == 0 else 70.0
	var target_fov := base + (14.0 if cam_mode == 0 else 24.0) * sf + (8.0 if nitro_on else 0.0)
	_fov = lerpf(_fov, target_fov, dt * (6.0 if nitro_on else 2.5))
	cam.fov = _fov
	# Kein Dauerwackeln bei Tempo: nur kurze, weiche Stöße bei Einschlägen und Landungen
	var amp := _shake * 0.06
	var drift_look := clampf((drift_angle - 6.0) / 24.0, 0.0, 1.0) * 0.45 if velocity.length() > 5.0 else 0.0
	_cam_drift = lerpf(_cam_drift, drift_look, 1.0 - exp(-dt * 3.0))
	if cam_mode == 0:
		# Verfolger: folgt mit leichter Verzögerung; im Drift schaut sie stufenlos ein Stück in Fahrtrichtung,
		# so sieht man die Kurve und den Winkel
		var yaw := global_rotation.y
		if velocity.length() > 2.0:
			yaw = lerp_angle(yaw, atan2(-velocity.x, -velocity.z), _cam_drift)
		var dist := 4.4 + sf * 0.6 + (0.4 if nitro_on else 0.0)
		var height := 1.6 - sf * 0.2
		if not _cam_init:
			_cam_yaw = yaw
			_cam_pos = global_position + Basis(Vector3.UP, yaw) * Vector3(0, height, dist)
			_cam_init = true
		# etwas Verzögerung: in Kurven sieht man das Auto einlenken (wie die NFSU-Verfolgerkamera)
		_cam_yaw = lerp_angle(_cam_yaw, yaw, 1.0 - exp(-dt * (2.0 if airborne else 4.5)))
		var target := global_position + Basis(Vector3.UP, _cam_yaw) * Vector3(0, height, dist)
		_cam_pos = _cam_pos.lerp(target, 1.0 - exp(-dt * 20.0))
		_cam_pos.y = lerpf(_cam_pos.y, target.y, 1.0 - exp(-dt * (6.0 if airborne else 20.0)))
		cam.global_position = _cam_pos
		cam.look_at(global_position + Basis(Vector3.UP, _cam_yaw) * Vector3(0, 1.1, -7.0), Vector3.UP)
		cam.rotate_object_local(Vector3.FORWARD, -steer * sf * 0.02)
	else:
		cam.rotation.z = lerpf(cam.rotation.z, -steer * sf * 0.025, dt * 5.0)
	_shake_t += dt
	cam.h_offset = sin(_shake_t * 41.0) * amp
	cam.v_offset = sin(_shake_t * 53.0 + 1.3) * amp
	_shake = move_toward(_shake, 0.0, dt * 3.0)


func place(xform: Transform3D) -> void:
	global_transform = xform
	velocity = Vector3.ZERO
	speed_fwd = 0.0
	steer = 0.0
	_spin = 0.0
	_slip_hold = 0.0
	stun = 0.0
	airborne = false
	vy = 0.0
	sinking = 0.0
	_cam_init = false
	_base_ok = false
	_curb_y = 0.0
	if model:
		model.rotation = Vector3.ZERO


## Verkehr ist das Schlimmste (frontal oder Auffahren: Dreher, kurz keine Kontrolle; seitlich: abprallen),
## Rennwagen werden gerempelt, an Wänden schrammt man entlang.
func _handle_collisions(pre: Vector3) -> void:
	var walled := false
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		n.y = 0.0
		if n.length_squared() < 0.01:
			continue
		n = n.normalized()
		var other := c.get_collider()
		if other is Node and other.is_in_group("traffic"):
			_hit_traffic(other, pre, n)
		elif other is Node and other.is_in_group("racer"):
			var impact := -pre.dot(n)
			other.bump(pre, n)
			velocity += n * clampf(impact, 0.0, 10.0) * 0.4
			if impact > 3.0:
				_shake = minf(_shake + impact * 0.02, 0.4)
				audio.crash(clampf(impact / 25.0, 0.1, 0.5))
		elif not walled:
			walled = true
			if debug_hits:
				_collider_name = _describe(c)
			_hit_wall(pre, n)


## Wand/Bande wie in NFSU: je flacher der Winkel, desto weniger Tempoverlust; das Auto wird parallel zur Wand
## gestellt und schrammt entlang. Nur frontal (fast rechtwinklig) prallt es ab.
func _hit_wall(pre: Vector3, n: Vector3) -> void:
	var spd := pre.length()
	var vn := -pre.dot(n)  # Tempo in die Wand hinein
	if spd < 0.5 or vn < 0.2:
		return
	var head_on := clampf(vn / spd, 0.0, 1.0)  # Sinus des Aufprallwinkels
	var tang := pre + n * vn
	var keep := 1.0 - 0.7 * head_on * head_on
	var new_v := n * vn * (0.08 + 0.15 * head_on * head_on)
	if tang.length() > 0.1:
		new_v += tang.normalized() * spd * keep * (1.0 - pow(head_on, 4.0))
	new_v = new_v.move_toward(Vector3.ZERO, 3.0 * get_physics_process_delta_time())  # Schleifen kostet etwas
	velocity = Vector3(new_v.x, 0.0, new_v.z)
	# Parallel zur Wand drehen (bei streifenden Treffern fast ganz, frontal gar nicht)
	if tang.length() > 0.5:
		var fwd := -global_basis.z
		fwd.y = 0.0
		var along := tang.normalized() * signf(tang.dot(fwd) + 0.001)
		var ang := fwd.normalized().signed_angle_to(along, Vector3.UP)
		_rotate_front(ang * (1.0 - smoothstep(0.75, 0.97, head_on)), 0.0)
	if vn > 1.5 and _wall_cool <= 0.0:
		_wall_cool = 0.4
		if debug_hits:
			last_hit = "%s v=%.1f vn=%.1f d=%.0f lat=%.1f" % [_collider_name, spd, vn, progress, lateral]
		wall_hits += 1
		audio.crash(clampf(vn / 30.0, 0.08, 1.0))
		_shake = minf(_shake + vn * 0.025, 0.8)
	if drift_mode and head_on > 0.5:
		_sliding = false
	if vn > 14.0 and head_on > 0.75 and _crash_cooldown <= 0.0:
		crashes += 1
		stun = 0.35
		_crash_cooldown = 0.5
		_spin = signf(pre.dot(global_basis.x) + 0.01) * 0.8


## Verkehr: frontal oder deutliches Auffahren ist ein Crash wie in NFS (fast Stillstand, Dreher, kurz keine
## Kontrolle). Seitliches Rempeln oder langsames Auffahren: abprallen und Tempo verlieren, das andere Auto schleudert.
func _hit_traffic(other: Node, pre: Vector3, n: Vector3) -> void:
	var ov: Vector3 = other.velocity_vec
	var rel: Vector3 = pre - ov
	var hit := -rel.dot(n)
	if hit < 1.5 or _crash_cooldown > 0.0:
		return
	var head_on := clampf(hit / maxf(rel.length(), 1.0), 0.0, 1.0)
	audio.crash(clampf(hit / 22.0, 0.25, 1.0))
	if drag_mode and hit > 9.0 and head_on > 0.5:
		totaled = true  # Drag: wer frontal oder ins Heck kracht, ist raus
	if hit > 14.0 and head_on > 0.55:
		other.knock(pre * 0.7)
		velocity = ov * 0.4 + n * 3.0
		_spin = randf_range(1.2, 2.4) * (1.0 if randf() < 0.5 else -1.0) * clampf(hit / 25.0, 0.5, 1.0)
		stun = 0.8
		_shake = 1.0
		_crash_cooldown = 0.7
		crashes += 1
	else:
		other.knock(-n * hit * 1.2)
		var v := pre + n * hit * 1.15
		velocity = v * lerpf(0.95, 0.72, head_on)
		velocity.y = 0.0
		_spin += signf(n.dot(global_basis.x)) * clampf(hit * 0.05, 0.1, 0.6)
		_shake = minf(_shake + hit * 0.04, 0.7)
		_crash_cooldown = 0.35
		if hit > 8.0:
			crashes += 1
			stun = 0.2


## Nur für Tests: beschreibt, woran das Auto gestoßen ist (Form, Lage, nächste Wandfläche)
func _describe(c: KinematicCollision3D) -> String:
	var cs := c.get_collider_shape() as CollisionShape3D
	if cs == null:
		return "?"
	var p := c.get_position()
	if cs.shape is BoxShape3D:
		return "Kiste %s bei %s (Eltern: %s)" % [cs.shape.size, cs.global_position.snapped(Vector3.ONE * 0.1), cs.get_parent().get_parent().name]
	if cs.shape is ConcavePolygonShape3D:
		var f: PackedVector3Array = cs.shape.get_faces()
		var best := 1e9
		var bi := 0
		for i in range(0, f.size(), 3):
			var m := (f[i] + f[i + 1] + f[i + 2]) / 3.0
			var dd := Vector2(m.x - p.x, m.z - p.z).length()
			if dd < best:
				best = dd
				bi = i
		return "Wand %s-%s bei %s" % [f[bi].snapped(Vector3.ONE * 0.1), f[bi + 1].snapped(Vector3.ONE * 0.1), p.snapped(Vector3.ONE * 0.1)]
	return str(cs.shape)

