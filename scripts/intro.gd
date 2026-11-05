extends Control
## Studio-Intro: ONE HUMANITY Logo zoomt mit Wackeln herein, kurzer Sound, dann Garage.
## Jede Taste / Klick / Gamepad-Knopf überspringt.

const LOGO := preload("res://assets/one_humanity_logo.svg")
const SOUND_PATH := "res://assets/intro_sound.mp3"  # optional, nicht im Git-Repo (Pixabay-Lizenz)
const GLOW := preload("res://shaders/logo_glow.gdshader")
const NEXT_SCENE := "res://scenes/garage.tscn"
const DURATION := 3.6

var logo: TextureRect
var halo: TextureRect
var title: Label
var flash: ColorRect
var fade: ColorRect
var mat: ShaderMaterial
var _t := 0.0
var _leaving := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.0, 0.0, 0.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Weicher blauer Schein hinter dem Logo
	var grad := Gradient.new()
	grad.set_color(0, Color(0.15, 0.6, 1.0, 0.55))
	grad.set_color(1, Color(0.15, 0.6, 1.0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 256
	gt.height = 256
	halo = TextureRect.new()
	halo.texture = gt
	halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	halo.size = Vector2(340, 340)
	halo.pivot_offset = halo.size / 2.0
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	halo.material = add
	add_child(halo)

	logo = TextureRect.new()
	logo.texture = LOGO
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	logo.size = Vector2(190, 190)
	logo.pivot_offset = logo.size / 2.0
	mat = ShaderMaterial.new()
	mat.shader = GLOW
	logo.material = mat
	add_child(logo)

	title = Label.new()
	title.text = "O N E   H U M A N I T Y"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var ls := LabelSettings.new()
	ls.font_size = 16
	ls.font_color = Color(0.92, 0.95, 1.0)
	ls.shadow_color = Color(0.1, 0.6, 1.0, 0.6)
	ls.shadow_size = 6
	title.label_settings = ls
	title.size = Vector2(400, 24)
	title.modulate.a = 0.0
	add_child(title)

	flash = ColorRect.new()
	flash.color = Color(0.7, 0.9, 1.0, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	fade = ColorRect.new()
	fade.color = Color(0, 0, 0, 1)
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fade)

	if ResourceLoader.exists(SOUND_PATH):
		var snd := AudioStreamPlayer.new()
		snd.stream = load(SOUND_PATH)
		snd.volume_db = -2.0
		add_child(snd)
		snd.play()
	# Musik erst nach dem Intro
	Music.set_paused(true)


func _process(dt: float) -> void:
	_t += dt
	var center := get_viewport_rect().size / 2.0
	# Zoom: schneller Einschlag, dann langsames Weiterziehen
	var hit := 1.0 - pow(1.0 - clampf(_t / 0.35, 0.0, 1.0), 3.0)
	var s := lerpf(0.35, 0.92, hit) + _t * 0.035
	logo.scale = Vector2(s, s)
	# Wackeln: kräftig beim Einschlag, dann ein leichtes Nachzittern
	var shake := 9.0 * exp(-_t * 5.0) + 0.8
	var off := Vector2(randf_range(-shake, shake), randf_range(-shake, shake))
	logo.position = center - logo.size / 2.0 + Vector2(0, -16) + off
	logo.rotation = randf_range(-1.0, 1.0) * 0.02 * exp(-_t * 4.0)
	halo.position = center - halo.size / 2.0 + Vector2(0, -16) + off * 0.5
	halo.scale = Vector2(s, s) * (1.0 + 0.04 * sin(_t * 6.0))
	halo.modulate.a = 0.55 + 0.9 * exp(-_t * 2.5)
	mat.set_shader_parameter("glow", 0.6 + 0.6 * exp(-_t * 3.0) + 0.1 * sin(_t * 9.0))
	title.position = center + Vector2(-200, 82) + off * 0.4
	title.modulate.a = clampf((_t - 0.7) / 0.5, 0.0, 1.0)
	flash.color.a = 0.35 * exp(-_t * 10.0) if _t > 0.05 else 0.0
	# Ein- und Ausblenden
	if _t < 0.12:
		fade.color.a = 1.0 - _t / 0.12
	elif _t > DURATION - 0.6:
		fade.color.a = clampf((_t - (DURATION - 0.6)) / 0.6, 0.0, 1.0)
	else:
		fade.color.a = 0.0
	if _t >= DURATION:
		_finish()


func _input(event: InputEvent) -> void:
	if _t < 0.3:
		return
	if (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton) and event.is_pressed():
		_finish()


func _finish() -> void:
	if _leaving:
		return
	_leaving = true
	Music.set_paused(false)
	get_tree().change_scene_to_file(NEXT_SCENE)
