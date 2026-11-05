extends CharacterBody3D
## Gegner: fährt Wege (Hauptstraße oder Abkürzung) mit Spurversatz ab, bremst vor Kurven, sucht Lücken im Verkehr,
## weicht gesperrten Spuren und dem Spieler aus, nimmt manchmal Abkürzungen, springt über Rampen.
## Am Bahnübergang hält er, wenn der Zug kommt – oder nimmt Anlauf über die Rampe.
## Auf Boulevards bleibt er auf seiner Seite des Mittelstreifens; in Gabelungen fährt er rechts und bremst hinter Verkehr.
## Berührt er den Spieler oder einen anderen Gegner, fährt er nicht hindurch: von hinten bleibt er an der Stoßstange und
## schiebt mit (gleich schwere Autos teilen sich das Tempo), seitlich drücken sich beide auseinander; wer blockiert
## wird, sucht eine andere Spur.

const Builder := preload("res://scripts/car_builder.gd")
const Track := preload("res://scripts/track_builder.gd")
const GRAVITY := 30.0
const MAX_LAUNCH_VY := 10.0  # kurze, knackige Sprünge statt Weitflug

var track: Dictionary
var path: Dictionary
var d := 0.0  # Position auf dem aktuellen Weg
var progress := 0.0  # Rennfortschritt in Metern der Hauptstraße (innerhalb der Runde)
var lap := 0
var total := 0.0  # Runden * Länge + progress
var player: Node3D
var traffic: Array = []
var crossing: Node
var player_progress := 0.0  # Spieler auf der Hauptstraße (innerhalb der Runde)
var player_total := 0.0  # Spieler-Gesamtfortschritt (für das Gummiband)
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
var rubber := Vector2(0.88, 1.07)  # Gummiband: Tempofaktor kleinster/größter Wert (Spieler weit hinten/vorn)
var drag := false  # Drag: Beschleunigung lässt mit dem Tempo nach (wie Gänge und Luftwiderstand)
var running := false
var finish_time := -1.0
var stun := 0.0
var model: Node3D
var length := 4.4
var shortcut_rate := 0.6
var shortcut_k := 1.0  # Schwierigkeit: auf Leicht nehmen Gegner Abkürzungen selten (Neulinge kennen sie noch nicht)
var jumper := true
var y := 0.0
var vy := 0.0
var airborne := false
var _ground_vy := 0.0
var _steer := 0.0
var _last_yaw := 0.0
var _think := 0.0
var _decided := {}
var rivals: Array = []  # alle Gegner (race.gd), für Kontakte untereinander
var width := 1.8
var _blocked_t := 0.0  # wie lange schon jemand direkt vor der Stoßstange klebt
var _blocker_lat := 0.0


func setup(track_: Dictionary, car_id: String, cfg: Dictionary, start_progress: float, start_lane: float, top_speed: float, skill_factor: float) -> void:
	track = track_
	path = track["paths"][0]
	add_to_group("racer")
	collision_layer = 2
	collision_mask = 0
	model = Builder.build(car_id, cfg)
	add_child(model)
	length = model.get_meta("length")
	width = model.get_meta("width")
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(model.get_meta("width"), 1.2, length)
	col.shape = shape
	col.position.y = 0.7
	add_child(col)
	d = start_progress
	progress = d
	total = d
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
		if t.path_id != 0:
			continue
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
	if running and total < finish and stun <= 0.0:
		var f0 := Track.frame_at(c, d)
		var f1 := Track.frame_at(c, d + 15.0 + speed * 1.3)
		var bend := (f0["fwd"] as Vector3).angle_to(f1["fwd"])
		target = top * skill * lerpf(1.0, 0.5, clampf(bend / 1.1, 0.0, 1.0))
		var gap := player_total - total
		target *= clampf(1.0 + gap * 0.0025, rubber.x, rubber.y)
		if on_main:
			# Ein paar Mal pro Sekunde: Spur wählen
			_think -= dt
			if _think <= 0.0:
				_think = 0.15
				var ahead := 12.0 + speed * 1.4
				var split := Track.median_at(track, d) > 0.3 or Track.median_at(track, d + ahead) > 0.3
				if _blocked_t > 0.6:
					# klebt hinter jemandem: auf die Spur mit dem meisten Abstand zum Hindernis ausweichen
					var far := lane_target
					for l in Track.LANES:
						if split and signf(l) != signf(lane):
							continue
						if absf(l - _blocker_lat) > absf(far - _blocker_lat) and absf(l - _blocker_lat) > 3.0:
							far = l
					lane_target = far
				elif not _lane_free(lane_target, -2.0, ahead) or _player_blocks(lane_target):
					var best := lane_target
					var best_cost := 1e9
					# Mittelstreifen in der Nähe: nur Spuren auf der eigenen Seite
					for l in Track.LANES:
						if split and signf(l) != signf(lane):
							continue
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
			elif path["kind"] == "fork":
				# Gabelung: rechte Spur, hinter Verkehr in gleicher Richtung abbremsen
				lane_target = 2.4
				target = minf(target, 36.0)
				for t in traffic:
					if t.path_id == path["id"] and t.dir > 0.0 and not t.wrecked:
						var t_gap: float = t.progress - d
						if t_gap > 0.0 and t_gap < 16.0 + speed * 0.4:
							target = minf(target, t.speed * 0.9)
				for t in traffic:
					# Wrack auf der eigenen Spur: über die Gegenfahrbahn vorbei
					if t.path_id == path["id"] and t.wrecked and absf(t.lateral() - 2.4) < 2.4:
						var w_gap: float = t.progress - d
						if w_gap > -(t.length + length) * 0.5 - 1.0 and w_gap < 20.0 + speed * 0.6:
							lane_target = -2.4
			else:
				target = minf(target, 30.0)  # enge Gasse
	# oben heraus zieht auch ein Gegner schwächer (Gänge, Luftwiderstand), sonst hängt er dich nach jeder Kurve ab
	var acc := accel * maxf(1.0 - 0.4 * pow(speed / maxf(top, 1.0), 2.0), 0.45)
	if drag:
		acc = accel * 0.8 * maxf(1.0 - pow(speed / maxf(top * skill, 1.0), 1.6), 0.05)
	acc *= 0.6 + 0.4 * minf(speed / 8.0, 1.0)  # Anfahren wie beim Spieler: erst greifen die Reifen nicht voll
	speed = move_toward(speed, target, dt * (acc if target > speed else 22.0))
	var prev_d := d
	d += speed * dt

	# Abkürzung nehmen?
	if on_main:
		for p in track["paths"]:
			if p["kind"] != "alley" and p["kind"] != "lake" and p["kind"] != "fork":
				continue
			if prev_d < p["from"] and d >= p["from"] and not _decided.has(p["id"]):
				_decided[p["id"]] = true
				if randf() < (0.5 if p["kind"] == "fork" else shortcut_rate) * shortcut_k:
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
	_contacts(dt, c, on_main, target)
	if on_main and track["loop"] and d >= track["length"]:
		d -= track["length"]
		lap += 1
		_decided.clear()  # neue Runde, neue Entscheidungen
	progress = d if on_main else lerpf(path["from"], path["to"], clampf(d / path["length"], 0.0, 1.0))
	total = lap * track["length"] + progress

	# Querbewegung: Spurwechsel + Rempel-Impulse
	var half: float = path["half_w"]
	lane_vel = move_toward(lane_vel, 0.0, dt * 6.0)
	lane += lane_vel * dt
	lane = move_toward(lane, lane_target, dt * 5.0)
	lane = clampf(lane, -half + 1.0, half - 1.0)

	_check_traffic_crash()
	_update_vertical(dt)

	var xf := Track.xform_at(c, d, Track.lane_lat(track, d, lane) if on_main else lane)
	xf.origin.y = y
	global_transform = xf
	var yaw_rate := wrapf(rotation.y - _last_yaw, -PI, PI) / maxf(dt, 0.0001)
	_last_yaw = rotation.y
	_steer = lerpf(_steer, clampf(-yaw_rate * 2.0 + lane_vel * 0.1, -1.0, 1.0), dt * 6.0)
	var pitch := 0.0
	if airborne:
		pitch = clampf(atan2(vy, maxf(speed, 1.0)) * 0.8, -0.35, 0.3)
	Builder.animate(model, speed, _steer, _steer * 0.04, pitch, false, dt)
	model.rotation.x = lerp_angle(model.rotation.x, 0.0 if airborne else atan(Track.slope_at(c, d)), 1.0 - exp(-dt * 12.0))


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


## Kontakte mit Spieler und anderen Gegnern (siehe Kopf). Positionen in Fahrtrichtung dieses Wagens.
func _contacts(dt: float, c: Curve3D, on_main: bool, target: float) -> void:
	_blocked_t = maxf(_blocked_t - dt * 0.5, 0.0)
	if not running:
		return
	var f := Track.frame_at(c, d)
	var lat := Track.lane_lat(track, d, lane) if on_main else lane
	var pos: Vector3 = f["pos"] + f["right"] * lat
	var others := []
	if player and is_instance_valid(player) and not player.tumbling and player.sinking <= 0.0:
		others.append([player, player.velocity, player._length, player.model.get_meta("width")])
	for r in rivals:
		if r != self and is_instance_valid(r) and not r.airborne:
			others.append([r, -r.global_basis.z * r.speed, r.length, r.width])
	for o in others:
		var rel: Vector3 = (o[0] as Node3D).global_position - pos
		rel.y = 0.0
		var along: float = rel.dot(f["fwd"])
		var side: float = rel.dot(f["right"])
		var lsum: float = (length + o[2]) * 0.5
		var wsum: float = (width + o[3]) * 0.5
		if absf(side) >= wsum or absf(along) >= lsum + 0.3:
			continue
		var their: float = (o[1] as Vector3).dot(f["fwd"])
		if along > lsum * 0.55 and absf(side) < wsum * 0.85:
			# Der andere ist vorn: nicht hineinfahren, an der Stoßstange bleiben
			d -= maxf(lsum + 0.15 - along, 0.0)
			if speed > their:
				var share := (speed - their) * 0.5  # unelastischer Stoß gleich schwerer Autos
				speed -= share
				_push(o[0], f["fwd"] * share)
			if target > speed + 1.0:
				# Gas geben schiebt den Vorderen mit (beide zusammen beschleunigen halb so stark)
				_push(o[0], f["fwd"] * accel * 0.5 * dt)
				speed = maxf(speed, their)
			_blocked_t += dt * 1.5
			_blocker_lat = lat + side
		elif along > -lsum * 0.55:
			# nebeneinander: beide weichen seitlich aus, je nach Überlappung
			var over := wsum - absf(side)
			lane -= signf(side) * over * 0.5
			lane_vel -= signf(side) * minf(over * 4.0, 3.0)
			_push(o[0], f["right"] * signf(side) * minf(over * 4.0, 3.0))


## Stoß an den Spieler (Geschwindigkeit) oder einen anderen Gegner (Tempo und Querbewegung) weitergeben
func _push(o: Node, dv: Vector3) -> void:
	if o == player:
		player.velocity += Vector3(dv.x, 0.0, dv.z)
	else:
		var n3 := o as Node3D
		var fwd := -n3.global_basis.z
		o.speed = maxf(o.speed + dv.dot(fwd), 0.0)
		o.lane_vel += dv.dot(n3.global_basis.x)


func _check_traffic_crash() -> void:
	for t in traffic:
		# Wracks nicht noch einmal: wer darin steckt, käme sonst nie wieder frei (Zusammenstoß, Benommenheit, wieder ...)
		if t.path_id != path["id"] or t.wrecked:
			continue
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
