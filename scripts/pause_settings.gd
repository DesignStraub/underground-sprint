extends VBoxContainer
## Einstellungen im Esc-Menü von Welt und Rennen (seit 2.52; vorher nur in der Garage): alles, was sofort wirkt
## (Lautstärke, Kamera & Tempo, Anzeige). Die Grafik-Optionen bauen die Welt um und bleiben in der Garage, ebenso
## V-Sync und FPS-Limit (sonst passte das Menü nicht auf den Bildschirm).
## Klick oder Rechts schaltet weiter, Links zurück; Zurück (oder Esc über back()) führt ins Pausemenü.

const UI := preload("res://scripts/ui_style.gd")

const KEYS := ["vol_music", "vol_sfx", "motion_blur", "speed_fov", "cam_shake", "jumpcam", "show_fps", "fullscreen"]

signal closed


func _init() -> void:
	theme = UI.theme()
	set_anchors_preset(Control.PRESET_CENTER)
	position = Vector2(-125, -122)
	custom_minimum_size = Vector2(250, 0)
	add_theme_constant_override("separation", 3)
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	var title := UI.label(self, 20, "cond", UI.TEXT, 1, HORIZONTAL_ALIGNMENT_CENTER)
	title.text = tr("EINSTELLUNGEN")
	for k in KEYS:
		_row(k)
	var back_b := Button.new()
	back_b.text = tr("< Zurück").to_upper()
	back_b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	back_b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back_b.pressed.connect(back)
	add_child(back_b)
	UI.menu_fx(back_b)
	var note := UI.label(self, 7, "wide", UI.DIM, 0, HORIZONTAL_ALIGNMENT_LEFT)
	note.text = tr("Grafik, V-Sync und FPS-Limit: in der Garage unter Einstellungen.")


func open() -> void:
	for c in get_children():
		if c.has_meta("setting"):
			_text(c)
	visible = true
	(get_child(1) as Button).grab_focus()


func back() -> void:
	if not visible:
		return
	Sfx.ui("back")
	visible = false
	closed.emit()


func _row(k: String) -> void:
	var b := Button.new()
	b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.set_meta("setting", k)
	var val := Label.new()
	val.name = "Wert"
	val.label_settings = UI.text_settings(10, "bold", UI.DIM)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	val.set_anchors_preset(Control.PRESET_FULL_RECT)
	val.offset_right = -10.0
	val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(val)
	add_child(b)
	UI.menu_fx(b)
	var change := func(dir: int):
		if k == "fullscreen":
			GameState.toggle_fullscreen()
		else:
			GameState.cycle_setting(k, dir)
		Sfx.ui("change")
		_text(b)
	b.pressed.connect(change.bind(1))
	b.gui_input.connect(func(ev: InputEvent):
		if ev.is_action_pressed("ui_left"):
			change.call(-1)
			b.accept_event()
		elif ev.is_action_pressed("ui_right"):
			change.call(1)
			b.accept_event())
	b.focus_entered.connect(func(): (b.get_node("Wert") as Label).label_settings = UI.text_settings(10, "bold", UI.TEXT))
	b.focus_exited.connect(func(): (b.get_node("Wert") as Label).label_settings = UI.text_settings(10, "bold", UI.DIM))


## "Musik: 80 %" -> links MUSIK, rechts 80 %
func _text(b: Button) -> void:
	var full := GameState.setting_text(b.get_meta("setting"))
	var i := full.rfind(": ")
	b.text = full.substr(0, i).to_upper() if i >= 0 else full.to_upper()
	(b.get_node("Wert") as Label).text = full.substr(i + 2).to_upper() if i >= 0 else ""
