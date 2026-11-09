extends CharacterBody3D
## Ziviler Verkehr: fährt langsam auf seiner Spur (rechts mit, links Gegenverkehr),
## weicht gesperrten Spuren aus, bremst für den Spieler und hält am Bahnübergang. Bei einem Crash wird er weggeschleudert,
## bei einem harten Treffer hebt er ab, überschlägt sich und bleibt auf Seite oder Dach liegen.
## Fährt auf der Hauptstraße (mit Mittelstreifen-Versatz) oder in einer Gabelung (path_id).
## Ton: race.gd schaltet bei den nächsten paar Autos Motor und Abrollen ein (sound()), mit Dopplereffekt im Vorbeifahren.

const Builder := preload("res://scripts/car_builder.gd")
const Track := preload("res://scripts/track_builder.gd")
const EngineAudio := preload("res://scripts/engine_audio.gd")
## Motorklang: ruhiger Vierzylinder; der Bus ein rauer Sechszylinder-Diesel
const SND_CAR := {"cyl": 4, "harm": [1.0, 0.4, 0.18, 0.06], "sub": 0.25, "turbo": 0.0, "rough": 0.15}
const SND_BUS := {"cyl": 6, "harm": [1.0, 0.62, 0.36, 0.16], "sub": 0.5, "turbo": 0.0, "rough": 0.6}

const KINDS := ["sedan", "sedan", "sedan", "taxi", "van", "van", "bus"]
const COLORS := [Color(0.5, 0.5, 0.52), Color(0.15, 0.15, 0.17), Color(0.25, 0.3, 0.4), Color(0.45, 0.1, 0.1),
	Color(0.7, 0.7, 0.68), Color(0.2, 0.3, 0.2), Color(0.35, 0.3, 0.25)]

var curve: Curve3D
var track: Dictionary
var path_id := 0  # 0 = Hauptstraße, sonst Gabelung
var blocks: Array = []
var progress := 0.0
var lane := 2.25
var dir := 1.0  # +1 mit uns, -1 Gegenverkehr
var speed := 13.0
var base_speed := 13.0
var length := 4.5
var track_length := 0.0
var wrecked := false
var player_progress := 0.0  # Spieler auf seinem Weg (Meter ab Wegbeginn)
var player_lateral := 100.0
var player_path := 0
var player_pos := Vector3.ZERO  # Spieler in der Welt (race.gd): weit Entferntes wird ausgedünnt
var crossing: Node
var _lane_cur := 2.25
var _wreck_vel := Vector3.ZERO
var _wreck_spin := 0.0
var velocity_vec := Vector3.ZERO
var _wreck_vy := 0.0
var _wreck_roll := 0.0
var _wreck_roll_v := 0.0
var _wreck_ground := 0.0
var _far_d2 := 0.0
var kind := ""
var _snd: AudioStreamPlayer3D
var _far_t := 0.0


func setup(kind_: String, rng: RandomNumberGenerator) -> void:
	kind = kind_
	add_to_group("traffic")
	_far_d2 = pow(GameState.view_distance() + 80.0, 2.0)
	_far_t = rng.randf() * 0.5
	_lane_cur = lane
	collision_layer = 2
	collision_mask = 0
	var col: Color = COLORS[rng.randi() % COLORS.size()]
	var size := Vector3(1.8, 1.5, 4.5)
	match kind:
		"sedan":
			_body(Vector2(1.8, 4.5), 0.65, col, Vector2(1.6, 2.2), 0.5)
		"taxi":
			_body(Vector2(1.8, 4.6), 0.65, Color(0.95, 0.75, 0.05), Vector2(1.6, 2.3), 0.5)
			Builder._add(self, Builder.box(Vector3(0.7, 0.22, 0.3)), Builder.mat(Color(1, 1, 0.8), 0, 0.4, Color(1, 0.95, 0.6), 2.5), Vector3(0, 1.62, 0.2))
		"van":
			size = Vector3(2.0, 2.3, 5.2)
			_body(Vector2(2.0, 5.2), 1.6, Color(0.85, 0.85, 0.85) if rng.randf() < 0.6 else col, Vector2(1.9, 1.0), 0.45, -1.9)
		"bus":
			size = Vector3(2.5, 3.2, 11.0)
			_body(Vector2(2.5, 11.0), 2.6, Color(0.9, 0.85, 0.1) if rng.randf() < 0.5 else Color(0.85, 0.85, 0.85), Vector2.ZERO, 0.0)
			var win := Builder.mat(Color(0.1, 0.1, 0.1), 0.5, 0.2, Color(1, 0.9, 0.6), 1.2)
			for s in [-1, 1]:
				Builder._add(self, Builder.box(Vector3(0.05, 0.9, 9.0)), win, Vector3(s * 1.26, 2.1, 0.5))
			Builder._add(self, Builder.box(Vector3(2.3, 1.0, 0.05)), win, Vector3(0, 2.0, -5.51))
	length = size.z
	Builder.merge_static(self)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position.y = size.y / 2.0 + 0.1
	add_child(cs)


func _body(fp: Vector2, h: float, col: Color, cabin: Vector2, cabin_h: float, cabin_z := 0.2) -> void:
	var paint := Builder.gloss_mat(col, 0.3, 0.4)
	var glass := Builder.mat(Color(0.03, 0.04, 0.06), 0.7, 0.1)
	var clear := 0.25
	Builder._add(self, Builder.tapered_box(fp, fp - Vector2(0.08, 0.2), h, 0.0), paint, Vector3(0, clear, 0))
	if cabin.x > 0.0:
		Builder._add(self, Builder.tapered_box(cabin, cabin - Vector2(0.25, 0.5), cabin_h, 0.1), glass, Vector3(0, clear + h, cabin_z))
	var head := Builder.mat(Color(1, 1, 0.9), 0, 0.3, Color(1, 0.95, 0.8), 4.0)
	var tail := Builder.mat(Color(0.6, 0, 0), 0, 0.3, Color(1, 0.05, 0.02), 3.0)
	for s in [-1, 1]:
		Builder._add(self, Builder.box(Vector3(0.35, 0.15, 0.05)), head, Vector3(s * (fp.x / 2 - 0.3), clear + 0.35, -fp.y / 2 - 0.01))
		Builder._add(self, Builder.box(Vector3(0.35, 0.15, 0.05)), tail, Vector3(s * (fp.x / 2 - 0.3), clear + 0.4, fp.y / 2 + 0.01))
	var tire := Builder.mat(Color(0.05, 0.05, 0.05), 0, 0.9)
	for s in [-1, 1]:
		for z in [-1, 1]:
			var c := CylinderMesh.new()
			c.top_radius = 0.33
			c.bottom_radius = 0.33
			c.height = 0.24
			c.radial_segments = 10
			Builder._add(self, c, tire, Vector3(s * (fp.x / 2 - 0.1), 0.33, z * (fp.y / 2 - 0.9))).rotation_degrees.z = 90


## Klang vorrechnen (race.gd beim Laden): sonst rechnete das erste nahe Auto mitten im Rennen und es ruckelte
static func prepare_sound() -> void:
	_loop_for("sedan")
	_loop_for("bus")


static func _loop_for(k: String) -> AudioStreamWAV:
	if k == "bus":
		return EngineAudio.render_loop(SND_BUS, 1300.0, 0.4, 0.9)
	return EngineAudio.render_loop(SND_CAR, 2100.0, 0.4, 0.9)


## Motor und Abrollen an/aus (race.gd: nur die nächsten paar Autos)
func sound(on: bool, bus: String) -> void:
	if wrecked:
		on = false
	if _snd == null:
		if not on:
			return
		var bus_k := kind == "bus"
		var w := _loop_for(kind)
		_snd = AudioStreamPlayer3D.new()
		_snd.stream = w
		_snd.unit_size = 7.0 if bus_k else 5.0
		_snd.max_distance = 100.0
		_snd.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		_snd.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		_snd.volume_db = -16.0 if bus_k else -19.0  # leiser als der eigene Motor, auch knapp daneben
		_snd.position.y = 0.6
		add_child(_snd)
	if on == _snd.playing:
		return
	_snd.bus = bus
	if on:
		_snd.play(randf() * _snd.stream.get_length())
	else:
		_snd.stop()


func _physics_process(dt: float) -> void:
	if _snd and _snd.playing:
		_snd.pitch_scale = clampf(0.8 + 0.4 * speed / maxf(base_speed, 1.0), 0.6, 1.4)
	if wrecked:
		global_position += _wreck_vel * dt
		_wreck_vel = _wreck_vel.move_toward(Vector3.ZERO, 9.0 * dt)
		rotate_y(_wreck_spin * dt)
		_wreck_spin = move_toward(_wreck_spin, 0.0, 2.5 * dt)
		velocity_vec = _wreck_vel
		if _wreck_vel.length_squared() > 0.01:
			# Lage für KI und Verkehr nachführen, damit sie um das Wrack herumfahren, wo es wirklich liegt
			progress = curve.get_closest_offset(global_position)
			var f := Track.frame_at(curve, progress)
			var lat: float = (global_position - f["pos"]).dot(f["right"])
			_lane_cur = Track.logical_lat(track, progress, lat) if path_id == 0 else lat
		if _wreck_roll_v != 0.0 or global_position.y > _wreck_ground + 0.01:
			_wreck_vy -= 18.0 * dt
			global_position.y += _wreck_vy * dt
			rotate_object_local(Vector3.BACK, _wreck_roll_v * dt)
			_wreck_roll += _wreck_roll_v * dt
			if global_position.y <= _wreck_ground and _wreck_vy < 0.0:
				global_position.y = _wreck_ground
				if _wreck_vy < -3.0:
					_wreck_vy *= -0.3  # schlägt auf und springt noch einmal
					_wreck_roll_v *= 0.5
				else:
					# liegen bleiben: auf Rädern, Seite oder Dach
					var flat := roundf(_wreck_roll / (PI / 2.0)) * (PI / 2.0)
					rotate_object_local(Vector3.BACK, flat - _wreck_roll)
					_wreck_roll = flat
					_wreck_roll_v = 0.0
					_wreck_vy = 0.0
		return

	# Gesperrte Spur (Rampe am Bahnübergang)? Dann eine Spur weiter nach innen.
	var target_lane := lane
	for b in blocks:
		if absf(b["lane"] - lane) < 1.0 and progress > b["from"] - 25.0 and progress < b["to"] + 10.0:
			target_lane = lane - signf(lane) * 4.5
	_lane_cur = move_toward(_lane_cur, target_lane, dt * 2.0)

	# Spieler direkt vor mir? Bremsen.
	var target := base_speed
	var ahead := (player_progress - progress) * dir
	if player_path == path_id and absf(player_lateral - _lane_cur) < 2.6 and ahead > 0.0 and ahead < length / 2.0 + 12.0:
		target = 0.0
	# Schranken unten? Vor der Haltelinie stehen bleiben.
	if crossing and path_id == 0 and crossing.is_blocked():
		var stop: float = (crossing.d_cross - 12.0 - progress) if dir > 0.0 else (progress - crossing.d_cross - 12.0)
		if stop > -2.0 and stop < 140.0:
			target = minf(target, sqrt(2.0 * 7.0 * maxf(stop, 0.0)))
	speed = move_toward(speed, target, dt * (4.0 if target > speed else 10.0))
	progress += speed * dt * dir
	if path_id == 0 and track.get("loop", false):
		progress = fposmod(progress, track_length)  # Rundkurs: einfach weiterfahren
	elif path_id != 0:
		# Gabelung: am Ende wieder am Anfang einsetzen
		if progress > track_length - 4.0:
			progress = 6.0
		elif progress < 4.0:
			progress = track_length - 6.0
	elif progress > track_length - 10.0:
		# Am Streckenende neu einsetzen (außer Sicht)
		progress = 40.0
	elif progress < 40.0:
		progress = track_length - 10.0
	# Außer Sichtweite: unsichtbar und Lage nur zweimal pro Sekunde neu (spart im Browser viel Rechenzeit)
	var far := global_position.distance_squared_to(player_pos) > _far_d2
	visible = not far
	if far:
		_far_t -= dt
		if _far_t > 0.0:
			return
		_far_t = 0.5
	place()


## Auf die Straße setzen (Spur, Fahrtrichtung, Steigung)
func place() -> void:
	var lat := Track.lane_lat(track, progress, _lane_cur) if path_id == 0 else _lane_cur
	var xf := Track.xform_at(curve, progress, lat, true)
	if dir < 0.0:
		xf.basis = xf.basis * Basis(Vector3.UP, PI)  # um die eigene Hochachse: bergab bleibt bergab
	var fwd := -xf.basis.z
	velocity_vec = fwd * speed
	global_transform = xf


## Unfall: wird mit (einem Teil) der Aufprallgeschwindigkeit weggeschoben und dreht sich.
func knock(v: Vector3) -> void:
	if not wrecked:
		wrecked = true
		_wreck_vel = velocity_vec
		_wreck_ground = global_position.y
	_wreck_vel += Vector3(v.x, 0, v.z) * 0.6
	_wreck_spin += randf_range(-1.0, 1.0) * clampf(v.length() / 10.0, 0.5, 3.0)
	if v.length() > 20.0 and _wreck_roll_v == 0.0 and global_position.y <= _wreck_ground + 0.01:
		_wreck_vy = clampf(v.length() * 0.18, 3.5, 7.0)
		_wreck_roll_v = randf_range(4.0, 7.0) * (1.0 if randf() < 0.5 else -1.0)


## Für KI/Verkehrslogik: aktuelle Querposition auf der Strecke
func lateral() -> float:
	return _lane_cur
