extends Node3D
## Hauptmenü in der Garage: dein Auto dreht sich im Neonlicht, links das Menü.
## Tuning und Autowechsel zeigen gesperrte Teile als Vorschau, gespeichert wird nur Freigeschaltetes.

const Catalog := preload("res://scripts/catalog.gd")
const Builder := preload("res://scripts/car_builder.gd")
const PixelView := preload("res://scripts/pixel_view.gd")
const UI := preload("res://scripts/ui_style.gd")
const I18n := preload("res://scripts/i18n.gd")
const CareerMap := preload("res://scripts/career_map.gd")

const Loading := preload("res://scripts/loading_screen.gd")
## Tipps wie auf den Ladebildschirmen von NFS Underground (stehen beim Ladebildschirm)
const TIPS := Loading.TIPS

var world: SubViewport
var turntable: Node3D
var car_node: Node3D
var cam: Camera3D
var menu: VBoxContainer
var menu_scroll: ScrollContainer  # lange Listen (Karriere) scrollen mit dem Fokus mit
var career_map: Control
## Tuning wie in NFS Underground: waagerechte Leiste unten statt der Liste links
var strip: Control
var strip_box: HBoxContainer
var _strip_mode := false
var _fade_left: TextureRect
var _info_panel: PanelContainer
var _keys: Label
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
## Rücktaste/Esc: eine Ebene zurück wie in NFS (jedes Menü setzt, wohin es zurückgeht; leer = Hauptmenü)
var _back := Callable()


func _ready() -> void:
	Music.toast_corner = true
	Music.menu()
	_build_scene()
	_build_ui()
	if GameState.language == "":
		_show_language(true)  # erster Start: Sprache wählen (Englisch vorausgewählt)
	else:
		_show_main()


func _build_scene() -> void:
	Builder.street = {}  # Lichtkarte der letzten Strecke gilt hier nicht
	var view_layer := CanvasLayer.new()
	view_layer.layer = -1
	add_child(view_layer)
	var pv := PixelView.new()
	pv.showroom = true
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
	# Spiegelungen: ohne sie spiegelt der Lack nur das Schwarz der Halle, Glanz und Matt sähen gleich aus.
	# Ein unsichtbarer Studio-Himmel (Lichtbänder an der Decke, Neonröhren) steht nur im Lack und im Boden.
	var sky_m := ShaderMaterial.new()
	sky_m.shader = preload("res://shaders/studio_sky.gdshader")
	env.sky = Sky.new()
	env.sky.sky_material = sky_m
	env.sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
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
	_fade_left = fade
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
	_info_panel = panel
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

	# Tuning-Leiste unten (Kacheln, die gewählte steht in der Mitte); Verlauf dahinter, damit sie vor dem Auto lesbar ist
	strip = Control.new()
	strip.anchor_top = 1.0
	strip.anchor_bottom = 1.0
	strip.anchor_right = 1.0
	strip.offset_top = -86.0
	strip.offset_bottom = -24.0
	strip.clip_contents = true
	strip.visible = false
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(strip)
	var sfade := UI.fade_rect(strip, Color(0, 0, 0, 0.75), false)
	sfade.set_anchors_preset(Control.PRESET_FULL_RECT)
	sfade.flip_v = true
	strip_box = HBoxContainer.new()
	strip_box.add_theme_constant_override("separation", 8)
	strip_box.position = Vector2(0, 8)
	strip.add_child(strip_box)
	for side in [-1, 1]:
		var arrow := _label(strip, 16, HORIZONTAL_ALIGNMENT_CENTER)
		arrow.text = "◀" if side < 0 else "▶"
		arrow.label_settings.font_color = UI.GREEN
		arrow.anchor_left = 0.0 if side < 0 else 1.0
		arrow.anchor_right = arrow.anchor_left
		arrow.offset_left = 2.0 if side < 0 else -20.0
		arrow.offset_right = 20.0 if side < 0 else -2.0
		arrow.offset_top = 20.0
		arrow.set_meta("arrow", side)

	var keys := _label(root, 9)
	_keys = keys
	keys.label_settings.font = UI.font("bold", 0.12)
	keys.text = tr("ENTER  Auswählen      ESC  Zurück      ←/→ A/D  Ändern      F11  Vollbild")
	keys.anchor_top = 1.0
	keys.anchor_bottom = 1.0
	keys.offset_left = 14.0
	keys.offset_top = -16.0
	keys.offset_right = 400.0
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
	# Klasse und Leistungsindex: zeigt, dass die Autos der Klasse S gleich stark sind; Tuning-Vorschau mit Zuwachs
	var pi := Catalog.rating(car_id, cfg)
	var pi0 := Catalog.rating(car_id, base if not base.is_empty() else cfg)
	head.text = tr("KLASSE %s  ·  LEISTUNG %d") % [Catalog.CARS[car_id].get("class", "-"), pi]
	if pi != pi0:
		head.text += "  (%+d)" % (pi - pi0)
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


var _cam_view := ""  # "" = Drehteller kreist, sonst Kategorie, deren Teil die Kamera zeigt
var _cam_pos := Vector3(4.6, 1.7, 5.6)
var _cam_look := Vector3(-1.6, 0.55, 0)
var _work_light: OmniLight3D  # Arbeitslicht an der Kamera für Nahaufnahmen (Felgen, Motor)


## Kamerapunkt und Blickziel je Tuning-Kategorie (Auto in Grundstellung: vorn -Z, rechte Seite +X)
func _view_for(cat: String) -> Array:
	var spec: Dictionary = Catalog.CARS[preview_car]
	var L: float = spec["length"]
	var W: float = spec["width"]
	var fz := -(L / 2.0 - Builder.axle(Builder.SHAPES.get(preview_car, {})))
	# Mittelmotor: Motor hinten, Kofferraum (Nitro) vorn
	if Builder.engine_rear(Builder.SHAPES.get(preview_car, {})) and cat in ["engine", "turbo", "nitro"]:
		cat = "nitro" if cat != "nitro" else "engine"
	match cat:
		"paint":
			return [Vector3(3.4, 1.35, -3.4), Vector3(0.2, 0.55, 0.0)]
		"finish":
			return [Vector3(4.1, 1.65, -3.8), Vector3(0.0, 0.55, 0.25)]
		"rims", "rimcol", "rimsize", "tires":
			return [Vector3(W / 2.0 + 1.3, 0.45, fz - 0.9), Vector3(W / 2.0, 0.32, fz)]
		"suspension":
			return [Vector3(W / 2.0 + 1.6, 0.55, fz - 0.6), Vector3(W / 2.0 - 0.1, 0.42, fz + 0.1)]
		"spoiler":
			return [Vector3(1.7, 1.55, L / 2.0 + 1.7), Vector3(0.0, 0.95, L / 2.0 - 0.35)]
		"bodykit":
			return [Vector3(3.2, 0.55, -2.6), Vector3(0.2, 0.35, -0.3)]
		"vinyl", "vinylcol":
			return [Vector3(4.0, 2.0, -1.6), Vector3(0.0, 0.6, 0.0)]
		"hood":
			return [Vector3(1.6, 1.9, -L / 2.0 - 1.9), Vector3(0.0, 0.75, -L / 2.0 + 1.0)]
		"exhaust":
			return [Vector3(1.4, 0.6, L / 2.0 + 1.6), Vector3(0.0, 0.3, L / 2.0)]
		"lights":
			return [Vector3(2.0, 0.9, -L / 2.0 - 2.6), Vector3(0.0, 0.5, -L / 2.0)]
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
	var goal_v := 0.0
	if _strip_mode:
		# Leiste unten: Auto mittig und etwas höher im Bild
		goal_off = 0.0
		goal_v = -0.1 * goal_pos.distance_to(goal_look)
	var k := 1.0 - exp(-dt * 3.5)
	_cam_pos = _cam_pos.lerp(goal_pos, k)
	_cam_look = _cam_look.lerp(goal_look, k)
	cam.h_offset = lerpf(cam.h_offset, goal_off, k)
	cam.v_offset = lerpf(cam.v_offset, goal_v, k)
	cam.position = _cam_pos
	cam.look_at(_cam_look)
	_work_light.light_energy = lerpf(_work_light.light_energy, 0.0 if _cam_view == "" else 1.4, k)
	status.text = tr("RENNSIEGE %d   ·   DRIFTSIEGE %d   ·   %s") % [GameState.wins, GameState.drift_wins, Catalog.CARS[GameState.current_car]["name"].to_upper()]


func _show_car(car_id: String, cfg: Dictionary) -> void:
	if car_node:
		car_node.queue_free()
	car_node = Builder.build(car_id, cfg, false, false)
	turntable.add_child(car_node)
	car_node.position.y = 0.06


# --- Menüs ----------------------------------------------------------------

func _clear_menu() -> void:
	_strip_on(false)
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
	b.focus_entered.connect(func(): Sfx.ui("move"))
	b.pressed.connect(func(): _press_sound(b))
	b.pressed.connect(cb)
	menu.add_child(b)
	return b


## Fokus setzen, falls der Knopf noch da ist (Menüs wechseln manchmal im selben Bild)
func _grab(c: Control) -> void:
	if is_instance_valid(c) and c.is_inside_tree():
		c.grab_focus()


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
			_grab.call_deferred(c)
			return


func _show_main() -> void:
	_clear_menu()
	_back = Callable()
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
	if not GameState.save_persistent():
		info.text = tr("Achtung: Dein Browser speichert hier keinen Spielstand. Öffne das Spiel über den Knopf oben rechts in einem eigenen Tab, dann bleibt dein Fortschritt erhalten.") + "\n\n" + info.text
	_focus_first()


const CREDITS_TEXT := "Motorklänge aus echten Aufnahmen (Wikimedia Commons, CC BY 3.0/4.0): prone, Y Racing, Tyler Riddle, Great Explorer, NEW CARS 2015 Official, Fabio Rojas Pichardo, Taz Ringer, asTUBE, Super Cars for you, Work With Sounds / Technisches Museum Slowenien. Reifenquietschen: Joseph Sardin, BigSoundBank (CC0). Bahnübergang: Renardo la vulpo (CC0), Work With Sounds / Konrad Gutkowski (CC BY 4.0), Extemporalist (CC0). Musik: Pixabay. Schrift: D-DIN (Datto, OFL). Karten © OpenStreetMap-Mitwirkende."

## Erklärung je Einstellung (unten im Infofeld)
const SETTING_HINTS := {
	"graphics": "Grafik wie in großen PC-Spielen: Voreinstellung wählen oder jede Option einzeln anpassen.",
	"preset": "Niedrig: für Handy, Tablet und schwache Rechner. Mittel: ausgewogen. Hoch und Ultra: für starke Grafikkarten. Links/Rechts wechselt.",
	"res": "Höchste Auflösung der 3D-Welt, darüber wird weich hochskaliert. Größter Hebel für die Bildrate.",
	"dynres": "Senkt die 3D-Auflösung automatisch, wenn die Bildrate unter 60 fällt, und hebt sie danach wieder an.",
	"view": "Wie weit du siehst. Weiter = mehr Häuser und Wahrzeichen im Bild, kostet Leistung.",
	"detail": "Ab welcher Entfernung Kleinteile verschwinden und Autos vereinfacht gezeichnet werden.",
	"tex": "Hoch: Asphalt bleibt bis weit nach vorn scharf, feinere Lichtkreise der Laternen. Braucht etwas mehr Grafikspeicher.",
	"lights": "Bis zu welcher Entfernung Laternen und Leuchtreklamen Autos und Häuser beleuchten. Die Lichtkreise auf der Straße sind immer da.",
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
	"motion": "Wie sich Tempo anfühlt: Bewegungsunschärfe, Tempo-Zoom, Kamerawackeln und Sprungkamera. Alles einzeln abschaltbar.",
	"motion_blur": "Bei hohem Tempo verwischt der Bildrand in Fahrtrichtung, mit Nitro stärker; das eigene Auto bleibt scharf. Aus: auch kein Nitro-Schimmer.",
	"speed_fov": "Das Sichtfeld wird mit dem Tempo und bei Nitro weiter. Aus: festes Sichtfeld.",
	"cam_shake": "Kurze Stöße bei Einschlägen und Landungen, die Kamera neigt sich beim Lenken. Aus: ruhige Kamera.",
}


## Grafik, Vollbild, Spielstand: nicht auf der Startseite, sondern gesammelt hier
func _show_settings(focus := "") -> void:
	_clear_menu()
	_back = _show_main
	_set_section("EINSTELLUNGEN")
	var g := _button("Grafik  >", _show_graphics)
	g.focus_entered.connect(func(): info.text = tr(SETTING_HINTS["graphics"]))
	g.set_meta("key", "graphics")
	var mo := _button("Kamera & Tempo  >", _show_motion)
	mo.focus_entered.connect(func(): info.text = tr(SETTING_HINTS["motion"]))
	mo.set_meta("key", "motion")
	for key in ["language", "difficulty", "show_fps", "vsync", "fps", "fullscreen", "touch"]:
		_setting_button(key).set_meta("key", key)
	_button("Spielstand zurücksetzen", _confirm_reset).set_meta("key", "reset")
	# Quellen: die Motorklänge sind echte Aufnahmen unter CC BY, die Urheber werden genannt (ausführlich in CREDITS.md)
	var cr := _button("Quellen & Lizenzen", func(): info.text = tr(CREDITS_TEXT))
	cr.focus_entered.connect(func(): info.text = tr(CREDITS_TEXT))
	cr.set_meta("key", "credits")
	cr.set_meta("quiet", true)
	_button("< Zurück", _show_main)
	info.text = tr(SETTING_HINTS["graphics"])
	_focus_first()
	_focus_key(focus)


## Nach dem Zurückgehen steht der Fokus wieder auf dem Eintrag, aus dem man kam
func _focus_key(key: String) -> void:
	if key == "":
		return
	for c in menu.get_children():
		if c.has_meta("key") and c.get_meta("key") == key:
			_grab.call_deferred(c as Control)
			return


## Grafikmenü: Voreinstellung oben, darunter jede Option einzeln (Links/Rechts oder Klick schaltet um).
## Optionen, die der Browser-Renderer nicht kann (Spiegelungen, Umgebungsverdeckung), fehlen dort.
func _show_graphics() -> void:
	_clear_menu()
	_back = _show_settings.bind("graphics")
	_set_section("GRAFIK")
	for key in ["preset"] + GameState.GFX_ORDER.filter(GameState.gfx_available) + ["pixel"]:
		_setting_button(key)
	_button("< Zurück", _back)
	info.text = tr(SETTING_HINTS["preset"])
	_focus_first()


## Tempogefühl: Bewegungsunschärfe, Tempo-Zoom, Kamerawackeln, Sprungkamera (gegen Übelkeit alles abschaltbar)
func _show_motion() -> void:
	_clear_menu()
	_back = _show_settings.bind("motion")
	_set_section("KAMERA & TEMPO")
	for key in ["motion_blur", "speed_fov", "cam_shake", "jumpcam"]:
		_setting_button(key)
	_button("< Zurück", _back)
	info.text = tr(SETTING_HINTS["motion_blur"])
	_focus_first()


func _setting_button(k: String) -> Button:
	var b := _button(GameState.setting_text(k), func(): pass)
	b.set_meta("setting", k)
	b.set_meta("quiet", true)  # Umschalten hat seinen eigenen Ton
	var change := func(dir: int):
		if k == "language":
			_show_language(false)
			return
		if k == "fullscreen":
			GameState.toggle_fullscreen()
		else:
			GameState.cycle_setting(k, dir)
		Sfx.ui("change")
		# Voreinstellung ändert alle Optionen, eine Option ggf. die Voreinstellung: alle Texte neu
		for c in menu.get_children():
			if c.has_meta("setting"):
				c.text = GameState.setting_text(c.get_meta("setting")).to_upper()
	b.pressed.connect(change.bind(1))
	if k != "language":
		b.gui_input.connect(func(ev): _lr_input(ev, change))
	b.focus_entered.connect(func(): info.text = tr(SETTING_HINTS[k]))
	return b


## Karriere wie in NFSU2: Stufen untereinander, alle Events einer offenen Stufe frei wählbar; drei Siege in einer
## Stufe öffnen die nächste. Jede Zeile trägt rechts die Art als farbiges Abzeichen (Sprint cyan, Rundkurs grün,
## Drag pink, Drift orange) und die Schwierigkeit als Rauten (golden, wenn gewonnen). Rechts die Deutschlandkarte.
func _show_races() -> void:
	_clear_menu()
	_back = _show_main
	_set_section("KARRIERE")
	career_map.visible = true
	var target: Control = null
	var target_stage := -1
	for s in Catalog.STAGES.size():
		menu.add_child(_stage_header(s))
		for ev in Catalog.STAGES[s]["events"]:
			var name: String = ev
			var ri := Catalog.race_index(name)
			var r: Dictionary = Catalog.RACES[ri]
			var open := GameState.career_open(name)
			var won: bool = name in GameState.won_events
			var b := _button(name, func():
				if GameState.career_open(name):
					_start_race(ri)
				else:
					Sfx.ui("locked"))
			b.set_meta("quiet", true)
			b.add_theme_font_size_override("font_size", 12)
			b.clip_text = true
			b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			_event_badge(b, r, won)
			if not open:
				b.modulate = Color(1, 1, 1, 0.38)
			elif target == null or (not won and s > target_stage):
				target = b
				target_stage = s if not won else -1
			b.focus_entered.connect(func():
				career_map.selected = name
				info.text = _career_info(name))
	_button("< Zurück", _show_main)
	_focus_first()
	# Fokus auf das erste offene, noch nicht gewonnene Event der höchsten offenen Stufe
	if target:
		_grab.call_deferred(target)
	# erst wenn die Liste ausgelegt ist, stimmt die Position: dann dorthin scrollen
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(target) and target.is_inside_tree():
		menu_scroll.ensure_control_visible(target)


## Überschrift einer Stufe: "STUFE 2 · SZENE" links, rechts "1/3 SIEGE" (offen, cyan), "FERTIG" (gold) oder
## "GESPERRT" (grau)
func _stage_header(s: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(226, 22 if s > 0 else 16)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var open := GameState.stage_open(s)
	var w := GameState.stage_wins(s)
	var done := w >= Catalog.stage_need(s)
	var col: Color = UI.GOLD if open and done else (UI.CYAN if open else Color(0.5, 0.53, 0.58))
	var left := tr("STUFE %d · %s") % [s + 1, tr(Catalog.STAGES[s]["name"]).to_upper()]
	var right := tr("GESPERRT") if not open else (tr("FERTIG") if done else tr("%d/%d SIEGE") % [w, Catalog.stage_need(s)])
	c.draw.connect(func():
		var f := UI.font("cond", 0.2)
		var y := c.size.y - 4.0
		c.draw_string_outline(f, Vector2(2, y), left, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, Color(0, 0, 0, 0.9))
		c.draw_string(f, Vector2(2, y), left, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)
		var rw := f.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		c.draw_string_outline(f, Vector2(c.size.x - rw - 4.0, y), right, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, 3, Color(0, 0, 0, 0.9))
		c.draw_string(f, Vector2(c.size.x - rw - 4.0, y), right, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, col)
		c.draw_rect(Rect2(2, c.size.y - 1.5, c.size.x - 4.0, 1.0), Color(col.r, col.g, col.b, 0.45)))
	return c


## Abzeichen der Event-Art rechts im Knopf; der Name wird davor gekürzt (Abstand rechts im Knopf-Stil)
func _event_badge(b: Button, r: Dictionary, won: bool) -> void:
	var rt: String = r["type"]
	var label := tr(Catalog.EVENT_TYPES[rt]["label"]).to_upper()
	var tier: int = r.get("tier", 1)
	var bw := UI.badge_width(label, 8, tier)
	for st in ["normal", "hover", "focus", "pressed", "disabled"]:
		var sb: StyleBox = b.get_theme_stylebox(st).duplicate()
		sb.content_margin_right = bw + 12.0
		b.add_theme_stylebox_override(st, sb)
	var bd := Control.new()
	bd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bd.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.add_child(bd)
	bd.draw.connect(func():
		UI.draw_badge(bd, Vector2(bd.size.x - bw - 8.0, (bd.size.y - 11.0) / 2.0), rt, label, 8, tier, won))


## Infotext zu einem Karriere-Event: Ort und Art, das Ziel, die Beschreibung, dann Stand (gesperrt, Bestwert)
func _career_info(ev: String) -> String:
	var r: Dictionary = Catalog.RACES[Catalog.race_index(ev)]
	var rt: String = r["type"]
	var head := "%s  ·  %s" % [r.get("town", ""), tr(Catalog.EVENT_TYPES[rt]["label"]).to_upper()]
	if r.has("laps") and rt != "sprint":
		head += "  ·  " + tr("%d Runden. ") % r["laps"]
	var goal := tr(Catalog.EVENT_TYPES[rt]["goal"])
	if rt == "circuit":
		goal = goal % r.get("laps", 2)
	elif rt == "drift":
		var tg: Array = Catalog.drift_targets(r, GameState.difficulty)
		goal = tr("%d Punkte für Platz 1 (Platz 3 ab %d).") % [tg[2], tg[0]]
	var t := head + "\n" + tr("Ziel: ") + goal + "\n" + tr(r.get("desc", Catalog.EVENT_TYPES[rt]["desc"]))
	var s := Catalog.stage_of(ev)
	if not GameState.career_open(ev):
		var left: int = Catalog.stage_need(s - 1) - GameState.stage_wins(s - 1)
		t = head + "\n" + tr("Ziel: ") + goal + "\n" + (tr("Gesperrt: gewinne noch %d Event in Stufe %d." if left == 1 else
			"Gesperrt: gewinne noch %d Events in Stufe %d.") % [left, s])
	elif GameState.best_times.has(ev):
		var best: float = GameState.best_times[ev]
		var bt := ("%d P" % int(best)) if rt == "drift" else "%d:%05.2f" % [int(best) / 60, fmod(best, 60.0)]
		t += "\n" + (tr("Gewonnen") + "  ·  " if ev in GameState.won_events else "") + tr("Bestwert: ") + bt
	return t


## Orts-Strecken nur unter "Städte", nicht zusätzlich unter ihrer Art
func _in_list(r: Dictionary, type: String) -> bool:
	return r.has("city") if type == "city" else (r["type"] == type and not r.has("city"))


func _show_events(type: String) -> void:
	_clear_menu()
	_back = _show_races
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
		b.set_meta("quiet", true)
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


## Rennen starten: sofort den Ladebildschirm zeigen (das Rennen übernimmt ihn), Musik leiser, dann Szene wechseln.
## Ohne das stand das Menü einige Sekunden still, während die Strecke gebaut wurde.
var _starting := false


func _start_race(i: int) -> void:
	if _starting:
		return
	_starting = true
	GameState.race_index = i
	GameState.save_game()
	Sfx.ui("go")
	Music.race_loading()
	Loading.next_tip()
	add_child(Loading.new(Catalog.RACES[i], GameState.current_car))
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/race.tscn")


func _show_tuning(focus := "") -> void:
	_clear_menu()
	_strip_on(true)
	_back = func(): _cam_view = ""; _show_main()
	_cam_view = ""
	preview_cfg = GameState.get_config(preview_car).duplicate()
	_show_car(preview_car, preview_cfg)
	_set_section("TUNING", true)
	_tile(tr("Fertig"), "", _back, {"back": true})
	var bo := _tile(tr("Optik"), tr("Lack, Felgen, Spoiler …"), func(): _show_group("optik"), {"key": "optik"})
	bo.focus_entered.connect(func(): info.text = tr("Lack, Felgen, Spoiler, Bodykit, Haube, Auspuff, Folierung, Neon, Scheiben, Licht.") + "\n" + tr(TUNING_SHARED))
	var bl := _tile(tr("Leistung"), tr("Motor, Turbo, Nitro …"), func(): _show_group("leistung"), {"key": "leistung"})
	bl.focus_entered.connect(func(): info.text = tr("Motor, Turbo, Nitro, Fahrwerk, Reifen. Wirkt wirklich auf das Fahrverhalten.") + "\n" + tr(TUNING_SHARED))
	_strip_ready(focus if focus != "" else "optik")


const TUNING_SHARED := "Eingebaute Teile passen auf alle deine Autos."


## Kategorien einer Gruppe als Kacheln, unter dem Namen jeweils das eingebaute Teil
func _show_group(group: String, focus := "") -> void:
	_clear_menu()
	_strip_on(true)
	_back = _show_tuning.bind(group)
	preview_cfg = GameState.get_config(preview_car).duplicate()
	_show_car(preview_car, preview_cfg)
	_set_section("OPTIK" if group == "optik" else "LEISTUNG", group == "leistung")
	_tile(tr("Zurück"), "", _back, {"back": true})
	var first := ""
	for cat in Catalog.PART_GROUPS[group]:
		var c: String = cat
		if first == "":
			first = c
		var opt := Catalog.part_of(preview_cfg, c)
		var oname := tr(opt["name"]) + _inch_suffix(c, preview_cfg)
		var b := _tile(tr(Catalog.PARTS[c]["label"]), oname, func(): _show_parts(c, group),
			{"key": c, "swatch": _swatch(c, int(preview_cfg.get(c, 0)))})
		b.focus_entered.connect(func():
			_cam_view = c
			Builder.showcase(car_node, preview_car, preview_cfg, _showcase_mode(c))
			info.text = tr(Catalog.PARTS[c]["label"]) + ": " + oname)
	_strip_ready(focus if focus != "" else first)


func _showcase_mode(cat: String) -> String:
	if cat == "engine" or cat == "turbo":
		return "engine"
	if cat == "nitro":
		return "nitro"
	return ""


## Teile einer Kategorie als Kacheln: Vorschau beim Auswählen, Einbauen mit Enter (wenn freigeschaltet)
func _show_parts(cat: String, group: String) -> void:
	_clear_menu()
	_strip_on(true)
	_back = _show_group.bind(group, cat)
	_cam_view = cat
	section.text = tr(Catalog.PARTS[cat]["label"]).to_upper()
	stats.get_parent().visible = group == "leistung"  # Optik-Teile ändern keine Fahrwerte: Balken weg, Auto frei
	var installed: int = GameState.get_config(preview_car).get(cat, 0)
	var opts: Array = Catalog.PARTS[cat]["options"]
	_tile(tr("Zurück"), "", _back, {"back": true})
	for i in opts.size():
		var idx := i
		var b := _tile("", "", func(): _install(cat, idx, group), {"part": idx, "swatch": _swatch(cat, idx), "quiet": true})
		b.focus_entered.connect(func(): _preview_part(cat, idx))
	_refresh_parts(cat)
	_strip_ready("", installed + 1)


func _refresh_parts(cat: String) -> void:
	var installed: int = GameState.get_config(preview_car).get(cat, 0)
	for b in strip_box.get_children():
		if not b.has_meta("part"):
			continue
		var i: int = b.get_meta("part")
		var opt: Dictionary = Catalog.PARTS[cat]["options"][i]
		var sub := ""
		var locked := not GameState.is_part_unlocked(cat, i)
		if i == installed:
			sub = tr("EINGEBAUT")
		elif locked:
			sub = tr("1 SIEG") if opt["wins"] == 1 else tr("%d SIEGE") % opt["wins"]
		var c2 := GameState.get_config(preview_car).duplicate()
		c2[cat] = i
		_tile_text(b, tr(opt["name"]) + _inch_suffix(cat, c2), sub)
		b.set_meta("installed", i == installed)
		b.set_meta("locked", locked)
		_tile_colors(b)


func _preview_part(cat: String, idx: int) -> void:
	var base := GameState.get_config(preview_car).duplicate()
	preview_cfg = base.duplicate()
	preview_cfg[cat] = idx
	_show_car(preview_car, preview_cfg)
	Builder.showcase(car_node, preview_car, preview_cfg, _showcase_mode(cat))
	_show_stats(preview_car, preview_cfg, base)
	_part_info(cat, idx)


func _press_sound(b: Button) -> void:
	if not b.has_meta("quiet"):
		Sfx.ui("select")


# --- Tuning-Leiste ----------------------------------------------------------

## Leiste an/aus: im Tuning verschwindet die Liste links, das Infofeld rückt nach links über die Leiste
func _strip_on(on: bool) -> void:
	_clear_strip()
	if _strip_mode == on:
		return
	_strip_mode = on
	strip.visible = on
	menu_scroll.visible = not on
	_fade_left.visible = not on
	if on:
		_info_panel.anchor_left = 0.0
		_info_panel.anchor_right = 0.0
		_info_panel.offset_left = 14.0
		_info_panel.offset_right = 290.0
		_info_panel.offset_top = -94.0  # wächst nach oben, so hoch wie der Text
		_info_panel.offset_bottom = -94.0
		_keys.text = tr("←/→  Auswählen      ENTER  Einbauen/Öffnen      ESC  Zurück      F11  Vollbild")
	else:
		_info_panel.anchor_left = 1.0
		_info_panel.anchor_right = 1.0
		_info_panel.offset_left = -300.0
		_info_panel.offset_right = -14.0
		_info_panel.offset_top = -92.0
		_info_panel.offset_bottom = -26.0
		_keys.text = tr("ENTER  Auswählen      ESC  Zurück      ←/→ A/D  Ändern      F11  Vollbild")


func _clear_strip() -> void:
	for c in strip_box.get_children():
		strip_box.remove_child(c)
		c.queue_free()
	strip_box.position.x = 0.0
	strip_box.size = Vector2.ZERO


## Eine Kachel: Name groß, darunter klein (eingebautes Teil, Sperre). opts: key, part, swatch (Farbe), back, quiet
func _tile(title_text: String, sub: String, cb: Callable, opts := {}) -> Button:
	var b := Button.new()
	var is_back: bool = opts.get("back", false)
	b.custom_minimum_size = Vector2(76.0 if is_back else 118.0, 46.0)
	b.focus_mode = Control.FOCUS_ALL
	for k in opts:
		if k != "swatch":
			b.set_meta(k, opts[k])
	var t := Label.new()
	t.name = "T"
	t.label_settings = LabelSettings.new()
	t.label_settings.font = UI.font("cond", 0.2)
	t.label_settings.font_size = 13
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.set_anchors_preset(Control.PRESET_TOP_WIDE)
	t.offset_left = 9.0
	t.offset_right = -5.0
	t.offset_top = 6.0 if sub != "" or not is_back else 14.0
	t.offset_bottom = t.offset_top + 17.0
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(t)
	var u := Label.new()
	u.name = "S"
	u.label_settings = LabelSettings.new()
	u.label_settings.font = UI.font("bold", 0.12)
	u.label_settings.font_size = 8
	u.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	u.clip_text = true
	u.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	u.set_anchors_preset(Control.PRESET_TOP_WIDE)
	u.offset_left = 9.0
	u.offset_right = -5.0
	u.offset_top = 26.0
	u.offset_bottom = 38.0
	u.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(u)
	var sw = opts.get("swatch", null)
	if sw is Color:
		# Farbfeld (Lack, Felgenfarbe, Folie, Neon, Licht)
		var r := ColorRect.new()
		r.name = "W"
		r.color = sw
		r.position = Vector2(10, 28)
		r.size = Vector2(9, 9)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rim := ColorRect.new()  # heller Rand: Schwarz auf dunkler Kachel sichtbar
		rim.color = Color(1, 1, 1, 0.5)
		rim.position = r.position - Vector2.ONE
		rim.size = r.size + Vector2(2, 2)
		rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(rim)
		b.add_child(r)
		u.offset_left = 20.0
	_tile_text(b, ("◀ " if is_back else "") + title_text, sub)
	b.focus_entered.connect(func():
		Sfx.ui("move")
		_center_strip(b)
		for c in strip_box.get_children():
			_tile_colors(c))
	b.focus_exited.connect(func(): _tile_colors(b))
	b.pressed.connect(func():
		if is_back:
			Sfx.ui("back")
		elif not opts.get("quiet", false):
			Sfx.ui("select")
		cb.call())
	strip_box.add_child(b)
	_tile_colors(b)
	return b


func _tile_text(b: Button, title_text: String, sub: String) -> void:
	(b.get_node("T") as Label).text = title_text.to_upper()
	(b.get_node("S") as Label).text = sub.to_upper()


## Schriftfarben je Zustand: gewählt (grüne Kachel) dunkel, eingebaut grün, gesperrt grau
func _tile_colors(b: Node) -> void:
	if not b is Button or not b.has_node("T"):
		return
	var focused := (b as Button).has_focus()
	var t: Label = b.get_node("T")
	var u: Label = b.get_node("S")
	var locked: bool = b.get_meta("locked", false)
	t.label_settings.font_color = Color(0.02, 0.05, 0.02) if focused else (Color(0.62, 0.64, 0.68) if locked else Color(0.95, 0.97, 1.0))
	u.label_settings.font_color = Color(0.05, 0.14, 0.05) if focused else (UI.GREEN if b.get_meta("installed", false) else
		(Color(1.0, 0.45, 0.35) if locked else UI.CYAN))
	(b as Button).modulate.a = 0.72 if locked and not focused else 1.0


## Leiste fertig: Ränder verknüpfen (rechts vom letzten geht es zum ersten), hoch/runter gesperrt, Fokus setzen.
## focus_key: Kachel mit meta "key", sonst Index focus_i (sonst die erste nach "Zurück").
func _strip_ready(focus_key := "", focus_i := -1) -> void:
	var tiles := strip_box.get_children()
	if tiles.is_empty():
		return
	for i in tiles.size():
		var b: Button = tiles[i]
		b.focus_neighbor_left = b.get_path_to(tiles[(i - 1 + tiles.size()) % tiles.size()])
		b.focus_neighbor_right = b.get_path_to(tiles[(i + 1) % tiles.size()])
		b.focus_neighbor_top = NodePath(".")
		b.focus_neighbor_bottom = NodePath(".")
	var target: Button = tiles[mini(1, tiles.size() - 1)]
	for b in tiles:
		if focus_key != "" and b.get_meta("key", "") == focus_key:
			target = b
	if focus_i >= 0 and focus_i < tiles.size():
		target = tiles[focus_i]
	# Leiste fährt von unten ein
	strip_box.modulate.a = 0.0
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(strip_box, "modulate:a", 1.0, 0.2)
	section.modulate.a = 0.0
	tw.tween_property(section, "modulate:a", 1.0, 0.25)
	_strip_focus.call_deferred(target)


func _strip_focus(b: Button) -> void:
	if not is_instance_valid(b) or not b.is_inside_tree():
		return
	strip_box.reset_size()
	strip_box.position.y = 8.0
	_center_strip(b, false)
	b.grab_focus()


## Gewählte Kachel in die Mitte schieben; Pfeile links/rechts nur, wenn dort noch Kacheln sind
func _center_strip(b: Button, animate := true) -> void:
	if not b.is_inside_tree():
		return
	var w := strip_box.size.x
	var tx := strip.size.x / 2.0 - (b.position.x + b.size.x / 2.0)
	if w + 48.0 <= strip.size.x:
		tx = (strip.size.x - w) / 2.0  # passt ganz hinein: mittig
	else:
		tx = clampf(tx, strip.size.x - w - 24.0, 24.0)
	if animate:
		var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(strip_box, "position:x", tx, 0.16)
	else:
		strip_box.position.x = tx
	for c in strip.get_children():
		if c.has_meta("arrow"):
			var side: int = c.get_meta("arrow")
			c.visible = (tx < 20.0) if side < 0 else (tx + w > strip.size.x - 20.0)


## Farbfeld für eine Kachel: Lack, Felgenfarbe, Folienfarbe, Neon, Licht (sonst null)
func _swatch(cat: String, idx: int):
	var opt: Dictionary = Catalog.PARTS[cat]["options"][idx]
	if cat == "paint" and idx == 0:
		return Catalog.CARS[preview_car].get("paint", opt.get("color", Color.WHITE))
	if opt.get("paint", false):
		return Builder.paint_color(preview_car, GameState.get_config(preview_car))
	if cat != "rims" and opt.get("color", null) is Color:
		return opt["color"]
	return null


func _install(cat: String, idx: int, group: String) -> void:
	if not GameState.is_part_unlocked(cat, idx):
		Sfx.ui("locked")
		return
	if GameState.get_config(preview_car).get(cat, 0) == idx:
		Sfx.ui("select")
		return
	GameState.set_part(preview_car, cat, idx)
	GameState.save_game()
	Sfx.ui("install")
	_refresh_parts(cat)
	_show_stats(preview_car, preview_cfg, GameState.get_config(preview_car))
	_part_info(cat, idx)


## Felgen und Zoll: Größe in Zoll hinter dem Namen (z. B. 18"), je Auto verschieden
func _inch_suffix(cat: String, cfg: Dictionary) -> String:
	if cat != "rims" and cat != "rimsize":
		return ""
	return "  %d\"" % Builder.rim_spec(preview_car, cfg)["inch"]


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
		"finish":
			var c3 := GameState.get_config(preview_car).duplicate()
			c3[cat] = idx
			var fk := Builder.paint_finish(preview_car, c3)
			var desc := {"gloss": "Uni-Lack unter Klarlack: satte Farbe, scharfe Spiegelungen.",
				"metal": "Feiner Flitter im Lack, frontal hell, zur Seite dunkler.", "matt": "Ohne Klarlack: stumpf, ohne Spiegelungen.",
				"pearl": "Die Farbe kippt zum Rand hin in einen hellen Schimmer."}
			if fk.begins_with("chrome"):
				t += "\n" + tr("Chrom bleibt Chrom, matt wird es gebürstet.")
			else:
				if idx == 0:
					t += "\n" + tr("Wie die Farbe: %s") % tr({"gloss": "Glanz", "metal": "Metallic", "matt": "Matt", "pearl": "Perlmutt"}[fk])
				t += "\n" + tr(desc[fk])
		"rims", "rimsize":
			var c2 := GameState.get_config(preview_car).duplicate()
			c2[cat] = idx
			var rs := Builder.rim_spec(preview_car, c2)
			t += "\n" + tr("Felge %d Zoll   ·   Reifen %s") % [rs["inch"], rs["tire"]]
			if cat == "rimsize" and rs["inch"] == rs["max_in"] and rs["std_in"] + int(opt["inch"]) > rs["max_in"]:
				t += "\n" + tr("Größer passt bei diesem Auto nicht unter den Reifen.")
			elif cat == "rimsize":
				t += "\n" + tr("Nur Optik: der Reifen behält seinen Durchmesser, die Flanke wird flacher.")
	if not GameState.is_part_unlocked(cat, idx):
		var missing: int = opt["wins"] - GameState.total_wins()
		t += "\n" + (tr("Gesperrt: noch 1 Sieg nötig.") if missing == 1 else tr("Gesperrt: noch %d Siege nötig.") % missing)
	elif idx != GameState.get_config(preview_car).get(cat, 0):
		t += "\n" + tr("ENTER: einbauen")
	info.text = t


func _show_cars() -> void:
	_clear_menu()
	_back = _show_main
	_set_section("AUTOHAUS", true)
	var b := _button("", func(): _cycle_car(1))
	b.set_meta("car", true)
	b.set_meta("quiet", true)
	b.gui_input.connect(func(ev): _lr_input(ev, _cycle_car))
	_button("Dieses Auto fahren", _choose_car).set_meta("quiet", true)
	_button("< Zurück", _show_main)
	_refresh_car()
	_focus_first()


func _cycle_car(dir: int) -> void:
	Sfx.ui("change")
	var i := Catalog.CAR_ORDER.find(preview_car)
	preview_car = Catalog.CAR_ORDER[posmod(i + dir, Catalog.CAR_ORDER.size())]
	preview_cfg = GameState.get_config(preview_car).duplicate()
	_show_car(preview_car, preview_cfg)
	_refresh_car()


func _refresh_car() -> void:
	var spec: Dictionary = Catalog.CARS[preview_car]
	var unlocked := GameState.is_car_unlocked(preview_car)
	menu.get_child(0).text = ("< %s >%s" % [spec["name"], "" if unlocked else tr("  [GESPERRT]")]).to_upper() \
		+ "  %d/%d" % [Catalog.CAR_ORDER.find(preview_car) + 1, Catalog.CAR_ORDER.size()]
	_show_stats(preview_car, preview_cfg)
	menu.get_child(1).disabled = not unlocked
	info.text = tr(spec["desc"]) + tr("\nHöchstgeschwindigkeit ab Werk: %d km/h") % int(spec["top_speed"] * 3.6) \
		+ tr("\nAntrieb: ") + tr({"fwd": "Frontantrieb", "rwd": "Heckantrieb", "mr": "Mittelmotor, Heckantrieb", "rr": "Heckmotor, Heckantrieb", "awd": "Allrad"}[spec.get("drive", "rwd")])
	if not unlocked:
		info.text += tr("\nFreischalten: ") + GameState.unlock_text(preview_car)


func _stars(v: float, lo: float, hi: float) -> String:
	var n := int(round(clampf((v - lo) / (hi - lo), 0.0, 1.0) * 4.0)) + 1
	return "#".repeat(n) + ".".repeat(5 - n)


func _choose_car() -> void:
	if GameState.is_car_unlocked(preview_car):
		Sfx.ui("install")
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
		b.focus_entered.connect(func(): Sfx.ui("move"))
		b.pressed.connect(func():
			Sfx.ui("select")
			GameState.set_language(l)
			get_tree().reload_current_scene())  # alle Texte neu in der gewählten Sprache
		menu.add_child(b)
	_back = Callable() if first else _show_settings.bind("language")
	if not first:
		_button("< Zurück", _back)
	info.text = "Choose your language. Title, places and signs stay German.\nWähle deine Sprache. Titel, Orte und Schilder bleiben deutsch."
	_focus_first()
	if not first and GameState.language == "de":
		_grab.call_deferred(menu.get_child(1))


func _confirm_reset() -> void:
	_clear_menu()
	_back = _show_settings.bind("reset")
	_set_section("ACHTUNG")
	info.text = tr("Alle Siege und Tuningteile gehen verloren.")
	_button("Ja, zurücksetzen", func(): GameState.reset_progress(); _show_main())
	_button("Abbrechen", _show_main)
	_grab.call_deferred(menu.get_child(1))


func _lr_input(ev: InputEvent, cb: Callable) -> void:
	if ev.is_action_pressed("ui_left"):
		cb.call(-1)
		get_viewport().set_input_as_handled()
	elif ev.is_action_pressed("ui_right"):
		cb.call(1)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and GameState.language != "" and not _starting:
		Sfx.ui("back")
		if _back.is_valid():
			_back.call()
		else:
			_show_main()


func _exit_tree() -> void:
	Music.toast_corner = false
