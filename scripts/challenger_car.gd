extends "res://scripts/traffic_car.gd"
## Herausforderer in der Open World (wie die Outrun-Gegner in Underground 2): ein getuntes Rennauto, das ab und zu
## auf der Autobahn auftaucht, den Spieler überholt und dann vor ihm herfährt. Fährt man dicht auf, startet Enter
## ein Duell (world.gd: wer 300 m Vorsprung hat, gewinnt). Fährt wie der Verkehr die Autobahnstücke entlang (auch
## über ihre Grenzen), wechselt aber zügig die Spur, wenn vor ihm jemand langsamer ist, und wird beim Rempeln nicht
## zum Wrack: er wird geschoben und verliert Tempo, wie die Gegner im Rennen (Gruppe "racer", bump()).

var car_id := ""
var others: Array = []  # Verkehr (world.traffic): freie Spur suchen
var _lc_cool := 0.0
var _push_lat := 0.0


func setup_racer(id: String, cfg: Dictionary) -> void:
	kind = "racer"
	car_id = id
	add_to_group("racer")
	_far_d2 = pow(GameState.view_distance() + 80.0, 2.0)
	_lane_cur = lane
	collision_layer = 2
	collision_mask = 0
	var model := Builder.build(car_id, cfg)
	add_child(model)
	length = model.get_meta("length")
	_half_w = float(model.get_meta("width")) / 2.0
	mass = 1.3
	lane_rate = 4.5
	accel_up = 6.5
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(_half_w * 2.0, 1.2, length)
	cs.shape = bs
	cs.position.y = 0.7
	add_child(cs)
	var bank := EngineAudio.bank(car_id)
	if not bank.is_empty():
		# Motor: Volllast-Schleife, Tonhöhe folgt dem Tempo (wie die Gegner im Rennen, nur einfacher)
		_snd = AudioStreamPlayer3D.new()
		_snd.stream = bank["on"][7]  # 6100/min
		_snd.unit_size = 6.0
		_snd.max_distance = 160.0
		_snd.volume_db = -14.0
		_snd.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP
		_snd.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		_snd.position = Vector3(0, 0.5, length / 2.0)
		add_child(_snd)


## world.gd schaltet den Klang für die nächsten Autos ein und aus; der Herausforderer ist immer zu hören
func sound(_on: bool, bus: String) -> void:
	if _snd == null:
		return
	_snd.bus = bus
	if not _snd.playing:
		_snd.play(randf() * _snd.stream.get_length())


func _physics_process(dt: float) -> void:
	_lc_cool -= dt
	if _lc_cool <= 0.0 and is_instance_valid(leader) and not leader.is_queued_for_deletion():
		var lg: float = (leader.progress - progress) * dir - (length + leader.length) / 2.0
		var lv: float = 0.0 if leader.wrecked else float(leader.speed)
		if lg < 55.0 and lv < base_speed - 2.0 and absf(leader.lateral() - _lane_cur) < 2.6:
			_change_lane()
	# vom Spieler gerempelt: kurz seitlich versetzt, dann zurück in die Spur
	if absf(_push_lat) > 0.01:
		_lane_cur += _push_lat * dt
		_push_lat = move_toward(_push_lat, 0.0, dt * 8.0)
	super(dt)
	if _snd and _snd.playing:
		# Drehzahl im 6. Gang ungefähr mit dem Tempo (die Schleife liegt bei 6100/min)
		_snd.pitch_scale = clampf((2200.0 + 4400.0 * speed / 60.0) / 6100.0, 0.45, 1.25)
	if player_path == path_id and absf(player_lateral - _lane_cur) < 2.6:
		var ahead := (player_progress - progress) * dir
		if ahead > 0.0 and ahead < 40.0 and speed < base_speed - 3.0 and _lc_cool <= 0.0:
			_change_lane()  # der Spieler blockiert: vorbei


## Freie Nachbarspur in Fahrtrichtung suchen (innen zuerst: dort ist es schneller)
func _change_lane() -> void:
	_lc_cool = 0.8
	var lanes: Array = [lane - 4.5 * signf(lane), lane + 4.5 * signf(lane)]
	for cand in lanes:
		if signf(cand) != signf(lane) or absf(cand) > 11.3 or absf(cand) < 2.0:
			continue
		if _lane_free(cand):
			lane = cand
			_lc_cool = 1.6
			return


func _lane_free(cand: float) -> bool:
	if player_path == path_id and absf(player_lateral - cand) < 2.8:
		var pa := (player_progress - progress) * dir
		if pa > -10.0 and pa < 25.0:
			return false
	for t in others:
		if t == self or not is_instance_valid(t) or t.get_parent() != get_parent() or t.path_id != path_id:
			continue
		if absf(t.lateral() - cand) > 2.8:
			continue
		var rel: float = (t.progress - progress) * dir
		if rel > -12.0 and rel < 50.0:
			return false
	return true


## Gerempelt (player_car: Gruppe "racer"): Tempo nach Impuls, seitlich versetzt, kein Wrack
func bump(player_vel: Vector3, n: Vector3) -> void:
	var fwd := -global_basis.z
	var right := global_basis.x
	var push := -n * clampf((player_vel - fwd * speed).dot(-n), 0.0, 25.0)
	speed = maxf(speed + push.dot(fwd) * 0.6, 0.0)
	_push_lat += push.dot(right) * 0.5 * dir


func knock(_v: Vector3) -> void:
	pass


func push(dv: Vector3) -> void:
	speed = maxf(speed - dv.length() * 0.3, 0.0)
