extends Node
## Splitscreen für zwei (seit 2.47, Fahrplan Punkt 7): nur in Rennen (in der offenen Welt wären zwei Ansichten zu viele
## Orte auf einmal) und nur am Rechner (nicht im Browser). Spieler 1 oben, Spieler 2 unten: eine zweite Bildfläche
## (PixelView) auf dieselbe 3D-Welt mit eigener Kamera, die jedes Bild der Kamera von Spieler 2 folgt. Zwei Gegner statt
## drei, kein Verkehr (er bremst nur für Spieler 1). Spieler 2 hat unten eine kleine Anzeige (Platz, Runde, Tempo,
## Nitro). Ziel: sind beide durch (oder 25 s nach dem ersten), eine gemeinsame Wertung; ein Spaßrennen ohne Erfahrung
## und Karriere. Tasten: GameState.split_input. Test: race.tscn -- --race=i --split [--p2bot].

const PlayerCar := preload("res://scripts/player_car.gd")
const PixelView := preload("res://scripts/pixel_view.gd")
const Track := preload("res://scripts/track_builder.gd")
const UI := preload("res://scripts/ui_style.gd")
const Catalog := preload("res://scripts/catalog.gd")
const RACING := 1  # race.gd State.RACING
const FINISHED := 2  # race.gd State.FINISHED

var race: Node  # race.gd
var p2: CharacterBody3D
var view2: TextureRect
var cam2: Camera3D
var t1 := -1.0  # Zielzeiten (-1: noch nicht im Ziel)
var t2 := -1.0
var _wait := 0.0
var _done := false
var _hud: Control
var _info2: Label
var _speed2: Label
var _center2: Label
var _bot := false


func setup(r: Node, pv1: TextureRect) -> void:
	race = r
	_bot = OS.get_cmdline_user_args().has("--p2bot")
	pv1.half = 1
	pv1.anchor_bottom = 0.5
	pv1.offset_bottom = 0.0
	pv1._resize()
	view2 = PixelView.new()
	view2.half = 2
	# Welt des oberen Bildes teilen, bevor das Bild in den Baum kommt (world_3d ist dort leer: find_world_3d)
	view2.world.own_world_3d = false
	view2.world.world_3d = pv1.world.find_world_3d()
	pv1.get_parent().add_child(view2)
	view2.anchor_top = 0.5
	view2.offset_top = 0.0
	view2.world.audio_listener_enable_3d = false
	view2.world.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	cam2 = Camera3D.new()
	view2.world.add_child(cam2)
	cam2.make_current()
	var id: String = GameState.p2_car if Catalog.CARS.has(GameState.p2_car) else GameState.current_car
	p2 = PlayerCar.new()
	p2.process_mode = Node.PROCESS_MODE_PAUSABLE
	p2.input_prefix = "p2_"
	p2.track = race.track
	race.world.add_child(p2)
	p2.setup(id, GameState.get_config(id))
	p2.top_speed *= GameState.pace()
	p2.accel *= 0.8 + 0.2 * GameState.pace()
	p2.place(Track.xform_at(race.curve, float(race.track["start"]) - 6.0, Track.LANES[1]))
	p2.controls_enabled = false
	p2.set_meta("hud_col", Color(1.0, 0.85, 0.2))
	race.player.cam.make_current()  # setup() hatte die Kamera von Spieler 2 im oberen Bild aktuell gemacht


## Anzeige von Spieler 2 in der unteren Hälfte (die von Spieler 1 bleibt oben)
func build_hud(layer: CanvasLayer) -> void:
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.anchor_top = 0.5
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_hud)
	var line := ColorRect.new()  # Trennlinie zwischen den Bildern
	line.color = Color(0, 0, 0, 0.9)
	line.anchor_right = 1.0
	line.offset_top = -1.0
	line.offset_bottom = 1.0
	_hud.add_child(line)
	_info2 = race._label(_hud, 14)
	_info2.position = Vector2(10, 8)
	_info2.label_settings.font = UI.font("cond", 0.2)
	_speed2 = race._label(_hud, 14)
	_speed2.anchor_left = 1.0
	_speed2.anchor_right = 1.0
	_speed2.offset_left = -180.0
	_speed2.offset_right = -10.0
	_speed2.offset_top = 8.0
	_speed2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed2.label_settings.font = UI.font("cond", 0.2)
	_center2 = race._label(_hud, 24)
	_center2.anchor_left = 0.5
	_center2.anchor_right = 0.5
	_center2.anchor_top = 0.35
	_center2.offset_left = -300.0
	_center2.offset_right = 300.0
	_center2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center2.label_settings.font = UI.font("wide", 0.15)


func go() -> void:
	p2.controls_enabled = true


## Platz eines Autos unter allen (beide Spieler und Gegner): im Ziel nach Zeit vorn, sonst nach Weg
func place_of(car: Node) -> int:
	var rows := []
	rows.append([race.player, t1, float(race.player.total)])
	rows.append([p2, t2, float(p2.total)])
	for ai in race.ais:
		rows.append([ai, float(ai.finish_time), float(ai.total)])
	rows.sort_custom(func(a, b):
		if a[1] >= 0.0 and b[1] >= 0.0:
			return a[1] < b[1]
		if a[1] >= 0.0 or b[1] >= 0.0:
			return a[1] >= 0.0
		return a[2] > b[2])
	for i in rows.size():
		if rows[i][0] == car:
			return i + 1
	return rows.size()


func step(dt: float) -> void:
	if p2 == null:
		return
	cam2.global_transform = p2.cam.global_transform
	cam2.fov = p2.cam.fov
	cam2.near = p2.cam.near
	cam2.far = p2.cam.far
	if _bot and race.state == RACING and t2 < 0.0:
		_drive_bot()
	if _info2:
		var n: int = race.ais.size() + 2
		var txt := tr("SPIELER 2") + "\n" + tr("PLATZ %d / %d") % [place_of(p2), n]
		if race.track["loop"]:
			txt += "   " + tr("RUNDE %d/%d") % [mini(p2.lap + 1, int(race.track["laps"])), int(race.track["laps"])]
		_info2.text = txt
		_speed2.text = "%d KM/H\nNITRO %d %%" % [int(absf(p2.speed_fwd) * 3.6), int(p2.nitro * 100.0)]
		_center2.text = race.hud["center"].text if t2 < 0.0 else _center2.text
	if race.state != RACING or _done:
		return
	if t2 < 0.0 and p2.total >= float(race.track["finish"]):
		t2 = race.race_time
		p2.controls_enabled = false
		p2.finished = true
		_center2.text = tr("%d. PLATZ") % place_of(p2)
	if t1 >= 0.0 or t2 >= 0.0:
		_wait += dt
	if (t1 >= 0.0 and t2 >= 0.0) or _wait > 25.0:
		_done = true
		_show_result()


## Spieler 1 im Ziel (race.gd statt der normalen Zielszene)
func p1_finished() -> void:
	if t1 >= 0.0:
		return
	t1 = race.race_time
	race.player.controls_enabled = false
	race.player.finished = true
	race.hud["center"].text = tr("%d. PLATZ") % place_of(race.player)


func reset_p2() -> void:
	var loc := Track.locate(race.track, p2.global_position)
	var p: Dictionary = loc["path"]
	var half: float = p["half_w"] - 2.0
	p2.place(Track.xform_at(p["curve"], loc["d"], clampf(loc["lat"], -half, half)))


func _show_result() -> void:
	race.state = FINISHED
	race.player.controls_enabled = false
	p2.controls_enabled = false
	var pl1 := place_of(race.player)
	var pl2 := place_of(p2)
	var head := tr("SPIELER 1 GEWINNT!") if pl1 < pl2 else tr("SPIELER 2 GEWINNT!")
	if pl1 > 1 and pl2 > 1:
		head = tr("DIE GEGNER WAREN SCHNELLER")
	var panel := PanelContainer.new()
	panel.theme = UI.theme()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-170, -70)
	panel.custom_minimum_size = Vector2(340, 0)
	_hud.get_parent().add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	var h: Label = race._label(vb, 18, HORIZONTAL_ALIGNMENT_CENTER)
	h.text = head
	h.label_settings.font_color = UI.GOLD
	for row in [[tr("SPIELER 1"), pl1, t1], [tr("SPIELER 2"), pl2, t2]]:
		var l: Label = race._label(vb, 13, HORIZONTAL_ALIGNMENT_CENTER)
		l.text = "%s:  %s   %s" % [row[0], tr("%d. PLATZ") % row[1], race._fmt(row[2]) if row[2] >= 0.0 else tr("nicht im Ziel")]
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(hb)
	var again := Button.new()
	again.text = tr("NOCHMAL")
	again.pressed.connect(func(): race.get_tree().reload_current_scene())
	hb.add_child(again)
	UI.menu_fx(again, "bottom")
	var back := Button.new()
	back.text = "GARAGE"
	back.pressed.connect(func():
		GameState.split = false
		race.get_tree().change_scene_to_file("res://scenes/garage.tscn"))
	hb.add_child(back)
	UI.menu_fx(back, "bottom")
	back.grab_focus.call_deferred()
	print("SPLIT Ziel: Spieler 1 Platz %d %.2f s, Spieler 2 Platz %d %.2f s" % [pl1, t1, pl2, t2])
	if OS.get_cmdline_user_args().has("--splitquit"):
		race.get_tree().create_timer(1.5).timeout.connect(race.get_tree().quit)


## Test (--p2bot): Spieler 2 fährt die Hauptstraße entlang (wie der Autopilot der Tests)
func _drive_bot() -> void:
	if p2.loc.is_empty():
		return
	var c: Curve3D = p2.loc["path"]["curve"]
	var d := c.get_closest_offset(p2.global_position)
	var ft := Track.frame_at(c, d + 16.0 + absf(p2.speed_fwd) * 0.5)
	var tgt: Vector3 = ft["pos"] + ft["right"] * 2.0
	var side := (tgt - p2.global_position).dot(p2.global_basis.x)
	Input.action_release("p2_steer_left")
	Input.action_release("p2_steer_right")
	if side > 0.6:
		Input.action_press("p2_steer_right", clampf(side / 6.0, 0.2, 1.0))
	elif side < -0.6:
		Input.action_press("p2_steer_left", clampf(-side / 6.0, 0.2, 1.0))
	Input.action_press("p2_accelerate", 0.85)
