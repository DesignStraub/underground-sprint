extends Node3D
## Hauptmenü in der Garage: dein Auto fährt auf einem Rollenprüfstand auf der Stelle (seit 2.38, vorher Drehteller),
## links das Menü. Tuning und Autowechsel zeigen gesperrte Teile als Vorschau, gespeichert wird nur Freigeschaltetes.

const Catalog := preload("res://scripts/catalog.gd")
const Builder := preload("res://scripts/car_builder.gd")
const PixelView := preload("res://scripts/pixel_view.gd")
const UI := preload("res://scripts/ui_style.gd")
const I18n := preload("res://scripts/i18n.gd")
const CareerMap := preload("res://scripts/career_map.gd")
const GarageSet := preload("res://scripts/garage_set.gd")

const Loading := preload("res://scripts/loading_screen.gd")
## Tipps wie auf den Ladebildschirmen von NFS Underground (stehen beim Ladebildschirm)
const TIPS := Loading.TIPS

var world: SubViewport
var stand: Node3D  # Stellplatz auf dem Laufband (Ursprung), daran hängen die Autos
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
var _keys: HBoxContainer
var _xp_line: Control
var _status_text := ""
var _ui: Control  # Wurzel der Oberfläche (Größe in UI-Pixeln: freie Fläche fürs Auto)
var _in_cars := false  # Autohaus offen (eigene Kamera, Auto fährt beim Blättern herein)
var title: Label
var info: InfoText
var status: Label
var section: Label
var stats: VBoxContainer
var _stats_card: PanelContainer
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
	elif GameState.world_menu == "tuning":
		preview_car = GameState.current_car
		_show_tuning()  # aus der Open World (Esc > Tuning): "Fertig" führt zurück in die Welt
	elif GameState.world_menu == "cars":
		preview_car = GameState.current_car
		_show_cars()
	elif GameState.world_menu == "driver":
		preview_car = GameState.current_car
		_show_driver()
	else:
		_show_main()
	if car_node == null:
		# Sprachwahl, aus der Welt direkt ins Autohaus oder zum Fahrer: das eigene Auto steht schon auf dem Band
		preview_car = GameState.current_car
		preview_cfg = GameState.get_config(preview_car).duplicate()
		_show_car(preview_car, preview_cfg)


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
	env.background_color = Color(0.008, 0.009, 0.012)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.34, 0.4)
	env.ambient_light_energy = 0.26
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_intensity = 0.6  # nur Scheinwerfer und Rückleuchten strahlen leicht über
	env.glow_hdr_threshold = 1.0
	# Spiegelungen: ohne sie spiegelt der Lack nur das Schwarz der Halle, Glanz und Matt sähen gleich aus.
	# Ein unsichtbarer Studio-Himmel (Lichtbänder an der Decke, Softboxen) steht nur im Lack und im Boden.
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

	# Seit 2.38 eine Werkstatt mit Rollenprüfstand (garage_set.gd) statt des Fotostudios mit Drehteller: das Auto fährt
	# auf einem Laufband auf der Stelle. Licht wie zuvor ruhig: ein Lichtkegel von oben auf das Auto, ein Wandstrahler
	# auf Lochwand und Werkbank, ein kühles Kantenlicht von hinten links. Das Auto ist der hellste Punkt im Bild.
	_hall = GarageSet.build(world)

	var top := SpotLight3D.new()
	top.position = Vector3(0, 6, 0.4)
	top.rotation_degrees.x = -84
	top.spot_range = 10
	top.spot_angle = 40
	top.spot_angle_attenuation = 0.6
	top.light_energy = 3.2
	top.light_color = Color(1.0, 0.97, 0.93)
	top.shadow_enabled = true
	if RenderingServer.get_current_rendering_method() == "gl_compatibility":
		# Browser-Renderer: mit dem Standardabstand lagen wellige Streifen (Schattenakne) auf Dach und Haube, seit das
		# Auto stillsteht und man oft aufs Dach schaut
		top.shadow_bias = 0.12
		top.shadow_normal_bias = 2.0
	world.add_child(top)
	# Wandstrahler: weiches Lichtfeld auf Lochwand und Werkbank, dort, wo man die Rückwand hinter dem Auto sieht
	var wash := SpotLight3D.new()
	wash.position = Vector3(-2.2, 6.4, -0.4)
	world.add_child(wash)
	wash.look_at_from_position(wash.position, Vector3(GarageSet.BACK_X, 1.5, -0.6), Vector3.UP)
	wash.spot_range = 12
	wash.spot_angle = 48
	wash.spot_angle_attenuation = 1.4
	wash.spot_attenuation = 0.35  # kaum Abfall über die Entfernung: das Feld auf der Wand bleibt weich und gleichmäßig
	wash.light_energy = 0.8
	wash.light_color = Color(1.0, 0.95, 0.88)
	# Kantenlicht von hinten links: Silhouette, Dachlinie, Glanz auf dem Lack
	var rim := SpotLight3D.new()
	rim.position = Vector3(-4.5, 3.4, -4.8)
	world.add_child(rim)
	rim.look_at_from_position(rim.position, Vector3(0, 0.7, 0), Vector3.UP)
	rim.spot_range = 13
	rim.spot_angle = 26
	rim.light_energy = 3.5
	rim.light_color = Color(0.82, 0.88, 1.0)
	# nur auf die Autos: es wirft keinen Schatten, auf dem glatten Hallenboden lag sein Glanz sonst hell unter dem Auto
	# (bis 2.38 verschluckte das dunkle Gummiband ihn)
	rim.light_cull_mask = Builder.CAR_LAYER
	# Aufhelllicht von rechts vorn oben (hoch genug, dass es keinen hellen Fleck auf den Boden vor der Kamera legt)
	var fill := OmniLight3D.new()
	fill.position = Vector3(4.2, 3.4, -2.2)
	fill.light_energy = 0.6
	fill.light_color = Color(1.0, 0.96, 0.9)
	fill.omni_range = 10
	world.add_child(fill)

	# Stellplatz um 180° gedreht: das Auto fährt nach +Z, die Kamera steht auf seiner linken Seite (_cam_goal)
	stand = Node3D.new()
	stand.position.y = 0.0  # Boden: das Band liegt bündig darin (seit 2.39)
	stand.rotation.y = PI
	world.add_child(stand)

	cam = Camera3D.new()
	cam.fov = CAM_FOV
	# Bildausschnitt per Objektivverschiebung (frustum_offset) statt seitlich versetzter Kamera (h_offset): das Auto steht
	# neben dem Menü bzw. über der Leiste, ohne dass sich der Blickwinkel ändert (Größe aus fov, _process)
	cam.projection = Camera3D.PROJECTION_FRUSTUM
	cam.size = 2.0 * cam.near * tan(deg_to_rad(cam.fov) * 0.5)
	world.add_child(cam)
	_work_light = OmniLight3D.new()
	_work_light.light_color = Color(1.0, 0.95, 0.88)
	_work_light.light_energy = 0.0
	_work_light.omni_range = 5.0 * CLOSE_K  # Nahansichten stehen seit 2.39 weiter weg (längere Brennweite)
	_work_light.position = Vector3(0.3, 0.3, 0.0)
	_work_light.light_cull_mask = Builder.CAR_LAYER  # leuchtet das Teil aus, nicht den Boden vor der Kamera
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
	_ui = root
	# Vignette und weiche Abdunklung links (Menü), oben (Kopf) und unten (Hinweise); das Auto bleibt frei und hell
	UI.vignette(root, 0.62)
	var fade := UI.fade_rect(root, Color(0, 0, 0, 0.74))
	fade.anchor_bottom = 1.0
	fade.offset_right = 310.0
	_fade_left = fade
	var top_fade := UI.fade_rect(root, Color(0, 0, 0, 0.5), false)
	top_fade.anchor_right = 1.0
	top_fade.offset_bottom = 60.0
	var bottom_fade := UI.fade_rect(root, Color(0, 0, 0, 0.78), false)
	bottom_fade.flip_v = true
	bottom_fade.anchor_top = 1.0
	bottom_fade.anchor_bottom = 1.0
	bottom_fade.anchor_right = 1.0
	bottom_fade.offset_top = -46.0
	var hair := ColorRect.new()
	hair.color = UI.LINE
	hair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hair.anchor_top = 1.0
	hair.anchor_bottom = 1.0
	hair.anchor_right = 1.0
	hair.offset_left = 14.0
	hair.offset_right = -14.0
	hair.offset_top = -21.0
	hair.offset_bottom = -20.0
	root.add_child(hair)

	# Wortmarke oben links: klein und ruhig, der Abschnittstitel darunter trägt die Seite
	var small := UI.label(root, 6, "wide", UI.DIM, 2)
	small.text = "NEED FOR"
	small.position = Vector2(14.5, 9)
	title = UI.label(root, 12, "cond", UI.TEXT, 1)
	title.text = "GESCHWINDIGKEIT"
	title.position = Vector2(14, 16)
	section = UI.section(root, Vector2(14, 40))

	menu_scroll = ScrollContainer.new()
	menu_scroll.anchor_bottom = 1.0
	menu_scroll.offset_left = 14.0
	menu_scroll.offset_right = 262.0
	menu_scroll.offset_top = 80.0
	menu_scroll.offset_bottom = -26.0
	menu_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	menu_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	menu_scroll.follow_focus = true
	root.add_child(menu_scroll)
	menu = VBoxContainer.new()
	menu.custom_minimum_size = Vector2(226, 0)
	menu.add_theme_constant_override("separation", 1)
	menu_scroll.add_child(menu)

	# Deutschlandkarte rechts (Startstadt, Karriere-Liste)
	career_map = CareerMap.new()
	career_map.anchor_left = 1.0
	career_map.anchor_right = 1.0
	career_map.anchor_bottom = 1.0
	career_map.offset_left = -196.0
	career_map.offset_right = -14.0
	career_map.offset_top = 54.0
	career_map.offset_bottom = -104.0
	career_map.visible = false
	root.add_child(career_map)

	# oben rechts: Stand mit Erfahrungs-Haarlinie, Tipp, Werte des Autos
	status = UI.label(root, 7, "wide", UI.DIM, 1, HORIZONTAL_ALIGNMENT_RIGHT)
	status.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	status.offset_left = -420.0
	status.offset_right = -14.0
	status.offset_top = 9.0
	_xp_line = Control.new()
	_xp_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_xp_line.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_xp_line.offset_left = -134.0
	_xp_line.offset_right = -14.0
	_xp_line.offset_top = 22.0
	_xp_line.offset_bottom = 23.0
	_xp_line.draw.connect(func():
		var li := GameState.level_info()
		var w := _xp_line.size.x
		var k := clampf(float(li["into"]) / maxf(float(li["need"]), 1.0), 0.0, 1.0)
		_xp_line.draw_rect(Rect2(0, 0, w, 1), UI.LINE_HI)
		_xp_line.draw_rect(Rect2(w * (1.0 - k), 0, w * k, 1), UI.ACCENT))
	root.add_child(_xp_line)
	tip = UI.label(root, 7, "bold", UI.FAINT, 0, HORIZONTAL_ALIGNMENT_RIGHT)
	tip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	tip.offset_left = -300.0
	tip.offset_right = -14.0
	tip.offset_top = 27.0
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Werte des Autos: links unter der Liste, im Tuning klein oben rechts (_place_stats), nie über dem Auto
	var sp := PanelContainer.new()
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(sp)
	_stats_card = sp
	stats = VBoxContainer.new()
	stats.add_theme_constant_override("separation", 2)
	sp.add_child(stats)

	# Infotext in einer Glasfläche unten rechts (erste Zeile als Kopf)
	var panel := PanelContainer.new()
	_info_panel = panel
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -300.0
	panel.offset_right = -14.0
	panel.offset_top = -82.0
	panel.offset_bottom = -28.0
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(panel)
	info = InfoText.new()
	panel.add_child(info)

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
	var sfade := UI.fade_rect(strip, Color(0, 0, 0, 0.6), false)
	sfade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sfade.flip_v = true
	strip_box = HBoxContainer.new()
	strip_box.add_theme_constant_override("separation", 6)
	strip_box.position = Vector2(0, 8)
	strip.add_child(strip_box)
	for side in [-1, 1]:
		# Kacheln laufen an den Rändern weich aus, darauf der Pfeil (nur wenn dort noch Kacheln sind)
		var ef := UI.fade_rect(strip, Color(0, 0, 0, 0.88))
		ef.anchor_bottom = 1.0
		if side > 0:
			ef.anchor_left = 1.0
			ef.anchor_right = 1.0
			ef.offset_left = -48.0
			ef.flip_h = true
		else:
			ef.offset_right = 48.0
		ef.set_meta("arrow", side)
		var arrow := UI.label(strip, 14, "cond", UI.DIM, 0, HORIZONTAL_ALIGNMENT_CENTER)
		arrow.text = "‹" if side < 0 else "›"
		arrow.anchor_left = 0.0 if side < 0 else 1.0
		arrow.anchor_right = arrow.anchor_left
		arrow.offset_left = 3.0 if side < 0 else -19.0
		arrow.offset_right = 19.0 if side < 0 else -3.0
		arrow.offset_top = 19.0
		arrow.set_meta("arrow", side)

	# Tastenhinweise als Kappen (auf Handy und Tablet ohne Tastatur nicht nötig)
	_keys = HBoxContainer.new()
	_keys.add_theme_constant_override("separation", 12)
	_keys.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_keys.anchor_top = 1.0
	_keys.anchor_bottom = 1.0
	_keys.offset_left = 14.0
	_keys.offset_top = -16.0
	_keys.offset_bottom = -4.0
	_keys.visible = not GameState.is_mobile()
	root.add_child(_keys)
	_set_keys(KEYS_MENU)
	_tip_i = randi() % TIPS.size()
	tip.text = tr("TIPP: ") + tr(TIPS[_tip_i])


## Tastenhinweise (übersetzter Text "TASTE  Wort      TASTE  Wort", siehe UI.parse_hints)
const KEYS_MENU := "ENTER  Auswählen      ESC  Zurück      ←/→ A/D  Ändern      F11  Vollbild"
const KEYS_STRIP := "←/→  Auswählen      ENTER  Einbauen/Öffnen      ESC  Zurück      F11  Vollbild"
const KEYS_GRID := "PFEILE  Farbe wählen      ENTER  Einbauen      ESC  Zurück      F11  Vollbild"
var _keys_text := ""


func _set_keys(key_text: String) -> void:
	if key_text == _keys_text:
		return
	_keys_text = key_text
	var t := tr(key_text)
	if key_text == KEYS_MENU:
		t += "      " + tr(",  Radio")
	UI.hint_bar(_keys, t)


## Infofeld: die erste Zeile als Kopf (weiß), der Rest leiser darunter; ohne Zeilenumbruch nur der leise Text.
## Neuer Text blendet kurz ein. Garage setzt info.text wie bei einem Label.
class InfoText extends VBoxContainer:
	var head: Label
	var body: Label
	var _text := ""
	var _tw: Tween
	var text: String:
		get:
			return _text
		set(v):
			if v == _text:
				return
			_text = v
			var i := v.find("\n")
			head.text = "" if i < 0 else v.substr(0, i)
			body.text = v if i < 0 else v.substr(i + 1).strip_edges(true, false)
			head.visible = head.text != ""
			body.visible = body.text != ""
			if is_inside_tree():
				if _tw:
					_tw.kill()
				modulate.a = 0.3
				_tw = create_tween()
				_tw.tween_property(self, "modulate:a", 1.0, 0.16)

	func _init() -> void:
		add_theme_constant_override("separation", 3)
		alignment = BoxContainer.ALIGNMENT_CENTER  # feste Mindesthöhe der Fläche, Text mittig darin
		custom_minimum_size = Vector2(258, 0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		head = UI.label(self, 9, "wide", UI.TEXT)
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body = UI.label(self, 8, "bold", Color(0.72, 0.75, 0.8))
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.label_settings.line_spacing = 1.0


## Wertekarte wie im Autohaus: Name, Klasse und Leistungsindex, vier Balken (10 Segmente), Motor-Tuning eingerechnet.
## Segmente hell, in der Tuning-Vorschau der Zuwachs im Akzent und der Verlust rot. Im Tuning (Leiste unten) knapp:
## ohne Namen (steht oben in der Statuszeile), Endtempo in der Kopfzeile, schmalere Balken.
func _show_stats(car_id: String, cfg: Dictionary, base := {}) -> void:
	for c in stats.get_children():
		stats.remove_child(c)
		c.queue_free()
	var compact := _strip_mode
	var st := Catalog.stats(car_id, cfg)
	var bs := Catalog.stats(car_id, base if not base.is_empty() else cfg)
	if not compact:
		var name_l := UI.label(stats, 12, "cond", UI.TEXT, 1)
		name_l.text = str(Catalog.CARS[car_id]["name"]).to_upper()
	var head := UI.label(stats, 7, "wide", UI.DIM, 1)
	# Klasse und Leistungsindex: zeigt, dass die Autos der Klasse S gleich stark sind; Tuning-Vorschau mit Zuwachs
	var pi := Catalog.rating(car_id, cfg)
	var pi0 := Catalog.rating(car_id, base if not base.is_empty() else cfg)
	head.text = tr("KLASSE %s  ·  LEISTUNG %d") % [Catalog.CARS[car_id].get("class", "-"), pi]
	if pi != pi0:
		head.text += "  (%+d)" % (pi - pi0)
		head.label_settings.font_color = UI.ACCENT if pi > pi0 else UI.LOSS
	elif compact:
		head.text += "  ·  %d KM/H" % int(st["top"] * 3.6)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 2 if compact else 3)
	stats.add_child(gap)
	for row in [["BESCHLEUNIGUNG", "accel", 9.0, 17.0], ["TOPSPEED", "top", 54.0, 90.0], ["GRIP", "grip", 19.0, 38.0],
			["DRIFT", "drift", 0.0, 1.0]]:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 2)
		stats.add_child(hb)
		var l := UI.label(hb, 7, "wide", UI.DIM, 1)
		l.text = tr(row[0])
		l.custom_minimum_size = Vector2(80, 0)
		var n := int(round(clampf((st[row[1]] - row[2]) / (row[3] - row[2]), 0.05, 1.0) * 10.0))
		var n0 := int(round(clampf((bs[row[1]] - row[2]) / (row[3] - row[2]), 0.05, 1.0) * 10.0))
		for k in 10:
			var seg := ColorRect.new()
			seg.custom_minimum_size = Vector2(7 if compact else 9, 3)
			seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if k < mini(n, n0):
				seg.color = Color(0.86, 0.88, 0.92)
			elif k < n:
				seg.color = UI.ACCENT  # Gewinn durch das Teil in der Vorschau
			elif k < n0:
				seg.color = UI.LOSS  # Verlust
			else:
				seg.color = Color(1, 1, 1, 0.1)
			hb.add_child(seg)
	if not compact:
		var top := UI.label(stats, 7, "wide", UI.DIM, 1, HORIZONTAL_ALIGNMENT_RIGHT)
		top.text = "%d KM/H" % int(st["top"] * 3.6)


func _set_section(text: String, with_stats := false) -> void:
	section.text = tr(text)
	var card := _stats_card
	if with_stats and not card.visible:
		_fade_in(card)
	card.visible = with_stats
	if with_stats:
		_show_stats(preview_car, preview_cfg)
		_place_stats()
		_place_stats.call_deferred()  # unter der Liste: erst wenn alle Einträge stehen


## Wertekarte so legen, dass sie das Auto nicht verdeckt: im Tuning klein oben rechts unter der Statuszeile, sonst
## links unter den Einträgen der Liste (bis 2.37 oben rechts über dem Auto)
func _place_stats() -> void:
	var card := _stats_card
	card.anchor_top = 0.0
	card.anchor_bottom = 0.0
	if _strip_mode:
		card.anchor_left = 1.0
		card.anchor_right = 1.0
		card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		card.offset_left = -14.0 - 200.0
		card.offset_right = -14.0
		card.offset_top = 32.0
	else:
		card.anchor_left = 0.0
		card.anchor_right = 0.0
		card.grow_horizontal = Control.GROW_DIRECTION_END
		card.offset_left = 14.0
		card.offset_right = 14.0 + menu.custom_minimum_size.x
		card.offset_top = menu_scroll.offset_top + menu.get_combined_minimum_size().y + 12.0
	card.offset_bottom = card.offset_top


## Fläche weich einblenden (Wertekarte, Karte), statt sie hart erscheinen zu lassen
func _fade_in(c: CanvasItem) -> void:
	c.modulate.a = 0.0
	create_tween().tween_property(c, "modulate:a", 1.0, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


var _cam_view := ""  # "" = ganzes Auto (Garage, Autohaus, Tuning-Übersicht), sonst Kategorie, deren Teil die Kamera zeigt
var _cam_pos := Vector3(5.0, 1.4, -4.0)
var _cam_look := Vector3(0, 0.6, 0)
var _cam_snap := true  # erstes Bild: Kamera gleich am Ziel statt heranzufliegen
var _cam_shift := Vector2.ZERO  # Lage des Ziels im Bild (-1 … 1, y nach oben), über die Objektivverschiebung
var _work_light: OmniLight3D  # Arbeitslicht an der Kamera für Nahaufnahmen (Felgen, Motor)
## Brennweite: 30° senkrecht (wie ein 45-mm-Normalobjektiv) statt 50° bis 2.38 (26-mm-Weitwinkel). Der Weitwinkel aus
## der Nähe zog die Front in die Länge, von schräg vorn wirkte jede Haube viel zu lang. Die Kamera steht dafür gut
## 1,7-mal so weit weg (_fit_car rechnet den Abstand) und bleibt dabei in der Halle (_hall_room).
const CAM_FOV := 30.0
## Nahansichten (_view_for) sind für 50° gemessen: tan(25°) / tan(15°) = 1,74-mal so weit weg zeigen sie das Teil gleich
## groß. Gut 8 % weniger, damit Felgen, Haube, Auspuff und Licht groß im Bild bleiben.
const CLOSE_K := 1.6
const WORK_LIGHT := 1.7  # Arbeitslicht in Nahansichten (1.0 bis 2.38, die Kamera stand nur gut halb so weit weg)
var _cam_fov := CAM_FOV  # Bildwinkel gerade (nur größer, wenn die Halle für den Abstand nicht reicht, _fit_car)

## Ansichten mit dem ganzen Auto: [Azimut, Höhe] in Grad (Azimut 0 = von vorn, 90 = von der Seite, 180 = von hinten;
## die Kamera steht links vom Auto, siehe _cam_goal). Die Kamera rahmt das Auto darin selbst ein (_fit_car): so groß wie
## möglich, ohne dass Kopf, Leiste, Farbraster oder Infofeld es verdecken, bei jedem Auto gleich (Chibi wie Raiden).
const FULL_VIEWS := {"paint": [40.0, 8.0], "finish": [52.0, 17.0], "vinyl": [80.0, 15.0], "vinylcol": [80.0, 15.0],
	"tint": [58.0, 8.0], "neon": [66.0, 3.5], "bodykit": [32.0, 5.0]}


## Kamerapunkt und Blickziel je Tuning-Kategorie für Nahansichten, am Auto gemessen (vorn -Z, rechte Seite +X; _cam_goal
## spiegelt sie auf die linke Seite). Lack, Lackart, Folierung, Scheiben, Neon und Bodykit zeigen seit 2.38 das ganze Auto
## (FULL_VIEWS).
func _view_for(cat: String) -> Array:
	var spec: Dictionary = Catalog.CARS[preview_car]
	var L: float = spec["length"]
	var W: float = spec["width"]
	var fz := -(L / 2.0 - Builder.axle(Builder.SHAPES.get(preview_car, {})))
	# Mittelmotor: Motor hinten, Kofferraum (Nitro) vorn
	if Builder.engine_rear(Builder.SHAPES.get(preview_car, {})) and cat in ["engine", "turbo", "nitro"]:
		cat = "nitro" if cat != "nitro" else "engine"
	match cat:
		"rims", "rimcol", "rimsize", "tires":
			return [Vector3(W / 2.0 + 1.3, 0.45, fz - 0.9), Vector3(W / 2.0, 0.32, fz)]
		"spur":
			# hinter dem Hinterrad, flach an der Flanke entlang nach vorn: wie weit die Räder unter den Kotflügeln stehen
			# (seit 2.37)
			return [Vector3(W / 2.0 + 0.65, 0.42, -fz + 2.1), Vector3(W / 2.0 - 0.1, 0.34, -fz)]
		"suspension":
			return [Vector3(W / 2.0 + 1.6, 0.55, fz - 0.6), Vector3(W / 2.0 - 0.1, 0.42, fz + 0.1)]
		"spoiler":
			return [Vector3(1.7, 1.55, L / 2.0 + 1.7), Vector3(0.0, 0.95, L / 2.0 - 0.35)]
		"plate":
			# Kennzeichen (seit 2.50): von hinten, leicht seitlich auf Höhe des Schilds
			return [Vector3(0.9, 0.75, L / 2.0 + 1.9), Vector3(0.0, 0.42, L / 2.0)]
		"hood":
			return [Vector3(1.6, 1.9, -L / 2.0 - 1.9), Vector3(0.0, 0.75, -L / 2.0 + 1.0)]
		"exhaust":
			return [Vector3(1.4, 0.6, L / 2.0 + 1.6), Vector3(0.0, 0.3, L / 2.0)]
		"lights":
			return [Vector3(2.0, 0.9, -L / 2.0 - 2.6), Vector3(0.0, 0.5, -L / 2.0)]
		# Motor und Kofferraum seit 2.38 etwas weiter weg: die offene Haube bzw. Klappe steht zwischen Infofeld und Werten
		"engine", "turbo":
			return [Vector3(1.35, 2.1, -L / 2.0 - 1.7), Vector3(0.0, 0.8, -L / 2.0 + 0.85)]
		"nitro":
			return [Vector3(1.1, 2.45, L / 2.0 + 1.9), Vector3(0.0, 0.82, L / 2.0 - 0.7)]
	return [Vector3(3.6, 1.6, -4.0), Vector3(0.0, 0.6, 0.0)]


## Blickrichtung (vom Auto zur Kamera) für Ansichten mit dem ganzen Auto, sonst null (Nahansicht eines Teils).
## Garage: langsam von schräg vorn über die Seite bis schräg hinten und zurück; Autohaus: schräg vorn, ein neues Auto
## kommt von rechts herein; Tuning-Übersicht schräg vorn. Alles mit leichtem Pendeln.
func _full_dir():
	var az := 0.0
	var el := 0.0
	if _cam_view == "":
		if _strip_mode:
			az = 38.0 + 5.0 * sin(_t * 0.13)
			el = 11.0
		elif _in_cars:
			az = 66.0 + 6.0 * sin(_t * 0.15)
			el = 9.0
		else:
			az = 82.0 + 44.0 * sin(_t * 0.085)
			el = 10.0 + 2.0 * sin(_t * 0.05)
	elif FULL_VIEWS.has(_cam_view):
		az = FULL_VIEWS[_cam_view][0] + 4.0 * sin(_t * 0.12)
		el = FULL_VIEWS[_cam_view][1]
	else:
		return null
	var a := deg_to_rad(az)
	var e := deg_to_rad(el)
	return Vector3(-sin(a) * cos(e), sin(e), -cos(a) * cos(e))  # linke Seite des Autos, siehe _cam_goal


## Freie Fläche fürs Auto in UI-Pixeln. Tuning: zwischen Kopf (Titel und Infofeld links, Werte rechts) und Leiste bzw.
## Farbraster; die oberen Ecken bleiben dem Text, dort ist ein Auto ohnehin niedriger als in der Mitte. Sonst rechts
## neben der Liste, über dem Infofeld und links von der Deutschlandkarte.
func _free_rect() -> Rect2:
	var s := _ui_size()
	if _strip_mode:
		var bottom := s.y - 92.0
		if color_grid and is_instance_valid(color_grid) and color_grid.size.y > 1.0:
			bottom = minf(bottom, color_grid.position.y - 8.0)
		return Rect2(26.0, 86.0, s.x - 52.0, maxf(bottom - 86.0, 60.0))
	var x0 := menu_scroll.offset_right + 6.0
	var x1 := s.x - 18.0
	if career_map.visible:
		x1 = minf(x1, s.x + career_map.offset_left - 8.0)
	var bottom := s.y - 92.0
	if _info_panel.visible and _info_panel.size.y > 1.0:
		bottom = minf(bottom, _info_panel.position.y - 8.0)
	return Rect2(x0, 60.0, maxf(x1 - x0, 60.0), maxf(bottom - 60.0, 60.0))


func _ui_size() -> Vector2:
	return _ui.size if _ui and _ui.size.x > 1.0 and _ui.size.y > 1.0 else Vector2(640, 360)


## Sichtkegel (Bildwinkel fov senkrecht) und freie Fläche in Bildkoordinaten (-1 … 1, y nach oben): [tan_h, tan_v, u0,
## u1, v0, v1, halbe Breite, halbe Höhe, Mitte u, Mitte v]
func _frustum(rect: Rect2, fov: float) -> Array:
	var s := _ui_size()
	var tv := tan(deg_to_rad(fov) * 0.5)
	var th := tv * s.x / s.y
	var u0 := rect.position.x / s.x * 2.0 - 1.0
	var u1 := rect.end.x / s.x * 2.0 - 1.0
	var v0 := 1.0 - rect.end.y / s.y * 2.0
	var v1 := 1.0 - rect.position.y / s.y * 2.0
	return [th, tv, u0, u1, v0, v1, (u1 - u0) / 2.0, (v1 - v0) / 2.0, (u0 + u1) / 2.0, (v0 + v1) / 2.0]


## Kamera, die das ganze Auto (Umriss _hull) in die freie Fläche setzt: der kleinste Abstand, bei dem das Bild des
## Umrisses hineinpasst (Halbierungssuche, Start bei einer sicheren Lösung), dann per Objektivverschiebung mittig in die
## Fläche geschoben (der Blickwinkel bleibt). dir zeigt vom Auto zur Kamera. Rückgabe [Kamerapunkt, Blickziel, Lage des
## Ziels im Bild u, v, Bildwinkel]. Gerechnet wird nur, wenn sich Richtung, Fläche oder Auto merklich geändert haben.
## Reicht die Halle für den Abstand nicht (seit 2.39 mit 30° statt 50°: in der Karriere ist zwischen Liste und Karte nur
## eine schmale Lücke), wird der Bildwinkel gerade so weit größer, dass das Auto trotzdem ganz hineinpasst.
var _fit_key := []
var _fit_out := []
var _fit_hi := 4.0  # Abstand der letzten Rechnung


func _fit_car(dir: Vector3, rect: Rect2) -> Array:
	var z := dir.normalized()
	var blocks := _blocks()
	if not _fit_key.is_empty() and _fit_key[0] == _hull and (_fit_key[1] as Rect2).is_equal_approx(rect) \
			and (_fit_key[2] as Vector3).dot(z) > 0.99995 and _fit_key[3] == blocks:
		# Abstand und Verschiebung ändern sich mit der Richtung kaum, die Lage aber in jedem Bild (sonst bliebe die
		# Kamera beim langsamen Schwenk in der Garage kurz stehen und spränge dann um gut ein halbes Grad)
		return [_hull_c + z * _fit_hi, _hull_c, _fit_out[2], _fit_out[3], _fit_out[4]]
	var fov := CAM_FOV
	var r := _fit_at(z, rect, blocks, fov)
	for it in 2:
		# Platz in der Halle: Abstand bis zur Wand (bzw. Grenze) auf der Linie zur Kamera, gemessen in der Halle
		var room := _hall_room(stand.transform * _hull_c, stand.transform * (_hull_c + z * float(r[0])))
		if room >= 0.995:
			break
		# Abstand und tan(Bildwinkel / 2) gehen umgekehrt: um so viel weiter muss der Bildwinkel werden
		fov = minf(rad_to_deg(2.0 * atan(tan(deg_to_rad(fov) * 0.5) / maxf(room, 0.2))), 60.0)
		r = _fit_at(z, rect, blocks, fov)
	_fit_key = [_hull, rect, z, blocks]
	_fit_hi = r[0]
	_fit_out = [_hull_c + z * float(r[0]), _hull_c, r[1], r[2], fov]
	return _fit_out


## Halbierungssuche für _fit_car bei Bildwinkel fov: [Abstand, Lage des Ziels im Bild u, v]
func _fit_at(z: Vector3, rect: Rect2, blocks: Array, fov: float) -> Array:
	var f := _frustum(rect, fov)
	var x := Vector3.UP.cross(z).normalized()
	var y := z.cross(x)
	var th: float = f[0]
	var tv: float = f[1]
	var hw: float = f[6]
	var hh: float = f[7]
	var cs := PackedVector3Array()
	var hi := 2.0
	for p in _hull:
		var r: Vector3 = p - _hull_c
		var c := Vector3(r.dot(x), r.dot(y), r.dot(z))
		cs.append(c)
		hi = maxf(hi, maxf(absf(c.x) / (hw * th), absf(c.y) / (hh * tv)) + c.z)  # passt sicher (Ziel in der Mitte)
	# Felder in den oberen Ecken (Infofeld links, Werte rechts): dort darf auch ein hoher Heckflügel nicht hineinragen
	hi = minf(hi * (1.25 if not blocks.is_empty() else 1.0), 30.0)
	var lo := hi * 0.35
	for it in 13:
		var d := (lo + hi) * 0.5
		var e := _extent(cs, d, th, tv)
		var ok := e.y - e.x <= 2.0 * hw and e.w - e.z <= 2.0 * hh
		if ok and not blocks.is_empty():
			ok = not _hits(cs, d, th, tv, Vector2(float(f[8]) - (e.x + e.y) * 0.5, float(f[9]) - (e.z + e.w) * 0.5), blocks)
		if ok:
			hi = d
		else:
			lo = d
	var ex := _extent(cs, hi, th, tv)
	return [hi, float(f[8]) - (ex.x + ex.y) * 0.5, float(f[9]) - (ex.z + ex.w) * 0.5]


## Flächen der Oberfläche, die über der freien Fläche liegen (Tuning: Infofeld oben links, Werte oben rechts), in
## Bildkoordinaten (u0, v0, u1, v1), mit etwas Rand
func _blocks() -> Array:
	var out := []
	if not _strip_mode:
		return out
	var s := _ui_size()
	for c in [_info_panel, _stats_card]:
		var ctl := c as Control
		if ctl.visible and ctl.size.y > 1.0:
			var r := ctl.get_rect().grow(4.0)
			out.append(Vector4(r.position.x / s.x * 2.0 - 1.0, 1.0 - r.end.y / s.y * 2.0, r.end.x / s.x * 2.0 - 1.0, 1.0 - r.position.y / s.y * 2.0))
	return out


## Liegt ein Punkt des Umrisses (bei Abstand d, Bild um shift verschoben) in einer der Flächen?
static func _hits(cs: PackedVector3Array, d: float, th: float, tv: float, shift: Vector2, blocks: Array) -> bool:
	for c in cs:
		var w := 1.0 / maxf(d - c.z, 0.05)
		var u := c.x * w / th + shift.x
		var v := c.y * w / tv + shift.y
		for b in blocks:
			if u > b.x and u < b.z and v > b.y and v < b.w:
				return true
	return false


## Ausdehnung des Umrisses im Bild (ohne Verschiebung) bei Abstand d: (u min, u max, v min, v max)
static func _extent(cs: PackedVector3Array, d: float, th: float, tv: float) -> Vector4:
	var e := Vector4(INF, -INF, INF, -INF)
	for c in cs:
		var w := 1.0 / maxf(d - c.z, 0.05)
		var u := c.x * w / th
		var v := c.y * w / tv
		e.x = minf(e.x, u)
		e.y = maxf(e.y, u)
		e.z = minf(e.z, v)
		e.w = maxf(e.w, v)
	return e


## Kamera im Abstand d vom Ziel in Richtung z, das Ziel erscheint in der Mitte der freien Fläche
func _place(target: Vector3, z: Vector3, d: float, f: Array) -> Array:
	return [target + z * d, target, float(f[8]), float(f[9]), CAM_FOV]


## Ziel der Kamera in Hallenkoordinaten. Gerechnet wird am Auto (vorn -Z), und zwar auf seiner linken Seite: der
## Stellplatz ist um 180° gedreht, das Auto zeigt mit der Front nach links zum Menü, ein neues kommt rechts von hinten
## herein und das alte fährt links hinaus. Hinter dem Auto steht so die Werkzeugwand. Die Nahansichten aus _view_for
## (für die rechte Seite beschrieben) werden dafür gespiegelt.
func _cam_goal() -> Array:
	var rect := _free_rect().grow(-6.0)
	var dir = _full_dir()
	var g: Array
	if dir != null:
		g = _fit_car(dir, rect).duplicate()
	else:
		var v := _view_for(_cam_view)
		var m := Vector3(-1.0, 1.0, 1.0)
		var to: Vector3 = (v[0] - v[1]) * m
		g = _place(v[1] * m, to.normalized(), to.length() * CLOSE_K, _frustum(rect, CAM_FOV))
	g[0] = stand.transform * (g[0] as Vector3)
	g[1] = stand.transform * (g[1] as Vector3)
	# Sicherheitsnetz: was trotzdem hinter einer Wand läge, rückt auf der Linie zum Blickziel heran
	g[0] = (g[1] as Vector3) + ((g[0] as Vector3) - (g[1] as Vector3)) * _hall_room(g[1], g[0])
	return g


## Wie weit die Kamera auf der Linie vom Blickziel look zu pos in der Halle bleibt (1 = ganz, 0,5 = nur bis zur Hälfte):
## vor den Stirnwänden mit den Toren, vor der Rückwand, unter 5,6 m; zur offenen Seite der Halle (dort steht keine
## Wand, die Kamera schaut immer zur Werkzeugwand) bis 16 m
static func _hall_room(look: Vector3, pos: Vector3) -> float:
	var d := pos - look
	var s := 1.0
	var lim := Vector3(16.0, 5.6, GarageSet.END_Z - 0.6)
	if absf(d.z) > 0.001:
		s = minf(s, (signf(d.z) * lim.z - look.z) / d.z)
	if d.x > 0.001:
		s = minf(s, (lim.x - look.x) / d.x)
	elif d.x < -0.001:
		s = minf(s, (GarageSet.BACK_X + 0.6 - look.x) / d.x)
	if d.y > 0.001:
		s = minf(s, (lim.y - look.y) / d.y)
	return clampf(s, 0.2, 1.0)


func _label(parent: Node, size: int, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	return UI.label(parent, size, "bold", UI.TEXT, 0, align)


func _process(dt: float) -> void:
	_t += dt
	_update_preview(dt)
	_tip_t += dt
	if _tip_t > 8.0:
		# Tipp wechselt mit kurzer Blende statt zu springen
		_tip_t = 0.0
		_tip_i = (_tip_i + 1) % TIPS.size()
		var tw := create_tween()
		tw.tween_property(tip, "modulate:a", 0.0, 0.25)
		tw.tween_callback(func(): tip.text = tr("TIPP: ") + tr(TIPS[_tip_i]))
		tw.tween_property(tip, "modulate:a", 1.0, 0.35)
	_roll_road(dt)
	# Kamera gleitet zur Ansicht (ganzes Auto oder Teil), das Auto bleibt dabei in der freien Fläche
	var g := _cam_goal()
	var k := 1.0 if _cam_snap else 1.0 - exp(-dt * 3.5)
	_cam_snap = false
	_cam_pos = _cam_pos.lerp(g[0], k)
	_cam_look = _cam_look.lerp(g[1], k)
	_cam_shift = _cam_shift.lerp(Vector2(g[2], g[3]), k)
	_cam_fov = lerpf(_cam_fov, g[4], k)
	cam.fov = _cam_fov
	var tv := tan(deg_to_rad(cam.fov) * 0.5)
	cam.size = 2.0 * cam.near * tv
	cam.frustum_offset = Vector2(-_cam_shift.x * tv * _ui_size().x / _ui_size().y, -_cam_shift.y * tv) * cam.near
	cam.position = _cam_pos
	cam.look_at(_cam_look)
	_work_light.light_energy = lerpf(_work_light.light_energy, 0.0 if _full_dir() != null else WORK_LIGHT, k)
	var st := tr("LEVEL %d   ·   %s   ·   SIEGE %d   ·   %s") % [GameState.level(), GameState.title_name().to_upper(), GameState.wins + GameState.drift_wins,
		Catalog.CARS[GameState.current_car]["name"].to_upper()]
	if st != _status_text:
		_status_text = st
		status.text = st
		_xp_line.queue_redraw()


# --- Rollenprüfstand (seit 2.38) --------------------------------------------------------------------------------------
## Das Auto fährt auf einem Laufband auf der Stelle: die Räder drehen im Reisetempo, das Band läuft unter ihm nach hinten,
## Spiegelungen ziehen über den Lack, die Federung arbeitet leicht. Seit 2.39 liegt das Band bündig im Boden und reicht
## von Tor zu Tor (garage_set.gd): man sieht es nicht, das Auto fährt einfach in der Halle. Wo man an den Rädern oder aus
## der Nähe an einem Teil arbeitet (STOP_CATS), rollt es sanft aus und hält mit kurz aufleuchtenden Bremslichtern; zurück
## in einer Ansicht mit dem ganzen Auto fährt es wieder an. Ein anderes Auto fährt hinten durchs Tor herein und bremst
## auf seinen Platz, das bisherige fährt vorn hinaus: beide auf dem Band, das durch beide Tore läuft.
const CRUISE := 7.0  # m/s auf dem Band (gut 25 km/h)
## Räder (Felgen, Felgenfarbe, Zoll, Spur, Reifen) und Arbeit aus der Nähe (Fahrwerk, Motor, Turbo, Nitro bei offener
## Haube bzw. Klappe, Motorhaube, Auspuff, Spoiler, Scheinwerfer): hier steht das Auto still
const STOP_CATS := ["rims", "rimcol", "rimsize", "spur", "tires", "suspension", "engine", "turbo", "nitro", "hood", "exhaust",
	"spoiler", "lights"]
const IN_FROM := 11.5  # Einfahrt beginnt am hinteren Tor (Mitte des Autos, m hinter dem Stellplatz)
const IN_TIME := 1.25  # s bis zum Stillstand auf dem Platz (bei schnellem Wechsel kürzer)
const OUT_ACC := 13.0  # m/s² beim Hinausfahren
var _hall := {}  # GarageSet.build: belt, rotor, glints
var _belt_v := 0.0  # Tempo des Bands (m/s)
var _belt_a := 0.0
var _belt_x := 0.0  # Weg des Bands (m), für das Muster (wiederholt sich nach 32 m, garage_floor.gdshader)
var _glint_u := 0.0  # Lage der wandernden Spiegelungen (0 … 1)
var _roll: RollCar  # Auto auf dem Stellplatz bzw. auf dem Weg dorthin
var _leaving: Array = []  # Autos, die vorn hinausfahren (höchstens zwei)
var _shown_id := ""
var _shown_cfg := {}
var _switch_ms := -100000  # letzter Autowechsel (schnell hintereinander: kürzere Einfahrt)
var _hull := PackedVector3Array()  # Umriss des Autos auf dem Platz (Kamera, _car_hull)
var _hull_c := Vector3(0.0, 0.6, 0.0)  # seine Mitte


## Ein Auto auf dem Prüfstand: Lage entlang des Bands (z, + hinten), Tempo gegenüber der Halle (v, vorwärts positiv),
## Bremslichter, Nicken der Karosserie als gedämpfte Feder, leichtes Wippen beim Fahren
class RollCar:
	var node: Node3D
	var body: Node3D
	var body_y := 0.0
	var lamps := []  # [Material, Grundhelligkeit] der roten Leuchten
	var glow: StandardMaterial3D  # Leuchthof hinten
	var glow_c := Color.BLACK
	var spill: OmniLight3D  # roter Schein der Bremslichter auf dem Boden hinter dem Auto (auch von vorn zu sehen)
	var phase := 0  # 0 auf dem Platz, 1 fährt herein, 2 fährt hinaus
	var leave_after := false  # fährt noch herein, soll danach gleich wieder hinaus (schnelles Blättern)
	var z := 0.0
	var v := 0.0
	var t := 0.0
	var dur := 1.0
	var z0 := 0.0
	var pitch := 0.0
	var pitch_v := 0.0
	var brake := 0.0
	var seed := 0.0

	func _init(n: Node3D) -> void:
		node = n
		body = n.get_meta("body")
		body_y = body.position.y
		seed = randf() * 50.0
		spill = OmniLight3D.new()
		spill.light_color = Color(1.0, 0.07, 0.03)
		spill.light_energy = 0.0
		spill.light_specular = 0.2
		spill.omni_range = 2.6
		spill.light_cull_mask = 0xFFFFF & ~Builder.CAR_LAYER  # nur Band und Boden, nicht das Auto selbst
		spill.position = Vector3(0, 0.3, float(n.get_meta("length")) / 2.0 + 0.45)
		spill.visible = false
		n.add_child(spill)
		var seen := {}
		var stack: Array = [n]
		while not stack.is_empty():
			var nd: Node = stack.pop_back()
			stack.append_array(nd.get_children())
			if not nd is MeshInstance3D:
				continue
			var mi := nd as MeshInstance3D
			if mi.has_meta("glow") and float(mi.get_meta("glow")) > 0.0 and mi.material_override is StandardMaterial3D:
				glow = mi.material_override
				glow_c = glow.albedo_color
			var ms := [mi.material_override]
			if mi.mesh:
				for si in mi.mesh.get_surface_count():
					ms.append(mi.get_surface_override_material(si))
					ms.append(mi.mesh.surface_get_material(si))
			for m in ms:
				# Rückleuchten, Bremsleuchte, Lichtbänder: rot leuchtend (Blinker sind orange, das Neon hat kein Leuchten)
				if m is StandardMaterial3D and not seen.has(m) and m.emission_enabled and m.emission.r > 0.6 and m.emission.g < 0.2:
					seen[m] = true
					lamps.append([m, m.emission_energy_multiplier])

	func arrive(from: float, time: float, delay: float) -> void:
		phase = 1
		z0 = from
		dur = time
		t = -delay
		z = from
		v = 2.0 * from / time
		node.position.z = z
		node.visible = delay <= 0.0

	## Lage, Tempo und Federung eines Vorgängers übernehmen (gleiches Auto mit anderen Teilen)
	func take(o: RollCar) -> void:
		phase = o.phase
		z = o.z
		v = o.v
		t = o.t
		dur = o.dur
		z0 = o.z0
		pitch = o.pitch
		pitch_v = o.pitch_v
		brake = o.brake
		node.position.z = z
		node.visible = o.node.visible

	func step(dt: float, belt: float, belt_a: float, now: float) -> void:
		var acc := 0.0  # gegenüber der Halle, vorwärts positiv
		if phase == 1:
			t += dt
			if t < 0.0:
				return  # wartet hinter dem Tor, bis der Vorgänger Platz gemacht hat
			node.visible = true
			var u := minf(t / dur, 1.0)
			z = z0 * (1.0 - u) * (1.0 - u)  # gleichmäßig gebremst bis zum Stillstand auf dem Platz
			v = 2.0 * z0 * (1.0 - u) / dur
			acc = -2.0 * z0 / (dur * dur)
			if u >= 1.0:
				phase = 2 if leave_after else 0
				t = 0.0
				z = 0.0
				v = 0.0
				acc = 0.0
		elif phase == 2:
			t += dt
			acc = OUT_ACC
			v += acc * dt
			z -= v * dt
		node.position.z = z
		var wheel := belt + v
		var braking := acc < -1.0 or belt_a < -0.8
		brake = move_toward(brake, 1.0 if braking else 0.0, dt * (14.0 if braking else 3.0))
		# Nicken: Feder (1,4 Hz, wenig gedämpft) zur Lage, die die Beschleunigung vorgibt: beim Bremsen geht der Bug runter,
		# beim Anhalten federt er zurück
		var target := clampf((acc + belt_a * 0.6) * 0.0024, -0.03, 0.03)
		var w := 8.8
		pitch_v += (-(pitch - target) * w * w - 2.0 * 0.3 * w * pitch_v) * dt
		pitch += pitch_v * dt
		var k := clampf(wheel / CRUISE, 0.0, 1.0)
		Builder.animate(node, wheel, 0.0, 0.0, 0.0, false, dt)
		body.rotation.x = pitch + 0.0016 * sin(now * 5.1 + seed) * k
		body.rotation.z = 0.0014 * sin(now * 4.3 + seed * 1.3) * k
		body.position.y = body_y + 0.0024 * (sin(now * 7.3 + seed) * 0.6 + sin(now * 12.1 + seed * 1.7) * 0.4) * k
		for e in lamps:
			(e[0] as StandardMaterial3D).emission_energy_multiplier = float(e[1]) * (1.0 + 1.6 * brake)
		if glow:
			var gm := 1.0 + 1.4 * brake
			glow.albedo_color = Color(glow_c.r * gm, glow_c.g * gm, glow_c.b * gm, glow_c.a)
		spill.visible = brake > 0.01
		spill.light_energy = 1.6 * brake

	## Lage nach tt Sekunden (für die Einfahrt des Nachfolgers): beim Hinausfahren gleichmäßig schneller, ein Auto, das
	## noch hereinfährt und danach gleich wieder hinaus soll, erst bis auf seinen Platz, dann von dort hinaus
	func z_at(tt: float) -> float:
		if phase == 2:
			return z - v * tt - 0.5 * OUT_ACC * tt * tt
		if phase != 1:
			return z
		var ta := t + tt
		if ta < dur:
			var u := maxf(ta, 0.0) / dur
			return z0 * (1.0 - u) * (1.0 - u)
		if not leave_after:
			return 0.0
		return -0.5 * OUT_ACC * (ta - dur) * (ta - dur)


## Laufband, Gebläse, Spiegelungen und Autos je Bild. Das Band folgt seinem Ziel (Reisetempo oder Stillstand) als
## kritisch gedämpfte Feder: weich anfahren, weich ausrollen, auch wenn das Ziel beim Blättern unterwegs wechselt.
func _roll_road(dt: float) -> void:
	var target := 0.0 if _cam_view in STOP_CATS else CRUISE
	var w := 4.4 if target < _belt_v else 3.0  # Anhalten in gut einer Sekunde, Anfahren etwas gemächlicher
	_belt_a += ((target - _belt_v) * w * w - 2.0 * w * _belt_a) * dt
	_belt_v = maxf(_belt_v + _belt_a * dt, 0.0)
	if absf(target - _belt_v) < 0.01 and absf(_belt_a) < 0.05:
		_belt_v = target
		_belt_a = 0.0
	_belt_x = fmod(_belt_x + _belt_v * dt, 32.0)
	var bm: ShaderMaterial = _hall["belt"]
	bm.set_shader_parameter("offset", _belt_x)
	bm.set_shader_parameter("blur", _belt_v * dt)
	(_hall["rotor"] as Node3D).rotation.z -= _belt_v * dt * 2.4
	# zwei Lichter, die nur das Auto treffen, ziehen mit dem Band von vorn nach hinten: Spiegelungen wandern über Dach,
	# Haube und Flanke wie Lampen bei der Fahrt; im Stand blenden sie aus
	var span := 9.0
	_glint_u = fmod(_glint_u + _belt_v * dt / span, 1.0)
	var gl: Array = _hall["glints"]
	for i in gl.size():
		var l: OmniLight3D = gl[i]
		var u := fposmod(_glint_u + i * 0.5, 1.0)
		# auf der Seite der Kamera, von der Front (+Z in der Halle) zum Heck
		l.position = Vector3(1.0 if i == 0 else 2.8, 2.4 if i == 0 else 1.0, span / 2.0 - u * span)
		l.light_energy = 0.4 * sin(PI * u) * clampf(_belt_v / CRUISE, 0.0, 1.0)
	if _roll:
		_roll.step(dt, _belt_v, _belt_a, _t)
	for i in range(_leaving.size() - 1, -1, -1):
		var rc: RollCar = _leaving[i]
		rc.step(dt, _belt_v, _belt_a, _t)
		if rc.z < -16.0 or rc.t > 3.5:
			rc.node.queue_free()
			_leaving.remove_at(i)


## Auto auf den Stand bringen. Gleiches Auto mit gleichen Teilen: bleibt stehen (nur Haube und Kofferraum zu); gleiches
## Auto mit anderen Teilen: tauscht an Ort und Stelle (Lage, Tempo, Federung bleiben); anderes Auto: das bisherige fährt
## vorn hinaus, das neue kommt hinten durchs Tor und bremst auf seinen Platz. Es wartet hinter dem Tor, bis der Vorgänger
## weit genug weg ist (nie ineinander), bei schnellem Wechsel ist die Einfahrt kürzer, und mehr als zwei Autos fahren
## nie zugleich hinaus.
func _show_car(car_id: String, cfg: Dictionary) -> void:
	if car_node and car_id == _shown_id and cfg == _shown_cfg:
		Builder.showcase(car_node, car_id, cfg, "")
		return
	var t0 := Time.get_ticks_usec()
	var node := Builder.build(car_id, cfg, false, false, false)
	stand.add_child(node)
	var rc := RollCar.new(node)
	var old := _roll
	if old != null:
		if car_id == _shown_id:
			rc.take(old)
			old.node.queue_free()
		else:
			var hurry := Time.get_ticks_msec() - _switch_ms < 1800
			_switch_ms = Time.get_ticks_msec()
			var from := IN_FROM * (0.8 if hurry else 1.0)
			var time := IN_TIME * (0.75 if hurry else 1.0)
			if old.phase == 1 and old.t < 0.0:
				old.node.queue_free()  # wartete noch hinter dem Tor
				var ahead: RollCar = _leaving.back() if not _leaving.is_empty() else null
				rc.arrive(from, time, _arrival_delay(ahead, node, from, time))
			else:
				if old.phase == 1:
					# fährt gerade herein: erst auf den Platz, dann gleich wieder vorn hinaus. Bis 2.38 fuhr es mit seiner
					# Einfahrt-Geschwindigkeit weiter und holte den Vordermann ein (zweimal schnell geblättert: zwei Autos
					# ineinander)
					old.leave_after = true
				else:
					old.phase = 2
					old.t = 0.0
				_leaving.append(old)
				while _leaving.size() > 2:
					(_leaving.pop_front() as RollCar).node.queue_free()
				rc.arrive(from, time, _arrival_delay(old, node, from, time))
	car_node = node
	_roll = rc
	_shown_id = car_id
	_shown_cfg = cfg.duplicate()
	# Umriss je Auto und Form merken: beim Blättern durch Farben ändert sich nichts daran (das Lesen der Karosserie
	# aus dem Grafikspeicher hält im Browser kurz an)
	var hk := _hull_key(car_id, cfg)
	if _hull_cache.has(hk):
		_hull = _hull_cache[hk]
	else:
		_hull = _car_hull(node)
		if _hull_cache.size() >= 32:
			_hull_cache.clear()
		_hull_cache[hk] = _hull
	var hb := AABB(_hull[0], Vector3.ZERO)
	for p in _hull:
		hb = hb.expand(p)
	_hull_c = hb.get_center()
	if OS.get_cmdline_user_args().has("--loadlog"):
		print("GARAGE build %s %.1f ms" % [car_id, (Time.get_ticks_usec() - t0) / 1000.0])


## Wie lange das neue Auto hinter dem Tor wartet, damit es den hinausfahrenden Vorgänger nie berührt (Abstand der
## Mitten mindestens halbe Längen beider plus 1,2 m über die ganze Einfahrt; der Vorgänger fährt dabei wie in z_at).
## Bis 2.38 waren es 40 cm: beim schnellen Blättern sah das aus, als führe das neue Auto dem alten fast hinten drauf.
func _arrival_delay(prev: RollCar, node: Node3D, from: float, time: float) -> float:
	if prev == null:
		return 0.0
	var need := (float(prev.node.get_meta("length")) + float(node.get_meta("length"))) / 2.0 + 1.2
	var delay := 0.0
	while delay < 3.0:
		var ok := true
		for i in 25:
			var tt := delay + time * i / 24.0
			var zo := prev.z_at(tt)
			var u := (tt - delay) / time
			if from * (1.0 - u) * (1.0 - u) - zo < need:
				ok = false
				break
		if ok:
			return delay
		delay += 0.05
	return delay


## Umriss des Autos für die Kamera, in seinen eigenen Koordinaten: die konvexe Hülle (in C++, Mesh.create_convex_shape)
## aus den Punkten der Karosserie (jeder vierte) und den Ecken aller übrigen Teile (Stoßfänger, Räder, Spoiler, Spiegel).
## Leuchthöfe und Neon-Lichtfleck zählen nicht (werfen keinen Schatten). Ein Quader wäre zu grob: von schräg oben ragen
## seine oberen Ecken weit über das Dach hinaus, das Auto stünde viel zu klein im Bild.
## Teile, die nur Farbe oder Licht ändern, nicht die Form (für den Merkzettel der Umrisse)
const LOOK_ONLY := ["paint", "finish", "rimcol", "vinyl", "vinylcol", "neon", "tint", "lights"]
static var _hull_cache := {}


static func _hull_key(car_id: String, cfg: Dictionary) -> String:
	var k := car_id
	for cat in Catalog.PART_ORDER:
		if not cat in LOOK_ONLY:
			k += ":%d" % int(cfg.get(cat, 0))
	return k


static func _car_hull(n: Node3D) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var stack: Array = [[n, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var e: Array = stack.pop_back()
		var xf: Transform3D = e[1]
		for c in (e[0] as Node).get_children():
			if not c is Node3D:
				continue
			var cx := xf * (c as Node3D).transform
			stack.append([c, cx])
			var mi := c as MeshInstance3D
			if mi == null or not mi.visible or mi.mesh == null or mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
				continue
			var bb := mi.mesh.get_aabb()
			if bb.size.length() > 2.5 and mi.mesh is ArrayMesh:
				for si in mi.mesh.get_surface_count():
					var vs: PackedVector3Array = mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX]
					for i in range(0, vs.size(), 4):
						pts.append(cx * vs[i])
			else:
				for k in 8:
					pts.append(cx * bb.get_endpoint(k))
	if pts.size() < 4:
		return PackedVector3Array([Vector3(-0.9, 0.0, -2.2), Vector3(0.9, 0.0, -2.2), Vector3(-0.9, 1.3, 2.2), Vector3(0.9, 1.3, 2.2)])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = pts
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arr)
	var hull: PackedVector3Array = am.create_convex_shape(true, false).points
	return hull if hull.size() >= 4 else pts


# --- Menüs ----------------------------------------------------------------

func _clear_menu() -> void:
	if color_grid:
		color_grid.queue_free()
		color_grid = null
	_info_panel.visible = true
	_in_cars = false
	_strip_on(false)
	career_map.visible = false
	menu_scroll.scroll_vertical = 0
	_menu_width(226.0)
	for c in menu.get_children():
		menu.remove_child(c)
		c.queue_free()


## Breite der Liste: 226, Einstellungen mit Wert rechts breiter (sonst würden lange Namen gekürzt)
func _menu_width(w: float) -> void:
	menu.custom_minimum_size.x = w
	menu_scroll.offset_right = 14.0 + w + 22.0


## Listeneintrag: Text links, "< Zurück" mit Abstand darüber und leiser, "Grafik  >" mit Pfeil rechts statt im Text
func _button(text: String, cb: Callable, disabled := false) -> Button:
	var b := Button.new()
	b.theme_type_variation = "MenuItem"
	var t := tr(text)
	var back := t.begins_with("< ")
	var more := t.ends_with(" >")
	if back:
		t = "‹  " + t.substr(2)
	if more:
		t = t.trim_suffix(">").strip_edges()
	b.text = t.to_upper()
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.disabled = disabled
	b.focus_entered.connect(func(): Sfx.ui("move"))
	b.pressed.connect(func(): _press_sound(b))
	b.pressed.connect(cb)
	if back and menu.get_child_count() > 0:
		_gap(6.0)
	menu.add_child(b)
	_item_fx(b)
	if back:
		b.add_theme_color_override("font_color", UI.DIM)
	if more:
		_row_value(b, "›")
	return b


## Abstand in der Liste (vor "Zurück", zwischen Gruppen)
func _gap(h: float) -> void:
	var g := Control.new()
	g.custom_minimum_size = Vector2(0, h)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(g)


## Auswahl-Effekt eines Listeneintrags: Strich und Verlauf wachsen ein (UI.menu_fx), der Text rückt dabei ein paar
## Pixel nach rechts; Maus darüber = Fokus. Jeder Eintrag hat eine eigene (leere) Fläche, deren Rand sich bewegt.
func _item_fx(b: Button) -> void:
	var box := StyleBoxEmpty.new()
	box.content_margin_left = 12.0
	box.content_margin_right = 12.0
	var pad := 5.0 if GameState.is_mobile() else 3.0  # Touch: etwas höhere Einträge zum Tippen
	box.content_margin_top = pad
	box.content_margin_bottom = pad
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		b.add_theme_stylebox_override(st, box)
	b.set_meta("box", box)
	UI.menu_fx(b, "left")
	var nudge := func(on: bool):
		if b.has_meta("nudge"):
			(b.get_meta("nudge") as Tween).kill()
		var tw := b.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(box, "content_margin_left", 15.0 if on else 12.0, 0.2 if on else 0.14)
		b.set_meta("nudge", tw)
	b.focus_entered.connect(nudge.bind(true))
	b.focus_exited.connect(nudge.bind(false))


## Wert rechts im Eintrag (Einstellungen, Titel, Autohaus): eigenes Label am rechten Rand; der Text links wird davor
## gekürzt. Mit Fokus hell, sonst leise; arrows: im Fokus "‹ WERT ›" (Links/Rechts ändert)
func _row_value(b: Button, text: String, col := UI.DIM, arrows := false) -> Label:
	var v: Label = b.get_node_or_null("V")
	if v == null:
		v = UI.label(b, 8, "wide", col, 1, HORIZONTAL_ALIGNMENT_RIGHT)
		v.name = "V"
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.offset_right = -10.0
		v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		v.label_settings.shadow_color = Color(0, 0, 0, 0)
		var paint := func():
			var on := b.has_focus()
			var base: String = v.get_meta("text", "")
			var c: Color = v.get_meta("col", UI.DIM)
			v.text = ("‹  " + base + "  ›") if on and v.get_meta("arrows", false) else base
			v.label_settings.font_color = UI.TEXT if on and c == UI.DIM else c
		v.set_meta("paint", paint)
		b.focus_entered.connect(paint)
		b.focus_exited.connect(paint)
	v.set_meta("text", text)
	v.set_meta("col", col)
	v.set_meta("arrows", arrows)
	(v.get_meta("paint") as Callable).call()
	var f := UI.font("wide", 0.0, 1)
	var w := f.get_string_size(("‹  " + text + "  ›") if arrows else text, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x
	(b.get_meta("box") as StyleBox).content_margin_right = w + 18.0
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return v


## Fokus setzen, falls der Knopf noch da ist (Menüs wechseln manchmal im selben Bild)
func _grab(c: Control) -> void:
	if is_instance_valid(c) and c.is_inside_tree():
		c.grab_focus()


## Menüwechsel: Liste und Titel blenden in ~0,2 s ein, die Liste rückt dabei ein kleines Stück von links nach
func _focus_first() -> void:
	_menu_in()
	for c in menu.get_children():
		if c is Button and not c.disabled:
			_grab.call_deferred(c)
			return


var _menu_tw: Tween


func _menu_in() -> void:
	if _menu_tw:
		_menu_tw.kill()
	menu.modulate.a = 0.0
	menu_scroll.position.x = 4.0
	section.modulate.a = 0.0
	_menu_tw = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_menu_tw.tween_property(menu_scroll, "position:x", 14.0, 0.22)
	_menu_tw.tween_property(menu, "modulate:a", 1.0, 0.2)
	_menu_tw.tween_property(section, "modulate:a", 1.0, 0.24)


func _show_main() -> void:
	GameState.split = false  # Splitscreen gilt nur für das gewählte Rennen (und NOCHMAL)
	if GameState.world_menu != "":
		# aus der Open World gekommen (Tuning, Autohaus): zurück dorthin statt ins Hauptmenü
		GameState.world_menu = ""
		_starting = true
		get_tree().change_scene_to_file("res://scenes/world.tscn")
		return
	_clear_menu()
	_back = Callable()
	_cam_view = ""
	preview_car = GameState.current_car
	preview_cfg = GameState.get_config(preview_car).duplicate()
	_show_car(preview_car, preview_cfg)
	_set_section("GARAGE", true)
	# Seit 2.28: Open World statt Rennen-Liste. Die Rennen findet man als Marker in den Städten. Seit 2.42 ohne Auswahl
	# der Startstadt: es geht dort weiter, wo man zuletzt war (world.gd, GameState.world_pos)
	_button("Losfahren", _drive_world)
	if not OS.has_feature("web") and not GameState.touch_ui():  # Splitscreen nur am Rechner (seit 2.47)
		_button("Zu zweit", _show_split)
	_button("Tuning", _show_tuning)
	_button("Auto wechseln", _show_cars)
	_button("Fahrer", _show_driver)
	_button("Einstellungen", _show_settings)
	if not OS.has_feature("web"):  # im Browser schließt man einfach den Tab
		_button("Beenden", func(): get_tree().quit())
	info.text = tr(Catalog.CARS[preview_car]["desc"]) + "\nF / F11: " + tr("Vollbild")
	if not GameState.save_persistent():
		info.text = tr("Achtung: Dein Browser speichert hier keinen Spielstand. Öffne das Spiel über den Knopf oben rechts in einem eigenen Tab, dann bleibt dein Fortschritt erhalten.") + "\n\n" + info.text
	_focus_first()


const CREDITS_TEXT := "Motorklänge aus echten Aufnahmen (Wikimedia Commons, CC BY 3.0/4.0): prone, Y Racing, Tyler Riddle, Great Explorer, NEW CARS 2015 Official, Fabio Rojas Pichardo, Taz Ringer, asTUBE, Super Cars for you, Work With Sounds / Technisches Museum Slowenien. Reifenquietschen: Joseph Sardin, BigSoundBank (CC0). Bahnübergang: Renardo la vulpo (CC0), Work With Sounds / Konrad Gutkowski (CC BY 4.0), Extemporalist (CC0). Musik: Pixabay; in Aachen „AC“ von Bruder Jakob x Jonas Platin (mit Genehmigung). Schrift: Inter (Rasmus Andersson, OFL), D-DIN (Datto, OFL). Karten © OpenStreetMap-Mitwirkende."

## Erklärung je Einstellung (unten im Infofeld)
const SETTING_HINTS := {
	"vol_music": "Lautstärke der Musik.",
	"vol_sfx": "Lautstärke von Motor, Reifen, Verkehr und Menütönen.",
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
	_menu_width(280.0)
	_back = _show_main
	_set_section("EINSTELLUNGEN")
	var g := _button("Grafik  >", _show_graphics)
	g.focus_entered.connect(func(): info.text = tr(SETTING_HINTS["graphics"]))
	g.set_meta("key", "graphics")
	var mo := _button("Kamera & Tempo  >", _show_motion)
	mo.focus_entered.connect(func(): info.text = tr(SETTING_HINTS["motion"]))
	mo.set_meta("key", "motion")
	var so := _button("Ton  >", _show_sound)
	so.focus_entered.connect(func(): info.text = tr(SETTING_HINTS["vol_sfx"]))
	so.set_meta("key", "sound")
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
	_menu_width(280.0)
	_back = _show_settings.bind("graphics")
	_set_section("GRAFIK")
	for key in ["preset"] + GameState.GFX_ORDER.filter(GameState.gfx_available) + ["pixel"]:
		_setting_button(key)
	_button("< Zurück", _back)
	info.text = tr(SETTING_HINTS["preset"])
	_focus_first()


## Ton (seit 2.52): Lautstärke von Musik und Effekten (auch im Esc-Menü von Welt und Rennen)
func _show_sound() -> void:
	_clear_menu()
	_menu_width(280.0)
	_back = _show_settings.bind("sound")
	_set_section("TON")
	for key in ["vol_music", "vol_sfx"]:
		_setting_button(key)
	_button("< Zurück", _back)
	info.text = tr(SETTING_HINTS["vol_music"])
	_focus_first()


## Tempogefühl: Bewegungsunschärfe, Tempo-Zoom, Kamerawackeln, Sprungkamera (gegen Übelkeit alles abschaltbar)
func _show_motion() -> void:
	_clear_menu()
	_menu_width(280.0)
	_back = _show_settings.bind("motion")
	_set_section("KAMERA & TEMPO")
	for key in ["motion_blur", "speed_fov", "cam_shake", "jumpcam"]:
		_setting_button(key)
	_button("< Zurück", _back)
	info.text = tr(SETTING_HINTS["motion_blur"])
	_focus_first()


func _setting_button(k: String) -> Button:
	var b := _button("", func(): pass)
	b.set_meta("setting", k)
	b.set_meta("quiet", true)  # Umschalten hat seinen eigenen Ton
	_setting_text(b)
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
				_setting_text(c)
	b.pressed.connect(change.bind(1))
	if k != "language":
		b.gui_input.connect(func(ev): _lr_input(ev, change))
	b.focus_entered.connect(func(): info.text = tr(SETTING_HINTS[k]))
	return b


## "Schwierigkeit: Normal" -> links SCHWIERIGKEIT, rechts NORMAL (im Fokus mit ‹ ›, Links/Rechts ändert);
## die Sprache öffnet ein eigenes Menü (Pfeil)
func _setting_text(b: Button) -> void:
	var k: String = b.get_meta("setting")
	var full := GameState.setting_text(k)
	var i := full.rfind(": ")
	if i < 0:
		b.text = full.to_upper()
		return
	b.text = full.substr(0, i).to_upper()
	var val := full.substr(i + 2).to_upper()
	if k == "language":
		_row_value(b, val + "  ›")
	else:
		_row_value(b, val, UI.DIM, true)


## Karriere wie in NFSU2: Stufen untereinander, alle Events einer offenen Stufe frei wählbar; drei Siege in einer
## Stufe öffnen die nächste. Jede Zeile trägt rechts die Art als farbiges Abzeichen (Sprint cyan, Rundkurs grün,
## Drag pink, Drift orange) und die Schwierigkeit als Rauten (golden, wenn gewonnen). Rechts die Deutschlandkarte.
# --- Fahrer: Level, Titel, Level-Liste (seit 2.33; Embleme seit 2.35 nicht mehr in der Garage) --------------------

## Fahrerkarte oben im Menü: Level groß, darunter der Titel, eine Haarlinie bis zum nächsten Level und die XP
func _driver_card() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(226, 58)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var li := GameState.level_info()
	c.draw.connect(func():
		var fc := UI.font("cond", 0.0, 1)
		var fw := UI.font("wide", 0.0, 1)
		var x := 12.0
		c.draw_string(fc, Vector2(x, 20), tr("LEVEL %d") % li["level"], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UI.TEXT)
		c.draw_string(fw, Vector2(x, 33), GameState.title_name().to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 200, 8, UI.ACCENT)
		var w := 200.0
		var k := clampf(float(li["into"]) / maxf(float(li["need"]), 1.0), 0.0, 1.0)
		c.draw_rect(Rect2(x, 40, w, 2), Color(1, 1, 1, 0.1))
		c.draw_rect(Rect2(x, 40, w * k, 2), UI.ACCENT)
		var xt := "%d / %d XP" % [li["into"], li["need"]]
		c.draw_string(fw, Vector2(x, 52), xt, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, UI.DIM))
	return c


func _show_driver() -> void:
	_clear_menu()
	_back = _show_main
	_set_section("FAHRER")
	stats.get_parent().visible = false
	menu.add_child(_driver_card())
	_gap(4.0)
	var bt := _button(tr("Titel: ").strip_edges().trim_suffix(":"), _show_titles)
	_row_value(bt, GameState.title_name().to_upper() + "  ›")
	bt.focus_entered.connect(func(): info.text = tr("Dein Titel steht im HUD der Welt und in der Garage. Neue Titel kommen mit dem Level."))
	var bl := _button(tr("Level-Liste") + "  >", _show_levels)
	bl.focus_entered.connect(func(): info.text = tr("Was du mit welchem Level freischaltest: Stufen der Karriere, Autos, Teile, Vinyls, Titel."))
	_button("< Zurück", _show_main)
	info.text = _xp_hint()
	_focus_first()


## Woher Erfahrung kommt (Infotext)
func _xp_hint() -> String:
	return tr("Erfahrung gibt es fürs Driften, knapp vorbei, Sprünge und Duelle in der Welt und für jedes Rennen (der erste Sieg zählt anderthalbfach). Mit dem Level öffnen sich Karriere-Stufen, Autos, Teile, Vinyls und Titel.")


func _show_titles() -> void:
	_clear_menu()
	_back = _show_driver
	_set_section("TITEL")
	stats.get_parent().visible = false
	var focus: Control = null
	for t in Catalog.TITLES.size():
		var ti := t
		var row: Dictionary = Catalog.TITLES[t]
		var open := GameState.title_unlocked(t)
		var b := _button(tr(row["name"]), func():
			if GameState.title_unlocked(ti):
				GameState.title = ti
				GameState.save_game()
				_show_driver()
			else:
				Sfx.ui("locked"))
		b.set_meta("quiet", true)
		if t == GameState.title:
			focus = b
			_row_value(b, "✓", UI.ACCENT)
		elif not open:
			_locked_row(b)
			_row_value(b, tr("AB LEVEL %d") % int(row["level"]), UI.FAINT)
		b.focus_entered.connect(func(): info.text = tr(row["name"]) + "\n" + (tr("Frei. Enter: als Titel tragen.") if GameState.title_unlocked(ti)
			else tr("Kommt mit Fahrer-Level %d.") % int(row["level"])))
	_button("< Zurück", _show_driver)
	_focus_first()
	if focus:
		_grab.call_deferred(focus)


## Gesperrter Eintrag: Text grau (im Fokus etwas heller), Fläche und Strich bleiben wie bei allen
func _locked_row(b: Button) -> void:
	b.add_theme_color_override("font_color", UI.FAINT)
	b.add_theme_color_override("font_focus_color", UI.DIM)
	b.add_theme_color_override("font_hover_color", UI.DIM)


## Level-Liste: je Level ein Eintrag (erreicht mit Haken, das nächste hell, spätere grau), Details im Infofeld
func _show_levels() -> void:
	_clear_menu()
	_back = _show_driver
	_set_section("LEVEL-LISTE")
	stats.get_parent().visible = false
	var lv := GameState.level()
	var focus: Control = null
	var last := 2
	for l in range(2, Catalog.LEVEL_MAX + 1):
		if not Catalog.level_rewards(l).is_empty():
			last = l
	for l in range(2, last + 1):
		var rw := Catalog.level_rewards(l)
		if rw.is_empty():
			continue
		var lvl := l
		var first: String = tr(str(rw[0]["name"]))
		for r in rw:  # Autos zuerst nennen, dann Stufen
			if r["kind"] == "car" or r["kind"] == "stage":
				first = tr(str(r["name"]))
				break
		var txt := tr("LEVEL %d") % l + "  ·  " + first + (" +%d" % (rw.size() - 1) if rw.size() > 1 else "")
		var b := _button(txt, func(): pass)
		b.set_meta("quiet", true)
		b.add_theme_font_size_override("font_size", 11)
		if l <= lv:
			b.add_theme_color_override("font_color", UI.DIM)
			_row_value(b, "✓", UI.ACCENT)
		elif focus == null:
			focus = b
			b.add_theme_color_override("font_color", UI.TEXT)
			_row_value(b, "›", UI.ACCENT)
		else:
			_locked_row(b)
		b.focus_entered.connect(func(): info.text = _level_info(lvl))
	_button("< Zurück", _show_driver)
	_focus_first()
	if focus:
		_grab.call_deferred(focus)
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(focus) and focus.is_inside_tree():
		menu_scroll.ensure_control_visible(focus)


func _level_info(l: int) -> String:
	var lines := []
	for r in Catalog.level_rewards(l):
		lines.append("·  " + GameState.reward_text(r))
	var head := tr("LEVEL %d") % l
	var cur := GameState.level()
	if l <= cur:
		head += "   ·   " + tr("erreicht")
	else:
		var total := 0
		for k in range(1, l):
			total += GameState.xp_need(k)
		head += "   ·   " + tr("noch %s XP") % _thousands(total - GameState.xp)
	return head + "\n" + "\n".join(lines)


static func _thousands(n: int) -> String:
	var s := str(maxi(n, 0))
	var out := ""
	while s.length() > 3:
		out = "." + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


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
			b.add_theme_font_size_override("font_size", 11)
			b.clip_text = true
			b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			_event_badge(b, r, won, open)
			if not open:
				_locked_row(b)
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


## Überschrift einer Stufe: "STUFE 2 · SZENE" links, rechts "1/3 SIEGE" (offen), "FERTIG" (gold) oder
## "AB LEVEL n" (grau); darunter eine Haarlinie
func _stage_header(s: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(226, 24 if s > 0 else 16)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var open := GameState.stage_open(s)
	var w := GameState.stage_wins(s)
	var n: int = Catalog.STAGES[s]["events"].size()
	var done := w >= n
	var col: Color = UI.GOLD if open and done else (UI.DIM if open else UI.FAINT)
	var left := tr("STUFE %d · %s") % [s + 1, tr(Catalog.STAGES[s]["name"]).to_upper()]
	var right := tr("AB LEVEL %d") % int(Catalog.STAGES[s]["level"]) if not open else (tr("FERTIG") if done else tr("%d/%d SIEGE") % [w, n])
	c.draw.connect(func():
		var f := UI.font("wide", 0.0, 1)
		var y := c.size.y - 5.0
		c.draw_string(f, Vector2(12, y), left, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, UI.TEXT if open else UI.FAINT)
		var rw := f.get_string_size(right, HORIZONTAL_ALIGNMENT_LEFT, -1, 7).x
		c.draw_string(f, Vector2(c.size.x - rw - 10.0, y), right, HORIZONTAL_ALIGNMENT_LEFT, -1, 7, col)
		c.draw_rect(Rect2(12, c.size.y - 1.0, c.size.x - 22.0, 1.0), UI.LINE))
	return c


## Abzeichen der Event-Art rechts im Eintrag; der Name wird davor gekürzt
func _event_badge(b: Button, r: Dictionary, won: bool, open := true) -> void:
	var rt: String = r["type"]
	var label := tr(Catalog.EVENT_TYPES[rt]["label"]).to_upper()
	var tier: int = r.get("tier", 1)
	var bw := UI.badge_width(label, 7, tier)
	(b.get_meta("box") as StyleBox).content_margin_right = bw + 18.0
	var bd := Control.new()
	bd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bd.set_anchors_preset(Control.PRESET_FULL_RECT)
	bd.modulate.a = 1.0 if open else 0.4
	b.add_child(bd)
	bd.draw.connect(func():
		UI.draw_badge(bd, Vector2(bd.size.x - bw - 10.0, (bd.size.y - 11.0) / 2.0), rt, label, 7, tier, won))


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
		t = head + "\n" + tr("Ziel: ") + goal + "\n" + tr("Gesperrt: Stufe %d öffnet mit Fahrer-Level %d (du bist Level %d).") \
			% [s + 1, int(Catalog.STAGES[s]["level"]), GameState.level()]
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


## Splitscreen für zwei (seit 2.47): ein Sprint oder Rundkurs (die offenen), Spieler 2 unten. Er fährt das freie Auto,
## das deinem im Tempo am nächsten kommt (sonst dasselbe). Ohne Erfahrung und Karriere, ohne Verkehr.
func _show_split() -> void:
	_clear_menu()
	_back = _show_main
	_set_section("ZU ZWEIT")
	var p2 := _p2_car()
	for i in Catalog.RACES.size():
		var r: Dictionary = Catalog.RACES[i]
		if not r.get("type", "sprint") in ["sprint", "circuit"] or not GameState.career_open(r["name"]):
			continue
		var idx := i
		var b := _button(tr(r["name"]), func():
			GameState.split = true
			GameState.p2_car = p2
			_start_race(idx))
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.set_meta("quiet", true)
	_button("< Zurück", _show_main)
	info.text = tr("Splitscreen an einem Rechner: Spieler 1 oben (WASD, Leertaste Handbremse, linke Umschalttaste Nitro oder erstes Gamepad), Spieler 2 unten (Pfeiltasten, rechte Umschalttaste Handbremse, Enter Nitro, Rücktaste zurücksetzen oder zweites Gamepad). Spieler 2 fährt: %s.") % str(Catalog.CARS[p2]["name"])
	_focus_first()


func _p2_car() -> String:
	var mine: float = Catalog.CARS[GameState.current_car]["top_speed"]
	var best := GameState.current_car
	var bd := 1e9
	for id in Catalog.CAR_ORDER:
		if id == GameState.current_car or not GameState.is_car_unlocked(id):
			continue
		var d := absf(float(Catalog.CARS[id]["top_speed"]) - mine)
		if d < bd:
			bd = d
			best = id
	return best


func _drive_world() -> void:
	if _starting:
		return
	_starting = true
	GameState.save_game()
	Sfx.ui("go")
	Music.race_loading()
	await get_tree().process_frame
	get_tree().change_scene_to_file("res://scenes/world.tscn")


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
	if cat in COLOR_CATS:
		_show_color_grid(cat, group)
		return
	if cat == "vinyl":
		_show_vinyl_groups()  # erst die Kategorien (seit 2.36), siehe unten
		return
	_clear_menu()
	_strip_on(true)
	_back = _show_group.bind(group, cat)
	_cam_view = cat
	section.text = tr(Catalog.PARTS[cat]["label"]).to_upper()
	stats.get_parent().visible = group == "leistung"  # Optik-Teile ändern keine Fahrwerte: Balken weg, Auto frei
	var installed: int = GameState.get_config(preview_car).get(cat, 0)
	var opts: Array = Catalog.PARTS[cat]["options"]
	_tile(tr("Zurück"), "", _back, {"back": true})
	var focus_i := 1
	for i in opts.size():
		if not _part_listed(cat, i):
			continue
		var idx := i
		var b := _tile("", "", func(): _install(cat, idx, group), {"part": idx, "swatch": _swatch(cat, idx), "quiet": true})
		b.focus_entered.connect(func(): _preview_part(cat, idx))
		if idx == installed:
			focus_i = strip_box.get_child_count() - 1
	_refresh_parts(cat)
	_strip_ready("", focus_i)


## Steht das Teil in der Leiste? Ausgeblendete (alte Zoll-Angaben bis 2.36) nicht, Zoll-Größen, die bei diesem Auto nicht
## über die Bremse passen (mehr als zwei Zoll unter Werk), auch nicht
func _part_listed(cat: String, idx: int) -> bool:
	var opt: Dictionary = Catalog.PARTS[cat]["options"][idx]
	if opt.get("hidden", false):
		return false
	if cat == "rimsize" and opt.has("abs"):
		return int(opt["abs"]) >= int(Builder.rim_spec(preview_car, GameState.get_config(preview_car))["min_in"])
	return true


# --- Folierung in Kategorien wie in NFS Underground (seit 2.36) -------------------------------------------------------

## Erst die Kategorien (Keins, dann Catalog.PARTS.vinyl.groups: Streifen, Flammen, Tribal, Rennsport, Spezial,
## Unikate), dann die Motive darin. Vorn die einfarbigen (Farbe unter Folienfarbe, die Kachel dafür steht auch am Ende
## ihrer Motive), hinten die mit festen Farben. In den Motiven wechseln Hoch/Runter (auch Q/E und die Schultertasten)
## die Kategorie; das Mausrad blättert, Rechtsklick geht zurück. Vorher stand alles in einer Leiste mit 34 Kacheln.
const KEYS_VINYL := "←/→  Auswählen      ↑/↓  Kategorie      ENTER  Einbauen      ESC  Zurück      F11  Vollbild"
var _vinyl_group := ""  # offene Kategorie, "" = Leiste der Kategorien
var _vinyl_wheel_ms := 0


## Eingebautes Vinyl; ein ausgeblendetes (die alten Motive mit Gesichtern) gilt als Keins
func _vinyl_installed() -> int:
	var i: int = GameState.get_config(preview_car).get("vinyl", 0)
	return 0 if Catalog.part_of({"vinyl": i}, "vinyl").get("hidden", false) else i


## Nimmt die Folienfarbe: die Streifen (ohne Bild) und die einfarbigen Motive (tint)
static func _vinyl_tinted(idx: int) -> bool:
	var opt: Dictionary = Catalog.PARTS["vinyl"]["options"][idx]
	return idx > 0 and (not opt.has("art") or opt.get("tint", false))


## Motive einer Kategorie (Indizes), nach Level, sonst in Katalog-Reihenfolge
static func _vinyl_items(gid: String) -> Array:
	var opts: Array = Catalog.PARTS["vinyl"]["options"]
	var out := []
	for i in opts.size():
		if opts[i].get("group", "") == gid and not opts[i].get("hidden", false):
			out.append(i)
	out.sort_custom(func(a: int, b: int) -> bool:
		var la := int(opts[a].get("level", 0))
		var lb := int(opts[b].get("level", 0))
		return la < lb or (la == lb and a < b))
	return out


static func _vinyl_group_def(gid: String) -> Dictionary:
	for gr in Catalog.PARTS["vinyl"]["groups"]:
		if gr["id"] == gid:
			return gr
	return {}


static func _vinyl_group_tinted(gid: String) -> bool:
	for i in _vinyl_items(gid):
		if not _vinyl_tinted(i):
			return false
	return true


## Kategorien als Kacheln: Zurück, Keins (baut sofort aus), dann die Kategorien; darunter "Farbe wählbar" oder "Feste
## Farben". Die Kategorie mit dem eingebauten Motiv nennt es im Akzent und hat beim Öffnen den Fokus.
func _show_vinyl_groups(focus := "") -> void:
	_clear_menu()
	_strip_on(true)
	_vinyl_group = ""
	_back = _show_group.bind("optik", "vinyl")
	_cam_view = "vinyl"
	section.text = tr(Catalog.PARTS["vinyl"]["label"]).to_upper()
	stats.get_parent().visible = false
	_tile(tr("Zurück"), "", _back, {"back": true})
	var none := _tile("", "", func(): _install("vinyl", 0, "optik"), {"part": 0, "key": "none", "quiet": true})
	none.focus_entered.connect(func(): _preview_part("vinyl", 0))
	for gr in Catalog.PARTS["vinyl"]["groups"]:
		var gid: String = gr["id"]
		var b := _tile(tr(gr["label"]), "", _show_vinyl_items.bind(gid), {"key": gid, "vgroup": gid})
		b.focus_entered.connect(_vinyl_group_focus.bind(gid))
	_refresh_parts("vinyl")
	_vinyl_wire()
	var inst := _vinyl_installed()
	_strip_ready(focus if focus != "" else (str(Catalog.PARTS["vinyl"]["options"][inst].get("group", "none")) if inst > 0 else "none"))


func _vinyl_group_focus(gid: String) -> void:
	_vinyl_preview_installed()
	var gr := _vinyl_group_def(gid)
	var items := _vinyl_items(gid)
	var free := items.filter(func(i: int) -> bool: return GameState.is_part_unlocked("vinyl", i)).size()
	var t := tr(gr["label"]) + "\n" + tr(gr["desc"]) + "\n"
	t += tr("Farbe wählbar: unter Folienfarbe, auch am Ende der Motive.") if _vinyl_group_tinted(gid) else \
		tr("Feste Farben: die Motive behalten ihre eigenen Farben.")
	if free < items.size():
		t += "\n" + tr("%d von %d Motiven frei") % [free, items.size()]
	info.text = t


## Vorschau zurück auf das Eingebaute (nach Motiven, die nur angesehen wurden)
func _vinyl_preview_installed() -> void:
	var base := GameState.get_config(preview_car)
	if preview_cfg != base:
		preview_cfg = base.duplicate()
		_pv_cat = "vinyl"
		_pv_pending = true
		_pv_t = 0.07


## Motive einer Kategorie: Vorschau beim Auswählen, Einbauen mit Enter (wenn frei). Einfarbige Kategorien haben am
## Ende eine Kachel für die Folienfarbe (Farbraster, Zurück führt wieder hierher). focus_key "colour": diese Kachel.
func _show_vinyl_items(gid: String, focus_key := "") -> void:
	_clear_menu()
	_strip_on(true)
	_set_keys(KEYS_VINYL)
	_vinyl_group = gid
	_back = _show_vinyl_groups.bind(gid)
	_cam_view = "vinyl"
	section.text = (tr(Catalog.PARTS["vinyl"]["label"]) + "  ·  " + tr(_vinyl_group_def(gid)["label"])).to_upper()
	stats.get_parent().visible = false
	_tile(tr("Zurück"), "", _back, {"back": true})
	var items := _vinyl_items(gid)
	for i in items:
		var idx: int = i
		var b := _tile("", "", func(): _install("vinyl", idx, "optik"), {"part": idx, "quiet": true})
		b.focus_entered.connect(func(): _preview_part("vinyl", idx))
	if _vinyl_group_tinted(gid):
		var c := _tile(tr(Catalog.PARTS["vinylcol"]["label"]), "", _vinyl_colour.bind(gid),
			{"key": "colour", "swatch": _swatch("vinylcol", GameState.get_config(preview_car).get("vinylcol", 0))})
		c.focus_entered.connect(func():
			_vinyl_preview_installed()
			info.text = tr(Catalog.PARTS["vinylcol"]["label"]) + ": " + tr(Catalog.part_of(GameState.get_config(preview_car), "vinylcol")["name"]) \
				+ "\n" + tr("Färbt die Streifen und alle einfarbigen Motive (Kontrast: Weiß auf dunklem, Schwarz auf hellem Lack). ENTER öffnet die Farben."))
	_refresh_parts("vinyl")
	_vinyl_wire()
	var pos := items.find(_vinyl_installed())
	_strip_ready(focus_key, -1 if focus_key != "" else (pos + 1 if pos >= 0 else 1))


## Folienfarbe aus den Motiven heraus: das Farbraster wie unter Optik, Zurück führt auf die Farbkachel
func _vinyl_colour(gid: String) -> void:
	_show_color_grid("vinylcol", "optik")
	_back = _show_vinyl_items.bind(gid, "colour")


## Hoch/Runter in den Motiven: vorige/nächste Kategorie (läuft rundherum)
func _vinyl_step(dir: int) -> void:
	var groups: Array = Catalog.PARTS["vinyl"]["groups"]
	var i := 0
	for k in groups.size():
		if groups[k]["id"] == _vinyl_group:
			i = k
	Sfx.ui("move")
	_show_vinyl_items(groups[(i + dir + groups.size()) % groups.size()]["id"])


## Kategorien- und Farbkachel nachziehen (beim Öffnen und nach dem Einbauen): die Kategorie mit dem eingebauten Motiv
## nennt es im Akzent, sonst steht dort "Farbe wählbar" oder "Feste Farben"; ganz gesperrte zeigen ihr Level
func _refresh_vinyl_tiles() -> void:
	var inst := _vinyl_installed()
	var opts: Array = Catalog.PARTS["vinyl"]["options"]
	for b in strip_box.get_children():
		if b.has_meta("vgroup"):
			var gid: String = b.get_meta("vgroup")
			var items := _vinyl_items(gid)
			var lv := 99
			var open := false
			for i in items:
				lv = mini(lv, int(opts[i].get("level", 0)))
				open = open or GameState.is_part_unlocked("vinyl", i)
			var sub := tr("FARBE WÄHLBAR") if _vinyl_group_tinted(gid) else tr("FESTE FARBEN")
			if inst in items:
				sub = tr(opts[inst]["name"])
			elif not open:
				sub = tr("AB LEVEL %d") % lv
			_tile_text(b, tr(_vinyl_group_def(gid)["label"]), sub)
			b.set_meta("installed", inst in items)
			b.set_meta("locked", not open)
			_tile_colors(b)
		elif b.get_meta("key", "") == "colour":
			_tile_text(b, tr(Catalog.PARTS["vinylcol"]["label"]), tr(Catalog.part_of(GameState.get_config(preview_car), "vinylcol")["name"]))


## Maus und Hoch/Runter für die Kacheln der Folierung (siehe _vinyl_input)
func _vinyl_wire() -> void:
	for c in strip_box.get_children():
		(c as Control).gui_input.connect(_vinyl_input.bind(c))


func _vinyl_input(ev: InputEvent, b: Control) -> void:
	var mb := ev as InputEventMouseButton
	if mb and mb.pressed:
		var bi := mb.button_index
		if bi == MOUSE_BUTTON_RIGHT:
			b.accept_event()
			Sfx.ui("back")
			_back.call_deferred()
		elif bi in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
			# Mausrad: eine Kachel weiter je Raste (Trackpads senden viele kleine Schritte: höchstens alle 90 ms)
			b.accept_event()
			if Time.get_ticks_msec() - _vinyl_wheel_ms < 90:
				return
			_vinyl_wheel_ms = Time.get_ticks_msec()
			var f := get_viewport().gui_get_focus_owner()
			if f == null or f.get_parent() != strip_box:
				f = b
			var back := bi == MOUSE_BUTTON_WHEEL_UP or bi == MOUSE_BUTTON_WHEEL_LEFT
			var nb := f.get_node_or_null(f.focus_neighbor_left if back else f.focus_neighbor_right) as Control
			if nb:
				nb.grab_focus()
		return
	if _vinyl_group == "" or not ev.is_pressed():
		return
	for a in [["ui_up", -1], ["ui_down", 1], ["shift_down", -1], ["shift_up", 1]]:
		if ev.is_action_pressed(a[0], true):
			b.accept_event()
			# Stick: jede Bewegung über der Totzone meldet sich als gedrückt (ein Schub sprang sonst drei, vier
			# Kategorien weiter oder einmal ganz herum); nur der erste Ausschlag schaltet
			if ev is InputEventJoypadMotion and not Input.is_action_just_pressed_by_event(a[0], ev):
				return
			_vinyl_step.call_deferred(a[1])
			return


## Farben (Lack, Felgenfarbe, Folienfarbe, Neon, Licht) als Raster statt als Leiste (seit 2.27): alle Farben auf einen
## Blick, Pfeiltasten in alle Richtungen. Über dem Raster Name und Zustand der gewählten Farbe.
const COLOR_CATS := ["paint", "rimcol", "vinylcol", "neon", "lights"]
var color_grid: Control


func _show_color_grid(cat: String, group: String) -> void:
	_clear_menu()
	_strip_on(true)
	strip.visible = false
	_back = _show_group.bind(group, cat)
	_cam_view = cat
	section.text = tr(Catalog.PARTS[cat]["label"]).to_upper()
	stats.get_parent().visible = false
	_set_keys(KEYS_GRID)
	var opts: Array = Catalog.PARTS[cat]["options"]
	var panel := PanelContainer.new()
	var sb := UI.panel_box(0.9)
	sb.set_content_margin_all(9)
	panel.add_theme_stylebox_override("panel", sb)
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.offset_bottom = -28.0
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 7)
	panel.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vb.add_child(head)
	var back := Button.new()
	back.theme_type_variation = "Ghost"
	back.text = "‹  " + tr("Zurück").to_upper()
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(func():
		Sfx.ui("back")
		_back.call())
	head.add_child(back)
	var sep := ColorRect.new()
	sep.color = UI.LINE_HI
	sep.custom_minimum_size = Vector2(1, 10)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(sep)
	var title := UI.label(head, 9, "wide", UI.TEXT, 1)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_vertical = Control.SIZE_FILL
	var grid := GridContainer.new()
	# eine Reihe bis 11 Farben, sonst zwei (seit 2.38; vorher acht Spalten, beim Lack drei Reihen über dem Auto)
	grid.columns = opts.size() if opts.size() <= 11 else ceili(opts.size() / 2.0)
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	vb.add_child(grid)
	var cells := []
	var cell := Vector2(40, 28) if GameState.is_mobile() else Vector2(34, 22)  # Touch: größere Felder
	for i in opts.size():
		var idx := i
		var b := Button.new()
		b.theme_type_variation = "Swatch"
		b.custom_minimum_size = cell
		b.focus_mode = Control.FOCUS_ALL
		var sw = _swatch(cat, idx)
		var r := Panel.new()  # Farbfeld mit leicht runden Ecken
		var rb := StyleBoxFlat.new()
		rb.bg_color = sw if sw is Color else Color(0.06, 0.065, 0.075)
		rb.set_corner_radius_all(1)
		r.add_theme_stylebox_override("panel", rb)
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		r.offset_left = 2.0
		r.offset_top = 2.0
		r.offset_right = -2.0
		r.offset_bottom = -2.0
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(r)
		if not sw is Color:
			# "Aus" bzw. ohne eigene Farbe: feiner Schrägstrich
			r.draw.connect(func(): r.draw_line(Vector2(r.size.x * 0.3, r.size.y * 0.8), Vector2(r.size.x * 0.7, r.size.y * 0.2), UI.FAINT, 1.0, true))
		var mark := Panel.new()  # eingebaut: kleiner Punkt im Akzent in der Ecke
		mark.name = "M"
		var mb := StyleBoxFlat.new()
		mb.bg_color = UI.ACCENT
		mb.set_corner_radius_all(3)
		mb.border_color = Color(0, 0, 0, 0.6)
		mb.set_border_width_all(1)
		mb.anti_aliasing = true
		mark.add_theme_stylebox_override("panel", mb)
		mark.size = Vector2(6, 6)
		mark.position = Vector2(cell.x - 8.0, 2)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(mark)
		b.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseMotion and not b.has_focus():
				b.grab_focus())
		b.focus_entered.connect(func():
			Sfx.ui("move")
			_preview_part(cat, idx)
			title.text = _color_title(cat, idx))
		b.pressed.connect(func():
			_install(cat, idx, group)
			_mark_grid(cells, cat)
			title.text = _color_title(cat, idx))
		grid.add_child(b)
		cells.append(b)
	strip.get_parent().add_child(panel)
	color_grid = panel
	_info_panel.visible = false  # Name und Zustand stehen über dem Raster
	_mark_grid(cells, cat)
	# Raster und Titel blenden ein
	panel.modulate.a = 0.0
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, 0.2)
	section.modulate.a = 0.0
	tw.tween_property(section, "modulate:a", 1.0, 0.24)
	var installed: int = GameState.get_config(preview_car).get(cat, 0)
	_grab.call_deferred(cells[clampi(installed, 0, cells.size() - 1)])


func _mark_grid(cells: Array, cat: String) -> void:
	var installed: int = GameState.get_config(preview_car).get(cat, 0)
	for i in cells.size():
		var b: Button = cells[i]
		b.get_node("M").visible = i == installed
		b.modulate.a = 1.0 if GameState.is_part_unlocked(cat, i) else 0.32


func _color_title(cat: String, idx: int) -> String:
	var opt: Dictionary = Catalog.PARTS[cat]["options"][idx]
	var t := tr(opt["name"]).to_upper()
	if idx == GameState.get_config(preview_car).get(cat, 0):
		t += "   ·   " + tr("EINGEBAUT")
	elif not GameState.is_part_unlocked(cat, idx):
		t += "   ·   " + GameState.part_lock_text(cat, idx)
	return t


func _refresh_parts(cat: String) -> void:
	var installed: int = GameState.get_config(preview_car).get(cat, 0)
	if cat == "vinyl":
		installed = _vinyl_installed()
		_refresh_vinyl_tiles()
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
			sub = GameState.part_lock_text(cat, i)
		var c2 := GameState.get_config(preview_car).duplicate()
		c2[cat] = i
		if sub == "" and (cat == "rimsize" or cat == "spur"):
			sub = Builder.rim_spec(preview_car, c2)["tire"]
		_tile_text(b, tr(opt["name"]) + _inch_suffix(cat, c2), sub)
		b.set_meta("installed", i == installed)
		b.set_meta("locked", locked)
		_tile_colors(b)


## Vorschau eines Teils: Werte und Text sofort, das Auto erst, wenn man kurz auf der Kachel bleibt (beim schnellen
## Durchblättern wird nicht jedes Teil gebaut, das Blättern bleibt flüssig)
var _pv_pending := false
var _pv_t := 0.0
var _pv_cat := ""


func _preview_part(cat: String, idx: int) -> void:
	var base := GameState.get_config(preview_car).duplicate()
	preview_cfg = base.duplicate()
	preview_cfg[cat] = idx
	_show_stats(preview_car, preview_cfg, base)
	_part_info(cat, idx)
	_pv_cat = cat
	_pv_pending = true
	_pv_t = 0.07


func _update_preview(dt: float) -> void:
	if not _pv_pending:
		return
	_pv_t -= dt
	if _pv_t > 0.0:
		return
	_pv_pending = false
	_show_car(preview_car, preview_cfg)
	Builder.showcase(car_node, preview_car, preview_cfg, _showcase_mode(_pv_cat))


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
	# Tuning: Infofeld klein oben links unter dem Titel (seit 2.38; vorher links über der Leiste, wo es Räder und Front
	# verdeckte), Tipps aus, Werte klein oben rechts. Das Auto hat die Mitte für sich.
	tip.visible = not on
	if on:
		_info_panel.anchor_left = 0.0
		_info_panel.anchor_right = 0.0
		_info_panel.anchor_top = 0.0
		_info_panel.anchor_bottom = 0.0
		_info_panel.grow_vertical = Control.GROW_DIRECTION_END
		_info_panel.offset_left = 14.0
		_info_panel.offset_right = 14.0 + 232.0
		_info_panel.offset_top = 80.0  # wächst nach unten, so hoch wie der Text
		_info_panel.offset_bottom = 80.0
		info.custom_minimum_size.x = 208.0
		_set_keys(KEYS_STRIP)
	else:
		_info_panel.anchor_left = 1.0
		_info_panel.anchor_right = 1.0
		_info_panel.anchor_top = 1.0
		_info_panel.anchor_bottom = 1.0
		_info_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_info_panel.offset_left = -300.0
		_info_panel.offset_right = -14.0
		_info_panel.offset_top = -82.0
		_info_panel.offset_bottom = -28.0
		info.custom_minimum_size.x = 258.0
		_set_keys(KEYS_MENU)
	_place_stats()


func _clear_strip() -> void:
	for c in strip_box.get_children():
		strip_box.remove_child(c)
		c.queue_free()
	strip_box.position.x = 0.0
	strip_box.size = Vector2.ZERO


## Eine Kachel: Name groß, darunter klein (eingebautes Teil, Sperre). opts: key, part, swatch (Farbe), back, quiet
func _tile(title_text: String, sub: String, cb: Callable, opts := {}) -> Button:
	var b := Button.new()
	b.theme_type_variation = "Tile"
	var is_back: bool = opts.get("back", false)
	b.custom_minimum_size = Vector2(70.0 if is_back else 112.0, 44.0)
	b.focus_mode = Control.FOCUS_ALL
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS  # Klick wirkt sofort, bevor die Leiste zur Kachel rückt
	for k in opts:
		if k != "swatch":
			b.set_meta(k, opts[k])
	var t := Label.new()
	t.name = "T"
	t.label_settings = UI.text_settings(11, "cond", UI.TEXT, 1)
	t.label_settings.shadow_color = Color(0, 0, 0, 0)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.clip_text = true
	t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	t.set_anchors_preset(Control.PRESET_TOP_WIDE)
	t.offset_left = 6.0
	t.offset_right = -6.0
	t.offset_top = 9.0 if sub != "" or not is_back else 14.0
	t.offset_bottom = t.offset_top + 16.0
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(t)
	var u := Label.new()
	u.name = "S"
	u.label_settings = UI.text_settings(7, "wide", UI.DIM, 1)
	u.label_settings.shadow_color = Color(0, 0, 0, 0)
	u.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	u.clip_text = true
	u.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	u.set_anchors_preset(Control.PRESET_TOP_WIDE)
	u.offset_left = 6.0
	u.offset_right = -6.0
	u.offset_top = 26.0
	u.offset_bottom = 36.0
	u.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(u)
	var sw = opts.get("swatch", null)
	if sw is Color:
		# Farbfeld (Lack, Felgenfarbe, Folie, Neon, Licht): klein vor dem Untertitel, mit feinem hellem Rand
		var r := Panel.new()
		r.name = "W"
		var rb := StyleBoxFlat.new()
		rb.bg_color = sw
		rb.border_color = Color(1, 1, 1, 0.35)
		rb.set_border_width_all(1)
		rb.set_corner_radius_all(1)
		r.add_theme_stylebox_override("panel", rb)
		r.position = Vector2(9, 27)
		r.size = Vector2(8, 8)
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(r)
		u.offset_left = 19.0
		b.resized.connect(_place_swatch.bind(b))
	_tile_text(b, ("‹  " if is_back else "") + title_text, sub)
	UI.menu_fx(b, "top", false)  # Maus darüber hellt nur auf: Fokus würde die Leiste unter der Maus wegschieben
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
	_place_swatch(b)


## Farbfeld direkt vor den (mittigen) Untertitel setzen, nicht an den Rand der Kachel
func _place_swatch(b: Button) -> void:
	var r: Control = b.get_node_or_null("W")
	if r == null:
		return
	var u: Label = b.get_node("S")
	var w := u.label_settings.font.get_string_size(u.text, HORIZONTAL_ALIGNMENT_LEFT, -1, u.label_settings.font_size).x
	var bw := maxf(b.size.x, b.custom_minimum_size.x)
	var total := w + 12.0  # Feld 8 + Abstand 4
	var x0 := (bw - total) / 2.0
	r.position.x = maxf(x0, 6.0)
	u.offset_left = r.position.x + 12.0
	u.offset_right = -(bw - (r.position.x + total)) + 1.0


## Breite, die Titel und Untertitel einer Kachel brauchen
func _tile_need(b: Button) -> float:
	var t: Label = b.get_node("T")
	var u: Label = b.get_node("S")
	var tw := t.label_settings.font.get_string_size(t.text, HORIZONTAL_ALIGNMENT_LEFT, -1, t.label_settings.font_size).x + 16.0
	var uw := u.label_settings.font.get_string_size(u.text, HORIZONTAL_ALIGNMENT_LEFT, -1, u.label_settings.font_size).x \
		+ 16.0 + (12.0 if b.has_node("W") else 0.0)
	return ceilf(maxf(tw, uw))


## Schriftfarben je Zustand: gewählt hell, eingebaut im Akzent, gesperrt grau
func _tile_colors(b: Node) -> void:
	if not b is Button or not b.has_node("T"):
		return
	var focused := (b as Button).has_focus()
	var t: Label = b.get_node("T")
	var u: Label = b.get_node("S")
	var locked: bool = b.get_meta("locked", false)
	t.label_settings.font_color = UI.TEXT if focused else (UI.FAINT if locked else Color(0.8, 0.82, 0.86))
	u.label_settings.font_color = UI.ACCENT if b.get_meta("installed", false) else (UI.FAINT if locked else UI.DIM)
	(b as Button).modulate.a = 0.7 if locked and not focused else 1.0


## Leiste fertig: Ränder verknüpfen (rechts vom letzten geht es zum ersten), hoch/runter gesperrt, Fokus setzen.
## focus_key: Kachel mit meta "key", sonst Index focus_i (sonst die erste nach "Zurück").
func _strip_ready(focus_key := "", focus_i := -1) -> void:
	var tiles := strip_box.get_children()
	if tiles.is_empty():
		return
	# alle Kacheln einer Leiste gleich breit, so breit wie der längste Text (in Grenzen), damit nichts abgeschnitten wird
	var w := 112.0
	for b in tiles:
		if not b.get_meta("back", false):
			w = maxf(w, _tile_need(b))
	for b in tiles:
		b.custom_minimum_size.x = _tile_need(b) if b.get_meta("back", false) else minf(w, 168.0)
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
	# Leiste blendet ein und fährt ein kleines Stück von unten herein
	strip_box.modulate.a = 0.0
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(strip_box, "modulate:a", 1.0, 0.2)
	section.modulate.a = 0.0
	tw.tween_property(section, "modulate:a", 1.0, 0.24)
	_strip_focus.call_deferred(target)


func _strip_focus(b: Button) -> void:
	if not is_instance_valid(b) or not b.is_inside_tree():
		return
	strip_box.reset_size()
	strip_box.position.y = 14.0
	create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).tween_property(strip_box, "position:y", 8.0, 0.22)
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


## Felgen und Zoll: Größe in Zoll hinter dem Namen (z. B. 18"), je Auto verschieden. Feste Größen (seit 2.37) tragen sie
## schon im Namen.
func _inch_suffix(cat: String, cfg: Dictionary) -> String:
	if cat != "rims" and cat != "rimsize":
		return ""
	if cat == "rimsize" and Catalog.part_of(cfg, "rimsize").has("abs"):
		return ""
	return "  %d\"" % Builder.rim_spec(preview_car, cfg)["inch"]


## Wirkung des Teils in Zahlen (wie die Werte im NFS-Tuning)
func _part_info(cat: String, idx: int) -> void:
	var opt: Dictionary = Catalog.PARTS[cat]["options"][idx]
	var t := tr(Catalog.PARTS[cat]["label"]) + ": " + tr(opt["name"])
	match cat:
		"vinyl":
			if idx > 0:
				# seit 2.36: jedes Motiv sagt, ob es die Folienfarbe nimmt (Streifen und einfarbige Motive) oder nicht
				t += "\n" + (tr("Einfarbig: die Farbe stellst du unter Folienfarbe ein.") if _vinyl_tinted(idx) else
					tr("Feste Farben: die Folienfarbe wirkt hier nicht."))
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
		"rims", "rimsize", "spur":
			var c2 := GameState.get_config(preview_car).duplicate()
			c2[cat] = idx
			var fi := Builder.fit_info(preview_car, c2)
			t += "\n" + tr("Felge %d Zoll   ·   Reifen %s") % [fi["inch"], fi["tire"]]
			if cat == "rimsize" and float(fi["lift"]) > 0.004:
				t += "\n" + tr("Größer als der Radlauf: das ganze Rad wächst mit, das Auto steht %d mm höher.") % roundi(float(fi["lift"]) * 1000.0)
			elif cat == "rimsize" and int(fi["inch"]) > int(fi["std_in"]):
				t += "\n" + tr("Nur Optik: der Reifen behält seinen Durchmesser, die Flanke wird flacher.")
			elif cat == "rimsize" and int(fi["inch"]) < int(fi["std_in"]):
				t += "\n" + tr("Nur Optik: der Reifen behält seinen Durchmesser, die Flanke wird höher.")
			if cat == "spur" and float(opt.get("wide", 0.0)) > 0.0:
				t += "\n" + tr("Reifen %d mm breiter, Räder je Seite %d mm weiter außen.") % [roundi(float(opt["wide"]) * 1000.0),
					roundi(float(opt["spacer"]) * 1000.0)]
			elif cat == "spur" and idx > 0:
				t += "\n" + tr("Räder je Seite %d mm weiter außen.") % roundi(float(opt["spacer"]) * 1000.0)
			if cat == "spur" and float(fi["camber"]) > 0.001:
				t += "\n" + tr("Tief und breit: die Räder bekommen negativen Sturz.")
				if float(fi["drop"]) < float(fi["drop_in"]) - 0.003:
					t += " " + tr("Damit sie Platz haben, liegt das Auto %d mm höher.") % roundi((float(fi["drop_in"]) - float(fi["drop"])) * 1000.0)
			elif cat == "spur" and idx > 0 and Builder.kit_flare(c2) == 0.0:
				t += "\n" + tr("Mit dem Breitbau-Kit rücken die Räder in die Verbreiterungen.")
	if not GameState.is_part_unlocked(cat, idx) and opt.has("find"):
		t += "\n" + (tr("Gesperrt: liegt in einer versteckten Werkstatt in %s. Halte nach bernsteinfarbenem Licht an einer Gasse Ausschau.")
			if str(opt["find"]).begins_with("werkstatt:") else tr("Gesperrt: das Schild liegt irgendwo in %s versteckt.")) % str(opt["find"]).get_slice(":", 1)
	elif not GameState.is_part_unlocked(cat, idx):
		t += "\n" + tr("Gesperrt: kommt mit Fahrer-Level %d (du bist Level %d).") % [int(opt.get("level", 1)), GameState.level()]
	elif idx != (_vinyl_installed() if cat == "vinyl" else GameState.get_config(preview_car).get(cat, 0)):
		t += "\n" + tr("ENTER: einbauen")
	info.text = t


## Autohaus: jedes Auto zeigt sich mit der Optik, die es beim Wechsel bekäme (seit 2.38 kommt sie mit, siehe
## GameState.switch_car). Ein anderes Auto fährt hinten herein, das bisherige vorn hinaus.
func _show_cars() -> void:
	_clear_menu()
	_back = _show_main
	_in_cars = true
	if not Catalog.CARS.has(preview_car):
		preview_car = GameState.current_car
	preview_cfg = GameState.switch_config(preview_car)
	if car_node == null or _shown_id != preview_car:
		_show_car(preview_car, preview_cfg)
	_set_section("AUTOHAUS", true)
	var b := _button("", func(): _cycle_car(1))
	b.set_meta("car", true)
	b.set_meta("quiet", true)
	b.gui_input.connect(func(ev): _lr_input(ev, _cycle_car))
	_button("Dieses Auto fahren", _choose_car).set_meta("quiet", true)
	_button("< Zurück", _show_main)
	_refresh_car()
	_focus_first()


## Blättern: Werte und Text sofort, das Auto erst, wenn man kurz stehen bleibt (_update_preview). Schnelles Blättern
## baut so nicht jedes Auto (das kostete jedes Mal einen Ruckler), und es fahren nie mehrere Autos auf einmal herein.
func _cycle_car(dir: int) -> void:
	Sfx.ui("change")
	var i := Catalog.CAR_ORDER.find(preview_car)
	preview_car = Catalog.CAR_ORDER[posmod(i + dir, Catalog.CAR_ORDER.size())]
	preview_cfg = GameState.switch_config(preview_car)
	_refresh_car()
	_pv_cat = ""
	_pv_pending = true
	_pv_t = 0.14


## Autowahl: "‹ NAME ›" links (Links/Rechts blättert), rechts Nummer und ggf. GESPERRT; die Wertekarte zeigt Name
## und Werte des gewählten Autos
func _refresh_car() -> void:
	var spec: Dictionary = Catalog.CARS[preview_car]
	var unlocked := GameState.is_car_unlocked(preview_car)
	var b: Button = menu.get_child(0)
	b.text = "‹  %s  ›" % str(spec["name"]).to_upper()
	var n := "%d / %d" % [Catalog.CAR_ORDER.find(preview_car) + 1, Catalog.CAR_ORDER.size()]
	_row_value(b, (tr("GESPERRT") + "  ·  " + n) if not unlocked else n)
	_show_stats(preview_car, preview_cfg)
	menu.get_child(1).disabled = not unlocked
	info.text = tr(spec["desc"]) + tr("\nHöchstgeschwindigkeit ab Werk: %d km/h") % int(spec["top_speed"] * 3.6) \
		+ tr("\nAntrieb: ") + tr({"fwd": "Frontantrieb", "rwd": "Heckantrieb", "mr": "Mittelmotor, Heckantrieb", "rr": "Heckmotor, Heckantrieb", "awd": "Allrad"}[spec.get("drive", "rwd")])
	if not unlocked:
		info.text += tr("\nFreischalten: ") + GameState.unlock_text(preview_car)
	elif preview_car != GameState.current_car and GameState.has_looks(GameState.current_car):
		info.text += tr("\nDeine Optik kommt mit: Lack, Felgen, Folie und alle anderen Teile.")


func _stars(v: float, lo: float, hi: float) -> String:
	var n := int(round(clampf((v - lo) / (hi - lo), 0.0, 1.0) * 4.0)) + 1
	return "#".repeat(n) + ".".repeat(5 - n)


## Auto übernehmen: die Optik kommt mit (GameState.switch_car), das Auto steht schon so auf dem Band
func _choose_car() -> void:
	if GameState.is_car_unlocked(preview_car):
		Sfx.ui("install")
		GameState.switch_car(preview_car)
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
		b.theme_type_variation = "MenuItem"
		b.text = I18n.NAMES[l].to_upper()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.focus_entered.connect(func(): Sfx.ui("move"))
		b.pressed.connect(func():
			Sfx.ui("select")
			GameState.set_language(l)
			get_tree().reload_current_scene())  # alle Texte neu in der gewählten Sprache
		menu.add_child(b)
		_item_fx(b)
		if l == GameState.language:
			_row_value(b, "✓", UI.ACCENT)
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
	_menu_in()
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
