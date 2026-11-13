extends CharacterBody3D
## Arcade-Fahrphysik mit Heckantrieb: Gänge mit Drehmomentkurve, Grip, der die Fahrtrichtung zur Fahrzeugachse zieht
## (ohne Tempo zu verschenken), mit Handbremse oder viel Gas in engen Kurven kommt das Heck; der Rutschzustand ist
## stufenlos (kein Umschalten zwischen Grip und Drift). Im Drift dreht das Auto um die Vorderachse (Heck schwenkt).
## Wände wie in NFSU: man schrammt entlang und dreht weich parallel zur Wand, Verkehr bestraft deutlich härter.
## Handbremse für Drifts, Nitro, Sprünge über Rampen (in der Luft keine Lenkung, Nitro schiebt weiter).
## Kamera: Verfolger (Standard), Stoßstange, Motorhaube – Taste C schaltet durch.
## Drag-Modus wie in NFSU: das Auto fährt wie auf Schienen in seiner Spur, links/rechts wechselt die Spur (weicher
## Schwenk), geschaltet wird von Hand mit S/X (im grünen Bereich perfekt), zu lange im Begrenzer überhitzt der Motor,
## ein Crash mit Verkehr ist Totalschaden.
## Antrieb: Gas baut sich in gut einer halben Sekunde auf, beim Anfahren begrenzt die Haftung, jeder Gangwechsel
## nimmt kurz Zug weg; Nitro und Start-Bonus setzen weich ein (kein Satz nach vorn).

const Catalog := preload("res://scripts/catalog.gd")
const Builder := preload("res://scripts/car_builder.gd")
const EngineAudio := preload("res://scripts/engine_audio.gd")
const Track := preload("res://scripts/track_builder.gd")
const Knockable := preload("res://scripts/knockable.gd")

## Ende von Gang 1..5 als Anteil der Höchstgeschwindigkeit; der 6. reicht bis über Topspeed
const GEARS := [0.0, 0.16, 0.31, 0.47, 0.63, 0.81, 1.3]
const SHIFT_RPM := 7400.0
const TOP_RPM := 6600.0  # Drehzahl bei Höchstgeschwindigkeit im 6. Gang
const VMAX_K := 0.948  # so viel von top_speed erreicht das Auto ohne Nitro in der Ebene (wie bis 2.12)
## Zug je Gang. Die unteren Gänge seit der Open World schwächer (vorher 1,0 / 0,86 / 0,74): das Anfahren war zu
## kräftig (Sakura 0–100 in 4,8 s, getunt 3,7 s; Einstiegsautos in Underground 7–8 s). Ab dem 4. Gang wie vorher,
## das Endtempo bleibt.
const GEAR_PULL := [0.0, 0.64, 0.6, 0.6, 0.59, 0.54, 0.46]
const GRAVITY := 18.0  # knapp 2 g: Sprünge mit spürbarer Flugphase, ohne zu schweben
const MAX_LAUNCH_VY := 14.0
## Überschlag nur wie in echt: quer rutschend mit der Flanke gegen ein Hindernis (die Räder haken, das Auto kippt
## darüber), ab 36 km/h Querfahrt und mindestens 50 km/h Tempo. Frontal gibt es Crash und Dreher, keinen Überschlag.
const TRIP_V := 10.0
const TRIP_MIN_SPEED := 14.0
const PIVOT := Vector3(0, 0.7, 0)  # Schwerpunkt: um ihn dreht sich das Auto in der Luft und beim Überschlag
const MIN_RADIUS := 5.2  # kleinster Wendekreis (Radius) bei voll eingeschlagener Lenkung
const BRAKE := 22.0  # m/s² Vollbremsung (gut 2 g: kräftig, aber nicht wie gegen eine Wand)
const REV_ACCEL := 5.0  # m/s² rückwärts (gemächlich, wie ein Rückwärtsgang)
const REV_TOP := 11.0  # m/s rückwärts höchstens (~40 km/h)
const TO_REVERSE := 0.3  # s im Stand mit Bremse, bis der Rückwärtsgang drin ist
const TO_FORWARD := 0.15  # s im Stand mit Gas, bis der erste Gang drin ist
## Antrieb (nur im normalen Fahren; im Drift-Event fahren alle gleich): Haftung beim Anfahren (Anteil, der vom
## Stand an greift), Heck kommt unter Gas (Übersteuern), Front schiebt unter Gas (Untersteuern)
const DRIVE := {
	"fwd": {"launch": 0.58, "oversteer": 0.0, "understeer": 0.16},
	"rwd": {"launch": 0.65, "oversteer": 1.0, "understeer": 0.0},
	"mr": {"launch": 0.72, "oversteer": 1.25, "understeer": 0.0},
	"awd": {"launch": 0.84, "oversteer": 0.3, "understeer": 0.06},
	"rr": {"launch": 0.8, "oversteer": 1.4, "understeer": 0.03},  # Heckmotor: viel Traktion, Heck kommt leicht
}
const WALL_TURN_RATE := 4.0  # rad/s: so schnell dreht die Wand das Auto höchstens parallel (kein Sprung im Bild)
const DRAG_LIMIT := 8000.0  # Begrenzer im Drag
const PERFECT_SHIFT := Vector2(7100.0, 7650.0)  # grüner Bereich zum Hochschalten
const GOOD_SHIFT := 6200.0
## Kameras (C schaltet weiter, die Wahl wird gespeichert): Verfolger nah und weit, Stoßstange, Motorhaube
const CAM_NAMES := ["Verfolger", "Verfolger weit", "Stoßstange", "Motorhaube"]
## Verfolger: Abstand, Höhe (je bei Stand, mit Tempo etwas weiter und flacher) und Blickpunkt vor dem Auto.
## Seit 2.24 ein Stück höher (wie in NFSU, vorher 4,4 m / 1,6 m), dazu eine weite Stufe.
const CHASE := [{"dist": 4.6, "height": 1.95, "look_y": 1.0, "look_z": -7.5},
	{"dist": 6.4, "height": 2.55, "look_y": 1.0, "look_z": -8.5}]
## Sprungkamera wie in NFSU: bei hohen, langen Sprüngen schneidet das Bild auf eine feste Kamera knapp über dem
## Boden schräg vor der Landestelle. Sie schaut dem Auto nach und zoomt so, dass es etwa gleich groß bleibt; dazu
## Zeitlupe. Kurz nach dem Aufsetzen geht es zurück zur Fahrerkamera.
const JUMP_CAM_PEAK := 1.6  # ab dieser vorhergesagten Höhe über dem Boden (m)
const JUMP_CAM_TIME := 0.6  # und dieser Flugdauer (s); Kuppen bleiben darunter, Seesprung und Bahnrampe nicht
const JC_AHEAD := 8.0  # Kamera so weit hinter der Landestelle
const JC_SIDE := 6.0  # und so weit seitlich der Flugbahn (schräg von vorn statt frontal)
const JC_HEIGHT := 1.3
const JC_FRAME := 2.4  # halbe Bildhöhe am Auto (m): kleiner = näher heran
const SLOW_REAL := 2.4  # Zeitlupe so stark, dass ein Sprung etwa so lange dauert (s, Echtzeit) ...
const SLOW_RANGE := Vector2(0.45, 0.7)  # ... aber nur leicht: Zeitfaktor in diesem Bereich

const TRAFFIC_BOUNCE := 0.25  # Stoßzahl gegen Verkehr: 0 klebt zusammen, 1 prallt voll ab

var controls_enabled := false
var finished := false
var cam_mode := 0

var model: Node3D
var cam: Camera3D
var audio: Node  # engine_audio.gd
var track: Dictionary:
	set(v):
		track = v
		_txf = v.get("xf", Transform3D.IDENTITY)
		_txi = _txf.affine_inverse()
## Open World: Lage der Strecke in der Welt. Alle Abfragen an die Strecke rechnen in ihren eigenen Koordinaten.
var _txf := Transform3D.IDENTITY
var _txi := Transform3D.IDENTITY

var accel := 11.0
var top_speed := 58.0
var grip_k := 8.0
var steer_rate := 2.2
var lat_acc := 28.0  # m/s²: so stark kann das Auto bei Tempo höchstens ums Eck (begrenzt die Drehrate)
var nitro_power := 1.0
var nitro_cap := 1.0

var nitro := 1.0
var nitro_on := false
var speed_fwd := 0.0
var speed_lat := 0.0
var steer := 0.0
var gear := 1
var rpm := 900.0
var _pull_gear := 1  # Gang für den Vortrieb (nach Tempo nach vorn); gear/rpm sind, was man hört und sieht
var _pull_rpm := 900.0
var drifting := false
var drift_angle := 0.0  # Grad zwischen Fahrtrichtung und Fahrzeugachse
var drift_k := 0.3  # 0..1: wie willig das Auto quer geht (aus dem Katalog)
var crashes := 0  # zählt harte Einschläge (Drift-Kette geht verloren)
var wall_hits := 0  # zählt jede Berührung mit Wand/Bande (Drift-Modus: Kette weg)
## Drift-Modus (Drift-Events): ist das Auto erst quer, hält Gas das Heck draußen, Lenken steuert den Winkel,
## die Fahrtrichtung folgt dem Auto nur langsam. Ohne Gas richtet es sich wieder auf.
var drift_mode := false
## Drag-Modus: Spur 0..3, Motortemperatur 0..1, Ergebnis des letzten Schaltvorgangs (für das HUD), Ausfälle
var drag_mode := false
var drag_lane := 2
var engine_heat := 0.0
var shift_result := ""
var blown := false
var totaled := false
var _limiter := false
var _nos_empty := false
var _sliding := false
var _slide_out := 0.0
var _thr_s := 0.0  # Gas weich nachgeführt (kein Sprung von 0 auf volle Kraft)
var _nos_k := 0.0  # Nitro-Schub, weich ein- und ausgeblendet
var _launch_t := 0.0  # > 0: perfekter Start (mehr Zug), < 0: Räder drehen durch (weniger Zug)
var _shift_boost := 0.0  # Drag: kurzer Schub nach perfektem Schalten
var _nos_burn := 0.0  # Nitro brennt nach dem Zünden mindestens so lange (s), auch wenn die Taste schon los ist
var _nos_lock := 0.0  # nach dem Abschalten kurz gesperrt (s): kein Dauerfeuer durch schnelles Tippen
var _nos_block := false  # Crash, Countdown, Motorschaden: Nitro sofort aus
const NOS_MIN_BURN := 0.5
const NOS_RELOCK := 0.9
var _backfire := 0.0  # Fehlzündung im Auspuff (Flamme), klingt schnell ab
var _pops: Array = []  # anstehende Fehlzündungen: [Restzeit s, Stärke]
var _crackle := 0.35  # Wahrscheinlichkeit für Knallen beim Schalten/Gaswegnehmen (Sportauspuff, Turbo: öfter)
var _thr_prev := 0.0
var _thr_held := 0.0  # wie lange schon Vollgas (s): nur danach knallt es beim Gaswegnehmen
var _crackle_cool := 0.0  # nach einer Knall-Folge kurz Ruhe (sonst knattert es beim Gas-Antippen wie ein MG)
var _scrape := 0.0  # Schrammen an der Wand (0..1), für den Ton
var _scrape_hold := 0.0
var drive_type := "rwd"  # Antrieb aus dem Katalog: fwd, rwd, mr (Mittelmotor, Heck), awd
var _wheel_v := Vector2.ZERO  # Umfangsgeschwindigkeit der Räder vorn/hinten (m/s), nur Optik (_wheel_speeds)
var reverse_gear := false  # Rückwärtsgang eingelegt (Tacho zeigt R)
var _change_t := 0.0  # wie lange das Auto schon steht und in die andere Richtung will
var _holding := false  # dieses Bild: Auto steht beim Gangwechsel still
var _rev_s := 0.0  # geglättetes "Gas" rückwärts
var _rail_lat := 0.0  # Drag: Querlage auf der Schiene (folgt der gewählten Spur weich)
var _rail_v := 0.0
var _rail_init := false
var _rail_on := false  # Schiene war im letzten Takt aktiv
var _rail_tf := Vector3.FORWARD  # Straßenrichtung dort
var _rail_speed := 0.0  # Tempo entlang der Straße (der Schwenk beim Spurwechsel ist kein Vortrieb)
var _was_enabled := false
var _slip_hold := 0.0  # 0..1: wie sehr das Heck gerade gelöst ist (Handbremse baut auf, Gas hält, klingt weich ab)
var _cam_drift := 0.0  # wie weit die Kamera im Drift in Fahrtrichtung schaut (geglättet)
var _shake_t := 0.0
var _wall_cool := 0.0
var _wall_turn := 0.0  # Restdrehung parallel zur Wand (rad), wird über einige Bilder abgebaut
var _wall_t := 10.0  # Zeit seit dem letzten Wandkontakt (kurz danach zählt Rutschen nicht als Drift)
var debug_hits := false  # nur für Tests (--handling, --trace): merkt sich, woran das Auto angeeckt ist
var last_hit := ""
var _collider_name := ""
## Rundkurs: abgeschlossene Runden und Gesamtfortschritt (Runden * Länge + Position)
var lap := 0
var total := 0.0
## Position auf der Strecke: Rennfortschritt (Meter Hauptstraße), Querlage, aktueller Weg
var progress := 0.0
var lateral := 0.0
var path_id := 0
var loc := {}
var stun := 0.0
var airborne := false
var air_time := 0.0
var last_air := 0.0  # Dauer des letzten Sprungs (für das HUD)
var landings := 0
var vy := 0.0
var sinking := 0.0
var tumbling := false  # Überschlag läuft (keine Kontrolle)
var rollovers := 0
var _air_pitch := 0.0  # Lage in der Luft: Nicken und Rollen mit eigener Drehgeschwindigkeit
var _air_pitch_v := 0.0
var _air_roll := 0.0
var _air_roll_v := 0.0
var _tumble_rest := 0.0

var _shift_timer := 0.0
var _shake := 0.0
var _fov := 72.0
var _length := 4.0
var _axle := 0.78  # Vorderachse so weit hinter dem Bug
var _spec: Dictionary
var _spin := 0.0
## Karosserie federt beim Wanken und Nicken nach (Feder mit leichter Dämpfung, seit 2.23). Die Drehrate folgt der
## Lenkung seit 2.24 wieder fast sofort wie in NFSU: die deutliche Trägheit aus 2.23 (Forza-Vergleich) war zu träge.
var _yaw_v := 0.0
var _roll_s := 0.0
var _roll_sv := 0.0
var _pitch_s := 0.0
var _pitch_sv := 0.0
var _on_walk := false
var _crash_cooldown := 0.0
var _ground_vy := 0.0
var _curb_y := 0.0  # Bordstein-Anteil der Höhe (weich), die Fahrbahnhöhe selbst gilt sofort
var _base_y := 0.0
var _base_vy := 0.0
var _base_ok := false
var _slope_pitch := 0.0
var _yaw_prev := 0.0
var _slope_roll := 0.0
var _cam_yaw := 0.0
var _cam_pos := Vector3.ZERO
var _cam_init := false
var jump_cam := false
var _jc_pos := Vector3.ZERO
var _jc_look := Vector3.ZERO
var _jc_landed := false
var _jc_hold := 0.0  # Echtzeit seit dem Aufsetzen
var _slowmo := 1.0  # Zeitfaktor, weich ein- und ausgeblendet
var _jc_slow := 1.0  # Ziel-Zeitfaktor dieses Sprungs
var _jc_light: OmniLight3D  # Aufhelllicht auf der Kameraseite: nachts von vorn wäre das Auto sonst fast schwarz
var _respawn_xf := Transform3D.IDENTITY
var _last_prog := 0.0


func setup(car_id: String, cfg: Dictionary) -> void:
	_spec = Catalog.CARS[car_id]
	var nos := Catalog.part_of(cfg, "nitro")
	# Tuning wirkt wirklich: Motor und Turbo auf Schub und Endtempo, Fahrwerk und Reifen auf Grip und Lenkung
	var st := Catalog.stats(car_id, cfg)
	accel = st["accel"]
	top_speed = st["top"]
	grip_k = st["grip"] * 0.6
	steer_rate = st["steer"]
	lat_acc = 14.0 + st["grip"] * 0.42  # 2,3–2,7 g ab Werk: griffig wie NFSU, aber enge Ecken wollen angebremst werden
	drift_k = st["drift"]
	drive_type = _spec.get("drive", "rwd")
	nitro_power = nos["power"]
	nitro_cap = nos["capacity"]

	model = Builder.build(car_id, cfg)
	add_child(model)
	_length = model.get_meta("length")
	_axle = model.get_meta("axle", 0.78)
	# Grundriss mit runden Ecken (vorn stärker): an Kanten, Pfosten und Inselspitzen gleitet das Auto ab,
	# statt frontal hängen zu bleiben
	var col := CollisionShape3D.new()
	var w: float = model.get_meta("width") / 2.0
	var l := _length / 2.0
	var pts := PackedVector3Array()
	for y in [-0.6, 0.6]:
		for corner in [[Vector2(w, -l), 0.62, Vector2(-1, 1)], [Vector2(-w, -l), 0.62, Vector2(1, 1)],
				[Vector2(w, l), 0.35, Vector2(-1, -1)], [Vector2(-w, l), 0.35, Vector2(1, -1)]]:
			var r: float = corner[1]
			var c: Vector2 = corner[0] + corner[2] * r  # Mittelpunkt der Rundung
			var out: Vector2 = -corner[2]
			for k in 7:
				var a := PI / 2.0 * k / 6.0
				pts.append(Vector3(c.x + out.x * r * sin(a), y, c.y + out.y * r * cos(a)))
	var hull := ConvexPolygonShape3D.new()
	hull.points = pts
	col.shape = hull
	var shape := BoxShape3D.new()
	shape.size = Vector3(w * 2.0, 1.2, _length)
	col.position.y = 0.7
	add_child(col)
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	collision_layer = 2
	collision_mask = 1 | 2
	# Fühler für Laternen, Mülltonnen & Co.
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = Knockable.LAYER
	area.monitorable = false
	var acs := CollisionShape3D.new()
	var abs_shape := BoxShape3D.new()
	abs_shape.size = shape.size + Vector3(0.2, 0.0, 0.3)
	acs.shape = abs_shape
	acs.position.y = 0.7
	area.add_child(acs)
	area.body_entered.connect(_on_prop_hit)
	add_child(area)

	cam = Camera3D.new()
	cam.far = GameState.view_distance()  # dahinter verschluckt ohnehin der Nebel fast alles
	cam.near = 0.05
	cam.doppler_tracking = Camera3D.DOPPLER_TRACKING_PHYSICS_STEP  # Gegner und Verkehr ziehen mit Dopplereffekt vorbei
	add_child(cam)
	cam.make_current()
	cam_mode = clampi(GameState.cam_mode, 0, CAM_NAMES.size() - 1)
	_apply_cam()

	audio = EngineAudio.new()
	var snd: Dictionary = _spec["sound"].duplicate()
	snd["car"] = car_id
	var turbo_stage := int(cfg.get("turbo", 0))
	if turbo_stage > 0:
		snd["turbo"] = maxf(snd.get("turbo", 0.0), 0.35 + 0.2 * turbo_stage)  # nachgerüsteter Lader zischt hörbar
		snd["bov"] = "bov"  # mit Blow-off-Ventil; der Serienlader flattert
	audio.configure(snd)
	add_child(audio)
	var ex := int(cfg.get("exhaust", 0))
	_crackle = clampf(0.35 + (0.25 if ex > 0 else 0.0) + (0.15 if ex == 5 else 0.0) + (0.1 if snd.get("turbo", 0.0) > 0.3 else 0.0), 0.0, 0.9)


func _apply_cam() -> void:
	_cam_init = false
	if _chase():
		cam.top_level = true
		return
	cam.top_level = false
	cam.transform = Transform3D.IDENTITY
	if cam_mode == 2:
		cam.position = Vector3(0, 0.5, -_length / 2 - 0.05)
		cam.rotation_degrees.x = -1.0
	else:
		cam.position = model.get_meta("eye")
		cam.rotation_degrees.x = -5.0


func toggle_camera() -> void:
	cam_mode = (cam_mode + 1) % CAM_NAMES.size()
	GameState.cam_mode = cam_mode
	GameState.save_game()
	_apply_cam()


func _chase() -> bool:
	return cam_mode <= 1


func _on_prop_hit(body: Node) -> void:
	if body.has_method("knock") and not body.knocked:
		# Treffpunkt auf Stoßstangenhöhe: hohe Teile kippen um, statt als Ganzes wegzufliegen
		var fwd := -global_basis.z
		body.knock(velocity, global_position + fwd * _length * 0.5 + Vector3(0, 0.55, 0))
		velocity *= 1.0 - (1.0 - body.slowdown) * 0.65  # kostet Tempo, aber man bleibt nicht hängen
		_shake = minf(_shake + 0.12, 1.0)
		audio.crash(0.15 + body.mass / 200.0)
		if body.has_meta("clang"):
			Sfx.play("clang", -6.0, randf_range(0.85, 1.1))


func _physics_process(dt: float) -> void:
	var thr := Input.get_action_strength("accelerate")
	var brk := Input.get_action_strength("brake")
	var steer_in := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	var hb := Input.is_action_pressed("handbrake")
	var want_nitro := Input.is_action_pressed("nitro")
	stun = maxf(stun - dt, 0.0)
	_crash_cooldown = maxf(_crash_cooldown - dt, 0.0)
	_wall_cool = maxf(_wall_cool - dt, 0.0)
	if sinking > 0.0:
		_update_sinking(dt)
		return
	if tumbling:
		_update_tumble(dt)
		return
	if stun > 0.0:
		# Nach einem Crash kurz keine Kontrolle
		thr = 0.0
		steer_in = 0.0
		want_nitro = false
	_nos_block = stun > 0.0 or not controls_enabled
	if not controls_enabled:
		# Vor dem Start darf man trotzdem am Gas spielen (Drehzahl hochjagen)
		if not finished:
			# Weicher Begrenzer: pendelt sanft knapp unter der Schaltdrehzahl
			var lim := SHIFT_RPM - 300.0 + sin(Time.get_ticks_msec() * 0.025) * 150.0
			rpm = move_toward(rpm, 900.0 + thr * (lim - 900.0), dt * (7000.0 if thr > 0.1 else 4000.0))
		thr = 0.0
		# nach dem Ziel bremsen bis zum Stand (nicht weiter: Bremse im Stand wäre Rückwärtsgang)
		brk = 1.0 if finished and speed_fwd > 0.3 else 0.0
		steer_in = 0.0
		hb = false
		want_nitro = false

	if drag_mode:
		# Drag: Spur per Tipp wechseln, gelenkt wird automatisch; geschaltet wird von Hand
		hb = false
		if controls_enabled and not blown:
			if Input.is_action_just_pressed("steer_left"):
				drag_lane = maxi(drag_lane - 1, 0)
			elif Input.is_action_just_pressed("steer_right"):
				drag_lane = mini(drag_lane + 1, 3)
			if Input.is_action_just_pressed("shift_up") and gear < 6:
				_drag_shift(1)
			elif Input.is_action_just_pressed("shift_down") and gear > 1:
				_drag_shift(-1)
		steer_in = 0.0  # gelenkt wird von der Schiene (_drag_rail)
		if controls_enabled:
			brk = 0.0  # S ist im Drag die Taste zum Hochschalten
		if blown:
			thr = 0.0
			want_nitro = false
			_nos_block = true

	# Wandkontakt: das Auto dreht über einige Bilder parallel zur Wand (Schrammen), statt auf einen Schlag
	# umzuspringen. Ohne neuen Kontakt klingt die Restdrehung aus.
	var walling := absf(_wall_turn) > 0.03
	_wall_t += dt
	if absf(_wall_turn) > 0.0005:
		var turn := clampf(_wall_turn * (1.0 - exp(-dt * 10.0)), -WALL_TURN_RATE * dt, WALL_TURN_RATE * dt)
		_rotate_front(turn, 0.0)
		_wall_turn = (_wall_turn - turn) * exp(-dt * 1.5)
	var fwd := -global_basis.z
	fwd.y = 0
	fwd = fwd.normalized()
	var right := Vector3(-fwd.z, 0, fwd.x)
	var hvel := Vector3(velocity.x, 0, velocity.z)
	speed_fwd = hvel.dot(fwd)
	speed_lat = hvel.dot(right)
	if _rail_on and not airborne:
		speed_fwd = _rail_speed
	_rail_on = false
	if controls_enabled and not _was_enabled:
		_thr_s = thr  # LOS: wer schon Gas gibt, lässt die Kupplung kommen (kein langsames Anrollen)
	_was_enabled = controls_enabled
	var spd := absf(speed_fwd)

	# --- Gänge & Drehzahl. Hochschalten am Gangende, Zurückschalten erst deutlich darunter (Hysterese): sonst pendelt
	# das Getriebe an einer Grenze hin und her, jeder Schaltvorgang nimmt kurz den Vortrieb und das Auto kommt nicht weiter.
	# Vortrieb: Gang nach dem Tempo nach vorn (so ist das Fahrverhalten abgestimmt)
	var ratio := spd / top_speed
	if drag_mode:
		_pull_gear = gear  # Handschaltung (oben)
	elif _pull_gear < 6 and ratio > GEARS[_pull_gear]:
		_pull_gear += 1
		_shift_timer = 0.2
	elif _pull_gear > 1 and ratio < GEARS[_pull_gear - 1] * 0.88:
		_pull_gear -= 1
	_shift_timer = maxf(_shift_timer - dt, 0.0)
	# Gang und Drehzahl, die man hört und auf dem Drehzahlmesser sieht: nach dem Tempo über Grund. Steht das Auto
	# im Drift quer, ist das Tempo nach vorn viel kleiner; danach schaltete der Motor mitten im Drift herunter und
	# die Drehzahl sprang. Jetzt bleibt der Gang, und mit Gas dreht der Motor im Drift hoch (Räder drehen durch).
	var g_ratio := ratio
	if not drag_mode:
		if speed_fwd > 0.0:
			g_ratio = maxf(spd, hvel.length()) / top_speed
		if gear < 6 and g_ratio > GEARS[gear]:
			gear += 1
			_upshift(thr)
		elif gear > 1 and g_ratio < GEARS[gear - 1] * 0.88:
			gear -= 1
	if controls_enabled or finished:
		var target_rpm: float
		var pull_target: float
		if airborne:
			# Räder in der Luft: Motor dreht frei hoch
			target_rpm = 1500.0 + thr * 5800.0
			pull_target = target_rpm
		elif drag_mode:
			# ohne Hochschalten dreht der Motor bis in den Begrenzer (dort kein Vortrieb, er wird heiß)
			var per_ratio: float = SHIFT_RPM / GEARS[gear] if gear < 6 else TOP_RPM
			var raw := maxf(900.0 + thr * 600.0, ratio * per_ratio)
			if spd < 6.0 and thr > 0.5:
				raw = maxf(raw, 2500.0 + 1500.0 * thr)  # Anfahren: Kupplung schleift, Motor bleibt im Drehmoment
			if gear == 6:
				raw = minf(raw, PERFECT_SHIFT.y - 100.0)  # letzter Gang: Nitro darf über Topspeed schieben, ohne Begrenzer
			_limiter = raw >= DRAG_LIMIT - 40.0 and thr > 0.1
			target_rpm = clampf(raw, 900.0, DRAG_LIMIT)
			if _limiter:
				target_rpm = DRAG_LIMIT - absf(sin(Time.get_ticks_msec() * 0.05)) * 350.0
			if speed_fwd < -0.5:
				target_rpm = 900.0 + spd * 300.0
			if hb and thr > 0.5 and spd < 25.0:
				target_rpm = maxf(target_rpm, 6500.0)
			pull_target = target_rpm
		else:
			pull_target = _gear_rpm(_pull_gear, ratio, thr, hb, spd, 0.0)
			var spin := thr * (400.0 + 700.0 * clampf((drift_angle - 5.0) / 25.0, 0.0, 1.0)) if drifting else 0.0
			target_rpm = _gear_rpm(gear, g_ratio, thr, hb, spd, spin)
		var rate := dt * (9000.0 if airborne else 20000.0)
		rpm = move_toward(rpm, target_rpm, rate)
		_pull_rpm = move_toward(_pull_rpm, pull_target, rate)

	# --- Nitro (funktioniert auch in der Luft). Leer ist leer: erst nach dem Loslassen geht es wieder
	# (sonst hält das minimale Nachladen den Schub bei gedrückter Taste ewig am Leben). Kein Dauerfeuer: einmal
	# gezündet brennt es mindestens NOS_MIN_BURN, nach dem Abschalten ist es NOS_RELOCK lang gesperrt.
	if not want_nitro:
		_nos_empty = false
	_nos_burn = maxf(_nos_burn - dt, 0.0)
	_nos_lock = maxf(_nos_lock - dt, 0.0)
	var nos_can := nitro > 0.0 and speed_fwd > 4.0 and not _nos_empty and not _nos_block
	if nitro_on:
		nitro_on = nos_can and (want_nitro or _nos_burn > 0.0)
		if not nitro_on:
			_nos_lock = NOS_RELOCK
	else:
		nitro_on = nos_can and want_nitro and _nos_lock <= 0.0
		if nitro_on:
			_nos_burn = NOS_MIN_BURN
	if nitro_on:
		nitro = maxf(nitro - dt * 0.3 / nitro_cap, 0.0)
		if nitro <= 0.0:
			_nos_empty = true
	else:
		# langsam von selbst; Drift, knapp vorbei und Sprünge geben Punkte, die etwas nachfüllen (race.gd)
		nitro = minf(nitro + dt * 0.022 / nitro_cap, 1.0)
	_nos_k = move_toward(_nos_k, 1.0 if nitro_on else 0.0, dt * (2.8 if nitro_on else 5.0))
	_update_pops(thr, dt)

	# --- Längsbeschleunigung (Drehmoment über die Drehzahl, unten herum Traktionsgrenze)
	_thr_s = move_toward(_thr_s, thr, dt * (3.0 if thr > _thr_s else 7.0))
	var tq := _torque(_pull_rpm)
	if drag_mode:
		# Drag: Drehmoment kommt erst oben (zu früh schalten kostet richtig), im Begrenzer nichts
		tq = 0.0 if _limiter else 0.55 + 0.45 * smoothstep(2500.0, 6800.0, rpm)
		if controls_enabled and not blown:
			var hot := rpm > PERFECT_SHIFT.y + 100.0 and gear < 6
			engine_heat = clampf(engine_heat + dt * ((0.42 if _limiter else 0.16) if hot else -0.12), 0.0, 1.0)
			if engine_heat >= 1.0:
				blown = true
				Sfx.play("clang", 0.0, 0.6)
				audio.crash(0.8)
	var a := 0.0
	var eff_top := top_speed * (1.0 + 0.22 * nitro_power * _nos_k)
	# Luftwiderstand so, dass das Auto wie bis 2.12 bei knapp 95 % von top_speed ausdreht (Abgleich mit den Gegnern);
	# der Drag rechnet mit eigener Drehmomentkurve und behält den alten Wert
	var drag_k: float = accel * GEAR_PULL[6] / (top_speed * top_speed)
	if not drag_mode:
		drag_k = accel * GEAR_PULL[6] * _torque(VMAX_K * TOP_RPM) / pow(VMAX_K * top_speed, 2.0)
	a += 8.0 * nitro_power * _nos_k
	if _launch_t > 0.0:
		_launch_t = maxf(_launch_t - dt, 0.0)
	elif _launch_t < 0.0:
		_launch_t = minf(_launch_t + dt, 0.0)
	_shift_boost = maxf(_shift_boost - dt, 0.0)
	if airborne:
		a -= drag_k * 0.5 * speed_fwd * absf(speed_fwd)
	else:
		# Schaltpause: kurz kaum Zug (Kupplung), danach setzt der neue Gang wieder ein
		var drive: float = accel * _thr_s * GEAR_PULL[_pull_gear] * tq * (0.3 if _shift_timer > 0.0 else 1.0)
		if spd < 8.0 and speed_fwd > -0.5:
			# Anfahren: Haftung begrenzt, der Zug baut sich mit dem Tempo auf (perfekter Start: volle Haftung).
			# Allrad greift am besten, Fronttriebler am schlechtesten (Gewicht geht beim Anfahren nach hinten)
			var base: float = 0.65 if drift_mode or drag_mode else DRIVE[drive_type]["launch"]
			drive *= 1.0 if _launch_t > 0.0 else base + (1.0 - base) * pow(spd / 8.0, 0.7)
		if reverse_gear:
			drive = 0.0  # im Rückwärtsgang zieht Gas nicht nach vorn (es bremst, siehe _brake_and_reverse)
		if _launch_t > 0.0:
			drive += accel * 0.3 * _thr_s * _launch_t
		elif _launch_t < 0.0:
			drive *= 0.75  # durchdrehende Räder
		drive += accel * 0.6 * _shift_boost / 0.5  # über eine halbe Sekunde etwa so viel wie früher der Sprung (+1,6 m/s)
		a += drive
		a -= drag_k * speed_fwd * absf(speed_fwd)
		if thr < 0.05 and brk < 0.05:
			a -= signf(speed_fwd) * 1.6  # Motorbremse
		_holding = false
		if drag_mode:
			if brk > 0.0 and speed_fwd > 1.0:
				a -= BRAKE * brk
		else:
			a += _brake_and_reverse(thr, brk, dt)
		if hb:
			a -= signf(speed_fwd) * 4.0
		# Bergauf etwas zäher, bergab etwas Schwung (abgeschwächt, damit es nicht frustriert)
		a -= 6.0 * sin(_slope_pitch)
	if speed_fwd > eff_top:
		a = minf(a, -4.0)
	speed_fwd += a * dt
	if not airborne and ((absf(speed_fwd) < 0.3 and thr < 0.05 and brk < 0.05) or (_holding and absf(speed_fwd) < 0.8)):
		speed_fwd = 0.0

	# --- Lenkung (in der Luft wirkungslos). Bei Tempo schlägt das Lenkrad etwas langsamer ein (Tastatur).
	var sf0 := clampf(spd / top_speed, 0.0, 1.0)
	var steer_speed := lerpf(6.0, 3.0, sf0) if absf(steer_in) > 0.01 else lerpf(8.0, 5.0, sf0)
	if steer_in * steer < 0.0:
		steer_speed = lerpf(9.0, 6.0, sf0)  # Gegenlenken geht schneller als Einlenken
	steer = move_toward(steer, steer_in, dt * steer_speed)
	var low_speed := clampf(spd / 2.0, 0.0, 1.0)
	# Drehrate: langsam begrenzt durch den Wendekreis (Lenkgeometrie), bei Tempo durch die Querbeschleunigung
	var lat_eff := lat_acc * (1.0 - 0.12 * sf0)  # bei Topspeed etwas weniger wendig
	var high_speed := minf(1.0, minf(lat_eff / maxf(spd, 0.1), spd / MIN_RADIUS) / steer_rate)
	var l2 := 0.0
	if drag_mode and not airborne and not loc.is_empty() and loc["path"]["id"] == 0 and (controls_enabled or finished):
		l2 = _drag_rail(dt)
	elif drift_mode and _sliding and not airborne:
		_slip_hold = 0.6
		l2 = _slide_physics(dt, fwd, right, thr, hb, a, eff_top, low_speed)
	else:
		# Heckantrieb: Vollgas bei engem Einschlag und mittlerem Tempo lässt das Heck etwas kommen (stufenlos).
		# Fronttriebler schieben dagegen unter Gas über die Vorderräder nach außen, Allradler ein wenig; beim
		# Gaswegnehmen in der Kurve dreht ein Fronttriebler etwas ein. Im Drift-Event fahren alle gleich.
		var dt_k: Dictionary = DRIVE["rwd"] if drift_mode or drag_mode else DRIVE[drive_type]
		var po := 0.0
		var push := 0.0
		if not airborne:
			var corner := smoothstep(0.35, 0.9, absf(steer))
			po = _thr_s * corner * smoothstep(6.0, 12.0, spd) \
				* (1.0 - smoothstep(top_speed * 0.4, top_speed * 0.7, spd)) * dt_k["oversteer"]
			push = _thr_s * corner * smoothstep(8.0, 20.0, spd) * dt_k["understeer"]
			if drive_type == "fwd" and not drift_mode and thr < 0.05 and spd > 12.0:
				push = -0.06 * corner  # Lastwechsel: Heck wird leicht
		if hb and spd > 8.0 and not airborne:
			_slip_hold = move_toward(_slip_hold, 1.0, dt * 5.0)
		elif brk > 0.3 and absf(steer) > 0.5 and spd > 18.0 and not airborne:
			# Anbremsen in die Kurve: das Heck wird leicht und kommt ein Stück (wie in NFSU reinbremsen und rutschen)
			_slip_hold = move_toward(_slip_hold, 0.35 * brk * absf(steer), dt * 3.0)
		else:
			# Gas hält den Drift (Driftautos länger), ohne Gas fängt sich das Auto
			_slip_hold = move_toward(_slip_hold, 0.0, dt * lerpf(2.2, 0.9, drift_k) * (1.0 - 0.55 * _thr_s))
		var yaw := 0.0
		if not airborne:
			yaw = -steer * steer_rate * low_speed * high_speed * signf(speed_fwd + 0.001)
			yaw *= 1.0 + (0.12 + 0.2 * drift_k) * _slip_hold + 0.1 * po + (0.4 if hb else 0.0) - push
			if drift_mode:
				# Drift-Modus: mit Gas und voll eingelenkt bricht das Heck aus
				yaw *= 1.0 + 0.25 * smoothstep(0.5, 1.0, absf(steer)) * _thr_s * smoothstep(10.0, 16.0, spd)
		_spin = move_toward(_spin, 0.0, dt * 2.0)
		# kaum Trägheit (glättet nur Sprünge in der Drehrate); 2.23 hatte 15/6,5 und war zu träge
		var yaw_k := 4.0 if airborne else lerpf(30.0, 20.0, sf0)
		_yaw_v = lerpf(_yaw_v, yaw, 1.0 - exp(-dt * yaw_k))
		_rotate_front((_yaw_v + _spin) * dt, 0.6 * _slip_hold)

		# Neue Fahrzeugachse; Geschwindigkeit bleibt zunächst in Weltrichtung -> Querschlupf entsteht
		var new_fwd := -global_basis.z
		new_fwd.y = 0
		new_fwd = new_fwd.normalized()
		var new_right := Vector3(-new_fwd.z, 0, new_fwd.x)
		var v := fwd * speed_fwd + right * speed_lat
		var f2 := v.dot(new_fwd)
		l2 = v.dot(new_right)

		# --- Grip: Querbewegung abbauen. Die Fahrtrichtung dreht zur Fahrzeugachse, der Betrag bleibt (Kurven
		# schenken kein Tempo); nur das Rutschen radiert je nach Winkel etwas ab.
		if not airborne:
			var gk := grip_k * lerpf(1.0, lerpf(0.35, 0.2, drift_k), _slip_hold) * (1.0 - 0.3 * po)
			# Am Grip-Limit (stark eingelenkt bei Tempo) arbeiten die Reifen sichtbar: das Auto steht ein paar Grad
			# schräg in der Kurve und radiert, wie in NFSU, ohne zu driften (bleibt unter der Drift-Schwelle). Der
			# Kurvenradius bleibt gleich, die Drehrate gibt weiter die Lenkung vor.
			gk *= 1.0 - 0.5 * smoothstep(0.5, 1.0, absf(steer)) * smoothstep(14.0, 24.0, spd) * (1.0 - _slip_hold)
			if hb:
				gk *= lerpf(0.45, 0.35, drift_k)
			if drift_mode:
				gk *= 0.4  # im Drift-Modus bricht das Heck leichter aus
			if stun > 0.0:
				gk *= 0.25
			if walling:
				gk *= 0.35  # an der Wand entlang schrammend: die Reifen ziehen das Auto nicht wieder hinein
			var l_new := l2 * exp(-gk * dt)
			# Betrag der Geschwindigkeit bleibt (nur das Rutschen radiert ab), die Richtung dreht zur Fahrzeugachse
			var vs := sqrt(f2 * f2 + l2 * l2)
			var sin_b := absf(l_new) / maxf(vs, 1.0)
			vs = maxf(vs - lerpf(6.0, 3.5, drift_k) * sin_b * dt, 0.0)
			var f_new := signf(f2) * sqrt(maxf(vs * vs - l_new * l_new, 0.0))
			f2 = minf(f_new, maxf(eff_top, speed_fwd))
			l2 = l_new
			var ang := rad_to_deg(atan2(absf(l2), maxf(absf(f2), 0.1)))
			# Schwelle mit Puffer: kein Flackern; Schrammen an der Wand ist kein Drift (keine Punkte, kein Nitro)
			drifting = spd > 10.0 and ang > (6.0 if drifting else 10.0) and _wall_t > 0.5
			drift_angle = ang if drifting else 0.0
			if drift_mode and spd > 10.0 and ang > 9.0 and f2 > 0.0 and _wall_t > 0.5:
				_sliding = true
				_slide_out = 0.0
		else:
			drifting = false
			drift_angle = 0.0
		velocity = new_fwd * f2 + new_right * l2
		velocity.y = 0.0
	var pre := velocity
	move_and_slide()
	_handle_collisions(pre)
	if _rail_on:
		_rail_speed = Vector3(velocity.x, 0.0, velocity.z).dot(_rail_tf)
	_update_vertical(dt)

	# --- Optik, Kamera, Sound
	var sf := clampf(spd / top_speed, 0.0, 1.0)
	# Gewichtsverlagerung: Nase taucht beim Bremsen ein, hebt sich beim Beschleunigen; Wanken nach der echten
	# Querbeschleunigung (Gierrate * Tempo) nach außen, im Rutschen zusätzlich zur Rutschseite
	var pitch := clampf(a * 0.0034, -0.065, 0.045)
	if airborne:
		pitch = 0.0  # in der Luft dreht sich das ganze Auto (unten), nicht die Karosserie
	var yaw_now := wrapf(global_rotation.y - _yaw_prev, -PI, PI) / maxf(dt, 0.0001)
	_yaw_prev = global_rotation.y
	var roll := clampf(-yaw_now * spd / 9.81 * 0.03, -0.085, 0.085) - clampf(l2 * 0.003, -0.035, 0.035)
	if airborne:
		roll = 0.0
	# Federung: knapp 1,6 Hz, leicht unterdämpft (wippt beim Einlenken und Bremsen einmal sanft nach)
	var w0 := 10.0
	_roll_sv += (w0 * w0 * (roll - _roll_s) - 2.0 * 0.45 * w0 * _roll_sv) * dt
	_roll_s += _roll_sv * dt
	_pitch_sv += (w0 * w0 * (pitch - _pitch_s) - 2.0 * 0.5 * w0 * _pitch_sv) * dt
	_pitch_s += _pitch_sv * dt
	Builder.animate(model, speed_fwd, steer, _roll_s, _pitch_s, nitro_on, dt, _wheel_speeds(thr, brk, hb, spd, dt), _backfire)
	# Ganzes Auto in die Steigung neigen (Trog, Bergstraße)
	if not airborne:
		model.rotation.x = lerp_angle(model.rotation.x, _slope_pitch, 1.0 - exp(-dt * 12.0))
		model.rotation.z = lerp_angle(model.rotation.z, _slope_roll, 1.0 - exp(-dt * 12.0))
	else:
		# Flug: die Nase folgt der Flugbahn mit etwas Trägheit (nach der Rampe noch oben, dann kippt sie ab),
		# einmal angestoßenes Rollen (Kante seitlich runter) läuft weiter
		var target := clampf(atan2(vy, maxf(spd, 1.0)) * 1.4, -0.6, 0.45)
		_air_pitch_v += ((target - _air_pitch) * 10.0 - _air_pitch_v * 4.5) * dt
		_air_pitch += _air_pitch_v * dt
		_air_roll_v *= exp(-0.5 * dt)
		_air_roll += _air_roll_v * dt
		model.rotation.x = _air_pitch
		model.rotation.z = _air_roll
	_update_camera(dt, sf)

	audio.rpm = rpm
	audio.throttle = 1.0 if nitro_on else (0.0 if finished else (_rev_s if reverse_gear else Input.get_action_strength("accelerate")))
	audio.nitro = nitro_on
	# Reifen (0..1): bis 2.15 nur aus dem Querrutschen in m/s – das reichte im normalen Rennen nie, selbst mit
	# Handbremse rutscht das Auto bei Tempo nur 2–3 m/s quer. Jetzt wie in NFSU: der Rutschwinkel, Kurvenfahrt am
	# Grip-Limit (Schrubben, leises Quietschen), Handbremse, Vollbremsung, Drift und durchdrehende Räder beim Start.
	var tire := 0.0
	if spd > 5.0 and not airborne:
		var slip_ang := rad_to_deg(atan2(absf(l2), maxf(absf(speed_fwd), 1.0)))
		var load := absf(yaw_now) * spd / maxf(lat_acc, 1.0)
		tire = smoothstep(2.5, 12.0, slip_ang)
		tire = maxf(tire, 0.5 * smoothstep(0.7, 1.0, load) * smoothstep(10.0, 20.0, spd))
		if hb and spd > 8.0:
			tire = maxf(tire, 0.8)
		if brk > 0.6 and speed_fwd > 15.0 and not reverse_gear and not drag_mode:
			tire = maxf(tire, 0.42 * brk)
		if _wheel_v.x == 0.0 and speed_fwd > 4.0:
			tire = maxf(tire, 0.55 * smoothstep(4.0, 14.0, speed_fwd))  # blockierte Räder radieren
		if drifting:
			tire = maxf(tire, 0.7)
	if _launch_t < 0.0 and _thr_s > 0.5:
		tire = maxf(tire, 0.7)
	audio.slip = tire
	audio.speed = spd
	_scrape_hold = maxf(_scrape_hold - dt, 0.0)
	if _scrape_hold <= 0.0:
		_scrape = move_toward(_scrape, 0.0, dt * 6.0)
	audio.scrape = _scrape


## Umfangsgeschwindigkeit der Räder vorn/hinten (m/s) für die Optik: sie rollen mit dem Tempo, blockieren bei der
## Bremse (alle vier) und der Handbremse (hinten), drehen an der Antriebsachse durch (Start mit zu viel Gas, Anfahren
## mit Vollgas, Drift) und laufen in der Luft frei weiter; Gas in der Luft lässt die Antriebsräder hochdrehen.
func _wheel_speeds(thr: float, brk: float, hb: bool, spd: float, dt: float) -> Vector2:
	var front_drive := drive_type in ["fwd", "awd"]
	var rear_drive := drive_type != "fwd"
	var t := Vector2(speed_fwd, speed_fwd)
	if airborne:
		t = _wheel_v * exp(-0.5 * dt)
		if thr > 0.1:
			if front_drive:
				t.x = speed_fwd + 25.0 * thr
			if rear_drive:
				t.y = speed_fwd + 25.0 * thr
	elif controls_enabled and not finished:
		var spin := 0.0
		if _launch_t < 0.0 and _thr_s > 0.5:
			spin = 16.0  # Start mit zu viel Gas: Räder drehen durch
		elif drifting and thr > 0.2:
			spin = (6.0 + spd * 0.25) * thr
		elif thr > 0.8 and spd < 7.0 and gear <= 1 and not reverse_gear:
			spin = (7.0 - spd) * 1.3  # kurzes Scharren beim Anfahren mit Vollgas
		if front_drive:
			t.x += spin
		if rear_drive:
			t.y += spin
		if brk > 0.3 and speed_fwd > 1.5 and not reverse_gear:
			t = Vector2.ZERO  # Vollbremsung: alle vier blockieren
		if hb and absf(speed_fwd) > 0.5:
			t.y = 0.0  # Handbremse: hinten blockiert
	# Blockieren geht schlagartig, Hochdrehen und Wiederanrollen dauern einen Moment
	_wheel_v.x = move_toward(_wheel_v.x, t.x, dt * (400.0 if t.x == 0.0 else 70.0))
	_wheel_v.y = move_toward(_wheel_v.y, t.y, dt * (400.0 if t.y == 0.0 else 70.0))
	return _wheel_v


## Drehmoment über der Drehzahl (0..1): unten weniger, ab ~5.000/min voll, oben leicht abfallend
func _torque(r: float) -> float:
	var x := clampf((r - 1000.0) / 6200.0, 0.0, 1.0)
	return 0.7 + 0.3 * sin(minf(x * 1.4, 1.0) * PI / 2.0) - 0.1 * maxf(x - 0.8, 0.0) / 0.2


## Start-Wertung (race.gd): k > 0 perfekter Start, k < 0 zu viel Gas
func launch(k: float) -> void:
	_launch_t = 1.2 * k if k > 0.0 else -0.7


## Drehzahl im Gang g bei Tempoanteil r: proportional zur Geschwindigkeit, im 6. Gang liegt Topspeed bei TOP_RPM.
## spin: Zuschlag für durchdrehende Räder im Drift.
## Bremsen und Rückwärtsgang wie im Auto statt wie ein Hoverboard: die Bremse verzögert bis zum Stand. Wer im Stand
## weiter bremst, legt nach kurzer Pause den Rückwärtsgang ein und rollt gemächlich rückwärts. Gas im Rückwärtsgang
## bremst erst bis zum Stand, nach einem kurzen Moment geht es vorwärts. Liefert die Beschleunigung (m/s²).
func _brake_and_reverse(thr: float, brk: float, dt: float) -> float:
	var a := 0.0
	if not reverse_gear:
		_rev_s = 0.0
		if brk > 0.05:
			if speed_fwd > 0.6:
				a -= BRAKE * brk
				_change_t = 0.0
			elif speed_fwd > -0.6:
				_holding = true
				_change_t += dt
				if _change_t > TO_REVERSE and thr < 0.05:
					reverse_gear = true
					_change_t = 0.0
			else:
				a += BRAKE * brk  # rollt im Vorwärtsgang zurück (Abprall, Hang): Bremse bremst
		else:
			_change_t = 0.0
	else:
		if thr > 0.05:
			_rev_s = move_toward(_rev_s, 0.0, dt * 6.0)
			if speed_fwd < -0.6:
				a += BRAKE * 0.8 * thr
				_change_t = 0.0
			else:
				_holding = true
				_change_t += dt
				if _change_t > TO_FORWARD:
					reverse_gear = false
					_change_t = 0.0
		elif brk > 0.05:
			_change_t = 0.0
			if speed_fwd > 0.6:
				a -= BRAKE * brk
			else:
				_rev_s = move_toward(_rev_s, brk, dt * 2.5)
				a -= REV_ACCEL * _rev_s * (1.0 - smoothstep(REV_TOP * 0.6, REV_TOP, -speed_fwd))
		else:
			_change_t = 0.0
			_rev_s = move_toward(_rev_s, 0.0, dt * 6.0)
	return a


## Hochschalten unter Last: der Motor nimmt kurz die Zündung weg (hörbar), bei hoher Drehzahl knallt es manchmal im
## Auspuff, mit Flamme. Sportauspuff und Turbo knallen öfter.
func _upshift(thr: float) -> void:
	if not controls_enabled or thr < 0.5:
		return
	audio.shift()
	if rpm > 5200.0 and _crackle_cool <= 0.0 and randf() < _crackle:
		_pops.append([randf_range(0.04, 0.08), randf_range(0.75, 1.0)])
		_crackle_cool = 0.6


## Fehlzündungen: Gas weg bei hoher Drehzahl knallt und blubbert es ein paar Mal nach (unverbranntes Gemisch). Die
## Knalle stehen in _pops und kommen nacheinander, jeder mit Flamme und Ton.
func _update_pops(thr: float, dt: float) -> void:
	_crackle_cool = maxf(_crackle_cool - dt, 0.0)
	if controls_enabled and _thr_prev > 0.5 and thr < 0.1 and rpm > 4500.0 and not nitro_on and _thr_held > 0.5 \
			and _crackle_cool <= 0.0 and randf() < _crackle + 0.15:
		var t := randf_range(0.03, 0.09)
		for i in randi_range(1, 4):
			_pops.append([t, randf_range(0.45, 0.9) * (1.0 - i * 0.15)])
			t += randf_range(0.07, 0.2)
		_crackle_cool = 1.5
	_thr_held = _thr_held + dt if thr > 0.5 else 0.0
	_thr_prev = thr
	_backfire = move_toward(_backfire, 0.0, dt * 9.0)
	var i := 0
	while i < _pops.size():
		_pops[i][0] -= dt
		if _pops[i][0] <= 0.0:
			var st: float = _pops[i][1]
			_backfire = maxf(_backfire, st)
			audio.backfire(st)
			_pops.remove_at(i)
		else:
			i += 1


func _gear_rpm(g: int, r: float, thr: float, hb: bool, spd: float, spin: float) -> float:
	var per_ratio: float = SHIFT_RPM / GEARS[g] if g < 6 else TOP_RPM
	var t := clampf(maxf(900.0 + thr * 600.0, r * per_ratio), 900.0, SHIFT_RPM + 300.0)
	if g == 1 and spd < 6.0 and thr > 0.5:
		t = maxf(t, 2500.0 + 1500.0 * thr)  # Anfahren: Kupplung schleift, Motor bleibt im Drehmoment
	if speed_fwd < -0.5:
		t = 900.0 + spd * 300.0
	elif spin > 0.0:
		t = maxf(t, minf(t + spin, SHIFT_RPM - 400.0))  # hoch, aber nicht im Begrenzer
	if hb and thr > 0.5 and spd < 25.0:
		t = maxf(t, 6500.0)
	return t


## Drag: Schaltvorgang bewerten. Im grünen Bereich kaum Zugkraftunterbrechung und ein kleiner Schub.
func _drag_shift(dir: int) -> void:
	if dir < 0:
		gear -= 1
		_shift_timer = 0.12
		shift_result = "down"
		return
	if rpm >= PERFECT_SHIFT.x and rpm <= PERFECT_SHIFT.y:
		shift_result = "perfect"
		_shift_timer = 0.04
		_shift_boost = 0.5
	elif rpm >= GOOD_SHIFT:
		shift_result = "good"
		_shift_timer = 0.14
	else:
		shift_result = "early"
		_shift_timer = 0.2
	gear += 1
	_upshift(1.0)


## Drag wie in NFSU: das Auto läuft auf einer Schiene. Die Querlage folgt der gewählten Spur als gedämpfte Feder
## (Spurwechsel in gut einer halben Sekunde, ohne Überschwingen), die Nase zeigt in Fahrt- plus Schwenkrichtung.
## Stöße von Gegnern verschieben das Auto kurz, die Schiene holt es zurück. Liefert die Quergeschwindigkeit.
func _drag_rail(dt: float) -> float:
	var c: Curve3D = loc["path"]["curve"]
	var d: float = loc["d"]
	var f := Track.frame_at(c, d)
	var tf: Vector3 = f["fwd"]
	var tr: Vector3 = f["right"]
	var lat_now: float = (global_position - f["pos"]).dot(tr)
	if not _rail_init:
		_rail_init = true
		_rail_lat = lat_now
		_rail_v = 0.0
	var target := Track.lane_lat(track, d, Track.LANES[drag_lane])
	var w := 8.0
	_rail_v += (w * w * (target - _rail_lat) - 2.0 * w * _rail_v) * dt
	_rail_lat += _rail_v * dt
	var lat_vel := _rail_v + (_rail_lat - lat_now) * 10.0
	var heading := (tf * maxf(absf(speed_fwd), 5.0) + tr * _rail_v).normalized()
	global_basis = Basis.looking_at(heading, Vector3.UP)
	velocity = tf * speed_fwd + tr * lat_vel
	_rail_on = true
	_rail_tf = tf
	steer = clampf(_rail_v * 0.3, -1.0, 1.0)
	drifting = false
	drift_angle = 0.0
	_slip_hold = 0.0
	return velocity.dot(global_basis.x)


## Drehung um die Hochachse; k = 0 dreht um die Wagenmitte, k = 1 um die Vorderachse (das Heck schwenkt aus,
## wie bei einem Hecktriebler im Drift).
func _rotate_front(angle: float, k: float) -> void:
	if k <= 0.0:
		rotate_y(angle)
		return
	var pivot := Vector3(0, 0, -(_length / 2.0 - _axle))
	var before := global_transform * pivot
	rotate_y(angle)
	var after := global_transform * pivot
	var shift := (before - after) * k
	shift.y = 0.0
	global_position += shift


## Drift-Modus, Auto steht quer: Gas hält den Winkel, Lenken steuert ihn, die Fahrtrichtung dreht langsam nach.
## Liefert die Quergeschwindigkeit (für Sound und Optik).
func _slide_physics(dt: float, fwd: Vector3, right: Vector3, thr: float, hb: bool, a: float, eff_top: float, low_speed: float) -> float:
	var vel := fwd * speed_fwd + right * speed_lat  # enthält schon den Antrieb entlang der Fahrzeugachse
	var beta := atan2(speed_lat, maxf(speed_fwd, 0.5))  # > 0: Auto rutscht nach rechts weg (Linkskurve)
	var yaw := -steer * steer_rate * 0.6 * (0.5 + 0.5 * low_speed)
	yaw += signf(beta) * thr * (0.7 + 0.35 * drift_k) * clampf(absf(beta) / 0.3, 0.0, 1.0)
	yaw -= beta * (1.1 + 0.9 * (1.0 - thr))  # ohne Gas richtet es sich auf
	if hb:
		yaw *= 1.3
	_spin = move_toward(_spin, 0.0, dt * 2.0)
	_yaw_v = lerpf(_yaw_v, clampf(yaw, -3.2, 3.2), 1.0 - exp(-dt * 20.0))
	_rotate_front((_yaw_v + _spin) * dt, 0.85)
	var nf := -global_basis.z
	nf.y = 0.0
	nf = nf.normalized()
	var nr := Vector3(-nf.z, 0, nf.x)
	var vs := vel.length()
	var b2 := atan2(vel.dot(nr), vel.dot(nf))
	# Seitenhalt im Rutschen: die Fahrtrichtung dreht mit begrenzter Rate zur Fahrzeugachse
	var mu := lerpf(12.0, 9.0, drift_k) * (0.6 if hb else 1.0) * (0.3 if stun > 0.0 else 1.0)
	var turn := signf(b2) * minf(absf(b2), mu / maxf(vs, 6.0) * dt)
	vel = vel.rotated(Vector3.UP, turn)
	b2 -= turn
	vs = clampf(vs - lerpf(8.5, 5.5, drift_k) * absf(sin(b2)) * dt, 0.0, maxf(eff_top, 1.0))
	velocity = vel.normalized() * vs if vel.length() > 0.01 else Vector3.ZERO
	velocity.y = 0.0
	drift_angle = rad_to_deg(absf(b2))
	drifting = absf(b2) > deg_to_rad(8.0) and vs > 8.0
	if absf(b2) < deg_to_rad(5.0) or vs < 6.0 or absf(b2) > deg_to_rad(100.0):
		_slide_out += dt
		if _slide_out > 0.15:
			_sliding = false
	else:
		_slide_out = 0.0
	return velocity.dot(nr)


## Höhe: Gehweg, Rampen, Absprung, Flug, Landung, Wasser
func _update_vertical(dt: float) -> void:
	if track.is_empty():
		position.y = 0.0
		return
	loc = Track.locate(track, _txi * global_position)
	path_id = loc["path"]["id"]
	progress = Track.race_progress(loc)
	lateral = loc["lat"]
	if track["loop"]:
		var L: float = track["length"]
		if progress < L * 0.25 and _last_prog > L * 0.75:
			lap += 1
		elif progress > L * 0.75 and _last_prog < L * 0.25:
			lap -= 1
		_last_prog = progress
	total = lap * track["length"] + progress
	var g := Track.ground(track, loc, _txi * global_position)
	var gh: float = g["h"]
	var base: float = g["base"]
	# Fahrbahnneigung in Fahrtrichtung des Autos
	var pc: Curve3D = loc["path"]["curve"]
	var sl := Track.slope_at(pc, loc["d"])
	var tf: Vector3 = _txf.basis * Track.frame_at(pc, loc["d"])["fwd"]
	_slope_pitch = atan(sl * (-global_basis.z).dot(tf))
	_slope_roll = atan(sl * global_basis.x.dot(tf))
	var bvy := (base - _base_y) / maxf(dt, 0.0001)
	var crest := _base_ok and absf(base - _base_y) < 2.0 and bvy < _base_vy - GRAVITY * dt * 1.1 and absf(speed_fwd) > 15.0
	_base_ok = true
	_base_vy = bvy
	_base_y = base
	if airborne:
		vy -= GRAVITY * dt
		position.y += vy * dt
		air_time += dt
		if g["water"] and position.y <= base - 0.5 and vy < 0.0:
			_land(position.y, true)  # taucht durch die Wasseroberfläche (auf Straßenhöhe gezeichnet)
			return
		if position.y <= gh and vy < 0.0:
			_curb_y = gh - base
			vy -= bvy  # Aufprall relativ zur Fahrbahn (bergab landet es sich weicher)
			_land(gh, g["water"])
		return
	var prev := position.y
	var drop := gh - base < _curb_y - 0.8
	if gh - base < _curb_y - 0.35 and absf(speed_fwd) > 6.0 or crest or drop:
		# Rampenende, Kuppe (die Straße fällt schneller weg, als die Schwerkraft das Auto mitnimmt) oder eine Kante,
		# hinter der es tiefer geht (Damm, Rampe seitlich): abheben und fallen
		airborne = true
		vy = minf(_ground_vy, MAX_LAUNCH_VY)
		air_time = 0.0
		if not tumbling:
			# von der Rampe mit erhobener Nase, so steil wie die Flugbahn beginnt
			_air_pitch = maxf(model.rotation.x, atan2(maxf(vy, 0.0), maxf(absf(speed_fwd), 1.0)) * 1.4)
			_air_pitch_v = 0.0
			_air_roll = model.rotation.z
			# seitlich über die Kante: die Seite, die zuerst den Halt verliert, sackt weg
			_air_roll_v = clampf(-speed_lat * 0.15, -1.2, 1.2) if drop and absf(speed_lat) > 1.5 else 0.0
		if not drop and not tumbling:
			Sfx.play("whoosh", -8.0 + clampf(vy, 0.0, 8.0), randf_range(0.9, 1.1))
		if not tumbling:
			_jump_cam_check()
		return
	if g["water"]:
		_splash()
		return
	# Bordstein: mit Puffer, sonst ruckelt es, wenn man genau an der Kante fährt
	var on_walk: bool = path_id == 0 and loc["score"] > (0.05 if _on_walk else 0.35)
	if on_walk != _on_walk:
		_on_walk = on_walk
		var s := velocity.length()
		_shake = minf(_shake + 0.06 + s * 0.003, 0.4)
		if on_walk:
			velocity *= 0.97
		model.get_meta("body").rotation.z += 0.04 * signf(lateral) * (1.0 if on_walk else -1.0)
	if g["ramp"]:
		_curb_y = gh - base
	else:
		_curb_y = move_toward(_curb_y, gh - base, dt * 3.0)
	position.y = base + _curb_y
	_ground_vy = (position.y - prev) / maxf(dt, 0.0001)


func _land(gh: float, water: bool) -> void:
	var impact := -vy
	_jc_landed = true
	position.y = gh
	if water:
		airborne = false
		vy = 0.0
		tumbling = false
		_reset_pose()
		_splash()
		return
	if tumbling:
		_tumble_bounce(impact)
		return
	# Wie liegt das Auto beim Aufsetzen? Schräg aufs Dach/die Seite oder steil mit der Nase: Überschlag
	var roll := absf(wrapf(_air_roll, -PI, PI))
	var nose := absf(_air_pitch - _slope_pitch)
	if (roll > 0.9 or nose > 0.85) and velocity.length() > 10.0 and not drag_mode:
		start_tumble(-global_basis.z, maxf(impact, 12.0))
		return
	airborne = false
	vy = 0.0
	last_air = air_time
	landings += 1
	Sfx.play("thud", linear_to_db(clampf(impact / 14.0, 0.3, 1.0)), randf_range(0.9, 1.05))
	audio.crash(clampf(impact / 30.0, 0.1, 0.4))
	_shake = minf(_shake + impact * 0.025, 0.7)
	# schief aufgesetzt kostet mehr Tempo als sauber auf allen vier Rädern
	velocity *= (0.97 if impact < 10.0 else 0.92) * (1.0 - 0.3 * clampf(nose + roll * 0.5, 0.0, 1.0))
	model.get_meta("body").rotation.x = -clampf(impact * 0.012, 0.05, 0.16)  # Federn tauchen ein
	if impact > 9.0:
		# hart gelandet: federt noch einmal kurz ab
		airborne = true
		vy = impact * 0.18
		air_time = 0.0
		_air_pitch = _slope_pitch
		_air_pitch_v = 0.0
		_air_roll_v *= 0.3


## Kippt das Auto über das Hindernis? Nur wenn es quer zur eigenen Achse schnell darauf zu rutscht und das Hindernis
## seitlich liegt (n zeigt auf die Flanke), nicht bei frontalen oder streifenden Treffern. rel: Geschwindigkeit
## relativ zum Hindernis.
func _trips(pre: Vector3, n: Vector3, rel: Vector3) -> bool:
	var side := global_basis.x
	var lat := rel.dot(side)  # Querrutschen relativ zum Hindernis
	return pre.length() > TRIP_MIN_SPEED and absf(lat) > TRIP_V and absf(lat) > 0.55 * rel.length() \
		and absf(n.dot(side)) > 0.6 and lat * n.dot(side) < 0.0


## Überschlag: das Auto hebt ab und rollt um die Längsachse (dazu etwas Nicken und Drehen). Jeder Bodenkontakt
## federt ab und kostet Tempo. Kommt es auf den Rädern zum Liegen, geht es weiter; liegt es auf Dach oder Seite,
## wird es nach kurzer Zeit auf die Straße zurückgesetzt (wie in NFS).
func start_tumble(push: Vector3, strength: float) -> void:
	if tumbling or sinking > 0.0:
		return
	if OS.get_cmdline_user_args().has("--tumblelog"):
		print("UEBERSCHLAG v=%s quer=%.1f stärke=%.1f luft=%s %s" % [velocity, velocity.dot(global_basis.x), strength, airborne, get_stack()[1]["function"]])
	tumbling = true
	_wall_turn = 0.0
	_jc_landed = true
	rollovers += 1
	crashes += 1
	airborne = true
	air_time = 0.0
	vy = clampf(strength * 0.28, 4.5, 9.0)
	# rollt weiter, wenn es schon schief liegt, sonst über die getroffene Seite; frontal kippt die Nase mit nach unten
	var side := signf(_air_roll) if absf(_air_roll) > 0.3 else signf(push.dot(global_basis.x) + randf_range(-0.4, 0.4))
	var fwd := -global_basis.z
	_air_roll = model.rotation.z
	_air_roll_v = side * clampf(strength * 0.3, 5.0, 10.0)
	_air_pitch = model.rotation.x
	_air_pitch_v = clampf(push.dot(fwd), -1.0, 0.0) * 3.0 + randf_range(-1.0, 1.0)
	_spin = randf_range(-1.6, 1.6)
	_tumble_rest = 0.0
	nitro_on = false
	stun = 0.0
	_shake = 1.0
	audio.crash(1.0)
	Sfx.play("thud", 0.0, 0.8)


func _update_tumble(dt: float) -> void:
	var h := Vector3(velocity.x, 0.0, velocity.z)
	if not airborne:
		h = h.move_toward(Vector3.ZERO, 11.0 * dt)  # schleift über den Asphalt
	velocity = h
	rotate_y(_spin * dt)
	_spin = move_toward(_spin, 0.0, dt * (0.6 if airborne else 3.0))
	var pre := velocity
	move_and_slide()
	_handle_collisions(pre)
	_update_vertical(dt)
	if not tumbling:
		return  # ins Wasser gefallen
	_air_roll += _air_roll_v * dt
	_air_pitch += _air_pitch_v * dt
	if not airborne:
		_air_pitch_v = move_toward(_air_pitch_v, 0.0, dt * 8.0)
		_air_pitch = lerp_angle(_air_pitch, _slope_pitch, 1.0 - exp(-dt * 4.0))
		var r := wrapf(_air_roll, -PI, PI)
		if absf(_air_roll_v) < 2.5 and absf(r) < 1.2:
			# kippt zurück auf die Räder
			_air_roll_v = 0.0
			_air_roll = lerp_angle(_air_roll, 0.0, 1.0 - exp(-dt * 7.0))
			if absf(wrapf(_air_roll, -PI, PI)) < 0.04:
				tumbling = false
				stun = 0.5
				_reset_pose()
				return
		else:
			# rollt aus und bleibt auf Dach oder Seite liegen
			_air_roll_v = move_toward(_air_roll_v, 0.0, dt * 9.0)
			if absf(_air_roll_v) < 2.5:
				_air_roll_v = 0.0
				var flat := roundf(r / (PI / 2.0)) * (PI / 2.0)
				_air_roll = lerp_angle(_air_roll, flat, 1.0 - exp(-dt * 8.0))
				_tumble_rest += dt
				if _tumble_rest > 1.3:
					var p: Dictionary = loc["path"]
					var half: float = p["half_w"] - 2.0
					place(_txf * Track.xform_at(p["curve"], loc["d"], clampf(loc["lat"], -half, half)))
					stun = 0.3
					return
	var b := Basis(Vector3.BACK, _air_roll) * Basis(Vector3.RIGHT, _air_pitch)
	# auf der Seite ist das Auto breiter als der Schwerpunkt hoch: etwas anheben, sonst steckt es im Asphalt
	model.transform = Transform3D(b, PIVOT - b * PIVOT + Vector3(0, absf(sin(_air_roll)) * 0.22, 0))
	speed_fwd = h.dot(-global_basis.z)
	rpm = move_toward(rpm, 1200.0, dt * 3000.0)
	audio.rpm = rpm
	audio.throttle = 0.0
	audio.speed = h.length()
	audio.scrape = 0.0
	audio.slip = 0.6 if not airborne and h.length() > 3.0 else 0.0
	_update_camera(dt, 0.0)


func _tumble_bounce(impact: float) -> void:
	if impact > 3.0:
		vy = impact * 0.35  # federt ab
		_air_roll_v *= 0.65
		_air_pitch_v *= -0.5
		velocity *= 0.78
		Sfx.play("thud", linear_to_db(clampf(impact / 12.0, 0.3, 1.0)), randf_range(0.8, 0.95))
		audio.crash(clampf(impact / 15.0, 0.3, 1.0))
		_shake = minf(_shake + impact * 0.04, 1.0)
	else:
		airborne = false
		vy = 0.0


func _reset_pose() -> void:
	tumbling = false
	_yaw_v = 0.0
	_air_roll = 0.0
	_air_roll_v = 0.0
	_air_pitch = 0.0
	_air_pitch_v = 0.0
	if model:
		model.transform = Transform3D.IDENTITY


func _splash() -> void:
	if sinking > 0.0:
		return
	sinking = 1.6
	airborne = false
	Sfx.play("splash")
	audio.crash(0.4)
	_shake = 0.6
	# Zurücksetzen vor die Rampe, mit Anlauf
	var p: Dictionary = loc["path"]
	var d := maxf(loc["d"] - 55.0, 2.0)
	for r in track["ramps"]:
		if r["path"] == p["id"] and loc["d"] > r["d0"] and loc["d"] - r["d0"] < 80.0:
			d = maxf(r["d0"] - 45.0, 2.0)
	_respawn_xf = _txf * Track.xform_at(p["curve"], d, 0.0)


func _update_sinking(dt: float) -> void:
	sinking -= dt
	velocity = velocity * 0.92
	position += velocity * dt
	position.y -= dt * 1.2
	rpm = move_toward(rpm, 900.0, dt * 4000.0)
	audio.rpm = rpm
	audio.throttle = 0.0
	audio.speed = 0.0
	audio.scrape = 0.0
	_update_camera(dt, 0.0)
	if sinking <= 0.0:
		sinking = 0.0
		place(_respawn_xf)


func _update_camera(dt: float, sf: float) -> void:
	if jump_cam:
		_update_jump_cam(dt)
		return
	var base := 58.0 if _chase() else 70.0
	var zoom := (14.0 if _chase() else 24.0) * sf + (8.0 if nitro_on else 0.0)
	if not GameState.speed_fov:
		zoom = (7.0 if _chase() else 12.0)  # Tempo-Zoom aus: festes, mittleres Sichtfeld
	var target_fov := base + zoom
	_fov = lerpf(_fov, target_fov, dt * (6.0 if nitro_on else 2.5))
	cam.fov = _fov
	# Kein Dauerwackeln bei Tempo: nur kurze, weiche Stöße bei Einschlägen und Landungen, dazu ab gut 80 % Tempo ein
	# feines Zittern wie in NFS (wenige Millimeter, mit Nitro etwas mehr; mit "Kamerawackeln aus" nichts)
	var amp := _shake * (0.06 if GameState.cam_shake else 0.0)
	if GameState.cam_shake and not airborne:
		amp += (0.006 + (0.006 if nitro_on else 0.0)) * smoothstep(0.78, 1.0, sf)
	var drift_look := clampf((drift_angle - 6.0) / 24.0, 0.0, 1.0) * 0.45 if velocity.length() > 5.0 else 0.0
	_cam_drift = lerpf(_cam_drift, drift_look, 1.0 - exp(-dt * 3.0))
	if _chase():
		# Verfolger: folgt mit leichter Verzögerung; im Drift schaut sie stufenlos ein Stück in Fahrtrichtung,
		# so sieht man die Kurve und den Winkel
		var yaw := global_rotation.y
		if velocity.length() > 2.0:
			yaw = lerp_angle(yaw, atan2(-velocity.x, -velocity.z), _cam_drift)
		var cs: Dictionary = CHASE[cam_mode]
		var dist: float = cs["dist"] + sf * 0.6 + (0.4 if nitro_on else 0.0)
		var height: float = cs["height"] - sf * 0.2
		if not _cam_init:
			_cam_yaw = yaw
			_cam_pos = global_position + Basis(Vector3.UP, yaw) * Vector3(0, height, dist)
			_cam_init = true
		# etwas Verzögerung: in Kurven sieht man das Auto einlenken (wie die NFSU-Verfolgerkamera)
		_cam_yaw = lerp_angle(_cam_yaw, yaw, 1.0 - exp(-dt * (2.0 if airborne else 4.5)))
		var target := global_position + Basis(Vector3.UP, _cam_yaw) * Vector3(0, height, dist)
		_cam_pos = _cam_pos.lerp(target, 1.0 - exp(-dt * 20.0))
		_cam_pos.y = lerpf(_cam_pos.y, target.y, 1.0 - exp(-dt * (6.0 if airborne else 20.0)))
		cam.global_position = _cam_pos
		cam.look_at(global_position + Basis(Vector3.UP, _cam_yaw) * Vector3(0, cs["look_y"], cs["look_z"]), Vector3.UP)
		if GameState.cam_shake:
			cam.rotate_object_local(Vector3.FORWARD, -steer * sf * 0.02)
	else:
		cam.rotation.z = lerpf(cam.rotation.z, -steer * sf * 0.025 if GameState.cam_shake else 0.0, dt * 5.0)
	_shake_t += dt
	cam.h_offset = sin(_shake_t * 41.0) * amp
	cam.v_offset = sin(_shake_t * 53.0 + 1.3) * amp
	_shake = move_toward(_shake, 0.0, dt * 3.0)


func place(xform: Transform3D) -> void:
	reverse_gear = false
	_change_t = 0.0
	_rev_s = 0.0
	global_transform = xform
	velocity = Vector3.ZERO
	speed_fwd = 0.0
	steer = 0.0
	_spin = 0.0
	_wall_turn = 0.0
	_slip_hold = 0.0
	stun = 0.0
	airborne = false
	vy = 0.0
	sinking = 0.0
	_rail_init = false
	_launch_t = 0.0
	_nos_k = 0.0
	_nos_burn = 0.0
	_nos_lock = 0.0
	nitro_on = false
	_pops.clear()
	_scrape = 0.0
	_end_jump_cam()
	_cam_init = false
	_base_ok = false
	_curb_y = 0.0
	_reset_pose()


## Verkehr ist das Schlimmste (frontal oder Auffahren: Dreher, kurz keine Kontrolle; seitlich: abprallen),
## Rennwagen werden gerempelt, an Wänden schrammt man entlang.
func _handle_collisions(pre: Vector3) -> void:
	var walled := false
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var n := c.get_normal()
		n.y = 0.0
		if n.length_squared() < 0.01:
			continue
		n = n.normalized()
		var other := c.get_collider()
		if other is Node and other.is_in_group("traffic"):
			_hit_traffic(other, pre, n)
		elif other is Node and other.is_in_group("racer"):
			# Gegner: gleich schwer, Stoß nach Impuls auf beide (wer auffährt, verliert Tempo, der andere wird geschoben);
			# hart von hinten oder frontal: kurz benommen
			var ov: Vector3 = -other.global_basis.z * float(other.speed)
			var rel := pre - ov
			var impact := -rel.dot(n)
			if impact > 0.5 and _crash_cooldown <= 0.0:
				other.bump(pre, n)
				velocity += n * impact * 0.65
				velocity.y = 0.0
				var ho := clampf(impact / maxf(rel.length(), 1.0), 0.0, 1.0)
				_shake = minf(_shake + impact * 0.03, 0.6)
				audio.crash(clampf(impact / 20.0, 0.1, 0.7))
				if impact > 12.0 and ho > 0.6:
					stun = 0.4
					_spin += randf_range(-0.8, 0.8)
					crashes += 1
					_crash_cooldown = 0.4
		elif not walled:
			walled = true
			if debug_hits:
				_collider_name = _describe(c)
			var k := _obstacle_kind(c)
			_hit_wall(pre, n, k == 1, k == 2)


## Feste Hindernisse wie in NFSU: sie geben nicht nach und federn nicht zurück. Frontal (Wand, Hausecke, Baum,
## Mast) steht das Auto mit einem Schlag; man muss zurücksetzen. Je flacher der Winkel, desto mehr Tempo bleibt:
## an Wänden schrammt das Auto entlang und dreht dabei weich parallel zur Wand (_wall_turn). Schmale runde
## Hindernisse (Baumstamm, Pfosten, pole) halten das Auto auf, sobald es sie mit der Front trifft, statt es um
## sich herumzulenken; nur wer sie seitlich streift, rutscht vorbei. Gegen das Hindernis Gas geben schiebt nicht
## zurück: das Tempo in das Hindernis hinein fällt einfach weg.
func _hit_wall(pre: Vector3, n: Vector3, small := false, pole := false) -> void:
	var spd := pre.length()
	var vn := -pre.dot(n)  # Tempo in die Wand hinein
	if spd < 0.5 or vn < 0.2:
		return
	_wall_t = 0.0
	# Überschlag nach der Lage beim Aufprall beurteilen (vor jeder Drehung durch die Wand)
	var trip := _trips(pre, n, pre) and not drag_mode and not drift_mode and not tumbling
	var head_on := clampf(vn / spd, 0.0, 1.0)  # Sinus des Aufprallwinkels
	var fwd := -global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	if pole:
		# Stamm oder Pfosten vor der Front: zählt wie frontal, auch wenn die runde Form schräg zurückwirft
		var front := clampf(pre.normalized().dot(fwd), -1.0, 1.0)
		if absf(front) > 0.5 and head_on > 0.3:
			head_on = maxf(head_on, 0.85)
	var tang := pre + n * vn
	var keep := 1.0 - 0.55 * head_on * head_on
	if tang.length() > 3.0 and not small:
		_scrape = maxf(_scrape, clampf(tang.length() / 30.0, 0.25, 1.0))
		_scrape_hold = 0.12
	# kein Zurückfedern: nur bei harten Einschlägen ein Hauch, damit das Auto nicht im Hindernis klebt
	var new_v := n * (0.6 if vn > 6.0 else 0.0)
	if tang.length() > 0.1:
		new_v += tang.normalized() * tang.length() * keep * (1.0 - pow(head_on, 1.8))
	new_v = new_v.move_toward(Vector3.ZERO, 3.0 * get_physics_process_delta_time())  # Schleifen kostet etwas
	velocity = Vector3(new_v.x, 0.0, new_v.z)
	# Parallel zur Wand drehen: streifend ganz, schräg teilweise, frontal gar nicht (dort steht man)
	if tang.length() > 0.5 and not tumbling:
		var along := tang.normalized() * signf(tang.dot(fwd) + 0.001)
		var ang := fwd.signed_angle_to(along, Vector3.UP)
		_wall_turn = ang * (1.0 - smoothstep(0.55, 0.85, head_on)) * (0.25 if small or pole else 1.0)
	if vn > 1.5 and _wall_cool <= 0.0:
		_wall_cool = 0.4
		if debug_hits:
			last_hit = "%s v=%.1f vn=%.1f d=%.0f lat=%.1f" % [_collider_name, spd, vn, progress, lateral]
		wall_hits += 1
		audio.crash(clampf(vn / 30.0, 0.08, 1.0))
		_shake = minf(_shake + vn * 0.03, 0.9)
	if drift_mode and head_on > 0.5:
		_sliding = false
	if trip:
		start_tumble(n, absf(pre.dot(global_basis.x)))
	elif vn > 12.0 and head_on > 0.75 and _crash_cooldown <= 0.0:
		# harter Einschlag: kurz benommen (kein Lenken, kein Gas), aber kein Herumwirbeln
		crashes += 1
		stun = 0.35
		_crash_cooldown = 0.5


## Verkehr wie in Underground: Rammen wird bestraft. Stoß nach Impuls gegen schwere Wagen (Pkw 2,5-, Bus 10-mal so
## schwer wie das eigene Auto); ab gut 30 km/h Unterschied frontal oder von hinten ist es ein Crash (Dreher, kurz keine
## Kontrolle, Tempo fast weg, man muss neu beschleunigen). Seitliches Streifen kostet etwas Tempo und schüttelt.
func _hit_traffic(other: Node, pre: Vector3, n: Vector3) -> void:
	var ov: Vector3 = other.velocity_vec
	var rel: Vector3 = pre - ov
	var hit := -rel.dot(n)
	if hit < 1.5 or _crash_cooldown > 0.0:
		return
	var head_on := clampf(hit / maxf(rel.length(), 1.0), 0.0, 1.0)
	var mt: float = other.mass if "mass" in other else 1.0
	var j := (1.0 + TRAFFIC_BOUNCE) * hit / (1.0 + 1.0 / mt)  # Stoß bei gleicher Masse des eigenen Autos
	var after := pre + n * j  # eigenes Tempo nach dem Stoß
	audio.crash(clampf(hit / 22.0, 0.25, 1.0))
	if drag_mode and hit > 9.0 and head_on > 0.5:
		totaled = true  # Drag: wer frontal oder ins Heck kracht, ist raus
	if _trips(pre, n, rel) and not drag_mode:
		other.push(-n * j / mt)
		velocity = after * 0.5 + n * 3.0
		_crash_cooldown = 0.7
		start_tumble(n, absf(rel.dot(global_basis.x)))
	elif hit > 9.0 and head_on > 0.5:
		other.push(-n * j / mt)
		velocity = after * 0.4 + n * 2.0
		velocity.y = 0.0
		_spin = randf_range(1.2, 2.4) * (1.0 if randf() < 0.5 else -1.0) * clampf(hit / 25.0, 0.5, 1.0)
		stun = 0.8
		_shake = 1.0
		_crash_cooldown = 0.7
		crashes += 1
	else:
		other.push(-n * j / mt)
		velocity = after * lerpf(0.95, 0.8, head_on)
		velocity.y = 0.0
		_spin += signf(n.dot(global_basis.x)) * clampf(hit * 0.08, 0.15, 0.9)
		_shake = minf(_shake + hit * 0.04, 0.7)
		_crash_cooldown = 0.35
		if hit > 8.0:
			crashes += 1
			stun = 0.2


## Vom Zug erfasst (rail_crossing._sweep_player): mitgerissen und seitlich weggeschleudert, Dreher, kurz keine
## Kontrolle. Die Lage hat der Bahnübergang schon neben den Zug gesetzt (auf Straßenhöhe, nie in den Boden).
func hit_by_train(v_train: Vector3, away: Vector3) -> void:
	if _crash_cooldown > 0.0:
		velocity += away * 2.0
		return
	velocity = v_train * 0.5 + away * 10.0
	velocity.y = 0.0
	_spin = randf_range(2.0, 3.0) * (1.0 if randf() < 0.5 else -1.0)
	stun = 1.2
	_shake = 1.0
	crashes += 1
	_crash_cooldown = 0.8
	audio.crash(1.0)


## Kleines Hindernis (Poller, Pfosten, Bank, Mülltonne): Kiste, die waagerecht nirgends über 2,5 m misst
## 0 Wand, 1 kleines Hindernis (Bank, Schaltkasten: eckig, unter 2,5 m), 2 schmal und fest (Baumstamm, Pfosten,
## Mast: rund oder unter 0,8 m)
func _obstacle_kind(c: KinematicCollision3D) -> int:
	var cs := c.get_collider_shape() as CollisionShape3D
	if cs == null:
		return 0
	if cs.shape is CylinderShape3D:
		return 2 if (cs.shape as CylinderShape3D).radius * cs.global_basis.get_scale().x < 1.0 else 0
	if not cs.shape is BoxShape3D:
		return 0
	var sz: Vector3 = (cs.shape as BoxShape3D).size * cs.global_basis.get_scale()
	var big := maxf(sz.x, sz.z)
	return 2 if big < 0.8 else (1 if big < 2.5 else 0)


## Nur für Tests: beschreibt, woran das Auto gestoßen ist (Form, Lage, nächste Wandfläche)
func _describe(c: KinematicCollision3D) -> String:
	var cs := c.get_collider_shape() as CollisionShape3D
	if cs == null:
		return "?"
	var p := c.get_position()
	if cs.shape is BoxShape3D:
		return "Kiste %s bei %s (Eltern: %s)" % [cs.shape.size, cs.global_position.snapped(Vector3.ONE * 0.1), cs.get_parent().get_parent().name]
	if cs.shape is ConcavePolygonShape3D:
		var f: PackedVector3Array = cs.shape.get_faces()
		var best := 1e9
		var bi := 0
		var pl := cs.global_transform.affine_inverse() * p  # Flächen liegen in Streckenkoordinaten
		for i in range(0, f.size(), 3):
			var m := (f[i] + f[i + 1] + f[i + 2]) / 3.0
			var dd := Vector2(m.x - pl.x, m.z - pl.z).length()
			if dd < best:
				best = dd
				bi = i
		var gt := cs.global_transform
		return "Wand %s-%s bei %s (%s)" % [(gt * f[bi]).snapped(Vector3.ONE * 0.1), (gt * f[bi + 1]).snapped(Vector3.ONE * 0.1), p.snapped(Vector3.ONE * 0.1),
			"%s/%s" % [cs.get_parent().get_parent().get_meta("race_name", "?"), cs.get_parent().name]]
	return str(cs.shape)


## Zeitlupe weich ein- und ausblenden, in Echtzeit (dt ist selbst schon verlangsamt). Nach dem Aufsetzen läuft sie
## aus; bei Überschlag oder Wasser bleibt sie, bis die Kamera zurückschneidet.
func _process(dt: float) -> void:
	var real := dt / maxf(Engine.time_scale, 0.01)
	var want := _jc_slow if jump_cam and GameState.jump_cam == 0 and (not _jc_landed or tumbling or sinking > 0.0) else 1.0
	if _slowmo >= 1.0 and want >= 1.0:
		return
	_slowmo = move_toward(_slowmo, want, real * (4.0 if want < _slowmo else 2.5))
	Engine.time_scale = _slowmo


func _exit_tree() -> void:
	Engine.time_scale = 1.0


## Beim Absprung: wird der Sprung hoch und lang genug und gibt es einen Standort mit freier Sicht, Sprungkamera an
func _jump_cam_check() -> void:
	if jump_cam or GameState.jump_cam == 2 or drag_mode or not controls_enabled or track.is_empty():
		return
	var f := _predict_flight()
	if OS.get_cmdline_user_args().has("--jumplog"):
		print("SPRUNG vorhergesagt t=%.2f s höhe=%.1f m v=%.0f km/h" % [f["time"], f["peak"], velocity.length() * 3.6])
	if f["peak"] < JUMP_CAM_PEAK or f["time"] < JUMP_CAM_TIME or f["loc"].is_empty():
		return
	var spot = _jump_cam_spot(f)
	if OS.get_cmdline_user_args().has("--jumplog"):
		print("SPRUNGKAMERA %s" % (str(spot) if spot != null else "kein freier Standort"))
	if spot == null:
		return
	jump_cam = true
	_jc_slow = clampf(f["time"] / SLOW_REAL, SLOW_RANGE.x, SLOW_RANGE.y)
	_jc_landed = false
	_jc_hold = 0.0
	_jc_pos = spot
	_jc_look = global_position + Vector3(0, 0.55, 0)
	cam.top_level = true
	cam.rotation = Vector3.ZERO
	if _jc_light == null:
		_jc_light = OmniLight3D.new()
		_jc_light.top_level = true
		_jc_light.omni_range = 6.0
		_jc_light.light_energy = 1.4
		_jc_light.light_color = Color(0.85, 0.9, 1.0)
		add_child(_jc_light)
	_jc_light.visible = true


func _end_jump_cam() -> void:
	if not jump_cam:
		return
	jump_cam = false
	_jc_light.visible = false
	_apply_cam()
	cam.fov = _fov


## Flugbahn vorausrechnen (geradeaus, ohne Luftwiderstand): Dauer, größte Höhe über dem Boden, Scheitel und
## Landepunkt mit Lage auf der Strecke
func _predict_flight() -> Dictionary:
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	var p := global_position
	var v := vy
	var peak := 0.0
	var apex := p
	var t := 0.0
	var step := 1.0 / 15.0
	while t < 4.0:
		t += step
		v -= GRAVITY * step
		p += hv * step
		p.y += v * step
		var l := Track.locate(track, _txi * p)
		var g := Track.ground(track, l, _txi * p)
		var floor_y: float = g["base"] - 0.5 if g["water"] else g["h"]
		if p.y <= floor_y and v < 0.0:
			return {"time": t, "peak": peak, "apex": apex, "land": Vector3(p.x, floor_y, p.z), "loc": l}
		if p.y - g["h"] > peak:
			peak = p.y - g["h"]
			apex = p
	return {"time": t, "peak": peak, "apex": apex, "land": p, "loc": {}}


## Kamerastandort: ein Stück hinter der Landestelle, seitlich versetzt (zur Straßenmitte hin, sonst zur anderen
## Seite, notfalls näher), knapp über dem Boden; nur wenn von dort Absprung, Scheitel und Landung frei zu sehen sind
func _jump_cam_spot(f: Dictionary) -> Variant:
	var l: Dictionary = f["loc"]
	var p: Dictionary = l["path"]
	var c: Curve3D = p["curve"]
	var fr := Track.frame_at(c, l["d"])
	var d: float = l["d"] + JC_AHEAD * (1.0 if velocity.dot(_txf.basis * fr["fwd"]) >= 0.0 else -1.0)
	var fc := Track.frame_at(c, d)
	var main: bool = p["id"] == 0
	# Hauptstraße: bis auf den Gehweg; Nebenwege: innerhalb ihrer (unsichtbaren) Randmauern
	var reach: float = Track.hw(track, d) + Track.WALK - 1.2 if main else p["half_w"] - 0.4
	var lat: float = l["lat"]
	var first := -signf(lat) if absf(lat) > 0.3 else 1.0
	var space := get_world_3d().direct_space_state
	# erst weit seitlich (tief, dann höher über Geländer und Mauern hinweg), dann näher an der Flugbahn
	for c2 in [[JC_SIDE, JC_HEIGHT], [-JC_SIDE, JC_HEIGHT], [JC_SIDE, 2.6], [-JC_SIDE, 2.6], [JC_SIDE * 0.6, JC_HEIGHT], [-JC_SIDE * 0.6, JC_HEIGHT]]:
		var cl := clampf(lat + c2[0] * first, -reach, reach)
		if absf(cl - lat) < 2.0:
			continue
		var g := Track.ground_path(track, p["id"], d, cl, absf(cl) - Track.hw(track, d) if main else -1.0)
		var pos: Vector3 = fc["pos"] + fc["right"] * cl
		pos.y = g["h"] + c2[1]
		pos = _txf * pos
		var ok := _sight(space, pos, global_position + Vector3(0, 1.0, 0)) and _sight(space, pos, f["apex"] + Vector3(0, 0.6, 0)) \
				and _sight(space, pos, f["land"] + Vector3(0, 1.0, 0)) and _free(space, pos)
		if OS.get_cmdline_user_args().has("--jumplog"):
			print("  quer %.1f -> %.1f höhe %.1f: %s" % [lat, cl, c2[1], "frei" if ok else "verdeckt"])
		if ok:
			return pos
	return null


func _sight(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.exclude = [get_rid()]
	return space.intersect_ray(q).is_empty()


func _free(space: PhysicsDirectSpaceState3D, pos: Vector3) -> bool:
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.5
	q.shape = sph
	q.transform = Transform3D(Basis(), pos)
	q.exclude = [get_rid()]
	return space.intersect_shape(q, 1).is_empty()


func _update_jump_cam(dt: float) -> void:
	var real := dt / maxf(Engine.time_scale, 0.01)
	if _jc_landed:
		_jc_hold += real
		if _jc_hold > (1.4 if tumbling or sinking > 0.0 else 0.45):
			_end_jump_cam()
			return
	var target := global_position + Vector3(0, 0.55, 0)
	_jc_look = _jc_look.lerp(target, 1.0 - exp(-real * 14.0))
	var dist := _jc_pos.distance_to(_jc_look)
	cam.global_position = _jc_pos
	if dist > 0.5:
		cam.look_at(_jc_look, Vector3.UP)
	cam.fov = clampf(rad_to_deg(2.0 * atan(JC_FRAME / maxf(dist, 0.1))), 9.0, 60.0)
	_jc_light.global_position = target + (_jc_pos - target).normalized() * 3.0 + Vector3(0, 1.0, 0)
	_shake_t += real
	var amp := _shake * (0.06 if GameState.cam_shake else 0.0)
	cam.h_offset = sin(_shake_t * 41.0) * amp
	cam.v_offset = sin(_shake_t * 53.0 + 1.3) * amp
	_shake = move_toward(_shake, 0.0, real * 3.0)
