extends CharacterBody3D
## Ziviler Verkehr: fährt langsam auf seiner Spur (rechts mit, links Gegenverkehr),
## weicht gesperrten Spuren aus, bremst für den Spieler und hält am Bahnübergang. Bei einem Crash wird er weggeschleudert
## und dreht sich, bei einem harten Treffer hebt er ab und überschlägt sich. Seit 2.35 (crash): das Wrack rutscht auf
## der Fahrbahn (Höhe der Straße an seiner Stelle, nie in den Boden; nicht durch die Randwand), aus Seitenlage kippt es
## auf Räder oder Dach. Auf den Rädern steht es kurz, dreht dann zurück in seine Spur und fährt weiter. Nur auf dem Dach
## bleibt es ein paar Sekunden liegen, blendet aus und wird außer Sicht neu eingesetzt.
## Fährt auf der Hauptstraße (mit Mittelstreifen-Versatz) oder in einer Gabelung (path_id).
## Bremst rechtzeitig für Spieler, Wracks und den Vordermann (leader, link_leaders), wechselt vor Wracks die Spur.
## Masse je Art: der Spieler stößt nach Impuls (player_car._hit_traffic), schwere Wagen geben weniger nach.
## Ton: race.gd schaltet bei den nächsten paar Autos Motor und Abrollen ein (sound()), mit Dopplereffekt im Vorbeifahren.

const Builder := preload("res://scripts/car_builder.gd")
const Track := preload("res://scripts/track_builder.gd")
const EngineAudio := preload("res://scripts/engine_audio.gd")
## Motorklang: ruhiger Vierzylinder; der Bus ein rauer Sechszylinder-Diesel

const KINDS := ["sedan", "sedan", "sedan", "taxi", "van", "van", "bus"]
const LKW_COLORS := [Color(0.75, 0.08, 0.06), Color(0.08, 0.2, 0.55), Color(0.92, 0.92, 0.9), Color(0.1, 0.4, 0.2),
	Color(0.95, 0.7, 0.1), Color(0.15, 0.15, 0.17)]
const SPEDITIONEN := ["SCHMITT LOGISTIK", "NORDFRACHT", "BAUER & SÖHNE", "KAIZEN CARGO", "RHEIN-MAIN SPEDITION",
	"ALPENTRANS", "HANSA KÜHLTRANSPORT", "SCHNELL & SICHER"]
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
var _wreck_vel := Vector3.ZERO  # Wrack: Rutschen (waagerecht, Eltern-Koordinaten)
var _wreck_spin := 0.0
var velocity_vec := Vector3.ZERO
## Unfall: NONE fährt, WRECK rutscht/fliegt, RECOVER fährt zurück in die Spur, ROOF liegt auf dem Dach
enum Crash { NONE, WRECK, RECOVER, ROOF }
const W_FRICTION := 9.0  # m/s²: so bremst ein rutschendes Wrack auf dem Asphalt
const W_REST := 1.0  # s steht das Wrack still, bevor es wieder anfährt
const ROOF_WAIT := 3.0  # s auf dem Dach, dann ausblenden
const FADE_T := 0.8
var crash := Crash.NONE
var _size := Vector3(1.8, 1.5, 4.5)
var _w_p := Vector3.ZERO  # Wrack: Fußpunkt unter der Wagenmitte (x, z)
var _w_yaw := 0.0  # Wrack: Drehung um die Hochachse
var _w_pitch := 0.0
var _w_roll := 0.0  # um die Längsachse: 0 auf den Rädern, ±PI auf dem Dach
var _w_roll_v := 0.0
var _w_roll_goal := 0.0  # Ruhelage nach der Landung (Räder 0/2π, Dach ±π)
var _w_air := 0.0  # Flughöhe über der Ruhelage
var _w_vy := 0.0
var _w_t := 0.0  # s im Zustand
var _w_rest := 0.0  # s fast still
var _w_side := 1.0  # Straßenseite beim Unfall (der Mittelstreifen wird nicht überquert)
var _yaw_off := 0.0  # zurück in die Spur: Abweichung von der Fahrtrichtung (rad), baut sich ab
var _fade := -1.0
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
		"lkw":
			# Sattelzug (seit 2.29, nur Autobahn): Zugmaschine in Farbe, weißer Auflieger mit Spedition
			size = Vector3(2.55, 3.9, 16.5)
			col = LKW_COLORS[rng.randi() % LKW_COLORS.size()]
	length = size.z
	_half_w = size.x / 2.0
	_size = size
	mass = {"van": 4.0, "bus": 10.0, "lkw": 14.0}.get(kind, 2.5)
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
			if it[0] is String:
				_label_from(it)
				continue
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
			"lkw":
				# Zugmaschine vorn (Fahrerhaus hoch), dahinter der Auflieger
				var paint := Builder.gloss_mat(col, 0.3, 0.4)
				var white := Builder.mat(Color(0.9, 0.9, 0.88), 0.1, 0.6)
				var dark := Builder.mat(Color(0.06, 0.06, 0.07), 0.2, 0.7)
				var glass := Builder.mat(Color(0.03, 0.04, 0.06), 0.7, 0.1)
				Builder._add(self, Builder.rtapered_box(Vector2(2.5, 2.4), Vector2(2.4, 2.3), 2.6, 0.0, 0.12), paint, Vector3(0, 0.9, -7.0))
				Builder._add(self, Builder.box(Vector3(2.3, 0.9, 0.05)), glass, Vector3(0, 2.75, -8.22))
				Builder._add(self, Builder.box(Vector3(2.5, 0.9, 3.6)), dark, Vector3(0, 0.45, -6.4))
				Builder._add(self, Builder.box(Vector3(2.55, 3.0, 13.4)), white, Vector3(0, 2.4, 1.5))
				Builder._add(self, Builder.box(Vector3(2.5, 0.7, 13.0)), dark, Vector3(0, 0.55, 1.5))
				var head := Builder.mat(Color(1, 1, 0.9), 0, 0.3, Color(1, 0.95, 0.8), 4.0)
				var tail := Builder.mat(Color(0.6, 0, 0), 0, 0.3, Color(1, 0.05, 0.02), 3.0)
				for sx in [-1, 1]:
					Builder._add(self, Builder.box(Vector3(0.4, 0.18, 0.05)), head, Vector3(sx * 0.9, 1.25, -8.22))
					Builder._add(self, Builder.box(Vector3(0.35, 0.15, 0.05)), tail, Vector3(sx * 1.0, 0.95, 8.21))
					for wz in [-7.6, -4.6, 4.4, 5.8, 7.2]:
						var c := CylinderMesh.new()
						c.top_radius = 0.5
						c.bottom_radius = 0.5
						c.height = 0.3
						c.radial_segments = 14
						c.rings = 1
						Builder._add(self, c, Builder.mat(Color(0.05, 0.05, 0.05), 0, 0.9), Vector3(sx * 1.08, 0.5, wz)).rotation_degrees.z = 90
				# Speditionsname an beiden Seiten des Aufliegers
				var name: String = SPEDITIONEN[absi(col.to_html().hash()) % SPEDITIONEN.size()]
				for sx in [-1.0, 1.0]:
					var l := Label3D.new()
					l.text = name
					l.font_size = 64
					l.pixel_size = 0.016
					l.modulate = col if col.get_luminance() < 0.8 else Color(0.1, 0.2, 0.5)
					l.shaded = true
					l.double_sided = false
					l.position = Vector3(sx * 1.29, 2.6, 1.5)
					l.rotation.y = sx * PI / 2.0
					add_child(l)
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
			elif c is Label3D:
				items.append([(c as Label3D).text, c.transform, (c as Label3D).modulate, (c as Label3D).pixel_size])
			else:
				cacheable = false  # unerwartete Teile: lieber nicht zwischenspeichern
		if cacheable:
			_models[key] = items


## Schriftzug (Spedition) aus dem Zwischenspeicher: [Text, Lage, Farbe, Pixelgröße]
func _label_from(it: Array) -> void:
	var l := Label3D.new()
	l.text = it[0]
	l.transform = it[1]
	l.modulate = it[2]
	l.pixel_size = it[3]
	l.font_size = 64
	l.shaded = true
	l.double_sided = false
	add_child(l)


## Alle Modelle beim Laden der Welt vorbauen (hinter dem Ladebild), damit auch das erste Auto jeder Farbe nicht ruckelt
static func prewarm() -> void:
	var plan := []
	for c in COLORS:
		plan.append(["sedan", c])
		plan.append(["van", c])
	plan.append_array([["taxi", Color(0.95, 0.75, 0.05)], ["van", Color(0.85, 0.85, 0.85)], ["bus", Color(0.9, 0.85, 0.1)],
		["bus", Color(0.85, 0.85, 0.85)]])
	for c in LKW_COLORS:
		plan.append(["lkw", c])
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
	return EngineAudio.traffic_loop("bus" if k == "bus" or k == "lkw" else "car")


## Motor und Abrollen an/aus (race.gd: nur die nächsten paar Autos)
func sound(on: bool, bus: String) -> void:
	if wrecked:
		on = false
	if _snd == null:
		if not on:
			return
		var bus_k := kind == "bus" or kind == "lkw"
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
	if crash == Crash.WRECK or crash == Crash.ROOF:
		_wreck_step(dt)
		return
	var recovering := crash == Crash.RECOVER

	# Gesperrte Spur (Rampe am Bahnübergang)? Dann eine Spur weiter nach innen.
	var target_lane := lane
	for b in blocks:
		if absf(b["lane"] - lane) < 1.0 and progress > b["from"] - 25.0 and progress < b["to"] + 10.0:
			target_lane = lane - signf(lane) * 4.5
	# nach einem Unfall zurück in die Spur: quer nur, solange er rollt; dabei dreht er sich wieder in Fahrtrichtung
	var lr := lane_rate
	if recovering:
		lr *= clampf(speed / 6.0, 0.3, 1.0)
	_lane_cur = move_toward(_lane_cur, target_lane, dt * lr)
	if recovering:
		_yaw_off = move_toward(_yaw_off, 0.0, (0.5 + speed * 0.15) * dt)
		# kommt er nicht los (Spieler oder Gegner stehen davor, festgefahren) oder dauert es zu lange: ausblenden und
		# außer Sicht neu einsetzen, statt dass sich zwei Autos gegenseitig blockieren
		_w_t += dt
		_w_rest = _w_rest + dt if speed < 1.0 else 0.0
		if _w_rest > 2.0 or _w_t > 9.0:
			_vanish()
			return

	# Spieler oder Wagen vor mir auf der Spur: rechtzeitig bremsen (der Bremsweg wächst mit dem Tempo) und
	# hinterherfahren; vor einem Wrack nach kurzem Warten die Spur wechseln
	var target := base_speed
	if recovering:
		target = minf(target, lerpf(base_speed, 3.0, clampf(absf(_yaw_off) / 1.2, 0.0, 1.0)))  # erst ausrichten
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
	if recovering and absf(_yaw_off) < 0.01 and absf(_lane_cur - target_lane) < 0.05:
		crash = Crash.NONE
		_yaw_off = 0.0
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
	if _yaw_off != 0.0:
		xf.basis = xf.basis * Basis(Vector3.UP, _yaw_off)  # nach einem Unfall noch schräg zur Spur
	transform = xf  # Eltern: Welt (Rennen) oder Strecke (Open World), beides ohne Verschiebung im Rennen


## Wunschtempo hinter etwas, das gap Meter vor mir mit lv fährt: so schnell, dass ich mit 6 m/s² noch 6 m davor
## zum Stehen (oder auf sein Tempo) komme
func _follow(gap: float, lv: float) -> float:
	return clampf(lv + sqrt(12.0 * maxf(gap - 6.0, 0.0)), 0.0, base_speed)


## Steckt der Spieler in mir (Wrack rutscht in ihn, oder ich fahre auf)? Dann bleibe ich an seiner Kante stehen,
## statt durch ihn hindurchzufahren.
func _clear_player() -> void:
	var w := crash == Crash.WRECK or crash == Crash.ROOF
	var c := Vector3(_w_p.x, position.y, _w_p.z) if w else position
	var rel := player_pos - c
	if rel.x * rel.x + rel.z * rel.z > 100.0:
		return
	var yb := Basis(Vector3.UP, _w_yaw) if w else transform.basis
	var q: Vector3 = yb.inverse() * rel
	var hx := _half_w + 1.0
	var hz := length / 2.0 + 2.2
	if absf(q.x) >= hx or absf(q.z) >= hz:
		return
	var px := hx - absf(q.x)
	var pz := hz - absf(q.z)
	var away := yb * (Vector3(-signf(q.x), 0, 0) if px < pz else Vector3(0, 0, -signf(q.z)))
	away.y = 0.0
	away = away.normalized()
	if w:
		_w_p += away * minf(px, pz)
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
	if _fade >= 0.0:
		return  # liegt auf dem Dach und blendet schon aus
	if crash == Crash.NONE or crash == Crash.RECOVER:
		_begin_wreck()
	elif crash == Crash.ROOF:
		crash = Crash.WRECK  # angestoßen: rutscht noch ein Stück
		_w_t = 0.0
		_w_rest = 0.0
	_wreck_vel += Vector3(dv.x, 0, dv.z)
	_wreck_spin += randf_range(-1.0, 1.0) * clampf(dv.length() / 6.0, 0.5, 3.0) / sqrt(mass)
	if dv.length() > 9.0 and mass < 3.0 and _w_roll_v == 0.0 and _w_air <= 0.0:
		_w_vy = clampf(dv.length() * 0.3, 3.5, 7.0)
		_w_air = 0.001
		_w_roll_v = randf_range(4.0, 7.0) * (1.0 if randf() < 0.5 else -1.0)


## Schwerer Crash mit dem Spieler: der Wagen hebt ab und überschlägt sich (Busse nur ein Ruck), egal wie schwer
## der Stoß rechnerisch war. away: Richtung vom Spieler weg (Welt), hit: Aufpralltempo (m/s)
func launch(away: Vector3, hit: float) -> void:
	if crash == Crash.NONE or crash == Crash.RECOVER:
		push(away * 0.1)
	if crash != Crash.WRECK:
		return
	if kind == "bus" or kind == "lkw":
		_wreck_spin += randf_range(-0.6, 0.6)
		return
	if _w_roll_v == 0.0 and _w_air <= 0.0:
		_w_vy = clampf(hit * 0.35, 4.5, 9.0)
		_w_air = 0.001
		_w_roll_v = randf_range(5.0, 8.0) * (1.0 if randf() < 0.5 else -1.0)
	var d := parent_basis.inverse() * away
	_wreck_vel += Vector3(d.x, 0, d.z) * clampf(hit * 0.25, 2.0, 8.0)
	_wreck_spin += randf_range(-2.5, 2.5)


## Aus dem Verkehr geworfen: ab jetzt rutscht der Wagen frei (Lage, Drehung und Tempo von eben, nur waagerecht; bis
## 2.34 auch mit der Steigung der Straße, an Kuppen sank das Wrack so in die Fahrbahn ein)
func _begin_wreck() -> void:
	var v := parent_basis.inverse() * velocity_vec
	_wreck_vel = Vector3(v.x, 0.0, v.z)
	var fw := -transform.basis.z
	_w_yaw = atan2(-fw.x, -fw.z)
	_w_pitch = 0.0
	_w_p = Vector3(position.x, 0.0, position.z)
	_w_roll = 0.0
	_w_roll_v = 0.0
	_w_roll_goal = 0.0
	_w_air = 0.0
	_w_vy = 0.0
	_w_t = 0.0
	_w_rest = 0.0
	_w_side = signf(_lane_cur) if absf(_lane_cur) > 0.1 else dir
	_yaw_off = 0.0
	_stuck_t = 0.0
	crash = Crash.WRECK
	wrecked = true


## Wrack: rutschen, drehen, fliegen und landen, immer auf der Höhe der Fahrbahn an seiner Stelle; danach zurück in die
## Spur (auf den Rädern) oder auf dem Dach liegen bleiben, ausblenden und neu einsetzen
func _wreck_step(dt: float) -> void:
	_w_t += dt
	_clear_player()
	var on_ground := _w_air <= 0.0 and _w_vy <= 0.0
	_w_p += _wreck_vel * dt
	_wreck_vel = _wreck_vel.move_toward(Vector3.ZERO, (W_FRICTION if on_ground else 1.0) * dt)
	_w_yaw += _wreck_spin * dt
	_wreck_spin = move_toward(_wreck_spin, 0.0, (2.5 if on_ground else 0.4) * dt)
	# Lage auf der Straße (für KI und Verkehr, die um das Wrack herumfahren): nicht durch die Randwand, nicht über
	# den Mittelstreifen
	progress = curve.get_closest_offset(Vector3(_w_p.x, 0.0, _w_p.z))
	var f := Track.frame_at(curve, progress)
	var fp: Vector3 = f["pos"]
	var right: Vector3 = f["right"]
	var lat: float = Vector3(_w_p.x - fp.x, 0.0, _w_p.z - fp.z).dot(right)
	var lim := _lat_limit(progress)
	var lo := -lim
	var hi := lim
	if path_id == 0:
		var m := Track.median_at(track, progress)
		if m > 0.4:
			if _w_side > 0.0:
				lo = minf(m + _half_w + 0.1, hi)
			else:
				hi = maxf(-(m + _half_w + 0.1), lo)
	if lat < lo or lat > hi:
		var nl := clampf(lat, lo, hi)
		_w_p += right * (nl - lat)
		var vout := _wreck_vel.dot(right)
		if (lat > hi and vout > 0.0) or (lat < lo and vout < 0.0):
			_wreck_vel -= right * vout * 1.25  # prallt etwas zurück
			_wreck_spin *= 0.7
		lat = nl
	_lane_cur = Track.logical_lat(track, progress, lat) if path_id == 0 else lat
	velocity_vec = parent_basis * _wreck_vel
	if not on_ground:
		_w_vy -= 18.0 * dt
		_w_air += _w_vy * dt
		_w_roll += _w_roll_v * dt
		if _w_air <= 0.0:
			_w_air = 0.0
			if _w_vy < -3.0:
				_w_vy *= -0.3  # schlägt auf und springt noch einmal
				_w_roll_v *= 0.5
				_wreck_spin *= 0.7
			else:
				_w_vy = 0.0
				# rollt er noch kräftig, rollt er sich auf der Straße weiter bis auf die Räder; sonst kippt er in die
				# nächste stabile Lage (Räder, oder Dach, wenn er schon fast darauf liegt)
				if absf(_w_roll_v) > 2.5:
					_w_roll_goal = (ceilf(_w_roll / TAU) if _w_roll_v > 0.0 else floorf(_w_roll / TAU)) * TAU
				else:
					_w_roll_goal = _roll_rest()
				_w_roll_v = 0.0
	else:
		_w_roll = move_toward(_w_roll, _w_roll_goal, 4.0 * dt)
	_wreck_place(f, lat)
	if crash == Crash.WRECK:
		var still := on_ground and _wreck_vel.length() < 0.6 and absf(_wreck_spin) < 0.4 and is_equal_approx(_w_roll, _w_roll_goal)
		_w_rest = _w_rest + dt if still else 0.0
		if base_speed < 0.5:
			_w_rest = 0.0  # Panne (stand schon vorher, Test --ctest=wreck): bleibt als Hindernis liegen
		elif _w_rest > W_REST or _w_t > 10.0:
			if cos(_w_roll) < 0.0:
				crash = Crash.ROOF
				_w_t = 0.0
			else:
				_start_recover(f)
	elif _w_t > ROOF_WAIT:
		if _fade < 0.0:
			_fade = 0.0
			collision_layer = 0  # niemand stößt mehr dagegen, während er verschwindet
		_fade += dt
		_set_fade(clampf(_fade / FADE_T, 0.0, 1.0))
		if _fade >= FADE_T:
			_respawn()


## Ruhelage für die aktuelle Drehung um die Längsachse: auf die Räder (rollt sich aus Seiten- und Schräglage zurück),
## außer er liegt schon fast auf dem Dach (gut 30° davon); so bleibt nur ein kleiner Teil der Überschläge auf dem Dach
## liegen, die übrigen fahren weiter
func _roll_rest() -> float:
	var wheels := floorf(_w_roll / TAU + 0.5) * TAU
	var dev := _w_roll - wheels
	return wheels + signf(dev) * PI if absf(dev) > PI - 0.6 else wheels


## Wrack auf die Straße setzen: Mitte über dem Fußpunkt, so hoch, dass die Karosserie in jeder Lage (Räder, Seite,
## Dach) auf der Fahrbahn aufliegt, plus Flughöhe; geneigt wie die Straße in Blickrichtung
func _wreck_place(f: Dictionary, lat: float) -> void:
	var half: float = Track.hw(track, progress) if path_id == 0 else float(track["paths"][path_id]["half_w"])
	var g: float = Track.ground_path(track, path_id, progress, lat, absf(lat) - half)["h"]
	if _w_air <= 0.0:
		var hdg := Vector3(-sin(_w_yaw), 0.0, -cos(_w_yaw))
		_w_pitch = atan(Track.slope_at(curve, progress) * hdg.dot(f["fwd"]))
	var b := Basis(Vector3.UP, _w_yaw) * Basis(Vector3.RIGHT, _w_pitch) * Basis(Vector3.BACK, _w_roll)
	var rest := absf(_half_w * sin(_w_roll)) + absf(_size.y / 2.0 * cos(_w_roll)) + 0.1 * maxf(cos(_w_roll), 0.0)
	var center := Vector3(_w_p.x, g + rest + _w_air, _w_p.z)
	transform = Transform3D(b, center - b * Vector3(0.0, _size.y / 2.0 + 0.1, 0.0))


## Wie weit ein Wrack quer rutschen darf: bis zur Randwand (im Trog bis zur Trogwand, im Drift-Kurs bis zur Bande),
## abzüglich der halben Wagenbreite
func _lat_limit(d: float) -> float:
	if path_id != 0:
		var p: Dictionary = track["paths"][path_id]
		return maxf(float(p["half_w"]) + (3.0 if p["kind"] == "fork" else 0.0) - _half_w - 0.1, 1.0)
	var wall := Track.hw(track, d) + Track.WALK + 0.3
	if track.get("type", "") == "drift":
		wall = Track.hw(track, d) + 0.4
	elif Track._trough_at(track, d) > 0:
		wall = Track.tun_w(track, d)
	return maxf(wall - _half_w - 0.2, 1.0)


## Wieder auf den Rädern: aus dem Stand zurück in die Spur (drehen, anfahren, einscheren), dann normal weiter
func _start_recover(f: Dictionary) -> void:
	if absf(_lane_cur - lane) > 7.0:
		_vanish()  # quer über die ganze Straße zurück (durch den Gegenverkehr): lieber außer Sicht neu einsetzen
		return
	crash = Crash.RECOVER
	wrecked = false
	_w_t = 0.0
	_w_rest = 0.0
	var lf: Vector3 = (f["fwd"] as Vector3) * dir
	_yaw_off = wrapf(_w_yaw - atan2(-lf.x, -lf.z), -PI, PI)
	if absf(_yaw_off) < 0.001:
		_yaw_off = 0.001
	_w_roll = 0.0
	_w_roll_v = 0.0
	_w_air = 0.0
	_w_vy = 0.0
	_wreck_vel = Vector3.ZERO
	_wreck_spin = 0.0
	speed = 0.0
	_stuck_t = 0.0
	place()


## Sofort ausblenden (ohne Kollision) und danach außer Sicht neu einsetzen (_respawn): für Wagen, die nach einem
## Unfall nicht von selbst zurück in den Verkehr finden
func _vanish() -> void:
	if crash == Crash.NONE or crash == Crash.RECOVER:
		_begin_wreck()
	_wreck_vel = Vector3.ZERO
	_wreck_spin = 0.0
	_w_roll_v = 0.0
	_w_roll_goal = _w_roll
	crash = Crash.ROOF
	_w_t = ROOF_WAIT


## Wagenteile ein- (0) oder ausgeblendet (1)
func _set_fade(a: float) -> void:
	for c in get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).transparency = a


## Vom Dach ausgeblendet: außer Sicht des Spielers auf demselben Weg neu einsetzen, wie der übrige Verkehr
func _respawn() -> void:
	crash = Crash.NONE
	wrecked = false
	_fade = -1.0
	_set_fade(0.0)
	collision_layer = 2
	_w_roll = 0.0
	_w_roll_v = 0.0
	_w_air = 0.0
	_w_vy = 0.0
	_wreck_vel = Vector3.ZERO
	_wreck_spin = 0.0
	_yaw_off = 0.0
	_lane_cur = lane
	speed = base_speed
	_handing = false
	var far := maxf(GameState.view_distance() + 60.0, 300.0)
	var best := -1.0
	var best_d := progress
	for i in 16:
		var d := randf_range(30.0, maxf(track_length - 30.0, 31.0))
		var q := curve.sample_baked(d)
		var dist := Vector2(q.x - player_pos.x, q.z - player_pos.z).length()
		if dist > best:
			best = dist
			best_d = d
		if dist > far:
			break
	progress = best_d
	place()


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
