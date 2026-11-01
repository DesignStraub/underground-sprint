extends Node3D
## Hauptmenü in der Garage: dein Auto dreht sich im Neonlicht, links das Menü.
## Tuning und Autowechsel zeigen gesperrte Teile als Vorschau, gespeichert wird nur Freigeschaltetes.

const Catalog := preload("res://scripts/catalog.gd")
const Builder := preload("res://scripts/car_builder.gd")
const PixelView := preload("res://scripts/pixel_view.gd")

var world: SubViewport
var turntable: Node3D
var car_node: Node3D
var cam: Camera3D
var menu: VBoxContainer
var title: Label
var info: Label
var status: Label
var preview_car := ""
var preview_cfg := {}
var _t := 0.0


func _ready() -> void:
	_build_scene()
	_build_ui()
	_show_main()


func _build_scene() -> void:
	var view_layer := CanvasLayer.new()
	view_layer.layer = -1
	add_child(view_layer)
	var pv := PixelView.new()
	view_layer.add_child(pv)
	world = pv.world
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.3, 0.45)
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 1.0
	env.glow_hdr_threshold = 0.9
	env.ssr_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var floor_m := Builder.mat(Color(0.05, 0.05, 0.06), 0.4, 0.12)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	floor_mi.mesh = pm
	floor_mi.material_override = floor_m
	world.add_child(floor_mi)

	var wall_m := Builder.mat(Color(0.08, 0.08, 0.1), 0.1, 0.8)
	for w in [[Vector3(0, 4, -7), Vector3(30, 8, 0.4)], [Vector3(-8, 4, 0), Vector3(0.4, 8, 30)]]:
		var mi := MeshInstance3D.new()
		mi.mesh = Builder.box(w[1])
		mi.material_override = wall_m
		mi.position = w[0]
		world.add_child(mi)

	# Neonröhren an den Wänden
	var tubes := [[Vector3(0, 2.2, -6.75), Vector3(14, 0.08, 0.08), Color(1, 0.1, 0.6)],
		[Vector3(0, 3.0, -6.75), Vector3(14, 0.08, 0.08), Color(0.1, 0.7, 1)],
		[Vector3(-7.75, 2.6, 0), Vector3(0.08, 0.08, 12), Color(0.1, 0.7, 1)]]
	for t in tubes:
		var mi := MeshInstance3D.new()
		mi.mesh = Builder.box(t[1])
		mi.material_override = Builder.mat(t[2], 0, 0.5, t[2], 6.0)
		mi.position = t[0]
		world.add_child(mi)
		var l := OmniLight3D.new()
		l.light_color = t[2]
		l.light_energy = 2.0
		l.omni_range = 9.0
		l.position = t[0] + Vector3(0.6 if t[0].x < -7 else 0.0, 0, 0.6 if t[0].z < -6 else 0.0)
		world.add_child(l)

	var top := SpotLight3D.new()
	top.position = Vector3(0, 6, 1)
	top.rotation_degrees.x = -80
	top.spot_range = 10
	top.spot_angle = 40
	top.light_energy = 3.0
	top.shadow_enabled = true
	world.add_child(top)
	var fill := OmniLight3D.new()
	fill.position = Vector3(4, 2, 4)
	fill.light_energy = 0.8
	fill.omni_range = 10
	world.add_child(fill)

	turntable = Node3D.new()
	world.add_child(turntable)
	var disc := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 3.2
	cm.bottom_radius = 3.2
	cm.height = 0.06
	cm.radial_segments = 48
	disc.mesh = cm
	disc.material_override = Builder.mat(Color(0.12, 0.12, 0.14), 0.7, 0.3)
	disc.position.y = 0.03
	turntable.add_child(disc)
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 3.15
	tm.outer_radius = 3.25
	ring.mesh = tm
	ring.material_override = Builder.mat(Color(0.1, 0.7, 1), 0, 0.5, Color(0.1, 0.7, 1), 4.0)
	ring.position.y = 0.06
	world.add_child(ring)

	cam = Camera3D.new()
	cam.fov = 50
	world.add_child(cam)
	cam.make_current()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.45)
	shade.position = Vector2(0, 0)
	shade.size = Vector2(230, 2000)
	root.add_child(shade)

	title = _label(root, 22)
	title.position = Vector2(14, 10)
	title.text = "UNDERGROUND\nSPRINT"
	title.label_settings.font_color = Color(0.4, 0.85, 1.0)
	status = _label(root, 11)
	status.position = Vector2(14, 72)

	menu = VBoxContainer.new()
	menu.position = Vector2(14, 96)
	menu.custom_minimum_size = Vector2(200, 0)
	menu.add_theme_constant_override("separation", 3)
	root.add_child(menu)

	info = _label(root, 10)
	info.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	info.position = Vector2(14, -70)
	info.size = Vector2(210, 64)
	info.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var music := _label(root, 10, HORIZONTAL_ALIGNMENT_RIGHT)
	music.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	music.position = Vector2(-330, -22)
	music.size = Vector2(320, 16)
	music.set_meta("music", true)
	_music_label = music


var _music_label: Label


func _label(parent: Node, size: int, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font_size = size
	ls.outline_size = 3
	ls.outline_color = Color(0, 0, 0, 0.9)
	l.label_settings = ls
	l.horizontal_alignment = align
	parent.add_child(l)
	return l


func _process(dt: float) -> void:
	_t += dt
	turntable.rotation.y += dt * 0.3
	var target := Vector3(-1.6, 0.55, 0)
	cam.position = Vector3(4.6 + sin(_t * 0.2) * 0.2, 1.7 + sin(_t * 0.3) * 0.08, 5.6)
	cam.look_at(target)
	status.text = "Siege: %d    Auto: %s" % [GameState.wins, Catalog.CARS[GameState.current_car]["name"]]
	_music_label.text = ("Musik: " + Music.current_title) if Music.current_title != "" else "Keine Musik: mp3/ogg in music/ legen"


func _show_car(car_id: String, cfg: Dictionary) -> void:
	if car_node:
		car_node.queue_free()
	car_node = Builder.build(car_id, cfg, false)
	turntable.add_child(car_node)
	car_node.position.y = 0.06


# --- Menüs ----------------------------------------------------------------

func _clear_menu() -> void:
	for c in menu.get_children():
		menu.remove_child(c)
		c.queue_free()


func _button(text: String, cb: Callable, disabled := false) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = disabled
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(cb)
	menu.add_child(b)
	return b


func _focus_first() -> void:
	for c in menu.get_children():
		if c is Button and not c.disabled:
			c.grab_focus.call_deferred()
			return


func _show_main() -> void:
	_clear_menu()
	preview_car = GameState.current_car
	preview_cfg = GameState.get_config(preview_car).duplicate()
	_show_car(preview_car, preview_cfg)
	_button("Rennen fahren", _show_races)
	_button("Tuning", _show_tuning)
	_button("Auto wechseln", _show_cars)
	var gfx := _button("", func(): pass)
	gfx.pressed.connect(func():
		GameState.cycle_pixel_mode()
		gfx.text = "Pixel-Look: " + GameState.PIXEL_MODES[GameState.pixel_mode]["name"])
	gfx.text = "Pixel-Look: " + GameState.PIXEL_MODES[GameState.pixel_mode]["name"]
	_button("Vollbild", GameState.toggle_fullscreen)
	_button("Spielstand zurücksetzen", _confirm_reset)
	if not OS.has_feature("web"):  # im Browser schließt man einfach den Tab
		_button("Beenden", func(): get_tree().quit())
	info.text = Catalog.CARS[preview_car]["desc"] + "\nF / F11: Vollbild"
	_focus_first()


func _show_races() -> void:
	_clear_menu()
	for i in Catalog.RACES.size():
		var r: Dictionary = Catalog.RACES[i]
		var unlocked := GameState.is_race_unlocked(i)
		var txt: String = r["name"]
		if not unlocked:
			txt += "  [%d Siege]" % r["wins"]
		elif GameState.best_times.has(r["name"]):
			var t: float = GameState.best_times[r["name"]]
			txt += "  %d:%05.2f" % [int(t) / 60, fmod(t, 60.0)]
		var idx := i
		_button(txt, func(): _start_race(idx), not unlocked)
	_button("< Zurück", _show_main)
	info.text = "Sprint gegen 3 Gegner. Nur Platz 1 zählt als Sieg und schaltet Teile frei."
	_focus_first()


func _start_race(i: int) -> void:
	GameState.race_index = i
	GameState.save_game()
	get_tree().change_scene_to_file("res://scenes/race.tscn")


func _show_tuning() -> void:
	_clear_menu()
	for cat in Catalog.PART_ORDER:
		var b := _button("", func(): _cycle_part(cat, 1))
		b.set_meta("cat", cat)
		b.gui_input.connect(func(ev): _lr_input(ev, func(dir): _cycle_part(cat, dir)))
		b.focus_entered.connect(func(): _part_info(cat))
	_button("< Fertig", _show_main)
	_refresh_tuning()
	_focus_first()


func _refresh_tuning() -> void:
	for b in menu.get_children():
		if not b.has_meta("cat"):
			continue
		var cat: String = b.get_meta("cat")
		var opt: Dictionary = Catalog.PARTS[cat]["options"][preview_cfg[cat]]
		var lock := "" if GameState.is_part_unlocked(cat, preview_cfg[cat]) else "  [GESPERRT]"
		b.text = "%s:  < %s >%s" % [Catalog.PARTS[cat]["label"], opt["name"], lock]


func _cycle_part(cat: String, dir: int) -> void:
	var n: int = Catalog.PARTS[cat]["options"].size()
	preview_cfg[cat] = posmod(preview_cfg[cat] + dir, n)
	if GameState.is_part_unlocked(cat, preview_cfg[cat]):
		GameState.get_config(preview_car)[cat] = preview_cfg[cat]
		GameState.save_game()
	_show_car(preview_car, preview_cfg)
	_refresh_tuning()
	_part_info(cat)


func _part_info(cat: String) -> void:
	var idx: int = preview_cfg[cat]
	var opt: Dictionary = Catalog.PARTS[cat]["options"][idx]
	if GameState.is_part_unlocked(cat, idx):
		info.text = "%s: %s\nLinks/Rechts zum Wechseln." % [Catalog.PARTS[cat]["label"], opt["name"]]
	else:
		var missing: int = opt["wins"] - GameState.wins
		info.text = "%s ist gesperrt.\nNoch %d Sieg%s nötig. (Nur Vorschau)" % [opt["name"], missing, "" if missing == 1 else "e"]


func _show_cars() -> void:
	_clear_menu()
	var b := _button("", func(): _cycle_car(1))
	b.set_meta("car", true)
	b.gui_input.connect(func(ev): _lr_input(ev, _cycle_car))
	_button("Dieses Auto fahren", _choose_car)
	_button("< Zurück", _show_main)
	_refresh_car()
	_focus_first()


func _cycle_car(dir: int) -> void:
	var i := Catalog.CAR_ORDER.find(preview_car)
	preview_car = Catalog.CAR_ORDER[posmod(i + dir, Catalog.CAR_ORDER.size())]
	preview_cfg = GameState.get_config(preview_car).duplicate()
	_show_car(preview_car, preview_cfg)
	_refresh_car()


func _refresh_car() -> void:
	var spec: Dictionary = Catalog.CARS[preview_car]
	var unlocked := GameState.is_car_unlocked(preview_car)
	menu.get_child(0).text = "< %s >%s" % [spec["name"], "" if unlocked else "  [GESPERRT]"]
	menu.get_child(1).disabled = not unlocked
	var stats := "Beschl. %s\nTopspeed %s  (%d km/h)\nGrip %s" % [
		_stars(spec["accel"], 9.0, 13.0), _stars(spec["top_speed"], 55.0, 75.0), int(spec["top_speed"] * 3.6),
		_stars(spec["grip"], 20.0, 29.0)]
	info.text = spec["desc"] + "\n" + stats
	if not unlocked:
		info.text += "\nFreischalten: %d Siege" % spec["wins"]


func _stars(v: float, lo: float, hi: float) -> String:
	var n := int(round(clampf((v - lo) / (hi - lo), 0.0, 1.0) * 4.0)) + 1
	return "#".repeat(n) + ".".repeat(5 - n)


func _choose_car() -> void:
	if GameState.is_car_unlocked(preview_car):
		GameState.current_car = preview_car
		GameState.save_game()
		_show_main()


func _confirm_reset() -> void:
	_clear_menu()
	info.text = "Alle Siege und Tuningteile gehen verloren."
	_button("Ja, zurücksetzen", func(): GameState.reset_progress(); _show_main())
	_button("Abbrechen", _show_main)
	menu.get_child(1).grab_focus.call_deferred()


func _lr_input(ev: InputEvent, cb: Callable) -> void:
	if ev.is_action_pressed("ui_left"):
		cb.call(-1)
		get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("ui_right"):
		cb.call(1)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_show_main()
