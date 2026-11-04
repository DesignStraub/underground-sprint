extends Node3D
## Hauptmenü in der Garage: dein Auto dreht sich im Neonlicht, links das Menü.
## Tuning und Autowechsel zeigen gesperrte Teile als Vorschau, gespeichert wird nur Freigeschaltetes.

const Catalog := preload("res://scripts/catalog.gd")
const Builder := preload("res://scripts/car_builder.gd")
const PixelView := preload("res://scripts/pixel_view.gd")
const UI := preload("res://scripts/ui_style.gd")
const I18n := preload("res://scripts/i18n.gd")
const CareerMap := preload("res://scripts/career_map.gd")

## Tipps wie auf den Ladebildschirmen von NFS Underground
const TIPS := [
	"Zu schwer? Einstellungen > Schwierigkeit: Leicht. Dann lernst du die Strecken in Ruhe kennen.",
	"Gib kurz vor LOS Gas: Drehzahl im grünen Bereich gibt einen perfekten Start.",
	"Knapp am Verkehr vorbei füllt dein Nitro.",
	"Im Drag im grünen Bereich schalten: perfekter Schaltvorgang, mehr Schub.",
	"Abkürzungen sparen Zeit, aber dort kommt dir Verkehr entgegen.",
	"Handbremse und Lenken stellen das Auto quer. Drift-Ketten bringen Multiplikator.",
	"Siege schalten neue Teile und Autos frei.",
	"Spar dir Nitro für die letzte Gerade.",
	"Über die Rampe am Bahnübergang springst du über die Gleise.",
	"Motor-Tuning steigert Beschleunigung und Höchstgeschwindigkeit.",
	"Im Drag nicht im Begrenzer bleiben: der Motor überhitzt.",
]

var world: SubViewport
var turntable: Node3D
var car_node: Node3D
var cam: Camera3D
var menu: VBoxContainer
var menu_scroll: ScrollContainer  # lange Listen (Karriere) scrollen mit dem Fokus mit
var career_map: Control
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
	if GameState.language == "":
		_show_language(true)  # erster Start: Sprache wählen (Englisch vorausgewählt)
	else:
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
	env.glow_intensity = 1.0
	env.glow_hdr_threshold = 0.9
	var apply_gfx := func():
		env.glow_enabled = GameState.gv("bloom")
		env.ssr_enabled = GameState.gfx_available("ssr") and GameState.gv("ssr") > 0
	apply_gfx.call()
	GameState.graphics_changed.connect(apply_gfx)
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
	_work_light = OmniLight3D.new()
	_work_light.light_color = Color(1.0, 0.95, 0.88)
	_work_light.light_energy = 0.0
	_work_light.omni_range = 5.0
	_work_light.position = Vector3(0.3, 0.3, 0.0)
	cam.add_child(_work_light)
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

	menu_scroll = ScrollContainer.new()
	menu_scroll.anchor_bottom = 1.0
	menu_scroll.offset_left = 14.0
	menu_scroll.offset_right = 262.0
	menu_scroll.offset_top = 86.0
	menu_scroll.offset_bottom = -24.0
	menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	menu_scroll.follow_focus = true
	root.add_child(menu_scroll)
	menu = VBoxContainer.new()
	menu.custom_minimum_size = Vector2(226, 0)
	menu.add_theme_constant_override("separation", 3)
	menu_scroll.add_child(menu)

	# Streckenkarte rechts (nur in der Karriere-Liste)
	career_map = CareerMap.new()
	career_map.anchor_left = 1.0
	career_map.anchor_right = 1.0
	career_map.anchor_bottom = 1.0
	career_map.offset_left = -196.0
	career_map.offset_right = -14.0
	career_map.offset_top = 46.0
	career_map.offset_bottom = -100.0
	career_map.visible = false
	root.add_child(career_map)

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
	keys.text = tr("ENTER  Auswählen      ESC  Zurück      ←/→ A/D  Ändern      F11  Vollbild")
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
	tip.text = tr("TIPP: ") + tr(TIPS[_tip_i])


## Leistungsbalken wie im Autohaus (10 Segmente), Motor-Tuning eingerechnet
func _show_stats(car_id: String, cfg: Dictionary, base := {}) -> void:
	for c in stats.get_children():
		c.queue_free()
	var st := Catalog.stats(car_id, cfg)
	var bs := Catalog.stats(car_id, base if not base.is_empty() else cfg)
	var head := _label(stats, 10, HORIZONTAL_ALIGNMENT_RIGHT)
	head.label_settings.font = UI.font("cond", 0.2)
	head.label_settings.font_color = UI.GREEN
	head.text = tr("LEISTUNG")
	for row in [["BESCHLEUNIGUNG", "accel", 9.0, 17.0], ["TOPSPEED", "top", 54.0, 90.0], ["GRIP", "grip", 19.0, 38.0],
			["DRIFT", "drift", 0.0, 1.0]]:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 2)
		stats.add_child(hb)
		var l := _label(hb, 8)
		l.label_settings.font = UI.font("bold", 0.12)
		l.text = tr(row[0])
		l.custom_minimum_size = Vector2(76, 0)
		var n := int(round(clampf((st[row[1]] - row[2]) / (row[3] - row[2]), 0.05, 1.0) * 10.0))
		var n0 := int(round(clampf((bs[row[1]] - row[2]) / (row[3] - row[2]), 0.05, 1.0) * 10.0))
		for k in 10:
			var seg := ColorRect.new()
			seg.custom_minimum_size = Vector2(11, 6)
			seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			if k < mini(n, n0):
				seg.color = UI.GREEN
			elif k < n:
				seg.color = UI.CYAN  # Gewinn durch das Teil in der Vorschau
			elif k < n0:
				seg.color = Color(1.0, 0.25, 0.2, 0.8)  # Verlust
			else:
				seg.color = Color(1, 1, 1, 0.12)
			hb.add_child(seg)
	var top := _label(stats, 8, HORIZONTAL_ALIGNMENT_RIGHT)
	top.label_settings.font = UI.font("bold", 0.12)
	top.label_settings.font_color = UI.CYAN
	top.text = "%d KM/H" % int(st["top"] * 3.6)


func _set_section(text: String, with_stats := false) -> void:
	section.text = tr(text)
	stats.get_parent().visible = with_stats
	if with_stats:
		_show_stats(preview_car, preview_cfg)


var _music_label: Label
var _cam_view := ""  # "" = Drehteller kreist, sonst Kategorie, deren Teil die Kamera zeigt
var _cam_pos := Vector3(4.6, 1.7, 5.6)
var _cam_look := Vector3(-1.6, 0.55, 0)
var _work_light: OmniLight3D  # Arbeitslicht an der Kamera für Nahaufnahmen (Felgen, Motor)


## Kamerapunkt und Blickziel je Tuning-Kategorie (Auto in Grundstellung: vorn -Z, rechte Seite +X)
func _view_for(cat: String) -> Array:
	var spec: Dictionary = Catalog.CARS[preview_car]
	var L: float = spec["length"]
	var W: float = spec["width"]
	var fz := -(L / 2.0 - 0.78)
	match cat:
		"paint":
			return [Vector3(3.4, 1.35, -3.4), Vector3(0.2, 0.55, 0.0)]
		"rims", "tires":
			return [Vector3(W / 2.0 + 1.3, 0.45, fz - 0.9), Vector3(W / 2.0, 0.32, fz)]
		"suspension":
			return [Vector3(W / 2.0 + 1.6, 0.55, fz - 0.6), Vector3(W / 2.0 - 0.1, 0.42, fz + 0.1)]
		"spoiler":
			return [Vector3(1.7, 1.55, L / 2.0 + 1.7), Vector3(0.0, 0.95, L / 2.0 - 0.35)]
		"bodykit":
			return [Vector3(3.2, 0.55, -2.6), Vector3(0.2, 0.35, -0.3)]
		"vinyl":
			return [Vector3(4.4, 1.1, 0.2), Vector3(0.0, 0.6, 0.0)]
		"neon":
			return [Vector3(3.3, 0.32, -1.6), Vector3(0.0, 0.05, 0.0)]
		"tint":
			return [Vector3(2.8, 1.45, -2.2), Vector3(0.0, 1.0, -0.2)]
		"engine", "turbo":
			return [Vector3(1.3, 1.95, -L / 2.0 - 1.4), Vector3(0.0, 0.8, -L / 2.0 + 0.85)]
		"nitro":
			return [Vector3(1.3, 1.95, L / 2.0 + 1.4), Vector3(0.0, 0.85, L / 2.0 - 0.6)]
	return [Vector3(3.6, 1.6, -4.0), Vector3(0.0, 0.6, 0.0)]


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
		tip.text = tr("TIPP: ") + tr(TIPS[_tip_i])
	var goal_pos := Vector3(4.6 + sin(_t * 0.2) * 0.2, 1.7 + sin(_t * 0.3) * 0.08, 5.6)
	var goal_look := Vector3(-1.6, 0.55, 0)
	var goal_off := 0.0
	if _cam_view == "":
		turntable.rotation.y += dt * 0.3
	else:
		# Tuning: Auto dreht in Grundstellung, Kamera fährt an das Teil heran (Ziel rechts vom Menü)
		turntable.rotation.y = lerp_angle(turntable.rotation.y, 0.0, 1.0 - exp(-dt * 4.0))
		var v := _view_for(_cam_view)
		goal_pos = v[0] + Vector3(0, sin(_t * 0.4) * 0.02, 0)
		goal_look = v[1]
		goal_off = -0.2 * goal_pos.distance_to(goal_look)
	var k := 1.0 - exp(-dt * 3.5)
	_cam_pos = _cam_pos.lerp(goal_pos, k)
	_cam_look = _cam_look.lerp(goal_look, k)
	cam.h_offset = lerpf(cam.h_offset, goal_off, k)
	cam.position = _cam_pos
	cam.look_at(_cam_look)
	_work_light.light_energy = lerpf(_work_light.light_energy, 0.0 if _cam_view == "" else 1.4, k)
	status.text = tr("RENNSIEGE %d   ·   DRIFTSIEGE %d   ·   %s") % [GameState.wins, GameState.drift_wins, Catalog.CARS[GameState.current_car]["name"].to_upper()]
	_music_label.text = (tr("Musik: ") + Music.current_title) if Music.current_title != "" else tr("Keine Musik: mp3/ogg in music/ legen")


func _show_car(car_id: String, cfg: Dictionary) -> void:
	if car_node:
		car_node.queue_free()
	car_node = Builder.build(car_id, cfg, false, false)
	turntable.add_child(car_node)
	car_node.position.y = 0.06


# --- Menüs ----------------------------------------------------------------

func _clear_menu() -> void:
	career_map.visible = false
	menu_scroll.scroll_vertical = 0
	for c in menu.get_children():
		menu.remove_child(c)
		c.queue_free()


func _button(text: String, cb: Callable, disabled := false) -> Button:
	var b := Button.new()
	b.text = tr(text).to_upper()
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = disabled
	b.focus_entered.connect(func(): Sfx.play("whoosh", -26.0, 2.4))
	b.pressed.connect(cb)
	menu.add_child(b)
	return b


func _focus_first() -> void:
	menu.modulate.a = 0.0
	menu_scroll.position.x = -24.0
	section.modulate.a = 0.0
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(menu_scroll, "position:x", 14.0, 0.18)
	tw.tween_property(menu, "modulate:a", 1.0, 0.18)
	tw.tween_property(section, "modulate:a", 1.0, 0.25)
	for c in menu.get_children():
		if c is Button and not c.disabled:
			c.grab_focus.call_deferred()
			return


func _show_main() -> void:
	_clear_menu()
	_cam_view = ""
	preview_car = GameState.current_car
	preview_cfg = GameState.get_config(preview_car).duplicate()
	_show_car(preview_car, preview_cfg)
	_set_section("GARAGE", true)
	_button("Rennen fahren", _show_races)
	_button("Tuning", _show_tuning)
	_button("Auto wechseln", _show_cars)
	_button("Einstellungen", _show_settings)
	if not OS.has_feature("web"):  # im Browser schließt man einfach den Tab
		_button("Beenden", func(): get_tree().quit())
	info.text = tr(Catalog.CARS[preview_car]["desc"]) + "\nF / F11: " + tr("Vollbild")
	_focus_first()


## Erklärung je Einstellung (unten im Infofeld)
const SETTING_HINTS := {
	"graphics": "Grafik wie in großen PC-Spielen: Voreinstellung wählen oder jede Option einzeln anpassen.",
	"preset": "Niedrig: für Handy, Tablet und schwache Rechner. Mittel: ausgewogen. Hoch und Ultra: für starke Grafikkarten. Links/Rechts wechselt.",
	"res": "Höchste Auflösung der 3D-Welt, darüber wird weich hochskaliert. Größter Hebel für die Bildrate.",
	"dynres": "Senkt die 3D-Auflösung automatisch, wenn die Bildrate unter 60 fällt, und hebt sie danach wieder an.",
	"view": "Wie weit du siehst. Weiter = mehr Häuser und Wahrzeichen im Bild, kostet Leistung.",
	"detail": "Ab welcher Entfernung Kleinteile verschwinden und Autos vereinfacht gezeichnet werden.",
	"lights": "Bis zu welcher Entfernung Laternen und Leuchtreklamen die Straße beleuchten.",
	"aa": "Glättet Treppchen an Kanten. MSAA ist schärfer, kostet aber mehr.",
	"bloom": "Leuchtreklamen, Scheinwerfer und Neon strahlen über.",
	"ssr": "Spiegelungen auf nasser Straße. Teuer.",
	"ssao": "Weiche Schatten in Ecken und unter Autos. Teuer.",
	"fx": "Regen, Dampf aus Gullys und andere Partikel.",
	"pixel": "Pixel-Look: die 3D-Welt grob gerastert wie ein Retro-Spiel. Spart zusätzlich Leistung.",
	"vsync": "V-Sync: kein Bildreißen. Aus = mehr FPS, aber evtl. Tearing.",
	"fps": "FPS-Limit: begrenzt die Bildrate (schont Akku und Lüfter).",
	"show_fps": "Zeigt oben in der Mitte Bildrate und aktuelle 3D-Auflösung.",
	"fullscreen": "Vollbild (auch F / F11).",
	"language": "Sprache des Spiels. Titel, Orte und Schilder bleiben deutsch.",
	"touch": "Touch-Knöpfe im Rennen. Auto: nur auf Handy und Tablet.",
	"difficulty": "Wie stark die Gegner fahren. Leicht: zum Kennenlernen der Strecken. Schwer: schnellere Autos, und wer führt, wird gejagt.",
	"jumpcam": "Bei hohen Sprüngen schaut eine Kamera schräg von vorn zu, wie in NFS Underground, dazu Zeitlupe.",
}


## Grafik, Vollbild, Spielstand: nicht auf der Startseite, sondern gesammelt hier
func _show_settings() -> void:
	_clear_menu()
	_set_section("EINSTELLUNGEN")
	var g := _button("Grafik  >", _show_graphics)
	g.focus_entered.connect(func(): info.text = tr(SETTING_HINTS["graphics"]))
	for key in ["language", "difficulty", "jumpcam", "show_fps", "vsync", "fps", "fullscreen", "touch"]:
		_setting_button(key)
	_button("Spielstand zurücksetzen", _confirm_reset)
	_button("< Zurück", _show_main)
	info.text = tr(SETTING_HINTS["graphics"])
	_focus_first()


## Grafikmenü: Voreinstellung oben, darunter jede Option einzeln (Links/Rechts oder Klick schaltet um).
## Optionen, die der Browser-Renderer nicht kann (Spiegelungen, Umgebungsverdeckung), fehlen dort.
func _show_graphics() -> void:
	_clear_menu()
	_set_section("GRAFIK")
	for key in ["preset"] + GameState.GFX_ORDER.filter(GameState.gfx_available) + ["pixel"]:
		_setting_button(key)
	_button("< Zurück", _show_settings)
	info.text = tr(SETTING_HINTS["preset"])
	_focus_first()


func _setting_button(k: String) -> Button:
	var b := _button(GameState.setting_text(k), func(): pass)
	b.set_meta("setting", k)
	var change := func(dir: int):
		if k == "language":
			_show_language(false)
			return
		if k == "fullscreen":
			GameState.toggle_fullscreen()
		else:
			GameState.cycle_setting(k, dir)
		Sfx.play("whoosh", -22.0, 1.6)
		# Voreinstellung ändert alle Optionen, eine Option ggf. die Voreinstellung: alle Texte neu
		for c in menu.get_children():
			if c.has_meta("setting"):
				c.text = GameState.setting_text(c.get_meta("setting")).to_upper()
	b.pressed.connect(change.bind(1))
	if k != "language":
		b.gui_input.connect(func(ev): _lr_input(ev, change))
	b.focus_entered.connect(func(): info.text = tr(SETTING_HINTS[k]))
	return b


## Karriere wie in NFS: alle Events der Reihe nach, ein Sieg öffnet das nächste. Rechts die Deutschlandkarte.
func _show_races() -> void:
	_clear_menu()
	_set_section("KARRIERE")
	career_map.visible = true
	var last_open := 0
	for i in Catalog.CAREER.size():
		var ev: String = Catalog.CAREER[i]
		var ri := Catalog.race_index(ev)
		var r: Dictionary = Catalog.RACES[ri]
		var open := GameState.career_unlocked(i)
		var txt := "%02d  %s  %s" % [i + 1, tr(ev), "*".repeat(r["tier"])]
		if GameState.best_times.has(ev):
			var best: float = GameState.best_times[ev]
			txt += "   " + ("%d P" % int(best) if r["type"] == "drift" else "%d:%05.2f" % [int(best) / 60, fmod(best, 60.0)])
		var idx := i
		var b := _button(txt, func():
			if GameState.career_unlocked(idx):
				_start_race(ri)
			else:
				Sfx.play("thud", -14.0, 1.3))
		if not open:
			b.modulate = Color(1, 1, 1, 0.38)
		else:
			last_open = i
		b.focus_entered.connect(func():
			career_map.selected = ev
			info.text = _career_info(idx))
	_button("< Zurück", _show_main)
	_focus_first()
	var target: Control = menu.get_child(last_open)
	target.grab_focus.call_deferred()
	# erst wenn die Liste ausgelegt ist, stimmt die Position: dann zum offenen Event scrollen
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(target) and target.is_inside_tree():
		menu_scroll.ensure_control_visible(target)


func _career_info(i: int) -> String:
	var r: Dictionary = Catalog.RACES[Catalog.race_index(Catalog.CAREER[i])]
	var rt: String = r["type"]
	var head := "%s  ·  %s" % [r.get("town", ""), tr(Catalog.EVENT_TYPES[rt]["label"])]
	if r.has("laps") and rt != "sprint":
		head += "  ·  " + tr("%d Runden. ") % r["laps"]
	var t := head + "\n" + tr(r.get("desc", Catalog.EVENT_TYPES[rt]["desc"]))
	if not GameState.career_unlocked(i):
		t = head + "\n" + tr("Gesperrt: gewinne zuerst %s.") % tr(Catalog.CAREER[i - 1])
	elif Catalog.CAREER[i] in GameState.won_events:
		t += "\n" + tr("Gewonnen")
	return t


## Orts-Strecken nur unter "Städte", nicht zusätzlich unter ihrer Art
func _in_list(r: Dictionary, type: String) -> bool:
	return r.has("city") if type == "city" else (r["type"] == type and not r.has("city"))


func _show_events(type: String) -> void:
	_clear_menu()
	section.text = tr(str(Catalog.CITY_EVENTS["label"] if type == "city" else Catalog.EVENT_TYPES[type]["label"])).to_upper()
	stats.get_parent().visible = false
	for i in Catalog.RACES.size():
		var r: Dictionary = Catalog.RACES[i]
		if not _in_list(r, type):
			continue
		var rt: String = r["type"]
		var txt: String = "%s  %s" % [tr(r["name"]), "*".repeat(r["tier"])]
		if GameState.best_times.has(r["name"]):
			var best: float = GameState.best_times[r["name"]]
			txt += "   " + ("%d P" % int(best) if rt == "drift" else "%d:%05.2f" % [int(best) / 60, fmod(best, 60.0)])
		var idx := i
		var b := _button(txt, func(): _start_race(idx))
		var extra := ""
		if r.has("laps") and rt != "sprint":
			extra = tr("%d Runden. ") % r["laps"]
		var desc: String = tr(r.get("desc", Catalog.EVENT_TYPES[rt]["desc"]))
		if r.has("city"):
			extra = tr(Catalog.EVENT_TYPES[rt]["label"]) + ". " + extra
		b.focus_entered.connect(func(): info.text = extra + desc)
	_button("< Zurück", _show_races)
	info.text = tr(Catalog.CITY_EVENTS["desc"] if type == "city" else Catalog.EVENT_TYPES[type]["desc"])
	_focus_first()


func _start_race(i: int) -> void:
	GameState.race_index = i
	GameState.save_game()
	get_tree().change_scene_to_file("res://scenes/race.tscn")


func _show_tuning() -> void:
	_clear_menu()
	_cam_view = ""
	preview_cfg = GameState.get_config(preview_car).duplicate()
	_show_car(preview_car, preview_cfg)
	_set_section("TUNING", true)
	var bo := _button("Optik", func(): _show_group("optik"))
	bo.focus_entered.connect(func(): info.text = tr("Lack, Felgen, Spoiler, Bodykit, Folierung, Unterbodenneon, Scheiben."))
	var bl := _button("Leistung", func(): _show_group("leistung"))
	bl.focus_entered.connect(func(): info.text = tr("Motor, Turbo, Nitro, Fahrwerk, Reifen. Wirkt wirklich auf das Fahrverhalten."))
	_button("< Fertig", func(): _cam_view = ""; _show_main())
	_focus_first()


## Kategorien einer Gruppe, rechts daneben jeweils das eingebaute Teil
func _show_group(group: String) -> void:
	_clear_menu()
	preview_cfg = GameState.get_config(preview_car).duplicate()
	_show_car(preview_car, preview_cfg)
	_set_section("OPTIK" if group == "optik" else "LEISTUNG", group == "leistung")
	for cat in Catalog.PART_GROUPS[group]:
		var c: String = cat
		var opt := Catalog.part_of(preview_cfg, c)
		var b := _button("%s:  %s" % [tr(Catalog.PARTS[c]["label"]), tr(opt["name"])], func(): _show_parts(c, group))
		b.focus_entered.connect(func():
			_cam_view = c
			Builder.showcase(car_node, preview_car, preview_cfg, _showcase_mode(c))
			info.text = tr(Catalog.PARTS[c]["label"]) + ": " + tr(opt["name"]))
	_button("< Zurück", _show_tuning)
	_focus_first()


func _showcase_mode(cat: String) -> String:
	if cat == "engine" or cat == "turbo":
		return "engine"
	if cat == "nitro":
		return "nitro"
	return ""


## Teile einer Kategorie: Vorschau beim Auswählen, Einbauen mit Enter (wenn freigeschaltet)
func _show_parts(cat: String, group: String) -> void:
	_clear_menu()
	_cam_view = cat
	section.text = tr(Catalog.PARTS[cat]["label"]).to_upper()
	stats.get_parent().visible = group == "leistung"  # Optik-Teile ändern keine Fahrwerte: Balken weg, Auto frei
	var installed: int = GameState.get_config(preview_car).get(cat, 0)
	var opts: Array = Catalog.PARTS[cat]["options"]
	for i in opts.size():
		var idx := i
		var b := _button("", func(): _install(cat, idx, group))
		b.set_meta("part", idx)
		b.focus_entered.connect(func(): _preview_part(cat, idx))
	_button("< Zurück", func(): _show_group(group))
	_refresh_parts(cat)
	_focus_first()
	# Fokus auf das eingebaute Teil
	if installed > 0 and installed < menu.get_child_count():
		menu.get_child(installed).grab_focus.call_deferred()


func _refresh_parts(cat: String) -> void:
	var installed: int = GameState.get_config(preview_car).get(cat, 0)
	for b in menu.get_children():
		if not b.has_meta("part"):
			continue
		var i: int = b.get_meta("part")
		var opt: Dictionary = Catalog.PARTS[cat]["options"][i]
		var suffix := ""
		if i == installed:
			suffix = "   " + tr("EINGEBAUT")
		elif not GameState.is_part_unlocked(cat, i):
			suffix = "   " + (tr("1 SIEG") if opt["wins"] == 1 else tr("%d SIEGE") % opt["wins"])
		b.text = (tr(opt["name"]) + suffix).to_upper()


func _preview_part(cat: String, idx: int) -> void:
	var base := GameState.get_config(preview_car).duplicate()
	preview_cfg = base.duplicate()
	preview_cfg[cat] = idx
	_show_car(preview_car, preview_cfg)
	Builder.showcase(car_node, preview_car, preview_cfg, _showcase_mode(cat))
	_show_stats(preview_car, preview_cfg, base)
	_part_info(cat, idx)


func _install(cat: String, idx: int, group: String) -> void:
	if not GameState.is_part_unlocked(cat, idx):
		Sfx.play("thud", -14.0, 1.3)
		return
	GameState.get_config(preview_car)[cat] = idx
	GameState.save_game()
	Sfx.play("clang", -16.0, 1.6)
	_refresh_parts(cat)
	_show_stats(preview_car, preview_cfg, GameState.get_config(preview_car))
	_part_info(cat, idx)


## Wirkung des Teils in Zahlen (wie die Werte im NFS-Tuning)
func _part_info(cat: String, idx: int) -> void:
	var opt: Dictionary = Catalog.PARTS[cat]["options"][idx]
	var t := tr(Catalog.PARTS[cat]["label"]) + ": " + tr(opt["name"])
	match cat:
		"engine", "turbo":
			t += "\n" + tr("Beschleunigung +%d %%   ·   Topspeed +%d %%") % [roundi((opt["accel"] - 1.0) * 100.0), roundi((opt["top"] - 1.0) * 100.0)]
		"nitro":
			t += "\n" + tr("Nitro-Schub +%d %%   ·   Füllung +%d %%") % [roundi((opt["power"] - 1.0) * 100.0), roundi((opt["capacity"] - 1.0) * 100.0)]
		"suspension":
			t += "\n" + tr("Grip +%d %%   ·   Lenkung +%d %%   ·   %d mm tiefer") % [roundi(opt["grip"] / Catalog.CARS[preview_car]["grip"] * 100.0),
				roundi(opt["steer"] / Catalog.CARS[preview_car]["steer"] * 100.0), roundi(opt["drop"] * 1000.0)]
		"tires":
			t += "\n" + tr("Grip +%d %%") % roundi(opt["grip"] / Catalog.CARS[preview_car]["grip"] * 100.0)
	if not GameState.is_part_unlocked(cat, idx):
		var missing: int = opt["wins"] - GameState.total_wins()
		t += "\n" + (tr("Gesperrt: noch 1 Sieg nötig.") if missing == 1 else tr("Gesperrt: noch %d Siege nötig.") % missing)
	elif idx != GameState.get_config(preview_car).get(cat, 0):
		t += "\n" + tr("ENTER: einbauen")
	info.text = t


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
	menu.get_child(0).text = ("< %s >%s" % [spec["name"], "" if unlocked else tr("  [GESPERRT]")]).to_upper()
	_show_stats(preview_car, preview_cfg)
	menu.get_child(1).disabled = not unlocked
	info.text = tr(spec["desc"]) + tr("\nHöchstgeschwindigkeit ab Werk: %d km/h") % int(spec["top_speed"] * 3.6)
	if not unlocked:
		info.text += tr("\nFreischalten: ") + GameState.unlock_text(preview_car)


func _stars(v: float, lo: float, hi: float) -> String:
	var n := int(round(clampf((v - lo) / (hi - lo), 0.0, 1.0) * 4.0)) + 1
	return "#".repeat(n) + ".".repeat(5 - n)


func _choose_car() -> void:
	if GameState.is_car_unlocked(preview_car):
		GameState.current_car = preview_car
		GameState.save_game()
		_show_main()


## Sprachwahl (erster Start und Einstellungen). Englisch steht oben und ist vorausgewählt.
func _show_language(first: bool) -> void:
	_clear_menu()
	section.text = "LANGUAGE · SPRACHE"
	stats.get_parent().visible = false
	for lang in I18n.LANGS:
		var l: String = lang
		var b := Button.new()
		b.text = I18n.NAMES[l].to_upper()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.focus_entered.connect(func(): Sfx.play("whoosh", -26.0, 2.4))
		b.pressed.connect(func():
			GameState.set_language(l)
			get_tree().reload_current_scene())  # alle Texte neu in der gewählten Sprache
		menu.add_child(b)
	if not first:
		_button("< Zurück", _show_settings)
	info.text = "Choose your language. Title, places and signs stay German.\nWähle deine Sprache. Titel, Orte und Schilder bleiben deutsch."
	_focus_first()
	if not first and GameState.language == "de":
		menu.get_child(1).grab_focus.call_deferred()


func _confirm_reset() -> void:
	_clear_menu()
	_set_section("ACHTUNG")
	info.text = tr("Alle Siege und Tuningteile gehen verloren.")
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
	if event.is_action_pressed("ui_cancel") and GameState.language != "":
		_show_main()
