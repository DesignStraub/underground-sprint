extends Node3D
## Bahnübergang: Gleise quer zur Straße, Schranken, Andreaskreuz mit Blinklicht, Glocke und ein Zug.
## Der Zug startet, wenn sich der Spieler nähert, so dass er ungefähr gleichzeitig ankommt.
## Er ist ein hartes Hindernis (Gruppe "traffic"). Mit der Rampe auf der rechten Außenspur springt man drüber.

const Builder := preload("res://scripts/car_builder.gd")
const BLINK_SHADER := preload("res://shaders/blink.gdshader")
const TrainBody := preload("res://scripts/train_body.gd")

const SPEED := 32.0
const RAIL_HALF := 560.0
const WARN_TIME := 5.0  # so viele Sekunden vor dem Zug gehen die Schranken runter

var d_cross := 0.0
var player: Node3D
var origin := Vector3.ZERO
var axis := Vector3.RIGHT  # Gleisrichtung
var fwd := Vector3.FORWARD  # Straßenrichtung
var train: TrainBody
var train_len := 0.0
var blocked := false
var _t_arrive := -1.0
var _dir := 1.0
var _clock := 0.0
var _triggered := false
var _gates := []
var _gate_angle := deg_to_rad(-85.0)
var _lights := []
var _bell: AudioStreamPlayer
var _rumble: AudioStreamPlayer


func setup(frame: Dictionary, d: float, half_w: float, walk: float) -> void:
	d_cross = d
	origin = frame["pos"]
	fwd = frame["fwd"]
	axis = frame["right"]
	var right: Vector3 = frame["right"]
	var steel := Builder.mat(Color(0.55, 0.55, 0.58), 0.9, 0.3)
	var gravel := Builder.mat(Color(0.18, 0.17, 0.16), 0.0, 1.0)
	var wood := Builder.mat(Color(0.15, 0.1, 0.07), 0.0, 0.9)
	var rail_basis := Basis.looking_at(axis, Vector3.UP)
	# Schienen
	for s in [-0.72, 0.72]:
		var r := MeshInstance3D.new()
		r.mesh = Builder.box(Vector3(0.1, 0.12, RAIL_HALF * 2.0))
		r.material_override = steel
		r.transform = Transform3D(rail_basis, origin + fwd * s + Vector3(0, 0.06, 0))
		add_child(r)
	# Schotterbett und Schwellen außerhalb der Straße
	var road_edge := half_w + walk + 0.5
	var sleepers := MultiMesh.new()
	sleepers.transform_format = MultiMesh.TRANSFORM_3D
	sleepers.mesh = Builder.box(Vector3(2.4, 0.12, 0.25))
	var xs := []
	var x := -RAIL_HALF
	while x < RAIL_HALF:
		if absf(x) > road_edge:
			xs.append(x)
		x += 0.9
	sleepers.instance_count = xs.size()
	var sleeper_basis := Basis.looking_at(fwd, Vector3.UP)
	for i in xs.size():
		sleepers.set_instance_transform(i, Transform3D(sleeper_basis, origin + axis * xs[i] + Vector3(0, 0.03, 0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = sleepers
	mmi.material_override = wood
	add_child(mmi)
	for s in [-1.0, 1.0]:
		var seg := RAIL_HALF - road_edge
		var g := MeshInstance3D.new()
		g.mesh = Builder.box(Vector3(3.6, 0.1, seg))
		g.material_override = gravel
		g.transform = Transform3D(rail_basis, origin + axis * s * (road_edge + seg / 2.0) + Vector3(0, -0.02, 0))
		add_child(g)
	# Andreaskreuz + Schranke je Fahrtrichtung (rechts für uns, links für den Gegenverkehr)
	for s in [1.0, -1.0]:
		var approach: Vector3 = -fwd * s  # von dort kommen die Autos
		var side_dir: Vector3 = right * s
		_cross_sign(origin + approach * 9.0 + side_dir * (half_w + 1.4), -approach)
		_gate(origin + approach * 6.0 + side_dir * (half_w + 0.6), -approach, half_w)
	_build_train()
	_bell = Sfx.looping("bell")
	add_child(_bell)
	_rumble = Sfx.looping("rumble")
	add_child(_rumble)


## Schild; `facing` ist die Fahrtrichtung der ankommenden Autos, das Schild schaut ihnen entgegen (+Z)
func _cross_sign(pos: Vector3, facing: Vector3) -> void:
	var n := Node3D.new()
	n.transform = Transform3D(Basis.looking_at(facing, Vector3.UP), pos + Vector3(0, 0.2, 0))
	add_child(n)
	var white := Builder.mat(Color(0.95, 0.95, 0.95), 0.0, 0.4, Color(1, 1, 1), 0.3)
	var red := Builder.mat(Color(0.85, 0.05, 0.05), 0.0, 0.4)
	var grey := Builder.mat(Color(0.3, 0.3, 0.32), 0.6, 0.4)
	Builder._add(n, Builder.box(Vector3(0.12, 3.6, 0.12)), grey, Vector3(0, 1.8, 0))
	for a in [45.0, -45.0]:
		Builder._add(n, Builder.box(Vector3(1.9, 0.3, 0.04)), red, Vector3(0, 3.2, 0.06)).rotation_degrees.z = a
		Builder._add(n, Builder.box(Vector3(1.75, 0.18, 0.04)), white, Vector3(0, 3.2, 0.09)).rotation_degrees.z = a
	Builder._add(n, Builder.box(Vector3(1.1, 0.4, 0.1)), Builder.mat(Color(0.05, 0.05, 0.05), 0.3, 0.5), Vector3(0, 2.2, 0.05))
	for k in 2:
		var m := ShaderMaterial.new()
		m.shader = BLINK_SHADER
		m.set_shader_parameter("rate", 1.2)
		var sm := SphereMesh.new()
		sm.radius = 0.14
		sm.height = 0.28
		var l := Builder._add(n, sm, m, Vector3(-0.3 + k * 0.6, 2.2, 0.14))
		l.set_instance_shader_parameter("phase", 0.5 * k)
		l.set_instance_shader_parameter("active", 0.0)
		_lights.append(l)


## Schranke: Drehpunkt am Straßenrand, Baum ragt zur Fahrbahnmitte (lokal -X)
func _gate(pos: Vector3, facing: Vector3, length: float) -> void:
	var post := Node3D.new()
	post.transform = Transform3D(Basis.looking_at(facing, Vector3.UP), pos)
	add_child(post)
	var white := Builder.mat(Color(0.95, 0.95, 0.95), 0.0, 0.4, Color(1, 1, 1), 0.4)
	var red := Builder.mat(Color(0.9, 0.05, 0.05), 0.0, 0.4, Color(1, 0.05, 0.02), 0.6)
	var grey := Builder.mat(Color(0.35, 0.35, 0.37), 0.6, 0.4)
	Builder._add(post, Builder.box(Vector3(0.45, 1.2, 0.45)), grey, Vector3(0, 0.6, 0))
	var pivot := Node3D.new()
	pivot.position = Vector3(0, 1.05, 0)
	post.add_child(pivot)
	var segs := 6
	for i in segs:
		var sl := length / segs
		Builder._add(pivot, Builder.box(Vector3(sl, 0.14, 0.1)), red if i % 2 == 0 else white, Vector3(-sl * (i + 0.5), 0, 0))
	Builder._add(pivot, Builder.box(Vector3(0.8, 0.3, 0.2)), grey, Vector3(0.5, 0, 0))  # Gegengewicht
	_gates.append(pivot)


func _build_train() -> void:
	train = TrainBody.new()
	train.add_to_group("traffic")
	train.collision_layer = 2
	train.collision_mask = 0
	add_child(train)
	var red := Builder.mat(Color(0.7, 0.05, 0.05), 0.4, 0.35)
	var white := Builder.mat(Color(0.85, 0.85, 0.87), 0.3, 0.4)
	var dark := Builder.mat(Color(0.06, 0.06, 0.07), 0.5, 0.5)
	var win := Builder.mat(Color(0.05, 0.05, 0.05), 0.5, 0.2, Color(1, 0.85, 0.6), 1.6)
	var head := Builder.mat(Color(1, 1, 0.9), 0.0, 0.3, Color(1, 1, 0.9), 6.0)
	var lengths := [16.0, 14.0, 14.0, 14.0, 14.0, 14.0]
	var gap := 1.0
	train_len = 0.0
	for l in lengths:
		train_len += l + gap
	train_len -= gap
	var z := -train_len / 2.0
	for i in lengths.size():
		var l: float = lengths[i]
		var cz := z + l / 2.0
		var car := Node3D.new()
		car.position = Vector3(0, 0, cz)
		train.add_child(car)
		Builder._add(car, Builder.box(Vector3(3.0, 3.1, l)), white, Vector3(0, 2.25, 0))
		Builder._add(car, Builder.box(Vector3(3.02, 0.6, l + 0.02)), red, Vector3(0, 1.05, 0))
		Builder._add(car, Builder.box(Vector3(3.04, 0.9, l - 1.6)), win, Vector3(0, 2.6, 0))
		Builder._add(car, Builder.box(Vector3(2.6, 0.3, l - 0.4)), dark, Vector3(0, 3.95, 0))
		for bz in [-l / 2.0 + 2.2, l / 2.0 - 2.2]:
			Builder._add(car, Builder.box(Vector3(2.4, 0.7, 2.4)), dark, Vector3(0, 0.45, bz))
		if i == 0:
			# Triebkopf vorne (lokal -Z): schräge Front, Scheinwerfer, Stromabnehmer
			Builder._add(car, Builder.tapered_box(Vector2(3.0, 2.0), Vector2(2.6, 0.6), 1.1, 0.5), dark, Vector3(0, 2.6, -l / 2.0 + 1.0))
			for s in [-0.9, 0.9]:
				Builder._add(car, Builder.box(Vector3(0.4, 0.25, 0.05)), head, Vector3(s, 1.4, -l / 2.0 - 0.02))
			Builder._add(car, Builder.box(Vector3(0.1, 1.2, 1.4)), dark, Vector3(0, 4.6, 0)).rotation_degrees.x = 30
			var sp := SpotLight3D.new()
			sp.position = Vector3(0, 1.6, -l / 2.0 - 0.3)
			sp.spot_range = 60.0
			sp.spot_angle = 30.0
			sp.light_energy = 6.0
			car.add_child(sp)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(3.2, 4.0, l)
		cs.shape = bs
		cs.position = Vector3(0, 0, cz) + Vector3(0, 2.0, 0)
		train.add_child(cs)
		z += l + gap
	train.visible = false
	train.position = origin + Vector3(0, -50, 0)


func is_blocked() -> bool:
	return blocked


func _process(dt: float) -> void:
	_clock += dt
	if player == null:
		return
	var p: float = player.progress
	if p < d_cross - 460.0:
		_triggered = false
	# Zug so starten, dass er mit dem Spieler am Übergang ankommt
	if not _triggered and _t_arrive < 0.0 and p > d_cross - 420.0 and p < d_cross - 200.0:
		_triggered = true
		if randf() < 0.8:
			var spd := maxf(absf(player.speed_fwd), 28.0)
			_t_arrive = _clock + (d_cross - p) / spd
			_dir = 1.0 if randf() < 0.5 else -1.0

	var was_blocked := blocked
	blocked = false
	if _t_arrive > 0.0:
		var x := (_clock - _t_arrive) * SPEED * _dir  # Mitte des Zugs entlang der Gleise
		var front := absf(x) - train_len / 2.0
		var approaching := x * _dir < 0.0
		blocked = (approaching and front < SPEED * WARN_TIME) or (not approaching and front < 12.0)
		train.visible = absf(x) < RAIL_HALF + train_len
		train.global_transform = Transform3D(Basis.looking_at(axis * _dir, Vector3.UP), origin + axis * x)
		train.velocity_vec = axis * _dir * SPEED
		var td := player.global_position.distance_to(train.global_position)
		_set_volume(_rumble, clampf(1.0 - td / 380.0, 0.0, 1.0), 2.0)
		if not approaching and front > RAIL_HALF:
			_t_arrive = -1.0
			train.visible = false
			train.position = origin + Vector3(0, -50, 0)
			_rumble.stop()
	if blocked and not was_blocked:
		var dist := player.global_position.distance_to(origin)
		Sfx.play("horn", linear_to_db(clampf(1.0 - dist / 600.0, 0.15, 1.0)))
	for l in _lights:
		l.set_instance_shader_parameter("active", 1.0 if blocked else 0.0)
	var cd := player.global_position.distance_to(origin)
	_set_volume(_bell, clampf(1.0 - cd / 220.0, 0.0, 1.0) if blocked else 0.0, -4.0)
	# Schranken: runter in ~2 s, rauf etwas langsamer
	var target := 0.0 if blocked else deg_to_rad(-85.0)
	_gate_angle = move_toward(_gate_angle, target, dt * (0.8 if blocked else 0.6))
	for g in _gates:
		g.rotation.z = _gate_angle


func _set_volume(a: AudioStreamPlayer, v: float, base_db: float) -> void:
	if v <= 0.01:
		if a.playing:
			a.stop()
		return
	a.volume_db = base_db + linear_to_db(v)
	if not a.playing:
		a.play()
