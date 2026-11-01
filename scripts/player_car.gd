extends CharacterBody3D
## Arcade-Fahrphysik: Gänge mit Drehzahl, Grip, der die Fahrtrichtung zur Fahrzeugachse zieht,
## Handbremse für Drifts, Nitro. Kamera sitzt auf Stoßstange oder Motorhaube.

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

var controls_enabled := false
var finished := false
var cam_mode := 0  # 0 Stoßstange, 1 Motorhaube

var model: Node3D
var cam: Camera3D
var audio: AudioStreamPlayer

var accel := 11.0
var top_speed := 58.0
var grip_k := 8.0
var steer_rate := 2.2
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
var _shift_timer := 0.0
var _shake := 0.0
var _fov := 72.0
var _length := 4.0
var _spec_cabin: Dictionary
var curve: Curve3D
var progress := 0.0
var lateral := 0.0
var stun := 0.0
var _spin := 0.0
var _on_walk := false
var _crash_cooldown := 0.0


func setup(car_id: String, cfg: Dictionary) -> void:
	var spec: Dictionary = Catalog.CARS[car_id]
	var eng: Dictionary = Catalog.PARTS["engine"]["options"][cfg["engine"]]
	var nos: Dictionary = Catalog.PARTS["nitro"]["options"][cfg["nitro"]]
	accel = spec["accel"] * eng["accel"]
	top_speed = spec["top_speed"] * eng["top"]
	grip_k = spec["grip"] * 0.32
	steer_rate = spec["steer"]
	nitro_power = nos["power"]
	nitro_cap = nos["capacity"]

	model = Builder.build(car_id, cfg)
	add_child(model)
	_length = model.get_meta("length")
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(model.get_meta("width"), 1.2, _length)
	col.shape = shape
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
	cam.far = 900.0
	cam.near = 0.05
	add_child(cam)
	cam.make_current()
	_spec_cabin = spec
	_apply_cam()

	audio = EngineAudio.new()
	audio.configure(spec["sound"])
	add_child(audio)



func _apply_cam() -> void:
	if cam_mode == 0:
		cam.position = Vector3(0, 0.5, -_length / 2 - 0.05)
		cam.rotation_degrees.x = -1.0
	else:
		var s := _spec_cabin
		cam.position = Vector3(0, Builder.CLEARANCE + s["height"] + 0.38, s["cabin_off"] - s["cabin_len"] / 2 - 0.05)
		cam.rotation_degrees.x = -5.0


func toggle_camera() -> void:
	cam_mode = (cam_mode + 1) % 2
	_apply_cam()


func _on_prop_hit(body: Node) -> void:
	if body.has_method("knock") and not body.knocked:
		body.knock(velocity)
		velocity *= body.slowdown
		_shake = minf(_shake + 0.2, 1.0)
		audio.crash(0.15 + body.mass / 200.0)


func _physics_process(dt: float) -> void:
	var thr := Input.get_action_strength("accelerate")
	var brk := Input.get_action_strength("brake")
	var steer_in := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	var hb := Input.is_action_pressed("handbrake")
	var want_nitro := Input.is_action_pressed("nitro")
	stun = maxf(stun - dt, 0.0)
	_crash_cooldown = maxf(_crash_cooldown - dt, 0.0)
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
		brk = 0.6 if finished else 0.0
		steer_in = 0.0
		hb = false
		want_nitro = false

	var fwd := -global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0, fwd.x)
	speed_fwd = velocity.dot(fwd)
	speed_lat = velocity.dot(right)
	var spd := absf(speed_fwd)

	# --- Gänge & Drehzahl
	var ratio := spd / top_speed
	var g := 1
	while g < 6 and ratio > GEARS[g]:
		g += 1
	if g > gear:
		_shift_timer = 0.16
	gear = g
	_shift_timer = maxf(_shift_timer - dt, 0.0)
	if controls_enabled or finished:
		# Drehzahl proportional zur Geschwindigkeit im Gang: nach dem Hochschalten fällt sie natürlich ab,
		# im 6. Gang liegt Topspeed bei TOP_RPM, mit Nitro steigt sie sanft weiter.
		var per_ratio: float = SHIFT_RPM / GEARS[gear] if gear < 6 else TOP_RPM
		var target_rpm := clampf(maxf(900.0 + thr * 600.0, ratio * per_ratio), 900.0, SHIFT_RPM + 300.0)
		if speed_fwd < -0.5:
			target_rpm = 900.0 + spd * 300.0
		if hb and thr > 0.5 and spd < 25.0:
			target_rpm = maxf(target_rpm, 6500.0)
		rpm = move_toward(rpm, target_rpm, dt * 20000.0)

	# --- Nitro
	nitro_on = want_nitro and nitro > 0.0 and speed_fwd > 4.0
	if nitro_on:
		nitro = maxf(nitro - dt * 0.3 / nitro_cap, 0.0)
	else:
		nitro = minf(nitro + dt * (0.015 + (0.13 if drifting else 0.0)) / nitro_cap, 1.0)

	# --- Längsbeschleunigung
	var a := 0.0
	var eff_top := top_speed * (1.0 + 0.22 * nitro_power if nitro_on else 1.0)
	if _shift_timer <= 0.0:
		a += accel * thr * GEAR_PULL[gear]
	if nitro_on:
		a += 8.5 * nitro_power
	var drag_k := accel * GEAR_PULL[6] / (top_speed * top_speed)
	a -= drag_k * speed_fwd * absf(speed_fwd)
	if speed_fwd > eff_top:
		a = minf(a, -6.0)
	if thr < 0.05:
		a -= signf(speed_fwd) * 1.6  # Motorbremse
	if brk > 0.0:
		if speed_fwd > 1.0:
			a -= 30.0 * brk
		elif speed_fwd > -14.0:
			a -= 9.0 * brk
	if hb:
		a -= signf(speed_fwd) * 4.0
	speed_fwd += a * dt
	if absf(speed_fwd) < 0.3 and thr < 0.05 and brk < 0.05:
		speed_fwd = 0.0

	# --- Lenkung
	var steer_speed := 6.0 if absf(steer_in) > 0.01 else 8.0
	steer = move_toward(steer, steer_in, dt * steer_speed)
	var low_speed := clampf(spd / 7.0, 0.0, 1.0)
	var high_speed := lerpf(1.0, 0.42, clampf(spd / top_speed, 0.0, 1.0))
	var yaw := -steer * steer_rate * low_speed * high_speed * signf(speed_fwd + 0.001)
	if hb:
		yaw *= 1.5
	if drifting:
		yaw *= 1.2  # Gegenlenken/Eindrehen im Drift
	_spin = move_toward(_spin, 0.0, dt * 2.0)
	rotate_y((yaw + _spin) * dt)

	# Neue Fahrzeugachse; Geschwindigkeit bleibt zunächst in Weltrichtung -> Querschlupf entsteht
	var new_fwd := -global_basis.z
	new_fwd.y = 0
	new_fwd = new_fwd.normalized()
	var new_right := Vector3(-new_fwd.z, 0, new_fwd.x)
	var v := fwd * speed_fwd + right * speed_lat
	var f2 := v.dot(new_fwd)
	var l2 := v.dot(new_right)

	# --- Grip: Querbewegung abbauen, einen Teil davon in Vortrieb umwandeln (Arcade)
	var gk := grip_k * (0.13 if hb else 1.0) * (0.25 if stun > 0.0 else 1.0)
	if drifting and not hb:
		gk *= 0.45  # Drift hält etwas an
	var l_new := l2 * exp(-gk * dt)
	var removed := absf(l2) - absf(l_new)
	f2 += removed * 0.55 * signf(f2)
	f2 = minf(f2, maxf(eff_top, speed_fwd))  # Drift-Umwandlung darf nicht über Topspeed schieben
	l2 = l_new
	drifting = absf(l2) > 3.5 and spd > 10.0

	velocity = new_fwd * f2 + new_right * l2
	velocity.y = 0.0
	var pre := velocity
	move_and_slide()
	_handle_collisions(pre)
	_update_ground(dt)

	# --- Optik, Kamera, Sound
	var sf := clampf(spd / top_speed, 0.0, 1.0)
	Builder.animate(model, speed_fwd, steer, steer * sf * 0.06 - l2 * 0.004, clampf(a * 0.004, -0.05, 0.04), nitro_on, dt)
	_update_camera(dt, sf)

	audio.rpm = rpm
	audio.throttle = 1.0 if nitro_on else (Input.get_action_strength("accelerate") if not finished else 0.0)
	audio.nitro = nitro_on
	audio.slip = clampf((absf(l2) - 3.0) / 10.0, 0.0, 1.0) if spd > 5.0 else 0.0
	audio.speed = spd


func _update_camera(dt: float, sf: float) -> void:
	var target_fov := 70.0 + 26.0 * sf + (12.0 if nitro_on else 0.0)
	_fov = lerpf(_fov, target_fov, dt * (6.0 if nitro_on else 2.5))
	cam.fov = _fov
	var amp := sf * sf * 0.025 + _shake * 0.12 + (0.015 if nitro_on else 0.0)
	cam.h_offset = randf_range(-amp, amp)
	cam.v_offset = randf_range(-amp, amp)
	cam.rotation.z = lerpf(cam.rotation.z, -steer * sf * 0.035 + speed_lat * 0.004, dt * 5.0)
	_shake = move_toward(_shake, 0.0, dt * 2.5)


func place(xform: Transform3D) -> void:
	global_transform = xform
	velocity = Vector3.ZERO
	speed_fwd = 0.0
	steer = 0.0
	_spin = 0.0
	stun = 0.0


## Wände/feste Hindernisse kosten viel Tempo, Verkehr ist ein Totalcrash, Rennwagen werden gerempelt.
func _handle_collisions(pre: Vector3) -> void:
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		n.y = 0.0
		n = n.normalized()
		var other := c.get_collider()
		var impact := -pre.dot(n)
		if other is Node and other.is_in_group("traffic"):
			var rel: Vector3 = pre - other.velocity_vec
			var hit := -rel.dot(n)
			if hit > 4.0 and _crash_cooldown <= 0.0:
				# Wie in NFS: fast Stillstand, Dreher, kurz keine Kontrolle
				other.knock(pre * 0.7)
				velocity = other.velocity_vec * 0.3 + n * 3.0
				_spin = randf_range(1.2, 2.6) * (1.0 if randf() < 0.5 else -1.0) * clampf(hit / 25.0, 0.4, 1.0)
				stun = 0.9
				_shake = 1.0
				_crash_cooldown = 0.6
				audio.crash(1.0)
		elif other is Node and other.is_in_group("racer"):
			other.bump(pre, n)
			velocity += n * clampf(impact, 0.0, 10.0) * 0.4
			if impact > 3.0:
				_shake = minf(_shake + impact * 0.03, 0.6)
				audio.crash(clampf(impact / 25.0, 0.1, 0.5))
		elif impact > 2.0:
			# Wand/Hindernis: je frontaler, desto mehr Tempoverlust
			var head_on := clampf(impact / maxf(pre.length(), 1.0), 0.0, 1.0)
			velocity *= lerpf(0.9, 0.35, head_on)
			_shake = minf(_shake + impact * 0.04, 1.0)
			if impact > 12.0 and _crash_cooldown <= 0.0:
				stun = 0.4 + head_on * 0.4
				_crash_cooldown = 0.5
				_spin = signf(velocity.dot(global_basis.x) + 0.01) * head_on * 1.2
			audio.crash(clampf(impact / 30.0, 0.15, 1.0))


## Fortschritt/Querposition auf der Strecke, Bordstein-Holpern und Gehweghöhe.
func _update_ground(dt: float) -> void:
	if curve == null:
		position.y = 0.0
		return
	progress = curve.get_closest_offset(global_position)
	var f := Track.frame_at(curve, progress)
	lateral = (global_position - f["pos"]).dot(f["right"])
	var on_walk := absf(lateral) > Track.HALF_W + 0.2
	if on_walk != _on_walk:
		_on_walk = on_walk
		var spd := velocity.length()
		_shake = minf(_shake + 0.15 + spd * 0.008, 0.8)
		velocity *= 0.9 if spd > 15.0 else 0.97
		model.get_meta("body").rotation.z += 0.08 * signf(lateral) * (1.0 if on_walk else -1.0)
	position.y = move_toward(position.y, Track.CURB_H if on_walk else 0.0, dt * 3.0)
