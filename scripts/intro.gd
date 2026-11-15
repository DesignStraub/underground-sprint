extends Control
## Studio-Intro: ONE HUMANITY Logo blendet ruhig ein und wächst dabei ein wenig, kurzer Sound, dann Garage.
## Seit 2.35 ohne Wackeln und Blitz (wirkte aufgesetzt), nur ein leiser Schein hinter dem Logo.
## Jede Taste / Klick / Gamepad-Knopf überspringt.

const LOGO := preload("res://assets/one_humanity_logo.svg")
const SOUND_PATH := "res://assets/intro_sound.mp3"  # optional, nicht im Git-Repo (Pixabay-Lizenz)
const GLOW := preload("res://shaders/logo_glow.gdshader")
const UI := preload("res://scripts/ui_style.gd")
const NEXT_SCENE := "res://scenes/garage.tscn"
const DURATION := 3.6

var logo: TextureRect
var halo: TextureRect
var title: Label
var fade: ColorRect
var mat: ShaderMaterial
var _t := 0.0
var _leaving := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UI.INK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Leiser kühler Schein hinter dem Logo
	var grad := Gradient.new()
	grad.set_color(0, Color(0.55, 0.7, 0.9, 0.16))
	grad.set_color(1, Color(0.55, 0.7, 0.9, 0.0))
	grad.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CUBIC
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
	halo.size = Vector2(380, 380)
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
	mat.set_shader_parameter("glow_color", Color(0.55, 0.7, 0.95))
	logo.material = mat
	add_child(logo)

	title = Label.new()
	title.text = "ONE HUMANITY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.label_settings = UI.text_settings(9, "wide", UI.TEXT, 4)
	title.label_settings.shadow_color = Color(0, 0, 0, 0)
	title.size = Vector2(400, 24)
	title.modulate.a = 0.0
	add_child(title)

	fade = ColorRect.new()
	fade.color = Color(UI.INK.r, UI.INK.g, UI.INK.b, 1)
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
	# ruhiges Einblenden: das Logo wächst in gut einer Sekunde weich auf seine Größe und zieht dann kaum merklich weiter
	var k := 1.0 - pow(1.0 - clampf(_t / 1.2, 0.0, 1.0), 3.0)
	var s := lerpf(0.86, 0.9, k) + _t * 0.012
	logo.scale = Vector2(s, s)
	logo.modulate.a = k
	logo.position = center - logo.size / 2.0 + Vector2(0, -16)
	halo.position = center - halo.size / 2.0 + Vector2(0, -16)
	halo.scale = Vector2(s, s)
	halo.modulate.a = k
	mat.set_shader_parameter("glow", 0.35 * k)
	title.position = center + Vector2(-200, 80)
	title.modulate.a = clampf((_t - 0.8) / 0.6, 0.0, 1.0)
	# Ein- und Ausblenden
	if _t < 0.25:
		fade.color.a = 1.0 - _t / 0.25
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
