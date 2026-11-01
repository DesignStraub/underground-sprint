extends Node3D
## Hochbahn-Zug: fährt in Abständen über das Viadukt und verschwindet an den Enden in den Häusern.
## Rein optisch, mit Rumpeln, das mit dem Abstand zum Spieler leiser wird (race.gd setzt target).

const Builder := preload("res://scripts/car_builder.gd")
const SPEED := 19.0
const CAR_LEN := 13.0
const CARS := 3

var curve: Curve3D
var d_from := 0.0
var d_to := 0.0
var lanes := [0.0, 0.0]
var deck_y := 0.0
var target: Node3D
var _cars: Array[Node3D] = []
var _d := 0.0
var _dir := 1.0
var _lane := 0.0
var _wait := 3.0
var _active := false
var _rumble: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _met := false  # Begegnung mit dem Spieler schon ausgelöst
var _check := 0.0


func setup(curve_: Curve3D, from: float, to: float, lanes_: Array, deck_y_: float, seed_: int) -> void:
	curve = curve_
	d_from = from
	d_to = to
	lanes = lanes_
	deck_y = deck_y_
	_rng.seed = seed_
	_wait = _rng.randf_range(0.5, 2.5)
	add_to_group("ambient")
	var body := Builder.mat(Color(0.55, 0.57, 0.6), 0.6, 0.35)
	var win := Builder.mat(Color(1.0, 0.9, 0.7), 0.0, 0.3, Color(1.0, 0.88, 0.65), 4.0)
	var stripe := Builder.mat(Color(0.75, 0.08, 0.06), 0.3, 0.4)
	var head := Builder.mat(Color(1, 1, 0.9), 0.0, 0.3, Color(1, 0.95, 0.8), 4.0)
	for i in CARS:
		var car := Node3D.new()
		car.visible = false
		Builder._add(car, Builder.box(Vector3(2.8, 2.9, CAR_LEN - 0.4)), body, Vector3(0, 1.75, 0))
		Builder._add(car, Builder.box(Vector3(2.86, 0.85, CAR_LEN - 1.4)), win, Vector3(0, 2.15, 0))
		Builder._add(car, Builder.box(Vector3(2.87, 0.22, CAR_LEN - 0.4)), stripe, Vector3(0, 1.2, 0))
		Builder._add(car, Builder.box(Vector3(2.0, 0.25, CAR_LEN - 2.0)), body, Vector3(0, 3.3, 0))
		for z in [-1.0, 1.0]:
			Builder._add(car, Builder.box(Vector3(1.6, 0.25, 0.05)), head, Vector3(0, 1.6, z * (CAR_LEN / 2.0 - 0.18)))
		add_child(car)
		_cars.append(car)
	_rumble = Sfx.looping("rumble")
	_rumble.pitch_scale = 1.3
	_rumble.volume_db = -80.0
	add_child(_rumble)


func _xform(d: float) -> Transform3D:
	var len := curve.get_baked_length()
	var a := curve.sample_baked(clampf(d - 1.0, 0.0, len))
	var b := curve.sample_baked(clampf(d + 1.0, 0.0, len))
	var fwd := b - a
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0, fwd.x)
	var p := curve.sample_baked(clampf(d, 0.0, len)) + right * _lane
	return Transform3D(Basis.looking_at(fwd * _dir, Vector3.UP), Vector3(p.x, deck_y, p.z))


func _process(dt: float) -> void:
	if curve == null:
		return
	_check -= dt
	var meet := false
	if not _met and _check <= 0.0 and target and is_instance_valid(target):
		# Spieler nähert sich: Zug kommt ihm entgegen, sie begegnen sich etwa in der Mitte.
		# Ein Zug, der gerade wegfährt, wird dafür neu gestartet.
		_check = 0.25
		var po := curve.get_closest_offset(target.global_position)
		meet = po > d_from - 300.0 and po < d_from - 60.0 and not (_active and _dir < 0.0)
		_met = _met or (po > d_from - 300.0 and po < d_from - 60.0)
	if not _active or meet:
		_wait -= dt
		if _wait <= 0.0 or meet:
			_active = true
			_dir = -1.0 if meet else (1.0 if _rng.randf() < 0.5 else -1.0)
			_lane = lanes[0] if _dir < 0.0 else lanes[1]
			_d = d_from - 2.0 if _dir > 0.0 else d_to + 2.0
			_rumble.play()
		else:
			return
	_d += SPEED * dt * _dir
	var train_len := CARS * (CAR_LEN + 0.6)
	for i in CARS:
		var dc := _d - _dir * (i * (CAR_LEN + 0.6) + CAR_LEN / 2.0)
		var car := _cars[i]
		car.visible = dc > d_from - CAR_LEN * 0.5 and dc < d_to + CAR_LEN * 0.5
		if car.visible:
			car.transform = _xform(dc)
	if target and is_instance_valid(target):
		var mid := _xform(_d - _dir * train_len * 0.5).origin
		var k := clampf(1.0 - target.global_position.distance_to(mid) / 170.0, 0.0, 1.0)
		_rumble.volume_db = -3.0 + linear_to_db(maxf(k * k, 0.0003))
	if (_dir > 0.0 and _d - train_len > d_to) or (_dir < 0.0 and _d + train_len < d_from):
		_active = false
		for car in _cars:
			car.visible = false
		_rumble.stop()
		_wait = _rng.randf_range(4.0, 10.0)
