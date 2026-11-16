extends Node
## Anflug beim Laden der Welt (seit 2.38), wie der Figurenwechsel in GTA V: wenn das Ladebild verschwindet, steht die
## Kamera hoch über dem eigenen Auto (Draufsicht wie ein Luftbild), dann geht es in drei schnellen Sprüngen hinunter,
## dazwischen kurze Halte, der letzte schwenkt hinter das Auto in die Verfolgerkamera (world.gd übergibt dann).
## Jede Taste, jeder Knopf, Klick oder Fingertipp überspringt: sofort die Verfolgerkamera.
##
## Damit es von oben stimmt:
## - Die Welt baut während des Anflugs nichts nach (world.gd): kein Ruckeln, keine Stadt erscheint im Bild. Die Draufsicht
##   ist nur so hoch, dass ihr Bildausschnitt (Ecken) im fertig gebauten Umkreis bleibt (hinter dem Ladebild gebaut wird
##   alles bis 420 m um den Start, _plan_heights).
## - Detailstufen: Kleinteile und mittlere Teile der Strecken haben eine Sichtweite (Track.apply_lod). Oben sind die
##   mittleren Teile je nach Einstellung alle aus oder alle an (wechseln erst im ersten Sprung), ab dem zweiten Halt
##   ist alles in Reichweite; gewechselt wird nur in der Bewegung. Das eigene Auto zeigt durchgehend das volle Modell
##   (sonst spränge es mitten im Bild von der Fernansicht aufs Modell).
## - Nebel nach Abstand: mit dem normalen Nebel (nachts 0,0036/m) läge über dem Auto aus 380 m drei Viertel Dunst;
##   oben bleibt ein leichter Schleier (HAZE), zur Landung hin wieder der normale Nebel. Sichtweite der Kamera passt.
## - Ruckler: die Ansichten oben und unten werden schon hinter dem Ladebild einmal gezeichnet (Shader übersetzt), im
##   Browser-Renderer die ganze Fahrt (prewarm).
##
## Unschärfe nur während der Sprünge (dieselbe Zoom-Unschärfe wie beim Tempo, scharfe Mitte, mit der Einstellung
## "Bewegungsunschärfe" abschaltbar). Ton: vorerst keiner (WHOOSH: das vorhandene whoosh.wav ist künstlich erzeugt; ein
## Luftrauschen käme nur als echte Aufnahme, nach Rückfrage beim User).
## Tests: --nozoom (aus), --zkind=start|short, --zshot=/pfad/pre (Bilder während des Anflugs), --ztimes=0,0.4,...,
## --zskip=1.2 (drückt dann Enter), --zlog (jedes Bild mit Zeit), --zcovered (wie im Tunnel: kein Anflug),
## --nowarmup (Browser-Renderer ohne Vorzeichnen).

const Track := preload("res://scripts/track_builder.gd")
const PlayerCar := preload("res://scripts/player_car.gd")

const FOV_TOP := 46.0  # Draufsicht etwas enger als die Verfolgerkamera: wirkt flacher, mehr wie ein Luftbild
const H_TOP := 380.0  # oben höchstens so hoch (Abstand zum Auto)
const H_MID := 115.0  # zweiter Halt
const H_LOW := 26.0  # dritter Halt, danach hinter das Auto
const YAW0 := 7.0  # Grad: oben leicht gedreht, dreht bis zur Landung weich gerade (lebt, ohne Abstände zu ändern)
const CREEP := 0.035  # während der Halte 2 und 3 sinkt die Kamera noch ein wenig (oben nicht: Detailstufen ruhig)
## so viel Dunst liegt von oben über dem Auto, nachts und am Tag (der normale Nebel gäbe aus 380 m gut 70 %, am Tag
## wirkt schon wenig milchig)
const HAZE := Vector2(0.22, 0.12)
## Zoom-Unschärfe auf dem schnellsten Stück eines Sprungs (mal Stufe der Bewegungsunschärfe); etwas unter der beim
## Höchsttempo (0,115), Effekte bleiben dezent
const BLUR_DROP := 0.08
const TRAIL := 0.35  # Lichtspuren und Randabdunklung dazu (speed im Tempo-Shader), ebenso schwach
## Abschnitte (s): Halt oben, Sprung, Halt, Sprung, Halt, Landung hinter dem Auto. "short": Schnellreise und Rückkehr
const TIMES := {"start": [0.7, 0.42, 0.3, 0.38, 0.24, 0.72], "short": [0.4, 0.36, 0.2, 0.32, 0.17, 0.62]}
const CTRL_AT := 0.82  # ab diesem Anteil der Landung fährt man schon (die Kamera steht dann praktisch hinter dem Auto)
## Luftrauschen je Sprung: [Lautstärke (dB), Tonhöhe] je Sprung, z. B. [[-17.0, 1.05], [-18.5, 1.15], [-20.0, 1.0]]
## mit einem Klang aus Sfx; startet etwas vor dem Sprung, die Spitze liegt in seiner Mitte. Leer = ganz ohne Ton (2.38:
## kein künstliches Rauschen, siehe oben).
const WHOOSH := []

var w: Node  # world.gd
var player: Node3D
var cam: Camera3D
var kind := "start"
var running := false
var blur := 0.0  # für world._update_speed_fx: Zoom-Unschärfe, Lichtspuren, Fluchtpunkt
var trail := 0.0
var focus := Vector2(0.5, 0.46)
var _t := 0.0
var _seq: Array = []  # je Abschnitt [Anfang, Dauer]
var _total := 0.0
var _h := [H_TOP, H_MID, H_LOW]
var _aspect := 16.0 / 9.0
var _ctrl := false
var _snd := [false, false, false]
var _whooshes := []  # laufende Luftrauschen (beim Überspringen aus)
var _car_lod := []  # [Knoten, Eigenschaft, alter Wert]: volles Automodell während des Anflugs
var _args := PackedStringArray()
# Test und Messung
var _shot_prefix := ""
var _shot_times: Array = []
var _shot_i := 0
var _shot_busy := false
var _skip_at := -1.0
var _log := false
var _last_us := 0
var _frames := 0
var _sum_ms := 0.0
var _max_ms := 0.0
var _slow := 0
var _shot_frame := false


## Vorbereiten (hinter dem Ladebild, das Auto steht schon): Höhen nach gebautem Umkreis und Detailstufen
func setup(world_node: Node, k: String) -> void:
	w = world_node
	player = w.player
	kind = k if TIMES.has(k) else "start"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_args = OS.get_cmdline_user_args()
	for a in _args:
		if a.begins_with("--zshot="):
			_shot_prefix = a.substr(8)
		elif a.begins_with("--ztimes="):
			for s in a.substr(9).split(","):
				_shot_times.append(float(s))
		elif a.begins_with("--zskip="):
			_skip_at = float(a.substr(8))
		elif a == "--zlog":
			_log = true
	var times: Array = TIMES[kind]
	var t0 := 0.0
	for d in times:
		_seq.append([t0, d])
		t0 += d
	_total = t0
	if _shot_prefix != "" and _shot_times.is_empty():
		var s := 0.0
		while s < _total + 0.15:
			_shot_times.append(s)
			s += 0.3
	var vs: Vector2 = Vector2(w.world.size)
	_aspect = vs.x / maxf(vs.y, 1.0)
	_plan_heights()
	cam = Camera3D.new()
	cam.name = "Anflug"
	cam.fov = FOV_TOP
	w.world.add_child(cam)
	_full_car_model(true)


## Höhen: oben so hoch, dass die Bildecken im gebauten Umkreis liegen (90 %) und höchstens H_TOP; der zweite Halt so,
## dass dort alle Kleinteile in Sichtweite sind (Ecken eingerechnet), der dritte knapp über dem Auto
func _plan_heights() -> void:
	var p := player.global_position
	var safe := 1e9
	for e in w.entries:
		if e["state"] != "ready":
			safe = minf(safe, w._dist(e, p))
	var ground_k := tan(deg_to_rad(FOV_TOP) / 2.0) * sqrt(1.0 + _aspect * _aspect)  # Bildecke am Boden je Meter Höhe
	var slant_k := sqrt(1.0 + ground_k * ground_k)  # Abstand Kamera - Bildecke je Meter Höhe
	var top := clampf(minf(H_TOP, 0.9 * safe / ground_k), 150.0, H_TOP)
	var lod: Array = GameState.lod_ranges()
	var mid := clampf(0.95 * float(lod[0]) / slant_k, 60.0, H_MID)
	_h = [top, mid, H_LOW]
	if _log or _shot_prefix != "":
		print("INTRO plan kind=%s hoehen=%.0f/%.0f/%.0f gebaut_bis=%.0f m seite=%.2f ecke_oben=%.0f m (Sichtweite mittel %.0f m) dauer=%.2f s" % [kind,
			top, mid, H_LOW, safe, _aspect, top * ground_k, float(lod[1]), _total])


## Steht das Auto im Tunnel? Dann gibt es keinen Anflug (von oben sähe man nur die Decke)
static func covered(pl: Node) -> bool:
	if OS.get_cmdline_user_args().has("--zcovered"):  # Test: als stünde das Auto im Tunnel
		return true
	if pl.track.is_empty() or pl.loc.is_empty():
		return false
	return pl.path_id == 0 and not Track.tunnel_at(pl.track, pl.progress, 12.0).is_empty()


## Hinter dem Ladebild: die nahe (dritter Halt) und die hohe Ansicht je einmal zeichnen, damit ihre Shader übersetzt
## sind, bevor man etwas sieht (die Verfolgerkamera hat world.gd davor schon gezeichnet). Im Browser-Renderer
## (Compatibility) übersetzt die Grafikkarte jeden Shader und jede Licht-Variante erst beim ersten Zeichnen, mitten in
## den Sprüngen und der Landung hakte es dort bis knapp 500 ms: dann zeichnen kleine Kameras die ganze Fahrt vorab
## (wie race._warmup; kostet beim ersten Mal gut 3 s Laden, danach liegen die Shader im Cache).
func prewarm() -> void:
	cam.make_current()
	_apply(_pose(_seq[4][0]))
	# die Zoom-Unschärfe (Tempo-Shader) einmal zeichnen, sonst wird er erst im ersten Sprung übersetzt
	w.fx_mat.set_shader_parameter("blur", 0.0)
	w.fx_mat.set_shader_parameter("swing", 0.0)
	w.fx_mat.set_shader_parameter("nitro", 0.0)
	w._fx_rect.visible = true
	await get_tree().process_frame
	if RenderingServer.get_current_rendering_method() == "gl_compatibility" and not _args.has("--nowarmup"):
		await _warm_path()
	_apply(_pose(0.0))
	await get_tree().process_frame


func _warm_path() -> void:
	var t0 := Time.get_ticks_msec()
	# zweiter Halt; dazu die Sprünge und die Landung in Schritten, der erste Sprung dicht (dort kommen Kleinteile und
	# Laternenlicht in Reichweite: jedes Material bekommt beim ersten Licht eine eigene Variante)
	var ts := [_seq[2][0]]
	for k in [0.15, 0.3, 0.42, 0.52, 0.62, 0.72, 0.84]:
		ts.append(_seq[1][0] + _seq[1][1] * k)
	for k in [0.25, 0.5, 0.75]:
		ts.append(_seq[3][0] + _seq[3][1] * k)
	for k in [0.15, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]:
		ts.append(_seq[5][0] + _seq[5][1] * k)
	var cams := []
	for i in 6:
		var vp := SubViewport.new()
		vp.size = Vector2i(256, 144)
		vp.world_3d = w.world.find_world_3d()
		vp.msaa_3d = w.world.msaa_3d
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var c := Camera3D.new()
		vp.add_child(c)
		add_child(vp)
		cams.append(c)
	var i := 0
	while i < ts.size():
		for c in cams:
			if i < ts.size():
				var pose := _pose(ts[i])
				(c as Camera3D).global_transform = pose["xf"]
				(c as Camera3D).fov = float(pose["fov"]) + 14.0  # etwas weiter: die Ränder zwischen den Proben
				(c as Camera3D).near = pose["near"]
				(c as Camera3D).far = pose["far"]
				i += 1
		await get_tree().process_frame
	await get_tree().process_frame
	for c in cams:
		(c as Node).get_parent().queue_free()
	if _log or _shot_prefix != "":
		print("INTRO vorgezeichnet: %d Ansichten in %d ms" % [ts.size(), Time.get_ticks_msec() - t0])


func start() -> void:
	running = true
	_t = 0.0
	Music.hold_toast(true)  # Musiktitel erst nach der Landung einblenden (kein HUD im Anflug)
	cam.make_current()
	_apply(_pose(0.0))
	_last_us = Time.get_ticks_usec()
	print("INTRO start kind=%s dauer=%.2f s" % [kind, _total])


## Jede Taste, jeder Knopf (auch Trigger und Stick über die Totzone), Klick oder Fingertipp überspringt. Die Eingabe
## bleibt beim Anflug: Esc öffnet nicht noch das Menü, Enter startet kein Rennen. Gehaltene Tasten (Wiederholung)
## zählen nicht; Gas, das man schon hält, wirkt nach der Übergabe sofort.
func _input(event: InputEvent) -> void:
	if not running:
		return
	var press := false
	if event is InputEventKey:
		press = event.pressed and not event.is_echo()
	elif event is InputEventJoypadButton or event is InputEventMouseButton or event is InputEventScreenTouch:
		press = event.is_pressed()
	elif event is InputEventJoypadMotion:
		# Trigger und Lenk-Stick erst deutlich gedrückt (die Totzone der Aktionen ist 0,15: ein zitternder Stick
		# soll den Anflug nicht abbrechen)
		if absf((event as InputEventJoypadMotion).axis_value) > 0.5:
			for a in ["accelerate", "brake", "steer_left", "steer_right"]:
				if event.is_action(a):
					press = true
	elif event is InputEventAction:
		press = event.is_pressed()
	if press:
		get_viewport().set_input_as_handled()
		skip()


func skip() -> void:
	if not running:
		return
	print("INTRO übersprungen bei %.2f s" % _t)
	for a in _whooshes:
		if is_instance_valid(a):
			(a as Node).queue_free()  # stop() gäbe kein finished, der Player bliebe liegen
	_finish(true)


## Ein Bild weiter (world._process, nach Tageslicht, vor der Tempo-Unschärfe)
func step(dt: float) -> void:
	if not running:
		return
	var now := Time.get_ticks_usec()
	var ms := (now - _last_us) / 1000.0
	_last_us = now
	if _frames > 0 and not _shot_frame:
		_sum_ms += ms
		_max_ms = maxf(_max_ms, ms)
		if ms > 30.0:
			_slow += 1
			print("INTRO langsames Bild %.1f ms bei %.2f s" % [ms, _t])
	_shot_frame = false
	_frames += 1
	if _log:
		print("INTRO bild t=%.3f %.1f ms" % [_t, ms])
	_t += minf(dt, 0.05)  # nach einem Hänger nicht springen
	if _skip_at >= 0.0 and _t >= _skip_at:
		_skip_at = -1.0
		for pressed in [true, false]:  # Test: Enter wie echt drücken (geht durch _input)
			var e := InputEventKey.new()
			e.keycode = KEY_ENTER
			e.physical_keycode = KEY_ENTER
			e.pressed = pressed
			Input.parse_input_event(e)
		return
	# Luftrauschen: Spitze (bei Tonhöhe p nach 0,45/p s) in die Mitte des Sprungs
	for i in mini(3, WHOOSH.size()):
		var sq: Array = _seq[1 + i * 2]
		var p: float = WHOOSH[i][1]
		if not _snd[i] and _t >= sq[0] + sq[1] * 0.45 - 0.45 / p:
			_snd[i] = true
			var a: AudioStreamPlayer = Sfx.play("whoosh", WHOOSH[i][0], p)
			if a:
				_whooshes.append(a)
	var land: Array = _seq[5]
	if not _ctrl and _t >= land[0] + land[1] * CTRL_AT:
		_ctrl = true
		player.controls_enabled = true  # keine Wartezeit am Ende
	if _t >= _total:
		_finish(false)
		return
	_apply(_pose(_t))
	_take_shots()


func _take_shots() -> void:
	if _shot_busy or _shot_prefix == "" or _shot_i >= _shot_times.size() or _t < _shot_times[_shot_i]:
		return
	_shot_busy = true  # nicht stapeln, falls das Fenster gerade nicht zeichnet (dann kämen lauter gleiche Bilder)
	var t := _t
	await RenderingServer.frame_post_draw  # das Bild mit der eben gesetzten Pose
	if not is_inside_tree():
		return
	get_viewport().get_texture().get_image().save_png("%s_%s_%02d.png" % [_shot_prefix, kind, _shot_i])
	print("INTRO bild %s_%s_%02d.png t=%.2f" % [_shot_prefix, kind, _shot_i, t])
	_shot_i += 1
	_shot_frame = true
	_shot_busy = false


## Szene endet mitten im Anflug (Spiel beendet): Musiktitel nicht festhalten
func _exit_tree() -> void:
	if running:
		running = false
		Music.hold_toast(false)


## Abgesagt, bevor er beginnt (world.gd, im Tunnel): alles wie ohne Anflug
func cancel() -> void:
	print("INTRO aus: Auto im Tunnel")
	running = false
	Music.hold_toast(false)
	_full_car_model(false)
	player.cam.make_current()
	cam.queue_free()
	queue_free()


func _finish(skipped: bool) -> void:
	running = false
	blur = 0.0
	trail = 0.0
	focus = Vector2(0.5, 0.46)
	_full_car_model(false)
	player.controls_enabled = true
	player.cam.make_current()
	cam.queue_free()
	w.env.fog_density = w.mood["fog_d"]
	Music.hold_toast(false)
	var avg := _sum_ms / maxf(_frames - 1, 1)
	print("INTRO ende kind=%s %s nach %.2f s, %d Bilder, mittel %.1f ms, max %.1f ms, über 30 ms: %d" % [kind,
		"übersprungen" if skipped else "fertig", _t, _frames, avg, _max_ms, _slow])
	w._intro_done(skipped)
	queue_free()


# --- Kamerafahrt --------------------------------------------------------------------------------------------------

static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 4.0 * x * x * x if x < 0.5 else 1.0 - pow(-2.0 * x + 2.0, 3.0) / 2.0


## Geschwindigkeit der Kurve _ease (0..1, Spitze in der Mitte = 1): für Unschärfe und Lichtspuren
static func _speed(x: float) -> float:
	if x <= 0.0 or x >= 1.0:
		return 0.0
	return (x * x * 4.0) if x < 0.5 else pow(2.0 - 2.0 * x, 2.0)


## Pose zur Zeit T: {xf, fov, far, near, dist (Abstand zum Auto für den Nebel), fx (0..1 Bewegung), focus}
func _pose(T: float) -> Dictionary:
	var p: Vector3 = player.global_position
	var fwd: Vector3 = -player.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.01 else Vector3.FORWARD
	var yaw := deg_to_rad(YAW0) * (1.0 - _ease(T / _total))
	var f := fwd.rotated(Vector3.UP, yaw)
	var h: float = _h[0]
	var fx := 0.0
	var seg := 0
	for i in _seq.size():
		if T >= _seq[i][0]:
			seg = i
	var u: float = clampf((T - _seq[seg][0]) / _seq[seg][1], 0.0, 1.0)
	match seg:
		0:
			h = _h[0]
		1, 3:
			var a: float = _h[(seg - 1) / 2]
			var b: float = _h[(seg + 1) / 2]
			h = exp(lerpf(log(a), log(b), _ease(u)))
			fx = _speed(u)
		2, 4:
			h = _h[seg / 2] * (1.0 - CREEP * u)
	if seg < 5:
		var top := {"xf": _top_xf(p, h, f), "fov": FOV_TOP, "dist": h, "fx": fx, "focus": Vector2(0.5, 0.5)}
		top["near"] = clampf(h * 0.004, 0.05, 1.0)
		top["far"] = maxf(player.cam.far, h * 1.6 + 60.0)
		return top
	# Landung: vom dritten Halt im Bogen hinter das Auto, Abstand und Winkel zugleich (der Winkel etwas später); der
	# Blick bleibt lange auf dem Auto und wandert erst zuletzt auf den Punkt davor, auf den die Verfolgerkamera schaut
	# (sonst rutscht das Auto mitten im Schwenk unten aus dem Bild).
	var h_low: float = _h[2] * (1.0 - CREEP)
	var chase: Dictionary = PlayerCar.CHASE[player.cam_mode] if player.cam_mode <= 1 else PlayerCar.CHASE[0]
	var piv := p + Vector3.UP * float(chase["look_y"])
	var back := -f
	var r_end := Vector2(float(chase["dist"]), float(chase["height"]) - float(chase["look_y"]))
	var ang_end := atan2(r_end.y, r_end.x)
	var k_r := _ease(u)
	var k_a := _ease((u - 0.06) / 0.94)
	var r := exp(lerpf(log(h_low - float(chase["look_y"])), log(r_end.length()), k_r))
	var ang := lerpf(PI / 2.0, ang_end, k_a)
	var pos := piv + (back * cos(ang) + Vector3.UP * sin(ang)) * r
	var look := piv.lerp(p + Vector3.UP * float(chase["look_y"]) + fwd * -float(chase["look_z"]), k_a * k_a)
	var up := f.lerp(Vector3.UP, k_a).normalized()
	var xf := Transform3D(Basis.IDENTITY, pos)
	var dir := look - pos
	if dir.length() > 0.01 and absf(dir.normalized().dot(up)) < 0.999:
		xf = xf.looking_at(look, up)
	else:
		xf = _top_xf(p, maxf(pos.y - p.y, 1.0), f)
	var fov := lerpf(FOV_TOP, player.cam.fov, k_a)
	# zuletzt genau auf die echte Verfolgerkamera (die rechnet weiter, auch wenn sie nicht zeigt)
	if player.cam_mode <= 1:
		var k_end := smoothstep(0.72, 1.0, u)
		var pc: Transform3D = player.cam.global_transform
		xf = Transform3D(xf.basis.slerp(pc.basis.orthonormalized(), k_end), xf.origin.lerp(pc.origin, k_end))
	var fxk := _speed(u) * 0.5
	return {"xf": xf, "fov": fov, "dist": maxf(xf.origin.distance_to(p), 1.0), "fx": fxk,
		"near": lerpf(clampf(h_low * 0.004, 0.05, 1.0), player.cam.near, k_r),
		"far": lerpf(maxf(player.cam.far, h_low * 1.6 + 60.0), player.cam.far, k_a),
		"focus": Vector2(0.5, 0.5).lerp(Vector2(0.5, 0.46), k_a)}


## Senkrecht nach unten, oben im Bild liegt f (die Fahrtrichtung, leicht gedreht)
static func _top_xf(p: Vector3, h: float, f: Vector3) -> Transform3D:
	var z := Vector3.UP  # die Kamera schaut entlang -Z, also nach unten
	var y := f
	var x := y.cross(z).normalized()
	return Transform3D(Basis(x, y, z), p + Vector3.UP * h)


func _apply(pose: Dictionary) -> void:
	cam.global_transform = pose["xf"]
	cam.fov = pose["fov"]
	cam.near = pose["near"]
	cam.far = pose["far"]
	# Nebel nach Abstand: über dem Auto liegt höchstens HAZE Dunst, darunter der normale Nebel
	var base: float = w.mood["fog_d"]
	var d: float = pose["dist"]
	var haze := lerpf(HAZE.x, HAZE.y, clampf(float(w.mood.get("day", 0.0)), 0.0, 1.0))
	w.env.fog_density = minf(base, -log(1.0 - haze) / maxf(d, 1.0))
	blur = BLUR_DROP * float(pose["fx"])
	trail = TRAIL * float(pose["fx"])
	focus = pose["focus"]  # Fluchtpunkt: von oben das Auto in der Bildmitte, hinter dem Auto der Horizont


## Volles Automodell während des Anflugs: Teile mit Sichtweite (Nahansicht) ohne Grenze, die Fernansicht aus;
## am Ende zurück (dann ist die Kamera hinter dem Auto, da gilt ohnehin die Nahansicht)
func _full_car_model(on: bool) -> void:
	if on:
		var st: Array = [player.model]
		while not st.is_empty():
			var n: Node = st.pop_back()
			st.append_array(n.get_children())
			if n is GeometryInstance3D:
				var gi := n as GeometryInstance3D
				if gi.visibility_range_end > 0.0:
					_car_lod.append([gi, "visibility_range_end", gi.visibility_range_end])
					gi.visibility_range_end = 0.0
				if gi.visibility_range_begin > 0.0:
					_car_lod.append([gi, "visibility_range_begin", gi.visibility_range_begin])
					gi.visibility_range_begin = 1.0e7
	else:
		for it in _car_lod:
			if is_instance_valid(it[0]):
				(it[0] as Object).set(it[1], it[2])
		_car_lod.clear()
