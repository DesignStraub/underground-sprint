extends CharacterBody3D
## Gegner: fährt die Mittellinie mit Spurversatz ab, bremst vor Kurven, sucht Lücken im Verkehr,
## weicht Baustellen und dem Spieler aus. Rempler verschieben ihn, Verkehrsunfälle werfen ihn zurück.

const Builder := preload("res://scripts/car_builder.gd")
const Track := preload("res://scripts/track_builder.gd")

var curve: Curve3D
var player: Node3D
var traffic: Array = []
var blocks: Array = []
var player_progress := 0.0
var player_lateral := 0.0
var finish := 0.0
var progress := 0.0
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
var _steer := 0.0
var _last_yaw := 0.0
var _think := 0.0


func setup(car_id: String, cfg: Dictionary, start_progress: float, start_lane: float, top_speed: float, skill_factor: float) -> void:
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
	progress = start_progress
	lane = start_lane
	lane_target = start_lane
	top = top_speed
	skill = skill_factor
	global_transform = Track.xform_at(curve, progress, lane)
	_last_yaw = rotation.y


## Ist die Spur bei `lat` zwischen progress+from und progress+to frei?
func _lane_free(lat: float, from: float, to: float) -> bool:
	for t in traffic:
		var tl: float = t.lateral()
		if absf(tl - lat) > 2.6:
			continue
		var rel: float = t.progress - progress
		var closing: float = 1.6 if t.dir < 0.0 else 0.0  # Gegenverkehr kommt schneller näher
		if rel > from - t.length and rel < to * (1.0 + closing):
			return false
	for b in blocks:
		if absf(b["lane"] - lat) < 2.6 and b["to"] > progress + from and b["from"] < progress + to:
			return false
	return true


func _physics_process(dt: float) -> void:
	if curve == null:
		return
	var target := 0.0
	stun = maxf(stun - dt, 0.0)
	if running and progress < finish and stun <= 0.0:
		var f0 := Track.frame_at(curve, progress)
		var look := progress + 15.0 + speed * 1.3
		var f1 := Track.frame_at(curve, look)
		var bend := (f0["fwd"] as Vector3).angle_to(f1["fwd"])
		target = top * skill * lerpf(1.0, 0.5, clampf(bend / 1.1, 0.0, 1.0))
		var gap := player_progress - progress
		target *= clampf(1.0 + gap * 0.0025, 0.88, 1.15)

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
		# Steckt fest hinter etwas? Tempo anpassen.
		if not _lane_free(lane, 0.0, 6.0 + speed * 0.6):
			target = minf(target, 12.0)
	speed = move_toward(speed, target, dt * (accel if target > speed else 22.0))
	progress += speed * dt

	# Querbewegung: Spurwechsel + Rempel-Impulse
	lane_vel = move_toward(lane_vel, 0.0, dt * 6.0)
	lane += lane_vel * dt
	lane = move_toward(lane, lane_target, dt * 5.0)
	lane = clampf(lane, -Track.HALF_W + 1.0, Track.HALF_W - 1.0)

	_check_traffic_crash()

	var xf := Track.xform_at(curve, progress, lane)
	global_transform = xf
	var yaw_rate := wrapf(rotation.y - _last_yaw, -PI, PI) / maxf(dt, 0.0001)
	_last_yaw = rotation.y
	_steer = lerpf(_steer, clampf(-yaw_rate * 2.0 + lane_vel * 0.1, -1.0, 1.0), dt * 6.0)
	Builder.animate(model, speed, _steer, _steer * 0.04, 0.0, false, dt)


func _player_blocks(lat: float) -> bool:
	var rel := player_progress - progress
	return absf(player_lateral - lat) < 2.4 and rel > 0.0 and rel < 10.0 + speed * 0.5


func _check_traffic_crash() -> void:
	for t in traffic:
		if absf(t.lateral() - lane) < 2.0 and absf(t.progress - progress) < (t.length + length) / 2.0:
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
	lane_vel += push.dot(right) * 0.7
	lane_target = clampf(lane + push.dot(right) * 0.4, Track.LANES[0], Track.LANES[3])
	speed = maxf(speed + push.dot(fwd) * 0.6, 0.0)
	if push.length() > 12.0:
		stun = 0.4
