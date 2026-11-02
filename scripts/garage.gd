extends Node3D
## Hauptmenü in der Garage: dein Auto dreht sich im Neonlicht, links das Menü.
## Tuning und Autowechsel zeigen gesperrte Teile als Vorschau, gespeichert wird nur Freigeschaltetes.

const Catalog := preload("res://scripts/catalog.gd")
const Builder := preload("res://scripts/car_builder.gd")
const PixelView := preload("res://scripts/pixel_view.gd")
const UI := preload("res://scripts/ui_style.gd")

## Ladetipps wie früher, nur ehrlicher
const TIPS := [
	"Lachgas ist kein Partygas. Shift drücken.",
	"Im grünen Bereich schalten. Wie Mülltrennung: einfach richtig machen.",
	"Blitzer gibt es hier keine. Glauben wir.",
	"Gas kurz vor LOS, sonst qualmen nur die Reifen.",
	"Knapp am Verkehr vorbei gibt Lachgas. Nicht zu knapp.",
	"Auf Platz 4 gibt es eine Teilnahmeurkunde. Immerhin.",
	"Handbremse plus Lenken gleich quer. Quer gleich Punkte.",
	"Der TÜV kommt nächstes Jahr. Bis dahin: Vollgas.",
	"In Würzburg nicht in den Main fahren. Der ist nass.",
	"Abkürzungen sparen Zeit. Gegenverkehr kostet Nerven.",
	"Baustellen sind hier Dauerzustand. Wie im echten Leben.",
]

var world: SubViewport
var turntable: Node3D
var car_node: Node3D
var cam: Camera3D
var menu: VBoxContainer
var title: Label
var info: Label
var status: Label
var section: Label
var stats: VBoxContainer
var tip: Label
var _tip_i := 0
var _tip_t := 0.0
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
	env.ssr_enabled = GameState.q()["ssr"] > 0
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
	root.theme = UI.theme()
	layer.add_child(root)
	# Abdunklung links (Menü) und unten (Tastenleiste), das Auto bleibt frei
	var fade := UI.fade_rect(root, Color(0, 0, 0, 0.8))
	fade.size = Vector2(330, 2000)
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0.7)
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.anchor_right = 1.0
	bar.offset_top = -18.0
	root.add_child(bar)
	var bar_line := ColorRect.new()
	bar_line.color = Color(UI.GREEN.r, UI.GREEN.g, UI.GREEN.b, 0.8)
	bar_line.anchor_top = 1.0
	bar_line.anchor_bottom = 1.0
	bar_line.anchor_right = 1.0
	bar_line.offset_top = -19.0
	bar_line.offset_bottom = -18.0
	root.add_child(bar_line)

	# Logo oben links
	var small := _label(root, 9)
	small.label_settings.font = UI.font("wide", 0.15)
	small.text = "NEED FOR"
	small.position = Vector2(14, 6)
	title = _label(root, 17)
	title.label_settings.font = UI.font("cond", 0.2)
	title.text = "GESCHWINDIGKEIT"
	title.label_settings.font_color = UI.CYAN
	title.label_settings.shadow_color = Color(UI.PINK.r, UI.PINK.g, UI.PINK.b, 0.5)
	title.label_settings.shadow_size = 4
	title.label_settings.shadow_offset = Vector2.ZERO
	title.position = Vector2(13, 15)
	section = UI.section(root, Vector2(14, 38))

	menu = VBoxContainer.new()
	menu.position = Vector2(14, 86)
	menu.custom_minimum_size = Vector2(210, 0)
	menu.add_theme_constant_override("separation", 3)
	root.add_child(menu)

	# oben rechts: Stand, Tipp, Leistung des Autos
	status = _label(root, 10, HORIZONTAL_ALIGNMENT_RIGHT)
	status.label_settings.font = UI.font("bold", 0.12)
	status.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	status.offset_left = -330.0
	status.offset_right = -12.0
	status.offset_top = 8.0
	tip = _label(root, 9, HORIZONTAL_ALIGNMENT_RIGHT)
	tip.label_settings.font = UI.font("bold", 0.12)
	tip.label_settings.font_color = UI.CYAN
	tip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tip.offset_left = -330.0
	tip.offset_right = -12.0
	tip.offset_top = 22.0
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var sp := PanelContainer.new()
	sp.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	sp.offset_left = -232.0
	sp.offset_right = -12.0
	sp.offset_top = 50.0
	sp.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	root.add_child(sp)
	stats = VBoxContainer.new()
	stats.add_theme_constant_override("separation", 1)
	sp.add_child(stats)

	# Infotext in einer Glasfläche unten rechts
	var panel := PanelContainer.new()
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -300.0
	panel.offset_right = -14.0
	panel.offset_top = -92.0
	panel.offset_bottom = -26.0
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(panel)
	info = _label(panel, 10)
	info.label_settings.font = UI.font("bold", 0.0)
	info.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(250, 0)

	var keys := _label(root, 9)
	keys.label_settings.font = UI.font("bold", 0.12)
	keys.text = "ENTER  Auswählen      ESC  Zurück      ←/→  Ändern      F11  Vollbild"
	keys.anchor_top = 1.0
	keys.anchor_bottom = 1.0
	keys.offset_left = 14.0
	keys.offset_top = -16.0
	keys.offset_right = 400.0
	var music := _label(root, 9, HORIZONTAL_ALIGNMENT_RIGHT)
	music.label_settings.font = UI.font("bold", 0.12)
	music.label_settings.font_color = Color(0.7, 0.75, 0.85)
	music.anchor_left = 1.0
	music.anchor_right = 1.0
	music.anchor_top = 1.0
	music.anchor_bottom = 1.0
	music.offset_left = -330.0
	music.offset_right = -12.0
	music.offset_top = -16.0
	music.set_meta("music", true)
	_music_label = music
	_tip_i = randi() % TIPS.size()
	tip.text = "TIPP: " + TIPS[_tip_i]


## Leistungsbalken wie im Autohaus (10 Segmente), Motor-Tuning eingerechnet
func _show_stats(car_id: String, cfg: Dictionary) -> void:
	for c in stats.get_children():
		c.queue_free()
	var spec: Dictionary = Catalog.CARS[car_id]
	var eng: Dictionary = Catalog.PARTS["engine"]["options"][cfg.get("engine", 0)]
	var head := _label(stats, 10, HORIZONTAL_ALIGNMENT_RIGHT)
	head.label_settings.font = UI.font("cond", 0.2)
	head.label_settings.font_color = UI.GREEN
	head.text = "LEISTUNG"
	for row in [["BESCHLEUNIGUNG", spec["accel"] * eng["accel"], 9.0, 14.5], ["TOPSPEED", spec["top_speed"] * eng["top"], 54.0, 82.0],
			["GRIP", spec["grip"], 19.0, 30.0], ["DRIFT", spec.get("drift", 0.3), 0.0, 1.0]]:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 2)
		stats.add_child(hb)
		var l := _label(hb, 8)
		l.label_settings.font = UI.font("bold", 0.12)
		l.text = row[0]
		l.custom_minimum_size = Vector2(76, 0)
		var n := int(round(clampf((row[1] - row[2]) / (row[3] - row[2]), 0.05, 1.0) * 10.0))
		for k in 10:
			var seg := ColorRect.new()
			seg.custom_minimum_size = Vector2(11, 6)
			seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			seg.color = (UI.GREEN if k < n else Color(1, 1, 1, 0.12))
			hb.add_child(seg)
	var top := _label(stats, 8, HORIZONTAL_ALIGNMENT_RIGHT)
	top.label_settings.font = UI.font("bold", 0.12)
	top.label_settings.font_color = UI.CYAN
	top.text = "%d KM/H" % int(spec["top_speed"] * eng["top"] * 3.6)


func _set_section(text: String, with_stats := false) -> void:
	section.text = text
	stats.get_parent().visible = with_stats
	if with_stats:
		_show_stats(preview_car, preview_cfg)


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
	_tip_t += dt
	if _tip_t > 6.0:
		_tip_t = 0.0
		_tip_i = (_tip_i + 1) % TIPS.size()
		tip.text = "TIPP: " + TIPS[_tip_i]
	turntable.rotation.y += dt * 0.3
	var target := Vector3(-1.6, 0.55, 0)
	cam.position = Vector3(4.6 + sin(_t * 0.2) * 0.2, 1.7 + sin(_t * 0.3) * 0.08, 5.6)
	cam.look_at(target)
	status.text = "RENNSIEGE %d   ·   DRIFTSIEGE %d   ·   %s" % [GameState.wins, GameState.drift_wins, Catalog.CARS[GameState.current_car]["name"].to_upper()]
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
	b.text = text.to_upper()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = disabled
	b.focus_entered.connect(func(): Sfx.play("whoosh", -26.0, 2.4))
	b.pressed.connect(cb)
	menu.add_child(b)
	return b


func _focus_first() -> void:
	menu.modulate.a = 0.0
	menu.position.x = -24.0
	section.modulate.a = 0.0
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(menu, "position:x", 14.0, 0.18)
	tw.tween_property(menu, "modulate:a", 1.0, 0.18)
	tw.tween_property(section, "modulate:a", 1.0, 0.25)
	for c in menu.get_children():
		if c is Button and not c.disabled:
			c.grab_focus.call_deferred()
			return


func _show_main() -> void:
	_clear_menu()
	preview_car = GameState.current_car
	preview_cfg = GameState.get_config(preview_car).duplicate()
	_show_car(preview_car, preview_cfg)
	_set_section("GARAGE", true)
	_button("Rennen fahren", _show_races)
	_button("Tuning", _show_tuning)
	_button("Auto wechseln", _show_cars)
	_button("Einstellungen", _show_settings)
	if not OS.has_feature("web"):  # im Browser schließt man einfach den Tab
		_button("Feierabend", func(): get_tree().quit())
	info.text = Catalog.CARS[preview_car]["desc"] + "\nF / F11: Vollbild"
	_focus_first()


## Grafik, Vollbild, Spielstand: nicht auf der Startseite, sondern gesammelt hier
func _show_settings() -> void:
	_clear_menu()
	_set_section("EINSTELLUNGEN")
	var hints := {
		"quality": "Niedrig: schnell, ohne Spiegelungen. Mittel: Spiegelungen auf nasser Straße. Hoch: alles, braucht eine starke Grafikkarte. Gilt ab dem nächsten Rennen.",
		"pixel": "Pixel-Look: die 3D-Welt grob gerastert wie ein Retro-Spiel. Spart zusätzlich Leistung.",
		"vsync": "V-Sync: kein Bildreißen. Aus = mehr FPS, aber evtl. Tearing.",
		"fps": "FPS-Limit: begrenzt die Bildrate (schont Akku und Lüfter).",
		"fullscreen": "Vollbild (auch F / F11).",
	}
	for key in ["quality", "pixel", "vsync", "fps", "fullscreen"]:
		var k: String = key
		var b := _button(GameState.setting_text(k), func(): pass)
		b.pressed.connect(func():
			if k == "fullscreen":
				GameState.toggle_fullscreen()
			else:
				GameState.cycle_setting(k)
			b.text = GameState.setting_text(k))
		b.focus_entered.connect(func(): info.text = hints[k])
	_button("Spielstand zurücksetzen", _confirm_reset)
	_button("< Zurück", _show_main)
	info.text = hints["quality"]
	_focus_first()


## Erst die Art wählen, dann das Event. Alles ist frei wählbar; Drift-Siege schalten Driftautos frei.
func _show_races() -> void:
	_clear_menu()
	_set_section("RENNEN")
	for type in Catalog.TYPE_ORDER + ["city"]:
		var n := 0
		for r in Catalog.RACES:
			if _in_list(r, type):
				n += 1
		var t: String = type
		var ty: Dictionary = Catalog.CITY_EVENTS if type == "city" else Catalog.EVENT_TYPES[type]
		var b := _button("%s  (%d)" % [ty["label"], n], func(): _show_events(t))
		b.focus_entered.connect(func(): info.text = ty["desc"])
	_button("< Zurück", _show_main)
	info.text = "Fahr, worauf du Lust hast. Rennsiege schalten schnelle Autos frei, Driftsiege die Driftautos.\nTempo-Stufe: %d %% (steigt mit jedem Sieg)" % int(GameState.pace() * 100.0)
	_focus_first()


## Orts-Strecken nur unter "Städte", nicht zusätzlich unter ihrer Art
func _in_list(r: Dictionary, type: String) -> bool:
	return r.has("city") if type == "city" else (r["type"] == type and not r.has("city"))


func _show_events(type: String) -> void:
	_clear_menu()
	_set_section(str(Catalog.CITY_EVENTS["label"] if type == "city" else Catalog.EVENT_TYPES[type]["label"]).to_upper())
	for i in Catalog.RACES.size():
		var r: Dictionary = Catalog.RACES[i]
		if not _in_list(r, type):
			continue
		var rt: String = r["type"]
		var txt: String = "%s  %s" % [r["name"], "*".repeat(r["tier"])]
		if GameState.best_times.has(r["name"]):
			var best: float = GameState.best_times[r["name"]]
			txt += "   " + ("%d Pkt" % int(best) if rt == "drift" else "%d:%05.2f" % [int(best) / 60, fmod(best, 60.0)])
		var idx := i
		var b := _button(txt, func(): _start_race(idx))
		var extra := ""
		if r.has("laps") and rt != "sprint":
			extra = "%d Runden. " % r["laps"]
		var desc: String = r.get("desc", Catalog.EVENT_TYPES[rt]["desc"])
		if r.has("city"):
			extra = Catalog.EVENT_TYPES[rt]["label"] + ". " + extra
		b.focus_entered.connect(func(): info.text = extra + desc)
	_button("< Zurück", _show_races)
	info.text = Catalog.CITY_EVENTS["desc"] if type == "city" else Catalog.EVENT_TYPES[type]["desc"]
	_focus_first()


func _start_race(i: int) -> void:
	GameState.race_index = i
	GameState.save_game()
	get_tree().change_scene_to_file("res://scenes/race.tscn")


func _show_tuning() -> void:
	_clear_menu()
	_set_section("TUNING", true)
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
		b.text = ("%s:  < %s >%s" % [Catalog.PARTS[cat]["label"], opt["name"], lock]).to_upper()


func _cycle_part(cat: String, dir: int) -> void:
	var n: int = Catalog.PARTS[cat]["options"].size()
	preview_cfg[cat] = posmod(preview_cfg[cat] + dir, n)
	if GameState.is_part_unlocked(cat, preview_cfg[cat]):
		GameState.get_config(preview_car)[cat] = preview_cfg[cat]
		GameState.save_game()
	_show_car(preview_car, preview_cfg)
	_show_stats(preview_car, preview_cfg)
	_refresh_tuning()
	_part_info(cat)


func _part_info(cat: String) -> void:
	var idx: int = preview_cfg[cat]
	var opt: Dictionary = Catalog.PARTS[cat]["options"][idx]
	if GameState.is_part_unlocked(cat, idx):
		info.text = "%s: %s\nLinks/Rechts zum Wechseln." % [Catalog.PARTS[cat]["label"], opt["name"]]
	else:
		var missing: int = opt["wins"] - GameState.total_wins()
		info.text = "%s ist gesperrt.\nNoch %d Sieg%s nötig. (Nur Vorschau)" % [opt["name"], missing, "" if missing == 1 else "e"]


func _show_cars() -> void:
	_clear_menu()
	_set_section("AUTOHAUS", true)
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
	menu.get_child(0).text = ("< %s >%s" % [spec["name"], "" if unlocked else "  [GESPERRT]"]).to_upper()
	_show_stats(preview_car, preview_cfg)
	menu.get_child(1).disabled = not unlocked
	info.text = spec["desc"] + "\nHöchstgeschwindigkeit ab Werk: %d km/h" % int(spec["top_speed"] * 3.6)
	if not unlocked:
		info.text += "\nFreischalten: " + GameState.unlock_text(preview_car)


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
	_set_section("ACHTUNG")
	info.text = "Alle Siege und Tuningteile gehen verloren. Wie beim TÜV: weg ist weg."
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
