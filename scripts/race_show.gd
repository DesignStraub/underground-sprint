extends Node3D
## Inszenierung rund ums Rennen wie in NFSU: Publikum am Start, Kameraflug übers Startfeld, Starterin zwischen
## den Autos (Arme hoch, bei GO runter), im Ziel laufen Fans auf die Straße und tanzen ums Auto.

const Track := preload("res://scripts/track_builder.gd")
const People := preload("res://scripts/people.gd")

const INTRO_TIME := 4.2

var track: Dictionary
var player: Node3D
var cam: Camera3D
var starter: MeshInstance3D
var start_crowd: Node3D
var intro_t := -1.0
var _keys: Array = []  # Kameraflug: [Position, Blickziel]
var _go_t := -1.0
var _arm := 0.6
var _arm_target := 0.6
var _fin_t := -1.0
var _fans: Array = []  # [Figur, Start, Ziel, Verzögerung]
var _orbit := 0.0
var _won := false


func setup(t: Dictionary, p: Node3D, start_lat: float) -> void:
	track = t
	player = p
	cam = Camera3D.new()
	cam.fov = 62.0
	cam.near = 0.05
	cam.far = GameState.q()["far"]
	add_child(cam)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var curve: Curve3D = track["curve"]
	var s: float = track["start"]
	# Publikum auf beiden Gehwegen rund um die Startlinie (hinter der Bande bei Drift-Kursen), Blick zur Straße
	var xfs := []
	var d := s - 24.0
	while d < s + 30.0:
		for side in [-1.0, 1.0]:
			var f := Track.frame_at(curve, d)
			var hw := Track.hw(track, d)
			for row in 3:
				# nicht in Laternen (alle LAMP_STEP ab 20 m, an der Bordsteinkante) oder Torpfeiler stellen
				var lamp := fposmod(d - 20.0, Track.LAMP_STEP)
				if row == 0 and (lamp < 1.2 or lamp > Track.LAMP_STEP - 1.2 or absf(d - s - 12.0) < 1.0):
					continue
				if rng.randf() < 0.72:
					var lat: float = side * (hw + 1.1 + row * 1.25 + rng.randf_range(-0.2, 0.2))
					var pos: Vector3 = f["pos"] + f["right"] * lat + f["fwd"] * rng.randf_range(-0.5, 0.5)
					pos.y = Track.CURB_H
					var look: Vector3 = -f["right"] * side + f["fwd"] * rng.randf_range(-0.4, 0.4)
					xfs.append(Transform3D(Basis.looking_at(look.normalized(), Vector3.UP), pos))
		d += 1.6
	start_crowd = People.crowd(self, xfs, [People.CHEER, People.CHEER, People.WAVE, People.CLAP], rng)
	# Starterin vor den Autos, mittig zwischen Spieler und Nachbar, Blick zu den Autos
	var fs := Track.frame_at(curve, s + 7.0)
	starter = People.single(self, 2, People.STARTER, Color(0.95, 0.95, 0.97), 0.25, 0.8)
	starter.transform = Transform3D(Basis.looking_at(-fs["fwd"], Vector3.UP), fs["pos"] + fs["right"] * start_lat)
	starter.material_override.set_shader_parameter("arm", _arm)
	# Kameraflug: hoch über der Strecke vorn, tief an der Starterin vorbei, seitlich am eigenen Auto, dann hinter das Auto
	var pl: Vector3 = player.global_position
	var pf: Vector3 = -player.global_basis.z
	var pr: Vector3 = player.global_basis.x
	var sp: Vector3 = starter.global_position
	_keys = [
		[_at(s + 48.0, -7.0, 11.0), _at(s, 0.0, 1.0)],
		[_at(s + 14.0, -3.5, 2.2), sp + Vector3(0, 1.4, 0)],
		[sp + pf * 1.5 + pr * 2.6 + Vector3(0, 1.3, 0), sp + Vector3(0, 1.5, 0)],
		[pl + pr * 4.5 + pf * 1.0 + Vector3(0, 1.1, 0), pl + Vector3(0, 0.6, 0)],
		[pl - pf * 5.4 + Vector3(0, 1.9, 0), pl + pf * 7.0 + Vector3(0, 1.1, 0)],
	]


func _at(d: float, lat: float, h: float) -> Vector3:
	var f := Track.frame_at(track["curve"], d)
	return f["pos"] + f["right"] * lat + Vector3(0, f["y"] + h, 0)


func start_intro() -> void:
	intro_t = 0.0
	cam.make_current()
	_place_cam(0.0)
	Sfx.play("crowd", -10.0)


func intro_done() -> bool:
	return intro_t >= INTRO_TIME


func skip_intro() -> void:
	intro_t = INTRO_TIME


## Countdown läuft: Arme hoch
func ready_set() -> void:
	_arm_target = 2.9


## GO: Arme mit Schwung runter, Publikum dreht durch
func go() -> void:
	_go_t = 0.0
	_arm_target = 0.35
	Sfx.play("crowd", -8.0, 1.05)


## Zieleinlauf: Kamera kreist ums Auto, Fans laufen von den Gehwegen herbei und tanzen (Sieg) oder klatschen
func finish(won: bool) -> void:
	_won = won
	_fin_t = 0.0
	_orbit = player.global_rotation.y
	cam.global_transform = player.cam.global_transform
	cam.make_current()
	if track["loop"] and start_crowd:
		People.set_mode(start_crowd, People.CHEER)


func _process(dt: float) -> void:
	if intro_t >= 0.0 and intro_t < INTRO_TIME:
		intro_t = minf(intro_t + dt, INTRO_TIME)
		_place_cam(intro_t / INTRO_TIME)
	# Starterin: Arme folgen dem Ziel (runter schnell, hoch etwas langsamer), bei GO nach vorn beugen
	_arm = move_toward(_arm, _arm_target, dt * (14.0 if _arm_target < _arm else 4.0))
	if starter:
		starter.material_override.set_shader_parameter("arm", _arm)
		var bow := 0.0
		if _go_t >= 0.0:
			_go_t += dt
			bow = clampf(_go_t / 0.15, 0.0, 1.0) * (1.0 - clampf((_go_t - 1.4) / 0.8, 0.0, 1.0))
			if _go_t > 2.2:
				_arm_target = 2.6  # danach jubelt sie den Autos hinterher
		starter.material_override.set_shader_parameter("bow", bow)
	if _fin_t >= 0.0:
		_update_finish(dt)


## Kamerafahrt als weiche Kurve durch die Schlüsselpunkte
func _place_cam(u: float) -> void:
	var n := _keys.size() - 1
	var x := smoothstep(0.0, 1.0, u) * n
	var i := mini(int(x), n - 1)
	var t := x - i
	var p0: Array = _keys[maxi(i - 1, 0)]
	var p1: Array = _keys[i]
	var p2: Array = _keys[i + 1]
	var p3: Array = _keys[mini(i + 2, n)]
	var pos: Vector3 = (p1[0] as Vector3).cubic_interpolate(p2[0], p0[0], p3[0], t)
	var look: Vector3 = (p1[1] as Vector3).cubic_interpolate(p2[1], p0[1], p3[1], t)
	cam.global_position = pos
	cam.look_at(look, Vector3.UP)


func _update_finish(dt: float) -> void:
	_fin_t += dt
	var car: Vector3 = player.global_position
	# Kamera: weich vom Verfolger in eine langsame Kreisfahrt ums Auto
	_orbit += dt * 0.32
	var want := car + Vector3(sin(_orbit), 0, cos(_orbit)) * 7.5 + Vector3(0, 2.3, 0)
	cam.global_position = cam.global_position.lerp(want, 1.0 - exp(-dt * 2.0))
	cam.look_at(car + Vector3(0, 0.7, 0), Vector3.UP)
	# Fans losschicken, sobald das Auto fast steht
	if _fans.is_empty() and (player.velocity.length() < 7.0 or _fin_t > 3.0):
		_spawn_fans()
	for fan in _fans:
		var mi: MeshInstance3D = fan[0]
		var k: float = clampf((_fin_t - fan[3]) / 1.6, 0.0, 1.0)
		if k <= 0.0:
			continue
		mi.visible = true
		var a: Vector3 = fan[1]
		var b: Vector3 = fan[2]
		var p := a.lerp(b, k)
		var face: Vector3 = (b - a) if k < 1.0 else (car - p)
		face.y = 0.0
		if face.length() > 0.05:
			mi.global_transform = Transform3D(Basis.looking_at(face.normalized(), Vector3.UP), p)
		else:
			mi.global_position = p
		if k >= 1.0 and not fan[4]:
			fan[4] = true
			var cd: Color = mi.material_override.get_shader_parameter("custom")
			cd.b = (People.DANCE if _won or randf() < 0.3 else People.CLAP) / 10.0
			mi.material_override.set_shader_parameter("custom", cd)


func _spawn_fans() -> void:
	var loc: Dictionary = player.loc
	if loc.is_empty():
		return
	var p: Dictionary = loc["path"]
	var c: Curve3D = p["curve"]
	var main: bool = p["id"] == 0
	var cd: float = loc["d"]
	var clat: float = loc["lat"]
	var half: float = (Track.hw(track, cd) if main else p["half_w"]) - 0.7
	var walk: float = Track.hw(track, cd) + 2.0 if main else p["half_w"] + 1.0
	var count := 12 if _won else 7
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in count:
		var ang := TAU * (i + rng.randf_range(-0.25, 0.25)) / count
		var r := rng.randf_range(3.4, 5.6)
		var td := cd + cos(ang) * r * 1.2
		var tl := clampf(clat + sin(ang) * r, -half, half)
		var side := 1.0 if sin(ang) > 0.0 else -1.0
		var from := Track.xform_at(c, td - rng.randf_range(4.0, 12.0) * signf(cos(ang) + 0.01), side * walk).origin
		var to := Track.xform_at(c, td, tl).origin
		var top: Color = People.SHIRTS[rng.randi() % People.SHIRTS.size()]
		var mi := People.single(self, rng.randi() % 2, People.RUN, top, rng.randf(), rng.randf())
		mi.visible = false
		mi.global_position = from
		_fans.append([mi, from, to, rng.randf_range(0.0, 0.7), false])
