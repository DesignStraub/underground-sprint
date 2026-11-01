extends CharacterBody3D
## Gegner: fährt Wege (Hauptstraße oder Abkürzung) mit Spurversatz ab, bremst vor Kurven, sucht Lücken im Verkehr,
## weicht Baustellen und dem Spieler aus, nimmt manchmal Abkürzungen, springt über Rampen.
## Am Bahnübergang hält er, wenn der Zug kommt – oder nimmt Anlauf über die Rampe.

const Builder := preload("res://scripts/car_builder.gd")
const Track := preload("res://scripts/track_builder.gd")
const GRAVITY := 30.0
const MAX_LAUNCH_VY := 10.0  # kurze, knackige Sprünge statt Weitflug

var track: Dictionary
var path: Dictionary
var d := 0.0  # Position auf dem aktuellen Weg
var progress := 0.0  # Rennfortschritt in Metern der Hauptstraße
var player: Node3D
var traffic: Array = []
var crossing: Node
var player_progress := 0.0
var player_lateral := 0.0
var player_path := 0
var finish := 0.0
var lane := 0.0
var lane_target := 0.0
var lane_vel := 0.0
var speed := 0.0
var top := 55.0
var accel := 9.0
var skill := 1.0
var running := false
var finish_time := -1.0
var stun := 0.0
var model: Node3D
var length := 4.4
var shortcut_rate := 0.6
var jumper := true
var y := 0.0
var vy := 0.0
var airborne := false
var _ground_vy := 0.0
var _steer := 0.0
var _last_yaw := 0.0
var _think := 0.0
var _decided := {}


func setup(track_: Dictionary, car_id: String, cfg: Dictionary, start_progress: float, start_lane: float, top_speed: float, skill_factor: float) -> void:
	track = track_
	path = track["paths"][0]
	add_to_group("racer")
	collision_layer = 2
	collision_mask = 0
	model = Builder.build(car_id, cfg)
	add_child(model)
	length = model.get_meta("length")
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(model.get_meta("width"), 1.2, length)
	col.shape = shape
	col.position.y = 0.7
	add_child(col)
	d = start_progress
	progress = d
	lane = start_lane
	lane_target = start_lane
	top = top_speed
	skill = skill_factor
	jumper = randf() < 0.7
	shortcut_rate = randf_range(0.35, 0.8)
	global_transform = Track.xform_at(path["curve"], d, lane)
	_last_yaw = rotation.y


## Ist die Spur bei `lat` zwischen d+from und d+to frei? (nur Hauptstraße)
func _lane_free(lat: float, from: float, to: float) -> bool:
	for t in traffic:
		var tl: float = t.lateral()
		if absf(tl - lat) > 2.6:
			continue
		var rel: float = t.progress - d
		var closing: float = 1.6 if t.dir < 0.0 else 0.0  # Gegenverkehr kommt schneller näher
		if rel > from - t.length and rel < to * (1.0 + closing):
			return false
	for b in track["blocks"]:
		if absf(b["lane"] - lat) < 2.6 and b["to"] > d + from and b["from"] < d + to:
			return false
	return true


func _player_blocks(lat: float) -> bool:
	if player_path != path["id"]:
		return false
	var rel := player_progress - progress
	return absf(player_lateral - lat) < 2.4 and rel > 0.0 and rel < 10.0 + speed * 0.5


func _physics_process(dt: float) -> void:
	if track.is_empty():
		return
	var c: Curve3D = path["curve"]
	var on_main: bool = path["id"] == 0
	var target := 0.0
	stun = maxf(stun - dt, 0.0)
	if running and progress < finish and stun <= 0.0:
		var f0 := Track.frame_at(c, d)
		var f1 := Track.frame_at(c, d + 15.0 + speed * 1.3)
		var bend := (f0["fwd"] as Vector3).angle_to(f1["fwd"])
		target = top * skill * lerpf(1.0, 0.5, clampf(bend / 1.1, 0.0, 1.0))
		var gap := player_progress - progress
		target *= clampf(1.0 + gap * 0.0025, 0.88, 1.15)
		if on_main:
			# Ein paar Mal pro Sekunde: Spur wählen
			_think -= dt
			if _think <= 0.0:
				_think = 0.15
				var ahead := 12.0 + speed * 1.4
				if not _lane_free(lane_target, -2.0, ahead) or _player_blocks(lane_target):
					var best := lane_target
					var best_cost := 1e9
					for l in Track.LANES:
						if _lane_free(l, -3.0, ahead) and not _player_blocks(l):
							var cost := absf(l - lane)
							if cost < best_cost:
								best_cost = cost
								best = l
					lane_target = best
			if not _lane_free(lane, 0.0, 6.0 + speed * 0.6):
				target = minf(target, 12.0)
			# Bahnübergang
			if crossing and crossing.is_blocked():
				var to_cross: float = crossing.d_cross - d
				if to_cross > 0.0 and to_cross < 260.0:
					if jumper:
						lane_target = Track.LANES[3]
						target = maxf(target, 40.0)
					else:
						target = minf(target, sqrt(2.0 * 18.0 * maxf(to_cross - 14.0, 0.0)))
		else:
			lane_target = 0.0
			if path["kind"] == "lake":
				target = maxf(target, 36.0)  # Anlauf für die Schanze
			else:
				target = minf(target, 30.0)  # enge Gasse
	speed = move_toward(speed, target, dt * (accel if target > speed else 22.0))
	var prev_d := d
	d += speed * dt

	# Abkürzung nehmen?
	if on_main:
		for p in track["paths"]:
			if p["kind"] != "alley" and p["kind"] != "lake":
				continue
			if prev_d < p["from"] and d >= p["from"] and not _decided.has(p["id"]):
				_decided[p["id"]] = true
				if randf() < shortcut_rate:
					path = p
					d = d - p["from"]
					lane = clampf(lane, -p["half_w"] + 1.5, p["half_w"] - 1.5)
					lane_target = 0.0
					break
	elif d >= path["length"] - 0.5:
		var back: float = path["to"]
		path = track["paths"][0]
		d = back
		lane_target = clampf(lane, Track.LANES[0], Track.LANES[3])
	c = path["curve"]
	on_main = path["id"] == 0
	progress = d if on_main else lerpf(path["from"], path["to"], clampf(d / path["length"], 0.0, 1.0))

	# Querbewegung: Spurwechsel + Rempel-Impulse
	var half: float = path["half_w"]
	lane_vel = move_toward(lane_vel, 0.0, dt * 6.0)
	lane += lane_vel * dt
	lane = move_toward(lane, lane_target, dt * 5.0)
	lane = clampf(lane, -half + 1.0, half - 1.0)

	if on_main:
		_check_traffic_crash()
	_update_vertical(dt)

	var xf := Track.xform_at(c, d, lane)
	xf.origin.y = y
	global_transform = xf
	var yaw_rate := wrapf(rotation.y - _last_yaw, -PI, PI) / maxf(dt, 0.0001)
	_last_yaw = rotation.y
	_steer = lerpf(_steer, clampf(-yaw_rate * 2.0 + lane_vel * 0.1, -1.0, 1.0), dt * 6.0)
	var pitch := 0.0
	if airborne:
		pitch = clampf(atan2(vy, maxf(speed, 1.0)) * 0.8, -0.35, 0.3)
	Builder.animate(model, speed, _steer, _steer * 0.04, pitch, false, dt)


func _update_vertical(dt: float) -> void:
	var g := Track.ground_path(track, path["id"], d, lane)
	var gh: float = g["h"]
	if airborne:
		vy -= GRAVITY * dt
		y += vy * dt
		if y <= gh:
			y = gh
			airborne = false
			vy = 0.0
		return
	if gh < y - 0.35 and speed > 6.0:
		airborne = true
		vy = minf(_ground_vy, MAX_LAUNCH_VY)
		return
	var prev := y
	y = gh
	_ground_vy = (y - prev) / maxf(dt, 0.0001)


func _check_traffic_crash() -> void:
	for t in traffic:
		if absf(t.lateral() - lane) < 2.0 and absf(t.progress - d) < (t.length + length) / 2.0 and not airborne:
			if stun <= 0.0:
				var fwd := -global_basis.z
				t.knock(fwd * speed)
				speed *= 0.2
				stun = 1.2
				lane_vel += signf(lane - t.lateral()) * 3.0


## Rempler vom Spieler. n zeigt vom Gegner zum Spieler.
func bump(player_vel: Vector3, n: Vector3) -> void:
	var fwd := -global_basis.z
	var right := global_basis.x
	var my_vel := fwd * speed
	var push := -n * clampf((player_vel - my_vel).dot(-n), 0.0, 25.0)
	var half: float = path["half_w"]
	lane_vel += push.dot(right) * 0.7
	lane_target = clampf(lane + push.dot(right) * 0.4, -half + 1.5, half - 1.5)
	speed = maxf(speed + push.dot(fwd) * 0.6, 0.0)
	if push.length() > 12.0:
		stun = 0.4
