extends CharacterBody3D
## Ziviler Verkehr: fährt langsam auf seiner Spur (rechts mit, links Gegenverkehr),
## weicht gesperrten Spuren aus, bremst für den Spieler und hält am Bahnübergang. Bei einem Crash wird er weggeschleudert,
## bei einem harten Treffer hebt er ab, überschlägt sich und bleibt auf Seite oder Dach liegen.
## Fährt auf der Hauptstraße (mit Mittelstreifen-Versatz) oder in einer Gabelung (path_id).
## Bremst rechtzeitig für Spieler, Wracks und den Vordermann (leader, link_leaders), wechselt vor Wracks die Spur.
## Masse je Art: der Spieler stößt nach Impuls (player_car._hit_traffic), schwere Wagen geben weniger nach.
## Ton: race.gd schaltet bei den nächsten paar Autos Motor und Abrollen ein (sound()), mit Dopplereffekt im Vorbeifahren.

const Builder := preload("res://scripts/car_builder.gd")
const Track := preload("res://scripts/track_builder.gd")
const EngineAudio := preload("res://scripts/engine_audio.gd")
## Motorklang: ruhiger Vierzylinder; der Bus ein rauer Sechszylinder-Diesel

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
## Open World: Lage der Strecke in der Welt (der Wagen hängt an ihrem Knoten) und Rückruf am Ende des Wegs
## (world.gd reicht ihn ans nächste Autobahnstück weiter oder setzt ihn außer Sicht neu ein)
var parent_basis := Basis.IDENTITY
var on_end := Callable()
var _handing := false
var mass := 2.5  # im Verhältnis zum Spielerauto (1): Pkw 2,5, Transporter 4, Bus 10. Verkehr ist schwer wie in
## Underground: wer ihn rammt, verliert viel Tempo; schwere Wagen geben kaum nach
var leader: Node = null  # nächster Wagen vor mir auf meiner Spur (link_leaders)
var player_speed := 0.0  # Spieler längs der Straße (+ in Wegrichtung)
var _half_w := 0.9
var _stuck_t := 0.0
var lane_rate := 2.0  # Spurwechsel m/s quer (Herausforderer: schneller)
var accel_up := 4.0  # Beschleunigen m/s² (Herausforderer: wie ein Sportwagen)


static var _models := {}  # Art + Farbe -> [[Mesh, Lage, Material, Schatten]] (setup)


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
	# Lackfarbe festlegen (Zufallszahlen in derselben Reihenfolge wie bisher)
	match kind:
		"taxi":
			col = Color(0.95, 0.75, 0.05)
		"van":
			size = Vector3(2.0, 2.3, 5.2)
			col = Color(0.85, 0.85, 0.85) if rng.randf() < 0.6 else col
		"bus":
			size = Vector3(2.5, 3.2, 11.0)
			col = Color(0.9, 0.85, 0.1) if rng.randf() < 0.5 else Color(0.85, 0.85, 0.85)
	length = size.z
	_half_w = size.x / 2.0
	mass = {"van": 4.0, "bus": 10.0}.get(kind, 2.5)
	# Modell je Art und Farbe nur einmal bauen: Bauen und Verschmelzen kostete gut 20 ms je Auto, beim Laden einer
	# Strecke kamen so ein Dutzend Autos auf einmal und das Bild ruckelte eine Sekunde lang (alle paar Sekunden)
	_model(col)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position.y = size.y / 2.0 + 0.1
	add_child(cs)


## Modell aus dem Zwischenspeicher oder neu bauen (dann merken)
func _model(col: Color) -> void:
	var key := kind + col.to_html()
	if _models.has(key):
		for it in _models[key]:
			var mi := MeshInstance3D.new()
			mi.mesh = it[0]
			mi.transform = it[1]
			mi.material_override = it[2]
			mi.cast_shadow = it[3]
			add_child(mi)
	else:
		match kind:
			"sedan":
				_body(Vector2(1.8, 4.5), 0.65, col, Vector2(1.6, 2.2), 0.5)
			"taxi":
				_body(Vector2(1.8, 4.6), 0.65, col, Vector2(1.6, 2.3), 0.5)
				Builder._add(self, Builder.box(Vector3(0.7, 0.22, 0.3)), Builder.mat(Color(1, 1, 0.8), 0, 0.4, Color(1, 0.95, 0.6), 2.5), Vector3(0, 1.62, 0.2))
			"van":
				_body(Vector2(2.0, 5.2), 1.6, col, Vector2(1.9, 1.0), 0.45, -1.9)
			"bus":
				_body(Vector2(2.5, 11.0), 2.6, col, Vector2.ZERO, 0.0)
				var win := Builder.mat(Color(0.1, 0.1, 0.1), 0.5, 0.2, Color(1, 0.9, 0.6), 1.2)
				for s in [-1, 1]:
					Builder._add(self, Builder.box(Vector3(0.05, 0.9, 9.0)), win, Vector3(s * 1.26, 2.1, 0.5))
				Builder._add(self, Builder.box(Vector3(2.3, 1.0, 0.05)), win, Vector3(0, 2.0, -5.51))
		Builder.merge_static(self)
		var items := []
		var cacheable := true
		for c in get_children():
			if c is MeshInstance3D and c.get_child_count() == 0:
				items.append([c.mesh, c.transform, c.material_override, c.cast_shadow])
			else:
				cacheable = false  # unerwartete Teile: lieber nicht zwischenspeichern
		if cacheable:
			_models[key] = items


## Alle Modelle beim Laden der Welt vorbauen (hinter dem Ladebild), damit auch das erste Auto jeder Farbe nicht ruckelt
static func prewarm() -> void:
	var plan := []
	for c in COLORS:
		plan.append(["sedan", c])
		plan.append(["van", c])
	plan.append_array([["taxi", Color(0.95, 0.75, 0.05)], ["van", Color(0.85, 0.85, 0.85)], ["bus", Color(0.9, 0.85, 0.1)],
		["bus", Color(0.85, 0.85, 0.85)]])
	var Self: GDScript = load("res://scripts/traffic_car.gd")
	for it in plan:
		if _models.has(it[0] + (it[1] as Color).to_html()):
			continue
		var t: Node3D = Self.new()
		t.kind = it[0]
		t._model(it[1])
		t.free()


func _body(fp: Vector2, h: float, col: Color, cabin: Vector2, cabin_h: float, cabin_z := 0.2) -> void:
	var paint := Builder.gloss_mat(col, 0.3, 0.4)
	var glass := Builder.mat(Color(0.03, 0.04, 0.06), 0.7, 0.1)
	var clear := 0.25
	# Karosserie und Kabine mit runden Kanten (bis 2.20 scharfkantige Kisten), dazu Stoßfänger, Spiegel und Felgen
	Builder._add(self, Builder.rtapered_box(fp, fp - Vector2(0.08, 0.2), h, 0.0, minf(0.14, h * 0.3)), paint, Vector3(0, clear, 0))
	if cabin.x > 0.0:
		Builder._add(self, Builder.rtapered_box(cabin, cabin - Vector2(0.25, 0.5), cabin_h, 0.1, 0.1), glass, Vector3(0, clear + h, cabin_z))
	var head := Builder.mat(Color(1, 1, 0.9), 0, 0.3, Color(1, 0.95, 0.8), 4.0)
	var tail := Builder.mat(Color(0.6, 0, 0), 0, 0.3, Color(1, 0.05, 0.02), 3.0)
	var trim := Builder.mat(Color(0.06, 0.06, 0.07), 0.2, 0.7)
	for s in [-1, 1]:
		Builder._add(self, Builder.rbox(Vector3(0.35, 0.15, 0.05), 0.02), head, Vector3(s * (fp.x / 2 - 0.3), clear + 0.35, -fp.y / 2 - 0.01))
		Builder._add(self, Builder.rbox(Vector3(0.35, 0.15, 0.05), 0.02), tail, Vector3(s * (fp.x / 2 - 0.3), clear + 0.4, fp.y / 2 + 0.01))
		if cabin.x > 0.0:
			Builder._add(self, Builder.rbox(Vector3(0.16, 0.09, 0.07), 0.03), paint, Vector3(s * (fp.x / 2 + 0.05), clear + h + 0.05, cabin_z - cabin.y / 2 + 0.25))
	for z in [-1, 1]:
		Builder._add(self, Builder.rbox(Vector3(fp.x - 0.06, 0.12, 0.1), 0.04), trim, Vector3(0, clear + 0.08, z * (fp.y / 2 - 0.02)))
	var tire := Builder.mat(Color(0.05, 0.05, 0.05), 0, 0.9)
	var hub := Builder.mat(Color(0.55, 0.56, 0.58), 0.7, 0.35)
	for s in [-1, 1]:
		for z in [-1, 1]:
			var c := CylinderMesh.new()
			c.top_radius = 0.33
			c.bottom_radius = 0.33
			c.height = 0.24
			c.radial_segments = 16
			c.rings = 1
			var wp := Vector3(s * (fp.x / 2 - 0.1), 0.33, z * (fp.y / 2 - 0.9))
			Builder._add(self, c, tire, wp).rotation_degrees.z = 90
			Builder._add(self, Builder._disc(0.2, 0.01), hub, wp + Vector3(s * 0.121, 0, 0)).rotation_degrees.z = 90


## Klang vorrechnen (race.gd beim Laden): sonst rechnete das erste nahe Auto mitten im Rennen und es ruckelte
static func prepare_sound() -> void:
	_loop_for("sedan")
	_loop_for("bus")


static func _loop_for(k: String) -> AudioStreamWAV:
	return EngineAudio.traffic_loop("bus" if k == "bus" else "car")


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
		position += _wreck_vel * dt
		_wreck_vel = _wreck_vel.move_toward(Vector3.ZERO, 9.0 * dt)
		rotate_y(_wreck_spin * dt)
		_wreck_spin = move_toward(_wreck_spin, 0.0, 2.5 * dt)
		velocity_vec = parent_basis * _wreck_vel
		_clear_player()
		if _wreck_vel.length_squared() > 0.01:
			# Lage für KI und Verkehr nachführen, damit sie um das Wrack herumfahren, wo es wirklich liegt
			progress = curve.get_closest_offset(position)
			var f := Track.frame_at(curve, progress)
			var lat: float = (position - f["pos"]).dot(f["right"])
			_lane_cur = Track.logical_lat(track, progress, lat) if path_id == 0 else lat
		if _wreck_roll_v != 0.0 or position.y > _wreck_ground + 0.01:
			_wreck_vy -= 18.0 * dt
			position.y += _wreck_vy * dt
			rotate_object_local(Vector3.BACK, _wreck_roll_v * dt)
			_wreck_roll += _wreck_roll_v * dt
			if position.y <= _wreck_ground and _wreck_vy < 0.0:
				position.y = _wreck_ground
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
	_lane_cur = move_toward(_lane_cur, target_lane, dt * lane_rate)

	# Spieler oder Wagen vor mir auf der Spur: rechtzeitig bremsen (der Bremsweg wächst mit dem Tempo) und
	# hinterherfahren; vor einem Wrack nach kurzem Warten die Spur wechseln
	var target := base_speed
	var ahead := (player_progress - progress) * dir
	if player_path == path_id and absf(player_lateral - _lane_cur) < 2.6 and ahead > 0.0:
		target = minf(target, _follow(ahead - length / 2.0 - 2.3, maxf(player_speed * dir, 0.0)))
	if is_instance_valid(leader) and leader.path_id == path_id:
		var lg: float = (leader.progress - progress) * dir
		if track.get("loop", false) and path_id == 0:
			lg = fposmod(lg, track_length)
		lg -= (length + leader.length) / 2.0
		if absf(leader.lateral() - _lane_cur) < 2.6:
			var lv: float = 0.0 if leader.wrecked else maxf(leader.speed * leader.dir * dir, 0.0)
			target = minf(target, _follow(lg, lv))
			if leader.wrecked and speed < 1.5 and lg < 15.0:
				_stuck_t += dt
				if _stuck_t > 1.2:
					_stuck_t = 0.0
					lane = lane - signf(lane) * 4.5 if absf(lane) > 4.0 else lane + signf(lane) * 4.5
	# Schranken unten? Vor der Haltelinie stehen bleiben.
	if crossing and path_id == 0 and crossing.is_blocked():
		var stop: float = (crossing.d_cross - 12.0 - progress) if dir > 0.0 else (progress - crossing.d_cross - 12.0)
		if stop > -2.0 and stop < 140.0:
			target = minf(target, sqrt(2.0 * 7.0 * maxf(stop, 0.0)))
	speed = move_toward(speed, target, dt * (accel_up if target > speed else 10.0))
	progress += speed * dt * dir
	if path_id == 0 and track.get("loop", false):
		progress = fposmod(progress, track_length)  # Rundkurs: einfach weiterfahren
	elif on_end.is_valid():
		if progress > track_length - 1.0 or progress < 1.0:
			progress = clampf(progress, 1.0, track_length - 1.0)
			if not _handing:
				_handing = true
				on_end.call_deferred(self)
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
	_clear_player()
	# Außer Sichtweite: unsichtbar und Lage nur zweimal pro Sekunde neu (spart im Browser viel Rechenzeit)
	var far := position.distance_squared_to(player_pos) > _far_d2
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
	velocity_vec = parent_basis * fwd * speed
	transform = xf  # Eltern: Welt (Rennen) oder Strecke (Open World), beides ohne Verschiebung im Rennen


## Wunschtempo hinter etwas, das gap Meter vor mir mit lv fährt: so schnell, dass ich mit 6 m/s² noch 6 m davor
## zum Stehen (oder auf sein Tempo) komme
func _follow(gap: float, lv: float) -> float:
	return clampf(lv + sqrt(12.0 * maxf(gap - 6.0, 0.0)), 0.0, base_speed)


## Steckt der Spieler in mir (Wrack rutscht in ihn, oder ich fahre auf)? Dann bleibe ich an seiner Kante stehen,
## statt durch ihn hindurchzufahren.
func _clear_player() -> void:
	var rel := player_pos - position
	if rel.x * rel.x + rel.z * rel.z > 100.0:
		return
	var q: Vector3 = transform.basis.inverse() * rel
	var hx := _half_w + 1.0
	var hz := length / 2.0 + 2.2
	if absf(q.x) >= hx or absf(q.z) >= hz:
		return
	var px := hx - absf(q.x)
	var pz := hz - absf(q.z)
	var away := transform.basis * (Vector3(-signf(q.x), 0, 0) if px < pz else Vector3(0, 0, -signf(q.z)))
	away.y = 0.0
	away = away.normalized()
	if wrecked:
		position += away * minf(px, pz)
		var into := -_wreck_vel.dot(away)
		if into > 0.0:
			_wreck_vel += away * into
	elif q.z < 0.0 and pz <= px:
		# der Spieler steht vor mir: zurück an seine Kante, stehen bleiben
		progress -= dir * pz
		speed = 0.0


## Unfall: wird mit (einem Teil) der Aufprallgeschwindigkeit weggeschoben und dreht sich (schwere Wagen weniger).
func knock(v: Vector3) -> void:
	push(v * 0.6 / mass)


## Stoß als Tempoänderung (Weltkoordinaten): aus dem Verkehr geworfen, rutscht, dreht sich, kleine Wagen kippen
func push(dv: Vector3) -> void:
	dv = parent_basis.inverse() * dv  # Stoß kommt in Weltkoordinaten
	if not wrecked:
		wrecked = true
		_wreck_vel = parent_basis.inverse() * velocity_vec
		_wreck_ground = position.y
	_wreck_vel += Vector3(dv.x, 0, dv.z)
	_wreck_spin += randf_range(-1.0, 1.0) * clampf(dv.length() / 6.0, 0.5, 3.0) / sqrt(mass)
	if dv.length() > 9.0 and mass < 3.0 and _wreck_roll_v == 0.0 and position.y <= _wreck_ground + 0.01:
		_wreck_vy = clampf(dv.length() * 0.3, 3.5, 7.0)
		_wreck_roll_v = randf_range(4.0, 7.0) * (1.0 if randf() < 0.5 else -1.0)


## Open World: auf einen anderen Weg (nächstes Autobahnstück) oder an eine andere Stelle desselben Wegs setzen
func move_to(new_track: Dictionary, d: float) -> void:
	track = new_track
	curve = track["curve"]
	track_length = track["length"]
	blocks = track["blocks"]
	progress = d
	_handing = false
	place()


## Für KI/Verkehrslogik: aktuelle Querposition auf der Strecke
func lateral() -> float:
	return _lane_cur


## Für jeden Wagen den nächsten vor ihm auf seiner Spur suchen (auch Wracks): race.gd und world.gd rufen das ein
## paarmal pro Sekunde auf, den Abstand rechnet jeder Wagen dann selbst in jedem Takt.
static func link_leaders(cars: Array) -> void:
	var groups := {}
	for t in cars:
		if not is_instance_valid(t) or not t.is_inside_tree():
			continue
		t.leader = null
		var key := "%d|%d|%d" % [t.get_parent().get_instance_id(), t.path_id, int(floor(t.lateral() / 4.5))]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(t)
	for g in groups.values():
		if g.size() < 2:
			continue
		g.sort_custom(func(a, b): return a.progress < b.progress)
		var n: int = g.size()
		var loop: bool = g[0].track.get("loop", false) and g[0].path_id == 0
		for i in n:
			var t = g[i]
			if t.wrecked:
				continue
			var j: int = i + (1 if t.dir > 0.0 else -1)
			if j >= n or j < 0:
				if not loop:
					continue
				j = posmod(j, n)
			if g[j] != t:
				t.leader = g[j]
